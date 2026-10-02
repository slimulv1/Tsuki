#!/usr/bin/env bash
# Test cho slock — chương trình KHÓA MÀN HÌNH, gắn vào Super+Delete.
#
# KHÔNG có test nào trong repo chạm tới slock trước đây: `slock`, `imgdec` và
# `netpanel` đều chưa từng được build từ nguồn. Đây là lỗ hổng kiểm thử.
#
# LỖI ĐÃ XẢY RA THẬT trên máy này: slock/config.def.h khai
#     static const char *group = "nogroup";
# "nogroup" là quy ước Debian/Ubuntu. Arch/CachyOS KHÔNG có group đó — gid
# 65534 trên Arch mang tên "nobody".
#
# Hậu quả: slock chết ở slock.c:379 `getgrnam(group)` TRƯỚC khi tới
# XGrabPointer (dòng 308), nên KHÔNG khoá được gì. Đo trên binary đã cài ở
# /usr/local/bin/slock (setuid 4755 — quyền đúng):
#     $ /usr/local/bin/slock
#     slock: getgrnam nogroup: group entry not found
#     rc = 1
# Tức Super+Delete im lặng không làm gì.
#
# Cách test: build slock thật từ nguồn rồi CHẠY, và kiểm `install.sh check`
# có bắt được cấu hình sai không.
set -u
R=/home/frost-auslese/tsuki
P=0; F=0
ok()  { printf '  PASS  %s\n' "$*"; P=$((P + 1)); }
bad() {
    _m1=$1; shift
    printf '  FAIL  %s\n        %s\n' "$_m1" "$*"
    F=$((F + 1))
}
T=$(mktemp -d)
cleanup() { rm -rf "$T"; }
trap cleanup EXIT INT TERM

if [ ! -f "$R/slock/config.def.h" ] || [ ! -f "$R/slock/slock.c" ]; then
    printf '  --   bỏ qua: không thấy thư mục slock\n'
    printf '\n  %d PASS, %d FAIL\n' "$P" "$F"
    exit 0
fi

# --- S1: user và group trong config.def.h phải TỒN TẠI trên máy ----------
# Đây là điều kiện để slock chạy được; đo trực tiếp bằng getent.
sl_g=$(sed -n 's/^static const char \*group *= *"\([^"]*\)".*/\1/p' "$R/slock/config.def.h" 2>/dev/null)
sl_u=$(sed -n 's/^static const char \*user *= *"\([^"]*\)".*/\1/p' "$R/slock/config.def.h" 2>/dev/null)
if [ -z "$sl_g" ] || [ -z "$sl_u" ]; then
    bad "S1 đọc được user/group từ slock/config.def.h" "user='$sl_u' group='$sl_g'"
else
    ok "S1 đọc được slock config: user='$sl_u' group='$sl_g'"
    if getent group "$sl_g" >/dev/null 2>&1; then
        ok "S1b group '$sl_g' tồn tại trên máy này (getent group)"
    else
        bad "S1b group '$sl_g' KHÔNG tồn tại" \
            "slock chết ở slock.c:379 getgrnam trước khi khoá màn hình — Super+Delete vô hiệu"
    fi
    if getent passwd "$sl_u" >/dev/null 2>&1; then
        ok "S1c user '$sl_u' tồn tại trên máy này (getent passwd)"
    else
        bad "S1c user '$sl_u' KHÔNG tồn tại" "slock sẽ chết ở getpwnam"
    fi
fi

# --- S2: cấu hình config.h (file build) phải KHỚP config.def.h -------------
# slock/config.h là file thật được biên dịch. Nếu ai sửa def nhưng quên sửa
# config.h thì build vẫn dùng giá trị cũ — đúng kiểu lỗi mà dwmwal.sh từng
# gây với themes/wal.h.
cfg_g=$(sed -n 's/^static const char \*group *= *"\([^"]*\)".*/\1/p' "$R/slock/config.h" 2>/dev/null)
if [ -z "$cfg_g" ]; then
    bad "S2 đọc được group từ slock/config.h" "file build không đọc được"
elif [ "$cfg_g" = "$sl_g" ]; then
    ok "S2 slock/config.h khớp config.def.h (group='$cfg_g')"
else
    bad "S2 slock/config.h KHÔNG khớp config.def.h" \
        "config.h='$cfg_g' nhưng def='$sl_g' — build sẽ dùng giá trị cũ"
fi

# --- S3: build thật rồi CHẠY thật ------------------------------------------
# Không build rồi đoán. slock chạy thật sẽ khoá màn hình, nên chạy dưới
# `timeout` và đọc stderr — lỗi getgrnam xuất hiện ở stderr trước khi nó khoá.
if ! command -v make >/dev/null 2>&1 || ! command -v cc >/dev/null 2>&1; then
    printf '  --   bỏ qua S3: thiếu make hoặc cc\n'
elif [ ! -d "$R/slock" ]; then
    printf '  --   bỏ qua S3: không có thư mục\n'
else
    # Build vào bản sao để KHÔNG đụng binary người dùng đang có.
    rm -rf "$T/s"; cp -a "$R/slock" "$T/s" 2>/dev/null
    if ( cd "$T/s" && make clean >/dev/null 2>&1 && make ) >"$T/build.log" 2>&1; then
        ok "S3 build slock từ nguồn thành công"
        out=$( cd "$T" && timeout 6 "$T/s/slock" 2>&1 )
        if printf '%s' "$out" | grep -q 'getgrnam'; then
            bad "S3b slock vẫn báo getgrnam" "$(printf '%s' "$out" | head -1)"
        else
            ok "S3b slock KHÔNG báo lỗi getgrnam khi chạy thật"
        fi
        # Lỗi OOM killer là do bản test KHÔNG setuid, không phải lỗi cấu hình —
        # nên không tính là FAIL, nhưng phải nói rõ.
        if printf '%s' "$out" | grep -q 'OOM killer'; then
            printf '  --   (đã tới bước OOM: bản test không setuid, /proc/self/oom_score_adj\n'
            printf '         cần quyền root — đây là bước SAU getgrnam nên user/group đã đúng)\n'
        fi
    else
        bad "S3 build slock thất bại" "xem $T/build.log"
        grep -m3 -i error "$T/build.log" | sed 's/^/        | /'
    fi
fi

# --- S4: install.sh check phải BẮT được cấu hình sai --------------------
# Nếu chỉ sửa file thì máy khác với config cũ vẫn hỏng im lặng. Cần có
# kiểm tra lúc cài.
if grep -q 'getent group' "$R/install.sh" 2>/dev/null; then
    ok "S4 install.sh có kiểm user/group của slock bằng getent"
else
    bad "S4 install.sh KHÔNG kiểm slock user/group" \
        "cấu hình sai sẽ chỉ lộ ra khi bấm phím, lúc đó desktop đang mở"
fi

# Chứng minh S4 bắt được: chạy check với group sai.
if grep -q 'getent group' "$R/install.sh" 2>/dev/null; then
    _d="$T/repo"; rm -rf "$_d"; cp -a "$R" "$_d" 2>/dev/null
    if [ -d "$_d" ]; then
        sed -i 's|^static const char \*group = "[^"]*";|static const char *group = "nogroup-khong-ton-tai";|' \
            "$_d/slock/config.def.h"
        _out=$(cd "$_d" && timeout 120 bash install.sh check 2>&1 || true)
        if printf '%s' "$_out" | grep -qi 'slock'; then
            ok "S4b install.sh check BÁO khi group sai"
        else
            bad "S4b install.sh check im lặng với group sai" "không bắt được lỗi thật"
        fi
        rm -rf "$_d"
    fi
fi

# --- S5: Makefile phải giữ bit setuid khi cài -----------------------------
# setgid/setuid là thứ làm cho bước OOM killer chạy được; thiếu nó thì
# Super+Delete vẫn chết (ở bước sau).
if grep -qE 'chmod (u\+s|g\+s|4[0-9]{3}|2[0-9]{3})' "$R/slock/Makefile" 2>/dev/null; then
    ok "S5 slock/Makefile đặt bit setuid/sgid khi install"
else
    bad "S5 slock/Makefile không đặt bit setuid/sgid" \
        "bước OOM killer sẽ chết dù đã qua getgrnam"
fi

printf '\n  %d PASS, %d FAIL\n' "$P" "$F"
[ "$F" -eq 0 ]

#!/usr/bin/env bash
# Test cho chuỗi gắn USB: cắm USB → nhận trong Thunar.
#
# TRIỆU CHỨNG: cắm USB vào mà hệ thống không nhận, Thunar không hiện.
#
# ĐO TẦNG PHẦN CỨNG — KHÔNG HỎNG. Khi USB đang cắm:
#     lsblk -d -o NAME,TRAN   ->  sdb  usb  29.8G  MassStorageClass
#     /dev/sdb1  exfat  Ventoy
#     /dev/sdb2  vfat   VTOYEFI
#     kernel: modinfo exfat / vfat / ntfs3 — cả ba module đều có
# Nên vấn đề KHÔNG ở kernel, KHÔNG ở driver hệ file, KHÔNG ở phân vùng.
#
# ĐO TẦNG PHẦN MỀM:
#     gio mount -l                    -> rỗng
#     busctl --system list|grep udisks -> 0
#     /media, /run/media/1000         -> rỗng, không có mount point nào
#     pacman -Qi udisks2, gvfs        -> chưa cài
#
# NGUYÊN NHÂN. `udisks2` là daemon D-Bus lo việc gắn/tháo ổ. Thunar lấy danh
# sách ổ qua GVolumeMonitor của GLib (thunar-device-monitor.c:218
# `g_volume_monitor_get()`); trên Linux đó là GUnixVolumeMonitor, nó hỏi
# udisks2 qua SYSTEM bus. Không có udisks2 thì ổ cắm vào không ai biết, và
# ổ chưa cắm không có gì để gắn. `gio mount -l` rỗng là hệ quả trực tiếp.
#
# `gvfs` là phụ thuộc CỨNG của udisks2 ngược lại — `pacman -Si gvfs` liệt kê
# `udisks2` trong Depends On — nên chỉ cần đưa `gvfs` vào PKG_SESSION là đủ,
# không cần liệt kê udisks2. Bản đầu bản test này định thêm `udisks2` riêng;
# đo lại thấy thừa.
#
# Test trích NGUYÊN VĂN mảng gói. Chỉ đọc, không gắn ổ, không cài gì.
set -u
R=/home/frost-auslese/tsuki
P=0; F=0
ok()  { printf '  PASS  %s\n' "$*"; P=$((P + 1)); }
bad() { printf '  FAIL  %s\n        %s\n' "$*"; F=$((F + 1)); }
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT

sed -n '/^readonly PKG_SESSION=(/,/^)/p' "$R/install.sh" > "$T/sess.sh"
[ -s "$T/sess.sh" ] || { printf 'FAIL: không trích được PKG_SESSION\n'; exit 1; }
{ cat "$T/sess.sh"; echo 'printf "%s\n" "${PKG_SESSION[@]}"'; } > "$T/dump.sh"
mapfile -t SESS < <(bash "$T/dump.sh" 2>/dev/null)
sess_txt=$(cat "$T/sess.sh")

# --- C1: gvfs phải nằm trong PKG_SESSION ------------------------------------
if printf '%s\n' "${SESS[@]}" | grep -qx gvfs; then
    ok "C1 PKG_SESSION có gvfs"
else
    bad "C1 PKG_SESSION thiếu gvfs" "thùng rác, USB, MTP đều cần nó"
fi

# --- C2: gvfs phải KÉO ĐƯỢC udisks2 -----------------------------------------
# Đây là mắt xích quyết định. Nếu udisks2 không phải phụ thuộc của gvfs thì
# phải liệt kê riêng; nếu KHÔNG phải (đo được: nó là) thì thêm riêng là
# ghi trùng. Ca này hỏi pacman chứ không tin comment của tôi.
if pacman -Si gvfs >/dev/null 2>&1; then
    if pacman -Si gvfs 2>/dev/null | sed -n 's/^Depends On *: *//p' \
        | tr ' ' '\n' | grep -qx udisks2; then
        ok "C2 gvfs phụ thuộc cứng udisks2 (đo từ pacman) — đủ, không cần liệt kê riêng"
    else
        bad "C2 gvfs KHÔNG phụ thuộc udisks2" \
            "phải thêm udisks2 vào PKG_SESSION, nếu không USB vẫn không được gắn"
    fi
else
    printf '  --   bỏ qua C2: không có pacman\n'
fi

# --- C3: KHÔNG liệt kê udisks2 trùng lặp ------------------------------------
# Ghi trùng không làm hỏng gì, nhưng làm người đọc tưởng phải thêm tay. Và
# `install_pkgs` in danh sách — thêm tên trùng sẽ thấy nó hai lần.
if printf '%s\n' "${SESS[@]}" | grep -qx udisks2; then
    bad "C3 liệt kê udisks2 trong khi gvfs đã kéo theo" "ghi trùng, và danh sách sẽ in tên này hai lần"
else
    ok "C3 không liệt kê udisks2 trùng lặp (gvfs đã kéo theo)"
fi

# --- C4: chú thích phải giải thích đúng cơ chế ----------------------------
# Bản đầu tôi ghi "gvfs — thùng rác, đĩa USB, máy tép MTP/SMB" và hết. Người
# đọc không hiểu vì sao thiếu gì. Và tôi có một dòng comment nói về
# `gvfs-mtp` trong khi KHÔNG cài gói đó — tài liệu nói dối.
if printf '%s' "$sess_txt" | grep -qF 'phụ thuộc CỨNG của nó'; then
    ok "C4 chú thích nói rõ gvfs kéo udisks2 và vì sao"
else
    bad "C4 chú thích không giải thích cơ chế udisks2" \
        "người đọc thấy 'đĩa USB' mà không biết thiếu gì"
fi
# Bất biến: gói được NHẮC tên trong chú thích thì hoặc phải có trong mảng, hoặc
# phải được nói rõ là không cài. Bản đầu chỉ kiểm "có nhắc mà không có trong
# mảng" thì đỏ, nhưng comment của tôi viết "KHÔNG thêm gvfs-mtp" — tức nói rõ
# không cài, hoàn toàn trung thực. Ca đỏ vì lỗi test.
# Nên: nhắc mà không có trong mảng thì phải kèm chữ "KHÔNG thêm"/"không cài".
#
# PHẢI GỘP DÒNG COMMENT trước khi so. Câu của tôi xuống dòng:
#     #     KHÔNG thêm `gvfs-mtp` (157 KiB, cho điện thoại): cần thì cài riêng
#     #     phải để sẵn cho mọi người.
# nên "KHÔNG thêm" nằm ở dòng trước, còn "gvfs-mtp" ở dòng sau — so từng dòng
# thì không dòng nào chứa cả hai. Đây là lần thứ ba tôi vấp chuyện xong dòng
# (khoá pacman.conf, trap trong root_sh), nên nay dùng chung một cách gộp.
sess_flat=$(printf '%s\n' "$sess_txt" | tr '\n' ' ')
if printf '%s\n' "${SESS[@]}" | grep -qx gvfs-mtp; then
    ok "C4b gvfs-mtp có trong mảng, chú thích khớp"
elif ! printf '%s' "$sess_flat" | grep -qF 'gvfs-mtp'; then
    ok "C4b chú thích không nhắc gói nào ngoài mảng"
elif printf '%s' "$sess_flat" | grep -qE 'KHÔNG (thêm|cài)[^.]{0,40}gvfs-mtp'; then
    ok "C4b nhắc gvfs-mtp nhưng nói rõ KHÔNG cài — trung thực, không gây hiểu nhầm"
else
    bad "C4b nhắc gvfs-mtp mà không nói rõ có cài hay không" \
        "đọc tưởng đã cài sẵn — tài liệu nói dối"
fi

# --- C5: tầng phần cứng phải ổn — nếu không thì cài gói cũng vô ích --------
# Nếu máy test không có USB cắm thì bỏ qua: ca này kiểm môi trường, không
# kiểm code. Nhưng nếu CÓ USB mà kernel không có module thì đó là nguyên nhân
# khác và phải báo.
usb=$(lsblk -d -o NAME,TRAN 2>/dev/null | awk '$2=="usb"{print $1; exit}')
if [ -z "$usb" ]; then
    printf '  --   bỏ qua C5: không có USB nào đang cắm\n'
else
    ok "C5 USB đang cắm và nhận ở tầng phần cứng: $usb (nguyên nhân nằm ở tầng mềm)"
    miss=""
    for fs in exfat vfat ntfs3; do
        modinfo "$fs" >/dev/null 2>&1 || miss+=" $fs"
    done
    if [ -z "$miss" ]; then
        ok "C5b kernel có module exfat/vfat/ntfs3 (không thiếu driver hệ file)"
    else
        bad "C5b kernel thiếu module$miss" "cài thêm gói cũng không gắn được"
    fi
fi

# --- C6: chuỗi kích hoạt phải chạy sau khi deps cài xong ------------------
# `all` gọi cmd_session ở CUỐI, sau cmd_deps — nên gvfs chắc chắn đã có trước
# khi người dùng dùng Thunar. Kiểm để không ai vô tình chuyển cmd_session lên
# đầu.
main_fn=$(sed -n '/^main() {/,/^}/p' "$R/install.sh")
all_code=$(printf '%s\n' "$main_fn" |
           sed -n '/^        all)/,/^            ;;/p' |
           grep -vE '^[[:space:]]*#')
i_deps=$(printf '%s\n' "$all_code" | grep -n 'cmd_deps' | head -1 | cut -d: -f1)
i_sess=$(printf '%s\n' "$all_code" | grep -n 'cmd_session' | head -1 | cut -d: -f1)
if [ -z "$i_deps" ] || [ -z "$i_sess" ]; then
    bad "C6 không tìm thấy cmd_deps/cmd_session trong all" "có thể cấu trúc đã đổi"
elif [ "$i_sess" -gt "$i_deps" ]; then
    ok "C6 cmd_session chạy sau cmd_deps (gvfs chắc chắn đã cài xong)"
else
    bad "C6 cmd_session chạy TRƯỚC cmd_deps" "Thunar sẽ mở ra khi gvfs chưa có"
fi

# --- C7: tài liệu phải nói về USB -------------------------------------------
# PACKAGES.md liệt kê từng gói; gvfs mà không giải thích tác dụng thì đọc
# không hiểu vì sao cần.
doc="$R/PACKAGES.md"
if grep -q '`gvfs`' "$doc" 2>/dev/null; then
    if grep -qi 'udisks' "$doc"; then
        ok "C7 PACKAGES.md giải thích gvfs kéo udisks2 (USB, thùng rác)"
    else
        bad "C7 PACKAGES.md có gvfs nhưng không nhắc udisks2" \
            "đọc không biết cắm USB cần cái gì"
    fi
else
    bad "C7 PACKAGES.md thiếu gvfs" "tài liệu phải khớp install.sh"
fi

printf '\n  %d PASS, %d FAIL\n' "$P" "$F"
[ "$F" -eq 0 ]

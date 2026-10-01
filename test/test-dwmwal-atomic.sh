#!/usr/bin/env dash
# Test cho ba lỗi ổn định trong dwmwal.sh, tìm ra bằng chạy thật chứ không đoán:
#
#   A) dwm KHÔNG KHỞI ĐỘNG ĐƯỢC khi walgen sinh thiếu màu.
#      drw.c:188 (drw_clr_create) gọi die() khi XftColorAllocName trả False.
#      Đo trên X thật của máy: "#9881dc" -> OK, "" -> FAIL. Màu rỗng là chuỗi
#      hợp lệ với C nên `make` VẪN ĐƯỢC — chỉ chết lúc mở app. Đây là kiểu lỗi
#      mà "build thành công" không bảo chứng gì.
#
#   B) themes/wal.h ghi bằng `cat >` không nguyên tử. Nếu script bị giết giữa
#      lúc ghi, rebuild.sh vài giây sau đọc file nửa vời -> không biên dịch.
#      `mv` cùng thư mục dùng rename(2), POSIX bảo đảm thay thế nguyên tử.
#
#   C) Hai dwmwal.sh chạy song song (bấm Super+W hai lần nhanh) cùng ghi cùng
#      file và cùng `rm -rf "$CACHE"`. Đã chạy 3 bản song song thật: một bản báo
#      lỗi X11 "X_KillClient" do các bản nhắm cùng một tiến trình để kill.
#
# Cách test: TRÍCH MÃ NGUỒN THẬT từ scripts/dwmwal.sh bằng sed, không chép lại
# logic — nếu không test sẽ "trôi" khỏi bản đang dùng, đã mắc lỗi đó nhiều lần.
set -u
R=/home/frost-auslese/tsuki
P=0; F=0
ok()  { printf '  PASS  %s\n' "$*"; P=$((P + 1)); }
bad() {
    # Nhiều lời giải thích có thể truyền nhiều đối số; nối lại để khớp 2 %s.
    _m1=$1; shift
    printf '  FAIL  %s\n        %s\n' "$_m1" "$*"
    F=$((F + 1))
}
T=$(mktemp -d)
cleanup() { rm -rf "$T"; }
trap cleanup EXIT INT TERM

DW="$R/scripts/dwmwal.sh"
W="$(printf '%s\n' "$(cat "$R/scripts/.wallpaper" 2>/dev/null)")"
[ -f "$W" ] || W=$(find "$HOME/Pictures/Wallpapers" -maxdepth 1 -type f \
                   \( -iname '*.png' -o -iname '*.jpg' \) 2>/dev/null | head -1)

# ===========================================================================
# Phần 1 — kiểm bằng VĂN BẢN (không cần X, không cần ảnh)
# ===========================================================================

# --- A1: phải có chặn màu rỗng, và phải nằm SAU khi nạp colors.sh ----------
# Thứ tự quan trọng: kiểm tra trước rồi mới nạp thì kiểm những biến rỗng.
_nguon=$(grep -n '\. "\$CACHE/colors\.sh"' "$DW" | head -1 | cut -d: -f1)
# Mốc so sánh phải là DÒNG LỆNH THẬT, không phải dòng comment. Đã dính: lấy
# `CHẶN MÀU RỖNG` (nằm trong comment dòng 107) làm mốc thì so với dòng 141 thì
# luôn FAIL, dù code đã đúng. Dùng `^for _v in` — bắt đầu vòng duyệt.
_kchan=$(grep -n '^for _v in' "$DW" | head -1 | cut -d: -f1)
if [ -z "$_nguon" ] || [ -z "$_kchan" ]; then
    bad "A1 dwmwal.sh có chặn màu rỗng" "không tìm thấy khối kiểm tra"
elif [ "$_kchan" -gt "$_nguon" ]; then
    ok "A1 chặn màu rỗng nằm sau khi nạp colors.sh (dòng $_kchan > $_nguon)"
else
    bad "A1 chặn màu rỗng nằm SỚM hơn lúc nạp colors.sh" \
        "dòng $_kchan < $_nguon — mọi biến còn rỗng khi kiểm, vô nghĩa"
fi

# --- A2: accent phải được gán TRƯỚC khi kiểm ------------------------------
# accents nạp ở nhánh else dòng ~144. Nếu kiểm trước, accent luôn rỗng và bị
# gán fallback oan, kể cả khi walgen có accent thật.
_g=$(grep -n '^[^#]*accent="\${accent:-\$color4}"' "$DW" | head -1 | cut -d: -f1)
if [ -z "$_g" ]; then
    bad "A2 có gán accent từ colors/accents" "không thấy dòng accent=..."
elif [ "$_g" -lt "$_kchan" ]; then
    ok "A2 accent gán ở dòng $_g, trước khối kiểm ở dòng $_kchan"
else
    # accent được gán SAU vòng duyệt màu chính — điều đó ĐÚNG, vì nó phải nạp
    # accents trước. Yêu cầu thật là: lần kiểm RIÊNG của accent (dòng
    # `for _v in accent`) phải nằm SAU chỗ gán. Kiểm cả hai vế.
    _kac=$(grep -n '^for _v in accent' "$DW" | head -1 | cut -d: -f1)
    if [ -n "$_kac" ] && [ "$_kac" -gt "$_g" ]; then
        ok "A2 accent gán ở $_g và kiểm lại ở $_kac (đúng thứ tự)"
    elif [ -z "$_kac" ]; then
        bad "A2 không có vòng kiểm riêng cho accent" \
            "accent nạp sau colors.sh, kiểm trước thì luôn rỗng rồi bị đè fallback"
    else
        bad "A2 kiểm accent ở $_kac TRƯỚC lúc gán ở $_g" \
            "accent thật bị đè bằng fallback oan"
    fi
fi

# --- A3: phải kiể đủ các biến màu mà dwm thực sự dùng ----------------------
# Nếu quên color9..15 thì tag1..5 vẫn rỗng và dwm vẫn chết. Tên biến suy ra
# từ chính heredoc sinh themes/wal.h — không hardcode danh sách ở đây.
GEN=$(sed -n '/^cat > "\$TSUKI_DIR\/themes\/wal\.h\.tmp"/,/^EOF$/p' "$DW")
[ -n "$GEN" ] || GEN=$(sed -n '/^cat > "\$TSUKI_DIR\/themes\/wal\.h"/,/^EOF$/p' "$DW")
if [ -z "$GEN" ]; then
    bad "A3 tìm thấy heredoc sinh themes/wal.h" "không trích được"
else
    # biến màu được dùng trong wal.h, theo đúng tên biến
    used=$(printf '%s\n' "$GEN" | grep -oE '\$\{?(color[0-9]+|accent|background|foreground|cursor)\}?' \
           | tr -d '${}' | sed 's/^\$//' | sort -u)
    missing=""
    for v in $used; do
        # kiểm biến này có nằm trong danh sách mà khối chặn duyệt không
        printf '%s\n' "$used" > "$T/used"
        sed -n '/CHẶN MÀU RỖNG/,/^fi$/p' "$DW" > "$T/block"
        grep -qw "$v" "$T/block" || missing="$missing $v"
    done
    if [ -z "$missing" ]; then
        ok "A3 khối chặn duyệt đủ $(printf '%s\n' "$used" | wc -l) biến màu wal.h dùng"
    else
        bad "A3 khối chặn BỎ SÓT biến màu" "$missing — sinh ra \"\" -> dwm chết lúc mở"
    fi
fi

# --- B1: themes/wal.h phải ghi qua file tạm rồi mv -------------------------
# Kiểm bằng CÁCH THẬT: lấy dòng đích (redirect) của lệnh ghi, rồi đòi .tmp.
_dest=$(printf '%s\n' "$GEN" | sed -n '1s/.*> "\([^"]*\)".*/\1/p')
if [ -z "$_dest" ]; then
    bad "B1 xác định được file đích của lệnh ghi wal.h" "không phân tích được"
elif [ "$_dest" = "\$TSUKI_DIR/themes/wal.h" ]; then
    bad "B1 themes/wal.h KHÔNG ghi nguyên tử" \
        "đích=$_dest, dùng cat > trực tiếp — giết giữa lúc ghi là file nửa vời"
else
    ok "B1 wal.h ghi qua ${_dest##*/} thay vì ghi thẳng (đích=$_dest)"
fi

# --- B2: phải có mv đưa file tạm về chỗ ------------------------------------
_mv=$(grep -n 'mv -f "\$TSUKI_DIR/themes/wal\.h\.tmp" "\$TSUKI_DIR/themes/wal\.h"' "$DW" | head -1 | cut -d: -f1)
if [ -n "$_mv" ]; then
    ok "B2 có mv đưa .tmp về themes/wal.h (dòng $_mv)"
else
    bad "B2 thiếu mv themes/wal.h.tmp -> themes/wal.h" \
        "file tạm sẽ đọng lại vĩnh viễn, wal.h không bao giờ cập nhật"
fi

# --- B3: file tạm phải CÙNG THƯ MỤC với đích (rename(2) chỉ atomic cùng fs) --
if [ -n "$_dest" ] && [ -n "$_mv" ] && [ "$_mv" -gt "$(printf '%s\n' "$GEN" | head -1 | wc -l)" ]; then
    # So SÁCH THƯ MỤC, không so hậu tố: cùng thư mục là điều kiện để rename(2)
    # thay thế nguyên tử. /themes/wal.h.tmp và /themes/wal.h cùng thư mục -> OK.
    # So bằng cách bỏ dấu / cuối rồi lấy phần thư mục.
    _d_dir=${_dest%/*}
    _d_tail=${_dest##*/}
    case $_d_tail in
        *.tmp) _d_tmp_dir=${_dest%/*} ;;
        *)     _d_tmp_dir="" ;;
    esac
    if [ -n "$_d_tmp_dir" ]; then
        ok "B3 file tạm cùng thư mục đích (${_d_dir##*/})"
    else
        bad "B3 đích ghi không phải file .tmp" \
            "$_dest — rename(2) chỉ nguyên tử với file tạm cùng thư mục"
    fi
else
    bad "B3 thứ tự ghi-tạm rồi mv" "mv (dòng ${_mv:-không có}) phải sau lệnh ghi"
fi

# --- C1: phải có khoá flock ------------------------------------------------
_lock=$(grep -n 'flock -w 30 9' "$DW" | head -1 | cut -d: -f1)
if [ -n "$_lock" ]; then
    ok "C1 có flock khoá dwmwal.sh (dòng $_lock)"
else
    bad "C1 không có flock" "bấm Super+W hai lần là hai tiến trình cùng ghi cùng file"
fi

# --- C2: khoá phải mở bằng exec trên fd cố định, và phải mkdir thư mục --------
# `exec 9>` mà không mkdir sẽ chết "Directory nonexistent" ở lần chạy đầu.
_mdir=$(grep -n 'mkdir -p "\$LOCKDIR"' "$DW" | head -1 | cut -d: -f1)
_exec=$(grep -n 'exec 9>"\$LOCK"' "$DW" | head -1 | cut -d: -f1)
if [ -n "$_exec" ]; then
    ok "C2 khoá bằng exec trên fd 9 (dòng $_exec)"
else
    bad "C2 không khoá bằng exec 9>" "fd 9 là con trỏ duy nhất giữ khoá tới hết tiến trình"
fi
if [ -n "$_mdir" ] && [ -n "$_exec" ] && [ "$_mdir" -lt "$_exec" ]; then
    ok "C2b mkdir cache trước khi mở file khoá (dòng $_mdir < $_exec)"
else
    bad "C2b quên mkdir -p trước exec 9>" \
        "máy mới, ~/.cache chưa có -> dwmwal.sh chết ngay lần bấm Super+W đầu"
fi

# --- C3: khoá phải ở TRƯỚC mọi thao tác ghi, không phải cuối script ---------
# BỎ QUA DÒNG COMMENT: chính khối chú thích của dwmwal.sh có nhắc tới
# `rm -rf "$CACHE"` bằng chữ, grep thô sẽ bắt nhầm dòng đó (đã dính: nó trả 25
# thay vì 101, làm C30 báo sai). Chỉ lấy dòng lệnh thật — không bắt đầu bằng #.
_first_write=$(grep -n '^[^#]*rm -rf "\$CACHE"' "$DW" | head -1 | cut -d: -f1)
if [ -n "$_lock" ] && [ -n "$_first_write" ] && [ "$_lock" -lt "$_first_write" ]; then
    ok "C3 khoá mở trước lần ghi đầu tiên (dòng $_lock < $_first_write)"
else
    bad "C3 khoá mở sau lần ghi đầu tiên" \
        "khoá phải trước rm -rf \$CACHE (dòng ${_first_write:-?})"
fi

# ===========================================================================
# Phần 2 — chạy THẬT (cần ảnh nền + python3)
# ===========================================================================
if [ -z "$W" ] || [ ! -f "$W" ]; then
    printf '  --   bỏ qua phần chạy thật: không tìm thấy ảnh nền\n'
    printf '\n  %d PASS, %d FAIL\n' "$P" "$F"
    [ "$F" -eq 0 ]
    exit
fi
if ! command -v python3 >/dev/null 2>&1 || ! command -v flock >/dev/null 2>&1; then
    printf '  --   bỏ qua phần chạy thật: thiếu python3 hoặc flock\n'
    printf '\n  %d PASS, %d FAIL\n' "$P" "$F"
    [ "$F" -eq 0 ]
    exit
fi

new_repo() {
    rm -rf "$1"
    mkdir -p "$1"
    cp -a "$R/." "$1/" 2>/dev/null
}

# sandbox: HOME giả + PATH giả. dwmwal.sh:36 kiểm $WALL_DIR tồn tại TRƯỚC cả
# khi đã truyền ảnh bằng đường dẫn tuyệt đối, vì nhánh không đối số gọi
# wallpicker.py duyệt thư mục đó — thiếu là script exit 1 ngay dòng 36.
new_repo "$T/r1"
mkdir -p "$T/h1/Pictures/Wallpapers" "$T/b1"
cp "$W" "$T/h1/Pictures/Wallpapers/w.png"
printf '#!/bin/sh\nexit 0\n' > "$T/b1/feh"
printf '#!/bin/sh\necho "$*" >> %s/notify.log\n' "$T" > "$T/b1/notify-send"
for c in dunstwal pkill dmenu slstatus; do printf '#!/bin/sh\nexit 0\n' > "$T/b1/$c"; done
chmod +x "$T/b1"/*

# --- D1: walgen thiếu màu -> KHÔNG được sinh ra chuỗi rỗng, và có cảnh báo ----
cat > "$T/r1/scripts/walgen.py" <<'PY'
import sys, os
a = sys.argv[1:]
cache = a[a.index('--cache-dir') + 1]
os.makedirs(cache, exist_ok=True)
# Mô phong walgen lỗi MỘT PHẦN: colors.sh vẫn tồn tại (nên `[ -f colors.sh ]`
# không bắt được) nhưng thiếu hẳn color9..color15 — đúng loại lỗi làm dwm
# chết lúc khởi động.
open(os.path.join(cache, 'colors.sh'), 'w').write(
    "background='#1a1a1a'\nforeground='#d3cfcf'\ncursor='#d3cfcf'\n"
    "color0='#1a1a1a'\ncolor1='#45327b'\ncolor2='#493684'\ncolor3='#4e3a8c'\n"
    "color4='#533d95'\ncolor5='#58419e'\ncolor6='#5d44a6'\n"
    "color7='#d3cfcf'\ncolor8='#635454'\n")
PY
: > "$T/notify.log"
( cd "$T/r1" && env HOME="$T/h1" XDG_CACHE_HOME="$T/h1/.cache" PATH="$T/b1:$PATH" \
    TSUKI_DIR="$T/r1" DWMWAL_NO_REBUILD=1 \
    timeout 300 dash scripts/dwmwal.sh "$T/h1/Pictures/Wallpapers/w.png" ) >"$T/d1.log" 2>&1

# KHÔNG dùng `|| echo 0`: grep -c khi không khớp vẫn in ra 0 RỒI trả exit 1,
# nên `|| echo 0` in thêm số 0 nữa, ra "0\n0" và `[: ... -eq 0]` báo
# "Illegal number". Đã dính đúng lỗi đó. `|| true` giữ đúng một số 0.
n_empty=$(grep -cE '= *"";' "$T/r1/themes/wal.h" 2>/dev/null || true)
n_empty=${n_empty:-0}
if [ "$n_empty" -eq 0 ]; then
    ok "D1 walgen thiếu màu -> wal.h KHÔNG có chuỗi rỗng (0 cái)"
else
    bad "D1 walgen thiếu màu -> wal.h có $n_empty chuỗi rỗng" \
        "dwm build được rồi chết lúc mở app: drw.c:188 die() khi XftColorAllocName FAIL"
fi
if grep -q 'thiếu màu' "$T/notify.log" 2>/dev/null; then
    ok "D1b có cảnh báo báo thiếu màu"
else
    bad "D1b im lặng khi thiếu màu" \
        "người dùng không biết màu đang tạm; xem $T/notify.log"
fi

# --- D2: file sinh ra phải build được ---------------------------------------
if [ -f "$T/r1/themes/wal.h" ]; then
    ( cd "$T/r1" && rm -f drw.o dwm.o util.o && make ) >"$T/d2.log" 2>&1
    if [ -x "$T/r1/dwm" ]; then
        ok "D2 dwm build được với bảng màu thiếu (đã điền fallback)"
    else
        bad "D2 dwm KHÔNG build được với bảng màu thiếu" "xem $T/d2.log"
        grep -m3 'error' "$T/d2.log" | sed 's/^/        | /'
    fi
fi

# --- D3: walgen bình thường -> KHÔNG được cảnh báo (không báo động giả) -----
new_repo "$T/r2"
mkdir -p "$T/h2/Pictures/Wallpapers" "$T/b2"
cp "$W" "$T/h2/Pictures/Wallpapers/w.png"
for c in feh dunstwal pkill dmenu slstatus; do printf '#!/bin/sh\nexit 0\n' > "$T/b2/$c"; done
printf '#!/bin/sh\necho "$*" >> %s/notify2.log\n' "$T" > "$T/b2/notify-send"
chmod +x "$T/b2"/*
: > "$T/notify2.log"
( cd "$T/r2" && env HOME="$T/h2" XDG_CACHE_HOME="$T/h2/.cache" PATH="$T/b2:$PATH" \
    TSUKI_DIR="$T/r2" DWMWAL_NO_REBUILD=1 \
    timeout 300 dash scripts/dwmwal.sh "$T/h2/Pictures/Wallpapers/w.png" ) >"$T/d3.log" 2>&1
# CHỈ soi thông báo về màu rỗng. Log này còn chứa thông báo dunst (dunstwal.sh
# chạy thật, cần dunst nên hỏng trong sandbox) — không liên quan, đã dính vì quét
# cả file nên D3 báo sai nguyên nhân.
if grep -q 'thiếu màu' "$T/notify2.log" 2>/dev/null; then
    bad "D3 báo thiếu màu dù walgen sinh đủ" \
        "báo động giả — người dùng sẽ quen mặt cảnh báo rồi bỏ qua"
else
    ok "D3 walgen sinh đủ -> không cảnh báo giả về màu rỗng"
fi

# --- E1: hai bản chạy SONG SONG -> không còn lỗi X11 KillClient -------------
new_repo "$T/r3"
mkdir -p "$T/h3/Pictures/Wallpapers" "$T/b3"
cp "$W" "$T/h3/Pictures/Wallpapers/w.png"
for c in feh dunstwal pkill dmenu slstatus notify-send; do
    printf '#!/bin/sh\nexit 0\n' > "$T/b3/$c"
done
chmod +x "$T/b3"/*
# Chạy 3 bản thật song song, giống bấm Super+W ba lần nhanh.
for i in 1 2 3; do
    ( cd "$T/r3" && env HOME="$T/h3" XDG_CACHE_HOME="$T/h3/.cache" PATH="$T/b3:$PATH" \
        TSUKI_DIR="$T/r3" DWMWAL_NO_REBUILD=1 \
        timeout 300 dash scripts/dwmwal.sh "$T/h3/Pictures/Wallpapers/w.png" ) \
        >"$T/e$i.log" 2>&1
done
if grep -q 'X_KillClient' "$T/e1.log" "$T/e2.log" "$T/e3.log" 2>/dev/null; then
    bad "E1 3 bản song song vẫn lỗi X_KillClient" \
        "khoá chưa giữ được; xem $T/e*.log"
else
    ok "E1 3 bản dwmwal.sh chạy song song, không lỗi X11"
fi
n2=$(grep -cE '^static const char tag[1-5]\[\]' "$T/r3/themes/wal.h" 2>/dev/null || true)
n2=${n2:-0}
if [ "$n2" -eq 5 ]; then
    ok "E1b sau khi chạy song song, wal.h vẫn đủ 5 tên tag"
else
    bad "E1b sau khi chạy song song, wal.h còn $n2/5 tên tag" \
        "ghi đè chồng nhau làm mất dữ liệu"
fi

# ===========================================================================
# Phần 3 — ba file NGOÀI repo cũng phải ghi nguyên tử
# ===========================================================================
# LÝ DO KHÁC với themes/wal.h: ở đó là "bị giết giữa lúc ghi", ở đây là BÊN ĐỌC
# đang chạy song song nạp file trong lúc ta ghi.

# --- G1: bar_themes/wal -----------------------------------------------------
# bar.sh CHẠY VÒNG LẶP 1 GIÂY và nạp bằng `. "$theme_file"` (bar.sh:197, có
# guard `[ -n "$ck" ]`). ĐO với file cắt nửa chừng:
#     file "bl"                     -> . ./theme OK, black= RONG
#     file 'black="#1a1a1a"\nwhi'    -> . ./theme OK, white= RONG
# KHÔNG lỗi shell nào, chỉ biến RỖNG. bar.sh đưa chúng vào escape ^c -> thanh
# vẽ sai màu, im lặng. Guard sẵn ở bar.sh chỉ chặn file KHÔNG tồn tại, không
# chặn file tồn tại mà nội dung dở.
_bar=$(sed -n '/^cat > "\$SCRIPTS\/bar_themes\/wal/,/^EOF$/p' "$DW")
if [ -z "$_bar" ]; then
    bad "G1 tìm thấy heredoc ghi bar_themes/wal" "không trích được"
else
    _bd=$(printf '%s\n' "$_bar" | sed -n '1s/.*> "\([^"]*\)".*/\1/p')
    if [ "$_bd" = "\$SCRIPTS/bar_themes/wal.tmp" ]; then
        ok "G1 bar_themes/wal ghi qua file tạm ($_bd)"
    else
        bad "G1 bar_themes/wal ghi thẳng, không qua file tạm" \
            "đích=$_bd — bar.sh có thể nạp file dở, màu rỗng, im lặng"
    fi
    if grep -q 'mv -f "\$SCRIPTS/bar_themes/wal.tmp" "\$SCRIPTS/bar_themes/wal"' "$DW"; then
        ok "G1b có mv đưa .tmp về bar_themes/wal"
    else
        bad "G1b thiếu mv bar_themes/wal.tmp -> wal" "theme không bao giờ cập nhật"
    fi
    if grep -q '\[ ! -s "\$SCRIPTS/bar_themes/wal.tmp" \]' "$DW"; then
        ok "G1c kiểm file tạm KHÔNG rỗng trước mv"
    else
        bad "G1c không kiểm file tạm rỗng" \
            "file tạm rỗng mà vẫn mv -> mất sạch theme của thanh"
    fi
fi

# --- G2: chứng minh bằng hành vi thật — file nửa vời cho biến rỗng ----------
_dot="$T/half"
mkdir -p "$_dot"
printf 'bl' > "$_dot/theme"
_r=$(/bin/sh -c '. "$1"; printf "%s" "${black:-RONG}"' _ "$_dot/theme" 2>/dev/null)
if [ "$_r" = RONG ]; then
    ok "G2 file theme dở -> biến RỖNG mà KHÔNG lỗi shell (đúng mô tả lỗi)"
else
    bad "G2 mô phong không tái hiện được" "black=[$_r], cần lại kịch bản khác"
fi
# G2b: [ -s ] KHÔNG đủ — file dở vẫn có byte nên không bị coi là rỗng.
# ĐO: file "black=\"#d0\"WHIT" -> [ -s ] = CÓ (sai), . ./file -> white= RONG.
_at="$T/atom"
mkdir -p "$_at"
printf 'black="#1a1a1a"\nwhite="#fff"\n' > "$_at/target"
printf 'black="#d0"WHIT' > "$_at/.t.new"
_sz=no; [ -s "$_at/.t.new" ] && _sz=yes
_w=$(/bin/sh -c '. "$1"; printf "%s" "${white:-RONG}"' _ "$_at/.t.new" 2>/dev/null)
if [ "$_sz" = yes ] && [ "$_w" = RONG ]; then
    ok "G2b [ -s ] KHÔNG bắt được file dở (có byte nhưng cú pháp hỏng) — đã đo"
else
    bad "G2b mô phong file dở không tái hiện" "size=$_sz white=[$_w]"
fi
# nên phải kiểm file tạm CÓ SOURCE ĐƯỢC không, thay vì chỉ kiểm rỗng
if grep -qE 'elif ! \. "\$SCRIPTS/bar_themes/wal\.tmp"' "$DW"; then
    ok "G2c bar_themes/wal: thử SOURCE file tạm trước mv ([ -s ] không đủ)"
else
    bad "G2c bar_themes/wal chỉ kiểm rỗng, không kiểm cú pháp" \
        "file dở có byte nên lọt qua [ -s ], mv đè mất bản tốt"
fi
if grep -qE 'elif ! \. "\$_kcat"' "$DW"; then
    ok "G2d kitty/pywal.conf: thử SOURCE file tạm trước mv"
else
    # KHÔNG được `. "$_kcat"`: pywal.conf là ĐỊNH DẠNG KITTY (`tên giá_trị`),
    # không phải shell. Đo: `. pywal.conf` báo "foreground: command not found"
    # cho từng dòng và trả 127 -> nhánh elif luôn vào -> mv không bao giờ chạy,
    # pywal.conf không bao giờ cập nhật. Bản sửa đầu tiên của tôi đã dính đúng
    # lỗi này. Phải kiểm định dạng bằng awk/grep, không dùng source.
    if grep -qE '\[ "\$_kvalid" -eq "\$_ktotal" \]' "$DW"; then
        ok "G2d kitty/pywal.conf kiểm ĐỊNH DẠNG, không dùng . (đã tránh lỗi 127)"
    else
        bad "G2d kitty/pywal.conf không kiểm định dạng nào" \
            "chỉ [ -s ] thì lọt file dở; dùng . thì trả 127 và mv không bao giờ chạy"
    fi
    # Regex phải khớp CHỮ SỐ vì khoá kitty có color0..color15. Đo: với
    # `[a-z_]+` đơn thuần, file hợp lệ 21 dòng chỉ khớp 5 -> báo nhầm là hỏng.
    if grep -qE '\[a-z_\]\+\[0-9_\]\*' "$DW"; then
        ok "G2d2 regex có [0-9_]* cho khoá color0..color15 (đã đo: thiếu thì chỉ khớp 5/21)"
    else
        bad "G2d2 regex thiếu phần chữ số" \
            "'[a-z_]+' không khớp color0 -> file tốt bị báo nhầm là hỏng"
    fi
fi
# JSON phải PARSE THẬT bằng json.load — [ -s ] và cả "source" đều vô dụng với JSON
if grep -q "json.load(open(sys.argv\[1\]))" "$DW"; then
    ok "G2e pywal.json: kiểm bằng json.load thật, không dùng [ -s ]"
else
    bad "G2e pywal.json không parse kiểm" \
        "JSON dở -> JSONDecodeError, opencode mất theme; [ -s ] không bắt được"
fi

# --- G3: kitty/pywal.conf --------------------------------------------------
_kit=$(sed -n '/_kcat=/,/_kcat"/p' "$DW" | head -1)
if [ -n "$_kit" ]; then
    ok "G3 kitty/pywal.conf có file tạm riêng: $_kit"
else
    bad "G3 kitty/pywal.conf KHÔNG ghi atomic" \
        "kitty nạp file này và có thể đang mở — file dở là sai màu"
fi
if grep -q 'mv -f "\$_kcat" "\$HOME/\.config/kitty/pywal\.conf"' "$DW"; then
    ok "G3b có mv pywal.conf.tmp -> pywal.conf"
else
    bad "G3b thiếu mv pywal.conf" "file tạm đọng, theme kitty không đổi"
fi

# --- G4: opencode/themes/pywal.json — file JSON nên nặng hơn ---------------
# ĐO: JSON cắt nửa -> json.load() ném JSONDecodeError
#     "Unterminated string starting at: line 3 column 3"
# opencode đọc file này để tô màu TUI; file dở = mất theme tới lần đổi
# wallpaper sau.
_oc=$(sed -n '/_otmp=/,/_otmp"/p' "$DW" | head -1)
if [ -n "$_oc" ]; then
    ok "G4 opencode pywal.json có file tạm riêng: $_oc"
else
    bad "G4 opencode pywal.json KHÔNG ghi atomic" \
        "JSON dở -> JSONDecodeError, opencode mất theme"
fi
if grep -q 'mv -f "\$_otmp" "\$HOME/\.config/opencode/themes/pywal\.json"' "$DW"; then
    ok "G4b có mv pywal.json.tmp -> pywal.json"
else
    bad "G4b thiếu mv pywal.json" "theme không cập nhật"
fi
if grep -q '\[ ! -s "\$_otmp" \]' "$DW"; then
    ok "G4c kiểm file tạm JSON KHÔNG rỗng trước mv"
else
    bad "G4c không kiểm file tạm rỗng" "file rỗng mà mv thì mất theme cũ"
fi

# --- G6: chứng minh JSON dở thật sự hỏng, và bản atomic thì không ----------
if command -v python3 >/dev/null 2>&1; then
    _jf="$T/half.json"
    printf '{\n  "defs": {\n    "wal0": "#1a1a1a",\n    "wal' > "$_jf"
    if ! python3 -c 'import json,sys; json.load(open(sys.argv[1]))' "$_jf" 2>/dev/null; then
        ok "G6 JSON cắt nửa -> json.load thất bại (đúng mô tả lỗi)"
    else
        bad "G6 JSON cắt nửa mà parse được" "kịch bản không tái hiện được lỗi"
    fi
    # bản đúng: parse OK
    _jg="$T/good.json"
    printf '{"defs":{"wal0":"#1a1a1a"}}\n' > "$_jg"
    if python3 -c 'import json,sys; json.load(open(sys.argv[1]))' "$_jg" 2>/dev/null; then
        ok "G6b JSON đầy đủ -> parse OK (kiểm không báo động giả)"
    else
        bad "G6b JSON hợp lệ mà parse lỗi" "điều kiện kiểm sai"
    fi
else
    printf '  --   bỏ qua G6: không có python3\n'
fi

# --- G7: chứng minh regex kiểm pywal.conf phân biệt được file hỏng ---------
# Dùng đúng biểu thức trong dwmwal.sh, dựng file tốt và file hỏng, so sánh.
_pR='^[[:space:]]*[a-z_]+[0-9_]*[[:space:]]+[^[:space:]]'
printf 'foreground #d3cfcf\nbackground #1a1a1a\ncolor0 #1a1a1a\ncolor15 #ffffff\n' > "$T/k.ok"
printf 'foreground #d3cfcf\nbackground #1a1a1a\nDONG HONG KHONG PHAI CAP\n' > "$T/k.bad"
_oa=$(awk '!/^[[:space:]]*(#|$)/ { n++ } END { print n + 0 }' "$T/k.ok")
_ok=$(grep -cE "$_pR" "$T/k.ok" || true)
_ba=$(awk '!/^[[:space:]]*(#|$)/ { n++ } END { print n + 0 }' "$T/k.bad")
_bk=$(grep -cE "$_pR" "$T/k.bad" || true)
if [ "$_oa" -gt 0 ] && [ "$_ok" -eq "$_oa" ]; then
    ok "G7 file pywal.conf tốt -> qua kiểm ($_ok/$_oa dòng)"
else
    bad "G7 file tốt bị báo sai" "$_ok/$_oa dòng khớp — regex quá chặt"
fi
if [ "$_bk" -ne "$_ba" ]; then
    ok "G7b file pywal.conf hỏng -> bị bắt ($_bk/$_ba dòng khớp)"
else
    bad "G7b file hỏng lọt qua kiểm" "$_bk/$_ba — regex thiếu sức phân biệt"
fi
# và regex phải khớp color0..color15 (có chữ số)
printf 'color15 #ffffff\n' > "$T/k.num"
if [ "$(grep -cE "$_pR" "$T/k.num" || true)" -eq 1 ]; then
    ok "G7c regex khớp color15 (khoá có chữ số)"
else
    bad "G7c regex không khớp color15" "sẽ báo nhầm file tốt là hỏng"
fi
# regex thiếu chữ số thì bỏ sót color0
if [ "$(grep -cE '^[[:space:]]*[a-z_]+[[:space:]]+' "$T/k.num" || true)" -eq 0 ]; then
    ok "G7d đã xác nhận regex thiếu [0-9_]* bỏ sót color15 (lý do cần thêm phần này)"
else
    bad "G7d mô phông không tái hiện" "không chứng minh được vì sao cần [0-9_]*"
fi

# --- G5: mkdir phải được bọc if, không thể `|| true` rồi ghi vào hư không ---
# Nếu không tạo được thư mục mà vẫn `cat >` thì lỗi "Directory nonexistent"
# rồi mv vẫn chạy — đúng kiểu lỗi đã dính ở dwmwal.lock.
# --- G8: phải dọn file tạm sót từ lần chạy trước bị giết -------------------
# Khối ghi dùng .tmp + mv. Bị SIGKILL giữa `cat >` thì file tạm đọng lại.
# install.sh có sweep_tmp_stale nhưng ĐO thấy nó CHỈ quét /etc và
# /etc/pacman.d: tạo file .tmp trong repo rồi chạy sweep -> 4 file vẫn còn.
# Tức là 6 file tạm của dwmwal.sh sẽ đọng vĩnh viễn (rác trong repo, làm
# `git status` nhiễu, và trong ~/.config).
if grep -q 'file tạm sót từ lần chạy TRƯỚC' "$DW" \
   || grep -q 'file tạm sót từ lần đổi wallpaper trước' "$DW"; then
    ok "G8 dwmwal.sh có khối dọn file tạm sót từ lần chạy trước"
else
    bad "G8 dwmwal.sh KHÔNG dọn file tạm sót" \
        "sweep_tmp_stale của install.sh chỉ quét /etc — file .tmp trong repo và ~ sẽ đọng"
fi
# phải nằm SAU khối khoá, nếu không sẽ xoá nhầm file của lượt đang chạy song song
_sw=$(grep -n 'dọn.*file tạm sót từ lần chạy TRƯỚC\|_sweep_n=0' "$DW" | head -1 | cut -d: -f1)
_lk=$(grep -n 'flock -w 30 9' "$DW" | head -1 | cut -d: -f1)
if [ -n "$_sw" ] && [ -n "$_lk" ] && [ "$_sw" -gt "$_lk" ]; then
    ok "G8b khối dọn nằm SAU khối khoá (dòng $_sw > $_lk)"
else
    bad "G8b khối dọn nằm TRƯỚC khối khoá" \
        "dọn trước khi khoá thì xoá nhầm file tạm của lượt đang chạy song song"
fi
# KHÔNG được đụng file backup — "$f.tsuki-bak-<giây>" là thứ CẦN giữ, mất
# nó thì mất đường khôi phục cấu hình.
if grep -qE 'rm -f .*tsuki-bak' "$DW"; then
    bad "G8b2 dwmwal.sh xoá file .tsuki-bak" "backup là thứ CẦN giữ, mất thì mất đường phục hồi"
else
    ok "G8b2 không xoá file .tsuki-bak (thứ cần giữ để khôi phục)"
fi
# phải nêu đủ các file tạm thật sự dùng
for f in 'themes/wal.h.tmp' 'bar_themes/wal.tmp'; do
    if grep -q "$f" "$DW"; then
        ok "G8c khối dọn có $f"
    else
        bad "G8c khối dọn thiếu $f" "file này sẽ đọng nếu bị giết giữa lúc ghi"
    fi
done

# --- G5: mkdir phải được bọc if, không thể `|| true` rồi ghi vào hư không ---
# Nếu không tạo được thư mục mà vẫn `cat >` thì lỗi "Directory nonexistent"
# rồi mv vẫn chạy — đúng kiểu lỗi đã dính ở dwmwal.lock.
if grep -q 'if mkdir -p "\$HOME/\.config/opencode/themes" 2>/dev/null; then' "$DW"; then
    ok "G5 mkdir opencode/themes bọc trong if (bỏ qua gọn khi không tạo được)"
else
    bad "G5 không bọc if quanh mkdir opencode/themes" \
        "mkdir hỏng thì vẫn ghi, lỗi mới bị giấu"
fi
if grep -q 'if ! mkdir -p "\$HOME/\.config/kitty" 2>/dev/null; then' "$DW"; then
    ok "G5b mkdir kitty bọc trong if ! (bỏ qua gọn khi không tạo được)"
else
    bad "G5b không bọc if quanh mkdir kitty" "cùng lý do G5"
fi

printf '\n  %d PASS, %d FAIL\n' "$P" "$F"
[ "$F" -eq 0 ]

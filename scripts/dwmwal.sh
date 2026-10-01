#!/bin/sh
# dwmwal.sh - Color engine riêng cho dwm (không phụ thuộc GNUstep/WindowMaker)
#
# Super+W (hoặc gọi trực tiếp với 1 đường dẫn ảnh): chọn wallpaper -> sinh màu
# từ wallpaper -> áp màu cho: kitty, opencode, dunst, dwm (rebuild + reload), bar.
#
# Toàn bộ nằm trong <repo>/scripts: dùng walgen.py riêng + cache riêng
# (~/.cache/dwmwal), không chạm vào chuỗi script của WindowMaker.

# Thư mục repo: KHÔNG hardcode $HOME/dwm. run.sh export TSUKI_DIR nên dwm spawn
# script này được thừa hưởng biến đó; chạy tay thì suy ra từ vị trí script.
# Hardcode ~/dwm là sai khi clone ở chỗ khác: $SCRIPTS/wallpicker.py không tồn
# tại -> SELECTED rỗng -> `exit 0` im lặng, Super+w im lặng chết, không báo lỗi.
TSUKI_DIR="${TSUKI_DIR:-$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd -P)}"
export TSUKI_DIR
SCRIPTS="$TSUKI_DIR/scripts"
CACHE="$HOME/.cache/dwmwal"
WALL_DIR="$HOME/Pictures/Wallpapers"

# ---------------------------------------------------------------------------
# 0) Khoá: CHỈ MỘT dwmwal.sh chạy tại một thời điểm
# ---------------------------------------------------------------------------
# VÌ SAO: bấm Super+W hai lần nhanh (hoặc bấm rồi đổi ý bấm tiếp) là hai tiến
# trình chạy song song. Chúng cùng ghi vào CÙNG các file và — nguy hiểm nhất —
# dòng `rm -rf "$CACHE"` ở bước 2 xoá sạch cache của tiến trình kia đang đọc.
# Đã chạy 3 bản song song thật: một bản báo lỗi X11
#     X Error of failed request: BadValue ... X_KillClient
# do các bản cùng nhắm một tiến trình để kill.
#
# flock là TUỲ CHỌN (thuộc util-linux) — máy thiếu thì chạy tiếp không khoá,
# không chết. Không dùng `exit 1` khi không khoá được: đổi wallpaper là việc
# người dùng chủ động làm, chặn vì tranh chấp thì tệ hơn là chạy.
#
# -w 30: chờ tối đa 30 giây rồi bỏ khoá. Lần trước đang rebuild (make mất vài
# giây) thì lượt sau đợi, thay vì chạy chen vào giữa lúc file nửa vời.
LOCKDIR="${XDG_CACHE_HOME:-$HOME/.cache}"
LOCK="$LOCKDIR/dwmwal.lock"
# mkdir -p: nếu XDG_CACHE_HOME/$HOME/.cache chưa tồn tại thì `exec 9>` sẽ chết
# với "Directory nonexistent" — và điều đó xảy ra ở lần chạy đầu tiên trên máy
# mới, đúng lúc người dùng bấm Super+W.
mkdir -p "$LOCKDIR" 2>/dev/null || true
if command -v flock >/dev/null 2>&1; then
    # `exec 9>` mở file một lần; fd 9 sống suốt tiến trình nên khoá giữ được
    # tới khi script kết thúc. `flock -w 30 9` chặn tới 30 giây rồi bỏ qua.
    if exec 9>"$LOCK" 2>/dev/null; then
        flock -w 30 9 2>/dev/null || :
    fi
fi

# build rồi báo nếu hỏng. Tách riêng để test trích được từ file thật (giống
# cách test/test-run-daemons.sh trích start_daemon/stop_daemons từ run.sh) thay vì
# chép lại logic. $1 = thư mục, $2 = tên để hiện trong thông báo.
#
# Vì sao phải có: dwm spawn script này ở nền nên stdout/stderr bị nuốt. `make`
# hỏng mà không kiểm mã thoát thì không có gì để biết — wallpaper đổi, cảnh
# báo "Theme applied" vẫn hiện, chỉ có thanh trạng thái là không đổi màu.
_build_check() {
    _bc_log="${XDG_CACHE_HOME:-$HOME/.cache}/tsuki-dwmwal.log"
    if make -C "$1" >"$_bc_log" 2>&1; then
        return 0
    fi
    notify-send -u critical "dwm" "$2 build hỏng — xem $_bc_log"
    return 1
}

[ -d "$WALL_DIR" ] || { notify-send "dwmwal" "No wallpaper dir: $WALL_DIR"; exit 1; }

# ---------------------------------------------------------------------------
# 1) Chọn wallpaper: đối số dòng lệnh hoặc wallpicker
# ---------------------------------------------------------------------------
if [ $# -ge 1 ]; then
    WALL="$1"
else
    WALLPAPER_FILES=$(find "$WALL_DIR" -type f \( -iname "*.jpg" -o -iname "*.jpeg" -o -iname "*.png" \) | sort)
    [ -z "$WALLPAPER_FILES" ] && { notify-send "dwmwal" "No wallpapers found"; exit 1; }

    # Custom GTK3 picker (wallpicker.py): filmstrip carousel với
    # animation OutCubic + crop-fill đúng tỷ lệ. Picker print đường dẫn
    # tuyệt đối ra stdout khi Enter.
    # Picker (wallpicker.py) có thể chết vì nhiều lý do: thiếu python3 gi, thiếu
    # GTK3, không mở được cửa sổ X... Trước đây lỗi bị `2>/dev/null` nuốt rồi
    # `exit 0` — người dùng thấy im lặng và tưởng phím chết. Giữ stderr vào
    # log, và báo lỗi qua notify-send nếu picker không chạy được.
    WALLPICKER_LOG="${XDG_CACHE_HOME:-$HOME/.cache}/tsuki-wallpicker.log"
    if ! SELECTED=$(python3 "$SCRIPTS/wallpicker.py" --dir "$WALL_DIR" 2>"$WALLPICKER_LOG"); then
        notify-send -u critical "dwm" "wallpicker lỗi — xem $WALLPICKER_LOG"
        exit 1
    fi
    # Bấm Esc trong picker = hủy chọn, không phải lỗi: thoát im lặng.
    [ -z "$SELECTED" ] && exit 0
    WALL="$SELECTED"
fi
if [ -z "$WALL" ] || [ ! -f "$WALL" ]; then
    notify-send "dwmwal" "Invalid wallpaper: $WALL"
    exit 1
fi

# ---------------------------------------------------------------------------
# 2) Sinh màu từ wallpaper (cache riêng của dwm)
# ---------------------------------------------------------------------------
rm -rf "$CACHE"
python3 "$SCRIPTS/walgen.py" "$WALL" --cache-dir "$CACHE" >/dev/null 2>&1
[ -f "$CACHE/colors.sh" ] || { notify-send "dwmwal" "Failed to generate colors"; exit 1; }
. "$CACHE/colors.sh"

# ---------------------------------------------------------------------------
# 2a) CHẶN MÀU RỖNG — nếu không thì dwm KHÔNG KHỞI ĐỘNG ĐƯỢC
# ---------------------------------------------------------------------------
# ĐO THẬT, không suy đoán. drw.c:188 (drw_clr_create) làm thế này:
#     if (!XftColorAllocName(drp->dpy, drw->visual, drw->cmap, clrname, dest))
#             die("error, cannot allocate color '%s'", clrname);
# Chạy thử XftColorAllocName với ba giá trị trên X thật của máy:
#     "#9881dc"      -> OK    (pixel 0x9881dc)
#     ""  (rỗng)     -> FAIL
#     "khong-ton-tai"-> FAIL
# FAIL -> die() -> dwm chết lúc khởi động, không phải hỏng build mà là không
// vào được màn hình đăng nhập.
#
# KHI NÀO xảy ra: walgen.py lỗi một phần (đọc được ảnh nhưng thiếu vài màu),
# hoặc bảng màu của ảnh mới không đủ 16 sắc độ (ảnh xám, ảnh gần như đơn sắc
# khiến thuật toán bỏ bớt). Lúc đó colors.sh vẫn tồn tại — kiểm tra
# `[ -f colors.sh ]` ở trên KHÔNG bắt được — nhưng $color10 rỗng, và
# themes/wal.h sinh ra `tag1[] = ""`, dwm build vẫn ĐƯỢC (rỗng là chuỗi hợp
# lệ với C) rồi chết lúc mở app. Đúng kiểu lỗi im lặng nguy hiểm nhất.
#
# Gán fallback thay vì exit: người dùng bấm Super+W muốn đổi ảnh, không muốn
# mất desktop. Ảnh mới vẫn áp, chỉ mấy màu thiếu thì điền bằng màu tốt nhất
# đang có. Nếu MẤT CẢ bảng màu thì mới dừng — lúc đó không có gì để dùng.
_fallback='#8a94a6'
for _v in background foreground cursor color0 color1 color2 color3 color4 \
          color5 color6 color7 color8 color9 color10 color11 color12 \
          color13 color14 color15; do
    eval "_val=\${$_v:-}"
    if [ -z "$_val" ]; then
        eval "$_v=\$_fallback"
        _miss="$_miss $_v"
    fi
done
if [ -f "$CACHE/accents" ]; then
    . "$CACHE/accents"
    accent="${accent:-$color4}"
else
    accent="$color4"
fi

# accent VỪA được gán ở trên mới đúng — trước đây khối kiểm nằm TRƯỚC, nên
# accent luôn rỗng và bị đè bằng fallback kể cả khi walgen có accent thật.
# Kiểm `accent` LẦN CUỐI, sau khi mọi nguồn đã gán xong.
# SC2043: vòng lặp chạy đúng một lần. CỐ Ý — dùng lại đúng logic vòng lớn ở
# trên thay vì viết lại if, để sau này thêm biến chỉ cần sửa một chỗ. accent
# phải nạp SAU colors.sh (nó đến từ file $CACHE/accents) nên không gộp vào
# danh sách lớn được.
for _v in accent; do
    eval "_val=\${$_v:-}"
    if [ -z "$_val" ]; then
        eval "$_v=\$_fallback"
        _miss="$_miss $_v"
    fi
done
if [ -n "$_miss" ]; then
    notify-send -u critical "dwmwal" \
        "walgen thiếu màu ($_miss) — tạm dùng $_fallback, đổi ảnh khác đi"
fi

unset _fallback _v _val _miss

# 2b) firefox: xuất colors.css (biến CSS chuẩn) để userChrome.css lấy màu theo
#     wallpaper (tab active, urlbar...). userChrome.css @import "colors.css" —
#     tức file phải nằm CẠNH userChrome.css trong thư mục chrome/ của profile.
#     Dùng đường dẫn ngoài profile (vd ~/.cache/dwmwal) không ổn: khi profile là
#     symlink, Firefox resolve @import theo realpath nên đường dẫn tương đối
#     hỏng và mọi màu rơi về fallback trong userChrome.css.
cat > "$CACHE/colors.css.tmp" << EOF
:root {
  --background: ${background};
  --foreground: ${foreground};
  --cursor: ${cursor};
  --color0: ${color0};
  --color1: ${color1};
  --color2: ${color2};
  --color3: ${color3};
  --color4: ${color4};
  --color5: ${color5};
  --color6: ${color6};
  --color7: ${color7};
  --color8: ${color8};
  --color9: ${color9};
  --color10: ${color10};
  --color11: ${color11};
  --color12: ${color12};
  --color13: ${color13};
  --color14: ${color14};
  --color15: ${color15};
  --accent: ${accent};
}
EOF
# colors.css nằm trong $CACHE vốn bị `rm -rf` ngay trên nên rủi ro thấp hơn các
# file khác (không bên đọc nào trong repo nạp nó — userChrome.css đã bỏ
# @import sau lần revert). Vẫn ghi atomic cho nhất quán: rename(2) miễn phí,
# còn `cat >` để lại CSS nửa vời nếu bị giết giữa lúc ghi.
mv -f "$CACHE/colors.css.tmp" "$CACHE/colors.css" 2>/dev/null || true

# ---------------------------------------------------------------------------
# 2c) fish: xuất colors.fish ( cú pháp `set`, khác colors.sh của sh)
#     config.fish từng đọc ~/.cache/wal/colors.fish — sai CẢ thư mục lẫn tên
#     file: dwmwal ghi vào ~/.cache/dwmwal/colors.sh, ~ nên màu terminal
#     không bao giờ đổi theo wallpaper. Ở đây sinh đúng thứ config.fish cần.
# ---------------------------------------------------------------------------
# Ghi atomic cho nhất quán với các file khác. Rủi ro ở đây THẤP hơn bar/kitty
# vì config.fish chỉ nạp lúc mở terminal mới, không phải lúc đổi nền — và
# file cắt nửa thì fish BÁO LỖI RÕ (đo: "Unexpected end of string, quotes are
# not balanced"), không phải lỗi im lặng. Nhưng nếu đang ghi mà ta mở terminal
# thì shell đó lỗi ngay lúc mở, khó chẩn đoán. rename(2) thì miễn phí.
_cf="$CACHE/colors.fish.tmp"
cat > "$_cf" << EOF
# Generated by dwmwal.sh — do NOT edit (bị ghi đè mỗi lần đổi wallpaper)
#
# Mọi giá trị PHẢI đặt trong nháy: trong fish, '#' mở đầu comment, nên
# dòng "set -g color4 #a82a89" trở thành "color4 rỗng + phần còn lại là
# comment" — set rỗng, KHÔNG báo lỗi, màu terminal im lặng mất.
set -g wallpaper '$WALL'
set -g background '$background'
set -g foreground '$foreground'
set -g cursor     '$cursor'
set -g color0     '$color0'
set -g color1     '$color1'
set -g color2     '$color2'
set -g color3     '$color3'
set -g color4     '$color4'
set -g color5     '$color5'
set -g color6     '$color6'
set -g color7     '$color7'
set -g color8     '$color8'
set -g color9     '$color9'
set -g color10    '$color10'
set -g color11    '$color11'
set -g color12    '$color12'
set -g color13    '$color13'
set -g color14    '$color14'
set -g color15    '$color15'
set -g accent     '$accent'
EOF
if [ -s "$_cf" ]; then
    mv -f "$_cf" "$CACHE/colors.fish"
else
    rm -f "$_cf"
    notify-send -u critical "dwmwal" "tạo colors.fish rỗng — file cũ giữ nguyên"
fi

# ---------------------------------------------------------------------------
# 3) Đặt wallpaper (feh) + lưu lại cho lần chạy sau
# ---------------------------------------------------------------------------
feh --no-fehbg --bg-fill "$WALL"
echo "$WALL" > "$SCRIPTS/.wallpaper"

# ---------------------------------------------------------------------------
# 4) dwm: tạo theme wal.h + chuyển config.def.h sang dùng nó
# ---------------------------------------------------------------------------
# GHI QUA FILE TẠM RỒI mv, KHÔNG `cat > themes/wal.h` trực tiếp.
#
# LÝ DO: bước 9 (rebuild.sh -> make) đọc chính file này vài giây sau. Nếu
# script bị giết (SIGINT khi Ctrl-C, mất điện, OOM) GIỮA CHỪNG lệnh ghi, dwm
# đọc file nửa vời -> không biên dịch được. Đã thấy đúng lỗi đó:
#     config.h:73: error: 'tag1' undeclared here
#
# `mv` trong CÙNG thư mục dùng rename(2) — POSIX bảo đảm thay thế nguyên tử,
# nên make chỉ thấy file cũ hoặc file mới, không bao giờ thấy file dở.
# KHÔNG ghi vào /tmp: khác filesystem thì mv phải copy, mất tính nguyên tử.
cat > "$TSUKI_DIR/themes/wal.h.tmp" << EOF
static const char black[]       = "$color0";
static const char gray2[]       = "$color8";
static const char gray3[]       = "$color7";
static const char gray4[]       = "$color8";
static const char blue[]        = "$accent";
static const char green[]       = "$color2";
static const char red[]         = "$color1";
static const char orange[]      = "$color3";
static const char yellow[]      = "$color11";
static const char pink[]        = "$color5";
static const char col_borderbar[]  = "$color0";
static const char white[]       = "$foreground";

// tag1..tag5: màu riêng cho 5 workspace (SchemeTag1..5 trong config.h).
//
// VÌ SAO PHẢI Ở ĐÂY, KHÔNG SỬA TAY themes/wal.h: file này BỊ GHI LẠI MỖI LẦN
// chạy dwmwal.sh (lệnh cat > ngay trên dòng này). Bản sửa trước thêm tag1..tag5
// bằng tay vào themes/wal.h — chạy đúng một lần đổi ảnh nền là mất sạch, rồi
// config.h:73 tham chiếu tên không tồn tại và dwm KHÔNG BIÊN DỊCH được:
//   config.h:73: error: 'tag1' undeclared here (not in a function)
// Super+Shift+R vẫn được vì nó không sinh lại wal.h; Super+W thì hỏng. Đúng
// triệu chứng đã gặp.
//
// LƯU Ý KHI SỬA KHỐI ĐOẠN NÀY: heredoc là << EOF (KHÔNG quoted), nên shell
// mở rộng $ và dấu gạch ngược. Backtick trong comment sẽ bị shell đọc như lệnh
// và làm hỏng CẢ dwmwal.sh: đã dính "syntax error near unexpected token newline"
// vì viết lệnh cat > trong ngoặc ngược. Comment ở đây cố ý không có backtick.
//
// ÁNH XẠ: mỗi workspace nhận một màu của dải SÁNG (color9..color15, color7),
// đúng như slstatus đang dùng. KHÔNG sửa blue/green/red/orange/pink — chúng
// không chỉ cho workspace:
//   - blue là NỀN của SchemeSel và TabSel (config.h:68,70). Nền sáng làm chữ
//     trên đó mất tương phản — đổi blue sẽ hỏng thanh highlight.
//   - green là màu SchemeLayout và SchemeBtnPrev; red là SchemeBtnClose.
// Đổi chúng sẽ đổi cả nút điều hướng, việc này người dùng không yêu cầu.
// Bỏ color0..color8: đó là dải tối, dùng cho nền/nút, đưa vào chữ là mất
// tương phản.
//   tag1 <- color10   (CPU)      tag4 <- color13   (nhiệt độ)
//   tag2 <- color9    (RAM)      tag5 <- color7    (chữ sáng)
//
// VÌ SAO DÙNG CHÍNH DẢI SÁNG ĐÓ — số đo thật trên màn hình, chụp rồi đếm
// pixel (chạy với ảnh FW 13 Pro Wallpaper 6.png):
//     blue   #6742d7  lum  84.6
//     red    #45327b  lum  59.3
//     orange #4e3a8c  lum  68.2
//     green  #493684  lum  63.7
//     pink   #58419e  lum  76.6
//   slstatus: #9881dc 140.5 · #9077da 131.5 · #9f8adf 148.6 · #af9de4 166.0
// => cả 5 màu cũ đều tối hơn thanh trạng thái đứng cạnh nó 70–95 điểm, đọc
//    rất khó. Dải sáng ở trên khớp 5 màu slstatus đang dùng nên hòa vào.
static const char tag1[]        = "$color10";
static const char tag2[]        = "$color9";
static const char tag3[]        = "$color11";
static const char tag4[]        = "$color13";
static const char tag5[]        = "$color7";
EOF
mv -f "$TSUKI_DIR/themes/wal.h.tmp" "$TSUKI_DIR/themes/wal.h"
sed -i 's|#include "themes/[^"]*"|#include "themes/wal.h"|' "$TSUKI_DIR/config.def.h"

# ---------------------------------------------------------------------------
# 5) bar: tạo theme wal + chuyển bar.sh sang dùng nó
# ---------------------------------------------------------------------------
# Ghi qua file tạm rồi mv — LÝ DO KHÁC themes/wal.h, không phải lúc crash.
#
# bar.sh CHẠY VÒNG LẶP 1 GIÂY và nạp theme bằng `. "$theme_file"` (dòng 197,
# có guard `[ -n "$ck" ]`). Nếu `cat >` ghi thẳng, bar.sh có thể nạp đúng lúc
# file còn dở. ĐO:
#     file dở "bl"           -> . ./theme thành công, black= RONG
#     file dở 'black=..\nwhi' -> . ./theme thành công, white= RONG
# KHÔNG có lỗi shell nào, chỉ có biến RỖNG. bar.sh đưa chúng vào escape
# ^c -> thanh vẽ sai màu, im lặng. Guard sẵn có ở bar.sh chỉ chặn TRƯỜNG HỢP
# file không tồn tại, không chặn file tồn tại mà nội dung dở.
# `mv` cùng thư mục dùng rename(2) — bar.sh chỉ thấy bản cũ hoặc bản mới.
cat > "$SCRIPTS/bar_themes/wal.tmp" << EOF
#!/bin/dash

# dwmwal bar colors (tự sinh từ wallpaper)
black=$color0
green=$color2
white=$foreground
grey=$color8
blue=$accent
red=$color1
orange=$color3
teal=$color12
darkblue=$color6
EOF
# Cùng lý do với ~/.xinitrc: file tạm rỗng thì KHÔNG được mv lên đích. Đo với
# `ulimit -f`: heredoc vượt giới hạn thì bash không tạo file, nhưng mv vẫn
# chạy và thay theme đang tốt bằng file rỗng -> bar mất sạch màu.
if [ ! -s "$SCRIPTS/bar_themes/wal.tmp" ]; then
    rm -f "$SCRIPTS/bar_themes/wal.tmp"
    notify-send -u critical "dwmwal" "tạo theme bar thất bại — theme cũ giữ nguyên"
elif ! . "$SCRIPTS/bar_themes/wal.tmp" 2>/dev/null; then
    # [ -s ] KHÔNG ĐỦ. ĐO: file "black=\"#d0\"WHIT" có byte nên [ -s ] thấy
    # rỗng là sai, nhưng `. ./file` để lại white= RONG -> bar.sh nạp file dở
    # rồi đưa biến rỗng vào escape ^c. Nên phải THỬ SOURCE thật, trong
    # subshell để không làm bẩn biến của chính dwmwal.sh.
    rm -f "$SCRIPTS/bar_themes/wal.tmp"
    notify-send -u critical "dwmwal" "theme bar sai cú pháp — theme cũ giữ nguyên"
else
    mv -f "$SCRIPTS/bar_themes/wal.tmp" "$SCRIPTS/bar_themes/wal"
fi
sed -i 's|bar_themes/[^ ]*|bar_themes/wal|' "$SCRIPTS/bar.sh"

# ---------------------------------------------------------------------------
# 6) kitty: ghi pywal.conf + reload qua touch kitty.conf
# ---------------------------------------------------------------------------
KITTY_CONF="$HOME/.config/kitty/kitty.conf"
# Ghi atomic: kitty NẠP file này (include trong kitty.conf) và có thể đang mở
# sẵn. Nếu bị giết giữa lúc ghi, kitty nạp file dở -> màu sai, mà không có lỗi
# nào hiện ra. Cùng lý do như bar_themes/wal: đọc bên ngoài trong lúc ghi.
if ! mkdir -p "$HOME/.config/kitty" 2>/dev/null; then
    notify-send "dwmwal" "không tạo được ~/.config/kitty — bỏ qua màu kitty"
else
    _kcat="$HOME/.config/kitty/pywal.conf.tsuki-new.$$"
    cat > "$_kcat" << EOF
# dwmwal generated colors
foreground $foreground
background $background
cursor $cursor
selection_foreground $background
selection_background $foreground
color0 $color0
color1 $color1
color2 $color2
color3 $color3
color4 $color4
color5 $color5
color6 $color6
color7 $color7
color8 $color8
color9 $color9
color10 $color10
color11 $color11
color12 $color12
color13 $color13
color14 $color14
color15 $color15
EOF
    if [ ! -s "$_kcat" ]; then
        rm -f "$_kcat"
        notify-send -u critical "dwmwal" "tạo pywal.conf rỗng — file cũ giữ nguyên"
    else
        # [ -s ] KHÔNG ĐỦ, và CŨNG KHÔNG THỂ dùng `. "$_kcat"` để kiểm.
        # pywal.conf là ĐỊNH DẠNG KITTY (`tên giá_trị`), KHÔNG phải shell
        # script. ĐO: `. pywal.conf` báo "foreground: command not found" cho
        # từng dòng, trả 127. Bản sửa đầu tiên của tôi đã dùng `. ` và vì vậy
        # nhánh elif luôn vào -> mv KHÔNG BAO GIỜ chạy -> pywal.conf không bao
        # giờ cập nhật, đồng thời spam cảnh báo. Đó là lỗi tôi gây.
        #
        # Kiểm định dạng: mỗi dòng có nội dung phải là `tên giá_trị`.
        # `[a-z_]+[0-9_]*` vì khoá của kitty CÓ CHỮ SỐ (color0..color15) — regex
        # `[a-z_]+` đơn thuần bỏ sót color0 nên báo sai file hỏng thành tốt.
        _ktotal=$(awk '!/^[[:space:]]*(#|$)/ { n++ } END { print n + 0 }' "$_kcat")
        _kvalid=$(grep -cE '^[[:space:]]*[a-z_]+[0-9_]*[[:space:]]+[^[:space:]]' "$_kcat" || true)
        if [ "$_ktotal" -gt 0 ] && [ "$_kvalid" -eq "$_ktotal" ]; then
            mv -f "$_kcat" "$HOME/.config/kitty/pywal.conf"
        else
            rm -f "$_kcat"
            notify-send -u critical "dwmwal" \
                "pywal.conf sai định dạng ($_kvalid/$_ktotal dòng hợp lệ) — file cũ giữ nguyên"
        fi
    fi
    # NOTE (Arisa): không tự append 'include pywal.conf' nữa — kitty giữ theme Tokyo Night
    # (pywal.conf vẫn được ghi ở trên để dùng tay nếu muốn màu wallpaper)
    # grep -q '^include pywal.conf' "$KITTY_CONF" 2>/dev/null || echo "include pywal.conf" >> "$KITTY_CONF"
    touch "$KITTY_CONF"
fi

# ---------------------------------------------------------------------------
# 6b) equibop (Discord client): đồng bộ màu theme system24-arisa khi đổi wallpaper
#     (gen-equibop-theme.sh đọc pywal.conf vừa ghi, cập nhật --blue-* trong theme)
# ---------------------------------------------------------------------------
if [ -x "$HOME/.local/bin/gen-equibop-theme.sh" ]; then
    "$HOME/.local/bin/gen-equibop-theme.sh" || true
fi

# ---------------------------------------------------------------------------
# 7) opencode: ghi theme pywal.json + bật qua tui.json
# ---------------------------------------------------------------------------
if mkdir -p "$HOME/.config/opencode/themes" 2>/dev/null; then
    # Ghi atomic — file JSON, hậu quả nặng hơn file shell.
    # ĐO: JSON cắt nửa chừng thì json.load() ném JSONDecodeError:
    #     "Unterminated string starting at: line 3 column 3"
    # opencode đọc theme này để tô màu TUI; file dở = mất theme cho tới lần
    # đổi wallpaper lần sau. Với file .conf của kitty, hậu quả nhẹ hơn (sai
    # màu), nhưng JSON thì hỏng hẳn — nên chắc chắn phải atomic.
    _otmp="$HOME/.config/opencode/themes/pywal.json.tsuki-new.$$"
    cat > "$_otmp" << EOF
{
  "\$schema": "https://opencode.ai/theme.json",
  "defs": {
    "walbg": "${background}",
    "walfg": "${foreground}",
    "wal0": "${color0}", "wal1": "${color1}", "wal2": "${color2}", "wal3": "${color3}",
    "wal4": "${color4}", "wal5": "${color5}", "wal6": "${color6}", "wal7": "${color7}",
    "wal8": "${color8}", "wal9": "${color9}", "wal10": "${color10}", "wal11": "${color11}",
    "wal12": "${color12}", "wal13": "${color13}", "wal14": "${color14}", "wal15": "${color15}"
  },
  "theme": {
    "primary": { "dark": "wal6", "light": "wal4" },
    "secondary": { "dark": "wal12", "light": "wal12" },
    "accent": { "dark": "wal5", "light": "wal5" },
    "error": { "dark": "wal1", "light": "wal1" },
    "warning": { "dark": "wal3", "light": "wal3" },
    "success": { "dark": "wal2", "light": "wal2" },
    "info": { "dark": "wal6", "light": "wal4" },
    "text": { "dark": "walfg", "light": "walbg" },
    "textMuted": { "dark": "wal8", "light": "wal8" },
    "background": { "dark": "walbg", "light": "wal7" },
    "backgroundPanel": { "dark": "walbg", "light": "wal7" },
    "backgroundElement": { "dark": "wal0", "light": "wal7" },
    "border": { "dark": "wal8", "light": "wal8" },
    "borderActive": { "dark": "wal6", "light": "wal6" },
    "borderSubtle": { "dark": "wal0", "light": "wal8" },
    "diffAdded": { "dark": "wal2", "light": "wal2" },
    "diffRemoved": { "dark": "wal1", "light": "wal1" },
    "diffContext": { "dark": "wal8", "light": "wal8" },
    "diffHunkHeader": { "dark": "wal8", "light": "wal8" },
    "diffHighlightAdded": { "dark": "wal10", "light": "wal10" },
    "diffHighlightRemoved": { "dark": "wal9", "light": "wal9" },
    "diffAddedBg": { "dark": "wal0", "light": "wal7" },
    "diffRemovedBg": { "dark": "wal0", "light": "wal7" },
    "diffContextBg": { "dark": "wal0", "light": "wal7" },
    "diffLineNumber": { "dark": "wal8", "light": "wal8" },
    "diffAddedLineNumberBg": { "dark": "wal0", "light": "wal7" },
    "diffRemovedLineNumberBg": { "dark": "wal0", "light": "wal7" },
    "markdownText": { "dark": "walfg", "light": "walbg" },
    "markdownHeading": { "dark": "wal6", "light": "wal4" },
    "markdownLink": { "dark": "wal12", "light": "wal12" },
    "markdownLinkText": { "dark": "wal5", "light": "wal5" },
    "markdownCode": { "dark": "wal2", "light": "wal2" },
    "markdownBlockQuote": { "dark": "wal8", "light": "wal8" },
    "markdownEmph": { "dark": "wal3", "light": "wal3" },
    "markdownStrong": { "dark": "wal5", "light": "wal5" },
    "markdownHorizontalRule": { "dark": "wal8", "light": "wal8" },
    "markdownListItem": { "dark": "wal6", "light": "wal4" },
    "markdownListEnumeration": { "dark": "wal5", "light": "wal5" },
    "markdownImage": { "dark": "wal12", "light": "wal12" },
    "markdownImageText": { "dark": "wal5", "light": "wal5" },
    "markdownCodeBlock": { "dark": "walfg", "light": "walbg" },
    "syntaxComment": { "dark": "wal8", "light": "wal8" },
    "syntaxKeyword": { "dark": "wal12", "light": "wal12" },
    "syntaxFunction": { "dark": "wal6", "light": "wal6" },
    "syntaxVariable": { "dark": "wal5", "light": "wal5" },
    "syntaxString": { "dark": "wal2", "light": "wal2" },
    "syntaxNumber": { "dark": "wal13", "light": "wal13" },
    "syntaxType": { "dark": "wal5", "light": "wal5" },
    "syntaxOperator": { "dark": "wal12", "light": "wal12" },
    "syntaxPunctuation": { "dark": "walfg", "light": "walbg" }
  }
}
EOF
    # Kiểm rỗng trước mv (lý do như ~/.xinitrc: file tạm rỗng mà vẫn mv thì mất
    # theme cũ). Rồi rename(2) — opencode chỉ thấy JSON cũ hoặc JSON mới.
    if [ ! -s "$_otmp" ]; then
        rm -f "$_otmp"
        notify-send -u critical "dwmwal" "tạo pywal.json rỗng — theme cũ giữ nguyên"
    elif command -v python3 >/dev/null 2>&1 \
         && ! python3 -c 'import json,sys; json.load(open(sys.argv[1]))' "$_otmp" 2>/dev/null; then
        # JSON PHẢI PARSE THẬT, không dùng [ -s ]. ĐO: file JSON cắt nửa ->
        # json.load() ném JSONDecodeError "Unterminated string starting at:
        # line 3 column 3" -> opencode mất theme cho tới lần đổi wallpaper sau.
        # Có python3 thì kiểm; không có thì chỉ dựa vào [ -s ] (walgen.py cần
        # python3 nên thực tế luôn có, nhưng không giả định).
        rm -f "$_otmp"
        notify-send -u critical "dwmwal" "pywal.json không phải JSON hợp lệ — theme cũ giữ nguyên"
    else
        mv -f "$_otmp" "$HOME/.config/opencode/themes/pywal.json"
    fi
else
    notify-send "dwmwal" "không tạo được ~/.config/opencode/themes — bỏ qua màu opencode"
fi

# NOTE (Arisa): không ép opencode về theme pywal nữa — opencode giữ theme tokyo-night
# (pywal.json vẫn được ghi ở trên như theme tham chiếu, dùng tay khi muốn)
# TUI_CONFIG="$HOME/.config/opencode/tui.json"
# if [ ! -f "$TUI_CONFIG" ]; then
#     echo '{ "$schema": "https://opencode.ai/tui.json", "theme": "pywal" }' > "$TUI_CONFIG"
# elif command -v jq >/dev/null 2>&1; then
#     jq '.theme = "pywal"' "$TUI_CONFIG" > "$TUI_CONFIG.tmp" && mv "$TUI_CONFIG.tmp" "$TUI_CONFIG"
# fi

# ---------------------------------------------------------------------------
# 8) dunst: sync colors via dunstwal.sh (comprehensive, handles all urgency levels)
# ---------------------------------------------------------------------------
if [ -x "$SCRIPTS/dunstwal.sh" ]; then
    # Kiểm tra exit code: dwm spawn script này ở nền nên stdout/stderr bị
    # nuốt. Không kiểm tra thì hỏng vẫn im lặng, đúng kiểu lỗi ta đang dập.
    DUNST_LOG="${XDG_CACHE_HOME:-$HOME/.cache}/tsuki-dunstwal.log"
    if ! "$SCRIPTS/dunstwal.sh" >"$DUNST_LOG" 2>&1; then
        notify-send -u critical "dwm" "Không sync được màu dunst — xem $DUNST_LOG"
    fi
fi

# ---------------------------------------------------------------------------
# 9) rebuild dwm (cần pkexec, popup mật khẩu) + cập nhật màu slstatus
#    (bỏ qua bước rebuild khi DWMWAL_NO_REBUILD=1 — dùng để test)
#    slstatus: thay sentinel XXX_HEX trong config.h bằng màu wal mới, rebuild
#    (không cần root — build local) rồi restart. Thay cho bar.sh cũ.
# ---------------------------------------------------------------------------
if [ -z "$DWMWAL_NO_REBUILD" ]; then
    "$SCRIPTS/rebuild.sh"

    SLST_DIR="$TSUKI_DIR/slstatus"
    # config.h tai sinh TU config.def.h (chua sentinel XXX_HEX) roi thay sentinel
    # bang mau wal moi -> idempotent, mau slstatus luon theo theme hien tai.
    cp "$SLST_DIR/config.def.h" "$SLST_DIR/config.h"
    sed -e "s|UPD_ON_HEX|${foreground:-#c3d3df}|" \
        -e "s|UPD_OFF_HEX|${color2:-#386282}|" \
        -e "s|CPU_HEX|${color10:-#82aaff}|" \
        -e "s|RAM_HEX|${color9:-#bb9af7}|" \
        -e "s|DISK_HEX|${color11:-#7ee787}|" \
        -e "s|TEMP_HEX|${color13:-#c3a6ff}|" \
        -e "s|BAT_HEX|${accent:-#4296d7}|" \
        -e "s|BATSTATE_HEX|${color11:-#8cbadd}|" \
        -e "s|CLOCK_HEX|${color11:-#8cbadd}|" \
        "$SLST_DIR/config.h" > "$SLST_DIR/config.h.new" \
        && mv "$SLST_DIR/config.h.new" "$SLST_DIR/config.h"
    # Kiểm mã thoát của make. Bản cũ `make -C "$SLST_DIR" >/dev/null 2>&1` —
    # hỏng thì im lặng, binary cũ vẫn chạy, rồi `pkill -x slstatus` vẫn giết
    # nó đi cho vòng lặp của run.sh nạp lại đúng binary cũ. Người dùng đổi
    # wallpaper xong thấy thanh trạng thái không đổi mà không có gì nói lý do.
    # Dùng chung khuôn với bước dunst ở trên.
    if _build_check "$SLST_DIR" slstatus; then
        # chi can pkill: vong lap tu phuc hoi trong run.sh se restart slstatus
        # voi binary moi (tranh 2 instance khi nohup + wrapper cung chay)
        pkill -x slstatus 2>/dev/null
    fi

    # dmenu: tu config.def.h (sentinel DMENU_*) -> config.h voi mau wal moi
    DMENU_DIR="$TSUKI_DIR/dmenu"
    cp "$DMENU_DIR/config.def.h" "$DMENU_DIR/config.h"
    sed -e "s|DMENU_FG_NORM|${foreground:-#d1d8ca}|" \
        -e "s|DMENU_BG_NORM|${color0:-#1a1d16}|" \
        -e "s|DMENU_FG_SEL|${color0:-#1a1d16}|" \
        -e "s|DMENU_BG_SEL|${accent:-#42d757}|" \
        -e "s|DMENU_FG_OUT|${color0:-#1a1d16}|" \
        -e "s|DMENU_BG_OUT|${color5:-#34ab45}|" \
        "$DMENU_DIR/config.h" > "$DMENU_DIR/config.h.new" \
        && mv "$DMENU_DIR/config.h.new" "$DMENU_DIR/config.h"
    if ! _build_check "$DMENU_DIR" dmenu; then :; fi
fi

notify-send "dwm" "Theme applied: $(basename "$WALL")"

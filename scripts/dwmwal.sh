#!/bin/sh
# dwmwal.sh - Color engine riêng cho dwm (không phụ thuộc GNUstep/WindowMaker)
#
# Super+W (hoặc gọi trực tiếp với 1 đường dẫn ảnh): chọn wallpaper -> sinh màu
# từ wallpaper -> áp màu cho: kitty, opencode, dunst, dwm (rebuild + reload), bar.
#
# Toàn bộ đều nằm trong ~/dwm/scripts: dùng walgen.py riêng + cache riêng
# (~/.cache/dwmwal), không chạm vào chuỗi script của WindowMaker.

DWM_DIR="$HOME/dwm"
SCRIPTS="$DWM_DIR/scripts"
CACHE="$HOME/.cache/dwmwal"
WALL_DIR="$HOME/Pictures/Wallpapers"

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
    SELECTED=$(python3 "$SCRIPTS/wallpicker.py" --dir "$WALL_DIR" 2>/dev/null)
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
if [ -f "$CACHE/accents" ]; then
    . "$CACHE/accents"
    accent="${accent:-$color4}"
else
    accent="$color4"
fi

# 2b) firefox: xuất colors.css (biến CSS chuẩn) để userChrome.css lấy màu theo
#     wallpaper (tab active, urlbar...). Firefox chỉ đọc đc file nằm ngoài
#     profile qua @import — cache dwmwal đủ quyền đọc.
cat > "$CACHE/colors.css" << EOF
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

# ---------------------------------------------------------------------------
# 3) Đặt wallpaper (feh) + lưu lại cho lần chạy sau
# ---------------------------------------------------------------------------
feh --no-fehbg --bg-fill "$WALL"
echo "$WALL" > "$SCRIPTS/.wallpaper"

# ---------------------------------------------------------------------------
# 4) dwm: tạo theme wal.h + chuyển config.def.h sang dùng nó
# ---------------------------------------------------------------------------
cat > "$DWM_DIR/themes/wal.h" << EOF
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
EOF
sed -i 's|#include "themes/[^"]*"|#include "themes/wal.h"|' "$DWM_DIR/config.def.h"

# ---------------------------------------------------------------------------
# 5) bar: tạo theme wal + chuyển bar.sh sang dùng nó
# ---------------------------------------------------------------------------
cat > "$SCRIPTS/bar_themes/wal" << EOF
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
sed -i 's|bar_themes/[^ ]*|bar_themes/wal|' "$SCRIPTS/bar.sh"

# ---------------------------------------------------------------------------
# 6) kitty: ghi pywal.conf + reload qua touch kitty.conf
# ---------------------------------------------------------------------------
KITTY_CONF="$HOME/.config/kitty/kitty.conf"
cat > "$HOME/.config/kitty/pywal.conf" << EOF
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
# NOTE (Arisa): không tự append 'include pywal.conf' nữa — kitty giữ theme Tokyo Night
# (pywal.conf vẫn được ghi ở trên để dùng tay nếu muốn màu wallpaper)
# grep -q '^include pywal.conf' "$KITTY_CONF" 2>/dev/null || echo "include pywal.conf" >> "$KITTY_CONF"
touch "$KITTY_CONF"

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
mkdir -p "$HOME/.config/opencode/themes"
cat > "$HOME/.config/opencode/themes/pywal.json" << EOF
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
    "$SCRIPTS/dunstwal.sh"
fi

# ---------------------------------------------------------------------------
# 9) rebuild dwm (cần pkexec, popup mật khẩu) + cập nhật màu slstatus
#    (bỏ qua bước rebuild khi DWMWAL_NO_REBUILD=1 — dùng để test)
#    slstatus: thay sentinel XXX_HEX trong config.h bằng màu wal mới, rebuild
#    (không cần root — build local) rồi restart. Thay cho bar.sh cũ.
# ---------------------------------------------------------------------------
if [ -z "$DWMWAL_NO_REBUILD" ]; then
    "$SCRIPTS/rebuild.sh"

    SLST_DIR="$HOME/dwm/slstatus"
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
    make -C "$SLST_DIR" >/dev/null 2>&1
    # chi can pkill: vong lap tu phuc hoi trong run.sh se restart slstatus
    # voi binary moi (tranh 2 instance khi nohup + wrapper cung chay)
    pkill -x slstatus 2>/dev/null

    # dmenu: tu config.def.h (sentinel DMENU_*) -> config.h voi mau wal moi
    DMENU_DIR="$HOME/dwm/dmenu"
    cp "$DMENU_DIR/config.def.h" "$DMENU_DIR/config.h"
    sed -e "s|DMENU_FG_NORM|${foreground:-#d1d8ca}|" \
        -e "s|DMENU_BG_NORM|${color0:-#1a1d16}|" \
        -e "s|DMENU_FG_SEL|${color0:-#1a1d16}|" \
        -e "s|DMENU_BG_SEL|${accent:-#42d757}|" \
        -e "s|DMENU_FG_OUT|${color0:-#1a1d16}|" \
        -e "s|DMENU_BG_OUT|${color5:-#34ab45}|" \
        "$DMENU_DIR/config.h" > "$DMENU_DIR/config.h.new" \
        && mv "$DMENU_DIR/config.h.new" "$DMENU_DIR/config.h"
    make -C "$DMENU_DIR" >/dev/null 2>&1
fi

notify-send "dwm" "Theme applied: $(basename "$WALL")"

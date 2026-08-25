#!/bin/bash
# dunstwal.sh — sync dunst colors with dwm wal theme
# Reads ~/.cache/wal/colors and ~/.cache/wal/accents
# Updates ~/.config/dunst/dunstrc and reloads dunst

DUNSTRC="$HOME/.config/dunst/dunstrc"
CACHE_COLORS="$HOME/.cache/wal/colors"
CACHE_ACCENTS="$HOME/.cache/wal/accents"

[ -f "$CACHE_COLORS" ] || { echo "wal colors not found at $CACHE_COLORS"; exit 1; }
[ -f "$DUNSTRC" ] || { echo "dunstrc not found at $DUNSTRC"; exit 1; }

# Read wal colors (16 lines, 0-indexed)
mapfile -t COLORS < "$CACHE_COLORS"

# color0  = background (darkest)
# color1-15 = palette
# accent from accents file or color4
BG="${COLORS[0]}"
FG="${COLORS[7]}"        # color7 = light foreground
BORDER="${COLORS[8]}"    # color8 = gray2 (dwm border color)
ACCENT="${COLORS[4]:-${COLORS[${#COLORS[@]}-1]:-#89b4fa}}"    # color4 = accent
BORDER="${BORDER:-$ACCENT}"   # file màu quá ngắn -> đừng ghi chuỗi rỗng vào dunstrc
FG="${FG:-${COLORS[-1]:-#cdd6f4}}"

if [ -f "$CACHE_ACCENTS" ]; then
    source "$CACHE_ACCENTS"
    ACCENT="${accent:-$ACCENT}"
fi

# Backup
cp "$DUNSTRC" "$DUNSTRC.bak" 2>/dev/null

# Update colors in dunstrc
# [global] section: background, foreground, frame_color
sed -i "/^\[global\]/,/^\[/{
    s/^[[:space:]]*background = .*/    background = \"$BG\"/
    s/^[[:space:]]*foreground = .*/    foreground = \"$FG\"/
    s/^[[:space:]]*frame_color = .*/    frame_color = \"$BORDER\"/
}" "$DUNSTRC"

# [urgency_low] background/foreground
sed -i "/^\[urgency_low\]/,/^\[/{
    s/^[[:space:]]*background = .*/        background = \"$BG\"/
    s/^[[:space:]]*foreground = .*/        foreground = \"$FG\"/
}" "$DUNSTRC"

# [urgency_normal] background/foreground
sed -i "/^\[urgency_normal\]/,/^\[/{
    s/^[[:space:]]*background = .*/        background = \"$BG\"/
    s/^[[:space:]]*foreground = .*/        foreground = \"$FG\"/
}" "$DUNSTRC"

# [urgency_critical] background/foreground + frame_color
sed -i "/^\[urgency_critical\]/,/^\[/{
    s/^[[:space:]]*background = .*/        background = \"$BG\"/
    s/^[[:space:]]*foreground = .*/        foreground = \"$ACCENT\"/
    s/^[[:space:]]*frame_color = .*/        frame_color = \"$ACCENT\"/
}" "$DUNSTRC"

# Reload dunst
killall dunst 2>/dev/null
for _ in $(seq 50); do
    pgrep -u "$UID" -x dunst >/dev/null 2>&1 || break
    sleep 0.1
done
dunst &

echo "dunst colors synced with wal:"
echo "  bg:      $BG"
echo "  fg:      $FG"
echo "  border:  $BORDER"
echo "  accent:  $ACCENT"
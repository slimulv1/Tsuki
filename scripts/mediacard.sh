#!/bin/sh
# mediacard.sh — M3 combined notification: Now Playing + Volume in ONE card
#   Left   : video thumbnail + ▶/⏸ video title
#   Right  : speaker glyph + "Volume N%"
#   Bottom : native dunst progress bar (volume level)
# Usage:
#   mediacard.sh volume up|down|mute   (volume key handler)
#   mediacard.sh daemon                (MPRIS watcher, started from run.sh)

ART_DIR=/tmp/nowplaying-art
LAST_FILE=/tmp/nowplaying-last
mkdir -p "$ART_DIR"

# Font Awesome speaker glyphs (Nerd Font PUA), emitted via octal UTF-8:
#   \357\200\246 = U+F026 volume-off (mute)
#   \357\200\247 = U+F027 volume-down (low)
#   \357\200\250 = U+F028 volume-up (high)
SPK_MUTE=$(printf '\357\200\246')
SPK_LOW=$(printf '\357\200\247')
SPK_HIGH=$(printf '\357\200\250')

# Adwaita symbolic icons (fallback left icon when no media)
ICON_MUTED=/usr/share/icons/Adwaita/symbolic/status/audio-volume-muted-symbolic.svg
ICON_LOW=/usr/share/icons/Adwaita/symbolic/status/audio-volume-low-symbolic.svg
ICON_MED=/usr/share/icons/Adwaita/symbolic/status/audio-volume-medium-symbolic.svg
ICON_HIGH=/usr/share/icons/Adwaita/symbolic/status/audio-volume-high-symbolic.svg

get_volume() {
    pactl get-sink-volume @DEFAULT_SINK@ 2>/dev/null | awk '{ for (i=1;i<=NF;i++) if ($i ~ /^[0-9]+%$/) { sub("%", "", $i); print $i; exit } }'
}

get_muted() {
    pactl get-sink-mute @DEFAULT_SINK@ 2>/dev/null | grep -o 'yes'
}

vol_icon() {
    # $1 = vol, $2 = muted
    if [ "$2" = "yes" ] || [ "$1" -eq 0 ]; then
        printf '%s' "$ICON_MUTED"
    elif [ "$1" -le 33 ]; then
        printf '%s' "$ICON_LOW"
    elif [ "$1" -le 66 ]; then
        printf '%s' "$ICON_MED"
    else
        printf '%s' "$ICON_HIGH"
    fi
}

speaker_glyph() {
    # $1 = muted, $2 = vol
    if [ "$1" = "yes" ] || [ "$2" -eq 0 ]; then
        printf '%s' "$SPK_MUTE"
    elif [ "$2" -le 33 ]; then
        printf '%s' "$SPK_LOW"
    else
        printf '%s' "$SPK_HIGH"
    fi
}

fetch_art() {
    # $1 = mpris:artUrl ; sets global ART_FILE (empty if failed)
    ART_FILE=""
    [ -z "$1" ] && return 0
    case "$1" in
        file://*)
            f=${1#file://}
            case "$f" in
                *.png)          dst="$ART_DIR/art.png" ;;
                *.webp)         dst="$ART_DIR/art.webp" ;;
                *)              dst="$ART_DIR/art.jpg" ;;
            esac
            if [ -f "$f" ]; then cp -f "$f" "$dst" && ART_FILE="$dst"; fi
            ;;
        http://*|https://*)
            fn=$(printf '%s' "$1" | sed 's/.*\///' | cut -d'?' -f1)
            case "$fn" in
                *.png)          dst="$ART_DIR/art.png" ;;
                *.webp)         dst="$ART_DIR/art.webp" ;;
                *)              dst="$ART_DIR/art.jpg" ;;
            esac
            if curl -s -m 8 -o "$dst" "$1" && [ -s "$dst" ]; then
                ART_FILE="$dst"
                if [ "$dst" = "$ART_DIR/art.webp" ] && command -v magick >/dev/null 2>&1; then
                    magick "$dst" "$ART_DIR/art.png" 2>/dev/null && ART_FILE="$ART_DIR/art.png"
                fi
            fi
            ;;
    esac
}

cached_art() {
    # fastest: reuse cached thumbnail if present (volume key path)
    ART_FILE=""
    for c in art.png art.jpg art.webp; do
        if [ -f "$ART_DIR/$c" ]; then ART_FILE="$ART_DIR/$c"; break; fi
    done
}

show_card() {
    # $1 = art file (may be empty)  $2 = title  $3 = volume  $4 = glyph  $5 = artist
    art="$1"; title="$2"; vol="$3"; glyph="$4"; artist="$5"
    [ -z "$vol" ] && vol=0
    [ "$vol" -lt 0 ] && vol=0
    muted=$(get_muted)
    if [ "$muted" = "yes" ] || [ "$vol" -eq 0 ]; then
        vtext="Muted"
    else
        vtext="${vol}%"
    fi
    if [ -z "$title" ]; then
        # no media playing → volume-only card
        title="Volume"
        glyph=""
        art=""
    fi
    body="$(speaker_glyph "$muted" "$vol") Volume ${vtext}"
    [ -n "$artist" ] && body="$body\n$artist"
    # overdrive: volume >100% → recolor text + progress bar (warning) via category rule
    CAT=""
    [ "$vol" -gt 100 ] && CAT=" -h string:category:overdrive"
    if [ -n "$CAT" ]; then
        dunstify -a "Now Playing" -u normal -t 2000 \
            -h int:value:"$vol" -h string:x-dunst-stack-tag:media $CAT \
            -i "$(if [ -n "$art" ]; then printf '%s' "$art"; else printf '%s' "$(vol_icon "$vol" "$muted")"; fi)" \
            "$glyph $title" "$body"
    elif [ -n "$art" ]; then
        dunstify -a "Now Playing" -u normal -t 2000 -i "$art" \
            -h int:value:"$vol" -h string:x-dunst-stack-tag:media \
            "$glyph $title" "$body"
    else
        dunstify -a "Now Playing" -u normal -t 2000 -i "$(vol_icon "$vol" "$muted")" \
            -h int:value:"$vol" -h string:x-dunst-stack-tag:media \
            "$glyph $title" "$body"
    fi
}

case "$1" in
    volume)
        # ---- volume key handler ----
        ACT="$2"
        case "$ACT" in
            up)   pactl set-sink-volume @DEFAULT_SINK@ +2% ;;
            down) pactl set-sink-volume @DEFAULT_SINK@ -2% ;;
            mute) pactl set-sink-mute @DEFAULT_SINK@ toggle ;;
            *)    exit 1 ;;
        esac
        # current media info (fast query, cached art only)
        META=$(playerctl metadata -a -f '{{playerName}}|{{status}}|{{xesam:title}}|{{xesam:artist}}' 2>/dev/null)
        LINE=$(printf '%s\n' "$META" | grep -m1 '|Playing|')
        [ -z "$LINE" ] && LINE=$(printf '%s\n' "$META" | head -1)
        title=""; artist=""; glyph=""
        if [ -n "$LINE" ]; then
            status=$(printf '%s' "$LINE" | cut -d'|' -f2)
            title=$(printf '%s' "$LINE" | cut -d'|' -f3)
            artist=$(printf '%s' "$LINE" | cut -d'|' -f4)
            [ "$status" = "Playing" ] && glyph="▶"
            [ "$status" = "Paused" ] && glyph="⏸"
        fi
        cached_art
        show_card "$ART_FILE" "$title" "$(get_volume)" "$glyph" "$artist"
        ;;
    daemon)
        # ---- MPRIS watcher (poll 2s, thưa dần 5s khi không có player) ----
        LAST=""
        IDLE=0
        [ -f "$LAST_FILE" ] && LAST=$(cat "$LAST_FILE")
        while true; do
            META=$(playerctl metadata -a -f '{{playerName}}|{{status}}|{{mpris:trackid}}|{{mpris:artUrl}}|{{xesam:title}}|{{xesam:artist}}' 2>/dev/null)
            LINE=$(printf '%s\n' "$META" | grep -m1 '|Playing|')
            [ -z "$LINE" ] && LINE=$(printf '%s\n' "$META" | head -1)
            if [ -n "$LINE" ]; then
                IDLE=0
                player=$(printf '%s' "$LINE" | cut -d'|' -f1)
                status=$(printf '%s' "$LINE" | cut -d'|' -f2)
                trackid=$(printf '%s' "$LINE" | cut -d'|' -f3)
                art=$(printf '%s' "$LINE" | cut -d'|' -f4)
                title=$(printf '%s' "$LINE" | cut -d'|' -f5)
                artist=$(printf '%s' "$LINE" | cut -d'|' -f6)
                [ -z "$title" ] && title=$player
                if [ -n "$trackid" ]; then SIG="$player|$status|$trackid"; else SIG="$player|$status|$title"; fi
                if [ "$SIG" != "$LAST" ]; then
                    fetch_art "$art"
                    glyph=""
                    [ "$status" = "Playing" ] && glyph="▶"
                    [ "$status" = "Paused" ] && glyph="⏸"
                    show_card "$ART_FILE" "$title" "$(get_volume)" "$glyph" "$artist"
                    LAST=$SIG
                    printf '%s' "$SIG" > "$LAST_FILE"
                fi
            else
                IDLE=$((IDLE + 1))
            fi
            # Không có player: poll thưa dần để giảm fork vô ích (2s → 5s)
            if [ "$IDLE" -ge 3 ]; then
                sleep 2
            else
                sleep 2
            fi
        done
        ;;
    *)
        echo "usage: mediacard.sh volume up|down|mute | daemon" >&2
        exit 1
        ;;
esac

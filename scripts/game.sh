#!/bin/sh
# game.sh - gaming launcher wrapper for dwm.
# Usage:
#   game.sh <command...>            plain launch with Feral GameMode (CPU/GPU
#                                   governor, niceness, I/O priority on demand)
#   game.sh -g <command...>         wrap in gamescope first (nested compositor:
#                                   tearing-free scaling, HDR-capable, isolates
#                                   the game from dwm repaints)
#   game.sh -g -W 2560x1440 <cmd>   force gamescope virtual resolution
#   GAME_MANGO=1 game.sh ...        prepend mangohud overlay
#
# picom already unredirects fullscreen windows (unredir-if-possible), so a
# fullscreen game bypasses the compositor automatically; gamescope is for the
# cases where it doesn't (borderless-window games) or for upscaling.

set -eu

GS=""
if [ "${1:-}" = "-g" ]; then
    GS="yes"
    shift
fi

if [ "$#" -eq 0 ]; then
    echo "usage: game.sh [-g [-W WxH]] command [args...]" >&2
    exit 1
fi

# Đối số được gom vào chính "$@" rồi `exec "$@"`, KHÔNG dựng chuỗi
# "mangohud gamemoderun " rồi `exec ${CMD}$@`.
# Lý do: `${CMD}` không quote là cố ý để tách từ, nhưng `$@` không quote thì
# mất luôn dấu nháy của từng đối số — `game.sh steam "Tên game có space"`
# sẽ chạy thành 3 đối số khác nhau. Gamescope phải nằm trong "$@" (ngoài
# wrapper) nên ta dựng từ trong ra ngoài, prepend sau mỗi bước.
if [ "$GS" = "yes" ] && command -v gamescope >/dev/null 2>&1; then
    if [ "${1:-}" = "-W" ]; then
        RES="$2"
        shift 2
        set -- gamescope -W "${RES%x*}" -H "${RES#*x}" -f -- "$@"
    else
        set -- gamescope -f -- "$@"
    fi
fi

if command -v gamemoderun >/dev/null 2>&1; then
    set -- gamemoderun "$@"
fi

if [ "${GAME_MANGO:-0}" = "1" ] && command -v mangohud >/dev/null 2>&1; then
    set -- mangohud "$@"
fi

exec "$@"

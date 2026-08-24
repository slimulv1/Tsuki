#!/bin/sh
# netpanel.sh — mở panel quản lý mạng (gắn với click chuột trái vào statusbar)
# Ưu tiên netpanel (popup X11 thuần C tự vẽ); fallback nm-connection-editor / nmtui.
# Gọi từ dwm spawn nên cần định tuyến DISPLAY nếu chưa có.

NETPANEL="$HOME/dwm/netpanel/netpanel"

if ! xset -q >/dev/null 2>&1 && [ -n "$DISPLAY" ]; then
    : # DISPLAY có sẵn, ok
fi

if [ -x "$NETPANEL" ]; then
    exec "$NETPANEL"
elif command -v nm-connection-editor >/dev/null 2>&1; then
    exec nm-connection-editor
elif command -v nmtui >/dev/null 2>&1 && command -v st >/dev/null 2>&1; then
    exec st -e nmtui
else
    # nhắc qua dunst nếu chẳng có gì
    notify-send "netpanel" "Không tìm thấy netpanel hay nm-connection-editor" 2>/dev/null || true
    exit 1
fi

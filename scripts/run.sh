#!/bin/sh
#
# run.sh — điểm vào của session Tsuki (dwm).
#
# Chạy được từ hai nơi, cùng một đường:
#   - TTY:        startx            (đọc ~/.xinitrc, do install.sh sinh ra)
#   - DM:         Tsuki.desktop     (GDM/SDDM/LightDM quét /usr/share/xsessions)
#
# Không được giả định mình chạy từ display manager: startx không nạp
# ~/.profile, không có $DBUS_SESSION_BUS_ADDRESS, $XDG_RUNTIME_DIR có thể
# chưa có, và biến session của DM (GNOME/Wayland) có thể còn sót lại.
# Mọi thứ cần cho một session X sạch đều dựng ở đây.

set -u

# --- vị trí repo: suy ra từ chính script, không hardcode $HOME/dwm -----------
# Đặt sau $HOME để người dùng clone ở đường dẫn khác vẫn chạy được.
DWM_DIR="${TSUKI_DIR:-$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd -P)}"
export TSUKI_DIR="$DWM_DIR"

# startx không nạp profile login shell -> PATH không có /usr/local/bin,
# nơi `make install` đặt dwm/st/slock/dmenu/slstatus. Thiếu thì while type dwm
# thoát ngay và ta bị đá về màn hình đăng nhập mà không thấy cửa sổ nào.
PATH="/usr/local/bin:$PATH"
export PATH
export PATH="$DWM_DIR:$PATH"   # cho netpanel/imgdec nằm trong repo

# --- danh tính session ------------------------------------------------------
# GDM kế thừa nguyên bộ biến của session GNOME cho mọi session nó khởi chạy.
# Ta là dwm + X11, nên phải tự ghi đè trước khi bất kỳ tiến trình nào kế thừa.
# Nếu không: xdg-desktop-portal chạy dưới nhãn GNOME/Wayland trên X11 thật →
# FileChooser nhận lệnh và trả về request handle nhưng không dựng được cửa sổ
# (Save Image As / Lưu ảnh không hiện gì).
export XDG_CURRENT_DESKTOP=dwm
export XDG_SESSION_DESKTOP=dwm
export XDG_SESSION_TYPE=x11
export DESKTOP_SESSION=dwm

# startx có thể khởi động với XDG_RUNTIME_DIR trỏ vào thư mục không tồn tại
# (user cũ còn sót). Các app dùng nó sẽ lỗi âm thầm.
if [ -z "${XDG_RUNTIME_DIR:-}" ] || [ ! -d "${XDG_RUNTIME_DIR:-/nonexistent}" ]; then
    XDG_RUNTIME_DIR="/run/user/$(id -u)"
    [ -d "$XDG_RUNTIME_DIR" ] || XDG_RUNTIME_DIR="${TMPDIR:-/tmp}/tsuki-$(id -u)"
    mkdir -p "$XDG_RUNTIME_DIR" 2>/dev/null || true
    export XDG_RUNTIME_DIR
fi

# --- XWayland: KHÔNG dùng ---------------------------------------------------
# Tsuki chạy X11 thuần, không bật XWayland. Gói xorg-xwayland chỉ cài binary
# /usr/bin/Xwayland chứ không có hook nào bật trong X session, nên nếu muốn thì
# phải tự thêm khối dưới đây. Hiện để tắt có chủ đích: app Wayland-only chạy
# qua XWayland bị vỡ clipboard và không chia sẻ màn hình được.
#
# if ! pgrep -x Xwayland >/dev/null 2>&1; then
#     Xwayland :1 -rootless -noreset >/dev/null 2>&1 &
#     sleep 0.5
# fi
# export WAYLAND_DISPLAY=wayland-1

# --- phụ đơn vị: chạy nền, chết thì session vẫn sống --------------------------
# Mỗi thứ một hàm + pidfile: không thêm process group mới, nên khi dwm chết
# (rebuild) các daemon này vẫn sống và không bị nhân bản.
start_daemon() {
    _name=$1; shift
    _pid="$XDG_RUNTIME_DIR/tsuki-$_name.pid"
    if [ -f "$_pid" ] && kill -0 "$(cat "$_pid" 2>/dev/null)" 2>/dev/null; then
        return 0                      # đã chạy, không spawn lần hai
    fi
    "$@" >/dev/null 2>&1 &
    echo $! >"$_pid"
}

# --- nền desktop ------------------------------------------------------------
[ -f "$HOME/.Xresources" ] && xrdb -merge "$HOME/.Xresources" &

WALLPAPER=$(cat "$DWM_DIR/scripts/.wallpaper" 2>/dev/null)
if [ -n "${WALLPAPER:-}" ] && [ -f "$WALLPAPER" ]; then
    feh --bg-fill "$WALLPAPER" &
elif [ -f "$HOME/Pictures/Wallpapers/japanese.jpg" ]; then
    feh --bg-fill "$HOME/Pictures/Wallpapers/japanese.jpg" &
else
    # Không có ảnh nào: vẽ nền đen bằng feh thay vì để X màu xám xịt.
    feh --bg-solid '#1a1a1a' &
    notify-send "tsuki" "Chưa có ảnh nền — đặt ảnh vào scripts/.wallpaper" 2>/dev/null || true
fi

xset r rate 200 50 &
picom &

# polkit-gnome authentication agent (cần cho popup mật khẩu của pkexec/sudo)
[ -x /usr/lib/polkit-gnome/polkit-gnome-authentication-agent-1 ] &&
    /usr/lib/polkit-gnome/polkit-gnome-authentication-agent-1 &

# --- fcitx5 -----------------------------------------------------------------
export GTK_IM_MODULE=fcitx
export QT_IM_MODULE=fcitx
export XMODIFIERS=@im=fcitx
command -v fcitx5 >/dev/null 2>&1 && start_daemon fcitx fcitx5 -d

# --- status bar -------------------------------------------------------------
# slstatus binary trong repo (dwmwal.sh rebuild + đổi màu theo wallpaper, không
# cần root). Vòng lặp tự phục hồi: nếu slstatus chết/bị kill (vd dwmwal pkill)
# thì restart ngay — bar không bao giờ trống.
SLSTATUS="$DWM_DIR/slstatus/slstatus"
[ -x "$SLSTATUS" ] || SLSTATUS="$(command -v slstatus 2>/dev/null || true)"

if [ -n "$SLSTATUS" ]; then
    (
        while :; do
            "$SLSTATUS"
            sleep 0.5
        done
    ) >/dev/null 2>&1 &
    echo $! >"$XDG_RUNTIME_DIR/tsuki-slstatus.pid"
fi

# --- daemon nền -------------------------------------------------------------
# updates-loop.sh tự flock nên gọi lại vô hại; mediacard.sh có chế độ daemon.
[ -f "$DWM_DIR/scripts/updates-loop.sh" ] &&
    start_daemon updates dash "$DWM_DIR/scripts/updates-loop.sh"
[ -f "$DWM_DIR/scripts/mediacard.sh" ] &&
    start_daemon mediacard dash "$DWM_DIR/scripts/mediacard.sh" daemon

# --- dwm --------------------------------------------------------------------
# Vòng lặp, không exec. Super+Shift+R -> scripts/rebuild.sh -> killall dwm:
# không có vòng lặp thì dwm chết là X session chết theo, ta bị đá về TTY giữa
# lúc đang code. Có vòng lặp thì binary mới được nạp và bạn không mất context.
#
# exit 0 = người dùng chủ động thoát (Super+Ctrl+Q trong config.h) -> kết thúc
# hẳn session, quay về TTY. Mọi exit code khác (crash, bị signal) -> nạp lại.
while type dwm >/dev/null 2>&1; do
    dwm
    _rc=$?
    [ "$_rc" -eq 0 ] && exit 0
    sleep 0.3
done

# Không có `dwm` trong PATH: binary chưa build hoặc startx không nạp profile.
echo "tsuki: không tìm thấy 'dwm' trong PATH — chạy ./install.sh build" >&2
exit 127

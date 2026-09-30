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
TSUKI_DIR="${TSUKI_DIR:-$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd -P)}"
export TSUKI_DIR
# Alias tương thích: script cũ / dotfile cá nhân từng đọc $DWM_DIR. Giữ để
# không vỡ gì; nội bộ Tsuki chỉ dùng TSUKI_DIR — khỏi hai tên cho một thứ.
export DWM_DIR="$TSUKI_DIR"

# startx không nạp profile login shell -> PATH không có /usr/local/bin,
# nơi `make install` đặt dwm/st/slock/dmenu/slstatus. Thiếu thì while type dwm
# thoát ngay và ta bị đá về màn hình đăng nhập mà không thấy cửa sổ nào.
PATH="/usr/local/bin:$PATH"
export PATH

# $TSUKI_DIR/dmenu ĐỨNG TRƯỚC /usr/local/bin — đây là chỗ duy nhất dmenu lấy
# màu mới. `dmenu_run` (script trong /usr/local/bin) gọi `dmenu` và `dmenu_path`
# BẰNG TÊN trần, nên nó lấy bản đầu tiên trong PATH. Trước đây dwmwal.sh chỉ
# `make -C dmenu` (build trong repo) mà không cài, nên Super+R ra dmenu màu cũ
# vĩnh viễn, đổi wallpaper vô ích. Đặt thư mục build của repo trước là cách
# không cần root — cùng ý với cách slstatus chạy bản trong repo bên dưới.
# Nếu repo chưa build (mới clone) thì rơi về /usr/local/bin như cũ, an toàn.
export PATH="$TSUKI_DIR/dmenu:$TSUKI_DIR:$PATH"

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

# --- systemd user manager: đưa DISPLAY/XAUTHORITY vào môi trường -------------
#
# Vì sao: dunst và xdg-desktop-portal chạy dưới systemd --user (Type=dbus),
# không phải con trực tiếp của X. Khi khởi động bằng `startx`, systemd user
# manager KHÔNG có DISPLAY trong environment (startx không đi qua logind),
# nên khi app gọi org.freedesktop.Notifications thì systemd D-Bus-activate
# dunst.service -> ExecStart=/usr/bin/dunst, nhưng dunst không thấy DISPLAY:
#     WARNING: Cannot open X11 display.
#     CRITICAL: Couldn't initialize X11 output. Aborting...
# -> exit 1 -> start-limit-hit -> không có dịch vụ thông báo nào, phím
# volume im lặng, hộp thoại "Lưu ảnh" của Firefox không hiện.
#
# `systemctl --user import-environment` là đường đúng: đẩy biến của ta vào
# môi trường của systemd user manager, để unit đọc được DISPLAY thật.
systemctl --user import-environment DISPLAY XAUTHORITY 2>/dev/null || true

# --- nền desktop ------------------------------------------------------------
[ -f "$HOME/.Xresources" ] && xrdb -merge "$HOME/.Xresources" &

WALLPAPER=$(cat "$TSUKI_DIR/scripts/.wallpaper" 2>/dev/null)
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

# --- cursor: Bibata Modern Ice -----------------------------------------------
# X11 không có khái niệm "cursor theme" sẵn như GNOME/KDE. Xcursor spec quy định
# theme chỉ được dùng khi ẢNH CỦA NÓ được nạp vào CORE CURSOR FONT của X
# server, và đó là việc của ứng dụng (libXcursor), không phải của window manager.
# Vì vậy có 3 tầng, tầng nào cũng cần thiết cho một nhóm app khác nhau:
#
#   1) ~/.Xresources (Xcursor/Xcursor.size) + .config/gtk-3.0/settings.ini
#      -> app GTK3 (Firefox, Thunar, hộp thoại...). Không cần gì thêm.
#      settings.ini là tầng quan trọng nhất và chạy được ngay.
#
#   2) `xsetroot -xcf <file> <size>` ở đây -> set con trỏ cho ROOT WINDOW, nên
#      mọi cửa sổ KHÔNG tự gọi XDefineCursor sẽ kế thừa: dmenu (dmenu.c không
#      hề set cursor), desktop, app lạ chưa biết theme.
#      LƯU Ý cú pháp: xsetroot 1.1.x KHÔNG có -cursor_size, và -cursor_name
#      nhận TÊN FONT CORE (left_ptr, watch...), KHÔNG phải tên theme — dùng
#      `-cursor_name Bibata-Modern-Ice -cursor_size 24` sẽ báo lỗi. Cách duy
#      nhất xsetroot 1.1.4 nhận theme là -xcf <file .xc> <size>.
#
#   3) dwm và st thì KHÔNG nằm trong 2 tầng trên: cả hai đều tự tạo cursor bằng
#      XCreateFontCursor() (dwm.c -> XDefineCursor cho bar/tab/tag; st/x.c cho vùng
#      text), mà X11 hiện đại ĐÃ BỎ đường nạp theme vào core cursor font. Đo thực
#      tế: sau XcursorImagesLoadCursors() thì số đo font "cursor" của X server y
#      nguyên, nên XCreateFontCursor vẫn trả về bitmap mặc định. Vì vậy
#      drw_cur_load() (drw.c) và load_themed_cursor() (st/x.c) tự đọc file
#      <theme>/cursors/<tên> theo Xresources "Xcursor" rồi tạo cursor riêng cho
#      dwm và st. Không có hai hàm đó thì đây là 2 mũi tên xám giữa desktop đã
#      theme — cùng kiểu "cài xong nhìn không thấy gì đổi".
CURSOR_THEME=Bibata-Modern-Ice
CURSOR_SIZE=24
# Ưu tiên bản hệ thống (libXcursor chỉ tìm /usr/share/icons); bản ~/.local/share
# chỉ để dự phòng cho -xcf vì ở đó -xcf vẫn đọc được file theo đường dẫn tuyệt đối.
CURSOR_DIR=""
for d in "/usr/share/icons/$CURSOR_THEME/cursors" \
         "$HOME/.local/share/icons/$CURSOR_THEME/cursors"; do
    [ -r "$d/default" ] && { CURSOR_DIR="$d"; break; }
done
if [ -n "$CURSOR_DIR" ] && command -v xsetroot >/dev/null 2>&1; then
    xsetroot -xcf "$CURSOR_DIR/default" "$CURSOR_SIZE" 2>/dev/null || \
        warn_cursor "xsetroot -xcf thất bại"
else
    if [ -z "$CURSOR_DIR" ]; then
        warn_cursor "chưa cài theme cursor '$CURSOR_THEME' — chạy ./install.sh deps"
    else
        warn_cursor "thiếu xorg-xsetroot — chạy ./install.sh deps"
    fi
fi

# --- thông báo + portal ------------------------------------------------------
#
# Cả hai đều BẮT BUỘC cho hai thứ hay vấn đề nhất trên rice:
#   1. OSD/phím volume — gọi dunstify -> cần org.freedesktop.Notifications.
#      Không có dunst thì phím volume vẫn đổi âm lượng nhưng không hiện gì.
#   2. "Lưu ảnh" của Firefox — GTK4 dùng xdg-desktop-portal FileChooser.
#      Không có portal-gtk thì app nhận lệnh nhưng không dựng được cửa sổ.
#
# `systemctl --user start` (không phải chạy tay) để dunst đi đúng con đường
# D-Bus mà app gọi tới. Vẫn cần bọc `|| true`: nếu không có systemd user bus
# (session rất cũ) thì bỏ qua, đừng làm hỏng cả session.
systemctl --user start xdg-desktop-portal.service xdg-desktop-portal-gtk.service 2>/dev/null || true
systemctl --user start dunst.service 2>/dev/null || true

# polkit-gnome authentication agent (cần cho popup mật khẩu của pkexec/sudo)
[ -x /usr/lib/polkit-gnome/polkit-gnome-authentication-agent-1 ] &&
    /usr/lib/polkit-gnome/polkit-gnome-authentication-agent-1 &

# --- fcitx5 -----------------------------------------------------------------
# 5 biến, khớp với khối `if status is-login` trong .config/fish/config.fish.
# Thiếu SDL và GLFW thì app SDL/GLFW (game, mpv, ...) chạy từ dwm không gõ
# được — biến trong config.fish chỉ có tác dụng với shell fish, app được
# dwm spawn thì kế thừa môi trường ở đây chứ không qua config.fish.
# GLFW_IM_MODULE=ibus là cố ý: fcitx5 có frontend tương thích ibus cho app
# GLFW, đặt "fcitx" sẽ làm chúng không gõ được.
export GTK_IM_MODULE=fcitx
export QT_IM_MODULE=fcitx
export XMODIFIERS=@im=fcitx
export SDL_IM_MODULE=fcitx
export GLFW_IM_MODULE=ibus
command -v fcitx5 >/dev/null 2>&1 && start_daemon fcitx fcitx5 -d

# --- xsettingsd --------------------------------------------------------------
# Daemon XSETTINGS cho app GTK. install.sh cài gói + repo có sẵn
# .config/xsettingsd/xsettingsd.conf, nhưng trước đây KHÔNG ai khởi động nó,
# nên cả file config là cấu hình chết.
#
# start_daemon tự kiểm tra pidfile nên login lần sau không spawn trùng. Cần
# `systemctl --user import-environment` (đã gọi ở trên) để nó thấy DISPLAY —
# không thì nó chết ngay với "Cannot open X11 display".
#
# KHÔNG kỳ vọng daemon này đổi con trỏ của dwm/st: xsettingsd không hỗ trợ
# cursor theme, và X11 không còn đường nạp theme vào core cursor font. Chi tiết
# ở .config/xsettingsd/xsettingsd.conf và ở khối cursor phía trên.
command -v xsettingsd >/dev/null 2>&1 &&
    start_daemon xsettingsd xsettingsd -c "$TSUKI_DIR/.config/xsettingsd/xsettingsd.conf"

# --- status bar -------------------------------------------------------------
# slstatus binary trong repo (dwmwal.sh rebuild + đổi màu theo wallpaper, không
# cần root). Vòng lặp tự phục hồi: nếu slstatus chết/bị kill (vd dwmwal pkill)
# thì restart ngay — bar không bao giờ trống.
SLSTATUS="$TSUKI_DIR/slstatus/slstatus"
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
[ -f "$TSUKI_DIR/scripts/updates-loop.sh" ] &&
    start_daemon updates dash "$TSUKI_DIR/scripts/updates-loop.sh"
[ -f "$TSUKI_DIR/scripts/mediacard.sh" ] &&
    start_daemon mediacard dash "$TSUKI_DIR/scripts/mediacard.sh" daemon

# --- thumbnail cho trình quản lý file --------------------------------------
# Thunar không tự sinh ảnh nhỏ. Nó hỏi `tumblerd` qua D-Bus theo Thumbnailer
# Specification, tumbler mới gọi plugin (gdk-pixbuf cho ảnh,
# ffmpegthumbnailer cho video, poppler cho PDF) rồi ghi vào
# ~/.cache/thumbnails/ theo freedesktop.org Thumbnail Management Specification.
#
# Tumbler CÓ tự khởi động qua D-Bus activation
# (/usr/share/dbus-1/services/org.freedesktop.Tumbler.service). Khởi động tay
# ở đây vì hai lý do:
#   1. Phiên này khởi động bằng `startx` từ TTY — không có systemd user
#      session, nên activation của D-Bus không luôn bật.
#   2. start_daemon tự kiểm pidfile, không spawn trùng mỗi lần login.
command -v tumblerd >/dev/null 2>&1 && start_daemon tumbler tumblerd

# Thư mục cache thumbnail phải có mode 0700 — đúng quy định freedesktop,
# còn Thunar/tumbler tự tạo thì đặt 0755 và bị coi là không hợp lệ.
_thumb_dir="${XDG_CACHE_HOME:-$HOME/.cache}/thumbnails"
if [ -d "$_thumb_dir" ]; then
    chmod 700 "$_thumb_dir" 2>/dev/null
fi

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

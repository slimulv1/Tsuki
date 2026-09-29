#!/bin/sh

# --- Danh tính session ---
# GDM kế thừa nguyên bộ biến của session GNOME cho mọi session nó khởi chạy.
# Ta là dwm + X11, nên phải tự ghi đè trước khi bất kỳ tiến trình nào kế thừa.
# Nếu không: xdg-desktop-portal chạy dưới nhãn GNOME/Wayland trên X11 thật →
# FileChooser nhận lệnh và trả về request handle nhưng không dựng được cửa sổ
# (Save Image As / Lưu ảnh không hiện gì). Đặt ở đây, trước mọi lệnh khác.
export XDG_CURRENT_DESKTOP=dwm
export XDG_SESSION_DESKTOP=dwm
export DESKTOP_SESSION=dwm

xrdb -merge ~/.Xresources &
WALLPAPER=$(cat "$HOME/dwm/scripts/.wallpaper" 2>/dev/null || echo "$HOME/Pictures/Wallpapers/japanese.jpg")
feh --bg-fill "$WALLPAPER" &
xset r rate 200 50 &
picom &

# polkit-gnome authentication agent (needed for pkexec/sudo GUI prompts)
/usr/lib/polkit-gnome/polkit-gnome-authentication-agent-1 &

# fcitx5 input method
export GTK_IM_MODULE=fcitx
export QT_IM_MODULE=fcitx
export XMODIFIERS=@im=fcitx
fcitx5 -d &

# --- status bar: slstatus (thay bar.sh cũ; bar.sh dùng xsetroot ghi đè slstatus -> chớp) ---
# Dùng binary local (dwmwal.sh rebuild + đổi màu theo wallpaper, không cần root)
# Vòng lặp tự phục hồi: nếu slstatus chết/bị kill (vd dwmwal pkill) thì restart ngay
( while :; do "$HOME/dwm/slstatus/slstatus"; sleep 0.5; done ) >/dev/null 2>&1 &
# async updater: refresh ~/.cache/dwm-updates cho module updates của slstatus
dash ~/dwm/scripts/updates-loop.sh >/dev/null 2>&1 &
dash ~/dwm/scripts/mediacard.sh daemon >/dev/null 2>&1 &
while type dwm >/dev/null; do
    dwm
    # exit 0 = user quit (Super+Ctrl+Q) -> end session; other (crash/rebuild signal) -> relaunch
    [ "$?" -eq 0 ] && exit 0
    sleep 0.3
done

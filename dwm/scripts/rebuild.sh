#!/bin/sh
# Rebuild dwm & reload — kích hoạt bởi Super+Shift+R (config.h) và dwmwal.sh.
#
# Lưu ý:
#   - config.h, *.o và binary dwm đều thuộc root -> build phải chạy qua pkexec
#     (polkit-gnome agent trong run.sh sẽ hiện popup mật khẩu).
#   - KHÔNG dùng `make clean`: nó xóa config.h rồi tái tạo từ config.def.h,
#     làm mất các tùy chỉnh chỉ có trong config.h (font IBM Plex Sans JP, keybind zalo...).
#     Chỉ xóa object files để ép compile lại toàn bộ.
#   - run.sh chạy dwm từ /usr/local/bin nên cần `make install` sau khi build.
#   - `killall dwm` (SIGTERM) làm dwm thoát với exit code != 0 -> vòng lặp
#     run.sh tự relaunch bản mới sau 0.3s.

DWM_DIR="$HOME/dwm/dwm"

notify-send "dwm" "Rebuilding…" &

if pkexec sh -c "cd '$DWM_DIR' && rm -f drw.o dwm.o util.o && make && make install"; then
    # reload: run.sh sẽ khởi động lại dwm với binary mới
    killall dwm 2>/dev/null
    notify-send "dwm" "Rebuild OK — đã reload"
else
    notify-send -u critical "dwm" "Rebuild thất bại — xem log trong terminal"
    exit 1
fi
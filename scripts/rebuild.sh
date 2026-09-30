#!/bin/sh
# Rebuild dwm & reload — kích hoạt bỏi Super+Shift+R (config.h) và dwmwal.sh.
#
# Lưu ý:
#   - Thư mục repo: KHÔNG hardcode $HOME/dwm. run.sh export TSUKI_DIR, nên dwm
#     spawn được script này và TSUKI_DIR có sẵn trong môi trường. Khi chạy tay
#     (không qua dwm) thì suy ra từ vị trí script. Hardcode ~/dwm là sai ngay
#     khi clone ở chỗ khác -> `cd` fail -> build fail, keybind chết.
#   - CHỈ `make install` cần root (ghi vào /usr/local/bin). Phần compile chạy
#     với user thường: build bằng root sẽ tạo .o/config.h/dwm thuộc root, và
#     lần rebuild sau user thường sẽ báo "Permission denied" khi make muốn
#     ghi đè chúng.
#   - KHÔNG dùng `make clean`: nó xóa config.h rồi tái tạo từ config.def.h,
#     làm mất các tùy chỉnh chỉ có trong config.h (font IBM Plex Sans JP,
#     keybind zalo...). Chỉ xóa object files để ép compile lại toàn bộ.
#   - run.sh chạy dwm từ /usr/local/bin nên cần `make install` sau khi build.
#   - `killall dwm` (SIGTERM) làm dwm thoát với exit code != 0 -> vòng lặp
#     run.sh tự relaunch bản mới sau 0.3s.

TSUKI_DIR="${TSUKI_DIR:-$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd -P)}"
export TSUKI_DIR

LOG="${XDG_CACHE_HOME:-$HOME/.cache}/tsuki-rebuild.log"
mkdir -p "$(dirname -- "$LOG")" 2>/dev/null || true

if [ ! -f "$TSUKI_DIR/Makefile" ]; then
    notify-send -u critical "dwm" "Rebuild thất bại: không thấy $TSUKI_DIR/Makefile"
    exit 1
fi

notify-send "dwm" "Rebuilding…"

# --- 1) compile (user thường) ------------------------------------------------
# Ghi log ra file: dwm spawn script này ở nền, không có terminal nào để đọc
# lỗi — nếu chỉ có notify-send thì "xem log trong terminal" là vô nghĩa.
if ! ( cd "$TSUKI_DIR" && rm -f drw.o dwm.o util.o && make ) >"$LOG" 2>&1; then
    notify-send -u critical "dwm" "Rebuild thất bại (compile) — xem $LOG"
    exit 1
fi

# --- 2) install vào /usr/local/bin (cần root) --------------------------------
INSTALL_PREFIX=$(
    cd "$TSUKI_DIR" && make -pn 2>/dev/null |
        sed -n 's/^PREFIX = //p' | head -1
)
: "${INSTALL_PREFIX:=/usr/local}"

if [ -w "$INSTALL_PREFIX/bin" ]; then
    if ! ( cd "$TSUKI_DIR" && make install ) >>"$LOG" 2>&1; then
        notify-send -u critical "dwm" "Rebuild thất bại (install) — xem $LOG"
        exit 1
    fi
else
    # pkexec hiện popup mật khẩu (polkit-gnome agent trong run.sh lo phần hiển thị)
    if ! pkexec sh -c "cd '$TSUKI_DIR' && make install" >>"$LOG" 2>&1; then
        # install hỏng KHÔNG được killall: dwm cũ vẫn chạy tốt, chỉ là binary
        # trong /usr/local/bin chưa cập nhật. Killall ở đây sẽ chỉ khiến ta mất
        # session vì reload một binary cũ hoặc không có binary.
        notify-send -u critical "dwm" "Rebuild thất bại (install) — xem $LOG"
        exit 1
    fi
fi

# --- 3) reload: run.sh sẽ khởi động lại dwm với binary mới -------------------
killall dwm 2>/dev/null
notify-send "dwm" "Rebuild OK — đã reload"

#!/usr/bin/env dash
#
# check-thumbs — kiểm tra chuỗi sinh thumbnail cho trình quản lý file.
#
#   ./scripts/check-thumbs.sh          # kiểm tra, tự sinh thử ảnh + video
#   ./scripts/check-thumbs.sh --clean  # xoá sạch cache thumbnail trước khi thử
#
# Không cần root, không mở Thunar.
#
# Ghi chú kỹ thuật — những chỗ dễ sai:
#
#  1. Binary KHÔNG nằm trong PATH. Gói `tumbler` cài daemon ở
#     /usr/lib/tumbler-1/tumblerd, không phải /usr/bin/tumblerd. Dùng
#     `command -v tumblerd` là luôn báo thiếu dù đã cài. Đã mắc đúng lỗi này.
#
#  2. Tên D-Bus KHÔNG phải org.freedesktop.Tumbler. File đăng ký D-Bus tên là
#     org.xfce.Tumbler.*.service, nhưng bus name thật mà daemon nắm là
#     org.freedesktop.thumbnails.{Thumbnailer1,Manager1,Cache1} — xem
#     /usr/share/dbus-1/services/org.xfce.Tumbler.Thumbnailer1.service.
#
#  3. Method KHÔNG phải CreateThumbnail. Đó là API tumbler 1.x. API hiện tại
#     theo Thumbnailer Specification:
#       bus name   : org.freedesktop.thumbnails.Thumbnailer1
#       object path: /org/freedesktop/thumbnails/Thumbnailer1
#       method     : Queue(as uris, as mime_types, s flavor, s scheduler,
#                          u handle_to_unqueue) -> u handle
#       signals    : Ready(u handle, as uris) | Error(u handle, as failed, ...)
#     flavor: normal | large | x-large | xx-large
#     scheduler: default | foreground | background
#
#  4. Phải kiểm tra daemon KHỎE trước khi thử. Nếu còn một tumblerd cũ giữ
#     bus name rồi chết, daemon mới thoát ngay với "Name ... lost on the
#     message dbus, exiting" — lúc đó mọi lệnh đều trả về handle hợp lệ
#     nhưng không sinh thumbnail nào. Đã gặp đúng tình huống này.

set -u

CLEAN=0
[ "${1:-}" = --clean ] && CLEAN=1

C_RST=; C_B=; C_G=; C_Y=; C_R=
if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
    C_RST=$(printf '\033[0m'); C_B=$(printf '\033[1;34m')
    C_G=$(printf '\033[1;32m');  C_Y=$(printf '\033[1;33m')
    C_R=$(printf '\033[1;31m')
fi
FAIL=0
ok()   { printf '  %s✓%s %s\n' "$C_G" "$C_RST" "$*"; }
info() { printf '  %s·%s %s\n' "$C_B" "$C_RST" "$*"; }
bad()  { printf '  %s✗%s %s\n' "$C_R" "$C_RST" "$*"; FAIL=$((FAIL + 1)); }
warn() { printf '  %s!%s %s\n' "$C_Y" "$C_RST" "$*"; }
step() { printf '%s==>%s %s%s\n' "$C_B" "$C_RST" "$*" "$C_RST"; }
have() { command -v "$1" >/dev/null 2>&1; }

BUS=org.freedesktop.thumbnails.Thumbnailer1
OBJ=/org/freedesktop/thumbnails/Thumbnailer1
CACHE=${XDG_CACHE_HOME:-$HOME/.cache}/thumbnails

# Binary có thể nằm ở PATH (bản cũ) hoặc /usr/lib/tumbler-1/ (bản hiện tại).
find_tumblerd() {
    if have tumblerd; then
        command -v tumblerd
        return 0
    fi
    local p
    for p in /usr/lib/tumbler-1/tumblerd /usr/libexec/tumblerd /usr/bin/tumblerd; do
        [ -x "$p" ] && { printf '%s\n' "$p"; return 0; }
    done
    return 1
}

bus_alive() {
    have busctl || return 1
    busctl --user --no-pager list 2>/dev/null | grep -q "^$BUS"
}

# --- 1. gói ------------------------------------------------------------------
step "1. gói"
if TUMBLERD=$(find_tumblerd); then
    ok "tumblerd: $TUMBLERD"
    inpath=no
    have tumblerd && inpath=yes
    [ "$inpath" = no ] && info "nằm ngoài PATH — gọi bằng đường dẫn đầy đủ"
else
    bad "không thấy tumblerd — cài: sudo pacman -S tumbler"
    TUMBLERD=
fi
for p in ffmpegthumbnailer poppler-glib libopenraw freetype2; do
    if have pacman; then
        pacman -Qq "$p" >/dev/null 2>&1 \
            && ok "$p" || warn "$p chưa cài (plugin tương ứng sẽ không hoạt động)"
    fi
done
# Plugin video phải nằm trong thư mục plugin của tumbler, không chỉ có binary.
for so in tumbler-pixbuf-thumbnailer.so tumbler-ffmpeg-thumbnailer.so; do
    if [ -n "$TUMBLERD" ]; then
        d=${TUMBLERD%/*}
        if [ -f "$d/plugins/$so" ]; then
            ok "plugin $so"
        else
            bad "thiếu plugin $so (thư mục $d/plugins)"
        fi
    fi
done

# --- 2. daemon ---------------------------------------------------------------
step "2. daemon"
if bus_alive; then
    ok "$BUS đang được giữ (pid $(pgrep -x tumblerd | tr '\n' ' '))"
else
    warn "daemon chưa chạy — sẽ khởi động thử"
    if [ -n "$TUMBLERD" ]; then
        setsid "$TUMBLERD" >/dev/null 2>&1 </dev/null &
        # Chờ bus name xuất hiện; một instance cũ còn giữ tên sẽ làm daemon
        # mới chết ngay, nên kiểm tra nhiều lần thay vì một lần.
        i=0
        while [ $i -lt 10 ]; do
            sleep 1
            bus_alive && break
            i=$((i + 1))
        done
        if bus_alive; then
            ok "đã khởi động, bus name OK"
        else
            bad "khởi động không được. Có thể còn tumblerd cũ giữ bus name:"
            warn "  pkill -x tumblerd; $TUMBLERD"
        fi
    fi
fi

# --- 3. thư mục cache --------------------------------------------------------
step "3. thư mục cache"
if [ "$CLEAN" = 1 ]; then
    rm -rf "$CACHE"
    ok "đã xoá cache (--clean)"
fi
mkdir -p "$CACHE/normal" "$CACHE/large" "$CACHE/x-large" "$CACHE/xx-large" "$CACHE/fail"
chmod 700 "$CACHE"
perms=$(stat -c '%a' "$CACHE" 2>/dev/null)
if [ "$perms" = 700 ]; then
    ok "$CACHE (mode 700 — đúng spec freedesktop)"
else
    bad "$CACHE mode $perms, spec yêu cầu 700"
fi

# --- 4. thử sinh thật --------------------------------------------------------
step "4. thử sinh thumbnail (ảnh + video)"
if ! bus_alive || ! have gdbus; then
    warn "bỏ qua: cần daemon sống và gdbus"
else
    TD=$(mktemp -d) || { warn "không tạo được thư mục tạm"; exit 1; }
    trap 'rm -rf "$TD"' EXIT INT TERM

    convert -size 320x240 gradient:'#204080'-#f0a020 "$TD/anh.png" 2>/dev/null \
        || warn "không có ImageMagick, bỏ qua phần ảnh"
    ffmpeg -v error -f lavfi -i "testsrc=size=320x240:rate=8:duration=2" \
        -c:v libx264 -pix_fmt yuv420p -an -y "$TD/vid.mp4" 2>/dev/null \
        || warn "không có ffmpeg, bỏ qua phần video"

    try_one() { # file, mime, nhãn
        f=$1; mime=$2; label=$3
        [ -s "$f" ] || return 0
        u="file://$f"
        key=$(printf '%s' "$u" | md5sum | cut -d' ' -f1)
        rm -f "$CACHE/normal/$key.png"
        if ! gdbus call --session --dest "$BUS" --object-path "$OBJ" \
             --method "$BUS.Queue" "['$u']" "['$mime']" normal default 0 \
             >/dev/null 2>&1; then
            bad "$label: Queue() bị từ chối"
            return 0
        fi
        i=0
        while [ $i -lt 12 ]; do
            [ -f "$CACHE/normal/$key.png" ] && break
            sleep 1
            i=$((i + 1))
        done
        if [ -f "$CACHE/normal/$key.png" ]; then
            ok "$label: $(identify -format '%wx%h' "$CACHE/normal/$key.png" 2>/dev/null), $(stat -c%s "$CACHE/normal/$key.png") bytes"
        else
            bad "$label: Queue() trả handle nhưng không sinh ra file"
        fi
    }

    try_one "$TD/anh.png" image/png "ảnh png"
    try_one "$TD/vid.mp4" video/mp4 "video mp4"
    rm -rf "$TD"
fi

printf '\n'
if [ "$FAIL" -gt 0 ]; then
    printf '  %d mục lỗi\n' "$FAIL"
    exit 1
fi
printf '  xong — Thunar sẽ hiện thumbnail\n'

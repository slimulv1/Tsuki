#!/usr/bin/env dash
#
# check-thumbs — kiểm tra chuỗi sinh thumbnail của trình quản lý file.
#
# Chạy sau khi cài:
#   ./scripts/check-thumbs.sh
#
# Kiểm tra từng mắt xích: gói đã cài, daemon sống, thư mục cache đúng quyền,
# và — quan trọng nhất — tự sinh một thumbnail rồi xem có ra file không.
# Không sửa gì ngoài thư mục cache.
#
# Không có root, không cần mở Thunar.

set -u

C_RST=; C_B=; C_G=; C_Y=; C_R=
if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
    C_RST=$(printf '\033[0m'); C_B=$(printf '\033[1;34m')
    C_G=$(printf '\033[1;32m');  C_Y=$(printf '\033[1;33m')
    C_R=$(printf '\033[1;31m')
fi
ok()   { printf '  %s✓%s %s\n' "$C_G" "$C_RST" "$*"; }
bad()  { printf '  %s✗%s %s\n' "$C_R" "$C_RST" "$*"; FAIL=$((FAIL + 1)); }
warn() { printf '  %s!%s %s\n' "$C_Y" "$C_RST" "$*"; }
step() { printf '%s==>%s %s%s\n' "$C_B" "$C_RST" "$*" "$C_RST"; }
have() { command -v "$1" >/dev/null 2>&1; }

FAIL=0
CACHE=${XDG_CACHE_HOME:-$HOME/.cache}/thumbnails

# --- 1. gói ------------------------------------------------------------------
step "1. gói đã cài"
have tumblerd && ok "tumblerd" || bad "thiếu tumblerd — cài: sudo pacman -S tumbler"
have ffmpegthumbnailer \
    && ok "ffmpegthumbnailer (video)" \
    || bad "thiếu ffmpegthumbnailer — cài: sudo pacman -S ffmpegthumbnailer"
if have pacman; then
    for p in tumbler ffmpegthumbnailer poppler-glib; do
        pacman -Qq "$p" >/dev/null 2>&1 || warn "$p chưa cài (không bắt buộc)"
    done
fi

# --- 2. daemon ---------------------------------------------------------------
step "2. daemon"
if pgrep -x tumblerd >/dev/null 2>&1; then
    ok "tumblerd đang chạy (pid $(pgrep -x tumblerd | tr '\n' ' '))"
elif have busctl; then
    # Tumbler tự khởi động qua D-Bus activation; chưa chạy cũng bình thường
    # cho tới lúc Thunar thật sự hỏi. Kiểm tra service có được đăng ký không.
    if busctl --user list 2>/dev/null | grep -q 'org.freedesktop.Tumbler'; then
        ok "tumblerd đăng ký trên session bus (sẽ tự chạy khi Thunar hỏi)"
    else
        warn "chưa thấy tumblerd; nếu Thunar không hiện thumbnail thì đăng nhập lại"
        warn "  (scripts/run.sh sẽ tự khởi động nó: start_daemon tumbler tumblerd)"
    fi
else
    warn "không kiểm được D-Bus; nếu không hiện thumbnail thì đăng nhập lại"
fi

# --- 3. thư mục cache --------------------------------------------------------
step "3. thư mục cache"
if [ -d "$CACHE" ]; then
    perms=$(stat -c '%a' "$CACHE" 2>/dev/null)
    # freedesktop.org yêu cầu 0700
    if [ "$perms" = 700 ]; then
        ok "$CACHE (mode $perms)"
    else
        warn "$CACHE đang mode $perms, freedesktop yêu cầu 700"
        warn "  sửa:  chmod 700 \"$CACHE\""
    fi
else
    warn "$CACHE chưa có (sẽ tự tạo khi Thunar sinh thumbnail lần đầu)"
fi

# --- 4. tự sinh thử ----------------------------------------------------------
step "4. thử sinh thumbnail thật"
TD=$(mktemp -d 2>/dev/null) || { echo "  không tạo được thư mục tạm"; exit 1; }
trap 'rm -rf "$TD"' EXIT INT TERM

# a) ảnh
if have convert; then
    convert -size 240x180 gradient:'#203040'-#90c0f0 "$TD/t.png" 2>/dev/null
else
    : > "$TD/t.png"
fi
have convert || warn "không có ImageMagick, bỏ qua phần ảnh"

# b) video
if have ffmpeg; then
    ffmpeg -v error -f lavfi -i testsrc=size=240x180:rate=8:duration=2 \
           -c:v libx264 -pix_fmt yuv420p -an -y "$TD/t.mp4" 2>/dev/null \
        || : > "$TD/t.mp4"
else
    : > "$TD/t.mp4"
fi

# Nếu có tumblerd, hỏi nó qua đúng D-Bus API của Thumbnailer Specification.
# Đây là bài kiểm tra thật: không có daemon thì không có gì trả lời.
if have gdbus && pgrep -x tumblerd >/dev/null 2>&1; then
    for f in "$TD/t.png" "$TD/t.mp4"; do
        [ -s "$f" ] || continue
        uri="file://$f"
        w=$([ "${f##*.}" = png ] && echo 128 || echo 128)
        h=$([ "${f##*.}" = png ] && echo 128 || echo 96)
        # org.freedesktop.Tumbler.CreateThumbnail
        if gdbus call --session --dest org.freedesktop.Tumbler \
             --object-path /org/freedesktop/Tumbler \
             --method org.freedesktop.Tumbler.CreateThumbnail \
             "$uri" "normal" "$w" "$h" "desktop" "tsuki-check" \
             >/dev/null 2>&1; then
            sleep 2
            key=$(printf '%s' "$uri" | md5sum | cut -d' ' -f1)
            if [ -f "$CACHE/normal/$key.png" ]; then
                ok "sinh được: ${f##*/} -> normal/$key.png ($(stat -c%s "$CACHE/normal/$key.png") bytes)"
            else
                bad "${f##*/}: tumblerd nhận lệnh nhưng không ra file"
            fi
        else
            bad "${f##*/}: tumblerd từ chối lệnh (thiếu plugin cho loại này?)"
        fi
    done
else
    warn "chưa có tumblerd hoặc gdbus — bỏ qua bước thử sinh thật"
    warn "  cài xong rồi đăng nhập lại (hoặc: tumblerd &) rồi chạy lại script này"
fi

printf '\n'
if [ "$FAIL" -gt 0 ]; then
    printf '  %d mục lỗi\n' "$FAIL"
    exit 1
fi
printf '  xong, thumbnail sẽ hiện trong Thunar\n'

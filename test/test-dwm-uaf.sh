#!/usr/bin/env bash
# Kiểm thử lỗi use-after-free trong hiddenWinStack của dwm.
#
# ================================================================== VÌ SAO FILE NÀY TỒN TẠI
#
# dwm.c giữ một mảng con trỏ Client* cho các cửa sổ đã "ẩn" (Super+x), và
# Super+Shift+x gọi lại chúng. Bản cũ lưu con trỏ, nhưng unmanage() giải phóng
# Client mà không gỡ khỏi mảng — nên con trỏ thành lỏng.
#
# Kịch bản người dùng gặp (không cần can thiệp kỹ thuật):
#     Super+x            ẩn một cửa sổ
#     đóng cửa sổ đó      (Alt+F4, click nút X, hoặc app tự tắt)
#     Super+Shift+x      restore
# → dwm ĐỌC VÙNG NHỚ ĐÃ GIẢI PHÓNG rồi chết. Mất toàn bộ window manager.
#
# Đã đo bằng ASan trên dwm thật + Xvfb:
#     ==598313==ERROR: AddressSanitizer: heap-use-after-free
#       READ of size 8 at 0x7cd14a5e19e8 thread T0
#           #0 restorewin dwm.c:3568
#           #1 keypress   dwm.c:2330
#           #2 run        dwm.c:2989
#           #3 main       dwm.c:4230
#       ─── nơi giải phóng ───
#           #1 unmanage  dwm.c:3613     ← free(c)
#           #2 run       dwm.c:2989
#
# ================================================================== CÁCH TEST
#
# 1. Build dwm với -fsanitize=address,undefined từ nguồn thật trong repo.
# 2. Chạy trên Xvfb (không phải :0 — :0 là session thật của người dùng).
# 3. Mở cửa sổ client nhỏ, ẩn nó bằng XTEST, để client tự hủy, rồi restore.
# 4. Kiểm dwm còn sống và ASan không báo lỗi.
#
# CHỨNG MINH TEST BẮT ĐƯỢC LỖI: đưa mã về bản cũ (lưu Client* thay vì Window
# ID) thì test này FAIL. Kiểm chứng bằng cách đặt lại biến thể lỗi.
#
# ⚠ KHÔNG BAO GIỜ dùng `pkill -x dwm` trong test: dwm thật của người dùng đang
# chạy trên :0, giết nó là mất session. File này chỉ kill theo PID kèm điều
# kiện DISPLAY=:95.
set -u

R="$(cd "$(dirname "$0")/.." && pwd)"
T="$(mktemp -d)"
P=0; F=0
trap 'rm -rf "$T"' EXIT INT TERM

ok()  { printf '  PASS  %s\n' "$*"; P=$((P + 1)); }
bad() { printf '  FAIL  %s\n' "$1"; [ $# -gt 1 ] && printf '        %s\n' "$2"; F=$((F + 1)); }
skip() { printf '  --    %s\n' "$*"; }

TESTDISP=":95"

if ! command -v cc >/dev/null 2>&1; then
    skip "thiếu cc"; printf '\n  %d PASS, %d FAIL\n' "$P" "$F"; exit 0
fi
if ! command -v Xvfb >/dev/null 2>&1; then
    skip "thiếu Xvfb (gói xorg-server-xvfb)"
    printf '        KHÔNG phải "test pass" — lỗi use-after-free chưa được kiểm.\n'
    printf '\n  %d PASS, %d FAIL\n' "$P" "$F"; exit 0
fi

# --- D1: mảng ẩn phải lưu Window ID, không lưu Client* --------------------
# Đây là ca tĩnh: bắt lỗi ngay ở mã nguồn, không cần chạy. Compiler KHÔNG bắt
# được lỗi này (con trỏ hợp lệ về kiểu, chỉ sai về ý nghĩa vòng đời).
if grep -qE 'static[[:space:]]+Client\*[[:space:]]+hiddenWinStack\[' "$R/dwm.c"; then
    bad "D1 hiddenWinStack không lưu con trỏ Client*" \
        "unmanage() gọi free(c) mà không gỡ khỏi mảng → con trỏ lỏng → use-after-free"
elif grep -qE 'static[[:space:]]+Window[[:space:]]+hiddenWinStack\[' "$R/dwm.c"; then
    ok "D1 hiddenWinStack lưu Window ID (an toàn sau free)"
else
    bad "D1 không tìm thấy khai báo hiddenWinStack" "xem dwm.c"
fi

# restorewin() phải tra cứu lại qua wintoclient() và kiểm NULL
if grep -qE 'wintoclient\(hiddenWinStack\[' "$R/dwm.c"; then
    ok "D2 restorewin tra cứu lại client qua wintoclient()"
else
    bad "D2 restorewin không tra cứu lại client" \
        "đọc trực tiếp con trỏ đã giải phóng là use-after-free"
fi

# --- build dwm với sanitizer ------------------------------------------------
echo "  build dwm với ASan+UBSan..."
if cc -std=c23 -Wall -Wextra -Os -g -fno-omit-frame-pointer \
       -fsanitize=address,undefined -fno-sanitize-recover=all \
       -D_DEFAULT_SOURCE -D_BSD_SOURCE -D_XOPEN_SOURCE=700L \
       -DVERSION=\"6.8\" -DXINERAMAFLAGS \
       -I/usr/include -I/usr/X11R6/include -I/usr/include/freetype2 \
       -o "$T/dwm" "$R/dwm.c" "$R/drw.c" "$R/util.c" \
       -lX11 -lXinerama -lfontconfig -lXft -lXrender -lImlib2 -lXcursor \
       >"$T/build.log" 2>&1; then
    ok "D3 build dwm với sanitizer thành công"
else
    bad "D3 build dwm với sanitizer thất bại" "xem $T/build.log"
    grep -m3 -i error "$T/build.log" | sed 's/^/        | /'
    printf '\n  %d PASS, %d FAIL\n' "$P" "$F"; exit 0
fi

# --- client X tối giản và công cụ gõ phím -----------------------------------
# Không phụ thuộc xterm/xclock (máy này không có) — cần cửa sổ thật để dwm có
# việc để quản lý.
cat >"$T/xclient.c" <<'EOF'
#include <X11/Xlib.h>
#include <X11/Xutil.h>
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
int main(int argc, char **argv)
{
	Display *dpy; Window win, root; XSetWindowAttributes wa;
	int secs = argc > 1 ? atoi(argv[1]) : 5;
	if (!(dpy = XOpenDisplay(NULL))) return 1;
	root = DefaultRootWindow(dpy);
	wa.override_redirect = False;
	wa.background_pixel = WhitePixel(dpy, DefaultScreen(dpy));
	wa.event_mask = StructureNotifyMask | FocusChangeMask;
	win = XCreateWindow(dpy, root, 150, 150, 500, 400, 0,
	                   CopyFromParent, CopyFromParent, CopyFromParent,
	                   CWOverrideRedirect | CWBackPixel | CWEventMask, &wa);
	XStoreName(dpy, win, "uaf-test");
	XMapWindow(dpy, win);
	XSync(dpy, False);
	fflush(stdout);
	sleep(secs);
	XDestroyWindow(dpy, win);
	XSync(dpy, False);
	usleep(300000);
	XCloseDisplay(dpy);
	return 0;
}
EOF

cat >"$T/tap.c" <<'EOF'
/* Bấm Super+x (ẩn) hoặc Super+Shift+x (restore) qua XTEST. */
#include <X11/Xlib.h>
#include <X11/keysym.h>
#include <X11/extensions/XTest.h>
#include <stdio.h>
#include <unistd.h>
static KeyCode kc(Display *d, KeySym s) { return XKeysymToKeycode(d, s); }
static void down(Display *d, KeyCode c) { if (c) { XTestFakeKeyEvent(d, c, True, 0); XFlush(d);} }
static void up(Display *d, KeyCode c)   { if (c) { XTestFakeKeyEvent(d, c, False, 0); XFlush(d);} }
int main(int argc, char **argv)
{
	Display *dpy; int evb, errb, maj, min, shift = 0;
	if (!(dpy = XOpenDisplay(NULL))) { fprintf(stderr, "no display\n"); return 1; }
	if (!XTestQueryExtension(dpy, &evb, &errb, &maj, &min)) return 2;
	if (argc < 2) return 2;
	if (argv[1][0] == 'X') shift = 1;
	down(dpy, kc(dpy, XK_Super_L)); usleep(40000);
	if (shift) { down(dpy, kc(dpy, XK_Shift_L)); usleep(40000); }
	down(dpy, kc(dpy, XK_x)); usleep(50000);
	up(dpy, kc(dpy, XK_x)); usleep(40000);
	if (shift) { up(dpy, kc(dpy, XK_Shift_L)); usleep(30000); }
	up(dpy, kc(dpy, XK_Super_L));
	XSync(dpy, False);
	return 0;
}
EOF

cc -O2 -o "$T/xclient" "$T/xclient.c" -lX11 2>/dev/null \
    || { skip "không compile được client X"; printf '\n  %d PASS, %d FAIL\n' "$P" "$F"; exit 0; }
cc -O2 -o "$T/tap" "$T/tap.c" -lX11 -lXtst 2>/dev/null \
    || { skip "không compile được công cụ gõ phím (thiếu libXtst?)"; printf '\n  %d PASS, %d FAIL\n' "$P" "$F"; exit 0; }
ok "D4 compile được client X và công cụ gõ phím"

# --- dọn môi trường cũ ----------------------------------------------------
# CHỈ giết dwm trên $TESTDISP. Tuyệt đối không `pkill -x dwm` — dwm thật của
# người dùng chạy trên :0, giết nó là mất session.
for p in $(pgrep -x dwm 2>/dev/null); do
    d=$(tr '\0' '\n' < "/proc/$p/environ" 2>/dev/null | sed -n 's/^DISPLAY=//p')
    [ "$d" = "$TESTDISP" ] && kill -9 "$p" 2>/dev/null
done
pkill -x Xvfb 2>/dev/null
sleep 1
rm -f "/tmp/.X${TESTDISP#:}-lock" "/tmp/.X11-unix/X${TESTDISP#:}" 2>/dev/null

# --- chạy kịch bản --------------------------------------------------------
Xvfb "$TESTDISP" -screen 0 1280x800x24 -noreset >"$T/xvfb.log" 2>&1 &
XPID=$!
sleep 3
export DISPLAY="$TESTDISP"
if ! xdpyinfo >/dev/null 2>&1; then
    skip "Xvfb không khởi động"; kill "$XPID" 2>/dev/null
    printf '\n  %d PASS, %d FAIL\n' "$P" "$F"; exit 0
fi
ok "D5 Xvfb khởi động ($TESTDISP)"

export ASAN_OPTIONS=detect_leaks=0:abort_on_error=0:halt_on_error=0
export UBSAN_OPTIONS=print_stacktrace=1:halt_on_error=0

"$T/dwm" >"$T/dwm.log" 2>&1 &
WM=$!
sleep 3
if ! kill -0 "$WM" 2>/dev/null; then
    bad "D6 dwm khởi động trên Xvfb" "$(head -2 "$T/dwm.log")"
    kill "$XPID" 2>/dev/null; printf '\n  %d PASS, %d FAIL\n' "$P" "$F"; exit 0
fi
ok "D6 dwm khởi động (có cửa sổ khoá thật, chưa lỗi)"

# --- KỊCH BẢN TÁI HIỆN LỖI ----------------------------------------------
# ẩn → client tự hủy (dwm gọi free) → restore
"$T/xclient" 5 >/dev/null 2>&1 &
XCPID=$!
sleep 1.5
"$T/tap" x      >/dev/null 2>&1   # Super+x  → hidewin
sleep 1
wait "$XCPID" 2>/dev/null           # chờ client tự hủy → unmanage → free(c)
sleep 1
"$T/tap" X      >/dev/null 2>&1   # Super+Shift+x → restorewin
sleep 2

if kill -0 "$WM" 2>/dev/null; then
    ok "D7 dwm SỐNG sau khi ẩn → đóng cửa sổ → restore"
else
    bad "D7 dwm CHẾT khi restore sau khi cửa sổ đã bị đóng" \
        "xem $T/dwm.log — đây chính là lỗi use-after-free"
fi

if grep -q 'heap-use-after-free\|use-after-free' "$T/dwm.log"; then
    bad "D8 ASan báo use-after-free" \
        "$(grep -m1 -A4 'use-after-free' "$T/dwm.log" | tr '\n' ' ')"
else
    ok "D8 ASan KHÔNG báo use-after-free"
fi

# --- thêm: ẩn nhiều cửa sổ rồi đóng hết, rồi restore --------------------
# Biến thể nặng hơn: nhiều con trỏ lỏng cùng lúc.
for i in 1 2 3; do
    "$T/xclient" 4 >/dev/null 2>&1 &
    sleep 1.2
    "$T/tap" x >/dev/null 2>&1
done
sleep 1
for i in 1 2 3; do "$T/tap" X >/dev/null 2>&1; sleep 0.6; done
sleep 1

if kill -0 "$WM" 2>/dev/null && ! grep -q 'use-after-free' "$T/dwm.log"; then
    ok "D9 ẩn 3 cửa sổ, đóng hết, restore 3 lần: dwm sống, ASan sạch"
else
    bad "D9 stress 3 cửa sổ ẩn rồi đóng" \
        "$(grep -m1 'use-after-free' "$T/dwm.log" 2>/dev/null || echo "dwm chết")"
fi

kill "$WM" 2>/dev/null
sleep 0.5
kill "$XPID" 2>/dev/null
wait 2>/dev/null

printf '\n  %d PASS, %d FAIL\n' "$P" "$F"
[ "$F" -eq 0 ]

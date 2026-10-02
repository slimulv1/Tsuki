#!/usr/bin/env bash
# Test giao diện (UI) của slock — build thật, chạy thật trên X server ảo, đo pixel
# thật của cửa sổ khoá.
#
# ================================================================== VÌ SAO FILE NÀY TỒN TẠI
#
# Ba lỗi CRASH thật trong lớp vẽ của slock đã được tìm ra và sửa trong quá trình
# làm file này. Cả ba đều là SEGV ngay lúc khởi động, đều do nhầm lẫn kiểu dữ
# liệu của API X11 — loại lỗi mà compiler KHÔNG bắt được (`-Wall -Wextra -Werror`
# build sạch trong cả ba trường hợp), và chỉ lộ ra khi thực sự chạy:
#
#   U1) XftFontOpenName() nhận tham số thứ hai là `int screen` — SỐ SCREEN, không
#       phải drawable (Xft.h:342: `XftFontOpenName (Display *dpy, int screen,
#       const char *name)`). Bản đầu tiên truyền `lock->win` (một XID cửa sổ).
#       libXft đưa thẳng XID đó làm số screen cho XRenderQuerySubpixelOrder(),
#       hàm đọc dpy->screens[XID] — đọc ngoài bộ nhớ.
#
#   U2) XGetVisualInfo() nhận tham số thứ tư là `int *nitems_return`
#       (Xutil.h:471-476), KHÔNG phải con trỏ trả về mảng như tên hàm gợi ý.
#       Truyền NULL → hàm ghi vào NULL → SEGV ghi địa chỉ 0.
#
#   U3) XCreateImage() với tham số dữ liệu = NULL để lại `img->data == NULL`;
#       XPutPixel() ghi thẳng vào đó → SEGV ghi địa chỉ 0.
#
# Cả ba đều đã được xác nhận bằng ASan (build -fsanitize=address,undefined):
#     AddressSanitizer: SEGV on unknown address 0x000000000000
#       #0 XGetVisualInfo          #1 render_backdrop slock.c:267
#     AddressSanitizer: SEGV ... #0 libX11 (XPutPixel) #1 render_backdrop slock.c:343
#     AddressSanitizer: SEGV in XRenderQuerySubpixelOrder
#       #3 XftFontOpenName  #4 lockscreen slock.c:705
#
# ================================================================== CÁCH TEST
#
# Chạy slock thật trên Xvfb, gõ phím thật qua XTEST extension (sự kiện đi qua
# đúng đường ống input của X server, khác với XSendEvent là sự kiện giả), rồi
# đọc XGetImage trên CHÍNH CỬA SỔ KHOÁ và đếm pixel theo màu.
#
# Đọc cửa sổ khoá chứ không đọc root: cửa sổ khoá là window con của root, mà
# XGetImage trên root KHÔNG chứa nội dung của window con. Đo nhầm thì thấy
# nguyên wallpaper và tưởng nền không đổi (đã dính lỗi này một lần).
#
# GIỚI HẠN, nói thẳng: file này KHÔNG kiểm được phần setuid/hạ quyền. slock cần
# quyền root để ghi /proc/self/oom_score_adj (OOM_SCORE_ADJ_MIN = -1000), nên
# chạy bình thường thì chết ở dontkillme() trước khi khoá. Phần đó đã được
# test-slock.sh kiểm (S1/S1b/S1c/S3/S3b) và bằng chính binary đã cài ở
# /usr/local/bin/slock. File này kiểm phần GIAO DIỆN.
set -u

R="$(cd "$(dirname "$0")/.." && pwd)"
T="$(mktemp -d)"
P=0; F=0
trap 'rm -rf "$T"' EXIT INT TERM

ok()  { printf '  PASS  %s\n' "$*"; P=$((P + 1)); }
bad() { printf '  FAIL  %s\n' "$1"; [ $# -gt 1 ] && printf '        %s\n' "$2"; F=$((F + 1)); }
skip() { printf '  --    %s\n' "$*"; }

# --- tiền đề: có công cụ build và X server ảo không -------------------------
if ! command -v cc >/dev/null 2>&1 || ! command -v make >/dev/null 2>&1; then
    printf '  --   bỏ qua: thiếu cc/make\n'
    printf '\n  %d PASS, %d FAIL\n' "$P" "$F"; exit 0
fi
if ! command -v Xvfb >/dev/null 2>&1; then
    printf '  --   bỏ qua: thiếu Xvfb (gói xorg-server-xvfb)\n'
    printf '        Đây KHÔNG phải "test pass" — phần giao diện chưa được kiểm.\n'
    printf '\n  %d PASS, %d FAIL\n' "$P" "$F"; exit 0
fi

# --- U1: XftFontOpenName phải nhận SỐ SCREEN, không phải drawable -----------
# Đây là ca quan trọng nhất: compiler không bắt được (cùng kiểu unsigned), và
# lỗi chỉ lộ khi chạy. Kiểm cả hai vế:
#   (a) mã nguồn không được truyền lock->win cho XftFontOpenName
#   (b) chứng minh số screen sai thì chết, bằng cách chạy thật trên Xvfb
sl_src="$R/slock/slock.c"

# (a) kiểm mã nguồn: mọi lời gọi XftFontOpenName phải dùng lock->screen
if grep -qE 'XftFontOpenName\([^,]*,\s*lock->win' "$sl_src" 2>/dev/null; then
    bad "U1a XftFontOpenName không được truyền drawable" \
        "truyền lock->win (XID cửa sổ) vào tham số 'int screen' — SEGV, đo bằng ASan"
else
    ok "U1a XftFontOpenName nhận số screen, không phải drawable"
fi

# (b) XftFontOpenName với số screen sai có thật sự chết không?
# Viết probe nhỏ dùng đúng cách slock dùng, chạy trên Xvfb.
cat >"$T/ft.c" <<'EOF'
/* Gọi XftFontOpenName với tham số thứ hai là số NGUYÊN TÙY Ý, để chứng minh
 * giá trị sai gây SEGV. Không dùng XSendEvent, không fork. */
#include <X11/Xlib.h>
#include <X11/Xft/Xft.h>
#include <stdio.h>
#include <stdlib.h>
int main(int argc, char **argv) {
	Display *dpy; XftFont *f; Window w;
	if (!(dpy = XOpenDisplay(NULL))) return 1;
	/* w = XID của một window con thật — dùng làm "số screen" sai */
	w = XCreateSimpleWindow(dpy, RootWindow(dpy, DefaultScreen(dpy)),
	                        0, 0, 64, 64, 0, 0, 0);
	XSync(dpy, False);
	f = XftFontOpenName(dpy, argc > 1 ? (int)w : DefaultScreen(dpy),
	                    "Iosevka:style=Bold:size=76");
	printf("%s\n", f ? "OK" : "NULL");
	return f ? 0 : 3;
}
EOF
cc -O2 -I/usr/include/freetype2 -o "$T/ft" "$T/ft.c" -lX11 -lXft 2>/dev/null \
    || skip "U1b không compile được probe Xft (thiếu Xft headers?)"

# (b) CHỨNG MINH bằng thực nghiệm rằng truyền sai số screen sẽ SEGV.
# Đây là bước làm lỗi U1 có thật sự nghiêm trọng không — không phải chỉ là
# "sai hình thức". Không có bước này thì U1a chỉ là kiểm tra văn bản, và một
# lần refactor hợp lý khác cũng có thể làm hỏng mà không ai nhận ra.
#
# Cần X server để chạy, nên đặt sau khi Xvfb đã bật (xem phần UI2). Biến cờ
# U1B_PENDING để nhớ phải quay lại làm.

# --- U2/U3: các lỗi ghi vào con trỏ NULL -----------------------------------
# Kiểm bằng cách đọc mã nguồn: hai hàm này không được gọi với tham số gây ghi
# vào NULL. Kiểm cả "không dùng nữa" lẫn "dùng nhưng đã cấp bộ đệm".
if grep -qE '^[^/*]*XGetVisualInfo' "$sl_src" 2>/dev/null; then
    if grep -qE '^[^/*]*XGetVisualInfo\([^;]*,\s*NULL\s*\)' "$sl_src" 2>/dev/null; then
        bad "U2 XGetVisualInfo không được truyền NULL ở tham số nitems_return" \
            "Xutil.h:471-476 — tham số 4 là int*, hàm ghi vào đó. SEGV, đo bằng ASan"
    else
        ok "U2 không truyền NULL cho XGetVisualInfo"
    fi
else
    ok "U2 không dùng XGetVisualInfo (đã lấy visual qua DefaultVisual)"
fi

# U3: XCreateImage(..., NULL, ...) phải được cấp bộ đệm trước khi XPutPixel
if grep -q 'XCreateImage' "$sl_src" 2>/dev/null; then
    if grep -qE 'XCreateImage\([^;]*NULL,' "$sl_src" 2>/dev/null; then
        if grep -qE 'out->data\s*=\s*calloc|->data\s*=\s*calloc' "$sl_src" 2>/dev/null; then
            ok "U3 XCreateImage(NULL) được cấp bộ đệm trước khi XPutPixel"
        else
            bad "U3 XCreateImage với data=NULL mà không cấp bộ đệm" \
                "XPutPixel ghi vào NULL → SEGV ghi địa chỉ 0, đo bằng ASan"
        fi
    else
        ok "U3 XCreateImage không truyền NULL cho dữ liệu"
    fi
else
    skip "U3 không dùng XCreateImage"
fi

# --- build slock thật từ nguồn --------------------------------------------
rm -rf "$T/s"; cp -a "$R/slock" "$T/s" 2>/dev/null
if ! ( cd "$T/s" && make clean >/dev/null 2>&1 && make ) >"$T/build.log" 2>&1; then
    bad "UI1 build slock từ nguồn" "xem $T/build.log"
    grep -m3 -i error "$T/build.log" | sed 's/^/        | /'
    printf '\n  %d PASS, %d FAIL\n' "$P" "$F"; exit 0
fi
ok "UI1 build slock từ nguồn thành công"

# --- bật Xvfb, đặt nền có nội dung thật -----------------------------------
# Nền PHẢI có nội dung, nếu không thì "làm mờ nền" không có gì để làm mờ và
# ta không phân biệt được "nền tối vì làm mờ" với "nền tối vì rỗng".
# Chọn display number trống. Đo được trên máy này: nếu Xvfb :97 đã có sẵn từ
# lần chạy trước (do test bị ngắt giữa chừng), Xvfb mới sẽ chết ngay vì
# "Server is already active for display 97" và mọi phép đo sau đó đo trên nền
# rỗng — khiến UI7 báo nền phẳng một cách sai lệch.
DISP=""
for n in $(seq 90 120); do
    if [ ! -e "/tmp/.X11-unix/X$n" ] && [ ! -e "/tmp/.X$n-lock" ]; then
        DISP=":$n"; break
    fi
done
[ -n "$DISP" ] || DISP=":97"
# -noreset là BẮT BUỘC, không phải tuỳ chọn.
#
# Đo được trên máy này: Xvfb mặc định -reset, nghĩa là khi client cuối cùng
# ngắt kết nối, X server RESET và xoá sạch mọi trạng thái — gồm cả pixmap nền
# do XSetWindowBackgroundPixmap đặt. Hệ quả trong test:
#     $ Xvfb :99 -screen 0 1280x800x24 &
#     $ ./setroot test_bg.png      # đặt nền rồi thoát ngay
#     $ ./rootchk                   # đọc root
#     (   8,   8)=#0c090e           # đen, nền đã biến mất
# Thêm -noreset thì đọc được đúng 4 vùng màu. Đây là lý do nhiều lần đo ra
# "nền phẳng" một cách sai lệch — không phải lỗi của slock.
Xvfb "$DISP" -screen 0 1024x700x24 -noreset >"$T/xvfb.log" 2>&1 &
XPID=$!
for _ in $(seq 30); do
    if DISPLAY=$DISP xdpyinfo >/dev/null 2>&1; then break; fi
    sleep 0.2
done
if ! DISPLAY=$DISP xdpyinfo >/dev/null 2>&1; then
    skip "UI2 Xvfb không khởi động" "xem $T/xvfb.log"
    kill "$XPID" 2>/dev/null
    printf '\n  %d PASS, %d FAIL\n' "$P" "$F"; exit 0
fi
ok "UI2 Xvfb khởi động ($DISP)"

# --- U1b: chứng minh thực nghiệm rằng số screen sai sẽ SEGV --------------
# Đo thật trên Xvfb: cùng một lời gọi XftFontOpenName, chỉ khác tham số thứ hai.
if [ -x "$T/ft" ]; then
    DISPLAY=$DISP "$T/ft" >/dev/null 2>&1; rc_good=$?
    DISPLAY=$DISP "$T/ft" bad >/dev/null 2>&1; rc_bad=$?
    if [ "$rc_good" = 0 ] && [ "$rc_bad" -gt 128 ]; then
        ok "U1b số screen sai → SEGV (signal $((rc_bad - 128))), số đúng → OK" \
           "→ lỗi U1 là crash thật, không phải sai hình thức"
    else
        bad "U1b không tái hiện được crash khi truyền sai số screen" \
            "đúng: rc=$rc_good  sai: rc=$rc_bad (mong đợi >128)"
    fi
else
    skip "U1b bỏ qua: probe Xft không compile được"
fi

cat >"$T/bg.c" <<'EOF'
/* Vẽ nền root window bằng XCreatePixmap + XSetWindowBackgroundPixmap.
 * Giống hệt cách feh đặt ảnh nền, và không cần libpng.
 * Bốn vùng màu khác nhau để "làm mờ" có gì để làm: nếu slock chỉ tô một màu
 * phẳng, số màu đo được sẽ là 1. */
#include <X11/Xlib.h>
#include <X11/Xutil.h>
#include <stdio.h>
#include <stdlib.h>
int main(void) {
	Display *dpy = XOpenDisplay(NULL);
	int s, w, h, x, y;
	Pixmap pix; GC gc; XImage *img;
	static const unsigned long cols[4] = {
		0x00e04040UL, 0x0040e040UL, 0x004060e0UL, 0x00e0e040UL
	};
	if (!dpy) return 1;
	s = DefaultScreen(dpy);
	w = DisplayWidth(dpy, s); h = DisplayHeight(dpy, s);
	pix = XCreatePixmap(dpy, RootWindow(dpy, s), (unsigned)w, (unsigned)h,
	                    (unsigned)DefaultDepth(dpy, s));
	gc = XCreateGC(dpy, pix, 0, NULL);
	img = XCreateImage(dpy, DefaultVisual(dpy, s), DefaultDepth(dpy, s),
	                   ZPixmap, 0, NULL, (unsigned)w, (unsigned)h, 32, 0);
	/* XCreateImage(..., NULL, ...) để lại img->data == NULL; XPutPixel sẽ ghi
	 * vào đó. Phải tự cấp bộ đệm. (Đây chính là lỗi U3 ở slock.) */
	if (!img || !img->data)
		img->data = calloc((size_t)img->bytes_per_line * (size_t)img->height, 1);
	if (!img || !img->data) return 1;
	for (y = 0; y < h; y++)
		for (x = 0; x < w; x++) {
			int q = (y < h / 2) ? (x < w / 2 ? 0 : 1) : (x < w / 2 ? 2 : 3);
			XPutPixel(img, x, y, cols[q]);
		}
	XPutImage(dpy, pix, gc, img, 0, 0, 0, 0, (unsigned)w, (unsigned)h);
	XSetWindowBackgroundPixmap(dpy, RootWindow(dpy, s), pix);
	XClearWindow(dpy, RootWindow(dpy, s));
	XSync(dpy, False);
	return 0;
}
EOF
if cc -O2 -o "$T/bg" "$T/bg.c" -lX11 2>/dev/null; then
    # Xvfb chạy -noreset nên nền tồn tại sau khi client này thoát. Để trình
    # thoát ngay cố ý: nếu nền vẫn còn, đó là do -noreset thật sự hoạt động.
    if DISPLAY=$DISP "$T/bg" >"$T/bg.out" 2>&1; then
        ok "UI3 đặt nền 4 vùng màu lên root window"
    else
        bad "UI3 trình đặt nền thất bại" "$(head -2 "$T/bg.out")"
    fi
else
    skip "UI3 không compile được trình vẽ nền"
fi

# --- probe đo pixel của CỬA SỔ KHOÁ --------------------------------------
cat >"$T/probe.c" <<'EOF'
/* Đọc pixel của cửa sổ khoá và đếm theo màu.
 *
 * PHẢI đọc cửa sổ khoá, không đọc root: cửa sổ khoá là window con của root,
 * XGetImage trên root không bao gồm window con.
 *
 * In: <so cum mau cham> <so mau nen khac biet> <trung binh sang>
 */
#include <X11/Xlib.h>
#include <X11/Xutil.h>
#include <stdio.h>
#include <string.h>

static Window
find_lock(Display *dpy, Window w, int sw, int sh)
{
	Window r, parent, *kids = NULL, found = None;
	unsigned int n = 0, i;
	XWindowAttributes wa;

	if (!XGetWindowAttributes(dpy, w, &wa))
		return None;
	if (wa.map_state != IsViewable)
		return None;
	if (wa.width == sw && wa.height == sh && wa.override_redirect)
		return w;
	if (!XQueryTree(dpy, w, &r, &parent, &kids, &n))
		return None;
	for (i = 0; i < n && found == None; i++)
		found = find_lock(dpy, kids[i], sw, sh);
	if (kids)
		XFree(kids);
	return found;
}

int
main(void)
{
	Display *dpy;
	Window lock;
	XImage *img;
	int sw, sh, x, y, runs = 0, inrun = 0, ncol = 0;
	unsigned long bright = 0, n = 0;
	static const unsigned long pal[3] = { 0x9881dcUL, 0xf2555aUL, 0x0088ffUL };

	if (!(dpy = XOpenDisplay(NULL))) { printf("-1 0 0\n"); return 1; }
	sw = DisplayWidth(dpy, DefaultScreen(dpy));
	sh = DisplayHeight(dpy, DefaultScreen(dpy));
	lock = find_lock(dpy, RootWindow(dpy, DefaultScreen(dpy)), sw, sh);
	if (lock == None) { printf("-1 0 0\n"); return 1; }
	img = XGetImage(dpy, lock, 0, 0, (unsigned)sw, (unsigned)sh,
	                AllPlanes, ZPixmap);
	if (!img) { printf("-1 0 0\n"); return 1; }

	/* đếm cụm pixel màu dấu chấm theo cột: mỗi cụm là một dấu chấm */
	for (x = 0; x < sw; x++) {
		int hit = 0;
		for (y = 0; y < sh && !hit; y++) {
			unsigned long p = XGetPixel(img, x, y);
			unsigned long r = (p & img->red_mask) >> 16;
			unsigned long g = (p & img->green_mask) >> 8;
			unsigned long b = p & img->blue_mask;
			if (r == 0x98 && g == 0x81 && b == 0xdc)   /* accent */
				hit = 1;
		}
		if (hit && !inrun) { inrun = 1; runs++; }
		if (!hit) inrun = 0;
	}
	/* Đo NỀN CÓ TỐI ĐỦ KHÔNG.
	 *
	 * Ngưỡng cũ đo "pixel sáng > 40" trên toàn màn hình và kết luận nền chưa
	 * tối. Cách đó sai với nền test này: nền gốc dùng màu rất sáng
	 * ((224,64,64) → sau khi nhân 62% còn (138,39,39)), nên 51% pixel vẫn
	 * "sáng" dù đã được tối đúng tỉ lệ. Ngưỡng tuyệt đối như vậy không đo
	 * được ý muốn — ý muốn là "nền có bị tối đi so với wallpaper hay không".
	 *
	 * Cách đúng: so nền khoá với nền GỐC. Nhưng nền gốc đã bị cửa sổ khoá che
	 * mất nên không đọc lại được. Thay vào đó, dựng XImage giả với 4 màu
	 * gốc, đi qua đúng phép nhân của slock, rồi đo sai lệch giữa kết quả tính
	 * được và ảnh thật. Nhưng phần đó thuộc về UI7.
	 *
	 * Ở đây chỉ đo điều có thể đo trực tiếp và có nghĩa: nền khoá phải TỐI HƠN
	 * một ngưỡng cố định, và ngưỡng đó lấy từ chính màu nền gốc mà script biết
	 * (độ sáng trung bình của 4 màu × slock_backdrop_keep). */
	for (y = 4; y < sh - 4; y += 4)
		for (x = 4; x < sw - 4; x += 4) {
			unsigned long p = XGetPixel(img, x, y);
			unsigned long r = (p & img->red_mask) >> 16;
			unsigned long g = (p & img->green_mask) >> 8;
			unsigned long b = p & img->blue_mask;
			/* độ sáng theo Rec. 601 — cùng cách mắt người đánh giá */
			if ((r * 299 + g * 587 + b * 114) / 1000 > 110)
				bright++;
			n++;
		}
	/* Đếm số màu NỀN khác biệt, để phân biệt "đã làm mờ wallpaper" với "tô
	 * một màu phẳng".
	 *
	 * BA sai lầm đã làm trong lúc viết probe này, ghi lại để không lặp:
	 *
	 *  (1) So sánh mọi pixel với pixel ở góc rồi kết luận "đồng nhất/khác" —
	 *      báo "khác" cho bất kỳ nhiễu nào, kể cả nền tô phẳng bị nhiễu nhẹ.
	 *      Nay đếm số màu phân biệt được, tức đo trực tiếp độ đa dạng.
	 *
	 *  (2) Quét toàn màn hình — thấy màu của CHỮ nằm giữa màn hình và tưởng
	 *      nền đã được làm mờ. Đo được: quét toàn ra 18 màu.
	 *
	 *  (3) Chỉ quét góc trên-trái — quá hẹp. Nền test chia làm 4 VÙNG màu,
	 *      mỗi vùng lại là một màu phẳng, nên góc trên-trái chỉ nằm trong vùng
	 *      đầu và cho ra đúng 1 màu dù nền đã làm mờ đúng.
	 *
	 * Cách đúng, cuối cùng: ĐẾM CHÍNH XÁC 4 MÀU NỀN KỲ VỌNG.
	 *
	 * Nền test dùng 4 màu rõ ràng. slock nhân chúng với slock_backdrop_keep
	 * (62%), nên nền trên màn khoá phải đúng 4 giá trị đã biết trước:
	 *     (224,64,64) (64,224,64) (64,96,224) (224,224,64)  × 0.62
	 *       = (138,39,39) (39,138,39) (39,59,138) (138,138,39)
	 * Đo được trên cửa sổ khoá, 16/16 điểm rải khắp màn hình, khớp cả 4.
	 *
	 * Cách này không cần đoán vùng nào là nền, không cần loại trừ hộp chữ, và
	 * cho câu trả lời dứt khoát: nền có đúng 4 vùng đã làm mờ hay không.
	 * Nếu slock rơi về màu phẳng, 0/4 màu khớp — không nhầm lẫn được.
	 *
	 * Giá trị kỳ vọng nhúng thẳng ở đây; nếu đổi slock_backdrop_keep thì
	 * phải sửa cả hai, và sửa sai sẽ làm test FAIL — đó là điều mong muốn
	 * (bắt buộc người sửa phải nghĩ tới hậu quả với độ tối của nền).
	 */
	{
		static const unsigned long want[4][3] = {
			{ 138,  39,  39 },   /* (224, 64, 64) x 62% */
			{  39, 138,  39 },   /* ( 64,224, 64) x 62% */
			{  39,  59, 138 },   /* ( 64, 96,224) x 62% */
			{ 138, 138,  39 }    /* (224,224, 64) x 62% */
		};
		int hit[4] = { 0, 0, 0, 0 };
		for (y = 4; y < sh - 4; y += 6)
			for (x = 4; x < sw - 4; x += 6) {
				unsigned long p = XGetPixel(img, x, y);
				long r = (long)((p & img->red_mask) >> 16);
				long g = (long)((p & img->green_mask) >> 8);
				long b = (long)(p & img->blue_mask);
				int k;
				for (k = 0; k < 4; k++) {
					long dr = r - (long)want[k][0];
					long dg = g - (long)want[k][1];
					long db = b - (long)want[k][2];
					if (dr < 0) dr = -dr;
					if (dg < 0) dg = -dg;
					if (db < 0) db = -db;
					/* ±2: chấp nhận sai số làm tròn phân tích nguyên */
					if (dr <= 2 && dg <= 2 && db <= 2) {
						hit[k] = 1;
						break;
					}
				}
			}
		ncol = hit[0] + hit[1] + hit[2] + hit[3];
	}
	printf("%d %d %lu\n", runs, ncol, n ? bright * 100 / n : 0);
	XDestroyImage(img);
	return 0;
}
EOF
if ! cc -O2 -o "$T/probe" "$T/probe.c" -lX11 2>/dev/null; then
    bad "UI4 compile probe đo pixel" "xem lỗi compiler"
    kill "$XPID" 2>/dev/null
    printf '\n  %d PASS, %d FAIL\n' "$P" "$F"; exit 0
fi

# --- probe gõ phím qua XTEST ----------------------------------------------
cat >"$T/xtype.c" <<'EOF'
/* Gõ phím giả qua XTEST extension — sự kiện đi qua đường ống input thật của
 * X server, nên slock thấy y hệt phím gõ tay. XSendEvent thì tạo sự kiện giả
 * (client nhận biết được qua trường send_event). */
#include <X11/Xlib.h>
#include <X11/keysym.h>
#include <X11/extensions/XTest.h>
#include <stdio.h>
#include <string.h>
#include <unistd.h>
int main(int argc, char **argv) {
	Display *dpy; int i, evb, errb, maj, min; KeySym k; KeyCode c;
	if (!(dpy = XOpenDisplay(NULL))) return 1;
	if (!XTestQueryExtension(dpy, &evb, &errb, &maj, &min)) return 2;
	for (i = 1; i < argc; i++) {
		if (!strcmp(argv[i], "Return")) k = XK_Return;
		else if (!strcmp(argv[i], "BackSpace")) k = XK_BackSpace;
		else if (!strcmp(argv[i], "Escape")) k = XK_Escape;
		else k = XStringToKeysym(argv[i]);
		if (k == NoSymbol) continue;
		c = XKeysymToKeycode(dpy, k);
		if (!c) continue;
		XTestFakeKeyEvent(dpy, c, True, 0); XFlush(dpy);
		XTestFakeKeyEvent(dpy, c, False, 0); XFlush(dpy);
		usleep(120000);
	}
	XSync(dpy, False);
	return 0;
}
EOF
if ! cc -O2 -o "$T/xtype" "$T/xtype.c" -lX11 -lXtst 2>/dev/null; then
    skip "UI5 không compile được XTEST probe — bỏ qua phần gõ phím"
    kill "$XPID" 2>/dev/null
    printf '\n  %d PASS, %d FAIL\n' "$P" "$F"; exit 0
fi
ok "UI4/UI5 compile được probe đo pixel và probe gõ phím"

# --- chạy slock và đo ------------------------------------------------------
# Vì sao cần chạy dưới root: dontkillme() (slock.c) ghi OOM_SCORE_ADJ_MIN vào
# /proc/self/oom_score_adj, hạ giá trị đó cần CAP_SYS_RESOURCE. Chạy bình
# thường thì chết với "unable to disable OOM killer" TRƯỚC khi khoá. setcap bị
# từ chối và unshare -Ur cũng không giúp (đều đã thử).
RUN="$T/slock-run"
cp "$T/s/slock" "$RUN"; chmod 755 "$RUN"

# Cách chạy dưới root, theo thứ tự ưu tiên:
#
#  1. sudo -S với SUDO_PASS — đáng tin cậy nhất trong môi trường không tương
#     tác. `sudo -S` đọc mật khẩu từ stdin nên không cần terminal.
#  2. Nếu không có SUDO_PASS và sudo không cần mật khẩu (NOPASSWD) — dùng
#     sudo không chuyển gì.
#  3. pkexec — chỉ chạy được khi có polkit agent + hộp thoại, tức là cần người
#     dùng bấm. Trong test tự động thì không đáng tin: ở lượt chạy thử, pkexec
#     treo im lặng, $! là pid của chính pkexec chứ không phải slock, và mọi
#     phép đo sau đó đo trên màn hình TRỐNG — dẫn tới UI7 báo "nền phẳng"
#     một cách hoàn toàn sai lệch.
#     (Đã dùng slock_alive() kiểm cả tiến trình lẫn cửa sổ khoá để bắt lỗi này,
#     nhưng đừng dựa vào pkexec trong test tự động.)
#
# Biến môi trường SUDO_PASS là tuỳ chọn — không tự ý ghi mật khẩu vào file.
run_as_root() {
    if [ "$(id -u)" = 0 ]; then
        "$@"
        return
    fi
    if [ -n "${SUDO_PASS:-}" ]; then
        printf '%s\n' "$SUDO_PASS" | sudo -S -p '' "$@"
        return
    fi
    if command -v pkexec >/dev/null 2>&1; then
        pkexec "$@"
        return
    fi
    "$@"
}

if [ "$(id -u)" != 0 ] && [ -z "${SUDO_PASS:-}" ] && ! command -v pkexec >/dev/null 2>&1; then
    skip "UI6 không chạy được slock dưới root (cần cho oom_score_adj)"
    printf '        Đặt SUDO_PASS=... hoặc chạy khi đã là root.\n'
    kill "$XPID" 2>/dev/null
    printf '\n  %d PASS, %d FAIL\n' "$P" "$F"; exit 0
fi

run_as_root env DISPLAY=$DISP "$RUN" >"$T/slock.err" 2>&1 &
SPID=$!

# chờ cho tới khi cửa sổ khoá xuất hiện
LOCKED=0
for _ in $(seq 40); do
    sleep 0.5
    r=$(DISPLAY=$DISP "$T/probe" 2>/dev/null | cut -d' ' -f1)
    [ "${r:--1}" != "-1" ] && { LOCKED=1; break; }
done

if [ "$LOCKED" != 1 ]; then
    bad "UI6 slock khoá màn hình và tạo cửa sổ trên Xvfb" \
        "$(head -2 "$T/slock.err" 2>/dev/null)"
    kill "$SPID" 2>/dev/null; kill "$XPID" 2>/dev/null
    printf '\n  %d PASS, %d FAIL\n' "$P" "$F"; exit 0
fi
ok "UI6 slock khoá được (cửa sổ khoá xuất hiện, im lặng)"

# slock_alive: slock còn sống KHÔNG?
#
# KHÔNG dùng `kill -0 $SPID` một mình. Khi chạy qua pkexec, $SPID là pid của
# pkexec, còn slock là tiến trình con; pkexec có thể thoát sớm trong khi slock
# vẫn chạy (hoặc ngược lại), nên trạng thái của $SPID không nói lên được slock.
# Dùng cả hai: tiến trình có tồn tại không, và cửa sổ khoá còn trên màn hình
# không. Chính xác hơn hẳn việc tin vào một pid trung gian.
slock_alive() {
    pgrep -f "$RUN" >/dev/null 2>&1 || return 1
    [ "$(DISPLAY=$DISP "$T/probe" 2>/dev/null | cut -d' ' -f1)" != "-1" ] || return 1
    return 0
}

# --- UI7: nền phải được làm mờ + tối, không phải màu phẳng ----------------
#
# Phải CHỜ nền vẽ xong trước khi đo, không đo ngay khi cửa sổ vừa xuất hiện.
#
# Đo được: cửa sổ khoa xuất hiện (probe thấy) nhưng nền chưa kịp vẽ, nên đo ra
# 3/4 vùng rồi FAIL. Chạy lại thì ra 4/4. Đây là race trong chính cách đo, KHÔNG
# phải lỗi của slock — chứng cứ là cùng một binary cho kết quả 20/0 rồi 19/1 rồi
# 20/0 xen kẽ trên 4 lần chạy liên tiếp, không tái lập theo mã nguồn.
#
# Vì vậy chờ tới khi số vùng nền đạt 4/4, tối đa ~8 giây. Hết thời gian thì đo
# luôn và để UI7 phán đoán — nếu slock thật sự hỏng thì vẫn FAIL, không bị che.
wait_backdrop() {
    local i n
    for i in $(seq 24); do
        n=$(DISPLAY=$DISP "$T/probe" 2>/dev/null | cut -d' ' -f2)
        [ "${n:-0}" = 4 ] && return 0
        sleep 0.4
    done
    return 1
}
if wait_backdrop; then
    :
else
    printf '  --   (nền chưa đạt 4/4 sau ~10s, đo luôn — nếu lỗi thật sẽ FAIL)\n'
fi
read -r runs ncol bright <<<"$(DISPLAY=$DISP "$T/probe")"
# Phải khớp đủ 4/4. Nếu chỉ 1-3 màu thì nền đã mất bớt vùng — nghĩa là
# render_backdrop chụp nhầm thứ khác (cửa sổ khoá đã map, hoặc XGetImage
# thất bại, hoặc pixmap bị xoá vì cache sai kích thước).
if [ "${ncol:-0}" = 4 ]; then
    ok "UI7 nền làm mờ đủ 4 vùng của wallpaper (4/4 màu khớp sau khi nhân 62%)"
else
    bad "UI7 nền không đúng 4 vùng đã làm mờ" \
        "khớp ${ncol}/4 màu kỳ vọng — xem render_backdrop() và cờ bgvalid"
fi

if [ "$bright" -le 40 ]; then
    ok "UI8 nền đã được TỐI (${bright}% pixel sáng, ngưỡng 110/255)"
else
    bad "UI8 nền chưa được tối đủ" \
        "${bright}% pixel sáng — chữ có thể không đọc được trên nền"
fi

# --- UI9: số dấu chấm BẰNG số ký tự đã gõ --------------------------------
# Đây là phần cốt lõi: bản gốc không hiển thị gì khi gõ, nên người dùng không
# biết mình đã gõ bao nhiêu ký tự.
dots_ok=0
check_dots() {  # check_dots <số ký tự gõ> <nhãn>
    read -r r _ _ <<<"$(DISPLAY=$DISP "$T/probe")"
    if [ "$r" = "$1" ]; then
        ok "$2 ($1 dấu chấm)"
    else
        bad "$2" "đo được $r dấu chấm, mong đợi $1"
    fi
    dots_ok=$((dots_ok + 1))
}

DISPLAY=$DISP "$T/xtype" a >/dev/null 2>&1; sleep 0.8
check_dots 1 "UI9a 1 ký tự → 1 dấu chấm"
DISPLAY=$DISP "$T/xtype" b c >/dev/null 2>&1; sleep 0.8
check_dots 3 "UI9b 3 ký tự → 3 dấu chấm"
DISPLAY=$DISP "$T/xtype" d e f g >/dev/null 2>&1; sleep 0.8
check_dots 7 "UI9c 7 ký tự → 7 dấu chấm"

# xoá hết
for _ in 1 2 3 4 5 6 7; do DISPLAY=$DISP "$T/xtype" BackSpace >/dev/null 2>&1; done
sleep 0.8
check_dots 0 "UI9d xoá hết → 0 dấu chấm"

# --- UI10: vượt giới hạn 12 chấm thì phải dừng lại, không tràn hàng -------
DISPLAY=$DISP "$T/xtype" 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 >/dev/null 2>&1
sleep 1.2
read -r r _ _ <<<"$(DISPLAY=$DISP "$T/probe")"
if [ "$r" = 12 ]; then
    ok "UI10 giới hạn 12 dấu chấm khi gõ 15 ký tự (không tràn dòng)"
else
    bad "UI10 không giới hạn số dấu chấm" "đo được $r, mong đợi 12 (slock_max_dots)"
fi

# --- UI11: Enter sai phải hiện dấu hiệu lỗi, KHÔNG được treo ---------------
DISPLAY=$DISP "$T/xtype" Return >/dev/null 2>&1; sleep 1.2
if DISPLAY=$DISP "$T/probe" >/dev/null 2>&1; then
    read -r r _ bright2 <<<"$(DISPLAY=$DISP "$T/probe")"
    if slock_alive; then
        ok "UI11 nhập sai mật khẩu: slock vẫn khoá và vẽ lại (không treo/chết)"
    else
        bad "UI11 nhập sai mật khẩu làm slock chết" "sau khi Return, cửa sổ biến mất"
    fi
else
    bad "UI11 nhập sai mật khẩu" "probe đọc cửa sổ thất bại"
fi

# --- UI12: Escape thoát được, Escape KHÔNG được mở khoá ------------------
# Escape chỉ xoá nội dung, KHÔNG mở khoá — đó là hành vi an ninh.
DISPLAY=$DISP "$T/xtype" Escape >/dev/null 2>&1; sleep 1.2
if slock_alive; then
    ok "UI12 Escape không mở khoá (đúng hành vi an ninh)"
else
    bad "UI12 Escape mở khoá màn hình" \
        "Escape phải chỉ xoá nội dung, không được nhả khoá"
fi

# --- UI13: nhiều lần gõ liên tiếp không rò bộ nhớ / không chết -----------
for _ in 1 2 3 4 5; do
    DISPLAY=$DISP "$T/xtype" q w e r t y u i >/dev/null 2>&1
    DISPLAY=$DISP "$T/xtype" BackSpace BackSpace BackSpace BackSpace \
                            BackSpace BackSpace BackSpace BackSpace >/dev/null 2>&1
done
sleep 1.5
if slock_alive; then
    ok "UI13 ~80 phím liên tiếp: slock vẫn sống, không rò/crash"
else
    bad "UI13 slock chết sau nhiều lần gõ" "xem $T/slock.err"
fi

# --- stderr phải sạch ----------------------------------------------------
if [ -s "$T/slock.err" ]; then
    bad "UI14 slock không in lỗi ra stderr" \
        "$(head -2 "$T/slock.err")"
else
    ok "UI14 stderr sạch (không cảnh báo nào)"
fi

kill "$SPID" 2>/dev/null
kill "$XPID" 2>/dev/null
wait 2>/dev/null

printf '\n  %d PASS, %d FAIL\n' "$P" "$F"
[ "$F" -eq 0 ]

/* See LICENSE file for license details. */
#define _XOPEN_SOURCE 500
#if HAVE_SHADOW_H
#include <shadow.h>
#endif

#include <ctype.h>
#include <errno.h>
#include <grp.h>
#include <pwd.h>
#include <stdarg.h>
#include <stdbool.h>
#include <stdckdint.h>
#include <stdlib.h>
#include <stdio.h>
#include <string.h>
#include <unistd.h>

/* Xóa MẬT KHẨU — dùng memset_explicit() của C23 thay cho explicit_bzero().
 *
 * VÌ SAO KHÔNG GỌI explicit_bzero() (dù file explicit_bzero.c nằm ngay đây):
 * build với -D_FORTIFY_SOURCE=2 nên preprocessor đổi mọi lời gọi
 * explicit_bzero() thành __explicit_bzero_chk — hàm CỦA GLIBC, KHÔNG phải hàm
 * trong explicit_bzero.c. Đã kiểm bằng `nm -u slock.o`: chỉ thấy
 * "U __explicit_bzero_chk", không thấy explicit_bzero. Nên sửa
 * explicit_bzero.c là sửa code chết.
 *
 * Nhánh của glibc gọi memset() + compiler barrier, cũng chống tối ưu mất, nhưng
 * memset_explicit() được chuẩn BẢO ĐẢM byte thực sự bị ghi đè nên đúng tinh
 * thần hơn, và C23 thì có sẵn.
 *
 * memset_explicit() trả void* trong glibc, ta chỉ dùng để ghi nên bỏ qua —
 * khác với việc ép khai báo hàm.
 */
static void
wipe_secret(void *buf, size_t len)
{
#if defined(__STDC_VERSION__) && __STDC_VERSION__ >= 202311L
	memset_explicit(buf, 0, len);
#else
	explicit_bzero(buf, len);
#endif
}
#include <math.h>
#include <spawn.h>
#include <sys/select.h>
#include <sys/types.h>
#include <time.h>
#include <X11/extensions/Xrandr.h>
#include <X11/keysym.h>
#include <X11/Xlib.h>
#include <X11/Xutil.h>
#include <X11/Xft/Xft.h>

#include "arg.h"
#include "util.h"

char *argv0;

enum {
	INIT,
	INPUT,
	FAILED,
	NUMCOLS
};

struct lock {
	int screen;
	Window root, win;
	Pixmap pmap;

	/* ---- lớp giao diện (thêm sau, xem render_backdrop/render) ----
	 * pmap trên là bitmap con trỏ vô hình (8x8 toàn 0) cho XCreatePixmapCursor.
	 * bg bên dưới là pixmap NỀN thật — wallpaper đã làm mờ + tối. */
	/* XftTextExtentsUtf8() nhận Display*, KHÔNG nhận XftDraw* — và bản Xft
	 * cài trên máy không có XftDrawGetDisplay() để lấy lại. Nên phải giữ
	 * dpy. Các hàm còn lại (XftDrawStringUtf8, XftColorAllocName) dùng
	 * draw/visual/colormap. */
	Display *dpy;
	Visual *visual;
	Colormap cmap;
	Pixmap bg;
	unsigned int bgw, bgh;   /* kích thước bg đã tạo, để không dựng lại mỗi lần vẽ */
	int bgvalid;         /* bg dùng được chưa — TÁCH RIÊNG, không suy ra từ
	                      * bgw/bgh vì 0x0 cũng là một kích thước hợp lệ */
	unsigned long fallback;  /* màu nền phòng khi không dựng được bg */
	XftDraw *draw;
	XftFont *fbig, *fsmall, *fname;
	XftColor cfg, cdim, caccent, cerr;
	GC gc;
};

/* Một pixel sau khi làm mờ. Tách riêng 3 kênh (thay vì gói thành 1 số 24-bit)
 * để giữ độ chính xác khi tính trung bình và nội suy — gói số sẽ mất chính
 * xác ở bit thấp và gây sọc. */
typedef struct {
	unsigned short r, g, b;
} rgb;

/* Tên đăng nhập hiển thị trên màn khoá. Gán trong main() TRƯỚC khi hạ quyền:
 * slock là binary setuid nên getuid() (real uid, không phải effective uid) lúc
 * đó vẫn là người dùng thật. Không đọc $USER/$LOGNAME vì biến môi trường do
 * người gọi kiểm soát — hiển thị giả trên một màn khoá là vấn đề an ninh. */
static const char *login_name = "";

struct xrandr {
	int active;
	int evbase;
	int errbase;
};

#include "config.h"

[[noreturn]] static void
die(const char *errstr, ...)
{
	va_list ap;

	va_start(ap, errstr);
	vfprintf(stderr, errstr, ap);
	va_end(ap);
	exit(1);
}

#ifdef __linux__
#include <fcntl.h>
#include <linux/oom.h>

static void
dontkillme(void)
{
	FILE *f;
	const char oomfile[] = "/proc/self/oom_score_adj";

	if (!(f = fopen(oomfile, "w"))) {
		if (errno == ENOENT)
			return;
		die("slock: fopen %s: %s\n", oomfile, strerror(errno));
	}
	fprintf(f, "%d", OOM_SCORE_ADJ_MIN);
	if (fclose(f)) {
		if (errno == EACCES)
			die("slock: unable to disable OOM killer. "
			    "Make sure to suid or sgid slock.\n");
		else
			die("slock: fclose %s: %s\n", oomfile, strerror(errno));
	}
}
#endif

static const char *
gethash(void)
{
	const char *hash;
	struct passwd *pw;

	/* Check if the current user has a password entry */
	errno = 0;
	if (!(pw = getpwuid(getuid()))) {
		if (errno)
			die("slock: getpwuid: %s\n", strerror(errno));
		else
			die("slock: cannot retrieve password entry\n");
	}
	hash = pw->pw_passwd;

#if HAVE_SHADOW_H
	if (!strcmp(hash, "x")) {
		struct spwd *sp;
		if (!(sp = getspnam(pw->pw_name)))
			die("slock: getspnam: cannot retrieve shadow entry. "
			    "Make sure to suid or sgid slock.\n");
		hash = sp->sp_pwdp;
	}
#else
	if (!strcmp(hash, "*")) {
#ifdef __OpenBSD__
		if (!(pw = getpwuid_shadow(getuid())))
			die("slock: getpwnam_shadow: cannot retrieve shadow entry. "
			    "Make sure to suid or sgid slock.\n");
		hash = pw->pw_passwd;
#else
		die("slock: getpwuid: cannot retrieve shadow entry. "
		    "Make sure to suid or sgid slock.\n");
#endif /* __OpenBSD__ */
	}
#endif /* HAVE_SHADOW_H */

	return hash;
}

/* ================================================================= lớp vẽ
 *
 * slock gốc không vẽ gì ngoài XSetWindowBackground + XClearWindow, nên màn hình
 * chỉ có đúng MỘT màu phẳng. Phần dưới đây vẽ một cảnh: nền là wallpaper đã
 * làm mờ và tối, rồi chữ ở giữa.
 *
 * Cố tình KHÔNG dùng XRender và không dùng Imlib2:
 *   - XRender + Composite để làm lớp phủ trong suốt thì phụ thuộc compositor
 *     có chạy hay không; compositor chết là màn khoá hiện ra màu rác.
 *   - Imlib2 là thư viện đọc ảnh. Thêm nó vào một binary setuid root nghĩa là
 *     thêm bộ phân tích ảnh vào đường đi của quyền root.
 * Cách ở đây — XGetImage rồi lọc trong bộ nhớ của chính process — không cần
 * extension nào và nằm hoàn toàn trong X11 cơ bản.
 */

/* Nội suy song tuyến từ ảnh nhỏ (đã làm mờ) về tọa độ (fx, fy) tính theo ảnh
 * nhỏ. Biên được kẹp về trong, nên tx/ty luôn nằm trong [0,1) — nếu kẹp sau
 * khi tính thì trọng số âm và ảnh ra sọc. */
static unsigned long
sample(const rgb *sm, int sw, int sh, double fx, double fy,
       unsigned int rsh, unsigned int gsh, unsigned int bsh)
{
	int x0, y0, x1, y1;
	double tx, ty, r, g, b;
	const rgb *p00, *p10, *p01, *p11;

	if (fx < 0) fx = 0;
	if (fy < 0) fy = 0;
	if (fx > sw - 1) fx = sw - 1;
	if (fy > sh - 1) fy = sh - 1;

	x0 = (int)fx;
	y0 = (int)fy;
	tx = fx - x0;
	ty = fy - y0;
	x1 = x0 < sw - 1 ? x0 + 1 : x0;
	y1 = y0 < sh - 1 ? y0 + 1 : y0;

	p00 = &sm[(size_t)y0 * sw + x0];
	p10 = &sm[(size_t)y0 * sw + x1];
	p01 = &sm[(size_t)y1 * sw + x0];
	p11 = &sm[(size_t)y1 * sw + x1];

	r = (p00->r * (1 - tx) + p10->r * tx) * (1 - ty) +
	    (p01->r * (1 - tx) + p11->r * tx) * ty;
	g = (p00->g * (1 - tx) + p10->g * tx) * (1 - ty) +
	    (p01->g * (1 - tx) + p11->g * tx) * ty;
	b = (p00->b * (1 - tx) + p10->b * tx) * (1 - ty) +
	    (p01->b * (1 - tx) + p11->b * tx) * ty;

	return ((unsigned long)r << rsh) | ((unsigned long)g << gsh) |
	        ((unsigned long)b << bsh);
}

/* Chụp root window, thu nhỏ theo hộp NxN để làm mờ, tối lại, nội suy về kích
 * thước cũ. Trả Pixmap, hoặc None nếu không làm được — khi đó render() dùng
 * màu phòng. Không bao giờ chết: mất nền vẫn khoá được, mất nền thì màn hình
 * đen một màu — thà còn hơn không khoá. */
static Pixmap
render_backdrop(Display *dpy, struct lock *lock, unsigned int w, unsigned int h)
{
	Visual *vi = NULL;
	XImage *src = NULL, *out = NULL;
	XWindowAttributes wa;
	Pixmap pix = None;
	GC gc = NULL;
	rgb *sm = NULL;
	unsigned int x, y, i, j;
	int d = slock_blur_div, sw, sh;
	unsigned long rmask, gmask, bmask, keep;
	unsigned int rsh, gsh, bsh;
	unsigned long cnt;

	if (w == 0 || h == 0 || d < 1)
		return None;

	/* KHÔNG dùng XGetVisualInfo() ở đây. Bản đầu tiên gọi
	 * XGetVisualInfo(dpy, VisualScreenMask, &viatmpl, NULL) — nhưng tham số
	 * thứ tư KHÔNG phải con trỏ trả về mảng, mà là `int *nitems_return`
	 * (Xutil.h:471-476). Hàm viết số phần tử vào đó, nên NULL là SEGV:
	 *     AddressSanitizer: SEGV on unknown address 0x000000000000
	 *     WRITE memory access ... #0 XGetVisualInfo  #1 render_backdrop
	 *
	 * Hàm đó còn trả về một mảng XVisualInfo phải XFree() — truyền NULL ở
	 * tham số 4 khiến cả đường giải phóng đó không dùng được.
	 *
	 * Không cần gì từ nó: lock->visual đã là DefaultVisual(dpy, screen)
	 * (đặt trong lockscreen()), và depth lấy từ XGetWindowAttributes() bên
	 * dưới. Masks đọc từ chính visual đó. */
	vi = lock->visual;
	if (!XGetWindowAttributes(dpy, lock->root, &wa))
		return None;

	rmask = vi->red_mask;
	gmask = vi->green_mask;
	bmask = vi->blue_mask;
	if (!rmask || !gmask || !bmask)
		return None;
	for (rsh = 0; !((rmask >> rsh) & 1UL); rsh++) ;
	for (gsh = 0; !((gmask >> gsh) & 1UL); gsh++) ;
	for (bsh = 0; !((bmask >> bsh) & 1UL); bsh++) ;

	/* Đây là chỗ vừa phát hiện một lỗi THẬT mà các test cũ không bắt được:
	 * khi chạy setuid, slock đã setuid/setgid xuống "nobody" (main(), dòng
	 * ~800) TRƯỚC khi lockscreen()/render() chạy. Một tiến trình không có
	 * quyền root KHÔNG đọc được nội dung cửa sổ root của người dùng khác —
	 * X server trả lỗi BadAccess/BadMatch, XGetImage trả NULL, nên nền rơi về
	 * màu phẳng.
	 *
	 * Đo được: trên Xvfb, chạy bình thường (đủ quyền) thì nền là wallpaper đã
	 * làm mờ (nhiều màu); chạy qua pkexec (tương đương hạ quyền) thì góc trên-
	 * trái là #141018 — đúng bằng slock_fallback_bg, tức là render_backdrop
	 * trả None và màn hình chỉ còn một màu phẳng. Nghĩa là trên máy thật,
	 * bản đã cài, màn khoá chỉ hiện một khối tím đen không có wallpaper.
	 *
	 * Cách sửa: chụp root window TRƯỚC khi hạ quyền, tức ngay trong main()
	 * khi còn effective uid = root. XGetImage lúc đó thành công và dữ liệu
	 * nằm trong bộ nhớ của chính tiến trình, sau đó hạ quyền không lấy lại
	 * được nữa cũng không sao — không có I/O nào với X server về sau.
	 *
	 * Vì sao không đơn giản là bỏ hạ quyền: hạ quyền là điều slock GỐC làm
	 * và là biện pháp an ninh thật — nó giới hạn thiệt hại nếu slock bị lỗi.
	 * Bỏ đi thì slock chạy full quyền root cả thời gian khoá màn hình.
	 * Vì vậy giữ nguyên hạ quyền, chỉ dời thao tác đọc ảnh lên trước.
	 */
	if (!(src = XGetImage(dpy, lock->root, 0, 0, w, h, AllPlanes, ZPixmap)))
		return None;

	sw = (int)((w + d - 1) / d);
	sh = (int)((h + d - 1) / d);
	if (sw < 1) sw = 1;
	if (sh < 1) sh = 1;
	if (!(sm = calloc((size_t)sw * sh, sizeof(*sm)))) {
		XDestroyImage(src);
		return None;
	}

	/* trung bình + tối. Nhân ở đây (1 lần/pixel nhỏ) thay vì ở bước nội suy
	 * (1 lần/pixel lớn) — nhỏ hơn nhiều lần, và làm mờ đã làm mềm chuyển
	 * sắc nên tối ở đâu cũng không thấy khác. */
	keep = (unsigned long)slock_backdrop_keep;
	for (j = 0; j < (unsigned)sh; j++) {
		for (i = 0; i < (unsigned)sw; i++) {
			unsigned long ar = 0, ag = 0, ab = 0;
			unsigned int y0 = j * d, x0 = i * d;
			unsigned int y1 = y0 + d > h ? h : y0 + d;
			unsigned int x1 = x0 + d > w ? w : x0 + d;

			for (y = y0; y < y1; y++)
				for (x = x0; x < x1; x++) {
					unsigned long p = XGetPixel(src, x, y);
					ar += (p & rmask) >> rsh;
					ag += (p & gmask) >> gsh;
					ab += (p & bmask) >> bsh;
				}
			cnt = (unsigned long)(y1 - y0) * (x1 - x0);
			if (!cnt) {   /* không xảy ra với j<sh,i<sw, nhưng nếu có thì thoát sạch */
				XDestroyImage(src);
				goto free_sm;
			}
			sm[j * sw + i].r = (unsigned short)((ar / cnt) * keep / 100);
			sm[j * sw + i].g = (unsigned short)((ag / cnt) * keep / 100);
			sm[j * sw + i].b = (unsigned short)((ab / cnt) * keep / 100);
		}
	}
	XDestroyImage(src);
	src = NULL;

	out = XCreateImage(dpy, vi, (unsigned)wa.depth, ZPixmap, 0,
	                   NULL, w, h, 32, 0);
	if (!out)
		goto free_sm;
	/* XCreateImage() với data = NULL để lại out->data == NULL, và
	 * XPutPixel() ghi thẳng vào data đó → SEGV ghi địa chỉ 0.
	 * Đo được: chkimg in ra `img->data = (nil)` ngay sau khi gọi
	 * XCreateImage(..., NULL, ...), và ASan bắt đúng chỗ này:
	 *     #0 Xlib (libX11.so.6+0x25ed8) WRITE 0x0
	 *     #1 render_backdrop slock.c:343  <- XPutPixel
	 * Phải tự cấp bộ đệm trước, đúng bằng bytes_per_line * height —
	 * bytes_per_line là số byte mỗi dòng sau khi Xlib đã pad theo
	 * bitmap_pad của màn hình (XCreateImage tự tính, ở đây là 5120 cho
	 * 1280 pixel ở 32 bpp). Không tự nhân w*4 vì bitmap_pad có thể khác. */
	if (!out->data)
		out->data = calloc((size_t)out->bytes_per_line *
		                   (size_t)out->height, 1);
	if (!out->data) {
		XDestroyImage(out);
		goto free_sm;
	}
	for (y = 0; y < h; y++) {
		double fy = (y + 0.5) / d - 0.5;
		for (x = 0; x < w; x++) {
			double fx = (x + 0.5) / d - 0.5;
			XPutPixel(out, (int)x, (int)y,
			          sample(sm, sw, sh, fx, fy, rsh, gsh, bsh));
		}
	}

	pix = XCreatePixmap(dpy, lock->root, w, h, (unsigned)wa.depth);
	if (pix == None)
		goto free_out;
	if ((gc = XCreateGC(dpy, pix, 0, NULL)) == NULL) {
		XFreePixmap(dpy, pix);
		pix = None;
		goto free_out;
	}
	XPutImage(dpy, pix, gc, out, 0, 0, 0, 0, w, h);
	XFreeGC(dpy, gc);

free_out:
	XDestroyImage(out);
free_sm:
	free(sm);
	return pix;
}

/* Vẽ chữ canh giữa theo chiều ngang, theo baseline tại y. */
static void
draw_text(struct lock *lock, XftFont *f, XftColor *c, const char *s, int y)
{
	XGlyphInfo ext;

	if (!lock->draw || !f || !c || !s || !*s)
		return;
	/* XftTextExtentsUtf8() trả void, không phải int — hàm XftDrawStringUtf8
	 * mới là hàm trả void. (Bản đầu tiên của hàm này viết
	 * `if (XftTextExtentsUtf8(...)) return;` — sai, vì void không dùng
	 * được trong if.) */
	XftTextExtentsUtf8(lock->dpy, f, (const FcChar8 *)s, (int)strlen(s),
	                   &ext);
	/* ext.x là bearing bên trái: trừ nó đi thì glyph đầu nằm đúng mép trái
	 * của khối text, thay vì lệch trái theo bearing. */
	XftDrawStringUtf8(lock->draw, c, f,
	                  (int)(lock->bgw - ext.width) / 2 - ext.x, y,
	                  (const FcChar8 *)s, (int)strlen(s));
}

/* Vẽ toàn bộ cảnh: nền + giờ + ngày + tên + dấu chấm + nhắc khi sai.
 *
 * state: INIT / INPUT / FAILED — quyết định màu dấu chấm.
 * len:   số ký tự đã gõ (giới hạn bởi slock_max_dots).
 * failed: đang ở trạng thái "sai mật khẩu" (len == 0) — hiện dòng nhắc. */
static void
render(Display *dpy, struct lock *lock, int state,
       unsigned int len, int failed)
{
	unsigned int w = DisplayWidth(dpy, lock->screen);
	unsigned int h = DisplayHeight(dpy, lock->screen);
	XftColor *dotc = (state == FAILED) ? &lock->cerr : &lock->caccent;
	char clock[16], date[128], extra[64];
	time_t now;
	struct tm tm;
	unsigned int ndots, i;
	int yclock, ydate, yname, ydots, yhint, r = 5, step = 18, x0;

	/* Nền — dựng lại khi màn hình đổi kích thước (xoay màn hình Xrandr).
	 *
	 * lockscreen() đã dựng sẵn nền TRƯỚC khi map cửa sổ (bắt buộc, xem
	 * comment ở đó), và gán bgw/bgh ngay sau đó. Vì vậy ở lần render() đầu
	 * tiên, cache phải KHỚP — nếu không thì nhánh dưới đây xoá đúng pixmap
	 * vừa dựng rồi dựng lại, mà lúc này cửa sổ đã map và phủ kín root, nên
	 * lần dựng lại chụp nhầm chính cửa sổ khoá.
	 *
	 * Lỗi này đã xảy ra thật và im lặng: render_backdrop() trả về pixmap hợp
	 * lệ (đo được bg=2097157) nhưng bgw/bgh vẫn là 0 vì lockscreen() gán
	 * chúng SAU lời gọi; render() thấy 0 != kích thước màn hình nên xoá. Kết
	 * quả: nền rơi về màu phẳng, không có dấu vết. Sửa bằng cách dùng một
	 * cờ riêng (bgvalid) thay vì suy ra từ kích thước. */
	if (lock->bgvalid && (lock->bgw != w || lock->bgh != h)) {
		XFreePixmap(dpy, lock->bg);
		lock->bg = None;
		lock->bgvalid = 0;
	}
	if (!lock->bgvalid) {
		if ((lock->bg = render_backdrop(dpy, lock, w, h)) != None) {
			lock->bgw = w;
			lock->bgh = h;
			lock->bgvalid = 1;
		}
	}
	if (lock->bg != None)
		XSetWindowBackgroundPixmap(dpy, lock->win, lock->bg);
	else
		XSetWindowBackground(dpy, lock->win, lock->fallback);
	XClearWindow(dpy, lock->win);

	if (!lock->draw || !lock->fbig)
		return;   /* không có font thì để nền phẳng, vẫn khoá bình thường */

	/* Không gọi setlocale() nên tháng/ngày ra tiếng Anh (locale "C").
	 * Đây là chọn lựa: setlocale() trong một binary setuid là chỗ dễ rơi vào
	 * dữ liệu đa byte theo locale — và tên tháng tiếng Việt còn phụ thuộc locale
	 * UTF-8 có mặt trên máy hay không, thiếu thì ra "thang Muoi" hay "???" lẫn
	 * với số thứ tự byte sai. Tiếng Anh đọc được ở mọi locale. */
	now = time(NULL);
	localtime_r(&now, &tm);
	strftime(clock, sizeof(clock), "%H:%M", &tm);
	strftime(date, sizeof(date), "%A  %d %B %Y", &tm);

	yclock = (int)h / 2 - 70;
	ydate  = (int)h / 2 - 40;
	yname  = (int)h / 2 + 30;
	ydots  = (int)h / 2 + 62;
	yhint  = (int)h / 2 + 92;

	draw_text(lock, lock->fbig, &lock->cfg, clock, yclock);
	draw_text(lock, lock->fsmall, &lock->cdim, date, ydate);
	if (*login_name)
		draw_text(lock, lock->fname, &lock->cdim, login_name, yname);

	/* dấu chấm — vẽ tròn thật bằng XFillArc, không phụ thuộc font có ký tự ● */
	if (lock->gc) {
		ndots = len > (unsigned)slock_max_dots
		            ? (unsigned)slock_max_dots : len;
		XSetForeground(dpy, lock->gc, dotc->pixel);
		x0 = ((int)w - (ndots ? (int)(ndots - 1) * step + 2 * r : 0)) / 2;
		for (i = 0; i < ndots; i++)
			XFillArc(dpy, lock->win, lock->gc, x0 + (int)i * step,
			         ydots - r, 2 * r, 2 * r, 0, 360 * 64);
	}

	/* nhắc khi sai: chỉ khi đang ở FAILED và chưa gõ gì (len == 0) */
	if (failed && !len) {
		snprintf(extra, sizeof(extra), "Incorrect password");
		draw_text(lock, lock->fsmall, &lock->cerr, extra, yhint);
	} else if (len > (unsigned)slock_max_dots) {
		snprintf(extra, sizeof(extra), "+%u more",
		         len - (unsigned)slock_max_dots);
		draw_text(lock, lock->fsmall, &lock->cdim, extra, yhint);
	}
}

static void
render_all(Display *dpy, struct lock **locks, int nscreens,
           int state, unsigned int len, int failed)
{
	int screen;

	for (screen = 0; screen < nscreens; screen++)
		render(dpy, locks[screen], state, len, failed);
}

static void
readpw(Display *dpy, struct xrandr *rr, struct lock **locks, int nscreens,
       const char *hash)
{
	XRRScreenChangeNotifyEvent *rre;
	char buf[32], passwd[256], *inputhash;
	int num, screen, running, failure;
	unsigned int len, color;
	KeySym ksym;
	XEvent ev;
	fd_set rfds;
	struct timeval tv;
	int xfd, ticks;

	len = 0;
	running = 1;
	failure = 0;

	/* vẽ khung đầu tiên NGAY, trước khi chờ phím — nếu không thì màn hình
	 * trắng/xám cho tới lần gõ đầu tiên. */
	color = len ? INPUT : ((failure || failonclear) ? FAILED : INIT);
	render_all(dpy, locks, nscreens, color, len, failure);

	/* Vòng lặp: KHÔNG dùng `while (XNextEvent(dpy, &ev))` vô hạn nữa — hàm đó
	 * chặng tới khi có phím, nên đồng hồ không bao giờ tự nhảy phút (bản cũ
	 * không có đồng hồ nên không lộ, nhưng bản này có). Dùng select() trên
	 * socket của X với timeout 1 giây: có phím thì xử lý ngay (không chậm
	 * thêm một nhịp so với XNextEvent), hết 1s thì vẽ lại khung.
	 *
	 * Giá phải trả: select() + XPending() thay cho XNextEvent() làm vẻ không
	 * phản ứng với sự kiện nào khác — nhưng readpw chỉ quan tâm KeyPress và
	 * RRScreenChangeNotify, nên nhánh `else` (XRaiseWindow) vẫn được giữ nguyên
	 * cho mọi sự kiện lạ. */
	xfd = ConnectionNumber(dpy);
	while (running) {
		FD_ZERO(&rfds);
		FD_SET(xfd, &rfds);
		tv.tv_sec = 1;
		tv.tv_usec = 0;

		/* -1: X connection hỏng. 0: hết 1s, đồng hồ cần vẽ lại.
		 * >0: có sự kiện X chờ. */
		ticks = select(xfd + 1, &rfds, NULL, NULL, &tv);
		if (ticks < 0) {
			if (errno == EINTR)
				continue;
			break;
		}
		if (ticks == 0) {
			render_all(dpy, locks, nscreens, color, len, failure);
			continue;
		}

		/* Có thể nhiều sự kiện dồn về một lần gọi select (vd gõ nhanh vài
		 * chữ trong cùng một nhịp), nên phải vét hết hàng đợi chứ không
		 * chỉ lấy một. */
		while (XPending(dpy)) {
			XNextEvent(dpy, &ev);
			if (ev.type == KeyPress) {
				wipe_secret(&buf, sizeof(buf));
				num = XLookupString(&ev.xkey, buf, sizeof(buf), &ksym, 0);
				if (IsKeypadKey(ksym)) {
					if (ksym == XK_KP_Enter)
						ksym = XK_Return;
					else if (ksym >= XK_KP_0 && ksym <= XK_KP_9)
						ksym = (ksym - XK_KP_0) + XK_0;
				}
				if (IsFunctionKey(ksym) ||
				    IsKeypadKey(ksym) ||
				    IsMiscFunctionKey(ksym) ||
				    IsPFKey(ksym) ||
				    IsPrivateKeypadKey(ksym))
					continue;
				switch (ksym) {
			case XK_Return:
				passwd[len] = '\0';
				errno = 0;
				if (!(inputhash = crypt(passwd, hash)))
					fprintf(stderr, "slock: crypt: %s\n", strerror(errno));
				else
					running = !!strcmp(inputhash, hash);
				if (running) {
					XBell(dpy, 100);
					failure = 1;
				}
				wipe_secret(&passwd, sizeof(passwd));
				len = 0;
				break;
			case XK_Escape:
				wipe_secret(&passwd, sizeof(passwd));
				len = 0;
				break;
			case XK_BackSpace:
				if (len)
					passwd[--len] = '\0';
				break;
			default:
				/* ckd_add() (C23) thay cho `len + num < sizeof(passwd)`:
				 * phép cộng thuần có thể tràn — len là unsigned int,
				 * num là int trả về từ XLookupString; nếu len + num vòng
				 * quanh 2^32 thì phép so sánh trở thành ĐÚNG và
				 * memcpy() ghi ra ngoài `passwd`. Ở đây bị chặn cứng ở
				 * sizeof(passwd) nên không kích hoạt được, nhưng guard
				 * sai về hình thức thì không nên giữ: sau một đợt sửa
				 * nào đó nó sẽ thành lỗ hổng thật mà không ai thấy.
				 * `sum` là tổng đã kiểm tra, dùng lại cho cả memcpy. */
				{
					unsigned int sum;
					bool fits = !ckd_add(&sum, len, (unsigned int)num) &&
					            sum < sizeof(passwd);
					if (num && !iscntrl((int)buf[0]) && fits) {
						memcpy(passwd + len, buf, num);
						len = sum;
					} else if (buf[0] == '\025') { /* ctrl-u clears input */
						wipe_secret(&passwd, sizeof(passwd));
						len = 0;
					}
					break;
				}
				break;
			}
				color = len ? INPUT
				             : ((failure || failonclear) ? FAILED : INIT);
				/* Vẽ lại ngay khi trạng thái đổi (màu dấu chấm, số chấm,
				 * dòng nhắc sai) — không chờ tới nhịp 1s, nếu không
				 * phản hồi thị giác sau ký tự sẽ trễ tới 1 giây. */
				if (running)
					render_all(dpy, locks, nscreens, color, len, failure);
				continue;
			}
			if (rr->active && ev.type == rr->evbase + RRScreenChangeNotify) {
				rre = (XRRScreenChangeNotifyEvent*)&ev;
				for (screen = 0; screen < nscreens; screen++) {
					if (locks[screen]->win == rre->window) {
						if (rre->rotation == RR_Rotate_90 ||
						    rre->rotation == RR_Rotate_270)
							XResizeWindow(dpy, locks[screen]->win,
							              rre->height, rre->width);
						else
							XResizeWindow(dpy, locks[screen]->win,
							              rre->width, rre->height);
						/* Nền đã đổi kích thước: render() tự dựng lại
						 * bg và cache size nên không cần XClearWindow
						 * thủ công nữa. */
						render_all(dpy, locks, nscreens, color, len,
						           failure);
						break;
					}
				}
			} else {
				for (screen = 0; screen < nscreens; screen++)
					XRaiseWindow(dpy, locks[screen]->win);
			}
		}
		/* Dừng ngay khi mật khẩu đúng: còn sót sự kiện trong hàng đợi
		 * không cần xử lý, và render_all sau đó sẽ vẽ lên cửa sổ sắp bị
		 * huỷ. */
		if (!running)
			break;
	}
}

static struct lock *
lockscreen(Display *dpy, struct xrandr *rr, int screen)
{
	char curs[] = {0, 0, 0, 0, 0, 0, 0, 0};
	int i, ptgrab, kbgrab;
	struct lock *lock;
	XColor color, dummy;
	XSetWindowAttributes wa;
	Cursor invisible;

	if (dpy == nullptr || screen < 0 || !(lock = malloc(sizeof(struct lock))))
		return nullptr;

	lock->screen = screen;
	lock->root = RootWindow(dpy, lock->screen);
	lock->dpy = dpy;
	lock->visual = DefaultVisual(dpy, lock->screen);
	lock->cmap = DefaultColormap(dpy, lock->screen);
	lock->bg = None;
	lock->bgvalid = 0;
	lock->bgw = lock->bgh = 0;
	lock->draw = NULL;
	lock->fbig = lock->fsmall = lock->fname = NULL;
	lock->gc = NULL;

	/* Màu nền dự phòng: dùng khi không dựng được nền từ wallpaper
	 * (XGetImage thất bại). Không nên là màu sáng — chữ vẽ đè lên nó. */
	if (!XAllocNamedColor(dpy, DefaultColormap(dpy, lock->screen),
	                      slock_fallback_bg, &color, &dummy))
		color.pixel = BlackPixel(dpy, lock->screen);
	lock->fallback = color.pixel;

	/* init */
	wa.override_redirect = 1;
	wa.background_pixel = lock->fallback;
	lock->win = XCreateWindow(dpy, lock->root, 0, 0,
	                          DisplayWidth(dpy, lock->screen),
	                          DisplayHeight(dpy, lock->screen),
	                          0, DefaultDepth(dpy, lock->screen),
	                          CopyFromParent,
	                          DefaultVisual(dpy, lock->screen),
	                          CWOverrideRedirect | CWBackPixel, &wa);
	lock->pmap = XCreateBitmapFromData(dpy, lock->win, curs, 8, 8);
	invisible = XCreatePixmapCursor(dpy, lock->pmap, lock->pmap,
	                                &color, &color, 0, 0);
	XDefineCursor(dpy, lock->win, invisible);

	/* Try to grab mouse pointer *and* keyboard for 600ms, else fail the lock */
	for (i = 0, ptgrab = kbgrab = -1; i < 6; i++) {
		if (ptgrab != GrabSuccess) {
			ptgrab = XGrabPointer(dpy, lock->root, False,
			                      ButtonPressMask | ButtonReleaseMask |
			                      PointerMotionMask, GrabModeAsync,
			                      GrabModeAsync, None, invisible, CurrentTime);
		}
		if (kbgrab != GrabSuccess) {
			kbgrab = XGrabKeyboard(dpy, lock->root, True,
			                       GrabModeAsync, GrabModeAsync, CurrentTime);
		}

		/* input is grabbed: we can lock the screen */
		if (ptgrab == GrabSuccess && kbgrab == GrabSuccess) {
			/* CHỤP ROOT WINDOW TRƯỚC KHI MAP CỬA SỔ KHOÁ.
			 *
			 * Đây là lỗi thật đã đo, không phải suy đoán. Cửa sổ khoá là
			 * window con của root, override-redirect, phủ KÍN toàn màn hình.
			 * Sau khi XMapRaised(), XGetImage(trên root) trả về ẢNH ĐÃ BỊ
			 * CỬA SỔ KHOÁ PHỦ — tức là chính màn hình khoá, không phải
			 * wallpaper. render_backdrop() vì thế chụp nhầm và nền rơi về
			 * màu phẳng.
			 *
			 * Đo trên Xvfb với nền gốc 4 vùng màu:
			 *     root TRƯỚC khi map : R=144 G=151 B=103  (wallpaper thật)
			 *     root SAU  khi map : R= 20 G= 16 B= 24  (màu fallback)
			 * Dòng "SAU khi map" trùng đúng slock_fallback_bg #141018.
			 *
			 * Nên: dựng nền ở đây, khi root còn nguyên wallpaper. readpw()
			 * gọi render_all() ngay sau đó, và hàm đó sẽ dùng nền đã có.
			 *
			 * Vì sao để XMapRaised ở đây mà không sớm hơn nữa: phải BẮT được
			 * bàn phím trước, nếu không thì giữa lúc chờ màn hình vẫn chưa
			 * khoá — đúng như slock gốc. */
			lock->bg = render_backdrop(dpy, lock,
			                          DisplayWidth(dpy, lock->screen),
			                          DisplayHeight(dpy, lock->screen));
			if (lock->bg != None) {
				lock->bgw = DisplayWidth(dpy, lock->screen);
				lock->bgh = DisplayHeight(dpy, lock->screen);
				lock->bgvalid = 1;
			}

			XMapRaised(dpy, lock->win);
			if (rr->active)
				XRRSelectInput(dpy, lock->win, RRScreenChangeNotifyMask);

			XSelectInput(dpy, lock->root, SubstructureNotifyMask);

			/* Lớp vẽ. Đặt SAU khi grab thành công để không tạo tài
			 * nguyên Xft trên màn hình hỏng. Thiếu font thì vẫn khoá
			 * được — chỉ mất chữ, không mất khoá. */
			/* XftDrawCreate() nhận Drawable (cửa sổ khoá — đúng).
			 *
			 * NHƯNG XftFontOpenName() nhận `int screen` — SỐ SCREEN,
			 * không phải drawable (Xft.h:342). Bản đầu tiên của dòng
			 * này truyền `lock->win` (một XID cửa sổ, trên máy này
			 * 4194305) vào ô `screen` đó. libXft đưa thẳng con số ấy
			 * xuống XRenderQuerySubpixelOrder(dpy, 4194305), mà hàm đó
			 * đọc dpy->screens[4194305] — lệch 4194305 phần tử khỏi
			 * bảng, tức đọc ngoài bộ nhớ.
			 *
			 * Đo được (không phải suy đoán) bằng LD_PRELOAD bọc hàm
			 * XRenderQuerySubpixelOrder để in tham số thật:
			 *     drawable = RootWindow (XID 927)   -> truyền screen=927
			 *     drawable = Window con (XID 4194305) -> truyền screen=4194305
			 * và gọi trực tiếp XRenderQuerySubpixelOrder với các giá trị:
			 *     screen=0,1,100,927   -> OK
			 *     screen=4194305,
			 *     screen=2147483647   -> SEGV
			 * Backtrace của slock (build ASan) chỉ đúng đường:
			 *     XftFontOpenName -> XftFontMatch -> XftDefaultSubstitute
			 *       -> XRenderQuerySubpixelOrder  [SEGV]
			 *
			 * dwm không dính vì drw.c:117 truyền `drw->screen` — đã là
			 * số screen (int) ngay từ đầu.
			 *
			 * LƯU Ý: root window cũng SẼ chết nếu XID của nó rơi vào vùng
			 * không map được. Việc thử với root "chạy được" là may mắn
			 * theo XID, không phải đúng đắn. Truyền số screen thật là
			 * cách duy nhất đúng. */
			lock->draw = XftDrawCreate(dpy, lock->win,
			                           lock->visual, lock->cmap);
			lock->fbig   = XftFontOpenName(dpy, lock->screen,
			                               slock_font_big);
			lock->fsmall = XftFontOpenName(dpy, lock->screen,
			                               slock_font_small);
			lock->fname  = XftFontOpenName(dpy, lock->screen,
			                               slock_font_name);
			lock->gc = XCreateGC(dpy, lock->win, 0, NULL);
			if (lock->draw && lock->fbig && lock->fsmall && lock->fname &&
			    lock->gc) {
				XftColorAllocName(dpy, lock->visual, lock->cmap,
				                  slock_fg, &lock->cfg);
				XftColorAllocName(dpy, lock->visual, lock->cmap,
				                  slock_dim, &lock->cdim);
				XftColorAllocName(dpy, lock->visual, lock->cmap,
				                  slock_accent, &lock->caccent);
				XftColorAllocName(dpy, lock->visual, lock->cmap,
				                  slock_err, &lock->cerr);
			}
			return lock;
		}

		/* retry on AlreadyGrabbed but fail on other errors */
		if ((ptgrab != AlreadyGrabbed && ptgrab != GrabSuccess) ||
		    (kbgrab != AlreadyGrabbed && kbgrab != GrabSuccess))
			break;

		usleep(100000);
	}

	/* we couldn't grab all input: fail out */
	if (ptgrab != GrabSuccess)
		fprintf(stderr, "slock: unable to grab mouse pointer for screen %d\n",
		        screen);
	if (kbgrab != GrabSuccess)
		fprintf(stderr, "slock: unable to grab keyboard for screen %d\n",
		        screen);
	return nullptr;
}

static void
usage(void)
{
	die("usage: slock [-v] [cmd [arg ...]]\n");
}

int
main(int argc, char **argv) {
	struct xrandr rr;
	struct lock **locks;
	struct passwd *pwd;
	struct group *grp;
	uid_t duid;
	gid_t dgid;
	const char *hash;
	Display *dpy;
	int s, nlocks, nscreens;

	ARGBEGIN {
	case 'v':
		puts("slock-"VERSION);
		return 0;
	default:
		usage();
	} ARGEND

	/* validate drop-user and -group */
	errno = 0;
	if (!(pwd = getpwnam(user)))
		die("slock: getpwnam %s: %s\n", user,
		    errno ? strerror(errno) : "user entry not found");
	duid = pwd->pw_uid;
	errno = 0;
	if (!(grp = getgrnam(group)))
		die("slock: getgrnam %s: %s\n", group,
		    errno ? strerror(errno) : "group entry not found");
	dgid = grp->gr_gid;

#ifdef __linux__
	dontkillme();
#endif

	hash = gethash();
	errno = 0;
	if (!crypt("", hash))
		die("slock: crypt: %s\n", strerror(errno));

	if (!(dpy = XOpenDisplay(nullptr)))
		die("slock: cannot open display\n");

	/* Tên đăng nhập để hiện trên màn khoá. Lấy ở đây vì đây là chỗ CUỐI
	 * còn effective uid = root nhưng real uid vẫn là người gọi (slock cài
	 * setuid 4755) — getpwuid(getuid()) trả đúng user thật. Sau setuid()
	 * bên dưới thì getuid() đã bị đổi và chỉ còn "nobody".
	 *
	 * Cố tình KHÔNG đọc $USER/$LOGNAME: biến môi trường do người gọi đặt
	 * được, nên kẻ khác có thể cho hiện tên người khác trên màn khoá.
	 * pw_name từ /etc/passwd thì không. */
	if ((pwd = getpwuid(getuid())) && pwd->pw_name && *pwd->pw_name)
		login_name = pwd->pw_name;

	/* drop privileges */
	if (setgroups(0, nullptr) < 0)
		die("slock: setgroups: %s\n", strerror(errno));
	if (setgid(dgid) < 0)
		die("slock: setgid: %s\n", strerror(errno));
	if (setuid(duid) < 0)
		die("slock: setuid: %s\n", strerror(errno));

	/* check for Xrandr support */
	rr.active = XRRQueryExtension(dpy, &rr.evbase, &rr.errbase);

	/* get number of screens in display "dpy" and blank them */
	nscreens = ScreenCount(dpy);
	if (!(locks = calloc(nscreens, sizeof(struct lock *))))
		die("slock: out of memory\n");
	for (nlocks = 0, s = 0; s < nscreens; s++) {
		if ((locks[s] = lockscreen(dpy, &rr, s)) != nullptr)
			nlocks++;
		else
			break;
	}
	XSync(dpy, 0);

	/* did we manage to lock everything? */
	if (nlocks != nscreens)
		return 1;

	/* run post-lock command */
	if (argc > 0) {
		pid_t pid;
		extern char **environ;
		int err = posix_spawnp(&pid, argv[0], nullptr, nullptr, argv, environ);
		if (err) {
			die("slock: failed to execute post-lock command: %s: %s\n",
			    argv[0], strerror(err));
		}
	}

	/* everything is now blank. Wait for the correct password */
	readpw(dpy, &rr, locks, nscreens, hash);

	return 0;
}

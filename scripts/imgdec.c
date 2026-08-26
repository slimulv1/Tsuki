/* imgdec.c - fast image -> PNG thumbnail decoder for the dwm wallpaper stack
 *
 * Usage: imgdec <input_image> <target_width> [outfile]
 *
 * Decodes <input_image> and writes a PNG scaled to exactly <target_width>
 * px wide (height follows the aspect ratio) to stdout, or to [outfile]
 * when given. Only PNG bytes ever reach stdout; diagnostics go to stderr
 * and the exit status is 0 on success.
 *
 * Decode paths, chosen by magic bytes (extension ignored):
 *   JPEG : libjpeg-turbo scaled DCT decode - the largest tjGetScalingFactors
 *          entry whose resulting width still reaches 1.5x the target, then
 *          finished to the exact size by stb_image_resize2
 *   WebP : libwebp WebPDecodeRGBA, resized when wider than the target
 *   other: stb_image (PNG/BMP/GIF/TGA/PSD/PNM/HDR), resized when wider
 *
 * Built by Makefile.imgdec. wallpicker.py runs this binary as its preferred
 * thumbnail fast path and falls back to Pillow/gdk-pixbuf when it is absent
 * or fails.
 */

#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include <turbojpeg.h>
#include <webp/decode.h>

#define STB_IMAGE_IMPLEMENTATION
#define STBI_NO_JPEG /* JPEG is handled by libjpeg-turbo above */
#pragma GCC diagnostic push
#pragma GCC diagnostic ignored "-Wunused-function"
#include "stb/stb_image.h"
#pragma GCC diagnostic pop

#define STB_IMAGE_RESIZE2_IMPLEMENTATION
#pragma GCC diagnostic push
#pragma GCC diagnostic ignored "-Wunused-but-set-variable"
#include "stb/stb_image_resize2.h"
#pragma GCC diagnostic pop

#define STB_IMAGE_WRITE_IMPLEMENTATION
#pragma GCC diagnostic push
#pragma GCC diagnostic ignored "-Wunused-function"
#include "stb/stb_image_write.h"
#pragma GCC diagnostic pop

/* who owns the pixel buffer - decides the correct release call */
enum buf_origin { ORIG_TJ, ORIG_WEBP, ORIG_STB };

[[noreturn]] static void
die(const char *msg)
{
	fprintf(stderr, "imgdec: %s\n", msg);
	exit(1);
}

static void
free_rgba(unsigned char *px, enum buf_origin origin)
{
	if (!px)
		return;
	if (origin == ORIG_WEBP)
		WebPFree(px);
	else
		free(px); /* turbojpeg and stb both hand back plain malloc */
}

/* Read a whole file into one buffer; refuses anything past INT_MAX because
 * stb_image takes a signed length. */
static unsigned char *
slurp(const char *path, size_t *len)
{
	FILE *fh;
	long sz;
	unsigned char *buf;

	fh = fopen(path, "rb");
	if (!fh)
		die("cannot open input file");
	if (fseek(fh, 0, SEEK_END) != 0 || (sz = ftell(fh)) < 0 ||
	    fseek(fh, 0, SEEK_SET) != 0)
		die("cannot stat input file");
	if (sz > 2147483647L)
		die("input file too large");
	buf = malloc(sz > 0 ? (size_t)sz : 1);
	if (!buf)
		die("out of memory");
	if (sz > 0 && fread(buf, 1, (size_t)sz, fh) != (size_t)sz)
		die("short read on input file");
	fclose(fh);
	*len = (size_t)sz;
	return buf;
}

static int
is_jpeg(const unsigned char *b, size_t n)
{
	return n >= 3 && b[0] == 0xFF && b[1] == 0xD8 && b[2] == 0xFF;
}

static int
is_webp(const unsigned char *b, size_t n)
{
	return n >= 12 && !memcmp(b, "RIFF", 4) && !memcmp(b + 8, "WEBP", 4);
}

/* Integer ceil(dim * factor) - same rule as the header's TJSCALED, done
 * locally so we never depend on how that macro wants its argument. */
static int
scaled_dim(int dim, const tjscalingfactor *f)
{
	return (dim * f->num + f->denom - 1) / f->denom;
}

/* Scaled JPEG decode: among the useful downscale set {1/2, 1/4, 1/8} pick
 * the largest factor whose resulting width still reaches 1.5x the target
 * (mirrors wallpicker's Pillow rule - the smallest sufficient decode), so
 * the DCT is shrunk on the cheap frequency domain before a single spatial
 * pixel exists. Falls back to full size when even 1/2 misses the bar.
 * Output is RGBA, ready for stbir. */
static unsigned char *
decode_jpeg(const unsigned char *buf, size_t len, int target, int *w, int *h)
{
	tjscalingfactor const *sf;
	tjscalingfactor const *best;
	tjhandle tj;
	double want = target * 1.5;
	unsigned char *px;
	int i, n, iw, ih, subsamp, cs, sw, sh;

	tj = tjInitDecompress();
	if (!tj)
		die("cannot initialise turbojpeg");
	if (tjDecompressHeader3(tj, buf, (unsigned long)len, &iw, &ih,
	                        &subsamp, &cs) < 0)
		die(tjGetErrorStr());
	sf = tjGetScalingFactors(&n);
	best = nullptr;
	for (i = 0; i < n; ++i) {
		long scaled;
		/* only the 1/{2,4,8} downscale set is worth decoding into */
		if (sf[i].num != 1 ||
		    (sf[i].denom != 2 && sf[i].denom != 4 && sf[i].denom != 8))
			continue;
		scaled = scaled_dim(iw, &sf[i]);
		if ((double)scaled >= want &&
		    (!best || sf[i].denom < best->denom)) /* largest fraction */
			best = &sf[i];
	}
	if (!best)
		best = &TJUNSCALED;
	sw = scaled_dim(iw, best);
	sh = scaled_dim(ih, best);
	px = malloc((size_t)sw * sh * 4);
	if (!px)
		die("out of memory");
	if (tjDecompress2(tj, buf, (unsigned long)len, px, sw, sw * 4, sh,
	                  TJPF_RGBA,
	                  TJFLAG_FASTDCT | TJFLAG_FASTUPSAMPLE |
	                  TJFLAG_NOREALLOC) < 0)
		die(tjGetErrorStr());
	tjDestroy(tj);
	*w = sw;
	*h = sh;
	return px;
}

/* First frame of a WebP (animated files degrade to an error here and the
 * Python side falls back to its own decoders). */
static unsigned char *
decode_webp(const unsigned char *buf, size_t len, int *w, int *h)
{
	unsigned char *px = WebPDecodeRGBA(buf, len, w, h);

	if (!px)
		die("invalid webp data");
	return px;
}

/* Everything else through stb_image, normalised to RGBA. */
static unsigned char *
decode_generic(const unsigned char *buf, size_t len, int *w, int *h)
{
	int comp;
	unsigned char *px =
	    stbi_load_from_memory(buf, (int)len, w, h, &comp, 4);

	if (!px)
		die("unsupported or corrupt image");
	return px;
}

/* Resize to exactly dst_w wide (aspect kept); hands back the original
 * buffer untouched when the width already matches. */
static unsigned char *
fit_width(unsigned char *src, int *w, int *h, int dst_w)
{
	unsigned char *dst;
	int dst_h;

	if (*w == dst_w)
		return src;
	dst_h = (int)lround((double)*h * dst_w / *w);
	if (dst_h < 1)
		dst_h = 1;
	dst = stbir_resize_uint8_linear(src, *w, *h, *w * 4, nullptr,
	                                dst_w, dst_h, dst_w * 4, STBIR_RGBA);
	if (!dst)
		die("resize failed");
	*w = dst_w;
	*h = dst_h;
	return dst;
}

/* stb_image_write sink that streams chunks straight to stdout. */
static void
write_stdout(void *ctx, void *data, int size)
{
	fwrite(data, 1, (size_t)size, (FILE *)ctx);
}

int
main(int argc, char **argv)
{
	enum buf_origin origin;
	const char *outfile;
	unsigned char *file, *rgba, *out;
	size_t flen;
	int target, w, h, ok;

	if (argc < 3 || argc > 4) {
		fprintf(stderr, "usage: %s <input_image> <target_width> "
		                "[outfile]\n", argv[0]);
		return 1;
	}
	target = atoi(argv[2]);
	if (target < 1 || target > 65536)
		die("target width out of range");

	file = slurp(argv[1], &flen);
	if (is_jpeg(file, flen)) {
		origin = ORIG_TJ;
		rgba = decode_jpeg(file, flen, target, &w, &h);
	} else if (is_webp(file, flen)) {
		origin = ORIG_WEBP;
		rgba = decode_webp(file, flen, &w, &h);
	} else {
		origin = ORIG_STB;
		rgba = decode_generic(file, flen, &w, &h);
	}
	free(file);

	out = fit_width(rgba, &w, &h, target);
	if (out != rgba)
		free_rgba(rgba, origin);

	stbi_write_png_compression_level = 1; /* thumbs: speed over size */
	/* fixed cheapest filter - skips stb's 5-filter/row entropy search */
	stbi_write_force_png_filter = 0;
	outfile = argc == 4 ? argv[3] : nullptr;
	if (outfile) {
		ok = stbi_write_png(outfile, w, h, 4, out, w * 4);
	} else {
		stbi_write_png_to_func(write_stdout, stdout, w, h, 4,
		                       out, w * 4);
		ok = !ferror(stdout);
	}
	free_rgba(out, origin);
	if (!ok)
		die("failed to encode png");
	if ((!outfile && (fflush(stdout) != 0 || ferror(stdout))))
		die("stdout write failed");
	return 0;
}

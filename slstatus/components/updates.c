/* See LICENSE file for copyright and license details. */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#include "../slstatus.h"
#include "../util.h"

/* Resolve cache path o LUC CHAY, khong ghi cung ten user luc bien dich.
 *
 * BUG DA SUA: truoc day ghi cung "/home/magnus/.cache/dwm-updates" — ten user
 * cua may khac. Cache that do updates-loop.sh ghi la "$HOME/.cache/dwm-updates",
 * nen fopen() luon truot, ham tu tao file rong o /home/magnus/... (thu muc do
 * khong ton tai -> fopen "w" cung truot) va luon tra n = 0 -> thanh bar bao
 * "Fully Updated" du may co 200 goi can update. Loi im lang, khong bao gi.
 *
 * Thu tu: $XDG_CACHE_HOME (bo qua neu khong phai duong tuyet doi, dung XDG
 * spec) -> $HOME/.cache -> /tmp kem uid (van dung theo user, khong dung user
 * khac nhu /tmp/dwm-updates chung). */
static const char *
updates_cache_path(char *dst, size_t dstsz)
{
        const char *base;
        int n;

        base = getenv("XDG_CACHE_HOME");
        if (base && base[0] == '/') {
                n = snprintf(dst, dstsz, "%s/dwm-updates", base);
                if (n > 0 && (size_t)n < dstsz)
                        return dst;
        }
        base = getenv("HOME");
        if (base && base[0] == '/') {
                n = snprintf(dst, dstsz, "%s/.cache/dwm-updates", base);
                if (n > 0 && (size_t)n < dstsz)
                        return dst;
        }
        n = snprintf(dst, dstsz, "/tmp/dwm-updates-%ld", (long)getuid());
        return (n > 0 && (size_t)n < dstsz) ? dst : NULL;
}

/* doc so package update tu ~/.cache/dwm-updates
 * n > 0 -> icon + so mau ON (trang)
 * n = 0 -> AN HOAN TOAN (tra ve chuoi rong, khong icon khong so)
 * Mau lay tu args truyen trong config.h: "ONHEX OFFHEX" (hex khong co '#'),
 * dwmwal.sh thay 2 sentinel UPD_ON_HEX / UPD_OFF_HEX moi khi doi wallpaper. */
const char *
updates(const char *arg)
{
        char *f;
        FILE *fp;
        long n;
        char on[8], off[8];
        char cachepath[512];
        const char *path = updates_cache_path(cachepath, sizeof(cachepath));

        if (!path)
                return nullptr;

        if (!(fp = fopen(path, "r"))) {
                /* cache chưa có (updates-loop.sh chưa chạy lần đầu):
                 * tự tạo mặc định "0", không spam warn mỗi giây */
                FILE *f0 = fopen(path, "w");
                if (f0) {
                        fputs("0\n", f0);
                        fclose(f0);
                }
                n = 0;
        } else {
                f = fgets(buf, sizeof(buf) - 1, fp);
                if (fclose(fp) < 0) {
                        warn("fclose '%s':", path);
                        return nullptr;
                }
                if (!f)
                        return nullptr;

                if ((f = strrchr(buf, '\n')))
                        f[0] = '\0';

                n = strtol(buf, nullptr, 10);
        }

/* parse "ONHEX OFFHEX" tu args (config.h); fallback mau mac dinh
 * icon: n = 0 -> AN (chuoi rong), n > 0 -> \uF013 gear + so update */
	if (n > 0) {
		if (arg && sscanf(arg, "%7s %7s", on, off) == 2)
			snprintf(buf, sizeof(buf), "^c%s^\uF013 %ld^d^ ", on, n);
		else
			snprintf(buf, sizeof(buf), "^c#c3d3df^\uF013 %ld^d^ ", n);
	} else {
		buf[0] = '\0';
	}

	return buf;
}

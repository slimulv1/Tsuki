/* See LICENSE file for copyright and license details. */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "../slstatus.h"
#include "../util.h"

/* doc: so update pacman tu ~/.cache/dwm-updates
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
        const char *path = "/home/magnus/.cache/dwm-updates";

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

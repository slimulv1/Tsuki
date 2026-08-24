/* See LICENSE file for copyright and license details. */
/*
 * net_icon — icon trạng thái internet cho statusbar (wifi / wired / offline)
 *
 * ƯU TIÊU: wifi (wlan0) có essid → icon wifi theo mức sóng (yêu cầu của
 * user 2026-08-24: bar luôn thể hiện mạng WiFi đang kết nối kể cả khi cắm dây).
 * Không có wifi → wired (enp8s0) carrier == '1' → icon ethernet.
 * Không có gì → icon wifi-gạch-chéo màu đỏ.
 *
 * Icon là Nerd Font glyph, đã verify render trên bar (2026-08-24):
 *   󰈀 ethernet | 󰤨 wifi 4 bars | 󰤧 3 bars | 󰤦 2 bars | 󰤭 off
 */
#include <net/if.h>
#include <netinet/in.h>
#include <stdio.h>
#include <string.h>
#include <sys/ioctl.h>
#include <sys/socket.h>
#include <unistd.h>
#include <linux/wireless.h>

#include "../slstatus.h"
#include "../util.h"

#define WIRED_IFACE "enp8s0"
#define WIFI_IFACE  "wlan0"

/* palette đồng bộ theme slstatus config.h */
#define C_OK    "#a5d793" /* xanh lá như battery_state */
#define C_WARN  "#cec4de" /* trắng ngà */
#define C_ERR   "#ff5555"

const char *
net_icon(const char *unused)
{
	(void)unused;

	/* 1) wifi: essid qua ioctl + chất lượng sóng từ /proc/net/wireless */
	int fd = socket(AF_INET, SOCK_DGRAM, 0);
	if (fd >= 0) {
		char essid[IW_ESSID_MAX_SIZE + 1] = "";
		struct iwreq wrq;
		memset(&wrq, 0, sizeof(wrq));
		snprintf(wrq.ifr_name, IFNAMSIZ, "%s", WIFI_IFACE);
		wrq.u.essid.pointer = essid;
		wrq.u.essid.length  = IW_ESSID_MAX_SIZE;
		wrq.u.essid.flags   = 0;

		int has_wifi = (ioctl(fd, SIOCGIWESSID, &wrq) >= 0 &&
		                wrq.u.essid.length > 0);

		if (has_wifi) {
			int perc = 100; /* mặc định mạnh nếu đọc không được */
			FILE *wf = fopen("/proc/net/wireless", "r");
			if (wf) {
				char line[256], ifn[64];
				while (fgets(line, sizeof(line), wf)) {
					char *colon = strchr(line, ':');
					if (!colon)
						continue;
					*colon = '\0';
					sscanf(line, "%63s", ifn);
					if (strcmp(ifn, WIFI_IFACE))
						continue;
					int link = 0;
					if (sscanf(colon + 1, "%*s %d", &link) == 1 && link > 0)
						perc = link * 100 / 70;
					break;
				}
				fclose(wf);
			}
			close(fd);
			snprintf(buf, sizeof(buf), "^c%s^%s^d^",
			         perc >= 60 ? C_OK : C_WARN,
			         perc >= 67 ? "󰤨" : perc >= 34 ? "󰤧" : "󰤦");
			return buf;
		}
		close(fd);
	}

	/* 2) wired: carrier file == '1' nghĩa là cắm dây và có mạng */
	FILE *f = fopen("/sys/class/net/" WIRED_IFACE "/carrier", "r");
	if (f) {
		int c = fgetc(f);
		fclose(f);
		if (c == '1') {
			snprintf(buf, sizeof(buf), "^c%s^󰈀^d^", C_OK);
			return buf;
		}
	}

	/* 3) offline */
	snprintf(buf, sizeof(buf), "^c%s^󰤭^d^", C_ERR);
	return buf;
}

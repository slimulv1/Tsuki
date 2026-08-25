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

/*
 * Marker vô hình bao quanh icon để dwm hit-test click (2026-08-25):
 * "^c#010203^^d^" chỉ set màu rồi reset ngay → không vẽ gì lên bar.
 * Cơ chế: dwm ghi tọa độ pixel NGAY LÚC VẼ — khi gặp mã màu #010203
 * trong pass vẽ của drawstatusbar(), nó lưu vị trí x hiện tại vào
 * m->neticon_x0 (marker mở) và m->neticon_x1 (marker đóng); buttonpress
 * chỉ so ev->x với vùng [x0, x1+4). Nhờ vậy vùng click TỰ CẬP NHẬT khi
 * system tray thêm/bớt icon làm dịch chuyển status, CHỈ click đúng vào
 * icon mới mở netpanel.
 * Màu #010203 phải KHÔNG được dùng ở bất kỳ component nào khác trong
 * slstatus config.h — nếu trùng thì hit-test sẽ sai vùng.
 */
#define NETICON_MARK "^c#010203^^d^"

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
			snprintf(buf, sizeof(buf), NETICON_MARK "^c%s^%s^d^" NETICON_MARK,
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
			snprintf(buf, sizeof(buf), NETICON_MARK "^c%s^󰈀^d^" NETICON_MARK, C_OK);
			return buf;
		}
	}

	/* 3) offline */
	snprintf(buf, sizeof(buf), NETICON_MARK "^c%s^󰤭^d^" NETICON_MARK, C_ERR);
	return buf;
}

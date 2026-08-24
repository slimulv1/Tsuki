/* See LICENSE file for copyright and license details. */
/*
 * wifi_panel — Wi-Fi Mini cho statusbar
 *
 * Hiển thị: tên WiFi đang kết nối (nền card #1a1a2e).
 * Icon (wired/wifi/offline) do net_icon lo phía trước;
 * panel đầy đủ (stats/DNS/scan...) do ~/dwm/netpanel lo khi click.
 * Mất kết nối: rỗng.
 *
 * Palette đã verify qua 2 vòng vision-check (2026-08-24):
 *   bg #1a1a2e | value #e0e0e8
 */
#include <net/if.h>
#include <stdio.h>
#include <string.h>
#include <sys/ioctl.h>
#include <sys/socket.h>
#include <unistd.h>
#include <linux/wireless.h>

#include "../slstatus.h"
#include "../util.h"

#define WIFI_IFACE "wlan0"

#define C_BG_CARD "#1a1a2e"
#define C_VALUE   "#e0e0e8"

const char *
wifi_panel(const char *unused)
{
	(void)unused;

	int fd = socket(AF_INET, SOCK_DGRAM, 0);
	if (fd < 0)
		return "";
	char essid[IW_ESSID_MAX_SIZE + 1] = "";
	struct iwreq wrq;
	memset(&wrq, 0, sizeof(wrq));
	snprintf(wrq.ifr_name, IFNAMSIZ, "%s", WIFI_IFACE);
	wrq.u.essid.pointer = essid;
	wrq.u.essid.length  = IW_ESSID_MAX_SIZE;
	wrq.u.essid.flags   = 0;

	int has_wifi = (ioctl(fd, SIOCGIWESSID, &wrq) >= 0 &&
	                wrq.u.essid.length > 0);
	essid[wrq.u.essid.length < IW_ESSID_MAX_SIZE ? wrq.u.essid.length
	                                             : IW_ESSID_MAX_SIZE] = '\0';
	close(fd);
	if (!has_wifi)
		return "";

	snprintf(buf, sizeof(buf),
	         "^b%s^^c%s^ %s ^d^ ",
	         C_BG_CARD, C_VALUE, essid);
	return buf;
}

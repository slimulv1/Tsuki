/* See LICENSE file for copyright and license details. */

/* interfaces */
#define IFACE_WIRED "enp8s0"
#define IFACE_WIFI  "wlan0"

/* fonts (Nerd Font Mono: đủ glyph wifi/lock/arrows) */
static const char *font_norm  = "JetBrainsMono Nerd Font Mono:style=Regular:size=11";
static const char *font_bold  = "JetBrainsMono Nerd Font Mono:style=Bold:size=12";
static const char *font_small = "JetBrainsMono Nerd Font Mono:style=Regular:size=9";
static const char *font_icon  = "JetBrainsMono Nerd Font Mono:style=Regular:size=17";

/* palette — đồng bộ slstatus + ảnh reference 2 */
#define C_BG_PANEL   "#16161e"
#define C_BG_CARD    "#2a2a2e"
#define C_BG_HOVER   "#333338"
#define C_BG_SELECT  "#3a3a3a"
#define C_BORDER     "#555555"
#define C_BORDER_DWM "#7842d7" /* viền ngoài panel = viền cửa sổ focused của dwm (themes/wal.h blue[]) */
#define C_LABEL      "#87879b"
#define C_VALUE      "#e0e0e8"
#define C_OK         "#a5d793"
#define C_ERR        "#ff5555"
#define C_ACCENT     "#7842d7"

/* layout */
#define PANEL_W        460
#define PAD            16
#define BAR_FALLBACK_Y 30   /* nếu không dò được cửa sổ bar */
#define MAX_LIST_ITEMS 6    /* số dòng tối đa mỗi list trước khi scroll */

/* tagline xoay dưới SSID (kiểu ảnh: "ROUTING CRUMBS"...) */
static const char *taglines[] = {
	"ROUTING CRUMBS", "COUNTING COLLISIONS", "HERDING PACKETS",
	"CHASING LATENCY", "JUGGLING SUBNETS", "POLISHING FIBER",
};

/* NextDNS: đọc từ systemd-resolved (/etc/systemd/resolved.conf DNS=...#xxx.dns.nextdns.io)
 * Lưu ý: nmcli không hỗ trợ DoT nên chỉ dùng IP anycast (vẫn đúng profile lọc) */
#define NEXTDNS_DNS "45.90.28.0 45.90.30.0"

/* DNS presets: name, dns string cho nmcli (NULL = DHCP/auto) */
static const struct { const char *name; const char *dns; } dns_providers[] = {
	{ "DHCP",       NULL },
	{ "Cloudflare", "1.1.1.1 1.0.0.1" },
	{ "Google",     "8.8.8.8 8.8.4.4" },
	{ "NextDNS",    NEXTDNS_DNS },
	{ "Custom",     "" },
};
#define DNS_NCUSTOM 4 /* index nút Custom */

/* speed test */
#define SPEED_URL "https://speed.cloudflare.com/__down?bytes=104857600"

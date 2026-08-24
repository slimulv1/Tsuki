/* See LICENSE file for copyright and license details. */
/*
 * netpanel — Wi-Fi panel popup thuần C/X11 cho dwm + slstatus.
 * Thiết kế bám ảnh reference ~/Projects/ui-reference*.png/jpg:
 *   header wifi + stats grid 2x4 + DNS provider + Speed Test + network lists.
 * Click trái vào statusbar (dwm ClkStatusText) → netpanel.sh → binary này.
 *
 * Build: make  (cần libx11 libxft libxrender libxext fontconfig)
 */
#include <X11/X.h>
#include <X11/Xlib.h>
#include <X11/Xutil.h>
#include <X11/keysym.h>
#include <X11/cursorfont.h>
#include <X11/extensions/shape.h>
#include <X11/Xft/Xft.h>
#include <arpa/inet.h>
#include <errno.h>
#include <fcntl.h>
#include <net/if.h>
#include <netinet/in.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/file.h>
#include <sys/ioctl.h>
#include <sys/select.h>
#include <sys/socket.h>
#include <sys/wait.h>
#include <time.h>
#include <unistd.h>
#include <linux/wireless.h>

#include "config.h"

/* ============ tiện ích chung ============ */
static void die(const char *msg) { fprintf(stderr, "netpanel: %s\n", msg); exit(1); }
static void *ecalloc(size_t n, size_t s) { void *p = calloc(n, s); if (!p) die("oom"); return p; }

/* quote chuỗi để nhúng an toàn vào shell trong dấu '...' */
static void sh_quote(char *dst, size_t dn, const char *s)
{
	size_t j = 0;
	if (dn < 8 || !s) { if (dn) dst[0] = '\0'; return; }
	dst[j++] = '\'';
	for (; *s && j < dn - 5; s++) {
		if (*s == '\'') {
			dst[j++] = '\''; dst[j++] = '\\'; dst[j++] = '\''; dst[j++] = '\'';
		} else {
			dst[j++] = *s;
		}
	}
	dst[j++] = '\'';
	dst[j] = '\0';
}

static int g_need_redraw = 1;

/* đọc từng dòng từ con trỏ bộ đệm */
static int next_line(char **p, char *dst, size_t dn)
{
	if (!**p) return 0;
	char *nl = strchr(*p, '\n');
	size_t l = nl ? (size_t)(nl - *p) : strlen(*p);
	if (l >= dn) l = dn - 1;
	memcpy(dst, *p, l);
	dst[l] = '\0';
	*p += l + (nl ? 1 : 0);
	return 1;
}

/* ============ dữ liệu mạng (state toàn cục) ============ */
typedef struct NetInfo {
	int has_wired, has_wifi, radio_on;
	char essid[64];
	int perc;
	unsigned long long rx_tot, tx_tot;
	double rx_rate, tx_rate;
	double dl_peak;
	char ip[64], gw[64];
	char ping_s[24], loss_s[12];
	int pinging;
	char conn_name[128];
	int dns_sel, dns_applying;
	char known[64][128]; int known_n;
	char other[64][128]; int other_sig[64]; int other_sec[64]; int other_use[64]; int other_n;
	int scanning, testing;
	time_t t_start;
	unsigned long long rx_at_start;
} NetInfo;

static NetInfo ni;

static int iface_active(char *out_essid, size_t on)
{
	FILE *f = fopen("/sys/class/net/" IFACE_WIRED "/carrier", "r");
	if (f) {
		int c = fgetc(f);
		fclose(f);
		if (c == '1') return 1; /* wired */
	}
	int fd = socket(AF_INET, SOCK_DGRAM, 0);
	if (fd >= 0) {
		char essid[IW_ESSID_MAX_SIZE + 1] = "";
		struct iwreq wrq;
		memset(&wrq, 0, sizeof(wrq));
		snprintf(wrq.ifr_name, IFNAMSIZ, "%s", IFACE_WIFI);
		wrq.u.essid.pointer = essid;
		wrq.u.essid.length = IW_ESSID_MAX_SIZE;
		wrq.u.essid.flags = 0;
		int ok = (ioctl(fd, SIOCGIWESSID, &wrq) >= 0 && wrq.u.essid.length > 0);
		close(fd);
		if (ok) {
			size_t cl = wrq.u.essid.length < IW_ESSID_MAX_SIZE ? wrq.u.essid.length : IW_ESSID_MAX_SIZE;
			if (cl > on - 1) cl = on - 1;
			if (out_essid) { memcpy(out_essid, essid, cl); out_essid[cl] = '\0'; }
			return 2; /* wifi */
		}
	}
	return 0;
}

static void get_signal_perc(void)
{
	ni.perc = 0;
	FILE *wf = fopen("/proc/net/wireless", "r");
	if (!wf) return;
	char line[256], ifn[64];
	while (fgets(line, sizeof(line), wf)) {
		char *colon = strchr(line, ':');
		if (!colon) continue;
		*colon = '\0';
		sscanf(line, "%63s", ifn);
		if (strcmp(ifn, IFACE_WIFI)) continue;
		int link = 0;
		if (sscanf(colon + 1, "%*s %d", &link) == 1 && link > 0)
			ni.perc = link * 100 / 70;
		break;
	}
	fclose(wf);
}

static void get_rx_tx(const char *ifn, unsigned long long *rx, unsigned long long *tx)
{
	*rx = *tx = 0;
	FILE *f = fopen("/proc/net/dev", "r");
	if (!f) return;
	char line[512];
	while (fgets(line, sizeof(line), f)) {
		char name[64];
		char *colon = strchr(line, ':');
		if (!colon) continue;
		*colon = '\0';
		sscanf(line, "%63s", name);
		if (strcmp(name, ifn)) continue;
		unsigned long long v[16];
		memset(v, 0, sizeof(v));
		int k = 0;
		char *p = colon + 1;
		while (k < 16 && sscanf(p, "%llu", &v[k]) == 1) {
			p = strchr(p, ' ');
			if (!p++) break;
			k++;
		}
		*rx = v[0]; *tx = v[8];
		break;
	}
	fclose(f);
}

static void get_ip_gw(const char *ifn)
{
	ni.ip[0] = ni.gw[0] = '\0';
	int fd = socket(AF_INET, SOCK_DGRAM, 0);
	if (fd >= 0) {
		struct ifreq ir;
		memset(&ir, 0, sizeof(ir));
		snprintf(ir.ifr_name, IFNAMSIZ, "%s", ifn);
		if (ioctl(fd, SIOCGIFADDR, &ir) == 0)
			snprintf(ni.ip, sizeof(ni.ip), "%s",
			         inet_ntoa(((struct sockaddr_in *)&ir.ifr_addr)->sin_addr));
		close(fd);
	}
	FILE *f = fopen("/proc/net/route", "r");
	if (!f) return;
	char line[256];
	fgets(line, sizeof(line), f); /* header */
	while (fgets(line, sizeof(line), f)) {
		char name[64];
		unsigned dest = 0, gate = 0;
		if (sscanf(line, "%63s %x %x", name, &dest, &gate) == 3 &&
		    !strcmp(name, ifn) && dest == 0 && gate != 0) {
			snprintf(ni.gw, sizeof(ni.gw), "%u.%u.%u.%u",
			         gate & 0xff, (gate >> 8) & 0xff, (gate >> 16) & 0xff, (gate >> 24) & 0xff);
			break;
		}
	}
	fclose(f);
}

static void fmt_speed(double bps, char *out, size_t on)
{
	static const char *u[] = { "B/s", "KB/s", "MB/s", "GB/s" };
	int i = 0;
	while (bps >= 1024.0 && i < 3) { bps /= 1024.0; i++; }
	snprintf(out, on, "%.1f %s", bps, u[i]);
}

static void fmt_total(double bytes, char *out, size_t on)
{
	static const char *u[] = { "B", "KB", "MB", "GB", "TB" };
	int i = 0;
	while (bytes >= 1024.0 && i < 4) { bytes /= 1024.0; i++; }
	snprintf(out, on, "%.1f %s", bytes, u[i]);
}

/* ============ job nền bất đồng bộ ============ */
typedef struct Job {
	int fd;
	pid_t pid;
	char out[32768];
	size_t len;
	void (*cb)(struct Job *);
	struct Job *next;
} Job;

static Job *jobs = NULL;

/* fire-and-forget không cần output (tự Reaper dọn zombie) */
static void run_bg(const char *cmd)
{
	pid_t pid = fork();
	if (pid == 0) {
		int dn = open("/dev/null", O_RDWR);
		if (dn >= 0) {
			dup2(dn, STDIN_FILENO); dup2(dn, STDOUT_FILENO); dup2(dn, STDERR_FILENO);
			if (dn > 2) close(dn);
		}
		execl("/bin/sh", "sh", "-c", cmd, (char *)NULL);
		_exit(127);
	}
}

static Job *job_run(const char *cmd, void (*cb)(Job *))
{
	int pfd[2];
	if (pipe(pfd) < 0) return NULL;
	pid_t pid = fork();
	if (pid < 0) { close(pfd[0]); close(pfd[1]); return NULL; }
	if (pid == 0) {
		close(pfd[0]);
		dup2(pfd[1], STDOUT_FILENO);
		close(pfd[1]);
		int dn = open("/dev/null", O_WRONLY);
		if (dn >= 0) { dup2(dn, STDERR_FILENO); if (dn > 2) close(dn); }
		execl("/bin/sh", "sh", "-c", cmd, (char *)NULL);
		_exit(127);
	}
	close(pfd[1]);
	int fl = fcntl(pfd[0], F_GETFL);
	fcntl(pfd[0], F_SETFL, fl | O_NONBLOCK);
	Job *j = ecalloc(1, sizeof(Job));
	j->fd = pfd[0]; j->pid = pid; j->cb = cb;
	j->next = jobs;
	jobs = j;
	return j;
}

static void reap(int sig) { (void)sig; while (waitpid(-1, NULL, WNOHANG) > 0) {} }

static void poll_jobs(void)
{
	Job **pj = &jobs;
	while (*pj) {
		Job *j = *pj;
		char tmp[4096];
		int finished = 0;
		for (;;) {
			ssize_t n = read(j->fd, tmp, sizeof(tmp));
			if (n > 0) {
				if (j->len + (size_t)n < sizeof(j->out) - 1) {
					memcpy(j->out + j->len, tmp, (size_t)n);
					j->len += (size_t)n;
				}
				continue;
			}
			if (n < 0 && (errno == EAGAIN || errno == EWOULDBLOCK))
				break; /* chưa có data */
			finished = 1; /* EOF hoặc lỗi → child xong */
			break;
		}
		if (!finished) {
			pj = &j->next;
			continue;
		}
		int st = 0;
		pid_t r = waitpid(j->pid, &st, WNOHANG);
		if (r == j->pid || r < 0) {
			Job *nx = j->next;
			j->out[j->len] = '\0';
			*pj = nx;
			close(j->fd);
			if (j->cb) j->cb(j);
			free(j);
			continue; /* *pj đã trỏ sang node kế */
		}
		pj = &j->next; /* pipe đóng nhưng child chưa thoát → chờ lần sau */
	}
}

/* ============ các job cụ thể ============ */

/* --- ping gateway --- */
static time_t last_ping = 0;
static void cb_ping(Job *j)
{
	ni.pinging = 0;
	float avg = -1.0f;
	int loss = -1;
	char line[512];
	char *p = j->out;
	while (next_line(&p, line, sizeof(line))) {
		float mn, av, mx, md;
		int pc;
		if ((sscanf(line, "%*d packets transmitted, %*d received, %d%% packet loss", &pc) == 1 ||
		     sscanf(line, "%*d packets transmitted, %*d received, +%*d errors, %d%% packet loss", &pc) == 1))
			loss = pc;
		if (sscanf(line, "rtt min/avg/max/mdev = %f/%f/%f/%f ms", &mn, &av, &mx, &md) == 4 ||
		    sscanf(line, "round-trip min/avg/max/mdev = %f/%f/%f/%f ms", &mn, &av, &mx, &md) == 4)
			avg = av;
	}
	if (avg >= 0) snprintf(ni.ping_s, sizeof(ni.ping_s), "%.1f ms", avg);
	else snprintf(ni.ping_s, sizeof(ni.ping_s), "—");
	if (loss >= 0) snprintf(ni.loss_s, sizeof(ni.loss_s), "%d%%", loss);
	else snprintf(ni.loss_s, sizeof(ni.loss_s), "—");
	g_need_redraw = 1;
}

static void kick_ping(void)
{
	if (ni.pinging || !ni.gw[0]) return;
	if (time(NULL) - last_ping < 5) return;
	last_ping = time(NULL);
	ni.pinging = 1;
	char qg[128], cmd[512];
	sh_quote(qg, sizeof(qg), ni.gw);
	snprintf(cmd, sizeof(cmd), "ping -c 3 -W 1 %s 2>/dev/null", qg);
	if (!job_run(cmd, cb_ping)) ni.pinging = 0;
}

/* --- status tổng hợp mỗi ~5s --- */
static void cb_status(Job *j)
{
	ni.scanning = 0;
	ni.known_n = 0;
	ni.other_n = 0;
	char *p = j->out;
	char line[512];
	int mode = 0; /* 0=meta, 1=known list, 2=scan list */
	while (next_line(&p, line, sizeof(line))) {
		if (!strncmp(line, "radio ", 6)) {
			ni.radio_on = strstr(line + 6, "enabled") != NULL;
		} else if (!strncmp(line, "conn ", 5)) {
			snprintf(ni.conn_name, sizeof(ni.conn_name), "%s", line + 5);
		} else if (!strncmp(line, "dns ", 4)) {
			const char *d = line + 4;
			ni.dns_sel = strstr(d, "1.1.1.1") || strstr(d, "1.0.0.1") ? 1
			           : strstr(d, "8.8.8.8") || strstr(d, "8.8.4.4") ? 2
			           : (d[0] && strcmp(d, "--")) ? 3 : 0;
		} else if (!strcmp(line, "__KNOWN__")) {
			mode = 1;
		} else if (!strcmp(line, "__SCAN__")) {
			mode = 2;
		} else if (line[0]) {
			if (mode == 1 && ni.known_n < 64) {
				snprintf(ni.known[ni.known_n++], 128, "%s", line);
			} else if (mode == 2 && ni.other_n < 64) {
				char use[8] = "", ssid[96] = "", sec[32] = "";
				int sig = 0;
				if (sscanf(line, "%7[^:]:%d:%95[^:]:%31[^\n]", use, &sig, ssid, sec) >= 3) {
					snprintf(ni.other[ni.other_n], 128, "%s", ssid);
					ni.other_sig[ni.other_n] = sig;
					ni.other_sec[ni.other_n] = sec[0] && strcmp(sec, "--") ? 1 : 0;
					ni.other_use[ni.other_n] = (use[0] == '*');
					ni.other_n++;
				}
			}
		}
	}
	g_need_redraw = 1;
}

static int rescan_requested = 0;
static void kick_status(void)
{
	const char *rescan = rescan_requested ? "--rescan yes" : "";
	rescan_requested = 0;
	char cmd[1024];
	snprintf(cmd, sizeof(cmd),
	         "echo \"radio $(nmcli radio wifi)\";"
	         "IF=" IFACE_WIFI ";"
	         "nmcli -t -f NAME,DEVICE connection show --active | grep -m1 \":$IF\" | cut -d: -f1 | sed 's/^/conn /';"
	         "echo \"dns $(nmcli -t --get-values IP4.DNS device show $IF 2>/dev/null | grep -v '^$' | head -n1)\";"
	         "echo __KNOWN__;"
	         "nmcli -t -f NAME,TYPE connection show 2>/dev/null | grep 802-11-wireless | cut -d: -f1;"
	         "if [ \"$(nmcli radio wifi)\" = enabled ]; then echo __SCAN__;"
	         "nmcli -t -f IN-USE,SIGNAL,SSID,SECURITY dev wifi list %s 2>/dev/null; fi",
	         rescan);
	if (rescan[0]) ni.scanning = 1;
	job_run(cmd, cb_status);
}

/* --- apply DNS --- */
static void ask_custom_dns(void);
static void cb_dns_done(Job *j)
{
	(void)j;
	ni.dns_applying = 0;
	kick_status();
	g_need_redraw = 1;
}

static void apply_dns(int idx)
{
	if (ni.dns_applying || !ni.conn_name[0]) return;
	if (idx == DNS_NCUSTOM) { ask_custom_dns(); return; }
	const char *dns = dns_providers[idx].dns ? dns_providers[idx].dns : "";
	const char *ignore = idx == 0 ? "no" : "yes";
	char qc[300], cmd[900];
	sh_quote(qc, sizeof(qc), ni.conn_name);
	snprintf(cmd, sizeof(cmd),
	         "nmcli con mod %s ipv4.ignore-auto-dns %s ipv4.dns '%s' && nmcli con up %s",
	         qc, ignore, dns, qc);
	ni.dns_applying = 1;
	g_need_redraw = 1;
	job_run(cmd, cb_dns_done);
}

static void cb_custom_dns(Job *j)
{
	char ip[128];
	if (sscanf(j->out, "%127s", ip) == 1 && strchr(ip, '.') && ni.conn_name[0]) {
		char qc[300], cmd[900];
		sh_quote(qc, sizeof(qc), ni.conn_name);
		snprintf(cmd, sizeof(cmd),
		         "nmcli con mod %s ipv4.ignore-auto-dns yes ipv4.dns '%s' && nmcli con up %s",
		         qc, ip, qc);
		run_bg(cmd);
		kick_status();
	}
}

static void ask_custom_dns(void)
{
	job_run("dmenu -P -p 'Custom DNS:' </dev/null", cb_custom_dns);
}

/* --- toggle wifi --- */
static void toggle_wifi(void)
{
	run_bg(ni.radio_on ? "nmcli radio wifi off" : "nmcli radio wifi on");
	ni.radio_on = !ni.radio_on;
	ni.has_wifi = 0;
	ni.essid[0] = '\0';
	g_need_redraw = 1;
	kick_status();
}

/* --- connect/disconnect --- */
static char pending_connect[128] = "";
static void cb_password(Job *j)
{
	size_t l = j->len;
	while (l && (j->out[l - 1] == '\n' || j->out[l - 1] == '\r')) l--;
	if (l == 0 || l >= 120) return;
	char pw[128];
	memcpy(pw, j->out, l);
	pw[l] = '\0';
	char qp[300], qs[300], cmd[1000];
	sh_quote(qp, sizeof(qp), pw);
	sh_quote(qs, sizeof(qs), pending_connect);
	snprintf(cmd, sizeof(cmd), "nmcli dev wifi connect %s password %s", qs, qp);
	run_bg(cmd);
	pending_connect[0] = '\0';
	/* refresh sau 3s cho nmcli kịp nối */
	run_bg("( sleep 3; killall -USR1 netpanel 2>/dev/null ) >/dev/null 2>&1 &");
}

static void do_connect(const char *ssid)
{
	for (int i = 0; i < ni.known_n; i++)
		if (!strcmp(ni.known[i], ssid)) {
			char qs[300], cmd[512];
			sh_quote(qs, sizeof(qs), ssid);
			snprintf(cmd, sizeof(cmd), "nmcli con up %s", qs);
			run_bg(cmd);
			g_need_redraw = 1;
			return;
		}
	snprintf(pending_connect, sizeof(pending_connect), "%s", ssid);
	char qs[300], cmd[600];
	sh_quote(qs, sizeof(qs), ssid);
	snprintf(cmd, sizeof(cmd), "dmenu -P -p 'Password (%s):' </dev/null", qs);
	job_run(cmd, cb_password);
}

static void do_disconnect(void)
{
	run_bg("nmcli dev disconnect " IFACE_WIFI);
	g_need_redraw = 1;
}

/* --- QR --- */
static void show_qr(void)
{
	if (!ni.has_wifi) return;
	char qs[200], cmd[700];
	sh_quote(qs, sizeof(qs), ni.essid);
	snprintf(cmd, sizeof(cmd),
	         "qrencode -t PNG -s 8 -o /tmp/netpanel-qr.png 'WIFI:T:WPA;S:%s;;'"
	         " && feh --title netpanel-qr /tmp/netpanel-qr.png",
	         qs);
	run_bg(cmd);
}

/* --- speed test --- */
static void start_speedtest(void)
{
	if (ni.testing) return;
	unsigned long long dummy;
	get_rx_tx(IFACE_WIFI, &ni.rx_at_start, &dummy);
	ni.testing = 1;
	ni.t_start = time(NULL);
	ni.dl_peak = 0;
	run_bg("curl -s -o /dev/null --max-time 12 '" SPEED_URL "' ; killall -USR1 netpanel 2>/dev/null");
}

static void tick_speedtest(void)
{
	if (!ni.testing) return;
	double dt = difftime(time(NULL), ni.t_start);
	if (dt <= 0) dt = 1;
	unsigned long long rx_now, tx_now;
	get_rx_tx(IFACE_WIFI, &rx_now, &tx_now);
	double mbps = (double)(rx_now - ni.rx_at_start) / dt / (1024.0 * 1024.0);
	if (mbps > ni.dl_peak) ni.dl_peak = mbps;
	g_need_redraw = 1;
}

/* SIGUSR1: curl xong hoặc sau-connect refresh */
static volatile sig_atomic_t got_usr1 = 0;
static void on_usr1(int sig) { (void)sig; got_usr1 = 1; }

/* SIGUSR2: instance khác yêu cầu đóng (click icon lần 2 = toggle) */
static volatile sig_atomic_t got_usr2 = 0;
static void on_usr2(int sig) { (void)sig; got_usr2 = 1; }

/* ============ X11 render ============ */
static Display *dpy;
static Window root, win;
static int scr;
static Pixmap pm;
static GC gc;
static XftDraw *xftdraw;
static XftFont *f_norm, *f_bold, *f_small, *f_icon;
static Colormap cmap;
static Visual *vis;
static Cursor cur_hand, cur_norm;

static XftColor bg_panel, bg_card, bg_hover, bg_select, border_c, label_c, value_c,
                ok_c, err_c, white_c;

#define CLR(dst, src) do { if (!XftColorAllocName(dpy, vis, cmap, (src), &(dst))) die("color " #dst); } while (0)

static int hover_id = -1;

typedef struct { int id, x, y, w, h; } Hit;
static Hit hits[192];
static int hits_n;

enum {
	ID_TOGGLE = 1, ID_QR,
	ID_DNS0, ID_DNS1, ID_DNS2, ID_DNS3,
	ID_RUN, ID_RESCAN,
	ID_KNOWN_BASE = 100, ID_OTHER_BASE = 200,
};

static void add_hit(int id, int x, int y, int w, int h)
{
	if (hits_n < 192) {
		hits[hits_n].id = id; hits[hits_n].x = x; hits[hits_n].y = y;
		hits[hits_n].w = w; hits[hits_n].h = h;
		hits_n++;
	}
}

static int hit_at(int mx, int my)
{
	for (int i = hits_n - 1; i >= 0; i--)
		if (mx >= hits[i].x && mx < hits[i].x + hits[i].w &&
		    my >= hits[i].y && my < hits[i].y + hits[i].h)
			return hits[i].id;
	return -1;
}

static int textw(XftFont *fnt, const char *s)
{
	XGlyphInfo ext;
	XftTextExtentsUtf8(dpy, fnt, (FcChar8 *)s, strlen(s), &ext);
	return ext.width;
}

static void draw_text(int x, int y, const char *s, XftFont *fnt, XftColor *col)
{
	XftDrawStringUtf8(xftdraw, col, fnt, x, y, (FcChar8 *)s, strlen(s));
}

static void draw_text_r(int xr, int y, const char *s, XftFont *fnt, XftColor *col)
{
	draw_text(xr - textw(fnt, s), y, s, fnt, col);
}

/* rounded rect: fill (+ stroke tuỳ chọn) bằng rect + 4 arc */
static void rrect_fill(int x, int y, int w, int h, int r, unsigned long fillpix)
{
	if (w <= 0 || h <= 0) return;
	if (2 * r > h) r = h / 2;
	if (2 * r > w) r = w / 2;
	XSetForeground(dpy, gc, fillpix);
	XFillRectangle(dpy, pm, gc, x + r, y, w - 2 * r, h);
	XFillRectangle(dpy, pm, gc, x, y + r, w, h - 2 * r);
	XFillArc(dpy, pm, gc, x, y, 2 * r, 2 * r, 90 * 64, 180 * 64);
	XFillArc(dpy, pm, gc, x + w - 2 * r, y, 2 * r, 2 * r, 270 * 64, 180 * 64);
	XFillArc(dpy, pm, gc, x, y + h - 2 * r, 2 * r, 2 * r, 180 * 64, 180 * 64);
	XFillArc(dpy, pm, gc, x + w - 2 * r, y + h - 2 * r, 2 * r, 2 * r, 0 * 64, 180 * 64);
}

static void rrect_stroke(int x, int y, int w, int h, int r, unsigned long pix)
{
	if (2 * r > h) r = h / 2;
	if (2 * r > w) r = w / 2;
	XSetForeground(dpy, gc, pix);
	XDrawLine(dpy, pm, gc, x + r, y, x + w - r, y);
	XDrawLine(dpy, pm, gc, x + r, y + h - 1, x + w - r, y + h - 1);
	XDrawLine(dpy, pm, gc, x, y + r, x, y + h - r);
	XDrawLine(dpy, pm, gc, x + w - 1, y + r, x + w - 1, y + h - r);
	XDrawArc(dpy, pm, gc, x, y, 2 * r, 2 * r, 90 * 64, 180 * 64);
	XDrawArc(dpy, pm, gc, x + w - 2 * r, y, 2 * r, 2 * r, 270 * 64, 180 * 64);
	XDrawArc(dpy, pm, gc, x, y + h - 2 * r, 2 * r, 2 * r, 180 * 64, 180 * 64);
	XDrawArc(dpy, pm, gc, x + w - 2 * r, y + h - 2 * r, 2 * r, 2 * r, 0 * 64, 180 * 64);
}

static void draw_toggle(int x, int y, int on)
{
	int w = 36, h = 18;
	rrect_fill(x, y, w, h, h / 2, (on ? ok_c : border_c).pixel);
	XSetForeground(dpy, gc, white_c.pixel);
	XFillArc(dpy, pm, gc, on ? x + w - h + 2 : x + 2, y + 2, h - 4, h - 4, 0, 360 * 64);
}

static void draw_button(int id, int x, int y, int w, int h, const char *label, int selected)
{
	int hovered = (hover_id == id);
	rrect_fill(x, y, w, h, h / 2 - 1,
	           selected ? bg_select.pixel : hovered ? bg_hover.pixel : bg_panel.pixel);
	rrect_stroke(x, y, w, h, h / 2 - 1, border_c.pixel);
	XftColor *tc = selected ? &value_c : hovered ? &value_c : &label_c;
	draw_text(x + (w - textw(f_small, label)) / 2,
	          y + (h - f_small->height) / 2 + f_small->ascent, label, f_small, tc);
	add_hit(id, x, y, w, h);
}

static const char *spinner(void)
{
	static const char *sp[] = { "⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏" };
	return sp[(unsigned long)(time(NULL) * 10) % 10];
}

/* ============ layout ============ */
#define GRID_ROWS 4
static const char *grid_labels[GRID_ROWS][2] = {
	{ "Ping",       "Packet Loss" },
	{ "Receiving",  "Sending"     },
	{ "Downloaded", "Uploaded"    },
	{ "IP Address", "Gateway"     },
};

static int panel_height(void)
{
	int h = PAD;
	h += 44;                                  /* header */
	h += 10 + GRID_ROWS * 32 + 14;            /* grid */
	h += 34 + 28 + 14;                        /* dns */
	h += 34 + 28 + 14;                        /* speed test */
	h += 34;                                  /* known title */
	h += (ni.known_n ? (ni.known_n > MAX_LIST_ITEMS ? MAX_LIST_ITEMS : ni.known_n) : 1) * 32;
	h += 14 + 34;                             /* gap + other title */
	h += (ni.other_n ? (ni.other_n > MAX_LIST_ITEMS ? MAX_LIST_ITEMS : ni.other_n) : 1) * 32;
	h += PAD;
	return h;
}

static void draw_panel(void)
{
	hits_n = 0;
	int W = PANEL_W;
	rrect_fill(0, 0, W, panel_height(), 14, bg_panel.pixel);

	int y = PAD;
	const int x = PAD;

	/* ---- header ---- */
	{
		const char *icon = ni.has_wired ? "󰈀" : !ni.radio_on ? "󰤭"
		                 : ni.perc >= 67 ? "󰤨" : ni.perc >= 34 ? "󰤧" : "󰤦";
		XftColor *ic = (!ni.has_wifi && !ni.has_wired) ? &err_c : &value_c;
		draw_text(x, y + 26, icon, f_icon, ic);

		int tx = x + 34;
		const char *title = ni.has_wired ? "Wired" : ni.has_wifi ? ni.essid
		                  : ni.radio_on ? "Wi-Fi" : "Wi-Fi off";
		draw_text(tx, y + 18, title, f_bold, &value_c);
		const char *tag = taglines[(unsigned long)(time(NULL) / 3600) %
		                           (sizeof(taglines) / sizeof(taglines[0]))];
		draw_text(tx, y + 33, tag, f_small, &label_c);

		int qx = W - PAD - 46 - 22;
		draw_text(qx, y + 21, "󰑖", f_icon, hover_id == ID_QR ? &value_c : &label_c);
		add_hit(ID_QR, qx - 6, y, 34, 28);
		draw_toggle(W - PAD - 36, y + 5, ni.radio_on);
		add_hit(ID_TOGGLE, W - PAD - 46, y - 2, 46, 32);
	}
	y += 44 + 8;

	/* ---- stats grid ---- */
	{
		int colw = (W - 2 * PAD - 24) / 2;
		static double last_rx = -1, last_tx = -1;
		static struct timespec lts = { 0, 0 };
		struct timespec ts;
		clock_gettime(CLOCK_MONOTONIC, &ts);
		double dt = (double)(ts.tv_sec - lts.tv_sec) + (double)(ts.tv_nsec - lts.tv_nsec) / 1e9;
		if (lts.tv_sec && dt > 0.2) {
			unsigned long long rx, tx;
			get_rx_tx(IFACE_WIFI, &rx, &tx);
			ni.rx_rate = (last_rx >= 0 && rx >= (unsigned long long)last_rx) ? ((double)rx - last_rx) / dt : 0;
			ni.tx_rate = (last_tx >= 0 && tx >= (unsigned long long)last_tx) ? ((double)tx - last_tx) / dt : 0;
			last_rx = (double)rx; last_tx = (double)tx;
			ni.rx_tot = rx; ni.tx_tot = tx;
		}
		lts = ts;

		static char v[8][48];
		const char *vals[GRID_ROWS][2];
		vals[0][0] = ni.ping_s;
		vals[0][1] = ni.loss_s;
		fmt_speed(ni.rx_rate, v[0], sizeof(v[0]));
		fmt_speed(ni.tx_rate, v[1], sizeof(v[1]));
		vals[1][0] = (ni.has_wifi || ni.has_wired) ? v[0] : "—";
		vals[1][1] = (ni.has_wifi || ni.has_wired) ? v[1] : "—";
		fmt_total((double)ni.rx_tot, v[2], sizeof(v[2]));
		fmt_total((double)ni.tx_tot, v[3], sizeof(v[3]));
		vals[2][0] = v[2]; vals[2][1] = v[3];
		vals[3][0] = ni.ip[0] ? ni.ip : "—";
		vals[3][1] = ni.gw[0] ? ni.gw : "—";

		for (int r = 0; r < GRID_ROWS; r++) {
			for (int c = 0; c < 2; c++) {
				int cx = PAD + c * (colw + 24);
				draw_text(cx, y + 15, grid_labels[r][c], f_small, &label_c);
				draw_text_r(cx + colw, y + 16, vals[r][c], f_norm, &value_c);
			}
			y += 32;
		}
	}
	y += 14;

	/* ---- DNS provider ---- */
	draw_text(PAD, y + 9, "DNS PROVIDER", f_small, &label_c);
	y += 34;
	{
		int bn = (int)(sizeof(dns_providers) / sizeof(dns_providers[0]));
		int gap = 8;
		int bw = (W - 2 * PAD - (bn - 1) * gap) / bn;
		for (int i = 0; i < bn; i++)
			draw_button(ID_DNS0 + i, PAD + i * (bw + gap), y, bw, 26,
			            dns_providers[i].name,
			            ni.dns_sel == i && !ni.dns_applying);
	}
	y += 30 + 14;

	/* ---- speed test ---- */
	draw_text(PAD, y + 9, "SPEED TEST", f_small, &label_c);
	{
		char spbuf[64] = "";
		if (ni.testing)
			snprintf(spbuf, sizeof(spbuf), "%s %.1f MB/s", spinner(), ni.dl_peak);
		else if (ni.dl_peak > 0)
			snprintf(spbuf, sizeof(spbuf), "%.1f MB/s", ni.dl_peak);
		draw_text(PAD + textw(f_small, "SPEED TEST") + 12, y + 9, spbuf, f_small,
		          ni.testing ? &ok_c : &label_c);
	}
	y += 34;
	draw_button(ID_RUN, W - PAD - 84, y, 84, 26, ni.testing ? "Running…" : "Run", 0);
	y += 28 + 14;

	/* ---- known networks ---- */
	{
		draw_text(PAD, y + 9, "KNOWN NETWORKS", f_small, &label_c);
		y += 34;
		int n = ni.known_n;
		if (!n) {
			draw_text(PAD, y + 16, ni.radio_on ? "(chưa có profile đã lưu)" : "(wi-fi đang tắt)",
			          f_small, &label_c);
			y += 32;
		}
		for (int i = 0; i < n && i < MAX_LIST_ITEMS; i++) {
			int is_cur = ni.has_wifi && !strcmp(ni.known[i], ni.essid);
			if (is_cur)
				rrect_fill(PAD - 8, y, W - 2 * PAD + 16, 28, 6, bg_card.pixel);
			else if (hover_id == ID_KNOWN_BASE + i)
				rrect_fill(PAD - 8, y, W - 2 * PAD + 16, 28, 6, bg_hover.pixel);
			draw_text(PAD, y + 19, "󰤨", f_norm, is_cur ? &ok_c : &label_c);
			draw_text(PAD + 26, y + 19, ni.known[i],
			          is_cur ? f_bold : f_norm, is_cur ? &value_c : &label_c);
			if (is_cur)
				draw_text_r(W - PAD - 20, y + 19, "Connected", f_small, &ok_c);
			draw_text_r(W - PAD, y + 19, "", f_small, &label_c);
			add_hit(ID_KNOWN_BASE + i, PAD - 8, y, W - 2 * PAD + 16, 30);
			y += 32;
		}
	}
	y += 14;

	/* ---- other networks ---- */
	{
		char ttl[80];
		snprintf(ttl, sizeof(ttl), "OTHER NETWORKS%s%s",
		         ni.scanning ? "  " : "", ni.scanning ? spinner() : "");
		draw_text(PAD, y + 9, ttl, f_small, &label_c);
		draw_text_r(W - PAD, y + 9, "⟳ Rescan", f_small,
		            hover_id == ID_RESCAN ? &value_c : &label_c);
		add_hit(ID_RESCAN, W - PAD - 76, y - 4, 80, 20);
		y += 34;
		int n = ni.other_n;
		if (!n) {
			draw_text(PAD, y + 16,
			          !ni.radio_on ? "(wi-fi đang tắt)"
			            : ni.scanning ? "đang quét…"
			            : "(không thấy mạng nào)",
			          f_small, &label_c);
			y += 32;
		}
		for (int i = 0; i < n && i < MAX_LIST_ITEMS; i++) {
			int is_cur = ni.has_wifi && !strcmp(ni.other[i], ni.essid);
			if (!is_cur && hover_id == ID_OTHER_BASE + i)
				rrect_fill(PAD - 8, y, W - 2 * PAD + 16, 28, 6, bg_hover.pixel);
			const char *sig_i = ni.other_sig[i] >= 75 ? "󰤨"
			                  : ni.other_sig[i] >= 50 ? "󰤧"
			                  : ni.other_sig[i] >= 25 ? "󰤦" : "󰤟";
			draw_text(PAD, y + 19, sig_i, f_norm, is_cur ? &ok_c : &label_c);
			draw_text(PAD + 26, y + 19, ni.other[i],
			          is_cur ? f_bold : f_norm, is_cur ? &value_c : &label_c);
			if (ni.other_sec[i])
				draw_text_r(W - PAD, y + 19, "", f_small, &label_c);
			add_hit(ID_OTHER_BASE + i, PAD - 8, y, W - 2 * PAD + 16, 30);
			y += 32;
		}
	}
	y += PAD;
	(void)x; (void)y;
}

/* ============ tương tác ============ */
static void handle_click(int id)
{
	switch (id) {
	case ID_TOGGLE: toggle_wifi(); break;
	case ID_QR: show_qr(); break;
	case ID_RUN: start_speedtest(); break;
	case ID_RESCAN:
		rescan_requested = 1;
		kick_status();
		g_need_redraw = 1;
		break;
	default:
		if (id >= ID_DNS0 && id <= ID_DNS3)
			apply_dns(id - ID_DNS0);
		else if (id >= ID_OTHER_BASE) {
			int i = id - ID_OTHER_BASE;
			if (i < ni.other_n) {
				if (ni.other_use[i]) do_disconnect();
				else do_connect(ni.other[i]);
			}
		} else if (id >= ID_KNOWN_BASE) {
			int i = id - ID_KNOWN_BASE;
			if (i < ni.known_n) {
				if (ni.has_wifi && !strcmp(ni.known[i], ni.essid)) do_disconnect();
				else do_connect(ni.known[i]);
			}
		}
	}
}

/* ============ main ============ */
static void reshape_mask(int H)
{
	Pixmap mask = XCreatePixmap(dpy, win, PANEL_W, H, 1);
	GC mgc = XCreateGC(dpy, mask, 0, NULL);
	XSetForeground(dpy, mgc, 0);
	XFillRectangle(dpy, mask, mgc, 0, 0, PANEL_W, H);
	XSetForeground(dpy, mgc, 1);
	int r = 14;
	XFillRectangle(dpy, mask, mgc, r, 0, PANEL_W - 2 * r, H);
	XFillRectangle(dpy, mask, mgc, 0, r, PANEL_W, H - 2 * r);
	XFillArc(dpy, mask, mgc, 0, 0, 2 * r, 2 * r, 90 * 64, 180 * 64);
	XFillArc(dpy, mask, mgc, PANEL_W - 2 * r, 0, 2 * r, 2 * r, 270 * 64, 180 * 64);
	XFillArc(dpy, mask, mgc, 0, H - 2 * r, 2 * r, 2 * r, 180 * 64, 180 * 64);
	XFillArc(dpy, mask, mgc, PANEL_W - 2 * r, H - 2 * r, 2 * r, 2 * r, 0 * 64, 180 * 64);
	XShapeCombineMask(dpy, win, ShapeBounding, 0, 0, mask, ShapeSet);
	XFreeGC(dpy, mgc);
	XFreePixmap(dpy, mask);
}

int main(void)
{
	memset(&ni, 0, sizeof(ni));
	snprintf(ni.ping_s, sizeof(ni.ping_s), "…");
	snprintf(ni.loss_s, sizeof(ni.loss_s), "…");

	signal(SIGCHLD, reap);
	signal(SIGUSR1, on_usr1);
	signal(SIGUSR2, on_usr2);

	/* --- khóa single-instance: click icon lần 2 → USR2 bảo instance cũ đóng --- */
	int lockfd = open("/tmp/netpanel.lock", O_RDWR | O_CREAT, 0600);
	if (lockfd < 0)
		die("lockfile");
	if (flock(lockfd, LOCK_EX | LOCK_NB) < 0) {
		char pidbuf[32] = "";
		ssize_t n = pread(lockfd, pidbuf, sizeof(pidbuf) - 1, 0);
		(void)n;
		pid_t op = (pid_t)atoi(pidbuf);
		if (op > 1)
			kill(op, SIGUSR2);
		close(lockfd);
		return 0; /* đã có panel mở */
	}
	ftruncate(lockfd, 0);
	dprintf(lockfd, "%d", (int)getpid());

	dpy = XOpenDisplay(NULL);
	if (!dpy) die("cannot open display");
	scr = DefaultScreen(dpy);
	root = RootWindow(dpy, scr);
	vis = DefaultVisual(dpy, scr);
	cmap = DefaultColormap(dpy, scr);
	gc = XCreateGC(dpy, root, 0, NULL);

	CLR(bg_panel, C_BG_PANEL); CLR(bg_card, C_BG_CARD); CLR(bg_hover, C_BG_HOVER);
	CLR(bg_select, C_BG_SELECT); CLR(border_c, C_BORDER); CLR(label_c, C_LABEL);
	CLR(value_c, C_VALUE); CLR(ok_c, C_OK); CLR(err_c, C_ERR); CLR(white_c, "#ffffff");

	f_norm = XftFontOpenName(dpy, scr, font_norm);
	f_bold = XftFontOpenName(dpy, scr, font_bold);
	f_small = XftFontOpenName(dpy, scr, font_small);
	f_icon = XftFontOpenName(dpy, scr, font_icon);
	if (!f_norm || !f_bold || !f_small || !f_icon) die("font");

	cur_hand = XCreateFontCursor(dpy, XC_hand2);
	cur_norm = XCreateFontCursor(dpy, XC_left_ptr);

	/* dò bar dwm: cửa sổ con của root, rộng ≈ màn hình, cao < 80, y = 0 */
	int sw = DisplayWidth(dpy, scr);
	int bar_h = BAR_FALLBACK_Y;
	Window rr, pr, *ch = NULL;
	unsigned int nc = 0;
	if (XQueryTree(dpy, root, &rr, &pr, &ch, &nc) && ch) {
		for (unsigned int i = 0; i < nc; i++) {
			XWindowAttributes a;
			if (XGetWindowAttributes(dpy, ch[i], &a) &&
			    a.y == 0 && a.width >= sw - 8 && a.height > 8 && a.height < 80) {
				bar_h = a.height + a.border_width;
				break;
			}
		}
		XFree(ch);
	}

	int H = panel_height();
	XSetWindowAttributes wa;
	wa.override_redirect = True;
	wa.background_pixel = bg_panel.pixel;
	wa.border_pixel = 0;
	wa.event_mask = ExposureMask | ButtonPressMask | ButtonReleaseMask |
	                PointerMotionMask | KeyPressMask | StructureNotifyMask;
	win = XCreateWindow(dpy, root, sw - PANEL_W - 8, bar_h + 2, PANEL_W, H, 0,
	                    CopyFromParent, InputOutput, CopyFromParent,
	                    CWOverrideRedirect | CWBackPixel | CWBorderPixel | CWEventMask, &wa);
	reshape_mask(H);
	pm = XCreatePixmap(dpy, win, PANEL_W, H, DefaultDepth(dpy, scr));
	xftdraw = XftDrawCreate(dpy, pm, vis, cmap);

	XMapRaised(dpy, win);
	XSync(dpy, False); /* bắt buộc: đảm bảo server đã map xong trước khi grab */

	/* chờ cửa sổ viewable để tránh GrabNotViewable (nguyên nhân mất Esc/click) */
	{
		int tries;
		for (tries = 0; tries < 50; tries++) {
			XWindowAttributes a;
			XGetWindowAttributes(dpy, win, &a);
			if (a.map_state == IsViewable)
				break;
			usleep(20000);
		}
	}
	int kgrab = XGrabKeyboard(dpy, win, True, GrabModeAsync, GrabModeAsync, CurrentTime);
	int pgrab = XGrabPointer(dpy, win, True,
	             ButtonPressMask | ButtonReleaseMask | PointerMotionMask,
	             GrabModeAsync, GrabModeAsync, None, None, CurrentTime);
	if (kgrab != GrabSuccess || pgrab != GrabSuccess)
		fprintf(stderr, "netpanel: grab failed k=%d p=%d\n", kgrab, pgrab);
	XSetInputFocus(dpy, win, RevertToNone, CurrentTime);
	XSync(dpy, False);

	/* dữ liệu ban đầu */
	{
		int mode = iface_active(ni.essid, sizeof(ni.essid));
		ni.has_wired = (mode == 1);
		ni.has_wifi = (mode == 2);
		get_ip_gw(mode ? (mode == 1 ? IFACE_WIRED : IFACE_WIFI) : IFACE_WIFI);
		get_signal_perc();
	}
	kick_ping();
	kick_status();

	int running = 1;
	time_t last_tick = 0;
	while (running) {
		struct timeval tv = { 1, 0 };
		fd_set rf;
		FD_ZERO(&rf);
		FD_SET(ConnectionNumber(dpy), &rf);
		int maxfd = ConnectionNumber(dpy);
		for (Job *j = jobs; j; j = j->next) {
			FD_SET(j->fd, &rf);
			if (j->fd > maxfd) maxfd = j->fd;
		}
		select(maxfd + 1, &rf, NULL, NULL, &tv);

		if (got_usr2) {
			got_usr2 = 0;
			running = 0; /* click icon lần 2 → đóng */
		}

		if (got_usr1) {
			got_usr1 = 0;
			kick_status();
			g_need_redraw = 1;
		}

		poll_jobs();

		while (XPending(dpy)) {
			XEvent ev;
			XNextEvent(dpy, &ev);
			switch (ev.type) {
			case Expose:
				g_need_redraw = 1;
				break;
			case ConfigureNotify:
				g_need_redraw = 1;
				break;
			case MotionNotify: {
				int id = hit_at(ev.xmotion.x, ev.xmotion.y);
				if (id != hover_id) {
					hover_id = id;
					XDefineCursor(dpy, win, id > 0 ? cur_hand : cur_norm);
					g_need_redraw = 1;
				}
				break;
			}
			case ButtonPress:
				if (ev.xbutton.window != win ||
				    ev.xbutton.x < 0 || ev.xbutton.y < 0 ||
				    ev.xbutton.x > PANEL_W || ev.xbutton.y > panel_height()) {
					running = 0;
				} else {
					int id = hit_at(ev.xbutton.x, ev.xbutton.y);
					if (id > 0) handle_click(id);
				}
				break;
			case KeyPress:
				if (XLookupKeysym(&ev.xkey, 0) == XK_Escape) running = 0;
				break;
			default:
				break;
			}
		}

		time_t now = time(NULL);
		tick_speedtest();
		if (now - last_tick >= 5) {
			last_tick = now;
			int mode = iface_active(ni.essid, sizeof(ni.essid));
			ni.has_wired = (mode == 1);
			ni.has_wifi = (mode == 2);
			get_ip_gw(mode == 1 ? IFACE_WIRED : IFACE_WIFI);
			get_signal_perc();
			kick_ping();
			kick_status();
			g_need_redraw = 1;
		}

		if (g_need_redraw) {
			g_need_redraw = 0;
			int newH = panel_height();
			if (newH != H) {
				H = newH;
				XFreePixmap(dpy, pm);
				pm = XCreatePixmap(dpy, win, PANEL_W, H, DefaultDepth(dpy, scr));
				XftDrawChange(xftdraw, pm);
				XResizeWindow(dpy, win, PANEL_W, H);
				reshape_mask(H);
			}
			draw_panel();
			XCopyArea(dpy, pm, win, gc, 0, 0, PANEL_W, H, 0, 0);
			XFlush(dpy);
		}
	}

	XUngrabPointer(dpy, CurrentTime);
	XUngrabKeyboard(dpy, CurrentTime);
	XftDrawDestroy(xftdraw);
	XFreePixmap(dpy, pm);
	XDestroyWindow(dpy, win);
	XSync(dpy, False);
	XCloseDisplay(dpy);
	if (lockfd >= 0) {
		flock(lockfd, LOCK_UN);
		close(lockfd);
		unlink("/tmp/netpanel.lock");
	}
	return 0;
}

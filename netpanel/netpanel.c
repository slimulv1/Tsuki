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
#include <X11/Xatom.h>
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
/* state ô nhập password — khai báo sớm vì cb_status cần ẩn ssid đang thử */
static char pw_ssid[128];
static char pw_buf[64];
static int pw_len;
static int pw_mode;   /* 1 = đang hiện ô nhập password */
static int pw_row;    /* index dòng other-network đang được nhập */

static time_t radio_kick_at;         /* mốc kick_status bổ sung sau toggle */
static int radio_pending;            /* đang chờ nmcli áp dụng on/off */
static time_t radio_pending_until;   /* sau mốc này nhận lại status thật */

static int dns_ignore_auto; /* ipv4.ignore-auto-dns của connection */

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
			/* đang chờ nmcli áp dụng toggle → bỏ qua giá trị CŨ
			   (query trả về trạng thái trước khi đổi, ghi đè sẽ làm
			   toggle nhảy qua lại); hết hạn chờ mới nhận status thật */
			if (radio_pending && time(NULL) < radio_pending_until)
				continue;
			radio_pending = 0;
			ni.radio_on = strstr(line + 6, "enabled") != NULL;
		} else if (!strncmp(line, "conn ", 5)) {
			snprintf(ni.conn_name, sizeof(ni.conn_name), "%s", line + 5);
		} else if (!strncmp(line, "ignore ", 7)) {
			dns_ignore_auto = !strcmp(line + 7, "yes");
		} else if (!strncmp(line, "dnsconf ", 8)) {
			/* DNS tĩnh trên connection; ignore-auto=no hoặc rỗng = DHCP/auto
			   (kể cả khi DNS router cấp cho device) */
			const char *d = line + 8;
			int nprov = (int)(sizeof(dns_providers) / sizeof(dns_providers[0]));
			if (!dns_ignore_auto || !d[0] || !strcmp(d, "--")) {
				ni.dns_sel = 0;
			} else {
				ni.dns_sel = DNS_NCUSTOM;
				for (int k = 1; k < nprov && ni.dns_sel == DNS_NCUSTOM; k++) {
					char tok[48];
					if (!dns_providers[k].dns ||
					    sscanf(dns_providers[k].dns, "%47s", tok) != 1)
						continue;
					if (strstr(d, tok))
						ni.dns_sel = k;
				}
			}
		} else if (!strcmp(line, "__KNOWN__")) {
			mode = 1;
		} else if (!strcmp(line, "__SCAN__")) {
			mode = 2;
		} else if (line[0]) {
			if (mode == 1 && ni.known_n < 64) {
				/* nmcli lưu profile NGAY khi submit (trước khi biết
				 * đúng/sai) → ẩn ssid đang thử khỏi KNOWN cho tới
				 * khi có kết quả, tránh "tự ý" nhảy vào danh sách */
				if (pw_mode && !strcmp(line, pw_ssid))
					continue;
				snprintf(ni.known[ni.known_n++], 128, "%s", line);
			} else if (mode == 2 && ni.other_n < 64) {
				char use[8] = "", ssid[96] = "", sec[32] = "";
				int sig = 0;
				if (sscanf(line, "%7[^:]:%d:%95[^:]:%31[^\n]", use, &sig, ssid, sec) >= 3 &&
				    ssid[0]) { /* bỏ qua mạng ẩn không phát SSID */
					int dup = 0;
					/* đã lưu trong Known Networks → không lặp lại ở OTHER
					   (known luôn parse xong trước vì script xuất trước scan) */
					for (int k = 0; k < ni.known_n && !dup; k++)
						if (!strcmp(ni.known[k], ssid))
							dup = 1;
					/* trùng SSID trong chính list quét (mạng 2 băng tần),
					 * hoặc chính là ssid đang thử mật khẩu */
					for (int k = 0; k < ni.other_n && !dup; k++)
						if (!strcmp(ni.other[k], ssid))
							dup = 1;
					if (pw_mode && !strcmp(ssid, pw_ssid))
						dup = 1;
					if (!dup) {
						snprintf(ni.other[ni.other_n], 128, "%s", ssid);
						ni.other_sig[ni.other_n] = sig;
						ni.other_sec[ni.other_n] = sec[0] && strcmp(sec, "--") ? 1 : 0;
						ni.other_use[ni.other_n] = (use[0] == '*');
						ni.other_n++;
					}
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
	         "C=$(nmcli -t -f NAME,DEVICE connection show --active | grep -m1 \":$IF\" | cut -d: -f1);"
	         "[ -n \"$C\" ] && { nmcli -t -f ipv4.ignore-auto-dns connection show \"$C\" | cut -d: -f2 | sed 's/^/ignore /';"
	         "nmcli -t -f ipv4.dns connection show \"$C\" | cut -d: -f2- | sed 's/^/dnsconf /'; }"
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
	         "nmcli con mod %s ipv4.ignore-auto-dns %s ipv4.dns '%s' && nmcli con up %s"
	         " && resolvectl flush-caches",
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
	/* debounce + serialize: bỏ click trong lúc nmcli chưa kịp áp dụng
	   (tránh 2 lệnh radio song song tranh chấp nhau) */
	if (radio_pending && time(NULL) < radio_pending_until)
		return;
	radio_kick_at = time(NULL) + 3; /* quét lại mạng sớm thay vì đợi tick 5s */
	radio_pending = 1;
	radio_pending_until = time(NULL) + 3; /* chỉ chặn double-click; chặn lâu làm click BẬT bị nuốt */
	run_bg(ni.radio_on ? "nmcli radio wifi off" : "nmcli radio wifi on");
	ni.radio_on = !ni.radio_on; /* optimistic — status thật đến từ cb_status */
	ni.has_wifi = 0;
	ni.essid[0] = '\0';
	g_need_redraw = 1;
	kick_status();
}

/* --- connect/disconnect --- */
/* --- nhập mật khẩu inline ngay dưới dòng SSID được chọn --- */
/* (pw_ssid/pw_buf/pw_len/pw_mode/pw_row đã khai báo sớm phía trên cb_status) */
static int pw_known_before; /* 1 nếu ssid đã là profile đã lưu TRƯỚC khi thử connect
                             * → sai mk thì KHÔNG delete profile (giữ mật khẩu cũ) */

/* trạng thái kết nối sau khi submit mật khẩu (ux: feedback gần vị trí nhập,
 * tự tắt sau ~4s theo quy tắc toast 3-5s của ui-ux-pro-max) */
static int conn_status;   /* 0=none 1=ok 2=wrong pw 3=checking */
static char conn_msg[128];
static time_t conn_msg_until;
static int conn_row;

static void cb_connect_done(Job *j)
{
	/* marker do shell wrapper in ra (fallback: từ khóa lỗi nmcli) */
	if (strstr(j->out, "NETPANEL_FAIL") ||
	    strstr(j->out, "Error") || strstr(j->out, "error") ||
	    strstr(j->out, "failed")) {
		/* sai mật khẩu: profile rác đã được shell wrapper xóa ngay cả
		   khi panel đã đóng trước đó; giữ ô nhập để sửa lại */
		conn_status = 2;
		snprintf(conn_msg, sizeof(conn_msg), "Wrong password — try again");
		if (pw_ssid[0])
			pw_mode = 1;
	} else {
		/* đúng mật khẩu: nmcli tự lưu profile + password */
		conn_status = 1;
		snprintf(conn_msg, sizeof(conn_msg), "Connected to %s", pw_ssid);
		pw_mode = 0;
		pw_len = 0;
		pw_buf[0] = '\0';
	}
	conn_row = pw_row;
	conn_msg_until = time(NULL) + 4;
	kick_status(); /* làm mới KNOWN/OTHER ngay (profile rác đã bị xóa /
	                  profile mới đã được lưu khi thành công) */
	g_need_redraw = 1;
}

static void submit_pw(void)
{
	if (conn_status == 3) return; /* đang chờ kết quả — chống double-submit */
	if (!pw_len || !pw_ssid[0]) { pw_mode = 0; return; }
	char qp[300], qs[300], cmd[1500];
	sh_quote(qp, sizeof(qp), pw_buf);
	sh_quote(qs, sizeof(qs), pw_ssid);
	/* wrapper shell: tự xóa profile rác khi activation fail — phải nằm
	   trong shell (không phải callback) để vẫn chạy dù panel đã đóng
	   giữa chừng nmcli retry 30-60s */
	snprintf(cmd, sizeof(cmd),
	         "out=$(nmcli dev wifi connect %s password %s 2>&1); "
	         "case \"$out\" in *Error*|*error*|*failed*) "
	         "nmcli connection delete %s >/dev/null 2>&1; echo NETPANEL_FAIL; ;; "
	         "*) echo NETPANEL_OK; ;; esac", qs, qp, qs);
	conn_status = 3;
	snprintf(conn_msg, sizeof(conn_msg), "Checking password…");
	conn_row = pw_row;
	conn_msg_until = time(NULL) + 12; /* chỉ dùng hiển thị; pending không tự tắt */
	job_run(cmd, cb_connect_done);
	/* refresh sau 3s cho nmcli kịp nối */
	run_bg("( sleep 3; killall -USR1 netpanel 2>/dev/null ) >/dev/null 2>&1 &");
	/* không xóa pw state ở đây — cb_connect_done quyết định giữ (sai)
	   hay xóa (đúng) để người dùng biết kết quả */
	g_need_redraw = 1;
}

static void do_connect(const char *ssid, int secured)
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
	if (!secured) {
		/* mạng mở — connect luôn không cần mật khẩu */
		char qs[300], cmd[600];
		sh_quote(qs, sizeof(qs), ssid);
		snprintf(cmd, sizeof(cmd), "nmcli dev wifi connect %s", qs);
		run_bg(cmd);
		run_bg("( sleep 3; killall -USR1 netpanel 2>/dev/null ) >/dev/null 2>&1 &");
		g_need_redraw = 1;
		return;
	}
	/* mạng khóa — mở ô nhập mật khẩu trong panel */
	snprintf(pw_ssid, sizeof(pw_ssid), "%s", ssid);
	pw_known_before = 0;
	for (int i = 0; i < ni.known_n; i++)
		if (!strcmp(ni.known[i], ssid)) { pw_known_before = 1; break; }
	pw_mode = 1;
	pw_row = -1;
	/* tìm row để vẽ đúng vị trí */
	for (int i = 0; i < ni.other_n; i++)
		if (!strcmp(ni.other[i], ssid)) { pw_row = i; break; }
	pw_len = 0;
	pw_buf[0] = '\0';
	g_need_redraw = 1;
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
static char st_iface[IFNAMSIZ];  /* interface đang đo */
static int st_failed;            /* curl lỗi / không có kết quả */

/* job xong: curl in %{speed_download} (bytes/s) ra stdout */
static void cb_speedtest(Job *j)
{
	double sp = 0;
	sscanf(j->out, "%lf", &sp);
	ni.testing = 0;
	if (sp > 0) {
		st_failed = 0;
		double mbps = sp / (1024.0 * 1024.0);
		if (mbps > ni.dl_peak) ni.dl_peak = mbps;
	} else {
		st_failed = 1;
	}
	g_need_redraw = 1;
}

static void start_speedtest(void)
{
	if (ni.testing) return;
	int mode = iface_active(ni.essid, sizeof(ni.essid));
	snprintf(st_iface, sizeof(st_iface), "%s", mode == 1 ? IFACE_WIRED : IFACE_WIFI);
	unsigned long long dummy;
	get_rx_tx(st_iface, &ni.rx_at_start, &dummy);
	ni.testing = 1;
	ni.t_start = time(NULL);
	ni.dl_peak = 0;
	st_failed = 0;
	char cmd[512];
	snprintf(cmd, sizeof(cmd),
	         "curl -s -o /dev/null --max-time 15 -w '%%{speed_download}' '" SPEED_URL "' ; echo");
	job_run(cmd, cb_speedtest);
	g_need_redraw = 1;
}

static void tick_speedtest(void)
{
	if (!ni.testing) return;
	double dt = difftime(time(NULL), ni.t_start);
	if (dt <= 0) dt = 1;
	unsigned long long rx_now, tx_now;
	get_rx_tx(st_iface, &rx_now, &tx_now);
	if (rx_now < ni.rx_at_start) return; /* counter reset/wrap */
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
static Window old_focus;   /* focus cần trả lại khi đóng panel */
static int old_revert;

static XftColor bg_panel, bg_card, bg_hover, bg_select, border_c, label_c, value_c,
                ok_c, err_c, white_c, border_dwm;

#define CLR(dst, src) do { if (!XftColorAllocName(dpy, vis, cmap, (src), &(dst))) die("color " #dst); } while (0)

static int hover_id = -1;

typedef struct { int id, x, y, w, h; } Hit;
static Hit hits[192];
static int hits_n;

enum {
	ID_TOGGLE = 1, ID_QR,
	ID_DNS0, ID_DNS1, ID_DNS2, ID_DNS3,
	ID_RUN, ID_RESCAN, ID_PW_CONNECT,
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
	/* track vuông + viền, knob vuông — style sharp đồng bộ panel */
	rrect_fill(x, y, w, h, 0, (on ? ok_c : border_c).pixel);
	rrect_stroke(x, y, w, h, 0, border_dwm.pixel);
	XSetForeground(dpy, gc, white_c.pixel);
	XFillRectangle(dpy, pm, gc, on ? x + w - h + 3 : x + 3, y + 3, h - 6, h - 6);
}

static void draw_button(int id, int x, int y, int w, int h, const char *label, int selected)
{
	int hovered = (hover_id == id);
	rrect_fill(x, y, w, h, 0,
	           selected ? bg_select.pixel : hovered ? bg_hover.pixel : bg_panel.pixel);
	rrect_stroke(x, y, w, h, 0, border_c.pixel);
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
	h += pw_mode ? 46 : 0;                    /* ô nhập mật khẩu inline */
	h += (conn_status && time(NULL) < conn_msg_until) ? 32 : 0; /* banner kết quả */
	h += PAD;
	return h;
}

static void draw_panel(void)
{
	hits_n = 0;
	int W = PANEL_W;
	rrect_fill(0, 0, W, panel_height(), 0, bg_panel.pixel);
	/* viền ngoài 1px màu viền cửa sổ focused của dwm, chạy theo bo góc */
	/* viền ngoài 2px: stroke kép ở mép trong */
	rrect_stroke(0, 0, W, panel_height(), 0, border_dwm.pixel);
	rrect_stroke(1, 1, W - 2, panel_height() - 2, 0, border_dwm.pixel);

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
	draw_text(PAD, y + 9, "\xf3\xb0\xa7\x9b DNS PROVIDER", f_small, &label_c);
	y += 34;
	{
		int bn = (int)(sizeof(dns_providers) / sizeof(dns_providers[0]));
		int gap = 6;
		int bw = (W - 2 * PAD - (bn - 1) * gap) / bn;
		for (int i = 0; i < bn; i++)
			draw_button(ID_DNS0 + i, PAD + i * (bw + gap), y, bw, 26,
			            dns_providers[i].name,
			            ni.dns_sel == i && !ni.dns_applying);
	}
	y += 30 + 14;

	/* ---- speed test ---- */
	draw_text(PAD, y + 9, "\xf3\xb0\x92\x85 SPEED TEST", f_small, &label_c);
	{
		char spbuf[64] = "";
		XftColor *spc = &label_c;
		if (ni.testing) {
			snprintf(spbuf, sizeof(spbuf), "%s %.1f MB/s", spinner(), ni.dl_peak);
			spc = &ok_c;
		} else if (st_failed) {
			snprintf(spbuf, sizeof(spbuf), "Failed");
			spc = &err_c;
		} else if (ni.dl_peak > 0) {
			snprintf(spbuf, sizeof(spbuf), "%.1f MB/s", ni.dl_peak);
		}
		draw_text(PAD + textw(f_small, "\xf3\xb0\x92\x85 SPEED TEST") + 12, y + 9, spbuf, f_small, spc);
	}
	y += 34;
	draw_button(ID_RUN, W - PAD - 84, y, 84, 26, ni.testing ? "Running…" : "Run", 0);
	y += 28 + 14;

	/* ---- known networks ---- */
	{
		draw_text(PAD, y + 9, "\xf3\xb0\x97\xa0 KNOWN NETWORKS", f_small, &label_c);
		y += 34;
		int n = ni.known_n;
		if (!n) {
			draw_text(PAD, y + 16, ni.radio_on ? "(no saved profiles)" : "(wi-fi is off)",
			          f_small, &label_c);
			y += 32;
		}
		for (int i = 0; i < n && i < MAX_LIST_ITEMS; i++) {
			int is_cur = ni.has_wifi && !strcmp(ni.known[i], ni.essid);
			if (is_cur)
				rrect_fill(PAD - 8, y, W - 2 * PAD + 16, 28, 0, bg_card.pixel);
			else if (hover_id == ID_KNOWN_BASE + i)
				rrect_fill(PAD - 8, y, W - 2 * PAD + 16, 28, 0, bg_hover.pixel);
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
		snprintf(ttl, sizeof(ttl), "\xf3\xb0\x80\xa1 OTHER NETWORKS%s%s",
		         ni.scanning ? "  " : "", ni.scanning ? spinner() : "");
		draw_text(PAD, y + 9, ttl, f_small, &label_c);
		draw_text_r(W - PAD, y + 9, "\xf3\xb0\x91\x90 Rescan", f_small,
		            hover_id == ID_RESCAN ? &value_c : &label_c);
		add_hit(ID_RESCAN, W - PAD - 76, y - 4, 80, 20);
		y += 34;
		int n = ni.other_n;
		if (!n) {
			draw_text(PAD, y + 16,
			          !ni.radio_on ? "(wi-fi is off)"
			            : ni.scanning ? "scanning…"
			            : "(no networks found)",
			          f_small, &label_c);
			y += 32;
		}
		for (int i = 0; i < n && i < MAX_LIST_ITEMS; i++) {
			int is_cur = ni.has_wifi && !strcmp(ni.other[i], ni.essid);
			if (!is_cur && hover_id == ID_OTHER_BASE + i)
				rrect_fill(PAD - 8, y, W - 2 * PAD + 16, 28, 0, bg_hover.pixel);
			const char *sig_i = ni.other_sig[i] >= 75 ? "󰤨"
			                  : ni.other_sig[i] >= 50 ? "󰤧"
			                  : ni.other_sig[i] >= 25 ? "󰤦" : "󰤟";
			draw_text(PAD, y + 19, sig_i, f_norm, is_cur ? &ok_c : &label_c);
			draw_text(PAD + 26, y + 19, ni.other[i],
			          is_cur ? f_bold : f_norm, is_cur ? &value_c : &label_c);
			if (ni.other_sec[i])
				draw_text_r(W - PAD, y + 19, "", f_small, &label_c);
			add_hit(ID_OTHER_BASE + i, PAD - 8, y, W - 2 * PAD + 16, 30);
			y += 32;
			/* banner kết quả: xanh=đúng mật khẩu, đỏ=sai (ux: error
			   hiện cạnh vị trí nhập, toast tự tắt 3-5s) */
			if (conn_status && conn_row == i && time(NULL) < conn_msg_until) {
				XftColor *bc = conn_status == 1 ? &ok_c
				             : conn_status == 2 ? &err_c : &label_c;
				const char *icon = conn_status == 1 ? "✓"
				                 : conn_status == 2 ? "✗" : "⋯";
				rrect_fill(PAD - 8, y + 2, W - 2 * PAD + 16, 28, 0, bg_card.pixel);
				rrect_stroke(PAD - 8, y + 2, W - 2 * PAD + 16, 28, 0, bc->pixel);
				draw_text(PAD + 4, y + 21, icon, f_small, bc);
				draw_text(PAD + 22, y + 21, conn_msg, f_small, bc);
				y += 32;
			}
			/* ô nhập mật khẩu ngay dưới SSID được chọn */
			if (pw_mode && pw_row == i) {
				rrect_fill(PAD - 8, y + 2, W - 2 * PAD + 16, 40, 0, bg_card.pixel);
				draw_text(PAD, y + 26, "\xef\x80\xa3 Password:", f_small, &label_c);
				char masked[80];
				int k;
				for (k = 0; k < pw_len && k < 60; k++) masked[k] = '*';
				masked[k] = '\0';
				draw_text(PAD + textw(f_small, "\xef\x80\xa3 Password:") + 12, y + 27,
				          masked, f_norm, &value_c);
				/* con trỏ nhấp nháy theo giây */
				if (time(NULL) & 1) {
					int mx = PAD + textw(f_small, "\xef\x80\xa3 Password:") + 12 + textw(f_norm, masked);
					XSetForeground(dpy, gc, value_c.pixel);
					XFillRectangle(dpy, pm, gc, mx + 2, y + 14, 2, 15);
				}
				draw_button(ID_PW_CONNECT, W - PAD - 76, y + 9, 72, 24,
				            "Connect", 1);
				y += 46;
			}
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
	case ID_PW_CONNECT:
		submit_pw();
		break;
	case ID_RESCAN:
		if (!pw_mode) { /* đang nhập mk thì không rescan (giữ list ổn định) */
			rescan_requested = 1;
			kick_status();
		}
		g_need_redraw = 1;
		break;
	default:
		if (id >= ID_DNS0 && id <= ID_DNS3)
			apply_dns(id - ID_DNS0);
		else if (id >= ID_OTHER_BASE) {
			int i = id - ID_OTHER_BASE;
			if (i < ni.other_n) {
				if (ni.other_use[i]) do_disconnect();
				else do_connect(ni.other[i], ni.other_sec[i]);
			}
		} else if (id >= ID_KNOWN_BASE) {
			int i = id - ID_KNOWN_BASE;
			if (i < ni.known_n) {
				if (ni.has_wifi && !strcmp(ni.known[i], ni.essid)) do_disconnect();
				else do_connect(ni.known[i], 1);
			}
		}
	}
}

/* ============ main ============ */
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
	/* ưu tiên ARGB 32-bit: bo góc bằng trong suốt thật → picom vẽ được
	   shadow (XShape bị picom bỏ qua shadow) */
	int depth = DefaultDepth(dpy, scr);
	XVisualInfo vinfo;
	if (XMatchVisualInfo(dpy, scr, 32, TrueColor, &vinfo)) {
		vis = vinfo.visual;
		cmap = XCreateColormap(dpy, root, vis, AllocNone);
		depth = 32;
	}
	/* gc tạo sau, trên pixmap ARGB (depth 32) để tránh BadMatch */

	CLR(bg_panel, C_BG_PANEL); CLR(bg_card, C_BG_CARD); CLR(bg_hover, C_BG_HOVER);
	CLR(bg_select, C_BG_SELECT); CLR(border_c, C_BORDER); CLR(label_c, C_LABEL);
	CLR(value_c, C_VALUE); CLR(ok_c, C_OK); CLR(err_c, C_ERR); CLR(white_c, "#ffffff");
	CLR(border_dwm, C_BORDER_DWM);

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
	wa.background_pixel = 0; /* trong suốt — nền vẽ trong pixmap ARGB */
	wa.border_pixel = 0;
	wa.colormap = cmap;
	wa.event_mask = ExposureMask | ButtonPressMask | ButtonReleaseMask |
	                PointerMotionMask | KeyPressMask | StructureNotifyMask;
	win = XCreateWindow(dpy, root, sw - PANEL_W - 8, bar_h + 2, PANEL_W, H, 0,
	                    depth, InputOutput, vis,
	                    CWOverrideRedirect | CWBackPixel | CWBorderPixel |
	                    CWColormap | CWEventMask, &wa);
	pm = XCreatePixmap(dpy, win, PANEL_W, H, depth);
	gc = XCreateGC(dpy, pm, 0, NULL); /* GC depth-32 khớp pixmap ARGB */
	xftdraw = XftDrawCreate(dpy, pm, vis, cmap);

	/* khai báo loại cửa sổ + class cho picom/compositor nhận diện */
	{
		Atom wt = XInternAtom(dpy, "_NET_WM_WINDOW_TYPE", False);
		Atom vals[2];
		vals[0] = XInternAtom(dpy, "_NET_WM_WINDOW_TYPE_POPUP_MENU", False);
		vals[1] = XInternAtom(dpy, "_NET_WM_WINDOW_TYPE_DROPDOWN_MENU", False);
		XChangeProperty(dpy, win, wt, XA_ATOM, 32, PropModeReplace,
		                (unsigned char *)vals, 2);
		XClassHint ch2 = { "netpanel", "Netpanel" };
		XSetClassHint(dpy, win, &ch2);
	}

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
	/* lưu focus hiện tại để trả lại khi đóng — tránh dwm mất focus,
	   phím gõ "chết" cho tới khi click vào cửa sổ khác */
	XGetInputFocus(dpy, &old_focus, &old_revert);
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

		/* toast hết hạn → tự tắt (quy tắc auto-dismiss 3-5s) */
		/* pending (status 3) không tự hết hạn — chờ nmcli trả kết quả
		   (sai mật khẩu NetworkManager có thể mất 30-60s mới báo lỗi) */
		if (conn_status && conn_status != 3 && time(NULL) > conn_msg_until) {
			conn_status = 0;
			g_need_redraw = 1;
		}
		/* hết hạn chờ toggle wifi → nhận lại status thật từ lần quét sau */
		if (radio_pending && time(NULL) > radio_pending_until)
			radio_pending = 0;
		if (radio_kick_at && time(NULL) >= radio_kick_at) {
			radio_kick_at = 0;
			kick_status();
		}

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
			case KeyPress: {
				KeySym ks = XLookupKeysym(&ev.xkey, 0);
				if (pw_mode) {
					if (ks == XK_Escape) {
						pw_mode = 0; pw_len = 0;
						pw_ssid[0] = '\0'; /* hủy neo ssid — nmcli pending muộn không mở lại ô nhập */
						g_need_redraw = 1;
					} else if (ks == XK_Return || ks == XK_KP_Enter) {
						submit_pw();
					} else if (ks == XK_BackSpace && pw_len > 0) {
						pw_len--; pw_buf[pw_len] = '\0'; g_need_redraw = 1;
					} else {
						char c;
						if (XLookupString(&ev.xkey, &c, 1, NULL, NULL) == 1 &&
						    (unsigned char)c >= 32 && pw_len < 63) {
							pw_buf[pw_len++] = c; pw_buf[pw_len] = '\0';
							g_need_redraw = 1;
						}
					}
				} else if (ks == XK_Escape) {
					running = 0;
				}
				break;
			}
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
			/* đang nhập mật khẩu thì KHÔNG rescan định kỳ — tránh
			   đổi thứ tự list làm ô nhập neo nhầm SSID */
			if (!pw_mode)
				kick_status();
			g_need_redraw = 1;
		}

		if (g_need_redraw) {
			g_need_redraw = 0;
			int newH = panel_height();
			if (newH != H) {
				H = newH;
				XFreePixmap(dpy, pm);
				pm = XCreatePixmap(dpy, win, PANEL_W, H, depth);
				XftDrawChange(xftdraw, pm);
				XResizeWindow(dpy, win, PANEL_W, H);
			}
			/* xóa trong suốt trước khi vẽ — góc panel sẽ để alpha 0 */
			XSetForeground(dpy, gc, 0);
			XFillRectangle(dpy, pm, gc, 0, 0, PANEL_W, H);
			draw_panel();
			XCopyArea(dpy, pm, win, gc, 0, 0, PANEL_W, H, 0, 0);
			XFlush(dpy);
		}
	}

	XUngrabPointer(dpy, CurrentTime);
	XUngrabKeyboard(dpy, CurrentTime);
	/* trả focus về cửa sổ cũ trước khi phá panel — nếu không dwm sẽ
	   giữ focus trỏ tới window đã chết → không gõ được gì */
	if (old_focus != None && old_focus != win && old_focus != PointerRoot)
		XSetInputFocus(dpy, old_focus, old_revert, CurrentTime);
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

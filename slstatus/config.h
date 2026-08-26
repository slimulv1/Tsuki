// clang-format off
/* See LICENSE file for copyright and license details. */

/* interval between updates (in ms) */
const unsigned int interval = 1000;

/* text to show if no value can be retrieved */
static const char unknown_str[] = "";

/* maximum output string length */
#define MAXLEN 2048

/*
 * function            description                     argument (example)
 *
 * battery_perc        battery percentage              battery name (BAT0)
 *                                                     nullptr on OpenBSD/FreeBSD
 * battery_remaining   battery remaining HH:MM         battery name (BAT0)
 *                                                     nullptr on OpenBSD/FreeBSD
 * battery_state       battery charging state          battery name (BAT0)
 *                                                     nullptr on OpenBSD/FreeBSD
 * cat                 read arbitrary file             path
 * cpu_freq            cpu frequency in MHz            nullptr
 * cpu_perc            cpu usage in percent            nullptr
 * datetime            date and time                   format string (%F %T)
 * disk_free           free disk space in GB           mountpoint path (/)
 * disk_perc           disk usage in percent           mountpoint path (/)
 * disk_total          total disk space in GB          mountpoint path (/)
 * disk_used           used disk space in GB           mountpoint path (/)
 * entropy             available entropy               nullptr
 * gid                 GID of current user             nullptr
 * hostname            hostname                        nullptr
 * ipv4                IPv4 address                    interface name (eth0)
 * ipv6                IPv6 address                    interface name (eth0)
 * kernel_release      `uname -r`                      nullptr
 * keyboard_indicators caps/num lock indicators        format string (c?n?)
 *                                                     see keyboard_indicators.c
 * keymap              layout (variant) of current     nullptr
 *                     keymap
 * load_avg            load average                    nullptr
 * netspeed_rx         receive network speed           interface name (wlan0)
 * netspeed_tx         transfer network speed          interface name (wlan0)
 * num_files           number of files in a directory  path
 *                                                     (/home/foo/Inbox/cur)
 * ram_free            free memory in GB               nullptr
 * ram_perc            memory usage in percent         nullptr
 * ram_total           total memory size in GB         nullptr
 * ram_used            used memory in GB               nullptr
 * run_command         custom shell command            command (echo foo)
 * swap_free           free swap in GB                 nullptr
 * swap_perc           swap usage in percent           nullptr
 * swap_total          total swap size in GB           nullptr
 * swap_used           used swap in GB                 nullptr
 * temp                temperature in degree celsius   sensor file
 *                                                     (/sys/class/thermal/...)
 *                                                     nullptr on OpenBSD
 *                                                     thermal zone on FreeBSD
 *                                                     (tz0, tz1, etc.)
 * uid                 UID of current user             nullptr
 * uptime              system uptime                   nullptr
 * username            username of current user        nullptr
 * vol_perc            OSS/ALSA volume in percent      mixer file (/dev/mixer)
 *                                                     nullptr on OpenBSD/FreeBSD
 * wifi_essid          WiFi ESSID                      interface name (wlan0)
 * wifi_perc           WiFi signal in percent          interface name (wlan0)
 */
static const struct arg args[] = {
    // Màu theo theme wal: dwmwal.sh thay sentinel XXX_HEX bằng #RRGGBB mỗi khi
    // đổi wallpaper (xem dwmwal.sh section 9) rồi rebuild slstatus.
    // LUU Y: dwm status2d CHI hieu ^c#HEX^ / ^b#HEX^ / ^d^ - KHONG hieu ^Cindex^

    // (truoc day ^C9^ bi hien thi nguyen van, thanh bar khong co mau).
    // RIENG net_icon + wifi_panel: MAU CO DINH (literal, khong XXX_HEX) —
    // khong doi theo wallpaper, va PHAI luon ton tai o day vi dwmwal.sh
    // tai sinh config.h TU FILE NAY moi lan doi hinh nen.

/* function       format                          argument */
{ updates,       "%s", "#cec4de #79405a" },  /* ON=trang khi co update, OFF=xanh khi khong */
{ cpu_perc,      " ^c#d38aab^󰻠 %s%%^d^ ",        nullptr },
{ ram_used,      "^c#9d81d0^ %s^d^ ",           nullptr },
{ disk_perc,     "^c#a5d793^󰋊 %s%%^d^ ",        "/" },
{ run_command, "^c#b9a4dd^󱩱 %s°C^d^ ",        "~/dwm/scripts/cpu_temp.sh" }, /* x86_pkg_temp = CPU thật (zone0 là acpitz, sai) */
{ net_icon,      "^c#7842d7^ %s ",               nullptr },  /* icon internet: MAU CO DINH #7842d7 — KHONG dung sentinel nen khong doi theo wallpaper; chi click vao icon (marker trong net_icon.c) -> netpanel.sh */
{ wifi_panel,    "%s",                           nullptr },  /* Wi-Fi Mini: chỉ tên mạng đang kết nối; màu nằm trong wifi_panel.c (#define) nên cũng cố định */
{ battery_perc,  "^c#7842d7^ %s%%^d^",          "BAT1" },
{ battery_state, "^c#a5d793^%s^d^ ",        "BAT1" },
{ datetime,      "^c#a5d793^󰸗 %s^d^",          "%a, %d/%m, %H:%M" },
};

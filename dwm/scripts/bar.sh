#!/bin/dash

# ^c$var^ = fg color
# ^b$var^ = bg color

# --- package updates (async) ---
# checkupdates refreshes in a detached loop; the bar only reads the cached count (never blocks)
# Loop moi: poll 60s, chay checkupdates khi (a) /var/log/pacman.log doi (vua update ->
# bar cap nhat ngay trong ~1 phut, khong doi 1 tieng nhu cu) hoac (b) da 1 tieng
# (goi moi tu server). Neu checkupdates LOI (network/lock/timeout) -> GIU cache cu,
# khong ghi "0" gia gay bao "Fully Updated" sai.
upd_cache=~/.cache/dwm-updates
[ -f "$upd_cache" ] || printf '0\n' > "$upd_cache"
if ! pgrep -f 'sh -c.*bar_updater_loop' >/dev/null 2>&1; then
  sh -c '
# self-dedupe: chi 1 loop duoc chay (flock chong race khi nhieu bar.sh spawn cung luc,
# vi du dwmwal.sh spawn tay + supervisor respawn -> 2 bar.sh -> 2 loop)
exec 9>"$HOME/.cache/dwm-updates.lock"
flock -n 9 || exit 0
bar_updater_loop() {
  cache="$HOME/.cache/dwm-updates"
  paclog=/var/log/pacman.log
  last_paclog=""
  last_check=0
  while :; do
    now=$(date +%s)
    pm=$(stat -c %Y "$paclog" 2>/dev/null || echo 0)
    if [ -z "$last_paclog" ] || [ "$pm" != "$last_paclog" ] || [ $((now - last_check)) -ge 3600 ]; then
      out=$(timeout 20 checkupdates 9>&- 2>/dev/null)
      ec=$?
      pm2=$(stat -c %Y "$paclog" 2>/dev/null || echo 0)
      if [ "$ec" -eq 0 ] || [ "$ec" -eq 2 ]; then
        if [ -n "$out" ]; then
          count=$(printf "%s\n" "$out" | wc -l)
        else
          count=0
        fi
        printf "%s\n" "$count" > "$cache"
        last_check=$now
        last_paclog=$pm2
      else
        # loi: giu cache cu, doi 1 tieng hoac pacman.log doi moi thu lai (khong spam)
        last_check=$now
        last_paclog=$pm
      fi
    fi
    sleep 60 9>&-
  done
}
bar_updater_loop' &
fi

# load colors (live-reloaded when theme file regenerates)
# GUARD: dash thoát (exit 2) khi `.` không đọc được file -> nếu wal bị xóa lúc
# runtime, bar.sh sẽ chết vĩnh viễn (supervisor run.sh chỉ check 1 lần lúc boot).
theme_file=~/dwm/dwm/scripts/bar_themes/wal
theme_ck=""
[ -r "$theme_file" ] && . "$theme_file"

# --- modules: output qua biến toàn cục $out ---
# Gọi function trong dash KHÔNG fork subshell (chỉ $( ) / pipeline mới fork).
# Trước đây: "$(cpu) $(battery) ..." = 6 subshell/giây + date + xsetroot + sleep
# = ~8 fork/giây. Bây giờ chỉ còn date + xsetroot + sleep = 2 fork/giây.
# Mỗi function kết thúc bằng 1 space để giữ nguyên khoảng cách hiển thị cũ.

# % CPU thật từ /proc/stat (delta giữa 2 lần đọc 1s) — KHÔNG dùng /proc/loadavg:
# loadavg là độ dài hàng đợi trung bình (máy 20 cores: build full -> loadavg ~20,
# không phải 100%). Công thức: busy% = (total_delta - idle_delta) / total_delta.
# Đọc 1 file, chỉ arithmetic — vẫn 0 fork.
prev_total=0
prev_idle=0
cpu() {
  read _ u n s i w irq sirq st _ < /proc/stat
  idle=$((i + w))
  total=$((u + n + s + i + w + irq + sirq + st))
  if [ "$prev_total" -gt 0 ] && [ "$total" -gt "$prev_total" ]; then
    dt=$((total - prev_total))
    di=$((idle - prev_idle))
    tenths=$(( ( (dt - di) * 1000 ) / dt ))
    [ "$tenths" -gt 1000 ] && tenths=1000
    [ "$tenths" -lt 0 ] && tenths=0
  else
    tenths=0
  fi
  prev_total=$total
  prev_idle=$idle
  out="$out^c$black^ ^b$green^ CPU^c$white^ ^b$grey^ $((tenths / 10)).$((tenths % 10))% ^b$black^ "
}

pkg_updates() {
  read updates < "$upd_cache" 2>/dev/null || updates=0
  # guard: cache hỏng (không phải số) -> coi như 0, không spam "Illegal number"
  case "$updates" in
    ''|*[!0-9]*) updates=0 ;;
  esac
  if [ "$updates" -le 0 ]; then
    out="$out  ^c$green^   "
  else
    out="$out  ^c$white^   $updates "
  fi
}

cputemp() {
  # Nhiệt độ CPU từ sysfs (milli°C). Ưu tiên zone loại x86_pkg_temp/cpu/pkg,
  # fallback zone hợp lệ đầu tiên; bỏ qua zone rác (< 20°C).
  temp="?"
  for z in /sys/class/thermal/thermal_zone*; do
    [ -r "$z/temp" ] || continue
    read t < "$z/temp" 2>/dev/null || continue
    case "$t" in ''|*[!0-9]*) continue ;; esac
    [ "$t" -lt 20000 ] && continue
    type=""
    read type < "$z/type" 2>/dev/null
    temp=$((t / 1000))
    case "$type" in
      x86_pkg_temp|*cpu*|*CPU*|*pkg*) break ;;
    esac
  done
  # label box màu teal + number box giống battery (trắng trên grey, reset black)
  out="$out^c$black^ ^b$teal^ 󰔄 "
  out="$out^c$white^ ^b$grey^ ${temp}°C ^b$black^ "
}

mem() {
  out="$out^c$red^^b$black^  "
  # Đọc /proc/meminfo bằng builtin read (không spawn awk mỗi giây)
  t=0; f=0; b=0; c=0
  while IFS=':' read -r key val; do
    case "$key" in
      MemTotal) t=${val% *} ;;
      MemFree)  f=${val% *} ;;
      Buffers)  b=${val% *} ;;
      Cached)   c=${val% *} ;;
    esac
  done < /proc/meminfo
  usedmb=$(( (t - f - b - c) / 1024 ))
  [ "$usedmb" -lt 0 ] && usedmb=0
  # %d.%dG: round 1 chữ số trước khi tách phần nguyên -> không bao giờ ra "1.10G"
  # (công thức cũ round phần dư riêng -> "1.10G" khi usedmb%1024 >= 973)
  tenths=$(( (usedmb * 10 + 512) / 1024 ))
  out="$out^c$red^ $((tenths / 10)).$((tenths % 10))G "
}

# --- internet: 1 glob duy nhất, cache 2s, xét TẤT CẢ interface ---
# BUG CŨ: break ở interface đầu tiên khớp glob — nếu nó down mà interface sau
# up (vd enp0 down + enp1 up, hoặc wlan0 down + wlan1 up) thì mất trạng thái.
# Giờ chỉ break khi tìm thấy interface UP; ưu tiên WIFI (wl*) trước mạng dây:
# nếu wifi đang kết nối thì hiện wifi + SSID thay vì wired (theo yêu cầu).
wlan_out=""
wlan() {
	op=""
	kind=""
	for f in /sys/class/net/wl*/operstate /sys/class/net/en*/operstate /sys/class/net/eth*/operstate; do
		[ -r "$f" ] || continue
		read st < "$f"
		case "$f" in
		*wl*) k=wifi ;;
		*)    k=wired ;;
		esac
		if [ "$st" = "up" ]; then
			op=up; kind=$k
			break
		fi
		op=$st; kind=$k
	done
	# GÁN MỚI (không append $wlan_out) — wlan_out tồn tại giữa các vòng lặp,
	# append sẽ cộng dồn "Wired" mỗi 2s -> spam tràn thanh bar
	case "$kind:$op" in
	wired:up)  wlan_out="^c$black^ ^b$blue^  ^d^ ^c$blue^Wired " ;;
	wifi:up)   ssid="$(iwgetid -r)"   # 1 fork/2s, chỉ khi wifi up
	           [ -n "$ssid" ] || ssid="WiFi"
	           wlan_out="^c$black^ ^b$blue^ 󰤨 ^d^ ^c$blue^$ssid " ;;
	wifi:down) wlan_out="^c$black^ ^b$blue^ 󰤭 ^d^ ^c$blue^Disconnected " ;;
	esac
}

clock() {
	out="$out^c$black^ ^b$darkblue^ 󱑆 "
	out="$out^c$black^^b$blue^ $(date '+%H:%M')  "
}

loopn=0
while true; do

  # reload theme when wallpaper changed (bar_themes/wal regenerated by dwmwal.sh)
  # stat mỗi 5 giây thay vì mỗi giây — giảm 80% fork, theme vẫn cập nhật nhanh
  # GUARD: [ -n "$ck" ] — wal bị xóa lúc runtime -> giữ theme cũ, không source (tránh crash)
  if [ $((loopn % 5)) -eq 0 ]; then
    ck=$(stat -c %Y "$theme_file" 2>/dev/null)
    if [ -n "$ck" ] && [ "$ck" != "$theme_ck" ]; then
      . "$theme_file"
      theme_ck="$ck"
    fi
  fi
  loopn=$((loopn + 1))

  # gộp toàn bộ vào 1 chuỗi, chỉ fork: date (trong clock) + xsetroot + sleep
  out=""
  pkg_updates
  cpu
  cputemp
  mem
  # internet: cache 2s — trạng thái mạng thay đổi chậm, giảm 50% I/O sysfs
  # (-eq 1: loopn đã tăng lên 1 trước đây nên vòng đầu phải chạy wlan ngay)
  if [ $((loopn % 2)) -eq 1 ]; then
    wlan
  fi
  out="$out$wlan_out"
  clock

  xsetroot -name "$out"
  sleep 1
done
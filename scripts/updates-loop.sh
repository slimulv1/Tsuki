#!/bin/dash

# Cập nhật cache số package updates cho slstatus (async, không block bar).
# Loop: poll 60s, chạy checkupdates khi (a) /var/log/pacman.log đổi (vừa update ->
# bar cập nhật ngay trong ~1 phút, không đợi 1 tiếng) hoặc (b) đã 1 tiếng
# (gọi mới từ server). Nếu checkupdates LỖI (network/lock/timeout) -> GIỮ cache cũ,
# không ghi "0" giả gây báo "Fully Updated" sai.
# (Tách từ bar.sh cũ — slstatus thay bar.sh nhưng cơ chế cache này vẫn dùng chung.)

# mkdir -p trước: nếu ~/.cache chưa có (user mới, hoặc XDG_CACHE_HOME trỏ
# chỗ chưa tạo) thì `printf > "$upd_cache"` hỏng và cả thanh updates + thanh
# bar im lặng — đúng lỗi đường dẫn, không phải lỗi mạng.
mkdir -p "$HOME/.cache"
upd_cache="$HOME/.cache/dwm-updates"
[ -f "$upd_cache" ] || printf '0\n' > "$upd_cache"

# self-dedupe: chỉ 1 loop được chạy (flock chống race khi nhiều script spawn cùng lúc)
exec 9>"$HOME/.cache/dwm-updates.lock"
flock -n 9 || exit 0

# Dọn file tạm sót từ lần chạy TRƯỚC bị giết (SAU khi đã giữ khoá — dọn trước
# khoá thì xoá nhầm file của tiến trình song song). Hậu tố là $$ của tiến
# trình đã chết nên glob là đủ; không đụng `dwm-updates` bản thật.
for _u in "$HOME/.cache/dwm-updates.tsuki-new."*; do
    [ -f "$_u" ] && rm -f -- "$_u" 2>/dev/null
done
unset _u

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
      # Ghi qua file tạm rồi mv. slstatus đọc file này (components/updates.c,
      # qua config.h) mỗi lần thanh cập nhật — thường là mỗi giây. Nếu bị
      # giết giữa lúc ghi, lần đọc kế có thể thấy file rỗng và thanh báo sai.
      # File chỉ vài byte nên cửa sổ hẹp, nhưng rename(2) miễn phí và loại
      # hẳn khả năng đó.
      # tmp CÙNG THƯ MỤC (không phải /tmp) để mv là rename trong cùng
      # filesystem — khác fs thì mv phải copy, mất tính nguyên tử.
      _utmp="$cache.tsuki-new.$$"
      if printf "%s\n" "$count" > "$_utmp" 2>/dev/null; then
          mv -f "$_utmp" "$cache" 2>/dev/null || rm -f "$_utmp"
      else
          rm -f "$_utmp" 2>/dev/null
      fi
      last_check=$now
      last_paclog=$pm2
    else
      # lỗi: giữ cache cũ, đợi 1 tiếng hoặc pacman.log đổi mới thử lại (không spam)
      last_check=$now
      last_paclog=$pm
    fi
  fi
  sleep 60 9>&-
done
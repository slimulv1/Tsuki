#!/bin/dash

# Cập nhật cache số package updates cho slstatus (async, không block bar).
# Loop: poll 60s, chạy checkupdates khi (a) /var/log/pacman.log đổi (vừa update ->
# bar cập nhật ngay trong ~1 phút, không đợi 1 tiếng) hoặc (b) đã 1 tiếng
# (gọi mới từ server). Nếu checkupdates LỖI (network/lock/timeout) -> GIỮ cache cũ,
# không ghi "0" giả gây báo "Fully Updated" sai.
# (Tách từ bar.sh cũ — slstatus thay bar.sh nhưng cơ chế cache này vẫn dùng chung.)

upd_cache="$HOME/.cache/dwm-updates"
[ -f "$upd_cache" ] || printf '0\n' > "$upd_cache"

# self-dedupe: chỉ 1 loop được chạy (flock chống race khi nhiều script spawn cùng lúc)
exec 9>"$HOME/.cache/dwm-updates.lock"
flock -n 9 || exit 0

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
      # lỗi: giữ cache cũ, đợi 1 tiếng hoặc pacman.log đổi mới thử lại (không spam)
      last_check=$now
      last_paclog=$pm
    fi
  fi
  sleep 60 9>&-
done
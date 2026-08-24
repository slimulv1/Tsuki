#!/bin/dash

# Nhiệt độ CPU (°C) từ sysfs. Ưu tiên zone loại x86_pkg_temp/cpu/pkg,
# fallback zone hợp lệ đầu tiên; bỏ qua zone rác (< 20°C, vd BAT0 2.6°C).
# Dùng cho slstatus run_command (chạy mỗi giây — dash rất nhẹ, ~0.5ms).
# KHÔNG hardcode thermal_zoneN: index zone thay đổi giữa các lần boot
# (thứ tự probe driver), nên phải tự tìm theo type.

last=""
for z in /sys/class/thermal/thermal_zone*; do
  [ -r "$z/temp" ] || continue
  read t < "$z/temp" 2>/dev/null || continue
  case "$t" in ''|*[!0-9]*) continue ;; esac
  [ "$t" -lt 20000 ] && continue
  type=""
  read type < "$z/type" 2>/dev/null
  last=$((t / 1000))
  case "$type" in
    x86_pkg_temp|*cpu*|*CPU*|*pkg*) printf '%d\n' "$last"; exit 0 ;;
  esac
done
[ -n "$last" ] && printf '%d\n' "$last"
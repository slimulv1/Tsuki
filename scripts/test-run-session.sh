#!/usr/bin/env dash
# Kiểm tra tích hợp scripts/run.sh — chạy SCRIPT THẬT trong sandbox với mọi
# lệnh X11 bị thay bằng stub, nên không đụng session đang chạy.
#
# Mục tiêu: chứng minh (1) run.sh chạy hết từ đầu đến cuối không vướng gì,
# (2) vòng lặp dwm có backoff đúng, (3) daemon được dọn khi thoát,
# (4) những thứ kiểm tra trước đây im lặng giờ có dấu vết trong nhật ký.
set -u
R=/home/frost-auslese/tsuki
T=$(mktemp -d)
P=0; F=0
ok()  { printf '  PASS  %s\n' "$*"; P=$((P+1)); }
bad() { printf '  FAIL  %s\n        %s\n' "$*"; F=$((F+1)); }
cleanup() {
    for p in $(cat "$T/run"/tsuki-*.pid 2>/dev/null); do kill "$p" 2>/dev/null; done
    rm -rf "$T"
}
trap cleanup EXIT INT TERM

# --- sandbox: mọi lệnh chạm X đều thành stub không-op ----------------------
mkdir -p "$T/bin" "$T/run" "$T/home"
# KHÔNG stub `flock`. Bản đầu của file này có flock trong danh sách stub, và
# điều đó TẮT ÂM THẦM toàn bộ cơ chế khoá của run.sh: `flock -n 8` trả 0 mà
# không khoá gì, `flock -n file -c true` luôn báo "trống". Hậu quả đo được:
#   - watchdog thấy mọi khoá đều trống nên hồi sinh liên tục
#   - bước xác nhận "sau supervise_one" luôn thấy trống -> ghi nhầm
#     "không khởi động được", và T13d fail oan dù watchdog chạy đúng
#   - T2/T5/T13b "pass" nhưng không thật sự kiểm khoá gì cả
# Dùng flock thật (/usr/bin/flock). Nó chỉ khoá file trong $T/run nên vô hại.
# PHẢI STUB MỌI DAEMON THẬT. Đã mắc lỗi nghiêm trọng: danh sách này thiếu
# `fcitx5`, nên sandbox gọi Fcitx5 THẬT. Nó fork rồi launcher chết, daemon thật
# thành mồ côi giữ khoá trên một file /tmp đã bị xoá — và `cleanup()` chỉ kill
# pid trong pidfile, mà pidfile trỏ tới launcher đã chết.
# Hậu quả sau khi chạy bộ test hàng trăm lần: 596 tiến trình fcitx5 mồ côi trên
# máy thật, 6.2 GB PSS. Đã dọn, và nay mọi daemon đều stub.
for c in feh picom xset xsetroot xrdb notify-send dunst fcitx5 xsettingsd \
         tumblerd slstatus polkit-gnome-authentication-agent-1; do
    printf '#!/bin/sh\nexit 0\n' > "$T/bin/$c"
    chmod +x "$T/bin/$c"
done
command -v flock >/dev/null 2>&1 || { echo "FAIL: cần flock thật để test"; exit 1; }
# `type dwm` trong run.sh phải thấy dwm giả
cat > "$T/bin/dwm" <<'EOF'
#!/bin/sh
n=$(cat "$FAKE_DWM_COUNT" 2>/dev/null); n=${n:-0}
n=$((n + 1))
printf '%s\n' "$n" > "$FAKE_DWM_COUNT"
# GHI LẠI umask mà dwm kế thừa được từ run.sh, cộng thêm mode thật của một
# file mà "app" tạo ra. dwm giả đóng vai dwm thật: nó là con trực tiếp của
# run.sh, nên nó thừa hưởng đúng cái umask mà mọi app dwm mở ra cũng thừa
# hưởng. File thật thì chắc chắn hơn đọc /proc/<pid>/status.
: > "$FAKE_UMASK_PROBE" 2>/dev/null
( umask; stat -c %a "$FAKE_UMASK_PROBE" 2>/dev/null || echo "?" ) > "$FAKE_UMASK_OUT" 2>/dev/null
# in ra lỗi thật mà dwm die() khi không nạp được font, rồi mới quyết định sống
printf 'no fonts could be loaded.\n' >&2
# Số lần chết nhanh từ biến môi trường; lần đó trả 1, còn lại trả 0
if [ "$n" -le "${FAKE_DWM_FAULTS:-0}" ]; then
    exit 1
fi
# FAKE_DWM_EXIT: ép trả mã cụ thể (143 = bị SIGTERM, đúng đường Super+Shift+R
# -> rebuild.sh -> killall dwm). FAKE_DWM_LINGER: ở lại mãi để test tín hiệu.
[ -n "${FAKE_DWM_EXIT:-}" ] && exit "$FAKE_DWM_EXIT"
if [ "${FAKE_DWM_LINGER:-0}" = 1 ]; then
    printf '%s\n' "$$" > "$FAKE_DWM_PID"
    while :; do sleep 0.2; done
fi
exit 0
EOF
chmod +x "$T/bin/dwm"

export PATH="$T/bin:/usr/bin:/bin"
export HOME="$T/home"
export XDG_RUNTIME_DIR="$T/run"
export XDG_CACHE_HOME="$T/home/.cache"
export FAKE_DWM_COUNT="$T/dwm.count"
# Hai biến cho probe umask của T8. PHẢI export ngay từ đầu chứ không để tới
# T8 mới set: stub dwm chạy cả trong T1..T7, nơi biến còn rỗng thì
# `: > "$FAKE_UMASK_PROBE"` hỏng và làm stub trả mã khác 0 -> dwm "crash" giả,
# T1/T6/T6c cùng hỏng theo. Đã mắc đúng lỗi này.
export FAKE_UMASK_PROBE="$T/probe.dat"
export FAKE_UMASK_OUT="$T/umask.out"
export NO_COLOR=1
: > "$FAKE_DWM_COUNT"

# run.sh đặt PATH theo thứ tự:  $TSUKI_DIR/dmenu : $TSUKI_DIR : /usr/local/bin : $PATH
# (dòng 37 và 27). Nên dwm thật ở /usr/local/bin sẽ bị che nếu ta đặt dwm giả
# trong $TSUKI_DIR. run.sh tôn trọng biến môi trường TSUKI_DIR
# (`TSUKI_DIR="${TSUKI_DIR:-...}"`), nên không cần vá dòng nào trong file thật —
# đây là cách sạch hơn hẳn việc sed lên bản sao.
#
# Repo giả: scripts/ trỏ tới repo thật (cần update dmm, dumpeven), còn lại là
# rỗng — đúng tình huống "vừa git clone, chưa build".
mkdir -p "$T/repo"
ln -s "$R/scripts" "$T/repo/scripts"
cp "$T/bin/dwm" "$T/repo/dwm"; chmod +x "$T/repo/dwm"
# slstatus giả: nếu thiếu thì run.sh sẽ cảnh báo "không tìm thấy slstatus" —
# đúng như máy thật khi chưa build. Để nguyên.
export TSUKI_DIR="$T/repo"
TSUKI_LOG_PATH="$XDG_CACHE_HOME/tsuki/session.log"
export TSUKI_STUB="$T/bin"
TSUKI_LOG_PATH="$XDG_CACHE_HOME/tsuki/session.log"

# --- T1: chạy trọn vẹn, thoát sạch, ghi nhật ký -----------------------------
printf '  (chạy run.sh thật, dwm giả trả 0 ngay)\n'
out=$(cd "$R" && timeout 60 sh "$R/scripts/run.sh" 2>&1)
rc=$?
if [ "$rc" -eq 0 ]; then
    ok "T1 run.sh chạy trọn vẹn và thoát 0"
else
    bad "T1 run.sh thoát 0" "rc=$rc"
    printf '%s\n' "$out" | tail -20 | sed 's/^/        /'
fi

LOG="$XDG_CACHE_HOME/tsuki/session.log"
if [ -s "$LOG" ]; then
    nl=$(wc -l < "$LOG")
    ok "T2 có nhật ký phiên ($nl dòng) tại $TSUKI_LOG_PATH"
else
    bad "T2 nhật ký phiên" "không có hoặc rỗng: $LOG"
fi

# --- T3: không còn lỗi 'command not found' ----------------------------------
if printf '%s\n' "$out" | grep -q 'command not found'; then
    bad "T3 không có lệnh chưa định nghĩa" \
        "$(printf '%s\n' "$out" | grep 'command not found' | head -3 | tr '\n' ';')"
else
    ok "T3 không có 'command not found' (warn_cursor đã được định nghĩa)"
fi

# --- T4: daemon được ghi nhận trong log --------------------------------------
if grep -qE '^INFO  (fcitx|slstatus|updates|mediacard):' "$LOG" 2>/dev/null; then
    ok "T4 daemon được khởi động và ghi log:" \
       "$(grep -cE '^INFO  [a-z]+: pid' "$LOG") daemon"
else
    bad "T4 daemon ghi log" "$(grep -E '^(INFO|WARN|FAIL)' "$LOG" 2>/dev/null | head -5 | tr '\n' ';')"
fi

# --- T5: thoát xong thì không còn khoá/pidfile sót ----------------------------
locks=$(ls "$XDG_RUNTIME_DIR"/tsuki-*.lock 2>/dev/null | wc -l)
pids=$(ls "$XDG_RUNTIME_DIR"/tsuki-*.pid 2>/dev/null | wc -l)
if [ "$locks" -eq 0 ] && [ "$pids" -eq 0 ]; then
    ok "T5 thoát xong: không còn khoá hay pidfile sót"
else
    bad "T5 dọn dẹp" "còn $locks khoá, $pids pidfile"
fi

# --- T6: vòng lặp dwm CÓ backoff khi crash liên tiếp --------------------------
# 5 lần crash nhanh rồi lần 6 exit 0. Backoff cố ý là 0.3 → 0.6 → 1.2 → 2 → 2
# (cap 2s) = 6.1s, thay vì 1.5s nếu cứ `sleep 0.3` như bản cũ.
: > "$FAKE_DWM_COUNT"
export FAKE_DWM_FAULTS=5
t0=$(date +%s)
( cd "$R" && timeout 120 sh scripts/run.sh >/dev/null 2>&1 )
t1=$(date +%s)
n=$(cat "$FAKE_DWM_COUNT" 2>/dev/null); n=${n:-0}
elapsed=$((t1 - t0))
if [ "$n" -eq 6 ]; then
    ok "T6 dwm chạy $n lần (5 crash + 1 thoát sạch)"
else
    bad "T6 số lần chạy dwm" "chạy $n lần, mong đợi 6"
fi
if [ "$elapsed" -ge 5 ]; then
    ok "T6b backoff có tác dụng: 5 lần crash mất ${elapsed}s (bản cũ chỉ 1.5s)"
else
    bad "T6b backoff" "chỉ ${elapsed}s — nhỏ hơn cả bản cũ"
fi
# Và phải TĂNG DẦN, không phải hằng số: đọc delay ghi trong log phiên.
LOG6="$XDG_CACHE_HOME/tsuki/session.log"
# Dòng log kết thúc bằng "nghỉ <số>s" — trường cuối là số giây. Không grep
# theo chữ có dấu ("nghi" vs "nghỉ") vì dễ sai; lọc bằng đuôi `<số>.<số>s`.
#
# Phải lọc thêm chứ không chỉ `grep 'dwm crash'`: dòng báo DỪNG
# ("FAIL  dwm crash liên tiếp N lần, ... — DỪNG") CŨNG chứa "dwm crash", và
# trường cuối của nó là chữ "DỪNG" -> awk không parse được ("invalid char in
# expression") và T6c FAIL oan. Chuyện này chỉ lộ ra khi vòng lặp đi tới ngưỡng
# 10 lần, tức đúng lúc T7 chạy. Đã mắc.
delays=$(grep 'dwm crash' "$LOG6" 2>/dev/null | grep -E '[0-9]+\.[0-9]s$' | awk '{print $NF}' | tr -d 's' | tr '\n' ' ')
first=$(printf '%s' "$delays" | awk '{print $1}')
last=$(printf '%s' "$delays" | awk '{print $NF}')
if [ -n "$first" ] && [ -n "$last" ] && awk "BEGIN{exit !($last > $first)}"; then
    ok "T6c delay tăng dần: $delays"
else
    bad "T6c delay tăng dần" "chuỗi delay: [$delays]"
fi

# --- T7: crash VÔ HẠN thì phải dừng, không quay vòng mãi ---------------------
: > "$FAKE_DWM_COUNT"
export FAKE_DWM_FAULTS=999   # luôn crash
out2=$( (cd "$R" && timeout 90 sh "$R/scripts/run.sh" 2>&1) )
rc2=$?
unset FAKE_DWM_FAULTS
n2=$(cat "$FAKE_DWM_COUNT" 2>/dev/null); n2=${n2:-0}
if [ "$rc2" -ne 124 ] && [ "$n2" -le 30 ]; then
    ok "T7 crash vô hạn: dừng sau $n2 lần (exit $rc2), không quay vòng vô tận"
else
    bad "T7 chặn crash loop" "chạy $n2 lần, rc=$rc2 (124 = hết timeout, tức vẫn đang quay)"
fi
if printf '%s\n' "$out2" | grep -q 'crash liên tục'; then
    ok "T7b in nguyên nhân ra thay vì im lặng"
else
    bad "T7b thông báo crash loop" "không tìm thấy trong output"
fi

# --- T8: umask của session KHÔNG được siết lại toàn cục ---------------------
# run.sh từng đặt `umask 077` ở giữa file. umask là TRẠNG THÁI TOÀN CỤC và
# mọi tiến trình con đều kế thừa — kể cả dwm, rồi từ dwm tới Firefox, Thunar,
# mọi app người dùng mở. Hậu quả: file người dùng lưu ra là 600, thư mục là
# 700, thay vì 644/755. Đo trên máy thật: dwm có Umask=0077 trong
# /proc/<pid>/status, và /tmp/.bun-*.so tạo trong phiên đó là -rw-------.
#
# Ý đồ của dòng umask đó là bảo vệ cache/log của chính run.sh — nhưng log được
# tạo ở DÒNG 28, trước umask, nên umask không bảo vệ được nó (session.log thật
# là 644). Còn ~/.cache/thumbnails thì run.sh đã chmod 700 tường minh. Tức là
# umask 077 không bảo vệ được gì mà lại siết chặt file của người dùng.
: > "$FAKE_DWM_COUNT"
( cd "$R" && timeout 60 sh scripts/run.sh >/dev/null 2>&1 )
if [ -s "$FAKE_UMASK_OUT" ]; then
    um_val=$(sed -n 1p "$FAKE_UMASK_OUT")
    mode_val=$(sed -n 2p "$FAKE_UMASK_OUT")
    if [ "$um_val" = "0022" ] && [ "$mode_val" = "644" ]; then
        ok "T8 dwm kế thừa umask 0022 — file người dùng lưu ra là 644"
    else
        bad "T8 umask bị siết toàn cục" "dwm thấy umask=$um_val, file tạo ra mode=$mode_val (mong đợi 0022/644)"
    fi
else
    bad "T8 không đọc được umask của dwm" "stub dwm không ghi ra $FAKE_UMASK_OUT"
fi

# --- T9: session.log vẫn phải là 600 dù không còn umask 077 toàn cục --------
# Nếu bỏ umask 077 thì phải bảo vệ log bằng cách khác, nếu không lại mất.
if [ -f "$TSUKI_LOG_PATH" ]; then
    lm=$(stat -c %a "$TSUKI_LOG_PATH" 2>/dev/null)
    if [ "$lm" = "600" ]; then
        ok "T9 session.log mode 600 — vẫn riêng tư sau khi bỏ umask toàn cục"
    else
        bad "T9 session.log không riêng tư" "mode=$lm (mong đợi 600)"
    fi
else
    bad "T9 không có session.log" "$TSUKI_LOG_PATH"
fi

# --- T10: dwm chết bằng SIGTERM (143) = đúng đường Super+Shift+R -----------
# rebuild.sh gọi `killall dwm` -> dwm chết với exit status 143. run.sh phải
# nạp lại dwm, KHÔNG được coi là kết thúc session. Đường này trước đây chưa
# hề được test: T6/T7 chỉ dùng exit 1.
: > "$FAKE_DWM_COUNT"
export FAKE_DWM_EXIT=143
( cd "$R" && timeout 60 sh scripts/run.sh >/dev/null 2>&1 )
unset FAKE_DWM_EXIT
n143=$(cat "$FAKE_DWM_COUNT" 2>/dev/null); n143=${n143:-0}
if [ "$n143" -ge 2 ]; then
    ok "T10 dwm chết 143 (SIGTERM) được nạp lại, không kết thúc session ($n143 lần)"
else
    bad "T10 xử lý exit 143" "chạy $n143 lần — mong đợi >= 2 (1 lần chết + 1 lần nạp lại)"
fi

# --- T11: SIGTERM gửi RIÊNG cho run.sh phải dọn được, và dwm không mồ côi ---
# POSIX hoãn trap khi shell chờ lệnh foreground. Bản cũ chạy `dwm` foreground
# nên `kill -TERM <pid run.sh>` không làm gì cả — đo thật trong sandbox: sau 3
# giây run.sh vẫn sống, dwm vẫn sống, log không có dòng "run.sh nhận SIGTERM".
# Nay dwm chạy nền + `wait` nên trap phải chạy ngay.
export FAKE_DWM_LINGER=1
export FAKE_DWM_PID="$T/dwm_linger.pid"
: > "$FAKE_DWM_COUNT"; rm -f "$FAKE_DWM_PID"
( cd "$R" && sh scripts/run.sh >/dev/null 2>&1 ) &
RUNPID=$!
for _ in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20; do
    [ -s "$FAKE_DWM_PID" ] && break
    sleep 0.5
done
dwmpid=$(cat "$FAKE_DWM_PID" 2>/dev/null)
if [ -n "$dwmpid" ] && kill -0 "$dwmpid" 2>/dev/null; then
    ok "T11 dwm giả chạy nền, pid $dwmpid"
else
    bad "T11 dwm giả không lên" "pid='$dwmpid'"
fi
kill -TERM "$RUNPID" 2>/dev/null
waited=0
for _ in 1 2 3 4 5 6 7 8 9 10; do
    kill -0 "$RUNPID" 2>/dev/null || { waited=1; break; }
    sleep 0.5
done
if [ "$waited" = 1 ]; then
    ok "T11b SIGTERM chỉ cho run.sh — trap chạy, run.sh thoát"
else
    bad "T11b run.sh không thoát sau SIGTERM" "vẫn sống sau 5s — trap bị hoãn (lỗi foreground)"
    kill -9 "$RUNPID" 2>/dev/null
fi
sleep 1
if [ -n "$dwmpid" ] && kill -0 "$dwmpid" 2>/dev/null; then
    bad "T11c dwm thành mồ côi" "dwm $dwmpid vẫn sống sau khi run.sh thoát"
    kill -9 "$dwmpid" 2>/dev/null
else
    ok "T11c dwm bị chuyển tiếp tín hiệu, không thành mồ côi"
fi
unset FAKE_DWM_LINGER FAKE_DWM_PID

# --- T12: SIGHUP gửi riêng cho run.sh cũng phải dọn --------------------------
# Cần nói rõ: test này gửi SIGHUP cho PID run.sh, KHÔNG phải cả process group.
# Logout thật thì terminal gửi SIGHUP cho cả nhóm foreground nên dwm chết
# trước, rồi trap của run.sh mới chạy — đường đó đã hoạt động từ trước và
# không cần dwm nền. Test này cố tình khó hơn: chỉ run.sh nhận HUP thì dwm
# không ai giết, nếu trap bị hoãn thì cả hai cùng treo. Cần giữ để chắc đổi
# dwm sang nền không làm hỏng gì.
export FAKE_DWM_LINGER=1
export FAKE_DWM_PID="$T/dwm_hup.pid"
: > "$FAKE_DWM_COUNT"; rm -f "$FAKE_DWM_PID"
( cd "$R" && sh scripts/run.sh >/dev/null 2>&1 ) &
RUNPID=$!
for _ in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20; do
    [ -s "$FAKE_DWM_PID" ] && break
    sleep 0.5
done
hpid=$(cat "$FAKE_DWM_PID" 2>/dev/null)
kill -HUP "$RUNPID" 2>/dev/null
for _ in 1 2 3 4 5 6 7 8 9 10; do
    kill -0 "$RUNPID" 2>/dev/null || break
    sleep 0.5
done
if ! kill -0 "$RUNPID" 2>/dev/null; then
    ok "T12 SIGHUP (logout) — run.sh thoát sạch"
else
    bad "T12 SIGHUP không dọn" "run.sh vẫn sống"
    kill -9 "$RUNPID" 2>/dev/null
fi
sleep 1
if [ -n "$hpid" ] && kill -0 "$hpid" 2>/dev/null; then
    bad "T12b dwm mồ côi sau SIGHUP" "dwm $hpid còn sống"
    kill -9 "$hpid" 2>/dev/null
else
    ok "T12b dwm không còn sống sau SIGHUP"
fi
# --- T13: watchdog hồi sinh daemon chết giữa phiên --------------------------
# Đo thật trước khi có watchdog: giết xsettingsd, chờ 11s — không ai khởi
# động lại, khoá báo TRONG, daemon nằm chết tới logout. Nay watchdog phải
# đưa nó về sống.
mkdir -p "$T/repo/.config/xsettingsd"
: > "$T/repo/.config/xsettingsd/xsettingsd.conf"
cat > "$T/bin/xsettingsd" <<'EOF'
#!/bin/sh
printf '%s\n' "$$" > "$XS_PID_FILE"
while :; do sleep 0.3; done
EOF
chmod +x "$T/bin/xsettingsd"
export WD_INTERVAL=1
export WD_MAX_RETRY=5
export XS_PID_FILE="$T/xs.pid"
export FAKE_DWM_LINGER=1
export FAKE_DWM_PID="$T/dwm_wd.pid"
: > "$FAKE_DWM_COUNT"; rm -f "$FAKE_DWM_PID" "$XS_PID_FILE"
( cd "$R" && sh scripts/run.sh >/dev/null 2>&1 ) &
RUNPID=$!
for _ in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20; do
    [ -s "$XS_PID_FILE" ] && break
    sleep 0.5
done
xs1=$(cat "$XS_PID_FILE" 2>/dev/null)
if [ -n "$xs1" ] && kill -0 "$xs1" 2>/dev/null; then
    ok "T13 xsettingsd chạy, pid $xs1"
else
    bad "T13 xsettingsd không lên" "pid='$xs1'"
fi
kill -9 "$xs1" 2>/dev/null
sleep 0.5
[ -e "$T/run/tsuki-xsettingsd.lock" ] && \
  flock -n "$T/run/tsuki-xsettingsd.lock" -c true 2>/dev/null && \
  ok "T13b sau khi giết, khoá được thả (kernel tự thả)" || true
xs2=""
for _ in $(seq 1 24); do
    xs2=$(cat "$XS_PID_FILE" 2>/dev/null)
    [ -n "$xs2" ] && [ "$xs2" != "$xs1" ] && kill -0 "$xs2" 2>/dev/null && break
    xs2=""
    sleep 0.5
done
if [ -n "$xs2" ] && kill -0 "$xs2" 2>/dev/null; then
    ok "T13c watchdog hồi sinh xsettingsd: pid $xs1 -> $xs2"
else
    bad "T13c watchdog không hồi sinh" "vẫn là pid cũ '$xs1' sau 12s"
fi
# Dòng nhật ký chỉ ghi SAU khi watchdog chờ 1s xác nhận daemon giữ được khoá
# (xem run.sh). Nên phải chờ dòng log, không grep ngay lúc pid vừa đổi — làm
# vậy thì test fail oan dù watchdog chạy đúng. Đã mắc đúng lỗi này.
logged=""
for _ in $(seq 1 20); do
    if grep -q 'watchdog: xsettingsd đã chết' "$XDG_CACHE_HOME/tsuki/session.log" 2>/dev/null; then
        logged=1; break
    fi
    sleep 0.5
done
if [ -n "$logged" ]; then
    ok "T13d watchdog ghi vào nhật ký phiên"
else
    bad "T13d không có dấu vết trong nhật ký" "thiếu dòng 'watchdog: ... đã chết'"
fi

# --- T13e: daemon hồi sinh KHÔNG được cầm khoá của watchdog ------------------
# fd 7 là khoá riêng của watchdog. Watchdog gọi start_daemon khi hồi sinh, nên
# bản chưa sửa cho mọi daemon kế thừa fd 7 — tức daemon cầm khoá watchdog.
# Hệ quả: watchdog chết là khoá vẫn bị giữ, watchdog mới `flock -n 7` thất
# bại, KHÔNG BAO GIỜ chạy lại được trong phần đời còn lại của phiên.
# Đọc thẳng /proc/<pid>/fd, không suy từ hành vi.
_xs2=$(cat "$XS_PID_FILE" 2>/dev/null)
_wdfd=""
for _fd in /proc/$_xs2/fd/*; do
    _t=$(readlink "$_fd" 2>/dev/null) || continue
    case "$_t" in *tsuki-watchdog.lock) _wdfd="$_wdfd ${_fd##*/}";; esac
done
if [ -z "$_wdfd" ]; then
    ok "T13e daemon hồi sinh không cầm khoá watchdog (fd sạch)"
else
    bad "T13e daemon hồi sinh cầm khoá watchdog" "fd:$_wdfd -> tsuki-watchdog.lock"
fi
# Và watchdog phải VẪN giữ khoá của chính nó (không đóng nhầm fd 7)
_wdp=$(cat "$T/run/tsuki-watchdog.pid" 2>/dev/null)
if [ -n "$_wdp" ] && [ -e "/proc/$_wdp/fd/7" ] && \
   ! flock -n "$T/run/tsuki-watchdog.lock" -c true 2>/dev/null; then
    ok "T13f watchdog vẫn giữ khoá riêng (đóng fd 7 không ảnh hưởng nó)"
else
    bad "T13f watchdog mất khoá" "pid=$_wdp fd7=$([ -e /proc/$_wdp/fd/7 ] && echo co || echo khong) khoá=$(flock -n "$T/run/tsuki-watchdog.lock" -c true 2>/dev/null && echo TRONG || echo 'DA GIU')"
fi

# --- T14: watchdog CÓ TRẦN, không lặp vô tận --------------------------------
# Giết liên tục. Sau WD_MAX_RETRY lần watchdog phải bỏ qua và ghi rõ, thay
# vì thử vô tạn. Thử vô tạn tệ hơn lúc đầu: log đầy, CPU quay, nguyên nhân
# gốc bị chôn.
for _ in 1 2 3 4 5 6 7 8; do
    kill -9 "$(cat "$XS_PID_FILE" 2>/dev/null)" 2>/dev/null
    sleep 1.2
done
sleep 3
trials=$(grep -c 'watchdog: xsettingsd đã chết' "$XDG_CACHE_HOME/tsuki/session.log" 2>/dev/null)
trials=${trials:-0}
if [ "$trials" -le 6 ] && grep -q 'bỏ qua' "$XDG_CACHE_HOME/tsuki/session.log" 2>/dev/null; then
    ok "T14 watchdog trần ${trials} lần rồi bỏ qua (không lặp vô tận)"
else
    bad "T14 watchdog không có trần" "thử $trials lần, 'bỏ qua' trong log: $(grep -c 'bỏ qua' "$XDG_CACHE_HOME/tsuki/session.log" 2>/dev/null)"
fi

# --- T15: lúc đang tắt thì watchdog KHÔNG hồi sinh gì ------------------------
# Race thật: watchdog đang ngủ, run.sh bắt đầu dọn. Nếu watchdog thức dậy
# giữa chừng và hồi sinh daemon, ta thoát với một đám tiến trình mồ côi.
kill -TERM "$RUNPID" 2>/dev/null
wait "$RUNPID" 2>/dev/null
sleep 1
before=$(grep -c 'watchdog: .* đã chết' "$XDG_CACHE_HOME/tsuki/session.log" 2>/dev/null)
sleep 20
after=$(grep -c 'watchdog: .* đã chết' "$XDG_CACHE_HOME/tsuki/session.log" 2>/dev/null)
if [ "$before" = "$after" ]; then
    ok "T15 sau khi tắt, watchdog không hồi sinh thêm gì (vẫn $after dòng)"
else
    bad "T15 watchdog hồi sinh sau khi tắt" "$before -> $after dòng"
fi
leftover=$(ls "$T/run"/tsuki-xsettingsd.lock 2>/dev/null | wc -l)
[ "$leftover" -eq 0 ] && ok "T15b khoá đã dọn sạch" || bad "T15b còn khoá sót" "$leftover"
unset FAKE_DWM_LINGER FAKE_DWM_PID XS_PID_FILE WD_INTERVAL WD_MAX_RETRY
wait 2>/dev/null || true

# --- T16: kiểm font trước khi chạy dwm --------------------------------------
# dwm.c:3101 — `if (!drw_fontset_create(...)) die("no fonts could be loaded.")`.
# Thiếu font là chết NGAY lúc khởi động: màn hình đen, không bar, không gì để
# tra. run.sh phải báo trước khi dwm kịp chết.
cat > "$T/repo/config.h" <<'EOF'
static const char *fonts[] = {"DejaVu Sans:style=book:size=10" ,"Serif:style=book:size=10" };
EOF
: > "$FAKE_DWM_COUNT"
( cd "$R" && timeout 60 sh scripts/run.sh >/dev/null 2>&1 )
if grep -q 'INFO  font:' "$TSUKI_LOG_PATH" 2>/dev/null; then
    ok "T16 font có thật: ghi 'INFO font:' vào nhật ký"
else
    bad "T16 không có dòng font trong nhật ký" "$(grep -c 'font' "$TSUKI_LOG_PATH" 2>/dev/null) dòng có 'font'"
fi
if grep -q 'SẼ CHẾT NGAY' "$TSUKI_LOG_PATH" 2>/dev/null; then
    bad "T16b báo chết-ngay dù font hợp lệ" "config.h trong test dùng DejaVu/Serif, đều có thật"
else
    ok "T16b không báo chết-ngay khi font hợp lệ"
fi

# --- T17: config.h trỏ font KHÔNG tồn tại -> phải báo trước -------------------
cat > "$T/repo/config.h" <<'EOF'
static const char *fonts[] = {"TsukiFontKhongTonTai123:style=medium:size=12" };
EOF
: > "$FAKE_DWM_COUNT"
( cd "$R" && timeout 60 sh scripts/run.sh >/dev/null 2>&1 )
if grep -q 'SẼ CHẾT NGAY' "$TSUKI_LOG_PATH" 2>/dev/null && \
   grep -q 'TsukiFontKhongTonTai123' "$TSUKI_LOG_PATH" 2>/dev/null; then
    ok "T17 font thiếu: báo tên font và cách cài, trước khi dwm chết"
else
    bad "T17 không báo font thiếu" "log: $(grep -iE 'CHẾT|font' "$TSUKI_LOG_PATH" 2>/dev/null | head -3 | tr '\n' ';')"
fi
rm -f "$T/repo/config.h"

# --- T18: stderr của dwm phải vào nhật ký ------------------------------------
# Bản cũ cho stderr dwm thẳng ra terminal rồi mất: nhật ký chỉ còn
# "dwm crash lần N", không có lý do. Giờ phải bắt được.
# FAKE_DWM_FAULTS=1: stub tra 1, dung kieu dwm CHET. Neu trả 0 thi run.sh thoat
# sach o nhanh exit 0 va KHONG bao stderr — dung y nghia, nhung khong phai
# kich ban dang can kiem.
: > "$FAKE_DWM_COUNT"
export FAKE_DWM_FAULTS=1
( cd "$R" && timeout 60 sh scripts/run.sh >/dev/null 2>&1 )
unset FAKE_DWM_FAULTS
if grep -q 'dwm: no fonts could be loaded' "$TSUKI_LOG_PATH" 2>/dev/null; then
    ok "T18 lỗi của dwm được ghi vào nhật ký (trước đây mất sạch)"
else
    bad "T18 không bắt được lỗi dwm" "log: $(grep -i dwm "$TSUKI_LOG_PATH" 2>/dev/null | head -3 | tr '\n' ';')"
fi

# --- T18b: dwm SỐNG LÂU thì KHÔNG được đổ nhiễu app con vào nhật ký --------
# `dwm 2>file` bắt stderr của dwm, và MỌI APP DWM MỞ ĐỀU KẾ THỪA fd đó. Đo trên
# máy thật: một lần Super+Shift+R (dwm chạy 81s rồi chết 143) ghi 54 dòng nhãn
# "dwm:" — erresc của terminal, DeprecationWarning của Electron/Discord,
# mesa_glthread, gtk_widget_add_accelerator. KHÔNG dòng nào của dwm.
# Nhiều hơn cả lỗi cần tra, và giong hệt thứ của app khác.
#
# Nên: chỉ đưa vào nhật ký khi dwm chết DƯỚI 10s, lúc đó app con chưa kịp mở.
# PHẢI ghi vào $T/repo/dwm, KHÔNG CHỈ $T/bin/dwm. run.sh đặt $TSUKI_DIR trước
# PATH nên `type dwm` tìm thấy $T/repo/dwm — bản sao làm lúc dựng sandbox.
# Bản đầu chỉ sửa $T/bin/dwm nên stub 12s KHÔNG BAO GIỜ chạy, và T18b "PASS"
# vì lý do sai: stub nhanh thoát 0 ngay, không ghi gì ra stderr.
cp "$T/repo/dwm" "$T/repo/dwm.fast"
cat > "$T/repo/dwm" <<'STUB'
#!/bin/sh
# Không dùng tên biến tự bịa: lần đầu viết : >> "$DWM_MARK" (biến này không
# tồn tại) -> chuyển hướng lỗi làm dash CHẾT ngay dòng 2, sleep 12 không bao
# giờ chạy, _ran=0s. T18b vẫn "PASS" vì lý do sai: run.sh đúng ra đã phải báo
# nhiễu vì dwm chết sớm, nhưng cả hai dấu hiệu đều không xuất hiện nên test
# xanh. Dùng ${VAR:-/dev/null} để không bao giờ chết vì biến rỗng.
printf 'ran\n' >> "${FAKE_DWM_COUNT:-/dev/null}"
sleep 12
printf 'erresc: unknown csi ESC[>0q\n' >&2
printf '(node:1) DeprecationWarning: punycode\n' >&2
exit 143
STUB
chmod +x "$T/repo/dwm"
: > "$FAKE_DWM_COUNT"
( cd "$R" && timeout 90 sh scripts/run.sh >/dev/null 2>&1 )
if grep -qE 'dwm: (erresc|.*DeprecationWarning)' "$TSUKI_LOG_PATH" 2>/dev/null; then
    bad "T18b nhiễu app con bị ghi vào nhật ký" "$(grep -m2 'dwm: ' "$TSUKI_LOG_PATH" | tr '\n' ';')"
else
    ok "T18b dwm sống >10s: nhiễu app con KHÔNG vào nhật ký"
fi
# nhưng dòng "dwm chết sau Ns" vẫn phải có — không mất thông tin thật
if grep -q 'dwm chết sau 1[0-9]s' "$TSUKI_LOG_PATH" 2>/dev/null; then
    ok "T18c dòng 'dwm chết sau Ns' vẫn được ghi (không mất thông tin thật)"
else
    bad "T18c mất dòng báo dwm chết" "LOG=[$(tr '\n' ';' < "$TSUKI_LOG_PATH" 2>/dev/null | tail -c 400)]"
fi
# PHẢI khôi phục stub nhanh — T19..T23 chạy sau, stub ngủ 12s sẽ làm chúng
# chậm và có thể hỏng. Lần đầu quên, T19 tốn 12s mỗi vòng lặp.
mv "$T/repo/dwm.fast" "$T/repo/dwm"

# --- T19: KHÔNG được tham chiếu biến chưa đặt (set -u) ở bất kỳ đâu ----------
# run.sh chạy `set -u`. Tham chiếu biến chưa đặt KHÔNG phải cảnh báo mà là
# THOÁT NGAY — script chết giữa chừng, dwm không bao giờ chạy.
#
# Đã mắc đúng lỗi này: khai báo `TSUKI_FONT_ALIASES` nhưng dùng
# `$_TSUKI_FONT_ALIASES`; phiên chết ở dòng 761, trước khi tới dwm:
#     run.sh: line 761: _TSUKI_FONT_ALIASES: unbound variable
# T16/T17 bắt được, nhưng chỉ vì tình cờ. Test này thay cho may mắn: quét
# stderr của cả một phiên, bắt mọi lỗi loại này không kể chỗ nào.
# LƯU Ý giới hạn: T19 chỉ phủ những đường THẬT SỰ được thực thi. Đã thử: bỏ
# config.h đi thì dòng lỗi ở khối font không chạy tới, T19 xanh trong khi T16
# vẫn đỏ. Nên ở đây PHẢI có config.h để khối font chạy thật — không thì T19
# chỉ là trang trí.
cat > "$T/repo/config.h" <<'EOF'
static const char *fonts[] = {"DejaVu Sans:style=book:size=10" };
EOF
: > "$FAKE_DWM_COUNT"
( cd "$R" && sh scripts/run.sh >/dev/null 2>"$T/stderr19.txt" )
rm -f "$T/repo/config.h"
_st=""
for _pat in 'unbound variable' 'syntax error' 'parameter not set' 'command not found'; do
    if grep -q "$_pat" "$T/stderr19.txt" 2>/dev/null; then
        _m=$(grep -m1 "$_pat" "$T/stderr19.txt" 2>/dev/null | tr -d '\n')
        _st="$_st  [$_pat] $_m
"
    fi
done
if [ -z "$_st" ]; then
    ok "T19 cả phiên không có lỗi set -u / cú pháp / command not found"
else
    bad "T19 run.sh báo lỗi shell khi chạy" "$_st"
fi

# --- T20: KHÔNG hàm nào được GỌI trước khi ĐỊNH NGHĨA ------------------------
# Hàm shell phải có trước lệnh gọi. Đã mắc lỗi này HAI LẦN trong cùng phiên:
#   1) `safe_touch` dùng ở dòng 37, định nghĩa ở dòng 71 -> unbound/không gọi được
#   2) `( _font_check ) &` ở dòng 178, hàm ở dòng 790
#      -> "line 178: _font_check: command not found"
# Lần (2) bị T3/T19 bắt, nhưng cả hai chỉ bắt được khi đường đó được chạy tới.
# Test này kiểm TĨNH, nên bắt được cả khi không có test nào chạy tới.
#
# Cách kiểm: với mỗi tên hàm, tìm dòng định nghĩa `ten() {` và dòng gọi đầu
# tiên trong code (bỏ qua comment), rồi so số thứ tự.
_bad_fn=""
for _h in $(grep -oE '^[a-z_][a-z0-9_]*\(\) \{' "$R/scripts/run.sh" | sed 's/() {//'); do
    _def=$(grep -nE "^${_h}\(\) \{" "$R/scripts/run.sh" | head -1 | cut -d: -f1)
    [ -n "$_def" ] || continue
    # dòng gọi: không phải comment, không phải chính dòng định nghĩa, và có
    # tên hàm đứng sau một ký tự ngăn cách lệnh
    _use=$(grep -nE "(^|[;&|(]|[[:space:]])${_h}([[:space:]]|$)" "$R/scripts/run.sh" \
           | grep -vE "^[0-9]+:[[:space:]]*#" \
           | awk -F: -v d="$_def" '$1 != d {print $1; exit}')
    if [ -n "$_use" ] && [ "$_use" -lt "$_def" ]; then
        _bad_fn="$_bad_fn  $_h: gọi ở dòng $_use, định nghĩa ở dòng $_def
"
    fi
done
if [ -z "$_bad_fn" ]; then
    ok "T20 không hàm nào bị gọi trước khi định nghĩa"
else
    bad "T20 hàm dùng trước khi định nghĩa" "$_bad_fn"
fi

# --- T21: KHÔNG daemon nào trốn ra khỏi sandbox ------------------------------
# Đã gây ra hậu quả thật: stub thiếu `fcitx5` khiến sandbox gọi Fcitx5 THẬT.
# Nó fork rồi launcher chết; daemon thật thành mồ côi, còn `cleanup()` chỉ kill
# pid trong pidfile — mà pidfile trỏ launcher đã chết. Sau hàng trăm lần chạy:
# 596 tiến trình mồ côi, 6.2 GB PSS trên máy thật.
#
# PHẢI KIỂM TRƯỚC KHI cleanup xoá thư mục. Bản đầu lọc theo "(deleted)" — vô
# dụng, vì "(deleted)" chỉ xuất hiện SAU khi cleanup đã `rm -rf`; lúc đó thì mọi
# daemon trốn ra đều trông sạch, và T21 xanh trong khi `fcitx5` thật đã chạy.
# Nay kiểm trên khoá của CHÍNH lần chạy này ($T/run/tsuki-*.lock), lúc nó còn
# tồn tại: daemon trốn ra sẽ vẫn cầm khoá đó sau khi run.sh thoát.
_esc=""
# Khớp theo TIỀN TỐ ĐƯỜNG DẪN, không đối chiếu danh sách file khoá. `stop_daemons`
# đã `rm -f` các file khoá, nên `[ -f "$lk" ]` thất bại và vòng lặp bỏ qua hết —
# đó là lý do bản đầu báo PASS trong khi daemon thật đã trốn ra. readlink vẫn
# trả đường dẫn GỐC kèm " (deleted)", nên khớp tiền tố vẫn bắt được.
for _p in $(pgrep -x fcitx5 2>/dev/null; pgrep -x xsettingsd 2>/dev/null; \
            pgrep -x tumblerd 2>/dev/null); do
    for _fd in /proc/$_p/fd/*; do
        _t=$(readlink "$_fd" 2>/dev/null) || continue
        case "$_t" in
            "$T"/*) _esc="$_esc  pid $_p cầm $_t
" ;;
        esac
    done
done
if [ -z "$_esc" ]; then
    ok "T21 không daemon nào trốn ra khỏi sandbox"
else
    bad "T21 daemon trốn ra ngoài sandbox" "$_esc"
fi

# --- T22: screensaver + DPMS của X server -------------------------------------
# Đo trên máy thật trước khi sửa: X screensaver BẬT, timeout 600, và
#     DPMS: Standby 600  Suspend 600  Off 600 — DPMS is Enabled
# Rời chuột 10 phút là màn hình trắng rồi monitor ngủ, trên X thuần không có
# idle daemon nào cấu hình được, và nó quay lại KHÔNG khoá.
#
# Kiểm bằng cách đọc lệnh `xset` mà run.sh thực sự gọi, quan sát qua PATH giả.
mkdir -p "$T/ss"
cat > "$T/ss/xset" <<'EOF'
#!/bin/sh
printf '%s\n' "$*" >> "$XSET_CALLS"
EOF
chmod +x "$T/ss/xset"
# xset phải được `have` thấy -> nằm trước /usr/bin trong PATH
_xss() {
    export XSET_CALLS="$T/ss/calls.$1"; : > "$XSET_CALLS"
    shift
    : > "$FAKE_DWM_COUNT"
    ( cd "$R" && PATH="$T/ss:$PATH" TSUKI_SCREENSAVER="$1" \
        sh scripts/run.sh >/dev/null 2>&1 )
    cat "$XSET_CALLS" 2>/dev/null
}
_calls=$(_xss default "")
if printf '%s\n' "$_calls" | grep -qx 's off' && printf '%s\n' "$_calls" | grep -qx -- '-dpms'; then
    ok "T22 mặc định: xset s off + xset -dpms"
else
    bad "T22 mặc định không tắt screensaver" "xset được gọi: [$(printf '%s' "$_calls" | tr '\n' '|')]"
fi
_calls=$(_xss keep keep)
# Bỏ `r rate` — đó là lời gọi xset khác, luôn chạy. Chỉ kiểm lệnh liên quan
# screensaver. Bản đầu khẳng định "không gọi xset nào" nên FAIL oan.
_calls_ss=$(printf '%s\n' "$_calls" | grep -v '^r rate ' | grep -v '^$')
if [ -z "$_calls_ss" ]; then
    ok "T22b TSUKI_SCREENSAVER=keep: không đụng screensaver/DPMS"
else
    bad "T22b keep vẫn gọi xset liên quan screensaver" "[$(printf '%s' "$_calls_ss" | tr '\n' '|')]"
fi
_calls=$(_xss num 600)
if printf '%s\n' "$_calls" | grep -qx 's 600'; then
    ok "T22c TSUKI_SCREENSAVER=600: đặt timeout, vẫn tắt DPMS"
else
    bad "T22c giá trị số không được dùng" "[$(printf '%s' "$_calls" | tr '\n' '|')]"
fi
_calls=$(_xss bad abc)
if printf '%s\n' "$_calls" | grep -qx 's off'; then
    ok "T22d giá trị rác -> rơi về off, không để trạng thái lạ"
else
    bad "T22d giá trị rác xử lý sai" "[$(printf '%s' "$_calls" | tr '\n' '|')]"
fi
rm -f "$T"/ss/calls.*

# --- T23: feh không được rác .fehbg vào $HOME ---------------------------------
# `feh --bg-fill` ghi .fehbg vào thư mục hiện tại. Chạy từ startx thì thư mục
# đó là $HOME — đo thấy ~/.fehbg bị ghi lại mỗi lần đăng nhập. `dwmwal.sh` cố
# ý dùng --no-fehbg, riêng run.sh thì quên.
if grep -qE '^\s*feh --bg-' "$R/scripts/run.sh"; then
    bad "T23 run.sh còn gọi feh thiếu --no-fehbg" "$(grep -nE '^\s*feh --bg-' "$R/scripts/run.sh" | head -1)"
else
    n_feh=$(grep -cE '^\s*feh --no-fehbg ' "$R/scripts/run.sh")
    ok "T23 cả $n_feh lời gọi feh đều có --no-fehbg"
fi

printf '\n  %d PASS, %d FAIL\n' "$P" "$F"
[ "$F" -eq 0 ]

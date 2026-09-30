#!/usr/bin/env dash
# Test cho start_daemon()/stop_daemons() của run.sh — trích trực tiếp từ
# file thật nên test không thể "trôi" khỏi bản đang dùng.
set -u
R=/home/frost-auslese/tsuki/scripts/run.sh
T=$(mktemp -d)
P=0; F=0
ok()  { printf '  PASS  %s\n' "$*"; P=$((P+1)); }
bad() { printf '  FAIL  %s\n        %s\n' "$*"; F=$((F+1)); }
cleanup() {
    for p in $(cat "$T"/run/tsuki-*.pid 2>/dev/null); do kill "$p" 2>/dev/null; done
    sleep 0.3
    rm -rf "$T"
}
trap cleanup EXIT INT TERM

FNS="$T/fns.sh"
cat > "$FNS" <<'EOF'
TSUKI_LOG=/dev/null
log()  { :; }
info() { :; }
warn() { :; }
fail() { :; }
have() { command -v "$1" >/dev/null 2>&1; }
EOF
sed -n '/^start_daemon() {/,/^}/p' "$R" >> "$FNS"
sed -n '/^stop_daemons() {/,/^}/p' "$R" >> "$FNS"
grep -q '^start_daemon() {' "$FNS" || { echo "FAIL: không trích được start_daemon"; exit 1; }

export XDG_RUNTIME_DIR="$T/run"; mkdir -p "$XDG_RUNTIME_DIR"
sd() { dash -c ". '$FNS'; start_daemon $*" 2>/dev/null; }
gf() { head -1 "$XDG_RUNTIME_DIR/tsuki-$1.pid" 2>/dev/null; }
n_of() { pgrep -c -x "$1" 2>/dev/null || echo 0; }

# --- T1: spawn lần đầu, ghi pid đúng tiến trình ------------------------------
sd sleeper sleep 300
sleep 0.4
p1=$(gf sleeper)
if [ -n "$p1" ] && [ "$(cat /proc/$p1/comm 2>/dev/null)" = sleep ]; then
    ok "T1 spawn lần đầu, pidfile $p1 trỏ đúng tiến trình 'sleep'"
else
    bad "T1 spawn lần đầu" "pid='$p1' comm='$(cat /proc/$p1/comm 2>/dev/null)'"
fi

# --- T2: gọi lại KHÔNG spawn trùng (khoá còn bị giữ) ------------------------
sd sleeper sleep 300
sleep 0.4
p2=$(gf sleeper)
# KHÔNG đếm `pgrep -x sleep`: chính các lệnh `sleep 0.4` trong test này cũng
# tên là sleep, nên đếm toàn hệ thống luôn ra số sai. So pid cụ thể.
if [ "$p1" = "$p2" ] && kill -0 "$p2" 2>/dev/null; then
    ok "T2 gọi lại không spawn trùng (pid giữ nguyên $p2)"
else
    bad "T2 không spawn trùng" "p1=$p1 p2=$p2"
fi

# --- T3: daemon chết thì khoá được thả, lại gọi thì spawn mới -----------------
kill "$p1" 2>/dev/null; sleep 0.6
if ! kill -0 "$p1" 2>/dev/null; then
    ok "T3 daemon chết → pid $p1 không còn sống"
else
    bad "T3 daemon chết" "pid $p1 vẫn sống"
fi
sd sleeper sleep 300
sleep 0.4
p3=$(gf sleeper)
if [ -n "$p3" ] && [ "$p3" != "$p1" ] && kill -0 "$p3" 2>/dev/null; then
    ok "T3b khoá đã được thả → gọi lại spawn tiến trình mới (pid $p3)"
else
    bad "T3b spawn lại sau khi chết" "pid cũ=$p1 pid mới=$p3"
fi

# --- T4: PID bị thu hồi cho tiến trình KHÁC cùng tên -------------------------
# Đây là lỗi của bản cũ (pidfile + kill -0). Ở đây tiến trình thay thế có
# comm GIỐNG HỆT "sleep", nên so comm cũng không phân biệt được — chỉ flock
# mới đúng.
kill "$p3" 2>/dev/null; sleep 0.5
sleep 300 & impostor=$!
echo "$impostor" > "$XDG_RUNTIME_DIR/tsuki-sleeper.pid"
sd sleeper sleep 300
sleep 0.4
p4=$(gf sleeper)
if [ "$p4" != "$impostor" ] && kill -0 "$p4" 2>/dev/null; then
    ok "T4 PID bị thu hồi cho tiến trình cùng tên → vẫn spawn đúng (pid $p4)"
else
    bad "T4 PID bị thu hồi" "dùng lại pid $impostor (lỗi của bản cũ)"
fi
kill "$impostor" 2>/dev/null

# --- T5: nhiều daemon khác tên chạy song song --------------------------------
for n in alpha beta gamma; do sd "$n" sleep 301; done
sleep 0.5
alive=0
for n in alpha beta gamma; do
    q=$(gf "$n")
    [ -n "$q" ] && kill -0 "$q" 2>/dev/null && alive=$((alive+1))
done
if [ "$alive" -eq 3 ]; then
    ok "T5 ba daemon khác tên chạy song song (3/3)"
else
    bad "T5 ba daemon" "sống $alive/3"
fi

# --- T6: race — gọi start_daemon song song 5 lần, chỉ 1 daemon được sinh ------
for n in racy; do
    for i in 1 2 3 4 5; do sd "$n" sleep 302 & done
done
wait
sleep 0.6
base=$(n_of sleep)
racy_pids=$(pgrep -x sleep 2>/dev/null | wc -l)
# đếm số process con có FD trên lockfile của racy
holders=$(ls -l /proc/*/fd 2>/dev/null | grep -c "tsuki-racy.lock" || echo 0)
if [ "$holders" -le 1 ]; then
    ok "T6 race 5 lần song song → chỉ 1 daemon giữ khoá (holders=$holders)"
else
    bad "T6 race" "$holders tiến trình cùng giữ khoá"
fi

# --- T7: stop_daemons dừng hết và dọn cả khoá --------------------------------
dash -c ". '$FNS'; stop_daemons" >/dev/null 2>&1
sleep 0.8
alive=""
for q in "$p4"; do
    [ -n "${q:-}" ] || continue
    kill -0 "$q" 2>/dev/null && alive="$alive $q"
done
for n in alpha beta gamma racy; do
    q=$(gf "$n")
    [ -n "$q" ] && kill -0 "$q" 2>/dev/null && alive="$alive $q"
done
locks=$(ls "$XDG_RUNTIME_DIR"/tsuki-*.lock 2>/dev/null | wc -l)
if [ -z "$alive" ] && [ "$locks" -eq 0 ]; then
    ok "T7 stop_daemons dừng hết daemon và dọn khoá"
else
    bad "T7 stop_daemons" "còn sống:$alive, $locks khoá"
fi

# --- T8: stop rồi gọi lại được spawn lại ------------------------------------
sd sleeper sleep 300
sleep 0.4
p8=$(gf sleeper)
if [ -n "$p8" ] && kill -0 "$p8" 2>/dev/null; then
    ok "T8 sau stop_daemons, gọi lại spawn được (pid $p8)"
else
    bad "T8 spawn lại sau stop" "pid='$p8'"
fi
kill "$p8" 2>/dev/null

printf '\n  %d PASS, %d FAIL\n' "$P" "$F"
[ "$F" -eq 0 ]

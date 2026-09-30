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

# --- T9: khoa run.sh PHAI SONG SAI khi script con tu khoa bang fd 9 -------
# Do duoc tren phien that. updates-loop.sh lam
#     exec 9>"$HOME/.cache/dwm-updates.lock"
# `exec 9>` GHI DE fd 9 cua chinh no -> tha khoa ma run.sh dang giu. Sau do
# lan start_daemon ke tiep thay khoa trong va spawn ban thu hai.
# run.sh nay dung fd 8 nen khong va cham.
#
# CHÚ Ý: khoá của script con PHẢI là file KHÁC. flock xung đột kể cả khi
# hai fd trong cùng một tiến trình trỏ cùng một file, nên nếu cho con khoá
# đúng file của run.sh thì `flock -n 9` trả 1, con `exit 0` ngay, và test báo
# FAIL dù code đúng. Thực tế cũng vậy: run.sh khoá
# $XDG_RUNTIME_DIR/tsuki-updates.lock còn updates-loop.sh khoá
# $HOME/.cache/dwm-updates.lock — hai file riêng.
cat > "$T/selflock.sh" <<'SL'
#!/bin/sh
exec 9>"$CHILD_LOCK"
flock -n 9 || exit 0
while :; do sleep 300; done
SL
chmod +x "$T/selflock.sh"
export CHILD_LOCK="$T/child-own.lock"
sd selflock dash "$T/selflock.sh"
sleep 0.6
# Kiem tra KHOA (khong kiem pid) - day moi la co che dung dac.
# Probe bang DUONG DAN, khong phai bang so fd: `flock -n 8 -c true` se ke
# thua chinh fd 8 cua shell dang goi nen bao gioi cung ra "tha khoa".
if flock -n "$XDG_RUNTIME_DIR/tsuki-selflock.lock" -c true 2>/dev/null; then
    bad "T9 khoa con sau khi script con tu flock fd 9" "khoa bi tha"
else
    ok "T9 khoa van duoc giu sau khi script con tu flock fd 9"
fi
sd selflock dash "$T/selflock.sh"
sleep 0.5
q=$(gf selflock)
if [ -n "$q" ] && kill -0 "$q" 2>/dev/null; then
    ok "T9b goi lai khong spawn ban thu hai"
else
    bad "T9b spawn trung" "pid='$q'"
fi
unset CHILD_LOCK

# --- T9c: chung minh T9 THAT SU BAT LOI, khong phai test ruong -----------
# Chay lai dung kich ban do, nhung ban start_daemon da dung lai fd 9 (ban
# cu). Neu T9 van PASS o day thi test khong kiem duoc gi ca.
export CHILD_LOCK="$T/child-own-fd9.lock"
sed -e 's/^        exec 8>/        exec 9>/' \
    -e 's/^        flock -n 8 || exit 0/        flock -n 9 || exit 0/' "$FNS" > "$T/fns_fd9.sh"
grep -q 'exec 9>"\$_lock"' "$T/fns_fd9.sh" || { bad "T9c khong tao duoc ban fd 9" "sed that bai"; }
dash -c ". '$T/fns_fd9.sh'; start_daemon oldfd dash '$T/selflock.sh'" 2>/dev/null
sleep 0.6
if flock -n "$XDG_RUNTIME_DIR/tsuki-oldfd.lock" -c true 2>/dev/null; then
    ok "T9c ban cu (fd 9) that su tha khoa — T9 co gia tri"
else
    bad "T9c ban cu van giu khoa" "T9 khong bat duoc loi that"
fi
kill "$(head -1 "$XDG_RUNTIME_DIR/tsuki-oldfd.pid" 2>/dev/null)" 2>/dev/null

# --- T10: daemon TỰ FORK (launcher chết) vẫn phải bị stop_daemons dọn -------
# Đây là kịch bản `fcitx5 -d`, đo được trên phiên thật:
#   tsuki-fcitx.pid = 452635  (CHẾT)   <- launcher
#   pid 3046 fcitx5            (SỐNG)  <- daemon thật
# `kill $pid` trên nội dung pidfile là kill một PID đã chết: im lặng, exit
# status bị nuốt, tưởng đã dọn xong. Rồi `rm -f` xoá file khoá trong khi
# daemon vẫn giữ fd trỏ tới inode đã xoá. Hậu quả: daemon sống sót qua
# logout (phiên sau sinh bản thứ hai), và khoá trên đĩa thành inode MỚI + TRỐNG
# nên watchdog tưởng daemon chết rồi thử sinh thêm — fcitx5 từ chối vì đã có
# một instance, khoá lại trống, watchdog ghi "không khởi động được fcitx (thiếu
# binary?)". Chẩn đoán sai hoàn toàn: binary có, daemon sống, ta chỉ mất dấu.
#
# stop_daemons nay gọi `fuser` trên từng file khoá để giết tiến trình THẬT
# đang giữ nó, không chỉ pid trong file.
cat > "$T/forker.sh" <<FORKEOF
#!/bin/sh
# giong 'fcitx5 -d': fork daemon that roi launcher chet ngay
sleep 300 &
printf '%s\n' "\$!" > "$T/real.pid"
exit 0
FORKEOF
chmod +x "$T/forker.sh"
sd forked "$T/forker.sh"
sleep 0.7
_lp=$(gf forked)                 # pid launcher: start_daemon ghi pid nay
_rp=$(cat "$T/real.pid" 2>/dev/null || echo '')
if [ -n "$_rp" ] && ! kill -0 "$_lp" 2>/dev/null && kill -0 "$_rp" 2>/dev/null; then
    ok "T10 dựng được daemon tự fork: launcher $_lp chết, daemon $_rp sống"
else
    bad "T10 dựng daemon tự fork" "launcher=$_lp (chet=$([ -n "$_lp" ] && ! kill -0 "$_lp" 2>/dev/null && echo yes || echo no)) daemon=$_rp"
fi
if flock -n "$XDG_RUNTIME_DIR/tsuki-forked.lock" -c true 2>/dev/null; then
    bad "T10 daemon con khong giu khoa" "khoa trong -> mo hinh fork khong giong fcitx5 -d"
else
    ok "T10 daemon con vẫn giữ khoá (kế thừa fd 8 qua fork)"
fi

dash -c ". '$FNS'; stop_daemons" >/dev/null 2>&1
sleep 0.8
if [ -n "$_rp" ] && ! kill -0 "$_rp" 2>/dev/null; then
    ok "T10 stop_daemons giết được daemon thật dù pidfile trỏ launcher đã chết"
else
    bad "T10 daemon sống sót qua stop_daemons" "pid $_rp van song — stop_daemons chi kill duoc pid trong pidfile"
fi
if [ -e "$XDG_RUNTIME_DIR/tsuki-forked.lock" ]; then
    bad "T10 khoa con lai" "tsuki-forked.lock chua bi xoa"
else
    ok "T10 khoa đã dọn sạch"
fi

# --- T10b: chứng minh T10 bắt được lỗi THẬT, không phải test rỗng ------------
# Chạy lại với bản stop_daemons CŨ (chỉ kill pid trong pidfile). Nếu T10 vẫn
# xanh ở đây thì test không kiểm được gì.
sed -e '/if have fuser; then/,/^            fi$/d' "$FNS" > "$T/fns_nofuser.sh"
grep -q 'have fuser' "$T/fns_nofuser.sh" && bad "T10b khong cat duoc khoi fuser" "sed that bai"
sd forked2 "$T/forker.sh"
sleep 0.7
_rp2=$(cat "$T/real.pid" 2>/dev/null || echo '')
dash -c ". '$T/fns_nofuser.sh'; stop_daemons" >/dev/null 2>&1
sleep 0.8
if [ -n "$_rp2" ] && kill -0 "$_rp2" 2>/dev/null; then
    ok "T10b bản cũ (không fuser) ĐỂ LỌT daemon $_rp2 — T10 có giá trị"
    kill "$_rp2" 2>/dev/null
else
    bad "T10b bản cũ cũng dọn được" "T10 không chứng minh được lỗi gì"
fi

printf '\n  %d PASS, %d FAIL\n' "$P" "$F"
[ "$F" -eq 0 ]

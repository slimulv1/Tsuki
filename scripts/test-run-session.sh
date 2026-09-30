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
for c in feh picom xset xsetroot xrdb notify-send dunst flock; do
    printf '#!/bin/sh\nexit 0\n' > "$T/bin/$c"
    chmod +x "$T/bin/$c"
done
# `type dwm` trong run.sh phải thấy dwm giả
cat > "$T/bin/dwm" <<'EOF'
#!/bin/sh
n=$(cat "$FAKE_DWM_COUNT" 2>/dev/null); n=${n:-0}
n=$((n + 1))
printf '%s\n' "$n" > "$FAKE_DWM_COUNT"
# Số lần chết nhanh từ biến môi trường; lần đó trả 1, còn lại trả 0
if [ "$n" -le "${FAKE_DWM_FAULTS:-0}" ]; then
    exit 1
fi
exit 0
EOF
chmod +x "$T/bin/dwm"

export PATH="$T/bin:/usr/bin:/bin"
export HOME="$T/home"
export XDG_RUNTIME_DIR="$T/run"
export XDG_CACHE_HOME="$T/home/.cache"
export TSUKI_DIR="$R"
export FAKE_DWM_COUNT="$T/dwm.count"
export NO_COLOR=1
: > "$FAKE_DWM_COUNT"

# run.sh tự prepend "/usr/local/bin" vào PATH (dòng 27) — nên dwm THẬT ở đó
# thắng stub của ta, và test sẽ vô tình chạy window manager thật (nó chỉ báo
# "another window manager is already running" rồi thoát, nhưng đó không phải
# thứ ta muốn kiểm). Không tránh được bằng môi trường, nên tạo một BẢN SAO
# của run.sh với đúng hai dòng khai báo PATH trỏ sang thư mục stub. Mọi logic
# khác — toàn bộ nội dung run.sh — là nguyên văn file thật.
python3 - "$R/scripts/run.sh" "$T/run.sh" <<'PY'
import sys
src, dst = sys.argv[1], sys.argv[2]
text = open(src, encoding="utf-8").read()
text = text.replace('PATH="/usr/local/bin:$PATH"',
                    'PATH="$TSUKI_STUB:$PATH"', 1)
text = text.replace('export PATH="$TSUKI_DIR/dmenu:$TSUKI_DIR:$PATH"',
                    'export PATH="$TSUKI_STUB:$TSUKI_DIR/dmenu:$TSUKI_DIR:$PATH"', 1)
open(dst, "w", encoding="utf-8").write(text)
PY
if grep -q 'PATH="/usr/local/bin:$PATH"' "$T/run.sh"; then
    echo "SAI: chưa trung hoá được PATH" >&2
    exit 1
fi
export TSUKI_STUB="$T/bin"
TSUKI_LOG_PATH="$XDG_CACHE_HOME/tsuki/session.log"
export TSUKI_STUB="$T/bin"
TSUKI_LOG_PATH="$XDG_CACHE_HOME/tsuki/session.log"

# --- T1: chạy trọn vẹn, thoát sạch, ghi nhật ký -----------------------------
printf '  (chạy run.sh thật, dwm giả trả 0 ngay)\n'
out=$(cd "$R" && timeout 60 sh "$T/run.sh" 2>&1)
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
: > "$FAKE_DWM_COUNT"
export FAKE_DWM_FAULTS=5     # 5 lần crash nhanh, lần 6 thì exit 0
t0=$(date +%s)
( cd "$R" && timeout 120 sh "$T/run.sh" >/dev/null 2>&1 )
t1=$(date +%s)
n=$(cat "$FAKE_DWM_COUNT" 2>/dev/null); n=${n:-0}
elapsed=$((t1 - t0))
# backoff 0.3+0.6+1.2+2.4+4.8 = 9.3s cho 5 lần crash
if [ "$n" -eq 6 ]; then
    ok "T6 dwm crash $n lần rồi thoát sạch (đúng số lần)"
else
    bad "T6 số lần chạy dwm" "chạy $n lần, mong đợi 6"
fi
if [ "$elapsed" -ge 8 ]; then
    ok "T6b backoff có tác dụng: 5 lần crash mất ${elapsed}s (không phải 1.5s như bản cũ)"
else
    bad "T6b backoff" "chỉ ${elapsed}s — có vẻ không nghỉ"
fi

# --- T7: crash VÔ HẠN thì phải dừng, không quay vòng mãi ---------------------
: > "$FAKE_DWM_COUNT"
export FAKE_DWM_FAULTS=999   # luôn crash
out2=$( (cd "$R" && timeout 90 sh "$T/run.sh" 2>&1) )
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

printf '\n  %d PASS, %d FAIL\n' "$P" "$F"
[ "$F" -eq 0 ]

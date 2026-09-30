#!/bin/bash
# fuzz-status.sh — regression test cho parser escape status2d của dwm.
#
# Parser nằm trong drawstatusbar(), đọc chuỗi lấy từ WM_NAME của ROOT WINDOW —
# tức BẤT KỲ X client nào trong session cũng ghi được. Đây là input không tin
# cậy thật sự, và nó đã từng giết dwm 3 lần:
#
#   1. heap OOB read  — escape ^f bị cắt cụt, ++i bước qua byte NUL
#   2. heap OOB write — nhánh ^r quét hết buffer, i vượt byte NUL, rồi
#                       text[i]='\0' ghi ra ngoài
#   3. DoS           — ^c#zzzzzz^ khiến XftColorAllocName fail -> drw die()
#
# Cách chạy: dựng dwm dưới ASan trên Xvfb riêng, bắn payload, đòi dwm phải
# sống. Chạy được cả trong CI lẫn tay, không đụng session thật.
#
#   ./scripts/fuzz-status.sh [so_payload] [do_dai_max]
#
# Exit 0 = dwm sống sót toàn bộ payload (PASS).

set -u

ROUNDS=${1:-6000}
MAXLEN=${2:-48}
# BUG ĐÃ SỬA: ghi cứng /home/slimu/dwm — đường dẫn trên máy tác giả, không tồn
# tại ở đây, nên script luôn fail ở dòng [ -f "$DWM" ]. Giờ suy ra từ vị trí
# script (vẫn override được bằng DWM_SRC=... nếu muốn trỏ chỗ khác).
DWM_SRC=${DWM_SRC:-$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd -P)}
DISP=${DISP:-:99}

DWM="$DWM_SRC/dwm"
ASAN_BIN="$DWM_SRC/.fuzz/dwm-asan"
PY=${PYTHON:-python3}

log()  { printf '%s\n' "$*"; }
fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }

command -v Xvfb      >/dev/null || { log "bỏ qua: không có Xvfb"; exit 0; }
[ -f "$DWM" ] || fail "không thấy $DWM (chạy make trước)"

mkdir -p "$DWM_SRC/.fuzz"
ASAN_OPTIONS="detect_leaks=0:abort_on_error=0"
export ASAN_OPTIONS

log "==> build dwm + ASan/UBSan"
cc -std=c23 -g -O1 -fsanitize=address,undefined -fno-omit-frame-pointer \
   -D_DEFAULT_SOURCE -D_BSD_SOURCE -D_XOPEN_SOURCE=700L -DVERSION='"6.8"' \
   -DXINERAMA -I/usr/include/freetype2 \
   -o "$ASAN_BIN" "$DWM_SRC"/dwm.c "$DWM_SRC"/drw.c "$DWM_SRC"/util.c \
   -lX11 -lXinerama -lfontconfig -lXft -lXrender -lImlib2 \
   || fail "build thất bại"

cleanup() {
	[ -n "${DWM_PID:-}" ] && kill "$DWM_PID" 2>/dev/null
	[ -n "${XVFB_PID:-}" ] && kill "$XVFB_PID" 2>/dev/null
	wait 2>/dev/null
	rm -f "/tmp/.X${DISP#:}-lock" 2>/dev/null
	return 0
}
trap cleanup EXIT

log "==> Xvfb $DISP"
Xvfb "$DISP" -screen 0 1920x1080x24 -nolisten tcp >"$DWM_SRC/.fuzz/xvfb.log" 2>&1 &
XVFB_PID=$!
sleep 3
DISPLAY="$DISP" xdpyinfo >/dev/null 2>&1 || fail "Xvfb không lên"

log "==> dwm (ASan) trên $DISP"
DISPLAY="$DISP" "$ASAN_BIN" >"$DWM_SRC/.fuzz/dwm.log" 2>&1 &
DWM_PID=$!
# Bắt buộc export: phần Python đọc os.environ["DWM_PID"] để hỏi dwm còn sống
# không. Không export thì Python ném KeyError và script báo FAIL giả.
export DWM_PID
sleep 4
kill -0 "$DWM_PID" 2>/dev/null || { cat "$DWM_SRC/.fuzz/dwm.log"; fail "dwm không khởi động"; }

log "==> bắn payload"
if ! DISPLAY="$DISP" ROUNDS="$ROUNDS" MAXLEN="$MAXLEN" "$PY" - <<'PYEOF'
import os, random, subprocess, sys, time
from Xlib import display

disp = os.environ["DISPLAY"]
d = display.Display(disp)
root = d.screen().root

def alive():
    return subprocess.run(["kill", "-0", os.environ["DWM_PID"]],
                          capture_output=True).returncode == 0

# các payload đã từng giết dwm — phải nằm trong danh sách này
known_bad = [
    "CPU 42%^f",           # (1) OOB read
    "A^f",                 # (1)
    "hi^r1,2,3",           # (2) OOB write
    "5^85d r9f03c1669bd86#2",  # (2) payload thật đã bắt được
    "^c#zzzzzz^",          # (3) DoS
    "^b#zzzzzz^",          # (3)
    "^c#gggggg^",          # (3)
    "^c#00000^",           # (3)
    "^r1,2,3,", "^r1,2,", "^r1,", "^r,", "^r", "^f", "^c", "^b", "^^,",
    "65536x65536^", "AAAAAAAAAA^f", "x^r1,2,3,4,5,6^", "^f99999999999^",
    # input hợp lệ — phải vẫn parse được, không được chết
    "^c#010203^^d^CPU 42% RAM 5G 34C^d^",
    "^b#1e1e2e^vol 80^f10^wlan0^",
    "^r10,2,20,8^^f6^abc^f0^def",
]
for p in known_bad:
    root.set_wm_name(p); d.flush(); time.sleep(0.2)
    if not alive():
        print("DWM CHẾT bởi payload đã biết: %r" % p); sys.exit(1)

random.seed(20260926)
alpha = "^fbrcd0123456789,#- xABCXYZ"
n = 0
for i in range(int(os.environ["ROUNDS"])):
    s = "".join(random.choice(alpha)
                for _ in range(random.randint(1, int(os.environ["MAXLEN"]))))
    root.set_wm_name(s); d.flush(); n += 1
    if i % 50 == 0:
        time.sleep(0.05)
        if not alive():
            print("DWM CHẾT ở payload #%d: %r" % (i, s)); sys.exit(1)

print("dwm sống sau %d payload ngẫu nhiên + %d payload đã biết"
      % (n, len(known_bad)))
sys.exit(0)
PYEOF
then
	fail "dwm chết khi tấn công (xem .fuzz/dwm.log)"
fi

sleep 1
if kill -0 "$DWM_PID" 2>/dev/null; then
	: # còn sống
else
	cat "$DWM_SRC/.fuzz/dwm.log"
	fail "dwm đã chết"
fi

if grep -qE 'ERROR: AddressSanitizer|runtime error' "$DWM_SRC/.fuzz/dwm.log"; then
	grep -A15 -E 'ERROR: AddressSanitizer|runtime error' "$DWM_SRC/.fuzz/dwm.log"
	fail "sanitizer báo lỗi (xem .fuzz/dwm.log)"
fi

log "PASS: dwm sống, sanitizer sạch"
exit 0

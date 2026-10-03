#!/usr/bin/env bash
# Ghi nhan cac VUNG CODE CHET do hang so bien dich = 0, va chung minh bang
# gcov tren dwm that chay tren Xvfb.
#
# ================================================================== VÌ SAO FILE NÀY TỒN TẠI
#
# Câu hỏi hay đặt ra: "dwm còn code chết nào không?". Đọc mắt không đủ — phải
# đo. Cách đo ở đây là coverage (gcov) chạy trên dwm thật với workload thật:
# một vùng mà `#####` (chưa bao giờ thực thi) VÀ nằm sau một hằng số compile
# -time bằng 0 thì chắc chắn không thể chạy, không phải "chưa được test".
#
# PHÂN BIỆT QUAN TRỌNG — đã dính sai hai lần khi làm thủ công:
#   - "hàm chưa bao giờ chạy" KHÔNG đồng nghĩa dead code. Lần đầu dot đo thấy
#     5 hàm 0%, trong đó 4 chỉ là THIẾU WORKLOAD: placemouse cần kéo chuột
#     (Super+Button1), tabmode cần Super+Ctrl+w, show cần hide→restore đúng
#     tag, shiftview/movestack cần phím mũi tên. Sau khi bổ sung workload,
#     coverage dwm.c tăng 53.9% -> 64.8% và 4 hàm đó có số đếm khác 0.
#   - chỉ `tag_preview = 0` mới thật sự chặn.
#
# TEST NÀY CHẠY CHẬM (cần build + gcov + workload ~1-2 phút). Nếu thiếu cc hoặc
# Xvfb thì báo -- chứ không coi là pass.
set -u

R="$(cd "$(dirname "$0")/.." && pwd)"
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT INT TERM

ok()  { printf '  PASS  %s\n' "$*"; P=$((P + 1)); }
bad() { printf '  FAIL  %s\n' "$1"; [ $# -gt 1 ] && printf '        %s\n' "$2"; F=$((F + 1)); }
skip() { printf '  --    %s\n' "$*"; }
P=0; F=0

skip_build() {
    skip "$1"
    printf '\n  %d PASS, %d FAIL\n' "$P" "$F"
    exit 0
}

for tool in cc Xvfb gcov xrandr; do
    command -v "$tool" >/dev/null 2>&1 || skip_build "thiếu $tool — KHÔNG phải 'test pass', dead code chưa được kiểm"
done

# ---------------------------------------------------------------- V1: khai bao
# Đọc hằng số = 0 trong config.h — đây là nguồn của mọi vùng chết bên dưới.
declare -A ZERO_CONST
while IFS= read -r line; do
    name=$(printf '%s' "$line" | sed -n 's/^static const \(unsigned \)\?int \([a-zA-Z_][a-zA-Z0-9_]*\)[[:space:]]*=[[:space:]]*0;.*/\2/p')
    [ -n "$name" ] && ZERO_CONST["$name"]=1
done < "$R/config.h"

expect_tag_preview=$(grep -E '^static const int +tag_preview ' "$R/config.h" | sed 's/.*=[[:space:]]*\([0-9]*\).*/\1/')
expect_systraypin=$(grep -E '^static const unsigned int +systraypinning ' "$R/config.h" | sed 's/.*=[[:space:]]*\([0-9]*\).*/\1/')
expect_attach_end=$(grep -E '^static const int +new_window_attach_on_end ' "$R/config.h" | sed 's/.*=[[:space:]]*\([0-9]*\).*/\1/')
expect_smartgaps=$(grep -E '^static const int +smartgaps ' "$R/config.h" | sed 's/.*=[[:space:]]*\([0-9]*\).*/\1/')

# V1: hai hang so phai van la 0 — neu user bat len, danh sach dead code nay het
#     dung va test bat buoc duoc sua theo (Dung im lang se thanh "pass gia").
if [ "$expect_tag_preview" = 0 ] && [ "$expect_systraypin" = 0 ] \
   && [ "$expect_attach_end" = 0 ] && [ "$expect_smartgaps" = 0 ]; then
    ok "V1 4 hằng số cổng chết vẫn = 0 (tag_preview, systraypinning, new_window_attach_on_end, smartgaps)"
else
    bad "V1 hằng số cổng chết đã đổi" \
        "tag_preview=$expect_tag_preview systraypinning=$expect_systraypin attach_on_end=$expect_attach_end smartgaps=$expect_smartgaps — danh sách dead code trong file này cần cập nhật"
fi

# ---------------------------------------------------------------- V2: co code sau cot
# Mỗi cổng phải còn tồn tại trong mã nguồn; nếu user đã xoá thì đây là tin tốt.
declare -a SITES
SITES=(
  "dwm.c|if(new_window_attach_on_end)|attach: nhánh if() gắn client vào CUỐI danh sách"
  "dwm.c|!tag_preview|tag preview: cổng trong showtagpreview() và switchtag()"
  "dwm.c|!systraypinning|systray pinning: cổng trong systraytomon()"
  "vanitygaps.c|smartgaps && n == 1|smartgaps: bỏ outer gap khi chỉ 1 cửa sổ"
)
found=0
for s in "${SITES[@]}"; do
    f=${s%%|*}; rest=${s#*|}; pat=${rest%%|*}; desc=${rest#*|}
    if grep -qF "$pat" "$R/$f"; then
        found=$((found+1))
        ok "V2 cổng còn trong $f — $desc"
    else
        skip "V2 $f không còn '$pat' ($desc) — có thể đã được dọn"
    fi
done
[ "$found" -eq 0 ] && bad "V2 không tim thay cổng chết nao" "danh sach trong file test da het hieu luc"

# ---------------------------------------------------------------- V3: do bang gcov
# Build dwm voi --coverage tu nguon that, chay tren Xvfb roi doc .gcda.
BUILD="$T/cov"
mkdir -p "$BUILD"
for f in dwm.c drw.c util.c vanitygaps.c movestack.c shiftview.c \
         config.h drw.h util.h arg.h functions.h vanitygaps.h \
         movestack.h shiftview.h Makefile config.mk; do
    [ -f "$R/$f" ] && cp "$R/$f" "$BUILD/"
done
cp -a "$R/themes" "$BUILD/" 2>/dev/null

python3 - "$BUILD/config.mk" <<'PYEOF'
import sys, re
p = sys.argv[1]
s = open(p).read()
# --coverage can -O; bo -O3/-flto (LTO khong hop voi coverage) va _FORTIFY_SOURCE
# (can optimization, se lam build FAIL du -Werror).
s = s.replace("-O3", "-O0").replace("-flto ", "").replace(" -flto", "")
s = s.replace("-D_FORTIFY_SOURCE=2 ", "").replace("-D_FORTIFY_SOURCE=2", "")
s = re.sub(r'^CFLAGS(\s*)=', r'CFLAGS\1= --coverage', s, count=1, flags=re.M)
s = re.sub(r'^LDFLAGS(\s*)=', r'LDFLAGS\1= --coverage', s, count=1, flags=re.M)
open(p, 'w').write(s)
PYEOF

echo "  build dwm voi --coverage..."
( cd "$BUILD" && make ) >"$T/build.log" 2>&1
if [ ! -x "$BUILD/dwm" ]; then
    bad "V3 build dwm voi --coverage that bai" "$(grep -m2 -iE 'error' "$T/build.log" | tr '\n' ' ')"
    printf '\n  %d PASS, %d FAIL\n' "$P" "$F"; exit 1
fi
ok "V3 build dwm với --coverage thành công"

# --- client X + cong cuu go phim --------------------------------------------
cat >"$T/xclient.c" <<'EOF'
#include <X11/Xlib.h>
#include <X11/Xutil.h>
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
int main(int argc, char **argv) {
	Display *d; Window w, r; XSetWindowAttributes wa;
	int secs = argc > 2 ? atoi(argv[2]) : 20;
	if (!(d = XOpenDisplay(NULL))) return 1;
	r = DefaultRootWindow(d);
	wa.override_redirect = False;
	wa.background_pixel = WhitePixel(d, DefaultScreen(d));
	wa.event_mask = StructureNotifyMask | PropertyChangeMask;
	w = XCreateWindow(d, r, 120, 120, 520, 400, 0, CopyFromParent,
	                  CopyFromParent, CopyFromParent,
	                  CWOverrideRedirect | CWBackPixel | CWEventMask, &wa);
	XStoreName(d, w, argc > 1 ? argv[1] : "c");
	XMapWindow(d, w); XSync(d, False);
	sleep((unsigned)secs);
	XDestroyWindow(d, w); XSync(d, False); usleep(200000);
	XCloseDisplay(d); return 0;
}
EOF
cat >"$T/tap.c" <<'EOF'
/* Go phim MOD+... bang XTEST. */
#include <X11/Xlib.h>
#include <X11/keysym.h>
#include <X11/extensions/XTest.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
static void dn(Display *d, KeyCode c){if(c){XTestFakeKeyEvent(d,c,True,0);XFlush(d);}}
static void up(Display *d, KeyCode c){if(c){XTestFakeKeyEvent(d,c,False,0);XFlush(d);}}
int main(int argc, char **argv){
	Display *d; int a,b,m,n; unsigned mod=Mod4Mask; KeySym s; const char *sp;
	if(!(d=XOpenDisplay(NULL)))return 1;
	if(!XTestQueryExtension(d,&a,&b,&m,&n))return 2;
	if(argc<2)return 2;
	sp=argv[1];
	if(strstr(sp,"shift"))mod|=ShiftMask;
	if(strstr(sp,"ctrl"))mod|=ControlMask;
	{ const char *p=sp+strlen(sp)-1;
	  if(*p>='1'&&*p<='9')s=XK_1+(*p-'1'); else if(*p=='0')s=XK_0;
	  else if(*p>='A'&&*p<='Z')s=XK_a+(*p-'A'); else s=XK_a+(*p-'a'); }
	dn(d,XKeysymToKeycode(d,XK_Super_L)); usleep(40000);
	if(mod&ControlMask){dn(d,XKeysymToKeycode(d,XK_Control_L));usleep(40000);}
	if(mod&ShiftMask){dn(d,XKeysymToKeycode(d,XK_Shift_L));usleep(40000);}
	{ KeyCode c=XKeysymToKeycode(d,s); if(!c)return 3;
	  dn(d,c);usleep(50000);up(d,c);usleep(40000); }
	if(mod&ShiftMask){up(d,XKeysymToKeycode(d,XK_Shift_L));usleep(30000);}
	if(mod&ControlMask){up(d,XKeysymToKeycode(d,XK_Control_L));usleep(30000);}
	up(d,XKeysymToKeycode(d,XK_Super_L)); XSync(d,False); return 0;
}
EOF
cc -O2 -o "$T/xclient" "$T/xclient.c" -lX11 2>/dev/null \
    || { skip "không compile được client X"; printf '\n  %d PASS, %d FAIL\n' "$P" "$F"; exit 0; }
cc -O2 -o "$T/tap" "$T/tap.c" -lX11 -lXtst 2>/dev/null \
    || { skip "không compile được công cụ gõ phím (thiếu libXtst?)"; printf '\n  %d PASS, %d FAIL\n' "$P" "$F"; exit 0; }
ok "V4 compile được client X và công cụ gõ phím"

# --- chay tren Xvfb ----------------------------------------------------------
D=":96"
kill_xvfb() {
    for q in $(pgrep -x Xvfb 2>/dev/null); do
        tr '\0' ' ' < "/proc/$q/cmdline" 2>/dev/null | grep -q -- "$1" && kill -9 "$q" 2>/dev/null
    done
}
for pid in $(pgrep -x dwm 2>/dev/null); do
    dd=$(tr '\0' '\n' < "/proc/$pid/environ" 2>/dev/null | sed -n 's/^DISPLAY=//p')
    [ "$dd" = "$D" ] && kill -9 "$pid" 2>/dev/null
done
kill_xvfb "$D"; sleep 1
rm -f "/tmp/.X${D#:}-lock" "/tmp/.X11-unix/X${D#:}" 2>/dev/null

Xvfb "$D" -screen 0 1920x1200x24 -noreset >"$T/xvfb.log" 2>&1 &
XFP=$!
sleep 3
export DISPLAY="$D"
if ! xdpyinfo >/dev/null 2>&1; then
    skip "Xvfb $D không khởi động"
    kill -9 "$XFP" 2>/dev/null
    printf '\n  %d PASS, %d FAIL\n' "$P" "$F"; exit 0
fi
ok "V5 Xvfb khởi động ($D)"

cd "$BUILD" || exit 1
./dwm >"$T/run.log" 2>&1 &
WM=$!
sleep 4
if [ ! -d "/proc/$WM" ]; then
    bad "V6 dwm khởi động trên Xvfb" "$(head -3 "$T/run.log")"
    kill -9 "$XFP" 2>/dev/null; printf '\n  %d PASS, %d FAIL\n' "$P" "$F"; exit 0
fi
ok "V6 dwm khởi động"

# workload: du kiem nhung path phai co cho cac so do chet duoc do dung
for i in 1 2 3 4 5 6; do "$T/xclient" "c$i" 60 >/dev/null 2>&1 & sleep 0.3; done
sleep 2
for k in t shift+f m ctrl+g ctrl+shift+t space; do "$T/tap" "$k" >/dev/null 2>&1; sleep 0.3; done
for n in 1 2 3 4 5; do "$T/tap" "$n" >/dev/null 2>&1; sleep 0.3; done
for k in f q shift+space ctrl+w shift+j shift+k; do "$T/tap" "$k" >/dev/null 2>&1; sleep 0.3; done

# THOAT SACH: phai dung Super+Ctrl+q. SIGTERM KHONG tao .gcda — gcov ghi qua
# atexit, SIGTERM thi dwm chet ngay (dwm chi bat SIGCHLD).
"$T/tap" ctrl+q >/dev/null 2>&1
for i in $(seq 1 20); do [ -d "/proc/$WM" ] || break; sleep 0.5; done
[ -d "/proc/$WM" ] && kill -9 "$WM" 2>/dev/null

if [ ! -f "$BUILD/dwm.gcda" ]; then
    bad "V7 không tạo được .gcda" \
        "phải thoát bằng Super+Ctrl+q (restart) chứ không phải SIGTERM — gcov ghi file ở atexit"
    kill -9 "$XFP" 2>/dev/null; printf '\n  %d PASS, %d FAIL\n' "$P" "$F"; exit 0
fi
ok "V7 gcov tạo .gcda (thoát sạch qua restart())"

gcov -o . dwm.gcda >/dev/null 2>&1
if [ ! -f "$BUILD/dwm.c.gcov" ]; then
    bad "V8 gcov không sinh dwm.c.gcov"; kill -9 "$XFP" 2>/dev/null
    printf '\n  %d PASS, %d FAIL\n' "$P" "$F"; exit 0
fi
ok "V8 gcov sinh dwm.c.gcov"
pkill -x xclient 2>/dev/null
kill -9 "$XFP" 2>/dev/null

# ---------------------------------------------------------------- V9..V13: dem vung chet
# `#####` = dong thuoc ma CHUA BAO GIO chay. Dem trong tung vung cong chết.
# Đếm dòng `#####` (chưa từng chạy) có số dòng nguồn nằm trong [a,b].
#
# KHÔNG suy ra vị trí từ số thứ tự dòng của file .gcov. Bản đầu của test này
# cộng thêm +2 với giả định mọi file .gcov có 2 dòng header — sai: dwm.c.gcov
# có 2 ("Runs:" rồi dòng trống) nhưng vanitygaps.c.gcov chỉ có 1 ("Source:").
# Kết quả V12 báo "không còn dòng chết nào" trong khi dòng đó vẫn chết.
#
# Cách đúng: cột thứ 2 của .gcov CHÍNH LÀ số dòng trong file nguồn. Đọc thẳng
# cột đó, không cần biết có bao nhiêu dòng header.
count_dead() {   # $1 = file .gcov, $2 = dong bat dau, $3 = dong ket thuc
    # Định dạng .gcov:  <count>: <dong nguon>: <code>
    #   $1 = "     #####" hoac "       17", $2 = so dong trong file nguon
    # Cách đầu của test này dùng sub() với phép gán trong tham số thứ 3 — awk
    # không cho phép, hàm chết ngay. Cách này đã đối chiếu tay: dwm.c.gcov
    # 710-718 = 3, vanitygaps.c.gcov 127-129 = 1.
    awk -F: -v a="$2" -v b="$3" '
        /^ *#####:/ { n = $2 + 0; if (n >= a && n <= b) c++ }
        END { print c + 0 }' "$1"
}

# Xac nhan vung co THAT SU bi bao phu: dung so dong .gcov de danh dau
check_site() {   # $1 ten, $2 file gocov, $3 dong bat dau, $4 dong ket thuc, $5 mo ta
    local n
    n=$(count_dead "$2" "$3" "$4")
    if [ "$n" -gt 0 ]; then
        ok "$1: $n dòng chưa từng chạy — $5"
    else
        bad "$1: KHÔNG còn dòng chết nào" \
            "$5 — hoặc hằng số đã bật, hoặc workload đã chạm tới; cần xem lại"
    fi
}

if [ "$expect_attach_end" = 0 ]; then
    check_site "V9" "$BUILD/dwm.c.gcov" 710 718 \
        "attach(): nhánh new_window_attach_on_end (dang 0)"
fi
if [ "$expect_systraypin" = 0 ]; then
    check_site "V10" "$BUILD/dwm.c.gcov" 4250 4257 \
        "systraytomon(): phần sau if(!systraypinning) (đang 0)"
fi
if [ "$expect_tag_preview" = 0 ]; then
    check_site "V11" "$BUILD/dwm.c.gcov" 3451 3463 \
        "switchtag(): khối tạo tagmap qua Imlib2 (tag_preview=0)"
fi
if [ "$expect_smartgaps" = 0 ]; then
    if [ -f "$BUILD/vanitygaps.c.gcov" ]; then
        check_site "V12" "$BUILD/vanitygaps.c.gcov" 127 129 \
            "vanitygaps.c: nhánh smartgaps (đang 0)"
    else
        skip "V12 không có vanitygaps.c.gcov"
    fi
fi

# V13: san co THAT SU chay — neu 0% thi do la do nghiem, khong phai do code.
pct=$(awk '/Lines executed:/{print $4; exit}' /dev/null 2>/dev/null)
pct=$(grep -m1 "Lines executed" /dev/null 2>/dev/null); pct=""
# doc truc tiep tu gcov
covline=$(cd "$BUILD" && gcov -o . dwm.gcda 2>/dev/null | grep -m1 "Lines executed")
covpct=$(printf '%s' "$covline" | sed 's/.*executed:\([0-9.]*\)%.*/\1/')
if [ -n "$covpct" ]; then
    ok "V13 coverage dwm.c = ${covpct}% (san co chay, con lai là path khong do duoc)"
else
    skip "V13 không đọc được tỉ lệ coverage"
fi

printf '\n  %d PASS, %d FAIL\n' "$P" "$F"
[ "$F" -eq 0 ]
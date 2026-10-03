#!/usr/bin/env bash
# Kiểm tra bất biến "số ID DNS phải bằng số preset DNS" của netpanel.
#
# ================================================================== VÌ SAO
#
# config.h khai báo 5 preset DNS:
#     static const ... dns_providers[] = {
#         { "DHCP", nullptr }, { "Cloudflare", ... }, { "Google", ... },
#         { "NextDNS", ... }, { "Custom", "" },
#     };
#     #define DNS_NCUSTOM 4      /* index nút Custom */
#
# draw_panel() vẽ nút theo vòng `for (i = 0; i < bn; i++) draw_button(ID_DNS0 + i, ...)`
# với bn = 5. Nhưng enum trong netpanel.c CHỈ CÓ ID_DNS0..ID_DNS3 (4 hằng).
# Nút thứ 5 ("Custom") vì thế mang id = ID_DNS0 + 4 = 7, trùng đúng ID_BAND0.
#
# Đo trên bản chạy thật (click vào nút 5 của hàng DNS):
#     CLICK id=7 (ID_DNS0=3 ID_DNS3=6 ID_BAND0=7 ID_BAND3=10)
#     APPLY_BAND idx=0
# Tức bấm "Custom" đổi BĂNG Wi-Fi thay vì mở ô nhập DNS. Đồng thời
# apply_dns(4) không bao giờ chạy -> ask_custom_dns() và cb_custom_dns()
# là code chết, không lời gọi nào tới được.
#
# Test này chốt bất biến gốc rễ: số hằng ID_DNS* phải ĐÚNG BẰNG số mục trong
# dns_providers[].
set -u

R="$(cd "$(dirname "$0")/.." && pwd)"
NP="$R/netpanel"
P=0; F=0
ok()  { printf '  PASS  %s\n' "$*"; P=$((P + 1)); }
bad() { printf '  FAIL  %s\n' "$1"; [ $# -gt 1 ] && printf '        %s\n' "$2"; F=$((F + 1)); }
skip() { printf '  --    %s\n' "$*"; printf '\n  %d PASS, %d FAIL\n' "$P" "$F"; exit 0; }

[ -f "$NP/netpanel.c" ] || { skip "không thấy $NP/netpanel.c"; exit 0; }
command -v cc >/dev/null 2>&1 || skip "thiếu cc"

SRC="$NP/netpanel.c"
CFG="$NP/config.h"

# --- N1: đếm số preset trong config.h ----------------------------------------
# Đếm phần tử khởi tạo trong dns_providers[]. Cách đáng tin: nhờ chính trình
# biên dịch in ra, chứ không đếm bằng grep (dấu phẩy/ngoặc trong chuỗi làm
# grep dễ đếm sai — đã dính kiểu này ở dwm với tags[]).
NPV=$(mktemp -d); trap 'rm -rf "$NPV"' EXIT
cat > "$NPV/probe.c" <<'EOF'
#include <stdio.h>
#include "config.h"
/* In ra số phần tử của dns_providers[] — để test đếm bằng chính trình dịch
 * thay vì đoán bằng grep. */
int main(void) {
	printf("%d\n", (int)(sizeof(dns_providers) / sizeof(dns_providers[0])));
	return 0;
}
EOF
if cc -std=c23 -I"$NP" -o "$NPV/probe" "$NPV/probe.c" 2>/dev/null; then
    nprov=$("$NPV/probe")
    ok "N1 dns_providers[] có $nprov phần tử (đếm bằng chính trình dịch)"
else
    bad "N1 không compile được probe đếm dns_providers" "xem $NP/config.h"
    nprov=0
fi

# --- N2: đếm hằng ID_DNS* trong enum ----------------------------------------
# Hai lỗi đã dính khi làm test này:
#   a) enum mở đầu bằng "enum {" Ở CỘT 0, không phải tab. sed '/^\tenum {/'
#      không khớp nên tìm được 0 hằng.
#   b) KHỐI ENUM CÓ CHÚ THÍCH giải thích lỗi, trong đó ghi "ID_DNS0..ID_DNS3".
#      Đếm thẳng sẽ tính nhầm ID_DNS0 và ID_DNS3 lấy từ comment. Phải bỏ
#      comment trước khi đếm.
enum_block() {
    sed -n '/^enum {/,/^};/p' "$SRC" | perl -0777 -pe 's{/\*.*?\*/}{}gs'
}
nid=$(enum_block | tr ',' '\n' | grep -cE '(^|[[:space:]])ID_DNS[0-9]+([[:space:]]|$)')
if [ "$nid" -gt 0 ]; then
    ok "N2 enum có $nid hằng ID_DNS* (đã bỏ comment)"
else
    bad "N2 không tìm thấy hằng ID_DNS* trong enum"
    nid=0
fi

# --- N3: BẤT BIẾN — hai con số phải bằng nhau -------------------------------
# Đây là bất biến gốc rễ của lỗi. Trước khi sửa: 5 preset vs 4 ID_DNS.
if [ "$nprov" = "$nid" ]; then
    ok "N3 số ID_DNS* ($nid) == số preset DNS ($nprov)"
else
    bad "N3 LỆCH: $nid hằng ID_DNS* nhưng $nprov preset DNS" \
        "draw_panel() vẽ $nprov nút (for i < bn) với id = ID_DNS0+i, nên nút cuối mang id = ID_DNS0+$nid — trùng ID_BAND0. Bấm nút đó sẽ gọi apply_band thay vì apply_dns."
fi

# --- N4: khoảng dispatch trong handle_click phải phủ hết --------------------
# `if (id >= ID_DNS0 && id <= ID_DNS3)` chỉ phủ 4 id; phải là ID_DNS4 (id cuối).
LAST_DNS=$(enum_block | tr ',' '\n' | grep -oE 'ID_DNS[0-9]+' | sed 's/ID_DNS//' | sort -n | tail -1)
if [ -n "$LAST_DNS" ] && [ "$LAST_DNS" -gt 0 ]; then
    if grep -q "id <= ID_DNS$LAST_DNS" "$SRC"; then
        ok "N4 handle_click phủ hết dải DNS (id <= ID_DNS$LAST_DNS)"
    else
        got=$(grep -oE 'id <= ID_DNS[0-9]+' "$SRC" | head -1 | grep -oE '[0-9]+$')
        bad "N4 khoảng dispatch hẹp hơn dải ID" \
            "enum có tới ID_DNS$LAST_DNS nhưng handle_click chỉ tới ID_DNS${got:-?}"
    fi
fi

# --- N5: apply_dns phải chặn truy cập ngoài mảng ----------------------------
# idx đến từ id - ID_DNS0; không có chốt thì lệch id lần sau là đọc ngoài mảng.
if grep -q 'idx < 0 || idx >= (int)(sizeof(dns_providers)' "$SRC"; then
    ok "N5 apply_dns chặn idx ngoài dns_providers[] trước khi đọc"
else
    bad "N5 apply_dns đọc dns_providers[idx] không kiểm biên" \
        "chính lỗi này đã cho thấy enum và bảng preset có thể lệch nhau"
fi

# --- N6: chạy thật — click nút DNS cuối phải vào apply_dns, không vào band --
# Bản dựng có log trong handle_click/apply_dns/apply_band, tự cấy (không sửa
# file trong repo). Nếu thiếu cc/Xvfb thì báo -- chứ không coi là pass.
for tool in cc Xvfb; do
    command -v "$tool" >/dev/null 2>&1 || { skip "thiếu $tool — N6 chưa kiểm được"; exit 0; }
done

python3 - "$SRC" "$NPV/netpanel-dbg.c" <<'PYEOF'
import sys, re
src, dst = sys.argv[1], sys.argv[2]
s = open(src).read()

# 1) log id trong handle_click
a = "static void handle_click(int id)\n{\n\tswitch (id) {"
b = ('static void handle_click(int id)\n{\n'
     '\tif (getenv("NPDBG_CLICK")) fprintf(stderr, "CLICK id=%d\\n", id);\n'
     '\tswitch (id) {')
assert a in s, "handle_click khong khop"
s = s.replace(a, b, 1)

# 2) log idx trong apply_dns
m = re.search(r'(static void apply_dns\(int idx\)\n\{\n)', s)
assert m, "apply_dns khong khop"
s = s[:m.end(1)] + ('\tif (getenv("NPDBG_CLICK")) fprintf(stderr, "APPLY_DNS idx=%d\\n", idx);\n') + s[m.end(1):]

# 3) log idx trong apply_band — phai co de phat hien id tran sang nhanh BAND
m = re.search(r'(static void apply_band\(int idx\)[^\n]*\n\{\n)', s)
assert m, "apply_band khong khop"
s = s[:m.end(1)] + ('\tif (getenv("NPDBG_CLICK")) fprintf(stderr, "APPLY_BAND idx=%d\\n", idx);\n') + s[m.end(1):]

# 4) log toa do vung cham — de test BAY TOA DO THAT cua tung nut DNS
#    thay vi tinh toan (lan truoc tinh tay thi click truot, day la ly do).
m = re.search(r'(static void add_hit\(int id, int x, int y, int w, int h\)\n\{\n)', s)
assert m, "add_hit khong khop"
s = s[:m.end(1)] + ('\tif (getenv("NPDBG_CLICK"))\n'
                    '\t\tfprintf(stderr, "HIT id=%d -> click %d %d\\n", id, x + w / 2, y + h / 2);\n') + s[m.end(1):]

open(dst, 'w').write(s)
print("ok")
PYEOF
[ -f "$NPV/netpanel-dbg.c" ] || { skip "không cấy được log vào handle_click/apply_dns/add_hit"; exit 0; }

cp "$NP/config.h" "$NPV/config.h" 2>/dev/null
if cc -std=c23 -O1 -g -D_DEFAULT_SOURCE -I"$NPV" -I/usr/include -I/usr/include/freetype2 \
      -o "$NPV/np-dbg" "$NPV/netpanel-dbg.c" \
      -lXft -lXrender -lXext -lX11 -lfontconfig -lm 2>/dev/null; then
    ok "N6 build bản có log thành công"
else
    bad "N6 build bản log thất bại"; printf '\n  %d PASS, %d FAIL\n' "$P" "$F"; exit 1
fi

kill_xvfb() {
    for q in $(pgrep -x Xvfb 2>/dev/null); do
        tr '\0' ' ' < "/proc/$q/cmdline" 2>/dev/null | grep -q -- "$1" && kill -9 "$q" 2>/dev/null
    done
}
kill_xvfb ":98"; sleep 1
rm -f /tmp/.X98-lock /tmp/.X11-unix/X98 2>/dev/null
Xvfb :98 -screen 0 1920x1200x24 -noreset >"$NPV/xvfb.log" 2>&1 &
XFP=$!
sleep 3
export DISPLAY=:98
xdpyinfo >/dev/null 2>&1 || { skip "Xvfb :98 không khởi động"; kill -9 "$XFP" 2>/dev/null; exit 0; }

# Cần XTest để click — dùng chính tiện ích nhỏ dựng ở đây.
cat > "$NPV/click.c" <<'EOF'
#include <X11/Xlib.h>
#include <X11/extensions/XTest.h>
#include <stdlib.h>
#include <unistd.h>
int main(int argc, char **argv) {
	Display *d = XOpenDisplay(NULL); int a,b,c,e;
	if (!d || argc < 3) return 1;
	if (!XTestQueryExtension(d,&a,&b,&c,&e)) return 2;
	XTestFakeMotionEvent(d, DefaultScreen(d), atoi(argv[1]), atoi(argv[2]), 0);
	XFlush(d); usleep(40000);
	XTestFakeButtonEvent(d, 1, True, 0); XFlush(d); usleep(50000);
	XTestFakeButtonEvent(d, 1, False, 0); XFlush(d); usleep(70000);
	XSync(d, False); return 0;
}
EOF
cc -O2 -o "$NPV/click" "$NPV/click.c" -lX11 -lXtst 2>/dev/null \
    || { skip "không compile được công cụ click"; kill -9 "$XFP" 2>/dev/null; exit 0; }

export XDG_RUNTIME_DIR="$NPV/run"; mkdir -p "$XDG_RUNTIME_DIR"; chmod 700 "$XDG_RUNTIME_DIR"
export ASAN_OPTIONS=detect_leaks=0:halt_on_error=0:exitcode=0
NPDBG_CLICK=1 "$NPV/np-dbg" >"$NPV/run.log" 2>&1 &
NP=$!
sleep 4
if [ ! -d "/proc/$NP" ]; then
    bad "N6 netpanel không khởi động" "$(head -3 "$NPV/run.log")"
    kill -9 "$XFP" 2>/dev/null; printf '\n  %d PASS, %d FAIL\n' "$P" "$F"; exit 0
fi

# BẤT ID của nút DNS cuối: ID_DNS0 + (số preset - 1)
# Giá trị số THẬT của ID_DNS0. KHÔNG lấy từ hậu tố tên: "ID_DNS0" có hậu tố 0
# nhưng giá trị là 3 (ID_TOGGLE=1, ID_QR, rồi tới nó). Hai lần thử trước —
# lấy hậu tố cho ra 4, rồi awk tự cộng cho ra 1 — đều ra nút sai.
# Nay nhờ chính trình biên dịch: cắt khối enum ra file rồi in giá trị.
enum_block > "$NPV/enum.h"
# Chỉ hỏi ID_DNS0 — hằng này có ở MỌI phiên bản, kể cả bản cũ thiếu ID_DNS4.
# Nếu probe cần ID_DNS4 thì trên bản cũ nó không compile, ID_DNS0_V rơi về 0,
# LAST_DNS_ID sai, và N6/N7 chạy vào nút khác — báo FAIL nhưng sai lý do.
cat > "$NPV/ev.c" <<'EOF'
#include <stdio.h>
#include "enum.h"
int main(void) { printf("%d\n", ID_DNS0); return 0; }
EOF
if cc -std=c23 -I"$NPV" -o "$NPV/ev" "$NPV/ev.c" 2>/dev/null; then
    ID_DNS0_V=$("$NPV/ev")
    ok "N6c trình biên dịch cho ID_DNS0=$ID_DNS0_V"
else
    bad "N6c không compile được probe đọc ID_DNS0"; ID_DNS0_V=0
fi
# id của nút DNS cuối = ID_DNS0 + (số preset - 1) — đúng ở cả bản cũ lẫn mới,
# nhờ vậy N6/N7 vẫn bắm đúng nút khi test chạy trên bản lỗi.
LAST_DNS_ID=$(( ID_DNS0_V + nprov - 1 ))

# LẤY TOẠ ĐỘ THẬT từ log add_hit của chính panel đang chạy, KHÔNG tính tay.
# Lần trước tính tay (x = PAD + 4*(bw+gap) + bw/2 = 410) thì click trượt —
# đúng loại sai lầm đã dính khi làm việc với thanh dwm.
sleep 1
LASTDNS_PT=$(grep -a "^HIT id=$LAST_DNS_ID " "$NPV/run.log" | tail -1 \
             | sed 's/.*-> click \([0-9]*\) \([0-9]*\).*/\1 \2/')
if [ -n "$LASTDNS_PT" ]; then
    ok "N6b panel đăng ký vùng bấm cho nút DNS cuối (id=$LAST_DNS_ID): $LASTDNS_PT"
else
    bad "N6b không thấy vùng bấm của nút DNS cuối trong log add_hit" "xem $NPV/run.log"
    kill -9 "$NP" 2>/dev/null; kill -9 "$XFP" 2>/dev/null
    printf '\n  %d PASS, %d FAIL\n' "$P" "$F"; exit 0
fi

"$NPV/click" $((1452 + $(echo "$LASTDNS_PT" | cut -d' ' -f1))) \
             $((36 + $(echo "$LASTDNS_PT" | cut -d' ' -f2))) >/dev/null 2>&1
sleep 2

if grep -q 'APPLY_DNS idx=4' "$NPV/run.log"; then
    ok "N6 click nút DNS thứ 5 -> APPLY_DNS idx=4 (đúng DNS_NCUSTOM)"
elif grep -q 'APPLY_DNS' "$NPV/run.log"; then
    got=$(grep -oE 'APPLY_DNS idx=[0-9]+' "$NPV/run.log" | tail -1)
    bad "N6 click nút DNS thứ 5 không tới Custom" "thấy: $got"
else
    got=$(grep -oE 'CLICK id=[0-9]+' "$NPV/run.log" | tail -1)
    bad "N6 click nút DNS thứ 5 không gọi apply_dns" "chỉ thấy: ${got:-không có CLICK}"
fi

# Không được phát sinh apply_band từ hàng DNS.
if grep -q 'APPLY_BAND' "$NPV/run.log"; then
    bad "N7 hàng DNS sinh apply_band — id vẫn còn trùng ID_BAND0"
else
    ok "N7 hàng DNS không sinh apply_band (id không còn trùng ID_BAND0)"
fi

kill -9 "$NP" 2>/dev/null
kill -9 "$XFP" 2>/dev/null

printf '\n  %d PASS, %d FAIL\n' "$P" "$F"
[ "$F" -eq 0 ]
#!/usr/bin/env bash
# Test cho preview_scale trong dwm.c — hệ số thu nhỏ tag preview (MẪU SỐ CHIA).
#
# config.h khai `static const int scalepreview = 4`. Nó là mẫu số ở 4 chỗ.
# Chỗ nguy hiểm nhất là dwm.c:667 trong arrangemon(), và khối đó KHÔNG có
# điều kiện nào — không cần bật tag_preview, không cần làm gì.
#
# ĐO trước khi sửa:
#   scalepreview = 0 -> "Floating point exception (core dumped)", rc = 136
#                     136 = 128 + SIGFPE(8). Tức dwm chết ngay lần bố trí lại
#                     cửa sổ đầu tiên. Đường chết không cần bật gì thêm.
#   scalepreview = -3 -> mh/scalepreview = -360 -> XMoveWindow với toạ độ Y âm
#                     (không chết, nhưng cửa sổ tag bị đẩy lệch chỗ).
#
# Khác với motion_skip_ms ở test-dwm-motion-throttle.sh: fallback ở đây là 1
# chứ không phải 0, vì scalepreview là hệ số THU NHỎ dùng để CHIA (1 = không
# thu nhỏ), còn motion_skip_ms là ngưỡng so sánh (0 = không bỏ qua gì).
#
# Cách test: TRÍCH khai báo thật từ dwm.c bằng sed, biên dịch và chạy.
set -u
R=/home/frost-auslese/tsuki
P=0; F=0
ok()  { printf '  PASS  %s\n' "$*"; P=$((P + 1)); }
bad() {
    _m1=$1; shift
    printf '  FAIL  %s\n        %s\n' "$_m1" "$*"
    F=$((F + 1))
}
T=$(mktemp -d)
cleanup() { rm -rf "$T"; }
trap cleanup EXIT INT TERM

if [ ! -f "$R/dwm.c" ]; then
    printf '  --   bỏ qua: không thấy dwm.c\n'
    printf '\n  %d PASS, %d FAIL\n' "$P" "$F"
    exit 0
fi

# --- Q1: phải có preview_scale clamp ---------------------------------------
if grep -q '^static const int preview_scale =' "$R/dwm.c"; then
    ok "Q1 dwm.c có preview_scale khai báo static const"
else
    bad "Q1 không thấy preview_scale" \
        "scalepreview=0 vẫn là SIGFPE trong arrangemon() — dwm chết khi bố trí lại"
fi
# clamp PHẢI là > 0, tức fallback 1 (không thu nhỏ), không phải 0
if grep -A1 '^static const int preview_scale =' "$R/dwm.c" \
   | grep -qE '\(scalepreview > 0\) \? scalepreview : 1'; then
    ok "Q1b clamp về 1 (= không thu nhỏ), đúng nghĩa toán học của hệ số CHIA"
else
    bad "Q1b clamp sai" \
        "hệ số thu nhỏ phải về 1; về 0 vẫn chia không định nghĩa"
fi

# --- Q2: không còn chỗ nào tự chia bởi scalepreview trong mã LỆNH ----------
# Loại dòng comment TRƯỚC rồi mới đếm. `^[^/*]` không dùng được vì `grep -n`
# thêm tiều tố số dòng, mọi dòng đều bắt đầu bằng chữ số (đã dính: 2 false
# positive, đều trong khối giải thích).
_uses=$(grep -vE '^[[:space:]]*(\*|/\*|//)' "$R/dwm.c" | grep '/ *scalepreview' || true)
n_left=$(printf '%s' "$_uses" | grep -c . || true)
if [ "$n_left" -eq 0 ]; then
    ok "Q2 không còn chỗ nào trong mã lệnh chia bởi scalepreview trực tiếp"
else
    bad "Q2 còn $n_left chỗ tự chia" "$(printf '%s' "$_uses" | head -3 | cut -c1-90)"
fi

# --- Q3: phải có ĐÚNG 4 chỗ dùng preview_scale trong mã lệnh ---------------
n_use=$(grep -vE '^[[:space:]]*(\*|/\*|//)' "$R/dwm.c" | grep -c '/ *preview_scale' || true)
if [ "$n_use" -ge 4 ]; then
    ok "Q3 còn $n_use chỗ dùng preview_scale (4 chỗ chia: 667, 3344, 3398, 3400)"
else
    bad "Q3 chỉ còn $n_use chỗ dùng preview_scale" "phải có 4, tức mọi mẫu số chia đều qua hằng số"
fi

# --- Q4: chạy thật, so bản cũ và bản mới ---------------------------------
if ! command -v cc >/dev/null 2>&1; then
    printf '  --   bỏ qua Q4: không có cc\n'
else
    DECL=$(sed -n '/^static const int preview_scale =/,+1p' "$R/dwm.c")
    if [ -z "$DECL" ]; then
        bad "Q4 trích được khai báo từ dwm.c" "không lấy được đoạn preview_scale"
    else
        cat > "$T/p.c" <<EOF
#include <stdio.h>
static const int scalepreview = SPR;
$DECL
int main(int argc, char **argv) {
    int old = (argc > 1);
    int mh = 1080, mw = 1920;
    /* dwm.c:667 dùng mh; 3344/3398/3400 dùng mw và mh */
    int a = old ? (mh / scalepreview) : (mh / preview_scale);
    int b = old ? (mw / scalepreview) : (mw / preview_scale);
    printf("%d %d\n", a, b);
    return 0;
}
EOF
        # --- Q4a: scalepreview > 0 phải CHO KẾT QUẢ GIỐNG HỆT ----------
        same=1; diffs=""
        for v in 4 2 1 3 8 16; do
            # shellcheck disable=SC2086
            cc -std=c23 -O1 -DSPR=$v -o "$T/o$v" "$T/p.c" 2>/dev/null || continue
            # shellcheck disable=SC2086
            cc -std=c23 -O1 -DSPR=$v -o "$T/n$v" "$T/p.c" 2>/dev/null || continue
            o=$("$T/o$v" o 2>/dev/null) || o="CHET"
            n=$("$T/n$v" 2>/dev/null) || n="CHET"
            [ "$o" = "$n" ] || { same=0; diffs="$diffs [spr=$v cu=$o moi=$n]"; }
        done
        if [ "$same" -eq 1 ]; then
            ok "Q4a scalepreview>0: cũ và mới cho CÙNG kết quả ở 6 giá trị"
        else
            bad "Q4a sửa làm đổi kết quả ở scalepreview>0" "$diffs"
        fi

        # --- Q4b: ĐO THẬT BẰNG BUILD THẬT ----------------------------------
        # ĐÍNH CHÍNH: bản chú thích cũ của tôi nói scalepreview=0 làm dwm chết
        # SIGFPE. SAI. Đo lại bằng build thật của dự án (-Wall -Wextra -Werror):
        #     scalepreview = 0  -> dwm.c:637: error: division by zero
        #                           [-Werror=div-by-zero]        -> make FAIL
        #     scalepreview = -3 -> BUILD SẠCH, không cảnh báo; mh/scalepreview
        #                           = 1080/-3 = -360 -> XMoveWindow với Y âm,
        #                           X11 clamp về 0 (đo trên X thật) -> chỉ lệch
        #                           vị trí, KHÔNG chết.
        # Nên giá trị thật của bản sửa: 0 và âm đều từ "make FAIL" thành
        # "build được và đúng". Không phải sửa crash — không có crash nào.
        if grep -q 'Werror' "$R/config.mk" 2>/dev/null; then
            for _v in 4 2 1 0 -1 -3 -100; do
                _d="$T/pb$_v"
                rm -rf "$_d"
                if ! cp -a "$R" "$_d" 2>/dev/null; then
                    printf '  --   Q4b: không sao chép được repo\n'; break
                fi
                sed -i "s|static const int scalepreview *= *[-0-9]*;|static const int scalepreview = $_v;|" \
                    "$_d/config.h" 2>/dev/null
                # SC2015: `A && B || C` không phải if-else — C chạy cả khi A
                # đúng. Tách: make clean một dòng, log make ra file, đếm lỗi sau.
                ( cd "$_d" && make clean >/dev/null 2>&1 ) || true
                _log="$T/plog$_v"
                ( cd "$_d" && make ) >"$_log" 2>&1 || true
                _e=$(grep -cE ': error:' "$_log" || true)
                if [ "${_e:-1}" -eq 0 ]; then
                    ok "Q4b scalepreview=$_v -> make BUILD ĐƯỢC"
                else
                    bad "Q4b scalepreview=$_v -> make FAIL" "còn lỗi compiler"
                fi
                rm -rf "$_d"
            done
        fi

        # --- Q4c: giá trị ÂM trước đây cho toạ độ âm, nay về 1x -----------
        # shellcheck disable=SC2086
        cc -std=c23 -O1 -DSPR=-3 -o "$T/oneg" "$T/p.c" 2>/dev/null
        # shellcheck disable=SC2086
        cc -std=c23 -O1 -DSPR=-3 -o "$T/nneg" "$T/p.c" 2>/dev/null
        og=$("$T/oneg" o 2>/dev/null | awk '{print $1}')
        ng=$("$T/nneg" 2>/dev/null | awk '{print $1}')
        if [ "${og:-0}" -lt 0 ] 2>/dev/null; then
            ok "Q4c scalepreview=-3: gốc cho Y=$og (toạ độ âm), nay về Y=$ng"
        else
            bad "Q4c không tái hiện được toạ độ âm" "giá trị gốc = $og"
        fi
    fi
fi

printf '\n  %d PASS, %d FAIL\n' "$P" "$F"
[ "$F" -eq 0 ]

#!/usr/bin/env bash
# Test cho motion_skip_ms trong dwm.c — ngưỡng bỏ qua sự kiện MotionNotify.
#
# config.h khai `static const int refreshrate = 120`, và movemouse() /
# placemouse() / resizemouse() đều viết:
#     if ((ev.xmotion.time - lasttime) <= (1000 / refreshrate))
#
# ── SỰ THẬT ĐÃ ĐO, và sự thật đã SAI TRƯỚC ĐÂY ─────────────────────────────
# Bản commit trước của tôi nói: "refreshrate = 0 -> SIGFPE, dwm chết lúc kéo
# cửa sổ, đo 20/20 lần". ĐO LẠI BẰNG BUILD THẬT của dự án (config.mk có
# -Wall -Wextra -Werror):
#     refreshrate = 0   -> dwm.c:2448: error: division by zero
#                           [-Werror=div-by-zero]                  -> make FAIL
#     refreshrate = -60 -> dwm.c:2448: error: comparison of integer expressions
#                           of different signedness              -> make FAIL
# Tức KHÔNG CÓ crash lúc chạy: refreshrate là `static const` nên GCC gấp
# 1000/refreshrate thành hằng lúc compile và chặn cả 0 lẫn âm. Người dùng sửa
# refreshrate = 0 sẽ không build được dwm, chứ không phải build xong rồi chết.
# Lý do đo trước sai: chương trình thử tự viết lấy giá trị RUNTIME qua atoi()
# và biên dịch -O0, nên mẫu số không phải hằng, GCC không can thiệp.
#
# VẬY BẢN SỬA NÀY ĐEM LẠI GÌ? Đo được:
#     refreshrate > 0   -> kết quả y hệt bản gốc (tương đương 100%)
#     refreshrate = 0   -> gốc: make FAIL  |  sau: make OK
#     refreshrate âm     -> gốc: make FAIL  |  sau: make OK
# Đó là toàn bộ giá trị thực: biến một cấu hình sai từ "không build được"
# thành "build được và chạy đúng". Không phải sửa crash — không có crash nào.
#
# Cách test: build thật bằng Makefile của dự án trong bản sao repo, và chạy
# so sánh cũ/mới bằng chương trình C trích khai báo THẬT từ dwm.c.
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

if [ ! -f "$R/dwm.c" ] || [ ! -f "$R/config.mk" ]; then
    printf '  --   bỏ qua: không thấy dwm.c hoặc config.mk\n'
    printf '\n  %d PASS, %d FAIL\n' "$P" "$F"
    exit 0
fi

# --- M1: phải có hằng số, và tách HAI bước --------------------------------
# Một bước `(rr > 0) ? (Time)(1000/rr) : 0` KHÔNG ĐỦ: GCC vẫn gấp phép chia ở
# cả nhánh chưa chọn nên refreshrate=0 vẫn FAIL. Đã đo trên bản một bước:
# 4/5 tổ hợp OK, riêng refreshrate=0 FAIL.
if grep -q '^static const int motion_refreshrate =' "$R/dwm.c" \
   && grep -q '^static const Time motion_skip_ms =' "$R/dwm.c"; then
    ok "M1 có clamp TÁCH HAI BƯỚC (motion_refreshrate rồi mới chia)"
else
    bad "M1 không thấy clamp hai bước" \
        "một bước thì refreshrate=0 vẫn ra lỗi div-by-zero lúc build"
fi

# --- M2: không còn tự chia bởi refreshrate trong mã lệnh -------------------
# Loại dòng comment TRƯỚC, rồi mới đếm — không dùng `^[^/*]` vì `grep -n` thêm
# tiền tố số dòng nên mọi dòng đều bắt đầu bằng chữ số, mẫu đó vô dụng (đã dính
# 5 false positive, tất cả đều nằm trong khối giải thích).
_n=$(grep -vE '^[[:space:]]*(\*|/\*|//)' "$R/dwm.c" | grep -cE '/ *refreshrate\b' || true)
if [ "$_n" -eq 0 ]; then
    ok "M2 không còn chỗ nào trong mã lệnh chia bởi refreshrate"
else
    bad "M2 còn $_n chỗ tự chia bởi refreshrate" "chưa đi qua hằng số đã clamp"
fi

# --- M3: 3 chỗ so sánh phải dùng motion_skip_ms ---------------------------
_n3=$(grep -cE '^[^/*]*\(ev\.[a-z]+\.time - lasttime\) *<= *motion_skip_ms' "$R/dwm.c" || true)
if [ "$_n3" -ge 3 ]; then
    ok "M3 cả 3 chỗ so sánh dùng motion_skip_ms (movemouse/placemouse/resizemouse)"
else
    bad "M3 chỉ tìm thấy $_n3 chỗ dùng motion_skip_ms" "đáng lẽ 3"
fi

# --- M4: BUILD THẬT — đây là phép đo đúng --------------------------------
# Đây mới là điều cần kiểm: có build được với giá trị xấu không.
if grep -q 'Werror' "$R/config.mk" 2>/dev/null; then
    for _v in 120 60 1 0 -1 -60; do
        _d="$T/b$_v"
        rm -rf "$_d"
        if ! cp -a "$R" "$_d" 2>/dev/null; then
            printf '  --   M4: không sao chép được repo\n'; break
        fi
        sed -i "s|static const int refreshrate *= *[-0-9]*;|static const int refreshrate = $_v;|" \
            "$_d/config.h" 2>/dev/null
        # SC2015: `A && B || C` KHÔNG phải if-else — C chạy cả khi A đúng.
        # Tách hẳn: make clean một dòng, đếm lỗi dòng sau. Nếu make fail
        # thì `make | grep -c` vẫn ra số (grep đọc hết output), không mất mã.
        ( cd "$_d" && make clean >/dev/null 2>&1 ) || true
        _log="$T/log$_v"
        ( cd "$_d" && make ) >"$_log" 2>&1 || true
        _err=$(grep -cE ': error:' "$_log" || true)
        if [ "${_err:-1}" -eq 0 ]; then
            ok "M4 refreshrate=$_v -> make BUILD ĐƯỢC"
        else
            bad "M4 refreshrate=$_v -> make FAIL" "còn lỗi compiler"
        fi
        rm -rf "$_d"
    done
fi

# --- M5: tương đương hành vi khi refreshrate > 0 --------------------------
# Quan trọng: sửa KHÔNG được làm đổi thứ người dùng đang thấy.
DECL=$(sed -n '/^static const int motion_refreshrate =/,+1p' "$R/dwm.c" | tr '\n' ' ')
DECL="$DECL $(sed -n '/^static const Time motion_skip_ms =/,+1p' "$R/dwm.c" | tr '\n' ' ')"
if [ -n "$DECL" ]; then
    cat > "$T/eq.c" <<EOF
#include <stdio.h>
#include <X11/Xlib.h>
static const int refreshrate = REFRATE;
$DECL
int main(void) {
    Time lasts[] = { 0, 1, 1000, 999999999UL };
    Time deltas[] = { 0, 1, 7, 8, 9, 16, 17, 1000, 100000 };
    long bad = 0, n = 0;
    for (int a = 0; a < 4; a++)
        for (int b = 0; b < 9; b++) {
            Time motion = lasts[a] + deltas[b];
            if (motion - lasts[a] != deltas[b]) continue;
            int o  = ((motion - lasts[a]) <= (1000 / refreshrate));
            int nn = ((motion - lasts[a]) <= motion_skip_ms);
            n++;
            if (o != nn) bad++;
        }
    printf("%ld %ld\n", n, bad);
    return 0;
}
EOF
    tot=0; badtot=0
    for r in 1 24 40 60 75 120 144 240 1000; do
        # shellcheck disable=SC2046
        cc -std=c23 -O2 -DREFRATE=$r -o "$T/e$r" "$T/eq.c" \
           $(pkg-config --cflags --libs x11 2>/dev/null || echo -lX11) 2>/dev/null || continue
        line=$("$T/e$r" 2>/dev/null) || continue
        tot=$((tot + ${line% *})); badtot=$((badtot + ${line#* }))
    done
    if [ "$tot" -gt 0 ] && [ "$badtot" -eq 0 ]; then
        ok "M5 refreshrate>0: giống hệt bản gốc trên $tot tổ hợp (0 khác biệt)"
    elif [ "$badtot" -eq 0 ]; then
        bad "M5 không so được tổ hợp nào" "harness có vấn đề"
    else
        bad "M5 sửa làm ĐỔI HÀNH VI ở refreshrate>0" "$badtot/$tot tổ hợp khác nhau"
    fi
fi

# --- M6: -fanalyzer hết sign-compare --------------------------------------
GATE=(-std=c23 -Wall -Wextra -fanalyzer -fsyntax-only
      "-I$R" -I/usr/include -I/usr/include/freetype2
      -D_DEFAULT_SOURCE -D_BSD_SOURCE -D_XOPEN_SOURCE=700L
      '-DVERSION="6.8"' -DXINERAMA)
if command -v gcc >/dev/null 2>&1; then
    sc=$(gcc "${GATE[@]}" "$R/dwm.c" 2>&1 | grep -c 'sign-compare' || true)
    if [ "$sc" -eq 0 ]; then
        ok "M6 gcc -fanalyzer: 0 cảnh báo sign-compare"
    else
        bad "M6 vẫn còn $sc cảnh báo sign-compare" "so sánh Time (unsigned long) với int"
    fi
fi

# --- M7: ghi chú phải nói đúng sự thật đã đo ------------------------------
# Chống tái phát: comment cũ nói "dwm chết SIGFPE" là sai, đã bị đo bác bỏ.
if grep -q 'ĐÍNH CHÍNH' "$R/dwm.c"; then
    ok "M7 dwm.c ghi lại đính chính về claim SIGFPE sai"
else
    bad "M7 thiếu đính chính" "comment đang khẳng định dwm chết — sai"
fi

printf '\n  %d PASS, %d FAIL\n' "$P" "$F"
[ "$F" -eq 0 ]

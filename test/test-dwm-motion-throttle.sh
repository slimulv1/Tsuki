#!/usr/bin/env bash
# Test cho motion_skip_ms trong dwm.c — ngưỡng bỏ qua sự kiện MotionNotify.
#
# LÝ DO: config.h có `static const int refreshrate = 120`, và ba hàm
# movemouse() / placemouse() / resizemouse() viết:
#     if ((ev.xmotion.time - lasttime) <= (1000 / refreshrate))
# Nên đây là câu hỏi KHÔNG THỂ ĐO BẰNG ĐỌC CODE: 1000/0 là chia không định
# nghĩa, mà refreshrate nằm trong config.h — tức NGƯỜI DÙNG SỬA TAY được.
# Ai cũng có thể tưởng "0 = không giới hạn". Phải chạy thật mới biết.
#
# ĐÃ ĐO, không suy đoán:
#   refreshrate=0   -> "Floating point exception (core dumped)", rc=136
#                     136 = 128 + SIGFPE(8). Lặp 20/20 lần đều vậy.
#   refreshrate=-60 -> 1000/-60 = -16, so sánh với Time (unsigned long) thành
#                     số khổng lồ -> điều kiện LUÔN đúng -> continue LUÔN ->
#                     kéo cửa sổ KHÔNG di chuyểng được (đo: 0/1000 sự kiện).
#
# Cách test: TRÍCH khai báo thật từ dwm.c bằng sed, biên dịch và chạy thật.
# Không chép lại biểu thức — nếu không test sẽ "trôi" khỏi bản đang dùng.
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

if ! command -v cc >/dev/null 2>&1; then
    printf '  --   bỏ qua: không có cc\n'
    printf '\n  %d PASS, %d FAIL\n' "$P" "$F"
    exit 0
fi
if [ ! -f "$R/dwm.c" ]; then
    printf '  --   bỏ qua: không thấy dwm.c\n'
    printf '\n  %d PASS, %d FAIL\n' "$P" "$F"
    exit 0
fi

# --- M1: phải có khai báo ngưỡng, và là hằng số ---------------------------
if grep -q '^static const Time motion_skip_ms' "$R/dwm.c"; then
    ok "M1 dwm.c có motion_skip_ms khai báo static const (compile-time)"
else
    bad "M1 không thấy motion_skip_ms" \
        "dòng so sánh vẫn tự chia mỗi sự kiện chuột; refreshrate=0 sẽ SIGFPE"
fi

# --- M2: không còn chỗ nào TỰ chia ở nơi dùng ------------------------------
# (trừ dòng khai báo và dòng trong comment)
uses=$(grep -nE '^\s*(if|while).*ev\.[a-z]+\.time - lasttime' "$R/dwm.c" || true)
n_uses=$(printf '%s\n' "$uses" | grep -c . || true)
n_div=$(printf '%s\n' "$uses" | grep -c 'refreshrate' || true)
if [ "$n_uses" -ge 3 ]; then
    ok "M2 có $n_uses chỗ so sánh motion (movemouse/placemouse/resizemouse)"
else
    bad "M2 chỉ tìm thấy $n_uses chỗ so sánh" \
        "đáng lẽ 3; có thể dwm.c đã bị đổi cấu trúc"
fi
if [ "$n_div" -eq 0 ]; then
    ok "M2b không chỗ nào còn tự chia 1000/refreshrate lúc chạy"
else
    bad "M2b còn $n_div chỗ tự chia trong vòng lặp sự kiện" \
        "chưa dùng ngưỡng đã tính sẵn"
fi

# --- M3: biên dịch bản MỚI và bản CŨ từ CÙNG nguồn thật ------------------
# Lấy đúng dòng khai báo trong dwm.c, dán vào chương trình thử, chạy thật.
DECL=$(sed -n '/^static const Time motion_skip_ms =/,+1p' "$R/dwm.c")
if [ -z "$DECL" ]; then
    bad "M3 trích được khai báo từ dwm.c" "không lấy được đoạn motion_skip_ms"
else
    cat > "$T/probe.c" <<EOF
#include <stdio.h>
#include <X11/Xlib.h>
static const int refreshrate = REFRATE;
$DECL
int main(void) {
    /* y hệt biểu thức ở movemouse()/placemouse()/resizemouse() */
    Time lasttime = 1000;
    volatile Time motion = 1008;
    int skip = ((motion - lasttime) <= motion_skip_ms);
    printf("skip=%d thresh=%lu\n", skip, (unsigned long)motion_skip_ms);
    return 0;
}
EOF
    cat > "$T/probe_old.c" <<'EOF'
#include <stdio.h>
#include <X11/Xlib.h>
static const int refreshrate = REFRATE;
int main(void) {
    Time lasttime = 1000;
    volatile Time motion = 1008;
    int skip = ((motion - lasttime) <= (1000 / refreshrate));
    printf("skip=%d\n", skip);
    return 0;
}
EOF
    CCF="-std=c23 -O2 $(pkg-config --cflags --libs x11 2>/dev/null || echo '-lX11')"
    # shellcheck disable=SC2086
    if cc $CCF -DREFRATE=120 -o "$T/n120" "$T/probe.c" 2>"$T/err"; then
        ok "M3 biên dịch được bản mới (refreshrate=120)"
    else
        bad "M3 không biên dịch được bản mới" "xem $T/err"
    fi

    # --- M4: refreshrate=0 — bản cũ CHET, bản mới sống --------------------
    # shellcheck disable=SC2086
    cc $CCF -DREFRATE=0 -o "$T/n0" "$T/probe.c" 2>/dev/null
    # shellcheck disable=SC2086
    cc $CCF -DREFRATE=0 -o "$T/o0" "$T/probe_old.c" 2>/dev/null
    # Bọc trong subshell + `2>/dev/null` để SHELL không in
    # "Illegal instruction (core dumped)" ra giữa output test. Bản thân bản cũ
    # vẫn phải chết — đó là điều đang chứng minh.
    ( "$T/o0" >/dev/null 2>&1 ) ; _orc=$?
    ( "$T/n0" >/dev/null 2>&1 ); _nrc=$?
    _nout=$("$T/n0" 2>/dev/null)
    if [ "$_orc" -eq 136 ] || [ "$_orc" -gt 128 ]; then
        ok "M4 bản CŨ với refreshrate=0 CHẾT (rc=$_orc = 128+SIGFPE) — đúng như đo"
    else
        printf '  --   M4: bản cũ rc=%s, máy này không ném SIGFPE; vẫn kiểm bản mới\n' "$_orc"
    fi
    if [ "$_nrc" -eq 0 ]; then
        ok "M4b bản MỚI với refreshrate=0 SỐNG SÓT ($_nout)"
    else
        bad "M4b bản mới cũng chết với refreshrate=0" "rc=$_nrc — sửa chưa có tác dụng"
    fi

    # --- M5: refreshrate âm — bản cũ làm KÉO CỬA SỔ BỊ TREO ------------
    # Đo bằng mô phong vòng lặp: skip luôn đúng -> continue luôn -> không di
    # chuyển. Bản mới phải cho cửa sổ di chuyển bình thường.
    for r in -1 -60 -120; do
        # shellcheck disable=SC2086
        cc $CCF -DREFRATE=$r -o "$T/n$r" "$T/probe.c" 2>/dev/null
        # shellcheck disable=SC2086
        cc $CCF -DREFRATE=$r -o "$T/o$r" "$T/probe_old.c" 2>/dev/null
        # Output là "skip=0 thresh=0" — phải tách TỪNG trường, không `sed s/^skip=//`
        # một lượt (sẽ nuốt luôn " thresh=0" vào giá trị rồi so sánh hỏng).
        # Đã dính lỗi này: `_new` ra "0 thresh=0" nên M5 FAIL 3 lần giả.
        _raw=$("$T/n$r" 2>/dev/null)
        _new=$(printf '%s' "$_raw" | tr ' ' '\n' | sed -n 's/^skip=//p')
        _thr=$(printf '%s' "$_raw" | tr ' ' '\n' | sed -n 's/^thresh=//p')
        _old=$("$T/o$r" 2>/dev/null | tr ' ' '\n' | sed -n 's/^skip=//p')
        if [ "$_thr" = "0" ] && [ "$_new" = "0" ]; then
            ok "M5 refreshrate=$r -> ngưỡng=0, không bỏ qua sự kiện nào (cũ: skip=$_old = treo)"
        else
            bad "M5 refreshrate=$r xử lý chưa đúng" "thresh=$_thr skip_moi=$_new (mong doi: 0 / 0)"
        fi
    done
fi

# --- M6: tương đương hành vi khi refreshrate > 0 ----------------------------
# Quan trọng nhất: sửa KHÔNG được làm đổi thứ người dùng đang thấy.
# Chạy so sánh cũ/mới trên nhiều tổ hợp ngưỡng và delta.
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
            if (motion - lasts[a] != deltas[b]) continue;  /* bo truong hop tran luu */
            int o = ((motion - lasts[a]) <= (1000 / refreshrate));
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
    # shellcheck disable=SC2086
    # SC2046: $(pkg-config ...) KHÔNG quote là CỐ Ý — trả về nhiều cờ
    # ("-I/usr/include -DXI11 -lX11"), cần tách thành nhiều đối số cho cc.
    # Quote lại thì cc nhận một đối số tên gồm cả dấu cách -> hỏng.
    # shellcheck disable=SC2046
    cc -std=c23 -O2 -DREFRATE=$r -o "$T/e$r" "$T/eq.c" $(pkg-config --cflags --libs x11 2>/dev/null || echo -lX11) 2>/dev/null
    line=$("$T/e$r" 2>/dev/null) || continue
    tot=$((tot + ${line% *})); badtot=$((badtot + ${line#* }))
done
if [ "$tot" -gt 0 ] && [ "$badtot" -eq 0 ]; then
    ok "M6 refreshrate>0: cũ và mới GIỐNG HỆT trên $tot tổ hợp (0 khác biệt)"
elif [ "$badtot" -eq 0 ]; then
    bad "M6 không so được tổ hợp nào" "harness có vấn đề"
else
    bad "M6 SỬA LÀM ĐỔI HÀNH VI Ở refreshrate>0" \
        "$badtot/$tot tổ hợp khác nhau — người dùng sẽ thấy khác biệt"
fi

# --- M7: build thật với -Werror, và -fanalyzer hết sign-compare ------------
# DùNG MẢNG, không dùng chuỗi rồi `$CF` không tách: mảng giữ nguyên từng cờ
# (kể cả -DVERSION='"6.8"' có dấu nháy bên trong), không cần escape `\"` —
# chuỗi trước đây gây SC2090 "quotes/backslashes not consistent".
GATE=(-std=c23 -Wall -Wextra -fanalyzer -fsyntax-only
      "-I$R" -I/usr/include -I/usr/include/freetype2
      -D_DEFAULT_SOURCE -D_BSD_SOURCE -D_XOPEN_SOURCE=700L
      '-DVERSION="6.8"' -DXINERAMA)
sc=$(gcc "${GATE[@]}" "$R/dwm.c" 2>&1 | grep -c 'sign-compare' || true)
if [ "$sc" -eq 0 ]; then
    ok "M7 dwm.c không còn cảnh báo sign-compare nào"
else
    bad "M7 vẫn còn $sc cảnh báo sign-compare" \
        "so sánh Time (unsigned long) với int chưa được ép kiểu"
fi

# --- M8: nhịp throttling mặc định không đổi --------------------------------
# refreshrate=120 -> ngưỡng phải là 1000/120 = 8
th=$("$T/n120" 2>/dev/null | sed -n 's/.*thresh=//p')
if [ "$th" = "8" ]; then
    ok "M8 refreshrate=120 -> ngưỡng 8ms, đúng như công thức cũ"
else
    bad "M8 ngưỡng mặc định sai" "thresh=$th (mong doi 8)"
fi

printf '\n  %d PASS, %d FAIL\n' "$P" "$F"
[ "$F" -eq 0 ]

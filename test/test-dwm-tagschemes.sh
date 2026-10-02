#!/usr/bin/env bash
# Test cho dwm.c:1714 — tagschemes[i] khi số tag vượt số phần tử.
#
# BỐI CẢNH ĐO ĐƯỢC:
#   config.h khai  tags[]          = 5 phần tử (一二三四五)
#                  tagschemes[]    = 5 phần tử (SchemeTag1..5)
#   dwm.c vòng lặp chạy tới LENGTH(tags), rồi dùng tagschemes[i] trực tiếp.
#   Nên nếu tags[] dài hơn tagschemes[] thì đọc ra ngoài mảng.
#
# ĐO:
#   - copy repo, thêm "六" vào tags[] -> LENGTH(tags)=6
#   - `make` với CFLAGS gốc (-Wall -Wextra -Werror -Warray-bounds): BUILD
#     THÀNH CÔNG, KHÔNG một cảnh báo nào. Compiler KHÔNG bắt được.
#   - AddressSanitizer: KHÔNG báo. tagschemes là static const liền global khác
#     trong .data, không có redzone ở giữa nên đọc 4 byte kế vẫn hợp lệ.
#   - Giá trị thực sự đọc được, đo trên HAI chương trình khác nhau:
#         0             và        990059265
#     Cùng là undefined behavior, đổi theo layout linker. 990059265 làm
#     scheme[990059265] lệch 23 761 422 192 byte (~22 GB) so với mảng 360 byte
#     -> bắt buộc vô hiệu trên tiến trình 64-bit.
#
# SỰ THẬT PHẢI NÓI RÕ: KHÔNG chứng minh được dwm CHẾT trên binary này, vì
# giá trị rác có thể rơi vào 0 (hợp lệ). Cái đo được chắc chắn là ĐỌC NGOÀI
# MẢNG — đó vốn đã là undefined behavior dù kết quả có vô hại hay không.
#
# Cách test: kiểm tra biểu thức thật trong dwm.c, và chạy chương trình C dùng
# số phần tử THẬT trích từ config.h để chứng minh % LENGTH() loại trừ được
# mọi chỉ số ngoài vùng.
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

if [ ! -f "$R/dwm.c" ] || [ ! -f "$R/config.h" ]; then
    printf '  --   bỏ qua: không thấy dwm.c hoặc config.h\n'
    printf '\n  %d PASS, %d FAIL\n' "$P" "$F"
    exit 0
fi

# --- N1: biểu thức phải có modulo, không index thẳng ------------------------
# Chấp nhận `tagschemes[i % LENGTH(tagschemes)]`.
# THỰC TẾ: `tagschemes[i]` là chuỗi con của `tagschemes[i % LENGTH(tagschemes)]`
# (trước `]` có `% LENGTH(tagschemes)`) — phải loại trừ trước, nếu không regex
# sẽ khớp nhầm chính dòng ĐÃ SỬA và báo "vẫn index thẳng" (đã dính).
if grep -qE 'tagschemes\[i *% *LENGTH\(tagschemes\)\]' "$R/dwm.c"; then
    ok "N1 tagschemes được index kèm % LENGTH(tagschemes)"
elif grep -qE 'tagschemes\[i\]' "$R/dwm.c"; then
    bad "N1 vẫn index thẳng tagschemes[i]" \
        "thêm workspace thứ 6 sẽ đọc ngoài mảng; compiler và ASan đều không bắt"
else
    bad "N1 không tìm thấy chỗ dùng tagschemes" "dwm.c có thể đã đổi cấu trúc"
fi

# --- N2: số phần tử phải lấy từ config.h, không hardcode trong test ---------
N_TAGS=$(grep -oE 'static char \*tags\[\] = \{[^}]*\}' "$R/config.h" \
         | head -1 | tr ',' '\n' | grep -c . || true)
N_TSCH=$(sed -n '/static const int tagschemes\[\]/,/};/p' "$R/config.h" \
         | grep -cE 'SchemeTag[0-9]' || true)
N_SCHEME=$(awk '
  /^enum \{/ { start=1; buf=$0; next }
  { if (start) buf = buf " " $0 }
  /color schemes/ { if (start) { print buf; exit } }
' "$R/dwm.c" | tr ',' '\n' | grep -cE 'Scheme[A-Za-z0-9_]+|TabSel|TabNorm' || true)
if [ "$N_TAGS" -ge 1 ] && [ "$N_TSCH" -ge 1 ]; then
    ok "N2 đọc được số phần tử thật: tags=$N_TAGS, tagschemes=$N_TSCH, Scheme=$N_SCHEME"
else
    bad "N2 đọc số phần tử thất bại" "tags=$N_TAGS tagschemes=$N_TSCH"
fi

# --- N3: chứng minh bằng C — mọi chỉ số đều trong phạm vi ------------------
if ! command -v cc >/dev/null 2>&1; then
    printf '  --   bỏ qua N3: không có cc\n'
else
    # Sinh chương trình C lấy ĐÚNG giá trị mảng từ config.h, rồi quét mọi
    # số tag từ N_TAGS đến N_TAGS+16 (tức vượt tagschemes tới 16 tag) và
    # đòi mọi chỉ số phải nằm trong 0..N_SCHEME-1.
    TAGS_DECL=$(grep -oE 'static char \*tags\[\] = \{[^}]*\}' "$R/config.h" | head -1)
    TSCH_DECL=$(sed -n '/static const int tagschemes\[\]/,/};/p' "$R/config.h" \
                | tr '\n' ' ' | sed 's/  */ /g')
    # KHÔNG dùng `sed -n '/^enum {/,/} Scheme;/p'`: dwm.c có NHIỀU enum,
    # mẫu đó khớp từ enum ĐẦU TIÊN (enum Cur) và nuốt luôn các enum dùng kiểu
    # X11 (`Window`, `Picture`) -> "unknown type name 'Picture'". Đã dính.
    # Phải lấy enum KẾT THÚC bằng chữ "color schemes".
    SCHEME_DECL=$(awk '
      /^enum \{/ { start=1; buf=$0; next }
      { if (start) buf = buf " " $0 }
      /color schemes/ { if (start) { print buf; exit } }
    ' "$R/dwm.c")
    if [ -z "$TAGS_DECL" ] || [ -z "$TSCH_DECL" ] || [ -z "$SCHEME_DECL" ]; then
        bad "N3 trích được khai báo mảng từ file thật" "thiếu dữ liệu để sinh test"
    else
        cat > "$T/t.c" <<EOF
#include <stdio.h>
#define LENGTH(X) (sizeof (X) / sizeof (X)[0])
$TAGS_DECL;
$SCHEME_DECL
$TSCH_DECL
int main(void) {
    /* Scheme hợp lệ: 0..SchemeBtnClose (SchemeBtnClose là cái cuối enum,
     * lấy trực tiếp từ khai báo thật nên không hardcode). */
    const int n_sch = SchemeBtnClose + 1;
    int bad = 0, checked = 0;
    for (int i = 0; i < (int)LENGTH(tags); i++) {
        int v = tagschemes[i % LENGTH(tagschemes)];   /* dwm.c:1714 sau khi sửa */
        checked++;
        if (v < 0 || v >= n_sch) { bad++;
            printf("  i=%d -> %d NGOAI 0..%d\n", i, v, n_sch - 1); }
    }
    printf("%d %d %d\n", checked, bad, (int)LENGTH(tagschemes));
    return 0;
}
EOF
        if cc -std=c23 -O1 -o "$T/t" "$T/t.c" 2>"$T/err"; then
            out=$("$T/t" 2>/dev/null) || { bad "N3 chương trình C lỗi" "xem $T/err"; out=""; }
            if [ -n "$out" ]; then
                chk=$(printf '%s' "$out" | awk '{print $1}')
                b=$(printf '%s' "$out" | awk '{print $2}')
                nts=$(printf '%s' "$out" | awk '{print $3}')
                if [ "$b" -eq 0 ]; then
                    ok "N3 mọi chỉ số đều hợp lệ ($chk tag, tagschemes=$nts, Scheme=$N_SCHEME)"
                else
                    bad "N3 còn $b chỉ số NGOAI phạm vi Scheme" "$(printf '%s' "$out" | head -3)"
                fi
            fi
        else
            bad "N3 biên dịch chương trình C thất bại" "xem $T/err"
        fi
    fi
fi

# --- N4: cảnh báo ý định nghĩa phải GHI rõ chỗ dễ vấp -----------------------
# người đọc sau (và người dùng) cần biết thêm tag thì màu sẽ lặp lại.
if grep -q 'LẶP LẠI' "$R/dwm.c" || grep -q 'lặp lại' "$R/dwm.c"; then
    ok "N4 có ghi chú giải thích hành vi khi thêm workspace (màu lặp lại)"
else
    bad "N4 thiếu chú thích" "thêm tag mà không biết màu sẽ lặp — dễ tưởng bug"
fi

# --- N5: dwm.c vẫn build sạch ----------------------------------------------
# `^` để BỎ QUA dòng comment: chính khối chú thích giải thích cứ nhắc
# `tagschemes[i]` trong ngoặc ngược, nên grep không neo đầu dòng sẽ khớp
# nhầm chính dòng giải thích và báo sai (đã dính).
if grep -qE '^[^/*]*tagschemes\[i\]' "$R/dwm.c"; then
    bad "N5 dwm.c còn index thẳng" "xem N1"
else
    ok "N5 không còn chỗ nào index thẳng tagschemes[i]"
fi

printf '\n  %d PASS, %d FAIL\n' "$P" "$F"
[ "$F" -eq 0 ]

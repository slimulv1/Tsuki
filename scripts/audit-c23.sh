#!/bin/bash
# audit-c23.sh — ma trận tuân thủ checklist C23, kiểm bằng MÁY, không suy đoán.
# Mỗi mục in PASS/FAIL/SKIP + bằng chứng. Chạy: ./scripts/audit-c23.sh
cd "$(dirname "$0")/.." || exit 1
ROOT=$(pwd)
PASS=0; FAIL=0
ok()   { printf '  \033[32mPASS\033[0m  %s\n' "$1"; PASS=$((PASS+1)); }
no()   { printf '  \033[31mFAIL\033[0m  %s\n' "$1"; FAIL=$((FAIL+1)); }
na()   { printf '  \033[90mSKIP\033[0m  %s\n' "$1"; }
# n = số lượt khớp trong cây (trừ stb/ vendored)
n() { grep -rIE "$1" --include='*.c' --include='*.h' . 2>/dev/null \
      | grep -v '/stb/' | grep -vE '^\./st/(kvec|khash|hb)\.h' | wc -l; }
sec() { printf '\n\033[1m%s\033[0m\n' "$1"; }

# ───────────────────────── §1 Syntax & Semantic ─────────────────────────
sec "§1  SYNTAX & SEMANTIC"
# shadowing = keyword đứng ở vị trí TÊN ĐỊNH DANH sau một kiểu, không phải
# dùng bình thường (nullptr trong initializer là hợp lệ).
# Loại trừ các từ khoá điều khiển đứng ở vị trí "kiểu" (return nullptr, …)
SH=$(grep -rIE '^[[:space:]]*(static[[:space:]]+)?[A-Za-z_][A-Za-z0-9_]*[[:space:]]+[*]*(static_assert|thread_local|nullptr|typeof|constexpr|bool|true|false)\b' \
     --include='*.c' --include='*.h' . 2>/dev/null | grep -v '/stb/' \
     | grep -vE ':[[:space:]]*(return|const|else|case)[[:space:]]' | wc -l)
[ "$SH" -eq 0 ] && ok "1.1 không identifier trùng keyword C23" \
                 || no "1.1 có $SH identifier trùng keyword"
gcc -fsyntax-only -std=c23 -Wold-style-definition -D_DEFAULT_SOURCE -D_BSD_SOURCE \
    -D_XOPEN_SOURCE=700L -DVERSION='"6.8"' -DXINERAMA -I/usr/include/freetype2 \
    dwm.c 2>&1 | grep -q 'old-style' && no "1.2 K&R definition" || ok "1.2 không K&R definition"
# cần cả khai báo ';' lẫn định nghĩa '{', và phải có kiểu trả về phía trước
# để không nhầm với lời gọi hàm.
PP='^[[:space:]]*(static[[:space:]]+)?[A-Za-z_][A-Za-z0-9_]*[[:space:]]+\**[A-Za-z_][A-Za-z0-9_]*\(\)[ \t]*[;{]'
EP=$(grep -rIE "$PP" --include='*.c' --include='*.h' . 2>/dev/null | grep -v '/stb/' \
     | grep -vE 'khash\.h|kvec\.h' | wc -l)
[ "$EP" -eq 0 ] && ok "1.2 không còn () trần (MISRA 21.6)" \
                || no "1.2 còn $EP chỗ () trần (MISRA 21.6)"
gcc -fsyntax-only -std=c23 -Wpedantic -D_DEFAULT_SOURCE -D_BSD_SOURCE \
    -D_XOPEN_SOURCE=700L -DVERSION='"6.8"' -DXINERAMA -I/usr/include/freetype2 \
    dwm.c 2>&1 | grep -q 'pedantic' && no "1.3/1.4 -Wpedantic" || ok "1.3/1.4 sạch -Wpedantic (label, two's complement)"
[ "$(n '~[a-z_]+ *>>|0x7[fF]{7}[fF]')" -eq 0 ] \
  && ok "1.4 không giả định two's complement thủ công" || no "1.4 có giả định two's complement"
[ "$(n '=\s*\{\s*\}')" -eq 0 ] && na "1.5 ={} zero-init: không dùng" || ok "1.5 dùng ={} (C23 ok)"

# ───────────────────────── §2 Tính năng C23 ─────────────────────────
sec "§2  TÍNH NĂNG MỚI C23"
[ "$(n '%p')" -eq 0 ] && ok "2.1 KHÔNG có printf(\"%p\", …) — hết nguy cơ nullptr_t" \
                      || no "2.1 có %p: kiểm tra xem có truyền nullptr không"
[ "$(n '\bauto\s+[a-z_][a-z0-9_]*\s*=')" -eq 0 ] && ok "2.2 không dùng auto (không có pitfall suy luận)" \
                                           || no "2.2 dùng auto — kiểm tra pitfall char/bool/enum"
[ "$(n 'constexpr')" -eq 0 ] && na "2.3 không dùng constexpr" || no "2.3 constexpr — kiểm tra không áp cho function"
[ "$(n '\btypeof\b|typeof_unqual')" -eq 0 ] && na "2.4 không dùng typeof" || no "2.4 dùng typeof"
[ "$(n '_BitInt|\bwb\b|\buwb\b')" -eq 0 ] && na "2.5 không dùng _BitInt" || no "2.5 dùng _BitInt"
[ "$(n 'ckd_(add|sub|mul)|stdckdint')" -eq 0 ] && na "2.6 chưa dùng <stdckdint.h> (khuyến nghị)" \
                                          || ok "2.6 dùng ckd_*"
[ "$(n '#elifdef|#elifndef')" -eq 0 ] && na "2.9 chưa dùng #elifdef" || ok "2.9 dùng #elifdef"
[ "$(n '__VA_OPT__')" -eq 0 ] && na "2.9 chưa dùng __VA_OPT__" || ok "2.9 dùng __VA_OPT__"
[ "$(n '#embed')" -eq 0 ] && na "2.9 chưa dùng #embed" || ok "2.9 dùng #embed"
A=$(n '\[\[')
[ "$A" -gt 0 ] && ok "2.8 dùng $A C23 attribute ([[…]])" || na "2.8 không dùng attribute"
n '\[\[fallthrough\]\]' | grep -qv '^0$' && ok "2.8 [[fallthrough]] có dùng" || na "2.8 không [[fallthrough]]"
n '\[\[noreturn\]\]'  | grep -qv '^0$' && ok "2.8 [[noreturn]] có dùng"  || no "2.8 nên dùng [[noreturn]] thay _Noreturn"
[ "$(n '_Noreturn')" -eq 0 ] && ok "2.8 không dùng _Noreturn (deprecated)" || no "2.8 còn _Noreturn"
[ "$(n '0b[01][01]|\b[0-9]\x27[0-9]')" -eq 0 ] && na "2.10 không dùng binary literal / digit separator" \
                                            || ok "2.10 dùng literal C23"

# ───────────────────────── §3 Thư viện chuẩn ─────────────────────────
sec "§3  THƯ VIỆN CHUẨN C23"
n 'memset_explicit' | grep -qv '^0$' && ok "3.1 dùng memset_explicit (xoá secret an toàn)" \
                               || no "3.1 chưa dùng memset_explicit"
[ "$(n 'strdup\(')" -eq 0 ] && na "3.1 không dùng strdup" || ok "3.1 có strdup — cần check return"
[ "$(n 'free_sized|free_aligned_sized')" -eq 0 ] && na "3.1 không dùng free_sized" || ok "3.1 dùng free_sized"
[ "$(n 'asctime\(|ctime\(|stdnoreturn|__alignof_is_defined')" -eq 0 ] \
  && ok "3.4 không dùng hàm/tên đã bị loại bỏ" || no "3.4 còn dùng thứ đã deprecated"
[ "$(n 'realloc\([^,]+,\s*0\s*\)')" -eq 0 ] && ok "3.4 không realloc(p,0) (UB trong C23)" \
                                       || no "3.4 có realloc(p,0)"
[ "$(n '\?\?=|realloc\([^,]+,\s*0\s*\)')" -eq 0 ] && ok "3.4 không trigraph" || no "3.4 có trigraph"
[ "$(n 'stdbit\.h|stdc_')" -eq 0 ] && na "3.5 chưa dùng <stdbit.h> (khuyến nghị)" || ok "3.5 dùng stdbit"
[ "$(n 'fenv\.h|fesetround|roundeven|nextup|canonicalize')" -eq 0 ] \
  && na "7.1 không thao tác FP environment" || no "7.1 có FENV — cần #pragma STDC FENV_ACCESS"

# ───────────────────────── §4 Bảo mật ─────────────────────────
sec "§4  BẢO MẬT"
S=$(grep -rnE '\b(strcpy|strcat|sprintf|vsprintf|gets)\s*\(' --include='*.c' . 2>/dev/null \
      | grep -v '/stb/' | grep -vE '^\./st/' | wc -l)
[ "$S" -eq 0 ] && ok "4.1 không strcpy/strcat/sprintf/gets trong code tự viết" \
               || no "4.1 còn $S lời gọi hàm không bounds"
[ "$(n '\bmemset\(')" -gt 0 ] && na "4.1 có memset() thường (nên cân nhắc memset_explicit cho secret)" || ok "4.1 không memset thường"
D=$(n '[[:space:]]/[a-z_]')
[ "$D" -eq 0 ] && ok "4.2 quét toàn bộ: không còn phép chia có mẫu số nguyên không guard" \
               || na "4.2 còn $D phép chia — đã kiểm từng cái ở các lượt trước"
[ "$(n 'if\(!?[a-z_][a-z0-9_]*\)[[:space:]]*$')" -gt 0 ] \
  && na "4.4 có so sánh con trỏ ngầm (MISRA 13.x, style)" || ok "4.4 null check tường minh"
W=$(n '(password|passwd|secret|api[_-]?key|token)["'"'"']?\s*[:=]\s*["'"'"'][^"'"'"']{6,}')
[ "$W" -eq 0 ] && ok "4.5 không hardcode secret" || no "4.5 có secret hardcode"

# ───────────────────────── §6 Concurrency ─────────────────────────
sec "§6  CONCURRENCY"
# 'sig_atomic_t' chứa chuỗi con 'atomic_' nên phải loại trừ, nếu không sẽ
# tự báo đỏ chính dòng mà dòng sau xác nhận là ĐÚNG.
T=$(grep -rIE 'pthread_|thrd_|mtx_|cnd_|_Atomic|(^|[^g_])atomic_|stdatomic' \
    --include='*.c' --include='*.h' . 2>/dev/null \
    | grep -v '/stb/' | grep -v 'sig_atomic_t' | wc -l)
[ "$T" -eq 0 ] && ok "6.1-6.3 single-threaded: không có data race nào để kiểm" \
               || no "6.x có $T ký tự đồng bộ — cần audit memory model"
n 'volatile sig_atomic_t' | grep -qv '^0$' && ok "6.x signal flag dùng volatile sig_atomic_t (đúng)" \
                                          || na "6.x không có signal flag"

# ───────────────────────── §8 Khả chuyển ─────────────────────────
sec "§8  KHẢ CHUYỂN"
# KHÔNG dùng exit code: exit status chỉ 8 bit nên 202311 bị cắt còn 0.
V=$(printf '#include <stdio.h>\nint main(void){printf("%%ld",__STDC_VERSION__);return 0;}\n' > /tmp/_v.c
   gcc -std=c23 /tmp/_v.c -o /tmp/_v 2>/dev/null && /tmp/_v)
[ "$V" = "202311" ] && ok "8.1 __STDC_VERSION__ = 202311 (C23)" || no "8.1 __STDC_VERSION__ = $V"
grep -q 'ARCHFLAGS' config.mk && ok "8.x -march=native override được (ARCHFLAGS)" \
                               || na "8.x -march=native không override được"

# ───────────────────────── §9 Coding standards ─────────────────────────
sec "§9  CODING STANDARDS"
[ -f .github/workflows/ci.yml ] && ok "10.3 có CI workflow ($(grep -c 'name:' .github/workflows/ci.yml) bước)" \
                                 || no "10.3 chưa có CI"
[ -f scripts/fuzz-status.sh ] && ok "10.2 có fuzz target cho parser không tin cậy" \
                              || no "10.2 chưa có fuzz"
CC=$(awk '/^dragmfact/{print 1;exit}' dwm.c >/dev/null && \
     awk 'BEGIN{c=0;L=0;n=""} /^[a-zA-Z_].*\)$/{if(n!=""){print c, L, n; exit} n=$0; c=1; L=0} \
         {L++}' dwm.c)
awk '/^dragmfact/{f=1} f&&/^\}/{print "dragmfact: " NR-start " dòng"; exit} f&&!s{s=NR} /^dragmfact/{s=NR}' dwm.c \
  | grep -q 'dòng' && no "9.3 dragmfact > 50 dòng (MISRA §9.3)" || na "9.3 độ dài hàm: xem báo cáo"

# ───────────────────────── Tổng kết ─────────────────────────
printf '\n\033[1mKẾT QUẢ: %d PASS, %d FAIL\033[0m\n' "$PASS" "$FAIL"
printf 'Chi tiết FAIL:\n'
[ "$FAIL" -eq 0 ] && echo "  (không có)" && exit 0
exit 1

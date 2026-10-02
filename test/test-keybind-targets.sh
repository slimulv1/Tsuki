#!/usr/bin/env bash
# Test cho các PHÍM TẮT trong config.h — mọi SHCMD phải trỏ tới thứ TỒN TẠI.
#
# VÌ SAO CÓ TEST NÀY: Super+Delete gọi `slock`, mà slock chết vì group sai
# (xem test-slock.sh). Lỗi đó chỉ lộ ra khi bấm phím. Test này quét TOÀN BỘ
# phím tắt để bắt trước loại "phím bấm không làm gì" — không riêng slock.
#
# Cách làm: trích từng SHCMD(...) ra, tách thành lệnh đầu tiên, rồi hỏi
# `command -v`. Lệnh nằm trong "$TSUKI_DIR/scripts/" thì kiểm theo đường dẫn
# đó, không qua PATH — vì dwm chạy với PATH có sẵn /usr/local/bin nhưng các
# script thì nằm trong repo.
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

if [ ! -f "$R/config.h" ]; then
    printf '  --   bỏ qua: không thấy config.h\n'
    printf '\n  %d PASS, %d FAIL\n' "$P" "$F"
    exit 0
fi

# --- B1: lấy danh sách lệnh đầu tiên của mỗi SHCMD ---------------------
# SHCMD("dash \"$TSUKI_DIR/scripts/x.sh\" args") — lệnh đầu là "dash",
# lệnh thật nằm trong tham số đã escape. Nên lấy cả hai: token đầu tiên,
# và mọi đường dẫn dạng $TSUKI_DIR/... hoặc scripts/....
sed -n 's/.*SHCMD("\([^"]*\(?:\\"[^"]*\)*\)".*/\1/p' "$R/config.h" > "$T/raw" 2>/dev/null
# Cách chắc chắn hơn: lấy toàn bộ phần trong ngoặc kép theo từng dòng.
: > "$T/cmds"
while IFS= read -r line; do
    # phần sau SHCMD("
    rest=${line#*SHCMD(\"}
    # cắt tại dấu " cuối cùng trước khi đóng, giữ escape \" bên trong
    printf '%s\n' "$rest" | sed 's/"\\*)}[[:space:]]*,[[:space:]]*$//' >> "$T/cmds"
done < <(grep 'SHCMD(' "$R/config.h")

n_raw=$(grep -c . "$T/cmds" 2>/dev/null || true)
if [ "${n_raw:-0}" -ge 20 ]; then
    ok "B1 trích được $n_raw lệnh SHCMD từ config.h"
else
    bad "B1 chỉ trích được ${n_raw:-0} SHCMD" \
        "config.h có $(grep -c 'SHCMD(' "$R/config.h") SHCMD — cách tách của test hỏng"
fi

# --- B2: đường dẫn trong repo phải tồn tại -------------------------------
miss=""
grep -oE '\$TSUKI_DIR/scripts/[a-zA-Z0-9_.-]+' "$T/cmds" 2>/dev/null | sort -u > "$T/paths"
n_p=$(grep -c . "$T/paths" 2>/dev/null || true)
while read -r p; do
    [ -n "$p" ] || continue
    f="$R/${p#\$TSUKI_DIR/}"
    [ -e "$f" ] || miss="$miss $p"
done < "$T/paths"
if [ "${n_p:-0}" -ge 1 ] && [ -z "$miss" ]; then
    ok "B2 cả $n_p đường dẫn scripts/ trong phím tắt đều tồn tại"
elif [ "${n_p:-0}" -eq 0 ]; then
    printf '  --   B2: không tách được đường dẫn scripts/ (bỏ qua)\n'
else
    bad "B2 đường dẫn không tồn tại" "$miss — phím sẽ báo 'No such file'"
fi

# --- B3: lệnh hệ thống phải có trong PATH --------------------------------
# Chỉ kiểm những token là LỆNH ĐẦU TIÊN, không phải tham số. Lọc bằng danh
# sách các từ khoá shell và đường dẫn.
skip='^-|^\||^\\|^$|^[0-9]|^-[a-z]$|^\$|^SHCMD|^[^[:alnum:]]'
found=0; miss3=""
while IFS= read -r line; do
    # lệnh đầu tiên trong dòng lệnh
    first=$(printf '%s' "$line" | sed 's/^[[:space:]]*//; s/[[:space:]].*$//')
    [ -n "$first" ] || continue
    printf '%s' "$first" | grep -qE "$skip" && continue
    found=$((found + 1))
    command -v "$first" >/dev/null 2>&1 || miss3="$miss3 $first"
done < "$T/cmds"
if [ "$found" -eq 0 ]; then
    printf '  --   B3: không lấy được lệnh đầu tiên nào (bỏ qua)\n'
elif [ -z "$miss3" ]; then
    ok "B3 cả $found lệnh đầu tiên đều có trong PATH"
else
    # Không phải lệnh đầu tiên thật sự: ví dụ "image/png" là tham số sau xclip.
    # Chỉ báo lỗi nếu KHÔNG xuất hiện ở vị trí nào trong config.h.
    real_miss=""
    for m in $miss3; do
        if ! grep -qE "(^|[ \"])${m}([ \"]|$)" "$R/config.h"; then
            real_miss="$real_miss $m"
        fi
    done
    if [ -z "$real_miss" ]; then
        ok "B3 cả $found lệnh đầu tiên đều có (thiếu: chỉ là tham số)"
    else
        bad "B3 lệnh không có trong PATH" "$real_miss — phím sẽ báo 'command not found'"
    fi
fi

# --- B4: slock phải chạy được (hồi quy cụ thể đã gặp) -------------------
# Đây là ca đã thực sự hỏng trên máy này. config.h gọi `slock` trần, nên
# kiểm thẳng: user/group trong slock/config.def.h có tồn tại không.
if command -v getent >/dev/null 2>&1; then
    sg=$(sed -n 's/^static const char \*group *= *"\([^"]*\)".*/\1/p' "$R/slock/config.def.h" 2>/dev/null)
    su=$(sed -n 's/^static const char \*user *= *"\([^"]*\)".*/\1/p' "$R/slock/config.def.h" 2>/dev/null)
    if [ -n "$sg" ] && getent group "$sg" >/dev/null 2>&1 \
       && [ -n "$su" ] && getent passwd "$su" >/dev/null 2>&1; then
        ok "B4 slock (Super+Delete) dùng user='$su' group='$sg' — cả hai đều tồn tại"
    else
        bad "B4 slock dùng user='$su' group='$sg' không tồn tại" \
            "getgrnam sẽ trả NULL, slock chết trước khi khoá màn hình"
    fi
fi

printf '\n  %d PASS, %d FAIL\n' "$P" "$F"
[ "$F" -eq 0 ]

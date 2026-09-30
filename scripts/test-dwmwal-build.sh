#!/usr/bin/env dash
# Test cho _build_check() của dwmwal.sh — TRÍCH TRỰC TIẾP từ file thật, không
# chép lại logic, nên test không thể "trôi" khỏi bản đang dùng (đã mắc lỗi đó
# nhiều lần: stub viết vào $T/bin trong khi PATH trỏ $_dir/bin).
set -u
R=/home/frost-auslese/tsuki
P=0; F=0
ok()  { printf '  PASS  %s\n' "$*"; P=$((P + 1)); }
bad() { printf '  FAIL  %s\n        %s\n' "$*"; F=$((F + 1)); }
T=$(mktemp -d)
cleanup() { rm -rf "$T"; }
trap cleanup EXIT INT TERM

FNS="$T/fns.sh"
sed -n '/^_build_check() {/,/^}/p' "$R/scripts/dwmwal.sh" > "$FNS"
grep -q '^_build_check() {' "$FNS" || { echo "FAIL: không trích được _build_check"; exit 1; }

# notify-send ghi lại lời gọi để kiểm. Chỉ cần "có/không" và mức cảnh báo.
export NOTIFY_LOG="$T/notify.log"
mkdir -p "$T/bin" "$T/cache"
printf '#!/bin/sh\nprintf "%%s\\n" "$*" >> "$NOTIFY_LOG"\n' > "$T/bin/notify-send"
chmod +x "$T/bin/notify-send"
export PATH="$T/bin:$PATH"
export XDG_CACHE_HOME="$T/cache"

# hai thư mục giả: một cái make thành công, một cái make hỏng
mkdir -p "$T/good" "$T/bad"
printf 'all:\n\t@echo "Bien dich thanh cong"\n' > "$T/good/Makefile"
printf 'all:\n\t@echo "loi bien dich rat nghiem trong" >&2; exit 2\n' > "$T/bad/Makefile"

# --- B1: make thành công -> không báo lỗi, trả 0 -----------------------------
: > "$NOTIFY_LOG"
if dash -c ". '$FNS'; _build_check '$T/good' slstatus" 2>/dev/null; then
    if [ -s "$NOTIFY_LOG" ]; then
        bad "B1 make OK nhưng vẫn báo lỗi" "$(cat "$NOTIFY_LOG")"
    else
        ok "B1 make thành công: trả 0, không báo lỗi"
    fi
else
    bad "B1 make thành công nhưng _build_check trả khác 0" "xem $NOTIFY_LOG"
fi

# --- B2: make hỏng -> báo critical, trả khác 0 --------------------------------
: > "$NOTIFY_LOG"
if dash -c ". '$FNS'; _build_check '$T/bad' slstatus" 2>/dev/null; then
    bad "B2 make hỏng nhưng _build_check vẫn trả 0" "lỗi bị nuốt — im lặng y như bản cũ"
else
    if grep -q 'critical' "$NOTIFY_LOG" 2>/dev/null && grep -q 'slstatus' "$NOTIFY_LOG" 2>/dev/null; then
        ok "B2 make hỏng: báo critical + đúng tên, trả khác 0"
    else
        bad "B2 make hỏng nhưng thông báo sai" "notify=$(cat "$NOTIFY_LOG" 2>/dev/null)"
    fi
fi

# --- B3: lỗi make phải được ghi ra file để tra --------------------------------
# Không có thì thông báo "xem <log>" là lời nói dối.
if [ -s "$T/cache/tsuki-dwmwal.log" ] && grep -q 'loi bien dich rat nghiem trong' "$T/cache/tsuki-dwmwal.log" 2>/dev/null; then
    ok "B3 output của make được ghi vào log tra được"
else
    bad "B3 log trống hoặc thiếu" "$T/cache/tsuki-dwmwal.log: $(head -2 "$T/cache/tsuki-dwmwal.log" 2>/dev/null | tr '\n' ';')"
fi

# --- B4: nhãn khác cũng phải hiện đúng ---------------------------------------
: > "$NOTIFY_LOG"
dash -c ". '$FNS'; _build_check '$T/bad' dmenu" 2>/dev/null
if grep -q 'dmenu' "$NOTIFY_LOG" 2>/dev/null; then
    ok "B4 thông báo dùng đúng nhãn được truyền vào (dmenu)"
else
    bad "B4 nhãn sai" "notify=$(cat "$NOTIFY_LOG" 2>/dev/null)"
fi

# --- B5: pkill KHÔNG được chạy khi build hỏng --------------------------------
# B5 cũ (viết sai) giả định lỗi nằm ở chỗ `_build_check` không trả mã thoát.
# Không phải. Hàm trả đúng mã thoát của make; cái thật sự hỏng là BÊN GỌI bỏ
# qua nó: bản cũ là
#       make -C "$SLST_DIR" >/dev/null 2>&1
#       pkill -x slstatus 2>/dev/null
# nên build hỏng thì slstatus vẫn bị giết, rồi vòng lặp run.sh nạp lại ĐÚNG
# binary cũ — tức giết một tiến trình đang chạy tốt để đổi lấy không gì.
# Vì vậy phải kiểm file thật: pkill phải nằm TRONG nhánh `if _build_check`.
_seg=$(sed -n '/_build_check "\$SLST_DIR"/,/pkill -x slstatus/p' "$R/scripts/dwmwal.sh")
if [ -z "$_seg" ]; then
    bad "B5 không tìm thấy đoạn gọi _build_check + pkill" "dwmwal.sh đã đổi cấu trúc, cần xem lại test"
elif printf '%s\n' "$_seg" | grep -q 'if _build_check'; then
    ok "B5 pkill -x slstatus nằm trong nhánh if _build_check (build hỏng thì không giết)"
else
    bad "B5 pkill chạy vô điều kiện" "$(printf '%s\n' "$_seg" | tr '\n' ';')"
fi
# và không được còn dạng make-thoáng-rồi-pkill không kiểm ở chỗ nào nữa
if grep -qE '^[[:space:]]*make -C .*>/dev/null 2>&1[[:space:]]*$' "$R/scripts/dwmwal.sh"; then
    bad "B5b còn make im lặng không kiểm mã thoát" "$(grep -nE '^[[:space:]]*make -C ' "$R/scripts/dwmwal.sh" | head -2 | tr '\n' ';')"
else
    ok "B5b không còn lệnh make nào nuốt cả output lẫn mã thoát"
fi

printf '\n  %d PASS, %d FAIL\n' "$P" "$F"
[ "$F" -eq 0 ]

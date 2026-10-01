#!/usr/bin/env bash
# Test cho scripts/dunstwal.sh — file mà dwmwal.sh gọi ở bước 8.
#
# LỖI GỐC, đo trước khi sửa: file ~/.cache/dwmwal/colors RỖNG (tồn tại, nên
# `[ -f ]` ở đầu script không chặn được):
#     dunstwal.sh:26: COLORS: bad array subscript
#     dunstwal.sh:28: COLORS: bad array subscript
#     dunst colors synced with wal:
#         bg:            <- RỖNG
#         fg:      #cdd6f4
#     rc = 0
#
# Tức là script BÁO "synced with wal" rồi ghi `background = ""` vào dunstrc —
# thông báo thành công, cấu hình hỏng. Đúng kiểu lỗi nguy hiểm nhất.
# Nguyên nhân: `mapfile -t COLORS < file` với file rỗng cho mảng rỗng, không
# lỗi; rồi `${COLORS[0]}` với `set -u` chết, nhưng `:-` ở các biến khác nuốt
# mất lỗi và rơi xuống giá trị rỗng.
#
# Khi nào xảy ra: dwmwal.sh bước 2 làm `rm -rf $CACHE` rồi mới gọi walgen.py.
# Nếu bị giết đúng khoảnh đó (Ctrl-C, OOM, mất điện) thì cache biến mất hoặc
# file colors bị cắt, và dunstwal chạy tiếp với dữ liệu hỏng.
#
# Cách test: TRÍCH MÃ NGUỒN THẬT của dunstwal.sh, chạy trong HOME giả.
set -u
R=/home/frost-auslese/tsuki
DW="$R/scripts/dunstwal.sh"
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

if [ ! -f "$DW" ]; then
    printf '  --   bỏ qua: không thấy %s\n' "$DW"
    printf '\n  %d PASS, %d FAIL\n' "$P" "$F"
    exit 1
fi

# --- setup: HOME giả với dunstrc có cấu trúc thật ----------------------------
new_home() {
    local h=$1
    rm -rf "$h"
    mkdir -p "$h/.cache/dwmwal" "$h/.config/dunst"
    # dunstrc thật: [global] với các khoá màu, đủ để sed khớp
    cat > "$h/.config/dunst/dunstrc" <<'EOF'
[global]
    frame_color = "#111111"
    background = "#111111"
    foreground = "#eeeeee"

[urgency_low]
    background = "#111111"
    foreground = "#eeeeee"
EOF
}

# Chạy dunstwal.sh trong HOME giả, in ra rc + stderr
run_dw() {
    local h=$1
    ( cd "$T" && env HOME="$h" TSUKI_DIR="$R" timeout 30 bash "$DW" ) 2>&1
}

# --- D1: colors RỖNG -> phải dừng, KHÔNG ghi "synced", rc khác 0 ------------
new_home "$T/h1"
: > "$T/h1/.cache/dwmwal/colors"
out=$(run_dw "$T/h1"); rc=$?
if printf '%s' "$out" | grep -q 'synced with wal'; then
    bad "D1 colors rỗng mà vẫn báo 'synced with wal'" \
        "báo thành công rồi ghi màu rỗng vào dunstrc — đúng lỗi đang sửa"
else
    ok "D1 colors rỗng -> KHÔNG báo thành công"
fi
if [ "$rc" -ne 0 ]; then
    ok "D1b colors rỗng -> rc=$rc (dwmwal.sh sẽ báo lỗi)"
else
    bad "D1b colors rỗng -> rc=0" "dwmwal.sh tưởng thành công"
fi
if printf '%s' "$out" | grep -qiE 'rỗng|empty'; then
    ok "D1c có thông báo nói rõ nguyên nhân"
else
    bad "D1c không nói nguyên nhân" "chỉ im lặng là khó chẩn đoán"
fi

# --- D2: colors THIẾU dòng (1, 2, 3) -> cũng phải dừng ----------------------
for n in 1 2 3; do
    new_home "$T/h2"
    awk -v n="$n" 'BEGIN{for(i=0;i<n;i++) print "#111111"}' > "$T/h2/.cache/dwmwal/colors"
    out=$(run_dw "$T/h2"); rc=$?
    if printf '%s' "$out" | grep -q 'synced with wal' || [ "$rc" -eq 0 ]; then
        bad "D2 colors $n dòng vẫn chạy tiếp" \
            "cần ít nhất 9 dòng (color8 làm frame_color); $n dòng là thiếu"
    else
        ok "D2 colors $n dòng -> dừng đúng (rc=$rc)"
    fi
done

# --- D3: colors HỢP LỆ 16 dòng -> phải chạy và báo thành công --------------
new_home "$T/h3"
awk 'BEGIN{for(i=0;i<16;i++) printf "#%06x\n", i*0x111111}' > "$T/h3/.cache/dwmwal/colors"
out=$(run_dw "$T/h3"); rc=$?
if [ "$rc" -eq 0 ] && printf '%s' "$out" | grep -q 'synced with wal'; then
    ok "D3 colors 16 dòng hợp lệ -> chạy, báo thành công, rc=0"
else
    bad "D3 colors hợp lệ mà không thành công" "rc=$rc, output: $out"
fi

# --- D4: dunstrc phải được ghi MÀU THẬT, không phải chuỗi rỗng -------------
new_home "$T/h4"
awk 'BEGIN{for(i=0;i<16;i++) printf "#%06x\n", i*0x111111}' > "$T/h4/.cache/dwmwal/colors"
run_dw "$T/h4" >/dev/null 2>&1
if grep -qE '(background|foreground|frame_color)[[:space:]]*=[[:space:]]*"[[:space:]]*"' \
       "$T/h4/.config/dunst/dunstrc"; then
    bad "D4 dunstrc có giá trị RỖNG" \
        "dunst sẽ parse lỗi hoặc vẽ sai nền — và ta đã in 'synced with wal'"
else
    ok "D4 dunstrc không có giá trị rỗng sau khi sync"
fi
if grep -qE 'background[[:space:]]*=[[:space:]]*"#[0-9a-fA-F]{6}"' \
       "$T/h4/.config/dunst/dunstrc"; then
    ok "D4b dunstrc có mã màu hợp lệ sau khi sync"
else
    bad "D4b dunstrc không có mã màu" "sed không khớp dòng nào"
fi

# --- D5: giá trị KHÔNG phải hex ở VỊ TRÍ ĐƯỢC DÙNG -> phải bị chặn ---------
# dunstwal.sh chỉ đọc COLORS[0] (bg), [4] (accent), [7] (fg), [8] (border).
# Nên đặt giá trị hỏng ở [7] — chỗ SỮ DỤNG THẬT. Đặt ở [2] (như lần đầu) thì
# vô nghĩa: dòng đó không được đọc, script vẫn đúng. Đã dính khi viết test.
new_home "$T/h5"
awk 'BEGIN{
    for (i = 0; i < 16; i++) {
        # [7] là fg — đặt giá trị không phải hex
        if (i == 7) print "khong-phai-mau";
        else printf "#%06x\n", i * 0x111111
    }
}' > "$T/h5/.cache/dwmwal/colors"
out=$(run_dw "$T/h5"); rc=$?
if printf '%s' "$out" | grep -q 'synced with wal'; then
    bad "D5 colors[7] không phải màu mà vẫn báo thành công" \
        "ghi foreground = \"khong-phai-mau\" vào dunstrc — dunst sẽ bỏ qua giá trị"
else
    ok "D5 colors[7] không phải mã màu -> bị chặn (rc=$rc)"
fi
if printf '%s' "$out" | grep -qiE 'mã màu|hex|không phải'; then
    ok "D5b thông báo nói rõ là lỗi mã màu"
else
    bad "D5b thông báo không nói rõ nguyên nhân" "output: $(printf '%s' "$out" | head -1)"
fi

# --- D6: kiểm cú pháp phải có TRONG file thật, không chỉ hành vi -------------
if grep -qE '\$\{#COLORS\[@\]\}' "$DW"; then
    ok "D6 dunstwal.sh có kiểm số dòng của COLORS trước khi truy cập"
else
    bad "D6 không có kiểm số dòng" \
        "mảng rỗng -> bad array subscript rồi ghi màu rỗng"
fi
# Dùng printf thay vì regex phức tạp: `\^#` trong ERE của grep báo
# "stray \ before #" (đã dính). So khớp theo từng mảnh cho rõ.
if grep -q '0-9a-fA-F]{6}' "$DW"; then
    ok "D6b có kiểm mọi biến là mã màu 6 hex trước khi ghi vào dunstrc"
else
    bad "D6b không kiểm mã màu trước khi ghi" \
        "biến rỗng lọt qua \${x:-...} rồi ghi background rỗng"
fi

printf '\n  %d PASS, %d FAIL\n' "$P" "$F"
[ "$F" -eq 0 ]

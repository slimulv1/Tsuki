#!/usr/bin/env bash
# Test cho việc so sánh nội dung dotfile khi thiếu cmp/diff.
#
# VÌ SAO CẦN. install.sh dùng cmp/diff (gói diffutils) ở same_content() để biết
# dotfile đã bị người dùng sửa hay chưa. Đo thì diffutils KHÔNG thuộc `base` và
# KHÔNG thuộc `base-devel`:
#     pacman -Si base-devel  ->  Depends On: ... sed sudo texinfo which
#     (không có diffutils)
# Nó chỉ là phụ thuộc của autoconf/devtools/mkinitcpio/steam. Máy Arch thường đã
# có vì hay cài steam hay devtools; máy tối giản thì không.
#
# Hậu quả đo trên bản sao, PATH cắt bỏ cmp, thư mục dmenu/ GIỐNG HỆT:
#     lan 1:  ! dmenu khác nội dung -> backup: dmenu.tsuki-bak-
#     lan 2:  ! dmenu khác nội dung -> backup: dmenu.tsuki-bak--1
#     lan 3:  ! dmenu khác nội dung -> backup: dmenu.tsuki-bak--2
# Mỗi lần chạy lại `./install.sh dotfiles` lại tạo một backup mới, dồn lên
# trong ~/.config. Dấu vết sai và thư mục phình dần.
#
# KHÔNG mất dữ liệu, và đây là điểm quan trọng: man cmp nói rõ "0 = không khác,
# 1 = có khác, 2 = lỗi", còn thiếu lệnh thì bash trả 127 — cả ba đều khác 0, nên
# hành vi CŨ đã là "coi là khác". Thiếu chỉ là CẢNH BÁO. Vì vậy test đòi hỏi
# canh báo + diffutils trong PKG_BUILD, KHÔNG đòi hỏi đổi mã trả về.
set -u
R=/home/frost-auslese/tsuki
P=0; F=0
ok()  { printf '  PASS  %s\n' "$*"; P=$((P + 1)); }
bad() { printf '  FAIL  %s\n        %s\n' "$*"; F=$((F + 1)); }
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT

# --- trích code thật ---------------------------------------------------------
# `sed -n '/^_TSUKI_NO_DIFFWARNED=0$/,/^}/p'` lấy _require_diffutils; hàm đó nằm
# ngay trên same_content.
{
    sed -n '/^_TSUKI_NO_DIFFWARNED=0$/,/^}/p'      "$R/install.sh"
    sed -n '/^same_content() {/,/^}/p'            "$R/install.sh"
    cat <<'EOS'
warn(){ printf '  ! %s\n' "$*"; }
info(){ printf '  · %s\n' "$*"; }
# Gọi hai lần có chủ đích: phải chứng minh cảnh báo KHÔNG lặp.
if same_content "$1" "$2"; then echo "  KET: giong"; else echo "  KET: khac"; fi
if same_content "$1" "$2"; then echo "  KET: giong"; else echo "  KET: khac"; fi
EOS
} > "$T/sc.sh"
grep -q '^same_content() {' "$T/sc.sh" || {
    printf 'FAIL: không trích được same_content\n'; exit 1; }

# Thư mục giả lập: nội dung GIỐNG HỆT, đúng tình huống đáng lẽ phải im lặng.
mkdir -p "$T/repo/dmenu" "$T/home/.config/dmenu"
printf 'a\n' > "$T/repo/dmenu/a.c"
printf 'b\n' > "$T/repo/dmenu/b.c"
cp -a "$T/repo/dmenu/." "$T/home/.config/dmenu/"

# PATH cắt: chỉ giữ vài lệnh cơ bản, KHÔNG có cmp/diff.
mkdir -p "$T/nb"
for b in bash sh sed grep cat head tail printf; do
    command -v "$b" >/dev/null 2>&1 && ln -sf "$(command -v "$b")" "$T/nb/$b"
done
if env PATH="$T/nb" bash -c 'command -v cmp' >/dev/null 2>&1; then
    bad "C0 môi trường thử" "PATH đã cắt mà vẫn thấy cmp — ca này kiểm không được gì"
else
    ok "C0 PATH thử thực sự không có cmp"
fi

# --- C1: đủ cmp/diff thì so sánh đúng, không cảnh báo gì -------------------
out=$(bash "$T/sc.sh" "$T/repo/dmenu" "$T/home/.config/dmenu" 2>&1)
if printf '%s' "$out" | grep -q 'thiếu cmp/diff'; then
    bad "C1 cảnh báo thiếu cmp khi máy ĐÃ CÓ cmp" "$out"
elif [ "$(printf '%s\n' "$out" | grep -c 'KET: giong')" = 2 ]; then
    ok "C1 đủ cmp/diff: hai lần đều 'giong', không cảnh báo"
else
    bad "C1 so sánh sai khi đủ cmp" "$out"
fi

# --- C2: thiếu cmp thì phải CẢNH BÁO, và nói rõ cách cài -------------------
out=$(env PATH="$T/nb" bash "$T/sc.sh" "$T/repo/dmenu" "$T/home/.config/dmenu" 2>&1)
if printf '%s' "$out" | grep -q 'thiếu cmp/diff'; then
    ok "C2 thiếu cmp/diff: có cảnh báo (trước đây im lặng tạo backup mỗi lần)"
else
    bad "C2 thiếu cmp/diff mà im lặng" "output: $out"
fi
if printf '%s' "$out" | grep -q 'pacman -S diffutils'; then
    ok "C2b cảnh báo kèm lệnh cài đúng gói"
else
    bad "C2b cảnh báo không nói cách cài" "output: $out"
fi

# --- C3: cảnh báo CHỈ MỘT LẦN cho cả lượt chạy ----------------------------
# Nếu không chặn lại, mỗi dotfile in một cặp dòng giống hệt nhau — hàng chục
# dòng nhiễu che mất thông báo thật sự quan trọng.
n_warn=$(printf '%s\n' "$out" | grep -c 'thiếu cmp/diff' || true)
if [ "$n_warn" -eq 1 ]; then
    ok "C3 cảnh báo đúng 1 lần dù gọi same_content 2 lần"
else
    bad "C3 cảnh báo lặp $n_warn lần" "phải chỉ 1 — mỗi dotfile sẽ in lặp nếu không chặn"
fi

# --- C4: vẫn phải coi là KHÁC khi thiếu cmp, không được coi là giống -------
# Đây là điểm an toàn: trả 0 (giống) thì install_dotfile bỏ qua file người dùng
# đã sửa — mất thay đổi thật. Nên khi thiếu lệnh phải trả "khác".
n_khac=$(printf '%s\n' "$out" | grep -c 'KET: khac' || true)
if [ "$n_khac" -eq 2 ]; then
    ok "C4 thiếu cmp: vẫn coi là khác (an toàn), không bỏ qua thay đổi của người dùng"
else
    bad "C4 thiếu cmp mà coi là giống" "output: $out — sẽ bỏ qua dotfile người dùng đã sửa"
fi

# --- C5: diffutils phải nằm trong PKG_BUILD --------------------------------
# Nếu chỉ cảnh báo mà không cài, người dùng phải tự nhớ lệnh. `deps` cài hết
# PKG_BUILD nên thêm vào đó là đủ.
build=$(sed -n '/^readonly PKG_BUILD=(/,/^)/p' "$R/install.sh")
# `( |\))` KHÔNG khớp dòng chỉ có "diffutils" rồi hết dòng — nên phải tính cả
# cuối dòng. Bản đầu thiếu `$` nên C5 đỏ trong khi code ĐÚNG; đã dính.
if printf '%s\n' "$build" | grep -qxE '[[:space:]]*diffutils([[:space:]]|\))?'; then
    ok "C5 diffutils nằm trong PKG_BUILD nên \`deps\` sẽ cài"
else
    bad "C5 thiếu diffutils trong PKG_BUILD" "chỉ cảnh báo thôi, \`deps\` không cài giúp"
fi

# --- C6: bất biến nền — diffutils không thuộc base cũng không thuộc base-devel
# Đây là LÝ DO phải thêm. Nếu sai thì `deps` đang thêm gói thừa vô nghĩa, và
# bài toán "thiếu cmp" thực ra chưa tồn tại. Kiểm bằng chính dữ liệu gói, không
# suy đoán. Bỏ qua nếu máy không có pacman.
if command -v pacman-conf >/dev/null 2>&1; then
    in_base=no; in_devel=no
    pacman -Si base 2>/dev/null | sed -n 's/^Depends On *: *//p' \
        | tr ' ' '\n' | grep -qx diffutils && in_base=CÓ
    pacman -Si base-devel 2>/dev/null | sed -n 's/^Depends On *: *//p' \
        | tr ' ' '\n' | grep -qx diffutils && in_devel=CÓ
    if [ "$in_base" = no ] && [ "$in_devel" = no ]; then
        ok "C6 xác nhận bằng pacman: diffutils không thuộc base, không thuộc base-devel"
    else
        bad "C6 diffutils ĐÃ thuộc base$([ "$in_base" = CÓ ] && echo ' (base)')$([ "$in_devel" = CÓ ] && echo ' (base-devel)')" \
            "thì máy nào chạy pacman cũng có — thêm vào PKG_BUILD là thừa, và cảnh báo là báo động giả"
    fi
else
    printf '  --   bỏ qua C6: không có pacman\n'
fi

# --- C7: cảnh báo KHÔNG được tính vào `warns` của cmd_check ----------------
# Thiếu diffutils thì vẫn cài được hết, chỉ là dấu vết bẩn hơn. Đưa vào `warns`
# sẽ khiến cmd_check kết luận "chưa sẵn sàng" vì thứ không chặn được gì.
cbody=$(sed -n '/^cmd_check() {/,/^}/p' "$R/install.sh")
if printf '%s\n' "$cbody" | grep -q 'so-sánh dotfile: chưa có cmp/diff'; then
    # phải nằm trong nhánh else của một if, tức dùng info chứ không phải warn
    if printf '%s\n' "$cbody" | grep -q 'info "so-sánh dotfile: chưa có cmp/diff'; then
        ok "C7 cmd_check báo cmp/diff bằng info, không tính vào warns"
    else
        bad "C7 nhánh thiếu cmp/diff dùng warn" "sẽ khiến cmd_check kết luận chưa sẵn sàng vì lý do không chặn được gì"
    fi
else
    bad "C7 cmd_check không báo gì về cmp/diff" "không rõ dotfile có đang bị backup thừa không"
fi

printf '\n  %d PASS, %d FAIL\n' "$P" "$F"
[ "$F" -eq 0 ]

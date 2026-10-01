#!/usr/bin/env bash
# Test cho install_dotfile() — đường ghi dotfile của người dùng.
#
# VÌ SAO CẦN. Bản cũ:
#     mv -- "$dst" "$bak"        # giữ file cũ đi chỗ khác
#     cp -a -- "$src" "$dst"     # mới chép file mới vào
# Giữa hai lệnh đó $dst KHÔNG TỒN TẠI, trong khoảng thời gian bằng đúng thời
# gian `cp`. Bị ngắt (Ctrl-C, mất điện, OOM) là cấu hình người dùng biến mất
# khỏi chỗ các app tìm — chỉ còn nằm trong file backup có tên lạ.
#
# Nay: stage vào thư mục tạm CÙNG thư mục đích TRƯỚC, rồi mới đụng $dst, rồi
# rename. Staging hỏng thì $dst còn nguyên vì chưa đụng tới.
#
# Test trích NGUYÊN VĂN install_dotfile từ install.sh, không chép lại logic.
set -u
R=/home/frost-auslese/tsuki
P=0; F=0
ok()  { printf '  PASS  %s\n' "$*"; P=$((P + 1)); }
bad() { printf '  FAIL  %s\n        %s\n' "$*"; F=$((F + 1)); }
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT

fn_src() { sed -n '/^install_dotfile() {/,/^}/p' "$R/install.sh"; }
[ -n "$(fn_src)" ] || { echo "FAIL: không trích được install_dotfile"; exit 1; }

# --- D1: STAGE PHẢI ĐỨNG TRƯỚC khi đụng $dst ---------------------------------
# Đây là bất biến quan trọng nhất, và nó là thứ SỐ THỨ TỰ quyết định — nên kiểm
# bằng số dòng, đúng thứ đọc code thấy. Kiểm bằng hành vi quan sát được thì
# không chứng minh được: may mắn thì vẫn xanh.
_src=$(fn_src)
ln_mktemp=$(printf '%s\n' "$_src" | grep -n 'mktemp -d --' | head -1 | cut -d: -f1)
ln_cp=$(printf '%s\n' "$_src" | grep -n 'cp -a -- "\$src" "\$item"' | head -1 | cut -d: -f1)
ln_mv_dst=$(printf '%s\n' "$_src" | grep -n 'mv -- "\$dst" "\$bak"' | head -1 | cut -d: -f1)
ln_mv_item=$(printf '%s\n' "$_src" | grep -n 'mv -f -- "\$item" "\$dst"' | head -1 | cut -d: -f1)

if [ -z "$ln_mktemp" ] || [ -z "$ln_mv_dst" ]; then
    bad "D1" "không tìm thấy mktemp hoặc mv \$dst — cấu trúc đã đổi, xem lại test"
elif [ "$ln_mktemp" -lt "$ln_mv_dst" ] && [ "$ln_cp" -lt "$ln_mv_dst" ]; then
    ok "D1 stage (mktemp dòng $ln_mktemp, cp dòng $ln_cp) TRƯỚC mv \$dst (dòng $ln_mv_dst)"
else
    bad "D1 thứ tự sai" "mktemp=$ln_mktemp cp=$ln_cp mv_dst=$ln_mv_dst — stage phải trước"
fi
if [ -n "$ln_mv_item" ] && [ "$ln_mv_dst" -lt "$ln_mv_item" ]; then
    ok "D1b đặt vào chỗ bằng rename (mv \$item dòng $ln_mv_item) ngay sau khi giữ bản cũ (dòng $ln_mv_dst)"
else
    bad "D1b" "không thấy mv -f \$item \$dst, hoặc thứ tự sai"
fi
if printf '%s\n' "$_src" | grep -qE '^\s*cp -a -- "\$src" "\$dst"\s*$'; then
    bad "D1c" "vẫn còn cp thẳng vào \$dst — không staging, mất file khi ngắt"
else
    ok "D1c không còn cp thẳng vào \$dst"
fi
# mktemp phải nằm trong thư mục ĐÍCH (cùng filesystem) thì mv mới nguyên tử
if printf '%s\n' "$_src" | grep -q 'mktemp -d -- "\$dstdir/\.tsuki-tmp-XXXXXX"'; then
    ok "D1d thư mục tạm nằm trong \$dstdir (cùng filesystem nên mv là rename nguyên tử)"
else
    bad "D1d" "mktemp không nằm trong thư mục đích — mv qua filesystem khác sẽ thành copy+unlink"
fi

# --- D2: chạy thật trên thư mục tạm ------------------------------------------
run_install() {
    local src=$1 dst=$2
    {
        echo 'ok(){ :; }'
        echo 'info(){ printf "  · %s\n" "$*"; }'
        echo 'warn(){ printf "  ! %s\n" "$*" >&2; }'
        echo 'die(){ printf "  ERR %s\n" "$*" >&2; exit 1; }'
        echo 'readonly GENERATED_FILES=(fish_variables)'
        echo 'readonly COLOR_GENERATED=(dunstrc pywal.conf)'
        echo 'is_generated(){ case " $GENERATED_FILES " in *" $1 "*) return 0;; esac; return 1; }'
        echo 'is_color_generated(){ case " $COLOR_GENERATED " in *" $1 "*) return 0;; esac; return 1; }'
        echo 'color_only_diff(){ return 1; }'
        echo 'strip_colors(){ cat; }'
        echo 'same_content(){ cmp -s -- "$1" "$2"; }'
        echo 'backup_path(){ local p=$1 ts bak n; ts=20260101000000'
        echo '  for n in 0 1 2 3 4 5 6 7 8 9; do'
        echo '    if [ "$n" = 0 ]; then bak="$p.tsuki-bak-$ts"; else bak="$p.tsuki-bak-$ts-$n"; fi'
        echo '    [ -e "$bak" ] || { printf "%s\n" "$bak"; return 0; }; done; return 1; }'
        fn_src
        echo "install_dotfile '$src' '$dst'"
    } > "$T/gen.sh"
    bash "$T/gen.sh" >"$T/o" 2>"$T/e"
}

mkdir -p "$T/home/.config" "$T/repo"
printf 'NOI DUNG MOI tu repo\n' > "$T/repo/dunstrc"
printf 'NOI DUNG CU cua nguoi dung\n' > "$T/home/.config/dunstrc"

run_install "$T/repo/dunstrc" "$T/home/.config/dunstrc"
if [ "$(cat "$T/home/.config/dunstrc" 2>/dev/null)" = "NOI DUNG MOI tu repo" ]; then
    ok "D2 nội dung mới đã được đặt vào chỗ"
else
    bad "D2 chưa đặt nội dung mới" "đọc được: [$(cat "$T/home/.config/dunstrc" 2>/dev/null)]"
fi
if ls "$T/home/.config"/dunstrc.tsuki-bak-* >/dev/null 2>&1; then
    ok "D3 bản cũ được giữ lại thành backup"
else
    bad "D3 không có file backup" "$(ls "$T/home/.config")"
fi
# không sót thư mục tạm
if ls -d "$T/home/.config"/.tsuki-tmp-* >/dev/null 2>&1; then
    bad "D4 sót thư mục tạm" "$(ls -d "$T/home/.config"/.tsuki-tmp-*)"
else
    ok "D4 không sót thư mục tạm .tsuki-tmp-*"
fi

# --- D5: STAGING HỎNG thì $dst phải còn nguyên ---------------------------------
# Dùng nguồn LÀ THƯ MỤC KHÔNG ĐỌC được? Không dùng được (chủ sở hữu vẫn đọc).
# Dùng cách chắc chắn hơn: nguồn tự biến mất giữa lúc chạy không kịp — thay vào
# đó kiểm điều kiện tiên quyết: nếu mktemp thất bại (thư mục đích không ghi
# được) thì hàm phải trả về 1 và ĐỂ NGUYÊN file cũ.
mkdir -p "$T/ro" "$T/ro2"
printf 'CON NGUYEN\n' > "$T/ro/dunstrc"
chmod 555 "$T/ro"
run_install "$T/repo/dunstrc" "$T/ro/dunstrc"
if [ "$(cat "$T/ro/dunstrc" 2>/dev/null)" = "CON NGUYEN" ]; then
    ok "D5 thư mục đích không ghi được: file cũ GIỮ NGUYÊN, không bị mất"
else
    bad "D5 mất file cũ khi staging hỏng" "đọc được: [$(cat "$T/ro/dunstrc" 2>/dev/null)]"
fi
if ls "$T/ro"/dunstrc.tsuki-bak-* >/dev/null 2>&1; then
    bad "D5b đã giữ bản cũ đi dù staging hỏng" "$(ls "$T/ro")"
else
    ok "D5b staging hỏng thì không đụng file cũ (không tạo backup thừa)"
fi
chmod 755 "$T/ro"

# --- D6: chạy lại với nội dung giống nhau -> không spam backup ----------------
printf 'NOI DUNG MOI tu repo\n' > "$T/home/.config/dunstrc"
run_install "$T/repo/dunstrc" "$T/home/.config/dunstrc"
n=$(ls "$T/home"/.config/dunstrc.tsuki-bak-* 2>/dev/null | wc -l)
if [ "$n" -le 1 ]; then
    ok "D6 nội dung giống nhau: không tạo backup thêm (tổng $n bản)"
else
    bad "D6 sinh backup thừa" "$n bản cho một nội dung không đổi"
fi

printf '\n  %d PASS, %d FAIL\n' "$P" "$F"
[ "$F" -eq 0 ]

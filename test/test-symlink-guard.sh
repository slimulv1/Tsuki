#!/usr/bin/env bash
# Test cho symlink_guard — bảo vệ file đích là symlink trong .xinitrc và .Xresources.
#
# VÌ SAO CẦN. `cat > "$f"` và `printf >> "$f"` đi QUA symlink: chúng mở đường
# dẫn rồi ghi vào file ĐÍCH. Đo trên bản sao trong test này, trước khi sửa:
#   ~/.xinitrc -> ~/dot/xinitrc
#   cp -a ~/.xinitrc ~/.xinitrc.tsuki-bak-<giây>  -> backup là symlink trỏ về
#                                                    ~/dot/xinitrc
#   cat > ~/.xinitrc <<EOF ... EOF                 -> ghi đè ~/dot/xinitrc
#   -> nội dung gốc mất, MÀ backup trỏ tới chính file vừa bị ghi đè. Khôi
#   phục cũng vô ích: mất cấu hình và mất đường khôi phục cùng lúc.
#
# install_dotfile KHÔNG dính: nó dùng `mv` (thay chính symlink) chứ không phải
# redirection. Nên phải sửa riêng .xinitrc và .Xresources.
#
# Test trích NGUYÊN VĂN symlink_guard/write_xinitrc/install_xresources, chỉ thay
# $TSUKI_HOME/$REPO_DIR bằng thư mục tạm. Không chạm nhà thật, không cần root.
set -u
R=/home/frost-auslese/tsuki
P=0; F=0
ok()  { printf '  PASS  %s\n' "$*"; P=$((P + 1)); }
bad() { printf '  FAIL  %s\n        %s\n' "$*"; F=$((F + 1)); }
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT

# --- trích code thật ---------------------------------------------------------
# `confirm` bị gọi bởi symlink_guard; bản thật đọc từ stdin nên ở test này thay
# bằng bản đọc $REPLY. Tự thừa nhận đây là chỗ DUY NHẤT lệch: phần quyết định
# có hỏi hay không nằm trong symlink_guard, không nằm trong confirm.
{
    sed -n '/^tilde() {/,/^}/p'              "$R/install.sh"
    sed -n '/^backup_path() {/,/^}/p'        "$R/install.sh"
    sed -n '/^symlink_guard() {/,/^}/p'      "$R/install.sh"
    sed -n '/^write_xinitrc() {/,/^}/p'      "$R/install.sh"
    sed -n '/^install_xresources() {/,/^}/p' "$R/install.sh"
    cat <<'EOS'
step(){ printf '  == %s\n' "$*"; }
ok(){ printf '  ✓ %s\n' "$*"; }
info(){ printf '  · %s\n' "$*"; }
warn(){ printf '  ! %s\n' "$*"; }
die(){ printf '  error: %s\n' "$*"; exit 1; }
confirm(){ printf '  [hỏi] %s -> %s\n' "$1" "${REPLY:-n}"; [[ ${REPLY:-n} == y ]]; }
# Rồi gọi đúng hàm cần thử. Bản đầu quên dòng này: script chạy, exit 0, không
# in gì, và mọi ca hỏi hành vi đều xanh/trống theo cách vô nghĩa.
"${FUNC:-write_xinitrc}"
EOS
} > "$T/lib.sh"
for f in symlink_guard write_xinitrc install_xresources backup_path; do
    grep -q "^${f}() {" "$T/lib.sh" || {
        printf 'FAIL: không trích được %s\n' "$f"; exit 1; }
done

# Dựng nhà giả: symlink ~/.xinitrc -> kho dotfiles, y như cách người dùng thật
# tổ chức file.
new_home() {   # new_home <tên> -> in đường dẫn $T/<tên>
    local n=$1
    mkdir -p "$T/$n" "$T/$n-dot"
    printf '# xinitrc trong kho dotfiles\n# dong tuy chinh\n' > "$T/$n-dot/xinitrc"
    ln -s "$T/$n-dot/xinitrc" "$T/$n/.xinitrc"
    printf '%s\n' "$T/$n"
}

# --- C1: symlink + trả lời "không" thì KHÔNG được đụng file kho dotfiles ------
# Đây là ca quan trọng nhất. Không có nó thì install.sh âm thầm sửa file của
# người dùng ở nơi họ không nhìn thấy.
H=$(new_home h1)
md5_before=$(md5sum "$T/h1-dot/xinitrc" | cut -d' ' -f1)
out=$(TSUKI_HOME="$H" REPO_DIR="$R" REPLY=n bash "$T/lib.sh" 2>&1)
md5_after=$(md5sum "$T/h1-dot/xinitrc" | cut -d' ' -f1)
if [ "$md5_before" = "$md5_after" ]; then
    ok "C1 trả lời 'không': file trong kho dotfiles giữ nguyên"
else
    bad "C1 ghi đè cả khi người dùng nói không" \
        "md5 $md5_before -> $md5_after"
fi
if [ -L "$H/.xinitrc" ]; then
    ok "C1b trả lời 'không': symlink còn nguyên (không bị thay bằng file thật)"
else
    bad "C1b symlink bị phá" "$(ls -l "$H/.xinitrc")"
fi

# --- C2: có hỏi trước không, và nói rõ sẽ sửa file nào ----------------------
# Không hỏi thì "giữ nguyên" ở C1 chỉ là may mắn do lỗi khác, không phải do
# thiết kế. Thông báo phải chỉ đích thật, không chỉ "~/.xinitrc".
if printf '%s' "$out" | grep -q 'là symlink'; then
    ok "C2 báo cho biết đích là symlink, không im lặng"
else
    bad "C2 không báo gì về symlink" "output: $out"
fi
if printf '%s' "$out" | grep -q "h1-dot/xinitrc"; then
    ok "C2b nêu đích thật (kho dotfiles), không chỉ nói '~/.xinitrc'"
else
    bad "C2b không nêu đường dẫn thật" "output: $out"
fi

# --- C3: trả lời "có" thì backup phải chứa NỘI DUNG GỐC, không phải symlink --
# Đây là lỗi gốc: `cp -a` chép CON TRỎ. Backup trỏ tới chính file sắp bị ghi
# đè nên không khôi phục được gì. `cp -aL` mới lưu nội dung.
H=$(new_home h2)
out=$(TSUKI_HOME="$H" REPO_DIR="$R" REPLY=y bash "$T/lib.sh" 2>&1)
baks=("$H"/.xinitrc.tsuki-bak-*)
((${#baks[@]})) || { bad "C3 không tạo backup nào" "$out"; }
real=0
for b in "${baks[@]}"; do
    [ -e "$b" ] || continue
    if [ -L "$b" ]; then
        bad "C3 backup là symlink" "$(basename "$b") trỏ tới $(readlink "$b") — file đó vừa bị ghi đè"
    elif grep -q 'kho dotfiles' "$b"; then
        real=$((real + 1))
    else
        bad "C3 backup có nhưng sai nội dung" "$(basename "$b"): $(head -1 "$b")"
    fi
done
[ "$real" -gt 0 ] && ok "C3 backup chứa nội dung gốc (file thật, không phải symlink)"

# --- C4: ghi xong thì nội dung mới thật sự nằm ở file đích ------------------
# Nếu C3 đạt mà C4 không, nghĩa là backup đúng nhưng ghi sai chỗ.
if grep -q 'Tsuki install.sh' "$T/h2-dot/xinitrc"; then
    ok "C4 sau khi ghi, file kho dotfiles chứa nội dung .xinitrc mới"
else
    bad "C4 không ghi được vào file đích" "$(head -1 "$T/h2-dot/xinitrc")"
fi

# --- C5: KHÔNG phải symlink thì hành vi cũ giữ nguyên ------------------------
# Chống hồi quy: thêm guard mà làm hỏng đường thường thì vô nghĩa.
mkdir -p "$T/h3"
printf '# xinitrc cua toi\n' > "$T/h3/.xinitrc"
out=$(TSUKI_HOME="$T/h3" REPO_DIR="$R" REPLY=n bash "$T/lib.sh" 2>&1)
if printf '%s' "$out" | grep -q 'Xresources là symlink'; then
    bad "C5 hỏi cả khi file thường" "output: $out"
elif grep -q 'Tsuki install.sh' "$T/h3/.xinitrc"; then
    ok "C5 file thường: vẫn ghi bình thường, không hỏi thừa"
else
    bad "C5 file thường mà không ghi được" "$(head -1 "$T/h3/.xinitrc")"
fi
# Và vẫn phải backup nội dung gốc của file thường.
found=0
for b in "$T"/h3/.xinitrc.tsuki-bak-*; do
    [ -e "$b" ] || continue
    grep -q 'xinitrc cua toi' "$b" && found=1
done
[ "$found" -eq 1 ] && ok "C5b file thường vẫn được backup nội dung gốc" \
                  || bad "C5b mất nội dung gốc khi backup file thường"

# --- C6: .Xresources cũng phải được bảo vệ ---------------------------------
# Ở đây còn NẶNG hơn .xinitrc: nhánh "đã có .Xresources nhưng chưa có Xcursor"
# gọi `printf >> "$f"` mà KHÔNG gọi backup_path — tức nối thêm vào file của
# người dùng mà không để lại dấu vết nào. Không có guard thì mất luôn.
mkdir -p "$T/h4" "$T/h4-dot" "$T/repo"
printf '! XTerm*Font: fixed\n' > "$T/h4-dot/Xresources"
ln -s "$T/h4-dot/Xresources" "$T/h4/.Xresources"
printf 'Xcursor: /usr/share/icons/x\nXcursor.size: 24\n' > "$T/repo/.Xresources"
md5_before=$(md5sum "$T/h4-dot/Xresources" | cut -d' ' -f1)
out=$(TSUKI_HOME="$T/h4" REPO_DIR="$T/repo" REPLY=n FUNC=install_xresources bash "$T/lib.sh" 2>&1)
md5_after=$(md5sum "$T/h4-dot/Xresources" | cut -d' ' -f1)
if [ "$md5_before" = "$md5_after" ]; then
    ok "C6 .Xresources symlink, trả lời 'không': không nối thêm vào file kho dotfiles"
else
    bad "C6 .Xresources bị sửa khi người dùng nói không" "md5 $md5_before -> $md5_after"
fi
# Trả lời có: phải có backup nội dung gốc, và nội dung mới phải tới đúng chỗ.
mkdir -p "$T/h5" "$T/h5-dot"
printf '! XTerm*Font: fixed\n' > "$T/h5-dot/Xresources"
ln -s "$T/h5-dot/Xresources" "$T/h5/.Xresources"
TSUKI_HOME="$T/h5" REPO_DIR="$T/repo" REPLY=y FUNC=install_xresources bash "$T/lib.sh" >/dev/null 2>&1
kept=0
for b in "$T"/h5/.Xresources.tsuki-bak-*; do
    [ -e "$b" ] && [ ! -L "$b" ] && grep -q 'XTerm' "$b" && kept=1
done
[ "$kept" -eq 1 ] && ok "C6b .Xresources: backup giữ được nội dung gốc khi symlink" \
                  || bad "C6b .Xresources không backup được nội dung gốc"
grep -q 'Xcursor' "$T/h5-dot/Xresources" \
    && ok "C6c .Xresources: ghi xong thì Xcursor tới đúng file đích" \
    || bad "C6c .Xresources: không ghi được Xcursor vào file đích"

# --- C6d: backup .Xresources cũng phải dùng -L ------------------------------
# Ca này bắt được lỗi tôi tự nhận: tôi bảo nhánh "đã có .Xresources nhưng chưa có
# Xcursor" không gọi backup_path. SAI — nó có gọi. Lỗi thật là `cp -a` chỉ chép
# con trỏ. Nên phải kiểm `-L`, không kiểm "có gọi backup_path không".
xbody=$(sed -n '/^install_xresources() {/,/^}/p' "$R/install.sh")
if printf '%s\n' "$xbody" | grep -qE 'cp -aL -- .*\$f.*\$bak'; then
    ok "C6d backup .Xresources dùng cp -aL (lưu nội dung, không chép con trỏ)"
else
    bad "C6d backup .Xresources không dùng -L" \
        "cp -a chỉ chép symlink — backup trỏ tới file sắp bị nối thêm"
fi

# --- C7: cấu trúc — mọi redirection vào $TSUKI_HOME phải qua guard ----------
# Kiểm theo CẤU TRÚC vì hành vi phụ thuộc người dùng trả lời gì, khó quan
# sát hết. Hai chỗ redirection này là chỗ duy nhất đi qua symlink.
for fn in write_xinitrc install_xresources; do
    body=$(sed -n "/^${fn}() {/,/^}/p" "$R/install.sh")
    if printf '%s\n' "$body" | grep -q 'symlink_guard'; then
        ok "C7 $fn gọi symlink_guard trước khi ghi"
    else
        bad "C7 $fn không gọi symlink_guard" "sẽ ghi đè file trong kho dotfiles của người dùng"
    fi
done
# Và backup phải dùng -L, không dùng cp -a trần trong write_xinitrc.
wbody=$(sed -n '/^write_xinitrc() {/,/^}/p' "$R/install.sh")
if printf '%s\n' "$wbody" | grep -qE 'cp -aL -- .*\.xinitrc'; then
    ok "C7b backup .xinitrc dùng cp -aL (lưu nội dung, không chép con trỏ)"
else
    bad "C7b backup .xinitrc không dùng -L" "cp -a chỉ chép symlink — backup trỏ tới file sắp bị ghi đè"
fi

# --- C8: không có terminal (chạy từ cron/systemd) thì KHÔNG ghi --------------
# confirm thật khi không có terminal tự chọn theo mặc định. Mặc định của câu
# hỏi này phải là "không": tự ý sửa kho dotfiles khi không ai ngồi trước máy
# thì tệ hơn nhiều so với bỏ qua.
gbody=$(sed -n '/^symlink_guard() {/,/^}/p' "$R/install.sh")
if printf '%s\n' "$gbody" | grep -q 'confirm "vẫn ghi đè file đích?" n'; then
    ok "C8 mặc định khi không có terminal là KHÔNG ghi"
else
    bad "C8 mặc định sai" "câu hỏi phải là 'vẫn ghi đè file đích?' với mặc định n"
fi

printf '\n  %d PASS, %d FAIL\n' "$P" "$F"
[ "$F" -eq 0 ]

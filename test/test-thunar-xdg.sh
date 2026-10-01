#!/usr/bin/env bash
# Test cho phần Thunar của install.sh: menu giải nén, thùng rác, thư mục chuẩn.
#
# BA NGUYÊN NHÂN, đo riêng từng cái (đều là thiếu gói, không phải hỏng config):
#
# 1. Chuột phải không có "Extract Here"
#    -> thunar-archive-plugin CHƯA CÀI. Nhưng KHÔNG ĐỦ: plugin không gọi 7z.
#    Đọc mã nguồn (xfce-mirror/thunar-archive-plugin, tap-backend.c:349-378): nó
#    dò file wrapper `LIBEXECDIR/thunar-archive-plugin/<basename>.tap` cho mỗi
#    app đăng ký với mime type, và loại app nào không có wrapper. Repo chính thức
#    CHỈ có 4 wrapper: ark.tap, engrampa.tap, file-roller.tap, peazip.tap —
#    KHÔNG có 7z.tap. Nên cài 7z không tạo được menu này.
#
# 2. Sidebar không có "Thùng rác"
#    -> gvfs chưa cài. ArchWiki (title/Thunar): "If installed, Thunar will show
#    the trash can, removable media, and remote filesystems (mtp/smb)".
#    Lưu ý `gio trash` CÓ chạy được (glib2 có sẵn) — đo trên nhà thật, exit 0 và
#    tạo ~/.local/share/Trash. Vậy backend không hỏng, chỉ thiếu phần hiện UI.
#
# 3. Không có ~/Documents, ~/Videos, ~/Music...
#    -> đo trước khi sửa: `xdg-user-dir DOCUMENTS` trả về `$HOME`, tức cả tám
#    mục trỏ về cùng một chỗ, vì ~/.config/user-dirs.dirs chưa tồn tại. Desktop
#    này có sẵn Documents/Downloads/Music/Pictures/Projects/Public/Templates/
#    Videos trong /etc/xdg/user-dirs.conf, nên gọi xdg-user-dirs-update là đủ.
#
# Test trích NGUYÊN VĂN mảng gói và hàm từ install.sh. Chỉ đọc, không cài gì.
set -u
R=/home/frost-auslese/tsuki
P=0; F=0
ok()  { printf '  PASS  %s\n' "$*"; P=$((P + 1)); }
bad() { printf '  FAIL  %s\n        %s\n' "$*"; F=$((F + 1)); }
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT

# --- trích code thật ---------------------------------------------------------
sed -n '/^cmd_userdirs() {/,/^}/p' "$R/install.sh" > "$T/ud.sh"
[ -s "$T/ud.sh" ] || { printf 'FAIL: không trích được cmd_userdirs\n'; exit 1; }

# Danh sách 9 mục — lấy từ CHÍNH CÁCH ĐẾM trong install.sh, không hardcode ở đây.
mapfile -t DIRS < <(grep -oE '\b(Desktop|Documents|Downloads|Music|Pictures|Projects|Public|Templates|Videos)\b' \
                     "$T/ud.sh" | sort -u)
if ((${#DIRS[@]} != 9)); then
    bad "C0 danh sách thư mục" "trích được ${#DIRS[@]}/9 từ cmd_userdirs"
else
    ok "C0 cmd_userdirs biết đủ 9 thư mục chuẩn (${DIRS[*]})"
fi

# --- C1: PKG_SESSION phải có plugin + app GUI + gvfs ------------------------
# Kiểm theo CẤU TRÚC mảng vì máy test chưa cài nên không kiểm được bằng
# `command -v`. Sourcing mảng thật, không parse bằng grep (có comment).
sed -n '/^readonly PKG_SESSION=(/,/^)/p' "$R/install.sh" > "$T/sess.sh"
[ -s "$T/sess.sh" ] || { printf 'FAIL: không trích được PKG_SESSION\n'; exit 1; }
{ cat "$T/sess.sh"; echo 'printf "%s\n" "${PKG_SESSION[@]}"'; } > "$T/dump.sh"
mapfile -t SESS < <(bash "$T/dump.sh" 2>/dev/null)

for p in thunar-archive-plugin file-roller gvfs; do
    if printf '%s\n' "${SESS[@]}" | grep -qx "$p"; then
        ok "C1 PKG_SESSION có $p"
    else
        bad "C1 PKG_SESSION thiếu $p" "hiện có ${#SESS[@]} gói, không thấy $p"
    fi
done

# --- C2: file-roller phải có thật trong kho --------------------------------
# Plugin tìm wrapper theo tên app. Wrapper có sẵn cho đúng 4 app: ark, engrampa,
# file-roller, peazip. Nếu đổi sang app khác thì menu sẽ không hiện dù plugin có.
if pacman -Si file-roller >/dev/null 2>&1; then
    ok "C2 file-roller có trong kho (ứng với file-roller.tap)"
else
    bad "C2 file-roller không có trong kho" "plugin sẽ không tìm thấy wrapper"
fi
# Và 4 app trong danh sách đó phải còn ứng dụng — đây là ràng buộc của plugin.
for a in ark engrampa file-roller peazip; do
    pacman -Si "$a" >/dev/null 2>&1 || {
        bad "C2b app không có wrapper: $a" "repo plugin chỉ có ark/engrampa/file-roller/peazip"
    }
done
ok "C2b cả 4 app có wrapper trong plugin vẫn tồn tại trong kho"

# --- C3: chú thích phải nói rõ 7z KHÔNG tạo được menu ----------------------
# Đây là chỗ tôi đã khuyên sai ở lượt trước (loại trừ app GUI vì "thừa cho dwm").
# Nếu ai đó đọc lại và tưởng 7z là đủ, họ sẽ cài 7z rồi thấy menu không hiện.
sess_txt=$(cat "$T/sess.sh")
# NHAY KÉP + `grep -F`: mẫu chứa backtick, và trong shell backtick là lệnh
# thế. Bản đầu tôi viết `grep -q 'KHÔNG có `7z.tap`'` — bash thử chạy `7z.tap`
# ("command not found") rồi so khớp chuỗi rỗng, nên C3 đỏ khi code ĐÚNG.
if printf '%s' "$sess_txt" | grep -qF 'KHÔNG có `7z.tap`'; then
    ok "C3 chú thích ghi rõ plugin không dùng 7z (chống hiểu nhầm như tôi đã hiểu sai)"
else
    bad "C3 chú thích không nói 7z không tạo được menu" \
        "người đọc sẽ cài 7z rồi tưởng xong"
fi

# --- C4: cmd_userdirs chạy THẬT trên nhà giả, phải tạo đủ 9 mục -----------
# Đây là ca chứng minh hành vi, không phải cấu trúc. Dùng HOME giả nên nhà thật
# không bị đụng.
{
    cat "$T/ud.sh"
    cat <<'EOS'
step(){ printf '  == %s\n' "$*"; }
ok(){ printf '  + %s\n' "$*"; }
warn(){ printf '  ! %s\n' "$*"; }
info(){ printf '  · %s\n' "$*"; }
TSUKI_HOME="$HOME"
cmd_userdirs
EOS
} > "$T/go.sh"
H="$T/home"; mkdir -p "$H"
out=$(env HOME="$H" bash "$T/go.sh" 2>&1)
n=0
for d in "${DIRS[@]}"; do [[ -d $H/$d ]] && n=$((n + 1)); done
if (( n == 9 )); then
    ok "C4 chạy thật: tạo đủ $n/9 thư mục"
else
    bad "C4 chỉ tạo $n/9 thư mục" "$out"
fi

# --- C5: ghi được user-dirs.dirs, và xdg-user-dir trả đúng đường dẫn -------
# Đây là phần cốt lõi. Không có file này thì `xdg-user-dir` trả về $HOME cho mọi
# mục — đó chính là lý do sidebar không hiện gì (đo trước khi sửa).
if [ -f "$H/.config/user-dirs.dirs" ]; then
    ok "C5 đã ghi ~/.config/user-dirs.dirs"
else
    bad "C5 không ghi user-dirs.dirs" "xdg-user-dir sẽ tiếp tục trả về \$HOME"
fi
# Gọi xdg-user-dir VỚI HOME giả để đọc đúng file vừa sinh.
bad_dirs=""
for d in DESKTOP DOCUMENTS DOWNLOAD MUSIC PICTURES PROJECTS PUBLICSHARE TEMPLATES VIDEOS; do
    got=$(env HOME="$H" xdg-user-dir "$d" 2>/dev/null)
    if [ "$got" = "$H" ] || [ -z "$got" ]; then
        bad_dirs+=" $d"
    fi
done
if [ -z "$bad_dirs" ]; then
    ok "C5b cả 9 biến XDG trỏ đúng thư mục, không còn trỏ về \$HOME"
else
    bad "C5b biến XDG vẫn trỏ sai" "$bad_dirs"
fi

# --- C6: không đụng nội dung thư mục đã có --------------------------------
# Chạy lần hai trên nhà đã có dữ liệu: phải giữ nguyên file.
mkdir -p "$H/Pictures"
printf 'anh cu\n' > "$H/Pictures/hinh.png"
env HOME="$H" bash "$T/go.sh" >/dev/null 2>&1
if [ -f "$H/Pictures/hinh.png" ] && [ "$(cat "$H/Pictures/hinh.png")" = "anh cu" ]; then
    ok "C6 chạy lại không xoá nội dung thư mục đã có"
else
    bad "C6 mất dữ liệu trong thư mục cũ" "Pictures/hinh.png bị mất hoặc đổi"
fi

# --- C7: phải chạy SAU cmd_dotfiles trong `all` ----------------------------
# Nếu chạy trước, install_dotfile có thể stage vào thư mục vừa sinh rồi dọn đi.
main_fn=$(sed -n '/^main() {/,/^}/p' "$R/install.sh")
# BỎ DÙNG DÒNG COMMENT — bản đầu grep thẳng cả khối nên dính chú thích.
all_code=$(printf '%s\n' "$main_fn" |
           sed -n '/^        all)/,/^            ;;/p' |
           grep -vE '^[[:space:]]*#')
i_dot=$(printf '%s\n' "$all_code" | grep -n 'cmd_dotfiles' | head -1 | cut -d: -f1)
i_ud=$(printf '%s\n' "$all_code" | grep -n 'cmd_userdirs' | head -1 | cut -d: -f1)
if [ -z "$i_ud" ]; then
    bad "C7 `all` không gọi cmd_userdirs" "chạy \`all\` thì thư mục chuẩn không được tạo"
elif [ -z "$i_dot" ]; then
    bad "C7 không tìm thấy cmd_dotfiles để so thứ tự" "có thể cấu trúc `all` đã đổi"
elif [ "$i_ud" -gt "$i_dot" ]; then
    ok "C7 cmd_userdirs chạy sau cmd_dotfiles (thứ tự đúng)"
else
    bad "C7 cmd_userdirs chạy TRƯỚC cmd_dotfiles" "install_dotfile có thể stage vào thư mục vừa sinh rồi dọn đi"
fi

# --- C8: không dùng --force, không chặn cứng -------------------------------
# --force ghi đè lựa chọn trong ~/.config/user-dirs.conf (người dùng có thể đã
# đổi tên thư mục). Không chặn cứng vì người dùng có thể cố ý bỏ bớt thư mục.
# Chỉ xét CODE, không xét comment. Bản đầu grep cả file nên dính đúng dòng
# chú thích "# KHÔNG dùng `--force`" và báo đỏ trong khi code đúng — lặp lại
# đúng lỗi lần trước. `grep -F` + bỏ dòng `#` + `grep --` để không bị hiểu
# `--force` là tuỳ chọn của grep.
ud_code=$(grep -vE '^[[:space:]]*#' "$T/ud.sh")
if printf '%s' "$ud_code" | grep -qF -- '--force'; then
    bad "C8 dùng --force" "sẽ ghi đè lựa chọn cục bộ của người dùng"
else
    ok "C8 không dùng --force, giữ lựa chọn cục bộ"
fi
if grep -qE '^\s*die\b' "$T/ud.sh"; then
    bad "C8b cmd_userdirs chết cứng khi thư mục thiếu" "người dùng có thể cố ý bỏ bớt thư mục"
else
    ok "C8b thiếu thư mục thì cảnh báo, không chết cứng"
fi

# --- C9: lệnh phải có trong --help ------------------------------------------
if ./install.sh --help 2>/dev/null | grep -q 'install.sh userdirs'; then
    ok "C9 --help có liệt kê ./install.sh userdirs"
else
    bad "C9 --help thiếu \`userdirs\`" "usage() rút từ khối comment đầu file"
fi
if printf '%s\n' "$main_fn" | grep -q 'userdirs)  cmd_userdirs'; then
    ok "C9b có lệnh riêng trong case"
else
    bad "C9b không có nhánh userdirs" "không gọi được bằng lệnh riêng"
fi

printf '\n  %d PASS, %d FAIL\n' "$P" "$F"
[ "$F" -eq 0 ]

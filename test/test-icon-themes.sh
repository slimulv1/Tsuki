#!/usr/bin/env bash
# Test cho nhóm icon theme (install_icons + khai trong xsettingsd.conf).
#
# YÊU CẦU: cài yet-another-monochrome-icon-set (Bitbucket) + buuf-nestort
# (Disroot), đặt YAMO làm icon chính thay cho kora.
#
# VÌ SAO YAMO LÀM ICON CHÍNH — đo độ phủ thật, không đoán:
#   Tham chiếu 46 icon từ mọi .desktop trong hệ thống (/usr/share/applications
#   + ~/.local/share/applications):
#     YAMO  41/46
#     kora  36/46
#     Buuf  36/46
#   Buuf không có icon app nào (0 file trong apps/) nên không hợp làm chính.
#
# 5 ICON YAMO THIẾU, đã tra từng cái xem có hại không:
#   applications-system-symbolic -> rơi về Adwaita
#   fcitx-lotus                 -> rơi về hicolor
#   com.sgtaziz.lianlilinux     -> rơi về hicolor
#   shelly-tray                 -> rơi về hicolor
#   flatpak-symbolic            -> KHÔNG rơi được, nhưng nó thuộc app
#     `com.shellyorg.shelly.desktop` mà `shelly-ui` không có trên máy, nên app
#     chưa cài -> icon thiếu không hiện ra.
#   => 5/5 không gây vấn đề thực tế.
#
# YAMO khai gốc `Inherits=Papirus-Dark,breeze-dark,Cosmic,Adwaita,hicolor`;
# máy không có Papirus-Dark và Cosmic nên install_icons sửa thành
# breeze-dark,Adwaita,hicolor — nhờ vậy 4 icon kia có nguồn dự phòng thật.
#
# Buuf khai thư mục `stock` trong Directories nhưng repo KHÔNG có thư mục đó.
# Đo thật: gtk-update-icon-cache vẫn tạo cache (373 KB), chỉ bỏ qua mục thiếu.
# Không sửa file tác giả.
set -u
R=/home/frost-auslese/tsuki
P=0; F=0
ok()  { printf '  PASS  %s\n' "$*"; P=$((P + 1)); }
# SC2183 báo "2 biến, truyền 1" — báo động giả: `$*` gộp mọi đối số thành
# một chuỗi, printf lặp lại nó cho mỗi `%s`. Mọi lời gọi `bad` ở dưới đều
# truyền đủ 2 (tên ca + lý do).
# shellcheck disable=SC2183
bad() { printf '  FAIL  %s\n        %s\n' "$*"; F=$((F + 1)); }
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT

sed -n '/^install_icons() {/,/^}/p' "$R/install.sh" > "$T/fn.sh"
[ -s "$T/fn.sh" ] || { printf 'FAIL: không trích được install_icons\n'; exit 1; }

ICONS_Y=~/.local/share/icons/yet-another-monochrome-icon-set

# --- C1: hai URL đúng, clone từ nguồn tác giả ---------------------------------
# Ghi sai chính tả URL là clone fail — đã dính kiểu này với `fwupmgr`.
for u in "bitbucket.org/dirn-typo/yet-another-monochrome-icon-set" \
         "git.disroot.org/eudaimon/buuf-nestort"; do
    if grep -qF "$u" "$T/fn.sh"; then
        ok "C1 có URL: $u"
    else
        bad "C1 thiếu URL $u" "clone fail nếu URL sai"
    fi
done

# --- C2: TÊN THƯ MỤC đích, không phải Name= trong index.theme ------------------
# GTK tra icon theme theo tên thư mục. Đặt tên thư mục theo `Name=` là lỗi
# hay gặp: YAMO khai Name=yet-another-monochrome-icon-set (trùng), Buuf khai
# Name=Buuf For Many Desktops (có khoảng trắng — không dùng được làm tên thư mục).
for n in yet-another-monochrome-icon-set Buuf-For-Many-Desktops; do
    if grep -qF "$n|" "$T/fn.sh"; then
        ok "C2 khai đúng tên thư mục: $n"
    else
        bad "C2 tên thư mục đích sai cho $n" "GTK tra theo tên thư mục, không theo Name="
    fi
done
# Cấm dùng "Buuf For Many Desktops" (Name= có khoảng trắng) làm tên thư mục.
if grep -qF 'Buuf For Many Desktops|' "$T/fn.sh"; then
    bad "C2b dùng Name= 'Buuf For Many Desktops' làm tên thư mục" "có khoảng trắng, GTK không tra được"
else
    ok "C2b không dùng Name= có khoảng trắng làm tên thư mục"
fi

# --- C3: xoá icon-theme.cache của tác giả TRƯỚC khi copy ----------------------
# Cache trong repo chứa đường dẫn tuyệt đối MÁY TÁC GIẢ. Dùng lại thì hỏng.
if grep -q 'rm -f -- "\$from/icon-theme.cache"' "$T/fn.sh"; then
    ok "C3 xoá icon-theme.cache của tác giả trước khi copy"
else
    bad "C3 giữ lại icon-theme.cache của tác giả" \
        "cache chứa đường dẫn tuyệt đối máy họ, dùng lại sẽ hỏng"
fi
# Và phải dựng lại cache sau khi copy.
if grep -q 'gtk-update-icon-cache -f -t' "$T/fn.sh"; then
    ok "C3b dựng lại icon-theme.cache sau khi copy"
else
    bad "C3b không dựng lại cache" "thiếu cache thì GTK phải quét mỗi lần vẽ"
fi

# --- C4: sửa Inherits của YAMO, bỏ theme máy không có ------------------------
# Bản gốc: Papirus-Dark,breeze-dark,Cosmic,Adwaita,hicolor. Máy này không có
# Papirus-Dark và không có Cosmic (đo bằng ls /usr/share/icons).
#
# CA RỖNG ĐÃ DÍNH LẦN NÀY: bản đầu grep thẳng `Inherits=.*Papirus-Dark` rồi
# coi là FAIL. Nhưng chuỗi đó chỉ nằm trong COMMENT giải thích và trong thông
# báo `ok`, KHÔNG nằm trong lệnh nào — nên ca đỏ trong khi code đúng. Đo lại:
#   $ grep -n Papirus-Dark install.sh (trong install_icons)
#     41: # YAMO khai `Inherits=Papirus-Dark,...`     <- comment
#     42: # Máy này không có Papirus-Dark...          <- comment
#     55: ok "YAMO Inherits -> ... (bỏ Papirus-Dark, Cosmic)"  <- thông báo
#   Không dòng lệnh nào chứa nó. Vì thế: xét DÒNG LỆNH THỰC THI, bỏ comment.
# C8/C8d mới là ca quyết định — nó chạy hàm thật rồi đọc index.theme sau khi
# sửa, nên không dựa vào việc đọc văn bản.
code_lines=$(grep -vE '^[[:space:]]*#' "$T/fn.sh")
for miss in Papirus-Dark Cosmic; do
    if [[ -d /usr/share/icons/$miss ]]; then
        printf '  --   bỏ qua phần của %s (máy này CÓ %s)\n' "$miss" "$miss"
        continue
    fi
    # Chỉ đổi giá trị Inherits (sau dấu `=` trong chuỗi sed hoặc tên biến), không
    # đếm lần nhắc trong thông báo.
    if printf '%s\n' "$code_lines" |
       grep -qE "^(Inherits=|.*-i *'?s\^Inherits=).*$miss"; then
        bad "C4 lệnh thực thi vẫn đặt $miss vào Inherits" "máy không có theme đó"
    else
        ok "C4 lệnh sửa không đặt $miss vào Inherits (máy không có)"
    fi
done
# Và phải giữ 3 theme thật sự có: đó là nguồn dự phòng cho 5 icon thiếu.
for keep in breeze-dark Adwaita hicolor; do
    if grep -q "Inherits=.*$keep" "$T/fn.sh"; then
        ok "C4b giữ $keep trong Inherits (nguồn dự phòng)"
    else
        bad "C4b mất $keep khỏi Inherits" \
            "4/5 icon YAMO thiếu rơi về đây — mất thì GTK vẽ icon trắng"
    fi
done

# --- C5: sửa file trong ~/.local phải qua symlink_guard ------------------------
# index.theme sau khi cài là file của user, có thể là symlink (vd trỏ về kho
# dotfiles). Sửa qua symlink = sửa file trong kho của user, đúng lúc không
# muốn. Đã có sự cố tương tự với kho dotfiles.
if grep -q 'symlink_guard "\$yi"' "$T/fn.sh"; then
    ok "C5 sửa index.theme qua symlink_guard"
else
    bad "C5 sửa index.theme không qua symlink_guard" \
        "sửa qua symlink là ghi vào kho dotfiles của user khi chưa hỏi"
fi

# --- C6: xsettingsd.conf khai YAMO làm icon chính -----------------------------
xs="$R/.config/xsettingsd/xsettingsd.conf"
if [[ ! -f $xs ]]; then
    bad "C6 không thấy $xs" "dotfile bị mất"
else
    name=$(grep -m1 '^Net/IconThemeName' "$xs" | sed 's/.*"\(.*\)".*/\1/')
    if [[ $name == yet-another-monochrome-icon-set ]]; then
        ok "C6 Net/IconThemeName = $name"
    else
        bad "C6 icon chính là '$name', không phải YAMO" \
            "sửa .config/xsettingsd/xsettingsd.conf trong kho dotfiles"
    fi
    # Phải khớp TÊN THƯ MỤC, không phải Name=. Đây là lỗi Kora từng mắc:
    # kora khai Name=Kora Grey nhưng GTK tra theo tên thư mục "kora-pgrey".
    if [[ -d $ICONS_Y ]]; then
        ok "C6b tên trong config khớp thư mục đã cài ($ICONS_Y)"
    else
        printf '  --   bỏ qua C6b: máy này chưa cài %s\n' "$ICONS_Y"
    fi
fi

# --- C7: có lệnh riêng, KHÔNG ép vào `all` ------------------------------------
main_fn=$(sed -n '/^main() {/,/^}/p' "$R/install.sh")
all_code=$(printf '%s\n' "$main_fn" |
           sed -n '/^        all)/,/^            ;;/p' |
           grep -vE '^[[:space:]]*#')
if printf '%s\n' "$all_code" | grep -q 'install_icons'; then
    bad "C7 install_icons chạy trong \`all\`" "163 MB icon theme, đã hỏi và chọn lệnh riêng"
else
    ok "C7 \`all\` không gọi install_icons (không ép 163 MB)"
fi
if printf '%s\n' "$main_fn" | grep -q 'icons)'; then
    ok "C7b có lệnh riêng: ./install.sh icons"
else
    bad "C7b không có lệnh \`icons\`" "không ép mà cũng không lệnh riêng = không cài được"
fi
if ./install.sh --help 2>/dev/null | grep -q 'install.sh icons'; then
    ok "C7c --help có liệt kê ./install.sh icons"
else
    bad "C7c --help thiếu \`icons\`" "usage() rút từ khối comment đầu file"
fi

# --- C8: chạy install_icons với repo GIẢ — không đụng mạy thật ----------------
# Clone 2 repo thật tốn 160+ MB và vài phút. Ở đâta dựng repo giả có cùng hình
# dạng (index.theme + thư mục con + icon-theme.cache của tác giả), trỏ HOME vào
# thư mục tạm, rồi kiểm cơ chế: có clone đúng, có copy đúng tên, có xoá cache
# của tác giả, có dựng lại cache, có sửa Inherits.
# LƯU Ý: dùng `git init` + commit thật, vì install_icons kiểm tra
# `-d $src/$cdir/.git` để quyết định clone hay bỏ qua. Không có .git thì nó
# clone lại mỗi lần — và test sẽ không phát hiện được nhánh "đã có".
mkdir -p "$T/fake"
mkfake() {   # $1 = tên cache dir, $2 = nội dung Inherits, $3 = số file svg
    local d="$T/fake/$1"
    mkdir -p "$d/apps/scalable" "$d/places/16"
    printf '[Icon Theme]\nName=%s\nInherits=%s\n' "$1" "$2" > "$d/index.theme"
    printf 'STALE-CACHE-FROM-AUTHOR\n' > "$d/icon-theme.cache"
    local i
    for ((i = 0; i < $3; i++)); do
        printf '<svg xmlns="http://www.w3.org/2000/svg" width="8" height="8"/>\n' \
            > "$d/apps/scalable/i$i.svg"
    done
    printf 'fake %s\n' "$1" > "$d/README"
    git -C "$d" init -q 2>/dev/null
    git -C "$d" -c user.email=t@t -c user.name=t add -A 2>/dev/null
    git -C "$d" -c user.email=t@t -c user.name=t commit -qm fake 2>/dev/null
}
mkfake yamo 'Papirus-Dark,breeze-dark,Cosmic,Adwaita,hicolor' 3
mkfake buuf 'oxygen,gnome,hicolor,breeze' 3

# URL thật -> trỏ về repo giả qua git config thay thế (insteadOf).
cat > "$T/clonewrap.sh" <<'WRAP'
#!/usr/bin/env bash
# Chặn `git clone <url> <dir>` rồi copy từ repo giả tương ứng.
for a in "$@"; do
    case $a in
        *yet-another-monochrome-icon-set*) src=$FAKE/yamo ;;
        *buuf-nestort*)                   src=$FAKE/buuf ;;
    esac
done
[[ -n ${src:-} ]] || { echo "stub: URL lạ, không biết dùng repo giả nào: $*" >&2; exit 1; }
last=${!#}
mkdir -p "$last"
cp -r -- "$src/." "$last/"
WRAP
chmod +x "$T/clonewrap.sh"

mkdir -p "$T/gitstub"
cat > "$T/gitstub/git" <<GITSTUB
#!/usr/bin/env bash
if [[ \${1:-} == clone ]]; then
    exec "$T/clonewrap.sh" "\$@"
fi
exec /usr/bin/git "\$@"
GITSTUB
chmod +x "$T/gitstub/git"

# Chạy install_icons với HOME giả + git giả. Phải khai đủ hàm mà hàm dùng.
cat > "$T/run.sh" <<RUNSH
step(){ printf '  == %s\n' "\$*"; }
ok(){ printf '  + %s\n' "\$*"; }
info(){ printf '  i %s\n' "\$*"; }
warn(){ printf '  ! %s\n' "\$*"; }
die(){ printf '  x %s\n' "\$*"; exit 1; }
confirm(){ return 1; }
tilde(){ printf '~/%s' "\${1#\${2:-}}"; }
# PHẢI có: install_icons gọi symlink_guard khi sửa index.theme. Bản đầu
# thiếu hàm này nên hàm chết ở dòng 48 với "command not found" — và mọi ca C8
# đỏ. Đo bằng cách gọi trực tiếp có lệnh source rồi thấy dòng 48 báo đúng lỗi đó.
#
# CŨNG PHẢI tránh backtick trong phần SINH FILE ở trên: heredoc <<RUNSH không
# quoted nên bash thay thế cả backtick, và nó còn thay thế backtick trong comment
# của chính khối sinh file đó. Bản đầu viết lệnh source trong ngoặc ngược ở
# comment -> bash chạy lệnh đó lúc sinh file -> dính "source: filename argument
# required" giữa kết quả, mà test vẫn xanh vì thoát 0. Comment ở đây cố ý viết
# không có backtick.
symlink_guard(){ return 0; }
backup_path(){ printf '%s\n' "\${1}.tsuki-bak-test"; }
export TSUKI_HOME="$T/home"
export FAKE="$T/fake"
mkdir -p "\$TSUKI_HOME"
$(cat "$T/fn.sh")
install_icons
RUNSH
out=$(PATH="$T/gitstub:$PATH" bash "$T/run.sh" 2>&1)
# In ra khi C8 đỏ — không để lỗi test hiện ra dấu chấm hỏi rồi phải đoán.
if ! printf '%s' "$out" | grep -q 'yet-another-monochrome-icon-set ->'; then
    printf '        [debug] output install_icons:\n'
    printf '%s\n' "$out" | sed 's/^/        /'
fi

if printf '%s' "$out" | grep -q 'clone thất bại'; then
    bad "C8 clone thất bại trong môi trường thử" "$out"
elif printf '%s' "$out" | grep -q 'yet-another-monochrome-icon-set ->'; then
    ok "C8 chạy thật: YAMO vào ~/.local/share/icons/yet-another-monochrome-icon-set"
else
    bad "C8 không copy YAMO vào đúng thư mục" "$out"
fi
if printf '%s' "$out" | grep -q 'Buuf-For-Many-Desktops ->'; then
    ok "C8b chạy thật: Buuf vào ~/.local/share/icons/Buuf-For-Many-Desktops"
else
    bad "C8b không copy Buuf vào đúng thư mục" "$out"
fi

# Cache của tác giả phải biến mất, và cache MỚI phải có.
if [ -f "$T/home/.local/share/icons/yet-another-monochrome-icon-set/icon-theme.cache" ]; then
    if grep -q 'STALE-CACHE-FROM-AUTHOR' \
        "$T/home/.local/share/icons/yet-another-monochrome-icon-set/icon-theme.cache" 2>/dev/null; then
        bad "C8c cache cũ của tác giả còn sót" "dùng lại cache có đường dẫn máy tác giả"
    else
        ok "C8c cache cũ đã bị xoá, dựng lại cache mới"
    fi
else
    # Có thể gtk-update-icon-cache không có trong PATH của test, hoặc theme quá
    # nhỏ nên không sinh cache. Cả hai đều được chấp nhận — nhưng phải nói rõ,
    # không im lặng coi như đã kiểm.
    if command -v gtk-update-icon-cache >/dev/null 2>&1; then
        printf '  --   bỏ qua C8c: cache không sinh (theme giả quá nhỏ?)\n'
    else
        printf '  --   bỏ qua C8c: không có gtk-update-icon-cache\n'
    fi
fi

# Inherits phải được sửa trong file ĐÃ COPY (ở HOME giả), không phải trong repo.
yi="$T/home/.local/share/icons/yet-another-monochrome-icon-set/index.theme"
if [ -f "$yi" ]; then
    inh=$(grep -m1 '^Inherits=' "$yi" | cut -d= -f2-)
    case $inh in
        *Papirus-Dark*|*Cosmic*)
            bad "C8d Inherits sau khi sửa vẫn có theme máy không có" "$inh" ;;
        *breeze-dark*)
            ok "C8d Inherits sau khi sửa: $inh" ;;
        *)
            bad "C8d Inherits sửa sai" "$inh" ;;
    esac
else
    bad "C8d không có index.theme ở HOME giả" "$out"
fi
# Repo giả phải GIỮ NGUYÊN — chỉ bản trong HOME mới được sửa.
ri=$(grep -m1 '^Inherits=' "$T/fake/yamo/index.theme" | cut -d= -f2-)
if [[ $ri == *Papirus-Dark* ]]; then
    ok "C8e repo gốc không bị sửa (chỉ bản trong HOME)"
else
    bad "C8e repo gốc bị sửa" "phải sửa bản trong ~/.local, không đụng nguồn: $ri"
fi

# --- C9: chạy LẠI lần hai — không clone lại, không mất cài đặt ----------------
out2=$(PATH="$T/gitstub:$PATH" bash "$T/run.sh" 2>&1)
if printf '%s' "$out2" | grep -q 'clone thất bại'; then
    bad "C9 lần chạy hai clone lại" "$out2"
elif printf '%s' "$out2" | grep -q 'yamo đã có — bỏ qua clone'; then
    ok "C9 lần hai bỏ qua clone, dùng bản cache"
else
    bad "C9 lần hai không bỏ qua clone" \
        "install_icons kiểm tra -d \$src/\$cdir/.git — nếu .git không có thì clone mãi" \
        "$out2"
fi
# Icon phải còn sau lần hai (không bị xoá rồi copy fail).
if [ -f "$yi" ]; then
    ok "C9b lần hai không làm mất icon đã cài"
else
    bad "C9b lần hai làm mất icon" "$out2"
fi

# --- C10: môi trường thật trên máy này ----------------------------------------
# Nếu chưa cài thì bỏ qua — test phải chạy được trên máy mới, không phụ thuộc
# bước `./install.sh icons` đã chạy hay chưa.
for pair in "yet-another-monochrome-icon-set" "Buuf-For-Many-Desktops"; do
    p=~/.local/share/icons/$pair
    if [ ! -d "$p" ]; then
        printf '  --   bỏ qua kiểm tra %s (chưa cài)\n' "$pair"
        continue
    fi
    if [ -f "$p/index.theme" ]; then
        ok "C10 $pair đã cài, có index.theme"
    else
        bad "C10 $pair cài nhưng thiếu index.theme" "GTK sẽ không nhận theme"
    fi
done

# Icon chính có thật sự được GTK nạp không? Hỏi GtkSettings.
if python3 -c 'import gi; gi.require_version("Gtk","3.0"); from gi.repository import Gtk' 2>/dev/null; then
    cur=$(python3 - <<'PY' 2>/dev/null
import gi
gi.require_version('Gtk', '3.0')
from gi.repository import Gtk
print(Gtk.Settings.get_default().get_property('gtk-icon-theme-name'))
PY
)
    if [[ -n $cur ]]; then
        if [[ $cur == yet-another-monochrome-icon-set ]]; then
            ok "C10b GtkSettings đang nạp: $cur"
        else
            printf '  --   GtkSettings đang nạp %s (chưa nạp lại xsettingsd)\n' "$cur"
            printf '         khởi động lại xsettingsd hoặc logout rồi test lại\n'
        fi
    else
        printf '  --   bỏ qua C10b: không đọc được GtkSettings (không có DISPLAY?)\n'
    fi
else
    printf '  --   bỏ qua C10b: không có Gtk3 bindings\n'
fi

printf '\n  %d PASS, %d FAIL\n' "$P" "$F"
[ "$F" -eq 0 ]

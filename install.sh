#!/usr/bin/env bash
#
# install.sh — cài Tsuki (dwm rice) trên Arch/CachyOS.
#
#   ./install.sh              # cài đầy đủ: deps -> build -> dotfiles -> session
#   ./install.sh deps         # chỉ cài gói phụ thuộc
#   ./install.sh arisa        # hỏi rồi thêm kho arisa (Super+C, Super+D)
#   ./install.sh paru         # cài paru để dùng AUR
#   ./install.sh pty          # bộ gõ Lotus (tiếng Việt) — cần paru
#   ./install.sh build        # chỉ build + cài binary
#   ./install.sh dotfiles     # chỉ copy ~/.config
#   ./install.sh session      # chỉ cấu hình chạy từ TTY (.xinitrc)
#   ./install.sh session --dm # cài thêm .desktop cho display manager
#   ./install.sh uninstall    # gỡ binary Tsuki đã cài
#   ./install.sh xlibre           # XLibre kênh stable (25.1)
#   ./install.sh xlibre beta      # XLibre kênh beta (25.2, dùng thử)
#   ./install.sh xlibre oldstable # kênh cũ (25.0)
#
# Không chạy `make clean` ở đâu cả: config.h là cấu hình thật của máy, đã được
# git track; `make clean` ở các Makefile cũ từng xoá nó rồi cp lại từ
# config.def.h, âm thầm thay hết tùy chỉnh. Xem scripts/rebuild.sh.
#
set -euo pipefail

REPO_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
readonly REPO_DIR
SUDO=""
PREFIX="${PREFIX:-/usr/local}"

# ---------------------------------------------------------------- logging ---
if [[ -t 1 && -z ${NO_COLOR:-} ]]; then
    C_RST=$'\033[0m' C_R=$'\033[1;31m' C_G=$'\033[1;32m'
    C_Y=$'\033[1;33m' C_B=$'\033[1;34m' C_D=$'\033[2m'
else
    C_RST="" C_R="" C_G="" C_Y="" C_B="" C_D=""
fi
step() { printf '%s==>%s %s%s%s\n' "$C_B" "$C_RST" "$C_B" "$*" "$C_RST"; }
ok()   { printf '  %s✓%s %s\n' "$C_G" "$C_RST" "$*"; }
info() { printf '  %s·%s %s\n' "$C_B" "$C_RST" "$*"; }
warn() { printf '  %s!%s %s\n' "$C_Y" "$C_RST" "$*" >&2; }
die()  { printf '%serror:%s %s\n' "$C_R" "$C_RST" "$*" >&2; exit 1; }

# Chạy lệnh cần quyền root: dùng sudo nếu có, nếu không (đã root) thì chạy thẳng.
as_root() {
    if (( EUID == 0 )); then
        "$@"
    else
        [[ -n $SUDO ]] || die "cần quyền root cho: $*  (thử lại với sudo)"
        sudo "$@"
    fi
}

# -------------------------------------------------------------- bootstrap ---
detect_sudo() {
    (( EUID == 0 )) && return 0
    if command -v sudo >/dev/null 2>&1; then
        SUDO=sudo
    else
        die "không có sudo và không phải root — không cài được"
    fi
}

# Chạy nguyên xi một khối lệnh với quyền root.
#
# BẪY: `bash -s -- -c 'script' _ args` KHÔNG chạy script. `-s` bắt bash đọc
# lệnh từ stdin, nên `-c` rơi xuống thành positional $0 và khối lệnh bị bỏ
# trắng — bash thoát 0, `set -e` không bắt được, script cứ đi tiếp như thể
# đã build/cài xong. Đã kiểm chứng:
#     bash -s -- -c 'echo hi' _ x   ->  (không in gì, exit 0)
# Phải là `bash -c 'script' _ args`: ở đây -c là chế độ, "_" là $0, args là $1...
root_sh() {
    as_root env TSUKI_PREFIX="$PREFIX" bash -c "$@"
}

# --------------------------------------------------------------- packages ---
# Bốn nhóm. Mỗi gói đều truy được về một chỗ cụ thể trong repo.
#
#   PKG_BUILD     — thư viện và toolchain lúc compile, lấy từ cờ -l trong
#                   */config.mk và pkg-config trong */Makefile
#   PKG_SESSION   — hạ tầng X11, lấy từ những gì scripts/run.sh và
#                   .config/fish/conf.d/tsuki.fish cần có mặt
#   PKG_CONFIG    — app có sẵn dotfile trong dwm/.config, mỗi mục khớp 1-1
#                   với một thư mục (hoặc file) trong đó
#   PKG_KEYBINDS  — app dwm mở bằng phím tắt, mỗi dòng ghi kèm SHCMD nào
#
# Nguồn đã quét khi lập danh sách: config.h + config.def.h (mọi SHCMD),
# scripts/*.sh, netpanel/*.sh, *.py, .config/fish/**, */config.mk, */Makefile.
#
# Cố ý KHÔNG cài:
#   - lệnh hệ thống — coreutils, grep, sed, findutils, gawk, tar, gzip,
#     procps-ng, psmisc. Đây là bộ phận của mọi Arch, cài lại chỉ là chạy
#     pacman không cần thiết.
#   - tiện ích chỉ nằm trong alias của .config/fish, không mở app nào:
#     eza, expac, neovim, hwinfo, wget, openbsd-netcat, jq.
#   - imagemagick — mediacard.sh:83 có guard `command -v magick`, thiếu thì
#     ảnh bìa webp không đổi sang png chứ không chết.
#   - fcitx5-lotus-bin — engine tiếng Việt đến từ AUR, xem cmd_pty.
#   - xorg-xsetroot, xorg-xwayland — xsetroot chỉ còn trong scripts/bar.sh,
#     mà bar.sh đã bị slstatus thay và không còn ai gọi. XWayland thì bị tắt
#     cố ý, xem scripts/run.sh.
#   - epos-gsx300-gui (config.h:189, Super+P) — app đi kèm chuột EPOS
#     GSX300, không có trong kho nào. Xem PKG_KEYBINDS.

# --- 1. build ---
readonly PKG_BUILD=(
    # toolchain: cc/make cho mọi Makefile
    base-devel make
    # netpanel/config.mk:5 và scripts/Makefile.imgdec:20-22 gọi pkg-config
    pkgconf
    # git chỉ để clone repo rồi chạy install.sh; Makefile nào cũng không gọi git
    git

    # dwm + dmenu: -lfontconfig -lXft -lXinerama -lXrender -lX11
    libx11 libxft libxinerama libxrender
    # drw tự dựng: -lfontconfig (kéo theo freetype2, harfbuzz)
    fontconfig freetype2 harfbuzz
    # dwm: -lImlib2
    imlib2

    # st: -lm -lXft -lXrender -lX11
    # slock: -lcrypt -lXext -lXrandr
    # netpanel: pkg-config x11 xft xrender xext fontconfig
    libxcrypt libxext libxrandr

    # scripts/Makefile.imgdec: pkg-config libturbojpeg + libwebp
    libjpeg-turbo libwebp
)

# --- 2. session ---
# Tsuki chạy X11 thuần: không cài xorg-xwayland. XWayland mở được app
# Wayland-only, đổi lại clipboard và chia sẻ màn hình bị vỡ — không đáng.
# Muốn bật thì tự thêm, xem scripts/run.sh.
readonly PKG_SESSION=(
    xorg-server
    # startx — .config/fish/conf.d/tsuki.fish chặn `dwm` nếu thiếu startx
    xorg-xinit
    # scripts/run.sh: xrdb nạp .Xresources, xset đổi nền chuột
    xorg-xrdb xorg-xset
    # scripts/dwmwal.sh:84 — feh vẽ wallpaper
    feh
    # libnotify cấp notify-send; dunst/picom/xsettingsd nằm ở PKG_CONFIG vì
    # chúng có dotfile trong dwm/.config
    libnotify
    # scripts/rebuild.sh chạy pkexec — không có auth agent thì hộp thoại hỏi
    # mật khẩu rơi vào terminal, không lên GUI
    polkit-gnome
    # mọi script trong repo shebang #!/bin/dash, config.h cũng spawn bằng `dash`
    dash
    # config.h:283 — Super+e mở quản lý file. Không có dotfile trong
    # dwm/.config nên không thuộc PKG_CONFIG; nhưng nó là app dwm spawn
    # thẳng, cùng kiểu với feh ở trên, nên để ở đây.
    thunar
    # scripts/run.sh:98 `start_daemon fcitx fcitx5 -d` — daemon bộ gõ. Thiếu
    # thì vẫn có bàn phím, mất gõ tiếng Việt. Engine Lotus tới từ AUR nên
    # nằm ở PKG_PTY, xem cmd_pty.
    fcitx5
)

# --- 3. app có dotfile trong dwm/.config ---
# Thứ tự khớp với thứ tự mục trong dwm/.config. Thêm dotfile mới thì phải sửa
# cả mảng này lẫn `items` trong cmd_dotfiles — hai chỗ phải khớp 1-1.
readonly PKG_CONFIG=(
    dunst        # .config/dunst/
    fastfetch    # .config/fastfetch/
    firefox      # .config/firefox/
    fish         # .config/fish/
    kitty        # .config/kitty/
    picom        # .config/picom/
    starship     # .config/starship.toml
    xsettingsd   # .config/xsettingsd/
)

# --- 4. app mở bằng phím tắt ---
# Mỗi dòng là một SHCMD(...) trong config.h. Không kèm gói cho `st` `slock`
# `dmenu_run` — ba cái đó build từ chính repo.
#
# Cố ý bỏ qua `epos-gsx300-gui` (config.h:189, Super+P): đó là app đi kèm
# chuột EPOS GSX300, không có trong kho Arch/CachyOS nào. Cài nó chỉ có thể
# bằng tay, nên để ngoài danh sách thay vì làm cả lô cài hỏng.
readonly PKG_KEYBINDS=(
    # config.h:170-172 — XF86XK_Audio*: scripts/mediacard.sh volume
    #   pactl đọc volume/mute, playerctl đọc metadata, curl tải ảnh bìa album
    libpulse playerctl curl
    # config.h:178,180,182 — Super+Ctrl+U / Super+U / Print
    scrot xclip

    # config.h:185 Super+C — `code`
    visual-studio-code-bin
    # config.h:187 Super+G
    steam
    # config.h:201 Super+D
    discord-ptb
    # config.h:202 Super+/ — `bat ... || less ...`; less là nhánh dự phòng nên
    # cần cả hai, thiếu less thì phím báo lỗi khi bat hỏng
    bat less

    # config.h:203 Super+W — scripts/dwmwal.sh, mở wallpicker.py
    python-gobject python-cairo python-pillow python-numpy gtk3

    # config.h:301 ClkNetIcon — netpanel.sh -> netpanel-band.sh + netpanel-qr.sh
    #   nmcli: đọc wifi (networkmanager), iw: băng tần, qrencode: vẽ QR,
    #   ip: tìm interface mặc định, column: canh cột trong netpanel-qr.sh
    networkmanager iw qrencode iproute2 util-linux

    # config.h:184 Super+R — dmenu_run; drw dựng chữ bằng fonts[] trong config.h
    # nên thiếu font thì mọi chữ trên bar và trong dmenu đều là ô vuông
    ttc-iosevka ttf-jetbrains-mono-nerd
)

missing_pkgs() {
    local -n ref=$1
    local p
    for p in "${ref[@]}"; do
        pacman -Qq "$p" >/dev/null 2>&1 || printf '%s\n' "$p"
    done
}

# Có tồn tại trong kho nào đang bật không. Cần vì `pacman -S a b c` huỷ CẢ LÔ
# khi chỉ một gói không tìm thấy ("target not found") — đã kiểm: cho
# `pacman -Sp less fake-pkg-xyz` thì cả `less` cũng không được nạp, exit 1.
# Mấy gói như visual-studio-code-bin hay discord-ptb nằm ở repo thứ ba, thiếu
# repo đó là toàn bộ nhóm hỏng theo.
available_pkgs() {
    local -a missing=("$@")
    local -a ok=() bad=()
    local p
    for p in "${missing[@]}"; do
        if pacman -Sddp "$p" >/dev/null 2>&1; then ok+=("$p"); else bad+=("$p"); fi
    done
    if (( ${#bad[@]} )); then
        warn "không có trong kho nào đang bật, bỏ qua: ${bad[*]}"
    fi
    (( ${#ok[@]} )) || return 0
    root_sh -c 'pacman -S --needed --noconfirm "$@"' _ "${ok[@]}"
}

install_pkgs() {
    # Truyền "$1" (TÊN mảng) chứ không phải "$ref". Với `local -n ref=$1`,
    # biến "$ref" mở rộng ra GIÁ TRỊ của mảng — tức phần tử đầu tiên — chứ
    # không phải tên. `missing_pkgs "$ref"` vì thế nhận "dunst" thay vì
    # "PKG_CONFIG", rồi `local -n ref=dunst` tạo nameref tới biến rỗng
    # `dunst`; vòng lặp duyệt rỗng nên luôn ra "đã đủ". Đã tái hiện được:
    # mảng PKG_CONFIG bắt đầu bằng `dunst` (tên biến hợp lệ, lỗi im lặng),
    # PKG_BUILD bắt đầu bằng `base-devel` (tên không hợp lệ, báo lỗi
    # "invalid variable name"). Ở đây chỉ cần tên, không cần nameref.
    local label=$2
    local -a missing=()
    mapfile -t missing < <(missing_pkgs "$1")
    if (( ${#missing[@]} == 0 )); then
        ok "$label: đã đủ"
        return 0
    fi
    step "cài gói ($label): ${#missing[@]} thiếu"
    printf '    %s\n' "${missing[*]}"
    available_pkgs "${missing[@]}"
    ok "$label: xong"
}

cmd_deps() {
    detect_sudo
    install_pkgs PKG_BUILD      "build"
    install_pkgs PKG_SESSION    "session"
    install_pkgs PKG_CONFIG     "config-apps"
    install_pkgs PKG_KEYBINDS   "keybind-apps"
}

# ------------------------------------------------------------------ build ---
# Build trong thư mục tạm rồi `make install` — không bao giờ đụng `make clean`.
build_one() {
    local dir=$1 name=$2
    local src="$REPO_DIR/$dir"

    [[ -d $src ]] || { warn "bỏ qua $name (không có thư mục $dir)"; return 0; }

    step "build $name"
    root_sh -c 'cd "$1" && make -j"$(nproc)" && make install PREFIX="$TSUKI_PREFIX"' _ "$src"
    ok "$name -> $PREFIX/bin"
}

cmd_build() {
    detect_sudo
    # Mỗi thư mục con đều có `config.h:` -> cp config.def.h $@ trong Makefile.
    # Thiếu file thì make âm thầm tạo lại từ config.def.h và mất sạch tùy chỉnh,
    # đúng thứ cảnh báo ở đầu script. Phải kiểm tra TỪNG cái, không chỉ config.h
    # gốc — kiểm tra thiếu thì lỗi chỉ lộ ra sau khi build xong.
    local d
    for d in . st slock dmenu slstatus netpanel; do
        if [[ -d $REPO_DIR/$d && ! -f $REPO_DIR/$d/config.h ]]; then
            die "thiếu $d/config.h — make sẽ cp từ config.def.h và xoá mất cấu hình
     Khôi phục:  git restore $d/config.h   (hoặc: git clone --depth 1 <repo> $REPO_DIR/$d)"
        fi
    done

    build_one .        dwm
    build_one st       st
    build_one slock    slock
    build_one dmenu    dmenu
    build_one slstatus slstatus

    step "build netpanel"
    if [[ -d $REPO_DIR/netpanel ]]; then
        root_sh -c 'cd "$1" && make -j"$(nproc)"' _ "$REPO_DIR/netpanel"
        ok "netpanel (cần chạy tại $REPO_DIR/netpanel/netpanel)"
    fi

    step "build imgdec (decoder ảnh cho picker)"
    if [[ -f $REPO_DIR/scripts/Makefile.imgdec ]]; then
        root_sh -c 'cd "$1" && make -f scripts/Makefile.imgdec' _ "$REPO_DIR"
        ok "imgdec"
    fi
}

# --------------------------------------------------------------- dotfiles ---
# File do chính chương trình sinh lại mỗi lần chạy — KHÔNG được đồng bộ, vì
# nếu copy, lần chạy sau nó lại khác và backup mọi lần (vòng lặp vô hạn).
#   fish_variables — fish tự ghi lúc khởi động, chứa universal variable của
#                    MÁY NÀY (kể cả biến export như token), không phải cấu hình
#                    để phân phối. Đã kiểm chứng: chạy `fish -c true` là file
#                    đổi ngay.
readonly GENERATED_FILES=(
    fish_variables
)

is_generated() {
    local name=$1 f
    for f in "${GENERATED_FILES[@]}"; do
        [[ $name == "$f" ]] && return 0
    done
    return 1
}

# So sánh nội dung, xử lý được cả file lẫn thư mục.
# `cmp` chỉ so file: so với thư mục nó luôn trả khác, nên mọi thư mục sẽ bị
# backup + ghi đè dù nội dung y hệt. `diff -rq` xử lý đúng cả hai.
# `-x` để bỏ qua file sinh tự động, nếu không `cmd_dotfiles` không bao giờ
# idempotent với ~/.config/fish.
same_content() {
    if [[ -d $1 && -d $2 ]]; then
        local -a excl=()
        local f
        for f in "${GENERATED_FILES[@]}"; do excl+=(-x "$f"); done
        diff -rq "${excl[@]}" -- "$1" "$2" >/dev/null 2>&1
    else
        cmp -s -- "$1" "$2"
    fi
}

# Copy có backup: mục cũ khác nội dung đổi thành <mục>.tsuki-bak-<timestamp>
install_dotfile() {
    local src=$1 dst=$2
    [[ -e $src ]] || return 0
    is_generated "$(basename -- "$src")" && return 0
    mkdir -p -- "$(dirname -- "$dst")"

    if [[ -e $dst || -L $dst ]]; then
        if same_content "$src" "$dst"; then
            return 0   # giống hệt, không đụng
        fi
        local bak="$dst.tsuki-bak-$(date +%Y%m%d%H%M%S)"
        mv -- "$dst" "$bak"
        warn "$(basename -- "$dst") khác nội dung -> backup: ${bak##*/}"
    fi
    cp -a -- "$src" "$dst"
}

cmd_dotfiles() {
    step "cài dotfiles vào ~/.config"
    # Danh sách này phải khớp PKG_CONFIG: mỗi gói ở đó có đúng một mục ở đây,
    # và ngược lại. Thêm dotfile mới thì sửa cả hai chỗ — nếu không sẽ có
    # dotfile được copy tới ~/.config mà không cài gói nào, hoặc cài gói mà
    # không dotfile nào dùng tới.
    local -a items=(dunst fastfetch firefox fish kitty picom starship.toml xsettingsd)
    local n=0 d
    for d in "${items[@]}"; do
        # starship.toml là file, còn lại là thư mục — install_dotfile nhận cả hai
        if [[ -e "$REPO_DIR/.config/$d" ]]; then
            install_dotfile "$REPO_DIR/.config/$d" "$HOME/.config/$d"
            n=$((n + 1))
        else
            warn "thiếu .config/$d trong repo — bỏ qua"
        fi
    done
    ok "xong ($n/${#items[@]} mục)"
}

cmd_firefox() {
    step "cài giao diện Firefox"
    local profile
    # `|| true` là bắt buộc: dưới `set -o pipefail`, khi head lấy đủ dòng rồi
    # thoát, find bị SIGPIPE và trả 141; lệnh gán cũng nhận luôn 141 -> set -e
    # kết thúc script ngay. Đã kiểm chứng: exit=141.
    profile="$(find "$HOME/.config/mozilla/firefox" -maxdepth 1 -name '*.default-release' 2>/dev/null | head -1 || true)"
    [[ -n $profile ]] || {
        warn "không tìm thấy Firefox profile — bỏ qua (mở Firefox một lần rồi chạy lại)"
        return 0
    }
    mkdir -p "$profile/chrome"
    install_dotfile "$REPO_DIR/.config/firefox/user.js" "$profile/user.js"
    install_dotfile "$REPO_DIR/.config/firefox/chrome/userChrome.css" "$profile/chrome/userChrome.css"
    ok "profile: ${profile##*/}"
}

# ---------------------------------------------------------------- session ---
# .xinitrc — điểm vào khi chạy `startx` từ TTY.
# startx KHÔNG nạp profile login shell, nên PATH phải tự dựng.
write_xinitrc() {
    step "ghi ~/.xinitrc"
    # Backup nếu đã có .xinitrc: `cat >` xoá trắng file cũ mà không để lại dấu
    # vết, và người dùng rất dễ đã có .xinitrc riêng từ trước.
    if [[ -f $HOME/.xinitrc ]] && ! grep -q 'Tsuki install.sh' "$HOME/.xinitrc"; then
        local bak="$HOME/.xinitrc.tsuki-bak-$(date +%Y%m%d%H%M%S)"
        cp -a -- "$HOME/.xinitrc" "$bak"
        warn ".xinitrc đã tồn tại -> backup: ${bak##*/}"
    fi
    cat >"$HOME/.xinitrc" <<EOF
# ~/.xinitrc — do Tsuki install.sh tạo. Chạy session dwm từ TTY: startx
#
# startx không nạp ~/.profile nên PATH phỏng vọng; make install đặt binary vào
# $PREFIX/bin nên phải thêm vào PATH ở đây, nếu không run.sh sẽ không tìm thấy dwm
# và vòng lặp thoát ngay.
export PATH="$PREFIX/bin:\$PATH"
exec "$REPO_DIR/scripts/run.sh"
EOF
    chmod 644 "$HOME/.xinitrc"
    ok "~/.xinitrc -> $REPO_DIR/scripts/run.sh"
}

# .desktop cho display manager (GDM/SDDM/LightDM đều quét /usr/share/xsessions).
# Không dùng ~/.xsessions: đó là thói quen từ LightDM, GDM không quét nên file
# im lặng biến mất khỏi màn hình đăng nhập mà không có lỗi nào báo.
install_desktop_entry() {
    step "đăng ký session cho display manager"
    root_sh -c '
        set -e
        d=/usr/share/xsessions
        install -d -m 755 "$d"
        cat > "$d/Tsuki.desktop" <<EOF
[Desktop Entry]
Name=Tsuki
Comment=Tsuki — dwm session (wallpaper-aware)
Exec=$1/scripts/run.sh
Icon=preferences-desktop
Terminal=false
Type=Application
EOF
        chmod 644 "$d/Tsuki.desktop"
        echo "  + $d/Tsuki.desktop"
    ' _ "$REPO_DIR"
}

cmd_session() {
    write_xinitrc
    if [[ ${1:-} == --dm ]]; then
        detect_sudo
        install_desktop_entry
    fi
    cat <<EOF

  Chạy từ TTY:
    1. thoát phiên hiện tại (nếu đang chạy GNOME/Wayland)
    2. Ctrl+Alt+F2 để qua TTY, đăng nhập
    3. gõ:  startx

  Thoát về TTY: Super+Ctrl+Q  (hoặc kill dwm)
EOF
}

# ---------------------------------------------------------------- xlibre ---
# Theo đúng hướng dẫn https://xlibre-arch.github.io/ :
#   1. tải key .asc -> pacman-key --add -> --finger -> --lsign-key
#   2. thêm [xlibre-<kênh>] vào cuối /etc/pacman.conf
#   3. pacman -Syyu
#   4. pacman -S xlibre-meta   (thay thế các gói X.Org tương ứng)
#
# Chỉ bật MỘT kênh. Bật cả stable và beta thì pacman lấy version cao nhất, nên
# bạn định dùng stable lại âm thầm nhận beta — đúng thứ gây khó chịu nhất khi
# debug. Muốn đổi kênh: chạy lại lệnh này với kênh khác.
readonly XLIBRE_KEY_URL="https://xlibre-arch.github.io/xlibre-archlinux.asc"
readonly XLIBRE_KEY_FPR="B97F7C613F359424"

xlibre_repo_name() {
    case ${1:-stable} in
        beta)      printf 'xlibre-beta' ;;
        oldstable) printf 'xlibre-oldstable' ;;
        stable)    printf 'xlibre-stable' ;;
        *) die "kênh lạ: $1 (chỉ stable | beta | oldstable)" ;;
    esac
}

xlibre_add_key() {
    step "thêm khoá ký XLibre ($XLIBRE_KEY_FPR)"
    if pacman-key --finger "$XLIBRE_KEY_FPR" >/dev/null 2>&1; then
        ok "khoá đã có trong keyring"
        return 0
    fi
    local tmp
    tmp="$(mktemp -d)"
    # shellcheck disable=SC2064
    trap "rm -rf '$tmp'" RETURN
    curl -fsSL -o "$tmp/xlibre.asc" "$XLIBRE_KEY_URL"
    as_root pacman-key --add "$tmp/xlibre.asc"
    # --lsign-key là bắt buộc: key mới thêm mặc định trust là "unknown",
    # pacman sẽ từ chối package với lỗi "signature from ... is marginal trust".
    as_root pacman-key --finger "$XLIBRE_KEY_FPR"
    as_root pacman-key --lsign-key "$XLIBRE_KEY_FPR"
    ok "khoá đã được trust"
}

# Liệt kê mọi mục [prefix...] mà pacman đang dùng, kèm file khai báo.
# Định dạng: [xlibre-beta]<TAB>/etc/pacman.conf
#
# Chỉ grep pacman.conf là thiếu — người dùng thường tự thêm [xlibre-beta]
# thẳng vào pacman.conf, không qua file Include của ta, nên ta sẽ không thấy
# và sẽ bật thêm kênh thứ hai. Hai kênh cùng bật thì pacman lấy version cao
# nhất: bạn định dùng stable vẫn nhận beta.
#
# Dùng chung cho [xlibre] và [arisa] — trước đây logic này viết riêng cho
# XLibre, arisa sẽ cần y hệt nên copy thêm bản thì hai chỗ lệch nhau theo
# thời gian.
pacman_active_sections() {
    local pattern=$1
    local conf f sec
    conf=/etc/pacman.conf
    [[ -r $conf ]] || return 0

    while IFS= read -r sec; do
        [[ -n $sec ]] && printf '%s\t%s\n' "$sec" "$conf"
    done < <(grep -hoE "$pattern" "$conf" 2>/dev/null || true)

    while read -r f; do
        [[ -r $f ]] || continue
        while IFS= read -r sec; do
            [[ -n $sec ]] && printf '%s\t%s\n' "$sec" "$f"
        done < <(grep -hoE "$pattern" "$f" 2>/dev/null || true)
    done < <(
        grep -hoE '^[[:space:]]*Include[[:space:]]*=[[:space:]]*.*' "$conf" 2>/dev/null \
            | sed -E 's/^[^=]*=[[:space:]]*//' | tr -d '"'
    )
}

xlibre_active_channels() {
    pacman_active_sections '^\[xlibre[^]]*\]'
}

readonly XLIBRE_OWN_CONF=/etc/pacman.d/xlibre.conf

xlibre_add_repo() {
    local repo=$1
    step "repo [$repo]"

    local -a active=()
    local sec src
    while IFS=$'\t' read -r sec src; do
        [[ -n $sec ]] && active+=("$sec"$'\t'"$src")
    done < <(xlibre_active_channels)

    if ((${#active[@]} > 1)); then
        local list="" a
        for a in "${active[@]}"; do
            list+="        ${a%%$'\t'*}  (trong ${a##*$'\t'})
"
        done
        die "đang bật nhiều kênh XLibre — pacman chỉ được dùng một:
$list     Gỡ bớt rồi chạy lại. Xoá cả dòng [xlibre-...] lẫn file Include của nó."
    fi

    if ((${#active[@]} == 1)); then
        sec=${active[0]%%$'\t'*}
        src=${active[0]##*$'\t'}
        if [[ $sec == "[$repo]" ]]; then
            ok "đã bật sẵn, không làm gì"
            return 0
        fi
        # Kênh khác đang bật, khai báo trong file CỦA TA -> ghi đè được an toàn.
        if [[ $src == "$XLIBRE_OWN_CONF" ]]; then
            warn "đổi kênh: ${sec} -> [$repo] (trong $XLIBRE_OWN_CONF)"
        else
            die "$sec đang bật trong $src — không phải file Tsuki tạo, nên tôi không tự xoá.
     Muốn dùng [$repo] thì hãy comment dòng $sec trong $src rồi chạy lại.
     Còn muốn giữ $sec thì bỏ qua lệnh này."
        fi
    fi

    # Ghi vào /etc/pacman.d/xlibre.conf rồi Include — sạch hơn là đụng vào
    # pacman.conf của distro, và gỡ được chỉ bằng cách xoá 1 file.
    #
    # Dùng $1 chứ không dùng $repo: biến `repo` là local của hàm ngoài, không
    # nằm trong môi trường của bash con — tham chiếu tới nó sẽ ra rỗng và file
    # ghi ra sẽ là `[]` + URL không có kênh.
    root_sh -c '
        set -e
        f=/etc/pacman.d/xlibre.conf
        install -d -m 755 /etc/pacman.d
        cat > "$f" <<EOF
# XLibre — https://xlibre-arch.github.io/
# Do Tsuki install.sh tạo. Muốn đổi kênh: ./install.sh xlibre <stable|beta|oldstable>
[$1]
Server = https://packages.xlibre.net/arch/$1/\$arch
EOF
        chmod 644 "$f"
        grep -qF "Include = /etc/pacman.d/xlibre.conf" /etc/pacman.conf || \
            printf "\nInclude = /etc/pacman.d/xlibre.conf\n" >> /etc/pacman.conf
        echo "  + $f"
    ' _ "$repo"
    ok "đã bật [$repo]"
}

cmd_xlibre() {
    detect_sudo
    local channel=${1:-stable} repo
    repo="$(xlibre_repo_name "$channel")"

    printf '%sXLibre — kênh %s%s\n' "$C_B" "$channel" "$C_RST"
    case $channel in
        beta)      warn "beta = series 25.2, XLibre chưa coi là ổn định. Dùng khi muốn thử tính năng mới." ;;
        oldstable) warn "oldstable = series 25.0, kênh cũ." ;;
    esac

    # Đã có XLibre chưa — nói trước để user không tưởng cài lại từ đầu.
    if pacman -Qq xlibre-meta >/dev/null 2>&1; then
        step "kiểm tra hiện trạng"
        # Hỏi từng gói một: `pacman -Q a b` trả 1 nếu bất kỳ gói nào không có,
        # dưới pipefail thành lỗi và set -e kết thúc cmd_xlibre ngay tại đây —
        # trước khi kịp làm gì. Đã kiểm chứng: exit=1.
        pacman -Q xlibre-xserver xlibre-meta 2>/dev/null | sed 's/^/  /' || true
    fi

    xlibre_add_key
    xlibre_add_repo "$repo"

    step "đồng bộ index"
    # KHÔNG dùng --noconfirm ở đây. `-Syyu` nâng cấp TOÀN BỘ hệ thống, mà
    # Arch không hỗ trợ partial upgrade: đồng ý hàng loạt có thể để lại hệ
    # thống lệch phiên bản rồi hỏng. Bỏ --noconfirm để bạn đọc danh sách trước.
    as_root pacman -Syyu

    step "cài xlibre-meta"
    warn "sẽ THAY THẾ các gói X.Org tương ứng (xorg-server, driver...). Trả lời 'y' khi pacman hỏi."
    as_root pacman -S --needed --noconfirm xlibre-meta

    cat <<EOF

  ${C_G}Xong.${C_RST} Đăng xuất rồi đăng nhập lại để X server mới có hiệu lực.

  Kiểm tra đã đúng XLibre chưa:
    sudo pacman -S xorg-xdpyinfo
    xdpyinfo | grep vendor        # phải in ra XLibre

  Nếu bị đá khỏi session khi đang cài: đăng nhập lại rồi chạy lại
    sudo pacman -S xlibre-meta
EOF
}

# ------------------------------------------------------------------- arisa ---
# Kho nhị phân tự dựng bằng GitHub Actions, KHÔNG phải kho của Arch/CachyOS.
# Không phải kho chính thức nên cần hỏi ý kiến thật sự, không phải hỏi cho
# có: thêm nó vào là pacman được quyền chạy code của kho đó bằng quyền root.
readonly ARISA_SERVER=https://github.com/slimulv1/arisa-repo/releases/download/repository
readonly ARISA_KEY_URL=$ARISA_SERVER/arisa.gpg
readonly ARISA_KEY_FPR=BD8284BAEE6197CF2EC59839A3C506C20357176E

# Hỏi y/n. 0 = có, 1 = không.
#
# Không đọc stdin khi stdin không phải terminal. install.sh chạy trong pipe,
# cron hay CI sẽ treo vô hạn ở `read`. Trường hợp đó lấy mặc định và nói rõ
# đang chọn gì, thay vì đoán.
confirm() {
    local prompt=$1 def=${2:-n} reply hint=${3:-}
    if [[ ! -t 0 ]]; then
        warn "không có terminal để hỏi — tự chọn '$def'."
        if [[ -n $hint ]]; then printf '    %s\n' "$hint"; fi
        if [[ $def == y ]]; then return 0; else return 1; fi
    fi
    local q='[y/N]'
    if [[ $def == y ]]; then q='[Y/n]'; fi
    while :; do
        printf '  %s %s ' "$prompt" "$q"
        read -r reply || reply=''
        case ${reply,,} in
            '')              if [[ $def == y ]]; then return 0; else return 1; fi ;;
            y|yes|co)        return 0 ;;
            n|no|khong)      return 1 ;;
        esac
        printf '  trả lời y hoặc n\n'
    done
}

# Đọc giá trị Server của đúng một mục trong file cấu hình pacman.
# Phải giới hạn theo mục — quét cả file sẽ trả về Server của mục đầu tiên
# (đã dính: [arisa] mà lại ra URL của [xlibre-beta] ở trên).
# So sánh tên mục bằng chuỗi thuần, không dùng regex: "arisa" chứa ký tự
# không đặc biệt nhưng "[xlibre]" thì có — truyền vào awk -v rồi so khớp regex
# sẽ hiểu [ là lớp ký tự.
pacman_section_server() {
    local file=$1 name=$2
    [[ -r $file ]] || return 0
    awk -v want="$name" '
        /^[[:space:]]*\[/ {
            s = $0
            gsub(/[[:space:]]/, "", s)
            inside = (s == "[" want "]")
            next
        }
        inside && /^[[:space:]]*Server[[:space:]]*=/ {
            line = $0
            sub(/^[^=]*=[[:space:]]*/, "", line)
            sub(/[[:space:]]+$/, "", line)
            print line
            exit
        }
    ' "$file"
}

arisa_add_key() {
    step "thêm khoá ký arisa ($ARISA_KEY_FPR)"
    if pacman-key --finger "$ARISA_KEY_FPR" >/dev/null 2>&1; then
        ok "khoá đã có trong keyring"
        return 0
    fi
    local tmp
    tmp="$(mktemp -d)"
    # shellcheck disable=SC2064
    trap "rm -rf '$tmp'" RETURN
    # README dùng `curl -LO` (tải vào thư mục hiện tại). Tải vào thư mục tạm
    # để không rác file .gpg vào ~/dwm khi chạy install.sh từ repo — bước còn
    # lại giữ nguyên.
    curl -fsSL -o "$tmp/arisa.gpg" "$ARISA_KEY_URL"
    as_root pacman-key --add "$tmp/arisa.gpg"
    # --lsign-key là bắt buộc: key vừa thêm mặc định trust là "unknown",
    # pacman sẽ từ chối package với lỗi "signature ... is marginal trust".
    as_root pacman-key --lsign-key "$ARISA_KEY_FPR"
    ok "khoá đã được trust"
}

arisa_add_repo() {
    step "bật repo [arisa] trong /etc/pacman.conf"

    local -a active=()
    local sec src
    while IFS=$'\t' read -r sec src; do
        [[ -n $sec ]] && active+=("$sec"$'\t'"$src")
    done < <(pacman_active_sections '^\[arisa[^]]*\]')

    if ((${#active[@]} > 1)); then
        local list="" a
        for a in "${active[@]}"; do
            list+="        ${a%%$'\t'*}  (trong ${a##*$'\t'})
"
        done
        die "đang bật nhiều mục [arisa*] — pacman chỉ được dùng một:
$list     Gỡ bớt rồi chạy lại."
    fi

    if ((${#active[@]} == 1)); then
        sec=${active[0]%%$'\t'*}
        src=${active[0]##*$'\t'}
        if [[ $sec != '[arisa]' ]]; then
            die "$sec đang bật trong $src — không phải tên mà tôi biết. Sửa tay rồi chạy lại."
        fi
        # Đã có sẵn thì không thêm lần nữa: hai mục [arisa] trùng nhau thì
        # pacman báo "Duplicate section" và HỎNG luôn, không phải chỉ thừa.
        local have
        have=$(pacman_section_server "$src" arisa)
        if [[ $have == "$ARISA_SERVER" ]]; then
            ok "[arisa] đã có trong $src với đúng Server, giữ nguyên"
        else
            warn "[arisa] trong $src nhưng Server là: ${have:-(không thấy dòng Server)}"
            warn "cần đúng URL thì đặt: $ARISA_SERVER"
        fi
        return 0
    fi

    # Theo README của arisa-repo: chèn block thẳng vào ĐẦU /etc/pacman.conf.
    # Không dùng file riêng + Include như XLibre — arisa không có nhiều kênh,
    # và README chỉ dạy cách này.
    #
    # Sửa /etc/pacman.conf của hệ thống nên sao lưu trước.
    root_sh -c '
        set -e
        f=/etc/pacman.conf
        bak="$f.tsuki-bak-$(date +%Y%m%d%H%M%S)"
        cp -a -- "$f" "$bak"
        # File tạm do mktemp sinh, không phải "$f.new" đặt cứng: nếu bị ngắt
        # giữa chừng thì không để lại rác trong /etc.
        new=$(mktemp /etc/pacman.conf.tsuki-XXXXXX)
        trap "rm -f -- \"\$new\"" EXIT
        {
            printf "%s\n" \
                "# Arisa — kho nhị phân tự dựng, KHÔNG phải kho chính thức Arch/CachyOS." \
                "# Do Tsuki install.sh chèn sau khi bạn đồng ý. Bỏ: xoá cả khối này rồi pacman -Sy" \
                "[arisa]" \
                "Server = $1" \
                "# Kho tự ký. Muốn bắt buộc kiểm tra chữ ký gói thì đổi thành:" \
                "#   SigLevel = Required DatabaseOptional" \
                "SigLevel = Optional DatabaseOptional" \
                ""
            cat -- "$f"
        } > "$new"
        # Ghi đè bằng `cat >` chứ không phải `mv`: giữ nguyên inode và quyền
        # của file gốc, và nếu hỏng giữa dòng thì còn file sao lưu.
        cat -- "$new" > "$f"
        echo "  + $f (sao lưu: ${bak##*/})"
    ' _ "$ARISA_SERVER"
    ok "đã bật [arisa]"
}

cmd_arisa() {
    printf '%sArisa — %s%s\n' "$C_B" "$ARISA_SERVER" "$C_RST"
    cat <<EOF
  Kho nhị phân dựng tự động bằng GitHub Actions, do
  github.com/slimulv1/arisa-repo phát hành. KHÔNG phải kho của Arch/CachyOS.

  Tsuki cần nó cho hai gói trong PKG_KEYBINDS:
    visual-studio-code-bin   Super+C
    discord-ptb              Super+D
  Không thêm kho này thì hai phím đó không hoạt động, phần còn lại vẫn bình
  thường — nên từ chối cũng được.

  Thêm vào nghĩa là pacman được chạy code từ kho này bằng quyền root.
EOF

    if ! confirm "thêm kho arisa?" n "bật tay: ./install.sh arisa"; then
        info "bỏ qua arisa"
        return 0
    fi

    detect_sudo
    # Key trước, kho sau — ngược thứ tự README. Hai bước độc lập và `pacman -Sy`
    # chạy sau cùng nên kết quả như nhau, nhưng làm key trước thì không có
    # khoảnh khắc nào pacman.conf đã trỏ tới kho mà keyring chưa có key.
    arisa_add_key
    arisa_add_repo

    step "đồng bộ index"
    # -Sy chứ không phải -Syyu: thêm kho mới không đòi nâng cấp cả hệ thống,
    # nên --noconfirm ở đây vô hại (khác với -Syyu trong cmd_xlibre, đó mới là
    # nâng cấp toàn hệ thống và Arch không hỗ trợ partial upgrade).
    as_root pacman -Sy --noconfirm

    ok "arisa xong — gói của kho này đã sẵn sàng cho ./install.sh deps"
}

# ------------------------------------------------- paru + bộ gõ Lotus (VN) ---
# Repo này có 2 gói đến từ AUR nên cần AUR helper trước.
readonly PARU_GIT=https://aur.archlinux.org/paru.git
# Clone vào ~/.local/src, KHÔNG clone vào thư mục repo — `git clone` không có
# đường dẫn đích sẽ rơi vào cwd, mà cwd khi chạy install.sh là ~/dwm, tức là
# rác vào chính repo đang chạy.
readonly PARU_SRC=$HOME/.local/src/paru

# PKGBUILD của paru: makedepends=('cargo'), depends=('git' 'pacman' 'libalpm.so>=14')
readonly PKG_AUR=(
    cargo
)
# Gói bộ gõ. Không có trong kho nào của Arch/CachyOS, chỉ có ở AUR.
readonly PKG_PTY=(
    fcitx5-lotus-bin
)

# Tên người gọi, đúng cả khi chạy `sudo ./install.sh`. `id -un` lúc đó trả về
# root, bật service theo tên root thì vô dụng.
tsuki_user() { printf '%s\n' "${SUDO_USER:-${USER:-$(id -un)}}"; }

cmd_paru() {
    if command -v paru >/dev/null 2>&1; then
        ok "paru đã có: $(paru --version 2>/dev/null | head -1)"
        return 0
    fi

    install_pkgs PKG_AUR "aur-build"
    step "clone paru ($PARU_GIT)"
    mkdir -p "$(dirname -- "$PARU_SRC")"
    rm -rf -- "$PARU_SRC"
    git clone --depth 1 "$PARU_GIT" "$PARU_SRC"

    step "build paru"
    # KHÔNG as_root ở đây: makepkg từ chối chạy dưới root ("Running makepkg as
    # root is not allowed"). Root chỉ dùng ở bước pacman -U ngay dưới đây.
    ( cd "$PARU_SRC" && makepkg -sf --noconfirm ) || die "build paru thất bại"

    local pkg
    # -print -quit thay cho `| head -1`: dưới pipefail, head thoát sớm làm find
    # dính SIGPIPE (141) và set -e giết script. Đã dính lỗi này ở cmd_firefox.
    pkg=$(find "$PARU_SRC" -maxdepth 1 -name '*.pkg.tar.*' -print -quit)
    [[ -n $pkg ]] || die "build xong nhưng không thấy *.pkg.tar.* trong $PARU_SRC"
    as_root pacman -U --noconfirm "$pkg"
    command -v paru >/dev/null 2>&1 || die "pacman -U xong nhưng vẫn không gọi được paru"
    ok "paru: $(paru --version 2>/dev/null | head -1)"
}

cmd_pty() {
    step "bộ gõ Lotus — tiếng Việt"
    cmd_paru

    local -a want=()
    mapfile -t want < <(missing_pkgs PKG_PTY)
    if ((${#want[@]})); then
        step "cài từ AUR: ${want[*]}"
        # --noconfirm vì người dùng đã đồng ý bằng cách chạy lệnh này; paru
        # vẫn tự hỏi mật khẩu sudo một lần.
        paru -S --needed --noconfirm -- "${want[@]}" || die "paru không cài được: ${want[*]}"
    else
        ok "đã có: ${PKG_PTY[*]}"
    fi

    # User cần cho unit là `uinput_proxy`, KHÔNG phải "lotus" — xem
    # /usr/lib/sysusers.d/lotus.conf do chính gói đó cài:
    #   u  uinput_proxy  -  "Lotus Uinput Proxy"
    #   m  uinput_proxy  input
    # Unit chạy `User=uinput_proxy Group=input`, nên phải có user trước khi
    # enable, không thì systemctl start sẽ fail.
    step "tạo user uinput_proxy"
    as_root systemd-sysusers
    getent passwd uinput_proxy >/dev/null 2>&1 ||
        die "sysusers xong nhưng user uinput_proxy vẫn chưa có — kiểm tra /usr/lib/sysusers.d/lotus.conf"

    step "module uinput"
    # `lsmod | grep -q` SAI dưới `set -o pipefail`: grep -q thoát ngay khi
    # thấy dòng khớp, đóng pipe, lsmod dính SIGPIPE (141), pipefail đưa cả
    # pipeline về 141 -> if rơi nhánh else -> modprobe chạy lại vô ích.
    # Đã tái hiện. Vì thế hút hết lsmod vào biến trước, rồi grep trên đó.
    local mods
    mods=$(lsmod)
    if grep -q '^uinput' <<<"$mods"; then
        ok "uinput đang chạy"
    else
        as_root modprobe uinput
    fi
    # modprobe chỉ có tác dụng tới lần boot này. Không ghi modules-load.d thì
    # reboot là mất, và service sẽ fail vì không có /dev/uinput.
    if [[ -f /etc/modules-load.d/uinput.conf ]]; then
        ok "/etc/modules-load.d/uinput.conf đã có"
    else
        root_sh -c 'install -d -m 755 /etc/modules-load.d
            printf "uinput\n" > /etc/modules-load.d/uinput.conf
            chmod 644 /etc/modules-load.d/uinput.conf
            echo "  + /etc/modules-load.d/uinput.conf"'
    fi

    local unit="fcitx5-lotus-server@$(tsuki_user).service"
    step "bật $unit"
    as_root systemctl enable --now "$unit"

    step "tắt ibus (xung đột với fcitx5)"
    if pgrep -x ibus-daemon >/dev/null 2>&1; then
        pkill -x ibus-daemon || true
        ok "đã dừng ibus-daemon"
    else
        ok "ibus-daemon không chạy"
    fi
    # kill chỉ dừng được tiến trình, không tắt autostart. Nếu ibus tự quay lại
    # ở lần đăng nhập sau thì phải bỏ autostart của nó, không có cách nào
    # chung cho mọi DE — nên nói rõ thay vì giả vờ đã xong.
    systemctl is-active --quiet ibus 2>/dev/null &&
        warn "service ibus đang bật — sẽ kéo ibus-daemon lại ở lần đăng nhập sau"

    ok "bộ gõ Lotus xong. Đăng xuất rồi đăng nhập lại để biến môi trường có hiệu lực."
    info "biến IM đã có sẵn trong .config/fish/config.fish và scripts/run.sh — không cần thêm gì"
}

# -------------------------------------------------------------- uninstall ---
cmd_uninstall() {
    detect_sudo
    step "gỡ binary Tsuki khỏi $PREFIX/bin"
    local b
    for b in dwm st slock dmenu slstatus; do
        if [[ -f "$PREFIX/bin/$b" ]]; then
            as_root rm -f -- "$PREFIX/bin/$b"
            ok "xóa $b"
        fi
    done
    as_root rm -f -- "$PREFIX/share/man/man1/dwm.1"
    step "giữ nguyên dotfiles trong ~/.config (không tự xóa)"
    # if/then chứ không phải [[ ]] && { ... }: AND-list ở CUỐI hàm sẽ khiến
    # hàm trả về 1 khi file không tồn tại, và set -e coi đó là lỗi -> script
    # exit 1 dù đã gỡ xong sạch.
    if [[ -f /usr/share/xsessions/Tsuki.desktop ]]; then
        as_root rm -f /usr/share/xsessions/Tsuki.desktop
        ok "xóa Tsuki.desktop"
    fi
}

# ------------------------------------------------------------------- main ---
# In khối mở đầu (dòng "#   ./install.sh ...") một cách ổn định: lấy từ
# dòng đầu tiên có "install.sh" cho tới dòng "#" trống kế sau nó.
# Hardcode '3,12p' sẽ cắt mất dòng mới mỗi lần thêm lệnh vào header.
usage() {
    sed -n '/^#   \.\/install\.sh/,/^#$/p' "${BASH_SOURCE[0]}" | sed 's/^# \?//'
}

main() {
    local cmd=${1:-all}
    case $cmd in
        deps)      cmd_deps ;;
        build)     cmd_build ;;
        dotfiles)  cmd_dotfiles; cmd_firefox ;;
        session)   cmd_session "${2:-}" ;;
        xlibre)    cmd_xlibre "${2:-stable}" ;;
        arisa)     cmd_arisa ;;
        paru)      cmd_paru ;;
        pty)       cmd_pty ;;
        uninstall) cmd_uninstall ;;
        all)
            # Trước deps: PKG_KEYBINDS có visual-studio-code-bin và discord-ptb
            # nằm trong kho arisa. Hỏi sau khi cài deps thì hai gói đó đã bị
            # bỏ qua rồi, phải chạy lại ./install.sh deps mới lấy được.
            cmd_arisa
            cmd_deps
            # Sau deps: cần base-devel + cargo mới build được paru.
            cmd_pty
            cmd_build
            cmd_dotfiles
            cmd_firefox
            cmd_session
            ;;
        -h|--help|help) usage ;;
        *) die "lệnh lạ: $cmd  (xem --help)" ;;
    esac
}

main "$@"

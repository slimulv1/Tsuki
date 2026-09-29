#!/usr/bin/env bash
#
# install.sh — cài Tsuki (dwm rice) trên Arch/CachyOS.
#
#   ./install.sh              # cài đầy đủ: deps -> build -> dotfiles -> session
#   ./install.sh deps         # chỉ cài gói phụ thuộc
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
# Gom theo nhóm để `install.sh deps` đọc được; nhóm rỗng nghĩa là không cài.
readonly PKG_CORE=(
    base-devel git make pkgconf
    libx11 libxft libxinerama libxrender
    fontconfig freetype2 harfbuzz libjpeg-turbo libwebp
)
# Tsuki chạy X11 thuần: không cài xorg-xwayland, không bật Xwayland trong
# run.sh. XWayland mở được app Wayland-only, đổi lại clipboard và chia sẻ màn
# hình bị vỡ — không đáng. Muốn bật thì tự thêm, xem scripts/run.sh.
readonly PKG_SESSION=(
    xorg-server xorg-xrdb xorg-xset xorg-xinit
)
readonly PKG_DESKTOP=(
    feh picom xsettingsd dunst libnotify polkit-gnome
    kitty fastfetch fish starship dash python
    fcitx5 ttf-jetbrains-mono-nerd ttc-iosevka
    networkmanager playerctl libpulse qrencode curl
    iw wpa_supplicant
)
readonly PKG_FIREFOX=(
    firefox
)

missing_pkgs() {
    local -n ref=$1
    local p
    for p in "${ref[@]}"; do
        pacman -Qq "$p" >/dev/null 2>&1 || printf '%s\n' "$p"
    done
}

install_pkgs() {
    local -n ref=$1
    local label=$2
    local missing
    mapfile -t missing < <(missing_pkgs "$ref")
    if (( ${#missing[@]} == 0 )); then
        ok "$label: đã đủ"
        return 0
    fi
    step "cài gói ($label): ${#missing[@]} thiếu"
    printf '    %s\n' "${missing[*]}"
    root_sh -c 'pacman -S --needed --noconfirm "$@"' _ "${missing[@]}"
    ok "$label: xong"
}

cmd_deps() {
    detect_sudo
    install_pkgs PKG_CORE     "build"
    install_pkgs PKG_SESSION "session"
    install_pkgs PKG_DESKTOP "desktop"
    install_pkgs PKG_FIREFOX "firefox"
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
    local n=0 d
    for d in dunst fastfetch kitty picom xsettingsd fish firefox; do
        if [[ -d "$REPO_DIR/.config/$d" ]]; then
            install_dotfile "$REPO_DIR/.config/$d" "$HOME/.config/$d"
            n=$((n + 1))
        fi
    done
    [[ -f $REPO_DIR/.config/starship.toml ]] &&
        install_dotfile "$REPO_DIR/.config/starship.toml" "$HOME/.config/starship.toml"
    ok "xong ($n thư mục)"
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
DesktopNames=dwm
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

xlibre_add_repo() {
    local repo=$1
    step "thêm repo [$repo] vào /etc/pacman.conf"
    if grep -qF "[$repo]" /etc/pacman.conf; then
        ok "đã có sẵn"
        return 0
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
    ok "repo [$repo]"
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
        uninstall) cmd_uninstall ;;
        all)
            cmd_deps
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

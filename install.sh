#!/usr/bin/env bash
#
# install.sh — cài Tsuki (dwm rice) trên Arch/CachyOS.
#
#   ./install.sh              # cài đầy đủ: deps -> build -> dotfiles -> session
#   ./install.sh check        # kiểm tra máy đã đủ công cụ chưa (không sửa gì)
#   ./install.sh deps         # chỉ gói phụ thuộc (hỏi rồi cài XLibre stable)
#   ./install.sh arisa        # hỏi rồi thêm kho arisa (Super+C, Super+D)
#   ./install.sh paru         # cài paru để dùng AUR
#   ./install.sh pty          # bộ gõ Lotus (tiếng Việt) — cần paru
#   ./install.sh build        # chỉ build + cài binary
#   ./install.sh dotfiles     # chỉ copy ~/.config
#   ./install.sh firefox      # chỉ nạp giao diện vào profile Firefox
#   ./install.sh firefox <thư mục profile>   # chỉ định profile (khi tự dò trượt)
#   ./install.sh themes       # chỉ cài theme Miami26 + icon Kora (từ git, user-level)
#   ./install.sh session      # chỉ cấu hình chạy từ TTY (.xinitrc)
#   ./install.sh session --dm # cài thêm .desktop cho display manager
#   ./install.sh uninstall    # gỡ binary Tsuki đã cài
#   ./install.sh xlibre beta      # thử XLibre beta (25.2) — nâng cấp cả hệ thống
#   ./install.sh xlibre oldstable # kênh cũ (25.0)
#
# XLibre thay X.Org: `deps` tự hỏi rồi cài bản STABLE, không cần làm gì thêm.
# Muốn beta thì thêm lệnh `xlibre beta` vào sau. Lệnh `xlibre` ở trên không
# phải để "chuyển sang XLibre" — việc đó đã tự động rồi; nó chỉ để đổi kênh,
# và sẽ nâng cấp toàn hệ thống (`pacman -Syyu`).
#
# Không chạy `make clean` ở đâu cả: config.h là cấu hình thật của máy, đã được
# git track; `make clean` ở các Makefile cũ từng xoá nó rồi cp lại từ
# config.def.h, âm thầm thay hết tùy chỉnh. Xem scripts/rebuild.sh.
#
set -euo pipefail

# Chuẩn hóa locale cho MỌI lệnh con.
#
# Vì sao: script có so khớp chuỗi trên output của lệnh khác — `sort` trong
# pkgs_absent_in_db, so sánh trong `grep` của các hàm dò profile, awk trên
# /etc/pacman.d/mirrorlist. Khi LANG của người dùng là ngôn ngữ khác (fr_FR,
# de_DE, vi_VN...), `sort` đổi thứ tự so với byte, `[[:space:]]` trong awk
# phụ thuộc locale, và thông báo lỗi của pacman/make đổi ngôn ngữ. Cài trên
# máy người khác thì hành vi khác máy này — đúng thứ ta muốn tránh.
# LC_ALL=C chỉ ảnh hưởng lệnh con; printf của chính script vẫn in tiếng Việt
# bình thường (printf truyền byte qua, không dịch).
export LC_ALL=C

REPO_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
readonly REPO_DIR
SUDO=""
PREFIX="${PREFIX:-/usr/local}"

# ---------------------------------------------------------------- logging ---
if [[ -t 1 && -z ${NO_COLOR:-} ]]; then
    C_RST=$'\033[0m' C_R=$'\033[1;31m' C_G=$'\033[1;32m'
    C_Y=$'\033[1;33m' C_B=$'\033[1;34m'
else
    C_RST="" C_R="" C_G="" C_Y="" C_B=""
fi
step() { printf '%s==>%s %s%s%s\n' "$C_B" "$C_RST" "$C_B" "$*" "$C_RST"; }
ok()   { printf '  %s✓%s %s\n' "$C_G" "$C_RST" "$*"; }
info() { printf '  %s·%s %s\n' "$C_B" "$C_RST" "$*"; }
warn() { printf '  %s!%s %s\n' "$C_Y" "$C_RST" "$*" >&2; }
die()  { printf '%serror:%s %s\n' "$C_R" "$C_RST" "$*" >&2; exit 1; }

# Rút gọn đường dẫn về ~/ để thông báo dễ đọc.
#
# KHÔNG dùng `${p/#$HOME/~}`: đã thử, không rút được khi chuỗi bằng đúng
# $HOME (trả về nguyên đường dẫn). Hàm tường minh hơn, không phụ thuộc chi tiết
# khác của bash.
tilde() {
    local p=$1
    if [[ -z ${HOME:-} ]]; then
        printf '%s' "$p"
    elif [[ $p == "$HOME" ]]; then
        printf '~'
    elif [[ $p == "$HOME"/* ]]; then
        printf '~/%s' "${p#"$HOME"/}"
    else
        printf '%s' "$p"
    fi
}

# --------------------------------------------------------------- preflight ---
# Kiểm tra công cụ cần thiết TRƯỚC khi làm việc.
#
# Không phải để "chắc chắn có" — mà để lỗi thiếu lệnh hiện ra NGAY ĐẦU, chứ
# không phải giữa chừng: `make` thiếu mà chạy `cmd_build` thì lỗi nằm trong
# `root_sh` của bash với quyền root, đọc như build hỏng chứ không phải thiếu
# toolchain. Máy khác máy này càng dễ dính vì image cài sẵn khác nhau.
need() {
    local -a missing=()
    local c
    for c in "$@"; do
        command -v "$c" >/dev/null 2>&1 || missing+=("$c")
    done
    if (( ${#missing[@]} )); then
        die "thiếu lệnh: ${missing[*]}
       Cài trước:  sudo pacman -S --needed ${missing[*]}"
    fi
}

# Báo cáo mọi thứ install.sh cần, KHÔNG sửa gì cả. Dùng để hỏi "máy tôi có
# chạy được không" trước khi chạy `all`, và để người khác chạy script trên máy
# mới rồi dán kết quả lên issue.
cmd_check() {
    step "kiểm tra môi trường"
    local -a warns=()
    local g c name tools d

    # 1. Hệ điều hành
    if [[ -r /etc/os-release ]]; then
        local os_id os_ver
        os_id=$(. /etc/os-release 2>/dev/null; printf '%s' "${ID:-?}")
        os_ver=$(. /etc/os-release 2>/dev/null; printf '%s' "${VERSION_ID:-${PRETTY_NAME:-?}}")
        case $os_id in
            arch|cachyos) ok "OS: $os_id $os_ver" ;;
            *) warn "OS: $os_id $os_ver — script viết cho Arch/CachyOS (dùng pacman)"
               warns+=(os) ;;
        esac
    else
        warn "không đọc được /etc/os-release"; warns+=(os)
    fi
    command -v pacman >/dev/null 2>&1 \
        || { warn "không có pacman — phần lớn bước sẽ không chạy"; warns+=(pacman); }

    # 2. Công cụ theo từng nhóm lệnh
    for g in "build|make gcc nproc" \
             "deps|pacman" \
             "pty|paru git makepkg" \
             "themes|git curl" \
             "session|systemctl"
    do
        name=${g%%|*}
        tools=${g#*|}
        local -a t=() miss=()
        read -ra t <<< "$tools"
        for c in "${t[@]}"; do
            command -v "$c" >/dev/null 2>&1 || miss+=("$c")
        done
        if (( ${#miss[@]} )); then
            warn "$name: thiếu ${miss[*]}"
            warns+=("$name")
        else
            ok "$name: ${t[*]}"
        fi
    done

    # 3. Quyền root
    if (( EUID == 0 )); then
        ok "đang chạy với quyền root"
    elif command -v sudo >/dev/null 2>&1; then
        ok "có sudo (sẽ hỏi mật khẩu khi cần)"
    else
        warn "không có sudo và không phải root — các bước cài gói sẽ dừng"
        warns+=(sudo)
    fi

    # 4. Repo: config.h phải có, nếu không make sẽ tự tạo lại từ config.def.h
    # và xoá sạch tuỳ chỉnh (xem cảnh báo đầu script).
    local bad_cfg=0
    for d in . st slock dmenu slstatus netpanel; do
        [[ -d $REPO_DIR/$d ]] || continue
        [[ -f $REPO_DIR/$d/config.h ]] || { bad_cfg=1; warns+=("$d/config.h"); }
    done
    if (( bad_cfg )); then
        warn "thiếu config.h — build sẽ cp từ config.def.h và mất cấu hình"
    else
        ok "config.h trong repo: đủ"
    fi

    # 5. Thư mục đích
    if [[ -w $TSUKI_HOME ]]; then
        ok "thư mục đích: $(tilde "$TSUKI_HOME")"
    else
        warn "không ghi được vào $TSUKI_HOME"; warns+=(home)
    fi

    # 6. Profile Firefox — báo cáo, KHÔNG tự chọn (khi có nhiều, cmd_firefox hỏi)
    local -a cands=()
    mapfile -t cands < <(firefox_candidates) || true
    if (( ${#cands[@]} == 0 )); then
        info "Firefox: chưa thấy profile nào (mở Firefox một lần rồi chạy lại)"
    elif (( ${#cands[@]} == 1 )); then
        ok "Firefox: $(tilde "${cands[0]}")"
    else
        warn "Firefox: ${#cands[@]} profile, sẽ hỏi khi cài"
        for c in "${cands[@]}"; do printf '    %s\n' "$(tilde "$c")"; done
    fi

    printf '\n'
    if (( ${#warns[@]} )); then
        warn "còn ${#warns[@]} điểm cần xử lý: ${warns[*]}"
        printf '  ./install.sh deps cài phần thiếu; bước chưa sẵn sàng thì bỏ qua.\n'
        return 0
    fi
    ok "mọi thứ đã sẵn sàng"
}

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

# ------------------------------------------------- người dùng và thư mục nhà ---
# Cả hai hàm này phải đúng khi chạy `sudo ./install.sh` (EUID=0) lẫn khi chạy
# trong shell root thật. `tsuki_user` chỉ cần tên cho tên unit systemd;
# `tsuki_home` cần đường dẫn tuyệt đối để đặt dotfiles.
#
# Vì sao không dùng thẳng $HOME: sudo mặc định GIỮ $HOME của người gọi
# (always_set_home tắt), nên `sudo ./install.sh` ra đúng. Nhưng trong shell
# root thật thì $HOME=/root, và dotfiles sẽ rơi vào /root/.config — cài xong
# tưởng không có gì xảy ra. SUDO_USER thì đúng cả hai đường.
tsuki_user() {
    printf '%s\n' "${SUDO_USER:-${USER:-$(id -un)}}"
}

tsuki_home() {
    local h=""
    if [[ -n ${SUDO_USER:-} ]]; then
        h=$(getent passwd "$SUDO_USER" 2>/dev/null | cut -d: -f6) || h=""
    fi
    printf '%s\n' "${h:-$HOME}"
}
# SC2155: `readonly X=$(...)` để readonly nuốt luôn exit code của lệnh, nên
# tsuki_home hỏng thì TSUKI_HOME vẫn được set và ta không biết. Tách ra.
TSUKI_HOME=$(tsuki_home)
readonly TSUKI_HOME

# ------------------------------------------------------------------ backup ---
# Đường dẫn backup CHƯA TỪNG dùng, cùng họ với $1. Chặn cả hai kiểu trùng:
#
#   - `date +%Y%m%d%H%M%S` chỉ chính xác tới GIÂY. Chạy `./install.sh dotfiles`
#     rồi `./install.sh session` trong cùng một giây thì lần hai ghi đè đúng
#     file backup của lần một — mất bản cũ mà không có dấu vết. Đã tái hiện.
#   - Nếu $bak đã tồn tại và là THƯ MỤC thì `mv -- $1 $bak` đặt $1 BÊN TRONG
#     $bak chứ không thay thế nó: /x.tsuki-bak-…/x. Backup cũ bị dính rác và
#     `cp` sau đó tạo lại $1 từ đầu. Đã tái hiện.
backup_path() {
    local p=$1 ts bak n
    ts=$(date +%Y%m%d%H%M%S)
    for n in 0 1 2 3 4 5 6 7 8 9; do
        if (( n == 0 )); then bak="$p.tsuki-bak-$ts"; else bak="$p.tsuki-bak-$ts-$n"; fi
        [[ -e $bak || -L $bak ]] || { printf '%s\n' "$bak"; return 0; }
    done
    die "không tìm được tên backup trống cho $p (thử $ts-0 đến $ts-9, hết chỗ)"
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
#
# Vì sao có "shellcheck disable=SC2034" trước từng mảng PKG_*: shellcheck báo
# chúng "appears unused". Sai. Chúng được đọc qua nameref (`local -n ref=$1`)
# nên shellcheck không thấy chỗ dùng. Không có dòng đó thì lần shellcheck sau
# sẽ có người "sửa" bằng cách xoá mảng đi.

# --- 1. build ---
# bo qua SC2034 o day: shellcheck khong thay mang doc qua nameref
# (xem ghi chuc dau muc "packages")
# shellcheck disable=SC2034
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
# bo qua SC2034 o day: shellcheck khong thay mang doc qua nameref
# (xem ghi chuc dau muc "packages")
# shellcheck disable=SC2034
readonly PKG_SESSION=(
    # X server. Tên gói vẫn là xorg-server nhưng `missing_pkgs` hỏi
    # `pacman -Qq xorg-server`, mà xlibre-xserver khai báo
    # `Provides: xorg-server` — nên khi XLibre đã cài, dòng này tự coi là
    # đủ và KHÔNG kéo X.Org xuống. Vì vậy cmd_deps phải gọi cmd_xlibre_auto
    # TRƯỚC install_pkgs PKG_SESSION; đảo thứ tự thì xorg-server về trước rồi
    # mới bị xlibre-meta thay, tốn vô ích một vòng cài/gỡ.
    xorg-server
    # startx — .config/fish/conf.d/tsuki.fish chặn `dwm` nếu thiếu startx
    xorg-xinit
    # scripts/run.sh: xrdb nạp .Xresources, xset đổi nền chuột
    xorg-xrdb xorg-xset
    # scripts/run.sh:114 — `xsetroot -cursor_name Bibata-Modern-Ice` nạp theme
    # cursor vào CORE CURSOR FONT của X, nhờ đó XCreateFontCursor() trong dwm
    # (bar) và st (vùng text) cũng ra ảnh trong theme. xorg-xsetroot CHƯA có
    # sẵn: nhóm xorg-xrdb/xorg-xset ở trên không cung cấp xsetroot.
    xorg-xsetroot
    # Theme cursor. PHẢI nằm ở /usr/share/icons: libXcursor mặc định chỉ tìm
    # trong /usr/share/icons và /usr/share/pixmaps — thư mục ~/.icons hay
    # ~/.local/share/icons KHÔNG được tìm tới (đã thử: XcursorLibraryPath()
    # trả về chuỗi có dấu '~' chưa bung, và bản đặt ở đó vẫn load fail).
    # Nên bản user-level chỉ giúp được app GTK, không nạp được cho X11 core.
    bibata-cursor-theme
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
    # Thumbnail cho Thunar. Tumbler là daemon theo Thumbnailer Specification;
    # Thunar hỏi nó qua D-Bus rồi mới vẽ ảnh nhỏ. KHÔNG có tumbler thì
    # Thunar mở lên toàn icon chữ cái — đúng triệu chứng "không có thumbnail".
    #   - tumbler kéo gdk-pixbuf: ảnh png/jpg/gif/webp/bmp/tiff/svg/…
    #   - tumbler-kde-thumbnailer: chỉ làm việc với KDE, thừa ở đây, không
    #     cài. ffmpegthumbnailer đã nằm trong gói tumbler? Không — phải cài
    #     riêng, xem dòng dưới.
    tumbler
    # Plugin thumbnail cho VIDEO. ffmpegthumbnailer đọc được hầu hết codec
    # (mp4/mkv/webm/avi/mov/m4v) nên Thunar hiện được khung hình thay vì
    # icon. Nó là Optional Dep chính thức của tumbler: `Optional Deps:
    # ffmpegthumbnailer: audio and video thumbnails`. Cài cả `ffmpeg` lẫn
    # `ffmpegthumbnailer`: cái sau cần cái trước để giải mã, và `ffmpeg` còn
    # dùng cho scripts/mediacard.sh (lyrics).
    ffmpegthumbnailer
    # Optional Dep còn lại của tumbler: trang đầu PDF. Trình quản lý file
    # duyệt PDF nhiều, mà không có cái này thì PDF hiện icon trắng.
    poppler-glib
    # scripts/run.sh:98 `start_daemon fcitx fcitx5 -d` — daemon bộ gõ. Thiếu
    # thì vẫn có bàn phím, mất gõ tiếng Việt. Engine Lotus tới từ AUR nên
    # nằm ở PKG_PTY, xem cmd_pty.
    fcitx5
)

# --- 3. app có dotfile trong dwm/.config ---
# Thứ tự khớp với thứ tự mục trong dwm/.config. Thêm dotfile mới thì phải sửa
# cả mảng này lẫn `items` trong cmd_dotfiles — hai chỗ phải khớp 1-1.
# bo qua SC2034 o day: shellcheck khong thay mang doc qua nameref
# (xem ghi chuc dau muc "packages")
# shellcheck disable=SC2034
readonly PKG_CONFIG=(
    dunst        # .config/dunst/
    fastfetch    # .config/fastfetch/
    firefox      # .config/firefox/
    fish         # .config/fish/
    gtk3         # .config/gtk-3.0/ (cursor theme cho app GTK3: Firefox...)
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
# bo qua SC2034 o day: shellcheck khong thay mang doc qua nameref
# (xem ghi chuc dau muc "packages")
# shellcheck disable=SC2034
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
    # Tridactyl — điều khiển Firefox bằng bàn phím kiểu Vim. KHÔNG có dotfile
    # trong .config (nên không thuộc PKG_CONFIG, vì PKG_CONFIG và items trong
    # cmd_dotfiles phải khớp 1-1) và không mở bằng phím tắt.
    # CÓ SẴN trong kho `extra` — tridactyl-guide.md:206 nói lấy ở AUR là
    # không còn đúng, nên không đưa vào PKG_PTY (nhóm AUR).
    firefox-tridactyl
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

# Số tiến trình song song cho các vòng hỏi pacman. `pacman -Qq` chỉ đọc cơ sở
# dữ liệu cục bộ nên chạy song song được, không cần khoá.
readonly JOBS=${JOBS:-8}

# Hỏi pacman về từng gói trong "$@", CHẠY SONG SONG, in ra gói nào không có.
#
# CỐ Ý vẫn hỏi TỪNG gói, chỉ chạy song song — không gộp thành
# `pacman -Qq p1 p2 …`. Bản liệt kê không kèm `Provides`, nên XLibre sẽ bị
# coi là thiếu rồi cài đè. Đã kiểm trên máy đang chạy XLibre:
#
#     pacman -Qq | grep -cx xorg-server   ->  0            (không trong danh sách)
#     pacman -Qq xorg-server              ->  xlibre-xserver
#
# Gộp lại là mất đúng thứ mà cmd_xlibre_auto sinh ra để tránh. Nếu sau này ai
# tối ưu tiếp chỗ này thì đọc lại đoạn này trước đã.
#
# `sort` chỉ để thứ tự ổn định giữa các lần chạy, không phải để sắp xếp.
# -0 để tên gói có ký tự lạ cũng an toàn; -r để "$@" rỗng thì không gọi sh.
pkgs_absent_in_db() {
    (($#)) || return 0
    printf '%s\0' "$@" |
        xargs -0 -P"$JOBS" -r -I{} \
            sh -c 'pacman -Qq "$1" >/dev/null 2>&1 || printf "%s\n" "$1"' _ {} |
        sort
}

missing_pkgs() {
    local -n ref=$1
    ((${#ref[@]})) || return 0
    pkgs_absent_in_db "${ref[@]}"
}

# Trong "$@", in ra gói KHÔNG có trong kho nào đang bật. Cần vì `pacman -S a b
# c` huỷ CẢ LÔ khi chỉ một gói không tìm thấy ("target not found") — đã kiểm:
# cho `pacman -Sp less fake-pkg-xyz` thì cả `less` cũng không được nạp, exit 1.
# Mấy gói như visual-studio-code-bin hay discord-ptb nằm ở repo thứ ba, thiếu
# repo đó là toàn bộ nhóm hỏng theo.
pkgs_absent_in_repos() {
    (($#)) || return 0
    printf '%s\0' "$@" |
        xargs -0 -P"$JOBS" -r -I{} \
            sh -c 'pacman -Sddp "$1" >/dev/null 2>&1 || printf "%s\n" "$1"' _ {} |
        sort
}

available_pkgs() {
    (($#)) || return 0
    local -a bad=() ok=()
    mapfile -t bad < <(pkgs_absent_in_repos "$@")
    if ((${#bad[@]})); then
        warn "không có trong kho nào đang bật, bỏ qua: ${bad[*]}"
        # Tập tra O(1) thay vì lồng hai vòng O(n·m).
        local -A gone=()
        local p
        for p in "${bad[@]}"; do gone[$p]=1; done
        for p in "$@"; do [[ -n ${gone[$p]:-} ]] || ok+=("$p"); done
    else
        ok=("$@")
    fi
    ((${#ok[@]})) || return 0
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
    # Một gói mỗi dòng, không phải "${missing[*]}" gộp cả nhóm lên một dòng:
    # PKG_KEYBINDS hơn 20 gói, một dòng dài sẽ vỡ khung terminal.
    printf '    %s\n' "${missing[@]}"
    available_pkgs "${missing[@]}"
    ok "$label: xong"
}

cmd_deps() {
    detect_sudo
    install_pkgs PKG_BUILD      "build"
    # XLibre trước PKG_SESSION: xlibre-xserver Provides xorg-server, đặt trước
    # thì PKG_SESSION không kéo X.Org xuống. Đảo thứ tự là tốn hai vòng cài/gỡ.
    cmd_xlibre_auto
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
    need make gcc nproc
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

# File mà NỘI DUNG MÀU được sinh tự động, không phải cấu hình người dùng.
#
# VÌ SAO CẦN: `scripts/dunstwal.sh` (chạy bởi Super+W) sửa trực tiếp màu
# trong ~/.config/dunst/dunstrc và ~/.config/kitty/pywal.conf theo wallpaper
# đang dùng. Nhưng repo cũng track hai file đó, kèm bảng màu của MỘT wallpaper
# cụ thể. Chạy `./install.sh dotfiles` là ghi đè màu đang chạy bằng bảng màu
# cũ trong repo — người dùng thấy giao diện tự đổi về màu lạ. Đã xảy ra thật
# trên máy này: dunst 28 dòng và pywal.conf 42 dòng bị đổi, phải khôi phục từ
# backup mới được.
#
# Cách xử lý: nếu hai file khác nhau CHỈ ở mã màu thì giữ bản đang chạy. Cấu
# hình khác (kích thước, font, phím tắt…) vẫn cập nhật bình thường. Cài mới
# hoàn toàn thì file đích chưa tồn tại nên vẫn copy bản repo — không mất mặc
# định.
readonly COLOR_GENERATED=(
    dunstrc
    pywal.conf
)

is_color_generated() {
    local name=$1 f
    for f in "${COLOR_GENERATED[@]}"; do
        [[ $name == "$f" ]] && return 0
    done
    return 1
}

# Hai file có khác nhau KHÔNG, ngoài các mã màu hex không?
#
# Bỏ mọi mã `#rrggbb` / `#rgb` (kể cả 8 chữ số có alpha) rồi so phần còn
# lại. Cùng cấu trúc, chỉ khác bảng màu -> sinh tự động, giữ bản hiện tại.
#
# `sed -E` thay vì `sed` vì repo cần BSD/GNU-compatible; dùng `[[:xdigit:]]`
# để không phụ thuộc locale (đã export LC_ALL=C ở đầu script).
color_only_diff() {
    local a=$1 b=$2
    [[ -f $a && -f $b ]] || return 1
    # Khác loại file (một bên là thư mục) -> không phải trường hợp này
    diff -q -- "$a" "$b" >/dev/null 2>&1 && return 1   # giống hệt thì không "chỉ khác màu"
    local sa sb
    sa=$(strip_colors < "$a")
    sb=$(strip_colors < "$b")
    [[ $sa == "$sb" ]]
}

# Bỏ mọi mã màu hex ra khỏi stdin.
strip_colors() {
    sed -E 's/#[0-9A-Fa-f]{3,8}\b//g'
}

# Cài MỘT mục dotfile, giữ nguyên file có mã màu sinh tự động.
#
# Cần hàm riêng vì cmd_dotfiles copy NGUYÊN THƯ MỤC (`.config/dunst/` ->
# `~/.config/dunst/`), nên logic per-file trong install_dotfile() không bao
# giờ nhìn thấy tên `dunstrc`. Đã kiểm chứng: thêm COLOR_GENERATED vào
# install_dotfile() rồi chạy `./install.sh dotfiles` vẫn ghi đè — vì
# install_dotfile() chỉ thấy đối số là thư mục.
#
# Khi thư mục đích ĐÃ tồn tại: đi TỪNG mục con thay vì `cp -a` cả thư mục.
# Nhờ vậy chỉ file thật sự khác mới bị backup — không tạo bản sao lưu cả thư
# mục mỗi lần chạy chỉ vì mấy dòng mã màu. File nào chỉ khác màu thì giữ
# nguyên bản đang chạy.
install_item() {
    local src=$1 dst=$2
    # Không phải thư mục, hoặc đích chưa có -> đường đơn giản
    if [[ ! -d $src || ! -d $dst ]]; then
        install_dotfile "$src" "$dst"
        return
    fi

    local e name kept=0 changed=0
    # "$src"/* + "$src"/.[!.]* : gồm cả file ẩn, bỏ . và ..
    for e in "$src"/* "$src"/.[!.]*; do
        [[ -e $e ]] || continue
        name=${e##*/}
        if [[ -f $e && -f $dst/$name ]] && is_color_generated "$name" \
           && color_only_diff "$e" "$dst/$name"; then
            info "$name: khác chỉ ở màu — giữ bản đang chạy"
            kept=$((kept + 1))
            continue
        fi
        if [[ -e $dst/$name ]] && ! same_content "$e" "$dst/$name"; then
            changed=$((changed + 1))
        fi
        install_dotfile "$e" "$dst/$name"
    done
    if (( ! kept && ! changed )); then
        ok "$(basename -- "$dst"): không có gì thay đổi"
    fi
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
        # Khác biệt CHỈ ở mã màu, và file đó nằm trong COLOR_GENERATED:
        # giữ bản đang chạy. Xem color_only_diff().
        if is_color_generated "$(basename -- "$dst")" \
           && color_only_diff "$src" "$dst"; then
            info "$(basename -- "$dst"): khác chỉ ở màu — giữ bản đang chạy"
            return 0
        fi
        # backup_path bảo đảm $bak CHƯA tồn tại. Không có nó thì `mv` đặt $dst
        # vào BÊN TRONG $bak nếu $bak đã là thư mục, thay vì thay thế nó.
        local bak
        bak=$(backup_path "$dst")
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
    local -a items=(dunst fastfetch firefox fish gtk-3.0 kitty picom starship.toml xsettingsd)
    local n=0 d
    for d in "${items[@]}"; do
        # starship.toml là file, còn lại là thư mục — install_dotfile nhận cả hai
        if [[ -e "$REPO_DIR/.config/$d" ]]; then
            install_item "$REPO_DIR/.config/$d" "$TSUKI_HOME/.config/$d"
            n=$((n + 1))
        else
            warn "thiếu .config/$d trong repo — bỏ qua"
        fi
    done
    ok "xong ($n/${#items[@]} mục)"
}

# Thư mục gốc có thể chứa profile Firefox. Thứ tự KHÔNG quan trọng vì
# firefox_candidates() đọc profiles.ini ở từng thư mục trước khi đoán, rồi
# mới hỏi người dùng khi có nhiều ứng viên.
#
# VÌ SAO LIỆT KÊ DÀI, VÌ SAO THỨ TỰ KHÔNG CÒN QUAN TRỌNG:
# Firefox đặt profile ở nhiều nơi tùy cách cài và tuỳ biến, và bản "sửa" trước
# đã hỏng vì cứ siết một đường dẫn cho một máy:
#   - gói Arch chính thức + psd (máy này): ~/.config/mozilla/firefox
#   - Firefox cài tay, không XDG:          ~/.mozilla/firefox
#   - Flatpak:  ~/.var/app/org.mozilla.firefox/{.mozilla,.config}/mozilla/firefox
#   - Snap:     ~/snap/firefox/common/{.mozilla,.config}/mozilla/firefox
#   - Bản dev/nightly: ~/.mozilla/firefox-dev, ~/.mozilla/firefox-nightly
#   - XDG tự đặt: $XDG_CONFIG_HOME/mozilla/firefox
#   - Cache đĩa (KHÔNG phải profile): $XDG_CACHE_HOME/mozilla/firefox
#
# Nguyên tắc: thứ tự ĐÚNG là thứ tự BỘ CHỨA profiles.ini. Thư mục không có
# profiles.ini thì chỉ được dùng ở mức dự phòng, và phải có prefs.js mới
# tính — nếu không sẽ dính thư mục cache trùng tên.
firefox_bases() {
    local cfg=${XDG_CONFIG_HOME:-$TSUKI_HOME/.config}
    local data=${XDG_DATA_HOME:-$TSUKI_HOME/.local/share}
    local cache=${XDG_CACHE_HOME:-$TSUKI_HOME/.cache}
    local flatpak=$TSUKI_HOME/.var/app/org.mozilla.firefox
    printf '%s\n' \
        "$cfg/mozilla/firefox" \
        "$TSUKI_HOME/.mozilla/firefox" \
        "$flatpak/.mozilla/firefox" \
        "$flatpak/.config/mozilla/firefox" \
        "$TSUKI_HOME/snap/firefox/common/.mozilla/firefox" \
        "$TSUKI_HOME/snap/firefox/common/.config/mozilla/firefox" \
        "$data/mozilla/firefox" \
        "$TSUKI_HOME/.mozilla/firefox-dev" \
        "$TSUKI_HOME/.mozilla/firefox-nightly" \
        "$TSUKI_HOME/.mozilla/firefox-beta" \
        "$cache/mozilla/firefox" \
        "$TSUKI_HOME/.cache/mozilla/firefox"
}

# Một đường dẫn có trông giống thư mục CACHE của Firefox không (tức KHÔNG
# phải profile). Cache đĩa của Firefox nằm cùng tên với profile:
#   ~/.cache/mozilla/firefox/<hash>.default-release/{cache2,safebrowsing,thumbnails,...}
# Ghi userChrome.css vào đó là vô nghĩa — Firefox không bao giờ đọc. Đây
# chính là chỗ bản "sửa" trước cài nhầm trên máy này.
firefox_looks_like_cache() {
    local d=$1
    [[ -d $d ]] || return 1
    # Có prefs.js thì chắc chắn là profile.
    [[ -f $d/prefs.js ]] && return 1
    # base của nó có profiles.ini thì base đó là nơi quản lý profile.
    [[ -f ${d%/*}/profiles.ini ]] && return 1
    # Dấu hiệu đặc trưng của cache2
    [[ -d $d/cache2 || -d $d/safebrowsing ]] && return 0
    return 1
}

# Đọc profiles.ini — nguồn CHUẨN XÁC cho biết profile nào đang được dùng.
#
# profiles.ini có hai loại mục:
#   [ProfileN]    Name=<tên>  IsRelative=1  Path=<thư mục>   Default=1?
#   [InstallXXXX] Name=<tên>  Default=1  Locked=1
# `Default=1` trong [Install*] là "kho cài đặt mặc định"; nó trỏ tới profile
# qua trường `Name` khớp với `Name` của một [ProfileN].
#
# Trả về đường dẫn tuyệt đối, hoặc rỗng nếu không đọc được gì hữu ích.
#
# Vì sao BẮT BUỘC đọc file này: bản trước chỉ đoán theo tên thư mục
# (`*.default-release`). Người dùng tự đổi tên profile — hoặc Firefox tự tạo
# tên khác (ví dụ `mycustom.profile`) — thì bản trước cài giao diện vào
# profile KHÔNG dùng, Firefox mở lên vẫn nguyên diện. Đã tái hiện được:
# profiles.ini trỏ `mycustom.profile`, có thêm bẫy `xyz.default-release`
# -> bản cũ chọn `xyz.default-release` (SAI).
firefox_profile_ini() {
    local base=$1 ini=$1/profiles.ini installs=$1/installs.ini
    [[ -f $ini ]] || return 1

    local rel want

    # BUOC 1 — TIN HIEU MANH NHAT: [Install<hash>] Default=<TEN PROFILE>.
    #
    # Day moi la thu Firefox that su dung. `Default` o day la TEN, KHONG phai
    # so 1. profiles.ini that tren may nay:
    #   [Install4F96D1932A9F858E]
    #   Default=jnetde4e.default-release      <- profile DANG DUNG
    #   Locked=1
    #   [Profile1]
    #   Name=default  Path=tihwr7jp.default  Default=1   <- profile RONG, 0 byte
    # Neu di theo `Default=1` se cai giao dien vao profile rong, Firefox van
    # mo profile khac va nguoi dung lai thay "khong doi gi".
    want="$(awk -F= '
        /^\[Install/ { isinst = 1; next }
        /^\[/        { isinst = 0; next }
        isinst && $1 == "Default" && $2 != "1" && $2 != "" { print $2; exit }
    ' "$ini" 2>/dev/null || true)"

    # installs.ini ghi lai cung thong tin, va la noi Chrome/Firefox ghi khi
    # nguoi dung chon "dat lam mac dinh" trong Profile Manager.
    if [[ -z ${want:-} && -f $installs ]]; then
        want="$(awk -F= '$1 == "Default" && $2 != "1" && $2 != "" { print $2; exit }' \
            "$installs" 2>/dev/null || true)"
    fi

    if [[ -n ${want:-} ]]; then
        # So khop ca `Name` LAN `Path`. profiles.ini that tren may nay:
        #   [Install4F96D1932A9F858E]  Default=jnetde4e.default-release
        #   [Profile0]  Name=default-release  Path=jnetde4e.default-release
        # Gia tri `Default` khop voi PATH, khong phai `Name`. Chi so `Name` se
        # khong khop -> `rel` rong -> rơi xuống buoc 3 ("[Profile*] dau tien")
        # va CHON DUNG NHIU CHUNG — tai day may that co [Profile0] la profile
        # dung nen may rat may tinh, nhung thu tu hai muc se bien chon sai.
        # Da bat bang cach them dieu kien so `Path`.
        rel="$(awk -F= -v want="$want" '
            /^\[Profile/ { isprof = 1; name = ""; next }
            /^\[/        { isprof = 0; next }
            isprof && $1 == "Name" { name = $2; next }
            isprof && $1 == "Path" && (name == want || $2 == want) { print $2; exit }
        ' "$ini" 2>/dev/null || true)"
    fi

    # BUOC 2 — khong co tin hieu Install: [Profile*] co Default=1.
    if [[ -z ${rel:-} ]]; then
        rel="$(awk -F= '
            /^\[Profile/ { isprof = 1; isdef = 0; next }
            /^\[/        { isprof = 0; isdef = 0; next }
            isprof && isdef == 0 && $1 == "Default" && $2 == "1" { isdef = 1; next }
            isprof && isdef == 1 && $1 == "Path" { print $2; exit }
        ' "$ini" 2>/dev/null || true)"
    fi

    # BUOC 3 — profiles.ini khong danh dau Default gi ca: [Profile*] dau tien.
    if [[ -z ${rel:-} ]]; then
        rel="$(awk -F= '
            /^\[Profile/ { isprof = 1; next }
            /^\[/        { isprof = 0; next }
            isprof && $1 == "Path" { print $2; exit }
        ' "$ini" 2>/dev/null || true)"
    fi

    [[ -n ${rel:-} ]] || return 1

    # IsRelative=0 nghia la Path la duong dan tuyet doi. Thu `[[ $rel == /* ]]`
    # truoc khi noi vao $base — `//abs/path` va `/base//abs/path` deu tro sai.
    if [[ $rel == /* ]]; then
        [[ -d $rel ]] && { printf '%s\n' "$rel"; return 0; }
        return 1
    fi
    if [[ -d $base/$rel ]]; then
        # GIU NGUYEN duong dan qua symlink, KHONG dung `realpath`/`readlink -f`.
        # Tren may nay profile la symlink -> overlay FUSE cua profile-sync-daemon
        # (/run/user/1000/psd/...). Ghi qua duong dan goc thi `mv`/backup hoat
        # dong binh thuong; `realpath` se dua ra /run/... (tmpfs) va mau khi
        # may restart. `[[ -d ]]` dinh nghia follow symlink nen van kiem tra
        # duoc dung thu muc that.
        printf '%s\n' "${base%/}/$rel"
        return 0
    fi
    return 1
}

# Tìm thư mục profile thật của Firefox.
#
# LỊCH SỬ LỖI (cả ba đều là kiểu "chạy xong mà không làm gì"):
#
#  1) Bản đầu tìm ở "$TSUKI_HOME/.config/mozilla/firefox". Sai hoàn toàn:
#     profile Firefox KHÔNG nằm trong ~/.config. `find` ra rỗng ->
#     `[[ -n $profile ]]` sai -> `return 0` (exit 0, coi là thành công) ->
#     user.js và userChrome.css chưa từng được copy, Firefox giữ nguyên
#     giao diện cũ mà install.sh vẫn in "xong".
#
#  2) Sửa thành ~/.mozilla. Máy này lại dùng ~/.cache/mozilla/firefox/
#     (không có biến MOZ_* nào, /usr/bin/firefox chỉ là
#     `exec /usr/lib/firefox/firefox "$@"` — Firefox 157 tự chọn ~/.cache).
#
#  3) Sửa thành "dò cả hai, ưu tiên .mozilla". Sai ở chỗ khác: thứ tự ưu
#     tiên cứng, `find | head -1` không sort (chọn theo thứ tự thư mục, không
#     ổn định), và hoàn toàn không biết profile nào ĐANG DÙNG.
#
#  4) SAI LẦM LỚN NHẤT — và đây là lý do giao diện vẫn không đổi sau khi
#     "đã sửa xong". Bản đầu tiên tìm ở `~/.config/mozilla/firefox` là ĐÚNG
#     với máy này, nhưng tôi (người viết dòng comment này) đã LOẠI nó đi sau
#     khi kết luận sai rằng profile nằm ở `~/.cache`.
#     Lý do kết luận sai: lệnh dò profile tôi dùng có `-type d`, mà profile
#     thật ở đây là SYMLINK (`~/.config/mozilla/firefox/jnetde4e.default-release
#     -> /run/user/1000/psd/...`) nên bị lọc mất. `~/.cache/mozilla/firefox/`
#     có thư mục TRÙNG TÊN — do chính những lần chạy thử headless của tôi tạo
#     ra — nên rất dễ tưởng đó là profile thật.
#     `~/.config/mozilla/firefox/` đã có `profiles.ini` + `installs.ini` từ
#     trước; `~/.cache/mozilla/firefox/` không có gì cả.
#     Đã thêm lại `~/.config/mozilla/firefox` vào firefox_bases, và đặt
#     `profiles.ini` lên trên mọi phép đoán.
#
#  5) `Default=1` trong [Profile*] KHÔNG phải tín hiệu đáng tin. profiles.ini
#     thật của máy này đặt `Default=1` cho `tihwr7jp.default` — thư mục RỖNG
#     (prefs.js 0 byte) — còn profile thật `jnetde4e.default-release`
#     (prefs.js 30 KB) chỉ được trỏ bởi `[Install*] Default=<tên>`.
#     Theo `Default=1` là cài vào chỗ Firefox không bao giờ mở.
#
# Cách sửa lần này: ưu tiên tuyệt đối profiles.ini; chỉ khi không có (hoặc
# không đọc được) mới đoán theo mtime, và đoán có thứ tự xác định.
#
# Thư mục sửa đổi gần nhất trong danh sách tham số.
# `sed -n 1p` chứ không `head -1`: head đóng pipe sau dòng đầu thì ls nhận
# SIGPIPE (141), dưới `set -o pipefail` thành lỗi. sed đọc hết nên không có.
# Đúng lỗi đó đã xảy ra ở paru_ver (dòng 1301) — giữ nhất quán.
#
# LƯU Ý: hàm tự thêm `--` để chặn đường dẫn bắt đầu bằng `-`. Vì vậy CALLER
# TUYỆT ĐỐI KHÔNG được truyền `--` nữa — nếu không sẽ thành
# `ls -dt -- -- /path/...`: dấu `--` thứ hai bị ls hiểu là TÊN FILE, ls trả 2
# ("cannot access '--'") dù đã in ra kết quả đúng. Đã mắc đúng lỗi này:
# `set -x` cho thấy `(( 3 ))` (3 tham số thay vì 2) và
# `ls -dt -- -- /tmp/.../zzz.default-release/` -> newest_dir trả 2 ->
# `newest_dir ... && return 0` trong firefox_profile KHÔNG bao giờ chạy ->
# hàm in ra đường dẫn đúng nhưng trả về 1.
newest_dir() {
    (( $# )) || return 1
    ls -dt -- "$@" 2>/dev/null | sed -n '1p'
}

firefox_candidates() {
    local base p seen=""
    local -a ini_hits=() guess_hits=() weak_hits=()

    # Gom ỨNG VIÊN TỪ MỌI thư mục gốc — KHÔNG return ngay trong vòng lặp.
    # Bản trước return ở thư mục đầu tiên tìm được, nên khi máy vừa dùng
    # ~/.config mà ~/.mozilla còn sót profile cũ thì chọn nhầm profile cũ.
    # Đã tái hiện: OLD (2021) vs NEW (2026) -> bản cũ trả về OLD.
    #
    # `while read` chứ không `for base in $(firefox_bases)`: word splitting
    # làm vỡ đường dẫn có khoảng trắng (ví dụ TSUKI_HOME="/home/a b").
    while IFS= read -r base; do
        [[ -n $base && -d $base ]] || continue
        # profiles.ini là nguồn chuẩn xác — ưu tiên tuyệt đối.
        p="$(firefox_profile_ini "$base" || true)"
        if [[ -n $p ]]; then
            ini_hits+=("$p")
            continue
        fi
        # Không có profiles.ini (Firefox chưa từng ghi, hoặc profile tạo tay
        # bằng --profile): đoán trong thư mục này.
        #
        # Glob KHÔNG khớp thì "$base"/*.*/ giữ nguyên chuỗi; `[[ -d ]]` loại.
        # CHIA HAI MỨC: ưu tiên ứng viên có `prefs.js` (dấu hiệu chắc chắn là
        # profile), phần còn lại để dự phòng cho profile vừa tạo chưa thoát
        # sạch lần nào — Firefox chỉ ghi prefs.js khi shutdown.
        #
        # Loại thư mục cache trùng tên ở mọi mức: `~/.cache/mozilla/firefox/
        # <hash>.default-release` chứa cache2/, thumbnails/, safebrowsing/ —
        # là cache đĩa của Firefox, KHÔNG phải profile, lại MỚI HƠN profile
        # thật nên đứng đầu khi sort mtime. Ghi userChrome.css vào đó là vô
        # nghĩa — và đó chính là cách bản "sửa" trước cài nhầm trên máy này.
        for p in "$base"/*.*/; do
            [[ -d $p ]] || continue
            firefox_looks_like_cache "$p" && continue
            if [[ -f $p/prefs.js ]]; then
                guess_hits+=("${p%/}")
            else
                weak_hits+=("${p%/}")
            fi
        done
    done < <(firefox_bases)

    # Thứ tự ưu tiên: profiles.ini > có prefs.js > dự phòng. Chỉ xuất ứng viên
    # của mức CAO NHẤT đang có — trả về cả ba lớp sẽ khiến người dùng bị hỏi
    # về một profile rỗng trong khi đã có profile thật.
    local -a out=()
    local -a pick=()
    if   (( ${#ini_hits[@]} ));   then pick=("${ini_hits[@]}")
    elif (( ${#guess_hits[@]} )); then pick=("${guess_hits[@]}")
    elif (( ${#weak_hits[@]} )); then pick=("${weak_hits[@]}")
    else return 1
    fi

    # Bỏ trùng (cùng một profile có thể lọt vào nhiều base, ví dụ ~/.mozilla
    # và $XDG_CONFIG_HOME trỏ cùng chỗ).
    for p in "${pick[@]}"; do
        [[ -n $p ]] || continue
        case $seen in *"|$p|"*) continue ;; esac
        seen+="|$p|"
        out+=("$p")
    done
    (( ${#out[@]} )) || return 1
    # Truyền tham số TRỰC TIẾP, KHÔNG qua pipe. `printf ... | func` khiến
    # "$@" của func rỗng -> `ls -dt --` không có đối số nào liệt kê thư mục
    # hiện tại -> trả về "." -> cmd_firefox ghi userChrome.css vào $PWD.
    # Đã mắc đúng lỗi này: in ra "profile: ." và tạo ./user.js + ./chrome/
    # trong cây repo. Đã xoá; giữ comment để không lặp lại.
    newest_dir_keep_all "${out[@]}"
    return 0
}

# In tất cả đường dẫn, mới nhất trước. `newest_dir` chỉ in dòng đầu nên không
# dùng được ở đây; `ls -dt` + `sed -n '1,$p'` đọc hết, không dính SIGPIPE.
newest_dir_keep_all() {
    ls -dt -- "$@" 2>/dev/null | sed -n '1,$p'
}

# Chọn 1 trong N ứng viên. Không có terminal thì lấy ứng viên ĐẦU (đã sort
# mới nhất trước) và nói rõ — im lặng chọn bừa là nguyên nhân gốc của mọi
# lần "cài nhầm" trước đây.
choose_profile() {
    local -a c=()
    mapfile -t c < <(firefox_candidates) || true
    (( ${#c[@]} )) || return 1
    if (( ${#c[@]} == 1 )); then
        printf '%s\n' "${c[0]}"
        return 0
    fi

    if [[ ! -t 0 ]]; then
        warn "có ${#c[@]} profile Firefox, không có terminal để hỏi."
        warn "  Dùng: ${c[0]}"
        warn "  (đặt FIREFOX_PROFILE=<đường dẫn> hoặc ./install.sh firefox <đường dẫn> để chỉ định)"
        printf '%s\n' "${c[0]}"
        return 0
    fi

    local i n=${#c[@]}
    warn "tìm thấy $n profile Firefox. Giao diện sẽ cài vào profile bạn chọn:"
    for ((i = 0; i < n; i++)); do
        printf '    %d) %s%s\n' "$((i + 1))" "${c[i]}" \
            "$( [[ ${c[i]} == /* ]] || true)$( mark_active "${c[i]}" )"
    done
    local reply
    while :; do
        printf '  chọn [1-%d] (mặc định 1): ' "$n"
        read -r reply || reply=''
        [[ -z $reply ]] && reply=1
        [[ $reply =~ ^[0-9]+$ ]] && (( reply >= 1 && reply <= n )) && break
        printf '  nhập số từ 1 đến %d\n' "$n"
    done
    printf '%s\n' "${c[reply - 1]}"
}

# Gắn nhãn cho ứng viên để người dùng dễ chọn: ưu tiên hiển thị mức tin cậy.
mark_active() {
    local d=$1
    if [[ -f ${d%/*}/profiles.ini ]]; then
        printf '   <- profiles.ini chỉ định'
    elif [[ -f $d/prefs.js ]]; then
        printf '   <- có prefs.js'
    else
        printf '   <- dự phòng (chưa có prefs.js)'
    fi
}

# Đường dẫn profile do người dùng chỉ định: tham số dòng lệnh, rồi biến môi
# trường. Chỉ dùng khi có; không phải đoán.
firefox_profile_override() {
    local p=${1:-}
    [[ -n $p ]] || p=${FIREFOX_PROFILE:-}
    [[ -n $p ]] || return 1
    # Cho phép truyền thư mục gốc (có profiles.ini) lẫn thẳng thư mục profile.
    if [[ -f $p/profiles.ini ]]; then
        local r
        r="$(firefox_profile_ini "$p" || true)"
        [[ -n $r ]] && { printf '%s\n' "$r"; return 0; }
        die "$p có profiles.ini nhưng không đọc được profile nào"
    fi
    [[ -d $p ]] || die "đường dẫn profile không tồn tại: $p"
    printf '%s\n' "$p"
}

firefox_profile() {
    choose_profile
}

cmd_firefox() {
    step "cài giao diện Firefox"
    local profile src_user src_css dst_user dst_css
    src_user="$REPO_DIR/.config/firefox/user.js"
    src_css="$REPO_DIR/.config/firefox/chrome/userChrome.css"

    # Kiểm tra nguồn TRƯỚC. install_dotfile() im lặng `return 0` khi
    # [[ -e $src ]] sai, nên nếu repo thiếu file thì hàm vẫn in
    # "OK profile: ..." và thoát 0 — đúng loại "báo thành công rỗng" mà
    # bản trước mắc. Đã tái hiện: repo thiếu userChrome.css -> in OK,
    # exit 0, nhưng profile không có file đó. Ở đây phải nói thẳng.
    local -a missing=()
    [[ -f $src_user ]] || missing+=("${src_user#$REPO_DIR/}")
    [[ -f $src_css  ]] || missing+=("${src_css#$REPO_DIR/}")
    if (( ${#missing[@]} )); then
        die "thiếu file trong repo: ${missing[*]}"
    fi

    # Ưu tiên đường dẫn NGƯỜI DÙNG chỉ định (arg hoặc $FIREFOX_PROFILE);
    # chỉ khi không có mới tự dò. Nhờ vậy máy nào cũng ép được nếu heuristic
    # trượt — đây là lưới an toàn cho mọi trường hợp lạ mà script chưa biết.
    profile="$(firefox_profile_override "${1:-}" || true)"
    if [[ -z $profile ]]; then
        profile="$(firefox_profile || true)"
    fi
    if [[ -z $profile ]]; then
        warn "không tìm thấy thư mục profile Firefox."
        local b
        while IFS= read -r b; do
            [[ -d $b ]] && warn "  đã dò: $(tilde "$b")"
        done < <(firefox_bases)
        warn "  Hãy MỞ FIREFOX MỘT LẦN (để nó tạo profile) rồi chạy lại ./install.sh firefox"
        warn "  hoặc chỉ định tay:  ./install.sh firefox ~/.mozilla/firefox/xyz.default-release"
        return 0
    fi

    # Chặn ghi vào thư mục CACHE. Ở đây KHÔNG chỉ cảnh báo rồi vẫn ghi: bản
    # "sửa" trước đã cài vào ~/.cache/mozilla/firefox/... và in "OK", người
    # dùng tin là xong nhưng Firefox không bao giờ đọc tới. Thà báo lỗi.
    if firefox_looks_like_cache "$profile"; then
        die "$profile trông như CACHE đĩa của Firefox (có cache2/ hoặc safebrowsing/, không phải profile).
       Ghi userChrome.css vào đó không có tác dụng. Chỉ định đúng profile:
         ./install.sh firefox <đường dẫn profile có prefs.js>"
    fi

    dst_user="$profile/user.js"
    dst_css="$profile/chrome/userChrome.css"
    mkdir -p "$profile/chrome"
    install_dotfile "$src_user" "$dst_user"
    install_dotfile "$src_css"  "$dst_css"

    # Xác minh bằng SO SÁNH NỘI DUNG, không chỉ "file tồn tại": install_dotfile
    # có thể bỏ qua vì is_generated, hoặc return sớm. So byte cho chắc.
    local -a bad=()
    cmp -s -- "$src_user" "$dst_user" || bad+=("user.js")
    cmp -s -- "$src_css"  "$dst_css"  || bad+=("chrome/userChrome.css")
    if (( ${#bad[@]} )); then
        die "đã copy nhưng nội dung KHÔNG khớp repo: ${bad[*]}"
    fi
    ok "profile: ${profile##*/} (user.js + userChrome.css đã khớp repo)"

    # userChrome.css CHỈ có tác dụng sau khi Firefox đọc lại pref. Pref
    # toolkit.legacyUserProfileCustomizations.stylesheets nằm trong user.js
    # vừa copy, nhưng Firefox nạp pref khi khởi động — nên file cũ có sẵn
    # thì phải đóng hẳn Firefox rồi mở lại mới thấy đổi. Nhắc luôn vì
    # "cài xong không thấy gì đổi" là triệu chứng dễ gặp nhất ở bước này.
    #
    # Tridactyl: KHÔNG cần bật tay. Gói `firefox-tridactyl` (kho `extra`) đặt
    # .xpi vào /usr/lib/firefox/browser/extensions/ — Firefox 157 tự quét
    # thư mục đó và tự bật. Đã kiểm chứng: chạy Firefox với profile tạm,
    # extensions.json ghi `tridactyl.vim@cmcaine.co.uk ... active=true,
    # location=app-global`. Nên KHÔNG bảo người dùng vào about:debugging
    # bật tay — bản trước bảo vậy là SAI.
    local ext_state=""
    if pacman -Qq firefox-tridactyl >/dev/null 2>&1; then
        ext_state="đã cài, Firefox tự bật (gõ \`:\` trong trang để kích hoạt)"
    else
        ext_state="CHƯA cài — chạy ./install.sh deps"
    fi
    cat <<EOF

  Giao diện đã nạp vào: ${profile##*/}
  Đóng hẳn Firefox rồi mở lại để userChrome.css có hiệu lực.

  Tridactyl: $ext_state.

EOF
}

# ---------------------------------------------------------------- session ---
# .xinitrc — điểm vào khi chạy `startx` từ TTY.
# startx KHÔNG nạp profile login shell, nên PATH phải tự dựng.
write_xinitrc() {
    step "ghi ~/.xinitrc"
    # Backup nếu đã có .xinitrc: `cat >` xoá trắng file cũ mà không để lại dấu
    # vết, và người dùng rất dễ đã có .xinitrc riêng từ trước.
    if [[ -f $TSUKI_HOME/.xinitrc ]] && ! grep -q 'Tsuki install.sh' "$TSUKI_HOME/.xinitrc"; then
        local bak
        bak=$(backup_path "$TSUKI_HOME/.xinitrc")
        cp -a -- "$TSUKI_HOME/.xinitrc" "$bak"
        warn ".xinitrc đã tồn tại -> backup: ${bak##*/}"
    fi
    cat >"$TSUKI_HOME/.xinitrc" <<EOF
# ~/.xinitrc — do Tsuki install.sh tạo. Chạy session dwm từ TTY: startx
#
# startx không nạp ~/.profile nên PATH phỏng vọng; make install đặt binary vào
# $PREFIX/bin nên phải thêm vào PATH ở đây, nếu không run.sh sẽ không tìm thấy dwm
# và vòng lặp thoát ngay.
export PATH="$PREFIX/bin:\$PATH"
exec "$REPO_DIR/scripts/run.sh"
EOF
    chmod 644 "$TSUKI_HOME/.xinitrc"
    # "~/.xinitrc" là chuỗi hiển thị cho người đọc, KHÔNG phải đường dẫn cần
    # mở — nên cố ý không dùng $HOME. shellcheck báo SC2088 ở đây là dương
    # tính giả.
    # shellcheck disable=SC2088
    ok "~/.xinitrc -> $REPO_DIR/scripts/run.sh"
}

# ~/.Xresources — tài nguyên X mà run.sh:101 `xrdb -merge` nạp trước khi exec
# dwm. Ở đây khai Xcursor/Xcursor.size (theme cursor).
#
# KHÔNG dùng install_dotfile/cp -f như .xinitrc: .Xresources là file mà người
# dùng rất dễ đã có sẵn của riêng họ (XTerm*, font, màu...). Ghi đè là mất
# luôn cấu hình đó. Nên:
#   - chưa có          -> copy nguyên bản của repo
#   - đã có, có Xcursor -> giữ nguyên (đã cấu hình rồi, không đụng)
#   - đã có, chưa có   -> backup rồi nối thêm khối Tsuki, giữ hết nội dung cũ
install_xresources() {
    step "cài ~/.Xresources"
    local f="$TSUKI_HOME/.Xresources"

    if [[ -f $f ]] && grep -q '^[[:space:]]*Xcursor:' "$f"; then
        ok "đã có Xcursor trong .Xresources — giữ nguyên"
        return 0
    fi
    if [[ -f $f ]]; then
        local bak
        bak=$(backup_path "$f")
        cp -a -- "$f" "$bak"
        warn ".Xresources đã tồn tại -> backup: ${bak##*/}"
        printf '\n%s\n' "$(cat "$REPO_DIR/.Xresources")" >>"$f"
    else
        install_dotfile "$REPO_DIR/.Xresources" "$f"
    fi
    ok "~/.Xresources (Xcursor + Xcursor.size)"
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

# --- theme GTK + icon: Miami26 + Kora ---------------------------------------
# Hai theme này KHÔNG có trong kho Arch/CachyOS/arisa, cũng không có trong AUR
# (đã tra rpc.v5/search của AUR: "miami26" và "kora-grey" đều 0 kết quả).
# Chúng chỉ có trên GitHub, nên phải clone rồi copy.
#
# Cài ở mức USER (~/.themes, ~/.local/share/icons) chứ không phải /usr/share:
# không cần root, và không đụng theme của các user khác trên cùng máy.
# GTK3 tra theme theo đúng tên thư mục sau khi cài, KHÔNG phải Name= trong
# index.theme — nên thư mục phải tên đúng "Miami26" / "kora-pgrey".
cmd_themes() {
    need git curl
    step "cài theme Miami26 + icon Kora (từ git)"
    local src="$TSUKI_HOME/.cache/tsuki-themes"
    mkdir -p "$src" "$TSUKI_HOME/.themes" "$TSUKI_HOME/.local/share/icons"

    fetch_repo() {
        local url=$1 dir=$2
        if [[ -d $src/$dir/.git ]]; then
            info "$dir đã có — bỏ qua clone"
            return 0
        fi
        rm -rf -- "$src/$dir"
        git clone -q --depth 1 "$url" "$src/$dir" \
            || { warn "clone thất bại: $url"; return 1; }
    }

    # Miami26: repo chứa nhiều biến thể trong Themes/, ta lấy đúng bản gốc.
    if fetch_repo https://github.com/dhampirave/Miami26 Miami26; then
        rm -rf -- "$TSUKI_HOME/.themes/Miami26"
        cp -r -- "$src/Miami26/Themes/Miami26" "$TSUKI_HOME/.themes/Miami26" \
            && ok "Miami26 -> ~/.themes/Miami26"
    fi

    # Kora: thư mục kora-pgrey/ và kora/ nằm Ở GỐC repo (không phải dưới kora/).
    if fetch_repo https://github.com/bikass/kora kora; then
        local t
        for t in kora-pgrey kora; do
            rm -rf -- "$TSUKI_HOME/.local/share/icons/$t"
            # icon-theme.cache trong repo là cache sinh trên MÁY TÁC GIẢ, chứa
            # đường dẫn tuyệt đối của họ -> dùng lại sẽ sai. Xoá rồi dựng lại.
            rm -f -- "$src/kora/$t/icon-theme.cache"
            if cp -r -- "$src/kora/$t" "$TSUKI_HOME/.local/share/icons/$t"; then
                command -v gtk-update-icon-cache >/dev/null 2>&1 &&
                    gtk-update-icon-cache -f -t \
                        "$TSUKI_HOME/.local/share/icons/$t" >/dev/null 2>&1 || true
                ok "Kora/$t -> ~/.local/share/icons/$t"
            fi
        done
    fi
}

cmd_session() {
    write_xinitrc
    install_xresources
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

# ĐƯỜNG DẪN trên server KHÁC TÊN MỤC trong pacman.conf. Theo tài liệu chính thức
# (https://xlibre-arch.github.io/):
#
#     [xlibre-stable]
#     Server = https://packages.xlibre.net/arch/stable/$arch
#                tên mục xlibre-stable ^^^^   path là stable, KHÁC
#
# BUG ĐÃ DÍNH Ở ĐÂY: xlibre_add_repo nhận tên mục rồi dùng luôn nó làm path,
# sinh /arch/xlibre-stable/$arch -> HTTP 404:
#     error: failed retrieving file 'xlibre-stable.db' ... The requested URL
#     returned error: 404
#
# Suy ra path bằng cách bỏ tiền tố, KHÔNG truyền thêm tham số: cả hai chỗ gọi
# đều chỉ có `xlibre_repo_name`, mà hàm đó trả về tên mục. Thêm tham số thứ
# hai nghĩa là phải sửa cả hai chỗ gọi và hai chỗ có thể lệch nhau.
xlibre_url_path() {
    local repo=$1 p
    p=${repo#xlibre-}
    # Bỏ tiền tố xong ra rỗng, hoặc không thấy tiền tố nào, nghĩa là tên mục
    # sai hình dạng. Chặn ở đây — còn hơn ghi file hỏng rồi mới biết lúc
    # pacman -Syy, lúc ấy pacman.conf đã hỏng rồi.
    [[ -n $p && $p != "$repo" ]] ||
        die "tên repo lạ: '$repo' (phải có dạng xlibre-<kênh>, vd xlibre-stable)"
    printf '%s' "$p"
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

# Được bật kênh $1 mà không cần tự xoá mục nào của người dùng không?
#   0 = được
#   1 = không — và hàm đã in lý do.
#
# Vì sao cần: XLibre mặc định là stable, nhưng người dùng có thể cố ý bật
# beta để dùng thử (thường thêm thẳng vào /etc/pacman.conf). Xoá mục đó để
# ép stable là hủy một lựa chọn có chủ đích mà không ai hỏi. Ở đường cài TỰ
# ĐỘNG thì bỏ qua và nói rõ; lệnh `xlibre` tường minh thì vẫn `die` trong
# xlibre_add_repo — gọi tường minh thì phải biết là không làm được.
xlibre_repo_writable() {
    local want=$1

    # mapfile chứ không `| head -n1`: xlibre_active_channels chạy grep, head đóng
    # sớm pipe thì grep nhận SIGPIPE (141) và pipefail hoá lỗi — đúng cái bẫy
    # đã dính hai lần trong script này.
    local -a lines=()
    mapfile -t lines < <(xlibre_active_channels | grep -v '^$')

    ((${#lines[@]} == 0)) && return 0

    if ((${#lines[@]} > 1)); then
        warn "đang bật ${#lines[@]} kênh XLibre cùng lúc — tôi không tự xoá mục nào:"
        printf '    %s\n' "${lines[@]}"
        warn "gộp còn một kênh rồi chạy lại."
        return 1
    fi

    local sec=${lines[0]%%$'\t'*} src=${lines[0]##*$'\t'}
    # Đúng kênh cần, dù khai báo ở đâu: xlibre_add_repo sẽ báo "đã bật sẵn".
    [[ $sec == "[$want]" ]] && return 0
    # Kênh khác nhưng nằm trong file TA tạo: ghi đè được, an toàn.
    [[ $src == "$XLIBRE_OWN_CONF" ]] && return 0

    warn "$sec đang bật trong $src — đó là lựa chọn của bạn, tôi không tự xoá."
    warn "Muốn về [$want]: bỏ mục $sec khỏi $src rồi chạy lại."
    return 1
}

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
    # KHÔNG ghi trước khi biết URL còn sống. Một Include hỏng làm HỎNG MỌI lệnh
    # pacman — kể cả `pacman -Syu` để gỡ nó ra. Bốn bước sau nó sẽ hỏng
    # không phụ thuộc bước nào trước, nên phải kiểm trước khi đụng pacman.conf.
    local path url code
    path="$(xlibre_url_path "$repo")"
    url="https://packages.xlibre.net/arch/$path/$(uname -m)"

    step "kiểm tra $repo trên server"
    # -fsS: -f làm curl trả 22 khi HTTP >= 400, -S giữ body lỗi để đọc được.
    #
    # KHÔNG viết `|| code=000`: curl đã in ra http_code rồi mới trả 22, nên `||`
    # sẽ xoá mất mã thật và thay bằng 000. Mất đúng thông tin cần nhất — 404
    # (sai tên kênh) và 000 (không nối được) là hai lỗi hoàn toàn khác, phải
    # đưa ra thông điệp khác nhau. Chỉ khi curl không in gì mới coi là 000.
    code="$(curl -fsS -o /dev/null -w '%{http_code}' --max-time 20 "$url/$repo.db" 2>/dev/null)" || :
    [[ -n $code ]] || code=000
    if [[ $code != 200 ]]; then
        die "server XLibre không phục vụ $repo.db (HTTP ${code:-no-route})
     URL: $url/$repo.db
     Có thể kênh '$path' đã đổi tên, hoặc server tạm lỗi.
     Trang chính thức: https://xlibre-arch.github.io/
     pacman.conf CHƯA bị đụng — thử lại sau, hoặc giữ X.Org (Tsuki vẫn chạy)."
    fi
    ok "server phục vụ $repo.db"

    # Dùng $2 cho path chứ không dùng $1: `$1` là tên mục pacman, đưa thẳng
    # vào URL là ra /arch/xlibre-stable/ — chính là 404 ở trên. Biến `repo`
    # là local của hàm ngoài, không có trong môi trường của bash con, nên
    # tham chiếu `repo` bên trong khối này sẽ ra rỗng; phải truyền qua
    # positional parameter.
    root_sh -c '
        set -e
        f=/etc/pacman.d/xlibre.conf
        install -d -m 755 /etc/pacman.d
        cat > "$f" <<EOF
# XLibre — https://xlibre-arch.github.io/
# Do Tsuki install.sh tạo. Muốn đổi kênh: ./install.sh xlibre <stable|beta|oldstable>
#
# SigLevel: kho KHÔNG đăng .db.sig và .files.sig (đã kiểm: HTTP 404), chỉ ký
# từng gói. DatabaseOptional là cấu hình duy nhất vừa xác minh package vẫn
# được kiểm chữ ký, vừa không đòi file mà server không có. Pin tại đây thay
# vì kế thừa global, vì global của một số distro là DatabaseRequired.
[$1]
SigLevel = Required DatabaseOptional
Server = https://packages.xlibre.net/arch/$2/\$arch
EOF
        chmod 644 "$f"
        grep -qF "Include = /etc/pacman.d/xlibre.conf" /etc/pacman.conf || \
            printf "\nInclude = /etc/pacman.d/xlibre.conf\n" >> /etc/pacman.conf
        echo "  + $f"
    ' _ "$repo" "$path"
    ok "đã bật [$repo]"
}

# Cài XLibre stable thay X.Org — chạy TỰ ĐỘNG trong `deps`, trước PKG_SESSION.
#
# Mặc định LUÔN là stable, không dò kênh đang bật rồi đi theo. Nếu âm thầm
# dùng beta chỉ vì còn sót mục [xlibre-beta] từ lần cài trước thì "mặc định"
# sẽ không còn là stable — và không ai hỏi. Muốn beta thì gọi tường minh:
#     ./install.sh xlibre beta
#
# Vì sao phải trước PKG_SESSION: xlibre-xserver khai báo `Provides:
# xorg-server`. Đặt cmd_xlibre_auto trước install_pkgs PKG_SESSION thì
# `missing_pkgs` thấy xorg-server đã được đáp ứng và không kéo X.Org xuống.
# Đảo thứ tự thì X.Org cài trước, xlibre-meta gỡ nó sau — tốn hai vòng cài/gỡ.
cmd_xlibre_auto() {
    detect_sudo

    if pacman -Qq xlibre-meta >/dev/null 2>&1; then
        ok "XLibre: đã có (xlibre-meta) — xorg-server do XLibre đáp ứng"
        return 0
    fi

    # Xem có gì đang bật không, và có xoá được không. Không xoá được thì bỏ
    # qua phần XLibre — cài nốt X.Org vẫn cho Tsuki chạy bình thường.
    local repo
    repo="$(xlibre_repo_name stable)"
    xlibre_repo_writable "$repo" || {
        warn "bỏ qua phần XLibre — Tsuki vẫn chạy, chỉ dùng X.Org thay XLibre."
        return 0
    }

    if ! confirm "Cài XLibre stable ($repo) thay cho xorg-server?" n \
                 "Câu trả lời: y = XLibre, n = giữ X.Org"; then
        warn "giữ X.Org — Tsuki vẫn chạy bình thường, chỉ khác nhà cung cấp X server"
        return 0
    fi

    printf '%sXLibre — kênh stable%s\n' "$C_B" "$C_RST"
    xlibre_add_key
    xlibre_add_repo "$repo"

    # -Syy chứ không phải -Syyu: đây là ngay sau khi hỏi, người dùng chưa kịp
    # đọc danh sách nâng cấp. -Syyu nâng cấp TOÀN BỘ hệ thống mà Arch không
    # hỗ trợ partial upgrade — đồng ý hàng loạt có thể để lại hệ thống lệch
    # phiên bản rồi hỏng. Nếu bạn đã có sẵn nhiều thứ trên máy, hãy tự
    # `sudo pacman -Syu` trước rồi chạy lại `deps`.
    step "đồng bộ index"
    as_root pacman -Syy --noconfirm

    step "cài xlibre-meta (thay xorg-server)"
    # --noconfirm ở đây là cố ý: người dùng đã trả lời y ở confirm() phía
    # trên. xlibre-xserver Conflicts với xorg-server nên pacman tự gói cả
    # việc gỡ X.Org vào cùng một transaction — không phải partial upgrade.
    as_root pacman -S --needed --noconfirm xlibre-meta
    ok "XLibre: xong. Đăng xuất rồi đăng nhập lại để X server mới có hiệu lực"
    info "muốn thử bản beta thì chạy: ./install.sh xlibre beta"
}

# ĐỔI KÊNH — không phải "cài XLibre" nữa, phần đó giờ tự chạy trong `deps`.
# Vẫn giữ `-Syyu` ở đây vì đổi kênh giữa chừng thì bắt buộc: hai series khác
# nhau (25.1 vs 25.2) lệch ABI, hạ cấp một nhóm thư viện rồi thay X server là
# cách chắc chắn làm vỡ session hiện tại.
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
    # để không rác file .gpg vào thư mục repo khi chạy install.sh từ đó — bước còn
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
        # Cùng lý do như backup_path ở ngoài: date chỉ chính xác tới giây, và
        # $bak đã là thư mục thì `cp -a file $bak` sẽ chép VÀO trong nó.
        ts=$(date +%Y%m%d%H%M%S)
        bak="$f.tsuki-bak-$ts"
        n=0
        while [ -e "$bak" ]; do n=$((n+1)); bak="$f.tsuki-bak-$ts-$n"; done
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
# đường dẫn đích sẽ rơi vào cwd, mà cwd khi chạy install.sh là thư mục repo, tức là
# rác vào chính repo đang chạy.
readonly PARU_SRC=$TSUKI_HOME/.local/src/paru

# PKGBUILD của paru: makedepends=('cargo'), depends=('git' 'pacman' 'libalpm.so>=14')
# bo qua SC2034 o day: shellcheck khong thay mang doc qua nameref
# (xem ghi chuc dau muc "packages")
# shellcheck disable=SC2034
readonly PKG_AUR=(
    cargo
)
# Gói bộ gõ. Không có trong kho nào của Arch/CachyOS, chỉ có ở AUR.
readonly PKG_PTY=(
    fcitx5-lotus-bin
    # Native messenger cho Tridactyl (extension Vim cho Firefox ở PKG_KEYBINDS).
    # KHÔNG có trong kho — chỉ có ở AUR (firefox-tridactyl-native 1.24.2-2 và
    # bản -bin). Nếu thiếu nó thì tridactyl vẫn chạy nhưng mọi tính năng
    # cần native bị chặn: :nativeinstall, :restart, :setpref, :guiset, :saveas,
    # và dấu `!` để chạy lệnh hệ thống. Cần paru — xem cmd_pty.
    firefox-tridactyl-native
)

# `sed -n 1p` chứ không phải `head -1`: head đóng pipe sau dòng đầu thì phía
# ghi dính SIGPIPE (141), dưới pipefail thành lỗi. sed đọc hết nên không có.
paru_ver() { paru --version 2>/dev/null | sed -n '1p'; }

cmd_paru() {
    if command -v paru >/dev/null 2>&1; then
        ok "paru đã có: $(paru_ver)"
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
    ok "paru: $(paru_ver)"
}

cmd_pty() {
    need paru git makepkg
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

    local unit
    unit="fcitx5-lotus-server@$(tsuki_user).service"
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
        firefox)   cmd_firefox "${2:-}" ;;
        check)     cmd_check ;;
        themes)    cmd_themes ;;
        session)   cmd_session "${2:-}" ;;
        xlibre)    cmd_xlibre "${2:-stable}" ;;
        arisa)     cmd_arisa ;;
        paru)      cmd_paru ;;
        pty)       cmd_pty ;;
        uninstall) cmd_uninstall ;;
        all)
            # Báo trước phần thiếu rồi mới làm — `all` chạy 8 bước,
            # hỏng ở bước 6 vì thiếu `make` thì mất công vô ích.
            cmd_check
            # Trước deps: PKG_KEYBINDS có visual-studio-code-bin và discord-ptb
            # nằm trong kho arisa. Hỏi sau khi cài deps thì hai gói đó đã bị
            # bỏ qua rồi, phải chạy lại ./install.sh deps mới lấy được.
            cmd_arisa
            cmd_deps
            # Sau deps: cần base-devel + cargo mới build được paru.
            cmd_pty
            cmd_build
            cmd_dotfiles
            cmd_themes
            cmd_firefox
            cmd_session
            ;;
        -h|--help|help) usage ;;
        *) die "lệnh lạ: $cmd  (xem --help)" ;;
    esac
}

main "$@"

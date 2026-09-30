#!/bin/sh
#
# run.sh — điểm vào của session Tsuki (dwm).
#
# Chạy được từ hai nơi, cùng một đường:
#   - TTY:        startx            (đọc ~/.xinitrc, do install.sh sinh ra)
#   - DM:         Tsuki.desktop     (GDM/SDDM/LightDM quét /usr/share/xsessions)
#
# Không được giả định mình chạy từ display manager: startx không nạp
# ~/.profile, không có $DBUS_SESSION_BUS_ADDRESS, $XDG_RUNTIME_DIR có thể
# chưa có, và biến session của DM (GNOME/Wayland) có thể còn sót lại.
# Mọi thứ cần cho một session X sạch đều dựng ở đây.

set -u

# Tạo/thục file mà KHÔNG để lỗi chuyển hướng giết shell.
#
# `: >file 2>/dev/null || thu_thay` TRONG DASH KHÔNG HOẠT ĐỘNG. Lỗi chuyển
# hướng là lỗi CHÍ TỬ với script không tương tác: shell thoát ngay, `||` không
# bao giờ chạy. Đo trực tiếp:
#     $ dash -c ': >/proc/khong/ghi/x.log 2>/dev/null || echo tiep tuc; echo vao day'
#     dash: 2: cannot create /proc/khong/ghi/x.log: Directory nonexistent
#     (không có dòng "vao day" — shell đã chết)
#     $ bash -c '...cùng lệnh...'
#     tiep tuc
#     vao day
# Tức là máy này (/bin/sh -> bash) che giấu lỗi, còn hệ thống có /bin/sh là
# dash thì run.sh chết. Bọc trong subshell thì lỗi chỉ giết subshell:
#     $ dash -c 'if ! ( : >/proc/khong/x.log ) 2>/dev/null; then L=/dev/null; ...'
#     L=/dev/null
#
# PHẢI ĐỊNH NGHĨA TRƯỚC mọi chỗ dùng — hàm bash/dash phải có trước lệnh gọi.
safe_touch() { ( : >"$1" ) 2>/dev/null; }

# --- nhật ký phiên -----------------------------------------------------------
# Trước đây run.sh không ghi gì cả. Mọi thứ đều `2>/dev/null` hoặc `>/dev/null
# 2>&1`, nên khi session có vấn đề (con trỏ không đổi, dunst không hiện OSD,
# daemon chết ngay) thì KHÔNG còn dấu vết để tra. Đây là loại lỗi hay gặp
# nhất trên rice và cũng khó nhất để tái hiện.
#
# Ghi vào $XDG_CACHE_HOME/tsuki/session.log, ghi đè mỗi lần đăng nhập (phiên
# mới phải bắt đầu sạch, không trộn log của phiên hôm qua). `tee -a` cho cả
# màn hình lẫn file: người dùng thấy ngay, và vẫn còn dấu vết sau.
TSUKI_LOG_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/tsuki"
# Rơi về $TMPDIR thì đặt tên kèm uid — nếu không, hai user cùng lỗi sẽ tranh
# nhau một file /tmp/tsuki/session.log và ghi đè lẫn nhau.
mkdir -p "$TSUKI_LOG_DIR" 2>/dev/null || TSUKI_LOG_DIR="${TMPDIR:-/tmp}/tsuki-$(id -u)"
# PHẢI mkdir CẢ nhánh fallback. Bản trước chỉ mkdir nhánh chính rồi đổi tên
# biến, nên khi XDG_CACHE_HOME không ghi được thì thư mục fallback chưa tồn tại
# và dòng `: >"$TSUKI_LOG"` ngay sau đó thất bại:
#     run.sh: 30: cannot create /tmp/tsuki-1000/session.log: Directory nonexistent
# rc=2, script chết trước khi làm được gì. Do test-run-matrix.sh dò ra.
mkdir -p "$TSUKI_LOG_DIR" 2>/dev/null || TSUKI_LOG_DIR=""
if [ -n "$TSUKI_LOG_DIR" ]; then
    TSUKI_LOG="$TSUKI_LOG_DIR/session.log"
    safe_touch "$TSUKI_LOG" || TSUKI_LOG=/dev/null
else
    # Không tạo được chỗ nào để ghi nhật ký thì dùng /dev/null cho chắc, thay
    # vì để `: >""` làm chết cả phiên.
    TSUKI_LOG=/dev/null
fi
# Nhật ký ghi tên các tiến trình, phiên, đường dẫn profile — thông tin riêng
# của máy. Đặt mode 600 tường minh thay vì dựa vào `umask` toàn cục, xem
# khối "quyền mặc định" bên dưới để biết vì sao không dùng cách đó.
chmod 600 "$TSUKI_LOG" 2>/dev/null || true
export TSUKI_LOG

log() {
    # `[ -w ]` là stat, không fork, nên rẻ. Nó giữ cho lỗi chuyển hướng ở dòng
    # sau không bao giờ thành lỗi chí tử (xem safe_touch): nếu TSUKI_LOG bị xoá,
    # mount mất, hay đổi quyền giữa phiên thì chuyển hằng sang /dev/null.
    # /dev/null luôn ghi được nên từ đó log() không còn đường để chết.
    [ -w "$TSUKI_LOG" ] 2>/dev/null || TSUKI_LOG=/dev/null
    printf '%s\n' "$*" >>"$TSUKI_LOG" 2>/dev/null || :
}
say()  { printf '%s\n' "$*"; log "$*"; }
warn() { printf 'tsuki: %s\n' "$*" >&2; log "WARN  $*"; }
info() { log "INFO  $*"; }
fail() { printf 'tsuki: %s\n' "$*" >&2; log "FAIL  $*"; }
have() { command -v "$1" >/dev/null 2>&1; }
stop_daemons() {
    # Cờ "đang tắt" đặt TRƯỚC mọi thứ khác. Watchdog thấy cờ là thoát
    # ngay, nên không có trường hợp nó hồi sinh daemon trong lúc ta đang dọn
    # (race thật: watchdog đang ngủ 15s, thức dậy giữa lúc dọn).
    safe_touch "$XDG_RUNTIME_DIR/tsuki-stopping" || true
    # Dừng watchdog trước, rồi mới giết daemon — nếu ngược lại watchdog có
    # thể kịp chạy một vòng nữa.
    if [ -f "$XDG_RUNTIME_DIR/tsuki-watchdog.pid" ]; then
        _wp=$(head -1 "$XDG_RUNTIME_DIR/tsuki-watchdog.pid" 2>/dev/null)
        case ${_wp:-} in ''|*[!0-9]*) ;; *) kill "$_wp" 2>/dev/null || true ;; esac
    fi
    # KHÔNG để dòng `_f` trần ở đây: shell hiểu nó là lệnh cần thực thi ->
    # "_f: command not found" mỗi lần dọn. Đã mắc bằng test tích hợp.
    for _f in "$XDG_RUNTIME_DIR"/tsuki-*.pid "$XDG_RUNTIME_DIR"/tsuki-*.lock; do
        [ -f "$_f" ] || continue
        case $_f in
        *.lock)
            # Giết TIẾN TRÌNH THẬT đang giữ khoá, không chỉ pid trong file.
            #
            # VÌ SAO CẦN: daemon tự fork thì $! là LAUNCHER đã chết, không
            # phải daemon. Đo được trên phiên thật với `fcitx5 -d`:
            #   tsuki-fcitx.pid = 452635 (CHẾT)   <- launcher
            #   pid 3046 (fcitx5 thật)             <- daemon, vẫn sống
            # Nên `kill $pid` trên nội dung pidfile là kill một PID đã chết:
            # im lặng, exit status bị bỏ, tưởng như đã dọn xong. Rồi dòng
            # `rm -f "$_f"` xoá luôn file khoá — trong khi daemon vẫn giữ fd
            # trỏ tới inode đã xoá. Hai hậu quả đo được:
            #   1. daemon sống sót qua logout, phiên sau sinh bản thứ hai
            #   2. khoá trên đĩa là inode MỚI và TRỐNG, nên start_daemon tưởng
            #      daemon đã chết -> watchdog thử sinh bản thứ hai -> fcitx5 từ
            #      chối vì đã có một instance -> khoá lại trống -> watchdog ghi
            #      "không khởi động được fcitx (thiếu binary?)" — CHẨN ĐOÁN SAI.
            #      Binary có; daemon sống; chỉ là ta đã mất dấu nó.
            #
            # `fuser` in pid ra stdout, tên file ra stderr, và mất 59ms với
            # hàng nghìn tiến trình. Quét /proc/*/fd thì phải gọi readlink
            # hàng chục nghìn lần — quá chậm lúc logout. Nên dùng fuser, và
            # lùi về pidfile khi máy không có fuser.
            #
            # AN TOÀN: run.sh cha KHÔNG giữ file khoá nào (đã kiểm /proc/<pid>/fd
            # trên phiên thật), nên không có nguy cơ tự giết chính mình. Watchdog
            # giữ tsuki-watchdog.lock nhưng đã bị giết ở trên; giết lần hai vô
            # hại, và lỡ pidfile của nó sai thì đây chính là cứu.
            if have fuser; then
                for _hp in $(fuser "$_f" 2>/dev/null); do
                    case ${_hp:-} in ''|*[!0-9]*) continue ;; esac
                    kill "$_hp" 2>/dev/null || true
                done
            fi
            ;;
        *.pid)
            _p=$(head -1 "$_f" 2>/dev/null)
            case ${_p:-} in ''|*[!0-9]*) ;; *) kill "$_p" 2>/dev/null || true ;; esac
            ;;
        esac
        rm -f "$_f"
    done
    # File trạng thái của mediacard.sh: nó ghi vào $XDG_RUNTIME_DIR nhưng không
    # tự dọn (không có trap trong file đó). XDG_RUNTIME_DIR bị xoá khi logout
    # nên chỉ còn sót qua vòng lặp rebuild trong cùng phiên — nhưng để lại
    # cũng không có lý do.
    rm -f "$XDG_RUNTIME_DIR/nowplaying-art" \
          "$XDG_RUNTIME_DIR/nowplaying-last" \
          "$XDG_RUNTIME_DIR/pulse" 2>/dev/null || true
    # Cờ tắt và bộ đếm thử lại chỉ có ý nghĩa trong phiên này.
    rm -f "$XDG_RUNTIME_DIR/tsuki-stopping" \
          "$XDG_RUNTIME_DIR"/tsuki-retry-* \
          "$XDG_RUNTIME_DIR"/tsuki-gaveup-* 2>/dev/null || true
}

# `stop_daemons` và `_dwm_forward` phải ĐỊNH NGHĨA TRƯỚC khối trap bên dưới.
# Thường thì thứ tự không quan trọng vì thân trap chỉ chạy lúc thoát — nhưng
# `exit 1` sớm (vd TSUKI_DIR sai) cũng đi qua trap EXIT, lúc đó hàm chưa có.
# Lỗi bị nuốt nhờ `2>/dev/null` trong trap, nên nó chỉ là may mắn. T20 bắt
# được. Dời lên đây để hết phụ thuộc vào may mắn.

_dwm_forward() {
    # $1 = TERM | HUP | INT. Chỉ khi dwm còn sống và khác chính ta.
    if [ -n "$_dwm_pid" ] && [ "$_dwm_pid" -ne "$$" ] 2>/dev/null; then
        kill -"$1" "$_dwm_pid" 2>/dev/null
    fi
    :
}

# Khi run.sh bị giết (SIGTERM/SIGHUP từ logout, hoặc đóng terminal), các daemon
# nó spawn sẽ thành mồ côi và tiếp tục chạy tới lần đăng nhập sau. Lần sau
# start_daemon sẽ phát hiện khoá vẫn bị giữ nên bỏ qua — nên session mới có
# daemon CŨ, có tuổi, thuộc phiên trước. trap ở đây dọn cả khoá lẫn tiến
# trình.
#
# `exit 0` trong vòng lặp dwm cũng đi qua trap EXIT, nên nhánh thoát chủ động
# vẫn dọn đúng (không cần gọi stop_daemons thủ công, nhưng gọi vẫn vô hại).
#
# PHẢI CHUYỂN TIẾP TÍN HIỆU CHO dwm, không chỉ tự dọn. Xem khối "dwm" cuối
# file: dwm chạy NỀN + `wait`, nên khi run.sh nhận tín hiệu, `wait` bị ngắt và
# trap chạy ngay. Nếu trap chỉ dọn daemon rồi thoát mà không báo dwm, dwm sống
# mồ côi giữ X server — người dùng thấy màn hình đen nhưng dwm vẫn giữ cửa sổ.
# pid của dwm, để trap chuyển tiếp tín hiệu được. Đặt rỗng; vòng lặp dwm
# sẽ gán khi dwm thật sự chạy.
_dwm_pid=""

# POSIX quy định trap BỊ HOÃN khi shell đang chờ một lệnh foreground. Bản cũ
# chạy `dwm` ở foreground nên `kill -TERM <pid run.sh>` KHÔNG làm gì cả: đo thật
# ở sandbox, sau 3 giây run.sh vẫn sống, dwm vẫn sống, và dòng "run.sh nhận
# SIGTERM" không hề có trong log. Nay dwm chạy nền + `wait` nên trap chạy
# ngay (đo cùng cách: trap chạy, `wait` trả 143).
#
# Lưu ý an toàn khi ngắm dwm ra nền: shell KHÔNG có job control (không phải
# shell tương tác) nên lệnh `&` KHÔNG tạo process group mới — dwm vẫn cùng
# pgid với run.sh, nên SIGHUP từ đóng terminal vẫn tới cả hai như cũ. Đo trên
# máy thật: run.sh pid 2845 pgid 2845, dwm pid 3215 pgid 2845.
trap 'stop_daemons 2>/dev/null; :' EXIT
trap '_dwm_forward TERM; info "run.sh nhận SIGTERM — dọn daemon"; stop_daemons 2>/dev/null; exit 143' TERM
trap '_dwm_forward HUP; info "run.sh nhận SIGHUP (logout) — dọn daemon"; stop_daemons 2>/dev/null; exit 129' HUP
trap '_dwm_forward INT; info "run.sh nhận SIGINT"; stop_daemons 2>/dev/null; exit 130' INT

# `warn_cursor` từng được gọi 3 lần ở khối con trỏ mà KHÔNG ĐỊNH NGHĨA ở đâu
# cả. Trong sh, gọi lệnh chưa định nghĩa chỉ in "command not found" rồi đi
# tiếp — nên đúng những thông báo phải cảnh báo người dùng cài theme cursor
# lại không bao giờ hiện. Giữ tên hàm cũ như một alias trỏ về warn.
warn_cursor() { warn "$*"; }

# --- vị trí repo: suy ra từ chính script, không hardcode $HOME/dwm -----------
# Đặt sau $HOME để người dùng clone ở đường dẫn khác vẫn chạy được.
TSUKI_DIR="${TSUKI_DIR:-$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd -P)}"
export TSUKI_DIR
# Alias tương thích: script cũ / dotfile cá nhân từng đọc $DWM_DIR. Giữ để
# không vỡ gì; nội bộ Tsuki chỉ dùng TSUKI_DIR — khỏi hai tên cho một thứ.
export DWM_DIR="$TSUKI_DIR"

# startx không nạp profile login shell -> PATH không có /usr/local/bin,
# nơi `make install` đặt dwm/st/slock/dmenu/slstatus. Thiếu thì while type dwm
# thoát ngay và ta bị đá về màn hình đăng nhập mà không thấy cửa sổ nào.
PATH="/usr/local/bin:$PATH"
export PATH

# $TSUKI_DIR/dmenu ĐỨNG TRƯỚC /usr/local/bin — đây là chỗ duy nhất dmenu lấy
# màu mới. `dmenu_run` (script trong /usr/local/bin) gọi `dmenu` và `dmenu_path`
# BẰNG TÊN trần, nên nó lấy bản đầu tiên trong PATH. Trước đây dwmwal.sh chỉ
# `make -C dmenu` (build trong repo) mà không cài, nên Super+R ra dmenu màu cũ
# vĩnh viễn, đổi wallpaper vô ích. Đặt thư mục build của repo trước là cách
# không cần root — cùng ý với cách slstatus chạy bản trong repo bên dưới.
# Nếu repo chưa build (mới clone) thì rơi về /usr/local/bin như cũ, an toàn.
export PATH="$TSUKI_DIR/dmenu:$TSUKI_DIR:$PATH"

# Kiểm tra TSUKI_DIR CÓ THẬT trước khi mọi thứ bên dưới đọc file trong đó.
# Không có bước này thì khi repo bị đổi tên / di chuyển / xoá, các lệnh đọc
# "$TSUKI_DIR/..." chỉ ra rỗng và fail im lặng: ảnh nền rỗng, xsettingsd không
# có config, updates-loop/mediacard không chạy — bề mặt thì session vẫn lên,
# bên trong thì nửa cấu hình là cấu hình chết. Nay nói thẳng ngay từ đầu.
if [ ! -d "$TSUKI_DIR" ]; then
    printf 'tsuki: TSUKI_DIR không tồn tại: %s\n' "$TSUKI_DIR" >&2
    printf '       startx gọi ~/.xinitrc, kiểm tra xem nó trỏ đúng repo không.\n' >&2
    exit 1
fi
if [ ! -d "$TSUKI_DIR/scripts" ]; then
    printf 'tsuki: %s không phải repo Tsuki (thiếu thư mục scripts/)\n' "$TSUKI_DIR" >&2
    exit 1
fi
info "TSUKI_DIR: $TSUKI_DIR"

# Locale. Không đặt thì app GTK/GLib in cảnh báo "Failed to connect to the
# bus"/"locale not supported" và hiển thị sai ngày/giờ. Ưu tiên giữ nguyên thứ
# người dùng đã đặt (qua ~/.xinitrc hoặc locale.conf); chỉ đặt khi rỗng.
# `C.UTF-8` có sẵn trên mọi Arch và xử lý đủ UTF-8, kể cả khi
# en_US.UTF-8 chưa được sinh trong /etc/locale.gen.
if [ -z "${LANG:-}" ]; then
    LANG=${LC_ALL:-C.UTF-8}
    export LANG
    info "LANG chưa đặt — dùng $LANG"
fi
[ -n "${LC_CTYPE:-}" ] || { LC_CTYPE=${LANG}; export LC_CTYPE; }

# KIỂM FONT, đồng bộ, trước khi chạy dwm.
#
# dwm.c:3101 — `if (!drw_fontset_create(dwm, fonts, LENGTH(fonts))) die(...)`.
# THIẾU FONT LÀ CHẾT NGAY lúc khởi động: màn hình đen, không bar. Không có
# gì để tra nếu không biết điều này.
#
# ĐỌC MẢNG `fonts[]` THẲNG TỪ config.h, không hardcode tên font — nên sửa
# config.h là tự kiểm lại, không phải sửa ở đây.
#
# CHI HAI TIẾN TRÌNH CON: `fc-list` + MỘT lần `awk`. Đo bằng mốc thời gian ở
# từng khối của run.sh:
#     phần danh tính    1 ms      daemon nền        14 ms
#     nền desktop       0 ms      thumbnail          3 ms
#     thông báo+portal  4 ms      KIỂM FONT         33 ms
# 33ms là khối lớn nhất, và phần lớn KHÔNG phải fontconfig: fc-list ~10ms,
# fc-match ~5ms (chạy song song vẫn 11ms vì fontconfig tự khởi tạo). Phần còn
# lại là ~9 tiến trình con: sed, tr, grep, printf. Gộp hết vào một awk.
#
# HÀM NÀY PHẢI ĐỊNH NGHĨA TRƯỚC CHỖ GỌI. Lần đầu đặt lệnh gọi ở đầu phiên còn
# hàm ở gần cuối file -> `line 178: _font_check: command not found`, và T3/T19
# bắt được ngay. Hàm shell phải có trước lệnh gọi, không có ngoại lệ.
#
# CHẠY SONG SONG, KHÔNG PHẢI BẤT ĐỒNG BỘ. Lệnh gọi nằm ở khối danh tính
# session, nhưng ta `wait` ngay TRƯỚC khi gọi dwm — nên kết quả chắc chắn có
# trong nhật ký trước khi dwm chạy. Đã thử bỏ hẳn `wait` (thuần bất đồng bộ)
# rồi báo cố và bỏ: T16/T17 fail vì grep nhật ký ngay khi run.sh thoát, và
# cleanup phải chờ. Chồng lấp thời gian chờ thì được, bất đồng bộ thì không.
_font_check() {
    have fc-list || return 0
    _fc_all=$(fc-list -f '%{family}\n' 2>/dev/null)
    # RỖNG = KHÔNG XÁC MINH ĐƯỢC, KHÔNG phải font thiếu. Cache fontconfig
    # hỏng, fc-list bị giới hạn, hay không có fontconfig đều ra rỗng. Báo động
    # giả thì tệ hơn hẳn sót: bảo người dùng cài gói họ đã có.
    [ -n "$_fc_all" ] || return 0

    _fc_bad=$(printf '%s\n' "$_fc_all" | awk -v cfg="$TSUKI_DIR/config.h" '
        {                                   # gom mọi family đã cài
            n = split($0, a, ",")
            for (i = 1; i <= n; i++) {
                gsub(/^[ \t]+|[ \t]+$/, "", a[i])
                if (a[i] != "") { have[a[i]] = 1; nfam++ }
            }
        }
        END {
            while ((getline l < cfg) > 0)
                if (l ~ /static const char \*fonts\[\]/) { line = l; break }
            close(cfg)
            if (line == "") { print "SO 0"; exit 0 }
            s = index(line, "{"); e = index(line, "}")
            if (s == 0 || e <= s) exit 0
            body = substr(line, s + 1, e - s - 1)
            cnt = split(body, items, ",")
            m = 0
            for (i = 1; i <= cnt; i++) {
                if (match(items[i], /"[^"]*"/) == 0) continue
                f = substr(items[i], RSTART + 1, RLENGTH - 2)
                if (f == "") continue
                fam = f; sub(/:.*$/, "", fam)      # bỏ :style=...:size=...
                # "serif"/"monospace" là yêu cầu chung của fontconfig, không
                # phải tên font, nên không có trong danh sách family.
                # PHẢI HẠ CHỮ THƯỜNG trước khi so: config.h có thể viết
                # "Serif", còn alias của fontconfig là chữ thường. Bản shell
                # cũ làm `tr A-Z a-z`; làm bản awk mà quên bước này thì T16
                # bắt được ngay ("báo chết-ngay dù font hợp lệ").
                lfam = tolower(fam)
                if (lfam == "serif" || lfam == "sans-serif" || lfam == "sans" ||
                    lfam == "monospace" || lfam == "cursive" || lfam == "fantasy" ||
                    lfam == "system-ui" || lfam == "emoji" || lfam == "math" ||
                    lfam == "fangsong" || lfam == "installed" ||
                    lfam == "ui-serif" || lfam == "ui-sans-serif" ||
                    lfam == "ui-monospace" || lfam == "ui-rounded") continue
                if (fam in have) continue
                m++; bad[m] = f
            }
            if (m == 0) { print "SO " nfam; exit 0 }
            for (i = 1; i <= m; i++) print bad[i]
        }' 2>/dev/null)

    case $_fc_bad in
    "SO "*)  info "font: hết (${_fc_bad#SO } family)"; return 0 ;;
    esac
    if [ -n "$_fc_bad" ]; then
        fail "dwm SẼ CHẾT NGAY: config.h trỏ font không có trên máy:"
        printf '%s\n' "$_fc_bad" | while IFS= read -r _l; do
            [ -n "$_l" ] && fail "  $_l  -> không có trong danh sách font đã cài"
        done
        fail "  cài gói: ttc-iosevka  ttf-jetbrains-mono-nerd   rồi chạy fc-cache -f"
        fail "  (đọc thẳng từ config.h nên sửa config.h cũng được kiểm lại)"
    fi
}

# BẮT ĐẦU kiểm font ngay từ đầu phiên, để nó chạy song song với phần khởi
# động daemon. `wait` của nó đặt ngay trước khi gọi dwm.
( _font_check ) & _FONT_PID=$!

# --- danh tính session ------------------------------------------------------
# GDM kế thừa nguyên bộ biến của session GNOME cho mọi session nó khởi chạy.
# Ta là dwm + X11, nên phải tự ghi đè trước khi bất kỳ tiến trình nào kế thừa.
# Nếu không: xdg-desktop-portal chạy dưới nhãn GNOME/Wayland trên X11 thật →
# FileChooser nhận lệnh và trả về request handle nhưng không dựng được cửa sổ
# (Save Image As / Lưu ảnh không hiện gì).
export XDG_CURRENT_DESKTOP=dwm
export XDG_SESSION_DESKTOP=dwm
export XDG_SESSION_TYPE=x11
export DESKTOP_SESSION=dwm

# startx có thể khởi động với XDG_RUNTIME_DIR trỏ vào thư mục không tồn tại
# (user cũ còn sót). Các app dùng nó sẽ lỗi âm thầm.
#
# Khi rơi về $TMPDIR, thư mục nằm trong /tmp nên PHẢI khoá quyền. Không có
# chmod thì `mkdir -p` tạo ra 755 (đo thật), và mọi file tao sau trong đó —
# tsuki-*.lock, tsuki-*.pid — ra 644: user khác trên máy đọc được, biết tên
# tiến trình và pid. Tệ hơn: user khác tạo trước thư mục cùng tên thì ta dùng
# nhầm thư mục của họ. 700 chặn cả hai.
if [ -z "${XDG_RUNTIME_DIR:-}" ] || [ ! -d "${XDG_RUNTIME_DIR:-/nonexistent}" ]; then
    XDG_RUNTIME_DIR="/run/user/$(id -u)"
    if [ ! -d "$XDG_RUNTIME_DIR" ]; then
        XDG_RUNTIME_DIR="${TMPDIR:-/tmp}/tsuki-$(id -u)"
        # Nếu thư mục do user khác tạo sẵn, mkdir -p vẫn "thành công" — nên
        # kiểm tra chủ sở hữu trước khi dùng, không tin kết quả của mkdir.
        if [ -d "$XDG_RUNTIME_DIR" ] && [ "$(stat -c %u "$XDG_RUNTIME_DIR" 2>/dev/null)" != "$(id -u)" ]; then
            XDG_RUNTIME_DIR="${TMPDIR:-/tmp}/tsuki-$(id -u)-$$"
        fi
    fi
    mkdir -p "$XDG_RUNTIME_DIR" 2>/dev/null || true
    chmod 700 "$XDG_RUNTIME_DIR" 2>/dev/null || true
    export XDG_RUNTIME_DIR
    info "XDG_RUNTIME_DIR dựng lại: $XDG_RUNTIME_DIR"
fi

# --- XWayland: KHÔNG dùng ---------------------------------------------------
# Tsuki chạy X11 thuần, không bật XWayland. Gói xorg-xwayland chỉ cài binary
# /usr/bin/Xwayland chứ không có hook nào bật trong X session, nên nếu muốn thì
# phải tự thêm khối dưới đây. Hiện để tắt có chủ đích: app Wayland-only chạy
# qua XWayland bị vỡ clipboard và không chia sẻ màn hình được.
#
# if ! pgrep -x Xwayland >/dev/null 2>&1; then
#     Xwayland :1 -rootless -noreset >/dev/null 2>&1 &
#     sleep 0.5
# fi
# export WAYLAND_DISPLAY=wayland-1

# --- phụ đơn vị: chạy nền, chết thì session vẫn sống --------------------------
# Mỗi thứ một hàm + khoá: không thêm process group mới, nên khi dwm chết
# (rebuild) các daemon này vẫn sống và không bị nhân bản.
#
# VÌ SAO DÙNG flock THAY VÌ PIDFILE (bản cũ chỉ `kill -0 $(cat pidfile)`):
#
#   1) PID REUSE. Nếu daemon chết mà pidfile còn, Linux sớm cấp lại PID đó
#      cho tiến trình khác. `kill -0` vẫn thành công -> start_daemon tưởng
#      daemon đang chạy -> BỎ QUA, không spawn. Triệu chứng thật trên máy này:
#      tsuki-fcitx.pid trỏ 3223 đã chết, trong khi fcitx5 thật đang chạy với
#      pid 185142 — pidfile sai hoàn toàn. Nếu 3223 được cấp lại, lần đăng
#      nhập sau sẽ không khởi động fcitx5 mà không in lỗi nào.
#
#   2) PIDFILE CŨ KHÔNG TỰ XOÁ. Nó nằm lại trong /run/user/1000 tới lần
#      đăng nhập sau; không ai dọn.
#
#   3) SO TÊN KHÔNG CHẮC CHẮN. Thử so /proc/<pid>/comm với tên daemon
#      không ăn: `start_daemon fcitx fcitx5 -d` cho comm="fcitx5" chứ không
#      phải "fcitx". Nếu tiến trình bị thu hồi mà tình cờ trùng tên thì vẫn
#      không phân biệt được.
#
# flock giải quyết cả ba: KERNEL tự thả khoá khi tiến trình chết, kể cả khi
# bị kill -9, nên trạng thái "daemon đang chạy" không bao giờ thành sai lệch.
# Cùng cách updates-loop.sh tự khoá (dòng 18-19 của file đó).
#
# SỰ THẬT ĐÃ ĐO ĐẠC ĐƯỢC TRÊN PHIÊN THẬT (2026-09-30, sau khi đổi sang flock):
#   fcitx5 -d TỰ FORK RỒI THOÁT. pid ta ghi ($! = 3054) là tiến trình CHA và
#   chết ngay; daemon thật là pid khác (3061, ppid=1). Nếu còn dùng pidfile
#   kiểu cũ thì `kill -0 3054` thất bại và lần đăng nhập sau sẽ spawn một
#   fcitx5 thứ hai. Với flock thì 3061 vẫn giữ khoá qua fd 8 -> đúng một bản.
#   Đây mới là nguyên nhân thật của pidfile "thối" quan sát được ở phiên trước
#   (tsuki-fcitx.pid trỏ 3223 đã chết) — KHÔNG phải PID reuse như tôi đoán
#   giữa chừng. Cả hai đều được flock chặn, nhưng ghi đúng nguyên nhân thì
#   comment mới đáng tin.
#
# pidfile vẫn ghi lại, nhưng chỉ để TIỆN TRA. Với lệnh tự daemonize (nhận
# `-d`) thì số trong pidfile là pid của tiến trình khởi chạy, KHÔNG phải pid
# daemon — đừng dùng nó để `kill`. Muốn biết daemon thật thì hỏi khoá:
#   fuser ~/.cache/tsuki/session.log >/dev/null 2>&1; fuser "$XDG_RUNTIME_DIR/tsuki-fcitx.lock"
start_daemon() {
    _name=$1; shift
    _lock="$XDG_RUNTIME_DIR/tsuki-$_name.lock"
    _pidf="$XDG_RUNTIME_DIR/tsuki-$_name.pid"

    # Nếu không probe được (không có flock, không cấp quyền ghi) thì vẫn
    # spawn: cũ hơn là chạy, thiếu daemon mới là hỏng.
    if have flock; then
        if flock -n "$_lock" -c true 2>/dev/null; then
            :                                   # khoá trống -> chưa có daemon
        else
            info "$_name: đã chạy (đang giữ khoá)"
            return 0
        fi
    elif [ -f "$_pidf" ] && kill -0 "$(head -1 "$_pidf" 2>/dev/null)" 2>/dev/null; then
        return 0                              # không có flock: lùi về pidfile
    fi

    # Subshell giữ khoá rồi exec — `exec` GIỮ NGUYÊN PID nên với lệnh chạy
    # tiền cảnh, số ghi ra đúng là pid của daemon.
    #
    # DÙNG FD 8, KHÔNG DÙNG FD 9. updates-loop.sh tự khoá bằng
    # `exec 9>"$HOME/.cache/dwm-updates.lock"` (dòng 18 của file đó) — `exec 9>`
    # GHI ĐÈ fd 9 của chính nó, tức là thả khoá mà run.sh đang giữ. Đã đo được
    # trên phiên thật: sau khi chạy, khoá `tsuki-updates.lock` báo trống.
    # Chọn fd 8 thì không va chạm với quy ước fd 9 phổ biến của script tự khoá.
    (
        exec 8>"$_lock"
        flock -n 8 || exit 0
        # ĐÓNG fd 7 trước khi exec. fd 7 là khoá RIÊNG của watchdog
        # (_start_watchdog mở nó), và watchdog gọi start_daemon khi hồi sinh
        # daemon nên mọi daemon nó sinh đều kế thừa fd 7 — tức là cầm khoá
        # của watchdog. Do đo trong test: daemon hồi sinh có
        # `fd 7 -> tsuki-watchdog.lock`. Hệ quả: watchdog chết thì khoá vẫn
        # bị giữ bởi con, `flock -n 7` của watchdog mới thất bại, và watchdog
        # KHÔNG BAO GIỜ khởi động lại được trong phần đời còn lại của phiên.
        # Đóng ở đây chỉ ảnh hưởng con; watchdog giữ fd 7 của riêng nó.
        # `exec 7>&-` khi fd 7 không mở thì không báo lỗi.
        exec 7>&-
        exec "$@"
    ) >/dev/null 2>&1 &
    printf '%s\n' "$!" >"$_pidf"
    info "$_name: pid $!"
}


# --- watchdog: định nghĩa lệnh hồi sinh + danh sách giám sát -----------------
#
# PHẢI KHỚP CHÍNH XÁC với lệnh spawn ở trên. Lệch một chỗ thì watchdog hồi
# sinh thứ KHÁC với thứ đang chạy — ví dụ gọi `fcitx5` không kèm `-d` sẽ tạo
# một tiến trình chạy tiền cảnh treo vĩnh viện thay vì daemon hoá.
supervise_one() {
    case $1 in
        polkit)   [ -x /usr/lib/polkit-gnome/polkit-gnome-authentication-agent-1 ] &&
                      start_daemon polkit /usr/lib/polkit-gnome/polkit-gnome-authentication-agent-1 ;;
        fcitx)    command -v fcitx5 >/dev/null 2>&1 && start_daemon fcitx fcitx5 -d ;;
        xsettingsd) command -v xsettingsd >/dev/null 2>&1 &&
                      start_daemon xsettingsd xsettingsd -c "$TSUKI_DIR/.config/xsettingsd/xsettingsd.conf" ;;
        picom)    have picom && start_daemon picom picom ;;
        tumbler)  [ -n "$_tumblerd" ] && start_daemon tumbler "$_tumblerd" ;;
        dunst)    [ "$_have_user_bus" = 0 ] && have dunst && start_daemon dunst dunst ;;
        portal)   [ "$_have_user_bus" = 0 ] && {
                      for _p in /usr/libexec/xdg-desktop-portal /usr/lib/xdg-desktop-portal; do
                          [ -x "$_p" ] && { start_daemon portal "$_p"; break; }
                      done; } ;;
        portal-gtk) [ "$_have_user_bus" = 0 ] && {
                      for _p in /usr/libexec/xdg-desktop-portal-gtk /usr/lib/xdg-desktop-portal-gtk; do
                          [ -x "$_p" ] && { start_daemon portal-gtk "$_p"; break; }
                      done; } ;;
        *)        warn "watchdog: không biết hồi sinh '$1' — bỏ qua" ;;
    esac
}
# --- watchdog: daemon chết giữa phiên ----------------------------------------
#
# VẤN ĐỀ ĐO ĐƯỢC: giết `xsettingsd` giữa phiên, chờ 11 giây — không ai khởi
# động lại. Khoá `tsuki-xsettingsd.lock` báo TRONG (kernel tự thả khi tiến
# trình chết) nhưng KHÔNG có gì gọi start_daemon lần nữa, nên nó nằm chết
# tới lúc logout. Daemon chết âm thầm kiểu này còn tệ hơn không có: keybind
# vẫn còn, bấm không ra gì, không có gì báo lỗi.
#
# PHẠM VI CỐ Ý HẸP — chỉ daemon KHÔNG tự phục hồi:
#   - slstatus, updates, mediacard  → đã có vòng lặp bọc trong chính nó
#   - dunst, xdg-desktop-portal     → systemd --user tự restart (Type=dbus)
#   - fcitx, xsettingsd, tumblerd, polkit, picom → exec thẳng, chết là chết
# Nếu không có systemd user bus thì dunst/portal cũng vào danh sách.
#
# CÓ TRẦN, KHÔNG LẶP VÔ TẠN, VÀ KHÔNG PHÍ RETRY LÊN THỨ KHÔNG BAO GIỜ CHẠY
# ĐƯỢC. Xem vòng lặp bên dưới: hồi sinh TRƯỚC, đếm SAU. Lệnh không giữ được
# khoá (thiếu binary, hoặc chết ngay) thì báo MỘT lần rồi bỏ hẳn — không đốt 5
# lần retry. Daemon đã từng chạy rồi mới chết mới tính từng lần, tối đa 5.
# Bản đầu đếm trước nên daemon-stub trong test đốt hết 5 lần mỗi cái, đo được
# 25 dòng WARN ngay lúc mới đăng nhập — thừa.
#
# AN TOÀN KHI TẮT: stop_daemons tạo cờ `tsuki-stopping` TRƯỚC khi dọn, watchdog
# thấy cờ là thoát ngay — không có trường hợp nó hồi sinh daemon trong lúc
# đang tắt. Cờ cũng nằm trong $XDG_RUNTIME_DIR nên tự biến mất khi logout.
#
# Watchdog giữ khoá riêng (fd 7) nên chạy hai bản chỉ một bản sống, và nó là
# tiến trình con của run.sh nên chết cùng session.
# Để ${VAR:-} chứ không gán thẳng: vừa để người dùng chỉnh được, vừa để test
# tăng tốc được. Bản đầu gán thẳng `WD_INTERVAL=15` nên ghi đè mọi giá trị từ
# môi trường — test truyền WD_INTERVAL=1 vẫn bị ép về 15, watchdog ngủ 15s
# trong khi test chỉ chờ 12s, và T13c fail oan. Đã mắc đúng lỗi này.
WD_INTERVAL="${WD_INTERVAL:-15}"
WD_MAX_RETRY="${WD_MAX_RETRY:-5}"

_start_watchdog() {
    (
        exec 7>"$XDG_RUNTIME_DIR/tsuki-watchdog.lock"
        flock -n 7 || exit 0
        # Vòng đầu chỉ để chờ: daemon vừa spawn có thể chưa kịp giữ khoá. Dù
        # chưa kịp thì cũng vô hại — trong start_daemon, subshell tự `flock -n 8
        # || exit 0` nên bản thứ hai tự thoát, không sinh trùng thật.
        _first=1
        while :; do
            sleep "$WD_INTERVAL"
            [ -e "$XDG_RUNTIME_DIR/tsuki-stopping" ] && exit 0
            if [ "$_first" = 1 ]; then _first=0; continue; fi

            for _d in ${WATCH_LIST:-}; do
                _lock="$XDG_RUNTIME_DIR/tsuki-$_d.lock"
                flock -n "$_lock" -c true 2>/dev/null || continue
                # khoá trống = daemon đã chết (kernel đã thả khi tiến trình chết)
                [ -e "$XDG_RUNTIME_DIR/tsuki-gaveup-$_d" ] && continue

                # THỬ HỒI SINH TRƯỚC, ĐẾM SAU. Nếu đếm trước thì daemon vốn
                # không bao giờ chạy được (binary thiếu, hoặc lệnh chết ngay)
                # sống thiệt 5 lần retry rồi mới bỏ — mỗi daemon 5 dòng WARN
                # trong nhật ký lúc mới đăng nhập, vô nghĩa. Đo được: 25 dòng.
                supervise_one "$_d"
                sleep 1
                if flock -n "$_lock" -c true 2>/dev/null; then
                    # vẫn không ai giữ khoá = lệnh không chạy được, hoặc chết
                    # ngay. Báo MỘT lần rồi bỏ hẳn.
                    warn "watchdog: không khởi động được $_d (thiếu binary?) — bỏ qua"
                    safe_touch "$XDG_RUNTIME_DIR/tsuki-gaveup-$_d" || true
                    continue
                fi
                # Lần này nó thật sự chạy được, nên mới tính là một lần thử.
                _cntf="$XDG_RUNTIME_DIR/tsuki-retry-$_d"
                _c=$(cat "$_cntf" 2>/dev/null) || _c=0
                case ${_c:-0} in ''|*[!0-9]*) _c=0 ;; esac
                _c=$((_c + 1))
                printf '%s\n' "$_c" >"$_cntf"
                if [ "$_c" -ge "$WD_MAX_RETRY" ]; then
                    warn "watchdog: $_d đã thử lại $_c lần vẫn chết — bỏ qua, xem nhật ký phiên"
                    safe_touch "$XDG_RUNTIME_DIR/tsuki-gaveup-$_d" || true
                else
                    warn "watchdog: $_d đã chết — khởi động lại (lần $_c/$WD_MAX_RETRY)"
                fi
            done
        done
    ) >/dev/null 2>&1 &
    printf '%s\n' "$!" >"$XDG_RUNTIME_DIR/tsuki-watchdog.pid"
}

# --- systemd user manager: đưa DISPLAY/XAUTHORITY vào môi trường -------------
#
# Vì sao: dunst và xdg-desktop-portal chạy dưới systemd --user (Type=dbus),
# không phải con trực tiếp của X. Khi khởi động bằng `startx`, systemd user
# manager KHÔNG có DISPLAY trong environment (startx không đi qua logind),
# nên khi app gọi org.freedesktop.Notifications thì systemd D-Bus-activate
# dunst.service -> ExecStart=/usr/bin/dunst, nhưng dunst không thấy DISPLAY:
#     WARNING: Cannot open X11 display.
#     CRITICAL: Couldn't initialize X11 output. Aborting...
# -> exit 1 -> start-limit-hit -> không có dịch vụ thông báo nào, phím
# volume im lặng, hộp thoại "Lưu ảnh" của Firefox không hiện.
#
# `systemctl --user import-environment` là đường đúng: đẩy biến của ta vào
# môi trường của systemd user manager, để unit đọc được DISPLAY thật.
# (Lệnh này nằm ở khối "thông báo + portal" bên dưới, ngay sau khi biết mình
# CÓ user bus hay không — gọi ở đây thì vô nghĩa khi không có bus.)

# --- D-Bus session bus: điều kiện tiên quyết của cả session -------------------
# Mọi thứ sau đây đi qua D-Bus: dunst (org.freedesktop.Notifications),
# xdg-desktop-portal (FileChooser cho Firefox), tumblerd (thumbnail Thunar),
# fcitx5, và PipeWire. KHÔNG có bus thì tất cả chết cùng lúc, mà trước đây
# run.sh không hề kiểm tra — chỉ có `systemctl --user ... || true` nuốt mất
# mọi dấu vết.
if [ -n "${DBUS_SESSION_BUS_ADDRESS:-}" ]; then
    info "D-Bus: $DBUS_SESSION_BUS_ADDRESS"
else
    warn "KHÔNG có DBUS_SESSION_BUS_ADDRESS"
    warn "  dunst, hộp thoại lưu file của Firefox, thumbnail Thunar, fcitx5 và âm thanh"
    warn "  đều cần nó. Nếu bạn thấy các thứ đó im lặng, đây là nguyên nhân."
    warn "  Thử: unset DBUS_SESSION_BUS_ADDRESS; eval \$(dbus-launch --sh-syntax)"
    if have dbus-run-session; then
        warn "  hoặc đăng nhập lại (cần có 'dbus-broker' hoặc 'dbus' đã cài)"
    fi
fi

# Quyền mặc định: 0022 — file 644, thư mục 755. Đặt tường minh để không phụ
# thuộc vào umask mà startx/login để lại.
#
# BẢN CŨ ĐẶT `umask 077` ở ĐÂY. SAI, ĐÃ GỠ. Lý do:
#
#   umask là TRẠNG THÁI TOÀN CỤC của tiến trình và mọi tiến trình con đều kế
#   thừa — kể cả dwm, rồi từ dwm tới mọi app người dùng mở. Đo trên máy
#   thật: `Umask: 0077` trong /proc/<pid>/status của dwm, slstatus, tumblerd;
#   /tmp/.bun-*.so tạo trong phiên đó là -rw-------.
#   Nghĩa là file người dùng lưu ra bị khoá 600 và thư mục 700, thay vì 644
#   và 755 — app nào tôn trọng umask thì bị, app nào tự đặt mode thì không.
#
#   Tệ hơn: umask đặt ở đây KHÔNG bảo vệ được thứ nó sinh ra để bảo vệ.
#   session.log được tạo ở DÒNG 28, trước dòng này, nên ra mode theo umask
#   lúc đó là 644 — đúng như đã đo được trên máy. ~/.cache/thumbnails thì
#   run.sh đã chmod 700 tường minh ở khối thumbnail, không cần umask.
#   Tức là `umask 077` không bảo vệ được gì, chỉ siết file của người dùng.
#
# Nên bảo vệ từng thứ bằng mode tường minh: session.log chmod 600 ở trên,
# ~/.cache/thumbnails chmod 700 ở khối thumbnail.
#
# ĐÃ KIỂM TRÊN MÁY THẬT, sau khi logout rồi đăng nhập lại (boot 21:05:48):
#   /proc/<pid>/status của dwm                    Umask: 0022   (trước: 0077)
#   ~/.cache/tsuki/session.log                    mode 600      (trước: 644)
#   /tmp/node-compile-cache, /tmp/opencode         755           (trước: 700)
#   file thường tạo trong phiên                    644
#   ~/.cache/tsuki/session.log                     600 — vẫn riêng tư như cũ
#
# Vẫn thấy 600/700 trong /tmp nhưng KHÔNG phải do umask:
#   /tmp/st-images-*, /tmp/scoped_dir*   700 — mkdtemp(), POSIX BẮT BUỘC 0700
#                                         bất kể umask (đã thử với umask 022:
#                                         mkdtemp ra 700, file thường bên
#                                         trong vẫn 644)
#   /tmp/.bun-*.so                        600 — bun tự đặt, binary private
umask 022 2>/dev/null || true

# --- nền desktop ------------------------------------------------------------
# xrdb -merge nạp font + màu X. Chạy ĐỒNG BỘ (bản cũ để `&`): nó mất chưa
# tới 50ms, nhưng nếu chạy nền thì app mở ra ngay sau có thể đọc X server
# TRƯỚC khi font được nạp -> dwm dựng bar bằng font dự phòng rồi mới nhảy sang
# font thật, thấy giật. Đồng bộ thì không có cửa sổ trắng lúc nạp.
if [ -f "$HOME/.Xresources" ]; then
    if have xrdb; then
        xrdb -merge "$HOME/.Xresources" 2>/dev/null || warn "xrdb -merge thất bại"
    else
        warn "thiếu xorg-xrdb — ~/.Xresources không được nạp"
    fi
fi

WALLPAPER=$(cat "$TSUKI_DIR/scripts/.wallpaper" 2>/dev/null)
_needs_wallpaper_msg=0
if [ -n "${WALLPAPER:-}" ] && [ -f "$WALLPAPER" ]; then
    feh --no-fehbg --bg-fill "$WALLPAPER" &
elif [ -f "$HOME/Pictures/Wallpapers/japanese.jpg" ]; then
    feh --no-fehbg --bg-fill "$HOME/Pictures/Wallpapers/japanese.jpg" &
else
    # Không có ảnh nào: vẽ nền đen bằng feh thay vì để X màu xám xịt.
    feh --no-fehbg --bg-solid '#1a1a1a' &
    # KHÔNG gọi notify-send ở đây. Bản cũ gọi ngay tại chỗ này, tức là TRƯỚC
    # khi dunst được khởi động (dunst chạy ở khối "thông báo + portal" phía
    # dưới) -> không ai nhận org.freedesktop.Notifications -> thông báo mất
    # im lặng. Đặt cờ, phát sau khi dunst sẵn sàng.
    _needs_wallpaper_msg=1
fi

# `xset r rate` đặt tốc độ lặp phím. Không có `&`: xrdb/`xset` chạy nhanh,
# chạy đồng bộ để không tranh X server với phần cursor phía dưới, và để lỗi
# (thiếu xorg-xset) được ghi vào nhật ký thay vì biến mất trong /dev/null.
if have xset; then
    xset r rate 200 50 2>/dev/null || warn "xset r rate thất bại — tốc độ lặp phím không đổi"

    # TẮT SCREEN SAVER + DPMS CỦA CHÍNH X SERVER.
    #
    # Đo trên máy thật trước khi sửa:
    #     Screen Saver:  timeout: 600  cycle: 600
    #     DPMS:          Standby 600  Suspend 600  Off 600  — DPMS is Enabled
    #
    # Nghĩa là rời chuột 10 phút là màn hình trắng, rồi monitor ngủ. Trên X
    # thuần KHÔNG có idle daemon nào cấu hình được, nên không tắt thì người
    # dùng bị màn hình trắng mà không có cách nào đổi. Tệ hơn: nó quay lại
    # KHÔNG khoá — Tsuki chỉ khoá bằng Super+Delete, không có tự khoá.
    #
    # Mặc định tắt, khớp với việc máy là desktop không có pin (không cần quản
    # lý năng lượng). Muốn bật lại thì đặt TSUKI_SCREENSAVER=off/trước startx:
    #     TSUKI_SCREENSAVER=600  -> blank sau 600s, tắt DPMS
    #     TSUKI_SCREENSAVER=off  -> không blank (mặc định)
    #     TSUKI_SCREENSAVER=keep -> giữ nguyên cấu hình X server
    _ss=${TSUKI_SCREENSAVER:-off}
    case $_ss in
        off)
            xset s off 2>/dev/null || warn "xset s off thất bại"
            xset -dpms 2>/dev/null || warn "xset -dpms thất bại"
            info "screensaver + DPMS: tắt (đặt TSUKI_SCREENSAVER=600 để bật lại)"
            ;;
        keep)
            info "screensaver + DPMS: giữ nguyên cấu hình X server"
            ;;
        ''|*[!0-9]*)
            warn "TSUKI_SCREENSAVER='$_ss' không hợp lệ — dùng off (off | 600 | keep)"
            xset s off 2>/dev/null; xset -dpms 2>/dev/null
            ;;
        *)
            xset s "$_ss" 2>/dev/null || warn "xset s $_ss thất bại"
            xset s noexpose 2>/dev/null || true
            xset -dpms 2>/dev/null || warn "xset -dpms thất bại"
            info "screensaver: $_ss giây, DPMS tắt"
            ;;
    esac
else
    warn "thiếu xorg-xset — bỏ qua tốc độ lặp phím"
fi
# Qua start_daemon chứ không phải `picom &`: bản cũ không khoá, nên chạy
# run.sh lần thứ hai (rebuild, hoặc ai đó chạy tay) sẽ sinh picom thứ hai —
# hai picom tranh cùng X server, hiệu năng tệ và log đầy lỗi. Giờ có khoá
# nên lần sau bỏ qua, và watchdog hồi sinh được nếu nó chết.
have picom && start_daemon picom picom

# --- cursor: Bibata Modern Ice -----------------------------------------------
# X11 không có khái niệm "cursor theme" sẵn như GNOME/KDE. Xcursor spec quy định
# theme chỉ được dùng khi ẢNH CỦA NÓ được nạp vào CORE CURSOR FONT của X
# server, và đó là việc của ứng dụng (libXcursor), không phải của window manager.
# Vì vậy có 3 tầng, tầng nào cũng cần thiết cho một nhóm app khác nhau:
#
#   1) ~/.Xresources (Xcursor/Xcursor.size) + .config/gtk-3.0/settings.ini
#      -> app GTK3 (Firefox, Thunar, hộp thoại...). Không cần gì thêm.
#      settings.ini là tầng quan trọng nhất và chạy được ngay.
#
#   2) `xsetroot -xcf <file> <size>` ở đây -> set con trỏ cho ROOT WINDOW, nên
#      mọi cửa sổ KHÔNG tự gọi XDefineCursor sẽ kế thừa: dmenu (dmenu.c không
#      hề set cursor), desktop, app lạ chưa biết theme.
#      LƯU Ý cú pháp: xsetroot 1.1.x KHÔNG có -cursor_size, và -cursor_name
#      nhận TÊN FONT CORE (left_ptr, watch...), KHÔNG phải tên theme — dùng
#      `-cursor_name Bibata-Modern-Ice -cursor_size 24` sẽ báo lỗi. Cách duy
#      nhất xsetroot 1.1.4 nhận theme là -xcf <file .xc> <size>.
#
#   3) dwm và st thì KHÔNG nằm trong 2 tầng trên: cả hai đều tự tạo cursor bằng
#      XCreateFontCursor() (dwm.c -> XDefineCursor cho bar/tab/tag; st/x.c cho vùng
#      text), mà X11 hiện đại ĐÃ BỎ đường nạp theme vào core cursor font. Đo thực
#      tế: sau XcursorImagesLoadCursors() thì số đo font "cursor" của X server y
#      nguyên, nên XCreateFontCursor vẫn trả về bitmap mặc định. Vì vậy
#      drw_cur_load() (drw.c) và load_themed_cursor() (st/x.c) tự đọc file
#      <theme>/cursors/<tên> theo Xresources "Xcursor" rồi tạo cursor riêng cho
#      dwm và st. Không có hai hàm đó thì đây là 2 mũi tên xám giữa desktop đã
#      theme — cùng kiểu "cài xong nhìn không thấy gì đổi".
CURSOR_THEME=Bibata-Modern-Ice
CURSOR_SIZE=24
# Ưu tiên bản hệ thống (libXcursor chỉ tìm /usr/share/icons); bản ~/.local/share
# chỉ để dự phòng cho -xcf vì ở đó -xcf vẫn đọc được file theo đường dẫn tuyệt đối.
CURSOR_DIR=""
for d in "/usr/share/icons/$CURSOR_THEME/cursors" \
         "$HOME/.local/share/icons/$CURSOR_THEME/cursors"; do
    [ -r "$d/default" ] && { CURSOR_DIR="$d"; break; }
done
if [ -n "$CURSOR_DIR" ] && command -v xsetroot >/dev/null 2>&1; then
    xsetroot -xcf "$CURSOR_DIR/default" "$CURSOR_SIZE" 2>/dev/null || \
        warn_cursor "xsetroot -xcf thất bại"
else
    if [ -z "$CURSOR_DIR" ]; then
        warn_cursor "chưa cài theme cursor '$CURSOR_THEME' — chạy ./install.sh deps"
    else
        warn_cursor "thiếu xorg-xsetroot — chạy ./install.sh deps"
    fi
fi

# --- thông báo + portal ------------------------------------------------------
#
# Cả hai đều BẮT BUỘC cho hai thứ hay vấn đề nhất trên rice:
#   1. OSD/phím volume — gọi dunstify -> cần org.freedesktop.Notifications.
#      Không có dunst thì phím volume vẫn đổi âm lượng nhưng không hiện gì.
#   2. "Lưu ảnh" của Firefox — GTK4 dùng xdg-desktop-portal FileChooser.
#      Không có portal-gtk thì app nhận lệnh nhưng không dựng được cửa sổ.
#
# `systemctl --user start` (không phải chạy tay) để dunst đi đúng con đường
# D-Bus mà app gọi tới.
#
# NHƯNG `systemctl --user` chỉ chạy được khi có systemd user manager. Phiên
# startx từ TTY không đi qua logind nên thường KHÔNG có user bus -> mọi lệnh
# dưới đây im lặng thất bại, dunst không chạy, phím volume không hiện OSD,
# hộp thoại "Lưu ảnh" của Firefox không dựng được. Trước đây lỗi này hoàn
# toàn im lặng vì có `2>/dev/null || true`.
#
# Nên: thử systemd trước, thấy không có thì chạy binary tay. Cả hai đều đi
# qua cùng session bus nên app vẫn tìm thấy.
_have_user_bus=0
if have systemctl && systemctl --user is-system-running >/dev/null 2>&1; then
    _have_user_bus=1
fi
# `is-system-running` trả "degraded" cũng là bus dùng được; nên thử thêm
# một cách trực tiếp: busctl có nói chuyện được không.
[ "$_have_user_bus" = 0 ] && have busctl && \
    busctl --user list >/dev/null 2>&1 && _have_user_bus=1

if [ "$_have_user_bus" = 1 ]; then
    systemctl --user import-environment DISPLAY XAUTHORITY 2>/dev/null || true
    systemctl --user start xdg-desktop-portal.service \
                        xdg-desktop-portal-gtk.service 2>/dev/null || true
    systemctl --user start dunst.service 2>/dev/null || true
    info "dunst/portal: qua systemd --user"
else
    warn "không có systemd user bus — chạy dunst/portal trực tiếp"
    have dunst && start_daemon dunst dunst
    for _p in /usr/libexec/xdg-desktop-portal /usr/lib/xdg-desktop-portal; do
        [ -x "$_p" ] && { start_daemon portal "$_p"; break; }
    done
    for _p in /usr/libexec/xdg-desktop-portal-gtk \
             /usr/lib/xdg-desktop-portal-gtk; do
        [ -x "$_p" ] && { start_daemon portal-gtk "$_p"; break; }
    done
fi

# Thông báo tường trễ: chỉ gửi được SAU khi dunst đã có mặt trên bus. Xem
# khối wallpaper — thông báo "chưa có ảnh nền" bản cũ gửi trước khi dunst
# chạy nên mất im lặng.
if [ "${_needs_wallpaper_msg:-0}" = 1 ] && have notify-send; then
    ( _i=0
      while [ $_i -lt 20 ] && ! busctl --user list 2>/dev/null | grep -q org.freedesktop.Notifications; do
          sleep 0.25; _i=$((_i + 1))
      done
      notify-send "tsuki" "Chưa có ảnh nền — đặt ảnh vào scripts/.wallpaper" 2>/dev/null || : ) &
fi

# polkit-gnome authentication agent (cần cho popup mật khẩu của pkexec/sudo)
if [ -x /usr/lib/polkit-gnome/polkit-gnome-authentication-agent-1 ]; then
    start_daemon polkit \
        /usr/lib/polkit-gnome/polkit-gnome-authentication-agent-1
else
    have pkexec && warn "thiếu polkit-gnome — sudo/pkexec sẽ không có hộp thoại"
fi

# --- fcitx5 -----------------------------------------------------------------
# 5 biến, khớp với khối `if status is-login` trong .config/fish/config.fish.
# Thiếu SDL và GLFW thì app SDL/GLFW (game, mpv, ...) chạy từ dwm không gõ
# được — biến trong config.fish chỉ có tác dụng với shell fish, app được
# dwm spawn thì kế thừa môi trường ở đây chứ không qua config.fish.
# GLFW_IM_MODULE=ibus là cố ý: fcitx5 có frontend tương thích ibus cho app
# GLFW, đặt "fcitx" sẽ làm chúng không gõ được.
export GTK_IM_MODULE=fcitx
export QT_IM_MODULE=fcitx
export XMODIFIERS=@im=fcitx
export SDL_IM_MODULE=fcitx
export GLFW_IM_MODULE=ibus
command -v fcitx5 >/dev/null 2>&1 && start_daemon fcitx fcitx5 -d

# --- xsettingsd --------------------------------------------------------------
# Daemon XSETTINGS cho app GTK. install.sh cài gói + repo có sẵn
# .config/xsettingsd/xsettingsd.conf, nhưng trước đây KHÔNG ai khởi động nó,
# nên cả file config là cấu hình chết.
#
# start_daemon tự kiểm tra pidfile nên login lần sau không spawn trùng. Cần
# `systemctl --user import-environment` (đã gọi ở trên) để nó thấy DISPLAY —
# không thì nó chết ngay với "Cannot open X11 display".
#
# KHÔNG kỳ vọng daemon này đổi con trỏ của dwm/st: xsettingsd không hỗ trợ
# cursor theme, và X11 không còn đường nạp theme vào core cursor font. Chi tiết
# ở .config/xsettingsd/xsettingsd.conf và ở khối cursor phía trên.
command -v xsettingsd >/dev/null 2>&1 &&
    start_daemon xsettingsd xsettingsd -c "$TSUKI_DIR/.config/xsettingsd/xsettingsd.conf"

# --- status bar -------------------------------------------------------------
# slstatus binary trong repo (dwmwal.sh rebuild + đổi màu theo wallpaper, không
# cần root). Vòng lặp tự phục hồi: nếu slstatus chết/bị kill (vd dwmwal pkill)
# thì restart ngay — bar không bao giờ trống.
SLSTATUS="$TSUKI_DIR/slstatus/slstatus"
[ -x "$SLSTATUS" ] || SLSTATUS="$(command -v slstatus 2>/dev/null || true)"

if [ -n "$SLSTATUS" ]; then
    # Dùng start_daemon + khoá thay vì `( ... ) &` + `echo $!`. Bản cũ ghi
    # pid của SUBSHELL wrapper, không phải của slstatus — nên
    # `kill $(cat tsuki-slstatus.pid)` giết wrapper còn slstatus vẫn chạy, và
    # lần đăng nhập sau thấy pidfile "còn sống" nên không spawn lại.
    start_daemon slstatus dash -c "
        while :; do
            '$SLSTATUS'
            sleep 0.5
        done
    "
else
    warn "không tìm thấy slstatus — thanh trạng thái sẽ trống (chạy ./install.sh build)"
fi

# --- daemon nền -------------------------------------------------------------
# updates-loop.sh tự flock nên gọi lại vô hại; mediacard.sh có chế độ daemon.
[ -f "$TSUKI_DIR/scripts/updates-loop.sh" ] &&
    start_daemon updates dash "$TSUKI_DIR/scripts/updates-loop.sh"
[ -f "$TSUKI_DIR/scripts/mediacard.sh" ] &&
    start_daemon mediacard dash "$TSUKI_DIR/scripts/mediacard.sh" daemon

# --- thumbnail cho trình quản lý file --------------------------------------
# Thunar không tự sinh ảnh nhỏ. Nó hỏi `tumblerd` qua D-Bus theo Thumbnailer
# Specification, tumbler mới gọi plugin (gdk-pixbuf cho ảnh,
# ffmpegthumbnailer cho video, poppler cho PDF) rồi ghi vào
# ~/.cache/thumbnails/ theo freedesktop.org Thumbnail Management Specification.
#
# Tumbler CÓ tự khởi động qua D-Bus activation. Khởi động tay ở đây vì phiên
# này khởi động bằng `startx` từ TTY — không có systemd user session, nên
# activation không luôn bật. start_daemon tự kiểm pidfile, không spawn trùng.
#
# QUAN TRỌNG: binary KHÔNG nằm trong PATH. Gói `tumbler` đặt nó ở
# /usr/lib/tumbler-1/tumblerd, KHÔNG phải /usr/bin/tumblerd. Dùng
# `command -v tumblerd` là luôn false dù đã cài — đã mắc đúng lỗi này, nên
# phải thử cả hai đường dẫn.
_tumblerd=""
if command -v tumblerd >/dev/null 2>&1; then
    _tumblerd=$(command -v tumblerd)
elif [ -x /usr/lib/tumbler-1/tumblerd ]; then
    _tumblerd=/usr/lib/tumbler-1/tumblerd
elif [ -x /usr/libexec/tumblerd ]; then
    _tumblerd=/usr/libexec/tumblerd
fi
[ -n "$_tumblerd" ] && start_daemon tumbler "$_tumblerd"
# Danh sách giám sát. KHÔNG gồm slstatus/updates/mediacard (đã có vòng lặp tự
# phục hồi) và dunst/portal khi đã có systemd user bus (systemd lo).
WATCH_LIST="picom fcitx xsettingsd tumbler polkit"
[ "$_have_user_bus" = 0 ] && WATCH_LIST="$WATCH_LIST dunst portal portal-gtk"
export WATCH_LIST WD_INTERVAL WD_MAX_RETRY

_start_watchdog

# Thư mục cache thumbnail phải có mode 0700 — đúng quy định freedesktop,
# còn Thunar/tumbler tự tạo thì đặt 0755 và bị coi là không hợp lệ.
_thumb_dir="${XDG_CACHE_HOME:-$HOME/.cache}/thumbnails"
mkdir -p "$_thumb_dir" 2>/dev/null && chmod 700 "$_thumb_dir" 2>/dev/null

# --- dwm --------------------------------------------------------------------

# `_font_check` chạy NỀN từ khối danh tính session, nhưng ta `wait` ngay trước
# khi gọi dwm — nên kết quả CHẮC CHẮN có trong nhật ký trước khi dwm chạy.
# Đây KHÔNG phải chẩn đoán bất đồng bộ (đã thử và bỏ vì sinh race), chỉ là
# chồng lấp thời gian chờ với phần khởi động daemon. Đo được ~15ms.
wait "${_FONT_PID:-}" 2>/dev/null || :
# Vòng lặp, không exec. Super+Shift+R -> scripts/rebuild.sh -> killall dwm:
# không có vòng lặp thì dwm chết là X session chết theo, ta bị đá về TTY giữa
# lúc đang code. Có vòng lặp thì binary mới được nạp và bạn không mất context.
#
# exit 0 = người dùng chủ động thoát (Super+Ctrl+Q trong config.h) -> kết thúc
# hẳn session, quay về TTY. Mọi exit code khác (crash, bị signal) -> nạp lại.
#
# VÌ SAO THÊM BACKOFF: bản cũ `sleep 0.3` rồi thử lại vô hạn. Nếu dwm hỏng
# nghiêm trọng — config.h sai cú pháp, thiếu font, X hết chỗ — nó crash ngay
# lập tức, và 3 lần/giây × cả buổi là hàng trăm nghìn lần ghi log, đầy đĩa,
# vẫn không bao giờ lên được. Nay:
#   - crash liên tiếp nhanh (<10s) -> nghỉ tăng dần 0.3 → 0.6 → 1.2 → cap 2s
#   - chạy được >10s rồi mới chết -> coi là bình thường, nghỉ 0.3s như cũ
#   - liên tụp 10 lần mà vẫn không lên -> dừng hẳn, in nguyên nhân
#
# Con số 10 và cap 2s chọn có chủ đích. Cap 5s/ngưỡng 20 như lần đầu thì phải
# chờ ~90 giây mới thấy thông báo — quá lâu cho người dùng đang ngồi nhìn
# màn hình đen. 0.3+0.6+1.2+2×6 = 14.1s thì đủ nhanh mà vẫn chịu được một
# sự cố tạm thời. Nhánh `killall dwm` khi rebuild KHÔNG bị ảnh hưởng: dwm đã
# chạy hàng giờ nên `_ran >= 10` -> nghỉ 0.3s như cũ.
# dwm chạy NỀN + `wait` thay vì foreground. Lý do: POSIX hoãn trap khi shell
# chờ lệnh foreground, mà dwm chạy vô tận — nên `kill -TERM <pid run.sh>`
# không làm gì (đo thật trong sandbox: run.sh sống, dwm sống, trap không chạy).
# Với `wait`, tín hiệu ngắt được `wait`, trap chạy ngay và chuyển tiếp tín
# hiệu cho dwm qua _dwm_forward.
#
# KHÔNG tạo process group mới: shell không có job control nên `&` giữ nguyên
# pgid, SIGHUP khi đóng terminal vẫn tới cả hai. `wait` trả đúng exit status
# của dwm, nên phần dưới y hệt bản foreground — dwm chết non-zero (bị SIGTERM
# từ rebuild.sh, hoặc crash) là nạp lại, dwm trả 0 là kết thúc session.
_crash_count=0
while type dwm >/dev/null 2>&1; do
    _t0=$(date +%s 2>/dev/null || echo 0)
    # stderr của dwm vào file riêng, rồi đưa vào nhật ký VÀ terminal khi dwm
    # thoát. Vì sao không cho thẳng ra terminal như bản cũ: nguyên nhân chết
    # của dwm ("no fonts could be loaded.") là thứ duy nhất giúp tra, mà bản
    # cũ chỉ in ra màn hình đen rồi mất — nhật ký chỉ còn "dwm crash lần N".
    #
    # NHƯNG CHỈ BÁO KHI DWM CHẾT SỚP. `dwm 2>file` bắt stderr của dwm, và MỌI
    # APP DWM MỞ ĐỀU KẾ THỪA fd đó — nên sau vài giây file đầy của thứ khác:
    #   erresc: unknown csi ESC[>0q        <- terminal escape cua st/kitty
    #   (node:...) DeprecationWarning       <- Electron cua Discord
    #   ATTENTION: mesa_glthread            <- GL cua app do dwm mo
    #   Gtk: gtk_widget_add_accelerator     <- GTK cua Discord
    # Do tren may that: mot lan `Super+Shift+R` (dwm chay 81s roi chet 143) ghi
    # 54 dong nhan "dwm:" — KHONG DONG NAO la cua dwm. Nhiieu hon ca loi can
    # tra, va giong het thu la loi cua app, tieu tan dung thu ma nhieu nhat.
    #
    # Ly do chi bao khi chet som: chan doan CUA DWM (die() khi khong nap duoc
    # font, khong mo duoc display) xay ra trong vai mili giay dau. dwm song
    # >10s roi moi chet thi phan lon noi dung file la cua app con.
    _dwm_err="$XDG_RUNTIME_DIR/tsuki-dwm.err"
    safe_touch "$_dwm_err" || true
    dwm 2>"$_dwm_err" &
    _dwm_pid=$!
    wait "$_dwm_pid"
    _rc=$?
    _dwm_pid=""

    if [ "$_rc" -eq 0 ]; then
        info "dwm thoát bình thường (exit 0) — kết thúc session"
        stop_daemons
        exit 0
    fi

    _t1=$(date +%s 2>/dev/null || echo 0)
    _ran=$(( _t1 - _t0 ))

    # Chỉ đưa stderr đã bắt vào nhật ký khi dwm chết SỚP — lúc đó nó gần như
    # chắc là của dwm, vì app con chưa kịp mở ra ghi gì. Xem giải thích dài ở
    # khối `dwm 2>$_dwm_err` phía trên.
    if [ "$_ran" -lt 10 ] && [ -s "$_dwm_err" ]; then
        while IFS= read -r _l; do
            printf 'dwm: %s\n' "$_l" >&2
            log "dwm: $_l"
        done <"$_dwm_err"
    fi
    safe_touch "$_dwm_err" || true

    if [ "$_ran" -ge 10 ]; then
        _crash_count=0            # đã chạy tốt rồi mới chết -> không phải lỗi cấu hình
        _delay=0.3
        info "dwm chết sau ${_ran}s (exit $_rc) — nạp lại"
    else
        _crash_count=$((_crash_count + 1))
        _delay=$(awk -v n="$_crash_count" -v t=0.3 'BEGIN{
            d = t; for (i = 1; i < n; i++) { d *= 2; if (d > 2) { d = 2; break } }
            printf "%.1f", d }')
        log "dwm crash lần $_crash_count sau ${_ran}s (exit $_rc), nghỉ ${_delay}s"
    fi

    if [ "$_crash_count" -ge 10 ]; then
        fail "dwm crash liên tục $_crash_count lần, không dậy nổi — DỪNG"
        fail "Nhật ký phiên: $TSUKI_LOG"
        fail "Nếu vừa sửa config.h: git restore config.h && make && sudo make install"
        fail "Nếu chưa build lần nào:    ./install.sh build"
        stop_daemons
        exit 1
    fi
    sleep "$_delay" 2>/dev/null || sleep 1
done

# Không có `dwm` trong PATH: binary chưa build hoặc startx không nạp profile.
fail "không tìm thấy 'dwm' trong PATH — chạy ./install.sh build"
stop_daemons
exit 127

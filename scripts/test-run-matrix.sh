#!/usr/bin/env dash
# Quét ma trận môi trường cho scripts/run.sh.
#
# T19 trong test-run-session.sh chỉ chạy MỘT phiên theo đường thẳng, nên nó
# chỉ bắt được lỗi `set -u` ở những dòng thật sự chạy tới. Đã chứng minh điều
# này bằng chứng cứ: bỏ config.h đi thì dòng lỗi trong khối font không chạy
# tới, T19 xanh trong khi T16 vẫn đỏ.
#
# File này chạy run.sh thật dưới nhiều hình thế môi trường khác nhau để ép hết
# nhánh: không có XDG_RUNTIME_DIR, /run/user không tồn tại, không D-Bus, không
# systemd user bus, không config.h, không .Xresources, không ảnh nền, HOME
# không ghi được, thiếu mọi lệnh X, thiếu từng daemon, font không tồn tại...
#
# Mỗi hình thế phải thỏa cả hai:
#   1) KHÔNG có lỗi shell nào (unbound variable, syntax error, command not
#      found, permission denied, bad substitution)
#   2) run.sh phải đi tới dwm — tức không chết sớm ở giữa chừng
set -u
R=/home/frost-auslese/tsuki
T=$(mktemp -d)
P=0; F=0
ok()  { printf '  PASS  %s\n' "$*"; P=$((P+1)); }
bad() { printf '  FAIL  %s\n        %s\n' "$*"; F=$((F+1)); }
# canh bao: bo qua mot kiem tra vi dieu kien moi truong khong cho phep.
# KHONG tinh vao P/F — bo qua khong phai that bai, nhung cung khong phai pass.
# Chi dung khi thu tuc that su khong chay duoc; im lang bo qua moi la rui ro.
warn() { printf '  SKIP  %s\n' "$*"; }
cleanup() {
    for p in $(cat "$T"/run*/tsuki-*.pid 2>/dev/null); do kill "$p" 2>/dev/null; done
    rm -rf "$T"
}
trap cleanup EXIT INT TERM

# --- sandbox dùng chung ------------------------------------------------------
# dwm giả: ghi ra file để biết chắc run.sh đã gọi tới dwm, rồi exit 0.
cat > "$T/dwm" <<'EOF'
#!/bin/sh
echo ran >> "$DWM_MARK"
exit 0
EOF
chmod +x "$T/dwm"

# CORE — LUÔN dùng bản thật, KHÔNG BAO GIỜ stub.
# run.sh cần các lệnh cơ sở này để tự dựng (mkdir thư mục khoá, chmod file,
# awk tính backoff, đọc /proc...). Stub chúng thì chính phần run.sh đang kiểm
# bị hỏng và KẾT QUẢ MẤU ĐÁNG GIÁ.
#
# Đã mắc đúng lỗi này: `mkdir` nằm trong danh sách stub, nên `mkdir -p` LUÔN
# trả 0. Nhánh fallback của nơi ghi nhật ký vì thế không bao giờ kích hoạt, và
# ca "cache không ghi được" pass vì LÝ DO SAI — ta tưởng fallback hoạt động
# trong khi thực ra stub đã nuốt lỗi. Đó là bài học: đừng stub thứ mà chính
# kịch bản đang kiểm dùng tới.
CORE_BINS="awk sed grep tr cat sleep date stat mkdir rm chmod kill head cut
ln cp mv touch find sort wc env id dirname basename expr test true false"

# OPTIONAL — stub thành no-op khi không nằm trong danh sách "giữ lại".
# Đây mới là thứ ta thật sự muốn tắt: lệnh X, daemon, trình hỗ trợ.
# Mọi DAEMON thật phải nằm đây để bị stub. Thiếu `fcitx5` một lần đã làm
# sandbox gọi fcitx5 thật, sinh 596 tiến trình mồ côi trên máy thật (6.2 GB
# PSS) vì cleanup chỉ kill pid trong pidfile mà pidfile trỏ launcher đã chết.
OPTIONAL_BINS="feh picom xset xsetroot xrdb notify-send dunst flock fc-match fc-list
fuser dbus-run-session busctl systemctl playerctl pactl wpctl xrandr xprop
fcitx5 xsettingsd tumblerd slstatus polkit-gnome-authentication-agent-1
xdg-desktop-portal xdg-desktop-portal-gtk"

# xây một bộ stub tùy biến: $1 = danh sách lệnh cần CÓ (thật hoặc stub no-op)
# $1 = thư mục ĐÍCH, $2 = danh sách lệnh cần CÓ.
#
# TRƯỚC ĐÂY mk_bin ghi vào $T/bin còn run_case trỏ PATH tới $_dir/bin — thư mục
# không tồn tại. Nghĩa là KHÔNG stub nào có tác dụng: mọi ca "tắt lệnh" đều
# chạy binary thật, và ca "fc-match im lặng" hoàn toàn rỗng — nó xanh vì
# fc-match thật trả về family đúng, chứ không phải vì run.sh bỏ qua.
mk_bin() {
    _dest=$1
    _keep=$2
    rm -rf "$_dest"; mkdir -p "$_dest"
    cp "$T/dwm" "$_dest/dwm"
    for c in $CORE_BINS; do
        ln -sf "$(command -v "$c" 2>/dev/null || echo /bin/false)" "$_dest/$c" 2>/dev/null
    done
    for c in $OPTIONAL_BINS; do
        case " $_keep " in
            *" $c "*) ln -sf "$(command -v "$c" 2>/dev/null || echo /bin/false)" "$_dest/$c" 2>/dev/null ;;
            *) printf '#!/bin/sh\nexit 0\n' > "$_dest/$c"; chmod +x "$_dest/$c" ;;
        esac
    done
    ln -sf "$(command -v dash)" "$_dest/sh" 2>/dev/null

    # PHẢI có: stub `id -u` trả uid giả. run.sh rơi về "/run/user/$(id -u)"
    # khi XDG_RUNTIME_DIR rỗng hoặc hỏng (dòng 334 của run.sh). Case
    # "khong-XDG_RT" và "khong-moi-X" cố tình đặt XDG_RUNTIME_DIR= rỗng nên
    # chúng chạy ĐÚNG nhánh đó — mà /run/user/1000 là thư mục THẬT của phiên
    # đang chạy.
    #
    # Hậu quả đo được lúc 00:13: bộ test xoá tsuki-*.lock + tsuki-*.pid thật
    # rồi kill daemon thật. Watchdog thấy khoá biến mất nên hồi sinh: picom
    # 2901->386318, tumbler 3254->387427, polkit chết hẳn (đạt trần 5 lần),
    # và session.log của phiên thật bị ghi đè.
    #
    # `id` chỉ dùng ở 4 chỗ trong run.sh, đều là `$(id -u)` để đặt tên thư mục
    # -> đổi uid không phá logic nào, và nhánh fallback VẪN ĐƯỢC KIỂM ĐÚNG:
    # /run/user/4242 không tồn tại nên run.sh phải rơi tiếp sang
    # $TMPDIR/tsuki-4242. Cách này an toàn cho MỌI case, kể cả case viết sau.
    # PHẢI gỡ symlink trước. `id` nằm trong CORE_BINS nên vòng lặp ln -sf phía
    # trên đã tạo symlink $_dest/id -> /usr/bin/id. `cat > $_dest/id` sau đó
    # GHI XUYÊN QUA SYMLINK, tức mở /usr/bin/id để ghi đè. Lần đầu chỉ sống
    # sót vì /usr/bin/id thuộc root (EACCES, không truncate) — nếu binary đó
    # thuộc user, hoặc user chạy test bằng quyền ghi lên đó, test sẽ phá hệ
    # thống. Đây là bẫy "ghi vào đường dẫn có thể là symlink"; mọi stub viết
    # bằng `cat >` trong file này đều phải rm -f trước.
    rm -f "$_dest/id"
    cat > "$_dest/id" <<'IDSTUB'
#!/bin/sh
# uid gia: /run/user/4242 khong ton tai -> run.sh rut sang $TMPDIR
for a in "$@"; do
    case "$a" in
        -u|-ru|--user) echo 4242; exit 0 ;;
    esac
done
exec /usr/bin/id "$@"
IDSTUB
    chmod +x "$_dest/id"
}

# chạy một hình thế. $1 = nhãn, $2 = danh sách lệnh có, $3 = tên biến env cần
# đặt thêm (dạng "TÊN=giá_trị TÊN2=giá_trị2"), $4 = "co" nếu cần tạo config.h
run_case() {
    _label=$1; _bins=$2; _env=${3:-}; _cfg=${4:-co}
    _dir="$T/case$(printf '%s' "$_label" | tr -cd 'a-z0-9' | cut -c1-24)"
    mkdir -p "$_dir/run" "$_dir/home"
    mk_bin "$_dir/bin" "$_bins"

    # repo gia: scripts tro ve repo that, con lai rong
    mkdir -p "$_dir/repo/.config/xsettingsd"
    ln -sfn "$R/scripts" "$_dir/repo/scripts"
    cp "$T/dwm" "$_dir/repo/dwm"; chmod +x "$_dir/repo/dwm"
    : > "$_dir/repo/.config/xsettingsd/xsettingsd.conf"
    [ "$_cfg" = co ] && cp "$R/config.h" "$_dir/repo/config.h"

    _ex="$T/dwm.mark"
    : > "$_ex"
    _log="$_dir/home/.cache/tsuki/session.log"
    _err="$_dir/stderr.txt"

    # bien moi truong: tach cap "TÊN=giá_trị" theo dau cach
    _oldifs=$IFS; IFS=' '
    set -f
    # shellcheck disable=SC2086
    env -i \
        PATH="$_dir/bin:/usr/bin:/bin" \
        HOME="$_dir/home" \
        XDG_RUNTIME_DIR="$_dir/run" \
        XDG_CACHE_HOME="$_dir/home/.cache" \
        TSUKI_DIR="$_dir/repo" \
        DWM_MARK="$_ex" \
        $_env \
        dash "$R/scripts/run.sh" >/dev/null 2>"$_err"
    _rc=$?
    set +f
    IFS=$_oldifs

    # 1) loi shell
    _bad=""
    for _p in 'unbound variable' 'syntax error' 'parameter not set' \
              'command not found' 'bad substitution' 'Permission denied' \
              'integer expression' 'unary operator'; do
        if grep -q "$_p" "$_err" 2>/dev/null; then
            _bad="$_bad  [$_p] $(grep -m1 "$_p" "$_err" 2>/dev/null | tr -d '\n')
"
        fi
    done
    if [ -n "$_bad" ]; then
        bad "$_label" "$_bad"
    elif [ ! -s "$_ex" ]; then
        bad "$_label" "run.sh chết trước khi tới dwm (rc=$_rc): $(tail -2 "$_err" 2>/dev/null | tr '\n' ';')"
    else
        ok "$_label (rc=$_rc, dwm đã chạy)"
    fi
}

ALL="feh picom xset xsetroot xrdb notify-send dunst flock fc-match fuser"

echo "--- môi trường bình thường, lần lượt tắt từng thứ ---"
run_case "day-du"            "$ALL"
run_case "khong-DBUS"        "$ALL" "DBUS_SESSION_BUS_ADDRESS="
run_case "khong-XDG_RT"      "$ALL" "XDG_RUNTIME_DIR="
run_case "XDG-RT-hong"       "$ALL" "XDG_RUNTIME_DIR=/khong/ton/tai/xyz"
run_case "khong-LANG"        "$ALL" "LANG= LC_ALL= LC_CTYPE="
run_case "co-DWM_DIR"        "$ALL" "DWM_DIR=/tam/gi"
run_case "khong-ConfigH"     "$ALL" "" "khong"
run_case "khong-Xresources"  "$ALL" "HOME=$T/rong"
run_case "khong-cache"       "$ALL" "XDG_CACHE_HOME=/proc/khong/ghi"
run_case "khong-moi-X"       "flock fc-match fuser" "XDG_RUNTIME_DIR="
run_case "khong-feh-picom"   "xset xsetroot xrdb flock fc-match fuser"
run_case "chi-flock"         "flock"

echo
echo "--- /run/user không tồn tại: ép fallback sang \$TMPDIR ---"
mkdir -p "$T/tmproot"
run_case "run-user-hong"     "$ALL" "XDG_RUNTIME_DIR=/khong/ton/tai/xyz TMPDIR=$T/tmproot"

echo
echo "--- hồi quy: XDG_RUNTIME_DIR rỗng KHÔNG được chạm vào thư mục thật ---"
# ĐÂY LÀ BẢO VỆ CHỐNG BỘ TEST TỰ PHÁ PHIÊN NGƯỜI DÙNG.
#
# run.sh rơi về "/run/user/$(id -u)" khi XDG_RUNTIME_DIR rỗng/hỏng (dòng 334).
# Case "khong-XDG_RT" và "khong-moi-X" cố tình đặt nó rỗng, tức chạy đúng nhánh
# đó — và nếu `id` thật, nhánh đó trỏ vào /run/user/1000: thư mục thật của phiên
# đang chạy. stop_daemons() có `rm -f "$XDG_RUNTIME_DIR"/tsuki-*.lock` và
# `tsuki-*.pid` rồi kill các pid ghi trong đó.
#
# Đã xảy ra thật lúc 00:13 ngày 01/10: bộ test xoá khoá/pid thật, kill daemon
# thật; watchdog thấy khoá biến mất nên hồi sinh (picom 2901->386318, tumbler
# 3254->387427, polkit chết hẳn sau 5 lần thử), session.log bị ghi đè.
#
# Cách kiểm: canary tên đúng dạng glob của stop_daemons (tsuki-*.lock). Nếu test
# chạm vào thư mục thật, canary bị xoá -> đỏ. Không cần đoán, không phụ thuộc
# thứ tự, không đụng daemon nào đang sống.
_REAL_RT=${XDG_RUNTIME_DIR:-}
if [ -z "$_REAL_RT" ] || [ ! -d "$_REAL_RT" ]; then
    warn "canary-XDG-RT thư mục runtime thật không xác định — BỎ QUA"
else
    _canary="$_REAL_RT/tsuki-canary.lock"
    if [ -e "$_canary" ]; then
        warn "canary-XDG-RT đã có $(), bỏ qua để không đụng file thật"
        warn "canary-XDG-RT thư mục thật: $_REAL_RT"
    else
        : > "$_canary" 2>/dev/null
        _cok=1
        [ -e "$_canary" ] || _cok=0
        if [ "$_cok" = 1 ]; then
            # chạy lại đúng case nguy hiểm, lần này có canary canh
            run_case "canary-XDG-RT" "$ALL" "XDG_RUNTIME_DIR=" >/dev/null 2>&1
            if [ -e "$_canary" ]; then
                ok "canary-XDG-RT: XDG_RUNTIME_DIR rỗng KHÔNG chạm thư mục thật"
            else
                bad "canary-XDG-RT" "canary $_canary bị XOÁ — test đã ghi vào $_REAL_RT (thư mục thật của phiên đang chạy)"
                bad "canary-XDG-RT" "nguyên nhân: run.sh dòng 334 rơi về /run/user/\$(id -u); stub 'id -u' trong mk_bin chưa được áp dụng"
            fi
        else
            warn "canary-XDG-RT không tạo được canary trong $_REAL_RT — BỎ QUA"
        fi
        rm -f "$_canary" 2>/dev/null
    fi
fi

echo
echo "--- config.h trỏ font không tồn tại (dwm chết ngay) ---"
_fdir="$T/case-font"
mkdir -p "$_fdir/run" "$_fdir/home" "$_fdir/repo/.config/xsettingsd"
mk_bin "$_fdir/bin" "$ALL fc-list"
ln -sfn "$R/scripts" "$_fdir/repo/scripts"
cp "$T/dwm" "$_fdir/repo/dwm"; chmod +x "$_fdir/repo/dwm"
: > "$_fdir/repo/.config/xsettingsd/xsettingsd.conf"
sed 's/"Iosevka:style:medium:size=12"/"TsukiKhongTonTai:style=medium:size=12"/' \
    "$R/config.h" > "$_fdir/repo/config.h"
: > "$_fdir/mark"
env -i PATH="$_fdir/bin:/usr/bin:/bin" HOME="$_fdir/home" \
    XDG_RUNTIME_DIR="$_fdir/run" XDG_CACHE_HOME="$_fdir/home/.cache" \
    TSUKI_DIR="$_fdir/repo" DWM_MARK="$_fdir/mark" \
    dash "$R/scripts/run.sh" >/dev/null 2>"$_fdir/err"
if grep -qE 'unbound variable|syntax error|command not found' "$_fdir/err" 2>/dev/null; then
    bad "font-khong-ton-tai" "$(grep -m1 -E 'unbound|syntax|not found' "$_fdir/err")"
elif grep -q 'SẼ CHẾT NGAY' "$_fdir/home/.cache/tsuki/session.log" 2>/dev/null; then
    ok "font-khong-ton-tai (báo trước, không lỗi shell)"
else
    bad "font-khong-ton-tai" "không báo trước, log: $(tail -3 "$_fdir/home/.cache/tsuki/session.log" 2>/dev/null | tr '\n' ';')"
fi

echo
echo "--- hồi quy: fc-list im lặng KHÔNG được báo font thiếu ---"
# Bản trước coi fc-match trả về RỖNG là "lệch" -> báo "SẼ CHẾT NGAY" cho font
# hoàn toàn bình thường. Đó là báo động giả, tệ hơn sót: nó bảo người dùng cài
# gói họ đã có. Rỗng xảy ra khi cache fontconfig hỏng hoặc fc-match bị giới hạn.
_rd="$T/casefc"
mkdir -p "$_rd/run" "$_rd/home" "$_rd/repo/.config/xsettingsd"
mk_bin "$_rd/bin" "$ALL"
ln -sfn "$R/scripts" "$_rd/repo/scripts"
cp "$T/dwm" "$_rd/repo/dwm"; chmod +x "$_rd/repo/dwm"
: > "$_rd/repo/.config/xsettingsd/xsettingsd.conf"
cp "$R/config.h" "$_rd/repo/config.h"          # font THẬT, hoàn toàn bình thường
# PHẢI stub `fc-list`, KHÔNG PHẢI `fc-match`. run.sh từng hỏi `fc-match` từng
# font; khi tối ưu hiệu năng đã đổi sang MỘT lần `fc-list` rồi so trong awk.
# Test vẫn stub `fc-match` nên trở nên RỖNG — nó xanh vì `fc-list` thật trả về
# family đúng, chứ không phải vì run.sh bỏ qua. Đã mắc đúng lỗi trôi này.
rm -f "$_rd/bin/fc-list"    # mk_bin để symlink tới fc-list thật; phải xoá trước
printf '#!/bin/sh\nexit 0\n' > "$_rd/bin/fc-list"
chmod +x "$_rd/bin/fc-list"
: > "$_rd/mark"
env -i PATH="$_rd/bin:/usr/bin:/bin" HOME="$_rd/home" \
    XDG_RUNTIME_DIR="$_rd/run" XDG_CACHE_HOME="$_rd/home/.cache" \
    TSUKI_DIR="$_rd/repo" DWM_MARK="$_rd/mark" \
    dash "$R/scripts/run.sh" >/dev/null 2>"$_rd/err"
if grep -q 'SẼ CHẾT NGAY' "$_rd/home/.cache/tsuki/session.log" 2>/dev/null; then
    bad "fc-list-im-lang" "báo SẼ CHẾT NGAY cho font thật — báo động giả"
else
    ok "fc-list im lặng: không báo động giả (bỏ qua thay vì đoán sai)"
fi

echo
echo "--- hồi quy: XDG_CACHE_HOME không ghi được thì phiên vẫn phải lên ---"
# Bản trước đổi TSUKI_LOG_DIR sang $TMPDIR/tsuki-$(id -u) nhưng KHÔNG mkdir
# nhánh đó, nên dòng `: >"$TSUKI_LOG"` ngay sau thất bại:
#     run.sh: 30: cannot create /tmp/tsuki-1000/session.log: Directory nonexistent
# rc=2, chết trước khi làm được gì.
_rc2="$T/casecache"
mkdir -p "$_rc2/run" "$_rc2/home" "$_rc2/repo/.config/xsettingsd" "$T/tmpx"
mk_bin "$_rc2/bin" "$ALL"
ln -sfn "$R/scripts" "$_rc2/repo/scripts"
cp "$T/dwm" "$_rc2/repo/dwm"; chmod +x "$_rc2/repo/dwm"
: > "$_rc2/repo/.config/xsettingsd/xsettingsd.conf"
cp "$R/config.h" "$_rc2/repo/config.h"
: > "$_rc2/mark"
env -i PATH="$_rc2/bin:/usr/bin:/bin" HOME="$_rc2/home" \
    XDG_RUNTIME_DIR="$_rc2/run" XDG_CACHE_HOME=/proc/khong/ghi \
    TSUKI_DIR="$_rc2/repo" DWM_MARK="$_rc2/mark" TMPDIR="$T/tmpx" \
    dash "$R/scripts/run.sh" >/dev/null 2>"$_rc2/err"
if [ -s "$_rc2/mark" ]; then
    ok "cache khong ghi duoc: phiên vẫn lên tới dwm"
else
    bad "cache khong ghi duoc" "dwm khong chay: $(tail -2 "$_rc2/err" 2>/dev/null | tr '\n' ';')"
fi

echo
echo "--- hồi quy: thư mục log tồn tại nhưng KHÔNG ghi được (mode 555) ---"
# Đây mới là ca đúng đắn cho lớp lỗi chuyển hướng chí tử:
#   - `mkdir -p` THÀNH CÔNG (thư mục đã tồn tại) -> không rơi vào fallback
#   - `: >"$TSUKI_LOG"` thất bại vì không có quyền ghi
#   - trong DASH, lỗi chuyển hướng là lỗi chí tử: `|| TSUKI_LOG=/dev/null`
#     KHÔNG BAO GIỜ chạy, shell chết, mất desktop.
# Ca "cache không ghi được" ở trên không bắt được lớp lỗi này, vì ở đó
# `mkdir -p` thất bại nên đã rơi vào fallback thành công.
_rd2="$T/casero"
mkdir -p "$_rd2/run" "$_rd2/home" "$_rd2/repo/.config/xsettingsd"
mkdir -p "$_rd2/cach/tsuki" "$_rd2/tmp/tsuki-$(id -u)"   # tồn tại sẵn
chmod 555 "$_rd2/cach/tsuki" "$_rd2/tmp/tsuki-$(id -u)"  # nhưng không ghi được
mk_bin "$_rd2/bin" "$ALL"
ln -sfn "$R/scripts" "$_rd2/repo/scripts"
cp "$T/dwm" "$_rd2/repo/dwm"; chmod +x "$_rd2/repo/dwm"
: > "$_rd2/repo/.config/xsettingsd/xsettingsd.conf"
cp "$R/config.h" "$_rd2/repo/config.h"
: > "$_rd2/mark"
env -i PATH="$_rd2/bin:/usr/bin:/bin" HOME="$_rd2/home" \
    XDG_RUNTIME_DIR="$_rd2/run" XDG_CACHE_HOME="$_rd2/cach" \
    TSUKI_DIR="$_rd2/repo" DWM_MARK="$_rd2/mark" TMPDIR="$_rd2/tmp" \
    dash "$R/scripts/run.sh" >/dev/null 2>"$_rd2/err"
if [ -s "$_rd2/mark" ]; then
    ok "thu muc log khong ghi duoc: phiên vẫn lên tới dwm"
else
    bad "thu muc log khong ghi duoc" "dwm khong chay: $(tail -2 "$_rd2/err" 2>/dev/null | tr '\n' ';')"
fi
chmod 755 "$_rd2/cach/tsuki" "$_rd2/tmp/tsuki-$(id -u)" 2>/dev/null || true

# --- KHÔNG daemon nào trốn ra khỏi sandbox ----------------------------------
# ĐÃ GÂY RA HẬU QUẢ THẬT: `fcitx5` không nằm trong danh sách stub nên sandbox
# gọi Fcitx5 THẬT. Nó fork, launcher chết, daemon thật thành mồ côi giữ khoá
# trên $T/case*/run/tsuki-fcitx.lock. `cleanup()` chỉ kill pid trong pidfile mà
# pidfile trỏ launcher đã chết. Sau hàng trăm lần chạy: 596 tiến trình mồ
# côi, 6.2 GB PSS trên máy thật. Đã dọn.
#
# Phải kiểm TRƯỚC cleanup, trên các khoá của chính lần chạy này — lọc theo
# "(deleted)" là vô dụng vì dấu đó chỉ hiện ra SAU khi cleanup đã xoá thư mục,
# lúc đó mọi daemon trốn ra đều trông sạch.
_esc=""
# Khớp theo TIỀN TỐ ĐƯỜNG DẪN, không đối chiếu danh sách file khoá. `stop_daemons`
# đã `rm -f` các file khoá, nên `[ -f "$lk" ]` thất bại và vòng lặp bỏ qua hết —
# đó là lý do bản đầu báo PASS trong khi daemon thật đã trốn ra. readlink vẫn
# trả đường dẫn GỐC kèm " (deleted)", nên khớp tiền tố vẫn bắt được.
for _p in $(pgrep -x fcitx5 2>/dev/null; pgrep -x xsettingsd 2>/dev/null; \
            pgrep -x tumblerd 2>/dev/null); do
    for _fd in /proc/$_p/fd/*; do
        _t=$(readlink "$_fd" 2>/dev/null) || continue
        case "$_t" in
            "$T"/*) _esc="$_esc  pid $_p cầm $_t
" ;;
        esac
    done
done
if [ -z "$_esc" ]; then
    ok "không daemon nào trốn ra khỏi sandbox"
else
    bad "daemon trốn ra ngoài sandbox" "$_esc"
fi

printf '\n  %d PASS, %d FAIL\n' "$P" "$F"
[ "$F" -eq 0 ]

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
OPTIONAL_BINS="feh picom xset xsetroot xrdb notify-send dunst flock fc-match fuser
dbus-run-session busctl systemctl playerctl pactl wpctl xrandr xprop"

# xây một bộ stub tùy biến: $1 = danh sách lệnh cần CÓ (thật hoặc stub no-op)
mk_bin() {
    _keep=$1
    rm -rf "$T/bin"; mkdir -p "$T/bin"
    cp "$T/dwm" "$T/bin/dwm"
    for c in $CORE_BINS; do
        ln -sf "$(command -v "$c" 2>/dev/null || echo /bin/false)" "$T/bin/$c" 2>/dev/null
    done
    for c in $OPTIONAL_BINS; do
        case " $_keep " in
            *" $c "*) ln -sf "$(command -v "$c" 2>/dev/null || echo /bin/false)" "$T/bin/$c" 2>/dev/null ;;
            *) printf '#!/bin/sh\nexit 0\n' > "$T/bin/$c"; chmod +x "$T/bin/$c" ;;
        esac
    done
    ln -sf "$(command -v dash)" "$T/bin/sh" 2>/dev/null
}

# chạy một hình thế. $1 = nhãn, $2 = danh sách lệnh có, $3 = tên biến env cần
# đặt thêm (dạng "TÊN=giá_trị TÊN2=giá_trị2"), $4 = "co" nếu cần tạo config.h
run_case() {
    _label=$1; _bins=$2; _env=${3:-}; _cfg=${4:-co}
    _dir="$T/case$(printf '%s' "$_label" | tr -cd 'a-z0-9' | cut -c1-24)"
    mkdir -p "$_dir/run" "$_dir/home"
    mk_bin "$_bins"

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
echo "--- config.h trỏ font không tồn tại (dwm chết ngay) ---"
_fdir="$T/case-font"
mkdir -p "$_fdir/run" "$_fdir/home" "$_fdir/repo/.config/xsettingsd"
mk_bin "$ALL"
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
echo "--- hồi quy: fc-match im lặng KHÔNG được báo font thiếu ---"
# Bản trước coi fc-match trả về RỖNG là "lệch" -> báo "SẼ CHẾT NGAY" cho font
# hoàn toàn bình thường. Đó là báo động giả, tệ hơn sót: nó bảo người dùng cài
# gói họ đã có. Rỗng xảy ra khi cache fontconfig hỏng hoặc fc-match bị giới hạn.
_rd="$T/casefc"
mkdir -p "$_rd/run" "$_rd/home" "$_rd/repo/.config/xsettingsd"
mk_bin "$ALL"
ln -sfn "$R/scripts" "$_rd/repo/scripts"
cp "$T/dwm" "$_rd/repo/dwm"; chmod +x "$_rd/repo/dwm"
: > "$_rd/repo/.config/xsettingsd/xsettingsd.conf"
cp "$R/config.h" "$_rd/repo/config.h"          # font THẬT, hoàn toàn bình thường
rm -f "$T/bin/fc-match"   # mk_bin để symlink tới fc-match thật; phải xoá trước
rm -f "$T/bin/fc-match"   # mk_bin tạo symlink; phải xoá trước khi ghi stub
printf '#!/bin/sh\nexit 0\n' > "$T/bin/fc-match"
chmod +x "$T/bin/fc-match"
: > "$_rd/mark"
env -i PATH="$T/bin:/usr/bin:/bin" HOME="$_rd/home" \
    XDG_RUNTIME_DIR="$_rd/run" XDG_CACHE_HOME="$_rd/home/.cache" \
    TSUKI_DIR="$_rd/repo" DWM_MARK="$_rd/mark" \
    dash "$R/scripts/run.sh" >/dev/null 2>"$_rd/err"
if grep -q 'SẼ CHẾT NGAY' "$_rd/home/.cache/tsuki/session.log" 2>/dev/null; then
    bad "fc-match-im-lang" "báo SẼ CHẾT NGAY cho font thật — báo động giả"
else
    ok "fc-match im lặng: không báo động giả (bỏ qua thay vì đoán sai)"
fi

echo
echo "--- hồi quy: XDG_CACHE_HOME không ghi được thì phiên vẫn phải lên ---"
# Bản trước đổi TSUKI_LOG_DIR sang $TMPDIR/tsuki-$(id -u) nhưng KHÔNG mkdir
# nhánh đó, nên dòng `: >"$TSUKI_LOG"` ngay sau thất bại:
#     run.sh: 30: cannot create /tmp/tsuki-1000/session.log: Directory nonexistent
# rc=2, chết trước khi làm được gì.
_rc2="$T/casecache"
mkdir -p "$_rc2/run" "$_rc2/home" "$_rc2/repo/.config/xsettingsd" "$T/tmpx"
mk_bin "$ALL"
ln -sfn "$R/scripts" "$_rc2/repo/scripts"
cp "$T/dwm" "$_rc2/repo/dwm"; chmod +x "$_rc2/repo/dwm"
: > "$_rc2/repo/.config/xsettingsd/xsettingsd.conf"
cp "$R/config.h" "$_rc2/repo/config.h"
: > "$_rc2/mark"
env -i PATH="$T/bin:/usr/bin:/bin" HOME="$_rc2/home" \
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
mk_bin "$ALL"
ln -sfn "$R/scripts" "$_rd2/repo/scripts"
cp "$T/dwm" "$_rd2/repo/dwm"; chmod +x "$_rd2/repo/dwm"
: > "$_rd2/repo/.config/xsettingsd/xsettingsd.conf"
cp "$R/config.h" "$_rd2/repo/config.h"
: > "$_rd2/mark"
env -i PATH="$T/bin:/usr/bin:/bin" HOME="$_rd2/home" \
    XDG_RUNTIME_DIR="$_rd2/run" XDG_CACHE_HOME="$_rd2/cach" \
    TSUKI_DIR="$_rd2/repo" DWM_MARK="$_rd2/mark" TMPDIR="$_rd2/tmp" \
    dash "$R/scripts/run.sh" >/dev/null 2>"$_rd2/err"
if [ -s "$_rd2/mark" ]; then
    ok "thu muc log khong ghi duoc: phiên vẫn lên tới dwm"
else
    bad "thu muc log khong ghi duoc" "dwm khong chay: $(tail -2 "$_rd2/err" 2>/dev/null | tr '\n' ';')"
fi
chmod 755 "$_rd2/cach/tsuki" "$_rd2/tmp/tsuki-$(id -u)" 2>/dev/null || true

printf '\n  %d PASS, %d FAIL\n' "$P" "$F"
[ "$F" -eq 0 ]

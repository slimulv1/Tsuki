#!/usr/bin/env bash
# Test cho phần TỰ GIẢI THÍCH của install.sh.
#
# VÌ SAO CẦN TEST NÀY. usage() KHÔNG hardcode danh sách lệnh — nó rút từ chính
# khối comment trong file:
#     sed -n '/^#   \.\/install\.sh/,/^#$/p' "${BASH_SOURCE[0]}" | sed 's/^# \?//'
# Nghĩa là help và mã là HAI BẢN SAO CÙNG NGUỒN. Thêm một lệnh con vào case
# mà quên viết vào comment thì lệnh đó chạy được nhưng không ai tìm thấy.
# Bốn lỗ hổng đã đo được trước khi có test này:
#
#   1. `xlibre` (mặc định stable) không có trong help — `xlibre) cmd_xlibre
#      "${2:-stable}"`, tức chạy không tham số là hợp lệ nhưng im lặng.
#   2. Cảnh báo "nâng cấp TOÀN HỆ THỐNG" nằm ngay dưới khối help nhưng bị
#      `^#$` cắt mất — help không in đoạn đó. Đo được:
#      ./install.sh --help | grep -c 'nâng cấp toàn hệ thống'  → 0
#   3. `-h` và `help` chạy được (case `-h|--help|help)`) nhưng không được nhắc.
#   4. Không dòng nào đánh dấu lệnh cần root, dù build ghi /usr/local/bin và
#      xlibre chạy pacman -Syyu.
#
# Test đọc main() thật trong install.sh và help thật từ `./install.sh -h`,
# nên không chép lại logic nào ở đây.
set -u
R=/home/frost-auslese/tsuki
P=0; F=0
ok()  { printf '  PASS  %s\n' "$*"; P=$((P + 1)); }
bad() { printf '  FAIL  %s\n        %s\n' "$*"; F=$((F + 1)); }

bash -n "$R/install.sh" 2>/dev/null || { echo "FAIL: install.sh lỗi cú pháp"; exit 1; }
HELP=$("$R/install.sh" -h 2>/dev/null) || { echo "FAIL: ./install.sh -h không chạy"; exit 1; }

# --- H1: mọi lệnh con trong main() đều phải có trong help ---------------------
# Rút tên lệnh từ case $cmd trong main(): các dòng dạng "  <tên>)".
MAIN=$(sed -n '/^main() {/,/^}/p' "$R/install.sh")
# Bỏ `all`: đó là default của main(), trong help hiện dạng "./install.sh" KHÔNG
# có tham số, nên so `./install.sh all` sẽ luôn trượt. H2 phụ trách việc đó.
# Regex phải khớp `^<cách trắng><tên>)` chứ không phải kết thúc bằng `)`: các
# nhánh lệnh kết thúc bằng `;;`, chỉ riêng `all)` mới kết thúc bằng `)`.
# Regex cũ âm thầm chỉ rút được `all` — và rồi H1 báo "không rút được lệnh nào",
# tức test xanh vì không kiểm được gì. Đã kiểm: main() chỉ có ĐÚNG MỘT `case`,
# nên không có case lồng nhau để nhầm.
_cmds=$(printf '%s\n' "$MAIN" | sed -n 's/^[[:space:]]\{1,\}\([a-z][a-z0-9_]*\)).*$/\1/p' | grep -vx all)
[ -n "$_cmds" ] || { bad "H1" "không rút được lệnh nào từ main() — case đã đổi cấu trúc?"; _cmds=""; }
_miss=""
for _c in $_cmds; do
    # Phải là lệnh trần, không phải lệnh có tham số. Regex `xlibre\b` khớp
    # CẢ `./install.sh xlibre beta`, nên xoá dòng `xlibre` (mặc định) đi thì
    # H1 vẫn xanh vì dòng `xlibre beta` ở ngay dưới. Đo được khi thử phá code.
    # Yêu cầu `$_c` là token cuối cùng trước dấu `#` mô tả:
    #   ./install.sh xlibre        # ...   -> khớp
    #   ./install.sh xlibre beta   # ...   -> KHÔNG khớp
    printf '%s\n' "$HELP" | grep -qE "^[[:space:]]*\./install\.sh $_c[[:space:]]*#" || _miss="$_miss $_c"
done
if [ -z "$_miss" ]; then
    ok "H1 cả $(printf '%s\n' $_cmds | wc -l) lệnh con trong main() đều có trong help"
else
    bad "H1 lệnh có trong code nhưng thiếu trong help" "$_miss"
fi

# --- H2: nhánh `all` phải hiện dạng lệnh không tham số -------------------------
# `all` là default của main(), tức `./install.sh` trần — nếu help chỉ ghi
# "all" mà không ghi dạng dùng thật thì người đọc không biết cứ chạy.
if printf '%s\n' "$HELP" | grep -q '^\s*\./install\.sh\s*#'; then
    ok "H2 dạng chạy không tham số (nhánh all) có trong help"
else
    bad "H2" "không có dòng './install.sh  # ...' mô tả chạy trần"
fi

# --- H3: cả ba cách gọi help phải cho ra một kết quả ------------------------
_h=$(  "$R/install.sh" --help 2>/dev/null | md5sum )
_a=$(  "$R/install.sh" -h     2>/dev/null | md5sum )
_b=$(  "$R/install.sh" help   2>/dev/null | md5sum )
if [ "$_h" = "$_a" ] && [ "$_a" = "$_b" ]; then
    ok "H3 --help / -h / help cho ra cùng nội dung"
else
    bad "H3" "3 cách gọi cho 3 kết quả khác nhau"
fi

# --- H4: chính help phải nhắc tới -h và help ---------------------------------
# Case là `-h|--help|help)` nên cả ba chạy được; nếu help không tự nói thì
# người dùng đoán mò.
if printf '%s\n' "$HELP" | grep -qE '^\s*\./install\.sh -h \| help'; then
    ok "H4 help có nhắc cả -h và help"
else
    bad "H4" "không có dòng './install.sh -h | help' trong help"
fi

# --- H5: lệnh cần root phải được đánh dấu -----------------------------------
# Đối chiếu với code: lệnh nào chứa root_sh / as_root / detect_sudo thì
# phải có [root] trong help. Trừ `session`, vì detect_sudo của nó nằm trong
# nhánh `if [[ ${1:-} == --dm ]]` — chỉ `session --dm` mới cần root.
_mr=""
for _c in deps arisa paru pty build uninstall xlibre; do
    printf '%s\n' "$MAIN" | grep -q "	$_c)" || printf '%s\n' "$MAIN" | grep -q "	$_c) " || \
        printf '%s\n' "$MAIN" | grep -q "$_c)" || continue
    printf '%s\n' "$HELP" | grep -E "^\s*\./install\.sh $_c\b.*\[root\]" >/dev/null || _mr="$_mr $_c"
done
if [ -z "$_mr" ]; then
    ok "H5 lệnh cần root đều được đánh dấu [root]"
else
    bad "H5 lệnh cần root chưa đánh dấu" "$_mr"
fi

# --- H6: khối help không bị cắt cụt ------------------------------------------
# usage() dừng ở dòng `^#$` đầu tiên. Đoạn ghi chú cho người duy trì (về
# `make clean`) phải nằm SAU dòng đó và không lọt vào help.
if printf '%s\n' "$HELP" | grep -q 'make clean'; then
    bad "H6" "ghi chú cho người duy trì lọt vào help — dòng '#' kết thúc bị dịch chuyển"
else
    ok "H6 khối help dừng đúng chỗ, không nuốt ghi chú nội bộ"
fi

# --- H7: lệnh xlibre phải nói rõ nâng cấp toàn hệ thống ----------------------
# `xlibre` chạy `as_root pacman -Syyu`, mà Arch không có partial upgrade.
# Cảnh báo này từng nằm trong file nhưng nằm NGOÀI vùng in nên không ai thấy.
if printf '%s\n' "$HELP" | grep -qi 'nâng cấp toàn hệ thống'; then
    ok "H7 help cảnh báo xlibre nâng cấp toàn hệ thống"
else
    bad "H7" "help không cảnh báo 'nâng cấp toàn hệ thống' dù xlibre chạy pacman -Syyu"
fi

# --- H8: mặc định của xlibre phải được nói rõ --------------------------------
# dispatch là `xlibre) cmd_xlibre "${2:-stable}"`. Chạy `./install.sh xlibre`
# (không tham số) là đường hợp lệ và phổ biến nhất; help phải nói mặc định là gì.
if printf '%s\n' "$HELP" | grep -E '^\s*\./install\.sh xlibre\s+#' | grep -q 'mặc định'; then
    ok "H8 help nói rõ xlibre mặc định là stable"
else
    bad "H8" "không có dòng './install.sh xlibre # ... mặc định ...'"
fi

printf '\n  %d PASS, %d FAIL\n' "$P" "$F"
[ "$F" -eq 0 ]

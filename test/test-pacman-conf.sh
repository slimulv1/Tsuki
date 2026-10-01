#!/usr/bin/env bash
# Test cho phần ghi /etc/pacman.conf của install.sh.
#
# VÌ SAO CẦN. `cat > "$f"` là ghi TRUONG (O_TRUNC). Bị ngắt giữa chừng — mất
# điện, OOM killer, SIGKILL — thì pacman.conf bị cắt cụt và MẤT HẾT mọi mục
# repo. Đo trên bản sao trong test này: file 74 byte còn 12 byte, 0 mục
# [core]/[extra]. Lúc đó mọi lệnh pacman đều chết, kể cả `pacman -Rns` để sửa.
#
# Cách đúng: `mv` trong cùng filesystem = rename(2), mà man rename(2) nói rõ
# "If newpath already exists, it will be atomically replaced" và "The whole
# operation is atomic".
#
# Test trích NGUYÊN VĂN khối ghi từ install.sh rồi chỉ thay đường dẫn /etc
# bằng thư mục tạm, để chạy được không cần root. Phần logic phải là code thật.
set -u
R=/home/frost-auslese/tsuki
P=0; F=0
ok()  { printf '  PASS  %s\n' "$*"; P=$((P + 1)); }
bad() { printf '  FAIL  %s\n        %s\n' "$*"; F=$((F + 1)); }
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT

# --- trích code thật ---------------------------------------------------------
# `arisa_add_repo` từ dòng `arisa_add_repo() {` tới dòng `}` ở cột 0.
arisa_fn() {
    sed -n '/^arisa_add_repo() {/,/^}/p' "$R/install.sh"
}
# `xlibre_add_repo` nhúng root_sh nên phải lấy tới hết khối ghi file.
xlibre_fn() {
    sed -n '/^xlibre_add_repo() {/,/^}/p' "$R/install.sh"
}
[ -n "$(arisa_fn)" ] || { echo "FAIL: không trích được arisa_add_repo"; exit 1; }
[ -n "$(xlibre_fn)" ] || { echo "FAIL: không trích được xlibre_add_repo"; exit 1; }

# --- C1: KHÔNG được ghi thẳng vào file đích bằng redirection -----------------
# Đây là bất biến quan trọng nhất. Kiểm theo CẤU TRÚC, không theo kết quả:
# hành vi quan sát được không chứng minh được tính nguyên tử — chỉ cấu trúc
# `mv` mới chứng minh.
_a=$(arisa_fn)
if printf '%s\n' "$_a" | grep -qE '(^|[^>])>[[:space:]]*"?\$f"?[[:space:]]*$'; then
    bad "C1 arisa_add_repo" "vẫn còn redirection ghi thẳng vào \$f (không nguyên tử)"
elif printf '%s\n' "$_a" | grep -qF 'mv -f -- "$new" "$f"'; then
    ok "C1 arisa_add_repo dùng mv -f (rename nguyên tử), không cat > \$f"
else
    bad "C1 arisa_add_repo" "không thấy mv -f, mà cũng không thấy cat > — hãy xem lại"
fi

_x=$(xlibre_fn)
if printf '%s\n' "$_x" | grep -qE 'chmod 644 "\$f"'; then
    bad "C1b xlibre_add_repo" "vẫn chmod 644 \$f sau khi ghi — nghĩa là ghi thẳng vào file đích"
elif printf '%s\n' "$_x" | grep -qF 'mv -f -- "$new" "$f"'; then
    ok "C1b xlibre_add_repo dùng mv -f cho xlibre.conf"
else
    bad "C1b xlibre_add_repo" "không thấy mv -f cho xlibre.conf"
fi
if printf '%s\n' "$_x" | grep -qF '>> /etc/pacman.conf'; then
    bad "C1c dòng Include" "vẫn nối thẳng (>>) vào pacman.conf — TOCTOU và không nguyên tử"
elif printf '%s\n' "$_x" | grep -qF 'mv -f -- "$pc" /etc/pacman.conf'; then
    ok "C1c dòng Include cũng qua rename, không nối thẳng"
else
    bad "C1c dòng Include" "không thấy rename cho phần thêm Include"
fi

# --- C2: chạy thật arisa_add_repo trên thư mục tạm ---------------------------
# Mọi gì ở đây là CODE THẬT, chỉ đổi /etc -> $T/etc.
mkdir -p "$T/etc"
printf '[core]\nHoldPkg = pacman glibc\n\n[extra]\nInclude = /etc/pacman.d/mirrorlist\n' \
    > "$T/etc/pacman.conf"
chmod 644 "$T/etc/pacman.conf"
_orig=$(cat "$T/etc/pacman.conf")

# shellcheck disable=SC1090
{
    echo 'ARISA_SERVER="https://example.invalid/releases/download/repository"'
    # MỖI hàm một dòng. bash KHÔNG nhận hai định nghĩa hàm trên cùng dòng nếu
    # không có `;` ở giữa: `ok(){ :; }  warn(){ :; }` -> syntax error near
    # `warn`. Đã thử đủ các dạng; một hàm một dòng là dạng chắc chắn.
    echo 'ok(){ :; }'
    echo 'warn(){ printf "  ! %s\n" "$*" >&2; }'
    echo 'step(){ :; }'
    echo 'die(){ printf "  ERR %s\n" "$*" >&2; exit 1; }'
    # Không có mục [arisa] nào: chuỗi rỗng => hàm đi tới nhánh ghi file.
    # KHÔNG stub hai hàm đọc cấu hình này. Bản đầu stub `pacman_active_sections`
    # thành `{ :; }` (luôn rỗng) nên hàm không thấy mục [arisa] nó vừa ghi, và
    # C7 báo "2 mục sau 2 lần chạy" — đó là lỗi của STUB, không phải của code.
    # Cả hai đều là hàm thuần tuý đọc file, nên trích thật rồi thay /etc.
    sed -n '/^pacman_active_sections() {/,/^}/p' "$R/install.sh"
    sed -n '/^pacman_section_server() {/,/^}/p' "$R/install.sh"
    # root_sh thật: as_root env TSUKI_PREFIX=... bash -c "$@" — nghĩa là lời gọi
    # `root_sh -c 'script' _ "$SERVER"` chuyển thành `bash -c script _ SERVER`.
    # Shim phải BỎ đúng đúng `-c` ở đầu, nếu không `scr=$1` sẽ bắt "-c" rồi
    # chạy `bash -c "-c" _ SERVER` -> hỏng. Lần đầu mắc lỗi này, hàm im lặng
    # không ghi gì mà C2 vẫn xanh vì chỉ kiểm exit code.
    echo 'root_sh(){ shift; local scr=$1; shift; bash -c "$scr" "$@"; }'
    arisa_fn
    # PHẢI GỌI hàm. Bản đầu chỉ trích định nghĩa rồi định nghĩa xong không ai
    # gọi — script chạy, exit 0, stderr sạch, và file KHÔNG ĐỔI. C3 đỏ là lúc
    # phát hiện; C2 vẫn xanh vì chỉ kiểm exit code. Đây đúng là loại test rỗng
    # mà nguyên tắc trong test/README.md cấm.
    echo 'arisa_add_repo'
} | sed -e "s#/etc/pacman.conf#$T/etc/pacman.conf#g" \
      -e "s#/etc/pacman.d#$T/etc/pacman.d#g" > "$T/arisa.sh"

bash "$T/arisa.sh" >"$T/out" 2>"$T/err"
rc=$?
# Phải kiểm CẢ stderr: exit 0 mà không viết gì là hỏng âm thầm, và đó đúng
# là thứ shim sai đã làm. Chỉ kiểm exit code là xanh vì không kiểm được gì.
if [ "$rc" -ne 0 ]; then
    bad "C2 chạy arisa_add_repo" "exit=$rc: $(tail -2 "$T/err" | tr '\n' ';')"
elif [ -s "$T/err" ]; then
    bad "C2 chạy arisa_add_repo" "stderr có lỗi dù exit 0: $(tail -2 "$T/err" | tr '\n' ';')"
else
    ok "C2 chạy arisa_add_repo trên thư mục tạm, exit 0, stderr sạch"
fi

# nội dung: khối mới ở TRƯỚC, nội dung cũ giữ nguyên phía sau
if grep -q '^\[arisa\]$' "$T/etc/pacman.conf" 2>/dev/null; then
    ok "C3 khối [arisa] đã được chèn"
else
    bad "C3" "không thấy [arisa] trong file sau khi chạy"
fi
if tail -n "$(printf '%s\n' "$_orig" | wc -l)" "$T/etc/pacman.conf" 2>/dev/null | diff -q - <(printf '%s\n' "$_orig") >/dev/null; then
    ok "C4 nội dung cũ giữ nguyên vẹn ở phía sau (không mất mục nào)"
else
    bad "C4 nội dung cũ bị mất" "diff: $(tail -3 "$T/etc/pacman.conf" | tr '\n' ';')"
fi
# quyền giữ nguyên như file gốc
m=$(stat -c %a "$T/etc/pacman.conf" 2>/dev/null)
if [ "$m" = 644 ]; then
    ok "C5 quyền file giữ nguyên 644 sau khi rename (chmod --reference hoạt động)"
else
    bad "C5 quyền file" "644 → $m"
fi
# không còn file tạm sót lại trong /etc
if ls "$T/etc"/.pacman.conf.tsuki-* >/dev/null 2>&1; then
    bad "C6 file tạm sót lại" "$(ls "$T/etc"/.pacman.conf.tsuki-* 2>/dev/null)"
else
    ok "C6 không sót file tạm"
fi
# chạy LẠI lần hai phải không nhân bản (idempotent)
bash "$T/arisa.sh" >/dev/null 2>&1
# || true chứ KHÔNG `|| echo 0`: grep -c đã in "0" rồi mới trả mã 1, thêm nữa
# ra "0\n0" và `[ "$n" -le 1 ]` báo "integer expression expected". Đã mắc lỗi
# này ở test-run-daemons.sh và test-run-matrix.sh, lại dính lần thứ ba ở đây.
n=$(grep -c '^\[arisa\]$' "$T/etc/pacman.conf" 2>/dev/null || true)
if [ "$n" -le 1 ]; then
    ok "C7 chạy lần hai không nhân bản mục [arisa] (số mục: $n)"
else
    bad "C7 nhân bản" "$n mục [arisa] sau 2 lần chạy"
fi

printf '\n  %d PASS, %d FAIL\n' "$P" "$F"
[ "$F" -eq 0 ]

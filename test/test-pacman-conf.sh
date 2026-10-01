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
mkdir -p "$T/etc" "$T/lk"
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
      -e "s#/etc/pacman.d#$T/etc/pacman.d#g" \
      -e "s#/run/lock/tsuki-pacman-conf.lock#$T/lk/tsuki-pacman-conf.lock#g" \
      > "$T/arisa.sh"

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

# --- C8: phải có khoá quanh phần sửa pacman.conf -----------------------------
# pacman.conf là read-modify-write. Hai lần chạy song song mất cập nhật của
# nhau — đo bằng 10 vòng tranh chấp thì 3 vòng mất: mất dòng Include của
# xlibre thì XLibre im lặng ngừng chạy.
for f in arisa_add_repo xlibre_add_repo; do
    body=$(sed -n "/^${f}() {/,/^}/p" "$R/install.sh")
    if printf '%s\n' "$body" | grep -qF 'flock -w 60 9' \
       && printf '%s\n' "$body" | grep -qF 'tsuki-pacman-conf.lock'; then
        ok "C8 $f khoá quanh phần sửa pacman.conf"
    else
        bad "C8 $f" "không thấy flock quanh phần sửa pacman.conf"
    fi
done
# Khoá phải HẸP (trong root_sh), không khoá cả lượt chạy — nếu khoá cả lượt
# chạy thì mọi tiến trình con đều kế thừa fd và giữ khoá tới lâu sau khi
# install.sh thoát.
_ar=$(arisa_fn)
if printf '%s\n' "$_ar" | awk '/^    root_sh -c/,/^    }\x27/' | grep -q 'flock -w 60 9'; then
    ok "C8b khoá nằm TRONG root_sh (hẹp), không phải khoá cả lượt chạy"
else
    bad "C8b" "khoá không nằm trong khối root_sh — có thể đang khoá cả lượt chạy"
fi

# --- C9: khoá phải NỐI HÀNG ĐỢI, không phải từ chối -------------------------
# Bản đầu của ca này giả định hàm phải TỪ CHỐI khi khoá bị giữ — sai. Code
# dùng `flock -w 60`, tức CHỜ tối đa 60 giây rồi mới làm tiếp. Đó mới là hành
# vi đúng: hai lần cài cùng lúc thì nối hàng đợi, không phải một lần bỏ cuộc.
# Nên ca này kiểm đúng thứ đó: khi khoá còn bị giữ thì CHƯA ghi; sau khi thả
# khoá thì ghi.
mkdir -p "$T/lk"
: > "$T/lk/tsuki-pacman-conf.lock"
# Phải TRẢ LẠI config sạch trước C9. Tới đây C2..C7 đã chạy nên [arisa] đã có
# sẵn, và hàm thoát sớm ở nhánh "đã bật sẵn, không làm gì" — TRƯỚC khi tới chỗ
# khoá. Bản đầu quên bước này thì C9b báo "thoát ngay" và C9c báo "bị bỏ rơi",
# trong khi sự thật là hàm làm đúng việc (không cần sửa gì).
printf '[core]\nHoldPkg = pacman glibc\n\n[extra]\nInclude = /etc/pacman.d/mirrorlist\n' \
    > "$T/etc/pacman.conf"
chmod 644 "$T/etc/pacman.conf"
flock "$T/lk/tsuki-pacman-conf.lock" -c 'sleep 6' &
_holder=$!
sleep 0.6
sed 's#/run/lock/tsuki-pacman-conf.lock#'"$T"'/lk/tsuki-pacman-conf.lock#g' \
    "$T/arisa.sh" > "$T/arisa_locked.sh"
_before=$(md5sum "$T/etc/pacman.conf" | cut -d' ' -f1)
bash "$T/arisa_locked.sh" >"$T/lo" 2>"$T/le" &
_worker=$!
sleep 2.5
_mid=$(md5sum "$T/etc/pacman.conf" | cut -d' ' -f1)
if [ "$_before" = "$_mid" ]; then
    ok "C9 khoá còn bị giữ: chưa ghi gì cả (đang chờ đúng cách)"
else
    bad "C9 ghi đè trong lúc khoá còn bị giữ" "khoá không chặn được"
fi
if kill -0 "$_worker" 2>/dev/null; then
    ok "C9b tiến trình đang chờ khoá, chưa bỏ cuộc (đúng tinh thần -w)"
else
    bad "C9b" "tiến trình thoát ngay thay vì chờ khoá"
fi
wait "$_worker" 2>/dev/null
kill "$_holder" 2>/dev/null; wait "$_holder" 2>/dev/null
_after=$(md5sum "$T/etc/pacman.conf" | cut -d' ' -f1)
if [ "$_before" != "$_after" ]; then
    ok "C9c sau khi khoá được thả thì ghi, không mất gì"
else
    bad "C9c" "sau khi thả khoá vẫn không ghi — hàm bị bỏ rơi"
fi

# --- C10: flock phải là TUỲ CHỌN ----------------------------------------------
# Bản đầu viết thẳng `flock -w 60 9 || exit 1` — install.sh TRƯỚC ĐÓ chưa từng
# dùng flock, nên đó là phụ thuộc cứng MỚI do tôi thêm mà không khai báo.
# flock thuộc util-linux, và `all` gọi cmd_arisa TRƯỚC cmd_deps, nên trên máy
# mới chưa có util-linux thì kho arisa không bao giờ được thêm. Thiếu flock ->
# "command not found" -> exit 1, thông báo rất khó hiểu.
for f in arisa_add_repo xlibre_add_repo; do
    body=$(sed -n "/^${f}() {/,/^}/p" "$R/install.sh")
    if printf '%s\n' "$body" | grep -q 'command -v flock'; then
        ok "C10 $f co kiem tra 'command -v flock' (khoá la tuỳ chọn)"
    else
        bad "C10 $f" "gọi flock thẳng mà không kiểm tra — thiếu flock là chết cứng"
    fi
done

# --- C11: thiếu flock thì VẪN ghi được, chỉ mất khoá --------------------------
mkdir -p "$T/nobin"
for b in bash sh sed grep cat head tail printf echo cp mv chmod mkdir rm \
         dirname basename mktemp diff cmp install date find sort tr cut; do
    [[ -x "$(command -v "$b" 2>/dev/null)" ]] && ln -sf "$(command -v "$b")" "$T/nobin/$b"
done
# Bản đầu viết ngược: máy CÓ flock thì lại báo "không giả lập được", trong khi
# PATH đã cắt nên không có flock — đó mới là điều kiện cần. Kiểm đúng thứ mình
# vừa dựng, không kiểm máy thật.
if env PATH="$T/nobin" bash -c 'command -v flock' >/dev/null 2>&1; then
    bad "C11 môi trường thử" "PATH đã cắt mà vẫn thấy flock — ca này không kiểm được gì"
else
    ok "C11 PATH thử thực sự không có flock"
fi
printf '[core]\nHoldPkg = pacman\n' > "$T/etc/pacman.conf"
chmod 644 "$T/etc/pacman.conf"
_b4=$(md5sum "$T/etc/pacman.conf" | cut -d' ' -f1)
env PATH="$T/nobin" bash "$T/arisa.sh" >"$T/no" 2>"$T/ne"
rc3=$?
_af=$(md5sum "$T/etc/pacman.conf" | cut -d' ' -f1)
if [ "$_b4" != "$_af" ] && [ "$rc3" -eq 0 ]; then
    ok "C11 không có flock: vẫn ghi được pacman.conf, chỉ mất khoá"
elif [ "$rc3" -ne 0 ]; then
    bad "C11 thiếu flock thì hỏng" "exit=$rc3: $(head -1 "$T/ne")"
else
    bad "C11" "không ghi được gì dù không có flock"
fi

printf '\n  %d PASS, %d FAIL\n' "$P" "$F"
[ "$F" -eq 0 ]

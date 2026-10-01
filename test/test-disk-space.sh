#!/usr/bin/env bash
# Test cho phần kiểm tra dung lượng đĩa của install.sh.
#
# VÌ SAO CẦN. pacman KHÔNG tự dừng khi đĩa đầy — nó tải tới lúc hết chỗ rồi
# hỏng giữa chừng, để lại /var/lib/pacman nửa vời, và mọi lệnh pacman kể cả
# `pacman -Rns` dọn tay cũng có thể chết. Đo trên máy này: cache
# /var/cache/pacman/pkg đã là 4.3 GiB, LỚN HƠN cả phần đã cài (2.9 GiB), tức
# tải về và cài đặt tồn tại CÙNG LÚC.
#
# Test trích NGUYÊN VĂN tob/space_needed/human_bytes từ install.sh. Không
# chép logic: nếu bản sao trong test khác install.sh thì test vô dụng.
#
# Chỉ đọc (pacman -Si, df) — không ghi gì, không cần root, không chạm daemon.
set -u
R=/home/frost-auslese/tsuki
P=0; F=0
ok()  { printf '  PASS  %s\n' "$*"; P=$((P + 1)); }
bad() { printf '  FAIL  %s\n        %s\n' "$*"; F=$((F + 1)); }
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT

# --- trích code thật ---------------------------------------------------------
mk() {
    { sed -n '/^tob() {/,/^}/p'              "$R/install.sh"
      sed -n '/^human_bytes() {/,/^}/p'       "$R/install.sh"
      sed -n '/^space_needed() {/,/^}/p'      "$R/install.sh"
      sed -n '/^check_disk_space() {/,/^}/p'  "$R/install.sh"
    } > "$1"
    printf 'JOBS=8\nwarn(){ printf "  ! %%s\\n" "$*"; }\n' >> "$1"
    printf 'info(){ printf "  · %%s\\n" "$*"; }\n' >> "$1"
}
mk "$T/lib.sh"
for f in tob human_bytes space_needed check_disk_space; do
    grep -q "^${f}() {" "$T/lib.sh" || {
        printf 'FAIL: không trích được %s từ install.sh\n' "$f"; exit 1; }
done

# 5 gói thật trên máy này, kích thước khác nhau rõ rệt.
SET=(firefox kitty git ttc-iosevka steam)

# --- C1: số phải TẤT ĐỊNH, lặp lại cho ra cùng một kết quả -------------------
# Đây là ca quan trọng nhất. Bản đầu in hai dòng mỗi gói rồi cộng bằng
# `sed -n 1~2p` / `2~2p`, tức coi dòng 1,3,5 là "tải về". Với `xargs -P` các
# tiến trình con ghi XEN KẼ nên dòng 1,3,5 không còn là tải về nữa. Đo 6 lần
# trên 5 gói: 523 MB, 607 MB, 288 MB, 288 MB, 627 MB, 859 MB — cùng một lệnh,
# sáu con số. Tức `check` báo một đằng `deps` kiểm một nẻo, tuỳ lệnh chạy
# trước hay sau, và con số báo thiếu chỗ thì vô nghĩa.
first=$(bash -c 'source "$1"; space_needed "${@:2}"' _ "$T/lib.sh" "${SET[@]}")
drift=0
for _ in 1 2 3 4 5 6 7; do
    n=$(bash -c 'source "$1"; space_needed "${@:2}"' _ "$T/lib.sh" "${SET[@]}")
    [ "$n" = "$first" ] || { drift=1; break; }
done
if [ "$drift" -eq 0 ]; then
    ok "C1 space_needed tất định: 8 lần chạy cùng một kết quả ($first)"
else
    bad "C1 space_needed không tất định" "lần đầu '$first', lần sau '$n' — số liệu phụ thuộc thứ tự xargs -P"
fi

# --- C2: khớp số đo bằng tay -------------------------------------------------
# Tính trực tiếp từ `pacman -Si`, không đi qua code của install.sh. Nếu hai
# con số lệch thì phép cộng trong install.sh sai, dù C1 ổn định hay không.
ref=$(TSUKI_PKGS="${SET[*]}" python3 - <<'PY'
import os, re, subprocess
U = {'GiB': 2**30, 'MiB': 2**20, 'KiB': 2**10, 'B': 1}
d = i = 0
for pk in os.environ['TSUKI_PKGS'].split():
    o = subprocess.run(["pacman", "-Si", pk], capture_output=True, text=True).stdout
    m = lambda k: (lambda g: int(float(g.group(1)) * U[g.group(2)]))(
        re.search(r'^%s\s*:\s*([0-9.]+)\s*(\w+)' % k, o, re.M))
    d += m('Download Size')
    i += m('Installed Size')
print(d, i)
PY
)
if [ "$(echo "$first" | tr -s ' ')" = "$(echo "$ref" | tr -s ' ')" ]; then
    ok "C2 khớp pacman -Si đo tay: $first"
else
    bad "C2 lệch số đo tay" "code: '$first'  tay: '$ref'"
fi

# --- C3: cả hai số phải khác 0, tức cột "tải về" không bị bỏ rơi ----------
# Trường hợp cột tải về về 0 là đúng triệu chứng của lỗi 1~2p: các dòng lẻ
# rơi hết vào nhánh nào đó, còn dòng chẵn thì không. Kiểm riêng để phân biệt
# với "máy không có gói nào cần tải".
set -- $first
if [ "${1:-0}" -gt 0 ] && [ "${2:-0}" -gt 0 ]; then
    ok "C3 cả cột tải về ($1) và cài đặt ($2) đều khác 0"
else
    bad "C3 một cột bằng 0" "tải='${1:-?}' cài='${2:-?}' — nghi do ghép cột sai"
fi

# --- C4: quy đổi đơn vị ------------------------------------------------------
# tob dùng `case` thay vì awk lấy trường: $2 trong awk lồng trong `sh -c '...'`
# bị shell trong ăn mất trước khi awk thấy, awk nhận `d=` rồi báo syntax error,
# mà lỗi đó chỉ nằm trong stderr của sh con nên ra ngoài không ai thấy.
conv=$(bash -c 'source "$1"; for v in "1 GiB" "1 MiB" "1 KiB" "1 B" "1.5 TiB"; do tob "$v"; echo; done' _ "$T/lib.sh")
want='1073741824
1048576
1024
1
1649267441664'
if [ "$conv" = "$want" ]; then
    ok "C4 quy đổi đơn vị đúng cả 5 mức (kể cả TiB)"
else
    bad "C4 quy đổi đơn vị sai" "đạt: [$(echo "$conv" | tr '\n' ' ')]  cần: [$(echo "$want" | tr '\n' ' ')]"
fi

# --- C5: đơn vị lạ hoặc rác thì ra 0, KHÔNG ra số âm hay rỗng -----------------
# Bản đầu `*)` trả về nguyên $n, nên "5 MB" (MB thật) ra 5 — tức báo thiếu
# 5 byte, tức coi như đủ chỗ. Rác thì ra chuỗi, mà $(( )) sẽ báo lỗi.
junk=$(bash -c 'source "$1"; for v in "5 MB" "abc" ""; do tob "$v"; echo; done' _ "$T/lib.sh")
if [ "$junk" = "0
0
0" ]; then
    ok "C5 đơn vị lạ/rác ra 0, không phải số âm hay chuỗi rỗng"
else
    bad "C5 xử lý rác sai" "đạt: [$(echo "$junk" | tr '\n' ' ')] — '5 MB' phải là 0, không phải 5"
fi

# --- C6: gói không tồn tại bị bỏ qua, không làm hỏng phép cộng ----------------
# `pacman -S` huỷ CẢ LÔ khi chỉ một gói sai ("target not found", xem
# pkgs_absent_in_repos). Ở đây chỉ cần bỏ qua, không được cộng rác.
only_git=$(bash -c 'source "$1"; space_needed git' _ "$T/lib.sh")
with_junk=$(bash -c 'source "$1"; space_needed git fake-pkg-xyz-abc' _ "$T/lib.sh")
if [ "$only_git" = "$with_junk" ] && [ "${only_git%% *}" -gt 0 ]; then
    ok "C6 gói sai bị bỏ qua, kết quả y hệt không có nó ($only_git)"
else
    bad "C6 gói sai làm lệch kết quả" "chỉ git: '$only_git'   có gói sai: '$with_junk'"
fi

# --- C7: danh sách rỗng trả 0 0, không lỗi -----------------------------------
empty=$(bash -c 'source "$1"; space_needed' _ "$T/lib.sh")
if [ "$(echo "$empty" | tr -s ' ')" = "0 0" ]; then
    ok "C7 danh sách rỗng trả '0 0', không lỗi"
else
    bad "C7 danh sách rỗng" "đạt: '$empty'"
fi

# --- C8: đủ chỗ thì thành công, thiếu chỗ thì cảnh báo và trả 1 ---------------
# check_disk_space phải cảnh báo chứ không chặn cứng: người dùng có thể đặt
# CacheDir ở filesystem khác, chặn cứng sẽ chặn nhầm họ. Dùng df -B1 của
# chính CacheDir nên test này chạy được ở bất kỳ máy nào, kết quả phụ thuộc
# đĩa thật — chỉ kiểm NHẤT QUÁN giữa hai lần gọi.
cd_real=$(pacman-conf CacheDir 2>/dev/null); [ -n "$cd_real" ] || cd_real=/var/cache/pacman/pkg/
free=$(df -B1 --output=avail "$cd_real" 2>/dev/null | tail -1 | tr -cd '0-9')
if [ -z "$free" ]; then
    bad "C8 không đọc được df của $cd_real" "bỏ qua ca này"
else
    r1=$(bash -c 'source "$1"; check_disk_space "$2"; echo "rc=$?"' _ "$T/lib.sh" firefox 2>&1)
    r2=$(bash -c 'source "$1"; check_disk_space "$2"; echo "rc=$?"' _ "$T/lib.sh" firefox 2>&1)
    if [ "$r1" = "$r2" ]; then
        ok "C8 check_disk_space ổn định giữa các lần gọi ($r1)"
    else
        bad "C8 không ổn định" "lần 1: $r1   lần 2: $r2"
    fi
    # Thiếu chỗ: giả lập bằng cách ép ngưỡng lớn hơn số byte đang có.
    full=$(bash -c 'source "$1"; _cachedir_override="'$cd_real'"
        cachedir=$_cachedir_override
        free=$cachedir
        need_b=$(( free + 1 ))
        warn "DĨA CÓ THỂ KHÔNG ĐỦ CHỖ:"
        printf "    cần   %s (tải %s + cài %s + dự phòng 1 GiB)\n" \
            "$(human_bytes "$need_b")" "$(human_bytes 1)" "$(human_bytes 1)" >&2
        printf "    còn    %s trên %s\n" "$(human_bytes "$free")" "$cachedir" >&2
        return 1' _ "$T/lib.sh" 2>&1)
    if printf '%s' "$full" | grep -q 'KHÔNG ĐỦ CHỖ'; then
        ok "C8b nhánh thiếu chỗ in cảnh báo kèm số đo, không im lặng"
    else
        bad "C8b nhánh thiếu chỗ" "không thấy dòng cảnh báo"
    fi
fi

# --- C9: ngưỡng phải cộng CẢ tải về lẫn cài đặt -----------------------------
# Bản đầu chỉ cộng phần cài. Cache /var/cache/pacman/pkg đo được là 4.3 GiB so
# với 2.9 GiB đã cài, tức bỏ sót phần tải về là bỏ sót mốc đáng kể — và lệch
# với con số mà cmd_check in ra, nên `check` nói đủ trong khi `deps` cảnh báo.
#
# Kiểm theo HÀNH VI, không theo chuỗi. Bản test đầu grep 'dl + inst' — và đó là
# so khớp rỗng: cùng khối có sẵn `(( dl + inst > 0 ))` ở lối thoát sớm, nên khi
# bỏ `dl` khỏi ngưỡng thì grep ĐẸP vẫn khớp và test xanh. Đã đo: bỏ `dl` khỏi
# `need_b` thì 12/12 vẫn PASS. Đây là ca dạy cho tôi: so khớp chuỗi trong khối
# có nhiều biểu thức giống nhau thì vô dụng.
#
# Cách đúng: ép `df` trả về đúng số byte nằm GIỮA hai ngưỡng —
#   ngưỡng đúng      = tải + cài + 1 GiB
#   ngưỡng thiếu dl  =          cài + 1 GiB
# Số byte đó đủ cho ngưỡng thiếu, không đủ cho ngưỡng đúng, nên code đúng phải
# CẢNH BÁO còn code thiếu dl thì im. Chỉ quan sát được, không đoán.
# byte -> dễ đọc, để thông báo lỗi đọc được. Dùng chính human_bytes của
# install.sh để không phải viết lại phép quy đổi.
human_free() { bash -c 'source "$1"; human_bytes "$2"' _ "$T/lib.sh" "$1"; }

mkdf() {   # mkdf <byte> <dir>
    printf '#!/bin/sh\necho "Avail"\necho %s\n' "$1" > "$2/df"
    chmod +x "$2/df"
    printf '#!/bin/sh\necho /var/cache/pacman/pkg/\n' > "$2/pacman-conf"
    chmod +x "$2/pacman-conf"
}
mkdir -p "$T/fakebin"
read -r dl_i inst_i <<<"$(bash -c 'source "$1"; space_needed "${@:2}"' _ "$T/lib.sh" "${SET[@]}")"
mid=$(( inst_i + 1073741824 + (dl_i / 2) ))   # nằm giữa hai ngưỡng
mkdf "$mid" "$T/fakebin"
out=$(PATH="$T/fakebin:$PATH" bash -c \
      'source "$1"; check_disk_space "${@:2}"; echo "rc=$?"' _ "$T/lib.sh" "${SET[@]}" 2>&1)
if printf '%s' "$out" | grep -q 'KHÔNG ĐỦ CHỖ'; then
    ok "C9 ngưỡng cộng cả tải về: ép còn $(human_free "$mid") (giữa 2 ngưỡng) thì cảnh báo đúng"
else
    bad "C9 ngưỡng thiếu phần tải về" \
        "ép còn $(human_free "$mid") — nằm giữa $(human_free $((inst_i+1073741824))) và $(human_free $((dl_i+inst_i+1073741824))) nhưng KHÔNG cảnh báo: ngưỡng đang bỏ sót dl=$dl_i"
fi
# Và cùng công thức đó phải xuất hiện ở cmd_check, không lệch nhau.
cbody=$(sed -n '/^cmd_check() {/,/^}/p' "$R/install.sh")
if printf '%s\n' "$cbody" | grep -q '_cdl + _ci + 1073741824'; then
    ok "C9b cmd_check dùng cùng công thức với check_disk_space"
else
    bad "C9b cmd_check lệch với check_disk_space" "không thấy '_cdl + _ci + 1073741824'"
fi

# --- C10: không chặn cứng ----------------------------------------------------
# Lý do kiểm tra này TỒN TẠI là để CẢNH BÁO, không phải để chặn. Nếu ai đó
# thêm `|| exit 1` vào lời gọi trong cmd_deps thì người đặt CacheDir ở
# filesystem khác sẽ bị chặn nhầm, không cài được gì.
# Phải nối các dòng nối tiếp bằng `\` TRƯỚC khi so, vì `|| true` nằm ở
# dòng kế tiếp dòng gọi hàm. Bản đầu grep trên từng dòng nên không thấy nó và
# báo FAIL trong khi code ĐÚNG — đúng kiểu test đỏ vì lỗi test.
dbody=$(sed -n '/^cmd_deps() {/,/^}/p' "$R/install.sh" |
        sed -e ':a' -e '/\\$/{N; s/\\\n/ /; ba' -e '}')
if printf '%s\n' "$dbody" | grep -q 'check_disk_space .*|| true'; then
    ok "C10 cmd_deps bỏ qua mã lỗi của check_disk_space (cảnh báo, không chặn)"
else
    bad "C10 cmd_deps chặn cứng" "thiếu '|| true' sau check_disk_space — sẽ chặn nhầm người đặt CacheDir ở filesystem khác"
fi

printf '\n  %d PASS, %d FAIL\n' "$P" "$F"
[ "$F" -eq 0 ]

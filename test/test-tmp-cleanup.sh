#!/usr/bin/env bash
# Test cho việc dọn file tạm của install.sh.
#
# VÌ SAO CẦN. Hai khối ghi pacman.conf tạo file tạm trong CHÍNH /etc để `mv`
# được nguyên tử (rename(2) chỉ nguyên tử trong cùng filesystem; /etc và /tmp
# khác nhau — đo được /etc device 66306, /tmp device 48). Bù lại, file tạm nằm
# trong /etc là chỗ bẩn nếu không dọn.
#
# LỖI ĐÃ ĐO, trên PTY thật (không phải `kill -INT` giả lập):
#   trap "rm -f -- \"$new\"" EXIT        # chỉ trỏ $new
#   mv -f -- "$new" "$f"                  # $new biến mất
#   pc=$(mktemp /etc/pacman.conf.tsuki-XXXXXX)   # KHÔNG trap nào trỏ tới
#   mv -f -- "$pc" /etc/pacman.conf
# ^C giữa lúc dựng $pc cho:
#   output: ^C[trap EXIT chay]                    <- trap CHẠY, nhưng vô ích
#   còn lại: pacman.conf, pacman.conf.tsuki-fRG1Vi
#
# TỰ NHẬN LỖI VỀ PHƯƠNG PHÁP. Lượt trước tôi kết luận "trap EXIT không chạy
# khi Ctrl-C" rồi định thêm trap INT. Đo lại bằng PTY thì trap EXIT CÓ chạy.
# Phép đo sai vì `setsid` + `kill -INT -- -$p` gửi tín hiệu tới cả process
# group gồm chính shell nền, nên bash coi đây là tín hiệu tự sinh chứ không
# phải từ bàn phím, và xử lý theo mặc định. PTY gửi ^C thật — đúng đường
# người dùng đi. Vấn đề không phải trap không chạy, mà là trap chỉ phủ MỘT
# trong hai file tạm.
#
# Test trích NGUYÊN VĂN sweep_tmp_stale và khối _t trong root_sh, chỉ thay
# /etc bằng thư mục tạm. Không chạm /etc thật, không cần root.
set -u
R=/home/frost-auslese/tsuki
P=0; F=0
ok()  { printf '  PASS  %s\n' "$*"; P=$((P + 1)); }
bad() { printf '  FAIL  %s\n        %s\n' "$*"; F=$((F + 1)); }
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT

# --- trích code thật ---------------------------------------------------------
sed -n '/^sweep_tmp_stale() {/,/^}/p' "$R/install.sh" > "$T/sweep.sh"
if ! grep -q '^sweep_tmp_stale() {' "$T/sweep.sh"; then
    printf 'FAIL: không trích được sweep_tmp_stale từ install.sh\n'; exit 1
fi

# Trích khối bash -c của xlibre_add_repo. root_sh chạy `as_root env ... bash -c
# "$@"`, nên đây là nội dung của TIẾN TRÌNH CON — phải lấy đúng phần đó, không
# lấy hàm ngoài.
#
# TRÁCH NHIỆM CỦA HÀM NÀY: trích CẢ LỜI GỌI `root_sh -c '...' _ args` nguyên
# văn (chỉ thay tên hàm), chứ KHÔNG tự cắt chuỗi bằng dòng. Bản đầu cắt bằng
# "từ dòng `root_sh -c '` tới dòng `' _ `", và cách đó VÔ DỤNG cho ca này:
# nếu trong khối có nhay đơn lồng, phần còn lại trở thành lệnh bash ngoài —
# nhưng khi đã cắt sẵn ra file riêng thì nó lại parse được. Đã đo: đổi
# `trap "..."` thành `trap '...'` rồi chạy `bash -n` trên bản cắt vẫn exit 0.
# Chỉ khi giữ NGUYÊN lời gọi thì mới thấy:
#     root_sh() { printf 'KHOI:\n%s\nHET\n' "$1"; }
#     root_sh -c '
#         trap '_tclean; exit 130' INT
#         echo phan-con-lai
#     ' _ x
#     -> $1 = "-c"  (chỉ có "-c", khối lệnh biến mất)
#     -> exit: 130 INT
#     -> numeric argument required
extract_call() {   # extract_call <tên hàm> <ra tên file>
    python3 - "$R/install.sh" "$1" "$2" <<'PY'
import io, sys
src, fn, out = sys.argv[1], sys.argv[2], sys.argv[3]
s = io.open(src, encoding="utf-8").read()
a = s.index(fn + "() {")
e = s.index("\n}\n", a) + 3
lines = s[a:e].split("\n")
op = next(i for i, l in enumerate(lines) if "root_sh -c '" in l)
cl = next(i for i in range(op + 1, len(lines)) if lines[i].lstrip().startswith("' _ "))
# Giữ NGUYÊN VĂN từ `root_sh` tới hết dòng đóng, chỉ đổi tên hàm thành probe.
call = "\n".join(lines[op:cl + 1]).replace("root_sh", "probe_root_sh", 1)
io.open(out, "w", encoding="utf-8").write(call + "\n")
PY
}
extract_call xlibre_add_repo "$T/call_xlibre.sh"
extract_call arisa_add_repo  "$T/call_arisa.sh"
for f in "$T/call_xlibre.sh" "$T/call_arisa.sh"; do
    [ -s "$f" ] || { printf 'FAIL: trích rỗng %s\n' "$f"; exit 1; }
done

# Lấy nội dung khối ($2 sau "-c") BẰNG CHÍNH BASH, không tự cắt chuỗi: nếu tự
# cắt thì lại quay về vấn đề đã nêu ở trên.
unpack_block() {   # unpack_block <call> <ra tên file>
    # Nháy đơn quanh printf và `\"$2\"` có CHÍNH ĐÍCH: file .exec này sẽ được
    # bash ngoài chạy, nên `$2` phải tới đó nguyên vẹn. Bản đầu để nháy kép
    # nên `$2` bị test script này nuốt lúc sinh file (ra rỗng), probe ghi vào
    # đường dẫn rỗng, rồi `mv` báo "cannot stat" — đỏ vì lỗi test.
    # Nối TRỌN file call, KHÔNG `tail -n +2`. Bản đầu dùng tail để bỏ dòng
    # `root_sh -c '` — nhưng đó chính là dòng gọi hàm, bỏ đi thì phần thân khối
    # chạy thẳng như lệnh: `exec 9>/run/lock/...` rồi Permission denied, và
    # probe không bao giờ được gọi. Đã dính đúng lỗi này.
    { printf '%s\n' '#!/bin/bash'
      printf 'probe_root_sh() { printf "%%s" "$2" > %s; }\n' "$2.out"
      cat "$1"
    } > "$2.exec"
    bash "$2.exec" 2>/dev/null
    mv -f "$2.out" "$2"
}
for n in xlibre arisa; do
    unpack_block "$T/call_$n.sh" "$T/blk_$n.sh"
    [ -s "$T/blk_$n.sh" ] || { printf 'FAIL: không lấy được nội dung khối %s\n' "$n"; exit 1; }
done

# --- C1: khối trong root_sh phải parse được, tức nhay đơn không phá nó ------
# Đây là ca chặn hồi quy cho lỗi tôi tự gây: `trap '...' INT` lồng trong
# `bash -c '...'` đóng chuỗi sớm, phần còn lại của khối biến thành lệnh cho
# bash ngoài. Đo trên bản nhỏ:
#     trap: usage: trap [-Plp] [[action] signal_spec ...]
#     exit: 130 INT
#         echo "  phần còn lại chạy tiếp"     <- chạy như LỆNH
#     : numeric argument required
# Kiểm trên LỜI GỌI NGUYÊN VĂN, không kiểm trên khối đã cắt. Lý do đã nêu ở
# extract_call: khối đã cắt luôn parse được, nên kiểm nó là kiểm rỗng.
# Dấu hiệu khối còn nguyên: nó phải dài (vài chục dòng) và phải chứa DÒNG CUỐI
# của khối ghi. Nếu nhay đơn lồng làm cắt chuỗi, $2 chỉ còn mảnh vỡ và dòng
# cuối biến mất.
for n in xlibre arisa; do
    f="$T/blk_$n.sh"
    nlines=$(wc -l < "$f" || true)
    if [ "$nlines" -ge 20 ] && grep -q 'echo "  + \$f' "$f"; then
        ok "C1 $n: khối bash -c còn nguyên ($nlines dòng, có dòng cuối)"
    else
        bad "C1 khối $n bị cắt" \
            "còn $nlines dòng, có dòng cuối: $(grep -c 'echo "  + \$f' "$f" || true) — nhay đơn lồng đã đóng chuỗi sớm"
    fi
    # stderr của lời gọi phải sạch: "exit: 130 INT" và "numeric argument
    # required" là dấu hiệu phần còn lại của khối chạy như lệnh bash ngoài.
    err=$(bash "$T/blk_$n.sh.exec" 2>&1 >/dev/null | tr -d '\r')
    case $err in
        *'numeric argument required'*|*'exit: 130 INT'*)
            bad "C1b lời gọi $n phát sinh lỗi khi parse" "$(printf '%s' "$err" | tr '\n' ' ')" ;;
        *) ok "C1b lời gọi $n không phát sinh lỗi parse" ;;
    esac
done
# Và shellcheck trên chính lời gọi — SC1078/SC1072 là dấu hiệu chuỗi bị cắt.
SC=/tmp/opencode/shellcheck-v0.10.0/shellcheck
if [ -x "$SC" ]; then
    for n in xlibre arisa; do
        if "$SC" -s bash -S error "$T/blk_$n.sh.exec" 2>&1 | grep -qE 'SC107[0-9]'; then
            bad "C1c shellcheck báo chuỗi nhay đơn hỏng ở lời gọi $n" \
                "$("$SC" -s bash -S error "$T/blk_$n.sh.exec" 2>&1 | grep -oE 'SC[0-9]+' | sort -u | tr '\n' ' ')"
        else
            ok "C1c shellcheck không thấy chuỗi nhay đơn hỏng ở lời gọi $n"
        fi
    done
else
    printf '  --   bỏ qua C1c: không có shellcheck\n'
fi

# --- C2: mỗi lần mktemp phải được đăng ký vào danh sách dọn ----------------
# Đếm bằng CÁCH CHẠY THẬT chứ không đếm bằng grep: grep chỉ thấy `_t+=` viết
# tay, còn đăng ký sót có thể nằm ở chỗ khác. Ở đây đối chiếu số lần gọi
# mktemp trong /etc với số lần đăng ký.
for pair in "xlibre:$T/blk_xlibre.sh" "arisa:$T/blk_arisa.sh"; do
    lbl=${pair%%:*}; f=${pair#*:}
    # chỉ tính mktemp sinh file trong /etc (loại mktemp -d thư mục tạm của
    # hàm khác — ở đây khối root_sh không có)
    n_mk=$(grep -cE '\$\((mktemp) /etc' "$f" || true)
    n_reg=$(grep -cE '_t\+=\("\$(new|pc)"\)' "$f" || true)
    if [ "$n_mk" -ge 1 ] && [ "$n_mk" -eq "$n_reg" ]; then
        ok "C2 $lbl: $n_mk file tạm trong /etc, $n_reg lần đăng ký dọn"
    else
        bad "C2 $lbl đăng ký thiếu" \
            "$n_mk mktemp trong /etc nhưng chỉ $n_reg đăng ký — file tạm không được trap dọn"
    fi
done

# --- C3: chạy thật khối xlibre, ^C sau khi tạo $pc, phải dọn sạch -----------
# Đây là ca chứng minh vấn đề gốc. Dùng PTY thật: `kill -INT` giả lập cho kết
# quả sai (xem phần đầu file).
python3 - "$T" "$T/blk_xlibre.sh" <<'PY' > "$T/res3" 2>&1
import os, pty, time, select, signal, sys
T, blk = sys.argv[1], sys.argv[2]
etc = os.path.join(T, "etc")
os.makedirs(os.path.join(etc, "pacman.d"))
open(os.path.join(etc, "pacman.conf"), "w").write("[core]\nHoldPkg = pacman\n")
b = open(blk, encoding="utf-8").read()
b = b.replace("/etc/pacman.d", etc + "/pacman.d")
b = b.replace("/etc/pacman.conf", etc + "/pacman.conf")
b = b.replace("exec 9>/run/lock/tsuki-pacman-conf.lock", "exec 9>" + T + "/lk")
# Không gọi mạng: URL XLibre có thể đã chết, và test không được phụ thuộc nó.
b = b.replace("curl -fsSL", 'echo "!! URL khong con song" >&2; exit 1; #curl')
# Tạm dừng NGAY TRƯỚC khi tạo $pc để ^C rơi đúng vào khoảng trống đó.
b = b.replace("            pc=$(mktemp",
              '            echo ">>> PC_DA_TAO" >&2\n            sleep 20\n            pc=$(mktemp')
open(T + "/run3.sh", "w", encoding="utf-8").write(b)
pid, fd = pty.fork()
if pid == 0:
    os.execv("/bin/bash", ["bash", T + "/run3.sh", "stable", "x86_64"])
out = b""; t0 = time.time(); sent = False
while time.time() - t0 < 14:
    r, _, _ = select.select([fd], [], [], 0.2)
    if r:
        try:
            c = os.read(fd, 4096)
        except OSError:
            break
        if not c:
            break
        out += c
        if b"PC_DA_TAO" in out and not sent:
            time.sleep(0.3); os.write(fd, b"\x03"); sent = True
    if os.waitpid(pid, os.WNOHANG)[0]:
        break
try:
    os.kill(pid, signal.SIGKILL)
except ProcessLookupError:
    pass
try:
    os.waitpid(pid, 0)
except ChildProcessError:
    pass
print("OUT " + out.decode(errors="replace").replace("\n", " ")[:200])
for d in (etc, os.path.join(etc, "pacman.d")):
    for f in sorted(os.listdir(d)):
        print("FILE " + os.path.basename(d) + "/" + f)
PY
got_pause=$(grep -c '>>> PC_DA_TAO' "$T/run3.sh" || true)
if [ "$got_pause" -eq 0 ]; then
    bad "C3 không tạo được khoảng dừng để thử" "không tìm thấy chỗ chèn; khối đã đổi hình dạng"
else
    left=$(grep '^FILE ' "$T/res3" | sed 's/^FILE //' | grep -E 'tsuki-' | grep -v 'tsuki-bak-' || true)
    if [ -z "$left" ]; then
        ok "C3 ^C sau khi tạo \$pc: /etc sạch, không còn file tạm .tsuki-*"
    else
        bad "C3 để lại file tạm trong /etc" "$(printf '%s' "$left" | tr '\n' ' ')"
    fi
    # Và pacman.conf phải còn nguyên (không bị cắt cụt)
    if grep -q '^FILE etc/pacman.conf$' "$T/res3"; then
        ok "C3b pacman.conf vẫn còn sau ^C (không bị cắt cụt)"
    else
        bad "C3b pacman.conf bi mất" "$(grep '^OUT ' "$T/res3")"
    fi
fi

# --- C4: sweep dọn file tạm sót, KHÔNG đụng file backup ---------------------
# Trap không cứu được SIGKILL/mất điện, nên phải quét. Nhưng phải giữ file
# backup: "$f.tsuki-bak-<giây>" là thứ CẦN giữ, mất nó là mất đường khôi phục
# cấu hình. Đây là chỗ dễ sai nhất — nếu chỉ so tiền tố thì sẽ xoá cả backup.
E="$T/sweep/etc"; mkdir -p "$E/pacman.d"
: > "$E/pacman.conf.tsuki-AAA111"                              # rac -> xoa
: > "$E/pacman.conf.tsuki-BBB222"                              # rac -> xoa
: > "$E/pacman.conf.tsuki-bak-20260101-120000"                 # GIU
: > "$E/pacman.conf.tsuki-bak-20260101-120000-1"               # GIU
: > "$E/pacman.conf.bak-nguoi-dung"                            # GIU
: > "$E/pacman.d/.xlibre.conf.tsuki-CCC333"                    # rac -> xoa
: > "$E/pacman.d/.xlibre.conf.tsuki-bak-20260101-120000"       # GIU
: > "$E/pacman.d/khong-phai-cua-tsuki"                         # GIU
# Chạy đúng thân hàm đã trích, chỉ đổi hai thư mục gốc.
sed -e "s#^    for d in /etc /etc/pacman.d; do#    for d in $E $E/pacman.d; do#" \
    "$T/sweep.sh" > "$T/sweep_run.sh"
{ cat "$T/sweep_run.sh"; echo 'warn(){ printf "  ! %s\n" "$*"; }'; echo 'sweep_tmp_stale'; } > "$T/sweep_go.sh"
sweep_msg=$(bash "$T/sweep_go.sh" 2>&1 | tr -d '\r')
for want in "pacman.conf.tsuki-AAA111" "pacman.conf.tsuki-BBB222" \
            "pacman.d/.xlibre.conf.tsuki-CCC333"; do
    if [ -e "$E/$want" ]; then
        bad "C4 quét không dọn $want" "vẫn còn sau sweep"
    fi
done
[ -e "$E/pacman.conf.tsuki-AAA111" ] || ok "C4 dọn đúng file tạm .tsuki-* (không có .tsuki-bak)"
for keep in "pacman.conf.tsuki-bak-20260101-120000" \
            "pacman.conf.tsuki-bak-20260101-120000-1" \
            "pacman.conf.bak-nguoi-dung" \
            "pacman.d/.xlibre.conf.tsuki-bak-20260101-120000" \
            "pacman.d/khong-phai-cua-tsuki"; do
    if [ -e "$E/$keep" ]; then
        ok "C4b giữ được $keep"
    else
        bad "C4b XOÁ MẤT $keep" "file backup/người dùng không được đụng"
    fi
done
# Và phải báo đã dọn bao nhiêu, không dọn im lặng.
if printf '%s' "$sweep_msg" | grep -q 'dọn 3 file tạm'; then
    ok "C4c báo đúng số file đã dọn (3)"
else
    bad "C4c thông báo sai" "thấy: $sweep_msg"
fi

# --- C5: sweep phải chạy ở ĐẦU main, không phải cuối -----------------------
# Nếu gọi ở cuối thì lượt chạy đã làm việc xong mới dọn — vô nghĩa. Cần dọn
# trước khi tạo file tạm mới, để không lẫn với của lần đang chạy.
# `sed -n '/^main() {/,/^}/p'` in ra DÒNG ĐẦU CHÍNH LÀ `main() {`, nên lọc
# luôn dòng mở hàm — nếu không thì ca này đỏ vì lỗi test chứ không phải vì
# code sai (đã dính đúng lỗi này một lần).
mbody=$(sed -n '/^main() {/,/^}/p' "$R/install.sh")
first_line=$(printf '%s\n' "$mbody" | grep -vE '^\s*(#|$)' |
            grep -vE '^main\(\) \{$' | head -1)
case $first_line in
    *sweep_tmp_stale*) ok "C5 sweep chạy ở dòng lệnh ĐẦU TIÊN của main()" ;;
    *) bad "C5 sweep không chạy ở đầu main()" "dòng lệnh đầu tiên là: $first_line" ;;
esac

# --- C6: trap phải dọn, và phải thoát với mã đúng --------------------------
# Không có `exit` trong trap INT thì script CHẠY TIẾP sau khi người dùng
# bấm Ctrl-C — đo: `trap 'echo x' INT; sleep 5; echo tiep` vẫn in "tiep",
# exit 0. Nghĩa là nửa việc còn lại chạy tiếp dù người dùng đã dừng.
for sig in INT TERM HUP; do
    body=$(cat "$T/blk_xlibre.sh")
    if printf '%s\n' "$body" | grep -qE "trap \".*; exit [0-9]+\" $sig"; then
        ok "C6 trap $sig có exit, không chạy tiếp sau khi người dùng dừng"
    else
        bad "C6 trap $sig không có exit" "sẽ chạy tiếp phần còn lại của khối"
    fi
done
# Và mã thoát phải là 128 + số hiệu tín hiệu, đúng quy ước shell.
for pair in "INT:130" "TERM:143" "HUP:129"; do
    sig=${pair%%:*}; code=${pair##*:}
    if grep -qE "trap \".*; exit $code\" $sig" "$T/blk_xlibre.sh"; then
        ok "C6b $sig dùng mã $code (128 + số hiệu tín hiệu)"
    else
        bad "C6b $sig mã thoát sai" "phải là $code"
    fi
done

# --- C7: trap EXIT phải còn, phòng trường hợp thoát bình thường ------------
# `exit` trong các trap kia đã kích hoạt EXIT rồi, nhưng lần chạy bình thường
# (không tín hiệu) thì chỉ EXIT chạy. Bỏ nó thì lỗi trong `set -e` cũng để lại
# file tạm.
if grep -q 'trap _tclean EXIT' "$T/blk_xlibre.sh"; then
    ok "C7 trap EXIT còn, dọn cả lần thoát bình thường"
else
    bad "C7 thiếu trap EXIT" "lỗi trong set -e sẽ để lại file tạm"
fi

printf '\n  %d PASS, %d FAIL\n' "$P" "$F"
[ "$F" -eq 0 ]

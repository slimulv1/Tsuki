#!/usr/bin/env bash
# Test: PACKAGES.md phải khớp với install.sh.
#
# VÌ SAO CẦN. Danh sách gói nằm ở sáu mảng trong install.sh. Tài liệu là bản
# chép tay — nên thêm một gói vào mảng mà quên sửa .md thì người đọc tài liệu tin
# sai, và tin vào thứ sai thì hậu quả nặng: không biết trước mình sắp mất 1.3
# GiB khi từ chối kho arisa, không biết `ffmpeg` tới từ đâu.
#
# Test đọc mảng thật trong install.sh, không chép danh sách vào đây.
set -u
R=/home/frost-auslese/tsuki
P=0; F=0
ok()  { printf '  PASS  %s\n' "$*"; P=$((P + 1)); }
bad() { printf '  FAIL  %s\n        %s\n' "$*"; F=$((F + 1)); }

DOC="$R/PACKAGES.md"
[ -f "$DOC" ] || { echo "FAIL: không có PACKAGES.md"; exit 1; }

# Rút mảng gói từ install.sh. Nhận ra mảng theo `readonly <TÊN>=(` rồi tới dòng
# `)` đóng ở cột 0 — không đoán theo số lượng phần tử.
groups() {
    # `1d` bỏ DÒNG MỞ MẢNG `readonly PKG_BUILD=(`. Không có nó thì chữ "readonly"
    # bị tính thành tên gói, và P3 ra 67 thay vì 66 — sai lệch đúng bằng 1.
    sed -n "/^readonly $1=($/,/^)$/p" "$R/install.sh" | sed '1d' \
      | sed 's/#.*$//' | tr -s ' \t' '\n' | grep -E '^[a-z0-9][a-z0-9.+-]*$'
}
# KHÔNG đặt tên biến là GROUPS: bash có sẵn mảng readonly GROUPS chứa group id
# của user, gán đè vào đó thất bại IM LẶNG và $GROUPS vẫn ra "1000". Đã mắc:
# P1/P3 báo 0 gói, P2 báo thiếu "1000".
PKG_ARRAYS="PKG_BUILD PKG_SESSION PKG_CONFIG PKG_KEYBINDS PKG_AUR PKG_PTY PKG_ARCHIVE PKG_HARDWARE"

# --- P1: mọi gói trong mảng đều phải xuất hiện trong tài liệu -----------------
miss=""
for g in $PKG_ARRAYS; do
    for p in $(groups "$g"); do
        grep -qF -- "$p" "$DOC" || miss="$miss $p"
    done
done
if [ -z "$miss" ]; then
    ok "P1 mọi gói trong 6 mảng đều có trong PACKAGES.md"
else
    bad "P1 gói có trong code nhưng thiếu trong tài liệu" "$miss"
fi

# --- P2: tên cả sáu mảng phải có, để người đọc đối chiếu được ---------------
gmiss=""
for g in $PKG_ARRAYS; do
    grep -qF -- "$g" "$DOC" || gmiss="$gmiss $g"
done
if [ -z "$gmiss" ]; then
    ok "P2 cả 6 tên mảng đều xuất hiện trong tài liệu"
else
    bad "P2 thiếu tên mảng" "$gmiss"
fi

# --- P3: con số tổng trong tài liệu phải khớp số thật -------------------------
# Bắt được cả THÊM lẫn BỚT gói: thêm gói thì số trong .md cũ, bỏ gói thì .md
# vẫn còn tên nó.
uniq=$(for g in $PKG_ARRAYS; do groups "$g"; done | sort -u | wc -l)
if grep -qF -- "**$uniq gói**" "$DOC"; then
    ok "P3 con số '$uniq gói' trong tài liệu khớp số thật"
else
    bad "P3 con số tổng lệch" "thật là $uniq gói; tài liệu không hề ghi '$uniq gói'"
fi

# --- P4: README phải trỏ tới, và file phải tồn tại ---------------------------
if grep -q 'PACKAGES\.md' "$R/README.md" && [ -f "$R/PACKAGES.md" ]; then
    ok "P4 README trỏ tới PACKAGES.md và file tồn tại"
else
    bad "P4" "README không trỏ tới PACKAGES.md, hoặc file không tồn tại"
fi

# --- P5: các gói AUR phải được ghi là AUR ------------------------------------
# `install_pkgs` dùng pacman, chỉ `cmd_pty` dùng paru. Nếu tài liệu gói AUR
# là "từ kho chính" thì người đọc tưởng `paru` không cần.
for p in $(groups PKG_PTY); do
    grep -qE "^### \`?$p|paru" "$DOC" || bad "P5 gói AUR $p" "không thấy nói tới paru"
done
if grep -q 'paru' "$DOC"; then
    ok "P5 tài liệu nói rõ nhóm AUR đi qua paru"
else
    bad "P5" "không nhắc paru ở đâu cả"
fi

printf '\n  %d PASS, %d FAIL\n' "$P" "$F"
[ "$F" -eq 0 ]

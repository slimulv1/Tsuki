#!/usr/bin/env bash
# Test cho nhóm gói công cụ nén/giải nén (PKG_ARCHIVE) của install.sh.
#
# VÌ SAO CẦN. Người dùng yêu cầu thêm gói giải nén. Trước khi thêm, phải trả lời
# bằng ĐO chứ không đoán: máy đã có gì, thiếu gì, và gói nào thực sự cần.
#
# Kết quả đo trên CachyOS (xem install.sh để biết chi tiết):
#   7z KHÔNG tạo/nén được RAR — mã giải nén RAR "không hoàn toàn tự do", Arch tách
#   plugin ra gói `p7zip-rar`, mà gói đó KHÔNG có trong kho CachyOS. Nên `unrar`
#   là bắt buộc chứ không phải tuỳ chọn.
#
# Test trích NGUYÊN VĂN mảng gói và hàm cmd_archive. Chỉ đọc, không cài gì.
set -u
R=/home/frost-auslese/tsuki
P=0; F=0
ok()  { printf '  PASS  %s\n' "$*"; P=$((P + 1)); }
bad() { printf '  FAIL  %s\n        %s\n' "$*"; F=$((F + 1)); }
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT

# --- trích code thật ---------------------------------------------------------
sed -n '/^readonly PKG_ARCHIVE=(/,/^)/p' "$R/install.sh" > "$T/arr.sh"
sed -n '/^cmd_archive() {/,/^}/p'       "$R/install.sh" > "$T/fn.sh"
for f in "$T/arr.sh" "$T/fn.sh"; do
    [ -s "$f" ] || { printf 'FAIL: không trích được %s\n' "$f"; exit 1; }
done

# Tên gói thực sự, bằng cách SOURCE mảng chứ không parse bằng grep: có thể có
# comment, dòng trống, và dấu ngoặc. Sourcing là cách duy nhất không đoán.
# shellcheck disable=SC1090
{ cat "$T/arr.sh"; echo 'printf "%s\n" "${PKG_ARCHIVE[@]}"'; } > "$T/dump.sh"
mapfile -t PKGS < <(bash "$T/dump.sh" 2>/dev/null)
if ((${#PKGS[@]} == 0)); then
    printf 'FAIL: PKG_ARCHIVE rỗng hoặc không source được\n'; exit 1
fi

# --- C1: mảng có đúng 3 gói, không rỗng, không trùng -----------------------
# Gói rỗng sẽ lọt qua `pacman -S` rồi báo lỗi khó hiểu; trùng thì pacman báo
# "target not found" cho bản thân nó (đo trước: pacman -Sp huỷ cả lô khi một
# gói sai — xem pkgs_absent_in_repos).
empty=0; dup=0
declare -A seen=()
for p in "${PKGS[@]}"; do
    # `-z` chứ không phải `-n`: bản đầu tôi viết `[[ -n $p ]] && empty++` — đếm
    # NGƯỢC, nên 3 gói đều hợp lệ lại ra "3 mục rỗng". Đỏ vì lỗi test.
    [[ -z $p ]] && empty=$((empty + 1))
    [[ -n ${seen[$p]:-} ]] && dup=$((dup + 1))
    seen[$p]=1
done
if (( empty == 0 && dup == 0 )); then
    ok "C1 mảng sạch: ${#PKGS[@]} gói, không rỗng, không trùng (${PKGS[*]})"
else
    bad "C1 mảng bẩn" "$empty mục rỗng, $dup mục trùng"
fi

# --- C2: đủ ba công cụ -------------------------------------------------------
# unrar là bắt buộc (không có plugin RAR trong kho), 7zip cho đa định dạng, zip
# cho tạo file .zip.
for p in 7zip zip unrar; do
    if printf '%s\n' "${PKGS[@]}" | grep -qx "$p"; then
        ok "C2 có $p trong PKG_ARCHIVE"
    else
        bad "C2 thiếu $p" "hiện có: ${PKGS[*]}"
    fi
done

# --- C3: mọi gói đều tồn tại trong kho đang bật -----------------------------
# Gói không có trong kho thì `deps`-style installer sẽ bỏ qua, in cảnh báo
# "KHÔNG được cài" — đúng nhưng người dùng phải chạy lại vô ích. Bắt sớm hơn.
missing=""
for p in "${PKGS[@]}"; do
    pacman -Si "$p" >/dev/null 2>&1 || missing+=" $p"
done
if [ -z "$missing" ]; then
    ok "C3 cả ${#PKGS[@]} gói đều có trong kho"
else
    bad "C3 gói không có trong kho" "$missing"
fi

# --- C4: unrar là BẮT BUỘC, không phải tuỳ chọn ----------------------------
# Nếu ai đó xoá unrar khỏi mảng thì .rar sẽ không giải nén được, mà script vẫn
# im lặng. Ca này chặn đúng việc đó.
abody=$(cat "$T/arr.sh")
if printf '%s\n' "$abody" | grep -q 'unrar'; then
    ok "C4 unrar còn trong mảng — .rar vẫn giải nén được"
else
    bad "C4 mất unrar khỏi mảng" "không có plugin p7zip-rar trong kho, unrar là cách duy nhất đọc .rar"
fi

# --- C5: cmd_archive gọi install_pkgs với ĐÚNG tên mảng --------------------
# Truyền nhầm tên mảng là lỗi im lặng: install_pkgs dùng `local -n ref=$1`, nên
# truyền "archive" (nhãn) thay vì "PKG_ARCHIVE" sẽ tạo namref tới biến rỗng và
# vòng lặp luôn ra "đã đủ" — cài KHÔNG được gì mà vẫn báo thành công. Đã có
# ghi chú dài trong install.sh về lỗi này.
if grep -q 'install_pkgs PKG_ARCHIVE "archive"' "$T/fn.sh"; then
    ok "C5 cmd_archive truyền đúng tên mảng PKG_ARCHIVE (không nhầm sang nhãn)"
else
    bad "C5 cmd_archive truyền sai tên mảng" "$(grep 'install_pkgs' "$T/fn.sh" || echo 'không thấy lệnh install_pkgs')"
fi

# --- C6: KHÔNG nằm trong `all`, có lệnh riêng ------------------------------
# Đây là quyết định đã hỏi người dùng: 3 gói ~4.6 MiB cho việc dùng tay thì không
# nên ép vào `all`. Nhưng nếu không có lệnh riêng thì người dùng không cài được.
main_fn=$(sed -n '/^main() {/,/^}/p' "$R/install.sh")
# BỎ DÒNG COMMENT trước khi so. Bản đầu grep thẳng cả khối nên dính đúng dòng
# chú thích "KHÔNG gọi cmd_archive trong `all`" — tức C6 đỏ trong khi code ĐÚNG.
# Đã dính đúng kiểu test đỏ-vì-lỗi-test này.
all_code=$(printf '%s\n' "$main_fn" |
           sed -n '/^        all)/,/^            ;;/p' |
           grep -vE '^[[:space:]]*#')
if printf '%s\n' "$all_code" | grep -q 'cmd_archive'; then
    bad "C6 cmd_archive chạy trong \`all\`" "3 gói ~4.6 MiB cho việc dùng tay — đã hỏi và chọn không ép"
else
    ok "C6 \`all\` không gọi cmd_archive (không ép cài công cụ dùng tay)"
fi
if printf '%s\n' "$main_fn" | grep -q 'archive)   cmd_archive'; then
    ok "C6b có lệnh riêng: ./install.sh archive"
else
    bad "C6b không có lệnh \`archive\`" "không ép vào \`all\` mà cũng không lệnh riêng = không cài được"
fi

# --- C7: lệnh phải xuất hiện trong --help -----------------------------------
# usage() rút help từ khối comment đầu file, nên thêm nhánh case mà quên comment
# thì lệnh chạy được nhưng người dùng không biết nó tồn tại.
if ./install.sh --help 2>/dev/null | grep -q 'install.sh archive'; then
    ok "C7 --help có liệt kê ./install.sh archive"
else
    bad "C7 --help không có \`archive\`" "usage() rút từ khối comment đầu file — phải thêm dòng đó"
fi

# --- C8: tài liệu PACKAGES.md nói đúng sự thật về RAR ----------------------
# Dễ nhất là ghi "7z giải nén được RAR" — sai, và người đọc sẽ tải về một .rar rồi
# ngồi nhìn 7z báo lỗi. Tài liệu phải nói rõ unrar là cách duy nhất.
doc="$R/PACKAGES.md"
if grep -q 'PKG_ARCHIVE' "$doc" 2>/dev/null; then
    ok "C8 PACKAGES.md có mục PKG_ARCHIVE"
else
    bad "C8 PACKAGES.md thiếu mục PKG_ARCHIVE" "tài liệu phải khớp install.sh — có test-packages-doc.sh kiểm số liệu"
fi
if grep -qi 'p7zip-rar' "$doc" && grep -qi 'không có trong kho' "$doc"; then
    ok "C8b PACKAGES.md nói rõ p7zip-rar không có trong kho, nên phải có unrar"
else
    bad "C8b PACKAGES.md không giải thích vì sao cần unrar" \
        "đọc giả sẽ tưởng 7z đủ, tải .rar rồi ngồi nhìn lỗi"
fi

printf '\n  %d PASS, %d FAIL\n' "$P" "$F"
[ "$F" -eq 0 ]

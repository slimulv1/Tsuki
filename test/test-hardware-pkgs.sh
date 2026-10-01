#!/usr/bin/env bash
# Test cho nhóm phần cứng ngoài vi (PKG_HARDWARE) của install.sh.
#
# YÊU CẦU: kiểm và cài thêm gói để hệ thống nhận diện đủ thiết bị như USB.
#
# ĐO TRƯỚC KHI THÊM — VÀ KẾT LUẬN QUAN TRỌNG: USB KHÔNG HỎNG.
#   15 thiết bị USB trên /sys/bus/usb/devices, tất cả đều "configured"
#   journalctl -k -p err | grep -icE 'usb|acpi'  ->  0 dòng lỗi
#   lsusb  ->  15 dòng (usbutils đã có sẵn)
# Nên đây không phải sửa lỗi nhận diện, mà bổ sung phần mềm quản lý còn thiếu.
#
# LOẠI TRỪ CÓ LÝ DO:
#   TLP, xfce4-power-manager — quản lý pin. /sys/class/power_supply RỖNG =>
#     máy tĩnh, không có pin. Cài là vô dụng.
#   cups — 12.8 MiB, kéo cups-filters + libpaper. Không thấy máy in trong /dev.
#   wireplumber-pulse — pipewire-pulse đã cài và đang chạy.
#   pavucontrol — đã có sẵn.
set -u
R=/home/frost-auslese/tsuki
P=0; F=0
ok()  { printf '  PASS  %s\n' "$*"; P=$((P + 1)); }
bad() { printf '  FAIL  %s\n        %s\n' "$*"; F=$((F + 1)); }
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT

# --- trích code thật ---------------------------------------------------------
sed -n '/^readonly PKG_HARDWARE=(/,/^)/p' "$R/install.sh" > "$T/arr.sh"
sed -n '/^cmd_hardware() {/,/^}/p'   "$R/install.sh" > "$T/fn.sh"
for f in "$T/arr.sh" "$T/fn.sh"; do
    [ -s "$f" ] || { printf 'FAIL: không trích được %s\n' "$f"; exit 1; }
done
# Sourcing mảng thật, không parse bằng grep (có comment và dòng trống).
{ cat "$T/arr.sh"; echo 'printf "%s\n" "${PKG_HARDWARE[@]}"'; } > "$T/dump.sh"
mapfile -t PKGS < <(bash "$T/dump.sh" 2>/dev/null)
((${#PKGS[@]})) || { printf 'FAIL: PKG_HARDWARE rỗng\n'; exit 1; }

# --- C1: mảng sạch -----------------------------------------------------------
empty=0; dup=0
declare -A seen=()
for p in "${PKGS[@]}"; do
    [[ -z $p ]] && empty=$((empty + 1))
    [[ -n ${seen[$p]:-} ]] && dup=$((dup + 1))
    seen[$p]=1
done
if (( empty == 0 && dup == 0 )); then
    ok "C1 mảng sạch: ${#PKGS[@]} gói, không rỗng, không trùng (${PKGS[*]})"
else
    bad "C1 mảng bẩn" "$empty mục rỗng, $dup mục trùng"
fi

# --- C2: đủ 5 gói người dùng đã chọn ---------------------------------------
for p in fwupd blueman acpid gvfs-mtp gvfs-smb; do
    if printf '%s\n' "${PKGS[@]}" | grep -qx "$p"; then
        ok "C2 có $p trong PKG_HARDWARE"
    else
        bad "C2 thiếu $p" "hiện có: ${PKGS[*]}"
    fi
done

# --- C3: mọi gói đều có trong kho đang bật -----------------------------------
missing=""
for p in "${PKGS[@]}"; do
    pacman -Si "$p" >/dev/null 2>&1 || missing+=" $p"
done
if [ -z "$missing" ]; then
    ok "C3 cả ${#PKGS[@]} gói đều có trong kho"
else
    bad "C3 gói không có trong kho" "$missing"
fi

# --- C4: KHÔNG có gói quản lý pin (vô dụng trên máy tĩnh) --------------------
# Đây là bất biến suy ra từ phần cứng: /sys/class/power_supply rỗng. Nếu sau
# này ai đó thêm TLP thì phải xoá ca này, không phải im lặng bỏ qua.
no_power=$(ls /sys/class/power_supply/ 2>/dev/null | wc -l)
if (( no_power == 0 )); then
    for p in tlp xfce4-power-manager; do
        if printf '%s\n' "${PKGS[@]}" | grep -qx "$p"; then
            bad "C4 có $p" "máy không có power_supply — quản lý pin vô dụng"
        else
            ok "C4 không cài $p (máy tĩnh, /sys/class/power_supply rỗng)"
        fi
    done
else
    printf '  --   bỏ qua C4: máy này CÓ nguồn cấp (%d), quản lý pin là hợp lý\n' "$no_power"
fi

# --- C5: không cài cups khi không thấy máy in --------------------------------
if printf '%s\n' "${PKGS[@]}" | grep -qx cups; then
    bad "C5 có cups" "không thấy máy in nào trong /dev, và nó kéo cups-filters + libpaper"
else
    ok "C5 không cài cups (không thấy máy in)"
fi

# --- C6: cmd_hardware truyền ĐÚNG tên mảng ----------------------------------
# install_pkgs dùng `local -n ref=$1`; truyền nhầm nhãn sẽ tạo namref tới biến
# rỗng, vòng lặp luôn ra "đã đủ" — cài không được gì mà báo thành công.
if grep -q 'install_pkgs PKG_HARDWARE "hardware"' "$T/fn.sh"; then
    ok "C6 cmd_hardware truyền đúng tên mảng PKG_HARDWARE"
else
    bad "C6 truyền sai tên mảng" "$(grep 'install_pkgs' "$T/fn.sh" || echo 'không thấy install_pkgs')"
fi

# --- C7: KHÔNG ép vào `all`, có lệnh riêng ---------------------------------
main_fn=$(sed -n '/^main() {/,/^}/p' "$R/install.sh")
# BỎ DÙNG DÒNG COMMENT — grep thẳng sẽ dính dòng "KHÔNG gọi cmd_hardware".
all_code=$(printf '%s\n' "$main_fn" |
           sed -n '/^        all)/,/^            ;;/p' |
           grep -vE '^[[:space:]]*#')
if printf '%s\n' "$all_code" | grep -q 'cmd_hardware'; then
    bad "C7 cmd_hardware chạy trong \`all\`" "27 MiB cho thiết bị ngoài vi — đã hỏi và chọn không ép"
else
    ok "C7 \`all\` không gọi cmd_hardware (không ép 27 MiB)"
fi
if printf '%s\n' "$main_fn" | grep -q 'hardware)  cmd_hardware'; then
    ok "C7b có lệnh riêng: ./install.sh hardware"
else
    bad "C7b không có lệnh \`hardware\`" "không ép mà cũng không lệnh riêng = không cài được"
fi

# --- C8: fwupd_note không tự chạy lệnh mạng --------------------------------
# `fwupmgr upgrade` cần `refresh` tải dữ liệu trước. Script không được tự làm
# thứ lấy mạng khi người dùng chỉ chạy `./install.sh hardware`.
# Gom hai khối vào MỘT biến. Bản đầu tôi viết `cat file1 "$(sed ...)"` — hai
# lệnh thay thế dính liền nên `cat` nhận tên file khổng lồ rồi báo
# "No such file or directory", biến fn_all rỗng, và C8/C8b cùng xanh-vỏ-trắng
# theo cách vô nghĩa. Lỗi test, không phải lỗi code.
sed -n '/^fwupd_note() {/,/^}/p' "$R/install.sh" > "$T/note.sh"
fn_all=$(cat "$T/fn.sh" "$T/note.sh")
# LƯU Ý CHÍNH TẢ: lệnh là `fwupdmgr` (có chữ d). Bản đầu tôi viết regex
# `fwupmgr` — thiếu chữ d — nên nó không khớp CÁ LỆNH NÀO, kể cả lệnh sai. Thử
# chèn `fwupdmgr refresh` vào code rồi test vẫn 18/18 xanh. Đây là ca rỗng do
# so khớp sai chính tả, không phải do code đúng.
if printf '%s' "$fn_all" | grep -qE '\bfwupdmgr +(upgrade|refresh|update)\b'; then
    bad "C8 cmd_hardware tự chạy lệnh mạng của fwupdmgr" \
        "không được tự tải dữ liệu khi người dùng chỉ yêu cầu cài gói"
else
    ok "C8 không tự chạy fwupdmgr upgrade/refresh (không tự lấy mạng)"
fi
if printf '%s' "$fn_all" | grep -qF 'fwupdmgr get-devices'; then
    ok "C8b chỉ gọi lệnh đọc, không cần mạng (get-devices)"
else
    bad "C8b không có lệnh đọc nào để báo trạng thái" "cài xong không biết có thiết bị LVFS không"
fi
# Và phải thoát ên khi fwupdmgr không có (không chết cứng).
note_fn=$(sed -n '/^fwupd_note() {/,/^}/p' "$R/install.sh")
if printf '%s\n' "$note_fn" | grep -q 'return 0'; then
    ok "C8c fwupd_note thoát ên khi không có fwupdmgr"
else
    bad "C8c fwupd_note không có đường thoát khi thiếu fwupdmgr" "sẽ lỗi trên máy chưa cài"
fi

# --- C9: help + tài liệu ----------------------------------------------------
if ./install.sh --help 2>/dev/null | grep -q 'install.sh hardware'; then
    ok "C9 --help có liệt kê ./install.sh hardware"
else
    bad "C9 --help thiếu \`hardware\`" "usage() rút từ khối comment đầu file"
fi
if grep -q 'PKG_HARDWARE' "$R/PACKAGES.md" 2>/dev/null; then
    ok "C9b PACKAGES.md có mục PKG_HARDWARE"
else
    bad "C9b PACKAGES.md thiếu PKG_HARDWARE" "tài liệu phải khớp install.sh"
fi

printf '\n  %d PASS, %d FAIL\n' "$P" "$F"
[ "$F" -eq 0 ]

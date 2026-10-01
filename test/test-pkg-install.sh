#!/usr/bin/env bash
# Test cho install_pkgs/available_pkgs — phần báo cáo kết quả cài gói.
#
# VÌ SAO CẦN. Trước đây available_pkgs `return 0` khi MỌI gói đều không có
# trong kho nào đang bật, nên install_pkgs in "OK <nhóm>: xong" — tức dòng
# cuối cùng người đọc thấy là "OK" — nằm ngay dưới dòng cảnh báo "bỏ qua:
# visual-studio-code-bin discord-ptb". Hai dòng trái nhau, và dòng sai là dòng
# dễ tin. Kịch bản thật: từ chối kho arisa rồi chạy ./install.sh deps.
#
# Test trích NGUYÊN VĂN install_pkgs và available_pkgs từ install.sh.
set -u
R=/home/frost-auslese/tsuki
P=0; F=0
ok()  { printf '  PASS  %s\n' "$*"; P=$((P + 1)); }
bad() { printf '  FAIL  %s\n        %s\n' "$*"; F=$((F + 1)); }
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT

_fn() {
    sed -n '/^install_pkgs() {/,/^}/p' "$R/install.sh"
    sed -n '/^available_pkgs() {/,/^}/p' "$R/install.sh"
    sed -n '/^SKIPPED=()/,/^}/p' "$R/install.sh" 2>/dev/null
}
[ -n "$(_fn)" ] || { echo "FAIL: không trích được install_pkgs/available_pkgs"; exit 1; }

# Dựng script chạy được: nối các hàm thật với hàm phụ trợ giả.
# $1 = danh sách gói "thiếu", $2 = danh sách gói "không có trong kho nào"
gen() {
    local miss=$1 norepo=$2
    {
        _fn
        echo 'ok(){ printf "OKLINE %s\n" "$*"; }'
        echo 'warn(){ printf "WARNLINE %s\n" "$*"; }'
        echo 'step(){ :; }'
        echo 'die(){ printf "ERR %s\n" "$*"; exit 1; }'
        printf 'missing_pkgs(){ printf "%%s\\n" %s; }\n' "$miss"
        # Rỗng thì sinh hàm rỗng, KHÔNG sinh `printf "%s\n" ;` — cái đó in ra
        # một DÒNG TRỐNG, và dòng trống đi vào bad[] thành gone[""] -> lỗi
        # "bad array subscript". Lỗi của bộ sinh script, không phải của code.
        if [ -z "$norepo" ]; then
            echo 'pkgs_absent_in_repos(){ return 0; }'
        else
            printf 'pkgs_absent_in_repos(){ printf "%%s\\n" %s; }\n' "$norepo"
        fi
        echo 'root_sh(){ printf "INSTALL %s\n" "$*"; }'
        echo 'install_pkgs PKG_TEST "keybind-apps"'
    } > "$T/g.sh"
    bash "$T/g.sh" 2>&1
}

# --- K1: mọi gói đều không có trong kho → KHÔNG được in "xong" trần ----------
out=$(gen "fake-a fake-b" "fake-a fake-b")
if printf '%s\n' "$out" | grep -q '^OKLINE keybind-apps: xong$'; then
    bad "K1" "vẫn in 'OK ...: xong' khi KHÔNG gói nào được cài"
elif printf '%s\n' "$out" | grep -q 'WARNLINE keybind-apps: xong, nhưng 2 gói KHÔNG được cài'; then
    ok "K1 không gói nào được cài: báo rõ '2 gói KHÔNG được cài', không in OK"
else
    bad "K1" "không thấy dòng cảnh báo tổng kết: $(printf '%s\n' "$out" | tr '\n' ';')"
fi
if printf '%s\n' "$out" | grep -q '^INSTALL '; then
    bad "K1b" "vẫn gọi pacman -S dù không có gói nào cài được"
else
    ok "K1b không gọi pacman -S khi không cài được gì"
fi

# --- K2: một phần cài được, một phần không -----------------------------------
out=$(gen "fake-a fake-b" "fake-b")
if printf '%s\n' "$out" | grep -qE '^INSTALL .*fake-a' \
   && ! printf '%s\n' "$out" | grep -qE '^INSTALL .*fake-b'; then
    ok "K2 cài đúng phần có trong kho (fake-a), không cài fake-b"
else
    bad "K2" "sai phần cài: $(printf '%s\n' "$out" | grep INSTALL | tr '\n' ';')"
fi
if printf '%s\n' "$out" | grep -q 'WARNLINE keybind-apps: xong, nhưng 1 gói KHÔNG được cài: fake-b'; then
    ok "K2b báo đúng số gói bị bỏ qua và tên gói"
else
    bad "K2b" "dòng cảnh báo sai: $(printf '%s\n' "$out" | grep WARNLINE | tr '\n' ';')"
fi
if printf '%s\n' "$out" | grep -q '^OKLINE keybind-apps: xong$'; then
    bad "K2c" "vẫn in 'OK ...: xong' dù còn gói bị bỏ qua"
else
    ok "K2c không in 'OK ...: xong' khi còn gói bị bỏ qua"
fi

# --- K3: cài được hết → in OK sạch, không cảnh báo thừa ----------------------
out=$(gen "fake-a" "")
if printf '%s\n' "$out" | grep -q '^OKLINE keybind-apps: xong$'; then
    ok "K3 cài được hết: in OK sạch"
else
    bad "K3" "không thấy 'OK ...: xong': $(printf '%s\n' "$out" | tr '\n' ';')"
fi
if printf '%s\n' "$out" | grep -q 'WARNLINE keybind-apps'; then
    bad "K3b" "cảnh báo thừa khi không có gói nào bị bỏ qua"
else
    ok "K3b không cảnh báo thừa"
fi

# --- K4: SKIPPED phải được khai báo và xoá sạch mỗi lần gọi -----------------
if grep -qE '^SKIPPED=\(\)' "$R/install.sh"; then
    ok "K4 SKIPPED được khai báo ở cấp script (available_pkgs đặt, install_pkgs đọc)"
else
    bad "K4" "không khai báo SKIPPED ở cấp script"
fi
_n=$(grep -c 'SKIPPED=()' <(sed -n '/^install_pkgs() {/,/^}/p' "$R/install.sh"))
if [ "$_n" -ge 1 ]; then
    ok "K4b install_pkgs xoá SKIPPED trước khi gọi (không dính kết quả lần trước)"
else
    bad "K4b" "install_pkgs không xoá SKIPPED trước khi gọi available_pkgs"
fi

printf '\n  %d PASS, %d FAIL\n' "$P" "$F"
[ "$F" -eq 0 ]

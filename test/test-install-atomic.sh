#!/usr/bin/env bash
# Test cho write_xinitrc() và install_desktop_entry() của install.sh — TRÍCH
# TRỰC TIẾP từ file thật bằng sed, không chép lại logic.
#
# LÝ DO: ~/.xinitrc quyết định có vào được desktop không. Nếu nó nửa vời thì
# startx chết. Ba đường làm hỏng, đều đo được:
#   1) install.sh bị SIGKILL giữa lúc ghi.
#   2) Đĩa đầy hoặc chạm RLIMIT_FSIZE giữa lúc ghi. Đo bằng `ulimit -f 1`:
#      cat > báo "File size limit exceeded", file còn 1024 byte so với ~4000
#      cần. LƯU Ý: bash chết bằng SIGXFSZ nên `set -e` KHÔNG kịp chạy — không
#      có chỗ nào báo người dùng.
#   3) Ctrl-C đúng lúc đó.
#
# Cả ba đều tự động khỏi nếu ghi qua file tạm rồi `mv` cùng thư mục: rename(2)
# thay thế nguyên tử nên file là bản cũ hoặc bản mới, không bao giờ là bản dở.
set -u
R=/home/frost-auslese/tsuki
P=0; F=0
ok()  { printf '  PASS  %s\n' "$*"; P=$((P + 1)); }
bad() {
    # Nhiều lời giải thích có thể truyền nhiều đối số; nối lại cho khớp 2 %s.
    _m1=$1; shift
    printf '  FAIL  %s\n        %s\n' "$_m1" "$*"
    F=$((F + 1))
}
T=$(mktemp -d)
cleanup() { rm -rf "$T"; }
trap cleanup EXIT INT TERM

# --- X1: write_xinitrc ghi qua file tạm, không ghi thẳng ---------------------
# Trích đúng khối hàm ra, rồi đọc dòng lệnh ghi để xem đích là gì.
FN=$(sed -n '/^write_xinitrc() {/,/^}/p' "$R/install.sh")
if [ -z "$FN" ]; then
    bad "X1 trích được write_xinitrc()" "không tìm thấy trong install.sh"
else
    _dest=$(printf '%s\n' "$FN" | grep -oE 'cat >"?\$?\{?TSUKI_HOME\}?/\.xinitrc[^"]*"?' | head -1)
    if printf '%s\n' "$FN" | grep -q 'cat >"\$TSUKI_HOME/\.xinitrc"'; then
        bad "X1 ~/.xinitrc ghi KHÔNG nguyên tử" \
            "cat > thẳng vào đích — giết giữa lúc ghi là file nửa vời, startx chết"
    elif printf '%s\n' "$FN" | grep -qE 'cat >"\$_xtmp"'; then
        ok "X1 ~/.xinitrc ghi qua file tạm \$_xtmp"
    else
        bad "X1 không tìm thấy lệnh ghi ~/.xinitrc" \
            "trích được hàm nhưng không thấy cat > nào; hàm có thể đã đổi tên"
    fi
fi

# --- X2: có mv đưa file tạm về đích -----------------------------------------
# Đích là $_xdst (đã resolve symlink), KHÔNG phải $TSUKI_HOME/.xinitrc thẳng —
# xem X6 để hiểu vì sao.
if [ -n "$FN" ]; then
    if printf '%s\n' "$FN" | grep -qE 'mv -f -- "\$_xtmp" "\$_xdst"'; then
        ok "X2 có mv -f đưa .tmp về \$_xdst (rename(2) nguyên tử)"
    else
        bad "X2 thiếu mv đưa \$_xtmp về \$_xdst" \
            "file tạm sẽ đọng, ~/.xinitrc không bao giờ cập nhật"
    fi
fi

# --- X3: chmod PHẢI trước mv ------------------------------------------------
# rename(2) giữ quyền của file nguồn. chmod sau mv tạo ra khoảnh thời gian
# .xinitrc tồn tại với quyền mặc định umask (thường 0600).
_ch=$(printf '%s\n' "$FN" | grep -n 'chmod 644 "\$_xtmp"' | cut -d: -f1)
_mv=$(printf '%s\n' "$FN" | grep -n 'mv -f -- "\$_xtmp"' | cut -d: -f1)
if [ -n "$_ch" ] && [ -n "$_mv" ] && [ "$_ch" -lt "$_mv" ]; then
    ok "X3 chmod 644 file tạm TRƯỚC mv (dòng $_ch < $_mv)"
elif [ -z "$_ch" ]; then
    bad "X3 không chmod file tạm" \
        "rename giữ quyền file nguồn; không chmod thì .xinitrc mang quyền umask"
else
    bad "X3 chmod SAU mv" "dòng $_ch > $_mv — có khoảng thời gian file sai quyền"
fi

# --- X4: mv thất bại phải được báo, không im lặng ---------------------------
# Nếu mv hỏng mà không báo, lần chạy sau thấy ~/.xinitrc cũ tưởng đã cài xong.
if [ -n "$FN" ]; then
    if printf '%s\n' "$FN" | grep -qE 'if ! mv -f -- "\$_xtmp"'; then
        ok "X4 mv thất bại được bắt (if ! mv)"
    else
        bad "X4 mv không được bắt lỗi" \
            "hỏng thì im lặng, người dùng tưởng .xinitrc đã cài"
    fi
    if printf '%s\n' "$FN" | grep -qE 'rm -f -- "\$_xtmp"'; then
        ok "X4b file tạm được dọn khi mv hỏng (không sót trong ~)"
    else
        bad "X4b mv hỏng thì sót file tạm" "lần sau ghi đè, lại nữa thì đầy nhà"
    fi
fi

# --- X6: mv KHÔNG được phá symlink ------------------------------------------
# HỒI QUY do tôi tự gây khi thêm atomic write. Đo trên cả hai cách, đích là
# symlink -> kho dotfiles (đúng tình huống symlink_guard hỏi trước):
#     cat > ~/.xinitrc        symlink CÒN, nội dung kho dotfiles ĐƯỢC ghi
#     tmp + mv ~/.xinitrc     symlink MẤT, kho dotfiles KHÔNG đổi
# mv thay chính symlink bằng file thật -> làm mất đúng thứ symlink_guard đã
# hỏi người dùng ("vẫn ghi đè file đích?"), và nội dung mới rơi vào đâu đó
# không ai biết. Lỗi này làm test-symlink-guard.sh C4 FAIL, nhưng bản thân
# test đó không nói ra nguyên nhân — nên ở đây mới có ca riêng.
if [ -n "$FN" ]; then
    if printf '%s\n' "$FN" | grep -qE 'if \[\[ -L \$TSUKI_HOME/\.xinitrc \]\]'; then
        ok "X6 write_xinitrc kiểm tra đích có phải symlink không"
    else
        bad "X6 write_xinitrc KHÔNG xử lý đích là symlink" \
            "mv sẽ thay chính symlink bằng file thật — phá kho dotfiles của người dùng"
    fi
    if printf '%s\n' "$FN" | grep -qE 'readlink -f -- "\$TSUKI_HOME/\.xinitrc"'; then
        ok "X6b có readlink -f để lấy file thật mà symlink trỏ tới"
    else
        bad "X6b không có readlink -f" "mv sẽ phá symlink"
    fi
    # File tạm phải cùng thư mục với file THẬT (đã resolve), không phải cùng
    # thư mục với symlink — nếu không, mv có thể phải copy, mất nguyên tử.
    if printf '%s\n' "$FN" | grep -qE '_xtmp="\$_xdst\.tsuki-new'; then
        ok "X6c file tạm đặt cạnh file thật (\$_xdst.tsuki-new) để rename nguyên tử"
    else
        bad "X6c file tạm không đặt cạnh file thật" \
            "mv qua filesystem khác = copy, mất tính nguyên tử"
    fi
    if printf '%s\n' "$FN" | grep -qE 'mv -f -- "\$_xtmp" "\$_xdst"'; then
        ok "X6d mv vào \$_xdst (đã resolve) chứ không vào đường dẫn có symlink"
    else
        bad "X6d mv vào \$TSUKI_HOME/.xinitrc thay vì \$_xdst" "phá symlink"
    fi
fi
# --- Y1: Tsuki.desktop cũng phải ghi atomic ---------------------------------
# File nằm trong /usr/share/xsessions, display manager quét MỖI LẦN vẽ màn
# hình đăng nhập. File dở -> mất mục Tsuki, người dùng tưởng session hỏng.
DN=$(sed -n '/^install_desktop_entry() {/,/^}/p' "$R/install.sh")
if [ -z "$DN" ]; then
    bad "Y1 trích được install_desktop_entry()" "không tìm thấy"
elif printf '%s\n' "$DN" | grep -q 'cat > "\$d/Tsuki.desktop"'; then
    bad "Y1 Tsuki.desktop ghi KHÔNG nguyên tử" \
        "cat > thẳng vào /usr/share — display manager có thể đọc file dở"
elif printf '%s\n' "$DN" | grep -qE 'cat > "\$t"'; then
    ok "Y1 Tsuki.desktop ghi qua file tạm \$t"
else
    bad "Y1 không thấy lệnh ghi Tsuki.desktop qua file tạm"
fi

# --- Y2: file tạm của .desktop phải CÙNG THƯ MỤC với đích -----------------
# Khác thư mục thì mv phải copy, mất tính nguyên tử.
if [ -n "$DN" ]; then
    if printf '%s\n' "$DN" | grep -qE 't="\$d/\.Tsuki\.desktop\.new'; then
        ok "Y2 file tạm nằm cùng thư mục đích (\$d/...)"
    else
        bad "Y2 file tạm .desktop không cùng thư mục đích" \
            "mv phải copy sang filesystem khác, mất tính nguyên tử"
    fi
fi

# --- Z1: CHỨNG MINH BẰNG THỰC HÀNH -----------------------------------------
# SAI SÓT ĐÃ MẮC, ghi lại để không lặp lại: tôi TỪNG tin rằng ghi qua .tmp rồi
# mv là đủ. Đo mới thấy SAI — rename(2) chỉ bảo đảm thay thế nguyên tử, không
# bảo đảm file tạm CÓ NỘI DUNG. Với heredoc vượt RLIMIT_FSIZE:
#     bash: cannot create temp file for here-document: No space left on device
# ...và lệnh mv VẪN CHẠY, thay file tốt bằng file 0 byte.
# Nên thiết kế đúng là ba bước: ghi .tmp -> kiểm .tmp KHÔNG RỖNG -> mv.
# Hai ca dưới đây đo đúng ba bước đó, và so với cách chỉ có hai bước.
_write3() {
    local dir=$1 limit=$2 guard=$3
    mkdir -p "$dir"
    printf 'BAN CU — chay duoc\n' > "$dir/target"
    (
        ulimit -f "$limit" 2>/dev/null || exit 9
        big=$(awk 'BEGIN{for(i=0;i<20000;i++) print "dong lon vuot gioi han kich thuoc"}')
        cat > "$dir/.t.new" <<XEOF
$big
XEOF
        if [ "$guard" = yes ] && [ ! -s "$dir/.t.new" ]; then
            rm -f "$dir/.t.new"
            exit 3          # dừng, KHÔNG mv
        fi
        mv -f "$dir/.t.new" "$dir/target" 2>/dev/null || exit 8
    ) >/dev/null 2>&1
    grep -q 'BAN CU' "$dir/target" 2>/dev/null && echo keep || echo lost
}

# 20 block * 512 = 10240 byte. payload 20000 dong ~ 900KB: chắc chắn vượt.
if [ "$(_write3 "$T/w1" 20 no)" = lost ]; then
    ok "Z1 KHÔNG có bước kiểm -> bản cũ bị thay bằng file rỗng (lỗi đang sửa)"
else
    bad "Z1 cách ghi 2 bước lại không hỏng" \
        "giới hạn không đủ nhỏ, test không chứng minh được gì"
fi
if [ "$(_write3 "$T/w2" 20 yes)" = keep ]; then
    ok "Z1b có bước kiểm -> giữ nguyên bản cũ, vẫn vào được desktop"
else
    bad "Z1b có bước kiểm mà bản cũ vẫn mất" "logic kiểm sai"
fi

# Ghi thẳng vào đích: bản cũ bị cắt cụt, không phải file 0 byte — cũng hỏng.
run_direct() {
    local dir=$1 limit=$2
    mkdir -p "$dir"
    printf 'BAN CU — chay duoc\n' > "$dir/target"
    (
        ulimit -f "$limit" 2>/dev/null || exit 9
        big=$(awk 'BEGIN{for(i=0;i<20000;i++) print "dong lon vuot gioi han kich thuoc"}')
        cat > "$dir/target" <<XEOF
$big
XEOF
    ) >/dev/null 2>&1
    grep -q 'BAN CU' "$dir/target" 2>/dev/null && echo keep || echo lost
}
if [ "$(run_direct "$T/w3" 20)" = lost ]; then
    ok "Z2 ghi thẳng vào đích -> bản cũ bị phá (khác kiểu với 2 bước)"
else
    bad "Z2 ghi thẳng lại giữ được bản cũ" "giới hạn không đủ nhỏ"
fi

# --- X7: CHỨNG MINH BẰNG HÀNH VI THẬT — symlink phải sống sót -------------
# Không đọc văn bản: dựng symlink thật rồi chạy đúng logic resolve+atomic.
_slink_case() {
    local dir=$1 resolve=$2
    mkdir -p "$dir/store" "$dir/home"
    printf '# ban cu trong kho dotfiles\n' > "$dir/store/xinitrc"
    ln -sf "$dir/store/xinitrc" "$dir/home/.xinitrc"
    local dst="$dir/home/.xinitrc"
    if [ "$resolve" = yes ]; then
        dst=$(readlink -f -- "$dir/home/.xinitrc" 2>/dev/null) || dst="$dir/home/.xinitrc"
        [ -n "$dst" ] || dst="$dir/home/.xinitrc"
    fi
    local tmp="$dst.tsuki-new.$$"
    printf '# noi dung moi\n' > "$tmp" 2>/dev/null || return 1
    mv -f "$tmp" "$dst" 2>/dev/null || return 1
    # trả về: "symlink-con" neu con la symlink, "mat" neu bi pha
    [ -L "$dir/home/.xinitrc" ] && echo symlink-con || echo mat
}
if [ "$(_slink_case "$T/s1" no)" = mat ]; then
    ok "X7 KHÔNG resolve -> mv phá mất symlink (hồi quy đã gây)"
else
    bad "X7 không resolve mà symlink vẫn còn" "kịch bản không mô phong được hồi quy"
fi
if [ "$(_slink_case "$T/s2" yes)" = symlink-con ]; then
    ok "X7b có resolve -> symlink sống sót, mv ghi vào file thật"
else
    bad "X7b có resolve mà symlink vẫn bị phá" "logic resolve sai"
fi
# và nội dung mới phải nằm trong kho dotfiles — đó là điều symlink_guard hỏi
if grep -q 'noi dung moi' "$T/s2/store/xinitrc" 2>/dev/null; then
    ok "X7c nội dung mới nằm trong kho dotfiles (đúng ý người dùng đã đồng ý)"
else
    bad "X7c nội dung mới KHÔNG vào kho dotfiles" \
        "nội dung rơi mất hoặc ghi sai chỗ, mà backup lại đã lấy rồi"
fi
# Đây là điều kiện để Z1b được bảo đảm trong install.sh, không chỉ trong test.
if [ -n "$FN" ]; then
    if printf '%s\n' "$FN" | grep -qE '\[\[ ! -s \$_xtmp \]\]'; then
        ok "X5 write_xinitrc kiểm \$_xtmp KHÔNG rỗng trước mv"
    else
        bad "X5 write_xinitrc KHÔNG kiểm file tạm rỗng" \
            "đo được: heredoc vượt giới hạn tạo file 0 byte, mv vẫn chạy, xoá .xinitrc tốt"
    fi
fi
if [ -n "$DN" ]; then
    if printf '%s\n' "$DN" | grep -qE '\[ ! -s "\$t" \]'; then
        ok "Y3 install_desktop_entry kiểm \$t KHÔNG rỗng trước mv"
    else
        bad "Y3 install_desktop_entry KHÔNG kiểm file tạm rỗng" \
            "Tsuki.desktop đang tốt sẽ bị thay bằng file 0 byte -> mất session"
    fi
fi

printf '\n  %d PASS, %d FAIL\n' "$P" "$F"
[ "$F" -eq 0 ]

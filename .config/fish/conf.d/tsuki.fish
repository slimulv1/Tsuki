# conf.d/tsuki.fish — bật Tsuki (dwm) từ TTY.
#
# Kịch bản chính: cài CachyOS/Arch KHÔNG chọn display manager, khởi động
# thẳng vào TTY, đăng nhập, gõ `dwm` -> vào thẳng session dwm.
#
# Hàm này tự dựng những thứ còn thiếu thay vì chỉ báo lỗi, vì trên máy mới
# cài gì cũng chưa có: chưa `~/.xinitrc`, có thể chưa build binary.
#
# Dùng function chứ không phải `alias` vì cần kiểm tra trước khi chạy.
# `alias dwm ...` không kiểm tra được gì: bật X thứ hai sẽ hỏng, thiếu gói
# thì báo lỗi mơ hồ.
#
# Lưu ý: hàm này che binary `dwm` trong fish. Bên trong Tsuki không sao —
# scripts/run.sh là #!/bin/sh (dash không có alias) nên `type dwm` vẫn ra
# binary thật. Ngoài TTY mà cần binary thì gõ `command dwm`.

function __tsuki_repo --description 'Thư mục repo Tsuki'
    # Nhiều chỗ vì người dùng clone ở nhiều tên khác nhau. `~/Tsuki` không phải
    # `~/tsuki`: filesystem này phân biệt hoa/thường, thiếu một bản thì hỏng.
    for d in ~/tsuki ~/Tsuki ~/dwm ~/.config/dwm ~/.config/tsuki
        test -f "$d/scripts/run.sh"; and echo $d; and return 0
    end
    # Cuối cùng thử chính thư mục cha của file đang chạy (conf.d/../..).
    set -l self (status --current-filename)
    test -n "$self"; and begin
        set -l up (builtin realpath "$self" 2>/dev/null)
        test -f "$up/scripts/run.sh"; and echo (dirname "$up"); and return 0
    end
    return 1
end

function __tsuki_have_dwm --description 'dwm đã được cài vào PATH chưa'
    # `command -s`, KHÔNG phải `type -q`: `type -q dwm` khớp luôn với chính hàm
    # `dwm` ở trên nên luôn trả về đúng, kể cả trên máy mới chưa build gì.
    # `command -s` chỉ tra executable, bỏ qua function/alias.
    command -s dwm >/dev/null 2>&1
end

function dwm --description 'Bật Tsuki (dwm) từ TTY'
    set -l repo (__tsuki_repo)

    # 1. Chưa clone repo — không có gì để chạy
    if test -z "$repo"
        echo "tsuki: chưa có mã nguồn Tsuki." >&2
        echo "  git clone https://github.com/slimulv1/Tsuki.git ~/tsuki" >&2
        echo "  cd ~/tsuki && ./install.sh" >&2
        return 1
    end

    # 2. Đã ở trong X session — không được bật X thứ hai
    if set -q DISPLAY; and test -n "$DISPLAY"
        echo "tsuki: $DISPLAY đang chạy, không thể bật X thứ hai." >&2
        echo "        Thoát về TTY trước: Super+Ctrl+Q trong dwm." >&2
        return 1
    end

    # 3. Chưa có ~/.xinitrc -> startx sẽ mở X trống rồi đứt. Tự sinh.
    if not test -f ~/.xinitrc
        echo "tsuki: chưa có ~/.xinitrc, đang tạo..." >&2
        printf 'export PATH="/usr/local/bin:$PATH"\nexec "%s/scripts/run.sh"\n' "$repo" \
            >~/.xinitrc
        chmod 644 ~/.xinitrc
    end

    # 4. Chưa có startx (gói xorg-xinit) — báo đúng gói cần cài
    if not type -q startx
        echo "tsuki: thiếu 'startx'. Cài:  sudo pacman -S xorg-xinit" >&2
        return 1
    end

    # 5. Chưa build binary dwm -> hỏi trước rồi build, không tự sudo
    if not __tsuki_have_dwm
        echo "tsuki: chưa có binary dwm. Build:  cd $repo && ./install.sh build" >&2
        return 1
    end

    # startx chạy tới khi dwm thoát, exec để không còn prompt lơ lửng giữa
    # session. Thoát X là thoát luôn về TTY.
    exec startx
end

function tsuki-status --description 'Trạng thái X session hiện tại'
    if not set -q DISPLAY; or test -z "$DISPLAY"
        echo "TTY thuần — chưa có X session."
        echo "Gõ 'dwm' để bật Tsuki."
        return 0
    end

    set -l v (xdpyinfo 2>/dev/null | string match -r 'vendor name:\s*(.*)')
    echo "DISPLAY = $DISPLAY"
    test -n "$v"; and echo "vendor  = $v"
    if pgrep -x dwm >/dev/null
        echo "dwm     = đang chạy (pid "(pgrep -x dwm | head -1)")"
    else
        echo "dwm     = KHÔNG chạy"
    end
end

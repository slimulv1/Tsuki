#!/usr/bin/env bash
# Test cho cảnh báo "khởi động lại Thunar" trong cmd_deps, và tài liệu đi kèm.
#
# VÌ SAO CẦN. Sidebar Thunar không phải đọc cấu hình rồi vẽ — nó dựng MODEL
# MỘT LẦN lúc mở cửa sổ. `thunar_shortcuts_model_places()` trong
# thunar-shortcuts-model.c:1172-1182 kiểm `thunar_g_vfs_is_uri_scheme_supported
# ("trash")` rồi mới thêm mục Thùng rác; gọi từ `thunar_shortcuts_model_new()`.
# Cài `gvfs` xong mà Thunar vẫn đang mở thì nó đã bỏ qua nhánh đó và không tự
# dựng lại.
#
# ĐO TRÊN MÁY NÀY:
#     PID     STARTED                        COMMAND
#     255569  Thu Oct  1 11:45:12 2026      Thunar
#     646609  Thu Oct  1 13:24:21 2026      gvfsd
# Thunar cũ hơn 1 giờ 43 phút. Backend `trash://` chạy tốt (gio list trash://
# trả về danh sách), nhưng sidebar của Thunar không có mục Thùng rác.
#
# LỖI ĐO CỦA TÔI TRONG LÚC CHẨN ĐOÁN. `pgrep -a thunar` trả về rỗng, tôi kết
# luận Thunar không chạy. SAI: tên tiến trình là `Thunar` — HOA chữ T đầu — còn
# `pgrep` phân biệt hoa thường. Đã kiểm lại bằng `ps -eo comm` thấy PID 255569.
# Đây là lý do cảnh báo trong install.sh dùng `pgrep -x Thunar`, và lý do
# TROUBLESHOOTING.md nêu cạm bẫy này.
set -u
R=/home/frost-auslese/tsuki
P=0; F=0
ok()  { printf '  PASS  %s\n' "$*"; P=$((P + 1)); }
bad() { printf '  FAIL  %s\n        %s\n' "$*"; F=$((F + 1)); }
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT

deps_fn=$(sed -n '/^cmd_deps() {/,/^}/p' "$R/install.sh")
[ -n "$deps_fn" ] || { printf 'FAIL: không trích được cmd_deps\n'; exit 1; }

# --- C1: cảnh báo phải nằm trong cmd_deps ----------------------------------
# Cài `thunar-archive-plugin` và `gvfs` xảy ra ở cmd_deps, nên cảnh báo phải ở
# đó chứ không ở main() — main() chạy cảnh báo cả khi người dùng chỉ muốn
# `./install.sh archive`, lúc đó cảnh báo vô nghĩa.
if printf '%s\n' "$deps_fn" | grep -q 'pgrep -x Thunar'; then
    ok "C1 cmd_deps có cảnh báo khởi động lại Thunar"
else
    bad "C1 cmd_deps không cảnh báo" "sau khi cài plugin mà Thunar đang mở thì vô dụng"
fi

# --- C2: phải dùng tên tiến trình ĐÚNG HOA THƯỜNG -------------------------
# `pgrep -x thunar` (chữ thường) không bắt được tiến trình tên `Thunar`. Đây
# chính là lỗi tôi đã mắc. Ca này chặn tái diễn.
if printf '%s\n' "$deps_fn" | grep -qE 'pgrep -x thunar\b'; then
    bad "C2 dùng pgrep -x thunar (chữ thường)" "tiến trình tên 'Thunar' — pgrep phân biệt hoa thường nên không bắt"
else
    ok "C2 dùng pgrep -x Thunar (đúng hoa thường)"
fi

# --- C3: cảnh báo phải nói cách khắc phục ----------------------------------
# Nói "cần khởi động lại" mà không nói cách thì người dùng không biết làm gì.
if printf '%s\n' "$deps_fn" | grep -q 'pkill -x Thunar'; then
    ok "C3 cảnh báo kèm lệnh khắc phục (pkill -x Thunar)"
else
    bad "C3 cảnh báo không nói cách khởi động lại" "chỉ bảo phải restart mà không chỉ lệnh"
fi

# --- C4: chỉ cảnh báo khi Thunar THẬT SỰ đang mở ---------------------------
# Báo trong `if pgrep` chứ không báo vô điều kiện — cảnh báo khi không có gì sai
# thì người dùng mất niềm tin vào cảnh báo, giống báo động giả ở mục repo-lock.
if printf '%s\n' "$deps_fn" \
   | grep -qE 'if pgrep -x Thunar.*then'; then
    ok "C4 cảnh báo có điều kiện, chỉ nói khi Thunar thật sự đang mở"
else
    bad "C4 cảnh báo không có điều kiện pgrep" "báo động giả khi Thunar không chạy"
fi

# --- C5: TROUBLESHOOTING.md phải có mục này -------------------------------
# Nếu lỗi này tái diễn với người khác, họ cần tra được. Và phải nêu cạm bẫy
# `pgrep thunar` — vì đó là chỗ dễ mắc nhất khi tự chẩn đoán.
doc="$R/TROUBLESHOOTING.md"
if grep -q 'Thunar không có mục' "$doc" 2>/dev/null; then
    ok "C5 TROUBLESHOOTING.md có mục sidebar Thunar"
else
    bad "C5 TROUBLESHOOTING.md thiếu mục" "lỗi này tái diễn là do không có tài liệu"
fi
if grep -q 'Giải nén' "$doc" && grep -q '7z.tap' "$doc"; then
    ok "C5b TROUBLESHOOTING.md nói rõ plugin không dùng 7z (7z.tap không tồn tại)"
else
    bad "C5b TROUBLESHOOTING.md không nói về 7z.tap" \
        "người đọc sẽ cài 7z rồi tưởng xong — đúng lỗi tôi đã mắc"
fi
if grep -q 'pgrep' "$doc" && grep -q 'HOA' "$doc"; then
    ok "C5c TROUBLESHOOTING.md cảnh báo cạm bẫy pgrep phân biệt hoa thường"
else
    bad "C5c TROUBLESHOOTING.md không cảnh báo cạm bẫy pgrep" \
        "chính tôi đã mắc lỗi này khi chẩn đoán — người khác cũng sẽ mắc"
fi

# --- C6: hành vi thật — pgrep -x Thunar bắt được, pgrep -x thunar không -----
# Chỉ khi máy này đang mở Thunar. Bỏ qua nếu không — đây là ca kiểm môi
# trường, không kiểm code.
if pgrep -x Thunar >/dev/null 2>&1; then
    if pgrep -x thunar >/dev/null 2>&1; then
        bad "C6 pgrep -x thunar CŨNG bắt được" "cảnh báo SC2086: pgrep có thể không phân biệt hoa thường ở đây — cần xác minh"
    else
        ok "C6 pgrep -x Thunar bắt được, pgrep -x thunar không (đúng như đo)"
    fi
else
    printf '  --   bỏ qua C6: máy này không mở Thunar lúc chạy test\n'
fi

# --- C7: nếu Thunar có thật sự đang mở, cảnh báo phải xuất hiện khi deps chạy
# Chạy thật phần cảnh báo với PID giả để không phải cài gói. Không chạy
# cmd_deps (nó sẽ gọi pacman), chỉ trích riêng nhánh cảnh báo.
if pgrep -x Thunar >/dev/null 2>&1; then
    blk=$(printf '%s\n' "$deps_fn" |
          sed -n '/if pgrep -x Thunar/,/fi/p')
    if [ -n "$blk" ]; then
        # ĐỊNH NGHĨA warn TRƯỚC khối lệnh. Bản đầu tôi đặt sau, nên bash báo
        # "warn: command not found" và nhánh cảnh báo im lặng — đỏ vì lỗi test.
        out=$(printf 'warn(){ printf "  ! %%s\\n" "$*"; }\n%s\n' "$blk" | bash 2>&1)
        if printf '%s' "$out" | grep -q 'pkill -x Thunar'; then
            ok "C7 nhánh cảnh báo chạy thật in ra lệnh khắc phục"
        else
            bad "C7 nhánh cảnh báo không in lệnh khắc phục" "output: $out"
        fi
    else
        bad "C7 không trích được nhánh cảnh báo" "nội dung cmd_deps đã đổi hình dạng"
    fi
else
    printf '  --   bỏ qua C7: máy này không mở Thunar lúc chạy test\n'
fi

printf '\n  %d PASS, %d FAIL\n' "$P" "$F"
[ "$F" -eq 0 ]

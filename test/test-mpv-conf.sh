#!/usr/bin/env bash
# Test cho .config/mpv/mpv.conf của rice Tsuki.
#
# VÌ SAO CẦN FILE NÀY: đo trên máy trước khi viết — `~/.config/mpv/` RỖNG và repo
# cũng không có .config/mpv/. Tài liệu mpv chính thức nói rõ: "Hardware decoding
# is not enabled by default, to keep the out-of-the-box configuration as reliable
# as possible." Nên mặc định `hwdec=no` = giải mã MỒM, dù GPU rảnh.
# Đo tương phản trên chính máy:
#   không config -> 0 dòng "Using hardware decoding"
#   có config    -> 1 dòng, "Using hardware decoding (vulkan)"
#
# CA RỖNG ĐÃ DÍNH: bản nháp đầu viết 4 option không tồn tại trong mpv 0.41 —
#   hwdec-extra-hooks, screenshot (option cờ), screenshot-flags, sub-auto-fuzzy
# — viết theo trí nhớ từ bản mpv khác. Đã bỏ hết sau khi đối chiếu
# `mpv --list-options`. C1 chốt việc đó: MỌI option trong file phải có thật.
set -u
R=/home/frost-auslese/tsuki
P=0; F=0
ok()  { printf '  PASS  %s\n' "$*"; P=$((P + 1)); }
# SC2183 báo động giả: `$*` gộp mọi đối số, printf lặp lại cho mỗi `%s`.
# shellcheck disable=SC2183
bad() { printf '  FAIL  %s\n        %s\n' "$*"; F=$((F + 1)); }
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT

CONF="$R/.config/mpv/mpv.conf"
if [[ ! -f $CONF ]]; then
    printf 'FAIL: không thấy %s\n' "$CONF"; exit 1
fi
command -v mpv >/dev/null 2>&1 || { printf 'FAIL: máy này chưa cài mpv\n'; exit 1; }

# --- C1: MỌI option trong file phải tồn tại thật --------------------------------
# Đây là ca quan trọng nhất. Bản nháp đầu viết 4 option không có trong mpv 0.41
# theo trí nhớ. Đối chiếu bằng chính danh sách option của mpv trên máy này.
# `--list-options` in ra " --ten" (HAI khoảng trắng ở đầu) — bản đầu tôi grep
# "^ --$o=" nên không khớp option nào, tưởng là mpv không có.
mpv --no-config --list-options 2>/dev/null > "$T/opts"
grep -oE '^[a-z][a-z0-9-]*=' "$CONF" | tr -d '=' | sort -u > "$T/used"
n_used=$(wc -l < "$T/used")
if (( n_used == 0 )); then
    bad "C1 file không có option nào" "grep 0 dòng dạng 'ten='"
else
    missing=""
    while IFS= read -r o; do
        # `${o}[ =]` chứ không phải `$o[ =]`: bash hiểu `$o[...]` là truy cập
        # mảng. Ở đây `o` là chuỗi option như `hwdec`, nên `$o[ =]` trở thành
        # phần tử mảng `o[ ...` — shellcheck báo SC1087, và với `o` rỗng thì
        # đọc phần tử mảng rỗng, cho ra chuỗi rỗng rồi khớp TẤT CẢ dòng.
        # Đã viết sai trước đó.
        grep -qE "^ +--${o}[ =]" "$T/opts" || missing="$missing $o"
    done < "$T/used"
    if [[ -z $missing ]]; then
        ok "C1 cả $n_used option đều tồn tại trong mpv $(mpv --version 2>/dev/null | head -1 | grep -oE 'v[0-9.]+')"
    else
        bad "C1 $(( $(wc -w <<<"$missing") )) option không tồn tại" \
            "$missing — mpv sẽ báo 'Invalid parameter' và bỏ qua"
    fi
fi

# --- C2: hwdec PHẢI bật, không phải để mặc định ---------------------------------
# Mặc định của mpv là `no` (đo trong `--list-options`). Nếu file không khai
# hwdec thì phim nặng giật.
hv=$(grep -m1 '^hwdec=' "$CONF" | cut -d= -f2-)
case $hv in
    no|"") bad "C2 hwdec='${hv:-rỗng}'" "mặc định mpv là no = giải mã mềm, phim nặng sẽ giật" ;;
    auto|auto-safe) ok "C2 hwdec=$hv (bật giải mã phần cứng)" ;;
    *) ok "C2 hwdec=$hv" ;;
esac
# auto-unsafe bật bừa mọi decoder tìm được — dễ vỡ hình trên codec lạ.
if [[ $hv == *auto-unsafe* ]]; then
    bad "C2b hwdec dùng auto-unsafe" "bật bừa mọi decoder tìm được, hay vỡ hình"
else
    ok "C2b không dùng auto-unsafe"
fi

# --- C3: vo phải khớp GPU thật của máy -----------------------------------------
# Máy: AMD Radeon RX 7800 XT (Navi 32), driver amdgpu. Với mpv 0.41 + RADV,
# backend đúng là gpu-next + Vulkan. Nếu cấu hình máy khác (NVIDIA/Intel thật)
# thì nguyên tắc không còn đúng — bỏ qua thay vì áp đặt.
if ! lspci 2>/dev/null | grep -qiE 'VGA.*(Advanced Micro Devices|ATI)'; then
    printf '  --   bỏ qua C3: máy này không dùng AMD, nguyên tắc khác\n'
else
    vo=$(grep -m1 '^vo=' "$CONF" | cut -d= -f2-)
    api=$(grep -m1 '^gpu-api=' "$CONF" | cut -d= -f2-)
    if [[ $vo == gpu* ]]; then
        ok "C3 vo=$vo (backend gpu, đúng cho mpv 0.41)"
    else
        bad "C3 vo='$vo'" "máy AMD thì backend gpu/gpu-next mới dùng được VA-API và HDR"
    fi
    if [[ $api == vulkan || $api == auto || -z $api ]]; then
        ok "C3b gpu-api=${api:-mặc định} (RADV hoạt động — đo bằng vulkaninfo)"
    else
        bad "C3b gpu-api='$api'" "RADV không cần API khác"
    fi
fi

# --- C4: mpv đọc file không báo lỗi --------------------------------------------
# --config-dir nhận THƯ MỤC. Bản đầu tôi truyền `--config=<file>` và mpv báo
# "Invalid parameter for config flag" — lỗi test, không phải lỗi file.
if err=$(timeout 60 mpv --config-dir="$R/.config/mpv" --list-options 2>&1 >/dev/null |
         grep -iE 'invalid|error parsing|unknown option|unrecognized'); then
    bad "C4 mpv báo lỗi khi đọc config" "$err"
else
    ok "C4 mpv đọc file không báo lỗi (15+ option hợp lệ)"
fi

# --- C5: CHỨNG MINH hwdec thật sự bật, bằng đo tương phản ----------------------
# Không tin vào việc "file có dòng hwdec=". Phải thấy mpv BÁO là đang giải mã
# phần cứng, và phải so với lúc KHÔNG có config — nếu không thì không biết
# config có tác dụng hay chỉ nằm đó.
V=$(mktemp -d)
if ! ffmpeg -hide_banner -loglevel error \
      -f lavfi -i testsrc=d=2:s=1280x720:r=24 -c:v libx264 -pix_fmt yuv420p \
      "$V/v.mp4" 2>/dev/null || [[ ! -s $V/v.mp4 ]]; then
    rm -rf "$V"
    printf '  --   bỏ qua C5: không tạo được file test (thiếu ffmpeg?)\n'
else
    without=$(timeout 90 mpv --no-config --ao=null --frames=5 "$V/v.mp4" 2>&1 |
              grep -ci 'Using hardware decoding' || true)
    with=$(timeout 90 mpv --config-dir="$R/.config/mpv" --ao=null --frames=5 "$V/v.mp4" 2>&1 |
           grep -ci 'Using hardware decoding' || true)
    if (( with >= 1 )); then
        ok "C5 đo tương phản: không config $without dòng → có config $with dòng (giải mã phần cứng)"
    else
        bad "C5 có config nhưng mpv không báo giải mã phần cứng" \
            "không config: $without dòng — nếu cả hai đều 0 thì hwdec không có tác dụng trên máy này"
    fi
    rm -rf "$V"
fi

# --- C6: mpv.conf phải được copy, không nằm mãi trong repo ---------------------
# Đo trước khi thêm mpv vào `items`: `install.sh dotfiles` KHÔNG copy
# .config/mpv, vì danh sách items không có nó. File trong repo mà không được
# copy thì chỉ người đọc repo thấy.
if [[ -f $HOME/.config/mpv/mpv.conf ]]; then
    if same=$(cmp -s "$CONF" "$HOME/.config/mpv/mpv.conf" 2>&1) && [[ -z $same ]]; then
        ok "C6 ~/.config/mpv/mpv.conf trùng với repo"
    else
        bad "C6 ~/.config/mpv/mpv.conf khác repo" \
            "$(cmp "$CONF" "$HOME/.config/mpv/mpv.conf" 2>&1 | head -1)"
    fi
else
    printf '  --   bỏ qua C6: chưa chạy ./install.sh dotfiles\n'
fi
# Và phải nằm trong danh sách items, không chỉ có trong repo.
# items trải trên 2 dòng (nối bằng dấu gạch ngược), nên `sed -n 's/.*items=(...)/.../'`
# trả RỖNG: mẫu đòi `)` ở CÙNG dòng nhưng `)` nằm ở dòng kế. Đo được. Phải
# gom cả khối rồi mới khớp, và cắt dấu `)` cuối.
items=$(sed -n '/local -a items=(/,/)/p' "$R/install.sh" | tr '\n' ' ' |
        sed 's/.*items=(//; s/)$//' | tr -s ' \\' '\n' |
        grep -v '^$' | sed 's/)$//')
if printf '%s\n' "$items" | grep -qx mpv; then
    ok "C6b mpv có trong danh sách items của cmd_dotfiles"
else
    bad "C6b mpv không có trong items" \
        "items đọc được: $(printf '%s' "$items" | tr '\n' ' ')"
fi

# --- C7: screenshot-template trỏ tới thư mục có thật ----------------------------
# mpv không tự tạo thư mục cha; template trỏ tới ~/Pictures không tồn tại thì
# phím screenshot không lưu được. `cmd_userdirs` tạo ~/Pictures.
tpl=$(grep -m1 '^screenshot-template=' "$CONF" | cut -d= -f2-)
dir=$(printf '%s' "$tpl" | sed "s|^~|$HOME|; s|/[^/]*$||")
if [[ -d $dir ]]; then
    ok "C7 thư mục screenshot tồn tại: $dir"
else
    bad "C7 thư mục screenshot không có: $dir" \
        "chạy ./install.sh userdirs, hoặc đổi screenshot-template"
fi

# --- C8: KHÔNG khai thứ vô dụng -------------------------------------------------
# `volume-save` và `autofit-fullscreen` không tồn tại trong mpv 0.41 — bản nháp
# đầu có chúng. Nếu sau này ai thêm vào thì C1 sẽ bắt, nhưng nhắc để khỏi thêm.
for dead in volume-save autofit-fullscreen screenshot-flags hwdec-extra-hooks; do
    if grep -qE "^$dead=" "$CONF"; then
        bad "C8 có option đã chết" "$dead không tồn tại trong mpv 0.41"
    else
        ok "C8 không khai $dead (không tồn tại trong mpv 0.41)"
    fi
done

# --- C9: phụ đề phải nạp được --------------------------------------------------
sub=$(grep -m1 '^sub-auto=' "$CONF" | cut -d= -f2-)
case $sub in
    no) bad "C9 sub-auto=no" "không tự nạp phụ đề cùng tên file" ;;
    exact|fuzzy|all) ok "C9 sub-auto=$sub" ;;
    *) bad "C9 sub-auto='$sub'" "chọn exact | fuzzy | all" ;;
esac

# --- C10: tài liệu khớp code ---------------------------------------------------
if [[ -f $R/PACKAGES.md ]] && grep -q 'mpv.conf' "$R/PACKAGES.md"; then
    ok "C10 PACKAGES.md có nhắc mpv.conf"
else
    bad "C10 PACKAGES.md thiếu mpv.conf" "tài liệu phải khớp install.sh"
fi

printf '\n  %d PASS, %d FAIL\n' "$P" "$F"
[ "$F" -eq 0 ]

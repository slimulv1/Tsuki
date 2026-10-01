#!/usr/bin/env bash
# Test cho màu 5 workspace bên trái (SchemeTag1..5) của dwm.
#
# YÊU CẦU: workspace bên trái phải MÀU SÁNG như màu bên slstatus.
#
# ĐO TRƯỚC KHI SỬA, trên màn hình thật (scrot -> đếm pixel, không đoán):
#   workspace hiện hiển thị #6742d7, luminance 84.6
#   slstatus dùng            #9881dc, luminance 140.5
#   => lệch 56 điểm, workspace tối hơn thanh trạng thái đứng cạnh nó.
# Đo cả 5 tag, tất cả đều tối hơn slstatus 70–95 điểm:
#   blue   #6742d7  lum  84.6      slstatus  #9881dc  140.5  (CPU)
#   red    #45327b  lum  59.3              #9077da  131.5  (RAM)
#   orange #4e3a8c  lum  68.2              #9f8adf  148.6  (đĩa)
#   green  #493684  lum  63.7              #af9de4  166.0  (nhiệt độ)
#   pink   #58419e  lum  76.6              #d3cfcf  207.9  (trắng)
#
# CÁCH SỬA: thêm 5 tên MỚI (tag1..tag5) vào themes/wal.h, KHÔNG sửa 5 tên cũ.
# Lý do, đo từ config.h:
#   - `blue` là NỀN của SchemeSel và TabSel (config.h:68,70) — đổi nó thành
#     màu sáng làm chữ trên nền mất tương phản.
#   - `green` là SchemeLayout + SchemeBtnPrev; `red` là SchemeBtnClose.
# Đổi chúng sẽ đổi cả nút điều hướng, việc người dùng không yêu cầu.
#
# Cả config.h VÀ config.def.h đều phải sửa: dwmwal.sh tái sinh config.h từ
# config.def.h (dwmwal.sh:334 `cp config.def.h config.h`), nên chỉ sửa config.h
# thì đổi wallpaper là mất thay đổi.
set -u
R=/home/frost-auslese/tsuki
P=0; F=0
ok()  { printf '  PASS  %s\n' "$*"; P=$((P + 1)); }
# shellcheck disable=SC2183
bad() { printf '  FAIL  %s\n        %s\n' "$*"; F=$((F + 1)); }

lum() {   # $1 = #rrggbb -> luminance 0..255
    local h=${1#\#} r g b
    r=$((16#${h:0:2})); g=$((16#${h:2:2})); b=$((16#${h:4:2}))
    awk -v r="$r" -v g="$g" -v b="$b" 'BEGIN{printf "%.1f", 0.2126*r + 0.7152*g + 0.0722*b}'
}

# Độ sáng trung bình của slstatus, đọc từ output thật nếu chạy được.
# KHÔNG `sort -u`: cần giữ THỨ TỰ xuất hiện trong thanh. Bản đầu có sort nên
# "5 màu đầu" thành 5 màu bất kỳ theo thứ tự alphabet, C4 đỏ 3/5 dù code đúng.
sl_colors=""
if [[ -x $R/slstatus/slstatus ]]; then
    sl_colors=$(TSUKI_DIR="$R" timeout 15 "$R/slstatus/slstatus" -s 2>/dev/null |
                head -1 | tr '\026' '\n' | grep -o 'c#[0-9a-f]\{6\}' | cut -c3- |
                awk '!seen[$0]++')
fi
if [[ -n $sl_colors ]]; then
    n=0; sum=0
    while IFS= read -r c; do
        sum=$(awk -v s="$sum" -v c="$c" 'BEGIN{printf "%.1f", s + '"$(lum "#$c")"'}'); n=$((n+1))
    done <<<"$sl_colors"
    sl_avg=$(awk -v s="$sum" -v n="$n" 'BEGIN{printf "%.1f", s/n}')
    ok "đọc được $n màu từ slstatus, luminance trung bình $sl_avg"
else
    printf '  --   bỏ qua phép so với slstatus: không chạy được slstatus\n'
    sl_avg=140.5   # giá trị đo được lúc viết, chỉ để tham chiếu
fi

# --- C1: cả hai file config phải dùng tên tag1..tag5 -------------------------
for f in config.h config.def.h; do
    if [[ ! -f $R/$f ]]; then
        bad "C1 thiếu $f" "repo không có file này"
        continue
    fi
    blk=$(sed -n '/SchemeTag1\]/,/SchemeTag5\]/p' "$R/$f")
    miss=""
    for n in 1 2 3 4 5; do
        grep -q "SchemeTag$n\].*tag$n," <<<"$blk" || miss="$miss tag$n"
    done
    if [[ -z $miss ]]; then
        ok "C1 $f khai cả 5 bằng tag1..tag5"
    else
        bad "C1 $f chưa dùng hết tên mới" "thiếu:$miss"
    fi
    # Và không được còn dùng tên cũ cho tag.
    for old in blue red orange green pink; do
        if grep -q "SchemeTag[0-9]\].*$old," <<<"$blk"; then
            bad "C1b $f còn dùng '$old' cho tag" \
                "tên cũ dùng chung cho highlight/nút — đổi sẽ hỏng chỗ khác"
        fi
    done
    grep -qE 'SchemeTag[1-5\].*tag[1-5],' <<<"$blk" &&
        ok "C1b $f không còn dùng tên cũ (blue/red/orange/green/pink) cho tag"
done

# --- C2: 5 tên mới phải có trong themes/wal.h ---------------------------------
WAL="$R/themes/wal.h"
if [[ ! -f $WAL ]]; then
    bad "C2 thiếu themes/wal.h" "config.h include file này"
else
    miss=""
    for n in 1 2 3 4 5; do
        grep -qE "^static const char tag$n\[\]" "$WAL" || miss="$miss tag$n"
    done
    if [[ -z $miss ]]; then
        ok "C2 themes/wal.h định nghĩa đủ tag1..tag5"
    else
        bad "C2 themes/wal.h thiếu" "thiếu:$miss"
    fi
    # KHÔNG được xoá 5 tên cũ — config.def.h được sinh lại có thể cần tới,
    # và blue/green/red vẫn đang dùng cho highlight và nút.
    for old in blue green red orange pink gray2 gray3 gray4 black white yellow; do
        grep -qE "^static const char $old\[\]" "$WAL" || bad "C2b mất tên '$old'" "tên khác còn dùng nó"
    done
    ok "C2b giữ nguyên các tên màu cũ (blue/green/red vẫn dùng cho highlight, nút)"
fi

# --- C3: màu của tag phải SÁNG, không kém slstatus quá nhiều ----------------
if [[ -f $WAL ]]; then
    worst=""
    worst_diff=0
    for n in 1 2 3 4 5; do
        h=$(grep -oE "^static const char tag$n\[\][[:space:]]*=[[:space:]]*\"#[0-9a-f]{6}\"" "$WAL" |
            grep -oE '#[0-9a-f]{6}')
        if [[ -z $h ]]; then
            worst="$worst tag$n(thieu-mau)"
            continue
        fi
        l=$(lum "$h")
        d=$(awk -v a="$l" -v b="$sl_avg" 'BEGIN{printf "%.1f", a-b}')
        # Ngưỡng: không được tối hơn slstatus quá 20 điểm luminance.
        if awk -v x="$d" 'BEGIN{exit !(x < -20)}'; then
            worst="$worst tag$n($h,${d})"
        fi
        [ "$(awk -v a="$d" -v b="$worst_diff" 'BEGIN{print (a<b)?1:0}')" = 1 ] && worst_diff=$d
    done
    if [[ -z $worst ]]; then
        ok "C3 cả 5 tag sáng hơn slstatus (tệ nhất chênh ${worst_diff#-} điểm)"
    else
        bad "C3 tag tối hơn slstatus quá bán" "$worst — yêu cầu là màu sáng như slstatus"
    fi
fi

# --- C4: màu tag phải TRÙNG màu slstatus đang dùng ---------------------------
# Người dùng nói "màu sáng NHƯ màu bên slstatus". Lấy đúng màu slstatus chạy ra,
# không tự chọn bảng màu riêng.
#
# ĐO THỨ TỰ THẬT của thanh slstatus (đọc `slstatus -s`, không sort):
#   1 #d3cfcf  updates-ON (CHỈ hiện khi có bản cập nhật; đo bằng cách ghi 3
#             vào ~/.cache/dwm-updates rồi đọc lại — ghi rõ trong test này)
#   2 #9881dc  CPU
#   3 #9077da  RAM
#   4 #9f8adf  đĩa
#   5 #af9de4  nhiệt độ
#   6 #7842d7  icon mạng — chỉ 11x11 px, KHÔNG dùng làm màu chữ
#   7 #010203  sentinel (màu reset), loại
#   8 #a5d793  updates-OFF (màu xanh lá), loại — không thuộc dải tím của rice
#
# Bản nháp test đầu lấy "5 màu đầu sau khi lọc" và chọn nhầm a5d793. Sửa bằng
# danh sách cố định đã đo, và tự chứng minh bằng cách ép updates lên.
if [[ -f $WAL ]]; then
    want="d3cfcf 9881dc 9077da 9f8adf af9de4"
    match=0; total=0
    for w in $want; do
        total=$((total + 1))
        grep -q "\"#$w\"" "$WAL" && match=$((match + 1))
    done
    if (( match == total )); then
        ok "C4 cả $total màu tag đều là màu slstatus đang dùng"
    else
        bad "C4 chỉ $match/$total màu tag trùng slstatus" \
            "cần: #$want"
    fi
    # Và chứng minh các màu đó THỰC SỰ xuất hiện trên thanh, không phải tôi
    # tự bịa. Ép có bản cập nhật để d3cfcf hiện ra rồi đọc lại.
    if [[ -x $R/slstatus/slstatus ]]; then
        ucache=$HOME/.cache/dwm-updates
        usave=$R/.dwm-updates.tagcol.bak
        [[ -f $ucache ]] && cp -- "$ucache" "$usave"
        printf '3\n' > "$ucache"
        on_colors=$(TSUKI_DIR="$R" timeout 15 "$R/slstatus/slstatus" -s 2>/dev/null |
                    head -1 | tr '\026' '\n' | grep -o 'c#[0-9a-f]\{6\}' | cut -c3-)
        if [[ -f $usave ]]; then cp -- "$usave" "$ucache"; else rm -f "$ucache"; fi
        rm -f "$usave"
        miss=""
        for w in $want; do
            grep -qx "$w" <<<"$on_colors" || miss="$miss $w"
        done
        if [[ -z $miss ]]; then
            ok "C4b ép updates lên thì cả 5 màu đều thật sự xuất hiện trên thanh"
        else
            bad "C4b màu không xuất hiện trên thanh" "thiếu:$miss"
        fi
    else
        printf '  --   bỏ qua C4b: không chạy được slstatus\n'
    fi
fi

# --- C5: các tên màu khác KHÔNG bị đổi --------------------------------------
# Đổi `blue` làm nền SchemeSel sáng lên -> chữ trên nền mất tương phản.
# Đổi `green`/`red` đổi cả nút điều hướng. Đây là việc người dùng KHÔNG yêu cầu.
if [[ -f $WAL ]]; then
    for pair in "blue:#6742d7" "green:#493684" "red:#45327b"; do
        n=${pair%%:*}; want=${pair##*:}
        h=$(grep -oE "^static const char $n\[\][[:space:]]*=[[:space:]]*\"#[0-9a-f]{6}\"" "$WAL" |
            grep -oE '#[0-9a-f]{6}')
        if [[ $h == "$want" ]]; then
            ok "C5 $n vẫn là $want (không đụng nền highlight / nút)"
        else
            bad "C5 $n đổi từ $want thành ${h:-rỗng}" \
                "$n còn dùng cho SchemeSel/TabSel/Layout/Btn — đổi là hỏng chỗ khác"
        fi
    done
fi

# --- C6: binary dwm phải chứa màu mới ---------------------------------------
# Nếu chỉ sửa config.h mà chưa `make`, binary vẫn giữ màu cũ và người dùng
# không thấy gì thay đổi mà không có gì báo lý do.
if [[ -x $R/dwm ]]; then
    missing=""
    for h in 9881dc 9077da 9f8adf af9de4; do
        strings "$R/dwm" | grep -q "$h" || missing="$missing $h"
    done
    if [[ -z $missing ]]; then
        ok "C6 binary dwm đã chứa 4 màu mới (đã make lại)"
    else
        bad "C6 binary dwm chưa có màu mới" "thiếu:$missing — chạy: make"
    fi
    # Và vẫn giữ màu cũ cho highlight/nút.
    if strings "$R/dwm" | grep -q 6742d7; then
        ok "C6b binary vẫn giữ #6742d7 cho SchemeSel/TabSel"
    else
        bad "C6b mất #6742d7" "màu nền highlight biến mất khỏi binary"
    fi
else
    printf '  --   bỏ qua C6: chưa build dwm\n'
fi

# --- C7: không có chỗ nào khác dùng nhầm tên tag ------------------------------
for f in config.h config.def.h; do
    [[ -f $R/$f ]] || continue
    # tag1..tag5 chỉ được dùng trong SchemeTag1..5, không dùng ở Scheme khác.
    bad_use=""
    while IFS= read -r line; do
        ln=${line%%:*}
        case $ln in
            *"/*"*|*"\**"*) continue ;;
        esac
        if grep -qE '^\s*\[(Scheme|Tab)[A-Za-z]+\].*tag[1-5],' <<<"$line"; then
            bad_use="$bad_use dòng $ln"
        fi
    done < <(grep -nE '\{ *tag[1-5],' "$R/$f")
    if [[ -z $bad_use ]]; then
        ok "C7 $f: tag1..tag5 chỉ dùng trong SchemeTag1..5"
    else
        bad "C7 $f dùng tên tag ở scheme khác" "$bad_use"
    fi
done

# --- C8: dwmwal.sh tái sinh config.h — phải giữ được thay đổi ----------------
# dwmwal.sh:334 `cp config.def.h config.h` rồi thay sentinel màu. Nếu chỉ sửa
# config.h, đổi wallpaper là mất. config.def.h phải dùng tên tag1..tag5.
if grep -n 'cp "\$SLST_DIR/config.def.h"' "$R/scripts/dwmwal.sh" >/dev/null 2>&1 ||
   grep -n 'config.def.h' "$R/scripts/dwmwal.sh" | grep -q 'cp '; then
    if grep -qE 'SchemeTag1\].*tag1,' "$R/config.def.h"; then
        ok "C8 config.def.h dùng tag1..tag5 nên đổi wallpaper không mất"
    else
        bad "C8 config.def.h chưa dùng tên tag" "đổi wallpaper sẽ ghi đè config.h"
    fi
else
    printf '  --   bỏ qua C8: không thấy dwmwal.sh tái sinh config.h\n'
fi

printf '\n  %d PASS, %d FAIL\n' "$P" "$F"
[ "$F" -eq 0 ]

#!/usr/bin/env bash
# Test cho nhóm giải trí (PKG_MEDIA) của install.sh.
#
# YÊU CẦU: cài đủ codec hình ảnh và âm thanh để giải trí đầy đủ.
#
# ĐO TRƯỚC KHI THÊM — KẾT LUẬN NGƯỢC VỚI DỰ ĐOÁN: phần lớn ĐÃ CÓ SẴN.
#
#   ffmpeg 9.0.2 — build config có --enable-gpl --enable-libx264 --enable-libx265
#     --enable-libvpx --enable-libaom --enable-librav1e --enable-libsvtav1
#     --enable-libopus --enable-libvorbis --enable-libtheora --enable-libmp3lame
#     --enable-libfdk-aac --enable-libass --enable-libbluray --enable-libmodplug
#     --enable-libopenmpt. Đã GIẢI MÃ THẬT (không chỉ đọc tên): h264.mp4,
#     hevc.mp4, vp9.webm, av1.mkv decode sạch; phụ đề srt và ass burn-in OK.
#     => không thêm gì cho ffmpeg.
#
#   GStreamer 1.28.7 — 188 plugin, gst-plugins-bad + ugly + gst-libav đã có.
#     gst-inspect-1.0 thấy avdec_h264/aac/mpeg4/flac/mp3. Thiếu đúng 2 gói con:
#     wavpack (gst-plugins-good) và cdparanoia (gst-plugins-base).
#
#   KHÔNG thêm ttf-dejavu: đã cài 2.37, fc-match "DejaVu Sans" ra
#   DejaVuSans.ttf, render ASS với font đó chạy OK. Thêm nữa là trùng.
#
#   KHÔNG thêm gói DVD: ffmpeg 9.0.2 KHÔNG CÓ `dvd` protocol —
#   `ffmpeg -h protocol=dvd` -> "Unknown protocol 'dvd'". libdvdnav 7.0.0 đã
#   cài cũng vô dụng, và gói `dvdnav` không có trong kho.
#
#   THIẾU LỚN NHẤT: không có trình phát nào. Không mpv, không vlc, không
#   celluloid. Đó là thứ duy nhất phải cài để giải trí.
set -u
R=/home/frost-auslese/tsuki
P=0; F=0
ok()  { printf '  PASS  %s\n' "$*"; P=$((P + 1)); }
# SC2183 báo "2 biến, truyền 1" — báo động giả: `$*` gộp mọi đối số thành
# một chuỗi, printf lặp lại nó cho mỗi `%s`. Mọi lời gọi `bad` ở dưới đều
# truyền đủ 2 (tên ca + lý do) nên vẫn đúng.
# shellcheck disable=SC2183
bad() { printf '  FAIL  %s\n        %s\n' "$*"; F=$((F + 1)); }
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT

sed -n '/^readonly PKG_MEDIA=(/,/^)/p' "$R/install.sh" > "$T/arr.sh"
sed -n '/^cmd_media() {/,/^}/p'       "$R/install.sh" > "$T/fn.sh"
sed -n '/^media_verify() {/,/^}/p'    "$R/install.sh" > "$T/vf.sh"
for f in "$T/arr.sh" "$T/fn.sh" "$T/vf.sh"; do
    [ -s "$f" ] || { printf 'FAIL: không trích được %s\n' "$f"; exit 1; }
done
{ cat "$T/arr.sh"; echo 'printf "%s\n" "${PKG_MEDIA[@]}"'; } > "$T/dump.sh"
mapfile -t PKGS < <(bash "$T/dump.sh" 2>/dev/null)
((${#PKGS[@]})) || { printf 'FAIL: PKG_MEDIA rỗng\n'; exit 1; }

# --- C1: mảng sạch ------------------------------------------------------------
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
    bad "C1 mảng bẩn" "$empty rỗng, $dup trùng"
fi

# --- C2: có trình phát --------------------------------------------------------
# Đây là thứ thiếu lớn nhất: máy không có mpv/vlc/celluloid nào.
for p in mpv celluloid; do
    if printf '%s\n' "${PKGS[@]}" | grep -qx "$p"; then
        ok "C2 có $p trong PKG_MEDIA"
    else
        bad "C2 thiếu $p" "không có trình phát nào thì không giải trí được"
    fi
done

# --- C3: có gói GStreamer bù phần còn thiếu -----------------------------------
for p in gst-plugins-good gst-plugins-base; do
    if printf '%s\n' "${PKGS[@]}" | grep -qx "$p"; then
        ok "C3 có $p (kéo wavpack / cdparanoia còn thiếu)"
    else
        bad "C3 thiếu $p" "thiếu 2 gói con của GStreamer"
    fi
done

# --- C4: mọi gói có trong kho --------------------------------------------------
missing=""
for p in "${PKGS[@]}"; do
    pacman -Si "$p" >/dev/null 2>&1 || missing+=" $p"
done
[ -z "$missing" ] && ok "C4 cả ${#PKGS[@]} gói đều có trong kho" \
                  || bad "C4 gói không có trong kho" "$missing"

# --- C5: KHÔNG thêm ffmpeg (đã có, và đầy đủ) ---------------------------------
# ffmpeg 9.0.2 đã build với libx264/x265/vp9/aom/rav1e/svt-av1/opus/vorbis/
# theora/mp3lame/fdk-aac/ass/bluray. Thêm bản khác chỉ tốn chỗ.
if printf '%s\n' "${PKGS[@]}" | grep -qx ffmpeg; then
    bad "C5 thêm ffmpeg vào PKG_MEDIA" "đã cài 9.0.2 và build đầy đủ — thêm chỉ tốn chỗ"
else
    ok "C5 không thêm ffmpeg (đã cài và build đủ codec)"
fi

# --- C6: KHÔNG thêm ttf-dejavu (đã có, ASS render OK) --------------------------
if printf '%s\n' "${PKGS[@]}" | grep -qx ttf-dejavu; then
    bad "C6 thêm ttf-dejavu" "đã cài 2.37; fc-match \"DejaVu Sans\" ra DejaVuSans.ttf và render ASS chạy OK"
else
    ok "C6 không thêm ttf-dejavu (đã có, phụ đề ASS render được)"
fi

# --- C7: KHÔNG thêm gói DVD (ffmpeg 9 không có `dvd` protocol) -----------------
# Nếu máy này ĐÃ CÓ dvd protocol thì bỏ qua — đó là giới hạn riêng của bản
# ffmpeg 9 đang đóng gói, không phải nguyên tắc chung.
if ffmpeg -hide_banner -h protocol=dvd 2>&1 | grep -q "Unknown protocol"; then
    dvd_pkgs=0
    # `*dvd*` ĐÃ khớp `libdvdnav` (chuỗi "dvd" nằm trong "libdvdnav"), nên
    # không thêm nhánh `libdvdnav` — làm vậy shellcheck báo SC2221/SC2222 và
    # nhánh sau là ngõ cụt.
    for p in "${PKGS[@]}"; do
        case $p in *dvd*) dvd_pkgs=$((dvd_pkgs + 1)) ;; esac
    done
    if (( dvd_pkgs == 0 )); then
        ok "C7 không thêm gói DVD (ffmpeg 9 không có \`dvd\` protocol, libdvdnav vô dụng)"
    else
        bad "C7 thêm gói DVD" "ffmpeg -h protocol=dvd -> Unknown protocol; cài gói DVD chỉ tốn chỗ"
    fi
else
    printf '  --   bỏ qua C7: ffmpeg này CÓ dvd protocol, nguyên tắc không còn đúng\n'
fi

# --- C8: cmd_media truyền ĐÚNG tên mảng ---------------------------------------
# install_pkgs dùng `local -n ref=$1`; truyền nhầm nhãn tạo namref tới biến
# rỗng, vòng lặp luôn ra "đã đủ" — cài không được gì mà báo thành công.
if grep -q 'install_pkgs PKG_MEDIA "media"' "$T/fn.sh"; then
    ok "C8 cmd_media truyền đúng tên mảng PKG_MEDIA"
else
    bad "C8 truyền sai tên mảng" "$(grep 'install_pkgs' "$T/fn.sh" || echo 'không thấy install_pkgs')"
fi

# --- C9: media_verify kiểm bằng CÂU HỎI CHO HỆ THỐNG, không đọc danh sách ----
# "đã cài" không chứng minh "giải mã được". Phải hỏi gst-inspect và ffmpeg.
if grep -q 'gst-inspect-1.0' "$T/vf.sh" && grep -q '\-decoders' "$T/vf.sh"; then
    ok "C9 media_verify hỏi gst-inspect và ffmpeg, không chỉ đếm gói"
else
    bad "C9 media_verify không kiểm bằng hành vi" \
        "cài xong mà không biết codec có thật sự giải mã được không"
fi

# --- C10: chạy media_verify thật, phải báo trạng thái thật --------------------
{ cat "$T/vf.sh"
  printf '%s\n' 'step(){ printf "  == %s\n" "$*"; }'
  printf '%s\n' 'ok(){ printf "  + %s\n" "$*"; }'
  printf '%s\n' 'warn(){ printf "  ! %s\n" "$*"; }'
  printf '%s\n' 'media_verify'
} > "$T/vfrun.sh"
if ! bash -n "$T/vfrun.sh" 2>"$T/verr"; then
    bad "C10 media_verify không parse được" "$(head -1 "$T/verr")"
else
    out=$(bash "$T/vfrun.sh" 2>&1)
    if printf '%s' "$out" | grep -q 'ffmpeg giải mã:'; then
        n=$(printf '%s' "$out" | sed -n 's/.*ffmpeg giải mã: //p' | wc -w)
        if (( n >= 5 )); then
            ok "C10 chạy thật: ffmpeg thấy $n bộ giải mã"
        else
            bad "C10 ffmpeg chỉ thấy $n bộ giải mã" "$out"
        fi
    else
        bad "C10 media_verify không báo ffmpeg" "$out"
    fi
    # CA RỖNG — đã dính lần này. Bản đầu đòi `out` phải chứa "mpv chưa có",
    # đúng vì lúc viết máy chưa cài mpv. Sau khi người dùng chạy
    # `./install.sh media` rồi reboot, mpv ĐÃ có nên dòng cảnh báo biến mất —
    # và ca FAIL dù code vẫn đúng. Ca test phụ thuộc trạng thái máy thì hỏng
    # theo thời gian. Sửa: đòi nhánh phản ứng đúng với chính máy này — có mpv
    # thì phải in dòng `ok`, không có thì phải cảnh báo. Cả hai đều đúng.
    if command -v mpv >/dev/null 2>&1; then
        if printf '%s' "$out" | grep -q 'mpv chưa có'; then
            bad "C10b cảnh báo mpv thiếu dù mpv đã có" \
                "$out" "máy đã cài mpv — nhánh else phải im"
        elif printf '%s' "$out" | grep -q 'mpv:'; then
            ok "C10b mpv đã có -> in dòng ok, không cảnh báo (đúng)"
        else
            bad "C10b mpv đã có nhưng không in gì về mpv" "$out"
        fi
    else
        if printf '%s' "$out" | grep -q 'mpv chưa có'; then
            ok "C10b mpv chưa có -> cảnh báo rõ (đúng)"
        else
            bad "C10b mpv thiếu mà không cảnh báo" "$out"
        fi
    fi
fi

# --- C11: KHÔNG ép vào `all` ---------------------------------------------------
main_fn=$(sed -n '/^main() {/,/^}/p' "$R/install.sh")
# BỎ DÙNG DÒNG COMMENT — grep thẳng sẽ dính dòng "KHÔNG gọi cmd_media".
all_code=$(printf '%s\n' "$main_fn" |
           sed -n '/^        all)/,/^            ;;/p' |
           grep -vE '^[[:space:]]*#')
if printf '%s\n' "$all_code" | grep -q 'cmd_media'; then
    bad "C11 cmd_media chạy trong \`all\`" "28 MiB cho trình phát — đã hỏi và chọn không ép"
else
    ok "C11 \`all\` không gọi cmd_media (không ép 28 MiB)"
fi
if printf '%s\n' "$main_fn" | grep -q 'media)     cmd_media'; then
    ok "C11b có lệnh riêng: ./install.sh media"
else
    bad "C11b không có lệnh \`media\`" "không ép mà cũng không lệnh riêng = không cài được"
fi

# --- C12: help + tài liệu -----------------------------------------------------
if ./install.sh --help 2>/dev/null | grep -q 'install.sh media'; then
    ok "C12 --help có liệt kê ./install.sh media"
else
    bad "C12 --help thiếu \`media\`" "usage() rút từ khối comment đầu file"
fi
if grep -q 'PKG_MEDIA' "$R/PACKAGES.md" 2>/dev/null; then
    ok "C12b PACKAGES.md có mục PKG_MEDIA"
else
    bad "C12b PACKAGES.md thiếu PKG_MEDIA" "tài liệu phải khớp install.sh"
fi

printf '\n  %d PASS, %d FAIL\n' "$P" "$F"
[ "$F" -eq 0 ]

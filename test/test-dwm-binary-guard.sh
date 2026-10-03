#!/usr/bin/env dash
# Kiểm tra bước tiền-vòng-lặp của run.sh: phát hiện dwm HỎNG trước khi quay
# 10 vòng crash rồi exit 1.
#
# ================================================================== VÌ SAO FILE NÀY TỒN TẠI
#
# run.sh:244 đặt "$TSUKI_DIR:$PATH" vào trước nên `dwm` luôn là bản build trong
# repo. Comment dòng 243 hứa: "Nếu repo chưa build (mới clone) thì rơi về
# /usr/local/bin như cũ, an toàn."
#
# Câu đó CHỈ ĐÚNG KHI FILE VẮNG MẶT. Đo trên máy thật, dựng lại đúng logic PATH:
#
#   ~/tsuki/dwm vắng mặt         -> type dwm -> /usr/local/bin/dwm    (đúng hứa)
#   ~/tsuki/dwm tồn tại, HỎNG    -> type dwm -> ~/tsuki/dwm           (SAI)
#
# "Hỏng" dễ xảy ra: `make` bị Ctrl-C, ổ đĩa đầy, `-flto` chết giữa chừng.
# File vẫn tồn tại và còn +x nên `type dwm` vẫn "thấy" → PATH chọn bản hỏng,
# còn /usr/local/bin/dwm đang chạy tốt thì KHÔNG bao giờ được thử. run.sh quay
# 10 vòng rồi exit 1 → mất toàn bộ session.
#
# Sửa: trước vòng lặp, thử chạy chính binary đó (`dwm -v`) và báo đúng nguyên
# nhân nếu hỏng. CỐ Ý KHÔNG tự rơi về /usr/local/bin — sửa config.h rồi mà
# build hỏng thì chạy bản cũ sẽ gây hiểu nhầm là thay đổi đã có hiệu lực.
#
# ================================================================== CÁCH TEST
#
# 1. Trích ĐÚNG hàm `_dwm_probe` từ run.sh bằng sed (không viết lại logic).
# 2. Chạy nó trên các trường hợp: binary thật, rác, 0 byte, ELF bị cắt,
#    không có quyền thực thi, không tồn tại.
# 3. Kiểm khối tiền-vòng-lặp có thật sự gọi hàm và báo đúng.
#
# CHỨNG MINH TEST BẮT ĐƯỢC LỖI: xoá khối tiền-vòng-lặp khỏi run.sh thì test
# này FAIL (thiếu hàm + không có thông báo chẩn đoán).
set -u

R="$(cd "$(dirname "$0")/.." && pwd)"
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT INT TERM

ok()  { printf '  PASS  %s\n' "$*"; P=$((P + 1)); }
bad() { printf '  FAIL  %s\n' "$1"; [ $# -gt 1 ] && printf '        %s\n' "$2"; F=$((F + 1)); }
skip() { printf '  --    %s\n' "$*"; }
P=0; F=0

RUN_SH="$R/scripts/run.sh"
if [ ! -f "$RUN_SH" ]; then
    skip "không thấy $RUN_SH"; printf '\n  %d PASS, %d FAIL\n' "$P" "$F"; exit 0
fi

# --- trích hàm thật, không viết lại -----------------------------------------
sed -n '/^_dwm_probe() {/,/^}/p' "$RUN_SH" > "$T/probe.sh"

# --- D1: hàm tồn tại và trích được ------------------------------------------
# CỐ Ý KHÔNG exit sớm khi D1 hỏng. Bản đầu của test này exit ngay, nên khi đưa
# run.sh về trước khi sửa chỉ thấy đúng 1 FAIL — không biết chắc các kiểm tra
# còn lại có bắt được gì hay không. Nay đánh dấu hàm vắng mặt rồi chạy tiếp:
# probe() sẽ tự trả 1, nên D4-D9 fail và D10-D12 fail theo.
if [ -s "$T/probe.sh" ]; then
    ok "D1 trích được _dwm_probe() từ run.sh"
else
    bad "D1 run.sh không có _dwm_probe()" \
        "khối tiền-vòng-lặp đã bị xoá — binary dwm hỏng sẽ crash 10 vòng rồi exit 1"
fi

# Hàm phải dùng `-v` chứ không kiểm exit code. die() trong util.c:26 luôn
# exit(1) kể cả khi in ra "dwm-6.8" đúng — đo trên bản thật:
#     $ ./dwm -v            -> dwm-6.8 (stderr)
#     $ ./dwm -v; echo $?   -> 1
if grep -q '\-v' "$T/probe.sh"; then
    ok "D2 _dwm_probe dùng cờ -v"
else
    bad "D2 _dwm_probe không dùng -v" "không có cách nào xác nhận binary chạy được"
fi

# --- chuẩn bị các binary mẫu ------------------------------------------------
mkdir -p "$T/bin"

# dwm thật trong repo: nguồn chuẩn để so
if [ -x "$R/dwm" ]; then
    cp "$R/dwm" "$T/bin/good"
    ok "D3 dùng dwm thật trong repo làm chuẩn"
else
    cp "$R/dwm.c" "$T/bin/good.notbinary" 2>/dev/null || : > "$T/bin/good"
    skip "chưa build dwm trong repo — D4..D9 dùng stub thay thế"
fi

# Các biến thể HỎNG. Ghi bằng printf vì dash không hiểu \xNN.
printf 'this is not an ELF executable\n'  > "$T/bin/garbage"; chmod +x "$T/bin/garbage"
: > "$T/bin/zero";                                                    chmod +x "$T/bin/zero"
printf '\177ELF'                          > "$T/bin/truncelf";       chmod +x "$T/bin/truncelf"
# shell script "trông giống" nhưng không phải dwm. KHÔNG kỳ vọng probe bắt
# được — xem D6.
printf '#!/bin/sh\necho "dwm-6.8"\n'       > "$T/bin/fakedwm";        chmod +x "$T/bin/fakedwm"
if [ -x "$R/dwm" ]; then
    cp "$R/dwm" "$T/bin/noexec"; chmod 644 "$T/bin/noexec"
    # dwm thật bị CẮT CỤT — cách hỏng thực tế nhất khi `make` bị Ctrl-C.
    head -c 90000 "$R/dwm" > "$T/bin/cutelf"; chmod +x "$T/bin/cutelf"
fi

# LƯU Ý CHỈ SỐ THAM SỐ: `dash -c 'script' NAME ARG` đặt NAME vào $0 và ARG vào
# $1 — không có $2. Lúc đầu tôi viết `. "$1"; _dwm_probe "$2"` nên nó source
# nhầm chính binary dwm rồi gọi probe với chuỗi rỗng. D4 bắt được lỗi này.
# Đúng phải là: $0 = file chứa hàm, $1 = binary cần thử.
#
# TRẢ VỀ 3 TRẠNG THÁI, không phải 2 — lý do:
#     0 = probe CHẤP NHẬN binary này
#     1 = probe TỪ CHỐI (đã kiểm, đúng kỳ vọng)
#     2 = HÀM KHÔNG TỒN TẠI, chưa kiểm được gì cả
# Nếu chỉ dùng 0/1 thì khi hàm vắng mặt, "probe bắt được file hỏng" lại đúng
# (vì không có gì để chạy) — ĐÓ LÀ PASS GIẢ, và tôi đã dính: khi xoá khối
# sửa, D5-D9 vẫn PASS. Sửa thành 3 trạng thái để trường hợp đó phải FAIL.
probe() {
    [ -s "$T/probe.sh" ] || return 2
    dash -c '. "$0"; _dwm_probe "$1"' "$T/probe.sh" "$1" 2>/dev/null
}

# Kỳ vọng: probe phải TỪ CHỐI $1.
must_reject() {
    probe "$1"
    case $? in
        1) return 0 ;;                       # đúng: đã kiểm và từ chối
        2) return 2 ;;                       # hàm vắng mặt: CHƯA kiểm được
        *) return 1 ;;                       # 0 = chấp nhận sai
    esac
}

# --- D4: binary tốt phải qua -------------------------------------------------
if [ -x "$R/dwm" ]; then
    probe "$R/dwm"; rc=$?
    case $rc in
        0) ok "D4 dwm thật -> probe ĐẠT" ;;
        2) bad "D4 không có _dwm_probe để thử" ;;
        *) bad "D4 dwm thật bị probe bác" "false negative — dwm tốt mà báo hỏng" ;;
    esac
else
    skip "D4 (chưa build dwm)"
fi

# --- D5: các biến thể hỏng phải bị bắt --------------------------------------
# `cutelf` là ca quan trọng nhất: 90 KB đầu của dwm thật, tức là "make bị
# Ctrl-C giữa chừng". Đo: chạy `-v` -> SIGSEGV, không in ra "dwm-<số>".
for c in garbage zero truncelf cutelf; do
    [ -e "$T/bin/$c" ] || continue
    must_reject "$T/bin/$c"; rc=$?
    case $rc in
        0) ok "D5 _dwm_probe bắt '$c' hỏng" ;;
        1) bad "D5 _dwm_probe chấp nhận '$c' hỏng" \
               "binary hỏng mà probe vẫn đạt -> vẫn crash 10 vòng như cũ" ;;
        *) bad "D5 '$c': chưa kiểm được vì _dwm_probe vắng mặt" \
               "test này KHÔNG có tác dụng khi thiếu hàm — phải tính là FAIL" ;;
    esac
done

# --- D6: GIỚI HẠN ĐÃ BIẾT, ghi ra để không ai tưởng là đã xử lý -------------
# Probe KHÔNG phân biệt được dwm thật với một script in "dwm-6.8". Đã thử thêm
# kiểm ELF magic để chặn, rồi BỎ — vì nó làm hỏng stub dwm trong
# test-run-matrix.sh / test-run-session.sh (stub là script, đúng như test cần)
# mà chẳng chặn được thứ gì thực tế: phép thử `-v` đã bắt hết rác, 0 byte,
# ELF cắt, dwm bị cắt 90 KB, ELF 1 KB. Case này chỉ tự thấy chính nó.
if probe "$T/bin/fakedwm"; then
    skip "D6 GIỚI HẠN ĐÃ BIẾT: probe chấp nhận script in 'dwm-6.8'"
    skip "    (không thêm kiểm ELF: nó phá stub test, đo ở D5 cho thấy -v đã đủ)"
else
    skip "D6 probe bất ngờ bắt được script giả (tốt hơn dự kiến)"
fi

if [ -f "$T/bin/noexec" ]; then
    must_reject "$T/bin/noexec"; rc=$?
    case $rc in
        0) ok "D7 _dwm_probe bắt file không có quyền thực thi" ;;
        1) bad "D7 _dwm_probe chấp nhận file không có quyền thực thi" ;;
        *) bad "D7 chưa kiểm được vì _dwm_probe vắng mặt" ;;
    esac
else
    skip "D7 (chưa build dwm để tạo noexec)"
fi

# --- D8: đường dẫn không tồn tại ---------------------------------------------
must_reject "$T/bin/khong-ton-tai"; rc=$?
case $rc in
    0) ok "D8 _dwm_probe bắt đường dẫn không tồn tại" ;;
    1) bad "D8 _dwm_probe chấp nhận đường dẫn không tồn tại" ;;
    *) bad "D8 chưa kiểm được vì _dwm_probe vắng mặt" ;;
esac

# --- D9: đường dẫn rỗng ------------------------------------------------------
if [ -s "$T/probe.sh" ]; then
    if dash -c '. "$0"; _dwm_probe ""' "$T/probe.sh" 2>/dev/null; then
        bad "D9 _dwm_probe chấp nhận đường dẫn rỗng"
    else
        ok "D9 _dwm_probe bắt đường dẫn rỗng"
    fi
else
    bad "D9 chưa kiểm được vì _dwm_probe vắng mặt"
fi

# --- D10: khối chẩn đoán có trong run.sh và nói đúng nguyên nhân --------------
if grep -q 'KHÔNG CHẠY ĐƯỢC' "$RUN_SH"; then
    ok "D10 run.sh có thông báo 'KHÔNG CHẠY ĐƯỢC'"
else
    bad "D10 thiếu thông báo chẩn đoán" \
        "vẫn chỉ có 'dwm crash liên tục' + gợi ý sai là config.h hỏng"
fi

# Phải nhắc rằng bản /usr/local/bin còn tốt và KHÔNG tự dùng nó —
# nếu không, "sửa" lại thành im lặng chạy bản cũ, che mất việc make hỏng.
if grep -q 'bản cài ở /usr/local/bin vẫn tốt' "$RUN_SH"; then
    ok "D11 nói rõ bản /usr/local/bin còn dùng được mà không tự dùng"
else
    bad "D11 không nhắc bản /usr/local/bin còn tốt"
fi

# Khối chẩn đoán phải nằm TRƯỚC vòng lặp — sau vòng lặp thì vô nghĩa.
LOOP=$(grep -n '^while type dwm' "$RUN_SH" | head -1 | cut -d: -f1)
CHK=$(grep -n '_dwm_path=$(command -v dwm' "$RUN_SH" | head -1 | cut -d: -f1)
if [ -n "$LOOP" ] && [ -n "$CHK" ] && [ "$CHK" -lt "$LOOP" ]; then
    ok "D12 khối kiểm tra nằm TRƯỚC vòng lặp (dòng $CHK < $LOOP)"
else
    bad "D12 khối kiểm tra sai chỗ" "phải nằm trước 'while type dwm' mới có tác dụng"
fi

# --- D13: cú pháp shell vẫn hợp lệ ------------------------------------------
if sh -n "$RUN_SH" 2>/dev/null && bash -n "$RUN_SH" 2>/dev/null; then
    ok "D13 run.sh vẫn qua kiểm tra cú pháp (sh -n và bash -n)"
else
    bad "D13 run.sh sai cú pháp sau khi sửa"
fi

printf '\n  %d PASS, %d FAIL\n' "$P" "$F"
[ "$F" -eq 0 ]
#!/usr/bin/env bash
# Test cho ba việc dùng hằng ngày:
#   A. slstatus (battery.c) — không in lỗi ra stderr khi máy không có pin
#   B. .config/paru/paru.conf — paru đọc được, không sai cú pháp
#   C. ghi chú paccache (timer chính thức của Arch, cần sudo để bật)
#
# SAI SÓT ĐÃ DÍNH, GHI LẠI ĐỂ KHÔNG LẶP:
#
# 1. TÔI BÁO SAI RẰNG THANH TRẠNG THÁI "TRỐNG". Lý do tôi đưa ra: chạy
#    `./slstatus` không có cờ -> stdout 0 byte. Đo lại thì SAI: slstatus.c
#    dòng 115 có `if (sflag) puts(...) else XStoreName(...)` — KHÔNG có -s thì nó
#    đẩy chữ vào X server (đó là cách dwm đọc), chứ không in ra stdout.
#    Đúng cách đo là `./slstatus -s` -> 182 byte, đầy đủ CPU/RAM/đĩa/nhiệt/
#    mạng/ngày giờ. Lỗi thật chỉ là 25 dòng "fopen ... No such file" trên
#    stderr mỗi lần vẽ.
#
# 2. paccache -k2 trả "no candidate packages found" trong khi có 1218 gói
#    trùng tên trong cache. Không phải paccache hỏng: mặc định
#    CleanMethod=KeepInstalled giữ bản đang cài, và hầu hết cache là bản
#    đang dùng nên chỉ có bản mới nhất. Đo lại: -k1 -> 23 ứng viên, 653 MiB;
#    -k2 trở lên -> 0. Bản timer chính thức dùng -k3 (mặc định), an toàn.
#
# 3. `grep -rE 'paccache' ... | sed 's/^/  /'` dính lỗi sed khi chuỗi chứa
#    `ExecStart=/usr/bin/paccache` — "dấu /" đầu tiên trong s[...]. Đã dùng sed
#    khác.
set -u
R=/home/frost-auslese/tsuki
P=0; F=0
ok()  { printf '  PASS  %s\n' "$*"; P=$((P + 1)); }
# shellcheck disable=SC2183
bad() { printf '  FAIL  %s\n        %s\n' "$*"; F=$((F + 1)); }
T=$(mktemp -d)
# B1 SỬA FILE THẬT trong ~/.config/paru/paru.conf để chứng minh phép đo có tác
# dụng. Phải phục hồi được kể cả khi bị Ctrl-C hoặc chết giữa chừng — không
# có trap thì một lần bấm C-c là mất cấu hình AUR của người dùng.
# Giữ nội dung trong biến + file tạm, trap ghi lại.
cp -- "$HOME/.config/paru/paru.conf" "$T/paru.conf.real" 2>/dev/null || :
_restore_paru() {
    if [[ -f $T/paru.conf.real ]]; then
        cp -- "$T/paru.conf.real" "$HOME/.config/paru/paru.conf"
    fi
    rm -rf "$T"
}
trap _restore_paru EXIT INT TERM HUP

SLS="$R/slstatus/slstatus"
export TSUKI_DIR="$R"

# =============================================================================
# A. slstatus — không in lỗi khi không có pin
# =============================================================================
# --- A1: máy này có pin không? Nguyên tắc "không có pin -> im" chỉ đúng khi
# máy thật sự không có pin. Nếu sau này bạn dùng máy có pin, ca sẽ báo sai.
if [[ -d /sys/class/power_supply ]] &&
   compgen -G '/sys/class/power_supply/BAT*' >/dev/null 2>&1; then
    printf '  --   bỏ qua A1-A3: máy này CÓ pin, nguyên tắc khác\n'
else
    # --- A1: stderr phải SẠCH khi không có pin -------------------------------
    # Đây là lỗi thật: battery_bar() cố tình trả nullptr khi không có pin (đúng
    # thiết kế, có ghi trong battery.c), nhưng nó gọi pscanf() mà pscanf() gọi
    # warn() khi fopen hỏng -> 25 dòng lỗi trên stderr MỖI LẦN vẽ.
    if [[ ! -x $SLS ]]; then
        printf '  --   bỏ qua A1: chưa build slstatus (chạy make trong slstatus/)\n'
    else
        err=$(timeout 20 "$SLS" -s 2>&1 >/dev/null | wc -l)
        if (( err == 0 )); then
            ok "A1 stderr sạch khi không có pin (0 dòng, trước khi sửa là 25)"
        else
            bad "A1 stderr vẫn bẩn" \
                "$err dòng lỗi: $(timeout 20 "$SLS" -s 2>&1 >/dev/null | head -1)"
        fi
    fi

    # --- A2: thanh phải CÓ NỘI DUNG ------------------------------------------
    # Đo bằng `-s` chứ không phải chạy không cờ. Không có -s thì slstatus đẩy
    # chữ vào X server bằng XStoreName (slstatus.c:121) nên stdout rỗng — đó là
    # bình thường, không phải hỏng. Tôi đã báo sai một lần vì chạy thiếu cờ.
    if [[ ! -x $SLS ]]; then
        printf '  --   bỏ qua A2: chưa build slstatus\n'
    else
        out=$(timeout 20 "$SLS" -s 2>/dev/null | head -1)
        n=${#out}
        if (( n > 50 )); then
            ok "A2 thanh có nội dung: $n byte"
        else
            bad "A2 thanh gần như rỗng ($n byte)" \
                "đo bằng 'slstatus -s' — không có -s thì nó đẩy vào X server"
        fi
    fi

    # --- A3: các component trong config.h phải chạy được -------------------
    # Không chỉ "thanh không rỗng" — mà phải là từng thành phần có giá trị thật.
    if [[ ! -x $SLS ]]; then
        printf '  --   bỏ qua A3: chưa build slstatus\n'
    else
        out=$(timeout 20 "$SLS" -s 2>/dev/null | head -1 |
              sed 's/\^\[[0-9;]*[a-z]//g; s/\^\[c#[0-9a-f]*\^//g; s/\^\[d\^//g')
        miss=""
        # ram: "3.1 Gi" hoac "1.2 Gi"
        grep -qE '[0-9.]+ (Gi|Mi)' <<<"$out" || miss="$miss ram"
        # cpu: dau phan tram, ví dụ " 12%"
        grep -qE '[0-9]+%' <<<"$out" || miss="$miss cpu"
        # dia: cung duoi dang %, nhung dung o giua
        # nhiet do: "42°C" hoac "42°C"
        grep -qE '[0-9]+°C' <<<"$out" || miss="$miss nhietdo"
        # ngay gio: "Thu, 01/10, 17:26"
        grep -qE '[0-9]{2}/[0-9]{2}, [0-9]{2}:[0-9]{2}' <<<"$out" || miss="$miss ngaygio"
        if [[ -z $miss ]]; then
            ok "A3 mọi component đều có giá trị: RAM, CPU, nhiệt độ, ngày giờ"
        else
            bad "A3 component không ra số" "thiếu:$miss" "$out"
        fi
    fi

    # --- A4: KHÔNG được im lặng bằng cách bỏ hẳn thành phần pin ---------------
    # Cách "nhanh" nhất để sửa 25 dòng lỗi là xoá dòng battery_bar khỏi
    # config.h. Nhưng battery.c là code dùng chung cho mọi máy — xoá ở config.h
    # thì máy có pin mất phần hiển thị pin. Sửa đúng là thêm access() trong
    # battery.c như pick() sẵn làm.
    if grep -q 'access(path, R_OK)' "$R/slstatus/components/battery.c"; then
        ok "A4 sửa ở battery.c bằng access() (giữ nguyên hàm cho máy có pin)"
    else
        bad "A4 battery.c không có access() trước pscanf" \
            "hoặc đã xoá battery_bar khỏi config.h — cách đó làm máy có pin mất hiển thị"
    fi
    # Và config.h vẫn phải giữ battery_bar (không tự ý bỏ).
    if grep -q '{ battery_bar,' "$R/slstatus/config.h"; then
        ok "A4b config.h vẫn khai battery_bar (không xoá cấu hình)"
    else
        bad "A4b battery_bar bi xoá khỏi config.h" \
            "bản nháp đầu tôi từng định xoá — nhưng thao tác đó làm hỏng máy có pin"
    fi
    # KHÔNG được sửa pscanf() — nó dùng chung, fopen hỏng chỗ khác vẫn là lỗi.
    # LỖI TEST ĐÃ DÍNH: bản đầu viết
    #     grep -qA3 'fopen(path, "r")' util.c | grep -q 'warn('
    # `grep -q` của vế ĐẦU thoát ngay khi khớp, đóng pipe, nên vế sau nhận rỗng
    # và luôn fail — ca đỏ dù code đúng. Đo lại: `grep -A3 ... | grep -c 'warn'`
    # cho ra 1. Sửa bằng cách bỏ -q ở vế đầu.
    if grep -A3 'fopen(path, "r")' "$R/slstatus/util.c" | grep -q 'warn('; then
        ok "A4c pscanf() giữ nguyên warn() (lỗi chỗ khác vẫn phải báo)"
    else
        bad "A4c pscanf() đã bị sửa" "nó dùng chung cho nhiều component"
    fi
fi

# --- A5: binary trong repo phải mới hơn source (đã build lại chưa) ------------
if [[ -x $SLS && -f $R/slstatus/components/battery.c ]]; then
    if [[ "$SLS" -nt "$R/slstatus/components/battery.c" ]]; then
        ok "A5 binary mới hơn source — đã make lại"
    else
        bad "A5 binary CŨ hơn source" "chạy: cd slstatus && make"
    fi
else
    printf '  --   bỏ qua A5: chưa có binary hoặc source\n'
fi

# =============================================================================
# B. paru.conf
# =============================================================================
CONF="$R/.config/paru/paru.conf"
if ! command -v paru >/dev/null 2>&1; then
    printf '  --   bỏ qua B: máy này chưa cài paru\n'
else
    if [[ ! -f $CONF ]]; then
        bad "B không có .config/paru/paru.conf" \
            "paru chạy toàn mặc định: build AUR không hỏi xem PKGBUILD làm gì"
    else
        # --- B1: cau hình ĐÚNG thì paru phải im ----------------------------------
        # CA RỖNG ĐÃ DÍNH: bản đầu chỉ chạy `paru --version` và grep "error".
        # Đo thử bằng cách cố tình thêm `BogusOption123` vào ~/.config — paru
        # CÓ báo "error: unknown option" trên stderr. Nên ca đó hợp lý về lý
        # thuyết, nhưng nó FAIL khi file đúng, tức báo lỗi dù không có. Nguyên
        # nhân: `paru --version 2>&1 | grep ...` trong `$(...)` — khi không có
        # dòng nào khớp, `grep` trả mã 1 và `$(...)` rỗng, `if err=$(...)`
        # coi rẗng là FALSE nên phải vào nhánh else. Nghe đúng, nhưng đo lại thì
        # vẫn đỏ — nên phải TỰ CHỨNG MINH thay vì tin logic.
        # Cách chắc: so message của file THẬT với message khi cố tình phá file
        # trong bản sao. Nếu hai message khác nhau, phép đo có tác dụng.
        real_err=$(timeout 90 paru --version 2>&1 >/dev/null | head -2)
        # Bản sao có chứa option sai, đặt ở vị trí mà paru thật sự đọc.
        # Phục hồi tức thời (không đợi trap) — trap chỉ là lưới an toàn.
        printf '%s\nBogusOption123\n' "$(cat "$T/paru.conf.real" 2>/dev/null || echo '[options]')" \
            > "$HOME/.config/paru/paru.conf"
        broke_err=$(timeout 90 paru --version 2>&1 >/dev/null | head -2)
        cp -- "$T/paru.conf.real" "$HOME/.config/paru/paru.conf"
        if [[ -z $real_err ]]; then
            if [[ -n $broke_err ]]; then
                ok "B1 file đúng: paru im; file phá: paru báo lỗi → phép đo phân biệt được"
            else
                bad "B1 phép đo vô dụng" \
                    "paru im lặng với CẢ file đúng lẫn file sai — không đo được gì"
            fi
        else
            bad "B1 paru báo lỗi với file đúng" "$real_err"
        fi

        # --- B2: phải có [options] --------------------------------------------
        if grep -qE '^\s*\[options\]\s*$' "$CONF"; then
            ok "B2 có [options] — đúng định dạng pacman.conf(5) mà man paru.conf(5) nêu"
        else
            bad "B2 thiếu [options]" "paru 2.1 báo 'key X does not belong to a section'"
        fi

        # --- B3: KHÔNG bật SkipReview ------------------------------------------
        # SkipReview là cờ BẬT để BỎ QUA việc đọc PKGBUILD. Đọc PKGBUILD là
        # biện pháp duy nhất chống cài nhầm script độc hại từ AUR.
        if grep -qE '^\s*SkipReview\s*$' "$CONF"; then
            bad "B3 SkipReview đang BẬT" "tức bỏ qua xem PKGBUILD — mất lớp bảo vệ duy nhất"
        else
            ok "B3 không bật SkipReview (vẫn xem PKGBUILD trước khi build)"
        fi

        # --- B4: chỉ dùng option có thật trong paru này ------------------------
        # PkgBuildCache / ReviewDiff / DiffMenu là option của hướng dẫn paru 1.x.
        # Đã kiểm cả man paru.conf(5) lẫn `strings /usr/bin/paru` — cả ba đều
        # không có trong 2.1.0. Viết vào thì paru báo "unknown option".
        for o in $(sed -n 's/^\([A-Z][A-Za-z]*\).*/\1/p' "$CONF"); do
            [[ $o == AUR || $o == REVIEWDIFF ]] && continue
            printf '     option trong file: %s\n' "$o" >&2
        done
        used=$(sed -n 's/^\([A-Z][A-Za-z]*\).*/\1/p' "$CONF" |
               grep -vE '^(CHÚ|THÍM|MỌI|CẤU|MỘT|NẾU|TỪ|ĐÃ|ĐÓNG|KHÔNG|GHI|Ở|LÀ|TỪ|BỎ)' || true)
        unknown=""
        while IFS= read -r o; do
            [[ -z $o ]] && continue
            man paru.conf 2>/dev/null | sed 's/\x1b\[[0-9;]*m//g' |
                grep -qE "^ *$o( |\$| \[)" || unknown="$unknown $o"
        done <<<"$used"
        if [[ -z $unknown ]]; then
            ok "B4 mọi option trong file đều có thật trong man paru.conf(5) của máy này"
        else
            bad "B4 option không tồn tại" \
                "$unknown — paru sẽ báo 'unknown option'. Đã kiểm PkgBuildCache/ReviewDiff/DiffMenu đều không có trong 2.1.0"
        fi

        # --- B5: phải copy sang máy --------------------------------------------
        if [[ -f $HOME/.config/paru/paru.conf ]]; then
            if cmp -s "$CONF" "$HOME/.config/paru/paru.conf"; then
                ok "B5 ~/.config/paru/paru.conf trùng repo"
            else
                bad "B5 ~/.config/paru/paru.conf khác repo" \
                    "chạy ./install.sh dotfiles"
            fi
            # Và phải nằm trong items, không chỉ có trong repo.
            items=$(sed -n '/local -a items=(/,/)/p' "$R/install.sh" | tr '\n' ' ' |
                    sed 's/.*items=(//; s/)$//' | tr -s ' \\' '\n' |
                    grep -v '^$' | sed 's/)$//')
            if printf '%s\n' "$items" | grep -qx paru; then
                ok "B5b paru có trong items của cmd_dotfiles"
            else
                bad "B5b paru không có trong items" \
                    "đo được: viết xong chạy dotfiles thì KHÔNG copy. items đọc được: $(printf '%s' "$items" | tr '\n' ' ')"
            fi
        else
            printf '  --   bỏ qua B5: chưa chạy ./install.sh dotfiles\n'
        fi
    fi
fi

# =============================================================================
# C. paccache — ghi chú, không tự bật (cần sudo)
# =============================================================================
# Không sửa gì ở đây: timer paccache là file CỦA GÓI ARCH (/usr/lib/systemd/system),
# không thuộc repo này. Chỉ cần bật bằng sudo.
if ! command -v paccache >/dev/null 2>&1; then
    printf '  --   bỏ qua C: máy này chưa cài paccache\n'
else
    if [[ -f /usr/lib/systemd/system/paccache.timer ]]; then
        ok "C1 timer paccache có sẵn từ gói Arch — không cần tự viết"
    else
        bad "C1 không có /usr/lib/systemd/system/paccache.timer" \
            "xem pacman-contrib có cài không"
    fi
    # -k phải là số >= 2: -k0 có thể xoá cả gói đang cài.
    # Đo: -k1 -> 23 ứng viên (653 MiB), -k2 trở lên -> 0.
    if ! timeout 30 paccache --help 2>&1 | grep -qE '\-k, --keep <num>'; then
        bad "C2 paccache không có -k" "không giới hạn được số bản"
    elif timeout 30 paccache --help 2>&1 | grep -qE 'default: 3'; then
        ok "C2 paccache mặc định -k3 — timer chính thức không cần tham số thêm"
    else
        printf '  --   C2: paccache không ghi rõ giá trị mặc định của -k\n'
    fi
    # Ghi chú: không xoá cache khi thiếu quyền.
    if grep -q 'PACCACHE_ARGS' /etc/conf.d/pacman-contrib 2>/dev/null; then
        ok "C3 /etc/conf.d/pacman-contrib tồn tại (chỗ đặt PACCACHE_ARGS)"
    else
        bad "C3 không có /etc/conf.d/pacman-contrib" "không chỉnh được PACCACHE_ARGS"
    fi
fi

# --- C4: tài liệu phải nói rõ việc cần SUDO -----------------------------------
if grep -q 'paccache.timer' "$R/TROUBLESHOOTING.md" 2>/dev/null; then
    ok "C4 TROUBLESHOOTING.md có hướng dẫn paccache.timer"
else
    bad "C4 TROUBLESHOOTING.md thiếu paccache.timer" \
        "việc này CẦN SUDO, người dùng phải tự chạy — phải có trong tài liệu"
fi

printf '\n  %d PASS, %d FAIL\n' "$P" "$F"
[ "$F" -eq 0 ]

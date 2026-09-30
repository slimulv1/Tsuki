#!/usr/bin/env bash
# Test cho phần dò profile Firefox của install.sh.
#
# Mục tiêu: chứng minh `firefox_profile` chọn đúng trên các layout máy khác
# nhau, không chỉ layout của máy đang phát triển. Mọi test dựng một $HOME giả
# rồi chạy đúng code TRÍCH TỪ install.sh — không sao chép logic, để test
# không thể "trôi" khỏi bản thật.
#
#   ./test/test-firefox-profile.sh
#
# Không cần root, không đụng profile thật. Chạy được trên máy sạch chưa cài
# Firefox — đó là lý do nó dựng layout giả thay vì đọc layout thật.

set -uo pipefail
REPO_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
readonly REPO_DIR
WORK=$(mktemp -d "${TMPDIR:-/tmp}/tsuki-fftest.XXXXXX")
trap 'rm -rf -- "$WORK"' EXIT

PASS=0
FAIL=0
pass() { printf '  PASS  %s\n' "$*"; PASS=$((PASS + 1)); }
bad()  { printf '  FAIL  %s\n        %s\n' "$*"; FAIL=$((FAIL + 1)); }
chk()  { # ten, actual, expected
    if [[ $2 == "$3" ]]; then pass "$1"; else bad "$1" "got [$2] want [$3]"; fi
}
chk_ne() { # ten, actual, khac-empty
    if [[ -n $2 && $2 != "$3" ]]; then pass "$1"; else bad "$1" "got [$2]"; fi
}

# ---------------------------------------------------- trích code từ install --
# Danh sách hàm cần dùng. Nếu install.sh đổi tên hàm thì test FAIL ngay thay
# vì âm thầm bỏ qua nhánh logic tương ứng.
FUNCS=(firefox_bases firefox_profile_ini newest_dir newest_dir_keep_all
       firefox_looks_like_cache firefox_candidates choose_profile
       mark_active firefox_profile_override firefox_profile)
FNS="$WORK/fns.sh"
# Vòng lặp dưới ghi TỪNG HÀM vào $FNS. Hàm nào không còn trong install.sh thì
# báo FAIL ngay — thay vì âm thầm bỏ qua nhánh logic tương ứng, làm test xanh
# trong khi code đã đổi.
{
    printf 'set -uo pipefail\n'
    printf 'warn() { printf "  !   %s\\n" "$*" >&2; }\n'
    printf 'die()  { printf "  ERR %s\\n" "$*" >&2; exit 1; }\n'
    for f in "${FUNCS[@]}"; do
        if grep -q "^${f}() {" "$REPO_DIR/install.sh"; then
            awk "/^${f}\\(\\)/,/^}\$/" "$REPO_DIR/install.sh"
        else
            bad "ham $f khong con trong install.sh" ""
            printf '# THIEU %s\n' "$f"
        fi
    done
    cat <<'EOF'
ff_profile() { firefox_profile; }
ff_cands()   { firefox_candidates; }
ff_looks()   { firefox_looks_like_cache "$1" && echo CACHE || echo PROFILE; }
ff_override(){ firefox_profile_override "${1:-}"; }
EOF
} > "$FNS"

if (( FAIL )); then
    printf '\n  KẾT QUẢ: %d PASS, %d FAIL\n' "$PASS" "$FAIL"
    exit 1
fi

# Chạy một hàm trong $HOME giả. ff() <home> <func> [args...]
ff() {
    local home=$1 fn=$2; shift 2
    env -u XDG_CONFIG_HOME -u XDG_DATA_HOME -u XDG_CACHE_HOME -u FIREFOX_PROFILE \
        TSUKI_HOME="$home" \
        bash -c 'source "$1"; shift; "$@"' _ "$FNS" "$fn" "$@"
}
# Như ff() nhưng kèm biến môi trường: ffx() <VAR> <value> <home> <func> [args]
ffx() {
    local name=$1 val=$2 home=$3 fn=$4; shift 4
    env -u XDG_CONFIG_HOME -u XDG_DATA_HOME -u XDG_CACHE_HOME -u FIREFOX_PROFILE \
        "$name=$val" TSUKI_HOME="$home" \
        bash -c 'source "$1"; shift; "$@"' _ "$FNS" "$fn" "$@"
}
# ffbase <home> <func> [args] — chạy hàm rồi chỉ giữ TÊN THƯ MỤC CUỐI.
# KHÔNG dùng `| xargs basename`: xargs cắt theo khoảng trắng nên "my prof.dir"
# ra "my" (fail oan), và hàm trong pipeline không nhận được $1.
# Bỏ tiền tố "/" bằng tham số mở rộng, giữ nguyên cả khoảng trắng trong tên.
ffbase() { local out; out=$(ff "$@"); [[ -n $out ]] || return 0; printf '%s\n' "${out##*/}"; }

mkprof() { mkdir -p "$1"; printf '{"user_pref("x",1);}\n' > "$1/prefs.js"; }
ini()    { mkdir -p "${1%/*}"; cat > "$1"; }

printf '  %d ham trich tu install.sh\n\n' "${#FUNCS[@]}"

# 1) Layout kinh dien: ~/.mozilla/firefox, khong profiles.ini
H=$WORK/h1
mkprof "$H/.mozilla/firefox/abc.default-release"
chk "T1  ~/.mozilla/firefox, khong profiles.ini" \
    "$(ffbase "$H" ff_profile)" "abc.default-release"

# 2) Layout may hien nay: profiles.ini tro [Install*] Default=<ten>
H=$WORK/h2
ini "$H/.config/mozilla/firefox/profiles.ini" <<'EOF'
[General]
StartWithLastProfile=1
[Profile0]
Name=default-release
IsRelative=1
Path=jnetde4e.default-release
[Install4F96D1932A9F858E]
Default=jnetde4e.default-release
Locked=1
[Profile1]
Name=default
IsRelative=1
Path=tihwr7jp.default
Default=1
EOF
mkprof "$H/.config/mozilla/firefox/jnetde4e.default-release"
mkprof "$H/.config/mozilla/firefox/tihwr7jp.default"
chk "T2  profiles.ini tro [Install*] Default=<ten>" \
    "$(ffbase "$H" ff_profile)" "jnetde4e.default-release"

# 3) Flatpak
H=$WORK/h3; mkprof "$H/.var/app/org.mozilla.firefox/.mozilla/firefox/ff.default"
chk "T3  flatpak" "$(ffbase "$H" ff_profile)" "ff.default"

# 4) Snap
H=$WORK/h4; mkprof "$H/snap/firefox/common/.mozilla/firefox/sn.default-release"
chk "T4  snap" "$(ffbase "$H" ff_profile)" "sn.default-release"

# 5) XDG_CONFIG_HOME tu dat
H=$WORK/h5; mkprof "$WORK/h5/xdg/mozilla/firefox/xd.default-release"
ffbase_via_xdg() {
    local out
    out=$(ffx XDG_CONFIG_HOME "$WORK/h5/xdg" "$WORK/h5/home" ff_profile)
    [[ -n $out ]] || return 0
    printf '%s\n' "${out##*/}"
}
chk "T5  XDG_CONFIG_HOME tu dat" \
    "$(ffbase_via_xdg)" \
    "xd.default-release"

# 6) Ban dev
H=$WORK/h6; mkprof "$H/.mozilla/firefox-dev/dev.default"
chk "T6  ban dev/nightly" "$(ffbase "$H" ff_profile)" "dev.default"

# 7) Thu muc CACHE trung ten + MOI HON profile that -> phai bo qua
H=$WORK/h7
ini "$H/.config/mozilla/firefox/profiles.ini" <<'EOF'
[Profile0]
Name=real
IsRelative=1
Path=real.default-release
Default=1
EOF
mkprof "$H/.config/mozilla/firefox/real.default-release"
mkdir -p "$H/.cache/mozilla/firefox/fake.default-release/cache2"
sleep 1; touch "$H/.cache/mozilla/firefox/fake.default-release"
chk "T7  bo qua thu muc cache cung ten (moi hon)" \
    "$(ffbase "$H" ff_profile)" "real.default-release"

# 8) profiles.ini tro thu muc khong ton tai -> fallback, khong dua path hong
H=$WORK/h8
ini "$H/.config/mozilla/firefox/profiles.ini" <<'EOF'
[Profile0]
Name=ghost
IsRelative=1
Path=khong-ton-tai
Default=1
EOF
mkprof "$H/.config/mozilla/firefox/thuc.default"
chk "T8  ini tro thu muc hong -> fallback" \
    "$(ffbase "$H" ff_profile)" "thuc.default"

# 9) IsRelative=0 (duong dan tuyet doi) qua override
mkdir -p "$WORK/abs9"
ini "$WORK/abs9/profiles.ini" <<EOF
[InstallQ]
Default=absprof
[Profile0]
Name=absprof
IsRelative=0
Path=$WORK/abs9
EOF
chk "T9  IsRelative=0" \
    "$(ff "$WORK/none" ff_override "$WORK/abs9")" "$WORK/abs9"

# 10) Override tro thang thu muc profile
mkprof "$WORK/direct"
chk "T10 override thang thu muc profile" \
    "$(ff "$WORK/none" ff_override "$WORK/direct")" "$WORK/direct"

# 11) Khong co profile nao -> rong
H=$WORK/h11; mkdir -p "$H/.mozilla"
chk "T11 khong co profile -> rong" "$(ff "$H" ff_profile)" ""

# 12) Ten profile co khoang trang
H=$WORK/h12; mkprof "$H/.mozilla/firefox/my prof.dir"
chk "T12 ten profile co khoang trang" \
    "$(ffbase "$H" ff_profile)" "my prof.dir"

# 13) HOME co khoang trang
H="$WORK/h 13"; mkprof "$H/.mozilla/firefox/sp.default"
chk "T13 HOME co khoang trang" \
    "$(ffbase "$H" ff_profile)" "sp.default"

# 14) Nhieu profile -> phai tra het, khong bo
H=$WORK/h14
mkprof "$H/.mozilla/firefox/one.default-release"
mkprof "$H/.mozilla/firefox/two.default-release"
chk "T14 nhieu profile -> tra het 2" \
    "$(ff "$H" ff_cands | wc -l)" "2"

# 15) firefox_looks_like_cache phan biet dung
mkprof "$WORK/h15/real"
mkdir -p "$WORK/h15/cachedir/cache2"
mkdir -p "$WORK/h15/withbase"; printf 'x' > "$WORK/h15/withbase/profiles.ini"
chk "T15a co prefs.js -> PROFILE"        "$(ff "$WORK/h15" ff_looks "$WORK/h15/real")"     "PROFILE"
chk "T15b co cache2/ -> CACHE"           "$(ff "$WORK/h15" ff_looks "$WORK/h15/cachedir")" "CACHE"
chk "T15c base co profiles.ini -> PROFILE" "$(ff "$WORK/h15" ff_looks "$WORK/h15/withbase")" "PROFILE"

# 16) Khong bao gio tra ve thu muc cache
H=$WORK/h16; mkdir -p "$H/.cache/mozilla/firefox/fake/cache2"
# Thu muc chi co cache2/ -> KHONG co profile nao. Ket qua dung la: rong.
# Neu tra ve duong dan nao thi phai la thu muc cache -> loi.
r="$(ff "$H" ff_profile)"
if [[ -z $r ]]; then
    pass "T16 chi co cache -> khong tra ve gi (dung)"
elif [[ $(ff "$H" ff_looks "$r") == CACHE ]]; then
    bad "T16 tra ve thu muc cache" "out=[$r]"
else
    pass "T16 tra ve profile that, khong phai cache"
fi

# 17) profiles.ini chi Default=1
H=$WORK/h17
ini "$H/.mozilla/firefox/profiles.ini" <<'EOF'
[Profile0]
Name=a
IsRelative=1
Path=zzz.default-release
Default=1
EOF
mkprof "$H/.mozilla/firefox/zzz.default-release"
mkprof "$H/.mozilla/firefox/aaa.default-release"
chk "T17 chi co Default=1" \
    "$(ffbase "$H" ff_profile)" "zzz.default-release"

# 18) Thu tu [Profile*] dao nguoc: phai theo Install, khong roi fallback
H=$WORK/h18
ini "$H/.mozilla/firefox/profiles.ini" <<'EOF'
[Profile0]
Name=empty
IsRelative=1
Path=zz.empty
[InstallX]
Default=aa.real
[Profile1]
Name=real
IsRelative=1
Path=aa.real
EOF
mkprof "$H/.mozilla/firefox/zz.empty"
mkprof "$H/.mozilla/firefox/aa.real"
chk "T18 thu tu [Profile*] dao nguoc" \
    "$(ffbase "$H" ff_profile)" "aa.real"

# 19) Cung mot profile lo ra o nhieu base -> khong trung ten
H=$WORK/h19
mkprof "$H/.mozilla/firefox/same.default"
mkdir -p "$H/.var/app/org.mozilla.firefox/.mozilla"
ln -s "$H/.mozilla/firefox/same.default" \
      "$H/.var/app/org.mozilla.firefox/.mozilla/same.default"
chk "T19 cung profile o nhieu base -> 1" \
    "$(ff "$H" ff_cands | wc -l)" "1"

# 20) Khong duoc tra ve "." (loi da gap: ham nhan rong args qua pipe)
H=$WORK/h20; mkprof "$H/.mozilla/firefox/nodot.default"
r="$(ff "$H" ff_profile)"
if [[ $r == "$H"/* && -d $r ]]; then
    pass "T20 duong dan that (khong phai '.')"
else
    bad "T20 duong dan khong hop le" "out=[$r]"
fi

printf '\n'
if (( FAIL )); then
    printf '  KẾT QUẢ: %d PASS, %d FAIL\n' "$PASS" "$FAIL"
    exit 1
fi
printf '  KẾT QUẢ: %d PASS, 0 FAIL\n' "$PASS"

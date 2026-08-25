#!/bin/bash
# netpanel-band.sh — xem/đặt band Wi-Fi (2.4/5/6 GHz) cho connection đang chạy.
# Adapt từ basecamp/omarchy `bin/omarchy-network-band` (MIT) — giữ nguyên các
# quyết định thiết kế chính: pin BAND chứ không pin BSSID (roaming còn nguyên),
# đọc cache scan (--rescan no), LC_ALL=C, -e no, SSID truyền qua environment,
# và revert setting cũ nếu reconnect thất bại.
#
# Usage:
#   netpanel-band.sh            → in "band <x>", "selected <x>", "available ..."
#   netpanel-band.sh auto|2.4|5|6 → đặt band; in NETPANEL_BAND_OK khi thành công

set -euo pipefail

nm_band_for() {
	case "$1" in
		2.4) echo "bg" ;;
		5)   echo "a" ;;
		6)   echo "6GHz" ;;
		*)   return 1 ;;
	esac
}

band_from_nm() {
	case "$1" in
		bg)   echo "2.4" ;;
		a)    echo "5" ;;
		6GHz) echo "6" ;;
		*)    echo "auto" ;;
	esac
}

# Chấp nhận "2412 MHz" (nmcli) hoặc "5745.0" (iw): lấy phần số nguyên đầu.
# Boundary mirror đúng phía hiển thị để label và lệnh không bao giờ lệch nhau.
band_for_freq() {
	local mhz=${1%%[!0-9]*}
	[[ -n $mhz ]] || return 1

	if ((mhz >= 2400 && mhz < 2500)); then
		echo "2.4"
	elif ((mhz >= 4900 && mhz < 5925)); then
		echo "5"
	elif ((mhz >= 5925 && mhz < 7125)); then
		echo "6"
	else
		return 1
	fi
}

# LC_ALL=C: nmcli dịch state word theo locale; -e no: tắt escaping của -g
# (nếu không ':' và '\' bị escape → SSID escaped không khớp bản raw của iw).
nm_get() {
	LC_ALL=C nmcli -e no -g "$@" 2>/dev/null
}

wifi_device() {
	nm_get DEVICE,TYPE,STATE device status |
		awk -F: '$2 == "wifi" && $3 == "connected" { print $1; exit }'
}

wifi_profile() {
	nm_get GENERAL.CONNECTION device show "$1"
}

selected_band() {
	band_from_nm "$(nm_get 802-11-wireless.band connection show "$1")"
}

read_link() {
	local link
	link=$(iw dev "$1" link 2>/dev/null)
	ssid=$(awk '/SSID:/ { sub(/.*SSID: /, ""); print; exit }' <<<"$link")
	freq=$(awk '/freq:/ { print $2; exit }' <<<"$link")
}

# Mọi band SSID chạm tới được, thấp→cao, LUÔN gồm band đang đứng (radio yếu
# hay bị scan bỏ sót). Band AP không phát thì không bao giờ đưa vào danh sách:
# pin tới nó = mất kết nối không có gì để reassociate. --rescan no đọc cache
# NetworkManager (scanner của panel giữ ấm); ép rescan sẽ stall mỗi poll.
available_bands() {
	local device=$1 ssid=$2 current=$3

	{
		if [[ -n $current ]]; then echo "$current"; fi

		# SSID query cuối để ghép verbatim; truyền qua ENVIRON chứ không -v
		# (-v expand backslash escape trong SSID chứa '\').
		nm_get FREQ,SSID dev wifi list ifname "$device" --rescan no |
			want="$ssid" awk -F: '
				BEGIN { want = ENVIRON["want"] }
				{
					name = $2
					for (i = 3; i <= NF; i++) name = name ":" $i
					if (name == want) print $1
				}' |
			while read -r freq; do band_for_freq "$freq" || true; done
	} | LC_ALL=C sort -u -g | tr '\n' ' ' | sed 's/ $//'
}

print_status() {
	local device profile band available

	device=$(wifi_device || true)
	[[ -n $device ]] || return 0

	read_link "$device"
	[[ -n $ssid ]] || return 0

	band=$(band_for_freq "$freq" || true)
	available=$(available_bands "$device" "$ssid" "$band")
	profile=$(wifi_profile "$device" || true)

	printf 'band %s\n' "${band:-?}"
	printf 'available %s\n' "$available"
	if [[ -n $profile ]]; then printf 'selected %s\n' "$(selected_band "$profile")"; fi
}

set_band() {
	local target=$1 device profile previous desired

	device=$(wifi_device || true)
	[[ -n $device ]] || { echo "Error: no connected Wi-Fi device." >&2; exit 1; }

	profile=$(wifi_profile "$device" || true)
	[[ -n $profile ]] || { echo "Error: no active Wi-Fi profile." >&2; exit 1; }

	if [[ $target == "auto" ]]; then
		desired=""
	else
		read_link "$device"
		if [[ " $(available_bands "$device" "$ssid" "$(band_for_freq "$freq" || true)") " != *" $target "* ]]; then
			echo "Error: ${target}GHz is not available on this network." >&2
			exit 1
		fi
		desired=$(nm_band_for "$target")
	fi

	previous=$(nm_get 802-11-wireless.band connection show "$profile" || true)
	[[ $previous == "$desired" ]] && { echo "NETPANEL_BAND_OK"; exit 0; }

	nmcli connection modify "$profile" 802-11-wireless.band "$desired" >/dev/null

	# Đổi band chỉ có hiệu lực sau reassociation. Radio không lên nổi band
	# mới → hoàn tác setting cũ và reconnect lại: không bao giờ bỏ máy offline.
	if ! nmcli connection up "$profile" >/dev/null 2>&1; then
		nmcli connection modify "$profile" 802-11-wireless.band "$previous" >/dev/null
		nmcli connection up "$profile" >/dev/null 2>&1 || true
		echo "Error: could not connect on ${target}; reverted to previous band." >&2
		exit 1
	fi
	echo "NETPANEL_BAND_OK"
}

usage() {
	echo "Usage: netpanel-band.sh [auto|2.4|5|6]" >&2
}

if (($# == 0)); then
	print_status
	exit 0
fi

if (($# > 1)); then
	usage
	exit 1
fi

case "$1" in
	auto | 2.4 | 5 | 6) set_band "$1" ;;
	*) usage; exit 1 ;;
esac

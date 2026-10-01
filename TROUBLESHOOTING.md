# TROUBLESHOOTING

Sự cố với `dwm` Tsuki. Mọi mục ở đây đều kiểm được bằng lệnh trên máy đang chạy.

## Nhật ký phiên

`scripts/run.sh` ghi lại mọi thứ nó làm vào `~/.cache/tsuki/session.log`, **ghi đè
mỗi lần đăng nhập**. Đây là bước đầu tiên cho mọi triệu chứng dưới đây:

```sh
less ~/.cache/tsuki/session.log
```

Ghi trực tiếp từ `run.sh:27`. Nếu file không tồn tại thì `run.sh` chưa từng chạy
trong phiên này — thường là vì `.xinitrc` chưa trỏ tới nó.

## Màn hình tự tắt / monitor ngủ

`run.sh` **tắt** screensaver và DPMS của X server:

```sh
xset s off && xset -dpms
```

Lý do: X server mặc định blank sau 600 giây và bật DPMS với cả ba mốc 600 —
rời chuột 10 phút là màn hình trắng rồi monitor ngủ. Trên X thuần không có idle
daemon nào cấu hình được, và nó quay lại **không khoá** (Tsuki chỉ khoá bằng
`Super+Delete`, không tự khoá).

Bật lại trước khi `startx`:

| Biến | Tác dụng |
|---|---|
| `TSUKI_SCREENSAVER=600` | blank sau 600 giây, vẫn tắt DPMS |
| `TSUKI_SCREENSAVER=off` | không blank — **mặc định** |
| `TSUKI_SCREENSAVER=keep` | giữ nguyên cấu hình X server |

Kiểm trạng thái hiện tại:

```sh
xset q | sed -n '/Screen Saver/,/^$/p'
```

## Daemon nào đang chạy

```sh
for d in "$XDG_RUNTIME_DIR"/tsuki-*.lock; do
  n=${d##*/tsuki-}; n=${n%.lock}
  printf '%-12s %s\n' "$n" \
    "$(flock -n "$d" -c true 2>/dev/null && echo TRONG || echo 'ĐÃ GIỮ')"
done
```

Ra `ĐÃ GIỮ` nghĩa là còn sống. `run.sh` khoá bằng `flock` (fd 8) chứ không
kiểm pidfile, nên gọi lại `run.sh` không sinh bản thứ hai — khoá tự thả khi tiến
trình chết, kể cả khi bị `kill -9`.

Có pidfile để tiện tra ở `$XDG_RUNTIME_DIR/tsuki-<tên>.pid`, **nhưng đừng
`kill` theo nó** khi lệnh tự daemonize. `fcitx5 -d` fork rồi thoát, nên pid
trong pidfile là tiến trình cha đã chết; daemon thật là pid khác. Hỏi khoá
thay vì hỏi pid:

```sh
fuser "$XDG_RUNTIME_DIR/tsuki-fcitx.lock"
```

`run.sh` khởi động: nền (`feh`), `picom`, `xrdb`, con trỏ, tốc độ lặp phím,
`dunst` + `xdg-desktop-portal` (+ `-gtk`), `polkit-gnome`, `fcitx5`,
`xsettingsd`, `slstatus`, `tumblerd`, và hai script nền `updates-loop.sh` /
`mediacard.sh`. Mỗi cái giữ một khoá `flock` trong `$XDG_RUNTIME_DIR` nên gọi lại
`run.sh` không sinh bản thứ hai.

## Watchdog

Daemon chết giữa phiên được khởi động lại trong **15 giây**:

```
WARN  watchdog: xsettingsd đã chết — khởi động lại (lần 1/5)
```

Chỉ áp dụng cho daemon không tự phục hồi. `slstatus`, `updates-loop.sh` và
`mediacard.sh` có vòng lặp riêng nên tự lại; `dunst` và portal do `systemd --user`
lo. Watchdog giám sát `picom`, `fcitx5`, `xsettingsd`, `tumblerd`, `polkit-gnome`
— và `dunst`/portal khi không có systemd user bus.

**Có trần 5 lần.** Daemon chết 5 lần thì watchdog bỏ qua và ghi:

```
WARN  watchdog: <tên> đã thử lại 5 lần vẫn chết — bỏ qua, xem nhật ký phiên
```

Thử vô hạn thì tệ hơn lúc đầu — log đầy, CPU quay, nguyên nhân gốc bị chôn dưới
hàng nghìn dòng "đã thử lại". Gặp dòng này thì đó mới là lỗi thật cần tra.

Daemon vốn không bao giờ chạy được (thiếu binary) chỉ báo **một lần**:

```
WARN  watchdog: không khởi động được <tên> (thiếu binary?) — bỏ qua
```

Nếu `dunst` im lặng mà bạn vừa cài, chạy `./install.sh deps` rồi đăng nhập lại.

Muốn đổi nhịp: `WD_INTERVAL` và `WD_MAX_RETRY` đọc từ môi trường, đặt trước khi
`startx`.

## "đã có run.sh khác đang giữ phiên này"

```
tsuki: đã có run.sh khác đang giữ phiên này (pid 2845) — không khởi động lần hai
```

`run.sh` giữ một khoá phiên trong `$XDG_RUNTIME_DIR/tsuki-session.claim`, nên chỉ
một bản được chạy cho mỗi phiên. Bản thứ hai **thoát ngay** thay vì ghi đè.

Đây là chủ ý. Trước khi có khoá, bản thứ hai khi thoát gọi `stop_daemons` — mà
`stop_daemons` xoá `tsuki-*.lock` + `tsuki-*.pid` rồi `kill` pid ghi trong đó,
tức là dọn **daemon của bản thứ nhất**. Đã gặp đúng sự cố đó: daemon của phiên
đang chạy bị giết hết, watchdog thấy khoá biến mất nên hồi sinh, `polkit` chết
hẳn sau 5 lần thử, `session.log` bị ghi đè.

Thường gặp khi `.xinitrc` chạy `run.sh` mà bạn lại gõ `startx` thủ công, hoặc vô
tình chạy `run.sh` hai lần để "sửa lỗi". Muốn chạy lại trong cùng phiên thì
thoát hẳn trước:

```sh
kill <pid>   # pid in ra trong thông báo
```

Rồi `startx`. Còn muốn kiểm tra xem phiên hiện tại còn sống không:

```sh
cat "$XDG_RUNTIME_DIR/tsuki-session.owner"
```

## Daemon sống sót qua logout

`fcitx5 -d` tự fork: tiến trình launcher thoát ngay, còn daemon thật giữ khoá.
Nên `tsuki-fcitx.pid` trỏ tới một PID **đã chết**, và `kill` theo pidfile là kill
một PID không tồn tại — im lặng, không báo gì, tưởng đã dọn.

`stop_daemons` nay dùng `fuser` trên từng file khoá để giết đúng tiến trình
đang giữ nó, không chỉ dựa vào pidfile.

Dấu hiệu daemon đã mất dấu: khoá **tồn tại nhưng trống**, tức không ai giữ:

```sh
fuser "$XDG_RUNTIME_DIR/tsuki-fcitx.lock"   # không in gì = mất dấu
```

Thường do `stop_daemons` chạy lúc `XDG_RUNTIME_DIR` bị dọn giữa chừng, hoặc
`run.sh` bị giết cưỡng (`kill -9`) nên trap không kịp dọn. Khắc phục: đăng nhập
lại. Còn muốn xem trạng thái hiện tại:

```sh
fuser "$XDG_RUNTIME_DIR"/tsuki-*.lock
```

## Con trỏ không đổi

`run.sh` nạp con trỏ bằng `xsetroot -xcf` từ theme `Bibata-Modern-Ice`, cỡ 24.
Nếu không đổi, tìm dòng `warn_cursor` trong `session.log`:

```sh
grep cursor ~/.cache/tsuki/session.log
```

**Không có dòng nào ra = con trỏ nạp bình thường.** Có dòng `WARN` mới là lỗi.
Hai nguyên nhân thường gặp, cả hai đều do thiếu gói:

- `chưa cài theme cursor` → `./install.sh deps`
- `thiếu xorg-xsetroot` → `./install.sh deps`

## Volume không hiện OSD

OSD do `dunst` vẽ. `run.sh` ưu tiên bật nó qua `systemd --user`; nếu không có
user bus thì mới tự chạy. Xem dòng đầu `session.log`:

```
INFO  dunst/portal: qua systemd --user
```

Có dòng đó nghĩa là dunst do systemd quản lý — đừng `pkill dunst`, sẽ bị systemd
dựng lại và OSD vẫn phải cấu hình lại. Nếu thấy `WARN ... không có systemd
user bus`, máy đang thiếu `dbus` hoặc `systemd` chưa bật user session.

## Hộp thoại lưu file của Firefox không dựng

Firefox hỏi `xdg-desktop-portal` qua D-Bus. Kiểm:

```sh
systemctl --user is-active xdg-desktop-portal.service
```

`inactive` nghĩa là chưa bật. Portal chỉ khởi động cùng `run.sh` khi có user
bus, nên nếu `session.log` không có dòng `dunst/portal` thì đây là hệ quả của
vấn đề bus ở mục trên.

## Thumbnail trong Thunar không có

Thunar **không tự sinh ảnh nhỏ** — nó hỏi `tumblerd` qua D-Bus. Ba gói tách
biệt, thiếu cái nào thì mất đúng loại file đó:

| Gói | Loại |
|---|---|
| `tumbler` | ảnh |
| `ffmpegthumbnailer` | video |
| `poppler-glib` | PDF |

Chuỗi đầy đủ:

```sh
./scripts/check-thumbs.sh
```

**Cạm bẫy hay gặp nhất:** binary `tumblerd` **không có trong `PATH`**. Nó nằm ở
`/usr/lib/tumbler-1/tumblerd`, nên gõ `tumblerd &` sẽ báo *command not found*.
`run.sh` tự dò lần lượt ba vị trí nên không dính, nhưng nếu bạn tự khởi động
thì phải dùng đường dẫn đầy đủ:

```sh
/usr/lib/tumbler-1/tumblerd &
```

Nếu Thunar vẫn không có thumbnail sau khi daemon chạy, xoá cache rồi thử lại:

```sh
rm -rf ~/.cache/thumbnails
```

## Thunar không có mục "Thùng rác" / "Giải nén" / ổ USB trong sidebar

**Cần khởi động lại Thunar sau khi cài gói.** Đây là cạm bẫy hay gặp nhất, vì
cài xong mọi thứ vẫn *thấy* thiếu mà không có lỗi nào báo.

Lý do: sidebar không phải đọc cấu hình rồi vẽ. Nó dựng **model một lần** lúc
mở cửa sổ — `thunar_shortcuts_model_places()` trong `thunar-shortcuts-model.c`,
gọi từ `thunar_shortcuts_model_new()`. Hàm đó kiểm từng thứ rồi mới thêm:

| Mục sidebar | Điều kiện | Cần gói |
|---|---|---|
| Thùng rác | `thunar_g_vfs_is_uri_scheme_supported("trash")` | `gvfs` |
| Giải nén (chuột phải) | plugin có wrapper `.tap` cho app | `thunar-archive-plugin` + `file-roller` |
| Ổ USB / đĩa cỡi được | GVolumeMonitor hỏi `udisks2` qua system bus | `udisks2` |

Thunar mở trước khi cài xong thì nó đã bỏ qua các nhánh đó, và model **không tự
dựng lại** khi có gói mới. Cài xong mà không đóng lại Thunar thì cứ tưởng cài
hỏng.

```sh
pkill -x Thunar   # tên tiến trình viết HOA chữ T đầu
```

**Cạm bẫy khi tự chẩn đoán:** `pgrep -a thunar` **không** thấy Thunar, vì tên
tiến trình là `Thunar` (hoa chữ T) còn lệnh gõ chữ thường — `pgrep` phân biệt
hoa thường. Dùng:

```sh
pgrep -a -x Thunar                  # có đang mở không
ps -eo lstart,comm | grep -i thunar # mở từ lúc nào
ps -eo lstart,comm | grep -E 'gvfsd|udisksd'   # daemon khởi động lúc nào
```

So sánh hai mốc thời gian đó. Nếu Thunar mở **trước** daemon, đó chính là
nguyên nhân — đóng lại là xong, không phải cài thêm gì. Nếu Thunar mở **sau**
mà vẫn thiếu, kiểm backend có thật sự không:

```sh
gio list trash://    # phải không lỗi
gio mount -l         # phải thấy ổ USB
```

## Menu "Giải nén" không có dù đã cài đủ mọi gói

`thunar-archive-plugin` **không** gọi `7z`. Nó dò file wrapper
`/usr/lib/xfce4/thunar-archive-plugin/<tên>.tap` cho từng app đăng ký với
mime type, rồi loại app không có wrapper. Ở bản 0.6.0 chỉ có wrapper cho `ark`,
`engrampa`, `file-roller`, `peazip` — **không có `7z.tap`**.

Nên cài `7z`/`zip`/`unrar` (nhóm `PKG_ARCHIVE`) sẽ **không** tạo ra mục này.
Phải có đúng một app trong danh sách bốn app trên.

```sh
ls /usr/lib/xfce4/thunar-archive-plugin/
```

## `dwm` không lên được

`run.sh` không quay vòng vô tận. Ba hành vi, tất cả đều ghi vào `session.log`:

- sống ≥10s rồi chết → nghỉ 0.3s rồi nạp lại (coi là bình thường)
- sống <10s → nghỉ tăng dần 0.3 → 0.6 → 1.2 → trần 2s
- **10 lần liên tiếp không lên nổi → dừng hẳn**, in nguyên nhân và thoát

Dừng hẳn là để tránh quay vòng mãi khi `config.h` sai cú pháp. Thấy dòng
`dwm crash liên tiếp ... DỪNG` thì đọc phần log ngay trước đó — thường là lỗi
build hoặc thiếu font. Sửa xong thì `Super+Shift+R`.

### Thiếu font — nguyên nhân số một

`dwm.c` chết ngay nếu không nạp được font nào: `if (!drw_fontset_create(...)) die("no fonts could be loaded.")`.
Triệu chứng là màn hình đen, không bar, không cửa sổ nào.

`run.sh` kiểm trước khi chạy dwm và ghi vào nhật ký:

```
FAIL  dwm SẼ CHẾT NGAY: config.h trỏ font không có trên máy:
FAIL      <tên font>  -> fontconfig thay bằng '<font khác>'
```

Cài rồi nạp lại cache:

```sh
sudo pacman -S --needed ttc-iosevka ttf-jetbrains-mono-nerd
fc-cache -f
```

Rồi `Super+Shift+R`. Danh sách font được đọc từ `config.h` nên sửa `config.h`
sẽ được kiểm lại ở lần đăng nhập sau — không cần sửa gì trong `run.sh`.

Mọi lỗi dwm in ra đều được `run.sh` ghi lại vào nhật ký theo từng lần chết, nên
đọc `session.log` là thấy nguyên nhân thật thay vì phải đoán.

## Bộ gõ tiếng Việt

```sh
grep -i fcitx ~/.cache/tsuki/session.log
pgrep -a fcitx5
```

Cần cả hai dòng: `fcitx5-lotus-server` (engine) và `fcitx5` (daemon). Thiếu
engine thì chạy `./install.sh pty`.

Nếu `ibus-daemon` tự quay lại ở lần đăng nhập sau, phải bỏ autostart của ibus
trong desktop environment — `install.sh` chỉ dừng được tiến trình, không tắt
được autostart.

## Sửa xong thì đăng nhập lại

`config.h` chỉ có hiệu lực khi `dwm` nạp lại. `Super+Shift+R` build và nạp
ngay trong phiên đang chạy, nhưng thay đổi trong `scripts/run.sh` cần logout rồi
đăng nhập lại — nó chỉ chạy một lần mỗi phiên.

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
`mediacard.sh`.

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

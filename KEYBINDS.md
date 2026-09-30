# dwm 6.8 Keybindings

> MODKEY = Super (Windows key)

## Launch apps
| Keybinding    | Action                    |
|---------------|---------------------------|
| Super + Enter | st (term)                 |
| Super + r     | dmenu_run                 |
| Super + c     | code                      |
| Super + s     | firefox                   |
| Super + g     | steam                     |
| Super + p     | EPOS GSX 300 GUI          |
| Super + d     | discord-ptb               |
| Super + e     | thunar                    |
| Super + z     | zalo                      |
| Super + /     | Bảng keybinds này         |
| Super + w     | Đổi wallpaper + màu theme |

### Thumbnail trong Thunar

`Super + e` mở Thunar. Thunar **không tự** vẽ ảnh nhỏ — nó hỏi daemon
`tumblerd` qua D-Bus (Thumbnailer Specification), tumbler gọi plugin rồi ghi
vào `~/.cache/thumbnails/` theo chuẩn freedesktop.

| Loại file | Plugin | Gói cài |
|---|---|---|
| Ảnh (png/jpg/gif/webp/bmp/tiff/avif/jxl/svg) | `tumbler-pixbuf-thumbnailer` | `tumbler` |
| JPEG (tốc độ riêng) | `tumbler-jpeg-thumbnailer` | `tumbler` |
| Video (mp4/mkv/webm/avi/mov/m4v) | `tumbler-ffmpeg-thumbnailer` | `ffmpegthumbnailer` |
| PDF | `tumbler-poppler-thumbnailer` | `poppler-glib` |
| Ảnh RAW máy ảnh | `tumbler-raw-thumbnailer` | `libopenraw` |
| Phông chữ | `tumbler-font-thumbnailer` | `freetype2` |
| ODF (odt/ods/odp) | `tumbler-odf-thumbnailer` | `libgsf` |
| Bìa sách, desktop, EPUB | `cover` / `desktop` / `gepub` | `libgepub` (tùy chọn) |

Lần đầu mở một thư mục, thumbnail sẽ trống rồi mới có sau vài giây — đó là
tumbler đang sinh. Lần sau tải từ cache, tức thì.

Kiểm tra chuỗi này còn sống hay không:

```sh
./scripts/check-thumbs.sh           # kiểm tra + tự sinh thử ảnh và video
./scripts/check-thumbs.sh --clean   # xoá sạch cache rồi thử lại
```

Nếu Thunar vẫn chỉ hiện icon, chạy `/usr/lib/tumbler-1/tumblerd &` hoặc đăng
nhập lại — `scripts/run.sh` sẽ tự khởi động daemon này.

> Binary `tumblerd` **không có trong `PATH`**: gói `tumbler` đặt nó ở
> `/usr/lib/tumbler-1/tumblerd`. Gõ `tumblerd &` sẽ báo *command not found* —
> phải dùng đường dẫn đầy đủ.

## Tiling / window management

| Keybinding            | Action               |
|-----------------------|----------------------|
| Super + b             | Toggle bar           |
| Super + j / k         | Focus next/prev      |
| Super + i             | Inc nmaster          |
| Super + Shift + j / k | Move stack (down/up) |
| Super + Shift + Enter | Zoom master          |
| Super + h / l         | Master area +/-      |
| Super + Shift + h / l | Client factor +/-    |
| Super + Shift + o     | Reset cfactor        |
| Super + Tab           | Previous view        |
| Super + f             | Toggle fullscreen    |
| Super + Shift + Space | Toggle floating      |
| Super + Ctrl + w      | Tab mode             |
| Super + Ctrl + q      | Restart dwm (re-exec)  |
| Super + Ctrl + Del    | Shutdown system      |
| Super + Del           | Lock screen (slock)  |
| Super + q             | Kill client          |
| Super + Shift + r     | Rebuild & reload     |

## Layouts

| Keybinding               | Action               |
|--------------------------|----------------------|
| Super + t                | tile                 |
| Super + Shift + f        | monocle              |
| Super + m                | spiral               |
| Super + Ctrl + g         | gaplessgrid           |
| Super + Ctrl + Shift + t | floating             |
| Super + Space            | next layout          |
| Super + Ctrl + , / .     | previous/next layout |

## Tags

| Keybinding                 | Action             |
|----------------------------|--------------------|
| Super + 1-9                | Switch view        |
| Super + Ctrl + 1-9         | Toggle view tag    |
| Super + Shift + 1-9        | Move client to tag |
| Super + Ctrl + Shift + 1-9 | Toggle client tag  |
| Super + 0                  | View all tags      |
| Super + Shift + 0          | Tag all            |

## Monitors

| Keybinding            | Action                           |
|-----------------------|----------------------------------|
| Super + Left / Right  | Next/prev monitor view           |
| Super + , / .         | Focus prev/next monitor          |
| Super + Shift + , / . | Move client to prev/next monitor |

## Gaps

| Keybinding               | Action                     |
|--------------------------|----------------------------|
| Super + Ctrl + t         | Toggle gaps                |
| Super + Ctrl + i / d     | All gaps +/-              |
| Super + Ctrl + Shift + i | Inner gap +/-             |
| Super + Ctrl + o / Ctrl+Shift+o | Outer gap +/-       |
| Super + Ctrl + 6 / 7     | Inner H/V gap +/- (Shift = -) |
| Super + Ctrl + 8 / 9     | Outer H/V gap +/- (Shift = -) |
| Super + Ctrl + Shift + d | Reset gaps                 |

## Screenshots

| Keybinding       | Action                                       |
|------------------|----------------------------------------------|
| Super + Ctrl + u | Fullscreen -> clipboard                      |
| Super + u        | Area select -> clipboard                     |
| Print            | Fullscreen -> clipboard (raw, không mở GUI)  |
| Print (trong Super+W picker) | Fullscreen chụp cả picker -> ~/Pictures + clipboard |

## Media / brightness

| Keybinding        | Action                       |
|-------------------|------------------------------|
| AudioUp/Down/Mute | Volume +/- / mute (kèm card) |
| BrightnessUp/Down | Brightness +/-               |

## Hide / focus

| Keybinding        | Action      |
|-------------------|-------------|
| Super + x         | Hide client |
| Super + Shift + x | Restore     |

## Borders

| Keybinding        | Action          |
|-------------------|-----------------|
| Super + Shift + - | Decrease border |
| Super + Shift + p | Increase border |
| Super + Shift + w | Reset border    |

## Terminal (st)

| Phím                            | Action                          |
|---------------------------------|---------------------------------|
| Lăn chuột lên / xuống          | Cuộn 1 dòng                    |
| Giữ chuột trái, kéo tới mép trên/dưới | Tự cuộn liên tục        |
| Shift + PgUp / PgDn             | Cuộn 1 trang                    |
| Alt + lăn chuột                 | Gửi `\031` (page up) tới app   |

## Khi có sự cố

`scripts/run.sh` ghi lại toàn bộ phiên vào `~/.cache/tsuki/session.log`
(ghi đè mỗi lần đăng nhập). Xem nó là bước đầu tiên khi con trỏ không đổi,
phím volume không hiện OSD, hộp thoại lưu file của Firefox không dựng, hoặc
thumbnail Thunar không có:

```sh
less ~/.cache/tsuki/session.log
```

Những gì `run.sh` khởi động: nền (`feh`), `picom`, `xrdb`, con trỏ
(`xsetroot -xcf`), tốc độ lặp phím (`xset r rate`), dunst, xdg-desktop-portal,
polkit-gnome, fcitx5, xsettingsd, slstatus, tumblerd, và hai script nền
`updates-loop.sh` / `mediacard.sh`.

Mỗi daemon giữ một khoá `flock` trong `$XDG_RUNTIME_DIR`, nên gọi lại
`run.sh` không sinh bản thứ hai. Muốn dừng tay:

```sh
pkill -f 'run\.sh$'; pkill -x tumblerd; pkill -x xsettingsd; pkill -x fcitx5
```

Nếu `dwm` không lên được, `run.sh` **tự dừng** sau 10 lần crash liên tiếp
thay vì quay vòng vô tận, và in trong log hướng khôi phục.

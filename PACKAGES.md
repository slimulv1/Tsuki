# Gói cài đặt

`./install.sh` cài **73 gói** (không tính trùng lặp, toàn bộ bảy mảng), khoảng
**2.9 GiB** đã cài trên máy. Danh sách này rút từ bảy mảng gói trong
`install.sh` — mỗi mảng là một nhóm, và nhóm quyết định **lúc nào** được cài.

Muốn xem nhanh: `./install.sh -h`. Muốn biết cài gì: trang này.

| Nhóm trong `install.sh` | Cài ở bước | Số gói | Dung lượng |
|---|---|---|---|
| `PKG_BUILD` | `deps` | 18 | 66 MiB |
| `PKG_SESSION` | `deps` | 18 | 372 MiB |
| `PKG_CONFIG` | `deps` | 9 | 462 MiB |
| `PKG_KEYBINDS` | `deps` (cần kho arisa) | 23 | 1.8 GiB |
| `PKG_AUR` | `deps` | 1 | 292 MiB |
| `PKG_PTY` | `pty` (cần `paru`) | 2 | 3.5 MiB |

Tổng các dòng trên lớn hơn 2.9 GiB vì `gtk3` nằm ở cả hai nhóm và bị đếm hai
lần. Xem [gtk3 xuất hiện hai lần](#gtk3-xuất-hiện-hai-lần).

Mười gói nặng nhất:

| Gói | Dung lượng | Vì sao |
|---|---|---|
| `visual-studio-code-bin` | 979 MiB | VS Code bản nhị phân — gói lớn nhất, từ kho arisa |
| `ttc-iosevka` | 446 MiB | font chữ cho dwm/dmenu. Thiếu thì mọi chữ trên bar là ô vuông |
| `bibata-cursor-theme` | 322 MiB | theme con trỏ — gói này lớn bất thường, từ kho arisa |
| `firefox` | 299 MiB | trình duyệt, kéo theo `ffmpeg` |
| `cargo` | 292 MiB | thực chất là gói `rust` (xem [cargo](#cargo-không-phải-một-gói-riêng)) |
| `ttf-jetbrains-mono-nerd` | 232 MiB | font monospace cho `st` |
| `kitty` | 77 MiB | terminal |
| `gtk3` | 54 MiB | nền cho theme con trỏ trong app GTK3 |
| `python-numpy` | 50 MiB | `wallpicker.py` tính màu wallpaper |
| `git` | 36 MiB | clone theme và repo theme |

Muốn bỏ tối đa mà vẫn có desktop chạy được, từ chối kho arisa là đủ — nó loại
ba gói 1.3 GiB:

| Gói | Dung lượng |
|---|---|
| `visual-studio-code-bin` | 979 MiB |
| `bibata-cursor-theme` | 322 MiB |
| `discord-ptb` | 6.4 MiB |

Cộng `steam` (20 MiB, không gắn phím nào) thì **1.30 GiB**. Cách bỏ: chạy
`./install.sh deps` cho tới khi nó hỏi kho arisa, từ chối, rồi
`./install.sh session` để cài phần còn lại.

Đổi lại mất theme con trỏ X11 — xem [mục kế bên](#bibata-cursor-theme-cũng-cần-kho-arisa-không-chỉ-hai-gói-kia).

---

## 1. `PKG_BUILD` — toolchain và thư viện để biên dịch (18 gói, 66 MiB)

Không phải app, mà là thứ `make` cần để build dwm/st/slock/dmenu/slstatus.

| Gói | Vai trò |
|---|---|
| `base-devel` | cc, ld, và các gói con |
| `make` | chạy Makefile |
| `pkgconf` | `pkg-config`, dùng bởi `netpanel/config.mk` và `Makefile.imgdec` |
| `diffutils` | `cmp`/`diff`: `install.sh` so nội dung dotfile trước khi ghi đè. **Không thuộc `base` cũng không thuộc `base-devel`** — chỉ là phụ thuộc của `autoconf`/`devtools`/`mkinitcpio`/`steam`, nên máy tối giản sẽ thiếu |
| `git` | chỉ để clone repo rồi chạy `install.sh`; Makefile nào cũng không gọi git |
| `libx11` `libxft` `libxinerama` `libxrender` | dwm + dmenu: `-lfontconfig -lXft -lXinerama -lXrender -lX11` |
| `fontconfig` `freetype2` `harfbuzz` | drw tự dựng: `-lfontconfig` kéo theo hai gói sau |
| `imlib2` | dwm: `-lImlib2` |
| `libxcrypt` `libxext` `libxrandr` | slock (`-lcrypt -lXext -lXrandr`) |
| `libjpeg-turbo` `libwebp` | `Makefile.imgdec`: `pkg-config libturbojpeg libwebp` |

## 2. `PKG_SESSION` — X server và nền session (18 gói, 372 MiB)

Phần lớn là app mà `run.sh` gọi thẳng, hoặc thứ mà `.Xresources` cần.

| Gói | Vai trò |
|---|---|
| `xorg-server` | X server. Tên gói vẫn là vậy dù XLibre cài — XLibre khai `Provides: xorg-server` nên khi có XLib rồi thì dòng này tự thấy đủ, **không** kéo X.Org xuống |
| `xorg-xinit` | `startx` |
| `xorg-xrdb` `xorg-xset` | `run.sh` nạp `.Xresources` (xrdb), đổi nền chuột (xset) |
| `xorg-xsetroot` | `xsetroot -cursor_name` nạp theme con trỏ vào X core cursor font |
| `bibata-cursor-theme` | theme con trỏ. Bắt buộc nằm ở `/usr/share/icons` — libXcursor chỉ tìm trong `/usr/share/icons` và `/usr/share/pixmaps`, **không** tìm `~/.icons` hay `~/.local/share/icons` |
| `feh` | vẽ wallpaper |
| `libnotify` | cấp `notify-send` |
| `polkit-gnome` | hộp thoại hỏi mật khẩu cho `pkexec` — không có nó thì prompt rơi vào terminal |
| `dash` | mọi script trong repo shebang `#!/bin/dash`, `config.h` cũng spawn bằng `dash` |
| `thunar` | `Super+e` — quản lý file |
| `thunar-archive-plugin` `file-roller` | chuột phải có mục **Giải nén**. Bắt buộc phải có *một app GUI* — plugin không gọi `7z`, nó dò wrapper `.tap` theo tên app mà repo chính thức chỉ có cho `ark`/`engrampa`/`file-roller`/`peazip` |
| `gvfs` | thùng rác, đĩa USB, máy tép MTP/SMB. Không có nó thì sidebar Thunar không hiện mục Thùng rác |
| `tumbler` | daemon thumbnail. Không có thì Thunar toàn icon chữ cái |
| `ffmpegthumbnailer` | thumbnail video (mp4/mkv/webm/avi/mov/m4v) |
| `poppler-glib` | trang đầu PDF. Không có thì PDF hiện icon trắng |
| `fcitx5` | daemon bộ gõ. Thiếu vẫn có bàn phím, mất gõ tiếng Việt. Engine Lotus ở nhóm `PKG_PTY` |

## 3. `PKG_CONFIG` — app có sẵn dotfile trong `~/.config` (9 gói, 462 MiB)

Nhóm này và `items` trong `cmd_dotfiles` phải khớp **1-1**: mỗi gói ở đây có
một thư mục `.config/<tên>/` được chép sang.

| Gói | Dotfile |
|---|---|
| `dunst` | `.config/dunst/` |
| `fastfetch` | `.config/fastfetch/` |
| `firefox` | `.config/firefox/` |
| `fish` | `.config/fish/` |
| `gtk3` | `.config/gtk-3.0/` — theme con trỏ cho app GTK3 |
| `kitty` | `.config/kitty/` |
| `picom` | `.config/picom/` |
| `starship` | `.config/starship.toml` |
| `xsettingsd` | `.config/xsettingsd/` |

## 3b. `PKG_ARCHIVE` — công cụ nén / giải nén (3 gói, 4.6 MiB)

Không nằm trong `all` — cài riêng bằng `./install.sh archive`.

| Gói | Vai trò |
|---|---|
| `7zip` | đa định dạng: 7z, zip, tar.*, gz, bz2, xz, zst, iso, wim |
| `zip` | tạo `.zip` — nhanh hơn 7z nhiều với file zip đơn giản |
| `unrar` | **cách duy nhất giải nén `.rar`** trên kho CachyOS |

**Về RAR, đọc kỹ trước khi tìm cách khác.** `7z` không tạo/nén được RAR: mã
giải nén RAR "không hoàn toàn tự do", nên Arch tách nó ra gói `p7zip-rar` riêng.
Gói đó **không có trong kho CachyOS** (đo: `pacman -Si p7zip-rar` → *not found*).
Nên `unrar` là bắt buộc, không phải tuỳ chọn.

**Không cài `atool`/`patool`** — chúng chỉ là wrapper gọi lệnh con, thêm một
tầng trừu tượng trong khi `7z` đã làm hết việc. **Không cài GUI** (`file-roller`,
`engrampa`, `ark`, `xarchiver`) — chúng kéo theo cả GNOME/KDE/MATE, thừa cho
dwm không có DE.

## 4. `PKG_KEYBINDS` — app mở bằng phím tắt (23 gói, 1.8 GiB)

Nhóm lớn nhất, và cũng là nhóm **cần kho arisa**.

| Gói | Phím / dùng để |
|---|---|
| `visual-studio-code-bin` | `Super+C` — **từ kho arisa** |
| `discord-ptb` | `Super+D` — **từ kho arisa** |
| `steam` | không có phím, cài cho sẵn |
| `firefox-tridactyl` | extension điều khiển Firefox kiểu Vim. Có sẵn trong `extra` |
| `scrot` `xclip` | `Super+Ctrl+U` / `Super+U` / `Print` — chụp màn hình |
| `libpulse` `playerctl` `curl` | volume: `pactl` đọc volume, `playerctl` đọc metadata, `curl` tải ảnh bìa |
| `bat` `less` | `Super+/` mở bảng keybind. `less` là nhánh dự phòng cho `bat` |
| `python-gobject` `python-cairo` `python-pillow` `python-numpy` `gtk3` | `Super+W` → `wallpicker.py` |
| `networkmanager` `iw` `qrencode` `iproute2` `util-linux` | click icon mạng → `netpanel.sh`: đọc wifi, băng tần, vẽ QR, tìm interface, canh cột |
| `ttc-iosevka` `ttf-jetbrains-mono-nerd` | `Super+R` dmenu, và chữ trên bar. Thiếu font thì mọi chữ là ô vuông |

## 5. `PKG_AUR` — toolchain để build gói AUR (1 gói, 292 MiB)

`cargo`. Xem [cargo không phải một gói riêng](#cargo-không-phải-một-gói-riêng).

## 6. `PKG_PTY` — bộ gõ và Tridactyl native (2 gói, 3.5 MiB)

Cài bằng `paru` (AUR), **không** dùng `pacman`.

| Gói | Vai trò |
|---|---|
| `fcitx5-lotus-bin` | engine Lotus — bộ gõ tiếng Việt |
| `firefox-tridactyl-native` | native messenger của Tridactyl. Thiếu thì extension vẫn chạy nhưng mọi tính năng cần native bị chặn: `:nativeinstall`, `:restart`, `:setpref`, `:guiset`, `:saveas`, và dấu `!` |

---

## Không phải gói: XLibre (tuỳ chọn)

`./install.sh xlibre` thay X.Org bằng XLibre. Chỉ cài trực tiếp 2 gói:

- `xlibre-meta` — gói meta, tự kéo phần còn lại
- `xorg-xdpyinfo`

**Mọi lệnh `xlibre` đều chạy `pacman -Syyu`, tức nâng cấp TOÀN HỆ THỐNG.** Arch
không hỗ trợ partial upgrade nên đồng ý hàng loạt có thể để lại hệ thống lệch
phiên bản. Đọc danh sách gói trước khi đồng ý.

Mặc định kênh là `stable`; `beta` và `oldstable` có sẵn. Kênh sai bị chặn ngay:
`kênh lạ: foo (chỉ stable | beta | oldstable)`.

`./install.sh deps` đã tự hỏi rồi cài XLibre **stable**, nên không cần chạy
`xlibre` chỉ để "chuyển sang XLibre" — lệnh đó chỉ để đổi kênh.

## Không phải gói: theme và icon tải từ Git

`./install.sh themes` clone rồi copy, cài ở mức **user** (`~/.themes`,
`~/.local/share/icons`) chứ không phải `/usr/share` — không cần root và không
đụng theme của user khác trên cùng máy.

- `dhampirave/Miami26` → `~/.themes/Miami26`
- `bikass/kora` → `~/.local/share/icons/kora-pgrey`

Không có trong kho Arch/CachyOS/arisa (đã tra `rpc/v5/search` của AUR: "miami26"
và "kora-grey" đều 0 kết quả).

Tên thư mục phải đúng `Miami26` / `kora-pgrey` vì GTK3 tra theme theo tên thư mục
sau khi cài, **không** theo `Name=` trong `index.theme`.

## Không phải gói: build từ mã nguồn trong repo

`./install.sh build` biên dịch 7 thứ, không tải gói nào:

`dwm` · `st` · `slock` · `dmenu` · `slstatus` · `netpanel` · `imgdec`

Cần `make`, `gcc`, `nproc`. Mặc định cài vào `/usr/local/bin` nên **cần root**.
Thư mục đích đổi được bằng biến môi trường: `PREFIX=~/.local ./install.sh build`.
`run.sh` tự thêm `$PREFIX/bin` vào `PATH` nên không cần khai báo tay.

`imgdec` build bằng `make -f scripts/Makefile.imgdec` và dùng
`scripts/stb/stb_image*.h` — thư viên single-header vendored sẵn trong repo, không
cài từ đâu.

`config.h` phải tồn tại trước khi build. Không có thì `make` âm thầm tạo lại từ
`config.def.h` và **xoá sạch tùy chỉnh** — `install.sh` kiểm tra trước và dừng.

---

## Năm điều cần biết trước khi cài

### `ffmpeg` không có trong danh sách

`scripts/mediacard.sh` dùng `ffmpeg` để giải mã audio lấy lời bài hát, nhưng
**không mảng gói nào chứa `ffmpeg`**. Nó tới nhờ là dependency của `firefox` và
`ffmpegthumbnailer`.

Đo trên máy này: `pacman -Qi ffmpeg` → `Required By: chromaprint ffmpegthumbnailer
firefox gst-libav lianli-linux-git vlc-plugin-ffmpeg`. Cả `firefox` và
`ffmpegthumbnailer` đều trong danh sách nên `ffmpeg` luôn có mặt — nhưng là
**gián tiếp**, không phải do Tsuki yêu cầu.

Trong `install.sh` có comment: *"Cài cả `ffmpeg` lẫn `ffmpegthumbnailer`"*. Đó là
ý định, nhưng code chỉ cài `ffmpegthumbnailer`. Tài liệu này ghi đúng code thật.

### `bibata-cursor-theme` cũng cần kho arisa, không chỉ hai gói kia

`cmd_arisa` nói: *"Tsuki cần nó cho hai gói trong `PKG_KEYBINDS`:
`visual-studio-code-bin`, `discord-ptb`"*. Đo `pacman -Si` trên máy này cho ra
**ba** gói từ arisa:

`visual-studio-code-bin` · `discord-ptb` · **`bibata-cursor-theme`**

Gói thứ ba nằm ở `PKG_SESSION`, không phải `PKG_KEYBINDS`. Chạy `./install.sh`
đầy đủ thì không sao — `main()` gọi `cmd_arisa` **trước** `cmd_deps`, nên kho đã
có sẵn khi `PKG_SESSION` được cài. Nhưng nếu chạy riêng `./install.sh session`
mà chưa có kho arisa, gói này bị bỏ qua và **không có theme con trỏ X11**.

### `cargo` không phải một gói riêng

Không kho nào đang bật có tên `cargo` — `pacman -Si cargo` báo *package not
found*. Nó được gói `rust` cung cấp (`Provides: cargo`): `pacman -Q cargo` trả
về `rust 1:1.98.1-1.1`, và `/usr/bin/cargo` có sẵn.

Vì `missing_pkgs` hỏi `pacman -Qq` nên coi `cargo` là đã có và bỏ qua. Đó là lý
do `PKG_AUR` trông như không làm gì — nó đang làm đúng việc.

### `gtk3` xuất hiện hai lần

Ở cả `PKG_CONFIG` và `PKG_KEYBINDS`. Vô hại — `pacman -S` tự bỏ trùng — nhưng
nên biết để không tưởng mình cài hai lần. Cũng là lý do tổng dung lượng theo
nhóm lớn hơn tổng thật.

### Gói không có trong kho nào sẽ bị bỏ qua

`available_pkgs` hỏi `pkgs_absent_in_repos` rồi bỏ qua gói không tìm thấy, chỉ in
một dòng cảnh báo:

```
không có trong kho nào đang bật, bỏ qua: <tên>
```

Cài tiếp vẫn chạy. Nghĩa là **từ chối kho arisa không làm hỏng bước cài** — chỉ
mất `visual-studio-code-bin`, `discord-ptb`, `bibata-cursor-theme`. Nếu thấy dòng
cảnh báo này mà muốn biết mất gì, xem `README.md` phần Cài.

## Thêm kho arisa nghĩa là gì

`arisa` là kho nhị phân do
[github.com/slimulv1/arisa-repo](https://github.com/slimulv1/arisa-repo) phát
hành, dựng bằng GitHub Actions. Không phải kho của Arch/CachyOS.

Thêm nó vào `pacman.conf` nghĩa là **pacman sẽ chạy code từ kho đó bằng quyền
root**. `install.sh` hỏi trước, mặc định là **không** thêm. Chạy `./install.sh
deps` cho tới khi nó hỏi, từ chối, rồi `./install.sh session` để cài phần còn
lại — mất ba gói ở trên, đổi lại không động vào kho thứ ba.

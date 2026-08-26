# dwm-dotfiles

![preview](assets/preview.png)

Bộ rice Linux của tôi: **dwm** (window manager) + **slstatus** (statusbar) + dotfiles cho Arch/CachyOS. Màu theme tự sinh từ wallpaper — đổi hình nền là toàn bộ bar, rofi, dunst đổi màu theo.

## Thành phần

| Thành phần | Vai trò |
|---|---|
| `dwm` | Window manager (patched: vanitygaps, movestack, shiftview, cfactor...) |
| `slstatus` | Statusbar: updates, CPU/RAM/disk/temp, icon mạng, Wi-Fi mini, pin, đồng hồ |
| `st` | Terminal |
| `slock` | Lock screen |
| `netpanel` | Panel Wi-Fi (click icon mạng trên bar): đổi mạng, band pinning, chia sẻ QR |
| `dmenu` | Launcher |
| `scripts/` | `run.sh` (khởi động session), `dwmwal.sh` (đổi wallpaper + sinh màu), `wallpicker.py` (GTK3 wallpaper picker), `walgen.py`, `imgdec.c` (decoder ảnh C), `game.sh` (gaming wrapper)... |
| `.config/` | kitty, dunst, rofi, fastfetch, fish + starship, picom |

## Cài đặt

### 1. Dependencies (Arch)

```sh
sudo pacman -S --needed base-devel libx11 libxft libxinerama fontconfig freetype \
    harfbuzz imlib2 libjpeg-turbo libwebp feh picom dunst kitty rofi fastfetch fish dash python \
    libnotify polkit-gnome fcitx5 nerd-fonts ttc-iosevka \
    starship networkmanager playerctl libpulse qrencode curl
```

> - `starship` — prompt cho fish (config: `.config/starship.toml`)
> - `networkmanager` — `nmcli`, cần cho icon Wi-Fi trên bar + netpanel
> - `playerctl` + `libpulse` — media/volume qua mediacard daemon (`pactl`)
> - `qrencode` — chia sẻ Wi-Fi bằng QR trong netpanel
> - `ttc-iosevka` + `nerd-fonts` — font bar (Iosevka) và statusbar/st (JetBrainsMono NF, Maple Mono NF)
> - `libjpeg-turbo` + `libwebp` — build `imgdec`, decoder ảnh nhanh cho wallpaper picker
>
> Tùy chọn cho gaming: `gamemode gamescope mangohud` (dùng cùng `scripts/game.sh`).

### 2. Build & install

> ⚠️ Clone thẳng repo vào `~/dwm` — toàn bộ script (`run.sh`, `dwmwal.sh`, `netpanel.sh`) và keybinds trong dwm đều trỏ tới `~/dwm/...`.

```sh
git clone https://github.com/slimulv1/dwm-dotfiles.git ~/dwm
cd ~/dwm

sudo make clean install                            # window manager
cd st      && sudo make clean install && cd ..     # terminal
cd slock   && sudo make clean install && cd ..     # lock screen
cd dmenu   && sudo make clean install && cd ..     # launcher
cd netpanel && sudo make clean install && cd ..    # wifi panel
cd slstatus && sudo make install                   # statusbar (cũng build local cho run.sh)

# decoder ảnh cho wallpaper picker (binary local, không cần root)
make -f scripts/Makefile.imgdec
```

> `slstatus` được chạy qua `scripts/run.sh` bằng **binary local** (`~/dwm/slstatus/slstatus`) để `dwmwal.sh` tự rebuild + đổi màu khi đổi wallpaper mà không cần quyền root. Tương tự, `imgdec` là binary local của picker — thiếu nó picker vẫn chạy (tự rơi về Pillow/gdk-pixbuf), chỉ chậm hơn.

### 3. Dotfiles

```sh
cp -r ~/dwm/.config/* ~/.config/     # hoặc symlink từng thư mục
```

### 4. Chạy session

Thêm vào `~/.xinitrc`:

```sh
exec ~/dwm/scripts/run.sh
```

`run.sh` sẽ: nạp Xresources, set wallpaper (feh), chạy picom, polkit, fcitx5, slstatus (loop tự phục hồi), updater updates + mediacard, rồi exec dwm.

## Đổi wallpaper / theme

Nhấn **Super + w** → picker GTK3 fullscreen mở dạng filmstrip: wallpaper đang dùng hiện to giữa (hero), các ảnh còn lại xếp dọc hai bên trượt mượt theo lựa chọn. `dwmwal.sh` tự:

1. Extract palette từ ảnh (`walgen.py`)
2. Rebuild dwm + sinh lại màu slstatus (CPU/RAM/disk/temp luôn dùng biến thể sáng, dễ đọc trên bar tối)
3. Cập nhật màu rofi, dunst

Decode ảnh của picker đi qua helper C `imgdec` (libjpeg-turbo scaled-DCT + WebP) — thumbnail được cache tại `~/.cache/dwmwal/picker/` nên lần mở sau gần như tức thì; thiếu imgdec thì fallback về Pillow/gdk-pixbuf.

## Gaming

picom đã tự unredirect cửa sổ fullscreen (`unredir-if-possible`), game chạy full-screen bypass compositor sẵn. Với game biên giới (borderless-window) hoặc cần upscale/ổn định thêm:

```sh
~/dwm/scripts/game.sh <lệnh game>              # gamemode (CPU/GPU governor, niceness)
~/dwm/scripts/game.sh -g <lệnh game>           # + gamescope (nested compositor)
~/dwm/scripts/game.sh -g -W 2560x1440 <lệnh>   # gamescope với virtual resolution
GAME_MANGO=1 ~/dwm/scripts/game.sh <lệnh>      # + overlay mangohud
```

## Keybinds

`MODKEY` = **Super**. Bảng đầy đủ: [KEYBINDS.md](KEYBINDS.md)

| Phím | Hành động |
|---|---|
| `Super + Enter` | Mở st |
| `Super + r` | Rofi launcher |
| `Super + j / k` | Focus cửa sổ dưới/trên |
| `Super + Shift + j / k` | Đổi chỗ cửa sổ |
| `Super + 1-9` | Chuyển tag |
| `Super + Shift + 1-9` | Đưa cửa sổ sang tag |
| `Super + f` | Fullscreen |
| `Super + Shift + Space` | Bật/tắt floating |
| `Super + t` | Layout tile |
| `Super + w` | Đổi wallpaper + theme |
| `Super + Del` | Lock (slock) |
| `Super + q` | Đóng cửa sổ |

## License

MIT — xem [LICENSE](LICENSE). slstatus/st/slock/dmenu thuộc [suckless.org](https://suckless.org).

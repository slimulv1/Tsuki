# dwm-dotfiles

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
| `scripts/` | `run.sh` (khởi động session), `dwmwal.sh` (đổi wallpaper + sinh màu), `walgen.py`... |
| `.config/` | kitty, dunst, rofi, fastfetch, fish, picom |

## Cài đặt

### 1. Dependencies (Arch)

```sh
sudo pacman -S --needed base-devel libx11 libxft libxinerama fontconfig freetype \
    harfbuzz imlib2 feh picom dunst kitty rofi fastfetch fish dash python \
    libnotify polkit-gnome fcitx5 nerd-fonts
```

### 2. Build & install

```sh
git clone https://github.com/slimulv1/dwm-dotfiles.git
cd dwm-dotfiles/dwm

sudo make clean install              # window manager
cd st      && sudo make clean install && cd ..   # terminal
cd slock   && sudo make clean install && cd ..   # lock screen
cd dmenu   && sudo make clean install && cd ..   # launcher
cd netpanel && sudo make clean install && cd ..  # wifi panel
cd slstatus && sudo make install && cd ..        # statusbar (cũng build local cho run.sh)
```

> `slstatus` được chạy qua `scripts/run.sh` bằng **binary local** (`~/dwm/slstatus/slstatus`) để `dwmwal.sh` tự rebuild + đổi màu khi đổi wallpaper mà không cần quyền root.

### 3. Đưa nguồn về ~/dwm

Các script chạy theo đường dẫn `$HOME/dwm`, nên cần nội dung thư mục `dwm/` nằm tại `~/dwm`:

```sh
mkdir -p ~/dwm && cp -r dwm/* ~/dwm/   # hoặc rsync/symlink
```

### 3. Dotfiles

```sh
cp -r .config/* ~/.config/           # hoặc symlink từng thư mục
```

### 4. Chạy session

Thêm vào `~/.xinitrc`:

```sh
exec ~/dwm/scripts/run.sh
```

`run.sh` sẽ: nạp Xresources, set wallpaper (feh), chạy picom, polkit, fcitx5, slstatus (loop tự phục hồi), updater updates + mediacard, rồi exec dwm.

## Đổi wallpaper / theme

Nhấn **Super + w** → chọn ảnh trong rofi picker. `dwmwal.sh` tự:

1. Extract palette từ ảnh (`walgen.py`)
2. Rebuild dwm + sinh lại màu slstatus (CPU/RAM/disk/temp luôn dùng biến thể sáng, dễ đọc trên bar tối)
3. Cập nhật màu rofi, dunst

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

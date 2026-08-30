# Tsuki

<p><br/></p>
<p align="center">
  <img src="assets/tsuki-logo.png" alt="Tsuki Logo" style="width: 192px" />
</p>
<p><br/></p>

**A dwm setup that doesn't suck. Or freeze.**

Personal dwm rice for Arch/CachyOS — built around minimalism, performance, and a cozy night theme. *Tsuki* (月, "moon") is the wallpaper-aware window manager that keeps your desktop in sync with whatever the night (or day) looks like.

## Preview

| <img src="assets/preview.png" alt="preview" /> |
|---|
| <img src="assets/wallpicker.png" alt="wallpaper picker" /> | <img src="assets/netpanel.png" alt="wifi panel" /> |

## Trong repo có gì

| Thành phần | Làm gì |
|---|---|
| `dwm` | Window manager chính (đã patch sẵn: vanitygaps, movestack, shiftview, cfactor...) |
| `slstatus` | Statusbar: số update, CPU/RAM/disk/nhiệt độ, icon mạng, Wi-Fi mini, pin, giờ |
| `st` | Terminal |
| `slock` | Lock screen |
| `netpanel` | Bấm icon Wi-Fi trên bar là ra panel: chọn mạng, giữ band, chia sẻ mật khẩu bằng QR |
| `dmenu` | Launcher |
| `scripts/` | Toàn bộ "phần mềm giữa": khởi động session, đổi wallpaper + sinh màu, picker ảnh nền, decoder ảnh viết bằng C, wrapper chơi game... |
| `.config/` | Config cho kitty, dunst, fastfetch, fish + starship, picom |

## Quick Start

```sh
git clone https://github.com/slimulv1/Tsuki.git ~/dwm
cd ~/dwm

sudo make clean install                            # window manager
cd st      && sudo make clean install && cd ..     # terminal
cd slock   && sudo make clean install && cd ..     # lock screen
cd dmenu   && sudo make clean install && cd ..     # launcher
cd slstatus && sudo make install                   # statusbar
cd netpanel && make && cd ..                       # wifi panel (chỉ cần build)

# decoder ảnh cho wallpaper picker
make -f scripts/Makefile.imgdec
```

### Dependencies (Arch)

```sh
sudo pacman -S --needed base-devel libx11 libxft libxinerama fontconfig freetype \
    harfbuzz imlib2 libjpeg-turbo libwebp feh picom xsettingsd dunst kitty fastfetch fish dash python \
    libnotify polkit-gnome fcitx5 nerd-fonts ttc-iosevka \
    starship networkmanager playerctl libpulse qrencode curl
```

Vài cái đáng nói:

- `starship` — prompt cho fish (config nằm ở `.config/starship.toml`)
- `networkmanager` — cần có để icon Wi-Fi trên bar và netpanel hoạt động
- `playerctl` + `libpulse` — media/volume qua mediacard daemon
- `qrencode` — để netpanel hiện mật khẩu Wi-Fi dạng QR
- `xsettingsd` — daemon XSETTINGS: để app GTK (file dialog, tooltip...) ăn theo theme font/màu tối của hệ thống, không bị "nguyên bản mặc định". Config nằm ở `.config/xsettingsd/`, chạy bằng `xsettingsd -c ~/.config/xsettingsd/xsettingsd.conf`
- `ttc-iosevka` + `nerd-fonts` — font cho bar và terminal
- `libjpeg-turbo` + `libwebp` — chỉ cần khi build `imgdec` (decoder ảnh cho picker, giải thích bên dưới)

Định chơi game trên máy này thì cài thêm: `gamemode gamescope mangohud`.

### Dotfiles

```sh
cp -r ~/dwm/.config/* ~/.config/     # hoặc symlink từng thư mục nếu thích gỡ bỏ dễ
```

> **Firefox transparent chrome (userChrome.css)** nằm riêng ở `.config/firefox/` trong repo —
> copy vào profile Firefox đang dùng, rồi **đổi path @import** cho khớp đường dẫn máy:
>
> ```sh
> # 1. Tìm profile (có chứa chuỗi .default-release, không -back-ovfs)
> ls ~/.config/mozilla/firefox/*.default-release*/
> # 2. Copy 2 file vào thư mục chrome/ của profile đó
> PROFILE=~/.config/mozilla/firefox/<tên-profile>
> mkdir -p "$PROFILE/chrome"
> cp .config/firefox/user.js                     "$PROFILE/"
> cp .config/firefox/chrome/userChrome.css       "$PROFILE/chrome/"
> # 3. Trong userChrome.css, sửa @import trỏ tới màu dwmwal:
> #    ../../../../../.cache/dwmwal/colors.css
> #    (path tính từ chrome/, 5 cấp lên tới ~/ rồi vào .cache/dwmwal/)
> ```
>
> **Cần bật** `browser.tabs.allowTransparentBrowser=true` — file `user.js` tự đặt khi Firefox
> khởi động (userPref). Toàn bộ cấu hình cần thiết đều nằm trong `.config/firefox/user.js`
> (đã copy ở bước 2), gồm:
>
> ```js
> // 1. BẮT BUỘC - bật userChrome.css (nếu tắt, css customize không load)
> user_pref("toolkit.legacyUserProfileCustomizations.stylesheets", true);
> // 2. Cho phép vẽ nền trong suốt (cho tab trong suốt xuyên wallpaper)
> user_pref("browser.tabs.allowTransparentBrowser", true);
> // 3. Tắt theme "Nova" mặc định (nếu để on, nó đè/bao phủ userChrome.css)
> user_pref("browser.nova.enabled", false);
> // 4. Hiện tùy chọn mật độ Compact trong menu Customize toolbar
> user_pref("browser.compactmode.show", true);
> ```
>
> Sau khi copy `user.js` + `userChrome.css` vào profile và **restart Firefox**:
>
> 1. **Kiểm tra CSS hoạt động** — mở `about:config`, xác nhận
>    `toolkit.legacyUserProfileCustomizations.stylesheets` = `true` (nếu vẫn `false`,
>    set thủ công rồi restart).
> 2. **Bật Compact density** (nếu muốn giao diện gọn như thiết kế) — vào
>    **Customize toolbar** (chuột phải thanh tab → Customize), hạ góc phải chọn
>    **Density → Compact**. (Chỉ khi `browser.compactmode.show=true` tùy chọn này mới hiện.)
>
> Sau đó **restart Firefox**. Màu tab/toolbar sync tự động theo wallpaper
> (dwmwal ghi `~/.cache/dwmwal/colors.css` mỗi lần đổi ảnh). Hiệu quả: **tab trong suốt**
> (thấy wallpaper), toolbar + url bar + nội dung vẫn nền đục cho dễ đọc.

### Chạy session

Thêm dòng này vào `~/.xinitrc`:

```sh
exec ~/dwm/scripts/run.sh
```

Lần bấm máy tiếp theo `run.sh` sẽ lo từ A-Z: nạp Xresources, trả lại wallpaper cũ, chạy picom, polkit, fcitx5, slstatus (chết tự sống lại), updater và mediacard, rồi cuối cùng là dwm.

## Tích hợp nổi bật

### 🌙 Đổi wallpaper (và toàn bộ theme) — *trái tim của Tsuki*

Bấm **Super + w**: một picker fullscreen kiểu filmstrip mở lên — ảnh đang dùng phóng to ở giữa, mấy ảnh còn lại xếp thành dải mỏng hai bên, trượt mượt theo lúc bạn duyệt.

![Wallpaper picker](assets/wallpicker.png)

Chọn xong thì `dwmwal.sh` lo phần còn lại:

1. Lấy palette màu từ chính tấm ảnh (`walgen.py`)
2. Rebuild dwm + sinh lại màu cho slstatus (CPU/RAM/disk/nhiệt độ luôn dùng biến bản sáng hơn cho dễ đọc trên nền tối)
3. Đổi theo màu dunst

Ảnh nền được decode bởi `imgdec` — một chương trình C nhỏ dùng libjpeg-turbo (decode JPEG đúng kích thước cần, không giải mã thừa pixel nào) kèm hỗ trợ WebP. Thumbnail được lưu cache ở `~/.cache/dwmwal/picker/`, nên lần thứ hai mở picker gần như là tức thì.

### 📶 Netpanel — quản lý Wi-Fi từ status bar

Bấm icon mạng trên bar: panel Wi-Fi hiện ra bên phải, cho chọn mạng, xem thông số kết nối, chia sẻ mật khẩu bằng QR, đổi DNS, chạy speed test — tất cả viết bằng C + libXft, không cần `nm-connection-editor` hay app nào khác.

![Netpanel](assets/netpanel.png)

### 🎮 Chơi game

picom đã cấu hình sẵn để nhường đường cho game fullscreen (unredirect), nên phần lớn trường hợp cứ chơi thẳng, mượt. Game nào chạy borderless-window hoặc muốn upscale/ổn định thêm thì dùng wrapper:

```sh
~/dwm/scripts/game.sh <lệnh game>              # gamemode: tăng ưu tiên CPU/GPU khi vào game
~/dwm/scripts/game.sh -g <lệnh game>           # thêm gamescope (compositor riêng cho game)
~/dwm/scripts/game.sh -g -W 2560x1440 <lệnh>   # gamescope + ép độ phân giải ảo
GAME_MANGO=1 ~/dwm/scripts/game.sh <lệnh>      # hiện overlay FPS của mangohud
```

### Tridactyl — duyệt web kiểu Vim trên Firefox

[Tridactyl](https://github.com/tridactyl/tridactyl) thay thế cơ chế điều khiển mặc định của Firefox bằng phím tắt kiểu Vim: cuộn, mở link, chuyển tab, tìm kiếm — không cần chạm chuột. Phần này tóm tắt hướng dẫn [từ README gốc](https://github.com/tridactyl/tridactyl#installation).

#### Cài đặt (Arch)

```sh
sudo pacman -S firefox-tridactyl
```

Rồi **restart Firefox _hai lần_** (bản Arch là bản "stable", thực chất là bản beta đông lạnh).

Muốn bản beta mới nhất (Firefox tự cập nhật mỗi ngày) thì mở link này ngay **trong Firefox**:

<https://tridactyl.cmcaine.co.uk/betas/tridactyl-latest.xpi>

Nếu link không tự cài được — đổi đuôi file từ `.zip` sang `.xpi` rồi mở bằng Firefox, hoặc vào `about:addons` → tab Extensions → icon bánh răng phía trên → **Install Add-on From File...**. Bản cài từ [AMO](https://addons.mozilla.org/en-US/firefox/addon/tridactyl-vim) (stable) lưu config riêng, không dùng chung với bản pacman — cần chuyển giữa hai bản thì xem [wiki migration](https://github.com/tridactyl/tridactyl/wiki/Migration-from-stable-to-beta).

#### Native messenger (tính năng nâng cao)

Muốn dùng mấy tính năng như **edit-in-Vim** (bấm phím trong ô text là nhảy ra editor chỉnh file tạm), cài native messenger:

```sh
# Cách 1: gói AUR
yay -S firefox-tridactyl-native
# Cách 2: tự cài ngay trong Tridactyl — gõ :nativeinstall rồi Enter
```

(Firefox dạng Snap/Flatpak thì native messaging cần Firefox beta `>= 106.0b6` + `flatpak permission-set webextensions tridactyl snap.firefox yes` + reboot.)

#### Bắt đầu nhanh

- `:help` hoặc `<F1>` — trợ giúp online; `:tutor` — bài học tương tác
- Config nằm ở `~/.tridactylrc` (như `.vimrc`), hoặc chỉnh qua lệnh `:config`
- Mấy phím hay dùng: `j/k/h/l` — cuộn, `f` — chọn link bằng hint, `yy` — copy URL, `/` — Quick Find, `<C-f>/<C-b>` — nhảy trang, `ZZ` — đóng Firefox
- Tridactyl **không chạy** trên trang `about:*`, `data:*`, `view-source:*` và `file:*`
- **Cẩm nang đầy đủ (tiếng Việt):** xem [tridactyl-guide.md](tridactyl-guide.md) — mở/đóng & chuyển tab, tìm kiếm thông tin, quickmark & marks, containers, tuỳ biến… soạn từ toàn bộ tutorial chính thức

## Keybinds

`MODKEY` = **Super**. Bảng đầy đủ nằm ở [KEYBINDS.md](KEYBINDS.md), còn đây là mấy phím hay dùng nhất:

| Phím | Hành động |
|---|---|
| `Super + Enter` | Mở st |
| `Super + r` | Rofi launcher |
| `Super + j / k` | Focus cửa sổ dưới/trên |
| `Super + Shift + j / k` | Đổi chỗ hai cửa sổ |
| `Super + 1-9` | Chuyển tag |
| `Super + Shift + 1-9` | Đưa cửa sổ sang tag khác |
| `Super + f` | Fullscreen |
| `Super + Shift + Space` | Bật/tắt floating |
| `Super + t` | Về layout tile |
| `Super + w` | Đổi wallpaper + theme |
| `Super + Del` | Khóa máy (slock) |
| `Super + q` | Đóng cửa sổ |

## Patches

| Patch | Mô tả |
|---|---|
| **vanitygaps** | Gaps giữa cửa sổ + `Super+Ctrl+u/t` toggle |
| **movestack** | `Super+Shift+j/k` đổi chỗ cửa sổ |
| **shiftview** | Cuộn qua tag dễ dàng |
| **cfactor** | `Super+Shift+h/l/o` đổi tỉ lệ cửa sổ |
| **pertag** | Mỗi tag nhớ layout, gaps, và floating riêng |
| **centered** | Layout centered master |
| **fakefullscreen** | Fullscreen thật sự cho game |
| **tabmode** | `Super+Ctrl+w` bật chế độ tab (tabbar) |

### st

| Feature | Mô tả |
|---|---|
| **kitty graphics** | Xem ảnh ngay trong terminal |
| **imlib2** | Decode ảnh nhanh (SHM) |
| **scrollback** | Cuộn lại lịch sử |
| **alpha** | Độ mờ nền |

### slstatus

| Feature | Mô tả |
|---|---|
| **status2d** | màu `^C#[HEX]^`/`^d^` trong status bar |
| **dwmwal sync** | Tự đổi màu theo wallpaper |

## License

MIT — xem [LICENSE](LICENSE). slstatus/st/slock/dmenu là của [suckless.org](https://suckless.org).

---

### Thêm

Muốn mở rộng setup? Xem thêm các repo config khác nếu có.

# Tsuki

<p><br/></p>
<p align="center">
  <img src="assets/tsuki-logo.png" alt="Tsuki Logo" style="width: 192px; height: 192px; object-fit: contain" />
</p>
<p><br/></p>

**Catch a window, moonlit and tidy.**

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
| `.config/firefox/` | Giao diện Firefox tối giản kiểu qutebrowser (userChrome.css) |
| `scripts/` | Toàn bộ "phần mềm giữa": khởi động session, đổi wallpaper + sinh màu, picker ảnh nền, decoder ảnh viết bằng C, wrapper chơi game... |
| `.config/` | Config cho kitty, dunst, fastfetch, fish + starship, picom |

## Quick Start

```sh
git clone https://github.com/slimulv1/Tsuki.git ~/dwm
cd ~/dwm

sudo make install                               # window manager
cd st      && sudo make clean install && cd ..  # terminal
cd slock   && sudo make clean install && cd ..  # lock screen
cd dmenu   && sudo make clean install && cd ..  # launcher
cd slstatus && sudo make install                   # statusbar
cd netpanel && make && cd ..                       # wifi panel (chỉ cần build)

# decoder ảnh cho wallpaper picker
make -f scripts/Makefile.imgdec
```

> **`config.h` là cấu hình thật của máy, đừng để `make clean` xoá nó.**
> Nó được git track và là nơi duy nhất chứa các tùy chỉnh riêng:
> `#include "themes/wal.h"` (đồng bộ màu theo wallpaper), tag, keybind, rules,
> `fonts`, `baralpha`, `cmd[]`. Lệnh `make clean` **không** xoá `config.h` nữa.
> Nếu cần dựng bản sạch từ đầu (mất cấu hình), dùng `make distclean` — hoặc
> chép `config.h` ra chỗ khác trước.

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

> ### Firefox — giao diện tối giản kiểu qutebrowser
>
> Firefox trên Tsuki mặc định ăn mình cái giao diện phẳng, bo góc bằng 0, thanh
> địa chỉ mảnh dính, nút thừa bị đá hết — đúng kiểu lười nhất có thể mà vẫn nhìn ra
> là người biết dùng bàn phím. Không có màu chuyển theo wallpaper, không có tab
> trong suốt xuyên ảnh nền, không có gì cả. Bù lại nó nhẹ, không giật, không xung đột
> với bất cứ theme nào khác, và quan trọng nhất: **không bao giờ hỏng** vì tôi lỡ tay
> sửa `@import` trỏ nhầm đường dẫn.
>
> Nguồn: [Dook97/firefox-qutebrowser-userchrome](https://github.com/Dook97/firefox-qutebrowser-userchrome)
> (GPL-3.0, 206 sao). Tác giả ghi rõ theme này sinh ra cho WM kiểu dwm, xmonad, awesome —
> nên nó hợp với Tsuki từ gốc.
>
> **Cài — ba lệnh, xong:**
>
> ```sh
> # 1. Copy user.js và userChrome.css vào profile Firefox đang dùng
> PROFILE=$(ls -d ~/.config/mozilla/firefox/*.default-release 2>/dev/null | head -1)
> mkdir -p "$PROFILE/chrome"
> cp .config/firefox/user.js           "$PROFILE/"
> cp .config/firefox/chrome/userChrome.css "$PROFILE/chrome/"
>
> # 2. Xong. Restart Firefox.
> ```
>
> Hết. Không sửa `@import`, không chỉnh path, không đoán mò. Dook97 dùng màu viết cứng
> trong file nên copy là chạy, không cần bất cứ bước nào khác.
>
> **Lưu profile tốt vào trước** (không nhất thiết nhưng nên):
>
> ```sh
> ls ~/.config/mozilla/firefox/
> ```
>
> Nếu thấy mấy thứ kiểu `*.default-release-back-ovfs`, `*-backup` — đừng xóa bừa. Đó là
> bản sao lưu của Firefox hoặc lớp overlay của bạn. Cài nhầm profile thì profile đúng vẫn
> nguyên, chỉ mất thời gian xóa đi làm lại.
>
> **Ba thứ phải bật**, tất cả nằm sẵn trong `user.js` mà bạn vừa copy — Firefox tự áp
> dụng lúc khởi động:
>
> ```js
> user_pref("toolkit.legacyUserProfileCustomizations.stylesheets", true); // bật userChrome.css — tắt là CSS chết
> user_pref("browser.nova.enabled", false);                              // tắt theme Nova, nó đè CSS của bạn
> user_pref("browser.compactmode.show", true);                          // lộ tùy chọn Density
> ```
>
> Còn `browser.tabs.allowTransparentBrowser` thì **không còn dùng** với theme này. Dook97
> vẽ nền đục, không trong suốt — bật nó chỉ là thừa.
>
> **Restart Firefox** rồi làm hai việc còn lại:
>
> 1. **Bật Compact density** — chuột phải thanh tab → **Customize toolbar** → góc phải →
>    **Density → Compact**. Chỉ hiện khi `browser.compactmode.show=true`, nên nếu thấy
>    mục này biến mất thì đừng tìm, quay lại `about:config` kiểm tra pref.
> 2. **Xem kỹ nếu Firefox thêm tab "Firefox View"** ở góc trái — gỡ nó trong Customize
>    toolbar, theme này cố tình giấu hết nút thừa, để lại nó thì mất tinh thần.
>
> **Font:** Dook97 dùng `DejaVu Sans Mono`. Máy bạn có sẵn 4 biến thể DejaVu nên không
> cài gì thêm. Nếu muốn đổi (Iosevka, JetBrains Mono Nerd của Tsuki), sửa hai dòng
> `--tab-font` và `--urlbar-font` ở đầu file.
>
> **Tridactyl — mảnh ghép còn thiếu, và là bắt buộc nếu bạn muốn theme này hết ý nghĩa.**
>
> Dook97 giấu hết nút, chỉ còn lại thanh địa chỉ. Chuột thì xong, nhưng để quản lý tab
> bằng chuột thì hơi điên. Tridactyl lấp đúng lỗ hổng đó: điều khiển Firefox kiểu Vim.
>
> ```sh
> sudo pacman -S firefox-tridactyl
> ```
>
> Restart Firefox **hai lần** (bản pacman là bản beta đông lạnh, lần một chưa chạy).
> Bản mới nhất tự cập nhật hằng ngày: <https://tridactyl.cmcaine.co.uk/betas/tridactyl-latest.xpi>
> — mở bằng Firefox, đổi đuôi `.zip` thành `.xpi` nếu nó không tự cài.
>
> Dùng thử:
>
> - `f` — bật chữ cái lên mọi link, gõ tiếp để nhảy, chạm chuột hoặc Enter để mở
> - `j` / `k` — cuộn xuống / lên
> - `H` / `L` — lịch sử ngược / tới
> - `yy` — copy URL, `/` — tìm nhanh trong trang
> - `ZZ` — đóng Firefox
> - `:help` — bảng phím đầy đủ, `:tutor` — bài tập tương tác
>
> Config nằm ở `~/.tridactylrc`, sửa như `.vimrc`. Tridactyl **không chạy** trên `about:*`,
> `view-source:*`, `file:*` — cũng đúng như mọi thứ khác.
>
> Ở repo có `tridactyl-guide.md` — cẩm nang tiếng Việt, đầy đủ mấy thứ mà `:help` không
> giải thích: quickmark, containers, quản lý nhiều tab, tuỳ biến. Đọc khi chán, không
> đọc ngay cũng được.
>
> **Muốn tinh chỉnh:** màu nằm gọn trong khối `:root` đầu file. `--tab-min-height` nâng
> lên nếu thấy sọc đen dưới thanh tab, `--navbar-height-setting` để thanh cao/thấp tuỳ
> ý. Tắt favicon thì tìm dòng `/* disable favicons */` rồi comment nó.
>
> **Quay lại theme theo wallpaper (nếu đổi ý):**
>
> ```sh
> PROFILE=$(ls -d ~/.config/mozilla/firefox/*.default-release 2>/dev/null | head -1)
> cd ~/dwm
> git log --oneline -- .config/firefox/chrome/userChrome.css   # tìm commit trước khi đổi
> git show <commit>:.config/firefox/chrome/userChrome.css > "$PROFILE/chrome/userChrome.css"
> cp ~/.cache/dwmwal/colors.css "$PROFILE/chrome/colors.css"
> ```
>
> Bản cũ còn nằm trong git, lấy lại được. Nhưng nhớ câu này: theme theo wallpaper cần
> `@import colors.css` nằm cạnh nó, và `dwmwal.sh` phải copy file đó vào mỗi profile —
> hiện đã bỏ, nên quay lại thì phải bật lại. Nói thật thì xem ảnh chụp ở trên rồi tự
> quyết, tôi không giữ ý kiến.

![Firefox minimalist chrome](assets/firefox.png)

### Chạy session

`run.sh` lo từ A-Z: nạp Xresources, trả lại wallpaper cũ, chạy picom, polkit, fcitx5, slstatus (chết tự sống lại), updater và mediacard, rồi cuối cùng là dwm. Có hai cách đăng nhập vào nó.

#### Gói cần thêm trước

```
sudo pacman -S --needed xorg-server xorg-xwayland xorg-xrdb xorg-xset
```

- `xorg-server` — dwm là X11 thuần. Máy chỉ chạy GNOME/Wayland thì **không có binary `Xorg`**, nên mọi session X sẽ chết ngay lúc đăng nhập.
- `xorg-xrdb`, `xorg-xset` — `run.sh` gọi `xrdb` và `xset`. Danh sách Dependencies ở trên không có hai gói này; thiếu thì dòng đó chết âm thầm.
- `xorg-xinit` — chỉ cần cho [Cách B](#cách-b--không-display-manager-startx-từ-tty).

Ngoài ra hai tên gói trong danh sách Dependencies không tồn tại trên Arch: `freetype` là `freetype2`, và `nerd-fonts` không có trong repo — dùng `ttf-jetbrains-mono-nerd` (đúng family name mà `config.h` yêu cầu).

#### Cách A — có display manager (GDM / SDDM / LightDM)

Session entry phải nằm ở `/usr/share/xsessions/`:

```sh
sudo install -d -m 755 /usr/share/xsessions
sudo tee /usr/share/xsessions/Tsuki.desktop >/dev/null <<'EOF'
[Desktop Entry]
Name=Tsuki
Comment=Tsuki — dwm session (wallpaper-aware)
Exec=/home/USER/.local/bin/tsuki-session
Icon=preferences-desktop
Terminal=false
Type=Application
EOF
sudo chmod 644 /usr/share/xsessions/Tsuki.desktop
```

Thay `USER` bằng tên user của bạn. Kèm một wrapper, vì `run.sh` kết thúc bằng `while type dwm; do dwm; done` — nó tra `dwm` trong `PATH`:

```sh
mkdir -p ~/.local/bin
cat > ~/.local/bin/tsuki-session <<'EOF'
#!/bin/sh
export PATH="$PATH:/usr/local/bin"
exec "$HOME/dwm/scripts/run.sh"
EOF
chmod +x ~/.local/bin/tsuki-session
```

Không có wrapper thì session desktop file chạy bằng `sh` chứ không qua login shell, `PATH` kế thừa từ display manager có thể thiếu `/usr/local/bin` (nơi `make install` đặt `dwm`, `st`, `slock`, `slstatus`, `dmenu`). Hệ quả: vòng lặp thoát ngay và bạn bị đá về màn hình đăng nhập mà không thấy cửa sổ nào.

Sau đó logout, bấm biểu tượng bánh răng ở màn hình đăng nhập, chọn **Tsuki**. Session cũ (GNOME/Wayland) vẫn còn nguyên — muốn bỏ Tsuki thì xoá `/usr/share/xsessions/Tsuki.desktop`.

> **Đừng đặt file ở `~/.xsessions`.** Cái đó là thói quen từ LightDM và chỉ có hiệu lực với một số DM. GDM chỉ quét `/usr/share/xsessions/`, `/usr/share/wayland-sessions/` và `/etc/X11/sessions/` — kiểm bằng `strings /usr/bin/gdm | grep xsessions`. File nằm ở `~/.xsessions` sẽ **không hiện** ở màn hình login, và không có lỗi nào báo ra để bạn biết vì sao.

#### Greeter chạy Wayland, session chạy X11

Greeter của GDM mặc định là **Wayland**. Điều đó không cản session X11: khi bạn chọn Tsuki, GDM khởi động Xorg riêng cho session đó (chính là lý do cần `xorg-server`). Greeter Wayland + session X11 là tổ hợp bình thường, không phải cấu hình lệch.

Nếu display manager của bạn cố tình tắt session X:

- **SDDM** — trong `/etc/sddm.conf`, phần `[Theme]` cần `WaylandSession=false` để buộc greeter X11; session trong `[Autologin]` phải trỏ tên khớp `Name=` của file `.desktop`.
- **GDM** — không cần cấu hình gì thêm, chỉ cần `xorg-server` và file trong `/usr/share/xsessions/`.
- **LightDM** — quét `/usr/share/xsessions/` luôn, nên Cách A chạy được nguyên xi.

#### Cách B — không display manager (startx từ TTY)

```sh
sudo pacman -S --needed xorg-xinit
echo 'exec ~/dwm/scripts/run.sh' > ~/.xinitrc
```

Logout, tới TTY (Ctrl+Alt+F2), đăng nhập, rồi `startx`. Cách này không cần file `.desktop` nào — nhưng cũng nghĩa là không có màn hình đăng nhập, và phải cài `xorg-xinit` vì `startx` nằm trong gói đó.

#### XWayland — chạy app Wayland-only trong dwm

Đây là mảnh ghép hay bị sót. Gói `xorg-xwayland` **chỉ cài đúng binary `/usr/bin/Xwayland`**, không kèm hook nào tự bật nó trong X session (`/etc/X11/xinit/xinitrc.d/` không có script nào gọi tới nó). Không bật thì mọi app chỉ hỗ trợ Wayland — Discord, Steam client, Firefox bản Wayland — sẽ không mở được.

Thêm vào `run.sh`, **trước** dòng `while type dwm`:

```sh
# XWayland — app Wayland-only (Discord, Steam, ...) cần nó
if ! pgrep -x Xwayland >/dev/null; then
    Xwayland :1 -rootless -noreset &
    sleep 0.5
fi
export WAYLAND_DISPLAY=wayland-1
export XDG_CURRENT_DESKTOP=dwm
```

Quy tắc ánh xạ: `Xwayland :N` sinh socket `wayland-N`. GNOME chạy `Xwayland :0 -rootless -noreset -accessx -core` và tạo `wayland-0`; trong dwm, X display thường rơi vào `:1` nên socket là `wayland-1`. Nếu sau này bạn đăng nhập X ở display khác, số trong `WAYLAND_DISPLAY` phải theo.

Giới hạn cần biết: chia sẻ màn hình và một số tính năng clipboard của app Wayland không hoạt động tốt qua XWayland. Đó là giới hạn của XWayland, không phải của Tsuki.

#### Ảnh nền

`run.sh` đọc `scripts/.wallpaper`, thiếu thì rơi về `~/Pictures/Wallpapers/japanese.jpg` — file này **không có trong repo**. Máy mới sẽ có nền đen vì `feh` fail. Trỏ vào ảnh của bạn:

```sh
echo "$HOME/Pictures/Wallpapers/<tên-ảnh>.jpg" > ~/dwm/scripts/.wallpaper
```

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

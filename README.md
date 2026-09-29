# Tsuki

<p align="center">
  <img src="assets/tsuki-logo.png" alt="Tsuki" width="150">
</p>

<p align="center"><i>
— good evening —<br><br>
One window opens,<br>
the pale moon comes in and stays —<br>
nothing at all moves.<br><br>
Each tile finds its place;<br>
the keyboard speaks, not the hand —<br>
and a color lands.
</i></p>

<p align="center"><sub>月 &nbsp;·&nbsp; <a href="https://dwm.suckless.org/">dwm</a> rice for Arch/CachyOS</sub></p>

## Ảnh

| | |
|---|---|
| ![Desktop](assets/preview.png) | ![Wallpaper picker](assets/wallpicker.png) |
| Desktop + statusbar | Bấm `Super+w` để đổi wallpaper |
| ![Netpanel](assets/netpanel.png) | ![Firefox](assets/firefox.png) |
| Netpanel — quản lý Wi-Fi | Giao diện Firefox |

## Cài

Cài Arch/CachyOS **không chọn display manager**, boot vào TTY rồi đăng nhập.

```sh
git clone https://github.com/slimulv1/Tsuki.git ~/dwm
cd ~/dwm
./install.sh
```

Lệnh này cài gói phụ thuộc, build `dwm` `st` `slock` `dmenu` `slstatus`, chép
`~/.config` và viết `~/.xinitrc`. Chỉ hỏi mật khẩu khi cần root.

Xong thì gõ `dwm`. Thoát về TTY bằng `Super+Ctrl+Q`.

| Phím | |
|---|---|
| `Super+w` | Đổi wallpaper và theme |
| `Super+Shift+R` | Build lại dwm |
| `Super+Ctrl+Q` | Thoát |

Đầy đủ: [KEYBINDS.md](KEYBINDS.md).

Ảnh nền không có sẵn trong repo, trỏ vào ảnh của bạn:

```sh
echo "$HOME/Pictures/Wallpapers/<tên>.jpg" > ~/dwm/scripts/.wallpaper
```

Muốn thay X.Org bằng XLibre thì `./install.sh xlibre`, thêm `beta` nếu muốn dùng
bản thử. Muốn có màn hình đăng nhập (GDM/SDDM/LightDM) thì `./install.sh session --dm`.

---

MIT — [LICENSE](LICENSE). `dwm` `st` `slock` `dmenu` `slstatus` thuộc
[suckless.org](https://suckless.org). Giao diện Firefox:
[Dook97/firefox-qutebrowser-userchrome](https://github.com/Dook97/firefox-qutebrowser-userchrome) (GPL-3.0).

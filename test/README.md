# Test

Bộ kiểm tra của Tsuki. Mỗi file tự chạy độc lập, in `PASS`/`FAIL` và trả về mã
thoát khác 0 nếu có ca hỏng — nên dùng được cả khi tay và cả trong script.

```sh
for t in test/*.sh; do printf '%-28s ' "$t"; "$t" 2>&1 | tail -1; done
```

| File | Phủ gì |
|---|---|
| `test-run-session.sh` | Cả phiên `run.sh`: khởi động, trap, vòng lặp nạp lại dwm, watchdog, screensaver, font, `dwm 2>` |
| `test-run-matrix.sh` | 29 hình thế môi trường lúc khởi động, mỗi hình thế một thư mục `env -i` riêng. Có canary chặn bộ test chạm vào `$XDG_RUNTIME_DIR` thật |
| `test-run-daemons.sh` | `start_daemon`/`stop_daemons` trích thẳng từ `run.sh`, kể cả daemon tự fork như `fcitx5 -d` |
| `test-firefox-profile.sh` | Dò profile Firefox qua `profiles.ini`/`installs.ini` |
| `test-dwmwal-build.sh` | `_build_check` của `dwmwal.sh`: build hỏng thì phải báo chứ không giết daemon đang chạy |

## Nguyên tắc khi thêm ca mới

- **Trích code thật, đừng chép logic.** `test-run-daemons.sh` cắt nguyên văn
  `start_daemon`/`stop_daemons` từ `run.sh` bằng `sed`, nên test không thể trôi
  khỏi bản đang dùng.
- **Phá code để chứng minh test đỏ được.** Mỗi bản sửa lỗi đều kèm một ca đối
  chứng: bỏ nhánh `if`, đổi ngưỡng, hay chạy lại bản cũ — phải thấy đỏ.
  Nhiều test "PASS" trông vậy là vì rỗng, nên chỉ số xanh không đủ.
- **Phải stub mọi daemon thật.** Thiếu `fcitx5` một lần đã khiến sandbox gọi
  Fcitx5 THẬT, để lại 596 tiến trình mồ côi trên máy (6.2 GB). Stub bắt buộc nằm
  ở thư mục bin mà `run.sh` thật sự nhìn thấy, không phải chỗ khác trong cây.

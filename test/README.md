# Test

Bộ kiểm tra của Tsuki. Mỗi file tự chạy độc lập, in `PASS`/`FAIL` và trả về mã
thoát khác 0 nếu có ca hỏng — nên dùng được cả khi tay và cả trong script.

```sh
for t in test/test-*.sh; do printf '%-28s ' "$t"; "$t" 2>&1 | tail -1; done
```

| File | Phủ gì |
|---|---|
| `test-run-session.sh` | Cả phiên `run.sh`: khởi động, trap, vòng lặp nạp lại dwm, watchdog, screensaver, font, `dwm 2>` |
| `test-run-matrix.sh` | 29 hình thế môi trường lúc khởi động, mỗi hình thế một thư mục `env -i` riêng. Có canary chặn bộ test chạm vào `$XDG_RUNTIME_DIR` thật |
| `test-run-daemons.sh` | `start_daemon`/`stop_daemons` trích thẳng từ `run.sh`, kể cả daemon tự fork như `fcitx5 -d` |
| `test-firefox-profile.sh` | Dò profile Firefox qua `profiles.ini`/`installs.ini` |
| `test-dwmwal-build.sh` | `_build_check` của `dwmwal.sh`: build hỏng thì phải báo chứ không giết daemon đang chạy |

## Công cụ kiểm, không phải test tự động

Ba file dưới đây cũng nằm ở đây nhưng cần thao tác tay hoặc phụ thuộc ngoài, nên
tách riêng cho khỏi nhầm với 5 file trên.

| File | Việc | Ghi chú |
|---|---|---|
| `audit-c23.sh` | Ma trận checklist C23, in PASS/FAIL/SKIP kèm bằng chứng | Mục **10.3 báo FAIL vĩnh viễn**: nó đòi `.github/workflows/ci.yml`, mà CI đã bị gỡ có chủ ý ở `58ac9c7` (rice cá nhân, chỉ máy này dùng). Xem mục "Mục 10.3" bên dưới. |
| `fuzz-status.sh` | Regression test parser escape `status2d` của dwm | Input đến từ WM_NAME — tức **bất kỳ X client nào** trong session đều ghi được. Đã từng giết dwm 3 lần. Cần `Xvfb` để chạy tự động, không có thì bỏ qua gọn. |
| `check-thumbs.sh` | Kiểm chuỗi sinh thumbnail, tự sinh ảnh + video thử | **Ghi vào `~/.cache/thumbnails` thật**, `--clean` xoá sạch trước. Cần thumbnailer + D-Bus. Chạy tay — cố ý không nằm trong vòng lặp ở đầu file. |

## Mục 10.3 của audit

`audit-c23.sh` kiểm có `.github/workflows/ci.yml` không, và báo FAIL khi thiếu.
CI đã bị gỡ ở `58ac9c7` với lý do "rice cá nhân, chỉ máy nó được build mới dùng;
sửa được kiểm tại chỗ bằng `audit-c23.sh` và `fuzz-status.sh`".

Nên 10.3 hiện là FAIL vĩnh viễn — báo động giả. Có ba cách xử lý, chọn một:

1. **Sửa thành SKIP** kèm lý do, nếu không có ý định thêm CI nữa.
2. **Xoá hẳn mục 10.3** khỏi checklist.
3. **Giữ nguyên FAIL** như một lời nhắc: nếu repo sau này thành của người khác
   dùng, thiếu CI là thiếu thật, và con số FAIL buộc phải nhìn.

Hiện tại để nguyên FAIL — đổi cần bạn quyết, tôi không tự đổi tiêu chí kiểm.

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
- **Đường dẫn phải khớp chỗ file thật.** `audit-c23.sh` tự kiểm sự tồn tại của
  `fuzz-status.sh`; chuyển file mà quên sửa dòng đó thì mục kiểm báo sai.

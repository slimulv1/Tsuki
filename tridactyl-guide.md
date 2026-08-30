# Cẩm nang Tridactyl — lướt web toàn bàn phím

> Soạn từ **toàn bộ 9 bài tutorial chính thức** của Tridactyl và
> [tài liệu ex-command](https://tridactyl.xyz/build/static/docs/modules/_src_excmds_.html),
> kèm kiểm chứng lại từng phím trong mã nguồn (`src/lib/config.ts`).
> Mọi phím nhắc tới đều là **phím mặc định** — mới cài về dùng được ngay.
> Bối rối ở đâu thì gõ `:tutor` mở lại bài học, hoặc `:help` để tra cứu.

Tridactyl biến Firefox thành trình duyệt điều khiển bằng bàn phím, kiểu như Vim vậy. Mới nghe có vẻ "rào rào" nhưng mấy thao tác giúp bạn bỏ hẳn con chuột chỉ gói gọn trong vài phím dưới đây.

---

## Cheat sheet — 12 phím nhớ trước hết

| Việc cần làm                          | Phím                  | Ghi chú ngắn gọn                          |
| ------------------------------------- | --------------------- | ----------------------------------------- |
| Mở trang / tìm kiếm                   | `o` / `t`             | `o` = tab này, `t` = tab mới, `w` = cửa sổ |
| Nhảy vào ô nhập liệu                  | `gi`                  | `Tab` để đổi ô                            |
| Đóng tab — mở lại tab vừa đóng        | `d` → `u`             | Tandem "hối hận" quen thuộc               |
| Chuyển tab kế / trước                 | `K` / `J`             | `g0`/`g$` = đầu/cuối, `Ctrl-6` = tab vừa rời |
| Danh sách tab, gõ để lọc              | `b`                   | `B` mở rộng ra mọi cửa sổ                 |
| "Bấm" link bằng phím                  | `f` / `F`             | `F` mở ở tab nền                          |
| Chép URL — dán mở                     | `yy` → `p`            | `P` dán ra tab mới                        |
| Quay lại trang trước / về chỗ cuộn cũ | `H` / `Ctrl-O`        | `Ctrl-O` nhớ vị trí đọc, hết thì tự lùi   |
| Tìm trong trang / nhảy kết quả        | `/` → `Ctrl-G`        | `Ctrl-Shift-G` ngược lại                   |
| Tìm kiếm luôn                         | `s` / `S`             | `S` = tab mới; `:open yt <từ>` cho YouTube |
| Đọc gọn gàng — lần trang (bài nhiều đoạn) | `gr` / `]]` `[[`   | Reader mode gọn quảng cáo                  |
| Đóng Firefox                          | `ZZ`                  | —                                         |

---

**Điều hướng & tab** — §1 Quen nền tảng · §2 Mở tab · §3 Đóng tab · §4 Chuyển tab

## 1. Quen nền tảng: năm "trạng thái"

Bất cứ lúc nào Tridactyl cũng nằm trong **một** trong năm trạng thái (mode) sau:

| Trạng thái      | Bước vào   | Đặc điểm                                                        |
| --------------- | ---------- | --------------------------------------------------------------- |
| **Normal mode** | mặc định   | mọi phím gõ đều là lệnh của Tridactyl                           |
| **Hint mode**   | `f`        | mỗi link gắn một nhãn chữ; gõ nhãn = click. Nhãn IN HOA chỉ để dễ đọc, gõ **thường** |
| **Visual mode** | `v`        | chọn đoạn văn bản bằng phím, sao chép hoặc đem đi tìm kiếm      |
| **Command mode**| `:`        | gõ lệnh dài như `:tabopen`, giống hệt Vim                       |
| **Ignore mode** | `Shift-Insert` | nhường toàn bộ bàn phím cho trang web (game, Gmail); bấm lại để thoát |

> [!IMPORTANT]
> **Chữ hoa khác chữ thường — xin đừng quên.** Tridactyl coi `o` và `O` là *hai lệnh khác nhau*. Muốn chạy lệnh viết hoa (`O`, `T`, `F`, `K`...) thì giữ `Shift` bấm chữ đó như gõ chữ hoa bình thường. Ví dụ `Shift+o` mở ô lệnh đã điền sẵn địa chỉ trang đang đứng; `ZZ` (hai chữ hoa) là lưu và đóng Firefox. Riêng trong hint mode thì ngược lại: nhãn hoa chỉ vì dễ đọc, gõ thường là chuẩn. Còn trong ô nhập liệu (`gi`) thì gõ hoa như thường — Tridactyl đứng ngoài cuộc.

Muốn thoát về normal mode bất cứ lúc nào: `Escape` (hoặc `Ctrl-[`).

## 2. Mở tab — "tôi muốn xem cái này"

| Ý của bạn                  | Bấm | Kết quả                                      |
| -------------------------- | --- | -------------------------------------------- |
| Xem luôn ở tab này          | `o` | mở ngay tại tab đang xem                     |
| Xem ở tab mới               | `t` | mở tab mới (thói quen nên nuôi)              |
| Xem ở cửa sổ riêng          | `w` | mở cửa sổ mới                                |
| Như trên mà kèm URL đang mở | `O` / `T` / `W` | ô lệnh được điền sẵn địa chỉ hiện tại |
| Muốn **tìm kiếm** luôn       | `s` / `S` | mở ô tìm với engine mặc định (tab này / tab mới) |
| Mở ở tab nền, không nhảy    | `:tabopen -b link` | mở ra sau lưng, đọc tiếp sau            |

> [!NOTE]
> Gõ `o` rồi nhập gì cũng được — Tridactyl tự đoán ý bạn: có `https://` hoặc dấu chấm giữa chữ → xem là *địa chỉ trang*, mở thẳng (thiếu `http://` thì tự thêm); bắt đầu bằng tên engine (`google`, `yt`...) → *tìm trong engine đó*; còn lại → *tìm bằng engine mặc định*.

## 3. Đóng tab và "cứu" tab vừa đóng

- `d` — đóng tab đang xem
- `D` — đóng tab rồi quay về tab trước đó luôn
- `:tabonly` — giữ lại tab này, dọn sạch mọi tab khác trong cửa sổ
- `gx$` / `gx0` — đóng hết các tab bên phải / bên trái
- `u` — **quả cam hối hận**: mở lại tab vừa đóng trong tích tắc
- `U` — mở lại cả cửa sổ vừa đóng
- `:tabduplicate` — nhân bản tab hiện tại (giữ nguyên trang, vị trí)
- `:tabmove 2` / `:tabmove $` — dời tab tới vị trí số 2, hoặc tận cùng bên phải

> [!NOTE]
> `d` đóng thẳng, không hỏi han gì cả. Tab đã ghim (pin) thì không đóng được bằng `d`.

## 4. Chuyển qua lại giữa các tab

- `K` / `J` — sang tab kế tiếp / quay về tab trước
- `gt` — nhảy tới tab số N: gõ `gt` rồi gõ số, hoặc `:tab 3`
- `g0` / `g$` — về ngay tab đầu tiên / tab cuối
- `Ctrl-6` — trở về đúng tab vừa rời đi; qua lại hai tab thì phím này "xịn" nhất
- `b` — danh sách tab của cửa sổ này; gõ vài ký tự để lọc, `Enter` để chọn
- `B` — như `b` nhưng liệt kê cả tab ở các cửa sổ khác
- `:tab foo` — nhảy thẳng tới tab có chứa chữ "foo" trong tên hoặc địa chỉ

> [!TIP]
> Bản mặc định để `J` = tab trước, `K` = tab sau — ngược với thói quen người dùng qutebrowser. Muốn đảo cho hợp tay: gõ `:bind J tabnext`, rồi `:bind K tabprev`.

---

**Tìm kiếm & nội dung** — §5 Tìm kiếm & quay lại · §6 Thao tác hằng ngày · §7 Visual mode · §8 Marks · §9 Hint nâng cao

## 5. Tìm kiếm thông tin

- `s` / `S` — mở ô tìm kiếm với engine mặc định (tab này / tab mới)
- `:open google từ khóa` — tìm theo engine cụ thể; `:open yt từ khóa` cho YouTube
- `/` — tìm kiếm ngay trong trang đang đọc; `Ctrl-G` / `Ctrl-Shift-G` nhảy qua các kết quả
- `H` / `L` — quay lại trang trước / đi tới trang kế (như nút Back/Forward)

### Quickmark — danh bạ cho các trang hay ghé

- Lưu: `:quickmark m` (lưu trang đang mở) hoặc `:quickmark m https://duckduckgo.com`
- Mở: `go m` (tab này), `gn m` (tab mới), `gw m` (cửa sổ mới)
- Xóa: `:quickmarkremove m`
- Đường tắt: bấm `M` rồi một ký tự — lưu ngay trang đang đứng mà không cần gõ lệnh

### Quay lại trang trước — 4 mức độ "lùi"

1. **`H`** — lùi đúng một bước trong lịch sử; muốn lùi nhiều thì `2H` hoặc `:back 2`.
2. **`Ctrl-O`** — quay về **chỗ cuộn cũ**: mỗi lần cuộn, Tridactyl lén ghi nhớ vị trí bạn đang đọc; `Ctrl-O` đưa bạn về vị trí trước đó, bấm tiếp tới khi hết thì nó tự "lùi" sang lịch sử. `Ctrl-I` đi chiều ngược lại.
3. **`gu`** — trèo lên một nấc địa chỉ: đang ở `/tin-tuc/bai-viet` thì `gu` về `/tin-tuc`, `2gu` lên tiếp một nấc; `gU` trở về chỉ còn tên miền.
4. **`[[`** — với báo mạng kiểu "1 2 3...": `[[` quay về trang trước, `]]` sang trang sau. Tự nhận biết link "trang trước/sau" hoặc đoán số trang trong địa chỉ.

> [!TIP]
> Lỡ trôi xa quá trong lịch sử thì gõ `:back ` (**chú ý dấu cách đằng sau**) — Tridactyl hiện *cây lịch sử* của tab, chọn thẳng trang muốn về, khỏi bấm Back mò mẫm từng bước. `:forward ` làm tương tự cho chiều tới.

## 6. Mớ thao tác thường dùng mỗi ngày

| Thao tác                          | Phím        | Ghi chú                                    |
| --------------------------------- | ----------- | ------------------------------------------ |
| Chép URL trang đang xem            | `yy`        | `yt` chép tên, `ym` chép dạng link Markdown |
| Dán clipboard ra mở                | `p` / `P`   | `P` = tab mới; chép được cả URL lẫn chuỗi tìm |
| Tải lại / tải lại thật sạch        | `r` / `R`   | `R` bỏ qua cache                           |
| Dừng tải                           | `x`         | trang ì ạch thì bấm cho đỡ nóng mắt        |
| "Bấm" link bằng phím               | `f` / `F`   | `F` mở ở tab nền                           |
| Phóng / thu / trả về 100%          | `zi` / `zo` / `zz` | —                                   |
| Đọc gọn gàng (reader mode)         | `gr`        | quảng cáo, cột phụ biến mất, chữ căn lại   |
| Lật tới / lùi trang bài nhiều đoạn | `]]` / `[[` | —                                         |
| Lặp lại thao tác vừa làm            | `.`         | quý nhất lúc phải làm đi làm lại một việc  |
| Lưu và đóng Firefox                | `ZZ`        | —                                         |

## 7. Chọn chữ rồi sao chép — Visual mode

Bấm `v` để vào chế độ chọn (trang cũng tự chuyển khi bạn bôi đen bằng chuột, hoặc qua `;h`):

- Dùng phím di chuyển để bung/thu vùng chọn: `h/j/k/l` từng ký tự, `w`/`b`/`e` từng từ, `0` về đầu dòng, `$` tới cuối dòng; gõ `=` liên tục tới khi cả trang sáng lên
- `o` — đảo hai đầu vùng chọn (cứu cánh khi lỡ kéo chọn quá xa)
- `y` — sao chép vùng chọn
- `s` / `S` — đem vùng chọn đi tìm kiếm ngay (tab này / tab mới)

## 8. Marks — đánh dấu chỗ đang đọc

Đọc được nửa bài dài mà phải đi làm thì khỏi lo: mark nhớ **vị trí cuộn** (quickmark chỉ nhớ trang, mark nhớ cả chỗ đứng):

- `m` + chữ thường (`ma`, `mb`...) — chấm một điểm trên trang hiện tại (chỉ tồn tại trong phiên làm việc)
- `m` + chữ hoa (`mA`...) — chấm điểm "toàn cục": hôm sau mở trình duyệt vẫn nhảy tới được
- Gõ `` ` `` + chữ — nhảy tới điểm đã đánh dấu
- Gõ `` `` `` — nhảy trở về nơi bạn đứng **trước** lần nhảy mark vừa rồi (kiểu "đi nhanh về nhanh")

## 9. Hint mode "trình cao" hơn

Đã quen `f`/`F` thì mấy phím này mê ly:

- `;y` — chép địa chỉ của link
- `;p` — chép trọn một đoạn văn; gõ tiếp `P` là đem đi tìm kiếm — mẹo số một để lần ra nguồn của một câu trích dẫn
- `;#` — chép liên kết nhảy tới đúng đoạn trong trang (`#đoạn-3`), tiện khi gửi link trỏ chính xác
- `;k` — xóa phăng một mảng quảng cáo (hết hạn khi tải lại trang)
- `;K` — chỉ giấu đi thôi, `:elementunhide` hiện lại
- `;i` / `;I` — chép ảnh / tải ảnh về máy
- `;h` — chọn chữ bắt đầu từ vị trí này (bước vào visual mode)

> [!TIP]
> Nhãn màu **xám** là chỗ dính JavaScript (menu ẩn, nút bật...). Nếu một phần tử có cả nhãn xám lẫn đỏ thì bấm **nhãn đỏ**. Khi trên màn hình chỉ còn đúng một nhãn thì Tridactyl tự "click" luôn, khỏi cần gõ.

---

**Tùy biến & nâng cao** — §10 Ô lệnh `:` · §11 Tùy biến · §12 Containers · §13 Native messenger · §14 Tra cứu

## 10. Gõ lệnh phức tạp hơn với `:`

Ô `:` như một cửa sổ lệnh thu nhỏ:

- `:tabdetach` — tách tab đang xem ra cửa sổ riêng
- `:composite reload; tabnext` — chạy nhiều lệnh liên tiếp (đổi `;` thành `|` khi muốn kết quả lệnh nọ truyền sang lệnh kia)
- `:viewsource` — xem mã nguồn trang (phím tắt `gf`)
- `:viewconfig nmaps` — xem keybind hiện hành

Ngay trong ô `:` cũng có phím riêng: `Up`/`Down` dò lịch sử lệnh, `Tab` dạo các gợi ý, `Space` chèn địa chỉ của gợi ý đang chọn vào lệnh, `Ctrl-Enter` chạy lệnh mà không đóng ô (tiện làm tiếp việc khác), `Ctrl-o` rồi `yy` để chép gợi ý đang chọn.

## 11. Tùy biến cho riêng mình

- Xem / sửa cấu hình: `get [tên]`, `set [tên] [giá trị]`, `unset [tên]`; `reset [phím]` trả phím về bản gốc
- `:set searchengine duckduckgo` — đổi máy tìm kiếm mặc định; thêm engine riêng nhớ để ý setting `searchurls`
- `:set hintfiltermode vimperator` kèm `:set hintchars 5432167890` — lọc nhãn bằng cách gõ thẳng chữ hiển thị trên link, đỡ phải học thuộc ký tự
- `:colours dark` — đổi sắc màu giao diện Tridactyl
- `:seturl [mẫu-URL] [key] ...` / `:bindurl ...` — cấu hình chỉ áp dụng cho những trang khớp mẫu
- `:bind --mode=hint [phím] [lệnh]` — gán phím riêng cho từng trạng thái

> [!NOTE]
> **File cấu hình của bạn** (tên `tridactylrc`): sửa xong gõ `:source` để nạp. Tridactyl ưu tiên tìm ở `~/.config/tridactyl/tridactylrc` trước, rồi mới ngó tới `~/.tridactylrc` thời kỳ cũ; gõ `:findrc` để biết đang dùng file nào. Trong file, mỗi dòng một lệnh y như gõ trong `:`; đầu dòng `#` hoặc `"` là chú thích. Muốn "xuất khẩu" toàn bộ cấu hình đang có ra file: `:mkt -f`.

## 12. Containers — nhiều tài khoản, một trình duyệt

Containers giúp mở nhiều tài khoản trên cùng một trang cùng lúc mà không lẫn: cookie được cách ly, trang trong container này không đọc được dữ liệu của container kia.

- `:tabopen -c cong-viec mail.google.com` — mở trang trong container "cong-viec"
- `:set tabopencontaineraware true` — từ nay `:tabopen` dùng chung container với tab đang đứng
- `:autocontain -s gmail\.com cong-viec` — mọi địa chỉ khớp mẫu tự mở vào container nói trên
- `:containercreate work` / `:viewcontainers` / `:recontain work` — tạo mới / xem danh sách / đổi container cho tab hiện tại

## 13. Native messenger — "tháo khóa" những tính năng xịn

Gõ `:nativeinstall` để cài (Arch thì lấy `firefox-tridactyl-native` ở AUR); kiểm tra bằng `:native` — nó báo ổn là ổn.

Từ đây bạn có thêm: nhảy từ ô text ra soạn thảo bằng trình editor yêu thích (`:help editor`), đọc cấu hình từ file trên đĩa, `:restart` Firefox, đổi giao diện bằng `:guiset`, nạp theme từ máy bằng `:colors`, tự chọn nơi lưu khi dùng `:saveas`, chỉnh `about:config` ngay trong console bằng `:setpref` — và cả dấu **`!`** để chạy lệnh hệ thống ngay từ Firefox: `!ls ~/Downloads` là thấy thư mục tải về của bạn.

## 14. Quên rồi thì tra ở đâu?

- `:help [lệnh]` hoặc `:help [phím]` — mở tài liệu đúng chỗ bạn cần
- `:bind [phím]` — phím này đang làm gì: `:bind d` sẽ trả lời `tabclose`
- `:get [setting]` — giá trị hiện tại của một cấu hình
- `:apropos [từ khóa]` — tìm mọi thứ liên quan tới từ khóa
- `:viewconfig` — soi toàn bộ cấu hình của mình (trang này Tridactyl tự "đứng ngoài", bấm `Alt-←` để trở lại)
- Cộng đồng: `github.com/tridactyl/tridactyl/wiki` · chuyện trục trặc: đọc `doc/troubleshooting.md` trong repo

---

Chúc bạn sớm lướt web không chuột. Luyện như tập ngón đàn: hôm nay quen vài phím, tuần sau tự khắc bỏ chuột — rồi một ngày không hiểu sao mình lại cầm nó làm gì.

*Soạn từ Tridactyl master (8a6bae17): `src/lib/config.ts`, `src/excmds.ts` và toàn bộ `src/static/clippy/`.*
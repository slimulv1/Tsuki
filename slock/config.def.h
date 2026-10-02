/* user and group to drop privileges to */
static const char *user  = "nobody";
/* Nhóm dùng khi slock hạ quyền. PHẢI tồn tại trên máy.
 *
 * Tên "nogroup" là quy ước của Debian/Ubuntu. Arch và CachyOS KHÔNG có group
 * đó — gid 65534 trên Arch mang tên "nobody" (đo trên máy này:
 * `getent group nogroup` không trả gì, còn `awk -F: '$3==65534' /etc/group`
 * cho "nobody").
 *
 * Hậu quả khi sai: slock chết ở slock.c:379 `getgrnam(group)` trước khi tới
 * XGrabPointer, nên KHÔNG khoá được gì. Đo trên binary cũ ở
 * /usr/local/bin/slock (setuid 4755, quyền đúng):
 *     $ /usr/local/bin/slock
 *     slock: getgrnam nogroup: group entry not found
 *     rc = 1
 * Tức Super+Delete trên máy này im lặng không làm gì — khoá màn hình hỏng
 * hoàn toàn mà không có thông báo nào cho người dùng.
 *
 * Đổi sang "nobody" cho khớp Arch. user ở trên vốn đã là "nobody" nên giờ
 * user:group đồng nhất — đây là cặp mặc định trên Arch, không phải lỗi.
 */
static const char *group = "nobody";

/* ------------------------------------------------------------------ giao diện
 *
 * slock gốc chỉ tô MỘT màu nền phẳng theo trạng thái, đổi giữa 3 giá trị
 * trong `colorname[]`. Không có gì khác trên màn hình: không chữ, không gợi ý,
 * không biết đang khoá ai, không thấy đã gõ bao nhiêu ký tự. Bản cài cũ còn
 * hardcode hai màu lạ "#005577" (xanh) và "#CC3333" (đỏ) — không thuộc bảng
 * màu của rice nên nhìn lạc, và đỏ của pywal tối quá nên đọc kém.
 *
 * Nay vẽ một cảnh thật sự:
 *   - NẾN: chụp nội dung root window (tức wallpaper) rồi làm mờ + tối đi trong
 *     phần mềm, nên thấy wallpaper mờ thay vì một khối màu. Không cần XRender,
 *     không cần compositor — thuần Xlib. Xem render_backdrop().
 *   - GIỮA MÀN HÌNH, theo cột:
 *       1. GIỜ (font 76) — đồng hồ tự đánh lại mỗi giây (readpw dùng select()
 *          với timeout 1s thay cho XNextEvent chặng vô hạn).
 *       2. Ngày tháng (font 17, màu dim).
 *       3. Tên đăng nhập (font 21).
 *       4. Dấu chấm: mỗi ký tự đã gõ một chấm, tô tròn bằng XFillArc nên không
 *          phụ thuộc font có ký tự ● hay không.
 *   - Khi sai mật khẩu: dấu chấm đổi sang slock_err và hiện dòng nhắc.
 *
 * slock_err VẪN phải là đỏ. Ở đây màu mang NGỮ NGHĨA chứ không phải trang trí:
 * bỏ đỏ thì không phân biệt được "gõ sai" với "chưa bấm Enter". Nhưng chọn
 * đỏ đủ sáng trên nền tối (#f2555a) thay vì #CC3333 cũ, và các màu khác lấy
 * tông tím của rice nên không còn lạc.
 */
static const char *slock_fg     = "#ece6f0";  /* giờ, tên user          */
static const char *slock_dim    = "#a89ec4";  /* ngày tháng             */
static const char *slock_accent = "#9881dc";  /* dấu chấm khi gõ       */
static const char *slock_err    = "#f2555a";  /* dấu chấm + nhắc khi sai */

/* Màu nền dự phòng khi không chụp được root window (XGetImage trả NULL).
 * Tối hơn hẳn wallpaper để chữ vẫn đọc được. */
static const char *slock_fallback_bg = "#141018";

static const char *slock_font_big   = "Iosevka:style=Bold:size=76";
static const char *slock_font_small = "Iosevka:style=Regular:size=17";
static const char *slock_font_name  = "Iosevka:style=Medium:size=21";

/* Nền giữ lại bao nhiêu % độ sáng gốc sau khi làm mờ. 62% đủ thấy wallpaper
 * làm "kính mờ" mà chữ #ece6f0 vẫn nổi rõ. */
static const int slock_backdrop_keep = 62;

/* Hệ số thu nhỏ để làm mờ: lấy trung bình mỗi khối NxN rồi nội suy bilinear
 * ngược lại. Nhỏ hơn = mờ nhiều hơn và nhanh hơn. 8 hợp với màn 3440x1440
 * (đo trên máy này) — buffer trung gian chỉ ~0.6 MB. */
static const int slock_blur_div = 8;

/* Số dấu chấm tối đa. Mật khẩu dài hơn thì hiện N chấm + "+M" để không tràn
 * hàng (hàng chấm rộng ~13px/chấm; 12 chấm ~ 190px, vừa gọn trên 3440px). */
static const int slock_max_dots = 12;

/* treat a cleared input like a wrong password (color) */
static const int failonclear = 1;

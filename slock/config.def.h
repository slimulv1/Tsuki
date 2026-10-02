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
 * XGrabPointer, nên KHÔNG khoá được gì. Đo trên binary đã cài ở
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

static const char *colorname[NUMCOLS] = {
	[INIT] =   "black",     /* after initialization */
	[INPUT] =  "#005577",   /* during input */
	[FAILED] = "#CC3333",   /* wrong password */
};

/* treat a cleared input like a wrong password (color) */
static const int failonclear = 1;

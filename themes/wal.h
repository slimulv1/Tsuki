static const char black[]       = "#1a1a1a";
static const char gray2[]       = "#635454";
static const char gray3[]       = "#d3cfcf";
static const char gray4[]       = "#635454";
static const char blue[]        = "#6742d7";
static const char green[]       = "#493684";
static const char red[]         = "#45327b";
static const char orange[]      = "#4e3a8c";
static const char yellow[]      = "#9f8adf";
static const char pink[]        = "#58419e";
static const char col_borderbar[]  = "#1a1a1a";
static const char white[]       = "#d3cfcf";

// tag1..tag5: màu riêng cho 5 workspace (SchemeTag1..5 trong config.h).
//
// VÌ SAO PHẢI Ở ĐÂY, KHÔNG SỬA TAY themes/wal.h: file này BỊ GHI LẠI MỖI LẦN
// chạy dwmwal.sh (lệnh cat > ngay trên dòng này). Bản sửa trước thêm tag1..tag5
// bằng tay vào themes/wal.h — chạy đúng một lần đổi ảnh nền là mất sạch, rồi
// config.h:73 tham chiếu tên không tồn tại và dwm KHÔNG BIÊN DỊCH được:
//   config.h:73: error: 'tag1' undeclared here (not in a function)
// Super+Shift+R vẫn được vì nó không sinh lại wal.h; Super+W thì hỏng. Đúng
// triệu chứng đã gặp.
//
// LƯU Ý KHI SỬA KHỐI ĐOẠN NÀY: heredoc là << EOF (KHÔNG quoted), nên shell
// mở rộng $ và dấu gạch ngược. Backtick trong comment sẽ bị shell đọc như lệnh
// và làm hỏng CẢ dwmwal.sh: đã dính "syntax error near unexpected token newline"
// vì viết lệnh cat > trong ngoặc ngược. Comment ở đây cố ý không có backtick.
//
// ÁNH XẠ: mỗi workspace nhận một màu của dải SÁNG (color9..color15, color7),
// đúng như slstatus đang dùng. KHÔNG sửa blue/green/red/orange/pink — chúng
// không chỉ cho workspace:
//   - blue là NỀN của SchemeSel và TabSel (config.h:68,70). Nền sáng làm chữ
//     trên đó mất tương phản — đổi blue sẽ hỏng thanh highlight.
//   - green là màu SchemeLayout và SchemeBtnPrev; red là SchemeBtnClose.
// Đổi chúng sẽ đổi cả nút điều hướng, việc này người dùng không yêu cầu.
// Bỏ color0..color8: đó là dải tối, dùng cho nền/nút, đưa vào chữ là mất
// tương phản.
//   tag1 <- color10   (CPU)      tag4 <- color13   (nhiệt độ)
//   tag2 <- color9    (RAM)      tag5 <- color7    (chữ sáng)
//
// VÌ SAO DÙNG CHÍNH DẢI SÁNG ĐÓ — số đo thật trên màn hình, chụp rồi đếm
// pixel (chạy với ảnh FW 13 Pro Wallpaper 6.png):
//     blue   #6742d7  lum  84.6
//     red    #45327b  lum  59.3
//     orange #4e3a8c  lum  68.2
//     green  #493684  lum  63.7
//     pink   #58419e  lum  76.6
//   slstatus: #9881dc 140.5 · #9077da 131.5 · #9f8adf 148.6 · #af9de4 166.0
// => cả 5 màu cũ đều tối hơn thanh trạng thái đứng cạnh nó 70–95 điểm, đọc
//    rất khó. Dải sáng ở trên khớp 5 màu slstatus đang dùng nên hòa vào.
static const char tag1[]        = "#9881dc";
static const char tag2[]        = "#9077da";
static const char tag3[]        = "#9f8adf";
static const char tag4[]        = "#af9de4";
static const char tag5[]        = "#d3cfcf";

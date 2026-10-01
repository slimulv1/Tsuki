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

// Màu riêng cho 5 workspace bên trái (SchemeTag1..5).
//
// VÌ SAO THÊM TÊN RIÊNG, KHÔNG SỬA LẠI 5 TÊN CŨ: đo trên màn hình thật
// (scrot -> dem pixel), workspace hiện hiển thị #6742d7, luminance 84.6 —
// trong khi slstatus dùng #9881dc, luminance 140.5. Lệch 56 điểm, tức
// workspace tối hơn hẳn thanh trạng thái đứng cạnh nó. Đo cả 5:
//     blue   #6742d7  lum  84.6
//     red    #45327b  lum  59.3
//     orange #4e3a8c  lum  68.2
//     green  #493684  lum  63.7
//     pink   #58419e  lum  76.6
//   slstatus: #9881dc 140.5 · #9077da 131.5 · #9f8adf 148.6 · #af9de4 166.0
//   => cả 5 đều tối hơn slstatus 70–95 điểm.
//
// KHÔNG sửa blue/green/red/orange/pink: chúng không chỉ cho workspace.
//   - `blue` là NỀN của SchemeSel và TabSel (config.h:68,70). Nền sáng làm
//     chữ trên đó mất tương phản — đổi `blue` sẽ hỏng thanh highlight.
//   - `green` là màu SchemeLayout và SchemeBtnPrev; `red` là SchemeBtnClose.
// Đổi chúng sẽ đổi cả nút điều hướng, việc này người dùng không yêu cầu.
//
// 5 màu dưới đây LẤY THẲNG từ slstatus đang chạy, không tự chọn:
// đọc từ output `slstatus -s` trên chính máy này.
static const char tag1[]        = "#9881dc";  /* lum 140.5 — như CPU */
static const char tag2[]        = "#9077da";  /* lum 131.5 — như RAM */
static const char tag3[]        = "#9f8adf";  /* lum 148.6 — như đĩa */
static const char tag4[]        = "#af9de4";  /* lum 166.0 — như nhiệt độ */
static const char tag5[]        = "#d3cfcf";  /* lum 207.9 — trắng, như chữ */

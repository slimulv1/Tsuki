// user.js - applied at Firefox startup
// Bật userChrome.css (bắt buộc để load css customize giao diện)
user_pref("toolkit.legacyUserProfileCustomizations.stylesheets", true);
// Cho phép vẽ cửa sổ nền trong suốt (cần cho giao diện transparent qua userChrome.css)
user_pref("browser.tabs.allowTransparentBrowser", true);
// Tắt theme "Nova" mặc định (để userChrome.css không bị nó đè/bao phủ)
user_pref("browser.nova.enabled", false);
// Hiện chọn "Compact" trong menu Customize toolbar (density)
user_pref("browser.compactmode.show", true);

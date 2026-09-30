
# fnm
# BUG ĐÃ SỬA: ghi cứng /home/magnus/.local/share/fnm — tên user của máy khác,
# thư mục đó không tồn tại nên `if [ -d ... ]` luôn false và fnm không bao giờ
# được nạp. Dùng $HOME đúng theo máy.
set FNM_PATH "$HOME/.local/share/fnm"
if [ -d "$FNM_PATH" ]
  set PATH "$FNM_PATH" $PATH
  fnm env --shell fish | source
end

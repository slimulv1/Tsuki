# ═══════════════════════════════════════════════════════════════
# config.fish — MERGED: Arisa (user) × Loom (KabosuNeko dotfiles)
# Backup cũ: config.fish.bak-pre-loom
# ═══════════════════════════════════════════════════════════════

# CachyOS system config — stderr silenced: upstream has 2 broken `alias vim = helix`
# lines (spaces around '=') that print warnings and define nothing.
source /usr/share/cachyos-fish-config/cachyos-config.fish 2>/dev/null

# ── Arisa: restore intended aliases (broken upstream) ─────────
alias vim 'nvim'
alias arisa 'opencode'
alias Arisa 'opencode'
alias opencode-clean 'rm -rf ~/.local/share/opencode ~/.config/opencode ~/.cache/opencode ~/.local/state/opencode /tmp/opencode ./.opencode.json ./.opencode/ 2>/dev/null; and echo "✅ Đã xóa sạch dữ liệu OpenCode"'
alias cdwm 'vim ~/dwm/config.h'
alias mdwm 'cd ~/dwm; sudo make clean install; cd -'

# ── Loom: pywal colors (tự theo wallpaper — dwmwal tạo colors.fish) ──
if test -f ~/.cache/wal/colors.fish
    source ~/.cache/wal/colors.fish
    if set -q foreground
        set fish_color_normal $foreground
        set fish_color_command $color4
        set fish_color_keyword $color5
        set fish_color_quote $color3
        set fish_color_redirection $color6
        set fish_color_end $color3
        set fish_color_error $color1
        set fish_color_param $color2
        set fish_color_comment $color8
        set fish_color_match --background=$color4
        set fish_color_selection --background=$color8
        set fish_color_search_match --background=$color8
        set fish_color_history_current --bold
        set fish_color_operator $color6
        set fish_color_escape $color5
        set fish_color_cwd $color4
        set fish_color_cwd_root $color1
        set fish_color_valid_path --underline
        set fish_color_autosuggestion $color8
        set fish_color_user $color2
        set fish_color_host $color4
        set fish_color_cancel $color1 '--reverse'
        set fish_color_option $color3

        set fish_pager_color_background $background
        set fish_pager_color_completion $foreground
        set fish_pager_color_description $color8
        set fish_pager_color_prefix $color4
        set fish_pager_color_progress $color8

        set fish_pager_color_secondary_background $background
        set fish_pager_color_secondary_completion $foreground
        set fish_pager_color_secondary_description $color8
        set fish_pager_color_secondary_prefix $color4

        set fish_pager_color_selected_background --background=$color8
        set fish_pager_color_selected_completion $foreground
        set fish_pager_color_selected_description $color8
        set fish_pager_color_selected_prefix $color4
    end
end

# ── Loom: done plugin — đã có conf.d/done.fish (auto-source) ──
set -U __done_min_cmd_duration 10000
set -U __done_notification_urgency_level low

# ── Loom: man pages qua bat ──
set -x MANROFFOPT "-c"
set -x MANPAGER "sh -c 'col -bx | bat -l man -p'"

# ── Loom: .fish_profile ──
if test -f ~/.fish_profile
    source ~/.fish_profile
end

# ── Loom: PATH ~/.local/bin (depot_tools bỏ vì chưa có) ──
if test -d ~/.local/bin
    if not contains -- ~/.local/bin $PATH
        set -p PATH ~/.local/bin
    end
end

# ── Loom: bang-bang (!! / !$) — oh-my-fish/plugin-bang-bang ──
function __history_previous_command
  switch (commandline -t)
  case "!"
    commandline -t $history[1]; commandline -f repaint
  case "*"
    commandline -i !
  end
end

function __history_previous_command_arguments
  switch (commandline -t)
  case "!"
    commandline -t ""
    commandline -f history-token-search-backward
  case "*"
    commandline -i '$'
  end
end

if [ "$fish_key_bindings" = fish_vi_key_bindings ]
  bind -Minsert ! __history_previous_command
  bind -Minsert '$' __history_previous_command_arguments
else
  bind ! __history_previous_command
  bind '$' __history_previous_command_arguments
end

# ── Loom: history với timestamp ──
function history
    builtin history --show-time='%F %T '
end

# ── Loom: backup & copy ──
function backup --argument filename
    cp $filename $filename.bak
end

# Copy DIR1 DIR2 (recursive nếu nguồn là dir)
function copy
    set count (count $argv | tr -d \n)
    if test "$count" = 2; and test -d "$argv[1]"
        set from (echo $argv[1] | trim-right /)
        set to (echo $argv[2])
        command cp -r $from $to
    else
        command cp $argv
    end
end

# ── Loom: aliases hữu ích (eza style user giữ ở dưới) ──
alias l.="eza -a | grep -e '^\.'"
alias grubup="sudo grub-mkconfig -o /boot/grub/grub.cfg"
alias fixpacman="sudo rm /var/lib/pacman/db.lck"
alias tarnow='tar -acf '
alias untar='tar -zxvf '
alias wget='wget -c '
alias psmem='ps auxf | sort -nr -k 4'
alias psmem10='ps auxf | sort -nr -k 4 | head -10'
alias ..='cd ..'
alias ...='cd ../..'
alias ....='cd ../../..'
alias .....='cd ../../../..'
alias ......='cd ../../../../..'
alias dir='dir --color=auto'
alias vdir='vdir --color=auto'
alias grep='grep --color=auto'
alias fgrep='fgrep --color=auto'
alias egrep='egrep --color=auto'
alias hw='hwinfo --short'
alias big="expac -H M '%m\t%n' | sort -h | nl"
alias gitpkg='pacman -Q | grep -i "\-git" | wc -l'
alias update='sudo pacman -Syu'
alias mirror="sudo cachyos-rate-mirrors"
alias apt='man pacman'
alias apt-get='man pacman'
alias please='sudo'
alias tb='nc termbin.com 9999'
alias cleanup='sudo pacman -Rns (pacman -Qtdq)'
alias jctl="journalctl -p 3 -xb"
alias rip="expac --timefmt='%Y-%m-%d %T' '%l\t%n %v' | sort | tail -200 | nl"

# ── Loom: ssh-agent (bỏ ssh-add id_ed25519 — máy chưa có key) ──
if not pgrep -u (whoami) ssh-agent > /dev/null
    eval (ssh-agent -c) > /dev/null
end

# ── Arisa: fcitx login env ──
if status is-login
    set -Ux GTK_IM_MODULE fcitx
    set -Ux QT_IM_MODULE fcitx
    set -Ux XMODIFIERS @im=fcitx
    set -Ux SDL_IM_MODULE fcitx
    set -Ux GLFW_IM_MODULE ibus
end

# ── Arisa: bun ──
set --export BUN_INSTALL "$HOME/.bun"
set --export PATH $BUN_INSTALL/bin $PATH
export OPENCODE_EXPERIMENTAL_BACKGROUND_SUBAGENTS=true

# ── Arisa: starship prompt (giữ — không dùng fish_prompt Loom) ──
starship init fish | source

# ── Arisa: eza + bat style ──
alias ls 'eza --icons --group-directories-first'
alias ll 'eza --icons --group-directories-first --time-style long-iso -l'
alias la 'eza --icons --group-directories-first --time-style long-iso -la'
alias lt 'eza --icons --group-directories-first --tree --level 2'
alias cat 'bat --paging=never'

# ── Arisa: greeting (giữ — Loom greeting time/uptime bỏ) ──
function fish_greeting
    set_color --bold bb9af7
    echo "アリサ、オンライン — ターミナル準備完了。ご主人様、今日は何をいたしましょうか？"
    set_color normal
    set -l current_time (date +"%-I:%M%P")
    set -l uptime_text (uptime -p | string replace -r '^up ' '')
    set -l kernel (uname -r)
    set_color -b black
    printf " "
    set_color brblack
    printf "it's  "
    set_color blue
    printf "%s" $current_time
    set_color green
    printf "  %s" $uptime_text
    set_color magenta
    printf "  %s" $kernel
    set_color normal
    printf " \n"
    printf " \n"
    
end



# ── Arisa: Lớp Bảo Vệ — công cụ nhanh ──
alias scan-skill '~/.local/bin/scan-skill.sh --all'
alias backup-opencode '~/.local/bin/backup-opencode.sh'
alias restore-opencode '~/.local/bin/restore-opencode.sh'
alias check-skills '~/.local/bin/check-skills.sh'

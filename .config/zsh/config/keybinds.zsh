bindkey -e

# Cursor movement
bindkey '^a' beginning-of-line
bindkey '^e' end-of-line

# Editing
bindkey '^w' backward-kill-word
bindkey '^u' backward-kill-line
bindkey '^_' undo
# Forward Delete sends CSI 3~; without this bind the trailing ~ is inserted.
bindkey '^[[3~' delete-char

# History search
bindkey '^[[A' history-beginning-search-backward
bindkey '^[[B' history-beginning-search-forward

# Character movement
bindkey '^b' backward-char
bindkey '^f' forward-char

# History substring search
bindkey '^p' history-substring-search-up
bindkey '^n' history-substring-search-down

# Shortcuts
bindkey -s '^G' 'tmux-sessionizer'

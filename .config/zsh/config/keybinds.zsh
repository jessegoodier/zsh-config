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

# History search: move within a multi-line buffer, otherwise search by prefix
# (plain history-beginning-search-* can flatten multi-line events to one line).
autoload -Uz up-line-or-beginning-search down-line-or-beginning-search
zle -N up-line-or-beginning-search
zle -N down-line-or-beginning-search
bindkey '^[[A' up-line-or-beginning-search
bindkey '^[[B' down-line-or-beginning-search

# Character movement
bindkey '^b' backward-char
bindkey '^f' forward-char

# History substring search
bindkey '^p' history-substring-search-up
bindkey '^n' history-substring-search-down

# Shortcuts
bindkey -s '^G' 'tmux-sessionizer'

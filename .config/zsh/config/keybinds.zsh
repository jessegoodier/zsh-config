bindkey -e

# Cursor movement
bindkey '^a' beginning-of-line
bindkey '^e' end-of-line
# Home/End: macOS terminals often map these; Linux sends CSI/SS3 sequences zsh
# does not bind by default. terminfo when available, plus common fallbacks.
if (( $+terminfo[khome] && $+terminfo[kend] )); then
	bindkey "${terminfo[khome]}" beginning-of-line
	bindkey "${terminfo[kend]}" end-of-line
fi
bindkey '\e[H' beginning-of-line
bindkey '\e[F' end-of-line
bindkey '\e[1~' beginning-of-line
bindkey '\e[4~' end-of-line
bindkey '\eOH' beginning-of-line
bindkey '\eOF' end-of-line

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

# Shared completion behavior (required for fzf-tab; override in the overlay if needed)
setopt COMPLETE_IN_WORD ALWAYS_TO_END AUTO_PARAM_SLASH PATH_DIRS
unsetopt MENU_COMPLETE LIST_BEEP

zstyle ':completion:*:git-checkout:*' sort false
zstyle ':completion:*:descriptions' format '[%d]'
zstyle ':completion:*' list-colors ${(s.:.)LS_COLORS}
zstyle ':completion:*' menu no

# exact -> case/hyphen-insensitive -> separator-aware -> substring
zstyle ':completion:*' matcher-list \
	'' \
	'm:{[:lower:][:upper:]-_}={[:upper:][:lower:]_-}' \
	'r:|[._-]=* r:|=*' \
	'l:|=* r:|=*'

zstyle ':completion:*' completer _complete _ignored
zstyle ':completion:*' accept-exact '*(N)'
zstyle ':completion:*' accept-exact-dirs true
zstyle ':completion:*' squeeze-slashes true
zstyle ':completion:*' list-dirs-first true

# Match Ctrl-R: 50% popup; colors/border/margin come from FZF_DEFAULT_OPTS_FILE.
# fzf-tab appends fzf-flags last, so this overrides its candidate-count height.
zstyle ':fzf-tab:*' fzf-flags --height=${FZF_TMUX_HEIGHT:-50%}

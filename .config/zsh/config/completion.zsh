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

# FZF_DEFAULT_OPTS_FILE still applies (colors). Override layout so a short
# candidate list is not crushed to one row by 90% height + border/margin/padding.
zstyle ':fzf-tab:*' fzf-min-height 10
zstyle ':fzf-tab:*' fzf-flags --height=10 --border=none --margin=0 --padding=0 --no-preview

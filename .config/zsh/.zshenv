# XDG base directories
export XDG_DATA_HOME="$HOME/.local/share"
export XDG_BIN_HOME="$HOME/.local/bin"
export XDG_CACHE_HOME="$HOME/.cache"
export XDG_STATE_HOME="$HOME/.local/state"

# Zsh configuration and plugins directories
export ZSH_CONFIG_DIR="$ZDOTDIR/config"
export ZSH_PLUGIN_DIR="$ZDOTDIR/plugins"
export ZSH_PATINA_PATH="$ZSH_PLUGIN_DIR/zsh-patina/target/release/zsh-patina"

# Tools configuration directories
export CARGO_BIN_HOME="$HOME/.cargo/bin"
export PNPM_HOME="$XDG_DATA_HOME/pnpm/bin/bin/bin"

# ATAC configuration
export ATAC_CONFIG_DIR="$XDG_CONFIG_HOME/atac"
export ATAC_THEME="$ATAC_CONFIG_DIR/themes/postman_theme.toml"
export ATAC_KEY_BINDINGS="$ATAC_CONFIG_DIR/key_binds/vim_key_bindings.toml"

# Disable docker hints
export DOCKER_CLI_HINTS=false

# Keep venv activate from prefixing the prompt with (env-name)
export VIRTUAL_ENV_DISABLE_PROMPT=1

# Default editor and pager
export EDITOR=nvim
export VISUAL=$EDITOR
export PAGER=less
export MANPAGER=$PAGER
export GPG_TTY=$(tty)

# Cursor theme and size
export XCURSOR_THEME=Bibata-Modern-Classic
export XCURSOR_SIZE=22
export GTK_CURSOR_THEME=$XCURSOR_THEME

# path setup
typeset -gU path
path_add() {
	local d
	local -a dirs
	for d in "$@"; do
		[[ -d $d ]] && dirs+=($d)
	done
	(( $#dirs )) && path=($dirs $path)
}

# Prefer Homebrew over /usr/bin (Apple jq, old git, …). Login shells: macOS
# /etc/zprofile path_helper reorders PATH after this file; .zprofile undoes that.
# Linux: /home/linuxbrew/.linuxbrew or ~/.linuxbrew (same paths as installer.sh).
() {
	local p
	for p in /opt/homebrew/bin/brew /usr/local/bin/brew "$HOME/.linuxbrew/bin/brew" /home/linuxbrew/.linuxbrew/bin/brew; do
		if [[ -x $p ]]; then
			eval "$("$p" shellenv)"
			return
		fi
	done
}

# User-local bins stay ahead of brew so $HOME/bin, cargo, etc. can override.
path_add \
	"$XDG_BIN_HOME" \
	"${HOMEBREW_PREFIX:-/opt/homebrew}/opt/rustup/bin" \
	"$PNPM_HOME"

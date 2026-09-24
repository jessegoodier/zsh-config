# Enable zsh hook management
autoload -U add-zsh-hook

# Source plugins
source "$ZDOTDIR/plugins.zsh"

# Load modular configs
local -a configs=(prompt history keybinds completion aliases fzf functions)
for f in $configs; do
	[[ -r "$ZSH_CONFIG_DIR/$f.zsh" ]] && source "$ZSH_CONFIG_DIR/$f.zsh"
done

# Global tools from ~/.venv stay on PATH, but do not `activate` (that sets
# VIRTUAL_ENV and makes uv ignore a project .venv). Prefer the cwd venv when
# present so VS Code/direnv/uv all see the same environment.
if [[ -d $HOME/.venv/bin ]]; then
	path=($HOME/.venv/bin $path)
fi
if [[ -r $PWD/.venv/bin/activate ]]; then
	source "$PWD/.venv/bin/activate"
fi

# Load personal overlay last (optional). Private secrets stay out of git.
[[ -r $ZDOTDIR/personal-config.zsh ]] && source "$ZDOTDIR/personal-config.zsh"
[[ -r $HOME/.zsh-config-private.zsh ]] && source "$HOME/.zsh-config-private.zsh"

# OMZ snippets and cloned plugins are zsh-defer'd, so they load after the
# first functions.zsh source and would win (aliases shadow functions).
# Re-apply after those tasks. Private overlay is not re-sourced here.
zsh-defer -c "[[ -r $ZSH_CONFIG_DIR/functions.zsh ]] && source $ZSH_CONFIG_DIR/functions.zsh"

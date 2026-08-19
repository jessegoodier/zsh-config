# Enable zsh hook management
autoload -U add-zsh-hook

# Source plugins
source "$ZDOTDIR/plugins.zsh"

# Load modular configs
local -a configs=(prompt history keybinds completion aliases fzf functions)
for f in $configs; do
	[[ -r "$ZSH_CONFIG_DIR/$f.zsh" ]] && source "$ZSH_CONFIG_DIR/$f.zsh"
done

[[ -r $HOME/.venv/bin/activate ]] && source "$HOME/.venv/bin/activate"

# Load personal overlay last (optional). Private secrets stay out of git.
[[ -r $ZDOTDIR/personal-config.zsh ]] && source "$ZDOTDIR/personal-config.zsh"
[[ -r $HOME/.zsh-config-private.zsh ]] && source "$HOME/.zsh-config-private.zsh"

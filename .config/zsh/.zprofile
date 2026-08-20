# Login shells only. macOS /etc/zprofile runs path_helper *after* .zshenv and
# puts /usr/bin first, which shadows Homebrew (e.g. Apple jq 1.7 vs brew 1.8).
# Re-source so brew shellenv + path_add run again. Non-login shells skip this.
[[ -r $ZDOTDIR/.zshenv ]] && source "$ZDOTDIR/.zshenv"

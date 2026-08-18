# Personal overlay (sourced last from .zshrc). Opinions live here.

# --- PATH ---
path_add \
	"$HOME/go/bin" \
	"$HOME/bin" \
	/opt/homebrew/opt/grep/libexec/gnubin

# --- Shell options ---
setopt AUTO_CD
alias ...='cd ../..'
alias ....='cd ../../..'

# --- Oh My Zsh snippets (vendored under plugins/oh-my-zsh-plugins; not cloned) ---
# lib/git.zsh helper used by git.plugin.zsh
git_current_branch() {
	local ref ret
	ref=$(command git symbolic-ref --quiet HEAD 2>/dev/null)
	ret=$?
	if [[ $ret != 0 ]]; then
		[[ $ret == 128 ]] && return
		ref=$(command git rev-parse --short HEAD 2>/dev/null) || return
	fi
	print -r -- ${ref#refs/heads/}
}

# lib/functions.zsh helper used by macos.plugin.zsh
(( $+functions[open_command] )) || open_command() { command open "$@" }

_omz_plugins="$ZSH_PLUGIN_DIR/oh-my-zsh-plugins"
# Defer alias packs so first prompt stays fast.
# git.plugin.zsh uses `local` at top level; source it in a function so that is legal.
zsh-defer -c "
[[ -r $_omz_plugins/git.plugin.zsh ]] && () { source $_omz_plugins/git.plugin.zsh }
[[ -r $_omz_plugins/kubectl.plugin.zsh ]] && source $_omz_plugins/kubectl.plugin.zsh
[[ \"$OSTYPE\" == darwin* && -r $_omz_plugins/macos.plugin.zsh ]] && source $_omz_plugins/macos.plugin.zsh
"
unset _omz_plugins

# --- Editor & aliases ---
export EDITOR='vim'
export VISUAL='vim'
alias vi='vim'
alias curl='noglob curl'

# --- fzf (search command only; theme/layout live in $XDG_CONFIG_HOME/fzf/config) ---
export FZF_DEFAULT_COMMAND='fd --type f --strip-cwd-prefix --hidden --exclude .git'
export FZF_CTRL_T_COMMAND="$FZF_DEFAULT_COMMAND"

# After zsh-autosuggestions loads (it is deferred)
zsh-defer -a bindkey '^[[Z' autosuggest-accept

if (( $+commands[kubecolor] )); then
	alias kubectl="kubecolor"
	compdef _kubectl kubecolor
	alias watch='KUBECOLOR_FORCE_COLORS=true watch --color '
fi

# Optional prompt prefix: kube context/namespace in front of PATH_INFO.
# Cached on kubeconfig mtime; first prompt stays fast, then this fills in.
typeset -g _KUBE_PROMPT_MTIME= _KUBE_PROMPT_READY=0
_kube_mtime() {
	if [[ "$OSTYPE" == darwin* ]]; then
		stat -L -f %m -- "$1" 2>/dev/null
	else
		stat -L -c %Y -- "$1" 2>/dev/null
	fi
}
_kube_prompt() {
	emulate -L zsh
	(( _KUBE_PROMPT_READY )) || return
	(( $+commands[kubectl] )) || { KUBE_INFO=; return }

	local kubeconfig=${KUBECONFIG:-$HOME/.kube/config} cfg now=
	local -a files=(${(s.:.)kubeconfig})
	for cfg in $files; do
		[[ -r $cfg ]] || continue
		now+=${now:+|}$(_kube_mtime "$cfg")
	done
	if [[ -z $now ]]; then
		KUBE_INFO=
		_KUBE_PROMPT_MTIME=
		return
	fi
	[[ $now == $_KUBE_PROMPT_MTIME ]] && return
	_KUBE_PROMPT_MTIME=$now

	local out ctx ns
	out=$(command kubectl config view --minify -o jsonpath='{.current-context}/{.contexts[0].context.namespace}' 2>/dev/null) || {
		KUBE_INFO=
		return
	}
	ctx=${out%%/*}
	ns=${out#*/}
	[[ -z $ns ]] && ns=default
	[[ -n $ctx ]] && KUBE_INFO="%F{cyan}${ctx}/${ns}%f " || KUBE_INFO=
}
add-zsh-hook precmd _kube_prompt
zsh-defer -c '_KUBE_PROMPT_READY=1; _kube_prompt; zle && zle reset-prompt'

# --- Functions ---
password_gen() {
	local str
	while true; do
		str=$(LC_ALL=C tr -dc 'a-zA-Z0-9_' < /dev/urandom | head -c 16)
		if [[ "$str" == *_* && "$str" != _* && "$str" != *_ ]]; then
			echo "$str"
			break
		fi
	done
}

# --- Extra files (last so they can override) ---
[[ -f ~/.keys ]] && source ~/.keys

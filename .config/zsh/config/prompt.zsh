# The prompt answers four questions:
#   1. Where am I?                           → PATH_INFO
#   2. What Git context am I in?             → GIT_INFO (branch/tag/HEAD)
#   3. Is the repo in a notable state?       → 󰁅pull 󰁝push and 󰐕󰏫󰝒 counts
#   4. Did my last command fail / take long? → CMD_STATUS + CMD_DURATION
#
# Overlay may set KUBE_INFO as an optional prefix; the core leaves it empty.
#
typeset -g PATH_INFO GIT_INFO KUBE_INFO CMD_STATUS CMD_DURATION
typeset -g _LAST_PWD
typeset -g _GITSTATUS_READY=0
typeset -g _PROMPT_START_TIME
setopt PROMPT_SUBST

# Start the daemon only once, after the shell is interactive
zsh-defer -c '
gitstatus_start -s -1 -u -1 -c -1 -d -1 -e "MY_PROMPT"
_GITSTATUS_READY=1
# Fire the first query asynchronously (no blocking)
gitstatus_query -t 0 -c _gitstatus_async_update "MY_PROMPT"
'

# Git prompt
# Example: 󰘬 main 󰁅3 󰁝2 [merge 󰀦1 󰀼2 󰐕4 󰏫5 󰝒1]
# main ⇡2 ⇣1
git_prompt() {
	emulate -L zsh
	[[ $VCS_STATUS_RESULT == ok-* ]] || return

	local ref
	if [[ -n $VCS_STATUS_LOCAL_BRANCH ]]; then
		ref=$VCS_STATUS_LOCAL_BRANCH
	elif [[ -n $VCS_STATUS_TAG ]]; then
		ref="#$VCS_STATUS_TAG"
	else
		ref="@${VCS_STATUS_COMMIT[1,7]}"
	fi
	(( $#ref > 32 )) && ref[13,-13]="…"

	local p="%F{green}󰘬 ${ref//\%/%%}%f"
	(( VCS_STATUS_COMMITS_BEHIND )) && p+=" %F{cyan}⇡${VCS_STATUS_COMMITS_BEHIND}%f"
	(( VCS_STATUS_COMMITS_AHEAD )) && p+=" %F{yellow}⇣${VCS_STATUS_COMMITS_AHEAD}%f"
	(( VCS_STATUS_PUSH_COMMITS_BEHIND )) && p+=" %F{cyan}⇠${VCS_STATUS_PUSH_COMMITS_BEHIND}%f"
	(( VCS_STATUS_PUSH_COMMITS_AHEAD )) && p+=" %F{yellow}⇢${VCS_STATUS_PUSH_COMMITS_AHEAD}%f"

	local -a segments
	[[ -n $VCS_STATUS_ACTION ]] && segments+=("action${VCS_STATUS_ACTION}")
	(( VCS_STATUS_NUM_CONFLICTED )) && segments+=("⇠conflicts${VCS_STATUS_NUM_CONFLICTED}")
	(( VCS_STATUS_STASHES )) && segments+=("⇣stashes${VCS_STATUS_STASHES}")
	(( VCS_STATUS_NUM_STAGED )) && segments+=("⇡staged${VCS_STATUS_NUM_STAGED}")
	(( VCS_STATUS_NUM_UNSTAGED )) && segments+=("⇣unstaged${VCS_STATUS_NUM_UNSTAGED}")
	(( VCS_STATUS_NUM_UNTRACKED )) && segments+=("⇡untracked${VCS_STATUS_NUM_UNTRACKED}")
	(( $#segments )) && p+=" %B%F{red}[${(j. .)segments}]%f%b"

	print -rn -- "$p"
}

_refresh_path_info() {
	# Only recalculate when something actually changed
	if [[ $PWD != ${_LAST_PWD-} ]]; then
		PATH_INFO=$(path_prompt)
		_LAST_PWD=$PWD
	fi
}

# Full path, replacing $HOME with ~
path_prompt() {
	print -rn -- "${(%):-%~}"
}

# Called by gitstatus when the async result arrives
_gitstatus_async_update() {
	GIT_INFO=$(git_prompt)
	_refresh_path_info
	# Only redraw if something visible changed
	[[ $GIT_INFO != $old_git || $PATH_INFO != ${_LAST_PATH_INFO-} ]] && zle && zle reset-prompt
	_LAST_PATH_INFO=$PATH_INFO
}

preexec() {
	_PROMPT_START_TIME=$SECONDS
}

precmd() {
	local st=$?
	CMD_STATUS=${${st:#0}:+%F{red}➜%f}
	CMD_STATUS=${CMD_STATUS:-%F{magenta}➜%f}

	# Duration
	CMD_DURATION=
	if (( ${+_PROMPT_START_TIME} )); then
		local -i sec=$(( SECONDS - _PROMPT_START_TIME ))
		unset _PROMPT_START_TIME

		if (( sec >= 2 )); then
			if (( sec >= 60 )); then
				local -i m=$(( sec / 60 ))
				local -i s=$(( sec % 60 ))
				CMD_DURATION="%F{yellow}${m}m${s}s%f"
			else
				CMD_DURATION="%F{yellow}${sec}s%f"
			fi
		fi
	fi

	# Pure async – never blocks the prompt
	if (( _GITSTATUS_READY )); then
		gitstatus_query -t 0 -c _gitstatus_async_update 'MY_PROMPT'
	fi

	# path updates on PWD or worktree change
	_refresh_path_info
}

PROMPT=$'\n${KUBE_INFO}%B%F{blue}${PATH_INFO}%f%b ${GIT_INFO}\n${CMD_STATUS} '
RPROMPT='${CMD_DURATION}'

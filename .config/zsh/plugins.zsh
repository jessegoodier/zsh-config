# Clone a plugin on first use (if missing)
plugin-path() {
	emulate -L zsh

	# Validate arguments
	(($# >= 2)) || {
		print -u2 -P "%F{red}usage: plugin-path <owner> <repo> %f"
		return 1
	}

	local owner=$1
	local repo=$2
	local dir="$ZSH_PLUGIN_DIR/$repo"

	# Clone the plugin if it's not installed
	if [[ ! -d "$dir" ]]; then
		mkdir -p "$ZSH_PLUGIN_DIR" || return 1
		print -u2 -P "→ ${(r:29:)repo} %F{cyan}installing...%f"

		if ! git clone --depth=1 --quiet \
			"https://github.com/$owner/$repo" "$dir"; then
			rm -rf "$dir"
			print -u2 -P "→ ${(r:29:)repo} %F{red}✗ clone failed%f"
			return 1
		fi
		print -u2 -P "→ ${(r:29:)repo} %F{green}✓ installed%f"
	fi

	# Prefer the conventional entry points
	local entry
	for entry in \
		"$dir/$repo.plugin.zsh" \
		"$dir"/*.plugin.zsh(N) \
		"$dir/$repo.zsh"; do
		[[ -r $entry ]] && {
			print -r -- $entry
			return 0
		}
	done

	# Last resort: only if there is exactly one *.zsh in the root
	local -a candidates=("$dir"/*.zsh(N))
	if (( $#candidates == 1 )) && [[ -r $candidates[1] ]]; then
		print -r -- $candidates[1]
		return 0
	fi

	print -u2 -P "→ ${(r:29:)repo} %F{red}✗ missing plugin entry%f ($dir)"
	return 1
}

# Install (and build if needed) + activate zsh-patina
# A fast syntax highlighter written in Rust
load-zsh-patina() {
	emulate -L zsh
	local name=zsh-patina
	local dir="$ZSH_PLUGIN_DIR/$name"

	# Clone on first use
	if [[ ! -d "$dir" ]]; then
		print -u2 -P "→ ${(r:29:)name} %F{cyan}installing...%f"
		if ! git clone --depth=1 --quiet \
			https://github.com/michel-kraemer/zsh-patina.git "$dir"; then
			rm -rf "$dir"
			print -u2 -P "→ ${(r:29:)name} %F{red}✗ clone failed%f"
			return 1
		fi
		print -u2 -P "→ ${(r:29:)name} %F{green}✓ installed%f"
	fi

	# Build the binary if it is missing
	if [[ ! -x $ZSH_PATINA_PATH ]]; then
		if ! (( $+commands[cargo] )); then
			print -u2 -P "→ ${(r:29:)name} %F{yellow}⚠ cargo is missing%f"
			print -u2 -P "  Install Rust from https://rustup.rs and then run:"
			print -u2 -P "  (cd $dir && cargo build --release)"
			return 1
		fi

		print -u2 -P "→ ${(r:29:)name} %F{cyan}building...%f"
		if ! (cd "$dir" && env -u CARGO_TARGET_DIR cargo build --release --quiet); then
			print -u2 -P "→ ${(r:29:)name} %F{red}✗ build failed%f"
			return 1
		fi
		print -u2 -P "→ ${(r:29:)name} %F{green}✓ built%f"
	fi

	# Final sanity check
	if [[ ! -x $ZSH_PATINA_PATH ]]; then
		print -u2 -P "→ ${(r:29:)name} %F{red}✗ binary not found at $ZSH_PATINA_PATH%f"
		return 1
	fi

	# Activate only once (safe to call multiple times)
	if ! typeset -f _zsh_patina_activate >/dev/null 2>&1; then
		_zsh_patina_activate() {
			unfunction _zsh_patina_activate
			add-zsh-hook -d precmd _zsh_patina_activate
			eval "$("$ZSH_PATINA_PATH" activate)"
		}
		add-zsh-hook precmd _zsh_patina_activate
	fi
}

# Update all installed plugin repositories in parallel
update-plugin() {
	emulate -L zsh
	setopt localoptions nomonitor

	local -a plugins=("$ZSH_PLUGIN_DIR"/*(/N))
	(( $#plugins )) || {
		print -P "%F{yellow}No plugins found in $ZSH_PLUGIN_DIR%f"
		return 0
	}

	print -P "%F{cyan}Updating ${#plugins} plugins...%f"

	local dir name
	for dir in $plugins; do
		[[ -d "$dir/.git" ]] || continue
		name=${dir:t}

		(
			local old new
			old=$(git -C "$dir" rev-parse HEAD 2>/dev/null) || {
				print -P "⎔ ${(r:29:)name} %F{red}✗ not a valid git repo%f"
				exit 1
			}

			if ! git -C "$dir" fetch --depth=1 --quiet origin 2>/dev/null; then
				print -P "⎔ ${(r:29:)name} %F{red}✗ fetch failed%f"
				exit 1
			fi

			# Prefer clean fast-forward, fall back to hard reset
			if ! git -C "$dir" merge --ff-only --quiet FETCH_HEAD 2>/dev/null &&
				! git -C "$dir" reset --hard --quiet FETCH_HEAD 2>/dev/null; then
				print -P "⎔ ${(r:29:)name} %F{red}✗ update failed%f"
				exit 1
			fi

			new=$(git -C "$dir" rev-parse HEAD)
			if [[ $old == $new ]]; then
				print -P "⎔ ${(r:29:)name} %F{8}○ already up to date%f"
			elif [[ $name != zsh-patina ]]; then
				print -P "⎔ ${(r:29:)name} %F{green}✓ updated%f"
			elif ! (( $+commands[cargo] )); then
				print -P "⎔ ${(r:29:)name} %F{yellow}⚠ updated, but cargo is missing%f"
			elif (cd "$dir" && env -u CARGO_TARGET_DIR cargo build --release --quiet); then
				print -P "⎔ ${(r:29:)name} %F{green}✓ updated & rebuilt%f"
			else
				print -P "⎔ ${(r:29:)name} %F{yellow}⚠ updated, but rebuild failed%f"
			fi
		) &
	done
	wait

	print -P "%F{green}Done.%f"
}

# Install every plugin now
plugin-path romkatv gitstatus                       >/dev/null
plugin-path romkatv zsh-defer                       >/dev/null
plugin-path mattmc3 ez-compinit                     >/dev/null
plugin-path zsh-users zsh-completions               >/dev/null
plugin-path aloxaf fzf-tab                          >/dev/null
plugin-path zsh-users zsh-autosuggestions           >/dev/null
plugin-path zsh-users zsh-history-substring-search  >/dev/null
plugin-path houssamouhra colored-man-pages          >/dev/null

# Ensure zsh-patina is cloned + built early (so the binary is ready)
load-zsh-patina >/dev/null

# Load the critical ones immediately
source "$(plugin-path romkatv gitstatus)"
source "$(plugin-path romkatv zsh-defer)"

# Completions must exist before anything calls `compdef` (personal-config, OMZ snippets)
# Stock /bin/zsh omits Apple Silicon Homebrew; without this, `compdef _kubectl …`
# autoloads a function whose file is never on fpath.
typeset -gU fpath
fpath=(${HOMEBREW_PREFIX:-/opt/homebrew}/share/zsh/site-functions(/N) $fpath)
zstyle ':plugin:ez-compinit' 'use-cache' yes
source "$(plugin-path mattmc3 ez-compinit)"
source "$(plugin-path zsh-users zsh-completions)"
# keybinds.zsh binds Up/Down to these widgets; load before config modules run.
source "$(plugin-path zsh-users zsh-history-substring-search)"

# One deferred task: avoid five precmd + reset-prompt cycles
zsh-defer -c "
source \"$(plugin-path aloxaf fzf-tab)\"
source \"$(plugin-path zsh-users zsh-autosuggestions)\"
source \"$(plugin-path houssamouhra colored-man-pages)\"
load-zsh-patina
"

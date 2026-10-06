#!/usr/bin/env zsh
# See README-installer.md
emulate -R zsh
set -euo pipefail
setopt EXTENDED_GLOB

# FUNCTION_ARGZERO (on by default) sets $0 to this file when it is sourced,
# so comparing $0 to "zsh" does not catch `source installer.sh`.
if [[ $ZSH_EVAL_CONTEXT == *file* ]]; then
	print -u2 "Run this script; do not source it. See README-installer.md."
	return 1
fi

REPO_ROOT="${0:A:h}"
SCRIPT_NAME="${0:t}"

# --- configuration ---

# command:formula pairs checked before linking.
TOOLS=(git:git fzf:fzf eza:eza bat:bat fd:fd cargo:rust uv:uv)
# Files zsh stops reading once ZDOTDIR is set. Copied, not moved.
SHADOWED=(.zprofile .zlogin .zlogout)
# Plugins are listed as `plugin-path <owner> <repo>` lines in plugins.zsh;
# zsh-patina is loaded separately there and needs a cargo build.
PLUGINS_FILE="$REPO_ROOT/.config/zsh/plugins.zsh"
PLUGIN_DIR="$REPO_ROOT/.config/zsh/plugins"
PATINA=(michel-kraemer zsh-patina)
# Repo paths linked into $HOME alongside the Python venv.
PYTHON_LINKS=(pyproject.toml .envrc src)
BREW_PATHS=(/opt/homebrew/bin/brew /usr/local/bin/brew "$HOME/.linuxbrew/bin/brew" /home/linuxbrew/.linuxbrew/bin/brew)
ITERM_DOMAIN=com.googlecode.iterm2
ITERM_PROFILE="$REPO_ROOT/iterm2/zsh-config.json"
ITERM_PROFILE_DEST="$HOME/Library/Application Support/iTerm2/DynamicProfiles/zsh-config.json"
# Earlier versions pointed iTerm2's custom settings folder here.
ITERM_OLD_FOLDER="$HOME/.config/iterm2-settings"

# --- state ---

DRY_RUN=0
# Optional steps: ask, yes, or no. Set by --<step> / --no-<step>.
typeset -A MODE=(brew ask iterm ask history ask python ask)
BACKUP_DIR=""
DID_WORK=0
REPORTED_FAILURE=0
typeset -a MANIFEST=()

# --- helpers ---

usage() {
	print "Usage: $SCRIPT_NAME [--dry-run] [--python|--no-python] [--brew|--no-brew] [--history|--no-history] [--iterm|--no-iterm] [--help]"
	print "See README-installer.md for details."
}

# True for files, directories, and symlinks (including dangling ones).
exists() { [[ -e $1 || -L $1 ]] }

# Run a command, or skip it under --dry-run. Callers record() what it did.
run() { (( DRY_RUN )) || "$@" }

# Like run, but say what is being run. For commands that record() nothing.
run_loud() {
	local verb=Running
	(( DRY_RUN )) && verb="Would run"
	print -r -- "$verb: ${(j: :)${(q-)@}}"
	run "$@"
}

append_file() { cat -- "$1" >>"$2" }

record() {
	local line="$1  $2"
	MANIFEST+=("$line")
	print -r -- "$line"
}

# confirm <step> <prompt>: honor --<step>/--no-<step>, otherwise ask.
confirm() {
	local step=$1 prompt=$2 reply
	case ${MODE[$step]} in
		yes) return 0 ;;
		no) return 1 ;;
	esac
	if (( DRY_RUN )); then
		print "Would prompt: $prompt"
		print "  (pass --$step to include this in a dry-run)"
		return 1
	fi
	if [[ ! -t 0 ]]; then
		print "stdin is not a TTY; skipping (pass --$step to proceed)."
		return 1
	fi
	print -n "$prompt [y/N] "
	read -r reply || true
	[[ $reply == (#i)y(es|) ]]
}

ensure_backup_dir() {
	[[ -n $BACKUP_DIR ]] && return
	BACKUP_DIR="$REPO_ROOT/backups/$(date +%Y-%m-%d_%H%M%S)"
	exists $BACKUP_DIR && BACKUP_DIR="${BACKUP_DIR}_$$"
	(( DRY_RUN )) && print "Would create $BACKUP_DIR"
	run mkdir -p "$BACKUP_DIR"
}

# Copy path into the backup dir, keeping its location relative to $HOME.
backup_copy() {
	local src=$1 dest
	ensure_backup_dir
	dest="$BACKUP_DIR/${src#$HOME/}"
	run mkdir -p "${dest:h}"
	run cp -a -- "$src" "$dest"
	record COPIED "$src -> $dest"
}

already_linked() {
	local src=$1 dest=$2 target
	[[ -L $dest ]] || return 1
	# ${dest:A} does not follow a dangling symlink (it stays on dest), so
	# compare the link text. That keeps a re-run from moving ~/.venv when
	# the clone environment has not been created yet.
	target=$(readlink "$dest") || return 1
	[[ $target == /* ]] || target="${dest:h}/$target"
	[[ ${target:A} == ${src:A} ]]
}

# Symlink dest -> src, moving anything already at dest into the backup dir.
install_pair() {
	local src=${1:A} dest=$2
	if already_linked "$src" "$dest"; then
		record SKIPPED "$dest -> $src (already linked)"
		return
	fi
	if exists $dest; then
		ensure_backup_dir
		local bdest="$BACKUP_DIR/${dest#$HOME/}"
		run mkdir -p "${bdest:h}"
		run mv -- "$dest" "$bdest"
		record MOVED "$dest -> $bdest"
	fi
	run mkdir -p "${dest:h}"
	run ln -s -- "$src" "$dest"
	record LINKED "$dest -> $src"
	DID_WORK=1
}

report_failure() {
	local -i code=$1
	# ZERR and EXIT can both run for one failure. Say this once.
	(( REPORTED_FAILURE )) && return 0
	REPORTED_FAILURE=1
	# set -e inside a function exits the shell without running the EXIT trap.
	# ZERR still runs, which is what prints this for a failed mv/ln/export.
	if (( code != 0 && ! DRY_RUN )) && [[ -n $BACKUP_DIR && -d $BACKUP_DIR ]]; then
		print -u2 "Install failed. Your files are in $BACKUP_DIR"
	fi
}

# --- steps ---

resolve_brew() {
	(( $+commands[brew] )) && return 0
	local p
	for p in $BREW_PATHS; do
		if [[ -x $p ]]; then
			eval "$("$p" shellenv)"
			rehash
			return 0
		fi
	done
	return 1
}

# Sets missing_cmds and missing_formulae in the caller's scope.
collect_missing_tools() {
	missing_cmds=() missing_formulae=()
	local spec
	for spec in $TOOLS; do
		(( $+commands[${spec%%:*}] )) && continue
		missing_cmds+=(${spec%%:*})
		missing_formulae+=(${spec#*:})
	done
	missing_formulae=(${(u)missing_formulae})
}

install_homebrew() {
	if (( DRY_RUN )); then
		print "Would install Homebrew from https://brew.sh"
		return 0
	fi
	print "Installing Homebrew..."
	local script
	script=$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)
	if [[ ${MODE[brew]} == yes ]]; then
		NONINTERACTIVE=1 /bin/bash -c "$script"
	else
		/bin/bash -c "$script"
	fi
	resolve_brew || {
		print -u2 "Homebrew installed but brew is not on PATH yet. Open a new terminal or eval brew shellenv."
		return 1
	}
}

offer_brew_packages() {
	local have_brew=0 prompt
	local -a missing_cmds missing_formulae
	resolve_brew && have_brew=1
	collect_missing_tools
	(( $#missing_cmds )) || return 0

	print "Missing tools: ${(j:, :)missing_cmds}"
	print "Homebrew formulae: ${(j:, :)missing_formulae}"
	if (( have_brew )); then
		prompt="Install missing tools with Homebrew?"
	else
		print "Homebrew is not installed. See https://brew.sh"
		prompt="Install Homebrew and the missing tools?"
	fi
	if ! confirm brew "$prompt"; then
		print -u2 "Warning: missing tools (install still continues): ${(j:, :)missing_cmds}"
		return 0
	fi

	if (( ! have_brew )) && ! install_homebrew; then
		print -u2 "Warning: Homebrew install failed; skipping packages."
		return 0
	fi

	run_loud brew install --formula $missing_formulae || print -u2 "Warning: brew install failed; continuing."
	(( DRY_RUN )) && return 0
	rehash
	collect_missing_tools
	(( $#missing_cmds )) && print -u2 "Still missing after brew: ${(j:, :)missing_cmds}"
	return 0
}

link_dotfiles() {
	local src
	install_pair "$REPO_ROOT/.zshenv" "$HOME/.zshenv"
	for src in "$REPO_ROOT"/.config/*(N); do
		install_pair "$src" "$HOME/.config/${src:t}"
	done
	install_pair "$REPO_ROOT/.config/zsh/.zshrc" "$HOME/.zshrc"
}

# Clone missing zsh plugins now instead of on the first shell start. Same
# repos and layout as plugin-path in plugins.zsh. Failures only warn: zsh
# retries on first launch.
install_plugins() {
	if ! (( $+commands[git] )); then
		print -u2 "Warning: git is not installed; zsh will clone plugins on first launch."
		return 0
	fi
	local -a specs
	local line
	for line in ${(f)"$(<$PLUGINS_FILE)"}; do
		[[ $line == (#b)plugin-path[[:space:]]##([^[:space:]]##)[[:space:]]##([^[:space:]]##)* ]] &&
			specs+=("$match[1]/$match[2]")
	done
	specs=(${(u)specs} ${(j:/:)PATINA})

	print "Plugins: $PLUGIN_DIR"
	local spec name dir
	for spec in $specs; do
		name=${spec:t} dir="$PLUGIN_DIR/${spec:t}"
		if [[ -d $dir ]]; then
			print "  OK      $name"
		elif (( DRY_RUN )); then
			print "  Would clone https://github.com/$spec"
		elif run mkdir -p "$PLUGIN_DIR" && git clone --depth=1 --quiet "https://github.com/$spec" "$dir"; then
			print "  CLONED  $name"
		else
			rm -rf -- "$dir"
			print -u2 "  Warning: could not clone $spec; zsh will retry on first launch."
		fi
	done
	build_patina
}

build_patina() {
	local dir="$PLUGIN_DIR/$PATINA[2]"
	[[ -x $dir/target/release/zsh-patina ]] && return 0
	[[ -d $dir ]] || (( DRY_RUN )) || return 0
	if ! (( $+commands[cargo] )); then
		print -u2 "  Warning: cargo is not installed; zsh-patina is not built (see https://rustup.rs)."
		return 0
	fi
	if (( DRY_RUN )); then
		print "  Would run: cargo build --release in $dir"
		return 0
	fi
	# Compiler warnings are noise on success; show the output only on failure.
	local out
	print "  Building zsh-patina (cargo build --release)..."
	if out=$(env -u CARGO_TARGET_DIR cargo build --release --quiet --manifest-path "$dir/Cargo.toml" 2>&1); then
		print "  BUILT   zsh-patina"
	else
		print -u2 -r -- "$out"
		print -u2 "  Warning: zsh-patina build failed; run: (cd $dir && cargo build --release)"
	fi
	return 0
}

# Link the zsh-config profile as an iTerm2 Dynamic Profile. iTerm2 loads it
# live and never writes it back, so the repo copy only changes when you
# re-export it on purpose. Other iTerm2 preferences are left alone.
install_iterm_profile() {
	[[ $(uname -s) == Darwin ]] || return 0
	migrate_iterm_folder
	confirm iterm "Install the zsh-config iTerm2 profile?" || return 0
	install_pair "$ITERM_PROFILE" "$ITERM_PROFILE_DEST"
	print "iTerm2: select the zsh-config profile, or make it the default in Settings > Profiles."
}

# Undo the old custom-folder setup: drop the dangling ~/.config link and warn
# if iTerm2 still loads from it. The setting itself is changed in iTerm2,
# because a running iTerm2 overwrites defaults writes when it quits.
migrate_iterm_folder() {
	if [[ -L $ITERM_OLD_FOLDER && ! -e $ITERM_OLD_FOLDER ]] && already_linked "$REPO_ROOT/.config/iterm2-settings" "$ITERM_OLD_FOLDER"; then
		run rm -- "$ITERM_OLD_FOLDER"
		record REMOVED "$ITERM_OLD_FOLDER (no longer in this repo)"
	fi
	if [[ $(iterm_pref LoadPrefsFromCustomFolder 0) == 1 && $(iterm_pref PrefsCustomFolder "") == "$ITERM_OLD_FOLDER" ]]; then
		print -u2 "Warning: iTerm2 still loads settings from $ITERM_OLD_FOLDER. This repo now ships a Dynamic Profile instead."
		print -u2 "  In iTerm2 Settings > General > Settings, turn off \"Load settings from a custom folder or URL\", then quit iTerm2 (Cmd-Q)."
	fi
	return 0
}

# iterm_pref <key> <default>
iterm_pref() { defaults read $ITERM_DOMAIN $1 2>/dev/null || print -r -- $2 }

snapshot_shadowed() {
	(( DID_WORK )) || return 0
	local name
	for name in $SHADOWED; do
		exists $HOME/$name && backup_copy "$HOME/$name"
	done
	return 0
}

import_zsh_history() {
	local old="$HOME/.zsh_history" new="$HOME/.cache/zsh/history"

	if ! exists $old; then
		print "No $old to import."
		return 0
	fi
	# Same path, symlink, or hardlink. Appending a file onto itself would
	# duplicate every line in the only copy.
	if exists $new && [[ $old -ef $new || ${old:A} == ${new:A} ]]; then
		print "History is already at $new; nothing to import."
		return 0
	fi
	confirm history "Import $old into $new?" || return 0

	backup_copy "$old"
	run mkdir -p "${new:h}"
	if exists $new; then
		backup_copy "$new"
		run append_file "$old" "$new"
	else
		run cp -a -- "$old" "$new"
	fi
	record IMPORTED "$old -> $new"
	(( DRY_RUN )) && return 0
	chmod 600 "$new" 2>/dev/null || true
	print "History imported into $new"
}

install_python_venv() {
	confirm python "Install Python venv from pyproject.toml and link ~/.venv?" || return 0
	if ! (( $+commands[uv] )); then
		print -u2 "uv is not installed; skipping Python venv. See https://docs.astral.sh/uv/"
		return 0
	fi
	if [[ ! -e $REPO_ROOT/pyproject.toml ]]; then
		print -u2 "No pyproject.toml in $REPO_ROOT; skipping Python venv."
		return 0
	fi
	# A parent uv workspace (for example ~/pyproject.toml) puts the environment
	# at the workspace root, which is ~/.venv. That collides with the symlink
	# this installer creates: the next run tries to mkdir ~/.venv and fails
	# with "File exists". Pin the environment to this clone so re-runs update
	# it in place, then link ~/.venv at that directory.
	local venv="$REPO_ROOT/.venv" name
	run_loud env -u VIRTUAL_ENV UV_PROJECT_ENVIRONMENT="$venv" uv --directory "$REPO_ROOT" sync
	install_pair "$venv" "$HOME/.venv"
	for name in $PYTHON_LINKS; do
		install_pair "$REPO_ROOT/$name" "$HOME/$name"
	done
}

write_manifest() {
	(( ! DRY_RUN )) && [[ -n $BACKUP_DIR && -d $BACKUP_DIR ]] || return 0
	print -rl -- "# installer backup ${BACKUP_DIR:t}" "# $(date '+%Y-%m-%d %H:%M:%S')" $MANIFEST \
		>"$BACKUP_DIR/MANIFEST.txt"
}

print_summary() {
	print
	if [[ -z $BACKUP_DIR ]]; then
		print "No files needed backing up."
	elif (( DRY_RUN )); then
		print "Would write MANIFEST.txt in $BACKUP_DIR"
	else
		print "Backup: $BACKUP_DIR"
	fi

	if (( DID_WORK )); then
		print
		print "Next: open a new terminal (do not source this session)."
		print "  echo \$ZDOTDIR    # should be ~/.config/zsh"
		print "If zsh is not your login shell: chsh -s \$(command -v zsh)"
	else
		print "Already installed; nothing to link."
	fi
}

# --- main ---

while (( $# )); do
	case $1 in
		-h | --help) usage; exit 0 ;;
		--dry-run) DRY_RUN=1 ;;
		--no-(brew|iterm|history|python)) MODE[${1#--no-}]=no ;;
		--(brew|iterm|history|python)) MODE[${1#--}]=yes ;;
		*)
			print -u2 "Unknown option: $1"
			usage
			exit 1
			;;
	esac
	shift
done

trap 'report_failure $?' EXIT ZERR

if [[ ! -e $REPO_ROOT/.zshenv || ! -d $REPO_ROOT/.config ]]; then
	print -u2 "Cannot find repo files under $REPO_ROOT"
	exit 1
fi

if [[ ${EUID:-$(id -u)} -eq 0 ]]; then
	print -u2 "Warning: running as root. Prefer installing as your normal user."
fi

offer_brew_packages

print "Repo:  $REPO_ROOT"
print "Home:  $HOME"
(( DRY_RUN )) && print "Mode:  dry-run"
print

link_dotfiles
install_plugins
install_iterm_profile
snapshot_shadowed
import_zsh_history
install_python_venv
write_manifest
print_summary

#!/usr/bin/env zsh
# See README-installer.md
emulate -R zsh
set -euo pipefail
setopt EXTENDED_GLOB

if [[ $0 == -* || ${0:t} == zsh ]]; then
	print -u2 "Run this script; do not source it. See README-installer.md."
	return 1 2>/dev/null || exit 1
fi

REPO_ROOT="${0:A:h}"
SCRIPT_NAME="${0:t}"
DRY_RUN=0
PYTHON_MODE=ask
BREW_MODE=ask
HISTORY_MODE=ask
BACKUP_DIR=""
DID_WORK=0
typeset -a MANIFEST=()
typeset -a MISSING_CMDS=()
typeset -a MISSING_FORMULAE=()

usage() {
	print "Usage: $SCRIPT_NAME [--dry-run] [--python|--no-python] [--brew|--no-brew] [--history|--no-history] [--help]"
	print "See README-installer.md for details."
}

already_linked() {
	local src=$1 dest=$2
	[[ -L $dest ]] || return 1
	[[ "${dest:A}" == "${src:A}" ]]
}

record() {
	local line="$1  $2"
	MANIFEST+=("$line")
	print -r -- "$line"
}

ensure_backup_dir() {
	[[ -n $BACKUP_DIR ]] && return
	local stamp
	stamp=$(date +%Y-%m-%d_%H%M%S)
	BACKUP_DIR="$REPO_ROOT/backups/$stamp"
	[[ -e $BACKUP_DIR ]] && BACKUP_DIR="${BACKUP_DIR}_$$"
	if (( DRY_RUN )); then
		print "Would create $BACKUP_DIR"
		return
	fi
	mkdir -p "$BACKUP_DIR"
}

install_pair() {
	local src=$1 dest=$2
	if already_linked "$src" "$dest"; then
		record SKIPPED "$dest (already linked)"
		return
	fi

	if [[ -e $dest || -L $dest ]]; then
		ensure_backup_dir
		local bdest="$BACKUP_DIR/${dest#$HOME/}"
		if (( ! DRY_RUN )); then
			mkdir -p "${bdest:h}"
			mv -- "$dest" "$bdest"
		fi
		record MOVED "$dest -> $bdest"
	fi

	if (( ! DRY_RUN )); then
		mkdir -p "${dest:h}"
		ln -s -- "${src:A}" "$dest"
	fi
	record LINKED "$dest -> ${src:A}"
	DID_WORK=1
}

snapshot_shadowed() {
	(( DID_WORK )) || return 0
	local -a names=(.zshrc .zprofile .zlogin .zlogout)
	local name dest bdest any=0
	for name in $names; do
		dest="$HOME/$name"
		if [[ -e $dest || -L $dest ]]; then
			any=1
			break
		fi
	done
	(( any )) || return 0

	ensure_backup_dir
	for name in $names; do
		dest="$HOME/$name"
		[[ -e $dest || -L $dest ]] || continue
		bdest="$BACKUP_DIR/$name"
		if (( ! DRY_RUN )); then
			mkdir -p "${bdest:h}"
			cp -a -- "$dest" "$bdest"
		fi
		record COPIED "$dest -> $bdest"
	done
}

write_manifest() {
	if [[ -z $BACKUP_DIR || $DRY_RUN -eq 1 || ! -d $BACKUP_DIR ]]; then
		return 0
	fi
	local line
	{
		print -r -- "# installer backup ${BACKUP_DIR:t}"
		print -r -- "# $(date '+%Y-%m-%d %H:%M:%S')"
		for line in $MANIFEST; do
			print -r -- "$line"
		done
	} >"$BACKUP_DIR/MANIFEST.txt"
}

on_exit() {
	local -i code=$?
	if (( code != 0 && ! DRY_RUN )) && [[ -n "${BACKUP_DIR:-}" && -d "${BACKUP_DIR}" ]]; then
		print -u2 "Install failed. Your files are in $BACKUP_DIR"
	fi
}

warn_if_root() {
	if [[ ${EUID:-$(id -u)} -eq 0 ]]; then
		print -u2 "Warning: running as root. Prefer installing as your normal user."
	fi
}

confirm_mode() {
	local mode=$1
	local prompt=$2
	local flag=$3
	case $mode in
		yes) return 0 ;;
		no) return 1 ;;
	esac
	if (( DRY_RUN )); then
		print "Would prompt: $prompt"
		print "  (pass $flag to include this in a dry-run)"
		return 1
	fi
	if [[ ! -t 0 ]]; then
		print "stdin is not a TTY; skipping (pass $flag to proceed)."
		return 1
	fi
	local reply
	print -n "$prompt "
	read -r reply || true
	if [[ $reply == [yY] || $reply == [yY][eE][sS] ]]; then
		return 0
	fi
	return 1
}

resolve_brew() {
	if (( $+commands[brew] )); then
		return 0
	fi
	local p
	for p in /opt/homebrew/bin/brew /usr/local/bin/brew "$HOME/.linuxbrew/bin/brew" /home/linuxbrew/.linuxbrew/bin/brew; do
		if [[ -x $p ]]; then
			eval "$("$p" shellenv)"
			rehash
			return 0
		fi
	done
	return 1
}

collect_missing_tools() {
	MISSING_CMDS=()
	MISSING_FORMULAE=()
	local spec cmd formula
	for spec in git:git fzf:fzf eza:eza bat:bat fd:fd cargo:rust uv:uv; do
		cmd=${spec%%:*}
		formula=${spec#*:}
		if ! (( $+commands[$cmd] )); then
			MISSING_CMDS+=("$cmd")
			(( ${MISSING_FORMULAE[(Ie)$formula]} )) || MISSING_FORMULAE+=("$formula")
		fi
	done
}

install_homebrew() {
	if (( DRY_RUN )); then
		print "Would install Homebrew from https://brew.sh"
		return 0
	fi
	print "Installing Homebrew..."
	if [[ $BREW_MODE == yes ]]; then
		NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
	else
		/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
	fi
	resolve_brew || {
		print -u2 "Homebrew installed but brew is not on PATH yet. Open a new terminal or eval brew shellenv."
		return 1
	}
}

offer_brew_packages() {
	local have_brew=0
	resolve_brew && have_brew=1

	collect_missing_tools
	(( $#MISSING_CMDS )) || return 0

	print "Missing tools: ${(j:, :)MISSING_CMDS}"
	print "Homebrew formulae: ${(j:, :)MISSING_FORMULAE}"

	local prompt
	if (( have_brew )); then
		prompt="Install missing tools with Homebrew? [y/N]"
	else
		print "Homebrew is not installed. See https://brew.sh"
		prompt="Install Homebrew and the missing tools? [y/N]"
	fi
	confirm_mode "$BREW_MODE" "$prompt" --brew || {
		print -u2 "Warning: missing tools (install still continues): ${(j:, :)MISSING_CMDS}"
		return 0
	}

	if (( ! have_brew )); then
		install_homebrew || {
			print -u2 "Warning: Homebrew install failed; skipping packages."
			return 0
		}
	fi

	if (( DRY_RUN )); then
		print "Would run: brew install --formula ${MISSING_FORMULAE}"
		return 0
	fi
	print "Running: brew install --formula ${MISSING_FORMULAE}"
	brew install --formula "${MISSING_FORMULAE[@]}" || print -u2 "Warning: brew install failed; continuing."
	rehash
	collect_missing_tools
	if (( $#MISSING_CMDS )); then
		print -u2 "Still missing after brew: ${(j:, :)MISSING_CMDS}"
	fi
}

want_python_venv() {
	confirm_mode "$PYTHON_MODE" "Install Python venv from pyproject.toml and link ~/.venv? [y/N]" --python
}

import_zsh_history() {
	local old="$HOME/.zsh_history"
	local new="$HOME/.cache/zsh/history"

	if [[ ! -e $old && ! -L $old ]]; then
		print "No $old to import."
		return 0
	fi
	if [[ -e $new || -L $new ]] && [[ "${old:A}" == "${new:A}" ]]; then
		print "History is already at $new; nothing to import."
		return 0
	fi

	confirm_mode "$HISTORY_MODE" "Import $old into $new? [y/N]" --history || return 0

	ensure_backup_dir
	local bold="$BACKUP_DIR/.zsh_history"
	local bnew="$BACKUP_DIR/.cache/zsh/history"

	if (( DRY_RUN )); then
		print "Would copy $old -> $bold"
		if [[ -e $new || -L $new ]]; then
			print "Would copy $new -> $bnew"
			print "Would append $old onto $new"
		else
			print "Would copy $old -> $new"
		fi
		record COPIED "$old -> $bold"
		if [[ -e $new || -L $new ]]; then
			record COPIED "$new -> $bnew"
		fi
		record IMPORTED "$old -> $new"
		return 0
	fi

	mkdir -p "${bold:h}"
	cp -a -- "$old" "$bold"
	record COPIED "$old -> $bold"

	mkdir -p "${new:h}"
	if [[ -e $new || -L $new ]]; then
		mkdir -p "${bnew:h}"
		cp -a -- "$new" "$bnew"
		record COPIED "$new -> $bnew"
		cat -- "$old" >>"$new"
	else
		cp -a -- "$old" "$new"
	fi
	record IMPORTED "$old -> $new"
	chmod 600 "$new" 2>/dev/null || true
	print "History imported into $new"
}

install_python_venv() {
	want_python_venv || return 0
	if ! (( $+commands[uv] )); then
		print -u2 "uv is not installed; skipping Python venv. See https://docs.astral.sh/uv/"
		return 0
	fi
	if [[ ! -e $REPO_ROOT/pyproject.toml ]]; then
		print -u2 "No pyproject.toml in $REPO_ROOT; skipping Python venv."
		return 0
	fi
	if (( DRY_RUN )); then
		print "Would run: uv sync in $REPO_ROOT"
	else
		print "Running uv sync in $REPO_ROOT"
		(cd "$REPO_ROOT" && uv sync)
	fi
	install_pair "$REPO_ROOT/.venv" "$HOME/.venv"
	print "Python venv: $HOME/.venv -> $REPO_ROOT/.venv"
	print ".zshrc sources ~/.venv/bin/activate when that path exists."
}

# --- main ---

while (( $# )); do
	case $1 in
		-h | --help)
			usage
			exit 0
			;;
		--dry-run)
			DRY_RUN=1
			shift
			;;
		--python)
			PYTHON_MODE=yes
			shift
			;;
		--no-python)
			PYTHON_MODE=no
			shift
			;;
		--brew)
			BREW_MODE=yes
			shift
			;;
		--no-brew)
			BREW_MODE=no
			shift
			;;
		--history)
			HISTORY_MODE=yes
			shift
			;;
		--no-history)
			HISTORY_MODE=no
			shift
			;;
		*)
			print -u2 "Unknown option: $1"
			usage
			exit 1
			;;
	esac
done

trap on_exit EXIT

if [[ ! -e $REPO_ROOT/.zshenv || ! -d $REPO_ROOT/.config ]]; then
	print -u2 "Cannot find repo files under $REPO_ROOT"
	exit 1
fi

warn_if_root
offer_brew_packages

print "Repo:  $REPO_ROOT"
print "Home:  $HOME"
(( DRY_RUN )) && print "Mode:  dry-run"
print

install_pair "$REPO_ROOT/.zshenv" "$HOME/.zshenv"

for src in "$REPO_ROOT/.config"/*(N); do
	[[ ${src:t} == .DS_Store ]] && continue
	install_pair "$src" "$HOME/.config/${src:t}"
done

snapshot_shadowed
import_zsh_history
install_python_venv
write_manifest

print
if [[ -n $BACKUP_DIR ]]; then
	if (( DRY_RUN )); then
		print "Would write MANIFEST.txt in $BACKUP_DIR"
	else
		print "Backup: $BACKUP_DIR"
	fi
else
	print "No files needed backing up."
fi

if (( DID_WORK )); then
	print
	print "Next: open a new terminal (do not source this session)."
	print "  echo \$ZDOTDIR    # should be ~/.config/zsh"
	print "If zsh is not your login shell: chsh -s \$(command -v zsh)"
else
	print "Already installed; nothing to link."
fi

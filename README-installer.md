# Installer

`installer.sh` backs up anything it will replace, then symlinks this clone into `$HOME`.

Edits in the clone are live. Re-running the installer is safe: paths that already point at this repo are left alone, and a new dated backup folder is created only when something is actually moved or copied.

## Run it

```zsh
git clone "https://github.com/jessegoodier/zsh-config.git" ~/git/zsh-config
cd ~/git/zsh-config
./installer.sh
```

Replace the clone path if you keep git checkouts elsewhere. Then open a **new** terminal (do not `source` an old session).

```zsh
echo $ZDOTDIR    # should be ~/.config/zsh
```

If zsh is not your login shell:

```zsh
chsh -s $(command -v zsh)
```

## Flags

```text
./installer.sh                  # backup + link; prompt for brew, history, and Python venv
./installer.sh --dry-run        # print actions, change nothing
./installer.sh --python         # install the venv without prompting
./installer.sh --no-python      # skip the venv without prompting
./installer.sh --brew           # install missing Homebrew formulae without prompting
./installer.sh --no-brew        # skip Homebrew without prompting
./installer.sh --history        # import ~/.zsh_history without prompting
./installer.sh --no-history     # skip history import without prompting
./installer.sh --help
```

`--dry-run` does not wait for prompts. Combine with `--python`, `--brew`, and/or `--history` to see those actions. If stdin is not a TTY, optional steps are skipped unless you pass the matching `--` flag.

Run the script; do not `source` it.

## What gets linked

| Repo path | Home path |
| --------- | --------- |
| `.zshenv` | `~/.zshenv` |
| `.config/zsh/.zshrc` | `~/.zshrc` |
| each top-level entry under `.config/` | `~/.config/<name>` |

Today that `.config/` set is `cspell`, `fzf`, `fzf-git`, `yazi`, `zsh`, and `zsh-patina`. New top-level entries are picked up automatically.

`$HOME/.zshenv` must be this repo’s file (or a copy of it). zsh only reads `$ZDOTDIR/.zshenv` automatically when `ZDOTDIR` is already set; this file sets it, then sources `$ZDOTDIR/.zshenv`.

`~/.zshrc` is a convenience symlink to the same file zsh loads as `$ZDOTDIR/.zshrc`. `ln -s` is the same on macOS and Linux; after `ZDOTDIR` is set, zsh does not also source `~/.zshrc`, so there is no double-load.

## Python venv

The installer asks whether to install the default virtual environment from [pyproject.toml](./pyproject.toml) (Python 3.12+, via `uv sync` in the clone) and symlink `$HOME/.venv` to `$REPO/.venv`.

`.zshrc` already activates it when present:

```zsh
[[ -r $HOME/.venv/bin/activate ]] && source "$HOME/.venv/bin/activate"
```

An existing `~/.venv` is moved into the dated backup folder before the symlink is created, same as the other targets. Needs [uv](https://docs.astral.sh/uv/). Details of the tools: [README-python.md](./README-python.md).

## Homebrew

Before linking, the installer checks for `git`, `fzf`, `eza`, `bat`, `fd`, `cargo`, and `uv`. If any are missing, it asks whether to install them with Homebrew (`cargo` → `rust`).

If `brew` is not on `PATH`, it also looks in `/opt/homebrew/bin`, `/usr/local/bin`, and the Linuxbrew locations. When Homebrew itself is missing, the prompt is to install Homebrew from [brew.sh](https://brew.sh) and then the formulae. `--brew` runs the Homebrew installer with `NONINTERACTIVE=1`.

## Zsh plugins

After linking `$HOME/.config/zsh`, the installer reads `plugin-path` entries from [`.config/zsh/plugins.zsh`](.config/zsh/plugins.zsh) and adds `zsh-patina`. For each plugin missing from `$HOME/.config/zsh/plugins/`, it clones from GitHub (same repos as first-launch `plugin-path`). If `zsh-patina` is present but not built, it runs `cargo build --release` when `cargo` is available.

`./installer.sh --dry-run` lists each plugin as `OK` or prints `Would clone …` / `Would run: cargo build …` without changing anything. Needs `git` on `PATH` (or installable via `--brew`).

## History import

This config writes history to `~/.cache/zsh/history` (`HISTFILE` in `config/history.zsh`). The installer asks whether to import `~/.zsh_history` there.

If you say yes (or pass `--history`):

- `~/.zsh_history` is copied into the dated backup folder (the original is left in `$HOME`).
- An existing `~/.cache/zsh/history` is copied into the same backup folder, then `~/.zsh_history` is appended onto it.
- If the new histfile does not exist yet, `~/.zsh_history` is copied there.

Re-running with `--history` can append the old file again. Skip with `--no-history` if you already imported.

## Backups

Existing targets are **moved** into `backups/YYYY-MM-DD_HHMMSS/`, keeping the path relative to `$HOME`:

```text
backups/2026-08-25_113145/
  MANIFEST.txt
  .zshenv
  .zshrc
  .config/zsh/
  .config/fzf/
```

If that timestamp already exists, the directory name gets `_<pid>` appended. Dated folders are gitignored so a user’s old config (and any secrets in it) is not committed.

Files this installer does not replace, but that zsh will stop reading once `ZDOTDIR` is set, are **copied** (not moved) into the same folder when the installer actually links something: `~/.zprofile`, `~/.zlogin`, `~/.zlogout`.

`MANIFEST.txt` lists `MOVED` / `COPIED` / `SKIPPED` / `LINKED` with source and destination.

If a move succeeds and a later link fails, the script prints the backup path. Restore from there before running again.

## Restore

Inspect the dated folder, then put files back. Example:

```zsh
ls backups/2026-08-25_113145
rm ~/.zshenv
mv backups/2026-08-25_113145/.zshenv ~/.zshenv
rm ~/.config/zsh
mv backups/2026-08-25_113145/.config/zsh ~/.config/zsh
```

Only restore the paths you need. Copied shadowed files (`.zshrc` and friends) were left in `$HOME`; the copies in the backup are extras.

## What it does not do

- Does not touch `~/.zsh-config-private.zsh`, or history files / brew packages you did not opt into.
- Does not run `chsh`.
- Clones missing zsh plugins into `$HOME/.config/zsh/plugins/` (see [Zsh plugins](#zsh-plugins)); `update-plugin` refreshes them later.
- Does not install the Python venv unless you answer yes or pass `--python`.
- Does not install Homebrew or formulae unless you answer yes or pass `--brew`.
- Does not import `~/.zsh_history` unless you answer yes or pass `--history`.
- Missing tools still produce a warning if you skip Homebrew; install continues. Missing `uv` only matters if you opted into the venv.

Requirements, first launch, overlays, and troubleshooting are in [README-howto.md](./README-howto.md).

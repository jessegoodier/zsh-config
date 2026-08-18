# How to implement this config

This repo is an XDG zsh setup: a tiny `$HOME/.zshenv` points zsh at `$XDG_CONFIG_HOME/zsh`, plugins clone themselves on first use, and opinions live in an overlay you can keep, edit, or skip.

## Layout

```
.zshenv                         →  $HOME/.zshenv          (sets ZDOTDIR)
.config/zsh/.zshenv             →  env, PATH, path_add
.config/zsh/.zshrc              →  plugins + modules + overlays
.config/zsh/plugins.zsh         →  clone/load plugins
.config/zsh/config/*.zsh        →  prompt, history, keys, completion, aliases, fzf, functions
.config/zsh/personal-config.zsh →  public overlay (kubectl, macOS, kube prompt, …)
.config/fzf/                    →  fzf theme + preview script
.zsh-config-private.zsh         →  $HOME/.zsh-config-private.zsh (not in git)
```

`$ZDOTDIR/plugins/` is gitignored. `plugin-path` clones into it; `update-plugin` refreshes those clones. Three Oh My Zsh _snippets_ (git / kubectl / macos) ship under `plugins/oh-my-zsh-plugins/` without the framework.

## Requirements

| Need                                                                               | Why                                                                         |
| ---------------------------------------------------------------------------------- | --------------------------------------------------------------------------- |
| zsh 5.8+ as login shell                                                            | this config                                                                 |
| git                                                                                | plugin clones                                                               |
| [fzf](https://github.com/junegunn/fzf)                                             | completions, Ctrl-R / Ctrl-T / Alt-C                                        |
| [eza](https://github.com/eza-community/eza), [bat](https://github.com/sharkdp/bat) | `ls` aliases and fzf preview                                                |
| [fd](https://github.com/sharkdp/fd)                                                | overlay `FZF_DEFAULT_COMMAND`                                               |
| rust/`cargo`                                                                       | first-time [zsh-patina](https://github.com/michel-kraemer/zsh-patina) build |

Optional: `kubectl` / `kubecolor` (overlay), `zoxide`, `yazi`, `fnm`, `keychain`, `nvim`. Missing tools are skipped or only break the alias that uses them.

On macOS, Homebrew is the usual source for these. The Arch-oriented aliases in `config/aliases.zsh` (`pacman`, `yay`) are harmless if you do not type them.

## 1. Back up what you have

```zsh
[[ -e ~/.zshenv ]] && mv ~/.zshenv ~/.zshenv.bak
[[ -e ~/.config/zsh ]] && mv ~/.config/zsh ~/.config/zsh.bak
[[ -e ~/.config/fzf ]] && mv ~/.config/fzf ~/.config/fzf.bak
```

Keep the backups until a new terminal starts cleanly.

## 2. Clone and symlink

Symlinks mean edits in the clone are live. Replace the clone path if you keep git checkouts elsewhere.

```zsh
git clone "https://github.com/jessegoodier/zsh-config.git" ~/git/zsh-config

mkdir -p ~/.config
ln -s ~/git/zsh-config/.zshenv ~/.zshenv
ln -s ~/git/zsh-config/.config/zsh ~/.config/zsh
ln -s ~/git/zsh-config/.config/fzf ~/.config/fzf
```

`$HOME/.zshenv` must be the repo file (or a copy of it). zsh only reads `$ZDOTDIR/.zshenv` automatically when `ZDOTDIR` is already set; this file sets it, then sources `$ZDOTDIR/.zshenv`.

If zsh is not your login shell:

```zsh
chsh -s $(command -v zsh)
```

## 3. First launch

Open a **new** terminal (do not `source` an old interactive session).

On the first run you should see clone messages for gitstatus, zsh-defer, ez-compinit, and the rest. zsh-patina builds with `cargo` if the binary is missing; that is the slow one-time step.

Then:

```zsh
echo $ZDOTDIR    # should be ~/.config/zsh
update-plugin    # later: refresh clones (skips the vendored OMZ snippets)
```

## 4. Make it yours

Three layers, last writer wins:

| File                            | In git? | Use for                                      |
| ------------------------------- | ------- | -------------------------------------------- |
| `config/*.zsh`                  | yes     | shared behavior you are happy to publish     |
| `$ZDOTDIR/personal-config.zsh`  | yes     | public opinions (PATH, aliases, kube prompt) |
| `$HOME/.zsh-config-private.zsh` | no      | secrets, machine-only PATH, extra hooks      |

**Keep the overlay, change the opinions.** Edit `personal-config.zsh`: PATH entries, `EDITOR`, `fd` as the fzf finder, kubectl/kubecolor, the kube prompt prefix (`KUBE_INFO`).

**Skip the overlay.** Remove or rename `personal-config.zsh`. Core prompt, completions, and plugins still load. `KUBE_INFO` stays empty.

**Add secrets.** Create `~/.zsh-config-private.zsh` (already gitignored). That is the place for tokens, extra `path_add` dirs, and company login helpers.

**Steal the loader only.** Copy `plugins.zsh` + `.zshenv` / `.zshrc` wiring and drop in your own `config/` modules. `plugin-path owner repo` clones `https://github.com/owner/repo` on first use.

## 5. What loads when

- **Eager:** gitstatus, zsh-defer, ez-compinit (queues `compdef`; real `compinit` on first prompt), zsh-completions, the `config/*.zsh` modules.
- **Deferred (`zsh-defer`):** fzf-tab, autosuggestions, history-substring-search, colored-man-pages, zsh-patina, overlay alias packs.
- **Lazy:** fzf widgets (Ctrl-R / Ctrl-T / Alt-C), `zoxide`, `fnm` (when `package.json` is in `$PWD`).

That split is what keeps first prompt snappy. Put slow or opinionated work in the overlay and `zsh-defer` it.

## 6. Recreate the benchmark

From a machine where this config is the login shell (or a scratch `HOME` that symlinks it):

```zsh
git clone "https://github.com/romkatv/zsh-bench.git" ~/zsh-bench
~/zsh-bench/zsh-bench --login yes
```

zsh-bench needs the prompt to contain the hostname or the last path component. This prompt does the latter. Numbers go in [README.md](./README.md); they are a min over 16 login iterations on one machine, not a guarantee.

## Troubleshooting

- **`command not found: compdef`** — ez-compinit must load before anything calls `compdef`. Do not defer `plugins.zsh` itself.
- **Plugins missing after clone** — first start needs network; check `$ZDOTDIR/plugins`.
- **zsh-patina missing** — install rust (`https://rustup.rs` or Homebrew `rustup`), then `update-plugin` or `cargo build --release` in `$ZDOTDIR/plugins/zsh-patina`.
- **fzf preview empty** — install `eza` and `bat`; confirm `$XDG_CONFIG_HOME/fzf/preview.sh` is executable.
- **Git aliases missing** — they come from the overlay snippets under `plugins/oh-my-zsh-plugins/` and load after first prompt.
- **Still on the old config** — this repo is not live until `~/.zshenv` and `~/.config/zsh` point at it. `echo $ZDOTDIR; ls -l ~/.zshenv ~/.config/zsh`.

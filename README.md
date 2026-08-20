# Zsh Config

Thanks to [houssamouhra/zsh-config](https://github.com/houssamouhra/zsh-config) for the inspiration!

----------------------------------------------------------------------------------------------------

A modular, lightweight, and performance-focused Zsh configuration built for my workflow as a software engineer.

> [!Note]
> This setup uses an XDG-based configuration path for zsh. The main config lives under `$ZDOTDIR` (`$XDG_CONFIG_HOME/zsh`).
> `$HOME/.zshenv` sets `$ZDOTDIR` so zsh uses the XDG configuration directory. A separate `$ZDOTDIR/.zshenv` holds the environment variables.

## Philosophy

Speed and simplicity first.

No frameworks. No bloat.

The configuration is fully modular, deliberately minimal, and built so that every piece has a clear reason to exist. Opinions (kubectl, editor, kube prompt) live in an optional overlay so the core stays copyable.

**Want to use it?** See [README-howto.md](./README-howto.md) for install, overlay vs private files, and how to make it yours.

## Features

- **Modular configuration**
  Split into focused modules (`prompt`, `history`, `keybinds`, `completion`, `aliases`, `fzf`, `functions`) for easy maintenance.

- **Fast startup**
  Deferred plugin loading (`zsh-defer`), lazy-loaded functionality, cached completions (`ez-compinit`), and a non-blocking prompt.

- **Minimal native prompt**
  Smart path truncation, real-time Git status, command duration, and command state. No external prompt frameworks. The overlay may prefix kube context via `KUBE_INFO`.

- **Enhanced completions**
  Interactive `fzf-tab` menu with extra completions from `zsh-completions`.

- **Smart history**
  Substring search, history-based autosuggestions, and optimized history settings.

- **Quality-of-life features**
  Syntax highlighting (`zsh-patina`), colored man pages, useful aliases, custom functions, and thoughtful keybindings.

- **Lightweight by design**
  No plugin manager and no Oh My Zsh framework. A [minimal custom loader](.config/zsh/plugins.zsh) clones a small plugin set on first use. The overlay vendors three Oh My Zsh *snippets* (git / kubectl aliases) without loading the framework.

- **Optional overlay**
  `$ZDOTDIR/personal-config.zsh` is the public opinionated layer. `$HOME/.zsh-config-private.zsh` is gitignored for machine-local secrets.

## Terminal

Shell startup is only part of the experience. I use [Ghostty](https://ghostty.org), a GPU-accelerated native terminal emulator, to keep the overall terminal experience fast and responsive.

## Plugins

Cloned on first use into `$ZDOTDIR/plugins` (gitignored). `update-plugin` refreshes those clones.

- [gitstatus](https://github.com/romkatv/gitstatus) — extremely fast Git status for the prompt
- [zsh-defer](https://github.com/romkatv/zsh-defer) — defers non-critical plugins to improve startup time
- [ez-compinit](https://github.com/mattmc3/ez-compinit) — lightweight and fast completion initialization
- [zsh-completions](https://github.com/zsh-users/zsh-completions) — additional completion definitions
- [fzf-tab](https://github.com/Aloxaf/fzf-tab) — interactive fzf completion menu
- [zsh-autosuggestions](https://github.com/zsh-users/zsh-autosuggestions) — fish-like history-based suggestions
- [zsh-history-substring-search](https://github.com/zsh-users/zsh-history-substring-search) — search history by substring
- [colored-man-pages](https://github.com/houssamouhra/colored-man-pages) — colored man pages
- [zsh-patina](https://github.com/michel-kraemer/zsh-patina) — fast syntax highlighting

Vendored snippets (shipped in-tree, not cloned): [ohmyzsh git](https://github.com/ohmyzsh/ohmyzsh/tree/master/plugins/git), [kubectl](https://github.com/ohmyzsh/ohmyzsh/tree/master/plugins/kubectl).

## Benchmark

This fork is much slower than the original, but fast enough for me.

Measured **2026-08-18** with [zsh-bench](https://github.com/romkatv/zsh-bench) `--iters 16 --login yes` (minimum over 16 login iterations). Apple Silicon Mac, zsh 5.9. Scratch `HOME` with this repo’s published files (core + `personal-config.zsh`, no private overlay) and plugins already cloned.

| Metric              | Result     |
|---------------------|-----------:|
| First prompt lag    | 56.693 ms  |
| First command lag   | 60.213 ms  |
| Command lag         | 14.976 ms  |
| Input lag           |  3.142 ms  |
| Exit time           | 46.944 ms  |

`ez-compinit` queues `compdef` during startup and runs real `compinit` on first prompt, so zsh-bench reports `has_compsys=1`. Autosuggestions and the gitstatus daemon start on idle via `zsh-defer`, so `has_autosuggestions` and `has_git_prompt` are 0 on that snapshot. Syntax highlighting is zsh-patina, which zsh-bench does not detect (`has_syntax_highlighting` only recognizes zsh-syntax-highlighting and fast-syntax-highlighting). Re-run after changing the overlay; see [README-howto.md](./README-howto.md#6-recreate-the-benchmark).

## License

[MIT](./LICENSE)

# shortcuts<!-- omit in toc -->

- [How `z` (zoxide) works](#how-z-zoxide-works)
- [All shortcut keys in this config](#all-shortcut-keys-in-this-config)
  - [Keybinds (`keybinds.zsh`)](#keybinds-keybindszsh)
  - [FZF widget keybinds (`fzf.zsh`)](#fzf-widget-keybinds-fzfzsh)
  - [Shell navigation](#shell-navigation)

## How `z` (zoxide) works

Zoxide is a **smarter `cd`** that learns your most-visited directories. The lazy-loader in [`functions.zsh:35-39`](.config/zsh/config/functions.zsh:35) — `unset -f z; eval "$(zoxide init zsh)"` — means it pays zero startup cost: the full zoxide shell integration (including completions and the `__zoxide_*` internals) is injected the very first time you type `z`.

**How the frecency algorithm works:**

- Every `cd` is tracked with a frequency + recency score ("frecency")
- `z foo` jumps to the highest-scoring directory matching `foo` — no full path needed
- The more you visit a directory, the higher it ranks; old visits decay over time
- Multiple tokens narrow the match: `z git jesse` → first dir matching both words

**Key zoxide commands:**

| Command                | What it does                                            |
| ---------------------- | ------------------------------------------------------- |
| `z foo`                | Jump to the best-matching directory for `foo`           |
| `z foo bar`            | Narrow by multiple tokens                               |
| `z -`                  | Jump to the previous directory (like `cd -`)            |
| `zi foo`               | **Interactive**: opens an fzf picker filtered by `foo`  |
| `zoxide query foo`     | Print the match without cd'ing (used internally by `y`) |
| `zoxide add <path>`    | Manually add a path to the database                     |
| `zoxide remove <path>` | Remove a path from the database                         |

---

## All shortcut keys in this config

### Keybinds ([`keybinds.zsh`](.config/zsh/config/keybinds.zsh))

| Key       | Action                                                     |
| --------- | ---------------------------------------------------------- |
| `Ctrl+A`  | Beginning of line                                          |
| `Ctrl+E`  | End of line                                                |
| `Ctrl+B`  | Move back one char                                         |
| `Ctrl+F`  | Move forward one char                                      |
| `Ctrl+W`  | Delete word backward                                       |
| `Ctrl+U`  | Delete to beginning of line                                |
| `Ctrl+_`  | Undo                                                       |
| `↑` / `↓` | History search by prefix (smarter — preserves multiline)   |
| `Ctrl+P`  | History substring search up (zsh-history-substring-search) |
| `Ctrl+N`  | History substring search down                              |
| `Ctrl+G`  | Launch `tmux-sessionizer`                                  |
| `Del`     | Forward delete char                                        |

### FZF widget keybinds ([`fzf.zsh`](.config/zsh/config/fzf.zsh))

| Key         | Action                                                                                          |
| ----------- | ----------------------------------------------------------------------------------------------- |
| `Ctrl+R`    | Fuzzy search shell history (exact match, reverse order)                                         |
| `Ctrl+T`    | Fuzzy find files (multi-select; `Ctrl+O` opens in nvim)                                         |
| `Alt+C`     | Fuzzy cd into a subdirectory (with tree preview)                                                |
| `Shift+Tab` | Accept zsh-autosuggestion (from [`personal-config.zsh:47`](.config/zsh/personal-config.zsh:47)) |

### Shell navigation

| Command/Alias    | What it does                                                         |
| ---------------- | -------------------------------------------------------------------- |
| `z <query>`      | Jump to a frecent directory                                          |
| `zi <query>`     | Interactive fzf directory picker                                     |
| `y [dir\|query]` | Open yazi file manager; if arg isn't a real dir, resolves via zoxide |
| `-`              | `cd -` (go to previous directory)                                    |
| `...`            | `cd ../..`                                                           |
| `....`           | `cd ../../..`                                                        |
| `AUTO_CD`        | Type a bare directory name (no `cd`) to enter it                     |

# Python Tools

[pyproject.toml](pyproject.toml) contains the tools I use frequently, installed in my profile to make them available globally.

`$HOME/.venv` is what `.zshrc` activates. [installer.sh](./installer.sh) can create this repo’s `.venv` with `uv sync` and symlink `~/.venv` there (prompt, or `--python` / `--no-python`). See [README-installer.md](./README-installer.md).

To recreate or update the venv from a checkout of this repo:

```bash
uvi
```

The function activates the virtual environment in the current shell. Run it again in a new shell when you need these tools.

To add a new tool, run:

```bash
uv add <tool>
```

To upgrade a tool, run:

```bash
uv lock --upgrade-package <tool>
```

or run the [script](scripts/update_dependencies.py) to update all dependencies.

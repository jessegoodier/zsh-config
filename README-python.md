# Python Tools

[pyproject.toml](pyproject.toml) contains the tools I use frequently, installed in my profile to make them available globally.

Run this function to install the dependencies and activate the virtual environment. It will create a `.venv` directory in the root of the project and install the dependencies.

The function activates the virtual environment in the current shell. Run it again in a new shell when you need these tools.

```bash
uvi
```

To add a new tool, run:

```bash
uv add <tool>
```

To upgrade a tool, run:

```bash
uv lock --upgrade-package <tool>
```

or run the [script](scripts/update_dependencies.py) to update all dependencies.

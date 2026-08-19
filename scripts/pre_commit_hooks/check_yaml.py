#!/usr/bin/env python3
"""Not currently used, this repo has helm templates that make this check tedious. Check YAML files for syntax errors."""

from __future__ import annotations

import sys

import yaml


def check_file(filename: str, allow_multiple: bool = False) -> tuple[bool, str | None]:
    """Check YAML file. Returns (is_valid, error_message)."""
    try:
        with open(filename, encoding="utf-8") as f:
            content = f.read()

        if allow_multiple:
            # Allow multiple documents
            list(yaml.safe_load_all(content))
        else:
            yaml.safe_load(content)

        return True, None
    except yaml.YAMLError as e:
        return False, str(e)
    except Exception as e:
        return False, f"Error reading file: {e}"


def main() -> int:
    """Main entry point."""
    args = sys.argv[1:]

    # Check for --allow-multiple-documents flag
    allow_multiple = "--allow-multiple-documents" in args
    filenames = [arg for arg in args if not arg.startswith("--")]

    if not filenames:
        return 0

    has_errors = False

    for filename in filenames:
        # Only check YAML files
        if not (filename.endswith((".yaml", ".yml"))):
            continue

        is_valid, error = check_file(filename, allow_multiple)

        if not is_valid:
            has_errors = True
            print(f"❌ YAML error in {filename}:")
            print(f"   {error}")

    if has_errors:
        return 1

    return 0


if __name__ == "__main__":
    raise SystemExit(main())

# Made with Bob

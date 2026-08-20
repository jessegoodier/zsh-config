from __future__ import annotations

import re
import sys
from pathlib import Path

ALIAS_RE = re.compile(r"^\s*alias\s+([A-Za-z0-9_-]+)=")


def _raise_duplicates(
    filename: str, duplicates: dict[str, list[int]], kind: str
) -> None:
    if not duplicates:
        return
    details = ", ".join(
        f"{name!r} (lines {', '.join(str(n) for n in nums)})"
        for name, nums in sorted(duplicates.items())
    )
    raise ValueError(f"duplicate {kind} in {filename}: {details}")


def sorted_alias_file(lines: list[str], filename: str) -> list[str]:
    alias_indexes: list[int] = []
    aliases: list[tuple[str, str]] = []
    definitions: dict[str, str] = {}
    seen: dict[str, list[int]] = {}

    for index, line in enumerate(lines):
        match = ALIAS_RE.match(line)
        if not match:
            continue
        name = match.group(1)
        previous = definitions.get(name)
        if previous is not None and previous != line:
            raise ValueError(
                f"conflicting definitions for alias {name!r} in {filename}"
            )
        definitions[name] = line
        seen.setdefault(name, []).append(index + 1)
        alias_indexes.append(index)
        aliases.append((name, line))

    _raise_duplicates(
        filename,
        {n: nums for n, nums in seen.items() if len(nums) > 1},
        "alias entries",
    )

    sorted_lines = [line for _, line in sorted(aliases)]
    result = lines.copy()
    for index, line in zip(alias_indexes, sorted_lines, strict=True):
        result[index] = line
    return result


def sorted_cspell_file(lines: list[str], filename: str) -> list[str]:
    seen: dict[str, list[int]] = {}
    for index, line in enumerate(lines):
        word = line.rstrip("\n")
        if not word.strip():
            continue
        seen.setdefault(word, []).append(index + 1)
    _raise_duplicates(
        filename,
        {w: nums for w, nums in seen.items() if len(nums) > 1},
        "entries",
    )
    return sorted(lines)


def sort_file(filename: str) -> bool:
    try:
        path = Path(filename)
        with path.open("r", encoding="utf-8") as f:
            lines = f.readlines()
        original = lines.copy()
        if lines and not lines[-1].endswith("\n"):
            lines[-1] += "\n"
        if path.name == "cspell.txt":
            updated = sorted_cspell_file(lines, filename)
        else:
            updated = sorted_alias_file(lines, filename)
        if updated == original:
            return False
        with path.open("w", encoding="utf-8") as f:
            f.writelines(updated)
        return True
    except (OSError, UnicodeError, ValueError) as e:
        print(f"Error processing file: {e}", file=sys.stderr)
        raise


def main() -> int:
    filenames = sys.argv[1:]
    if not filenames:
        print(f"Usage: python {sys.argv[0]} <file_to_sort> [...]", file=sys.stderr)
        return 1
    changed = False
    for filename in filenames:
        try:
            file_changed = sort_file(filename)
            if file_changed:
                print(f"Sorting {filename}")
            changed |= file_changed
        except (OSError, UnicodeError, ValueError):
            return 1
    return int(changed)


if __name__ == "__main__":
    raise SystemExit(main())

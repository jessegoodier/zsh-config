"""Basic repository guardrails for secrets and large files."""

from __future__ import annotations

import re
import subprocess
import sys
from pathlib import Path

MAX_FILE_KB = 500
MAX_FILE_BYTES = MAX_FILE_KB * 1024
SECRET_PATTERNS = [
    re.compile(r"AKIA[0-9A-Z]{16}"),  # AWS access key id
    re.compile(r"-----BEGIN (?:RSA|EC|OPENSSH|PRIVATE) KEY-----"),
    re.compile(r"(?i)(api[_-]?key|token|secret)\s*[:=]\s*['\"][^'\"]{8,}['\"]"),
]
ALLOWED_SECRET_FILES = {".env.example"}


def tracked_files() -> list[Path]:
    output = subprocess.check_output(["git", "ls-files"], text=True)
    return [Path(line.strip()) for line in output.splitlines() if line.strip()]


def main() -> int:
    bad_size: list[tuple[str, int]] = []
    bad_secret: list[str] = []

    for file_path in tracked_files():
        if not file_path.exists() or file_path.is_dir():
            continue
        size_bytes = file_path.stat().st_size
        if size_bytes > MAX_FILE_BYTES:
            bad_size.append((str(file_path), size_bytes // 1024))

        if file_path.name in ALLOWED_SECRET_FILES:
            continue
        try:
            content = file_path.read_text(encoding="utf-8", errors="ignore")
        except OSError:
            continue
        for pattern in SECRET_PATTERNS:
            if pattern.search(content):
                bad_secret.append(str(file_path))
                break

    if bad_size or bad_secret:
        if bad_size:
            print(f"Large files detected (max: {MAX_FILE_KB}KB):")
            for item, size_kb in bad_size:
                print(f" - {item}: {size_kb}KB")
        if bad_secret:
            print("Potential secrets detected:")
            for item in bad_secret:
                print(f" - {item}")
        return 1

    print("Repository safety checks passed.")
    return 0


if __name__ == "__main__":
    sys.exit(main())

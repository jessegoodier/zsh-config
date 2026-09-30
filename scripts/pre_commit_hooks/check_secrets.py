#!/usr/bin/env python3
"""Check for accidentally committed secrets in files."""

from __future__ import annotations

import argparse
import re

# Patterns that might indicate secrets
SECRET_PATTERNS = [
    (
        r'(?i)(api[_-]?key)\s*[:=]\s*["\']?(?!REPLACE_WITH_|YOUR_|CHANGEME|EXAMPLE_)[a-zA-Z0-9_\-]{20,}["\']?',
        "API key",
    ),
    (
        r"(?<!@sha256:)\b[0-9a-fA-F]{64}\b",
        "SHA-256 hash",
    ),  # Negative lookbehind to exclude @sha256: image digests
    (
        r'(?i)(secret[_-]?key|secretkey)\s*[:=]\s*["\']?[a-zA-Z0-9_\-]{20,}["\']?',
        "Secret key",
    ),
    (r'(?i)(token)\s*[:=]\s*["\']?[a-zA-Z0-9_\-]{20,}["\']?', "Token"),
    (
        r'(?i)(aws[_-]?access[_-]?key[_-]?id)\s*[:=]\s*["\']?[A-Z0-9]{20}["\']?',
        "AWS Access Key",
    ),
    (
        r'(?i)(aws[_-]?secret[_-]?access[_-]?key)\s*[:=]\s*["\']?[A-Za-z0-9/+=]{40}["\']?',
        "AWS Secret Key",
    ),
    (r"-----BEGIN (RSA |DSA )?PRIVATE KEY-----", "Private Key"),
]

# Files to skip
SKIP_PATTERNS = [
    r"\.git/",
    r"\.venv/",
    r"node_modules/",
    r"\.pyc$",
    r"\.pyo$",
    r"\.so$",
    r"\.dylib$",
]


def should_skip(filepath: str) -> bool:
    """Check if file should be skipped."""
    return any(re.search(pattern, filepath) for pattern in SKIP_PATTERNS)


def check_file(filepath: str, ignore_yaml_keys: set[str] | None = None) -> list[tuple[int, str]]:
    """Check a file for potential secrets without retaining secret values."""
    findings = []
    ignore_yaml_keys = ignore_yaml_keys or set()
    try:
        with open(filepath, encoding="utf-8", errors="ignore") as f:
            for line_num, line in enumerate(f, 1):
                # Check if line contains an ignored YAML key
                should_ignore = False
                if ignore_yaml_keys:
                    # Match YAML key patterns: "key:" or "key :"
                    for key in ignore_yaml_keys:
                        if re.search(rf"^\s*{re.escape(key)}\s*:", line):
                            should_ignore = True
                            break

                if should_ignore:
                    continue

                for pattern, secret_type in SECRET_PATTERNS:
                    if re.search(pattern, line):
                        findings.append((line_num, secret_type))
    except Exception:
        # Skip files that can't be read
        pass
    return findings


def main() -> int:
    """Main entry point."""
    parser = argparse.ArgumentParser(description="Check for accidentally committed secrets in files.")
    parser.add_argument("filenames", nargs="*", help="Files to check")
    parser.add_argument(
        "--exclude-files",
        type=str,
        help="Comma-separated list of filenames to exclude (e.g., values.yaml,test.yaml)",
    )
    parser.add_argument(
        "--ignore-yaml-keys",
        type=str,
        help="Comma-separated list of YAML keys to ignore (e.g., authSecret,apiKey)",
    )

    args = parser.parse_args()

    if not args.filenames:
        return 0

    # Parse excluded files
    excluded_files = set()
    if args.exclude_files:
        excluded_files = {f.strip() for f in args.exclude_files.split(",")}

    # Parse ignored YAML keys
    ignore_yaml_keys = set()
    if args.ignore_yaml_keys:
        ignore_yaml_keys = {k.strip() for k in args.ignore_yaml_keys.split(",")}

    found_secrets = False

    for filename in args.filenames:
        # Check if filename matches any ignored file
        if any(filename.endswith(ignored) for ignored in excluded_files):
            continue

        if should_skip(filename):
            continue

        findings = check_file(filename, ignore_yaml_keys)
        if findings:
            found_secrets = True
            print(f"\n⚠️  Potential secrets found in {filename}:")
            for line_num, secret_type in findings:
                print(f"  Line {line_num} ({secret_type}): [REDACTED]")

    if found_secrets:
        print("\n❌ Commit blocked: potential secrets detected")
        print("If these are false positives, add them to .gitignore or update the patterns")
        return 1

    return 0


if __name__ == "__main__":
    raise SystemExit(main())

# Made with Bob

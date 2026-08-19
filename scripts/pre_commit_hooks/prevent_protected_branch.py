#!/usr/bin/env python3
"""Block direct local commits or pushes to protected branches."""

from __future__ import annotations

import subprocess
import sys

PROTECTED_BRANCHES = {"main"}
ZERO_SHA = "0" * 40


def git(args: list[str]) -> str:
    return subprocess.check_output(["git", *args], text=True, stderr=subprocess.DEVNULL).strip()


def current_branch() -> str | None:
    try:
        return git(["symbolic-ref", "--quiet", "--short", "HEAD"])
    except subprocess.CalledProcessError:
        return None


def protected_ref_name(ref: str) -> str | None:
    prefix = "refs/heads/"
    if ref.startswith(prefix):
        branch = ref.removeprefix(prefix)
        if branch in PROTECTED_BRANCHES:
            return branch
    return None


def main() -> int:
    branch = current_branch()
    if branch in PROTECTED_BRANCHES:
        print(f"Refusing to commit on protected branch '{branch}'. Create a feature branch first.")
        return 1

    blocked_pushes: list[str] = []
    for line in sys.stdin:
        parts = line.split()
        if len(parts) < 4:
            continue
        _local_ref, local_sha, remote_ref, _remote_sha = parts[:4]
        if local_sha == ZERO_SHA:
            continue
        branch_name = protected_ref_name(remote_ref)
        if branch_name:
            blocked_pushes.append(branch_name)

    if blocked_pushes:
        branches = ", ".join(sorted(set(blocked_pushes)))
        print(f"Refusing to push directly to protected branch: {branches}. Open a PR instead.")
        return 1

    return 0


if __name__ == "__main__":
    raise SystemExit(main())

"""Commit only reported dependency edits, open a PR, and explicitly dispatch CI."""

import json
import os
import subprocess
from pathlib import Path, PurePosixPath


def run(*args: str) -> str:
    return subprocess.check_output(args, text=True).strip()


def stage_report(report_path: Path) -> list[str]:
    report = json.loads(report_path.read_text())
    if report.get("dry_run") is not False:
        raise ValueError("An applied update report is required")
    files = report["changed_files"]
    if not isinstance(files, list) or not files:
        raise ValueError("No dependency changes to commit")
    for name in files:
        if not isinstance(name, str):
            raise TypeError("Invalid dependency path")
        path = PurePosixPath(name)
        if (
            not name
            or path.is_absolute()
            or ".." in path.parts
            or path.parts[0] == ".git"
        ):
            raise ValueError("Unsafe dependency path")
        if Path(name).is_symlink() or not Path(name).is_file():
            raise ValueError("Dependency file must be a regular file")
    staged = run("git", "diff", "--cached", "--name-only", "-z")
    modified = set(filter(None, run("git", "diff", "--name-only", "-z").split("\0")))
    untracked = set(
        filter(
            None,
            run("git", "ls-files", "--others", "--exclude-standard", "-z").split("\0"),
        )
    )
    if staged or modified | untracked != set(files):
        raise ValueError("Working tree does not match the dependency report")
    run("git", "add", "--", *files)
    return files


def main() -> None:
    files = stage_report(Path(os.environ["UPDATE_REPORT"]))
    branch = os.environ["UPDATE_BRANCH"]
    base = os.environ["BASE_BRANCH"]
    run("git", "check-ref-format", "--branch", branch)
    run("git", "switch", "-c", branch)
    run("git", "config", "user.name", "github-actions[bot]")
    run(
        "git",
        "config",
        "user.email",
        "41898282+github-actions[bot]@users.noreply.github.com",
    )
    run("git", "commit", "-m", "chore: update all dependencies")
    run("git", "push", "origin", branch)
    body = (
        "Updates dependencies using jessegoodier/update-dependencies, with major updates enabled "
        "and a 48-hour release cooldown. Existing exclusions remain in effect.\n\n"
        "Changed files:\n"
        + "".join(f"- `{name}`\n" for name in files)
        + "\nValidation before opening: locked install, Ruff lint/format, and pytest. "
        "Full CI is explicitly dispatched "
        "for this branch.\n"
    )
    url = run(
        "gh",
        "pr",
        "create",
        "--base",
        base,
        "--head",
        branch,
        "--title",
        "chore: update all dependencies",
        "--body",
        body,
    )
    print(url)
    # GITHUB_TOKEN-created PRs may need approval; dispatch CI explicitly for the exact branch.
    run("gh", "workflow", "run", "ci.yml", "--ref", branch)
    summary = os.environ.get("GITHUB_STEP_SUMMARY")
    if summary:
        with Path(summary).open("a") as stream:
            stream.write(f"\nDependency pull request: {url}\n")


if __name__ == "__main__":
    main()

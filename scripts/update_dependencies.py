#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.12"
# dependencies = [
#     "packaging>=24.3.0",
#     "rich>=14.0.0",
# ]
# ///

"""Update Python dependencies, GitHub Actions, Docker digests, and pre-commit hooks.

USAGE
    update_dependencies.py [--dry-run] [--only ECOSYSTEM] [--allow-major]

    Run it from the root of the repo you want to update. The current working
    directory is that root; where this script lives does not matter. Ecosystems
    with nothing to update are skipped. Needs `uv`; also `gh` (actions) and
    `docker` (images) when those are used.

ECOSYSTEMS
    python   pyproject.toml + uv.lock: relax exact pins, `uv lock --upgrade`,
             then raise the minimum versions in pyproject.toml.
    actions  every `uses: owner/repo@ref` in .github/**/*.yml (workflows and
             composite actions) is pinned to a commit SHA with a `# vX.Y.Z` comment.
    docker   every FROM line in Dockerfile*, *.Dockerfile, Containerfile (found
             anywhere in the repo) is pinned to an image digest.
    hooks    `pre-commit autoupdate --freeze`.

OPTIONS
    --dry-run      Show what would change and leave every file as it was.
    --only X       Run a single ecosystem (python, actions, docker, hooks).
    --allow-major  Allow major upgrades. Without it, a new major release of an
                   action is reported as "held" and the current version is only
                   pinned in place; Python upper bounds (<N) are kept.

NO_AUTO_UPDATE
    Everything is pinned unless the line opts out. Put NO_AUTO_UPDATE in a comment on the
    same line, or in a comment on the line directly above. Any comment style
    works (#, //, ;, --, /* */, <!-- -->):

        - uses: actions/checkout@v7  # NO_AUTO_UPDATE
        # NO_AUTO_UPDATE keep floating so auto-updates do not break our scripts
        - uses: actions/checkout@v7
        FROM python:3.13-slim  # NO_AUTO_UPDATE

    Opted-out lines are left untouched and listed in the output.

NOTES
    Reusable workflows (owner/repo/.github/workflows/x.yml@ref) are pinned to the
    commit of their current ref, never moved to the repo's latest release.
    Branch refs (@main) are deliberate and left alone.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import shutil
import subprocess
import time
import tomllib
import urllib.parse
import urllib.request
from collections.abc import Mapping
from pathlib import Path

from packaging.requirements import InvalidRequirement, Requirement
from packaging.version import InvalidVersion, Version
from rich.console import Console
from rich.table import Table
from rich.text import Text

console = Console()
# The alias lives in this repo and is run from other checkouts. Update the
# directory the command was started in, which is the root of that repo.
ROOT = Path.cwd().resolve()
PYPROJECT = ROOT / "pyproject.toml"
UV_LOCK = ROOT / "uv.lock"
PRE_COMMIT = ROOT / ".pre-commit-config.yaml"


def run(
    command: list[str], *, cwd: Path | None = None, allow_not_found: bool = False
) -> subprocess.CompletedProcess[str]:
    result = subprocess.run(
        command,
        cwd=cwd or ROOT,
        capture_output=True,
        text=True,
        check=False,
    )
    if result.returncode != 0:
        if allow_not_found and "(HTTP 404)" in result.stderr:
            return result
        console.print(f"[bold red]Command failed:[/bold red] {' '.join(command)}")
        if result.stdout.strip():
            console.print(result.stdout)
        if result.stderr.strip():
            console.print(result.stderr)
        raise SystemExit(result.returncode)
    return result


DEPENDENCY_SECTIONS = {"project", "project.optional-dependencies", "dependency-groups"}
SPEC_RE = re.compile(r'"([^"\n]+)"')


def dependency_specs(text: str):
    """Yield requirement spans without rewriting TOML formatting or comments."""
    section = ""
    in_dependencies = False
    offset = 0
    for line in text.splitlines(keepends=True):
        stripped = line.strip()
        if stripped.startswith("["):
            section = stripped.strip("[]")
        if section == "project" and stripped.startswith("dependencies = ["):
            in_dependencies = True
        if section in DEPENDENCY_SECTIONS and (section != "project" or in_dependencies):
            # Comments can contain quoted examples; only inspect the TOML content.
            content = line.split("#", 1)[0]
            if "include-group" in content:
                offset += len(line)
                continue
            for match in SPEC_RE.finditer(content):
                try:
                    requirement = Requirement(match.group(1))
                except InvalidRequirement:
                    continue
                if requirement.url or pep508_name(requirement.name) == "pr-agent":
                    continue
                yield (
                    offset + match.start(1),
                    offset + match.end(1),
                    match.group(1),
                    requirement,
                )
        if section == "project" and stripped.endswith("]"):
            in_dependencies = False
        offset += len(line)


def pep508_name(spec: str) -> str:
    name = re.split(r"[<>=!~\[; ]", spec.strip(), maxsplit=1)[0]
    return re.sub(r"[-_.]+", "-", name).lower()


def parse_pyproject_direct() -> set[str]:
    return {
        pep508_name(req.name)
        for _, _, _, req in dependency_specs(PYPROJECT.read_text())
    }


def relax_spec(spec: str, req: Requirement, *, allow_major: bool = False) -> str:
    updated = spec
    for constraint in req.specifier:
        if constraint.operator == "==" and "*" not in constraint.version:
            updated = updated.replace(
                f"=={constraint.version}", f">={constraint.version}", 1
            )
            if req.marker:
                # Distinct pins under Python markers intentionally track different major lines.
                upper = Version(constraint.version).major + 1
                updated = updated.replace(
                    f">={constraint.version}", f">={constraint.version},<{upper}", 1
                )
        elif allow_major and constraint.operator == "<" and not req.marker:
            updated = re.sub(
                r",?\s*<" + re.escape(constraint.version) + r"(?=,|;|$)", "", updated
            )
    return updated


def relax_constraints(text: str, *, allow_major: bool = False) -> str:
    """Let uv resolve exact pins; retain marker-specific major lines and bounds."""
    for start, end, spec, req in reversed(list(dependency_specs(text))):
        text = (
            text[:start] + relax_spec(spec, req, allow_major=allow_major) + text[end:]
        )
    return text


def update_pyproject_constraints(
    locked_versions: dict[str, list[str]],
    *,
    original: str,
    allow_major: bool = False,
) -> list[tuple[str, str, str]]:
    changes = []
    text = original
    for start, end, spec, req in reversed(list(dependency_specs(original))):
        relaxed = Requirement(relax_spec(spec, req, allow_major=allow_major))
        candidates = [
            v
            for v in locked_versions.get(pep508_name(req.name), [])
            if Version(v) in relaxed.specifier
        ]
        if not candidates:
            continue
        version = max(candidates, key=Version)
        updated = spec
        for constraint in req.specifier:
            if constraint.operator in ("==", ">=") and "*" not in constraint.version:
                if Version(version) > Version(constraint.version):
                    updated = updated.replace(
                        f"{constraint.operator}{constraint.version}",
                        f"{constraint.operator}{version}",
                        1,
                    )
            elif (
                allow_major
                and constraint.operator == "<"
                and Version(version) not in req.specifier
            ):
                updated = updated.replace(
                    f"<{constraint.version}", f"<{Version(version).major + 1}", 1
                )
        if updated != spec:
            text = text[:start] + updated + text[end:]
            changes.append((pep508_name(req.name), spec, updated))
    PYPROJECT.write_text(text, encoding="utf-8")
    return list(reversed(changes))


def parse_uv_lock() -> dict[str, str]:
    if not UV_LOCK.is_file():
        return {}
    with UV_LOCK.open("rb") as handle:
        data = tomllib.load(handle)
    return {pkg["name"]: pkg["version"] for pkg in data.get("package", [])}


def version_parts(version: str) -> tuple[int, int, int]:
    cleaned = version.lstrip("v").split("-", 1)[0]
    parts: list[int] = []
    for piece in cleaned.split("."):
        digits = "".join(char for char in piece if char.isdigit())
        parts.append(int(digits) if digits else 0)
    while len(parts) < 3:
        parts.append(0)
    return parts[0], parts[1], parts[2]


def bump_type(old: str, new: str) -> str | None:
    old_parts = version_parts(old)
    new_parts = version_parts(new)
    if new_parts <= old_parts:
        return None
    if new_parts[0] > old_parts[0]:
        return "major"
    if new_parts[1] > old_parts[1]:
        return "minor"
    return "patch"


def collect_changes(
    before: Mapping[str, str],
    after: Mapping[str, str],
    *,
    direct: set[str] | None = None,
) -> dict[str, list[tuple[str, str, str]]]:
    changes: dict[str, list[tuple[str, str, str]]] = {
        "major": [],
        "minor": [],
        "patch": [],
    }
    for name in sorted(set(before) | set(after)):
        if direct is not None and name not in direct:
            continue
        old = before.get(name)
        new = after.get(name)
        if not old or not new or old == new:
            continue
        kind = bump_type(old, new)
        if kind:
            changes[kind].append((name, old, new))
    return changes


KIND_STYLE = {
    "major": "bold red",
    "minor": "yellow",
    "patch": "blue",
    "spec": "magenta",
    "pin": "yellow",
    "digest": "blue",
}


def short_rev(value: str) -> str:
    if re.fullmatch(r"(?:sha256:)?[0-9a-f]{12,64}", value):
        return value.removeprefix("sha256:")[:12]
    return value


def emit_section(
    title: str,
    rows: list[tuple[str, str, str, str, str]],
    *,
    extra: str = "",
) -> None:
    """Print one ecosystem as a colored count line plus borderless bump rows."""
    if not rows and not extra:
        console.print(f"[bold cyan]{title:<7}[/] [green]up to date[/]")
        return
    counts: dict[str, int] = {}
    for kind, *_rest in rows:
        counts[kind] = counts.get(kind, 0) + 1
    bits = [
        f"[{KIND_STYLE.get(kind, 'white')}]{count} {kind}[/]"
        for kind, count in counts.items()
    ]
    if extra:
        bits.append(f"[dim]{extra}[/]")
    console.print(f"[bold cyan]{title:<7}[/] " + "  ".join(bits))
    if not rows:
        return
    table = Table(
        box=None,
        show_header=False,
        pad_edge=False,
        padding=(0, 1),
        collapse_padding=True,
        expand=False,
    )
    table.add_column(min_width=6, no_wrap=True)
    table.add_column(style="cyan", no_wrap=True)
    table.add_column(style="dim", justify="right", no_wrap=True)
    table.add_column(style="dim", width=1, no_wrap=True)
    table.add_column(style="green", no_wrap=True)
    table.add_column(style="dim italic", no_wrap=True)
    for kind, name, old, new, note in rows:
        table.add_row(
            Text(kind, style=KIND_STYLE.get(kind, "white")),
            name,
            short_rev(old),
            "→",
            short_rev(new),
            note,
        )
    console.print(table)


def update_python(
    *, allow_major: bool = False, dry_run: bool = False
) -> tuple[dict[str, str], list[tuple[str, str, str]]]:
    original = PYPROJECT.read_text(encoding="utf-8")
    original_lock = UV_LOCK.read_bytes() if UV_LOCK.is_file() else None

    def restore() -> None:
        PYPROJECT.write_text(original, encoding="utf-8")
        if original_lock is None:
            UV_LOCK.unlink(missing_ok=True)
        else:
            UV_LOCK.write_bytes(original_lock)

    try:
        PYPROJECT.write_text(
            relax_constraints(original, allow_major=allow_major), encoding="utf-8"
        )
        run(["uv", "lock", "--upgrade"])
        with UV_LOCK.open("rb") as handle:
            packages = tomllib.load(handle).get("package", [])
        versions: dict[str, list[str]] = {}
        for package in packages:
            versions.setdefault(package["name"], []).append(package["version"])
        changes = update_pyproject_constraints(
            versions, original=original, allow_major=allow_major
        )
        if not dry_run:
            run(["uv", "lock"])
            run(["uv", "sync"])
        after = parse_uv_lock()
    except BaseException:
        restore()
        raise
    if dry_run:
        restore()
    return after, changes


ACTION_RE = re.compile(
    r"(?P<prefix>^\s*(?:-\s*)?uses:\s+)(?P<action>[\w.-]+/[\w./-]+)@"
    r"(?P<ref>[\w.-]+)(?P<comment>[^\n]*)",
    re.MULTILINE,
)
FROM_RE = re.compile(
    r"^(?P<prefix>[ \t]*FROM[ \t]+(?:--\S+[ \t]+)*)(?P<ref>[^\s@]+)"
    r"(?:@(?P<digest>sha256:[0-9a-f]{64}))?(?P<rest>[^\n]*)",
    re.MULTILINE | re.IGNORECASE,
)
STAGE_RE = re.compile(r"\bAS[ \t]+(\S+)", re.IGNORECASE)
VERSION_IN_COMMENT_RE = re.compile(
    r"(?<![\w.])(?:v\d+(?:\.\d+){0,2}|\d+\.\d+(?:\.\d+)?)\b", re.IGNORECASE
)

SKIP_DIRS = {".git", ".venv", "venv", "node_modules", ".tox", "__pycache__"}
COMMENT_STARTS = ("#", "//", ";", "--", "/*", "*", "<!--", "%", "'", "REM ")
# (file, name, ref) for every line left alone because of NO_AUTO_UPDATE.
NO_AUTO_UPDATE_SKIPS: list[tuple[str, str, str]] = []


def find_files(match) -> list[Path]:
    """Tracked and untracked-but-not-ignored files, or a plain walk outside git."""
    listed = subprocess.run(
        ["git", "ls-files", "-co", "--exclude-standard", "-z"],
        cwd=ROOT,
        capture_output=True,
        text=True,
        check=False,
    )
    if listed.returncode == 0:
        paths = (ROOT / name for name in listed.stdout.split("\0") if name)
        return sorted(p for p in paths if p.is_file() and match(p.name))
    found: list[Path] = []
    for dirpath, dirnames, filenames in os.walk(ROOT):
        dirnames[:] = sorted(d for d in dirnames if d not in SKIP_DIRS)
        found += [Path(dirpath) / n for n in sorted(filenames) if match(n)]
    return found


def is_dockerfile(name: str) -> bool:
    lower = name.lower()
    return lower.startswith(("dockerfile", "containerfile")) or lower.endswith(
        ".dockerfile"
    )


def find_dockerfiles() -> list[Path]:
    return find_files(is_dockerfile)


def find_action_files() -> list[Path]:
    return [
        p
        for p in find_files(lambda n: n.endswith((".yml", ".yaml")))
        if p.relative_to(ROOT).parts[:1] == (".github",)
    ]


def has_NO_AUTO_UPDATE(text: str, pos: int) -> bool:
    """NO_AUTO_UPDATE on the line holding `pos`, or in a comment on the line above."""
    start = text.rfind("\n", 0, pos) + 1
    end = text.find("\n", pos)
    if "NO_AUTO_UPDATE" in text[start : end if end != -1 else len(text)]:
        return True
    if start == 0:
        return False
    above = text[: start - 1].rsplit("\n", 1)[-1].strip()
    return "NO_AUTO_UPDATE" in above and above.startswith(COMMENT_STARTS)


def action_comment(existing: str, tag: str) -> str:
    """Comment after a pinned SHA naming the release that commit belongs to."""
    if VERSION_IN_COMMENT_RE.search(existing):
        return VERSION_IN_COMMENT_RE.sub(tag, existing, count=1)
    body = existing.strip()
    if body.startswith("#"):
        body = body[1:].strip()
    if body:
        return f" # {tag} {body}"
    return f" # {tag}"


def update_actions(
    *, dry_run: bool = False, allow_major: bool = False
) -> list[tuple[str, str, str, str, str]]:
    """Return table rows (kind, action, old, new, note) for each pin that moved."""
    rows: list[tuple[str, str, str, str, str]] = []
    latest: dict[str, tuple[str, str] | None] = {}
    commits: dict[tuple[str, str], str] = {}

    def commit_sha(repo: str, ref: str) -> str:
        if (repo, ref) not in commits:
            data = json.loads(run(["gh", "api", f"repos/{repo}/commits/{ref}"]).stdout)
            commits[(repo, ref)] = data["sha"]
        return commits[(repo, ref)]

    def latest_release(repo: str) -> tuple[str, str] | None:
        if repo not in latest:
            result = run(
                ["gh", "api", f"repos/{repo}/releases/latest"], allow_not_found=True
            )
            if result.returncode != 0:
                console.print(
                    f"[yellow]actions: no latest release for {repo}, skipped[/]"
                )
                latest[repo] = None
            else:
                tag = json.loads(result.stdout)["tag_name"]
                latest[repo] = (tag, commit_sha(repo, tag))
        return latest[repo]

    for path in find_action_files():
        rel = str(path.relative_to(ROOT))
        original = path.read_text()

        def replace(match: re.Match[str], rel: str = rel, text: str = original) -> str:
            action = match["action"]
            ref = match["ref"]
            repo = "/".join(action.split("/")[:2])
            if repo.lower() in {"kubecost/kc-pr-agent", "codium-ai/pr-agent"}:
                return match[0]
            if has_NO_AUTO_UPDATE(text, match.start("action")):
                NO_AUTO_UPDATE_SKIPS.append((rel, action, ref))
                return match[0]
            pinned = re.fullmatch(r"[0-9a-f]{40}", ref) is not None
            if pinned:
                label = VERSION_IN_COMMENT_RE.search(match["comment"])
                if not label:
                    return match[0]
                old = label.group(0)
            else:
                old = ref
            try:
                current = Version(old)
            except InvalidVersion:
                # Branch refs are deliberate selections, not release pins.
                return match[0]

            # Reusable workflows are pinned to their own ref, not the repo's latest release.
            in_place = ".github/workflows/" in action
            held = False
            tag = sha = ""
            if not in_place:
                release = latest_release(repo)
                if release is None:
                    return match[0]
                tag, sha = release
                try:
                    newest = Version(tag)
                except InvalidVersion:
                    # Latest release is not an action version (e.g. a tool bundle).
                    newest = None
                if newest is None or newest < current:
                    in_place = True
                    tag = ""
                elif newest.major > current.major and not allow_major:
                    rows.append(
                        ("major", action, old, tag, f"{rel} held, use --allow-major")
                    )
                    in_place = held = True
                    tag = ""
            if in_place:
                if pinned:
                    return match[0]
                tag, sha = ref, commit_sha(repo, ref)
            updated = f"{match['prefix']}{action}@{sha}{action_comment(match['comment'], tag)}"
            if updated == match[0]:
                return match[0]
            if not held:
                same_release = not pinned and current == Version(tag)
                new = sha[:12] if same_release or in_place else tag
                kind = bump_type(old, tag) or "pin"
                rows.append((kind, action, old, new, rel))
            return updated

        updated = ACTION_RE.sub(replace, original)
        if updated != original and not dry_run:
            path.write_text(updated)
    return rows


def image_digest(image: str) -> str:
    if image.startswith("public.ecr.aws/"):
        # Public ECR supports anonymous pulls. Fetch a fresh token instead of consulting
        # Docker's potentially expired operator credentials or a cached token response.
        repository, tag = image.removeprefix("public.ecr.aws/").rsplit(":", 1)
        query = urllib.parse.urlencode(
            {
                "service": "public.ecr.aws",
                "scope": f"repository:{repository}:pull",
                "t": time.time_ns(),
            }
        )
        with urllib.request.urlopen(
            f"https://public.ecr.aws/token/?{query}", timeout=30
        ) as response:
            token = json.load(response)["token"]
        request = urllib.request.Request(
            f"https://public.ecr.aws/v2/{repository}/manifests/{tag}",
            headers={
                "Authorization": f"Bearer {token}",
                "Accept": "application/vnd.oci.image.index.v1+json, "
                "application/vnd.docker.distribution.manifest.list.v2+json, "
                "application/vnd.oci.image.manifest.v1+json, "
                "application/vnd.docker.distribution.manifest.v2+json",
            },
        )
        with urllib.request.urlopen(request, timeout=30) as response:
            return "sha256:" + hashlib.sha256(response.read()).hexdigest()
    manifest = json.loads(
        run(
            [
                "docker",
                "buildx",
                "imagetools",
                "inspect",
                image,
                "--format",
                "{{json .Manifest}}",
            ]
        ).stdout
    )
    return manifest["digest"]


def update_docker(*, dry_run: bool = False) -> list[tuple[str, str, str, str, str]]:
    """Pin or refresh image digests. Return rows (kind, image, old, new, dockerfile)."""
    rows: list[tuple[str, str, str, str, str]] = []
    digests: dict[str, str] = {}
    for path in find_dockerfiles():
        rel = str(path.relative_to(ROOT))
        original = path.read_text()
        stages: set[str] = set()

        def replace(
            match: re.Match[str],
            rel: str = rel,
            text: str = original,
            stages: set[str] = stages,
        ) -> str:
            ref = match["ref"]
            is_stage = ref.lower() in stages
            stages.update(s.lower() for s in STAGE_RE.findall(match["rest"]))
            if is_stage or ref.lower() == "scratch" or "$" in ref:
                return match[0]
            if has_NO_AUTO_UPDATE(text, match.start()):
                NO_AUTO_UPDATE_SKIPS.append((rel, ref, match["digest"] or "unpinned"))
                return match[0]
            image = ref if ":" in ref.rsplit("/", 1)[-1] else f"{ref}:latest"
            if image not in digests:
                digest = image_digest(image)
                if not re.fullmatch(r"sha256:[0-9a-f]{64}", digest):
                    raise ValueError(f"Invalid registry digest for {image}: {digest}")
                digests[image] = digest
            if match["digest"] == digests[image] and image == ref:
                return match[0]
            rows.append(
                (
                    "digest" if match["digest"] else "pin",
                    image,
                    match["digest"] or "unpinned",
                    digests[image],
                    rel,
                )
            )
            return f"{match['prefix']}{image}@{digests[image]}{match['rest']}"

        updated = FROM_RE.sub(replace, original)
        if updated != original and not dry_run:
            path.write_text(updated)
    return rows


HOOK_UPDATE_RE = re.compile(
    r"Updating\s+(?P<repo>\S+).*?\bupdating\s+(?P<old>\S+)\s+->\s+(?P<new>\S+)"
)


def repo_label(repo: str) -> str:
    repo = repo.removesuffix(".git")
    for prefix in ("https://github.com/", "https://gitlab.com/", "git@"):
        if repo.startswith(prefix):
            return repo.removeprefix(prefix)
    return repo


def update_hooks(*, dry_run: bool = False) -> list[tuple[str, str, str]]:
    original = PRE_COMMIT.read_bytes()
    try:
        result = run(["uv", "run", "pre-commit", "autoupdate", "--freeze"])
    finally:
        if dry_run:
            PRE_COMMIT.write_bytes(original)
    changes: list[tuple[str, str, str]] = []
    for line in result.stdout.splitlines():
        match = HOOK_UPDATE_RE.search(line)
        if match:
            changes.append(
                (
                    repo_label(match["repo"]),
                    match["old"].rstrip("."),
                    match["new"].rstrip("."),
                )
            )
    return changes


def print_python(
    *,
    python_direct: set[str],
    python_before: dict[str, str],
    python_after: dict[str, str],
    pyproject_constraint_changes: list[tuple[str, str, str]],
) -> None:
    changes = collect_changes(python_before, python_after)
    rows: list[tuple[str, str, str, str, str]] = []
    listed: set[str] = set()
    for kind in ("major", "minor", "patch"):
        for name, old, new in changes[kind]:
            direct = name in python_direct
            if kind == "patch" and not direct:
                continue
            rows.append((kind, name, old, new, "direct" if direct else ""))
            listed.add(name)
    for _name, old, new in pyproject_constraint_changes:
        package = pep508_name(old)
        if package in listed:
            continue
        rows.append(("spec", package, old, new, "pyproject"))
    hidden = sum(
        1 for name, _old, _new in changes["patch"] if name not in python_direct
    )
    extra = ""
    if hidden:
        extra = (
            f"{hidden} transitive patch"
            if hidden == 1
            else f"{hidden} transitive patches"
        )
    emit_section("python", rows, extra=extra)


def print_actions(rows: list[tuple[str, str, str, str, str]]) -> None:
    emit_section("actions", rows)


def print_docker(rows: list[tuple[str, str, str, str, str]]) -> None:
    emit_section("docker", rows)


def print_NO_AUTO_UPDATE() -> None:
    for path, name, ref in NO_AUTO_UPDATE_SKIPS:
        console.print(
            f"[bold yellow]NO_AUTO_UPDATE[/]  {name}@{short_rev(ref)} left as-is [dim]({path})[/]"
        )


def print_hooks(changes: list[tuple[str, str, str]]) -> None:
    emit_section("hooks", [("pin", repo, old, new, "") for repo, old, new in changes])


def skip_reason(ecosystem: str) -> str | None:
    """Ecosystems with nothing to update stay out of the run.

    This file's own dependencies are declared in its script header, so a
    repository does not need a project lockfile for the script to run.
    """
    if ecosystem == "python" and not PYPROJECT.is_file():
        return "no pyproject.toml"
    if ecosystem == "actions" and not find_action_files():
        return "no .github workflow files"
    if ecosystem == "docker" and not find_dockerfiles():
        return "no Dockerfiles"
    if ecosystem == "hooks" and not PRE_COMMIT.is_file():
        return "no .pre-commit-config.yaml"
    return None


def main() -> None:
    parser = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Show what would change without modifying any file.",
    )
    parser.add_argument(
        "--only",
        choices=("python", "actions", "docker", "hooks"),
        help="Update one ecosystem. Default: python, actions, docker, and hooks.",
    )
    parser.add_argument(
        "--allow-major",
        action="store_true",
        help="Allow major upgrades (Python upper bounds, new action majors).",
    )
    args = parser.parse_args()
    selected = [args.only] if args.only else ["python", "actions", "docker", "hooks"]
    ecosystems: set[str] = set()
    for ecosystem in selected:
        reason = skip_reason(ecosystem)
        if reason is None:
            ecosystems.add(ecosystem)
            continue
        if args.only:
            parser.error(f"{ecosystem} updates need a project file ({reason})")
        console.print(f"[bold cyan]{ecosystem:<7}[/] [dim]skipped ({reason})[/]")
    required = {"uv"}
    if "actions" in ecosystems:
        required.add("gh")
    if "docker" in ecosystems:
        required.add("docker")
    for tool in sorted(required):
        if shutil.which(tool) is None:
            parser.error(f"Required tool not found: {tool}")
    if args.dry_run:
        console.print("[bold magenta]dry run[/] [dim]no files will be changed[/]")
    if "python" in ecosystems:
        with console.status("[cyan]python[/]", spinner="dots"):
            python_before = parse_uv_lock()
            python_direct = parse_pyproject_direct()
            python_after, changes = update_python(
                allow_major=args.allow_major, dry_run=args.dry_run
            )
        print_python(
            python_direct=python_direct,
            python_before=python_before,
            python_after=python_after,
            pyproject_constraint_changes=changes,
        )
    if "actions" in ecosystems:
        with console.status("[cyan]actions[/]", spinner="dots"):
            action_changes = update_actions(
                dry_run=args.dry_run, allow_major=args.allow_major
            )
        print_actions(action_changes)
    if "docker" in ecosystems:
        with console.status("[cyan]docker[/]", spinner="dots"):
            docker_changes = update_docker(dry_run=args.dry_run)
        print_docker(docker_changes)
    if "hooks" in ecosystems:
        with console.status("[cyan]hooks[/]", spinner="dots"):
            hook_changes = update_hooks(dry_run=args.dry_run)
        print_hooks(hook_changes)
    print_NO_AUTO_UPDATE()


if __name__ == "__main__":
    main()

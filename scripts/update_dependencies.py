#!/usr/bin/env python3
"""Update Python dependencies, GitHub Actions, Docker digests, and pre-commit hooks."""

from __future__ import annotations

import argparse
import hashlib
import json
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
ROOT = Path(__file__).resolve().parents[1]
PYPROJECT = ROOT / "pyproject.toml"
UV_LOCK = ROOT / "uv.lock"


def run(
    command: list[str], *, cwd: Path | None = None
) -> subprocess.CompletedProcess[str]:
    result = subprocess.run(
        command,
        cwd=cwd or ROOT,
        capture_output=True,
        text=True,
        check=False,
    )
    if result.returncode != 0:
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
    *, allow_major: bool = False
) -> tuple[dict[str, str], list[tuple[str, str, str]]]:
    original = PYPROJECT.read_text(encoding="utf-8")
    original_lock = UV_LOCK.read_bytes()
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
        run(["uv", "lock"])
    except BaseException:
        PYPROJECT.write_text(original, encoding="utf-8")
        UV_LOCK.write_bytes(original_lock)
        raise
    run(["uv", "sync"])
    return parse_uv_lock(), changes


ACTION_RE = re.compile(
    r"(?P<prefix>^\s*(?:-\s*)?uses:\s+)(?P<action>[\w.-]+/[\w./-]+)@"
    r"(?P<ref>[\w.-]+)(?P<comment>[^\n]*)",
    re.MULTILINE,
)
IMAGE_RE = re.compile(r"(?P<image>[\w./-]+:[\w.-]+)@sha256:[0-9a-f]{64}")
VERSION_IN_COMMENT_RE = re.compile(r"v?\d+\.\d+\.\d+")


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


def update_actions() -> list[tuple[str, str, str, str]]:
    """Return (workflow, action, old ref, new ref) for each pin that moved."""
    changes: list[tuple[str, str, str, str]] = []
    releases: dict[str, tuple[str, str]] = {}
    for path in sorted((ROOT / ".github/workflows").glob("*")):
        if path.suffix not in (".yml", ".yaml"):
            continue

        def replace(match: re.Match[str], workflow: Path = path) -> str:
            action = match["action"]
            repo = "/".join(action.split("/")[:2])
            if repo.lower() in {"kubecost/kc-pr-agent", "codium-ai/pr-agent"}:
                return match[0]
            pinned_sha = re.fullmatch(r"[0-9a-f]{40}", match["ref"])
            if not pinned_sha:
                try:
                    current = Version(match["ref"].removeprefix("v"))
                except InvalidVersion:
                    # Branch refs are deliberate selections, not release pins.
                    return match[0]
            elif not VERSION_IN_COMMENT_RE.search(match["comment"]):
                return match[0]
            if repo not in releases:
                release = json.loads(
                    run(["gh", "api", f"repos/{repo}/releases/latest"]).stdout
                )
                tag = release["tag_name"]
                ref = json.loads(
                    run(["gh", "api", f"repos/{repo}/commits/{tag}"]).stdout
                )
                releases[repo] = (tag, ref["sha"])
            tag, sha = releases[repo]
            comment = action_comment(match["comment"], tag)
            updated = f"{match['prefix']}{action}@{sha}{comment}"
            if updated == match[0]:
                return match[0]
            if pinned_sha:
                old_label = VERSION_IN_COMMENT_RE.search(match["comment"])
                old = old_label.group(0) if old_label else match["ref"][:7]
                new = tag
            else:
                old = match["ref"]
                same_release = current == Version(tag.removeprefix("v"))
                new = sha[:12] if same_release else tag
            changes.append((str(workflow.relative_to(ROOT)), action, old, new))
            return updated

        original = path.read_text()
        updated = ACTION_RE.sub(replace, original)
        if updated != original:
            path.write_text(updated)
    return changes


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
                "application/vnd.docker.distribution.manifest.list.v2+json",
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


def update_docker() -> list[tuple[str, str, str, str]]:
    """Refresh immutable digests. Return (dockerfile, image, old digest, new digest)."""
    changes: list[tuple[str, str, str, str]] = []
    digests: dict[str, str] = {}
    for path in sorted((ROOT / "docker").glob("Dockerfile*")):

        def replace(match: re.Match[str], dockerfile: Path = path) -> str:
            image = match["image"]
            if image not in digests:
                digest = image_digest(image)
                if not re.fullmatch(r"sha256:[0-9a-f]{64}", digest):
                    raise ValueError(f"Invalid registry digest for {image}: {digest}")
                digests[image] = digest
            updated = f"{image}@{digests[image]}"
            if updated != match[0]:
                changes.append(
                    (
                        str(dockerfile.relative_to(ROOT)),
                        image,
                        match[0].split("@", 1)[1],
                        digests[image],
                    )
                )
            return updated

        original = path.read_text()
        updated = IMAGE_RE.sub(replace, original)
        if updated != original:
            path.write_text(updated)
    return changes


HOOK_UPDATE_RE = re.compile(
    r"Updating\s+(?P<repo>\S+).*?\bupdating\s+(?P<old>\S+)\s+->\s+(?P<new>\S+)"
)


def repo_label(repo: str) -> str:
    repo = repo.removesuffix(".git")
    for prefix in ("https://github.com/", "https://gitlab.com/", "git@"):
        if repo.startswith(prefix):
            return repo.removeprefix(prefix)
    return repo


def update_hooks() -> list[tuple[str, str, str]]:
    result = run(["uv", "run", "pre-commit", "autoupdate", "--freeze"])
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


def print_actions(changes: list[tuple[str, str, str, str]]) -> None:
    emit_section(
        "actions",
        [("pin", action, old, new, path) for path, action, old, new in changes],
    )


def print_docker(changes: list[tuple[str, str, str, str]]) -> None:
    emit_section(
        "docker",
        [("digest", image, old, new, path) for path, image, old, new in changes],
    )


def print_hooks(changes: list[tuple[str, str, str]]) -> None:
    emit_section("hooks", [("pin", repo, old, new, "") for repo, old, new in changes])


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--only",
        choices=("python", "actions", "docker", "hooks"),
        help="Update one ecosystem. Default: python, actions, docker, and hooks.",
    )
    parser.add_argument(
        "--allow-major",
        action="store_true",
        help="Allow Python upgrades across upper bounds.",
    )
    args = parser.parse_args()
    ecosystems = {args.only} if args.only else {"python", "actions", "docker", "hooks"}
    required = {"uv"}
    if "actions" in ecosystems:
        required.add("gh")
    if "docker" in ecosystems:
        required.add("docker")
    for tool in sorted(required):
        if shutil.which(tool) is None:
            parser.error(f"Required tool not found: {tool}")
    if "python" in ecosystems:
        with console.status("[cyan]python[/]", spinner="dots"):
            python_before = parse_uv_lock()
            python_direct = parse_pyproject_direct()
            python_after, changes = update_python(allow_major=args.allow_major)
        print_python(
            python_direct=python_direct,
            python_before=python_before,
            python_after=python_after,
            pyproject_constraint_changes=changes,
        )
    if "actions" in ecosystems:
        with console.status("[cyan]actions[/]", spinner="dots"):
            action_changes = update_actions()
        print_actions(action_changes)
    if "docker" in ecosystems:
        with console.status("[cyan]docker[/]", spinner="dots"):
            docker_changes = update_docker()
        print_docker(docker_changes)
    if "hooks" in ecosystems:
        with console.status("[cyan]hooks[/]", spinner="dots"):
            hook_changes = update_hooks()
        print_hooks(hook_changes)


if __name__ == "__main__":
    main()

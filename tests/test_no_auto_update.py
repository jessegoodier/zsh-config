"""A NO_AUTO_UPDATE comment on a line, or on the line above it, blocks an update."""

from __future__ import annotations

import importlib.util
import json
import subprocess
import sys
from pathlib import Path

import pytest

_SCRIPT = Path(__file__).resolve().parents[1] / "scripts" / "update_dependencies.py"
_SPEC = importlib.util.spec_from_file_location(
    "update_dependencies_under_test", _SCRIPT
)
assert _SPEC is not None and _SPEC.loader is not None
updater = importlib.util.module_from_spec(_SPEC)
sys.modules[_SPEC.name] = updater
_SPEC.loader.exec_module(updater)

COMMENT_PREFIXES = ("#", "//", ";", "--", "/*", "*", "<!--", "%", "'", "REM")


@pytest.fixture(autouse=True)
def _clear_skip_lists():
    updater.NO_AUTO_UPDATE_SKIPS.clear()
    updater.DOCKER_LATEST_SKIPS.clear()
    updater._ACTION_FILES = None
    updater._DOCKERFILES = None
    yield
    updater.NO_AUTO_UPDATE_SKIPS.clear()
    updater.DOCKER_LATEST_SKIPS.clear()


@pytest.mark.parametrize("prefix", COMMENT_PREFIXES)
def test_same_line_comment_opts_out(prefix: str) -> None:
    text = f"FROM python:3.13-slim  {prefix} NO_AUTO_UPDATE\n"
    assert updater.has_NO_AUTO_UPDATE(text, text.index("FROM"))


@pytest.mark.parametrize("prefix", COMMENT_PREFIXES)
def test_previous_line_comment_opts_out(prefix: str) -> None:
    text = f"{prefix} NO_AUTO_UPDATE\nFROM python:3.13-slim\n"
    assert updater.has_NO_AUTO_UPDATE(text, text.index("FROM"))


def test_marker_two_lines_above_does_not_opt_out() -> None:
    text = "# NO_AUTO_UPDATE\n\nFROM python:3.13-slim\n"
    assert not updater.has_NO_AUTO_UPDATE(text, text.index("FROM"))


def test_marker_on_a_previous_code_line_does_not_opt_out() -> None:
    text = "ENV KEEP=NO_AUTO_UPDATE\nFROM python:3.13-slim\n"
    assert not updater.has_NO_AUTO_UPDATE(text, text.index("FROM"))


def test_relax_constraints_leaves_marked_requirements() -> None:
    text = """\
[project]
name = "demo"
version = "0.1.0"
dependencies = [
    "alpha==1.0.0",  # NO_AUTO_UPDATE
    # NO_AUTO_UPDATE
    "beta==1.2.3",
    "gamma==1.4.0",
]
"""
    updated = updater.relax_constraints(text)
    assert '"alpha==1.0.0"' in updated
    assert '"beta==1.2.3"' in updated
    assert '"gamma>=1.4.0"' in updated


def test_pyproject_constraints_leave_marked_requirements(
    monkeypatch: pytest.MonkeyPatch, tmp_path: Path
) -> None:
    text = """\
[project]
name = "demo"
version = "0.1.0"
dependencies = [
    "alpha==1.0.0",  # NO_AUTO_UPDATE
    # NO_AUTO_UPDATE
    "beta==1.2.3",
    "gamma==1.4.0",
]
"""
    pyproject = tmp_path / "pyproject.toml"
    pyproject.write_text(text, encoding="utf-8")
    monkeypatch.setattr(updater, "PYPROJECT", pyproject)

    changes = updater.update_pyproject_constraints(
        {"alpha": ["9.0.0"], "beta": ["9.0.0"], "gamma": ["2.0.0"]},
        original=text,
    )

    written = pyproject.read_text(encoding="utf-8")
    assert '"alpha==1.0.0"' in written
    assert '"beta==1.2.3"' in written
    assert '"gamma==2.0.0"' in written
    assert changes == [("gamma", "gamma==1.4.0", "gamma==2.0.0")]
    assert {spec for _path, spec, _ref in updater.NO_AUTO_UPDATE_SKIPS} == {
        "alpha==1.0.0",
        "beta==1.2.3",
    }


def test_freeze_holds_marked_requirements_at_the_locked_version() -> None:
    text = """\
[project]
name = "demo"
version = "0.1.0"
dependencies = [
    "botocore[crt]>=1.0",  # NO_AUTO_UPDATE
    "pkg>=1.0; python_version < '3.14'",  # NO_AUTO_UPDATE
    "gamma==1.4.0",
]
"""
    frozen = updater.freeze_opted_out(text, {"botocore": "1.2.3", "pkg": "4.5.6"})
    assert '"botocore[crt]==1.2.3"' in frozen
    assert "\"pkg==4.5.6; python_version < '3.14'\"" in frozen
    assert '"gamma==1.4.0"' in frozen


def test_python_upgrade_does_not_move_marked_requirements(
    monkeypatch: pytest.MonkeyPatch, tmp_path: Path
) -> None:
    original = """\
[project]
name = "demo"
version = "0.1.0"
dependencies = [
    "alpha>=1.0.0",  # NO_AUTO_UPDATE
    # NO_AUTO_UPDATE
    "beta>=1.0.0",
    "gamma==1.0.0",
]
"""
    pyproject = tmp_path / "pyproject.toml"
    lock = tmp_path / "uv.lock"
    pyproject.write_text(original, encoding="utf-8")
    lock.write_text(
        """\
version = 1
[[package]]
name = "alpha"
version = "1.2.0"
[[package]]
name = "beta"
version = "1.4.0"
[[package]]
name = "gamma"
version = "1.0.0"
""",
        encoding="utf-8",
    )
    monkeypatch.setattr(updater, "PYPROJECT", pyproject)
    monkeypatch.setattr(updater, "UV_LOCK", lock)
    seen: list[str] = []

    def fake_run(
        command: list[str], **_kwargs: object
    ) -> subprocess.CompletedProcess[str]:
        assert command == ["uv", "lock", "--upgrade"]
        seen.append(pyproject.read_text(encoding="utf-8"))
        lock.write_text(
            """\
version = 1
[[package]]
name = "alpha"
version = "1.2.0"
[[package]]
name = "beta"
version = "1.4.0"
[[package]]
name = "gamma"
version = "2.0.0"
""",
            encoding="utf-8",
        )
        return subprocess.CompletedProcess(command, 0, stdout="", stderr="")

    monkeypatch.setattr(updater, "run", fake_run)

    _after, changes = updater.update_python(dry_run=True)

    assert len(seen) == 1
    assert '"alpha==1.2.0"' in seen[0]
    assert '"beta==1.4.0"' in seen[0]
    assert '"gamma>=1.0.0"' in seen[0]
    assert changes == [("gamma", "gamma==1.0.0", "gamma==2.0.0")]
    assert pyproject.read_text(encoding="utf-8") == original


def test_actions_leave_marked_uses(
    monkeypatch: pytest.MonkeyPatch, tmp_path: Path
) -> None:
    workflow = tmp_path / ".github" / "workflows" / "ci.yml"
    workflow.parent.mkdir(parents=True)
    original = """\
name: CI
on: push
jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4  # NO_AUTO_UPDATE
      # NO_AUTO_UPDATE
      - uses: actions/checkout@v4
      - uses: actions/checkout@v4
"""
    workflow.write_text(original, encoding="utf-8")
    monkeypatch.setattr(updater, "ROOT", tmp_path)
    monkeypatch.setattr(updater, "find_action_files", lambda: [workflow])
    monkeypatch.setattr(updater, "github_freshness", lambda _repo: None)
    sha = "c" * 40

    def fake_run(
        command: list[str], **_kwargs: object
    ) -> subprocess.CompletedProcess[str]:
        api = command[-1]
        if api.endswith("/releases?per_page=100"):
            body = [
                {
                    "draft": False,
                    "prerelease": False,
                    "tag_name": "v9.0.0",
                    "published_at": "2020-01-01T00:00:00Z",
                }
            ]
            return subprocess.CompletedProcess(
                command, 0, stdout=json.dumps(body), stderr=""
            )
        if "/commits/" in api:
            return subprocess.CompletedProcess(
                command, 0, stdout=json.dumps({"sha": sha}), stderr=""
            )
        raise AssertionError(command)

    monkeypatch.setattr(updater, "run", fake_run)

    updater.update_actions(dry_run=False, allow_major=True, min_age_hours=0)

    lines = original.splitlines()
    lines[-1] = f"      - uses: actions/checkout@{sha} # v9.0.0"
    expected = "\n".join(lines) + "\n"
    assert workflow.read_text(encoding="utf-8") == expected
    assert len(updater.NO_AUTO_UPDATE_SKIPS) == 2
    assert {ref for _path, _name, ref in updater.NO_AUTO_UPDATE_SKIPS} == {"v4"}


def test_docker_leaves_marked_from_lines(
    monkeypatch: pytest.MonkeyPatch, tmp_path: Path
) -> None:
    dockerfile = tmp_path / "Dockerfile"
    original = """\
FROM python:3.12-slim  # NO_AUTO_UPDATE
# NO_AUTO_UPDATE
FROM golang:1.22.5-alpine
FROM node:20.18.0-alpine
"""
    dockerfile.write_text(original, encoding="utf-8")
    digest = "sha256:" + ("ab" * 32)
    monkeypatch.setattr(updater, "ROOT", tmp_path)
    monkeypatch.setattr(updater, "find_dockerfiles", lambda: [dockerfile])
    monkeypatch.setattr(updater, "image_freshness", lambda _image: None)
    monkeypatch.setattr(
        updater,
        "image_digest",
        lambda _image, *, ecr_tokens: digest,
    )

    updater.update_docker(dry_run=False, enable_latest=True)

    expected = original.replace(
        "FROM node:20.18.0-alpine",
        f"FROM node:20.18.0-alpine@{digest}",
    )
    assert dockerfile.read_text(encoding="utf-8") == expected
    skipped = {ref for _path, ref, _digest in updater.NO_AUTO_UPDATE_SKIPS}
    assert skipped == {"python:3.12-slim", "golang:1.22.5-alpine"}


def test_uv_image_bump_leaves_marked_lines(
    monkeypatch: pytest.MonkeyPatch, tmp_path: Path
) -> None:
    dockerfile = tmp_path / "Dockerfile"
    original = """\
FROM ghcr.io/astral-sh/uv:0.5.0  # NO_AUTO_UPDATE
# NO_AUTO_UPDATE
FROM ghcr.io/astral-sh/uv:0.5.1
FROM ghcr.io/astral-sh/uv:0.4.0
"""
    dockerfile.write_text(original, encoding="utf-8")
    monkeypatch.setattr(updater, "ROOT", tmp_path)
    monkeypatch.setattr(updater, "find_dockerfiles", lambda: [dockerfile])

    _rows, blocked = updater.bump_dockerfile_uv("0.9.0", dry_run=False)

    text = dockerfile.read_text(encoding="utf-8")
    assert "uv:0.5.0  # NO_AUTO_UPDATE" in text
    assert "uv:0.5.1\n" in text
    assert "uv:0.4.0" not in text
    assert "uv:0.9.0\n" in text
    assert blocked


def test_uv_build_floor_leaves_a_marked_requirement(
    monkeypatch: pytest.MonkeyPatch, tmp_path: Path
) -> None:
    pyproject = tmp_path / "pyproject.toml"
    marked = '[build-system]\nrequires = ["uv_build>=0.5.0"]  # NO_AUTO_UPDATE\n'
    pyproject.write_text(marked, encoding="utf-8")
    monkeypatch.setattr(updater, "PYPROJECT", pyproject)

    assert updater._write_uv_build_floor("0.9.0", False, raise_only=False) == []
    assert pyproject.read_text(encoding="utf-8") == marked

    plain = '[build-system]\nrequires = ["uv_build>=0.5.0"]\n'
    pyproject.write_text(plain, encoding="utf-8")
    changes = updater._write_uv_build_floor("0.9.0", False, raise_only=False)
    assert changes == [("uv_build", "uv_build>=0.5.0", "uv_build>=0.9.0")]
    assert '["uv_build>=0.9.0"]' in pyproject.read_text(encoding="utf-8")


def test_hooks_leave_marked_repos(
    monkeypatch: pytest.MonkeyPatch, tmp_path: Path
) -> None:
    config = tmp_path / ".pre-commit-config.yaml"
    original = """\
repos:
- repo: https://github.com/a/b
  rev: v1.0.0  # NO_AUTO_UPDATE
  hooks:
  - id: x
# NO_AUTO_UPDATE
- repo: https://github.com/c/d
  rev: v2.0.0
  hooks:
  - id: y
- repo: https://github.com/e/f
  rev: v3.0.0
  hooks:
  - id: z
"""
    config.write_text(original, encoding="utf-8")
    monkeypatch.setattr(updater, "PRE_COMMIT", config)
    sha_a = "a" * 40
    sha_c = "c" * 40
    sha_e = "e" * 40

    def fake_run(
        command: list[str], **_kwargs: object
    ) -> subprocess.CompletedProcess[str]:
        text = config.read_text(encoding="utf-8")
        text = (
            text.replace("v1.0.0", sha_a)
            .replace("v2.0.0", sha_c)
            .replace("v3.0.0", sha_e)
        )
        config.write_text(text, encoding="utf-8")
        stdout = "\n".join(
            [
                f"Updating https://github.com/a/b ... updating v1.0.0 -> {sha_a}.",
                f"Updating https://github.com/c/d ... updating v2.0.0 -> {sha_c}.",
                f"Updating https://github.com/e/f ... updating v3.0.0 -> {sha_e}.",
            ]
        )
        return subprocess.CompletedProcess(command, 0, stdout=stdout, stderr="")

    monkeypatch.setattr(updater, "run", fake_run)

    changes = updater.update_hooks(dry_run=False)

    written = config.read_text(encoding="utf-8")
    assert "rev: v1.0.0  # NO_AUTO_UPDATE" in written
    assert "rev: v2.0.0\n" in written
    assert f"rev: {sha_e}\n" in written
    assert sha_a not in written
    assert sha_c not in written
    assert changes == [("e/f", "v3.0.0", sha_e)]

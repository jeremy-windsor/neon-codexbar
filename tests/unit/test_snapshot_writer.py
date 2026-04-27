from __future__ import annotations

import json
import os
import stat
from pathlib import Path

import pytest

from neon_codexbar.adapter.normalizer import normalize_json
from neon_codexbar.ipc.snapshot_writer import (
    SCHEMA_VERSION,
    SNAPSHOT_PATH_ENV_VAR,
    build_snapshot,
    default_snapshot_path,
    write_snapshot,
)

FIXTURES = Path(__file__).resolve().parents[1] / "fixtures" / "codexbar"


def test_default_snapshot_path_uses_cache_home() -> None:
    assert default_snapshot_path().name == "snapshot.json"
    assert "neon-codexbar" in str(default_snapshot_path())


def test_default_snapshot_path_honors_env_override(
    monkeypatch: pytest.MonkeyPatch,
    tmp_path: Path,
) -> None:
    target = tmp_path / "custom" / "snap.json"
    monkeypatch.setenv(SNAPSHOT_PATH_ENV_VAR, str(target))
    assert default_snapshot_path() == target


def test_build_snapshot_includes_schema_and_codexbar_block() -> None:
    cards = normalize_json((FIXTURES / "codex_cli_success.json").read_text(encoding="utf-8"))
    payload = build_snapshot(
        cards=cards,
        diagnostics=["hello"],
        codexbar_path="/usr/bin/codexbar",
        codexbar_version="CodexBar 1.0.0",
    )

    assert payload["schema_version"] == SCHEMA_VERSION
    assert payload["ok"] is True
    assert payload["diagnostics"] == ["hello"]
    assert payload["codexbar"] == {
        "available": True,
        "path": "/usr/bin/codexbar",
        "version": "CodexBar 1.0.0",
    }
    assert payload["cards"][0]["provider_id"] == "codex"
    assert payload["generated_at"].endswith("Z")


def test_build_snapshot_marks_unavailable_when_codexbar_missing() -> None:
    payload = build_snapshot(
        cards=[],
        diagnostics=["CodexBar CLI not found"],
        codexbar_path=None,
        codexbar_version=None,
    )
    assert payload["ok"] is False
    assert payload["codexbar"]["available"] is False


def test_write_snapshot_atomic_rename_and_mode(tmp_path: Path) -> None:
    target = tmp_path / "snap.json"
    payload = build_snapshot(
        cards=[],
        diagnostics=[],
        codexbar_path="/x",
        codexbar_version="v",
    )
    written = write_snapshot(payload, target)

    assert written == target
    assert target.exists()
    # Sibling tmp file should not linger after rename.
    assert not (tmp_path / "snap.json.tmp").exists()
    # Mode should be user-only (0o600). Compare just the permission bits.
    mode = stat.S_IMODE(os.stat(target).st_mode)
    assert mode == 0o600
    # Round-trips as JSON with the schema version.
    loaded = json.loads(target.read_text(encoding="utf-8"))
    assert loaded["schema_version"] == SCHEMA_VERSION


def test_write_snapshot_creates_parent_directories(tmp_path: Path) -> None:
    target = tmp_path / "deeply" / "nested" / "snap.json"
    payload = build_snapshot(
        cards=[],
        diagnostics=[],
        codexbar_path=None,
        codexbar_version=None,
    )
    write_snapshot(payload, target)
    assert target.exists()

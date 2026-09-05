from __future__ import annotations

import json
import os
import subprocess
import sys
from datetime import UTC, datetime
from pathlib import Path

import pytest

from neon_codexbar.adapter.normalizer import normalize_payload
from neon_codexbar.cli import _dump_json

FIXTURES = Path(__file__).resolve().parents[1] / "fixtures" / "codexbar"
ROOT = Path(__file__).resolve().parents[2]


def _env() -> dict[str, str]:
    env = dict(os.environ)
    src = str(ROOT / "src")
    env["PYTHONPATH"] = f"{src}:{env.get('PYTHONPATH', '')}"
    return env


def test_cli_version_works() -> None:
    result = subprocess.run(
        [sys.executable, "-m", "neon_codexbar", "--version"],
        cwd=ROOT,
        env=_env(),
        capture_output=True,
        text=True,
        check=False,
    )

    assert result.returncode == 0
    assert "neon-codexbar" in result.stdout


def test_cli_fetch_json_against_fixture() -> None:
    result = subprocess.run(
        [
            sys.executable,
            "-m",
            "neon_codexbar",
            "fetch",
            "--json",
            "--fixture",
            str(FIXTURES / "openrouter_api_success.json"),
        ],
        cwd=ROOT,
        env=_env(),
        capture_output=True,
        text=True,
        check=False,
    )

    assert result.returncode == 0, result.stderr
    payload = json.loads(result.stdout)
    assert payload["ok"] is True
    assert payload["cards"][0]["provider_id"] == "openrouter"
    assert payload["cards"][0]["quota_windows"] == []
    assert payload["cards"][0]["credit_meters"][0]["balance"] == 3.48599225


def test_cli_fetch_error_fixture_returns_nonzero() -> None:
    result = subprocess.run(
        [
            sys.executable,
            "-m",
            "neon_codexbar",
            "fetch",
            "--json",
            "--fixture",
            str(FIXTURES / "representative_error.json"),
        ],
        cwd=ROOT,
        env=_env(),
        capture_output=True,
        text=True,
        check=False,
    )

    assert result.returncode == 1
    assert json.loads(result.stdout)["ok"] is False


def test_json_output_serializes_cards_before_redacting(capsys: pytest.CaptureFixture[str]) -> None:
    card = normalize_payload(
        {
            "provider": "codex",
            "usage": {
                "identity": {"email": "person@example.com", "apiKey": "dummy-value"},
                "primary": {"usedPercent": 12, "resetsAt": "2026-09-05T01:00:00Z"},
            },
        },
        attempted_at=datetime(2026, 9, 5, tzinfo=UTC),
    )

    _dump_json({"cards": [card], "command": None})

    payload = json.loads(capsys.readouterr().out)
    assert payload["command"] is None
    assert payload["cards"][0]["identity"] == {
        "email": "user@example.com",
        "apiKey": "[REDACTED]",
    }
    assert payload["cards"][0]["last_attempt"] == "2026-09-05T00:00:00Z"
    assert payload["cards"][0]["quota_windows"][0]["resets_at"] == "2026-09-05T01:00:00Z"


def test_cli_refresh_creates_private_sentinel(tmp_path: Path) -> None:
    snapshot = tmp_path / "cache" / "snapshot.json"
    result = subprocess.run(
        [
            sys.executable,
            "-m",
            "neon_codexbar",
            "refresh",
            "--json",
            "--snapshot-path",
            str(snapshot),
        ],
        cwd=ROOT,
        env=_env(),
        capture_output=True,
        text=True,
        check=False,
    )

    sentinel = snapshot.parent / "refresh.touch"
    assert result.returncode == 0, result.stderr
    assert json.loads(result.stdout)["ok"] is True
    assert sentinel.exists()
    assert sentinel.stat().st_mode & 0o777 == 0o600

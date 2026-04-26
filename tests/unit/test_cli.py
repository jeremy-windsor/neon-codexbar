from __future__ import annotations

import json
import os
import subprocess
import sys
from pathlib import Path

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
    assert payload["cards"][0]["credit_meters"][0]["balance"] == 74.5

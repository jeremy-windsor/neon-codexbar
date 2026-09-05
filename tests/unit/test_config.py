from __future__ import annotations

import json
from pathlib import Path

import pytest

from neon_codexbar.config import CODEXBAR_PATH_ENV_VAR, AppConfig, load_config


def test_config_loads_runtime_preferences_with_legacy_keys(
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    monkeypatch.delenv(CODEXBAR_PATH_ENV_VAR, raising=False)
    config_path = tmp_path / "config.json"
    config_path.write_text(
        json.dumps({
            "codexbar_path": "/custom/codexbar",
            "refresh_interval_seconds": 120,
            "version": 1,
            "warning_threshold_percent": 80,
            "critical_threshold_percent": 95,
            "provider_display_mode": "all-configured",
            "provider_overrides": {"codex": {"display_name": "Custom"}},
        }),
        encoding="utf-8",
    )

    assert load_config(config_path) == AppConfig(
        codexbar_path="/custom/codexbar",
        refresh_interval_seconds=120,
    )


def test_config_rejects_provider_secret_keys(tmp_path: Path) -> None:
    config_path = tmp_path / "config.json"
    config_path.write_text(
        json.dumps({"version": 1, "provider_overrides": {"zai": {"api_key": "nope"}}}),
        encoding="utf-8",
    )

    with pytest.raises(ValueError, match="must not contain provider secrets"):
        load_config(config_path)

from __future__ import annotations

import json
from pathlib import Path

import pytest

from neon_codexbar.config import load_config


def test_config_rejects_provider_secret_keys(tmp_path: Path) -> None:
    config_path = tmp_path / "config.json"
    config_path.write_text(
        json.dumps({"version": 1, "provider_overrides": {"zai": {"api_key": "nope"}}}),
        encoding="utf-8",
    )

    with pytest.raises(ValueError, match="must not contain provider secrets"):
        load_config(config_path)

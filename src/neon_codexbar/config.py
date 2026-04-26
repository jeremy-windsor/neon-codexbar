"""neon-codexbar UI-only configuration.

Provider credentials belong to CodexBar, provider CLIs, or CodexBar-supported
environment variables. This module deliberately stores only UI/runtime preferences.
"""

from __future__ import annotations

import json
import os
from dataclasses import dataclass, field, fields
from pathlib import Path
from typing import Any

CONFIG_ENV_VAR = "NEON_CODEXBAR_CONFIG"
CODEXBAR_PATH_ENV_VAR = "NEON_CODEXBAR_CODEXBAR_PATH"
SENSITIVE_CONFIG_KEY_FRAGMENTS = (
    "apikey",
    "api_key",
    "token",
    "secret",
    "cookie",
    "password",
    "authorization",
)


@dataclass(slots=True)
class AppConfig:
    """UI/runtime preferences owned by neon-codexbar."""

    version: int = 1
    codexbar_path: str | None = None
    refresh_interval_seconds: int = 300
    warning_threshold_percent: int = 70
    critical_threshold_percent: int = 90
    provider_display_mode: str = "enabled-only"
    provider_overrides: dict[str, dict[str, Any]] = field(default_factory=dict)

    @classmethod
    def from_dict(cls, data: dict[str, Any]) -> AppConfig:
        """Build config from a JSON dictionary, ignoring unknown keys."""

        known = {item.name for item in fields(cls)}
        return cls(**{key: value for key, value in data.items() if key in known})

    def to_dict(self) -> dict[str, Any]:
        """Return config as a serializable dictionary."""

        return {
            "version": self.version,
            "codexbar_path": self.codexbar_path,
            "refresh_interval_seconds": self.refresh_interval_seconds,
            "warning_threshold_percent": self.warning_threshold_percent,
            "critical_threshold_percent": self.critical_threshold_percent,
            "provider_display_mode": self.provider_display_mode,
            "provider_overrides": self.provider_overrides,
        }


def _contains_sensitive_key(value: Any) -> bool:
    if isinstance(value, dict):
        for key, item in value.items():
            normalized = str(key).replace("-", "_").lower()
            if any(fragment in normalized for fragment in SENSITIVE_CONFIG_KEY_FRAGMENTS):
                return True
            if _contains_sensitive_key(item):
                return True
    elif isinstance(value, list):
        return any(_contains_sensitive_key(item) for item in value)
    return False


def default_config_path() -> Path:
    """Return the default neon-codexbar config path."""

    override = os.environ.get(CONFIG_ENV_VAR)
    if override:
        return Path(override).expanduser()
    return Path.home() / ".config" / "neon-codexbar" / "config.json"


def load_config(path: Path | None = None) -> AppConfig:
    """Load UI-only config, returning defaults when the file does not exist."""

    config_path = path or default_config_path()
    if not config_path.exists():
        config = AppConfig()
    else:
        with config_path.open("r", encoding="utf-8") as handle:
            loaded = json.load(handle)
        if not isinstance(loaded, dict):
            raise ValueError(f"Config root must be an object: {config_path}")
        if _contains_sensitive_key(loaded):
            raise ValueError(
                "neon-codexbar config must not contain provider secrets; "
                "keep provider auth in CodexBar-supported locations"
            )
        config = AppConfig.from_dict(loaded)

    env_codexbar = os.environ.get(CODEXBAR_PATH_ENV_VAR)
    if env_codexbar:
        config.codexbar_path = env_codexbar
    return config

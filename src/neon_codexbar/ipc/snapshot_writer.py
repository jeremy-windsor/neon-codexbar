"""Atomic snapshot file producer for the daemon ↔ widget interface.

The widget reads ``~/.cache/neon-codexbar/snapshot.json``. The daemon writes it
by exclusively creating a private sibling temporary file and renaming it into place — that rename
is atomic on the same filesystem, which ``~/.cache`` always is.
"""

from __future__ import annotations

import json
import os
from pathlib import Path
from typing import Any

from neon_codexbar.ipc.private_file import write_private_file
from neon_codexbar.models import ProviderCard, to_jsonable, utc_now

SNAPSHOT_PATH_ENV_VAR = "NEON_CODEXBAR_SNAPSHOT_PATH"
SCHEMA_VERSION = 1


def default_snapshot_path() -> Path:
    """Return the configured snapshot path, honoring the env override."""

    override = os.environ.get(SNAPSHOT_PATH_ENV_VAR)
    if override:
        return Path(override).expanduser()
    return Path.home() / ".cache" / "neon-codexbar" / "snapshot.json"


def build_snapshot(
    *,
    cards: list[ProviderCard],
    diagnostics: list[str],
    codexbar_path: str | None,
    codexbar_version: str | None,
    ok: bool | None = None,
) -> dict[str, Any]:
    """Build the dict that will be serialized to ``snapshot.json``."""

    return {
        "schema_version": SCHEMA_VERSION,
        "generated_at": to_jsonable(utc_now()),
        "ok": bool(ok) if ok is not None else codexbar_path is not None,
        "cards": to_jsonable(cards),
        "diagnostics": list(diagnostics),
        "codexbar": {
            "available": codexbar_path is not None,
            "path": codexbar_path,
            "version": codexbar_version,
        },
    }


def write_snapshot(payload: dict[str, Any], path: Path | None = None) -> Path:
    """Atomically write ``payload`` to ``path`` (default: cache snapshot)."""

    target = path or default_snapshot_path()
    serialized = json.dumps(payload, sort_keys=True, indent=2)
    return write_private_file(target, serialized)

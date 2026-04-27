"""Atomic snapshot file producer for the daemon ↔ widget interface.

The widget reads ``~/.cache/neon-codexbar/snapshot.json``. The daemon writes it
by creating a sibling ``*.tmp`` file and renaming it into place — that rename
is atomic on the same filesystem, which ``~/.cache`` always is.
"""

from __future__ import annotations

import json
import os
from pathlib import Path
from typing import Any

from neon_codexbar.models import ProviderCard, dataclass_asdict, to_jsonable, utc_now

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
        "cards": [dataclass_asdict(card) for card in cards],
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
    target.parent.mkdir(parents=True, exist_ok=True)
    tmp = target.with_suffix(target.suffix + ".tmp")
    serialized = json.dumps(payload, sort_keys=True, indent=2)
    with tmp.open("w", encoding="utf-8") as handle:
        handle.write(serialized)
        handle.flush()
        os.fsync(handle.fileno())
    os.chmod(tmp, 0o600)
    tmp.replace(target)
    return target

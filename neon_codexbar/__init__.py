"""Source-checkout shim for ``python -m neon_codexbar``.

The installable package lives under ``src/``. This shim keeps the Phase 1
acceptance command working directly from a fresh checkout without requiring an
editable install first.
"""

from __future__ import annotations

from pathlib import Path

_SRC_PACKAGE = Path(__file__).resolve().parents[1] / "src" / "neon_codexbar"
if _SRC_PACKAGE.is_dir():
    __path__.insert(0, str(_SRC_PACKAGE))  # type: ignore[name-defined]

__version__ = "0.1.0"

__all__ = ["__version__"]

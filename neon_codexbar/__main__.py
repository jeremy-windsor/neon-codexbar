"""Source-checkout entry point for ``python -m neon_codexbar``."""

from __future__ import annotations

from .cli import main

if __name__ == "__main__":
    raise SystemExit(main())

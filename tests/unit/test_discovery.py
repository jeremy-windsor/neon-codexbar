from __future__ import annotations

from pathlib import Path

from neon_codexbar.adapter.discovery import parse_config_dump

FIXTURES = Path(__file__).resolve().parents[1] / "fixtures" / "codexbar"


def test_discovery_parses_config_fixture() -> None:
    entries = parse_config_dump((FIXTURES / "config_dump.json").read_text(encoding="utf-8"))
    by_id = {entry.provider_id: entry for entry in entries}

    assert by_id["codex"].enabled is True
    assert by_id["codex"].source == "cli"
    assert by_id["claude"].source == "cli"
    assert by_id["zai"].source == "api"
    assert by_id["openrouter"].source == "api"
    assert by_id["unknown-provider"].skipped is True
    assert by_id["unknown-provider"].source is None
    assert by_id["unknown-provider"].diagnostic

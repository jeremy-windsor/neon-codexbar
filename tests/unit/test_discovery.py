from __future__ import annotations

from pathlib import Path

from neon_codexbar.adapter.discovery import discover, parse_config_dump
from neon_codexbar.models import CommandResult

FIXTURES = Path(__file__).resolve().parents[1] / "fixtures" / "codexbar"


class _ConfigDumpRunner:
    def __init__(self, payload: str) -> None:
        self.payload = payload

    def config_dump(self) -> CommandResult:
        return CommandResult(
            command=["codexbar", "config", "dump"],
            stdout=self.payload,
            stderr="",
            exit_code=0,
            timed_out=False,
            duration_seconds=0.0,
        )


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


def test_disabled_unknown_provider_keeps_entry_but_does_not_warn() -> None:
    raw = """
    {
      "version": 1,
      "providers": [
        {"id": "codex", "enabled": true},
        {"id": "unknown-disabled", "enabled": false},
        {"id": "unknown-enabled", "enabled": true}
      ]
    }
    """
    entries = parse_config_dump(raw)
    by_id = {entry.provider_id: entry for entry in entries}

    assert by_id["unknown-disabled"].skipped is True
    assert by_id["unknown-disabled"].diagnostic
    assert by_id["unknown-enabled"].skipped is True
    assert by_id["unknown-enabled"].diagnostic


def test_discover_warns_only_for_enabled_unknown_providers() -> None:
    raw = """
    {
      "version": 1,
      "providers": [
        {"id": "codex", "enabled": true},
        {"id": "unknown-disabled", "enabled": false},
        {"id": "unknown-enabled", "enabled": true}
      ]
    }
    """

    result = discover(_ConfigDumpRunner(raw))  # type: ignore[arg-type]

    assert result.ok is True
    assert len(result.diagnostics) == 1
    assert "unknown-enabled" in result.diagnostics[0]
    assert "unknown-disabled" not in result.diagnostics[0]

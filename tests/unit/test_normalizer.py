from __future__ import annotations

from pathlib import Path

from neon_codexbar.adapter.normalizer import normalize_json
from neon_codexbar.models import ProviderCard

FIXTURES = Path(__file__).resolve().parents[1] / "fixtures" / "codexbar"


def _normalize(name: str) -> ProviderCard:
    return normalize_json((FIXTURES / name).read_text(encoding="utf-8"))[0]


def test_normalizer_handles_codex_primary_secondary_windows() -> None:
    card = _normalize("codex_cli_success.json")

    assert card.provider_id == "codex"
    assert card.display_name == "Codex"
    assert card.source == "cli"
    assert [window.id for window in card.quota_windows] == ["primary", "secondary"]
    assert card.quota_windows[0].used_percent == 12.0
    assert card.quota_windows[1].window_minutes == 10080
    assert card.credit_meters[0].balance == 42.0
    assert card.error_message is None


def test_normalizer_handles_claude_primary_secondary_windows() -> None:
    card = _normalize("claude_cli_success.json")

    assert card.provider_id == "claude"
    assert card.display_name == "Claude Code"
    assert [window.id for window in card.quota_windows] == ["primary", "secondary"]
    assert card.quota_windows[0].reset_description == "3pm (America/Phoenix)"
    assert card.quota_windows[1].resets_at is not None


def test_normalizer_handles_zai_primary_secondary_tertiary_windows() -> None:
    card = _normalize("zai_api_success.json")

    assert card.provider_id == "zai"
    assert [window.id for window in card.quota_windows] == ["primary", "secondary", "tertiary"]
    assert [window.window_label for window in card.quota_windows] == [
        "Window 1",
        "Window 2",
        "Window 3",
    ]
    assert card.credit_meters == []


def test_normalizer_handles_openrouter_credit_balance_without_fake_windows() -> None:
    card = _normalize("openrouter_api_success.json")

    assert card.provider_id == "openrouter"
    assert card.quota_windows == []
    assert len(card.credit_meters) == 1
    meter = card.credit_meters[0]
    assert meter.label == "OpenRouter Balance"
    assert meter.balance == 74.5
    assert meter.used == 25.5
    assert meter.total == 100.0
    assert meter.used_percent == 25.5


def test_normalizer_handles_error_payload() -> None:
    card = _normalize("representative_error.json")

    assert card.provider_id == "zai"
    assert card.error_message is not None
    assert card.setup_hint is not None
    assert card.last_success is None

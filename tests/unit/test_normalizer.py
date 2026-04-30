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
    assert card.source == "codex-cli"
    assert [window.id for window in card.quota_windows] == ["primary", "secondary"]
    assert card.quota_windows[0].used_percent == 55.0
    assert card.quota_windows[0].window_label == "5-hour window"
    assert card.quota_windows[1].window_minutes == 10080
    assert card.quota_windows[1].window_label == "7-day window"
    assert card.credit_meters[0].balance == 42.0
    assert card.error_message is None


def test_normalizer_handles_claude_primary_secondary_windows() -> None:
    card = _normalize("claude_cli_success.json")

    assert card.provider_id == "claude"
    assert card.display_name == "Claude Code"
    assert [window.id for window in card.quota_windows] == ["primary", "secondary"]
    # Live claude primary lacks resetsAt and resetDescription entirely.
    assert card.quota_windows[0].reset_description is None
    assert card.quota_windows[0].resets_at is None
    assert card.quota_windows[0].window_minutes == 300
    assert card.quota_windows[0].window_label == "5-hour window"
    assert card.quota_windows[1].resets_at is not None
    assert card.quota_windows[1].window_minutes == 10080
    assert card.quota_windows[1].window_label == "7-day window"


def test_normalizer_handles_zai_reliable_quota_windows() -> None:
    card = _normalize("zai_api_success.json")

    assert card.provider_id == "zai"
    assert [window.id for window in card.quota_windows] == ["primary", "tertiary"]
    assert [window.window_label for window in card.quota_windows] == [
        "7-day window",
        "5-hour window",
    ]
    assert card.credit_meters == []


def test_normalizer_handles_openrouter_credit_balance_without_fake_windows() -> None:
    card = _normalize("openrouter_api_success.json")

    assert card.provider_id == "openrouter"
    assert card.quota_windows == []
    # Live OpenRouter exposes both an account balance meter and a per-key usage meter.
    assert len(card.credit_meters) == 2
    balance = card.credit_meters[0]
    assert balance.label == "OpenRouter Balance"
    assert balance.balance == 3.48599225
    assert balance.used == 1.51400775
    assert balance.total == 5.0
    assert balance.used_percent == 30.280154999999997
    key_meter = card.credit_meters[1]
    assert key_meter.label == "OpenRouter Key Quota"
    assert key_meter.used == 1.09768035


def test_normalizer_drops_zai_unreliable_one_minute_window() -> None:
    """z.ai reports a one-minute window without enough metadata to display."""

    card = _normalize("zai_api_success.json")

    assert all(window.id != "secondary" for window in card.quota_windows)


def test_normalizer_handles_error_payload() -> None:
    card = _normalize("representative_error.json")

    assert card.provider_id == "zai"
    assert card.error_message is not None
    assert card.setup_hint is not None
    assert card.last_success is None

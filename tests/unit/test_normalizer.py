from __future__ import annotations

from datetime import UTC, datetime
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


def test_normalizer_handles_claude_oauth_nested_usage_windows() -> None:
    card = _normalize("claude_oauth_success.json")

    assert card.provider_id == "claude"
    assert card.display_name == "Claude Code"
    assert card.source == "oauth"
    assert [window.id for window in card.quota_windows] == [
        "primary",
        "secondary",
        "claude-routines",
    ]
    assert [window.window_label for window in card.quota_windows] == [
        "5-hour window",
        "7-day window",
        "Daily Routines",
    ]
    assert card.login_method == "Claude Pro"
    assert card.error_message is None


def test_normalizer_handles_zai_reliable_quota_windows() -> None:
    card = _normalize("zai_api_success.json")

    assert card.provider_id == "zai"
    assert [window.id for window in card.quota_windows] == ["tertiary", "primary"]
    assert [window.window_label for window in card.quota_windows] == [
        "5-hour window",
        "7-day window",
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


def test_normalizer_labels_grok_primary_window_like_codexbar() -> None:
    attempted_at = datetime(2026, 7, 11, 14, 36, 13, tzinfo=UTC)
    card = normalize_json(
        (FIXTURES / "grok_web_success.json").read_text(encoding="utf-8"),
        attempted_at=attempted_at,
    )[0]

    assert card.provider_id == "grok"
    assert card.display_name == "Grok"
    assert card.source == "grok-web"
    assert card.plan == "SuperGrok"
    assert [window.id for window in card.quota_windows] == ["primary"]
    assert card.quota_windows[0].used_percent == 66.0
    assert card.quota_windows[0].window_label == "Weekly"
    assert card.last_success == attempted_at
    assert card.error_message is None


def test_success_without_provider_updated_at_uses_fetch_time() -> None:
    attempted_at = datetime(2026, 7, 11, 15, 0, 0, tzinfo=UTC)
    card = normalize_json(
        '{"provider":"codex","source":"cli","usage":'
        '{"primary":{"usedPercent":10,"windowMinutes":300}}}',
        attempted_at=attempted_at,
    )[0]

    assert card.error_message is None
    assert card.last_success == attempted_at


def test_normalizer_drops_zai_unreliable_one_minute_window() -> None:
    """z.ai reports a one-minute window without enough metadata to display."""

    card = _normalize("zai_api_success.json")

    assert all(window.id != "secondary" for window in card.quota_windows)


def test_normalizer_handles_error_payload() -> None:
    card = _normalize("representative_error.json")

    assert card.provider_id == "zai"
    assert card.error_message is not None
    assert card.error_title == "Z.ai usage is unavailable"
    assert card.error_severity == "error"
    assert card.setup_hint is not None
    assert "Z_AI_API_KEY" in card.setup_hint
    assert "Coding Plan" in card.setup_hint
    assert card.last_success is None


def test_codex_rpc_timeout_gets_readable_warning_and_recovery_hint() -> None:
    card = normalize_json(
        '[{"provider":"codex","source":"codex-cli","error":{"message":'
        '"Codex RPC timed out waiting for `account/rateLimits/read` reply."}}]'
    )[0]

    assert card.error_message == (
        "Codex RPC timed out waiting for `account/rateLimits/read` reply."
    )
    assert card.error_title == "Codex usage check timed out"
    assert card.error_severity == "warning"
    assert card.setup_hint is not None
    assert "codex login" in card.setup_hint


def test_codex_auth_error_gets_direct_login_instruction() -> None:
    card = normalize_json(
        '[{"provider":"codex","source":"oauth","error":{"message":'
        '"Codex authentication token is missing."}}]'
    )[0]

    assert card.error_title == "Codex sign-in required"
    assert card.error_severity == "error"
    assert card.setup_hint == "Run codex login in a terminal, then click Refresh."

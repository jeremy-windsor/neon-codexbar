from __future__ import annotations

from neon_codexbar.diagnostics import (
    EMAIL_PLACEHOLDER,
    SECRET_PLACEHOLDER,
    redact_secrets,
    redact_string,
)


def test_diagnostics_redacts_token_like_strings() -> None:
    raw = "Authorization: Bearer sk-testsecretvalue1234567890 for person@example.com"
    redacted = redact_string(raw)

    assert SECRET_PLACEHOLDER in redacted
    assert EMAIL_PLACEHOLDER in redacted
    assert "sk-testsecretvalue" not in redacted
    assert "person@example.com" not in redacted


def test_diagnostics_redacts_sensitive_keys() -> None:
    payload = {"apiKey": "abc123", "nested": {"refresh_token": "def456"}}

    assert redact_secrets(payload) == {
        "apiKey": SECRET_PLACEHOLDER,
        "nested": {"refresh_token": SECRET_PLACEHOLDER},
    }

from __future__ import annotations

import json

import pytest

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


@pytest.mark.parametrize("key", ["apiKey", "access_token", "password", r"api\u004bey"])
def test_redacts_json_strings_and_preserves_provider_data(key: str) -> None:
    raw = '{"' + key + '": "dummy value with spaces", "usedPercent": 12}'
    result = json.loads(redact_string(raw))
    assert "dummy" not in json.dumps(result)
    assert result["usedPercent"] == 12


def test_redacts_nested_json_strings_and_arrays() -> None:
    inner = json.dumps({"refresh_token": "dummy-value"})
    outer = json.dumps([{"stdout": json.dumps(inner)}])
    result = json.loads(redact_string(outer))
    assert json.loads(json.loads(result[0]["stdout"])) == {
        "refresh_token": SECRET_PLACEHOLDER,
    }


def test_redacts_json_embedded_in_error_text() -> None:
    raw = r'error: {"api\u004bey": "dummy-value"} next: {"password": "dummy-password"}'
    result = redact_string(raw)
    assert "dummy" not in result
    assert result.startswith("error: ")
    assert " next: " in result


def test_json_redaction_preserves_identity_opt_out() -> None:
    raw = json.dumps({"email": "person@example.com", "token": "dummy-value"})
    result = json.loads(redact_string(raw, redact_identity=False))
    assert result == {"email": "person@example.com", "token": SECRET_PLACEHOLDER}
    assert json.loads(redact_string(raw))["email"] == EMAIL_PLACEHOLDER


def test_redacts_truncated_json_and_plain_password_assignment() -> None:
    assert "dummy" not in redact_string('error: {"apiKey": "dummy value",')
    assert "dummy" not in redact_string("password='dummy value'")


def test_redacts_bearer_without_token_prefix() -> None:
    assert "dummy" not in redact_string("Authorization: Bearer dummycredential12345")


@pytest.mark.parametrize("secret", ["abc[123]def", "abc{\"nested\":1}def", "abc[1,2]def"])
def test_json_fragments_do_not_split_quoted_credentials(secret: str) -> None:
    assert redact_string(f"password='{secret}'") == f"password='{SECRET_PLACEHOLDER}'"


def test_prefixed_json_with_container_secret_is_redacted() -> None:
    result = redact_string('error: {"password": {"nested": "dummy-secret"}}')
    assert result == 'error: {"password": "[REDACTED]"}'


@pytest.mark.parametrize("depth", [500, 1000, 2000])
def test_excessively_nested_json_fails_closed(depth: int) -> None:
    raw = '[' * depth + '{"apiKey":"dummy-value"}' + ']' * depth
    result = redact_string(raw)
    assert "dummy" not in result
    assert SECRET_PLACEHOLDER in result

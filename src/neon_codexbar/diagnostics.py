"""Diagnostics helpers with conservative redaction."""

from __future__ import annotations

import re
from typing import Any

SECRET_PLACEHOLDER = "[REDACTED]"
EMAIL_PLACEHOLDER = "user@example.com"

_SECRET_ASSIGNMENT_PATTERNS = [
    re.compile(
        r"(?i)\b(api[_-]?key|access[_-]?token|refresh[_-]?token|id[_-]?token|token|secret|cookie|authorization)"
        r"(\s*[:=]\s*)(['\"]?)([^'\"\s,;}]+)"
    ),
    re.compile(r"(?i)\b(bearer)(\s+)([A-Za-z0-9._~+/=-]{12,})"),
]

_TOKEN_VALUE_PATTERNS = [
    re.compile(r"\b(sk-[A-Za-z0-9][A-Za-z0-9_-]{10,})\b"),
    re.compile(r"\b([A-Za-z0-9_-]{24,}\.[A-Za-z0-9_-]{12,}\.[A-Za-z0-9_-]{12,})\b"),
]

_EMAIL_PATTERN = re.compile(r"\b[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}\b")

_SENSITIVE_KEY_PATTERN = re.compile(
    r"(?i)(api[_-]?key|access[_-]?token|refresh[_-]?token|id[_-]?token|token|secret|cookie|authorization|password)"
)


def redact_string(value: str, *, redact_identity: bool = True) -> str:
    """Redact token-like strings and optional email identities from text."""

    redacted = value
    for pattern in _SECRET_ASSIGNMENT_PATTERNS:
        if pattern.pattern.lower().startswith("(?i)\\b(bearer"):
            redacted = pattern.sub(
                lambda match: f"{match.group(1)}{match.group(2)}{SECRET_PLACEHOLDER}",
                redacted,
            )
        else:
            redacted = pattern.sub(
                lambda match: (
                    f"{match.group(1)}{match.group(2)}"
                    f"{match.group(3)}{SECRET_PLACEHOLDER}"
                ),
                redacted,
            )
    for pattern in _TOKEN_VALUE_PATTERNS:
        redacted = pattern.sub(SECRET_PLACEHOLDER, redacted)
    if redact_identity:
        redacted = _EMAIL_PATTERN.sub(EMAIL_PLACEHOLDER, redacted)
    return redacted


def redact_secrets(value: Any, *, redact_identity: bool = True) -> Any:
    """Recursively redact secrets from diagnostics payloads."""

    if isinstance(value, str):
        return redact_string(value, redact_identity=redact_identity)
    if isinstance(value, list):
        return [redact_secrets(item, redact_identity=redact_identity) for item in value]
    if isinstance(value, tuple):
        return [redact_secrets(item, redact_identity=redact_identity) for item in value]
    if isinstance(value, dict):
        redacted: dict[str, Any] = {}
        for key, item in value.items():
            key_str = str(key)
            if _SENSITIVE_KEY_PATTERN.search(key_str):
                redacted[key_str] = SECRET_PLACEHOLDER if item not in (None, "") else item
            else:
                redacted[key_str] = redact_secrets(item, redact_identity=redact_identity)
        return redacted
    return value


def diagnostic_error(message: str, *, code: str = "diagnostic_error") -> dict[str, str]:
    """Build a redacted diagnostic error object."""

    return {"code": code, "message": redact_string(message)}

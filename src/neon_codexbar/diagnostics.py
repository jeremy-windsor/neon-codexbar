"""Diagnostics helpers with conservative redaction."""

from __future__ import annotations

import json
import re
from typing import Any

SECRET_PLACEHOLDER = "[REDACTED]"
EMAIL_PLACEHOLDER = "user@example.com"

_BEARER_PATTERN = re.compile(r"(?i)\b(bearer)(\s+)([A-Za-z0-9._~+/=-]{12,})")
_SECRET_ASSIGNMENT_PATTERN = re.compile(
    r"(?i)\b(api[_-]?key|access[_-]?token|refresh[_-]?token|id[_-]?token|token|secret|cookie|authorization|password)"
    r"([\"']?\s*[:=]\s*)(\"(?:\\.|[^\"\\])*\"|'(?:\\.|[^'\\])*'|[^'\"\s,;}]+)"
)

_TOKEN_VALUE_PATTERNS = [
    re.compile(r"\b(sk-[A-Za-z0-9][A-Za-z0-9_-]{10,})\b"),
    re.compile(r"\b([A-Za-z0-9_-]{24,}\.[A-Za-z0-9_-]{12,}\.[A-Za-z0-9_-]{12,})\b"),
]

_EMAIL_PATTERN = re.compile(r"\b[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}\b")

_SENSITIVE_KEY_PATTERN = re.compile(
    r"(?i)(api[_-]?key|access[_-]?token|refresh[_-]?token|id[_-]?token|token|secret|cookie|authorization|password)"
)


def _redact_assignment(match: re.Match[str]) -> str:
    quote = match.group(3)[0] if match.group(3)[0] in "\"'" else ""
    return f"{match.group(1)}{match.group(2)}{quote}{SECRET_PLACEHOLDER}{quote}"


def _redact_plain_text(value: str, *, redact_identity: bool) -> str:
    """Fallback for ordinary text and incomplete JSON."""

    redacted = _BEARER_PATTERN.sub(
        lambda match: f"{match.group(1)}{match.group(2)}{SECRET_PLACEHOLDER}", value,
    )
    redacted = _SECRET_ASSIGNMENT_PATTERN.sub(_redact_assignment, redacted)
    for pattern in _TOKEN_VALUE_PATTERNS:
        redacted = pattern.sub(SECRET_PLACEHOLDER, redacted)
    if redact_identity:
        redacted = _EMAIL_PATTERN.sub(EMAIL_PLACEHOLDER, redacted)
    return redacted


def redact_string(value: str, *, redact_identity: bool = True) -> str:
    """Redact JSON structurally while keeping subprocess output as text."""

    try:
        return _redact_json_text(value, redact_identity=redact_identity)
    except RecursionError:
        # Fail closed on excessively nested input rather than leaking it or
        # crashing provider discovery. The replacement remains valid JSON.
        return json.dumps(SECRET_PLACEHOLDER)


def _redact_json_text(value: str, *, redact_identity: bool) -> str:
    try:
        parsed = json.loads(value)
    except (json.JSONDecodeError, ValueError):
        pass
    else:
        if isinstance(parsed, (dict, list, str)):
            return json.dumps(redact_secrets(parsed, redact_identity=redact_identity))

    # Protect whole quoted credentials before scanning JSON-looking fragments
    # inside them, e.g. password="abc[123]def". Leave container values intact
    # so their contents can still be parsed and redacted structurally.
    value = _SECRET_ASSIGNMENT_PATTERN.sub(
        lambda match: _redact_assignment(match)
        if match.group(3)[0] in "\"'" else match.group(0),
        value,
    )
    # Error messages can contain JSON after a prefix, or several JSON records.
    decoder = json.JSONDecoder()
    chunks: list[str] = []
    end = 0
    for match in re.finditer(r"[\[{]", value):
        if match.start() < end:
            continue
        try:
            parsed, next_end = decoder.raw_decode(value, match.start())
        except (json.JSONDecodeError, ValueError):
            continue
        chunks.append(_redact_plain_text(value[end:match.start()], redact_identity=redact_identity))
        chunks.append(json.dumps(redact_secrets(parsed, redact_identity=redact_identity)))
        end = next_end
    chunks.append(_redact_plain_text(value[end:], redact_identity=redact_identity))
    return "".join(chunks)


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

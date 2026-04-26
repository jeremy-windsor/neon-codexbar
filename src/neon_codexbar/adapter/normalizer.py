"""Normalize CodexBar CLI JSON payloads into generic provider cards."""

from __future__ import annotations

import json
from datetime import datetime
from typing import Any

from neon_codexbar.models import (
    CreditMeter,
    JsonDict,
    ProviderCard,
    QuotaWindow,
    parse_datetime,
    utc_now,
)

DISPLAY_NAMES: dict[str, str] = {
    "codex": "Codex",
    "claude": "Claude Code",
    "zai": "Z.ai",
    "openrouter": "OpenRouter",
}

_WINDOW_KEYS = ("primary", "secondary", "tertiary")

# OpenRouter exposes credit balance as loginMethod (for example, "Balance: $74.50").
# That string is useful as a login method, but it is not a subscription plan name.
_NON_PLAN_LOGIN_PREFIXES = ("balance:",)


def _as_dict(value: Any) -> JsonDict:
    return value if isinstance(value, dict) else {}


def _as_list(value: Any) -> list[Any]:
    return value if isinstance(value, list) else []


def _as_float(value: Any) -> float | None:
    if isinstance(value, bool) or value is None:
        return None
    if isinstance(value, int | float):
        return float(value)
    if isinstance(value, str):
        try:
            return float(value.strip().replace("$", "").replace(",", ""))
        except ValueError:
            return None
    return None


def _as_int(value: Any) -> int | None:
    if isinstance(value, bool) or value is None:
        return None
    if isinstance(value, int):
        return value
    if isinstance(value, float):
        return int(value)
    if isinstance(value, str):
        try:
            return int(value.strip())
        except ValueError:
            return None
    return None


def _display_name(provider_id: str) -> str:
    return DISPLAY_NAMES.get(provider_id, provider_id.replace("-", " ").replace("_", " ").title())


def _identity_from_payload(payload: JsonDict, usage: JsonDict) -> JsonDict:
    identity = dict(_as_dict(usage.get("identity")))
    if payload.get("account") is not None and "account" not in identity:
        identity["account"] = payload.get("account")
    for key in ("accountEmail", "accountOrganization", "loginMethod"):
        if usage.get(key) is not None and key not in identity:
            identity[key] = usage.get(key)
    return identity


def _normalize_window(
    *,
    window_id: str | None,
    window_label: str | None,
    raw_window: JsonDict,
) -> QuotaWindow:
    return QuotaWindow(
        id=window_id,
        used_percent=_as_float(raw_window.get("usedPercent")),
        resets_at=parse_datetime(raw_window.get("resetsAt")),
        reset_description=(
            raw_window.get("resetDescription")
            if isinstance(raw_window.get("resetDescription"), str)
            else None
        ),
        window_label=window_label,
        window_minutes=_as_int(raw_window.get("windowMinutes")),
        raw=raw_window,
    )


def _quota_windows(usage: JsonDict) -> list[QuotaWindow]:
    windows: list[QuotaWindow] = []
    for index, key in enumerate(_WINDOW_KEYS, start=1):
        raw_window = _as_dict(usage.get(key))
        if not raw_window:
            continue
        windows.append(
            _normalize_window(
                window_id=key,
                window_label=(
                    raw_window.get("title")
                    if isinstance(raw_window.get("title"), str)
                    else f"Window {index}"
                ),
                raw_window=raw_window,
            )
        )

    for fallback_index, named in enumerate(
        _as_list(usage.get("extraRateWindows")),
        start=len(windows) + 1,
    ):
        named_dict = _as_dict(named)
        raw_window = _as_dict(named_dict.get("window"))
        if not raw_window:
            continue
        window_id = named_dict.get("id") if isinstance(named_dict.get("id"), str) else None
        title = (
            named_dict.get("title")
            if isinstance(named_dict.get("title"), str)
            else f"Window {fallback_index}"
        )
        windows.append(
            _normalize_window(window_id=window_id, window_label=title, raw_window=raw_window)
        )

    return windows


def _openrouter_credit_meters(openrouter_usage: JsonDict) -> list[CreditMeter]:
    if not openrouter_usage:
        return []

    meters = [
        CreditMeter(
            label="OpenRouter Balance",
            balance=_as_float(openrouter_usage.get("balance")),
            used=_as_float(openrouter_usage.get("totalUsage")),
            total=_as_float(openrouter_usage.get("totalCredits")),
            used_percent=_as_float(openrouter_usage.get("usedPercent")),
            currency="USD",
            raw=openrouter_usage,
        )
    ]

    key_limit = _as_float(openrouter_usage.get("keyLimit"))
    key_usage = _as_float(openrouter_usage.get("keyUsage"))
    if key_limit is not None or key_usage is not None:
        key_balance: float | None = None
        key_used_percent: float | None = None
        if key_limit is not None and key_usage is not None:
            key_balance = max(0.0, key_limit - key_usage)
            key_used_percent = (
                min(100.0, max(0.0, (key_usage / key_limit) * 100.0))
                if key_limit > 0
                else None
            )
        meters.append(
            CreditMeter(
                label="OpenRouter Key Quota",
                balance=key_balance,
                used=key_usage,
                total=key_limit,
                used_percent=key_used_percent,
                currency="USD",
                raw=openrouter_usage,
            )
        )
    return meters


def _credit_meters(payload: JsonDict, usage: JsonDict) -> list[CreditMeter]:
    meters: list[CreditMeter] = []

    credits = _as_dict(payload.get("credits"))
    if credits:
        meters.append(
            CreditMeter(
                label="Credits",
                balance=_as_float(credits.get("remaining")),
                used=None,
                total=None,
                used_percent=None,
                currency=None,
                raw=credits,
            )
        )

    meters.extend(_openrouter_credit_meters(_as_dict(usage.get("openRouterUsage"))))

    provider_cost = _as_dict(usage.get("providerCost"))
    if provider_cost:
        used = _as_float(provider_cost.get("used"))
        total = _as_float(provider_cost.get("limit"))
        used_percent: float | None = None
        if used is not None and total is not None and total > 0:
            used_percent = min(100.0, max(0.0, (used / total) * 100.0))
        meters.append(
            CreditMeter(
                label="Provider Cost",
                balance=max(0.0, total - used) if used is not None and total is not None else None,
                used=used,
                total=total,
                used_percent=used_percent,
                currency=(
                    provider_cost.get("currency")
                    if isinstance(provider_cost.get("currency"), str)
                    else None
                ),
                raw=provider_cost,
            )
        )

    return meters


def _model_usage(payload: JsonDict, usage: JsonDict) -> list[JsonDict]:
    candidates: list[Any] = [
        usage.get("modelUsage"),
        usage.get("models"),
        _as_dict(payload.get("openaiDashboard")).get("usageBreakdown"),
        _as_dict(payload.get("openaiDashboard")).get("dailyBreakdown"),
    ]
    for candidate in candidates:
        items = [item for item in _as_list(candidate) if isinstance(item, dict)]
        if items:
            return [dict(item) for item in items]
    return []


def _last_success(payload: JsonDict, usage: JsonDict) -> datetime | None:
    if payload.get("error") is not None:
        return None
    for value in (
        usage.get("updatedAt"),
        _as_dict(payload.get("credits")).get("updatedAt"),
        _as_dict(usage.get("openRouterUsage")).get("updatedAt"),
        _as_dict(payload.get("openaiDashboard")).get("updatedAt"),
    ):
        parsed = parse_datetime(value)
        if parsed is not None:
            return parsed
    return None


def normalize_payload(
    payload: JsonDict,
    *,
    attempted_at: datetime | None = None,
    include_raw: bool = False,
) -> ProviderCard:
    """Normalize one CodexBar ``ProviderPayload`` object."""

    attempt_time = attempted_at or utc_now()
    provider_id = str(payload.get("provider") or "unknown")
    source = str(payload.get("source") or "unknown")
    usage = _as_dict(payload.get("usage"))
    identity = _identity_from_payload(payload, usage)
    error = _as_dict(payload.get("error"))
    error_message = error.get("message") if isinstance(error.get("message"), str) else None
    login_method = (
        identity.get("loginMethod") if isinstance(identity.get("loginMethod"), str) else None
    )
    plan = (
        login_method
        if login_method and not login_method.lower().startswith(_NON_PLAN_LOGIN_PREFIXES)
        else None
    )

    return ProviderCard(
        provider_id=provider_id,
        display_name=_display_name(provider_id),
        source=source,
        version=str(payload.get("version")) if payload.get("version") is not None else None,
        identity=identity,
        plan=plan,
        login_method=login_method,
        quota_windows=_quota_windows(usage),
        credit_meters=_credit_meters(payload, usage),
        model_usage=_model_usage(payload, usage),
        error_message=error_message,
        setup_hint=(
            f"Check CodexBar configuration/auth for {provider_id}." if error_message else None
        ),
        is_stale=False,
        last_success=_last_success(payload, usage),
        last_attempt=attempt_time,
        raw=payload if include_raw else None,
    )


def normalize_payloads(
    payloads: list[Any],
    *,
    attempted_at: datetime | None = None,
    include_raw: bool = False,
) -> list[ProviderCard]:
    """Normalize a list of CodexBar payload objects."""

    return [
        normalize_payload(payload, attempted_at=attempted_at, include_raw=include_raw)
        for payload in payloads
        if isinstance(payload, dict)
    ]


def normalize_json(
    raw_json: str,
    *,
    attempted_at: datetime | None = None,
    include_raw: bool = False,
) -> list[ProviderCard]:
    """Parse and normalize CodexBar JSON output."""

    parsed = json.loads(raw_json)
    if isinstance(parsed, list):
        return normalize_payloads(parsed, attempted_at=attempted_at, include_raw=include_raw)
    if isinstance(parsed, dict):
        return [normalize_payload(parsed, attempted_at=attempted_at, include_raw=include_raw)]
    raise ValueError("CodexBar JSON root must be an object or array")

"""Display models produced from CodexBar CLI payloads."""

from __future__ import annotations

from dataclasses import asdict, dataclass, fields, is_dataclass
from datetime import UTC, datetime
from typing import Any

JsonDict = dict[str, Any]


@dataclass(slots=True)
class QuotaWindow:
    """A generic provider quota/rate-limit window."""

    id: str | None
    used_percent: float | None
    resets_at: datetime | None
    reset_description: str | None
    window_label: str | None
    window_minutes: int | None
    raw: JsonDict


@dataclass(slots=True)
class CreditMeter:
    """A generic credit, balance, or key quota meter."""

    label: str
    balance: float | None
    used: float | None
    total: float | None
    used_percent: float | None
    currency: str | None
    raw: JsonDict


@dataclass(slots=True)
class ProviderCard:
    """Normalized card data consumed by future KDE UI layers."""

    provider_id: str
    display_name: str
    source: str
    version: str | None
    identity: JsonDict
    plan: str | None
    login_method: str | None
    quota_windows: list[QuotaWindow]
    credit_meters: list[CreditMeter]
    model_usage: list[JsonDict]
    error_message: str | None
    setup_hint: str | None
    is_stale: bool
    last_success: datetime | None
    last_attempt: datetime
    raw: JsonDict | None = None


@dataclass(slots=True)
class ProviderConfigEntry:
    """A provider entry discovered from ``codexbar config dump``."""

    provider_id: str
    enabled: bool | None
    configured_source: str | None = None
    source: str | None = None
    skipped: bool = False
    diagnostic: str | None = None


@dataclass(slots=True)
class CommandResult:
    """Structured subprocess result from CodexBar."""

    command: list[str]
    stdout: str
    stderr: str
    exit_code: int
    timed_out: bool
    duration_seconds: float
    error: str | None = None

    @property
    def ok(self) -> bool:
        """Return true when the subprocess exited successfully before timeout."""

        return self.exit_code == 0 and not self.timed_out and self.error is None


def utc_now() -> datetime:
    """Return timezone-aware UTC now."""

    return datetime.now(UTC)


def parse_datetime(value: Any) -> datetime | None:
    """Parse CodexBar date values encoded as ISO-8601 strings or Unix timestamps."""

    if value is None:
        return None
    if isinstance(value, datetime):
        return value
    if isinstance(value, int | float):
        try:
            return datetime.fromtimestamp(float(value), tz=UTC)
        except (OverflowError, OSError, ValueError):
            return None
    if not isinstance(value, str):
        return None

    raw = value.strip()
    if not raw:
        return None
    if raw.endswith("Z"):
        raw = f"{raw[:-1]}+00:00"
    try:
        parsed = datetime.fromisoformat(raw)
    except ValueError:
        return None
    if parsed.tzinfo is None:
        return parsed.replace(tzinfo=UTC)
    return parsed


def to_jsonable(value: Any) -> Any:
    """Convert dataclasses and datetimes into JSON-serializable values."""

    if isinstance(value, datetime):
        return value.astimezone(UTC).isoformat().replace("+00:00", "Z")
    if is_dataclass(value):
        return {field.name: to_jsonable(getattr(value, field.name)) for field in fields(value)}
    if isinstance(value, list):
        return [to_jsonable(item) for item in value]
    if isinstance(value, tuple):
        return [to_jsonable(item) for item in value]
    if isinstance(value, dict):
        return {str(key): to_jsonable(item) for key, item in value.items()}
    return value


def dataclass_asdict(value: Any) -> JsonDict:
    """Return a JSON-ready dictionary for a dataclass instance."""

    if not is_dataclass(value):
        raise TypeError("dataclass_asdict() expects a dataclass instance")
    return to_jsonable(asdict(value))

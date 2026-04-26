"""Linux-safe CodexBar source policy.

Never use ``--source auto`` on Linux provider fetches. Unknown providers are skipped
until validated and added here.
"""

from __future__ import annotations

from collections.abc import Iterable
from dataclasses import dataclass

LINUX_SOURCE_POLICY: dict[str, str] = {
    "codex": "cli",
    "claude": "cli",
    "zai": "api",
    "openrouter": "api",
}


@dataclass(frozen=True, slots=True)
class SourceDecision:
    """Policy decision for a discovered provider."""

    provider_id: str
    source: str | None
    skipped: bool
    diagnostic: str | None = None


def normalize_provider_id(provider_id: str) -> str:
    """Normalize provider IDs for policy lookup."""

    return provider_id.strip().lower()


def source_for(provider_id: str) -> str | None:
    """Return the Linux-safe source for a provider, or ``None`` when unknown."""

    return LINUX_SOURCE_POLICY.get(normalize_provider_id(provider_id))


def decision_for(provider_id: str) -> SourceDecision:
    """Return a source decision, skipping unknown providers rather than guessing."""

    normalized = normalize_provider_id(provider_id)
    source = source_for(normalized)
    if source is None:
        return SourceDecision(
            provider_id=normalized,
            source=None,
            skipped=True,
            diagnostic=(
                f"Provider '{normalized}' is not in neon-codexbar Linux source policy; "
                "skipping instead of guessing --source auto."
            ),
        )
    return SourceDecision(provider_id=normalized, source=source, skipped=False)


def apply_policy(provider_ids: Iterable[str]) -> tuple[list[SourceDecision], list[str]]:
    """Apply source policy to provider IDs, returning decisions and diagnostics."""

    decisions = [decision_for(provider_id) for provider_id in provider_ids]
    diagnostics = [decision.diagnostic for decision in decisions if decision.diagnostic]
    return decisions, diagnostics

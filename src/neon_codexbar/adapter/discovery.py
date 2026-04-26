"""Provider discovery from CodexBar config dump output."""

from __future__ import annotations

import json
from dataclasses import dataclass
from typing import Any

from neon_codexbar.adapter.runner import CodexBarRunner
from neon_codexbar.adapter.source_policy import decision_for
from neon_codexbar.diagnostics import redact_secrets
from neon_codexbar.models import CommandResult, ProviderConfigEntry


@dataclass(slots=True)
class DiscoveryResult:
    """Structured discovery output."""

    providers: list[ProviderConfigEntry]
    diagnostics: list[str]
    command_result: CommandResult | None = None

    @property
    def ok(self) -> bool:
        """Return true when discovery produced provider entries."""

        return bool(self.providers)


def _provider_items(config: Any) -> list[Any]:
    if isinstance(config, dict):
        providers = config.get("providers")
        if isinstance(providers, list):
            return providers
        if isinstance(providers, dict):
            items: list[Any] = []
            for key, value in providers.items():
                if isinstance(value, dict):
                    items.append({"id": key, **value})
                else:
                    items.append({"id": key})
            return items
        if "id" in config or "provider" in config:
            return [config]
    if isinstance(config, list):
        return config
    return []


def parse_config_dump(raw_json: str) -> list[ProviderConfigEntry]:
    """Parse ``codexbar config dump`` JSON into provider entries."""

    data = json.loads(raw_json)
    entries: list[ProviderConfigEntry] = []

    for item in _provider_items(data):
        if isinstance(item, str):
            provider_id = item
            enabled = None
            configured_source = None
        elif isinstance(item, dict):
            provider_value = item.get("id") or item.get("provider") or item.get("providerID")
            if not provider_value:
                continue
            provider_id = str(provider_value)
            enabled_raw = item.get("enabled")
            enabled = enabled_raw if isinstance(enabled_raw, bool) else None
            configured_source_raw = item.get("source")
            configured_source = str(configured_source_raw) if configured_source_raw else None
        else:
            continue

        policy = decision_for(provider_id)
        entries.append(
            ProviderConfigEntry(
                provider_id=policy.provider_id,
                enabled=enabled,
                configured_source=configured_source,
                source=policy.source,
                skipped=policy.skipped,
                diagnostic=policy.diagnostic,
            )
        )

    return entries


def discover(runner: CodexBarRunner) -> DiscoveryResult:
    """Discover providers by invoking CodexBar config dump."""

    result = runner.config_dump()
    if not result.ok:
        message = result.error or result.stderr or "CodexBar config dump failed."
        return DiscoveryResult(
            providers=[],
            diagnostics=[str(redact_secrets(message))],
            command_result=result,
        )

    try:
        providers = parse_config_dump(result.stdout)
    except json.JSONDecodeError as exc:
        return DiscoveryResult(
            providers=[],
            diagnostics=[f"CodexBar config dump was not valid JSON: {exc.msg}"],
            command_result=result,
        )

    diagnostics = [entry.diagnostic for entry in providers if entry.diagnostic]
    return DiscoveryResult(providers=providers, diagnostics=diagnostics, command_result=result)

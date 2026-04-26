"""Command line interface for Phase 1 neon-codexbar."""

from __future__ import annotations

import argparse
import json
import sys
from collections.abc import Sequence
from dataclasses import asdict
from datetime import datetime
from pathlib import Path
from typing import Any

from neon_codexbar import __version__
from neon_codexbar.adapter.discovery import discover
from neon_codexbar.adapter.normalizer import normalize_json
from neon_codexbar.adapter.runner import CodexBarRunner
from neon_codexbar.adapter.source_policy import LINUX_SOURCE_POLICY
from neon_codexbar.config import load_config
from neon_codexbar.diagnostics import redact_secrets
from neon_codexbar.models import (
    ProviderCard,
    ProviderConfigEntry,
    dataclass_asdict,
    to_jsonable,
    utc_now,
)


def _dump_json(payload: Any) -> None:
    print(json.dumps(to_jsonable(redact_secrets(payload)), indent=2, sort_keys=True))


def _entry_to_dict(entry: ProviderConfigEntry) -> dict[str, Any]:
    return to_jsonable(asdict(entry))


def _card_to_dict(card: ProviderCard) -> dict[str, Any]:
    return dataclass_asdict(card)


def _command_result_payload(result: Any) -> dict[str, Any] | None:
    if result is None:
        return None
    payload = dataclass_asdict(result)
    return redact_secrets(payload)


def _runner(args: argparse.Namespace) -> CodexBarRunner:
    config_path = Path(args.config).expanduser() if getattr(args, "config", None) else None
    config = load_config(config_path)
    return CodexBarRunner(config=config, codexbar_path=getattr(args, "codexbar", None))


def cmd_version(args: argparse.Namespace) -> int:
    runner = _runner(args)
    result = runner.version()
    codexbar_version = result.stdout.strip() if result.ok else "unavailable"
    print(f"neon-codexbar {__version__} (codexbar {codexbar_version})")
    return 0


def cmd_discover(args: argparse.Namespace) -> int:
    if not args.json:
        print("discover currently supports JSON output only; pass --json", file=sys.stderr)
        return 2

    runner = _runner(args)
    result = discover(runner)
    payload = {
        "ok": result.ok,
        "providers": [_entry_to_dict(entry) for entry in result.providers],
        "diagnostics": result.diagnostics,
        "command": _command_result_payload(result.command_result),
    }
    _dump_json(payload)
    return 0


def _error_card(
    provider_id: str,
    source: str,
    message: str,
    attempted_at: datetime,
) -> ProviderCard:
    payload = {
        "provider": provider_id,
        "source": source,
        "error": {"message": message, "kind": "provider"},
    }
    return normalize_json(json.dumps([payload]), attempted_at=attempted_at)[0]


def _selected_entries(
    args: argparse.Namespace,
    entries: list[ProviderConfigEntry],
) -> list[ProviderConfigEntry]:
    requested = set(args.provider or [])
    selected: list[ProviderConfigEntry] = []
    for entry in entries:
        if requested and entry.provider_id not in requested:
            continue
        if entry.skipped:
            continue
        if entry.enabled is not True and not requested:
            continue
        selected.append(entry)
    return selected


def cmd_fetch(args: argparse.Namespace) -> int:
    if not args.json:
        print("fetch currently supports JSON output only; pass --json", file=sys.stderr)
        return 2

    attempted_at = utc_now()
    runner = _runner(args)

    if args.fixture:
        raw = Path(args.fixture).expanduser().read_text(encoding="utf-8")
        cards = normalize_json(raw, attempted_at=attempted_at)
        _dump_json(
            {"ok": True, "cards": [_card_to_dict(card) for card in cards], "diagnostics": []}
        )
        return 0

    discovery = discover(runner)
    cards: list[ProviderCard] = []
    diagnostics = list(discovery.diagnostics)
    if not discovery.providers:
        message = "; ".join(discovery.diagnostics) or "No CodexBar providers discovered."
        _dump_json(
            {
                "ok": False,
                "cards": [],
                "diagnostics": [message],
                "discovery_command": _command_result_payload(discovery.command_result),
            }
        )
        return 1

    for entry in _selected_entries(args, discovery.providers):
        source = entry.source
        if not source:
            diagnostics.append(
                entry.diagnostic or f"No source policy for provider {entry.provider_id}."
            )
            continue
        fetch_result = runner.fetch_provider(entry.provider_id, source)
        if not fetch_result.ok:
            cards.append(
                _error_card(
                    entry.provider_id,
                    source,
                    fetch_result.error or fetch_result.stderr or "CodexBar provider fetch failed.",
                    attempted_at,
                )
            )
            diagnostics.append(f"{entry.provider_id}: {fetch_result.error or fetch_result.stderr}")
            continue
        try:
            cards.extend(normalize_json(fetch_result.stdout, attempted_at=attempted_at))
        except (json.JSONDecodeError, ValueError) as exc:
            cards.append(
                _error_card(
                    entry.provider_id,
                    source,
                    f"Invalid CodexBar JSON: {exc}",
                    attempted_at,
                )
            )
            diagnostics.append(f"{entry.provider_id}: invalid CodexBar JSON: {exc}")

    payload = {
        "ok": all(card.error_message is None for card in cards),
        "cards": [_card_to_dict(card) for card in cards],
        "diagnostics": diagnostics,
    }
    _dump_json(payload)
    return 0 if cards else 1


def cmd_diagnose(args: argparse.Namespace) -> int:
    if not args.json:
        print("diagnose currently supports JSON output only; pass --json", file=sys.stderr)
        return 2

    runner = _runner(args)
    located = runner.locate()
    version_result = runner.version()
    discovery = discover(runner)
    payload = {
        "ok": located is not None and version_result.ok and discovery.ok,
        "neon_codexbar_version": __version__,
        "codexbar": {
            "available": located is not None,
            "path": located,
            "version": version_result.stdout.strip() if version_result.ok else None,
            "version_command": _command_result_payload(version_result),
        },
        "source_policy": LINUX_SOURCE_POLICY,
        "providers": [_entry_to_dict(entry) for entry in discovery.providers],
        "diagnostics": discovery.diagnostics,
        "discovery_command": _command_result_payload(discovery.command_result),
    }
    _dump_json(payload)
    return 0


def build_parser() -> argparse.ArgumentParser:
    """Build the CLI parser."""

    parser = argparse.ArgumentParser(prog="neon-codexbar")
    parser.add_argument(
        "--version",
        action="store_true",
        help="show neon-codexbar and CodexBar versions",
    )
    parser.add_argument("--config", help="path to neon-codexbar UI config")
    parser.add_argument("--codexbar", help="explicit path to codexbar CLI")

    subparsers = parser.add_subparsers(dest="command")

    discover_parser = subparsers.add_parser("discover", help="discover CodexBar providers")
    discover_parser.add_argument("--json", action="store_true", required=True, help="emit JSON")
    discover_parser.set_defaults(func=cmd_discover)

    fetch_parser = subparsers.add_parser("fetch", help="fetch normalized provider cards")
    fetch_parser.add_argument("--json", action="store_true", required=True, help="emit JSON")
    fetch_parser.add_argument(
        "--provider",
        action="append",
        help="provider id to fetch; defaults to enabled known providers",
    )
    fetch_parser.add_argument(
        "--fixture",
        help="read CodexBar JSON fixture instead of invoking CodexBar",
    )
    fetch_parser.set_defaults(func=cmd_fetch)

    diagnose_parser = subparsers.add_parser("diagnose", help="emit redacted diagnostic bundle")
    diagnose_parser.add_argument("--json", action="store_true", required=True, help="emit JSON")
    diagnose_parser.set_defaults(func=cmd_diagnose)

    return parser


def main(argv: Sequence[str] | None = None) -> int:
    """Run the CLI."""

    parser = build_parser()
    args = parser.parse_args(argv)
    if args.version:
        return cmd_version(args)
    if not hasattr(args, "func"):
        parser.print_help(sys.stderr)
        return 2
    return int(args.func(args))

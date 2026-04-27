"""neon-codexbar refresh daemon.

Long-running process that polls every enabled CodexBar provider on a fixed
cadence, normalizes the results, and atomically writes one snapshot file the
KDE widget watches.

Lifecycle:
- On start: write a placeholder snapshot, then immediately do tick #1.
- Every ``refresh_interval_seconds``: tick.
- ``SIGUSR1`` or touching ``<snapshot_dir>/refresh.touch``: trigger an early tick.
- ``SIGTERM`` / ``SIGINT``: graceful shutdown; finish in-flight tick first.
"""

from __future__ import annotations

import argparse
import json
import logging
import signal
import sys
import threading
import time
from concurrent.futures import ThreadPoolExecutor, as_completed
from dataclasses import dataclass, replace
from datetime import datetime, timedelta
from pathlib import Path
from typing import Any

from neon_codexbar.adapter.discovery import discover
from neon_codexbar.adapter.normalizer import normalize_json
from neon_codexbar.adapter.runner import CodexBarRunner
from neon_codexbar.config import AppConfig, load_config
from neon_codexbar.ipc.snapshot_writer import (
    build_snapshot,
    default_snapshot_path,
    write_snapshot,
)
from neon_codexbar.models import ProviderCard, ProviderConfigEntry, utc_now

LOG = logging.getLogger("neon_codexbar.daemon")
MAX_FETCH_WORKERS = 8
SLEEP_TICK_SECONDS = 1.0


@dataclass(slots=True)
class TickResult:
    """Outcome of one refresh cycle."""

    cards: list[ProviderCard]
    diagnostics: list[str]
    started_at: datetime
    elapsed_seconds: float
    fetch_count: int
    error_count: int


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


def _selected(entries: list[ProviderConfigEntry]) -> list[ProviderConfigEntry]:
    """Filter to providers we should fetch on a tick — enabled, with a source."""

    return [
        entry
        for entry in entries
        if entry.enabled is True and not entry.skipped and entry.source
    ]


def _fetch_one(
    runner: CodexBarRunner,
    entry: ProviderConfigEntry,
    attempted_at: datetime,
) -> tuple[ProviderConfigEntry, list[ProviderCard], str | None]:
    """Fetch one provider and return cards + optional diagnostic line."""

    assert entry.source is not None  # _selected guarantees this
    result = runner.fetch_provider(entry.provider_id, entry.source)
    if not result.ok:
        message = result.error or result.stderr or "CodexBar provider fetch failed."
        card = _error_card(entry.provider_id, entry.source, message, attempted_at)
        return entry, [card], f"{entry.provider_id}: {message}"
    try:
        cards = normalize_json(result.stdout, attempted_at=attempted_at)
    except (json.JSONDecodeError, ValueError) as exc:
        message = f"Invalid CodexBar JSON: {exc}"
        card = _error_card(entry.provider_id, entry.source, message, attempted_at)
        return entry, [card], f"{entry.provider_id}: {message}"
    return entry, cards, None


def _apply_staleness(
    cards: list[ProviderCard],
    last_success_by_provider: dict[str, datetime],
    *,
    now: datetime,
    refresh_interval: timedelta,
) -> list[ProviderCard]:
    """Mark cards stale based on time since their last successful fetch."""

    threshold = refresh_interval * 2
    updated: list[ProviderCard] = []
    for card in cards:
        if card.last_success is not None:
            last_success_by_provider[card.provider_id] = card.last_success
        last_success = last_success_by_provider.get(card.provider_id)
        is_stale = last_success is None or (now - last_success) > threshold
        if is_stale != card.is_stale or (
            last_success is not None and card.last_success is None
        ):
            updated.append(
                replace(
                    card,
                    is_stale=is_stale,
                    last_success=card.last_success or last_success,
                )
            )
        else:
            updated.append(card)
    return updated


class Daemon:
    """neon-codexbar refresh loop. Designed to be unit-testable.

    ``runner`` and ``snapshot_path`` are injectable so tests can drive ticks
    against fixtures without invoking a real CodexBar subprocess.
    """

    def __init__(
        self,
        config: AppConfig,
        *,
        runner: CodexBarRunner | None = None,
        snapshot_path: Path | None = None,
        max_workers: int = MAX_FETCH_WORKERS,
    ) -> None:
        self.config = config
        self.runner = runner or CodexBarRunner(config=config)
        self.snapshot_path = snapshot_path or default_snapshot_path()
        self.refresh_interval = timedelta(seconds=config.refresh_interval_seconds)
        self.max_workers = max_workers
        self.last_success_by_provider: dict[str, datetime] = {}
        self.shutdown_event = threading.Event()
        self.refresh_event = threading.Event()
        self.tick_count = 0
        self.refresh_sentinel = self.snapshot_path.parent / "refresh.touch"

    # ----- one tick -------------------------------------------------------

    def tick(self) -> TickResult:
        """Run one refresh cycle: discover, fan out, normalize, return."""

        started = utc_now()
        attempted_at = started
        discovery = discover(self.runner)
        diagnostics = list(discovery.diagnostics)
        cards: list[ProviderCard] = []

        if not discovery.ok:
            LOG.warning("discovery returned no providers; nothing to fetch this tick")
            elapsed = (utc_now() - started).total_seconds()
            return TickResult(
                cards=[],
                diagnostics=diagnostics or ["No providers discovered."],
                started_at=started,
                elapsed_seconds=elapsed,
                fetch_count=0,
                error_count=0,
            )

        targets = _selected(discovery.providers)
        if not targets:
            elapsed = (utc_now() - started).total_seconds()
            return TickResult(
                cards=[],
                diagnostics=diagnostics or ["No enabled providers in source policy."],
                started_at=started,
                elapsed_seconds=elapsed,
                fetch_count=0,
                error_count=0,
            )

        error_count = 0
        worker_count = min(self.max_workers, len(targets))
        with ThreadPoolExecutor(max_workers=worker_count) as pool:
            futures = [
                pool.submit(_fetch_one, self.runner, entry, attempted_at) for entry in targets
            ]
            for future in as_completed(futures):
                _entry, fetched_cards, diagnostic = future.result()
                cards.extend(fetched_cards)
                if diagnostic:
                    diagnostics.append(diagnostic)
                    error_count += 1

        cards.sort(key=lambda card: card.provider_id)
        cards = _apply_staleness(
            cards,
            self.last_success_by_provider,
            now=utc_now(),
            refresh_interval=self.refresh_interval,
        )
        elapsed = (utc_now() - started).total_seconds()
        return TickResult(
            cards=cards,
            diagnostics=diagnostics,
            started_at=started,
            elapsed_seconds=elapsed,
            fetch_count=len(targets),
            error_count=error_count,
        )

    # ----- snapshot writing -----------------------------------------------

    def write_initial_snapshot(self) -> Path:
        """Write a placeholder so the widget never sees a missing file."""

        located = self.runner.locate()
        version = None
        if located is not None:
            version_result = self.runner.version()
            if version_result.ok:
                version = version_result.stdout.strip() or None
        payload = build_snapshot(
            cards=[],
            diagnostics=["initial: refresh in progress"],
            codexbar_path=located,
            codexbar_version=version,
        )
        return write_snapshot(payload, self.snapshot_path)

    def write_tick_snapshot(self, tick: TickResult) -> Path:
        """Persist a completed tick's cards and diagnostics."""

        located = self.runner.locate()
        version = None
        if located is not None:
            version_result = self.runner.version()
            if version_result.ok:
                version = version_result.stdout.strip() or None
        payload = build_snapshot(
            cards=tick.cards,
            diagnostics=tick.diagnostics,
            codexbar_path=located,
            codexbar_version=version,
            ok=tick.error_count == 0 and located is not None,
        )
        return write_snapshot(payload, self.snapshot_path)

    # ----- main loop ------------------------------------------------------

    def request_refresh(self) -> None:
        """Trigger an early tick from another thread / signal handler."""

        self.refresh_event.set()

    def request_shutdown(self) -> None:
        """Signal the loop to exit after the current tick finishes."""

        self.shutdown_event.set()
        self.refresh_event.set()

    def _consume_sentinel(self) -> bool:
        if not self.refresh_sentinel.exists():
            return False
        try:
            self.refresh_sentinel.unlink()
        except FileNotFoundError:
            pass
        return True

    def _sleep_until_next_tick(self) -> None:
        deadline = time.monotonic() + self.refresh_interval.total_seconds()
        while not self.shutdown_event.is_set():
            now = time.monotonic()
            if now >= deadline:
                return
            if self.refresh_event.is_set():
                self.refresh_event.clear()
                return
            if self._consume_sentinel():
                return
            self.shutdown_event.wait(min(SLEEP_TICK_SECONDS, deadline - now))

    def run_forever(self) -> int:
        """Block running ticks until shutdown is requested. Return exit code."""

        LOG.info(
            "daemon starting: snapshot=%s refresh_interval=%ss",
            self.snapshot_path,
            int(self.refresh_interval.total_seconds()),
        )
        self.write_initial_snapshot()
        try:
            while not self.shutdown_event.is_set():
                self.tick_count += 1
                tick = self.tick()
                self.write_tick_snapshot(tick)
                LOG.info(
                    "tick %d providers=%d ok=%d errors=%d elapsed=%.1fs",
                    self.tick_count,
                    tick.fetch_count,
                    tick.fetch_count - tick.error_count,
                    tick.error_count,
                    tick.elapsed_seconds,
                )
                if self.shutdown_event.is_set():
                    break
                self._sleep_until_next_tick()
        except Exception:  # pragma: no cover — last-resort safety net
            LOG.exception("daemon crashed; exiting non-zero")
            return 1
        LOG.info("daemon stopped after %d ticks", self.tick_count)
        return 0


# ----- CLI entry point ----------------------------------------------------


def _install_signal_handlers(daemon: Daemon) -> None:
    def on_term(signum: int, _frame: Any) -> None:
        LOG.info("received signal %d; shutting down after current tick", signum)
        daemon.request_shutdown()

    def on_refresh(_signum: int, _frame: Any) -> None:
        LOG.info("received SIGUSR1; refreshing on next tick boundary")
        daemon.request_refresh()

    signal.signal(signal.SIGTERM, on_term)
    signal.signal(signal.SIGINT, on_term)
    signal.signal(signal.SIGUSR1, on_refresh)


def _configure_logging(verbose: bool) -> None:
    logging.basicConfig(
        level=logging.DEBUG if verbose else logging.INFO,
        format="%(asctime)s %(levelname)s %(name)s: %(message)s",
        stream=sys.stderr,
    )


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(prog="neon-codexbar-daemon")
    parser.add_argument("--config", help="path to neon-codexbar UI config")
    parser.add_argument("--codexbar", help="explicit path to codexbar CLI")
    parser.add_argument("--snapshot-path", help="override snapshot output path")
    parser.add_argument("-v", "--verbose", action="store_true", help="debug logging")
    parser.add_argument(
        "--once",
        action="store_true",
        help="run one tick, write the snapshot, and exit (no loop)",
    )
    return parser


def main(argv: list[str] | None = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)
    _configure_logging(args.verbose)

    config_path = Path(args.config).expanduser() if args.config else None
    config = load_config(config_path)
    runner = CodexBarRunner(config=config, codexbar_path=args.codexbar)
    snapshot_path = Path(args.snapshot_path).expanduser() if args.snapshot_path else None
    daemon = Daemon(config, runner=runner, snapshot_path=snapshot_path)

    if args.once:
        daemon.write_initial_snapshot()
        tick = daemon.tick()
        daemon.write_tick_snapshot(tick)
        LOG.info(
            "single-tick run providers=%d ok=%d errors=%d elapsed=%.1fs",
            tick.fetch_count,
            tick.fetch_count - tick.error_count,
            tick.error_count,
            tick.elapsed_seconds,
        )
        return 0

    _install_signal_handlers(daemon)
    return daemon.run_forever()


if __name__ == "__main__":
    sys.exit(main())

from __future__ import annotations

import json
from datetime import UTC, datetime, timedelta
from pathlib import Path

import pytest

from neon_codexbar.config import AppConfig
from neon_codexbar.daemon import Daemon, _apply_staleness
from neon_codexbar.models import CommandResult, ProviderCard, utc_now

FIXTURES = Path(__file__).resolve().parents[1] / "fixtures" / "codexbar"


class FakeRunner:
    """Drop-in for CodexBarRunner that serves payloads from fixtures."""

    def __init__(
        self,
        *,
        config_dump_payload: str,
        provider_payloads: dict[str, str],
        binary: str | None = "/fake/codexbar",
        version: str = "FakeCodexBar 0.0.1",
    ) -> None:
        self.config = AppConfig()
        self.codexbar_path = binary
        self._config_dump = config_dump_payload
        self._provider_payloads = provider_payloads
        self._version = version
        self.fetch_calls: list[tuple[str, str]] = []
        self.version_calls = 0
        self.locate_calls = 0

    def locate(self) -> str | None:
        self.locate_calls += 1
        return self.codexbar_path

    def version(self) -> CommandResult:
        self.version_calls += 1
        return CommandResult(
            command=["codexbar", "--version"],
            stdout=self._version,
            stderr="",
            exit_code=0,
            timed_out=False,
            duration_seconds=0.0,
        )

    def config_dump(self) -> CommandResult:
        return CommandResult(
            command=["codexbar", "config", "dump"],
            stdout=self._config_dump,
            stderr="",
            exit_code=0,
            timed_out=False,
            duration_seconds=0.0,
        )

    def fetch_provider(self, provider_id: str, source: str) -> CommandResult:
        self.fetch_calls.append((provider_id, source))
        payload = self._provider_payloads.get(provider_id)
        if payload is None:
            return CommandResult(
                command=["codexbar", "--provider", provider_id, "--source", source],
                stdout="",
                stderr=f"unknown provider {provider_id}",
                exit_code=1,
                timed_out=False,
                duration_seconds=0.0,
                error=f"unknown provider {provider_id}",
            )
        return CommandResult(
            command=["codexbar", "--provider", provider_id, "--source", source],
            stdout=payload,
            stderr="",
            exit_code=0,
            timed_out=False,
            duration_seconds=0.0,
        )


def _fake_runner_all_four() -> FakeRunner:
    return FakeRunner(
        config_dump_payload=json.dumps(
            {
                "version": 1,
                "providers": [
                    {"id": "codex", "enabled": True},
                    {"id": "claude", "enabled": True},
                    {"id": "zai", "enabled": True},
                    {"id": "openrouter", "enabled": True},
                ],
            }
        ),
        provider_payloads={
            "codex": (FIXTURES / "codex_cli_success.json").read_text(encoding="utf-8"),
            "claude": (FIXTURES / "claude_cli_success.json").read_text(encoding="utf-8"),
            "zai": (FIXTURES / "zai_api_success.json").read_text(encoding="utf-8"),
            "openrouter": (FIXTURES / "openrouter_api_success.json").read_text(encoding="utf-8"),
        },
    )


@pytest.fixture
def snapshot_path(tmp_path: Path) -> Path:
    return tmp_path / "snapshot.json"


def test_daemon_tick_fetches_all_enabled_and_normalizes(snapshot_path: Path) -> None:
    runner = _fake_runner_all_four()
    daemon = Daemon(AppConfig(), runner=runner, snapshot_path=snapshot_path)

    tick = daemon.tick()

    assert tick.fetch_count == 4
    assert tick.error_count == 0
    assert {(pid, src) for pid, src in runner.fetch_calls} == {
        ("codex", "cli"),
        ("claude", "cli"),
        ("zai", "api"),
        ("openrouter", "api"),
    }
    assert [card.provider_id for card in tick.cards] == ["claude", "codex", "openrouter", "zai"]
    for card in tick.cards:
        assert card.error_message is None


def test_daemon_writes_snapshot_atomically(snapshot_path: Path) -> None:
    runner = _fake_runner_all_four()
    daemon = Daemon(AppConfig(), runner=runner, snapshot_path=snapshot_path)
    tick = daemon.tick()

    daemon.write_tick_snapshot(tick)

    assert snapshot_path.exists()
    payload = json.loads(snapshot_path.read_text(encoding="utf-8"))
    assert payload["schema_version"] == 1
    assert payload["ok"] is True
    assert payload["codexbar"]["available"] is True
    assert {card["provider_id"] for card in payload["cards"]} == {
        "claude",
        "codex",
        "openrouter",
        "zai",
    }


def test_daemon_initial_snapshot_is_placeholder(snapshot_path: Path) -> None:
    runner = _fake_runner_all_four()
    daemon = Daemon(AppConfig(), runner=runner, snapshot_path=snapshot_path)

    daemon.write_initial_snapshot()

    payload = json.loads(snapshot_path.read_text(encoding="utf-8"))
    assert payload["cards"] == []
    assert payload["diagnostics"] == ["initial: refresh in progress"]
    assert payload["codexbar"]["version"] == "FakeCodexBar 0.0.1"


def test_daemon_tick_records_provider_error(tmp_path: Path) -> None:
    snapshot = tmp_path / "snapshot.json"
    runner = FakeRunner(
        config_dump_payload=json.dumps(
            {"version": 1, "providers": [{"id": "codex", "enabled": True}]}
        ),
        provider_payloads={},  # codex fetch will fail
    )
    daemon = Daemon(AppConfig(), runner=runner, snapshot_path=snapshot)

    tick = daemon.tick()
    daemon.write_tick_snapshot(tick)

    assert tick.fetch_count == 1
    assert tick.error_count == 1
    assert tick.cards[0].provider_id == "codex"
    assert tick.cards[0].error_message is not None

    # snapshot.ok is global health, not per-provider success.
    payload = json.loads(snapshot.read_text(encoding="utf-8"))
    assert payload["ok"] is True
    assert payload["cards"][0]["error_message"] is not None


class _ExplodingRunner(FakeRunner):
    """Runner whose fetch_provider raises — simulating a bug in _fetch_one."""

    def fetch_provider(self, provider_id: str, source: str) -> CommandResult:
        self.fetch_calls.append((provider_id, source))
        raise RuntimeError(f"boom from {provider_id}")


def test_daemon_tick_survives_worker_exception(snapshot_path: Path) -> None:
    """A worker raising must not kill the tick; it must produce an error card."""

    runner = _ExplodingRunner(
        config_dump_payload=json.dumps(
            {
                "version": 1,
                "providers": [
                    {"id": "codex", "enabled": True},
                    {"id": "zai", "enabled": True},
                ],
            }
        ),
        provider_payloads={},
    )
    daemon = Daemon(AppConfig(), runner=runner, snapshot_path=snapshot_path)

    tick = daemon.tick()
    daemon.write_tick_snapshot(tick)

    assert tick.fetch_count == 2
    assert tick.error_count == 2
    assert {c.provider_id for c in tick.cards} == {"codex", "zai"}
    for card in tick.cards:
        assert card.error_message is not None
        # Diagnostic should not leak the raw exception repr verbatim through
        # any code path that bypasses redaction.
        assert "boom" in (card.error_message or "")
    payload = json.loads(snapshot_path.read_text(encoding="utf-8"))
    # Global daemon health is fine — CodexBar was located. Only providers errored.
    assert payload["ok"] is True


def test_daemon_run_forever_exits_immediately_when_shutdown_pre_set(snapshot_path: Path) -> None:
    runner = _fake_runner_all_four()
    config = AppConfig(refresh_interval_seconds=10)
    daemon = Daemon(config, runner=runner, snapshot_path=snapshot_path)
    daemon.request_shutdown()

    code = daemon.run_forever()

    # Shutdown set before the loop body runs → no ticks, but the initial
    # placeholder snapshot is still written so the widget never sees a missing file.
    assert code == 0
    assert daemon.tick_count == 0
    assert snapshot_path.exists()


def test_daemon_run_forever_executes_tick_then_exits_on_shutdown(snapshot_path: Path) -> None:
    import threading

    runner = _fake_runner_all_four()
    config = AppConfig(refresh_interval_seconds=10)
    daemon = Daemon(config, runner=runner, snapshot_path=snapshot_path)
    # Set shutdown shortly after the loop starts so exactly one tick completes.
    threading.Timer(0.2, daemon.request_shutdown).start()

    code = daemon.run_forever()

    assert code == 0
    assert daemon.tick_count == 1
    payload = json.loads(snapshot_path.read_text(encoding="utf-8"))
    assert payload["ok"] is True
    assert {card["provider_id"] for card in payload["cards"]} == {
        "claude",
        "codex",
        "openrouter",
        "zai",
    }


def test_daemon_caches_codexbar_version_after_first_probe(snapshot_path: Path) -> None:
    """version() spawns a subprocess; only call it once per daemon lifetime."""

    runner = _fake_runner_all_four()
    daemon = Daemon(AppConfig(), runner=runner, snapshot_path=snapshot_path)

    daemon.write_initial_snapshot()
    tick = daemon.tick()
    daemon.write_tick_snapshot(tick)
    daemon.write_tick_snapshot(tick)

    assert runner.version_calls == 1


def test_daemon_retries_codexbar_probe_until_binary_appears(snapshot_path: Path) -> None:
    """If CodexBar isn't present at startup, retry on the next snapshot write."""

    runner = FakeRunner(
        config_dump_payload=json.dumps({"version": 1, "providers": []}),
        provider_payloads={},
        binary=None,  # CodexBar missing at start
    )
    daemon = Daemon(AppConfig(), runner=runner, snapshot_path=snapshot_path)

    daemon.write_initial_snapshot()
    assert runner.locate_calls == 1
    # Binary appears between writes (e.g. user installs CodexBar).
    runner.codexbar_path = "/fake/codexbar"

    daemon.write_initial_snapshot()
    assert runner.locate_calls == 2  # retried because not yet probed
    assert runner.version_calls == 1  # but version called once binary was found

    daemon.write_initial_snapshot()
    assert runner.version_calls == 1  # cached now


def test_apply_staleness_marks_card_when_last_success_is_old() -> None:
    now = datetime(2026, 4, 26, 20, 0, 0, tzinfo=UTC)
    refresh = timedelta(seconds=300)
    fresh_card = ProviderCard(
        provider_id="codex",
        display_name="Codex",
        source="cli",
        version=None,
        identity={},
        plan=None,
        login_method=None,
        quota_windows=[],
        credit_meters=[],
        model_usage=[],
        error_message=None,
        setup_hint=None,
        is_stale=False,
        last_success=now - timedelta(seconds=60),
        last_attempt=now,
    )
    stale_card = ProviderCard(
        provider_id="claude",
        display_name="Claude Code",
        source="cli",
        version=None,
        identity={},
        plan=None,
        login_method=None,
        quota_windows=[],
        credit_meters=[],
        model_usage=[],
        error_message=None,
        setup_hint=None,
        is_stale=False,
        last_success=now - timedelta(seconds=1200),  # > 2x refresh
        last_attempt=now,
    )

    updated = _apply_staleness(
        [fresh_card, stale_card],
        last_success_by_provider={},
        now=now,
        refresh_interval=refresh,
    )

    by_id = {card.provider_id: card for card in updated}
    assert by_id["codex"].is_stale is False
    assert by_id["claude"].is_stale is True


def test_apply_staleness_marks_stale_when_no_success_recorded() -> None:
    now = utc_now()
    card = ProviderCard(
        provider_id="zai",
        display_name="Z.ai",
        source="api",
        version=None,
        identity={},
        plan=None,
        login_method=None,
        quota_windows=[],
        credit_meters=[],
        model_usage=[],
        error_message="boom",
        setup_hint=None,
        is_stale=False,
        last_success=None,
        last_attempt=now,
    )

    updated = _apply_staleness(
        [card],
        last_success_by_provider={},
        now=now,
        refresh_interval=timedelta(seconds=300),
    )

    assert updated[0].is_stale is True

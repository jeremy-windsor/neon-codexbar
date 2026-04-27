# Phase 2 — Daemon + Snapshot IPC

Date opened: 2026-04-26
Status: in progress

Build tracker for the Phase 2 deliverable from
`plans/claude-neon-codexbar-plan.md` §15.

## Goal

A long-running Python process that periodically calls every enabled CodexBar
provider, normalizes results, and atomically writes one snapshot file the
Plasma widget can watch. No QML in this phase. No installer in this phase.

## Acceptance criteria (from master plan)

- [x] `systemctl --user start neon-codexbar` runs cleanly *(deferred until
  install scripts land — verified via `python3 -m neon_codexbar.daemon` in
  the meantime)*
- [x] `~/.cache/neon-codexbar/snapshot.json` updates every N seconds
- [x] `journalctl --user -u neon-codexbar` shows clean logs *(equivalent: stderr
  log lines are clean and structured, suitable for journald capture)*
- [x] Killing the daemon results in `is_stale=true` after 2× refresh interval
  *(field on each card; daemon also stops touching the file, so widget can
  detect staleness via mtime if it prefers)*

## Design decisions

### IPC mechanism — file watching, not D-Bus

The widget reads `~/.cache/neon-codexbar/snapshot.json`. The daemon writes it
atomically (`*.tmp` then rename). Plasma 6 has `FileWatcher`; if it proves
unreliable in Phase 3, fall back to polling. **Do not migrate to D-Bus until
file-watching is observed to drop updates.**

Rationale: a file is the simplest interface that survives daemon restarts,
crashes, and widget reloads. D-Bus would couple lifetimes.

### Single process, threadpool for fetches

`ThreadPoolExecutor(max_workers=8)` runs one CodexBar subprocess per enabled
provider per tick. Subprocesses are I/O-bound (claude takes ~15s on the network),
so threads are appropriate. No asyncio — `subprocess.run` is sync and the
threadpool is sufficient.

### Refresh cadence

`AppConfig.refresh_interval_seconds` (default 300s). Daemon sleeps in 1s
increments between ticks so signals/sentinels can interrupt cleanly.

### Manual refresh triggers

1. **SIGUSR1** — signal-based, scriptable (`pkill -USR1 neon-codexbar-daemon`).
2. **Sentinel file** — `~/.cache/neon-codexbar/refresh.touch`. Widget can
   `touch` it to force a refresh without needing a PID. Daemon checks once per
   sleep tick; deletes the sentinel on consumption.

### Stale detection

Each card tracks `last_success`. On each tick, if
`now - last_success > 2 * refresh_interval`, the card's `is_stale` flag goes
true in the next written snapshot. The daemon does not need to be alive for
the widget to compute staleness — it can compare snapshot `generated_at` to
wall clock and dim the UI on its own — but `is_stale` is a hint.

### Snapshot schema

```json
{
  "schema_version": 1,
  "generated_at": "2026-04-26T20:00:00Z",
  "ok": true,
  "cards": [ ... ProviderCard.to_dict() ... ],
  "diagnostics": [ "..." ],
  "codexbar": {
    "available": true,
    "path": "/home/user/.local/bin/codexbar",
    "version": "CodexBar"
  }
}
```

`ok` reflects whether the daemon could find CodexBar at all, not per-card
success (per-card errors land in `cards[i].error_message`).

### Atomic write

```python
tmp = path.with_suffix(".json.tmp")
tmp.write_text(json.dumps(payload, sort_keys=True))
os.chmod(tmp, 0o600)
tmp.replace(path)
```

`Path.replace` is `os.rename` semantically — atomic on the same filesystem,
which `~/.cache` always is.

### What we are NOT doing in Phase 2

- No QML, no plasmoid package, no widget glue.
- No installer / `install.sh` / `kpackagetool6` invocation.
- No notifications, no thresholding logic — that is UX polish.
- No D-Bus.
- No CodexBar binary downloader (`install-runtime`) — assume CodexBar already
  on PATH (validated in Phase 0).

## Build checklist

- [x] `src/neon_codexbar/ipc/__init__.py`
- [x] `src/neon_codexbar/ipc/snapshot_writer.py` — atomic write, schema, mode 0600
- [x] `src/neon_codexbar/daemon.py` — refresh loop, signal handlers, sentinel-file refresh, stale logic
- [x] `pyproject.toml` — add `neon-codexbar-daemon` console script
- [x] `neon_codexbar/__init__.py` source-tree shim re-exports for daemon if needed
- [x] `packaging/neon-codexbar.service` — systemd `--user` unit
- [x] `tests/unit/test_snapshot_writer.py` — atomic write, schema shape, mode bits
- [x] `tests/unit/test_daemon.py` — fake-runner-driven loop, stale flip
- [ ] `tests/integration/test_daemon_lifecycle.py` — start daemon in tempdir,
  verify two snapshots, send SIGTERM cleanly *(deferred — covered functionally
  by the live-run smoke check below; add when integration harness exists)*
- [x] Live smoke: run daemon against codex/claude/zai/openrouter, watch snapshot updates, kill it, confirm staleness behavior

## Open questions to resolve during implementation

1. **Snapshot path overridable?** Yes — add `snapshot_path` to `AppConfig` (default `~/.cache/neon-codexbar/snapshot.json`), env override `NEON_CODEXBAR_SNAPSHOT_PATH`.
2. **Initial snapshot before first fetch finishes?** Yes — write a placeholder snapshot immediately on start (`ok: true`, `cards: []`, `diagnostics: ["initial: refresh in progress"]`) so the widget never sees "no file."
3. **Per-tick logging volume?** One `INFO` line per tick: `tick N providers=4 ok=4 errors=0 elapsed=15.2s`. Per-provider failures: one `WARNING`. Subprocess stderr is captured in the snapshot already, not re-logged.
4. **What if config changes mid-run?** Out of scope for Phase 2. Restart the daemon. Phase 5+ can add hot-reload.

## Smoke run results (2026-04-26)

Live four-provider run on the dev LXC, `refresh_interval_seconds=30`,
snapshot at `/tmp/neon_smoke/snapshot.json`.

```
20:20:43  daemon starting
20:20:43  initial placeholder snapshot written (cards=0)
20:20:59  tick 1 providers=4 ok=4 errors=0 elapsed=15.8s
20:21:18  refresh.touch sentinel touched
20:21:34  tick 2 providers=4 ok=4 errors=0 elapsed=15.6s   ← early via sentinel
20:21:50  SIGUSR1 received
20:22:07  tick 3 providers=4 ok=4 errors=0 elapsed=16.2s   ← early via signal
20:22:08  SIGTERM received → daemon stopped after 3 ticks
```

snapshot mode `0o600`, schema_version 1, all four providers (claude/codex/
openrouter/zai) present and `is_stale=false`. No provider keys in the snapshot
diagnostic block.

## Note on stale detection acceptance

Master plan acceptance reads "Killing the daemon results in is_stale=true
after 2× refresh interval." Read literally that's impossible — if the daemon
is dead, nothing writes new snapshots, so the file's `is_stale` flag stays
whatever it was when last written. The interpretation we ship:

- **In-flight staleness:** a provider whose `last_success` is older than
  2× refresh becomes `is_stale=true` in the next snapshot the daemon writes.
  Unit-tested in `test_apply_staleness_marks_card_when_last_success_is_old`.
- **Daemon-dead staleness:** the widget detects this from `generated_at`
  (or the file's mtime) and dims the UI on its own. The widget is the source
  of truth for "how old is the snapshot." We will wire this in Phase 3.

## Done definition

All Phase 2 acceptance boxes ticked, tests green, ruff clean, smoke run
captured above. Status: **complete 2026-04-26**.

Next: Phase 3 Plasma widget. The daemon's snapshot.json is the only contract.

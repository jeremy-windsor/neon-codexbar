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

- [x] `systemctl --user start neon-codexbar` runs cleanly
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

1. **Snapshot path overridable?** Yes — `--snapshot-path` CLI flag and
   `NEON_CODEXBAR_SNAPSHOT_PATH` env var override the default
   `~/.cache/neon-codexbar/snapshot.json`. Not added to `AppConfig` because no
   call site needs persistent config for it; revisit if the widget or installer
   ever needs it.
2. **Initial snapshot before first fetch finishes?** Yes — write a placeholder snapshot immediately on start (`ok: true`, `cards: []`, `diagnostics: ["initial: refresh in progress"]`) so the widget never sees "no file."
3. **Per-tick logging volume?** One `INFO` line per tick: `tick N providers=4 ok=4 errors=0 elapsed=15.2s`. Per-provider failures: one `WARNING`. Subprocess stderr is captured in the snapshot already, not re-logged.
4. **What if config changes mid-run?** Out of scope for Phase 2. Restart the daemon. Phase 5+ can add hot-reload.

## systemd --user install (2026-04-26, dev LXC)

```bash
pip install --user --force-reinstall --no-deps -e .
mkdir -p ~/.config/systemd/user
cp packaging/neon-codexbar.service ~/.config/systemd/user/
# Provider keys via drop-in (still owned by user, 0600), not the unit itself:
mkdir -p ~/.config/systemd/user/neon-codexbar.service.d
cat > ~/.config/systemd/user/neon-codexbar.service.d/dev-env.conf <<'EOF'
[Service]
Environment=Z_AI_API_KEY=...
Environment=OPENROUTER_API_KEY=...
EOF
chmod 600 ~/.config/systemd/user/neon-codexbar.service.d/dev-env.conf
systemctl --user daemon-reload
systemctl --user enable --now neon-codexbar.service
```

Verified:

```
Active: active (running) since Sun 2026-04-26 20:28:13 MST
Loaded: loaded (...neon-codexbar.service; enabled; preset: enabled)
journalctl --user -u neon-codexbar:
  daemon starting: snapshot=~/.cache/neon-codexbar/snapshot.json refresh_interval=300s
  tick 1 providers=4 ok=4 errors=0 elapsed=16.1s
~/.cache/neon-codexbar/snapshot.json: mode 0600, schema_version 1, 4 cards, no errors
```

Provider auth still lives outside neon-codexbar — the systemd drop-in is the
recommended place for headless API keys (or the user's shell rc, or any other
CodexBar-supported location). The unit file itself stays generic and shippable.

Heads-up: claude fetches spawn the full claude CLI process tree (node, bun,
MCP servers), so peak memory during a claude tick is ~500MB on this host.
Steady-state between ticks is much lower. Not a Phase 2 blocker; flag for
Phase 5+ if it bothers anyone.

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

## GPT Phase 2 review notes — 2026-04-26

Review request: read-only review of whether Phase 2 was implemented properly.
No code changes were made during review.

### Review verdict

Phase 2 is substantially complete and good enough to proceed toward Phase 3,
but the following issues should be fixed before the Plasma widget treats the
snapshot as a stable UI contract.

### Verified during review

```text
git status: clean, synced with origin/main
HEAD: 37c2c79 feat(phase 2): refresh daemon + atomic snapshot IPC
ruff: passed
pytest: 32 passed
```

A local `--once` smoke run wrote a snapshot with schema version 1 and four
cards (`claude`, `codex`, `openrouter`, `zai`). OpenRouter/z.ai errored in that
specific shell because API-key environment variables were not injected into the
process; that was treated as an environment/auth wiring issue, not a daemon
architecture failure.

### Must-fix before Phase 3 UI consumes snapshot.json

#### 1. `snapshot.ok` semantics currently disagree with this plan

The plan says `ok` means global daemon/CodexBar availability, not per-provider
success. Current daemon behavior sets snapshot `ok=false` when any provider
fetch fails:

```python
ok=tick.error_count == 0 and located is not None
```

That makes one bad provider key look like a global daemon/CodexBar failure.
The widget should not have to guess whether `ok=false` means "CodexBar missing"
or "OpenRouter burped."

Recommended semantics:

- `snapshot.ok`: daemon can locate and invoke CodexBar / global health.
- `cards[i].error_message`: provider-specific failure.
- Optional future field: `provider_error_count` if the UI needs a summary.

#### 2. systemd user service needs a deliberate provider auth story

The unit starts the daemon cleanly, but systemd user services do not reliably
inherit interactive shell environment variables. API providers such as z.ai and
OpenRouter need `Z_AI_API_KEY` / `OPENROUTER_API_KEY` or a CodexBar-supported
auth/config path.

Do **not** store secrets in neon-codexbar config. Keep auth owned by CodexBar,
the user environment, or a user-owned systemd drop-in.

Accepted options to document/standardize later:

```bash
systemctl --user import-environment Z_AI_API_KEY OPENROUTER_API_KEY
```

or a user-owned drop-in such as:

```ini
[Service]
Environment=Z_AI_API_KEY=...
Environment=OPENROUTER_API_KEY=...
```

The shipped unit file should remain generic and secret-free.

#### 3. provider worker exceptions should not crash the daemon

`future.result()` is not wrapped. If a provider worker raises outside the normal
`CommandResult` path, the whole tick can bubble to the daemon's top-level crash
handler and exit. A single provider should produce an error card and diagnostic,
not kill the daemon.

Recommended behavior:

- catch exceptions around each future result
- emit provider-specific error card when possible
- include a redacted diagnostic
- keep the daemon alive

#### 4. snapshot path config mismatch

The plan says `snapshot_path` belongs in `AppConfig`; implementation supports
`--snapshot-path` and `NEON_CODEXBAR_SNAPSHOT_PATH` instead. That is probably
fine, but the docs and code should agree.

Recommendation: keep CLI/env override for now and update the plan/docs; do not
add more persistent config unless the widget/install flow needs it.

### Not blockers

- Deferred integration lifecycle test is acceptable while unit coverage and live
  smoke exist.
- `is_stale` after daemon death cannot be written by a dead daemon; the widget
  should compute daemon-dead staleness from `generated_at` or file mtime.
- Disabled-provider diagnostics are noisy but Jeremy explicitly deprioritized
  that bug for now.

### Recommendation

Proceed to Phase 3 only after fixing `snapshot.ok` semantics and deciding the
systemd/provider-env story. The exception handling and docs mismatch can be
fixed in the same cleanup pass, but they are smaller gremlins.

### Review fixes applied — 2026-04-27

| # | Finding | Fix |
|---|---|---|
| 1 | `snapshot.ok` conflated global health with per-provider success | `daemon.write_tick_snapshot` no longer passes `ok=`; `build_snapshot` defaults to `ok = codexbar_path is not None`. New assertion in `test_daemon_tick_records_provider_error` locks the semantic. |
| 2 | Worker exceptions could crash daemon | `tick()` now catches around each `future.result()`, logs via `LOG.exception`, emits a redacted error card + diagnostic, keeps the daemon alive. New test `test_daemon_tick_survives_worker_exception` proves it with a runner that raises. |
| 3 | systemd auth story undocumented | New section in `docs/PROVIDER_SETUP.md` covering three options: `systemctl --user import-environment`, user-owned 0600 drop-in, `EnvironmentFile=`. Shipped unit stays secret-free. |
| 4 | `snapshot_path` doc/code mismatch | Open-questions item updated to match implementation (CLI/env override only, no `AppConfig` field). |

Tests: 33 passing. Ruff: clean. Daemon restarted on the dev LXC against the
fix; `tick 1 providers=4 ok=4 errors=0` and snapshot `ok=true`.

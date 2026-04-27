# GPT / Forge Peer Review — neon-codexbar Phase 0–2

Review date: 2026-04-26  
Reviewer: Forge via `kimi-k2.6` council-style peer review  
Scope: Phase 0 live validation, Phase 1 adapter/normalizer/source policy, Phase 2 daemon + snapshot IPC  
Mode: review-only; no code changes requested or made by reviewer

## Verdict

Phase 2 is substantially complete and architecturally sound. The project is close to ready for Phase 3, but the snapshot contract should be tightened before QML consumes it.

Proceed to Phase 3 after fixing two must-fix issues:

1. `snapshot.ok` semantics.
2. provider worker exception isolation.

The rest are smaller cleanup/docs items.

## What is solid

- **Architecture boundary is clean.** CodexBar owns provider auth, provider fetching, API keys, cookies, and provider-specific behavior. `neon-codexbar` owns Linux/KDE UX policy, source policy, normalization, diagnostics, and snapshot IPC.
- **Linux source policy is explicit.** `codex -> cli`, `claude -> cli`, `zai -> api`, `openrouter -> api`; no `--source auto` guessing on Linux.
- **Adapter code is testable.** `runner.py`, `discovery.py`, `normalizer.py`, and `source_policy.py` are small and fixture-driven.
- **Fixtures are grounded in live captures.** Codex, Claude, z.ai, and OpenRouter payloads are represented in `tests/fixtures/codexbar/`.
- **Normalizer handles non-trivial provider shape.** z.ai tertiary windows and OpenRouter credit/balance style are supported instead of forcing everything into two quota bars.
- **Snapshot writer is correct.** `src/neon_codexbar/ipc/snapshot_writer.py` writes a schema-versioned JSON file atomically via temp file + fsync + replace and sets mode `0600`.
- **Daemon lifecycle is real.** Phase 2 includes startup placeholder snapshot, periodic refresh, sentinel refresh, `SIGUSR1`, graceful shutdown, and stale-card logic.
- **Config hygiene is enforced.** `config.py` rejects suspicious secret-looking config keys; provider secrets do not belong in neon-codexbar config.
- **systemd unit is generic and secret-free.** `packaging/neon-codexbar.service` does not bake in provider keys.
- **Tests are green.** At review time, ruff passed and pytest reported 32 passing tests.

## Must-fix before Phase 3

### 1. Fix `snapshot.ok` semantics

Location:

```text
src/neon_codexbar/daemon.py:write_tick_snapshot()
```

Current behavior effectively makes root snapshot `ok` depend on provider success:

```python
ok=tick.error_count == 0 and located is not None
```

Problem: one bad provider key makes the whole snapshot look globally broken. The Phase 3 widget should not have to guess whether `ok=false` means:

- CodexBar missing/broken globally, or
- one provider failed locally.

Recommended contract:

```text
snapshot.ok = daemon can locate/invoke CodexBar and write a valid snapshot
cards[i].error_message = provider-specific failure
provider_error_count = optional root summary for widget convenience
```

Recommended implementation direction:

```python
ok = located is not None
provider_error_count = tick.error_count
```

If `provider_error_count` is added, document it in the daemon/widget contract and tests.

### 2. Harden provider worker exception handling

Location:

```text
src/neon_codexbar/daemon.py:tick()
```

Current pattern:

```python
for future in as_completed(futures):
    _entry, fetched_cards, diagnostic = future.result()
```

Problem: if a worker raises outside the normal `CommandResult` path, `future.result()` re-raises and can abort the tick. The outer daemon crash handler then exits non-zero; with systemd restart this can become a provider-triggered crash loop.

Recommended behavior:

- catch exceptions around each `future.result()`
- emit a redacted diagnostic
- produce an error card when provider identity is known
- keep the daemon alive

Sketch:

```python
for future in as_completed(futures):
    try:
        _entry, fetched_cards, diagnostic = future.result()
    except Exception as exc:
        diagnostics.append(f"worker crashed: {exc}")
        error_count += 1
        continue
    cards.extend(fetched_cards)
    if diagnostic:
        diagnostics.append(diagnostic)
        error_count += 1
```

Better version: keep a `future -> ProviderConfigEntry` map so the error diagnostic can name the provider.

## Should-fix before or during early Phase 3

### 3. Canonicalize systemd provider auth documentation

Locations:

```text
docs/PROVIDER_SETUP.md
plans/phase-2-daemon.md
packaging/neon-codexbar.service
```

The systemd user service will not reliably inherit interactive shell environment variables. z.ai/OpenRouter need `Z_AI_API_KEY` / `OPENROUTER_API_KEY` or another CodexBar-supported auth path.

Do not store secrets in neon-codexbar config.

Document one canonical approach, likely a user-owned systemd drop-in:

```ini
[Service]
Environment=Z_AI_API_KEY=...
Environment=OPENROUTER_API_KEY=...
```

or document `systemctl --user import-environment` as an alternative.

### 4. Cache CodexBar version metadata

Location:

```text
src/neon_codexbar/daemon.py:write_initial_snapshot()
src/neon_codexbar/daemon.py:write_tick_snapshot()
```

`runner.version()` is called every tick. It is not a huge issue at a 300-second refresh interval, but it is unnecessary subprocess churn. Cache locate/version after first success and refresh on daemon restart or explicit manual refresh if needed.

### 5. Wire provider display overrides eventually

Location:

```text
src/neon_codexbar/adapter/normalizer.py
src/neon_codexbar/config.py
```

`DISPLAY_NAMES` is hardcoded. `provider_overrides` exists in config but is not wired into normalization. New upstream providers will show raw IDs until code is updated.

This is not a Phase 2 blocker, but it matters for user-facing polish.

### 6. Snapshot path docs/code mismatch

The Phase 2 plan discussed `snapshot_path` in `AppConfig`; implementation supports CLI/env override instead:

```text
--snapshot-path
NEON_CODEXBAR_SNAPSHOT_PATH
```

This is acceptable. Prefer documenting the implementation rather than adding persistent config too early.

## Missing but acceptable for now

| Item | Status | Notes |
|---|---|---|
| QML plasmoid | Not started | Correctly deferred to Phase 3 |
| Installer scripts | Not started | Later packaging phase |
| CodexBar binary downloader | Not started | Keep CodexBar as external runtime for now |
| Integration daemon lifecycle test | Deferred | Unit tests + smoke runs cover most behavior for now |
| Config hot-reload | Out of scope | Restart daemon when config changes |
| Provider override rendering | Not wired | UX polish, not daemon contract blocker |

## Recommended daemon/widget contract doc

Create `docs/DAEMON_CONTRACT.md` before serious Phase 3 QML work.

Minimum contract should define:

- default snapshot path: `~/.cache/neon-codexbar/snapshot.json`
- override: `NEON_CODEXBAR_SNAPSHOT_PATH`
- schema version: `1`
- root fields: `schema_version`, `generated_at`, `ok`, `cards`, `diagnostics`, `codexbar`
- optional root summary: `provider_error_count`
- root `ok` semantics: global daemon/CodexBar health only
- per-card failures: `cards[i].error_message`
- daemon-dead staleness: widget computes from `generated_at` or file mtime
- provider staleness: `cards[i].is_stale`
- manual refresh options: touch `refresh.touch` or send `SIGUSR1`

## Final recommendation

Do a small Phase 2 hardening pass before Phase 3:

1. change `snapshot.ok` to global health semantics
2. optionally add `provider_error_count`
3. wrap provider worker exceptions
4. document the daemon/widget contract
5. document the systemd provider-env story in one canonical place

After that, Phase 3 can start without the widget inheriting ambiguous daemon behavior.

The architecture is good. The remaining work is contract hygiene, not a redesign. Tiny goblins, not a dragon.

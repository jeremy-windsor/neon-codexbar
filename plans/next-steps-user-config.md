# neon-codexbar — Next Steps and User Config Plan

Date: 2026-04-26  
Status: after live KDE Neon Codex validation

## Current phase

We are at the end of **Phase 1 + hardening** and have started **live Phase 0 validation**.

That sounds backwards because it is slightly backwards, but on purpose:

- The sandbox could build and test the adapter against fixtures.
- Jeremy's KDE Neon laptop is the only place with real CodexBar CLI/auth/session behavior.
- So Phase 1 adapter work was built first, then Phase 0 live validation is being completed against the real target.

Current state:

| Area | Status |
|---|---|
| Python package / CLI | done |
| CodexBar config discovery | live validated |
| Codex provider fetch via `cli` | live validated |
| Source policy | working for codex/claude/zai/openrouter |
| Redaction | working for account email |
| Tests | passing, 17 tests |
| Runtime installer | not started |
| Daemon/snapshot IPC | not started |
| Plasma widget | not started |
| All-in-one installer | later phase |

Live validation already proved:

```text
codexbar config dump --format json
neon-codexbar discover --json
neon-codexbar diagnose --json
neon-codexbar fetch --json
```

work on KDE Neon for the currently enabled `codex` provider.

## What we are ignoring for now

Discovery currently emits noisy diagnostics for disabled providers that are outside the Linux source policy.

This is not a blocker for the next phase.

Reason:

- the data path works
- the noise is cosmetic/UX
- daemon/widget work can filter or reduce it later
- do not derail the phase plan for a warning-text papercut

Track as deferred polish:

> Disabled unsupported providers should not create prominent diagnostics. Only enabled unsupported providers should warn loudly.

## Configuration ownership model

Core rule:

> CodexBar owns provider configuration and secrets. neon-codexbar owns display preferences and runtime behavior.

That means neon-codexbar should not invent provider credentials, provider auth files, provider token parsing, or provider-specific config schemas.

### CodexBar-owned config

CodexBar remains responsible for:

- which providers exist
- which providers are enabled
- provider auth/session discovery
- API keys/env var names
- provider-specific fetch strategy
- provider-specific payload shape
- CLI output

Known CodexBar config surface:

```bash
codexbar config dump --format json
```

Current observed output shape:

```json
{
  "version": 1,
  "providers": [
    { "id": "codex", "enabled": true },
    { "id": "claude", "enabled": false },
    { "id": "zai", "enabled": false },
    { "id": "openrouter", "enabled": false }
  ]
}
```

neon-codexbar reads this; it does not replace it.

### neon-codexbar-owned config

neon-codexbar may store only UI/runtime preferences, such as:

- refresh interval
- display order
- hidden providers
- warning/critical thresholds
- snapshot path
- explicit CodexBar binary path override
- whether disabled providers should be shown in diagnostics
- local widget layout preferences

Existing local config module:

```text
src/neon_codexbar/config.py
```

Default path:

```text
~/.config/neon-codexbar/config.json
```

Environment override:

```text
NEON_CODEXBAR_CONFIG=/path/to/config.json
```

CodexBar binary override:

```text
NEON_CODEXBAR_CODEXBAR_PATH=/path/to/codexbar
```

### Absolutely not stored by neon-codexbar

Do not store these in neon-codexbar config:

- API keys
- cookies
- bearer tokens
- OAuth tokens
- refresh tokens
- provider passwords
- provider session blobs

Current code already rejects sensitive keys under provider overrides. Keep that rule.

## How users enable providers

Short version:

> Users enable/configure providers through CodexBar-supported config/auth surfaces, then neon-codexbar discovers and renders them.

### Phase 1 / manual validation flow

For now, provider enablement is manual and CodexBar-first:

1. User configures provider using CodexBar-supported method.
2. User verifies raw CodexBar works:

   ```bash
   codexbar config dump --format json
   codexbar --provider <provider> --source <source> --format json
   ```

3. User verifies neon-codexbar sees it:

   ```bash
   neon-codexbar discover --json
   neon-codexbar fetch --json
   neon-codexbar diagnose --json
   ```

### Linux source policy

Current explicit Linux source policy:

| Provider | Source |
|---|---|
| `codex` | `cli` |
| `claude` | `cli` |
| `zai` | `api` |
| `openrouter` | `api` |

Do not use Linux `--source auto`.

### Provider-specific notes

#### Codex

Validated live on KDE Neon.

Expected command:

```bash
codexbar --provider codex --source cli --format json
```

#### Claude

Expected command:

```bash
codexbar --provider claude --source cli --format json
```

Need live validation after enabling in CodexBar config.

#### z.ai

Expected command:

```bash
codexbar --provider zai --source api --format json
```

Credential source should be CodexBar-supported, likely env/config. neon-codexbar must not store the key.

Need live validation after enabling in CodexBar config.

#### OpenRouter

Expected command:

```bash
codexbar --provider openrouter --source api --format json
```

OpenRouter may expose balance/credits instead of quota windows. Renderer must support credit meters without inventing fake session/weekly windows.

Need live validation after enabling in CodexBar config.

## Tracking user config

There are two layers to track.

### 1. Provider state snapshot

This comes from CodexBar:

```bash
codexbar config dump --format json
```

neon-codexbar should track this as runtime state, not own it.

Recommended normalized fields:

```json
{
  "provider_id": "codex",
  "enabled": true,
  "source_policy": "cli",
  "configured_source": null,
  "skipped": false,
  "diagnostic": null
}
```

This is already close to the current `discover --json` output.

### 2. neon-codexbar preferences

This comes from:

```text
~/.config/neon-codexbar/config.json
```

Recommended v1 shape:

```json
{
  "version": 1,
  "codexbar_path": null,
  "refresh_interval_seconds": 300,
  "warning_threshold_percent": 70,
  "critical_threshold_percent": 90,
  "provider_display_mode": "enabled-only",
  "provider_overrides": {
    "codex": {
      "display_name": "Codex",
      "hidden": false,
      "order": 10
    }
  }
}
```

Rules:

- provider overrides are UI metadata only
- sensitive keys are rejected
- unknown UI keys can be ignored or preserved later
- no provider auth fields

## Recommended next steps

### Step 1 — Finish live Phase 0 for four providers

Validate these on Jeremy's KDE Neon laptop:

```bash
codexbar --provider codex --source cli --format json
codexbar --provider claude --source cli --format json
codexbar --provider zai --source api --format json
codexbar --provider openrouter --source api --format json
```

Then run:

```bash
neon-codexbar discover --json
neon-codexbar fetch --json
neon-codexbar diagnose --json
```

Acceptance:

- Codex remains working.
- Claude works or returns a clear setup/auth error.
- z.ai works or returns a clear setup/auth error.
- OpenRouter works or returns a clear setup/auth error.
- No secrets appear in neon-codexbar output.
- Live payload shapes are either compatible with fixtures or documented.

If payload shape differs, patch normalizer/tests before moving on.

### Step 2 — Document provider enablement notes

Create user-facing docs:

```text
docs/PROVIDER_SETUP.md
```

Contents:

- CodexBar is the provider engine
- where CodexBar config lives, if known
- how to verify provider config
- Linux source policy table
- warning not to use `--source auto`
- provider-specific notes for codex/claude/zai/openrouter
- how to run `neon-codexbar diagnose --json`

No secrets. No pasted keys.

### Step 3 — Phase 2 daemon + snapshot IPC

Only after live provider validation is boring.

Build:

- daemon refresh loop
- snapshot JSON writer
- atomic writes
- stale detection
- subprocess timeout/backoff
- no QML
- no installer yet

Snapshot path proposal:

```text
~/.cache/neon-codexbar/snapshot.json
```

Snapshot should contain:

```json
{
  "schema_version": 1,
  "generated_at": "...",
  "ok": true,
  "cards": [],
  "diagnostics": [],
  "codexbar": {
    "available": true,
    "path": "/home/user/.local/bin/codexbar",
    "version": "CodexBar"
  }
}
```

### Step 4 — Phase 3 Plasma widget

Only after daemon snapshot is stable.

Widget reads snapshot only. QML does not call CodexBar directly.

### Step 5 — Installer/runtime packaging

Later phase.

Installer should:

- install Python package
- install Plasma widget
- install systemd user service
- locate existing `codexbar`
- optionally install pinned CodexBar runtime to `~/.local/bin/codexbar`
- verify checksum if downloading
- avoid overwriting user-managed binaries

## Immediate decision

Do not change plan because the current status was confusing.

Current next action:

> Complete live validation for Claude, z.ai, and OpenRouter on KDE Neon, then update fixtures/docs based on real payloads.

Ignore disabled-provider diagnostic noise for now.

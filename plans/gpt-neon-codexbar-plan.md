# neon-codexbar Plan — GPT Review v2

Date: 2026-04-26
Author: Will / GPT review
Repo: `jeremy-windsor/neon-codexbar`

## Executive read

Build `neon-codexbar` as a KDE Neon / Plasma frontend powered by upstream `codexbar` CLI.

The revised Claude plan is now mostly right: it adopted the correct architectural line and turned into a useful implementation spec. This document keeps that stronger structure, adds the fixes I want before implementation, and preserves the non-negotiable rule:

> **CodexBar owns providers. neon-codexbar owns KDE UX.**

No provider auth/parsing swamp in Python. No second secrets store. No QML subprocess goblin circus.

```text
CodexBar / CodexBarCore
  owns providers, config, auth, fetch strategies, parsing, CLI JSON

neon-codexbar
  owns KDE widget/systray UX, install flow, Linux source policy, rendering, diagnostics
```

## What we know already

Tested on KDE Neon / Jeremy's laptop:

- `codexbar --provider codex --source cli --format json --pretty` works.
- `codexbar --provider claude --source cli --format json --pretty` works.
- z.ai works through CodexBar CLI with API key/env and `--source api`.
- OpenRouter works through CodexBar CLI with API source and returns balance/credit usage.
- `jjlinares/codexbar-kde-widget` proves a pure QML Plasma widget can call CodexBar CLI and render providers.
- `radoslavchobanov/PlasmaCodexBar` proves another KDE widget direction works, but its original provider approach reimplemented provider logic in Python, which we should not copy.
- Linux `--source auto` is unsafe/noisy. Many providers fall into macOS/web-only paths unless we force source policy.

## Product shape

`neon-codexbar` should feel like its own KDE app while using CodexBar internally as the provider engine.

User-facing:

- KDE/Plasma widget first
- optional systray app later
- provider cards
- quota windows
- balances/credits
- stale/error/setup states
- diagnostics that do not leak secrets
- no need for users to understand CodexBar unless troubleshooting or reading docs

Implementation reality:

- install or locate `codexbar` CLI
- keep provider config/secrets in CodexBar-supported locations
- daemon calls CodexBar CLI for all provider data
- widget reads normalized snapshots
- docs disclose CodexBar dependency/license/attribution

## Widget first, systray later

The app should target a **Plasma widget first**.

Reason: existing proof points are Plasma widgets, and KDE users expect panel widgets. A systray-only app is acceptable later, but it adds another UX/packaging surface before the core problem is solved.

Phase order:

1. Plasma widget + daemon + snapshot file
2. optional app menu entry for diagnostics/settings
3. optional real systray mode if panel widget limitations become annoying

Do not build both widget and systray in v0.1 unless the implementation is trivial. It will not be trivial. Nothing involving QML ever is. QML is JavaScript wearing a trench coat.

## Licensing and transparency

It is fine for the UX to present as `neon-codexbar`, but it must not pretend provider functionality is original.

Required:

- include CodexBar license/notice in repo and app docs
- document that provider data is powered by CodexBar CLI
- link upstream: `https://github.com/steipete/CodexBar`
- document which parts are ours vs upstream
- About dialog must include CodexBar attribution

Suggested wording:

> neon-codexbar is a KDE/Plasma frontend powered by the CodexBar CLI provider engine.

## Architecture

### Components

1. **Installer/bootstrap**
   - checks Plasma 6 / KDE Neon prerequisites
   - checks Python 3.10+
   - checks/installs `codexbar` CLI without clobbering user-managed binaries
   - installs Python daemon
   - installs Plasma widget
   - installs optional systemd user service
   - verifies a one-shot fetch works

2. **CodexBar adapter layer**
   - single abstraction around CLI calls
   - handles command construction
   - enforces Linux-safe source policy
   - parses JSON
   - normalizes data into UI blocks
   - redacts diagnostics
   - pins/validates known CLI version behavior

3. **Backend daemon**
   - Python service under `systemd --user`
   - runs all CodexBar subprocess calls
   - writes atomic `snapshot.json`
   - handles refresh/backoff/stale state
   - exposes one-shot CLI commands for debugging

4. **Plasma widget**
   - QML-only display layer
   - never spawns provider subprocesses
   - reads snapshot file
   - renders cards dynamically
   - manual refresh signal to daemon via sentinel file or lightweight command

5. **Docs/diagnostics**
   - installation
   - CodexBar setup
   - provider enablement
   - source policy
   - troubleshooting
   - redacted diagnostic bundle

## Repository layout

Use Claude's revised layout as the base, with one clarification: docs should explicitly separate architecture from CodexBar provider policy.

```text
neon-codexbar/
├── README.md
├── LICENSE
├── NOTICE
├── pyproject.toml
├── docs/
│   ├── ARCHITECTURE.md
│   ├── CODEXBAR_RUNTIME.md
│   ├── SOURCE_POLICY.md
│   ├── PROVIDERS.md
│   ├── ATTRIBUTION.md
│   └── TROUBLESHOOTING.md
├── packaging/
│   ├── install.sh
│   ├── uninstall.sh
│   └── neon-codexbar.service
├── plasmoid/
│   ├── metadata.json
│   └── contents/
│       ├── ui/
│       │   ├── main.qml
│       │   ├── CompactRepresentation.qml
│       │   ├── FullRepresentation.qml
│       │   ├── ProviderCard.qml
│       │   ├── QuotaWindowBar.qml
│       │   ├── CreditMeter.qml
│       │   └── ConfigGeneral.qml
│       └── config/
│           ├── main.xml
│           └── config.qml
├── src/
│   └── neon_codexbar/
│       ├── adapter/
│       │   ├── installer.py
│       │   ├── runner.py
│       │   ├── discovery.py
│       │   ├── source_policy.py
│       │   └── normalizer.py
│       ├── daemon.py
│       ├── models.py
│       ├── config.py
│       ├── diagnostics.py
│       └── cli.py
└── tests/
    ├── fixtures/
    ├── unit/
    └── integration/
```

## CodexBar adapter layer

### Binary management

Find `codexbar` in this order:

1. explicit path in neon config
2. PATH
3. `~/.local/bin/codexbar`
4. installer-managed runtime path

Rules:

- Do not silently overwrite an existing user-managed `codexbar`.
- If version mismatch exists, warn and offer installer-managed runtime.
- If downloading a binary, verify SHA-256.
- Keep the pinned target version in repo, e.g. `vendor/codexbar/version.txt` and `vendor/codexbar/checksums.json`.
- `neon-codexbar --version` must print both neon-codexbar and codexbar versions.

### Invocation contract

Every provider fetch must go through one function, roughly:

```python
fetch_provider(provider_id: str, source: str, timeout: int = 10) -> RawProviderResult
```

Rules:

- always pass `--provider <id>`
- always pass explicit `--source <source>`
- always request JSON output
- never rely on Linux `--source auto`
- capture stdout/stderr/exit code
- redact anything that looks like a token/key before diagnostics
- do not surface raw stderr directly in the widget

Important: verify exact CodexBar CLI flags during Phase 1 before hardcoding docs.

Known working examples from testing:

```bash
codexbar --provider codex --source cli --format json --pretty
codexbar --provider claude --source cli --format json --pretty
codexbar --provider zai --source api --format json --pretty
codexbar --provider openrouter --source api --format json --pretty
codexbar config dump --pretty
```

Do **not** assume `codexbar config dump --format json` exists until tested. Claude's plan used that form; we need to verify it. If `--pretty` is the actual stable JSON command, use that.

### Provider discovery

Discovery uses CodexBar config output.

Desired behavior:

- read all provider IDs known to CodexBar
- know whether each provider is enabled
- filter based on neon config display mode
- skip unknown providers unless source policy has an entry
- show skipped/unknown providers in diagnostics, not the main UI

Display modes:

- `enabled-only` default
- `all-configured`
- `debug-all`

### Linux source policy

Initial table:

| Provider | Linux source | Status |
|---|---|---|
| codex | `cli` | tested working |
| claude | `cli` | tested working |
| zai | `api` | tested working |
| openrouter | `api` | tested working |
| kimik2 | `api` | needs token test |
| gemini | likely `api` or CLI-backed source | needs auth test |
| copilot | likely `api` | needs token/device-flow test |
| kilo | `api` or CLI fallback | needs auth test |
| opencode | unknown/problematic | likely needs upstream Linux support/manual flow |

Unknown providers default to:

```text
skip + diagnostic note
```

Not:

```text
guess source + spam failing subprocesses
```

Because we are building software, not a smoke machine.

## Configuration and secrets

### Our config: UI only

`~/.config/neon-codexbar/config.json`:

```json
{
  "version": 1,
  "codexbar_path": null,
  "refresh_interval_seconds": 300,
  "warning_threshold_percent": 70,
  "critical_threshold_percent": 90,
  "provider_display_mode": "enabled-only",
  "provider_overrides": {
    "zai": { "display_name": "Z.ai (GLM)" }
  }
}
```

No secrets here.

### Provider secrets: CodexBar only

Provider keys/auth live in places CodexBar already reads:

- `~/.codexbar/config.json`
- provider CLI auth files like `~/.codex`, Claude CLI auth, etc.
- CodexBar-supported env vars such as:
  - `Z_AI_API_KEY`
  - `OPENROUTER_API_KEY`

`neon-codexbar` must not invent its own provider key names or secret file.

### Systemd user env gotcha

This is the big fix Claude's plan needs called out clearly.

A `systemd --user` daemon may not inherit shell env vars. That means `Z_AI_API_KEY` and `OPENROUTER_API_KEY` might work in a terminal but fail in the daemon.

Preferred order:

1. Put long-lived provider keys in CodexBar config if CodexBar supports it.
2. If using env vars, installer/docs must explain importing them into the user manager:

```bash
systemctl --user import-environment Z_AI_API_KEY OPENROUTER_API_KEY
systemctl --user restart neon-codexbar.service
```

3. Optional later: support an env file loaded by the **systemd unit only**, not parsed/stored by the app as a secret manager.

If we add env-file support, it should be explicit, documented, mode `0600`, and still use CodexBar's env var names. No parallel secret schema.

## Data model strategy

Do not hardcode `primary = Session` and `secondary = Weekly`.

Providers differ:

- Codex: primary/secondary look like session/weekly
- Claude: primary/secondary look like session/weekly
- z.ai: primary/secondary/tertiary can be 1-week / 1-minute / 5-hour windows
- OpenRouter: no quota windows; returns balance/credits/usage

Normalize into generic display blocks:

```python
@dataclass
class QuotaWindow:
    id: str | None
    used_percent: float | None
    resets_at: datetime | None
    reset_description: str | None
    window_label: str | None
    window_minutes: int | None
    raw: dict

@dataclass
class CreditMeter:
    label: str
    balance: float | None
    used: float | None
    total: float | None
    used_percent: float | None
    currency: str | None
    raw: dict

@dataclass
class ProviderCard:
    provider_id: str
    display_name: str
    source: str
    version: str | None
    identity: dict
    plan: str | None
    login_method: str | None
    quota_windows: list[QuotaWindow]
    credit_meters: list[CreditMeter]
    model_usage: list[dict]
    error_message: str | None
    setup_hint: str | None
    is_stale: bool
    last_success: datetime | None
    last_attempt: datetime
```

Renderer rules:

- draw all quota windows in returned order
- use CodexBar-provided labels when available
- fallback label: `Window 1`, `Window 2`, etc.
- draw credit meters when quota windows are absent or when provider exposes both
- show setup/error card for explicitly enabled providers that fail
- never hide enabled provider failures silently

## OpenRouter display rule

OpenRouter currently returns credit/balance usage rather than primary/secondary/tertiary windows.

Display should show:

- balance
- total credits
- total usage
- used percent
- rate limit if present
- key status if present

No fake quota bars. If there is no quota window, don't invent one. This is basic dignity.

## z.ai display rule

z.ai may return primary/secondary/tertiary windows. Display all of them dynamically.

Do not label them Session/Weekly unless CodexBar itself provides those exact labels.

## Daemon model

Use Claude's daemon approach, with conservative defaults.

### Lifecycle

- `systemd --user` service
- logs to journald
- one-shot CLI mode for debugging
- graceful reload/refresh

### Refresh loop

Every refresh interval:

1. discover enabled providers
2. apply Linux source policy
3. fetch providers with bounded concurrency
4. normalize results
5. atomic-write snapshot file
6. update stale/error state

Concurrency:

- start with max 4 concurrent provider calls
- not 8 until we have evidence it is harmless
- per-provider timeout: 10s
- retry/backoff on repeated failures
- no tight loops

Backoff:

- first failure: retry next normal interval
- repeated failures: exponential-ish backoff capped at 15 minutes
- manual refresh overrides backoff once

### Snapshot IPC

Use atomic JSON file:

```text
~/.cache/neon-codexbar/snapshot.json
```

Write pattern:

```text
snapshot.json.tmp -> fsync -> rename snapshot.json
```

Widget reads only `snapshot.json`.

Open question: verify Plasma 6 file watching. If unreliable, fallback to polling every 5 seconds.

## Plasma widget

QML components:

- `CompactRepresentation.qml`
  - panel icon
  - color ring based on worst visible usage
  - stale/error indicator

- `FullRepresentation.qml`
  - refresh button
  - provider card list
  - settings/diagnostics entry

- `ProviderCard.qml`
  - provider icon/name/source
  - identity/plan/login method where safe
  - quota windows
  - credit meters
  - setup/error hints

- `QuotaWindowBar.qml`
- `CreditMeter.qml`
- `ConfigGeneral.qml`

Widget rules:

- no provider subprocesses
- no secret handling
- no provider-specific API calls
- no hardcoded primary/secondary semantics
- use theme colors
- test light + dark themes

## CLI surface

Provide one app CLI for users and implementation agents:

```bash
neon-codexbar --version
neon-codexbar config show
neon-codexbar config set <key> <value>
neon-codexbar discover
neon-codexbar fetch --json
neon-codexbar diagnose
neon-codexbar install-runtime
neon-codexbar refresh
```

`diagnose` must redact:

- API keys
- bearer tokens
- cookies
- auth headers
- email can be optionally redacted with `--redact-identity`

Default diagnostic output should be safe to paste into GitHub issues.

## Provider extension strategy

When a provider is missing or broken:

1. Add/fix provider in CodexBar using upstream `docs/provider.md`:
   - descriptor
   - fetch strategy
   - parser/fetcher
   - CLI source modes
   - tests/docs

2. Confirm Linux CLI output:

```bash
codexbar --provider <id> --source <source> --format json --pretty
```

3. Update `neon-codexbar` only for:
   - icon/name/dashboard metadata if needed
   - source policy
   - display mapping if a new output shape appears

Rule: provider auth/parsing does not live in `neon-codexbar`.

Exception: a temporary local proof-of-concept may be allowed only if it is explicitly marked disposable and deleted/replaced by CodexBar work before release.

## MVP scope

MVP includes:

- Plasma 6 widget
- Python daemon
- CodexBar CLI install/check
- provider discovery from CodexBar config dump
- Linux-safe source policy
- provider cards for tested providers:
  - Codex
  - Claude
  - z.ai
  - OpenRouter
- generic quota window rendering
- OpenRouter-style balance/credit rendering
- errors/setup hints for enabled providers
- refresh/backoff/stale state
- basic settings
- license/attribution docs
- redacted diagnostics

MVP does **not** include:

- rewriting provider fetchers
- storing API keys in widget/app config
- browser cookie import
- KWallet/libsecret integration
- full settings UI for every provider
- Flatpak/AppImage packaging
- macOS/Windows support
- systray mode unless it falls out naturally

## Implementation phases

### Phase 0 — validate CodexBar commands

Before writing architecture into code, test the actual CLI surface on KDE Neon:

```bash
codexbar --version
codexbar config dump --pretty
codexbar config dump --format json   # verify if valid; do not assume
codexbar --provider codex --source cli --format json --pretty
codexbar --provider claude --source cli --format json --pretty
codexbar --provider zai --source api --format json --pretty
codexbar --provider openrouter --source api --format json --pretty
```

Acceptance:

- exact command forms documented
- fixtures saved under `tests/fixtures/`
- source policy matches tested behavior

### Phase 1 — scaffold + adapter proof

- create Python package and CLI
- implement CodexBar binary lookup
- implement runner
- implement hardcoded source policy for four tested providers
- implement one-shot `neon-codexbar fetch --json`

Acceptance:

- one command fetches Codex, Claude, z.ai, OpenRouter and emits normalized JSON
- no QML yet

### Phase 2 — daemon + snapshot IPC

- systemd user service
- refresh loop
- bounded concurrency
- atomic snapshot writer
- stale/error state
- manual refresh trigger

Acceptance:

- daemon writes valid snapshot
- survives provider failure
- no secrets in logs

### Phase 3 — Plasma widget v1

- package installs with `kpackagetool6`
- widget reads snapshot
- provider cards render dynamically
- quota windows and credit meters display correctly
- manual refresh button works

Acceptance:

- Codex/Claude render normal windows
- z.ai renders all returned windows
- OpenRouter renders balance/credits without fake quota windows

### Phase 4 — discovery + diagnostics

- use CodexBar config dump for provider discovery
- support display modes
- unknown providers skip with diagnostic note
- implement redacted `diagnose`

Acceptance:

- enabled providers appear automatically if source policy exists
- failed enabled providers show setup/error card
- diagnostics are safe to paste

### Phase 5 — UX polish

- settings UI
- icons/metadata
- theme cleanup
- README screenshots
- About dialog attribution
- optional notifications

Acceptance:

- non-developer can install/use on KDE Neon without reading source code

### Phase 6 — packaging/distribution

- idempotent install/uninstall
- KDE Neon clean VM test
- tag v0.1.0

Acceptance:

- clean VM to working panel widget using documented install path

## Pros of this approach

- Provider logic stays where it belongs.
- KDE app remains maintainable.
- CodexBar provider additions flow into neon-codexbar.
- Secrets stay in one system.
- QML stays mostly dumb.
- Python daemon gives us testable logic and safe subprocess handling.

## Cons / risks

| Risk | Mitigation |
|---|---|
| CodexBar CLI JSON changes | pin version; adapter owns parsing; fixture tests |
| `config dump` flags/schema differ | Phase 0 validation before implementation |
| systemd daemon misses env vars | prefer CodexBar config; document `systemctl --user import-environment`; optional env file later |
| unknown provider discovered | skip unless source policy exists; show diagnostic note |
| file watcher unreliable | fallback polling |
| provider API rate limits | bounded concurrency + backoff |
| user has their own codexbar binary | do not overwrite; warn and allow explicit path/runtime install |
| upstream CodexBar lacks Linux support | fix/provider PR upstream or maintained CodexBar fork, not Python plugin swamp |

## Recommended decision

Use the revised Claude plan as the implementation skeleton, but apply these corrections:

1. **Widget-first**, systray later.
2. **Phase 0 CLI validation** before coding assumptions.
3. **Systemd env handling** documented and tested.
4. **Non-destructive CodexBar binary management**.
5. **Bounded refresh/backoff** from day one.
6. **No provider auth/parsing in neon-codexbar**.
7. **No local provider secrets store**.

That gives us the best build document: Claude's useful implementation detail plus the architectural guardrails that keep this from turning into a second, worse CodexBar wearing KDE pants.

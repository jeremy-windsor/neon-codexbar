# Provider Setup

neon-codexbar does not own provider configuration. CodexBar does. This document
describes the CodexBar-side setup that neon-codexbar reads from.

> **No secrets in neon-codexbar config.** API keys and auth artifacts live where
> CodexBar already reads them — `~/.codexbar/config.json`, env vars, or per-CLI
> auth files (e.g. `~/.claude/`). neon-codexbar will refuse to store
> sensitive keys.

## Verifying CodexBar is reachable

```bash
codexbar --version
codexbar config dump --format json
```

The first prints the build identifier. The second prints the canonical provider
list. If either fails, install CodexBar before doing anything below.

neon-codexbar will discover the binary on `PATH`, then fall back to common
locations (`~/.local/bin/codexbar`, `~/bin/codexbar`,
`/opt/neon-codexbar/bin/codexbar`). Override explicitly with the
`NEON_CODEXBAR_CODEXBAR_PATH` env var or by setting `codexbar_path` in
`~/.config/neon-codexbar/config.json`.

## Enabling providers in CodexBar

Edit `~/.codexbar/config.json`. **Important:** the file must list every
provider id from `codexbar config dump --format json`, not just the ones you
want enabled. Partial files fail with `"data is missing"`.

Easiest workflow:

```bash
codexbar config dump --format json | jq . > ~/.codexbar/config.json
```

…then flip `enabled: true` for each provider you want active. Re-validate:

```bash
codexbar config validate --format json --pretty
codexbar config dump --format json | jq '.providers[] | select(.enabled==true)'
```

## Linux source policy

neon-codexbar refuses `--source auto` on Linux (it picks unreliable defaults).
The adapter pins the source per provider:

| Provider | Source | Notes |
|---|---|---|
| `codex` | `cli` | uses `~/.codex` auth |
| `claude` | `cli` | uses `~/.claude` auth; **slow (~15s/call)** |
| `zai` | `api` | requires `Z_AI_API_KEY` env var |
| `openrouter` | `api` | requires `OPENROUTER_API_KEY` env var |

Unknown providers are skipped with a diagnostic. To add a provider, extend
`src/neon_codexbar/adapter/source_policy.py` and capture a fixture from
`codexbar usage --provider <id> --source <type> --format json`.

## Provider-specific notes

### codex

```bash
codexbar usage --provider codex --source cli --format json --pretty
```

Auth is whatever `codex` CLI is logged in as. Returns 2 quota windows (5h /
1wk) and a credits meter. Reset descriptions use U+202F NARROW NO-BREAK SPACE
between time and AM/PM — render as a regular space.

### claude

```bash
codexbar usage --provider claude --source cli --format json --pretty
```

Auth is whatever `claude` CLI is logged in as (`~/.claude/`). Returns 2 quota
windows (5h / 1wk).

- Slow: a single fetch hits claude.ai and takes ~15 seconds.
- The `primary` window is sometimes returned with only `usedPercent` and
  `windowMinutes` — no `resetsAt`, no `resetDescription`. Display layer must
  tolerate.
- Identity is bare (only `providerID`). No email surfaced.

### zai

```bash
export Z_AI_API_KEY=...
codexbar usage --provider zai --source api --format json --pretty
```

Returns 3 quota windows (1wk / 1min / 5h).

- The `secondary` (1-minute) window omits `windowMinutes` entirely. Read the
  label from `resetDescription` instead.
- `usedPercent` may be float-noisy (e.g. `1.0999999999999999`). Round in the
  UI.

### openrouter

```bash
export OPENROUTER_API_KEY=...
codexbar usage --provider openrouter --source api --format json --pretty
```

Returns no quota windows; instead emits an `openRouterUsage` block. neon-codexbar
normalizes it into two credit meters:

- **OpenRouter Balance** — account-wide credits remaining vs. purchased
- **OpenRouter Key Quota** — per-key spend (only meaningful if a key limit is set)

`rateLimit.requests: -1` indicates unlimited. `loginMethod` carries a human
balance string (`"Balance: $3.49"`) which the widget can display verbatim.

## Verifying neon-codexbar sees your config

```bash
neon-codexbar discover --json
neon-codexbar fetch --json
neon-codexbar diagnose --json
```

`discover` lists known providers and which source neon-codexbar will use.
`fetch` runs each enabled provider and emits normalized cards. `diagnose`
captures a redacted bundle suitable for sharing in bug reports.

If `diagnose` ever shows what looks like a real key, file a bug —
`diagnostics.py` is supposed to redact those.

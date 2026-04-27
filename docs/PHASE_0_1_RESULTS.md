# Phase 0-1 Results

Date: 2026-04-26
Scope: Phase 0 validation + Phase 1 Python adapter proof.

## Status

Phase 0 live validation **complete** for all four target providers on the Debian
LXC dev host (CodexBar CLI installed at `/home/claude/.local/bin/codexbar`,
resolves to `CodexBarCLI`).

| Provider | Source | Result | Shape captured |
|---|---|---|---|
| codex | cli | 2 quota windows + Credits meter | yes |
| claude | cli | 2 quota windows | yes |
| zai | api | 3 quota windows | yes |
| openrouter | api | Balance + Key Quota meters | yes |

## CodexBar CLI command shape (verified)

The actual invocation is:

```bash
codexbar usage --provider <id> --source <type> --format json
```

The `usage` subcommand is implicit when omitted, so

```bash
codexbar --provider <id> --source <type> --format json
```

also works. Our adapter uses the implicit form and that is fine — both routes
are stable in this CodexBar build.

`codexbar --version` prints just `CodexBar` (no version string in this binary).
The per-provider payload exposes `version` (e.g. `"0.123.0"` for codex,
`"2.1.119"` for claude — that is the upstream CLI version, not CodexBar's).

## CodexBar config schema gotcha

`~/.codexbar/config.json` requires the **full** provider list. Writing only the
subset of providers you want enabled fails with:

```
"Failed to decode CodexBar config: The operation could not be completed. The data is missing."
```

Working minimum:

```json
{
  "version": 1,
  "providers": [
    {"id": "codex", "enabled": true},
    {"id": "claude", "enabled": true},
    ... // every provider id from `codexbar config dump --format json`
    {"id": "openrouter", "enabled": true}
  ]
}
```

Discovery via `codexbar config dump --format json` always emits the canonical
list, so it is safe to clone-and-edit that output.

## Per-provider payload findings

### codex (cli)
- Returns `version`, `usage.identity` with `accountEmail`/`loginMethod`/`providerID`,
  `usage.primary` and `usage.secondary` quota windows, plus a `credits` block.
- Reset descriptions use U+202F NARROW NO-BREAK SPACE (`"10:34 PM"`).
  Display layer should treat as a regular space.

### claude (cli)
- **Slow.** ~15s per fetch (live HTTP roundtrip to claude.ai). The original 10s
  per-call timeout was too tight; bumped to 30s default in `runner.py`.
- Live `usage.primary` lacks `resetsAt` and `resetDescription` — only
  `usedPercent` and `windowMinutes`. Normalizer must tolerate.
- `usage.identity` only contains `providerID` (no email).
- `source` field echoes back as `"claude"` (not `"cli"`).

### zai (api)
- Three quota windows: 1-week / 1-minute / 5-hours, in `primary`/`secondary`/`tertiary`.
- **`secondary` omits `windowMinutes`** entirely — only `resetDescription:
  "1 minute window"`. Pinned by `test_normalizer_handles_zai_secondary_without_window_minutes`.
- `usedPercent` may be float-noisy (`1.0999999999999999`).
- Identity is bare (only `providerID`).
- Auth via `Z_AI_API_KEY` env var works; no `~/.codexbar/config.json` entry needed beyond enabling the provider.

### openrouter (api)
- No quota windows — `primary`/`secondary`/`tertiary` are all null.
- `usage.openRouterUsage` block: `balance`, `totalCredits`, `totalUsage`,
  `keyUsage`, `rateLimit`, `usedPercent`.
- Normalizer emits two credit meters: "OpenRouter Balance" (account-wide) and
  "OpenRouter Key Quota" (per-key usage). Real `keyUsage` is populated; old
  fixture had it null.
- `rateLimit.requests: -1` indicates unlimited.
- `loginMethod` carries the human-readable balance string (`"Balance: $3.49"`).
- Auth via `OPENROUTER_API_KEY` env var.

## Phase 1 implementation

Implemented:

- Python package skeleton under `src/neon_codexbar/`
- Source-checkout shim for `python3 -m neon_codexbar` before editable install
- CodexBar adapter modules: `runner.py`, `discovery.py`, `source_policy.py`, `normalizer.py`
- CLI commands: `--version`, `discover --json`, `fetch --json`, `diagnose --json`
- UI-only config model; no provider secrets stored by neon-codexbar
- Redacted diagnostics
- 18 pytest unit tests (source policy, discovery, normalization, diagnostics, CLI fixture fetch)
- Per-call subprocess timeout: 30s (was 10s; insufficient for claude)

Source policy (Linux):

| Provider | Source |
|---|---|
| `codex` | `cli` |
| `claude` | `cli` |
| `zai` | `api` |
| `openrouter` | `api` |

Unknown providers are skipped with diagnostics. `--source auto` is never used.

## Verification

```bash
python3 -m ruff check .
python3 -m pytest
```

Both clean. End-to-end live fetch (`python3 -m neon_codexbar fetch --json`)
returns valid `ProviderCard` JSON for all four providers.

## Fixtures

`tests/fixtures/codexbar/*.json` are now sanitized live captures, not
hand-built structural mocks. Sanitization applied:

- codex `accountEmail` → `user@example.com`
- no API keys, tokens, cookies, auth headers
- error fixture unchanged shape, generic message

## Next phase

Phase 2 prerequisites are met. See `plans/next-steps-user-config.md` for the
ordered next steps.

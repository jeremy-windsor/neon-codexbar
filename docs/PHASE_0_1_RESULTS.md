# Phase 0-1 Results

Date: 2026-04-26  
Scope: Phase 0 validation + Phase 1 Python adapter proof only.

## Phase 0 command findings

`codexbar` is not installed on this host. PATH/common-path checks failed for:

- `~/.local/bin/codexbar`
- `~/bin/codexbar`
- `/usr/local/bin/codexbar`
- `/opt/neon-codexbar/bin/codexbar`

Exact commands tested:

| Command | Result |
|---|---|
| `codexbar --version` | `bash: codexbar: command not found`, exit `127` |
| `codexbar config dump --pretty` | `bash: codexbar: command not found`, exit `127` |
| `codexbar config dump --format json` | `bash: codexbar: command not found`, exit `127` |
| `codexbar --provider codex --source cli --format json --pretty` | `bash: codexbar: command not found`, exit `127` |
| `codexbar --provider claude --source cli --format json --pretty` | `bash: codexbar: command not found`, exit `127` |
| `codexbar --provider zai --source api --format json --pretty` | `bash: codexbar: command not found`, exit `127` |
| `codexbar --provider openrouter --source api --format json --pretty` | `bash: codexbar: command not found`, exit `127` |

Blocker: live provider command validation cannot proceed until CodexBar CLI is installed/configured on the target machine.

## Fixture sources

Sanitized structural fixtures were added under `tests/fixtures/codexbar/` from upstream CodexBar schema/test inspection, not from live secrets:

- `config_dump.json`
- `codex_cli_success.json`
- `claude_cli_success.json`
- `zai_api_success.json`
- `openrouter_api_success.json`
- `representative_error.json`

Sanitization applied:

- email identity uses `user@example.com`
- no org IDs/account IDs
- no API keys/tokens/cookies/auth headers
- error fixture uses `[REDACTED]`

## Phase 1 implementation

Implemented:

- Python package skeleton under `src/neon_codexbar/`
- source-checkout shim for `python3 -m neon_codexbar` before editable install
- CodexBar adapter modules:
  - `runner.py`
  - `discovery.py`
  - `source_policy.py`
  - `normalizer.py`
- CLI commands:
  - `neon-codexbar --version`
  - `neon-codexbar discover --json`
  - `neon-codexbar fetch --json`
  - `neon-codexbar diagnose --json`
- UI-only config model; no provider secrets stored by neon-codexbar
- redacted diagnostics
- pytest unit coverage for source policy, discovery, normalization, diagnostics, and CLI fixture fetch

Source policy implemented:

| Provider | Source |
|---|---|
| `codex` | `cli` |
| `claude` | `cli` |
| `zai` | `api` |
| `openrouter` | `api` |

Unknown providers are skipped with diagnostics. `--source auto` is never used for Linux provider fetches.

## Verification

This sandbox has `python3` but no `python` executable.

Commands run:

```bash
python3 -m ruff check .
python3 -m pytest
```

Results:

```text
All checks passed!
13 passed in 0.32s
```

CLI smoke checks:

```bash
python3 -m neon_codexbar --version
python3 -m neon_codexbar discover --json
python3 -m neon_codexbar fetch --json --fixture tests/fixtures/codexbar/openrouter_api_success.json
python3 -m neon_codexbar diagnose --json
```

Results:

- `--version` prints `neon-codexbar 0.1.0 (codexbar unavailable)`.
- `discover --json` returns a structured `ok: false` error because CodexBar is unavailable.
- fixture-backed `fetch --json` emits a normalized OpenRouter card with credit meter and no fake quota windows.
- `diagnose --json` returns a redacted diagnostic bundle with `ok: false` because CodexBar is unavailable.

## Blockers

- CodexBar CLI unavailable on this host, so live command behavior/auth cannot be validated.
- Live Codex, Claude, z.ai, and OpenRouter payloads could not be captured.
- `python` is absent on PATH; use `python3` here or install/provide a `python` shim in the target dev environment.

## Next recommended phase

Install or provide CodexBar CLI on the KDE target machine, rerun Phase 0 command validation, and replace/augment structural fixtures with sanitized live fixtures where safe. After live CLI validation passes, proceed to daemon/snapshot work before QML/Plasma rendering.

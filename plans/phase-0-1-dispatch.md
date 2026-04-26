# neon-codexbar Phase 0–1 Dispatch

Owner/PM: Will
Builder: Forge
Model target: GPT-5.5, xhigh thinking
Repo: `jeremy-windsor/neon-codexbar`

## Read first

Before coding, read:

1. `plans/gpt-neon-codexbar-plan.md`
2. `plans/claude-neon-codexbar-plan.md`

Use `plans/gpt-neon-codexbar-plan.md` as the governing architecture when the two plans differ.

Core rule:

> CodexBar owns providers. neon-codexbar owns KDE UX.

Do not build provider auth/parsing logic in neon-codexbar. Do not create a local provider secret store.

## Scope for this run

Implement **Phase 0 + Phase 1 only**.

Do not implement yet:

- Plasma/QML widget
- daemon/systemd service
- installer
- systray app
- KWallet/libsecret
- custom provider plugins
- provider auth/parsing outside CodexBar

If tempted, stop. The raccoon brain is lying.

## Phase 0 — validate CodexBar CLI commands

Goal: prove the exact CodexBar command surface on this machine and save sanitized fixtures.

Test these command forms, if `codexbar` exists and auth is available:

```bash
codexbar --version
codexbar config dump --pretty
codexbar config dump --format json
codexbar --provider codex --source cli --format json --pretty
codexbar --provider claude --source cli --format json --pretty
codexbar --provider zai --source api --format json --pretty
codexbar --provider openrouter --source api --format json --pretty
```

If a command fails due to missing auth/config on this host, document the failure and create a fixture from known repo/test shape only if safe. Do not invent provider semantics.

### Fixture rules

Save fixtures under:

```text
tests/fixtures/codexbar/
```

Required fixture types:

- config dump fixture
- Codex CLI success fixture, if available
- Claude CLI success fixture, if available
- z.ai API success fixture, if available
- OpenRouter API success fixture, if available
- representative error fixture

Sanitize fixtures:

- remove emails or replace with `user@example.com`
- remove org IDs/account IDs if sensitive
- remove API keys/tokens/cookies/auth headers
- preserve structural fields needed by parser tests

## Phase 1 — Python adapter proof

Build the minimal Python package spine.

Required files/modules:

```text
pyproject.toml
src/neon_codexbar/__init__.py
src/neon_codexbar/__main__.py
src/neon_codexbar/cli.py
src/neon_codexbar/models.py
src/neon_codexbar/config.py
src/neon_codexbar/diagnostics.py
src/neon_codexbar/adapter/__init__.py
src/neon_codexbar/adapter/runner.py
src/neon_codexbar/adapter/discovery.py
src/neon_codexbar/adapter/source_policy.py
src/neon_codexbar/adapter/normalizer.py
tests/unit/
tests/fixtures/
```

Implement CLI commands:

```bash
neon-codexbar --version
neon-codexbar discover --json
neon-codexbar fetch --json
neon-codexbar diagnose --json
```

It is fine if install/runtime/widget commands are stubs that return a clear “not implemented in Phase 1” message.

## Required behavior

### Source policy

Initial Linux policy:

| Provider | Source |
|---|---|
| codex | `cli` |
| claude | `cli` |
| zai | `api` |
| openrouter | `api` |

Unknown providers:

- skip by default
- include diagnostic note
- do not guess `auto`

### Runner

- locate `codexbar` from PATH or explicit config/env override
- run exactly one provider/source command at a time in Phase 1
- timeout default: 10 seconds
- capture stdout/stderr/exit code
- return structured result
- redact secrets in diagnostics

### Discovery

- parse `codexbar config dump` output
- expose provider ids and enabled state
- tolerate command/flag mismatch by trying documented known forms in order

### Normalizer

Normalize CodexBar JSON into generic cards:

- provider id
- display name
- source
- version
- identity dictionary
- quota windows list
- credit meters list
- model usage list
- error/setup hint
- last attempt/success fields where available

Do not assume:

- `primary = Session`
- `secondary = Weekly`
- only two windows exist
- every provider has quota windows

OpenRouter must normalize into credit/balance meters when `primary`, `secondary`, and `tertiary` are null.

z.ai must preserve primary/secondary/tertiary as generic quota windows.

## Tests required

Use pytest.

Minimum tests:

- source policy returns expected sources for codex/claude/zai/openrouter
- unknown provider is skipped/diagnostic, not guessed
- discovery parses config fixture
- normalizer handles Codex/Claude primary+secondary windows
- normalizer handles z.ai primary+secondary+tertiary windows
- normalizer handles OpenRouter credit/balance usage
- diagnostics redacts token-like strings
- CLI `--version` works
- CLI `fetch --json` can run against fixtures or mocked runner

## Acceptance criteria

This phase is complete only when:

1. `python -m pytest` passes.
2. `python -m neon_codexbar --version` works.
3. `python -m neon_codexbar discover --json` works or returns a clear structured error if `codexbar` is unavailable.
4. `python -m neon_codexbar fetch --json` emits normalized provider card JSON for available providers or fixtures/mocks.
5. No provider secrets are stored in app config.
6. No provider-specific auth/parsing is implemented outside CodexBar output normalization.
7. No QML/daemon/installer work is included.
8. Git diff is focused and reviewable.

## Stop conditions

Stop and report if:

- CodexBar CLI is unavailable and cannot be installed safely.
- CodexBar CLI flags differ materially from the plan.
- Provider output shape is incompatible with the proposed normalizer.
- Tests require real secrets to pass.
- Scope pressure pulls toward QML/daemon/installer.

## Deliverables

- Code changes implementing Phase 0–1.
- Sanitized fixtures.
- Passing tests.
- Short implementation note in `docs/PHASE_0_1_RESULTS.md` summarizing:
  - exact CodexBar commands tested
  - what passed/failed
  - fixture sources
  - known blockers
  - next recommended phase

## PM expectation

Do not push without tests passing unless blocked. If blocked, commit only if the partial state is clean and useful, then document the blocker clearly.

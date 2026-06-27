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
| `claude` | `oauth` | uses Claude Code OAuth auth; avoids Claude CLI probe sessions |
| `zai` | `api` | requires `Z_AI_API_KEY` env var |
| `openrouter` | `api` | requires `OPENROUTER_API_KEY` env var |

Unknown providers are skipped with a diagnostic. To add a provider, extend
`src/neon_codexbar/adapter/source_policy.py` and capture a fixture from
`codexbar usage --provider <id> --source <type> --format json`.

CodexBar `v0.25.1` was the latest release checked for this document. The Linux
standalone CLI in that release fixes `codexbar --version` by packaging its
`VERSION` file.

## CodexBar v0.25+ provider inventory

CodexBar now exposes these provider ids in `config dump`:

```text
codex, openai, claude, cursor, opencode, opencodego, alibaba, factory,
gemini, antigravity, copilot, zai, minimax, manus, kimi, kilo, kiro,
vertexai, augment, jetbrains, kimik2, amp, ollama, synthetic, warp,
openrouter, perplexity, mimo, doubao, abacus, mistral, deepseek, codebuff,
crof, venice, commandcode, stepfun
```

`v0.25` added or expanded support for Manus, MiMo, Qwen/Doubao, Command Code,
StepFun, Crof, Venice, OpenAI API balance, MiniMax multi-service quota cards,
Antigravity OAuth fetching, and provider balance text for OpenRouter/Mistral/Kimi
K2.

Do not turn those on in neon-codexbar just because they appear in the config
dump. Many upstream providers use browser cookies or macOS web support. On
Linux, those often return runtime errors such as "selected source requires web
support and is only supported on macOS." Add a provider to the source policy
only after this works on Linux:

```bash
codexbar usage --provider <id> --source <source> --format json --pretty
```

Then save a sanitized fixture under `tests/fixtures/codexbar/` and add a
normalizer/source-policy test.

New CodexBar CLI features worth future neon-codexbar work:

- `codexbar cost --format json` for local Codex/Claude token-cost history.
- `codexbar usage --status --format json` for provider service-status payloads.
- `--json-only` for cleaner stdout when CodexBar logs get noisy.
- Usage pace and quota warning metadata for better tray warnings.

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
codexbar usage --provider claude --source oauth --format json --pretty
```

Auth is Claude Code OAuth state. Returns the standard quota windows plus any
Claude-specific extra windows CodexBar exposes.

- Fast on Linux: live validation on Jeremy's laptop returned in about 2 seconds.
- Avoids the old CLI probe path that created empty Claude Code recents.
- The old `cli` source still works, but it launches the Claude CLI probe and is
  intentionally not used by neon-codexbar.

### zai

```bash
export Z_AI_API_KEY=...
codexbar usage --provider zai --source api --format json --pretty
```

Returns quota metadata for the documented Coding Plan limits.

- z.ai may report a `secondary` row as `1 minute window` while omitting
  `windowMinutes`. That row does not match the documented 5-hour, weekly, or
  MCP monthly limits and is ignored by the normalizer.
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

## Headless auth for the systemd `--user` daemon

`packaging/neon-codexbar.service` ships **secret-free**. systemd `--user`
services do not reliably inherit your interactive shell environment, so
`Z_AI_API_KEY` and `OPENROUTER_API_KEY` (and any other env-based provider
auth) need to be made available to the unit explicitly. Pick one:

**Option A — import once per login session.** Quickest, no on-disk secret.

```bash
export Z_AI_API_KEY=...
export OPENROUTER_API_KEY=...
systemctl --user import-environment Z_AI_API_KEY OPENROUTER_API_KEY
systemctl --user restart neon-codexbar.service
```

The vars are only available to user services started after the import. They
do not survive a logout — re-import on next login (or wire it into your shell
rc + a oneshot service).

**Option B — user-owned drop-in.** Persistent across logouts. Keep mode `0600`.

```bash
mkdir -p ~/.config/systemd/user/neon-codexbar.service.d
cat > ~/.config/systemd/user/neon-codexbar.service.d/auth.conf <<'EOF'
[Service]
Environment=Z_AI_API_KEY=...
Environment=OPENROUTER_API_KEY=...
EOF
chmod 600 ~/.config/systemd/user/neon-codexbar.service.d/auth.conf
systemctl --user daemon-reload
systemctl --user restart neon-codexbar.service
```

**Option C — `EnvironmentFile=`.** If you already have a sourced env file:

```ini
[Service]
EnvironmentFile=%h/.config/neon-codexbar/auth.env
```

In all cases the secret stays user-owned and outside neon-codexbar's own
config. Do not paste keys into `~/.config/neon-codexbar/config.json` — the
loader will refuse the file.

`codex` and `claude` providers do not need any of this — they read
`~/.codex/` and `~/.claude/` respectively, which the daemon inherits via
`%h`.

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

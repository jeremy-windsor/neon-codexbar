# Daemon ↔ Widget Contract

This document is the single source of truth for the snapshot file the
`neon-codexbar-daemon` writes and the Plasma widget reads. If something here
disagrees with the code, the code is wrong; please open an issue.

## File location

| | |
|---|---|
| Default path | `~/.cache/neon-codexbar/snapshot.json` |
| Override env | `NEON_CODEXBAR_SNAPSHOT_PATH` (absolute or `~`-relative) |
| Override CLI | `neon-codexbar-daemon --snapshot-path /path/to/snapshot.json` |
| Mode | `0600` (user-only) |
| Ownership | The daemon writes; the widget reads. The widget MUST NOT write or unlink. |

## Atomic write semantics

The daemon writes to `<path>.tmp`, fsyncs, then `rename(2)`s into place. On
the same filesystem that is atomic. The widget must therefore be safe to
re-read on any change notification: a partial file is never visible.

## Schema

```json
{
  "schema_version": 1,
  "generated_at": "2026-04-26T20:00:00Z",
  "ok": true,
  "cards": [ ... ProviderCard ... ],
  "diagnostics": [ "human-readable lines" ],
  "codexbar": {
    "available": true,
    "path": "/home/user/.local/bin/codexbar",
    "version": "CodexBar"
  }
}
```

### Root fields

| Field | Type | Meaning |
|---|---|---|
| `schema_version` | int | Currently `1`. Bumped only for breaking changes. New fields can be added without bumping. |
| `generated_at` | ISO-8601 string with `Z` | UTC time the daemon finished assembling this snapshot. |
| `ok` | bool | **Global** daemon/CodexBar health only. `true` iff the daemon could locate the CodexBar binary. Per-provider failures do **not** flip this false. |
| `cards` | array of ProviderCard | One entry per provider the daemon attempted this tick. Sorted by `provider_id`. |
| `diagnostics` | array of strings | Human-readable lines explaining anything notable: source-policy skips, parser errors, worker exceptions. Already redacted. |
| `codexbar` | object | CodexBar binary metadata (see below). |

### `codexbar` object

| Field | Type | Meaning |
|---|---|---|
| `available` | bool | `true` iff the daemon located the CodexBar binary at startup. |
| `path` | string or null | Resolved binary path, or `null` if missing. |
| `version` | string or null | Output of `codexbar --version`, trimmed. May be `null` if the binary exists but `--version` failed. |

Cached after first successful probe; restart the daemon to pick up a CodexBar
upgrade.

### ProviderCard

| Field | Type | Meaning |
|---|---|---|
| `provider_id` | string | CodexBar provider id (`codex`, `claude`, `zai`, `openrouter`, …). |
| `display_name` | string | Human label (e.g. "Z.ai"). Currently from a hardcoded table; user overrides will land in Phase 5. |
| `source` | string | Whatever CodexBar echoed (`cli`, `api`, `codex-cli`, `claude`, …). |
| `version` | string or null | Provider's reported version (e.g. claude CLI `2.1.119`). |
| `identity` | object | Whatever CodexBar returned in `usage.identity`. May be `{providerID: "..."}` only. |
| `plan` | string or null | Subscription plan if surfaced; `null` for credit-style providers. |
| `login_method` | string or null | Auth descriptor from CodexBar (e.g. `"max"`, `"Balance: $3.49"`). |
| `quota_windows` | array of QuotaWindow | 0..N rate/quota windows in CodexBar's order (primary → secondary → tertiary). |
| `credit_meters` | array of CreditMeter | 0..N credit/balance meters. |
| `model_usage` | array | Per-model breakdown if the provider exposes it; usually empty. |
| `error_message` | string or null | Human-readable provider-specific failure. **Per-provider, NOT global.** |
| `setup_hint` | string or null | If `error_message` is set, a CodexBar-side action the user can take. |
| `is_stale` | bool | `true` when this card's last successful fetch is older than `2 × refresh_interval`. See "Staleness" below. |
| `last_success` | ISO-8601 string or null | When this provider last returned valid data. |
| `last_attempt` | ISO-8601 string | When the daemon most recently tried to fetch this provider. |

### QuotaWindow

| Field | Type | Meaning |
|---|---|---|
| `id` | string | `"primary"` / `"secondary"` / `"tertiary"`. |
| `used_percent` | float or null | 0–100. May be float-noisy (e.g. `1.0999999999999999`); round in the UI. |
| `resets_at` | ISO-8601 string or null | When the window resets. May be missing on some providers. |
| `reset_description` | string or null | CodexBar's human label (e.g. `"1 minute window"`, `"Resets7am(America/Phoenix)"`). |
| `window_label` | string | `"Window 1"` / `"Window 2"` / `"Window 3"` for ordering. |
| `window_minutes` | int or null | Window length. **z.ai's secondary window omits this** — fall back to `reset_description`. |
| `raw` | object | Original window object as returned by CodexBar. |

### CreditMeter

| Field | Type | Meaning |
|---|---|---|
| `label` | string | Human label (e.g. `"OpenRouter Balance"`, `"Credits"`). |
| `balance` | float or null | Remaining (e.g. unspent dollars). |
| `used` | float or null | Amount consumed. |
| `total` | float or null | Cap or purchased amount. |
| `used_percent` | float or null | 0–100. |
| `currency` | string or null | E.g. `"USD"`. |
| `raw` | object | Original `openRouterUsage` / `credits` block. |

## Semantic rules the widget must respect

### `ok` is GLOBAL, not per-provider

A snapshot with `ok: true` and one `cards[i].error_message != null` means
**CodexBar is fine, one provider is broken**. Render that provider with an
error state; do not show a banner saying "everything is broken."

A snapshot with `ok: false` means **the daemon couldn't even find CodexBar**.
Show the install/setup hint; provider cards will be empty.

### Staleness has two cases

1. **In-flight staleness** — `cards[i].is_stale: true`. The daemon is alive
   and writing snapshots, but this provider hasn't returned successfully in
   a while (older than `2 × refresh_interval`). Dim that card.
2. **Daemon-dead staleness** — the daemon is gone, no new snapshots are
   being written. The widget detects this by comparing `generated_at` (or
   the file's mtime) to wall clock. If the snapshot is older than
   `~2 × refresh_interval`, treat the **whole snapshot** as stale and dim
   everything. The default `refresh_interval` is 300s, so a 600s-old
   snapshot is suspicious; older than 1800s is definitely dead.

The widget owns daemon-dead staleness. The daemon literally cannot write
"I'm dead" into the file it wrote before dying.

### `cards[]` is sorted by `provider_id`

Stable order across ticks. Don't re-sort.

### `quota_windows[]` ordering is meaningful

Order is preserved from CodexBar (primary → secondary → tertiary). Display
in that order.

### `diagnostics[]` is already redacted

Safe to display verbatim. Do not paste user-supplied or environment values
back in.

## Manual refresh triggers

Two equivalent ways for the widget (or any external script) to ask the
daemon to refresh sooner than `refresh_interval`:

| Method | How |
|---|---|
| Sentinel file | `touch ~/.cache/neon-codexbar/refresh.touch` (relative to the snapshot directory). Daemon consumes (deletes) it, then runs a tick. |
| Signal | `kill -USR1 $(pgrep -u $UID -x neon-codexbar-d)` |

Both interrupt the inter-tick sleep within ~1 second.

## What the daemon owns vs the widget owns

| | Daemon | Widget |
|---|---|---|
| Spawning subprocesses | yes | **no, ever** |
| Reading `~/.codexbar/config.json` | yes (via `codexbar config dump`) | no |
| Writing the snapshot | yes | no |
| Reading the snapshot | no | yes |
| Computing in-flight staleness | yes (`cards[i].is_stale`) | reads it |
| Computing daemon-dead staleness | no | yes (mtime/`generated_at` vs now) |
| Owning provider auth | no (CodexBar does) | no |
| Threshold colors / UI hints | no | yes |
| Triggering manual refresh | no | yes (touch sentinel or SIGUSR1) |

## Forward compatibility

- New top-level fields will be added without bumping `schema_version`. Widget should ignore unknown root keys.
- New per-card fields will be added without bumping `schema_version`. Widget should ignore unknown card keys.
- Renames or removals will bump `schema_version` to `2` and the daemon will
  refuse to write a snapshot the configured widget can't read.

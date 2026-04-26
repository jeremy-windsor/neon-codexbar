# neon-codexbar Plan — GPT Review

Date: 2026-04-26
Author: Will / GPT review
Repo: `jeremy-windsor/neon-codexbar`

## Executive read

Build `neon-codexbar` as a KDE Neon / Plasma frontend for upstream `codexbar` CLI.

Do **not** rebuild provider auth, quota endpoints, cookies, API parsing, or provider-specific logic inside the KDE app. That work belongs in upstream CodexBar or a maintained CodexBar fork. `neon-codexbar` should be the Linux/KDE shell: install, configure, run, render, diagnose.

The clean split:

```text
CodexBar / CodexBarCore
  owns providers, config, auth, fetch strategies, parsing, CLI JSON

neon-codexbar
  owns KDE widget/systray UX, install flow, source policy, rendering, diagnostics
```

## What we know already

Tested on KDE Neon / Jeremy's laptop:

- `codexbar --provider codex --source cli --format json --pretty` works.
- `codexbar --provider claude --source cli --format json --pretty` works.
- z.ai works through CodexBar CLI with API key/env and `--source api`.
- OpenRouter works through CodexBar CLI with API source and returns balance/credit usage.
- `jjlinares/codexbar-kde-widget` already proves a pure QML Plasma widget can call CodexBar CLI and render providers.
- `radoslavchobanov/PlasmaCodexBar` proves another KDE widget direction works, but it reimplements provider logic in Python, which is the wrong long-term shape.

## Recommended product shape

`neon-codexbar` should feel like its own app to the user while using CodexBar internally as the provider engine.

User-facing:

- KDE/Plasma widget and/or systray app named `neon-codexbar`
- simple setup flow
- provider cards
- quota windows
- balances/credits
- clear setup errors
- no need for users to understand CodexBar unless troubleshooting or reading docs

Implementation reality:

- bundle or install upstream `codexbar` CLI
- keep config/secrets in CodexBar's supported locations
- call CodexBar CLI for all provider data
- document CodexBar license and attribution clearly

## Transparency and licensing

It is fine for the UX to present as `neon-codexbar`, but it must not pretend provider functionality is original.

Required:

- include CodexBar license/notice in repo and app docs
- document that provider data is powered by CodexBar CLI
- link upstream: `https://github.com/steipete/CodexBar`
- document which parts are ours vs upstream

Suggested wording:

> neon-codexbar is a KDE/Plasma frontend powered by the CodexBar CLI provider engine.

## Architecture

### Components

1. **Installer/bootstrap**
   - installs/checks `codexbar` CLI
   - installs Plasma widget
   - optionally installs systray/autostart component later
   - verifies CLI works

2. **CodexBar adapter layer**
   - single abstraction around CLI calls
   - handles command construction
   - enforces Linux-safe source policy
   - parses JSON
   - normalizes data into UI blocks
   - captures diagnostics without secrets

3. **Provider source policy**
   - avoids bad Linux defaults like blind `auto`
   - maps providers to working source modes

   Initial policy:

   | Provider | Preferred Linux source | Status |
   |---|---|---|
   | codex | `cli` | tested working |
   | claude | `cli` | tested working |
   | zai | `api` | tested working |
   | openrouter | `api` | tested working |
   | gemini | `api` / provider default | needs Gemini auth test |
   | copilot | `api` | needs token/device flow test |
   | kilo | `api` or CLI fallback | needs Kilo auth test |
   | opencode | likely web/manual-cookie limited | needs Linux test |

4. **UI renderer**
   - renders generic data blocks, not hardcoded provider assumptions
   - supports quota windows: primary / secondary / tertiary
   - supports credit/balance meters like OpenRouter
   - supports provider errors/setup hints
   - supports stale/cache state

5. **Settings/diagnostics**
   - refresh interval
   - warning/critical thresholds
   - CLI path
   - provider display mode: enabled-only / all configured / debug all
   - validate CodexBar config
   - copy diagnostics with secrets redacted

## Data model strategy

Do not hardcode `primary = Session` and `secondary = Weekly`.

CodexBar providers do not all share the same meaning:

- Codex: primary is session, secondary is weekly
- Claude: primary is session, secondary is weekly
- z.ai: primary/secondary/tertiary can represent different quota windows
- OpenRouter: no primary/secondary windows; exposes balance/usage credits

Normalize into display blocks:

```text
ProviderCard
  identity/plan/source/version
  quota windows[]
  credit meters[]
  model usage[]
  errors[]
  status
```

This keeps the UI future-proof when CodexBar adds providers or changes provider-specific fields.

## Build vs fork decision

### Use existing widget designs as references

Use these repos as reference material:

- `jjlinares/codexbar-kde-widget`
  - best architecture reference: pure QML + CodexBar CLI
  - useful install flow, QML structure, provider cards/icons

- `radoslavchobanov/PlasmaCodexBar`
  - good KDE Neon proof and UI reference
  - wrong provider strategy because it reimplements providers in Python

### Build our own repo

Since `neon-codexbar` is a new app/repo, use the above as patterns, not necessarily as direct upstream forks.

Best path:

1. start with a minimal pure QML Plasma widget scaffold
2. borrow/recreate useful structure from `jjlinares/codexbar-kde-widget`
3. implement a clean CodexBar adapter layer immediately
4. avoid copying stale provider assumptions

## Provider extension strategy

When a provider is missing or broken:

1. Add/fix provider in CodexBar using `docs/provider.md`:
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
   - icon/name/dashboard metadata
   - source policy
   - display mapping if a new output shape appears

Rule: provider auth/parsing should not live in `neon-codexbar` except as a short-lived experiment.

## Configuration and secrets

Keys/config stay with CodexBar.

Preferred sources:

- `~/.codexbar/config.json`
- provider CLI auth files (`~/.codex`, Claude CLI auth, etc.)
- environment variables supported by CodexBar, e.g.:
  - `Z_AI_API_KEY`
  - `OPENROUTER_API_KEY`

`neon-codexbar` should not store provider secrets.

If KDE session environment becomes painful, consider a local env-file loader later, but treat that as a convenience wrapper around CodexBar-supported environment variables, not a new secret store.

## MVP scope

MVP should include:

- Plasma 6 widget
- CodexBar CLI install/check
- provider discovery from `codexbar config dump`
- Linux-safe source policy
- provider cards for tested providers
- generic quota window rendering
- OpenRouter-style balance/credit rendering
- errors/setup hints for enabled providers
- refresh/backoff
- basic settings
- license/attribution docs

MVP should not include:

- rewriting provider fetchers
- storing API keys in the widget
- browser cookie import
- KWallet/libsecret integration
- full settings UI for every provider
- Flatpak/AppImage packaging before the widget behavior is proven

## Pros of this approach

- Fast path to working KDE app.
- Provider logic stays where it belongs.
- Upstream CodexBar improvements flow into `neon-codexbar`.
- Lower maintenance burden.
- Easier to add providers correctly.
- Cleaner licensing/attribution story.

## Cons / risks

- Depends on CodexBar CLI JSON stability.
- Linux source behavior is uneven; `auto` often chooses macOS/web paths.
- Web-cookie providers may remain limited until CodexBar supports Linux-safe/manual flows.
- QML can get ugly if business logic leaks into UI files.
- If we need provider changes upstream quickly, we may need to maintain a CodexBar fork or contribute PRs.

## Recommended implementation phases

### Phase 1 — scaffold and proof

- Create minimal Plasma 6 widget.
- Add installer/check for `codexbar` CLI.
- Call known-good providers:
  - Codex CLI
  - Claude CLI
  - z.ai API
  - OpenRouter API

Acceptance: widget renders all four from real CLI output.

### Phase 2 — adapter cleanup

- Create clean adapter module.
- Add Linux source policy table.
- Add `codexbar config dump` provider discovery.
- Add redacted diagnostics.

Acceptance: no provider command construction scattered through QML cards.

### Phase 3 — generic renderer

- Render quota windows dynamically.
- Render credit/balance meters.
- Render errors/setup hints.
- Stop hardcoding Session/Weekly except when labels are actually known.

Acceptance: z.ai tertiary window and OpenRouter balance both display correctly.

### Phase 4 — UX polish

- Better icons/metadata.
- Settings page.
- Refresh/backoff/stale state.
- Threshold colors/notifications.

### Phase 5 — packaging/docs

- Install script.
- KDE Neon install docs.
- CodexBar attribution/license docs.
- Troubleshooting guide.

## Final recommendation

Build `neon-codexbar` as a new KDE/Plasma frontend powered by CodexBar CLI.

Use the existing widget projects as blueprints, but keep the architecture clean from day one:

- CodexBar owns providers.
- neon-codexbar owns KDE UX.
- Provider additions happen upstream/CodexBar-first.
- The app renders whatever CodexBar can output.

That is the least dumb path. Suspiciously rare, but here we are.

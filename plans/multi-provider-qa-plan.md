# Multi-Provider QA Plan

## Goal

Before starting Phase 4, verify the Phase 3 widget renders multiple provider
shapes correctly:

- quota-window providers
- three-window providers
- credit/balance providers
- provider error cards
- diagnostics overflow

The current live Codex-only test proves install, daemon, snapshot read, compact
summary, and popup activation. It does not prove the generic renderer handles
the other normalized card shapes.

## Test Order

### 1. Preserve the Working Popup Fix

Status: done locally during KDE Neon QA.

The compact icon now opens the full popup using a KDE-style `MouseArea` that
toggles the parent `PlasmoidItem.expanded`.

### 2. Fixture-Based UI Tests

Use fixture snapshots before changing auth/provider config. This keeps UI
validation independent from live API credentials.

Recommended fixture:

```text
tests/fixtures/snapshot/phase3-four-provider.json
```

Manual test flow:

```bash
systemctl --user stop neon-codexbar.service
cp tests/fixtures/snapshot/phase3-four-provider.json ~/.cache/neon-codexbar/snapshot.json
kquitapp6 plasmashell && kstart plasmashell
```

Validate:

- compact icon shows the max usage from the fixture
- popup opens on left click
- every fixture provider has a card
- quota windows render in array order
- credit meters render when present
- error/setup hints render as provider-local cards
- diagnostics area scrolls and can collapse/expand

After fixture testing:

```bash
systemctl --user start neon-codexbar.service
```

### 3. Live Provider Tests

Enable and validate one provider at a time. Do not change multiple auth/config
surfaces at once.

#### Codex

Already validated live.

Expected:

- provider name: Codex
- source/version visible
- plan/login/email visible when available
- two quota windows visible

#### Claude

Prerequisite: Claude CLI is authenticated.

Validation:

```bash
codexbar --provider claude --source cli --format json
neon-codexbar fetch --json
systemctl --user restart neon-codexbar.service
```

Expected:

- Claude card appears if enabled in CodexBar config and source policy allows it
- provider failures show as a card, not as a global daemon failure

#### z.ai

Prerequisite: API auth configured where CodexBar expects it.

Validation:

```bash
codexbar --provider zai --source api --format json
neon-codexbar fetch --json
systemctl --user restart neon-codexbar.service
```

Expected:

- z.ai card can render three quota windows
- labels are generic and not hardcoded to Session/Weekly

#### OpenRouter

Prerequisite: API auth configured where CodexBar expects it.

Validation:

```bash
codexbar --provider openrouter --source api --format json
neon-codexbar fetch --json
systemctl --user restart neon-codexbar.service
```

Expected:

- credit/balance meter appears
- missing `used_percent` falls back to readable text
- plan/login heuristics do not display a balance string as a plan

## Diagnostics Noise

Current live popup shows many diagnostics for disabled/unsupported providers:

```text
Provider 'cursor' is not in neon-codexbar Linux source policy; skipping...
```

This is acceptable for debug but too noisy for normal use.

Recommended follow-up before or during Phase 4:

- disabled unsupported providers should be quiet by default
- enabled unsupported providers should warn clearly
- diagnostics should remain available for troubleshooting
- normal popup should focus on enabled/attempted providers

## Acceptance Criteria

- Clean install works from current `main`.
- Compact icon shows live max usage.
- Left-click opens the full popup.
- Popup clearly identifies which provider is near limit.
- Multiple provider cards render without overlap.
- Fixture with four providers renders all expected cards.
- Live enabled providers appear automatically when auth/config is present.
- One failed provider does not make the whole widget look globally broken.
- Diagnostics are useful but not overwhelming in normal use.

## Multi-Agent Review Prompts

1. **Renderer review:** Inspect `FullRepresentation.qml`, `ProviderCard.qml`,
   `QuotaWindowBar.qml`, and `CreditMeter.qml` against
   `docs/DAEMON_CONTRACT.md`; identify any field shapes that can break layout.
2. **Fixture review:** Validate that `phase3-four-provider.json` exercises
   quota windows, credit meters, errors, stale cards, and diagnostics.
3. **Live-provider review:** Compare CodexBar live outputs for Codex, Claude,
   z.ai, and OpenRouter against normalized `ProviderCard` output.
4. **Diagnostics review:** Recommend a Phase 4 display policy for disabled,
   unsupported, enabled-failing, and unknown providers.

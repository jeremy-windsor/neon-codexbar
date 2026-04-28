# Popup Details QA and Fix Plan

## Current Observation

After fixing QML local file reads, the compact panel icon renders live data:

- Example: `1 provider 86%`
- This confirms the daemon snapshot is readable by the plasmoid.

Clicking the icon does not currently show the expected detailed popup with:

- provider name/id/source/version
- plan/login/account identity when available
- quota window bars
- credit meters
- diagnostics/setup hints

## Phase Classification

This is mostly a **Phase 3 QA/fix item**, not Phase 4.

Phase 3 already defines and implements:

- `FullRepresentation.qml` as the popup
- `ProviderCard.qml` for one provider
- dynamic quota windows and credit meters
- diagnostics display

Phase 4 can still improve the experience by adding:

- provider display mode
- per-provider show/hide
- better settings UI
- provider expansion/discovery refinements

But the basic click-to-open detailed popup should work before Phase 4.

## Likely Causes to Investigate

1. `compactRepresentation` may not be opening `fullRepresentation` under Plasma 6.
2. Removing the explicit `MouseArea` may have left no activation handler on the compact item.
3. Plasma may require `Plasmoid.activated()` or an explicit `MouseArea` that preserves panel behavior.
4. The popup may open but size to an unusable/empty geometry.
5. The popup content may be rendered but hidden by layout sizing issues.

## Candidate Fixes

### Option A: Use Plasmoid Activation API

Preferred first attempt if Plasma 6 supports it cleanly:

```qml
TapHandler {
    onTapped: Plasmoid.activated()
}
```

or:

```qml
MouseArea {
    anchors.fill: parent
    acceptedButtons: Qt.LeftButton
    onClicked: Plasmoid.activated()
}
```

Need to verify this does not break panel drag/edit interactions.

### Option B: Toggle Expanded Explicitly

Fallback if activation does not work:

```qml
onClicked: Plasmoid.expanded = !Plasmoid.expanded
```

This is simple and readable, but should be tested on Plasma 6 because some shell versions prefer activation over direct `expanded` mutation.

### Option C: Keep Compact Click Passive, Add Popup Action

Less ideal for normal UX. Add an explicit action or context menu item to open details. This should only be used if Plasma panel interaction rules make direct compact clicks unreliable.

## Popup Content Improvements

Once the popup opens, verify these details are visible for the current one-provider snapshot:

- Header: `neon-codexbar`, update age, CodexBar version.
- Provider card title: `Codex`.
- Metadata line: source and version, for example `codex-cli v0.125.0`.
- Identity line: plan/login/email where present.
- Quota bars:
  - primary 5-hour window usage
  - secondary weekly window usage
  - reset descriptions
- Diagnostics collapsed by default but available.

If the popup opens but is too terse, improve `ProviderCard.qml` with a small metadata section:

- `provider_id`
- `source`
- `version`
- `plan`
- `login_method`
- `identity.accountEmail`
- `last_success`
- `last_attempt`

Keep this provider-agnostic. Do not hardcode Codex, Claude, z.ai, OpenRouter, Session, or Weekly labels.

## Validation Commands

After changing the activation behavior:

```bash
kpackagetool6 -t Plasma/Applet -u /home/jeremy/neon-codexbar/plasmoid
kquitapp6 plasmashell || true
kstart plasmashell
journalctl --user -b --since '2 minutes ago' --no-pager \
  | grep -iE 'neon-codexbar|qml|plasmoid|PageRow|FullRepresentation|CompactRepresentation'
```

Manual validation:

1. Click the compact panel icon.
2. Confirm a popup opens.
3. Confirm the popup shows the provider card, not only the summary text.
4. Confirm diagnostics can expand/collapse.
5. Confirm clicking outside closes the popup.
6. Confirm panel edit/drag behavior is not broken.

## Multi-Agent Review Prompts

Use separate agents for independent verification:

1. **Plasma API review:** Review `main.qml` and `CompactRepresentation.qml`; recommend the Plasma 6-correct way to open `fullRepresentation` from compact clicks without breaking panel behavior.
2. **Layout review:** Review `FullRepresentation.qml`, `ProviderCard.qml`, `QuotaWindowBar.qml`, and `CreditMeter.qml`; identify why the popup could open blank/tiny or fail to show detailed provider fields.
3. **UX review:** Given the snapshot contract, recommend the minimum provider-agnostic metadata that should be visible in a one-provider popup.
4. **QA review:** Turn the current live laptop findings into a checklist that distinguishes install failures, daemon failures, snapshot read failures, and popup activation failures.

## Acceptance Criteria

- Compact icon still shows the summary percentage.
- Left-click opens a detailed popup.
- Popup renders one card per snapshot card.
- The current Codex card explains what the 86% refers to through quota-window labels/reset text.
- No provider-specific assumptions are added to QML.
- Fresh journal logs stay free of QML activation/layout errors.

## Status — applied 2026-04-27

Two fixes landed:

### 1. Click-to-expand activation

Root cause: removing the explicit `MouseArea` in the previous peer-review pass
left `CompactRepresentation` with no input handler at all. PlasmoidItem does
**not** auto-handle compact clicks under Plasma 6 — that was a wrong claim in
the prior peer review.

Fix: `TapHandler` in `plasmoid/contents/ui/CompactRepresentation.qml`:

```qml
TapHandler {
    acceptedButtons: Qt.LeftButton
    onTapped: Plasmoid.expanded = !Plasmoid.expanded
}
```

`TapHandler` (Qt 6 native pointer handler) toggles the popup but, unlike a
`MouseArea` with `anchors.fill: parent`, does **not** swallow the panel
chrome's drag-to-move or middle-click events. This satisfies both the prior
peer-review concern and the actual KDE Neon QA finding.

### 2. Enriched popup metadata

`plasmoid/contents/ui/ProviderCard.qml` gains a per-field metadata block under
the identity row:

- `id: <provider_id>` (monospaced)
- `last success: <relative time>`
- `last attempt: <relative time>` (only when it differs from `last_success`,
  i.e. a recent failed retry)

Reuses `SnapshotStore.relativeAge()` via a new optional `store` property on
`ProviderCard` (passed through from `FullRepresentation`'s `Repeater`).
Stays provider-agnostic — values come from `snapshot.cards[i]` verbatim.

Header still shows `display_name`, `source v<version>`, and a `stale` badge.
Identity row still shows `plan / login_method / accountEmail` (de-duplicated
when login_method == plan).

### Acceptance retest items for KDE Neon

After re-installing (`./packaging/install.sh --restart-plasma`):

1. Compact icon still shows summary.
2. Left-click on the icon opens the popup. ← was failing before
3. Drag the widget on the panel still works. ← TapHandler doesn't swallow
4. Middle-click on the widget still triggers the panel context, not popup.
5. ProviderCard shows the new metadata block (id, last success/attempt).
6. Diagnostics toggle still works.

Plan status: **complete pending KDE Neon retest**.

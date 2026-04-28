# Phase 4 UI/UX Cleanup Plan

## Current QA Findings

KDE Neon QA now proves the core Phase 3 path works:

- clean install/uninstall mostly works
- daemon starts and writes snapshots
- Codex and Claude render in the popup
- compact icon opens the popup
- quota labels are friendlier than `Window 1` / `Window 2`
- disabled unsupported providers no longer flood diagnostics

The remaining issues are UX polish and settings architecture, not provider
fetching fundamentals.

## Settings Dialog Problem

The Plasma settings window currently shows `General`, `Keyboard Shortcuts`, and
`About`, but the `General` page can appear empty or not useful. That means users
cannot comfortably configure:

- provider order
- which provider is active in the tray
- tray display mode
- popup/debug behavior
- thresholds and snapshot path

Text-field-only settings are not the right final UX. Users should not need to
edit JSON or type comma-separated provider ids for normal display control.

## Settings UX Target

Build a real provider display settings page.

### Provider Rows

Show one row per provider from the current snapshot/discovery data:

- display name
- provider id
- source/version when known
- enabled/fetch status
- up/down buttons for popup order
- checkbox: `Show in popup`
- single-select radio/check: `Active in tray`

Only one provider can be active in tray at a time.

### Tray Mode

Add a clear segmented/combobox control:

- `Highest usage`
- `Selected provider`
- later: `Problem first`

Behavior:

- `Highest usage`: compact icon shows max usage across visible providers.
- `Selected provider`: compact icon shows the selected provider's max usage.
- If selected provider is missing, fall back to highest usage and show a debug
  note.

### Internal Storage

Use Plasma/KConfig fields behind the GUI:

- `providerOrder`
- `trayProvider`
- `trayMode`
- optionally `hiddenProviders`

It is acceptable for KConfig to store strings internally, but the GUI must hide
that from the user.

## Popup Cleanup

The popup is now functional but visually uneven.

Recommended changes:

- Keep the user-resizable/tall popup behavior. Do not force a smaller height.
- Keep provider cards compact but readable.
- Collapse routine metadata by default.
- Rename `Show details` to a more specific label such as `Provider details`.
- Keep `Show debug (0)` always visible so troubleshooting is discoverable.
- Move `Show debug` to a consistent footer-like position.
- Reduce link/button styling artifacts that make `Show debug` look like an
  underlined web link.
- Preserve enough spacing between cards and sections to avoid visual crowding.

## Reset Text Cleanup

Current reset text can look noisy, especially with provider strings like:

```text
ResetsMay4,7am(America/Phoenix) • resets 4 May 2026 07:00:00
```

KDE Neon QA also exposed a z.ai-specific ambiguity:

```text
1 minute window
resets 5 May 2026 06:57:36
```

The raw snapshot for that row had `window_minutes=null`,
`reset_description="1 minute window"`, and a far-future `resets_at`. Pairing
those fields makes the UI imply a one-minute window resets days later, which is
misleading. Treat that as conflicting provider metadata, not as a normal reset
line.

Recommended policy:

- Prefer provider `reset_description` when it is readable.
- If `reset_description` is cramped or machine-like, prefer formatted
  `resets_at`.
- Avoid showing both if they duplicate the same information.
- If `reset_description` is itself a window label (`1 minute window`,
  `1 week window`, `5 hours window`) and `window_minutes` is missing, use it as
  the row title and do not append `resets_at` unless CodexBar provides enough
  matching duration data to prove the timestamp belongs to that window.
- Format timestamps as local short date/time.
- Consider labels like:
  - `resets today 10:01 AM`
  - `resets May 4, 7:00 AM`

For z.ai, prefer showing the provider-supplied window labels directly:

- `1 week window`
- `1 minute window`
- `5 hours window`

Do not hardcode these labels globally; use them when CodexBar supplies them.
Keep raw conflicting fields available in debug.

## Diagnostics / Debug

Debug should be available without dominating normal usage.

Recommended collapsed content:

- provider count
- selected tray mode/provider
- snapshot path
- generated timestamp
- CodexBar path/version
- diagnostics list, or `No diagnostics`

Diagnostics policy:

- disabled unsupported providers: quiet
- enabled unsupported providers: warn
- enabled provider fetch failure: provider error card
- global CodexBar/daemon failure: global banner

## Provider Enablement

Provider enablement remains CodexBar-owned:

- neon-codexbar settings control display only
- CodexBar config controls whether a provider is enabled
- provider auth/secrets stay in CodexBar-supported locations

For Phase 4, consider adding a read-only provider status section:

- `Configured in CodexBar`
- `Enabled`
- `Supported on Linux`
- `Last fetch status`

Do not add provider API-key fields to neon-codexbar.

## Implementation Notes

The config page may need a small QML snapshot reader or a helper model so it can
show current providers. Avoid duplicating too much `SnapshotStore.qml`; a shared
read-only provider model would be cleaner if the QML allows it.

If the settings dialog cannot safely read snapshot data, keep Phase 4 settings
simple:

- tray mode combobox
- active provider combobox populated from known providers in snapshot
- order list populated from snapshot

Fallback unknown/manual fields can remain hidden under an advanced section.

## Acceptance Criteria

- `General` settings page is populated and useful.
- Provider order can be changed without editing JSON.
- Active tray provider can be selected without typing provider ids.
- Popup order follows settings.
- Tray icon follows selected mode.
- Debug is always discoverable.
- Normal popup has no disabled-provider diagnostic flood.
- No provider secrets are stored in neon-codexbar config.

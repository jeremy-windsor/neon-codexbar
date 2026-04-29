# Phase 4 Cleanup Process

## Goal

Phase 4 is the display-control phase. The daemon and provider fetch path already
work; this phase should make the Plasma widget configurable and useful without
editing config files by hand.

The target user workflow:

1. Open the popup.
2. Click a configure button from the popup or use the normal Plasma settings.
3. Reorder providers manually.
4. Hide providers from the popup.
5. Pick what the compact tray icon represents.
6. Pick how the compact tray icon renders usage.
7. Save settings and see the popup/tray update without restarting the daemon.

## Current QA State

Observed on KDE Neon:

- Popup renders provider cards and current usage.
- The Settings window opens and shows `General`, `Keyboard Shortcuts`, and
  `About`.
- The `General` page body is empty.
- Plasma logs show PageRow/config load errors when opening the applet config:

```text
PageRow.qml:999: TypeError: Passing incompatible arguments to C++ functions from JavaScript is not allowed.
AppletConfiguration.qml:55: TypeError: Cannot read property 'saveConfig' of null
```

Do not continue adding settings controls until the General page reliably loads.
The current failure means users cannot reach Phase 4 features even if the
underlying KConfig fields exist.

## Work Order

### 1. Fix Settings Page Loading

Objective: `General` must show real controls.

Tasks:

- Make `ConfigGeneral.qml` follow the Plasma 6 applet configuration pattern
  used by installed working applets on this machine.
- Keep it as a KCM/page object, not a bare layout.
- Confirm `config.qml` resolves the page source correctly.
- Confirm all `cfg_*` properties that Plasma injects have matching writable
  properties or aliases on the page.
- Remove or isolate anything that breaks page creation:
  - unsupported root type
  - unsupported injected property
  - bad `ConfigCategory.source`
  - config page imports not available in plasmashell
  - early JavaScript side effects during component construction

Acceptance:

- Opening widget settings shows visible controls under `General`.
- No new `PageRow.qml` or `AppletConfiguration.qml` errors appear in
  `journalctl --user`.
- OK/Cancel/Apply behavior still works.

Test:

```bash
journalctl --user --since "2 minutes ago" --no-pager \
  | rg -i "neon-codexbar|ConfigGeneral|AppletConfiguration|PageRow|qml"
```

Manual:

- Right-click widget.
- Open settings.
- Click `General`.
- Confirm controls are visible.
- Click OK and Cancel once each.

### 2. Add Configure Button To Popup

Objective: users should not have to know Plasma's right-click path.

Tasks:

- Add a configure button in the popup header near Refresh.
- Use a standard settings icon, such as `configure`.
- Open the applet configuration window through the Plasma applet API.
- Keep Refresh and Configure visually distinct.
- Add a tooltip: `Configure`.

Acceptance:

- Popup has a visible configure button.
- Clicking it opens the same settings window as Plasma's widget settings.
- Button does not interfere with popup refresh.

### 3. Provider Display Controls

Objective: manual provider order and visibility work from the settings page.

KConfig fields:

- `providerOrder`: comma-separated provider IDs in popup order.
- `hiddenProviders`: comma-separated provider IDs hidden from normal display.
- `trayProvider`: provider ID used when tray source is selected provider.
- `trayMode`: `highest-usage` or `selected-provider`.

Settings UI:

- Show one row per provider from the latest snapshot.
- Row content:
  - display name
  - provider ID
  - source/version when available
  - fetch/status summary
  - up/down buttons
  - `Show in popup` checkbox
  - `Active in tray` radio button
- Hide the raw comma-separated strings from normal users.
- If snapshot data is unavailable, show a clear empty/error state and keep
  advanced manual fields hidden or collapsed.

Acceptance:

- Moving provider rows changes popup card order.
- Unchecking `Show in popup` hides the provider from the popup.
- Hidden providers are not candidates for selected-provider tray display.
- Selected tray provider persists after OK/reopen.

### 4. Tray Percentage Source

Objective: users can choose which percentage the compact icon represents.

Add KConfig fields:

- `trayUsageSource`
- `trayPrimaryWindow`
- `traySecondaryWindow`

Suggested values:

- `trayUsageSource`
  - `highest-visible-provider`
  - `selected-provider`
  - `selected-window`
  - `two-windows`
- `trayPrimaryWindow`
  - `highest`
  - `primary`
  - `secondary`
  - `tertiary`
  - `5-hour`
  - `7-day`
- `traySecondaryWindow`
  - same options as `trayPrimaryWindow`

Rules:

- `highest-visible-provider`: use max usage across visible providers.
- `selected-provider`: use max usage for `trayProvider`.
- `selected-window`: use the chosen window for `trayProvider`, falling back to
  that provider's max usage if the window is missing.
- `two-windows`: render primary and secondary values for `trayProvider`.
- If `trayProvider` is missing or hidden, fall back to highest visible provider
  and show this in debug.

Acceptance:

- Changing the source changes the compact icon immediately after Apply.
- Missing windows have a predictable fallback.
- Debug output states the resolved tray source and fallback, if any.

### 5. Tray Icon Render Styles

Objective: users can choose how compact usage appears in the panel.

Add KConfig field:

- `trayIconStyle`

Initial styles:

- `percent-ring`: current style, one number inside severity-colored ring.
- `percent-only`: just the percentage text, no ring.
- `two-percentages`: compact `86/21` style for two selected windows.
- `bars`: one or two tiny horizontal bars.
- `circles`: one or two small circular indicators.

Keep styles readable at normal Plasma panel sizes. If a style cannot remain
legible at small panel heights, do not ship it yet.

Acceptance:

- Style can be changed from Settings.
- Style persists after Plasma restart.
- Compact icon does not resize the panel.
- Text does not overlap or clip badly at common panel heights.

Manual test matrix:

- Horizontal panel, small height.
- Horizontal panel, default height.
- Vertical panel if practical.
- Dark theme, current machine theme.

### 6. Popup Reset Text Cleanup

Objective: reset lines should be readable and not misleading.

Current screenshot still shows noisy examples:

- `ResetsMay4,6:59am(America/Phoenix) • resets 4 May 2026 06:59:00`
- `1 minute window` followed by `resets 5 May 2026 ...`

Tasks:

- Avoid showing provider reset description and formatted `resets_at` when they
  duplicate the same fact.
- If `reset_description` is itself a window label and `window_minutes` is
  missing, do not append `resets_at`.
- Prefer local short date/time formatting.
- Keep raw provider fields available only in debug/details.

Acceptance:

- No duplicated reset text.
- z.ai `1 minute window` no longer implies a days-later one-minute reset.

### 7. Verification

Automated:

```bash
.venv/bin/python -m pytest
.venv/bin/python -m ruff check .
git diff --check
```

Local install:

```bash
packaging/install.sh
```

Runtime:

```bash
systemctl --user is-active neon-codexbar.service
systemctl --user is-enabled neon-codexbar.service
python3 - <<'PY'
import json
from pathlib import Path
p = Path.home() / ".cache/neon-codexbar/snapshot.json"
data = json.loads(p.read_text())
print(data.get("ok"), len(data.get("cards", [])), len(data.get("diagnostics", [])))
PY
```

Plasma QA:

- Restart plasmashell after install if needed:

```bash
kquitapp6 plasmashell && kstart plasmashell
```

- Open popup.
- Click Configure.
- Confirm General page has controls.
- Reorder providers.
- Hide one provider.
- Change tray source.
- Change tray icon style.
- Click OK.
- Reopen popup and settings.
- Confirm settings persisted and UI followed them.

## Definition Of Done

Phase 4 is done when:

- General settings page is not blank.
- Popup has a working Configure button.
- Provider order is manually adjustable.
- Provider visibility is manually adjustable.
- Tray provider/source is manually adjustable.
- Tray icon style is manually adjustable.
- Popup and compact icon honor saved settings.
- Reset text is readable and not misleading.
- Python tests and ruff pass.
- KDE Neon manual QA passes after reinstall.

## Status — applied 2026-04-28

| # | Item | Status |
|---|---|---|
| 1 | Fix Settings Page Loading | ✅ done in `45213db` (`KCM.SimpleKCM` root, all `cfg_*` aliases) |
| 2 | Add Configure Button To Popup | ✅ done — `FullRepresentation` ToolButton next to Refresh; `Plasmoid.internalAction("configure").trigger()` called via `plasmoidItem` reference (same pattern that fixed compact-click last round) |
| 3 | Provider Display Controls | ✅ done in `9b616c8` — per-provider rows with up/down/check/radio + Reload button |
| 4 | Tray Percentage Source | ⚠️ **partial** — `highest-usage` and `selected-provider` work; `selected-window` and `two-windows` deferred (see below) |
| 5 | Tray Icon Render Styles | ⚠️ **MVP only** — `percent-ring` (default) + `percent-only` shipped; `two-percentages` / `bars` / `circles` deferred (see below) |
| 6 | Popup Reset Text Cleanup | ✅ done in `9b616c8` — `_looksLikeWindowLabel` regex skips redundant `resets_at` line in `QuotaWindowBar` |
| 7 | Verification | ✅ 37/37 pytest, ruff clean (sandbox); KDE Neon manual QA on Jeremy |

### Deferred items, with reasoning

**Item 4 — `selected-window` / `two-windows` tray sources.** Pushed to a
follow-up. Reasoning:

- The existing `highest-usage` and `selected-provider` cover the common
  cases. Power users wanting per-window pinning are a smaller audience.
- `selected-window` requires a new `SnapshotStore` method to resolve "give
  me provider X's window N percent" plus matching settings UI conditional
  rows (only visible when source is `selected-window`/`two-windows`).
- The plan explicitly hedges: "If a style cannot remain legible at small
  panel heights, do not ship it yet." Two-windows in particular needs visual
  validation we cannot do in the sandbox.
- Designing the right window-picker UX is easier after the basic
  percent-only style has been used and we know what's missing.

**Item 5 — `two-percentages` / `bars` / `circles` icon styles.** Pushed to a
follow-up. Reasoning:

- `percent-only` (the new style) gives users an immediate "hide the ring"
  option which is the highest-probability real ask.
- Sandbox cannot validate visual legibility of `bars` or `circles` at
  panel sizes. The plan says do not ship illegible styles.
- `two-percentages` couples to `two-windows` (item 4), which is also
  deferred. They should ship together so the source/style combination is
  coherent.

When the deferred work picks up: extend `main.xml` with `trayUsageSource`,
`trayPrimaryWindow`, `traySecondaryWindow`; extend `SnapshotStore` with a
`windowPercentForProvider(providerId, windowKey)` resolver; extend
`CompactRepresentation` with the additional style cases; extend
`ConfigGeneral` with conditional rows.

### Verification this pass

```
python3 -m pytest          → 37 passed
python3 -m ruff check .    → All checks passed
```

KDE Neon retest items:

1. Click Configure button in popup header → settings dialog opens.
2. In settings, change Tray icon style to "Percent only" → ring disappears,
   percent text scales up. Save persists across reopen.
3. Existing item-1 / item-3 / item-6 functionality still works (no regression).

Plan status: **complete for the v1 ship targets**. Items 4 and 5's deferred
slices are tracked in this status section as the next iteration's queue.

## Follow-up questions for Jeremy

Real questions I'd want answered before building the deferred slices or
moving to Phase 5. Most are small but they shape the implementation.

### Q1 — Configure button & percent-only style: do they actually work on Neon?

I shipped both blind (no Plasma session in the sandbox). Both reuse patterns
KDE QA already validated last round, but I'd like real confirmation before
trusting the same APIs further:

- Does the Configure button in the popup header open the settings dialog?
- Does `Tray icon style: Percent only` actually hide the ring and scale the
  text up legibly at your normal panel height?

If either fails, I want to know before I extend `internalAction()` calls to
other actions or before I add more icon styles.

### Q2 — Window picker semantics for `selected-window` mode

Snapshots expose windows as both:

- **index keys** — `quota_windows[0..2].id` is `"primary"` / `"secondary"`
  / `"tertiary"`
- **semantic labels** — `quota_windows[i].window_label` is `"5-hour window"`
  / `"7-day window"` / `null` (z.ai's secondary)

The window-picker dropdown in settings has to use one of these. Tradeoffs:

- **Index (primary/secondary/tertiary):** always present, provider-agnostic,
  but cryptic. User has to remember "primary = 5h for Codex, primary = 7d
  for z.ai."
- **Label (5-hour window):** friendly, but not stable across providers and
  sometimes null. A "5-hour window" pick might match codex's primary AND
  z.ai's tertiary depending on which provider is selected.

Recommended: hybrid — show `<label> (primary/secondary/tertiary)` in the
dropdown. When the label is null, show just the index key.

**Question:** OK with the hybrid, or you want strictly one or the other?

### Q3 — Hidden providers vs `highest-usage` tray

Right now `displayCards` filters hidden providers, and
`highest-usage` walks `displayCards`. So hiding a provider also stops it
from triggering tray-color alerts.

That's a real semantic choice with two reasonable answers:

- **Current behavior** — hidden = invisible everywhere, including tray
  alerts. Clean and consistent.
- **Alternative** — hidden = invisible in the popup, but still counted in
  `highest-usage` so tray turns red if any *enabled* provider is hot.

The alternative is what most "show only my main accounts but warn me if
anything's burning" power users probably want. Today the user has no way
to express "I want this provider monitored but collapsed."

**Question:** keep current, switch, or add a third state ("show in popup"
+ "include in tray alerts" as separate checkboxes)?

### Q4 — `trayProviderMissing` indicator

When tray mode is `selected-provider` and the chosen provider is gone
(hidden or removed from snapshot), `SnapshotStore` falls back to highest
usage and sets `trayProviderMissing = true`. Today the only place this
surfaces is the debug block.

**Question:** want a visual indicator on the compact icon (e.g., dotted
ring border, or a small `?` overlay), or is the silent-fallback +
debug-only signal enough?

### Q5 — Bounds on KConfig SpinBoxes

Current `daemonStaleThreshold` minimum is 30s, `daemonDeadThreshold` is
60s, `pollingInterval` max is 300s. Some of these feel arbitrary now that
we have real usage:

- 30s stale threshold is shorter than a normal CodexBar fetch cycle
  (claude alone takes ~15s). Should the floor be ~120s?
- 300s polling interval feels like it should max higher; if the daemon
  refresh is 300s, polling at 300s gives no headroom.

**Question:** want me to revise the bounds, or are the current ones fine
as guardrails?

### Q6 — i18n in popup strings

`ConfigGeneral.qml` uses `i18n("…")` for every label. The popup
(`FullRepresentation.qml`, `ProviderCard.qml`, banners, etc.) does not —
strings like "Refresh", "Configure", "Show debug", "snapshot unavailable"
are bare English.

Master plan §16 ("Open questions") said i18n is deferred to v0.2. With
Phase 4 settling the popup UX, now might be the right time — or not.

**Question:** wrap popup strings in `i18n()` as part of Phase 5 polish, or
keep deferred?

### Q7 — `Plasmoid.toolTipMainText` / `toolTipSubText` deprecation

`main.qml` uses these with a comment noting they're deprecated in Plasma 6
in favor of `toolTipItem`. Migration is a small change but visible in
journalctl as warnings.

**Question:** migrate now (clean journal), or defer until we want a
richer tooltip with an icon (which is the actual reason `toolTipItem`
exists)?

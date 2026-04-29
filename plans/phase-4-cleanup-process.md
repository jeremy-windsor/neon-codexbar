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

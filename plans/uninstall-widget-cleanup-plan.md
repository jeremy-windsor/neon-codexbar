# Uninstall Widget Cleanup Plan

## Current Observation

Running:

```bash
./packaging/uninstall.sh --purge
```

removes the plasmoid package from the widget list, but any existing
neon-codexbar instance can remain on the panel/taskbar until Plasma is
restarted. After restart, the widget may appear as a broken/missing applet and
must be removed manually in panel edit mode.

That makes uninstall look incomplete even though `kpackagetool6 -r` succeeded.

## Root Cause

`kpackagetool6 -t Plasma/Applet -r org.jeremywindsor.neon-codexbar` removes the
installed widget package. It does not remove live applet instances from the
user's Plasma layout.

Those instances live in Plasma's layout/config state, typically:

```text
~/.config/plasma-org.kde.plasma.desktop-appletsrc
```

Editing this file directly is risky because it stores the whole desktop/panel
layout. A bad edit can damage unrelated panels/widgets.

## Desired Behavior

Uninstall should either:

1. Safely remove neon-codexbar applet instances before removing the package, or
2. Clearly tell the user to remove the widget from the panel first and offer a
   Plasma shell restart afterward.

Prefer the safest behavior over silent config surgery.

## Recommended v1 Fix

Add a preflight warning to `packaging/uninstall.sh`:

1. Detect whether `~/.config/plasma-org.kde.plasma.desktop-appletsrc` contains
   `org.jeremywindsor.neon-codexbar`.
2. If found, print a clear warning before package removal:

   ```text
   neon-codexbar still appears in your Plasma panel layout.
   Recommended: remove it from the panel first:
     1. Right-click panel -> Enter Edit Mode
     2. Hover/right-click neon-codexbar -> Remove
     3. Re-run uninstall.sh
   Continuing will remove the package, but Plasma may leave a broken panel item
   until plasmashell is restarted and the item is removed manually.
   ```

3. In interactive terminals, ask for confirmation unless `--force` is supplied.
4. In non-interactive mode, continue but print the warning.
5. After uninstall, offer to restart Plasma:

   ```bash
   kquitapp6 plasmashell || true
   kstart plasmashell
   ```

## Optional v2 Fix: Remove Instances Automatically

Only attempt automatic instance removal if we can use a supported Plasma API.
Research options:

- Plasma scripting through `qdbus6 org.kde.plasmashell /PlasmaShell evaluateScript`.
- A JavaScript snippet that iterates panels/applets and removes only applets
  whose plugin id equals `org.jeremywindsor.neon-codexbar`.

Possible shape, subject to live validation:

```javascript
for (const panel of panels()) {
  for (const widget of panel.widgets()) {
    if (widget.type === "org.jeremywindsor.neon-codexbar") {
      widget.remove();
    }
  }
}
```

Do not ship this until verified on KDE Neon/Plasma 6. Plasma scripting APIs can
change, and accidental removal of unrelated widgets would be worse than a manual
cleanup prompt.

## Avoid

- Do not directly rewrite `plasma-org.kde.plasma.desktop-appletsrc` in v1.
- Do not delete broader Plasma config files.
- Do not restart Plasma without telling the user.
- Do not touch `~/.codexbar/`.

## Test Plan

Manual test sequence:

1. Install neon-codexbar.
2. Add the widget to the panel.
3. Run `./packaging/uninstall.sh --purge`.
4. Confirm the script detects the existing panel instance and warns clearly.
5. Remove the widget manually from panel edit mode.
6. Re-run uninstall and confirm no warning appears.
7. Restart Plasma and confirm no broken neon-codexbar item remains.

Optional automatic-removal test, only if v2 is implemented:

1. Back up Plasma layout:

   ```bash
   cp ~/.config/plasma-org.kde.plasma.desktop-appletsrc \
      ~/.config/plasma-org.kde.plasma.desktop-appletsrc.before-neon-codexbar-test
   ```

2. Install and add neon-codexbar to the panel.
3. Run uninstall with the automatic removal flag.
4. Confirm only neon-codexbar applet entries are removed.
5. Confirm unrelated widgets and panels remain intact.

## Multi-Agent Review Prompts

1. **Installer safety review:** Review `packaging/uninstall.sh` and recommend a
   safe UX for detecting live Plasma applet instances without editing global
   layout state.
2. **Plasma scripting review:** Determine whether Plasma 6 exposes a supported
   `qdbus6 ... evaluateScript` path to remove applets by plugin id.
3. **QA review:** Build a clean install/uninstall checklist that covers package
   removal, live panel instance cleanup, Plasma restart behavior, and purge
   safety.

## Acceptance Criteria

- `uninstall.sh --purge` no longer silently leaves users confused by a broken
  panel item.
- The script clearly distinguishes package removal from panel instance removal.
- v1 does not risk corrupting unrelated Plasma layout config.
- Any future automatic cleanup is opt-in or well-validated on Plasma 6.

# Install Launch Fix Plan

## Problem

Fresh installs can leave the plasmoid present but unable to launch/usefully render:

- Plasma/QML blocks local `file://` reads unless `QML_XHR_ALLOW_FILE_READ=1` is present in the running `plasmashell` environment.
- The config page source must resolve through Plasma's package root. `source: "ConfigGeneral.qml"` can make Plasma apply neon-codexbar `cfg_*` properties to built-in config pages such as shortcuts/about.

Observed symptoms:

- Panel tooltip says `CodexBar not available` even while `neon-codexbar-daemon` is running and writing a valid snapshot.
- Journal includes `Set QML_XHR_ALLOW_FILE_READ to 1 to enable this feature.`
- Journal includes `ConfigurationShortcuts does not have a property called cfg_*` and `AboutPlugin does not have a property called cfg_*`.

## Immediate Fix

1. Keep `plasmoid/contents/config/config.qml` using package-root source paths:

   ```qml
   source: "config/ConfigGeneral.qml"
   ```

2. Make the installer set the user session environment before Plasma is restarted:

   ```bash
   systemctl --user set-environment QML_XHR_ALLOW_FILE_READ=1
   dbus-update-activation-environment --systemd QML_XHR_ALLOW_FILE_READ
   ```

3. After installing/upgrading the plasmoid, restart the shell in a way that reliably inherits the environment:

   ```bash
   kquitapp6 plasmashell || true
   kstart plasmashell
   ```

## Installer Changes

Update `packaging/install.sh`:

1. Add a `configure_plasma_qml_file_read` step after prerequisite checks.
2. Run both environment export commands if available.
3. Print a warning if either command fails, but do not fail the whole install.
4. After `kpackagetool6` install/upgrade, offer or perform a Plasma shell restart so the new env is picked up.
5. Add a post-install validation step:

   ```bash
   systemctl --user show-environment | grep -F 'QML_XHR_ALLOW_FILE_READ=1'
   ```

## Verification

After install:

```bash
pgrep -af plasmashell
tr '\0' '\n' < /proc/$(pgrep -n plasmashell)/environ | grep '^QML_XHR_ALLOW_FILE_READ=1$'
journalctl --user -b --since '2 minutes ago' --no-pager \
  | grep -iE 'neon-codexbar|QML_XHR|ConfigGeneral|ConfigurationShortcuts|AboutPlugin|PageRow.qml'
```

Expected result:

- Running `plasmashell` has `QML_XHR_ALLOW_FILE_READ=1`.
- No fresh `QML_XHR`, `ConfigurationShortcuts cfg_*`, `AboutPlugin cfg_*`, or `PageRow.qml` errors after shell restart.
- `neon-codexbar.service` remains active and snapshot writes continue.

## Follow-Up

Longer term, consider replacing QML `XMLHttpRequest file://` reads with a KDE-supported local I/O bridge if Plasma continues tightening local file access. For now, the environment variable is the smallest install-time fix and matches Plasma's own runtime diagnostic.

## Status — applied 2026-04-27

| Item | Status | Where |
|---|---|---|
| `config.qml` source path uses `config/ConfigGeneral.qml` | done (manual fix in commit `cee4796`) | `plasmoid/contents/config/config.qml:8` |
| `systemctl --user set-environment QML_XHR_ALLOW_FILE_READ=1` | done | `packaging/install.sh` step 5 |
| `dbus-update-activation-environment --systemd QML_XHR_ALLOW_FILE_READ=1` | done | `packaging/install.sh` step 5 (with `dbus-x11` install hint if missing) |
| Post-install `systemctl --user show-environment` validation | done | `packaging/install.sh` step 5 |
| Plasma shell restart (opt-in via `--restart-plasma`) | done | `packaging/install.sh` step 6, also printed as instructions when flag absent |
| Warn-not-fail behavior on env-set / dbus failures | done | both wrapped in `warn` not `die` |

QA on KDE Neon:

```bash
./packaging/install.sh --restart-plasma
systemctl --user show-environment | grep -F 'QML_XHR_ALLOW_FILE_READ=1'
tr '\0' '\n' < /proc/$(pgrep -n plasmashell)/environ | grep '^QML_XHR_ALLOW_FILE_READ=1$'
journalctl --user -b --since '2 minutes ago' --no-pager \
  | grep -iE 'neon-codexbar|QML_XHR|ConfigurationShortcuts|AboutPlugin|PageRow.qml'
```

Expected: env var present in both systemd manager and the running `plasmashell` process; no fresh `QML_XHR_ALLOW_FILE_READ` warnings; no `cfg_*` errors against `ConfigurationShortcuts` / `AboutPlugin`.

Plan status: **complete**.

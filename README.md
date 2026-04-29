# neon-codexbar

KDE Plasma widget for CodexBar provider usage.

CodexBar owns provider auth, provider fetching, and provider-specific API/CLI
quirks. neon-codexbar owns the KDE UX: daemon snapshot writing, popup display,
provider ordering, and tray icon rendering.

## Current Status

- Python daemon fetches enabled CodexBar providers.
- Plasma popup renders multiple provider cards.
- Settings page supports provider order, provider visibility, selected tray
  provider, and tray icon style.
- Popup has Refresh and Configure buttons.
- Compact tray icon supports:
  - percent in ring
  - percent only
  - 5h / 7d bars
  - 5h / 7d circles
  - 5h / 7d tiles

## Runtime Flow

```text
neon-codexbar-daemon
  -> CodexBarCLI --provider <id> --source <source> --format json
  -> normalize provider cards
  -> write ~/.cache/neon-codexbar/snapshot.json
  -> Plasma widget reads snapshot.json
```

Runtime files live in standard XDG locations:

- snapshot: `~/.cache/neon-codexbar/snapshot.json`
- systemd user unit: `~/.config/systemd/user/neon-codexbar.service`
- optional auth env drop-in: `~/.config/neon-codexbar/auth.env`

`~/.codexbar/` belongs to CodexBar and is not managed by neon-codexbar.

## Install

```bash
packaging/install.sh
```

The installer:

- installs the Python package with `pip install --user`
- installs or upgrades the Plasma applet with `kpackagetool6`
- installs and starts the systemd user daemon
- enables `QML_XHR_ALLOW_FILE_READ=1` for Plasma snapshot reads
- bootstraps CodexBar config if missing, without overwriting existing config

On this KDE Neon setup, restart Plasma with:

```bash
systemctl --user restart plasma-plasmashell.service
```

## Verify

```bash
.venv/bin/python -m pytest
.venv/bin/python -m ruff check .
systemctl --user status neon-codexbar.service
```

Quick snapshot check:

```bash
python3 - <<'PY'
import json
from pathlib import Path
p = Path.home() / ".cache/neon-codexbar/snapshot.json"
data = json.loads(p.read_text())
print(data.get("ok"), len(data.get("cards", [])), len(data.get("diagnostics", [])))
PY
```

## Refresh Behavior

The daemon refreshes providers on its configured interval and also supports an
early refresh via `SIGUSR1`.

Measured on this machine:

- Codex CLI source: about 2 seconds
- Claude CLI source: about 16 seconds
- z.ai API source: under 1 second
- full daemon tick: about 17 seconds because providers fetch in parallel and
  Claude is the slowest source

The current default refresh cadence is conservative. Shorter intervals should
be tested carefully because some provider sources are CLI-driven and may be
expensive.

## Provider Support

New providers should be added to CodexBar first. neon-codexbar expects CodexBar
to expose providers through:

```bash
CodexBarCLI config dump --format json
CodexBarCLI --provider <id> --source <source> --format json
```

If CodexBar emits the existing generic usage fields, neon-codexbar should
mostly render the provider automatically. Provider-specific work here should be
limited to source policy, friendly display names, fixtures, and tests.

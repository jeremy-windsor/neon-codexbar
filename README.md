# neon-codexbar

KDE Neon / Plasma 6 integration for CodexBar provider usage.

CodexBar owns provider auth, provider fetching, and provider-specific API/CLI
quirks. neon-codexbar owns the KDE UX: daemon snapshot writing, popup display,
provider ordering, and tray icon rendering.

## Project Positioning

neon-codexbar exists to make CodexBar easy to use on Linux KDE desktops,
starting with KDE Neon.

This project is not a replacement for CodexBar and does not reimplement
provider usage tracking. CodexBar is the provider engine. neon-codexbar is the
Linux KDE/Plasma integration layer that installs a Plasma widget, runs a user
daemon, reads normalized CodexBar output, and renders it in the panel.

This is also not PlasmaCodexBar. PlasmaCodexBar is a separate Plasma widget
inspired by CodexBar for macOS. neon-codexbar is specifically an adapter for
the CodexBar CLI/provider engine.

Current support target:

- KDE Neon first.
- KDE Plasma 6 desktops next.
- Wayland and X11 are both acceptable as long as Plasma 6 and plasmoids work.
- Other Linux desktops are out of scope for this repo unless a separate UI
  layer is added later.

Long term, the goal is boring and practical: keep CodexBar provider/auth logic
in CodexBar, keep Linux desktop presentation here, and avoid duplicating
provider-specific scraping or API behavior in the widget.

## Current Status

- Python daemon fetches enabled CodexBar providers.
- Plasma popup renders multiple provider cards.
- Settings page supports provider order, provider visibility, selected tray
  provider, and tray icon style.
- Popup has Refresh and Configure buttons.
- Runner preserves CodexBar JSON provider errors even when the CLI exits
  nonzero, so setup/auth failures reach the widget instead of a generic error.
- Compact tray icon supports:
  - percent in ring
  - percent only
  - provider window bars
  - provider window circles
  - provider window tiles

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
- optional auth file referenced by a user-service drop-in:
  `~/.config/neon-codexbar/auth.env`

`~/.codexbar/` belongs to CodexBar and is not managed by neon-codexbar.

Optional daemon settings in `~/.config/neon-codexbar/config.json` are
`codexbar_path` and `refresh_interval_seconds` (default: 300). Display settings
belong to the Plasma widget's settings page. Legacy Python display settings
are ignored; they never affected the widget.

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
python3 -m venv .venv
.venv/bin/python -m pip install -e '.[dev]'
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

The daemon refreshes providers on its configured interval. The popup and
settings page call `neon-codexbar refresh`, which creates the daemon's refresh
sentinel. `SIGUSR1` remains available for scripts.

Measured on this machine:

- Codex CLI source: about 2 seconds
- Claude OAuth source: about 2 seconds
- z.ai API source: under 1 second
- full daemon tick: usually under 3 seconds when all enabled providers use
  Codex/OAuth/API sources

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

## CodexBar Release Notes

Latest locally validated upstream release: CodexBar `v0.50.0`.

`v0.50.0` is validated with Grok's `auto` source on Linux. That path lets the
installed Grok CLI refresh its short-lived OAuth token, then falls back to
CodexBar's token-authenticated billing request when the CLI billing RPC is not
available.

`v0.25.1` first mattered on Linux because the standalone CLI archives included the
`VERSION` file, so `codexbar --version` reports the release tag instead of
`CodexBar unknown`.

`v0.25` expanded the provider inventory and added features that are useful for
neon-codexbar:

- New providers: `manus`, `mimo`, `doubao`, `commandcode`, `stepfun`, `crof`,
  `venice`, and `openai` API balance support.
- Provider improvements: MiniMax multi-service quota cards, Antigravity OAuth
  fetching, Factory/Droid billing windows, OpenRouter/Mistral/Kimi K2 balance
  text, Gemini CLI auth fixes, Vertex AI credential detection, and DeepSeek
  balance display fixes.
- Usage metadata: session pace indicators and quota warning metadata.
- CLI features worth evaluating here: `codexbar cost --format json`,
  `codexbar usage --status --format json`, `--json-only`, and the provider
  balance/pace fields.

The Linux source policy intentionally remains conservative. A provider is only
added to `src/neon_codexbar/adapter/source_policy.py` after a Linux-safe source
is validated and a sanitized fixture is captured. `auto` is allowed only when
that exact provider fallback chain has been validated. Most browser-cookie/web
providers are still macOS-only in upstream CodexBar, so adding them here without
validation would just generate prettier errors.

# neon-codexbar — Project Plan

A KDE Plasma 6 system tray application for monitoring AI provider usage on Linux.

This document is the complete build spec. Hand it to an implementation agent. Each phase has explicit acceptance criteria.

---

## 1. What this is

`neon-codexbar` is a Linux-native (KDE Plasma 6 / Wayland) systray widget plus a Python backend daemon. It surfaces real-time usage limits across many AI providers (Claude, Codex, z.ai, OpenRouter, OpenCode, etc.) via:

1. **The vendored `codexbar` CLI binary** (steipete/CodexBar) for the providers it supports on Linux.
2. **Native Python provider modules** for providers `codexbar` does not yet support on Linux (e.g. OpenCode).

To the end user, neon-codexbar appears as a single integrated app. The fact that `codexbar` is invoked under the hood is an implementation detail. License attribution is documented in `NOTICE` and the About dialog, but the user-facing brand is **neon-codexbar**.

## 2. Goals & non-goals

**Goals**
- Plasma 6 systray widget that works on Wayland (KDE Neon).
- Multi-provider usage display with session/weekly/credits windows.
- Zero hand-coding for any provider already supported by `codexbar` CLI on Linux.
- Plugin architecture for custom providers.
- Clean secrets management — secrets do not leak into the user's session env.
- Backend in **Python 3.10+** (intentional — for maintainability by a Python-first developer).
- MIT licensed, with full attribution to upstream `codexbar`.

**Non-goals**
- macOS or Windows support.
- Replicating every `codexbar` macOS feature (web cookie scraping, WidgetKit, etc.).
- Modifying the upstream `codexbar` source code (we vendor the binary, we don't fork it).
- Supporting providers that `codexbar` declares macOS-only (Cursor, Factory, Augment, Amp, etc.).

## 3. Architecture

```
┌──────────────────────────────────────────────────────────────┐
│  KDE Plasma 6 Panel                                          │
│  ┌─────────────────────────────────────────────────────┐     │
│  │  neon-codexbar Plasmoid (QML)                       │     │
│  │  - Panel icon (color-coded ring)                    │     │
│  │  - Popup: one card per provider                     │     │
│  │  - Settings dialog                                  │     │
│  └─────────────────────────────┬───────────────────────┘     │
└────────────────────────────────┼─────────────────────────────┘
                                 │ reads snapshot.json
                                 │ (atomic file watch)
                                 ▼
┌──────────────────────────────────────────────────────────────┐
│  neon-codexbar-daemon  (Python, systemd --user service)      │
│  ┌─────────────────────────────────────────────────────┐     │
│  │  Provider Registry                                  │     │
│  │  ┌──────────────────────────────────────────────┐   │     │
│  │  │  CodexBarCLIProvider  (one instance per      │   │     │
│  │  │  codexbar-supported provider on Linux)       │   │     │
│  │  └──────────────────────────────────────────────┘   │     │
│  │  ┌──────────────────────────────────────────────┐   │     │
│  │  │  Custom providers (OpenCodeProvider, …)      │   │     │
│  │  └──────────────────────────────────────────────┘   │     │
│  └─────────────────────────────┬───────────────────────┘     │
│                                ▼                             │
│              Normalizer → ProviderSnapshot                   │
│                                ▼                             │
│              Aggregator + atomic snapshot writer             │
└──────────────────────────────────────────────────────────────┘
                                 │
                                 ▼
┌──────────────────────────────────────────────────────────────┐
│  External resources                                          │
│  - /usr/local/bin/codexbar              (vendored binary)    │
│  - ~/.config/neon-codexbar/secrets.json (mode 600)           │
│  - ~/.config/neon-codexbar/config.json                       │
│  - ~/.cache/neon-codexbar/snapshot.json (daemon → widget)    │
│  - ~/.local/share/opencode/             (OpenCode logs)      │
└──────────────────────────────────────────────────────────────┘
```

**Key design choices**
- **File-watching IPC** between daemon and widget for v1. Simple, no D-Bus complexity. Migrate to D-Bus only if file-watching causes real problems.
- **Daemon-based** so the widget can be cheap and synchronous. Daemon does all I/O.
- **One subprocess per provider per refresh** to `codexbar` CLI. No batching — `--provider all` errors on Linux because of `--source auto` defaults.

## 4. Repository layout

```
neon-codexbar/
├── README.md                        # quick start
├── LICENSE                          # MIT
├── NOTICE                           # third-party attribution (codexbar, etc.)
├── CHANGELOG.md
├── pyproject.toml                   # hatchling build, console scripts
├── docs/
│   ├── ARCHITECTURE.md              # detailed design (this doc, refined)
│   ├── PROVIDERS.md                 # every supported provider + how to enable
│   ├── ADDING_PROVIDERS.md          # how to write a custom provider plugin
│   └── ATTRIBUTION.md               # codexbar credits + license text
├── packaging/
│   ├── install.sh                   # combined installer
│   ├── uninstall.sh
│   ├── neon-codexbar.service        # systemd --user unit
│   └── debian/                      # future .deb packaging
├── plasmoid/
│   ├── metadata.json
│   ├── contents/
│   │   ├── ui/
│   │   │   ├── main.qml
│   │   │   ├── CompactRepresentation.qml   # panel icon
│   │   │   ├── FullRepresentation.qml      # popup
│   │   │   ├── ProviderCard.qml
│   │   │   ├── UsageBar.qml
│   │   │   └── ConfigGeneral.qml
│   │   └── config/
│   │       ├── main.xml
│   │       └── config.qml
│   └── translations/
├── src/
│   └── neon_codexbar/
│       ├── __init__.py
│       ├── __main__.py              # `python -m neon_codexbar`
│       ├── cli.py                   # `neon-codexbar` user-facing command
│       ├── daemon.py                # `neon-codexbar-daemon` long-running service
│       ├── models.py                # ProviderSnapshot, UsageWindow, CreditInfo
│       ├── normalizer.py            # codexbar JSON → ProviderSnapshot
│       ├── config.py                # config.json read/write
│       ├── secrets.py               # secrets.json read/write
│       ├── ipc/
│       │   └── snapshot_writer.py   # atomic writes to snapshot.json
│       ├── providers/
│       │   ├── __init__.py
│       │   ├── base.py              # Provider abstract class
│       │   ├── registry.py          # discovery + registration
│       │   ├── codexbar.py          # CodexBarCLIProvider
│       │   └── opencode.py          # custom OpenCode provider
│       └── codexbar_runtime/
│           ├── installer.py         # downloads/verifies codexbar binary
│           ├── catalog.py           # known codexbar providers + sources
│           └── runner.py            # subprocess wrapper
├── vendor/
│   └── codexbar/
│       ├── README.md                # why vendored, how versioned
│       └── version.txt              # pinned version + sha256
└── tests/
    ├── unit/
    │   ├── test_normalizer.py
    │   ├── test_codexbar_provider.py
    │   ├── test_secrets.py
    │   └── fixtures/                # golden JSON samples
    └── integration/
        └── test_daemon_lifecycle.py
```

## 5. Licensing & attribution

- **Project license:** MIT (chosen for compatibility with upstream `codexbar`).
- **`codexbar` binary:** NOT bundled in the source repo. Downloaded at install time from `github.com/steipete/CodexBar/releases`. Version pinned in `vendor/codexbar/version.txt` with SHA-256 checksum.
- **`NOTICE` file** lists:
  - `codexbar` — MIT, Peter Steinberger, https://github.com/steipete/CodexBar
  - Any other third-party components.
- **About dialog** in widget: "Powered by codexbar (MIT, © Peter Steinberger). neon-codexbar is an independent project, not affiliated with or endorsed by Anthropic, OpenAI, or codexbar's authors."
- **README** clearly states `codexbar` is a runtime dependency that's auto-installed.
- **Do not strip `codexbar` branding from the binary.** When `neon-codexbar --version` is run, it should print both versions (`neon-codexbar X.Y.Z`, then a line listing the vendored `codexbar` version).

## 6. Prerequisites (runtime)

- KDE Plasma 6
- Wayland session (X11 should also work, but Wayland is the target)
- Python 3.10+
- `pip` and `python3-venv`
- `kpackagetool6`
- `systemd` (for `--user` service)
- `curl` and `tar` (for installer)
- 64-bit x86_64 or aarch64 Linux (codexbar binary platforms)

Optional, per provider:
- `claude` CLI authenticated → enables Claude
- `codex` CLI authenticated → enables Codex
- `gemini` CLI authenticated → enables Gemini
- API tokens stored via `neon-codexbar add-secret` → enables z.ai, OpenRouter, Kimi K2, Copilot

## 7. codexbar CLI integration layer

This is the heart of the system. All `codexbar` interaction goes through `src/neon_codexbar/codexbar_runtime/`.

### 7.1 Installation
- `codexbar_runtime/installer.py` exposes `ensure_installed()`:
  - Looks for `codexbar` in PATH.
  - If found and version matches `vendor/codexbar/version.txt`: done.
  - If missing or version mismatch: downloads tarball from GitHub Releases for the host arch, verifies SHA-256, installs to `~/.local/bin/codexbar`.
- Triggered by `neon-codexbar install-runtime` and by the daemon at startup.
- Failure modes: network down, checksum mismatch, unsupported arch — all surface clear errors.

### 7.2 Invocation contract
- One subprocess per provider per refresh cycle.
- Always pass:
  - `--provider <id>`
  - `--source <type>` (never default — defaults to `auto` which fails on Linux)
  - `--format json`
- Inject only the env vars the specific provider needs, from `secrets.json`. Do not pass through the user's full env.
- 10-second timeout per call.
- stderr captured for diagnostics; surfaced to the daemon log, never to the widget.

### 7.3 Provider catalog
`codexbar_runtime/catalog.py` is a hand-maintained registry of `codexbar` providers known to work on Linux:

```python
CODEXBAR_PROVIDERS = {
    "codex":      {"source": "cli",  "secrets_required": []},
    "claude":     {"source": "cli",  "secrets_required": []},
    "zai":        {"source": "api",  "secrets_required": ["Z_AI_API_KEY"]},
    "openrouter": {"source": "api",  "secrets_required": ["OPENROUTER_API_KEY"]},
    "kimik2":     {"source": "api",  "secrets_required": ["KIMI_K2_API_KEY"]},
    "gemini":     {"source": "api",  "secrets_required": []},  # OAuth via gemini CLI
    "copilot":    {"source": "api",  "secrets_required": ["COPILOT_API_TOKEN"]},
    # add new providers here as steipete adds Linux support upstream
}
```

When upstream `codexbar` adds a new Linux-compatible provider, the only change needed in neon-codexbar is one entry in this dict.

### 7.4 Auto-discovery
`neon-codexbar discover` runs every entry in the catalog with current secrets, and reports:
- Which providers returned valid usage data.
- Which returned auth errors (provider exists but not configured).
- Which returned "not supported on Linux".

Results saved to `~/.cache/neon-codexbar/discovery.json`. Widget shows only "available" providers by default; user can re-enable disabled ones from settings.

## 8. Custom provider plugin system

### 8.1 Provider abstract base (`providers/base.py`)
```python
@dataclass
class ProviderInfo:
    id: str
    display_name: str
    branding_color: str | None = None
    dashboard_url: str | None = None

class Provider(ABC):
    info: ProviderInfo

    @abstractmethod
    def is_available(self) -> bool:
        """Return True if this provider can be queried right now."""

    @abstractmethod
    def fetch(self) -> ProviderSnapshot:
        """Fetch current usage. Raise ProviderError on failure."""

    def secrets_required(self) -> list[str]:
        return []
```

### 8.2 Registry (`providers/registry.py`)
- Imports every module in `providers/` package.
- Each module registers its provider class via a `@register_provider` decorator.
- Registry exposes `list_providers()`, `get_provider(id)`.

### 8.3 First custom provider — OpenCode

**Research spike required before implementation.** Open questions:
- Where does OpenCode write logs? (likely `~/.local/share/opencode/`)
- What's the JSONL session format?
- Does it expose any usage/quota API?

Once answered, implement `providers/opencode.py`:
- Reads OpenCode session JSONL files modified within the last 7 days.
- Aggregates input + output tokens.
- Computes 5-hour and 7-day usage windows from session timestamps.
- Returns a `ProviderSnapshot` with `primary` (5h) and `secondary` (7d).
- No external secrets needed (local file parsing only).

## 9. Data normalization

### 9.1 Models (`models.py`)
```python
@dataclass
class UsageWindow:
    used_percent: float
    resets_at: datetime | None
    window_minutes: int | None
    label: str  # human-readable, e.g. "Session", "Weekly", "5-hour"

@dataclass
class CreditInfo:
    balance: float | None
    total: float | None
    used_percent: float | None
    currency: str = "USD"

@dataclass
class ProviderSnapshot:
    provider_id: str
    display_name: str
    is_connected: bool
    error_message: str | None
    primary: UsageWindow | None
    secondary: UsageWindow | None
    tertiary: UsageWindow | None      # third window (z.ai uses this)
    credits: CreditInfo | None
    identity: dict
    last_update: datetime
    source: str                       # "codexbar:cli", "opencode:local", etc.
```

### 9.2 codexbar JSON → ProviderSnapshot mapping
- `provider`, `usage.primary/secondary/tertiary`, `credits`, `identity`, `updatedAt` map directly.
- **Window-label override map** in `normalizer.py` per provider — e.g. for z.ai, `primary.label = "Weekly"`, `tertiary.label = "5-hour"`. Fixes the labeling quirk seen in jjlinares' widget.
- Defensive parsing: every field optional, never throws on malformed JSON.

### 9.3 Golden test fixtures
- One real JSON sample per supported provider in `tests/unit/fixtures/`.
- `test_normalizer.py` runs each through the normalizer and asserts the resulting `ProviderSnapshot`.

## 10. Secrets management

### 10.1 Storage
- `~/.config/neon-codexbar/secrets.json`, mode `0600`.
- Schema:
  ```json
  {
    "version": 1,
    "providers": {
      "zai":        { "Z_AI_API_KEY":      "..." },
      "openrouter": { "OPENROUTER_API_KEY": "..." }
    }
  }
  ```
- **Never** stored in `~/.config/plasma-workspace/env/` — that file leaks the value to every app the user runs.

### 10.2 Access
- `secrets.py` is the only module allowed to read the file.
- The codexbar runner asks `secrets.py` for the env dict it needs, gets a freshly-built dict containing only the relevant vars, and passes it to `subprocess.run(env=...)`.
- Secrets never logged. Redacted in `--debug` output.

### 10.3 CLI surface
```
neon-codexbar add-secret <provider> <env_var> [--from-stdin | --prompt]
neon-codexbar list-secrets                # prints redacted (last 4 chars only)
neon-codexbar remove-secret <provider> <env_var>
```

### 10.4 Future v2: KWallet
- Document the desired interface in `secrets.py` so `JSONFileBackend` can be swapped for `KWalletBackend` without touching call sites.
- Defer implementation to v2.

## 11. Configuration

### 11.1 Config file
`~/.config/neon-codexbar/config.json`:
```json
{
  "version": 1,
  "refresh_interval_seconds": 300,
  "warning_threshold_percent": 70,
  "critical_threshold_percent": 90,
  "enabled_providers": ["codex", "claude", "zai", "openrouter", "opencode"],
  "provider_overrides": {
    "zai": {
      "primary_label": "Weekly",
      "tertiary_label": "5-hour"
    }
  }
}
```

### 11.2 CLI surface
```
neon-codexbar config show
neon-codexbar config set <key> <value>
neon-codexbar enable-provider <id>
neon-codexbar disable-provider <id>
```

### 11.3 Widget settings UI
- Refresh interval (presets: 1m, 2m, 5m, 15m, manual).
- Warning + critical thresholds.
- Per-provider toggles (driven by discovery results).
- Reorder providers (drag-and-drop optional, defer if QML drag is hard).

## 12. Backend daemon

### 12.1 Lifecycle
- Long-running Python process.
- Started by `systemd --user` service unit `neon-codexbar.service`.
- Logs to journald (`journalctl --user -u neon-codexbar`).

### 12.2 Refresh loop
- Every `refresh_interval_seconds`:
  1. For each enabled provider, call `provider.fetch()` in a thread pool (max 8 concurrent).
  2. Collect `ProviderSnapshot` results (or error placeholders).
  3. Atomic-write all snapshots into `~/.cache/neon-codexbar/snapshot.json` (write to `.tmp`, then rename).
- On startup, immediate refresh (don't wait for first interval).
- Manual refresh via SIGUSR1 or via writing a sentinel file (widget triggers this).

### 12.3 systemd unit (`packaging/neon-codexbar.service`)
```ini
[Unit]
Description=neon-codexbar daemon
After=plasma-plasmashell.service

[Service]
Type=simple
ExecStart=%h/.local/bin/neon-codexbar-daemon
Restart=on-failure
RestartSec=5

[Install]
WantedBy=default.target
```

## 13. KDE Plasmoid (frontend)

### 13.1 Package metadata
- Plugin ID: `org.jeremywindsor.neon-codexbar` (or your namespace; not `com.codexbar.*`).
- Name: "neon-codexbar".
- Author/license fields filled.
- Category: `System Information` or `Utilities`.

### 13.2 QML structure
- `main.qml` — entry point, loads compact + full representations.
- `CompactRepresentation.qml` — panel icon. Color-coded ring based on max usage across all enabled providers.
- `FullRepresentation.qml` — popup. Header with refresh button + settings cog. Scrollable list of `ProviderCard`.
- `ProviderCard.qml` — provider icon, name, usage bars (primary/secondary, tertiary if present), reset countdown, dashboard link.
- `UsageBar.qml` — color-coded based on thresholds from config.
- `ConfigGeneral.qml` — settings dialog.

### 13.3 Data binding
- A `FileWatcher` (or `QFileSystemWatcher` from a Plasma data engine) watches `~/.cache/neon-codexbar/snapshot.json`.
- On change, parse and bind to a ListModel feeding the cards.
- No direct `subprocess`/`Process` calls from QML. Daemon is the only thing that runs subprocesses.

### 13.4 Theming
- All colors from `PlasmaCore.Theme`.
- Test in dark + light Plasma themes.

## 14. Build & packaging

### 14.1 Plasmoid
- `kpackagetool6 -t Plasma/Applet -i plasmoid/`
- Reinstall: `kpackagetool6 -t Plasma/Applet -u plasmoid/`
- Uninstall: `kpackagetool6 -t Plasma/Applet -r org.jeremywindsor.neon-codexbar`

### 14.2 Python package
- `pyproject.toml` with hatchling.
- Console scripts:
  - `neon-codexbar` → `neon_codexbar.cli:main`
  - `neon-codexbar-daemon` → `neon_codexbar.daemon:main`
- Install: `pip install --user .`

### 14.3 Combined installer (`packaging/install.sh`)
Steps in order:
1. Verify Plasma 6 (`plasmashell --version`) and Python 3.10+.
2. `pip install --user .`
3. `neon-codexbar install-runtime` (downloads `codexbar` binary if missing).
4. `kpackagetool6 -t Plasma/Applet -i plasmoid/`
5. Install systemd unit to `~/.config/systemd/user/`.
6. `systemctl --user daemon-reload`
7. `systemctl --user enable --now neon-codexbar.service`
8. Print "Add the neon-codexbar widget to your panel: right-click panel → Add Widgets → search 'neon-codexbar'".

`uninstall.sh` reverses all of the above.

### 14.4 Future distribution
- AUR package (deferred).
- KDE Store submission (deferred).
- `.deb` for KDE Neon (deferred — `packaging/debian/` scaffold only).

## 15. Testing

### 15.1 Unit tests (`tests/unit/`)
- `test_normalizer.py` — golden JSON inputs from `fixtures/` → expected `ProviderSnapshot`.
- `test_codexbar_provider.py` — mock `subprocess.run`, verify correct flags, env, and parsing.
- `test_secrets.py` — read/write/redact.
- `test_config.py` — schema validation + defaults.

### 15.2 Integration tests (`tests/integration/`)
- Spin up the daemon in a tempdir, run two refresh cycles, verify `snapshot.json` is written and well-formed.
- Optional: real `codexbar` binary against a stub provider account (skipped in CI without credentials).

### 15.3 Widget verification
- Manual checklist in `docs/QA.md`: dark theme, light theme, 0% / 50% / 95% usage, error state, no providers enabled, narrow panel, vertical panel.

## 16. Documentation

- `README.md` — installation, what it does, screenshot, license.
- `docs/ARCHITECTURE.md` — this plan, refined as code lands.
- `docs/PROVIDERS.md` — every supported provider, how to enable it, what secrets it needs.
- `docs/ADDING_PROVIDERS.md` — step-by-step guide for writing a custom Python provider.
- `docs/ATTRIBUTION.md` — full credit to upstream `codexbar`, MIT license text.
- `CHANGELOG.md` — kept current per release.

## 17. Future-proofing for new codexbar providers

When steipete adds a new provider to `codexbar` that works on Linux:

1. Update `vendor/codexbar/version.txt` to the new version + sha.
2. Add an entry to `CODEXBAR_PROVIDERS` in `codexbar_runtime/catalog.py`.
3. (Optional) Add a window-label override in `normalizer.py` if the provider's window semantics need clarifying.
4. Bump neon-codexbar version, ship.

That's it. No QML changes, no widget rebuild needed.

If the agent is patient: write a follow-up issue to auto-discover providers from `codexbar config dump` so step 2 isn't manual either.

## 18. Phased delivery

Each phase has explicit acceptance criteria. The agent should not start a phase before the previous phase's criteria are met.

### Phase 1 — Skeleton + read-only POC
- Repo scaffolded as in section 4.
- `models.py`, `providers/base.py`, `providers/registry.py` complete.
- `codexbar_runtime/installer.py` + `runner.py` complete.
- `providers/codexbar.py` implemented for **codex + claude only**.
- `normalizer.py` handles those two.
- `neon-codexbar fetch --json` prints a JSON array of two `ProviderSnapshot` objects.
- Unit tests pass for normalizer with golden fixtures.
- **Acceptance:** running `neon-codexbar fetch --json` on a machine with `codexbar` and authenticated `codex`+`claude` CLIs prints valid usage data.

### Phase 2 — Daemon + IPC
- `daemon.py` implements the refresh loop.
- `ipc/snapshot_writer.py` does atomic writes.
- systemd unit file present.
- `neon-codexbar config` subcommand with show/set/enable-provider/disable-provider.
- **Acceptance:** `systemctl --user start neon-codexbar` runs the daemon, `~/.cache/neon-codexbar/snapshot.json` updates every N seconds, `journalctl --user -u neon-codexbar` shows clean logs.

### Phase 3 — Plasmoid v1
- Plasmoid package installs via `kpackagetool6`.
- Reads `snapshot.json` via `FileWatcher`.
- Renders cards for codex + claude.
- Panel icon shows color-coded ring based on max usage.
- Manual refresh button.
- **Acceptance:** widget on panel shows the same data as `neon-codexbar fetch`. Panel icon color tracks usage.

### Phase 4 — Provider expansion
- `CODEXBAR_PROVIDERS` catalog populated for: zai, openrouter, kimik2, gemini, copilot.
- Window-label overrides in normalizer for z.ai.
- `neon-codexbar add-secret` / `list-secrets` / `remove-secret` commands.
- Discovery command (`neon-codexbar discover`).
- **Acceptance:** with secrets configured, all six providers above show in widget with correct labels.

### Phase 5 — Custom OpenCode provider
- Research spike: document OpenCode's log format in `docs/PROVIDERS.md`.
- `providers/opencode.py` reads logs, computes 5h + 7d windows.
- Tests with synthetic log fixtures.
- **Acceptance:** OpenCode card appears in widget when OpenCode has been used recently.

### Phase 6 — Polish
- Settings UI in plasmoid (`ConfigGeneral.qml`).
- Configurable thresholds with live preview.
- About dialog with codexbar attribution.
- Per-provider show/hide toggles in widget.
- README screenshots.
- **Acceptance:** non-developer user can install, configure, and use the widget without reading code.

### Phase 7 — Distribution prep
- `install.sh` and `uninstall.sh` polished.
- `.desktop` file for app menu entry.
- Tag v0.1.0 release.
- **Acceptance:** clean VM install via `install.sh` results in a working widget on the panel.

## 19. Open questions for the agent

These need resolution before the relevant phase begins:

1. **OpenCode log format** — research spike at start of Phase 5.
2. **Plasmoid file-watching** — confirm Plasma 6 has a usable `FileWatcher` QML element. If not, fall back to a `Plasma5Support.DataSource` polling at 5s.
3. **Daemon vs. on-demand fetch** — confirm the daemon model is acceptable. Alternative: widget invokes `neon-codexbar fetch` directly every refresh interval. Tradeoff: simpler architecture, more startup cost per refresh.
4. **Provider auto-discovery scope** — should the catalog be hand-maintained (current plan) or should `neon-codexbar` parse `codexbar config dump` to auto-populate? Defer to Phase 4 review.
5. **Internationalization** — defer to v2 unless the user asks.

## 20. Risks & mitigations

| Risk | Mitigation |
|---|---|
| `codexbar` JSON schema changes between versions | Pin version + checksum; integration tests run against the pinned version; bump only when intentional |
| `codexbar` project abandoned | Vendoring strategy is binary-only; if upstream dies, neon-codexbar can fork or replace runtime gracefully |
| User upgrades `codexbar` outside neon-codexbar's control | `installer.py` checks version on each daemon start; warn if mismatch |
| Provider auto-discovery noisy (lots of unconfigured providers shown as errors) | Hide "auth error" providers by default; user opts in from settings |
| Secrets file readable by malware in user session | `chmod 600`; document KWallet roadmap; do not pass secrets through env to anything except the codexbar subprocess |
| File-watching IPC misses an update | Daemon also touches `snapshot.json` mtime even on no-change to wake watchers; if this proves unreliable, migrate to D-Bus signal |
| Widget shows stale data when daemon is dead | Plasmoid checks snapshot mtime; if older than `2 * refresh_interval`, dim icon and show "stale" badge |

## 21. Definition of done (v0.1.0)

- All Phase 1–6 acceptance criteria met.
- `pip install --user .` + `install.sh` produces a working install on a fresh KDE Neon VM.
- README has screenshot of the widget on a panel.
- LICENSE, NOTICE, ATTRIBUTION docs are correct.
- `neon-codexbar --version` prints both neon-codexbar and codexbar versions.
- All unit tests green; integration tests green when run with credentials.
- No upstream `codexbar` source is bundled or modified.

---

**Implementation order matters.** Do not skip phases. Each one builds on the last. If a phase's acceptance criteria can't be met, stop and surface the blocker rather than improvising.

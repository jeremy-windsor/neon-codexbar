# neon-codexbar — Project Plan

A KDE Plasma 6 system tray application for monitoring AI provider usage on Linux.

This document is the complete build spec. Hand it to an implementation agent. Each phase has explicit acceptance criteria.

---

## 1. Architectural principle

> **CodexBar owns providers. neon-codexbar owns KDE UX.**

Provider auth, quota endpoints, cookie handling, API parsing, and provider-specific logic belong in upstream `codexbar` (or a maintained fork). `neon-codexbar` is the Linux/KDE shell: install, configure, render, diagnose. If a provider is missing or broken on Linux, the fix goes upstream in Swift via `docs/provider.md` — not reimplemented in Python in this repo.

```
CodexBar / CodexBarCore       neon-codexbar
─────────────────────         ──────────────────────
providers, auth, fetch        widget, systray UX
config, cookies, parsing      install/bootstrap
CLI JSON output               source policy
                              rendering, diagnostics
```

## 2. Goals & non-goals

**Goals**
- Plasma 6 systray widget on Wayland (KDE Neon target).
- Render whatever `codexbar` CLI emits — quota windows, credits, balances, identity, errors.
- Auto-discover providers from `codexbar config dump`.
- Linux-safe source policy (never use the failing `--source auto` defaults).
- Clean install/uninstall.
- MIT licensed with full attribution to upstream `codexbar`.

**Non-goals**
- macOS / Windows support.
- Reimplementing any provider logic in Python.
- Storing provider secrets in our own config store.
- Supporting providers `codexbar` declares macOS-only until upstream adds Linux support.

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
                                 ▼
┌──────────────────────────────────────────────────────────────┐
│  neon-codexbar-daemon (Python, systemd --user)               │
│  ┌─────────────────────────────────────────────────────┐     │
│  │  CodexBar Adapter Layer                             │     │
│  │  - command construction                             │     │
│  │  - source policy enforcement                        │     │
│  │  - JSON parse → generic display blocks              │     │
│  │  - redacted diagnostics                             │     │
│  └─────────────────────────────┬───────────────────────┘     │
│                                ▼                             │
│              Aggregator + atomic snapshot writer             │
└──────────────────────────────────────────────────────────────┘
                                 │
                                 ▼
┌──────────────────────────────────────────────────────────────┐
│  External (managed by codexbar, NOT us)                      │
│  - codexbar binary (PATH or ~/.local/bin)                    │
│  - ~/.codexbar/config.json     (provider config + secrets)   │
│  - provider auth files (~/.codex, ~/.claude, etc.)           │
│  - env vars (Z_AI_API_KEY, OPENROUTER_API_KEY, etc.)         │
│                                                              │
│  Owned by us:                                                │
│  - ~/.config/neon-codexbar/config.json (UI prefs only)       │
│  - ~/.cache/neon-codexbar/snapshot.json (daemon → widget)    │
└──────────────────────────────────────────────────────────────┘
```

**Key design choices**
- File-watching IPC daemon → widget. Migrate to D-Bus only if file-watching proves unreliable.
- Daemon runs all subprocesses; QML never spawns processes.
- One subprocess per provider per refresh (no `--provider all`, fails on Linux).
- **No parallel secret store.** Use `~/.codexbar/config.json` + env vars (CodexBar's existing surface).

## 4. Repository layout

```
neon-codexbar/
├── README.md
├── LICENSE                          # MIT
├── NOTICE                           # third-party attribution (codexbar)
├── CHANGELOG.md
├── pyproject.toml
├── docs/
│   ├── ARCHITECTURE.md
│   ├── SOURCE_POLICY.md             # Linux source policy table
│   ├── ATTRIBUTION.md
│   └── TROUBLESHOOTING.md
├── packaging/
│   ├── install.sh
│   ├── uninstall.sh
│   └── neon-codexbar.service        # systemd --user unit
├── plasmoid/
│   ├── metadata.json
│   └── contents/
│       ├── ui/
│       │   ├── main.qml
│       │   ├── CompactRepresentation.qml
│       │   ├── FullRepresentation.qml
│       │   ├── ProviderCard.qml
│       │   ├── QuotaWindowBar.qml
│       │   ├── CreditMeter.qml
│       │   └── ConfigGeneral.qml
│       └── config/
│           ├── main.xml
│           └── config.qml
├── src/
│   └── neon_codexbar/
│       ├── __init__.py
│       ├── __main__.py
│       ├── cli.py                   # neon-codexbar
│       ├── daemon.py                # neon-codexbar-daemon
│       ├── models.py                # generic display blocks
│       ├── adapter/
│       │   ├── __init__.py
│       │   ├── runner.py            # subprocess wrapper
│       │   ├── discovery.py         # parse `codexbar config dump`
│       │   ├── source_policy.py     # Linux-safe source per provider
│       │   ├── installer.py         # ensure codexbar binary present
│       │   └── normalizer.py        # JSON → display blocks
│       ├── config.py                # OUR config (UI prefs only)
│       └── ipc/
│           └── snapshot_writer.py
└── tests/
    ├── unit/
    │   ├── test_normalizer.py
    │   ├── test_source_policy.py
    │   ├── test_discovery.py
    │   └── fixtures/                # golden JSON samples per provider
    └── integration/
        └── test_daemon_lifecycle.py
```

Note: no `secrets.py`, no `providers/` directory. Provider logic lives in CodexBar.

## 5. Licensing & attribution

- **Project license:** MIT.
- **`codexbar` binary:** not bundled in source. Downloaded at install time from `github.com/steipete/CodexBar/releases`. Version pinned with SHA-256.
- **`NOTICE`:** lists `codexbar` (MIT, Peter Steinberger).
- **About dialog:** "neon-codexbar is a KDE/Plasma frontend powered by the CodexBar CLI provider engine. Powered by codexbar (MIT, © Peter Steinberger). Independent project, not affiliated with or endorsed by Anthropic, OpenAI, or codexbar's authors."
- **Do not strip codexbar branding.** `neon-codexbar --version` prints both versions.

## 6. Prerequisites

- KDE Plasma 6, Wayland session (X11 should also work)
- Python >=3.11, pip, python3-venv
- `kpackagetool6`, `systemd --user`, `curl`, `tar`
- 64-bit x86_64 or aarch64 Linux

Per-provider auth is the user's responsibility (or codexbar's), not ours:
- `claude` / `codex` / `gemini` CLIs authenticated → those providers light up
- API tokens set in `~/.codexbar/config.json` or supported env vars → API providers light up

## 7. CodexBar adapter layer

### 7.1 Binary management (`adapter/installer.py`)
- `ensure_installed()` checks PATH for `codexbar`. If missing or version mismatch with `vendor/codexbar/version.txt`, downloads tarball, verifies SHA-256, installs to `~/.local/bin/codexbar`.
- Surfaces clear errors for: network down, checksum mismatch, unsupported arch.

### 7.2 Invocation contract (`adapter/runner.py`)
- One subprocess per provider per refresh.
- Always pass `--provider <id> --source <type> --format json`. Never default `--source`.
- Pass through env vars CodexBar supports (`Z_AI_API_KEY`, `OPENROUTER_API_KEY`, etc.). Do **not** invent our own env-var names.
- 10s timeout per call. stderr captured for diagnostics; never surfaced to widget.

### 7.3 Provider discovery (`adapter/discovery.py`)
- Calls `codexbar config dump --format json`.
- Yields the list of provider IDs CodexBar knows about.
- No hardcoded list in our repo. When CodexBar adds a provider, we pick it up automatically.

### 7.4 Source policy (`adapter/source_policy.py`)
Linux source defaults are unreliable. We maintain a small policy table mapping provider ID → preferred source on Linux. Initial table:

| Provider | Linux source | Notes |
|---|---|---|
| codex | `cli` | tested working |
| claude | `cli` | tested working |
| zai | `api` | tested working with `Z_AI_API_KEY` |
| openrouter | `api` | tested working with `OPENROUTER_API_KEY` |
| kimik2 | `api` | needs token test |
| gemini | `api` | needs gemini CLI auth test |
| copilot | `api` | needs device-flow test |
| kilo | `api` w/ CLI fallback | needs auth test |
| (others) | omit until validated |

Unknown providers from discovery default to "skip + show in diagnostics," not "guess at source."

### 7.5 Normalizer (`adapter/normalizer.py`)
**Generic, no hardcoded window meanings.** Maps CodexBar JSON to display blocks. The renderer shows whatever exists with the labels CodexBar provides.

## 8. Display block model (`models.py`)

```python
@dataclass
class QuotaWindow:
    used_percent: float
    resets_at: datetime | None
    window_label: str | None      # from CodexBar; e.g. "5 hours window"
    window_minutes: int | None

@dataclass
class CreditMeter:
    label: str                    # "Balance" / "Total Credits" / etc.
    used: float | None
    total: float | None
    used_percent: float | None
    currency: str | None

@dataclass
class ProviderCard:
    provider_id: str
    display_name: str             # from discovery
    source: str                   # which source produced the data
    version: str | None
    plan: str | None
    identity: dict
    quota_windows: list[QuotaWindow]   # 0..N, in CodexBar order
    credit_meters: list[CreditMeter]   # 0..N
    model_usage: list[dict]
    error_message: str | None
    setup_hint: str | None
    is_stale: bool
    last_update: datetime
```

The renderer does not assume Session/Weekly. It draws each `QuotaWindow` and `CreditMeter` with its given label.

## 9. Configuration (ours, UI only)

`~/.config/neon-codexbar/config.json`:
```json
{
  "version": 1,
  "refresh_interval_seconds": 300,
  "warning_threshold_percent": 70,
  "critical_threshold_percent": 90,
  "provider_display_mode": "enabled-only",
  "provider_overrides": {
    "zai": { "display_name": "Z.ai (GLM)" }
  }
}
```

`provider_display_mode`: `enabled-only` | `all-configured` | `debug-all`.

**No secrets here.** API keys live where CodexBar already reads them.

CLI surface:
```
neon-codexbar config show
neon-codexbar config set <key> <value>
neon-codexbar discover         # runs `codexbar config dump` + source policy probe
neon-codexbar diagnose         # redacted dump for troubleshooting
neon-codexbar fetch [--json]   # one-shot fetch
neon-codexbar install-runtime  # ensure codexbar binary
```

## 10. Backend daemon

### 10.1 Lifecycle
- Long-running Python process.
- `systemd --user` unit `neon-codexbar.service`.
- Logs to journald: `journalctl --user -u neon-codexbar`.

### 10.2 Refresh loop
- Every `refresh_interval_seconds`:
  1. For each enabled provider, call `runner.fetch(provider_id, source)` in a thread pool (max 8 concurrent).
  2. Normalize each result to a `ProviderCard`.
  3. Atomic-write all cards into `~/.cache/neon-codexbar/snapshot.json` (write `.tmp` then rename).
- Immediate refresh on startup.
- Manual refresh: SIGUSR1 or sentinel file (widget triggers via touch).
- Stale detection: if a fetch hasn't succeeded in `2 * refresh_interval`, mark `is_stale=true`.

### 10.3 systemd unit
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

## 11. KDE Plasmoid (frontend)

### 11.1 Package metadata
- Plugin ID: `org.jeremywindsor.neon-codexbar`
- Name: "neon-codexbar"
- Category: `System Information`

### 11.2 QML components
- `main.qml` — entry point.
- `CompactRepresentation.qml` — panel icon. Color-coded ring: green/yellow/red based on max `used_percent` across all visible quota windows + credit meters.
- `FullRepresentation.qml` — popup. Refresh button + settings cog. Scrollable provider cards.
- `ProviderCard.qml` — renders a `ProviderCard` model: icon, name, plan, dynamic list of quota bars, dynamic list of credit meters, error/setup hints.
- `QuotaWindowBar.qml` — single quota window.
- `CreditMeter.qml` — single credit/balance.
- `ConfigGeneral.qml` — settings.

### 11.3 Data binding
- `FileWatcher` (or `Plasma5Support.DataSource` polling at 5s if `FileWatcher` proves unreliable on Plasma 6) watches `snapshot.json`.
- On change, parse → ListModel → cards.
- Widget never spawns subprocesses.

### 11.4 Theming
- All colors from `PlasmaCore.Theme`. Test dark + light.

## 12. Build & packaging

### 12.1 Plasmoid
- Install: `kpackagetool6 -t Plasma/Applet -i plasmoid/`
- Update: `kpackagetool6 -t Plasma/Applet -u plasmoid/`
- Uninstall: `kpackagetool6 -t Plasma/Applet -r org.jeremywindsor.neon-codexbar`

### 12.2 Python package
- `pyproject.toml` with hatchling.
- Console scripts: `neon-codexbar`, `neon-codexbar-daemon`.
- Install: `pip install --user .`.

### 12.3 Combined installer (`packaging/install.sh`)
1. Verify Plasma 6 + Python >=3.11.
2. `pip install --user .`
3. `neon-codexbar install-runtime` (codexbar binary).
4. `kpackagetool6 -t Plasma/Applet -i plasmoid/`
5. Install systemd unit to `~/.config/systemd/user/`.
6. `systemctl --user daemon-reload && systemctl --user enable --now neon-codexbar.service`
7. Print: "Add the neon-codexbar widget: right-click panel → Add Widgets → search 'neon-codexbar'."

`uninstall.sh` reverses.

## 13. Testing

### 13.1 Unit tests
- `test_normalizer.py` — golden JSON fixtures (codex, claude, zai, openrouter, plus error cases) → expected `ProviderCard`.
- `test_source_policy.py` — provider ID → expected source.
- `test_discovery.py` — mock `codexbar config dump`, verify provider list extraction.
- `test_runner.py` — mock subprocess; verify flags, env, timeout, error handling.

### 13.2 Integration tests
- Daemon in tempdir, two refresh cycles, verify `snapshot.json` is well-formed.
- Optional: real `codexbar` binary against authenticated codex+claude (skipped without creds).

### 13.3 Widget verification
- Manual checklist in `docs/QA.md`: dark/light theme, 0% / 50% / 95% usage, error state, no providers, narrow panel, vertical panel, z.ai 3-window provider, OpenRouter credit-only provider.

## 14. Future-proofing

When CodexBar adds a Linux-supported provider:
1. Run `codexbar --version` → confirm pinned version supports it.
2. If new arch needed, bump `vendor/codexbar/version.txt`.
3. Add a row to `source_policy.py` if needed (or leave in default skip-list until validated).
4. (Maybe) add display-name override in `config.json`.

No QML changes. No widget rebuild. Discovery picks it up.

## 15. Phased delivery

### Phase 1 — Scaffold + adapter proof
- Repo scaffolded per section 4.
- `models.py`, `adapter/runner.py`, `adapter/installer.py`, `adapter/source_policy.py`, `adapter/normalizer.py` complete.
- `cli.py` exposes `fetch`, `discover`, `install-runtime`.
- Source policy implemented for codex, claude, zai, openrouter.
- Unit tests: normalizer + source_policy + golden fixtures green.
- **Acceptance:** `neon-codexbar fetch --json` returns valid `ProviderCard` JSON for the four tested providers on a machine with their auth in place.

### Phase 2 — Daemon + IPC
- `daemon.py` refresh loop.
- `ipc/snapshot_writer.py` atomic writes.
- systemd unit installed.
- Stale detection works.
- **Acceptance:** `systemctl --user start neon-codexbar` runs cleanly. `~/.cache/neon-codexbar/snapshot.json` updates every N seconds. `journalctl --user -u neon-codexbar` shows clean logs. Killing the daemon results in `is_stale=true` after 2× refresh interval.

### Phase 3 — Plasmoid v1 (generic renderer)
- Package installs via `kpackagetool6`.
- `FileWatcher` reads `snapshot.json`.
- `ProviderCard.qml` renders dynamic quota windows + credit meters (no Session/Weekly assumptions).
- Panel icon: color-coded ring on max usage.
- Manual refresh button (touches sentinel file).
- **Acceptance:** widget shows codex + claude (Session/Weekly), z.ai (three windows with their actual labels), OpenRouter (balance meter, no quota windows). All match `neon-codexbar fetch` output.

### Phase 4 — Discovery + provider expansion
- `adapter/discovery.py` calls `codexbar config dump`.
- `provider_display_mode: enabled-only` filters list.
- Source policy table extended (gemini, copilot, kimik2, kilo) with documented test results.
- `neon-codexbar diagnose` produces redacted dump.
- **Acceptance:** with relevant auth in place, all working providers appear automatically. Diagnose output redacts secrets but shows source, exit code, error message per provider.

### Phase 5 — UX polish
- `ConfigGeneral.qml` settings UI: refresh interval, thresholds, display mode, per-provider show/hide.
- About dialog with codexbar attribution.
- README screenshots.
- Threshold-based notifications (optional, behind a toggle).
- **Acceptance:** non-developer can install, configure, and use without reading code.

### Phase 6 — Distribution
- `install.sh` / `uninstall.sh` polished and idempotent.
- `.desktop` file for app menu.
- Tag v0.1.0.
- **Acceptance:** clean KDE Neon VM → `install.sh` → working widget on panel.

## 16. Open questions

1. **Plasma 6 `FileWatcher`** — verify it exists and works. Fallback: `Plasma5Support.DataSource` polling at 5s.
2. **Daemon vs. on-demand** — daemon model is current plan. Alternative: widget runs `neon-codexbar fetch` on its own timer. Tradeoff: simpler, but ~10× more subprocess cost.
3. **`codexbar config dump` schema** — confirm the JSON shape exposes the provider list cleanly. If not, parse text output as a fallback.
4. **Error provider display** — in `enabled-only` mode, do error-state providers show or hide? Recommend: show only if explicitly enabled in CodexBar config.
5. **i18n** — defer to v0.2.

## 17. Risks & mitigations

| Risk | Mitigation |
|---|---|
| CodexBar JSON schema changes between versions | Pin version + sha; integration tests run against pinned version; bump only intentionally |
| `codexbar config dump` shape changes | Wrap parsing in adapter; one place to fix |
| CodexBar project abandonment | Vendoring is binary-only; codebase stays usable; can swap to fork |
| User upgrades codexbar outside our control | Daemon checks version on startup; warns on mismatch |
| Linux-broken provider sneaks into discovery | Default unknown providers to skip; require explicit source policy entry |
| File-watching IPC misses an update | Daemon also touches mtime on no-change; fallback to polling DataSource |
| Widget shows stale data when daemon dies | `is_stale=true` after 2× refresh; renderer dims + shows "stale" badge |
| Provider needs Linux fix that's not upstream yet | Document the upstream PR path; don't patch in our repo |

## 18. Definition of Done (v0.1.0)

- All Phase 1–5 acceptance criteria met.
- `pip install --user .` + `install.sh` produces a working install on a clean KDE Neon VM.
- README has screenshot of the widget on a panel.
- LICENSE, NOTICE, ATTRIBUTION docs correct.
- `neon-codexbar --version` prints both neon-codexbar and codexbar versions.
- All unit tests green; integration tests green where credentials available.
- No upstream codexbar source bundled or modified.
- No provider auth/parsing logic in `src/neon_codexbar/`.

---

**Implementation order matters. Do not skip phases. Each builds on the last. If acceptance criteria can't be met, stop and surface the blocker rather than improvise.**

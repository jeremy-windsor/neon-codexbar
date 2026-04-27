# Phase 3 — Plasmoid v1 Generic Renderer

Date opened: 2026-04-27
Status: planned

Build tracker for the Phase 3 deliverable from `plans/claude-neon-codexbar-plan.md` §15.

## Goal

Ship the first KDE Plasma 6 widget that reads the Phase 2 daemon snapshot and renders provider usage without knowing provider-specific semantics.

Phase 3 is UI only. The widget reads `~/.cache/neon-codexbar/snapshot.json`, watches for changes, renders provider cards, and can request a manual refresh by touching the daemon sentinel file. It does **not** spawn `codexbar`, read provider config, store secrets, parse provider auth, or run Python subprocesses.

## Phase 0–2 review summary

### Phase 0 — live CodexBar validation

Complete.

Evidence:

- CodexBar CLI validated on KDE Neon and sandbox.
- `codexbar config dump --format json` returns usable provider config.
- Raw provider fetches validated for:
  - `codex` via `cli`
  - `claude` via `cli`
  - `zai` via `api`
  - `openrouter` via `api`
- Linux source policy remains explicit. No `--source auto` guessing.

### Phase 1 — adapter proof

Complete.

Evidence:

- `neon-codexbar fetch/discover/diagnose` exist.
- Normalizer produces generic `ProviderCard` data.
- z.ai three-window output and OpenRouter credit/balance output are represented without hardcoding Session/Weekly assumptions.
- Secret redaction is in place.
- Current validation: `python3 -m ruff check .` passes; `python3 -m pytest` passes with 35 tests; `python3 -m neon_codexbar --version` reports `neon-codexbar 0.1.0 (codexbar CodexBar)`.

### Phase 2 — daemon + snapshot IPC

Complete after review fixes.

Evidence:

- `neon-codexbar-daemon` exists.
- `packaging/neon-codexbar.service` exists and stays secret-free.
- Snapshot writer does atomic temp-file + fsync + replace and mode `0600`.
- Snapshot contract documented in `docs/DAEMON_CONTRACT.md`.
- Must-fix GPT review findings were closed:
  - root `snapshot.ok` means global CodexBar health only
  - provider worker exceptions do not crash daemon
  - systemd auth story documented
  - CodexBar metadata cached
- Current validation: ruff clean, 35 tests passing, `diagnose --json` sees CodexBar at `/home/claude/.local/bin/CodexBarCLI`.

## Phase 3 acceptance criteria

From the master plan:

- [ ] Package installs via `kpackagetool6`.
- [ ] Widget reads `snapshot.json` via file watcher or polling fallback.
- [ ] `ProviderCard.qml` renders dynamic quota windows and credit meters.
- [ ] No UI code assumes Session/Weekly labels or exactly two windows.
- [ ] Panel icon color-coded ring reflects max usage across visible quota windows and credit meters.
- [ ] Manual refresh button touches the daemon sentinel file.
- [ ] Widget shows Codex + Claude quota windows, z.ai three windows, and OpenRouter balance meter matching the snapshot/fetch output.

## Non-goals for Phase 3

- No installer script polish beyond enough `kpackagetool6` commands to install/update manually.
- No settings UI beyond a placeholder if Plasma requires one.
- No provider enablement UI.
- No notifications.
- No screenshots/README marketing pass.
- No CodexBar auth work.
- No new provider support.
- No D-Bus unless Plasma file watching fails in testing.

## Contract to consume

Use `docs/DAEMON_CONTRACT.md` as the source of truth.

Default snapshot path:

```text
~/.cache/neon-codexbar/snapshot.json
```

Manual refresh sentinel:

```text
~/.cache/neon-codexbar/refresh.touch
```

Important semantic rules:

- `snapshot.ok=false` means CodexBar/global daemon setup is broken.
- `cards[i].error_message` means one provider is broken.
- `cards[i].is_stale=true` means one provider is stale while daemon is alive.
- The widget must compute daemon-dead staleness from `generated_at` or file mtime.
- `cards[]` is already sorted; do not re-sort.
- `quota_windows[]` order matters; render in given order.
- Ignore unknown fields for forward compatibility.

## Proposed file layout

```text
plasmoid/
├── metadata.json
└── contents/
    ├── ui/
    │   ├── main.qml
    │   ├── CompactRepresentation.qml
    │   ├── FullRepresentation.qml
    │   ├── ProviderCard.qml
    │   ├── QuotaWindowBar.qml
    │   ├── CreditMeter.qml
    │   ├── StatusBanner.qml
    │   └── SnapshotStore.qml
    └── config/
        ├── main.xml
        └── config.qml
```

`SnapshotStore.qml` owns file loading, parsing, watcher/polling fallback, derived state, and refresh sentinel touching. UI components receive plain properties/models.

## Component responsibilities

### `main.qml`

- Defines compact/full representation.
- Owns one `SnapshotStore` instance.
- Exposes derived state to compact/full components.

### `SnapshotStore.qml`

Responsibilities:

- Expand default paths using `$HOME`.
- Read `snapshot.json`.
- Parse JSON safely.
- Keep these properties:
  - `snapshotOk`
  - `codexbarAvailable`
  - `generatedAt`
  - `cards`
  - `diagnostics`
  - `readError`
  - `daemonDeadStale`
  - `maxUsagePercent`
  - `worstState` (`ok`, `warning`, `critical`, `error`, `stale`, `missing`)
- Watch the file if Plasma has a reliable file-watching primitive.
- Fall back to timer polling every 5 seconds if watcher is unavailable or flaky.
- Touch `refresh.touch` for manual refresh.

Implementation note: if QML cannot reliably touch/create files directly without ugly hacks, add a tiny helper command later. First try QML-native file I/O/watcher options on KDE Neon.

### `CompactRepresentation.qml`

- Shows a compact panel icon/ring.
- Color rules:
  - missing snapshot / `snapshot.ok=false`: error color
  - daemon-dead stale: muted/stale color
  - max usage >= critical threshold: critical color
  - max usage >= warning threshold: warning color
  - else: healthy color
- Tooltip includes summary: provider count, max usage, generated time/stale state.

Default thresholds for Phase 3 hardcoded in QML:

```text
warning: 70%
critical: 90%
```

Real configurable thresholds belong in Phase 5.

### `FullRepresentation.qml`

- Header: title, generated timestamp, refresh button, global status.
- Shows global setup banner if snapshot missing or `snapshot.ok=false`.
- Shows daemon-dead stale banner if snapshot age is too old.
- Scrollable list of provider cards.
- Diagnostics section collapsed or visually secondary.

### `ProviderCard.qml`

Render one card generically:

- Display name + provider id/source.
- Plan/login method if present.
- Identity, redacted already; keep compact.
- Error message/setup hint if present.
- Stale badge if `is_stale` or daemon-dead stale.
- Dynamic repeater for every `quota_windows[]` entry.
- Dynamic repeater for every `credit_meters[]` entry.
- Do not assume provider-specific labels.

### `QuotaWindowBar.qml`

- Label priority:
  1. `reset_description` if useful
  2. `window_label`
  3. `id`
- Usage percent rounded for display.
- Show reset time if `resets_at` exists.
- Use same threshold colors as compact icon.
- Handle `used_percent=null` gracefully.

### `CreditMeter.qml`

- Render balance/used/total/used_percent based on what exists.
- For OpenRouter, show balance-style data without pretending it is a quota window.
- If `used_percent` exists, show a bar.
- If only `balance` exists, show text-only meter.

## Build steps

1. Create minimal plasmoid skeleton.
2. Add sample snapshot fixture under `tests/fixtures/snapshot/phase3-four-provider.json` from current daemon output or sanitized live output.
3. Build `SnapshotStore.qml` against the fixture first, not live daemon data.
4. Build compact icon state calculation.
5. Build full popup provider card rendering.
6. Add manual install/update instructions:

```bash
kpackagetool6 -t Plasma/Applet -i plasmoid/
kpackagetool6 -t Plasma/Applet -u plasmoid/
kpackagetool6 -t Plasma/Applet -r org.jeremywindsor.neon-codexbar
```

7. Test on KDE Neon with the Phase 2 daemon running.
8. Compare widget rendering against `neon-codexbar fetch --json` / snapshot output.

## Manual QA checklist

Run on KDE Neon/Plasma 6.

### Install/load

- [ ] `kpackagetool6 -t Plasma/Applet -i plasmoid/` succeeds.
- [ ] Widget appears in Add Widgets search as `neon-codexbar`.
- [ ] Widget can be added to panel.
- [ ] Widget survives plasmashell restart.

### Snapshot states

- [ ] Missing snapshot: clear setup/error state; no QML crash.
- [ ] `snapshot.ok=false`: global CodexBar setup error, not per-provider confusion.
- [ ] Valid empty snapshot: sensible “no providers” state.
- [ ] Valid four-provider snapshot: four cards render.
- [ ] Malformed JSON: readable error state; no QML crash.

### Provider rendering

- [ ] Codex card shows quota windows.
- [ ] Claude card shows quota windows.
- [ ] z.ai card shows all three windows in order.
- [ ] OpenRouter card shows credit/balance meter and does not require quota windows.
- [ ] Provider-specific error card renders without marking whole widget broken.
- [ ] Long reset labels do not explode layout like a raccoon in a ceiling fan.

### Staleness

- [ ] Provider `is_stale=true` dims only that card.
- [ ] Old `generated_at` dims whole widget as daemon-dead stale.
- [ ] Fresh snapshot clears stale state.

### Manual refresh

- [ ] Refresh button creates/touches `refresh.touch` next to snapshot.
- [ ] Daemon consumes sentinel.
- [ ] Snapshot updates and widget refreshes.

### Theming/layout

- [ ] Dark theme readable.
- [ ] Light theme readable.
- [ ] Narrow panel works.
- [ ] Vertical panel works.
- [ ] Popup scrolls when provider cards exceed height.

## Test strategy

Automated QML testing can wait unless it is cheap. Phase 3 needs a real Plasma session more than fake coverage theater.

Minimum gates before calling Phase 3 complete:

```bash
python3 -m ruff check .
python3 -m pytest
kpackagetool6 -t Plasma/Applet -i plasmoid/   # on KDE Neon
```

Manual QA checklist above must be captured in this file or `docs/QA.md` with pass/fail notes.

## Risks

| Risk | Mitigation |
|---|---|
| Plasma 6 file watcher API is awkward or absent | Start with watcher, fall back to 5s polling. Polling is acceptable for v1. |
| QML file write for manual refresh is ugly | Add a tiny helper only if QML-native touch is not viable. Do not let QML spawn provider fetches. |
| Snapshot schema evolves while widget is built | Treat `docs/DAEMON_CONTRACT.md` as frozen for Phase 3. Ignore unknown fields. |
| UI accidentally hardcodes provider assumptions | Use z.ai and OpenRouter fixtures as mandatory QA cases. They are the anti-bullshit detectors. |
| Daemon-dead stale threshold needs refresh interval | Phase 3 can hardcode 600s warning / 1800s dead-ish. Phase 5 can read real config. |

## Recommended implementation dispatch

Hand this to Codex/Claude Code as a UI implementation task, not a backend refactor:

> Build Phase 3 only. Create the Plasma 6 plasmoid described in `plans/phase-3-plasmoid.md`. Do not change provider fetching, daemon semantics, or snapshot schema unless the widget cannot consume the documented contract. Use `docs/DAEMON_CONTRACT.md` as the API. Keep QML generic and provider-agnostic. Add/update docs and a manual QA checklist. Run Python tests/ruff after any Python-adjacent changes; validate install on KDE Neon with `kpackagetool6` when available.

## Done definition

Phase 3 is done when:

- Plasmoid package installs on KDE Neon.
- Widget reads and refreshes from `snapshot.json`.
- Codex, Claude, z.ai, and OpenRouter render correctly from live or sanitized snapshot data.
- Manual refresh sentinel works.
- Missing/malformed/stale/error states are safe and visible.
- No provider-specific assumptions land in QML.
- Phase 3 QA notes are recorded.

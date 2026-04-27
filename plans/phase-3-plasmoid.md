# Phase 3 — Plasmoid v1 Generic Renderer

Date opened: 2026-04-27
Status: in progress (build dispatched)

## Sandbox constraint

This sandbox is a Debian LXC. **No Plasma session.** Cannot run the widget,
see it render, verify theming visually, exercise FileWatcher live, or run
`kpackagetool6`. All runtime acceptance happens on Jeremy's KDE Neon laptop
via the QA checklist below. What gets done here:

- structurally correct QML / metadata / install scripts
- static cross-check against `docs/DAEMON_CONTRACT.md` field-by-field
- generated sample snapshot fixture for QML to develop against
- catch wrong imports (Plasma 5 vs 6)
- peer review by an agent

## Multi-agent build dispatch

Two `general-purpose` agents in parallel — non-overlapping scopes. Both read
this file, `docs/DAEMON_CONTRACT.md`, the four sample snapshots, and the
master plan §11–§12.

| Agent | Scope | Status |
|---|---|---|
| A | `plasmoid/` tree (8 QML files + metadata + KConfigXT schema + config dialog) | dispatched |
| B | `packaging/install.sh`, `packaging/uninstall.sh` | dispatched |

After both return, this file gets a "Build results" section, then a peer-
review agent runs over the integrated tree.

## Build results — 2026-04-27

Both agents returned. 1,021 lines of QML across 8 files plus metadata, KConfigXT
schema, config dialog, and two install scripts (5,431 + 4,339 bytes).

### File inventory

```
plasmoid/
├── metadata.json                       Plasma 6 schema, plugin id org.jeremywindsor.neon-codexbar
└── contents/
    ├── ui/
    │   ├── main.qml                    45 lines  — PlasmoidItem entry, owns SnapshotStore, wires representations
    │   ├── SnapshotStore.qml          215 lines  — sole file I/O, XHR GET, polling Timer, sentinel PUT, derived state
    │   ├── CompactRepresentation.qml   66 lines  — colored ring + center percent; theme-only colors
    │   ├── FullRepresentation.qml     172 lines  — header, global StatusBanners, scrollable cards, collapsible diagnostics
    │   ├── ProviderCard.qml           138 lines  — provider-agnostic header, error banner, repeaters
    │   ├── QuotaWindowBar.qml         102 lines  — label fallback chain, handles window_minutes=null
    │   ├── CreditMeter.qml             98 lines  — bar when used_percent exists, text-only fallback
    │   └── StatusBanner.qml            69 lines  — reusable severity banner (error/warning/info/stale)
    └── config/
        ├── main.xml                    47 lines  — KConfigXT schema (6 fields)
        ├── config.qml                  10 lines  — ConfigModel pointing to ConfigGeneral
        └── ConfigGeneral.qml           59 lines  — Kirigami.FormLayout with cfg_* aliases

packaging/
├── install.sh                          5,431 B   — idempotent: prereq checks, pip install, kpackagetool6 install/upgrade, systemd enable
└── uninstall.sh                        4,339 B   — disable/stop/remove unit, plasmoid, pip; --purge opt-in for user data; refuses to touch ~/.codexbar/
```

### Pre-peer-review contract cross-check (myself)

I read every QML file against `docs/DAEMON_CONTRACT.md` field by field:

- `snapshot.ok` semantic respected — global setup banner triggered by `!snapshotOk || !codexbarAvailable`, distinct from per-card error banners. ✅
- `cards[i].error_message` rendered in per-card `StatusBanner`. ✅
- `cards[i].is_stale` dims that one card via `opacity: 0.55`. ✅
- Daemon-dead staleness computed in `SnapshotStore` from `generated_at` vs `Date.now()`; thresholds `daemonStaleThresholdSec=600` / `daemonDeadThresholdSec=1800`. ✅
- `cards[]` order preserved — Repeater iterates as-is, no `sort()`. ✅
- `quota_windows[]` order preserved — Repeater iterates as-is. ✅
- `quota_window.window_minutes=null` (z.ai secondary) handled — `QuotaWindowBar._primaryLabel` falls through to `reset_description`, and the secondary line drops the "min window" piece when minutes are missing. ✅
- `credit_meter` text-only fallback when no `used_percent` (OpenRouter Key Quota in some snapshots) — bar `visible: _hasPct`, detail line still renders balance/used/total. ✅
- `diagnostics[]` rendered verbatim under collapsible toggle. ✅
- No string in any QML mentions `codex`/`claude`/`zai`/`openrouter`/`Session`/`Weekly`. ✅
- All colors via `Kirigami.Theme.*` (positive/neutral/negative/disabled/text). ✅
- Plasma 6 imports throughout (`org.kde.plasma.plasmoid 2.0`, `org.kde.plasma.components 3.0`, `org.kde.kirigami 2.20`). ✅
- No subprocess spawning. ✅

### Open TODOs flagged by Agent A

- `XMLHttpRequest PUT` against `file://` for the sentinel may be rejected by Qt's
  QNetworkAccessManager file scheme on some builds. If so, the refresh button
  still works (re-reads the snapshot) and `console.log("touch sentinel TODO: ...")`
  fires. Real-target QA item.
- `Plasmoid.expanded` toggle on click in `CompactRepresentation` — Plasma 6
  sometimes prefers `Plasmoid.activated()`. Real-target QA item.
- `Qt.labs.platform.StandardPaths` is part of stock Qt 6 but plasmashell can be
  picky about which Qt labs modules ship. If missing, swap to `XdgDirs` via
  PlasmaCore. Real-target QA item.

All three are caught by the existing `docs/QA.md`-equivalent checklist embedded
above. No code blockers from my cross-check.

## Build checklist — updated

- [x] `docs/snapshot.example.json` — sanitized live capture (kept at
      `tests/fixtures/snapshot/phase3-four-provider.json` per the file layout)
- [x] Agent A delivered `plasmoid/` tree
- [x] Agent B delivered `packaging/install.sh` + `uninstall.sh`
- [x] I cross-checked QML against `DAEMON_CONTRACT.md` field-by-field
- [x] QA checklist embedded above (no separate `docs/QA.md`; this file is the home)
- [x] Peer-review agent verdict captured below
- [x] Review fixes applied or deferred with reasons
- [x] Tests + ruff still green (no Python regressions) — 35 passing
- [ ] `git push origin main`

## Peer review verdict — 2026-04-27

Spawned a `general-purpose` review agent (read-only) over the integrated
plasmoid + scripts. Verdict: **ship after fixes** — contract adherence is
solid, blockers are Plasma 6 packaging/API correctness only catchable on a
real session.

### Triage and disposition

| # | Finding | Decision |
|---|---|---|
| Must-1 | `KPackageStructure` may need to be inside `KPlugin` not top-level | **Defensive fix:** keep at top level AND add inside `KPlugin`. KPackage ignores unknown fields — whichever Plasma reads, it'll find. (I'm fairly sure top-level is correct on Plasma 6, but cost of dual-location is zero.) |
| Must-2 | Explicit `MouseArea` swallows panel chrome events (drag, middle-click) | **Fixed.** Removed `MouseArea` from `CompactRepresentation.qml`; PlasmoidItem default click-to-expand handles it. |
| Must-3 | Unused `org.kde.plasma.core` import in `main.qml` and `CompactRepresentation.qml` | **Fixed.** Removed both. |
| Must-4 | `width: root.width - …` inside `ScrollView` content — binding loop / clipping risk | **Fixed.** Inner `ColumnLayout.width: scroll.availableWidth`, `ScrollView.contentWidth: availableWidth`. |
| Must-5 | `Plasmoid.toolTipMainText` deprecation in Plasma 6 | **Fixed (partially).** Removed `Plasmoid.` prefix to use the PlasmoidItem property form; full migration to `toolTipItem` deferred to Phase 5 (it's just deprecation warnings, not breakage). Code comment added. |
| Must-6 | Icon `system-help` looks like an unknown widget in Add Widgets | **Fixed.** Now `utilities-system-monitor`. |
| Should-1 | XHR race when polling tick + manual refresh overlap | **Fixed.** Added `_loading` guard; cleared in DONE callback and the open/send catch. |
| Should-2 | XHR PUT to `file://` may silently no-op on some Qt builds | **Documented only.** Switching to subprocess violates the architecture; agent already TODO'd. The fallback (re-read snapshot) is harmless. Real KDE QA confirms or denies. |
| Should-3 | Raw `generated_at` ugly in popup header | **Fixed.** New `SnapshotStore.relativeAge()` formatter ("Xm ago"); wired into all three header/banner uses in FullRepresentation. |
| Should-4 | `daemonStaleThreshold` / `daemonDeadThreshold` had no `<max>` in main.xml while ConfigGeneral SpinBoxes capped at 86400 | **Fixed.** Added `<max>86400</max>` to both. |
| Should-5 | StatusBanner title used severity color → low contrast on warning/stale | **Fixed.** Title uses `Kirigami.Theme.textColor`; border keeps severity color. |
| Should-6 | `_epochSeconds` silently breaks if daemon ever drops the `Z` suffix | **Fixed.** Added comment noting the contract dependency. |
| Bonus | `pip install --user .` will fail on PEP-668 (Neon's system Python) | **Fixed.** install.sh tries clean form first; on `externally-managed-environment` error, retries with `--break-system-packages`. |
| Nice-to-have | i18n on bare strings, accessibility, kbuildsycoca6 | **Deferred.** Phase 5 (UX polish). |

### Verification

```
python3 -m ruff check .   → All checks passed
python3 -m pytest -q      → 35 passed
bash -n install.sh        → syntax OK
grep -nE "\\b(claude|zai|openrouter|Session|Weekly)\\b" plasmoid/   → no matches
```

The single Must-1 item (metadata structure) is the only one I didn't
unconditionally accept the reviewer on — defensive dual-location is the
pragmatic call.

## Status: ready for KDE Neon QA

Phase 3 sandbox-side work is complete. The QA checklist embedded above runs
on Jeremy's KDE Neon laptop. Findings from real-session QA (especially
metadata.json acceptance, sentinel PUT behavior, theme correctness) get
recorded back here as a "Phase 3 QA results" section before Phase 4 starts.

This file is now ready to send out for additional external peer review.

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

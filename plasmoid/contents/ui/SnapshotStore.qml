// SnapshotStore.qml
//
// Sole owner of file I/O for the plasmoid. Reads ~/.cache/neon-codexbar/snapshot.json
// via XMLHttpRequest against a file:// URL (the standard QML pattern; QML cannot
// read raw paths directly). Polls every pollingInterval seconds.
//
// TODO (verify on real KDE Neon): touching the refresh.touch sentinel via
// XMLHttpRequest PUT is documented to work on most QML stacks, but the underlying
// QNetworkAccessManager file scheme is read-only on some Qt builds. If
// `requestRefresh()` doesn't produce the sentinel, we'll add a tiny shell helper
// or fall back to invoking `kill -USR1` via a launcher process. For Phase 3 the
// button at minimum re-loads the snapshot and logs the failure.
//
// We deliberately do NOT spawn `touch` via Plasma5Support.DataSource because the
// contract is "no subprocess spawning, ever." Sentinel writes are pure file I/O.

import QtQuick
import Qt.labs.platform as Labs

QtObject {
    id: store

    // ---- Configuration (parent passes from KConfigXT) ----
    property string snapshotPath: ""           // empty => default $HOME/.cache/neon-codexbar/snapshot.json
    property int warningThreshold: 70
    property int criticalThreshold: 90
    property int daemonStaleThresholdSec: 600
    property int daemonDeadThresholdSec: 1800
    property int pollingInterval: 5

    // Qt.labs.platform.StandardPaths gives us the home directory portably.
    readonly property string _homeDir: {
        var url = Labs.StandardPaths.writableLocation(Labs.StandardPaths.HomeLocation);
        // url is a file:// URL; strip the scheme.
        var s = url.toString();
        if (s.indexOf("file://") === 0) s = s.substring(7);
        return s.replace(/\/$/, "");
    }

    // ---- Derived: resolved absolute path ----
    readonly property string resolvedPath: {
        if (snapshotPath && snapshotPath.length > 0) {
            if (snapshotPath.indexOf("~/") === 0) {
                return _homeDir + snapshotPath.substring(1);
            }
            return snapshotPath;
        }
        return _homeDir + "/.cache/neon-codexbar/snapshot.json";
    }

    readonly property string resolvedSentinelPath: {
        var p = resolvedPath;
        var idx = p.lastIndexOf("/");
        if (idx < 0) return "refresh.touch";
        return p.substring(0, idx) + "/refresh.touch";
    }

    // ---- Exposed snapshot fields ----
    property bool snapshotOk: false
    property bool codexbarAvailable: false
    property string codexbarVersion: ""
    property string generatedAt: ""
    property var cards: []
    property var diagnostics: []
    property string readError: ""

    // Guard against overlapping reads. Polling tick + manual refresh can race
    // when the user clicks Refresh during a slow filesystem read.
    property bool _loading: false

    // ---- Derived freshness/state ----
    property bool daemonStaleWarning: false
    property bool daemonDeadStale: false
    property real maxUsagePercent: 0.0
    property string worstState: "missing"  // ok | warning | critical | error | stale | missing

    function _toFileUrl(absPath) {
        if (absPath.indexOf("file://") === 0) return absPath;
        return "file://" + absPath;
    }

    function _epochSeconds(iso) {
        // Daemon emits Z-suffixed UTC ISO-8601 (see DAEMON_CONTRACT.md) so
        // Date.parse picks up the timezone; if the contract ever drops the Z
        // this silently treats the string as local time, breaking staleness.
        if (!iso) return 0;
        var d = new Date(iso);
        var t = d.getTime();
        if (isNaN(t)) return 0;
        return t / 1000;
    }

    // Human-readable relative time string for the popup header.
    function relativeAge(iso) {
        if (!iso) return "";
        var sec = _epochSeconds(iso);
        if (sec === 0) return iso;
        var deltaSec = Math.max(0, Math.floor(Date.now() / 1000 - sec));
        if (deltaSec < 5)        return "just now";
        if (deltaSec < 60)       return deltaSec + "s ago";
        if (deltaSec < 3600)     return Math.floor(deltaSec / 60) + "m ago";
        if (deltaSec < 86400)    return Math.floor(deltaSec / 3600) + "h ago";
        return Math.floor(deltaSec / 86400) + "d ago";
    }

    function _recompute() {
        var nowSec = Date.now() / 1000;
        var genSec = _epochSeconds(generatedAt);
        var ageSec = genSec > 0 ? (nowSec - genSec) : Number.POSITIVE_INFINITY;
        daemonStaleWarning = ageSec >= daemonStaleThresholdSec;
        daemonDeadStale = ageSec >= daemonDeadThresholdSec;

        var maxPct = 0.0;
        var anyError = false;
        var anyStaleCard = false;
        if (cards && cards.length) {
            for (var i = 0; i < cards.length; ++i) {
                var c = cards[i];
                if (!c) continue;
                if (c.error_message) anyError = true;
                if (c.is_stale) anyStaleCard = true;
                var qws = c.quota_windows || [];
                for (var j = 0; j < qws.length; ++j) {
                    var p = qws[j].used_percent;
                    if (typeof p === "number" && !isNaN(p) && p > maxPct) maxPct = p;
                }
                var cms = c.credit_meters || [];
                for (var k = 0; k < cms.length; ++k) {
                    var cp = cms[k].used_percent;
                    if (typeof cp === "number" && !isNaN(cp) && cp > maxPct) maxPct = cp;
                }
            }
        }
        maxUsagePercent = maxPct;

        // worstState precedence: missing > error > stale > critical > warning > ok
        if (readError && readError.length) {
            worstState = "missing";
        } else if (!snapshotOk || !codexbarAvailable) {
            worstState = "error";
        } else if (daemonDeadStale) {
            worstState = "stale";
        } else if (anyError) {
            worstState = "error";
        } else if (daemonStaleWarning || anyStaleCard) {
            worstState = "stale";
        } else if (maxPct >= criticalThreshold) {
            worstState = "critical";
        } else if (maxPct >= warningThreshold) {
            worstState = "warning";
        } else {
            worstState = "ok";
        }
    }

    function load() {
        if (_loading) return;   // skip overlapping reads
        _loading = true;
        var url = _toFileUrl(resolvedPath);
        var xhr = new XMLHttpRequest();
        xhr.onreadystatechange = function() {
            if (xhr.readyState !== XMLHttpRequest.DONE) return;
            _loading = false;
            // For file:// URLs, status is typically 0 even on success.
            var text = xhr.responseText;
            if (!text || text.length === 0) {
                readError = "Snapshot file is empty or missing: " + resolvedPath;
                snapshotOk = false;
                codexbarAvailable = false;
                cards = [];
                diagnostics = [];
                _recompute();
                return;
            }
            try {
                var parsed = JSON.parse(text);
                readError = "";
                snapshotOk = !!parsed.ok;
                generatedAt = parsed.generated_at || "";
                cards = Array.isArray(parsed.cards) ? parsed.cards : [];
                diagnostics = Array.isArray(parsed.diagnostics) ? parsed.diagnostics : [];
                if (parsed.codexbar) {
                    codexbarAvailable = !!parsed.codexbar.available;
                    codexbarVersion = parsed.codexbar.version || "";
                } else {
                    codexbarAvailable = false;
                    codexbarVersion = "";
                }
                _recompute();
            } catch (e) {
                readError = "Snapshot JSON parse error: " + e;
                snapshotOk = false;
                codexbarAvailable = false;
                cards = [];
                diagnostics = [];
                _recompute();
            }
        };
        try {
            xhr.open("GET", url);
            xhr.send();
        } catch (e) {
            _loading = false;
            readError = "Cannot open snapshot URL: " + e;
            _recompute();
        }
    }

    function requestRefresh() {
        // Try XHR PUT against the sentinel file:// URL. Most QML stacks honor
        // this for local files; some refuse. When it fails we still kick a
        // re-read so the user gets immediate feedback.
        var url = _toFileUrl(resolvedSentinelPath);
        var xhr = new XMLHttpRequest();
        xhr.onreadystatechange = function() {
            if (xhr.readyState !== XMLHttpRequest.DONE) return;
            store.load();
        };
        try {
            xhr.open("PUT", url);
            xhr.send("");
        } catch (e) {
            console.log("neon-codexbar: touch sentinel TODO: " + e
                + " (URL=" + url + "). Refresh button only re-read snapshot.");
            store.load();
        }
    }

    // Polling fallback. Plasma 6 has no stable QML FileSystemWatcher binding so
    // we always poll; on a 5s interval the cost is negligible.
    property var _ticker: Timer {
        interval: store.pollingInterval * 1000
        running: true
        repeat: true
        onTriggered: store.load()
    }

    Component.onCompleted: load()
}

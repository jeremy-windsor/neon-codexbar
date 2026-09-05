// SnapshotStore.qml
//
// Sole owner of file I/O for the plasmoid. Reads ~/.cache/neon-codexbar/snapshot.json
// via XMLHttpRequest against a file:// URL (the standard QML pattern; QML cannot
// read raw paths directly). Polls every pollingInterval seconds.
//
// Manual refresh invokes the installed neon-codexbar helper through Plasma's
// executable data source. The helper only creates the daemon's refresh sentinel.

import QtQuick
import Qt.labs.platform as Labs
import org.kde.plasma.plasma5support as Plasma5Support

QtObject {
    id: store

    // ---- Configuration (parent passes from KConfigXT) ----
    property string snapshotPath: ""           // empty => default $HOME/.cache/neon-codexbar/snapshot.json
    property int warningThreshold: 70
    property int criticalThreshold: 90
    property int daemonStaleThresholdSec: 600
    property int daemonDeadThresholdSec: 1800
    property int pollingInterval: 5
    property string providerOrder: ""          // comma-separated provider ids
    property string hiddenProviders: ""        // comma-separated provider ids hidden from popup/tray
    property string trayProvider: ""           // provider id when trayMode=selected-provider
    property string trayMode: "highest-usage"  // highest-usage | selected-provider

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

    // ---- Exposed snapshot fields ----
    property bool snapshotOk: false
    property bool codexbarAvailable: false
    property string codexbarVersion: ""
    property string generatedAt: ""
    property var cards: []
    property var displayCards: []
    property var diagnostics: []
    property string readError: ""

    // Guard against overlapping reads. Polling tick + manual refresh can race
    // when the user clicks Refresh during a slow filesystem read.
    property bool _loading: false

    // ---- Derived freshness/state ----
    property bool daemonStaleWarning: false
    property bool daemonDeadStale: false
    property real maxUsagePercent: 0.0
    property real trayUsagePercent: 0.0
    property real trayPrimaryUsagePercent: 0.0
    property real traySecondaryUsagePercent: 0.0
    property var trayWindowItems: []
    property string trayLabel: "max"
    property var trayCard: null
    property bool trayProviderMissing: false
    property string trayState: "missing"    // ok | warning | critical | error | stale | missing
    property string worstState: "missing"  // ok | warning | critical | error | stale | missing
    property bool refreshInProgress: false
    property string refreshError: ""
    property string _refreshBaseline: ""
    property int _refreshPollsRemaining: 0

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

    function _providerMaxPercent(card) {
        if (!card) return 0.0;
        var maxPct = 0.0;
        var qws = card.quota_windows || [];
        for (var i = 0; i < qws.length; ++i) {
            var p = qws[i].used_percent;
            if (typeof p === "number" && !isNaN(p) && p > maxPct) maxPct = p;
        }
        var cms = card.credit_meters || [];
        for (var j = 0; j < cms.length; ++j) {
            var cp = cms[j].used_percent;
            if (typeof cp === "number" && !isNaN(cp) && cp > maxPct) maxPct = cp;
        }
        return maxPct;
    }

    function _providerErrorSeverity(card) {
        if (!card || !card.error_message) return "";
        return card.error_severity === "warning" ? "warning" : "error";
    }

    function _compactWindowLabel(window, index) {
        if (!window) return "W" + (index + 1);
        var minutes = window.window_minutes;
        if (typeof minutes === "number" && !isNaN(minutes) && minutes > 0) {
            if (minutes % 10080 === 0) return (minutes / 10080) + "w";
            if (minutes % 1440 === 0) return (minutes / 1440) + "d";
            if (minutes % 60 === 0) return (minutes / 60) + "h";
            return minutes + "m";
        }
        var label = window.window_label || window.reset_description || "";
        var match = label.toLowerCase().match(/^(\d+)-(minute|hour|day|week) window$/);
        if (match) {
            var units = {"minute": "m", "hour": "h", "day": "d", "week": "w"};
            return match[1] + units[match[2]];
        }
        return label || "W" + (index + 1);
    }

    function _trayWindowItemsForCard(card) {
        var items = [];
        if (!card) return items;
        var qws = card.quota_windows || [];
        for (var i = 0; i < qws.length && items.length < 2; ++i) {
            var w = qws[i];
            if (!w) continue;
            var percent = w.used_percent;
            if (typeof percent !== "number" || isNaN(percent)) continue;
            items.push({
                "label": _compactWindowLabel(w, i),
                "percent": percent
            });
        }
        return items;
    }

    function _orderedCards(sourceCards) {
        var items = sourceCards ? sourceCards.slice(0) : [];
        if (!providerOrder || providerOrder.trim().length === 0) return items;

        var ranks = {};
        var ids = providerOrder.split(",");
        for (var i = 0; i < ids.length; ++i) {
            var id = ids[i].trim().toLowerCase();
            if (id.length > 0 && ranks[id] === undefined) ranks[id] = i;
        }

        items.sort(function(a, b) {
            var aid = a && a.provider_id ? a.provider_id.toLowerCase() : "";
            var bid = b && b.provider_id ? b.provider_id.toLowerCase() : "";
            var ar = ranks[aid] === undefined ? 100000 : ranks[aid];
            var br = ranks[bid] === undefined ? 100000 : ranks[bid];
            if (ar !== br) return ar - br;
            return aid.localeCompare(bid);
        });
        return items;
    }

    function _visibleCards(sourceCards) {
        var items = sourceCards ? sourceCards.slice(0) : [];
        if (!hiddenProviders || hiddenProviders.trim().length === 0) return items;

        var hidden = {};
        var ids = hiddenProviders.split(",");
        for (var i = 0; i < ids.length; ++i) {
            var id = ids[i].trim().toLowerCase();
            if (id.length > 0) hidden[id] = true;
        }

        return items.filter(function(card) {
            var providerId = card && card.provider_id ? card.provider_id.toLowerCase() : "";
            return !hidden[providerId];
        });
    }

    function _recompute() {
        var nowSec = Date.now() / 1000;
        var genSec = _epochSeconds(generatedAt);
        var ageSec = genSec > 0 ? (nowSec - genSec) : Number.POSITIVE_INFINITY;
        daemonStaleWarning = ageSec >= daemonStaleThresholdSec;
        daemonDeadStale = ageSec >= daemonDeadThresholdSec;

        displayCards = _orderedCards(_visibleCards(cards));

        var maxPct = 0.0;
        var maxCard = null;
        var anyError = false;
        var anyProviderWarning = false;
        var anyStaleCard = false;
        if (displayCards && displayCards.length) {
            for (var i = 0; i < displayCards.length; ++i) {
                var c = displayCards[i];
                if (!c) continue;
                if (_providerErrorSeverity(c) === "error") anyError = true;
                if (_providerErrorSeverity(c) === "warning") anyProviderWarning = true;
                if (c.is_stale) anyStaleCard = true;
                var cardPct = _providerMaxPercent(c);
                if (cardPct >= maxPct) {
                    maxPct = cardPct;
                    maxCard = c;
                }
            }
        }
        maxUsagePercent = maxPct;

        trayUsagePercent = maxPct;
        trayLabel = maxCard ? (maxCard.display_name || maxCard.provider_id || "max") : "max";
        trayProviderMissing = false;
        var selectedTrayCard = maxCard;
        if (trayMode === "selected-provider" && trayProvider && trayProvider.trim().length) {
            var selectedId = trayProvider.trim().toLowerCase();
            trayProviderMissing = true;
            for (var m = 0; displayCards && m < displayCards.length; ++m) {
                var card = displayCards[m];
                if (card && card.provider_id && card.provider_id.toLowerCase() === selectedId) {
                    trayUsagePercent = _providerMaxPercent(card);
                    trayLabel = card.display_name || card.provider_id;
                    selectedTrayCard = card;
                    trayProviderMissing = false;
                    break;
                }
            }
        }
        trayCard = selectedTrayCard;
        trayWindowItems = _trayWindowItemsForCard(selectedTrayCard);
        trayPrimaryUsagePercent = trayWindowItems.length > 0 ? trayWindowItems[0].percent : 0.0;
        traySecondaryUsagePercent = trayWindowItems.length > 1 ? trayWindowItems[1].percent : 0.0;

        // trayState mirrors worstState precedence, but its usage/error inputs
        // are scoped to the provider selected for tray display.
        if (readError && readError.length) {
            trayState = "missing";
        } else if (!snapshotOk || !codexbarAvailable || trayProviderMissing) {
            trayState = "error";
        } else if (daemonDeadStale) {
            trayState = "stale";
        } else if (_providerErrorSeverity(selectedTrayCard) === "error") {
            trayState = "error";
        } else if (daemonStaleWarning || (selectedTrayCard && selectedTrayCard.is_stale)) {
            trayState = "stale";
        } else if (trayUsagePercent >= criticalThreshold) {
            trayState = "critical";
        } else if (_providerErrorSeverity(selectedTrayCard) === "warning"
                   || trayUsagePercent >= warningThreshold) {
            trayState = "warning";
        } else {
            trayState = "ok";
        }

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
        } else if (anyProviderWarning || maxPct >= warningThreshold) {
            worstState = "warning";
        } else {
            worstState = "ok";
        }
    }

    onProviderOrderChanged: _recompute()
    onHiddenProvidersChanged: _recompute()
    onTrayProviderChanged: _recompute()
    onTrayModeChanged: _recompute()

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

    function _shellQuote(value) {
        return "'" + String(value).replace(/'/g, "'\"'\"'") + "'";
    }

    function requestRefresh() {
        if (refreshInProgress) return;
        refreshInProgress = true;
        refreshError = "";
        _refreshBaseline = generatedAt;
        _refreshPollsRemaining = 60;
        var helper = _homeDir + "/.local/bin/neon-codexbar";
        var command = _shellQuote(helper) + " refresh --json --snapshot-path "
            + _shellQuote(resolvedPath);
        refreshCommand.connectSource(command);
    }

    property var _refreshCommand: Plasma5Support.DataSource {
        id: refreshCommand
        engine: "executable"
        connectedSources: []

        onNewData: {
            var exitCode = data["exit code"];
            disconnectSource(sourceName);
            if (exitCode !== 0) {
                store.refreshInProgress = false;
                store.refreshError = data["stderr"] || "Refresh helper failed.";
                return;
            }
            refreshPollTimer.start();
        }
    }

    property var _refreshPollTimer: Timer {
        id: refreshPollTimer
        interval: 1000
        repeat: true
        onTriggered: {
            if (store.generatedAt && store.generatedAt !== store._refreshBaseline) {
                stop();
                store.refreshInProgress = false;
                store.refreshError = "";
                return;
            }
            if (store._refreshPollsRemaining <= 0) {
                stop();
                store.refreshInProgress = false;
                store.refreshError = "Daemon did not publish a fresh snapshot.";
                return;
            }
            store._refreshPollsRemaining -= 1;
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

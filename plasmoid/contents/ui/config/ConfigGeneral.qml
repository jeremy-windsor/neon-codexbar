import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import Qt.labs.platform as Labs
import org.kde.kcmutils as KCM
import org.kde.kirigami 2.20 as Kirigami

// Standard Plasma 6 KConfigXT pattern: properties named cfg_<entry> are
// auto-bound to the matching <entry name> in main.xml via plasma's config dialog.
KCM.SimpleKCM {
    id: root

    property alias cfg_snapshotPath: snapshotPathField.text
    property alias cfg_warningThreshold: warningSpin.value
    property alias cfg_criticalThreshold: criticalSpin.value
    property alias cfg_daemonStaleThreshold: staleSpin.value
    property alias cfg_daemonDeadThreshold: deadSpin.value
    property alias cfg_pollingInterval: pollSpin.value
    property string cfg_providerOrder: ""
    property string cfg_hiddenProviders: ""
    property string cfg_trayProvider: ""
    property string cfg_trayMode: "highest-usage"
    property string cfg_trayIconStyle: "percent-ring"

    readonly property string _homeDir: {
        var url = Labs.StandardPaths.writableLocation(Labs.StandardPaths.HomeLocation);
        var s = url.toString();
        if (s.indexOf("file://") === 0) s = s.substring(7);
        return s.replace(/\/$/, "");
    }
    property bool _loadingProviders: false
    property bool _syncingProviders: false
    property string providerReadError: ""

    ListModel {
        id: providerModel
    }

    Component.onCompleted: {
        trayModeCombo.currentIndex = cfg_trayMode === "selected-provider" ? 1 : 0;
        syncTrayIconStyleCombo();
        loadProviders();
    }

    onCfg_trayModeChanged: {
        trayModeCombo.currentIndex = cfg_trayMode === "selected-provider" ? 1 : 0;
    }

    onCfg_trayIconStyleChanged: {
        syncTrayIconStyleCombo();
    }

    onCfg_providerOrderChanged: loadProviders()
    onCfg_hiddenProvidersChanged: loadProviders()
    onCfg_trayProviderChanged: syncTrayCombo()
    onCfg_snapshotPathChanged: loadProviders()

    function resolvedSnapshotPath() {
        if (cfg_snapshotPath && cfg_snapshotPath.length > 0) {
            if (cfg_snapshotPath.indexOf("~/") === 0) {
                return _homeDir + cfg_snapshotPath.substring(1);
            }
            return cfg_snapshotPath;
        }
        return _homeDir + "/.cache/neon-codexbar/snapshot.json";
    }

    function toFileUrl(absPath) {
        if (absPath.indexOf("file://") === 0) return absPath;
        return "file://" + absPath;
    }

    function splitIds(value) {
        var result = [];
        if (!value || value.trim().length === 0) return result;
        var parts = value.split(",");
        for (var i = 0; i < parts.length; ++i) {
            var id = parts[i].trim().toLowerCase();
            if (id.length > 0 && result.indexOf(id) < 0) result.push(id);
        }
        return result;
    }

    function sortedCards(cards) {
        var items = cards ? cards.slice(0) : [];
        var order = splitIds(cfg_providerOrder);
        var ranks = {};
        for (var i = 0; i < order.length; ++i) ranks[order[i]] = i;

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

    function loadProviders() {
        if (_loadingProviders) return;
        _loadingProviders = true;
        providerReadError = "";

        var xhr = new XMLHttpRequest();
        xhr.onreadystatechange = function() {
            if (xhr.readyState !== XMLHttpRequest.DONE) return;
            _loadingProviders = false;

            var text = xhr.responseText;
            if (!text || text.length === 0) {
                rebuildProviderModel([]);
                providerReadError = i18n("Snapshot not found yet.");
                return;
            }

            try {
                var parsed = JSON.parse(text);
                var cards = Array.isArray(parsed.cards) ? parsed.cards : [];
                rebuildProviderModel(cards);
            } catch (e) {
                rebuildProviderModel([]);
                providerReadError = i18n("Snapshot JSON could not be read.");
            }
        };

        try {
            xhr.open("GET", toFileUrl(resolvedSnapshotPath()));
            xhr.send();
        } catch (e) {
            _loadingProviders = false;
            rebuildProviderModel([]);
            providerReadError = i18n("Snapshot path could not be opened.");
        }
    }

    function rebuildProviderModel(cards) {
        _syncingProviders = true;
        providerModel.clear();

        var hidden = splitIds(cfg_hiddenProviders);
        var items = sortedCards(cards);
        for (var i = 0; i < items.length; ++i) {
            var card = items[i];
            if (!card || !card.provider_id) continue;
            var providerId = card.provider_id.toLowerCase();
            var sourceBits = [];
            if (card.source) sourceBits.push(card.source);
            if (card.version) sourceBits.push("v" + card.version);
            providerModel.append({
                "providerId": providerId,
                "displayName": card.display_name || card.provider_id,
                "sourceText": sourceBits.join(" "),
                "statusText": providerStatus(card),
                "showInPopup": hidden.indexOf(providerId) < 0
            });
        }

        _syncingProviders = false;
        syncFromProviderModel();
        syncTrayCombo();
    }

    function providerStatus(card) {
        if (card.error_message) return i18n("Fetch failed");
        if (card.is_stale) return i18n("Stale");
        if (card.quota_windows && card.quota_windows.length > 0) return i18n("Usage available");
        if (card.credit_meters && card.credit_meters.length > 0) return i18n("Usage available");
        return i18n("No usage data");
    }

    function syncFromProviderModel() {
        if (_syncingProviders) return;

        var order = [];
        var hidden = [];
        var firstVisible = "";
        var selectedVisible = false;
        for (var i = 0; i < providerModel.count; ++i) {
            var row = providerModel.get(i);
            order.push(row.providerId);
            if (!row.showInPopup) {
                hidden.push(row.providerId);
            } else {
                if (!firstVisible) firstVisible = row.providerId;
                if (cfg_trayProvider === row.providerId) selectedVisible = true;
            }
        }
        cfg_providerOrder = order.join(",");
        cfg_hiddenProviders = hidden.join(",");

        if ((!cfg_trayProvider || !selectedVisible) && firstVisible) {
            cfg_trayProvider = firstVisible;
        }
        syncTrayCombo();
    }

    function syncTrayCombo() {
        var selected = cfg_trayProvider ? cfg_trayProvider.toLowerCase() : "";
        for (var i = 0; i < trayProviderCombo.count; ++i) {
            if (trayProviderCombo.valueAt(i) === selected) {
                trayProviderCombo.currentIndex = i;
                return;
            }
        }
        trayProviderCombo.currentIndex = providerModel.count > 0 ? 0 : -1;
    }

    function syncTrayIconStyleCombo() {
        for (var i = 0; i < trayIconStyleCombo.count; ++i) {
            if (trayIconStyleCombo.valueAt(i) === cfg_trayIconStyle) {
                trayIconStyleCombo.currentIndex = i;
                return;
            }
        }
        trayIconStyleCombo.currentIndex = 0;
    }

    function moveProvider(from, to) {
        if (from < 0 || to < 0 || from >= providerModel.count || to >= providerModel.count) return;
        providerModel.move(from, to, 1);
        syncFromProviderModel();
    }

    Kirigami.FormLayout {
        Layout.fillWidth: true

        QQC2.TextField {
            id: snapshotPathField
            Kirigami.FormData.label: i18n("Snapshot path:")
            Layout.fillWidth: true
            placeholderText: i18n("Leave empty for $HOME/.cache/neon-codexbar/snapshot.json")
        }

        QQC2.SpinBox {
            id: warningSpin
            Kirigami.FormData.label: i18n("Warning threshold (%):")
            from: 1
            to: 100
        }

        QQC2.SpinBox {
            id: criticalSpin
            Kirigami.FormData.label: i18n("Critical threshold (%):")
            from: 1
            to: 100
        }

        QQC2.SpinBox {
            id: staleSpin
            Kirigami.FormData.label: i18n("Snapshot stale (seconds):")
            from: 30
            to: 86400
        }

        QQC2.SpinBox {
            id: deadSpin
            Kirigami.FormData.label: i18n("Daemon dead (seconds):")
            from: 60
            to: 86400
        }

        QQC2.SpinBox {
            id: pollSpin
            Kirigami.FormData.label: i18n("Polling interval (seconds):")
            from: 1
            to: 300
        }

        QQC2.ComboBox {
            id: trayModeCombo
            Kirigami.FormData.label: i18n("Tray shows:")
            textRole: "text"
            valueRole: "value"
            model: [
                {"text": i18n("Highest usage"), "value": "highest-usage"},
                {"text": i18n("Selected provider"), "value": "selected-provider"}
            ]
            onActivated: cfg_trayMode = currentValue
        }

        QQC2.ComboBox {
            id: trayIconStyleCombo
            Kirigami.FormData.label: i18n("Tray icon style:")
            textRole: "text"
            valueRole: "value"
            model: [
                {"text": i18n("Percent in ring"), "value": "percent-ring"},
                {"text": i18n("Percent only"), "value": "percent-only"},
                {"text": i18n("5h / 7d bars"), "value": "two-bars"},
                {"text": i18n("5h / 7d circles"), "value": "two-circles"},
                {"text": i18n("5h / 7d tiles"), "value": "two-tiles"}
            ]
            onActivated: cfg_trayIconStyle = currentValue
        }

        QQC2.ComboBox {
            id: trayProviderCombo
            Kirigami.FormData.label: i18n("Active in tray:")
            enabled: trayModeCombo.currentValue === "selected-provider" && providerModel.count > 0
            textRole: "displayName"
            valueRole: "providerId"
            model: providerModel
            onActivated: cfg_trayProvider = currentValue
        }

        ColumnLayout {
            Kirigami.FormData.label: i18n("Providers:")
            Layout.fillWidth: true
            spacing: Kirigami.Units.smallSpacing

            Text {
                visible: providerReadError.length > 0
                text: providerReadError
                color: Kirigami.Theme.disabledTextColor
                font.pixelSize: Kirigami.Theme.smallFont.pixelSize
                Layout.fillWidth: true
            }

            Repeater {
                model: providerModel
                delegate: Rectangle {
                    Layout.fillWidth: true
                    radius: Kirigami.Units.smallSpacing
                    color: Qt.rgba(Kirigami.Theme.textColor.r,
                                   Kirigami.Theme.textColor.g,
                                   Kirigami.Theme.textColor.b, 0.04)
                    border.color: Qt.rgba(Kirigami.Theme.textColor.r,
                                          Kirigami.Theme.textColor.g,
                                          Kirigami.Theme.textColor.b, 0.16)
                    implicitHeight: rowLayout.implicitHeight + Kirigami.Units.smallSpacing

                    RowLayout {
                        id: rowLayout
                        anchors.fill: parent
                        anchors.margins: Kirigami.Units.smallSpacing
                        spacing: Kirigami.Units.smallSpacing

                        QQC2.ToolButton {
                            icon.name: "go-up"
                            display: QQC2.AbstractButton.IconOnly
                            enabled: index > 0
                            onClicked: moveProvider(index, index - 1)
                            QQC2.ToolTip.text: i18n("Move up")
                            QQC2.ToolTip.visible: hovered
                            QQC2.ToolTip.delay: 500
                        }

                        QQC2.ToolButton {
                            icon.name: "go-down"
                            display: QQC2.AbstractButton.IconOnly
                            enabled: index < providerModel.count - 1
                            onClicked: moveProvider(index, index + 1)
                            QQC2.ToolTip.text: i18n("Move down")
                            QQC2.ToolTip.visible: hovered
                            QQC2.ToolTip.delay: 500
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 0

                            Text {
                                text: displayName
                                color: Kirigami.Theme.textColor
                                font.bold: true
                                elide: Text.ElideRight
                                Layout.fillWidth: true
                            }

                            Text {
                                text: {
                                    var bits = [providerId, statusText];
                                    if (sourceText) bits.push(sourceText);
                                    return bits.join(" • ");
                                }
                                color: Kirigami.Theme.disabledTextColor
                                font.pixelSize: Kirigami.Theme.smallFont.pixelSize
                                elide: Text.ElideRight
                                Layout.fillWidth: true
                            }
                        }

                        QQC2.CheckBox {
                            checked: showInPopup
                            text: i18n("Show")
                            onToggled: {
                                providerModel.setProperty(index, "showInPopup", checked);
                                syncFromProviderModel();
                            }
                        }

                        QQC2.RadioButton {
                            checked: cfg_trayProvider === providerId
                            enabled: showInPopup
                            onClicked: {
                                cfg_trayProvider = providerId;
                                cfg_trayMode = "selected-provider";
                            }
                            QQC2.ToolTip.text: i18n("Active in tray")
                            QQC2.ToolTip.visible: hovered
                            QQC2.ToolTip.delay: 500
                        }
                    }
                }
            }

            QQC2.Button {
                text: i18n("Reload providers")
                icon.name: "view-refresh"
                onClicked: loadProviders()
            }
        }
    }
}

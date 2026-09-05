// UsageTooltip.qml
// Rich hover tooltip content. It follows the same tray-provider selection as
// CompactRepresentation and reuses the existing quota/credit renderers.

import QtQuick
import QtQuick.Layouts
import org.kde.kirigami 2.20 as Kirigami

Item {
    id: root
    property var store
    property int warningThreshold: 70
    property int criticalThreshold: 90

    readonly property var _card: store && store.trayCard ? store.trayCard : null
    readonly property var _windows: _card && _card.quota_windows ? _card.quota_windows : []
    readonly property var _meters: _card && _card.credit_meters ? _card.credit_meters : []
    readonly property bool _hasData: _windows.length > 0 || _meters.length > 0

    implicitWidth: Kirigami.Units.gridUnit * 26
    implicitHeight: content.implicitHeight

    function providerName(card) {
        if (!card) return "";
        return card.display_name || card.provider_id || "";
    }

    function providerMeta(card) {
        if (!card) return "";
        var bits = [];
        if (card.plan) bits.push("plan: " + card.plan);
        if (card.source) bits.push(card.source);
        if (card.version) bits.push("v" + card.version);
        return bits.join(" • ");
    }

    function providerPercent(card) {
        if (!card || !store || !store._providerMaxPercent) return 0;
        return Math.round(store._providerMaxPercent(card));
    }

    function providerSummaryLine() {
        if (!store || !store.displayCards || store.displayCards.length === 0) return "";
        var bits = [];
        for (var i = 0; i < store.displayCards.length; ++i) {
            var card = store.displayCards[i];
            if (!card) continue;
            bits.push(providerName(card) + " " + providerPercent(card) + "%");
        }
        return bits.join("   ");
    }

    function fallbackText() {
        if (!store) return "Waiting for snapshot...";
        if (store.readError && store.readError.length) return store.readError;
        if (!store.codexbarAvailable) return "CodexBar not available";
        if (store.daemonDeadStale) return "Daemon snapshot is stale";
        return "No providers configured.";
    }

    ColumnLayout {
        id: content
        width: root.implicitWidth
        spacing: Kirigami.Units.smallSpacing

        Text {
            visible: !root._card
            text: root.fallbackText()
            color: Kirigami.Theme.disabledTextColor
            font.pixelSize: Kirigami.Theme.smallFont.pixelSize
            wrapMode: Text.WordWrap
            Layout.fillWidth: true
        }

        Text {
            visible: root._card
            text: root.providerName(root._card)
            color: Kirigami.Theme.textColor
            font.bold: true
            font.pixelSize: Kirigami.Theme.defaultFont.pixelSize + 1
            elide: Text.ElideRight
            Layout.fillWidth: true
        }

        Text {
            visible: text.length > 0
            text: root.providerMeta(root._card)
            color: Kirigami.Theme.disabledTextColor
            font.pixelSize: Kirigami.Theme.smallFont.pixelSize
            wrapMode: Text.WordWrap
            Layout.fillWidth: true
        }

        Text {
            visible: root.store && root.store.trayProviderMissing
            text: "Configured tray provider is hidden or missing; showing highest usage."
            color: Kirigami.Theme.neutralTextColor
            font.pixelSize: Kirigami.Theme.smallFont.pixelSize
            wrapMode: Text.WordWrap
            Layout.fillWidth: true
        }

        Text {
            visible: root._card && root._card.error_message
            text: root._card && root._card.error_message ? root._card.error_message : ""
            color: Kirigami.Theme.negativeTextColor
            font.pixelSize: Kirigami.Theme.smallFont.pixelSize
            wrapMode: Text.WordWrap
            Layout.fillWidth: true
        }

        Repeater {
            model: root._windows

            delegate: QuotaWindowBar {
                window: modelData
                warningThreshold: root.warningThreshold
                criticalThreshold: root.criticalThreshold
            }
        }

        Repeater {
            model: root._meters

            delegate: CreditMeter {
                meter: modelData
                warningThreshold: root.warningThreshold
                criticalThreshold: root.criticalThreshold
            }
        }

        Text {
            visible: root._card && !root._hasData && !(root._card && root._card.error_message)
            text: "No usage data reported"
            color: Kirigami.Theme.disabledTextColor
            font.italic: true
            Layout.fillWidth: true
        }

        Rectangle {
            visible: store && store.displayCards && store.displayCards.length > 1
            Layout.fillWidth: true
            height: 1
            color: Qt.rgba(Kirigami.Theme.textColor.r,
                           Kirigami.Theme.textColor.g,
                           Kirigami.Theme.textColor.b, 0.15)
        }

        Text {
            visible: store && store.displayCards && store.displayCards.length > 1 && text.length > 0
            text: root.providerSummaryLine()
            color: Kirigami.Theme.disabledTextColor
            font.pixelSize: Kirigami.Theme.smallFont.pixelSize
            wrapMode: Text.WordWrap
            Layout.fillWidth: true
        }
    }
}

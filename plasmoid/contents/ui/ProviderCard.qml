// ProviderCard.qml
// Renders one provider card. Provider-agnostic: never inspects display_name,
// window_label, or any provider id. Quota windows and credit meters are
// rendered as repeaters in the array order the daemon supplied.

import QtQuick
import QtQuick.Layouts
import org.kde.kirigami 2.20 as Kirigami

Rectangle {
    id: root
    property var card: ({})
    property bool daemonDeadStale: false
    property int warningThreshold: 70
    property int criticalThreshold: 90

    Layout.fillWidth: true
    radius: Kirigami.Units.smallSpacing
    color: Qt.rgba(Kirigami.Theme.textColor.r,
                   Kirigami.Theme.textColor.g,
                   Kirigami.Theme.textColor.b, 0.05)
    border.color: Qt.rgba(Kirigami.Theme.textColor.r,
                          Kirigami.Theme.textColor.g,
                          Kirigami.Theme.textColor.b, 0.20)
    border.width: 1
    implicitHeight: contentCol.implicitHeight + Kirigami.Units.largeSpacing

    // Dim the whole card if this provider is stale or the daemon is dead.
    opacity: (card && (card.is_stale || daemonDeadStale)) ? 0.55 : 1.0

    ColumnLayout {
        id: contentCol
        anchors.fill: parent
        anchors.margins: Kirigami.Units.smallSpacing
        spacing: Kirigami.Units.smallSpacing

        // Header: display_name + source/version + plan
        RowLayout {
            Layout.fillWidth: true
            spacing: Kirigami.Units.smallSpacing
            Text {
                text: (card && card.display_name) ? card.display_name : ""
                color: Kirigami.Theme.textColor
                font.bold: true
                font.pixelSize: Kirigami.Theme.defaultFont.pixelSize + 2
                elide: Text.ElideRight
                Layout.fillWidth: true
            }
            Text {
                visible: text.length > 0
                text: {
                    if (!card) return "";
                    var bits = [];
                    if (card.source) bits.push(card.source);
                    if (card.version) bits.push("v" + card.version);
                    return bits.join(" ");
                }
                color: Kirigami.Theme.disabledTextColor
                font.pixelSize: Kirigami.Theme.smallFont.pixelSize
            }
            // Stale badge — only if THIS card is in-flight stale (daemon-dead is
            // shown globally by FullRepresentation, not per card).
            Rectangle {
                visible: card && card.is_stale
                radius: 4
                color: "transparent"
                border.color: Kirigami.Theme.disabledTextColor
                implicitWidth: staleText.implicitWidth + Kirigami.Units.smallSpacing
                implicitHeight: staleText.implicitHeight + Kirigami.Units.smallSpacing / 2
                Text {
                    id: staleText
                    anchors.centerIn: parent
                    text: "stale"
                    color: Kirigami.Theme.disabledTextColor
                    font.pixelSize: Kirigami.Theme.smallFont.pixelSize
                }
            }
        }

        // Plan / login / identity (compact, optional)
        Text {
            visible: text.length > 0
            text: {
                if (!card) return "";
                var bits = [];
                if (card.plan) bits.push("plan: " + card.plan);
                if (card.login_method) bits.push(card.login_method);
                if (card.identity && card.identity.accountEmail)
                    bits.push(card.identity.accountEmail);
                return bits.join(" • ");
            }
            color: Kirigami.Theme.disabledTextColor
            font.pixelSize: Kirigami.Theme.smallFont.pixelSize
            wrapMode: Text.WordWrap
            Layout.fillWidth: true
        }

        // Per-provider error banner.
        StatusBanner {
            visible: card && card.error_message && card.error_message.length > 0
            title: card && card.error_message ? card.error_message : ""
            detail: card && card.setup_hint ? card.setup_hint : ""
            severity: "error"
        }

        // Quota windows (in given order).
        Repeater {
            model: (card && card.quota_windows) ? card.quota_windows : []
            delegate: QuotaWindowBar {
                window: modelData
                warningThreshold: root.warningThreshold
                criticalThreshold: root.criticalThreshold
            }
        }

        // Credit meters (in given order).
        Repeater {
            model: (card && card.credit_meters) ? card.credit_meters : []
            delegate: CreditMeter {
                meter: modelData
                warningThreshold: root.warningThreshold
                criticalThreshold: root.criticalThreshold
            }
        }

        // Empty-state hint when a provider has neither windows nor meters and
        // isn't reporting an error. Common for misconfigured providers.
        Text {
            visible: card && !card.error_message
                     && (!card.quota_windows || card.quota_windows.length === 0)
                     && (!card.credit_meters || card.credit_meters.length === 0)
            text: "No usage data reported"
            color: Kirigami.Theme.disabledTextColor
            font.italic: true
            Layout.fillWidth: true
        }
    }
}

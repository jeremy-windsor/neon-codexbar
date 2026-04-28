// ProviderCard.qml
// Renders one provider card. Provider-agnostic: never inspects display_name,
// window_label, or any provider id. Quota windows and credit meters are
// rendered as repeaters in the array order the daemon supplied.

import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami 2.20 as Kirigami

Rectangle {
    id: root
    property var card: ({})
    property bool daemonDeadStale: false
    property int warningThreshold: 70
    property int criticalThreshold: 90
    // Optional: SnapshotStore reference, used only for relativeAge() on the
    // last_success / last_attempt lines. Card still renders without it.
    property var store: null

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

        // Identity row: plan / login_method / account email.
        // Kept tight; the longer per-field metadata block sits below it.
        Text {
            visible: text.length > 0
            text: {
                if (!card) return "";
                var bits = [];
                if (card.plan) bits.push("plan: " + card.plan);
                if (card.login_method && card.login_method !== card.plan)
                    bits.push(card.login_method);
                if (card.identity && card.identity.accountEmail)
                    bits.push(card.identity.accountEmail);
                return bits.join(" • ");
            }
            color: Kirigami.Theme.disabledTextColor
            font.pixelSize: Kirigami.Theme.smallFont.pixelSize
            wrapMode: Text.WordWrap
            Layout.fillWidth: true
        }

        QQC2.ToolButton {
            id: detailsToggle
            visible: card && (card.provider_id || card.last_success || card.last_attempt)
            text: checked ? "Hide provider details" : "Provider details"
            checkable: true
            checked: false
            flat: true
            Layout.leftMargin: -Kirigami.Units.smallSpacing
        }

        // Per-field metadata block. Collapsed by default so routine ids and
        // timestamps do not crowd the quota bars.
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 0
            visible: detailsToggle.visible && detailsToggle.checked

            Text {
                visible: card && card.provider_id && card.provider_id.length > 0
                text: card && card.provider_id ? "id: " + card.provider_id : ""
                color: Kirigami.Theme.disabledTextColor
                font.pixelSize: Kirigami.Theme.smallFont.pixelSize
                font.family: "monospace"
                Layout.fillWidth: true
            }
            Text {
                visible: card && card.last_success
                text: {
                    if (!card || !card.last_success) return "";
                    var ago = root.store && root.store.relativeAge
                        ? root.store.relativeAge(card.last_success)
                        : card.last_success;
                    return "last success: " + ago;
                }
                color: Kirigami.Theme.disabledTextColor
                font.pixelSize: Kirigami.Theme.smallFont.pixelSize
                Layout.fillWidth: true
            }
            Text {
                // Show last_attempt only if it differs meaningfully from last_success
                // (i.e. there's been a recent failed retry).
                visible: {
                    if (!card || !card.last_attempt) return false;
                    if (!card.last_success) return true;
                    return card.last_attempt !== card.last_success;
                }
                text: {
                    if (!card || !card.last_attempt) return "";
                    var ago = root.store && root.store.relativeAge
                        ? root.store.relativeAge(card.last_attempt)
                        : card.last_attempt;
                    return "last attempt: " + ago;
                }
                color: Kirigami.Theme.disabledTextColor
                font.pixelSize: Kirigami.Theme.smallFont.pixelSize
                Layout.fillWidth: true
            }
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

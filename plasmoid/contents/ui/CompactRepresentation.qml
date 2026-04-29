// CompactRepresentation.qml
// Panel icon: a colored ring keyed off store.worstState. Theme colors only.
//
// KDE's stock Plasma 6 applets commonly use MouseArea for compact click
// activation. KDE Neon QA showed TapHandler did not open the popup here.

import QtQuick
import QtQuick.Layouts
import org.kde.plasma.plasmoid 2.0
import org.kde.kirigami 2.20 as Kirigami

Item {
    id: root
    property var store
    property var plasmoidItem
    // "percent-ring" (default) draws the colored ring with centered percent.
    // "percent-only" hides the ring and shows the percent text larger.
    property string trayIconStyle: "percent-ring"

    // Left-click toggles popup. Keep this minimal and provider-agnostic.
    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton
        onClicked: {
            if (root.plasmoidItem) {
                root.plasmoidItem.expanded = !root.plasmoidItem.expanded;
            }
        }
    }

    // Plasma sizes panel icons via Layout hints; honor them.
    Layout.minimumWidth: Kirigami.Units.iconSizes.small
    Layout.minimumHeight: Kirigami.Units.iconSizes.small
    Layout.preferredWidth: Kirigami.Units.iconSizes.medium
    Layout.preferredHeight: Kirigami.Units.iconSizes.medium

    readonly property int _dim: Math.min(parent ? parent.width : width,
                                          parent ? parent.height : height) - 2
    readonly property bool _showRing: trayIconStyle !== "percent-only"

    readonly property color ringColor: {
        if (!store) return Kirigami.Theme.textColor;
        switch (store.worstState) {
        case "critical": return Kirigami.Theme.negativeTextColor;
        case "error":    return Kirigami.Theme.negativeTextColor;
        case "warning":  return Kirigami.Theme.neutralTextColor;
        case "stale":    return Kirigami.Theme.disabledTextColor;
        case "missing":  return Kirigami.Theme.disabledTextColor;
        case "ok":
        default:         return Kirigami.Theme.positiveTextColor;
        }
    }

    // The ring. Hidden in percent-only mode; the text below scales up to
    // fill the freed space.
    Rectangle {
        id: ring
        visible: root._showRing
        anchors.centerIn: parent
        width: root._dim
        height: width
        radius: width / 2
        color: "transparent"
        border.color: ringColor
        border.width: Math.max(2, Math.round(width / 8))
        antialiasing: true
    }

    // Center label: max usage percent, or "!" if no data.
    Text {
        anchors.centerIn: parent
        text: {
            if (!store) return "";
            if (store.worstState === "missing" || store.worstState === "error") return "!";
            if (!store.cards || store.cards.length === 0) return "-";
            return Math.round(store.trayUsagePercent) + "";
        }
        color: ringColor
        // Scale up text in percent-only mode since the ring no longer
        // constrains the inner space.
        font.pixelSize: {
            var divisor = root._showRing ? 2.6 : 1.6;
            return Math.max(8, Math.round(root._dim / divisor));
        }
        font.bold: true
    }
}

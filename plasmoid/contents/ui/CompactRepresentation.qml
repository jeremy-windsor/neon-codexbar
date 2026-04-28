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

    // The ring. Drawn as a circle outline; size scales with the panel icon.
    Rectangle {
        id: ring
        anchors.centerIn: parent
        width: Math.min(parent.width, parent.height) - 2
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
            return Math.round(store.maxUsagePercent) + "";
        }
        color: ringColor
        font.pixelSize: Math.max(8, Math.round(ring.width / 2.6))
        font.bold: true
    }
}

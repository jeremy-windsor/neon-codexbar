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
    // "two-bars", "two-circles", and "two-tiles" show 5-hour and 7-day
    // usage as side-by-side mini widgets.
    property string trayIconStyle: "percent-ring"

    property var _windowItems: [
        {
            "label": store ? store.trayPrimaryLabel : "5h",
            "percent": store ? store.trayPrimaryUsagePercent : 0
        },
        {
            "label": store ? store.traySecondaryLabel : "7d",
            "percent": store ? store.traySecondaryUsagePercent : 0
        }
    ]

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
    Layout.preferredWidth: root._showMulti
        ? Kirigami.Units.iconSizes.medium * 3.2
        : Kirigami.Units.iconSizes.medium
    Layout.preferredHeight: Kirigami.Units.iconSizes.medium

    readonly property int _dim: Math.min(parent ? parent.width : width,
                                          parent ? parent.height : height) - 2
    readonly property bool _showRing: trayIconStyle === "percent-ring"
    readonly property bool _showBars: trayIconStyle === "two-bars"
    readonly property bool _showCircles: trayIconStyle === "two-circles"
    readonly property bool _showTiles: trayIconStyle === "two-tiles"
    readonly property bool _showMulti: _showBars || _showCircles || _showTiles

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
        visible: !root._showMulti
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

    ColumnLayout {
        visible: root._showBars
        anchors.centerIn: parent
        width: Math.max(64, parent.width - 4)
        spacing: 1

        Repeater {
            model: root._windowItems

            delegate: ColumnLayout {
                Layout.fillWidth: true
                spacing: 0

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 2

                    Text {
                        text: modelData.label
                        color: ringColor
                        font.pixelSize: Math.max(6, Math.round(root._dim / 5.0))
                        font.bold: true
                        Layout.preferredWidth: Math.max(10, Math.round(root._dim / 2.8))
                        horizontalAlignment: Text.AlignRight
                    }

                    Text {
                        text: Math.round(modelData.percent) + "%"
                        color: ringColor
                        font.pixelSize: Math.max(6, Math.round(root._dim / 5.0))
                        font.bold: true
                        Layout.fillWidth: true
                        horizontalAlignment: Text.AlignLeft
                    }
                }

                Rectangle {
                    Layout.fillWidth: true
                    Layout.leftMargin: 1
                    Layout.rightMargin: 1
                    height: Math.max(3, Math.round(root._dim / 7))
                    radius: height / 2
                    color: Qt.rgba(Kirigami.Theme.textColor.r,
                                   Kirigami.Theme.textColor.g,
                                   Kirigami.Theme.textColor.b, 0.18)

                    Rectangle {
                        anchors.left: parent.left
                        anchors.top: parent.top
                        anchors.bottom: parent.bottom
                        width: parent.width * (Math.max(0, Math.min(100, modelData.percent)) / 100.0)
                        radius: parent.radius
                        color: ringColor
                    }
                }
            }
        }
    }

    RowLayout {
        visible: root._showCircles
        anchors.centerIn: parent
        width: Math.max(64, parent.width - 4)
        height: Math.max(18, parent.height - 2)
        spacing: 2

        Repeater {
            model: root._windowItems

            delegate: Item {
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.minimumWidth: 28

                Rectangle {
                    id: circle
                    anchors.centerIn: parent
                    width: Math.min(parent.width, parent.height) - 3
                    height: width
                    radius: width / 2
                    color: "transparent"
                    border.color: ringColor
                    border.width: Math.max(2, Math.round(width / 10))
                    antialiasing: true
                }

                Text {
                    anchors.horizontalCenter: circle.horizontalCenter
                    anchors.verticalCenter: circle.verticalCenter
                    anchors.verticalCenterOffset: -Math.max(2, Math.round(circle.width / 10))
                    text: Math.round(modelData.percent)
                    color: ringColor
                    font.pixelSize: Math.max(7, Math.round(circle.width / 3.8))
                    font.bold: true
                }

                Text {
                    anchors.horizontalCenter: circle.horizontalCenter
                    anchors.bottom: circle.bottom
                    anchors.bottomMargin: Math.max(1, Math.round(circle.width / 10))
                    text: modelData.label
                    color: ringColor
                    font.pixelSize: Math.max(5, Math.round(circle.width / 6.2))
                    font.bold: true
                }
            }
        }
    }

    RowLayout {
        visible: root._showTiles
        anchors.centerIn: parent
        width: Math.max(64, parent.width - 4)
        height: Math.max(18, parent.height - 2)
        spacing: 2

        Repeater {
            model: root._windowItems

            delegate: Rectangle {
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.minimumWidth: 28
                radius: 3
                color: Qt.rgba(Kirigami.Theme.textColor.r,
                               Kirigami.Theme.textColor.g,
                               Kirigami.Theme.textColor.b, 0.08)
                border.color: Qt.rgba(ringColor.r, ringColor.g, ringColor.b, 0.8)
                border.width: 1

                ColumnLayout {
                    anchors.centerIn: parent
                    spacing: -3

                    Text {
                        text: modelData.label
                        color: ringColor
                        font.pixelSize: Math.max(6, Math.round(root._dim / 5.2))
                        font.bold: true
                        Layout.alignment: Qt.AlignHCenter
                    }

                    Text {
                        text: Math.round(modelData.percent) + "%"
                        color: ringColor
                        font.pixelSize: Math.max(8, Math.round(root._dim / 3.8))
                        font.bold: true
                        Layout.alignment: Qt.AlignHCenter
                    }
                }
            }
        }
    }
}

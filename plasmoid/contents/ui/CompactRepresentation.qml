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
    property string traySingleWindow: "highest"
    property bool trayShowProvider: false

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
    Layout.preferredWidth: root._basePreferredWidth + root._providerLabelWidth
    Layout.preferredHeight: Kirigami.Units.iconSizes.medium

    readonly property int _providerLabelWidth: _showProviderLabel
        ? Math.min(providerLabel.implicitWidth + Kirigami.Units.smallSpacing,
                   Kirigami.Units.gridUnit * 4)
        : 0
    readonly property int _basePreferredWidth: root._showMulti
        ? Kirigami.Units.iconSizes.medium * 2.7
        : Kirigami.Units.iconSizes.medium
    readonly property int _visualWidth: Math.max(Kirigami.Units.iconSizes.small,
                                                 (parent ? parent.width : width) - _providerLabelWidth)
    readonly property real _visualCenterOffset: _providerLabelWidth / 2
    readonly property int _dim: Math.min(_visualWidth,
                                          parent ? parent.height : height) - 2
    readonly property bool _showRing: trayIconStyle === "percent-ring"
    readonly property bool _showBars: trayIconStyle === "two-bars"
    readonly property bool _showCircles: trayIconStyle === "two-circles"
    readonly property bool _showTiles: trayIconStyle === "two-tiles"
    readonly property bool _showMulti: _showBars || _showCircles || _showTiles
    readonly property bool _showProviderLabel: trayShowProvider && store && store.trayLabel
                                            && store.trayLabel !== "max"
    readonly property real _singleUsagePercent: {
        if (!store) return 0;
        if (traySingleWindow === "primary") return store.trayPrimaryUsagePercent;
        if (traySingleWindow === "secondary") return store.traySecondaryUsagePercent;
        return store.trayUsagePercent;
    }

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
    onRingColorChanged: ring.requestPaint()
    on_SingleUsagePercentChanged: ring.requestPaint()

    Text {
        id: providerLabel
        visible: root._showProviderLabel
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        width: root._providerLabelWidth
        text: store ? store.trayLabel : ""
        color: ringColor
        font.pixelSize: Math.max(9, Math.round(root._dim / 3.6))
        font.bold: true
        elide: Text.ElideRight
        horizontalAlignment: Text.AlignLeft
        verticalAlignment: Text.AlignVCenter
    }

    Canvas {
        id: ring
        visible: root._showRing
        anchors.centerIn: parent
        anchors.horizontalCenterOffset: root._visualCenterOffset
        width: root._dim
        height: width
        antialiasing: true

        onPaint: {
            var ctx = getContext("2d");
            ctx.reset();
            var lineWidth = Math.max(2, Math.round(width / 8));
            var radius = width / 2 - lineWidth / 2;
            var center = width / 2;
            var start = -Math.PI / 2;
            var pct = Math.max(0, Math.min(100, root._singleUsagePercent)) / 100.0;

            ctx.lineWidth = lineWidth;
            ctx.lineCap = "round";
            ctx.strokeStyle = Qt.rgba(Kirigami.Theme.textColor.r,
                                      Kirigami.Theme.textColor.g,
                                      Kirigami.Theme.textColor.b, 0.18);
            ctx.beginPath();
            ctx.arc(center, center, radius, 0, Math.PI * 2, false);
            ctx.stroke();

            if (pct > 0) {
                ctx.strokeStyle = root.ringColor;
                ctx.beginPath();
                ctx.arc(center, center, radius, start, start + Math.PI * 2 * pct, false);
                ctx.stroke();
            }
        }
    }

    // Center label: max usage percent, or "!" if no data.
    Text {
        visible: !root._showMulti
        anchors.centerIn: parent
        anchors.horizontalCenterOffset: root._visualCenterOffset
        text: {
            if (!store) return "";
            if (store.worstState === "missing" || store.worstState === "error") return "!";
            if (!store.cards || store.cards.length === 0) return "-";
            return Math.round(root._singleUsagePercent) + "";
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
        anchors.horizontalCenterOffset: root._visualCenterOffset
        width: Math.max(54, root._visualWidth - 2)
        spacing: 1

        Repeater {
            model: root._windowItems

            delegate: ColumnLayout {
                Layout.fillWidth: true
                spacing: 0

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 3

                    Text {
                        text: modelData.label
                        color: ringColor
                        font.pixelSize: Math.max(9, Math.round(root._dim / 3.7))
                        font.bold: true
                        Layout.preferredWidth: Math.max(16, Math.round(root._dim / 1.9))
                        horizontalAlignment: Text.AlignRight
                    }

                    Rectangle {
                        Layout.fillWidth: true
                        height: Math.max(4, Math.round(root._dim / 6.2))
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

                    Text {
                        text: Math.round(modelData.percent) + "%"
                        color: ringColor
                        font.pixelSize: Math.max(9, Math.round(root._dim / 3.7))
                        font.bold: true
                        Layout.preferredWidth: Math.max(22, Math.round(root._dim / 1.4))
                        horizontalAlignment: Text.AlignLeft
                    }
                }
            }
        }
    }

    RowLayout {
        visible: root._showCircles
        anchors.centerIn: parent
        anchors.horizontalCenterOffset: root._visualCenterOffset
        width: Math.max(52, root._visualWidth - 2)
        height: Math.max(18, parent.height - 2)
        spacing: 2

        Repeater {
            model: root._windowItems

            delegate: RowLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.minimumWidth: 25
                spacing: 1

                Text {
                    text: modelData.label
                    color: ringColor
                    font.pixelSize: Math.max(10, Math.round(root._dim / 3.5))
                    font.bold: true
                    Layout.alignment: Qt.AlignVCenter
                }

                Item {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    Layout.minimumWidth: 16

                    Rectangle {
                        id: circle
                        anchors.centerIn: parent
                        width: Math.min(parent.width, parent.height) - 2
                        height: width
                        radius: width / 2
                        color: "transparent"
                        border.color: ringColor
                        border.width: Math.max(2, Math.round(width / 10))
                        antialiasing: true
                    }

                    Text {
                        anchors.centerIn: circle
                        text: Math.round(modelData.percent)
                        color: ringColor
                        font.pixelSize: Math.max(8, Math.round(circle.width / 3.2))
                        font.bold: true
                    }
                }
            }
        }
    }

    RowLayout {
        visible: root._showTiles
        anchors.centerIn: parent
        anchors.horizontalCenterOffset: root._visualCenterOffset
        width: Math.max(50, root._visualWidth - 2)
        height: Math.max(18, parent.height - 2)
        spacing: 1

        Repeater {
            model: root._windowItems

            delegate: Rectangle {
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.minimumWidth: 23
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
                        font.pixelSize: Math.max(8, Math.round(root._dim / 4.2))
                        font.bold: true
                        Layout.alignment: Qt.AlignHCenter
                    }

                    Text {
                        text: Math.round(modelData.percent) + "%"
                        color: ringColor
                        font.pixelSize: Math.max(9, Math.round(root._dim / 3.5))
                        font.bold: true
                        Layout.alignment: Qt.AlignHCenter
                    }
                }
            }
        }
    }
}

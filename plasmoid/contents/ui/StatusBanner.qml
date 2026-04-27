// StatusBanner.qml
// Single banner component reused for global setup / daemon-dead / per-card
// errors. Color via severity prop ("error" | "warning" | "info" | "stale").

import QtQuick
import QtQuick.Layouts
import org.kde.kirigami 2.20 as Kirigami

Rectangle {
    id: root
    property string title: ""
    property string detail: ""
    property string severity: "error"  // error | warning | info | stale

    visible: title.length > 0 || detail.length > 0
    Layout.fillWidth: true
    radius: Kirigami.Units.smallSpacing
    color: {
        switch (severity) {
        case "error":   return Qt.rgba(Kirigami.Theme.negativeTextColor.r,
                                       Kirigami.Theme.negativeTextColor.g,
                                       Kirigami.Theme.negativeTextColor.b, 0.12);
        case "warning": return Qt.rgba(Kirigami.Theme.neutralTextColor.r,
                                       Kirigami.Theme.neutralTextColor.g,
                                       Kirigami.Theme.neutralTextColor.b, 0.12);
        case "stale":   return Qt.rgba(Kirigami.Theme.disabledTextColor.r,
                                       Kirigami.Theme.disabledTextColor.g,
                                       Kirigami.Theme.disabledTextColor.b, 0.12);
        case "info":
        default:        return Qt.rgba(Kirigami.Theme.textColor.r,
                                       Kirigami.Theme.textColor.g,
                                       Kirigami.Theme.textColor.b, 0.08);
        }
    }
    border.color: {
        switch (severity) {
        case "error":   return Kirigami.Theme.negativeTextColor;
        case "warning": return Kirigami.Theme.neutralTextColor;
        case "stale":   return Kirigami.Theme.disabledTextColor;
        case "info":
        default:        return Kirigami.Theme.textColor;
        }
    }
    border.width: 1
    implicitHeight: contentCol.implicitHeight + Kirigami.Units.smallSpacing * 2

    ColumnLayout {
        id: contentCol
        anchors.fill: parent
        anchors.margins: Kirigami.Units.smallSpacing
        spacing: Kirigami.Units.smallSpacing / 2

        Text {
            visible: root.title.length > 0
            text: root.title
            // Use textColor for the title rather than the border severity color
            // — neutralTextColor / disabledTextColor against a 0.12-alpha bg of
            // the same hue gives near-zero contrast.
            color: Kirigami.Theme.textColor
            font.bold: true
            wrapMode: Text.WordWrap
            Layout.fillWidth: true
        }
        Text {
            visible: root.detail.length > 0
            text: root.detail
            color: Kirigami.Theme.textColor
            wrapMode: Text.WordWrap
            Layout.fillWidth: true
        }
    }
}

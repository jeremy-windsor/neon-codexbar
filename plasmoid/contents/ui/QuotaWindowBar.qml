// QuotaWindowBar.qml
// Renders one quota window. Label fallback: window_label > reset_description > id.
// reset_description is also shown as the secondary line when present (e.g. z.ai's
// "1-minute window" or codex's "11:02 AM"); resets_at appears parenthetically.
//
// used_percent may be null (rare); if so we show a textless bar and the words
// "no usage data".

import QtQuick
import QtQuick.Layouts
import org.kde.kirigami 2.20 as Kirigami

ColumnLayout {
    id: root
    Layout.fillWidth: true
    spacing: Kirigami.Units.smallSpacing / 2

    property var window: ({})
    property int warningThreshold: 70
    property int criticalThreshold: 90

    readonly property string _primaryLabel: {
        if (window.window_label) return window.window_label;
        if (window.reset_description) return window.reset_description;
        if (window.id) return window.id;
        return "";
    }

    readonly property bool _hasPercent: typeof window.used_percent === "number"
                                        && !isNaN(window.used_percent)
    readonly property real _percent: _hasPercent ? Math.max(0, Math.min(100, window.used_percent)) : 0
    readonly property int _displayPercent: _hasPercent ? Math.round(window.used_percent) : 0

    readonly property color _barColor: {
        if (!_hasPercent) return Kirigami.Theme.disabledTextColor;
        if (_percent >= criticalThreshold) return Kirigami.Theme.negativeTextColor;
        if (_percent >= warningThreshold) return Kirigami.Theme.neutralTextColor;
        return Kirigami.Theme.positiveTextColor;
    }

    readonly property string _resetLine: {
        // Avoid duplicating the description when window_label was empty and we
        // already used reset_description as the primary label.
        var rd = window.reset_description || "";
        var ra = _formatReset(window.resets_at || "");
        var parts = [];
        if (rd && _primaryLabel !== rd) parts.push(rd);
        else if (rd && _primaryLabel === rd) {
            // already shown
        }
        if (ra) parts.push("resets " + ra);
        return parts.join(" • ");
    }

    function _formatReset(iso) {
        if (!iso || iso.length === 0) return "";
        var d = new Date(iso);
        if (isNaN(d.getTime())) return iso;
        return d.toLocaleString(Qt.locale(), Locale.ShortFormat);
    }

    RowLayout {
        Layout.fillWidth: true
        spacing: Kirigami.Units.smallSpacing
        Text {
            text: root._primaryLabel
            color: Kirigami.Theme.textColor
            font.bold: true
            elide: Text.ElideRight
            Layout.fillWidth: true
        }
        Text {
            text: root._hasPercent ? root._displayPercent + "%" : "—"
            color: root._barColor
            font.bold: true
        }
    }

    // Bar
    Rectangle {
        Layout.fillWidth: true
        height: Kirigami.Units.smallSpacing * 1.2
        radius: height / 2
        color: Qt.rgba(Kirigami.Theme.textColor.r,
                       Kirigami.Theme.textColor.g,
                       Kirigami.Theme.textColor.b, 0.15)

        Rectangle {
            anchors.left: parent.left
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            width: parent.width * (root._percent / 100.0)
            radius: parent.radius
            color: root._barColor
            visible: root._hasPercent
        }
    }

    Text {
        visible: root._resetLine.length > 0 || !root._hasPercent
        text: root._hasPercent ? root._resetLine : "no usage data"
        color: Kirigami.Theme.disabledTextColor
        font.pixelSize: Kirigami.Theme.smallFont.pixelSize
        wrapMode: Text.WordWrap
        Layout.fillWidth: true
    }
}

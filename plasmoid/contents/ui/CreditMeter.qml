// CreditMeter.qml
// Renders one credit/balance meter. Behavior depends on which fields exist:
//   - used_percent present → render a bar with label and "used / total" text
//   - balance only         → text-only (e.g. OpenRouter Key Quota in some snapshots)
//   - balance + total      → bar + monetary detail
// We do not assume currency formatting beyond "{currency} {amount}" style.

import QtQuick
import QtQuick.Layouts
import org.kde.kirigami 2.20 as Kirigami

ColumnLayout {
    id: root
    Layout.fillWidth: true
    spacing: Kirigami.Units.smallSpacing / 2

    property var meter: ({})
    property int warningThreshold: 70
    property int criticalThreshold: 90

    readonly property bool _hasPct: typeof meter.used_percent === "number"
                                    && !isNaN(meter.used_percent)
    readonly property real _pct: _hasPct ? Math.max(0, Math.min(100, meter.used_percent)) : 0
    readonly property int _displayPct: _hasPct ? Math.round(meter.used_percent) : 0

    readonly property color _barColor: {
        if (!_hasPct) return Kirigami.Theme.disabledTextColor;
        if (_pct >= criticalThreshold) return Kirigami.Theme.negativeTextColor;
        if (_pct >= warningThreshold) return Kirigami.Theme.neutralTextColor;
        return Kirigami.Theme.positiveTextColor;
    }

    function _fmt(v) {
        if (typeof v !== "number" || isNaN(v)) return null;
        // Trim to 2 decimals; avoid scientific notation.
        return (Math.round(v * 100) / 100).toString();
    }

    readonly property string _detail: {
        var cur = meter.currency ? meter.currency + " " : "";
        var bal = _fmt(meter.balance);
        var used = _fmt(meter.used);
        var total = _fmt(meter.total);
        var parts = [];
        if (bal !== null) parts.push("balance " + cur + bal);
        if (used !== null && total !== null) parts.push("used " + cur + used + " / " + cur + total);
        else if (used !== null) parts.push("used " + cur + used);
        else if (total !== null) parts.push("total " + cur + total);
        return parts.join(" • ");
    }

    RowLayout {
        Layout.fillWidth: true
        spacing: Kirigami.Units.smallSpacing
        Text {
            text: meter.label || "Credits"
            color: Kirigami.Theme.textColor
            font.bold: true
            elide: Text.ElideRight
            Layout.fillWidth: true
        }
        Text {
            visible: root._hasPct
            text: root._displayPct + "%"
            color: root._barColor
            font.bold: true
        }
    }

    // Bar — only when used_percent exists.
    Rectangle {
        visible: root._hasPct
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
            width: parent.width * (root._pct / 100.0)
            radius: parent.radius
            color: root._barColor
        }
    }

    Text {
        visible: root._detail.length > 0
        text: root._detail
        color: Kirigami.Theme.disabledTextColor
        font.pixelSize: Kirigami.Theme.smallFont.pixelSize
        wrapMode: Text.WordWrap
        Layout.fillWidth: true
    }
}

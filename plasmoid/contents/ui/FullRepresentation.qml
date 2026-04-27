// FullRepresentation.qml
// Popup contents: header (title, generated_at, refresh button), global banners,
// scrollable provider cards, collapsible diagnostics.

import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.plasma.plasmoid 2.0
import org.kde.plasma.components 3.0 as PlasmaComponents
import org.kde.kirigami 2.20 as Kirigami

Item {
    id: root
    property var store

    Layout.minimumWidth: Kirigami.Units.gridUnit * 22
    Layout.minimumHeight: Kirigami.Units.gridUnit * 18
    Layout.preferredWidth: Kirigami.Units.gridUnit * 26
    Layout.preferredHeight: Kirigami.Units.gridUnit * 24

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: Kirigami.Units.smallSpacing
        spacing: Kirigami.Units.smallSpacing

        // ----- Header -----
        RowLayout {
            Layout.fillWidth: true
            spacing: Kirigami.Units.smallSpacing

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0
                Text {
                    text: "neon-codexbar"
                    color: Kirigami.Theme.textColor
                    font.bold: true
                    font.pixelSize: Kirigami.Theme.defaultFont.pixelSize + 3
                }
                Text {
                    text: {
                        if (!store) return "";
                        if (store.readError && store.readError.length) return "snapshot unavailable";
                        var bits = [];
                        if (store.generatedAt) bits.push("updated " + store.relativeAge(store.generatedAt));
                        if (store.codexbarVersion) bits.push(store.codexbarVersion);
                        return bits.join(" • ");
                    }
                    color: Kirigami.Theme.disabledTextColor
                    font.pixelSize: Kirigami.Theme.smallFont.pixelSize
                    wrapMode: Text.WordWrap
                    Layout.fillWidth: true
                }
            }

            PlasmaComponents.ToolButton {
                icon.name: "view-refresh"
                text: "Refresh"
                display: PlasmaComponents.AbstractButton.IconOnly
                onClicked: if (store) store.requestRefresh()
                QQC2.ToolTip.text: "Touch refresh sentinel"
                QQC2.ToolTip.visible: hovered
                QQC2.ToolTip.delay: 500
            }
        }

        // ----- Global banners -----
        StatusBanner {
            visible: store && store.readError && store.readError.length > 0
            title: "Snapshot unavailable"
            detail: store ? store.readError : ""
            severity: "error"
        }
        StatusBanner {
            visible: store && !store.readError && (!store.snapshotOk || !store.codexbarAvailable)
            title: "CodexBar setup needed"
            detail: store && !store.codexbarAvailable
                ? "The neon-codexbar daemon could not locate the CodexBar binary."
                : "The daemon reported a global problem (snapshot.ok=false)."
            severity: "error"
        }
        StatusBanner {
            visible: store && !store.readError && store.snapshotOk && store.daemonDeadStale
            title: "Daemon may be stopped"
            detail: store ? "No fresh snapshot since " + store.relativeAge(store.generatedAt) : ""
            severity: "stale"
        }
        StatusBanner {
            visible: store && !store.readError && store.snapshotOk
                     && !store.daemonDeadStale && store.daemonStaleWarning
            title: "Snapshot is getting old"
            detail: store ? "Last update " + store.relativeAge(store.generatedAt) : ""
            severity: "warning"
        }

        // ----- Provider cards (scrollable) -----
        QQC2.ScrollView {
            id: scroll
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            contentWidth: availableWidth   // makes inner ColumnLayout track popup width

            ColumnLayout {
                // Bind to the ScrollView's available width so we don't fight
                // its content size manager (avoids Plasma 6 binding loops).
                width: scroll.availableWidth
                spacing: Kirigami.Units.smallSpacing

                Repeater {
                    model: store ? store.cards : []
                    delegate: ProviderCard {
                        card: modelData
                        daemonDeadStale: store ? store.daemonDeadStale : false
                        warningThreshold: store ? store.warningThreshold : 70
                        criticalThreshold: store ? store.criticalThreshold : 90
                    }
                }

                Text {
                    visible: store && !store.readError && store.cards
                             && store.cards.length === 0
                    text: "No providers configured."
                    color: Kirigami.Theme.disabledTextColor
                    font.italic: true
                    Layout.fillWidth: true
                    horizontalAlignment: Text.AlignHCenter
                }

                // ----- Diagnostics (collapsible, secondary) -----
                Item {
                    Layout.fillWidth: true
                    visible: store && store.diagnostics && store.diagnostics.length > 0
                    implicitHeight: diagCol.implicitHeight

                    ColumnLayout {
                        id: diagCol
                        anchors.left: parent.left
                        anchors.right: parent.right
                        spacing: 0

                        PlasmaComponents.ToolButton {
                            id: diagToggle
                            text: (checked ? "Hide" : "Show") + " diagnostics ("
                                  + (store && store.diagnostics ? store.diagnostics.length : 0) + ")"
                            checkable: true
                            checked: false
                            flat: true
                        }

                        Rectangle {
                            visible: diagToggle.checked
                            Layout.fillWidth: true
                            color: Qt.rgba(Kirigami.Theme.textColor.r,
                                           Kirigami.Theme.textColor.g,
                                           Kirigami.Theme.textColor.b, 0.04)
                            radius: Kirigami.Units.smallSpacing
                            implicitHeight: diagText.implicitHeight + Kirigami.Units.smallSpacing * 2
                            Text {
                                id: diagText
                                anchors.fill: parent
                                anchors.margins: Kirigami.Units.smallSpacing
                                text: store && store.diagnostics
                                      ? store.diagnostics.join("\n")
                                      : ""
                                color: Kirigami.Theme.disabledTextColor
                                font.pixelSize: Kirigami.Theme.smallFont.pixelSize
                                wrapMode: Text.WordWrap
                            }
                        }
                    }
                }
            }
        }
    }
}

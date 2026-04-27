import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami 2.20 as Kirigami

// Standard Plasma 6 KConfigXT pattern: properties named cfg_<entry> are
// auto-bound to the matching <entry name> in main.xml via plasma's config dialog.
Kirigami.FormLayout {
    id: root

    property alias cfg_snapshotPath: snapshotPathField.text
    property alias cfg_warningThreshold: warningSpin.value
    property alias cfg_criticalThreshold: criticalSpin.value
    property alias cfg_daemonStaleThreshold: staleSpin.value
    property alias cfg_daemonDeadThreshold: deadSpin.value
    property alias cfg_pollingInterval: pollSpin.value

    QQC2.TextField {
        id: snapshotPathField
        Kirigami.FormData.label: i18n("Snapshot path:")
        Layout.fillWidth: true
        placeholderText: i18n("Leave empty for $HOME/.cache/neon-codexbar/snapshot.json")
    }

    QQC2.SpinBox {
        id: warningSpin
        Kirigami.FormData.label: i18n("Warning threshold (%):")
        from: 1
        to: 100
    }

    QQC2.SpinBox {
        id: criticalSpin
        Kirigami.FormData.label: i18n("Critical threshold (%):")
        from: 1
        to: 100
    }

    QQC2.SpinBox {
        id: staleSpin
        Kirigami.FormData.label: i18n("Snapshot stale (seconds):")
        from: 30
        to: 86400
    }

    QQC2.SpinBox {
        id: deadSpin
        Kirigami.FormData.label: i18n("Daemon dead (seconds):")
        from: 60
        to: 86400
    }

    QQC2.SpinBox {
        id: pollSpin
        Kirigami.FormData.label: i18n("Polling interval (seconds):")
        from: 1
        to: 300
    }
}

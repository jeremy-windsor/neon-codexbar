import QtQuick
import QtQuick.Window
import "../../plasmoid/contents/ui" as Widget

Window {
    width: 320
    height: 200
    visible: false

    Widget.SnapshotStore {
        id: store
        snapshotPath: "/tmp/neon-codexbar-qml-smoke-missing.json"
    }

    Timer {
        interval: 0
        running: true
        repeat: false
        onTriggered: {
            var items = store._trayWindowItemsForCard({
                "quota_windows": [
                    {"id": "primary", "window_label": "Weekly", "used_percent": 66}
                ]
            });
            if (items.length !== 1 || items[0].label !== "Weekly" || items[0].percent !== 66) {
                console.error("Weekly tray window was not preserved");
                Qt.exit(1);
                return;
            }
            if (store._providerErrorSeverity({
                    "error_message": "timeout",
                    "error_severity": "warning"
                }) !== "warning") {
                console.error("Provider warning severity was not preserved");
                Qt.exit(1);
                return;
            }
            Qt.exit(0);
        }
    }
}

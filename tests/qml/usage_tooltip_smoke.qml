import QtQuick
import QtQuick.Window
import "../../plasmoid/contents/ui" as Widget

Window {
    id: root
    width: 480
    height: 360
    visible: false

    QtObject {
        id: fakeStore
        property bool trayProviderMissing: false
        property var displayCards: [
            {
                "display_name": "Claude Code",
                "provider_id": "claude",
                "plan": "Claude Pro",
                "source": "oauth",
                "version": "2.1.195",
                "quota_windows": [
                    {
                        "window_label": "5-hour window",
                        "used_percent": 75,
                        "reset_description": "Jun 28 at 12:00PM",
                        "resets_at": "2026-06-28T19:00:00Z"
                    },
                    {
                        "window_label": "7-day window",
                        "used_percent": 75,
                        "reset_description": "Jun 29 at 7:00AM",
                        "resets_at": "2026-06-29T14:00:00Z"
                    }
                ],
                "credit_meters": []
            }
        ]
        property var trayCard: displayCards[0]

        function _providerMaxPercent() {
            return 75;
        }
    }

    Widget.UsageTooltip {
        id: tooltip
        store: fakeStore
        warningThreshold: 70
        criticalThreshold: 90
    }

    Timer {
        interval: 0
        running: true
        repeat: false
        onTriggered: {
            if (tooltip.implicitWidth <= 0 || tooltip.implicitHeight <= 0) {
                console.error("UsageTooltip did not produce a visible layout");
                Qt.exit(1);
                return;
            }
            Qt.exit(0);
        }
    }
}

// main.qml
// Plasma 6 entry point. Owns the SnapshotStore and exposes it to compact/full
// representations. All file I/O lives in SnapshotStore.qml.

import QtQuick
import org.kde.plasma.plasmoid 2.0

PlasmoidItem {
    id: root

    // Inject KConfigXT-backed properties into the store so changes apply live.
    SnapshotStore {
        id: store
        snapshotPath: Plasmoid.configuration.snapshotPath
        warningThreshold: Plasmoid.configuration.warningThreshold
        criticalThreshold: Plasmoid.configuration.criticalThreshold
        daemonStaleThresholdSec: Plasmoid.configuration.daemonStaleThreshold
        daemonDeadThresholdSec: Plasmoid.configuration.daemonDeadThreshold
        pollingInterval: Plasmoid.configuration.pollingInterval
        providerOrder: Plasmoid.configuration.providerOrder
        hiddenProviders: Plasmoid.configuration.hiddenProviders
        trayProvider: Plasmoid.configuration.trayProvider
        trayMode: Plasmoid.configuration.trayMode
    }

    // Keep both representations referencing the same store via property aliases.
    property alias snapshotStore: store

    preferredRepresentation: compactRepresentation
    compactRepresentation: CompactRepresentation {
        store: root.snapshotStore
        plasmoidItem: root
        trayIconStyle: Plasmoid.configuration.trayIconStyle
        traySingleWindow: Plasmoid.configuration.traySingleWindow
    }
    fullRepresentation: FullRepresentation {
        store: root.snapshotStore
        plasmoidItem: root
    }

    // toolTipMainText/toolTipSubText still parse on Plasma 6 but emit
    // deprecation warnings; toolTipItem is the long-term API. For v1 we keep
    // the simple string form — migrate to toolTipItem when we add an icon
    // alongside the text.
    toolTipMainText: "neon-codexbar"
    toolTipSubText: {
        if (store.readError && store.readError.length) return store.readError;
        if (!store.codexbarAvailable) return "CodexBar not available";
        if (store.daemonDeadStale) return "Daemon snapshot is stale";
        if (store.cards && store.cards.length)
            return store.cards.length + " providers • "
                + store.trayLabel + " " + Math.round(store.trayUsagePercent) + "%";
        return "No providers";
    }
}

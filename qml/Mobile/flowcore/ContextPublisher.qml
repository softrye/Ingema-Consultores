import QtQuick

// Non-visual QML adapter for the host dock context. A surface declares what
// it needs (ownerId, contextId, semantic actions) and handles `command`.
// It carries no geometry and never draws anything.
QtObject {
    id: publisher

    property string ownerId: ""
    property string contextId: ""
    property var actions: []
    property bool active: true
    property bool ready: true

    signal command(string commandId)

    function publish() {
        if (!active || !ready || ownerId.length === 0 || contextId.length === 0)
            return
        if (typeof dockContextController === "undefined" || !dockContextController)
            return
        dockContextController.publishContext(ownerId, contextId, actions, "qml")
    }

    function clear() {
        if (ownerId.length === 0)
            return
        if (typeof dockContextController === "undefined" || !dockContextController)
            return
        dockContextController.clearContext(ownerId)
    }

    onActionsChanged: Qt.callLater(publish)
    onReadyChanged: { if (ready) Qt.callLater(publish) }
    onContextIdChanged: Qt.callLater(publish)
    onActiveChanged: active ? Qt.callLater(publish) : clear()
    Component.onCompleted: Qt.callLater(publish)
    // An inactive publisher never published, so it must not clear an owner
    // context that another (active) publisher of the same owner holds.
    Component.onDestruction: {
        if (active)
            clear()
    }

    property Connections routerConnection: Connections {
        target: typeof dockCommandRouter !== "undefined" ? dockCommandRouter : null
        function onQmlCommand(ownerId, contextId, commandId, dispatchId) {
            if (ownerId !== publisher.ownerId)
                return
            try {
                if (publisher.active && contextId === publisher.contextId)
                    publisher.command(commandId)
            } finally {
                dockCommandRouter.complete(dispatchId)
            }
        }
    }
}

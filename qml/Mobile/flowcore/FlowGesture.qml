import QtQuick 2.15

Item {
    id: root

    readonly property int priorityNavigation: 10
    readonly property int priorityComponent: 20
    readonly property int priorityInternalDrag: 30
    readonly property int priorityMap: 40

    property int priority: priorityComponent
    property bool tapEnabled: true
    property bool doubleTapEnabled: true
    property bool longPressEnabled: true
    property bool horizontalSwipeEnabled: false
    property bool verticalSwipeEnabled: false
    property bool dragEnabled: false
    property bool pinchEnabled: false
    property real swipeThreshold: 48
    property real dragThreshold: 8

    property point pressPoint: Qt.point(0, 0)
    property point lastPoint: Qt.point(0, 0)

    signal tapped(real x, real y)
    signal doubleTapped(real x, real y)
    signal longPressed(real x, real y)
    signal horizontalSwiped(int direction, real distance)
    signal verticalSwiped(int direction, real distance)
    signal dragStarted(real x, real y)
    signal dragged(real deltaX, real deltaY)
    signal dragFinished(real deltaX, real deltaY)
    signal pinched(real scale)

    MouseArea {
        id: pointerArea
        anchors.fill: parent
        enabled: root.tapEnabled || root.doubleTapEnabled
                 || root.longPressEnabled || root.horizontalSwipeEnabled
                 || root.verticalSwipeEnabled || root.dragEnabled
        hoverEnabled: true
        preventStealing: root.priority >= root.priorityInternalDrag
        pressAndHoldInterval: 520

        onPressed: function(mouse) {
            root.pressPoint = Qt.point(mouse.x, mouse.y)
            root.lastPoint = root.pressPoint
            if (root.dragEnabled)
                root.dragStarted(mouse.x, mouse.y)
        }

        onPositionChanged: function(mouse) {
            if (!pressed)
                return
            var dx = mouse.x - root.lastPoint.x
            var dy = mouse.y - root.lastPoint.y
            root.lastPoint = Qt.point(mouse.x, mouse.y)
            if (root.dragEnabled
                    && (Math.abs(mouse.x - root.pressPoint.x) >= root.dragThreshold
                        || Math.abs(mouse.y - root.pressPoint.y) >= root.dragThreshold))
                root.dragged(dx, dy)
        }

        onClicked: function(mouse) {
            if (root.tapEnabled)
                root.tapped(mouse.x, mouse.y)
        }

        onDoubleClicked: function(mouse) {
            if (root.doubleTapEnabled)
                root.doubleTapped(mouse.x, mouse.y)
        }

        onPressAndHold: function(mouse) {
            if (root.longPressEnabled)
                root.longPressed(mouse.x, mouse.y)
        }

        onReleased: function(mouse) {
            var dx = mouse.x - root.pressPoint.x
            var dy = mouse.y - root.pressPoint.y
            if (root.horizontalSwipeEnabled
                    && Math.abs(dx) >= root.swipeThreshold
                    && Math.abs(dx) > Math.abs(dy))
                root.horizontalSwiped(dx < 0 ? 1 : -1, Math.abs(dx))
            if (root.verticalSwipeEnabled
                    && Math.abs(dy) >= root.swipeThreshold
                    && Math.abs(dy) > Math.abs(dx))
                root.verticalSwiped(dy < 0 ? 1 : -1, Math.abs(dy))
            if (root.dragEnabled)
                root.dragFinished(dx, dy)
        }
    }

    PinchHandler {
        id: pinchHandler
        enabled: root.pinchEnabled
        target: null
        onActiveScaleChanged: root.pinched(activeScale)
    }
}

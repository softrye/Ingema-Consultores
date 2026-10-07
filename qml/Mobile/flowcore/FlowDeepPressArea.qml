import QtQuick 2.15

Item {
    id: root

    property var flow: null
    property string contextName: "default"
    property int importance: 1
    property bool deepPressEnabled: true
    property real holdProgress: 0.0
    property bool deepPressTriggered: false
    property real pressStartX: 0.0
    property real pressStartY: 0.0

    readonly property var policy:
        flow && flow.deepPressPolicy
        ? flow.deepPressPolicy(contextName, importance)
        : ({
               enabled: true,
               holdDuration: 420,
               cancelDistance: 17,
               readyScale: 1.04,
               pressedScale: 0.97
           })

    readonly property bool pressed: pointerArea.pressed
    readonly property bool armed:
        pressed
        && deepPressEnabled
        && policy.enabled
        && holdProgress > 0.01

    signal tapped()
    signal deepPressed(real globalX, real globalY)
    signal canceled()

    function resetProgress(animated) {
        holdAnimation.stop()

        if (animated && flow && flow.motionAllowed) {
            resetAnimation.from = holdProgress
            resetAnimation.to = 0.0
            resetAnimation.duration = flow.deepPressResetDuration
            resetAnimation.restart()
        } else {
            holdProgress = 0.0
        }
    }

    function cancelHold(animated) {
        holdTimer.stop()
        if (!deepPressTriggered)
            resetProgress(animated)
    }

    Timer {
        id: holdTimer
        interval: Math.max(180, Number(root.policy.holdDuration) || 420)
        repeat: false

        onTriggered: {
            if (!pointerArea.pressed
                    || root.deepPressTriggered
                    || !root.deepPressEnabled
                    || !root.policy.enabled)
                return

            root.deepPressTriggered = true
            root.holdProgress = 1.0

            var point = root.mapToItem(null, root.width / 2, 0)
            root.deepPressed(point.x, point.y)
        }
    }

    NumberAnimation {
        id: holdAnimation
        target: root
        property: "holdProgress"
        from: 0.0
        to: 1.0
        easing.type: Easing.InOutQuad
    }

    NumberAnimation {
        id: resetAnimation
        target: root
        property: "holdProgress"
        easing.type: root.flow ? root.flow.easeOut : Easing.OutCubic
    }

    MouseArea {
        id: pointerArea
        anchors.fill: parent
        hoverEnabled: true
        preventStealing: root.deepPressTriggered

        onPressed: function(mouse) {
            root.pressStartX = mouse.x
            root.pressStartY = mouse.y
            root.deepPressTriggered = false
            root.holdProgress = 0.0

            if (root.deepPressEnabled && root.policy.enabled) {
                holdAnimation.duration = Math.max(
                            180,
                            Number(root.policy.holdDuration) || 420
                        )
                holdAnimation.restart()
                holdTimer.restart()
            }
        }

        onPositionChanged: function(mouse) {
            if (!pressed || root.deepPressTriggered)
                return

            var dx = mouse.x - root.pressStartX
            var dy = mouse.y - root.pressStartY
            var distance = Math.sqrt(dx * dx + dy * dy)

            if (distance > (Number(root.policy.cancelDistance) || 17))
                root.cancelHold(true)
        }

        onReleased: function(mouse) {
            holdTimer.stop()

            if (!root.deepPressTriggered)
                root.tapped()

            root.resetProgress(true)
            root.deepPressTriggered = false
        }

        onCanceled: {
            holdTimer.stop()
            root.deepPressTriggered = false
            root.resetProgress(true)
            root.canceled()
        }

        onExited: {
            if (pressed && !root.deepPressTriggered)
                root.cancelHold(true)
        }
    }
}

import QtQuick 2.15

Item {
    id: root

    property var flow: null
    property color rippleColor: "#2A0654A2"
    property bool clipRipple: true
    property real cornerRadius: 0

    anchors.fill: parent
    clip: clipRipple
    visible: enabled && circle.opacity > 0.001
    z: 999

    function trigger(px, py) {
        if (!enabled)
            return
        var d = flow && flow.rippleDiameter ? flow.rippleDiameter(width, height) : Math.max(width, height) * 2.2
        var cx = Math.max(-d, Math.min(width + d, Number(px)))
        var cy = Math.max(-d, Math.min(height + d, Number(py)))
        circle.width = 12
        circle.height = 12
        circle.x = cx - 6
        circle.y = cy - 6
        circle.opacity = 0.24
        circle.scale = 1.0
        circle.targetDiameter = d
        circle.targetX = cx - d / 2
        circle.targetY = cy - d / 2
        ripple.restart()
    }

    Rectangle {
        id: circle
        property real targetDiameter: 0
        property real targetX: 0
        property real targetY: 0
        width: 12
        height: 12
        radius: width / 2
        color: root.rippleColor
        opacity: 0.0
        transformOrigin: Item.Center
    }

    ParallelAnimation {
        id: ripple
        NumberAnimation {
            target: circle
            property: "width"
            to: circle.targetDiameter
            duration: root.flow ? root.flow.rippleDuration : 390
            easing.type: root.flow ? root.flow.easeOut : Easing.OutCubic
        }
        NumberAnimation {
            target: circle
            property: "height"
            to: circle.targetDiameter
            duration: root.flow ? root.flow.rippleDuration : 390
            easing.type: root.flow ? root.flow.easeOut : Easing.OutCubic
        }
        NumberAnimation {
            target: circle
            property: "x"
            to: circle.targetX
            duration: root.flow ? root.flow.rippleDuration : 390
            easing.type: root.flow ? root.flow.easeOut : Easing.OutCubic
        }
        NumberAnimation {
            target: circle
            property: "y"
            to: circle.targetY
            duration: root.flow ? root.flow.rippleDuration : 390
            easing.type: root.flow ? root.flow.easeOut : Easing.OutCubic
        }
        SequentialAnimation {
            PauseAnimation { duration: root.flow ? Math.round(root.flow.rippleDuration * 0.30) : 115 }
            NumberAnimation {
                target: circle
                property: "opacity"
                to: 0.0
                duration: root.flow ? root.flow.rippleFadeDuration : 250
                easing.type: root.flow ? root.flow.easeOut : Easing.OutCubic
            }
        }
    }
}

import QtQuick 2.15

Item {
    id: root

    property var flow: null
    property bool running: true
    property color accent: flow ? flow.theme.accent : "#0654A2"
    property color track: Qt.rgba(accent.r, accent.g, accent.b, 0.20)
    property real stroke: 4

    width: 34
    height: 34
    visible: running
    opacity: running ? 1.0 : 0.0
    scale: running ? 1.0 : 0.82

    Behavior on opacity {
        NumberAnimation { duration: root.flow ? root.flow.normalDuration : 180; easing.type: Easing.OutCubic }
    }
    Behavior on scale {
        NumberAnimation { duration: root.flow ? root.flow.normalDuration : 180; easing.type: Easing.OutBack }
    }

    Rectangle {
        anchors.fill: parent
        radius: width / 2
        color: "transparent"
        border.width: root.stroke
        border.color: root.track
    }

    Rectangle {
        id: marker
        width: Math.max(7, root.stroke * 1.8)
        height: width
        radius: width / 2
        color: root.accent
        anchors.horizontalCenter: parent.horizontalCenter
        y: 0
    }

    // Render thread: sigue girando aunque el hilo QML esté ocupado.
    RotationAnimator on rotation {
        from: 0
        to: 360
        duration: root.flow ? Math.max(620, root.flow.emphasizedDuration * 2) : 760
        loops: Animation.Infinite
        running: root.running && root.visible
        easing.type: Easing.Linear
    }
}

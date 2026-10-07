import QtQuick 2.15

Item {
    id: root
    property bool active: false
    property var flow
    property color color: "#8FB2D5"

    width: 112
    height: 112

    Rectangle {
        id: halo
        anchors.centerIn: parent
        width: 82
        height: 82
        radius: 41
        color: "transparent"
        border.width: 2
        border.color: root.color
        opacity: 0.30
        scale: 0.75
    }

    Rectangle {
        id: horizontalBar
        anchors.centerIn: parent
        width: 56
        height: 10
        radius: 5
        color: root.color
        scale: 0.0
    }

    Rectangle {
        id: verticalBar
        anchors.centerIn: parent
        width: 10
        height: 56
        radius: 5
        color: root.color
        scale: 0.0
    }

    ParallelAnimation {
        id: reveal
        NumberAnimation { target: horizontalBar; property: "scale"; from: 0.0; to: 1.0; duration: root.flow ? root.flow.duration(420) : 420; easing.type: Easing.OutBack }
        NumberAnimation { target: verticalBar; property: "scale"; from: 0.0; to: 1.0; duration: root.flow ? root.flow.duration(520) : 520; easing.type: Easing.OutBack }
        NumberAnimation { target: halo; property: "scale"; from: 0.72; to: 1.0; duration: root.flow ? root.flow.duration(620) : 620; easing.type: Easing.OutQuart }
        NumberAnimation { target: halo; property: "opacity"; from: 0.0; to: 0.30; duration: root.flow ? root.flow.duration(480) : 480 }
    }

    SequentialAnimation on rotation {
        running: Boolean(root.active && root.flow !== null && root.flow !== undefined && root.flow.motionAllowed === true)
        loops: Animation.Infinite
        NumberAnimation { from: -3; to: 3; duration: 2200; easing.type: Easing.InOutSine }
        NumberAnimation { from: 3; to: -3; duration: 2200; easing.type: Easing.InOutSine }
    }

    onActiveChanged: {
        if (active) reveal.restart()
        else {
            reveal.stop()
            horizontalBar.scale = 0.0
            verticalBar.scale = 0.0
            halo.scale = 0.75
            halo.opacity = 0.0
        }
    }
}

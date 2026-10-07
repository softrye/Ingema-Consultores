import QtQuick 2.15
import QtQuick.Controls 2.15
import InGe.CoreFlow 3.0 as Mobile
import "../flowcore" as FlowCore

Item {
    id: root

    signal clicked(bool opened)

    property bool opened: false
    property int diameter: 68
    property color color: "#0654A2"
    property color hoverColor: "#0780C3"
    property color textColor: "#FFFFFF"
    property string label: "+"
    property bool motionEnabled: true
    property bool reduceMotion: false
    property int motionLevel: 2

    width: diameter
    height: diameter

    property bool pressed: tapArea.pressed
    property bool hovered: tapArea.containsMouse

    readonly property var flow: Mobile.InGeCoreFlow

    layer.enabled: pressed || hovered || root.opened
    layer.smooth: true

    Rectangle {
        id: shadow
        x: 5
        y: root.pressed ? 7 : 12
        width: parent.width - 10
        height: parent.height - 4
        radius: width / 2
        color: "#000000"
        opacity: root.pressed ? 0.13 : (root.opened ? 0.27 : 0.21)
        scale: root.pressed ? 0.94 : 1.0

        Behavior on y { NumberAnimation { duration: flow.fastDuration; easing.type: flow.easeOut } }
        Behavior on opacity { NumberAnimation { duration: flow.normalDuration; easing.type: flow.easeOut } }
        Behavior on scale { NumberAnimation { duration: flow.fastDuration; easing.type: flow.easeOut } }
    }

    Rectangle {
        id: button
        anchors.fill: parent
        radius: width / 2
        color: root.hovered || root.opened ? root.hoverColor : root.color
        scale: root.pressed ? flow.compactPressScale : 1.0
        clip: true

        Behavior on scale {
            NumberAnimation {
                duration: root.pressed ? flow.instantDuration : flow.slowDuration
                easing.type: root.pressed ? flow.easeOut : flow.easeOvershoot
            }
        }
        Behavior on color { ColorAnimation { duration: flow.normalDuration; easing.type: flow.easeOut } }

        FlowCore.FlowRipple {
            id: ripple
            flow: flow
            rippleColor: "#55FFFFFF"
            enabled: flow.motionAllowed
        }

        Text {
            id: plusIcon
            anchors.centerIn: parent
            text: root.label
            color: root.textColor
            font.pixelSize: 34
            font.bold: true
            rotation: root.opened ? 45 : 0
            scale: root.pressed ? 0.88 : 1.0

            Behavior on rotation {
                NumberAnimation { duration: flow.slowDuration; easing.type: flow.easeOvershoot }
            }
            Behavior on scale {
                NumberAnimation { duration: flow.normalDuration; easing.type: flow.easeOvershoot }
            }
        }

        MouseArea {
            id: tapArea
            anchors.fill: parent
            hoverEnabled: true
            onPressed: ripple.trigger(mouse.x, mouse.y)
            onClicked: {
                root.opened = !root.opened
                root.clicked(root.opened)
            }
        }
    }

    SequentialAnimation {
        id: appear
        running: false
        NumberAnimation { target: root; property: "scale"; from: 0.82; to: 1.06; duration: flow.normalDuration; easing.type: flow.easeOut }
        NumberAnimation { target: root; property: "scale"; from: 1.06; to: 1.0; duration: flow.normalDuration; easing.type: flow.easeOvershoot }
    }

    Component.onCompleted: if (flow.motionAllowed) appear.restart()
}

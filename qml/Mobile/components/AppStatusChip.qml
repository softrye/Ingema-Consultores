import QtQuick 2.15
import InGe.CoreFlow 3.0 as Mobile
import "../flowcore" as FlowCore

Rectangle {
    id: root

    property string label: "Estado"
    property string value: "Listo"
    property color accent: flow.theme.accent
    property bool motionEnabled: true
    property bool reduceMotion: false
    property int motionLevel: 2
    property bool initialized: false

    height: 34
    radius: 17
    color: Qt.rgba(accent.r, accent.g, accent.b, 0.10)
    border.color: Qt.rgba(accent.r, accent.g, accent.b, 0.20)
    border.width: 1
    scale: 1.0

    readonly property var flow: Mobile.InGeCoreFlow

    Component.onCompleted: initialized = true
    onValueChanged: {
        if (initialized && flow.motionAllowed)
            statusPulse.restart()
    }

    Row {
        anchors.centerIn: parent
        spacing: 8
        Rectangle {
            id: dot
            width: 8
            height: 8
            radius: 4
            color: root.accent
            anchors.verticalCenter: parent.verticalCenter
        }
        Text {
            text: root.label + ": " + root.value
            color: flow.theme.textPrimary
            font.pixelSize: 13
            anchors.verticalCenter: parent.verticalCenter
        }
    }

    SequentialAnimation {
        id: statusPulse
        ParallelAnimation {
            NumberAnimation { target: root; property: "scale"; to: 1.045; duration: flow.fastDuration; easing.type: flow.easeOut }
            NumberAnimation { target: dot; property: "scale"; to: 1.55; duration: flow.fastDuration; easing.type: flow.easeOut }
        }
        ParallelAnimation {
            NumberAnimation { target: root; property: "scale"; to: 1.0; duration: flow.normalDuration; easing.type: flow.easeOvershoot }
            NumberAnimation { target: dot; property: "scale"; to: 1.0; duration: flow.normalDuration; easing.type: flow.easeOvershoot }
        }
    }
}

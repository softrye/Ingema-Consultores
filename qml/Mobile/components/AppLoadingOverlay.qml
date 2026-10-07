import QtQuick 2.15
import InGe.CoreFlow 3.0 as Mobile
import "../flowcore" as FlowCore

Rectangle {
    id: root

    property bool running: false
    property string message: "Cargando..."
    property bool darkMode: false
    property bool motionEnabled: true
    property bool reduceMotion: false
    property int motionLevel: 2

    anchors.fill: parent
    color: darkMode ? "#AA07111F" : "#B8FFFFFF"
    visible: running || opacity > 0.001
    opacity: running ? 1.0 : 0.0
    z: 1000

    readonly property var flow: Mobile.InGeCoreFlow

    Behavior on opacity {
        NumberAnimation { duration: flow.normalDuration; easing.type: flow.easeOut }
    }

    Rectangle {
        id: card
        width: Math.min(parent.width - 64, 220)
        height: 126
        radius: 24
        anchors.centerIn: parent
        color: darkMode ? "#F21C2D44" : "#F8FFFFFF"
        border.color: darkMode ? "#335C7E" : "#DDE7F2"
        scale: root.running ? 1.0 : 0.92
        opacity: root.running ? 1.0 : 0.0

        Behavior on scale { NumberAnimation { duration: flow.slowDuration; easing.type: flow.easeOvershoot } }
        Behavior on opacity { NumberAnimation { duration: flow.normalDuration; easing.type: flow.easeOut } }

        Column {
            anchors.centerIn: parent
            spacing: 12

            FlowCore.FlowBusyIndicator {
                width: 38
                height: 38
                anchors.horizontalCenter: parent.horizontalCenter
                running: root.running
                flow: flow
                accent: flow.interfaceBlue
                track: darkMode ? "#446CA8C7" : "#330654A2"
            }

            Text {
                text: root.message
                color: darkMode ? "#FFFFFF" : flow.navy
                font.pixelSize: 13
                font.bold: true
                anchors.horizontalCenter: parent.horizontalCenter
            }
        }
    }
}

import QtQuick 2.15
import InGe.CoreFlow 3.0 as Mobile
import "../flowcore" as FlowCore

Rectangle {
    id: root

    signal clicked()

    property string title: "Módulo"
    property string subtitle: "Descripción"
    property string iconSource: "qrc:/ui/v2/placeholders/ph_missing_resource.svg"
    property color accentColor: "#0654A2"
    property bool motionEnabled: true
    property bool reduceMotion: false
    property int motionLevel: 2
    property int revealDelay: 0

    width: 160
    height: 210
    radius: 22
    color: tap.pressed ? "#F2F7FC" : "#FFFFFF"
    border.color: tap.containsMouse ? accentColor : "#D9E1EE"
    border.width: 1
    scale: tap.pressed ? flow.cardPressScale : 1.0
    transformOrigin: Item.Center
    clip: true

    readonly property var flow: Mobile.InGeCoreFlow

    Behavior on scale {
        NumberAnimation {
            duration: tap.pressed ? flow.instantDuration : flow.normalDuration
            easing.type: tap.pressed ? flow.easeOut : flow.easeOvershoot
        }
    }
    Behavior on color { ColorAnimation { duration: flow.fastDuration } }
    Behavior on border.color { ColorAnimation { duration: flow.fastDuration } }



    Column {
        anchors.fill: parent
        anchors.margins: 18
        spacing: 10

        Image {
            id: iconImage
            width: 48
            height: 48
            source: root.iconSource
            fillMode: Image.PreserveAspectFit
            scale: tap.pressed ? 0.92 : 1.0
            rotation: tap.pressed ? -3 : 0

            Behavior on scale { NumberAnimation { duration: flow.fastDuration; easing.type: flow.easeOut } }
            Behavior on rotation { NumberAnimation { duration: flow.normalDuration; easing.type: flow.easeOvershoot } }
        }

        Text {
            text: root.title
            color: "#102347"
            font.pixelSize: 18
            font.bold: true
            wrapMode: Text.WordWrap
        }
        Text {
            text: root.subtitle
            color: "#66718A"
            font.pixelSize: 13
            wrapMode: Text.WordWrap
            width: parent.width
        }
    }

    FlowCore.FlowRipple {
        id: ripple
        flow: flow
        rippleColor: flow.rippleLight
        enabled: flow.motionAllowed
    }

    MouseArea {
        id: tap
        anchors.fill: parent
        hoverEnabled: true
        onPressed: ripple.trigger(mouse.x, mouse.y)
        onClicked: root.clicked()
    }
}

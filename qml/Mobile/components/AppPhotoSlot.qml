import QtQuick 2.15
import InGe.CoreFlow 3.0 as Mobile
import "../flowcore" as FlowCore

Rectangle {
    id: root

    signal clicked()

    property string imageSource: "qrc:/ui/v2/placeholders/ph_photo_empty.svg"
    property bool interactive: false
    property bool motionEnabled: true
    property bool reduceMotion: false
    property int motionLevel: 2

    width: 150
    height: 92
    radius: flow.radius.field
    color: tap.pressed ? flow.theme.pressed : flow.theme.surfaceSecondary
    border.color: flow.theme.border
    clip: true
    scale: tap.pressed ? flow.cardPressScale : 1.0

    readonly property var flow: Mobile.InGeCoreFlow

    Behavior on color { ColorAnimation { duration: flow.fastDuration } }
    Behavior on scale { NumberAnimation { duration: flow.normalDuration; easing.type: flow.easeOvershoot } }

    Image {
        id: photo
        anchors.fill: parent
        anchors.margins: 8
        source: root.imageSource
        fillMode: Image.PreserveAspectFit
        asynchronous: true
        opacity: status === Image.Ready ? 1.0 : 0.35
        scale: status === Image.Ready ? 1.0 : 0.96
        Behavior on opacity { NumberAnimation { duration: flow.normalDuration; easing.type: flow.easeOut } }
        Behavior on scale { NumberAnimation { duration: flow.slowDuration; easing.type: flow.easeOvershoot } }
    }

    FlowCore.FlowRipple {
        id: ripple
        flow: flow
        rippleColor: flow.rippleLight
        enabled: root.interactive && flow.motionAllowed
    }

    MouseArea {
        id: tap
        anchors.fill: parent
        enabled: root.interactive
        onPressed: ripple.trigger(mouse.x, mouse.y)
        onClicked: root.clicked()
    }
}

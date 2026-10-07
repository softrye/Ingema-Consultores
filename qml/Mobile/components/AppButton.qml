import QtQuick 2.15
import QtQuick.Controls 2.15
import InGe.CoreFlow 3.0 as Mobile
import "../flowcore" as FlowCore

Button {
    id: root

    property bool primary: true
    property bool danger: false
    property bool busy: false
    property bool motionEnabled: true
    property bool reduceMotion: false
    property int motionLevel: 2
    property color primaryColor: danger ? flow.theme.error : flow.theme.accent
    property color secondaryColor: flow.theme.isGlass
                                   ? flow.theme.glassSurface : flow.theme.surface
    property color borderColor: danger ? flow.theme.error : flow.theme.border

    implicitHeight: 52
    font.pixelSize: 16
    font.bold: true
    enabled: !busy
    scale: down ? flow.pressScale : 1.0
    transformOrigin: Item.Center

    readonly property var flow: Mobile.InGeCoreFlow

    Behavior on scale {
        NumberAnimation {
            duration: root.down ? flow.instantDuration : flow.normalDuration
            easing.type: root.down ? flow.easeOut : flow.easeOvershoot
        }
    }

    onDownChanged: {
        if (down)
            ripple.trigger(width / 2, height / 2)
    }

    background: Rectangle {
        id: bg
        radius: flow.radius.field
        color: root.down
               ? (root.primary ? Qt.darker(root.primaryColor, 1.14)
                               : flow.theme.pressed)
               : (root.primary ? root.primaryColor : root.secondaryColor)
        border.color: root.primary ? root.primaryColor : root.borderColor
        border.width: 1
        opacity: root.enabled ? 1.0 : 0.58
        clip: true

        Behavior on color { ColorAnimation { duration: flow.fastDuration } }
        Behavior on opacity { NumberAnimation { duration: flow.normalDuration } }

        FlowCore.FlowRipple {
            id: ripple
            flow: flow
            rippleColor: root.primary ? "#55FFFFFF" : flow.rippleLight
            cornerRadius: bg.radius
            enabled: flow.motionAllowed && root.enabled
        }
    }

    contentItem: Item {
        Row {
            anchors.centerIn: parent
            spacing: 9

            FlowCore.FlowBusyIndicator {
                width: 22
                height: 22
                running: root.busy
                flow: flow
                accent: root.primary ? "#FFFFFF" : root.primaryColor
                track: root.primary ? "#55FFFFFF" : "#330654A2"
                anchors.verticalCenter: parent.verticalCenter
            }

            Text {
                text: root.text
                color: root.primary ? "#FFFFFF"
                                    : (root.danger ? flow.theme.error
                                                   : flow.theme.textPrimary)
                font: root.font
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
                anchors.verticalCenter: parent.verticalCenter
                opacity: root.busy ? 0.82 : 1.0

                Behavior on opacity { NumberAnimation { duration: flow.fastDuration } }
            }
        }
    }
}

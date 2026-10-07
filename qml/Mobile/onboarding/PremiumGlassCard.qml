import QtQuick 2.15
import "../flowcore" as CoreFlow

CoreFlow.FlowGlassSurface {
    id: root

    property string title: ""
    property string subtitle: ""
    property string symbol: ""
    property color accent: "#8FB2D5"
    property bool active: true
    property bool selected: false
    property bool dark: true
    property int revealIndex: 0

    signal clicked()

    radius: 22
    darkMode: root.dark
    strength: root.selected ? 1.16 : 0.92
    border.width: root.selected ? 2 : 1
    border.color: root.selected
                  ? root.accent
                  : (root.dark ? "#3AFFFFFF" : "#260654A2")
    opacity: root.active ? 1.0 : 0.0
    scale: cardMouse.pressed && root.flow
           ? root.flow.cardPressScale
           : (root.active ? 1.0 : 0.94)
    clip: true

    Rectangle {
        anchors.fill: parent
        radius: parent.radius
        color: root.accent
        opacity: root.selected ? (root.dark ? 0.10 : 0.07) : 0.0

        Behavior on opacity {
            NumberAnimation {
                duration: root.flow
                          ? root.flow.motion.policy(root.flow.motion.tabSelect).duration
                          : 180
            }
        }
    }

    transform: Translate {
        id: revealOffset
        y: root.active ? 0 : 16

        Behavior on y {
            NumberAnimation {
                duration: root.flow
                          ? root.flow.motion.policy(root.flow.motion.enterScale).duration
                            + root.revealIndex * root.flow.staggerDuration
                          : 230
                easing.type: root.flow
                             ? root.flow.motion.policy(root.flow.motion.enterScale).easing
                             : Easing.OutQuart
            }
        }
    }

    Behavior on opacity {
        NumberAnimation {
                duration: root.flow
                      ? root.flow.motion.policy(root.flow.motion.enterFade).duration
                        + root.revealIndex * root.flow.staggerDuration
                      : 180
        }
    }

    Behavior on scale {
        NumberAnimation {
            duration: root.flow ? root.flow.fastDuration : 110
            easing.type: root.flow
                         ? root.flow.motion.policy(root.flow.motion.pressStandard).easing
                         : Easing.OutCubic
        }
    }

    Behavior on border.color {
        ColorAnimation {
            duration: root.flow ? root.flow.normalDuration : 180
        }
    }

    Rectangle {
        width: 4
        height: parent.height - 22
        radius: 2
        anchors.left: parent.left
        anchors.leftMargin: 8
        anchors.verticalCenter: parent.verticalCenter
        color: root.accent
        opacity: root.selected ? 1.0 : 0.38
    }

    Row {
        anchors.fill: parent
        anchors.margins: 13
        anchors.leftMargin: 20
        spacing: 12

        Rectangle {
            width: 44
            height: 44
            radius: 14
            anchors.verticalCenter: parent.verticalCenter
            color: root.selected
                   ? root.accent
                   : (root.dark ? "#20FFFFFF" : "#E8F5FC")
            border.width: 1
            border.color: root.selected ? "#70FFFFFF" : root.accent

            Text {
                anchors.centerIn: parent
                text: root.symbol
                color: root.selected ? "white" : root.accent
                font.pixelSize: 19
                font.bold: true
            }
        }

        Column {
            width: parent.width - 76
            anchors.verticalCenter: parent.verticalCenter
            spacing: 3

            CoreFlow.FlowText {
                width: parent.width
                text: root.title
                role: "label"
                color: root.dark ? "white" : "#151A30"
                font.pixelSize: 14
                font.weight: Font.DemiBold
                maximumLineCount: 1
                elide: Text.ElideRight
            }

            CoreFlow.FlowText {
                width: parent.width
                text: root.subtitle
                role: "caption"
                color: root.dark ? "#D1DEEA" : "#536176"
                font.pixelSize: 11
                lineHeight: 1.12
                lineHeightMode: Text.ProportionalHeight
                wrapMode: Text.WordWrap
                maximumLineCount: 2
                elide: Text.ElideRight
            }
        }
    }

    MouseArea {
        id: cardMouse
        anchors.fill: parent
        onClicked: root.clicked()
    }
}

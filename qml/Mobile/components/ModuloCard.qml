import QtQuick
import QtQuick.Controls
import InGe.CoreFlow 3.0 as Mobile
import "../flowcore" as FlowCore

Item {
    id: root

    // ============================================================
    // ModuloCard.qml
    // Card táctil reutilizable para módulos de InGe+
    // Optimizado para Android/Qt 6: animamos scale/opacity/y, no width/height.
    // ============================================================

    signal clicked()

    property string title: "Calicatas"
    property string subtitle: "Registro técnico de campo"
    property string iconText: "CA"
    property string badgeText: ""
    property int count: -1
    property real progress: -1.0
    property color accentColor: "#0654A2"
    property color cardColor: "#FFFFFF"
    property color textColor: "#151A30"
    property color mutedColor: "#667085"
    property color borderColor: "#DDE7F2"
    property color pressedColor: "#F4F7FB"

    // Permite insertar QtLottie u otro icono externo sin acoplar este componente.
    // Ejemplo:
    // iconDelegate: Component { LottieAnimation { source: "qrc:/..." } }
    property Component iconDelegate: null

    property bool pressed: tapArea.pressed
    property bool hovered: tapArea.containsMouse
    property bool motionEnabled: true
    property bool reduceMotion: false
    property int motionLevel: 2
    property int revealDelay: 0

    readonly property var flow: Mobile.InGeCoreFlow

    width: 172
    height: 156

    // Capa temporal solo durante interacción: evita rasterizar siempre la card.
    layer.enabled: pressed || hovered || cardScaleBehavior.running || shadowOpacityBehavior.running
    layer.smooth: true

    Rectangle {
        id: softShadow
        x: 4
        y: root.pressed ? 5 : 9
        width: parent.width - 8
        height: parent.height - 4
        radius: 22
        color: "#000000"
        opacity: root.pressed ? 0.09 : (root.hovered ? 0.16 : 0.12)
        scale: root.pressed ? 0.985 : 1.0

        Behavior on y {
            NumberAnimation { duration: flow.fastDuration; easing.type: Easing.OutCubic }
        }

        Behavior on opacity {
            id: shadowOpacityBehavior
            NumberAnimation { duration: flow.normalDuration; easing.type: Easing.OutCubic }
        }

        Behavior on scale {
            NumberAnimation { duration: flow.fastDuration; easing.type: Easing.OutCubic }
        }
    }

    Rectangle {
        id: card
        anchors.fill: parent
        radius: 22
        color: root.pressed ? root.pressedColor : root.cardColor
        border.color: root.hovered ? root.accentColor : root.borderColor
        border.width: root.hovered ? 1.2 : 1
        scale: root.pressed ? 0.972 : 1.0

        // Microinteracción principal: hundimiento táctil.
        Behavior on scale {
            id: cardScaleBehavior
            NumberAnimation { duration: root.pressed ? flow.instantDuration : flow.normalDuration; easing.type: Easing.OutCubic }
        }

        Behavior on color {
            ColorAnimation { duration: flow.normalDuration; easing.type: Easing.OutCubic }
        }

        Behavior on border.color {
            ColorAnimation { duration: flow.normalDuration; easing.type: Easing.OutCubic }
        }

        Rectangle {
            id: iconBox
            x: 16
            y: 16
            width: 48
            height: 48
            radius: 16
            color: Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.12)
            scale: root.pressed ? 0.94 : 1.0

            Behavior on scale {
                NumberAnimation { duration: flow.fastDuration; easing.type: Easing.OutCubic }
            }

            Loader {
                id: iconLoader
                anchors.fill: parent
                anchors.margins: 6
                sourceComponent: root.iconDelegate
                visible: root.iconDelegate !== null
            }

            Text {
                anchors.centerIn: parent
                visible: root.iconDelegate === null
                text: root.iconText
                color: root.accentColor
                font.pixelSize: 15
                font.bold: true
            }
        }

        Rectangle {
            id: badge
            visible: root.badgeText.length > 0
            x: parent.width - width - 14
            y: 16
            width: Math.max(56, badgeLabel.implicitWidth + 20)
            height: 26
            radius: 13
            color: Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.10)
            opacity: visible ? 1.0 : 0.0

            Behavior on opacity {
                NumberAnimation { duration: flow.normalDuration; easing.type: Easing.OutCubic }
            }

            Text {
                id: badgeLabel
                anchors.centerIn: parent
                text: root.badgeText
                color: root.accentColor
                font.pixelSize: 11
                font.bold: true
                elide: Text.ElideRight
            }
        }

        Text {
            id: titleText
            x: 16
            y: 78
            width: parent.width - 32
            text: root.title
            color: root.textColor
            font.pixelSize: 17
            font.bold: true
            elide: Text.ElideRight
        }

        Text {
            id: subtitleText
            x: 16
            y: 104
            width: parent.width - 32
            text: root.subtitle
            color: root.mutedColor
            font.pixelSize: 12
            lineHeight: 1.05
            wrapMode: Text.WordWrap
            maximumLineCount: 2
            elide: Text.ElideRight
        }

        Text {
            visible: root.count >= 0
            x: 16
            y: parent.height - 26
            width: parent.width - 32
            text: root.count >= 0 ? (root.count + " registros") : ""
            color: root.accentColor
            font.pixelSize: 12
            font.bold: true
            elide: Text.ElideRight
        }

        Rectangle {
            id: progressTrack
            visible: root.progress >= 0
            x: 16
            y: parent.height - 18
            width: parent.width - 32
            height: 5
            radius: 3
            color: "#EAF0F6"

            Rectangle {
                width: Math.max(0, Math.min(1, root.progress)) * parent.width
                height: parent.height
                radius: parent.radius
                color: root.accentColor

                Behavior on width {
                    NumberAnimation { duration: flow.slowDuration; easing.type: Easing.OutCubic }
                }
            }
        }

        FlowCore.FlowRipple {
            id: ripple
            flow: flow
            rippleColor: flow.rippleLight
            enabled: flow.motionAllowed
        }

        MouseArea {
            id: tapArea
            anchors.fill: parent
            hoverEnabled: true
            onPressed: ripple.trigger(mouse.x, mouse.y)
            onClicked: root.clicked()
        }
    }


}

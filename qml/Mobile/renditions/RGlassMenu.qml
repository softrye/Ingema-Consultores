import QtQuick
import "RStyle.js" as S

// Menú contextual tipo Haptic Touch: emerge desde el control que lo abre
// (escala 0.95 -> 1 y opacidad, 220 ms; cierre 160 ms), con cristal claro y
// puntero hacia el origen. Se cierra al tocar fuera, con Atrás o al elegir.
// Sólo transformaciones y opacidad: sin blur ni relayout de la pantalla.
Item {
    id: menu
    property var ui
    property bool open: false
    property real anchorX: 0                 // punto de origen en coordenadas de [menu]
    property real anchorY: 0
    property bool above: true                // true: sobre el origen (dock); false: debajo (filtro)
    property real cardWidth: 280 * ui.u
    property real margin: 14 * ui.u
    default property alias content: body.data
    signal dismissed()
    anchors.fill: parent
    visible: card.opacity > 0.01 || open
    z: 50

    function close() { if (open) { open = false; dismissed() } }

    MouseArea {                                // tocar fuera cierra sin ejecutar nada
        anchors.fill: parent
        enabled: menu.open
        onClicked: menu.close()
        onPressAndHold: menu.close()
    }

    Item {
        id: card
        width: Math.min(menu.cardWidth, menu.width - 2 * menu.margin)
        height: body.implicitHeight + 24 * menu.ui.u
        x: Math.max(menu.margin, Math.min(menu.width - width - menu.margin, menu.anchorX - width / 2))
        y: menu.above ? Math.max(menu.margin, menu.anchorY - height - 14 * menu.ui.u)
                      : Math.min(menu.height - height - menu.margin, menu.anchorY + 12 * menu.ui.u)
        transformOrigin: menu.above ? Item.Bottom : Item.TopRight
        scale: menu.open ? 1 : 0.95
        opacity: menu.open ? 1 : 0
        Behavior on scale { NumberAnimation { duration: menu.open ? 220 : 160; easing.type: Easing.OutCubic } }
        Behavior on opacity { NumberAnimation { duration: menu.open ? 200 : 150; easing.type: Easing.OutQuad } }

        // Sombra suave (dos capas estáticas, sin efecto de desenfoque).
        Rectangle { anchors.fill: parent; anchors.topMargin: 8 * menu.ui.u; anchors.margins: -2 * menu.ui.u; radius: 22 * menu.ui.u; color: S.ink(0.05) }
        Rectangle { anchors.fill: parent; anchors.topMargin: 4 * menu.ui.u; radius: 20 * menu.ui.u; color: S.ink(0.05) }
        // Puntero hacia el control de origen.
        Rectangle {
            width: 16 * menu.ui.u; height: width
            rotation: 45
            color: "#FBFCFE"
            border.width: 1; border.color: Qt.rgba(1, 1, 1, 0.9)
            x: Math.max(18 * menu.ui.u, Math.min(card.width - 34 * menu.ui.u, menu.anchorX - card.x - width / 2))
            y: menu.above ? card.height - height / 2 - 1 : -height / 2 + 1
        }
        Rectangle {
            anchors.fill: parent
            radius: 20 * menu.ui.u
            gradient: Gradient {
                GradientStop { position: 0.0; color: Qt.rgba(1, 1, 1, 0.97) }
                GradientStop { position: 1.0; color: Qt.rgba(246 / 255, 249 / 255, 253 / 255, 0.93) }
            }
            border.width: 1
            border.color: Qt.rgba(1, 1, 1, 0.95)
        }
        MouseArea { anchors.fill: parent; enabled: menu.open }   // no atraviesa al fondo
        Column {
            id: body
            x: 12 * menu.ui.u
            y: 12 * menu.ui.u
            width: card.width - 24 * menu.ui.u
        }
    }
}

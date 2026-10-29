import QtQuick
import "RStyle.js" as S

// Menú contextual 3D Touch (estilo iOS): emerge desde el control que lo abre
// (escala 0.9 -> 1 con leve rebote y opacidad; cierre rápido), el fondo se
// atenúa para dar foco y la tarjeta es compacta. Siempre queda dentro de la
// zona segura: nunca cubre la barra de estado, el Dock ni InGe IA; si el
// contenido no cabe, se desplaza dentro de la tarjeta. Se cierra al tocar
// fuera, con Atrás o al elegir. Sólo transformaciones y opacidad (sin blur).
Item {
    id: menu
    property var ui
    property bool open: false
    property real anchorX: 0                 // punto de origen en coordenadas de [menu]
    property real anchorY: 0
    property bool above: true                // true: sobre el origen (dock); false: debajo (filtro)
    property real cardWidth: 264 * ui.u
    property real margin: 12 * ui.u
    // Límite del contenido: permite al selector de formulario evitar el IME
    // sin modificar la geometría ni la animación del Dock global.
    property real viewportBottom: height
    // Zona segura: barra de estado arriba; Dock (e InGe IA) abajo.
    property real topInset: ui && ui.topInset !== undefined ? ui.topInset : 0
    property real bottomInset: ui && ui.dockArea !== undefined ? ui.dockArea : 0
    readonly property real safeBottom: Math.min(viewportBottom, height - bottomInset) - margin
    readonly property real safeTop: topInset + margin
    readonly property real availableHeight: Math.max(0, Math.min(anchorY, viewportBottom) - 2 * margin - 14 * ui.u)
    readonly property real maxCardHeight: Math.max(120 * ui.u, safeBottom - safeTop)
    default property alias content: body.data
    signal dismissed()
    anchors.fill: parent
    visible: card.opacity > 0.01 || open
    z: 50

    function close() { if (open) { open = false; dismissed() } }

    property bool dimBackground: true          // false cuando el anfitrión ya desenfoca/atenúa
    Rectangle {                                // fondo atenuado: el foco queda en el menú
        anchors.fill: parent
        color: "#0A1020"
        visible: menu.dimBackground
        opacity: menu.open ? 0.28 : 0
        Behavior on opacity { NumberAnimation { duration: menu.open ? 200 : 150 } }
    }
    MouseArea {                                // tocar fuera cierra sin ejecutar nada
        anchors.fill: parent
        enabled: menu.open
        preventStealing: true                    // el fondo no se desplaza con el menú abierto
        onClicked: menu.close()
        onPressAndHold: menu.close()
        onWheel: function(wheel) { wheel.accepted = true }
    }

    Item {
        id: card
        width: Math.min(menu.cardWidth, menu.width - 2 * menu.margin)
        height: Math.min(body.implicitHeight + 16 * menu.ui.u, menu.maxCardHeight)
        x: Math.max(menu.margin, Math.min(menu.width - width - menu.margin, menu.anchorX - width / 2))
        y: Math.max(menu.safeTop, Math.min(menu.safeBottom - height,
               menu.above ? Math.min(menu.anchorY, menu.viewportBottom) - height - 12 * menu.ui.u
                          : menu.anchorY + 10 * menu.ui.u))
        transformOrigin: menu.above ? Item.Bottom : Item.Top
        scale: menu.open ? 1 : 0.9
        opacity: menu.open ? 1 : 0
        Behavior on scale { NumberAnimation { duration: menu.open ? 240 : 150
                                              easing.type: menu.open ? Easing.OutBack : Easing.InCubic; easing.overshoot: 1.3 } }
        Behavior on opacity { NumberAnimation { duration: menu.open ? 180 : 140; easing.type: Easing.OutQuad } }

        // Sombra suave (dos capas estáticas, sin efecto de desenfoque).
        Rectangle { anchors.fill: parent; anchors.topMargin: 8 * menu.ui.u; anchors.margins: -2 * menu.ui.u; radius: 18 * menu.ui.u; color: S.ink(0.07) }
        Rectangle { anchors.fill: parent; anchors.topMargin: 3 * menu.ui.u; radius: 16 * menu.ui.u; color: S.ink(0.05) }
        Rectangle {
            anchors.fill: parent
            radius: 16 * menu.ui.u
            gradient: Gradient {
                GradientStop { position: 0.0; color: S.glass(0.96) }
                GradientStop { position: 1.0; color: S.lite(244, 248, 253, 0.93) }
            }
            border.width: 1
            border.color: S.edge(0.95)
        }
        MouseArea { anchors.fill: parent; enabled: menu.open }   // no atraviesa al fondo
        Flickable {                                 // desplazable si no cabe en la zona segura
            x: 8 * menu.ui.u
            y: 8 * menu.ui.u
            width: card.width - 16 * menu.ui.u
            height: card.height - 16 * menu.ui.u
            contentHeight: body.implicitHeight
            clip: contentHeight > height
            boundsBehavior: Flickable.StopAtBounds
            interactive: contentHeight > height
            Column {
                id: body
                width: parent.width
            }
        }
    }
}

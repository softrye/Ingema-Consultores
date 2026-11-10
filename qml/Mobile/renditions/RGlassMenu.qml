import QtQuick
import "../kawaii" as Kawaii
import "RStyle.js" as S
import ".." as Mobile                          // GlassSurface: Liquid Glass oficial (Dock)
import InGe.CoreFlow 3.0 as CoreFlowModule           // ganchos «Extrema» del motor único

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

    // Liquid Glass oficial: con un `ui` de vidrio (glassTexture/backdrop/glassTick) la
    // tarjeta usa el MISMO GlassSurface/glass.frag y los parámetros del Dock.
    property var liquidUi: null
    readonly property var liquidMaterial: ui && ui.liquidGlass !== false ? ui.liquidGlassMaterial || null : null
    readonly property bool liquid: !!liquidMaterial && !!liquidUi       // en LOW, GlassSurface dibuja el respaldo
    property int geometryTick: 0
    QtObject {
        id: menuGlass
        readonly property Item backdrop: menu.liquidUi ? menu.liquidUi.backdrop : null
        readonly property bool glassReady: !!menu.liquidUi && menu.liquidUi.glassReady !== false
        readonly property var glassTexture: menu.liquidUi ? menu.liquidUi.glassTexture : null
        readonly property int glassTick: (menu.liquidUi ? menu.liquidUi.glassTick : 0) + menu.geometryTick
    }
    // Calicatas: vidrio esmerilado sólido (blanco 72 % / grafito 75 %, filo del
    // Dock) en vez de la tarjeta blanca opaca cuando no hay Liquid Glass.
    property bool frostedFallback: false
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
        height: Math.min(body.implicitHeight + (S.halloween || S.kawaii ? 42 : 16) * menu.ui.u, menu.maxCardHeight)
        x: Math.max(menu.margin, Math.min(menu.width - width - menu.margin, menu.anchorX - width / 2))
        y: Math.max(menu.safeTop, Math.min(menu.safeBottom - height,
               menu.above ? Math.min(menu.anchorY, menu.viewportBottom) - height - 12 * menu.ui.u
                          : menu.anchorY + 10 * menu.ui.u))
        transformOrigin: menu.above ? Item.Bottom : Item.Top
        // «Extrema»: nace desde su origen (escala menor) y el vidrio pasa de gel a panel.
        readonly property bool extreme: CoreFlowModule.InGeCoreFlow.extremeMotion === true
        scale: menu.open ? 1 : (extreme ? CoreFlowModule.InGeCoreFlow.sheetStartScale : 0.9)
        property real gel: 0
        NumberAnimation { id: gelOut; target: card; property: "gel"; to: 0; duration: 360; easing.type: Easing.OutCubic }
        Connections {
            target: menu
            function onOpenChanged() {
                if (!menu.open || !card.extreme) return
                card.gel = CoreFlowModule.InGeCoreFlow.sheetOriginGel
                gelOut.restart()
            }
        }
        opacity: menu.open ? 1 : 0
        // Hero (ui.heroMotion, sólo advancedMotion): easeOutBack al abrir, acceleration al cerrar,
        // con optimizedDurationTo del cambio de tamaño real (10 % de la tarjeta).
        readonly property var hero: menu.ui && menu.ui.heroMotion ? menu.ui.heroMotion : null
        Behavior on scale { NumberAnimation { duration: card.hero ? card.hero.duration(0.1 * (card.width + card.height)) : menu.open ? 240 : 150
                                              easing.type: card.hero ? Easing.BezierSpline : menu.open ? Easing.OutBack : Easing.InCubic
                                              easing.bezierCurve: card.hero ? (menu.open ? card.hero.easeOutBack : card.hero.acceleration) : []
                                              easing.overshoot: 1.3 } }
        Behavior on opacity { NumberAnimation { duration: menu.open ? 180 : 140; easing.type: Easing.OutQuad } }
        // El host del vidrio expone glassTick de sólo lectura: el menú suma el suyo.
        onXChanged: menu.geometryTick++
        onYChanged: menu.geometryTick++
        onHeightChanged: menu.geometryTick++
        onScaleChanged: menu.geometryTick++
        Mobile.DockGlassPanel {                  // Liquid Glass oficial (preset único del Dock)
            visible: menu.liquid && (textureReady || fallbackOn)
            glassUi: menuGlass
            material: menu.liquidMaterial
            tint: menu.ui.dockGlassTint                  // oscuro igual que claro y el Dock: sin tinte negro
            radius: 18 * menu.ui.u
            u: menu.ui.u
            gel: card.gel
        }
        Rectangle {                              // claro: velo blanco leve para el texto oscuro
            visible: menu.liquid && !S.dark
            anchors.fill: parent
            radius: 18 * menu.ui.u
            color: Qt.rgba(1, 1, 1, 0.22)
        }

        // Sombra suave (dos capas estáticas, sin efecto de desenfoque).
        Rectangle { visible: !menu.liquid; anchors.fill: parent; anchors.topMargin: 8 * menu.ui.u; anchors.margins: -2 * menu.ui.u; radius: 18 * menu.ui.u; color: S.ink(0.07) }
        Rectangle { visible: !menu.liquid; anchors.fill: parent; anchors.topMargin: 3 * menu.ui.u; radius: 16 * menu.ui.u; color: S.ink(0.05) }
        Rectangle {
            visible: !menu.liquid
            anchors.fill: parent
            radius: 16 * menu.ui.u
            gradient: Gradient {
                GradientStop { position: 0.0; color: menu.frostedFallback ? (S.dark ? Qt.rgba(40 / 255, 40 / 255, 42 / 255, 0.78) : Qt.rgba(1, 1, 1, 0.80))
                                                                          : S.glass(0.96) }
                GradientStop { position: 1.0; color: menu.frostedFallback ? (S.dark ? Qt.rgba(28 / 255, 28 / 255, 30 / 255, 0.75) : Qt.rgba(1, 1, 1, 0.72))
                                                                          : S.lite(244, 248, 253, 0.93) }
            }
            border.width: 1
            border.color: menu.frostedFallback ? (S.dark ? Qt.rgba(1, 1, 1, 0.18) : Qt.rgba(1, 1, 1, 0.85)) : S.edge(0.95)
        }
        Rectangle {                              // filo especular superior (como el Dock)
            visible: !menu.liquid && menu.frostedFallback
            anchors.fill: parent
            radius: 16 * menu.ui.u
            gradient: Gradient {
                GradientStop { position: 0.0; color: Qt.rgba(1, 1, 1, S.dark ? 0.12 : 0.45) }
                GradientStop { position: Math.min(0.5, 28 * menu.ui.u / Math.max(1, card.height)); color: Qt.rgba(1, 1, 1, 0) }
            }
        }
        Kawaii.KawaiiMascot {
            active: S.kawaii
            frame: 1; tilePixels: 96
            anchors.right: parent.right; anchors.top: parent.top
            width: 46*menu.ui.u; height: width
            enabled: false
        }
        Image {
            visible: S.halloween
            x: 12 * menu.ui.u; y: 5 * menu.ui.u
            width: 32 * menu.ui.u; height: 24 * menu.ui.u
            source: visible ? "qrc:/images/halloween/bat.svg" : ""; sourceSize: Qt.size(64, 48)
        }
        MouseArea { anchors.fill: parent; enabled: menu.open }   // no atraviesa al fondo
        Flickable {                                 // desplazable si no cabe en la zona segura
            x: 8 * menu.ui.u
            y: (S.halloween || S.kawaii ? 34 : 8) * menu.ui.u
            width: card.width - 16 * menu.ui.u
            height: card.height - (S.halloween || S.kawaii ? 42 : 16) * menu.ui.u
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

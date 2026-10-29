import QtQuick
import "RStyle.js" as S
import ".." as Mobile

// Tarjeta de vidrio con columna de contenido; tocable si [clickable].
Rectangle {
    id: card
    Component.onCompleted: S.renderCount(objectName.indexOf("expense:") === 0 ? "expense_delegate_created" : "section_card_created")
    property var ui
    property bool clickable: false
    default property alias content: body.data
    signal activated()

    implicitHeight: body.implicitHeight + 32 * ui.u
    // Crecer/encoger con suavidad cuando aparece o se oculta contenido (no en la carga).
    property bool settled: false
    Timer { interval: 400; running: true; onTriggered: card.settled = true }
    Behavior on implicitHeight { enabled: card.settled && card.ui && card.ui.reducedMotion !== true
                                 NumberAnimation { duration: 240; easing.type: Easing.OutCubic } }
    radius: 18 * ui.u
    readonly property bool glassOn: !!ui && !!ui.cardGlassUi && !!ui.cardGlassUi.glassTexture
                                    && ui.cardGlassUi.glassReady !== false
    // Fuera de pantalla no se dibuja el vidrio (ahorra pasadas de GPU al desplazar).
    readonly property bool onScreen: {
        if (!glassOn) return false
        var tick = ui.cardGlassUi.glassTick
        var p = mapToItem(null, 0, 0)
        return p.y + height > -20 && p.y < (Window.height > 0 ? Window.height : 2400) + 20
    }
    color: glassOn ? (tap.pressed ? Qt.rgba(1, 1, 1, 0.06) : "transparent") : (tap.pressed ? S.surfaceStrong : S.surface)
    border.width: glassOn ? 0 : 1
    border.color: S.border
    Mobile.GlassSurface {                             // Liquid Glass real (material del Dock), claro y oscuro
        ui: card.glassOn ? card.ui.cardGlassUi : null
        visible: card.onScreen
        radius: card.radius
        margin: 10 * card.ui.u
        tint: S.dark ? Qt.rgba(10 / 255, 14 / 255, 24 / 255, 0.42) : Qt.rgba(1, 1, 1, 0.78)
        refraction: S.dark ? card.ui.dockGlassRefraction : 0          // claro: sin lente oscura
        specular: S.dark ? 0.75 : 0.45                                   // oscuro: filo claro como iOS
        bevel: card.ui.dockGlassBevel
        contrast: card.ui.dockGlassContrast
        frost: S.dark ? card.ui.dockGlassFrost : 7 * card.ui.u           // esmerilado blanco intenso
        edge: S.dark ? Qt.rgba(1, 1, 1, 0.38) : Qt.rgba(1, 1, 1, 0.95)
        shadowAlpha: S.dark ? card.ui.dockGlassShadowAlpha : 0.10
    }
    Rectangle {                                       // brillo superior del vidrio oscuro
        visible: S.dark && !card.glassOn
        anchors.fill: parent; anchors.margins: 1; radius: parent.radius - 1
        gradient: Gradient {
            GradientStop { position: 0.0; color: Qt.rgba(1, 1, 1, 0.10) }
            GradientStop { position: 0.45; color: Qt.rgba(1, 1, 1, 0.0) }
        }
    }
    Column {
        id: body
        x: 16 * card.ui.u
        y: 16 * card.ui.u
        width: card.width - 32 * card.ui.u
        spacing: 8 * card.ui.u
        // Lo de abajo se desplaza, no salta (sin «add»: fijaba opacity y anulaba estados desactivados).
        move: Transition { enabled: card.settled && card.ui.reducedMotion !== true
                           NumberAnimation { property: "y"; duration: 240; easing.type: Easing.OutCubic } }
    }
    MouseArea {
        id: tap
        anchors.fill: parent
        enabled: card.clickable
        z: -1
        onClicked: card.activated()
    }
}

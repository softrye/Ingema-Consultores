import QtQuick
import "RStyle.js" as S
import ".." as Mobile
import "../components" as Components             // PresenceAvatars / FieldPresenceHighlight
import InGe.CoreFlow 3.0 as CoreFlowModule           // ganchos «Extrema» del motor único

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
    // Liquid Glass activo: captura lista, o respaldo LOW del material (sin captura).
    readonly property bool liquidOn: !!ui && ui.liquidGlass !== false && !!ui.liquidGlassMaterial
                                     && (glassOn || (ui.liquidGlassMaterial.fallback === true && !!ui.cardGlassUi))
    // Fuera de pantalla no se dibuja el vidrio (ahorra pasadas de GPU al desplazar).
    readonly property bool onScreen: {
        if (!liquidOn) return false
        var tick = ui.cardGlassUi ? ui.cardGlassUi.glassTick : 0
        var p = mapToItem(null, 0, 0)
        return p.y + height > -20 && p.y < (Window.height > 0 ? Window.height : 2400) + 20
    }
    color: liquidOn ? (tap.pressed ? Qt.rgba(1, 1, 1, 0.06) : "transparent") : (tap.pressed ? S.surfaceStrong : S.surface)
    border.width: liquidOn ? 0 : 1
    border.color: S.border
    Mobile.GlassSurface {                             // Liquid Glass oficial (preset único del Dock)
        ui: card.glassOn ? card.ui.cardGlassUi : null
        material: card.liquidOn ? card.ui.liquidGlassMaterial : null
        tint: card.ui.dockGlassTint                  // oscuro igual que claro y el Dock: sin tinte negro
        visible: card.onScreen
        radius: card.radius
        margin: 10 * card.ui.u
    }
    Rectangle {                                       // brillo superior del vidrio oscuro
        visible: S.dark && !card.liquidOn
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
    // «Extrema»: escala y realce del vidrio al pulsar (sólo tarjetas tocables).
    readonly property bool extremePress: card.clickable && CoreFlowModule.InGeCoreFlow.extremeMotion === true
    scale: extremePress && tap.pressed ? CoreFlowModule.InGeCoreFlow.pressScale : 1
    Behavior on scale { enabled: card.extremePress; NumberAnimation { duration: 110; easing.type: Easing.OutQuad } }
    Rectangle {
        anchors.fill: parent; radius: card.radius; z: 2
        visible: card.extremePress && tap.pressed
        color: Qt.rgba(1, 1, 1, CoreFlowModule.InGeCoreFlow.pressHighlight)
    }
    // Presencia en vivo: la tarjeta se ilumina con el color y el nombre de quien
    // edita su sector (`presenceFieldKey` = el `field` que publica ese editor).
    property var presenceMembers: []
    property string presenceFieldKey: ""
    // El foco de un TextField anidado sube hasta la tarjeta; se publica el
    // mismo identificador que usa el halo. No convierte una simple lectura en edición.
    readonly property string presenceField: presenceFieldKey
    Components.FieldPresenceHighlight {
        anchors.fill: parent
        members: card.presenceMembers
        field: card.presenceFieldKey
        radius: card.radius
        u: card.ui ? card.ui.u : 1
        fontFamily: card.ui ? card.ui.fontFamily : ""
        reducedMotion: !!card.ui && card.ui.reducedMotion === true
    }
}

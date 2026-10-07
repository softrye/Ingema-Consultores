import QtQuick
import QtQuick.Window
import QtQuick.Controls
import "../flowcore" as FlowCore

// Liquid Glass REAL de Calicatas: FlowCore.LiquidGlassSurface (el material del Dock
// extraído tal cual, liquidglass.frag) con los TOKENS DEL DOCK. No hay otro shader
// ni otro material; este adaptador solo decide la COMPOSICIÓN.
//
// Tres niveles (como "Información de la calicata"):
//  1. SUPERFICIE PRIMARIA (level "card" / "sheet"): captura y refracta un fondo
//     INTENCIONAL — un ambiente opaco y sin texto marcado "calicataGlassBackdrop"
//     (hermano, nunca ancestro) o, para hojas del Overlay, el contenido de la
//     ventana como el peek. Una primaria dentro de otra primaria NO vuelve a
//     capturar: pasa al tratamiento de control anidado.
//  2. CONTROL (level "control": campos, botones, chips, iconos): el mismo shader y
//     los mismos tokens por su camino SIN captura (material base + borde de luz,
//     bisel y brillo especular). Nunca refracta otra superficie de vidrio: sin
//     recursión, sin texto duplicado, sin coste de captura.
//  3. CONTENIDO (textos, valores, iconos): fuera del vidrio, nítido.
//
// Por qué la captura se limita: con fondo, el shader pinta OPACO (alpha 1) lo que
// capturó; cualquier zona transparente del fondo (esquinas redondeadas de otro
// vidrio, margen fuera del ítem capturado, un velo translúcido) sale NEGRA. Por eso
// solo se capturan ambientes opacos y el rectángulo se recorta dentro de sus límites.
Item {
    id: glass

    property bool dark: false
    property real radius: 12
    property color accent: "#0654A2"
    property color danger: "#D9483B"

    // "glass" | "tinted" (acento) | "primary" (acción principal) | "danger" | "clear"
    property string tone: "glass"
    // "control" | "card" (superficie primaria) | "sheet" (hoja flotante primaria)
    property string level: "control"

    property bool pressed: false
    property bool focused: false
    property bool error: false
    property bool selected: false
    property bool enabledLook: true

    // Fondo explícito opcional (p. ej. el mapa bajo un panel flotante).
    property Item backdrop: null

    // Estado resuelto de la composición.
    property Item _resolvedBackdrop: null
    property bool _nested: false
    readonly property bool primarySurface: glass.level !== "control" && !glass._nested
    // Una captura más alta que esto (px físicos, 4096 = límite seguro en GLES de gama baja) no se pide: no cabe con
    // seguridad en GPUs de gama baja; la superficie queda con el material base.
    readonly property bool _captureFits: glass.width * Screen.devicePixelRatio <= 4096
                                         && glass.height * Screen.devicePixelRatio <= 4096
    // TODAS las superficies (primarias y controles) refractan un fondo real y opaco:
    // el camino sin captura del shader no sirve en claro (ver fallbackGlass abajo).
    // Los controles solo aceptan fondos marcados (ambientes, capas ya desenfocadas de
    // los emergentes), nunca otro vidrio ni la ventana con texto nítido.
    readonly property Item effectiveBackdrop: !glass._captureFits ? null
                                              : glass.backdrop ? glass.backdrop : glass._resolvedBackdrop

    // Marca de superficie primaria: lo que vive dentro no vuelve a capturar.
    objectName: glass.primarySurface ? "calicataGlassPrimary" : ""
    opacity: glass.enabledLook ? 1 : 0.48

    function _isAncestor(candidate) {
        for (var node = glass.parent; node; node = node.parent)
            if (node === candidate) return true
        return false
    }
    function resolveComposition() {
        var nested = false, found = null, child = glass
        for (var node = glass.parent; node; node = node.parent) {
            var kids = node.children
            for (var i = 0; i < kids.length; ++i) {
                var k = kids[i]
                if (k === child || !k.visible) continue
                if (k.objectName === "calicataGlassPrimary") nested = true
                // Un fondo puede exponer su capa estable (glassLayer): los emergentes animan
                // la opacidad de su scrim al abrir, y capturar la raíz re-renderizaría cada
                // control en cada frame; la capa interior desenfocada no cambia.
                else if (!found && k.objectName === "calicataGlassBackdrop") found = k.glassLayer ? k.glassLayer : k
            }
            child = node
        }
        if (!found && glass.level === "sheet") {
            var windowContent = ApplicationWindow.contentItem
            if (windowContent && !glass._isAncestor(windowContent)) found = windowContent
        }
        glass._nested = glass.level !== "control" && nested
        glass._resolvedBackdrop = found
    }
    Component.onCompleted: Qt.callLater(glass.resolveComposition)
    onParentChanged: Qt.callLater(glass.resolveComposition)
    onVisibleChanged: if (visible) Qt.callLater(glass.resolveComposition)

    // Tokens del Dock (GlobalContextDock.qml, mismos valores por tema).
    QtObject {
        id: dockTokens
        readonly property bool shown: glass.visible && glass.opacity > 0 && glass.width > 1 && glass.height > 1
        readonly property Item glassBackdrop: shown ? glass.effectiveBackdrop : null
        readonly property real materialPosition: 0
        readonly property bool lowCostGlass: false
        readonly property color glassTint: glass.dark ? Qt.rgba(0.0824, 0.102, 0.1882, 0.10) : Qt.rgba(0.95, 0.97, 1.0, 0.02)
        // Qt PREMULTIPLICA los colores que pasa a un ShaderEffect (Qt.rgba(r,g,b,a) llega
        // como (r*a, g*a, b*a, a)) y liquidglass.frag vuelve a multiplicar por alpha: un
        // fallback translúcido (0.14) se pinta como un 14 % de casi negro = el GRIS de los
        // campos. Opaco no cambia al premultiplicar: superficie clara/oscura limpia si un
        // fondo aún no está disponible (primer frame).
        readonly property color fallbackGlass: glass.dark ? Qt.rgba(0.14, 0.16, 0.20, 1.0) : Qt.rgba(0.985, 0.99, 1.0, 1.0)
        readonly property real rimLight: glass.dark ? 0.30 : 0.34
        readonly property real rimShade: glass.dark ? 0.08 : 0.07
        readonly property real rimSheen: glass.dark ? 0.06 : 0.03
        readonly property real edgeContrast: glass.dark ? 0.0 : 0.05
        readonly property real glassSaturation: 1.22
        readonly property color shadowColor: Qt.rgba(0.0824, 0.102, 0.1882, glass.dark ? 0.22 : 0.10)
    }

    // Tokens de las superficies PRIMARIAS = los del peek "Información de la calicata"
    // (CalicatasEditorPage, peekGlassTokens: los del primer menú 3D Touch del Dock).
    QtObject {
        id: peekTokens
        readonly property bool shown: dockTokens.shown
        readonly property Item glassBackdrop: dockTokens.glassBackdrop
        readonly property real materialPosition: 0
        readonly property bool lowCostGlass: false
        readonly property color glassTint: glass.dark ? Qt.rgba(0.0824, 0.102, 0.1882, 0.10) : Qt.rgba(0.95, 0.97, 1.0, 0.02)
        // Qt PREMULTIPLICA los colores que pasa a un ShaderEffect (Qt.rgba(r,g,b,a) llega
        // como (r*a, g*a, b*a, a)) y liquidglass.frag vuelve a multiplicar por alpha: un
        // fallback translúcido (0.14) se pinta como un 14 % de casi negro = el GRIS de los
        // campos. Opaco no cambia al premultiplicar: superficie clara/oscura limpia si un
        // fondo aún no está disponible (primer frame).
        readonly property color fallbackGlass: glass.dark ? Qt.rgba(0.14, 0.16, 0.20, 1.0) : Qt.rgba(0.985, 0.99, 1.0, 1.0)
        readonly property real rimLight: glass.dark ? 0.18 : 0.20
        readonly property real rimShade: glass.dark ? 0.04 : 0.035
        readonly property real rimSheen: glass.dark ? 0.03 : 0.015
        readonly property real edgeContrast: glass.dark ? 0.0 : 0.03
        readonly property real glassSaturation: 1.12
        readonly property color shadowColor: Qt.rgba(0.0824, 0.102, 0.1882, glass.dark ? 0.22 : 0.10)
    }

    // Halo de foco / error (estado, fuera del material).
    Rectangle {
        anchors.fill: parent
        anchors.margins: -3
        radius: glass.radius + 3
        color: "transparent"
        border.width: 2
        border.color: Qt.rgba(glass.error ? glass.danger.r : glass.accent.r,
                              glass.error ? glass.danger.g : glass.accent.g,
                              glass.error ? glass.danger.b : glass.accent.b, glass.dark ? 0.55 : 0.38)
        opacity: glass.focused || glass.error ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
    }

    // EL material: misma superficie, mismo shader, mismos tokens que el Dock.
    FlowCore.LiquidGlassSurface {
        id: surface
        anchors.fill: parent
        visible: glass.tone !== "clear" || glass.pressed || glass.selected
        tokens: glass.primarySurface ? peekTokens : dockTokens
        cornerRadius: Math.min(glass.radius, Math.min(glass.width, glass.height) / 2)
        surfaceName: "calicata-" + (glass.primarySurface ? glass.level : "control")
        // Primarias: el preset EXACTO del panel del peek (lens 0.3, frost 8, 6 taps,
        // bisel 14). Controles: preset de las superficies anidadas del Dock (búsqueda /
        // IA). Pulsado/seleccionado = la lente de selección del Dock (más fuerza).
        strength: glass.pressed || glass.selected ? 1.2 : glass.primarySurface ? 1.0 : 0.55
        lens: glass.primarySurface ? 0.3 : 0.8
        frost: glass.primarySurface ? 8 : 3
        frostTaps: glass.primarySurface ? 6 : 4
        magnify: 0
        bevel: glass.primarySurface ? Math.min(14, Math.min(glass.width, glass.height) * 0.3)
                                    : Math.min(6, Math.min(glass.width, glass.height) * 0.19)
        elevation: glass.primarySurface
        // Primarias sobre un ambiente estático que se desplaza con ellas: captura
        // dirigida por eventos (solo re-renderiza si cambian fondo o geometría).
        liveCapture: true
        // Rectángulo de captura recortado DENTRO del fondo (más el margen del shader):
        // nunca se muestrea fuera del ítem capturado (eso pintaría negro).
        captureRect: {
            var b = dockTokens.glassBackdrop
            var dependency = glass.x + glass.y + glass.width + glass.height + (dockTokens.shown ? 1 : 0)
                             + (glass.parent ? glass.parent.y + glass.parent.height : 0)
            if (!b || b.width <= 2 * surface.captureMargin || b.height <= 2 * surface.captureMargin)
                return Qt.rect(0, 0, 0, 0)
            var m = surface.captureMargin
            var p = glass.mapToItem(b, 0, 0)
            var w = Math.min(glass.width, b.width - 2 * m)
            var h = Math.min(glass.height, b.height - 2 * m)
            return Qt.rect(Math.max(m, Math.min(p.x, b.width - w - m)),
                           Math.max(m, Math.min(p.y, b.height - h - m)), w, h)
        }
    }

    // Hojas flotantes: tinte de lectura LIGERO (el fondo llega ya desenfocado desde el
    // scrim del emergente, así que no hace falta un velo lechoso) y filo de luz.
    Rectangle {
        anchors.fill: parent
        radius: surface.cornerRadius
        visible: glass.level === "sheet" && glass.primarySurface
        color: glass.dark ? Qt.rgba(0.0824, 0.102, 0.1882, 0.26) : Qt.rgba(0.98, 0.99, 1.0, 0.24)
        border.width: 1
        border.color: glass.dark ? Qt.rgba(1, 1, 1, 0.10) : Qt.rgba(1, 1, 1, 0.55)
    }

    // Capa SEMÁNTICA sobre el material (no lo sustituye): acento, acción, error.
    Rectangle {
        anchors.fill: parent
        radius: surface.cornerRadius
        visible: glass.tone !== "glass" || glass.pressed || glass.selected
        color: glass.tone === "primary"
               ? Qt.rgba(glass.accent.r, glass.accent.g, glass.accent.b, glass.pressed ? 0.96 : 0.86)
               : glass.tone === "tinted" || glass.tone === "danger" || glass.selected
                 ? Qt.rgba(glass.tone === "danger" ? glass.danger.r : glass.accent.r,
                           glass.tone === "danger" ? glass.danger.g : glass.accent.g,
                           glass.tone === "danger" ? glass.danger.b : glass.accent.b,
                           (glass.dark ? 0.20 : 0.12) + (glass.pressed ? 0.08 : 0))
                 : Qt.rgba(1, 1, 1, glass.pressed ? (glass.dark ? 0.10 : 0.24) : 0)
        border.width: glass.selected || glass.focused || glass.error ? 1 : 0
        border.color: glass.error ? glass.danger
                      : Qt.rgba(glass.accent.r, glass.accent.g, glass.accent.b, glass.focused ? 0.9 : 0.5)
        Behavior on color { ColorAnimation { duration: 140 } }
    }
}

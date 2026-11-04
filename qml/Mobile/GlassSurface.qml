import QtQuick
import InGe 1.0                                  // GraphicsCore: perfil de fidelidad
import "renditions/RStyle.js" as RenderStats

// Superficie de cristal esmerilado del Home (2026-10-12). Se coloca como
// primer hijo (debajo de textos e iconos, que quedan nítidos) y ocupa su
// padre más un margen para la sombra. Muestrea la textura desenfocada
// COMPARTIDA del Home (ui.glassTexture) en la región que coincide con la
// fotografía (ui.backdrop); ui.glassTick avisa de cambios de posición.
Item {
    id: glass
    Component.onCompleted: {
        RenderStats.renderCount("glass_created")
        if (source) shaderSource = source
    }

    property var ui
    // Liquid Glass oficial (2026-11-02): HomeScreen.liquidGlassMaterial, el
    // preset ÚNICO del Dock para toda la app. Con material, sus valores son los
    // predeterminados y en LOW se dibuja su respaldo (sin shader ni captura).
    property var material: null
    // Respaldo en LOW (salvo lowFallback: false, el Dock: lente sin refracción)
    // o mientras la captura aún no está lista.
    property bool lowFallback: true
    readonly property bool fallbackOn: !!material && ((lowFallback && material.fallback === true) || !textureReady)
    property real radius: 18
    property real margin: 10                     // sombra exterior
    property color tint: material ? material.tint : Qt.rgba(28 / 255, 45 / 255, 80 / 255, 0.38)   // #1C2D50
    property color edge: material ? material.edge : Qt.rgba(1, 1, 1, 0.26)
    property real edgeWidth: 1
    property real shadowAlpha: material ? material.shadowAlpha : 0.22
    property color shadowColor: "#151A30"
    // Óptica opcional (InGe Earth). En 0, idéntico al material del Home.
    property real refraction: material ? material.refraction : 0   // px de lente en el borde
    property real specular: material ? material.specular : 0       // 0..1 brillo especular / filo de luz
    property real bevel: material ? material.bevel : 0             // px de la zona curva del borde
    // Material del Dock: contraste adaptativo y esmerilado propio. En 0, sin cambios.
    property real contrast: material ? material.contrast : 0       // 0..1
    property real frost: material ? material.frost : 0             // px
    // VERY_HIGH/EXTREME (GraphicsCore.textSmoothing > 0): 9 muestras de esmerilado en lugar de 5.
    property real frostQuality: GraphicsCore.textSmoothing > 0 ? 1 : 0
    // Perfil «Extrema» (GraphicsCore.extremeGlass; si no existe, false): lente que
    // respira, gotas y muestreo de alta calidad en el material del Dock (specular >= 0,95).
    // Desactivado, el shader no evalúa nada nuevo: resultado idéntico.
    property bool extreme: GraphicsCore.extremeGlass === true
    property bool reducedMotion: false
    property real gel: 0                         // 0..1 estiramiento tipo gel
    property var drops: []                       // hasta 8 vector4d: x, y (px locales), radio, vida
    readonly property vector4d noDrop: Qt.vector4d(0, 0, 0, 0)
    function dropAt(i) { return i < drops.length ? drops[i] : noDrop }
    FrameAnimation {
        id: glassClock
        running: glass.extreme && !glass.reducedMotion && glass.specular >= 0.95
                 && glass.visible && glass.textureReady && !glass.fallbackOn
    }

    anchors.fill: parent
    anchors.margins: -margin
    z: -1

    property var source: ui ? ui.glassTexture : null
    // Último proveedor válido: el ShaderEffect nunca recibe null (aviso «Texture t1
    // is not assigned a valid texture provider» al volver de una subapp). Mientras
    // la captura no está lista se ve el respaldo; sin ningún proveedor aún, el
    // shader no existe.
    property var shaderSource: null
    onSourceChanged: if (source) shaderSource = source
    // Callers may override this item's visibility. The shader owns its own
    // texture guard so that an inherited visible:true cannot draw a null sampler.
    readonly property bool textureReady: !!source && !!ui
                                         && ui.glassReady !== false
                                         && (source.sourceItem === undefined || !!source.sourceItem)
                                         && width > 0 && height > 0
    property vector2d itemSize: Qt.vector2d(width, height)
    property vector4d region: {
        var tick = ui ? ui.glassTick : 0      // dependencia de reposicionamiento
        var backdrop = ui ? ui.backdrop : null
        if (!backdrop || backdrop.width <= 0 || backdrop.height <= 0 || width <= 0)
            return Qt.vector4d(0, 0, 1, 1)
        var p = glass.mapToItem(backdrop, margin, margin)
        return Qt.vector4d(p.x / backdrop.width, p.y / backdrop.height,
                           (width - 2 * margin) / backdrop.width,
                           (height - 2 * margin) / backdrop.height)
    }

    visible: textureReady || fallbackOn
    Rectangle {                                  // respaldo LOW: cristal neutro del Dock
        visible: glass.fallbackOn
        anchors.fill: parent
        anchors.margins: glass.margin
        radius: glass.radius
        border.width: 1
        border.color: glass.material ? glass.material.fallbackEdge : "transparent"
        gradient: Gradient {
            GradientStop { position: 0.0; color: glass.material ? glass.material.fallbackTop : "transparent" }
            GradientStop { position: 0.5; color: glass.material ? glass.material.fallbackMid : "transparent" }
            GradientStop { position: 1.0; color: glass.material ? glass.material.fallbackBottom : "transparent" }
        }
    }
    Loader {
        anchors.fill: parent
        active: !!glass.shaderSource
        visible: glass.textureReady && !glass.fallbackOn
        enabled: visible
        sourceComponent: ShaderEffect {
            objectName: "glassShader"
            anchors.fill: parent
            property var source: glass.shaderSource
            property vector2d itemSize: glass.itemSize
            property vector4d region: glass.region
            property real radius: glass.radius
            property real margin: glass.margin
            property color tint: glass.tint
            property color edge: glass.edge
            property real edgeWidth: glass.edgeWidth
            property real shadowAlpha: glass.shadowAlpha
            property color shadowColor: glass.shadowColor
            property real refraction: glass.refraction
            property real specular: glass.specular
            property real bevel: glass.bevel
            property real contrast: glass.contrast
            property real frost: glass.frost
            property real frostQuality: glass.frostQuality
            property real extreme: glass.extreme ? 1 : 0
            property real time: glass.extreme ? glassClock.elapsedTime : 0
            property real gel: glass.extreme && !glass.reducedMotion ? glass.gel : 0
            property vector4d drop0: glass.dropAt(0)
            property vector4d drop1: glass.dropAt(1)
            property vector4d drop2: glass.dropAt(2)
            property vector4d drop3: glass.dropAt(3)
            property vector4d drop4: glass.dropAt(4)
            property vector4d drop5: glass.dropAt(5)
            property vector4d drop6: glass.dropAt(6)
            property vector4d drop7: glass.dropAt(7)
            fragmentShader: "qrc:/InGe/Mobile/shaders/glass.frag.qsb"
        }
    }
}

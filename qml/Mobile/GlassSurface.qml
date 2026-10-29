import QtQuick
import "renditions/RStyle.js" as RenderStats

// Superficie de cristal esmerilado del Home (2026-10-12). Se coloca como
// primer hijo (debajo de textos e iconos, que quedan nítidos) y ocupa su
// padre más un margen para la sombra. Muestrea la textura desenfocada
// COMPARTIDA del Home (ui.glassTexture) en la región que coincide con la
// fotografía (ui.backdrop); ui.glassTick avisa de cambios de posición.
ShaderEffect {
    id: glass
    Component.onCompleted: RenderStats.renderCount("glass_created")

    property var ui
    property real radius: 18
    property real margin: 10                     // sombra exterior
    property color tint: Qt.rgba(28 / 255, 45 / 255, 80 / 255, 0.38)   // #1C2D50
    property color edge: Qt.rgba(1, 1, 1, 0.26)
    property real edgeWidth: 1
    property real shadowAlpha: 0.22
    property color shadowColor: "#151A30"
    // Óptica opcional (InGe Earth). En 0, idéntico al material del Home.
    property real refraction: 0                  // px de lente en el borde
    property real specular: 0                    // 0..1 brillo especular / filo de luz
    property real bevel: 0                       // px de la zona curva del borde
    // Material del Dock: contraste adaptativo y esmerilado propio. En 0, sin cambios.
    property real contrast: 0                    // 0..1
    property real frost: 0                       // px

    anchors.fill: parent
    anchors.margins: -margin
    z: -1

    property var source: ui ? ui.glassTexture : null
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

    visible: source !== null
    fragmentShader: "qrc:/InGe/Mobile/shaders/glass.frag.qsb"
}

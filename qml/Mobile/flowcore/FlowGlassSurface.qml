import QtQuick 2.15
import InGe.CoreFlow 3.0 as Mobile

// Superficie de material plano de InGe+: color de tema, estado y borde.
// Sin vidrio, captura, desenfoque ni sombra.
Rectangle {
    id: root

    property var flow: Mobile.InGeCoreFlow
    property bool darkMode: flow.theme.isDark
    property string materialRole: "regular" // clear | regular | emphasized | light | dark
    property bool selected: false
    property bool pressed: false
    property color fallbackLight: flow.theme.surfaceElevated
    property color fallbackDark: flow.theme.surfaceElevated
    property color overlayTintColor: "transparent"
    property real overlayTintOpacity: 0.0
    // Entradas de la superficie anterior que algunas pantallas aún asignan; no
    // tienen efecto. Se retiran al reconstruir esas pantallas.
    property Item blurSource: null
    property bool blurEnabled: false
    property bool elevationEnabled: false
    property bool highlightEnabled: false
    property bool edgeDispersionEnabled: false
    property real strength: 1.0
    property real blurAmount: 0.0
    property real blurSaturation: 0.0

    readonly property bool effectiveDarkMode: materialRole === "dark"
                                               ? true
                                               : (materialRole === "light" ? false : darkMode)

    function mixColor(baseColor, tintColor, amount) {
        var t = Math.max(0.0, Math.min(1.0, Number(amount)))
        return Qt.rgba(baseColor.r + (tintColor.r - baseColor.r) * t,
                       baseColor.g + (tintColor.g - baseColor.g) * t,
                       baseColor.b + (tintColor.b - baseColor.b) * t,
                       baseColor.a + (tintColor.a - baseColor.a) * t)
    }

    readonly property color baseColor: effectiveDarkMode ? fallbackDark : fallbackLight
    readonly property color stateColor: pressed
        ? mixColor(baseColor, flow.theme.textPrimary, 0.075)
        : (selected ? mixColor(baseColor, flow.theme.accent, 0.16) : baseColor)

    color: overlayTintOpacity > 0 ? mixColor(stateColor, overlayTintColor, overlayTintOpacity) : stateColor
    border.color: selected ? mixColor(flow.theme.border, flow.theme.accent, 0.48) : flow.theme.border
    border.width: selected ? 1.35 : 1
    antialiasing: true
    clip: true
}

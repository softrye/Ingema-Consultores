import QtQuick
import "../renditions/RStyle.js" as RS

// Mismo material translúcido que RCard/SectionCard/RGlassMenu de Rendiciones.
// Sólo mezcla alfa: sin capturas, desenfoques ni efectos por control.
Rectangle {
    id: surface

    property bool dark: false
    property color accent: "#0654A2"
    property color danger: "#D9483B"
    // "glass" (neutro) | "tinted" (acento) | "primary" (acción principal) | "danger" | "clear"
    property string tone: "glass"
    // "control" | "card" | "sheet"
    property string level: "control"
    property bool pressed: false
    property bool focused: false
    property bool error: false
    property bool selected: false
    property bool enabledLook: true

    readonly property real materialAlpha: {
        var c = level === "card" ? RS.cardGlass
              : level === "sheet" ? RS.popup : RS.surface
        var a = c !== undefined && c !== null ? c.a : undefined
        if (typeof a === "number" && isFinite(a))
            return a
        // RStyle.js puede entregar colores sin propiedad .a (p. ej. hexadecimal).
        // Conservar el alfa original de cada nivel/tema sin asignar undefined.
        return level === "card" ? (RS.dark ? 0.55 : 0.62)
             : level === "sheet" ? (RS.dark ? 0.96 : 0.94)
             : (RS.dark ? 0.62 : 0.86)
    }
    // Ficha (patrón QField): controles y tarjetas como vidrio claro de borde fino
    // sobre la hoja; «sheet» (emergentes) conserva su material opaco.
    readonly property color neutral: RS.halloween ? RS.glass(0.94)
        : level === "sheet" ? (dark ? Qt.rgba(28 / 255, 45 / 255, 80 / 255, materialAlpha) : RS.popup)
        : level === "card" ? (dark ? Qt.rgba(1, 1, 1, 0.04) : Qt.rgba(1, 1, 1, 0.45))
        : (dark ? Qt.rgba(1, 1, 1, 0.07) : Qt.rgba(1, 1, 1, 0.75))
    readonly property color toneColor: tone === "primary" ? accent
        : tone === "danger" ? Qt.tint(neutral, Qt.rgba(danger.r, danger.g, danger.b, dark ? 0.28 : 0.14))
        : (tone === "tinted" || selected) ? Qt.tint(neutral, Qt.rgba(accent.r, accent.g, accent.b, dark ? 0.28 : 0.14))
        : tone === "clear" ? "transparent"
        : neutral

    color: pressed && tone !== "clear" ? Qt.darker(toneColor, dark ? 0.85 : 1.08)
           : pressed ? (dark ? Qt.rgba(1, 1, 1, 0.10) : Qt.rgba(0, 0, 0, 0.06))
           : toneColor
    border.width: error || focused || selected ? 2 : (tone === "clear" ? 0 : 1)
    border.color: RS.halloween && !error && !focused && !selected ? RS.edge(0.95) : error ? danger
                  : (focused || selected) ? accent
                  : level === "sheet" ? (dark ? Qt.rgba(1, 1, 1, 0.10) : Qt.rgba(1, 1, 1, 0.90))
                  : (dark ? Qt.rgba(1, 1, 1, 0.16) : Qt.rgba(21 / 255, 26 / 255, 48 / 255, level === "card" ? 0.10 : 0.16))
    opacity: enabledLook ? 1 : 0.48
}

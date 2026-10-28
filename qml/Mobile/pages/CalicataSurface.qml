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

    readonly property real materialAlpha: level === "card" ? RS.cardGlass.a
        : level === "sheet" ? RS.popup.a : RS.surface.a
    readonly property color neutral: dark
        ? Qt.rgba(28 / 255, 45 / 255, 80 / 255, materialAlpha)
        : level === "card" ? RS.cardGlass : level === "sheet" ? RS.popup : RS.surface
    readonly property color toneColor: tone === "primary" ? accent
        : tone === "danger" ? Qt.tint(neutral, Qt.rgba(danger.r, danger.g, danger.b, dark ? 0.28 : 0.14))
        : (tone === "tinted" || selected) ? Qt.tint(neutral, Qt.rgba(accent.r, accent.g, accent.b, dark ? 0.28 : 0.14))
        : tone === "clear" ? "transparent"
        : neutral

    color: pressed && tone !== "clear" ? Qt.darker(toneColor, dark ? 0.85 : 1.08)
           : pressed ? (dark ? Qt.rgba(1, 1, 1, 0.10) : Qt.rgba(0, 0, 0, 0.06))
           : toneColor
    border.width: error || focused || selected ? 2 : (tone === "clear" ? 0 : 1)
    border.color: error ? danger
                  : (focused || selected) ? accent
                  : (dark ? Qt.rgba(1, 1, 1, 0.10) : (level === "control" ? RS.border : Qt.rgba(1, 1, 1, 0.90)))
    opacity: enabledLook ? 1 : 0.48
}

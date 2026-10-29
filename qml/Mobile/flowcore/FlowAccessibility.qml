import QtQuick 2.15

QtObject {
    property bool reducedMotion: false
    property bool highContrast: false
    property bool focusVisible: true
    // Main.qml lo enlaza a app.effectiveTextScale (A-/A+ x fuente de Android,
    // limitado a 0.85-1.30), la misma escala que usa su fs().
    property real textScale: 1.0
    property int minimumTouchTarget: 48
    property bool transparentSurfaces: true

    function scaledTextSize(baseSize) {
        return Math.max(10, Math.round(Number(baseSize) * textScale))
    }

    function touchSize(requestedSize) {
        return Math.max(minimumTouchTarget, Number(requestedSize))
    }

    function contrastBorder(baseColor, highContrastColor) {
        return highContrast ? highContrastColor : baseColor
    }

    function surfaceOpacity(requestedOpacity) {
        if (highContrast || !transparentSurfaces)
            return 1.0
        return Math.max(0.58, Math.min(1.0, Number(requestedOpacity)))
    }
}

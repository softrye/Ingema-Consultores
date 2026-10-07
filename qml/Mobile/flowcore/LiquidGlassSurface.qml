import QtQuick
import QtQuick.Effects

// InGe+ Liquid Glass surface: the Dock material extracted verbatim from
// GlobalContextDock.qml so every approved surface (Dock, Calicatas info
// peek) shares one pipeline: local backdrop capture refracted, frosted and
// lit by liquidglass.frag. `tokens` supplies the material (see the Dock).
Item {
    id: surface
    required property var tokens
    property real cornerRadius: height / 2
    property real strength: 1
    property real lens: 1
    property real frost: 5
    property real magnify: 0
    property real frostTaps: 12
    property real lowCostTaps: 2
    property string surfaceName: ""
    // Extra geometry dependency for a surface whose container moves
    // (the context menu panel); the capsule surfaces leave it at 0.
    property real positionKey: 0
    property string reportedStatus: ""
    // A shader the driver rejects is dropped once (no per-frame retries);
    // the surface degrades to a flat rim material and the error is logged.
    property bool shaderFailed: false
    property bool elevation: true
    // Static surfaces (a modal peek over a blocked page) freeze the backdrop:
    // one grab when capture starts, no re-render while open. Default: live.
    property bool liveCapture: true
    // Backdrop-space rect to sample instead of mapping the item each frame
    // (lets a transformed/animated surface keep a single stable grab).
    property rect captureRect: Qt.rect(0, 0, 0, 0)
    // Bevel width override; 0 keeps the Dock formula (19% of the short side),
    // which on a large panel reads as thick glass.
    property real bevel: 0
    readonly property real captureMargin: 6
    readonly property bool captureActive: surface.visible && surface.tokens.shown
        && !!surface.tokens.glassBackdrop

    Item {
        id: emptyBackdrop
        width: 1
        height: 1
    }

    // Event-driven, once per final state. Uncompiled is Qt's front-end
    // bookkeeping (it can stay there while the effect renders), so it is
    // never reported as a verdict; only Compiled and Error are.
    function reportShaderStatus() {
        var s = glassEffect.status
        if (s !== ShaderEffect.Compiled && s !== ShaderEffect.Error)
            return
        var name = s === ShaderEffect.Compiled ? "compiled" : "error"
        if (name === surface.reportedStatus)
            return
        surface.reportedStatus = name
        console.info("INGE_DOCK_SHADER_STATUS surface=" + surface.surfaceName + " status=" + name
                     + (s === ShaderEffect.Error ? " log=" + glassEffect.log : ""))
    }
    Component.onCompleted: reportShaderStatus()
    onCaptureActiveChanged: {
        if (captureActive && !liveCapture)
            localBackdrop.scheduleUpdate()
    }

    ShaderEffectSource {
        id: localBackdrop
        sourceItem: surface.captureActive ? surface.tokens.glassBackdrop : emptyBackdrop
        sourceRect: {
            var geometryDependency = surface.tokens.materialPosition
                + surface.x + surface.y + surface.width + surface.height + surface.positionKey
            if (!surface.captureActive)
                return Qt.rect(0, 0, 1, 1)
            var m = surface.captureMargin
            if (surface.captureRect.width > 0 && surface.captureRect.height > 0)
                return Qt.rect(surface.captureRect.x - m, surface.captureRect.y - m,
                               surface.captureRect.width + 2 * m, surface.captureRect.height + 2 * m)
            var p = surface.mapToItem(surface.tokens.glassBackdrop, 0, 0)
            return Qt.rect(p.x - m, p.y - m,
                           Math.max(1, surface.width + 2 * m),
                           Math.max(1, surface.height + 2 * m))
        }
        // Re-renders only when the backdrop subtree is dirty; no timer.
        live: surface.captureActive && surface.liveCapture
        // A frozen grab must be retaken when its rect settles after the first
        // frame; a resized, un-regrabbed layer is empty (reads as grey glass).
        onSourceRectChanged: {
            if (surface.captureActive && !surface.liveCapture)
                scheduleUpdate()
        }
        recursive: false
        hideSource: false
        visible: false
    }

    RectangularShadow {
        anchors.fill: parent
        // No soft shadow pass on Earth (GPU shared with Cesium).
        visible: surface.elevation && surface.captureActive && !surface.tokens.lowCostGlass
        radius: surface.cornerRadius
        offset: Qt.vector2d(0, 2)
        blur: 8
        spread: -2
        color: surface.tokens.shadowColor
    }

    ShaderEffect {
        id: glassEffect
        anchors.fill: parent
        visible: !surface.shaderFailed && width > 1 && height > 1
        property var source: localBackdrop
        property size itemSize: Qt.size(Math.max(1, width), Math.max(1, height))
        property real margin: surface.captureMargin
        property real radius: Math.min(surface.cornerRadius, Math.min(width, height) / 2)
        property real thickness: surface.bevel > 0 ? surface.bevel
                                                   : Math.max(4, Math.min(width, height) * 0.19)
        property real refraction: 0.2 * surface.lens
        property real magnify: surface.magnify
        property real edgeContrast: surface.tokens.edgeContrast * surface.strength
        property real frost: surface.frost
        property real taps: surface.tokens.lowCostGlass ? surface.lowCostTaps : surface.frostTaps
        property real rimLight: surface.tokens.rimLight * surface.strength
        property real rimShade: surface.tokens.rimShade * surface.strength
        property real rimSheen: surface.tokens.rimSheen * surface.strength
        property real saturation: surface.tokens.glassSaturation
        property real backdropMix: surface.captureActive ? 1.0 : 0.0
        Behavior on backdropMix { NumberAnimation { duration: 140 } }
        property color tint: Qt.rgba(surface.tokens.glassTint.r, surface.tokens.glassTint.g,
                                     surface.tokens.glassTint.b,
                                     Math.min(1, surface.tokens.glassTint.a * surface.strength))
        property color fallbackColor: surface.tokens.fallbackGlass
        fragmentShader: "qrc:/InGe/Mobile/shaders/liquidglass.frag.qsb"
        onStatusChanged: {
            if (status === ShaderEffect.Error) {
                console.warn("INGE_DOCK_GLASS_SHADER_ERROR surface=" + surface.surfaceName + " " + log)
                surface.shaderFailed = true
            }
            surface.reportShaderStatus()
        }
    }

    Rectangle {
        anchors.fill: parent
        visible: surface.shaderFailed
        radius: surface.cornerRadius
        color: surface.tokens.fallbackGlass
        border.width: 1
        border.color: Qt.rgba(1, 1, 1, surface.tokens.rimLight * 0.8)
    }
}

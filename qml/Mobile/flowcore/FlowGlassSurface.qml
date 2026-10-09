pragma ComponentBehavior: Bound

import QtQuick 2.15
import QtQuick.Effects
import InGe.CoreFlow 3.0 as Mobile

Rectangle {
    id: root

    property var flow: Mobile.InGeCoreFlow
    property bool darkMode: flow.theme.isDark
    property string materialRole: "regular" // clear | regular | emphasized | light | dark
    property real strength: 1.0
    property bool highlightEnabled: true
    property bool selected: false
    property bool pressed: false
    property Item blurSource: null
    property bool blurEnabled: true
    property real blurAmount: flow.theme.glassBlur
    property real blurSaturation: flow.theme.glassSaturation
    property color fallbackLight: flow.theme.surfaceElevated
    property color fallbackDark: flow.theme.surfaceElevated
    property color overlayTintColor: "transparent"
    property real overlayTintOpacity: 0.0
    property bool edgeDispersionEnabled: true
    property bool elevationEnabled: materialRole === "emphasized"

    readonly property bool effectiveDarkMode: materialRole === "dark"
                                               ? true
                                               : (materialRole === "light"
                                                  ? false : darkMode)

    // Live ShaderEffectSource captures of the Qt scene are unstable when a
    // Flutter TextureView is interleaved with the Qt surface on the A12. Keep
    // the Liquid Glass tint/rim/specular pipeline active without scene capture.
    readonly property bool realBlurActive: false

    // Only emphasized, idle groups with a separate backdrop opt into the Dock
    // pipeline. Rows/ordinary cards keep the established lightweight material.
    function canCaptureBackdrop() {
        if (!root.blurSource) return false
        var item = root
        while (item) {
            if (item === root.blurSource) return false // never sample an ancestor
            item = item.parent
        }
        return true
    }
    function idleInViewport() {
        var item = root.parent
        while (item) {
            var viewport = item as Flickable
            if (viewport) {
                if (viewport.moving) return false
                var point = root.parent.mapToItem(viewport.contentItem, root.x, root.y)
                return point.y + root.height > viewport.contentY
                    && point.y < viewport.contentY + viewport.height
            }
            item = item.parent
        }
        return true
    }
    readonly property bool canonicalActive: root.visible && root.blurEnabled
        && root.materialRole === "emphasized" && root.flow.theme.isGlass
        && !!root.flow.glassMaterial && root.flow.performance.shaderEffectsEnabled
        && root.flow.motionAllowed
        && !root.flow.earthActive && root.canCaptureBackdrop() && root.idleInViewport()

    QtObject {
        id: dockMaterial
        readonly property var material: root.flow.glassMaterial
        readonly property bool shown: root.canonicalActive
        readonly property Item glassBackdrop: root.blurSource
        readonly property real materialPosition: 0
        readonly property bool lowCostGlass: root.flow.performance.profile >= root.flow.performance.balanced
        readonly property color glassTint: !material ? "transparent" : root.pressed
            ? root.mixColor(material.glassTint, root.flow.theme.textPrimary, 0.10)
            : (root.selected ? root.mixColor(material.glassTint, root.flow.theme.accent, 0.20) : material.glassTint)
        readonly property color fallbackGlass: material ? material.fallbackGlass : root.stateFallbackColor
        readonly property real rimLight: material ? material.rimLight : 0
        readonly property real rimShade: material ? material.rimShade : 0
        readonly property real rimSheen: material ? material.rimSheen : 0
        readonly property real edgeContrast: material ? material.edgeContrast : 0
        readonly property real glassSaturation: material ? material.glassSaturation : 1
        readonly property color shadowColor: material ? material.shadowColor : "transparent"
    }

    readonly property color materialColor: materialRole === "clear"
                                             ? flow.theme.glassClear
                                             : (materialRole === "emphasized"
                                                ? flow.theme.glassEmphasized
                                                : (materialRole === "light"
                                                   ? Qt.rgba(0.96, 0.98, 0.99, 0.64)
                                                   : (materialRole === "dark"
                                                      ? Qt.rgba(0.1098, 0.1765, 0.3137, 0.62)
                                                      : flow.theme.glassRegular)))

    function mixColor(baseColor, tintColor, amount) {
        var t = Math.max(0.0, Math.min(1.0, Number(amount)))
        return Qt.rgba(baseColor.r + (tintColor.r - baseColor.r) * t,
                       baseColor.g + (tintColor.g - baseColor.g) * t,
                       baseColor.b + (tintColor.b - baseColor.b) * t,
                       baseColor.a + (tintColor.a - baseColor.a) * t)
    }

    readonly property color baseFallbackColor: effectiveDarkMode
                                                ? fallbackDark : fallbackLight
    readonly property color stateFallbackColor: pressed
        ? mixColor(baseFallbackColor, flow.theme.textPrimary, 0.075)
        : (selected
           ? mixColor(baseFallbackColor, flow.theme.accent, 0.16)
           : baseFallbackColor)
    readonly property color stateMaterialColor: pressed
        ? mixColor(materialColor, flow.theme.textPrimary, 0.10)
        : (selected
           ? mixColor(materialColor, flow.theme.accent, 0.20)
           : materialColor)

    function mappedSourceRect() {
        if (!blurSource)
            return Qt.rect(0, 0, 0, 0)
        var point = root.mapToItem(blurSource, 0, 0)
        return Qt.rect(point.x, point.y, root.width, root.height)
    }

    color: root.canonicalActive ? "transparent" : flow.theme.isGlass
           ? Qt.rgba(stateMaterialColor.r,
                     stateMaterialColor.g,
                     stateMaterialColor.b,
                     Math.min(0.94, stateMaterialColor.a
                              * (realBlurActive ? 0.72 : 1.0)
                              * Math.max(0.72, strength)))
           : stateFallbackColor

    border.color: selected
                  ? mixColor(flow.theme.glassBorder, flow.theme.accent, 0.48)
                  : (flow.theme.isGlass ? flow.theme.glassBorder
                                        : flow.theme.border)
    border.width: selected ? 1.35 : 1
    antialiasing: true
    clip: true

    layer.enabled: elevationEnabled
                   && !root.canonicalActive
                   && visible
                   && flow.performance.secondaryEffectsEnabled
    layer.effect: MultiEffect {
        shadowEnabled: true
        shadowColor: root.flow.theme.glassShadow
        blurMax: 32
        shadowBlur: root.materialRole === "emphasized" ? 0.82 : 0.58
        shadowHorizontalOffset: 0
        shadowVerticalOffset: root.materialRole === "emphasized" ? 8 : 5
        autoPaddingEnabled: true
    }

    Loader {
        anchors.fill: parent
        active: root.canonicalActive
        sourceComponent: Component {
            LiquidGlassSurface {
                tokens: dockMaterial
                cornerRadius: root.radius
                strength: root.strength
                lens: 0.35
                frost: 4.5
                frostTaps: 6
                liveCapture: false
                elevation: root.elevationEnabled
                bevel: Math.max(4, Math.min(width, height) * 0.08)
                surfaceName: "flow-secondary"
            }
        }
    }

    // The scene-capture blur is disabled (realBlurActive, see above). Its mask
    // layer, capture and MultiEffect are only created if it is enabled again,
    // instead of in every FlowGlassSurface (Buscador, Perfil, Documentos...).
    Loader {
        id: realBlurLoader
        anchors.fill: parent
        active: root.realBlurActive
        sourceComponent: Item {
            readonly property alias capture: glassCapture
            readonly property alias mask: glassMask

            Rectangle {
                id: glassMask
                anchors.fill: parent
                radius: root.radius
                color: "white"
                visible: false
                layer.enabled: true
            }

            ShaderEffectSource {
                id: glassCapture
                anchors.fill: parent
                sourceItem: root.blurSource
                sourceRect: root.mappedSourceRect()
                live: root.realBlurActive && root.visible
                hideSource: false
                visible: false
            }

            MultiEffect {
                anchors.fill: parent
                source: glassCapture
                visible: root.realBlurActive
                blurEnabled: true
                blur: root.blurAmount
                blurMax: root.materialRole === "emphasized" ? 64 : 48
                saturation: root.blurSaturation
                opacity: root.flow.theme.glassOpacity
                scale: 1.0 + root.flow.theme.glassRefraction * 0.018
                maskEnabled: true
                maskSource: glassMask
                autoPaddingEnabled: false
            }
        }
    }

    // Fallback material visible even when the renderer cannot sample the
    // backdrop. It provides directional light and depth without pretending
    // that an unavailable blur exists.
    Rectangle {
        anchors.fill: parent
        radius: root.radius
        enabled: false
        visible: root.flow.theme.isGlass && !root.canonicalActive
        opacity: root.realBlurActive ? 0.48 : 0.82
        gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop {
                position: 0.0
                color: root.effectiveDarkMode
                       ? Qt.rgba(0.561, 0.698, 0.835, 0.12)
                       : Qt.rgba(1.0, 1.0, 1.0, 0.42)
            }
            GradientStop {
                position: 0.36
                color: "transparent"
            }
            GradientStop {
                position: 1.0
                color: root.effectiveDarkMode
                       ? Qt.rgba(0.0824, 0.102, 0.1882, 0.18)
                       : Qt.rgba(0.0235, 0.3294, 0.6353, 0.055)
            }
        }
    }

    // Lightweight edge dispersion: two gated capture passes shift opposite
    // color channels by a fraction of the centralized refraction token.
    Loader {
        anchors.fill: parent
        active: root.realBlurActive && realBlurLoader.status === Loader.Ready
        sourceComponent: Item {
            MultiEffect {
                anchors.fill: parent
                source: realBlurLoader.item.capture
                visible: root.realBlurActive
                         && root.edgeDispersionEnabled
                         && root.flow.performance.reflectionsEnabled
                         && root.flow.theme.glassChromaticDispersion > 0
                blurEnabled: false
                colorization: 1.0
                colorizationColor: "#FF5E8B"
                opacity: root.flow.theme.glassChromaticDispersion * 2.6
                transform: Translate {
                    x: -root.flow.theme.glassRefraction * 7.0
                    y: -root.flow.theme.glassRefraction * 2.0
                }
                maskEnabled: true
                maskSource: realBlurLoader.item.mask
                autoPaddingEnabled: false
            }

            MultiEffect {
                anchors.fill: parent
                source: realBlurLoader.item.capture
                visible: root.realBlurActive
                         && root.edgeDispersionEnabled
                         && root.flow.performance.reflectionsEnabled
                         && root.flow.theme.glassChromaticDispersion > 0
                blurEnabled: false
                colorization: 1.0
                colorizationColor: "#55D7FF"
                opacity: root.flow.theme.glassChromaticDispersion * 2.6
                transform: Translate {
                    x: root.flow.theme.glassRefraction * 7.0
                    y: root.flow.theme.glassRefraction * 2.0
                }
                maskEnabled: true
                maskSource: realBlurLoader.item.mask
                autoPaddingEnabled: false
            }
        }
    }

    Rectangle {
        anchors.fill: parent
        radius: root.radius
        enabled: false
        visible: root.flow.theme.isGlass && !root.canonicalActive
        color: root.flow.theme.glassTint
        opacity: root.materialRole === "clear" ? 0.48
                 : (root.materialRole === "emphasized" ? 0.86 : 0.68)
    }

    Rectangle {
        anchors.fill: parent
        radius: root.radius
        enabled: false
        visible: root.flow.theme.isGlass && root.overlayTintOpacity > 0
        color: root.overlayTintColor
        opacity: root.overlayTintOpacity
    }

    Rectangle {
        anchors.fill: parent
        radius: parent.radius
        enabled: false
        visible: root.flow.theme.isGlass && !root.canonicalActive
                 && root.highlightEnabled
                 && root.flow.translucentSurfacesEnabled === true
                 && root.flow.performance.reflectionsEnabled
        color: "transparent"

        gradient: Gradient {
            GradientStop {
                position: 0.0
                color: root.flow.theme.glassSpecular
            }
            GradientStop {
                position: 0.42
                color: "transparent"
            }
            GradientStop {
                position: 1.0
                color: root.effectiveDarkMode
                       ? "#120654A2"
                       : "#080654A2"
            }
        }
        opacity: root.flow.performance.reflectionIntensity
    }

    Rectangle {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.leftMargin: Math.max(2, root.radius * 0.32)
        anchors.rightMargin: Math.max(2, root.radius * 0.32)
        height: 1
        visible: root.flow.theme.isGlass && !root.canonicalActive && root.highlightEnabled
        color: root.flow.theme.glassHighlight
        opacity: root.materialRole === "emphasized" ? 0.88 : 0.68
    }

    Rectangle {
        anchors.fill: parent
        anchors.margins: 1.5
        radius: Math.max(0, root.radius - 1.5)
        color: "transparent"
        border.width: 1
        border.color: root.flow.theme.glassInnerLight
        visible: root.flow.theme.isGlass && !root.canonicalActive
                 && root.highlightEnabled
                 && root.flow.performance.reflectionsEnabled
        opacity: root.materialRole === "emphasized" ? 0.88 : 0.62
    }

    Rectangle {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.leftMargin: Math.max(3, root.radius * 0.48)
        anchors.rightMargin: Math.max(3, root.radius * 0.48)
        height: 1
        visible: root.flow.theme.isGlass && root.highlightEnabled
        color: root.flow.theme.glassBorder
        opacity: 0.24
    }

    Behavior on color {
        ColorAnimation {
            duration: root.flow.normalDuration
            easing.type: root.flow.easeStandard
        }
    }
}

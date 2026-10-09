import QtQuick 2.15
import QtQuick.Window
import QtQuick.Effects
import InGe.CoreFlow 3.0 as Mobile
import "../flowcore" as FlowCore
import "../lib/IconCatalog.js" as IconCatalog

Item {
    id: root

    property string name: ""
    property url sourceOverride: ""
    property var flow: Mobile.InGeCoreFlow
    property string variant: flow.variant.buttonIcon
    property bool active: false
    property bool pressed: false
    property bool mirror: false
    property bool tintEnabled: true
    // Qt 6.9 solo multiplica sourceSize por el DPR en URLs que reconoce como
    // escalables (image:, *.svg, *.svgz, *.pdf). Los SVG data: de IconCatalog no
    // lo son: se rasterizan aqui al tamaño fisico exacto (nitidos con DPR 3+,
    // sin sobremuestreo con DPR 1.5-2). Las URLs reconocidas usan el DPR de Qt.
    readonly property bool sourceScaledByQt: {
        var s = resolvedSource.toString()
        return /^image:/i.test(s) || /\.(svgz?|pdf)(\?.*)?$/i.test(s)
    }
    property real rasterScale: sourceScaledByQt ? 1.0 : Math.max(1, Screen.devicePixelRatio)
    property color tintColor: flow.theme.textSecondary
    property color activeTintColor: flow.theme.accent
    property color disabledTintColor: flow.theme.textMuted
    property real inactiveOpacity: flow.opacityTokens.secondary
    property bool pulseOnActive: true
    property string flowState: enabled
                               ? (pressed ? flow.states.pressed
                                  : (active ? flow.states.selected
                                            : flow.states.idle))
                               : flow.states.disabled

    readonly property url resolvedSource:
        sourceOverride.toString().length > 0
        ? sourceOverride : IconCatalog.sourceForState(name, flowState)
    readonly property bool valid:
        resolvedSource.toString().length > 0
    readonly property bool motionAllowed: flow.motionAllowed
    readonly property int fastDuration: flow.fastDuration
    readonly property int normalDuration: flow.normalDuration
    readonly property real compactPressScale: flow.compactPressScale
    readonly property real activeScale: flow.activeIconScale
    property real pulseScale: 1.0

    implicitWidth: flow.metrics.iconMedium
    implicitHeight: flow.metrics.iconMedium
    opacity: enabled ? (active ? flow.opacityTokens.opaque : inactiveOpacity)
                     : flow.opacityTokens.disabled
    readonly property real stateScale:
        pressed ? compactPressScale : (active ? activeScale : 1.0)
    scale: stateScale * pulseScale

    transform: Scale {
        origin.x: root.width / 2
        origin.y: root.height / 2
        xScale: root.mirror ? -1 : 1
        yScale: 1
    }

    Behavior on opacity {
        NumberAnimation {
            duration: root.normalDuration
        }
    }

    Behavior on scale {
        NumberAnimation {
            duration: root.normalDuration
            easing.type: root.flow.easeOvershoot
        }
    }

    Image {
        id: iconImage
        anchors.fill: parent
        visible: root.valid && root.flowState !== root.flow.states.loading
        source: root.resolvedSource
        fillMode: Image.PreserveAspectFit
        smooth: true
        // Solo si se rasteriza por encima del tamaño fisico.
        mipmap: root.rasterScale > (root.sourceScaledByQt ? 1.0
                                                         : Math.max(1, Screen.devicePixelRatio)) + 0.01
        sourceSize.width: Math.max(1, Math.round(width * root.rasterScale))
        sourceSize.height: Math.max(1, Math.round(height * root.rasterScale))
        asynchronous: false
        cache: true
        layer.enabled: root.tintEnabled && status === Image.Ready
        layer.effect: MultiEffect {
            // Los SVG oficiales usan trazos oscuros. En Oscuro y Liquid Glass
            // elevamos su luminancia antes de aplicar el tinte semántico para
            // conservar contraste sin mantener variantes paralelas de iconos.
            brightness: root.flow.theme.isDark ? 0.55 : 0.0
            colorization: 1.0
            colorizationColor: {
                if (!root.enabled
                        || root.flowState === root.flow.states.disabled)
                    return root.disabledTintColor
                if (root.flowState === root.flow.states.error)
                    return root.flow.theme.error
                if (root.flowState === root.flow.states.warning)
                    return root.flow.theme.warning
                if (root.flowState === root.flow.states.success)
                    return root.flow.theme.success
                return root.active ? root.activeTintColor : root.tintColor
            }
        }
    }

    FlowCore.FlowBusyIndicator {
        anchors.fill: parent
        running: root.flowState === root.flow.states.loading
        visible: running
        flow: root.flow
        accent: root.activeTintColor
        track: Qt.rgba(root.activeTintColor.r,
                       root.activeTintColor.g,
                       root.activeTintColor.b, 0.22)
    }

    SequentialAnimation {
        id: activePulse
        running: false

        NumberAnimation {
            target: root
            property: "pulseScale"
            from: 1.0
            to: root.motionAllowed ? 1.08 : 1.0
            duration: root.fastDuration
            easing.type: Easing.OutCubic
        }

        NumberAnimation {
            target: root
            property: "pulseScale"
            from: root.motionAllowed ? 1.08 : 1.0
            to: 1.0
            duration: root.normalDuration
            easing.type: root.flow.easeOvershoot
        }
    }

    onActiveChanged: {
        if (active && pulseOnActive && motionAllowed)
            activePulse.restart()
    }

    function pulse() {
        if (motionAllowed)
            activePulse.restart()
    }

    function validateSource() {
        if (name.length > 0 && !valid)
            console.warn("[InGeCoreFlow] Icono semantico no registrado:", name)
    }

    Component.onCompleted: validateSource()
    onNameChanged: validateSource()
}

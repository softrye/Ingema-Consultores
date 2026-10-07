import QtQuick 2.15
import InGe.CoreFlow 3.0 as Mobile

Rectangle {
    id: root

    readonly property var flow: Mobile.InGeCoreFlow
    property string variant: flow.variant.surfaceStandard
    property int elevationLevel:
        variant === flow.variant.surfaceElevated ? flow.elevation.medium
        : (variant === flow.variant.surfaceOverlay ? flow.elevation.high
                                                   : flow.elevation.flat)

    radius: variant === flow.variant.surfaceTechnical
            ? flow.radius.md : flow.radius.lg
    color: {
        if (variant === flow.variant.surfaceGlass)
            return flow.theme.isGlass
                    ? flow.theme.glassRegular : flow.theme.surfaceElevated
        if (variant === flow.variant.surfaceOverlay)
            return flow.theme.surfaceOverlay
        if (variant === flow.variant.surfaceElevated)
            return flow.theme.surfaceElevated
        if (variant === flow.variant.surfaceTechnical)
            return flow.theme.surfaceSecondary
        return flow.theme.surface
    }
    border.width: flow.metrics.dividerWidth
    border.color: variant === flow.variant.surfaceGlass && flow.theme.isGlass
                  ? flow.theme.glassBorder : flow.theme.border
    antialiasing: true

    Rectangle {
        z: -1
        x: flow.spacing.xs
        y: flow.spacing.sm
        width: root.width
        height: root.height
        radius: root.radius
        visible: root.elevationLevel > flow.elevation.flat
        color: Qt.rgba(0.03, 0.08, 0.16,
                       flow.elevation.shadowOpacity(root.elevationLevel))
    }

    Rectangle {
        anchors.fill: parent
        radius: root.radius
        visible: root.variant === flow.variant.surfaceGlass
                 && flow.theme.isGlass
                 && flow.performance.reflectionsEnabled
        color: "transparent"
        gradient: Gradient {
            GradientStop {
                position: 0.0
                color: flow.theme.glassHighlight
            }
            GradientStop {
                position: 0.32
                color: "transparent"
            }
            GradientStop {
                position: 1.0
                color: flow.theme.glassTint
            }
        }
        opacity: flow.performance.reflectionIntensity
    }

    Behavior on color {
        ColorAnimation {
            duration: flow.normalDuration
            easing.type: flow.easeStandard
        }
    }
}

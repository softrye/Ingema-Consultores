import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15
import InGe.CoreFlow 3.0 as Mobile
import "../components" as Components

Button {
    id: root

    readonly property var flow: Mobile.InGeCoreFlow
    property string variant: flow.variant.buttonPrimary
    property string flowState: flow.states.idle
    property string iconName: ""
    property string hapticIntent: variant === flow.variant.buttonDanger
                                  ? "warning" : "light"
    property bool loading: flowState === flow.states.loading
    property bool success: flowState === flow.states.success
    property bool warning: flowState === flow.states.warning
    property bool hasError: flowState === flow.states.error
    property bool colorOverridesEnabled: false
    property color foregroundOverride: flow.theme.textPrimary
    property color fillOverride: flow.theme.surface
    property color borderOverride: flow.theme.border

    readonly property string effectiveState:
        flow.states.effective(enabled, loading, hasError, success,
                              down, activeFocus, hovered, checked)
    readonly property color foregroundColor: {
        if (colorOverridesEnabled)
            return foregroundOverride
        if (variant === flow.variant.buttonPrimary)
            return flow.theme.onActionPrimary
        if (variant === flow.variant.buttonDanger)
            return flow.colors.white
        if (variant === flow.variant.buttonGlass)
            return flow.theme.textPrimary
        return variant === flow.variant.buttonGhost
                ? flow.theme.accent : flow.theme.textPrimary
    }
    readonly property color fillColor: {
        if (colorOverridesEnabled)
            return fillOverride
        if (variant === flow.variant.buttonDanger)
            return flow.theme.error
        if (variant === flow.variant.buttonPrimary)
            return flow.theme.actionPrimary
        if (variant === flow.variant.buttonSecondary)
            return flow.theme.surfaceSecondary
        if (variant === flow.variant.buttonGlass)
            return flow.theme.isGlass
                    ? flow.theme.glassEmphasized : flow.theme.surfaceElevated
        return "transparent"
    }

    implicitHeight: flow.accessibility.touchSize(flow.metrics.buttonHeight)
    implicitWidth: Math.max(flow.accessibility.touchSize(96),
                            contentRow.implicitWidth + flow.spacing.xxl * 2)
    enabled: !loading
    hoverEnabled: true
    transformOrigin: Item.Center
    scale: down ? flow.motion.policy(flow.motion.pressStandard).scale : 1.0
    Accessible.name: text
    Accessible.role: Accessible.Button

    onClicked: flow.triggerHaptic(hapticIntent)

    Behavior on scale {
        NumberAnimation {
            duration: flow.fastDuration
            easing.type: root.down ? flow.easeOut : flow.easeOvershoot
        }
    }

    background: Rectangle {
        id: buttonBackground
        radius: root.variant === flow.variant.buttonIcon
                ? flow.radius.pill : flow.radius.lg
        color: root.fillColor
        border.width: flow.metrics.dividerWidth
        border.color: root.colorOverridesEnabled
                      ? root.borderOverride
                      : (root.variant === flow.variant.buttonGlass
                         && flow.theme.isGlass
                      ? flow.theme.glassBorder
                      : (root.variant === flow.variant.buttonGhost
                         ? "transparent" : flow.theme.border))
        opacity: root.enabled ? flow.opacityTokens.opaque
                              : flow.opacityTokens.disabled
        clip: true

        FlowRipple {
            id: ripple
            flow: root.flow
            rippleColor: root.variant === flow.variant.buttonPrimary
                         || root.variant === flow.variant.buttonDanger
                         ? "#55FFFFFF" : flow.rippleLight
            cornerRadius: buttonBackground.radius
            enabled: root.enabled && flow.motionAllowed
        }

        Rectangle {
            anchors.fill: parent
            radius: parent.radius
            visible: root.variant === flow.variant.buttonGlass
                     && flow.theme.isGlass
                     && flow.performance.reflectionsEnabled
            color: "transparent"
            gradient: Gradient {
                GradientStop {
                    position: 0.0
                    color: flow.theme.glassHighlight
                }
                GradientStop {
                    position: 0.45
                    color: "transparent"
                }
                GradientStop {
                    position: 1.0
                    color: flow.theme.glassTint
                }
            }
            opacity: flow.performance.reflectionIntensity
        }
    }

    contentItem: RowLayout {
        id: contentRow
        spacing: flow.spacing.sm

        FlowBusyIndicator {
            Layout.preferredWidth: flow.metrics.iconMedium
            Layout.preferredHeight: flow.metrics.iconMedium
            visible: root.loading
            running: root.loading
            flow: root.flow
            accent: root.foregroundColor
            track: Qt.rgba(root.foregroundColor.r,
                           root.foregroundColor.g,
                           root.foregroundColor.b, 0.25)
        }

        Components.FlowIcon {
            Layout.preferredWidth: flow.metrics.iconMedium
            Layout.preferredHeight: flow.metrics.iconMedium
            visible: !root.loading && root.iconName.length > 0
            name: root.success ? Mobile.FlowIcons.success
                               : (root.warning ? Mobile.FlowIcons.warning
                                  : (root.hasError ? Mobile.FlowIcons.error
                                                   : root.iconName))
            flow: root.flow
            flowState: root.effectiveState
            tintEnabled: true
            tintColor: root.foregroundColor
            activeTintColor: root.foregroundColor
            disabledTintColor: root.foregroundColor
        }

        FlowText {
            Layout.fillWidth: true
            text: root.text
            role: "label"
            color: root.foregroundColor
            font.weight: flow.typography.semiboldWeight
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
        }
    }

    onDownChanged: {
        if (down)
            ripple.trigger(width / 2, height / 2)
    }
}

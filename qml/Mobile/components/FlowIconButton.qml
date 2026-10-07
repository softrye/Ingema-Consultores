import QtQuick 2.15
import QtQuick.Layouts 1.15
import InGe.CoreFlow 3.0 as Mobile
import "../flowcore" as FlowCore

Rectangle {
    id: root

    property string iconName: ""
    property url sourceOverride: ""
    property string label: ""
    property var flow: Mobile.InGeCoreFlow
    property string variant: flow.variant.buttonIcon
    property bool selected: false
    property bool showLabel: label.length > 0
    property bool iconTintEnabled: true
    property color iconColor: flow.theme.textSecondary
    property color selectedIconColor: flow.theme.accent
    property color disabledIconColor: flow.theme.textMuted
    property color idleColor: "transparent"
    property color pressedColor: flow.theme.surfaceSecondary
    property color selectedColor: flow.theme.surfaceSecondary
    property color labelColor: flow.theme.textSecondary
    property color selectedLabelColor: flow.theme.accent
    property color rippleColor: flow.rippleLight
    property int iconSize: flow.metrics.iconMedium
    property int cornerRadius: flow.radius.md
    property bool pulseOnSelected: true
    property string hapticIntent: "selection"
    property string flowState: enabled
                               ? (tap.pressed ? flow.states.pressed
                                  : (selected ? flow.states.selected
                                              : flow.states.idle))
                               : flow.states.disabled

    signal clicked()

    implicitWidth: showLabel ? 72
                             : flow.accessibility.touchSize(
                                   flow.metrics.compactTouchTarget)
    implicitHeight: showLabel ? 58
                              : flow.accessibility.touchSize(
                                    flow.metrics.compactTouchTarget)
    radius: cornerRadius
    clip: true
    readonly property int fastDuration: flow.fastDuration
    readonly property real pressScale: flow.compactPressScale

    color: tap.pressed
           ? pressedColor
           : (selected ? selectedColor
                       : (variant === flow.variant.buttonGlass
                          ? flow.theme.glassSurface : idleColor))
    border.width: variant === flow.variant.buttonGlass ? 1 : 0
    border.color: flow.theme.glassBorder
    scale: tap.pressed ? pressScale : 1.0
    opacity: enabled ? 1.0 : flow.opacityTokens.disabled
    Accessible.name: label.length > 0 ? label : iconName
    Accessible.role: Accessible.Button

    Behavior on color {
        ColorAnimation {
            duration: root.fastDuration
        }
    }

    Behavior on scale {
        NumberAnimation {
            duration: root.fastDuration
            easing.type: root.flow.easeOut
        }
    }

    FlowCore.FlowRipple {
        id: ripple
        anchors.fill: parent
        flow: root.flow
        rippleColor: root.rippleColor
        enabled: root.flow.motionAllowed && root.enabled
    }

    ColumnLayout {
        anchors.centerIn: parent
        spacing: root.showLabel ? 3 : 0

        FlowIcon {
            id: iconView
            Layout.preferredWidth: root.iconSize
            Layout.preferredHeight: root.iconSize
            Layout.alignment: Qt.AlignHCenter
            name: root.iconName
            sourceOverride: root.sourceOverride
            flow: root.flow
            active: root.selected
            pressed: tap.pressed
            flowState: root.flowState
            enabled: root.enabled
            pulseOnActive: root.pulseOnSelected
            tintEnabled: root.iconTintEnabled
            tintColor: root.iconColor
            activeTintColor: root.selectedIconColor
            disabledTintColor: root.disabledIconColor
        }

        Text {
            visible: root.showLabel
            Layout.alignment: Qt.AlignHCenter
            text: root.label
            color: root.selected ? root.selectedLabelColor : root.labelColor
            font.family: flow.typography.family
            font.pixelSize: flow.accessibility.scaledTextSize(
                                flow.typography.captionSize)
            font.bold: root.selected
            maximumLineCount: 1
            elide: Text.ElideRight

            Behavior on color {
                ColorAnimation {
                    duration: root.fastDuration
                }
            }
        }
    }

    MouseArea {
        id: tap
        anchors.fill: parent
        enabled: root.enabled
        hoverEnabled: true

        onPressed: function(mouse) {
            ripple.trigger(mouse.x, mouse.y)
        }

        onClicked: {
            root.flow.triggerHaptic(root.hapticIntent)
            root.clicked()
        }
    }

    function pulse() {
        iconView.pulse()
    }
}

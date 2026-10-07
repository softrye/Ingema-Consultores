import QtQuick 2.15
import QtQuick.Layouts 1.15
import InGe.CoreFlow 3.0 as Mobile
import "../components" as Components

Rectangle {
    id: root

    readonly property var flow: Mobile.InGeCoreFlow
    property string variant: flow.variant.tabPrimaryNavigation
    property string text: ""
    property string iconName: ""
    property bool selected: false
    property bool closable: false

    signal clicked()
    signal closeRequested()

    implicitHeight: flow.accessibility.touchSize(
                        variant === flow.variant.tabCompact
                        ? flow.metrics.compactTouchTarget
                        : flow.metrics.tabHeight)
    implicitWidth: tabRow.implicitWidth + flow.spacing.xxl
    radius: variant === flow.variant.tabWorkspace
            ? flow.radius.sm : flow.radius.pill
    color: selected
           ? (variant === flow.variant.tabGlass
              ? flow.theme.glassSurface : flow.theme.surfaceSecondary)
           : "transparent"
    border.width: selected && variant === flow.variant.tabGlass ? 1 : 0
    border.color: flow.theme.glassBorder
    opacity: enabled ? 1.0 : flow.opacityTokens.disabled

    RowLayout {
        id: tabRow
        anchors.centerIn: parent
        spacing: flow.spacing.xs

        Components.FlowIcon {
            Layout.preferredWidth: flow.metrics.iconSmall
            Layout.preferredHeight: flow.metrics.iconSmall
            visible: root.iconName.length > 0
            name: root.iconName
            flow: root.flow
            active: root.selected
            flowState: root.selected ? flow.states.selected : flow.states.idle
            tintColor: flow.theme.textSecondary
            activeTintColor: flow.theme.accent
        }

        FlowText {
            text: root.text
            role: "label"
            color: root.selected ? flow.theme.accent : flow.theme.textSecondary
            font.weight: root.selected ? flow.typography.semiboldWeight
                                       : flow.typography.regularWeight
        }

        Components.FlowIcon {
            Layout.preferredWidth: flow.metrics.iconSmall
            Layout.preferredHeight: flow.metrics.iconSmall
            visible: root.closable
            name: Mobile.FlowIcons.close
            flow: root.flow
            tintColor: flow.theme.textMuted
            MouseArea {
                anchors.fill: parent
                onClicked: function(mouse) {
                    mouse.accepted = true
                    root.closeRequested()
                }
            }
        }
    }

    MouseArea {
        anchors.fill: parent
        enabled: root.enabled
        onClicked: {
            flow.triggerHaptic("selection")
            root.clicked()
        }
    }

    Rectangle {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        width: root.selected ? Math.max(24, root.width * 0.42) : 0
        height: 3
        radius: 2
        color: flow.theme.accent
        visible: root.variant === flow.variant.tabPrimaryNavigation

        Behavior on width {
            NumberAnimation {
                duration: flow.motion.policy(flow.motion.tabSelect).duration
                easing.type: flow.easeOut
            }
        }
    }
}

import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15
import InGe.CoreFlow 3.0 as Mobile
import "../components" as Components

Item {
    id: root

    readonly property var flow: Mobile.InGeCoreFlow
    property string variant: flow.variant.fieldStandard
    property string label: ""
    property string placeholderText: ""
    property string helperText: ""
    property string errorText: ""
    property bool success: false
    property bool readOnly: variant === flow.variant.fieldReadOnly
    property alias text: input.text
    property alias validator: input.validator
    property alias inputMethodHints: input.inputMethodHints
    property alias echoMode: input.echoMode
    readonly property bool acceptableInput: input.acceptableInput
    readonly property string flowState:
        flow.states.effective(enabled, false, errorText.length > 0,
                              success, false, input.activeFocus,
                              input.hovered, false)

    implicitWidth: 260
    implicitHeight: label.length > 0
                    ? flow.metrics.fieldHeight + flow.spacing.xl
                      + (supportText.visible ? flow.spacing.xl : 0)
                    : flow.metrics.fieldHeight

    FlowText {
        id: fieldLabel
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        visible: root.label.length > 0
        text: root.label
        role: "label"
        color: root.flowState === flow.states.error
               ? flow.theme.error : flow.theme.textSecondary
    }

    Rectangle {
        id: fieldFrame
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: fieldLabel.visible ? fieldLabel.bottom : parent.top
        anchors.topMargin: fieldLabel.visible ? flow.spacing.xs : 0
        height: flow.accessibility.touchSize(flow.metrics.fieldHeight)
        radius: flow.radius.md
        color: root.variant === flow.variant.fieldGlass
               ? flow.theme.glassSurface
               : (root.readOnly ? flow.theme.surfaceSecondary
                                : flow.theme.surface)
        border.width: input.activeFocus
                      && flow.accessibility.focusVisible ? 2 : 1
        border.color: root.flowState === flow.states.error
                      ? flow.theme.error
                      : (root.flowState === flow.states.success
                         ? flow.theme.success
                         : (input.activeFocus ? flow.theme.accent
                                              : flow.theme.border))
        opacity: root.enabled ? 1.0 : flow.opacityTokens.disabled

        Components.FlowIcon {
            id: leadingIcon
            anchors.left: parent.left
            anchors.leftMargin: flow.spacing.md
            anchors.verticalCenter: parent.verticalCenter
            width: flow.metrics.iconMedium
            height: flow.metrics.iconMedium
            visible: root.variant === flow.variant.fieldSearch
            name: Mobile.FlowIcons.search
            flow: root.flow
            flowState: root.flowState
            tintColor: flow.theme.textMuted
            activeTintColor: flow.theme.accent
        }

        TextField {
            id: input
            anchors.fill: parent
            anchors.leftMargin: leadingIcon.visible
                                ? flow.metrics.iconMedium + flow.spacing.xl
                                : flow.spacing.md
            anchors.rightMargin: flow.spacing.md
            background: null
            color: flow.theme.textPrimary
            placeholderText: root.placeholderText
            placeholderTextColor: flow.theme.textMuted
            font.family: flow.typography.family
            font.pixelSize: flow.accessibility.scaledTextSize(
                                flow.typography.bodySize)
            readOnly: root.readOnly
            selectByMouse: true
            verticalAlignment: TextInput.AlignVCenter
            inputMethodHints: root.variant === flow.variant.fieldNumeric
                              ? Qt.ImhFormattedNumbersOnly : Qt.ImhNone
            Accessible.name: root.label.length > 0
                             ? root.label : root.placeholderText
        }
    }

    FlowText {
        id: supportText
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: fieldFrame.bottom
        anchors.topMargin: flow.spacing.xs
        visible: root.errorText.length > 0 || root.helperText.length > 0
        text: root.errorText.length > 0 ? root.errorText : root.helperText
        role: "caption"
        color: root.errorText.length > 0
               ? flow.theme.error : flow.theme.textMuted
    }
}

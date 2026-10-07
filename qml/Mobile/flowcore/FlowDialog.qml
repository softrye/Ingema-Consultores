import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15
import InGe.CoreFlow 3.0 as Mobile

Popup {
    id: root

    readonly property var flow: Mobile.InGeCoreFlow
    property string variant: flow.variant.dialogStandard
    property string title: ""
    property string message: ""
    property string acceptText: qsTr("Aceptar")
    property string rejectText: qsTr("Cancelar")
    property bool showReject: true
    default property alias flowContent: dialogBody.data

    signal accepted()
    signal rejected()

    parent: Overlay.overlay
    anchors.centerIn: parent
    width: Math.min(parent ? parent.width - flow.spacing.xxxl : 420, 420)
    padding: flow.spacing.xl
    modal: true
    dim: true
    focus: true
    closePolicy: Popup.CloseOnEscape

    Overlay.modal: Rectangle {
        color: flow.theme.scrim
    }

    background: FlowSurface {
        variant: root.variant === flow.variant.dialogGlass
                 ? flow.variant.surfaceGlass : flow.variant.surfaceOverlay
        border.color: root.variant === flow.variant.dialogCritical
                      ? flow.theme.error
                      : (root.variant === flow.variant.dialogGlass
                         ? flow.theme.glassBorder : flow.theme.border)
        radius: flow.radius.xl
        elevationLevel: flow.elevation.high
    }

    contentItem: ColumnLayout {
        spacing: flow.spacing.lg

        FlowText {
            Layout.fillWidth: true
            text: root.title
            role: "title"
            color: root.variant === flow.variant.dialogCritical
                   ? flow.theme.error : flow.theme.textPrimary
        }

        FlowText {
            Layout.fillWidth: true
            visible: root.message.length > 0
            text: root.message
            role: "body"
        }

        Item {
            id: dialogBody
            Layout.fillWidth: true
            implicitHeight: childrenRect.height
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: flow.spacing.md

            Item { Layout.fillWidth: true }

            FlowButton {
                visible: root.showReject
                text: root.rejectText
                variant: flow.variant.buttonGhost
                onClicked: {
                    root.rejected()
                    root.close()
                }
            }

            FlowButton {
                text: root.acceptText
                variant: root.variant === flow.variant.dialogCritical
                         ? flow.variant.buttonDanger
                         : flow.variant.buttonPrimary
                onClicked: {
                    root.accepted()
                    root.close()
                }
            }
        }
    }

    enter: Transition {
        ParallelAnimation {
            NumberAnimation {
                property: "opacity"
                from: 0.0
                to: 1.0
                duration: flow.motion.policy(
                              flow.motion.dialogPresent).duration
            }
            NumberAnimation {
                property: "scale"
                from: flow.motion.policy(flow.motion.dialogPresent).scale
                to: 1.0
                duration: flow.motion.policy(
                              flow.motion.dialogPresent).duration
                easing.type: flow.motion.policy(
                                 flow.motion.dialogPresent).easing
            }
        }
    }

    exit: Transition {
        ParallelAnimation {
            NumberAnimation {
                property: "opacity"
                to: 0.0
                duration: flow.motion.policy(
                              flow.motion.dialogDismiss).duration
            }
            NumberAnimation {
                property: "scale"
                to: flow.motion.policy(flow.motion.dialogDismiss).scale
                duration: flow.motion.policy(
                              flow.motion.dialogDismiss).duration
                easing.type: flow.motion.policy(
                                 flow.motion.dialogDismiss).easing
            }
        }
    }
}

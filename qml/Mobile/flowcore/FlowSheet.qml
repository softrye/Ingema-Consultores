import QtQuick 2.15
import QtQuick.Controls 2.15
import InGe.CoreFlow 3.0 as Mobile

Popup {
    id: root

    readonly property var flow: Mobile.InGeCoreFlow
    property string variant: flow.variant.sheetStandard
    property string title: ""
    property real maximumHeightRatio: 0.86
    default property alias flowContent: sheetBody.data

    signal presented()
    signal dismissed()

    parent: Overlay.overlay
    x: 0
    y: parent ? parent.height - height : 0
    width: parent ? parent.width : 360
    height: Math.min(parent ? parent.height * maximumHeightRatio : 640,
                     sheetColumn.implicitHeight + flow.spacing.xl)
    padding: 0
    modal: true
    dim: true
    focus: true
    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside

    Overlay.modal: Rectangle {
        color: flow.theme.scrim
        Behavior on opacity {
            NumberAnimation {
                duration: flow.fastDuration
            }
        }
    }

    background: FlowSurface {
        variant: root.variant === flow.variant.sheetGlass
                 ? flow.variant.surfaceGlass : flow.variant.surfaceOverlay
        radius: flow.radius.xxl
    }

    contentItem: Column {
        id: sheetColumn
        spacing: flow.spacing.md

        Rectangle {
            anchors.horizontalCenter: parent.horizontalCenter
            width: 44
            height: 5
            radius: 3
            color: flow.theme.textMuted
            opacity: flow.opacityTokens.muted
        }

        FlowText {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.leftMargin: flow.spacing.xl
            anchors.rightMargin: flow.spacing.xl
            visible: root.title.length > 0
            text: root.title
            role: "title"
        }

        Item {
            id: sheetBody
            width: parent.width
            implicitHeight: childrenRect.height
        }
    }

    enter: Transition {
        ParallelAnimation {
            NumberAnimation {
                property: "y"
                from: root.parent ? root.parent.height : root.height
                to: root.parent ? root.parent.height - root.height : 0
                duration: flow.motion.policy(flow.motion.sheetPresent).duration
                easing.type: flow.motion.policy(
                                 flow.motion.sheetPresent).easing
            }
            NumberAnimation {
                property: "opacity"
                from: 0.0
                to: 1.0
                duration: flow.fastDuration
            }
        }
    }

    exit: Transition {
        ParallelAnimation {
            NumberAnimation {
                property: "y"
                to: root.parent ? root.parent.height : root.height
                duration: flow.motion.policy(flow.motion.sheetDismiss).duration
                easing.type: flow.motion.policy(
                                 flow.motion.sheetDismiss).easing
            }
            NumberAnimation {
                property: "opacity"
                to: 0.0
                duration: flow.fastDuration
            }
        }
    }

    onOpened: {
        flow.triggerHaptic("light")
        presented()
    }
    onClosed: dismissed()

    function present() {
        open()
    }

    function dismiss() {
        close()
    }
}

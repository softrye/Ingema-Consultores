import QtQuick 2.15
import InGe.CoreFlow 3.0 as Mobile

FlowSurface {
    id: root

    property string cardVariant: flow.variant.cardStandard
    property string flowState: flow.states.idle
    property bool interactive:
        cardVariant === flow.variant.cardInteractive
    property bool expanded: flowState === flow.states.expanded
    default property alias contentData: contentHost.data

    signal clicked()
    signal expansionRequested(bool expanded)

    variant: cardVariant === flow.variant.cardGlass
             ? flow.variant.surfaceGlass
             : (cardVariant === flow.variant.cardTechnical
                ? flow.variant.surfaceTechnical
                : flow.variant.surfaceStandard)
    implicitHeight: cardVariant === flow.variant.cardCompact ? 72 : 112
    implicitWidth: 240
    scale: cardTap.pressed && interactive ? flow.cardPressScale : 1.0
    transformOrigin: Item.Center

    Item {
        id: contentHost
        anchors.fill: parent
        anchors.margins: root.cardVariant === flow.variant.cardCompact
                         ? flow.spacing.md : flow.spacing.lg
    }

    MouseArea {
        id: cardTap
        anchors.fill: parent
        enabled: root.interactive
        hoverEnabled: true
        onClicked: {
            flow.triggerHaptic("selection")
            root.clicked()
        }
        onDoubleClicked: root.expansionRequested(!root.expanded)
    }

    Behavior on scale {
        NumberAnimation {
            duration: flow.fastDuration
            easing.type: cardTap.pressed ? flow.easeOut : flow.easeOvershoot
        }
    }
}

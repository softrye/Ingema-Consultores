import QtQuick 2.15
import QtQuick.Layouts 1.15
import InGe.CoreFlow 3.0 as Mobile
import "../components" as Components

FlowSurface {
    id: root

    property string title: ""
    property string subtitle: ""
    property string leadingIcon: ""
    property string toolbarVariant: flow.variant.surfaceStandard
    property alias leadingActions: leadingRow.data
    property alias trailingActions: trailingRow.data

    signal leadingClicked()

    variant: toolbarVariant
    radius: flow.radius.none
    implicitHeight: flow.metrics.toolbarHeight

    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: flow.spacing.lg
        anchors.rightMargin: flow.spacing.lg
        spacing: flow.spacing.md

        Row {
            id: leadingRow
            spacing: flow.spacing.xs

            Components.FlowIconButton {
                visible: root.leadingIcon.length > 0
                iconName: root.leadingIcon
                flow: root.flow
                variant: root.toolbarVariant === flow.variant.surfaceGlass
                         ? flow.variant.buttonGlass : flow.variant.buttonGhost
                onClicked: root.leadingClicked()
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 0

            FlowText {
                Layout.fillWidth: true
                text: root.title
                role: "title"
                elide: Text.ElideRight
                maximumLineCount: 1
            }

            FlowText {
                Layout.fillWidth: true
                visible: root.subtitle.length > 0
                text: root.subtitle
                role: "caption"
                muted: true
                elide: Text.ElideRight
                maximumLineCount: 1
            }
        }

        Row {
            id: trailingRow
            spacing: flow.spacing.xs
        }
    }
}

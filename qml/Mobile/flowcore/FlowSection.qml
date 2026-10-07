import QtQuick 2.15
import QtQuick.Layouts 1.15
import InGe.CoreFlow 3.0 as Mobile
import "../components" as Components

FlowSurface {
    id: root

    property string title: ""
    property string subtitle: ""
    property string leadingIcon: ""
    property string sectionVariant: flow.variant.cardStandard
    property alias actions: actionsRow.data
    default property alias contentData: sectionBody.data

    variant: sectionVariant === flow.variant.cardGlass
             ? flow.variant.surfaceGlass
             : (sectionVariant === flow.variant.cardTechnical
                ? flow.variant.surfaceTechnical
                : flow.variant.surfaceStandard)
    implicitWidth: 320
    implicitHeight: sectionColumn.implicitHeight + flow.spacing.xxl

    ColumnLayout {
        id: sectionColumn
        anchors.fill: parent
        anchors.margins: flow.spacing.lg
        spacing: flow.spacing.md

        RowLayout {
            Layout.fillWidth: true
            spacing: flow.spacing.md

            Components.FlowIcon {
                Layout.preferredWidth: flow.metrics.iconMedium
                Layout.preferredHeight: flow.metrics.iconMedium
                visible: root.leadingIcon.length > 0
                name: root.leadingIcon
                flow: root.flow
                tintColor: flow.theme.accent
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: flow.spacing.xxs

                FlowText {
                    Layout.fillWidth: true
                    text: root.title
                    role: "subtitle"
                    font.weight: flow.typography.semiboldWeight
                }

                FlowText {
                    Layout.fillWidth: true
                    visible: root.subtitle.length > 0
                    text: root.subtitle
                    role: "caption"
                    muted: true
                }
            }

            Row {
                id: actionsRow
                spacing: flow.spacing.xs
            }
        }

        Item {
            id: sectionBody
            Layout.fillWidth: true
            implicitHeight: childrenRect.height
        }
    }
}

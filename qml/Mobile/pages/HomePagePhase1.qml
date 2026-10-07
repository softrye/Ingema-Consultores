import QtQuick 2.15
import QtQuick.Layouts 1.15
import QtQuick.Effects
import InGe.CoreFlow 3.0 as Mobile
import "../flowcore" as FlowCore
import "../components" as Components

Item {
    id: root

    property var flow: Mobile.InGeCoreFlow
    property int themeMode: 0
    property bool darkMode: themeMode !== 0
    property string calCode: ""
    property string calProject: ""
    property real navigationInset: flow.metrics.navigationHeight + flow.spacing.xl

    readonly property bool liquidGlass: themeMode === flow.theme.liquidGlass

    signal navigateRequested(int page)
    signal messageRequested(string message)

    Item {
        id: homeBackdrop
        anchors.fill: parent

        Rectangle {
            anchors.fill: parent
            color: root.liquidGlass ? root.flow.colors.navy900
                                    : root.flow.theme.background
        }

        Image {
            anchors.fill: parent
            visible: root.liquidGlass
            source: "qrc:/ui/v2/backgrounds/bg_topographic_lines.svg"
            fillMode: Image.PreserveAspectCrop
            opacity: 0.74
            smooth: true
            layer.enabled: true
            layer.effect: MultiEffect {
                colorization: 0.72
                colorizationColor: root.flow.colors.cyan500
                brightness: 0.16
            }
        }

        Image {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            height: parent.height * 0.38
            visible: root.liquidGlass
            source: "qrc:/ui/v2/backgrounds/bg_mountain_soft.svg"
            fillMode: Image.PreserveAspectCrop
            opacity: 0.20
            smooth: true
        }
    }

    Flickable {
        id: homeScroll
        anchors.fill: parent
        clip: true
        contentWidth: width
        contentHeight: contentColumn.height + root.navigationInset + root.flow.spacing.lg
        interactive: contentHeight > height
        boundsBehavior: root.flow.motionAllowed
                        ? Flickable.DragAndOvershootBounds
                        : Flickable.StopAtBounds
        flickDeceleration: root.flow.flickDeceleration
        maximumFlickVelocity: root.flow.maximumFlickVelocity

        Column {
            id: contentColumn
            x: root.flow.spacing.page
            y: root.flow.spacing.compact
            width: parent.width - root.flow.spacing.page * 2
            spacing: root.flow.spacing.compact




            SectionTitle {
                width: parent.width
                text: "Módulos"
            }

            FlowCore.FlowText {
                width: parent.width
                text: "Herramientas geotécnicas para el trabajo de campo."
                role: "caption"
                color: root.flow.theme.textSecondary
                wrapMode: Text.WordWrap
                maximumLineCount: 2
            }

            Row {
                id: modulesRow
                width: parent.width
                height: 64
                spacing: root.flow.spacing.sm

                ModuleChip {
                    width: (parent.width - root.flow.spacing.sm) / 2
                    title: "Calicatas"
                    status: "Disponible"
                    statusColor: root.flow.theme.success
                    iconName: "home.calicata"
                    onTriggered: root.navigateRequested(1)
                }

                ModuleChip {
                    width: (parent.width - root.flow.spacing.sm) / 2
                    title: "Taludes"
                    status: "Próximamente"
                    statusColor: root.flow.theme.warning
                    iconName: "module.taludes"
                    enabled: false
                }
            }
        }
    }



    component SectionTitle: FlowCore.FlowText {
        role: "label"
        color: root.flow.theme.textPrimary
        font.weight: root.flow.typography.semiboldWeight
        verticalAlignment: Text.AlignVCenter
    }


    component ModuleChip: FlowCore.FlowGlassSurface {
        id: moduleChip
        property string title: ""
        property string status: ""
        property string iconName: ""
        property color statusColor: root.flow.theme.success
        signal triggered()

        height: 64
        radius: root.flow.radius.md
        flow: root.flow
        darkMode: root.darkMode
        strength: 0.42
        blurSource: homeBackdrop
        blurAmount: 0.62
        color: root.liquidGlass
               ? Qt.rgba(root.flow.theme.glassSurface.r,
                         root.flow.theme.glassSurface.g,
                         root.flow.theme.glassSurface.b, 0.30)
               : (moduleTap.pressed ? root.flow.theme.pressed
                                    : root.flow.theme.surface)
        border.color: moduleTap.pressed
                      ? moduleChip.statusColor : root.flow.theme.border
        scale: moduleTap.pressed ? root.flow.compactPressScale : 1
        Accessible.name: moduleChip.title + ", " + moduleChip.status
        Accessible.role: Accessible.Button

        Components.FlowIcon {
            anchors.left: parent.left
            anchors.leftMargin: root.flow.spacing.md
            anchors.verticalCenter: parent.verticalCenter
            width: root.flow.metrics.iconMedium
            height: root.flow.metrics.iconMedium
            name: moduleChip.iconName
            flow: root.flow
            pressed: moduleTap.pressed
            tintEnabled: true
            tintColor: moduleChip.statusColor
            activeTintColor: moduleChip.statusColor
            inactiveOpacity: 1
        }
        Column {
            anchors.left: parent.left
            anchors.leftMargin: 46
            anchors.right: parent.right
            anchors.rightMargin: root.flow.spacing.sm
            anchors.verticalCenter: parent.verticalCenter
            spacing: 0
            FlowCore.FlowText {
                width: parent.width
                text: moduleChip.title
                role: "caption"
                color: root.flow.theme.textPrimary
                font.weight: root.flow.typography.semiboldWeight
                elide: Text.ElideRight
            }
            FlowCore.FlowText {
                width: parent.width
                text: moduleChip.status
                role: "caption"
                color: moduleChip.statusColor
                font.pixelSize: root.flow.accessibility.scaledTextSize(10)
                font.weight: root.flow.typography.semiboldWeight
                elide: Text.ElideRight
            }
        }

        FlowCore.FlowDeepPressArea {
            id: moduleTap
            anchors.fill: parent
            flow: root.flow
            contextName: "card"
            importance: 1
            deepPressEnabled: false
            onTapped: {
                root.flow.triggerHaptic("selection")
                moduleChip.triggered()
            }
        }
    }
}

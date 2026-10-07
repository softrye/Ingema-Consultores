import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15
import InGe.CoreFlow 3.0 as Mobile
import "../lib/PropACalicataIconMap.js" as CalIcons
import "../flowcore" as FlowCore

Item {
    id: root

    property bool flowMotionEnabled: true
    property bool flowReduceMotion: false
    property int flowMotionLevel: 2

    readonly property var pageFlow: Mobile.InGeCoreFlow


    width: parent ? parent.width : 420
    implicitHeight: mainCol.implicitHeight

    // Fase 5.4: UI general refinada, NO editable tecnico final.
    property bool darkMode: false
    property bool online: true
    property bool gpsAvailable: false
    property bool hasLogoMtc: false
    property bool hasLogoProyecto: false
    property url logoMtcSource: ""
    property url logoProyectoSource: ""
    property string codigoFicha: "CAL-000"
    property string proyecto: "Proyecto_Local"
    property string progresiva: "Km / Progresiva"
    property string fecha: "00/00/0000"
    property string utmX: "--"
    property string utmY: "--"
    property string zona: "--"
    property string altitud: "--"

    signal requestPickMtc()
    signal requestPickProject()
    signal requestRefreshGps()
    signal requestAddEstrato()
    signal requestTakePhoto()
    signal requestSave()
    signal requestExportExcel()
    signal requestExportPdf()

    readonly property color pageBg: darkMode ? "#061525" : "#F4F8FB"
    readonly property color card: darkMode ? "#0D263F" : "#FFFFFF"
    readonly property color cardSoft: darkMode ? "#132F4B" : "#F7FBFD"
    readonly property color cardBlue: darkMode ? "#07335D" : "#E8F4FF"
    readonly property color textMain: darkMode ? "#F5FAFF" : "#0E2235"
    readonly property color textSub: darkMode ? "#AFC4D8" : "#607284"
    readonly property color border: darkMode ? "#315A80" : "#D7E7F0"
    readonly property color navy: "#005282"
    readonly property color blue: "#0077D9"
    readonly property color teal: "#0087AE"
    readonly property color orange: "#FDAC11"
    readonly property color green: "#36C16B"

    function i(name) { return CalIcons.icon(name, root.darkMode) }
    function a(name) { return CalIcons.action(name, root.darkMode) }

    Column {
        id: mainCol
        width: root.width
        spacing: 12

        Rectangle {
            width: parent.width
            radius: 26
            color: root.darkMode ? "#071E35" : "#FFFFFF"
            border.width: 1
            border.color: root.border
            implicitHeight: heroCol.implicitHeight + 26
            clip: true

            Rectangle {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                height: 104
                gradient: Gradient {
                    GradientStop { position: 0.0; color: root.darkMode ? "#005282" : "#0077D9" }
                    GradientStop { position: 1.0; color: root.darkMode ? "#00365C" : "#005282" }
                }
            }

            ColumnLayout {
                id: heroCol
                anchors.fill: parent
                anchors.margins: 14
                spacing: 12

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 10

                    IconBox {
                        Layout.preferredWidth: 58
                        Layout.preferredHeight: 58
                        iconSource: root.i("editable")
                        iconSize: 42
                        boxColor: root.darkMode ? "#0E2B48" : "#FFFFFF"
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 1
                        Text { Layout.fillWidth: true; text: "Fichas / Calicata"; color: "white"; font.pixelSize: 22; font.bold: true; elide: Text.ElideRight }
                        Text { Layout.fillWidth: true; text: "UI general integrada · editable técnico pendiente"; color: "#D9F0FF"; font.pixelSize: 12; elide: Text.ElideRight }
                    }

                    Image { Layout.preferredWidth: 86; Layout.preferredHeight: 42; source: CalIcons.logoIngePlus(root.darkMode); fillMode: Image.PreserveAspectFit; smooth: true }
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8
                    StatusChip { Layout.fillWidth: true; label: root.online ? "En línea" : "Sin conexión"; iconSource: CalIcons.status(root.online ? "online" : "offline", root.darkMode) }
                    StatusChip { Layout.fillWidth: true; label: root.gpsAvailable ? "GPS listo" : "GPS pendiente"; iconSource: CalIcons.gps(root.gpsAvailable, root.darkMode) }
                }
            }
        }

        Rectangle {
            width: parent.width
            radius: 22
            color: root.card
            border.width: 1
            border.color: root.border
            implicitHeight: summaryCol.implicitHeight + 24

            ColumnLayout {
                id: summaryCol
                anchors.fill: parent
                anchors.margins: 12
                spacing: 10

                RowLayout { Layout.fillWidth: true; spacing: 8
                    Image { Layout.preferredWidth: 28; Layout.preferredHeight: 28; source: root.i("project"); fillMode: Image.PreserveAspectFit; smooth: true }
                    ColumnLayout { Layout.fillWidth: true; spacing: 0
                        Text { Layout.fillWidth: true; text: "Vista general de ficha"; color: root.textMain; font.pixelSize: 17; font.bold: true }
                        Text { Layout.fillWidth: true; text: "Esta fase ordena la UI; la edición técnica final queda para después."; color: root.textSub; font.pixelSize: 12; elide: Text.ElideRight }
                    }
                }

                GridLayout {
                    Layout.fillWidth: true
                    columns: 2
                    columnSpacing: 8
                    rowSpacing: 8
                    InfoMiniCard { Layout.fillWidth: true; title: "Código"; value: root.codigoFicha && root.codigoFicha.length ? root.codigoFicha : "CAL-000"; iconSource: root.i("code") }
                    InfoMiniCard { Layout.fillWidth: true; title: "Fecha"; value: root.fecha && root.fecha.length ? root.fecha : "00/00/0000"; iconSource: root.i("date") }
                    InfoMiniCard { Layout.fillWidth: true; title: "Proyecto"; value: root.proyecto && root.proyecto.length ? root.proyecto : "Proyecto_Local"; iconSource: root.i("project") }
                    InfoMiniCard { Layout.fillWidth: true; title: "Progresiva"; value: root.progresiva && root.progresiva.length ? root.progresiva : "Km / Progresiva"; iconSource: root.i("depth") }
                }
            }
        }

        Rectangle {
            width: parent.width
            radius: 22
            color: root.card
            border.width: 1
            border.color: root.border
            implicitHeight: logosCol.implicitHeight + 24

            ColumnLayout {
                id: logosCol
                anchors.fill: parent
                anchors.margins: 12
                spacing: 10

                RowLayout { Layout.fillWidth: true; spacing: 8
                    Image { Layout.preferredWidth: 30; Layout.preferredHeight: 30; source: root.i("logo_mtc_icon"); fillMode: Image.PreserveAspectFit; smooth: true }
                    Text { Layout.fillWidth: true; text: "Logos reales de ficha"; color: root.textMain; font.pixelSize: 17; font.bold: true }
                }

                RowLayout { Layout.fillWidth: true; spacing: 8
                    LogoPreviewCard { Layout.fillWidth: true; title: "Logo MTC"; sourceIcon: root.i("logo_mtc_icon"); sourceLogo: root.hasLogoMtc ? root.logoMtcSource : CalIcons.logoMtcDefault(); buttonColor: root.navy; onClicked: root.requestPickMtc() }
                    LogoPreviewCard { Layout.fillWidth: true; title: "Logo empresa"; sourceIcon: root.i("logo_project_icon"); sourceLogo: root.hasLogoProyecto ? root.logoProyectoSource : CalIcons.logoEmpresaDefault(); buttonColor: root.teal; onClicked: root.requestPickProject() }
                }

                Text { Layout.fillWidth: true; text: "Los logos se cargan con PreserveAspectFit: no se estiran, no se recortan y no se reemplazan por placeholders."; color: root.textSub; font.pixelSize: 11; wrapMode: Text.WordWrap }
            }
        }

        Rectangle {
            width: parent.width
            radius: 22
            color: root.card
            border.width: 1
            border.color: root.border
            implicitHeight: actionCol.implicitHeight + 24

            ColumnLayout {
                id: actionCol
                anchors.fill: parent
                anchors.margins: 12
                spacing: 10

                RowLayout { Layout.fillWidth: true; spacing: 8
                    Image { Layout.preferredWidth: 30; Layout.preferredHeight: 30; source: root.a("addStratum"); fillMode: Image.PreserveAspectFit; smooth: true }
                    Text { Layout.fillWidth: true; text: "Acciones generales"; color: root.textMain; font.pixelSize: 17; font.bold: true }
                }

                RowLayout { Layout.fillWidth: true; spacing: 8
                    ActionTile { Layout.fillWidth: true; label: "Estratos"; iconSource: root.a("addStratum"); onClicked: root.requestAddEstrato() }
                    ActionTile { Layout.fillWidth: true; label: "Cámara"; iconSource: root.a("camera"); onClicked: root.requestTakePhoto() }
                    ActionTile { Layout.fillWidth: true; label: "Foto"; iconSource: root.a("addPhoto"); onClicked: root.requestTakePhoto() }
                    ActionTile { Layout.fillWidth: true; label: "Guardar"; iconSource: root.a("save"); filled: true; onClicked: root.requestSave() }
                }

                RowLayout { Layout.fillWidth: true; spacing: 8
                    PillButton { Layout.fillWidth: true; label: "Exportar Excel"; iconSource: root.a("export"); colorFill: root.teal; onClicked: root.requestExportExcel() }
                    PillButton { Layout.fillWidth: true; label: "Exportar PDF"; iconSource: root.a("export"); colorFill: root.orange; onClicked: root.requestExportPdf() }
                }
            }
        }

        Rectangle {
            width: parent.width
            radius: 18
            color: root.darkMode ? "#0B2B45" : "#EAF6FF"
            border.width: 1
            border.color: root.darkMode ? "#26577E" : "#CFE8F8"
            implicitHeight: pendingRow.implicitHeight + 18
            RowLayout {
                id: pendingRow
                anchors.fill: parent
                anchors.margins: 10
                spacing: 10
                Image { Layout.preferredWidth: 28; Layout.preferredHeight: 28; source: root.i("editable"); fillMode: Image.PreserveAspectFit; smooth: true }
                Text { Layout.fillWidth: true; text: "Cierre 5.4: UI general refinada. El editable técnico detallado de calicatas no queda cerrado todavía."; color: root.textMain; font.pixelSize: 12; wrapMode: Text.WordWrap }
            }
        }
    }

    component IconBox: Rectangle {
        property url iconSource: ""
        property int iconSize: 38
        property color boxColor: root.card
        radius: 18
        color: boxColor
        border.width: 1
        border.color: root.border
        Image { anchors.centerIn: parent; width: iconSize; height: iconSize; source: iconSource; fillMode: Image.PreserveAspectFit; smooth: true }
    }

    component StatusChip: Rectangle {
        property string label: ""
        property url iconSource: ""
        implicitHeight: 38
        radius: 19
        color: root.darkMode ? "#102E4D" : "#FFFFFF"
        border.width: 1
        border.color: root.border
        Row { anchors.centerIn: parent; spacing: 8; Image { width: 22; height: 22; source: iconSource; fillMode: Image.PreserveAspectFit; smooth: true } Text { text: label; color: root.textMain; font.pixelSize: 12; font.bold: true } }
    }

    component InfoMiniCard: Rectangle {
        property string title: ""
        property string value: ""
        property url iconSource: ""
        implicitHeight: 64
        radius: 17
        color: root.cardSoft
        border.width: 1
        border.color: root.border
        RowLayout { anchors.fill: parent; anchors.margins: 9; spacing: 8
            Image { Layout.preferredWidth: 28; Layout.preferredHeight: 28; source: iconSource; fillMode: Image.PreserveAspectFit; smooth: true }
            ColumnLayout { Layout.fillWidth: true; spacing: 0
                Text { Layout.fillWidth: true; text: title; color: root.textSub; font.pixelSize: 11; elide: Text.ElideRight }
                Text { Layout.fillWidth: true; text: value; color: root.textMain; font.pixelSize: 13; font.bold: true; elide: Text.ElideRight }
            }
        }
    }

    component LogoPreviewCard: Rectangle {
        property string title: ""
        property url sourceLogo: ""
        property url sourceIcon: ""
        property color buttonColor: root.navy
        signal clicked()
        implicitHeight: 144
        radius: 18
        color: root.cardSoft
        border.width: 1
        border.color: root.border
        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 10
            spacing: 6
            RowLayout { Layout.fillWidth: true; spacing: 6; Image { Layout.preferredWidth: 30; Layout.preferredHeight: 30; source: sourceIcon; fillMode: Image.PreserveAspectFit; smooth: true } Text { Layout.fillWidth: true; text: title; color: root.textMain; font.pixelSize: 13; font.bold: true; elide: Text.ElideRight } }
            Rectangle { Layout.fillWidth: true; Layout.preferredHeight: 64; radius: 12; color: root.darkMode ? "#082038" : "#FFFFFF"; border.width: 1; border.color: root.border; clip: true
                Image { anchors.centerIn: parent; width: parent.width - 12; height: parent.height - 10; source: sourceLogo; fillMode: Image.PreserveAspectFit; smooth: true; mipmap: true }
            }
            Rectangle { Layout.fillWidth: true; height: 34; radius: 12; color: buttonColor
                Text { anchors.centerIn: parent; text: "Cambiar"; color: "white"; font.pixelSize: 12; font.bold: true }
                MouseArea { anchors.fill: parent; onClicked: parent.parent.clicked() }
            }
        }
    }

    component ActionTile: Rectangle {
        property string label: ""
        property url iconSource: ""
        property bool filled: false
        signal clicked()
        implicitHeight: 74
        radius: 18
        color: filled ? root.navy : root.cardSoft
        border.width: 1
        border.color: filled ? root.navy : root.border
        Column { anchors.centerIn: parent; spacing: 4; Image { width: 44; height: 44; source: iconSource; fillMode: Image.PreserveAspectFit; smooth: true; mipmap: true; anchors.horizontalCenter: parent.horizontalCenter } Text { text: label; color: filled ? "white" : root.textMain; font.pixelSize: 12; font.bold: true; anchors.horizontalCenter: parent.horizontalCenter } }
        MouseArea { anchors.fill: parent; onClicked: parent.clicked() }
    }

    component PillButton: Rectangle {
        property string label: ""
        property url iconSource: ""
        property color colorFill: root.teal
        signal clicked()
        implicitHeight: 46
        radius: 16
        color: colorFill
        Row { anchors.centerIn: parent; spacing: 8; Image { width: 28; height: 28; source: iconSource; fillMode: Image.PreserveAspectFit; smooth: true; mipmap: true } Text { text: label; color: "white"; font.pixelSize: 13; font.bold: true } }
        MouseArea { anchors.fill: parent; onClicked: parent.clicked() }
    }
}

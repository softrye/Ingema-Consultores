// SPDX-License-Identifier: GPL-3.0-only
import QtQuick
import InGe.CoreFlow 3.0 as Mobile

Item {
    id: cell
    required property var entry
    required property var controller
    property bool grid: false
    property color ink: "white"
    property color surface: Mobile.InGeCoreFlow.colors.ingemaNavy
    // Identidad INGEMA: acento y texto secundario los publica NothingDocumentsRoot.
    property color accent: Mobile.InGeCoreFlow.theme.accent
    property color muted: Mobile.InGeCoreFlow.theme.textTertiary
    property bool chosen: controller.selectedCount > 0 && controller.selected(entry.path)
    // Long press (fuera de selección múltiple): lift sutil mientras el menú está abierto.
    property string heldPath: ""
    readonly property bool lifted: heldPath.length > 0 && heldPath === entry.path
    signal menuRequested(var file)
    signal activated(var file)
    signal longPressed(var file)
    height: grid ? 150 : 80
    z: lifted ? 2 : 0
    scale: lifted ? 1.02 : 1
    Behavior on scale { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
    Rectangle {
        anchors.fill: parent
        anchors.margins: 4
        anchors.topMargin: 8
        anchors.bottomMargin: 1
        radius: cell.grid ? 24 : 20
        color: "#000000"
        opacity: cell.lifted ? 0.22 : 0
        Behavior on opacity { NumberAnimation { duration: 140 } }
    }
    Rectangle {
        anchors.fill: parent
        anchors.margins: 4
        radius: cell.grid ? 24 : 20
        color: cell.chosen ? Qt.rgba(cell.accent.r, cell.accent.g, cell.accent.b, 0.15) : (cell.grid || cell.lifted) ? cell.surface : "transparent"
        border.width: cell.chosen || cell.lifted ? 1 : 0
        border.color: cell.accent
    }
    MouseArea {
        anchors.fill: parent
        // Un hold manejado no emite clicked: el long press nunca abre la carpeta.
        // Si la lista empieza a desplazarse, el Flickable cancela este MouseArea.
        onClicked: cell.controller.selectedCount ? cell.controller.toggleSelection(cell.entry.path) : cell.activated(cell.entry)
        onPressAndHold: cell.controller.selectedCount ? cell.controller.toggleSelection(cell.entry.path) : cell.longPressed(cell.entry)
        Accessible.role: Accessible.Button
        Accessible.name: cell.entry.name
    }
    Rectangle {
        id: preview
        x: cell.grid ? (parent.width - width) / 2 : 16
        y: cell.grid ? 12 : 18
        width: cell.grid ? 76 : 44
        height: width
        radius: 12
        color: cell.entry.directory ? Qt.rgba(cell.accent.r, cell.accent.g, cell.accent.b, 0.10) : "transparent"
        NothingIcon {
            anchors.centerIn: parent
            name: cell.entry.icon || "insert_drive_file"
            ink: cell.accent
        }
        Image {
            anchors.fill: parent
            asynchronous: true
            cache: true
            sourceSize.width: 160
            sourceSize.height: 160
            fillMode: Image.PreserveAspectCrop
            source: !cell.entry.remote && cell.entry.kind === "image" ? cell.entry.url : !cell.entry.remote && cell.entry.kind === "video" ? "image://nothingvideo/" + encodeURIComponent(cell.entry.path) : ""
        }
        Rectangle {
            anchors.fill: parent
            visible: cell.chosen
            radius: 12
            color: Qt.rgba(cell.accent.r, cell.accent.g, cell.accent.b, 0.50)
            NothingIcon {
                anchors.centerIn: parent
                name: "check"
                ink: "white"
            }
        }
    }
    Column {
        x: cell.grid ? 12 : 76
        y: cell.grid ? 98 : 23
        width: cell.grid ? cell.width - 24 : cell.width - 120
        spacing: 4
        Text {
            width: parent.width
            text: String(cell.entry.name || "").toUpperCase()
            elide: Text.ElideRight
            color: cell.ink
            font.family: Mobile.InGeCoreFlow.typography.family
            font.pixelSize: cell.grid ? 10 : 14
            font.bold: !cell.grid
            horizontalAlignment: cell.grid ? Text.AlignHCenter : Text.AlignLeft
        }
        Text {
            width: parent.width
            text: (cell.grid ? "" : (cell.entry.date || "") + " • ") + (cell.entry.directory ? "CARPETA" : cell.controller.formatSize(cell.entry.bytes || 0))
            elide: Text.ElideRight
            color: cell.muted
            font.family: Mobile.InGeCoreFlow.typography.family
            font.pixelSize: cell.grid ? 8 : 10
            horizontalAlignment: cell.grid ? Text.AlignHCenter : Text.AlignLeft
        }
    }
    NothingButton {
        x: cell.width - width - 4
        y: cell.grid ? 2 : 18
        glyph: "more_vert"
        visible: cell.controller.selectedCount === 0
        Accessible.name: "Acciones de " + cell.entry.name
        onClicked: cell.menuRequested(cell.entry)
    }
}

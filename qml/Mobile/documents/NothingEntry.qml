import QtQuick
import QtQuick.Controls

Item {
    id: cell
    required property var entry
    required property var controller
    property bool grid: false
    property color ink: "#111827"
    property color surface: "#FFFFFF"
    property color accent: "#0654A2"
    property color muted: "#64748B"
    property string heldPath: ""
    readonly property bool chosen: controller.selectedCount > 0 && controller.selected(entry.path)
    signal menuRequested(var file)
    signal activated(var file)
    signal longPressed(var file)
    implicitHeight: grid ? 150 : 66
    height: implicitHeight
    Rectangle {
        anchors.fill: parent
        color: cell.chosen ? "#E8EDF4" : cell.surface
        border.color: "#D1D5DB"
        border.width: 1
    }
    Column {
        anchors.left: parent.left
        anchors.right: menuButton.left
        anchors.leftMargin: 10
        anchors.verticalCenter: parent.verticalCenter
        spacing: 4
        Text {
            width: parent.width
            text: (cell.entry.directory ? "[DIR] " : "[FILE] ") + String(cell.entry.name || "")
            elide: Text.ElideRight
            color: cell.ink
            font.pixelSize: 13
        }
        Text {
            width: parent.width
            text: cell.entry.directory ? "Carpeta" : cell.controller.formatSize(cell.entry.bytes || 0)
            color: cell.muted
            font.pixelSize: 11
            elide: Text.ElideRight
        }
    }
    MouseArea {
        anchors.fill: parent
        onClicked: cell.controller.selectedCount
                   ? cell.controller.toggleSelection(cell.entry.path) : cell.activated(cell.entry)
        onPressAndHold: cell.controller.selectedCount
                        ? cell.controller.toggleSelection(cell.entry.path) : cell.longPressed(cell.entry)
    }
    Button {
        id: menuButton
        anchors.right: parent.right
        anchors.rightMargin: 2
        anchors.verticalCenter: parent.verticalCenter
        width: 44
        text: "..."
        visible: cell.controller.selectedCount === 0
        Accessible.name: "Acciones de " + String(cell.entry.name || "")
        onClicked: cell.menuRequested(cell.entry)
    }
}

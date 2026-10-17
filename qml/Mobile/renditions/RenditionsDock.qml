import QtQuick
import "RStyle.js" as S

// Dock exclusivo de Rendiciones: exactamente tres acciones (Balance, Nueva
// rendición, Carpeta) y sin acceso a InGe IA. Conserva la altura, el margen
// inferior y la cápsula flotante del dock global (ui.dockHeight/dockBottom);
// cristal claro translúcido (no opaco), separadores sutiles.
Item {
    id: dock
    property var ui
    property string active: "balance"        // acción resaltada (menú abierto o vista actual)
    signal balance(real cx, real cy)
    signal create(real cx, real cy)
    signal folder(real cx, real cy)

    readonly property real cell: 92 * ui.u
    width: cell * 3 + 16 * ui.u
    height: ui.dockHeight

    // Sombra flotante discreta (estática).
    Rectangle { anchors.fill: parent; anchors.topMargin: 10 * dock.ui.u; anchors.margins: -3 * dock.ui.u; radius: height / 2; color: S.ink(0.05) }
    Rectangle { anchors.fill: parent; anchors.topMargin: 5 * dock.ui.u; radius: height / 2; color: S.ink(0.05) }
    // Cristal: blanco translúcido + brillo superior + borde luminoso.
    Rectangle {
        anchors.fill: parent
        radius: height / 2
        gradient: Gradient {
            GradientStop { position: 0.0; color: Qt.rgba(1, 1, 1, 0.78) }
            GradientStop { position: 0.55; color: Qt.rgba(1, 1, 1, 0.52) }
            GradientStop { position: 1.0; color: Qt.rgba(236 / 255, 242 / 255, 250 / 255, 0.62) }
        }
        border.width: 1
        border.color: Qt.rgba(1, 1, 1, 0.92)
    }
    Rectangle {
        anchors.fill: parent; anchors.margins: 1
        radius: height / 2
        color: "transparent"
        border.width: 1
        border.color: S.ink(0.05)
    }

    component DockCell: Item {
        id: cellItem
        property string key: ""
        property string label: ""
        default property alias glyphContent: glyphSlot.data
        signal triggered()
        width: dock.cell
        height: dock.height
        readonly property bool highlighted: dock.active === key
        Rectangle {
            anchors.centerIn: parent
            width: 52 * dock.ui.u; height: width
            radius: width / 2
            color: cellItem.highlighted ? Qt.rgba(6 / 255, 84 / 255, 162 / 255, 0.10) : "transparent"
            border.width: cellItem.highlighted ? 1 : 0
            border.color: Qt.rgba(1, 1, 1, 0.9)
            scale: tap.pressed ? 0.9 : 1
            Behavior on scale { NumberAnimation { duration: 110; easing.type: Easing.OutQuad } }
            Behavior on color { ColorAnimation { duration: 180 } }
            Item { id: glyphSlot; anchors.centerIn: parent; width: 30 * dock.ui.u; height: width }
        }
        MouseArea { id: tap; anchors.fill: parent; onClicked: cellItem.triggered() }
        Accessible.role: Accessible.Button
        Accessible.name: label
    }

    Row {
        anchors.centerIn: parent
        DockCell {
            key: "balance"; label: "Balance de rendiciones"
            onTriggered: { var p = mapToItem(dock, width / 2, 0); dock.balance(p.x, p.y) }
            // Gráfico de barras (tres barras redondeadas).
            Row {
                anchors.centerIn: parent
                height: 22 * dock.ui.u
                spacing: 3 * dock.ui.u
                Repeater {
                    model: [0.45, 0.72, 1.0]
                    delegate: Rectangle {
                        required property real modelData
                        width: 6 * dock.ui.u
                        height: 22 * dock.ui.u * modelData
                        radius: 3 * dock.ui.u
                        y: 22 * dock.ui.u - height
                        color: dock.active === "balance" ? S.corporateBlue : S.ink(0.62)
                    }
                }
            }
        }
        Rectangle { width: 1; height: 26 * dock.ui.u; anchors.verticalCenter: parent.verticalCenter; color: S.ink(0.12) }
        DockCell {
            key: "create"; label: "Nueva rendición"
            onTriggered: { var p = mapToItem(dock, width / 2, 0); dock.create(p.x, p.y) }
            // Signo más dentro de un círculo.
            Rectangle {
                anchors.centerIn: parent
                width: 28 * dock.ui.u; height: width; radius: width / 2
                color: "transparent"
                border.width: 2 * dock.ui.u
                border.color: dock.active === "create" ? S.corporateBlue : S.ink(0.66)
                Rectangle { anchors.centerIn: parent; width: 12 * dock.ui.u; height: 2 * dock.ui.u; radius: 1; color: parent.border.color }
                Rectangle { anchors.centerIn: parent; width: 2 * dock.ui.u; height: 12 * dock.ui.u; radius: 1; color: parent.border.color }
            }
        }
        Rectangle { width: 1; height: 26 * dock.ui.u; anchors.verticalCenter: parent.verticalCenter; color: S.ink(0.12) }
        DockCell {
            key: "folder"; label: "Carpeta documental"
            onTriggered: { var p = mapToItem(dock, width / 2, 0); dock.folder(p.x, p.y) }
            Text {
                anchors.centerIn: parent
                text: String.fromCharCode(0xE0D7)             // Lucide folder
                font.family: dock.ui.iconFamily
                font.pixelSize: 27 * dock.ui.u
                color: dock.active === "folder" ? S.corporateBlue : S.ink(0.66)
            }
        }
    }
}

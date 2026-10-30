import QtQuick
import "RStyle.js" as S

// Opción de un RGlassMenu: icono (glifo Lucide o dibujo) + texto + separador.
Item {
    id: item
    property var ui
    property string label: ""
    property int glyph: 0
    property color glyphColor: S.muted
    property bool separator: true
    property bool enabledItem: true
    default property alias icon: iconSlot.data
    signal activated()
    width: parent ? parent.width : 0
    height: 44 * ui.u                          // fila compacta estilo iOS
    opacity: enabledItem ? 1 : 0.45

    Rectangle { anchors.fill: parent; anchors.margins: 2 * item.ui.u; radius: 12 * item.ui.u; color: tap.pressed ? S.ink(0.06) : "transparent" }
    Item {
        id: iconSlot
        x: 6 * item.ui.u
        width: 28 * item.ui.u; height: 28 * item.ui.u
        anchors.verticalCenter: parent.verticalCenter
        Text {
            anchors.centerIn: parent
            visible: item.glyph > 0
            text: String.fromCharCode(item.glyph)
            font.family: item.ui.iconFamily
            font.pixelSize: 19 * item.ui.u
            color: item.glyphColor
        }
    }
    Text {
        x: 42 * item.ui.u
        width: parent.width - x - 8 * item.ui.u
        anchors.verticalCenter: parent.verticalCenter
        text: item.label
        color: S.text
        elide: Text.ElideRight
        font.family: item.ui.fontFamily
        font.pixelSize: 15 * item.ui.u
    }
    Rectangle {
        visible: item.separator
        x: 42 * item.ui.u
        width: parent.width - x
        height: 1
        anchors.bottom: parent.bottom
        color: S.ink(0.08)
    }
    MouseArea { id: tap; anchors.fill: parent; enabled: item.enabledItem; onClicked: item.activated() }
    Accessible.role: Accessible.MenuItem
    Accessible.name: label
}

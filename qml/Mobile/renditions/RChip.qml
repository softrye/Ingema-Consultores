import QtQuick
import "RStyle.js" as S

// Píldora seleccionable (filtros, pestañas, opciones).
Rectangle {
    id: chip
    property var ui
    property string label: ""
    property bool selected: false
    property bool enabledChip: true
    property color tone: S.accentSoft
    signal activated()

    implicitHeight: 38 * ui.u
    implicitWidth: chipText.implicitWidth + 28 * ui.u
    radius: height / 2
    color: selected ? S.accent : S.ink(tap.pressed ? 0.16 : 0.07)
    border.width: 1
    border.color: selected ? "transparent" : S.border
    opacity: enabledChip ? 1 : 0.45
    Text {
        id: chipText
        anchors.centerIn: parent
        text: chip.label
        color: chip.selected ? S.onAccent : S.text
        font.family: chip.ui.fontFamily
        font.pixelSize: 14 * chip.ui.u
    }
    MouseArea {
        id: tap
        anchors.fill: parent
        enabled: chip.enabledChip
        onClicked: chip.activated()
    }
    Accessible.role: Accessible.Button
    Accessible.name: label
    Accessible.checked: selected
}

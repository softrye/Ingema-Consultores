import QtQuick

// Fila de ajustes: icono en baldosa, título, subtítulo y, a la derecha, valor,
// interruptor o flecha (equivale a SettingsIcon + NavigationLink/Toggle/InfoRow).
Item {
    id: row
    property var ui
    property int glyph: 0
    property string title: ""
    property string subtitle: ""
    property string value: ""
    property bool chevron: true
    property bool toggle: false
    property bool checked: false
    property bool last: false
    readonly property bool dark: !!ui && ui.darkTheme === true
    property color titleColor: dark ? "#F2F4F8" : "#151A30"
    property color tone: "#0654A2"                 // color del icono y su baldosa
    property color valueColor: dark ? "#A3A9B6" : "#5A6378"
    signal clicked()
    signal toggled(bool value)
    width: parent ? parent.width : 0
    height: (subtitle.length ? 72 : 56) * ui.u
    property bool enabledRow: true
    opacity: enabledRow ? 1 : 0.5
    scale: tap.pressed ? 0.985 : 1
    Behavior on scale { NumberAnimation { duration: 110; easing.type: Easing.OutCubic } }

    Rectangle { anchors.fill: parent; color: row.dark ? Qt.rgba(1, 1, 1, tap.pressed ? 0.06 : 0) : Qt.rgba(21 / 255, 26 / 255, 48 / 255, tap.pressed ? 0.06 : 0) }
    Rectangle {
        id: tile
        visible: row.glyph > 0
        x: 14 * row.ui.u; anchors.verticalCenter: parent.verticalCenter
        width: 40 * row.ui.u; height: width; radius: 11 * row.ui.u
        gradient: Gradient {
            GradientStop { position: 0.0; color: (row.dark ? Qt.lighter(row.tone, 1.25) : Qt.lighter(row.tone, 1.35)) }
            GradientStop { position: 1.0; color: row.dark ? Qt.lighter(row.tone, 1.25) : row.tone }
        }
        border.width: 1; border.color: Qt.rgba(1, 1, 1, 0.55)
        Text { anchors.centerIn: parent; text: String.fromCharCode(row.glyph); color: "white"
               font.family: row.ui.iconFamily; font.pixelSize: 19 * row.ui.u }
    }
    Column {
        x: tile.visible ? tile.x + tile.width + 14 * row.ui.u : 18 * row.ui.u
        width: trailing.x - x - 10 * row.ui.u
        anchors.verticalCenter: parent.verticalCenter
        spacing: 3 * row.ui.u
        Text { width: parent.width; text: row.title; color: row.titleColor; elide: Text.ElideRight
               font.family: row.ui.fontFamily; font.pixelSize: 16.5 * row.ui.u; font.weight: Font.DemiBold }
        Text { width: parent.width; visible: row.subtitle.length > 0; text: row.subtitle; elide: Text.ElideRight
               color: row.valueColor; font.family: row.ui.fontFamily; font.pixelSize: 12.5 * row.ui.u }
    }
    Row {
        id: trailing
        anchors.right: parent.right; anchors.rightMargin: 16 * row.ui.u; anchors.verticalCenter: parent.verticalCenter
        spacing: 8 * row.ui.u
        Text { visible: row.value.length > 0; anchors.verticalCenter: parent.verticalCenter; text: row.value
               color: row.valueColor; font.family: row.ui.fontFamily; font.pixelSize: 14 * row.ui.u }
        SettingsSwitch { visible: row.toggle; enabled: row.enabledRow; ui: row.ui; checked: row.checked; onToggled: function(v) { row.toggled(v) } }
        Text { visible: row.chevron && !row.toggle; anchors.verticalCenter: parent.verticalCenter
               text: String.fromCharCode(0xE06F); color: row.dark ? "#8A93A8" : "#7A8299"
               font.family: row.ui.iconFamily; font.pixelSize: 18 * row.ui.u }
    }
    Rectangle {                                       // separador interno (no en la última fila)
        visible: !row.last
        anchors.bottom: parent.bottom; anchors.right: parent.right
        x: tile.visible ? tile.x + tile.width + 14 * row.ui.u : 18 * row.ui.u
        width: parent.width - x; height: 1; color: row.dark ? Qt.rgba(1, 1, 1, 0.08) : Qt.rgba(21 / 255, 26 / 255, 48 / 255, 0.08)
    }
    MouseArea { id: tap; anchors.fill: parent; enabled: !row.toggle && row.enabledRow; onClicked: row.clicked() }
    Accessible.role: row.toggle ? Accessible.CheckBox : Accessible.Button
    Accessible.name: row.title
}

import QtQuick

// Grupo redondeado de ajustes (equivalente a Section de SwiftUI), vidrio claro.
Rectangle {
    id: group
    property var ui
    default property alias content: body.data
    width: parent ? parent.width : 0
    implicitHeight: body.implicitHeight
    radius: 22 * ui.u
    readonly property bool dark: !!ui && ui.darkTheme === true
    color: dark ? Qt.rgba(28 / 255, 45 / 255, 80 / 255, 0.55) : Qt.rgba(1, 1, 1, 0.80)
    border.width: 1
    border.color: dark ? Qt.rgba(1, 1, 1, 0.08) : "white"
    Behavior on color { ColorAnimation { duration: 220 } }
    clip: true
    Column { id: body; width: parent.width }
}

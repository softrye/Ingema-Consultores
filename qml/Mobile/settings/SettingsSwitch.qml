import QtQuick

// Interruptor estilo iOS (Toggle).
Rectangle {
    id: sw
    property var ui
    property bool checked: false
    signal toggled(bool value)
    width: 51 * ui.u; height: 31 * ui.u; radius: height / 2
    color: checked ? (sw.ui && sw.ui.darkTheme === true ? "#8AB8FF" : "#0654A2")
                   : (sw.ui && sw.ui.darkTheme === true ? Qt.rgba(1, 1, 1, 0.18) : Qt.rgba(21 / 255, 26 / 255, 48 / 255, 0.16))
    Behavior on color { ColorAnimation { duration: 160 } }
    Rectangle {
        width: 27 * sw.ui.u; height: width; radius: width / 2; color: "white"
        anchors.verticalCenter: parent.verticalCenter
        x: sw.checked ? parent.width - width - 2 * sw.ui.u : 2 * sw.ui.u
        Behavior on x { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
    }
    MouseArea { anchors.fill: parent; onClicked: sw.toggled(!sw.checked) }
    Accessible.role: Accessible.CheckBox
    Accessible.checked: checked
}

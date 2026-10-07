import QtQuick 2.15

Rectangle {
    id: root

    property var flow: null
    property bool active: false
    property color accent: flow ? flow.theme.focus : "#0654A2"
    property real ringRadius: 14

    anchors.fill: parent
    anchors.margins: -2
    radius: ringRadius
    color: "transparent"
    border.width: active ? 2 : 0
    border.color: accent
    opacity: active ? 1.0 : 0.0
    scale: active ? 1.0 : 0.985
    visible: opacity > 0.001
    z: 10

    Behavior on opacity {
        NumberAnimation { duration: root.flow ? root.flow.fastDuration : 105; easing.type: Easing.OutCubic }
    }
    Behavior on scale {
        NumberAnimation { duration: root.flow ? root.flow.normalDuration : 180; easing.type: Easing.OutCubic }
    }
}

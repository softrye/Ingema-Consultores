import QtQuick 2.15

Row {
    id: root
    property bool active: false
    property color color: "#8FB2D5"
    property var flow
    spacing: 3
    Repeater {
        model: 5
        Rectangle {
            required property int index
            width: 3
            radius: 2
            color: root.color
            height: root.active ? 7 + ((index * 7) % 15) : 4
            opacity: root.active ? 1.0 : 0.45
            Behavior on height { NumberAnimation { duration: root.flow ? root.flow.fastDuration : 110 } }
            SequentialAnimation on height {
                running: Boolean(root.active && root.flow !== null && root.flow !== undefined && root.flow.motionAllowed === true)
                loops: Animation.Infinite
                NumberAnimation { from: 5 + index; to: 18 - index; duration: 240 + index * 45; easing.type: Easing.InOutSine }
                NumberAnimation { from: 18 - index; to: 5 + index; duration: 260 + index * 55; easing.type: Easing.InOutSine }
            }
        }
    }
}

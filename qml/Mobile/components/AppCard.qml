import QtQuick 2.15
import InGe.CoreFlow 3.0 as Mobile
import "../flowcore" as FlowCore

Rectangle {
    id: root

    property color fillColor: flow.theme.isGlass
                              ? flow.theme.glassSurface : flow.theme.surface
    property color strokeColor: flow.theme.border
    property bool animateOnCompleted: true
    property bool motionEnabled: true
    property bool reduceMotion: false
    property int motionLevel: 2
    property int revealDelay: 0

    radius: flow.radius.card
    color: fillColor
    border.color: strokeColor
    border.width: 1
    transformOrigin: Item.Center

    readonly property var flow: Mobile.InGeCoreFlow

    Rectangle {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: 1
        height: 1
        radius: root.radius
        color: flow.theme.isGlass ? flow.theme.glassHighlight : "transparent"
        visible: flow.theme.isGlass
    }



    Behavior on color { ColorAnimation { duration: flow.normalDuration } }
    Behavior on border.color { ColorAnimation { duration: flow.normalDuration } }
}

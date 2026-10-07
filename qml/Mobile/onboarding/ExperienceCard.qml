import QtQuick 2.15
import QtQuick.Controls 2.15

Rectangle {
    id: root
    property string title: ""
    property string subtitle: ""
    property string symbol: ""
    property color accent: "#8FB2D5"
    property bool selected: false
    property var flow
    signal clicked()

    radius: 22
    color: selected ? "#1DFFFFFF" : "#10FFFFFF"
    border.width: selected ? 2 : 1
    border.color: selected ? accent : "#36FFFFFF"
    scale: mouse.pressed && flow ? flow.cardPressScale : 1.0

    Behavior on scale { NumberAnimation { duration: flow ? flow.fastDuration : 110; easing.type: Easing.OutCubic } }
    Behavior on border.color { ColorAnimation { duration: flow ? flow.normalDuration : 180 } }
    Behavior on color { ColorAnimation { duration: flow ? flow.normalDuration : 180 } }

    Row {
        anchors.fill: parent
        anchors.margins: 16
        spacing: 14
        Rectangle {
            width: 48
            height: 48
            radius: 16
            color: root.selected ? root.accent : "#16FFFFFF"
            Text {
                anchors.centerIn: parent
                text: root.symbol
                color: root.selected ? "#FFFFFF" : root.accent
                font.pixelSize: 22
                font.bold: true
            }
        }
        Column {
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width - 78
            spacing: 4
            Text { width: parent.width; text: root.title; color: "#FFFFFF"; font.pixelSize: 16; font.bold: true; elide: Text.ElideRight }
            Text { width: parent.width; text: root.subtitle; color: "#C8D8E8"; font.pixelSize: 12; wrapMode: Text.WordWrap; maximumLineCount: 2; elide: Text.ElideRight }
        }
    }

    MouseArea { id: mouse; anchors.fill: parent; onClicked: root.clicked() }
}

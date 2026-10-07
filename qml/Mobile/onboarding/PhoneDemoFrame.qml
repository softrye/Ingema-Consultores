import QtQuick 2.15

Rectangle {
    id: root
    property bool active: false
    property var flow
    property string title: "InGe+"
    property string status: "GPS listo · Sync"
    property color accent: "#8FB2D5"
    property alias contentData: content.data

    radius: 34
    color: "#F8FBFF"
    border.width: 2
    border.color: "#58FFFFFF"
    opacity: root.active ? 1 : 0
    scale: root.active ? 1 : 0.88
    rotation: root.active ? 0 : -3
    Behavior on opacity { NumberAnimation { duration: root.flow ? root.flow.cardRevealDuration : 300 } }
    Behavior on scale { NumberAnimation { duration: root.flow ? root.flow.experienceMorphDuration : 620; easing.type: Easing.OutBack } }
    Behavior on rotation { NumberAnimation { duration: root.flow ? root.flow.experienceMorphDuration : 620; easing.type: Easing.OutQuart } }

    Rectangle {
        anchors.top: parent.top
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.topMargin: 8
        width: 68
        height: 6
        radius: 3
        color: "#C7D4DF"
    }

    Rectangle {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.topMargin: 24
        height: 68
        color: "#0654A2"
        Text { anchors.left: parent.left; anchors.leftMargin: 18; anchors.verticalCenter: parent.verticalCenter; text: root.title; color: "white"; font.pixelSize: 18; font.bold: true }
        Text { anchors.right: parent.right; anchors.rightMargin: 16; anchors.verticalCenter: parent.verticalCenter; text: root.status; color: "#D9F4FF"; font.pixelSize: 9 }
    }

    Item {
        id: content
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.topMargin: 92
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 18
        anchors.margins: 14
    }
}

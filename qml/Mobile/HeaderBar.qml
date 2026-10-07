import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15
import InGe.CoreFlow 3.0 as Mobile
import "flowcore" as FlowCore
import "components" as Components

Rectangle {
    id: root

    height: 150
    implicitHeight: 150
    color: "#004F8C"
    clip: true

    property string greetingText: "Hola, Invitado"
    property string subGreetingText: ""
    property bool showSearch: true
    property bool online: true
    property bool motionEnabled: true
    property bool reduceMotion: false
    property int motionLevel: 2

    signal menuClicked()
    signal searchAccepted(string text)

    readonly property var flow: Mobile.InGeCoreFlow

    ColumnLayout {
        id: content
        anchors.fill: parent
        anchors.margins: 18
        spacing: 10

        RowLayout {
            spacing: 10
            Layout.fillWidth: true

            Image {
                id: logo
                source: "qrc:/ui/v2/branding/logo_oficial_ingeplus_dark.png"
                sourceClipRect: Qt.rect(297, 175, 397, 150)
                fillMode: Image.PreserveAspectFit
                smooth: true
                Layout.preferredWidth: 106
                Layout.preferredHeight: 46
                Layout.minimumWidth: 106
                Layout.minimumHeight: 46
                Layout.maximumWidth: 106
                Layout.maximumHeight: 46
                Layout.alignment: Qt.AlignVCenter
            }

            Item {
                Layout.fillWidth: true
                Layout.preferredHeight: 40
                Layout.alignment: Qt.AlignVCenter
                visible: root.showSearch
                scale: tfSearch.activeFocus ? flow.focusScale : 1.0

                Behavior on scale { NumberAnimation { duration: flow.normalDuration; easing.type: flow.easeOut } }

                TextField {
                    id: tfSearch
                    anchors.fill: parent
                    placeholderText: "Buscar ficha geológica..."
                    font.pixelSize: 14
                    leftPadding: 34
                    rightPadding: 12
                    background: Rectangle {
                        radius: 14
                        color: "#FFFFFF"
                        border.width: tfSearch.activeFocus ? 2 : 1
                        border.color: tfSearch.activeFocus ? "#27B9DC" : "#E0E0E0"
                        Behavior on border.color { ColorAnimation { duration: flow.fastDuration } }
                    }
                    onAccepted: root.searchAccepted(text)
                }

                Components.FlowIcon {
                    anchors.left: parent.left
                    anchors.leftMargin: 10
                    anchors.verticalCenter: parent.verticalCenter
                    width: 18
                    height: 18
                    name: "action.search"
                    flow: flow
                    active: tfSearch.activeFocus
                    tintColor: "#7A8CA4"
                    activeTintColor: "#0780C3"
                    inactiveOpacity: 1.0
                }
            }

            ToolButton {
                id: btnMenu
                text: ""
                font.pixelSize: 16
                scale: down ? flow.compactPressScale : 1.0
                onClicked: root.menuClicked()
                Layout.preferredWidth: 34
                Layout.preferredHeight: 34
                Layout.minimumWidth: 34
                Layout.minimumHeight: 34
                Layout.maximumWidth: 34
                Layout.maximumHeight: 34
                Layout.alignment: Qt.AlignVCenter
                Behavior on scale { NumberAnimation { duration: flow.fastDuration; easing.type: flow.easeOut } }
                background: Rectangle {
                    radius: 9
                    color: btnMenu.down ? "#E59A00" : (btnMenu.hovered ? "#FCC253" : "#FDAC11")
                    Behavior on color { ColorAnimation { duration: flow.fastDuration } }
                }
                contentItem: Components.FlowIcon {
                    width: 19
                    height: 19
                    name: "action.menu"
                    flow: flow
                    pressed: btnMenu.down
                    tintColor: "#FFFFFF"
                    activeTintColor: "#FFFFFF"
                    inactiveOpacity: 1.0
                }
            }

            Rectangle {
                id: onlineDot
                width: 10
                height: 10
                radius: 5
                color: root.online ? "#6FC04A" : "#FDAC11"
                opacity: 0.95
                Layout.alignment: Qt.AlignVCenter
                Behavior on color { ColorAnimation { duration: flow.normalDuration } }
            }
        }

        ColumnLayout {
            spacing: 2
            Layout.fillWidth: true
            Label { text: root.greetingText; font.pixelSize: 18; font.bold: true; color: "white" }
            Label { text: root.subGreetingText; font.pixelSize: 13; color: "#CFE3F5" }
        }
    }

    onOnlineChanged: if (flow.motionAllowed) onlinePulse.restart()
    SequentialAnimation {
        id: onlinePulse
        NumberAnimation { target: onlineDot; property: "scale"; to: 1.7; duration: flow.fastDuration; easing.type: flow.easeOut }
        NumberAnimation { target: onlineDot; property: "scale"; to: 1.0; duration: flow.normalDuration; easing.type: flow.easeOvershoot }
    }


}

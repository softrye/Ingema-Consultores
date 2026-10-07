import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15
import InGe.CoreFlow 3.0 as Mobile
import "flowcore" as FlowCore
import "components" as Components

Rectangle {
    id: root

    height: 68
    color: "#005B97"
    property string currentKey: "home"
    property bool motionEnabled: true
    property bool reduceMotion: false
    property int motionLevel: 2
    signal tabClicked(string key)

    readonly property var flow: Mobile.InGeCoreFlow

    RowLayout {
        anchors.fill: parent
        anchors.margins: 8
        spacing: 8

        Repeater {
            model: [
                { key: "home", iconKey: "nav.home" },
                { key: "map", iconKey: "nav.map" },
                { key: "docs", iconKey: "nav.documents" },
                { key: "profile", iconKey: "profile.user" }
            ]

            delegate: Item {
                id: navItem
                required property var modelData
                Layout.fillWidth: true
                Layout.fillHeight: true
                readonly property bool active: root.currentKey === modelData.key
                property real lift: 0

                Rectangle {
                    anchors.fill: parent
                    radius: 16
                    color: tap.pressed ? "#2AFFFFFF" : (navItem.active ? "#18FFFFFF" : "transparent")
                    scale: tap.pressed ? flow.pressScale : 1.0
                    clip: true

                    Behavior on color { ColorAnimation { duration: flow.fastDuration } }
                    Behavior on scale { NumberAnimation { duration: flow.fastDuration; easing.type: flow.easeOut } }

                    FlowCore.FlowRipple {
                        id: ripple
                        flow: flow
                        rippleColor: "#44FFFFFF"
                        enabled: flow.motionAllowed
                    }

                    Components.FlowIcon {
                        anchors.centerIn: parent
                        anchors.verticalCenterOffset: navItem.lift
                        width: navItem.active ? 28 : 24
                        height: width
                        name: navItem.modelData.iconKey
                        flow: flow
                        active: navItem.active
                        pressed: tap.pressed
                        tintColor: "#D8E7F6"
                        activeTintColor: "#FFFFFF"
                        inactiveOpacity: 0.78
                    }

                    Rectangle {
                        width: navItem.active ? 22 : 0
                        height: 3
                        radius: 2
                        color: "#FDAC11"
                        anchors.horizontalCenter: parent.horizontalCenter
                        anchors.bottom: parent.bottom
                        anchors.bottomMargin: 2
                        Behavior on width { NumberAnimation { duration: flow.normalDuration; easing.type: flow.easeOut } }
                    }

                    MouseArea {
                        id: tap
                        anchors.fill: parent
                        hoverEnabled: true
                        onPressed: function(mouse) { ripple.trigger(mouse.x, mouse.y) }
                        onClicked: root.tabClicked(navItem.modelData.key)
                    }
                }

                onActiveChanged: if (active && flow.motionAllowed) activate.restart()
                SequentialAnimation {
                    id: activate
                    NumberAnimation { target: navItem; property: "lift"; to: -4; duration: flow.fastDuration; easing.type: flow.easeOut }
                    NumberAnimation { target: navItem; property: "lift"; to: 0; duration: flow.normalDuration; easing.type: flow.easeOvershoot }
                }
            }
        }
    }
}

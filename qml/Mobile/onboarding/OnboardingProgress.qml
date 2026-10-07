pragma ComponentBehavior: Bound

import QtQuick 2.15
import "../flowcore" as CoreFlow

CoreFlow.FlowGlassSurface {
    id: root

    property int count: 1
    property int currentIndex: 0
    property bool dark: true

    width: dots.implicitWidth + 18
    height: 21
    radius: 11
    darkMode: dark
    strength: 0.78
    highlightEnabled: false

    Row {
        id: dots
        anchors.centerIn: parent
        spacing: 5

        Repeater {
            model: root.count

            Rectangle {
                required property int index

                width: index === root.currentIndex ? 27 : 6
                height: 6
                radius: 3
                color: index === root.currentIndex
                       ? "#8FB2D5"
                       : (root.dark ? "#56FFFFFF" : "#350654A2")

                Behavior on width {
                    NumberAnimation {
                        duration: root.flow
                                  ? root.flow.motion.policy(root.flow.motion.tabSelect).duration
                                  : 180
                        easing.type: root.flow
                                     ? root.flow.motion.policy(root.flow.motion.tabSelect).easing
                                     : Easing.OutQuart
                    }
                }

                Behavior on color {
                    ColorAnimation {
                        duration: root.flow
                                  ? root.flow.motion.policy(root.flow.motion.tabSelect).duration
                                  : 180
                    }
                }
            }
        }
    }
}

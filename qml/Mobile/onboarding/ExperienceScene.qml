import QtQuick 2.15

Item {
    id: root
    property bool active: false
    property var flow
    property bool dark: true
    property color backgroundStart: dark ? "#07111F" : "#F4F9FD"
    property color backgroundEnd: dark ? "#151A30" : "#EAF4FF"
    property color primaryText: dark ? "#FFFFFF" : "#151A30"
    property color secondaryText: dark ? "#C8D8E8" : "#536176"
    property color accent: "#8FB2D5"
    property color secondaryAccent: "#0654A2"
    property real pointerX: width * 0.5
    property real pointerY: height * 0.5
    default property alias contentData: content.data

    opacity: active ? 1.0 : 0.74
    scale: active ? 1.0 : (flow ? flow.experienceDepthScale : 0.965)

    Behavior on opacity {
        NumberAnimation {
            duration: root.flow
                      ? root.flow.motion.policy(root.flow.motion.navigationForward).duration
                      : 230
            easing.type: root.flow
                         ? root.flow.motion.policy(root.flow.motion.navigationForward).easing
                         : Easing.OutCubic
        }
    }

    Behavior on scale {
        NumberAnimation {
            duration: root.flow
                      ? root.flow.motion.policy(root.flow.motion.navigationForward).duration
                      : 230
            easing.type: root.flow
                         ? root.flow.motion.policy(root.flow.motion.navigationForward).easing
                         : Easing.OutQuart
        }
    }

    PremiumBackdrop {
        anchors.fill: parent
        active: root.active
        flow: root.flow
        dark: root.dark
        accentA: root.accent
        accentB: root.secondaryAccent
        pointerX: root.pointerX
        pointerY: root.pointerY
    }

    Rectangle {
        anchors.fill: parent
        color: "transparent"

        gradient: Gradient {
            GradientStop {
                position: 0.0
                color: root.dark ? "#52040B14" : "#50FFFFFF"
            }
            GradientStop {
                position: 0.22
                color: "transparent"
            }
            GradientStop {
                position: 0.68
                color: "transparent"
            }
            GradientStop {
                position: 1.0
                color: root.dark ? "#A606101D" : "#B8F4F9FD"
            }
        }
    }

    Rectangle {
        anchors.left: parent.left
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        width: Math.max(14, parent.width * 0.045)
        color: "transparent"

        gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop {
                position: 0.0
                color: root.dark ? "#4D06101D" : "#42F4F9FD"
            }
            GradientStop {
                position: 1.0
                color: "transparent"
            }
        }
    }

    Rectangle {
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        width: Math.max(14, parent.width * 0.045)
        color: "transparent"

        gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop {
                position: 0.0
                color: "transparent"
            }
            GradientStop {
                position: 1.0
                color: root.dark ? "#4D06101D" : "#42F4F9FD"
            }
        }
    }

    Item {
        id: content
        anchors.fill: parent
        anchors.leftMargin: Math.max(20, Math.min(34, parent.width * 0.058))
        anchors.rightMargin: Math.max(20, Math.min(34, parent.width * 0.058))
        anchors.topMargin: Math.max(74, Math.min(88, parent.height * 0.10))
        anchors.bottomMargin: Math.max(132, Math.min(148, parent.height * 0.17))

        Rectangle {
            width: 42
            height: 3
            radius: 2
            x: root.active ? 0 : -12
            y: -8
            color: root.accent
            opacity: root.active ? 0.9 : 0.0

            Behavior on x {
                NumberAnimation {
                    duration: root.flow
                              ? root.flow.motion.policy(root.flow.motion.enterFade).duration
                              : 180
                    easing.type: Easing.OutQuart
                }
            }

            Behavior on opacity {
                NumberAnimation {
                    duration: root.flow
                              ? root.flow.motion.policy(root.flow.motion.enterFade).duration
                              : 180
                }
            }
        }
    }

    HoverHandler {
        id: hover
        enabled: root.active
        onPointChanged: {
            root.pointerX = point.position.x
            root.pointerY = point.position.y
        }
    }

}

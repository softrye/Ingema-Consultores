pragma ComponentBehavior: Bound

import QtQuick 2.15

Item {
    id: root

    property bool active: false
    property var flow
    property bool dark: true
    property color accentA: "#8FB2D5"
    property color accentB: "#0654A2"
    property real pointerX: width * 0.5
    property real pointerY: height * 0.5

    readonly property int performanceLevelSafe: root.flow ? Number(root.flow.performanceLevel) : 0
    readonly property bool premiumMotion: Boolean(
        root.active
        && root.flow !== null
        && root.flow !== undefined
        && root.flow.motionAllowed === true
        && root.performanceLevelSafe >= 2
    )

    clip: true

    Rectangle {
        anchors.fill: parent
        gradient: Gradient {
            GradientStop {
                position: 0.0
                color: root.dark ? "#030A12" : "#FAFDFF"
            }
            GradientStop {
                position: 0.48
                color: root.dark ? "#0A1D30" : "#EDF7FE"
            }
            GradientStop {
                position: 1.0
                color: root.dark ? "#11182A" : "#E7F2FA"
            }
        }
    }

    Rectangle {
        width: Math.max(root.width * 1.34, 500)
        height: Math.max(root.height * 0.16, 120)
        x: -width * 0.22
        y: root.height * 0.34
        rotation: -17
        opacity: root.dark ? 0.16 : 0.11

        gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop {
                position: 0.0
                color: "transparent"
            }
            GradientStop {
                position: 0.44
                color: root.accentA
            }
            GradientStop {
                position: 0.68
                color: root.accentB
            }
            GradientStop {
                position: 1.0
                color: "transparent"
            }
        }

        transform: Translate {
            id: auroraDrift
        }

        SequentialAnimation {
            running: root.premiumMotion
            loops: Animation.Infinite

            NumberAnimation {
                target: auroraDrift
                property: "x"
                from: -12
                to: 12
                duration: 5400
                easing.type: Easing.InOutSine
            }

            NumberAnimation {
                target: auroraDrift
                property: "x"
                from: 12
                to: -12
                duration: 5400
                easing.type: Easing.InOutSine
            }
        }
    }

    Rectangle {
        id: glowA
        width: Math.max(root.width * 0.90, 360)
        height: width
        radius: width / 2
        x: -width * 0.34 + (root.pointerX / Math.max(1, root.width) - 0.5) * 20
        y: -height * 0.50 + (root.pointerY / Math.max(1, root.height) - 0.5) * 12
        color: root.accentA
        opacity: root.dark ? 0.13 : 0.09
        scale: root.active ? 1.0 : 0.90

        Behavior on x {
            NumberAnimation {
                duration: root.flow ? root.flow.slowDuration : 270
            }
        }

        Behavior on y {
            NumberAnimation {
                duration: root.flow ? root.flow.slowDuration : 270
            }
        }

        Behavior on scale {
            NumberAnimation {
                duration: root.flow ? root.flow.experienceSceneDuration : 460
                easing.type: Easing.OutQuart
            }
        }

        SequentialAnimation on opacity {
            running: root.premiumMotion
            loops: Animation.Infinite

            NumberAnimation {
                from: root.dark ? 0.10 : 0.07
                to: root.dark ? 0.16 : 0.11
                duration: 2600
                easing.type: Easing.InOutSine
            }

            NumberAnimation {
                from: root.dark ? 0.16 : 0.11
                to: root.dark ? 0.10 : 0.07
                duration: 2600
                easing.type: Easing.InOutSine
            }
        }
    }

    Rectangle {
        id: glowB
        width: Math.max(root.width * 0.76, 300)
        height: width
        radius: width / 2
        x: root.width - width * 0.58 - (root.pointerX / Math.max(1, root.width) - 0.5) * 16
        y: root.height - height * 0.48 - (root.pointerY / Math.max(1, root.height) - 0.5) * 18
        color: root.accentB
        opacity: root.dark ? 0.11 : 0.075
        rotation: root.active ? 0 : -7

        Behavior on x {
            NumberAnimation {
                duration: root.flow ? root.flow.slowDuration : 270
            }
        }

        Behavior on y {
            NumberAnimation {
                duration: root.flow ? root.flow.slowDuration : 270
            }
        }

        Behavior on rotation {
            NumberAnimation {
                duration: root.flow ? root.flow.experienceSceneDuration : 460
                easing.type: Easing.OutQuart
            }
        }
    }

    Image {
        anchors.fill: parent
        source: "qrc:/raw/qml/Mobile/onboarding/assets/topographic_contours.svg"
        fillMode: Image.PreserveAspectCrop
        opacity: root.dark ? 0.30 : 0.20
        rotation: root.active ? -2 : -6
        scale: root.active ? 1.04 : 1.10
        smooth: true
        mipmap: false

        transform: Translate {
            id: contourDrift
            x: 0
        }

        Behavior on rotation {
            NumberAnimation {
                duration: root.flow ? root.flow.experienceMorphDuration : 620
                easing.type: Easing.OutQuart
            }
        }

        Behavior on scale {
            NumberAnimation {
                duration: root.flow ? root.flow.experienceMorphDuration : 620
                easing.type: Easing.OutQuart
            }
        }

        SequentialAnimation {
            running: root.premiumMotion
            loops: Animation.Infinite

            NumberAnimation {
                target: contourDrift
                property: "x"
                from: -8
                to: 8
                duration: 7600
                easing.type: Easing.InOutSine
            }

            NumberAnimation {
                target: contourDrift
                property: "x"
                from: 8
                to: -8
                duration: 7600
                easing.type: Easing.InOutSine
            }
        }
    }

    Image {
        anchors.fill: parent
        source: "qrc:/raw/qml/Mobile/onboarding/assets/film_grain.svg"
        fillMode: Image.PreserveAspectCrop
        opacity: root.dark ? 0.42 : 0.24
        smooth: true
        mipmap: false
    }

    Image {
        anchors.right: parent.right
        anchors.rightMargin: -Math.max(22, width * 0.12)
        anchors.bottom: parent.bottom
        anchors.bottomMargin: Math.max(82, root.height * 0.11)
        width: Math.min(root.width * 0.62, 320)
        height: width
        source: root.dark
                ? "qrc:/ui/v2/branding/logo_oficial_ingeplus_dark.png"
                : "qrc:/ui/v2/branding/logo_oficial_ingeplus_light.png"
        sourceClipRect: Qt.rect(297, 175, 397, 150)
        fillMode: Image.PreserveAspectFit
        opacity: root.dark ? 0.035 : 0.026
        rotation: root.active ? -7 : -12
        smooth: true
        mipmap: false

        Behavior on rotation {
            NumberAnimation {
                duration: root.flow
                          ? root.flow.motion.policy(root.flow.motion.navigationForward).duration
                          : 230
                easing.type: Easing.OutQuart
            }
        }
    }

    Repeater {
        model: root.performanceLevelSafe >= 2 ? 18 : 10

        Rectangle {
            id: particle
            required property int index

            readonly property real seedX: ((index * 83 + 17) % 101) / 101
            readonly property real seedY: ((index * 149 + 31) % 103) / 103

            width: 2 + (index % 3)
            height: width
            radius: width / 2
            color: index % 5 === 0
                   ? "#486426"
                   : (index % 3 === 0 ? "#FFFFFF" : "#8FB2D5")
            opacity: root.dark ? 0.17 : 0.10
            x: seedX * root.width
            y: seedY * root.height

            transform: Translate {
                id: particleDrift
                y: 0
            }

            SequentialAnimation {
                running: root.premiumMotion
                loops: Animation.Infinite

                NumberAnimation {
                    target: particleDrift
                    property: "y"
                    from: 0
                    to: -12 - (particle.index % 4) * 3
                    duration: 3300 + particle.index * 91
                    easing.type: Easing.InOutSine
                }

                NumberAnimation {
                    target: particleDrift
                    property: "y"
                    from: -12 - (particle.index % 4) * 3
                    to: 0
                    duration: 3300 + particle.index * 91
                    easing.type: Easing.InOutSine
                }
            }
        }
    }
}

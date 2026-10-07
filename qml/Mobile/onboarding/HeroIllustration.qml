import QtQuick 2.15

Item {
    id: root

    property url source
    property bool active: false
    property var flow
    property color accent: "#8FB2D5"
    property real heroScale: 1.0
    property string fallbackSymbol: "+"

    readonly property bool premiumMotion: Boolean(
        root.active
        && root.flow !== null
        && root.flow !== undefined
        && root.flow.motionAllowed === true
        && Number(root.flow.performanceLevel) >= 2
    )

    Rectangle {
        anchors.centerIn: parent
        width: Math.min(parent.width, parent.height) * 0.82
        height: width
        radius: width / 2
        color: root.accent
        opacity: root.active ? 0.10 : 0.0
        scale: root.active ? 1.0 : 0.68

        Behavior on opacity {
            NumberAnimation {
                duration: root.flow ? root.flow.experienceSceneDuration : 460
            }
        }

        Behavior on scale {
            NumberAnimation {
                duration: root.flow ? root.flow.experienceMorphDuration : 620
                easing.type: Easing.OutBack
            }
        }

        SequentialAnimation on scale {
            running: root.premiumMotion
            loops: Animation.Infinite

            NumberAnimation {
                from: 0.98
                to: 1.035
                duration: 2400
                easing.type: Easing.InOutSine
            }

            NumberAnimation {
                from: 1.035
                to: 0.98
                duration: 2400
                easing.type: Easing.InOutSine
            }
        }
    }

    Image {
        id: art
        anchors.centerIn: parent
        width: Math.min(parent.width, parent.height) * 0.90
        height: width
        source: root.source
        fillMode: Image.PreserveAspectFit
        smooth: true
        mipmap: false
        cache: true
        asynchronous: false
        opacity: root.active && status !== Image.Error ? 1.0 : 0.0
        scale: root.active ? root.heroScale : root.heroScale * 0.80
        rotation: root.active ? 0 : -4

        transform: Translate {
            id: artDrift
            y: 0
        }

        Behavior on opacity {
            NumberAnimation {
                duration: root.flow ? root.flow.duration(360) : 360
            }
        }

        Behavior on scale {
            NumberAnimation {
                duration: root.flow ? root.flow.experienceMorphDuration : 620
                easing.type: Easing.OutBack
            }
        }

        Behavior on rotation {
            NumberAnimation {
                duration: root.flow ? root.flow.experienceMorphDuration : 620
                easing.type: Easing.OutQuart
            }
        }

        SequentialAnimation {
            running: root.premiumMotion && art.status === Image.Ready
            loops: Animation.Infinite

            NumberAnimation {
                target: artDrift
                property: "y"
                from: -4
                to: 6
                duration: 2800
                easing.type: Easing.InOutSine
            }

            NumberAnimation {
                target: artDrift
                property: "y"
                from: 6
                to: -4
                duration: 2800
                easing.type: Easing.InOutSine
            }
        }
    }

    Rectangle {
        anchors.centerIn: parent
        width: Math.min(parent.width, parent.height) * 0.42
        height: width
        radius: width / 2
        visible: art.status === Image.Error
        color: "#1AFFFFFF"
        border.width: 2
        border.color: root.accent

        Text {
            anchors.centerIn: parent
            text: root.fallbackSymbol
            color: root.accent
            font.pixelSize: Math.round(parent.width * 0.46)
            font.bold: true
        }
    }
}

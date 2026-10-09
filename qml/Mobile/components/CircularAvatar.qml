import QtQuick 2.15
import QtQuick.Window
import QtQuick.Effects

Item {
    id: root

    property url source: ""
    property bool hasImage: String(source || "").length > 0
    property color backgroundColor: "#AEB8C4"
    property color borderColor: "#D8E7FA"
    property real borderWidth: 1
    property bool showStatus: false
    property color statusColor: "#486426"
    property real statusSize: Math.max(10, width * 0.22)
    property color fallbackColor: "#FFFFFF"
    property string fallbackText: ""
    property color fallbackTextColor: "#0654A2"
    property real fallbackTextScale: 0.34
    property real imageScale: 1.0

    implicitWidth: 48
    implicitHeight: 48

    Rectangle {
        anchors.fill: parent
        radius: Math.min(width, height) / 2
        color: root.backgroundColor
        border.color: root.borderColor
        border.width: root.borderWidth
        antialiasing: true
    }

    Item {
        id: avatarViewport
        anchors.fill: parent
        anchors.margins: Math.max(1, root.borderWidth + 1)

        Rectangle {
            id: avatarMask
            anchors.fill: parent
            radius: Math.min(width, height) / 2
            color: "white"
            antialiasing: true
        }

        ShaderEffectSource {
            id: avatarMaskSource
            anchors.fill: avatarMask
            visible: root.hasImage && avatarImage.status === Image.Ready
            sourceItem: avatarMask
            hideSource: true
            live: true
            recursive: false
        }

        Image {
            id: avatarImage
            anchors.fill: parent
            source: root.source
            fillMode: Image.PreserveAspectCrop
            horizontalAlignment: Image.AlignHCenter
            verticalAlignment: Image.AlignVCenter
            // Decode only what is shown: the profile preview may be the
            // original 12-50 MP camera file, and each avatar (cache: false)
            // decodes its own copy. With PreserveAspectCrop the reader scales
            // to cover this box, so the crop stays sharp.
            sourceSize.width: Math.ceil(Math.max(1, width) * Screen.devicePixelRatio
                                        * Math.max(1, root.imageScale))
            sourceSize.height: Math.ceil(Math.max(1, height) * Screen.devicePixelRatio
                                         * Math.max(1, root.imageScale))
            asynchronous: true
            cache: false
            smooth: true
            mipmap: true
            autoTransform: true
            visible: root.hasImage && status !== Image.Error
            scale: root.imageScale
            layer.enabled: visible && status === Image.Ready
            layer.effect: MultiEffect {
                maskEnabled: true
                maskSource: avatarMaskSource
            }
        }

        Item {
            anchors.fill: parent
            visible: !root.hasImage || avatarImage.status === Image.Error

            Text {
                anchors.centerIn: parent
                visible: root.fallbackText.length > 0
                text: root.fallbackText
                color: root.fallbackTextColor
                font.pixelSize: Math.max(12, parent.width * root.fallbackTextScale)
                font.bold: true
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
            }

            Item {
                anchors.fill: parent
                visible: root.fallbackText.length === 0

                Rectangle {
                    width: parent.width * 0.30
                    height: width
                    radius: width / 2
                    x: (parent.width - width) / 2
                    y: parent.height * 0.20
                    color: root.fallbackColor
                    antialiasing: true
                }

                Rectangle {
                    width: parent.width * 0.60
                    height: parent.height * 0.34
                    radius: height / 2
                    x: (parent.width - width) / 2
                    y: parent.height * 0.57
                    color: root.fallbackColor
                    antialiasing: true
                }
            }
        }
    }

    Rectangle {
        visible: root.showStatus
        width: root.statusSize
        height: width
        radius: width / 2
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        color: root.statusColor
        border.color: "#FFFFFF"
        border.width: Math.max(1.5, width * 0.16)
        antialiasing: true
    }
}

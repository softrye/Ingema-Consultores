import QtQuick 2.15
import QtQuick.Controls 2.15
import ".."

ExperienceScene {
    id: root
    property string languageCode: "es"
    accent: "#8FB2D5"
    secondaryAccent: "#08A5C3"

    SceneTitle {
        id: title
        width: parent.width
        eyebrow: "INGECOREFLOW"
        title: root.languageCode === "en" ? "Motion with purpose" : (root.languageCode === "qu" ? "Kuyuriy yuyaywan" : "Movimiento con propósito")
        subtitle: root.languageCode === "en" ? "Every transition guides, confirms or explains. Nothing moves without a reason." : (root.languageCode === "qu" ? "Sapa transición yanapan, sut'ichan, confirmanku." : "Cada transición orienta, confirma o explica. Nada se mueve sin una razón.")
        titleColor: root.primaryText
        subtitleColor: root.secondaryText
        accent: root.accent
        active: root.active
        flow: root.flow
    }

    HeroIllustration {
        id: hero
        anchors.top: title.bottom
        anchors.topMargin: 8
        anchors.horizontalCenter: parent.horizontalCenter
        width: Math.min(parent.width * 0.70, 300)
        height: width
        source: "qrc:/raw/qml/Mobile/onboarding/assets/motion_constellation.svg"
        active: root.active
        flow: root.flow
        accent: root.accent
    }

    Row {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 8
        spacing: 8
        Repeater {
            model: [
                {n:"60", u:"FPS", d:"Objetivo"},
                {n:"12", u:"ESC", d:"Narrativa"},
                {n:"0", u:"CORTES", d:"Continuidad"}
            ]
            Rectangle {
                required property var modelData
                required property int index
                width: (parent.width - 16) / 3
                height: 92
                radius: 20
                color: "#12FFFFFF"
                border.color: index === 1 ? "#486426" : "#3C8FB2D5"
                opacity: root.active ? 1 : 0
                scale: root.active ? 1 : 0.84
                Behavior on opacity { NumberAnimation { duration: root.flow ? root.flow.duration(360 + index * 100) : 360 } }
                Behavior on scale { NumberAnimation { duration: root.flow ? root.flow.duration(500 + index * 100) : 500; easing.type: Easing.OutBack } }
                Column {
                    anchors.centerIn: parent
                    spacing: 2
                    Row {
                        anchors.horizontalCenter: parent.horizontalCenter
                        spacing: 3
                        Text { text: modelData.n; color: root.primaryText; font.pixelSize: 24; font.bold: true }
                        Text { text: modelData.u; color: root.accent; font.pixelSize: 9; font.bold: true }
                    }
                    Text { text: modelData.d; color: root.secondaryText; font.pixelSize: 10; anchors.horizontalCenter: parent.horizontalCenter }
                }
            }
        }
    }
}

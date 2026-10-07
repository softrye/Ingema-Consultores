import QtQuick 2.15
import QtQuick.Controls 2.15
import ".."

ExperienceScene {
    id: root

    property string languageCode: "es"

    accent: "#8FB2D5"
    secondaryAccent: "#486426"

    HeroIllustration {
        id: hero
        anchors.top: parent.top
        anchors.topMargin: -6
        anchors.horizontalCenter: parent.horizontalCenter
        width: Math.min(parent.width * 0.46, 195)
        height: width
        source: "qrc:/raw/qml/Mobile/onboarding/assets/ready_constellation.svg"
        fallbackSymbol: "✓"
        active: root.active
        flow: root.flow
        accent: root.accent
    }

    Rectangle {
        id: brandPanel
        anchors.top: hero.bottom
        anchors.topMargin: -16
        anchors.horizontalCenter: parent.horizontalCenter
        width: Math.min(parent.width * 0.86, 370)
        height: 82
        radius: 22
        color: "#F4FFFFFF"
        border.width: 1
        border.color: "#48FFFFFF"
        clip: true
        opacity: root.active ? 1.0 : 0.0
        scale: root.active ? 1.0 : 0.86

        Behavior on opacity {
            NumberAnimation {
                duration: root.flow ? root.flow.duration(430) : 430
            }
        }

        Behavior on scale {
            NumberAnimation {
                duration: root.flow ? root.flow.experienceMorphDuration : 620
                easing.type: Easing.OutBack
            }
        }

        Image {
            anchors.fill: parent
            anchors.margins: 7
            source: root.dark
                    ? "qrc:/ui/v2/branding/logo_oficial_ingeplus_dark.png"
                    : "qrc:/ui/v2/branding/logo_oficial_ingeplus_light.png"
            sourceClipRect: Qt.rect(297, 175, 397, 150)
            fillMode: Image.PreserveAspectFit
            smooth: true
            mipmap: false
            cache: true
        }
    }

    Text {
        id: readyTitle
        anchors.top: brandPanel.bottom
        anchors.topMargin: 12
        width: parent.width
        text: root.languageCode === "en"
              ? "Everything is ready"
              : (root.languageCode === "qu"
                 ? "Tukuy wakichisqañam"
                 : "Todo está listo")
        color: root.primaryText
        font.pixelSize: 29
        font.bold: true
        horizontalAlignment: Text.AlignHCenter
    }

    Text {
        id: tagline
        anchors.top: readyTitle.bottom
        anchors.topMargin: 4
        width: parent.width
        text: root.languageCode === "en"
              ? "Field, management and evidence in one platform."
              : "Campo, gestión y evidencia en una sola plataforma."
        color: root.secondaryText
        font.pixelSize: 13
        horizontalAlignment: Text.AlignHCenter
        wrapMode: Text.WordWrap
    }

    Rectangle {
        id: credits
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: tagline.bottom
        anchors.topMargin: 14
        height: 150
        radius: 24
        color: "#F4FFFFFF"
        border.width: 1
        border.color: "#44FFFFFF"
        clip: true

        Column {
            anchors.fill: parent
            anchors.margins: 13
            spacing: 6

            Image {
                width: parent.width
                height: 43
                source: "qrc:/ui/ingeplus/propuesta_a/00_branding/logo_ingema/logo_ingema_full_dark.png"
                fillMode: Image.PreserveAspectFit
                smooth: true
                mipmap: false
            }

            Text {
                width: parent.width
                text: "CEO · Paola Rosas Gonzales"
                color: "#151A30"
                font.pixelSize: 13
                font.bold: true
                horizontalAlignment: Text.AlignHCenter
            }

            Text {
                width: parent.width
                text: root.languageCode === "en" ? "Development" : "Programación"
                color: "#0780C3"
                font.pixelSize: 10
                font.bold: true
                horizontalAlignment: Text.AlignHCenter
            }

            Text {
                width: parent.width
                text: "JuanPablo Ramos Rosas · Fernando Quispe Rosas"
                color: "#536176"
                font.pixelSize: 11
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.WordWrap
            }
        }
    }

    Rectangle {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: credits.bottom
        anchors.topMargin: 10
        height: 50
        radius: 18
        gradient: Gradient {
            GradientStop {
                position: 0
                color: "#0654A2"
            }
            GradientStop {
                position: 1
                color: "#08A5C3"
            }
        }

        Text {
            anchors.centerIn: parent
            text: "Impulsado por InGeCoreFlow · Premium"
            color: "white"
            font.pixelSize: 13
            font.bold: true
        }

        SequentialAnimation on scale {
            running: Boolean(
                root.active
                && root.flow !== null
                && root.flow !== undefined
                && root.flow.motionAllowed === true
            )
            loops: Animation.Infinite

            NumberAnimation {
                from: 0.99
                to: 1.015
                duration: 1500
                easing.type: Easing.InOutSine
            }

            NumberAnimation {
                from: 1.015
                to: 0.99
                duration: 1500
                easing.type: Easing.InOutSine
            }
        }
    }
}

pragma ComponentBehavior: Bound

import QtQuick 2.15
import ".."
import "../../flowcore" as CoreFlow

ExperienceScene {
    id: root

    property string languageCode: "es"

    accent: "#8FB2D5"
    secondaryAccent: "#0654A2"

    CoreFlow.FlowGlassSurface {
        id: experienceBadge
        anchors.top: parent.top
        anchors.horizontalCenter: parent.horizontalCenter
        width: badgeText.implicitWidth + 28
        height: 28
        radius: 14
        flow: root.flow
        darkMode: root.dark
        strength: 0.76
        highlightEnabled: false
        opacity: root.active ? 1.0 : 0.0

        CoreFlow.FlowText {
            id: badgeText
            anchors.centerIn: parent
            text: root.languageCode === "en"
                  ? "WELCOME · INGE+"
                  : (root.languageCode === "qu"
                     ? "ALLIN HAMUSQA · INGE+"
                     : "BIENVENIDA · INGE+")
            role: "caption"
            color: root.accent
            font.pixelSize: 9
            font.letterSpacing: 1.25
            font.weight: Font.DemiBold
        }

        Behavior on opacity {
            NumberAnimation {
                duration: root.flow
                          ? root.flow.motion.policy(root.flow.motion.enterFade).duration
                          : 180
            }
        }
    }

    Item {
        id: body
        anchors.top: experienceBadge.bottom
        anchors.topMargin: Math.max(8, parent.height * 0.018)
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: ingemaFooter.top
        anchors.bottomMargin: Math.max(8, parent.height * 0.018)

        Column {
            id: composition
            anchors.centerIn: parent
            width: parent.width
            spacing: Math.max(5, Math.min(12, parent.height * 0.018))

            CoreFlow.FlowGlassSurface {
                id: markHalo
                x: (parent.width - width) / 2
                width: Math.min(206, Math.max(158, body.height * 0.32))
                height: Math.round(width * 0.42)
                radius: 24
                flow: root.flow
                darkMode: root.dark
                strength: 1.12
                border.color: root.active ? "#6B27B9DC" : "#2FFFFFFF"
                opacity: root.active ? 1.0 : 0.0
                scale: root.active ? 1.0 : 0.84

                Rectangle {
                    anchors.centerIn: parent
                    width: parent.width - 18
                    height: parent.height - 14
                    radius: 18
                    color: "transparent"
                    border.width: 1
                    border.color: "#3527B9DC"
                    rotation: root.active ? 0 : -18

                    Behavior on rotation {
                        NumberAnimation {
                            duration: root.flow
                                      ? root.flow.motion.policy(root.flow.motion.enterScale).duration
                                      : 180
                            easing.type: Easing.OutQuart
                        }
                    }
                }

                Image {
                    anchors.centerIn: parent
                    width: parent.width * 0.92
                    height: parent.height * 0.86
                    source: root.dark
                            ? "qrc:/ui/v2/branding/logo_oficial_ingeplus_dark.png"
                            : "qrc:/ui/v2/branding/logo_oficial_ingeplus_light.png"
                    sourceClipRect: Qt.rect(297, 175, 397, 150)
                    fillMode: Image.PreserveAspectFit
                    smooth: true
                    mipmap: false
                    cache: true
                }

                Behavior on opacity {
                    NumberAnimation {
                        duration: root.flow
                                  ? root.flow.motion.policy(root.flow.motion.enterScale).duration
                                  : 180
                    }
                }

                Behavior on scale {
                    NumberAnimation {
                        duration: root.flow
                                  ? root.flow.motion.policy(root.flow.motion.enterScale).duration
                                  : 180
                        easing.type: root.flow
                                     ? root.flow.motion.policy(root.flow.motion.enterScale).easing
                                     : Easing.OutBack
                    }
                }
            }

            AnimatedGreeting {
                width: parent.width
                height: Math.min(86, Math.max(62, body.height * 0.14))
                active: root.active
                flow: root.flow
                color: root.primaryText
                words: root.languageCode === "en"
                       ? ["hello", "hola", "rimaykullayki"]
                       : (root.languageCode === "qu"
                          ? ["rimaykullayki", "hola", "welcome"]
                          : ["hola", "rimaykullayki", "welcome"])
            }

            CoreFlow.FlowText {
                width: parent.width
                text: root.languageCode === "en"
                      ? "Welcome to InGe+"
                      : (root.languageCode === "qu"
                         ? "InGe+man allin hamusqayki"
                         : "Bienvenido a InGe+")
                role: "titleLarge"
                color: root.primaryText
                font.pixelSize: Math.round(Math.min(25, Math.max(21, parent.width * 0.062)))
                font.weight: Font.DemiBold
                horizontalAlignment: Text.AlignHCenter
                opacity: root.active ? 1.0 : 0.0

                Behavior on opacity {
                    NumberAnimation {
                        duration: root.flow
                                  ? root.flow.motion.policy(root.flow.motion.enterFade).duration
                                  : 180
                    }
                }
            }

            CoreFlow.FlowText {
                width: parent.width * 0.92
                x: (parent.width - width) / 2
                text: root.languageCode === "en"
                      ? "The immersive workspace that connects field work, management and evidence."
                      : (root.languageCode === "qu"
                         ? "Campo llamk'ayta, gestiónta, evidenciata huñuq experiencia."
                         : "Una experiencia inmersiva que conecta campo, gestión y evidencia.")
                role: "body"
                color: root.secondaryText
                font.pixelSize: 13
                lineHeight: 1.22
                lineHeightMode: Text.ProportionalHeight
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.WordWrap
                opacity: root.active ? 1.0 : 0.0

                Behavior on opacity {
                    NumberAnimation {
                        duration: root.flow
                                  ? root.flow.motion.policy(root.flow.motion.enterFade).duration
                                  : 180
                    }
                }
            }

            CoreFlow.FlowGlassSurface {
                x: (parent.width - width) / 2
                width: Math.min(parent.width * 0.94, 380)
                height: 58
                radius: 20
                flow: root.flow
                darkMode: root.dark
                strength: 0.86
                opacity: root.active ? 1.0 : 0.0

                Row {
                    anchors.centerIn: parent
                    spacing: Math.max(8, parent.width * 0.028)

                    Repeater {
                        model: root.languageCode === "en"
                               ? ["FIELD", "MANAGEMENT", "EVIDENCE"]
                               : ["CAMPO", "GESTIÓN", "EVIDENCIA"]

                        Rectangle {
                            id: chip
                            required property string modelData
                            required property int index

                            width: chipLabel.implicitWidth + 16
                            height: 26
                            radius: 13
                            color: index === 1 ? "#1C496426" : "#1627B9DC"
                            border.width: 1
                            border.color: index === 1 ? "#68496426" : "#4827B9DC"

                            CoreFlow.FlowText {
                                id: chipLabel
                                anchors.centerIn: parent
                                text: chip.modelData
                                role: "caption"
                                color: root.primaryText
                                font.pixelSize: 9
                                font.letterSpacing: 0.8
                                font.weight: Font.DemiBold
                            }
                        }
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
    }

    BrandFooter {
        id: ingemaFooter
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 2
        width: Math.min(parent.width * 0.74, 310)
        height: 54
        active: root.active
        flow: root.flow
        dark: root.dark
    }
}

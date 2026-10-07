import QtQuick 2.15
import "../flowcore" as CoreFlow

Column {
    id: root

    property string eyebrow: ""
    property string title: ""
    property string subtitle: ""
    property color titleColor: "white"
    property color subtitleColor: "#C8D8E8"
    property color accent: "#8FB2D5"
    property bool active: false
    property var flow

    spacing: 7

    CoreFlow.FlowText {
        id: eyebrowLabel
        width: parent.width
        text: root.eyebrow.toUpperCase()
        visible: text.length > 0
        role: "caption"
        color: root.accent
        font.pixelSize: 11
        font.letterSpacing: 1.6
        font.weight: Font.DemiBold
        opacity: root.active ? 1.0 : 0.0

        transform: Translate {
            id: eyebrowOffset
            x: root.active ? 0 : -16
            Behavior on x {
                NumberAnimation {
                    duration: root.flow
                              ? root.flow.motion.policy(root.flow.motion.enterFade).duration
                              : 180
                    easing.type: root.flow
                                 ? root.flow.motion.policy(root.flow.motion.enterFade).easing
                                 : Easing.OutQuart
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

    CoreFlow.FlowText {
        id: titleLabel
        width: parent.width
        text: root.title
        role: "titleLarge"
        color: root.titleColor
        font.pixelSize: Math.round(Math.min(32, Math.max(25, root.width * 0.078)))
        font.weight: Font.DemiBold
        lineHeight: 1.03
        lineHeightMode: Text.ProportionalHeight
        wrapMode: Text.WordWrap
        maximumLineCount: 2
        elide: Text.ElideRight
        opacity: root.active ? 1.0 : 0.0

        transform: Translate {
            id: titleOffset
            y: root.active ? 0 : 14
            Behavior on y {
                NumberAnimation {
                    duration: root.flow
                              ? root.flow.motion.policy(root.flow.motion.navigationForward).duration
                              : 230
                    easing.type: root.flow
                                 ? root.flow.motion.policy(root.flow.motion.navigationForward).easing
                                 : Easing.OutQuart
                }
            }
        }

        Behavior on opacity {
            NumberAnimation {
                duration: root.flow
                          ? root.flow.motion.policy(root.flow.motion.enterScale).duration
                          : 180
            }
        }
    }

    CoreFlow.FlowText {
        id: subtitleLabel
        width: parent.width
        text: root.subtitle
        role: "body"
        color: root.subtitleColor
        font.pixelSize: 13
        lineHeight: 1.18
        lineHeightMode: Text.ProportionalHeight
        wrapMode: Text.WordWrap
        maximumLineCount: 3
        elide: Text.ElideRight
        opacity: root.active ? 1.0 : 0.0

        transform: Translate {
            id: subtitleOffset
            y: root.active ? 0 : 10
            Behavior on y {
                NumberAnimation {
                    duration: root.flow
                              ? root.flow.motion.policy(root.flow.motion.navigationForward).duration
                              : 230
                    easing.type: root.flow
                                 ? root.flow.motion.policy(root.flow.motion.navigationForward).easing
                                 : Easing.OutQuart
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

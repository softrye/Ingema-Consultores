import QtQuick 2.15
import "../flowcore" as CoreFlow

CoreFlow.FlowGlassSurface {
    id: root

    property bool active: false
    property bool dark: true

    radius: 18
    darkMode: false
    strength: 1.12
    border.width: 1
    border.color: root.dark ? "#48FFFFFF" : "#220654A2"
    opacity: root.active ? 1.0 : 0.0
    clip: true

    transform: Translate {
        id: footerOffset
        y: root.active ? 0 : 12

        Behavior on y {
            NumberAnimation {
                duration: root.flow ? root.flow.duration(500) : 500
                easing.type: Easing.OutQuart
            }
        }
    }

    Behavior on opacity {
        NumberAnimation {
            duration: root.flow ? root.flow.duration(400) : 400
        }
    }

    Image {
        anchors.fill: parent
        anchors.margins: 11
        source: "qrc:/ui/ingeplus/propuesta_a/00_branding/logo_ingema/logo_ingema_full_dark.png"
        fillMode: Image.PreserveAspectFit
        smooth: true
        mipmap: false
        cache: true
    }
}

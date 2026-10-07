import QtQuick 2.15
import QtQuick.Controls 2.15
import ".."

ExperienceScene {
    id: root
    property string languageCode: "es"
    property int syncStep: 0
    accent: syncStep < 2 ? "#FDAC11" : "#486426"
    secondaryAccent: "#0E5878"

    onActiveChanged: if (active) { syncStep = 0; syncTimer.restart() } else syncTimer.stop()
    Timer { id: syncTimer; interval: 1150; repeat: true; onTriggered: root.syncStep = (root.syncStep + 1) % 3 }

    SceneTitle {
        id: title
        width: parent.width
        eyebrow: "OFFLINE FIRST"
        title: root.languageCode === "en" ? "Keep working without a signal" : (root.languageCode === "qu" ? "Señal mana kaptinpas llamk'ay" : "Sigue trabajando sin señal")
        subtitle: root.languageCode === "en" ? "InGe+ saves locally and synchronizes when the connection returns." : (root.languageCode === "qu" ? "Localpi waqaychan, señal kutimuptin sincronizan." : "InGe+ guarda localmente y sincroniza cuando regresa la conexión.")
        titleColor: root.primaryText
        subtitleColor: root.secondaryText
        accent: root.accent
        active: root.active
        flow: root.flow
    }

    HeroIllustration {
        anchors.top: title.bottom
        anchors.topMargin: 8
        anchors.horizontalCenter: parent.horizontalCenter
        width: Math.min(parent.width * 0.68, 290)
        height: width
        source: "qrc:/raw/qml/Mobile/onboarding/assets/offline_sync.svg"
        active: root.active
        flow: root.flow
        accent: root.accent
    }

    Column {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 4
        spacing: 8
        Repeater {
            model: [
                {t:"Guardado local", d:"Tu trabajo permanece en el dispositivo.", c:"#0E5878", s:"1"},
                {t:"Pendiente", d:"La cola conserva cada cambio.", c:"#FDAC11", s:"2"},
                {t:"Sincronizado", d:"Campo y oficina vuelven a estar alineados.", c:"#486426", s:"✓"}
            ]
            PremiumGlassCard {
                required property var modelData
                required property int index
                width: parent.width
                height: 70
                title: modelData.t
                subtitle: modelData.d
                symbol: modelData.s
                accent: modelData.c
                selected: root.syncStep === index
                active: root.active
                revealIndex: index
                dark: root.dark
                flow: root.flow
            }
        }
    }
}

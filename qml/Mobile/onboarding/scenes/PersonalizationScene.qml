import QtQuick 2.15
import QtQuick.Controls 2.15
import ".."

ExperienceScene {
    id: root
    property string languageCode: "es"
    property int themeMode: 0
    property bool narrationEnabled: true
    signal themeSelected(int mode)
    signal narrationSelected(bool enabled)
    accent: "#0780C3"
    secondaryAccent: "#8FB2D5"

    SceneTitle {
        id: title
        width: parent.width
        eyebrow: root.languageCode === "en" ? "YOUR EXPERIENCE" : "TU EXPERIENCIA"
        title: root.languageCode === "en" ? "Make it yours" : (root.languageCode === "qu" ? "Qanpa hina ruray" : "Hazlo tuyo")
        subtitle: root.languageCode === "en" ? "A clean light appearance keeps every tool clear. Premium performance is already active." : (root.languageCode === "qu" ? "Ch'uya rikch'aywan llapa llamk'ana sut'i kachkan." : "La apariencia normal clara mantiene cada herramienta legible.")
        titleColor: root.primaryText
        subtitleColor: root.secondaryText
        accent: root.accent
        active: root.active
        flow: root.flow
    }

    HeroIllustration {
        anchors.top: title.bottom
        anchors.topMargin: 6
        anchors.horizontalCenter: parent.horizontalCenter
        width: Math.min(parent.width * 0.50, 220)
        height: width
        source: "qrc:/raw/qml/Mobile/onboarding/assets/theme_prism.svg"
        active: root.active
        flow: root.flow
        accent: root.accent
    }

    Rectangle {
        id: themes
        anchors.top: title.bottom
        anchors.topMargin: 230
        width: parent.width
        height: 76
        radius: 22
        color: "#F4F9FD"
        border.width: 2
        border.color: root.accent
        Row {
            anchors.centerIn: parent
            spacing: 10
            Rectangle { width: 38; height: 38; radius: 19; color: "#FFFFFF"; border.color: root.accent; border.width: 1 }
            Text { anchors.verticalCenter: parent.verticalCenter; text: root.languageCode === "en" ? "Normal light appearance" : "Apariencia normal clara"; color: "#151A30"; font.pixelSize: 13; font.bold: true }
        }
    }

    PremiumGlassCard {
        id: voiceCard
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: themes.bottom
        anchors.topMargin: 10
        height: 76
        title: root.languageCode === "en" ? "Guided narration" : (root.languageCode === "qu" ? "Rimay yanapay" : "Narración guiada")
        subtitle: root.narrationEnabled ? (root.languageCode === "en" ? "Voice and subtitles are active." : "Voz y subtítulos activos.") : (root.languageCode === "en" ? "Subtitles only." : "Solo subtítulos.")
        symbol: root.narrationEnabled ? "♪" : "—"
        selected: root.narrationEnabled
        accent: "#8FB2D5"
        active: root.active
        dark: root.dark
        flow: root.flow
        onClicked: root.narrationSelected(!root.narrationEnabled)
    }

    Rectangle {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: voiceCard.bottom
        anchors.topMargin: 10
        height: 62
        radius: 20
        color: "#16496426"
        border.color: "#70496426"
        Row {
            anchors.fill: parent
            anchors.margins: 12
            spacing: 12
            Rectangle { width: 38; height: 38; radius: 13; color: "#486426"; Text { anchors.centerIn: parent; text: "P"; color: "white"; font.bold: true } }
            Column {
                anchors.verticalCenter: parent.verticalCenter
                Text { text: "Premium · Equilibrado para 60 FPS"; color: root.primaryText; font.pixelSize: 13; font.bold: true }
                Text { text: "Calidad visual alta sin efectos innecesarios."; color: root.secondaryText; font.pixelSize: 11 }
            }
        }
    }
}

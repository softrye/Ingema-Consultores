import QtQuick 2.15
import QtQuick.Controls 2.15
import ".."

ExperienceScene {
    id: root
    property string languageCode: "es"
    accent: "#486426"
    secondaryAccent: "#0654A2"

    SceneTitle {
        id: title
        width: parent.width
        eyebrow: root.languageCode === "en" ? "TRUST AND CONTROL" : "CONFIANZA Y CONTROL"
        title: root.languageCode === "en" ? "Permissions with a purpose" : (root.languageCode === "qu" ? "Permiso yuyaywan" : "Permisos con propósito")
        subtitle: root.languageCode === "en" ? "Camera, location and files are requested only when needed, with a clear explanation." : (root.languageCode === "qu" ? "Cámara, ubicación, archivo necesario kaptinlla mañakun." : "Cámara, ubicación y archivos se solicitan solo cuando son necesarios y con una explicación clara.")
        titleColor: root.primaryText
        subtitleColor: root.secondaryText
        accent: root.accent
        active: root.active
        flow: root.flow
    }

    HeroIllustration {
        anchors.top: title.bottom
        anchors.topMargin: 4
        anchors.horizontalCenter: parent.horizontalCenter
        width: Math.min(parent.width * 0.52, 230)
        height: width
        source: "qrc:/raw/qml/Mobile/onboarding/assets/privacy_lock.svg"
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
                {s:"◉", t:"Cámara", d:"Evidencia fotográfica de campo."},
                {s:"⌖", t:"Ubicación", d:"Coordenadas vinculadas al proyecto."},
                {s:"▤", t:"Archivos", d:"Importar, exportar y organizar."}
            ]
            PremiumGlassCard {
                required property var modelData
                required property int index
                width: parent.width
                height: 67
                title: modelData.t
                subtitle: modelData.d
                symbol: modelData.s
                accent: index === 1 ? "#486426" : "#8FB2D5"
                selected: true
                active: root.active
                revealIndex: index
                dark: root.dark
                flow: root.flow
            }
        }
    }
}

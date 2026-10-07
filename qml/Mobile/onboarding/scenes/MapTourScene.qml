import QtQuick 2.15
import QtQuick.Controls 2.15
import ".."

ExperienceScene {
    id: root
    property string languageCode: "es"
    accent: "#8FB2D5"
    secondaryAccent: "#0E5878"

    SceneTitle {
        id: title
        width: parent.width
        eyebrow: "GPS · MAPA"
        title: root.languageCode === "en" ? "Location becomes evidence" : (root.languageCode === "qu" ? "Ubicaciónqa evidenciaman tikrakun" : "La ubicación se convierte en evidencia")
        subtitle: root.languageCode === "en" ? "Coordinates, photos and technical points remain tied to the project." : (root.languageCode === "qu" ? "Coordenada, foto, punto técnico proyectowan huñukun." : "Coordenadas, fotos y puntos técnicos permanecen vinculados al proyecto.")
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
        width: Math.min(parent.width * 0.84, 350)
        height: width
        source: "qrc:/raw/qml/Mobile/onboarding/assets/map_route.svg"
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
                {s:"⌖", t:"GPS", d:"Precisión"},
                {s:"◉", t:"Foto", d:"Evidencia"},
                {s:"▣", t:"Ficha", d:"Proyecto"}
            ]
            Rectangle {
                required property var modelData
                required property int index
                width: (parent.width - 16) / 3
                height: 78
                radius: 20
                color: "#12FFFFFF"
                border.color: index === 0 ? "#486426" : "#3C8FB2D5"
                Column {
                    anchors.centerIn: parent
                    spacing: 4
                    Text { text: modelData.s; color: index === 0 ? "#7EA25A" : root.accent; font.pixelSize: 22; font.bold: true; anchors.horizontalCenter: parent.horizontalCenter }
                    Text { text: modelData.t; color: root.primaryText; font.pixelSize: 11; font.bold: true; anchors.horizontalCenter: parent.horizontalCenter }
                    Text { text: modelData.d; color: root.secondaryText; font.pixelSize: 9; anchors.horizontalCenter: parent.horizontalCenter }
                }
            }
        }
    }
}

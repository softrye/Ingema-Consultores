import QtQuick 2.15
import QtQuick.Controls 2.15
import ".."

ExperienceScene {
    id: root
    property string languageCode: "es"
    accent: "#0780C3"
    secondaryAccent: "#486426"

    SceneTitle {
        id: title
        width: parent.width
        eyebrow: root.languageCode === "en" ? "FIELD TO OFFICE" : "CAMPO A OFICINA"
        title: root.languageCode === "en" ? "One record, many useful formats" : (root.languageCode === "qu" ? "Huk ficha, achka formato" : "Una ficha, múltiples formatos útiles")
        subtitle: root.languageCode === "en" ? "Editable Excel, PDF, organized photos and cloud-ready documents." : (root.languageCode === "qu" ? "Excel editable, PDF, foto, nube documentokuna." : "Excel editable, PDF, fotografías organizadas y documentos listos para la nube.")
        titleColor: root.primaryText
        subtitleColor: root.secondaryText
        accent: root.accent
        active: root.active
        flow: root.flow
    }

    HeroIllustration {
        id: hero
        anchors.top: title.bottom
        anchors.topMargin: 12
        anchors.horizontalCenter: parent.horizontalCenter
        width: Math.min(parent.width * 0.80, 340)
        height: width
        source: "qrc:/raw/qml/Mobile/onboarding/assets/documents_transform.svg"
        active: root.active
        flow: root.flow
        accent: root.accent
    }

    Rectangle {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 8
        height: 72
        radius: 22
        color: "#13FFFFFF"
        border.color: "#3C8FB2D5"
        Row {
            anchors.centerIn: parent
            spacing: 12
            Repeater {
                model: ["XLSX", "PDF", "IMG", "NUBE"]
                Rectangle {
                    required property string modelData
                    required property int index
                    width: 58
                    height: 34
                    radius: 12
                    color: index === 0 ? "#486426" : (index === 1 ? "#C74343" : (index === 2 ? "#0780C3" : "#0E5878"))
                    Text { anchors.centerIn: parent; text: modelData; color: "white"; font.pixelSize: 9; font.bold: true }
                }
            }
        }
    }
}

import QtQuick 2.15
import QtQuick.Controls 2.15
import ".."

ExperienceScene {
    id: root
    property string languageCode: "es"
    accent: "#8FB2D5"
    secondaryAccent: "#486426"

    SceneTitle {
        id: title
        width: parent.width
        eyebrow: root.languageCode === "en" ? "CREATE" : "CREAR"
        title: root.languageCode === "en" ? "From idea to verified record" : (root.languageCode === "qu" ? "Yuyaymanta ficha validasqaman" : "De una idea a una ficha validada")
        subtitle: root.languageCode === "en" ? "A guided flow keeps data, photos and coordinates connected." : (root.languageCode === "qu" ? "Datos, foto, coordenada huk flujo guiadowan." : "Un flujo guiado mantiene conectados datos, fotografías y coordenadas.")
        titleColor: root.primaryText
        subtitleColor: root.secondaryText
        accent: root.accent
        active: root.active
        flow: root.flow
    }

    HeroIllustration {
        anchors.top: title.bottom
        anchors.topMargin: 12
        anchors.horizontalCenter: parent.horizontalCenter
        width: Math.min(parent.width * 0.86, 360)
        height: width * 0.62
        source: "qrc:/raw/qml/Mobile/onboarding/assets/create_pipeline.svg"
        active: root.active
        flow: root.flow
        accent: root.accent
    }

    Column {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 6
        spacing: 8
        Repeater {
            model: root.languageCode === "en" ? ["New field record", "Technical data", "GPS and photography", "Validate and save"] : (root.languageCode === "qu" ? ["Ficha musuq", "Datos técnicos", "GPS, foto", "Validay, waqaychay"] : ["Nueva ficha", "Datos técnicos", "GPS y fotografía", "Validar y guardar"])
            Rectangle {
                required property string modelData
                required property int index
                width: parent.width
                height: 46
                radius: 16
                color: index === 3 ? "#21496426" : "#12FFFFFF"
                border.color: index === 3 ? "#486426" : "#308FB2D5"
                opacity: root.active ? 1 : 0
                x: root.active ? 0 : (index % 2 === 0 ? -24 : 24)
                Behavior on opacity { NumberAnimation { duration: root.flow ? root.flow.duration(300 + index * 80) : 300 } }
                Behavior on x { NumberAnimation { duration: root.flow ? root.flow.duration(430 + index * 90) : 430; easing.type: Easing.OutQuart } }
                Row {
                    anchors.fill: parent
                    anchors.margins: 10
                    spacing: 12
                    Rectangle {
                        width: 26
                        height: 26
                        radius: 9
                        color: index === 3 ? "#486426" : "#0654A2"
                        Text { anchors.centerIn: parent; text: index === 3 ? "✓" : String(index + 1); color: "white"; font.bold: true; font.pixelSize: 11 }
                    }
                    Text { text: modelData; color: root.primaryText; font.pixelSize: 13; font.bold: true; anchors.verticalCenter: parent.verticalCenter }
                }
            }
        }
    }
}

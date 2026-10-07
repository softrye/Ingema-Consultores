import QtQuick 2.15
import QtQuick.Controls 2.15
import ".."

ExperienceScene {
    id: root
    property string languageCode: "es"
    accent: "#0780C3"
    secondaryAccent: "#0654A2"

    SceneTitle {
        id: title
        width: parent.width
        eyebrow: root.languageCode === "en" ? "HOME" : "INICIO"
        title: root.languageCode === "en" ? "Your field command center" : (root.languageCode === "qu" ? "Campo llamk'aypa chawpin" : "Tu centro de trabajo")
        subtitle: root.languageCode === "en" ? "Modules, project, GPS and synchronization stay visible and within reach." : (root.languageCode === "qu" ? "Módulos, proyecto, GPS, sincronización hukllapi." : "Módulos, proyecto, GPS y sincronización permanecen visibles y al alcance.")
        titleColor: root.primaryText
        subtitleColor: root.secondaryText
        accent: root.accent
        active: root.active
        flow: root.flow
    }

    PhoneDemoFrame {
        id: phone
        anchors.top: title.bottom
        anchors.topMargin: 16
        anchors.horizontalCenter: parent.horizontalCenter
        width: Math.min(parent.width * 0.78, 310)
        height: Math.min(parent.height - title.height - 28, 430)
        active: root.active
        flow: root.flow
        title: "Hola, Fernando"
        status: "GPS ✓  Sync ✓"
        Item {
            anchors.fill: parent
            Image { anchors.centerIn: parent; width: parent.width * 0.90; height: parent.height * 0.95; source: "qrc:/raw/qml/Mobile/onboarding/assets/home_dashboard.svg"; fillMode: Image.PreserveAspectFit; opacity: 0.96 }
            Rectangle {
                id: spotlight
                width: parent.width * 0.42
                height: 84
                radius: 24
                x: 10
                y: 98
                color: "transparent"
                border.width: 3
                border.color: "#8FB2D5"
                opacity: root.active ? 1 : 0
                SequentialAnimation on scale {
                    running: Boolean(root.active && root.flow !== null && root.flow !== undefined && root.flow.motionAllowed === true)
                    loops: Animation.Infinite
                    NumberAnimation { from: 0.98; to: 1.04; duration: 950; easing.type: Easing.InOutSine }
                    NumberAnimation { from: 1.04; to: 0.98; duration: 950; easing.type: Easing.InOutSine }
                }
            }
        }
    }

    Rectangle {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 2
        width: Math.min(parent.width * 0.92, 360)
        height: 46
        radius: 16
        color: "#16FFFFFF"
        border.color: "#3C8FB2D5"
        Text { anchors.centerIn: parent; text: "Calicatas · Mapa · Documentos · Perfil"; color: root.primaryText; font.pixelSize: 11; font.bold: true }
    }
}

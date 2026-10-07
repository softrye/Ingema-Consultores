import QtQuick 2.15
import QtQuick.Controls 2.15
import ".."

ExperienceScene {
    id: root
    property string languageCode: "es"
    signal languageSelected(string code)
    accent: "#8FB2D5"
    secondaryAccent: "#486426"

    SceneTitle {
        id: title
        width: parent.width
        eyebrow: "PERSONALIZACIÓN"
        title: root.languageCode === "en" ? "Choose your language" : (root.languageCode === "qu" ? "Rimayniykita akllay" : "Elige tu idioma")
        subtitle: root.languageCode === "en" ? "Text, guidance and narration adapt instantly." : (root.languageCode === "qu" ? "Qillqa, yanapay, rimaypas chaylla tikrakun." : "Los textos, las ayudas y la narración se adaptan al instante.")
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
        width: Math.min(parent.width * 0.58, 250)
        height: width
        source: "qrc:/raw/qml/Mobile/onboarding/assets/language_orbit.svg"
        active: root.active
        flow: root.flow
        accent: root.accent
    }

    Column {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 4
        spacing: 9
        Repeater {
            model: [
                {code:"es", title:"Español", subtitle:"Idioma principal · Perú", symbol:"ES"},
                {code:"qu", title:"Quechua", subtitle:"Rimaykullayki · Perú", symbol:"QU"},
                {code:"en", title:"English", subtitle:"International", symbol:"EN"}
            ]
            PremiumGlassCard {
                required property var modelData
                required property int index
                width: parent.width
                height: 72
                title: modelData.title
                subtitle: modelData.subtitle
                symbol: modelData.symbol
                selected: root.languageCode === modelData.code
                accent: modelData.code === "qu" ? "#486426" : "#8FB2D5"
                active: root.active
                revealIndex: index
                dark: root.dark
                flow: root.flow
                onClicked: root.languageSelected(modelData.code)
            }
        }
    }
}

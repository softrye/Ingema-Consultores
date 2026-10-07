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
        eyebrow: root.languageCode === "en" ? "INGEMA COMMITMENT" : (root.languageCode === "qu" ? "INGEMA KAMACHIY" : "COMPROMISO INGEMA")
        title: root.languageCode === "en" ? "Engineering with purpose" : (root.languageCode === "qu" ? "Yachaywan, munaywan" : "Ingeniería con propósito")
        subtitle: root.languageCode === "en" ? "A digital experience grounded in technical rigor, trust and responsible innovation." : (root.languageCode === "qu" ? "Yachay, confianza, seguridad, innovaciónwan ruwasqa experiencia digital." : "Una experiencia digital basada en rigor técnico, confianza e innovación responsable.")
        titleColor: root.primaryText
        subtitleColor: root.secondaryText
        accent: root.accent
        active: root.active
        flow: root.flow
    }

    HeroIllustration {
        id: hero
        anchors.top: title.bottom
        anchors.topMargin: 6
        anchors.horizontalCenter: parent.horizontalCenter
        width: Math.min(parent.width * 0.58, 260)
        height: width
        source: "qrc:/raw/qml/Mobile/onboarding/assets/commitment_precision.svg"
        active: root.active
        flow: root.flow
        accent: root.accent
    }

    Column {
        anchors.top: hero.bottom
        anchors.topMargin: -4
        anchors.left: parent.left
        anchors.right: parent.right
        spacing: 8
        Repeater {
            model: root.languageCode === "en" ? [
                {s:"✓", t:"Technical precision", d:"Clear data, evidence and traceability.", c:"#8FB2D5"},
                {s:"◇", t:"Safe and reliable", d:"Processes designed for field and office.", c:"#486426"},
                {s:"+", t:"Useful innovation", d:"Technology that simplifies real work.", c:"#0780C3"}
            ] : (root.languageCode === "qu" ? [
                {s:"✓", t:"Yachay sut'i", d:"Datos, evidencia, trazabilidad.", c:"#8FB2D5"},
                {s:"◇", t:"Seguro, confiable", d:"Campo, oficinapa procesos.", c:"#486426"},
                {s:"+", t:"Innovación allin", d:"Llamk'ayta sasachakusqa mana kananpaq.", c:"#0780C3"}
            ] : [
                {s:"✓", t:"Precisión técnica", d:"Datos claros, evidencia y trazabilidad.", c:"#8FB2D5"},
                {s:"◇", t:"Seguro y confiable", d:"Procesos diseñados para campo y oficina.", c:"#486426"},
                {s:"+", t:"Innovación útil", d:"Tecnología que simplifica el trabajo real.", c:"#0780C3"}
            ])
            PremiumGlassCard {
                required property var modelData
                required property int index
                width: parent.width
                height: 72
                title: modelData.t
                subtitle: modelData.d
                symbol: modelData.s
                accent: modelData.c
                selected: index === 0
                active: root.active
                revealIndex: index
                dark: root.dark
                flow: root.flow
            }
        }
    }
}

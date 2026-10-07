import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15
import "."

HomePageContent {
    id: root



    // === ARM HYBRID PHONE/TABLET HELPERS ===
    readonly property real __armWidth:  width  > 0 ? width  : 420
    readonly property real __armHeight: height > 0 ? height : 820
    readonly property real __armMinSide: Math.min(__armWidth, __armHeight)
    readonly property bool __armPhone: __armMinSide < 600
    readonly property bool __armTablet: !__armPhone
    readonly property real __armScale: __armPhone
        ? Math.max(0.95, Math.min(1.16, __armMinSide / 390.0))
        : Math.max(1.05, Math.min(1.32, __armMinSide / 720.0))
    readonly property int __touchTarget: Math.round((__armPhone ? 56 : 60) * __armScale)
    readonly property int __touchPressDelay: 140
    readonly property real __flickVelocity: __armPhone ? 1600 : 2200
    function __dp(v) { return Math.round(v * __armScale) }
    function __sp(v) { return Math.max(12, Math.round(v * __armScale)) }

    function resolveUserName() {
        if (!auth || !auth.logged) return "Invitado"
        var dn = ""
        if (auth.displayName !== undefined)
            dn = (typeof auth.displayName === "function") ? auth.displayName() : auth.displayName
        dn = (dn || "").toString().trim()
        return dn.length ? dn : "Invitado"
    }

    greetingText: "Hola, " + resolveUserName()
    subGreetingText: "¿Qué ficha quieres completar?"
    showSearch: true

    // Clicks de cards
    cardCalicata.onClicked: root.requestOpenCalicata()
    cardTalud.onClicked:    root.requestOpenTalud()
    cardPE.onClicked:       root.requestOpenPE()
    cardEG.onClicked:       root.requestOpenEG()

    // Hook del buscador (si AppShell lo llama)
    function searchAccepted(text) {
        // luego conectas búsqueda global
        // console.log("Buscar:", text)
    }
}

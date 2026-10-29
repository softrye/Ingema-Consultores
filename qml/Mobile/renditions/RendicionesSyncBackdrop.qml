import QtQuick
import ".." as Mobile

// Fondo de estado de sincronización según la apariencia:
//   claro                 -> RendicionesSyncAura (auras de siempre)
//   oscuro                -> aurora del Login (AuroraField) sobre negro; su
//                            luz clara se tiñe de rojo (error/sin conexión) o
//                            de ámbar (atención), igual que las auras
//   skin Galaxias         -> RendicionesSyncStars (universo; en claro, fondo blanco grisáceo)
// Mismos estados para los tres: synced | pending | syncing | attention | error | offline | unknown.
Item {
    id: backdrop
    property string mode: "unknown"
    property bool running: true
    property bool reducedMotion: false
    property bool lowCost: false
    property bool dark: false
    property string skin: "none"
    property string auraObjectName: ""
    enabled: false

    readonly property bool galaxy: skin === "galaxias"
    readonly property bool error: mode === "error" || mode === "offline"

    RendicionesSyncAura {
        objectName: backdrop.auraObjectName
        anchors.fill: parent
        visible: !backdrop.dark && !backdrop.galaxy
        mode: backdrop.mode
        running: backdrop.running && !backdrop.dark && !backdrop.galaxy
        reducedMotion: backdrop.reducedMotion
        lowCost: backdrop.lowCost
    }
    RendicionesSyncStars {
        anchors.fill: parent
        visible: backdrop.galaxy
        light: !backdrop.dark
        mode: backdrop.mode
        running: backdrop.running && backdrop.galaxy
        reducedMotion: backdrop.reducedMotion
        lowCost: backdrop.lowCost
    }
    Mobile.AuroraField {
        anchors.fill: parent
        visible: backdrop.dark && !backdrop.galaxy
        mode: 0
        motion: backdrop.running && visible && !backdrop.reducedMotion
        lowPower: backdrop.lowCost
        baseColor: "#0A0A0A"
        deepColor: "#101A2E"
        primaryColor: "#8AB8FF"
        accentColor: "#8DB85A"
        tintColor: backdrop.error ? "#D9483B" : "#F2B21B"
        tintAmount: backdrop.error || backdrop.mode === "attention" ? 0.85 : 0
        Behavior on tintAmount { NumberAnimation { duration: 600; easing.type: Easing.InOutSine } }
    }
}

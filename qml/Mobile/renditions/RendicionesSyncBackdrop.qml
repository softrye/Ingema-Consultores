import QtQuick
import ".." as Mobile
import "../halloween" as Halloween

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
    property var halloweenController: null
    property string auraObjectName: ""
    enabled: false

    readonly property bool galaxy: skin === "galaxias"
    readonly property bool corporate: skin === "ingema"
    readonly property bool halloween: skin === "halloween"
    readonly property bool error: mode === "error" || mode === "offline"

    Rectangle {
        objectName: "ingemaBackground"
        anchors.fill: parent
        visible: backdrop.corporate
        color: backdrop.dark ? "#06111F" : "#F1F5FA"
    }
    RendicionesSyncAura {
        objectName: backdrop.auraObjectName
        anchors.fill: parent
        visible: !backdrop.dark && !backdrop.galaxy && !backdrop.corporate && !backdrop.halloween
        mode: backdrop.mode
        running: backdrop.running && visible
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
        objectName: "backdropAurora"
        anchors.fill: parent
        visible: backdrop.corporate || backdrop.dark && !backdrop.galaxy && !backdrop.halloween
        opacity: backdrop.corporate && !backdrop.dark ? 0.18 : 1
        mode: 0
        motion: backdrop.running && visible && !backdrop.reducedMotion
        lowPower: backdrop.lowCost
        baseColor: backdrop.corporate ? "#06111F" : "#0A0A0A"
        deepColor: backdrop.corporate ? "#071A33" : "#101A2E"
        primaryColor: backdrop.corporate ? "#0654A2" : "#8AB8FF"
        accentColor: backdrop.corporate ? "#486426" : "#8DB85A"
        tintColor: backdrop.error ? "#D9483B" : "#F2B21B"
        tintAmount: backdrop.error || backdrop.mode === "attention" ? 0.85 : 0
        Behavior on tintAmount { NumberAnimation { duration: 600; easing.type: Easing.InOutSine } }
    }
    Image {
        anchors.right: parent.right; anchors.bottom: parent.bottom
        anchors.margins: 24
        width: Math.min(parent.width * 0.58, 300)
        height: Math.min(parent.height * 0.12, 90)
        visible: backdrop.corporate
        source: backdrop.corporate ? (backdrop.dark ? "qrc:/images/INGEMA_CONSULTORES_LOGO_NEGATIVO.png" : "qrc:/images/INGEMA_CONSULTORES_LOGO.png") : ""
        fillMode: Image.PreserveAspectFit
        opacity: backdrop.dark ? 0.12 : 0.06
        smooth: true
    }

    // ---- Skin Halloween (tierno): noche morada, luna calabaza y adornos flotando.
    Item {
        id: spooky
        anchors.fill: parent
        visible: backdrop.halloween
        Rectangle {
            anchors.fill: parent
            gradient: Gradient {
                GradientStop { position: 0.0; color: backdrop.dark ? "#2B1047" : "#FFF3E6" }
                GradientStop { position: 0.55; color: backdrop.dark ? "#170A28" : "#FBF1FF" }
                GradientStop { position: 1.0; color: backdrop.dark ? "#0C0614" : "#F1E6FA" }
            }
        }
        Loader {
            anchors.fill: parent
            active: backdrop.halloween
            sourceComponent: Component {
                Halloween.HalloweenLayer {
                    controller: backdrop.halloweenController
                    running: backdrop.running && !backdrop.reducedMotion
                }
            }
        }
        Rectangle {                                    // estados: rojo (error) / ámbar (atención)
            anchors.fill: parent
            color: backdrop.error ? "#D9483B" : "#F2B21B"
            opacity: backdrop.error || backdrop.mode === "attention" ? 0.16 : 0
            Behavior on opacity { NumberAnimation { duration: 600 } }
        }
    }
}

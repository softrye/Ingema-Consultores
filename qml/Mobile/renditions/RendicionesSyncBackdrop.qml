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
        readonly property bool moving: backdrop.running && visible && !backdrop.reducedMotion
        Rectangle {
            anchors.fill: parent
            gradient: Gradient {
                GradientStop { position: 0.0; color: "#2B1047" }
                GradientStop { position: 0.55; color: "#170A28" }
                GradientStop { position: 1.0; color: "#0C0614" }
            }
        }
        Rectangle {                                    // halo de la luna
            width: Math.min(parent.width, parent.height) * 0.62; height: width; radius: width / 2
            x: parent.width - width * 0.72; y: -height * 0.22
            color: "#FF9A3C"; opacity: 0.16
        }
        Rectangle {                                    // luna
            width: Math.min(parent.width, parent.height) * 0.30; height: width; radius: width / 2
            x: parent.width - width * 1.12; y: width * 0.30
            gradient: Gradient {
                GradientStop { position: 0.0; color: "#FFD27A" }
                GradientStop { position: 1.0; color: "#FF9A3C" }
            }
            opacity: 0.92
        }
        Repeater {
            model: [ { t: "🎃", x: 0.10, y: 0.80, s: 0.13 }, { t: "👻", x: 0.70, y: 0.55, s: 0.11 },
                     { t: "🦇", x: 0.20, y: 0.18, s: 0.08 }, { t: "🦇", x: 0.48, y: 0.10, s: 0.06 },
                     { t: "🍬", x: 0.82, y: 0.86, s: 0.07 }, { t: "👻", x: 0.06, y: 0.42, s: 0.08 },
                     { t: "🎃", x: 0.58, y: 0.90, s: 0.09 }, { t: "🕸", x: 0.84, y: 0.30, s: 0.09 },
                     { t: "⭐", x: 0.34, y: 0.34, s: 0.04 }, { t: "⭐", x: 0.90, y: 0.66, s: 0.035 } ]
            delegate: Text {
                id: deco
                required property var modelData
                required property int index
                text: modelData.t
                font.pixelSize: Math.max(18, spooky.width * modelData.s)
                x: spooky.width * modelData.x
                y: spooky.height * modelData.y - height / 2 + drift
                opacity: 0.62
                property real drift: 0
                SequentialAnimation on drift {
                    running: spooky.moving; loops: Animation.Infinite
                    NumberAnimation { to: -10 - deco.index % 3 * 4; duration: 2600 + deco.index * 310; easing.type: Easing.InOutSine }
                    NumberAnimation { to: 0; duration: 2600 + deco.index * 310; easing.type: Easing.InOutSine }
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

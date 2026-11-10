import QtQuick

// Versión del modo oscuro de RendicionesSyncAura: cielo estrellado con dos
// meteoros. Misma API y mismo significado de estados que las auras:
//   meteoro A = luz principal (azul claro; en error, azul marino claro)
//   meteoro B = estado (verde synced · rojo error/offline · ámbar attention ·
//               gris pizarra unknown/pending/syncing)
// Una parte de las estrellas toma el color del estado. Coste: estrellas
// estáticas en tres capas que titilan por capa (3 animaciones) y dos meteoros.
// Error/offline: aparece un agujero negro que arrastra el universo.
// Atención (amarillo): «guerra de meteoros» cruzándose en ambos sentidos.
// Movimiento reducido o app en segundo plano: cielo quieto, sin meteoros.
Item {
    id: sky
    property string mode: "unknown"           // unknown | syncing | pending | synced | attention | error | offline
    property bool running: true
    property bool reducedMotion: false
    property bool lowCost: false
    property bool light: false                // versión clara: fondo blanco grisáceo y estrellas oscuras
    enabled: false

    readonly property bool animate: running && visible && !reducedMotion
                                    && Qt.application.state === Qt.ApplicationActive
    readonly property bool error: mode === "error" || mode === "offline"
    readonly property bool synced: mode === "synced"
    readonly property bool attention: mode === "attention"
    // Paleta Ingema invertida (tonos claros para fondo negro).
    readonly property color primaryTint: light ? (error ? "#1C2D50" : "#0654A2") : (error ? "#7C93C8" : "#8AB8FF")
    readonly property color secondaryTint: light ? (error ? "#C62F3E" : attention ? "#C98A06" : synced ? "#486426" : "#7A8299")
                                                 : (error ? "#FF6B78" : attention ? "#FFD45C" : synced ? "#A8CF7F" : "#AFC0DA")
    readonly property color starCore: light ? "#1C2D50" : "white"

    function rnd(i, k) { var v = Math.sin(i * 127.1 + k * 311.7) * 43758.5453; return v - Math.floor(v) }

    // Universo de fondo (imagen generada: estrellas densas + Vía Láctea), un poco
    // más grande que la pantalla y desplazándose muy lento: «cámara flotando».
    Image {
        id: space
        source: sky.light ? "../assets/space/space_bg_light.webp" : "../assets/space/space_bg.webp"
        width: sky.width * 1.12; height: sky.height * 1.12
        fillMode: Image.PreserveAspectCrop
        asynchronous: true; smooth: true
        property real drift: 0
        x: -sky.width * 0.06 + Math.sin(drift) * sky.width * 0.04
        y: -sky.height * 0.06 + Math.cos(drift * 0.8) * sky.height * 0.03
        NumberAnimation on drift { from: 0; to: Math.PI * 2; duration: 90000; loops: Animation.Infinite; running: sky.animate }
        // En error el espacio es arrastrado hacia el agujero negro.
        scale: sky.error ? 1.18 : 1
        Behavior on scale { NumberAnimation { duration: 2200; easing.type: Easing.InOutCubic } }
        RotationAnimation on rotation { from: 0; to: 360; duration: 60000; loops: Animation.Infinite; running: sky.animate && sky.error }
    }
    // Galaxia espiral que gira despacio (abajo a la derecha).
    Image {
        source: sky.light ? "../assets/space/galaxy_light.webp" : "../assets/space/galaxy.webp"
        width: Math.min(sky.width, sky.height) * 0.42; height: width
        x: sky.width - width * 0.85; y: sky.height - height * 0.95
        opacity: 0.85; asynchronous: true; smooth: true
        RotationAnimation on rotation { from: 0; to: -360; duration: 240000; loops: Animation.Infinite; running: sky.animate }
    }

    // Estrellas con destello en cruz que titilan (una parte toma el color del estado).
    Repeater {
        model: sky.lowCost ? 9 : 15
        delegate: Item {
            id: flare
            required property int index
            readonly property int n: 700 + index
            readonly property color tint: sky.rnd(n, 3) < 0.35 ? sky.secondaryTint : (sky.rnd(n, 6) < 0.5 ? sky.primaryTint : (sky.light ? "#C98A06" : "#FFE3B0"))
            readonly property real size: 10 + sky.rnd(n, 4) * 16
            x: sky.rnd(n, 1) * sky.width - size / 2; y: sky.rnd(n, 2) * sky.height - size / 2
            width: size; height: size
            opacity: 0.9
            SequentialAnimation on opacity {
                running: sky.animate; loops: Animation.Infinite
                PauseAnimation { duration: sky.rnd(flare.n, 7) * 2000 }
                NumberAnimation { to: 0.25; duration: 1400 + sky.rnd(flare.n, 8) * 1600; easing.type: Easing.InOutSine }
                NumberAnimation { to: 1; duration: 1400 + sky.rnd(flare.n, 8) * 1600; easing.type: Easing.InOutSine }
            }
            Rectangle { anchors.centerIn: parent; width: parent.width; height: 1.4; radius: 1
                        gradient: Gradient { orientation: Gradient.Horizontal
                            GradientStop { position: 0.0; color: Qt.rgba(flare.tint.r, flare.tint.g, flare.tint.b, 0) }
                            GradientStop { position: 0.5; color: flare.tint }
                            GradientStop { position: 1.0; color: Qt.rgba(flare.tint.r, flare.tint.g, flare.tint.b, 0) } } }
            Rectangle { anchors.centerIn: parent; width: 1.4; height: parent.height; radius: 1
                        gradient: Gradient {
                            GradientStop { position: 0.0; color: Qt.rgba(flare.tint.r, flare.tint.g, flare.tint.b, 0) }
                            GradientStop { position: 0.5; color: flare.tint }
                            GradientStop { position: 1.0; color: Qt.rgba(flare.tint.r, flare.tint.g, flare.tint.b, 0) } } }
            Rectangle { anchors.centerIn: parent; width: flare.size * 0.45; height: width; radius: width / 2; opacity: 0.22; color: flare.tint }
            Rectangle { anchors.centerIn: parent; width: 3.4; height: 3.4; radius: 1.7; color: sky.starCore }
        }
    }

    // Meteoro: cabeza brillante + estela; cruza en diagonal y espera.
    component Meteor: Item {
        id: meteor
        property color tint: "white"
        property real lane: 0.2                // fila de salida (fracción del alto)
        property int delay: 0
        property bool fromLeft: false          // sale por la izquierda (guerra de meteoros)
        property int flight: sky.error ? 1100 : 1500
        property int rest: (sky.error ? 3200 : 5200) * (sky.lowCost ? 1.4 : 1)
        property real progress: 0
        readonly property real travel: Math.hypot(sky.width, sky.height) * 0.75
        width: 140; height: 3
        transformOrigin: Item.Right
        rotation: fromLeft ? 32 : 148          // diagonal hacia abajo, en un sentido u otro
        x: fromLeft ? sky.width * 0.05 - width + progress * travel * 0.85
                    : sky.width * 0.95 - width - progress * travel * 0.85
        y: sky.height * lane + progress * travel * 0.53
        opacity: progress <= 0 || progress >= 1 ? 0 : Math.min(1, progress * 6, (1 - progress) * 4)
        visible: sky.animate
        Rectangle {                            // estela
            anchors.fill: parent; radius: height / 2
            gradient: Gradient { orientation: Gradient.Horizontal
                GradientStop { position: 0.0; color: Qt.rgba(meteor.tint.r, meteor.tint.g, meteor.tint.b, 0) }
                GradientStop { position: 1.0; color: meteor.tint } }
        }
        Rectangle {                            // cabeza
            anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
            width: 6; height: 6; radius: 3; color: sky.starCore
            border.width: 1; border.color: meteor.tint
        }
        SequentialAnimation on progress {
            running: sky.animate; loops: Animation.Infinite
            PauseAnimation { duration: meteor.delay }
            NumberAnimation { from: 0; to: 1; duration: meteor.flight; easing.type: Easing.InQuad }
            PauseAnimation { duration: meteor.rest }
        }
    }

    // ---------------------------------------------------- Error: agujero negro
    Item {
        id: blackHole
        readonly property real d: Math.min(sky.width, sky.height) * 0.30
        width: d * 3; height: d * 3
        x: (sky.width - width) / 2; y: sky.height * 0.42 - height / 2
        opacity: sky.error ? 1 : 0
        visible: opacity > 0.01
        scale: sky.error ? 1 : 0.6
        Behavior on opacity { NumberAnimation { duration: 1200; easing.type: Easing.InOutCubic } }
        Behavior on scale { NumberAnimation { duration: 1600; easing.type: Easing.OutCubic } }
        Rectangle {                                   // resplandor rojizo de fondo
            anchors.centerIn: parent; width: blackHole.d * 2.6; height: width; radius: width / 2
            color: Qt.rgba(1, 0.32, 0.30, 0.10)
        }
        Image {                                       // disco de acreción (inclinado, girando)
            anchors.centerIn: parent; width: blackHole.d * 2.4; height: width
            source: "../assets/space/accretion.webp"; asynchronous: true; smooth: true
            transform: Scale { origin.x: blackHole.d * 1.2; origin.y: blackHole.d * 1.2; yScale: 0.38 }
            RotationAnimation on rotation { from: 0; to: 360; duration: 7000; loops: Animation.Infinite; running: sky.animate && sky.error }
        }
        Image {                                       // anillo de fotones (vertical, lento)
            anchors.centerIn: parent; width: blackHole.d * 1.35; height: width; opacity: 0.85
            source: "../assets/space/accretion.webp"; asynchronous: true; smooth: true
            RotationAnimation on rotation { from: 360; to: 0; duration: 12000; loops: Animation.Infinite; running: sky.animate && sky.error }
        }
        Rectangle {                                   // horizonte de sucesos
            anchors.centerIn: parent; width: blackHole.d * 0.62; height: width; radius: width / 2
            color: "#000000"; border.width: 2; border.color: Qt.rgba(1, 0.78, 0.55, 0.9)
            SequentialAnimation on scale {
                running: sky.animate && sky.error; loops: Animation.Infinite
                NumberAnimation { to: 1.05; duration: 1600; easing.type: Easing.InOutSine }
                NumberAnimation { to: 1.0; duration: 1600; easing.type: Easing.InOutSine }
            }
        }
    }

    // ------------------------------------------ Atención: guerra de meteoros
    Repeater {
        model: sky.attention && sky.animate ? (sky.lowCost ? 6 : 10) : 0
        delegate: Meteor {
            required property int index
            tint: index % 3 === 0 ? sky.starCore : sky.secondaryTint
            fromLeft: index % 2 === 0
            lane: 0.02 + sky.rnd(900 + index, 1) * 0.6
            delay: Math.round(sky.rnd(900 + index, 2) * 1800)
            flight: 800 + Math.round(sky.rnd(900 + index, 3) * 500)
            rest: 400 + Math.round(sky.rnd(900 + index, 4) * 1400)
        }
    }
    Meteor { tint: sky.primaryTint; lane: 0.08; delay: 600 }
    Meteor { tint: sky.secondaryTint; lane: 0.30; delay: 3400 }
}

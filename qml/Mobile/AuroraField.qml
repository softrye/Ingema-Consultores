import QtQuick

// Aurora animada del acceso (Login V1, 2026-10-12): un único ShaderEffect en
// GPU (shaders/aurora.frag). El tiempo avanza con una animación nativa; sin
// temporizadores ni imágenes generadas en CPU. Se detiene si la app no está
// activa o si el sistema pide reducir el movimiento. Resolución completa:
// la capa a media resolución cortaba la aurora al cambiar el tamaño de la
// ventana (teclado) y generaba bandas.
Item {
    id: aurora

    property int mode: 0                 // 0 = Login, 1 = Welcome
    property bool motion: true           // false = cuadro estático
    property bool lowPower: false
    property real boost: 0               // 0..1 inundación verde (Continue)
    property real tintAmount: 0          // 0..1 tinte de error
    property real glowGain: 1.0
    property color baseColor: "#151A30"
    property color deepColor: "#1C2D50"
    property color primaryColor: "#0654A2"
    property color accentColor: "#486426"
    property color tintColor: "#D9483B"
    property real time

    readonly property bool running: motion && visible
                                    && Qt.application.state === Qt.ApplicationActive

    NumberAnimation on time {
        from: 12.0
        to: 100012.0
        duration: 100000000      // segundos de aurora; nunca da la vuelta
        loops: Animation.Infinite
        running: aurora.running
        paused: false
    }

    Item {
        id: surface
        anchors.fill: parent

        ShaderEffect {
            anchors.fill: parent
            property real time: aurora.time
            property real aspect: height > 0 ? width / height : 0.5
            property real mode: aurora.mode
            property real boost: aurora.boost
            property real tintAmount: aurora.tintAmount
            property real glowGain: aurora.glowGain
            property color baseColor: aurora.baseColor
            property color deepColor: aurora.deepColor
            property color primaryColor: aurora.primaryColor
            property color accentColor: aurora.accentColor
            property color tintColor: aurora.tintColor
            fragmentShader: "qrc:/InGe/Mobile/shaders/aurora.frag.qsb"
        }
    }
}

import QtQuick

// Indicador propio de InGe+ (tres puntos que suben en secuencia).
// Implementación nativa independiente: no porta ni copia constantes de
// recursos sin licencia identificada. Solo YAnimator (render thread).
// Ciclo de cada punto (periodo común 1050 ms): sube 300 ms, baja 300 ms,
// reposa 450 ms; cada punto arranca 150 ms después del anterior.
Item {
    id: root

    property bool running: true
    property color color: "#0654A2" // INGEMA Blue (por defecto; el llamador pasa su token)
    property real ballSize: 8
    property real spacing: 6
    property real travel: 4
    property bool reduceMotion: false

    implicitWidth: ballSize * 3 + spacing * 2
    implicitHeight: ballSize + travel
    visible: running
    readonly property bool animating: running && visible && !reduceMotion
    readonly property real restY: travel

    Repeater {
        model: 3
        Rectangle {
            id: dot
            required property int index
            width: root.ballSize
            height: root.ballSize
            radius: width / 2
            color: root.color
            x: index * (root.ballSize + root.spacing)
            y: root.restY
            opacity: 0.9

            SequentialAnimation {
                running: root.animating
                onRunningChanged: if (!running) dot.y = root.restY
                PauseAnimation { duration: dot.index * 150 }
                SequentialAnimation {
                    loops: Animation.Infinite
                    YAnimator { target: dot; from: root.restY; to: 0; duration: 300; easing.type: Easing.OutSine }
                    YAnimator { target: dot; from: 0; to: root.restY; duration: 300; easing.type: Easing.InSine }
                    PauseAnimation { duration: 450 }
                }
            }
        }
    }
}

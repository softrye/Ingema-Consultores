import QtQuick
import "RStyle.js" as S

// Confeti breve de "Gasto registrado" (sólo con confirmación REAL del servidor).
// Una única reproducción (~1.5 s), 26 piezas planas con colores corporativos;
// por cuadro sólo cambian posición, rotación y opacidad (sin partículas, blur
// ni shaders: apto para gama baja). No recibe toques ni bloquea la navegación.
// Con movimiento reducido no se reproduce.
Item {
    id: confetti
    property var ui
    property bool reducedMotion: false
    readonly property bool running: burst.running
    enabled: false
    clip: false

    readonly property var palette: [S.corporateBlue, S.corporateGreen, S.warning, S.accentSoft, S.navy]
    property var pieces: []

    function play() {
        if (reducedMotion || burst.running) return
        var list = []
        for (var i = 0; i < 26; ++i) {
            var angle = (-150 + Math.random() * 120) * Math.PI / 180      // abanico hacia arriba
            var speed = (0.55 + Math.random() * 0.45) * Math.max(width, height) * 0.55
            list.push({ dx: Math.cos(angle) * speed, dy: Math.sin(angle) * speed,
                        spin: (Math.random() < 0.5 ? -1 : 1) * (240 + Math.random() * 360),
                        color: palette[i % palette.length], w: (6 + Math.random() * 5) * ui.u,
                        h: (9 + Math.random() * 6) * ui.u, round: Math.random() < 0.3 })
        }
        pieces = list
        progress = 0
        burst.restart()
    }

    property real progress: 0
    NumberAnimation on progress {
        id: burst
        running: false
        from: 0; to: 1
        duration: 1500
        easing.type: Easing.Linear
        onFinished: confetti.pieces = []
    }

    Repeater {
        model: confetti.pieces
        delegate: Rectangle {
            required property var modelData
            readonly property real t: confetti.progress
            width: modelData.w
            height: modelData.round ? modelData.w : modelData.h
            radius: modelData.round ? width / 2 : 1.5 * confetti.ui.u
            color: modelData.color
            // Salida balística suave + gravedad; desvanecido en el último tercio.
            x: confetti.width / 2 + modelData.dx * t - width / 2
            y: confetti.height * 0.42 + modelData.dy * t + confetti.height * 0.9 * t * t - height / 2
            rotation: modelData.spin * t
            opacity: t < 0.66 ? 1 : Math.max(0, 1 - (t - 0.66) / 0.34)
        }
    }
}

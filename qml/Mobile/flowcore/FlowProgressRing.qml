import QtQuick

// Port de FluentUI · FluProgressRing (modo indeterminado).
// Origen: C:\Users\PC-02\Documents\calicatas\FluentUI-main.zip →
//   FluentUI-main/src/Qt6/imports/FluentUI/Controls/FluProgressRing.qml
// Licencia: MIT, Copyright (c) 2023 zhuzichu (FluentUI-main/License).
//
// Conserva del original: pista circular con borde `strokeWidth`, arco con
// lineCap "round", radio = width/2 − strokeWidth/2, duración 2000 ms y las
// dos secuencias lineales:
//   startAngle 0 → 450 (duration/2) → 1080 (duration/2)
//   sweepAngle 0 → 180 (duration/2) → 0   (duration/2)
//   arco = [startAngle − 90°, startAngle − 90° + sweepAngle]
// Adaptación sin cambio visual: rotar el Canvas `startAngle` grados equivale
// a desplazar el arco; ese giro va en RotationAnimator (render thread) para
// que el anillo no se congele durante trabajo síncrono. Sin FluTheme/FluText.
Item {
    id: control

    property bool running: true
    property int duration: 2000
    property real strokeWidth: 6
    property color color: "#0654A2" // INGEMA Blue (por defecto; el llamador pasa su token)
    property color backgroundColor: Qt.rgba(214 / 255, 214 / 255, 214 / 255, 1)

    implicitWidth: 56
    implicitHeight: 56
    visible: running

    readonly property real _radius: width / 2 - strokeWidth / 2
    property real _sweepAngle: 0

    // background del original
    Rectangle {
        anchors.fill: parent
        radius: width / 2
        color: "transparent"
        border.color: control.backgroundColor
        border.width: control.strokeWidth
    }

    Canvas {
        id: canvas
        anchors.fill: parent
        antialiasing: true
        renderTarget: Canvas.Image
        onPaint: {
            var ctx = canvas.getContext("2d")
            ctx.clearRect(0, 0, canvas.width, canvas.height)
            ctx.save()
            ctx.lineWidth = control.strokeWidth
            ctx.strokeStyle = control.color
            ctx.lineCap = "round"
            ctx.beginPath()
            ctx.arc(width / 2, height / 2, control._radius,
                    Math.PI * (-90) / 180,
                    Math.PI * (-90 + control._sweepAngle) / 180)
            ctx.stroke()
            ctx.closePath()
            ctx.restore()
        }

        // startAngle del original → rotación del Canvas (render thread).
        SequentialAnimation {
            loops: Animation.Infinite
            running: control.running && control.visible
            RotationAnimator { target: canvas; from: 0; to: 450; duration: control.duration / 2 }
            RotationAnimator { target: canvas; from: 450; to: 1080; duration: control.duration / 2 }
        }
    }

    SequentialAnimation on _sweepAngle {
        loops: Animation.Infinite
        running: control.running && control.visible
        PropertyAnimation { from: 0; to: 180; duration: control.duration / 2 }
        PropertyAnimation { from: 180; to: 0; duration: control.duration / 2 }
    }
    on_SweepAngleChanged: canvas.requestPaint()
    onColorChanged: canvas.requestPaint()
}

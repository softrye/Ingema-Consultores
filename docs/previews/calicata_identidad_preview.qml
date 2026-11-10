import QtQuick
import QtQuick.Window

// Maqueta «Ficha de calicata · General» con el lenguaje de la referencia Workouts
// (identidad_ref_workouts.png): fondo plano, widgets de vidrio grafito, tipografía
// grande blanco/gris, anillos finos, lima #B8E986 solo en detalles. Solo preview.
// Datos: los de la ficha real de la captura (68.png); lo que no existe se muestra «—».
Window {
    id: win
    width: 2 * 412 + 3 * 28
    height: 900
    visible: true
    color: "#111111"
    readonly property string outPath: "C:/Users/PC-02/Documents/InGePlus/AppCalicatasDemo/docs/previews/calicata_identidad_preview.png"
    readonly property string font: "Segoe UI"

    // Widget de vidrio grafito (oscuro) / vidrio claro (blanco y grises).
    component Widget: Item {
        id: w
        readonly property Item ph: { var q = parent; while (q && !q.isPhone) q = q.parent; return q }
        property real radius: 30
        property string corner: ""                 // "touch" (3D Touch) solo donde existe
        Rectangle {                                 // sombra suave (solo claro)
            anchors.fill: parent; anchors.topMargin: 3; radius: w.radius
            color: w.ph && !w.ph.dark ? Qt.rgba(0, 0, 0, 0.06) : "transparent"
        }
        Rectangle {
            anchors.fill: parent; radius: w.radius
            gradient: Gradient {
                GradientStop { position: 0; color: w.ph && w.ph.dark ? "#2A2A2C" : "#FFFFFF" }
                GradientStop { position: 1; color: w.ph && w.ph.dark ? "#1E1E20" : "#F6F6F8" }
            }
            border.width: 1
            border.color: w.ph && w.ph.dark ? Qt.rgba(1, 1, 1, 0.10) : Qt.rgba(0, 0, 0, 0.07)
        }
        Rectangle {                                 // filo especular superior
            x: w.radius; width: parent.width - w.radius * 2; height: 1; y: 1
            color: w.ph && w.ph.dark ? Qt.rgba(1, 1, 1, 0.22) : Qt.rgba(1, 1, 1, 1)
        }
        Glyph { visible: w.corner.length > 0; kind: w.corner; size: 26
                anchors.right: parent.right; anchors.rightMargin: 18; y: 18 }
    }

    // Íconos lineales finos (mismo trazo que la referencia).
    component Glyph: Canvas {
        id: gl
        readonly property Item ph: { var q = parent; while (q && !q.isPhone) q = q.parent; return q }
        property string kind: "sliders"
        property real size: 24
        property color tone: ph ? ph.soft : "gray"
        width: size; height: size
        onToneChanged: requestPaint()
        onPaint: {
            var c = getContext("2d"), s = width; c.reset(); c.strokeStyle = gl.tone; c.lineWidth = 1.7; c.lineCap = "round"; c.lineJoin = "round"
            c.beginPath()
            if (kind === "sliders") {
                c.moveTo(s * .32, s * .08); c.lineTo(s * .32, s * .46); c.moveTo(s * .32, s * .74); c.lineTo(s * .32, s * .92)
                c.moveTo(s * .68, s * .08); c.lineTo(s * .68, s * .22); c.moveTo(s * .68, s * .50); c.lineTo(s * .68, s * .92)
                c.stroke(); c.beginPath(); c.arc(s * .32, s * .60, s * .13, 0, Math.PI * 2); c.stroke()
                c.beginPath(); c.arc(s * .68, s * .36, s * .13, 0, Math.PI * 2)
            } else if (kind === "touch") {                       // 3D Touch: pulsación con ondas
                c.arc(s / 2, s / 2, s * .14, 0, Math.PI * 2); c.stroke(); c.beginPath()
                c.arc(s / 2, s / 2, s * .30, -Math.PI * .8, -Math.PI * .2); c.stroke(); c.beginPath()
                c.arc(s / 2, s / 2, s * .30, Math.PI * .2, Math.PI * .8); c.stroke(); c.beginPath()
                c.arc(s / 2, s / 2, s * .46, -Math.PI * .75, -Math.PI * .25); c.stroke(); c.beginPath()
                c.arc(s / 2, s / 2, s * .46, Math.PI * .25, Math.PI * .75)
            } else if (kind === "doc") {
                c.moveTo(s * .22, s * .06); c.lineTo(s * .60, s * .06); c.lineTo(s * .80, s * .26); c.lineTo(s * .80, s * .94); c.lineTo(s * .22, s * .94); c.closePath()
                c.moveTo(s * .36, s * .56); c.lineTo(s * .66, s * .56); c.moveTo(s * .36, s * .72); c.lineTo(s * .56, s * .72)
            } else if (kind === "tools") {
                c.moveTo(s * .14, s * .86); c.lineTo(s * .64, s * .36); c.arc(s * .74, s * .26, s * .14, Math.PI * .75, Math.PI * 2.4)
                c.moveTo(s * .86, s * .86); c.lineTo(s * .30, s * .30); c.moveTo(s * .12, s * .12); c.lineTo(s * .30, s * .30)
            } else if (kind === "more") {
                for (var i = 0; i < 3; ++i) { c.moveTo(s * (.24 + i * .26) + 1.6, s / 2); c.arc(s * (.24 + i * .26), s / 2, 1.6, 0, Math.PI * 2) }
            }
            c.stroke()
        }
    }

    // Anillo fino de avance (vacío y en gris si no hay dato).
    component Ring: Item {
        id: r
        readonly property Item ph: { var q = parent; while (q && !q.isPhone) q = q.parent; return q }
        property real value: -1                     // -1: sin dato
        property string label: "—"
        width: 74; height: 74
        Canvas {
            anchors.fill: parent
            onPaint: {
                var c = getContext("2d"); c.reset(); c.lineWidth = 3; c.lineCap = "round"
                c.strokeStyle = r.ph && r.ph.dark ? "rgba(255,255,255,0.16)" : "rgba(0,0,0,0.10)"
                c.beginPath(); c.arc(37, 37, 33, 0, Math.PI * 2); c.stroke()
                if (r.value > 0) { c.strokeStyle = r.ph && r.ph.dark ? "#FFFFFF" : "#151A30"
                                   c.beginPath(); c.arc(37, 37, 33, -Math.PI / 2, -Math.PI / 2 + Math.PI * 2 * r.value); c.stroke() }
            }
        }
        Text { anchors.centerIn: parent; text: r.label; color: r.ph ? r.ph.soft : "gray"; font.pixelSize: 24; font.family: win.font }
    }

    component RoundButton: Item {
        id: rb
        readonly property Item ph: { var q = parent; while (q && !q.isPhone) q = q.parent; return q }
        width: 54; height: 54
        Rectangle { anchors.fill: parent; radius: width / 2
                    color: rb.ph && rb.ph.dark ? "#2A2A2C" : "#FFFFFF"
                    border.width: 1; border.color: rb.ph && rb.ph.dark ? Qt.rgba(1, 1, 1, 0.12) : Qt.rgba(0, 0, 0, 0.07) }
    }

    component Phone: Item {
        id: ph
        readonly property bool isPhone: true
        property bool dark: false
        readonly property color ink: dark ? "#FFFFFF" : "#111114"
        readonly property color soft: dark ? "#8E8E93" : "#7C7C84"
        readonly property color lime: "#B8E986"
        width: 412; height: 892
        clip: true
        Rectangle { anchors.fill: parent; color: ph.dark ? "#000000" : "#EDEDF0" }

        Column {
            x: 18; y: 42; width: parent.width - 36
            spacing: 14

            // ---- Título grande, solo
            Item {
                width: parent.width; height: 72
                Column {
                    anchors.verticalCenter: parent.verticalCenter
                    Text { text: "Ficha de calicata"; color: ph.soft; font.pixelSize: 15; font.family: win.font }
                    Text { text: "General"; color: ph.ink; font.pixelSize: 44; font.weight: Font.DemiBold; font.family: win.font }
                }
            }

            // ---- Código / Proyecto / Supervisor (ancho, código grande)
            Widget {
                width: parent.width; height: 172
                Column {
                    x: 22; y: 20; spacing: 0
                    Row {
                        spacing: 8
                        Text { text: "c+00+11"; color: ph.ink; font.pixelSize: 46; font.weight: Font.Medium; font.family: win.font }
                        Text { text: "código"; color: ph.soft; font.pixelSize: 17; font.family: win.font; anchors.baseline: parent.children[0].baseline }
                    }
                }
                Column {
                    x: 22; anchors.bottom: parent.bottom; anchors.bottomMargin: 20; spacing: 2
                    Text { text: "PROYECTO_HUARMEY"; color: ph.ink; font.pixelSize: 19; font.family: win.font }
                    Text { text: "Supervisor  —"; color: ph.soft; font.pixelSize: 16; font.family: win.font }
                }
            }

            // ---- Tipo de ficha · Fechas / Logos
            Row {
                width: parent.width; spacing: 14
                Widget {
                    width: (parent.width - 14) / 2; height: 196
                    Item { x: 20; y: 20; width: 74; height: 74
                           Ring { anchors.fill: parent; label: "" }
                           Glyph { anchors.centerIn: parent; kind: "doc"; size: 30; tone: ph.ink } }
                    Column {
                        x: 20; width: parent.width - 40; anchors.bottom: parent.bottom; anchors.bottomMargin: 20; spacing: 2
                        Text { text: "Tipo de ficha"; color: ph.ink; font.pixelSize: 19; font.family: win.font }
                        Text { width: parent.width; text: "proyecto de prueba de inge+"; color: ph.soft; font.pixelSize: 15
                               elide: Text.ElideRight; font.family: win.font }
                    }
                }
                Widget {
                    width: (parent.width - 14) / 2; height: 196
                    Row {
                        x: 20; y: 26; spacing: 6
                        Text { text: "—"; color: ph.ink; font.pixelSize: 52; font.weight: Font.Medium; font.family: win.font }
                        Text { text: "día"; color: ph.soft; font.pixelSize: 17; font.family: win.font; anchors.baseline: parent.children[0].baseline }
                    }
                    Column {
                        x: 20; width: parent.width - 40; anchors.bottom: parent.bottom; anchors.bottomMargin: 20; spacing: 2
                        Text { text: "Fechas / Logos"; color: ph.ink; font.pixelSize: 19; font.family: win.font }
                        Text { text: "Inicio —  ·  Fin —"; color: ph.soft; font.pixelSize: 15; font.family: win.font }
                    }
                }
            }

            // ---- Maquinaria · Excavación (3D Touch)
            Row {
                width: parent.width; spacing: 14
                Widget {
                    width: (parent.width - 14) / 2; height: 196; corner: "touch"
                    Item { x: 20; y: 20; width: 74; height: 74
                           Ring { anchors.fill: parent; label: "" }
                           Glyph { anchors.centerIn: parent; kind: "tools"; size: 30; tone: ph.ink } }
                    Column {
                        x: 20; width: parent.width - 40; anchors.bottom: parent.bottom; anchors.bottomMargin: 20; spacing: 2
                        Text { text: "Maquinaria"; color: ph.ink; font.pixelSize: 19; font.family: win.font }
                        Text { width: parent.width; text: "Excavadora hidráulica"; color: ph.soft; font.pixelSize: 15
                               elide: Text.ElideRight; font.family: win.font }
                    }
                }
                Widget {
                    width: (parent.width - 14) / 2; height: 196; corner: "touch"
                    Ring { x: 20; y: 20; value: -1; label: "—" }     // anillo solo con dato real
                    Column {
                        x: 20; width: parent.width - 40; anchors.bottom: parent.bottom; anchors.bottomMargin: 20; spacing: 2
                        Text { text: "Excavación"; color: ph.ink; font.pixelSize: 19; font.family: win.font }
                        Text { text: "Profundidad — m"; color: ph.soft; font.pixelSize: 15; font.family: win.font }
                    }
                }
            }
        }

        // ---- Dock: SOLO maqueta de contexto; en la app se mantiene el Dock real sin cambios, en vidrio grafito / claro
        Item {
            x: 18; y: parent.height - 96; width: parent.width - 36; height: 70
            Rectangle { anchors.fill: parent; radius: 35
                        color: ph.dark ? "#1E1E20" : "#FFFFFF"
                        border.width: 1; border.color: ph.dark ? Qt.rgba(1, 1, 1, 0.10) : Qt.rgba(0, 0, 0, 0.07) }
            Row {
                anchors.centerIn: parent; spacing: 62
                Repeater { model: ["‹", "▭", "›", "+"]
                    Text { required property string modelData; text: modelData; color: ph.soft; font.pixelSize: 26; font.family: win.font } }
            }
        }
    }

    Item {
        id: canvasRoot
        width: 2 * 412 + 3 * 28; height: 892 + 56
        Rectangle { anchors.fill: parent; color: "#111111" }
        Row {
            x: 28; y: 28; spacing: 28
            Phone { dark: false }
            Phone { dark: true }
        }
    }

    Timer {
        interval: 1500; running: true
        onTriggered: canvasRoot.grabToImage(function (r) { r.saveToFile(win.outPath); Qt.quit() })
    }
}

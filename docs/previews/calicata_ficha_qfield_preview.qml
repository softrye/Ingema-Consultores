import QtQuick
import QtQuick.Window
import QtQuick.Effects

// Maqueta «Ficha de calicata» con el patrón de formulario de QField (referencia de UX,
// sin código de QField): hoja sobre el mapa, pestañas con estado en texto, campos en
// lista vertical con obligatorios y faltantes, siguiente pendiente y guardar.
// Datos reales de la ficha c+00+11 (capturas docs/previews/seccion_*.png); «—» si no hay.
Window {
    id: win
    width: 3 * 412 + 4 * 24
    height: 900
    visible: true
    color: "#1A1A1A"
    readonly property string outPath: "C:/Users/PC-02/Documents/InGePlus/AppCalicatasDemo/docs/previews/calicata_ficha_qfield_preview.png"
    readonly property string ff: "Segoe UI"

    // ---------- Piezas de la lista ----------
    component Group: Text {
        readonly property Item ph: { var q = parent; while (q && !q.isPhone) q = q.parent; return q }
        topPadding: 10; bottomPadding: 2
        font.pixelSize: 12; font.weight: Font.Bold; font.letterSpacing: 1.4; font.family: win.ff; color: ph ? ph.soft : "gray"
    }
    component Row2: Column {                        // campo editable: etiqueta (*) + caja de vidrio + regla
        readonly property Item ph: { var q = parent; while (q && !q.isPhone) q = q.parent; return q }
        id: rw
        property string label: ""
        property string value: ""
        property string placeholder: "—"
        property string unit: ""
        property bool required: false
        property bool missing: false
        property bool focused: false
        property string rule: ""
        property bool chevron: false
        width: parent ? parent.width : 0
        topPadding: 6; bottomPadding: 4; spacing: 5
        Row {
            spacing: 3
            Text { text: rw.label; color: rw.ph.soft; font.pixelSize: 13; font.weight: Font.DemiBold; font.family: win.ff }
            Text { visible: rw.required; text: "*"; color: rw.missing ? rw.ph.missing : rw.ph.soft; font.pixelSize: 14; font.bold: true }
        }
        Rectangle {
            width: rw.width; height: 46; radius: 14
            color: rw.ph.dark ? Qt.rgba(1, 1, 1, 0.07) : Qt.rgba(1, 1, 1, 0.75)
            border.width: rw.focused || rw.missing ? 2 : 1
            border.color: rw.focused ? rw.ph.accent : rw.missing ? rw.ph.missing
                        : (rw.ph.dark ? Qt.rgba(1, 1, 1, 0.16) : Qt.rgba(21 / 255, 26 / 255, 48 / 255, 0.16))
            Text { x: 14; anchors.verticalCenter: parent.verticalCenter; width: parent.width - 28 - (rw.chevron || rw.unit.length ? 40 : 0)
                   text: rw.value.length ? rw.value : rw.placeholder; elide: Text.ElideRight
                   color: rw.value.length ? rw.ph.ink : rw.ph.soft; font.pixelSize: 17; font.family: win.ff }
            Rectangle { visible: rw.focused; x: 14 + 9.4 * rw.value.length; anchors.verticalCenter: parent.verticalCenter; width: 2; height: 22; color: rw.ph.accent }
            Text { visible: rw.unit.length > 0; anchors.right: parent.right; anchors.rightMargin: 14; anchors.verticalCenter: parent.verticalCenter
                   text: rw.unit; color: rw.ph.soft; font.pixelSize: 15; font.family: win.ff }
            Text { visible: rw.chevron; anchors.right: parent.right; anchors.rightMargin: 14; anchors.verticalCenter: parent.verticalCenter
                   text: "›"; color: rw.ph.soft; font.pixelSize: 24 }
        }
        Text { visible: rw.rule.length > 0; width: rw.width; wrapMode: Text.WordWrap; text: rw.rule
               color: rw.missing ? rw.ph.missing : rw.ph.soft; font.pixelSize: 13
               font.weight: rw.missing ? Font.DemiBold : Font.Normal; font.family: win.ff }
    }


    component Phone: Item {
        id: ph
        readonly property bool isPhone: true
        property bool dark: false
        property int tab: 0
        readonly property color ink: dark ? "#FFFFFF" : "#151A30"
        readonly property color soft: dark ? Qt.rgba(1, 1, 1, 0.62) : "#5A6378"
        readonly property color line: dark ? Qt.rgba(1, 1, 1, 0.10) : Qt.rgba(21 / 255, 26 / 255, 48 / 255, 0.09)
        readonly property color accent: dark ? "#B8E986" : "#486426"
        readonly property color missing: dark ? "#FFB088" : "#A33800"
        width: 412; height: 892
        clip: true

        Item {                                          // mapa topográfico + punto de la calicata
            id: backdrop
            anchors.fill: parent
            Rectangle { anchors.fill: parent
                        gradient: Gradient {
                            GradientStop { position: 0; color: ph.dark ? "#16241A" : "#E8EDE1" }
                            GradientStop { position: 1; color: ph.dark ? "#0C140E" : "#D7E0CC" } } }
            Canvas {
                anchors.fill: parent
                onPaint: {
                    var c = getContext("2d"); c.reset()
                    for (var k = 0; k < 24; ++k) {
                        c.beginPath(); c.lineWidth = k % 5 === 0 ? 1.6 : 0.9
                        c.strokeStyle = ph.dark ? (k % 5 === 0 ? "rgba(184,233,134,0.30)" : "rgba(184,233,134,0.14)")
                                                : (k % 5 === 0 ? "rgba(72,100,38,0.42)" : "rgba(72,100,38,0.20)")
                        for (var x = -10; x <= width + 10; x += 8) {
                            var y = k * 42 - 40 + 30 * Math.sin(x / 70 + k * 0.45) + 18 * Math.sin(x / 23 + k * 1.3) + 0.25 * x
                            if (x === -10) c.moveTo(x, y); else c.lineTo(x, y)
                        }
                        c.stroke()
                    }
                    c.beginPath(); c.lineWidth = 7; c.strokeStyle = ph.dark ? "rgba(240,200,120,0.35)" : "rgba(214,160,70,0.55)"
                    c.moveTo(-20, 40); c.bezierCurveTo(140, 120, 220, 60, 430, 190); c.stroke()
                }
            }
            Rectangle { x: 206 - 18; y: 34 - 18; width: 36; height: 36; radius: 18; color: Qt.rgba(1, 0.65, 0.2, 0.25) }
            Rectangle { x: 206 - 9; y: 34 - 9; width: 18; height: 18; radius: 9; color: "#FFA733"; border.width: 3; border.color: "white" }
        }

        // ---- Hoja de formulario (vidrio esmerilado) ----
        Item {
            id: sheet
            y: 64; width: parent.width; height: parent.height - y + 40
            Item { id: smask; anchors.fill: parent; visible: false; layer.enabled: true
                   Rectangle { anchors.fill: parent; radius: 28; color: "black" } }
            ShaderEffectSource { id: ssrc; anchors.fill: parent; visible: false; sourceItem: backdrop
                                 sourceRect: Qt.rect(0, sheet.y, sheet.width, sheet.height) }
            MultiEffect { anchors.fill: parent; source: ssrc; blurEnabled: true; blur: 1; blurMax: 32; maskEnabled: true; maskSource: smask }
            Rectangle { anchors.fill: parent; radius: 28
                        color: ph.dark ? Qt.rgba(28 / 255, 28 / 255, 30 / 255, 0.86) : Qt.rgba(1, 1, 1, 0.82)
                        border.width: 1; border.color: ph.dark ? Qt.rgba(1, 1, 1, 0.14) : Qt.rgba(1, 1, 1, 0.9) }
            Rectangle { anchors.horizontalCenter: parent.horizontalCenter; y: 8; width: 40; height: 5; radius: 3
                        color: ph.dark ? Qt.rgba(1, 1, 1, 0.3) : Qt.rgba(0, 0, 0, 0.18) }

            // Cabecera: cancelar · título · guardar (como el formulario de QField)
            Item {
                x: 16; y: 22; width: parent.width - 32; height: 44
                Rectangle { width: 40; height: 40; radius: 20; color: ph.dark ? Qt.rgba(1, 1, 1, 0.08) : Qt.rgba(0, 0, 0, 0.05)
                            Text { anchors.centerIn: parent; text: "✕"; color: ph.ink; font.pixelSize: 15 } }
                Column {
                    x: 52; anchors.verticalCenter: parent.verticalCenter
                    Row {
                        spacing: 10
                        Text { id: codeT; text: "c+00+11"; color: ph.ink; font.pixelSize: 19; font.weight: Font.DemiBold; font.family: win.ff }
                        Text { anchors.baseline: codeT.baseline; text: ph.tab === 1 ? "Guardando…" : "Guardado ✓"
                               color: ph.tab === 1 ? ph.soft : ph.accent; font.pixelSize: 13; font.weight: Font.DemiBold; font.family: win.ff }
                    }
                    Text { text: "PROYECTO_HUARMEY"; color: ph.soft; font.pixelSize: 13; font.family: win.ff }
                }
            }

            // Pestañas compactas con estado en texto
            Flickable {
                x: 0; y: 74; width: parent.width; height: 46
                contentWidth: tabsRow.width + 32; clip: true; interactive: false
                contentX: ph.tab >= 2 ? 120 : 0
                Row {
                    id: tabsRow; x: 16; spacing: 8
                    Repeater {
                        model: [["Identidad", "Falta 1"], ["Ubicación", "Faltan 2"], ["Perfil", "Falta 1"],
                                ["Laboratorio", "Sin estratos"], ["Fotos", "Faltan 3"], ["Resumen", ""]]
                        Rectangle {
                            required property var modelData
                            required property int index
                            readonly property bool cur: index === ph.tab
                            readonly property bool ok: modelData[1] === "✓"
                            height: 46; radius: 23; width: tabCol.width + 26
                            color: cur ? (ph.dark ? Qt.rgba(1, 1, 1, 0.14) : "#151A30") : "transparent"
                            border.width: cur ? 0 : 1; border.color: ph.line
                            Column {
                                id: tabCol; anchors.centerIn: parent; spacing: -1
                                Text { anchors.horizontalCenter: parent.horizontalCenter; text: modelData[0]; font.pixelSize: 14; font.weight: Font.DemiBold
                                       font.family: win.ff; color: cur ? (ph.dark ? "white" : "white") : ph.ink }
                                Text { anchors.horizontalCenter: parent.horizontalCenter; visible: modelData[1].length > 0
                                       text: modelData[1]; font.pixelSize: 13; font.weight: Font.DemiBold; font.family: win.ff
                                       color: cur ? (ph.dark ? ph.missing : "#FFD2B3") : ph.missing }
                            }
                        }
                    }
                }
            }
            Rectangle { y: 128; width: parent.width; height: 1; color: ph.line }

            // Cuerpo de la pestaña
            Loader {
                x: 20; y: 142; width: parent.width - 40
                sourceComponent: ph.tab === 0 ? identityTab : ph.tab === 1 ? locationTab : profileTab
            }

            // Única barra inferior: el Dock se oculta en esta pantalla
            Item {
                x: 16; y: parent.height - 40 - 24 - 56; width: parent.width - 32; height: 56   // Dock oculto aquí (dockSuppressed); no se modifica
                Rectangle { anchors.fill: parent; radius: 28; color: ph.dark ? "#B8E986" : "#486426" }
                Text { anchors.centerIn: parent; color: ph.dark ? "#1A2A10" : "white"; font.pixelSize: 15; font.weight: Font.DemiBold; font.family: win.ff
                       text: ph.tab === 0 ? "Siguiente pendiente: Supervisor  →"
                           : ph.tab === 1 ? "Siguiente pendiente: Zona UTM  →" : "Siguiente pendiente: Estratos  →" }
            }
        }

        Component {
            id: identityTab
            Column {
                width: parent ? parent.width : 0
                Group { text: "CÓDIGO / PROYECTO / SUPERVISOR" }
                Row2 { label: "Código"; required: true; value: "c+00+11" }
                Row2 { label: "Nombre del proyecto"; required: true; value: "PROYECTO_HUARMEY" }
                Row2 { label: "Supervisor"; required: true; missing: true; placeholder: "Escribe el supervisor"; rule: "Obligatorio · falta el supervisor de campo" }
                Group { text: "FICHA Y PERIODO" }
                Row2 { label: "Tipo de ficha"; value: "proyecto de prueba de inge+"; chevron: true }
                Row2 { label: "Fecha inicio / fin"; chevron: true; placeholder: "Seleccionar fecha" }
                Group { text: "TRABAJO DE CAMPO" }
                Row2 { label: "Maquinaria"; value: "Excavadora hidráulica"; chevron: true }
            }
        }
        Component {
            id: locationTab
            Column {
                width: parent ? parent.width : 0
                Group { text: "COORDENADAS UTM" }
                Row2 { label: "X UTM (Este)"; required: true; value: "277237.98"; unit: "m"; rule: "Entre 100 000 y 900 000" }
                Row2 { label: "Y UTM (Norte)"; required: true; value: "8676908.17"; unit: "m"; rule: "Entre 0 y 10 000 000" }
                Row2 { label: "Z UTM / Cota"; value: "180.4"; unit: "m"; rule: "Manual" }
                Row2 { label: "Zona UTM"; required: true; missing: true; focused: true; value: "18"; rule: "Falta la banda: escribe, por ejemplo, 18L" }
                Group { text: "SISTEMA GEODÉSICO" }
                Row2 { label: "Datum"; required: true; missing: true; chevron: true; placeholder: "Elegir datum"; rule: "Obligatorio · WGS84 o PSAD56" }
                Group { text: "REFERENCIA VIAL" }
                Row2 { label: "Lado de la vía"; chevron: true }
            }
        }
        Component {
            id: profileTab
            Column {
                width: parent ? parent.width : 0
                Group { text: "CONFIGURACIÓN DEL PERFIL" }
                Row2 { label: "Profundidad total"; value: "0.00"; unit: "m"; focused: true; rule: "Registrada por estratos: 0.00 m" }
                Row2 { label: "Nivel freático"; unit: "m"; placeholder: "Sin registrar"; rule: "Ningún estrato registra agua" }
                Row2 { label: "Tipo de excavación"; chevron: true }
                Row2 { label: "Método de descripción"; chevron: true; rule: "SUCS o AASHTO" }
                Group { text: "ESTRATIGRAFÍA" }
                Item {                                   // lista repetible compacta (vacía hoy)
                    width: parent.width; height: 96
                    Rectangle { x: -20; width: 3; height: 88; y: 4; radius: 2; color: ph.missing }
                    Column {
                        y: 8; width: parent.width; spacing: 8
                        Text { text: "Sin estratos  ·  al menos uno es obligatorio *"; color: ph.missing; font.pixelSize: 13; font.weight: Font.DemiBold; font.family: win.ff }
                        Row {
                            spacing: 10
                            Repeater {
                                model: ["+ Crear primer estrato", "Usar plantilla"]
                                Rectangle {
                                    required property string modelData
                                    height: 40; radius: 20; width: et.width + 28
                                    color: "transparent"; border.width: 1; border.color: ph.line
                                    Text { id: et; anchors.centerIn: parent; text: modelData; color: ph.ink; font.pixelSize: 14; font.family: win.ff }
                                }
                            }
                        }
                        Text { text: "Cada estrato: 0.00–0.40 m · descripción · SUCS  ⋮"; color: ph.soft; font.pixelSize: 12; font.family: win.ff }
                    }
                }
            }
        }
    }

    Item {
        id: canvasRoot
        width: win.width; height: 892 + 48
        Rectangle { anchors.fill: parent; color: "#1A1A1A" }
        Row {
            x: 24; y: 24; spacing: 24
            Phone { dark: false; tab: 0 }
            Phone { dark: true; tab: 1 }
            Phone { dark: false; tab: 2 }
        }
    }

    Timer {
        interval: 1500; running: true
        onTriggered: canvasRoot.grabToImage(function (r) { r.saveToFile(win.outPath); Qt.quit() })
    }
}

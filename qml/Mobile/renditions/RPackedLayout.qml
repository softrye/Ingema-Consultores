import QtQuick

// Acomodo AUTÓNOMO de cajas de Rendiciones (prioridad: espacio horizontal).
// Cuadrícula de 12 columnas: Icono = 3, 1/3 = 4, 1/2 = 6, Ancho = 12.
//  1. Cada fila empieza con la siguiente caja del orden del usuario.
//  2. Los huecos se rellenan adelantando cajas posteriores que quepan (sin dejar
//     filas a medias mientras exista alguna caja que entre).
//  3. Si aun así sobra espacio, las cajas de la fila se estiran en proporción
//     (los iconos como máximo hasta media fila) para que la fila quede completa.
//  4. Las cajas de icono ocupan la altura de su fila (aprovecha el espacio vertical).
// Sólo cambia posiciones y anchos; el orden guardado y los datos no se alteran.
Item {
    id: packer
    property real spacing: 10
    readonly property int columns: 12
    property var spanOf: function(item) { return 6 }
    property var layoutTrigger: null               // cambia cuando cambian tamaños/orden
    property bool pending: false
    implicitHeight: contentHeight
    height: contentHeight
    property real contentHeight: 0

    // Límite de seguridad: como máximo 12 reacomodos seguidos por ráfaga de cambios.
    property int burst: 0
    Timer { id: burstReset; interval: 250; onTriggered: { var over = packer.burst > 12; packer.burst = 0; if (over) packer.schedule() } }
    function schedule() {
        if (pending || burst > 12) return
        pending = true
        burst++
        burstReset.restart()
        Qt.callLater(relayout)
    }
    onWidthChanged: schedule()
    onChildrenChanged: schedule()
    onLayoutTriggerChanged: schedule()

    function relayout() {
        pending = false
        if (width <= 0) return
        var items = []
        for (var i = 0; i < children.length; ++i) {
            var c = children[i]
            if (c.visible && c.order !== undefined && c.key !== undefined && String(c.key).length) items.push(c)
        }
        items.sort(function(a, b) { return a.order - b.order })
        var rest = items.slice(), rows = []
        while (rest.length) {
            var first = rest.shift()
            var row = [first], used = Math.min(columns, spanOf(first))
            for (var k = 0; k < rest.length && used < columns;) {
                var sp = Math.min(columns, spanOf(rest[k]))
                if (used + sp <= columns) { row.push(rest[k]); used += sp; rest.splice(k, 1) }
                else ++k
            }
            rows.push({ items: row, used: used })
        }
        var y = 0
        for (var r = 0; r < rows.length; ++r) {
            var cells = rows[r].items
            var avail = width - (cells.length - 1) * spacing
            // Reparto del sobrante: los iconos crecen como máximo hasta media fila.
            var spans = cells.map(function(it) { return Math.min(columns, packer.spanOf(it)) })
            var total = spans.reduce(function(a, b) { return a + b }, 0)
            var scale = columns / total
            var widths = cells.map(function(it, idx) {
                var grown = spans[idx] * scale
                if (it.iconPresentation === true) grown = Math.min(grown, columns / 2)
                return avail * grown / columns
            })
            var x = 0, h = 0
            for (var c2 = 0; c2 < cells.length; ++c2) {
                var it = cells[c2]
                // Sólo se asigna lo que cambia: evita cascadas de reacomodo (bucles).
                var nw = Math.floor(widths[c2]), nx = Math.round(x), ny = Math.round(y)
                if (it.width !== nw) it.width = nw
                if (it.x !== nx) it.x = nx
                if (it.y !== ny) it.y = ny
                if (!it.placedOnce) it.placedOnce = true
                x += Math.floor(widths[c2]) + spacing
                h = Math.max(h, it.fillRow ? it.minRowHeight : it.height)
            }
            for (var c3 = 0; c3 < cells.length; ++c3) if (cells[c3].rowHeight !== h) cells[c3].rowHeight = h
            y += h + spacing
        }
        var nh = Math.max(0, y - spacing)
        if (contentHeight !== nh) contentHeight = nh
    }
}

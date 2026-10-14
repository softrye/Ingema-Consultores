.pragma library
// Paleta de la subapp Rendiciones: lenguaje visual actual de InGe+ (vidrio
// azul oscuro, texto blanco). Sin reglas de negocio.

var background = "#111827"
var surface = Qt.rgba(28 / 255, 45 / 255, 80 / 255, 0.50)
var surfaceStrong = Qt.rgba(28 / 255, 45 / 255, 80 / 255, 0.78)
var border = Qt.rgba(1, 1, 1, 0.22)
var text = "#FFFFFF"
var muted = Qt.rgba(1, 1, 1, 0.72)
var faint = Qt.rgba(1, 1, 1, 0.45)
var accent = "#2F6FE0"
var accentSoft = "#8FC1FF"
var danger = "#FF8A80"
var success = "#7EE2A8"
var warning = "#FFD27A"

function syncColor(state) {
    switch (String(state || "").toUpperCase()) {
    case "SYNCED": return success
    case "SYNCING": return accentSoft
    case "CONFLICT":
    case "ERROR": return danger
    case "NEEDS_RECONCILIATION":
    case "PENDING_CREATE":
    case "PENDING_UPDATE":
    case "LOCAL_ONLY": return warning
    }
    return muted
}

function statusColor(status) {
    switch (String(status || "").toUpperCase()) {
    case "BORRADOR": return accentSoft
    case "OBSERVADO": return warning
    case "EN_REVISION": return "#C9B3FF"
    case "APROBADO": return success
    }
    return muted
}

function text_(row, a, b) {
    if (!row) return ""
    var v = row[a]
    if ((v === undefined || v === null || String(v).length === 0) && b) v = row[b]
    return v === undefined || v === null ? "" : String(v)
}

// dd/mm/aaaa a partir de ISO (solo presentación).
function date(iso) {
    var s = String(iso || "")
    if (s.length < 10) return s.length ? s : "—"
    return s.substring(8, 10) + "/" + s.substring(5, 7) + "/" + s.substring(0, 4)
}

function period(start, end) {
    return date(start) + " – " + date(end)
}

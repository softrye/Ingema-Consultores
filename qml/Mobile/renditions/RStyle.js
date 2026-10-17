.pragma library
// Paleta de la subapp Rendiciones: variante clara aprobada (2026-10-15) con
// la paleta corporativa INGEMA. Blanco, grises y transparencias son superficie;
// ámbar/rojo sólo como color semántico de estado. Sin reglas de negocio.

// Corporativos
var navyDark = "#151A30"      // 21, 26, 48
var navy = "#1C2D50"          // 28, 45, 80
var corporateBlue = "#0654A2" // 6, 84, 162
var corporateGreen = "#486426" // 72, 100, 38

// Superficies y texto (variante clara)
var background = "#FFFFFF"
var surface = Qt.rgba(1, 1, 1, 0.86)
var surfaceStrong = "#F3F6FB"
var popup = Qt.rgba(1, 1, 1, 0.94)
var border = Qt.rgba(21 / 255, 26 / 255, 48 / 255, 0.10)
var text = navyDark
var muted = "#7A8299"
var faint = "#A7AEC0"
var accent = corporateBlue
var accentSoft = "#3B82D6"
var onAccent = "#FFFFFF"
var track = "#E3E8F0"
// Nuevo gasto (previews aprobados): bordes de campo y superficies azuladas suaves.
var fieldBorder = Qt.rgba(6 / 255, 84 / 255, 162 / 255, 0.10)
var tintSoft = Qt.rgba(6 / 255, 84 / 255, 162 / 255, 0.07)       // mosaicos, nota informativa, chip
var tintSoftBorder = Qt.rgba(6 / 255, 84 / 255, 162 / 255, 0.12)
var cardGlass = Qt.rgba(1, 1, 1, 0.62)                          // tarjeta de sección (vidrio claro)

// Semánticos
var danger = "#C62F3E"
var success = corporateGreen
var warning = "#F2B21B"       // Borrador: ámbar de los puntos aprobados
var syncErrorRed = "#B42334"  // sólo para el aura de error de sincronización

// Tinta oscura translúcida para rellenos sobre blanco.
function ink(alpha) { return Qt.rgba(21 / 255, 26 / 255, 48 / 255, alpha) }

function syncColor(state) {
    switch (String(state || "").toUpperCase()) {
    case "SYNCED": return success
    case "SYNCING": return accentSoft
    case "CONFLICT":
    case "ERROR": return danger
    case "NEEDS_RECONCILIATION":
    case "PENDING_CREATE":
    case "PENDING_UPDATE":
    case "LOCAL_ONLY": return "#C98A06"
    }
    return muted
}

// Estado ADMINISTRATIVO de la ficha (nunca sincronización).
function statusColor(status) {
    switch (String(status || "BORRADOR").toUpperCase()) {
    case "BORRADOR": return warning
    case "OBSERVADO": return danger
    case "EN_REVISION": return corporateBlue
    case "APROBADO": return corporateGreen
    }
    return muted
}

// Igual que renditionDocumentName.ts (Web): el código no sustituye al nombre.
function renditionDisplayName(name, code) {
    var title = String(name === undefined || name === null ? "" : name).trim()
    var ref = String(code || "").trim()
    if (!title || title === ref || /^RDC-\d{4}-\d+(?:\.rend)?$/i.test(title)) return "Rendición"
    return title
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

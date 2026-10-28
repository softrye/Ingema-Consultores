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
function ink(alpha) { return dark ? Qt.rgba(1, 1, 1, alpha) : Qt.rgba(21 / 255, 26 / 255, 48 / 255, alpha) }

// Vidrio de superficie: blanco en claro; azul #1C2D50 translúcido en oscuro.
function glass(alpha) { return dark ? Qt.rgba(12 / 255, 16 / 255, 26 / 255, Math.min(0.90, alpha * 0.70)) : Qt.rgba(1, 1, 1, alpha) }
// Filo/borde del vidrio: blanco en claro; blanco tenue en oscuro.
function edge(alpha) { return dark ? Qt.rgba(1, 1, 1, alpha * 0.12) : Qt.rgba(1, 1, 1, alpha) }
// Pastilla de selección (segmentos): blanca en claro; verde suave en oscuro.
function pill() { return dark ? Qt.rgba(110 / 255, 154 / 255, 66 / 255, 0.30) : "#FFFFFF" }
// Tinte claro fijo (r, g, b en 0..255): igual en claro; vidrio oscuro en oscuro.
function lite(r, g, b, alpha) { return dark ? Qt.rgba(24 / 255, 30 / 255, 44 / 255, Math.min(0.92, alpha * 0.80)) : Qt.rgba(r / 255, g / 255, b / 255, alpha) }

// Tema oscuro: negro #0A0A0A, vidrio azul #1C2D50 y tonos claros de la marca.
// Los valores se leen al crear cada pantalla; HomeScreen recrea la subapp al cambiar de tema.
var dark = false
function setDark(on) {
    dark = on === true
    text = dark ? "#F2F4F8" : navyDark
    muted = dark ? "#A3A9B6" : "#7A8299"
    faint = dark ? "#6E7586" : "#A7AEC0"
    background = dark ? "#0A0A0A" : "#FFFFFF"
    surface = dark ? Qt.rgba(12 / 255, 16 / 255, 26 / 255, 0.62) : Qt.rgba(1, 1, 1, 0.86)
    surfaceStrong = dark ? "#181E2C" : "#F3F6FB"
    popup = dark ? Qt.rgba(18 / 255, 22 / 255, 32 / 255, 0.96) : Qt.rgba(1, 1, 1, 0.94)
    border = dark ? Qt.rgba(1, 1, 1, 0.12) : Qt.rgba(21 / 255, 26 / 255, 48 / 255, 0.10)
    // Íconos, selección y botones principales: verde Ingema medio en oscuro.
    corporateBlue = dark ? "#6E9A42" : "#0654A2"
    navy = dark ? "#8DB85A" : "#1C2D50"          // íconos (regresar, filtro, menús) en verde
    corporateGreen = dark ? "#A8CF7F" : "#486426"
    accent = dark ? "#6E9A42" : "#0654A2"
    accentSoft = dark ? "#8DB85A" : "#3B82D6"
    onAccent = "#FFFFFF"
    track = dark ? Qt.rgba(1, 1, 1, 0.12) : "#E3E8F0"
    fieldBorder = dark ? Qt.rgba(141 / 255, 184 / 255, 90 / 255, 0.22) : Qt.rgba(6 / 255, 84 / 255, 162 / 255, 0.10)
    tintSoft = dark ? Qt.rgba(110 / 255, 154 / 255, 66 / 255, 0.16) : Qt.rgba(6 / 255, 84 / 255, 162 / 255, 0.07)
    tintSoftBorder = dark ? Qt.rgba(110 / 255, 154 / 255, 66 / 255, 0.30) : Qt.rgba(6 / 255, 84 / 255, 162 / 255, 0.12)
    cardGlass = dark ? Qt.rgba(12 / 255, 16 / 255, 26 / 255, 0.55) : Qt.rgba(1, 1, 1, 0.62)
    success = corporateGreen
    danger = dark ? "#FF6B78" : "#C62F3E"
}

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
    case "EN_REVISION": return dark ? "#8AB8FF" : corporateBlue
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

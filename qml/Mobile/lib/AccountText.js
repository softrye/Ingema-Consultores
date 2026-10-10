.pragma library

// Política de texto de cuentas (AGENTS: el correo se conserva exactamente como
// fue escrito; la capitalización solo se aplica a nombres de persona), extraída
// de InGeCoreFlow.qml (Visual Zero, 2026-10-10). Sin interfaz.
//
// Regla crítica:
// - Nombres: pueden corregirse para mostrarse.
// - Correos: se devuelven exactamente como fueron recibidos.
// - emailLookupKey(): solo para comparación interna; nunca se guarda ni se
//   usa como sustituto del correo original.

var PRESERVE_EMAIL_EXACTLY = true
var TEXT_POLICY_VERSION = "1.0"

function originalText(value, fallbackValue) {
    if (value === undefined || value === null)
        return fallbackValue === undefined || fallbackValue === null
                ? "" : String(fallbackValue)
    return String(value)
}

function hasVisibleText(value) {
    var raw = originalText(value, "")
    return raw.replace(/^\s+|\s+$/g, "").length > 0
}

function looksLikeEmail(value) {
    var raw = originalText(value, "")
    var at = raw.indexOf("@")
    return at > 0 && at < raw.length - 1
}

function displayEmailExact(value, fallbackValue) {
    var raw = originalText(value, "")
    if (raw.replace(/^\s+|\s+$/g, "").length === 0)
        return originalText(fallbackValue, "")
    return raw
}

function emailLookupKey(value) {
    return originalText(value, "")
            .replace(/^\s+|\s+$/g, "")
            .toLowerCase()
}

function normalizeNameSegment(segment) {
    var raw = originalText(segment, "")
    if (raw.length === 0)
        return ""
    var upper = raw.toUpperCase()
    var lower = raw.toLowerCase()
    // Una combinación interna de mayúsculas y minúsculas se conserva (McDonald).
    if (raw !== upper && raw !== lower)
        return raw.charAt(0).toUpperCase() + raw.substring(1)
    return lower.charAt(0).toUpperCase() + lower.substring(1)
}

function normalizeNameWord(word) {
    var raw = originalText(word, "")
    var result = ""
    var segment = ""
    for (var i = 0; i < raw.length; ++i) {
        var ch = raw.charAt(i)
        if (ch === "-" || ch === "'") {
            result += normalizeNameSegment(segment)
            result += ch
            segment = ""
        } else {
            segment += ch
        }
    }
    result += normalizeNameSegment(segment)
    return result
}

// `capitalize` (por defecto true) = corrección de nombres habilitada.
function displayPersonName(value, fallbackValue, capitalize) {
    var raw = originalText(value, "")
    if (raw.replace(/^\s+|\s+$/g, "").length === 0)
        raw = originalText(fallbackValue, "")
    // Un correo jamás se capitaliza, aunque se pida formatear como nombre.
    if (looksLikeEmail(raw))
        return displayEmailExact(raw, fallbackValue)
    var compact = raw
            .replace(/^\s+|\s+$/g, "")
            .replace(/\s+/g, " ")
    if (capitalize === false)
        return compact
    var words = compact.split(" ")
    var result = []
    for (var i = 0; i < words.length; ++i) {
        if (words[i].length > 0)
            result.push(normalizeNameWord(words[i]))
    }
    return result.join(" ")
}

function personInitials(value, maximumLetters, capitalize) {
    var formatted = displayPersonName(value, "", capitalize)
    if (formatted.length === 0 || looksLikeEmail(formatted))
        return ""
    var limit = Math.max(1, Math.min(3, Math.round(Number(maximumLetters) || 2)))
    var words = formatted.split(/\s+/)
    var initials = ""
    for (var i = 0; i < words.length && initials.length < limit; ++i) {
        if (words[i].length > 0)
            initials += words[i].charAt(0).toUpperCase()
    }
    if (initials.length === 0)
        initials = formatted.substring(0, limit).toUpperCase()
    return initials
}

function displayText(value, role, fallbackValue, capitalize) {
    var safeRole = originalText(role, "plain").toLowerCase()
    if (safeRole === "email" || safeRole === "correo")
        return displayEmailExact(value, fallbackValue)
    if (safeRole === "person" || safeRole === "name"
            || safeRole === "nombre" || safeRole === "personname")
        return displayPersonName(value, fallbackValue, capitalize)
    return originalText(value, fallbackValue)
}

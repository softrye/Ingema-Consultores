.pragma library

// Reglas del espacio de trabajo de Calicatas (documentos, nombres de archivo y
// estados), extraídas de CalicatasEditorPage.qml (Visual Zero, 2026-10-10).
// Sin interfaz: operan sobre documentos planos { header, cortes, images, observaciones, status }.

var STATUS_LABELS = {
    BORRADOR: "Borrador", EN_REVISION: "En revisión", OBSERVADO: "Observado",
    REVISADO: "Revisado", APROBADO: "Aprobado", EXPORTADO: "Exportado", ARCHIVADO: "Archivado"
}
var SYNC_LABELS = {
    LOCAL: "Solo en este equipo", PENDING: "Pendiente de sincronizar",
    SYNCING: "Sincronizando…", SYNCED: "Sincronizada", CONFLICT: "Conflicto con el servidor"
}
// Ciclo de vida de la ficha (orden de presentación de los estados).
var STATUS_LIFECYCLE = ["BORRADOR", "EN_REVISION", "OBSERVADO", "REVISADO", "APROBADO", "EXPORTADO"]

function statusLabel(status) { return STATUS_LABELS[String(status || "")] || String(status || "") }
function syncLabel(state) { return SYNC_LABELS[String(state || "")] || String(state || "") }

// Ficha vacía (sin proyecto, identidad remota, código, cabecera, estratos, fotos
// ni observaciones): se puede descartar o reutilizar sin pérdida.
function isPlaceholderDoc(doc) {
    if (!doc) return true
    var h = doc.header || {}
    if (String(h.projectId || "").length || String(h.remoteCalicataId || "").length
            || String(h.code || h.codigo || "").trim().length) return false
    var keys = ["supervisor", "maquina", "ubicacion", "utm_x", "utm_y", "description", "progresiva", "fecha_inicio"]
    for (var k = 0; k < keys.length; ++k) if (String(h[keys[k]] || "").trim().length) return false
    var cortes = doc.cortes || []
    for (var i = 0; i < cortes.length; ++i) {
        var c = cortes[i] || {}
        if (String(c.descripcion || "").trim().length || String(c.a || "").trim().length
                || String(c.sucs || "").length || String(c.tipo_muestra || "").length) return false
    }
    var images = doc.images || {}
    for (var p = 1; p <= 3; ++p) if (String(images["foto" + p + "_path"] || "").length) return false
    return !String(doc.observaciones || "").trim().length
}

// Conflicto de código antes de sincronizar: otra ficha abierta del MISMO proyecto
// con el mismo código (salvo la misma calicata remota o una archivada sin remoto).
// `others` = las demás fichas abiertas; `sameDoc(a, b)` identifica la misma instancia.
function codeConflict(doc, others, sameDoc) {
    if (!doc) return ""
    var h = doc.header || {}
    var code = String(h.code || h.codigo || "").trim()
    var projectId = String(h.projectId || "")
    var remoteId = String(h.remoteCalicataId || "")
    if (!code.length || !projectId.length) return ""
    for (var i = 0; i < others.length; ++i) {
        var other = others[i]
        if (!other || other === doc || (sameDoc && sameDoc(other, doc))) continue
        var oh = other.header || {}
        if (String(oh.projectId || "") !== projectId) continue
        if (String(oh.code || oh.codigo || "").trim() !== code) continue
        if (remoteId.length && String(oh.remoteCalicataId || "") === remoteId) continue
        if (String(other.status || "") === "ARCHIVADO" && !String(oh.remoteCalicataId || "").length) continue
        return "Otra ficha abierta de este proyecto ya usa el código " + code
                + ". Cambia el código antes de sincronizar."
    }
    return ""
}

// Nombre de archivo seguro (Windows/Android): sin caracteres inválidos ni punto/espacio final.
function safeStem(s) {
    s = (s || "").toString().trim()
    s = s.replace(/[<>:"\/\\|?*\x00-\x1F]/g, "_")
    s = s.replace(/[\. ]+$/g, "")
    if (!s.length) s = "calicata"
    return s
}

function headerCode(doc) {
    var h = doc ? doc.header : null
    return h && (h.codigo || h.calicata || h.pk || h.progresiva)
            ? (h.codigo || h.calicata || h.pk || h.progresiva) : ""
}

function headerStem(doc) { return safeStem(headerCode(doc)) }

function stemForSaveAs(doc) {
    var code = (headerCode(doc) || "").toString().trim()
    return code.length ? code : "calicata"
}

// Ruta legible del Excel exportado a InGeDrive.
function excelDrivePath(result, projectName, fileName) {
    var folder = String(result.remoteFolderPath || "")
    return projectName + " › " + (folder.length ? folder.split("/").join(" › ")
                                                : "carpeta del JSON › exports") + " › " + fileName
}

// Igualdad estructural de estados guardados (escalares del mismo tipo se comparan como texto).
function deepEqual(a, b) {
    if (a === b) return true
    if (a === null || b === null || a === undefined || b === undefined) return false
    if (typeof a !== typeof b) return false
    if (typeof a !== "object") return String(a) === String(b)
    var aa = Array.isArray(a), ab = Array.isArray(b)
    if (aa !== ab) return false
    if (aa) {
        if (a.length !== b.length) return false
        for (var i = 0; i < a.length; i++) if (!deepEqual(a[i], b[i])) return false
        return true
    }
    var ka = Object.keys(a).sort()
    var kb = Object.keys(b).sort()
    if (ka.length !== kb.length) return false
    for (var j = 0; j < ka.length; j++) if (ka[j] !== kb[j]) return false
    for (var k = 0; k < ka.length; k++) {
        var key = ka[k]
        if (!deepEqual(a[key], b[key])) return false
    }
    return true
}

function pad2(value) { return value < 10 ? "0" + value : String(value) }

function todayIso(now) {
    var d = now || new Date()
    return d.getFullYear() + "-" + pad2(d.getMonth() + 1) + "-" + pad2(d.getDate())
}

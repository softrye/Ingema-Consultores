.pragma library

// Esquema de edición/sello de fotografías de Calicatas (campos del sello, estilo,
// ajustes de imagen y marca de agua), extraído de CalicataPhotoEditor.qml
// (Visual Zero, 2026-10-10). Lo consume la edición en C++ (applyPhotoImageEdit,
// persistStampedPhotoToCache). Sin interfaz.

// [clave, etiqueta, visible por defecto]
var PHOTO_FIELDS = [
    ["zone", "Zona", true], ["easting", "Este", true], ["northing", "Norte", true], ["altitude", "Altitud", true],
    ["calicata", "Código de calicata", true], ["project", "Proyecto", true], ["date", "Fecha", true],
    ["time", "Hora", true], ["depth", "Profundidad", false], ["category", "Categoría", false], ["user", "Responsable", false]
]
var DEFAULT_STYLE = { fontId: "sans", bold: false, sizePct: 4, color: "#ffffff",
    backdrop: "shadow", anchor: "bottom-right", offsetXPct: 0, offsetYPct: 0, coordFormat: "utm",
    logoAnchor: "top-left", logoScalePct: 100, logoOpacityPct: 100, logoMarginPct: 0, enlargeSmall: true }
var DEFAULT_IMAGE = { rotation: 0, angle: 0, flipH: false, flipV: false, aspect: "free",
    exposure: 0, brightness: 0, contrast: 0, highlights: 0, shadows: 0, warmth: 0, tint: 0, saturation: 0,
    clarity: 0, sharpness: 0, vignette: 0, vignetteSize: 50, vignetteSoftness: 50, vignetteX: 0.5, vignetteY: 0.5,
    preset: "original", presetIntensity: 100, resolution: "max" }
// Datos que fija la captura (no se sobrescriben con lo guardado en la edición).
var CAPTURE_OWNED_KEYS = ["date", "time", "time_source", "altitude", "altitude_source", "project", "calicata"]

function clone(v) { return JSON.parse(JSON.stringify(v === undefined || v === null ? {} : v)) }

// Metadatos vigentes de la ficha + lo guardado en la foto que no sea de la captura.
function mergeMetadata(fresh, stored, category) {
    var merged = clone(fresh)
    stored = stored || {}
    for (var key in stored) {
        if (CAPTURE_OWNED_KEYS.indexOf(key) >= 0) continue
        var value = stored[key]
        if (String(merged[key] || "").trim().length) continue
        if (value !== undefined && value !== null && String(value).trim().length) merged[key] = value
    }
    merged.category = category
    return merged
}

// Edición completa con valores por defecto y rangos válidos. `freshMetadata()`
// solo se llama si la edición no trae metadatos.
function normalizeEdit(e, freshMetadata) {
    var n = clone(e)
    n.withMetadata = n.withMetadata !== false
    var f = n.fields || {}
    for (var i = 0; i < PHOTO_FIELDS.length; ++i)
        if (f[PHOTO_FIELDS[i][0]] === undefined) f[PHOTO_FIELDS[i][0]] = PHOTO_FIELDS[i][2]
    n.fields = f
    n.metadata = n.metadata || (freshMetadata ? freshMetadata() : {})
    var s = n.style || {}
    for (var k in DEFAULT_STYLE) if (s[k] === undefined) s[k] = DEFAULT_STYLE[k]
    s.sizePct = Math.max(2, Math.min(10, Number(s.sizePct)))
    s.offsetXPct = Math.max(-45, Math.min(45, Number(s.offsetXPct)))
    s.offsetYPct = Math.max(-45, Math.min(45, Number(s.offsetYPct)))
    s.logoScalePct = Math.max(40, Math.min(300, Number(s.logoScalePct)))
    s.logoOpacityPct = Math.max(10, Math.min(100, Number(s.logoOpacityPct)))
    s.logoMarginPct = Math.max(0, Math.min(15, Number(s.logoMarginPct)))
    n.style = s
    n.logo = n.logo || { enabled: false, source: "PROJECT" }
    var im = n.image || {}
    for (var j in DEFAULT_IMAGE) if (im[j] === undefined) im[j] = DEFAULT_IMAGE[j]
    im.rotation = ((Math.round(Number(im.rotation) / 90) * 90) % 360 + 360) % 360
    im.angle = Math.max(-45, Math.min(45, Number(im.angle) || 0))
    var adjust = ["exposure", "brightness", "contrast", "highlights", "shadows", "warmth", "tint", "saturation", "clarity", "vignette"]
    for (var a = 0; a < adjust.length; ++a) im[adjust[a]] = Math.max(-100, Math.min(100, Number(im[adjust[a]]) || 0))
    im.sharpness = Math.max(0, Math.min(100, Number(im.sharpness) || 0))
    n.image = im
    var w = n.watermark || {}
    if (w.enabled === undefined) w.enabled = false
    if (w.text === undefined) w.text = String((n.metadata || {}).project || "")
    if (w.opacityPct === undefined) w.opacityPct = 30
    if (w.sizePct === undefined) w.sizePct = 6
    if (w.anchor === undefined) w.anchor = "middle-center"
    if (w.tiled === undefined) w.tiled = false
    n.watermark = w
    n.annotations = n.annotations || []
    return n
}

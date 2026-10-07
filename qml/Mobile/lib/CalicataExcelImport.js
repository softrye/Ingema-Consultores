.pragma library
// Importación de fichas de Calicata desde Excel (.xlsx) — servicio puro.
//
//   libro (celdas de texto + rangos combinados, leído en C++ por
//   ExcelExporter.readWorkbookCells: solo .xlsx, sin macros ni objetos)
//     → detectTemplate()            detector de plantilla
//     → adapter                     InGePlusExcelAdapter
//                                   IngemaTestificacionAdapter (ficha llenada a mano, p. ej. C-AA-02)
//                                   GenericCalicataExcelAdapter (etiquetas normalizadas)
//     → borrador normalizado        { header, cortes, observaciones, timestamp }
//     → validateDraft()             sin datos inventados ni ficha basura
//     → reporte                     confianza por campo (EXACT/HEURISTIC/MISSING/INVALID/AMBIGUOUS)
//
// Sin dependencias de UI: se prueba con Node (tests/calicatas/excel_import.cjs).
// El nombre del proyecto sale SIEMPRE del contenido del libro; la carpeta de
// origen solo se conserva como metadato de origen/destino sugerido.

var EXACT = "EXACT", HEURISTIC = "HEURISTIC", MISSING = "MISSING", INVALID = "INVALID", AMBIGUOUS = "AMBIGUOUS"
var STATUS_OK = "OK", STATUS_NOT_RECOGNIZED = "NOT_RECOGNIZED", STATUS_FAILED = "FAILED"
var NOT_RECOGNIZED_MESSAGE = "No pudimos reconocer este formato de calicata."
var IMAGES_WARNING = "Las imágenes del Excel no fueron importadas."
var SAMPLE_TYPES = ["MA", "MI", "MS", "MW"]
var ORIGIN_RE = /^(natural|relleno(\s+antr[oó]pico)?|antr[oó]pico|mixto\s*\/\s*intervenido)$/i
var MAX_STRATA = 60

// ---------------------------------------------------------------- celdas
// SUCS/AASHTO impresos en la ficha oficial = clasificación declarada del
// laboratorio (columnas de resultados), no una sugerencia: van a la autoridad
// del laboratorio (primary/secondary/is_composite/aashto, contrato Web). El
// texto original se conserva en corte.sucs / corte.aashto.
var LAB_SUCS = ["GW", "GP", "GM", "GC", "SW", "SP", "SM", "SC", "ML", "CL", "OL", "MH", "CH", "OH", "PT"]
var LAB_AASHTO = ["A-1-a", "A-1-b", "A-2-4", "A-2-5", "A-2-6", "A-2-7", "A-3", "A-4", "A-5", "A-6", "A-7-5", "A-7-6"]
function labClassificationFromSheet(corte) {
    var codes = String(corte.sucs || "").toUpperCase().split(/[^A-Z]+/).filter(function(c) { return LAB_SUCS.indexOf(c) >= 0 })
    if (codes.length) {
        corte.primary_sucs = codes[0]
        corte.is_composite = codes.length > 1 && codes[1] !== codes[0]
        corte.secondary_sucs = corte.is_composite ? codes[1] : ""
    }
    var aashto = String(corte.aashto || "").trim().replace(/\s+/g, "")
    for (var i = 0; i < LAB_AASHTO.length; ++i)
        if (LAB_AASHTO[i].toUpperCase() === aashto.toUpperCase()) corte.lab_confirmed_aashto = LAB_AASHTO[i]
}

function colNumber(letters) {
    var n = 0
    for (var i = 0; i < letters.length; ++i) n = n * 26 + (letters.charCodeAt(i) - 64)
    return n
}
function colLetters(n) {
    var s = ""
    while (n > 0) { var m = (n - 1) % 26; s = String.fromCharCode(65 + m) + s; n = Math.floor((n - 1) / 26) }
    return s
}
function parseRef(ref) {
    var m = /^([A-Z]+)(\d+)$/.exec(String(ref || "").toUpperCase())
    return m ? { col: colNumber(m[1]), row: Number(m[2]) } : null
}
function parseRange(range) {
    var parts = String(range || "").toUpperCase().split(":")
    var a = parseRef(parts[0]), b = parseRef(parts[1] || parts[0])
    if (!a || !b) return null
    return { r1: Math.min(a.row, b.row), c1: Math.min(a.col, b.col), r2: Math.max(a.row, b.row), c2: Math.max(a.col, b.col) }
}
function Sheet(raw) {
    this.name = String(raw && raw.name || "")
    this.cells = (raw && raw.cells) || {}
    this.merges = []
    var list = (raw && raw.merges) || []
    for (var i = 0; i < list.length; ++i) { var r = parseRange(list[i]); if (r) this.merges.push(r) }
}
Sheet.prototype.text = function(ref) {
    var v = this.cells[ref]
    return v === undefined || v === null ? "" : String(v).replace(/\r\n/g, "\n").trim()
}
Sheet.prototype.at = function(row, col) { return this.text(colLetters(col) + row) }
Sheet.prototype.refs = function() { return Object.keys(this.cells) }

function normalizeLabel(text) {
    var s = String(text || "").toUpperCase()
    var from = "ÁÉÍÓÚÜÑÀÈÌÒÙ", to = "AEIOUUNAEIOU"
    var out = ""
    for (var i = 0; i < s.length; ++i) { var k = from.indexOf(s[i]); out += k >= 0 ? to[k] : s[i] }
    return out.replace(/[.:]+$/g, "").replace(/\s+/g, " ").trim()
}
function decimal(text) {
    var t = String(text || "").trim().replace(",", ".")
    if (!/^-?\d+(\.\d+)?$/.test(t)) return NaN
    return Number(t)
}
function fmt2(n) { return (Math.round(n * 100) / 100).toFixed(2) }
function uuid4() {
    return "xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx".replace(/[xy]/g, function(ch) {
        var r = Math.random() * 16 | 0
        return (ch === "x" ? r : (r & 0x3 | 0x8)).toString(16)
    })
}
// Identidad local nueva (como CalicataFormPage.addCorte): un estrato importado
// nunca reutiliza ids remotos ni del archivo.
function withLocalIdentity(cortes) {
    for (var i = 0; i < cortes.length; ++i) {
        cortes[i].id = "stratum-" + Date.now() + "-" + i + "-" + Math.random().toString(36).slice(2)
        cortes[i].local_stratum_id = uuid4()
    }
    return cortes
}
function dmyToIso(text) {
    var m = /(\d{1,2})\/(\d{1,2})\/(\d{4})/.exec(String(text || ""))
    if (!m) return ""
    var d = Number(m[1]), mo = Number(m[2]), y = Number(m[3])
    if (mo < 1 || mo > 12 || d < 1 || d > 31) return ""
    return y + "-" + (mo < 10 ? "0" : "") + mo + "-" + (d < 10 ? "0" : "") + d
}

// ---------------------------------------------------------------- reporte
function Report() { this.fields = {}; this.warnings = [] }
Report.prototype.set = function(key, confidence, detail) {
    this.fields[key] = detail ? { confidence: confidence, detail: detail } : { confidence: confidence }
}
Report.prototype.warn = function(text) { if (this.warnings.indexOf(text) < 0) this.warnings.push(text) }

// ---------------------------------------------------------------- detector
// Ficha "TESTIFICACIÓN DE CALICATA" (plantilla INGEMA/MTC usada por el
// exportador de InGe+ y por las fichas oficiales llenadas a mano).
var TESTIFICACION_SIGNATURE = [
    ["AG1", /^TESTIFICACION DE CALICATA/],
    ["AY8", /^CALICATA$/],
    ["AH9", /^SUPERVISOR$/],
    ["AR9", /^X UTM$/],
    ["J13", /^DESCRIPCION DEL TERRENO$/],
    ["AH13", /^CLASIFICACION SUCS$/],
    ["AG13", /^CLASIFICACION AASHTO$/]
]

function testificacionScore(sheet) {
    var hits = 0
    for (var i = 0; i < TESTIFICACION_SIGNATURE.length; ++i) {
        var sig = TESTIFICACION_SIGNATURE[i]
        if (sig[1].test(normalizeLabel(sheet.text(sig[0]).split("\n")[0]))) hits++
    }
    return hits / TESTIFICACION_SIGNATURE.length
}

// Marca del exportador nativo: "FIN DE LA CALICATA — x m" y descripciones
// "de–a m\n…" con guion largo; una ficha llenada a mano no las tiene.
function isNativeExport(sheet) {
    var refs = sheet.refs()
    for (var i = 0; i < refs.length; ++i)
        if (/^FIN DE LA CALICATA\s+—\s+\d+(\.\d+)?\s*m$/.test(sheet.text(refs[i]))) return true
    return false
}

function detectTemplate(workbook) {
    var sheets = (workbook && workbook.sheets) || []
    var best = null
    for (var i = 0; i < sheets.length; ++i) {
        var sheet = new Sheet(sheets[i])
        var score = testificacionScore(sheet)
        if (score >= 0.7 && (!best || score > best.score))
            best = { family: "TESTIFICACION", sheet: sheet, score: score,
                     adapter: isNativeExport(sheet) ? "InGePlusExcelAdapter" : "IngemaTestificacionAdapter" }
    }
    if (best) return best
    for (var k = 0; k < sheets.length; ++k) {
        var generic = new Sheet(sheets[k])
        var labels = genericLabelHits(generic)
        if (labels.score >= 3 && (!best || labels.score > best.score))
            best = { family: "GENERIC", sheet: generic, score: labels.score, adapter: "GenericCalicataExcelAdapter" }
    }
    return best
}

// ------------------------------------------- adapter determinista TESTIFICACIÓN
// Escala vertical del perfil: etiquetas numéricas de la columna C (C21 = 0 …
// C81 = profundidad del eje). El tramo de profundidad d empieza en la fila
// (etiqueta + 1). Interpolación lineal por tramos (tolera filas insertadas).
function depthScale(sheet) {
    var points = []
    for (var row = 18; row <= 400; ++row) {
        var t = sheet.at(row, 3)
        if (!t.length) continue
        var v = decimal(t)
        if (isFinite(v)) points.push({ row: row + 1, depth: v })
    }
    var ok = points.length >= 2 && points[0].depth === 0
    for (var i = 1; ok && i < points.length; ++i) ok = points[i].depth > points[i - 1].depth && points[i].row > points[i - 1].row
    return ok ? points : null
}
function depthAtRow(points, row) {
    if (row <= points[0].row) return points[0].depth
    for (var i = 1; i < points.length; ++i) {
        var a = points[i - 1], b = points[i]
        if (row <= b.row) return a.depth + (row - a.row) * (b.depth - a.depth) / (b.row - a.row)
    }
    var p = points[points.length - 2], q = points[points.length - 1]
    return q.depth + (row - q.row) * (q.depth - p.depth) / (q.row - p.row)
}
function finRow(sheet) {
    var refs = sheet.refs()
    for (var i = 0; i < refs.length; ++i)
        if (/^FIN DE LA CALICATA/i.test(sheet.text(refs[i]))) { var r = parseRef(refs[i]); if (r) return r.row }
    return 0
}
function mergeAt(sheet, row, col) {
    for (var i = 0; i < sheet.merges.length; ++i) {
        var m = sheet.merges[i]
        if (m.r1 === row && m.c1 === col) return m
    }
    return null
}

// "0.00 – 0.50 m …", "2.00 - 300 m. …": intervalo declarado al inicio del texto.
var INTERVAL_RE = /^\s*(\d+(?:[.,]\d+)?)\s*[-–—]\s*(\d+(?:[.,]\d+)?)\s*m\b\.?\s*/i

function parseStrata(sheet, report, native) {
    var scale = depthScale(sheet)
    if (!scale) { report.set("cortes", MISSING, "Sin escala de profundidad"); return [] }
    var endRow = finRow(sheet) || scale[scale.length - 1].row + 1
    var rows = []
    for (var row = scale[0].row; row < endRow && rows.length < MAX_STRATA; ++row) {
        var merge = mergeAt(sheet, row, 10)
        var text = sheet.at(row, 10)
        if (!merge && !text.length) continue
        if (!text.length && !sheet.at(row, 33).length && !sheet.at(row, 34).length && !sheet.at(row, 30).length) continue
        rows.push({ r1: row, r2: merge ? merge.r2 : row, merged: !!merge, text: text })
        if (merge) row = merge.r2
    }
    var cortes = [], exact = true
    for (var i = 0; i < rows.length; ++i) {
        var item = rows[i]
        // Límite inferior: fin del rango combinado del estrato; sin combinación,
        // el inicio del siguiente estrato (o la fila FIN para el último).
        var nextRow = item.merged ? item.r2 + 1 : (i + 1 < rows.length ? rows[i + 1].r1 : endRow)
        var geoDe = depthAtRow(scale, item.r1), geoA = depthAtRow(scale, nextRow)
        var de = geoDe, a = geoA, body = item.text
        var m = INTERVAL_RE.exec(item.text)
        if (m) {
            body = item.text.slice(m[0].length).replace(/^\s*\n/, "").trim()
            var tDe = decimal(m[1]), tA = decimal(m[2])
            var tolerance = Math.max(0.05, (geoA - geoDe) * 0.05)
            if (Math.abs(tDe - geoDe) <= tolerance && Math.abs(tA - geoA) <= tolerance) { de = tDe; a = tA }
            else {
                exact = false
                report.warn("Estrato " + (i + 1) + ": el intervalo escrito («" + m[0].trim()
                            + "») no coincide con el perfil; se usó " + fmt2(geoDe) + "–" + fmt2(geoA) + " m.")
            }
        } else exact = false
        var origin = ""
        if (native) {
            var lines = body.split("\n")
            if (lines.length && ORIGIN_RE.test(lines[0].trim())) { origin = lines.shift().trim(); body = lines.join("\n").trim() }
        }
        var corte = {
            de: fmt2(de), a: fmt2(a), descripcion: body, material_origin: origin,
            tipo_muestra: "", tipo_otro: "", muestra_desde: "", muestra_hasta: "",
            resultados: sheet.at(item.r1, 32), aashto: sheet.at(item.r1, 33), sucs: sheet.at(item.r1, 34),
            gmax: sheet.at(item.r1, 35), g2: sheet.at(item.r1, 36), g04: sheet.at(item.r1, 37),
            g008: sheet.at(item.r1, 38), g002: sheet.at(item.r1, 39), wl: sheet.at(item.r1, 40),
            lp: sheet.at(item.r1, 41), hum2: sheet.at(item.r1, 42),
            humedad: -1, excavabilidad: -1, estabilidad: -1
        }
        if (corte.lp.toUpperCase() === "NP") { corte.lp = ""; corte.nonplastic_confirmed = true }
        labClassificationFromSheet(corte)
        if (!native && percentFromFractions(corte))
            report.set("estratos.laboratorio", HEURISTIC, "Fracciones de la plantilla convertidas a % (max. = 1)")
        var tipo = sheet.at(item.r1, 30)
        if (tipo.length) {
            var upper = tipo.toUpperCase()
            if (SAMPLE_TYPES.indexOf(upper) >= 0) corte.tipo_muestra = upper
            else { corte.tipo_muestra = "Otro"; corte.tipo_otro = tipo }
            var interval = /^\s*(\d+(?:[.,]\d+)?)\s*[-–—]\s*(\d+(?:[.,]\d+)?)\s*$/.exec(sheet.at(item.r1, 31))
            if (interval) { corte.muestra_desde = fmt2(decimal(interval[1])); corte.muestra_hasta = fmt2(decimal(interval[2])) }
        }
        cortes.push(corte)
    }
    report.set("cortes", cortes.length ? (exact ? EXACT : HEURISTIC) : MISSING,
               cortes.length + " estrato(s)")
    report.set("estratos.sucs", cortes.some(function(c) { return c.sucs.length }) ? EXACT : MISSING)
    report.set("estratos.aashto", cortes.some(function(c) { return c.aashto.length }) ? EXACT : MISSING)
    report.set("estratos.humedad_excavabilidad_estabilidad", MISSING,
               "Marcas gráficas de la plantilla; no se leen como datos")
    return cortes
}

// AH84: "OBSERVACIONES\nUbicación: …\nNivel freático: …\nProfundidad final: …\n<libres>"
function parseObservations(text, header, report) {
    var free = []
    var lines = String(text || "").split("\n")
    var water = null, finalDepth = NaN
    for (var i = 0; i < lines.length; ++i) {
        var line = lines[i].trim()
        if (!line.length || /^OBSERVACIONES$/i.test(normalizeLabel(line))) continue
        var m
        if ((m = /^ubicaci[oó]n\s*:\s*(.*)$/i.exec(line))) { header.ubicacion = m[1].replace(/\.$/, "").trim(); continue }
        if ((m = /^nivel\s+fre[aá]tico\s*:\s*(.*)$/i.exec(line))) { water = m[1].trim(); continue }
        if ((m = /^profundidad\s+final\s*:\s*(\d+(?:[.,]\d+)?)/i.exec(line))) { finalDepth = decimal(m[1]); continue }
        free.push(line)
    }
    if (water === null) report.set("nivel_freatico", MISSING)
    else {
        var depth = /(\d+(?:[.,]\d+)?)/.exec(water)
        if (/^N\.?P\.?$/i.test(water.replace(/\s+/g, "")) || /no\s+(se\s+)?(encontr|present)/i.test(water)) {
            header.water_table_status = "NO_ENCONTRADO"; header.water_table_present = false
            report.set("nivel_freatico", EXACT)
        } else if (depth) {
            header.water_table_status = "ENCONTRADO"; header.water_table_present = true
            header.water_table_depth = fmt2(decimal(depth[1]))
            report.set("nivel_freatico", EXACT)
        } else report.set("nivel_freatico", AMBIGUOUS, water)
    }
    return { observaciones: free.join("\n"), finalDepth: finalDepth }
}

// Progresiva en el formato canónico de la ficha (Rules.normalizeProgresiva):
// kilómetro con al menos 2 dígitos ("0+620" -> "00+620"). Nunca se une al código.
function canonicalProgresiva(text) {
    var t = String(text || "").trim()
    var m = /^(\d{1,3})\s*\+\s*(\d{3})$/.exec(t)
    return m ? (m[1].length < 2 ? "0" + m[1] : m[1]) + "+" + m[2] : t
}

// Inversa UTM WGS84 del hemisferio sur: misma convención que Rules._utmInverse
// para una zona numérica sin banda (Web parseSheetCoordinate).
function utmSouthToGeo(x, y, zone) {
    if (!isFinite(x) || !isFinite(y) || x < 100000 || x > 900000 || y < 0 || y > 10000000) return null
    var a = 6378137, e2 = 0.0066943799901413165, k0 = 0.9996, ep2 = e2 / (1 - e2)
    x -= 500000; y -= 10000000
    var mu = (y / k0) / (a * (1 - e2/4 - 3*e2*e2/64 - 5*e2*e2*e2/256))
    var e1 = (1 - Math.sqrt(1-e2)) / (1 + Math.sqrt(1-e2))
    var fp = mu + (3*e1/2 - 27*Math.pow(e1,3)/32)*Math.sin(2*mu)
        + (21*e1*e1/16 - 55*Math.pow(e1,4)/32)*Math.sin(4*mu)
        + 151*Math.pow(e1,3)/96*Math.sin(6*mu) + 1097*Math.pow(e1,4)/512*Math.sin(8*mu)
    var sin = Math.sin(fp), cos = Math.cos(fp), tan = Math.tan(fp)
    var n = a/Math.sqrt(1-e2*sin*sin), r = a*(1-e2)/Math.pow(1-e2*sin*sin,1.5)
    var t = tan*tan, c = ep2*cos*cos, d = x/(n*k0)
    var lat = fp - n*tan/r * (d*d/2 - (5+3*t+10*c-4*c*c-9*ep2)*Math.pow(d,4)/24
        + (61+90*t+298*c+45*t*t-252*ep2-3*c*c)*Math.pow(d,6)/720)
    var lon = (d-(1+2*t+c)*Math.pow(d,3)/6+(5-2*c+28*t-3*c*c+8*ep2+24*t*t)*Math.pow(d,5)/120)/cos
    lat *= 180/Math.PI
    lon = zone*6-183 + lon*180/Math.PI
    if (!isFinite(lat) || !isFinite(lon) || lat < -80 || lat > 0 || Math.abs(lon) > 180) return null
    return { latitude: lat, longitude: lon }
}

// Zona escrita sin banda ("18", o "18S" = hemisferio sur en fichas de campo):
// la ficha exige la banda (18L). Se deriva de la propia UTM y se calculan
// lat/lon con la conversión canónica; queda marcado HEURISTIC para revisar.
function completeUtmZone(header, report) {
    var written = String(header.zona || "").trim()
    var m = /^([1-9]|[1-5][0-9]|60)\s*(?:S|SUR)?$/i.exec(written)
    if (!m) return
    var geo = utmSouthToGeo(decimal(header.utm_x), decimal(header.utm_y), Number(m[1]))
    if (!geo) return
    var band = "CDEFGHJKLMNPQRSTUVWX".charAt(Math.max(0, Math.min(19, Math.floor((geo.latitude + 80) / 8))))
    header.zona = header.utm_zone = m[1] + band
    header.latitude = geo.latitude
    header.longitude = geo.longitude
    report.set("zona", HEURISTIC, "«" + written + "» → " + m[1] + band + " (hemisferio sur)")
    report.warn("Zona «" + written + "» sin banda: se usó " + m[1] + band
                + " y la latitud/longitud calculadas desde la UTM (WGS84, hemisferio sur). Verifica el datum.")
}

// Plantilla INGEMA llenada a mano (C-AA-01): granulometría y humedad guardadas
// como fracción con formato porcentaje ("max." = 1 -> 100 %, 0.39 -> 39 %).
// Solo se convierte con esa evidencia; nunca se completan valores ausentes.
var FRACTION_KEYS = ["gmax", "g2", "g04", "g008", "g002", "hum2"]
function percentFromFractions(corte) {
    if (corte.gmax !== "1") return false
    for (var i = 0; i < FRACTION_KEYS.length; ++i) {
        var raw = corte[FRACTION_KEYS[i]]
        if (raw.length && !(decimal(raw) >= 0 && decimal(raw) <= 1)) return false
    }
    for (var k = 0; k < FRACTION_KEYS.length; ++k) {
        var key = FRACTION_KEYS[k]
        if (corte[key].length) corte[key] = String(Number((decimal(corte[key]) * 100).toFixed(2)))
    }
    return true
}

function setText(header, report, keys, value, reportKey) {
    var v = String(value || "").trim()
    if (!v.length || v === "---") { report.set(reportKey, MISSING); return "" }
    for (var i = 0; i < keys.length; ++i) header[keys[i]] = v
    report.set(reportKey, EXACT)
    return v
}

function testificacionAdapter(sheet, native) {
    var report = new Report()
    var header = {}
    var timestamp = {}
    // Nombre contractual del proyecto (AG4:BC6): contenido, nunca la carpeta.
    var project = setText(header, report, ["project_full_name", "excel_title"], sheet.text("AG4"), "projectName")
    if (project.length) timestamp.proyecto = project
    var code = setText(header, report, ["codigo", "calicata", "code"], sheet.text("AY9"), "calicataCode")
    var band = sheet.text("AG1").split("\n")
    if (band.length > 1 && band.slice(1).join("\n").trim().length) header.description = band.slice(1).join("\n").trim()
    setText(header, report, ["supervisor"], sheet.text("AJ9"), "supervisor")
    setText(header, report, ["maquina"], sheet.text("AJ10"), "maquina")
    setText(header, report, ["location", "lado_via"], sheet.text("AJ11"), "lado_via")
    setText(header, report, ["pk", "progresiva"], canonicalProgresiva(sheet.text("AT8")), "progresiva")
    var coordinate = function(ref, keys, key) {
        var t = sheet.text(ref), v = decimal(t)
        if (!t.length) { report.set(key, MISSING); return }
        if (!isFinite(v)) { report.set(key, INVALID, t); report.warn(key + ": valor no numérico «" + t + "»."); return }
        for (var i = 0; i < keys.length; ++i) header[keys[i]] = t.replace(",", ".")
        report.set(key, EXACT)
    }
    coordinate("AT9", ["utm_x", "easting"], "utm_x")
    coordinate("AT10", ["utm_y", "northing"], "utm_y")
    coordinate("AT11", ["utm_z", "altitud", "altitude_m"], "utm_z")
    setText(header, report, ["zona", "utm_zone"], sheet.text("AW10"), "zona")
    completeUtmZone(header, report)
    var start = dmyToIso(sheet.text("AU8")), end = dmyToIso(sheet.text("AU9"))
    if (start.length) { header.fecha_inicio = header.start_date = start; report.set("fecha_inicio", EXACT) }
    else report.set("fecha_inicio", MISSING)
    if (end.length) { header.fecha_fin = header.end_date = end; report.set("fecha_fin", EXACT) }
    else report.set("fecha_fin", MISSING)

    var cortes = parseStrata(sheet, report, native)
    var obs = parseObservations(sheet.text("AH84"), header, report)
    var finalDepth = obs.finalDepth
    var fin = /—\s*(\d+(?:[.,]\d+)?)\s*m/.exec(sheet.text("Q" + finRow(sheet)))
    if (!isFinite(finalDepth) && fin) finalDepth = decimal(fin[1])
    if (!isFinite(finalDepth) && cortes.length) finalDepth = decimal(cortes[cortes.length - 1].a)
    if (isFinite(finalDepth) && finalDepth > 0) {
        header.requested_depth_m = finalDepth; header.final_depth_m = finalDepth
        report.set("profundidad_final", EXACT)
    } else report.set("profundidad_final", MISSING)
    report.warn(IMAGES_WARNING)
    return { header: header, cortes: cortes, observaciones: obs.observaciones, timestamp: timestamp, report: report }
}

// ------------------------------------------------ adapter genérico (etiquetas)
var GENERIC_LABELS = [
    { keys: ["project_full_name", "excel_title"], report: "projectName", labels: ["NOMBRE DEL PROYECTO", "PROYECTO", "OBRA"] },
    { keys: ["codigo", "calicata", "code"], report: "calicataCode", labels: ["CODIGO DE CALICATA", "CALICATA", "CODIGO", "CALICATA N", "N DE CALICATA"] },
    { keys: ["pk", "progresiva"], report: "progresiva", labels: ["PROGRESIVA", "P.K", "PK", "KM"] },
    { keys: ["ubicacion"], report: "ubicacion", labels: ["UBICACION", "TRAMO"] },
    { keys: ["fecha_inicio", "start_date"], report: "fecha_inicio", labels: ["FECHA", "FECHA INICIO", "FECHA DE INICIO"], date: true },
    { keys: ["utm_x", "easting"], report: "utm_x", labels: ["ESTE", "X UTM", "COORDENADA ESTE"], number: true },
    { keys: ["utm_y", "northing"], report: "utm_y", labels: ["NORTE", "Y UTM", "COORDENADA NORTE"], number: true },
    { keys: ["utm_z", "altitud", "altitude_m"], report: "utm_z", labels: ["COTA", "Z UTM", "ALTITUD"], number: true },
    { keys: ["requested_depth_m", "final_depth_m"], report: "profundidad_final", labels: ["PROFUNDIDAD", "PROFUNDIDAD FINAL", "PROFUNDIDAD TOTAL"], number: true },
    { keys: ["supervisor"], report: "supervisor", labels: ["SUPERVISOR", "RESPONSABLE"] }
]
function labelIndex(sheet) {
    var index = {}
    var refs = sheet.refs()
    for (var i = 0; i < refs.length; ++i) {
        var label = normalizeLabel(sheet.text(refs[i]).replace(/[º°]/g, ""))
        if (label.length > 40) continue
        ;(index[label] = index[label] || []).push(parseRef(refs[i]))
    }
    return index
}
function genericLabelHits(sheet) {
    var index = labelIndex(sheet), score = 0
    for (var i = 0; i < GENERIC_LABELS.length; ++i)
        for (var k = 0; k < GENERIC_LABELS[i].labels.length; ++k)
            if (index[GENERIC_LABELS[i].labels[k]]) { score++; break }
    return { score: score, index: index }
}
function valueNear(sheet, ref) {
    for (var c = ref.col + 1; c <= ref.col + 8; ++c) {
        var t = sheet.at(ref.row, c)
        if (t.length) return t
    }
    return sheet.at(ref.row + 1, ref.col)
}
function genericAdapter(sheet) {
    var report = new Report(), header = {}, timestamp = {}
    var index = labelIndex(sheet)
    for (var i = 0; i < GENERIC_LABELS.length; ++i) {
        var spec = GENERIC_LABELS[i], found = []
        for (var k = 0; k < spec.labels.length; ++k)
            (index[spec.labels[k]] || []).forEach(function(ref) { var v = valueNear(sheet, ref); if (v.length) found.push(v) })
        var unique = found.filter(function(v, n) { return found.indexOf(v) === n })
        if (!unique.length) { report.set(spec.report, MISSING); continue }
        if (unique.length > 1) { report.set(spec.report, AMBIGUOUS, unique.join(" | ")); continue }
        var value = unique[0]
        if (spec.date) { value = dmyToIso(value); if (!value.length) { report.set(spec.report, INVALID, unique[0]); continue } }
        if (spec.number && !isFinite(decimal(value))) { report.set(spec.report, INVALID, value); continue }
        for (var j = 0; j < spec.keys.length; ++j) header[spec.keys[j]] = spec.number ? String(decimal(value)) : value
        report.set(spec.report, HEURISTIC)
    }
    if (header.project_full_name) timestamp.proyecto = header.project_full_name
    var cortes = genericStrata(sheet, report)
    report.warn(IMAGES_WARNING)
    return { header: header, cortes: cortes, observaciones: "", timestamp: timestamp, report: report }
}
// Tabla de estratos: fila de encabezado con DESDE/HASTA (o PROFUNDIDAD) y DESCRIPCIÓN.
function genericStrata(sheet, report) {
    var refs = sheet.refs(), columns = null, headerRow = 0
    for (var i = 0; i < refs.length && !columns; ++i) {
        var ref = parseRef(refs[i]); if (!ref) continue
        var cols = {}
        for (var c = 1; c <= 80; ++c) {
            var label = normalizeLabel(sheet.at(ref.row, c))
            if (label === "DESDE" || label === "DE") cols.de = c
            else if (label === "HASTA" || label === "A") cols.a = c
            else if (/^DESCRIPCION/.test(label)) cols.descripcion = c
            else if (label === "SUCS" || label === "CLASIFICACION SUCS") cols.sucs = c
            else if (label === "AASHTO" || label === "CLASIFICACION AASHTO") cols.aashto = c
        }
        if (cols.de && cols.a && cols.descripcion) { columns = cols; headerRow = ref.row }
    }
    var cortes = []
    if (columns) {
        for (var row = headerRow + 1; row <= headerRow + 400 && cortes.length < MAX_STRATA; ++row) {
            var de = decimal(sheet.at(row, columns.de)), a = decimal(sheet.at(row, columns.a))
            if (!isFinite(de) || !isFinite(a)) { if (cortes.length) break; else continue }
            cortes.push({ de: fmt2(de), a: fmt2(a), descripcion: sheet.at(row, columns.descripcion),
                          sucs: columns.sucs ? sheet.at(row, columns.sucs) : "",
                          aashto: columns.aashto ? sheet.at(row, columns.aashto) : "",
                          material_origin: "", tipo_muestra: "", tipo_otro: "", muestra_desde: "", muestra_hasta: "",
                          resultados: "", gmax: "", g2: "", g04: "", g008: "", g002: "", wl: "", lp: "", hum2: "",
                          humedad: -1, excavabilidad: -1, estabilidad: -1 })
        }
    }
    report.set("cortes", cortes.length ? HEURISTIC : MISSING, cortes.length + " estrato(s)")
    return cortes
}

// ---------------------------------------------------------------- validador
function validateDraft(draft, report) {
    var errors = []
    var code = String(draft.header.codigo || "").trim()
    var project = String(draft.header.project_full_name || "").trim()
    if (!code.length && !project.length) errors.push("Sin código de calicata ni nombre de proyecto.")
    var previous = 0
    for (var i = 0; i < draft.cortes.length; ++i) {
        var de = decimal(draft.cortes[i].de), a = decimal(draft.cortes[i].a)
        if (!isFinite(de) || !isFinite(a) || a <= de) { errors.push("Estrato " + (i + 1) + ": intervalo inválido."); continue }
        if (Math.abs(de - previous) > 0.011)
            report.warn("Estrato " + (i + 1) + ": no continúa al anterior (" + fmt2(previous) + " → " + fmt2(de) + " m).")
        previous = a
    }
    return errors
}

// ---------------------------------------------------------------- servicio
// workbook: resultado de ExcelExporter.readWorkbookCells(path).
// source:   { fileId, path, folderPath, folderId, name } — solo metadatos de
//           origen/destino; nunca alimentan el contenido de la ficha.
function importWorkbook(workbook, source) {
    source = source || {}
    if (!workbook || workbook.ok !== true)
        return { status: STATUS_FAILED, message: String((workbook && workbook.error) || "No se pudo leer el Excel.") }
    var detected = detectTemplate(workbook)
    if (!detected)
        return { status: STATUS_NOT_RECOGNIZED, message: NOT_RECOGNIZED_MESSAGE }
    var draft = detected.family === "TESTIFICACION"
            ? testificacionAdapter(detected.sheet, detected.adapter === "InGePlusExcelAdapter")
            : genericAdapter(detected.sheet)
    var report = draft.report
    var errors = validateDraft(draft, report)
    // Formato genérico: exige al menos código + (proyecto o estratos) para no
    // crear una ficha basura a partir de un libro cualquiera.
    if (detected.family === "GENERIC" && (!draft.header.codigo || (!draft.header.project_full_name && !draft.cortes.length)))
        errors.push("Datos insuficientes en un formato no reconocido.")
    if (errors.length)
        return { status: STATUS_NOT_RECOGNIZED, message: NOT_RECOGNIZED_MESSAGE, errors: errors,
                 adapter: detected.adapter, report: { fields: report.fields, warnings: report.warnings } }
    var meta = {
        adapter: detected.adapter, template: detected.family, score: detected.score, sheet: detected.sheet.name,
        sourceFileId: String(source.fileId || ""), sourcePath: String(source.path || workbook.path || ""),
        sourceName: String(source.name || workbook.fileName || ""), sourceFolderPath: String(source.folderPath || ""),
        sourceHash: String(workbook.sha256 || ""), importedAt: new Date().toISOString()
    }
    draft.header.import_source = meta
    withLocalIdentity(draft.cortes)
    return {
        status: STATUS_OK, adapter: detected.adapter, template: detected.family,
        state: { header: draft.header, cortes: draft.cortes, observaciones: draft.observaciones, timestamp: draft.timestamp },
        report: { fields: report.fields, warnings: report.warnings }, source: meta
    }
}

// Mismo archivo ya importado (hash o id de origen) en los borradores dados.
function findDuplicate(drafts, source) {
    var list = drafts || []
    for (var i = 0; i < list.length; ++i) {
        var meta = (list[i] && list[i].importSource) || {}
        if ((source.sourceHash && meta.sourceHash === source.sourceHash)
                || (source.sourceFileId && meta.sourceFileId === source.sourceFileId))
            return list[i]
    }
    return null
}

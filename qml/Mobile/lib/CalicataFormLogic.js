.pragma library
.import "CalicataRules.js" as Rules

// Lógica de dominio de la ficha de Calicatas, extraída de CalicataFormPage.qml
// (Visual Zero, 2026-10-10). Sin interfaz: recibe datos planos (filas de estratos,
// cabecera) y devuelve resultados. Las reglas geotécnicas siguen en CalicataRules.js;
// aquí está la aplicación de esas reglas a la ficha completa.

var HUMIDITY_LABELS = ["Seco", "Bajo", "Medio", "Agua"]
var EXCAVABILITY_LABELS = ["Rend. bajo", "Rend. medio", "Rend. alto", "Rend. muy alto"]
var STABILITY_LABELS = ["Baja", "Media", "Alta", "Muy Alta"]

function newUuid() {
    return "xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx".replace(/[xy]/g, function(c) {
        var r = Math.random() * 16 | 0
        return (c === "x" ? r : (r & 0x3 | 0x8)).toString(16)
    })
}

function enumIndex(value, labels) {
    var numeric = Number(value)
    if (value !== "" && value !== undefined && value !== null && isFinite(numeric) && numeric >= 0 && numeric < labels.length)
        return Math.floor(numeric)
    var wanted = String(value || "").trim().toLowerCase()
    for (var i = 0; i < labels.length; ++i) {
        if (String(labels[i]).toLowerCase() === wanted)
            return i
    }
    return -1
}

function hasText(x) { return x !== undefined && x !== null && String(x).trim().length > 0 }

// ---------------------------------------------------------------- estratos

function defaultCorte(uuidFn) {
    var uuid = uuidFn || newUuid
    return {
        id: "stratum-" + Date.now() + "-" + Math.random().toString(36).slice(2),
        material_origin: "",
        _extraJson: JSON.stringify({ local_stratum_id: uuid() }),
        _percentageFieldsJson: "[]",
        remote_sample_id: "",
        sample_code: "",
        descripcion: "",
        humedad: -1,
        excavabilidad: -1,
        estabilidad: -1,
        tipoText: "",
        tipo_muestra: "",
        tipo_otro: "",
        de: "",
        a: "",
        muestra_desde: "",
        muestra_hasta: "",
        resultados: "",
        aashto: "",
        sucs: "",
        gmax: "",
        g2: "",
        g04: "",
        g008: "",
        g002: "",
        wl: "",
        lp: "",
        hum2: ""
    }
}

// Fila plana estable a partir de un estrato guardado (o heredado). `options`:
// newUuid() para identidades nuevas y onAssignedIdentity() cuando un estrato
// heredado sin identidad remota recibe una local (se persiste en el autosave).
function normalizeCorte(x, options) {
    var opts = options || {}
    var uuid = opts.newUuid || newUuid
    var input = (x && typeof x === "object") ? x : {}
    var o = Object.assign({}, JSON.parse(input._extraJson || "{}"), input)
    delete o._extraJson
    var d = defaultCorte(uuid)
    // Los nulos conservan el valor tipado por defecto; listas/objetos anidados
    // viven solo en _extraJson (corteToPlainObject los restaura).
    var r = Object.assign({}, d)
    for (var key in o)
        if (o[key] !== null && o[key] !== undefined && typeof o[key] !== "object") r[key] = o[key]
    if (!o.local_stratum_id) {
        o.local_stratum_id = o.remote_stratum_id || uuid()
        if (!o.remote_stratum_id && typeof opts.onAssignedIdentity === "function") opts.onAssignedIdentity()
    }
    r.local_stratum_id = String(o.local_stratum_id)
    r.remote_sample_id = String(o.remote_sample_id || "")
    r.sample_code = String(o.sample_code || "")
    r._extraJson = JSON.stringify(o)
    r._percentageFieldsJson = JSON.stringify(o.percentage_fields || [])
    // "A1a", "A 2 4"… -> código canónico; un valor desconocido se conserva tal cual.
    r.aashto = Rules.normalizeAashtoCode(r.aashto) || String(r.aashto || "")
    r.humedad = enumIndex(r.humedad, HUMIDITY_LABELS)
    r.excavabilidad = enumIndex(r.excavabilidad, EXCAVABILITY_LABELS)
    r.estabilidad = enumIndex(r.estabilidad, STABILITY_LABELS)
    r.de = (r.de === undefined || r.de === null) ? "" : String(r.de)
    r.a  = (r.a  === undefined || r.a  === null) ? "" : String(r.a)
    var legacyType = String(o.tipo_muestra || o.muestra || o.tipoText || "").trim()
    var legacyTypeUpper = legacyType.toUpperCase()
    if (["MA", "MS", "MI", "MW"].indexOf(legacyTypeUpper) >= 0) {
        r.tipo_muestra = legacyTypeUpper
    } else if (legacyType.length && !String(r.tipo_muestra || "").length) {
        r.tipo_muestra = "Otro"
        r.tipo_otro = legacyType
    }
    r.muestra_desde = (o.muestra_desde !== undefined && o.muestra_desde !== null)
            ? String(o.muestra_desde) : r.de
    r.muestra_hasta = (o.muestra_hasta !== undefined && o.muestra_hasta !== null)
            ? String(o.muestra_hasta) : r.a
    r.resultados = String(o.resultados || o.resultado || "")
    r.g002 = String(o.g002 || o.g2micra || o.g2_micra || "")
    return r
}

// Estrato canónico (persistencia, sincronización y Excel) a partir de una fila.
function corteToPlainObject(row) {
    var source = (row && typeof row === "object") ? row : {}
    return Object.assign({}, JSON.parse(source._extraJson || "{}"), {
        id: String(source.id || ""),
        material_origin: String(source.material_origin || ""),
        ip: JSON.parse(source._extraJson || "{}").nonplastic_confirmed === true ? "NP" : Rules.plasticityIndex(source.wl, source.lp),
        percentage_fields: JSON.parse(source._percentageFieldsJson || "[]"),
        descripcion: String(source.descripcion || ""),
        humedad: isFinite(Number(source.humedad)) ? Number(source.humedad) : -1,
        excavabilidad: isFinite(Number(source.excavabilidad)) ? Number(source.excavabilidad) : -1,
        estabilidad: isFinite(Number(source.estabilidad)) ? Number(source.estabilidad) : -1,
        tipoText: String(source.tipo_muestra === "Otro"
                         ? (source.tipo_otro || "") : (source.tipo_muestra || "")),
        tipo_muestra: String(source.tipo_muestra || ""),
        tipo_otro: String(source.tipo_otro || ""),
        de: String(source.de === undefined || source.de === null ? "" : source.de),
        a: String(source.a === undefined || source.a === null ? "" : source.a),
        muestra_desde: source.tipo_muestra || source.tipoText || source.sample_code || source.remote_sample_id
                      ? Rules.sampleIntervalValue(source, "muestra_desde") : String(source.muestra_desde || ""),
        muestra_hasta: source.tipo_muestra || source.tipoText || source.sample_code || source.remote_sample_id
                      ? Rules.sampleIntervalValue(source, "muestra_hasta") : String(source.muestra_hasta || ""),
        resultados: String(source.resultados || ""),
        aashto: String(source.aashto || ""),
        sucs: String(source.sucs || ""),
        gmax: String(source.gmax === undefined || source.gmax === null ? "" : source.gmax),
        g2: String(source.g2 === undefined || source.g2 === null ? "" : source.g2),
        g04: String(source.g04 === undefined || source.g04 === null ? "" : source.g04),
        g008: String(source.g008 === undefined || source.g008 === null ? "" : source.g008),
        g002: String(source.g002 === undefined || source.g002 === null ? "" : source.g002),
        wl: String(source.wl === undefined || source.wl === null ? "" : source.wl),
        lp: String(source.lp === undefined || source.lp === null ? "" : source.lp),
        hum2: String(source.hum2 === undefined || source.hum2 === null ? "" : source.hum2)
    })
}

function rowHasMeaningfulData(r) {
    if (!r) return false
    return hasText(r.descripcion) || hasText(r.tipo_muestra) || hasText(r.tipo_otro) ||
           hasText(r.a) || hasText(r.aashto) || hasText(r.sucs) ||
           hasText(r.muestra_desde) || hasText(r.muestra_hasta) || hasText(r.resultados) ||
           hasText(r.gmax) || hasText(r.g2) || hasText(r.g04) || hasText(r.g008) ||
           hasText(r.g002) ||
           hasText(r.wl) || hasText(r.lp) || hasText(r.hum2)
}

// ---------------------------------------------------------------- profundidades

function parseDepthText(s) { return Rules.parseDecimalSafe(s) }

function fmtDepth(v) { return (Math.round(v * 100) / 100).toFixed(2) }

function parseLooseNumber(value) {
    return Rules.parseDecimalSafe(String(value === undefined || value === null ? "" : value)
        .replace(/m\s*s\.?\s*n\.?\s*m\.?/gi, "").replace("%", "").trim())
}

// Renumeración de intervalos (regla de PC): DE automático desde el A anterior,
// A normalizado a 2 decimales en múltiplos de 0.05 m; un intervalo inválido rompe
// la cadena y se conserva para corregirlo (nunca se recorta ni se borra).
// Trabaja sobre copias de las filas; devuelve las filas resultantes, los cambios
// por fila y las derivadas (profundidad total, nivel freático de los estratos).
function renumberIntervals(rows) {
    var out = []
    var changes = []
    for (var c = 0; c < rows.length; ++c) out.push(Object.assign({}, rows[c]))
    var setProp = function(i, key, value) {
        out[i][key] = value
        changes.push({ index: i, key: key, value: value })
    }
    var prevA = 0.0
    var prevKnown = true
    var maxA = 0.0
    for (var i = 0; i < out.length; ++i) {
        var row = out[i]
        var previousDe = String(row.de || "")
        var deTxt = prevKnown ? fmtDepth(prevA) : ""
        if (String(row.de || "") !== deTxt)
            setProp(i, "de", deTxt)
        var inherited = Rules.inheritSampleInterval(row, previousDe, row.a)
        for (var key in inherited) setProp(i, key, inherited[key])
        if (!prevKnown) continue
        var aRaw = ((row.a || "") + "").trim()
        var aVal = parseDepthText(aRaw)
        if (!aRaw.length || isNaN(aVal)) {
            prevKnown = false
            continue
        }
        if (aVal <= prevA || Math.abs(aVal * 20 - Math.round(aVal * 20)) > 0.000001) {
            prevKnown = false
            continue
        }
        aVal = Math.round(aVal * 100) / 100
        var aTxt = fmtDepth(aVal)
        if ((row.a || "") !== aTxt)
            setProp(i, "a", aTxt)
        prevA = aVal
        maxA = Math.max(maxA, aVal)
    }
    return {
        rows: out,
        changes: changes,
        totalDepthM: maxA,
        strataGroundwaterDepth: Rules.strataDerived(out).groundwaterDepth
    }
}

function derivedDepthText(totalDepthM) { return totalDepthM > 0 ? totalDepthM.toFixed(3) : "" }

// Nivel freático derivado: el primer estrato con humedad "Agua".
function derivedGroundwater(rows) {
    var strata = []
    for (var i = 0; i < rows.length; ++i) {
        var row = rows[i]
        strata.push({ moistureCondition: Number(row.humedad) === 3 ? "AGUA" : "",
                      fromDepthM: String(row.de || "") })
    }
    return Rules.derivedGroundwaterDepth(strata)
}

// ---------------------------------------------------------------- perfil

// Espesores por grupo a partir de los intervalos válidos.
function profileStats(rows) {
    var stats = { anthropicCount: 0, anthropicThickness: 0, total: 0,
                  coarse: 0, silt: 0, clay: 0, organic: 0, classified: 0 }
    for (var i = 0; i < rows.length; ++i) {
        var row = rows[i]
        var from = Rules.parseDecimalSafe(row.de), to = Rules.parseDecimalSafe(row.a)
        var thickness = isFinite(from) && isFinite(to) && to > from ? to - from : 0
        stats.total += thickness
        if (Rules.isAnthropicFill(row.material_origin)) {
            stats.anthropicCount++
            stats.anthropicThickness += thickness
            continue
        }
        var code = Rules.labProjection(corteToPlainObject(row)).primary
        if (!code.length) continue
        stats.classified += thickness
        if (/^[GS]/.test(code)) stats.coarse += thickness
        if (/^(O|PT)/.test(code)) stats.organic += thickness
        if (/(^|-)(M|GM|SM)/.test(code) || /^ML|^MH/.test(code)) stats.silt += thickness
        if (/(^|-)(C|GC|SC)/.test(code) || /^CL|^CH/.test(code)) stats.clay += thickness
    }
    return stats
}

function suggestedGeneralClass(s) {
    if (s.total <= 0) return ""
    if (s.anthropicThickness / s.total >= 0.5) return "Perfil con relleno antrópico"
    if (s.classified <= 0) return ""
    if (s.organic / s.classified >= 0.4) return "Perfil orgánico"
    var coarseShare = s.coarse / s.classified
    if (coarseShare >= 0.7)
        return s.clay > s.silt ? "Perfil granular con arcilla"
             : s.silt > 0 ? "Perfil granular con limo" : "Perfil granular"
    if (coarseShare <= 0.3) return s.clay > s.silt ? "Perfil fino arcilloso" : "Perfil fino limoso"
    return "Perfil mixto / heterogéneo"
}

function waterDepthValue(groundwaterText) {
    var value = String(groundwaterText || "").trim()
    return value.length ? Rules.parseDecimalSafe(value) : NaN
}

function profileInterpretation(strataCount, stats, totalDepthM, waterDepth) {
    if (!strataCount) return ""
    var s = stats
    var parts = []
    parts.push("Perfil de " + Math.max(totalDepthM, 0).toFixed(2) + " m con " + strataCount
               + (strataCount === 1 ? " estrato." : " estratos."))
    if (s.anthropicCount > 0)
        parts.push("Relleno antrópico en " + s.anthropicThickness.toFixed(2) + " m de espesor.")
    var groups = [{ label: "material granular", value: s.coarse }, { label: "limos", value: s.silt },
                  { label: "arcillas", value: s.clay }, { label: "suelos orgánicos", value: s.organic }]
    groups.sort(function(x, y) { return y.value - x.value })
    if (groups[0].value > 0) parts.push("Predominio de " + groups[0].label + ".")
    parts.push(isFinite(waterDepth) ? "Nivel freático a " + waterDepth.toFixed(2) + " m."
                                    : "Sin nivel freático registrado.")
    return parts.join(" ")
}

// ---------------------------------------------------------------- laboratorio

// SUCS confirmado: primario/secundario coherentes con el código heredado.
function labAuthority(extra) {
    var legacy = String(extra.lab_confirmed_sucs || "").trim().toUpperCase()
    if (!String(extra.primary_sucs || "").length && legacy.length) {
        var parts = legacy.split("-")
        extra.primary_sucs = Rules.webSucsCodes.indexOf(parts[0]) >= 0 ? parts[0] : ""
        extra.secondary_sucs = parts.length > 1 && Rules.webSucsCodes.indexOf(parts[1]) >= 0 ? parts[1] : ""
        extra.is_composite = extra.primary_sucs.length > 0 && extra.secondary_sucs.length > 0
    }
    var primary = String(extra.primary_sucs || "").toUpperCase(), secondary = String(extra.secondary_sucs || "").toUpperCase()
    extra.lab_confirmed_sucs = primary.length
        ? primary + (extra.is_composite === true && secondary.length && secondary !== primary ? "-" + secondary : "") : ""
    return extra
}

// Validación Web, identidad y revisión de laboratorio de UN estrato. Devuelve el
// _extraJson resultante (igual al de entrada si no hay cambios).
function deriveLabExtraJson(row, uuidFn) {
    var uuid = uuidFn || newUuid
    var extra = labAuthority(JSON.parse(row._extraJson || "{}"))
    var review = Rules.webLabValidate(row, extra)
    extra.web_lab_valid = review.valid
    extra.web_lab_errors = review.errors
    extra.web_lab_projection = review.projection
    // Identidad del laboratorio = UUID del estrato (remoto si existe), nunca la posición.
    if (!extra.local_stratum_id) extra.local_stratum_id = extra.remote_stratum_id || uuid()
    var form = Rules.labForm(row, extra), web = Rules.reviewLaboratorySample(form)
    extra.web_lab_review = {
        status: Rules.laboratoryReviewStatus(form, web),
        ip: web.ip === null ? "" : String(web.ip),
        aashto: web.aashto, sucs: web.sucs, observations: web.observations
    }
    return JSON.stringify(extra)
}

// ---------------------------------------------------------------- fechas

function parseDMY(s) {
    if (!s || s.indexOf("/") === -1) return null
    var p = s.split("/")
    if (p.length !== 3) return null
    var dd = parseInt(p[0], 10)
    var mm = parseInt(p[1], 10) - 1
    var yy = parseInt(p[2], 10)
    if (isNaN(dd) || isNaN(mm) || isNaN(yy)) return null
    var dt = new Date(yy, mm, dd)
    // valida fecha real (evita 32/13/2025)
    if (dt.getFullYear() !== yy || dt.getMonth() !== mm || dt.getDate() !== dd) return null
    return dt
}

function dmyToIso(dmy) {
    var d = parseDMY(dmy)
    if (!d) return ""
    var mm = (d.getMonth() + 1); if (mm < 10) mm = "0" + mm
    var dd = d.getDate();        if (dd < 10) dd = "0" + dd
    return d.getFullYear() + "-" + mm + "-" + dd
}

function isoToDMY(iso) {
    return iso && iso.length >= 10 ? iso.substring(8, 10) + "/" + iso.substring(5, 7) + "/" + iso.substring(0, 4) : ""
}

// ---------------------------------------------------------------- cabecera y estado

// Cabecera canónica de la ficha (alias Web + legados para Excel). `input`:
//   baseHeader: cabecera guardada (se conservan sus campos: excel_title, pk...)
//   fields: { code, pk, projectFullName, supervisor, maquina, ubicacion,
//             utm_x, utm_y, utm_z, zona, fechaInicio (dd/mm/aaaa), fechaFin }
//   requestedDepthM, totalDepthM, roadSide, profileSetup,
//   groundwaterText (efectivo), groundwaterCustom
function canonicalHeader(input) {
    var baseHeader = input.baseHeader || {}
    var f = input.fields || {}
    var code = String(f.code || "").trim()
    var pk = String(f.pk || "").trim()
    var projectFullName = String(f.projectFullName || "").trim()
    // Si el campo local está vacío se conserva el nombre contractual guardado.
    if (!projectFullName.length)
        projectFullName = String(baseHeader.project_full_name || "").trim()
    var h = Object.assign({}, baseHeader, {
        supervisor: String(f.supervisor || ""),
        maquina:    String(f.maquina || ""),
        codigo:     code,
        calicata:   code,
        pk:         pk,
        progresiva: pk,
        ubicacion:  String(f.ubicacion || ""),
        utm_x:      String(f.utm_x || ""),
        utm_y:      String(f.utm_y || ""),
        utm_z:      String(f.utm_z || ""),
        altitud:    String(f.utm_z || ""),
        zona:       String(f.zona || ""),
        project_full_name: projectFullName,
        depth_max_m: null, // Sin tope; no serializar Infinity.
        requested_depth_m: input.requestedDepthM,
        final_depth_m: input.totalDepthM
    })
    h.code = code
    h.title = String(h.title || "").trim()
    // calicatas.location = lado de la vía. `ubicacion` (tramo) queda local.
    h.location = String(input.roadSide || "").trim()
    h.lado_via = h.location
    h.easting = String(h.utm_x || "").trim()
    h.northing = String(h.utm_y || "").trim()
    h.altitude_m = String(h.utm_z || "").trim()
    h.depth_m = derivedDepthText(input.totalDepthM)
    h.profile_setup = Object.assign({}, input.profileSetup || {})
    var water = String(input.groundwaterText || "")
    var previousWater = String(baseHeader.water_table_status || "")
    h.groundwater_custom = input.groundwaterCustom === true
    h.water_table_depth = water
    h.groundwater_depth_m = water
    h.water_table_present = water.length > 0
    h.water_table_status = water.length ? "ENCONTRADO"
            : previousWater === "NO_ENCONTRADO" ? "NO_ENCONTRADO" : "NO_EVALUADO"
    // utm_zone numérico 1..60; `zona` conserva la banda local ("18L").
    var zoneMatch = /^(\d{1,2})\s*[C-HJ-NP-X]?$/i.exec(String(h.zona || "").trim())
    var zoneNumber = zoneMatch ? Number(zoneMatch[1]) : 0
    h.utm_zone = zoneNumber >= 1 && zoneNumber <= 60 ? zoneNumber : null
    h.machine = String(h.maquina || "").trim()
    h.description = String(h.description || "").trim()
    h.fecha_inicio = dmyToIso(f.fechaInicio)
    h.fecha_fin    = dmyToIso(f.fechaFin)
    h.start_date = h.fecha_inicio
    h.end_date = h.fecha_fin
    h.hora_inicio = Rules.normalizeOptionalTime(h.hora_inicio) || ""
    h.start_time = h.hora_inicio
    return h
}

// Estado exportable completo (persistencia local, sincronización y Excel).
function exportState(header, rows, observaciones, doc, view) {
    var cortes = []
    for (var i = 0; i < rows.length; ++i)
        cortes.push(corteToPlainObject(rows[i]))
    var v = view || {}
    return {
        header: header,
        uiState: Object.assign({}, (doc ? (doc.uiState || {}) : {}), {
            calicatasView: { stageSchema: 2, stage: v.stage, selectedStratum: v.selectedStratum,
                             photoCategory: v.photoCategory,
                             validation: { reviewed: v.reviewed, issues: v.issues } }
        }),
        cortes: cortes,
        observaciones: observaciones,
        timestamp: Object.assign({}, (doc ? (doc.timestamp || {}) : {})),
        images: Object.assign({}, (doc ? (doc.images || {}) : {}))
    }
}

// ---------------------------------------------------------------- coordenadas

// Cambio de datum (WGS84 <-> PSAD56) de la cabecera. `utmFields` = { x, y, zone }
// con los valores UTM vigentes. Devuelve { header, utm, reread }:
//   utm: { x, y, zone } transformados (null si no aplica);
//   reread: true si, sin datum previo, las UTM existentes pasan a leerse en el nuevo.
function changeDatum(header, newDatum, utmFields) {
    var h = Object.assign({}, header)
    var oldDatum = String(h.datum || "")
    var known = oldDatum === "WGS84" || oldDatum === "PSAD56"
    if (!known || !(newDatum === "WGS84" || newDatum === "PSAD56") || newDatum === oldDatum) {
        h.datum = newDatum
        return { header: h, utm: null, reread: !known }
    }
    var u = utmFields || {}
    var lat = Rules.parseDecimalSafe(h.latitude), lon = Rules.parseDecimalSafe(h.longitude)
    if (!isFinite(lat) || !isFinite(lon)) {
        var geo = Rules.utmToGeoForDatum(u.x, u.y, u.zone, oldDatum)
        if (geo) { lat = geo.latitude; lon = geo.longitude }
    }
    var utm = isFinite(lat) && isFinite(lon) ? Rules.geoToUtmForDatum(lat, lon, newDatum) : null
    h.datum = newDatum
    if (!utm) return { header: h, utm: null, reread: false }
    // Contrato de zona existente: se conserva la forma usada (con o sin banda).
    var zone = String(u.zone || "").trim()
    var zoneText = /[C-HJ-NP-X]$/i.test(zone) || !zone.length ? String(utm.zone) + utm.band : String(utm.zone)
    var x = utm.easting.toFixed(2), y = utm.northing.toFixed(2)
    h.utm_x = x
    h.utm_y = y
    h.zona = zoneText
    h.latitude = lat
    h.longitude = lon
    return { header: h, utm: { x: x, y: y, zone: zoneText }, reread: false }
}

function photoGeoFromUtm(meta, datum) {
    if (!meta) return null
    var g = Rules.utmToGeoForDatum(meta.easting, meta.northing, meta.zone, String(datum || ""))
    return g && isFinite(g.latitude) && isFinite(g.longitude) ? g : null
}

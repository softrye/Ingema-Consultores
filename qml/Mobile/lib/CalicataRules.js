.pragma library

// An unedited sample uses its stratum interval. A manual subinterval remains explicit.
function sampleIntervalValue(row, key) {
    row = row || {}
    var value = row[key]
    if (value !== undefined && value !== null && String(value).trim().length)
        return String(value)
    var boundary = row[key === "muestra_desde" ? "de" : "a"]
    return boundary === undefined || boundary === null ? "" : String(boundary)
}

function inheritSampleInterval(row, previousDe, previousA) {
    row = row || {}
    if (!row.tipo_muestra && !row.tipoText && !row.sample_code && !row.remote_sample_id
            && !row.muestra_desde && !row.muestra_hasta) return {}
    var result = {}
    var fields = ["muestra_desde", "muestra_hasta"]
    var previous = [previousDe, previousA]
    var boundaries = [row.de, row.a]
    for (var i = 0; i < fields.length; ++i) {
        var raw = row[fields[i]]
        var value = parseDecimalSafe(raw), old = parseDecimalSafe(previous[i])
        var follows = raw === undefined || raw === null || !String(raw).trim().length
                      || (isFinite(value) && isFinite(old) && Math.abs(value - old) < 0.000001)
        result[fields[i]] = follows ? String(boundaries[i] === undefined || boundaries[i] === null ? "" : boundaries[i])
                                   : String(raw)
    }
    return result
}

// P3: pure entity operations; laboratory and remote identity travel with the row.
function strataDerived(rows) {
    var previous = 0, depth = 0, water = null, from = [], thickness = []
    for (var i = 0; i < rows.length; ++i) {
        from.push(isFinite(previous) ? previous.toFixed(2) : "")
        var end = parseDecimalSafe(rows[i].a)
        var valid = isFinite(previous) && isFinite(end) && end > previous
                && Math.abs(end * 20 - Math.round(end * 20)) < 0.000001
        thickness.push(valid ? (end - previous).toFixed(2) : "")
        if (water === null && isFinite(previous)
                && (rows[i].moisture_condition === "AGUA" || Number(rows[i].humedad) === 3))
            water = previous.toFixed(2)
        if (valid) depth = end
        previous = valid ? end : NaN
    }
    return {from:from, thickness:thickness, depth:depth, groundwaterDepth:water}
}

function moveStratumEntities(rows, source, target) {
    if (source < 0 || target < 0 || source >= rows.length || target >= rows.length) return null
    var derived = strataDerived(rows), copies = [], sizes = []
    for (var i = 0; i < rows.length; ++i) {
        if (!derived.thickness[i]) return null
        copies.push(JSON.parse(JSON.stringify(rows[i])))
        sizes.push(Math.round(Number(derived.thickness[i]) * 100))
    }
    copies.splice(target, 0, copies.splice(source, 1)[0])
    sizes.splice(target, 0, sizes.splice(source, 1)[0])
    var cm = 0
    for (i = 0; i < copies.length; ++i) {
        var oldFrom = parseDecimalSafe(copies[i].de)
        copies[i].de = (cm / 100).toFixed(2)
        // Preserve the sample's offset within its own entity.
        for (var j = 0; j < 2; ++j) {
            var key = j ? "muestra_hasta" : "muestra_desde"
            var sample = parseDecimalSafe(copies[i][key])
            if (isFinite(sample) && isFinite(oldFrom)) copies[i][key] = (sample - oldFrom + cm / 100).toFixed(2)
        }
        cm += sizes[i]
        copies[i].a = (cm / 100).toFixed(2)
    }
    return copies
}

// Decimal input is locale independent. Never strip punctuation or parse a prefix.
var DEPTH_METERS = "depth"
var PERCENTAGE = "percentage"
var COORDINATE = "coordinate"
var ELEVATION = "elevation"
var INTEGER = "integer"
var FREE_TEXT = "text"
var CHAINAGE_PK = "chainage"
var sucsCodes = ["GW", "GP", "GM", "GC", "SW", "SP", "SM", "SC",
    "ML", "CL", "OL", "MH", "CH", "OH", "Pt", "CL-ML", "GW-GM", "GW-GC",
    "GP-GM", "GP-GC", "SW-SM", "SW-SC", "SP-SM", "SP-SC", "GC-GM", "SC-SM", "GM-GC"]
var aashtoCodes = ["A-1-a", "A-1-b", "A-2-4", "A-2-5", "A-2-6", "A-2-7",
    "A-3", "A-4", "A-5", "A-6", "A-7-5", "A-7-6"]
// "A1a", "A-1-A", "A 1 a", "A1-b", "A 2 4", "A-2 4" -> código canónico; "" si no
// es un grupo AASHTO del catálogo (nunca se infiere desde SUCS).
function normalizeAashtoCode(text) {
    var compact = String(text || "").replace(/[\s_-]/g, "").toUpperCase()
    var m = /^A([1-7])([0-9AB])?$/.exec(compact)
    if (!m) return ""
    var suffix = m[2] ? "-" + (/[AB]/.test(m[2]) ? m[2].toLowerCase() : m[2]) : ""
    var code = "A-" + m[1] + suffix
    return aashtoCodes.indexOf(code) >= 0 ? code : ""
}
// Índice de Grupo (AASHTO M 145): IG = (F-35)[0.2+0.005(LL-40)] + 0.01(F-15)(IP-10),
// F = % pasa Nº 200. A-1, A-3, A-2-4, A-2-5: 0. A-2-6/A-2-7: solo el término del IP.
// Resultado redondeado; negativo -> 0. Sin datos -> null (nunca se inventa).
// Índice de grupo AASHTO M 145 con los mismos topes que Web (soilClassification.ts).
function aashtoGroupIndex(code, fines, liquidLimit, plasticityIndex) {
    if (!code || fines === null || fines === undefined || !isFinite(fines)) return null
    if (code === "A-1-a" || code === "A-1-b" || code === "A-3" || code === "A-2-4" || code === "A-2-5") return 0
    if (plasticityIndex === null || plasticityIndex === undefined || !isFinite(plasticityIndex)) return null
    var partial = 0.01 * Math.max(0, Math.min(40, fines - 15)) * Math.max(0, Math.min(20, plasticityIndex - 10))
    if (code === "A-2-6" || code === "A-2-7") return Math.max(0, Math.round(partial))
    if (liquidLimit === null || liquidLimit === undefined || !isFinite(liquidLimit)) return null
    var first = Math.max(0, Math.min(40, fines - 35)) * (0.2 + 0.005 * Math.max(0, Math.min(20, liquidLimit - 40)))
    return Math.max(0, Math.round(first + partial))
}

function parseDecimalSafe(value) {
    var text = String(value === undefined || value === null ? "" : value).trim()
    if (!/^[+-]?(?:\d+(?:[.,]\d*)?|[.,]\d+)$/.test(text)) return NaN
    var number = Number(text.replace(",", "."))
    return isFinite(number) ? number : NaN
}
function normalizeDecimalText(value, kind, allowNP) {
    var text = String(value === undefined || value === null ? "" : value).trim()
    if (kind === FREE_TEXT || kind === CHAINAGE_PK || !text.length) return text
    if (allowNP && /^(NP|no pl[aá]stico)$/i.test(text)) return "NP"
    var number = parseDecimalSafe(text)
    if (!isFinite(number)) return null
    if (kind === INTEGER) return Math.floor(number) === number ? String(number) : null
    return text.replace(",", ".")
}
function validateDecimalRange(value, minimum, maximum) {
    var number = parseDecimalSafe(value)
    return isFinite(number) && number >= minimum && number <= maximum
}
function plasticityIndex(wl, lp) {
    if (/^NP$/i.test(String(wl)) || /^NP$/i.test(String(lp))) return "NP"
    var a = parseDecimalSafe(wl), b = parseDecimalSafe(lp)
    return isFinite(a) && isFinite(b) && a >= b ? (a - b).toFixed(2) : ""
}
function canonicalSucs(text) {
    var value = String(text || "").trim().toUpperCase()
    for (var i = 0; i < sucsCodes.length; ++i)
        if (sucsCodes[i].toUpperCase() === value) return sucsCodes[i]
    return ""
}
function patternCodes(text) {
    var code = canonicalSucs(text)
    return code ? code.split("-") : []
}
// Graphical patterns are independent of the laboratory classification. Explicit
// empty secondary values must survive restore (never revive a legacy second).
function selectedPatternCodes(row) {
    var legacy = patternCodes(row.sucs)
    var primary = row.pattern_primary !== undefined ? row.pattern_primary : legacy[0]
    var secondary = row.pattern_secondary !== undefined ? row.pattern_secondary : legacy[1]
    var out = [], a = canonicalSucs(primary), b = canonicalSucs(secondary)
    if (a && a.indexOf('-') < 0) out.push(a)
    if (b && b.indexOf('-') < 0 && b !== a && out.length) out.push(b)
    return out
}
function compatibleSecondary(primary) {
    var canonical = canonicalSucs(primary)
    var result = []
    for (var i = 0; i < sucsCodes.length; ++i) {
        var parts = sucsCodes[i].split("-")
        if (parts.length === 2 && parts[0] === canonical) result.push(parts[1])
    }
    return result
}
function boundaryError(rows, index, value, maximum) {
    var to = parseDecimalSafe(value)
    var from = index > 0 ? parseDecimalSafe(rows[index - 1].a) : 0
    if (!isFinite(to)) return "Hasta: ingresa una profundidad decimal válida."
    var step = to / 0.05
    if (Math.abs(step - Math.round(step)) > 0.000001) return "Hasta debe avanzar en pasos de 0.05 m."
    if (!isFinite(from) || to <= from) return "Hasta debe ser mayor que Desde."
    if (isFinite(maximum) && maximum > 0 && to > maximum + 0.000001)
        return "Hasta no puede superar la profundidad total de " + maximum.toFixed(2) + " m."
    if (index + 1 < rows.length) {
        var next = parseDecimalSafe(rows[index + 1].a)
        if (isFinite(next) && to >= next) return "El límite invade el siguiente estrato."
    }
    // Test the proposed inherited interval; a manual subinterval must remain inside its stratum.
    for (var i = index; i <= Math.min(index + 1, rows.length - 1); ++i) {
        var lower = i === index ? from : to
        var upper = i === index ? to : parseDecimalSafe(rows[i].a)
        var proposed = Object.assign({}, rows[i], {de:lower.toFixed(2), a:isFinite(upper) ? upper.toFixed(2) : ""})
        var previousLower = i === index ? from : parseDecimalSafe(rows[index].a)
        var inherited = inheritSampleInterval(proposed, previousLower, rows[i].a)
        var sf = parseDecimalSafe(inherited.muestra_desde === undefined ? rows[i].muestra_desde : inherited.muestra_desde)
        var st = parseDecimalSafe(inherited.muestra_hasta === undefined ? rows[i].muestra_hasta : inherited.muestra_hasta)
        if ((isFinite(sf) && sf < lower) || (isFinite(st) && st > upper))
            return "El límite dejaría una muestra fuera del estrato " + (i + 1) + "."
    }
    return ""
}
function gpsFixValid(lat, lon, accuracy, timestamp, now, baseline, requireNew, target) {
    return isFinite(lat) && isFinite(lon) && lat >= -90 && lat <= 90
        && lon >= -180 && lon <= 180 && isFinite(accuracy) && accuracy > 0
        && accuracy <= target && isFinite(timestamp) && timestamp > 0
        && now >= timestamp && now - timestamp <= 30000
        && (!requireNew || timestamp > baseline)
}

function contextWarnings(rows) {
    var warnings = [], previous = 0
    for (var i = 0; i < rows.length; ++i) {
        var row=rows[i], from=parseDecimalSafe(row.de), to=parseDecimalSafe(row.a)
        if (isFinite(from) && Math.abs(from-previous)>0.001) warnings.push("Estrato "+(i+1)+": intervalo discontinuo")
        if (isFinite(to) && isFinite(from) && to<=from) warnings.push("Estrato "+(i+1)+": espesor no positivo")
        if (isFinite(to)) previous=to
        if (String(row.descripcion || "").trim().length<12) warnings.push("Estrato "+(i+1)+": completa la evidencia descriptiva")
    }
    return warnings
}

// Single decision contract for review, official export, approval and final sync.
function validateDocument(state) {
    state = state || {}
    var h = state.header || {}, rows = state.cortes || [], issues = []
    function add(section, stratum, message, severity) {
        issues.push({section: section, stratum: stratum, message: message,
                     severity: severity || "BLOCKER"})
    }
    function text(value) { return String(value === undefined || value === null ? "" : value).trim() }
    function number(key) { return parseDecimalSafe(h[key]) }
    var uuid = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i
    if (!uuid.test(text(h.projectId)) || /^0{8}-0{4}-0{4}-0{4}-0{12}$/.test(text(h.projectId)))
        add(1, -1, "Proyecto no asignado.")
    if (!text(h.codigo || h.calicata)) add(1, -1, "Ingresa el código de calicata.")
    if (!text(h.projectName || h.project_full_name)) add(1, -1, "Falta el nombre del proyecto.")
    if (h.status === "ARCHIVADO") add(1, -1, "La ficha está archivada.")
    function validDate(value) {
        var t = text(value), d = new Date(t + "T00:00:00Z")
        return /^\d{4}-\d{2}-\d{2}$/.test(t) && isFinite(d.getTime()) && d.toISOString().slice(0,10) === t
    }
    if (!validDate(h.fecha_inicio)) add(1, -1, "Selecciona una fecha válida de excavación.")
    if (text(h.fecha_fin) && (!validDate(h.fecha_fin) || text(h.fecha_fin) < text(h.fecha_inicio)))
        add(1, -1, "La fecha de fin debe ser válida y no anterior al inicio.")
    var lat = number("latitude"), lon = number("longitude")
    if (!isFinite(lat) || !isFinite(lon) || lat < -80 || lat > 84 || Math.abs(lon) > 180)
        add(2, -1, "Falta una ubicación válida en el rango UTM.")
    if (!validateDecimalRange(h.utm_x, 100000, 900000)) add(2, -1, "Este UTM: ingresa un valor entre 100000 y 900000 m.")
    if (!validateDecimalRange(h.utm_y, 0, 10000000)) add(2, -1, "Norte UTM: ingresa un valor entre 0 y 10000000 m.")
    if (!/^(?:[1-9]|[1-5][0-9]|60)[C-HJ-NP-X]$/i.test(text(h.zona)))
        add(2, -1, "Zona UTM no válida; incluye la banda, por ejemplo 18L.")
    if (!text(h.datum)) add(2, -1, "Datum no definido.")
    if (text(h.utm_z) && !validateDecimalRange(h.utm_z, -12000, 10000)) add(2, -1, "Altitud no válida.")
    // Largo/ancho de excavación son opcionales (la ficha oficial C-AA-01 no los
    // tiene): vacío o 0 no es pendiente ni advertencia. Solo un valor escrito
    // que no se puede leer o es negativo se marca para corregir.
    for (var d = 0; d < 2; ++d) {
        var dimension = d ? "width_m" : "length_m"
        if (text(h[dimension]) && (!isFinite(number(dimension)) || number(dimension) < 0))
            add(3, -1, (d ? "Ancho" : "Largo") + ": ingresa una dimensión válida o déjalo vacío.")
    }
    if (!rows.length) add(4, -1, "Registra al menos un estrato.")
    var previous = 0, finalDepth = 0
    for (var i = 0; i < rows.length; ++i) {
        var row = rows[i] || {}, from = parseDecimalSafe(row.de), to = parseDecimalSafe(row.a)
        var label = "Estrato " + (i + 1) + ": "
        if (!isFinite(from) || !isFinite(to) || from < 0 || to <= from || Math.abs(to * 20 - Math.round(to * 20)) > 0.000001)
            add(4, i, label + "Intervalo inválido: Hasta debe superar Desde en pasos de 0.05 m.")
        if (isFinite(from) && isFinite(previous) && Math.abs(from - previous) > 0.001)
            add(4, i, label + (from < previous ? "se solapa con el intervalo anterior." : "hay un hueco antes del intervalo."))
        var limit = number("requested_depth_m")
        if (isFinite(limit) && limit > 0 && isFinite(to) && to > limit + 0.000001)
            add(4, i, label + "Hasta supera la profundidad total de " + limit.toFixed(2) + " m.")
        previous = to
        if (isFinite(to)) finalDepth = Math.max(finalDepth, to)
        if (text(row.muestra_desde) || text(row.muestra_hasta)) {
            var sf = parseDecimalSafe(row.muestra_desde), st = parseDecimalSafe(row.muestra_hasta)
            if (!isFinite(sf) || !isFinite(st) || sf >= st || sf < from - 0.001 || st > to + 0.001)
                add(5, i, label + "la muestra debe quedar dentro del estrato, con Desde menor que Hasta.")
        }
        // Laboratorio: el mismo validador que Web (validateCalicataLaboratoryForm).
        var labCheck = webLabValidate(row, row)
        for (var k = 0; k < labCheck.errors.length; ++k) add(5, i, label + labCheck.errors[k])
    }
    var requested = number("requested_depth_m"), finalValue = number("final_depth_m")
    var expected = finalValue
    if (!isFinite(expected) || expected <= 0 || Math.abs(finalDepth - expected) > 0.001)
        add(3, -1, "La profundidad final debe coincidir con el final de los estratos.")
    var water = text(h.water_table_status)
    if (!water) water = h.water_table_present === true ? "ENCONTRADO" : h.water_table_present === false ? "NO_ENCONTRADO" : "NO_EVALUADO"
    if (water === "ENCONTRADO" && !validateDecimalRange(h.water_table_depth, 0, finalDepth))
        add(3, -1, "Nivel freático encontrado: indica una profundidad entre 0 y " + finalDepth + " m.")
    else if (water === "NO_EVALUADO") add(3, -1, "Nivel freático no evaluado.", "WARNING")
    else if (["ENCONTRADO", "NO_ENCONTRADO"].indexOf(water) < 0) add(3, -1, "Estado de nivel freático no válido.")
    var images = state.images || {}, names = ["Zona de ejecución", "Interior de calicata", "Acopios"]   // = photoSlotTitles / Web EXECUTION·INTERIOR·STOCKPILES
    for (var p = 1; p <= 3; ++p) {
        if (!text(images["foto" + p + "_path"])) add(7, -1, "Falta " + names[p - 1] + ".")
        else if (state.photoAvailability && state.photoAvailability[String(p)] === false)
            add(7, -1, "No se encuentra el archivo de " + names[p - 1] + ".")
    }
    if (images.logo_mtc_removed === true || images.logo_proyecto_removed === true)
        add(6, -1, "Completa los logos del informe o selecciona los predeterminados.")
    return issues
}
function blockers(issues) { return issues.filter(function(issue) { return issue.severity !== "WARNING" }) }

// Profundidad de la regla: el valor ingresado no se reduce al último estrato.
// Cero/vacío identifica fichas antiguas sin profundidad independiente.
function profileDepth(requested, recorded) {
    var depth = parseDecimalSafe(requested)
    if (isFinite(depth) && depth > 0) return depth
    var last = parseDecimalSafe(recorded)
    return isFinite(last) && last > 0 ? last : 0
}

// ===== Revisión de cierre (pantalla Revisión) =====
// Todo sale del mismo contrato que exportación/aprobación (validateDocument) y de
// los datos de la ficha. Sin pesos, métricas ni conclusiones inventadas.
function _reviewText(value) { return String(value === undefined || value === null ? "" : value).trim() }
function _reviewRowHasLab(row) {
    row = row || {}
    return hasLabTestData(labForm(row, row))
}
function _reviewWaterStatus(h) {
    var water = _reviewText(h.water_table_status)
    if (!water) water = h.water_table_present === true ? "ENCONTRADO" : h.water_table_present === false ? "NO_ENCONTRADO" : "NO_EVALUADO"
    return water
}

// Completitud por componente = requisitos que validateDocument evalúa en esa sección;
// cada BLOCKER es un requisito no cumplido. Laboratorio es informativo (no bloquea la
// exportación): % de estratos con ensayos registrados y sin errores.
function reviewSummary(state, issues) {
    state = state || {}
    issues = issues || validateDocument(state)
    var h = state.header || {}, rows = state.cortes || []
    function inSections(sections) {
        return issues.filter(function(issue) { return sections.indexOf(Number(issue.section)) >= 0 })
    }
    var defs = [
        { key: "general", label: "Datos generales", section: 1, sections: [1], gated: true,
          required: 4 + (_reviewText(h.fecha_fin) ? 1 : 0) + (h.status === "ARCHIVADO" ? 1 : 0) },
        { key: "location", label: "Ubicación", section: 2, sections: [2], gated: true,
          required: 5 + (_reviewText(h.utm_z) ? 1 : 0) },
        { key: "profile", label: "Perfil", section: 4, sections: [3, 4], gated: true,
          required: 4 + Math.max(1, rows.length) },
        { key: "lab", label: "Laboratorio", section: 5, sections: [5], gated: false,
          required: Math.max(1, rows.length) },
        { key: "photos", label: "Fotos", section: 7, sections: [7], gated: true, required: 3 },
        { key: "identity", label: "Identidad", section: 6, sections: [6], gated: true, required: 1 }
    ]
    var components = [], gatedSum = 0, gatedCount = 0, pending = 0
    for (var d = 0; d < defs.length; ++d) {
        var def = defs[d], list = inSections(def.sections)
        var blockerList = blockers(list)
        var warningList = list.filter(function(issue) { return issue.severity === "WARNING" })
        var done
        if (def.key === "lab") {
            done = 0
            for (var r = 0; r < rows.length; ++r) {
                var rowBlocked = blockerList.some(function(issue) { return Number(issue.stratum) === r })
                if (_reviewRowHasLab(rows[r]) && !rowBlocked) ++done
            }
        } else {
            done = def.required - Math.min(def.required, blockerList.length)
        }
        var pct = Math.round(100 * done / def.required)
        var status = blockerList.length ? "blocker"
                   : def.key === "lab" && done < def.required ? "pending"
                   : warningList.length ? "warning" : "complete"
        components.push({ key: def.key, label: def.label, section: def.section, gated: def.gated,
                          required: def.required, done: done, percent: pct, status: status,
                          blockers: blockerList, warnings: warningList,
                          message: (blockerList[0] || warningList[0] || {}).message || "" })
        if (def.gated) {
            gatedSum += pct; ++gatedCount
            if (blockerList.length) ++pending
        }
    }
    var allBlockers = blockers(issues)
    return {
        components: components,
        percent: gatedCount ? Math.round(gatedSum / gatedCount) : 0,
        pendingCount: pending,
        blockerCount: allBlockers.length,
        warningCount: issues.length - allBlockers.length,
        complete: allBlockers.length === 0
    }
}

// Datos reales para Resumen, Perfil y Rendimiento. Índices de excavabilidad /
// estabilidad / humedad = posición en la lista de la ficha (Rend. bajo..muy alto,
// Baja..Muy Alta). El índice de excavabilidad pondera por espesor (25/50/75/100).
function reviewFacts(state) {
    state = state || {}
    var h = state.header || {}, rows = state.cortes || [], images = state.images || {}
    var segments = [], finalDepth = 0, samples = 0, labRows = 0, classified = 0
    var byCode = {}, excWeighted = 0, excThickness = 0, excByIndex = {}, estByIndex = {}
    for (var i = 0; i < rows.length; ++i) {
        var row = rows[i] || {}
        var from = parseDecimalSafe(row.de), to = parseDecimalSafe(row.a)
        if (_reviewText(row.tipo_muestra || row.muestra || row.tipoText)
                || _reviewText(row.muestra_desde) || _reviewText(row.muestra_hasta)) ++samples
        if (_reviewRowHasLab(row)) ++labRows
        var cls = exportClassification(row)
        if (cls.label || cls.aashto) ++classified
        if (!isFinite(from) || !isFinite(to) || to <= from) continue
        var thickness = to - from, code = cls.label
        finalDepth = Math.max(finalDepth, to)
        var exc = Number(row.excavabilidad), est = Number(row.estabilidad)
        segments.push({ index: i, from: from, to: to, thickness: thickness, code: code,
                        sucs: cls.label, aashto: cls.aashto,
                        description: _reviewText(row.descripcion),
                        excavability: isFinite(exc) && exc >= 0 ? exc : -1,
                        stability: isFinite(est) && est >= 0 ? est : -1 })
        if (code) byCode[code] = (byCode[code] || 0) + thickness
        if (isFinite(exc) && exc >= 0 && exc <= 3) {
            excWeighted += (exc + 1) * 25 * thickness; excThickness += thickness
            excByIndex[exc] = (excByIndex[exc] || 0) + thickness
        }
        if (isFinite(est) && est >= 0 && est <= 3) estByIndex[est] = (estByIndex[est] || 0) + thickness
    }
    function predominant(map) {
        var best = null
        for (var key in map) if (best === null || map[key] > map[best]) best = key
        return best === null ? -1 : best
    }
    var code = predominant(byCode)
    var length = parseDecimalSafe(h.length_m), width = parseDecimalSafe(h.width_m)
    var requested = parseDecimalSafe(h.requested_depth_m)
    function dateOf(value) {
        var t = _reviewText(value), d = new Date(t + "T00:00:00Z")
        return /^\d{4}-\d{2}-\d{2}$/.test(t) && isFinite(d.getTime()) ? d : null
    }
    var start = dateOf(h.fecha_inicio), end = dateOf(h.fecha_fin)
    var photos = 0
    for (var p = 1; p <= 3; ++p)
        if (_reviewText(images["foto" + p + "_path"])
                && !(state.photoAvailability && state.photoAvailability[String(p)] === false)) ++photos
    var water = _reviewWaterStatus(h), waterDepth = parseDecimalSafe(h.water_table_depth)
    var volume = isFinite(length) && isFinite(width) && length > 0 && width > 0 && finalDepth > 0
            ? length * width * finalDepth : NaN
    var durationDays = start && end && end >= start ? Math.round((end - start) / 86400000) + 1 : NaN
    // Riesgo operativo (determinista, solo con datos de campo de la ficha):
    //   Alto  = algún estrato con estabilidad "Baja" (índice 0) o nivel freático
    //           encontrado por encima del fondo de la calicata;
    //   Medio = algún estrato con estabilidad "Media" (índice 1);
    //   Bajo  = estabilidad registrada en TODO el perfil, toda "Alta"/"Muy Alta",
    //           y sin agua por encima del fondo;
    //   -1    = datos insuficientes (no se afirma nada).
    var stabilityThickness = 0
    for (var key in estByIndex) stabilityThickness += estByIndex[key]
    var waterAbove = water === "ENCONTRADO" && isFinite(waterDepth) && waterDepth < finalDepth
    var riskReasons = []
    if (estByIndex[0] > 0) riskReasons.push("estabilidad baja en " + estByIndex[0].toFixed(2) + " m")
    if (waterAbove) riskReasons.push("agua a " + waterDepth.toFixed(2) + " m")
    var risk = riskReasons.length ? 2
             : estByIndex[1] > 0 ? 1
             : finalDepth > 0 && stabilityThickness >= finalDepth - 1e-6 && water !== "NO_EVALUADO" ? 0
             : -1
    if (risk === 1) riskReasons.push("estabilidad media en " + estByIndex[1].toFixed(2) + " m")
    return {
        strata: rows.length, segments: segments, finalDepth: finalDepth,
        samples: samples, labRows: labRows, classified: classified, photos: photos,
        predominantCode: code === -1 ? "" : code,
        predominantThickness: code === -1 ? 0 : byCode[code],
        waterStatus: water,
        waterDepth: water === "ENCONTRADO" && isFinite(waterDepth) ? waterDepth : NaN,
        length: isFinite(length) && length > 0 ? length : NaN,
        width: isFinite(width) && width > 0 ? width : NaN,
        volume: volume,
        requestedDepth: isFinite(requested) && requested > 0 ? requested : NaN,
        reachedPercent: isFinite(requested) && requested > 0 ? Math.min(100, Math.round(100 * finalDepth / requested)) : NaN,
        durationDays: durationDays,
        // Rendimiento real = volumen excavado ÷ días de trabajo; avance = profundidad ÷ días.
        productivity: isFinite(volume) && isFinite(durationDays) && durationDays > 0 ? volume / durationDays : NaN,
        advanceRate: finalDepth > 0 && isFinite(durationDays) && durationDays > 0 ? finalDepth / durationDays : NaN,
        stabilityCoverage: finalDepth > 0 ? Math.round(100 * Math.min(1, stabilityThickness / finalDepth)) : 0,
        operationalRisk: risk,
        operationalRiskReasons: riskReasons,
        // Ubicación tal como está guardada (UTM de la ficha; lat/lon solo si no hay UTM).
        location: (function() {
            var zone = _reviewText(h.zona || h.utm_zone), e = parseDecimalSafe(h.utm_x), n = parseDecimalSafe(h.utm_y)
            var lat = parseDecimalSafe(h.latitude), lon = parseDecimalSafe(h.longitude)
            var datum = _reviewText(h.datum)
            if (zone && isFinite(e) && isFinite(n))
                return { text: zone + " · " + e.toFixed(2) + " E / " + n.toFixed(2) + " N", datum: datum }
            if (isFinite(lat) && isFinite(lon) && Math.abs(lat) <= 90 && Math.abs(lon) <= 180)
                return { text: lat.toFixed(6) + ", " + lon.toFixed(6), datum: datum }
            return { text: "", datum: datum }
        })(),
        excavabilityIndex: excThickness > 0 ? Math.round(excWeighted / excThickness) : NaN,
        excavabilityCoverage: finalDepth > 0 ? Math.round(100 * excThickness / finalDepth) : 0,
        predominantExcavability: Number(predominant(excByIndex)),
        predominantStability: Number(predominant(estByIndex))
    }
}

// Recomendaciones SOLO cuando un dato de la ficha las sustenta (sin inferencias
// geotécnicas): cada una indica la sección donde se resuelve.
function reviewRecommendations(state, facts) {
    state = state || {}
    facts = facts || reviewFacts(state)
    var rows = state.cortes || [], out = []
    if (facts.waterStatus === "NO_EVALUADO")
        out.push({ text: "Evalúa y registra el nivel freático (figura como no evaluado).", section: 3, stratum: -1 })
    else if (facts.waterStatus === "ENCONTRADO" && isFinite(facts.waterDepth))
        out.push({ text: "Nivel freático registrado a " + facts.waterDepth.toFixed(2)
                         + " m: prevé control de agua durante la excavación.", section: 3, stratum: -1 })
    var missingLab = facts.strata - facts.labRows
    if (facts.strata > 0 && missingLab > 0)
        out.push({ text: "Registra ensayos de laboratorio en " + missingLab
                         + (missingLab === 1 ? " estrato sin resultados." : " estratos sin resultados."), section: 5, stratum: -1 })
    if (facts.strata > 0 && facts.samples === 0)
        out.push({ text: "No hay muestras registradas: define el tipo e intervalo de muestra.", section: 5, stratum: -1 })
    for (var i = 0; i < rows.length; ++i)
        if (_reviewText((rows[i] || {}).descripcion).length < 12)
            out.push({ text: "Completa la descripción de campo del estrato " + (i + 1) + ".", section: 4, stratum: i })
    var lowStability = 0
    for (var s = 0; s < facts.segments.length; ++s) if (facts.segments[s].stability === 0) ++lowStability
    if (lowStability)
        out.push({ text: "Estabilidad registrada «Baja» en " + lowStability
                         + (lowStability === 1 ? " estrato" : " estratos") + ": revisa las medidas de sostenimiento.", section: 4, stratum: -1 })
    return out
}

// Resumen técnico factual (no IA): solo hechos registrados en la ficha.
function reviewConclusion(summary, facts) {
    if (!facts || !facts.strata) return "Aún no hay estratos registrados en la ficha."
    var parts = ["Calicata de " + facts.finalDepth.toFixed(2) + " m con " + facts.strata
                 + (facts.strata === 1 ? " estrato registrado." : " estratos registrados.")]
    if (facts.predominantCode)
        parts.push("Predomina " + facts.predominantCode + " (" + facts.predominantThickness.toFixed(2) + " m de espesor).")
    parts.push(facts.waterStatus === "ENCONTRADO"
               ? "Nivel freático encontrado" + (isFinite(facts.waterDepth) ? " a " + facts.waterDepth.toFixed(2) + " m." : ".")
               : facts.waterStatus === "NO_ENCONTRADO" ? "Nivel freático no encontrado." : "Nivel freático no evaluado.")
    parts.push(facts.labRows + " de " + facts.strata + " estratos con ensayos de laboratorio.")
    if (summary)
        parts.push(summary.pendingCount
                   ? "Ficha al " + summary.percent + " %: " + summary.pendingCount
                     + (summary.pendingCount === 1 ? " elemento pendiente." : " elementos pendientes.")
                   : "Ficha completa para exportar.")
    // Nunca se afirma estabilidad ni seguridad geotécnica: con datos faltantes la
    // conclusión lo dice expresamente; completa, remite al especialista.
    var limited = (summary && summary.blockerCount > 0) || facts.labRows < facts.strata
    parts.push(limited
               ? "Conclusión limitada por datos faltantes: no se emite juicio sobre estabilidad ni seguridad geotécnica."
               : "Los datos registrados no sustituyen la evaluación geotécnica del especialista.")
    return parts.join(" ")
}

// WGS84 inverse UTM (datum-aware variant: utmToGeoForDatum). Band (C..X), not an
// ambiguous N/S hemisphere suffix.
function utmToGeo(easting, northing, zoneText) {
    return _utmInverse(easting, northing, zoneText, 6378137, 0.0066943799901413165)
}
// Inverse UTM on the ellipsoid (a, e2).
function _utmInverse(easting, northing, zoneText, a, e2) {
    var x = parseDecimalSafe(easting), y = parseDecimalSafe(northing)
    var match = /^([1-9]|[1-5][0-9]|60)([C-HJ-NP-X])?$/i.exec(String(zoneText || "").trim())
    if (!match || !isFinite(x) || !isFinite(y) || x < 100000 || x > 900000 || y < 0 || y > 10000000) return null
    // A bare numeric zone (cloud `utm_zone`) follows Web parseSheetCoordinate:
    // southern hemisphere, no band check.
    var zone = Number(match[1]), band = match[2] ? match[2].toUpperCase() : "", south = !band || band < "N"
    x -= 500000
    if (south) y -= 10000000
    var ep2 = e2 / (1 - e2), k0 = 0.9996
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
    var bands = "CDEFGHJKLMNPQRSTUVWX", lower = band ? -80 + bands.indexOf(band)*8 : -80
    var upper = !band ? 0 : (band === "X" ? 84 : lower+8)
    if (!isFinite(lat) || !isFinite(lon) || lat < lower - 0.00001 || lat > upper + 0.00001 || Math.abs(lon) > 180) return null
    return {latitude: lat, longitude: lon}
}

// ===== Datum horizontal de la ficha: WGS84 / PSAD56 =====
// La ubicación física es única y se guarda en grados WGS84 (latitude/longitude,
// lo que usan GPS y mapa). `datum` define solo el CRS de las UTM mostradas:
//  - WGS84 : elipsoide WGS84 (a=6378137, f=1/298.257223563).
//  - PSAD56: elipsoide Internacional 1924 / Hayford (a=6378388, f=1/297).
// PSAD56 → WGS84 en Perú: traslación geocéntrica de 3 parámetros publicada por
// NIMA TR8350.2 ("Provisional South American 1956 – Peru"):
// dX = -279 m, dY = +175 m, dZ = -379 m (exactitud declarada ±6/±8/±12 m).
// WGS84 → PSAD56 aplica la misma traslación con signo opuesto. La cota (Z) no
// se transforma: el cambio es solo de referencia horizontal.
var ELLIPSOID_WGS84 = { a: 6378137.0, f: 1 / 298.257223563 }
var ELLIPSOID_INTL1924 = { a: 6378388.0, f: 1 / 297.0 }
var PSAD56_TO_WGS84_PERU = { dx: -279.0, dy: 175.0, dz: -379.0 }

function _ellipsoidFor(datum) {
    return datum === "PSAD56" ? ELLIPSOID_INTL1924 : ELLIPSOID_WGS84
}

function _geoToEcef(latDeg, lonDeg, ell) {
    var e2 = ell.f * (2 - ell.f)
    var lat = latDeg * Math.PI / 180, lon = lonDeg * Math.PI / 180
    var s = Math.sin(lat), c = Math.cos(lat)
    var n = ell.a / Math.sqrt(1 - e2 * s * s)
    return { x: n * c * Math.cos(lon), y: n * c * Math.sin(lon), z: n * (1 - e2) * s }
}

function _ecefToGeo(x, y, z, ell) {
    var e2 = ell.f * (2 - ell.f)
    var p = Math.sqrt(x * x + y * y)
    var lat = Math.atan2(z, p * (1 - e2)), h = 0
    for (var i = 0; i < 8; ++i) {
        var s = Math.sin(lat)
        var n = ell.a / Math.sqrt(1 - e2 * s * s)
        h = p / Math.cos(lat) - n
        lat = Math.atan2(z, p * (1 - e2 * n / (n + h)))
    }
    return { latitude: lat * 180 / Math.PI, longitude: Math.atan2(y, x) * 180 / Math.PI }
}

// Grados WGS84 → grados en `datum` (y viceversa). Sin cambio para WGS84.
function wgs84ToDatum(lat, lon, datum) {
    if (datum !== "PSAD56") return { latitude: lat, longitude: lon }
    var t = PSAD56_TO_WGS84_PERU, p = _geoToEcef(lat, lon, ELLIPSOID_WGS84)
    return _ecefToGeo(p.x - t.dx, p.y - t.dy, p.z - t.dz, ELLIPSOID_INTL1924)
}
function datumToWgs84(lat, lon, datum) {
    if (datum !== "PSAD56") return { latitude: lat, longitude: lon }
    var t = PSAD56_TO_WGS84_PERU, p = _geoToEcef(lat, lon, ELLIPSOID_INTL1924)
    return _ecefToGeo(p.x + t.dx, p.y + t.dy, p.z + t.dz, ELLIPSOID_WGS84)
}

// Proyección UTM directa (Transverse Mercator, k0 0.9996) sobre un elipsoide;
// misma serie que GpsBus.latLonToUTM.
function _tmForward(latDeg, lonDeg, zone, ell) {
    var a = ell.a, k0 = 0.9996, e2 = ell.f * (2 - ell.f), ep2 = e2 / (1 - e2)
    var lat = latDeg * Math.PI / 180, lon = lonDeg * Math.PI / 180
    var lon0 = (-183 + zone * 6) * Math.PI / 180
    var s = Math.sin(lat), c = Math.cos(lat), tn = Math.tan(lat)
    var N = a / Math.sqrt(1 - e2 * s * s), T = tn * tn, C = ep2 * c * c, A = c * (lon - lon0)
    var e4 = e2 * e2, e6 = e4 * e2
    var M = a * ((1 - e2/4 - 3*e4/64 - 5*e6/256) * lat
        - (3*e2/8 + 3*e4/32 + 45*e6/1024) * Math.sin(2*lat)
        + (15*e4/256 + 45*e6/1024) * Math.sin(4*lat)
        - (35*e6/3072) * Math.sin(6*lat))
    var easting = k0 * N * (A + (1 - T + C) * Math.pow(A, 3) / 6
        + (5 - 18*T + T*T + 72*C - 58*ep2) * Math.pow(A, 5) / 120) + 500000
    var northing = k0 * (M + N * tn * (A*A/2 + (5 - T + 9*C + 4*C*C) * Math.pow(A, 4) / 24
        + (61 - 58*T + T*T + 600*C - 330*ep2) * Math.pow(A, 6) / 720))
    if (latDeg < 0) northing += 10000000
    return { easting: easting, northing: northing }
}

// Grados WGS84 → UTM en `datum`. La zona se calcula con la longitud del datum
// (contrato de zona existente: número + banda, p. ej. "18L").
function geoToUtmForDatum(lat, lon, datum) {
    if (!isFinite(lat) || !isFinite(lon)) return null
    var g = wgs84ToDatum(lat, lon, datum)
    var zone = Math.floor((g.longitude + 180) / 6) + 1
    var bands = "CDEFGHJKLMNPQRSTUVWX"
    var band = bands.charAt(Math.max(0, Math.min(19, Math.floor((g.latitude + 80) / 8))))
    var p = _tmForward(g.latitude, g.longitude, zone, _ellipsoidFor(datum))
    return { zone: zone, band: band, easting: p.easting, northing: p.northing }
}

// UTM en `datum` → grados WGS84 (para mapa y lat/lon guardados).
function utmToGeoForDatum(easting, northing, zoneText, datum) {
    var ell = _ellipsoidFor(datum)
    var g = _utmInverse(easting, northing, zoneText, ell.a, ell.f * (2 - ell.f))
    return g ? datumToWgs84(g.latitude, g.longitude, datum) : null
}


// ===== InGe+ Web parity: laboratory contract =====
// Mirrors src/lib/calicatas/laboratoryContract.ts. This contract is intentionally
// independent from the older MTC evidence helper above: Web stores the laboratory
// row explicitly and treats classification as engineer-confirmed data plus review.
var webSucsCodes = ["GW", "GP", "GM", "GC", "SW", "SP", "SM", "SC",
    "ML", "CL", "OL", "MH", "CH", "OH", "PT"]
var webAashtoCodes = ["A-1-a", "A-1-b", "A-2-4", "A-2-5", "A-2-6", "A-2-7",
    "A-3", "A-4", "A-5", "A-6", "A-7-5", "A-7-6"]
var webGranulometryFields = ["gmax", "passing_no4", "g2", "g04", "g008"]

function webLabPercent(value, maximum) {
    var text = String(value === undefined || value === null ? "" : value).trim().replace(",", ".")
    if (!text.length) return { valid:true, value:NaN, text:"" }
    if (!/^\d+(?:\.\d{0,2})?$/.test(text)) return { valid:false, value:NaN, text:text }
    var n=Number(text), max=maximum===undefined?100:maximum
    return { valid:isFinite(n)&&n>=0&&n<=max, value:n, text:text }
}
function webLabInteger(value) {
    var text=String(value===undefined||value===null?"":value).trim().replace(",", ".")
    if(!text.length) return {valid:true,value:NaN,text:""}
    if(!/^\d+$/.test(text)) return {valid:false,value:NaN,text:text}
    var n=Number(text); return {valid:isFinite(n)&&n>=0,value:n,text:text}
}
// LL / LP: Web validateInteger (calicata_lab_results.liquid_limit/plastic_limit
// son integer). Un decimal es un error visible; nunca se redondea en silencio.
function webLabLimit(value) {
    var text=String(value===undefined||value===null?"":value).trim().replace(",", ".")
    if(!text.length) return {valid:true,value:NaN,text:""}
    if(!/^(?:\d+|\d*\.\d+)$/.test(text)) return {valid:false,value:NaN,text:text}
    var n=Number(text)
    return {valid:isFinite(n)&&Math.floor(n)===n&&n>=0,value:n,text:text}
}
function webLabNormalizeLimit(value) {
    var parsed=webLabLimit(value)
    if(!parsed.valid) return null
    return parsed.text.length ? String(parsed.value) : ""
}
function webLabBounds(row, field) {
    row=row||{}; var idx=webGranulometryFields.indexOf(field)
    if(idx<0) return {min:0,max:100}
    var min=0,max=100,i,p
    for(i=0;i<idx;++i){
        p=webLabPercent(field==="passing_no4"?row[field]:row[webGranulometryFields[i]],100)
        if(p.valid&&isFinite(p.value)) max=Math.min(max,p.value)
    }
    for(i=idx+1;i<webGranulometryFields.length;++i){
        var k=webGranulometryFields[i]
        p=webLabPercent(k==="passing_no4"?row[k]:row[k],100)
        if(p.valid&&isFinite(p.value)) min=Math.max(min,p.value)
    }
    return {min:min,max:max}
}
function webLabNormalizePercent(value, bounds) {
    var parsed=webLabPercent(value,100)
    if(!parsed.valid || !isFinite(parsed.value)) return parsed.text.length?null:""
    bounds=bounds||{min:0,max:100}
    if(parsed.value<bounds.min || parsed.value>bounds.max) return null
    return parsed.value.toFixed(2)
}
function webLabProjection(primary,isComposite,secondary) {
    return formatSucsProjection(primary, isComposite, secondary)
}

// Web validateCalicataLaboratoryForm (laboratoryContract.ts), mismo orden y
// mismos mensajes. errors: { campoDelFormulario: mensaje }.
function _labParse(value, maximumFractionDigits) {
    var normalized=String(value===undefined||value===null?"":value).trim().replace(",", ".")
    if(!normalized.length) return {valid:true,value:null}
    var pattern=maximumFractionDigits===undefined ? /^(?:\d+|\d*\.\d+)$/
        : new RegExp("^\\d+(?:\\.\\d{0,"+maximumFractionDigits+"})?$")
    if(!pattern.test(normalized)) return {valid:false,value:null}
    var parsed=Number(normalized)
    return isFinite(parsed) ? {valid:true,value:parsed} : {valid:false,value:null}
}
function validateLaboratoryForm(form) {
    var errors={}
    function percent(value, field, maximum) {
        maximum=maximum===undefined?100:maximum
        var parsed=_labParse(value,2)
        if(!parsed.valid){ errors[field]="Ingresa un número válido con máximo dos decimales."; return {valid:false,value:null} }
        if(parsed.value!==null&&(parsed.value<0||parsed.value>maximum)){
            errors[field]="Debe estar entre 0.00 y "+maximum.toFixed(2)+" %."; return {valid:false,value:parsed.value} }
        return {valid:true,value:parsed.value}
    }
    function integer(value, field) {
        var parsed=_labParse(value)
        if(!parsed.valid||(parsed.value!==null&&Math.floor(parsed.value)!==parsed.value)) errors[field]="Debe ser un número entero."
        else if(parsed.value!==null&&parsed.value<0) errors[field]="No puede ser negativo."
        return parsed.value
    }
    var granulometry={ sieveMaxPct: percent(form.sieveMaxPct,"sieveMaxPct"), sieveNo4Pct: percent(form.sieveNo4Pct,"sieveNo4Pct"),
        sieve2mmPct: percent(form.sieve2mmPct,"sieve2mmPct"), sieve04mmPct: percent(form.sieve04mmPct,"sieve04mmPct"),
        sieve008mmPct: percent(form.sieve008mmPct,"sieve008mmPct") }
    var liquidLimit=integer(form.liquidLimit,"liquidLimit"), plasticLimit=integer(form.plasticLimit,"plasticLimit")
    var naturalMoisture=percent(form.naturalMoisturePct,"naturalMoisturePct",500)
    var fields=["sieveMaxPct","sieveNo4Pct","sieve2mmPct","sieve04mmPct","sieve008mmPct"], previousValue=null
    for(var i=0;i<fields.length;++i){
        var parsed=granulometry[fields[i]]
        if(!parsed.valid||parsed.value===null) continue
        if(previousValue!==null&&previousValue<parsed.value) errors[fields[i]]=LAB_GRANULOMETRY_SEQUENCE_ERROR
        previousValue=parsed.value
    }
    if(liquidLimit!==null&&plasticLimit!==null&&plasticLimit>liquidLimit) errors.plasticLimit="LP debe ser menor o igual que WL."
    if(form.isComposite&&!form.primarySucs) errors.primarySucs="Selecciona el SUCS principal."
    if(form.isComposite&&!form.secondarySucs) errors.secondarySucs="Selecciona el segundo SUCS."
    if(form.isComposite&&form.primarySucs===form.secondarySucs) errors.secondarySucs="El segundo SUCS debe ser diferente del principal."
    if(form.testDate){
        var date=new Date(form.testDate+"T00:00:00Z")
        if(!/^\d{4}-\d{2}-\d{2}$/.test(form.testDate)||isNaN(date.getTime())||date.toISOString().slice(0,10)!==form.testDate)
            errors.testDate="Ingresa una fecha válida."
    }
    var keys=Object.keys(errors)
    if(keys.length) return {changes:null, errors:errors}
    return {errors:errors, changes:{
        sieve_max_pct: granulometry.sieveMaxPct.value, sieve_no4_pct: granulometry.sieveNo4Pct.value,
        sieve_2mm_pct: granulometry.sieve2mmPct.value, sieve_04mm_pct: granulometry.sieve04mmPct.value,
        sieve_008mm_pct: granulometry.sieve008mmPct.value, liquid_limit: liquidLimit, plastic_limit: plasticLimit,
        natural_moisture_pct: naturalMoisture.value, primary_sucs: form.primarySucs||null, is_composite: form.isComposite,
        secondary_sucs: form.isComposite ? form.secondarySucs||null : null, aashto: form.aashto||null,
        laboratory_source: String(form.laboratorySource||"").trim().replace(/\s+/g," ")||null, test_date: form.testDate||null }}
}
var LAB_GRANULOMETRY_SEQUENCE_ERROR = "La granulometría debe decrecer: Máx. ≥ Nº 4 ≥ Nº 10 ≥ Nº 40 ≥ Nº 200."
var LAB_FIELD_LABELS = { sieveMaxPct: "Máx.", sieveNo4Pct: "Nº 4", sieve2mmPct: "Nº 10", sieve04mmPct: "Nº 40",
    sieve008mmPct: "Nº 200", liquidLimit: "LL", plasticLimit: "LP", naturalMoisturePct: "Humedad natural",
    primarySucs: "SUCS principal", secondarySucs: "Segundo SUCS", aashto: "AASHTO", testDate: "Fecha de ensayo" }
// Fila Android -> mismo validador Web. projection = lo que Estrato muestra.
function webLabValidate(row, extra) {
    var form=labForm(row, extra), result=validateLaboratoryForm(form), messages=[]
    for(var key in result.errors) messages.push((LAB_FIELD_LABELS[key]||key)+": "+result.errors[key])
    return { valid: result.changes!==null, errors: messages, fieldErrors: result.errors, changes: result.changes,
             projection: formatSucsProjection(form.primarySucs, form.isComposite, form.secondarySucs) }
}


// ===== InGe+ Web parity: identity header (P5) =====
// Mirrors src/lib/calicatas/sheetPresentation.ts and sheetHeaderFields.ts.
var ROAD_SIDE_OPTIONS = ["Derecho", "Izquierdo", "Ambos", "Eje de vía",
    "Berma derecha", "Berma izquierda", "Fuera de vía"]
var MACHINE_OPTIONS = ["Retroexcavadora", "Retroexcavadora mixta", "Miniexcavadora",
    "Excavadora hidráulica", "Cargador frontal", "Zanjadora", "Excavación manual"]
var SUPERVISOR_MAX_LENGTH = 160   // calicatas_supervisor_length_check
var MACHINE_MAX_LENGTH = 120      // calicatas_machine_length_check
var PROGRESIVA_PATTERN = /^\d{2,3}\+\d{3}$/
var PROGRESIVA_SUGGESTION_LIMIT = 100
var CHAINAGE_LADDER = [5, 10, 20, 25, 50, 100, 250, 500, 1000]

// Catalogue value with its canonical spelling, or "" when it is not in it.
function catalogValue(value, options) {
    var wanted = String(value || "").trim().toLowerCase()
    for (var i = 0; i < options.length; ++i)
        if (options[i].toLowerCase() === wanted) return options[i]
    return ""
}

// Digits only; the last three digits are the metres, so "51425" -> "51+425".
function acceptProgresivaDraft(current, next) {
    next = String(next === undefined || next === null ? "" : next)
    if (next === "") return ""
    var digits = next.replace(/\+/g, "")
    if (!/^\d{1,6}$/.test(digits)) return String(current || "")
    if (next.indexOf("+") >= 0 && /^\d{1,3}\+\d{0,3}$/.test(next)) return next
    return digits.length >= 5 ? digits.slice(0, -3) + "+" + digits.slice(-3) : digits
}

function normalizeProgresiva(value) {
    var trimmed = String(value || "").trim()
    if (!/^\d{5,6}$/.test(trimmed)) return trimmed
    return trimmed.slice(0, -3) + "+" + trimmed.slice(-3)
}

function isValidProgresiva(value) {
    return PROGRESIVA_PATTERN.test(String(value || "").trim())
}

function _padChainage(n, width) {
    var s = String(n)
    while (s.length < width) s = "0" + s
    return s
}

function chainageNeighbours(metres) {
    if (!isFinite(metres) || metres < 0) return []
    var seen = {}, values = []
    var push = function(v) { if (v >= 0 && !seen[v]) { seen[v] = true; values.push(v) } }
    push(metres)
    for (var i = 0; i < CHAINAGE_LADDER.length; ++i) {
        push(metres - CHAINAGE_LADDER[i])
        push(metres + CHAINAGE_LADDER[i])
    }
    values.sort(function(a, b) { return a - b })
    return values.map(function(v) {
        return _padChainage(Math.floor(v / 1000), 2) + "+" + _padChainage(v % 1000, 3)
    })
}

function progresivaSuggestions(value) {
    value = String(value || "")
    var digits = value.trim().replace(/\+/g, "")
    var out = [], i
    if (!/^\d+$/.test(digits)) {
        for (i = 0; i < PROGRESIVA_SUGGESTION_LIMIT; ++i) out.push(_padChainage(i, 2) + "+000")
        return out
    }
    var hasSeparator = value.indexOf("+") >= 0
    var kilometreDigits = hasSeparator ? (value.split("+")[0] || "")
        : digits.slice(0, Math.max(digits.length - 3, digits.length > 3 ? 3 : digits.length))
    var metreDigits = hasSeparator ? (value.split("+")[1] || "") : digits.slice(kilometreDigits.length)
    var kilometre = kilometreDigits.length < 2 ? _padChainage(kilometreDigits, 2) : kilometreDigits
    if (!metreDigits) {
        var step = 1000 / PROGRESIVA_SUGGESTION_LIMIT
        for (i = 0; i < PROGRESIVA_SUGGESTION_LIMIT; ++i) out.push(kilometre + "+" + _padChainage(i * step, 3))
        return out
    }
    if (metreDigits.length === 1) {
        var base100 = Number(metreDigits) * 100
        for (i = 0; i < 100; ++i) out.push(kilometre + "+" + _padChainage(base100 + i, 3))
        return out
    }
    if (metreDigits.length === 2) {
        var base10 = Number(metreDigits) * 10
        for (i = 0; i < 10; ++i) out.push(kilometre + "+" + _padChainage(base10 + i, 3))
        return out
    }
    return chainageNeighbours(Number(kilometre) * 1000 + Number(metreDigits.slice(0, 3)))
}

// "CT" + "51+425" -> "CT-51+425"; an existing progresiva suffix is replaced.
function composeCalicataCode(code, progresiva) {
    code = String(code || "")
    var base = code.trim().replace(/-?\d{2,3}\+\d{3}$/, "")
    var prefix = base.replace(/-$/, "")
    return isValidProgresiva(progresiva) ? (prefix ? prefix + "-" : "") + progresiva : code.trim()
}

// Inverse of composeCalicataCode: the valid progresiva a code ends with, or "".
function progresivaFromCode(code) {
    var match = /(?:^|[^\d])(\d{2,3}\+\d{3})$/.exec(String(code || "").trim())
    return match ? match[1] : ""
}

// First corte logged as AGUA marks the water table: its "Desde", 3 decimals.
// `strata` = [{ moistureCondition: "AGUA"|..., fromDepthM: "1.20" }]
function derivedGroundwaterDepth(strata) {
    for (var i = 0; i < strata.length; ++i) {
        if (strata[i].moistureCondition !== "AGUA") continue
        var depth = String(strata[i].fromDepthM || "").trim().replace(",", ".")
        if (!/^\d+(?:\.\d{1,3})?$/.test(depth)) return null
        return Number(depth).toFixed(3)
    }
    return null
}

// Hora opcional de la ficha (header.hora_inicio, rótulo de fotos):
// "" = vacía (las fotos usan su hora del sistema fijada); "H:mm", "HH:mm" o
// "HH:mm:ss" -> "HH:mm:ss"; null si no es una hora válida.
function normalizeOptionalTime(value) {
    var t = String(value === undefined || value === null ? "" : value).trim()
    if (!t.length) return ""
    var m = /^(\d{1,2})[:.](\d{2})(?:[:.](\d{2}))?$/.exec(t)
    if (!m) return null
    var h = Number(m[1]), mi = Number(m[2]), s = m[3] === undefined ? 0 : Number(m[3])
    if (h > 23 || mi > 59 || s > 59) return null
    function two(n) { return (n < 10 ? "0" : "") + n }
    return two(h) + ":" + two(mi) + ":" + two(s)
}

// ISO yyyy-mm-dd dates; "" when valid or incomplete.
function validateFieldDates(startDate, endDate) {
    if (!startDate || !endDate) return ""
    return endDate < startDate ? "La fecha de fin no puede ser anterior a la de inicio." : ""
}


// ===== InGe+ Web parity: laboratory review engine (P2) =====
// Mirrors src/lib/calicatas/soilClassification.ts. It only SUGGESTS: the
// engineer's SUCS/AASHTO (primary_sucs / aashto) stay the confirmed values and
// are never rewritten here. Android keys: gmax=Máx, passing_no4=Nº4 (extra),
// g2=Nº10, g04=Nº40, g008=Nº200, wl=LL, lp=LP, hum2=humedad natural.
// ===== Laboratorio: port exacto de Web feature/calicatas-cloud-media-04a =====
// src/lib/calicatas/soilClassification.ts + laboratoryContract.ts. Sin
// variantes Android: ni NP ni D10/D30/D60 influyen en la clasificación (Web no
// los registra). Un grueso limpio sin Cu/Cc queda como conjunto de candidatos;
// nunca se inventa GW/GP/SW/SP. Sugerir nunca escribe: adoptar es un clic.
var LAB_CLEAN_COARSE_FINES = 5
var LAB_REVIEW_LABELS = { empty: "Sin datos", conforme: "Conforme", incompleto: "Faltan datos", revisar: "Revisar" }

function _labNumber(value) {
    var t = String(value === undefined || value === null ? "" : value).trim().replace(",", ".")
    if (!t.length || !/^-?\d+(?:\.\d+)?$/.test(t)) return null
    var n = Number(t)
    return isFinite(n) ? n : null
}

// Web catalogValue: solo códigos del catálogo (Android antiguo guardaba "Pt").
function _labCatalog(value, catalog) {
    var v = String(value === undefined || value === null ? "" : value).trim().toUpperCase()
    for (var i = 0; i < catalog.length; ++i) if (catalog[i].toUpperCase() === v) return catalog[i]
    return ""
}

// CalicataLaboratoryFormState leído de una fila Android (corte + extra).
// Autoridad de clasificación = extra.primary_sucs / is_composite /
// secondary_sucs / lab_confirmed_aashto (= calicata_lab_results). row.sucs /
// row.aashto son el valor legado del estrato (calicata_strata) y no entran aquí.
function labForm(row, extra) {
    row = row || {}; extra = extra || {}
    function s(v) { return v === undefined || v === null ? "" : String(v) }
    return {
        sieveMaxPct: s(row.gmax), sieveNo4Pct: s(extra.passing_no4), sieve2mmPct: s(row.g2),
        sieve04mmPct: s(row.g04), sieve008mmPct: s(row.g008), liquidLimit: s(row.wl),
        plasticLimit: s(row.lp), naturalMoisturePct: s(row.hum2),
        primarySucs: _labCatalog(extra.primary_sucs, webSucsCodes), isComposite: extra.is_composite === true,
        secondarySucs: _labCatalog(extra.secondary_sucs, webSucsCodes),
        aashto: _labCatalog(extra.lab_confirmed_aashto, webAashtoCodes),
        laboratorySource: s(extra.laboratory_source), testDate: s(extra.test_date)
    }
}

function readSoilSample(form) {
    return { passing4: _labNumber(form.sieveNo4Pct), passing10: _labNumber(form.sieve2mmPct),
             passing40: _labNumber(form.sieve04mmPct), passing200: _labNumber(form.sieve008mmPct),
             liquidLimit: _labNumber(form.liquidLimit), plasticLimit: _labNumber(form.plasticLimit) }
}

// Web plasticityIndex(sample): null mientras falte un límite.
function labPlasticityIndex(sample) {
    if (sample.liquidLimit === null || sample.plasticLimit === null) return null
    return Math.round((sample.liquidLimit - sample.plasticLimit) * 100) / 100
}

function aLinePlasticity(liquidLimit) { return 0.73 * (liquidLimit - 20) }

function classifyAashto(sample) {
    var passing10 = sample.passing10, passing40 = sample.passing40, passing200 = sample.passing200
    var liquidLimit = sample.liquidLimit, pi = labPlasticityIndex(sample)
    if (passing10 === null || passing40 === null || passing200 === null) return null
    if (liquidLimit === null || pi === null) return null
    function groupIndex(code) {
        if (code === "A-1-a" || code === "A-1-b" || code === "A-3" || code === "A-2-4" || code === "A-2-5") return 0
        var fines = passing200
        var partial = 0.01 * Math.max(0, Math.min(40, fines - 15)) * Math.max(0, Math.min(20, pi - 10))
        if (code === "A-2-6" || code === "A-2-7") return Math.max(0, Math.round(partial))
        var first = Math.max(0, Math.min(40, fines - 35)) * (0.2 + 0.005 * Math.max(0, Math.min(20, liquidLimit - 40)))
        return Math.max(0, Math.round(first + partial))
    }
    function decide(code, reason) { return { code: code, groupIndex: groupIndex(code), reason: reason } }
    if (passing200 <= 35) {
        if (passing10 <= 50 && passing40 <= 30 && passing200 <= 15 && pi <= 6)
            return decide("A-1-a", "Granular con pocos finos: pasa 2 mm ≤ 50, 0.4 mm ≤ 30, 0.08 mm ≤ 15 e IP ≤ 6.")
        if (passing40 <= 50 && passing200 <= 25 && pi <= 6)
            return decide("A-1-b", "Granular: pasa 0.4 mm ≤ 50, 0.08 mm ≤ 25 e IP ≤ 6.")
        if (passing40 >= 51 && passing200 <= 10 && pi <= 0)
            return decide("A-3", "Arena fina no plástica: pasa 0.4 mm ≥ 51, 0.08 mm ≤ 10 e IP nulo.")
        if (liquidLimit <= 40 && pi <= 10)
            return decide("A-2-4", "Granular con finos: pasa 0.08 mm ≤ 35, LL ≤ 40 e IP ≤ 10.")
        if (liquidLimit >= 41 && pi <= 10)
            return decide("A-2-5", "Granular con finos limosos de alta compresibilidad: LL ≥ 41 e IP ≤ 10.")
        if (liquidLimit <= 40)
            return decide("A-2-6", "Granular con finos arcillosos: LL ≤ 40 e IP ≥ 11.")
        return decide("A-2-7", "Granular con finos arcillosos de alta compresibilidad: LL ≥ 41 e IP ≥ 11.")
    }
    if (liquidLimit <= 40 && pi <= 10) return decide("A-4", "Limo: pasa 0.08 mm > 35, LL ≤ 40 e IP ≤ 10.")
    if (liquidLimit >= 41 && pi <= 10) return decide("A-5", "Limo de alta compresibilidad: LL ≥ 41 e IP ≤ 10.")
    if (liquidLimit <= 40) return decide("A-6", "Arcilla: LL ≤ 40 e IP ≥ 11.")
    return pi <= liquidLimit - 30
        ? decide("A-7-5", "Arcilla de alta compresibilidad con IP ≤ LL − 30.")
        : decide("A-7-6", "Arcilla de alta compresibilidad con IP > LL − 30.")
}

function coarseDivision(sample) {
    var passing4 = sample.passing4, passing200 = sample.passing200
    if (passing4 === null || passing200 === null) return null
    var coarseFraction = 100 - passing200
    if (coarseFraction <= 0) return null
    var retainedOnNo4 = 100 - passing4
    return retainedOnNo4 > coarseFraction / 2 ? "G" : "S"
}

function _narrowToDivision(candidates, division, reason) {
    var matching = division ? candidates.filter(function(code) { return code.indexOf(division) === 0 }) : []
    var kept = matching.length ? matching : candidates
    var divisionReason = division === "G" ? "Más de la mitad del grueso queda retenido en el Nº 4: es grava."
        : division === "S" ? "Más de la mitad del grueso pasa el Nº 4: es arena."
        : "No se registra el tamiz Nº 4, que separa grava de arena."
    return { candidates: kept, conclusive: kept.length === 1, reason: reason + " " + divisionReason }
}

function recommendSucs(sample) {
    var passing200 = sample.passing200, liquidLimit = sample.liquidLimit, pi = labPlasticityIndex(sample)
    if (passing200 === null) return null
    var aLine
    if (passing200 >= 50) {
        if (liquidLimit === null || pi === null) return null
        aLine = aLinePlasticity(liquidLimit)
        if (liquidLimit >= 50)
            return pi > aLine
                ? { candidates: ["CH"], conclusive: true, reason: "Fino con LL ≥ 50 por encima de la línea A." }
                : { candidates: ["MH", "OH"], conclusive: false, reason: "Fino con LL ≥ 50 bajo la línea A; separar MH de OH exige el ensayo de secado en horno." }
        if (pi > aLine && pi > 7)
            return { candidates: ["CL"], conclusive: true, reason: "Fino con LL < 50, IP > 7 y por encima de la línea A." }
        if (pi < 4 || pi < aLine)
            return { candidates: ["ML", "OL"], conclusive: false, reason: "Fino con LL < 50 bajo la línea A; separar ML de OL exige el ensayo de secado en horno." }
        return { candidates: ["CL", "ML"], conclusive: false, reason: "Fino en la zona CL-ML de la carta de plasticidad (4 ≤ IP ≤ 7)." }
    }
    var division = coarseDivision(sample)
    if (passing200 < LAB_CLEAN_COARSE_FINES)
        return _narrowToDivision(["GW", "GP", "SW", "SP"], division,
            "Grueso limpio (finos < 5 %); la graduación exige Cu y Cc de la curva completa.")
    if (passing200 > 12) {
        if (pi === null || liquidLimit === null)
            return _narrowToDivision(["GM", "GC", "SM", "SC"], division,
                "Grueso con finos (> 12 %), sin límites de Atterberg para saber si son limosos o arcillosos.")
        aLine = aLinePlasticity(liquidLimit)
        return pi > aLine && pi > 7
            ? _narrowToDivision(["GC", "SC"], division, "Grueso con finos arcillosos (sobre la línea A).")
            : _narrowToDivision(["GM", "SM"], division, "Grueso con finos limosos (bajo la línea A o IP ≤ 7).")
    }
    return _narrowToDivision(["GW", "GP", "GM", "GC", "SW", "SP", "SM", "SC"], division,
        "Grueso con 5–12 % de finos: la norma pide una clasificación doble, que esta ficha no registra.")
}

function reviewLaboratorySample(form) {
    var sample = readSoilSample(form), observations = [], pi = labPlasticityIndex(sample)
    var granulometry = [["max", "tamaño máximo", _labNumber(form.sieveMaxPct)], ["no4", "Nº 4", sample.passing4],
                        ["2mm", "Nº 10", sample.passing10], ["04mm", "Nº 40", sample.passing40],
                        ["008mm", "Nº 200", sample.passing200]]
    var missing = granulometry.filter(function(g) { return g[2] === null && g[0] !== "no4" }).map(function(g) { return g[1] })
    if (missing.length)
        observations.push({ id: "granulometry-missing", severity: "missing",
            message: "Falta granulometría: " + missing.join(", ") + ". Sin esos porcentajes no se puede verificar la clasificación." })
    var present = granulometry.filter(function(g) { return g[2] !== null })
    var i
    for (i = 0; i < present.length; ++i)
        if (present[i][2] < 0 || present[i][2] > 100)
            observations.push({ id: "granulometry-range-" + present[i][1], severity: "conflict",
                message: "El porcentaje que pasa " + present[i][1] + " es " + present[i][2] + " %, fuera de 0 a 100." })
    for (i = 1; i < present.length; ++i)
        if (present[i][2] > present[i - 1][2])
            observations.push({ id: "granulometry-order-" + present[i][1], severity: "conflict",
                message: "Pasa " + present[i][1] + " (" + present[i][2] + " %) supera a " + present[i - 1][1] + " (" + present[i - 1][2]
                         + " %): un tamiz más fino nunca deja pasar más material." })
    if (sample.liquidLimit !== null && sample.plasticLimit !== null && pi !== null && pi < 0)
        observations.push({ id: "atterberg-order", severity: "conflict",
            message: "El límite plástico (" + sample.plasticLimit + ") supera al líquido (" + sample.liquidLimit + "): el índice plástico saldría negativo." })
    if (sample.liquidLimit === null || sample.plasticLimit === null)
        observations.push({ id: "atterberg-missing", severity: "missing",
            message: "Faltan los límites de Atterberg; sin LL y LP no se puede clasificar la muestra." })
    if (sample.passing200 !== null && sample.passing200 < LAB_CLEAN_COARSE_FINES && pi !== null && pi > 0)
        observations.push({ id: "atterberg-implausible", severity: "conflict",
            message: "Se declara IP " + pi + " sobre una muestra con " + sample.passing200 + " % de finos (menos del "
                     + LAB_CLEAN_COARSE_FINES + " %). Con esa fracción el ensayo suele reportarse como no plástico; confirma LL y LP contra el acta." })
    var aashto = classifyAashto(sample), sucs = recommendSucs(sample)
    if (aashto && form.aashto && form.aashto !== aashto.code)
        observations.push({ id: "aashto-mismatch", severity: "conflict",
            message: "AASHTO declarado " + form.aashto + ", pero los porcentajes y los límites dan " + aashto.code + ". " + aashto.reason })
    if (sucs && form.primarySucs && sucs.candidates.indexOf(form.primarySucs) < 0)
        observations.push({ id: "sucs-mismatch", severity: "conflict",
            message: "SUCS declarado " + form.primarySucs + ", fuera de lo que permiten los datos (" + sucs.candidates.join(", ") + "). " + sucs.reason })
    // ip: el mismo derivado que la ficha Web muestra; nunca se guarda.
    return { aashto: aashto, sucs: sucs, observations: observations, ip: pi }
}

var LAB_REVIEWED_FIELDS = ["sieveMaxPct", "sieveNo4Pct", "sieve2mmPct", "sieve04mmPct", "sieve008mmPct",
                           "liquidLimit", "plasticLimit", "naturalMoisturePct", "primarySucs", "secondarySucs", "aashto"]
function hasLaboratoryData(form) {
    for (var i = 0; i < LAB_REVIEWED_FIELDS.length; ++i)
        if (String(form[LAB_REVIEWED_FIELDS[i]] || "").trim() !== "") return true
    return false
}

function laboratoryReviewStatus(form, review) {
    if (!hasLaboratoryData(form)) return "empty"
    for (var i = 0; i < review.observations.length; ++i)
        if (review.observations[i].severity === "conflict") return "revisar"
    return review.observations.length ? "incompleto" : "conforme"
}

// Web SuggestedClassification: hasta 4 chips SUCS a la vez, el resto "+N".
var LAB_VISIBLE_SUCS_CANDIDATES = 4
function labSuggestion(form, review) {
    var candidates = review && review.sucs ? review.sucs.candidates : []
    return {
        aashto: review && review.aashto ? { code: review.aashto.code, current: form.aashto === review.aashto.code,
                                            reason: review.aashto.reason } : null,
        sucs: candidates.slice(0, LAB_VISIBLE_SUCS_CANDIDATES).map(function(code) {
            return { code: code, current: form.primarySucs === code } }),
        hidden: Math.max(0, candidates.length - LAB_VISIBLE_SUCS_CANDIDATES),
        reason: review && review.sucs ? review.sucs.reason : review && review.aashto ? review.aashto.reason : "",
        note: review && review.sucs ? (review.sucs.conclusive ? "Determinado por los datos" : "Varias opciones posibles") : ""
    }
}

// Web formatSucsProjection: lo que Estrato muestra (solo lectura).
function formatSucsProjection(primary, isComposite, secondary) {
    primary = _labCatalog(primary, webSucsCodes); secondary = _labCatalog(secondary, webSucsCodes)
    if (!primary) return ""
    return isComposite === true && secondary ? primary + " + " + secondary : primary
}

// Web sucsSymbols.ts: las mismas teselas 24×24 (SUCS/web, generadas del mismo
// SVG). La exportación usa el trazo de impresión (sucsExportSymbolUrl).
function sucsSymbolUrl(code) {
    code = _labCatalog(code, webSucsCodes)
    return code ? "qrc:/SUCS/web/" + code + ".svg" : ""
}
function sucsExportSymbolUrl(code) {
    code = _labCatalog(code, webSucsCodes)
    return code ? "qrc:/SUCS/web/export/" + code + ".svg" : ""
}

// Web resolveCalicataSucsPattern: una capa por código (compuesto = dos).
function resolveCalicataSucsPattern(primary, isComposite, secondary) {
    primary = _labCatalog(primary, webSucsCodes); secondary = _labCatalog(secondary, webSucsCodes)
    var codes = primary ? (isComposite === true && secondary ? [primary, secondary] : [primary]) : []
    return {
        key: codes.length ? "SUCS_" + codes.join("_") : "SUCS_NONE",
        layers: codes.map(function(code, position) { return { id: position + ":" + code, code: code, url: sucsSymbolUrl(code) } }),
        hasVerifiedAsset: codes.length > 0
    }
}

// Proyección del laboratorio para una fila (Estrato, perfil, resumen): una
// sola lectura; Estrato nunca la edita.
function labProjection(plain) {
    var form = labForm(plain, plain)
    return {
        primary: form.primarySucs, isComposite: form.isComposite, secondary: form.secondarySucs,
        aashto: form.aashto,
        sucs: formatSucsProjection(form.primarySucs, form.isComposite, form.secondarySucs),
        pattern: resolveCalicataSucsPattern(form.primarySucs, form.isComposite, form.secondarySucs)
    }
}

// Datos de ensayo (sin clasificación): etapa del estrato en Laboratorio.
function hasLabTestData(form) {
    var keys = ["sieveMaxPct", "sieveNo4Pct", "sieve2mmPct", "sieve04mmPct", "sieve008mmPct",
                "liquidLimit", "plasticLimit", "naturalMoisturePct"]
    for (var i = 0; i < keys.length; ++i) if (String(form[keys[i]] || "").trim() !== "") return true
    return false
}

// Muestra = dato de CAMPO (Perfil), solo lectura en Laboratorio. Contrato Web
// (CalicataLaboratoryResultsTable): "M-XX, intervalo y tipo proceden de Campo".
// La referencia M-XX es solo presentación: nunca se persiste como identidad.
function labSampleSummary(row, index) {
    row = row || {}
    function t(v) { return v === undefined || v === null ? "" : String(v).trim() }
    var type = t(row.tipo_muestra) === "Otro" ? (t(row.tipo_otro) || "Otro") : t(row.tipo_muestra)
    var code = t(row.sample_code)
    var from = t(row.muestra_desde), to = t(row.muestra_hasta), sFrom = t(row.de), sTo = t(row.a)
    // Sin intervalo propio la fila hereda el del estrato: eso no es un intervalo de muestra.
    var own = (from.length > 0 || to.length > 0) && !(from === sFrom && to === sTo)
    var n = (Number(index) || 0) + 1
    return {
        hasSample: type.length > 0 || code.length > 0,
        type: type,
        code: code,
        reference: code.length ? code : "M-" + (n < 10 ? "0" : "") + n,
        referenceIsPresentational: code.length === 0,
        interval: own ? (from || "—") + " – " + (to || "—") + " m" : "",
        stratumInterval: (sFrom || "—") + " – " + (sTo || "—") + " m"
    }
}

// Un solo vocabulario de estado de laboratorio por estrato.
var LAB_STAGE_LABELS = { no_data: "Sin datos", no_test: "Sin ensayo", in_progress: "En proceso",
                         suggested: "Sugerido", confirmed: "Adoptado" }
// confirmed = el técnico adoptó/eligió SUCS o AASHTO en Laboratorio.
function labStage(c) {
    c = c || {}
    if (c.confirmed === true) return "confirmed"
    if (c.hasTests !== true) return c.hasSample === true ? "no_test" : "no_data"
    return c.suggestion === true ? "suggested" : "in_progress"
}

// Web stepLaboratoryPercentDraft: empty starts at the bound in the direction
// of travel; the result is clamped to the live bounds and has two decimals.
function stepLabPercent(current, bounds, direction, step) {
    step = step || 0.01
    if (!bounds || !isFinite(bounds.min) || !isFinite(bounds.max) || bounds.min > bounds.max || !(step > 0)) return String(current || "")
    var parsed = _labNumber(current)
    var candidate = parsed !== null ? parsed + direction * step : (direction === 1 ? bounds.min : bounds.max)
    var bounded = Math.min(bounds.max, Math.max(bounds.min, candidate))
    return (Math.round(bounded * 100) / 100).toFixed(2)
}

// LL / LP: enteros (Web validateInteger; calicata_lab_results.liquid_limit integer).
function stepLabInteger(current, direction, maximum) {
    var parsed = _labNumber(current)
    var next = parsed === null ? 0 : Math.round(parsed) + direction
    next = Math.max(0, Math.min(maximum === undefined ? 999 : maximum, next))
    return String(next)
}


// ===== Clasificación de reporte (Resumen, Excel y PDF) =====
// Web exportModel: el laboratorio es la clasificación de registro; el valor
// anterior del estrato (calicata_strata.sucs/aashto) solo se usa si el
// laboratorio está vacío. label = "SP-SM" si es compuesta.
var REPORT_RA_CODE = "RA"
var REPORT_RA_PATTERN = "qrc:/SUCS/mtc/RE_Relleno_Antropico.svg"
function isAnthropicFill(origin) {
    return /^relleno(?:\s|$)/i.test(String(origin || "").trim())
}
function exportClassification(row) {
    row = row || {}
    var form = labForm(row, row)
    var legacy = patternCodes(row.sucs).map(function(code) { return _labCatalog(code, webSucsCodes) })
    var primary = form.primarySucs || legacy[0] || ""
    var secondary = form.primarySucs ? (form.isComposite ? form.secondarySucs : "") : (legacy[1] || "")
    var labLabel = form.primarySucs && form.isComposite && form.secondarySucs ? form.primarySucs + "-" + form.secondarySucs : form.primarySucs
    return {
        primary: primary, secondary: secondary,
        label: labLabel || _reviewText(row.sucs),
        aashto: form.aashto || _reviewText(row.aashto),
        fromLaboratory: form.primarySucs.length > 0 || form.aashto.length > 0
    }
}

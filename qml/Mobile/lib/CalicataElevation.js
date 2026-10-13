.pragma library
// Altitud / Cota Z de la calicata — política del cliente.
//
// El número NUNCA se calcula ni se consulta desde Android: la app envía las
// coordenadas (y su GPS/cota actual como evidencia) a la Edge Function
// resolve-calicata-elevation, que reúne evidencias geoespaciales reales (Google
// Elevation si está configurada, Copernicus DEM GLO-30/GLO-90), elige el valor
// con reglas deterministas y usa Gemini SOLO como validador estructurado.
// Aquí se decide qué mostrar y qué guardar.
//
// Prioridad: 1) Z manual confirmada  2) servicio de elevación  3) GPS (elipsoidal)  4) vacío.
// Sin dependencias de UI: probado con Node (tests/calicatas/*.cjs).

function validCoordinate(lat, lon) {
    return isFinite(lat) && isFinite(lon) && lat >= -80 && lat <= 84 && Math.abs(lon) <= 180
}

function zText(header) {
    var h = header || {}
    var z = h.utm_z !== undefined && h.utm_z !== null && String(h.utm_z).trim().length ? h.utm_z : h.altitud
    return z === undefined || z === null ? "" : String(z).trim()
}
// Z manual = escrita/confirmada por el técnico (MANUAL) o una cota previa sin
// fuente registrada (fichas existentes, p. ej. 718 de topografía).
function isManual(header) {
    var source = String((header || {}).altitude_source || "")
    return zText(header).length > 0 && (source === "MANUAL" || source === "")
}
// Una resolución automática (tras "Mi ubicación" / punto confirmado) solo puede
// escribir la Z si está vacía o también fue automática.
function autoWriteAllowed(header) {
    return !isManual(header)
}

// Cuerpo para resolve-calicata-elevation (sin datos del proyecto).
function requestBody(header, point, gpsAltitude, gpsAccuracy) {
    var body = { latitude: Number(point.lat), longitude: Number(point.lon) }
    if (isFinite(gpsAltitude)) {
        body.gpsAltitude = Number(gpsAltitude)
        body.gpsVerticalReference = "ellipsoid"   // Android Location.getAltitude(): WGS84 elipsoidal
        if (isFinite(gpsAccuracy)) body.gpsAccuracy = Number(gpsAccuracy)
    }
    var z = Number(zText(header))
    if (zText(header).length && isFinite(z)) {
        body.referenceAltitude = z
        body.referenceSource = isManual(header) ? "Cota manual de la ficha" : "Cota automática anterior"
    }
    return body
}

function _round1(v) { return Math.round(Number(v) * 10) / 10 }
function _text(v) { return String(v === undefined || v === null ? "" : v) }

// Campos persistidos (header local = columnas remotas, 20261007181000).
function serverHeaderPatch(result) {
    var value = String(_round1(result.elevation_m))
    return { utm_z: value, altitud: value, altitude_m: value,
             altitude_source: result.source === "GOOGLE_ELEVATION" ? "GOOGLE_ELEVATION" : "DEM",
             altitude_mode: "AUTOMATICA",
             altitude_confidence: _text(result.confidence),
             altitude_accuracy_m: isFinite(Number(result.accuracy_m)) && result.accuracy_m !== null ? Number(result.accuracy_m) : null,
             altitude_vertical_reference: "terrain_msl",
             altitude_resolved_at: _text(result.resolved_at),
             altitude_evidence: (result.evidence || []).map(function(e) {
                 return { id: _text(e.id), provider: _text(e.provider), value: Number(e.value),
                          vertical_reference: _text(e.vertical_reference),
                          accuracy_m: e.accuracy_m === null || e.accuracy_m === undefined ? null : Number(e.accuracy_m),
                          resolution_m: e.resolution_m === null || e.resolution_m === undefined ? null : Number(e.resolution_m) }
             }),
             altitude_source_detail: _text(result.provider) }
}
// Altura del GPS del teléfono: ELIPSOIDAL (WGS84), nunca rotulada m.s.n.m.
function deviceHeaderPatch(altitude, nowIso) {
    var value = String(_round1(altitude))
    return { utm_z: value, altitud: value, altitude_m: value, altitude_source: "GPS_ELIPSOIDAL",
             altitude_mode: "AUTOMATICA", altitude_confidence: "BAJA", altitude_accuracy_m: null,
             altitude_vertical_reference: "ellipsoid", altitude_resolved_at: nowIso,
             altitude_evidence: [{ id: "device_gps", provider: "GPS del dispositivo", value: Number(value),
                                   vertical_reference: "ellipsoid", accuracy_m: null, resolution_m: null }],
             altitude_source_detail: "GPS del dispositivo · altura elipsoidal (no m.s.n.m.)" }
}
function manualHeaderPatch(value) {
    var t = _text(value).trim()
    return { utm_z: t, altitud: t, altitude_m: t, altitude_source: t.length ? "MANUAL" : "",
             altitude_mode: t.length ? "MANUAL" : "", altitude_confidence: "", altitude_accuracy_m: null,
             altitude_vertical_reference: t.length ? "unknown" : "", altitude_resolved_at: "",
             altitude_evidence: [], altitude_source_detail: "" }
}

// Qué hacer con la respuesta del backend.
//   apply   -> se guarda sin preguntar (Z vacía/automática y evidencias consistentes)
//   confirm -> diálogo "Usar automática / Ingresar manual" (discrepancia o Z manual)
//   none    -> sin valor: queda la edición manual (message explica por qué)
function outcome(result, header, trigger, deviceAltitude, nowIso) {
    var manual = isManual(header)
    if (!result || result.ok !== true) {
        var fallback = isFinite(deviceAltitude) && !manual
            ? { action: "apply", patch: deviceHeaderPatch(deviceAltitude, nowIso),
                message: "Servicio de altitud no disponible; se usó la altura GPS (elipsoidal)." } : null
        return fallback || { action: "none", message: _text(result && result.error) || "No se pudo resolver la altitud. Ingresa la cota manualmente." }
    }
    if (result.elevation_m === null || result.elevation_m === undefined || !isFinite(Number(result.elevation_m))) {
        if (isFinite(deviceAltitude) && !manual)
            return { action: "apply", patch: deviceHeaderPatch(deviceAltitude, nowIso),
                     message: "Sin elevación del terreno; se usó la altura GPS (elipsoidal)." }
        return { action: "none", message: _text(result.warning) || "No se obtuvo la elevación del terreno. Ingresa la cota manualmente." }
    }
    var patch = serverHeaderPatch(result)
    var warning = result.status === "discrepant" ? _text(result.warning) : ""
    if (warning.length || (manual && zText(header) !== patch.utm_z))
        return { action: "confirm", patch: patch, warning: warning }
    return { action: "apply", patch: patch, warning: "" }
}

function sourceLabel(header) {
    var h = header || {}
    var source = _text(h.altitude_source)
    if (source === "GOOGLE_ELEVATION") return "Automática · Google Elevation"
    if (source === "DEM") {
        var detail = _text(h.altitude_source_detail)
        if (!detail.length && h.altitude_evidence && h.altitude_evidence.length) detail = _text(h.altitude_evidence[0].provider)
        return "Automática · DEM" + (detail.length ? " (" + detail + ")" : "")
    }
    if (source === "GPS_ELIPSOIDAL") return "GPS · altura elipsoidal (no m.s.n.m.)"
    return "Manual"
}
function statusText(header) {
    var z = zText(header)
    if (!z.length) return "Sin cota. Pulsa Obtener altitud o escríbela."
    var h = header || {}
    var confidence = _text(h.altitude_confidence)
    return z + " m · " + sourceLabel(h) + (confidence.length && _text(h.altitude_source) !== "MANUAL" ? " · confianza " + confidence.toLowerCase() : "")
}
// Texto del diálogo de decisión.
function decisionText(header, decision) {
    var p = decision.patch
    var lines = ["Cota automática: " + p.utm_z + " m", "Fuente: " + sourceLabel(p)]
    if (decision.warning) lines.push("Advertencia: " + decision.warning)
    if (isManual(header)) lines.push("Cota actual: " + zText(header) + " m (manual).")
    return lines.join("\n")
}

.pragma library

// Bus compartido M08/M09: una sola fuente de coordenadas entre Mapa y Calicatas.
var utmZone = ""
var utmX = NaN
var utmY = NaN

var latitude = NaN
var longitude = NaN
var horizontalAccuracy = NaN
var sourceLabel = ""
var revision = 0

var altitude = NaN
var altitudeOk = false
var timeText = ""
var pending = false

var _appliedX = NaN
var _appliedY = NaN
var _epsMeters = 0.8

function hasFix() {
    return (utmZone && utmZone.length > 0 && isFinite(utmX) && isFinite(utmY))
}

function hasGeoFix() {
    return isFinite(latitude) && isFinite(longitude)
}

function altitudeText() {
    return altitudeOk ? Number(altitude).toFixed(1) : ""
}

function accuracyText() {
    return isFinite(horizontalAccuracy) ? Number(horizontalAccuracy).toFixed(1) + " m" : "--"
}

function clear() {
    utmZone = ""
    utmX = NaN
    utmY = NaN
    latitude = NaN
    longitude = NaN
    horizontalAccuracy = NaN
    sourceLabel = ""
    altitude = NaN
    altitudeOk = false
    timeText = ""
    pending = false
    _appliedX = NaN
    _appliedY = NaN
    revision += 1
}

function markApplied() {
    _appliedX = utmX
    _appliedY = utmY
    pending = false
}

function _changedFromApplied() {
    if (!isFinite(_appliedX) || !isFinite(_appliedY)) return true
    if (!isFinite(utmX) || !isFinite(utmY)) return false
    return (Math.abs(utmX - _appliedX) > _epsMeters) || (Math.abs(utmY - _appliedY) > _epsMeters)
}

function _utmZoneFromLon(lon) { return Math.floor((lon + 180.0) / 6.0) + 1 }

function _utmBandFromLat(lat) {
    var bands = "CDEFGHJKLMNPQRSTUVWX"
    var idx = Math.floor((lat + 80.0) / 8.0)
    if (idx < 0) idx = 0
    if (idx > 19) idx = 19
    return bands.charAt(idx)
}

function latLonToUTM(latDeg, lonDeg) {
    var a = 6378137.0
    var f = 1.0 / 298.257223563
    var k0 = 0.9996
    var e2 = f * (2.0 - f)
    var ep2 = e2 / (1.0 - e2)
    var lat = latDeg * Math.PI / 180.0
    var lon = lonDeg * Math.PI / 180.0
    var zone = _utmZoneFromLon(lonDeg)
    var lon0Deg = -183.0 + zone * 6.0
    var lon0 = lon0Deg * Math.PI / 180.0
    var sinLat = Math.sin(lat)
    var cosLat = Math.cos(lat)
    var tanLat = Math.tan(lat)
    var N = a / Math.sqrt(1.0 - e2 * sinLat * sinLat)
    var T = tanLat * tanLat
    var C = ep2 * cosLat * cosLat
    var A = cosLat * (lon - lon0)
    var e4 = e2 * e2
    var e6 = e4 * e2
    var M = a * (
        (1.0 - e2/4.0 - 3.0*e4/64.0 - 5.0*e6/256.0) * lat
        - (3.0*e2/8.0 + 3.0*e4/32.0 + 45.0*e6/1024.0) * Math.sin(2.0*lat)
        + (15.0*e4/256.0 + 45.0*e6/1024.0) * Math.sin(4.0*lat)
        - (35.0*e6/3072.0) * Math.sin(6.0*lat)
    )
    var easting = k0 * N * (A + (1.0 - T + C) * Math.pow(A,3)/6.0
        + (5.0 - 18.0*T + T*T + 72.0*C - 58.0*ep2) * Math.pow(A,5)/120.0) + 500000.0
    var northing = k0 * (M + N * tanLat * (A*A/2.0
        + (5.0 - T + 9.0*C + 4.0*C*C) * Math.pow(A,4)/24.0
        + (61.0 - 58.0*T + T*T + 600.0*C - 330.0*ep2) * Math.pow(A,6)/720.0))
    if (latDeg < 0) northing += 10000000.0
    return { zone: zone, band: _utmBandFromLat(latDeg), easting: easting, northing: northing }
}

function updateFromGeo(lat, lon, alt, altValid, hhmmss, accuracyMeters, source) {
    latitude = Number(lat)
    longitude = Number(lon)
    horizontalAccuracy = Number(accuracyMeters)
    sourceLabel = source || "GPS"
    var u = latLonToUTM(latitude, longitude)
    updateUtm(String(u.zone) + u.band, u.easting, u.northing, alt, altValid, hhmmss)
}

function updateUtm(zone, x, y, alt, altValid, hhmmss) {
    utmZone = (zone || "")
    utmX = Number(x)
    utmY = Number(y)
    altitude = Number(alt)
    altitudeOk = !!altValid && isFinite(altitude)
    timeText = (hhmmss || "")
    pending = hasFix() && _changedFromApplied()
    revision += 1
}

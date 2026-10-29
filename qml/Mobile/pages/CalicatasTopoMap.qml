import QtQuick
import QtLocation
import QtPositioning
import "../components" as Components
import "../renditions/RStyle.js" as S

// Mapa topográfico interactivo del Home de Calicatas sobre Qt Location (Map +
// plugin "osm" con servidor de teselas propio). El motor de Qt gestiona la
// descarga, la caché en memoria, disco y textura, la precarga de niveles
// vecinos y, mientras llegan las teselas de un nivel nuevo, sigue dibujando
// las del nivel anterior ampliadas: no quedan regiones vacías al acercar,
// alejar o desplazar.
// Base topográfica: OpenTopoMap (CC-BY-SA, datos © OpenStreetMap; máx. z17).
// Capa alternativa: OpenStreetMap estándar (máx. z19). Sin claves propias.
// Gestos propios (Map de Qt 6 no trae): arrastrar, pellizcar (zoom + rotación
// con el punto bajo los dedos fijo), doble toque y rueda. Marcadores con
// MapQuickItem (siguen su coordenada sin cálculo en QML por fotograma).
// El Map se crea la primera vez que la página del mapa se muestra (no durante
// la entrada a Calicatas) y se conserva después: cámara y caché sobreviven al
// ir a la lista y volver. Cambiar de capa recrea solo el Map (cada capa es un
// Plugin distinto); la cámara vive en este Item.
Item {
    id: map
    property var ui
    property var flow
    // [{ key, lat, lon, code, status }] — solo fichas con coordenadas válidas.
    property var markers: []
    property string selectedKey: ""
    property real bottomInset: 0                // reserva del Dock
    property real topInset: ui && ui.topInset !== undefined ? ui.topInset : 0
    property bool topoLayer: true
    // El Home lo desactiva mientras la página del mapa no se ve.
    property bool active: true
    // Pruebas de escritorio: servidor de teselas y caché locales.
    property string tileHostOverride: ""
    property string cacheDirectoryOverride: ""
    signal markerTapped(var marker, real x, real y)
    signal backgroundTapped()

    readonly property string tileHost: tileHostOverride.length ? tileHostOverride
                                     : topoLayer ? "https://tile.opentopomap.org/" : "https://tile.openstreetmap.org/"
    readonly property int maxZoom: topoLayer ? 17 : 19
    readonly property int minZoom: 3
    readonly property real tileSize: 256
    readonly property real u: ui ? ui.u : 1
    readonly property color backgroundColor: "#E9EEF2"

    // Cámara (fuente de verdad mientras no hay Map; espejo del Map cuando existe).
    property real centerLat: -9.2
    property real centerLon: -75.0
    property real zoom: 5
    property real bearing: 0
    readonly property int tileZoom: Math.floor(zoom)
    readonly property real originX: width / 2                            // centro óptico (sobre el Dock)
    readonly property real originY: (height - bottomInset) / 2
    readonly property bool running: active && visible && width > 0 && height > 0
                                    && Qt.application.state === Qt.ApplicationActive
    property bool everActive: false
    readonly property var geoMap: engine.item
    readonly property bool mapReady: !!geoMap && geoMap.mapReady === true
    property string mapError: ""

    function _trace(msg) { console.info("INGE_CALICATA_MAP_" + msg) }
    onRunningChanged: {
        _trace("ACTIVE running=" + running)
        if (running && !everActive) everActive = true
    }
    onTileZoomChanged: _trace("LEVEL to=" + tileZoom + " zoom=" + zoom.toFixed(2))

    // ---- Web Mercator (para encuadres sin depender de que exista el Map).
    function worldX(lon) { return (lon + 180) / 360 }
    function worldY(lat) {
        var r = Math.max(-85.0511, Math.min(85.0511, lat)) * Math.PI / 180
        return (1 - Math.log(Math.tan(r) + 1 / Math.cos(r)) / Math.PI) / 2
    }
    function latFromWorldY(y) { return Math.atan(Math.sinh(Math.PI * (1 - 2 * y))) * 180 / Math.PI }
    function lonFromWorldX(x) { return x * 360 - 180 }
    function clampZoom(v) { return Math.max(minZoom, Math.min(maxZoom, v)) }
    function normalizedBearing(b) { var x = b % 360; return x < 0 ? x + 360 : x }

    // ---- Sincronía cámara <-> Map (sin bindings en ambos sentidos).
    property bool _syncing: false
    function _pushCamera() {
        var m = geoMap
        if (!m || _syncing) return
        _syncing = true
        if (Math.abs(m.zoomLevel - zoom) > 1e-9) m.zoomLevel = zoom
        if (Math.abs(m.bearing - bearing) > 1e-9) m.bearing = bearing
        var c = m.center
        if (Math.abs(c.latitude - centerLat) > 1e-12 || Math.abs(c.longitude - centerLon) > 1e-12)
            m.center = QtPositioning.coordinate(centerLat, centerLon)
        _syncing = false
        _pullCamera()                                            // el Map pudo acotar el zoom
    }
    function _pullCamera() {
        var m = geoMap
        if (!m || _syncing) return
        _syncing = true
        zoom = m.zoomLevel
        bearing = m.bearing
        centerLat = m.center.latitude
        centerLon = m.center.longitude
        _syncing = false
    }
    onZoomChanged: _pushCamera()
    onBearingChanged: _pushCamera()
    onCenterLatChanged: _pushCamera()
    onCenterLonChanged: _pushCamera()
    function setCamera(lat, lon, z) {
        _syncing = true                                          // un solo envío al Map
        centerLat = lat; centerLon = lon; zoom = clampZoom(z)
        _syncing = false
        _pushCamera()
    }
    // Centro del Map (centro del ítem) para que el punto (lat, lon) quede en el centro óptico.
    function _cameraFor(lat, lon, z) {
        var scale = tileSize * Math.pow(2, z)
        var wy = worldY(lat) + (height / 2 - originY) / scale
        return { lat: latFromWorldY(wy), lon: lon }
    }

    // Encuadra los marcadores reales (vista general del Perú si ninguno tiene coordenadas).
    function fitToMarkers() {
        var list = markers || []
        if (!list.length) { var pe = _cameraFor(-9.2, -75.0, 5); setCamera(pe.lat, pe.lon, 5); return }
        var minX = 1, maxX = 0, minY = 1, maxY = 0
        for (var i = 0; i < list.length; ++i) {
            var x = worldX(list[i].lon), y = worldY(list[i].lat)
            minX = Math.min(minX, x); maxX = Math.max(maxX, x)
            minY = Math.min(minY, y); maxY = Math.max(maxY, y)
        }
        var spanX = Math.max(1e-7, maxX - minX), spanY = Math.max(1e-7, maxY - minY)
        var usableW = Math.max(120, width - 96 * u), usableH = Math.max(120, height - bottomInset - topInset - 160 * u)
        var zx = Math.log(usableW / (spanX * tileSize)) / Math.LN2
        var zy = Math.log(usableH / (spanY * tileSize)) / Math.LN2
        var z = clampZoom(Math.min(list.length === 1 ? 15 : 16, Math.min(zx, zy)))
        var c = _cameraFor(latFromWorldY((minY + maxY) / 2), lonFromWorldX((minX + maxX) / 2), z)
        setCamera(c.lat, c.lon, z)
    }
    function centerOn(lat, lon, minZoomLevel) {
        var z = minZoomLevel !== undefined && zoom < minZoomLevel ? minZoomLevel : zoom
        var c = _cameraFor(lat, lon, clampZoom(z))
        setCamera(c.lat, c.lon, z)
    }
    // Zoom manteniendo fijo el punto de pantalla (px, py): pellizco, rueda y doble toque.
    function zoomAround(newZoom, px, py) {
        newZoom = clampZoom(newZoom)
        var m = geoMap
        if (!m) { zoom = newZoom; return }
        var c = m.toCoordinate(Qt.point(px, py), false)
        m.zoomLevel = newZoom
        if (c.isValid) m.alignCoordinateToPoint(c, Qt.point(px, py))
        _pullCamera()
    }
    property real _animZoom: 5
    property point _animAnchor: Qt.point(0, 0)
    on_AnimZoomChanged: if (zoomAnim.running) zoomAround(_animZoom, _animAnchor.x, _animAnchor.y)
    function animateZoomTo(target, px, py) {
        zoomAnim.stop()
        _animAnchor = px === undefined ? Qt.point(originX, originY) : Qt.point(px, py)
        _animZoom = zoom
        zoomAnim.to = clampZoom(target)
        zoomAnim.start()
    }
    function zoomBy(delta) { animateZoomTo(Math.round(zoom) + delta) }
    NumberAnimation { id: zoomAnim; target: map; property: "_animZoom"; duration: 240; easing.type: Easing.OutCubic }
    // Brújula: vuelve al norte arriba por el camino más corto.
    function resetNorth() {
        var b = normalizedBearing(bearing)
        bearing = b > 180 ? b - 360 : b
        northAnim.restart()
    }
    NumberAnimation { id: northAnim; target: map; property: "bearing"; to: 0; duration: 260; easing.type: Easing.OutCubic }
    // Desplazamiento del contenido en pantalla (el dedo arrastra el mapa).
    function panBy(dx, dy) {
        var m = geoMap
        if (!m) {
            var scale = tileSize * Math.pow(2, zoom)
            centerLon = lonFromWorldX(Math.max(0, Math.min(1, worldX(centerLon) - dx / scale)))
            centerLat = latFromWorldY(Math.max(0, Math.min(1, worldY(centerLat) - dy / scale)))
            return
        }
        var c = m.toCoordinate(Qt.point(m.width / 2 - dx, m.height / 2 - dy), false)
        if (c.isValid) m.center = c
        _pullCamera()
    }
    // Punto de pantalla de una coordenada (coordenadas de este Item).
    function screenPoint(lat, lon) {
        var m = geoMap
        if (m) { var p = m.fromCoordinate(QtPositioning.coordinate(lat, lon), false); return Qt.point(p.x, p.y) }
        var scale = tileSize * Math.pow(2, zoom)
        return Qt.point(width / 2 + (worldX(lon) - worldX(centerLon)) * scale,
                        height / 2 + (worldY(lat) - worldY(centerLat)) * scale)
    }
    // Borde superior de la gota de un marcador, o null.
    function markerScreenPoint(key) {
        var list = markers || []
        for (var i = 0; i < list.length; ++i) {
            if (list[i].key !== key) continue
            var p = screenPoint(list[i].lat, list[i].lon)
            return Qt.point(p.x, p.y - 40 * u)
        }
        return null
    }
    // ¿Hay un marcador bajo el punto? (gota + etiqueta; el más alto gana). El fondo
    // no cierra el detalle en el mismo toque que lo abre.
    function pinAt(px, py) {
        var list = markers || [], hit = null
        for (var i = 0; i < list.length; ++i) {
            var p = screenPoint(list[i].lat, list[i].lon)
            if (px >= p.x - 18 * u && px <= p.x + 130 * u && py >= p.y - 44 * u && py <= p.y + 6 * u) hit = list[i]
        }
        return hit
    }

    // ======================================================= GPS nativo
    // Reutiliza el GPS nativo de InGe+ (Perms); nunca inventa una posición.
    //   ready | waiting | denied | disabled | stale | unavailable
    property int gpsRevision: 0
    readonly property string gpsState: {
        var dep = gpsRevision
        if (typeof Perms === "undefined" || !Perms) return "unavailable"
        if (Perms.hasLocationPermission && !Perms.hasLocationPermission()) return "denied"
        var st = String(Perms.nativeLocationStatus || "")
        if (st === "service_disabled" || st === "no_provider"
                || (Perms.isLocationServiceEnabled && !Perms.isLocationServiceEnabled())) return "disabled"
        if (deviceFix()) return "ready"
        return Perms.nativeHasFix ? "stale" : "waiting"
    }
    readonly property var gpsLabels: ({ ready: "Ubicación GPS disponible", waiting: "Esperando una posición GPS real…",
                                        denied: "Permiso de ubicación denegado", disabled: "Ubicación del teléfono desactivada",
                                        stale: "La última posición GPS caducó; esperando una nueva…",
                                        unavailable: "GPS no disponible en este equipo" })
    property bool awaitingDeviceCenter: false
    property string gpsMessage: ""
    function deviceFix() {
        if (typeof Perms === "undefined" || !Perms || !Perms.nativeHasFix) return null
        var lat = Number(Perms.nativeLatitude), lon = Number(Perms.nativeLongitude), at = Number(Perms.nativeTimestampMs)
        if (!isFinite(lat) || !isFinite(lon) || Math.abs(lat) > 90 || Math.abs(lon) > 180
                || (lat === 0 && lon === 0) || !isFinite(at) || at <= 0 || Math.abs(Date.now() - at) > 120000) return null
        return { lat: lat, lon: lon }
    }
    function useDeviceFix() {
        var f = deviceFix()
        if (!f) return false
        map.centerOn(f.lat, f.lon, 15)
        awaitingDeviceCenter = false
        deviceFixTimeout.stop()
        _showGps("Centrado en tu ubicación GPS")
        return true
    }
    function _showGps(text) { gpsMessage = text; gpsMessageTimer.restart() }
    function centerOnDeviceOrMarkers() {
        gpsRevision++
        var st = gpsState
        _trace("GPS state=" + st)
        if (st === "ready") { useDeviceFix(); return }
        _showGps(gpsLabels[st] || "")
        if (st === "unavailable") return
        if (st === "denied") { if (Perms.requestLocationPermission) Perms.requestLocationPermission(); return }
        if (st === "disabled") { if (Perms.openLocationSettings) Perms.openLocationSettings(); return }
        awaitingDeviceCenter = true                                // waiting | stale: pide una posición real
        deviceFixTimeout.restart()
        if (Perms.requestImmediateLocationUpdate) Perms.requestImmediateLocationUpdate()
        else if (Perms.refreshNativeLocation) Perms.refreshNativeLocation()
    }
    Timer {
        id: deviceFixTimeout
        interval: 15000
        onTriggered: {
            if (!map.awaitingDeviceCenter) return
            map.awaitingDeviceCenter = false
            map._trace("GPS timeout")
            map._showGps("No llegó una posición GPS. El mapa no se movió.")
        }
    }
    Timer { id: gpsMessageTimer; interval: 4000; onTriggered: map.gpsMessage = "" }
    Timer { interval: 30000; repeat: true; running: map.running; onTriggered: map.gpsRevision++ }   // caducidad
    Connections {
        target: typeof Perms !== "undefined" ? Perms : null
        ignoreUnknownSignals: true
        function onNativeLocationChanged() { map.gpsRevision++; if (map.awaitingDeviceCenter) map.useDeviceFix() }
        function onNativeLocationStatusChanged() { map.gpsRevision++ }
        function onNativePermissionChanged() { map.gpsRevision++ }
    }

    // ================================================== Motor Qt Location
    property bool _reloading: false
    onTileHostChanged: if (everActive) { _reloading = true; Qt.callLater(function() { map._reloading = false }) }
    Rectangle { anchors.fill: parent; color: map.backgroundColor }
    Loader {
        id: engine
        objectName: "mapEngine"
        anchors.fill: parent
        active: map.everActive && !map._reloading
        sourceComponent: Component {
            Map {
                id: geo
                color: map.backgroundColor
                copyrightsVisible: false                      // atribución propia, siempre visible
                minimumZoomLevel: map.minZoom
                maximumZoomLevel: map.maxZoom
                plugin: Plugin {
                    name: "osm"
                    // Sin repositorio remoto de proveedores: solo el servidor configurado.
                    PluginParameter { name: "osm.mapping.providersrepository.disabled"; value: true }
                    PluginParameter { name: "osm.mapping.custom.host"; value: map.tileHost }
                    PluginParameter { name: "osm.mapping.custom.mapcopyright"; value: map.topoLayer ? "OpenTopoMap (CC-BY-SA)" : "OpenStreetMap" }
                    PluginParameter { name: "osm.mapping.custom.datacopyright"; value: "OpenStreetMap contributors" }
                    // Política de uso de teselas: agente identificable.
                    PluginParameter { name: "osm.useragent"; value: "InGePlus-Android-Calicatas/1.0" }
                    PluginParameter { name: "osm.mapping.highdpi_tiles"; value: false }
                    // Perfil LOW (Mali-G52): un nivel vecino precargado, cachés acotadas.
                    PluginParameter { name: "osm.mapping.prefetching_style"; value: "PrefetchNeighbourLayer" }
                    PluginParameter { name: "osm.mapping.cache.disk.size"; value: 104857600 }
                    PluginParameter { name: "osm.mapping.cache.memory.size"; value: 8388608 }
                    PluginParameter { name: "osm.mapping.cache.texture.size"; value: 25165824 }
                    PluginParameter { name: map.cacheDirectoryOverride.length ? "osm.mapping.cache.directory" : "osm.mapping.cache.unused"
                                      value: map.cacheDirectoryOverride }
                }
                Component.onCompleted: {
                    for (var i = 0; i < supportedMapTypes.length; ++i)
                        if (supportedMapTypes[i].style === MapType.CustomMap) activeMapType = supportedMapTypes[i]
                    zoomLevel = map.zoom
                    bearing = map.bearing
                    center = QtPositioning.coordinate(map.centerLat, map.centerLon)
                    map._trace("ENGINE created type=" + (activeMapType ? activeMapType.name : "?")
                               + " layer=" + (map.topoLayer ? "topo" : "osm"))
                }
                onMapReadyChanged: if (mapReady) { map._trace("ENGINE ready"); map._pushCamera() }
                onErrorChanged: {
                    map.mapError = error === Map.NoError ? "" : String(errorString || error)
                    if (map.mapError.length) map._trace("ENGINE error code=" + error)
                }
                onCenterChanged: map._pullCamera()
                onZoomLevelChanged: map._pullCamera()
                onBearingChanged: map._pullCamera()

                // ---- Posición GPS real del teléfono (solo con una posición vigente).
                MapQuickItem {
                    readonly property var fix: map.gpsState === "ready" ? map.deviceFix() : null
                    visible: !!fix
                    coordinate: fix ? QtPositioning.coordinate(fix.lat, fix.lon) : QtPositioning.coordinate()
                    anchorPoint.x: 9 * map.u
                    anchorPoint.y: 9 * map.u
                    z: 2
                    sourceItem: Rectangle {
                        width: 18 * map.u; height: width; radius: width / 2
                        color: S.corporateBlue
                        border.width: 3 * map.u
                        border.color: "#FFFFFF"
                    }
                }

                // ---- Marcadores de calicatas (uno por ficha con coordenadas reales).
                MapItemView {
                    model: map.markers
                    delegate: MapQuickItem {
                        id: pinItem
                        required property var modelData
                        readonly property bool selected: map.selectedKey === modelData.key
                        coordinate: QtPositioning.coordinate(modelData.lat, modelData.lon)
                        anchorPoint.x: 16 * map.u                     // punta de la gota sobre la coordenada
                        anchorPoint.y: 40 * map.u
                        z: selected ? 4 : 3
                        sourceItem: Item {
                            id: pin
                            readonly property bool isMapPin: true
                            readonly property color tone: S.statusColor(pinItem.modelData.status)
                            objectName: "mapPin_" + pinItem.modelData.key
                            width: label.x + label.width
                            height: 44 * map.u
                            Rectangle {                               // gota del marcador
                                id: drop
                                width: 32 * map.u; height: width
                                radius: width / 2
                                color: pin.tone
                                border.width: 2 * map.u
                                border.color: "#FFFFFF"
                                scale: pinItem.selected ? 1.15 : 1
                                Behavior on scale { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
                                Rectangle { anchors.centerIn: parent; width: 10 * map.u; height: width; radius: width / 2; color: "#FFFFFF" }
                                Rectangle {                           // punta hacia la coordenada
                                    width: 12 * map.u; height: width
                                    rotation: 45
                                    color: pin.tone
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    y: parent.height - height / 2 - 2 * map.u
                                    z: -1
                                }
                            }
                            Rectangle {                               // código sobre vidrio
                                id: label
                                x: drop.width + 4 * map.u
                                y: (drop.height - height) / 2
                                width: codeText.implicitWidth + 16 * map.u
                                height: 28 * map.u
                                radius: height / 2
                                color: S.glass(0.86)
                                border.width: 1
                                border.color: S.ink(0.06)
                                Text {
                                    id: codeText
                                    anchors.centerIn: parent
                                    text: pinItem.modelData.code || "Sin código"
                                    color: S.text
                                    font.family: map.ui ? map.ui.fontFamily : ""
                                    font.pixelSize: 15 * map.u
                                    font.weight: Font.DemiBold
                                }
                            }
                            function openMarkerDetail(kind) {
                                var p = map.markerScreenPoint(pinItem.modelData.key)
                                map._trace("MARKER_OPEN gesture=" + kind)
                                map.markerTapped(pinItem.modelData, p.x, p.y)
                            }
                            // Toque corto o pulsación prolongada (3D Touch) abren el detalle;
                            // un arrastre lo toma el paneo del mapa y cancela el toque.
                            TapHandler {
                                gesturePolicy: TapHandler.ReleaseWithinBounds
                                onTapped: pin.openMarkerDetail("tap")
                                onLongPressed: pin.openMarkerDetail("press")
                            }
                            Accessible.role: Accessible.Button
                            Accessible.name: "Calicata " + (pinItem.modelData.code || "")
                        }
                    }
                }
            }
        }
    }
    Connections {
        target: Qt.application
        function onStateChanged() { map._trace("APP_STATE state=" + Qt.application.state) }
    }
    Connections {                               // superficie GL perdida/recuperada (Android)
        target: map.Window.window
        ignoreUnknownSignals: true
        function onSceneGraphError(error, message) { map._trace("SG_ERROR code=" + error) }
        function onSceneGraphInvalidated() { map._trace("SG_INVALIDATED") }
        function onSceneGraphInitialized() { map._trace("SG_INITIALIZED") }
    }

    // ---- Gestos: arrastrar, pellizcar (zoom + rotación), doble toque y rueda.
    DragHandler {
        id: panHandler
        target: null
        property real lastX: NaN
        property real lastY: NaN
        onActiveChanged: {
            if (active) zoomAnim.stop()
            lastX = active ? centroid.position.x : NaN
            lastY = active ? centroid.position.y : NaN
        }
        onCentroidChanged: {
            if (!active) return
            var x = centroid.position.x, y = centroid.position.y
            if (isFinite(lastX) && isFinite(lastY))
                map.panBy(x - lastX, y - lastY)
            lastX = x
            lastY = y
        }
    }
    PinchHandler {
        target: null
        property real startZoom: map.zoom
        property real startBearing: map.bearing
        onActiveChanged: if (active) { zoomAnim.stop(); northAnim.stop(); startZoom = map.zoom; startBearing = map.bearing }
        onActiveScaleChanged: map.zoomAround(startZoom + Math.log(activeScale) / Math.LN2, centroid.position.x, centroid.position.y)
        // Girar los dedos en sentido horario gira el contenido igual (cámara opuesta).
        onActiveRotationChanged: map.bearing = startBearing - activeRotation
    }
    WheelHandler {
        target: null
        onWheel: function(event) { map.zoomAround(map.zoom + (event.angleDelta.y > 0 ? 0.5 : -0.5), event.x, event.y) }
    }
    TapHandler {
        onDoubleTapped: function(eventPoint) {
            if (!map.pinAt(eventPoint.position.x, eventPoint.position.y))
                map.animateZoomTo(Math.round(map.zoom) + 1, eventPoint.position.x, eventPoint.position.y)
        }
        onSingleTapped: function(eventPoint) {
            if (!map.pinAt(eventPoint.position.x, eventPoint.position.y)) map.backgroundTapped()
        }
    }

    // ---- Controles (vidrio).
    component MapButton: Rectangle {
        id: mapButton
        property string iconName: ""
        property string accessibleName: ""
        default property alias content: slot.data
        signal activated()
        signal longActivated()
        width: 52 * map.u; height: width
        radius: width / 2
        color: tap.pressed ? S.glass(0.98) : S.glass(0.86)
        border.width: 1
        border.color: S.ink(0.06)
        scale: tap.pressed ? 0.94 : 1
        Behavior on scale { NumberAnimation { duration: 120 } }
        Rectangle { z: -1; anchors.fill: parent; anchors.topMargin: 4 * map.u; radius: parent.radius; color: S.ink(0.06) }
        Components.FlowIcon {
            visible: mapButton.iconName.length > 0
            anchors.centerIn: parent
            width: 24 * map.u; height: width
            name: mapButton.iconName
            flow: map.flow
            tintColor: S.navyDark
            activeTintColor: S.navyDark
            inactiveOpacity: 1
        }
        Item { id: slot; anchors.fill: parent }
        TapHandler {
            id: tap
            onTapped: mapButton.activated()
            onLongPressed: mapButton.longActivated()
        }
        Accessible.role: Accessible.Button
        Accessible.name: mapButton.accessibleName
    }
    Column {
        id: controls
        objectName: "mapControls"
        anchors.right: parent.right
        anchors.rightMargin: 16 * map.u
        y: map.topInset + 64 * map.u
        spacing: 12 * map.u
        // Brújula real: indica el norte del mapa rotado; tocarla orienta al norte.
        MapButton {
            objectName: "mapCompass"
            accessibleName: "Brújula: orientar el mapa al norte"
            onActivated: map.resetNorth()
            Item {
                anchors.centerIn: parent
                width: 30 * map.u; height: width
                rotation: -map.bearing
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    y: -2 * map.u
                    text: "N"
                    color: S.navyDark
                    font.family: map.ui ? map.ui.fontFamily : ""
                    font.pixelSize: 11 * map.u
                    font.weight: Font.Bold
                }
                Rectangle {                               // aguja: mitad norte
                    width: 7 * map.u; height: 12 * map.u
                    anchors.horizontalCenter: parent.horizontalCenter
                    y: 11 * map.u
                    radius: 2 * map.u
                    color: S.navyDark
                }
                Rectangle {                               // aguja: mitad sur
                    width: 7 * map.u; height: 7 * map.u
                    anchors.horizontalCenter: parent.horizontalCenter
                    y: 23 * map.u
                    radius: 2 * map.u
                    color: S.ink(0.25)
                }
            }
        }
        MapButton {
            objectName: "mapFit"
            iconName: "map.recenter"
            accessibleName: map.gpsLabels[map.gpsState] + ". Tocar: mi ubicación GPS; mantener pulsado: encuadrar calicatas"
            onActivated: map.centerOnDeviceOrMarkers()
            onLongActivated: map.fitToMarkers()
            Rectangle {                                   // estado GPS (verde listo, ámbar esperando, rojo bloqueado)
                objectName: "mapGpsState"
                anchors.right: parent.right; anchors.top: parent.top
                anchors.margins: 6 * map.u
                width: 10 * map.u; height: width; radius: width / 2
                border.width: 1.5 * map.u; border.color: "#FFFFFF"
                visible: map.gpsState !== "unavailable"
                color: map.gpsState === "ready" ? S.corporateGreen
                     : map.gpsState === "waiting" || map.gpsState === "stale" ? S.warning : S.syncErrorRed
            }
        }
        MapButton { objectName: "mapLayers"; iconName: "map.layers"
                    accessibleName: map.topoLayer ? "Cambiar a mapa estándar" : "Cambiar a mapa topográfico"
                    onActivated: map.topoLayer = !map.topoLayer }
    }
    Rectangle {                                       // aviso de ubicación (temporal)
        objectName: "mapGpsMessage"
        visible: map.gpsMessage.length > 0
        anchors.horizontalCenter: parent.horizontalCenter
        y: map.topInset + 64 * map.u
        width: Math.min(parent.width - 150 * map.u, gpsText.implicitWidth + 28 * map.u)
        height: gpsText.implicitHeight + 16 * map.u
        radius: 16 * map.u
        color: S.glass(0.92)
        border.width: 1; border.color: S.ink(0.06)
        Text {
            id: gpsText
            anchors.centerIn: parent
            width: parent.width - 28 * map.u
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
            text: map.gpsMessage
            color: S.text
            font.family: map.ui ? map.ui.fontFamily : ""
            font.pixelSize: 13 * map.u
        }
    }
    Rectangle {                                       // zoom +/- (cápsula)
        objectName: "mapZoomControls"
        anchors.right: parent.right
        anchors.rightMargin: 16 * map.u
        anchors.bottom: parent.bottom
        anchors.bottomMargin: map.bottomInset + 24 * map.u
        width: 52 * map.u
        height: 112 * map.u
        radius: 18 * map.u
        color: S.glass(0.86)
        border.width: 1
        border.color: S.ink(0.06)
        Column {
            anchors.fill: parent
            Item {
                width: parent.width; height: parent.height / 2
                Text { anchors.centerIn: parent; text: "+"; color: S.navyDark; font.pixelSize: 28 * map.u; font.family: map.ui ? map.ui.fontFamily : "" }
                TapHandler { onTapped: map.zoomBy(1) }
                Accessible.role: Accessible.Button; Accessible.name: "Acercar"
            }
            Rectangle { width: parent.width - 16 * map.u; x: 8 * map.u; height: 1; color: S.ink(0.08) }
            Item {
                width: parent.width; height: parent.height / 2 - 1
                Text { anchors.centerIn: parent; text: "−"; color: S.navyDark; font.pixelSize: 28 * map.u; font.family: map.ui ? map.ui.fontFamily : "" }
                TapHandler { onTapped: map.zoomBy(-1) }
                Accessible.role: Accessible.Button; Accessible.name: "Alejar"
            }
        }
    }
    // Atribución obligatoria del proveedor.
    Text {
        anchors.left: parent.left
        anchors.leftMargin: 10 * map.u
        anchors.bottom: parent.bottom
        anchors.bottomMargin: map.bottomInset + 6 * map.u
        text: map.topoLayer ? "© OpenTopoMap (CC-BY-SA) · © OpenStreetMap" : "© OpenStreetMap"
        color: S.dark ? "#C9D1E2" : "#3C4650"
        font.pixelSize: 10 * map.u
        font.family: map.ui ? map.ui.fontFamily : ""
        leftPadding: 4; rightPadding: 4
        Rectangle { z: -1; anchors.fill: parent; radius: 4; color: S.glass(0.75) }
    }
}

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Window
import QtPositioning
import InGe 1.0
import "../components" as Components
import "../flowcore" as FlowCore

// Selector de ubicación de Calicatas sobre InGe Earth (CesiumJS).
// El área `mapHost` reserva el espacio: Android coloca ahí el MISMO WebView de
// InGe Earth en modo selector (un solo motor Cesium, sin WebView duplicado).
// Tocar el mapa o pedir el GPS solo cambia el candidato; la ficha cambia
// únicamente con «Usar esta ubicación» en la hoja del editor.
Item {
    id: root

    property var auth: null
    property var flow: null
    property bool darkMode: false
    property int themeMode: 0
    property bool interactive: true
    property bool coordinatePickerMode: true
    property bool pageActive: true
    property bool followGps: false
    property real navigationInset: 0

    property bool gpsHasFix: false
    property real gpsLat: NaN
    property real gpsLon: NaN
    property real gpsAlt: NaN
    property real gpsAccuracy: NaN
    property double gpsTimestampMs: 0

    property bool selected: false
    property real selectedLat: NaN
    property real selectedLon: NaN
    property real selectedAlt: NaN
    property real selectedAccuracy: NaN
    property string selectedSource: "Punto de la ficha"
    property string selectionMessage: ""
    property bool statusCardOnly: false
    readonly property bool referenceFramed: selected

    property bool awaitingGps: false
    property bool _startedTracking: false
    readonly property int gpsMaxAgeMs: 30000
    property bool gpsOnly: false
    property string gpsError: ""
    readonly property string gpsSourceLabel: "GPS del dispositivo"
    readonly property string mapSourceLabel: "Punto fijado en mapa"
    readonly property string gpsState: awaitingGps ? "searching"
        : (selected && selectedSource === gpsSourceLabel) ? "fixed"
        : gpsError.length > 0 ? "error" : "idle"

    // Mapa Cesium (WebView nativo de InGe Earth sobre `mapHost`).
    readonly property bool mapSupported: Qt.platform.os === "android"
        && typeof GraphicsCore !== "undefined" && GraphicsCore.earthAvailable
    // Tarjeta de la ficha (no interactiva): resumen estático del punto; tocarla
    // abre el selector a pantalla completa, único lugar donde vive el mapa.
    readonly property bool previewMode: !interactive
    // Un diálogo Qt sobre el mapa (p. ej. confirmación de distancia) lo oculta
    // sin perder la cámara ni el punto.
    property bool mapSuspended: false
    property string mapState: "IDLE"      // IDLE · OPENING · LOADING_ENGINE · LOADING_VIEW · READY · ERROR_* · CLOSED
    property bool _mapOpen: false
    property bool _openedWithPoint: false
    property var _lastRect: [0, 0, 0, 0]

    signal requestGpsEnabled(bool enabled)
    signal requestGpsRefresh()

    function validPoint(lat, lon) {
        return isFinite(lat) && isFinite(lon)
                && lat >= -90 && lat <= 90
                && Math.abs(lon) <= 180
    }

    function _pushMapPoint(kind, fly) {
        if (!root._mapOpen || !root.selected) return
        GraphicsCore.setEarthPickerPoint(JSON.stringify({
            kind: kind, selected: true, fly: fly !== false,
            latitude: root.selectedLat, longitude: root.selectedLon,
            accuracy: isFinite(root.selectedAccuracy) ? root.selectedAccuracy : -1
        }))
    }

    function selectCoordinate(lat, lon, alt, accuracy, source, keepCamera) {
        if (!validPoint(lat, lon))
            return
        selectedLat = Number(lat)
        selectedLon = Number(lon)
        selectedAlt = isFinite(alt) ? Number(alt) : NaN
        selectedAccuracy = isFinite(accuracy) && Number(accuracy) > 0
                ? Number(accuracy) : NaN
        selectedSource = source && String(source).length
                ? String(source) : "Punto de la ficha"
        selected = true
        // El punto tocado ya está dibujado por Cesium; el resto se refleja allí.
        if (selectedSource !== mapSourceLabel)
            _pushMapPoint(selectedSource === gpsSourceLabel ? "gps" : "chosen", keepCamera !== true)
    }

    function centerOn(lat, lon) {
        if (validPoint(lat, lon) && !selected)
            selectCoordinate(lat, lon, NaN, NaN, "Punto de la ficha")
        else if (validPoint(lat, lon))
            _pushMapPoint(selectedSource === gpsSourceLabel ? "gps" : "chosen", true)
    }

    function gpsFixIsFresh() {
        return gpsHasFix && validPoint(gpsLat, gpsLon)
                && gpsTimestampMs > 0
                && Math.abs(Date.now() - gpsTimestampMs) <= gpsMaxAgeMs
    }

    function requestFreshFix() {
        if (typeof Perms !== "undefined" && Perms.nativePermissionGranted)
            Perms.requestImmediateLocationUpdate()
    }

    function _stopGpsSearch() {
        awaitingGps = false
        followGps = false
        gpsWait.stop()
        if (_startedTracking) {
            _startedTracking = false
            requestGpsEnabled(false)
        }
    }

    function applyGpsFix() {
        if (!awaitingGps || !gpsFixIsFresh())
            return
        _stopGpsSearch()
        gpsError = ""
        // Selección explícita: el técnico pidió el GPS; la ficha aún no cambia.
        selectCoordinate(gpsLat, gpsLon, gpsAlt, gpsAccuracy, gpsSourceLabel, false)
        selectionMessage = !isFinite(gpsAccuracy)
               ? "Posición GPS actual"
               : "Posición GPS actual ±" + Number(gpsAccuracy).toFixed(1) + " m"
    }

    function gpsDiagnostic() {
        if (typeof Perms === "undefined")
            return "La ubicación no está disponible en este dispositivo."
        if (!Perms.nativePermissionGranted)
            return "Se requiere permiso de ubicación precisa."
        if (String(Perms.nativeLocationStatus) === "service_disabled")
            return "La ubicación del dispositivo está desactivada."
        if (String(Perms.nativeLocationError || "").length > 0)
            return String(Perms.nativeLocationError)
        return "No se obtuvo una posición GPS actual. Busca cielo abierto y vuelve a intentarlo."
    }

    function centerGps() {
        awaitingGps = true
        followGps = true
        gpsError = ""
        selectionMessage = "Buscando posición GPS actual..."
        if (typeof Perms === "undefined" || !Perms.nativeTracking) {
            _startedTracking = typeof Perms !== "undefined" && !Perms.nativeTracking
            requestGpsEnabled(true)
        }
        requestFreshFix()
        gpsWait.restart()
        applyGpsFix()
    }

    // Toque en el mapa Cesium: candidato elegido a mano (sin altitud: la cota
    // del terreno se resuelve al confirmar, como en la ficha).
    function _onMapPointSelected(lat, lon) {
        if (!root._mapOpen || !validPoint(lat, lon)) return
        if (awaitingGps) _stopGpsSearch()
        gpsError = ""
        selectCoordinate(lat, lon, NaN, NaN, mapSourceLabel, true)
        selectionMessage = ""
        console.info("INGE_LOCATION_MAP_POINT selected=true")
    }

    // ---- WebView del selector: apertura, geometría y cierre ----
    function _hostRect() {
        if (!mapHost.visible || mapHost.width < 8 || mapHost.height < 8 || !root.Window.window)
            return null
        var p = mapHost.mapToGlobal(0, 0)
        var dpr = Screen.devicePixelRatio > 0 ? Screen.devicePixelRatio : 1
        return [Math.round(p.x * dpr), Math.round(p.y * dpr),
                Math.round(mapHost.width * dpr), Math.round(mapHost.height * dpr)]
    }
    function _syncMap() {
        if (!root.mapSupported) return
        var wanted = root.pageActive && root.interactive && root.visible
        if (!wanted) { root._closeMap(); return }
        var r = root._hostRect()
        if (!r) return
        if (!root._mapOpen) {
            var options = { hasPoint: root.selected, latitude: root.selected ? root.selectedLat : 0,
                            longitude: root.selected ? root.selectedLon : 0,
                            mapType: String(GraphicsCore.earthPickerMapType || "DEFAULT") }
            root._openedWithPoint = root.selected
            root._mapOpen = GraphicsCore.openEarthPicker(JSON.stringify(options), r[0], r[1], r[2], r[3])
            root.mapState = root._mapOpen ? "OPENING" : "ERROR_HOST"
            root._lastRect = r
            if (root._mapOpen) console.info("INGE_LOCATION_MAP_OPEN engine=cesium hasPoint=" + options.hasPoint)
            return
        }
        if (r[0] !== root._lastRect[0] || r[1] !== root._lastRect[1]
                || r[2] !== root._lastRect[2] || r[3] !== root._lastRect[3]) {
            root._lastRect = r
            GraphicsCore.updateEarthPickerRect(r[0], r[1], r[2], r[3])
        }
    }
    function _closeMap() {
        if (!root._mapOpen) return
        root._mapOpen = false
        GraphicsCore.closeEarthPicker()
        root.mapState = "CLOSED"
        console.info("INGE_LOCATION_MAP_CLOSED")
    }
    function retryMap() {
        root._closeMap()
        root.mapState = "IDLE"
        geometryWatch.restart()
    }

    onMapSuspendedChanged: if (root._mapOpen) GraphicsCore.setEarthPickerSuspended(root.mapSuspended)
    onPageActiveChanged: geometryWatch.restart()
    onVisibleChanged: geometryWatch.restart()

    // La geometría global no tiene notificador (animación de apertura del
    // popup): se vigila brevemente tras cada cambio, sin sondeo permanente.
    Timer {
        id: geometryWatch
        interval: 90
        repeat: true
        property int ticks: 0
        onRunningChanged: if (running) ticks = 0
        onTriggered: {
            root._syncMap()
            if (++ticks >= 10) stop()
        }
    }

    Connections {
        target: typeof GraphicsCore !== "undefined" ? GraphicsCore : null
        ignoreUnknownSignals: true
        function onEarthPickerPointSelected(latitude, longitude) { root._onMapPointSelected(latitude, longitude) }
        function onEarthPickerStateChanged(state) {
            if (!root._mapOpen && state !== "CLOSED") return
            root.mapState = String(state)
            if (root.mapState.indexOf("ERROR") === 0) {
                root._mapOpen = false
                console.warn("INGE_LOCATION_MAP_ERROR state=" + root.mapState)
            } else if (root.mapState === "READY" && root.selected) {
                root._pushMapPoint(root.selectedSource === root.gpsSourceLabel ? "gps" : "chosen", !root._openedWithPoint)
            }
        }
    }

    Timer {
        interval: 4000
        repeat: true
        running: root.awaitingGps
        onTriggered: root.requestFreshFix()
    }

    Connections {
        target: typeof Perms !== "undefined" ? Perms : null
        ignoreUnknownSignals: true
        function onNativePermissionChanged() {
            if (root.awaitingGps)
                root.requestFreshFix()
        }
        function onNativeTrackingChanged() {
            if (root.awaitingGps)
                root.requestFreshFix()
        }
    }

    Timer {
        id: gpsWait
        interval: 25000
        repeat: false
        onTriggered: {
            if (!root.awaitingGps)
                return
            root._stopGpsSearch()
            root.gpsError = root.gpsDiagnostic()
            root.selectionMessage = root.gpsError
        }
    }

    onGpsTimestampMsChanged: applyGpsFix()
    onGpsHasFixChanged: applyGpsFix()

    Rectangle {
        anchors.fill: parent
        color: root.darkMode ? "#07111C" : "#EEF3F8"
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        // Área del mapa: Android coloca aquí el WebView de InGe Earth. Debajo
        // (o si no puede abrirse) se ve el estado real de la carga o el error.
        Item {
            id: mapHost
            Layout.fillWidth: true
            Layout.fillHeight: true
            onWidthChanged: geometryWatch.restart()
            onHeightChanged: geometryWatch.restart()

            Rectangle {
                anchors.fill: parent
                color: root.darkMode ? "#0A1828" : "#E5EEF7"
            }
            // Vista previa cartográfica liviana (tarjeta de la ficha): mosaico 3×3 de
            // teselas OSM —la misma base sin claves del selector Cesium— centrado en
            // la coordenada guardada, con su marcador. Sin WebView ni segundo motor;
            // las teselas solo se piden al cambiar la coordenada (caché de Qt) y no
            // al desplazar el formulario. Tocar la tarjeta abre el selector Cesium.
            Item {
                id: previewMap
                anchors.fill: parent
                visible: root.previewMode
                clip: true
                readonly property int zoom: 16
                readonly property real tileSize: 256
                readonly property bool hasPoint: root.selected && root.validPoint(root.selectedLat, root.selectedLon)
                // Web Mercator (EPSG:3857), índices de tesela fraccionarios.
                readonly property real tileX: hasPoint ? (root.selectedLon + 180) / 360 * Math.pow(2, zoom) : 0
                readonly property real tileY: {
                    if (!hasPoint) return 0
                    var rad = root.selectedLat * Math.PI / 180
                    return (1 - Math.log(Math.tan(rad) + 1 / Math.cos(rad)) / Math.PI) / 2 * Math.pow(2, zoom)
                }
                // Mismo servidor de teselas que InGe Earth (DEFAULT_MAP_URL); si
                // no está configurado, OpenStreetMap con identificación de la app.
                readonly property string tileTemplate: {
                    var url = root.mapSupported ? String(GraphicsCore.earthBaseMapUrl() || "") : ""
                    if (!url.length) return "https://tile.openstreetmap.org/{z}/{x}/{y}.png"
                    return /\{z\}/i.test(url) ? url : url.replace(/\/+$/, "") + "/{z}/{x}/{y}.png"
                }
                readonly property bool osmTiles: tileTemplate.indexOf("tile.openstreetmap.org") >= 0
                // Satélite: miniatura capturada por Cesium al cerrar el selector,
                // válida solo para esta coordenada (si cambió, se usa el mapa).
                readonly property bool satelliteSnapshot: root.mapSupported && hasPoint
                    && String(GraphicsCore.earthPickerMapType) === "SATELLITE"
                    && String(GraphicsCore.earthPickerSnapshotUrl).length > 1024
                    && Math.abs(GraphicsCore.earthPickerSnapshotLatitude - root.selectedLat) < 1e-6
                    && Math.abs(GraphicsCore.earthPickerSnapshotLongitude - root.selectedLon) < 1e-6
                property int readyTiles: 0
                property int failedTiles: 0
                onTileXChanged: { readyTiles = 0; failedTiles = 0 }
                onTileYChanged: { readyTiles = 0; failedTiles = 0 }

                Image {
                    anchors.fill: parent
                    visible: previewMap.satelliteSnapshot
                    source: previewMap.satelliteSnapshot ? GraphicsCore.earthPickerSnapshotUrl : ""
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    cache: false
                    onStatusChanged: if (status === Image.Ready) previewMap.readyTiles = Math.max(previewMap.readyTiles, 1)
                }
                Repeater {
                    model: previewMap.hasPoint && !previewMap.satelliteSnapshot ? 9 : 0
                    delegate: Image {
                        required property int index
                        readonly property int dx: index % 3 - 1
                        readonly property int dy: Math.floor(index / 3) - 1
                        readonly property int tx: Math.floor(previewMap.tileX) + dx
                        readonly property int ty: Math.floor(previewMap.tileY) + dy
                        width: previewMap.tileSize
                        height: previewMap.tileSize
                        x: previewMap.width / 2 - (previewMap.tileX - Math.floor(previewMap.tileX)) * previewMap.tileSize + dx * previewMap.tileSize
                        y: previewMap.height / 2 - (previewMap.tileY - Math.floor(previewMap.tileY)) * previewMap.tileSize + dy * previewMap.tileSize
                        asynchronous: true
                        cache: true
                        smooth: true
                        sourceSize: Qt.size(256, 256)
                        source: previewMap.tileTemplate.replace(/\{z\}/i, previewMap.zoom)
                                    .replace(/\{x\}/i, tx).replace(/\{y\}/i, ty)
                        onStatusChanged: {
                            if (status === Image.Ready) previewMap.readyTiles += 1
                            else if (status === Image.Error) previewMap.failedTiles += 1
                        }
                    }
                }
                // Marcador de la coordenada (la captura satelital ya trae el de Cesium).
                Rectangle {
                    visible: previewMap.hasPoint && !previewMap.satelliteSnapshot
                    width: 18; height: 18; radius: 9
                    x: previewMap.width / 2 - width / 2
                    y: previewMap.height / 2 - height / 2
                    color: "#FFB84D"
                    border.width: 2
                    border.color: "#FFFFFF"
                }
                Label {
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    anchors.margins: 6
                    visible: previewMap.readyTiles > 0
                    text: previewMap.satelliteSnapshot ? "Satélite · Cesium ion"
                          : root.mapSupported && String(GraphicsCore.earthPickerMapType) === "SATELLITE"
                            ? "Mapa · captura satelital pendiente (abre el mapa)"
                          : previewMap.osmTiles ? "© OpenStreetMap" : "© Proveedor del mapa base de InGe Earth"
                    font.pixelSize: 10
                    color: "#3C4650"
                    background: Rectangle { color: "#CCFFFFFF"; radius: 4 }
                    padding: 3
                }
                // Estados reales: sin punto, cargando o sin conexión con el proveedor.
                Label {
                    anchors.centerIn: parent
                    width: Math.min(parent.width - 32, 300)
                    visible: !previewMap.hasPoint || previewMap.readyTiles === 0
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.WordWrap
                    font.pixelSize: 13
                    color: root.darkMode ? "#B9C7D6" : "#536274"
                    text: !previewMap.hasPoint ? "Sin ubicación registrada. Toca para abrir el mapa de InGe Earth."
                          : previewMap.failedTiles >= 9 ? "Vista previa no disponible sin conexión. Toca para abrir el mapa."
                          : "Cargando vista previa…"
                }
            }
            ColumnLayout {
                anchors.centerIn: parent
                width: Math.min(parent.width - 32, 320)
                spacing: 10
                // La carga la muestra el host Android (pantalla única); aquí solo
                // los casos sin mapa: plataforma no soportada o error de apertura.
                visible: !root.previewMode
                         && (!root.mapSupported || root.mapState.indexOf("ERROR") === 0)
                Label {
                    Layout.fillWidth: true
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.WordWrap
                    color: root.mapState.indexOf("ERROR") === 0
                           ? (root.darkMode ? "#FFAAA3" : "#B42318")
                           : (root.darkMode ? "#B9C7D6" : "#536274")
                    font.pixelSize: 14
                    text: !root.mapSupported ? "El mapa de InGe Earth está disponible en Android. Usa Mi ubicación o edita las coordenadas UTM en la ficha."
                          : root.mapState === "ERROR_EARTH_ACTIVE" ? "InGe Earth está abierto en otra pantalla. Ciérralo y vuelve a intentarlo."
                          : "No se pudo abrir el mapa de InGe Earth."
                }
                Button {
                    Layout.alignment: Qt.AlignHCenter
                    visible: root.mapSupported && root.mapState.indexOf("ERROR") === 0
                    text: "Reintentar"
                    onClicked: root.retryMap()
                }
            }
        }

        // Barra del selector (Qt, nunca cubierta por el mapa): GPS explícito.
        RowLayout {
            visible: !root.previewMode
            Layout.fillWidth: true
            Layout.leftMargin: 12
            Layout.rightMargin: 12
            Layout.topMargin: 8
            Layout.bottomMargin: 8
            spacing: 10
            Rectangle {
                id: gpsButton
                Layout.preferredHeight: 40
                Layout.preferredWidth: gpsRow.implicitWidth + 28
                radius: height / 2
                enabled: root.interactive && !root.awaitingGps
                opacity: enabled ? 1 : 0.6
                color: gpsTap.pressed ? (root.darkMode ? "#24425E" : "#D3E3F2")
                                      : (root.darkMode ? "#18324A" : "#FFFFFF")
                border.width: 1
                border.color: root.darkMode ? "#2C4A66" : "#C8D6E4"
                Accessible.role: Accessible.Button
                Accessible.name: "Mi ubicación"
                RowLayout {
                    id: gpsRow
                    anchors.centerIn: parent
                    spacing: 8
                    Loader {
                        Layout.preferredWidth: 20
                        Layout.preferredHeight: 20
                        active: !!root.flow
                        sourceComponent: Components.FlowIcon {
                            name: root.awaitingGps ? "status.gps" : "map.location"
                            flow: root.flow
                            tintColor: root.darkMode ? "#BFD9EE" : "#174E7A"
                            activeTintColor: tintColor
                            inactiveOpacity: 1
                        }
                    }
                    Label {
                        text: root.awaitingGps ? "Buscando GPS…" : "Mi ubicación"
                        color: root.darkMode ? "#F4F8FC" : "#172033"
                        font.pixelSize: 14
                        font.weight: Font.DemiBold
                    }
                }
                TapHandler {
                    id: gpsTap
                    enabled: gpsButton.enabled
                    onTapped: root.centerGps()
                }
            }
            Label {
                Layout.fillWidth: true
                text: root.gpsError.length > 0 ? root.gpsError
                      : root.selectionMessage.length > 0 ? root.selectionMessage
                      : "Toca el mapa para elegir el punto."
                color: root.gpsError.length > 0
                       ? (root.darkMode ? "#FFAAA3" : "#B42318")
                       : (root.darkMode ? "#9CC4E0" : "#24577D")
                font.pixelSize: 12
                wrapMode: Text.WordWrap
                maximumLineCount: 2
                elide: Text.ElideRight
            }
        }
    }

    function handleBack() { return false }

    readonly property int distanceCheckMaxAgeMs: 300000
    function distanceToRecentFix(lat, lon) {
        if (!gpsHasFix || !validPoint(gpsLat, gpsLon)
                || !validPoint(lat, lon) || gpsTimestampMs <= 0
                || Math.abs(Date.now() - gpsTimestampMs) > distanceCheckMaxAgeMs)
            return NaN
        return QtPositioning.coordinate(gpsLat, gpsLon)
            .distanceTo(QtPositioning.coordinate(lat, lon))
    }

    onInteractiveChanged: if (!root.interactive) root._closeMap()

    Component.onCompleted: {
        if (root.interactive)
            console.info("INGE_LOCATION_PICKER_OPEN engine=" + (root.mapSupported ? "cesium" : "none"))
        // El host fija el punto de la ficha con Qt.callLater: la apertura del
        // mapa espera a la geometría y a ese candidato inicial.
        geometryWatch.restart()
    }

    Component.onDestruction: {
        root._closeMap()
        if (root._startedTracking) {
            root._startedTracking = false
            root.requestGpsEnabled(false)
        }
    }
}

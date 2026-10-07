import QtQuick
import QtQuick.Controls
import QtLocation
import QtPositioning
import MapLibre.Location 4.0
import "../components" as Components
import "../flowcore" as FlowCore

// Loaded by URL only when a location view/picker is visible.
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
    property string selectedSource: "Punto fijado en mapa"
    property string selectionMessage: ""
    // El host (Ubicación) ya muestra el punto: la tarjeta queda solo para avisos.
    property bool statusCardOnly: false
    // "Buscar GPS" espera una lectura actual; una posición cacheada antigua
    // no se acepta como punto de la calicata.
    property bool awaitingGps: false
    // GPS bajo demanda (one-shot): abrir el mapa NUNCA pide ubicación. Solo
    // "Mi ubicación" (centerGps) la solicita; si este selector encendió el
    // tracking nativo lo apaga al recibir el fix.
    property bool _startedTracking: false
    readonly property int gpsMaxAgeMs: 30000
    readonly property int gpsFieldZoom: 18
    // Ficha de calicata: el GPS del dispositivo es la única fuente de la
    // posición (sin selección por toque ni segundo marcador). Al abrir se pide
    // una lectura; mientras la pantalla está abierta el pin sigue las lecturas
    // frescas del tracking nativo ya activo, sin mover la cámara.
    property bool gpsOnly: false
    property string gpsError: ""
    readonly property string gpsSourceLabel: "GPS del dispositivo"
    readonly property string gpsState: awaitingGps ? "searching"
        : (selected && selectedSource === gpsSourceLabel) ? "fixed"
        : gpsError.length > 0 ? "error" : "idle"
    signal requestGpsEnabled(bool enabled)
    signal requestGpsRefresh()

    function asset(name) { return "qrc:/ui/v2/maps/" + name }

    function validPoint(lat, lon) {
        return isFinite(lat) && isFinite(lon) && lat >= -80 && lat <= 84 && Math.abs(lon) <= 180
    }
    function selectCoordinate(lat, lon, alt, accuracy, source, keepCamera) {
        if (!validPoint(lat, lon)) return
        selectedLat = lat
        selectedLon = lon
        selectedAlt = isFinite(alt) ? alt : NaN
        selectedAccuracy = isFinite(accuracy) && accuracy > 0 ? accuracy : NaN
        selectedSource = source && String(source).length ? String(source) : "Punto fijado en mapa"
        selected = true
        if (keepCamera !== true)
            map.center = QtPositioning.coordinate(lat, lon)
    }
    // Encuadre inicial sobre la posición guardada, sin marcarla como lectura GPS.
    function centerOn(lat, lon) {
        if (!validPoint(lat, lon)) return
        map.center = QtPositioning.coordinate(lat, lon)
        map.zoomLevel = 17
    }
    function gpsFixIsFresh() {
        return gpsHasFix && validPoint(gpsLat, gpsLon) && gpsTimestampMs > 0
                && Math.abs(Date.now() - gpsTimestampMs) <= gpsMaxAgeMs
    }
    // Última posición conocida pero vieja: solo encuadra el mapa (sin pin ni
    // confirmación) mientras llega una lectura actual.
    property bool referenceFramed: false
    function frameStaleReference() {
        if (!gpsOnly || !awaitingGps || selected || referenceFramed) return
        if (!gpsHasFix || !validPoint(gpsLat, gpsLon)) return
        referenceFramed = true
        centerOn(gpsLat, gpsLon)
    }
    // Lectura inmediata real (PermissionHelper descarta duplicados pendientes).
    function requestFreshFix() {
        if (typeof Perms !== "undefined" && Perms.nativePermissionGranted)
            Perms.requestImmediateLocationUpdate()
    }
    function applyGpsFix() {
        if (!gpsFixIsFresh()) {
            frameStaleReference()
            return
        }
        // Solo una solicitud explícita ("Mi ubicación") acepta un fix; el
        // tracking que siga llegando no mueve el punto ni la cámara.
        if (!awaitingGps) return
        awaitingGps = false
        gpsWait.stop()
        gpsError = ""
        console.info("INGE_LOCATION_DEVICE_FIX accuracy=" + (isFinite(gpsAccuracy) ? Math.round(gpsAccuracy) : "n/a"))
        selectCoordinate(gpsLat, gpsLon, gpsAlt, gpsAccuracy, gpsSourceLabel, false)
        map.zoomLevel = Math.min(map.maximumZoomLevel, gpsFieldZoom)
        followGps = false
        if (_startedTracking) {
            _startedTracking = false
            requestGpsEnabled(false)
        }
        if (gpsOnly) {
            selectionMessage = ""
            return
        }
        selectionMessage = !isFinite(gpsAccuracy)
                ? "Posición GPS actual (precisión no informada)"
                : gpsAccuracy > 100
                  ? "Ubicación aproximada ±" + Math.round(gpsAccuracy) + " m. Ajusta el punto en el mapa."
                  : "Posición GPS actual ±" + gpsAccuracy.toFixed(1) + " m"
    }
    // Solo diagnósticos que PermissionHelper distingue realmente.
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
        // Solicita una lectura actual (permisos y arranque por la vía real:
        // requestGpsEnabled → requestGpsM0809; lectura inmediata si hay permiso).
        console.info("INGE_LOCATION_DEVICE_REQUEST")
        awaitingGps = true
        followGps = true
        gpsError = ""
        selectionMessage = gpsOnly ? "" : "Buscando posición GPS actual..."
        // Con el tracking ya activo no se reinicia la infraestructura: solo se
        // pide una lectura inmediata.
        if (!gpsOnly || typeof Perms === "undefined" || !Perms.nativeTracking) {
            _startedTracking = typeof Perms !== "undefined" && !Perms.nativeTracking
            requestGpsEnabled(true)
        }
        requestFreshFix()
        gpsWait.restart()
        applyGpsFix()
    }
    // El filtro de ruido nativo no republica lecturas idénticas, así que el
    // timestamp publicado puede quedarse viejo: mientras se espera se vuelve a
    // pedir una lectura inmediata.
    Timer {
        interval: 4000
        repeat: true
        running: root.gpsOnly && root.awaitingGps
        onTriggered: root.requestFreshFix()
    }
    // Permiso recién concedido / tracking recién iniciado: lectura inmediata
    // sin esperar a que el usuario vuelva a pulsar.
    Connections {
        target: typeof Perms !== "undefined" ? Perms : null
        ignoreUnknownSignals: true
        function onNativePermissionChanged() {
            if (root.gpsOnly && root.awaitingGps) root.requestFreshFix()
        }
        function onNativeTrackingChanged() {
            if (root.gpsOnly && root.awaitingGps) root.requestFreshFix()
        }
    }
    Timer {
        id: gpsWait
        interval: 25000
        repeat: false
        onTriggered: {
            if (!root.awaitingGps) return
            root.awaitingGps = false
            root.followGps = false
            if (root._startedTracking) {
                root._startedTracking = false
                root.requestGpsEnabled(false)
            }
            if (root.gpsOnly)
                root.gpsError = root.gpsDiagnostic()
            else
                root.selectionMessage = "No se obtuvo una posición GPS actual. Activa ubicación precisa o toca el punto en el mapa."
        }
    }

    function selectPreferredMapType() {
        var types = map.supportedMapTypes
        if (!types || types.length === 0)
            return

        var preferred = null
        var fallback = null
        for (var i = 0; i < types.length; ++i) {
            var candidate = types[i]
            var name = String(candidate.name || "").toLowerCase()

            // Evita el provider satelital legacy que Qt reporta deshabilitado.
            if (name.indexOf("satellite") >= 0
                    || name.indexOf("aerial") >= 0
                    || name.indexOf("hybrid") >= 0)
                continue

            if (!fallback)
                fallback = candidate

            if (name.indexOf("street") >= 0
                    || name.indexOf("standard") >= 0
                    || name.indexOf("mapnik") >= 0
                    || name.indexOf("osm") >= 0) {
                preferred = candidate
                break
            }
        }

        map.activeMapType = preferred || fallback || types[0]
    }

    onGpsTimestampMsChanged: applyGpsFix()
    onGpsHasFixChanged: applyGpsFix()
    Plugin {
        id: mapProvider
        name: "maplibre"
        PluginParameter {
            name: "maplibre.map.styles"
            value: "https://basemaps.cartocdn.com/gl/voyager-gl-style/style.json"
        }
    }
    Map {
        id: map
        anchors.fill: parent
        plugin: mapProvider
        center: QtPositioning.coordinate(0, 0)
        zoomLevel: root.selected ? 16 : 1
        copyrightsVisible: true
        onSupportedMapTypesChanged: root.selectPreferredMapType()

        // Satélite por defecto: capa raster aplicada al cargar el style,
        // encima de la base vectorial. Servicio público sin token.
        MapLibre.style: Style {
            SourceParameter {
                styleId: "inge-satellite"
                type: "raster"
                property var tiles: ["https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}"]
                property int tileSize: 256
                property int maxzoom: 19
                property string attribution: "Imagery © Esri, Maxar, Earthstar Geographics"
            }
            LayerParameter {
                styleId: "inge-satellite-layer"
                type: "raster"
                property string source: "inge-satellite"
            }
        }

        MapQuickItem {
            coordinate: QtPositioning.coordinate(root.selectedLat, root.selectedLon)
            visible: root.selected
            anchorPoint.x: 21
            anchorPoint.y: 44
            sourceItem: Item {
                width: 42
                height: 48
                scale: root.selected ? 1.0 : 0.78
                Behavior on scale {
                    NumberAnimation {
                        duration: root.flow && root.flow.motionAllowed
                                  ? root.flow.fastDuration : 0
                        easing.type: Easing.OutBack
                    }
                }
                Image {
                    anchors.fill: parent
                    source: root.asset("marker_selected_minimal.svg")
                    fillMode: Image.PreserveAspectFit
                    smooth: true
                }
            }
        }
        MapQuickItem {
            coordinate: QtPositioning.coordinate(root.gpsLat, root.gpsLon)
            visible: !root.gpsOnly && root.gpsHasFix && root.validPoint(root.gpsLat, root.gpsLon)
            anchorPoint.x: 14
            anchorPoint.y: 14
            sourceItem: Item {
                width: 28
                height: 28
                Image {
                    anchors.fill: parent
                    source: root.asset("icon_gps_current.svg")
                    fillMode: Image.PreserveAspectFit
                    smooth: true
                }
            }
        }
        DragHandler {
            id: mapDrag
            enabled: root.interactive
            target: null
            property point lastTranslation: Qt.point(0, 0)
            onActiveChanged: {
                lastTranslation = active ? translation : Qt.point(0, 0)
            }
            onTranslationChanged: {
                if (!active) return
                var dx = translation.x - lastTranslation.x
                var dy = translation.y - lastTranslation.y
                lastTranslation = translation
                map.pan(-dx, -dy)
            }
        }
        PinchHandler {
            id: mapPinch
            enabled: root.interactive
            target: null
            property var startCoordinate
            property real startZoom: 16
            onActiveChanged: {
                if (!active) return
                startCoordinate = map.toCoordinate(centroid.position, false)
                startZoom = map.zoomLevel
            }
            onScaleChanged: {
                if (!active || !startCoordinate) return
                map.zoomLevel = Math.max(map.minimumZoomLevel,
                                         Math.min(map.maximumZoomLevel,
                                                  startZoom + Math.log2(scale)))
                map.alignCoordinateToPoint(startCoordinate, centroid.position)
            }
        }
        // El candidato también puede elegirse tocando el mapa (sin GPS).
        TapHandler {
            enabled: root.interactive
            onTapped: function(eventPoint) {
                var point = map.toCoordinate(eventPoint.position, false)
                if (!root.validPoint(point.latitude, point.longitude)) return
                if (map.zoomLevel < 14) {
                    root.selectionMessage = "Acerca el mapa para elegir el punto con precisión."
                    return
                }
                // Tocar solo mueve el candidato: la distancia al GPS se consulta
                // al confirmar (host), nunca al explorar.
                root.awaitingGps = false
                gpsWait.stop()
                root.selectCoordinate(point.latitude, point.longitude, NaN, NaN, "Punto fijado en mapa")
                root.selectionMessage = ""
                root.followGps = false
            }
        }
    }
    // Superficie de los controles flotantes (sin glass: el mapa es live).
    readonly property color controlSurface: root.darkMode ? Qt.rgba(0.1098, 0.1765, 0.3137, 0.94) : Qt.rgba(1, 1, 1, 0.96)
    readonly property color controlBorder: root.darkMode ? Qt.rgba(1, 1, 1, 0.10) : Qt.rgba(0.0824, 0.102, 0.1882, 0.10)
    readonly property color controlPressed: root.darkMode ? "#102B52" : "#EBF1F8"

    // Tarjeta de estado. Con `statusCardOnly` (el host ya muestra el punto)
    // solo aparece para mensajes o errores del mapa.
    Rectangle {
        readonly property bool hasStatus: root.selectionMessage.length > 0
                                          || String(map.errorString || "").length > 0
        visible: !root.statusCardOnly || hasStatus
        x: 12; y: 12
        width: Math.min(parent.width - 24 - (root.interactive ? 60 : 0), 290)
        height: hint.implicitHeight + 24
        radius: 14
        color: "transparent"
        // Tarjeta de estado sobre el mapa: el mismo vidrio real (refracta el mapa) con el
        // velo de lectura de las hojas flotantes.
        CalicataLiquidGlass {
            anchors.fill: parent
            dark: root.darkMode
            radius: parent.radius
            level: "sheet"
            backdrop: map
        }
        Label {
            id: hint
            anchors.fill: parent
            anchors.margins: 12
            text: root.selectionMessage.length ? root.selectionMessage : String(map.errorString || "").length > 0
                ? "No se pudo cargar el mapa: " + String(map.errorString)
                : root.selected
                  ? "Punto seleccionado\n" + root.selectedLat.toFixed(6)
                    + ", " + root.selectedLon.toFixed(6)
                  : "Ubicación precisa\nToca el punto de extracción en el mapa."
            color: root.darkMode ? "white" : "#151A30"
            font.pixelSize: 14
            wrapMode: Text.WordWrap
        }
    }

    // Controles flotantes (columna derecha, como el preview), todos con acción
    // real: capas (solo si el proveedor expone más de un tipo de mapa),
    // centrar en la lectura GPS vigente y pedir una lectura GPS inmediata.
    // Material: LiquidGlassSurface real con los tokens del peek "Información
    // de la calicata"; backdrop = solo el mapa, recortado al rect de cada botón.
    QtObject {
        id: mapGlassTokens
        readonly property bool shown: root.interactive && root.visible
        readonly property Item glassBackdrop: root.interactive ? map : null
        readonly property real materialPosition: 0
        readonly property bool lowCostGlass: false
        readonly property color glassTint: root.darkMode ? Qt.rgba(0.0824, 0.102, 0.1882, 0.10) : Qt.rgba(0.95, 0.97, 1.0, 0.02)
        // Opaco: Qt premultiplica los colores de un ShaderEffect; translúcido se pintaría gris.
        readonly property color fallbackGlass: root.darkMode ? Qt.rgba(0.14, 0.16, 0.20, 1.0) : Qt.rgba(0.985, 0.99, 1.0, 1.0)
        readonly property real rimLight: root.darkMode ? 0.18 : 0.20
        readonly property real rimShade: root.darkMode ? 0.04 : 0.035
        readonly property real rimSheen: root.darkMode ? 0.03 : 0.015
        readonly property real edgeContrast: root.darkMode ? 0.0 : 0.03
        readonly property real glassSaturation: 1.12
        readonly property color shadowColor: Qt.rgba(0.0824, 0.102, 0.1882, root.darkMode ? 0.22 : 0.10)
    }

    component MapGlassButton: Item {
        id: glassButton
        property string iconName: ""
        property color iconTint: root.darkMode ? "#FFFFFF" : "#151A30"
        property bool spinning: false
        signal activated()
        width: 48
        height: 48
        opacity: enabled ? 1 : 0.45
        scale: glassTap.pressed ? 0.985 : 1
        Behavior on scale { NumberAnimation { duration: 130; easing.type: Easing.OutCubic } }
        Accessible.role: Accessible.Button

        FlowCore.LiquidGlassSurface {
            anchors.fill: parent
            tokens: mapGlassTokens
            cornerRadius: 16
            surfaceName: "calicata-map-control"
            // Captura viva justificada: el usuario desplaza/acerca el mapa bajo el control
            // (ShaderEffectSource solo re-renderiza cuando el mapa cambia).
            liveCapture: true
            lens: 0.2
            frost: 6
            frostTaps: 6
            magnify: 0
            bevel: 6
            elevation: true
        }
        // Velo de legibilidad sobre satélite (solo esta instancia).
        Rectangle {
            anchors.fill: parent
            radius: 16
            color: glassTap.pressed
                   ? (root.darkMode ? Qt.rgba(0.1098, 0.1765, 0.3137, 0.80) : Qt.rgba(0.93, 0.95, 1.0, 0.86))
                   : (root.darkMode ? Qt.rgba(0.0824, 0.102, 0.1882, 0.62) : Qt.rgba(0.98, 0.99, 1.0, 0.74))
            border.width: 1
            border.color: root.darkMode ? Qt.rgba(1, 1, 1, 0.08) : Qt.rgba(1, 1, 1, 0.55)
            Behavior on color { ColorAnimation { duration: 130 } }
        }
        Components.FlowIcon {
            id: glassIcon
            anchors.centerIn: parent
            width: 22
            height: 22
            name: glassButton.iconName
            tintColor: glassButton.iconTint
            activeTintColor: glassButton.iconTint
            inactiveOpacity: 1
            pulseOnActive: false
        }
        // Indicador discreto de búsqueda: el mismo icono respira.
        SequentialAnimation {
            running: glassButton.spinning
            loops: Animation.Infinite
            onRunningChanged: if (!running) glassIcon.opacity = 1
            NumberAnimation { target: glassIcon; property: "opacity"; to: 0.35; duration: 520; easing.type: Easing.InOutSine }
            NumberAnimation { target: glassIcon; property: "opacity"; to: 1.0; duration: 520; easing.type: Easing.InOutSine }
        }
        MouseArea {
            id: glassTap
            anchors.fill: parent
            enabled: glassButton.enabled
            onClicked: glassButton.activated()
        }
    }

    Column {
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: 12
        spacing: 12
        visible: root.interactive

        // 1 · Capas: recorre los tipos de mapa reales del proveedor.
        MapGlassButton {
            visible: !!map.supportedMapTypes && map.supportedMapTypes.length > 1
            iconName: "map.layers"
            Accessible.name: "Cambiar tipo de mapa"
            onActivated: {
                var types = map.supportedMapTypes
                var index = 0
                for (var i = 0; i < types.length; ++i)
                    if (String(types[i].name) === String(map.activeMapType.name)) index = i
                map.activeMapType = types[(index + 1) % types.length]
            }
        }
        // 2 · Centrar en la lectura GPS vigente (sin pedir otra).
        MapGlassButton {
            enabled: root.gpsOnly ? root.gpsState === "fixed" : root.selected
            iconName: "map.recenter"
            Accessible.name: "Centrar en la ubicación"
            onActivated: {
                map.center = QtPositioning.coordinate(root.selectedLat, root.selectedLon)
                map.zoomLevel = Math.max(map.zoomLevel, 17)
            }
        }
        // 3 · Actualizar GPS: lectura inmediata (idle / buscando / fijo / error).
        MapGlassButton {
            iconName: "status.gps"
            spinning: root.awaitingGps
            iconTint: root.gpsState === "fixed" ? (root.darkMode ? "#8FB2D5" : "#0654A2")
                      : root.gpsState === "error" ? (root.darkMode ? "#FF8A80" : "#C9302C")
                      : (root.darkMode ? "#FFFFFF" : "#151A30")
            Accessible.name: root.awaitingGps ? "Buscando ubicación" : "Mi ubicación"
            onActivated: root.centerGps()
        }
    }

    function handleBack() { return false }
    // Distancia (m) del candidato a una lectura REAL y reciente del dispositivo;
    // NaN si no hay con qué comparar (una coordenada técnica lejana es válida).
    readonly property int distanceCheckMaxAgeMs: 300000
    function distanceToRecentFix(lat, lon) {
        if (!gpsHasFix || !validPoint(gpsLat, gpsLon) || !validPoint(lat, lon) || gpsTimestampMs <= 0
                || Math.abs(Date.now() - gpsTimestampMs) > distanceCheckMaxAgeMs) return NaN
        return QtPositioning.coordinate(gpsLat, gpsLon).distanceTo(QtPositioning.coordinate(lat, lon))
    }
    Label {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 4
        text: "Imagery © Esri, Maxar, Earthstar Geographics"
        font.pixelSize: 9
        color: "white"
        style: Text.Outline
        styleColor: "#99000000"
    }
    Component.onCompleted: {
        Qt.callLater(root.selectPreferredMapType)
        // Abrir el mapa != obtener GPS. El host centra el punto de la ficha;
        // la ubicación del dispositivo solo se pide con "Mi ubicación".
        if (root.interactive) console.info("INGE_LOCATION_MAP_OPEN gpsOnly=" + root.gpsOnly)
    }
    Component.onDestruction: {
        // Un fix pendiente que encendió el tracking no lo deja encendido.
        if (root._startedTracking) {
            root._startedTracking = false
            root.requestGpsEnabled(false)
        }
    }
}

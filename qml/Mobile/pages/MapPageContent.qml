import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Effects
import QtPositioning
import QtLocation
import MapLibre.Location 4.0
import "../lib/GpsBus.js" as GpsBus
import "../flowcore" as FlowCore
import "../components" as Components

Page {
    id: root

    required property var auth
    property var flow: null
    property bool darkMode: false
    property int themeMode: 0
    readonly property bool liquidGlass: themeMode === 2
    readonly property bool trueDark: themeMode === 1
    property bool pageActive: false
    property bool coordinatePickerMode: false
    property real navigationInset: flow
                                      ? flow.metrics.navigationHeight
                                        + flow.spacing.xl
                                      : 92

    property bool gpsEnabled: false
    property bool gpsServiceEnabled: false
    property bool gpsHasFix: false
    property string gpsPermissionState: "undetermined"
    property string gpsStatusText: "GPS desactivado"
    property string gpsErrorText: ""
    property double gpsLat: NaN
    property double gpsLon: NaN
    property double gpsAlt: NaN
    property double gpsAccuracy: NaN
    property string gpsLastUpdate: "--:--:--"
    property string gpsProvider: ""
    property string currentCalicataCode: "Calicata actual"

    signal requestGpsEnabled(bool enabled)
    signal requestGpsRefresh()
    signal requestUsePoint(real latitude, real longitude, real altitude, string sourceLabel)
    signal requestOpenCalicatas()
    signal requestOpenLocationSettings()
    signal requestGlobalSearch(string initialText)
    signal mapInteractionChanged(bool active)

    // El punto de trabajo y la ubicación GPS son dos estados independientes.
    // La ubicación azul permanece visible y se actualiza aunque el usuario
    // mueva el mapa o fije otro punto mediante una pulsación prolongada.
    property bool selected: false
    property double selectedLat: NaN
    property double selectedLon: NaN
    property double selectedAlt: NaN
    property string selectedSource: "Punto fijado en mapa"
    property bool followGps: true
    property double lastCameraLat: NaN
    property double lastCameraLon: NaN

    // V38.18: medición de campo en vivo entre el GPS azul y el punto fijado.
    property bool measurementLineVisible: true
    property bool mapQuickActionsOpen: false
    readonly property bool measurementAvailable:
        selected && gpsHasFix
        && validLatLon(selectedLat, selectedLon)
        && validLatLon(gpsLat, gpsLon)
    readonly property var safeMeasurementPath:
        measurementAvailable
        ? [
              QtPositioning.coordinate(gpsLat, gpsLon),
              QtPositioning.coordinate(selectedLat, selectedLon)
          ]
        : [
              QtPositioning.coordinate(-11.9570376, -77.0657864),
              QtPositioning.coordinate(-11.9570375, -77.0657864)
          ]
    readonly property double measurementMeters:
        measurementAvailable
        ? geoDistanceMeters(gpsLat, gpsLon, selectedLat, selectedLon)
        : NaN
    readonly property string measurementText:
        formatDistance(measurementMeters)
    readonly property bool mapInteractionBusy:
        mapGestureBusy || mapQuickActionsOpen

    property bool mapOnline: false
    property string networkText: "Inicializando mapa..."
    property string mapErrorText: ""
    property bool panActive: false
    property bool pinchActive: false
    property bool holdActive: false
    property bool threeDPreviewEnabled: false

    readonly property bool mapGestureBusy: panActive || pinchActive || holdActive
    readonly property double displayLat: selected ? selectedLat : (gpsHasFix ? gpsLat : fieldMap.map.center.latitude)
    readonly property double displayLon: selected ? selectedLon : (gpsHasFix ? gpsLon : fieldMap.map.center.longitude)
    readonly property double displayAlt: selected ? selectedAlt : (gpsHasFix ? gpsAlt : NaN)
    readonly property string displayTitle: selected
                                                   ? "Punto fijado"
                                                   : (gpsHasFix ? "Mi ubicación" : "Centro visible del mapa")
    readonly property string displaySubtitle: selected
                                                       ? "Mantén presionado en otro lugar para reemplazarlo"
                                                       : (gpsHasFix
                                                          ? "Precisión ± " + fmt(gpsAccuracy, 1) + " m"
                                                          : "La ubicación se inicia automáticamente; también puedes fijar un punto")

    function bgColor() { return flow ? flow.theme.background : (darkMode ? "#050D18" : "#F3F5F8") }
    function cardColor() { return flow ? (liquidGlass ? flow.theme.glassSurface : flow.theme.surface) : (darkMode ? "#081827" : "#FFFFFF") }
    function card2Color() { return flow ? flow.theme.surfaceSecondary : (darkMode ? "#102235" : "#E8EDF3") }
    function textColor() { return flow ? flow.theme.textPrimary : (darkMode ? "#FFFFFF" : "#1F2937") }
    function mutedColor() { return flow ? flow.theme.textSecondary : (darkMode ? "#B9C7DA" : "#667085") }
    function borderColor() { return flow ? flow.theme.border : (darkMode ? "#2B4157" : "#D6DEE8") }
    function primaryColor() { return flow ? flow.theme.accent : "#0B5BD4" }
    function successColor() { return flow ? flow.theme.success : "#39B54A" }
    function warningColor() { return flow ? flow.theme.warning : "#FDAC11" }
    function dangerColor() { return flow ? flow.theme.error : "#DC3545" }
    function asset(name) { return "qrc:/ui/v2/maps/" + name }
    function fmt(n, d) { return isFinite(n) ? Number(n).toFixed(d) : "--" }
    function clamp(value, minimum, maximum) { return Math.max(minimum, Math.min(maximum, value)) }
    function geoDistanceMeters(lat1, lon1, lat2, lon2) {
        if (!isFinite(lat1) || !isFinite(lon1) || !isFinite(lat2) || !isFinite(lon2))
            return Infinity
        var toRad = Math.PI / 180.0
        var dLat = (lat2 - lat1) * toRad
        var dLon = (lon2 - lon1) * toRad
        var a = Math.sin(dLat / 2) * Math.sin(dLat / 2)
                + Math.cos(lat1 * toRad) * Math.cos(lat2 * toRad)
                * Math.sin(dLon / 2) * Math.sin(dLon / 2)
        return 6371000.0 * 2.0 * Math.atan2(Math.sqrt(a), Math.sqrt(1.0 - a))
    }

    function formatDistance(meters) {
        if (!isFinite(meters))
            return "--"
        if (meters < 1000)
            return (meters < 100 ? Number(meters).toFixed(1)
                                 : Math.round(meters)) + " m"
        return Number(meters / 1000.0).toFixed(meters < 10000 ? 2 : 1) + " km"
    }

    function measurementMidpointCoordinate() {
        if (!measurementAvailable)
            return QtPositioning.coordinate()
        return QtPositioning.coordinate(
                    (gpsLat + selectedLat) / 2.0,
                    (gpsLon + selectedLon) / 2.0)
    }

    function measurementZoomLevel(distanceMeters) {
        if (!isFinite(distanceMeters))
            return 16
        if (distanceMeters < 40) return 19
        if (distanceMeters < 100) return 18
        if (distanceMeters < 300) return 17
        if (distanceMeters < 800) return 16
        if (distanceMeters < 2000) return 15
        if (distanceMeters < 5000) return 14
        if (distanceMeters < 15000) return 12.8
        if (distanceMeters < 50000) return 11
        return 9.5
    }

    function fitMeasurement() {
        if (!fieldMap.map || !fieldMap.map.mapReady)
            return false
        if (!measurementAvailable) {
            if (selected && isFinite(selectedLat) && isFinite(selectedLon)) {
                followGps = false
                fieldMap.map.center = QtPositioning.coordinate(selectedLat, selectedLon)
                fieldMap.map.zoomLevel = Math.max(fieldMap.map.zoomLevel, 17)
                return true
            }
            return false
        }

        followGps = false
        fieldMap.map.center = measurementMidpointCoordinate()
        animateZoomTo(measurementZoomLevel(measurementMeters))
        console.log("[InGe+ MAP] medición encuadrada distance=", measurementMeters)
        return true
    }

    function toggleMeasurementLine() {
        measurementLineVisible = !measurementLineVisible
        console.log("[InGe+ MAP] línea de medición visible=", measurementLineVisible)
    }

    function openMapQuickActions(anchorItem, bubbleTitle, actions) {
        if (!anchorItem || !mapQuickBubble)
            return
        mapQuickBubble.openFor(anchorItem, bubbleTitle, actions)
    }

    function handleMapQuickAction(actionKey) {
        var key = String(actionKey || "")
        if (key === "zoom.near")
            animateZoomTo(19)
        else if (key === "zoom.street")
            animateZoomTo(17)
        else if (key === "zoom.sector")
            animateZoomTo(15)
        else if (key === "zoom.district")
            animateZoomTo(13)
        else if (key === "zoom.overview")
            animateZoomTo(10)
        else if (key === "gps.center")
            recenterGps()
        else if (key === "gps.follow") {
            followGps = true
            requestGpsEnabled(true)
            syncCameraToGps(true)
        } else if (key === "gps.refresh") {
            requestGpsEnabled(true)
            requestGpsRefresh()
        } else if (key === "measure.fit")
            fitMeasurement()
        else if (key === "measure.line")
            toggleMeasurementLine()
        else if (key === "measure.clear")
            clearSelectedPoint()
    }

    function permissionMessage() {
        if (gpsPermissionState === "denied")
            return "Permite la ubicación precisa para mostrar tu posición"
        if (!gpsServiceEnabled)
            return "La ubicación del dispositivo está desactivada"
        if (gpsPermissionState === "requesting")
            return "Solicitando permiso de ubicación..."
        if (gpsStatusText && gpsStatusText.length)
            return gpsStatusText
        return gpsHasFix
                ? "Ubicación en tiempo real activa"
                : "Buscando tu ubicación..."
    }

    function validLatLon(latitude, longitude) {
        return isFinite(latitude) && isFinite(longitude)
                && latitude >= -90 && latitude <= 90
                && longitude >= -180 && longitude <= 180
    }

    function validCoordinate(c) {
        return c && validLatLon(c.latitude, c.longitude)
    }

    function selectProductionMapType() {
        if (!fieldMap.map.supportedMapTypes || fieldMap.map.supportedMapTypes.length === 0)
            return

        // MapLibre expone el estilo vectorial como tipo de mapa principal.
        // No se fuerza CustomMap ni mosaicos raster OSM.
        fieldMap.map.activeMapType = fieldMap.map.supportedMapTypes[0]
    }

    function refreshMapState() {
        if (!fieldMap.map.mapReady) {
            mapOnline = false
            networkText = "Inicializando mapa..."
            return
        }

        if (fieldMap.map.error === Map.NoError) {
            mapOnline = true
            mapErrorText = ""
            networkText = "MapLibre · OpenFreeMap"
            return
        }

        mapOnline = false
        mapErrorText = fieldMap.map.errorString && fieldMap.map.errorString.length
                ? fieldMap.map.errorString
                : "No se pudo cargar el mapa vectorial"
        networkText = "Mapa sin conexión"
    }

    function updateSelectedMarkerModel(latitude, longitude) {
        if (!isFinite(latitude) || !isFinite(longitude))
            return
        if (selectedPointModel.count === 0) {
            selectedPointModel.append({ "latitude": latitude, "longitude": longitude })
        } else {
            selectedPointModel.setProperty(0, "latitude", latitude)
            selectedPointModel.setProperty(0, "longitude", longitude)
        }
    }

    function centerOnCoordinate(latitude, longitude) {
        if (validLatLon(latitude, longitude)) {
            fieldMap.map.center = QtPositioning.coordinate(latitude, longitude)
            fieldMap.map.zoomLevel = 17
        }
    }

    function setSelectedCoordinate(c, sourceLabel) {
        if (!validCoordinate(c))
            return

        selected = true
        selectedLat = c.latitude
        selectedLon = c.longitude
        selectedAlt = NaN
        selectedSource = sourceLabel || "Punto fijado en mapa"
        followGps = false
        updateSelectedMarkerModel(selectedLat, selectedLon)
    }

    function clearSelectedPoint() {
        // MapItemView destruye inmediatamente el MapQuickItem al vaciar el
        // modelo. No queda un marcador invisible ni una referencia muerta.
        selectedPointModel.clear()
        selected = false
        selectedLat = NaN
        selectedLon = NaN
        selectedAlt = NaN
        selectedSource = "Punto fijado en mapa"
        console.log("[InGe+ MAP] punto de trabajo eliminado")
    }

    function selectGpsAsPoint() {
        requestGpsEnabled(true)
        requestGpsRefresh()
        if (!gpsHasFix || !isFinite(gpsLat) || !isFinite(gpsLon)) {
            console.log("[InGe+ GPS] esperando primera coordenada para usarla como punto")
            return
        }

        selected = true
        selectedLat = gpsLat
        selectedLon = gpsLon
        selectedAlt = gpsAlt
        selectedSource = "GPS del dispositivo"
        followGps = true
        updateSelectedMarkerModel(selectedLat, selectedLon)
        syncCameraToGps(true)
    }

    function targetZoomForAccuracy() {
        var targetZoom = 17
        if (isFinite(gpsAccuracy)) {
            if (gpsAccuracy > 1500) targetZoom = 12
            else if (gpsAccuracy > 700) targetZoom = 13
            else if (gpsAccuracy > 300) targetZoom = 14
            else if (gpsAccuracy > 120) targetZoom = 15
            else if (gpsAccuracy > 50) targetZoom = 16
        }
        return targetZoom
    }

    function syncCameraToGps(force) {
        if (!fieldMap.map || !fieldMap.map.mapReady
                || !gpsHasFix || !isFinite(gpsLat) || !isFinite(gpsLon))
            return false
        if (!force && (mapInteractionBusy || !pageActive || !followGps))
            return false

        var center = fieldMap.map.center
        var distance = geoDistanceMeters(center.latitude, center.longitude, gpsLat, gpsLon)
        var cameraDeadband = Math.max(4, Math.min(18,
                                  isFinite(gpsAccuracy) ? gpsAccuracy * 0.45 : 8))
        if (!force && isFinite(distance) && distance < cameraDeadband)
            return false

        fieldMap.map.center = QtPositioning.coordinate(gpsLat, gpsLon)
        lastCameraLat = gpsLat
        lastCameraLon = gpsLon
        if (force)
            fieldMap.map.zoomLevel = targetZoomForAccuracy()
        console.log("[InGe+ MAP] cámara GPS sincronizada force=", force,
                    "distance=", distance, "deadband=", cameraDeadband)
        return true
    }

    function recenterGps() {
        // Acción explícita del usuario: asegura el watcher, solicita una lectura
        // fresca una sola vez y centra de inmediato con el último fix disponible.
        followGps = true
        requestGpsEnabled(true)
        requestGpsRefresh()
        if (!syncCameraToGps(true))
            console.log("[InGe+ GPS] botón Mi ubicación: esperando primer fix")
    }

    function sendPointToCalicata() {
        if (coordinatePickerMode) return
        if (!selected)
            return

        var fromGps = selectedSource === "GPS del dispositivo"
        var pointTime = fromGps ? gpsLastUpdate : Qt.formatTime(new Date(), "hh:mm:ss")
        var pointAccuracy = fromGps ? gpsAccuracy : NaN

        GpsBus.updateFromGeo(selectedLat, selectedLon, selectedAlt, isFinite(selectedAlt),
                             pointTime, pointAccuracy, selectedSource)
        requestUsePoint(selectedLat, selectedLon, selectedAlt, selectedSource)
    }

    function animateZoomTo(targetZoom, anchorPoint) {
        if (!fieldMap.map || !fieldMap.map.mapReady)
            return
        zoomAnimator.stop()
        zoomAnimator.from = fieldMap.map.zoomLevel
        zoomAnimator.to = clamp(targetZoom, fieldMap.minimumZoomLevel, fieldMap.maximumZoomLevel)
        zoomAnimator.start()
    }

    function syncInteractionState() {
        mapInteractionChanged(mapInteractionBusy)
    }

    onPanActiveChanged: syncInteractionState()
    onPinchActiveChanged: syncInteractionState()
    onHoldActiveChanged: syncInteractionState()
    onMapQuickActionsOpenChanged: syncInteractionState()

    onGpsHasFixChanged: {
        if (gpsHasFix && followGps)
            Qt.callLater(function() { syncCameraToGps(false) })
    }
    onGpsLatChanged: {
        if (gpsHasFix && followGps && pageActive)
            gpsCenterSyncTimer.restart()
    }
    onGpsLonChanged: {
        if (gpsHasFix && followGps && pageActive)
            gpsCenterSyncTimer.restart()
    }
    onPageActiveChanged: {
        if (pageActive) {
            // La ubicación se inicia al entrar al mapa; ya no existe interruptor.
            autoGpsStartTimer.restart()
            if (gpsHasFix && followGps)
                Qt.callLater(function() { syncCameraToGps(false) })
            Qt.callLater(refreshMapState)
        } else {
            panActive = false
            pinchActive = false
            holdActive = false
            if (mapQuickBubble)
                mapQuickBubble.close()
        }
    }

    Timer {
        id: autoGpsStartTimer
        interval: 60
        repeat: false
        onTriggered: {
            if (root.pageActive && !root.coordinatePickerMode)
                root.requestGpsEnabled(true)
        }
    }

    // Latitud y longitud cambian como dos propiedades separadas. Se agrupan
    // en una única actualización para evitar dos recentrados y dos renderizados
    // completos del mapa por cada lectura del GPS.
    Timer {
        id: gpsCenterSyncTimer
        interval: 90
        repeat: false
        onTriggered: {
            if (root.gpsHasFix && root.followGps && root.pageActive)
                root.syncCameraToGps(false)
        }
    }



    ListModel {
        id: selectedPointModel
        dynamicRoles: false
    }

    Plugin {
        id: mapLibrePlugin
        name: "maplibre"

        // Estilo vectorial abierto, nítido y sin API key.
        // OpenFreeMap usa datos OpenStreetMap y es compatible con MapLibre Native.
        PluginParameter {
            name: "maplibre.map.styles"
            value: root.trueDark
                   ? "https://tiles.openfreemap.org/styles/dark"
                   : "https://tiles.openfreemap.org/styles/liberty"
        }
    }

    background: Rectangle { color: root.bgColor() }

    Component.onCompleted: {
        if (pageActive)
            autoGpsStartTimer.restart()
        fieldMap.map.center = QtPositioning.coordinate(gpsHasFix ? gpsLat : -11.9570376,
                                                   gpsHasFix ? gpsLon : -77.0657864)
        Qt.callLater(function() {
            selectProductionMapType()
            refreshMapState()
            if (gpsHasFix)
                syncCameraToGps(false)
        })
    }

    Component.onDestruction: mapInteractionChanged(false)

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: root.liquidGlass ? 0 : root.flow.spacing.sm
        spacing: 0

        Rectangle {
            id: mapCard
            Layout.fillWidth: true
            Layout.fillHeight: true
            radius: root.liquidGlass ? 0 : root.flow.radius.lg
            color: root.cardColor()
            border.color: root.liquidGlass ? "transparent" : root.borderColor()
            clip: true

            // V38.6: núcleo táctil determinista sobre MapLibre.
            // Se usa un único Map y gestores separados por cantidad de dedos:
            // 1 dedo = paneo, 2 dedos = zoom/paneo combinado. Esto evita la
            // competencia que ocurría entre MapView, el detector externo y
            // InGeCoreFlow. El zoom usa activeScale acumulado desde el inicio
            // del gesto, por lo que no se multiplica repetidamente ni se frena.
            Item {
                id: fieldMap
                anchors.fill: parent

                property alias map: mapSurface
                readonly property real minimumZoomLevel: mapSurface.minimumZoomLevel
                readonly property real maximumZoomLevel: mapSurface.maximumZoomLevel
                property real pinchStartZoom: 16
                property geoCoordinate pinchAnchor: QtPositioning.coordinate()
                property point panLastTranslation: Qt.point(0, 0)
                function zoomAround(screenPoint, zoomDelta) {
                    if (!mapSurface.mapReady)
                        return
                    var anchor = mapSurface.toCoordinate(screenPoint, false)
                    mapSurface.zoomLevel = root.clamp(
                                mapSurface.zoomLevel + zoomDelta,
                                mapSurface.minimumZoomLevel,
                                mapSurface.maximumZoomLevel)
                    if (root.validCoordinate(anchor))
                        mapSurface.alignCoordinateToPoint(anchor, screenPoint)
                }

                Map {
                    id: mapSurface
                    anchors.fill: parent
                    plugin: mapLibrePlugin
                    zoomLevel: 16
                    copyrightsVisible: false
                    color: root.trueDark ? "#111C29" : "#E7EDF3"

                    MapCircle {
                        visible: root.gpsHasFix
                                 && isFinite(root.gpsAccuracy)
                                 && root.gpsAccuracy > 0
                                 && root.gpsAccuracy <= 5000
                        center: QtPositioning.coordinate(root.gpsLat, root.gpsLon)
                        radius: Math.max(3, Math.min(5000, root.gpsAccuracy))
                        color: root.darkMode ? "#2268A8F8" : "#1C4285F4"
                        border.width: 1
                        border.color: "#554285F4"
                    }

                    // Distancia directa de campo. La línea consume las coordenadas
                    // publicadas por el GPS; no reinicia ni duplica el watcher.
                    MapPolyline {
                        id: measurementLine
                        visible: root.measurementAvailable
                                 && root.measurementLineVisible
                        path: root.safeMeasurementPath
                        line.width: 3
                        line.color: root.darkMode ? "#8CC8FF" : "#1769AA"
                        opacity: 0.9
                        z: 14
                    }

                    MapQuickItem {
                        id: measurementLabel
                        visible: root.measurementAvailable
                                 && root.measurementLineVisible
                        coordinate: root.measurementMidpointCoordinate()
                        anchorPoint.x: measurementLabelVisual.width / 2
                        anchorPoint.y: measurementLabelVisual.height / 2
                        autoFadeIn: false
                        z: 25

                        sourceItem: Rectangle {
                            id: measurementLabelVisual
                            width: measurementLabelText.implicitWidth + 18
                            height: 30
                            radius: 15
                            color: root.darkMode ? "#F21A2B40" : "#F5FFFFFF"
                            border.color: root.darkMode ? "#6FAEDF" : "#94BFE0"
                            border.width: 1

                            Text {
                                id: measurementLabelText
                                anchors.centerIn: parent
                                text: root.measurementText
                                color: root.darkMode ? "#FFFFFF" : "#123C60"
                                font.pixelSize: 11
                                font.bold: true
                            }
                        }
                    }

                    MapQuickItem {
                        id: liveLocationMarker
                        visible: root.gpsHasFix
                                 && isFinite(root.gpsLat)
                                 && isFinite(root.gpsLon)
                        coordinate: QtPositioning.coordinate(root.gpsLat, root.gpsLon)
                        anchorPoint.x: 18
                        anchorPoint.y: 18
                        autoFadeIn: false
                        z: 20

                        sourceItem: Item {
                            width: 36
                            height: 36

                            // Halo estático: evita repintados continuos del mapa
                            // vectorial y conserva la lectura visual del GPS.
                            Rectangle {
                                anchors.centerIn: parent
                                width: 30
                                height: 30
                                radius: 15
                                color: "#244285F4"
                                border.color: "#334285F4"
                                border.width: 1
                            }

                            Rectangle {
                                anchors.centerIn: parent
                                width: 16
                                height: 16
                                radius: 8
                                color: "#4285F4"
                                border.color: "#FFFFFF"
                                border.width: 3
                            }
                        }
                    }

                    // Punto de trabajo administrado por modelo. Al ejecutar
                    // selectedPointModel.clear(), MapItemView destruye el item
                    // visual y MapLibre lo retira en el mismo ciclo de eventos.
                    MapItemView {
                        id: selectedMarkerView
                        model: selectedPointModel

                        delegate: MapQuickItem {
                            required property real latitude
                            required property real longitude
                            coordinate: QtPositioning.coordinate(latitude, longitude)
                            anchorPoint.x: 12
                            anchorPoint.y: 30
                            autoFadeIn: false
                            z: 30

                            sourceItem: Image {
                                id: selectedMarkerVisual
                                width: 24
                                height: 32
                                source: root.asset("marker_selected_minimal.svg")
                                fillMode: Image.PreserveAspectFit
                                opacity: 0.25
                                scale: 0.86

                                ParallelAnimation {
                                    running: true
                                    NumberAnimation {
                                        target: selectedMarkerVisual
                                        property: "opacity"
                                        to: 1.0
                                        duration: 90
                                    }
                                    NumberAnimation {
                                        target: selectedMarkerVisual
                                        property: "scale"
                                        to: 1.0
                                        duration: 130
                                        easing.type: Easing.OutCubic
                                    }
                                }
                            }
                        }
                    }

                    onMapReadyChanged: {
                        if (mapReady) {
                            root.selectProductionMapType()
                            Qt.callLater(function() {
                                if (root.gpsHasFix)
                                    root.syncCameraToGps(false)
                                else {
                                    mapSurface.center = QtPositioning.coordinate(-11.9570376, -77.0657864)
                                    mapSurface.zoomLevel = 16
                                }
                            })
                            console.log("[InGe+ V38.9] MapLibre listo; esperando ubicación Android", zoomLevel)
                        }
                        root.refreshMapState()
                    }
                    onSupportedMapTypesChanged: root.selectProductionMapType()
                    onErrorChanged: root.refreshMapState()
                }

                // Dos dedos siempre pueden tomar el control del gesto iniciado
                // con uno. activeScale es acumulado desde 1.0, por eso el zoom
                // parte de pinchStartZoom y no se suma sobre sí mismo.
                PinchHandler {
                    id: mapPinch
                    target: null
                    minimumPointCount: 2
                    maximumPointCount: 2
                    acceptedDevices: PointerDevice.TouchScreen | PointerDevice.TouchPad
                    grabPermissions: PointerHandler.CanTakeOverFromAnything
                                     | PointerHandler.ApprovesTakeOverByAnything

                    onActiveChanged: {
                        root.pinchActive = active
                        if (active) {
                            root.followGps = false
                            fieldMap.pinchStartZoom = mapSurface.zoomLevel
                            fieldMap.pinchAnchor = mapSurface.toCoordinate(centroid.position, false)
                        }
                    }

                    onActiveScaleChanged: {
                        if (!active || !mapSurface.mapReady
                                || !root.validCoordinate(fieldMap.pinchAnchor))
                            return

                        mapSurface.zoomLevel = root.clamp(
                                    fieldMap.pinchStartZoom
                                    + Math.log(activeScale) / Math.LN2,
                                    mapSurface.minimumZoomLevel,
                                    mapSurface.maximumZoomLevel)
                        mapSurface.alignCoordinateToPoint(fieldMap.pinchAnchor,
                                                          centroid.position)
                    }
                }

                DragHandler {
                    id: mapPan
                    target: null
                    minimumPointCount: 1
                    maximumPointCount: 1
                    acceptedDevices: PointerDevice.TouchScreen
                                     | PointerDevice.Mouse
                                     | PointerDevice.TouchPad
                    grabPermissions: PointerHandler.CanTakeOverFromAnything
                                     | PointerHandler.ApprovesTakeOverByAnything

                    onActiveChanged: {
                        root.panActive = active
                        fieldMap.panLastTranslation = translation
                        if (active)
                            root.followGps = false
                    }

                    onTranslationChanged: {
                        if (!mapSurface.mapReady || mapPinch.active) {
                            fieldMap.panLastTranslation = translation
                            return
                        }
                        var dx = translation.x - fieldMap.panLastTranslation.x
                        var dy = translation.y - fieldMap.panLastTranslation.y
                        fieldMap.panLastTranslation = translation
                        if (isFinite(dx) && isFinite(dy) && (dx !== 0 || dy !== 0))
                            mapSurface.pan(-dx, -dy)
                    }
                }

                // Pulsación larga pasiva. Si el dedo se desplaza o aparece un
                // segundo dedo, cede el control al paneo o al pellizco.
                TapHandler {
                    id: mapLongPress
                    target: null
                    acceptedButtons: Qt.LeftButton
                    acceptedDevices: PointerDevice.TouchScreen | PointerDevice.Mouse
                    gesturePolicy: TapHandler.DragThreshold
                    longPressThreshold: 0.48
                    grabPermissions: PointerHandler.ApprovesTakeOverByAnything

                    onTapped: {
                        if (root.coordinatePickerMode)
                            root.setSelectedCoordinate(mapSurface.toCoordinate(point.position, false), "Punto fijado en mapa")
                    }
                    onLongPressed: {
                        var c = mapSurface.toCoordinate(point.position, false)
                        root.setSelectedCoordinate(c, "Punto fijado en mapa")
                    }

                    onDoubleTapped: function(eventPoint, button) {
                        fieldMap.zoomAround(eventPoint.position, 1.0)
                    }
                }

                WheelHandler {
                    target: mapSurface
                    acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                    property: "zoomLevel"
                    rotationScale: 1 / 240
                    onActiveChanged: {
                        if (active) {
                            root.followGps = false
                        }
                    }
                }


            }

            Rectangle {
                id: locationNotice
                visible: root.gpsPermissionState === "denied"
                         || (root.gpsPermissionState === "granted" && !root.gpsServiceEnabled)
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: 12
                height: 58
                radius: 18
                color: root.cardColor()
                border.color: root.gpsPermissionState === "denied" ? "#F1B8B5" : "#B7D4F4"
                z: 60

                RowLayout {
                    anchors.fill: parent
                    anchors.margins: 10
                    spacing: 9

                    Rectangle {
                        Layout.preferredWidth: 34
                        Layout.preferredHeight: 34
                        radius: 12
                        color: root.gpsPermissionState === "denied" ? "#FDECEB" : "#E7F2FF"
                        Image {
                            anchors.centerIn: parent
                            width: 21
                            height: 21
                            source: root.asset("icon_gps_current.svg")
                            fillMode: Image.PreserveAspectFit
                        }
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 1
                        Text {
                            Layout.fillWidth: true
                            text: root.gpsPermissionState === "denied"
                                  ? "Permiso de ubicación requerido"
                                  : "Activa la ubicación del dispositivo"
                            color: root.textColor()
                            font.pixelSize: 12
                            font.bold: true
                            elide: Text.ElideRight
                        }
                        Text {
                            Layout.fillWidth: true
                            text: root.gpsPermissionState === "denied"
                                  ? "Permite ubicación precisa para ver el punto azul"
                                  : "Android mostrará el control para activarla ahora"
                            color: root.mutedColor()
                            font.pixelSize: 9
                            elide: Text.ElideRight
                        }
                    }

                    Button {
                        Layout.preferredWidth: 78
                        Layout.preferredHeight: 36
                        text: "Activar"
                        highlighted: true
                        onClicked: root.requestOpenLocationSettings()
                    }
                }
            }

            FlowCore.FlowGlassSurface {
                id: selectionHint
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.leftMargin: 10
                anchors.rightMargin: 10
                anchors.topMargin: locationNotice.visible ? 78 : 10
                z: 40
                height: 92
                radius: 16
                flow: root.flow
                darkMode: root.darkMode
                strength: 0.48
                blurSource: fieldMap
                blurAmount: 0.74
                blurSaturation: -0.08
                overlayTintColor: root.flow.colors.navy900
                overlayTintOpacity: root.liquidGlass ? 0.62 : 0
                color: root.liquidGlass
                       ? Qt.rgba(root.flow.colors.navy900.r,
                                 root.flow.colors.navy900.g,
                                 root.flow.colors.navy900.b, 0.54)
                       : "transparent"
                border.color: root.liquidGlass
                              ? root.flow.theme.glassBorder : "transparent"

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 8
                    spacing: 7

                    RowLayout {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 32
                        spacing: 8

                        FlowCore.FlowGlassSurface {
                            id: mapModeSelector
                            Layout.fillWidth: true
                            Layout.preferredHeight: 32
                            radius: 11
                            flow: root.flow
                            darkMode: root.darkMode
                            strength: 0.38
                            blurSource: fieldMap
                            blurAmount: 0.62
                            overlayTintColor: root.flow.colors.navy800
                            overlayTintOpacity: root.liquidGlass ? 0.46 : 0
                            color: root.liquidGlass
                                   ? Qt.rgba(root.flow.colors.navy800.r,
                                             root.flow.colors.navy800.g,
                                             root.flow.colors.navy800.b, 0.48)
                                   : root.card2Color()
                            border.color: root.borderColor()

                            RowLayout {
                                anchors.fill: parent
                                anchors.margins: 2
                                spacing: 2

                                Rectangle {
                                    Layout.fillWidth: true
                                    Layout.fillHeight: true
                                    radius: 9
                                    color: root.primaryColor()
                                    FlowCore.FlowText {
                                        anchors.centerIn: parent
                                        text: "Mapa"
                                        role: "caption"
                                        color: "#FFFFFF"
                                        font.weight: root.flow.typography.semiboldWeight
                                    }
                                }
                                Rectangle {
                                    Layout.fillWidth: true
                                    Layout.fillHeight: true
                                    radius: 9
                                    color: "transparent"
                                    opacity: fieldMap.map.supportedMapTypes
                                             && fieldMap.map.supportedMapTypes.length > 1 ? 1.0 : 0.52
                                    FlowCore.FlowText {
                                        anchors.centerIn: parent
                                        text: "Satélite"
                                        role: "caption"
                                        color: root.mutedColor()
                                    }
                                }
                            }
                        }

                        FlowCore.FlowGlassSurface {
                            id: layerButton
                            Layout.preferredWidth: 34
                            Layout.preferredHeight: 32
                            radius: 11
                            flow: root.flow
                            darkMode: root.darkMode
                            strength: 0.40
                            blurSource: fieldMap
                            blurAmount: 0.66
                            overlayTintColor: root.flow.colors.navy900
                            overlayTintOpacity: root.liquidGlass ? 0.54 : 0
                            color: layerMouse.pressed
                                   ? root.flow.theme.pressed
                                   : (root.liquidGlass
                                       ? Qt.rgba(root.flow.theme.glassSurface.r,
                                                 root.flow.theme.glassSurface.g,
                                                 root.flow.theme.glassSurface.b, 0.46)
                                      : root.cardColor())
                            border.color: root.borderColor()

                            Components.FlowIcon {
                                anchors.centerIn: parent
                                width: 20
                                height: 20
                                name: "nav.map"
                                flow: root.flow
                                pressed: layerMouse.pressed
                                tintEnabled: true
                                tintColor: root.textColor()
                                activeTintColor: root.primaryColor()
                                inactiveOpacity: 1
                            }

                            MouseArea {
                                id: layerMouse
                                anchors.fill: parent
                                onClicked: {
                                    root.flow.triggerHaptic("selection")
                                    root.openMapQuickActions(layerButton,
                                            "Capas y visualización", [
                                                { "key": "measure.line",
                                                  "label": root.measurementLineVisible ? "Ocultar medición" : "Mostrar medición",
                                                  "subtitle": "Línea entre GPS y punto fijado", "icon": "nav.map" },
                                                { "key": "gps.center", "label": "Centrar ubicación",
                                                  "subtitle": "Volver al punto GPS", "icon": "map.recenter" },
                                                { "key": "gps.refresh", "label": "Actualizar GPS",
                                                  "subtitle": "Solicitar una lectura precisa", "icon": "system.refresh" }
                                            ])
                                }
                            }
                        }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 38
                        spacing: 8

                        FlowCore.FlowGlassSurface {
                            id: mapSearchSurface
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            radius: 12
                            flow: root.flow
                            darkMode: root.darkMode
                            strength: 0.36
                            blurSource: fieldMap
                            blurAmount: 0.62
                            overlayTintColor: root.flow.colors.navy900
                            overlayTintOpacity: root.liquidGlass ? 0.60 : 0
                            color: root.liquidGlass
                                   ? Qt.rgba(root.flow.colors.navy900.r,
                                             root.flow.colors.navy900.g,
                                             root.flow.colors.navy900.b, 0.54)
                                   : root.flow.theme.field
                            border.color: mapSearch.activeFocus ? root.primaryColor() : root.borderColor()

                            Components.FlowIcon {
                                anchors.left: parent.left
                                anchors.leftMargin: 11
                                anchors.verticalCenter: parent.verticalCenter
                                width: 18
                                height: 18
                                name: "action.search"
                                flow: root.flow
                                tintEnabled: true
                                tintColor: root.mutedColor()
                                opacity: 0.82
                            }

                            TextField {
                                id: mapSearch
                                anchors.left: parent.left
                                anchors.leftMargin: 36
                                anchors.right: parent.right
                                anchors.rightMargin: 8
                                anchors.top: parent.top
                                anchors.bottom: parent.bottom
                                placeholderText: "Buscar puntos, direcciones..."
                                color: root.textColor()
                                placeholderTextColor: root.mutedColor()
                                font.family: root.flow.typography.family
                                font.pixelSize: root.flow.accessibility.scaledTextSize(
                                                    root.flow.typography.captionSize)
                                background: Item {}
                                onAccepted: root.requestGlobalSearch(text)
                            }
                        }

                        FlowCore.FlowGlassSurface {
                            id: mapFilterButton
                            Layout.preferredWidth: 38
                            Layout.fillHeight: true
                            radius: 12
                            flow: root.flow
                            darkMode: root.darkMode
                            strength: 0.40
                            blurSource: fieldMap
                            blurAmount: 0.66
                            overlayTintColor: root.flow.colors.navy900
                            overlayTintOpacity: root.liquidGlass ? 0.54 : 0
                            color: mapFilterMouse.pressed
                                   ? root.flow.theme.pressed
                                   : (root.liquidGlass
                                       ? Qt.rgba(root.flow.theme.glassSurface.r,
                                                 root.flow.theme.glassSurface.g,
                                                 root.flow.theme.glassSurface.b, 0.46)
                                      : root.cardColor())
                            border.color: root.borderColor()
                            Components.FlowIcon {
                                anchors.centerIn: parent
                                width: 19
                                height: 19
                                name: "action.menu"
                                flow: root.flow
                                pressed: mapFilterMouse.pressed
                                tintEnabled: true
                                tintColor: root.textColor()
                                activeTintColor: root.primaryColor()
                                inactiveOpacity: 1
                            }
                            MouseArea {
                                id: mapFilterMouse
                                anchors.fill: parent
                                onClicked: {
                                    root.flow.triggerHaptic("selection")
                                    root.openMapQuickActions(mapFilterButton,
                                            "Visualización del mapa", [
                                                { "key": "gps.center", "label": "Centrar ubicación", "subtitle": "Volver al punto GPS", "icon": "map.recenter" },
                                                { "key": "measure.line", "label": root.measurementLineVisible ? "Ocultar medición" : "Mostrar medición", "subtitle": "Línea entre ubicaciones", "icon": "nav.map" }
                                            ])
                                }
                            }
                        }
                    }
                }
            }

            Column {
                id: mapControls
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.topMargin: selectionHint.y + selectionHint.height + 10
                anchors.rightMargin: 12
                spacing: 10
                z: 45

                MapRoundButton {
                    id: zoomInButton
                    visible: false
                    glyph: "zoomIn"
                    accessibleName: "Acercar mapa"
                    bubbleTitle: "Acercar mapa"
                    bubbleActions: [
                        { "key": "zoom.near", "label": "Vista cercana",
                          "subtitle": "Detalle máximo de campo", "icon": "map.zoomIn" },
                        { "key": "zoom.street", "label": "Vista de calle",
                          "subtitle": "Escala de trabajo", "icon": "nav.map" },
                        { "key": "zoom.sector", "label": "Vista de sector",
                          "subtitle": "Mayor contexto", "icon": "map.zoomOut" }
                    ]
                    onClicked: root.animateZoomTo(fieldMap.map.zoomLevel + 1)
                    onDeepPressed: root.openMapQuickActions(
                                       zoomInButton,
                                       zoomInButton.bubbleTitle,
                                       zoomInButton.bubbleActions)
                }

                MapRoundButton {
                    id: zoomOutButton
                    visible: false
                    glyph: "zoomOut"
                    accessibleName: "Alejar mapa"
                    bubbleTitle: "Alejar mapa"
                    bubbleActions: [
                        { "key": "zoom.sector", "label": "Vista de sector",
                          "subtitle": "Contexto inmediato", "icon": "map.zoomOut" },
                        { "key": "zoom.district", "label": "Vista de distrito",
                          "subtitle": "Reconocimiento general", "icon": "nav.map" },
                        { "key": "zoom.overview", "label": "Vista panorámica",
                          "subtitle": "Cobertura amplia", "icon": "system.refresh" }
                    ]
                    onClicked: root.animateZoomTo(fieldMap.map.zoomLevel - 1)
                    onDeepPressed: root.openMapQuickActions(
                                       zoomOutButton,
                                       zoomOutButton.bubbleTitle,
                                       zoomOutButton.bubbleActions)
                }

                MapRoundButton {
                    id: measurementButton
                    glyph: "measure"
                    accessibleName: "Encuadrar medición"
                    active: root.selected
                    enabled: root.gpsHasFix
                    bubbleTitle: "Medición de campo"
                    bubbleActions: [
                        { "key": "measure.fit", "label": "Ver ambos puntos",
                          "subtitle": root.measurementAvailable
                                      ? root.measurementText + " de distancia directa"
                                      : "Centra el punto fijado",
                          "icon": "map.recenter" },
                        { "key": "measure.line",
                          "label": root.measurementLineVisible
                                   ? "Ocultar línea" : "Mostrar línea",
                          "subtitle": "Conservar u ocultar la unión visual",
                          "icon": "nav.map" },
                        { "key": "measure.clear", "label": "Quitar punto fijado",
                          "subtitle": "Elimina el marcador rojo", "icon": "action.delete" }
                    ]
                    onClicked: {
                        if (root.measurementAvailable)
                            root.fitMeasurement()
                        else
                            root.selectGpsAsPoint()
                    }
                    onDeepPressed: root.openMapQuickActions(
                                       measurementButton,
                                       measurementButton.bubbleTitle,
                                       measurementButton.bubbleActions)
                }

                MapRoundButton {
                    id: gpsLocationButton
                    glyph: "location"
                    accessibleName: "Mi ubicación"
                    active: root.followGps && root.gpsHasFix
                    bubbleTitle: "Mi ubicación"
                    bubbleActions: [
                        { "key": "gps.center", "label": "Centrar ahora",
                          "subtitle": "Usa la última posición válida", "icon": "map.recenter" },
                        { "key": "gps.follow", "label": "Seguir mi movimiento",
                          "subtitle": "Mantiene la cámara sobre el punto azul",
                          "icon": "status.gpsReady" },
                        { "key": "gps.refresh", "label": "Actualizar precisión",
                          "subtitle": "Solicita una lectura GPS fresca",
                          "icon": "system.refresh" }
                    ]
                    onClicked: root.recenterGps()
                    onDeepPressed: root.openMapQuickActions(
                                       gpsLocationButton,
                                       gpsLocationButton.bubbleTitle,
                                       gpsLocationButton.bubbleActions)
                }

                MapRoundButton {
                    id: threeDButton
                    labelText: "3D"
                    accessibleName: "Alternar perspectiva 3D"
                    active: root.threeDPreviewEnabled
                    onClicked: root.threeDPreviewEnabled = !root.threeDPreviewEnabled
                }
            }

            Rectangle {
                id: attributionPill
                anchors.left: parent.left
                anchors.bottom: infoPanel.top
                anchors.leftMargin: 12
                anchors.bottomMargin: 8
                z: 42
                width: attributionText.implicitWidth + 14
                height: 24
                radius: 10
                color: root.cardColor()

                Text {
                    id: attributionText
                    anchors.centerIn: parent
                    text: "<a href=\"https://openfreemap.org/\">© OpenFreeMap</a> · <a href=\"https://www.openstreetmap.org/copyright\">© OpenStreetMap</a>"
                    textFormat: Text.RichText
                    color: root.mutedColor()
                    linkColor: root.mutedColor()
                    font.pixelSize: 8
                    onLinkActivated: function(link) { Qt.openUrlExternally(link) }
                }
            }

            FlowCore.FlowGlassSurface {
                id: infoPanel
                visible: !root.coordinatePickerMode
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                anchors.leftMargin: root.flow.spacing.sm
                anchors.rightMargin: root.flow.spacing.sm
                anchors.bottomMargin: root.navigationInset
                height: root.selected ? 246 : 194
                radius: root.flow.radius.navigation
                flow: root.flow
                darkMode: root.darkMode
                strength: 0.52
                blurSource: fieldMap
                blurAmount: 0.76
                blurSaturation: -0.08
                overlayTintColor: root.flow.colors.navy900
                overlayTintOpacity: root.liquidGlass ? 0.34 : 0
                color: root.liquidGlass
                       ? Qt.rgba(root.flow.colors.navy900.r,
                                 root.flow.colors.navy900.g,
                                 root.flow.colors.navy900.b, 0.62)
                       : root.cardColor()
                border.color: root.borderColor()
                z: 50

                Rectangle {
                    anchors.top: parent.top
                    anchors.topMargin: 7
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: 34
                    height: 3
                    radius: 2
                    color: root.liquidGlass ? "#70FFFFFF" : root.borderColor()
                }

                ColumnLayout {
                    id: infoColumn
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.margins: 10
                    spacing: 4

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8

                        Components.FlowIcon {
                            Layout.preferredWidth: 14
                            Layout.preferredHeight: 14
                            Layout.alignment: Qt.AlignTop
                            name: root.gpsHasFix ? "status.gpsReady" : "status.gps"
                            flow: root.flow
                            active: root.gpsHasFix
                            tintEnabled: true
                            tintColor: root.mutedColor()
                            activeTintColor: root.primaryColor()
                            inactiveOpacity: 1
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 0

                            FlowCore.FlowText {
                                Layout.fillWidth: true
                                text: root.displayTitle
                                role: "label"
                                color: root.textColor()
                                font.weight: root.flow.typography.semiboldWeight
                                elide: Text.ElideRight
                            }
                            FlowCore.FlowText {
                                Layout.fillWidth: true
                                text: root.displaySubtitle
                                role: "caption"
                                color: root.mutedColor()
                                font.pixelSize: root.flow.accessibility.scaledTextSize(10)
                                elide: Text.ElideRight
                            }
                        }

                        Rectangle {
                            visible: false
                            Layout.preferredWidth: Math.min(statusText.implicitWidth + 14,
                                                            infoPanel.width * 0.36)
                            Layout.preferredHeight: 22
                            radius: 11
                            color: root.mapOnline ? "#EAF6EC" : "#FFF1DA"

                            Text {
                                id: statusText
                                anchors.fill: parent
                                anchors.leftMargin: 7
                                anchors.rightMargin: 7
                                text: root.networkText
                                color: root.mapOnline ? root.successColor() : root.warningColor()
                                font.pixelSize: 8
                                font.bold: true
                                horizontalAlignment: Text.AlignHCenter
                                verticalAlignment: Text.AlignVCenter
                                elide: Text.ElideRight
                            }
                        }
                    }

                    FlowCore.FlowText {
                        Layout.fillWidth: true
                        text: "N " + root.fmt(root.displayLat, 6)
                              + "°   W " + root.fmt(Math.abs(root.displayLon), 6) + "°"
                        role: "caption"
                        color: root.textColor()
                        elide: Text.ElideRight
                    }

                    RowLayout {
                        visible: false
                        Layout.fillWidth: true
                        spacing: 12

                        Item {
                            Layout.fillWidth: true
                            Layout.preferredHeight: 20

                            Text {
                                id: latitudeLabel
                                anchors.left: parent.left
                                anchors.verticalCenter: parent.verticalCenter
                                text: "LAT"
                                color: root.mutedColor()
                                font.pixelSize: 8
                                font.bold: true
                            }
                            Text {
                                anchors.left: latitudeLabel.right
                                anchors.right: parent.right
                                anchors.leftMargin: 6
                                anchors.verticalCenter: parent.verticalCenter
                                text: root.fmt(root.displayLat, 7)
                                color: root.textColor()
                                font.pixelSize: 11
                                font.bold: true
                                horizontalAlignment: Text.AlignRight
                                elide: Text.ElideRight
                            }
                        }

                        Item {
                            Layout.fillWidth: true
                            Layout.preferredHeight: 20

                            Text {
                                id: longitudeLabel
                                anchors.left: parent.left
                                anchors.verticalCenter: parent.verticalCenter
                                text: "LON"
                                color: root.mutedColor()
                                font.pixelSize: 8
                                font.bold: true
                            }
                            Text {
                                anchors.left: longitudeLabel.right
                                anchors.right: parent.right
                                anchors.leftMargin: 6
                                anchors.verticalCenter: parent.verticalCenter
                                text: root.fmt(root.displayLon, 7)
                                color: root.textColor()
                                font.pixelSize: 11
                                font.bold: true
                                horizontalAlignment: Text.AlignRight
                                elide: Text.ElideRight
                            }
                        }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 5

                        visible: false

                        Text { text: "Precisión"; color: root.mutedColor(); font.pixelSize: 9 }
                        Text {
                            text: (!root.selected || root.selectedSource === "GPS del dispositivo")
                                  && root.gpsHasFix && isFinite(root.gpsAccuracy)
                                  ? root.fmt(root.gpsAccuracy, 1) + " m"
                                  : "--"
                            color: root.textColor()
                            font.pixelSize: 10
                            font.bold: true
                        }
                        Item { Layout.fillWidth: true }
                        Text { text: "Actualización"; color: root.mutedColor(); font.pixelSize: 9 }
                        Text {
                            text: root.gpsHasFix ? root.gpsLastUpdate : "--:--:--"
                            color: root.textColor()
                            font.pixelSize: 10
                            font.bold: true
                        }
                    }

                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 22
                        radius: 9
                        color: root.card2Color()
                        border.color: root.borderColor()

                        FlowCore.FlowText {
                            anchors.fill: parent
                            anchors.leftMargin: 9
                            anchors.rightMargin: 9
                            text: "Altitud  " + (isFinite(root.displayAlt)
                                  ? root.fmt(root.displayAlt, 1) + " m"
                                  : "-- m")
                            role: "caption"
                            color: root.mutedColor()
                            font.pixelSize: root.flow.accessibility.scaledTextSize(10)
                            minimumPixelSize: 8
                            fontSizeMode: Text.Fit
                            horizontalAlignment: Text.AlignLeft
                            verticalAlignment: Text.AlignVCenter
                        }
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 3

                        FlowCore.FlowText {
                            text: "Capas activas"
                            role: "caption"
                            color: root.textColor()
                            font.pixelSize: root.flow.accessibility.scaledTextSize(10)
                            font.weight: root.flow.typography.semiboldWeight
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            Layout.preferredHeight: 22
                            spacing: 5

                            Repeater {
                                model: ["Puntos", "Sondeos", "Calicatas", "Ensayos"]
                                Rectangle {
                                    readonly property color chipAccent:
                                        index === 0 ? root.flow.theme.accent
                                        : (index === 1 ? root.flow.theme.accentSecondary
                                           : (index === 2 ? root.flow.theme.success
                                              : root.flow.colors.purple500))
                                    Layout.fillWidth: true
                                    Layout.fillHeight: true
                                    radius: 9
                                    color: Qt.rgba(chipAccent.r,
                                                   chipAccent.g,
                                                   chipAccent.b,
                                                   root.liquidGlass ? 0.24
                                                   : (root.darkMode ? 0.20 : 0.13))
                                    border.color: Qt.rgba(chipAccent.r,
                                                         chipAccent.g,
                                                         chipAccent.b,
                                                         root.liquidGlass ? 0.58 : 0.30)
                                    FlowCore.FlowText {
                                        anchors.centerIn: parent
                                        text: modelData
                                        role: "caption"
                                        color: root.darkMode
                                               ? root.flow.colors.white : chipAccent
                                        font.pixelSize: root.flow.accessibility.scaledTextSize(9)
                                        font.weight: index === 0
                                                     ? root.flow.typography.semiboldWeight
                                                     : root.flow.typography.regularWeight
                                    }
                                }
                            }
                        }
                    }

                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 44
                        visible: root.measurementAvailable
                        radius: 13
                        color: root.darkMode ? "#203A526B" : "#EDF6FD"
                        border.color: root.darkMode ? "#496B89" : "#C7DFF0"

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 11
                            anchors.rightMargin: 11
                            spacing: 10

                            Item {
                                Layout.preferredWidth: 26
                                Layout.preferredHeight: 26

                                Canvas {
                                    anchors.fill: parent
                                    onPaint: {
                                        var ctx = getContext("2d")
                                        ctx.reset()
                                        ctx.strokeStyle = root.darkMode ? "#8CC8FF" : "#1769AA"
                                        ctx.fillStyle = ctx.strokeStyle
                                        ctx.lineWidth = 2
                                        ctx.beginPath()
                                        ctx.moveTo(6, 19)
                                        ctx.lineTo(20, 7)
                                        ctx.stroke()
                                        ctx.beginPath()
                                        ctx.arc(6, 19, 3, 0, Math.PI * 2)
                                        ctx.arc(20, 7, 3, 0, Math.PI * 2)
                                        ctx.fill()
                                    }
                                }
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 0
                                Text {
                                    Layout.fillWidth: true
                                    text: "Distancia directa desde tu ubicación"
                                    color: root.textColor()
                                    font.pixelSize: 10
                                    font.bold: true
                                    elide: Text.ElideRight
                                }
                                Text {
                                    Layout.fillWidth: true
                                    text: isFinite(root.gpsAccuracy)
                                          ? "GPS ±" + root.fmt(root.gpsAccuracy, 1) + " m"
                                          : "Precisión GPS no disponible"
                                    color: root.mutedColor()
                                    font.pixelSize: 8
                                }
                            }

                            Text {
                                text: root.measurementText
                                color: root.primaryColor()
                                font.pixelSize: 15
                                font.bold: true
                            }
                        }
                    }

                    Text {
                        Layout.fillWidth: true
                        visible: false
                        text: "Ubicación actual"
                              + (root.gpsProvider.length ? " (" + root.gpsProvider + ")" : "")
                              + "  " + root.fmt(root.gpsLat, 6)
                              + ", " + root.fmt(root.gpsLon, 6)
                              + (isFinite(root.gpsAccuracy)
                                 ? "  ·  ±" + root.fmt(root.gpsAccuracy, 1) + " m"
                                 : "")
                        color: "#4285F4"
                        font.pixelSize: 9
                        font.bold: true
                        elide: Text.ElideRight
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 6

                        MapActionButton {
                            Layout.fillWidth: true
                            text: root.gpsHasFix ? "Fijar aquí mi ubicación" : "Buscar ubicación"
                            onClicked: root.selectGpsAsPoint()
                        }
                        MapActionButton {
                            Layout.fillWidth: true
                            text: root.selected ? "Quitar punto" : "Centrar GPS"
                            active: root.selected
                            onClicked: {
                                if (root.selected)
                                    root.clearSelectedPoint()
                                else
                                    root.recenterGps()
                            }
                        }
                    }

                    Button {
                        Layout.fillWidth: true
                        visible: root.gpsPermissionState === "denied"
                         || (root.gpsPermissionState === "granted" && !root.gpsServiceEnabled)
                        text: root.gpsPermissionState === "denied"
                              ? "Abrir permisos de ubicación"
                              : "Activar ubicación del dispositivo"
                        onClicked: root.requestOpenLocationSettings()
                    }

                    MapActionButton {
                        Layout.fillWidth: true
                        visible: root.selected
                        text: root.selected
                              ? "Enviar punto a " + root.currentCalicataCode
                              : "Fija un punto para continuar"
                        primary: true
                        enabled: root.selected
                        onClicked: root.sendPointToCalicata()
                    }
                }
            }
        }
    }



    FlowCore.FlowQuickBubble {
        id: mapQuickBubble
        anchors.fill: parent
        z: 1000
        flow: root.flow
        darkMode: root.darkMode

        onPresentedChanged: {
            root.mapQuickActionsOpen = presented
            root.syncInteractionState()
        }

        onActionTriggered: function(actionKey) {
            root.handleMapQuickAction(actionKey)
        }
    }

    NumberAnimation {
        id: zoomAnimator
        target: fieldMap.map
        property: "zoomLevel"
        duration: 190
        easing.type: Easing.OutCubic
    }

    component MapActionButton: FlowCore.FlowButton {
        id: actionButton

        property bool primary: false
        property bool active: false

        implicitHeight: 42
        variant: actionButton.primary
                 ? root.flow.variant.buttonPrimary
                 : (root.liquidGlass
                    ? root.flow.variant.buttonGlass
                    : root.flow.variant.buttonSecondary)
        checked: actionButton.active
        hapticIntent: "selection"
    }

    component MapRoundButton: FlowCore.FlowGlassSurface {
        id: control

        property string glyph: "location"
        property string labelText: ""
        property string accessibleName: ""
        property bool active: false
        property string bubbleTitle: ""
        property var bubbleActions: []
        signal clicked()
        signal deepPressed()

        width: 48
        height: 48
        radius: root.flow.radius.md
        flow: root.flow
        darkMode: root.darkMode
        strength: 0.44
        blurSource: fieldMap
        blurAmount: 0.70
        overlayTintColor: root.flow.colors.navy900
        overlayTintOpacity: root.liquidGlass ? 0.58 : 0
        color: !enabled
               ? root.flow.theme.disabled
               : (root.liquidGlass
                  ? Qt.rgba(root.flow.colors.navy900.r,
                            root.flow.colors.navy900.g,
                            root.flow.colors.navy900.b,
                            active ? 0.68 : 0.54)
                  : (deepPressArea.pressed
                     ? root.flow.theme.pressed
                     : (active ? root.flow.theme.selected
                               : root.flow.theme.surface)))
        opacity: enabled ? 1.0 : root.flow.opacityTokens.disabled
        scale: deepPressArea.pressed
               ? root.flow.compactPressScale
               : 1.0
        border.width: active ? 1.5 : 1
        border.color: !enabled
                       ? root.borderColor()
                       : (active
                          ? root.primaryColor()
                         : (deepPressArea.pressed
                            ? root.primaryColor()
                            : root.borderColor()))

        Accessible.role: Accessible.Button
        Accessible.name: accessibleName

        Behavior on scale {
            NumberAnimation {
                duration: root.flow && root.flow.fastDuration !== undefined
                          ? root.flow.fastDuration : 120
                easing.type: Easing.OutCubic
            }
        }

        Behavior on color {
            ColorAnimation {
                duration: root.flow && root.flow.fastDuration !== undefined
                          ? root.flow.fastDuration : 120
            }
        }

        Components.FlowIcon {
            anchors.centerIn: parent
            width: 24
            height: 24
            visible: control.labelText.length === 0
            name: control.glyph === "zoomIn"
                  ? "map.zoomIn"
                  : (control.glyph === "zoomOut"
                     ? "map.zoomOut"
                     : (control.glyph === "measure"
                        ? "home.calicata" : "status.gpsReady"))
            flow: root.flow
            active: control.active
            pressed: deepPressArea.pressed
            tintEnabled: true
            tintColor: root.textColor()
            activeTintColor: root.primaryColor()
            inactiveOpacity: 1
        }

        FlowCore.FlowText {
            anchors.centerIn: parent
            visible: control.labelText.length > 0
            text: control.labelText
            role: "label"
            color: control.active ? root.primaryColor() : root.textColor()
            font.weight: root.flow.typography.semiboldWeight
        }

        Rectangle {
            anchors.fill: parent
            anchors.margins: 2
            radius: control.radius - 2
            color: "transparent"
            border.width: deepPressArea.holdProgress > 0.01 ? 2 : 0
            border.color: root.darkMode ? "#8CC8FF" : "#70B8ED"
            opacity: deepPressArea.holdProgress
        }

        Rectangle {
            visible: control.active
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 4
            width: 6
            height: 6
            radius: 3
            color: root.primaryColor()
        }

        FlowCore.FlowDeepPressArea {
            id: deepPressArea
            anchors.fill: parent
            flow: root.flow
            contextName: "map"
            importance: 1
            deepPressEnabled: control.enabled

            onTapped: {
                root.flow.triggerHaptic("selection")
                control.clicked()
            }
            onDeepPressed: {
                root.flow.triggerHaptic("light")
                control.deepPressed()
            }
        }
    }
}

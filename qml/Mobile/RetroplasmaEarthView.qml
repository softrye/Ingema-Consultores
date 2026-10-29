pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Effects
import InGe.Retroplasma 1.0

// One native GPU viewport; forms and telemetry remain ordinary Qt Quick.
// UX 5.0: sin barras superiores/inferiores propias. Buscar, Lugares, Medir,
// Archivos, Info, Fuentes y Herramientas se abren desde "···" del Dock global
// (HomeScreen.earthDockPreset); aquí quedan los seis controles Liquid Glass.
Item {
    id: root
    required property var controller
    property real u: 1
    property string fontFamily: ""
    property string iconFamily: ""          // Lucide, la misma fuente del Dock
    property bool lowCostGlass: false       // gama baja: sin captura del globo
    property color glassTint: Qt.rgba(10 / 255, 14 / 255, 20 / 255, 0.20)   // vidrio neutro: sin tinte corporativo
    property int externalGlassTick: 0   // HomeScreen: el Dock se movió (show/hide, menú)
    property var requestedTarget: ({})      // destino pedido por Calicatas/Home
    property var selectedTarget: ({})       // último destino real: GPS, coordenadas o petición
    onRequestedTargetChanged: if (requestedTarget && requestedTarget.latitude !== undefined) selectedTarget = requestedTarget
    property string filesIntent: ""
    property string searchMessage: ""
    property real viewportHeight: height // compatibility; rendering always fills this Item
    property real safeTop: 36 * u
    property real safeBottom: 110 * u
    property bool reducedMotion: false
    property string sheet: ""
    property string exportPath: ""
    property bool filesInitialized: false
    property var permissions: Perms
    onSheetChanged: if (sheet === "files") filesInitialized = true
    function showSheet(name) { sheet = name }
    // Archivos desde el Dock: import | drive | save | export (el panel aplica la intención al cargar).
    function openFiles(intent) {
        filesIntent = intent || ""
        showSheet("files")
        if (filesLoader.documentPanel && filesIntent.length) { filesLoader.documentPanel.applyIntent(filesIntent); filesIntent = "" }
    }
    function handleBack() {
        if (sheet.length) { sheet = ""; coordinateEntryFinished(); return true }
        if (controller.measuring) { controller.cancelMeasure(); return true }
        return false
    }
    onCoordinateEntryShownChanged: if (coordinateEntryShown) showSheet("search")
    onSourceEntryShownChanged: if (sourceEntryShown) showSheet("layers")
    onDiagnosticsShownChanged: if (diagnosticsShown) showSheet("info")
    property bool diagnosticsShown: false
    property bool coordinatesShown: false
    property bool coordinateEntryShown: false
    property bool sourceEntryShown: false
    signal coordinateEntryFinished()
    property bool gpsRequested: false
    property bool gpsStartedTracking: false
    property var otherGpsClientActive: function() { return false }
    property string gpsMessage: ""
    property string gpsState: "idle"        // idle | searching | fixed | error
    function finishGps() {
        gpsTimeout.stop()
        gpsRequested = false
        if (gpsStartedTracking && !otherGpsClientActive()) root.permissions.stopNativeLocationUpdates()
        gpsStartedTracking = false
    }
    function obtainGpsFix() {
        gpsStartedTracking = gpsStartedTracking || !root.permissions.nativeTracking
        if (!root.permissions.requestImmediateLocationUpdate()) {
            gpsMessage = root.permissions.nativeLocationError || "Activa la ubicación del dispositivo."
            gpsState = "error"
            finishGps()
        } else {
            gpsMessage = "Buscando posición GPS…"
            gpsTimeout.restart()
        }
    }
    function requestGps() {
        if (gpsRequested) return
        gpsRequested = true
        gpsMessage = "Buscando posición GPS…"   // antes del estado: la confirmación nunca muestra el fix anterior
        gpsState = "searching"
        if (!root.permissions.hasLocationPermission()) {
            gpsMessage = "Autoriza ubicación precisa para centrar el planeta."
            root.permissions.requestLocationPermission()
            gpsTimeout.restart()
        } else obtainGpsFix()
    }
    function completeGpsFix() {
        if (!gpsRequested || !root.permissions.nativeHasFix || Date.now() - root.permissions.nativeTimestampMs > 30000) return
        if (controller.goTo(root.permissions.nativeLatitude, root.permissions.nativeLongitude, isFinite(root.permissions.nativeAltitude) ? root.permissions.nativeAltitude : 0)) {
            gpsMessage = "GPS · precisión " + Number(root.permissions.nativeAccuracy).toFixed(0) + " m"
            selectedTarget = { latitude: root.permissions.nativeLatitude, longitude: root.permissions.nativeLongitude,
                               altitude: isFinite(root.permissions.nativeAltitude) ? root.permissions.nativeAltitude : 0,
                               label: "mi ubicación" }
            gpsState = "fixed"
            finishGps()
        }
    }
    Timer { id: gpsTimeout; interval: 30000; onTriggered: { root.gpsMessage = "No se obtuvo una posición reciente. Reintenta GPS."; root.gpsState = "error"; root.finishGps() } }
    Connections {
        target: root.permissions
        function onNativePermissionChanged() {
            if (root.gpsRequested && root.permissions.hasLocationPermission()) root.obtainGpsFix()
        }
        function onNativeLocationChanged() {
            // Finish after the shared helper has completed starting/requesting its one source.
            if (root.gpsRequested) Qt.callLater(root.completeGpsFix)
        }
    }
    Component.onDestruction: finishGps()

    Rectangle { anchors.fill: parent; color: "#070F1E" }
    RetroplasmaView {
        id: viewport
        objectName: "earthFullViewport"
        anchors.fill: parent
        controller: root.controller
        DragHandler {
            target: null; minimumPointCount: 1; maximumPointCount: 1
            grabPermissions: PointerHandler.CanTakeOverFromAnything
            onTranslationChanged: function(delta) {
                if (!active) return
                if (root.controller.navigationMode) root.controller.pan(delta.x, delta.y)
                else root.controller.orbit(delta.x, delta.y)
            }
        }
        TapHandler {
            onTapped: function(eventPoint) {
                if (root.controller.measuring) root.controller.selectPosition(eventPoint.position.x, eventPoint.position.y)
            }
            onDoubleTapped: function(eventPoint) { root.controller.selectPosition(eventPoint.position.x, eventPoint.position.y) }
            onLongPressed: { var point = this.point.position; root.controller.selectPosition(point.x, point.y, true) }
        }
        PinchHandler {
            target: null; minimumPointCount: 2; maximumPointCount: 2
            grabPermissions: PointerHandler.CanTakeOverFromAnything
            property real lastScale: 1
            property real lastRotation: 0
            onActiveChanged: { lastScale = activeScale; lastRotation = activeRotation }
            onScaleChanged: {
                if (active && lastScale > 0 && activeScale > 0) root.controller.zoom(activeScale / lastScale)
                lastScale = activeScale
            }
            onRotationChanged: {
                if (active) root.controller.rotateView((activeRotation - lastRotation) * Math.PI / 180)
                lastRotation = activeRotation
            }
            onTranslationChanged: function(delta) { if (active) root.controller.pan(delta.x, delta.y) }
        }
        WheelHandler { target: null; onWheel: function(event) { root.controller.zoom(Math.exp(event.angleDelta.y / 600)); event.accepted = true } }
    }
    // ================================================ Cámara: estado compartido
    // Los seis controles y el Dock usan los mismos métodos del controlador
    // (command/goTo); la cámara nativa ya interpola cada objetivo.
    readonly property bool planetReady: controller.ready
    readonly property real cameraAltitude: Number(controller.cameraInfo.cameraAltitude) || 0
    readonly property real rawHeading: Number(controller.cameraInfo.heading) || 0
    readonly property real headingOffset: ((rawHeading % 360) + 540) % 360 - 180
    readonly property real minCameraAltitude: 2000         // límites de RetroplasmaCamera::zoom
    readonly property real maxCameraAltitude: 50000000
    property real zoomPrediction: 0                        // telemetría a 2 Hz: predice toques seguidos
    readonly property real effectiveAltitude: zoomPrediction > 0 ? zoomPrediction : cameraAltitude
    Timer { id: zoomPredictionReset; interval: 900; onTriggered: root.zoomPrediction = 0 }
    function formatAltitude(metres) {
        if (metres >= 100000) return Math.round(metres / 1000).toLocaleString(Qt.locale(), "f", 0) + " km"
        if (metres >= 1000) return Number(metres / 1000).toFixed(1) + " km"
        return Math.round(metres) + " m"
    }
    function zoomStep(zoomIn) {
        var next = Math.max(minCameraAltitude, Math.min(maxCameraAltitude, effectiveAltitude * (zoomIn ? 0.75 : 1.333333)))
        if (!controller.command(zoomIn ? "zoomIn" : "zoomOut"))
            return false
        zoomPrediction = next
        zoomPredictionReset.restart()
        return true
    }
    function orientNorth() {
        var wasNorth = Math.abs(headingOffset) <= 0.5
        if (!controller.command("north")) { compassAction.confirm("La brújula no está disponible todavía.", "error"); return }
        compassAction.confirm(wasNorth ? "Ya orientado al norte" : "Norte restablecido", "ok")
    }
    function centerView() {
        var t = selectedTarget, info = controller.cameraInfo
        if (t && t.latitude !== undefined) {
            var lonGap = Math.abs(((Number(info.longitude) - t.longitude) % 360 + 540) % 360 - 180)
            var centered = Math.abs(Number(info.latitude) - t.latitude) < 0.02 && lonGap < 0.02
            if (!centered) {
                if (controller.goTo(t.latitude, t.longitude, t.altitude || 0)) centerAction.confirm("Centrado en " + (t.label || "la ubicación seleccionada"), "ok")
                else centerAction.confirm("No se pudo centrar la ubicación.", "error")
                return
            }
        }
        // Sin selección, o ya centrado en ella: recupera el encuadre del planeta.
        if (controller.command("reset")) centerAction.confirm("Encuadre del planeta restablecido", "ok")
        else centerAction.confirm("El planeta aún se está cargando.", "error")
    }
    onGpsStateChanged: {
        if (gpsState === "searching") gpsAction.confirm(gpsMessage.length ? gpsMessage : "Buscando posición GPS…", "info")
        else if (gpsState === "fixed") gpsAction.confirm(gpsMessage, "ok")
        else if (gpsState === "error") gpsAction.confirm(gpsMessage, "error")
    }
    onGpsMessageChanged: if (gpsState === "searching" && gpsMessage.length) gpsAction.confirm(gpsMessage, "info")
    Timer { id: gpsFixFade; interval: 12000; running: root.gpsState === "fixed"; onTriggered: root.gpsState = "idle" }

    // ================================================ Liquid Glass compartido
    // UNA captura del globo bajo la columna (1/4 de resolución) + UN desenfoque:
    // los seis botones muestrean la misma textura. Sin blur por botón; sin
    // captura en gama baja ni con la columna oculta (se pausa por completo).
    readonly property real controlSpacing: 12 * u
    readonly property real controlTop: safeTop + 16 * u
    readonly property real controlBottom: height - safeBottom - 16 * u
    readonly property real controlSize: Math.max(40 * u, Math.min(52 * u, (controlBottom - controlTop - 5 * controlSpacing) / 6))
    property real controlsShown: sheet.length ? 0 : 1      // un panel abierto nunca queda tapado
    Behavior on controlsShown { NumberAnimation { duration: root.reducedMotion ? 0 : 240; easing.type: Easing.OutCubic } }
    readonly property bool glassLive: !lowCostGlass && visible && controlsShown > 0.001
    property int glassTick: 0
    onWidthChanged: glassTick++
    onHeightChanged: glassTick++
    Item {
        id: controlGlass
        readonly property real pad: 14 * root.u
        x: controls.x - pad
        y: controls.y - pad
        width: controls.width + 2 * pad
        height: controls.height + 2 * pad
        readonly property Item backdrop: controlGlass
        // Se conserva asignada (congelada) aunque la columna se oculte: GlassSurface
        // no admite pasar a una textura nula sin avisos.
        readonly property var glassTexture: glassChain.item ? glassChain.item.texture : null
        readonly property int glassTick: root.glassTick
        onXChanged: root.glassTick++
        onYChanged: root.glassTick++
        onWidthChanged: root.glassTick++
        onHeightChanged: root.glassTick++
        Loader {   // gama baja: no existe; columna oculta: live = false (cero trabajo por frame)
            id: glassChain
            anchors.fill: parent
            active: !root.lowCostGlass
            sourceComponent: Item {
                readonly property var texture: controlGlassTexture
                ShaderEffectSource {
                    id: controlCapture
                    width: controlGlass.width
                    height: controlGlass.height
                    sourceItem: viewport
                    sourceRect: Qt.rect(controlGlass.x, controlGlass.y, controlGlass.width, controlGlass.height)
                    live: root.glassLive
                    hideSource: false
                    visible: false
                    textureSize: Qt.size(Math.max(1, Math.round(width / 4)), Math.max(1, Math.round(height / 4)))
                }
                MultiEffect {
                    id: controlBlur
                    width: controlGlass.width
                    height: controlGlass.height
                    source: controlCapture
                    blurEnabled: true
                    blurMax: 32
                    blur: 1.0
                    autoPaddingEnabled: false
                }
                ShaderEffectSource {
                    id: controlGlassTexture
                    sourceItem: controlBlur
                    live: root.glassLive
                    hideSource: true
                    visible: false
                    smooth: true
                    textureSize: Qt.size(Math.max(1, Math.round(controlBlur.width / 4)), Math.max(1, Math.round(controlBlur.height / 4)))
                }
            }
        }
    }

    // Liquid Glass del Dock: lo resuelve el motor único de HomeScreen, que
    // captura esta vista (earthNativeLoader) en todas las gamas. Earth no
    // configura ni captura nada para el Dock.

    // ================================================ Seis controles laterales
    Column {
        id: controls
        z: 5
        spacing: root.controlSpacing
        x: root.width - width - 18 * root.u + (1 - root.controlsShown) * (width + 36 * root.u)
        y: root.controlTop
        opacity: root.controlsShown
        visible: opacity > 0.01
        enabled: root.controlsShown > 0.99
        EarthGlassAction {   // 1. Brújula: rumbo real; toque = norte animado
            id: compassAction
            glassHost: controlGlass; u: root.u; iconFamily: root.iconFamily; fontFamily: root.fontFamily
            width: root.controlSize; height: width; reducedMotion: root.reducedMotion; tint: root.glassTint
            label: "Brújula: orientar al norte"
            hint: "Rumbo " + Math.round(((root.rawHeading % 360) + 360) % 360) + "°"
            available: root.planetReady
            active: Math.abs(root.headingOffset) > 0.5
            face: Component {
                Item {
                    rotation: -root.rawHeading
                    Behavior on rotation { NumberAnimation { duration: root.reducedMotion ? 0 : 480; easing.type: Easing.OutCubic } }
                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        y: 2 * root.u
                        text: "N"
                        font.family: root.fontFamily
                        font.pixelSize: 9.5 * root.u
                        font.bold: true
                        color: "#FF9A8F"
                        style: Text.Raised
                        styleColor: Qt.rgba(4 / 255, 10 / 255, 24 / 255, 0.6)
                    }
                    Text {
                        anchors.centerIn: parent
                        anchors.verticalCenterOffset: 2 * root.u
                        text: String.fromCharCode(0xE124)      // lucide navigation-2 (aguja)
                        font.family: root.iconFamily
                        font.pixelSize: 19 * root.u
                        color: "white"
                        style: Text.Raised
                        styleColor: Qt.rgba(4 / 255, 10 / 255, 24 / 255, 0.55)
                    }
                }
            }
            onActivated: root.orientNorth()
            onRejected: compassAction.confirm("El planeta aún se está cargando.", "error")
        }
        EarthGlassAction {   // 2. GPS compartido: permisos, búsqueda, fix o fallo reales
            id: gpsAction
            glassHost: controlGlass; u: root.u; iconFamily: root.iconFamily; fontFamily: root.fontFamily
            width: root.controlSize; height: width; reducedMotion: root.reducedMotion; tint: root.glassTint
            label: "Mi ubicación GPS"
            hint: root.gpsMessage
            glyph: root.gpsState === "fixed" ? 0xE1DB : 0xE1DA   // lucide locate-fixed / locate
            available: root.planetReady
            active: root.gpsState === "fixed"
            busy: root.gpsRequested
            accent: root.gpsState === "error" ? "#FF8A8A" : "#8FD8FF"
            onActivated: {
                if (root.gpsRequested) gpsAction.confirm(root.gpsMessage.length ? root.gpsMessage : "Buscando posición GPS…", "info")
                else root.requestGps()
            }
            onRejected: gpsAction.confirm("El planeta aún se está cargando.", "error")
        }
        EarthGlassAction {   // 3. Capas: panel real de fuentes NASA / EOX / Landsat
            id: layersAction
            glassHost: controlGlass; u: root.u; iconFamily: root.iconFamily; fontFamily: root.fontFamily
            width: root.controlSize; height: width; reducedMotion: root.reducedMotion; tint: root.glassTint
            label: "Capas y fuentes"
            hint: "NASA Blue Marble, Sentinel EOX, Landsat HLS y capas KML"
            glyph: 0xE529                                          // lucide layers
            active: root.sheet === "layers"
            onActivated: root.showSheet("layers")
        }
        EarthGlassAction {   // 4. Acercar (mismo comando que el Dock)
            id: zoomInAction
            glassHost: controlGlass; u: root.u; iconFamily: root.iconFamily; fontFamily: root.fontFamily
            width: root.controlSize; height: width; reducedMotion: root.reducedMotion; tint: root.glassTint
            label: "Acercar"
            hint: "Altitud de cámara " + root.formatAltitude(root.effectiveAltitude)
            glyph: 0xE13D                                          // lucide plus
            available: root.planetReady && root.effectiveAltitude > root.minCameraAltitude * 1.01
            onActivated: {
                if (root.zoomStep(true)) zoomInAction.confirm("Acercando · " + root.formatAltitude(root.zoomPrediction), "info")
                else zoomInAction.confirm("No se pudo acercar la cámara.", "error")
            }
            onRejected: zoomInAction.confirm(root.planetReady ? "Acercamiento máximo: " + root.formatAltitude(root.minCameraAltitude) : "El planeta aún se está cargando.", "error")
        }
        EarthGlassAction {   // 5. Alejar (mismo comando que el Dock)
            id: zoomOutAction
            glassHost: controlGlass; u: root.u; iconFamily: root.iconFamily; fontFamily: root.fontFamily
            width: root.controlSize; height: width; reducedMotion: root.reducedMotion; tint: root.glassTint
            label: "Alejar"
            hint: "Altitud de cámara " + root.formatAltitude(root.effectiveAltitude)
            glyph: 0xE11C                                          // lucide minus
            available: root.planetReady && root.effectiveAltitude < root.maxCameraAltitude / 1.01
            onActivated: {
                if (root.zoomStep(false)) zoomOutAction.confirm("Alejando · " + root.formatAltitude(root.zoomPrediction), "info")
                else zoomOutAction.confirm("No se pudo alejar la cámara.", "error")
            }
            onRejected: zoomOutAction.confirm(root.planetReady ? "Alejamiento máximo: " + root.formatAltitude(root.maxCameraAltitude) : "El planeta aún se está cargando.", "error")
        }
        EarthGlassAction {   // 6. Centrar: selección (GPS/coordenadas/calicata) o encuadre del planeta
            id: centerAction
            glassHost: controlGlass; u: root.u; iconFamily: root.iconFamily; fontFamily: root.fontFamily
            width: root.controlSize; height: width; reducedMotion: root.reducedMotion; tint: root.glassTint
            label: "Centrar vista"
            hint: root.selectedTarget && root.selectedTarget.latitude !== undefined
                  ? "Centra " + (root.selectedTarget.label || "la ubicación seleccionada") + "; otro toque recupera el planeta completo"
                  : "Recupera el encuadre del planeta completo"
            glyph: 0xE29E                                          // lucide focus
            available: root.planetReady
            onActivated: root.centerView()
            onRejected: centerAction.confirm("El planeta aún se está cargando.", "error")
        }
    }

    Text { font.family: root.fontFamily;
        anchors.centerIn: parent; width: parent.width - 100 * root.u
        visible: !root.controller.ready
        text: root.controller.busy ? "Cargando la Tierra..." : root.controller.status
        color: "white"; wrapMode: Text.WordWrap; horizontalAlignment: Text.AlignHCenter
    }

    // ================================================ Telemetría mínima (abajo-izquierda)
    property bool attributionExpanded: false
    Column {
        id: telemetry
        x: 18 * root.u
        y: root.height - root.safeBottom - 10 * root.u - height
        width: Math.max(120 * root.u, root.width - 36 * root.u - controls.width - 16 * root.u)
        spacing: 6 * root.u
        opacity: root.controlsShown
        visible: opacity > 0.01
        Text { font.family: root.fontFamily
            width: parent.width
            visible: text.length > 0
            text: root.controller.measuring ? "Toca dos puntos sobre la Tierra"
                  : (root.gpsState === "searching" || root.gpsState === "error" ? root.gpsMessage : "")
            color: "#FFFFFF"; style: Text.Outline; styleColor: "#070F1E"; font.pixelSize: 12 * root.u; wrapMode: Text.WordWrap
        }
        Item {
            width: 100 * root.u; height: 16 * root.u
            property real metres: { var position = root.controller.cameraInfo; return root.controller.scaleMetres(width) }
            visible: metres > 0
            Text { font.family: root.fontFamily; anchors.left: parent.left; anchors.bottom: scaleBar.top; anchors.bottomMargin: 3 * root.u; text: parent.metres >= 1000 ? Number(parent.metres / 1000).toFixed(1) + " km" : Number(parent.metres).toFixed(0) + " m"; color: "white"; style: Text.Outline; styleColor: "#070F1E"; font.pixelSize: 10 * root.u }
            Rectangle { id: scaleBar; anchors.bottom: parent.bottom; width: parent.width; height: 2 * root.u; color: "white" }
        }
        Text { font.family: root.fontFamily
            width: parent.width
            visible: root.coordinatesShown
            text: {
                var p = root.controller.cameraInfo
                return Number(p.latitude).toFixed(4) + ", " + Number(p.longitude).toFixed(4)
                    + " | " + Number(p.cameraAltitude / 1000).toFixed(1) + " km"
            }
            color: "white"; style: Text.Outline; styleColor: "#070F1E"; font.pixelSize: 11 * root.u
        }
        // Atribución obligatoria NASA / EOX (CC BY 4.0): siempre visible y compacta;
        // un toque la amplía con la licencia y otro abre Capas y fuentes.
        Rectangle {
            id: attribution
            width: Math.min(telemetry.width, attributionText.width + 22 * root.u)
            height: attributionText.height + 10 * root.u
            radius: Math.min(height / 2, 12 * root.u)
            color: Qt.rgba(7 / 255, 15 / 255, 30 / 255, 0.50)
            border.width: 1
            border.color: Qt.rgba(1, 1, 1, 0.16)
            Text {
                id: attributionText
                x: 11 * root.u
                anchors.verticalCenter: parent.verticalCenter
                width: Math.min(implicitWidth, telemetry.width - 22 * root.u)
                text: root.attributionExpanded
                      ? "NASA / USGS · EOxCloudless https://cloudless.eox.at by EOX IT Services GmbH (Contains modified Copernicus Sentinel data 2016). CC BY 4.0. Toca de nuevo para ver Capas y fuentes."
                      : "ⓘ NASA / USGS · EOxCloudless by EOX IT Services GmbH (Contains modified Copernicus Sentinel data 2016)"
                color: Qt.rgba(1, 1, 1, 0.86)
                font.family: root.fontFamily
                font.pixelSize: 9 * root.u
                wrapMode: Text.WordWrap
                maximumLineCount: root.attributionExpanded ? 6 : 2
                elide: Text.ElideRight
            }
            Accessible.role: Accessible.Button
            Accessible.name: "Atribución: NASA / USGS. EOxCloudless https://cloudless.eox.at by EOX IT Services GmbH (Contains modified Copernicus Sentinel data 2016). CC BY 4.0"
            Accessible.onPressAction: root.toggleAttribution()
            MouseArea {
                anchors.fill: parent
                anchors.margins: -6 * root.u
                onClicked: root.toggleAttribution()
            }
            Timer { id: attributionCollapse; interval: 8000; onTriggered: root.attributionExpanded = false }
        }
    }
    function goToCoordinates(latitude, longitude, altitude) {
        if (!controller.goTo(latitude, longitude, altitude)) {   // el controlador valida rangos
            searchMessage = "Coordenadas no válidas: latitud ±90°, longitud ±180°, altitud ≤ 100 km."
            return false
        }
        searchMessage = ""
        selectedTarget = { latitude: latitude, longitude: longitude, altitude: altitude,
                           label: Number(latitude).toFixed(4) + ", " + Number(longitude).toFixed(4) }
        return true
    }
    function searchResults(query, layers) {
        var q = String(query || "").trim()
        if (!q.length) return []
        var result = []
        var pair = q.replace(/;/g, ",").match(/^(-?\d+(?:[.,]\d+)?)\s*[, ]\s*(-?\d+(?:[.,]\d+)?)$/)
        if (pair) {
            var la = Number(pair[1].replace(",", ".")), lo = Number(pair[2].replace(",", "."))
            if (Math.abs(la) <= 90 && Math.abs(lo) <= 180)
                result.push({ title: "Ir a " + la + ", " + lo, latitude: la, longitude: lo })
        }
        var needle = q.toLocaleLowerCase()
        for (var i = 0; i < layers.length && result.length < 12; ++i)
            for (var k = 0; k < layers[i].features.length && result.length < 12; ++k) {
                var f = layers[i].features[k]
                if (String(f.name).toLocaleLowerCase().indexOf(needle) >= 0 || String(layers[i].name).toLocaleLowerCase().indexOf(needle) >= 0)
                    result.push({ title: f.name + " · " + layers[i].name, layerId: layers[i].id, index: f.index })
            }
        return result
    }
    function toggleAttribution() {
        if (attributionExpanded) { attributionExpanded = false; showSheet("layers") }
        else { attributionExpanded = true; attributionCollapse.restart() }
    }
    Rectangle {
        id: sheetPanel
        z: 10; width: parent.width; height: Math.min(parent.height - root.safeTop - 80 * root.u, 490 * root.u)
        y: root.sheet.length ? parent.height - root.safeBottom - height : parent.height
        radius: 24 * root.u; color: "#F5F8FC"; visible: y < root.height
        Behavior on y { NumberAnimation { duration: root.reducedMotion ? 0 : 220; easing.type: Easing.OutCubic } }
        // Own all gestures inside the panel; they never orbit the globe behind it.
        MouseArea { anchors.fill: parent; onClicked: {} }
        Rectangle { anchors.horizontalCenter: parent.horizontalCenter; y: 8 * root.u; width: 38 * root.u; height: 4 * root.u; radius: 2 * root.u; color: "#C4CFDA" }
        Button { font.family: root.fontFamily; anchors.right: parent.right; anchors.rightMargin: 14 * root.u; y: 12 * root.u; text: "Cerrar"; onClicked: root.handleBack() }
        Text { font.family: root.fontFamily; x: 20 * root.u; y: 24 * root.u; text: ({search:"Buscar lugares y coordenadas",layers:"Capas y fuentes",places:"Lugares guardados",measure:"Medir distancia",files:"Archivos KML / KMZ",info:"Información geográfica"})[root.sheet] || ""; width: parent.width - 130 * root.u; elide: Text.ElideRight; color: "#163451"; font.pixelSize: 18 * root.u; font.bold: true }
        Flickable {
            anchors.fill: parent; anchors.topMargin: 66 * root.u; anchors.margins: 18 * root.u
            anchors.bottomMargin: 18 * root.u
            clip: true; contentHeight: content.implicitHeight; boundsBehavior: Flickable.StopAtBounds
            Column {
                id: content; width: parent.width; spacing: 10 * root.u
                Column {
                    width: parent.width; spacing: 8 * root.u; visible: root.sheet === "search"
                    // Lugares guardados y geometrías KML/KMZ cargadas, o "lat, lon" en una línea.
                    TextField { id: placeQuery; width: parent.width; placeholderText: "Lugar guardado, capa o \"lat, lon\"" }
                    Repeater {
                        model: root.searchResults(placeQuery.text, root.controller.geoLayers)
                        delegate: Button { font.family: root.fontFamily
                            required property var modelData
                            width: content.width; text: modelData.title
                            onClicked: {
                                if (modelData.latitude !== undefined) {
                                    if (!root.goToCoordinates(modelData.latitude, modelData.longitude, 0)) return
                                } else root.controller.centerGeoLayer(modelData.layerId, modelData.index)
                                root.sheet = ""; root.coordinateEntryFinished()
                            }
                        }
                    }
                    Text { font.family: root.fontFamily; width: parent.width; color: "#344A62"; wrapMode: Text.WordWrap
                        visible: placeQuery.text.trim().length > 0 && root.searchResults(placeQuery.text, root.controller.geoLayers).length === 0
                        text: "Sin coincidencias en los lugares guardados ni en las capas KML/KMZ abiertas. Escribe coordenadas o importa un archivo."
                    }
                    TextField { id: lat; width: parent.width; placeholderText: "Latitud (-12.0464)"; inputMethodHints: Qt.ImhFormattedNumbersOnly }
                    TextField { id: lon; width: parent.width; placeholderText: "Longitud (-77.0428)"; inputMethodHints: Qt.ImhFormattedNumbersOnly }
                    TextField { id: alt; width: parent.width; placeholderText: "Altitud en metros (opcional)"; inputMethodHints: Qt.ImhFormattedNumbersOnly }
                    Button { font.family: root.fontFamily; text: "Ir a coordenadas"; enabled: lat.text.trim().length > 0 && lon.text.trim().length > 0
                        onClicked: {
                            if(root.goToCoordinates(Number(lat.text.replace(",",".")),Number(lon.text.replace(",",".")),alt.text.trim().length ? Number(alt.text.replace(",",".")) : 0)) { root.sheet=""; root.coordinateEntryFinished() }
                        }
                    }
                    Text { font.family: root.fontFamily; width: parent.width; visible: root.searchMessage.length > 0; text: root.searchMessage; color: "#A52D35"; wrapMode: Text.WordWrap }
                    Row { spacing: 6 * root.u
                        Button { font.family: root.fontFamily; text: "Peru"; onClicked: {root.controller.command("peru");root.sheet=""} }
                        Button { font.family: root.fontFamily; text: "Lima"; onClicked: {root.controller.command("lima");root.sheet=""} }
                        Button { font.family: root.fontFamily; text: "GPS"; onClicked: {root.requestGps();root.sheet=""} }
                    }
                }
                Column {
                    width: parent.width; spacing: 8 * root.u; visible: root.sheet === "layers"
                    Button { font.family: root.fontFamily; width: parent.width; text: "NASA + Sentinel 2016 | 10 m"; onClicked: root.controller.setPlanetImagery("sentinel") }
                    Button { font.family: root.fontFamily; width: parent.width; text: "NASA Blue Marble | 500 m"; onClicked: root.controller.setPlanetImagery("blue-marble") }
                    TextField { id: imageryDate; width: parent.width; placeholderText: "Fecha Landsat AAAA-MM-DD; vacio = reciente" }
                    Button { font.family: root.fontFamily; width: parent.width; text: "NASA / USGS Landsat HLS | 30 m"; onClicked: root.controller.setPlanetImagery("landsat",imageryDate.text.trim()) }
                    Text { font.family: root.fontFamily; width: parent.width; text: root.controller.sourceName; color: "#344A62"; font.pixelSize: 12 * root.u; wrapMode: Text.WordWrap }
                    Text { font.family: root.fontFamily; width: parent.width; text: "EOxCloudless https://cloudless.eox.at by EOX IT Services GmbH (Contains modified Copernicus Sentinel data 2016). CC BY 4.0. Archivo historico, sin edificios 3D. Servicio gratuito sin garantia de disponibilidad."; color: "#344A62"; font.pixelSize: 12 * root.u; wrapMode: Text.WordWrap }
                    Button { font.family: root.fontFamily; text: "Licencia y fuente EOX"; onClicked: Qt.openUrlExternally("https://maps.eox.at/") }
                    Button { font.family: root.fontFamily; text: "Reintentar descarga"; onClicked: root.controller.retryScene() }
                }
                Column {
                    width: parent.width; spacing: 8 * root.u; visible: root.sheet === "places"
                    TextField { id: placeName; width: parent.width; placeholderText: "Nombre del lugar en el centro de la vista" }
                    Button { font.family: root.fontFamily; text: "Guardar marcador"; onClicked: root.controller.addPlace(placeName.text) }
                    Text { font.family: root.fontFamily; width: parent.width; text: "Mantener pulsada la Tierra agrega un marcador. Doble toque acerca a la posicion."; color: "#344A62"; wrapMode: Text.WordWrap }
                    Repeater {
                        model: root.controller.geoLayers
                        delegate: Column {
                            id: layerDelegate
                            required property var modelData
                            width: content.width; spacing: 4 * root.u
                            Row { spacing: 4 * root.u
                                CheckBox { text: modelData.name; checked: modelData.visible; onToggled: root.controller.setLayerVisible(modelData.id,checked); width: content.width - 90 * root.u }
                                Button { font.family: root.fontFamily; text: "Quitar"; onClicked: root.controller.removeGeoLayer(modelData.id) }
                            }
                            Repeater {
                                model: modelData.features
                                delegate: Button { font.family: root.fontFamily;
                                    required property var modelData
                                    property string layerId: layerDelegate.modelData.id
                                    width: content.width; text: modelData.name + " / " + modelData.kind
                                    onClicked: {root.controller.centerGeoLayer(layerId,modelData.index);root.sheet=""}
                                }
                            }
                            Text { font.family: root.fontFamily; width: parent.width; visible: modelData.warnings.length > 0; text: modelData.warnings; color: "#785313"; wrapMode: Text.WordWrap }
                        }
                    }
                }
                Column {
                    width: parent.width; spacing: 10 * root.u; visible: root.sheet === "measure"
                    Text { font.family: root.fontFamily; width: parent.width; text: "Distancia geodesica WGS84 entre dos puntos. No mide desnivel ni rutas."; color: "#344A62"; wrapMode: Text.WordWrap }
                    Text { font.family: root.fontFamily; text: Number(root.controller.measurementKm).toFixed(3) + " km"; color: "#163451"; font.pixelSize: 26 * root.u }
                    Button { font.family: root.fontFamily; text: "Elegir dos puntos"; onClicked: {root.controller.beginMeasure();root.sheet=""} }
                    Button { font.family: root.fontFamily; text: "Borrar medicion"; onClicked: root.controller.cancelMeasure() }
                }
                Loader {
                    id: filesLoader
                    property var documentPanel: item
                    width: parent.width; height: visible && documentPanel ? documentPanel.implicitHeight : 0
                    visible: root.sheet === "files"
                    active: root.filesInitialized; source: "EarthDocumentSheet.qml"
                    onLoaded: {
                        documentPanel.controller = root.controller; documentPanel.width = width
                        if (root.filesIntent.length) { documentPanel.applyIntent(root.filesIntent); root.filesIntent = "" }
                    }
                }
                Column {
                    width: parent.width; spacing: 8 * root.u; visible: root.sheet === "info"
                    Text { font.family: root.fontFamily; width: parent.width; text: root.controller.coordinates; color: "#344A62"; wrapMode: Text.WordWrap }
                    Text { font.family: root.fontFamily; width: parent.width; text: "Resolucion mas fina cargada: " + Number(root.controller.cameraInfo.resolutionMetres).toFixed(0) + " m/pixel. La base NASA permanece en zonas sin detalle."; color: "#344A62"; wrapMode: Text.WordWrap }
                    Text { font.family: root.fontFamily; width: parent.width; text: root.controller.status; color: "#344A62"; wrapMode: Text.WordWrap }
                    Text { font.family: root.fontFamily; width: parent.width; text: JSON.stringify(root.controller.metrics,null,2); color: "#344A62"; font.pixelSize: 11 * root.u; wrapMode: Text.WrapAnywhere }
                }
                Text { font.family: root.fontFamily; width: parent.width; visible: root.controller.documentMessage.length > 0 && root.sheet !== "files"; text: root.controller.documentMessage; color: "#344A62"; wrapMode: Text.WordWrap }
            }
        }
    }
}

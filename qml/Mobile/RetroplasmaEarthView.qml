import QtQuick
import QtQuick.Controls
import InGe.Retroplasma 1.0

// One native GPU viewport; forms and telemetry remain ordinary Qt Quick.
Column {
    id: root
    required property var controller
    property real u: 1
    property string fontFamily: ""
    property real viewportHeight: 360
    property bool diagnosticsShown: false
    property bool coordinatesShown: false
    property bool coordinateEntryShown: false
    property bool sourceEntryShown: false
    signal coordinateEntryFinished()
    property bool gpsRequested: false
    property bool gpsStartedTracking: false
    property var otherGpsClientActive: function() { return false }
    property string gpsMessage: ""
    function finishGps() {
        gpsTimeout.stop()
        gpsRequested = false
        if (gpsStartedTracking && !otherGpsClientActive()) Perms.stopNativeLocationUpdates()
        gpsStartedTracking = false
    }
    function obtainGpsFix() {
        gpsStartedTracking = gpsStartedTracking || !Perms.nativeTracking
        if (!Perms.requestImmediateLocationUpdate()) {
            gpsMessage = Perms.nativeLocationError || "Activa la ubicación del dispositivo."
            finishGps()
        } else {
            gpsMessage = "Buscando posición GPS…"
            gpsTimeout.restart()
        }
    }
    function requestGps() {
        if (gpsRequested) return
        gpsRequested = true
        if (!Perms.hasLocationPermission()) {
            gpsMessage = "Autoriza ubicación precisa para centrar el planeta."
            Perms.requestLocationPermission()
            gpsTimeout.restart()
        } else obtainGpsFix()
    }
    function completeGpsFix() {
        if (!gpsRequested || !Perms.nativeHasFix || Date.now() - Perms.nativeTimestampMs > 30000) return
        if (controller.goTo(Perms.nativeLatitude, Perms.nativeLongitude, isFinite(Perms.nativeAltitude) ? Perms.nativeAltitude : 0)) {
            gpsMessage = "GPS · precisión " + Number(Perms.nativeAccuracy).toFixed(0) + " m"
            finishGps()
        }
    }
    Timer { id: gpsTimeout; interval: 30000; onTriggered: { root.gpsMessage = "No se obtuvo una posición reciente. Reintenta GPS."; root.finishGps() } }
    Connections {
        target: Perms
        function onNativePermissionChanged() {
            if (root.gpsRequested && Perms.hasLocationPermission()) root.obtainGpsFix()
        }
        function onNativeLocationChanged() {
            // Finish after the shared helper has completed starting/requesting its one source.
            if (root.gpsRequested) Qt.callLater(root.completeGpsFix)
        }
    }
    Component.onDestruction: finishGps()
    spacing: 10 * u
    Text {
        width: parent.width
        text: root.controller.sourceName
        color: "#B4C2D3"
        font.family: root.fontFamily
        font.pixelSize: 13 * root.u
        wrapMode: Text.WordWrap
    }
    Rectangle {
        width: parent.width
        height: root.viewportHeight
        color: "#0C1722"
        clip: true
        RetroplasmaView {
            id: viewport
            anchors.fill: parent
            controller: root.controller
            DragHandler {
                target: null
                minimumPointCount: 1
                maximumPointCount: 1
                grabPermissions: PointerHandler.CanTakeOverFromAnything
                onTranslationChanged: function(delta) {
                    if (!active) return
                    if (root.controller.navigationMode)
                        root.controller.pan(delta.x, delta.y)
                    else
                        root.controller.orbit(delta.x, delta.y)
                }
            }
            PinchHandler {
                id: pinch
                target: null
                minimumPointCount: 2
                maximumPointCount: 2
                grabPermissions: PointerHandler.CanTakeOverFromAnything
                property real lastScale: 1
                property real lastRotation: 0
                onActiveChanged: {
                    lastScale = activeScale
                    lastRotation = activeRotation
                }
                onScaleChanged: {
                    if (active && lastScale > 0 && activeScale > 0)
                        root.controller.zoom(activeScale / lastScale)
                    lastScale = activeScale
                }
                onRotationChanged: {
                    if (active)
                        root.controller.rotateView((activeRotation - lastRotation) * Math.PI / 180)
                    lastRotation = activeRotation
                }
                onTranslationChanged: function(delta) {
                    if (active) root.controller.pan(delta.x, delta.y)
                }
            }
            WheelHandler {
                target: null
                onWheel: function(event) {
                    root.controller.zoom(Math.exp(event.angleDelta.y / 600))
                    event.accepted = true
                }
            }
        }
        Text {
            anchors.centerIn: parent
            width: parent.width - 28 * root.u
            visible: !root.controller.ready || root.controller.metrics.meshes === 0
            text: root.controller.busy ? "Cargando escena 3D…" : root.controller.status
            color: "#B4C2D3"
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
            font.family: root.fontFamily
            font.pixelSize: 14 * root.u
        }
    }
    Text {
        width: parent.width
        text: root.controller.status + (root.controller.navigationMode
              ? " · Un dedo desplaza" : " · Un dedo orienta") + " · Dos dedos: zoom, desplazamiento y giro"
        color: "#B4C2D3"
        font.family: root.fontFamily
        font.pixelSize: 12 * root.u
        wrapMode: Text.WordWrap
    }
    Text {
        width: parent.width
        visible: root.gpsMessage.length > 0
        text: root.gpsMessage
        color: "#B4C2D3"; wrapMode: Text.WordWrap; font.family: root.fontFamily
    }
    Flow {
        width: parent.width
        spacing: 4 * root.u
        Button { text: "Planeta completo"; onClicked: root.controller.command("reset") }
        Button { text: "Sudamérica"; onClicked: root.controller.command("southAmerica") }
        Button { text: "Perú"; onClicked: root.controller.command("peru") }
        Button { text: "Lima"; onClicked: root.controller.command("lima") }
        Button { text: "GPS"; onClicked: root.requestGps() }
    }
    Text {
        width: parent.width
        visible: root.coordinatesShown
        text: root.controller.coordinates
        color: "white"
        font.family: root.fontFamily
        font.pixelSize: 13 * root.u
        wrapMode: Text.WordWrap
    }
    Text {
        width: parent.width
        visible: root.diagnosticsShown || root.controller.metrics.renderError.length > 0
        text: {
            var m = root.controller.metrics
            return "FPS presentación Qt: " + Number(m.fps).toFixed(1)
                 + " · intervalo " + Number(m.frameMs).toFixed(1) + " ms"
                 + "\nRegistro CPU: " + Number(m.cpuRecordMs).toFixed(2) + " ms · " + m.backend
                 + "\nMallas " + m.meshes + " · triángulos enviados " + m.triangles + " · texturas " + m.textures
                 + "\nCaché CPU " + Number(m.cpuMiB).toFixed(1) + " MiB · recursos GPU aprox. " + Number(m.gpuMiB).toFixed(1) + " MiB"
                 + "\nNodos pendientes " + m.pending + " · errores de datos " + m.decodeErrors
                 + (m.renderError ? "\n" + m.renderError : "")
        }
        color: "#B4C2D3"
        font.family: root.fontFamily
        font.pixelSize: 12 * root.u
        wrapMode: Text.WordWrap
    }
    Button {
        text: "Reintentar escena"
        visible: root.controller.metrics.renderError.length > 0 || root.controller.metrics.decodeErrors > 0
                 || (!root.controller.ready && !root.controller.busy && root.controller.status.indexOf("RP_") === 0)
        onClicked: root.controller.retryScene()
    }
    Column {
        width: parent.width
        spacing: 6 * root.u
        visible: root.coordinateEntryShown
        Text { text: "Ir a coordenadas WGS84"; color: "white"; font.family: root.fontFamily }
        TextField { id: latitude; width: parent.width; placeholderText: "Latitud (grados)"; inputMethodHints: Qt.ImhFormattedNumbersOnly }
        TextField { id: longitude; width: parent.width; placeholderText: "Longitud (grados)"; inputMethodHints: Qt.ImhFormattedNumbersOnly }
        TextField { id: altitude; width: parent.width; placeholderText: "Altitud (metros); vacío = 0"; inputMethodHints: Qt.ImhFormattedNumbersOnly }
        Button {
            text: "Ir"
            enabled: latitude.text.trim().length > 0 && longitude.text.trim().length > 0
            onClicked: {
                if (root.controller.goTo(Number(latitude.text.replace(",", ".")), Number(longitude.text.replace(",", ".")), altitude.text.trim().length ? Number(altitude.text.replace(",", ".")) : 0))
                    root.coordinateEntryFinished()
            }
        }
    }
    Column {
        width: parent.width
        spacing: 6 * root.u
        visible: root.sourceEntryShown
        Text {
            width: parent.width
            text: "Paquete de escena local autorizado: scene.json, mallas y texturas en la misma carpeta."
            color: "#B4C2D3"; wrapMode: Text.WordWrap; font.family: root.fontFamily
        }
        TextField { id: sourcePath; width: parent.width; placeholderText: "Ruta local del archivo scene.json" }
        Button {
            text: "Cargar escena"
            enabled: sourcePath.text.trim().length > 0
            onClicked: {
                root.controller.loadLocalScene(sourcePath.text.trim())
            }
        }
        Button { text: "Volver al planeta NASA"; onClicked: root.controller.openPlanet() }
        Text { width: parent.width; text: "Mosaicos regionales: conexión a Internet. HLS Landsat: 30 m, cobertura parcial, nubes y fecha de adquisición; no ofrece detalle de edificios."; color: "#B4C2D3"; wrapMode: Text.WordWrap; font.family: root.fontFamily }
        Button { text: "NASA Blue Marble mundial / GIBS 500 m"; onClicked: root.controller.setPlanetImagery("blue-marble") }
        TextField { id: imageryDate; width: parent.width; placeholderText: "Fecha Landsat AAAA-MM-DD; vacío: reciente por región" }
        Button { text: "NASA/USGS Landsat HLS · 30 m"; onClicked: root.controller.setPlanetImagery("landsat", imageryDate.text.trim()) }
    }
}

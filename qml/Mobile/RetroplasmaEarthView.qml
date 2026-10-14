pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import InGe.Retroplasma 1.0

// One native GPU viewport; forms and telemetry remain ordinary Qt Quick.
Item {
    id: root
    required property var controller
    property real u: 1
    property string fontFamily: ""
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
            finishGps()
        } else {
            gpsMessage = "Buscando posición GPS…"
            gpsTimeout.restart()
        }
    }
    function requestGps() {
        if (gpsRequested) return
        gpsRequested = true
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
            finishGps()
        }
    }
    Timer { id: gpsTimeout; interval: 30000; onTriggered: { root.gpsMessage = "No se obtuvo una posición reciente. Reintenta GPS."; root.finishGps() } }
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

    component FloatButton: Rectangle {
        id: action
        property string label: ""
        property string glyph: label
        signal activated()
        width: 48 * root.u; height: 48 * root.u; radius: 24 * root.u
        color: tap.pressed ? "#E0E9F6" : "#F5F8FC"
        Accessible.role: Accessible.Button
        Accessible.name: label
        Accessible.onPressAction: activated()
        Text { font.family: root.fontFamily; anchors.centerIn: parent; text: action.glyph; color: "#163451"; font.pixelSize: 17 * root.u; font.bold: true }
        TapHandler { id: tap; onTapped: action.activated() }
    }
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
    Rectangle {
        id: searchPill
        x: 16 * root.u; y: root.safeTop + 12 * root.u
        width: parent.width - 32 * root.u; height: 52 * root.u; radius: 26 * root.u; color: "#F5F8FC"
        Accessible.role: Accessible.Button; Accessible.name: "Buscar coordenadas o lugares"
        Accessible.onPressAction: root.showSheet("search")
        Text { font.family: root.fontFamily; anchors.left: parent.left; anchors.leftMargin: 20 * root.u; anchors.verticalCenter: parent.verticalCenter; text: "InGe Earth  |  Buscar lugar"; color: "#344A62"; font.pixelSize: 15 * root.u }
        TapHandler { onTapped: root.showSheet("search") }
    }
    Column {
        anchors.right: parent.right; anchors.rightMargin: 16 * root.u
        y: searchPill.y + searchPill.height + 18 * root.u; spacing: 10 * root.u
        FloatButton { label: "Orientar al norte"; glyph: "N"; onActivated: root.controller.command("north")
            Text { font.family: root.fontFamily; anchors.horizontalCenter: parent.horizontalCenter; anchors.bottom: parent.bottom; anchors.bottomMargin: 3 * root.u; text: Math.round(root.controller.cameraInfo.heading) + "\u00b0"; color: "#344A62"; font.pixelSize: 8 * root.u }
        }
        FloatButton { label: "Mi ubicacion"; glyph: "GPS"; onActivated: root.requestGps() }
        FloatButton { label: "Capas"; glyph: "☷"; onActivated: root.showSheet("layers") }
        FloatButton { label: "Acercar"; glyph: "+"; onActivated: root.controller.command("zoomIn") }
        FloatButton { label: "Alejar"; glyph: "-"; onActivated: root.controller.command("zoomOut") }
        FloatButton { label: "Planeta completo"; glyph: "◎"; onActivated: root.controller.command("reset") }
    }
    Text { font.family: root.fontFamily;
        anchors.centerIn: parent; width: parent.width - 100 * root.u
        visible: !root.controller.ready
        text: root.controller.busy ? "Cargando la Tierra..." : root.controller.status
        color: "white"; wrapMode: Text.WordWrap; horizontalAlignment: Text.AlignHCenter
    }
    Rectangle {
        id: toolbar
        x: 16 * root.u; width: parent.width - 32 * root.u; height: 54 * root.u; radius: 27 * root.u
        y: parent.height - root.safeBottom - height - 28 * root.u; color: "#F5F8FC"
        Row { anchors.fill: parent; anchors.margins: 4 * root.u
            Repeater {
                model: [{title:"Lugares",key:"places"},{title:"Medir",key:"measure"},{title:"Archivos",key:"files"},{title:"Info",key:"info"}]
                delegate: Item {
                    required property var modelData
                    width: (toolbar.width - 8 * root.u) / 4; height: toolbar.height - 8 * root.u
                    Accessible.role: Accessible.Button; Accessible.name: modelData.title
                    Accessible.onPressAction: root.showSheet(modelData.key)
                    Text { font.family: root.fontFamily; anchors.centerIn: parent; text: modelData.title; color: "#163451"; font.pixelSize: 13 * root.u; font.bold: true }
                    TapHandler { onTapped: root.showSheet(modelData.key) }
                }
            }
        }
    }
    Text { font.family: root.fontFamily;
        x: 18 * root.u; y: toolbar.y - implicitHeight - 12 * root.u; width: parent.width - 100 * root.u
        text: root.controller.measuring ? "Toca dos puntos sobre la Tierra" : root.gpsMessage
        color: "#FFFFFF"; style: Text.Outline; styleColor: "#070F1E"; font.pixelSize: 12 * root.u; wrapMode: Text.WordWrap
    }
    Text { font.family: root.fontFamily;
        x: 18 * root.u; y: toolbar.y - 56 * root.u; width: parent.width - 90 * root.u
        visible: root.coordinatesShown
        text: {
            var p = root.controller.cameraInfo
            return Number(p.latitude).toFixed(4) + ", " + Number(p.longitude).toFixed(4)
                + " | " + Number(p.cameraAltitude / 1000).toFixed(1) + " km"
        }
        color: "white"; style: Text.Outline; styleColor: "#070F1E"; font.pixelSize: 11 * root.u
    }
    Rectangle {
        x: 18 * root.u; y: toolbar.y - 70 * root.u; width: 100 * root.u; height: 2 * root.u; color: "white"
        property real metres: { var position = root.controller.cameraInfo; return root.controller.scaleMetres(width) }
        visible: metres > 0
        Text { font.family: root.fontFamily; anchors.left: parent.left; anchors.bottom: parent.top; anchors.bottomMargin: 3 * root.u; text: parent.metres >= 1000 ? Number(parent.metres / 1000).toFixed(1) + " km" : Number(parent.metres).toFixed(0) + " m"; color: "white"; style: Text.Outline; styleColor: "#070F1E"; font.pixelSize: 10 * root.u }
    }
    Text { font.family: root.fontFamily;
        id: attribution
        x: 18 * root.u; y: toolbar.y + toolbar.height + 5 * root.u; width: parent.width - 36 * root.u
        text: "NASA / USGS | EOxCloudless https://cloudless.eox.at\nby EOX IT Services GmbH (Contains modified Copernicus Sentinel data 2016)"
        color: "#FFFFFF"; style: Text.Outline; styleColor: "#070F1E"; font.pixelSize: 9 * root.u; wrapMode: Text.WordWrap
        TapHandler { onTapped: root.showSheet("layers") }
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
        Text { font.family: root.fontFamily; x: 20 * root.u; y: 24 * root.u; text: ({search:"Buscar",layers:"Capas y fuentes",places:"Lugares",measure:"Medir distancia",files:"Documentos",info:"Informacion"})[root.sheet] || ""; color: "#163451"; font.pixelSize: 18 * root.u; font.bold: true }
        Flickable {
            anchors.fill: parent; anchors.topMargin: 66 * root.u; anchors.margins: 18 * root.u
            anchors.bottomMargin: 18 * root.u
            clip: true; contentHeight: content.implicitHeight; boundsBehavior: Flickable.StopAtBounds
            Column {
                id: content; width: parent.width; spacing: 10 * root.u
                Column {
                    width: parent.width; spacing: 8 * root.u; visible: root.sheet === "search"
                    TextField { id: lat; width: parent.width; placeholderText: "Latitud (-12.0464)"; inputMethodHints: Qt.ImhFormattedNumbersOnly }
                    TextField { id: lon; width: parent.width; placeholderText: "Longitud (-77.0428)"; inputMethodHints: Qt.ImhFormattedNumbersOnly }
                    TextField { id: alt; width: parent.width; placeholderText: "Altitud en metros (opcional)"; inputMethodHints: Qt.ImhFormattedNumbersOnly }
                    Button { font.family: root.fontFamily; text: "Ir a coordenadas"; enabled: lat.text.trim().length > 0 && lon.text.trim().length > 0
                        onClicked: {
                            if(root.controller.goTo(Number(lat.text.replace(",",".")),Number(lon.text.replace(",",".")),alt.text.trim().length ? Number(alt.text.replace(",",".")) : 0)) { root.sheet=""; root.coordinateEntryFinished() }
                        }
                    }
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
                    property var documentPanel: item
                    width: parent.width; height: visible && documentPanel ? documentPanel.implicitHeight : 0
                    visible: root.sheet === "files"
                    active: root.filesInitialized; source: "EarthDocumentSheet.qml"
                    onLoaded: { documentPanel.controller = root.controller; documentPanel.width = width }
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

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtPositioning
import "../components" as Components
import "../flowcore" as FlowCore

// Selector de ubicación independiente del motor cartográfico.
// La ficha mantiene latitud/longitud/altitud y captura GPS nativa; la
// visualización cartográfica completa vive en InGe Earth (Cesium).
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

    property bool awaitingGps: false
    property bool _startedTracking: false
    readonly property int gpsMaxAgeMs: 30000
    property bool gpsOnly: false
    property string gpsError: ""
    readonly property string gpsSourceLabel: "GPS del dispositivo"
    readonly property string gpsState: awaitingGps ? "searching"
        : (selected && selectedSource === gpsSourceLabel) ? "fixed"
        : gpsError.length > 0 ? "error" : "idle"

    signal requestGpsEnabled(bool enabled)
    signal requestGpsRefresh()

    function validPoint(lat, lon) {
        return isFinite(lat) && isFinite(lon)
                && lat >= -90 && lat <= 90
                && Math.abs(lon) <= 180
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
    }

    // Compatibilidad con los hosts existentes. El encuadre pertenece ahora a
    // InGe Earth, por lo que aquí solo se conserva el punto técnico.
    function centerOn(lat, lon) {
        if (validPoint(lat, lon) && !selected)
            selectCoordinate(lat, lon, NaN, NaN, "Punto de la ficha")
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

    function applyGpsFix() {
        if (!awaitingGps || !gpsFixIsFresh())
            return

        awaitingGps = false
        gpsWait.stop()
        gpsError = ""
        selectCoordinate(gpsLat, gpsLon, gpsAlt, gpsAccuracy,
                         gpsSourceLabel, true)
        followGps = false

        if (_startedTracking) {
            _startedTracking = false
            requestGpsEnabled(false)
        }

        selectionMessage = gpsOnly ? ""
            : (!isFinite(gpsAccuracy)
               ? "Posición GPS actual"
               : "Posición GPS actual ±" + Number(gpsAccuracy).toFixed(1) + " m")
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
        selectionMessage = gpsOnly ? "" : "Buscando posición GPS actual..."

        if (!gpsOnly || typeof Perms === "undefined" || !Perms.nativeTracking) {
            _startedTracking = typeof Perms !== "undefined" && !Perms.nativeTracking
            requestGpsEnabled(true)
        }
        requestFreshFix()
        gpsWait.restart()
        applyGpsFix()
    }

    Timer {
        interval: 4000
        repeat: true
        running: root.gpsOnly && root.awaitingGps
        onTriggered: root.requestFreshFix()
    }

    Connections {
        target: typeof Perms !== "undefined" ? Perms : null
        ignoreUnknownSignals: true
        function onNativePermissionChanged() {
            if (root.gpsOnly && root.awaitingGps)
                root.requestFreshFix()
        }
        function onNativeTrackingChanged() {
            if (root.gpsOnly && root.awaitingGps)
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
            root.awaitingGps = false
            root.followGps = false
            if (root._startedTracking) {
                root._startedTracking = false
                root.requestGpsEnabled(false)
            }
            root.gpsError = root.gpsDiagnostic()
            if (!root.gpsOnly)
                root.selectionMessage = root.gpsError
        }
    }

    onGpsTimestampMsChanged: applyGpsFix()
    onGpsHasFixChanged: applyGpsFix()

    Rectangle {
        anchors.fill: parent
        color: root.darkMode ? "#07111C" : "#EEF3F8"

        gradient: Gradient {
            GradientStop {
                position: 0.0
                color: root.darkMode ? "#0A1828" : "#F8FBFF"
            }
            GradientStop {
                position: 1.0
                color: root.darkMode ? "#10263A" : "#E5EEF7"
            }
        }
    }

    // Fondo técnico liviano mientras la cartografía completa se resuelve en
    // InGe Earth. Evita dependencias nativas duplicadas en Calicatas.
    Canvas {
        anchors.fill: parent
        opacity: root.darkMode ? 0.18 : 0.22
        onPaint: {
            var ctx = getContext("2d")
            ctx.clearRect(0, 0, width, height)
            ctx.strokeStyle = root.darkMode ? "#7AA8C8" : "#6E8FA8"
            ctx.lineWidth = 1
            var step = 36
            for (var x = 0; x < width; x += step) {
                ctx.beginPath()
                ctx.moveTo(x, 0)
                ctx.lineTo(x, height)
                ctx.stroke()
            }
            for (var y = 0; y < height; y += step) {
                ctx.beginPath()
                ctx.moveTo(0, y)
                ctx.lineTo(width, y)
                ctx.stroke()
            }
        }
    }

    ColumnLayout {
        anchors.centerIn: parent
        width: Math.min(parent.width - 32, 340)
        spacing: 10

        Components.FlowIcon {
            Layout.alignment: Qt.AlignHCenter
            Layout.preferredWidth: 34
            Layout.preferredHeight: 34
            name: root.awaitingGps ? "status.gps" : "map.location"
            flow: root.flow
            tintColor: root.darkMode ? "#BFD9EE" : "#174E7A"
            activeTintColor: tintColor
            inactiveOpacity: 1
        }

        Label {
            Layout.fillWidth: true
            text: root.selected ? "Ubicación de la calicata" : "Ubicación GPS"
            color: root.darkMode ? "#F4F8FC" : "#172033"
            font.pixelSize: 18
            font.weight: Font.DemiBold
            horizontalAlignment: Text.AlignHCenter
        }

        Label {
            Layout.fillWidth: true
            text: root.selected
                  ? root.selectedLat.toFixed(6) + ", " + root.selectedLon.toFixed(6)
                  : (root.awaitingGps ? "Buscando posición actual…"
                                     : "Obtén la posición del dispositivo para actualizar la ficha.")
            color: root.darkMode ? "#B9C7D6" : "#536274"
            font.pixelSize: 14
            wrapMode: Text.WordWrap
            horizontalAlignment: Text.AlignHCenter
        }

        Label {
            Layout.fillWidth: true
            visible: root.selected && isFinite(root.selectedAccuracy)
            text: "Precisión ±" + Number(root.selectedAccuracy).toFixed(1) + " m"
            color: root.darkMode ? "#8FA3B8" : "#66788A"
            font.pixelSize: 12
            horizontalAlignment: Text.AlignHCenter
        }

        Label {
            Layout.fillWidth: true
            visible: root.gpsError.length > 0 || root.selectionMessage.length > 0
            text: root.gpsError.length > 0 ? root.gpsError : root.selectionMessage
            color: root.gpsError.length > 0
                   ? (root.darkMode ? "#FFAAA3" : "#B42318")
                   : (root.darkMode ? "#9CC4E0" : "#24577D")
            font.pixelSize: 12
            wrapMode: Text.WordWrap
            horizontalAlignment: Text.AlignHCenter
        }

        Button {
            Layout.alignment: Qt.AlignHCenter
            visible: root.interactive
            enabled: !root.awaitingGps
            text: root.awaitingGps ? "Buscando…" : "Actualizar ubicación GPS"
            onClicked: root.centerGps()
        }

        Label {
            Layout.fillWidth: true
            text: "Cartografía completa: InGe Earth · Cesium"
            color: root.darkMode ? "#6F879D" : "#788A9A"
            font.pixelSize: 11
            horizontalAlignment: Text.AlignHCenter
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

    Component.onCompleted: {
        if (root.interactive)
            console.info("INGE_LOCATION_PICKER_OPEN gpsOnly=" + root.gpsOnly)
    }

    Component.onDestruction: {
        if (root._startedTracking) {
            root._startedTracking = false
            root.requestGpsEnabled(false)
        }
    }
}

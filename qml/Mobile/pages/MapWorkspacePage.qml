import QtQuick
import QtQuick.Controls
import QtCore
import QtWebView

Page {
    id: root

    required property var auth
    required property var workspaceController
    property var flow: null
    property bool darkMode: false
    property int themeMode: 0
    property bool pageActive: false
    property real navigationInset: 0

    property bool gpsEnabled: false
    property bool gpsServiceEnabled: false
    property bool gpsHasFix: false
    property bool gpsFollow: false
    property string gpsPermissionState: "undetermined"
    property string gpsStatusText: "GPS desactivado"
    property string gpsErrorText: ""
    property double gpsLat: NaN
    property double gpsLon: NaN
    property double gpsAlt: NaN
    property double gpsAccuracy: NaN
    property string gpsLastUpdate: "--:--:--"
    property string gpsProvider: ""

    property string currentCalicataCode: ""
    property string currentProjectId: ""
    property string currentProjectName: ""

    property bool pageLoaded: false
    property bool workspaceReady: false
    property bool pollInFlight: false
    property bool loadRequested: false
    property bool loadFailed: false
    property string loadError: ""

    signal requestGpsEnabled(bool enabled)
    signal requestGpsRefresh()
    signal requestGpsFollow(bool enabled)
    signal requestUsePoint(real latitude, real longitude, real altitude, string sourceLabel)
    signal requestOpenCalicatas()
    signal requestOpenLocationSettings()
    signal requestGlobalSearch(string initialText)
    signal requestExitMap()
    signal requestMeasure()
    signal mapInteractionChanged(bool active)

    background: Rectangle { color: "#02050A" }

    Settings {
        id: mapSettings
        category: "InGePlus/MapV2"
        property string pointsJson: "[]"
        property string cameraJson: "{}"
        property string selectedPointId: ""
        property string viewMode: "globe3d"
        property string mapType: "satellite"
    }

    function parseJson(text, fallbackValue) {
        try {
            var value = JSON.parse(String(text || ""))
            return value === null || value === undefined ? fallbackValue : value
        } catch (error) {
            return fallbackValue
        }
    }

    function runtimePayload() {
        return {
            runtime: workspaceController.runtimeConfiguration(),
            points: parseJson(mapSettings.pointsJson, []),
            selectedPointId: mapSettings.selectedPointId,
            camera: parseJson(mapSettings.cameraJson, {}),
            mode: mapSettings.viewMode,
            mapType: mapSettings.mapType,
            projectId: currentProjectId,
            projectName: currentProjectName,
            calicataCode: currentCalicataCode,
            gps: gpsPayload()
        }
    }

    function gpsPayload() {
        return {
            enabled: gpsEnabled,
            serviceEnabled: gpsServiceEnabled,
            hasFix: gpsHasFix,
            follow: gpsFollow,
            permissionState: gpsPermissionState,
            status: gpsStatusText,
            error: gpsErrorText,
            latitude: isFinite(gpsLat) ? gpsLat : null,
            longitude: isFinite(gpsLon) ? gpsLon : null,
            altitude: isFinite(gpsAlt) ? gpsAlt : null,
            accuracy: isFinite(gpsAccuracy) ? gpsAccuracy : null,
            lastUpdate: gpsLastUpdate,
            provider: gpsProvider
        }
    }

    function runMapScript(script, callback) {
        if (!pageLoaded || loadFailed)
            return
        if (callback)
            workspaceView.runJavaScript(script, callback)
        else
            workspaceView.runJavaScript(script, function() {})
    }

    function loadWorkspace() {
        var html = String(workspaceController.workspaceHtml || "")
        if (!html.length) {
            loadFailed = true
            loadError = "Los recursos locales de MAP V2 no están disponibles."
            return
        }
        pageLoaded = false
        workspaceReady = false
        loadFailed = false
        loadError = ""
        loadRequested = true
        workspaceView.loadHtml(
                    html,
                    "")
    }

    function configureWorkspace() {
        var json = JSON.stringify(runtimePayload())
        runMapScript("window.InGeMap ? window.InGeMap.configure(" + json + ") : null")
    }

    function pushGps() {
        var json = JSON.stringify(gpsPayload())
        runMapScript("window.InGeMap ? window.InGeMap.updateGps(" + json + ") : null")
    }

    function persistPoints(event) {
        if (!(event.points instanceof Array))
            return
        mapSettings.pointsJson = JSON.stringify(event.points)
        mapSettings.selectedPointId = String(event.selectedPointId || "")
    }

    function eventAltitude(value) {
        return value === null || value === undefined || !isFinite(Number(value))
                ? NaN : Number(value)
    }

    function handleBridgeEvent(event) {
        var type = String(event.type || "")
        if (type === "html.ready") {
            configureWorkspace()
        } else if (type === "workspace.ready") {
            workspaceReady = true
        } else if (type === "workspace.error") {
            loadError = String(event.message || "El renderer no pudo iniciar")
        } else if (type === "navigation.back") {
            requestExitMap()
        } else if (type === "points.changed") {
            persistPoints(event)
        } else if (type === "camera.changed" && event.camera) {
            mapSettings.cameraJson = JSON.stringify(event.camera)
        } else if (type === "view.changed") {
            mapSettings.viewMode = String(event.mode || "globe3d")
            mapSettings.mapType = String(event.mapType || "satellite")
        } else if (type === "gps.enabled") {
            requestGpsEnabled(event.enabled === true)
        } else if (type === "gps.refresh") {
            requestGpsRefresh()
        } else if (type === "gps.follow") {
            requestGpsFollow(event.enabled === true)
        } else if (type === "point.use") {
            requestUsePoint(Number(event.latitude), Number(event.longitude),
                            eventAltitude(event.altitude),
                            String(event.sourceLabel || "Punto del mapa"))
        } else if (type === "measure.request") {
            requestMeasure()
        }
    }

    function drainBridge() {
        if (pollInFlight || !pageLoaded || loadFailed)
            return
        pollInFlight = true
        workspaceView.runJavaScript(
                    "window.ingeBridge ? window.ingeBridge.takeEvents() : '[]'",
                    function(result) {
            root.pollInFlight = false
            var batch = root.parseJson(result, [])
            if (!(batch instanceof Array))
                return
            for (var i = 0; i < batch.length; ++i)
                root.handleBridgeEvent(batch[i])
        })
    }

    onGpsEnabledChanged: gpsPushTimer.restart()
    onGpsServiceEnabledChanged: gpsPushTimer.restart()
    onGpsHasFixChanged: gpsPushTimer.restart()
    onGpsFollowChanged: gpsPushTimer.restart()
    onGpsLatChanged: gpsPushTimer.restart()
    onGpsLonChanged: gpsPushTimer.restart()
    onGpsAltChanged: gpsPushTimer.restart()
    onGpsAccuracyChanged: gpsPushTimer.restart()
    onGpsLastUpdateChanged: gpsPushTimer.restart()
    onGpsProviderChanged: gpsPushTimer.restart()

    onPageActiveChanged: {
        runMapScript("window.InGeMap ? window.InGeMap.setActive("
                     + (pageActive ? "true" : "false") + ") : null")
    }

    Timer {
        id: bridgePollTimer
        interval: 140
        repeat: true
        running: root.pageActive && root.pageLoaded && !root.loadFailed
        onTriggered: root.drainBridge()
    }

    Timer {
        id: gpsPushTimer
        interval: 180
        repeat: false
        onTriggered: root.pushGps()
    }

    WebView {
        id: workspaceView
        anchors.fill: parent
        visible: !root.loadFailed

        onLoadingChanged: function(loadRequest) {
            if (loadRequest.status === WebView.LoadSucceededStatus) {
                root.pageLoaded = true
                root.loadFailed = false
                root.loadError = ""
            } else if (loadRequest.status === WebView.LoadFailedStatus) {
                root.pageLoaded = false
                root.loadFailed = true
                root.loadError = String(loadRequest.errorString || "No se pudo abrir MAP V2")
            }
        }
    }

    // Solo aparece cuando la vista nativa está oculta por un fallo de carga;
    // nunca se superpone al WebView en Android.
    Rectangle {
        anchors.fill: parent
        visible: !workspaceView.visible
        color: "#06111E"

        Column {
            anchors.centerIn: parent
            width: Math.min(parent.width - 48, 360)
            spacing: 12

            Label {
                width: parent.width
                text: "MAP V2 no pudo iniciar"
                color: "#F6F9FC"
                font.pixelSize: 22
                font.bold: true
                horizontalAlignment: Text.AlignHCenter
            }
            Label {
                width: parent.width
                text: root.loadError.length ? root.loadError
                                            : "No se pudo desplegar el workspace web local."
                color: "#B9C7D6"
                font.pixelSize: 14
                wrapMode: Text.WordWrap
                horizontalAlignment: Text.AlignHCenter
            }
            Button {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "Volver a Inicio"
                onClicked: root.requestExitMap()
            }
        }
    }

    Component.onCompleted: {
        if (!workspaceController) {
            loadFailed = true
            loadError = "El controlador de MAP V2 no está disponible."
        } else {
            loadWorkspace()
        }
    }

    Component.onDestruction: mapInteractionChanged(false)
}

import QtQuick
import QtLocation
import QtPositioning

Item {
    id: root

    property real minZoom: 2
    property real maxZoom: 19
    property real wheelStep: 0.25
    property real _lastPinchScale: 1.0

    property bool hasController: (typeof mapController !== "undefined" && mapController)
    property bool manualMode: hasController ? !mapController.gpsActive : true
    property bool markerDragActive: false

    property var currentCoord: (
        hasController && mapController.coordinate !== undefined
    ) ? mapController.coordinate : QtPositioning.coordinate()

    function clamp(v, lo, hi) {
        return Math.max(lo, Math.min(hi, v))
    }

    function breakCenterBinding() {
        // Esto rompe cualquier binding activo de center
        map.center = map.center
    }

    function applyCoordinate(c) {
        if (!c || !c.isValid)
            return

        breakCenterBinding()

        if (hasController) {
            mapController.followGps = false
            mapController.pickCoordinate(c)
        }
    }

    function recenterOnMarker() {
        if (!currentCoord || !currentCoord.isValid)
            return

        map.center = currentCoord

        if (hasController && mapController.gpsActive)
            mapController.followGps = true
    }

    Plugin {
        id: osmPlugin
        name: "osm"

        PluginParameter { name: "osm.useragent"; value: "InGePlus/1.0" }
        PluginParameter { name: "osm.mapping.providersrepository.disabled"; value: true }
        PluginParameter { name: "osm.mapping.host"; value: "https://tile.openstreetmap.org/" }
    }

    Map {
        id: map
        anchors.fill: parent
        plugin: osmPlugin

        zoomLevel: hasController ? mapController.zoom : 16

        // Centro inicial. OJO: sí puede arrancar ligado al pin,
        // pero al primer gesto del usuario rompemos esa relación.
        center: (currentCoord && currentCoord.isValid)
                ? currentCoord
                : QtPositioning.coordinate(-5.1946, -80.6327)

        Binding {
            target: map
            property: "center"
            when: hasController
                  && mapController.followGps
                  && currentCoord
                  && currentCoord.isValid
            value: currentCoord
        }

        onZoomLevelChanged: function() {
            if (hasController)
                mapController.zoom = map.zoomLevel
        }

        // ---------------------------
        // Marcador / puntero principal
        // ---------------------------
        MapQuickItem {
            id: pin
            coordinate: currentCoord
            anchorPoint.x: markerRoot.width / 2
            anchorPoint.y: markerRoot.height / 2
            visible: currentCoord && currentCoord.isValid

            sourceItem: Item {
                id: markerRoot
                width: 24
                height: 24

                Rectangle {
                    anchors.fill: parent
                    radius: width / 2
                    color: "white"
                    border.width: 3
                    border.color: "#111111"
                }

                MouseArea {
                    id: markerMouse
                    anchors.fill: parent
                    enabled: root.manualMode
                    hoverEnabled: enabled
                    preventStealing: true
                    acceptedButtons: Qt.LeftButton
                    cursorShape: enabled
                                 ? (pressed ? Qt.ClosedHandCursor : Qt.OpenHandCursor)
                                 : Qt.ArrowCursor

                    property point grabOffset: Qt.point(0, 0)

                    onPressed: function(mouse) {
                        root.breakCenterBinding()
                        root.markerDragActive = true

                        if (root.hasController) {
                            mapController.followGps = false
                            mapController.beginManualDrag()
                        }

                        grabOffset = Qt.point(
                            mouse.x - markerRoot.width / 2,
                            mouse.y - markerRoot.height / 2
                        )
                        mouse.accepted = true
                    }

                    onPositionChanged: function(mouse) {
                        if (!pressed || !enabled)
                            return

                        var mapPt = markerRoot.mapToItem(
                            map,
                            mouse.x - grabOffset.x,
                            mouse.y - grabOffset.y
                        )

                        var c = map.toCoordinate(Qt.point(mapPt.x, mapPt.y), false)
                        root.applyCoordinate(c)
                        mouse.accepted = true
                    }

                    onReleased: function(mouse) {
                        root.markerDragActive = false

                        if (root.hasController)
                            mapController.endManualDrag()

                        mouse.accepted = true
                    }

                    onCanceled: {
                        root.markerDragActive = false

                        if (root.hasController)
                            mapController.endManualDrag()
                    }
                }
            }
        }

        // ---------------------------
        // PAN del mapa
        // ---------------------------
        DragHandler {
            id: drag
            target: null
            enabled: !root.markerDragActive
            acceptedButtons: Qt.LeftButton
            property point lastT: Qt.point(0, 0)

            onActiveChanged: {
                if (active) {
                    root.breakCenterBinding()
                    lastT = translation
                    if (root.hasController)
                        mapController.followGps = false
                }
            }

            onTranslationChanged: {
                if (!active)
                    return

                const dx = translation.x - lastT.x
                const dy = translation.y - lastT.y

                map.pan(-dx, -dy)
                lastT = translation
            }
        }

        // ---------------------------
        // Zoom rueda
        // ---------------------------
        WheelHandler {
            target: null

            onWheel: function(w) {
                root.breakCenterBinding()

                if (root.hasController)
                    mapController.followGps = false

                var steps = w.angleDelta.y / 120.0
                if (steps === 0)
                    return

                map.zoomLevel = root.clamp(
                    map.zoomLevel + steps * root.wheelStep,
                    root.minZoom,
                    root.maxZoom
                )
            }
        }

        // ---------------------------
        // Pinch / touchpad
        // ---------------------------
        PinchHandler {
            target: null

            onActiveChanged: {
                if (active) {
                    root.breakCenterBinding()
                    root._lastPinchScale = 1.0
                    if (root.hasController)
                        mapController.followGps = false
                }
            }

            onScaleChanged: {
                var delta = scale / root._lastPinchScale
                root._lastPinchScale = scale

                var dz = Math.log(delta) / Math.log(2)
                if (dz !== 0) {
                    map.zoomLevel = root.clamp(
                        map.zoomLevel + dz,
                        root.minZoom,
                        root.maxZoom
                    )
                }
            }
        }

        // ---------------------------
        // Doble clic para ubicar punto
        // ---------------------------
        TapHandler {
            acceptedButtons: Qt.LeftButton
            gesturePolicy: TapHandler.ReleaseWithinBounds

            onDoubleTapped: function(eventPoint, button) {
                if (!root.manualMode)
                    return

                root.breakCenterBinding()

                var c = map.toCoordinate(eventPoint.position, false)
                root.applyCoordinate(c)

                if (c && c.isValid)
                    map.center = c
            }
        }

        // ---------------------------
        // Botón flotante centrar
        // ---------------------------
        Rectangle {
            id: btnCenter
            width: 44
            height: 44
            radius: 22
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.margins: 12
            color: (root.hasController && mapController.gpsActive && mapController.followGps)
                   ? "#E8F5E9" : "#FFFFFF"
            border.width: 1
            border.color: "#9aa6b2"
            opacity: 0.95

            Text {
                anchors.centerIn: parent
                text: "⌖"
                font.pixelSize: 20
                color: "#0B4F86"
            }

            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: root.recenterOnMarker()
            }
        }
    }
}

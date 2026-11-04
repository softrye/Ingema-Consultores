import QtQuick
import QtQuick.Controls
import "../lib/CalicataRules.js" as Rules
import "../lib/CalicataElevation.js" as Elevation

// Ficha · Ubicación · mapa a pantalla completa (preview aprobado
// docs/previews/ubicacion_mapa_completo_aprobado.webp). UN solo Map: el editor
// adopta el CalicatasTopoMap de la tarjeta (`map`, reparentado) mientras está
// abierto y lo devuelve al cerrar. El punto se coloca moviendo el mapa bajo la cruz.
// Hero usa el InGeCoreFlow existente y reparenta el Map AL FINAL de la
// transición (no reescala la superficie GPU en cada fotograma).
// El Dock global se reutiliza SOLO mientras el mapa está abierto:
// InGeCoreFlow.dockOverride presenta cuatro herramientas a la derecha.
// "Fijar ubicación" emite un único borrador commitLocation; el formulario guarda.
Item {
    id: editor
    property var form: null                      // CalicataFormPage (dp, sp, darkMode, flow)
    property var flow: form ? form.flow : null
    property var savedPoint: ({ lat: NaN, lon: NaN })
    property string documentId: ""
    property bool commitAccepted: false
    property var header: ({})
    property real topInset: dp(34)
    property string iconFamily: lucide.status === FontLoader.Ready ? lucide.font.family : ""
    property url iconSource: "qrc:/InGe/Mobile/fonts/lucide/Lucide-w300.ttf"
    property bool reducedMotion: !!flow && flow.motionAllowed === false
    // One transactional action; the form remains the only owner of setters
    // and document persistence. No duplicate document model in this editor.
    signal commitLocation(var draft)
    signal closed()

    FontLoader { id: lucide; source: editor.iconSource }
    function dp(v) { return form && form.dp ? form.dp(v) : v }
    function sp(v) { return form && form.sp ? form.sp(v) : v }
    readonly property bool dark: !!form && form.darkMode === true
    readonly property bool hasSaved: isFinite(savedPoint.lat) && isFinite(savedPoint.lon)

    // ------------------------------------------------------------ Hero
    property bool open: false
    property real t: 0                            // 0 = tarjeta, 1 = pantalla completa
    property rect fromRect: Qt.rect(0, 0, 0, 0)
    // Cubre la ventana (o `coverItem`, p. ej. un marco de prueba).
    property Item coverItem: null
    readonly property point origin: parent ? parent.mapFromItem(coverItem, 0, 0) : Qt.point(0, 0)
    readonly property real fullW: coverItem ? coverItem.width : (Window.width > 0 ? Window.width : (parent ? parent.width : 0))
    readonly property real fullH: coverItem ? coverItem.height : (Window.height > 0 ? Window.height : (parent ? parent.height : 0))
    readonly property var hero: flow && flow.hero ? flow.hero : null
    visible: open || t > 0.001
    x: fromRect.x + (origin.x - fromRect.x) * t
    y: fromRect.y + (origin.y - fromRect.y) * t
    width: fromRect.width + (fullW - fromRect.width) * t
    height: fromRect.height + (fullH - fromRect.height) * t
    z: 1000
    readonly property int heroDuration: reducedMotion ? 0
        : hero ? hero.duration(Math.abs(origin.x - fromRect.x) + Math.abs(origin.y - fromRect.y)
                               + (fullW - fromRect.width) + (fullH - fromRect.height)) : 300
    NumberAnimation {
        id: heroAnim
        target: editor; property: "t"
        duration: editor.heroDuration
        easing.type: editor.hero ? Easing.BezierSpline : Easing.InOutCubic
        easing.bezierCurve: editor.hero ? editor.hero.standard : []
        onFinished: if (editor.t < 0.001) {
            editor._publishDock(false)
            editor._returnMap()
            editor.closed()
        }
    }
    onTChanged: {
        // Respaldo para duración Hero=0 (reduced motion): el Dock vertical
        // se libera exactamente al volver a la tarjeta, nunca a mitad
        // del cierre cuando aún cubre los botones de la ficha.
        if (!open && t < 0.001 && _ownedDockOverride)
            _publishDock(false)
        if (t >= 0.999 && open && map && map.parent !== mapHost) {
            // Do NOT resize a QtLocation Map in every Hero animation frame.
            _adoptMap()
            if (hasSaved) map.centerOn(savedPoint.lat, savedPoint.lon, 15)
            else map.setCamera(-12.05, -77.04, 6)
            sheet.loadFromCenter()
            console.info("INGE_CALICATA_MAP_HERO_READY single_engine=1")
            if (_openMode === "gps") useMyLocation()
        }
    }
    // mode: "move" | "coordinates" | "gps"
    property string _openMode: "move"
    function openFrom(cardItem, mode) {
        if (cardItem && parent) {
            var p = cardItem.mapToItem(parent, 0, 0)
            fromRect = Qt.rect(p.x, p.y, cardItem.width, cardItem.height)
        } else fromRect = Qt.rect(origin.x, origin.y, fullW, fullH)
        _openMode = mode || "move"
        sheetOpen = mode === "coordinates"
        gpsMode = false
        if (!map) return
        // Un único Dock real: cambia temporalmente sus herramientas a la
        // columna de la referencia; no se toca su preset/posición normal.
        open = true
        _publishDock(true)
        // Map stays at its original card dimensions during Hero. Reparent once
        // at completion, avoiding expensive GPU texture reallocations.
        heroAnim.stop(); heroAnim.from = t; heroAnim.to = 1; heroAnim.start()
        if (heroDuration === 0) {
            t = 1
        }
    }
    function close() {
        if (!open) return
        _returnMap() // free fullscreen Map GPU before Hero reverse animation
        Qt.inputMethod.hide()
        open = false
        heroAnim.stop(); heroAnim.from = t; heroAnim.to = 0; heroAnim.start()
    }
    function handleBack() {
        if (!open) return false
        if (sheetOpen) { sheetOpen = false; return true }
        close()
        return true
    }

    // Esquinas de la tarjeta mientras viaja (sin capa: anillo exterior).
    clip: false // never clip the QtLocation Map through the Hero transition
    readonly property real cornerRadius: dp(20) * (1 - t)

    // ------------------------------------------------------------ Mapa
    property bool sheetOpen: false
    property bool gpsMode: false
    property var _ownedDockOverride: null

    function _publishDock(activate) {
        if (!flow) return
        if (!activate) {
            // No borrar el contexto si otra pantalla tomó la propiedad.
            if (_ownedDockOverride && flow.dockOverride === _ownedDockOverride)
                flow.dockOverride = null
            _ownedDockOverride = null
            return
        }
        if (!open) return
        var selected = sheetOpen ? "map.coordinates" : (gpsMode ? "map.gps" : "map.move")
        var entry = {
            id: "calicatas.location.fullscreen",
            vertical: true,
            actions: [
                // El Dock real despacha SOLO acciones con .command.
                // Sin este campo dockSlotTap muestra el botón pero NO ejecuta.
                { id: "map.move", command: "map.move", tapCommand: true,
                  label: "Mover punto", glyph: 0xE111,
                  selected: selected === "map.move", enabled: true },
                { id: "map.coordinates", command: "map.coordinates", tapCommand: true,
                  label: "Ingresar coordenadas", glyph: 0xE0E9,
                  selected: selected === "map.coordinates", enabled: true },
                { id: "map.gps", command: "map.gps", tapCommand: true,
                  label: "Mi ubicación", glyph: 0xE123,
                  selected: selected === "map.gps", enabled: true },
                { id: "map.center", command: "map.center", tapCommand: true,
                  label: "Centrar", glyph: 0xE1DB,
                  selected: false, enabled: hasSaved }
            ],
            command: function(actionId) { editor.runCommand(actionId) }
        }
        _ownedDockOverride = entry
        flow.dockOverride = entry
        console.info("INGE_CALICATA_MAP_DOCK vertical=1 actions=4 selected=" + selected)
    }
    function _refreshDock() {
        // Evitar destruir un delegado del Dock durante su propio onClicked.
        if (!open || !_ownedDockOverride) return
        Qt.callLater(function() { if (editor.open && editor._ownedDockOverride)
            editor._publishDock(true) })
    }
    onSheetOpenChanged: _refreshDock()
    onGpsModeChanged: _refreshDock()
    readonly property real sheetHeight: sheetOpen ? sheet.height : 0
    // Map compartido con la tarjeta (sin segundo motor ni efectos encima).
    property var map: null
    property Item _mapHome: null
    Item { id: mapHost; anchors.fill: parent }
    function _adoptMap() {
        if (!map || map.parent === mapHost) return
        _mapHome = map.parent
        map.parent = mapHost
    }
    function _returnMap() {
        if (map && _mapHome && map.parent === mapHost) map.parent = _mapHome
    }
    Binding {
        target: editor.map
        property: "bottomInset"
        value: editor.sheetOpen ? editor.sheetHeight : editor.dp(96)
        when: !!editor.map && editor.open
        restoreMode: Binding.RestoreBindingOrValue
    }
    // Punto bajo la cruz (centro óptico del mapa).
    readonly property var crossPoint: {
        if (!map) return { lat: NaN, lon: NaN }
        var dep = map.centerLat + map.centerLon + map.zoom + map.bearing + map.bottomInset + map.height
        var scale = map.tileSize * Math.pow(2, map.zoom)
        var wy = map.worldY(map.centerLat) + (map.originY - map.height / 2) / scale
        var wx = map.worldX(map.centerLon) + (map.originX - map.width / 2) / scale
        return { lat: map.latFromWorldY(wy), lon: map.lonFromWorldX(wx) }
    }
    readonly property string datum: sheet.datum.length ? sheet.datum
                                    : (header && header.datum === "PSAD56" ? "PSAD56" : "WGS84")
    readonly property var crossUtm: Rules.geoToUtmForDatum(crossPoint.lat, crossPoint.lon, datum)
    function _fmt(v) {
        var n = Number(v)
        if (!isFinite(n)) return "—"
        var parts = n.toFixed(3).split(".")
        return parts[0].replace(/\B(?=(\d{3})+(?!\d))/g, " ") + "." + parts[1]
    }
    // One lightweight saved marker only. No per-frame ShapePath/curve renderer.
    readonly property point savedScreen: {
        var dep = map ? (map.centerLat + map.centerLon + map.zoom + map.bearing + map.width + map.height) : 0
        return hasSaved && map ? map.screenPoint(savedPoint.lat,savedPoint.lon) : Qt.point(-100,-100)
    }
    Rectangle {
        visible: editor.hasSaved
        width: editor.dp(18); height: width; radius: width / 2
        x: editor.savedScreen.x - width / 2; y: editor.savedScreen.y - height / 2
        color: "#F39A1E"; border.width: editor.dp(2.5); border.color: "white"
    }
    Item {                                        // cruz central: el punto se coloca moviendo el mapa
        x: map.originX - width / 2; y: map.originY - height / 2
        width: editor.dp(70); height: width
        readonly property color ink: editor.dark ? "white" : "#1E2833"
        Rectangle { x: 0; y: parent.height / 2 - height / 2; width: parent.width / 2 - editor.dp(6); height: editor.dp(1.6); color: parent.ink }
        Rectangle { x: parent.width / 2 + editor.dp(6); y: parent.height / 2 - height / 2; width: parent.width / 2 - editor.dp(6); height: editor.dp(1.6); color: parent.ink }
        Rectangle { x: parent.width / 2 - width / 2; y: 0; width: editor.dp(1.6); height: parent.height / 2 - editor.dp(6); color: parent.ink }
        Rectangle { x: parent.width / 2 - width / 2; y: parent.height / 2 + editor.dp(6); width: editor.dp(1.6); height: parent.height / 2 - editor.dp(6); color: parent.ink }
        Rectangle { anchors.centerIn: parent; width: editor.dp(11); height: width; color: "transparent"
                    border.width: editor.dp(1.6); border.color: parent.ink }
    }

    // Esmerilado visible en claro y oscuro: vidrio del Dock + velo (nunca transparente).
    readonly property color veil: dark ? Qt.rgba(28 / 255, 38 / 255, 42 / 255, 0.90) : Qt.rgba(248 / 255, 250 / 255, 251 / 255, 0.92)
    readonly property color ink: dark ? "#FFFFFF" : "#17212B"
    readonly property color inkMuted: dark ? Qt.rgba(1, 1, 1, 0.72) : "#4A5562"
    // Esmerilado estático: velo opaco + filo, sin capturas ni shaders sobre el Map
    // (el mapa se mueve a la tasa del dispositivo; también en LOW).
    component Glass: Rectangle {
        color: editor.veil
        radius: height / 2
        border.width: 1
        border.color: editor.dark ? Qt.rgba(1, 1, 1, 0.14) : Qt.rgba(1, 1, 1, 0.9)
        Rectangle {
            anchors.fill: parent; anchors.margins: 1; radius: parent.radius - 1
            gradient: Gradient {
                GradientStop { position: 0.0; color: editor.dark ? Qt.rgba(1, 1, 1, 0.08) : Qt.rgba(1, 1, 1, 0.55) }
                GradientStop { position: 0.5; color: Qt.rgba(1, 1, 1, 0) }
            }
        }
    }
    component FieldLabel: Text { color: editor.inkMuted; font.pixelSize: editor.sp(12.5) }
    component NumField: TextField {
        width: coordGrid.cellW; height: editor.dp(42)
        inputMethodHints: Qt.ImhFormattedNumbersOnly | Qt.ImhNoPredictiveText
        color: editor.ink; font.pixelSize: editor.sp(15)
        leftPadding: editor.dp(12)
        background: Rectangle { radius: editor.dp(10)
            color: editor.dark ? Qt.rgba(1, 1, 1, 0.06) : "white"
            border.width: 1; border.color: parent.acceptableInput && parent.ok !== false ? (editor.dark ? Qt.rgba(1, 1, 1, 0.16) : "#D4DAE0") : "#D64545" }
        property bool ok: true
        onTextEdited: sheet.jump()
    }
    component RoundButton2: Glass {
        id: rb
        property int glyph: 0
        property string accessibleName: ""
        signal tapped()
        width: editor.dp(58); height: width
        scale: rbTap.pressed ? 0.94 : 1
        Behavior on scale { NumberAnimation { duration: 120 } }
        Text { anchors.centerIn: parent; text: String.fromCharCode(rb.glyph); font.family: editor.iconFamily
               font.pixelSize: editor.dp(22); color: editor.ink }
        MouseArea { id: rbTap; anchors.fill: parent; onClicked: rb.tapped() }
        Accessible.role: Accessible.Button
        Accessible.name: rb.accessibleName
    }

    Item {
        id: chrome
        anchors.fill: parent
        opacity: Math.max(0, (editor.t - 0.55) / 0.45)
        visible: opacity > 0.01

        RoundButton2 {                            // ✕ cerrar
            x: editor.dp(16); y: editor.topInset + editor.dp(8)
            glyph: 0xE1B2; accessibleName: "Cerrar el mapa"
            onTapped: editor.close()
        }
        Glass {                                   // píldora E · N · zona  /  Lat · Lon
            id: coordPill
            anchors.horizontalCenter: parent.horizontalCenter
            y: editor.topInset + editor.dp(62)
            width: Math.min(parent.width - editor.dp(40), pillCol.implicitWidth + editor.dp(36))
            height: pillCol.implicitHeight + editor.dp(18)
            radius: editor.dp(18)
            Column {
                id: pillCol
                anchors.centerIn: parent; spacing: editor.dp(2)
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: editor.crossUtm ? "E " + editor._fmt(editor.crossUtm.easting) + " · N " + editor._fmt(editor.crossUtm.northing)
                                            + " · " + editor.crossUtm.zone + editor.crossUtm.band : "Mueve el mapa para ubicar el punto"
                    color: editor.ink; font.pixelSize: editor.sp(15); font.weight: Font.DemiBold
                }
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: "Lat " + editor.crossPoint.lat.toFixed(6) + " · Lon " + editor.crossPoint.lon.toFixed(6)
                    color: editor.inkMuted; font.pixelSize: editor.sp(12.5)
                }
            }
            MouseArea {
                anchors.fill: parent
                Accessible.role: Accessible.Button
                Accessible.name: "Escribir coordenadas"
                onClicked: editor.openManualSheet()
            }
        }
        Rectangle {                               // ± X m · GPS (dato real del posicionamiento)
            radius: height / 2
            color: Qt.rgba(36 / 255, 140 / 255, 66 / 255, 0.92)
            border.width: 1; border.color: Qt.rgba(1, 1, 1, 0.25)
            readonly property real accuracy: typeof Perms !== "undefined" && Perms ? Number(Perms.nativeAccuracy) : NaN
            visible: editor.gpsMode && !!map && map.gpsState === "ready" && isFinite(accuracy) && accuracy > 0
            anchors.left: coordPill.left
            anchors.top: coordPill.bottom; anchors.topMargin: editor.dp(8)
            width: accRow.implicitWidth + editor.dp(24); height: editor.dp(32)
            Row {
                id: accRow
                anchors.centerIn: parent; spacing: editor.dp(6)
                Text { anchors.verticalCenter: parent.verticalCenter; text: String.fromCharCode(0xE44B); font.family: editor.iconFamily
                       font.pixelSize: editor.dp(15); color: "white" }
                Text { anchors.verticalCenter: parent.verticalCenter
                       text: "± " + Math.max(1, Math.round(parent.parent.accuracy)) + " m · GPS"
                       color: "white"; font.pixelSize: editor.sp(13); font.weight: Font.DemiBold }
            }
        }
        // Las cuatro herramientas de mapa están en el Dock vertical
        // verdadero (a la derecha), no en una segunda barra flotante.

        // ---------------------------------------------- Ingresar coordenadas
        Item {
            id: sheet
            anchors.left: parent.left; anchors.right: parent.right
            y: editor.sheetOpen ? parent.height - height - editor.keyboardInset : parent.height + editor.dp(20)
            Behavior on y { enabled: !editor.reducedMotion
                NumberAnimation { duration: editor.hero ? editor.hero.duration(sheet.height) : 260
                                  easing.type: editor.hero ? Easing.BezierSpline : Easing.OutCubic
                                  easing.bezierCurve: editor.hero ? editor.hero.deceleration : [] } }
            visible: y < parent.height
            implicitHeight: sheetCol.implicitHeight + editor.dp(130)
            height: Math.min(implicitHeight, Math.max(editor.dp(250),
                   editor.height - editor.topInset - editor.dp(54) - editor.keyboardInset))
            property string datum: ""
            property var altitudePatch: null
            property string altitudeRequestId: ""
            property string altitudeStatus: ""
            function loadFromCenter() {
                datum = editor.header && editor.header.datum === "PSAD56" ? "PSAD56" : "WGS84"
                var h = editor.header || {}
                fieldE.text = String(h.utm_x || (editor.crossUtm ? editor.crossUtm.easting.toFixed(3) : ""))
                fieldN.text = String(h.utm_y || (editor.crossUtm ? editor.crossUtm.northing.toFixed(3) : ""))
                var z=String(h.zona || h.utm_zone || "").trim().toUpperCase()
                // Legacy numeric-only zone (e.g. "18") from the remote
                // database: derive the band from the document's own E/N and
                // datum, NOT from the default map camera. CalicataRules
                // interprets bare UTM zones in the Southern Hemisphere.
                var numericZone=/^(?:[1-9]|[1-5][0-9]|60)$/.test(z)
                var geo=numericZone
                      ? Rules.utmToGeoForDatum(fieldE.text,fieldN.text,z,datum) : null
                var actual=geo ? Rules.geoToUtmForDatum(geo.latitude,geo.longitude,datum) : null
                var mapHint=editor.crossUtm
                      ? String(editor.crossUtm.zone)+String(editor.crossUtm.band) : ""
                // Unknown E/N: keep the invalid "18" visible for correction.
                fieldZone.text=numericZone ? (actual ? z+String(actual.band) : z)
                                           : (z || mapHint)
                fieldZ.text = h.utm_z === undefined || h.utm_z === null ? "" : String(h.utm_z)
                fieldSide.currentIndex = editor.roadSideIndex()
                fieldProgresiva.text = String(h.progresiva || h.pk || "")
                fieldTramo.text = String(h.ubicacion || h.tramo || "")
                altitudePatch = null
                altitudeRequestId = ""
                altitudeStatus = ""
            }
            readonly property bool eOk: Rules.validateDecimalRange(fieldE.text, 100000, 900000)
            readonly property bool nOk: Rules.validateDecimalRange(fieldN.text, 0, 10000000)
            readonly property bool zoneOk: /^(?:[1-9]|[1-5][0-9]|60)[C-HJ-NP-X]$/i.test(fieldZone.text.trim())
            readonly property bool zOk: fieldZ.text.trim().length === 0 || Rules.validateDecimalRange(fieldZ.text, -12000, 10000)
            readonly property bool pkOk: !fieldProgresiva.text.trim().length
                                       || Rules.isValidProgresiva(Rules.normalizeProgresiva(fieldProgresiva.text))
            readonly property bool valid: eOk && nOk && zoneOk && zOk && pkOk
            // «Al ingresar coordenadas, el punto saltará a esa posición».
            function changeDatum(nextDatum) {
                if (nextDatum===datum) return
                var before=editor.crossPoint
                datum=nextDatum
                var projected=Rules.geoToUtmForDatum(before.lat,before.lon,nextDatum)
                if (projected) {
                    fieldE.text=String(projected.easting.toFixed(3))
                    fieldN.text=String(projected.northing.toFixed(3))
                    fieldZone.text=String(projected.zone)+String(projected.band)
                }
                altitudePatch=null
                altitudeRequestId=""
            }
            function jump() {
                altitudePatch=null  // coordinate changed: discard old DEM response
                altitudeRequestId=""
                if (!(eOk && nOk && zoneOk)) return
                var g = Rules.utmToGeoForDatum(fieldE.text, fieldN.text, fieldZone.text.trim(), datum)
                if (g) map.centerOn(g.latitude, g.longitude, map.zoom)
            }
            Rectangle {
                anchors.fill: parent
                anchors.bottomMargin: -editor.dp(30)
                radius: editor.dp(26)
                color: editor.dark ? Qt.rgba(24 / 255, 32 / 255, 36 / 255, 0.96) : Qt.rgba(1, 1, 1, 0.96)
                border.width: 1; border.color: editor.dark ? Qt.rgba(1, 1, 1, 0.08) : Qt.rgba(0, 0, 0, 0.06)
                MouseArea { anchors.fill: parent }
            }
            Rectangle { anchors.horizontalCenter: parent.horizontalCenter; y: editor.dp(8); width: editor.dp(38); height: editor.dp(4)
                        radius: height / 2; color: editor.dark ? Qt.rgba(1, 1, 1, 0.25) : Qt.rgba(0, 0, 0, 0.18) }
            Flickable {
                id: sheetScroll
                x: editor.dp(20); y: editor.dp(22)
                width: parent.width - editor.dp(40)
                height: Math.max(editor.dp(120), sheet.height - editor.dp(96))
                contentHeight: sheetCol.implicitHeight
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                flickableDirection: Flickable.VerticalFlick
            Column {
                id: sheetCol
                width: sheetScroll.width
                spacing: editor.dp(10)
                Row {
                    spacing: editor.dp(10)
                    Text { anchors.verticalCenter: parent.verticalCenter; text: String.fromCharCode(0xE0E9); font.family: editor.iconFamily
                           font.pixelSize: editor.dp(20); color: editor.ink }
                    Text { anchors.verticalCenter: parent.verticalCenter; text: "Ingresar coordenadas"; color: editor.ink
                           font.pixelSize: editor.sp(17); font.weight: Font.DemiBold }
                }
                Rectangle {                        // WGS84 | PSAD56
                    width: parent.width; height: editor.dp(38); radius: editor.dp(12)
                    color: editor.dark ? Qt.rgba(1, 1, 1, 0.07) : "#EEF1F3"
                    Row {
                        anchors.fill: parent; anchors.margins: editor.dp(3)
                        Repeater {
                            model: ["WGS84", "PSAD56"]
                            delegate: Rectangle {
                                required property string modelData
                                width: (parent.width) / 2; height: parent.height; radius: editor.dp(10)
                                color: sheet.datum === modelData ? (editor.dark ? "#2F7D46" : "#BFEBC8") : "transparent"
                                Text { anchors.centerIn: parent; text: parent.modelData
                                       color: sheet.datum === parent.modelData ? (editor.dark ? "white" : "#1E6B35") : editor.inkMuted
                                       font.pixelSize: editor.sp(13); font.weight: Font.DemiBold }
                                MouseArea { anchors.fill: parent; onClicked: sheet.changeDatum(parent.modelData) }
                            }
                        }
                    }
                }
                Grid {
                    id: coordGrid
                    columns: 2; columnSpacing: editor.dp(14); rowSpacing: editor.dp(8)
                    width: parent.width
                    readonly property real cellW: (width - columnSpacing) / 2
                    FieldLabel { text: "E (Este)" }
                    FieldLabel { text: "N (Norte)" }
                    NumField { id: fieldE; ok: text.length === 0 || sheet.eOk; Accessible.name: "Este UTM" }
                    NumField { id: fieldN; ok: text.length === 0 || sheet.nOk; Accessible.name: "Norte UTM" }
                    FieldLabel { text: "Zona y banda" }
                    FieldLabel { text: "Cota / Z" }
                    NumField {                         // zona con banda: texto + lista de zonas del Perú
                        id: fieldZone
                        ok: text.length === 0 || sheet.zoneOk
                        inputMethodHints: Qt.ImhUppercaseOnly | Qt.ImhNoPredictiveText
                        rightPadding: editor.dp(40)
                        onTextEdited: {
                            var up = text.toUpperCase()
                            if (up !== text) text = up
                            sheet.jump()
                        }
                        Accessible.name: "Zona UTM con banda"
                        Text { anchors.right: parent.right; anchors.rightMargin: editor.dp(12); anchors.verticalCenter: parent.verticalCenter
                               text: String.fromCharCode(0xE06D); font.family: editor.iconFamily; font.pixelSize: editor.dp(18); color: editor.inkMuted
                               MouseArea { anchors.fill: parent; anchors.margins: -editor.dp(10); onClicked: zoneMenu.popup() } }
                        Menu {
                            id: zoneMenu
                            Repeater {
                                model: ["17K", "17L", "17M", "18K", "18L", "18M", "19K", "19L", "19M"]
                                MenuItem { required property string modelData; text: modelData
                                           onTriggered: { fieldZone.text = modelData; sheet.jump() } }
                            }
                        }
                    }
                    NumField { id: fieldZ; ok: sheet.zOk; Accessible.name: "Cota en metros sobre el nivel del mar"
                               onTextEdited: { sheet.altitudePatch = null; sheet.altitudeRequestId = "" }
                               rightPadding: editor.dp(70)
                               Text { anchors.right: parent.right; anchors.rightMargin: editor.dp(10); anchors.verticalCenter: parent.verticalCenter
                                      text: "m.s.n.m."; color: editor.inkMuted; font.pixelSize: editor.sp(13) } }
                }
                Row {
                    width: parent.width
                    spacing: editor.dp(10)
                    Rectangle {
                        width: parent.width
                        height: editor.dp(39); radius: editor.dp(12)
                        color: editor.dark ? "#30473E" : "#E7F5EA"
                        Text { anchors.centerIn: parent
                               text: editor.form && editor.form.elevationBusy ? "Consultando…" : "Obtener altitud"
                               color: editor.dark ? "#B6E5C6" : "#287342"; font.pixelSize: editor.sp(13) }
                        MouseArea { anchors.fill: parent
                                    enabled: !!editor.form && !editor.form.elevationBusy
                                    onClicked: editor.requestAltitudeAtCross() }
                    }
                }
                Text {
                    text: "REFERENCIA VIAL"; color: editor.inkMuted
                    font.pixelSize: editor.sp(11); font.weight: Font.DemiBold
                    topPadding: editor.dp(6)
                }
                Text { text: "Lado de la vía"; color: editor.inkMuted; font.pixelSize: editor.sp(12) }
                ComboBox {
                    id: fieldSide
                    width: parent.width
                    height: editor.dp(44)
                    model: editor.form ? editor.form.roadSideModel : ["-- Seleccione lado --"]
                    currentIndex: 0
                    font.pixelSize: editor.sp(14)
                    background: Rectangle {
                        radius: editor.dp(11); color: editor.dark ? "#35434D" : "#FFFFFF"
                        border.width: 1; border.color: editor.dark ? "#71818D" : "#D6DCE2"
                    }
                    contentItem: Text {
                        text: fieldSide.displayText; color: editor.ink
                        verticalAlignment: Text.AlignVCenter
                        leftPadding: editor.dp(12)
                        font.pixelSize: editor.sp(14); elide: Text.ElideRight
                    }
                }
                Row {
                    width: parent.width; spacing: editor.dp(12)
                    Column {
                        width: (parent.width - editor.dp(12)) / 2; spacing: editor.dp(6)
                        Text { text: "Progresiva (XX+XXX)"; color: editor.inkMuted; font.pixelSize: editor.sp(12) }
                        TextField {
                            id: fieldProgresiva
                            width: parent.width; height: editor.dp(44)
                            placeholderText: "00+000"
                            inputMethodHints: Qt.ImhDigitsOnly
                            color: editor.ink
                            font.pixelSize: editor.sp(14)
                            background: Rectangle {
                                radius: editor.dp(11)
                                color: editor.dark ? "#35434D" : "#FFFFFF"
                                border.width: 1
                                border.color: sheet.pkOk ? (editor.dark ? "#71818D" : "#D6DCE2") : "#CA4242"
                            }
                        }
                    }
                    Column {
                        width: (parent.width - editor.dp(12)) / 2; spacing: editor.dp(6)
                        Text { text: "Ubicación / Tramo"; color: editor.inkMuted; font.pixelSize: editor.sp(12) }
                        TextField {
                            id: fieldTramo; width: parent.width; height: editor.dp(44)
                            placeholderText: "Tramo"
                            color: editor.ink
                            font.pixelSize: editor.sp(14)
                            background: Rectangle {
                                radius: editor.dp(11)
                                color: editor.dark ? "#35434D" : "#FFFFFF"
                                border.width: 1; border.color: editor.dark ? "#71818D" : "#D6DCE2"
                            }
                        }
                    }
                }
                Text { width: parent.width; visible: !sheet.pkOk
                       text: "Progresiva: usa XX+XXX o XXX+XXX."
                       wrapMode: Text.WordWrap; color: "#C2414F"; font.pixelSize: editor.sp(12) }
                Text { width: parent.width; visible: sheet.altitudeStatus.length > 0
                       text: sheet.altitudeStatus; wrapMode: Text.WordWrap
                       color: editor.inkMuted; font.pixelSize: editor.sp(12) }
                Text {
                    width: parent.width
                    text: !sheet.zoneOk && fieldZone.text.trim().length ? "La zona debe incluir la banda, por ejemplo 18L."
                          : (fieldE.text.length && !sheet.eOk) ? "Este UTM: entre 100000 y 900000 m."
                          : (fieldN.text.length && !sheet.nOk) ? "Norte UTM: entre 0 y 10000000 m."
                          : !sheet.zOk ? "Cota: entre -12000 y 10000 m."
                          : ""
                    color: sheet.valid || (!fieldE.text.length && !fieldN.text.length) ? editor.inkMuted : "#C2414F"
                    font.pixelSize: editor.sp(12); wrapMode: Text.WordWrap
                }
            }
            } // Flickable content
        }

        // Referencia aprobada: Cancelar (vidrio) + Fijar ubicación (verde).
        // Ambos quedan al fondo, sin Dock horizontal encima; las herramientas
        // se despachan por la columna derecha del Dock global.
        Row {
            id: buttons
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.leftMargin: editor.dp(18)
            anchors.rightMargin: editor.dp(18)
            y: parent.height - height - editor.dp(26) - editor.keyboardInset
            height: editor.dp(58)
            spacing: editor.dp(12)
            Glass {
                id: cancelButton
                width: (buttons.width - buttons.spacing) / 2
                height: buttons.height
                radius: editor.dp(18)
                Text {
                    anchors.centerIn: parent
                    text: "Cancelar"
                    color: editor.ink
                    font.pixelSize: editor.sp(16)
                    font.weight: Font.DemiBold
                }
                MouseArea { anchors.fill: parent; onClicked: editor.close() }
                Accessible.role: Accessible.Button
                Accessible.name: "Cancelar, descartar cambios"
            }
            Rectangle {
                id: fixButton
                width: (buttons.width - buttons.spacing) / 2
                height: buttons.height
                radius: editor.dp(18)
                readonly property bool canFix: editor.sheetOpen
                    ? sheet.valid : isFinite(editor.crossPoint.lat)
                opacity: canFix ? 1 : 0.55
                color: "#238B47"
                Text {
                    anchors.centerIn: parent
                    text: "Fijar ubicación"
                    color: "white"
                    font.pixelSize: editor.sp(16)
                    font.weight: Font.DemiBold
                }
                MouseArea {
                    anchors.fill: parent
                    enabled: fixButton.canFix
                    onClicked: editor.fix()
                }
                Accessible.role: Accessible.Button
                Accessible.name: "Fijar ubicación"
            }
        }
    }

    // ------------------------------------------------------------ Edición / persistencia
    readonly property real keyboardInset: Qt.inputMethod.visible
        ? Math.min(Qt.inputMethod.keyboardRectangle.height, editor.height * 0.45) : 0
    function roadSideIndex() {
        var options = form ? (form.roadSideModel || []) : []
        var saved = form ? String(form.roadSideValue || "") : ""
        for (var i=1;i<options.length;++i)
            if (String(options[i])===saved || String(options[i])===saved+" (histórico)") return i
        return 0
    }
    function openManualSheet() {
        gpsMode = false
        if (!sheetOpen) sheet.loadFromCenter()
        sheetOpen = true
    }
    // Reuse existing Calicata Elevation backend without writing the document
    // before the single confirmation. Ignore stale responses on a moved point.
    function requestAltitudeAtCross() {
        var point=sheet.eOk && sheet.nOk && sheet.zoneOk
            ? Rules.utmToGeoForDatum(fieldE.text,fieldN.text,fieldZone.text,sheet.datum)
            : crossPoint
        if (!point) return
        var lat=point.latitude===undefined?point.lat:point.latitude
        var lon=point.longitude===undefined?point.lon:point.longitude
        if (!Elevation.validCoordinate(lat,lon)) return
        var id="map-elevation-"+Date.now()+"-"+Math.round(Math.random()*10000)
        sheet.altitudeRequestId=id
        sheet.altitudeStatus="Consultando elevación…"
        sheet.altitudePatch=null
        var body=Elevation.requestBody({}, {lat:lat,lon:lon},NaN,NaN)
        if (typeof CalicataCloud==="undefined" || !CalicataCloud
                || !CalicataCloud.resolveElevation(id,body)) {
            sheet.altitudeStatus="No se pudo consultar la elevación."
            sheet.altitudeRequestId=""
        }
    }
    Connections {
        target: typeof CalicataCloud !== "undefined" ? CalicataCloud : null
        ignoreUnknownSignals: true
        function onElevationResolved(requestId,result) {
            if (!editor.open || requestId!==sheet.altitudeRequestId) return
            sheet.altitudeRequestId=""
            var decision=Elevation.outcome(result, {}, "explicit", NaN, new Date().toISOString())
            if (decision.action==="apply") {
                sheet.altitudePatch=decision.patch
                fieldZ.text=decision.patch.utm_z
                sheet.altitudeStatus="Altitud obtenida · "+Elevation.sourceLabel(decision.patch)
                console.info("INGE_CALICATA_MAP_ELEVATION ok=1")
            } else {
                sheet.altitudeStatus=decision.message || "Revisa la elevación antes de fijarla."
                console.info("INGE_CALICATA_MAP_ELEVATION ok=0")
            }
        }
    }
    function useMyLocation() {
        sheetOpen=false
        gpsMode=true
        if (map) map.centerOnDeviceOrMarkers()
    }
    function fix() {
        if (!map || (sheetOpen && !sheet.valid)) return
        var manual=sheetOpen
        var fixData=gpsMode?map.deviceFix():null
        var altitude=fixData && typeof Perms!=="undefined" ? Number(Perms.nativeAltitude) : NaN
        var accuracy=fixData && typeof Perms!=="undefined" ? Number(Perms.nativeAccuracy) : NaN
        var sideOptions=form ? (form.roadSideModel || []) : []
        var index=fieldSide.currentIndex
        var side=index>0 && index<sideOptions.length ? String(sideOptions[index]).replace(" (histórico)","") : ""
        var draft={
            mode:manual?"manual":"point",
            latitude: crossPoint.lat, longitude:crossPoint.lon,
            altitude:altitude, accuracy:accuracy,
            source:fixData?"GPS del teléfono":"Punto fijado en mapa",
            easting:fieldE.text.trim(), northing:fieldN.text.trim(),
            zone:fieldZone.text.trim().toUpperCase(),
            elevation:fieldZ.text.trim(), datum:sheet.datum,
            altitudePatch:sheet.altitudePatch,
            roadSide:side,
            progresiva:Rules.normalizeProgresiva(fieldProgresiva.text),
            tramo:fieldTramo.text.trim()
        }
        console.info("INGE_CALICATA_MAP_COMMIT mode="+draft.mode+" road=1")
        commitAccepted=false
        commitLocation(draft)
        if (commitAccepted) close()
        else {
            sheet.altitudeStatus="No se guardó la ubicación. Revisa la ficha activa."
            openManualSheet()
            console.warn("INGE_CALICATA_MAP_COMMIT_FAILED")
        }
    }
    function runCommand(id) {
        if (!open) return
        console.info("INGE_CALICATA_MAP_TOOL action=" + id)
        if (id === "map.move") {
            sheetOpen = false
            gpsMode = false
        } else if (id === "map.coordinates") {
            openManualSheet()
        } else if (id === "map.gps") {
            useMyLocation()
        } else if (id === "map.center" && hasSaved && map) {
            sheetOpen = false
            gpsMode = false
            map.centerOn(savedPoint.lat, savedPoint.lon, Math.max(map.zoom, 14))
        }
    }
    Component.onDestruction: {
        _publishDock(false)
        _returnMap()
    }
}

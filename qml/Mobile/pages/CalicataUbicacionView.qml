import QtQuick
import InGe.CoreFlow 3.0 as CoreFlow
import "../lib/CalicataRules.js" as Rules

// Ficha de calicata · 2 · Ubicación (preview aprobado docs/previews/ubicacion_aprobado.webp).
// Cabecera con SOLO el nombre de la calicata; tarjeta de mapa (CalicatasTopoMap,
// sin otro motor) con el punto naranja, expandir y «Lat · Lon» + «Actualizar
// ubicación»; «Datos de ubicación»: cuatro INDICADORES (no editables) calculados
// con CalicataRules. Tocar el mapa, expandir o un indicador abre el mapa completo
// (CalicataMapEditor) con la transición Hero desde esta tarjeta.
Item {
    id: view
    property var form: null                      // CalicataFormPage (dp, sp, darkMode, flow, doc)
    property string title: ""
    property var header: ({})                    // doc.header
    property var point: ({ lat: NaN, lon: NaN })  // _locationPoint()

    property string iconFamily: lucide.status === FontLoader.Ready ? lucide.font.family : ""
    property url iconSource: "qrc:/InGe/Mobile/fonts/lucide/Lucide-w300.ttf"
    readonly property Item mapCard: mapCard
    // ÚNICO Map de la sección: CalicataMapEditor lo adopta al abrir y lo devuelve al cerrar.
    readonly property Item topoMap: cardMap
    function recenter() { _placeCamera() }
    // mode: "move" (mapa) | "coordinates" (hoja «Ingresar coordenadas») | "gps" (Actualizar ubicación)
    signal openMap(string mode)

    FontLoader { id: lucide; source: view.iconSource }
    function dp(v) { return form && form.dp ? form.dp(v) : v }
    function sp(v) { return form && form.sp ? form.sp(v) : v }
    readonly property bool dark: !!form && form.darkMode === true
    readonly property color cText: dark ? "#FFFFFF" : "#15202B"
    readonly property color cMuted: dark ? Qt.rgba(1, 1, 1, 0.62) : "#5B6672"
    readonly property color cCard: dark ? Qt.rgba(30 / 255, 38 / 255, 50 / 255, 0.92) : Qt.rgba(1, 1, 1, 0.94)
    readonly property color cBorder: dark ? Qt.rgba(1, 1, 1, 0.09) : Qt.rgba(21 / 255, 32 / 255, 43 / 255, 0.08)
    readonly property color cBlue: dark ? "#7DB3FF" : "#0A5BD3"
    readonly property bool hasPoint: isFinite(point.lat) && isFinite(point.lon)

    // ---------------------------------------------------------- Indicadores
    function _grouped(v, decimals) {
        var n = Number(v)
        if (!isFinite(n)) return "—"
        var parts = n.toFixed(decimals).split(".")
        return parts[0].replace(/\B(?=(\d{3})+(?!\d))/g, " ") + (parts.length > 1 ? "." + parts[1] : "")
    }
    readonly property var indicators: {
        var h = header || {}
        var e = Rules.parseDecimalSafe(h.utm_x), n = Rules.parseDecimalSafe(h.utm_y)
        var utmOk = Rules.validateDecimalRange(h.utm_x, 100000, 900000) && Rules.validateDecimalRange(h.utm_y, 0, 10000000)
        var zone = String(h.zona || h.utm_zone || "").trim()
        var zoneFull = /^(?:[1-9]|[1-5][0-9]|60)[C-HJ-NP-X]$/i.test(zone)
        var zoneNumber = /^(?:[1-9]|[1-5][0-9]|60)$/.test(zone)
        var zText = String(h.utm_z === undefined || h.utm_z === null ? "" : h.utm_z).trim()
        var zOk = zText.length > 0 && Rules.validateDecimalRange(h.utm_z, -12000, 10000)
        var datum = String(h.datum || "")
        var datumOk = datum === "WGS84" || datum === "PSAD56"
        return [
            { key: "utm", title: "Coordenadas UTM", glyph: 0xE1DA, subGlyph: 0xE529,
              value: utmOk ? "E " + _grouped(e, 3) + " · N " + _grouped(n, 3)
                           : (isFinite(e) || isFinite(n) ? "Revisa Este y Norte" : "—"),
              state: utmOk ? "ok" : "missing", chip: utmOk ? "Completo" : "Falta dato" },
            { key: "zone", title: "Zona UTM", glyph: 0xE529, subGlyph: 0xE111,
              value: zone.length ? zone.toUpperCase() : "—",
              state: zoneFull ? "ok" : (zoneNumber ? "band" : "missing"),
              chip: zoneFull ? "Completo" : (zoneNumber ? "Falta la banda" : "Falta dato") },
            { key: "z", title: "Cota / Z", glyph: 0xE231, subGlyph: 0xE231,
              value: zOk ? _grouped(Rules.parseDecimalSafe(h.utm_z), 1) + " m.s.n.m." : "—",
              state: zOk ? "ok" : "missing", chip: zOk ? "Completo" : "Falta dato" },
            { key: "datum", title: "Sistema geodésico", glyph: 0xE0E8, subGlyph: 0xE0AD,
              value: datumOk ? datum : "—",
              state: datumOk ? "ok" : "missing", chip: datumOk ? "Completo" : "Falta dato" }
        ]
    }
    // Tonos del preview: verde completo, rojo «Falta la banda», ámbar «Falta dato».
    function tone(state, kind) {
        var c = state === "ok" ? (dark ? ["#2E5A3C", "#7FD39A", "#1E3A28", "#9BE3B2"] : ["#E3F3E8", "#2F8F4E", "#DDF2E3", "#237A3F"])
              : state === "band" ? (dark ? ["#5A2E35", "#F09AA6", "#3E2228", "#FFB3BE"] : ["#FBE4E6", "#C2414F", "#FCE3E5", "#B12F3E"])
              : (dark ? ["#5A4A28", "#F2C46B", "#3D3220", "#FFD27A"] : ["#FBEFD9", "#C98A1B", "#FCEFD8", "#B87308"])
        return c[{ tile: 0, icon: 1, chip: 2, chipText: 3 }[kind]]
    }

    implicitHeight: column.implicitHeight
    Column {
        id: column
        width: parent.width
        spacing: view.dp(14)

        // Cabecera: SOLO el nombre de la calicata (sin alerta ni avatar).
        Text {
            width: parent.width
            text: view.title.length ? view.title : "Calicata"
            color: view.cText
            font.pixelSize: view.sp(24)
            font.weight: Font.DemiBold
            elide: Text.ElideRight
            Accessible.role: Accessible.Heading
        }

        // ---- Tarjeta de mapa ----
        Rectangle {
            id: mapCard
            width: parent.width
            height: view.dp(232)
            radius: view.dp(20)
            color: view.cCard
            border.width: 1
            border.color: view.cBorder
            Item {
                id: mapFrame
                x: view.dp(6); y: view.dp(6)
                width: parent.width - view.dp(12)
                height: view.dp(172)
                CalicatasTopoMap {
                    id: cardMap
                    anchors.fill: parent          // también dentro del editor (reparentado)
                    z: -1                         // al volver queda bajo el marco, el punto y el toque
                    ui: QtObject {
                        readonly property real u: view.dp(1)
                        readonly property real topInset: 0
                        readonly property string fontFamily: ""
                    }
                    flow: view.form && view.form.flow ? view.form.flow : CoreFlow.InGeCoreFlow
                    controlsVisible: false
                    // Activo mientras se ve (en la tarjeta o en el editor): sin alternar por el Hero.
                    active: !!view.form && !!view.form.doc
                            && (view.form.stageIndex === 1 || view.form.ubicacionMapOpen)
                    Component.onCompleted: view._placeCamera()
                }
                // Esquinas redondeadas sin capa: anillo del color de la tarjeta.
                Rectangle {
                    anchors.fill: parent
                    anchors.margins: -view.dp(6)
                    radius: view.dp(20)
                    color: "transparent"
                    border.width: view.dp(6)
                    border.color: view.cCard
                }
                Rectangle {                          // punto de la calicata
                    visible: view.hasPoint
                    width: view.dp(20); height: width; radius: width / 2
                    x: parent.width / 2 - width / 2; y: parent.height / 2 - height / 2
                    color: "#F39A1E"
                    border.width: view.dp(3); border.color: "white"
                }
                Text {
                    visible: !view.hasPoint
                    anchors.centerIn: parent
                    text: "Sin ubicación todavía"
                    color: "#3B4652"; font.pixelSize: view.sp(13); font.weight: Font.DemiBold
                }
                Rectangle {                          // expandir
                    anchors.right: parent.right; anchors.bottom: parent.bottom
                    anchors.margins: view.dp(10)
                    width: view.dp(40); height: width; radius: width / 2
                    color: Qt.rgba(1, 1, 1, 0.92)
                    border.width: 1; border.color: Qt.rgba(0, 0, 0, 0.06)
                    Text { anchors.centerIn: parent; text: String.fromCharCode(0xE113); font.family: view.iconFamily
                           font.pixelSize: view.dp(18); color: "#1F2A36" }
                    Accessible.role: Accessible.Button
                    Accessible.name: "Abrir el mapa a pantalla completa"
                }
                MouseArea {                          // tocar el mapa o expandir: mapa completo (Hero)
                    anchors.fill: parent
                    onClicked: view.openMap("move")
                }
            }
            Item {
                anchors.left: parent.left; anchors.right: parent.right; anchors.bottom: parent.bottom
                anchors.leftMargin: view.dp(16); anchors.rightMargin: view.dp(10)
                height: view.dp(54)
                Text {
                    anchors.left: parent.left; anchors.right: updateChip.left; anchors.rightMargin: view.dp(8)
                    anchors.verticalCenter: parent.verticalCenter
                    text: view.hasPoint ? "Lat " + view.point.lat.toFixed(6) + " · Lon " + view.point.lon.toFixed(6) : "Sin coordenadas"
                    color: view.cMuted; font.pixelSize: view.sp(12.5)
                    fontSizeMode: Text.HorizontalFit; minimumPixelSize: 10
                    elide: Text.ElideRight
                }
                Rectangle {
                    id: updateChip
                    anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                    width: chipRow.implicitWidth + view.dp(18); height: view.dp(32); radius: height / 2
                    color: updateTap.pressed ? (view.dark ? Qt.rgba(1, 1, 1, 0.14) : "#E8F0FC")
                                             : (view.dark ? Qt.rgba(1, 1, 1, 0.08) : "#FFFFFF")
                    border.width: 1; border.color: view.dark ? Qt.rgba(1, 1, 1, 0.12) : Qt.rgba(10 / 255, 91 / 255, 211 / 255, 0.18)
                    Row {
                        id: chipRow
                        anchors.centerIn: parent; spacing: view.dp(6)
                        Text { anchors.verticalCenter: parent.verticalCenter; text: String.fromCharCode(0xE111)
                               font.family: view.iconFamily; font.pixelSize: view.dp(15); color: view.cBlue }
                        Text { anchors.verticalCenter: parent.verticalCenter
                               text: view.hasPoint ? "Actualizar ubicación" : "Obtener ubicación"
                               color: view.cBlue; font.pixelSize: view.sp(12); font.weight: Font.DemiBold }
                    }
                    MouseArea { id: updateTap; anchors.fill: parent; onClicked: view.openMap("gps") }
                    Accessible.role: Accessible.Button
                    Accessible.name: view.hasPoint ? "Actualizar ubicación" : "Obtener ubicación"
                }
            }
        }

        // Read-only road summary. The whole card opens the FULLSCREEN editor;
        // there are no text fields or pickers in the closed location section.
        Rectangle {
            width: parent.width; height: view.dp(54); radius: view.dp(14)
            color: view.cCard; border.width: 1; border.color: view.cBorder
            readonly property var h: view.header || ({})
            readonly property string side: String(h.location || h.lado_via || "").trim()
            readonly property string pk: String(h.progresiva || h.pk || "").trim()
            readonly property string tramo: String(h.ubicacion || h.tramo || "").trim()
            Text {
                anchors.left: parent.left; anchors.leftMargin: view.dp(14)
                anchors.right: parent.right; anchors.rightMargin: view.dp(14)
                anchors.verticalCenter: parent.verticalCenter
                text: parent.side.length || parent.pk.length || parent.tramo.length
                      ? "Referencia vial · " + [parent.side,parent.pk,parent.tramo].filter(function(v){return v.length}).join(" · ")
                      : "Sin referencia vial"
                color: view.cMuted; elide: Text.ElideRight
                font.pixelSize: view.sp(13)
            }
            MouseArea { anchors.fill: parent; onClicked: view.openMap("coordinates") }
        }

        // ---- Datos de ubicación: solo indicadores ----
        Text {
            topPadding: view.dp(4)
            text: "Datos de ubicación"
            color: view.cText
            font.pixelSize: view.sp(18); font.weight: Font.DemiBold
        }
        Repeater {
            model: view.indicators
            delegate: Rectangle {
                id: ind
                required property var modelData
                width: column.width
                height: view.dp(76)
                radius: view.dp(16)
                color: indTap.pressed ? (view.dark ? Qt.rgba(1, 1, 1, 0.10) : "#F2F5F8") : view.cCard
                border.width: 1; border.color: view.cBorder
                scale: indTap.pressed ? 0.985 : 1
                Behavior on scale { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
                Rectangle {
                    id: indTile
                    x: view.dp(12); anchors.verticalCenter: parent.verticalCenter
                    width: view.dp(52); height: width; radius: view.dp(14)
                    color: view.tone(ind.modelData.state, "tile")
                    Text { anchors.centerIn: parent; text: String.fromCharCode(ind.modelData.glyph); font.family: view.iconFamily
                           font.pixelSize: view.dp(26); color: view.tone(ind.modelData.state, "icon") }
                }
                Column {
                    anchors.left: indTile.right; anchors.leftMargin: view.dp(14)
                    anchors.right: indChip.left; anchors.rightMargin: view.dp(8)
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: view.dp(5)
                    Text { width: parent.width; text: ind.modelData.title; color: view.cText
                           font.pixelSize: view.sp(15); font.weight: Font.DemiBold; elide: Text.ElideRight }
                    Row {
                        spacing: view.dp(8)
                        Text { anchors.verticalCenter: parent.verticalCenter; text: String.fromCharCode(ind.modelData.subGlyph)
                               font.family: view.iconFamily; font.pixelSize: view.dp(15); color: view.cMuted }
                        Text { anchors.verticalCenter: parent.verticalCenter; text: ind.modelData.value
                               color: view.cMuted; font.pixelSize: view.sp(13) }
                    }
                }
                Rectangle {
                    id: indChip
                    anchors.right: parent.right; anchors.rightMargin: view.dp(12)
                    y: view.dp(14)
                    width: chipText.implicitWidth + view.dp(18); height: view.dp(24); radius: view.dp(8)
                    color: view.tone(ind.modelData.state, "chip")
                    Text { id: chipText; anchors.centerIn: parent; text: ind.modelData.chip
                           color: view.tone(ind.modelData.state, "chipText"); font.pixelSize: view.sp(11.5); font.weight: Font.Medium }
                }
                MouseArea { id: indTap; anchors.fill: parent; onClicked: view.openMap("coordinates") }
                Accessible.role: Accessible.Button
                Accessible.name: ind.modelData.title + ": " + ind.modelData.value + ". " + ind.modelData.chip
            }
        }
    }

    // Camera initialization/explicit recenter only: doc hydration and
    // autosave emit new point objects, but must NOT fight pan/zoom gestures.
    property string _cameraDocKey: ""
    function _placeCamera() {
        if (view.form && view.form.ubicacionMapOpen) return
        if (hasPoint) cardMap.setCamera(point.lat, point.lon, 14)
        else cardMap.setCamera(-12.05, -77.04, 5)
    }
    function initializeCamera(docKey) {
        var key=String(docKey || "")
        if (key === _cameraDocKey) return
        _cameraDocKey=key
        if (view.form && view.form.stageIndex === 1) _placeCamera()
    }
    onHasPointChanged: {
        if (view.form && view.form.stageIndex === 1 && !view.form.ubicacionMapOpen)
            _placeCamera()
    }
}

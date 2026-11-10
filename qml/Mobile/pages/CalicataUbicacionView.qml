import QtQuick
import QtQuick.Effects
import InGe.CoreFlow 3.0 as CoreFlow
import "../lib/CalicataRules.js" as Rules
import "../components" as Components

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

    // Estado por caja: "ok" (verde) | "partial" (amarillo) | "empty" (rojo). Lo calcula la ficha.
    property var idStatus: ["empty", "empty", "empty", "empty"]
    signal openName()
    signal openFolder()
    signal openMachine()
    signal openLogos()
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
    readonly property color cText: dark ? "#FFFFFF" : "#0B0B0B"
    readonly property color cMuted: dark ? Qt.rgba(1, 1, 1, 0.62) : "#5B6672"
    readonly property color cCard: dark ? Qt.rgba(30 / 255, 38 / 255, 50 / 255, 0.92) : Qt.rgba(1, 1, 1, 0.94)
    readonly property color cBorder: dark ? Qt.rgba(1, 1, 1, 0.09) : Qt.rgba(21 / 255, 32 / 255, 43 / 255, 0.08)
    readonly property color cBlue: dark ? "#7DB3FF" : "#0A5BD3"
    readonly property bool hasPoint: isFinite(point.lat) && isFinite(point.lon)

    function _g(v, d) {
        var raw = String(v === undefined || v === null ? "" : v).trim()
        var n = Number(raw.replace(",", "."))
        if (!raw.length || !isFinite(n)) return "-"
        var p = n.toFixed(d).split(".")
        return p[0].replace(/\B(?=(\d{3})+(?!\d))/g, " ") + (p.length > 1 ? "." + p[1] : "")
    }
    function _t(v) { var s = String(v === undefined || v === null ? "" : v).trim(); return s.length ? s : "-" }
    readonly property string utmText: {
        var h = header || {}
        var d = String(h.datum || "").trim(), z = String(h.zona || h.utm_zone || "").trim()
        return d.length || z.length ? (d.length ? d : "-") + " - " + (z.length ? z.toUpperCase() : "-") : "-"
    }
    readonly property var details: {
        var h = header || {}
        var f = form || {}
        return [
            { big: "UTM", small: utmText, ico: 57576 },
            { big: _g(h.utm_z, 0), small: "m.s.n.m", ico: 57905 },
            { big: _t(f.derivedDepthText), small: "Cota", ico: 58978 },
            { big: _g(h.utm_y, 2), small: "Coordenada N", ico: 57516 },
            { big: _g(h.utm_x, 2), small: "Coordenada E", ico: 57516 },
            { big: _t(f.effectiveGroundwaterText), small: "Nivel freático", ico: 57524 }
        ]
    }

    // Medidas proporcionales al ancho del contenido (preview de referencia: 562 px).
    readonly property real w: width
    FontLoader { id: figRegular; source: "qrc:/InGe/Mobile/fonts/Figtree-Regular.ttf" }
    FontLoader { id: figMedium; source: "qrc:/InGe/Mobile/fonts/Figtree-Medium.ttf" }
    FontLoader { id: figBold; source: "qrc:/InGe/Mobile/fonts/Figtree-Bold.ttf" }
    readonly property string fig: figRegular.status === FontLoader.Ready ? figRegular.name : ""

    component IdBox: Rectangle {
        id: box
        property int glyph: 0
        property string label: ""
        signal activated()
        width: view.w * 0.206
        height: width
        radius: width * 0.33
        property string status: "empty"
        readonly property color glowColor: status === "ok" ? "#2FD06B" : status === "partial" ? "#FFC21A" : "#FF4D4D"
        // Aura de estado (verde: rellenado · amarillo: falta · rojo: vacío), pulsante.
        Rectangle {
            id: glowOuter
            z: -1
            anchors.fill: parent
            anchors.margins: -view.dp(5)
            radius: parent.radius + view.dp(5)
            color: Qt.rgba(box.glowColor.r, box.glowColor.g, box.glowColor.b, 0.22)
            border.width: view.dp(2)
            border.color: Qt.rgba(box.glowColor.r, box.glowColor.g, box.glowColor.b, 0.55)
        }
        Rectangle {
            z: -1
            anchors.fill: parent
            anchors.margins: -view.dp(2)
            radius: parent.radius + view.dp(2)
            color: "transparent"
            border.width: view.dp(2.5)
            border.color: box.glowColor
        }
        SequentialAnimation {
            running: !!view.form && view.form.flow ? view.form.flow.motionAllowed !== false : true
            loops: Animation.Infinite
            NumberAnimation { target: glowOuter; property: "opacity"; from: 0.45; to: 1; duration: box.status === "empty" ? 1100 : box.status === "partial" ? 1500 : 2200; easing.type: Easing.InOutSine }
            NumberAnimation { target: glowOuter; property: "opacity"; from: 1; to: 0.45; duration: box.status === "empty" ? 1100 : box.status === "partial" ? 1500 : 2200; easing.type: Easing.InOutSine }
        }
        color: tap.pressed ? (view.dark ? Qt.rgba(1, 1, 1, 0.16) : "#EBEBEB") : (view.dark ? Qt.rgba(1, 1, 1, 0.08) : "#F4F4F4")
        scale: tap.pressed ? 0.93 : 1
        Behavior on scale { NumberAnimation { duration: 140; easing.type: Easing.OutBack } }
        Text {
            anchors.centerIn: parent
            text: String.fromCharCode(box.glyph)
            font.family: view.iconFamily
            font.pixelSize: Math.round(box.width * 0.45)
            color: view.cText
        }
        MouseArea { id: tap; anchors.fill: parent; onClicked: box.activated() }
        Accessible.role: Accessible.Button
        Accessible.name: box.label
    }

    implicitHeight: column.implicitHeight
    Column {
        id: column
        width: parent.width
        spacing: 0

        // ---- Preview satelital con «Identidad» encima (sin cabecera aparte) ----
        Item {
            id: mapCard
            width: parent.width
            height: Math.round(view.w * 0.94)
            Item {
                id: mapFrame
                anchors.fill: parent
                layer.enabled: !(view.form && view.form.ubicacionMapOpen)
                layer.effect: MultiEffect { maskEnabled: true; maskSource: cardMask }
                CalicatasTopoMap {
                    id: cardMap
                    anchors.fill: parent
                    z: -1
                    mapType: "satellite"
                    ui: QtObject {
                        readonly property real u: view.dp(1)
                        readonly property real topInset: 0
                        readonly property string fontFamily: ""
                    }
                    flow: view.form && view.form.flow ? view.form.flow : CoreFlow.InGeCoreFlow
                    controlsVisible: false
                    active: !!view.form && !!view.form.doc
                            && (view.form.stageIndex === 1 || view.form.ubicacionMapOpen)
                    Component.onCompleted: view._placeCamera()
                }
                Rectangle {
                    anchors.left: parent.left; anchors.right: parent.right; anchors.bottom: parent.bottom
                    height: parent.height * 0.42
                    gradient: Gradient {
                        GradientStop { position: 0; color: "transparent" }
                        GradientStop { position: 0.75; color: Qt.rgba(0, 0, 0, 0.78) }
                        GradientStop { position: 1; color: Qt.rgba(0, 0, 0, 0.92) }
                    }
                }
                Text {
                    visible: !view.hasPoint
                    anchors.centerIn: parent
                    text: "Sin ubicación todavía"
                    color: "white"; font.family: view.fig; font.pixelSize: view.sp(13); font.weight: Font.DemiBold
                }
                Text {
                    x: view.w * 0.043; y: view.w * 0.035
                    text: "Identidad"
                    color: "white"; font.family: view.fig; font.pixelSize: Math.round(view.w * 0.062); font.weight: Font.Bold
                    style: Text.Outline; styleColor: Qt.rgba(0, 0, 0, 0.3)
                    Accessible.role: Accessible.Heading
                }
                Column {
                    x: view.w * 0.075
                    width: parent.width - view.w * 0.1
                    anchors.bottom: parent.bottom
                    anchors.bottomMargin: view.w * 0.062
                    spacing: view.w * 0.008
                    Text {
                        width: parent.width
                        text: view.title.length ? view.title : "Calicata"
                        color: "white"; font.family: view.fig; font.pixelSize: Math.round(view.w * 0.053); font.weight: Font.Bold
                        elide: Text.ElideRight
                    }
                    Text {
                        width: parent.width
                        text: "UTM " + view.utmText + "   E " + view._g((view.header || {}).utm_x, 2) + " m   N " + view._g((view.header || {}).utm_y, 2) + " m"
                        color: "white"; font.family: view.fig; font.pixelSize: Math.round(view.w * 0.0325)
                        elide: Text.ElideRight
                    }
                }
                MouseArea { anchors.fill: parent; onClicked: view.openMap("move") }
            }
            Item {
                id: cardMask
                anchors.fill: parent
                visible: false
                layer.enabled: true
                Rectangle { anchors.fill: parent; radius: view.w * 0.1; color: "black" }
            }
        }

        Item { width: 1; height: view.w * 0.1 }
        // ---- General: 4 cajas ----
        Text { text: "General"; color: view.cText; font.family: view.fig; font.pixelSize: Math.round(view.w * 0.058); font.weight: Font.Bold; leftPadding: view.w * 0.043 }
        Item { width: 1; height: view.w * 0.04 }
        Row {
            spacing: view.w * 0.034
            leftPadding: view.w * 0.045
            IdBox { status: view.idStatus[0]; glyph: 57759; label: "Código y nombre del proyecto"; onActivated: view.openName() }
            IdBox { status: view.idStatus[1]; glyph: 57500; label: "Carpeta del proyecto"; onActivated: view.openFolder() }
            IdBox { status: view.idStatus[2]; glyph: 58628; label: "Maquinaria"; onActivated: view.openMachine() }
            IdBox { status: view.idStatus[3]; glyph: 57590; label: "Logos"; onActivated: view.openLogos() }
        }

        Item { width: 1; height: view.w * 0.085 }
        // ---- Detalles ----
        Text { text: "Detalles"; color: view.cText; font.family: view.fig; font.pixelSize: Math.round(view.w * 0.058); font.weight: Font.Bold; leftPadding: view.w * 0.043 }
        Item { width: 1; height: view.w * 0.04 }
        Grid {
            columns: 3
            columnSpacing: 0; rowSpacing: view.w * 0.06
            leftPadding: view.w * 0.047
            Repeater {
                model: view.details
                delegate: Column {
                    id: cell
                    width: view.w * 0.33
                    spacing: view.w * 0.004
                    Row {
                        spacing: view.w * 0.012
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: String.fromCharCode(modelData.ico)
                            font.family: view.iconFamily; font.pixelSize: Math.round(view.w * 0.064)
                            color: view.cText
                        }
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: modelData.big
                            width: Math.min(implicitWidth, cell.width - view.w * 0.1)
                            elide: Text.ElideRight
                            color: view.cText; font.family: view.fig; font.pixelSize: Math.round(view.w * 0.043); font.weight: Font.Bold
                        }
                    }
                    Text { text: modelData.small; width: cell.width - view.w * 0.02; elide: Text.ElideRight
                           color: view.cText; font.family: view.fig; font.pixelSize: Math.round(view.w * 0.032) }
                }
            }
        }
        Item { width: 1; height: view.w * 0.05 }
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

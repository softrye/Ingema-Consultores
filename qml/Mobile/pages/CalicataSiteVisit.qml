import QtQuick
import QtQuick.Shapes
import QtQuick.Effects
import InGe 1.0                                   // singleton CalicataCloud (foto del lugar)
import ".." as Mobile                             // DockGlassPanel (vidrio del Dock)
import "../components" as Components
import "../renditions/RStyle.js" as S

// Visita de campo: pantalla de entrada al abrir una calicata. Sólo presenta el
// avance real de CalicataFormPage.siteVisitSnapshot() (mismo validador que
// Revisión) y abre las secciones existentes del formulario; no edita datos.
Item {
    id: visit
    property var ui
    property var flow
    property var editor                           // CalicatasEditorPage
    property var snapshot: null                   // { code, project, percent, sections[] }
    readonly property real u: ui ? ui.u : 1
    readonly property bool dark: editor ? editor.darkMode === true : S.dark
    readonly property string fontFamily: ui ? ui.fontFamily : ""
    signal openSection(int section)
    signal back()

    // Con la foto del lugar: velo oscuro y vidrio verde de Calicatas, textos claros.
    readonly property bool onPhoto: photoUrl.length > 0 && sitePhoto.status === Image.Ready
    readonly property bool light: dark || onPhoto
    // Paleta corporativa (RStyle): navyDark/navy/corporateBlue/corporateGreen.
    readonly property color ink: light ? "#F2F4F8" : S.navyDark
    readonly property color muted: onPhoto ? Qt.rgba(1, 1, 1, 0.78) : dark ? "#A3A9B6" : "#7A8299"
    readonly property color accent: light ? "#6E9A42" : "#0654A2"
    readonly property color green: light ? "#6E9A42" : "#486426"
    readonly property color track: light ? Qt.rgba(1, 1, 1, 0.12) : "#E3E8F0"
    readonly property color stripe: light ? Qt.rgba(1, 1, 1, 0.22) : Qt.rgba(21 / 255, 26 / 255, 48 / 255, 0.16)
    readonly property color panel: "transparent"                  // la superficie la da el vidrio del Dock
    readonly property color tile: "transparent"
    readonly property color edge: "transparent"

    readonly property int percent: snapshot ? Math.max(0, Math.min(100, snapshot.percent)) : 0
    // Los tres accesos se pintan desde el primer cuadro (ícono y título fijos); el
    // avance real llega con el resumen del formulario y sólo cambia estado y anillo.
    readonly property var sectionDefaults: [{ key: "identity", label: "Identidad", section: 1 },
                                            { key: "lab", label: "Laboratorio y estratos", section: 4 },
                                            { key: "photos", label: "Fotos y resumen", section: 7 }]
    readonly property var sections: {
        var real = snapshot && snapshot.sections ? snapshot.sections : []
        var out = []
        for (var i = 0; i < sectionDefaults.length; ++i) {
            var d = sectionDefaults[i], r = null
            for (var j = 0; j < real.length; ++j) if (real[j].key === d.key) r = real[j]
            out.push({ key: d.key, label: d.label, section: r ? r.section : d.section,
                       percent: r ? Math.max(0, Math.min(100, Number(r.percent) || 0)) : 0,
                       status: r ? String(r.status) : "loading" })
        }
        return out
    }
    // El primer acceso no completado es el siguiente paso: se resalta en verde.
    readonly property string nextKey: {
        if (!snapshot) return ""
        for (var i = 0; i < sections.length; ++i) if (sections[i].status !== "complete") return sections[i].key
        return ""
    }
    function statusText(status) {
        return status === "complete" ? "Completado" : status === "progress" ? "En proceso"
             : status === "loading" ? "Calculando…" : "Pendiente"
    }
    function iconFor(key) {
        return key === "identity" ? "profile.user" : key === "lab" ? "lab.flask" : "action.camera"
    }

    readonly property real gutter: 22 * u
    readonly property real topPad: (ui ? ui.topInset : 0) + 14 * u
    readonly property real bottomPad: (photoUrl.length ? 46 : 28) * u

    // Foto real del lugar (Wikimedia Commons por coordenadas WGS84, caché por calicata).
    property string photoUrl: ""
    property string photoCredit: ""
    property string _photoKey: ""
    // También al crearse: onSnapshotChanged no se emite para el valor inicial
    // del Loader, y la foto nunca se pedía si el resumen ya estaba listo.
    Component.onCompleted: requestPhoto()
    onSnapshotChanged: requestPhoto()
    function requestPhoto() {
        var s = visit.snapshot
        if (!s || !String(s.key || "").length || !isFinite(s.latitude) || !isFinite(s.longitude)) return
        if (visit._photoKey === s.key + "@" + s.latitude.toFixed(3) + "," + s.longitude.toFixed(3)) return
        visit._photoKey = s.key + "@" + s.latitude.toFixed(3) + "," + s.longitude.toFixed(3)
        if (typeof CalicataCloud !== "undefined" && CalicataCloud.requestSitePhoto)
            CalicataCloud.requestSitePhoto(String(s.key), s.latitude, s.longitude)
    }
    Connections {
        target: typeof CalicataCloud !== "undefined" ? CalicataCloud : null
        ignoreUnknownSignals: true
        function onSitePhotoReady(key, url, credit) {
            if (!visit.snapshot || key !== String(visit.snapshot.key || "")) return
            visit.photoUrl = url
            visit.photoCredit = credit
        }
    }

    Item {                                        // fondo: color + foto + velo (lo muestrea el vidrio)
        id: backdrop
        anchors.fill: parent
    Rectangle { anchors.fill: parent; color: visit.editor ? visit.editor.calBgColor() : (visit.dark ? "#0A0A0A" : "#FFFFFF") }
    Image {                                       // sin foto o sin red: queda el fondo actual
        id: sitePhoto
        anchors.fill: parent
        source: visit.photoUrl
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        cache: false
        sourceSize.width: Math.max(1, visit.width)     // decodifica al tamaño de pantalla (tier LOW)
        opacity: status === Image.Ready ? 1 : 0
        visible: opacity > 0.01
        Behavior on opacity {
            enabled: !!visit.flow && !visit.flow.reduceMotion
            NumberAnimation { duration: 250; easing.type: Easing.OutCubic }   // la captura del vidrio sigue el fundido
        }
    }
    // Foto como fondo de pantalla (claro y oscuro igual): sin velo uniforme, sólo
    // degradados oscuros suaves arriba (título, Atrás) y abajo (crédito); el centro
    // queda nítido. La legibilidad de las tarjetas la da el vidrio verde.
    Rectangle {
        anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top
        height: Math.min(parent.height * 0.38, visit.topPad + 260 * visit.u)
        visible: sitePhoto.visible
        opacity: sitePhoto.opacity
        gradient: Gradient {
            GradientStop { position: 0.0; color: Qt.rgba(0, 0, 0, 0.45) }
            GradientStop { position: 0.6; color: Qt.rgba(0, 0, 0, 0.22) }
            GradientStop { position: 1.0; color: Qt.rgba(0, 0, 0, 0) }
        }
    }
    Rectangle {
        anchors.left: parent.left; anchors.right: parent.right; anchors.bottom: parent.bottom
        height: 120 * visit.u
        visible: sitePhoto.visible
        opacity: sitePhoto.opacity
        gradient: Gradient {
            GradientStop { position: 0.0; color: Qt.rgba(0, 0, 0, 0) }
            GradientStop { position: 1.0; color: Qt.rgba(0, 0, 0, 0.40) }
        }
    }
    }
    ShaderEffectSource {
        id: backdropCapture
        sourceItem: backdrop
        hideSource: false
        visible: false
        smooth: true
        live: true                                // fondo base desde el primer cuadro; la foto entra sola
    }
    QtObject {
        id: glassHost
        readonly property Item backdrop: backdrop
        readonly property var glassTexture: backdropCapture
        readonly property bool glassReady: true
        property int glassTick: 0
    }
    // Tarjetas: EXACTAMENTE el vidrio del Dock (DockGlassPanel, preset único y
    // dockGlassTint), visible desde el primer cuadro sobre lo que haya detrás.
    readonly property color dockTint: ui && ui.dockGlassTint !== undefined ? ui.dockGlassTint : Qt.rgba(0, 0, 0, 0)
    readonly property color outline: ui && ui.dockGlyphOutline !== undefined ? ui.dockGlyphOutline : Qt.rgba(21 / 255, 26 / 255, 48 / 255, 0.95)
    MouseArea { anchors.fill: parent }           // el formulario de abajo no recibe toques

    Flickable {
        id: flick
        anchors.fill: parent
        contentHeight: Math.max(height, body.y + body.height + visit.bottomPad)
        onContentYChanged: glassHost.glassTick++
        boundsBehavior: Flickable.StopAtBounds
        clip: true

        Column {
            id: body
            x: visit.gutter
            y: visit.topPad
            width: parent.width - 2 * visit.gutter
            spacing: 26 * visit.u

            Column {                                // cabecera + avance (altura natural)
                id: head
                width: parent.width
                spacing: 24 * visit.u

                Rectangle {                         // Atrás (sin botones a la derecha)
                    width: 52 * visit.u; height: width; radius: width / 2
                    color: backTap.pressed ? Qt.rgba(1, 1, 1, 0.12) : visit.tile
                    border.color: visit.edge
                    Mobile.DockGlassPanel { glassUi: glassHost; radius: parent.radius; u: visit.u; tint: visit.dockTint }
                    Components.FlowIcon {
                        anchors.centerIn: parent
                        width: 24 * visit.u; height: width; name: "nav.back"; flow: visit.flow; onDark: visit.light
                        tintColor: visit.ink; activeTintColor: visit.ink; inactiveOpacity: 1
                    }
                    MouseArea { id: backTap; anchors.fill: parent; onClicked: visit.back() }
                    Accessible.role: Accessible.Button
                    Accessible.name: "Volver a Calicatas"
                }

                Text {
                    width: parent.width
                    text: "Visita de campo"
                    color: visit.onPhoto ? "#FFFFFF" : visit.ink
                    layer.enabled: visit.onPhoto            // blanco con sombra suave sobre la foto
                    layer.effect: MultiEffect { shadowEnabled: true; shadowColor: Qt.rgba(0, 0, 0, 0.55); shadowBlur: 0.5; shadowVerticalOffset: 1; shadowHorizontalOffset: 0 }
                    font.family: visit.fontFamily; font.pixelSize: 36 * visit.u; font.weight: Font.Bold
                }

                Row {                               // calicata + proyecto
                    width: parent.width
                    spacing: 16 * visit.u
                    Rectangle {
                        width: 64 * visit.u; height: width; radius: 20 * visit.u
                        color: visit.tile; border.color: visit.edge
                        anchors.verticalCenter: parent.verticalCenter
                        Mobile.DockGlassPanel { glassUi: glassHost; radius: parent.radius; u: visit.u; tint: visit.dockTint }
                        Components.FlowIcon {
                            anchors.centerIn: parent
                            width: 30 * visit.u; height: width; name: "map.location"; flow: visit.flow; onDark: visit.light
                            tintColor: visit.accent; activeTintColor: visit.accent; inactiveOpacity: 1
                        }
                    }
                    Column {
                        width: parent.width - 80 * visit.u
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 4 * visit.u
                        layer.enabled: visit.onPhoto            // blanco con sombra suave sobre la foto
                        layer.effect: MultiEffect { shadowEnabled: true; shadowColor: Qt.rgba(0, 0, 0, 0.55); shadowBlur: 0.5; shadowVerticalOffset: 1; shadowHorizontalOffset: 0 }
                        Text {
                            width: parent.width; elide: Text.ElideRight
                            text: visit.snapshot && visit.snapshot.code.length ? "Calicata " + visit.snapshot.code : "Calicata sin código"
                            color: visit.onPhoto ? "#FFFFFF" : visit.ink
                            font.family: visit.fontFamily; font.pixelSize: 25 * visit.u; font.weight: Font.DemiBold
                        }
                        Text {
                            width: parent.width; elide: Text.ElideRight
                            text: visit.snapshot && visit.snapshot.project.length ? visit.snapshot.project : "Sin proyecto"
                            color: visit.onPhoto ? Qt.rgba(1, 1, 1, 0.92) : visit.muted
                            font.family: visit.fontFamily; font.pixelSize: 17 * visit.u
                        }
                    }
                }

                Rectangle {                         // avance real de la calicata
                    width: parent.width
                    height: progressCol.height + 44 * visit.u
                    radius: 26 * visit.u
                    color: visit.panel; border.color: visit.edge
                    Mobile.DockGlassPanel { glassUi: glassHost; radius: parent.radius; u: visit.u; tint: visit.dockTint }
                    Column {
                        id: progressCol
                        x: 22 * visit.u; y: 22 * visit.u
                        width: parent.width - 44 * visit.u
                        spacing: 16 * visit.u
                        Text {
                            text: "Avance de la calicata"
                            color: visit.ink
                            style: visit.light ? Text.Outline : Text.Normal; styleColor: visit.outline   // contorno del Dock
                            font.family: visit.fontFamily; font.pixelSize: 20 * visit.u; font.weight: Font.DemiBold
                        }
                        Item {                      // barra: tramo hecho + tramo pendiente rayado
                            id: bar
                            width: parent.width; height: 28 * visit.u
                            readonly property real doneWidth: width * visit.percent / 100
                            Rectangle {
                                anchors.fill: parent; radius: height / 2
                                color: visit.track
                                clip: true
                                Item {
                                    x: bar.doneWidth; width: parent.width - x; height: parent.height
                                    clip: true
                                    Repeater {
                                        // Con ancho aún 0 la columna es negativa (-88 u): ceil(-8,8) + 4 = -4.
                                        model: Math.max(0, Math.ceil(bar.width / (10 * visit.u)) + 4)
                                        Rectangle {
                                            required property int index
                                            x: index * 10 * visit.u - bar.height
                                            y: -bar.height / 2
                                            width: 4 * visit.u; height: bar.height * 2
                                            rotation: 35
                                            color: visit.stripe
                                        }
                                    }
                                }
                            }
                            Rectangle {
                                width: Math.max(height, bar.doneWidth)
                                visible: visit.percent > 0
                                height: parent.height; radius: height / 2
                                color: visit.accent
                                Behavior on width {
                                    enabled: !!visit.flow && !visit.flow.reduceMotion
                                    NumberAnimation { duration: visit.flow ? visit.flow.durationTokens.slow : 270; easing.type: Easing.OutCubic }
                                }
                            }
                        }
                        Item {                      // porcentajes bajo cada tramo
                            width: parent.width; height: 24 * visit.u
                            Text {
                                visible: visit.snapshot === null
                                text: "Calculando avance…"
                                color: visit.muted
                                style: visit.light ? Text.Outline : Text.Normal; styleColor: visit.outline   // contorno del Dock
                                font.family: visit.fontFamily; font.pixelSize: 16 * visit.u
                            }
                            Text {
                                visible: visit.snapshot !== null
                                x: Math.max(0, Math.min(parent.width - width, bar.doneWidth / 2 - width / 2))
                                text: visit.percent + "%"
                                color: visit.ink
                                style: visit.light ? Text.Outline : Text.Normal; styleColor: visit.outline   // contorno del Dock
                                font.family: visit.fontFamily; font.pixelSize: 17 * visit.u; font.weight: Font.DemiBold
                            }
                            Text {
                                visible: visit.snapshot !== null && visit.percent < 100
                                x: Math.max(0, Math.min(parent.width - width, bar.doneWidth + (bar.width - bar.doneWidth) / 2 - width / 2))
                                text: (100 - visit.percent) + "%"
                                color: visit.muted
                                style: visit.light ? Text.Outline : Text.Normal; styleColor: visit.outline   // contorno del Dock
                                font.family: visit.fontFamily; font.pixelSize: 17 * visit.u; font.weight: Font.DemiBold
                            }
                        }
                    }
                }

                Text {
                    text: "Secciones"
                    color: visit.onPhoto ? "#FFFFFF" : visit.ink
                    layer.enabled: visit.onPhoto            // blanco con sombra suave sobre la foto
                    layer.effect: MultiEffect { shadowEnabled: true; shadowColor: Qt.rgba(0, 0, 0, 0.55); shadowBlur: 0.5; shadowVerticalOffset: 1; shadowHorizontalOffset: 0 }
                    font.family: visit.fontFamily; font.pixelSize: 23 * visit.u; font.weight: Font.DemiBold
                }
            }

            Row {                                   // accesos directos: llenan la altura restante
                id: tiles
                width: parent.width
                height: Math.max(visit.height * 0.35,
                                 visit.height - visit.topPad - head.height - body.spacing - visit.bottomPad)
                spacing: 12 * visit.u
                Repeater {
                    model: visit.sections
                    delegate: Rectangle {
                        id: tileCard
                        required property var modelData
                        readonly property bool next: modelData.key === visit.nextKey
                        readonly property color fg: next ? "#FFFFFF" : visit.ink
                        width: (tiles.width - 2 * tiles.spacing) / 3
                        height: tiles.height
                        radius: 24 * visit.u
                        color: next ? visit.green : visit.tile
                        border.color: next ? "transparent" : visit.edge
                        Mobile.DockGlassPanel { glassUi: glassHost; radius: parent.radius; u: visit.u; tint: visit.dockTint; visible: !tileCard.next }   // el activo conserva su acento
                        scale: tileTap.pressed ? 0.97 : 1
                        Behavior on scale {
                            enabled: !!visit.flow && !visit.flow.reduceMotion
                            NumberAnimation { duration: visit.flow ? visit.flow.durationTokens.fast : 105; easing.type: Easing.OutCubic }
                        }
                        Column {
                            anchors.centerIn: parent
                            width: parent.width - 16 * visit.u
                            spacing: 14 * visit.u
                            Components.FlowIcon {
                                anchors.horizontalCenter: parent.horizontalCenter
                                width: 50 * visit.u; height: width; name: visit.iconFor(tileCard.modelData.key)
                                flow: visit.flow; onDark: visit.light || tileCard.next
                                tintColor: tileCard.next ? "#FFFFFF" : visit.accent
                                activeTintColor: tintColor; inactiveOpacity: 1
                            }
                            Text {
                                width: parent.width
                                horizontalAlignment: Text.AlignHCenter
                                wrapMode: Text.WordWrap; maximumLineCount: 3; elide: Text.ElideRight
                                text: tileCard.modelData.label
                                color: tileCard.fg
                                style: visit.light ? Text.Outline : Text.Normal; styleColor: visit.outline   // contorno del Dock
                                font.family: visit.fontFamily; font.pixelSize: 17 * visit.u; font.weight: Font.DemiBold
                            }
                            Text {
                                width: parent.width
                                horizontalAlignment: Text.AlignHCenter
                                text: visit.statusText(tileCard.modelData.status)
                                color: tileCard.next ? Qt.rgba(1, 1, 1, 0.86) : visit.muted
                                style: visit.light ? Text.Outline : Text.Normal; styleColor: visit.outline   // contorno del Dock
                                font.family: visit.fontFamily; font.pixelSize: 15 * visit.u
                            }
                            Item {                  // indicador: check, anillo parcial o anillo vacío
                                id: indicator
                                anchors.horizontalCenter: parent.horizontalCenter
                                width: 42 * visit.u; height: width
                                readonly property real r: width / 2 - 3 * visit.u
                                Rectangle {
                                    anchors.fill: parent; radius: width / 2
                                    visible: tileCard.modelData.status === "complete"
                                    color: visit.green
                                    border.color: tileCard.next ? "#FFFFFF" : "transparent"
                                    border.width: 2 * visit.u
                                    Components.FlowIcon {
                                        anchors.centerIn: parent
                                        width: 22 * visit.u; height: width; name: "action.check"; flow: visit.flow; onDark: true
                                        tintColor: "#FFFFFF"; activeTintColor: "#FFFFFF"; inactiveOpacity: 1
                                    }
                                }
                                Shape {
                                    anchors.fill: parent
                                    visible: tileCard.modelData.status !== "complete"
                                    preferredRendererType: Shape.CurveRenderer
                                    ShapePath {
                                        strokeColor: tileCard.next ? Qt.rgba(1, 1, 1, 0.35) : visit.onPhoto ? Qt.rgba(1, 1, 1, 0.22) : visit.track
                                        strokeWidth: 4 * visit.u; fillColor: "transparent"
                                        PathAngleArc { centerX: indicator.width / 2; centerY: indicator.height / 2
                                                       radiusX: indicator.r; radiusY: indicator.r
                                                       startAngle: 0; sweepAngle: 360 }
                                    }
                                    ShapePath {                 // contorno del Dock bajo el arco blanco
                                        strokeColor: visit.onPhoto && !tileCard.next ? visit.outline : "transparent"
                                        strokeWidth: 6 * visit.u; fillColor: "transparent"; capStyle: ShapePath.RoundCap
                                        PathAngleArc { centerX: indicator.width / 2; centerY: indicator.height / 2
                                                       radiusX: indicator.r; radiusY: indicator.r
                                                       startAngle: -90
                                                       sweepAngle: tileCard.modelData.status === "progress"
                                                                   ? 3.6 * Math.max(8, Math.min(100, tileCard.modelData.percent)) : 0 }
                                    }
                                    ShapePath {
                                        // Sobre el vidrio el acento no se distinguía (anillo «vacío»): blanco con contorno.
                                        strokeColor: tileCard.next || visit.onPhoto ? "#FFFFFF" : visit.accent
                                        strokeWidth: 4 * visit.u; fillColor: "transparent"; capStyle: ShapePath.RoundCap
                                        PathAngleArc { centerX: indicator.width / 2; centerY: indicator.height / 2
                                                       radiusX: indicator.r; radiusY: indicator.r
                                                       startAngle: -90
                                                       // En proceso muestra su avance; pendiente, anillo vacío.
                                                       sweepAngle: tileCard.modelData.status === "progress"
                                                                   ? 3.6 * Math.max(8, Math.min(100, tileCard.modelData.percent)) : 0 }
                                    }
                                }
                            }
                        }
                        MouseArea { id: tileTap; anchors.fill: parent; onClicked: visit.openSection(tileCard.modelData.section) }
                        Accessible.role: Accessible.Button
                        Accessible.name: tileCard.modelData.label + ", " + visit.statusText(tileCard.modelData.status)
                    }
                }
            }
        }
    }

    Text {                                        // crédito obligatorio de la licencia
        anchors.left: parent.left; anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.leftMargin: visit.gutter; anchors.rightMargin: visit.gutter
        anchors.bottomMargin: 12 * visit.u
        visible: sitePhoto.visible && visit.photoCredit.length > 0
        text: visit.photoCredit
        elide: Text.ElideRight
        horizontalAlignment: Text.AlignHCenter
        color: visit.onPhoto ? Qt.rgba(1, 1, 1, 0.85) : visit.muted
        font.family: visit.fontFamily; font.pixelSize: 11 * visit.u
    }
}

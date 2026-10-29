pragma ComponentBehavior: Bound
import QtQuick

// InGe Earth · control flotante Liquid Glass (UX 5.0, 2026-10-14).
// Misma familia material que el Dock global: una instancia de GlassSurface
// (shaders/glass.frag, sin cambios) que muestrea UNA textura compartida y ya
// desenfocada del globo (glassHost), más capas ópticas estáticas pintadas una
// sola vez (borde iluminado, brillo especular, sombra interior). La refracción
// se aproxima con una lente: el cristal muestrea una región algo menor que su
// tamaño, centrada en el botón, más la lente de borde del shader; no añade
// pasadas GPU. Tinte neutro casi incoloro: el globo se ve a través del vidrio,
// nunca un relleno corporativo. Sin textura (gama baja o backdrop no
// disponible) degrada a cristal neutro translúcido con las mismas capas.
Item {
    id: action

    property var glassHost: null           // Item con backdrop + glassTexture + glassTick (como GlassSurface.ui)
    property real u: 1
    property string iconFamily: ""
    property string fontFamily: ""
    property int glyph: 0                  // Lucide (misma fuente que el Dock)
    property real glyphRotation: 0
    property string label: ""
    property string hint: ""
    property bool available: true          // false: atenuado, el toque explica por qué
    property bool active: false
    property bool busy: false
    property bool reducedMotion: false
    property color tint: Qt.rgba(10 / 255, 14 / 255, 20 / 255, 0.20)   // vidrio grafito neutro y translúcido: sin color de marca, icono blanco legible sobre nubes
    property color fallbackTint: Qt.rgba(14 / 255, 18 / 255, 24 / 255, 0.42)   // neutro translúcido
    property color accent: "#8FD8FF"
    property real lens: 1.14
    property Component face: null         // contenido propio (p. ej. la brújula)
    signal activated()
    signal rejected()

    readonly property bool pressed: tap.pressed
    readonly property bool hasBackdrop: glassHost !== null && !!glassHost.glassTexture

    function haptic(intent) {
        if (typeof FlowHaptics !== "undefined" && FlowHaptics)
            FlowHaptics.trigger(intent)
    }
    // Confirmación visual breve junto al botón: info | ok | error.
    function confirm(text, tone) {
        if (!text || !text.length)
            return
        pillText.text = text
        pill.tone = tone || "info"
        pill.shown = true
        pillTimer.interval = pill.tone === "error" ? 3200 : 1900
        pillTimer.restart()
        if (pill.tone === "error")
            haptic("error")
    }
    function trigger() {
        if (!available) {
            haptic("warning")
            rejected()
            return
        }
        haptic("light")
        if (!reducedMotion)
            releasePulse.restart()
        activated()
    }

    implicitWidth: 52 * u
    implicitHeight: implicitWidth
    width: implicitWidth
    height: implicitHeight

    Accessible.role: Accessible.Button
    Accessible.name: label + (available ? "" : ". No disponible")
    Accessible.description: hint
    Accessible.onPressAction: action.trigger()

    // ----------------------------------------------------------- lente
    property int lensTick: 0
    onXChanged: lensTick++
    onYChanged: lensTick++
    onWidthChanged: lensTick++
    Item {
        id: lensBackdrop
        visible: false
        readonly property Item backdrop: lensBackdrop
        readonly property var glassTexture: action.hasBackdrop ? action.glassHost.glassTexture : null
        readonly property int hostTick: (action.glassHost ? action.glassHost.glassTick : 0) + action.lensTick
        property int geometryTick: 0
        readonly property int glassTick: hostTick + geometryTick
        readonly property point hostOrigin: {
            var tick = hostTick                    // dependencia de reposicionamiento
            return action.glassHost ? action.glassHost.mapToItem(action, 0, 0) : Qt.point(0, 0)
        }
        // Misma textura ampliada alrededor del centro del botón.
        x: action.width / 2 - action.lens * (action.width / 2 - hostOrigin.x)
        y: action.height / 2 - action.lens * (action.height / 2 - hostOrigin.y)
        width: action.glassHost ? action.glassHost.width * action.lens : 1
        height: action.glassHost ? action.glassHost.height * action.lens : 1
        onXChanged: geometryTick++
        onYChanged: geometryTick++
        onWidthChanged: geometryTick++
        onHeightChanged: geometryTick++
    }

    // ----------------------------------------------------------- cuerpo
    Item {
        id: body
        anchors.fill: parent
        // Presión: se hunde rápido; al soltar recupera con rebote moderado.
        property real press: tap.pressed && action.available ? 1 : 0
        Behavior on press {
            NumberAnimation {
                duration: action.reducedMotion ? 0 : (tap.pressed ? 90 : 300)
                easing.type: tap.pressed ? Easing.OutQuad : Easing.OutBack
                easing.overshoot: 2.0
            }
        }
        scale: 1 - 0.09 * press
        onScaleChanged: action.lensTick++

        // Sombra de respaldo (la GlassSurface ya dibuja la suya).
        Rectangle {
            visible: !action.hasBackdrop
            anchors.centerIn: parent
            width: parent.width + 6 * action.u
            height: width
            radius: width / 2
            color: Qt.rgba(21 / 255, 26 / 255, 48 / 255, 0.20)
        }
        GlassSurface {
            ui: lensBackdrop
            radius: body.width / 2
            margin: 10 * action.u
            tint: action.tint
            edge: Qt.rgba(1, 1, 1, 0.34)
            shadowAlpha: 0.20
            refraction: 5 * action.u               // lente de borde: el globo se curva hacia el centro
            specular: 0.55
            bevel: 12 * action.u
        }
        Rectangle {   // degradación digna: vidrio neutro translúcido (el globo se sigue viendo)
            visible: !action.hasBackdrop
            anchors.fill: parent
            radius: width / 2
            color: action.fallbackTint
            border.width: 1
            border.color: Qt.rgba(1, 1, 1, 0.30)
            gradient: Gradient {
                GradientStop { position: 0.0; color: Qt.rgba(1, 1, 1, 0.16) }
                GradientStop { position: 0.5; color: action.fallbackTint }
                GradientStop { position: 1.0; color: Qt.rgba(14 / 255, 18 / 255, 24 / 255, 0.50) }
            }
        }
        // Capas ópticas estáticas: se pintan una vez por tamaño, no por frame.
        Canvas {
            id: optics
            anchors.fill: parent
            onWidthChanged: requestPaint()
            onHeightChanged: requestPaint()
            onPaint: {
                var ctx = getContext("2d")
                var w = width, h = height, r = Math.min(w, h) / 2
                if (r <= 1)
                    return
                ctx.reset()
                function disc() { ctx.beginPath(); ctx.arc(w / 2, h / 2, r, 0, 2 * Math.PI); ctx.closePath() }
                // Profundidad: sombra interior baja, muy contenida.
                var shade = ctx.createRadialGradient(w / 2, h * 1.08, r * 0.15, w / 2, h * 0.92, r * 1.05)
                shade.addColorStop(0, "rgba(4,10,24,0.30)")
                shade.addColorStop(1, "rgba(4,10,24,0)")
                ctx.fillStyle = shade; disc(); ctx.fill()
                // Brillo especular superior izquierdo.
                var spec = ctx.createRadialGradient(w * 0.34, h * 0.16, 0, w * 0.34, h * 0.16, r * 1.0)
                spec.addColorStop(0, "rgba(255,255,255,0.32)")
                spec.addColorStop(0.5, "rgba(255,255,255,0.07)")
                spec.addColorStop(1, "rgba(255,255,255,0)")
                ctx.fillStyle = spec; disc(); ctx.fill()
                // Borde iluminado: luz arriba, cáustica fría abajo.
                var lw = Math.max(1, 1.2 * action.u)
                var rim = ctx.createLinearGradient(0, 0, 0, h)
                rim.addColorStop(0, "rgba(255,255,255,0.64)")
                rim.addColorStop(0.42, "rgba(255,255,255,0.10)")
                rim.addColorStop(0.78, "rgba(255,255,255,0.05)")
                rim.addColorStop(1, "rgba(170,225,255,0.34)")
                ctx.lineWidth = lw
                ctx.strokeStyle = rim
                ctx.beginPath(); ctx.arc(w / 2, h / 2, r - lw / 2, 0, 2 * Math.PI); ctx.stroke()
            }
        }
        Rectangle {   // estado activo: realce sutil (vidrio algo más luminoso + anillo fino)
            anchors.fill: parent
            anchors.margins: 2 * action.u
            radius: width / 2
            color: Qt.rgba(1, 1, 1, 0.10)
            border.width: 1.5 * action.u
            border.color: action.accent
            opacity: action.active ? 1 : 0
            visible: opacity > 0.01
            Behavior on opacity { NumberAnimation { duration: action.reducedMotion ? 0 : 200 } }
        }
        Rectangle {   // presionado
            anchors.fill: parent
            radius: width / 2
            color: "white"
            opacity: 0.14 * body.press
            visible: opacity > 0.005
        }
        Text {
            visible: action.glyph !== 0
            anchors.centerIn: parent
            text: String.fromCharCode(action.glyph)
            rotation: action.glyphRotation
            font.family: action.iconFamily
            font.pixelSize: 23 * action.u
            color: action.active ? "#FFFFFF" : Qt.rgba(1, 1, 1, 0.92)
            style: Text.Raised                      // legible sobre nubes y desiertos
            styleColor: Qt.rgba(4 / 255, 10 / 255, 24 / 255, 0.55)
            opacity: action.available ? 1 : 0.42
        }
        Loader {
            anchors.fill: parent
            active: action.face !== null
            sourceComponent: action.face
            opacity: action.available ? 1 : 0.42
        }
        Canvas {   // operación en curso (p. ej. GPS buscando)
            id: busyRing
            anchors.fill: parent
            anchors.margins: 3 * action.u
            visible: action.busy
            onWidthChanged: requestPaint()
            onPaint: {
                var ctx = getContext("2d")
                var w = width, h = height, lw = Math.max(1.5, 2 * action.u)
                ctx.reset()
                var g = ctx.createLinearGradient(0, 0, w, 0)
                g.addColorStop(0, "rgba(143,216,255,0)")
                g.addColorStop(1, "rgba(143,216,255,0.95)")
                ctx.lineWidth = lw
                ctx.lineCap = "round"
                ctx.strokeStyle = g
                ctx.beginPath(); ctx.arc(w / 2, h / 2, w / 2 - lw, -Math.PI / 2, Math.PI * 0.85); ctx.stroke()
            }
            RotationAnimator on rotation {
                from: 0; to: 360; duration: 1100
                loops: Animation.Infinite
                running: busyRing.visible && !action.reducedMotion
            }
        }
        Rectangle {   // liberación: onda de cristal que se expande y desvanece
            id: pulse
            anchors.centerIn: parent
            width: parent.width
            height: width
            radius: width / 2
            color: "transparent"
            border.width: 1.5 * action.u
            border.color: Qt.rgba(1, 1, 1, 0.55)
            opacity: 0
            ParallelAnimation {
                id: releasePulse
                ScaleAnimator { target: pulse; from: 1.0; to: 1.38; duration: 360; easing.type: Easing.OutCubic }
                OpacityAnimator { target: pulse; from: 0.55; to: 0; duration: 360; easing.type: Easing.OutCubic }
            }
        }
    }

    MouseArea {
        id: tap
        anchors.fill: parent
        anchors.margins: -4 * action.u                // objetivo táctil >= 56 dp
        preventStealing: true
        onClicked: action.trigger()
    }

    // ----------------------------------------------- confirmación lateral
    Item {
        id: pill
        property bool shown: false
        property string tone: "info"
        height: 34 * action.u
        width: pillText.width + 34 * action.u
        anchors.verticalCenter: parent.verticalCenter
        x: -width - 12 * action.u + (shown ? 0 : 14 * action.u)
        opacity: shown ? 1 : 0
        visible: opacity > 0.01
        Behavior on opacity { NumberAnimation { duration: action.reducedMotion ? 0 : 180 } }
        Behavior on x { NumberAnimation { duration: action.reducedMotion ? 0 : 240; easing.type: Easing.OutCubic } }
        Rectangle {
            anchors.fill: parent
            radius: height / 2
            color: Qt.rgba(21 / 255, 26 / 255, 48 / 255, 0.86)
            border.width: 1
            border.color: Qt.rgba(1, 1, 1, 0.24)
            Rectangle {   // brillo superior del cristal
                anchors.fill: parent
                anchors.margins: 1
                radius: height / 2
                gradient: Gradient {
                    GradientStop { position: 0.0; color: Qt.rgba(1, 1, 1, 0.12) }
                    GradientStop { position: 0.55; color: Qt.rgba(1, 1, 1, 0.0) }
                }
            }
        }
        Rectangle {
            x: 13 * action.u
            anchors.verticalCenter: parent.verticalCenter
            width: 7 * action.u
            height: width
            radius: width / 2
            color: pill.tone === "error" ? "#FF8A8A" : (pill.tone === "ok" ? "#8FE3B0" : action.accent)
        }
        Text {
            id: pillText
            x: 26 * action.u
            anchors.verticalCenter: parent.verticalCenter
            width: Math.min(implicitWidth, 230 * action.u)
            elide: Text.ElideRight
            color: "white"
            font.family: action.fontFamily
            font.pixelSize: 13 * action.u
        }
        Timer { id: pillTimer; onTriggered: pill.shown = false }
    }
}

pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import "../flowcore" as FlowCore

// Una sola representación de una operación foreground REAL de Calicatas.
// operation = { id, kind, title, detail, phase, blocking, cover, immediate,
//               result: ""|"SUCCESS"|"ERROR"|"INFO", actions: [{ id, label }] }
// Anti-flash: aparece tras showDelayMs; una vez visible dura al menos
// minVisibleMs. La operación nunca se retrasa: solo la transición visual.
Item {
    id: overlay
    anchors.fill: parent
    z: 1000

    property var operation: null
    // Tokens de la página anfitriona (sin paleta propia).
    property color pageColor: "#F4F6F8"
    property color surfaceColor: "#FFFFFF"
    property color textColor: "#101418"
    property color mutedColor: "#5E6B78"
    property color accentColor: "#0A73EB"
    property color borderColor: "#D9E0E7"
    property color errorColor: "#B4232E"
    // Tema derivado de los tokens recibidos (texto claro = modo oscuro).
    readonly property bool dark: (textColor.r + textColor.g + textColor.b) / 3 > 0.5
    property int showDelayMs: 150
    property int minVisibleMs: 380

    signal actionTriggered(string actionId, var operation)

    property bool shown: false
    property double shownAt: 0
    // Lo que se muestra sobrevive a la salida para no parpadear el texto.
    property var displayed: null
    readonly property bool resultState: !!displayed && !!displayed.result && displayed.result.length > 0
    readonly property bool blocking: shown && (!displayed || displayed.blocking !== false)

    function _reveal() {
        displayed = operation
        shown = true
        shownAt = Date.now()
    }

    onOperationChanged: {
        if (operation) {
            hideTimer.stop()
            if (shown) { displayed = operation; return }
            if (operation.immediate === true || (operation.result && operation.result.length)) {
                showTimer.stop()
                _reveal()
            } else {
                showTimer.restart()
            }
        } else {
            showTimer.stop()
            if (!shown) return
            // Nunca negativo: si ya pasó el mínimo, sale en el siguiente frame.
            hideTimer.interval = Math.max(1, minVisibleMs - (Date.now() - shownAt))
            hideTimer.restart()
        }
    }

    Component.onCompleted: {
        if (operation && (operation.immediate === true || (operation.result && operation.result.length)))
            _reveal()
        else if (operation)
            showTimer.restart()
    }

    Timer { id: showTimer; interval: overlay.showDelayMs; repeat: false; onTriggered: if (overlay.operation) overlay._reveal() }
    Timer { id: hideTimer; interval: 1; repeat: false; onTriggered: overlay.shown = false }

    visible: opacity > 0.001
    opacity: shown ? 1 : 0
    // Opacidad en render thread: el fade no se detiene durante trabajo síncrono.
    Behavior on opacity { OpacityAnimator { duration: overlay.shown ? 160 : 190; easing.type: Easing.OutCubic } }

    // Cover = pantalla de preparación (sin tarjeta); si no, tarjeta flotante.
    readonly property bool coverMode: !!displayed && displayed.cover === true && !resultState

    // Mientras hay una operación crítica, el contenido (y el Dock bajo esta
    // capa) no recibe toques; no se modifica la arquitectura del Dock.
    MouseArea {
        anchors.fill: parent
        enabled: overlay.blocking
        hoverEnabled: enabled
        preventStealing: true
        onPressed: function(mouse) { mouse.accepted = true }
        onWheel: function(wheel) { wheel.accepted = true }
    }

    Rectangle {
        anchors.fill: parent
        color: overlay.displayed && overlay.displayed.cover === true
               ? overlay.pageColor : Qt.rgba(0.04, 0.06, 0.09, 0.16)
        // Cover: la luz del ambiente Liquid Glass de Calicatas (estática).
        gradient: overlay.displayed && overlay.displayed.cover === true ? coverAmbient : null
        Gradient {
            id: coverAmbient
            GradientStop { position: 0.0; color: overlay.dark ? "#18202B" : "#EEF4FF" }
            GradientStop { position: 1.0; color: overlay.dark ? "#11161D" : "#F8FAFD" }
        }
    }

    // ===== Modo cover: preparación a pantalla completa, sin tarjeta =====
    Column {
        id: coverColumn
        visible: overlay.coverMode
        width: Math.min(parent.width - 64, 320)
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.verticalCenter: parent.verticalCenter
        anchors.verticalCenterOffset: -24
        spacing: 14
        transform: Translate { id: coverLift; y: 0 }

        // FluentUI FluProgressRing (MIT) portado en FlowCore.FlowProgressRing.
        FlowCore.FlowProgressRing {
            anchors.horizontalCenter: parent.horizontalCenter
            width: 40; height: 40
            strokeWidth: 3.5
            running: overlay.coverMode && overlay.visible
            color: overlay.accentColor
            backgroundColor: overlay.borderColor
        }
        Item { width: 1; height: 6 }
        Text {
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
            text: overlay.displayed ? String(overlay.displayed.title || "") : ""
            color: overlay.textColor
            font.pixelSize: 20
            font.weight: Font.DemiBold
        }
        Text {
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
            visible: text.length > 0
            text: overlay.displayed ? String(overlay.displayed.detail || "") : ""
            color: overlay.mutedColor
            font.pixelSize: 14
            lineHeight: 1.15
        }
    }

    // Entrada del contenido: asentamiento vertical corto (sin escala, sin rebote).
    onShownChanged: {
        if (!shown) return
        coverLiftAnim.restart()
        cardLiftAnim.restart()
    }
    NumberAnimation {
        id: coverLiftAnim
        target: coverLift; property: "y"
        from: 8; to: 0; duration: 220; easing.type: Easing.OutCubic
    }

    // ===== Modo tarjeta: operaciones y resultados =====
    Rectangle {
        id: card
        visible: !overlay.coverMode
        anchors.centerIn: parent
        width: Math.min(parent.width - 48, 340)
        height: column.implicitHeight + 44
        radius: 22
        color: "transparent"
        transform: Translate { id: cardLift; y: 0 }

        // Tarjeta de estado = material Liquid Glass de Calicatas (velo casi opaco).
        CalicataSurface {
            anchors.fill: parent
            dark: overlay.dark
            accent: overlay.accentColor
            danger: overlay.errorColor
            radius: card.radius
            level: "sheet"
        }

        NumberAnimation {
            id: cardLiftAnim
            target: cardLift; property: "y"
            from: 10; to: 0; duration: 200; easing.type: Easing.OutCubic
        }

        Column {
            id: column
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: 22
            spacing: 10

            FlowCore.FlowProgressRing {
                anchors.horizontalCenter: parent.horizontalCenter
                width: 32; height: 32
                strokeWidth: 3
                running: !overlay.coverMode && overlay.visible && !overlay.resultState
                color: overlay.accentColor
                backgroundColor: overlay.borderColor
            }
            Rectangle {
                anchors.horizontalCenter: parent.horizontalCenter
                visible: overlay.resultState
                width: 34; height: 34; radius: 17
                color: "transparent"
                border.width: 0
                border.color: overlay.displayed && overlay.displayed.result === "ERROR" ? overlay.errorColor : overlay.accentColor
                CalicataSurface {
                    anchors.fill: parent
                    dark: overlay.dark
                    accent: overlay.accentColor
                    danger: overlay.errorColor
                    radius: parent.radius
                    tone: overlay.displayed && overlay.displayed.result === "ERROR" ? "danger" : "tinted"
                }
                Text {
                    anchors.centerIn: parent
                    text: overlay.displayed && overlay.displayed.result === "ERROR" ? "!" : "✓"
                    color: parent.border.color
                    font.pixelSize: 16; font.bold: true
                }
            }
            Text {
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.WordWrap
                text: overlay.displayed ? String(overlay.displayed.title || "") : ""
                color: overlay.textColor
                font.pixelSize: 17
                font.weight: Font.DemiBold
            }
            Text {
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.WordWrap
                visible: text.length > 0
                text: overlay.displayed ? String(overlay.displayed.detail || "") : ""
                color: overlay.mutedColor
                font.pixelSize: 14
                lineHeight: 1.15
            }
            Flow {
                width: parent.width
                spacing: 8
                visible: overlay.resultState && !!overlay.displayed.actions && overlay.displayed.actions.length > 0
                Repeater {
                    model: overlay.displayed && overlay.displayed.actions ? overlay.displayed.actions : []
                    delegate: Button {
                        id: actionButton
                        required property var modelData
                        required property int index
                        text: modelData.label
                        flat: index > 0
                        highlighted: index === 0
                        implicitHeight: 40
                        leftPadding: 16
                        rightPadding: 16
                        scale: down ? 0.97 : 1
                        Behavior on scale { NumberAnimation { duration: 130; easing.type: Easing.OutCubic } }
                        background: CalicataSurface {
                            dark: overlay.dark
                            accent: overlay.accentColor
                            danger: overlay.errorColor
                            radius: 12
                            tone: actionButton.highlighted ? "primary" : "glass"
                            pressed: actionButton.down
                        }
                        contentItem: Text {
                            text: actionButton.text
                            color: actionButton.highlighted ? (overlay.dark ? "#0B1220" : "#FFFFFF") : overlay.textColor
                            font.pixelSize: 14
                            font.weight: Font.DemiBold
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                        }
                        onClicked: overlay.actionTriggered(modelData.id, overlay.displayed)
                    }
                }
            }
        }
    }
}

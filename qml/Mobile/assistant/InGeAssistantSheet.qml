import QtQuick
import QtQuick.Controls

// Interfaz GLOBAL y ÚNICA de InGe IA (anfitrión: HomeScreen). Conversación real
// con el servicio InGeAssistant a través de InGeAssistantController; el módulo
// activo (Home, Calicatas, Rendiciones, InGe Earth…) aporta contexto y
// herramientas nativas, como el Dock contextual. La hoja no se recrea: se
// superpone a la subapp sin destruir su estado y conserva la conversación de
// la sesión por módulo y usuario.
// Diseño aprobado: encabezado con destello, saludo con el nombre, pregunta,
// introducción y tarjeta "Por ejemplo" como estado inicial; después, historial
// desplazable. Campo píldora con envío circular; acción principal sólo si el
// módulo publica una herramienta primaria (Rendiciones: "Registrar gasto").
Item {
    id: sheet
    objectName: "ingeAssistantSheet"
    property var ui
    property var flow: null                       // motor único InGeCoreFlow (geometría del teclado)
    property var controller: null                 // InGeAssistantController
    property bool open: false
    property string userName: ""
    property string question: "¿En qué te ayudo hoy?"
    property string intro: "InGe IA puede ayudarte a registrar tus gastos de forma rápida y sencilla."
    property string example: ""
    // Paleta corporativa (configurable por el anfitrión).
    property color textColor: "#151A30"
    property color mutedColor: "#7A8299"
    property color accentColor: "#0654A2"
    readonly property color sparkColor: "#2F6BFF"
    signal proposalAction(int index, var proposal)
    signal dismissed()

    anchors.fill: parent
    visible: open || card.y < height
    z: 70

    readonly property bool available: !!controller && controller.available
    readonly property bool busy: !!controller && controller.busy
    readonly property var messages: controller ? controller.messages : []
    readonly property var module: controller ? controller.module : ({})
    readonly property var tools: module && module.tools ? module.tools : []
    readonly property var primaryTool: tools.filter(function(t) { return t.primary === true })[0] || null
    readonly property var secondaryTools: tools.filter(function(t) { return t.primary !== true })
    readonly property var proposals: controller && controller.proposalsKey === controller.key ? controller.proposals : []
    readonly property bool canSend: available && !busy && (!controller || controller.cooldownSeconds <= 0) && input.text.trim().length > 0

    function show() { open = true }
    function close() {
        if (!open) return
        Qt.inputMethod.hide()
        input.focus = false
        open = false
        dismissed()
    }
    function send() {
        if (!canSend) return
        if (controller.send(input.text)) input.text = ""
    }

    readonly property real keyboardLift: flow && flow.imeHeight !== undefined ? Number(flow.imeHeight) : 0
    readonly property bool reduced: ui && ui.reducedMotion === true
    onMessagesChanged: Qt.callLater(function() { history.positionViewAtEnd() })

    Rectangle {                                       // fondo atenuado
        anchors.fill: parent
        color: Qt.rgba(21 / 255, 26 / 255, 48 / 255, 0.22)
        opacity: sheet.open ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: sheet.reduced ? 0 : 200 } }
        MouseArea { anchors.fill: parent; enabled: sheet.open; onClicked: sheet.close() }
    }

    Rectangle {
        id: card
        width: parent.width - 16 * sheet.ui.u
        x: 8 * sheet.ui.u
        readonly property real maxHeight: parent.height - sheet.keyboardLift - (sheet.ui.topInset || 0) - 24 * sheet.ui.u
        height: Math.min(maxHeight, sheet.messages.length || sheet.proposals.length ? maxHeight * 0.92 : header.height + introColumn.implicitHeight + bottomArea.implicitHeight + 72 * sheet.ui.u)
        Behavior on height { enabled: !sheet.reduced; NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
        readonly property real restY: parent.height - height - Math.max(sheet.keyboardLift + 10 * sheet.ui.u, (sheet.ui.dockArea || 0) - 8 * sheet.ui.u)
        y: sheet.open ? restY : parent.height + 20 * sheet.ui.u
        Behavior on y { NumberAnimation { duration: sheet.reduced ? 0 : (sheet.open ? 280 : 180); easing.type: Easing.OutCubic } }
        radius: 32 * sheet.ui.u
        gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop { position: 0.0; color: Qt.rgba(1, 1, 1, 0.98) }
            GradientStop { position: 1.0; color: Qt.rgba(238 / 255, 240 / 255, 255 / 255, 0.97) }   // toque lavanda del preview
        }
        border.width: 1
        border.color: Qt.rgba(1, 1, 1, 0.95)
        clip: true
        MouseArea { anchors.fill: parent }        // no atraviesa al fondo

        // ------------------------------------------------------- encabezado
        Item {
            id: header
            x: 24 * sheet.ui.u; y: 18 * sheet.ui.u
            width: parent.width - 48 * sheet.ui.u
            height: 52 * sheet.ui.u
            Row {
                anchors.verticalCenter: parent.verticalCenter
                spacing: 12 * sheet.ui.u
                Rectangle {
                    width: 48 * sheet.ui.u; height: width; radius: width / 2
                    color: Qt.rgba(47 / 255, 107 / 255, 255 / 255, 0.08)
                    Text { anchors.centerIn: parent; text: String.fromCharCode(0xE412); color: sheet.sparkColor
                           font.family: sheet.ui.iconFamily; font.pixelSize: 26 * sheet.ui.u }
                }
                Column {
                    anchors.verticalCenter: parent.verticalCenter
                    Text { text: "InGe IA"; color: sheet.textColor
                           font.family: sheet.ui.fontFamily; font.pixelSize: 21 * sheet.ui.u; font.weight: Font.DemiBold }
                    Text { objectName: "assistantContext"
                           text: (sheet.available ? "" : "No disponible · ") + String(sheet.module.name || "InGe+")
                           color: sheet.available ? sheet.mutedColor : "#B42334"
                           font.family: sheet.ui.fontFamily; font.pixelSize: 13 * sheet.ui.u }
                }
            }
            Rectangle {
                objectName: "assistantClose"
                width: 44 * sheet.ui.u; height: width; radius: width / 2
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                color: closeTap.pressed ? Qt.rgba(21 / 255, 26 / 255, 48 / 255, 0.10) : "transparent"
                Text { anchors.centerIn: parent; text: String.fromCharCode(0xE1B2); color: sheet.textColor
                       font.family: sheet.ui.iconFamily; font.pixelSize: 24 * sheet.ui.u }
                MouseArea { id: closeTap; anchors.fill: parent; onClicked: sheet.close() }
                Accessible.role: Accessible.Button
                Accessible.name: "Cerrar InGe IA"
            }
        }

        // ------------------------------------------ estado inicial (saludo)
        Column {
            id: introColumn
            visible: sheet.messages.length === 0 && sheet.proposals.length === 0
            x: 24 * sheet.ui.u
            anchors.top: header.bottom; anchors.topMargin: 12 * sheet.ui.u
            width: parent.width - 48 * sheet.ui.u
            spacing: 12 * sheet.ui.u
            Column {
                width: parent.width
                spacing: 6 * sheet.ui.u
                Text { width: parent.width
                       text: sheet.userName.length ? "¡Hola " + sheet.userName + "!" : "¡Hola!"
                       color: sheet.textColor; wrapMode: Text.WordWrap
                       font.family: sheet.ui.fontFamily; font.pixelSize: 30 * sheet.ui.u; font.weight: Font.Bold }
                Text { width: parent.width; text: sheet.question; color: sheet.textColor; wrapMode: Text.WordWrap
                       font.family: sheet.ui.fontFamily; font.pixelSize: 21 * sheet.ui.u; font.weight: Font.DemiBold }
            }
            Text { width: parent.width; text: sheet.intro; color: sheet.mutedColor; wrapMode: Text.WordWrap
                   font.family: sheet.ui.fontFamily; font.pixelSize: 17 * sheet.ui.u }
            Rectangle {                                // tarjeta "Por ejemplo" (toque = usarlo)
                visible: sheet.example.length > 0
                width: parent.width
                height: exampleColumn.implicitHeight + 32 * sheet.ui.u
                radius: 22 * sheet.ui.u
                color: exampleTap.pressed ? Qt.rgba(47 / 255, 107 / 255, 255 / 255, 0.12) : Qt.rgba(47 / 255, 107 / 255, 255 / 255, 0.06)
                Column {
                    id: exampleColumn
                    x: 18 * sheet.ui.u; y: 16 * sheet.ui.u
                    width: parent.width - 36 * sheet.ui.u
                    spacing: 8 * sheet.ui.u
                    Row {
                        spacing: 8 * sheet.ui.u
                        Text { text: String.fromCharCode(0xE412); color: sheet.sparkColor
                               font.family: sheet.ui.iconFamily; font.pixelSize: 18 * sheet.ui.u }
                        Text { text: "Por ejemplo:"; color: sheet.mutedColor
                               font.family: sheet.ui.fontFamily; font.pixelSize: 15 * sheet.ui.u }
                    }
                    Text { width: parent.width; text: "“" + sheet.example + "”"; color: sheet.textColor; wrapMode: Text.WordWrap
                           font.italic: true; font.family: sheet.ui.fontFamily; font.pixelSize: 16 * sheet.ui.u }
                }
                MouseArea { id: exampleTap; anchors.fill: parent; onClicked: { input.text = sheet.example; input.forceActiveFocus() } }
            }
        }

        // ------------------------------------------------------- historial
        ListView {
            id: history
            objectName: "assistantHistory"
            visible: !introColumn.visible
            x: 16 * sheet.ui.u
            anchors.top: header.bottom; anchors.topMargin: 8 * sheet.ui.u
            anchors.bottom: bottomArea.top; anchors.bottomMargin: 8 * sheet.ui.u
            width: parent.width - 32 * sheet.ui.u
            clip: true
            spacing: 10 * sheet.ui.u
            boundsBehavior: Flickable.StopAtBounds
            model: sheet.messages
            delegate: Item {
                required property var modelData
                readonly property bool mine: modelData.role === "user"
                readonly property bool tool: modelData.role === "tool"
                width: history.width
                height: bubble.height
                Rectangle {
                    id: bubble
                    readonly property real maxW: history.width * (tool ? 1 : 0.84)
                    width: Math.min(maxW, bubbleText.implicitWidth + 32 * sheet.ui.u)
                    height: bubbleText.implicitHeight + 24 * sheet.ui.u
                    x: mine ? history.width - width : 0
                    radius: 20 * sheet.ui.u
                    color: mine ? sheet.accentColor : tool ? Qt.rgba(72 / 255, 100 / 255, 38 / 255, 0.10) : "#FFFFFF"
                    border.width: mine ? 0 : 1
                    border.color: Qt.rgba(21 / 255, 26 / 255, 48 / 255, 0.08)
                    Text {
                        id: bubbleText
                        x: 16 * sheet.ui.u; y: 12 * sheet.ui.u
                        width: Math.min(implicitWidth, bubble.maxW - 32 * sheet.ui.u)
                        text: (tool ? "Herramienta InGe+ · " : "") + modelData.text
                        color: mine ? "#FFFFFF" : sheet.textColor
                        wrapMode: Text.Wrap
                        textFormat: Text.PlainText
                        font.family: sheet.ui.fontFamily; font.pixelSize: 15 * sheet.ui.u
                    }
                }
            }
            footer: Item {                               // indicador "respondiendo"
                width: history.width
                height: sheet.busy ? 44 * sheet.ui.u : 0
                visible: sheet.busy
                Row {
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 6 * sheet.ui.u
                    Repeater {
                        model: 3
                        delegate: Rectangle {
                            required property int index
                            width: 8 * sheet.ui.u; height: width; radius: width / 2
                            color: sheet.sparkColor
                            opacity: 0.35
                            SequentialAnimation on opacity {
                                running: sheet.busy && !sheet.reduced
                                loops: Animation.Infinite
                                PauseAnimation { duration: index * 140 }
                                NumberAnimation { to: 1; duration: 280 }
                                NumberAnimation { to: 0.35; duration: 280 }
                                PauseAnimation { duration: (2 - index) * 140 }
                            }
                        }
                    }
                    Text { text: "InGe IA está respondiendo…"; color: sheet.mutedColor
                           font.family: sheet.ui.fontFamily; font.pixelSize: 13 * sheet.ui.u }
                }
            }
        }

        // ------------------------------- propuestas del módulo + entrada
        Column {
            id: bottomArea
            x: 24 * sheet.ui.u
            width: parent.width - 48 * sheet.ui.u
            anchors.bottom: parent.bottom; anchors.bottomMargin: 20 * sheet.ui.u
            spacing: 10 * sheet.ui.u

            // Propuestas estructuradas (p. ej. gastos): editables antes de abrirlas en el formulario.
            Repeater {
                model: sheet.proposals
                delegate: Rectangle {
                    id: proposalCard
                    required property var modelData
                    required property int index
                    width: bottomArea.width
                    height: proposalColumn.implicitHeight + 24 * sheet.ui.u
                    radius: 20 * sheet.ui.u
                    color: "#FFFFFF"
                    border.width: 1; border.color: Qt.rgba(6 / 255, 84 / 255, 162 / 255, 0.14)
                    Column {
                        id: proposalColumn
                        x: 14 * sheet.ui.u; y: 12 * sheet.ui.u
                        width: parent.width - 28 * sheet.ui.u
                        spacing: 6 * sheet.ui.u
                        Row {
                            width: parent.width
                            spacing: 8 * sheet.ui.u
                            TextField {
                                objectName: "proposalConcept"
                                width: parent.width * 0.62
                                text: String(proposalCard.modelData.concept || "")
                                placeholderText: "Concepto"
                                color: sheet.textColor
                                font.family: sheet.ui.fontFamily; font.pixelSize: 15 * sheet.ui.u
                                onEditingFinished: if (sheet.controller.editProposal) sheet.controller.editProposal(proposalCard.index, "concept", text)
                            }
                            TextField {
                                objectName: "proposalAmount"
                                width: parent.width * 0.38 - 8 * sheet.ui.u
                                text: String(proposalCard.modelData.amount || "")
                                placeholderText: "0.00"
                                inputMethodHints: Qt.ImhFormattedNumbersOnly
                                color: sheet.textColor
                                font.family: sheet.ui.fontFamily; font.pixelSize: 15 * sheet.ui.u
                                onEditingFinished: if (sheet.controller.editProposal) sheet.controller.editProposal(proposalCard.index, "amount", text)
                            }
                        }
                        Text { width: parent.width; text: String(proposalCard.modelData.summary || ""); color: sheet.mutedColor; wrapMode: Text.WordWrap
                               font.family: sheet.ui.fontFamily; font.pixelSize: 13 * sheet.ui.u }
                        Text { width: parent.width; visible: String(proposalCard.modelData.problem || "").length > 0
                               text: String(proposalCard.modelData.problem || ""); color: "#B42334"; wrapMode: Text.WordWrap
                               font.family: sheet.ui.fontFamily; font.pixelSize: 13 * sheet.ui.u }
                        Rectangle {
                            width: parent.width; height: 42 * sheet.ui.u; radius: 14 * sheet.ui.u
                            color: sheet.accentColor
                            opacity: proposalCard.modelData.ready === true ? 1 : 0.45
                            Text { anchors.centerIn: parent; text: String(proposalCard.modelData.actionLabel || "Revisar y registrar"); color: "#FFFFFF"
                                   font.family: sheet.ui.fontFamily; font.pixelSize: 15 * sheet.ui.u; font.weight: Font.DemiBold }
                            MouseArea { anchors.fill: parent; enabled: proposalCard.modelData.ready === true
                                        onClicked: sheet.proposalAction(proposalCard.index, proposalCard.modelData) }
                            Accessible.role: Accessible.Button
                            Accessible.name: String(proposalCard.modelData.actionLabel || "Revisar y registrar")
                        }
                    }
                }
            }

            // Herramientas nativas secundarias del módulo (chips).
            Flow {
                width: parent.width
                spacing: 8 * sheet.ui.u
                visible: sheet.secondaryTools.length > 0
                Repeater {
                    model: sheet.secondaryTools
                    delegate: Rectangle {
                        required property var modelData
                        readonly property bool usable: sheet.available && !sheet.busy && modelData.enabled !== false
                        height: 38 * sheet.ui.u
                        width: chipRow.implicitWidth + 24 * sheet.ui.u
                        radius: height / 2
                        color: chipTap.pressed ? Qt.rgba(47 / 255, 107 / 255, 255 / 255, 0.16) : Qt.rgba(47 / 255, 107 / 255, 255 / 255, 0.07)
                        opacity: usable || modelData.offline === true ? 1 : 0.45
                        Row {
                            id: chipRow
                            anchors.centerIn: parent
                            spacing: 6 * sheet.ui.u
                            Text { visible: Number(modelData.glyph || 0) > 0; text: String.fromCharCode(Number(modelData.glyph || 0))
                                   color: sheet.sparkColor; font.family: sheet.ui.iconFamily; font.pixelSize: 16 * sheet.ui.u
                                   anchors.verticalCenter: parent.verticalCenter }
                            Text { text: modelData.label; color: sheet.textColor; anchors.verticalCenter: parent.verticalCenter
                                   font.family: sheet.ui.fontFamily; font.pixelSize: 14 * sheet.ui.u }
                        }
                        MouseArea { id: chipTap; anchors.fill: parent
                                    enabled: modelData.enabled !== false && (modelData.offline === true || (sheet.available && !sheet.busy))
                                    onClicked: sheet.controller.runTool(modelData.id) }
                        Accessible.role: Accessible.Button
                        Accessible.name: modelData.label
                    }
                }
            }

            // Error real con reintento.
            Row {
                width: parent.width
                visible: !!sheet.controller && sheet.controller.lastError.length > 0
                spacing: 10 * sheet.ui.u
                Text { width: parent.width - retryButton.width - 10 * sheet.ui.u; anchors.verticalCenter: parent.verticalCenter
                       text: sheet.controller ? sheet.controller.lastError : ""; color: "#B42334"; wrapMode: Text.WordWrap
                       font.family: sheet.ui.fontFamily; font.pixelSize: 13 * sheet.ui.u }
                Rectangle {
                    id: retryButton
                    visible: !!sheet.controller && sheet.controller.retryAction !== null
                    width: visible ? retryText.implicitWidth + 28 * sheet.ui.u : 0; height: 36 * sheet.ui.u; radius: height / 2
                    color: Qt.rgba(180 / 255, 35 / 255, 52 / 255, 0.10)
                    readonly property bool ready: !!sheet.controller && sheet.controller.cooldownSeconds <= 0
                    opacity: ready ? 1 : 0.55
                    Text { id: retryText; anchors.centerIn: parent
                           text: sheet.controller && sheet.controller.cooldownSeconds > 0
                               ? "Reintentar en " + sheet.controller.cooldownSeconds + " s" : "Reintentar"
                           color: "#B42334"
                           font.family: sheet.ui.fontFamily; font.pixelSize: 14 * sheet.ui.u; font.weight: Font.DemiBold }
                    MouseArea { anchors.fill: parent; enabled: retryButton.ready; onClicked: sheet.controller.retry() }
                }
            }

            Rectangle {                                // campo píldora con envío circular
                width: parent.width
                height: 60 * sheet.ui.u
                radius: height / 2
                color: "#FFFFFF"
                border.width: 1
                border.color: input.activeFocus ? "#3B82D6" : Qt.rgba(21 / 255, 26 / 255, 48 / 255, 0.08)
                Text { x: 20 * sheet.ui.u; anchors.verticalCenter: parent.verticalCenter
                       text: String.fromCharCode(0xE412); color: sheet.sparkColor
                       font.family: sheet.ui.iconFamily; font.pixelSize: 20 * sheet.ui.u }
                TextField {
                    id: input
                    objectName: "assistantInput"
                    x: 52 * sheet.ui.u
                    width: parent.width - x - 64 * sheet.ui.u
                    anchors.verticalCenter: parent.verticalCenter
                    color: sheet.textColor
                    placeholderText: sheet.available ? "Escribe tu solicitud…" : "InGe IA no está disponible ahora"
                    placeholderTextColor: "#8E9AB5"
                    font.family: sheet.ui.fontFamily
                    font.pixelSize: 16 * sheet.ui.u
                    maximumLength: 4000
                    background: null
                    onAccepted: sheet.send()
                }
                Rectangle {
                    objectName: "assistantSend"
                    width: 46 * sheet.ui.u; height: width; radius: width / 2
                    anchors.right: parent.right; anchors.rightMargin: 7 * sheet.ui.u
                    anchors.verticalCenter: parent.verticalCenter
                    color: sheet.canSend ? sheet.sparkColor : "#A9B4FF"
                    opacity: sheet.canSend ? 1 : 0.55
                    Behavior on color { ColorAnimation { duration: 150 } }
                    Text { anchors.centerIn: parent; text: String.fromCharCode(0xE152); color: "#FFFFFF"   // send (Lucide)
                           font.family: sheet.ui.iconFamily; font.pixelSize: 20 * sheet.ui.u }
                    MouseArea { anchors.fill: parent; enabled: sheet.canSend; onClicked: sheet.send() }
                    Accessible.role: Accessible.Button
                    Accessible.name: "Enviar"
                }
            }
            // Acción principal del módulo (sólo si existe: Rendiciones -> "Registrar gasto").
            Rectangle {
                id: actionButton
                objectName: "assistantAction"
                visible: sheet.primaryTool !== null
                readonly property bool active: sheet.primaryTool !== null && sheet.available && !sheet.busy && sheet.primaryTool.enabled !== false
                width: parent.width
                height: visible ? 58 * sheet.ui.u : 0
                radius: 20 * sheet.ui.u
                gradient: Gradient {
                    orientation: Gradient.Horizontal
                    GradientStop { position: 0.0; color: "#1F6FE5" }
                    GradientStop { position: 1.0; color: sheet.accentColor }
                }
                opacity: active ? 1 : 0.45
                Row {
                    anchors.centerIn: parent
                    spacing: 10 * sheet.ui.u
                    Text { text: String.fromCharCode(0xE412); color: "#FFFFFF"; anchors.verticalCenter: parent.verticalCenter
                           font.family: sheet.ui.iconFamily; font.pixelSize: 22 * sheet.ui.u }
                    Text { text: sheet.primaryTool ? sheet.primaryTool.label : ""; color: "#FFFFFF"; anchors.verticalCenter: parent.verticalCenter
                           font.family: sheet.ui.fontFamily; font.pixelSize: 18 * sheet.ui.u; font.weight: Font.DemiBold }
                }
                MouseArea { anchors.fill: parent; enabled: actionButton.active; onClicked: sheet.controller.runTool(sheet.primaryTool.id) }
                Accessible.role: Accessible.Button
                Accessible.name: sheet.primaryTool ? sheet.primaryTool.label : ""
            }
        }
    }
}

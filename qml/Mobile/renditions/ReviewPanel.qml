import QtQuick
import QtQuick.Controls
import "RStyle.js" as S

// Revisión y correcciones (paridad con RenditionReviewPanel de la Web). El
// contexto efectivo del servidor decide qué acciones existen: cambio de
// estado (administración), solicitud de corrección (responsable) y decisión
// sobre solicitudes. Motivo obligatorio; CAS por row_version del contexto.
RCard {
    id: panel
    property var app
    property string remoteId: ""
    property bool active: true
    readonly property var ctl: app.ctl
    ui: app.ui

    property var context: null
    property string contextError: ""
    property bool contextLoading: false
    property string reason: ""
    property string nextState: ""
    property string requestedState: ""               // se elige primero; luego aparece el motivo
    property string requestId: ""
    property string actionError: ""
    readonly property var life: ({ alive: true })
    readonly property bool hasActions: context !== null && (context.can_request_edit === true || (context.next_states || []).length > 0
                                       || (context.can_decide_edit === true && (context.requests || []).length > 0))
    readonly property var adminStates: context ? (context.next_states || []) : []
    readonly property bool asAdmin: adminStates.length > 0
    readonly property bool asOwner: context !== null && context.can_request_edit === true && !asAdmin
    readonly property var pendingRequests: context && context.can_decide_edit === true
                                           ? (context.requests || []).filter(function(r) { return r.status === "PENDING" }) : []
    readonly property string picked: asAdmin ? nextState : asOwner ? requestedState : ""
    readonly property var stateKeys: asAdmin ? adminStates.map(function(k) { return String(k) }) : asOwner ? ["EN_REVISION", "OBSERVADO", "APROBADO"] : []
    readonly property bool needsReason: picked.length > 0 || pendingRequests.length > 0
    // Rediseño aprobado: la tarjeta sólo aparece cuando hay algo que hacer o ver.
    visible: remoteId.length > 0 && (contextError.length > 0 || hasActions || (context !== null && (context.requests || []).length > 0))
    color: S.glass(0.80)
    border.color: S.edge(1)
    radius: 24 * ui.u
    signal changed()
    Component.onDestruction: life.alive = false

    function loadContext() {
        if (!remoteId.length) { context = null; return }
        contextLoading = true
        contextError = ""
        var life = panel.life
        app.call("reviewContext", { renditionId: remoteId }, "reviewContext:" + remoteId, function(ok, result, code, message) {
            if (!life.alive) return
            panel.contextLoading = false
            if (!ok) { panel.context = null; panel.contextError = panel.app.errorText(code, message); return }
            panel.context = (result.rows || [])[0] || null
        })
    }
    onActiveChanged: if (active && !context && !contextLoading) loadContext()
    onRemoteIdChanged: if (active) loadContext()
    Component.onCompleted: if (active) loadContext()

    function afterAction(ok, result, code, message, successText) {
        if (!ok) { if (panel.life.alive) panel.actionError = panel.app.errorText(code, message); return }
        panel.app.toast(successText, "success")
        panel.app.refresh()
        if (!panel.life.alive) return
        panel.reason = ""
        reasonField.text = ""
        panel.nextState = ""
        panel.requestId = ""
        var next = (result.rows || [])[0]
        if (next && next.rendition_id) panel.context = next
        else panel.loadContext()
        panel.changed()
    }
    function transition() {
        actionError = ""
        app.call("reviewTransition", { renditionId: remoteId, expectedRowVersion: Number(context.row_version), nextState: nextState, reason: reason.trim() },
                 "reviewAction:" + remoteId, function(ok, result, code, message) {
            panel.afterAction(ok, result, code, message, "Estado de la rendición actualizado.")
        })
    }
    function requestChange() {
        actionError = ""
        if (!requestId.length) requestId = ctl.newId()   // estable mientras no cambie el motivo
        app.call("reviewRequest", { renditionId: remoteId, expectedRowVersion: Number(context.row_version), requestId: requestId,
                                    requestedState: requestedState, reason: reason.trim() },
                 "reviewAction:" + remoteId, function(ok, result, code, message) {
            panel.afterAction(ok, result, code, message, "Solicitud enviada a administración.")
        })
    }
    function decide(request, approve) {
        actionError = ""
        app.call("reviewDecide", { renditionId: remoteId, editRequestId: S.text_(request, "id"), expectedRowVersion: Number(context.row_version),
                                   expectedRequestRowVersion: Number(request.row_version || 0), approve: approve, reason: reason.trim() },
                 "reviewAction:" + remoteId, function(ok, result, code, message) {
            panel.afterAction(ok, result, code, message, approve ? "Solicitud autorizada." : "Solicitud denegada.")
        })
    }

    Text { text: panel.asOwner ? "Solicitar cambio" : "Cambiar estado"; color: S.text
           font.family: panel.ui.fontFamily; font.pixelSize: 17 * panel.ui.u; font.weight: Font.Bold }
    Text {
        width: parent.width
        visible: panel.contextLoading && panel.context === null
        text: "Consultando revisión…"
        color: S.muted
        font.family: panel.ui.fontFamily; font.pixelSize: 13 * panel.ui.u
    }
    Text {
        width: parent.width
        visible: panel.contextError.length > 0
        text: panel.contextError
        color: S.danger; wrapMode: Text.WordWrap
        font.family: panel.ui.fontFamily; font.pixelSize: 14 * panel.ui.u
    }
    Text {
        width: parent.width
        visible: panel.context !== null && !!panel.context.correction_base_version_id
        text: "La corrección se presentará como una nueva versión; la anterior se conserva."
        color: S.muted; wrapMode: Text.WordWrap
        font.family: panel.ui.fontFamily; font.pixelSize: 13 * panel.ui.u
    }

    // Selector segmentado: primero el estado (administración o responsable).
    Rectangle {
        objectName: "reviewStatePicker"
        width: parent.width; height: 48 * panel.ui.u; radius: 14 * panel.ui.u
        color: S.track
        visible: panel.asAdmin || panel.asOwner
        Rectangle {                                  // píldora deslizante del selector
            readonly property real cell: (stateRow.width - (panel.stateKeys.length - 1) * stateRow.spacing) / Math.max(1, panel.stateKeys.length)
            visible: panel.picked.length > 0
            x: stateRow.x + (Math.max(0, panel.stateKeys.indexOf(panel.picked))) * (cell + stateRow.spacing)
            y: stateRow.y
            width: cell; height: stateRow.height; radius: 11 * panel.ui.u
            color: S.pill()
            Behavior on x { enabled: panel.ui.reducedMotion !== true
                            SpringAnimation { spring: 4.2; damping: 0.38; epsilon: 0.25 } }
        }
        Row {
            id: stateRow
            anchors.fill: parent; anchors.margins: 3 * panel.ui.u; spacing: 3 * panel.ui.u
            Repeater {
                model: panel.asAdmin ? panel.adminStates : panel.asOwner ? ["EN_REVISION", "OBSERVADO", "APROBADO"] : []
                delegate: Rectangle {
                    id: stateCell
                    required property var modelData
                    required property int index
                    readonly property string key: String(modelData)
                    readonly property bool on: panel.picked === key
                    objectName: "reviewState:" + key
                    width: (stateRow.width - (stateRepeaterCount.value - 1) * stateRow.spacing) / Math.max(1, stateRepeaterCount.value)
                    height: stateRow.height; radius: 11 * panel.ui.u
                    color: cellTap.pressed && !on ? S.glass(0.5) : "transparent"
                    Text { anchors.centerIn: parent; width: parent.width - 8 * panel.ui.u; horizontalAlignment: Text.AlignHCenter
                           text: panel.ctl.statusLabel(stateCell.key); elide: Text.ElideRight
                           color: stateCell.on ? S.accent : S.text
                           font.family: panel.ui.fontFamily; font.pixelSize: 13.5 * panel.ui.u; font.weight: stateCell.on ? Font.Bold : Font.DemiBold }
                    MouseArea {
                        id: cellTap
                        anchors.fill: parent
                        enabled: !panel.app.busy("reviewAction:" + panel.remoteId)
                        onClicked: {
                            var next = stateCell.on ? "" : stateCell.key
                            if (panel.asAdmin) panel.nextState = next
                            else { panel.requestedState = next; panel.requestId = "" }
                            panel.actionError = ""
                        }
                    }
                    Accessible.role: Accessible.RadioButton
                    Accessible.name: panel.ctl.statusLabel(key)
                    Accessible.checked: on
                }
            }
        }
        QtObject { id: stateRepeaterCount; readonly property int value: panel.asAdmin ? panel.adminStates.length : 3 }
    }

    // Motivo: aparece después de elegir (o cuando hay solicitudes por decidir).
    RField {
        id: reasonField
        objectName: "reviewReason"
        width: parent.width
        ui: panel.ui
        formStyle: true
        visible: panel.needsReason
        label: "Motivo"
        placeholder: panel.picked === "OBSERVADO" ? "¿Qué debe corregir el responsable?" : "Breve motivo del cambio"
        maxLength: 500
        onEdited: { panel.reason = text; panel.requestId = "" }
    }
    RButton {
        objectName: "reviewConfirm"
        width: parent.width; height: 50 * panel.ui.u; radius: 16 * panel.ui.u
        ui: panel.ui
        primary: true
        visible: panel.picked.length > 0 && panel.reason.trim().length > 0
        label: panel.asAdmin ? "Confirmar: " + panel.ctl.statusLabel(panel.picked)
                             : panel.picked === "OBSERVADO" ? "Solicitar corrección" : "Solicitar cambio de estado"
        busy: panel.app.busy("reviewAction:" + panel.remoteId)
        onActivated: panel.asAdmin ? panel.transition() : panel.requestChange()
    }

    // Solicitudes registradas y decisión de administración.
    Repeater {
        model: panel.context ? (panel.context.requests || []) : []
        delegate: Rectangle {
            id: requestCard
            required property var modelData
            readonly property bool pending: modelData.status === "PENDING"
            width: panel.width - 32 * panel.ui.u
            height: requestColumn.implicitHeight + 20 * panel.ui.u
            radius: 16 * panel.ui.u
            color: S.surfaceStrong; border.width: 1; border.color: S.tintSoftBorder
            Column {
                id: requestColumn
                x: 12 * panel.ui.u; y: 10 * panel.ui.u
                width: parent.width - 24 * panel.ui.u
                spacing: 6 * panel.ui.u
                Text {
                    width: parent.width
                    text: (requestCard.pending ? "Solicitud pendiente" : requestCard.modelData.status === "APPROVED" ? "Solicitud autorizada" : "Solicitud denegada")
                          + " · " + panel.ctl.statusLabel(String(requestCard.modelData.requested_state || "OBSERVADO"))
                    color: S.text; wrapMode: Text.WordWrap
                    font.family: panel.ui.fontFamily; font.pixelSize: 13.5 * panel.ui.u; font.weight: Font.Bold
                }
                Text {
                    width: parent.width
                    text: S.date(requestCard.modelData.created_at) + " · " + S.text_(requestCard.modelData, "reason")
                          + (S.text_(requestCard.modelData, "decision_reason").length ? "\nDecisión: " + requestCard.modelData.decision_reason : "")
                    color: S.muted; wrapMode: Text.WordWrap
                    font.family: panel.ui.fontFamily; font.pixelSize: 13 * panel.ui.u
                }
                Row {
                    width: parent.width
                    spacing: 8 * panel.ui.u
                    visible: panel.context.can_decide_edit === true && requestCard.pending
                    RButton {
                        width: (parent.width - parent.spacing) / 2
                        ui: panel.ui; label: "Autorizar"; primary: true
                        enabledButton: panel.reason.trim().length > 0 && String(requestCard.modelData.requested_state || "OBSERVADO") !== "BORRADOR"
                        onActivated: panel.decide(requestCard.modelData, true)
                    }
                    RButton { width: (parent.width - parent.spacing) / 2; ui: panel.ui; label: "Denegar"; danger: true
                              enabledButton: panel.reason.trim().length > 0; onActivated: panel.decide(requestCard.modelData, false) }
                }
            }
        }
    }
    Text {
        width: parent.width
        visible: panel.actionError.length > 0
        text: panel.actionError
        color: S.danger; wrapMode: Text.WordWrap
        font.family: panel.ui.fontFamily; font.pixelSize: 14 * panel.ui.u
    }
}

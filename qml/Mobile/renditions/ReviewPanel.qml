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
    property string requestedState: "OBSERVADO"
    property string requestId: ""
    property string actionError: ""
    readonly property var life: ({ alive: true })
    readonly property bool hasActions: context !== null && (context.can_request_edit === true || (context.next_states || []).length > 0
                                       || (context.can_decide_edit === true && (context.requests || []).length > 0))
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

    Text { text: "Revisión y correcciones"; color: S.text; font.family: panel.ui.fontFamily; font.pixelSize: 15 * panel.ui.u; font.weight: Font.DemiBold }
    Text {
        width: parent.width
        visible: !panel.remoteId.length
        text: "Disponible cuando la rendición existe en el servidor."
        color: S.muted; wrapMode: Text.WordWrap
        font.family: panel.ui.fontFamily; font.pixelSize: 14 * panel.ui.u
    }
    Text {
        width: parent.width
        visible: panel.contextLoading
        text: "Consultando revisión…"
        color: S.muted
        font.family: panel.ui.fontFamily; font.pixelSize: 14 * panel.ui.u
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
        visible: panel.context !== null
        text: panel.context ? panel.ctl.statusLabel(String(panel.context.status)) + (panel.context.can_edit ? " · Edición autorizada" : " · Gastos de solo lectura")
                              + (panel.context.correction_base_version_id ? "\nLa corrección se presentará como una nueva versión; el snapshot anterior se conserva." : "")
                            : ""
        color: S.muted; wrapMode: Text.WordWrap
        font.family: panel.ui.fontFamily; font.pixelSize: 14 * panel.ui.u
    }
    Text {
        width: parent.width
        visible: panel.context !== null && !panel.hasActions
        text: "No hay cambios de estado disponibles para tu acceso en este momento."
        color: S.faint; wrapMode: Text.WordWrap
        font.family: panel.ui.fontFamily; font.pixelSize: 13 * panel.ui.u
    }
    RField {
        id: reasonField
        width: parent.width
        ui: panel.ui
        visible: panel.hasActions
        label: "Motivo de la operación (obligatorio)"
        maxLength: 500
        onEdited: { panel.reason = text; panel.requestId = "" }
    }

    // Administración: cambio de estado permitido por el servidor.
    Flow {
        width: parent.width
        spacing: 8 * panel.ui.u
        visible: panel.context !== null && (panel.context.next_states || []).length > 0
        Repeater {
            model: panel.context ? (panel.context.next_states || []) : []
            delegate: RChip {
                required property var modelData
                ui: panel.ui
                label: panel.ctl.statusLabel(String(modelData))
                selected: panel.nextState === String(modelData)
                onActivated: panel.nextState = String(modelData)
            }
        }
    }
    RButton {
        width: parent.width
        ui: panel.ui
        visible: panel.context !== null && (panel.context.next_states || []).length > 0
        label: "Cambiar estado"
        primary: true
        enabledButton: panel.nextState.length > 0 && panel.reason.trim().length > 0
        busy: panel.app.busy("reviewAction:" + panel.remoteId)
        onActivated: panel.transition()
    }

    // Responsable: solicitar corrección o cambio de estado.
    Flow {
        width: parent.width
        spacing: 8 * panel.ui.u
        visible: panel.context !== null && panel.context.can_request_edit === true && (panel.context.next_states || []).length === 0
        Repeater {
            model: ["OBSERVADO", "EN_REVISION", "APROBADO"]
            delegate: RChip {
                required property var modelData
                ui: panel.ui
                label: panel.ctl.statusLabel(modelData)
                selected: panel.requestedState === modelData
                onActivated: { panel.requestedState = modelData; panel.requestId = "" }
            }
        }
    }
    RButton {
        width: parent.width
        ui: panel.ui
        visible: panel.context !== null && panel.context.can_request_edit === true && (panel.context.next_states || []).length === 0
        label: panel.requestedState === "OBSERVADO" ? "Solicitar corrección" : "Solicitar cambio de estado"
        enabledButton: panel.reason.trim().length > 0
        busy: panel.app.busy("reviewAction:" + panel.remoteId)
        onActivated: panel.requestChange()
    }

    // Solicitudes registradas y decisión de administración.
    Repeater {
        model: panel.context ? (panel.context.requests || []) : []
        delegate: Column {
            required property var modelData
            width: panel.width - 32 * panel.ui.u
            spacing: 6 * panel.ui.u
            Text {
                width: parent.width
                text: "Solicitud " + (modelData.status === "PENDING" ? "pendiente" : modelData.status === "APPROVED" ? "autorizada" : "denegada")
                      + " · destino " + panel.ctl.statusLabel(String(modelData.requested_state || "OBSERVADO")) + " · " + S.date(modelData.created_at)
                      + "\n" + S.text_(modelData, "reason")
                      + (S.text_(modelData, "decision_reason").length ? "\nDecisión: " + modelData.decision_reason : "")
                color: S.muted; wrapMode: Text.WordWrap
                font.family: panel.ui.fontFamily; font.pixelSize: 13 * panel.ui.u
            }
            Row {
                spacing: 8 * panel.ui.u
                visible: panel.context.can_decide_edit === true && modelData.status === "PENDING"
                RButton {
                    ui: panel.ui; label: "Autorizar"
                    enabledButton: panel.reason.trim().length > 0 && String(modelData.requested_state || "OBSERVADO") !== "BORRADOR"
                    onActivated: panel.decide(modelData, true)
                }
                RButton { ui: panel.ui; label: "Denegar"; danger: true; enabledButton: panel.reason.trim().length > 0; onActivated: panel.decide(modelData, false) }
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
    RButton {
        ui: panel.ui
        visible: panel.remoteId.length > 0
        glyph: 0xE145
        label: "Actualizar revisión"
        busy: panel.contextLoading
        onActivated: panel.loadContext()
    }
}

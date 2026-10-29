import QtQuick
import QtQuick.Controls
import "RStyle.js" as S

// Gastos de la rendición seleccionada: totales (C++), lista con estado de
// revisión y de sincronización, alta, edición y eliminación autorizada.
Item {
    id: tab
    property var detail
    readonly property var app: detail.app
    readonly property var ui: detail.ui
    readonly property var ctl: detail.ctl
    readonly property var expenses: {
        var rows = detail.selected ? (app.st.expenses || []) : []
        return rows.filter(function(e) { return e.archived !== true })
    }
    readonly property var totals: ctl.totals(expenses)
    ListModel { id: expensesModel }
    onExpensesChanged: S.syncRows(expensesModel, expenses, ["localId"])
    Component.onCompleted: S.syncRows(expensesModel, expenses, ["localId"])
    // Borradores en la nube (Working Document): filas sin terminar, propias o de
    // otra sesión/dispositivo. No son gastos contables hasta registrarse.
    readonly property var drafts: detail.selected ? (app.st.workingRows || []) : []
    readonly property var fieldLabels: ({ projectId: "Proyecto", expenseDate: "Fecha", categoryCode: "Categoría", concept: "Concepto",
        beneficiary: "Proveedor / beneficiario", paymentMethodCode: "Medio de pago", paymentMethodDetail: "Detalle del pago",
        supportTypeCode: "Tipo de sustento", supportNumber: "N.º de comprobante", supportDetail: "Detalle del sustento",
        currencyCode: "Moneda", amount: "Monto", justification: "Justificación" })

    function draftState(d) {
        if (d.syncState === "CONFLICT") return { label: "Conflicto", tone: S.danger }
        if (d.promoteRequested) return { label: "Registro pendiente", tone: S.accentSoft }
        if (d.archiveRequested) return { label: "Descarte pendiente", tone: S.muted }
        if (d.syncState === "LOCAL_ONLY") return { label: "Solo en este equipo", tone: S.muted }
        if (d.syncState === "ERROR" && tab.ctl.visibleSyncError(String(d.syncError || "")).length) return { label: "Rechazado", tone: S.danger }
        if (d.syncState === "SYNCED" && d.inCloud) return { label: "Borrador en la nube", tone: S.success }
        return { label: "Pendiente de subir", tone: S.warning }
    }
    // Estado del panel de conflicto POR borrador, fuera de los delegados: el Repeater
    // los recrea en cada publicación de estado y no debe perderse la versión consultada.
    property var inspected: ({})            // workingId -> fila vigente del servidor
    property var inspectErrors: ({})        // workingId -> texto
    function setInspect(id, row, error) {
        var a = Object.assign({}, inspected); var b = Object.assign({}, inspectErrors)
        if (row) a[id] = row; else delete a[id]
        if (error) b[id] = error; else delete b[id]
        inspected = a; inspectErrors = b
    }
    function inspect(id) {
        setInspect(id, null, "")
        var self = tab
        app.call("workingInspect", { renditionId: String(detail.current.remoteId || "") }, "inspect:" + id,
                 function(ok, result, code, message) {
            if (!self.life.alive) return
            if (!ok) { self.setInspect(id, null, self.app.errorText(code, message) || "No se pudo consultar la versión del servidor. Tus cambios se conservan."); return }
            var rows = result.rows || []
            for (var i = 0; i < rows.length; ++i) if (rows[i].id === id) { self.setInspect(id, rows[i], ""); return }
            self.setInspect(id, null, "La fila ya no está disponible en el servidor. Tus cambios siguen aquí.")
        })
    }
    function resolve(id, keepLocal) {
        var self = tab
        app.call("resolveWorking", { localId: detail.localId, workingId: id, keepLocal: keepLocal, serverRow: inspected[id] },
                 "working:" + id, function(ok, result, code, message) {
            if (!self.life.alive) return
            if (!ok) { self.setInspect(id, self.inspected[id], self.app.errorText(code, message)); return }
            self.setInspect(id, null, "")
            self.app.toast(keepLocal ? "Tus cambios se aplicarán sobre la versión del servidor." : "Se adoptó la versión del servidor.", "success")
        })
    }
    readonly property var life: ({ alive: true })
    Component.onDestruction: life.alive = false

    function promote(d) {
        tab.app.call("promoteWorking", { localId: tab.detail.localId, workingId: d.id }, "working:" + d.id,
                     function(ok, result, code, message) {
            // Falla: se muestra EN la tarjeta del borrador (sin recuadros flotantes).
            if (!ok) { if (tab.life.alive) tab.setInspect(d.id, tab.inspected[d.id] || null, tab.app.errorText(code, message)); return }
            tab.app.toast("Gasto enviado a registro · el servidor lo confirmará al sincronizar.", "success")
        })
    }
    function discard(d) {
        tab.app.confirm("Descartar borrador",
                        "Se retirará «" + (S.text_(d.form, "concept") || "borrador sin concepto") + "» del documento de trabajo. No se registra ningún gasto.",
                        "Descartar", true, function() {
            tab.app.call("archiveWorking", { localId: tab.detail.localId, workingId: d.id }, "working:" + d.id,
                         function(ok, result, code, message) {
                if (!ok) { if (tab.life.alive) tab.setInspect(d.id, tab.inspected[d.id] || null, tab.app.errorText(code, message)); return }
                tab.app.toast("Borrador descartado.", "success")
            })
        })
    }

    function attachmentsOf(expense) {
        var count = 0
        var rows = expense.attachments || []
        for (var i = 0; i < rows.length; ++i) if (!S.text_(rows[i], "archived_at").length) ++count
        return count
    }
    function remove(expense) {
        app.confirm("Eliminar gasto",
                    "Se eliminará «" + S.text_(expense, "concept") + "». El cambio se sincroniza con el servidor y no se puede deshacer desde Android.",
                    "Eliminar", true, function() {
            tab.app.call("deleteExpense", { localId: tab.detail.localId, expenseLocalId: String(expense.localId) },
                         "deleteExpense:" + expense.localId, function(ok, result, code, message) {
                tab.app.toast(ok ? "Gasto eliminado en el equipo · pendiente de sincronizar." : tab.app.errorText(code, message),
                              ok ? "success" : "error")
            })
        })
    }

    Flickable {
        anchors.fill: parent
        contentWidth: width
        contentHeight: column.height + 140 * tab.ui.u
        boundsBehavior: Flickable.StopAtBounds
        clip: true
        Column {
            id: column
            x: tab.ui.gutter
            width: parent.width - 2 * tab.ui.gutter
            spacing: 12 * tab.ui.u

            RCard {
                width: parent.width
                ui: tab.ui
                Text {
                    width: parent.width
                    text: "Declarado"
                    color: S.muted; font.family: tab.ui.fontFamily; font.pixelSize: 13 * tab.ui.u
                }
                Text {
                    width: parent.width
                    text: tab.totals.error ? "Hay un importe no válido en los gastos."
                          : tab.ctl.formatCents(tab.totals.penCents, "PEN") + "   ·   " + tab.ctl.formatCents(tab.totals.usdCents, "USD")
                    color: tab.totals.error ? S.danger : S.text
                    font.family: tab.ui.fontFamily; font.pixelSize: 19 * tab.ui.u; font.weight: Font.DemiBold
                }
                Text {
                    width: parent.width
                    visible: !tab.totals.error
                    text: "Validado " + tab.ctl.formatCents(tab.totals.validatedPenCents, "PEN") + " · " + tab.ctl.formatCents(tab.totals.validatedUsdCents, "USD")
                    color: S.muted; font.family: tab.ui.fontFamily; font.pixelSize: 14 * tab.ui.u
                }
                Text {
                    width: parent.width
                    visible: !tab.totals.error
                    text: (tab.totals.count || 0) + " gastos · " + (tab.totals.pending || 0) + " pendientes · "
                          + (tab.totals.observed || 0) + " observados · " + (tab.totals.validated || 0) + " validados"
                    color: S.muted; wrapMode: Text.WordWrap
                    font.family: tab.ui.fontFamily; font.pixelSize: 14 * tab.ui.u
                }
            }

            RButton {
                width: parent.width
                ui: tab.ui
                primary: true
                glyph: 0xE13D
                label: "Agregar gasto"
                visible: tab.detail.writable
                enabledButton: tab.detail.editable
                onActivated: tab.app.openExpense(tab.detail.localId, "")
            }

            // ---- Borradores sin registrar (Working Document)
            Text {
                width: parent.width
                visible: tab.drafts.length > 0
                topPadding: 4 * tab.ui.u
                text: tab.drafts.length === 1 ? "1 borrador sin registrar" : tab.drafts.length + " borradores sin registrar"
                color: S.text; font.family: tab.ui.fontFamily; font.pixelSize: 17 * tab.ui.u; font.weight: Font.DemiBold
            }
            Repeater {
                model: tab.drafts
                delegate: RCard {
                    id: draftCard
                    required property var modelData
                    objectName: "draft:" + modelData.id
                    width: column.width
                    ui: tab.ui
                    readonly property var st: tab.draftState(modelData)
                    readonly property bool idle: !modelData.promoteRequested && !modelData.archiveRequested
                    readonly property var server: tab.inspected[modelData.id] || null       // versión vigente consultada
                    readonly property string inspectError: tab.inspectErrors[modelData.id] || ""
                    function inspect() { tab.inspect(modelData.id) }
                    function resolve(keepLocal) { tab.resolve(modelData.id, keepLocal) }
                    Row {
                        width: parent.width
                        spacing: 8 * tab.ui.u
                        Text {
                            width: parent.width - draftAmount.width - 8 * tab.ui.u
                            text: S.text_(modelData.form, "concept") || "Borrador sin concepto"
                            color: S.text; elide: Text.ElideRight
                            font.family: tab.ui.fontFamily; font.pixelSize: 16 * tab.ui.u; font.weight: Font.DemiBold
                        }
                        Text {
                            id: draftAmount
                            text: S.text_(modelData.form, "amount").length && !tab.ctl.amountError(S.text_(modelData.form, "amount")).length
                                  ? tab.ctl.formatMoney(S.text_(modelData.form, "amount"), S.text_(modelData.form, "currencyCode") || "PEN") : "—"
                            color: S.text
                            font.family: tab.ui.fontFamily; font.pixelSize: 16 * tab.ui.u
                        }
                    }
                    Text {
                        width: parent.width
                        text: (S.text_(modelData.form, "expenseDate").length ? S.date(S.text_(modelData.form, "expenseDate")) : "Sin fecha")
                              + " · " + (S.text_(modelData.form, "beneficiary") || "Sin proveedor")
                        color: S.muted; elide: Text.ElideRight
                        font.family: tab.ui.fontFamily; font.pixelSize: 13 * tab.ui.u
                    }
                    Flow {
                        width: parent.width
                        spacing: 6 * tab.ui.u
                        RBadge { ui: tab.ui; label: draftCard.st.label; tone: draftCard.st.tone }
                        RBadge { ui: tab.ui; visible: modelData.kind === "EDIT"; label: "Edición de gasto"; tone: S.accentSoft }
                        RBadge { ui: tab.ui; label: (modelData.sources || []).length + " sustentos"; tone: S.accentSoft }
                        RBadge {
                            ui: tab.ui; visible: Number(modelData.missingSources || 0) > 0
                            label: modelData.missingSources + " por volver a adjuntar"; tone: S.warning
                        }
                    }
                    Text {                                       // rechazo real del servidor (no conexión)
                        width: parent.width
                        readonly property string reason: tab.ctl.visibleSyncError(String(modelData.syncError || ""))
                        visible: reason.length > 0
                        text: reason
                        color: modelData.syncState === "CONFLICT" ? S.danger : S.warning
                        wrapMode: Text.WordWrap
                        font.family: tab.ui.fontFamily; font.pixelSize: 13 * tab.ui.u
                    }
                    // Falla de una acción de ESTE borrador (registrar, descartar, revisar).
                    Text {
                        objectName: "draftError"
                        width: parent.width; visible: draftCard.inspectError.length > 0
                        text: draftCard.inspectError; color: S.danger; wrapMode: Text.WordWrap
                        font.family: tab.ui.fontFamily; font.pixelSize: 13 * tab.ui.u
                    }
                    // ---- Conflicto real: revisar y resolver de forma explícita.
                    Column {
                        width: parent.width
                        spacing: 6 * tab.ui.u
                        visible: modelData.syncState === "CONFLICT" && tab.detail.writable
                        RButton {
                            ui: tab.ui; label: draftCard.server ? "Volver a consultar el servidor" : "Revisar versión del servidor"
                            busy: tab.app.busy("inspect:" + modelData.id)
                            onActivated: draftCard.inspect()
                        }
                        Repeater {
                            model: draftCard.server ? Object.keys(tab.fieldLabels).filter(function(f) {
                                return String(modelData.form[f] || "") !== String(((draftCard.server.payload || {}).form || {})[f] || "")
                            }) : []
                            delegate: Text {
                                required property var modelData
                                width: parent.width
                                text: tab.fieldLabels[modelData] + "\nTus cambios: " + (String(draftCard.modelData.form[modelData] || "") || "Vacío")
                                      + "\nServidor: " + (String(((draftCard.server.payload || {}).form || {})[modelData] || "") || "Vacío")
                                color: S.text; wrapMode: Text.WordWrap
                                font.family: tab.ui.fontFamily; font.pixelSize: 13 * tab.ui.u
                            }
                        }
                        Flow {
                            width: parent.width
                            spacing: 8 * tab.ui.u
                            visible: !!draftCard.server
                            RButton { ui: tab.ui; label: "Usar versión del servidor"; onActivated: draftCard.resolve(false) }
                            RButton {
                                ui: tab.ui; label: "Aplicar mis cambios sobre esta versión"
                                visible: !!draftCard.server && draftCard.server.state === "ACTIVE"
                                onActivated: draftCard.resolve(true)
                            }
                        }
                    }
                    Flow {
                        width: parent.width
                        spacing: 8 * tab.ui.u
                        visible: tab.detail.writable && modelData.syncState !== "CONFLICT"
                        RButton {
                            ui: tab.ui; label: "Continuar"; enabledButton: draftCard.idle
                            onActivated: tab.app.openExpense(tab.detail.localId, String(modelData.expenseLocalId || ""), modelData.id)
                        }
                        RButton {
                            ui: tab.ui; primary: true; label: "Registrar"
                            enabledButton: draftCard.idle && Number(modelData.missingSources || 0) === 0
                            busy: tab.app.busy("working:" + modelData.id)
                            onActivated: tab.promote(modelData)
                        }
                        RButton {
                            ui: tab.ui; danger: true; label: "Descartar"; enabledButton: draftCard.idle
                            onActivated: tab.discard(modelData)
                        }
                    }
                }
            }
            Text {
                width: parent.width
                visible: tab.drafts.length > 0 && tab.expenses.length > 0
                topPadding: 4 * tab.ui.u
                text: "Gastos registrados"
                color: S.text; font.family: tab.ui.fontFamily; font.pixelSize: 17 * tab.ui.u; font.weight: Font.DemiBold
            }

            Text {
                width: parent.width
                visible: !tab.detail.selected
                text: "Cargando los gastos de la rendición…"
                color: S.muted
                font.family: tab.ui.fontFamily; font.pixelSize: 15 * tab.ui.u
            }
            Text {
                width: parent.width
                visible: tab.detail.selected && tab.expenses.length === 0
                text: tab.detail.writable ? "Aún no hay gastos. Registra el primero con «Agregar gasto»." : "Esta rendición no tiene gastos registrados."
                color: S.muted; wrapMode: Text.WordWrap
                font.family: tab.ui.fontFamily; font.pixelSize: 15 * tab.ui.u
            }

            Repeater {
                model: expensesModel
                delegate: RCard {
                    required property string rowJson
                    readonly property var modelData: JSON.parse(rowJson)
                    width: column.width
                    ui: tab.ui
                    clickable: true
                    onActivated: tab.app.openExpense(tab.detail.localId, String(modelData.localId))
                    Row {
                        width: parent.width
                        spacing: 8 * tab.ui.u
                        Text {
                            width: parent.width - amount.width - 8 * tab.ui.u
                            text: S.text_(modelData, "concept") || "Gasto sin concepto"
                            color: S.text; elide: Text.ElideRight
                            font.family: tab.ui.fontFamily; font.pixelSize: 16 * tab.ui.u; font.weight: Font.DemiBold
                        }
                        Text {
                            id: amount
                            text: tab.ctl.formatMoney(modelData.amount, S.text_(modelData, "currencyCode", "currency_code"))
                            color: S.text
                            font.family: tab.ui.fontFamily; font.pixelSize: 16 * tab.ui.u
                        }
                    }
                    Text {
                        width: parent.width
                        text: S.date(S.text_(modelData, "expenseDate", "expense_date")) + " · " + (S.text_(modelData, "beneficiary") || "Sin proveedor")
                              + " · " + tab.ctl.projectLabel(S.text_(modelData, "projectId", "project_id"))
                        color: S.muted; elide: Text.ElideRight
                        font.family: tab.ui.fontFamily; font.pixelSize: 13 * tab.ui.u
                    }
                    Flow {
                        width: parent.width
                        spacing: 6 * tab.ui.u
                        RBadge {
                            ui: tab.ui
                            readonly property string review: (S.text_(modelData, "reviewStatus", "review_status") || "PENDIENTE").toUpperCase()
                            label: review === "VALIDADO" ? "Validado" : review === "OBSERVADO" ? "Observado" : "Pendiente de revisión"
                            tone: review === "VALIDADO" ? S.success : review === "OBSERVADO" ? S.warning : S.muted
                        }
                        RBadge { ui: tab.ui; label: tab.ctl.syncLabel(tab.app.syncState(modelData)); tone: S.syncColor(tab.app.syncState(modelData)) }
                        RBadge { ui: tab.ui; label: tab.attachmentsOf(modelData) + " sustentos"; tone: tab.attachmentsOf(modelData) > 0 ? S.accentSoft : S.warning }
                    }
                    Text {
                        width: parent.width
                        visible: S.text_(modelData, "reviewComment", "review_comment").length > 0
                        text: "Observación: " + S.text_(modelData, "reviewComment", "review_comment")
                        color: S.warning; wrapMode: Text.WordWrap
                        font.family: tab.ui.fontFamily; font.pixelSize: 13 * tab.ui.u
                    }
                    RButton {
                        ui: tab.ui
                        visible: tab.detail.writable
                        enabledButton: tab.detail.editable
                        danger: true
                        label: "Eliminar"
                        busy: tab.app.busy("deleteExpense:" + modelData.localId)
                        onActivated: tab.remove(modelData)
                    }
                }
            }
        }
    }
}

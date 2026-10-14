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
                model: tab.expenses
                delegate: RCard {
                    required property var modelData
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
                        RBadge { ui: tab.ui; label: tab.ctl.syncLabel(S.text_(modelData, "syncState")); tone: S.syncColor(modelData.syncState) }
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

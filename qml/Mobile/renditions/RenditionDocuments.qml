import QtQuick
import QtQuick.Controls
import "RStyle.js" as S

// Documentos de la rendición: ubicación en InGe Drive, sustentos por gasto
// (copia local durable + objeto privado en el servidor), apertura con URL
// firmada de 60 s (attachmentAccess) y exportaciones PDF/XLSX de la versión
// inmutable (ownerExport). Reutiliza el almacenamiento existente.
Item {
    id: tab
    property var detail
    readonly property var app: detail.app
    readonly property var ui: detail.ui
    readonly property var ctl: detail.ctl
    readonly property var current: detail.current
    readonly property var expenses: detail.selected ? (app.st.expenses || []).filter(function(e) { return e.archived !== true }) : []
    readonly property var remote: detail.selected ? (app.st.attachments || []) : []
    ListModel { id: expensesModel }
    onExpensesChanged: S.syncRows(expensesModel, expenses, ["localId"])
    Component.onCompleted: S.syncRows(expensesModel, expenses, ["localId"])
    readonly property bool exportable: String(current.remoteId || "").length > 0 && String(current.currentVersionId || "").length > 0
                                       && ["BORRADOR", "OBSERVADO"].indexOf(String(current.status || "BORRADOR")) < 0
    readonly property var life: ({ alive: true })
    Component.onDestruction: life.alive = false

    function remoteFor(expense) {
        var id = S.text_(expense, "remoteId")
        return remote.filter(function(a) { return id.length && S.text_(a, "expense_id", "expenseId") === id && !S.text_(a, "archived_at").length })
    }
    function localFor(expense) {
        return (expense.attachments || []).filter(function(a) { return !S.text_(a, "archived_at").length && S.text_(a, "phase") !== "READY" })
    }
    function open(attachmentId) {
        app.call("attachmentAccess", { attachmentId: attachmentId }, "access:" + attachmentId, function(ok, result, code, message) {
            if (!ok) { tab.app.toast(tab.app.errorText(code, message), "error"); return }
            var row = (result.rows || [])[0] || {}
            if (!String(row.signedUrl || "").length) { tab.app.toast("El servidor no devolvió un acceso al sustento.", "error"); return }
            Qt.openUrlExternally(row.signedUrl)
        })
    }
    function archive(attachment) {
        app.confirm("Retirar sustento", "Se archivará «" + S.text_(attachment, "file_name", "fileName") + "» en el servidor. La versión presentada conserva su copia.",
                    "Retirar", true, function() {
            tab.app.call("archiveAttachment", { attachmentId: S.text_(attachment, "id"), rowVersion: Number(attachment.row_version || 0) },
                         "archive:" + S.text_(attachment, "id"), function(ok, result, code, message) {
                tab.app.toast(ok ? "Solicitud enviada; la lista se actualizará al confirmar el servidor." : tab.app.errorText(code, message), ok ? "info" : "error")
            })
        })
    }
    function exportVersion(format) {
        app.call("ownerExport", { format: format }, "export:" + format, function(ok, result, code, message) {
            if (!ok) { tab.app.toast(tab.app.errorText(code, message), "error"); return }
            var path = String(result.output || "")
            tab.app.toast("Archivo generado: " + path, "success")
            if (typeof excelExporter !== "undefined" && excelExporter && path.length)
                excelExporter.openExportedFile(path, true)
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
                Text { text: "Ubicación en InGe Drive"; color: S.text; font.family: tab.ui.fontFamily; font.pixelSize: 15 * tab.ui.u; font.weight: Font.DemiBold }
                Text {
                    width: parent.width
                    wrapMode: Text.WordWrap
                    color: S.muted
                    font.family: tab.ui.fontFamily; font.pixelSize: 14 * tab.ui.u
                    text: String(tab.current.documentParentNodeId || "").length
                          ? "Carpeta: " + (S.text_(tab.current, "documentParentNodeName", "folderName") || "seleccionada en el proyecto principal")
                            + (String(tab.current.documentNodeId || "").length ? "\nExpediente documental creado en el servidor." : "\nEl expediente se crea al sincronizar.")
                          : "Sin carpeta documental. Edita los datos de la rendición para elegirla."
                }
            }

            RCard {
                width: parent.width
                ui: tab.ui
                Text { text: "Exportar versión presentada"; color: S.text; font.family: tab.ui.fontFamily; font.pixelSize: 15 * tab.ui.u; font.weight: Font.DemiBold }
                Text {
                    width: parent.width
                    wrapMode: Text.WordWrap
                    color: S.muted
                    font.family: tab.ui.fontFamily; font.pixelSize: 13 * tab.ui.u
                    text: tab.exportable ? "Se exporta la versión inmutable " + (tab.current.versionNumber || "") + " con su fondo y tipo de cambio congelados."
                                         : "Disponible cuando la rendición tiene una versión presentada y sincronizada."
                }
                Row {
                    spacing: 8 * tab.ui.u
                    RButton { ui: tab.ui; glyph: 0xE32A; label: "PDF"; enabledButton: tab.exportable; busy: tab.app.busy("export:pdf"); onActivated: tab.exportVersion("pdf") }
                    RButton { ui: tab.ui; glyph: 0xE32A; label: "Excel"; enabledButton: tab.exportable; busy: tab.app.busy("export:xlsx"); onActivated: tab.exportVersion("xlsx") }
                }
            }

            Text { text: "Sustentos por gasto"; color: S.text; font.family: tab.ui.fontFamily; font.pixelSize: 17 * tab.ui.u; font.weight: Font.DemiBold }
            Text {
                width: parent.width
                visible: tab.expenses.length === 0
                text: "No hay gastos con sustentos. Agrega comprobantes desde la ficha de cada gasto."
                color: S.muted; wrapMode: Text.WordWrap
                font.family: tab.ui.fontFamily; font.pixelSize: 14 * tab.ui.u
            }
            Repeater {
                model: expensesModel
                delegate: RCard {
                    id: expenseCard
                    required property string rowJson
                    readonly property var modelData: JSON.parse(rowJson)
                    readonly property var remoteRows: tab.remoteFor(modelData)
                    readonly property var localRows: tab.localFor(modelData)
                    ListModel { id: remoteFiles }
                    ListModel { id: localFiles }
                    onRemoteRowsChanged: S.syncRows(remoteFiles, remoteRows, ["id"])
                    onLocalRowsChanged: S.syncRows(localFiles, localRows, ["localId"])
                    Component.onCompleted: {
                        S.syncRows(remoteFiles, remoteRows, ["id"])
                        S.syncRows(localFiles, localRows, ["localId"])
                    }
                    width: column.width
                    ui: tab.ui
                    Text {
                        width: parent.width
                        text: (S.text_(modelData, "concept") || "Gasto") + " · " + tab.ctl.formatMoney(modelData.amount, S.text_(modelData, "currencyCode", "currency_code"))
                        color: S.text; elide: Text.ElideRight
                        font.family: tab.ui.fontFamily; font.pixelSize: 15 * tab.ui.u; font.weight: Font.DemiBold
                    }
                    Text {
                        width: parent.width
                        visible: expenseCard.remoteRows.length === 0 && expenseCard.localRows.length === 0
                        text: "Sin sustentos."
                        color: S.warning
                        font.family: tab.ui.fontFamily; font.pixelSize: 13 * tab.ui.u
                    }
                    Repeater {
                        model: localFiles
                        delegate: Text {
                            required property string rowJson
                            readonly property var modelData: JSON.parse(rowJson)
                            width: column.width - 32 * tab.ui.u
                            text: "• " + S.text_(modelData, "fileName") + " · " + tab.ctl.syncLabel(tab.app.syncState(modelData))
                                  + (tab.ctl.visibleSyncError(S.text_(modelData, "syncError")).length ? " · " + tab.ctl.visibleSyncError(S.text_(modelData, "syncError")) : "")
                            color: S.syncColor(tab.app.syncState(modelData)); wrapMode: Text.WordWrap
                            font.family: tab.ui.fontFamily; font.pixelSize: 13 * tab.ui.u
                        }
                    }
                    Repeater {
                        model: remoteFiles
                        delegate: Row {
                            required property string rowJson
                            readonly property var modelData: JSON.parse(rowJson)
                            width: column.width - 32 * tab.ui.u
                            spacing: 6 * tab.ui.u
                            Text {
                                width: parent.width - 200 * tab.ui.u
                                anchors.verticalCenter: parent.verticalCenter
                                text: "• " + S.text_(modelData, "file_name", "fileName")
                                color: S.text; elide: Text.ElideRight
                                font.family: tab.ui.fontFamily; font.pixelSize: 13 * tab.ui.u
                            }
                            RButton { ui: tab.ui; label: "Abrir"; width: 90 * tab.ui.u; busy: tab.app.busy("access:" + S.text_(modelData, "id")); onActivated: tab.open(S.text_(modelData, "id")) }
                            RButton {
                                ui: tab.ui; label: "Retirar"; danger: true; width: 100 * tab.ui.u
                                visible: tab.detail.writable
                                enabledButton: tab.detail.editable
                                onActivated: tab.archive(modelData)
                            }
                        }
                    }
                    RButton {
                        ui: tab.ui
                        visible: tab.detail.writable
                        enabledButton: tab.detail.editable
                        glyph: 0xE12D
                        label: "Adjuntar comprobante"
                        onActivated: tab.app.openExpense(tab.detail.localId, String(modelData.localId))
                    }
                }
            }
        }
    }
}

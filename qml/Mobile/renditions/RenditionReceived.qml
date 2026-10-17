import QtQuick
import QtQuick.Controls
import "RStyle.js" as S

// Rendición recibida: versión inmutable confirmada (receivedQuery por
// renditionId + versionId + versionNumber + hash), recepción administrativa
// idempotente, notas, actividad, sustentos del snapshot, exportación y
// acciones de revisión autorizadas por el servidor.
Item {
    id: page
    property var app
    property var row: ({})
    readonly property var ui: app.ui
    readonly property var ctl: app.ctl
    readonly property string title: S.renditionDisplayName(S.text_(row, "displayName", "display_name"), S.text_(row, "visible_code"))
                                   + " · " + (S.text_(row, "visible_code") || "Código pendiente") + " · v" + (row.version_number || "?")
    readonly property var identity: ({
        renditionId: S.text_(row, "rendition_id"), versionId: S.text_(row, "rendition_version_id"),
        versionNumber: Number(row.version_number || 0), hash: S.text_(row, "snapshot_hash")
    })
    readonly property var life: ({ alive: true })

    property var snapshot: null
    property string loadError: ""
    property var notes: []
    property var activity: []
    property string receivedAt: S.text_(row, "received_at")
    property string receiveRequestId: ""
    property string noteBody: ""
    property string noteRequestId: ""
    property string lastNoteBody: ""

    readonly property var payload: snapshot ? (snapshot.snapshot_payload || {}) : ({})
    readonly property var expenses: payload.expenses || []
    readonly property var attachments: payload.attachments || []

    function handleBack() { return false }
    Component.onCompleted: load()
    Component.onDestruction: {
        life.alive = false
        if (page.ctl) page.ctl.send("receivedClose", {}, "")
    }

    function load() {
        loadError = ""
        snapshot = null
        var life = page.life
        app.call("receivedQuery", identity, "receivedQuery", function(ok, result, code, message) {
            if (!life.alive) return
            if (!ok) { page.loadError = page.app.errorText(code, message); return }
            var rows = result.rows || []
            if (rows.length !== 1 || S.text_(rows[0], "rendition_id") !== page.identity.renditionId) {
                page.loadError = "No se confirmó la versión presentada."
                return
            }
            page.snapshot = rows[0]
            page.loadAdministration()
        })
    }
    function loadAdministration() {
        var life = page.life
        var args = { renditionId: identity.renditionId, versionId: identity.versionId }
        app.call("receivedNotes", args, "receivedNotes", function(ok, result, code, message) {
            if (life.alive && ok) page.notes = result.rows || []
        })
        app.call("receivedActivity", args, "receivedActivity", function(ok, result, code, message) {
            if (life.alive && ok) page.activity = result.rows || []
        })
    }
    function receive() {
        if (!receiveRequestId.length) receiveRequestId = ctl.newId()
        var life = page.life
        app.call("receive", { renditionId: identity.renditionId, requestId: receiveRequestId }, "receive:" + identity.renditionId,
                 function(ok, result, code, message) {
            if (!ok) { page.app.toast(page.app.errorText(code, message), "error"); return }
            var r = (result.rows || [])[0] || {}
            page.app.toast(r.result_code === "ALREADY_RECEIVED" ? "La rendición ya estaba recibida." : "Recepción registrada en el servidor.", "success")
            if (life.alive) { page.receivedAt = S.text_(r, "received_at") || new Date().toISOString(); page.loadAdministration() }
        })
    }
    function addNote() {
        var body = noteBody.trim()
        if (body.length < 3) return
        if (body !== lastNoteBody || !noteRequestId.length) noteRequestId = ctl.newId()  // reintento = mismo id
        lastNoteBody = body
        var life = page.life
        app.call("receivedAddNote", { renditionId: identity.renditionId, versionId: identity.versionId, body: body, noteRequestId: noteRequestId },
                 "receivedAddNote", function(ok, result, code, message) {
            if (!ok) { page.app.toast(page.app.errorText(code, message), "error"); return }
            page.app.toast("Nota registrada.", "success")
            if (!life.alive) return
            page.noteBody = ""
            noteField.text = ""
            page.noteRequestId = ""
            page.loadAdministration()
        })
    }
    function openAttachment(id) {
        app.call("receivedAttachment", { renditionId: identity.renditionId, versionId: identity.versionId, hash: identity.hash, attachmentId: id },
                 "receivedAttachment:" + id, function(ok, result, code, message) {
            if (!ok) { page.app.toast(page.app.errorText(code, message), "error"); return }
            var url = String(((result.rows || [])[0] || {}).signedUrl || "")
            if (url.length) Qt.openUrlExternally(url)
            else page.app.toast("El servidor no devolvió un acceso al sustento.", "error")
        })
    }
    function exportSnapshot(format) {
        app.call("receivedExport", { renditionId: identity.renditionId, versionId: identity.versionId, hash: identity.hash, format: format },
                 "receivedExport:" + format, function(ok, result, code, message) {
            if (!ok) { page.app.toast(page.app.errorText(code, message), "error"); return }
            var path = String(result.output || "")
            page.app.toast("Archivo generado: " + path, "success")
            if (typeof excelExporter !== "undefined" && excelExporter && path.length)
                excelExporter.openExportedFile(path, true)
        })
    }

    Flickable {
        anchors.fill: parent
        contentWidth: width
        contentHeight: column.height + 140 * page.ui.u
        boundsBehavior: Flickable.StopAtBounds
        clip: true
        Column {
            id: column
            x: page.ui.gutter
            y: 8 * page.ui.u
            width: parent.width - 2 * page.ui.gutter
            spacing: 12 * page.ui.u

            RCard {
                width: parent.width
                ui: page.ui
                Text { width: parent.width; text: S.text_(page.row, "owner_name"); color: S.text; font.family: page.ui.fontFamily; font.pixelSize: 17 * page.ui.u; font.weight: Font.DemiBold; elide: Text.ElideRight }
                Text {
                    width: parent.width
                    text: [S.text_(page.row, "primary_project_code"), S.text_(page.row, "primary_project_name")].filter(function(s) { return s.length }).join(" · ")
                          + "\nPeríodo " + S.period(page.row.period_start, page.row.period_end)
                          + "\nPresentada " + S.date(page.row.submitted_at) + " · " + page.ctl.statusLabel(S.text_(page.row, "status"))
                    color: S.muted; wrapMode: Text.WordWrap
                    font.family: page.ui.fontFamily; font.pixelSize: 14 * page.ui.u
                }
                Text {
                    width: parent.width
                    text: page.ctl.formatMoney(page.row.total_declared_pen, "PEN") + "   ·   " + page.ctl.formatMoney(page.row.total_declared_usd, "USD")
                          + "   ·   " + (page.row.expense_count || 0) + " gastos"
                    color: S.text
                    font.family: page.ui.fontFamily; font.pixelSize: 16 * page.ui.u
                }
                Text {
                    width: parent.width
                    visible: page.snapshot !== null
                    wrapMode: Text.WordWrap
                    color: S.muted
                    font.family: page.ui.fontFamily; font.pixelSize: 13 * page.ui.u
                    text: {
                        if (!page.snapshot) return ""
                        var f = page.snapshot.funding || {}, r = page.snapshot.exchangeRate || {}
                        return "Fondo congelado: " + (f.enabled === true ? page.ctl.formatMoney(f.pen, "PEN") + " + " + page.ctl.formatMoney(f.usd, "USD") : "sin fondo")
                               + " · Tipo de cambio: " + (r.rate === undefined || r.rate === null ? "sin registrar" : String(r.rate))
                    }
                }
                Row {
                    spacing: 8 * page.ui.u
                    RBadge { ui: page.ui; label: page.receivedAt.length ? "Recibida " + S.date(page.receivedAt) : "Pendiente de recepción"; tone: page.receivedAt.length ? S.success : S.warning }
                }
                RButton {
                    ui: page.ui
                    visible: !page.receivedAt.length
                    primary: true
                    label: "Registrar recepción"
                    enabledButton: page.snapshot !== null
                    busy: page.app.busy("receive:" + page.identity.renditionId)
                    onActivated: page.app.confirm("Registrar recepción", "Se registrará que recibiste la versión " + page.identity.versionNumber + " de esta rendición.",
                                                  "Registrar", false, function() { page.receive() })
                }
            }

            Text {
                width: parent.width
                visible: page.snapshot === null && !page.loadError.length
                text: "Consultando la versión presentada…"
                color: S.muted
                font.family: page.ui.fontFamily; font.pixelSize: 15 * page.ui.u
            }
            Column {
                width: parent.width
                visible: page.loadError.length > 0
                spacing: 8 * page.ui.u
                Text { width: parent.width; text: page.loadError; color: S.danger; wrapMode: Text.WordWrap; font.family: page.ui.fontFamily; font.pixelSize: 15 * page.ui.u }
                RButton { ui: page.ui; label: "Reintentar"; busy: page.app.busy("receivedQuery"); onActivated: page.load() }
            }

            ReviewPanel {
                width: parent.width
                app: page.app
                remoteId: page.identity.renditionId
                active: page.snapshot !== null
            }

            RCard {
                width: parent.width
                ui: page.ui
                visible: page.snapshot !== null
                Text { text: "Exportar esta versión"; color: S.text; font.family: page.ui.fontFamily; font.pixelSize: 15 * page.ui.u; font.weight: Font.DemiBold }
                Row {
                    spacing: 8 * page.ui.u
                    RButton { ui: page.ui; glyph: 0xE32A; label: "PDF"; busy: page.app.busy("receivedExport:pdf"); onActivated: page.exportSnapshot("pdf") }
                    RButton { ui: page.ui; glyph: 0xE32A; label: "Excel"; busy: page.app.busy("receivedExport:xlsx"); onActivated: page.exportSnapshot("xlsx") }
                }
            }

            Text { visible: page.snapshot !== null; text: "Gastos (" + page.expenses.length + ")"; color: S.text; font.family: page.ui.fontFamily; font.pixelSize: 17 * page.ui.u; font.weight: Font.DemiBold }
            Repeater {
                model: page.expenses
                delegate: RCard {
                    id: expenseCard
                    required property var modelData
                    readonly property var files: page.attachments.filter(function(a) { return S.text_(a, "expense_id") === S.text_(modelData, "id") })
                    width: column.width
                    ui: page.ui
                    Text {
                        width: parent.width
                        text: (S.text_(modelData, "concept") || "Gasto") + " · " + page.ctl.formatMoney(modelData.amount, S.text_(modelData, "currency_code"))
                        color: S.text; wrapMode: Text.WordWrap
                        font.family: page.ui.fontFamily; font.pixelSize: 15 * page.ui.u
                    }
                    Text {
                        width: parent.width
                        text: S.date(modelData.expense_date) + " · " + (S.text_(modelData, "beneficiary") || "Sin proveedor")
                              + (S.text_(modelData, "review_status").length ? " · " + S.text_(modelData, "review_status") : "")
                        color: S.muted; elide: Text.ElideRight
                        font.family: page.ui.fontFamily; font.pixelSize: 13 * page.ui.u
                    }
                    Repeater {
                        model: expenseCard.files
                        delegate: RButton {
                            required property var modelData
                            ui: page.ui
                            glyph: 0xE0CC
                            label: S.text_(modelData, "file_name") || "Sustento"
                            busy: page.app.busy("receivedAttachment:" + S.text_(modelData, "id"))
                            onActivated: page.openAttachment(S.text_(modelData, "id"))
                        }
                    }
                }
            }

            Text { visible: page.snapshot !== null; text: "Notas administrativas"; color: S.text; font.family: page.ui.fontFamily; font.pixelSize: 17 * page.ui.u; font.weight: Font.DemiBold }
            Repeater {
                model: page.notes
                delegate: Text {
                    required property var modelData
                    width: column.width
                    text: "• " + S.text_(modelData, "body") + "  (" + S.date(modelData.created_at) + (S.text_(modelData, "author_name").length ? " · " + modelData.author_name : "") + ")"
                    color: S.muted; wrapMode: Text.WordWrap
                    font.family: page.ui.fontFamily; font.pixelSize: 14 * page.ui.u
                }
            }
            RField {
                id: noteField
                width: parent.width
                ui: page.ui
                visible: page.snapshot !== null
                placeholder: "Escribe una nota para esta versión"
                maxLength: 2000
                onEdited: page.noteBody = text
            }
            RButton {
                ui: page.ui
                visible: page.snapshot !== null
                label: "Agregar nota"
                enabledButton: page.noteBody.trim().length >= 3
                busy: page.app.busy("receivedAddNote")
                onActivated: page.addNote()
            }

            Text { visible: page.activity.length > 0; text: "Actividad"; color: S.text; font.family: page.ui.fontFamily; font.pixelSize: 17 * page.ui.u; font.weight: Font.DemiBold }
            Repeater {
                model: page.activity
                delegate: Text {
                    required property var modelData
                    width: column.width
                    text: "• " + S.date(modelData.created_at) + " · " + (S.text_(modelData, "summary") || S.text_(modelData, "message") || S.text_(modelData, "event_type") || S.text_(modelData, "action"))
                    color: S.muted; wrapMode: Text.WordWrap
                    font.family: page.ui.fontFamily; font.pixelSize: 13 * page.ui.u
                }
            }
        }
    }
}

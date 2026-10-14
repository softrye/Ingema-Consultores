import QtQuick
import QtQuick.Controls
import QtQuick.Dialogs
import "RStyle.js" as S

// Alta / edición de un gasto con sus sustentos. Validación en C++
// (RenditionValidation), guardado con saveExpense (outbox, CAS por
// expectedExpenseRowVersion) y sustentos con attachSupport (reserve ->
// upload -> finalize del flujo existente). Sin IA: todo se completa a mano.
Item {
    id: page
    property var app
    property string renditionLocalId: ""
    property string expenseLocalId: ""
    readonly property var ui: app.ui
    readonly property var ctl: app.ctl
    readonly property var life: ({ alive: true })
    readonly property var rendition: {
        if (String(app.st.selectedLocalId || "") === renditionLocalId && app.st.current) return app.st.current
        return ({})
    }
    readonly property var expense: {
        var id = savedId.length ? savedId : expenseLocalId
        var rows = app.st.expenses || []
        for (var i = 0; i < rows.length; ++i) if (rows[i].localId === id) return rows[i]
        return null
    }
    readonly property bool writable: ctl.canEdit(rendition) && !(expense && expense.archived === true)
    readonly property string title: expenseLocalId.length ? (writable ? "Editar gasto" : "Detalle del gasto") : "Nuevo gasto"
    readonly property string draftKey: "expense:" + renditionLocalId + ":" + (expenseLocalId.length ? expenseLocalId : "new")
    readonly property string saveKey: "expense:" + renditionLocalId

    property string savedId: ""
    property string intentId: ""
    property string projectId: ""
    property string expenseDate: ""
    property string categoryCode: ""
    property string currencyCode: "PEN"
    property string paymentMethodCode: ""
    property string supportTypeCode: ""
    property var pending: []                 // sustentos aún no entregados al almacén
    property string error: ""
    property bool saving: false
    property bool finished: false
    property bool restored: false
    property bool waitingPhoto: false

    readonly property var textFields: ["amount", "concept", "beneficiary", "ruc", "supportNumber",
                                       "paymentMethodDetail", "subtotal", "igv", "justification"]
    function fieldItem(name) {
        return ({ amount: amountField, concept: conceptField, beneficiary: beneficiaryField, ruc: rucField,
                  supportNumber: supportNumberField, paymentMethodDetail: paymentDetailField,
                  subtotal: subtotalField, igv: igvField, justification: justificationField })[name]
    }
    function catalogOptions(kind) {
        var rows = ctl.catalog(kind)
        return rows.map(function(r) {
            var code = S.text_(r, "code")
            return { value: code, label: S.text_(r, "label") || S.text_(r, "name") || S.text_(r, "description") || code }
        })
    }
    readonly property var projectOptions: (rendition.projectIds || []).map(function(id) {
        return { value: String(id), label: ctl.projectLabel(String(id)) }
    })

    function values() {
        var v = {
            clientIntentId: intentId, projectId: projectId, expenseDate: expenseDate, categoryCode: categoryCode,
            currencyCode: currencyCode, paymentMethodCode: paymentMethodCode, supportTypeCode: supportTypeCode
        }
        for (var i = 0; i < textFields.length; ++i) {
            var t = fieldItem(textFields[i]).text
            v[textFields[i]] = textFields[i] === "amount" ? t.replace(",", ".").trim() : t
        }
        return v
    }

    Component.onCompleted: {
        var draft = (app.st.editorDrafts || {})[draftKey]
        var source = draft && draft.intentId ? draft : (expense || {})
        restored = !!(draft && draft.intentId)
        intentId = S.text_(source, "intentId", "clientIntentId") || ctl.newId()
        savedId = restored ? String(draft.savedId || "") : ""
        projectId = S.text_(source, "projectId", "project_id") || String(rendition.primaryProjectId || "")
        expenseDate = S.text_(source, "expenseDate", "expense_date") || (rendition.periodStart <= ctl.today() && ctl.today() <= rendition.periodEnd ? ctl.today() : String(rendition.periodStart || ""))
        categoryCode = S.text_(source, "categoryCode", "category_code")
        currencyCode = S.text_(source, "currencyCode", "currency_code") || "PEN"
        paymentMethodCode = S.text_(source, "paymentMethodCode", "payment_method_code")
        supportTypeCode = S.text_(source, "supportTypeCode", "support_type_code")
        for (var i = 0; i < textFields.length; ++i) {
            var snake = textFields[i].replace(/[A-Z]/g, function(c) { return "_" + c.toLowerCase() })
            fieldItem(textFields[i]).text = S.text_(source, textFields[i], snake)
        }
        pending = restored ? (draft.pendingAttachments || []) : []
    }
    Component.onDestruction: life.alive = false

    function handleBack() { return false }

    function changed() {
        error = ""
        if (writable && !finished) autosave.restart()
    }
    Timer {
        id: autosave
        interval: 600
        onTriggered: {
            var draft = page.values()
            draft.intentId = page.intentId
            draft.savedId = page.savedId
            draft.pendingAttachments = page.pending
            draft.renditionLocalId = page.renditionLocalId
            page.app.call("saveEditorDraft", { key: page.draftKey, draft: draft }, "")
        }
    }

    // ------------------------------------------------------------ Sustentos
    function addFile(url, sourceKind) {
        var info = ctl.describeLocalFile(url)
        if (String(info.error).length) { error = info.error; return }
        var list = pending.slice()
        for (var i = 0; i < list.length; ++i)
            if (list[i].localUri === info.localUri) return
        info.sourceKind = sourceKind
        info.importedUrl = String(url)
        delete info.error
        list.push(info)
        pending = list
        changed()
    }
    function removePending(index) {
        var list = pending.slice()
        var item = list.splice(index, 1)[0]
        pending = list
        if (item && item.sourceKind !== "file" && typeof Perms !== "undefined" && Perms)
            Perms.releaseImportedPhoto(item.importedUrl)
        changed()
    }
    function requestPhoto(camera) {
        if (typeof Perms === "undefined" || !Perms) { error = "La cámara no está disponible en este equipo."; return }
        waitingPhoto = true
        if (camera) {
            if (Perms.setPhotoCaptureContext) Perms.setPhotoCaptureContext("renditions:" + intentId)
            Perms.capturePhoto(101)
        } else {
            Perms.pickPhoto(101)
        }
    }
    Connections {
        target: typeof Perms !== "undefined" ? Perms : null
        ignoreUnknownSignals: true
        function onPhotoSelected(targetIdx, localUrl, sourceKind) {
            if (targetIdx !== 101 || !page.waitingPhoto) return
            page.waitingPhoto = false
            page.addFile(localUrl, sourceKind)
        }
        function onPhotoSelectionCanceled(targetIdx, sourceKind) {
            if (targetIdx === 101) page.waitingPhoto = false
        }
        function onPhotoSelectionError(targetIdx, code, message) {
            if (targetIdx !== 101) return
            page.waitingPhoto = false
            page.error = String(message || code)
        }
    }
    FileDialog {
        id: fileDialog
        title: "Selecciona el comprobante"
        fileMode: FileDialog.OpenFile
        nameFilters: ["Comprobantes (*.pdf *.jpg *.jpeg *.png *.webp)"]
        onAccepted: page.addFile(selectedFile, "file")
    }

    // -------------------------------------------------------------- Guardar
    function save() {
        if (saving || !writable) return
        var v = values()
        var problem = ctl.amountError(v.amount)
        if (!problem.length) problem = ctl.expenseError(rendition, v)
        if (problem.length) { error = problem; return }
        saving = true
        error = ""
        autosave.stop()
        var args = { localId: renditionLocalId, expenseLocalId: savedId.length ? savedId : expenseLocalId,
                     expense: v, synchronize: true }
        if (!savedId.length && expenseLocalId.length && expense)
            args.expectedExpenseRowVersion = Number(expense.rowVersion || 0)
        var life = page.life
        app.call("saveExpense", args, saveKey, function(ok, result, code, message) {
            if (!ok) {
                page.saving = false
                if (life.alive) page.error = page.app.errorText(code, message)
                return
            }
            page.savedId = String(result.localId || "")
            if (!page.savedId.length) {
                page.saving = false
                page.error = "No se confirmó la identidad del gasto."
                return
            }
            page.attachNext(life)
        })
    }
    // Un sustento a la vez; sólo se quita de la lista cuando el almacén lo confirma.
    function attachNext(life) {
        if (!pending.length) { finish(); return }
        var a = pending[0]
        app.call("attachSupport", {
            localId: renditionLocalId, expenseLocalId: savedId,
            attachment: { localUri: a.localUri, fileName: a.fileName, mimeType: a.mimeType, sizeBytes: a.sizeBytes,
                          clientIntentId: intentId + ":" + a.localUri, supportTypeCode: supportTypeCode,
                          documentNumber: supportNumberField.text }
        }, "attach:" + savedId, function(ok, result, code, message) {
            if (!ok) {
                page.saving = false
                page.error = "El gasto está guardado. " + page.app.errorText(code, message)
                page.changed()
                return
            }
            var list = page.pending.slice()
            var done = list.shift()
            page.pending = list
            if (done.sourceKind !== "file" && typeof Perms !== "undefined" && Perms)
                Perms.releaseImportedPhoto(done.importedUrl)
            page.attachNext(life)
        })
    }
    function finish() {
        finished = true
        saving = false
        app.call("saveEditorDraft", { key: draftKey, draft: {} }, "")
        app.toast("Gasto guardado en el equipo · pendiente de sincronizar con el servidor.", "success")
        if (life.alive) app.closePage()
    }

    Flickable {
        anchors.fill: parent
        contentWidth: width
        contentHeight: form.height + 160 * page.ui.u
        boundsBehavior: Flickable.StopAtBounds
        clip: true
        Column {
            id: form
            x: page.ui.gutter
            y: 8 * page.ui.u
            width: parent.width - 2 * page.ui.gutter
            spacing: 12 * page.ui.u

            Text {
                width: parent.width
                visible: page.restored
                text: "Se recuperaron los datos que estabas escribiendo."
                color: S.accentSoft; wrapMode: Text.WordWrap
                font.family: page.ui.fontFamily; font.pixelSize: 14 * page.ui.u
            }
            Text {
                width: parent.width
                visible: !page.writable
                text: "Gasto en solo lectura: la rendición no tiene permiso efectivo de edición."
                color: S.warning; wrapMode: Text.WordWrap
                font.family: page.ui.fontFamily; font.pixelSize: 14 * page.ui.u
            }
            Flow {
                width: parent.width
                spacing: 6 * page.ui.u
                visible: page.expense !== null
                RBadge {
                    ui: page.ui
                    readonly property string review: page.expense ? (S.text_(page.expense, "reviewStatus", "review_status") || "PENDIENTE").toUpperCase() : ""
                    label: review === "VALIDADO" ? "Validado" : review === "OBSERVADO" ? "Observado" : "Pendiente de revisión"
                    tone: review === "VALIDADO" ? S.success : review === "OBSERVADO" ? S.warning : S.muted
                }
                RBadge { ui: page.ui; label: page.expense ? page.ctl.syncLabel(S.text_(page.expense, "syncState")) : ""; tone: S.syncColor(page.expense ? page.expense.syncState : "") }
            }

            RSelect {
                width: parent.width; ui: page.ui; label: "Proyecto"; readOnly: !page.writable
                options: page.projectOptions; value: page.projectId
                onPicked: function(v) { page.projectId = v; page.changed() }
            }
            RDateField {
                width: parent.width; ui: page.ui; label: "Fecha del gasto"; readOnly: !page.writable
                value: page.expenseDate
                minimum: String(page.rendition.periodStart || ""); maximum: String(page.rendition.periodEnd || "")
                onPicked: function(v) { page.expenseDate = v; page.changed() }
            }
            RSelect {
                width: parent.width; ui: page.ui; label: "Categoría"; readOnly: !page.writable
                options: { page.app.st; return page.catalogOptions("CATEGORY") }
                value: page.categoryCode
                onPicked: function(v) { page.categoryCode = v; page.changed() }
            }
            RField { id: conceptField; width: parent.width; ui: page.ui; label: "Concepto"; placeholder: "Qué se compró o qué servicio se realizó"; readOnly: !page.writable; onEdited: page.changed() }
            RField { id: beneficiaryField; width: parent.width; ui: page.ui; label: "Proveedor o beneficiario"; readOnly: !page.writable; onEdited: page.changed() }
            RField { id: rucField; width: parent.width; ui: page.ui; label: "RUC (opcional)"; numeric: true; maxLength: 11; readOnly: !page.writable; onEdited: page.changed() }
            RSelect {
                width: parent.width; ui: page.ui; label: "Tipo de comprobante"; readOnly: !page.writable
                options: { page.app.st; return page.catalogOptions("SUPPORT_TYPE") }
                value: page.supportTypeCode
                onPicked: function(v) { page.supportTypeCode = v; page.changed() }
            }
            RField { id: supportNumberField; width: parent.width; ui: page.ui; label: "Número de comprobante"; placeholder: "Serie y número"; readOnly: !page.writable; onEdited: page.changed() }
            RSelect {
                width: parent.width; ui: page.ui; label: "Medio de pago"; readOnly: !page.writable
                options: { page.app.st; return page.catalogOptions("PAYMENT_METHOD") }
                value: page.paymentMethodCode
                onPicked: function(v) { page.paymentMethodCode = v; page.changed() }
            }
            RField { id: paymentDetailField; width: parent.width; ui: page.ui; label: "Detalle del pago (opcional)"; readOnly: !page.writable; onEdited: page.changed() }

            Text { text: "Moneda"; color: S.muted; font.family: page.ui.fontFamily; font.pixelSize: 13 * page.ui.u }
            Row {
                spacing: 8 * page.ui.u
                RChip { ui: page.ui; label: "Soles (PEN)"; selected: page.currencyCode === "PEN"; enabledChip: page.writable; onActivated: { page.currencyCode = "PEN"; page.changed() } }
                RChip { ui: page.ui; label: "Dólares (USD)"; selected: page.currencyCode === "USD"; enabledChip: page.writable; onActivated: { page.currencyCode = "USD"; page.changed() } }
            }
            RField {
                id: amountField; width: parent.width; ui: page.ui; label: "Importe total"; placeholder: "0.00"; numeric: true; readOnly: !page.writable
                error: text.length ? page.ctl.amountError(text) : ""
                onEdited: page.changed()
            }
            Row {
                width: parent.width
                spacing: 10 * page.ui.u
                RField { id: subtotalField; width: (parent.width - 10 * page.ui.u) / 2; ui: page.ui; label: "Subtotal (opcional)"; numeric: true; readOnly: !page.writable; onEdited: page.changed() }
                RField { id: igvField; width: (parent.width - 10 * page.ui.u) / 2; ui: page.ui; label: "IGV (opcional)"; numeric: true; readOnly: !page.writable; onEdited: page.changed() }
            }
            RField { id: justificationField; width: parent.width; ui: page.ui; label: "Justificación (opcional)"; placeholder: "Relación del gasto con el trabajo"; readOnly: !page.writable; onEdited: page.changed() }

            Text { text: "Sustentos"; color: S.text; font.family: page.ui.fontFamily; font.pixelSize: 17 * page.ui.u; font.weight: Font.DemiBold }
            Repeater {
                model: page.expense ? (page.expense.attachments || []).filter(function(a) { return !S.text_(a, "archived_at").length }) : []
                delegate: Text {
                    required property var modelData
                    width: form.width
                    text: "• " + (S.text_(modelData, "fileName", "file_name") || "Sustento") + " · "
                          + (S.text_(modelData, "phase") === "READY" ? "en el servidor" : page.ctl.syncLabel(S.text_(modelData, "syncState")))
                    color: S.muted; elide: Text.ElideRight
                    font.family: page.ui.fontFamily; font.pixelSize: 14 * page.ui.u
                }
            }
            Repeater {
                model: page.pending
                delegate: Row {
                    required property var modelData
                    required property int index
                    width: form.width
                    spacing: 8 * page.ui.u
                    Text {
                        width: parent.width - 110 * page.ui.u
                        anchors.verticalCenter: parent.verticalCenter
                        text: "• " + modelData.fileName + " · se adjunta al guardar"
                        color: S.accentSoft; elide: Text.ElideRight
                        font.family: page.ui.fontFamily; font.pixelSize: 14 * page.ui.u
                    }
                    RButton { ui: page.ui; label: "Quitar"; danger: true; width: 100 * page.ui.u; enabledButton: !page.saving; onActivated: page.removePending(index) }
                }
            }
            Flow {
                width: parent.width
                spacing: 8 * page.ui.u
                visible: page.writable
                RButton { ui: page.ui; glyph: 0xE064; label: "Tomar foto"; busy: page.waitingPhoto; enabledButton: !page.saving; onActivated: page.requestPhoto(true) }
                RButton { ui: page.ui; glyph: 0xE0F6; label: "Galería"; enabledButton: !page.saving && !page.waitingPhoto; onActivated: page.requestPhoto(false) }
                RButton { ui: page.ui; glyph: 0xE0CC; label: "PDF / archivo"; enabledButton: !page.saving; onActivated: fileDialog.open() }
            }

            Text {
                width: parent.width
                visible: page.error.length > 0
                text: page.error
                color: S.danger; wrapMode: Text.WordWrap
                font.family: page.ui.fontFamily; font.pixelSize: 14 * page.ui.u
            }
            RButton {
                width: parent.width
                ui: page.ui
                visible: page.writable
                primary: true
                glyph: 0xE14D
                label: page.savedId.length && page.pending.length ? "Reintentar sustentos" : "Guardar gasto"
                busy: page.saving
                onActivated: page.save()
            }
        }
    }
}

pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Dialogs
import "RStyle.js" as S

// Formulario compacto de gasto (imagen 2): gasto expandido en la lista y
// formulario rápido del "+" del Dock. NO es otro motor: usa exactamente los
// comandos del bridge que usa Nuevo gasto (saveExpense con CAS por
// expectedExpenseRowVersion, attachSupport, archiveAttachment, attachmentAccess)
// y la validación C++ (amountError / expenseError). Subtotal e IGV se conservan
// del gasto original y siguen disponibles en el editor completo.
Column {
    id: form
    property var app
    property string renditionLocalId: ""
    property var expense: null                  // null = gasto nuevo
    property bool showAttachments: true
    property bool modalEditor: false
    property int section: 0
    property bool restoredDraft: false
    property string previewUrl: ""
    property string previewName: ""
    readonly property bool dirty: editRevision > 0 || pending.length > 0 || restoredDraft
    readonly property string displayConcept: conceptField.text
    readonly property string displayAmount: amountField.text
    // Posición de la barra de secciones (el editor modal la fija arriba al bajar).
    readonly property real tabsBarY: editorTabs.parent ? editorTabs.parent.y : 0
    readonly property real tabsBarHeight: editorTabs.parent ? editorTabs.parent.height : 0
    signal finished(bool saved)
    signal deleteRequested()
    signal openFullForm()             // RUC, IGV, número de comprobante, sustentos con cámara…
    readonly property var ui: app.ui
    readonly property var ctl: app.ctl
    readonly property bool isNew: !expense
    readonly property var rendition: String(app.st.selectedLocalId || "") === renditionLocalId && app.st.current ? app.st.current : ({})
    readonly property bool writable: ctl.canEdit(rendition) && !(expense && expense.archived === true)
                                     && ["CONFLICT", "NEEDS_RECONCILIATION"].indexOf(String(rendition.syncState || "")) < 0
    readonly property string busyKey: "quick:" + renditionLocalId + ":" + (expense ? expense.localId : "new")
    readonly property var life: ({ alive: true })
    Component.onDestruction: life.alive = false
    spacing: 10 * ui.u

    property string intentId: ""
    property string expenseDate: ""
    property string currencyCode: "PEN"
    property string projectId: ""
    property string categoryCode: ""
    property string paymentMethodCode: ""
    property string supportTypeCode: ""
    property string error: ""
    property bool saving: false
    property bool applying: false
    property bool ready: false
    property bool completedSave: false
    property bool suspendedForAdvanced: false
    property var preservedValues: ({})
    property int editRevision: 0
    property int baseRowVersion: 0
    property string savedId: ""
    // Misma copia local que ExpenseEditor: no hay un segundo borrador competidor.
    readonly property string draftKey: "expense:" + renditionLocalId + ":" + expenseKey
    property var pending: []                     // archivos elegidos para un gasto nuevo

    function v(key, snake) { return expense ? S.text_(expense, key, snake) : "" }
    function load(ignoreDraft) {
        if (!ready) return
        autosave.stop()
        applying = true
        editRevision = 0
        var draft = ignoreDraft === true ? null : (app.st.editorDrafts || {})[draftKey]
        restoredDraft = !!(draft && draft.intentId)
        completedSave = false
        intentId = v("clientIntentId", "client_intent_id") || ctl.newId()
        var today = ctl.today()
        expenseDate = v("expenseDate", "expense_date") || defaultDate()
        currencyCode = v("currencyCode", "currency_code") || "PEN"
        projectId = v("projectId", "project_id") || String(rendition.primaryProjectId || "")
        categoryCode = v("categoryCode", "category_code")
        paymentMethodCode = v("paymentMethodCode", "payment_method_code")
        supportTypeCode = v("supportTypeCode", "support_type_code")
        conceptField.text = v("concept")
        var savedAmount = v("amount")
        amountField.text = savedAmount.length && !isNaN(Number(savedAmount)) ? Number(savedAmount).toFixed(2) : savedAmount
        beneficiaryField.text = v("beneficiary"); notesField.text = v("justification")
        supportNumberField.text = v("supportNumber", "support_number")
        rucField.text = v("ruc"); supportDetailField.text = v("supportDetail", "support_detail")
        paymentDetailField.text = v("paymentMethodDetail", "payment_method_detail")
        baseRowVersion = Number(expense ? expense.rowVersion || 0 : 0)
        preservedValues = { subtotal: v("subtotal"), igv: v("igv") }
        savedId = ""
        error = ""; pending = []
        if (draft && draft.intentId) {
            intentId = String(draft.intentId)
            savedId = String(draft.savedId || "")
            if (draft.baseRowVersion !== undefined) baseRowVersion = Number(draft.baseRowVersion)
            preservedValues = { subtotal: String(draft.subtotal === undefined ? preservedValues.subtotal : draft.subtotal),
                                igv: String(draft.igv === undefined ? preservedValues.igv : draft.igv) }
            expenseDate = String(draft.expenseDate || expenseDate)
            currencyCode = String(draft.currencyCode || "PEN")
            projectId = String(draft.projectId || ""); categoryCode = String(draft.categoryCode || "")
            supportTypeCode = String(draft.supportTypeCode || ""); paymentMethodCode = String(draft.paymentMethodCode || "")
            conceptField.text = String(draft.concept || ""); amountField.text = String(draft.amount || "")
            beneficiaryField.text = String(draft.beneficiary || ""); notesField.text = String(draft.justification || "")
            rucField.text = String(draft.ruc || ""); supportNumberField.text = String(draft.supportNumber || "")
            supportDetailField.text = String(draft.supportDetail || ""); paymentDetailField.text = String(draft.paymentMethodDetail || "")
            pending = draft.pendingAttachments || []
        }
        loadedKey = expenseKey
        applying = false
    }
    Component.onCompleted: { ready = true; load() }
    function defaultDate() {
        var today = ctl.today(), start = String(rendition.periodStart || ""), end = String(rendition.periodEnd || "")
        return start.length && end.length && !(start <= today && today <= end) ? start : today
    }
    onRenditionChanged: {
        if (!ready || applying || saving) return
        var wasApplying = applying
        applying = true                                    // completar no cuenta como edición
        if (!expenseDate.length && String(rendition.periodStart || "").length) expenseDate = defaultDate()
        if (!projectId.length && String(rendition.primaryProjectId || "").length) projectId = String(rendition.primaryProjectId)
        applying = wasApplying
    }
    // La identidad cambia al elegir otro gasto; una publicación/CAS no pisa la edición.
    property string loadedKey: ""
    readonly property string expenseKey: expense ? String(expense.localId) : "new"
    onExpenseKeyChanged: if (!saving && expenseKey !== loadedKey) load()
    onRenditionLocalIdChanged: if (!saving) load()
    onVisibleChanged: {
        if (visible && suspendedForAdvanced && !saving) {
            suspendedForAdvanced = false
            load()
        }
    }
    function changed() {
        if (!ready || applying) return
        editRevision++
        error = ""
        autosave.restart()
    }
    function persistLocal(done, quiet) {
        autosave.stop()
        if (!ready || completedSave || !renditionLocalId.length) { if (done) done(true); return }
        if (!dirty && !saving && !savedId.length) { if (done) done(true); return }
        var draft = values()
        draft.intentId = intentId; draft.savedId = savedId; draft.baseRowVersion = baseRowVersion
        draft.pendingAttachments = pending.slice(); draft.renditionLocalId = renditionLocalId
        var key = draftKey
        var requestId = app.call("saveEditorDraft", { key: key, draft: draft, quiet: quiet === true }, "", function(ok, result, code, message) {
            if (!form.life.alive || form.draftKey !== key) return
            if (!ok) form.error = form.app.errorText(code, message) || "No se pudo conservar la copia local. Mantén abierto el formulario y reintenta."
            if (done) done(ok)
        })
        if (!String(requestId || "").length) {
            error = "No se pudo iniciar la copia local. Mantén abierto el formulario y reintenta."
            if (done) done(false)
        }
    }
    function requestClose() {
        if (imagePreview.opened) { imagePreview.close(); return }
        if (saving) return
        if (form.app && form.app.ctl) form.app.ctl.resolveIssue("expenseForm")   // al cerrar se retira el aviso
        if (!modalEditor) { persistLocal(); finished(false); return }
        if (!dirty && (completedSave || !savedId.length)) { finished(false); return }
        // Puede existir un ID ya guardado con adjuntos sin confirmar; no cerrar
        // hasta recibir el acuse de la copia local aunque no haya nuevas teclas.
        if (!dirty) {
            var cleanRevision = editRevision
            persistLocal(function(ok) {
                if (ok && editRevision === cleanRevision && !saving) finished(false)
            })
            return
        }
        app.confirm("Cerrar edición", "Hay cambios sin guardar. Se conservará una copia local para continuar después.",
                    "Conservar y cerrar", false, function() {
            var revision = form.editRevision
            form.persistLocal(function(ok) {
                if (ok && form.editRevision === revision && !form.saving) form.finished(false)
                else if (ok) form.error = "Hay cambios posteriores. Cierra de nuevo para conservarlos."
            })
        })
    }
    // ---- Editor modal (rediseño aprobado): iconos por catálogo, faltante real
    // del validador C++ (sin reglas nuevas) y sección a la que lleva.
    function labelOf(kind, code) {
        var rows = options(kind)
        for (var i = 0; i < rows.length; ++i) if (rows[i].value === code) return rows[i].label
        return ""
    }
    function glyphFor(kind, label) {
        var l = String(label || "").toLowerCase()
        function has(words) { return words.some(function(w) { return l.indexOf(w) >= 0 }) }
        if (kind === "CATEGORY")
            return has(["aliment", "comida"]) ? 0xE2F6 : has(["transport", "pasaje", "taxi", "movil"]) ? 0xE1D4
                 : has(["hosped"]) ? 0xE2C1 : has(["peaje"]) ? 0xE298 : has(["combust"]) ? 0xE2AF
                 : has(["material"]) ? 0xE129 : has(["comunic", "telef"]) ? 0xE133 : has(["equipo"]) ? 0xE11D
                 : has(["administr"]) ? 0xE062 : has(["banc", "comisi"]) ? 0xE23A : has(["servicio"]) ? 0xE1B1
                 : has(["otro"]) ? 0xE0B6 : 0xE0CC
        if (kind === "PAYMENT_METHOD")
            return has(["efectivo"]) ? 0xE052 : has(["yape", "plin", "billetera"]) ? 0xE163
                 : has(["tarjeta", "débito", "debito", "crédito", "credito"]) ? 0xE0AA : has(["transfer"]) ? 0xE146
                 : has(["depósito", "deposito"]) ? 0xE23A : 0xE0B6
        return has(["sin sustento", "declara"]) ? 0xE12F : has(["factura"]) ? 0xE0CC : has(["boleta"]) ? 0xE3D3
             : has(["honorario"]) ? 0xE19F : has(["ticket"]) ? 0xE20F : has(["operaci", "banc"]) ? 0xE23A : 0xE0C8
    }
    readonly property bool dateOutOfRange: expenseDate.length > 0
        && ((String(rendition.periodStart || "").length && expenseDate < String(rendition.periodStart))
            || (String(rendition.periodEnd || "").length && expenseDate > String(rendition.periodEnd)))
    readonly property bool declarationSupport: labelOf("SUPPORT_TYPE", supportTypeCode).toLowerCase().indexOf("sin sustento") >= 0
    readonly property string problem: {
        editRevision; categoryCode; paymentMethodCode; supportTypeCode; currencyCode; projectId; expenseDate
        if (!ready || !modalEditor) return ""
        var current = values()
        var p = ctl.amountError(current.amount)
        return p.length ? p : ctl.expenseError(rendition, current)
    }
    readonly property string problemKey: { var m = /Falta completar: (\w+)/.exec(problem); return m ? m[1] : (problem.length ? "amount" : "") }
    readonly property int problemSection: ({ supportTypeCode: 1, paymentMethodCode: 2 })[problemKey] || 0
    readonly property string problemText: {
        var labels = { categoryCode: "categoría", paymentMethodCode: "medio de pago", supportTypeCode: "tipo de comprobante", concept: "concepto" }
        var m = /Falta completar: (\w+)/.exec(problem)
        return m ? "Falta: " + (labels[m[1]] || m[1]) : problem
    }
    function selectSection(index) {
        if (section === index) return
        Qt.inputMethod.hide()
        section = index
    }
    // Copia local silenciosa mientras se escribe: no republica el estado (sin parpadeo ni saltos).
    // Gasto nuevo: el cursor empieza en «Concepto» (arriba de la tarjeta).
    Timer { id: focusConceptLater; interval: 320; onTriggered: conceptField.focusField() }
    function focusConcept() { if (writable) focusConceptLater.restart() }
    Timer { id: autosave; interval: 900; onTriggered: form.persistLocal(null, true) }
    onExpenseDateChanged: changed()
    onCurrencyCodeChanged: changed()
    onProjectIdChanged: changed()
    onCategoryCodeChanged: changed()
    onPaymentMethodCodeChanged: changed()
    onSupportTypeCodeChanged: changed()
    function openAdvanced() {
        if (saving) return
        var targetId = savedId || (expense ? String(expense.localId) : "")
        var draft = values()
        draft.intentId = intentId; draft.savedId = savedId; draft.pendingAttachments = pending.slice()
        draft.renditionLocalId = renditionLocalId
        draft.baseRowVersion = baseRowVersion
        var key = "expense:" + renditionLocalId + ":" + (targetId || "new")
        app.call("saveEditorDraft", { key: key, draft: draft }, "", function(ok, result, code, message) {
            if (!form.life.alive) return
            if (!ok) { form.error = form.app.errorText(code, message); return }
            form.suspendedForAdvanced = true
            form.app.closeMenus()
            form.app.openExpense(form.renditionLocalId, targetId)
        })
    }

    function options(kind) {
        return ctl.catalog(kind).map(function(r) {
            var code = S.text_(r, "code")
            return { value: code, label: S.text_(r, "name") || S.text_(r, "label") || code }
        })
    }
    function values() {
        var base = {}
        base.subtotal = String(preservedValues.subtotal || "")
        base.igv = String(preservedValues.igv || "")
        base.clientIntentId = intentId; base.projectId = projectId; base.expenseDate = expenseDate
        base.categoryCode = categoryCode; base.currencyCode = currencyCode; base.paymentMethodCode = paymentMethodCode
        base.supportTypeCode = supportTypeCode; base.concept = conceptField.text
        base.amount = amountField.text.replace(",", ".").trim(); base.beneficiary = beneficiaryField.text
        base.justification = notesField.text
        base.ruc = rucField.text; base.supportNumber = supportNumberField.text
        base.supportDetail = supportDetailField.text; base.paymentMethodDetail = paymentDetailField.text
        return base
    }
    function save() {
        if (saving || !writable) return
        var values = form.values()
        var problem = ctl.amountError(values.amount)
        if (!problem.length) problem = ctl.expenseError(rendition, values)
        if (problem.length && !String(values.expenseDate || "").length && problem.indexOf("fecha") >= 0)
            problem = "Falta la fecha del gasto."                 // no «fuera del período» si está vacía
        if (problem.length) {
            var labels = { categoryCode: "Categoría", paymentMethodCode: "Medio de pago", supportTypeCode: "Tipo de comprobante", concept: "Concepto" }
            error = problem.replace(/Falta completar: (\w+)\./, function(m, k) { return "Falta completar: " + (labels[k] || k) + "." })
            // Se avisa y se lleva a la pestaña del dato que falta (antes no había aviso visible).
            var tabs = { supportTypeCode: 1, paymentMethodCode: 2 }
            var m = /Falta completar: (\w+)\./.exec(problem)
            if (m && tabs[m[1]] !== undefined) section = tabs[m[1]]
            else if (m) section = 0
            else if (problem.indexOf("Justificación:") === 0) { section = 1; notesField.forceActiveFocus() }
            else if (problem.indexOf("Detalle del comprobante:") === 0) { section = 1; supportDetailField.focusField() }
            else if (problem.indexOf("Detalle de pago:") === 0) { section = 2; paymentDetailField.focusField() }
            // El dato faltante del encabezado recibe el foco: se ve y se escribe al instante.
            if (m && m[1] === "concept") conceptField.focusField()
            else if (!m && ctl.amountError(values.amount).length) amountField.focusField()
            // Aura ámbar (atención): incidencia localizada y corregible.
            if (form.app && form.app.ctl)
                form.app.ctl.reportIssue("expenseForm", { what: error, area: "Gastos", title: "Gasto incompleto",
                                                          severity: "attention", renditionLocalId: renditionLocalId })
            return
        }
        saving = true; error = ""
        if (form.app && form.app.ctl) form.app.ctl.resolveIssue("expenseForm")
        autosave.stop()
        persistLocal()
        var revision = editRevision
        var args = { localId: renditionLocalId, expenseLocalId: savedId || (expense ? String(expense.localId) : ""), expense: values, synchronize: true }
        if (expense || savedId.length) args.expectedExpenseRowVersion = baseRowVersion
        var life = form.life
        var requestId = app.call("saveExpense", args, busyKey, function(ok, result, code, message) {
            if (!life.alive) return
            if (!ok) { form.saving = false; form.error = form.app.errorText(code, message) || "No se pudo guardar el gasto."; return }
            var localId = String(result.localId || "")
            if (!localId.length) { form.saving = false; form.error = "No se confirmó la identidad del gasto."; return }
            form.savedId = localId
            var rows = form.app.st.expenses || []
            for (var i = 0; i < rows.length; ++i)
                if (String(rows[i].localId) === localId) form.baseRowVersion = Number(rows[i].rowVersion || 0)
            form.persistLocal()
            form.attachPending(localId, function() {
                form.saving = false
                if (form.editRevision !== revision) {
                    form.persistLocal()
                    form.error = "Se guardó la versión enviada. Hay cambios posteriores; pulsa Guardar para conservarlos."
                    return
                }
                form.completedSave = true
                form.app.call("saveEditorDraft", { key: form.draftKey, draft: {} }, "")
                form.finished(true)
            })
        })
        if (!String(requestId || "").length) { saving = false; error = "Ya hay una operación en curso. Tus cambios se conservan." }
    }
    function attachFile(expenseLocalId, info, done) {
        var requestId = app.call("attachSupport", {
            localId: renditionLocalId, expenseLocalId: expenseLocalId,
            attachment: { localUri: info.localUri, fileName: info.fileName, mimeType: info.mimeType, sizeBytes: info.sizeBytes,
                          clientIntentId: intentId + ":" + info.localUri, supportTypeCode: supportTypeCode,
                          documentNumber: supportNumberField.text }
        }, "attach:" + expenseLocalId, function(ok, result, code, message) {
            if (!form.life.alive) return
            if (!ok) form.error = "El gasto está guardado; falta adjuntar «" + info.fileName + "». " + form.app.errorText(code, message)
            if (done) done(ok)
        })
        if (!String(requestId || "").length) { form.error = "No se pudo iniciar el adjunto; se conserva para reintentar."; if (done) done(false) }
    }
    function attachPending(expenseLocalId, done) {
        if (!pending.length || !expenseLocalId.length) { done(); return }
        var next = pending[0]
        attachFile(expenseLocalId, next, function(ok) {
            if (!ok || !form.life.alive) { form.saving = false; return }
            form.pending = form.pending.filter(function(p) { return p.localUri !== next.localUri })
            form.persistLocal()
            form.attachPending(expenseLocalId, done)
        })
    }
    function addFile(url) {
        var info = ctl.describeLocalFile(url)
        if (String(info.error || "").length) { error = info.error; return }
        delete info.error
        if (!pending.some(function(p) { return p.localUri === info.localUri })) pending = pending.concat([info])
        changed(); persistLocal()
    }
    FileDialog {
        id: fileDialog
        title: "Selecciona el comprobante"
        fileMode: FileDialog.OpenFile
        nameFilters: ["Comprobantes (*.pdf *.jpg *.jpeg *.png *.webp)"]
        onAccepted: form.addFile(selectedFile)
    }

    // ---- Comprobantes del gasto (servidor + en cola + nuevos), con ver / retirar.
    readonly property var attachmentExpense: {
        if (expense) return expense
        var rows = app.st.expenses || []
        for (var i = 0; i < rows.length; ++i) if (savedId.length && String(rows[i].localId) === savedId) return rows[i]
        return null
    }
    readonly property var files: {
        var rows = [], i
        var saved = attachmentExpense ? attachmentExpense.attachments || [] : []
        var rid = attachmentExpense ? S.text_(attachmentExpense, "remoteId") : ""
        var remote = rid.length ? (app.st.attachments || []).filter(function(a) {
            return S.text_(a, "expense_id", "expenseId") === rid && !S.text_(a, "archived_at").length }) : []
        for (i = 0; i < remote.length; ++i) {
            var remoteId = S.text_(remote[i], "id")
            var mirror = saved.filter(function(a) { return S.text_(a, "remoteId") === remoteId })[0] || {}
            rows.push({ kind: "remote", id: S.text_(remote[i], "id"), name: S.text_(remote[i], "file_name", "fileName") || "Sustento",
                        size: Number(remote[i].size_bytes || remote[i].sizeBytes || 0), uri: S.text_(mirror, "localUri"), data: remote[i] })
        }
        var local = saved.filter(function(a) {
            return !S.text_(a, "archived_at").length && !remote.some(function(r) { return S.text_(a, "remoteId").length && S.text_(a, "remoteId") === S.text_(r, "id") }) })
        for (i = 0; i < local.length; ++i)
            rows.push({ kind: "local", name: S.text_(local[i], "fileName", "file_name") || "Sustento",
                        size: Number(local[i].sizeBytes || 0), uri: S.text_(local[i], "localUri"),
                        state: S.text_(local[i], "phase") === "READY" ? "" : "pendiente de subir" })
        for (i = 0; i < pending.length; ++i)
            rows.push({ kind: "pending", index: i, name: pending[i].fileName, size: Number(pending[i].sizeBytes || 0),
                        uri: String(pending[i].localUri || ""), state: "se adjunta al guardar" })
        return rows
    }
    function sizeText(b) { return b <= 0 ? "" : b >= 1048576 ? (b / 1048576).toFixed(1) + " MB" : Math.max(1, Math.round(b / 1024)) + " KB" }
    function localUrl(value) {
        var path = String(value || "").replace(/\\/g, "/")
        if (!path.length) return ""
        return /^(file|content|https?):/i.test(path) ? path : "file:///" + path.replace(/^\/+/, "")
    }
    function openFileUrl(row, url, download) {
        if (!download && /\.(jpe?g|png|webp)$/i.test(String(row.name || ""))) {
            previewName = row.name
            previewUrl = url
            imagePreview.open()
        } else Qt.openUrlExternally(url)
    }
    function viewFile(row, download) {
        if (row.kind === "remote") {
            app.call("attachmentAccess", { attachmentId: row.id }, "access:" + row.id, function(ok, result, code, message) {
                if (!ok) { form.error = form.app.errorText(code, message) || "No se pudo abrir el comprobante."; return }
                var r = (result.rows || [])[0] || {}
                if (!form.life.alive) return
                if (String(r.signedUrl || "").length) form.openFileUrl(row, r.signedUrl, download === true)
                else form.error = "El servidor no devolvió un acceso al comprobante."
            })
        } else if (String(row.uri || "").length) {
            openFileUrl(row, localUrl(row.uri), download === true)
        }
    }
    Popup {
        // Entrada/salida suaves (fundido + leve escala), como el resto de hojas.
        enter: Transition { NumberAnimation { property: "opacity"; from: 0; to: 1; duration: 180; easing.type: Easing.OutCubic }
                            NumberAnimation { property: "scale"; from: 0.96; to: 1; duration: 220; easing.type: Easing.OutCubic } }
        exit: Transition { NumberAnimation { property: "opacity"; from: 1; to: 0; duration: 140; easing.type: Easing.InCubic } }
        id: imagePreview
        parent: Overlay.overlay
        modal: true; dim: true; focus: true
        width: parent ? Math.min(parent.width - 24 * form.ui.u, 800 * form.ui.u) : 0
        height: parent ? Math.min(parent.height - 40 * form.ui.u, 680 * form.ui.u) : 0
        x: parent ? (parent.width - width) / 2 : 0
        y: parent ? (parent.height - height) / 2 : 0
        padding: 14 * form.ui.u
        background: Rectangle { radius: 24 * form.ui.u; color: S.popup; border.width: 1; border.color: S.edge(1) }
        onClosed: form.previewUrl = ""
        contentItem: Item {
            Text { width: parent.width - 50 * form.ui.u; text: form.previewName; elide: Text.ElideMiddle
                   font.family: form.ui.fontFamily; font.pixelSize: 14 * form.ui.u; color: S.text }
            RButton { anchors.right: parent.right; ui: form.ui; width: 44 * form.ui.u; height: width; glyph: 0xE1B2
                      Accessible.name: "Cerrar vista previa"; onActivated: imagePreview.close() }
            Image { anchors.fill: parent; anchors.topMargin: 52 * form.ui.u; source: form.previewUrl
                    asynchronous: true; fillMode: Image.PreserveAspectFit }
        }
    }
    function removeFile(row) {
        if (saving) return
        if (row.kind === "pending") { pending = pending.filter(function(p) { return p.localUri !== row.uri }); changed(); persistLocal(); return }
        if (row.kind !== "remote" || !writable) return
        app.confirm("Retirar comprobante", "Se archivará «" + row.name + "» en el servidor. La versión presentada conserva su copia.", "Retirar", true, function() {
            form.app.call("archiveAttachment", { attachmentId: row.id, rowVersion: Number(row.data.row_version || row.data.rowVersion || 0) },
                          "archive:" + row.id, function(ok, result, code, message) {
                if (!ok) form.error = form.app.errorText(code, message) || "No se pudo retirar el comprobante."
            })
        })
    }

    // Una sola instancia de cada entrada; las secciones sólo cambian visibilidad.
    component FieldBox: Rectangle {
        id: box
        property int glyph: 0
        default property alias fields: fieldBody.data
        property alias body: fieldBody
        implicitHeight: fieldBody.implicitHeight + (form.modalEditor ? 18 : 0) * form.ui.u
        radius: 18 * form.ui.u
        color: form.modalEditor ? S.cardGlass : "transparent"
        border.width: form.modalEditor ? 1 : 0
        border.color: S.edge(1)
        data: [
            Rectangle {
                x: 8 * form.ui.u; anchors.verticalCenter: parent.verticalCenter
                width: 30 * form.ui.u; height: width; radius: 10 * form.ui.u
                visible: form.modalEditor
                color: S.tintSoft
                Text { anchors.centerIn: parent; text: String.fromCharCode(box.glyph); color: S.accent
                       font.family: form.ui.iconFamily; font.pixelSize: 21 * form.ui.u }
            },
            Column {
                id: fieldBody
                x: (form.modalEditor ? 46 : 0) * form.ui.u
                y: (form.modalEditor ? 9 : 0) * form.ui.u
                width: box.width - x - (form.modalEditor ? 9 : 0) * form.ui.u
                spacing: 4 * form.ui.u
            }
        ]
    }
    component OptionGrid: Grid {
        id: optionGrid
        property string kind: ""
        property string value: ""
        property bool tall: true
        signal picked(string value)
        width: parent ? parent.width : 0
        columns: tall ? 4 : 2
        spacing: 6 * form.ui.u
        Repeater {
            model: { form.app.st; return form.options(optionGrid.kind) }
            delegate: Rectangle {
                id: optionTile
                required property var modelData
                readonly property bool on: optionGrid.value === modelData.value
                readonly property int glyph: form.glyphFor(optionGrid.kind, modelData.label)
                width: (optionGrid.width - (optionGrid.columns - 1) * optionGrid.spacing) / optionGrid.columns
                height: (optionGrid.tall ? 76 : 50) * form.ui.u
                scale: optionTap.pressed ? 0.94 : 1
                Behavior on scale { enabled: form.ui.reducedMotion !== true; NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
                transform: Scale { id: optionPop; origin.x: optionTile.width / 2; origin.y: optionTile.height / 2 }
                onOnChanged: if (on && form.ui.reducedMotion !== true) optionPopAnim.restart()
                SequentialAnimation {
                    id: optionPopAnim
                    ParallelAnimation {
                        NumberAnimation { target: optionPop; property: "xScale"; to: 1.07; duration: 110; easing.type: Easing.OutQuad }
                        NumberAnimation { target: optionPop; property: "yScale"; to: 1.07; duration: 110; easing.type: Easing.OutQuad }
                    }
                    ParallelAnimation {
                        NumberAnimation { target: optionPop; property: "xScale"; to: 1; duration: 260; easing.type: Easing.OutBack }
                        NumberAnimation { target: optionPop; property: "yScale"; to: 1; duration: 260; easing.type: Easing.OutBack }
                    }
                }
                radius: 14 * form.ui.u
                color: on ? Qt.rgba(6 / 255, 84 / 255, 162 / 255, 0.10) : (optionTap.pressed ? S.glass(0.9) : S.cardGlass)
                border.width: on ? 2 : 1
                border.color: on ? S.accent : S.edge(1)
                Behavior on color { ColorAnimation { duration: 120 } }
                Column {
                    visible: optionGrid.tall
                    anchors.centerIn: parent
                    width: parent.width - 6 * form.ui.u
                    spacing: 4 * form.ui.u
                    Text { anchors.horizontalCenter: parent.horizontalCenter; text: String.fromCharCode(optionTile.glyph); color: S.accent
                           font.family: form.ui.iconFamily; font.pixelSize: 22 * form.ui.u }
                    Text { width: parent.width; horizontalAlignment: Text.AlignHCenter; text: optionTile.modelData.label
                           color: optionTile.on ? S.accent : S.text; wrapMode: Text.WordWrap; maximumLineCount: 2; elide: Text.ElideRight
                           fontSizeMode: Text.HorizontalFit; minimumPixelSize: 8.5 * form.ui.u
                           font.family: form.ui.fontFamily; font.pixelSize: 11 * form.ui.u; font.weight: optionTile.on ? Font.Bold : Font.Normal }
                }
                Row {
                    visible: !optionGrid.tall
                    x: 10 * form.ui.u; anchors.verticalCenter: parent.verticalCenter
                    width: parent.width - 20 * form.ui.u; spacing: 10 * form.ui.u
                    Text { anchors.verticalCenter: parent.verticalCenter; text: String.fromCharCode(optionTile.glyph); color: S.accent
                           font.family: form.ui.iconFamily; font.pixelSize: 20 * form.ui.u }
                    Text { width: parent.width - 30 * form.ui.u; anchors.verticalCenter: parent.verticalCenter; text: optionTile.modelData.label
                           color: optionTile.on ? S.accent : S.text; wrapMode: Text.WordWrap; maximumLineCount: 2; elide: Text.ElideRight
                           font.family: form.ui.fontFamily; font.pixelSize: 13.5 * form.ui.u; font.weight: optionTile.on ? Font.Bold : Font.Normal }
                }
                MouseArea { id: optionTap; anchors.fill: parent; enabled: form.writable; onClicked: optionGrid.picked(optionTile.modelData.value) }
                Accessible.role: Accessible.RadioButton
                Accessible.name: modelData.label
                Accessible.checked: on
            }
        }
    }

    // ---- Tarjeta principal (sólo editor modal): concepto, monto con moneda,
    // fecha y proyecto siempre a la vista. Las entradas son las mismas
    // instancias del formulario (se reubican aquí), no copias.
    Rectangle {
        id: heroCard
        visible: form.modalEditor
        width: parent.width
        height: heroColumn.implicitHeight + 24 * form.ui.u
        radius: 22 * form.ui.u
        color: S.glass(0.78)
        border.width: 1.5; border.color: S.edge(1)
        Column {
            id: heroColumn
            x: 12 * form.ui.u; y: 12 * form.ui.u
            width: parent.width - 24 * form.ui.u
            spacing: 10 * form.ui.u
            Row {
                width: parent.width; spacing: 10 * form.ui.u
                Rectangle {
                    id: heroCategory
                    width: 48 * form.ui.u; height: width; radius: 14 * form.ui.u
                    anchors.bottom: parent.bottom; anchors.bottomMargin: 4 * form.ui.u
                    color: S.tintSoft; border.width: 1; border.color: S.edge(1)
                    Text { anchors.centerIn: parent; color: S.accent; font.family: form.ui.iconFamily; font.pixelSize: 26 * form.ui.u
                           text: String.fromCharCode(form.glyphFor("CATEGORY", form.labelOf("CATEGORY", form.categoryCode))) }
                    MouseArea { anchors.fill: parent; onClicked: form.selectSection(0) }
                    transform: Scale { id: heroPop; origin.x: 24 * form.ui.u; origin.y: 24 * form.ui.u }
                    SequentialAnimation {
                        id: heroPopAnim
                        ParallelAnimation {
                            NumberAnimation { target: heroPop; property: "xScale"; to: 0.82; duration: 90 }
                            NumberAnimation { target: heroPop; property: "yScale"; to: 0.82; duration: 90 }
                        }
                        ParallelAnimation {
                            NumberAnimation { target: heroPop; property: "xScale"; to: 1; duration: 320; easing.type: Easing.OutBack; easing.overshoot: 2.2 }
                            NumberAnimation { target: heroPop; property: "yScale"; to: 1; duration: 320; easing.type: Easing.OutBack; easing.overshoot: 2.2 }
                        }
                    }
                    Connections { target: form; function onCategoryCodeChanged() { if (form.ready && !form.applying && form.ui.reducedMotion !== true) heroPopAnim.restart() } }
                    Accessible.role: Accessible.Button
                    Accessible.name: "Categoría"
                }
                Item { id: heroConcept; width: parent.width - heroCategory.width - parent.spacing; height: conceptField.height }
            }
            Row {
                width: parent.width; spacing: 8 * form.ui.u
                Item { id: heroAmount; width: parent.width - currencySwitch.width - parent.spacing; height: amountField.height }
                Rectangle {
                    id: currencySwitch
                    objectName: "heroCurrency"
                    y: heroAmount.height - height
                    width: 112 * form.ui.u; height: 50 * form.ui.u; radius: 14 * form.ui.u
                    color: S.track
                    Rectangle {                                  // píldora deslizante del selector
                        readonly property real cell: (currencyRow.width - (2 - 1) * currencyRow.spacing) / Math.max(1, 2)
                        visible: true
                        x: currencyRow.x + (form.currencyCode === "USD" ? 1 : 0) * (cell + currencyRow.spacing)
                        y: currencyRow.y
                        width: cell; height: currencyRow.height; radius: 11 * form.ui.u
                        color: S.accent
                        Behavior on x { enabled: form.ui.reducedMotion !== true
                                        SpringAnimation { spring: 4.2; damping: 0.38; epsilon: 0.25 } }
                    }
                    Row {
                        id: currencyRow; anchors.fill: parent; anchors.margins: 3 * form.ui.u; spacing: 2 * form.ui.u
                        Repeater {
                            model: ["PEN", "USD"]
                            delegate: Rectangle {
                                required property string modelData
                                width: (currencyRow.width - currencyRow.spacing) / 2; height: currencyRow.height; radius: 11 * form.ui.u
                                color: "transparent"
                                Text { anchors.centerIn: parent; text: parent.modelData
                                       color: form.currencyCode === parent.modelData ? S.onAccent : S.text
                                       font.family: form.ui.fontFamily; font.pixelSize: 13 * form.ui.u; font.weight: Font.Bold }
                                MouseArea { anchors.fill: parent; enabled: form.writable; onClicked: form.currencyCode = parent.modelData }
                                Accessible.role: Accessible.RadioButton
                                Accessible.name: modelData
                            }
                        }
                    }
                }
            }
            Row {
                width: parent.width; spacing: 8 * form.ui.u
                Rectangle {
                    id: heroDate
                    width: heroDateRow.implicitWidth + 24 * form.ui.u; height: 44 * form.ui.u; radius: 12 * form.ui.u
                    color: heroDateTap.pressed ? S.tintSoft : form.dateOutOfRange ? Qt.rgba(198 / 255, 47 / 255, 62 / 255, 0.08) : S.glass(0.9)
                    border.width: form.dateOutOfRange ? 1.5 : 1; border.color: form.dateOutOfRange ? S.danger : S.fieldBorder
                    Behavior on color { ColorAnimation { duration: 200 } }
                    Row { id: heroDateRow; anchors.centerIn: parent; spacing: 8 * form.ui.u
                          Text { text: String.fromCharCode(0xE063); color: form.dateOutOfRange ? S.danger : S.accent; font.family: form.ui.iconFamily; font.pixelSize: 18 * form.ui.u }
                          Text { text: S.date(form.expenseDate); color: form.dateOutOfRange ? S.danger : S.text; font.family: form.ui.fontFamily; font.pixelSize: 14 * form.ui.u; font.weight: Font.DemiBold } }
                    MouseArea { id: heroDateTap; anchors.fill: parent; enabled: form.writable; onClicked: dateField.openPicker() }
                    Accessible.role: Accessible.Button
                    Accessible.name: "Fecha " + S.date(form.expenseDate)
                }
                Rectangle {
                    width: parent.width - heroDate.width - parent.spacing; height: 44 * form.ui.u; radius: 12 * form.ui.u
                    color: heroProjectTap.pressed ? S.tintSoft : S.glass(0.9); border.width: 1; border.color: S.fieldBorder
                    Text { x: 12 * form.ui.u; anchors.verticalCenter: parent.verticalCenter; text: String.fromCharCode(0xE0D7); color: S.accent
                           font.family: form.ui.iconFamily; font.pixelSize: 18 * form.ui.u }
                    Text { x: 38 * form.ui.u; width: parent.width - x - 30 * form.ui.u; anchors.verticalCenter: parent.verticalCenter
                           text: form.projectId.length ? form.ctl.projectLabel(form.projectId) : "Proyecto"; elide: Text.ElideRight
                           color: S.text; font.family: form.ui.fontFamily; font.pixelSize: 14 * form.ui.u; font.weight: Font.DemiBold }
                    Text { anchors.right: parent.right; anchors.rightMargin: 10 * form.ui.u; anchors.verticalCenter: parent.verticalCenter
                           text: String.fromCharCode(0xE06D); color: S.muted; font.family: form.ui.iconFamily; font.pixelSize: 16 * form.ui.u }
                    MouseArea { id: heroProjectTap; anchors.fill: parent; enabled: form.writable; onClicked: projectSelect.openSheet() }
                    Accessible.role: Accessible.ComboBox
                    Accessible.name: "Proyecto"
                }
            }
        }
    }
    Text {
        objectName: "heroDateHint"
        visible: form.modalEditor && form.dateOutOfRange
        width: parent.width; leftPadding: 4 * form.ui.u; wrapMode: Text.WordWrap
        text: "La fecha está fuera del período (" + S.date(String(form.rendition.periodStart || "")) + " – " + S.date(String(form.rendition.periodEnd || "")) + "). Toca la fecha para cambiarla."
        color: S.danger; font.family: form.ui.fontFamily; font.pixelSize: 12.5 * form.ui.u
    }
    // Secciones en una sola fila; punto ámbar donde está el faltante.
    Rectangle {
        visible: form.modalEditor
        width: parent.width; height: 52 * form.ui.u; radius: 16 * form.ui.u
        // Sticky tabs occlude the scrolled fields in both themes.
        color: S.dark ? S.surfaceStrong : S.track
        Rectangle {                                  // píldora deslizante del selector
            readonly property real cell: (editorTabs.width - (4 - 1) * editorTabs.spacing) / Math.max(1, 4)
            visible: true
            x: editorTabs.x + (form.section) * (cell + editorTabs.spacing)
            y: editorTabs.y
            width: cell; height: editorTabs.height; radius: 12 * form.ui.u
            color: S.pill()
            Behavior on x { enabled: form.ui.reducedMotion !== true
                            SpringAnimation { spring: 4.2; damping: 0.38; epsilon: 0.25 } }
        }
        // Un solo tamaño de letra para las cuatro pestañas: el justo para que «Comprobante» quepa.
        TextMetrics { id: tabMetrics; font.family: form.ui.fontFamily; font.pixelSize: 11 * form.ui.u; font.bold: true; text: "Comprobante" }
        Row {
            id: editorTabs
            readonly property real labelPx: Math.min(11 * form.ui.u, 11 * form.ui.u * ((width - 3 * spacing) / 4 - 8 * form.ui.u) / Math.max(1, tabMetrics.advanceWidth))
            objectName: "expenseEditorTabs"
            anchors.fill: parent; anchors.margins: 4 * form.ui.u
            spacing: 4 * form.ui.u
            Repeater {
                model: ["General", "Comprobante", "Pago", "Sustentos"]
                delegate: Rectangle {
                    id: sectionButton
                    required property string modelData
                    required property int index
                    objectName: "expenseEditorSection:" + index
                    readonly property bool selected: form.section === index
                    width: (editorTabs.width - 3 * editorTabs.spacing) / 4; height: editorTabs.height
                    radius: 12 * form.ui.u
                    color: "transparent"
                    Text { anchors.centerIn: parent; width: parent.width - 6 * form.ui.u; horizontalAlignment: Text.AlignHCenter
                           text: sectionButton.modelData; color: sectionButton.selected ? S.accent : S.text
                           elide: Text.ElideRight
                           font.family: form.ui.fontFamily; font.pixelSize: editorTabs.labelPx; font.weight: sectionButton.selected ? Font.Bold : Font.DemiBold }
                    Rectangle { visible: form.problem.length > 0 && form.problemSection === sectionButton.index && form.problemKey !== "amount" && form.problemKey !== "concept"
                                anchors.right: parent.right; anchors.rightMargin: 7 * form.ui.u; y: 6 * form.ui.u
                                width: 8 * form.ui.u; height: width; radius: width / 2; color: S.warning }
                    MouseArea { anchors.fill: parent; onClicked: form.selectSection(sectionButton.index) }
                    Accessible.role: Accessible.Button
                    Accessible.name: modelData
                    Accessible.checked: selected
                }
            }
        }
    }
    // Opciones de un toque sobre el catálogo real (sin listas desplegables).
    Text { visible: form.modalEditor && form.section < 3; text: ["Categoría", "Tipo de comprobante", "Medio de pago", ""][form.section]
           leftPadding: 4 * form.ui.u; color: S.text; font.family: form.ui.fontFamily; font.pixelSize: 13 * form.ui.u; font.weight: Font.Bold }
    OptionGrid { objectName: "categoryGrid"; visible: form.modalEditor && form.section === 0; kind: "CATEGORY"; value: form.categoryCode
                 onPicked: function(value) { form.categoryCode = value } }
    OptionGrid { objectName: "supportTypeGrid"; visible: form.modalEditor && form.section === 1; kind: "SUPPORT_TYPE"; tall: false
                 value: form.supportTypeCode; onPicked: function(value) { form.supportTypeCode = value } }
    OptionGrid { objectName: "paymentMethodGrid"; visible: form.modalEditor && form.section === 2; kind: "PAYMENT_METHOD"; value: form.paymentMethodCode
                 onPicked: function(value) { form.paymentMethodCode = value } }
    Grid {
        id: fieldsGrid
        width: parent.width
        columns: form.modalEditor && width >= 440 * form.ui.u ? 2 : 1
        spacing: 8 * form.ui.u
        readonly property real cellWidth: (width - (columns - 1) * spacing) / columns
        FieldBox {
            width: fieldsGrid.cellWidth; glyph: 0xE063
            visible: !form.modalEditor
            RDateField { id: dateField; width: parent.width; ui: form.ui; label: "Fecha"; value: form.expenseDate; readOnly: !form.writable
                         minimum: String(form.rendition.periodStart || ""); maximum: String(form.rendition.periodEnd || "")
                         onPicked: function(value) { form.expenseDate = value } }
        }
        FieldBox {
            id: conceptBox
            width: fieldsGrid.cellWidth; glyph: 0xE0C0; visible: !form.modalEditor
            RField { id: conceptField; parent: form.modalEditor ? heroConcept : conceptBox.body; objectName: "quickConceptInput"; width: parent.width; ui: form.ui; formStyle: form.modalEditor; label: "Concepto"; placeholder: "Describe el gasto…"
                     readOnly: !form.writable; onEdited: form.changed() }
        }
        FieldBox {
            id: amountBox
            width: fieldsGrid.cellWidth; glyph: 0xE47D; visible: !form.modalEditor
            RField { id: amountField; parent: form.modalEditor ? heroAmount : amountBox.body; width: parent.width; ui: form.ui; formStyle: form.modalEditor; label: "Monto (" + form.currencyCode + ")"; placeholder: "0.00"; numeric: true
                     readOnly: !form.writable; onEdited: form.changed(); error: text.length ? form.ctl.amountError(text) : "" }
        }
        FieldBox {
            width: fieldsGrid.cellWidth; glyph: 0xE0D7; visible: !form.modalEditor
            RSelect { id: projectSelect; width: parent.width; ui: form.ui; formStyle: form.modalEditor; label: "Proyecto"; readOnly: !form.writable; value: form.projectId
                      options: (form.rendition.projectIds || []).map(function(id) { return { value: String(id), label: form.ctl.projectLabel(String(id)) } })
                      onPicked: function(value) { form.projectId = value } }
        }
        FieldBox {
            width: fieldsGrid.cellWidth; glyph: 0xE1D5; visible: !form.modalEditor
            RSelect { width: parent.width; ui: form.ui; formStyle: form.modalEditor; label: "Categoría"; readOnly: !form.writable; value: form.categoryCode
                      options: { form.app.st; return form.options("CATEGORY") }
                      onPicked: function(value) { form.categoryCode = value } }
        }
        FieldBox {
            width: fieldsGrid.cellWidth; glyph: 0xE19F; visible: !form.modalEditor || form.section === 0
            RField { id: beneficiaryField; width: parent.width; ui: form.ui; formStyle: form.modalEditor; label: "Proveedor / Beneficiario"; placeholder: "Nombre del proveedor…"
                     readOnly: !form.writable; onEdited: form.changed() }
        }
        FieldBox {
            id: quickPaymentMethods
            objectName: "quickPaymentMethods"
            width: fieldsGrid.cellWidth; glyph: 0xE0AA; visible: !form.modalEditor
            RSelect { width: parent.width; ui: form.ui; formStyle: form.modalEditor; label: "Medio de pago"; value: form.paymentMethodCode; readOnly: !form.writable
                      options: { form.app.st; return form.options("PAYMENT_METHOD") }
                      onPicked: function(value) { form.paymentMethodCode = value } }
        }
        FieldBox {
            id: quickSupportTypes
            objectName: "quickSupportTypes"
            width: fieldsGrid.cellWidth; glyph: 0xE0CC; visible: !form.modalEditor
            RSelect { width: parent.width; ui: form.ui; formStyle: form.modalEditor; label: "Tipo de comprobante"; value: form.supportTypeCode; readOnly: !form.writable
                      options: { form.app.st; return form.options("SUPPORT_TYPE") }
                      onPicked: function(value) { form.supportTypeCode = value } }
        }
        FieldBox {
            width: fieldsGrid.cellWidth; glyph: 0xE0CC; visible: !form.modalEditor || (form.section === 1 && !form.declarationSupport)
            RField { id: supportNumberField; width: parent.width; ui: form.ui; formStyle: form.modalEditor; label: "Número de comprobante"; placeholder: "Serie y número"
                     readOnly: !form.writable; onEdited: form.changed() }
        }
        FieldBox {
            width: fieldsGrid.cellWidth; glyph: 0xE0CC; visible: !form.modalEditor || (form.section === 1 && !form.declarationSupport)
            RField { id: rucField; width: parent.width; ui: form.ui; formStyle: form.modalEditor; label: "RUC"; placeholder: "RUC del proveedor"; maxLength: 11
                     readOnly: !form.writable; onEdited: form.changed() }
        }
        FieldBox {
            width: fieldsGrid.cellWidth; glyph: 0xE116; visible: !form.modalEditor || (form.section === 1 && !form.declarationSupport)
            RField { id: supportDetailField; width: parent.width; ui: form.ui; formStyle: form.modalEditor; label: form.supportTypeCode === "OTHER" ? "Detalle del sustento (obligatorio)" : "Detalle (opcional)"
                     readOnly: !form.writable; onEdited: form.changed() }
        }
        FieldBox {
            id: currencyBox
            width: fieldsGrid.cellWidth; glyph: 0xE47D; visible: !form.modalEditor
            RSelect { width: parent.width; ui: form.ui; formStyle: form.modalEditor; label: "Moneda"; value: form.currencyCode; readOnly: !form.writable
                      options: [{value:"PEN",label:"Soles (PEN)"}, {value:"USD",label:"Dólares (USD)"}]
                      onPicked: function(value) { form.currencyCode = value } }
        }
        FieldBox {
            width: fieldsGrid.cellWidth; glyph: 0xE0AA; visible: !form.modalEditor || form.section === 2
            RField { id: paymentDetailField; width: parent.width; ui: form.ui; formStyle: form.modalEditor; label: "Detalle de pago"; placeholder: "Banco, tarjeta u operación"
                     readOnly: !form.writable; onEdited: form.changed() }
        }
    }
    FieldBox {
        width: parent.width; glyph: 0xE116; visible: !form.modalEditor || form.section === 1
        Text { text: (form.modalEditor ? "Justificación" : "Observaciones") + (form.declarationSupport || form.categoryCode === "OTHER" ? " (obligatoria)" : ""); color: S.muted; font.family: form.ui.fontFamily; font.pixelSize: 13 * form.ui.u }
        TextArea {
            id: notesField; width: parent.width; height: 80 * form.ui.u
            placeholderText: "Ingrese una descripción adicional…"; readOnly: !form.writable
            color: S.text; placeholderTextColor: S.faint; font.family: form.ui.fontFamily; font.pixelSize: 15 * form.ui.u
            wrapMode: TextEdit.Wrap; selectByMouse: true; onTextChanged: form.changed()
            background: Rectangle { radius: 12 * form.ui.u; color: S.surfaceStrong; border.width: 1; border.color: S.fieldBorder }
        }
    }
    RCard {
        id: attachmentCard
        objectName: "expenseEditorAttachments"
        ui: form.ui; width: parent.width; color: S.cardGlass; radius: 22 * form.ui.u
        border.color: S.edge(1)
        visible: form.showAttachments && (!form.modalEditor || form.section === 3)
        Row {
            width: parent.width; spacing: 6 * form.ui.u
            Text { visible: !form.modalEditor; width: parent.width - addAttachment.width - parent.spacing
                   anchors.verticalCenter: parent.verticalCenter
                   text: "Comprobante · " + form.files.length + (form.files.length === 1 ? " archivo" : " archivos")
                   wrapMode: Text.WordWrap; color: S.text; font.family: form.ui.fontFamily; font.pixelSize: 13 * form.ui.u; font.weight: Font.DemiBold }
            RButton { id: addAttachment; ui: form.ui; width: form.modalEditor ? parent.width : Math.min(132 * form.ui.u, parent.width * 0.48)
                      height: (form.modalEditor ? 56 : 48) * form.ui.u; primary: form.modalEditor
                      label: form.modalEditor ? (form.files.length ? "Agregar otro archivo" : "Agregar comprobante") : "Agregar archivo"; glyph: 0xE13D; enabledButton: form.writable && !form.saving
                      color: form.modalEditor ? S.accent : S.tintSoft; onActivated: fileDialog.open() }
        }
        Repeater {
            model: form.showAttachments ? form.files : []
            delegate: Rectangle {
                id: fileTile
                required property var modelData
                readonly property bool pdf: String(modelData.name).toLowerCase().indexOf(".pdf") > 0
                readonly property bool compact: width < 420 * form.ui.u
                width: parent.width; height: (compact ? 104 : 64) * form.ui.u
                radius: 16 * form.ui.u; color: S.cardGlass
                border.width: 1; border.color: S.edge(1)
                Rectangle {
                    x: 8 * form.ui.u; y: 8 * form.ui.u
                    width: 44 * form.ui.u; height: width; radius: 10 * form.ui.u
                    color: fileTile.pdf ? "#E5322D" : S.tintSoft
                    Text { anchors.centerIn: parent; text: fileTile.pdf ? "PDF" : String.fromCharCode(0xE0F6)
                           color: fileTile.pdf ? "white" : S.accent
                           font.family: fileTile.pdf ? form.ui.fontFamily : form.ui.iconFamily; font.pixelSize: 18 * form.ui.u }
                    Image { anchors.fill: parent; source: !fileTile.pdf ? form.localUrl(fileTile.modelData.uri) : ""
                            asynchronous: true; fillMode: Image.PreserveAspectFit; visible: status === Image.Ready }
                }
                Column {
                    x: 60 * form.ui.u; y: 9 * form.ui.u
                    width: Math.max(0, parent.width - x - 8 * form.ui.u - (fileTile.compact ? 0 : fileActions.width))
                    spacing: 3 * form.ui.u
                    Text { width: parent.width; text: fileTile.modelData.name; color: S.text; elide: Text.ElideMiddle
                           font.family: form.ui.fontFamily; font.pixelSize: 13 * form.ui.u; font.weight: Font.DemiBold }
                    Text { width: parent.width; text: [form.sizeText(fileTile.modelData.size),fileTile.modelData.state || ""].filter(function(t) { return t.length }).join(" · ")
                           color: S.muted; elide: Text.ElideRight; font.family: form.ui.fontFamily; font.pixelSize: 11 * form.ui.u }
                }
                Row {
                    id: fileActions
                    anchors.right: parent.right; anchors.rightMargin: 5 * form.ui.u
                    anchors.bottom: parent.bottom; anchors.bottomMargin: 5 * form.ui.u
                    spacing: 4 * form.ui.u
                    RButton { ui: form.ui; width: 44 * form.ui.u; height: width; radius: width / 2; glyph: 0xE0BA
                              color: S.cardGlass; enabledButton: fileTile.modelData.kind === "remote" || String(fileTile.modelData.uri || "").length > 0
                              Accessible.name: "Ver " + fileTile.modelData.name; onActivated: form.viewFile(fileTile.modelData) }
                    RButton { ui: form.ui; width: 44 * form.ui.u; height: width; radius: width / 2; glyph: 0xE0B2
                              visible: fileTile.modelData.kind === "remote"; color: S.cardGlass
                              Accessible.name: "Descargar " + fileTile.modelData.name; onActivated: form.viewFile(fileTile.modelData, true) }
                    RButton { ui: form.ui; width: 44 * form.ui.u; height: width; radius: width / 2; glyph: 0xE18E; danger: true
                              visible: form.writable && (fileTile.modelData.kind === "remote" || fileTile.modelData.kind === "pending")
                              enabledButton: !form.saving; color: S.cardGlass
                              Accessible.name: "Retirar " + fileTile.modelData.name; onActivated: form.removeFile(fileTile.modelData) }
                }
            }
        }
    }
    RChip { visible: !form.modalEditor; ui: form.ui; label: "Formulario completo · IGV y campos avanzados"; enabledChip: !form.saving; onActivated: form.openFullForm() }
    Text { visible: form.error.length > 0; width: parent.width; text: form.error; color: S.danger; wrapMode: Text.WordWrap
           font.family: form.ui.fontFamily; font.pixelSize: 13 * form.ui.u }
    Row {
        width: parent.width
        spacing: 8 * form.ui.u
        visible: form.writable && !form.modalEditor
        readonly property real bw: (width - 2 * spacing) / 3
        RButton { width: parent.bw; ui: form.ui; danger: true; label: "Eliminar"; visible: !form.isNew
                  busy: form.app.busy("deleteExpense:" + (form.expense ? form.expense.localId : ""))
                  enabledButton: !form.saving; onActivated: form.deleteRequested() }
        RButton { width: form.isNew ? (parent.width - parent.spacing) / 2 : parent.bw; ui: form.ui; label: "Cancelar"
                  enabledButton: !form.saving; onActivated: form.requestClose() }
        RButton { objectName: "quickSaveButton"; width: form.isNew ? (parent.width - parent.spacing) / 2 : parent.bw; ui: form.ui; primary: true
                  label: "Guardar"; busy: form.saving; onActivated: form.save() }
    }
}

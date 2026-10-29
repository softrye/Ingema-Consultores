import QtQuick
import QtQuick.Controls
import QtQuick.Dialogs
import "RStyle.js" as S
import "../flowcore" as FlowCore

// Nuevo gasto / edición de gasto (EL formulario existente de Rendiciones).
// Cuatro secciones sobre el MISMO formulario y el MISMO motor de guardado:
//   General · Comprobante · Pago e importe · Sustentos
// Composición de los previews aprobados (16-10-2026): tarjeta de vidrio claro
// por grupo, título de sección grande + subtítulo, etiquetas fuertes, cajas de
// 56 dp con icono Lucide, moneda segmentada, mosaicos de captura y filas de
// archivo con menú ⋮. Sin línea de progreso: el encabezado muestra la sección y
// el indicador real del borrador. Navegación y herramientas en el Dock global:
//   [← Volver] [Borrador] [+ Siguiente | Registrar] [··· Herramientas]
// Toque = acción primaria; Deep Press 380 ms = menú 3D Touch del Dock global.
// Validación en C++ (RenditionValidation) mostrada JUNTO al campo; los fallos
// operativos van al panel "Estado de Rendiciones". Guardado con saveExpense
// (outbox, CAS) o saveWorking/promoteWorking (Working Document). Sin IA.
Item {
    id: page
    readonly property bool editingInProgress: true
    property var app
    property string renditionLocalId: ""
    property string expenseLocalId: ""
    property string initialSection: ""          // general | receipt | payment | supports
    property var prefill: null                  // propuesta de InGe IA (revisada por el usuario aquí)
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
    // ---- Borrador en la nube (Working Document): mismo editor, un solo motor.
    property string workingId: ""
    property var removedSources: []
    readonly property var working: {
        if (!workingId.length) return null
        var rows = app.st.workingRows || []
        for (var i = 0; i < rows.length; ++i) if (rows[i].id === workingId) return rows[i]
        return null
    }
    readonly property bool draftMode: workingId.length > 0
    readonly property bool cloudDrafts: String(rendition.remoteId || "").length > 0
                                       && String(app.st.workingContract || "") !== "UNAVAILABLE"
    readonly property var workingSources: working ? (working.sources || []).filter(function(s) { return removedSources.indexOf(s.id) < 0 }) : []
    readonly property bool draftBlocked: !!working && (working.syncState === "CONFLICT"
                                                       || working.promoteRequested === true || working.archiveRequested === true)
    readonly property bool writable: ctl.canEdit(rendition) && !(expense && expense.archived === true) && !draftBlocked
                                     && resultKind === ""
    readonly property string draftKey: "expense:" + renditionLocalId + ":"
                                       + (draftMode ? "draft:" + workingId : expenseLocalId.length ? expenseLocalId : "new")
    readonly property string saveKey: "expense:" + renditionLocalId

    // ------------------------------------------------------------ Secciones
    readonly property var sections: ["general", "receipt", "payment", "supports"]
    readonly property var sectionTitles: ["General", "Comprobante", "Pago e importe", "Sustentos"]
    property int section: 0
    readonly property string title: sectionTitles[section]
    readonly property bool lastSection: section === sections.length - 1
    function goToSection(index) {
        var next = Math.max(0, Math.min(sections.length - 1, index))
        if (next === section) return
        Qt.inputMethod.hide()
        closeTools()
        section = next
        app.haptic("selection")
    }
    function sectionIndex(name) { var i = sections.indexOf(String(name)); return i < 0 ? 0 : i }

    // ---- Indicador real del borrador (encabezado). Texto corto; el detalle
    // vive en el estado del Working/outbox, nunca es decorativo.
    readonly property var headerChip: {
        if (resultKind === "confirmed") return { label: "Registrado", tone: S.success }
        if (saving) return { label: "Guardando…", tone: S.accentSoft }
        if (resultKind === "pending") return { label: "Sin sincronizar", tone: S.warning }
        if (working) {
            if (working.syncState === "CONFLICT") return { label: "Conflicto", tone: S.danger }
            if (working.promoteRequested) return { label: "Registro pendiente", tone: S.accentSoft }
            if (working.syncState === "LOCAL_ONLY") return { label: "En el equipo", tone: S.muted }
            if (working.inCloud && working.syncState === "SYNCED") return { label: "En la nube", tone: S.success }
            return { label: "Sin sincronizar", tone: S.warning }
        }
        if (expense) {
            var state = app.syncState(expense)
            if (state === "SYNCED") return { label: "Registrado", tone: S.success }
            if (state === "CONFLICT") return { label: "Conflicto", tone: S.danger }
            return { label: "Sin sincronizar", tone: S.warning }
        }
        return { label: localSaved ? "Borrador guardado" : "Borrador", tone: S.corporateBlue }
    }

    // ------------------------------------------------------------ Estado
    property string savedId: ""
    property string intentId: ""
    property string projectId: ""
    property string expenseDate: ""
    property string categoryCode: ""
    property string currencyCode: "PEN"
    property string paymentMethodCode: ""
    property string supportTypeCode: ""
    property var pending: []                 // sustentos aún no entregados al almacén
    property string error: ""                // última validación (se muestra junto al campo)
    property var fieldErrors: ({})           // campo -> mensaje de validación
    property string opError: ""              // fallo operativo (también en Estado de Rendiciones)
    property bool saving: false
    property bool finished: false
    property bool restored: false
    property bool waitingPhoto: false
    property bool localSaved: false           // copia local del formulario persistida
    // Revisión de edición (paridad Web PR #11, ADR-023/052): un guardado sólo
    // acredita la instantánea que envió, nunca lo escrito mientras estaba en curso.
    property int editRevision: 0
    property string replacingSource: ""      // sustento a reemplazar tras elegir archivo
    // Resultado del registro: "" | "pending" (guardado, falta confirmación) | "confirmed"
    property string resultKind: ""
    property bool awaitingConfirmation: false

    readonly property var textFields: ["amount", "concept", "beneficiary", "ruc", "supportNumber", "supportDetail",
                                       "paymentMethodDetail", "subtotal", "igv", "justification"]
    function fieldItem(name) {
        return ({ amount: amountField, concept: conceptField, beneficiary: beneficiaryField, ruc: rucField,
                  supportNumber: supportNumberField, supportDetail: supportDetailField, paymentMethodDetail: paymentDetailField,
                  subtotal: subtotalField, igv: igvField, justification: justificationField })[name]
    }
    function catalogOptions(kind) {
        var rows = ctl.catalog(kind)
        return rows.map(function(r) {
            var code = S.text_(r, "code")
            return { value: code, label: S.text_(r, "label") || S.text_(r, "name") || S.text_(r, "description") || code }
        })
    }
    // Proyecto en dos líneas (código / nombre), como en el preview aprobado.
    readonly property var projectOptions: (rendition.projectIds || []).map(function(id) {
        var p = ctl.project(String(id)) || {}
        var code = S.text_(p, "code"), name = S.text_(p, "name")
        return code.length && name.length ? { value: String(id), label: code, detail: name }
                                          : { value: String(id), label: ctl.projectLabel(String(id)) }
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
    function hasContent() {
        var v = values()
        return ["concept", "beneficiary", "amount", "supportNumber", "justification", "categoryCode"].some(function(k) {
            return String(v[k] || "").trim().length > 0 }) || pending.length > 0
    }

    // Formulario del contrato Working: los 13 campos de texto del servidor.
    function workingForm() {
        var v = values()
        return { projectId: v.projectId, expenseDate: v.expenseDate, categoryCode: v.categoryCode, concept: v.concept,
                 beneficiary: v.beneficiary, paymentMethodCode: v.paymentMethodCode, paymentMethodDetail: v.paymentMethodDetail,
                 supportTypeCode: v.supportTypeCode, supportNumber: v.supportNumber, supportDetail: v.supportDetail,
                 currencyCode: v.currencyCode, amount: v.amount, justification: v.justification }
    }
    function workingFiles(includeNew) {
        var list = workingSources.map(function(s) { return { id: s.id } })
        if (includeNew)
            for (var i = 0; i < pending.length; ++i)
                list.push({ localUri: pending[i].localUri, fileName: pending[i].fileName,
                            mimeType: pending[i].mimeType, sizeBytes: pending[i].sizeBytes })
        return list
    }

    property bool applying: false
    function applySource(source) {
        applying = true
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
        applying = false
    }
    Component.onCompleted: {
        var draft = (app.st.editorDrafts || {})[draftKey]
        var source = draft && draft.intentId ? draft : (draftMode && working ? working.form : (expense || {}))
        restored = !!(draft && draft.intentId)
        // Propuesta de InGe IA: sólo para un gasto NUEVO sin copia local; nada se registra
        // hasta que el usuario lo confirme con "Registrar gasto".
        if (prefill && !restored && !draftMode && !expenseLocalId.length) source = Object.assign({}, source, prefill)
        intentId = S.text_(source, "intentId", "clientIntentId") || ctl.newId()
        savedId = restored ? String(draft.savedId || "") : ""
        applySource(source)
        pending = restored ? (draft.pendingAttachments || []) : []
        if (restored && draft.section !== undefined) section = Math.max(0, Math.min(3, Number(draft.section)))
        if (initialSection.length) section = sectionIndex(initialSection)
        if (prefill && !restored) { localSaved = false; autosave.restart() }   // la propuesta queda como copia local
    }
    Component.onDestruction: life.alive = false

    function handleBack() {
        if (toolMenu.open || reuseMenu.open || fileMenu.open || filesMenu.open) { closeTools(); return true }
        if (resultKind.length) return false          // tras registrar, Atrás sale
        if (section > 0) { goToSection(section - 1); return true }
        // General: sale a la lista SIN descarte silencioso (la copia local queda guardada).
        autosave.stop()
        if (writable && !finished && hasContent()) persistLocal()
        return false
    }

    function changed() {
        if (applying) return
        editRevision++
        error = ""
        if (Object.keys(fieldErrors).length) fieldErrors = ({})
        localSaved = false
        if (writable && !finished) autosave.restart()
    }
    function persistLocal() {
        var draft = values()
        draft.intentId = intentId
        draft.savedId = savedId
        draft.pendingAttachments = pending
        draft.renditionLocalId = renditionLocalId
        draft.section = section
        var revision = editRevision
        app.call("saveEditorDraft", { key: draftKey, draft: draft }, "", function(ok) {
            if (ok && page.life.alive && page.editRevision === revision) page.localSaved = true
        })
    }
    Timer {
        id: autosave
        interval: 600
        onTriggered: {
            page.persistLocal()
            if (page.draftMode) page.saveDraft(false)
        }
    }
    // Fallo OPERATIVO (no de validación): al panel "Estado de Rendiciones" (con su
    // causa y acción) y una línea discreta en la tarjeta activa; nunca un recuadro flotante.
    function fail(code, message, prefix) {
        var text = app.errorText(code, message)
        if (!text.length) return                     // conexión/sesión: sólo aura (silencioso)
        opError = (prefix || "") + text
        if (app.reportProblem !== undefined) app.reportProblem(opError, "Nuevo gasto · " + title)
        app.haptic("error")
    }

    // ------------------------------------------------------------ Borradores
    function saveDraft(explicitSave, done) {
        if (!writable) return
        var args = { localId: renditionLocalId, workingId: workingId, form: workingForm(),
                     files: workingFiles(explicitSave === true), final: explicitSave === true }
        // Sustentos enviados en ESTE guardado: los añadidos mientras está en curso se conservan.
        var sentUris = explicitSave === true ? pending.map(function(a) { return a.localUri }) : []
        if (!workingId.length && expenseLocalId.length && expense && String(expense.remoteId || "").length)
            args.expenseLocalId = expenseLocalId
        var life = page.life
        var previousKey = draftKey
        app.call("saveWorking", args, explicitSave === true ? "working:" + renditionLocalId : "", function(ok, result, code, message) {
            if (!life.alive) return
            if (!ok) { if (explicitSave === true) page.fail(code, message); if (done) done(false); return }
            page.workingId = String(result.workingId || page.workingId)
            // La copia local del formulario "nuevo" pasa a ser el borrador en la nube:
            // se retira la clave anterior para no ofrecer dos veces el mismo contenido.
            if (page.draftKey !== previousKey) {
                page.app.call("saveEditorDraft", { key: previousKey, draft: {} }, "")
                page.persistLocal()
            }
            if (explicitSave === true)
                page.pending = page.pending.filter(function(a) { return sentUris.indexOf(a.localUri) < 0 })
            if (done) done(true)
        })
    }
    // Botón 2 (Borrador): guarda y sigue editando. Sin contrato en la nube (ficha aún
    // no confirmada o entorno sin Working) la copia local durable es el borrador.
    function saveAsDraft() {
        if (saving || !writable) return
        error = ""; opError = ""
        autosave.stop()
        persistLocal()
        if (!cloudDrafts) { app.toast("Borrador guardado en el equipo.", "success"); return }
        saving = true
        saveDraft(true, function(ok) {
            page.saving = false
            if (ok) { page.app.haptic("success"); page.app.toast("Borrador guardado.", "success") }
        })
    }
    function leaveKeepingDraft() {                   // la copia local queda para retomarla
        autosave.stop()
        if (writable && !finished && hasContent()) persistLocal()
        app.closePage()
    }
    function exitWithoutSaving() {
        app.confirm("Salir sin guardar", "Se descartarán los cambios de este formulario que no guardaste como borrador. Los borradores ya guardados se conservan.",
                    "Salir", true, function() {
            page.finished = true
            autosave.stop()
            page.app.call("saveEditorDraft", { key: page.draftKey, draft: {} }, "")
            page.app.closePage()
        })
    }
    function cancelRegistration() {
        app.confirm("Cancelar registro", page.draftMode
                    ? "Se descartará este borrador de gasto (también en la nube). No se registra ningún gasto."
                    : "Se descartará este gasto sin registrarlo. Los gastos ya registrados no se modifican.",
                    "Cancelar registro", true, function() {
            page.finished = true
            autosave.stop()
            page.app.call("saveEditorDraft", { key: page.draftKey, draft: {} }, "")
            if (page.draftMode)
                page.app.call("archiveWorking", { localId: page.renditionLocalId, workingId: page.workingId }, "working:" + page.workingId)
            page.app.closePage()
        })
    }
    readonly property var otherDrafts: (app.st.workingRows || []).filter(function(w) {
        return w.id !== page.workingId && !w.promoteRequested && !w.archiveRequested
    })
    function recoverLastDraft() {
        if (!otherDrafts.length) return
        var latest = otherDrafts.slice().sort(function(a, b) { return String(b.updatedAt || "") < String(a.updatedAt || "") ? -1 : 1 })[0]
        var open = function() { page.finished = true; autosave.stop(); page.app.replaceExpense(page.renditionLocalId, String(latest.expenseLocalId || ""), latest.id) }
        if (hasContent())
            app.confirm("Recuperar último borrador", "Se abrirá el borrador «" + (S.text_(latest.form, "concept") || "sin concepto")
                        + "». Lo que escribiste aquí queda guardado en el equipo.", "Abrir borrador", false, function() { page.persistLocal(); open() })
        else open()
    }
    function openStatus() { opError = ''; if (app.toggleStatus !== undefined) app.toggleStatus() }
    function openDraftList() {
        leaveKeepingDraft()
        if (app.detailPage) app.detailPage.showSection("expenses")
    }

    // ------------------------------------------------------------ Sustentos
    function addFile(url, sourceKind) {
        var info = ctl.describeLocalFile(url)
        if (String(info.error).length) { setFieldError("files", info.error); return }
        var list = pending.slice()
        for (var i = 0; i < list.length; ++i)
            if (list[i].localUri === info.localUri) return
        info.sourceKind = sourceKind
        info.importedUrl = String(url)
        delete info.error
        list.push(info)
        pending = list
        if (replacingSource.length) {                // reemplazo: retira el anterior tras elegir el nuevo
            if (replacingSource.indexOf("pending:") === 0) {
                var index = Number(replacingSource.substring(8))
                if (index >= 0 && index < pending.length - 1) removePending(index)
            } else if (replacingSource.indexOf("remote:") === 0) {
                var target = remoteAttachments.filter(function(a) { return "remote:" + S.text_(a, "id") === page.replacingSource })[0]
                if (target) app.call("archiveAttachment", { attachmentId: S.text_(target, "id"), rowVersion: Number(target.row_version || target.rowVersion || 0) },
                                     "replace:" + S.text_(target, "id"))
            } else if (removedSources.indexOf(replacingSource) < 0) {
                removedSources = removedSources.concat([replacingSource])
            }
            replacingSource = ""
        }
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
        if (typeof Perms === "undefined" || !Perms) { setFieldError("files", "La cámara no está disponible en este equipo."); return }
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
            if (targetIdx === 101) { page.waitingPhoto = false; page.replacingSource = "" }
        }
        function onPhotoSelectionError(targetIdx, code, message) {
            if (targetIdx !== 101) return
            page.waitingPhoto = false
            page.replacingSource = ""
            page.setFieldError("files", String(message || code))
        }
    }
    FileDialog {
        id: fileDialog
        title: "Selecciona el comprobante"
        fileMode: FileDialog.OpenFile
        nameFilters: ["Comprobantes (*.pdf *.jpg *.jpeg *.png *.webp)"]
        onAccepted: page.addFile(selectedFile, "file")
        onRejected: page.replacingSource = ""
    }
    // Archivos del gasto (orden: servidor, en cola de subida, borrador en la nube, nuevos).
    readonly property var savedAttachments: expense ? (expense.attachments || []).filter(function(a) { return !S.text_(a, "archived_at").length }) : []
    readonly property var remoteAttachments: {
        var id = expense ? S.text_(expense, "remoteId") : ""
        if (!id.length) return []
        return (app.st.attachments || []).filter(function(a) {
            return S.text_(a, "expense_id", "expenseId") === id && !S.text_(a, "archived_at").length })
    }
    readonly property var queuedAttachments: savedAttachments.filter(function(a) { return S.text_(a, "phase") !== "READY" })
    readonly property int pendingUploads: queuedAttachments.length
                                          + workingSources.filter(function(s) { return !s.ready && s.local }).length
    readonly property int fileCount: Math.max(savedAttachments.length, remoteAttachments.length + queuedAttachments.length)
                                     + workingSources.length + pending.length
    readonly property var fileRows: {
        var rows = [], i
        for (i = 0; i < remoteAttachments.length; ++i) {
            var r = remoteAttachments[i]
            rows.push({ key: "remote:" + S.text_(r, "id"), kind: "remote", name: S.text_(r, "file_name", "fileName") || "Sustento",
                        mime: S.text_(r, "mime_type", "mimeType"), size: Number(r.size_bytes || r.sizeBytes || 0),
                        state: "En el servidor", data: r })
        }
        var savedReady = savedAttachments.length - queuedAttachments.length
        if (!remoteAttachments.length && savedReady > 0)
            for (i = 0; i < savedAttachments.length; ++i)
                if (S.text_(savedAttachments[i], "phase") === "READY")
                    rows.push({ key: "saved:" + i, kind: "saved", name: S.text_(savedAttachments[i], "fileName", "file_name") || "Sustento",
                                mime: S.text_(savedAttachments[i], "mimeType", "mime_type"), size: Number(savedAttachments[i].sizeBytes || 0),
                                state: "En el servidor", data: savedAttachments[i] })
        for (i = 0; i < queuedAttachments.length; ++i) {
            var q = queuedAttachments[i]
            var st = app.syncState(q)
            rows.push({ key: "queued:" + i, kind: "queued", name: S.text_(q, "fileName", "file_name") || "Sustento",
                        mime: S.text_(q, "mimeType", "mime_type"), size: Number(q.sizeBytes || 0), localUri: S.text_(q, "localUri"),
                        state: st === "ERROR" || st === "CONFLICT" ? "Carga no completada" : "Pendiente de subir", data: q })
        }
        for (i = 0; i < workingSources.length; ++i) {
            var w = workingSources[i]
            rows.push({ key: w.id, kind: "working", name: w.name, mime: String(w.type || ""), size: Number(w.size || 0),
                        state: w.ready ? "En el servidor" : w.local ? "Pendiente de subir" : "Falta volver a adjuntar", data: w })
        }
        for (i = 0; i < pending.length; ++i)
            rows.push({ key: "pending:" + i, kind: "pending", index: i, name: pending[i].fileName, mime: String(pending[i].mimeType || ""),
                        size: Number(pending[i].sizeBytes || 0), localUri: String(pending[i].importedUrl || pending[i].localUri || ""),
                        state: "Se adjunta al registrar", data: pending[i] })
        return rows
    }
    function isImage(row) {
        var m = String(row.mime || "").toLowerCase(), n = String(row.name || "").toLowerCase()
        return m.indexOf("image/") === 0 || /\.(jpe?g|png|webp|heic)$/.test(n)
    }
    function fileMeta(row) {
        var n = String(row.name || ""), dot = n.lastIndexOf(".")
        var ext = dot >= 0 ? n.substring(dot + 1).toUpperCase() : (isImage(row) ? "IMG" : "ARCHIVO")
        var b = Number(row.size || 0)
        var size = b <= 0 ? "" : b >= 1048576 ? (b / 1048576).toFixed(1) + " MB" : Math.max(1, Math.round(b / 1024)) + " KB"
        return ext + (size.length ? " · " + size : "") + " · " + row.state
    }
    function localUrl(path) {
        var p = String(path || "")
        return p.indexOf(":/") > 0 || p.indexOf("file:") === 0 || p.indexOf("content:") === 0 ? p : "file:///" + p.replace(/^\/+/, "")
    }
    // Ver: servidor -> acceso efímero autorizado; local/cola -> el propio archivo del equipo.
    function viewFile(row) {
        closeTools()
        if (row.kind === "remote") {
            app.call("attachmentAccess", { attachmentId: S.text_(row.data, "id") }, "access:" + S.text_(row.data, "id"), function(ok, result, code, message) {
                if (!ok) { page.fail(code, message, "No se pudo abrir el sustento. "); return }
                var r = (result.rows || [])[0] || {}
                if (String(r.signedUrl || "").length) Qt.openUrlExternally(r.signedUrl)
                else page.fail("ACCESS_UNAVAILABLE", "El servidor no devolvió un acceso al sustento.")
            })
        } else if (row.kind === "working") {
            if (row.data.ready) app.openAuthorized("workingFileOpen", { fileId: row.data.uploadRequestId }, "workingFile:" + row.data.id)
        } else if (row.localUri && row.localUri.length) {
            Qt.openUrlExternally(localUrl(row.localUri))
        }
    }
    function canView(row) {
        return row.kind === "remote" || (row.kind === "working" && row.data.ready === true) || String(row.localUri || "").length > 0
    }
    function canReplace(row) {
        return writable && (row.kind === "remote" || row.kind === "working" || row.kind === "pending")
    }
    // Reemplazar: se elige el archivo nuevo; el anterior se retira con su operación real
    // (servidor: archiveAttachment con CAS; borrador: fuente retirada; nuevo: se quita).
    function replaceFile(row) {
        closeTools()
        if (!canReplace(row)) return
        var pick = function() {
            page.replacingSource = row.kind === "pending" ? "pending:" + row.index : row.kind === "remote" ? row.key : row.data.id
            page.goToSection(3)
            fileDialog.open()
        }
        if (row.kind === "remote")
            app.confirm("Reemplazar adjunto", "Elige el archivo nuevo. «" + row.name + "» se retirará del gasto en el servidor al confirmar el reemplazo; la versión presentada conserva su copia.",
                        "Elegir archivo", false, pick)
        else pick()
    }
    function removeFile(row) {
        closeTools()
        if (!writable) return
        if (row.kind === "pending") { removePending(row.index); return }
        if (row.kind === "working") { removedSources = removedSources.concat([row.data.id]); changed(); return }
        if (row.kind === "remote")
            app.confirm("Retirar sustento", "Se archivará «" + row.name + "» en el servidor. La versión presentada conserva su copia.", "Retirar", true, function() {
                page.app.call("archiveAttachment", { attachmentId: S.text_(row.data, "id"), rowVersion: Number(row.data.row_version || row.data.rowVersion || 0) },
                              "archive:" + S.text_(row.data, "id"), function(ok, result, code, message) {
                    if (!ok) page.fail(code, message, "No se pudo retirar el sustento. ")
                })
            })
    }
    function canRemove(row) { return writable && (row.kind === "pending" || row.kind === "working" || row.kind === "remote") }
    property var fileMenuRow: null
    function openFileMenu(row, item) {
        fileMenuRow = row
        var p = item.mapToItem(page, item.width / 2, item.height)
        fileMenu.anchorX = p.x; fileMenu.anchorY = p.y
        fileMenu.open = true
    }

    // -------------------------------------------------------------- Registrar
    function validationProblem() {
        var v = values()
        var problem = ctl.amountError(v.amount)
        if (!problem.length) problem = ctl.expenseError(rendition, v)
        return problem
    }
    // Validación -> campo exacto (junto al campo, nunca como fallo técnico global).
    function fieldForProblem(problem) {
        var p = String(problem), l = p.toLowerCase()
        if (p.indexOf("categoryCode") >= 0) return "category"
        if (p.indexOf("supportTypeCode") >= 0) return "supportType"
        if (p.indexOf("paymentMethodCode") >= 0 || l.indexOf("medio real de pago") >= 0) return "payment"
        if (p.indexOf("Falta completar: concept") >= 0 || l.indexOf("concepto") === 0) return "concept"
        if (l.indexOf("fecha") >= 0) return "date"
        if (l.indexOf("proyecto") >= 0) return "project"
        if (l.indexOf("moneda") >= 0) return "currency"
        if (l.indexOf("monto") >= 0 || l.indexOf("importe") >= 0) return "amount"
        if (l.indexOf("justificación") >= 0) return "justification"
        return "form"
    }
    readonly property var fieldSections: ({ project: 0, date: 0, category: 0, concept: 0, supportType: 1,
                                            payment: 2, currency: 2, amount: 2, justification: 3, files: 3 })
    function setFieldError(field, text) {
        var map = {}
        map[field] = text
        fieldErrors = map
    }
    function fieldError(field) { return fieldErrors[field] || "" }
    function showProblem(problem) {
        var labels = { categoryCode: "Categoría", paymentMethodCode: "Medio de pago", supportTypeCode: "Tipo de comprobante", concept: "Concepto" }
        error = String(problem).replace(/Falta completar: (\w+)\./, function(m, key) { return "Falta completar: " + (labels[key] || key) + "." })
        var field = fieldForProblem(problem)
        setFieldError(field, error)
        if (fieldSections[field] !== undefined && fieldSections[field] !== section) goToSection(fieldSections[field])
        app.haptic("error")
    }
    function sectionForProblem(problem) {
        var s = fieldSections[fieldForProblem(problem)]
        return sections[s === undefined ? section : s]
    }
    function register() { if (draftMode) promoteDraft(); else save() }
    function save() {
        if (saving || !writable) return
        var problem = validationProblem()
        if (problem.length) { showProblem(problem); return }
        saving = true
        error = ""; opError = ""
        autosave.stop()
        var v = values()
        var args = { localId: renditionLocalId, expenseLocalId: savedId.length ? savedId : expenseLocalId,
                     expense: v, synchronize: true }
        if (!savedId.length && expenseLocalId.length && expense)
            args.expectedExpenseRowVersion = Number(expense.rowVersion || 0)
        var life = page.life
        app.call("saveExpense", args, saveKey, function(ok, result, code, message) {
            if (!ok) {
                page.saving = false
                if (life.alive) page.fail(code, message, "No se pudo guardar el gasto. ")
                return
            }
            page.savedId = String(result.localId || "")
            if (!page.savedId.length) {
                page.saving = false
                page.fail("EXPENSE_IDENTITY", "No se confirmó la identidad del gasto.")
                return
            }
            page.attachNext(life)
        })
    }
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
                page.fail(code, message, "El gasto está guardado; falta adjuntar «" + a.fileName + "». ")
                page.changed()
                return
            }
            // Se retira el sustento confirmado por su identidad, no por su posición.
            var done = a
            page.pending = page.pending.filter(function(p) { return p.localUri !== a.localUri })
            if (done.sourceKind !== "file" && typeof Perms !== "undefined" && Perms)
                Perms.releaseImportedPhoto(done.importedUrl)
            page.attachNext(life)
        })
    }
    function promoteDraft() {
        if (saving || !writable) return
        var problem = validationProblem()
        if (problem.length) { showProblem(problem); return }
        saving = true
        error = ""; opError = ""
        autosave.stop()
        var life = page.life
        app.call("promoteWorking", { localId: renditionLocalId, workingId: workingId, form: workingForm(),
                                     files: workingFiles(true), final: true }, "working:" + renditionLocalId,
                 function(ok, result, code, message) {
            if (!life.alive) return
            page.saving = false
            if (!ok) { page.fail(code, message, "No se pudo registrar el borrador. "); return }
            page.pending = []
            page.finish()
        })
    }
    // Guardado local completo (outbox). El cuadro final distingue la confirmación
    // REAL del servidor (confeti) de un guardado pendiente de sincronizar.
    function finish() {
        finished = true
        saving = false
        app.call("saveEditorDraft", { key: draftKey, draft: {} }, "")
        awaitingConfirmation = true
        resultKind = ""
        if (app.connection === "OFFLINE") resultKind = "pending"
        else confirmTimeout.restart()
        checkConfirmation()
    }
    readonly property bool serverConfirmed: {
        if (!finished) return false
        if (draftMode) return (app.st.promotedWorkingIds || []).indexOf(workingId) >= 0
        return !!expense && app.syncState(expense) === "SYNCED" && String(expense.remoteId || "").length > 0
    }
    onServerConfirmedChanged: checkConfirmation()
    function checkConfirmation() {
        if (!awaitingConfirmation) return
        if (serverConfirmed) {
            confirmTimeout.stop()
            if (resultKind !== "confirmed") {
                resultKind = "confirmed"
                app.haptic("success")
                celebrations++
                confettiLayer.play()                 // sólo con confirmación real
            }
        }
    }
    property int confirmWaitMs: 8000
    property int celebrations: 0                  // confirmaciones reales celebradas (pruebas)
    Timer { id: confirmTimeout; interval: page.confirmWaitMs; onTriggered: if (page.resultKind === "") page.resultKind = "pending" }
    function viewInExpenses() {
        app.closePage()
        if (app.detailPage) app.detailPage.showSection("expenses")
    }
    function registerAnother() { app.replaceExpense(renditionLocalId, "", "") }

    // ------------------------------------------------------------- Dock (4)
    // [← Volver] [Borrador] [+ Siguiente|Registrar] [···]. Toque = acción primaria
    // (tapCommand); Deep Press 380 ms = menú 3D Touch del propio Dock global.
    readonly property string dockContextKey: "rendiciones/expense"
    readonly property var sectionTools: {
        var v = { general: [
                    { id: "renditions.tool.today", label: "Usar fecha de hoy", icon: "renditions.today", enabled: writable },
                    { id: "renditions.tool.period", label: "Revisar período permitido", icon: "renditions.period" },
                    { id: "renditions.tool.reuse", label: "Reutilizar datos anteriores", icon: "renditions.reuse", enabled: writable && previousExpenses.length > 0 } ],
                  receipt: [
                    { id: "renditions.tool.requirements", label: "Revisar requisitos", icon: "renditions.requirements" },
                    { id: "renditions.tool.noReceipt", label: "Registrar sin comprobante", icon: "renditions.noReceipt", enabled: writable && noReceiptType !== null },
                    { id: "renditions.tool.help", label: "Ayuda sobre comprobantes", icon: "renditions.help" } ],
                  payment: [
                    { id: "renditions.tool.igv", label: "Calcular IGV", icon: "renditions.calculator" },
                    { id: "renditions.tool.amounts", label: "Validar importes", icon: "renditions.validate" },
                    { id: "renditions.tool.breakdown", label: "Revisar desglose", icon: "renditions.breakdown" } ],
                  supports: [
                    { id: "renditions.tool.files", label: "Ver archivos adjuntos", icon: "renditions.attachments", enabled: fileCount > 0 },
                    { id: "renditions.tool.replace", label: "Reemplazar adjunto", icon: "renditions.replace", enabled: writable && fileRows.some(function(r) { return page.canReplace(r) }) },
                    { id: "renditions.tool.retry", label: "Reintentar carga", icon: "renditions.retry", enabled: pendingUploads > 0 } ] }
        return v[sections[section]]
    }
    readonly property var dockActions: {
        var tools = sectionTools.map(function(t, i) {
            return { id: t.id, label: t.label, icon: t.icon, command: t.id, enabled: t.enabled !== false && resultKind === "", priority: 4 + i }
        })
        return [
            { id: "previous", label: section > 0 ? "Sección anterior" : "Volver", icon: "renditions.arrowBack",
              command: "renditions.page.back", tapCommand: true, enabled: true, priority: 1,
              children: [
                { id: "renditions.page.toList", label: "Volver a la lista de gastos", icon: "renditions.home", command: "renditions.page.toList" },
                { id: "renditions.page.exitNoSave", label: "Salir sin guardar", icon: "renditions.logout", command: "renditions.page.exitNoSave", enabled: writable },
                { id: "renditions.page.cancel", label: "Cancelar registro", icon: "renditions.cancel", command: "renditions.page.cancel", enabled: writable, destructive: true } ] },
            { id: "renditions.page.draft", label: "Borrador", icon: "documents.file",
              command: "renditions.page.draft", tapCommand: true, enabled: writable, priority: 2,
              children: [
                { id: "renditions.page.saveDraft", label: "Guardar como borrador", icon: "action.save", command: "renditions.page.draft", enabled: writable },
                { id: "renditions.page.drafts", label: "Ver mis borradores", icon: "renditions.list", command: "renditions.page.drafts", enabled: !!app.detailPage || app.closePage !== undefined },
                { id: "renditions.page.recover", label: "Recuperar último borrador", icon: "renditions.recover", command: "renditions.page.recover", enabled: otherDrafts.length > 0 } ] },
            { id: "next", label: lastSection ? "Registrar gasto" : "Siguiente", icon: "action.add",
              command: "renditions.page.next", tapCommand: true, enabled: lastSection ? writable : true, priority: 3,
              children: [
                { id: "renditions.page.toSupports", label: "Ir a Sustentos", icon: "renditions.forward", command: "renditions.page.toSupports", enabled: !lastSection },
                { id: "renditions.page.saveContinue", label: "Guardar y continuar", icon: "action.save", command: "renditions.page.saveContinue", enabled: writable && !lastSection },
                // Preparado para InGe IA; deshabilitado (INGE_RENDITIONS_AI_ENABLED=0).
                { id: "renditions.page.aiValidate", label: "Validar datos con IA", icon: "renditions.ai", command: "renditions.page.aiValidate", enabled: false } ] }
        ].concat(tools)
    }
    function dockCommand(name) {
        if (name === "renditions.page.back") { if (!handleBack()) leaveKeepingDraft(); return }
        if (name === "renditions.page.toList") { openDraftList(); return }
        if (name === "renditions.page.exitNoSave") { exitWithoutSaving(); return }
        if (name === "renditions.page.cancel") { cancelRegistration(); return }
        if (name === "renditions.page.draft") { saveAsDraft(); return }
        if (name === "renditions.page.drafts") { openDraftList(); return }
        if (name === "renditions.page.recover") { recoverLastDraft(); return }
        if (name === "renditions.page.next") { if (lastSection) register(); else goToSection(section + 1); return }
        if (name === "renditions.page.toSupports") { goToSection(3); return }
        if (name === "renditions.page.saveContinue") { saveAsDraft(); goToSection(section + 1); return }
        if (name.indexOf("renditions.tool.") === 0) runTool(name.substring("renditions.tool.".length))
    }

    // --------------------------------------------- Herramientas deterministas
    readonly property var supportTypes: ctl.catalog("SUPPORT_TYPE")
    readonly property var noReceiptType: {
        var rows = supportTypes
        for (var i = 0; i < rows.length; ++i) {
            var text = (S.text_(rows[i], "code") + " " + S.text_(rows[i], "name") + " " + S.text_(rows[i], "label")).toLowerCase()
            if (text.indexOf("sin comprobante") >= 0 || text.indexOf("sin_comprobante") >= 0
                    || text.indexOf("declaración jurada") >= 0 || text.indexOf("declaracion jurada") >= 0
                    || text.indexOf("declaracion_jurada") >= 0)
                return rows[i]
        }
        return null
    }
    readonly property var previousExpenses: {
        var out = []
        var own = app.st.expenses || []
        for (var i = own.length - 1; i >= 0; --i)
            if (own[i].archived !== true && own[i].localId !== expenseLocalId && own[i].localId !== savedId) out.push(own[i])
        var rows = app.st.renditions || []
        for (var r = 0; r < rows.length && out.length < 12; ++r) {
            if (rows[r].localId === renditionLocalId) continue
            var list = rows[r].expenses || []
            for (var k = list.length - 1; k >= 0 && out.length < 12; --k)
                if (list[k].archived !== true) out.push(list[k])
        }
        return out.slice(0, 8)
    }
    function supportTypeLabel(code) {
        for (var i = 0; i < supportTypes.length; ++i)
            if (S.text_(supportTypes[i], "code") === code) return S.text_(supportTypes[i], "name") || S.text_(supportTypes[i], "label") || code
        return code
    }
    function isInvoice() {
        var t = (supportTypeCode + " " + supportTypeLabel(supportTypeCode)).toLowerCase()
        return t.indexOf("factura") >= 0 || t.indexOf("invoice") >= 0
    }
    function money(value) { return ctl.formatMoney(value, currencyCode) }
    function cents(text) {
        var t = String(text || "").replace(",", ".").trim()
        if (!t.length || ctl.amountError(t).length) return null
        return Math.round(Number(t) * 100)
    }
    // Herramienta -> resultado en un menú anclado al botón ··· (título, texto y acción).
    property string toolTitle: ""
    property string toolBody: ""
    property string toolActionLabel: ""
    property var toolAction: null
    function anchorAtMore(menu) {
        var p = app.dockCellPoint(3)
        menu.anchorX = p.x; menu.anchorY = p.y
        menu.open = true
    }
    function showTool(title, body, actionLabel, action) {
        toolTitle = title; toolBody = body
        toolActionLabel = actionLabel || ""; toolAction = action || null
        anchorAtMore(toolMenu)
    }
    function closeTools() { toolMenu.close(); reuseMenu.close(); fileMenu.close(); filesMenu.close() }
    function runTool(key) {
        if (key === "today") {
            if (!writable) return
            expenseDate = ctl.today(); changed()
            var inside = expenseDate >= String(rendition.periodStart || "") && expenseDate <= String(rendition.periodEnd || "")
            if (!inside) {
                setFieldError("date", "Hoy está fuera del período de la rendición (" + S.period(rendition.periodStart, rendition.periodEnd) + ").")
                showTool("Fecha de hoy", "Se colocó " + S.date(expenseDate) + ", pero está fuera del período de la rendición ("
                         + S.period(rendition.periodStart, rendition.periodEnd) + "). Corrígela antes de registrar.")
            }
            return
        }
        if (key === "period") {
            var start = String(rendition.periodStart || ""), end = String(rendition.periodEnd || "")
            var ok = expenseDate.length && expenseDate >= start && expenseDate <= end
            showTool("Período permitido", "Período de la rendición: " + S.period(start, end) + ".\n"
                     + (!expenseDate.length ? "Aún no indicaste la fecha del gasto."
                        : ok ? "La fecha " + S.date(expenseDate) + " está dentro del período."
                             : "La fecha " + S.date(expenseDate) + " está FUERA del período: el gasto no se podrá registrar con esa fecha."))
            return
        }
        if (key === "reuse") { if (writable && previousExpenses.length) anchorAtMore(reuseMenu); return }
        if (key === "requirements") {
            var label = supportTypeCode.length ? supportTypeLabel(supportTypeCode) : ""
            var missing = []
            if (!supportTypeCode.length) missing.push("tipo de comprobante")
            if (!categoryCode.length) missing.push("categoría")
            if (!paymentMethodCode.length) missing.push("medio de pago")
            if (!conceptField.text.trim().length) missing.push("concepto")
            if (!amountField.text.trim().length) missing.push("importe")
            showTool("Requisitos del comprobante",
                     (label.length ? "Tipo seleccionado: " + label + ".\n" : "Primero elige el tipo de comprobante.\n")
                     + "Para registrar el gasto se requiere: tipo de comprobante, categoría, medio de pago, concepto descriptivo, "
                     + "fecha dentro del período e importe mayor que cero."
                     + (isInvoice() ? "\nEn una factura indica su serie y número y el RUC del proveedor; el IGV puede desglosarse." : "")
                     + (missing.length ? "\nAún falta: " + missing.join(", ") + "." : "\nLos datos obligatorios están completos.")
                     + "\nAdjunta el comprobante en Sustentos para que la revisión lo valide.")
            return
        }
        if (key === "noReceipt") {
            if (!noReceiptType || !writable) return
            var nr = noReceiptType
            app.confirm("Registrar sin comprobante", "Se usará el tipo «" + (S.text_(nr, "name") || S.text_(nr, "code"))
                        + "». La justificación del gasto será necesaria y el revisor podrá observarlo.", "Usar este tipo", false, function() {
                page.supportTypeCode = S.text_(nr, "code"); page.changed(); page.goToSection(3)
            })
            return
        }
        if (key === "help") {
            var names = supportTypes.map(function(r) { return S.text_(r, "name") || S.text_(r, "label") || S.text_(r, "code") })
            showTool("Ayuda sobre comprobantes",
                     (names.length ? "Tipos disponibles: " + names.join(", ") + ".\n" : "")
                     + "El comprobante debe ser válido, estar a nombre correcto y corresponder al gasto realizado. "
                     + "Usa el número tal como figura en el documento (serie y correlativo).")
            return
        }
        if (key === "igv") {
            var total = cents(amountField.text)
            if (total === null) { showTool("Calcular IGV", "Indica primero el importe total del comprobante."); return }
            if (!isInvoice()) {
                showTool("Calcular IGV", "El IGV sólo se desglosa en comprobantes con crédito fiscal (factura). "
                         + "Con el tipo seleccionado no se calcula: deja Subtotal e IGV vacíos o según el documento.")
                return
            }
            // Tasa general vigente del IGV en Perú (18 %). Existen tasas especiales:
            // el usuario confirma antes de aplicar; nada se calcula sin su decisión.
            var sub = Math.round(total / 1.18), igv = total - sub
            showTool("Calcular IGV (tasa general 18 %)",
                     "Total " + money((total / 100).toFixed(2)) + " = Subtotal " + money((sub / 100).toFixed(2))
                     + " + IGV " + money((igv / 100).toFixed(2)) + ".\nSi tu comprobante aplica una tasa especial, ingresa los valores del documento.",
                     writable ? "Aplicar al formulario" : "", function() {
                         subtotalField.text = (sub / 100).toFixed(2); igvField.text = (igv / 100).toFixed(2); page.changed()
                     })
            return
        }
        if (key === "amounts") {
            var problems = []
            var t2 = cents(amountField.text), s2 = cents(subtotalField.text), i2 = cents(igvField.text)
            if (!amountField.text.trim().length) problems.push("Falta el importe total.")
            else if (t2 === null) problems.push("El importe total no tiene un formato válido.")
            else if (t2 <= 0) problems.push("El importe total debe ser mayor que cero.")
            if (subtotalField.text.trim().length && s2 === null) problems.push("El subtotal no tiene un formato válido.")
            if (igvField.text.trim().length && i2 === null) problems.push("El IGV no tiene un formato válido.")
            if (t2 !== null && s2 !== null && i2 !== null && Math.abs(s2 + i2 - t2) > 1)
                problems.push("Subtotal + IGV (" + money(((s2 + i2) / 100).toFixed(2)) + ") no coincide con el total (" + money((t2 / 100).toFixed(2)) + ").")
            if (t2 !== null && s2 !== null && i2 === null && s2 > t2) problems.push("El subtotal supera el total.")
            if (currencyCode !== "PEN" && currencyCode !== "USD") problems.push("Elige la moneda (PEN o USD).")
            showTool("Validar importes", problems.length ? problems.join("\n") : "Los importes son consistentes.")
            return
        }
        if (key === "breakdown") {
            var tt = cents(amountField.text), ss = cents(subtotalField.text), ii = cents(igvField.text)
            showTool("Desglose del importe",
                     tt === null ? "Aún no hay un importe total válido."
                     : "Moneda: " + (currencyCode === "USD" ? "dólares (USD)" : "soles (PEN)") + ".\nTotal: " + money((tt / 100).toFixed(2))
                       + (ss !== null ? "\nSubtotal: " + money((ss / 100).toFixed(2)) : "")
                       + (ii !== null ? "\nIGV: " + money((ii / 100).toFixed(2)) : "")
                       + (ss === null && ii === null ? "\nSin desglose de impuestos (opcional)." : ""))
            return
        }
        if (key === "files") { if (fileCount > 0) { goToSection(3); anchorAtMore(filesMenu) } return }
        if (key === "replace") {
            var candidates = fileRows.filter(function(r) { return page.canReplace(r) })
            if (!candidates.length) return
            if (candidates.length === 1) replaceFile(candidates[0])
            else { goToSection(3); filesMenu.replacing = true; anchorAtMore(filesMenu) }
            return
        }
        if (key === "retry") { if (pendingUploads > 0) app.synchronize(true); return }
    }
    function reuse(row) {
        var apply = function() {
            if (row.categoryCode) page.categoryCode = String(row.categoryCode)
            if ((page.rendition.projectIds || []).indexOf(String(row.projectId || "")) >= 0) page.projectId = String(row.projectId)
            page.beneficiaryField.text = S.text_(row, "beneficiary")
            page.rucField.text = S.text_(row, "ruc")
            if (row.paymentMethodCode) page.paymentMethodCode = String(row.paymentMethodCode)
            page.paymentDetailField.text = S.text_(row, "paymentMethodDetail", "payment_method_detail")
            if (row.supportTypeCode) page.supportTypeCode = String(row.supportTypeCode)
            if (row.currencyCode) page.currencyCode = String(row.currencyCode)
            page.changed()
        }
        reuseMenu.close()
        // Datos compatibles (no importe, fecha ni número de comprobante). Si ya hay
        // datos escritos, se pide confirmación antes de sobrescribirlos.
        var filled = categoryCode.length || beneficiaryField.text.length || paymentMethodCode.length || supportTypeCode.length
        if (filled) app.confirm("Reutilizar datos anteriores", "Se copiarán categoría, proyecto, proveedor, RUC, medio de pago y tipo de comprobante de «"
                                + (S.text_(row, "concept") || "gasto anterior") + "». Los datos actuales se reemplazarán.", "Reutilizar", false, apply)
        else apply()
    }

    // ================================================================= Vista
    property alias toolMenu: toolMenu
    property alias reuseMenu: reuseMenu
    property alias pagerTrack: track
    property alias beneficiaryField: beneficiaryField
    property alias rucField: rucField
    property alias paymentDetailField: paymentDetailField
    readonly property var flowRef: app.flow !== undefined ? app.flow : null      // motor único InGeCoreFlow (IME)
    readonly property bool reduced: ui.reducedMotion === true

    // Tarjeta de sección (vidrio claro de los previews): título grande + subtítulo.
    component SectionCard: Rectangle {
        id: sectionCard
        property var ui
        property string heading: ""
        property string subtitle: ""
        default property alias content: cardBody.data
        width: parent ? parent.width : 0
        implicitHeight: cardColumn.implicitHeight + 40 * ui.u
        height: implicitHeight
        radius: 24 * ui.u
        color: S.cardGlass
        border.width: 1
        border.color: S.edge(0.9)
        Rectangle {                                   // sombra muy suave (estática)
            z: -1
            anchors.fill: parent
            anchors.topMargin: 6 * sectionCard.ui.u
            radius: parent.radius
            color: S.ink(0.035)
        }
        Column {
            id: cardColumn
            x: 20 * sectionCard.ui.u; y: 22 * sectionCard.ui.u
            width: parent.width - 40 * sectionCard.ui.u
            spacing: 14 * sectionCard.ui.u
            Column {
                width: parent.width
                spacing: 4 * sectionCard.ui.u
                visible: sectionCard.heading.length > 0
                Text { width: parent.width; text: sectionCard.heading; color: S.text; wrapMode: Text.WordWrap
                       font.family: sectionCard.ui.fontFamily; font.pixelSize: 26 * sectionCard.ui.u; font.weight: Font.DemiBold }
                Text { width: parent.width; visible: sectionCard.subtitle.length > 0; text: sectionCard.subtitle; color: S.muted
                       wrapMode: Text.WordWrap; font.family: sectionCard.ui.fontFamily; font.pixelSize: 15 * sectionCard.ui.u }
            }
            Column { id: cardBody; width: parent.width; spacing: 14 * sectionCard.ui.u }
        }
    }
    // Nota informativa (azul) del preview de Comprobante; tono configurable.
    component Notice: Rectangle {
        id: notice
        property var ui
        property string text: ""
        property color tone: S.corporateBlue
        property int glyph: 0xE0F9                    // info (Lucide)
        width: parent ? parent.width : 0
        height: noticeText.implicitHeight + 28 * ui.u
        radius: 18 * ui.u
        color: Qt.rgba(tone.r, tone.g, tone.b, 0.08)
        border.width: 1
        border.color: Qt.rgba(tone.r, tone.g, tone.b, 0.10)
        Text { id: noticeIcon; x: 16 * notice.ui.u; y: 14 * notice.ui.u; text: String.fromCharCode(notice.glyph)
               color: notice.tone; font.family: notice.ui.iconFamily; font.pixelSize: 22 * notice.ui.u }
        Text { id: noticeText; x: 50 * notice.ui.u; y: 14 * notice.ui.u; width: parent.width - 66 * notice.ui.u
               text: notice.text; color: notice.tone; wrapMode: Text.WordWrap
               font.family: notice.ui.fontFamily; font.pixelSize: 15 * notice.ui.u }
    }
    // Línea discreta con el fallo operativo y acceso REAL al diagnóstico.
    component OperationLine: Text {
        property var ui
        property Item owner
        width: parent ? parent.width : 0
        visible: !!owner && owner.opError.length > 0
        text: owner ? owner.opError + '  ·  Ver estado' : ''
        color: S.danger
        wrapMode: Text.WordWrap
        font.family: ui.fontFamily; font.pixelSize: 13 * ui.u
        MouseArea { anchors.fill: parent; onClicked: parent.owner.openStatus() }
    }
    // Error de validación que no corresponde a un campo concreto.
    component FormLine: Text {
        property var ui
        property Item owner
        property int forSection: 0
        width: parent ? parent.width : 0
        visible: !!owner && owner.section === forSection && owner.fieldError('form').length > 0
        text: owner ? owner.fieldError('form') : ''
        color: S.danger
        wrapMode: Text.WordWrap
        font.family: ui.fontFamily; font.pixelSize: 13 * ui.u
    }

    Item {
        id: pager
        objectName: "expensePager"
        anchors.fill: parent
        clip: true

        // Navegación táctil entre las CUATRO secciones del mismo gasto.
        // Drag horizontal: sigue al dedo; flick vertical: pertenece a cada
        // ImeAwareFlickable. Ni el gesto ni su cancelación guardan o registran.
        property bool swipeTracking: false
        property real swipeOffset: 0
        property real swipeOriginX: 0
        property real swipeVelocityX: 0

        function followSwipe(dx) {
            var firstEdge = page.section === 0 && dx > 0
            var lastEdge = page.lastSection && dx < 0
            if (firstEdge || lastEdge) {
                // Resistencia visual: no salir del formulario por swipe.
                swipeOffset = (dx < 0 ? -1 : 1) * Math.min(28 * page.ui.u, Math.abs(dx) * 0.18)
                return
            }
            swipeOffset = Math.max(-width * 0.95, Math.min(width * 0.95, dx))
        }

        DragHandler {
            id: sectionSwipe
            target: null
            yAxis.enabled: false
            acceptedButtons: Qt.LeftButton
            minimumPointCount: 1
            maximumPointCount: 1
            dragThreshold: Math.round(11 * page.ui.u)
            enabled: page.resultKind.length === 0 && !page.saving
            onActiveChanged: {
                if (active) {
                    var dx = centroid.scenePosition.x - centroid.scenePressPosition.x
                    var dy = centroid.scenePosition.y - centroid.scenePressPosition.y
                    pager.swipeOriginX = centroid.scenePosition.x
                    pager.swipeVelocityX = 0
                    // No interrumpir escritura con teclado ni scroll vertical.
                    pager.swipeTracking = !(page.flowRef && page.flowRef.imeVisible === true)
                                          && Math.abs(dx) > Math.abs(dy) * 1.2
                    return
                }
                if (!pager.swipeTracking) return
                var travelled = pager.swipeOffset
                var velocity = pager.swipeVelocityX
                pager.swipeTracking = false
                var dir = travelled < 0 ? 1 : -1
                var destination = page.section + dir
                var inside = destination >= 0 && destination < page.sections.length
                var enoughDistance = Math.abs(travelled) >= pager.width * 0.24
                var fastEnough = Math.abs(travelled) >= 28 * page.ui.u
                                 && velocity * (travelled < 0 ? -1 : 1) >= 560 * page.ui.u
                // MISMO camino de navegación que el Dock; máximo una sección.
                if (inside && (enoughDistance || fastEnough))
                    page.goToSection(destination)
                pager.swipeOffset = 0
            }
            onCentroidChanged: {
                if (!active || !pager.swipeTracking) return
                pager.swipeVelocityX = centroid.velocity.x
                pager.followSwipe(centroid.scenePosition.x - pager.swipeOriginX)
            }
        }

        Row {
            id: track
            objectName: "expenseTrack"
            height: pager.height
            // Seguimiento directo del dedo; settle suave al soltar.
            x: -page.section * pager.width + pager.swipeOffset
            Behavior on x { enabled: !pager.swipeTracking && !page.reduced; NumberAnimation { duration: 300; easing.type: Easing.OutCubic } }

            // ---------------------------------------------------- GENERAL
            FlowCore.ImeAwareFlickable {
                width: pager.width; height: pager.height
                flow: page.flowRef
                contentWidth: width; contentHeight: generalColumn.height + page.ui.dockArea + 40 * page.ui.u
                boundsBehavior: Flickable.StopAtBounds; clip: true
                Column {
                    id: generalColumn
                    x: page.ui.gutter; y: 8 * page.ui.u
                    width: parent.width - 2 * page.ui.gutter
                    spacing: 14 * page.ui.u
                    Notice { ui: page.ui; visible: page.restored; text: "Se recuperaron los datos que estabas escribiendo." }
                    Notice { ui: page.ui; visible: !page.writable && page.resultKind === ""; tone: S.warning; glyph: 0xE193
                             text: page.draftBlocked ? "Este borrador está en conflicto o en registro; revísalo desde la lista de gastos."
                                                     : "Gasto en solo lectura: la rendición no tiene permiso efectivo de edición." }
                    SectionCard {
                        ui: page.ui; heading: "Información general"; subtitle: "Datos principales del gasto."
                        OperationLine { ui: page.ui; owner: page }
                        FormLine { ui: page.ui; owner: page; forSection: 0 }
                        RSelect {
                            width: parent.width; ui: page.ui; formStyle: true; glyph: 0xE0D7
                            label: "Proyecto *"; placeholder: "Seleccionar proyecto"; readOnly: !page.writable
                            options: page.projectOptions; value: page.projectId; error: page.fieldError("project")
                            onPicked: function(v) { page.projectId = v; page.changed() }
                        }
                        RDateField {
                            width: parent.width; ui: page.ui; formStyle: true; clearable: true
                            label: "Fecha del gasto *"; readOnly: !page.writable
                            value: page.expenseDate; error: page.fieldError("date")
                            minimum: String(page.rendition.periodStart || ""); maximum: String(page.rendition.periodEnd || "")
                            onPicked: function(v) { page.expenseDate = v; page.changed() }
                        }
                        RSelect {
                            width: parent.width; ui: page.ui; formStyle: true; glyph: 0xE17F
                            label: "Categoría *"; placeholder: "Seleccionar categoría"; readOnly: !page.writable
                            options: { page.app.st; return page.catalogOptions("CATEGORY") }
                            value: page.categoryCode; error: page.fieldError("category")
                            onPicked: function(v) { page.categoryCode = v; page.changed() }
                        }
                        RField { id: conceptField; width: parent.width; ui: page.ui; formStyle: true; glyph: 0xE0CC
                                 label: "Concepto *"; placeholder: "Describe el gasto…"; readOnly: !page.writable
                                 error: page.fieldError("concept"); onEdited: page.changed() }
                        RField { id: beneficiaryField; width: parent.width; ui: page.ui; formStyle: true; glyph: 0xE19F
                                 label: "Proveedor / Beneficiario"; placeholder: "Nombre del proveedor…"; readOnly: !page.writable; onEdited: page.changed() }
                        RField { id: rucField; width: parent.width; ui: page.ui; formStyle: true; glyph: 0xE0AA
                                 label: "RUC (opcional)"; placeholder: "Ingrese RUC…"; numeric: true; maxLength: 11; readOnly: !page.writable; onEdited: page.changed() }
                    }
                }
            }
            // ------------------------------------------------- COMPROBANTE
            FlowCore.ImeAwareFlickable {
                width: pager.width; height: pager.height
                flow: page.flowRef
                contentWidth: width; contentHeight: receiptColumn.height + page.ui.dockArea + 40 * page.ui.u
                boundsBehavior: Flickable.StopAtBounds; clip: true
                Column {
                    id: receiptColumn
                    x: page.ui.gutter; y: 8 * page.ui.u
                    width: parent.width - 2 * page.ui.gutter
                    spacing: 14 * page.ui.u
                    SectionCard {
                        ui: page.ui; heading: "Comprobante"; subtitle: "Información del comprobante de pago."
                        OperationLine { ui: page.ui; owner: page }
                        FormLine { ui: page.ui; owner: page; forSection: 1 }
                        // Tipo de comprobante (imagen 4): selector compacto con los tipos REALES del catálogo.
                        Text { text: "Tipo de comprobante *"; color: S.text; font.family: page.ui.fontFamily; font.pixelSize: 15 * page.ui.u; font.weight: Font.DemiBold }
                        Flow {
                            id: supportTypeFlow
                            objectName: "supportTypeChips"
                            width: parent.width
                            spacing: 8 * page.ui.u
                            Repeater {
                                model: { page.app.st; return page.catalogOptions("SUPPORT_TYPE") }
                                delegate: Rectangle {
                                    required property var modelData
                                    readonly property bool selected: page.supportTypeCode === modelData.value
                                    height: 44 * page.ui.u
                                    width: Math.max(84 * page.ui.u, typeText.implicitWidth + 30 * page.ui.u)
                                    radius: 14 * page.ui.u
                                    color: selected ? Qt.rgba(6 / 255, 84 / 255, 162 / 255, 0.10) : (typeTap.pressed ? S.ink(0.08) : S.glass(0.78))
                                    border.width: selected ? 1.5 : 1
                                    border.color: selected ? S.accent : S.fieldBorder
                                    opacity: page.writable ? 1 : 0.5
                                    Behavior on color { ColorAnimation { duration: page.reduced ? 0 : 140 } }
                                    Text { id: typeText; anchors.centerIn: parent; text: modelData.label
                                           color: parent.selected ? S.accent : S.text
                                           font.family: page.ui.fontFamily; font.pixelSize: 15 * page.ui.u
                                           font.weight: parent.selected ? Font.DemiBold : Font.Normal }
                                    MouseArea { id: typeTap; anchors.fill: parent; enabled: page.writable
                                                onClicked: { page.supportTypeCode = modelData.value; page.app.haptic("selection"); page.changed() } }
                                    Accessible.role: Accessible.Button
                                    Accessible.name: modelData.label
                                    Accessible.checked: selected
                                }
                            }
                        }
                        Text { visible: page.fieldError("supportType").length > 0; width: parent.width; text: page.fieldError("supportType")
                               color: S.danger; wrapMode: Text.WordWrap; font.family: page.ui.fontFamily; font.pixelSize: 13 * page.ui.u }
                        RField { id: supportNumberField; width: parent.width; ui: page.ui; formStyle: true; glyph: 0xE0EF
                                 label: "Número de comprobante"; placeholder: "Ingrese número…"; readOnly: !page.writable; onEdited: page.changed() }
                        RField { id: supportDetailField; width: parent.width; ui: page.ui; formStyle: true; glyph: 0xE0CC
                                 label: "Detalle del comprobante (opcional)"; placeholder: "Serie, emisor u otro dato…"; readOnly: !page.writable; onEdited: page.changed() }
                        Notice { ui: page.ui; text: "El comprobante debe ser válido y corresponder al gasto realizado." }
                    }
                }
            }
            // ---------------------------------------------- PAGO E IMPORTE
            FlowCore.ImeAwareFlickable {
                width: pager.width; height: pager.height
                flow: page.flowRef
                contentWidth: width; contentHeight: paymentColumn.height + page.ui.dockArea + 40 * page.ui.u
                boundsBehavior: Flickable.StopAtBounds; clip: true
                Column {
                    id: paymentColumn
                    x: page.ui.gutter; y: 8 * page.ui.u
                    width: parent.width - 2 * page.ui.gutter
                    spacing: 14 * page.ui.u
                    SectionCard {
                        ui: page.ui; heading: "Pago e importe"; subtitle: "Cómo se realizó el pago."
                        OperationLine { ui: page.ui; owner: page }
                        FormLine { ui: page.ui; owner: page; forSection: 2 }
                        // Medio de pago (imagen 4): mosaicos con los medios REALES del catálogo
                        // (sin códigos nuevos); el icono se elige por el nombre del medio.
                        Text { text: "Medio de pago *"; color: S.text; font.family: page.ui.fontFamily; font.pixelSize: 15 * page.ui.u; font.weight: Font.DemiBold }
                        Grid {
                            id: payGrid
                            objectName: "paymentTiles"
                            width: parent.width
                            columns: 4
                            spacing: 8 * page.ui.u
                            Repeater {
                                model: { page.app.st; return page.catalogOptions("PAYMENT_METHOD") }
                                delegate: Rectangle {
                                    required property var modelData
                                    readonly property bool selected: page.paymentMethodCode === modelData.value
                                    readonly property string key: (modelData.label + " " + modelData.value).toLowerCase()
                                    width: (payGrid.width - 3 * payGrid.spacing) / 4
                                    height: 84 * page.ui.u
                                    radius: 16 * page.ui.u
                                    color: selected ? S.accent : (payTap.pressed ? S.ink(0.08) : S.glass(0.78))
                                    border.width: 1
                                    border.color: selected ? S.accent : S.fieldBorder
                                    opacity: page.writable ? 1 : 0.5
                                    scale: payTap.pressed && !page.reduced ? 0.97 : 1
                                    Behavior on scale { NumberAnimation { duration: 120 } }
                                    Column {
                                        anchors.centerIn: parent
                                        width: parent.width - 8 * page.ui.u
                                        spacing: 6 * page.ui.u
                                        Text {
                                            anchors.horizontalCenter: parent.horizontalCenter
                                            // banknote · smartphone · repeat (transferencia) · credit-card (Lucide verificados)
                                            text: String.fromCharCode(parent.parent.key.indexOf("efectivo") >= 0 || parent.parent.key.indexOf("cash") >= 0 ? 0xE052
                                                  : parent.parent.key.indexOf("yape") >= 0 || parent.parent.key.indexOf("plin") >= 0 ? 0xE163
                                                  : parent.parent.key.indexOf("transfer") >= 0 || parent.parent.key.indexOf("depósito") >= 0 ? 0xE146 : 0xE0AA)
                                            color: parent.parent.selected ? S.onAccent : S.navy
                                            font.family: page.ui.iconFamily; font.pixelSize: 24 * page.ui.u
                                        }
                                        Text { width: parent.width; horizontalAlignment: Text.AlignHCenter; text: modelData.label
                                               color: parent.parent.selected ? S.onAccent : S.text; elide: Text.ElideRight
                                               font.family: page.ui.fontFamily; font.pixelSize: 12 * page.ui.u }
                                    }
                                    MouseArea { id: payTap; anchors.fill: parent; enabled: page.writable
                                                onClicked: { page.paymentMethodCode = modelData.value; page.app.haptic("selection"); page.changed() } }
                                    Accessible.role: Accessible.Button
                                    Accessible.name: modelData.label
                                    Accessible.checked: selected
                                }
                            }
                        }
                        Text { visible: page.fieldError("payment").length > 0; width: parent.width; text: page.fieldError("payment")
                               color: S.danger; wrapMode: Text.WordWrap; font.family: page.ui.fontFamily; font.pixelSize: 13 * page.ui.u }
                        RField { id: paymentDetailField; width: parent.width; ui: page.ui; formStyle: true; glyph: 0xE0CC
                                 label: "Detalle de pago (opcional)"; placeholder: "Banco, tarjeta, operación, etc…"; readOnly: !page.writable; onEdited: page.changed() }
                    }
                    SectionCard {
                        ui: page.ui; heading: "Importes"; subtitle: "Monto del gasto."
                        Text { text: "Moneda *"; color: S.text; font.family: page.ui.fontFamily; font.pixelSize: 15 * page.ui.u; font.weight: Font.DemiBold }
                        Row {                                // control segmentado PEN | USD
                            id: currencyRow
                            width: parent.width
                            spacing: 10 * page.ui.u
                            Repeater {
                                model: ["PEN", "USD"]
                                delegate: Rectangle {
                                    required property string modelData
                                    readonly property bool selected: page.currencyCode === modelData
                                    width: (currencyRow.width - currencyRow.spacing) / 2
                                    height: 50 * page.ui.u
                                    radius: 16 * page.ui.u
                                    color: selected ? S.accent : (currencyTap.pressed ? S.ink(0.10) : S.ink(0.05))
                                    border.width: selected ? 0 : 1
                                    border.color: S.fieldBorder
                                    opacity: page.writable ? 1 : 0.5
                                    Behavior on color { ColorAnimation { duration: page.reduced ? 0 : 160 } }
                                    Text { anchors.centerIn: parent; text: modelData; color: parent.selected ? S.onAccent : S.text
                                           font.family: page.ui.fontFamily; font.pixelSize: 16 * page.ui.u; font.weight: Font.DemiBold }
                                    MouseArea { id: currencyTap; anchors.fill: parent; enabled: page.writable
                                                onClicked: { page.currencyCode = modelData; page.app.haptic("selection"); page.changed() } }
                                    Accessible.role: Accessible.Button
                                    Accessible.name: modelData
                                    Accessible.checked: selected
                                }
                            }
                        }
                        Text { visible: page.fieldError("currency").length > 0; width: parent.width; text: page.fieldError("currency")
                               color: S.danger; wrapMode: Text.WordWrap; font.family: page.ui.fontFamily; font.pixelSize: 13 * page.ui.u }
                        RField {
                            id: amountField; width: parent.width; ui: page.ui; formStyle: true
                            prefix: page.currencyCode === "USD" ? "US$" : "S/"
                            label: "Importe total *"; placeholder: "0.00"; numeric: true; readOnly: !page.writable
                            error: page.fieldError("amount") || (text.length ? page.ctl.amountError(text) : "")
                            onEdited: page.changed()
                        }
                        RField { id: subtotalField; width: parent.width; ui: page.ui; formStyle: true; prefix: page.currencyCode === "USD" ? "US$" : "S/"
                                 label: "Subtotal (opcional)"; placeholder: "0.00"; numeric: true; readOnly: !page.writable; onEdited: page.changed() }
                        RField { id: igvField; width: parent.width; ui: page.ui; formStyle: true; prefix: page.currencyCode === "USD" ? "US$" : "S/"
                                 label: "IGV (opcional)"; placeholder: "0.00"; numeric: true; readOnly: !page.writable; onEdited: page.changed() }
                    }
                }
            }
            // --------------------------------------------------- SUSTENTOS
            FlowCore.ImeAwareFlickable {
                width: pager.width; height: pager.height
                flow: page.flowRef
                contentWidth: width; contentHeight: supportsColumn.height + page.ui.dockArea + 40 * page.ui.u
                boundsBehavior: Flickable.StopAtBounds; clip: true
                Column {
                    id: supportsColumn
                    x: page.ui.gutter; y: 8 * page.ui.u
                    width: parent.width - 2 * page.ui.gutter
                    spacing: 14 * page.ui.u
                    SectionCard {
                        ui: page.ui; heading: "Sustentos"; subtitle: "Adjunta fotos, documentos o archivos del gasto."
                        OperationLine { ui: page.ui; owner: page }
                        FormLine { ui: page.ui; owner: page; forSection: 3 }
                        Row {                                // mosaicos de captura
                            id: tiles
                            width: parent.width
                            spacing: 10 * page.ui.u
                            visible: page.writable
                            Repeater {
                                model: [{ key: "camera", glyph: 0xE064, label: "Tomar foto" },
                                        { key: "gallery", glyph: 0xE0F6, label: "Galería" },
                                        { key: "file", glyph: 0xE12D, label: "PDF / Archivo" }]
                                delegate: Rectangle {
                                    required property var modelData
                                    width: (tiles.width - 2 * tiles.spacing) / 3
                                    height: 96 * page.ui.u
                                    radius: 18 * page.ui.u
                                    color: tileTap.pressed ? Qt.rgba(6 / 255, 84 / 255, 162 / 255, 0.14) : S.tintSoft
                                    border.width: 1; border.color: S.tintSoftBorder
                                    scale: tileTap.pressed && !page.reduced ? 0.97 : 1
                                    Behavior on scale { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
                                    opacity: page.saving || (page.waitingPhoto && modelData.key !== "file") ? 0.5 : 1
                                    Column {
                                        anchors.centerIn: parent
                                        spacing: 8 * page.ui.u
                                        Text { anchors.horizontalCenter: parent.horizontalCenter; text: String.fromCharCode(modelData.glyph)
                                               color: S.accent; font.family: page.ui.iconFamily; font.pixelSize: 30 * page.ui.u }
                                        Text { anchors.horizontalCenter: parent.horizontalCenter; text: modelData.label; color: S.accent
                                               font.family: page.ui.fontFamily; font.pixelSize: 14 * page.ui.u; font.weight: Font.DemiBold }
                                    }
                                    MouseArea {
                                        id: tileTap
                                        anchors.fill: parent
                                        enabled: !page.saving && !(page.waitingPhoto && modelData.key !== "file")
                                        onClicked: modelData.key === "camera" ? page.requestPhoto(true)
                                                 : modelData.key === "gallery" ? page.requestPhoto(false) : fileDialog.open()
                                    }
                                    Accessible.role: Accessible.Button
                                    Accessible.name: modelData.label
                                }
                            }
                        }
                        Text { visible: page.fieldError("files").length > 0; width: parent.width; text: page.fieldError("files")
                               color: S.danger; wrapMode: Text.WordWrap; font.family: page.ui.fontFamily; font.pixelSize: 13 * page.ui.u }
                        Repeater {                            // filas de archivo (miniatura, nombre, tipo/tamaño, ⋮)
                            model: page.fileRows
                            delegate: Rectangle {
                                id: fileRow
                                required property var modelData
                                width: supportsColumn.width - 40 * page.ui.u
                                height: 76 * page.ui.u
                                radius: 18 * page.ui.u
                                color: S.glass(0.72)
                                border.width: 1; border.color: S.fieldBorder
                                Rectangle {
                                    id: thumb
                                    x: 12 * page.ui.u
                                    width: 52 * page.ui.u; height: width; radius: 12 * page.ui.u
                                    anchors.verticalCenter: parent.verticalCenter
                                    clip: true
                                    readonly property bool pdf: String(fileRow.modelData.name).toLowerCase().indexOf(".pdf") > 0
                                                                || String(fileRow.modelData.mime).indexOf("pdf") >= 0
                                    color: pdf ? "#E5322D" : S.tintSoft
                                    Image {
                                        anchors.fill: parent
                                        visible: page.isImage(fileRow.modelData) && String(fileRow.modelData.localUri || "").length > 0
                                        source: visible ? page.localUrl(fileRow.modelData.localUri) : ""
                                        sourceSize.width: 104; sourceSize.height: 104
                                        fillMode: Image.PreserveAspectCrop
                                        asynchronous: true
                                    }
                                    Text { anchors.centerIn: parent
                                           visible: !(page.isImage(fileRow.modelData) && String(fileRow.modelData.localUri || "").length > 0)
                                           text: thumb.pdf ? "PDF" : String.fromCharCode(page.isImage(fileRow.modelData) ? 0xE0F6 : 0xE0CC)
                                           color: thumb.pdf ? "#FFFFFF" : S.accent
                                           font.family: thumb.pdf ? page.ui.fontFamily : page.ui.iconFamily
                                           font.pixelSize: (thumb.pdf ? 14 : 24) * page.ui.u; font.weight: Font.Bold }
                                }
                                Column {
                                    x: 78 * page.ui.u
                                    width: parent.width - x - 52 * page.ui.u
                                    anchors.verticalCenter: parent.verticalCenter
                                    spacing: 3 * page.ui.u
                                    Text { width: parent.width; text: fileRow.modelData.name; color: S.text; elide: Text.ElideMiddle
                                           font.family: page.ui.fontFamily; font.pixelSize: 16 * page.ui.u; font.weight: Font.DemiBold }
                                    Text { width: parent.width; text: page.fileMeta(fileRow.modelData); elide: Text.ElideRight
                                           color: fileRow.modelData.state === "Falta volver a adjuntar" || fileRow.modelData.state === "Carga no completada" ? S.warning : S.muted
                                           font.family: page.ui.fontFamily; font.pixelSize: 13 * page.ui.u }
                                }
                                Rectangle {                    // menú ⋮ del archivo
                                    id: kebab
                                    width: 44 * page.ui.u; height: width; radius: width / 2
                                    anchors.right: parent.right; anchors.rightMargin: 6 * page.ui.u
                                    anchors.verticalCenter: parent.verticalCenter
                                    color: kebabTap.pressed ? S.ink(0.08) : "transparent"
                                    Text { anchors.centerIn: parent; text: String.fromCharCode(0xE0B7); color: S.text
                                           font.family: page.ui.iconFamily; font.pixelSize: 22 * page.ui.u }
                                    MouseArea { id: kebabTap; anchors.fill: parent; onClicked: page.openFileMenu(fileRow.modelData, kebab) }
                                    Accessible.role: Accessible.Button
                                    Accessible.name: "Opciones de " + fileRow.modelData.name
                                }
                            }
                        }
                        Text {
                            width: parent.width
                            visible: page.fileCount === 0
                            text: "Aún no hay sustentos adjuntos."
                            color: S.faint; font.family: page.ui.fontFamily; font.pixelSize: 14 * page.ui.u
                        }
                    }
                    SectionCard {
                        ui: page.ui; heading: "Justificación"; subtitle: "Relación del gasto con el trabajo (opcional)."
                        TextArea {
                            id: justificationField
                            width: parent.width
                            height: Math.max(120 * page.ui.u, implicitHeight)
                            wrapMode: TextEdit.Wrap
                            readOnly: !page.writable
                            color: S.text
                            placeholderText: "Describe la relación del gasto con el proyecto, actividad o necesidad…"
                            placeholderTextColor: S.faint
                            font.family: page.ui.fontFamily
                            font.pixelSize: 16 * page.ui.u
                            leftPadding: 16 * page.ui.u; rightPadding: 16 * page.ui.u
                            topPadding: 14 * page.ui.u; bottomPadding: 14 * page.ui.u
                            background: Rectangle {
                                radius: 16 * page.ui.u
                                color: S.glass(0.78)
                                border.width: 1
                                border.color: page.fieldError("justification").length ? S.danger
                                            : justificationField.activeFocus ? S.accentSoft : S.fieldBorder
                            }
                            onTextChanged: if (activeFocus) page.changed()
                        }
                        Text { visible: page.fieldError("justification").length > 0; width: parent.width; text: page.fieldError("justification")
                               color: S.danger; wrapMode: Text.WordWrap; font.family: page.ui.fontFamily; font.pixelSize: 13 * page.ui.u }
                    }
                }
            }
        }
    }

    // ---- Resultado de herramienta: menú anclado al botón ··· del Dock.
    component MenuTitle: Text {
        property var ui
        width: parent ? parent.width : 0
        leftPadding: 6 * ui.u; bottomPadding: 8 * ui.u
        color: S.text; wrapMode: Text.WordWrap
        font.family: ui.fontFamily; font.pixelSize: 17 * ui.u; font.weight: Font.DemiBold
    }
    RGlassMenu {
        id: toolMenu
        objectName: "toolMenu"
        ui: page.ui
        cardWidth: 340 * page.ui.u
        MenuTitle { ui: page.ui; text: page.toolTitle }
        Rectangle { width: parent.width; height: 1; color: S.ink(0.10) }
        Text { width: parent.width; leftPadding: 6 * page.ui.u; rightPadding: 6 * page.ui.u; topPadding: 10 * page.ui.u; bottomPadding: 10 * page.ui.u
               text: page.toolBody; color: S.text; wrapMode: Text.WordWrap
               font.family: page.ui.fontFamily; font.pixelSize: 15 * page.ui.u }
        RButton {
            visible: page.toolActionLabel.length > 0
            width: parent.width
            ui: page.ui; primary: true; label: page.toolActionLabel
            onActivated: { var a = page.toolAction; toolMenu.close(); if (a) a() }
        }
    }
    RGlassMenu {
        id: reuseMenu
        objectName: "reuseMenu"
        ui: page.ui
        cardWidth: 340 * page.ui.u
        MenuTitle { ui: page.ui; text: "Reutilizar datos de un gasto anterior" }
        Repeater {
            model: page.previousExpenses
            delegate: RMenuItem {
                required property var modelData
                required property int index
                width: parent.width
                ui: page.ui
                glyph: 0xE1F5
                glyphColor: S.accent
                label: (S.text_(modelData, "concept") || "Gasto sin concepto") + " · " + page.ctl.formatMoney(modelData.amount, S.text_(modelData, "currencyCode", "currency_code") || "PEN")
                separator: index < page.previousExpenses.length - 1
                onActivated: page.reuse(modelData)
            }
        }
    }
    // Ver archivos adjuntos / elegir cuál reemplazar.
    RGlassMenu {
        id: filesMenu
        objectName: "filesMenu"
        property bool replacing: false
        ui: page.ui
        cardWidth: 340 * page.ui.u
        onDismissed: replacing = false
        MenuTitle { ui: page.ui; text: filesMenu.replacing ? "Elige el adjunto a reemplazar" : "Archivos adjuntos" }
        Repeater {
            model: filesMenu.replacing ? page.fileRows.filter(function(r) { return page.canReplace(r) }) : page.fileRows
            delegate: RMenuItem {
                required property var modelData
                required property int index
                width: parent.width
                ui: page.ui
                glyph: page.isImage(modelData) ? 0xE0F6 : 0xE0CC
                glyphColor: S.accent
                label: modelData.name
                enabledItem: filesMenu.replacing || page.canView(modelData)
                onActivated: { var r = modelData; var rep = filesMenu.replacing; filesMenu.close(); if (rep) page.replaceFile(r); else page.viewFile(r) }
            }
        }
    }
    // Menú ⋮ de una fila de archivo.
    RGlassMenu {
        id: fileMenu
        objectName: "fileMenu"
        ui: page.ui
        above: false
        cardWidth: 260 * page.ui.u
        RMenuItem { ui: page.ui; label: "Ver"; glyph: 0xE0F6; glyphColor: S.accent
                    enabledItem: !!page.fileMenuRow && page.canView(page.fileMenuRow)
                    onActivated: page.viewFile(page.fileMenuRow) }
        RMenuItem { ui: page.ui; label: "Reemplazar"; glyph: 0xE145; glyphColor: S.accent
                    enabledItem: !!page.fileMenuRow && page.canReplace(page.fileMenuRow)
                    onActivated: page.replaceFile(page.fileMenuRow) }
        RMenuItem { ui: page.ui; label: "Quitar"; glyph: 0xE18E; glyphColor: S.danger; separator: false
                    enabledItem: !!page.fileMenuRow && page.canRemove(page.fileMenuRow)
                    onActivated: page.removeFile(page.fileMenuRow) }
    }

    // ---- Gasto registrado: confirmación REAL del servidor (con confeti) o
    // guardado pendiente de sincronizar (sin celebración). Diseño del preview.
    Item {
        id: resultLayer
        objectName: "resultLayer"
        anchors.fill: parent
        visible: page.resultKind.length > 0
        z: 40
        Rectangle { anchors.fill: parent; color: S.ink(0.22); opacity: resultLayer.visible ? 1 : 0
                    Behavior on opacity { enabled: !page.reduced; NumberAnimation { duration: 200 } } }
        MouseArea { anchors.fill: parent }
        Rectangle {
            id: resultCard
            readonly property bool ok: page.resultKind === "confirmed"
            width: Math.min(parent.width - 56 * page.ui.u, 340 * page.ui.u)
            height: resultColumn.implicitHeight + 48 * page.ui.u
            anchors.centerIn: parent
            radius: 28 * page.ui.u
            color: S.glass(0.98)
            border.width: 1; border.color: S.edge(0.95)
            scale: resultLayer.visible ? 1 : 0.94
            Behavior on scale { enabled: !page.reduced; NumberAnimation { duration: 240; easing.type: Easing.OutCubic } }
            Rectangle {                                // cerrar (vuelve a mis gastos)
                width: 40 * page.ui.u; height: width; radius: width / 2
                anchors.right: parent.right; anchors.top: parent.top; anchors.margins: 12 * page.ui.u
                color: closeResultTap.pressed ? S.ink(0.08) : "transparent"
                Text { anchors.centerIn: parent; text: String.fromCharCode(0xE1B2); color: S.text
                       font.family: page.ui.iconFamily; font.pixelSize: 22 * page.ui.u }
                MouseArea { id: closeResultTap; anchors.fill: parent; onClicked: page.viewInExpenses() }
                Accessible.role: Accessible.Button
                Accessible.name: "Cerrar"
            }
            Column {
                id: resultColumn
                x: 24 * page.ui.u; y: 28 * page.ui.u
                width: parent.width - 48 * page.ui.u
                spacing: 12 * page.ui.u
                Item {
                    width: parent.width; height: 92 * page.ui.u
                    Rectangle {                         // halo
                        anchors.centerIn: parent
                        width: 92 * page.ui.u; height: width; radius: width / 2
                        color: resultCard.ok ? Qt.rgba(46 / 255, 184 / 255, 114 / 255, 0.14) : Qt.rgba(242 / 255, 178 / 255, 27 / 255, 0.14)
                    }
                    Rectangle {
                        anchors.centerIn: parent
                        width: 62 * page.ui.u; height: width; radius: width / 2
                        color: resultCard.ok ? "#2EB872" : S.warning
                        Text { anchors.centerIn: parent; text: String.fromCharCode(resultCard.ok ? 0xE06C : 0xE145)
                               font.family: page.ui.iconFamily; font.pixelSize: 32 * page.ui.u; color: "#FFFFFF" }
                    }
                }
                Text { width: parent.width; horizontalAlignment: Text.AlignHCenter
                       text: resultCard.ok ? "Gasto registrado" : "Gasto guardado"
                       color: S.text; font.family: page.ui.fontFamily; font.pixelSize: 22 * page.ui.u; font.weight: Font.DemiBold }
                Text { width: parent.width; horizontalAlignment: Text.AlignHCenter; wrapMode: Text.WordWrap
                       text: resultCard.ok ? "El gasto se ha guardado correctamente."
                                           : "Quedó guardado en el equipo. Se registrará en el servidor al sincronizar."
                       color: S.muted; font.family: page.ui.fontFamily; font.pixelSize: 15 * page.ui.u }
                Item { width: 1; height: 4 * page.ui.u }
                RButton { objectName: "viewExpensesButton"; width: parent.width; ui: page.ui; primary: true; label: "Ver en mis gastos"; onActivated: page.viewInExpenses() }
                RButton { objectName: "registerAnotherButton"; width: parent.width; ui: page.ui; label: "Registrar otro gasto"; onActivated: page.registerAnother() }
            }
        }
        RConfetti {
            id: confettiLayer
            objectName: "confetti"
            anchors.fill: parent
            ui: page.ui
            reducedMotion: page.reduced
        }
    }
}

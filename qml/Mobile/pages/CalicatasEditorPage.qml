import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15
import QtCore
import InGe 1.0
import ".." as App
import "../flowcore" as FlowCore
import "../components" as Components
import "../documents" as Documents
import QtQuick.Effects
import "../lib/IconCatalog.js" as IconCatalog
import "../lib/CalicataExcelImport.js" as ExcelImport
import InGe.CoreFlow 3.0 as Mobile


Page {
    id: root
    readonly property var docs: Docs
    property var flow: null
    property bool flowMotionEnabled: true
    property bool flowReduceMotion: false
    property int flowMotionLevel: 2



    // === ARM HYBRID PHONE/TABLET HELPERS ===
    // Alto sin teclado: mismo criterio que _layoutHeight de CalicataFormPage.
    // Mientras se escribe se conserva el alto previo (abrir el IME ya no cambia
    // __armPhone ni __armScale); rotar, split arriba/abajo o ventanas libres se
    // aceptan. El alto retenido solo se usa con el mismo ancho.
    property real __armLayoutWidth: 0
    property real __armLayoutHeight: 0
    function __armImeLikely() {
        // Acceso indexado, como InGeCoreFlow: existen en runtime aunque la
        // metadata estatica de qmllint no las enumere.
        if (Qt.inputMethod["visible"] === true)
            return true
        var focusItem = Window.activeFocusItem
        return !!focusItem && focusItem["cursorPosition"] !== undefined
    }
    function __armUpdateLayoutSize() {
        if (Math.abs(width - __armLayoutWidth) > 0.5
                || height > __armLayoutHeight || !__armImeLikely()) {
            __armLayoutHeight = height
            __armLayoutWidth = width
        }
    }
    onWidthChanged: Qt.callLater(__armUpdateLayoutSize)
    onHeightChanged: Qt.callLater(__armUpdateLayoutSize)
    readonly property real __armWidth:  width  > 0 ? width  : 420
    readonly property real __armHeight: height > 0 ? height : 820
    readonly property real __armMinSide: {
        var w = width > 0 ? width : 420
        var h = height > 0 ? height : 820
        if (Math.abs(width - __armLayoutWidth) <= 0.5 && __armLayoutHeight > h)
            h = __armLayoutHeight
        return Math.min(w, h)
    }
    readonly property bool __armPhone: __armMinSide < 600
    readonly property bool __armTablet: !__armPhone
    readonly property real __armScale: __armPhone
        ? Math.max(0.95, Math.min(1.16, __armMinSide / 390.0))
        : Math.max(1.05, Math.min(1.32, __armMinSide / 720.0))
    readonly property int __touchTarget: Math.round((__armPhone ? 56 : 60) * __armScale)
    readonly property int __touchPressDelay: 140
    readonly property real __flickVelocity: __armPhone ? 1600 : 2200
    function __dp(v) { return Math.round(v * __armScale) }
    function __sp(v) { return Math.max(12, Math.round(v * __armScale)) }
    function calAsset(name) { return "qrc:/ui/v2/calicatas/" + name }
    function navAsset(name) { return "qrc:/ui/v2/nav_ficha/" + name }
    function exportAsset(name) { return "qrc:/ui/v2/calicatas_export/" + name }
    function calBgColor() { return flow ? flow.theme.background : (darkMode ? "#050D18" : "#F3F5F8") }
    function calPanelColor() { return flow ? (liquidGlass ? flow.theme.glassSurface : flow.theme.surface) : (darkMode ? "#081827" : "#FFFFFF") }
    function calPanel2Color() { return flow ? flow.theme.surfaceSecondary : (darkMode ? "#102235" : "#E8EDF3") }
    function calTextColor() { return flow ? flow.theme.textPrimary : (darkMode ? "#FFFFFF" : "#1F2937") }
    function calMutedColor() { return flow ? flow.theme.textSecondary : (darkMode ? "#B9C7DA" : "#667085") }
    function calBorderColor() { return flow ? flow.theme.border : (darkMode ? "#2B4157" : "#D6DEE8") }
    function calAccentColor() { return flow ? flow.theme.accent : "#0654A2" }
    function showExportProgress(msg) {
        exportProgressText = msg || "Preparando exportación..."
        exportProgressPopup.open()
    }

    required property var auth

        // ✅ CLAVE: si lo abre un Loader, esto evita que sea 0x0
        width:  parent ? parent.width  : 420
        height: parent ? parent.height : 820

    // estado inicial (viene del Shell)
    property bool gpsEnabled: false
    property bool darkMode: false
    property int themeMode: 0
    readonly property bool liquidGlass: themeMode === 2

    property int untitledSeq: 0

    property int _pendingCloseTid: -1
    property bool _pendingCloseAfterSave: false
    property int _pendingSaveTid: -1
    property string _pendingSaveDocId: ""
    property bool _closeOperationActive: false
    property int _closeOperationSerial: 0
    property bool _suspendFormLoader: false
    property bool _formLoaderReady: false
    property var _retiredDocs: []
    property string _publishingDocId: ""
    property bool _exportPreparing: false
    readonly property bool exportBusy: _exportPreparing || _publishingDocId.length > 0
    property string _savingCloudDocId: ""
    property string _queuedSaveDocId: ""
    property string _pendingCloudXlsxPath: ""
    property string _archivingCloudDocId: ""
    property int _archivingCloudTid: -1
    property string _remoteLoadingDocId: ""
    property string _remoteLoadingProjectId: ""
    // Live: hydrate silencioso al reconectar (no se reproducen cambios perdidos).
    property string _liveRevalidatingDocId: ""

    // Live field changes (contrato Web canónico, docs/CALICATAS_LIVE_COLLAB_V1.md):
    // "calicata-field-change" de otra persona se aplica campo a campo en la
    // ficha activa; SUPERSEDED aplica el valor vigente del servidor. Al
    // reconectar se revalida con el hydrate existente solo si la ficha está limpia.
    Connections {
        target: typeof CalicataCloud !== "undefined" ? CalicataCloud : null
        ignoreUnknownSignals: true
        function onFieldChangeReceived(calicataId, change) {
            var doc = root._liveDocFor(calicataId)
            if (!doc || root._remoteLoadingDocId.length || doc.applyingCloudState) return
            var apply = root.formValue(formLoader.item, "applyRemoteFieldChange")
            if (apply) apply(change)
        }
        function onFieldChangeSettled(localDocumentId, result) {
            var doc = root.currentDoc
            if (!doc || root._docInstanceId(doc) !== localDocumentId) return
            var outcome = String(result.outcome || "")
            if (outcome === "SUPERSEDED") {
                var apply = root.formValue(formLoader.item, "applyRemoteFieldChange")
                if (apply) apply(result)
                root.workspaceStatusText = "Otro usuario cambió " + String(result.field || "un campo")
                                           + "; se muestra el valor vigente"
            } else if (outcome === "REFUSED") {
                root.workspaceStatusText = "Cambio en vivo rechazado: " + String(result.message || "")
            }
        }
        function onLiveResyncRequested(calicataId) { root._liveRevalidate(calicataId, 0) }
    }

    function _liveDocFor(calicataId) {
        var doc = root.currentDoc
        if (!doc || doc.closed === true) return null
        return String(doc.header.remoteCalicataId || "").toLowerCase() === String(calicataId || "").toLowerCase()
                ? doc : null
    }

    function _liveRevalidate(calicataId, revision) {
        var doc = root._liveDocFor(calicataId)
        if (!doc) return
        var local = Number(doc.header.remoteRowVersion || 0)
        if (revision > 0 && revision <= local) return
        var form = formLoader.item
        var pending = root.formValue(form, "_pendingCommitFields")
        if (doc.dirty || root.formValue(form, "dirty") || (pending && pending.length)
                || String(doc.syncState || "") !== "SYNCED"
                || root._remoteLoadingDocId.length || root._autoSyncDocId.length
                || root._savingCloudDocId.length || root._driveJsonBusy) {
            console.info("INGE_LIVE_REVALIDATE_SKIPPED calicataId=" + calicataId + " localRevision=" + local
                         + " remoteRevision=" + revision)
            return
        }
        var projectId = String(doc.header.projectId || "")
        if (!projectId.length) return
        root._liveRevalidatingDocId = root._docInstanceId(doc)
        root._remoteLoadingProjectId = projectId
        root._remoteLoadingDocId = root._liveRevalidatingDocId
        console.info("INGE_LIVE_REVALIDATE calicataId=" + calicataId + " localRevision=" + local
                     + " remoteRevision=" + revision)
        CalicataCloud.loadRemoteDocument(doc, projectId, String(doc.header.remoteCalicataId))
    }
    // ===== Operación foreground única (CalicataOperationOverlay) =====
    // Arranca con APP_INIT: la subapp nunca muestra un editor a medio iniciar.
    property var foregroundOperation: ({ id: "APP_INIT-0", kind: "APP_INIT", phase: "BEGIN",
                                         title: "Preparando Calicatas", detail: "Cargando tus proyectos y borradores",
                                         blocking: true, cover: true, immediate: true, startedAt: Date.now() })
    property int _operationSeq: 0
    property bool _exportFlowActive: false
    property string _googleExportPath: ""
    property string _exportOperationId: ""
    readonly property bool foregroundBusy: !!foregroundOperation && !foregroundOperation.result
    // Dock oculto solo mientras la tarjeta de operación es visible (anti-flash incluido).
    readonly property bool dockSuppressed: operationOverlay.shown && !!operationOverlay.displayed
                                           && operationOverlay.displayed.blocking !== false
    property bool leaving: false

    // Salida segura: suelta todo input antes de que Main destruya la página.
    function prepareForLeave() {
        var form = formLoader.item
        var state = form && typeof form.releaseInputForLeave === "function" ? form.releaseInputForLeave() : ({})
        root.leaving = true
        root.enabled = false                 // desagarra mouse/touch de todo el subárbol
        hydrateTimeout.stop()
        exportKickoff.task = null
        exportKickoff.stop()
        root.foregroundOperation = null      // sin UI de operación sobre un host que se va
        return state
    }

    // Pestaña inicial vacía: aún no es una Calicata. No se autoguarda ni sincroniza.
    function _isPlaceholderDoc(doc) {
        if (!doc) return true
        var h = doc.header || {}
        if (String(h.projectId || "").length || String(h.remoteCalicataId || "").length
                || String(h.code || h.codigo || "").trim().length) return false
        var keys = ["supervisor", "maquina", "ubicacion", "utm_x", "utm_y", "description", "progresiva", "fecha_inicio"]
        for (var k = 0; k < keys.length; ++k) if (String(h[keys[k]] || "").trim().length) return false
        var cortes = doc.cortes || []
        for (var i = 0; i < cortes.length; ++i) {
            var c = cortes[i] || {}
            if (String(c.descripcion || "").trim().length || String(c.a || "").trim().length
                    || String(c.sucs || "").length || String(c.tipo_muestra || "").length) return false
        }
        var images = doc.images || {}
        for (var p = 1; p <= 3; ++p) if (String(images["foto" + p + "_path"] || "").length) return false
        return !String(doc.observaciones || "").trim().length
    }
    // P0: apertura cloud pedida antes de terminar de inicializar el workspace.
    property var _pendingCloudOpen: null
    property var _pendingExcelImport: null
    // P0: sincronización automática (autosave) en curso para este documento.
    property string _autoSyncDocId: ""
    property bool _autoSyncCreating: false
    property double _lastAutoSyncMs: 0
    property string _statusChangingDocId: ""
    property string _restoreAfterLoadDocId: ""
    property string _restoringDocId: ""
    property string _pendingExportLogDocId: ""
    property string _pendingExportFileName: ""
    property bool _cloudListArchived: false
    Connections {
        target: CalicataCloud
        // Retry audit events left pending by a previous offline session.
        Component.onCompleted: Qt.callLater(function() { CalicataCloud.flushActivity() })
        function onStatusChangeSucceeded(localDocumentId, status, confirmed) {
            if (localDocumentId === root._statusChangingDocId) root._statusChangingDocId = ""
            var idx = root._indexForDocId(localDocumentId)
            if (idx >= 0) root._syncTabFromDoc(idx)
            root.workspaceStatusText = "Estado: " + root.statusLabel(status)
                    + (confirmed ? "" : " · se sincronizará al guardar online")
        }
        function onStatusChangeFailed(localDocumentId, message) {
            if (localDocumentId === root._statusChangingDocId) root._statusChangingDocId = ""
            root.showMsg("No se pudo cambiar el estado", message)
        }
        function onRestoreSucceeded(localDocumentId, status, confirmed) {
            if (localDocumentId === root._restoringDocId) root._restoringDocId = ""
            var idx = root._indexForDocId(localDocumentId)
            if (idx >= 0) root._syncTabFromDoc(idx)
            root.workspaceStatusText = "Calicata restaurada · " + root.statusLabel(status)
        }
        function onRestoreFailed(localDocumentId, message) {
            if (localDocumentId === root._restoringDocId) root._restoringDocId = ""
            root.showMsg("No se pudo restaurar", message)
        }
        function onProjectCalicatasLoaded(projectId, rows) {
            if (String(projectId || "") !== root._remoteLoadingProjectId) return
            root.workspaceStatusText = rows && rows.length
                    ? (rows.length + " calicata(s) online disponibles")
                    : "No hay calicatas online activas en este proyecto"
        }
        function onProjectCalicatasLoadFailed(projectId, message) {
            if (String(projectId || "") !== root._remoteLoadingProjectId) return
            root.showMsg("No se pudo listar Calicatas Web", message)
        }
        function onRemoteLoadSucceeded(localDocumentId, projectId, calicataId) {
            if (localDocumentId !== root._remoteLoadingDocId) return
            var liveRevalidation = localDocumentId === root._liveRevalidatingDocId
            root._liveRevalidatingDocId = ""
            var idx = root._indexForDocId(localDocumentId)
            var doc = root._docAt(idx)
            if (!doc) { root._remoteLoadingDocId = ""; return }
            if (idx !== root.currentIndex) root.selectTab(idx)
            if (formLoader.item && formLoader.item.importState) {
                formLoader.item.importState({
                    header: doc.header, uiState: doc.uiState, cortes: doc.cortes,
                    observaciones: doc.observaciones, timestamp: doc.timestamp, images: doc.images
                })
            }
            root._remoteLoadingDocId = ""
            p0AutoSaveDebounce.stop()
            driveJsonAutosave.stop()
            root._syncTabFromDoc(root.currentIndex)
            cloudCalicatasPopup.close()
            root.workspaceStatusText = liveRevalidation ? "Actualizada con cambios de otra sesión"
                                                        : "Calicata online cargada y vinculada al proyecto"
            if (formLoader.item && formLoader.item._reconcileMediaCloud)
                formLoader.item._reconcileMediaCloud()   // fotos, logos y actividad desde la nube
            hydrateTimeout.stop()
            if (root.foregroundOperation && root.foregroundOperation.kind === "CALICATA_OPEN")
                root.endOperation(root.foregroundOperation.id, "OK")
            console.info("INGE_CALICATA_HYDRATE_OK projectId=" + projectId + " calicataId=" + calicataId
                         + " remoteCalicataId=" + String(doc.header.remoteCalicataId || "")
                         + " strata=" + (doc.cortes ? doc.cortes.length : 0))
            if (String(doc.status || "") === "ARCHIVADO") {
                // An archived sheet is never silently reactivated: restore is
                // explicit (requested from "Archivadas") or offered here.
                if (root._restoreAfterLoadDocId === localDocumentId) {
                    root._restoreAfterLoadDocId = ""
                    root._restoringDocId = localDocumentId
                    if (!CalicataCloud.restoreDocument(doc)) root._restoringDocId = ""
                } else {
                    root.showMsg("Calicata archivada",
                                 "Esta ficha está archivada y sus datos se conservan. "
                                 + "Restáurala (mantén pulsado Calicatas › Estado › Restaurar) antes de editarla o sincronizarla.")
                }
            }
        }
        function onRemoteLoadFailed(localDocumentId, message) {
            if (localDocumentId !== root._remoteLoadingDocId) return
            if (localDocumentId === root._liveRevalidatingDocId) {
                // Revalidación de fondo: sin diálogo; el documento local sigue intacto.
                root._liveRevalidatingDocId = ""
                root._remoteLoadingDocId = ""
                console.warn("INGE_LIVE_REVALIDATE_FAILED " + message)
                return
            }
            root._remoteLoadingDocId = ""
            if (root._restoreAfterLoadDocId === localDocumentId) root._restoreAfterLoadDocId = ""
            hydrateTimeout.stop()
            var failedOp = root.foregroundOperation
            if (failedOp && failedOp.kind === "CALICATA_OPEN") {
                console.warn("INGE_CALICATA_HYDRATE_FAILED " + message)
                root.endOperation(failedOp.id, "ERROR", { title: "No se pudo cargar la ficha",
                    detail: "Revisa la conexión e inténtalo de nuevo. Tus datos locales se conservan.",
                    actions: failedOp.retry ? [{ id: "retry", label: "Reintentar" }, { id: "back", label: "Volver" }]
                                            : [{ id: "close", label: "Cerrar" }] })
            } else {
                root.showMsg("No se pudo abrir la calicata online", message)
            }
        }
        function onSyncSucceeded(localDocumentId, result) {
            if (localDocumentId === root._autoSyncDocId) {
                var autoIdx = root._indexForDocId(localDocumentId)
                var autoDoc = root._docAt(autoIdx)
                if (root._autoSyncCreating && autoDoc)
                    console.info("INGE_CALICATA_DRAFT_CREATED projectId=" + String(autoDoc.header.projectId || "")
                                 + " calicataId=" + String(autoDoc.header.remoteCalicataId || ""))
                root._autoSyncDocId = ""
                root._autoSyncCreating = false
                if (autoDoc) {
                    autoDoc.saveDraft()   // persist the bound cloud identity at once
                    if (autoIdx === root.currentIndex && formLoader.item && formLoader.item.adoptStratumIdentities)
                        formLoader.item.adoptStratumIdentities(autoDoc.cortes)
                    root._syncTabFromDoc(autoIdx)
                }
                root._resumeQueuedSave(localDocumentId)
                return
            }
            var idx = root._indexForDocId(localDocumentId)
            var doc = root._docAt(idx)
            if (!doc) {
                if (localDocumentId === root._savingCloudDocId) root._savingCloudDocId = ""
                if (localDocumentId === root._publishingDocId) root._publishingDocId = ""
                root._pendingCloudXlsxPath = ""
                return
            }
            root._syncTabFromDoc(idx)
            if (idx === root.currentIndex && formLoader.item && formLoader.item.adoptStratumIdentities)
                formLoader.item.adoptStratumIdentities(doc.cortes)
            var docsBase = (root.docs && root.docs.basePath !== undefined)
                    ? String(root.docs.basePath || "") : ""
            var portable = doc.portableState(docsBase)
            if (!portable || !portable.instance_id) {
                if (localDocumentId === root._savingCloudDocId) root._savingCloudDocId = ""
                if (localDocumentId === root._publishingDocId) root._publishingDocId = ""
                root._pendingCloudXlsxPath = ""
                root.showMsg("Sincronización incompleta", doc.errorString)
                return
            }

            if (localDocumentId === root._savingCloudDocId) {
                root.workspaceStatusText = "Datos sincronizados; publicando ficha portable…"
                // Un JSON de autoguardado en curso no cierra este Guardar: el JSON
                // de la versión sincronizada se encola y corre al terminar aquel.
                if (root._driveJsonBusy) {
                    root._driveJsonQueuedDocId = localDocumentId
                    return
                }
                root._startManualDriveJson(localDocumentId, doc)
                return
            }

            if (localDocumentId === root._publishingDocId) {
                root._logPendingExport(doc, true)
                var xlsx = root._pendingCloudXlsxPath
                root._pendingCloudXlsxPath = ""
                root.exportProgressText = "Datos sincronizados; subiendo Excel…"
                if (!ExcelExporter.publishCalicata(portable, xlsx)) {
                    root._publishingDocId = ""
                    exportProgressPopup.close()
                    root.exportResultText = ExcelExporter.lastError
                    exportErrorPopup.open()
                }
            }
        }
        function onSyncFailed(localDocumentId, message) {
            if (localDocumentId === root._autoSyncDocId) {
                // Offline or rejected: the draft stays local/PENDING and is retried.
                root._autoSyncDocId = ""
                root._autoSyncCreating = false
                root.workspaceStatusText = "Borrador guardado en el dispositivo; se sincronizará al recuperar conexión"
                root._resumeQueuedSave(localDocumentId)
                return
            }
            if (localDocumentId === root._savingCloudDocId) {
                root._savingCloudDocId = ""
                root._clearPendingSave()
                root.showMsg("No se pudo sincronizar la calicata", message + "\nEl borrador local se conserva.")
            }
            if (localDocumentId === root._publishingDocId) {
                // The Excel exists locally; a synced calicata still records it.
                var failedDoc = root._docAt(root._indexForDocId(localDocumentId))
                root._logPendingExport(failedDoc, false)
                var pendingXlsx = root._pendingCloudXlsxPath
                root._publishingDocId = ""
                root._pendingCloudXlsxPath = ""
                // Sin red / sync rechazado: el Excel se encola igual en la cola
                // persistente de InGeDrive; se sube al recuperar conexión.
                if (failedDoc && pendingXlsx.length) {
                    var queuedOffline = ExcelExporter.publishCalicata(
                                failedDoc.portableState(String(root.docs && root.docs.basePath || "")), pendingXlsx)
                    console.info(queuedOffline ? "INGE_CALICATA_EXPORT_QUEUED offline=1"
                                               : "INGE_CALICATA_EXPORT_PUBLISH_PENDING " + ExcelExporter.lastError)
                }
            }
        }
        function onArchiveSucceeded(localDocumentId) {
            if (localDocumentId !== root._archivingCloudDocId) return
            var tid = root._archivingCloudTid
            root._archivingCloudDocId = ""
            root._archivingCloudTid = -1
            var idx = root._indexForDocId(localDocumentId)
            if (idx >= 0) root._syncTabFromDoc(idx)
            root._closeTabsByTids([tid], true)
            root.workspaceStatusText = "Calicata archivada; datos conservados"
        }
        function onArchiveFailed(localDocumentId, message) {
            if (localDocumentId !== root._archivingCloudDocId) return
            root._archivingCloudDocId = ""
            root._archivingCloudTid = -1
            root.showMsg("No se pudo archivar", message)
        }
    }

    Connections {
        target: ExcelExporter
        function onExportResultChanged() { root._refreshGoogleExcelExport() }
        function onCalicataSavedOnline(documentId) {
            if (documentId !== root._savingCloudDocId) return
            root._savingCloudDocId = ""
            root._clearPendingSave()
            root._notifySaved("Ficha guardada en el proyecto online")
            root._finishPendingCloseIfAny()
        }
        function onCalicataPublished(documentId) {
            if (documentId !== root._publishingDocId) return
            root._publishingDocId = ""
            var shown = root.foregroundOperation
            if (shown && shown.kind === "EXPORT_XLSX" && shown.result === "SUCCESS")
                root.foregroundOperation = Object.assign({}, shown, {
                    detail: String(shown.detail || "").replace("Pendiente de sincronización", "Sincronizado") })
        }
        function onCalicataPublishFailed(documentId, message) {
            if (documentId === root._savingCloudDocId) {
                root._savingCloudDocId = ""
                root._clearPendingSave()
                root.showMsg("Subida pendiente", message + "\nSe conserva el borrador y la cola reintentará la subida.")
            }
            if (documentId !== root._publishingDocId) return
            root._publishingDocId = ""
            // El Excel ya existe y está abierto; la cola reintenta la subida.
            console.warn("INGE_CALICATA_EXPORT_PUBLISH_PENDING " + message)
        }
    }

    signal requestBack()
    signal requestPickCalicataFile()
    signal requestGpsAutoShare(bool on)
    signal requestOpenEarth(real latitude, real longitude, real altitude,
                            string label)
    signal requestOpenMap()

    readonly property bool hasOpenDocument: !!root.currentTab
    readonly property bool canExportPdf: !!formLoader.item
        && typeof formLoader.item.exportPdfFlow === "function"

    // Semantic dock context: the current stage states which actions it needs;
    // the host dock decides how they are represented.
    readonly property int contextStage: formLoader.item ? formLoader.item.stageIndex : 0
    readonly property bool contextCorrectingReview: !!formLoader.item
        && formLoader.item.reviewCorrectionActive === true

    // Lifecycle / cloud state of the open sheet, re-evaluated on dataChanged.
    readonly property string contextStatus: root.currentDoc && root.currentDoc.status !== undefined
        ? String(root.currentDoc.status || "BORRADOR") : ""
    readonly property string contextSyncState: root.currentDoc && root.currentDoc.syncState !== undefined
        ? String(root.currentDoc.syncState || "LOCAL") : ""
    readonly property var contextTransitions: {
        var dependency = root.contextStatus
        return root.currentDoc && root.currentDoc.allowedStatusTransitions
            ? root.currentDoc.allowedStatusTransitions() : []
    }
    readonly property var statusLabels: ({
        BORRADOR: "Borrador", EN_REVISION: "En revisión", OBSERVADO: "Observado",
        REVISADO: "Revisado", APROBADO: "Aprobado", EXPORTADO: "Exportado", ARCHIVADO: "Archivado"
    })
    readonly property var syncLabels: ({
        LOCAL: "Solo en este equipo", PENDING: "Pendiente de sincronizar",
        SYNCING: "Sincronizando…", SYNCED: "Sincronizada", CONFLICT: "Conflicto con el servidor"
    })
    function statusLabel(status) { return statusLabels[String(status || "")] || String(status || "") }
    function syncLabel(state) { return syncLabels[String(state || "")] || String(state || "") }

    // Sheet management tree hanging from the "tabs" action (long press).
    // Ids are stable across stages; only enabled/visible/labels change.
    function calicataBranch(hasForm) {
        var hasDoc = hasForm && !!root.currentDoc
        var archived = root.contextStatus === "ARCHIVADO"
        var cloudBusy = root._savingCloudDocId.length > 0 || root._publishingDocId.length > 0
                        || root._statusChangingDocId.length > 0 || root._archivingCloudDocId.length > 0
        var lifecycle = ["BORRADOR", "EN_REVISION", "OBSERVADO", "REVISADO", "APROBADO", "EXPORTADO"]
        var statusChildren = []
        if (archived) {
            statusChildren.push({id: "calicata.restore", label: "Restaurar", icon: "action.check",
                                 command: "calicatas.restore", enabled: !cloudBusy})
        } else {
            for (var i = 0; i < lifecycle.length; ++i) {
                var s = lifecycle[i]
                statusChildren.push({id: "calicata.status." + s, label: root.statusLabel(s),
                                     command: "calicatas.status." + s,
                                     selected: root.contextStatus === s,
                                     enabled: !cloudBusy && root.contextTransitions.indexOf(s) >= 0})
            }
        }
        return [
            {id: "calicata.new", label: "Nueva calicata", icon: "action.add", command: "calicatas.new"},
            {id: "calicata.open", label: "Abrir del proyecto", icon: "documents.folder",
             command: "calicatas.openProject", enabled: hasDoc},
            {id: "calicata.status", label: "Estado · " + root.statusLabel(root.contextStatus),
             icon: "action.check", visible: hasDoc, children: statusChildren},
            // Guardar: fila + Smart Document + JSON en InGeDrive; estado real de ambos.
            {id: "calicata.sync", icon: "action.save", command: "calicatas.sync",
             label: "Guardar · " + root.saveStateLabel,
             visible: hasDoc, enabled: !archived && !cloudBusy},
            {id: "calicata.saveAs", icon: "documents.folder", command: "calicatas.saveDriveAs",
             label: "Guardar en…", visible: hasDoc, enabled: !archived && !cloudBusy && !root._driveJsonBusy},
            {id: "calicata.more", label: "Más", icon: "action.more", visible: hasDoc, children: [
                {id: "calicata.info", label: "Información", icon: "documents.file", command: "calicatas.info"},
                {id: "calicata.duplicate", label: "Duplicar ficha", icon: "action.copy", command: "calicatas.duplicate"},
                {id: "calicata.drive", label: "Abrir desde InGeDrive", icon: "documents.open", command: "calicatas.openDrive"},
                {id: "calicata.archivedList", label: "Archivadas del proyecto", icon: "calgen.history", command: "calicatas.archivedList"},
                {id: "calicata.close", label: "Cerrar ficha", icon: "calgen.close", command: "calicatas.closeTab"},
                {id: "calicata.archive", label: "Archivar", icon: "archive.item", command: "calicatas.archive",
                 destructive: true, visible: !archived, enabled: !cloudBusy}
            ]}
        ]
    }

    // Lectura dinámica de la ficha cargada (Loader.item no tiene tipo estático).
    function formValue(form, name) {
        return form ? form[name] : undefined
    }

    function buildContextActions(stage, correctingReview, hasForm) {
        var actions = [{id: "tabs", label: "Calicatas abiertas", icon: "documents.file",
                        command: "calicatas.tabs", priority: 10,
                        children: root.calicataBranch(hasForm)}]
        if (!hasForm)
            return actions
        actions.push({id: "information", label: "Información · " + root.statusLabel(root.contextStatus),
                      icon: "documents.file", command: "calicatas.info", priority: 15})
        if (stage === 0)
            actions.push({id: "identity", label: "Identidad del informe", icon: "profile.user",
                          command: "calicatas.identity", priority: 20})
        else if (stage === 1)
            actions.push({id: "location", label: "Ubicación", icon: "map.location",
                          command: "calicatas.map", priority: 20, children: [
                              {id: "location.map", label: "Elegir en el mapa", icon: "nav.map",
                               command: "calicatas.map"},
                              {id: "location.gps", label: "Capturar GPS", icon: "map.location",
                               command: "calicatas.gps"},
                              {id: "location.earth", label: "Ver en InGe Earth", icon: "nav.map",
                               command: "calicatas.earth"}
                          ]})
        else if (stage === 2)
            actions.push({id: "addStratum", label: "Agregar estrato", icon: "action.addStratum",
                          command: "calicatas.addStratum", priority: 20, children: [
                              {id: "stratum.add", label: "Agregar estrato", icon: "action.add",
                               command: "calicatas.addStratum"},
                              {id: "stratum.duplicate", label: "Duplicar estrato", icon: "action.copy",
                               command: "calicatas.profile.duplicate",
                               enabled: root.formValue(formLoader.item, "selectedStratum") >= 0},
                              {id: "stratum.insert", label: "Insertar / dividir estrato", icon: "action.add",
                               command: "calicatas.profile.insert",
                               enabled: root.formValue(formLoader.item, "selectedStratum") >= 0},
                              {id: "stratum.reorder", label: "Reordenar estratos", icon: "action.menu",
                               command: "calicatas.profile.reorder",
                               enabled: root.formValue(formLoader.item, "visibleStrataCount") > 1},
                              {id: "profile.templates", label: "Plantillas globales", icon: "documents.file",
                               command: "calicatas.profile.templates"},
                              {id: "profile.graph", label: "Ver perfil ampliado", icon: "module.stratigraphy",
                               command: "calicatas.profile.graph",
                               enabled: root.formValue(formLoader.item, "visibleStrataCount") > 0}
                          ]})
        else if (stage === 3)
            actions.push(root.labContextAction())
        else if (stage === 4)
            actions.push(root.photoContextAction())
        else if (stage === 5)
            actions.push({id: "sections", label: "Revisar secciones", icon: "action.edit",
                          command: "calicatas.sections", priority: 20})
        if (correctingReview) {
            actions.push({id: "returnReview", label: "Listo", icon: "system.forward",
                          command: "calicatas.returnReview", priority: 40})
            return actions
        }
        if (stage > 0)
            actions.push({id: "previous", label: "Anterior", icon: "system.back",
                          command: "calicatas.previous", priority: 30})
        if (stage === 5)
            actions.push({id: "export", label: "Exportar", icon: "action.export",
                          command: "", priority: 40,
                          enabled: root.hasOpenDocument && !root.exportBusy, children: [
                              {id: "export.google", label: "Excel → Google Drive",
                               icon: "action.export", command: "calicatas.exportGoogle", enabled: !root.exportBusy},
                              {id: "export.inge", label: "Excel → InGeDrive",
                               icon: "documents.folder", command: "calicatas.exportInGe", enabled: !root.exportBusy},
                              {id: "export.pdf", label: "Exportar PDF", icon: "documents.file",
                               command: "calicatas.exportPdf", visible: root.canExportPdf},
                              {id: "export.drive", label: "Ver en InGeDrive", icon: "documents.folder",
                               command: "calicatas.openDrive"}
                          ]})
        else
            actions.push({id: "next", label: "Siguiente", icon: "system.forward",
                          command: "calicatas.next", priority: 40})
        return actions
    }

    // Laboratorio: acción propia del Dock. Tap = acción primaria; mantener pulsado
    // abre el submenú Liquid Glass (mismo mecanismo que Perfil: children).
    function labContextAction() {
        var form = formLoader.item
        var strata = root.formValue(form, "visibleStrataCount") || 0
        if (root.formValue(form, "labDetailOpen") === true) {
            var tab = String(root.formValue(form, "labTab") || "lab")
            return {id: "lab", label: "Laboratorio", icon: "lab.flask", command: "calicatas.lab.tab:lab", priority: 20,
                    children: [
                        {id: "lab.tab.lab", label: "Ensayos y resultados", icon: "lab.flask",
                         command: "calicatas.lab.tab:lab", selected: tab === "lab"},
                        {id: "lab.editSample", label: "Editar muestra (Perfil)", icon: "calgen.attach",
                         command: "calicatas.lab.editSample"},
                        {id: "lab.tab.context", label: "Contexto del estrato", icon: "module.stratigraphy",
                         command: "calicatas.lab.tab:context", selected: tab === "context"},
                        {id: "lab.tab.history", label: "Historial", icon: "status.sync",
                         command: "calicatas.lab.tab:history", selected: tab === "history"},
                        {id: "lab.summary", label: "Resultados y seguimiento", icon: "documents.file",
                         command: "calicatas.lab.summary"},
                        {id: "lab.close", label: "Volver a la lista", icon: "system.back",
                         command: "calicatas.lab.close"}
                    ]}
        }
        if (strata === 0)
            return {id: "lab", label: "Laboratorio", icon: "lab.flask", command: "calicatas.lab.profile", priority: 20,
                    children: [{id: "lab.profile", label: "Ir a Perfil", icon: "module.stratigraphy",
                                command: "calicatas.lab.profile"}]}
        var entries = root.formValue(form, "labStrataEntries") || []
        var pending = root.formValue(form, "labPendingCount") || 0
        var dataCount = root.formValue(form, "labDataCount") || 0
        var filterKey = String(root.formValue(form, "labFilterKey") || "")
        var filters = [{id: "lab.filter.all", label: "Todos", icon: "action.menu",
                        command: "calicatas.lab.filter:", selected: filterKey === ""}]
        for (var i = 0; i < entries.length; ++i)
            filters.push({id: "lab.filter." + i, label: entries[i].label, icon: "module.stratigraphy",
                          command: "calicatas.lab.filter:" + entries[i].key, selected: filterKey === entries[i].key})
        var children = [
            {id: "lab.new", label: "Nueva muestra", icon: "action.add", command: "calicatas.lab.new"},
            {id: "lab.filter", label: "Filtrar por estrato", icon: "action.menu", command: "", children: filters}
        ]
        if (pending > 0)
            children.push({id: "lab.pending", label: "Ver pendientes (" + pending + ")", icon: "status.sync",
                           command: "calicatas.lab.pending", selected: filterKey === "pending"})
        var view = String(root.formValue(form, "labView") || "strata")
        children.push(view === "results"
            ? {id: "lab.strata", label: "Estratos y muestras", icon: "module.stratigraphy", command: "calicatas.lab.strata"}
            : {id: "lab.summary", label: "Resultados y seguimiento", icon: "documents.file", command: "calicatas.lab.summary"})
        if (dataCount > 0)
            children.push({id: "lab.history", label: "Historial", icon: "status.sync", command: "calicatas.lab.history"})
        return {id: "lab", label: "Laboratorio", icon: "lab.flask", command: "calicatas.lab.new", priority: 20,
                children: children}
    }

    // Fotos: tap = tomar foto en la categoría activa; mantener pulsado = submenú
    // Liquid Glass con categoría y TODAS las acciones según el estado real del slot
    // (misma fuente photoActions() que tarjetas y hoja de acciones).
    function photoContextAction() {
        var form = formLoader.item
        var active = Number(root.formValue(form, "activePhotoCategory") || 1)
        var titles = root.formValue(form, "photoSlotTitles") || []
        var actionsFor = root.formValue(form, "photoActions")
        var categories = []
        for (var i = 0; i < titles.length; ++i)
            categories.push({id: "photo.cat." + (i + 1), label: titles[i], icon: "documents.image",
                             command: "calicatas.photo.cat:" + (i + 1), selected: active === i + 1})
        var children = [{id: "photo.category", label: "Categoría · " + (titles[active - 1] || ""), icon: "documents.image",
                         command: "", children: categories}]
        var list = actionsFor ? actionsFor(active) : []
        for (var a = 0; a < list.length; ++a)
            children.push({id: "photo.act." + list[a].id, label: list[a].label, icon: list[a].icon,
                           command: "calicatas.photo.act:" + list[a].id, enabled: list[a].enabled,
                           destructive: list[a].destructive})
        return {id: "photos", label: "Fotografías", icon: "action.camera", command: "calicatas.photoCapture",
                priority: 20, children: children}
    }

    function runContextCommand(commandId) {
        if (commandId === "calicatas.tabs") {
            openTabsPopup()
            return
        }
        if (commandId === "calicatas.new") {
            root.addNewTab()
            return
        }
        if (String(commandId).indexOf("calicatas.status.") === 0) {
            root.changeCurrentStatus(String(commandId).substring("calicatas.status.".length))
            return
        }
        var sheetCommands = {
            "calicatas.openProject": function() { root.openCloudCalicataBrowser() },
            "calicatas.archivedList": function() { root.openCloudCalicataBrowser(true) },
            "calicatas.restore": function() { root.restoreCurrentCalicata() },
            "calicatas.sync": function() { root.doSave(false) },
            "calicatas.saveDriveAs": function() { root.openDriveFolderPicker() },
            "calicatas.info": function() { root.showCalicataInfo() },
            "calicatas.duplicate": function() { root.duplicateCurrentTabM09() },
            "calicatas.openDrive": function() { root.openDialogAbrirCalicata() },
            "calicatas.closeTab": function() { root.tryCloseTab(root.currentIndex) },
            "calicatas.archive": function() { root.archiveCurrentCalicata() },
            "calicatas.exportPdf": function() { root.exportPdfIfOpen() }
        }
        if (sheetCommands[commandId]) {
            sheetCommands[commandId]()
            return
        }
        var form = formLoader.item
        if (!form)
            return
        if (commandId === "calicatas.map")
            root.openCoordinatePicker()
        else if (commandId === "calicatas.gps")
            form._tryUpdateCoordsFromGps()
        else if (commandId === "calicatas.earth")
            form._openCurrentCoordinateInEarth()
        else if (commandId === "calicatas.stratumLab") {
            if (form.selectedStratum >= 0)
                form.openLabForStratum(form.selectedStratum)
        }
        // Fotos: tap del Dock = misma fuente única de acciones que tarjeta, hoja y menú.
        else if (commandId === "calicatas.photoCapture")
            root.formValue(form, "runPhotoCommand")("act:capture")
        else if (commandId === "calicatas.photoPick")
            root.formValue(form, "runPhotoCommand")("act:pick")
        else if (commandId === "calicatas.identity")
            form.scrollToSection(6)
        else if (commandId === "calicatas.addStratum")
            form.addStratumFromProfile()
        else if (commandId.indexOf("calicatas.photo.") === 0)
            root.formValue(form, "runPhotoCommand")(commandId.substring("calicatas.photo.".length))
        else if (commandId.indexOf("calicatas.lab.") === 0)
            root.formValue(form, "runLabCommand")(commandId.substring("calicatas.lab.".length))
        else if (commandId.indexOf("calicatas.profile.") === 0)
            root.formValue(form, "runProfileCommand")(commandId.substring("calicatas.profile.".length))
        else if (commandId === "calicatas.previous")
            form.goPreviousStage()
        else if (commandId === "calicatas.next") {
            _backAtWorkspace = false
            form.goNextStage()
        }
        else if (commandId === "calicatas.returnReview")
            form.finishReviewCorrection()
        else if (commandId === "calicatas.sections")
            openSectionsPopup()
        else if (commandId === "calicatas.export")
            exportExcelIfOpen()
        else if (commandId === "calicatas.exportGoogle")
            root.exportCurrentExcel("GOOGLE_DRIVE")
        else if (commandId === "calicatas.exportInGe")
            root.exportCurrentExcel("SUPABASE")
    }

    FlowCore.ContextPublisher {
        ownerId: "calicatas"
        // Do not publish the tabs-only loading state before the form exists.
        // An initialized empty workspace still has a legitimate tabs action.
        ready: !!formLoader.item || (root._formLoaderReady && tabsModel.count === 0)
        contextId: "calicatas/stage-" + root.contextStage
                   + (root.contextStage === 3 && root.formValue(formLoader.item, "labDetailOpen") === true ? "/lab-detail" : "")
                   + (root.contextCorrectingReview ? "/review-correction" : "")
        actions: root.buildContextActions(root.contextStage, root.contextCorrectingReview,
                                          !!formLoader.item)
        onCommand: function(commandId) { root.runContextCommand(commandId) }
    }

    property bool _backAtWorkspace: false
    function handleBack() {
        if (root.leaving) return true
        if (infoPeek.visible) { infoPeek.close(); return true }
        if (distantPointConfirm.opened) { distantPointConfirm.close(); return true }
        if (coordinatePicker.opened) { if (coordinateMap.item && coordinateMap.item.handleBack()) return true; coordinatePicker.close(); return true }
        if (inGeDriveCalicataPopup.opened) {
            if (driveCalicataBrowser.handleBack()) return true
            inGeDriveCalicataPopup.close()
            return true
        }
        if (cloudCalicatasPopup.opened) { cloudCalicatasPopup.close(); return true }
        if (driveFolderPopup.opened) { driveFolderPopup.close(); return true }
        if (tabsPopup.opened) {
            var exitWorkspace = _backAtWorkspace
            _backAtWorkspace = false
            tabsPopup.close()
            if (exitWorkspace) requestBack()
            return true
        }
        if (overflowPopup.opened) { overflowPopup.close(); return true }
        if (sectionsPopup.opened) { sectionsPopup.close(); return true }
        if (exportPopup.opened) { exportPopup.close(); return true }
        if (formLoader.item && formLoader.item.handleBack()) {
            _backAtWorkspace = false
            return true
        }
        if (formLoader.item && !formLoader.item.commitPendingField()) return true

        // Back Android NO recorre etapas: el cambio de sección es solo
        // táctil (swipe horizontal). Sin modal ni popup pendiente,
        // el Back pertenece al shell desde cualquier etapa.
        if (!autoSaveCurrentM09(true)) return true

        // Guardamos y devolvemos false para que Main.qml haga RETURN_HOME.
        _backAtWorkspace = false
        return false
    }

    function openCloudCalicataBrowser(archived) {
        if (!root.currentDoc) return
        if (formLoader.item && !formLoader.item.commitPendingField()) return
        if (!root.autoSaveCurrentM09(true)) return
        var h = root.currentDoc.header || {}
        var projectId = String(h.projectId || h.project_id || "")
        if (!projectId.length) {
            root.showMsg("Proyecto requerido",
                         "Selecciona primero el proyecto real de la calicata.")
            return
        }
        root._cloudListArchived = archived === true
        root._remoteLoadingProjectId = projectId
        root.workspaceStatusText = "Consultando Calicatas Web del proyecto…"
        CalicataCloud.listProjectCalicatas(projectId)
        CalicataCloud.flushActivity()
        cloudCalicatasPopup.open()
    }

    // Archived sheets of the listed project: server rows plus local drafts
    // that never reached the server. Only offered for explicit restore.
    readonly property var archivedCalicataEntries: {
        var entries = []
        if (!cloudCalicatasPopup.opened || !root._cloudListArchived) return entries
        var remote = CalicataCloud.archivedProjectCalicatas || []
        for (var i = 0; i < remote.length; ++i)
            entries.push({id: String(remote[i].id), code: remote[i].code, title: remote[i].title,
                          location: remote[i].location, status: "ARCHIVADO", localDraftId: ""})
        var probe = root.currentDoc
        if (probe && probe.listProjectDrafts && root._remoteLoadingProjectId.length) {
            var local = probe.listProjectDrafts(root._remoteLoadingProjectId, true)
            for (var k = 0; k < local.length; ++k) {
                if (String(local[k].status) !== "ARCHIVADO" || String(local[k].remoteCalicataId || "").length)
                    continue
                entries.push({id: "", code: local[k].code || local[k].title, title: "Borrador local",
                              location: "", status: "ARCHIVADO", localDraftId: String(local[k].instanceId),
                              fileUrl: String(local[k].fileUrl || "")})
            }
        }
        return entries
    }

    function openArchivedEntry(entry) {
        if (!entry) return
        if (entry.localDraftId && entry.localDraftId.length) {
            restoreLocalArchivedDraft(entry.localDraftId, entry.fileUrl)
            return
        }
        loadCloudCalicata(entry, true)
    }

    function restoreLocalArchivedDraft(draftId, fileUrl) {
        if (root._indexForDocId(draftId) >= 0) {
            root.selectTab(root._indexForDocId(draftId))
            cloudCalicatasPopup.close()
            return
        }
        if (formLoader.item && !formLoader.item.commitPendingField()) return
        if (root.currentDoc && !root.autoSaveCurrentM09(true)) return
        var doc = _newDoc()
        var loaded = !!doc && doc.loadDraftById && doc.loadDraftById(draftId)
        if (!loaded && doc && fileUrl && fileUrl.length) loaded = doc.load(Qt.resolvedUrl(fileUrl))
        if (!loaded || _docInstanceId(doc) !== draftId) {
            if (doc && doc.destroy) doc.destroy()
            root.showMsg("No se pudo abrir el borrador archivado", "El archivo local no está disponible.")
            return
        }
        var urlStr = doc.fileUrl && doc.fileUrl.toString ? doc.fileUrl.toString() : ""
        var tid = tabIdCounter++
        _appendDoc(doc)
        tabsModel.append({
            tid: tid, docId: draftId, title: String(doc.displayName || _newUntitledTitle()),
            fileUrl: urlStr, openKey: urlStr.length ? _openKeyFromUrl(urlStr) : "",
            dirty: false, conflict: false, isScratch: !urlStr.length, demoSeeded: false,
            selected: false, thumbUrl: ""
        })
        selectTab(tabsModel.count - 1)
        cloudCalicatasPopup.close()
        root._restoringDocId = draftId
        if (!CalicataCloud.restoreDocument(doc)) root._restoringDocId = ""
    }

    function restoreCurrentCalicata() {
        if (!root.currentDoc || root._restoringDocId.length) return
        root._restoringDocId = root._docInstanceId(root.currentDoc)
        root.workspaceStatusText = "Restaurando calicata…"
        if (!CalicataCloud.restoreDocument(root.currentDoc)) root._restoringDocId = ""
    }

    function changeCurrentStatus(status) {
        if (!root.currentDoc || root._statusChangingDocId.length) return
        if (!root.autoSaveCurrentM09(true)) return
        root._statusChangingDocId = root._docInstanceId(root.currentDoc)
        root.workspaceStatusText = "Cambiando estado a " + root.statusLabel(status) + "…"
        if (!CalicataCloud.changeStatus(root.currentDoc, status)) root._statusChangingDocId = ""
    }

    // Snapshot of the current sheet shown by the Dock "information" peek.
    property var calicataInfo: ({})
    function showCalicataInfo() {
        var doc = root.currentDoc
        if (!doc) return
        var h = doc.header || {}
        function text(value) {
            return String(value === undefined || value === null ? "" : value).trim()
        }
        root.calicataInfo = {
            code: text(h.code || h.codigo),
            project: text((h.projectCode ? h.projectCode + " · " : "") + (h.projectName || "")),
            status: text(doc.status),
            statusLabel: text(root.statusLabel(doc.status)),
            syncState: text(doc.syncState),
            syncLabel: text(root.syncLabel(doc.syncState)),
            localId: text(doc.instanceId),
            remoteId: text(h.remoteCalicataId),
            createdAt: text(h.created_at || h.local_created_at),
            updatedAt: text(h.updated_at),
            version: text(h.row_version)
        }
        infoPeek.originX = root._dockSlotCenterX(1, root.buildContextActions(
            root.contextStage, root.contextCorrectingReview, !!formLoader.item).length,
            Overlay.overlay ? Overlay.overlay.width : root.width)
        infoPeek.open()
    }

    // UX-only guard for UNIQUE(project_id, code) inside the open workspace.
    function _workspaceCodeConflict(doc) {
        if (!doc) return ""
        var h = doc.header || {}
        var code = String(h.code || h.codigo || "").trim()
        var projectId = String(h.projectId || "")
        var remoteId = String(h.remoteCalicataId || "")
        if (!code.length || !projectId.length) return ""
        for (var i = 0; i < tabsModel.count; ++i) {
            var other = _docAt(i)
            if (!other || other === doc || _docInstanceId(other) === _docInstanceId(doc)) continue
            var oh = other.header || {}
            if (String(oh.projectId || "") !== projectId) continue
            if (String(oh.code || oh.codigo || "").trim() !== code) continue
            if (remoteId.length && String(oh.remoteCalicataId || "") === remoteId) continue
            if (String(other.status || "") === "ARCHIVADO" && !String(oh.remoteCalicataId || "").length) continue
            return "Otra ficha abierta de este proyecto ya usa el código " + code
                    + ". Cambia el código antes de sincronizar."
        }
        return ""
    }

    function _logPendingExport(doc, synced) {
        if (!doc || root._pendingExportLogDocId !== root._docInstanceId(doc)) return
        var fileName = root._pendingExportFileName
        root._pendingExportLogDocId = ""
        root._pendingExportFileName = ""
        var h = doc.header || {}
        CalicataCloud.logActivity(doc, "EXPORT_CALICATA",
                                  "Calicata exportada a Excel: " + String(h.code || h.codigo || ""),
                                  {format: "XLSX", file_name: fileName, synced_before_publish: synced === true})
    }

    // P0-A: abrir una calicata cloud existente (Web/InGeDrive) por su
    // identidad canónica project_id + calicatas.id. Nunca crea otra fila: si
    // ya hay una pestaña ligada a ese UUID se reutiliza; si no, se hidrata
    // desde la nube en una pestaña limpia (instanceId solo es identidad local).
    function beginOperation(kind, title, detail, options) {
        var id = kind + "-" + (++root._operationSeq)
        root.foregroundOperation = Object.assign({ id: id, kind: kind, phase: "BEGIN", title: title, detail: detail,
                                                   blocking: true, cover: false, immediate: false,
                                                   startedAt: Date.now() }, options || {})
        console.info("INGE_CALICATA_OPERATION_BEGIN kind=" + kind + " id=" + id)
        return id
    }
    function phaseOperation(id, phase, detail, title) {
        var op = root.foregroundOperation
        if (!op || op.id !== id) return
        console.info("INGE_CALICATA_OPERATION_PHASE kind=" + op.kind + " phase=" + phase)
        root.foregroundOperation = Object.assign({}, op, { phase: phase, detail: detail,
                                                           title: title !== undefined ? title : op.title })
    }
    // result "OK" cierra; "SUCCESS"/"ERROR"/"INFO" deja una hoja con acciones.
    function endOperation(id, result, sheet) {
        var op = root.foregroundOperation
        if (!op || op.id !== id) return
        console.info("INGE_CALICATA_OPERATION_END kind=" + op.kind + " result=" + result
                     + " elapsedMs=" + (Date.now() - op.startedAt))
        root.foregroundOperation = result === "OK" ? null
                : Object.assign({}, op, sheet || {}, { result: result, cover: false, immediate: true })
    }
    // Un toque = un intent: un segundo toque mientras la hoja se oculta no lanza otro visor/chooser.
    property double _fileIntentAt: 0
    function _operationAction(actionId, op) {
        root.foregroundOperation = null
        if (!op) return
        if (actionId === "retry" && typeof op.retry === "function") op.retry()
        else if ((actionId === "open" || actionId === "share") && typeof ExcelExporter !== "undefined") {
            var now = Date.now()
            if (now - root._fileIntentAt < 900) {
                console.info("INGE_CALICATA_FILE_INTENT_IGNORED_DOUBLE_TAP")
                return
            }
            root._fileIntentAt = now
            var share = actionId === "share"
            var isPdf = op.kind === "EXPORT_PDF"
            console.info(isPdf ? (share ? "INGE_CALICATA_PDF_SHARE_REQUEST" : "INGE_CALICATA_PDF_OPEN_REQUEST")
                               : "INGE_CALICATA_EXPORT_OPEN_REQUEST")
            var exporter = ExcelExporter
            var ok = op.filePath ? exporter.openExportedFile(String(op.filePath), share)
                                 : exporter.openLastExport(share)
            if (!ok) {
                // La hoja vuelve: el archivo nunca se pierde.
                root.foregroundOperation = op
                var why = String(exporter.lastError || "")
                root.showMsg(share ? "No se pudo compartir" : "No se pudo abrir el archivo",
                             (why.length ? why : "No hay una aplicación compatible instalada.") + " El archivo se conserva.")
            }
        } else if (actionId === "back") root.requestBack()
    }

    Timer {
        id: hydrateTimeout
        interval: 45000
        repeat: false
        onTriggered: {
            var op = root.foregroundOperation
            if (!op || op.kind !== "CALICATA_OPEN" || op.result) return
            root._remoteLoadingDocId = ""
            root.endOperation(op.id, "ERROR", { title: "No se pudo cargar la ficha",
                detail: "La nube no respondió a tiempo. Tus datos locales se conservan.",
                actions: [{ id: "retry", label: "Reintentar" }, { id: "back", label: "Volver" }] })
        }
    }

    function openCloudCalicata(projectId, calicataId) {
        if (root.leaving) return
        projectId = String(projectId || "").trim()
        calicataId = String(calicataId || "").trim().toLowerCase()
        if (!projectId.length || !calicataId.length) {
            root.showMsg("No se pudo abrir la calicata", "El documento no contiene una identidad cloud válida.")
            return
        }
        if (!root.initializationComplete) {
            root._pendingCloudOpen = { projectId: projectId, calicataId: calicataId }
            return
        }
        var openOp = root.beginOperation("CALICATA_OPEN", "Abriendo ficha…", "Conectando con InGeDrive",
                                         { cover: true, retry: function() { root.openCloudCalicata(projectId, calicataId) } })
        hydrateTimeout.restart()
        for (var i = 0; i < tabsModel.count; ++i) {
            var existing = root._docAt(i)
            var remote = existing ? String(existing.header.remoteCalicataId || "").toLowerCase() : ""
            if (remote === calicataId) {
                console.info("INGE_CALICATA_BIND_IDENTITY reuse tab calicataId=" + calicataId)
                root.selectTab(i)
                // Cambios locales sin confirmar no se pisan: los lleva el
                // autosave con CAS (CONFLICT si Web cambió).
                if (!existing.dirty && String(existing.syncState || "") !== "PENDING"
                        && String(existing.syncState || "") !== "CONFLICT") {
                    root._remoteLoadingProjectId = projectId
                    root._remoteLoadingDocId = root._docInstanceId(existing)
                    console.info("INGE_CALICATA_HYDRATE_BEGIN projectId=" + projectId + " calicataId=" + calicataId)
                    root.phaseOperation(openOp, "HYDRATE", "Recuperando datos de Calicatas", "Sincronizando ficha…")
                    CalicataCloud.loadRemoteDocument(existing, projectId, calicataId)
                } else {
                    hydrateTimeout.stop()
                    root.endOperation(openOp, "OK")
                }
                return
            }
        }
        // P0: un draft local ya ligado a este calicatas.id (aunque no esté
        // abierto) se reutiliza; nunca se crea otro draft para el mismo UUID.
        var probe = root.currentDoc
        var drafts = probe && probe.listProjectDrafts ? probe.listProjectDrafts(projectId, true) : []
        for (var d = 0; d < drafts.length; ++d) {
            if (String(drafts[d].remoteCalicataId || "").toLowerCase() !== calicataId) continue
            var reused = root._openLocalDraftTab(String(drafts[d].instanceId), String(drafts[d].fileUrl || ""))
            if (!reused) break
            console.info("INGE_CALICATA_BIND_IDENTITY reuse draft=" + drafts[d].instanceId + " calicataId=" + calicataId)
            var pendingLocal = String(reused.syncState || "") === "PENDING" || String(reused.syncState || "") === "CONFLICT"
            if (!pendingLocal) {
                root._remoteLoadingProjectId = projectId
                root._remoteLoadingDocId = root._docInstanceId(reused)
                console.info("INGE_CALICATA_HYDRATE_BEGIN projectId=" + projectId + " calicataId=" + calicataId)
                root.phaseOperation(openOp, "HYDRATE", "Recuperando datos de Calicatas", "Sincronizando ficha…")
                CalicataCloud.loadRemoteDocument(reused, projectId, calicataId)
            } else {
                hydrateTimeout.stop()
                root.endOperation(openOp, "OK")
            }
            return
        }
        root._remoteLoadingProjectId = projectId
        root.loadCloudCalicata({ id: calicataId })
    }

    function _openLocalDraftTab(draftId, fileUrl) {
        var open = root._indexForDocId(draftId)
        if (open >= 0) { root.selectTab(open); return root._docAt(open) }
        if (formLoader.item && !formLoader.item.commitPendingField()) return null
        if (root.currentDoc && !root.autoSaveCurrentM09(true)) return null
        var doc = _newDoc()
        var loaded = !!doc && doc.loadDraftById && doc.loadDraftById(draftId)
        if (!loaded && doc && fileUrl && fileUrl.length) loaded = doc.load(Qt.resolvedUrl(fileUrl))
        if (!loaded || _docInstanceId(doc) !== draftId) {
            if (doc && doc.destroy) doc.destroy()
            return null
        }
        var urlStr = doc.fileUrl && doc.fileUrl.toString ? doc.fileUrl.toString() : ""
        _appendDoc(doc)
        tabsModel.append({
            tid: tabIdCounter++, docId: draftId, title: String(doc.displayName || _newUntitledTitle()),
            fileUrl: urlStr, openKey: urlStr.length ? _openKeyFromUrl(urlStr) : "",
            dirty: false, conflict: false, isScratch: !urlStr.length, demoSeeded: false,
            selected: false, thumbUrl: ""
        })
        selectTab(tabsModel.count - 1)
        return doc
    }

    // P0-B: borrador automático. Con proyecto real y código, la primera
    // sincronización crea UNA fila BORRADOR (create_my_project_calicata_v02) y
    // CalicataCloudService liga calicatas.id + row_version al instante, así un
    // reintento actualiza la misma fila. Después, cada autosave con cambios
    // viaja por la misma vía. Sin red queda PENDING y se reintenta.
    function _queueAutoCloudSync(doc) {
        if (root.leaving || !doc || doc.closed === true || typeof CalicataCloud === "undefined") return
        if (root._autoSyncDocId.length || root._savingCloudDocId.length || root._publishingDocId.length
                || root._driveJsonBusy || root._remoteLoadingDocId.length || root._archivingCloudDocId.length) return
        var h = doc.header || {}
        var state = String(doc.syncState || "")
        if (!String(h.projectId || "").length || !String(h.code || h.codigo || "").trim().length) return
        if (String(doc.status || "") === "ARCHIVADO" || state === "SYNCING" || state === "CONFLICT") return
        if (state === "SYNCED" && !doc.dirty) return
        if (root._workspaceCodeConflict(doc).length) return
        var creating = !String(h.remoteCalicataId || "").length
        // Una fila ya creada se actualiza como máximo cada 8 s (el timer de 20 s
        // recoge el resto); la creación del borrador no espera.
        if (!creating && Date.now() - root._lastAutoSyncMs < 8000) return
        root._lastAutoSyncMs = Date.now()
        root._autoSyncCreating = creating
        root._autoSyncDocId = root._docInstanceId(doc)
        if (!CalicataCloud.syncDocument(doc, "autosave")) {
            root._autoSyncDocId = ""
            root._autoSyncCreating = false
        }
    }

    function loadCloudCalicata(row, restoreAfterLoad) {
        if (!row || !row.id || !root._remoteLoadingProjectId.length) return
        if (root._remoteLoadingDocId.length) return

        // Never overwrite a populated local tab just because the user opens a
        // remote sheet. Keep the current draft and load Web into a clean tab.
        var h = root.currentDoc ? (root.currentDoc.header || {}) : {}
        var populated = !!root.currentTab && (root.currentTab.dirty
                        || String(h.code || h.codigo || "").trim().length > 0
                        || (root.currentDoc.cortes && root.currentDoc.cortes.length > 0))
        if (populated) {
            if (!root.addNewTab()) return
        }
        var doc = root.currentDoc
        if (!doc) return
        root._remoteLoadingDocId = root._docInstanceId(doc)
        root._restoreAfterLoadDocId = restoreAfterLoad === true ? root._remoteLoadingDocId : ""
        root.workspaceStatusText = "Abriendo calicata online…"
        console.info("INGE_CALICATA_HYDRATE_BEGIN projectId=" + root._remoteLoadingProjectId + " calicataId=" + String(row.id))
        var hydrating = root.foregroundOperation
        if (hydrating && hydrating.kind === "CALICATA_OPEN")
            root.phaseOperation(hydrating.id, "HYDRATE", "Recuperando datos de Calicatas", "Sincronizando ficha…")
        else
            root.beginOperation("CALICATA_OPEN", "Sincronizando ficha…", "Recuperando datos de Calicatas", { cover: true })
        CalicataCloud.loadRemoteDocument(doc, root._remoteLoadingProjectId, String(row.id))
    }

    // Archive is a soft status change (data, strata, photos and history are
    // kept). One path for synced sheets (server CAS) and local-only drafts.
    function archiveCurrentCalicata() {
        if (!currentDoc || !autoSaveCurrentM09(true)) return
        if (root._archivingCloudDocId.length) return
        root._archivingCloudDocId = root._docInstanceId(currentDoc)
        root._archivingCloudTid = currentTab.tid
        workspaceStatusText = "Archivando calicata…"
        if (!CalicataCloud.archiveDocument(currentDoc)) {
            root._archivingCloudDocId = ""
            root._archivingCloudTid = -1
            showMsg("No se pudo archivar", CalicataCloud.lastError)
        }
    }

    function _finishReviewCorrectionAfterSave() {
        var form = formLoader.item
        if (!form || form.reviewCorrectionActive !== true
                || typeof form.finishReviewCorrection !== "function")
            return
        Qt.callLater(function() {
            if (formLoader.item === form)
                form.finishReviewCorrection()
        })
    }

    function exportExcelIfOpen() {
        if (root.hasOpenDocument)
            root.exportCurrentExcel()
    }

    function exportPdfIfOpen() {
        if (!root.hasOpenDocument)
            return
        var form = formLoader.item
        if (form && typeof form.exportPdfFlow === "function")
            form.exportPdfFlow()
        else
            root.showMsg("Exportacion PDF no disponible",
                         "El formulario actual no expone exportPdfFlow().")
    }

    function openCoordinatePicker() {
        if (Qt.platform.os !== "android") {
            if (formLoader.item) formLoader.item.scrollToSection(2)
            root.showMsg("Ubicación", "El mapa nativo está disponible en Android. Edita las coordenadas UTM en Ubicación.")
            return
        }
        var form = formLoader.item
        if (!form || !form.commitPendingField()) return
        form.flushRequested()
        // Cierra el IME solo si está visible (sin hide/resize redundante) y sin
        // devolver el foco al formulario: el Popup del mapa recibe el foco.
        if (Qt.inputMethod.visible) {
            Qt.inputMethod.commit()
            Qt.inputMethod.hide()
        }
        coordinatePicker.documentId = root._docInstanceId(root.currentDoc)
        coordinatePicker.open()
    }

    // "Usar esta ubicación": único punto que persiste el candidato del mapa.
    // X/Y/zona/lat/lon siempre; Z solo si el candidato trae altitud real.
    function _commitCoordinateCandidate() {
        var map = coordinateMap.item
        if (!map || !formLoader.item || coordinatePicker.documentId !== root._docInstanceId(root.currentDoc)) {
            coordinatePicker.close()
            return
        }
        console.info("INGE_LOCATION_COMMIT source=" + map.selectedSource + " altitude=" + (isFinite(map.selectedAlt) ? "device" : "kept"))
        if (formLoader.item.acceptMapPoint(map.selectedLat, map.selectedLon, map.selectedAlt,
                                           map.selectedAccuracy, map.selectedSource))
            coordinatePicker.close()
    }

    function openAnchoredPopup(popup, requestedWidth) {
        var ov = Overlay.overlay
        popup.parent = ov
        popup.width = Math.min(root.width - 24, root.__dp(requestedWidth))
        popup.x = Math.max(12, (ov.width - popup.width) / 2)
        popup.y = Math.max(12, ov.height - popup.height - root.__dp(104))
        popup.open()
        Qt.callLater(function() {
            popup.y = Math.max(12,
                ov.height - popup.height - root.__dp(104))
        })
    }

    function openSectionsPopup() {
        if (root.hasOpenDocument)
            root.openAnchoredPopup(sectionsPopup, 344)
    }

    function openTabsPopup() {
        if (formLoader.item && !formLoader.item.commitPendingField()) return
        root.resumeView = "tabs"
        tabsPopup.open()
    }

    ListModel { id: tabsModel }

    // IDs estables para historial tipo Chrome
    property int tabIdCounter: 1
    property var navHistory: []
    property int navPos: -1
    property bool _navJump: false

    property int docCounter: 1
    property int currentIndex: 0
    property bool autoSaveEnabled: true

    Settings {
        id: calicatasSettingsM09
        category: "InGePlus/M09Calicatas"
        property bool autoSave: true
        property string lastDocumentUrl: ""
    }

    onAutoSaveEnabledChanged: calicatasSettingsM09.autoSave = autoSaveEnabled
    property string lastExcelPath: ""
    property string exportProgressText: "Preparando exportación..."
    property string exportResultText: ""
    property string workspaceStatusText: ""
    // El checkpoint pertenece al UUID activo; dirty sigue indicando que falta
    // guardar la ficha definitiva incluso cuando su borrador ya está a salvo.
    property string draftCheckpointDocId: ""
    readonly property bool formHasPendingEdits: !!formLoader.item
        && formLoader.item._pendingCommitFields.length > 0
    readonly property bool persistenceHasError: !!currentDoc && String(currentDoc.errorString || "").length > 0
    readonly property string persistenceStatus: {
        if (!currentDoc) return workspaceStatusText
        if (persistenceHasError) return "Error de guardado: " + currentDoc.errorString
        if (formHasPendingEdits) return "Cambios sin guardar"
        if (p0AutoSaveDebounce.running) return "Guardando…"
        if (currentTab && currentTab.dirty) {
            if (draftCheckpointDocId === _docInstanceId(currentDoc))
                return "Borrador guardado automáticamente"
            return autoSaveEnabled ? "Cambios sin guardar · Auto-guardado: activo"
                                   : "Cambios sin guardar · Auto-guardado: manual"
        }
        return currentDoc ? "Guardado" : ""
    }
    property bool saveConfirmed: false
    readonly property bool debugCt12FixtureEnabled:
        Qt.application.arguments.indexOf("--debug-ct12-fixture") >= 0

    // ===== tamaños consistentes para botones =====
    readonly property int topBtnW: root.__touchTarget
    readonly property int topBtnH: root.__touchTarget
    readonly property int botBtnW: root.__dp(62)
    readonly property int botBtnH: root.__touchTarget

    property int _prevIndex: -1
    property bool _workspaceInitialized: false
    property bool initializationComplete: false

    property string resumeView: "doc"    // "doc" | "tabs"
    property bool _openFromTabsPopup: false




    property bool _menuJustClosed: false

    property int selectedCount: 0

    function updateSelectedCount() {
        var n = 0
        for (var i=0; i<tabsModel.count; ++i) {
            var t = tabsModel.get(i)
            if (t && t.selected) n++
        }
        selectedCount = n
    }

    Timer {
        id: menuGuard
        interval: 120
        repeat: false
        onTriggered: root._menuJustClosed = false
    }

    property bool tabsEditMode: false


    property int thumbW: root.__armPhone ? root.__dp(300) : root.__dp(360)
    property int thumbH: root.__armPhone ? root.__dp(188) : root.__dp(226)

    property var docsList: []

    function _docInstanceId(candidate) {
        if (!candidate || candidate.instanceId === undefined || candidate.instanceId === null)
            return ""
        return String(candidate.instanceId)
    }

    function _mappingError(context, index, tabDocId, actualDocId) {
        console.error("[InGe+ M09] mapping error context=" + String(context || "unknown")
                      + " index=" + index
                      + " tab.docId=" + String(tabDocId || "")
                      + " doc.instanceId=" + String(actualDocId || ""))
    }

    function _appendDoc(doc) {
        docsList = docsList.concat([doc])
    }

    function _removeDocAt(i) {
        if (i < 0 || i >= docsList.length) return null
        var next = docsList.slice(0)
        var removed = next.splice(i, 1)
        docsList = next
        return removed.length ? removed[0] : null
    }

    function _fileStemFromUrl(urlStr) {
        var fn = _fileNameFromUrl(urlStr)
        return fn.replace(".calicata.json","").replace(".json","")
    }

    function _headerStem(doc) {
        var h = doc ? doc.header : null
        var code = h && (h.codigo || h.calicata || h.pk || h.progresiva)
                ? (h.codigo || h.calicata || h.pk || h.progresiva) : ""
        return _safeStem(code)
    }

    property string _mismatch_fileStem: ""
    property string _mismatch_headerStem: ""
    property string _mismatch_folderAbs: ""
    property string _mismatch_oldAbs: ""

    function _docAt(i) {
        if (i < 0 || i >= docsList.length) return null
        var candidate = docsList[i]
        if (!candidate || candidate.closed === true) return null
        if (i >= tabsModel.count) {
            if (tabsModel.count > 0)
                _mappingError("_docAt", i, "", _docInstanceId(candidate))
            return null
        }
        var tab = tabsModel.get(i)
        var tabDocId = tab ? String(tab.docId || "") : ""
        var actualDocId = _docInstanceId(candidate)
        if (!tab || !tabDocId.length || tabDocId !== actualDocId) {
            if (!_closeOperationActive)
                _mappingError("_docAt", i, tabDocId, actualDocId)
            return null
        }
        return candidate
    }

    function _indexForDocId(docId) {
        var wanted = String(docId || "")
        if (!wanted.length) return -1
        for (var i = 0; i < tabsModel.count; ++i) {
            var tab = tabsModel.get(i)
            if (tab && String(tab.docId || "") === wanted)
                return i
        }
        return -1
    }

    function _validateTabDocMapping(context) {
        if (tabsModel.count !== docsList.length) {
            _mappingError(context, -1, "tabs=" + tabsModel.count,
                          "docs=" + docsList.length)
            return false
        }
        for (var i = 0; i < tabsModel.count; ++i) {
            var tab = tabsModel.get(i)
            var candidate = docsList[i]
            var tabDocId = tab ? String(tab.docId || "") : ""
            var actualDocId = _docInstanceId(candidate)
            if (!tab || !candidate || candidate.closed === true
                    || !tabDocId.length || tabDocId !== actualDocId) {
                _mappingError(context, i, tabDocId, actualDocId)
                return false
            }
        }
        return true
    }

    function _indexForTid(tid) {
        for (var i = 0; i < tabsModel.count; ++i) {
            var tab = tabsModel.get(i)
            if (tab && tab.tid === tid) return i
        }
        return -1
    }

    function _pendingSaveIndex() {
        var index = _indexForTid(_pendingSaveTid)
        if (index < 0) return -1
        var tab = tabsModel.get(index)
        var actualDocId = _docInstanceId(_docAt(index))
        if (!tab || String(tab.docId || "") !== _pendingSaveDocId
                || actualDocId !== _pendingSaveDocId) {
            _mappingError("pending save", index, _pendingSaveDocId, actualDocId)
            return -1
        }
        return index
    }

    function _clearPendingSave() {
        _pendingSaveTid = -1
        _pendingSaveDocId = ""
    }

    function _prepareFormForDocClose(targetDoc) {
        if (!targetDoc || !formLoader.item) return
        if (formLoader.item.prepareForDocumentClose)
            formLoader.item.prepareForDocumentClose(targetDoc)
    }

    function _retireDoc(targetDoc) {
        if (!targetDoc) return
        try {
            if (targetDoc.prepareForClose) targetDoc.prepareForClose()
        } catch (error) {
            console.warn("[InGe+ M09] no se pudo preparar documento para cierre:", error)
        }
        if (_retiredDocs.indexOf(targetDoc) < 0)
            _retiredDocs = _retiredDocs.concat([targetDoc])
        if (_retiredDocs.length === 25 || (_retiredDocs.length > 25
                                            && _retiredDocs.length % 25 === 0)) {
            console.warn("[InGe+ M09] documentos retirados retenidos="
                         + _retiredDocs.length
                         + "; liberación diferida no aplicada por riesgo de lifetime")
        }
    }

    function _syncDocsList(context) {
        return _validateTabDocMapping(context || "_syncDocsList")
    }


    // ====== THUMBS (persistentes en disco) ======
    function _thumbsDirAbs() {
        var dir = FS.join(docs.basePath, "Proyecto_Local/Calicata/Edit/.thumbs")
        FS.mkpath(dir)
        return dir
    }

    function _safeStem(s) {
        s = (s || "").toString().trim()
        // inválidos Windows: <>:"/\|?* + control chars
        s = s.replace(/[<>:"\/\\|?*\x00-\x1F]/g, "_")
        // no terminar con punto/espacio
        s = s.replace(/[\. ]+$/g, "")
        if (!s.length) s = "calicata"
        return s
    }

    function _thumbAbsForTab(i) {
        var t = tabsModel.get(i)
        var d = _docAt(i)
        var base = ""
        if (d && d.fileUrl && d.fileUrl.toString().length) {
            base = _fileNameFromUrl(d.fileUrl.toString())
            base = base.replace(".calicata.json","").replace(".json","")
        } else {
            base = "scratch_" + (t ? t.tid : i)
        }
        base = _safeStem(base)
        return FS.join(_thumbsDirAbs(), base + ".png")
    }

    property bool _thumbBusy: false

    // forceTop=true -> antes de capturar sube el scroll a 0 (para preview “primera parte”)
    function captureThumb(i, forceTop) {
        if (_thumbBusy) return
        if (i < 0 || i >= tabsModel.count) return
        if (i !== currentIndex) return
        if (formLoader.status !== Loader.Ready) return
        if (!formLoader.item) return

        var t = tabsModel.get(i)
        var targetDoc = _docAt(i)
        var targetTid = t ? t.tid : -1
        var targetDocId = _docInstanceId(targetDoc)
        if (!t || !targetDocId.length || String(t.docId || "") !== targetDocId)
            return
        var need = !!forceTop || (t.dirty || !(t.thumbUrl && t.thumbUrl.length))
        if (!need) return

        _thumbBusy = true

        if (forceTop && formLoader.item.scrollToTop)
            formLoader.item.scrollToTop()

        var outAbs = _thumbAbsForTab(i)
        var outUrl = _toFileUrl(outAbs)

        formLoader.grabToImage(function(res) {
            try {
                if (!res) return
                var liveIndex = root._indexForTid(targetTid)
                if (liveIndex < 0
                        || root._docInstanceId(root._docAt(liveIndex)) !== targetDocId
                        || root._docInstanceId(root.currentDoc) !== targetDocId) {
                    return
                }
                if (res.saveToFile) {
                    var ok = res.saveToFile(outAbs)
                    if (!ok) ok = res.saveToFile(outUrl)
                    if (ok) tabsModel.setProperty(liveIndex, "thumbUrl", String(outUrl))
                }
            } finally {
                _thumbBusy = false
            }
        }, Qt.size(thumbW, thumbH))
    }

    function clearTabSelection() {
        for (var i=0; i<tabsModel.count; ++i)
            tabsModel.setProperty(i, "selected", false)
        selectedCount = 0
    }

    function selectedTabsCount() {
        var n = 0
        for (var i=0; i<tabsModel.count; ++i) {
            var t = tabsModel.get(i)
            if (t && t.selected) n++
        }
        return n
    }

    function _closeTabsByTids(tids, discardChanges) {
        if (!discardChanges && currentTab && tids && tids.indexOf(currentTab.tid) >= 0 && !autoSaveCurrentM09(true)) return
        if (_closeOperationActive || !tids || !tids.length) return

        var validTids = []
        var seen = {}
        var closingDocIds = ({})
        var fallbackIndex = tabsModel.count
        var activeTid = currentTab ? currentTab.tid : -1

        for (var i = 0; i < tids.length; ++i) {
            var tid = Number(tids[i])
            if (seen[tid]) continue
            var idx = _indexForTid(tid)
            if (idx < 0) continue
            seen[tid] = true
            validTids.push(tid)
            fallbackIndex = Math.min(fallbackIndex, idx)
            var closingDoc = _docAt(idx)
            var closingDocId = _docInstanceId(closingDoc)
            closingDocIds[String(tid)] = closingDocId
            console.info("[InGe+ M09] close start tid=" + tid
                         + " instanceId=" + closingDocId)
            _prepareFormForDocClose(closingDoc)
        }

        if (!validTids.length) return

        _closeOperationActive = true
        _closeOperationSerial++
        var closeSerial = _closeOperationSerial
        _suspendFormLoader = true

        Qt.callLater(function() {
            if (closeSerial !== root._closeOperationSerial) return
            var indexes = []
            for (var j = 0; j < validTids.length; ++j) {
                var liveIndex = root._indexForTid(validTids[j])
                if (liveIndex >= 0) indexes.push(liveIndex)
            }
            indexes.sort(function(a, b) { return b - a })

            for (var k = 0; k < indexes.length; ++k) {
                var removeIndex = indexes[k]
                var closingTab = tabsModel.get(removeIndex)
                var closingTid = closingTab ? closingTab.tid : -1
                var retired = root._removeDocAt(removeIndex)
                tabsModel.remove(removeIndex)
                root._retireDoc(retired)
                console.info("[InGe+ M09] close end tid=" + closingTid
                             + " instanceId="
                             + String(closingDocIds[String(closingTid)] || ""))
            }

            root.clearTabSelection()
            root.tabsEditMode = false

            if (tabsModel.count === 0) {
                root.untitledSeq = 0
                root.navHistory = []
                root.navPos = -1
                root.currentIndex = 0
                root._prevIndex = -1
                root.resumeView = "tabs"
                root._suspendFormLoader = false
                root._closeOperationActive = false
                return
            }

            var activeIndex = root._indexForTid(activeTid)
            root.currentIndex = activeIndex >= 0
                    ? activeIndex
                    : Math.max(0, Math.min(fallbackIndex, tabsModel.count - 1))
            root._prevIndex = root.currentIndex
            var resumeTab = tabsModel.get(root.currentIndex)
            var resumeTid = resumeTab ? resumeTab.tid : -1
            var resumeDocId = resumeTab ? String(resumeTab.docId || "") : ""

            Qt.callLater(function() {
                if (closeSerial !== root._closeOperationSerial) return
                root._suspendFormLoader = false
                Qt.callLater(function() {
                    if (closeSerial !== root._closeOperationSerial) return
                    var resumeIndex = root._indexForTid(resumeTid)
                    if (resumeIndex < 0
                            || root._docInstanceId(root._docAt(resumeIndex))
                               !== resumeDocId) {
                        root._mappingError("close restore", resumeIndex,
                                           resumeDocId,
                                           root._docInstanceId(root._docAt(resumeIndex)))
                        root._closeOperationActive = false
                        return
                    }
                    root.currentIndex = resumeIndex
                    root.restoreTab(resumeIndex)
                    root._closeOperationActive = false
                })
            })
        })
    }

    function closeSelectedTabs() {
        if (_closeOperationActive) return

        var tids = []
        var dirtyCount = 0
        for (var i = 0; i < tabsModel.count; ++i) {
            var tab = tabsModel.get(i)
            if (!tab || !tab.selected) continue
            tids.push(tab.tid)
            if (tab.dirty) dirtyCount++
        }

        if (!tids.length) return
        if (dirtyCount > 0) {
            showMsg("Cambios sin guardar",
                    "Hay " + dirtyCount + " ficha(s) seleccionada(s) con cambios. "
                    + "Ciérralas individualmente para elegir Guardar, No guardar o Cancelar.")
            return
        }

        _closeTabsByTids(tids)
    }

    function openDialogAbrirCalicata() {
        if (formLoader.item && !formLoader.item.commitPendingField()) return
        if (!root.autoSaveCurrentM09(true)) return
        inGeDriveCalicataPopup.open()
        Qt.callLater(function() { driveCalicataBrowser.openDriveRoot() })
    }


    // ===== DOC FACTORY (1 doc por pestaña) =====
    Component {
        id: docFactory
        CalicataDocument { }
    }

    readonly property var currentDoc: _docAt(currentIndex)

    function _newDoc() {
        return docFactory.createObject(root)
    }

    function _normPath(p) {
        var s = (p || "").toString().trim()
        if (!s.length) return ""
        // normaliza separadores
        s = s.replace(/\\/g, "/")
        // windows case-insensitive
        if (Qt.platform.os === "windows") s = s.toLowerCase()
        return s
    }

    function _openKey(p) { return _normPath(p) }

    function _findTabByKey(key) {
        for (var i = 0; i < tabsModel.count; ++i) {
            var t = tabsModel.get(i)
            if (t && t.openKey === key) return i
        }
        return -1
    }

    // Sincroniza roles del tab desde el doc (title/dirty/path)
    function _syncTabFromDoc(i) {
        if (i < 0 || i >= tabsModel.count) return
            var t = tabsModel.get(i)
            if (!t) return            // ✅ ya no existe t.doc
            var d = _docAt(i)
            if (!d) return

        var urlStr = d.fileUrl ? d.fileUrl.toString() : ""
        tabsModel.setProperty(i, "fileUrl", urlStr)
        if (urlStr.length) calicatasSettingsM09.lastDocumentUrl = urlStr
        tabsModel.setProperty(i, "openKey", urlStr.length ? _openKeyFromUrl(urlStr) : "")

        var isScratch = !(urlStr && urlStr.length)
        if (!isScratch) tabsModel.setProperty(i, "demoSeeded", false)
        // ✅ Si NO tiene archivo, el dirty real lo maneja el UI (tabsModel.dirty)
        tabsModel.setProperty(i, "dirty", !!d.dirty)

        var title = ""
        if (urlStr.length) {
            // ✅ title = nombre de archivo SIN extensión
            title = _fileNameFromUrl(urlStr)
            title = title.replace(".calicata.json","").replace(".json","")
        } else {
            title = (t.title && t.title.length) ? t.title : _newUntitledTitle()
        }
        tabsModel.setProperty(i, "title", title)
            tabsModel.setProperty(i, "isScratch", !(urlStr && urlStr.length))
    }


    // Tab actual seguro (evita undefined)
    readonly property var currentTab: (tabsModel.count > 0
                                      && currentIndex >= 0
                                      && currentIndex < tabsModel.count)
                                     ? tabsModel.get(currentIndex)
                                     : null

    function _tidIndex(tid) {
        for (var i = 0; i < tabsModel.count; ++i) {
            var t = tabsModel.get(i)
            if (t && t.tid === tid) return i
        }
        return -1
    }

    function _newUntitledTitle() {
        untitledSeq++
        return "Sin guardar " + untitledSeq
    }

    function _pushHistory(tid) {
        if (_navJump) return
        if (tid === undefined || tid === null) return
        if (navPos >= 0 && navHistory.length && navHistory[navPos] === tid) return
        navHistory = navHistory.slice(0, navPos + 1)
        navHistory.push(tid)
        navPos = navHistory.length - 1
    }

    function canGoBack() {
        var p = navPos - 1
        while (p >= 0) {
            if (_tidIndex(navHistory[p]) >= 0) return true
            p--
        }
        return false
    }

    function canGoForward() {
        var p = navPos + 1
        while (p < navHistory.length) {
            if (_tidIndex(navHistory[p]) >= 0) return true
            p++
        }
        return false
    }

    function goBackHistory() {
        var p = navPos - 1
        while (p >= 0) {
            var idx = _tidIndex(navHistory[p])
            if (idx >= 0) {
                _navJump = true
                navPos = p
                selectTab(idx)
                Qt.callLater(function(){ _navJump = false })
                return
            }
            p--
        }
    }

    function goForwardHistory() {
        var p = navPos + 1
        while (p < navHistory.length) {
            var idx = _tidIndex(navHistory[p])
            if (idx >= 0) {
                _navJump = true
                navPos = p
                selectTab(idx)
                Qt.callLater(function(){ _navJump = false })
                return
            }
            p++
        }
    }

    function _pad2(value) {
        return value < 10 ? "0" + value : String(value)
    }

    function _todayIso() {
        var now = new Date()
        return now.getFullYear() + "-" + _pad2(now.getMonth() + 1) + "-" + _pad2(now.getDate())
    }

    function restorePersistentDraftTabs() {
        var probe = _newDoc()
        if (!probe || !probe.listDrafts) {
            if (probe && probe.destroy) probe.destroy()
            return 0
        }

        var drafts = probe.listDrafts()
        if (probe.destroy) probe.destroy()

        var restored = 0
        for (var i = 0; i < drafts.length; ++i) {
            var info = drafts[i]
            var draftId = info && info.instanceId !== undefined
                    ? String(info.instanceId) : ""
            if (!draftId.length || _indexForDocId(draftId) >= 0)
                continue

            var doc = _newDoc()
            if (!doc || !doc.loadDraftById || !doc.loadDraftById(draftId)) {
                if (doc && doc.destroy) doc.destroy()
                continue
            }

            var docId = _docInstanceId(doc)
            if (!docId.length || docId !== draftId || _indexForDocId(docId) >= 0) {
                if (doc.destroy) doc.destroy()
                continue
            }

            var urlStr = doc.fileUrl && doc.fileUrl.toString
                    ? doc.fileUrl.toString() : ""
            var openKey = urlStr.length ? _openKeyFromUrl(urlStr) : ""
            if (openKey.length && _findTabByKey(openKey) >= 0) {
                if (doc.destroy) doc.destroy()
                continue
            }

            var tid = tabIdCounter++
            _appendDoc(doc)
            tabsModel.append({
                tid: tid,
                docId: docId,
                title: info && info.title ? String(info.title) : String(doc.displayName || _newUntitledTitle()),
                fileUrl: urlStr,
                openKey: openKey,
                dirty: true,
                conflict: false,
                isScratch: !urlStr.length,
                demoSeeded: false,
                selected: false,
                thumbUrl: ""
            })
            restored++
        }

        if (restored > 0) {
            currentIndex = 0
            _prevIndex = 0
            _syncDocsList("restorePersistentDraftTabs")
            workspaceStatusText = restored === 1
                    ? "Borrador recuperado automáticamente"
                    : (restored + " borradores recuperados automáticamente")
            Qt.callLater(function() {
                if (root.currentIndex >= 0 && root.currentIndex < tabsModel.count)
                    root.restoreTab(root.currentIndex)
            })
        }

        return restored
    }

    function createInitialScratchTab() {
        createScratchTab()
    }

    function createScratchTab() {
        var doc = _newDoc()
        var docId = _docInstanceId(doc)
        var tid = tabIdCounter++
        if (!doc || !docId.length) {
            console.error("[InGe+ M09] no se pudo crear documento para tid=" + tid)
            return
        }
        _appendDoc(doc)

        tabsModel.append({
            tid: tid,
            docId: docId,
            title: _newUntitledTitle(),
            fileUrl: "",
            openKey: "",
            dirty: false,
            conflict: false,
            isScratch: true,
            demoSeeded: false,
            selected: false,
            thumbUrl: ""          // ✅
        })
        currentIndex = tabsModel.count - 1
        _syncTabFromDoc(currentIndex)
        console.info("[InGe+ M09] create tab tid=" + tid + " instanceId=" + docId)
    }

    function ensureAtLeastOneTab() {
        if (tabsModel.count === 0) {
            createScratchTab()
            return
        }
        if (currentIndex < 0) currentIndex = 0
        if (currentIndex >= tabsModel.count) currentIndex = tabsModel.count - 1
    }

    function initializeWorkspaceDeferred() {
        if (tabsModel.count === 0)
            restorePersistentDraftTabs()

        var restoreUrl = calicatasSettingsM09.lastDocumentUrl
        var restoreAbs = restoreUrl && restoreUrl.length ? _fileUrlToAbs(restoreUrl) : ""
        var canRestore = restoreUrl && restoreUrl.length
                && (!FS.exists || FS.exists(restoreAbs))
        if (tabsModel.count === 0 && canRestore) {
            createScratchTab()
            if (currentTab) _pushHistory(currentTab.tid)
            var restoreTid = currentTab ? currentTab.tid : -1
            var restoreDocId = _docInstanceId(currentDoc)
            if (!root.applyPickedFile(restoreUrl))
                root.workspaceStatusText = "No se pudo restaurar la ficha anterior"
            else root.workspaceStatusText = "Ficha recuperada"

        } else if (tabsModel.count === 0) {
            createInitialScratchTab()
            if (currentTab) _pushHistory(currentTab.tid)
        }
        ensureAtLeastOneTab()
        _syncDocsList()
        _formLoaderReady = true
        initializationComplete = true
        if (root.foregroundOperation && root.foregroundOperation.kind === "APP_INIT")
            root.endOperation(root.foregroundOperation.id, "OK")
        if (root._pendingCloudOpen) {
            var request = root._pendingCloudOpen
            root._pendingCloudOpen = null
            root.openCloudCalicata(request.projectId, request.calicataId)
        }
        if (root._pendingExcelImport) {
            var excel = root._pendingExcelImport
            root._pendingExcelImport = null
            root.importCalicataExcel(excel.path, excel.source)
        }
    }

    // Abrir con Calicatas (.xlsx): lectura segura en C++ → detector/adapters/
    // validador (lib/CalicataExcelImport.js) → borrador real en una pestaña
    // nueva del editor existente (General, estratos, fotos, autosave, sync y
    // exportación como una ficha creada a mano). El Excel origen no se toca y
    // la carpeta de origen nunca alimenta el nombre del proyecto.
    function importCalicataExcel(localPath, source) {
        if (root.leaving) return
        source = source || {}
        if (!root.initializationComplete) {
            root._pendingExcelImport = { path: String(localPath), source: source }
            return
        }
        var raw = ExcelExporter.readWorkbookCells(String(localPath))
        var result = ExcelImport.importWorkbook(raw, source)
        console.info("INGE_CALICATA_EXCEL_IMPORT status=" + result.status + " adapter=" + (result.adapter || "")
                     + " warnings=" + ((result.report && result.report.warnings) || []).length)
        if (result.status !== ExcelImport.STATUS_OK) {
            root.showMsg("No se pudo abrir con Calicatas",
                         result.status === ExcelImport.STATUS_FAILED ? result.message : ExcelImport.NOT_RECOGNIZED_MESSAGE)
            return
        }
        // Mismo archivo (hash/id) ya importado en una ficha abierta: no se duplica.
        for (var i = 0; i < tabsModel.count; ++i) {
            var open = root._docAt(i)
            var meta = open && open.header ? (open.header.import_source || {}) : {}
            if ((result.source.sourceHash && meta.sourceHash === result.source.sourceHash)
                    || (result.source.sourceFileId && meta.sourceFileId === result.source.sourceFileId)) {
                root.selectTab(i)
                root.showMsg("Ficha ya importada", "Este Excel ya está abierto como ficha. Se mostró la existente para no duplicarla.")
                return
            }
        }
        if (root.addNewTab() === false) return
        var doc = root.currentDoc
        if (!doc) return
        doc.header = Object.assign({}, doc.header || {}, result.state.header)
        doc.cortes = result.state.cortes
        doc.observaciones = result.state.observaciones
        doc.timestamp = Object.assign({}, doc.timestamp || {}, result.state.timestamp)
        if (formLoader.item && formLoader.item.importFromDoc) formLoader.item.importFromDoc()
        root._syncTabFromDoc(root.currentIndex)
        if (!doc.saveDraft())
            console.warn("INGE_CALICATA_EXCEL_IMPORT draft_not_saved " + doc.errorString)
        var notes = (result.report.warnings || []).slice(0, 4)
        root.showMsg("Ficha importada",
                     "Revisa los datos antes de guardar o exportar."
                     + (notes.length ? "\n\n• " + notes.join("\n• ") : ""))
    }

    function isCloseLocked(i) {
        return false
    }

    function addNewTab(titleOpt) {
        if (formLoader.item && !formLoader.item.commitPendingField()) return false
        if (currentDoc && !autoSaveCurrentM09(true)) return false
        var doc = _newDoc()
        var docId = _docInstanceId(doc)
        var tid = tabIdCounter++
        if (!doc || !docId.length) {
            console.error("[InGe+ M09] no se pudo crear documento para tid=" + tid)
            return
        }
        _appendDoc(doc)

        tabsModel.append({
            tid: tid,
            docId: docId,
            title: _newUntitledTitle(),
            fileUrl: "",
            openKey: "",
            dirty: false,
            conflict: false,
            isScratch: true,
            demoSeeded: false,
            selected: false,
            thumbUrl: ""          // ✅
        })
        selectTab(tabsModel.count - 1)
        _syncTabFromDoc(currentIndex)
        console.info("[InGe+ M09] create tab tid=" + tid + " instanceId=" + docId)
    }

    function _closeTabNow(i) {
        if (_closeOperationActive || i < 0 || i >= tabsModel.count) return
        var tab = tabsModel.get(i)
        if (!tab) return
        _closeTabsByTids([tab.tid])
    }

    function tryCloseTab(i) {
        if (_closeOperationActive || i < 0 || i >= tabsModel.count) return
        if (isCloseLocked(i)) return

        var tab = tabsModel.get(i)
        if (!tab) return

        if (i === currentIndex && !autoSaveCurrentM09(true)) return
        tab = tabsModel.get(i)
        if (!tab) return

        if (!tab.dirty) {
            _closeTabsByTids([tab.tid])
            return
        }

        _pendingCloseTid = tab.tid
        confirmCloseTab.open()
    }

    function markDirty(isDirty) {
        if (!currentTab) return
        tabsModel.setProperty(currentIndex, "dirty", !!isDirty)

        var d = _docAt(currentIndex)
        if (d && d.setDirty)
            d.setDirty(!!isDirty)
        else if (d)
            console.warn("[InGe+ M09] documento sin contrato setDirty instanceId="
                         + _docInstanceId(d))
    }

    function applyPickedFile(filePathOrUrl) {
        if (!filePathOrUrl) return false
        if (formLoader.item && !formLoader.item.commitPendingField()) return false

        var urlStr = _toFileUrl(filePathOrUrl)
        if (!urlStr.length) return false
        var key = _openKeyFromUrl(urlStr)

        var existing = _findTabByKey(key)
        if (existing >= 0) { root.selectTab(existing); return true }

        ensureAtLeastOneTab()
        _syncDocsList()

        // abre en el tab actual (o crea uno nuevo si el actual ya tiene contenido)
        if (root.currentTab && (root.currentTab.dirty || (root.currentTab.fileUrl && root.currentTab.fileUrl.length))) {
            root.addNewTab()
        }

        var doc = _docAt(currentIndex)
        if (!doc) return false

        var ok = doc.load(Qt.resolvedUrl(urlStr))
        if (!ok) return false
        var loadedDocId = _docInstanceId(doc)
        if (!loadedDocId.length) return false
        tabsModel.setProperty(currentIndex, "docId", loadedDocId)

        // doc -> UI
        if (formLoader.item && formLoader.item.importState) {
            formLoader.item.importState({
                header: doc.header,
                uiState: doc.uiState,
                cortes: doc.cortes,
                observaciones: doc.observaciones,
                timestamp: doc.timestamp,
                images: doc.images
            })
        }

        _syncTabFromDoc(currentIndex)
        tabsModel.setProperty(currentIndex, "demoSeeded", false)
        return true
    }

    function _stemForSaveAs(doc) {
        var h = doc ? doc.header : null
        var code = h && (h.codigo || h.calicata || h.pk || h.progresiva)
                ? (h.codigo || h.calicata || h.pk || h.progresiva) : ""
        code = (code || "").toString().trim()
        return code.length ? code : "calicata"
    }

    function _syncFormIntoDoc(doc, forSave) {
        if (!doc || doc.closed === true || !formLoader.item || !formLoader.item.exportState)
            return false
        if (doc.applyingCloudState || root._remoteLoadingDocId.length || root.formValue(formLoader.item, "_loading")) return true
        var targetDocId = _docInstanceId(doc)
        var formDocId = formLoader.item._docInstanceId
                ? formLoader.item._docInstanceId(formLoader.item.doc) : ""
        if (!targetDocId.length || formDocId !== targetDocId) {
            console.error("[InGe+ M09] snapshot rechazado por documento no activo"
                          + " target=" + targetDocId + " form=" + formDocId)
            return false
        }
        if (forSave && formLoader.item.commitPendingField && !formLoader.item.commitPendingField()) return false
        // Presentation defaults and derived lab fields are not user edits.
        if (!root.formValue(formLoader.item, "dirty") && !doc.dirty) return true
        var st = formLoader.item.exportState(!!forSave)
        if (!st) return false

        var wasSyncing = formLoader.item._syncingDocument
        formLoader.item._syncingDocument = true
        try {
        // Solo escribir si cambió (evita “dirty fantasma”)
        if (st.header !== undefined && !_deepEqual(st.header, doc.header)) doc.header = st.header
        if (st.uiState !== undefined && !_deepEqual(st.uiState, doc.uiState)) doc.uiState = st.uiState
        if (st.cortes !== undefined && !_deepEqual(st.cortes, doc.cortes)) doc.cortes = st.cortes
        if (st.observaciones !== undefined && st.observaciones !== doc.observaciones) doc.observaciones = st.observaciones
        if (st.timestamp !== undefined && !_deepEqual(st.timestamp, doc.timestamp)) doc.timestamp = st.timestamp
        if (st.images !== undefined && !_deepEqual(st.images, doc.images)) doc.images = st.images
        } finally { formLoader.item._syncingDocument = wasSyncing }

        return true
    }

    function _resumeQueuedSave(documentId) {
        if (root._queuedSaveDocId !== documentId) return
        root._queuedSaveDocId = ""
        if (root._docInstanceId(root.currentDoc) !== documentId) return
        Qt.callLater(function() {
            if (root._docInstanceId(root.currentDoc) === documentId) root.doSave(false)
        })
    }

    function doSave(forceSaveAs) {
        if (root._savingCloudDocId.length) return
        if (!forceSaveAs && (root._autoSyncDocId.length || root._driveJsonBusy)) {
            root._queuedSaveDocId = root._docInstanceId(root.currentDoc)
            return
        }
        driveJsonAutosave.stop()
        var tab = currentTab
        if (!tab) return

        _syncDocsList()
        var doc = _docAt(currentIndex)
        if (!doc) return
        var saveTid = tab.tid
        var saveDocId = _docInstanceId(doc)
        if (String(tab.docId || "") !== saveDocId) {
            _mappingError("save start", currentIndex, tab.docId, saveDocId)
            return
        }
        _pendingSaveTid = saveTid
        _pendingSaveDocId = saveDocId
        console.info("[InGe+ M09] save start tid=" + saveTid
                     + " instanceId=" + saveDocId)

        if (!_syncFormIntoDoc(doc, true)) {
            _clearPendingSave()
            return
        }

        if (!forceSaveAs) {
            if (!String(doc.header.projectId || "").length) {
                _clearPendingSave()
                root.showMsg("Selecciona un proyecto", "Elige el proyecto online desde General. El borrador local se conserva.")
                return
            }
            if (!doc.saveDraft()) {
                _clearPendingSave()
                root.showMsg("No se pudo guardar el borrador", doc.errorString)
                return
            }
            var duplicateCode = root._workspaceCodeConflict(doc)
            if (duplicateCode.length) {
                _clearPendingSave()
                root.showMsg("Código duplicado", duplicateCode + "\nEl borrador local se conserva.")
                return
            }
            _finishReviewCorrectionAfterSave()
            root._savingCloudDocId = saveDocId
            root.workspaceStatusText = "Sincronizando datos de Calicatas con el servidor…"
            if (!CalicataCloud.syncDocument(doc)) {
                root._savingCloudDocId = ""
                _clearPendingSave()
                root.showMsg("No se pudo iniciar la sincronización", CalicataCloud.lastError)
                return
            }
            _syncTabFromDoc(currentIndex)
            return
        }

        var hasUrl = doc.fileUrl && doc.fileUrl.toString && doc.fileUrl.toString().length > 0

        // ✅ si ya tiene archivo y NO es SaveAs, valida mismatch
        if (!forceSaveAs && hasUrl) {
            var fileStem = _safeStem(_fileStemFromUrl(doc.fileUrl.toString()))
            var headStem = _headerStem(doc)

            if (headStem.length && fileStem.length && headStem !== fileStem) {
                var oldAbs = _fileUrlToAbs(doc.fileUrl.toString()).replace(/\\/g,"/")
                var p = oldAbs.lastIndexOf("/")
                _mismatch_oldAbs = oldAbs
                _mismatch_folderAbs = (p >= 0) ? oldAbs.substring(0, p) : ""
                _mismatch_fileStem = fileStem
                _mismatch_headerStem = headStem
                nameMismatchPopup.open()
                return
            }
        }

        if (forceSaveAs || !hasUrl) {
            var editDir = FS.join(docs.basePath, "Proyecto_Local/Calicata/Edit")
            FS.mkpath(editDir)
            calDlg.mode = "save"
            calDlg.initialDir = editDir
            calDlg.defaultFileName = _safeStem(_stemForSaveAs(doc))
            calDlg.open()
            return
        }

        if (!doc.save()) {
            console.warn("[InGe+ M09] save end ok=false tid=" + saveTid
                         + " instanceId=" + saveDocId)
            _clearPendingSave()
            root.showMsg("No se pudo guardar", "Falló el guardado del archivo.")
            return
        }
        _finishReviewCorrectionAfterSave()
        var savedIndex = _pendingSaveIndex()
        if (savedIndex >= 0)
            _syncTabFromDoc(savedIndex)
        console.info("[InGe+ M09] save end ok=true tid=" + saveTid
                     + " instanceId=" + saveDocId)
        _clearPendingSave()
        _notifySaved("Ficha guardada")
        _finishPendingCloseIfAny()
    }

    function _notifySaved(message) {
        workspaceStatusText = message || "Ficha guardada"
        saveConfirmation.restart()
        if (typeof saveIcon !== "undefined") saveIcon.pulse()
    }

    SequentialAnimation {
        id: saveConfirmation
        PropertyAction { target: root; property: "saveConfirmed"; value: true }
        PauseAnimation {
            duration: root.flow ? root.flow.successHoldDuration : 0
        }
        PropertyAction { target: root; property: "saveConfirmed"; value: false }
    }


    function _cloneM09(value) {
        try {
            return JSON.parse(JSON.stringify(value))
        } catch(e) {
            console.warn("[InGe+ M09] no se pudo clonar dato puro:", e)
            return undefined
        }
    }

    function duplicateCurrentTabM09() {
        if (!currentTab) return
        _syncDocsList()
        var src = _docAt(currentIndex)
        if (!src) return
        _syncFormIntoDoc(src, true)

        var srcTitle = currentTab.title || "Calicata"
        var clonedHeader = _cloneM09(src.header)
        var clonedUiState = _cloneM09(src.uiState)
        var clonedCortes = _cloneM09(src.cortes)
        var clonedTimestamp = _cloneM09(src.timestamp)
        var clonedImages = _cloneM09(src.images)
        if (clonedHeader === undefined
                || clonedUiState === undefined
                || clonedCortes === undefined
                || clonedTimestamp === undefined
                || clonedImages === undefined) {
            return
        }
        addNewTab()
        var dst = _docAt(currentIndex)
        if (!dst) return

        dst.header = clonedHeader
        dst.uiState = clonedUiState
        dst.cortes = clonedCortes
        dst.observaciones = src.observaciones
        dst.timestamp = clonedTimestamp
        dst.images = clonedImages
        if (dst.copyPhotosFrom)
            dst.copyPhotosFrom(src)
        dst.setDirty(true)
        tabsModel.setProperty(currentIndex, "title", "Copia " + srcTitle)
        tabsModel.setProperty(currentIndex, "dirty", true)
        var dstTab = currentTab
        var dstTid = dstTab ? dstTab.tid : -1
        var dstDocId = _docInstanceId(dst)

        Qt.callLater(function() {
            var dstIndex = root._indexForTid(dstTid)
            var liveDoc = root._docAt(dstIndex)
            if (dstIndex < 0
                    || dstIndex !== root.currentIndex
                    || root._docInstanceId(liveDoc) !== dstDocId) {
                return
            }
            if (formLoader.item && formLoader.item.importState) {
                formLoader.item.importState({
                    header: liveDoc.header,
                    uiState: liveDoc.uiState,
                    cortes: liveDoc.cortes,
                    observaciones: liveDoc.observaciones,
                    timestamp: liveDoc.timestamp,
                    images: liveDoc.images
                })
            }
        })
        workspaceStatusText = "Copia creada; guarda para asignar nombre definitivo"
    }

    function autoSaveCurrentM09(flushEditing) {
        if (root._remoteLoadingDocId.length || (root.currentDoc && root.currentDoc.applyingCloudState)) return true
        if (flushEditing && formLoader.item && formLoader.item.commitPendingField
                && !formLoader.item.commitPendingField()) return false
        var tab = currentTab
        if (!tab) return true
        _syncDocsList()
        var doc = _docAt(currentIndex)
        if (!doc) return false
        if (!_syncFormIntoDoc(doc, false)) return false
        if (root._isPlaceholderDoc(doc)) return true
        if (!doc.dirty && !tab.dirty) {
            root._queueAutoCloudSync(doc)   // reintento de un borrador PENDING
            return true
        }

        // P0: autosave nunca confirma ni renombra la ficha.
        // Solo persiste el draft asociado al UUID del documento.
        var ok = doc.saveDraft ? doc.saveDraft() : false
        if (ok) {
            _syncTabFromDoc(currentIndex)
            draftCheckpointDocId = _docInstanceId(doc)
            workspaceStatusText = "Guardado"
            console.info("INGE_CALICATA_AUTOSAVE_LOCAL docId=" + _docInstanceId(doc)
                         + " projectId=" + String(doc.header.projectId || ""))
            root._queueAutoCloudSync(doc)
        } else {
            workspaceStatusText = "Error de guardado: " + String(doc.errorString || "No se pudo guardar el borrador")
        }
        return ok
    }    function exportCurrentExcel(provider) {
        // Un tap lógico = un flujo. El guard vive en la entrada del comando.
        if (root.leaving) return
        if (root._exportFlowActive || root.exportBusy || root._exportPreparing || root._publishingDocId.length) {
            console.info("INGE_CALICATA_EXPORT_IGNORED_ALREADY_RUNNING")
            return
        }
        if (!root.currentTab) {
            root.showMsg("Sin ficha", "Abre o crea una ficha de calicata antes de exportar.")
            return
        }
        if (provider === undefined || provider === null || provider === "") {
            root.openAnchoredPopup(exportPopup, 344)
            return
        }
        if (provider !== "GOOGLE_DRIVE" && provider !== "SUPABASE") {
            root.showMsg("Destino no válido", "Elige Google Drive o InGeDrive.")
            return
        }
        // Bloqueo técnico transitorio (no por contenido): la ficha aún se hidrata.
        if (root._remoteLoadingDocId.length) {
            console.info("INGE_CALICATA_EXPORT_IGNORED_ALREADY_RUNNING reason=HYDRATING")
            return
        }
        if (!formLoader.item || !formLoader.item.exportExcelFlow) {
            root.showMsg("Exportación no disponible", "El formulario actual no expone exportExcelFlow().")
            return
        }
        // La revisión (BLOCKER/WARNING) es informativa: una calicata SIEMPRE
        // se puede exportar, incompleta o con observaciones.
        root._googleExportPath = ""
        root._exportFlowActive = true
        root._exportOperationId = root.beginOperation("EXPORT_XLSX", "Exportando Excel…", "Preparando datos…", { immediate: true })
        console.info("INGE_CALICATA_EXPORT_BEGIN format=XLSX")

        root._syncDocsList()
        var doc = root._docAt(root.currentIndex)
        if (doc) {
            root._syncFormIntoDoc(doc, true)
            if (!root.autoSaveCurrentM09(true)) {
                root._exportFlowActive = false
                root.endOperation(root._exportOperationId, "ERROR", { title: "No se pudo exportar",
                    detail: "Termina de corregir el campo en edición y vuelve a exportar.",
                    actions: [{ id: "close", label: "Cerrar" }] })
                return
            }
        }

        root._exportPreparing = true
        var exportTid = root.currentTab ? root.currentTab.tid : -1
        var exportDocId = root._docInstanceId(root.currentDoc)
        // Un frame para pintar el overlay antes de la generación síncrona.
        exportKickoff.task = function() {
            try {
            var exportIndex = root._indexForTid(exportTid)
            if (exportIndex < 0
                    || exportIndex !== root.currentIndex
                    || root._docInstanceId(root._docAt(exportIndex)) !== exportDocId
                    || !formLoader.item
                    || root._docInstanceId(formLoader.item.doc) !== exportDocId) {
                console.warn("[InGe+ M09] exportación cancelada: cambió la ficha destino")
                root._exportFlowActive = false
                root.endOperation(root._exportOperationId, "OK")
                return
            }
            root.phaseOperation(root._exportOperationId, "GENERATING", "Generando archivo Excel…")
            var out = ""
            try {
                out = formLoader.item.exportExcelFlow(provider)
            } catch(e) {
                console.warn("INGE_CALICATA_EXPORT_FAILED " + e)
                out = ""
            }
            if (!out || !String(out).length) {
                root._exportFlowActive = false
                // El motivo real (p. ej. qué foto o logo falta) llega al usuario.
                var reason = typeof ExcelExporter !== "undefined" ? String(ExcelExporter.lastError || "") : ""
                root.endOperation(root._exportOperationId, "ERROR", { title: "No se pudo crear el Excel",
                    detail: (reason.length ? reason : "Error técnico al generar el archivo.") + "\nLa ficha se conserva.",
                    actions: [{ id: "close", label: "Cerrar" }] })
                return
            }
            root._finishExcelExport(out, exportDocId)
            } catch (taskError) {
                // Cualquier excepción libera el flujo: un nuevo intento siempre es posible.
                console.warn("INGE_CALICATA_EXPORT_FAILED " + taskError)
                if (root._exportFlowActive) {
                    root._exportFlowActive = false
                    root.endOperation(root._exportOperationId, "ERROR", { title: "No se pudo crear el Excel",
                        detail: "Error técnico al generar el archivo.\nLa ficha se conserva.",
                        actions: [{ id: "close", label: "Cerrar" }] })
                }
            } finally {
                root._exportPreparing = false
            }
        }
        exportKickoff.restart()
    }

    // Única superficie de operaciones foreground de Calicatas.
    CalicataOperationOverlay {
        id: operationOverlay
        operation: root.foregroundOperation
        pageColor: root.darkMode ? Mobile.InGeCoreFlow.colors.ingemaDeep : "#FCFCFC"
        surfaceColor: root.darkMode ? Mobile.InGeCoreFlow.colors.ingemaNavy : "#FFFFFF"
        textColor: root.darkMode ? "#F6F6F7" : Mobile.InGeCoreFlow.colors.ingemaDeep
        mutedColor: root.darkMode ? Mobile.InGeCoreFlow.colors.ingemaPaperSecondary : Mobile.InGeCoreFlow.colors.ingemaInkSecondary
        accentColor: root.darkMode ? Mobile.InGeCoreFlow.colors.ingemaBlueTint : Mobile.InGeCoreFlow.colors.ingemaBlue
        borderColor: root.darkMode ? "#404F6C" : "#DFE2E6"
        onActionTriggered: function(actionId, op) { root._operationAction(actionId, op) }
    }
    Binding {
        target: formLoader.item
        property: "operationHost"
        value: root
        when: formLoader.item !== null && formLoader.item !== undefined
        restoreMode: Binding.RestoreNone
    }

    Timer {
        id: exportKickoff
        property var task: null
        interval: 32
        repeat: false
        onTriggered: { var t = task; task = null; if (t) t() }
    }

    // Export queues the private workbook; the user downloads/views it in InGeDrive.
    function _excelDrivePath(result, projectName, fileName) {
        var folder = String(result.remoteFolderPath || "")
        return projectName + " › " + (folder.length ? folder.split("/").join(" › ")
                                                    : "carpeta del JSON › exports") + " › " + fileName
    }
    function _finishExcelExport(out, exportDocId) {
        var result = ExcelExporter.lastExportResult || {}
        if (result.provider === "GOOGLE_DRIVE") {
            root.lastExcelPath = out
            root._googleExportPath = out
            root._refreshGoogleExcelExport()
            return
        }
        var doc = root._docAt(root._indexForDocId(exportDocId))
        var fileName = String(out).replace(/\\/g, "/").split("/").pop()
        var remote = String(result.remoteLogicalPath || "")
        var projectId = doc ? String(doc.header.projectId || "") : ""
        // Ruta de destino: espacio de guardado (projectName), nunca el nombre contractual.
        var projectName = doc ? String(doc.header.projectName || "Proyecto") : "Proyecto"
        console.info("INGE_CALICATA_EXPORT_GENERATED localPhysicalPath=" + out + " remoteLogicalPath=" + remote)
        root.lastExcelPath = out
        var queued = false
        if (projectId.length && doc) {
            root.phaseOperation(root._exportOperationId, "QUEUING", "Publicando en InGeDrive…")
            root._publishingDocId = exportDocId
            root._pendingCloudXlsxPath = out
            root._pendingExportLogDocId = exportDocId
            root._pendingExportFileName = fileName
            // Sincroniza la ficha y publica (onSyncSucceeded). Sin red, se
            // encola la publicación igual (cola persistente de exportación).
            if (!CalicataCloud.syncDocument(doc, "export")) {
                root._publishingDocId = ""
                root._pendingCloudXlsxPath = ""
                queued = ExcelExporter.publishCalicata(doc.portableState(String(root.docs && root.docs.basePath || "")), out)
            } else {
                queued = true
            }
            if (queued) console.info("INGE_CALICATA_EXPORT_QUEUED")
        }
        var drivePath = root._excelDrivePath(result, projectName, fileName)
        var syncState = String(result.syncState || "PENDING_SYNC")
        var synced = syncState === "SYNCED"
        var failed = syncState === "ERROR" || syncState === "CONFLICT"
        root._exportFlowActive = false
        root.endOperation(root._exportOperationId, failed ? "ERROR" : "SUCCESS", {
            title: failed ? "Excel pendiente de publicar" : synced ? "Excel guardado en InGeDrive"
                          : projectId.length ? "Excel encolado para InGeDrive" : "Excel generado localmente",
            detail: fileName + "\n\n" + (projectId.length
                    ? "InGeDrive: " + drivePath + "\nEstado: " + (synced ? "Sincronizado" : failed ? "Error de sincronización"
                                                                                                    : queued ? "Pendiente de sincronización" : "Solo en el dispositivo")
                      + "\nCuando esté sincronizado, descárgalo desde InGeDrive para verlo."
                    : "Selecciona un proyecto para publicarlo en InGeDrive.")
                    + (failed && result.error ? "\n" + String(result.error) : ""),
            actions: [{ id: "close", label: "Cerrar" }]
        })
    }
    function _refreshGoogleExcelExport() {
        if (!root._exportFlowActive || !root._googleExportPath) return
        var result = ExcelExporter.lastExportResult || {}
        if (result.provider !== "GOOGLE_DRIVE") return
        var state = String(result.syncState || "PENDING_SYNC")
        if ((state === "PENDING_SYNC" || state === "UPLOADING") && !result.awaitingRetry) {
            root.phaseOperation(root._exportOperationId, "QUEUING", "Autorizando y guardando Excel en Google Drive…")
            return
        }
        var confirmed = state === "SYNCED" && String(result.remoteId || "").length > 0
        root._exportFlowActive = false
        root.endOperation(root._exportOperationId, confirmed ? "SUCCESS" : "ERROR", {
            title: confirmed ? "Excel guardado en Google Drive" : "Excel pendiente de subir",
            detail: String(result.fileName || "Excel") + "\nGoogle Drive › 01_CALICATAS"
                    + (confirmed ? "" : "\n" + String(result.error || "No se confirmó la subida del archivo.")
                                      + "\nEl Excel se conserva para reintentar."),
            retry: function() { root._retryGoogleExcelExport() },
            actions: confirmed ? [{ id: "close", label: "Cerrar" }]
                               : [{ id: "retry", label: "Reintentar" }, { id: "close", label: "Cerrar" }]
        })
    }
    function _retryGoogleExcelExport() {
        if (root._exportFlowActive || !root._googleExportPath) return
        root._exportFlowActive = true
        root._exportOperationId = root.beginOperation("EXPORT_XLSX", "Guardando Excel…", "Reintentando Google Drive…", { immediate: true })
        ExcelExporter.retryPendingExports()
    }
    function snapshotTab(i) {
        if (i < 0 || i >= tabsModel.count) return
        if (i !== currentIndex) {
            console.warn("[InGe+ M09] snapshot ignorado para pestaña no visible tid="
                         + tabsModel.get(i).tid)
            return
        }
        if (!formLoader.item) return

        _syncDocsList()
        var doc = _docAt(i)
        if (!doc) return

        _syncFormIntoDoc(doc, false)
        _syncTabFromDoc(i)
    }

    function restoreTab(i) {
        if (i < 0 || i >= tabsModel.count) return
        if (i !== currentIndex) return
        if (!formLoader.item) return

        _syncDocsList()

        var t = tabsModel.get(i)
        if (!t) return
        var doc = _docAt(i)
        if (!doc) return
        if (String(t.docId || "") !== _docInstanceId(doc)
                || _docInstanceId(currentDoc) !== _docInstanceId(doc)) {
            _mappingError("restoreTab", i, t.docId, _docInstanceId(doc))
            return
        }

        var want = (t.fileUrl && t.fileUrl.length) ? t.fileUrl : ""
        var cur  = (doc.fileUrl && doc.fileUrl.toString) ? doc.fileUrl.toString() : ""

        if (want.length && cur !== want) {
            if (!doc.load(Qt.resolvedUrl(want))) return
            var loadedDocId = _docInstanceId(doc)
            if (!loadedDocId.length) return
            tabsModel.setProperty(i, "docId", loadedDocId)
        }

        if (formLoader.item.importState) {
            formLoader.item.importState({
                header: doc.header,
                uiState: doc.uiState,
                cortes: doc.cortes,
                observaciones: doc.observaciones,
                timestamp: doc.timestamp,
                images: doc.images
            })
        } else if (formLoader.item.resetForm) {
            formLoader.item.resetForm()
        }
    }
    function _toFileUrl(anyPathOrUrl) {
        var s = (anyPathOrUrl || "").toString().trim()
        if (!s.length) return ""

        if (s.indexOf("://") >= 0) return s  // ya es URL

        s = s.replace(/\\/g, "/")
        if (Qt.platform.os === "windows") {
            if (s.length >= 2 && s[1] === ":") return "file:///" + s
        }
        if (s[0] === "/") return "file://" + s
        return s
    }

    function _fileUrlToAbs(urlStr) {
        var u = (urlStr || "").toString()
        if (!u.length) return ""
        if (u.startsWith("file:///")) return decodeURIComponent(u.substring("file:///".length))
        if (u.startsWith("file://"))  return decodeURIComponent(u.substring("file://".length))
        return decodeURIComponent(u)
    }

    function _openKeyFromUrl(urlStr) {
        var abs = _fileUrlToAbs(urlStr).replace(/\\/g, "/")
        if (Qt.platform.os === "windows") abs = abs.toLowerCase()
        return abs
    }

    function _prettyTabPath(fileUrl) {
        if (!fileUrl || !fileUrl.length) return "Sin archivo (nuevo)"

        var abs = _fileUrlToAbs(fileUrl).replace(/\\/g, "/")
        abs = abs.replace(/\/+$/, "")

        var base = (docs && docs.basePath) ? ("" + docs.basePath) : ""
        base = base.replace(/\\/g, "/").replace(/\/+$/, "")

        var absCmp = abs
        var baseCmp = base
        if (Qt.platform.os === "windows") {
            absCmp = absCmp.toLowerCase()
            baseCmp = baseCmp.toLowerCase()
        }

        if (baseCmp.length && absCmp.indexOf(baseCmp) === 0) {
            var rel = abs.substring(base.length)
            rel = rel.replace(/^\/+/, "")
            return rel.length ? rel : abs.split("/").pop()
        }

        // fallback: últimos 2-3 segmentos
        var parts = abs.split("/")
        return parts.slice(Math.max(0, parts.length - 3)).join("/")
    }

    function _fileNameFromUrl(fileUrl) {
        if (!fileUrl || !fileUrl.length) return ""
        var abs = _fileUrlToAbs(fileUrl).replace(/\\/g, "/").replace(/\/+$/, "")
        return abs.split("/").pop()
    }

    function _tabHeaderText(fileUrl, title, dirty) {
        var t = ""
        if (fileUrl && fileUrl.length) {
            t = _fileNameFromUrl(fileUrl)          // ✅ arriba: nombre real del archivo
        } else {
            t = (title && title.length) ? title : "Sin archivo (nuevo)"
        }
        if (dirty) t += " *"
        return t
    }

    function _tabFooterText(fileUrl) {
        if (!fileUrl || !fileUrl.length) return "Sin archivo (nuevo)"
        return _prettyTabPath(fileUrl)             // ✅ abajo: ruta relativa bonita
    }

    function _finishPendingCloseIfAny() {
        if (!_pendingCloseAfterSave) return

        var idx = _indexForTid(_pendingCloseTid)
        if (idx < 0) {
            _pendingCloseAfterSave = false
            _pendingCloseTid = -1
            return
        }

        var tab = tabsModel.get(idx)
        if (tab && !tab.dirty) {
            var tid = _pendingCloseTid
            _pendingCloseAfterSave = false
            _pendingCloseTid = -1
            Qt.callLater(function() { root._closeTabsByTids([tid]) })
        }
    }

    function _deepEqual(a, b) {
        if (a === b) return true
        if (a === null || b === null || a === undefined || b === undefined) return false
        if (typeof a !== typeof b) return false
        if (typeof a !== "object") return String(a) === String(b)

        var aa = Array.isArray(a), ab = Array.isArray(b)
        if (aa !== ab) return false
        if (aa) {
            if (a.length !== b.length) return false
            for (var i=0;i<a.length;i++) if (!_deepEqual(a[i], b[i])) return false
            return true
        }

        var ka = Object.keys(a).sort()
        var kb = Object.keys(b).sort()
        if (ka.length !== kb.length) return false
        for (var j=0;j<ka.length;j++) if (ka[j] !== kb[j]) return false
        for (var k=0;k<ka.length;k++) {
            var key = ka[k]
            if (!_deepEqual(a[key], b[key])) return false
        }
        return true
    }

    // ✅ Snapshot SOLO del tab que está visible (currentIndex)
    function snapshotCurrentTab() {
        captureThumb(currentIndex, false)
        if (currentIndex < 0 || currentIndex >= tabsModel.count) return
        if (!formLoader.item) return

        var t = tabsModel.get(currentIndex)
        if (!t) return
        if (formLoader.item.commitPendingField && !formLoader.item.commitPendingField()) return

        _syncDocsList()
        var doc = _docAt(currentIndex)
        if (!doc) return

        console.info("[InGe+ M09] snapshot tid=" + t.tid
                     + " instanceId=" + _docInstanceId(doc))
        _syncFormIntoDoc(doc, false)
        _syncTabFromDoc(currentIndex)
    }

    // ✅ Switch controlado: snapshot antes, luego cambias index, luego restore
    function selectTab(idx) {
        _backAtWorkspace = false
        if (idx === currentIndex) return
        if (idx < 0 || idx >= tabsModel.count) return

        var oldTab = currentTab
        var targetTab = tabsModel.get(idx)
        var oldTid = oldTab ? oldTab.tid : -1
        var targetTid = targetTab ? targetTab.tid : -1
        var targetDocId = targetTab ? String(targetTab.docId || "") : ""
        if (!targetTab
                || _docInstanceId(_docAt(idx)) !== targetDocId) {
            _mappingError("selectTab", idx, targetDocId,
                          _docInstanceId(_docAt(idx)))
            return
        }

        if (formLoader.item && !formLoader.item.commitPendingField()) return
        snapshotCurrentTab()      // captura el actual (última vista)

        // P0: cambiar de pestaña también es un punto transaccional de guardado.
        if (root.autoSaveEnabled && oldTab && !root.autoSaveCurrentM09(true)) return

        currentIndex = idx
        console.info("[InGe+ M09] switch " + oldTid + " -> " + targetTid)
        ensureAtLeastOneTab()
        restoreTab(idx)
        root.playFormSwapV600(0.3)

        // ✅ si ese tab no tiene thumb todavía, forzar preview “arriba”
        Qt.callLater(function(){
            var liveIndex = root._indexForTid(targetTid)
            if (liveIndex < 0
                    || root._docInstanceId(root._docAt(liveIndex)) !== targetDocId)
                return
            var t = tabsModel.get(liveIndex)
            var noThumb = !(t.thumbUrl && t.thumbUrl.length)
            root.captureThumb(liveIndex, noThumb)
        })

        if (currentTab) _pushHistory(currentTab.tid)
        _prevIndex = currentIndex
    }

    // Cambio de documento: operación local, sin loader; solo continuidad visual.
    function playFormSwapV600(fromOpacity) {
        formSwapAnimV600.stop()
        if (!root.flow || !root.flow.motionAllowed) {
            formLoader.opacity = 1.0
            return
        }
        formLoader.opacity = fromOpacity
        formSwapAnimV600.duration = fromOpacity < 0.1 ? 180 : 160
        formSwapAnimV600.start()
    }
    OpacityAnimator {
        id: formSwapAnimV600
        target: formLoader
        to: 1.0
        duration: 160
        easing.type: Easing.OutCubic
    }

    function showMsg(t, m) {
        msgTitle.text = t
        msgBody.text = m
        msgPopup.open()
    }

    CalPopup {
        id: msgPopup
        width: Math.min(root.width - root.__dp(48), root.__dp(400))
        x: (root.width - width) / 2
        baseY: (root.height - height) / 2
        padding: root.__dp(20)

        contentItem: ColumnLayout {
            spacing: root.__dp(8)

            Label {
                id: msgTitle
                Layout.fillWidth: true
                font.bold: true
                font.pixelSize: root.__sp(17)
                color: root.calTextColor()
                wrapMode: Text.WordWrap
            }
            Label {
                id: msgBody
                Layout.fillWidth: true
                wrapMode: Text.WrapAnywhere   // ✅ parte rutas largas
                font.pixelSize: root.__sp(14)
                color: root.calMutedColor()
            }

            CalButton {
                Layout.topMargin: root.__dp(8)
                Layout.alignment: Qt.AlignRight
                Layout.preferredWidth: root.__dp(104)
                tone: "primary"
                text: "OK"
                onClicked: msgPopup.close()
            }
        }
    }

    // ===== INFORMACIÓN DE LA CALICATA · peek invocado por el Dock =====
    // Centre of a capsule slot of the Dock (GlobalContextDock geometry:
    // sidePadding 10, slot 46, gap 8, core 49 + coreGap 16, group centred).
    function _dockSlotCenterX(slot, count, width) {
        var main = 20 + count * 46 + Math.max(0, count - 1) * 8
        return (width - (main + 16 + 49)) / 2 + 10 + slot * 54 + 23
    }
    readonly property Item _peekBackdropSource: ApplicationWindow.contentItem ? ApplicationWindow.contentItem : root
    function _peekText(value) { return value && String(value).length ? String(value) : "—" }
    function _peekHero(name) { return IconCatalog.heroiconSvg(name, 1.5) }
    function _statusTone(status) {
        var d = root.darkMode
        switch (String(status || "")) {
        case "BORRADOR": return d ? {bg: "#3A2A16", fg: "#FFC58A", dot: "#FF9F43"} : {bg: "#FCE8CC", fg: "#C2580A", dot: "#F07C12"}
        case "EN_REVISION": return d ? {bg: "#102B52", fg: Mobile.InGeCoreFlow.colors.ingemaBlueTint, dot: Mobile.InGeCoreFlow.colors.ingemaBlueTint} : {bg: Mobile.InGeCoreFlow.colors.blue100, fg: Mobile.InGeCoreFlow.colors.ingemaBlue, dot: Mobile.InGeCoreFlow.colors.ingemaBlue}
        case "OBSERVADO": return d ? {bg: "#3D1C1A", fg: "#FFB4AB", dot: "#FF6B5E"} : {bg: "#FBE2DF", fg: "#B42318", dot: "#E0442F"}
        case "REVISADO":
        case "APROBADO": return d ? {bg: "#24302D", fg: Mobile.InGeCoreFlow.colors.ingemaGreenTint, dot: Mobile.InGeCoreFlow.colors.ingemaGreenTint} : {bg: Mobile.InGeCoreFlow.colors.ingemaGreenWash, fg: Mobile.InGeCoreFlow.colors.ingemaGreen, dot: Mobile.InGeCoreFlow.colors.ingemaGreen}
        case "EXPORTADO": return d ? {bg: "#2A3A5A", fg: Mobile.InGeCoreFlow.colors.ingemaPaperSecondary, dot: Mobile.InGeCoreFlow.colors.ingemaPaperTertiary} : {bg: "#E8EAEE", fg: Mobile.InGeCoreFlow.colors.ingemaNavy, dot: Mobile.InGeCoreFlow.colors.ingemaNavy}
        default: return d ? {bg: "#262C34", fg: "#C9D1DB", dot: "#8B96A5"} : {bg: "#E8EBEF", fg: "#4B5563", dot: "#8B96A5"}
        }
    }
    function _syncTone(state) {
        var d = root.darkMode
        switch (String(state || "")) {
        case "SYNCED": return d ? {bg: "#24302D", fg: Mobile.InGeCoreFlow.colors.ingemaGreenTint} : {bg: Mobile.InGeCoreFlow.colors.ingemaGreenWash, fg: Mobile.InGeCoreFlow.colors.ingemaGreen}
        case "PENDING": return d ? {bg: "#3A2A16", fg: "#FFC58A"} : {bg: "#FCE8CC", fg: "#C2580A"}
        case "CONFLICT": return d ? {bg: "#3D1C1A", fg: "#FFB4AB"} : {bg: "#FBE2DF", fg: "#B42318"}
        default: return d ? {bg: "#102B52", fg: Mobile.InGeCoreFlow.colors.ingemaBlueTint} : {bg: Mobile.InGeCoreFlow.colors.blue100, fg: Mobile.InGeCoreFlow.colors.ingemaBlue}
        }
    }
    readonly property var calicataInfoRows: [
        {label: "Código", value: root.calicataInfo.code, kind: "text"},
        {label: "Proyecto", value: root.calicataInfo.project, kind: "text"},
        {label: "Estado", value: root.calicataInfo.statusLabel, kind: "status"},
        {label: "Sincronización", value: root.calicataInfo.syncLabel, kind: "sync"},
        {label: "ID local", value: root.calicataInfo.localId, kind: "id"},
        {label: "ID de calicata (nube)", value: root.calicataInfo.remoteId, kind: "text"},
        {label: "Creada", value: root.calicataInfo.createdAt, kind: "text"},
        {label: "Actualizada en servidor", value: root.calicataInfo.updatedAt, kind: "text"},
        {label: "Versión", value: root.calicataInfo.version, kind: "text"}
    ]
    function copyCalicataLocalId() {
        var id = String(root.calicataInfo.localId || "")
        if (!id.length) return
        infoClipboard.text = id
        infoClipboard.selectAll()
        infoClipboard.copy()
        infoClipboard.deselect()
        if (root.flow && typeof root.flow.triggerHaptic === "function")
            root.flow.triggerHaptic("light")
        infoToast.show()
    }
    TextEdit { id: infoClipboard; visible: false }

    Popup {
        id: infoPeek
        parent: Overlay.overlay
        x: 0
        y: 0
        width: parent ? parent.width : root.width
        height: parent ? parent.height : root.height
        padding: 0
        modal: true
        dim: false
        focus: true
        closePolicy: Popup.CloseOnEscape
        background: Item {}

        // Motion state driven only by enter/exit. originX: Dock slot centre.
        property real originX: width / 2
        property real reveal: 0
        property real panelOpacity: 0
        property real panelScale: 0.9
        property real panelShift: 22
        readonly property bool motion: !root.flow || root.flow.motionAllowed !== false
        readonly property bool dark: root.darkMode
        readonly property color labelColor: dark ? Mobile.InGeCoreFlow.colors.ingemaPaperSecondary : Mobile.InGeCoreFlow.colors.ingemaInkSecondary
        readonly property color valueColor: dark ? "#F6F6F7" : Mobile.InGeCoreFlow.colors.ingemaDeep
        readonly property color hairline: dark ? Qt.rgba(1, 1, 1, 0.08) : Qt.rgba(0.0824, 0.102, 0.1882, 0.09)

        onAboutToShow: {
            if (root.flow && typeof root.flow.triggerHaptic === "function")
                root.flow.triggerHaptic("medium")
            console.info("INGE_CALICATA_INFO_PEEK open")
            console.info("INGE_CALICATA_INFO_PEEK_TRANSITION phase=open-start")
        }
        onOpened: console.info("INGE_CALICATA_INFO_PEEK_TRANSITION phase=open-end")
        onAboutToHide: console.info("INGE_CALICATA_INFO_PEEK_TRANSITION phase=close-start")

        // Only opacity/scale/translation animate; blur, taps and shadow stay
        // fixed. Leading pauses absorb the first-frame cost (backdrop grab,
        // effect creation) so the motion is never skipped. Reduced motion: fade.
        enter: Transition {
            ParallelAnimation {
                SequentialAnimation {
                    PauseAnimation { duration: infoPeek.motion ? 40 : 0 }
                    NumberAnimation { property: "reveal"; from: 0; to: 1; duration: infoPeek.motion ? 110 : 120; easing.type: Easing.OutCubic }
                }
                SequentialAnimation {
                    PauseAnimation { duration: infoPeek.motion ? 50 : 0 }
                    ParallelAnimation {
                        NumberAnimation { property: "panelOpacity"; from: 0; to: 1; duration: infoPeek.motion ? 140 : 120; easing.type: Easing.OutCubic }
                        NumberAnimation { property: "panelScale"; from: infoPeek.motion ? 0.96 : 1; to: 1; duration: infoPeek.motion ? 210 : 0; easing.type: Easing.OutQuart }
                        NumberAnimation { property: "panelShift"; from: infoPeek.motion ? 12 : 0; to: 0; duration: infoPeek.motion ? 210 : 0; easing.type: Easing.OutQuart }
                    }
                }
            }
        }
        exit: Transition {
            ParallelAnimation {
                NumberAnimation { property: "reveal"; to: 0; duration: infoPeek.motion ? 150 : 120; easing.type: Easing.OutCubic }
                NumberAnimation { property: "panelOpacity"; to: 0; duration: infoPeek.motion ? 130 : 120; easing.type: Easing.InOutQuad }
                NumberAnimation { property: "panelScale"; to: infoPeek.motion ? 0.978 : 1; duration: infoPeek.motion ? 150 : 0; easing.type: Easing.OutCubic }
                NumberAnimation { property: "panelShift"; to: infoPeek.motion ? 6 : 0; duration: infoPeek.motion ? 150 : 0; easing.type: Easing.OutCubic }
            }
        }

        // Material tokens consumed by the Dock's GlassSurface/liquidglass.frag.
        QtObject {
            id: peekGlassTokens
            readonly property bool shown: infoPeek.visible
            readonly property Item glassBackdrop: infoPeek.visible ? root._peekBackdropSource : null
            // Static: the panel grabs its backdrop once, not per animation frame.
            readonly property real materialPosition: 0
            readonly property bool lowCostGlass: Mobile.InGeCoreFlow.lowMemoryMode
                || Mobile.InGeCoreFlow.performance.profile >= Mobile.InGeCoreFlow.performance.safe
            // Same material as the Dock's first 3D Touch menu (Dock tokens,
            // near-zero tint); legibility comes from one light veil, not tint.
            readonly property color glassTint: infoPeek.dark ? Qt.rgba(0.0824, 0.102, 0.1882, 0.10) : Qt.rgba(0.95, 0.97, 1.0, 0.02)
            readonly property color fallbackGlass: infoPeek.dark ? Qt.rgba(0.30, 0.33, 0.38, 0.18) : Qt.rgba(0.97, 0.98, 1.0, 0.14)
            readonly property real rimLight: infoPeek.dark ? 0.18 : 0.20
            readonly property real rimShade: infoPeek.dark ? 0.04 : 0.035
            readonly property real rimSheen: infoPeek.dark ? 0.03 : 0.015
            readonly property real edgeContrast: infoPeek.dark ? 0.0 : 0.03
            readonly property real glassSaturation: 1.12
            readonly property color shadowColor: Qt.rgba(0.0824, 0.102, 0.1882, infoPeek.dark ? 0.22 : 0.10)
        }

        contentItem: Item {
            // Real blur of the live content behind the popup (form, header,
            // Dock) plus a light dim; both follow `reveal`. ApplicationWindow's
            // contentItem is a sibling of Overlay.overlay, so the capture never
            // includes this popup. Created only while the peek is visible.
            Loader {
                anchors.fill: parent
                active: infoPeek.visible
                // One frozen grab at 0.5x (it is blurred anyway), blurred once
                // with fixed parameters; released when the popup is hidden.
                sourceComponent: Item {
                    ShaderEffectSource {
                        id: peekBackdropCapture
                        anchors.fill: parent
                        sourceItem: root._peekBackdropSource
                        textureSize: Qt.size(Math.max(1, Math.round(width * 0.5)),
                                             Math.max(1, Math.round(height * 0.5)))
                        live: false
                        hideSource: false
                        visible: false
                        Component.onCompleted: {
                            scheduleUpdate()
                            console.info("INGE_CALICATA_INFO_PEEK_TRANSITION phase=backdrop-grab snapshotSize="
                                         + textureSize.width + "x" + textureSize.height)
                        }
                    }
                    MultiEffect {
                        anchors.fill: parent
                        source: peekBackdropCapture
                        visible: infoPeek.reveal > 0
                        autoPaddingEnabled: false
                        blurEnabled: true
                        blurMax: 16
                        blur: 0.26
                        saturation: -0.04
                        opacity: infoPeek.reveal
                    }
                }
            }
            Rectangle {
                anchors.fill: parent
                color: infoPeek.dark ? Mobile.InGeCoreFlow.colors.ingemaDeepShade : Mobile.InGeCoreFlow.colors.ingemaDeep
                opacity: (infoPeek.dark ? 0.22 : 0.10) * infoPeek.reveal
            }
            // Tap outside the panel closes; the form and Dock stay inert.
            MouseArea {
                anchors.fill: parent
                enabled: infoPeek.opened
                onClicked: infoPeek.close()
            }

            Item {
                id: peekPanel
                readonly property real sideMargin: root.__dp(22)
                readonly property real topLimit: root.__dp(40)
                readonly property real bottomLimit: root.__dp(92)
                readonly property real headerHeight: root.__dp(70)
                readonly property real bottomPad: root.__dp(12)
                readonly property real maxHeight: Math.max(root.__dp(240), parent.height - topLimit - bottomLimit)
                width: Math.min(parent.width - 2 * sideMargin, root.__dp(440))
                height: Math.min(headerHeight + peekBody.implicitHeight + bottomPad, maxHeight)
                x: Math.round((parent.width - width) / 2)
                y: Math.round(Math.max(topLimit, Math.min(parent.height - bottomLimit - height,
                                                          (parent.height - height) / 2 + root.__dp(12))))
                opacity: infoPeek.panelOpacity
                transform: [
                    Scale {
                        origin.x: infoPeek.originX - peekPanel.x
                        origin.y: peekPanel.height
                        xScale: infoPeek.panelScale
                        yScale: infoPeek.panelScale
                    },
                    Translate { y: infoPeek.panelShift }
                ]

                MouseArea { anchors.fill: parent }   // swallow taps on the glass

                FlowCore.LiquidGlassSurface {
                    anchors.fill: parent
                    tokens: peekGlassTokens
                    cornerRadius: root.__dp(30)
                    surfaceName: "calicata-info"
                    // Balanced preset for the peek only (Dock keeps its defaults).
                    lens: 0.3
                    frost: 8
                    frostTaps: 6
                    magnify: 0
                    bevel: root.__dp(14)
                    elevation: true
                    liveCapture: false
                    // Final (untransformed) panel rect: one stable grab while
                    // scale/translate animate.
                    captureRect: Qt.rect(peekPanel.x, peekPanel.y, peekPanel.width, peekPanel.height)
                }
                // Legibility veil, same values as the Dock menu, plus a
                // near-invisible hairline edge.
                Rectangle {
                    anchors.fill: parent
                    radius: root.__dp(30)
                    color: infoPeek.dark ? Qt.rgba(0.0824, 0.102, 0.1882, 0.30) : Qt.rgba(0.98, 0.99, 1.0, 0.42)
                    border.width: 1
                    border.color: infoPeek.dark ? Qt.rgba(1, 1, 1, 0.06) : Qt.rgba(1, 1, 1, 0.30)
                }
                Rectangle {
                    anchors.horizontalCenter: parent.horizontalCenter
                    y: root.__dp(9)
                    width: root.__dp(34)
                    height: root.__dp(4)
                    radius: height / 2
                    color: infoPeek.dark ? Qt.rgba(1, 1, 1, 0.22) : Qt.rgba(0.20, 0.25, 0.32, 0.26)
                }

                // Header: document tile · title · circular close.
                Item {
                    id: peekHeader
                    x: root.__dp(16)
                    y: root.__dp(20)
                    width: parent.width - root.__dp(32)
                    height: root.__dp(40)
                    Rectangle {
                        id: peekDocTile
                        width: root.__dp(40)
                        height: width
                        radius: root.__dp(14)
                        anchors.verticalCenter: parent.verticalCenter
                        color: infoPeek.dark ? Qt.rgba(0.42, 0.58, 0.95, 0.16) : Qt.rgba(0.42, 0.58, 0.95, 0.14)
                        Components.FlowIcon {
                            anchors.centerIn: parent
                            width: root.__dp(22)
                            height: width
                            name: "documents.file"
                            sourceOverride: root._peekHero("document")
                            pulseOnActive: false
                            inactiveOpacity: 1
                            tintColor: infoPeek.valueColor
                        }
                    }
                    Label {
                        anchors.left: peekDocTile.right
                        anchors.leftMargin: root.__dp(14)
                        anchors.right: peekClose.left
                        anchors.rightMargin: root.__dp(10)
                        anchors.verticalCenter: parent.verticalCenter
                        text: "Información de la calicata"
                        font.pixelSize: root.__sp(17)
                        font.weight: Font.Bold
                        color: infoPeek.valueColor
                        fontSizeMode: Text.HorizontalFit
                        minimumPixelSize: 12
                        elide: Text.ElideRight
                    }
                    Rectangle {
                        id: peekClose
                        width: root.__dp(40)
                        height: width
                        radius: width / 2
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        color: infoPeek.dark ? Qt.rgba(1, 1, 1, closeTap.pressed ? 0.14 : 0.05)
                                             : Qt.rgba(1, 1, 1, closeTap.pressed ? 0.55 : 0.30)
                        border.width: 1
                        border.color: infoPeek.dark ? Qt.rgba(1, 1, 1, 0.12) : Qt.rgba(0.0824, 0.102, 0.1882, 0.07)
                        scale: closeTap.pressed ? 0.94 : 1.0
                        Behavior on scale { NumberAnimation { duration: 90; easing.type: Easing.OutQuad } }
                        Components.FlowIcon {
                            anchors.centerIn: parent
                            width: root.__dp(20)
                            height: width
                            name: "system.close"
                            sourceOverride: root._peekHero("x-mark")
                            pulseOnActive: false
                            inactiveOpacity: 1
                            tintColor: infoPeek.valueColor
                        }
                        MouseArea {
                            id: closeTap
                            anchors.fill: parent
                            anchors.margins: -root.__dp(6)
                            onClicked: infoPeek.close()
                        }
                        Accessible.role: Accessible.Button
                        Accessible.name: "Cerrar"
                    }
                }

                Flickable {
                    id: peekScroll
                    x: root.__dp(8)
                    y: peekPanel.headerHeight
                    width: parent.width - root.__dp(16)
                    height: parent.height - peekPanel.headerHeight - peekPanel.bottomPad
                    contentWidth: width
                    contentHeight: peekBody.implicitHeight
                    interactive: contentHeight > height + 1
                    boundsBehavior: Flickable.StopAtBounds
                    clip: true

                    Column {
                        id: peekBody
                        width: peekScroll.width
                        spacing: root.__dp(10)

                        Rectangle {
                            width: parent.width
                            height: peekRows.implicitHeight + root.__dp(8)
                            radius: root.__dp(22)
                            color: "transparent"

                            Column {
                                id: peekRows
                                x: root.__dp(12)
                                y: root.__dp(2)
                                width: parent.width - root.__dp(24)

                                Repeater {
                                    model: root.calicataInfoRows
                                    delegate: Item {
                                        id: infoRow
                                        required property var modelData
                                        readonly property string kind: String(modelData.kind)
                                        readonly property string value: String(modelData.value || "")
                                        readonly property real labelWidth: Math.round(width * 0.40)
                                        readonly property real contentH: Math.max(rowLabel.implicitHeight,
                                            infoRow.kind === "status" || infoRow.kind === "sync" ? rowPill.height : rowValue.implicitHeight,
                                            infoRow.kind === "id" && infoRow.value.length ? rowCopy.height : 0)
                                        width: peekRows.width
                                        height: Math.max(root.__dp(44), infoRow.contentH + root.__dp(16))

                                        Label {
                                            id: rowLabel
                                            width: infoRow.labelWidth - root.__dp(8)
                                            anchors.verticalCenter: parent.verticalCenter
                                            text: infoRow.modelData.label
                                            font.pixelSize: root.__sp(14)
                                            color: infoPeek.labelColor
                                            wrapMode: Text.WordWrap
                                        }
                                        Label {
                                            id: rowValue
                                            visible: infoRow.kind === "text" || infoRow.kind === "id"
                                            x: infoRow.labelWidth
                                            width: infoRow.width - x - (rowCopy.visible ? rowCopy.width + root.__dp(8) : 0)
                                            anchors.verticalCenter: parent.verticalCenter
                                            text: root._peekText(infoRow.value)
                                            font.pixelSize: root.__sp(14)
                                            color: infoPeek.valueColor
                                            wrapMode: Text.WrapAtWordBoundaryOrAnywhere
                                        }
                                        Rectangle {
                                            id: rowPill
                                            readonly property var tone: infoRow.kind === "status"
                                                ? root._statusTone(root.calicataInfo.status)
                                                : root._syncTone(root.calicataInfo.syncState)
                                            visible: infoRow.kind === "status" || infoRow.kind === "sync"
                                            x: infoRow.labelWidth
                                            anchors.verticalCenter: parent.verticalCenter
                                            width: Math.min(infoRow.width - x, pillRow.implicitWidth + root.__dp(24))
                                            height: root.__dp(30)
                                            radius: height / 2
                                            color: tone.bg
                                            Row {
                                                id: pillRow
                                                anchors.centerIn: parent
                                                spacing: root.__dp(7)
                                                Rectangle {
                                                    visible: infoRow.kind === "status"
                                                    width: root.__dp(8)
                                                    height: width
                                                    radius: width / 2
                                                    anchors.verticalCenter: parent.verticalCenter
                                                    color: rowPill.tone.dot || rowPill.tone.fg
                                                }
                                                Components.FlowIcon {
                                                    visible: infoRow.kind === "sync"
                                                    width: root.__dp(18)
                                                    height: width
                                                    anchors.verticalCenter: parent.verticalCenter
                                                    name: "status.online"
                                                    sourceOverride: root._peekHero("cloud")
                                                    pulseOnActive: false
                                                    inactiveOpacity: 1
                                                    tintColor: rowPill.tone.fg
                                                }
                                                Label {
                                                    anchors.verticalCenter: parent.verticalCenter
                                                    text: root._peekText(infoRow.value)
                                                    font.pixelSize: root.__sp(14)
                                                    color: rowPill.tone.fg
                                                    elide: Text.ElideRight
                                                }
                                            }
                                        }
                                        Rectangle {
                                            id: rowCopy
                                            visible: infoRow.kind === "id" && infoRow.value.length > 0
                                            anchors.right: parent.right
                                            anchors.verticalCenter: parent.verticalCenter
                                            width: root.__dp(32)
                                            height: width
                                            radius: root.__dp(10)
                                            color: infoPeek.dark ? Qt.rgba(1, 1, 1, rowCopyTap.pressed ? 0.14 : 0.05)
                                                                 : Qt.rgba(1, 1, 1, rowCopyTap.pressed ? 0.55 : 0.30)
                                            border.width: 1
                                            border.color: infoPeek.dark ? Qt.rgba(1, 1, 1, 0.12) : Qt.rgba(0.0824, 0.102, 0.1882, 0.10)
                                            Components.FlowIcon {
                                                anchors.centerIn: parent
                                                width: root.__dp(17)
                                                height: width
                                                name: "action.copy"
                                                sourceOverride: root._peekHero("document-duplicate")
                                                pulseOnActive: false
                                                inactiveOpacity: 1
                                                tintColor: infoPeek.valueColor
                                            }
                                            MouseArea {
                                                id: rowCopyTap
                                                anchors.fill: parent
                                                anchors.margins: -root.__dp(6)
                                                onClicked: root.copyCalicataLocalId()
                                            }
                                            Accessible.role: Accessible.Button
                                            Accessible.name: "Copiar ID local"
                                        }
                                        Rectangle {
                                            anchors.bottom: parent.bottom
                                            width: parent.width
                                            height: 1
                                            color: infoPeek.hairline
                                        }
                                    }
                                }
                            }
                        }

                        // Bottom action: Copiar ID local.
                        Rectangle {
                            id: peekCopyAction
                            width: parent.width
                            height: root.__dp(50)
                            radius: root.__dp(20)
                            enabled: String(root.calicataInfo.localId || "").length > 0
                            opacity: enabled ? 1.0 : 0.45
                            color: infoPeek.dark ? Qt.rgba(1, 1, 1, copyActionTap.pressed ? 0.10 : 0.04)
                                                 : Qt.rgba(1, 1, 1, copyActionTap.pressed ? 0.50 : 0.22)
                            border.width: 1
                            border.color: infoPeek.hairline
                            scale: copyActionTap.pressed ? 0.985 : 1.0
                            Behavior on scale { NumberAnimation { duration: 90; easing.type: Easing.OutQuad } }
                            Components.FlowIcon {
                                id: copyActionIcon
                                x: root.__dp(18)
                                anchors.verticalCenter: parent.verticalCenter
                                width: root.__dp(22)
                                height: width
                                name: "action.copy"
                                sourceOverride: root._peekHero("document-duplicate")
                                pulseOnActive: false
                                inactiveOpacity: 1
                                tintColor: infoPeek.valueColor
                            }
                            Label {
                                anchors.left: copyActionIcon.right
                                anchors.leftMargin: root.__dp(14)
                                anchors.right: copyActionChevron.left
                                anchors.verticalCenter: parent.verticalCenter
                                text: "Copiar ID local"
                                font.pixelSize: root.__sp(15)
                                color: infoPeek.valueColor
                                elide: Text.ElideRight
                            }
                            Components.FlowIcon {
                                id: copyActionChevron
                                anchors.right: parent.right
                                anchors.rightMargin: root.__dp(14)
                                anchors.verticalCenter: parent.verticalCenter
                                width: root.__dp(18)
                                height: width
                                name: "system.forward"
                                sourceOverride: root._peekHero("chevron-right")
                                pulseOnActive: false
                                inactiveOpacity: 1
                                tintColor: infoPeek.labelColor
                            }
                            MouseArea {
                                id: copyActionTap
                                anchors.fill: parent
                                enabled: peekCopyAction.enabled
                                onClicked: root.copyCalicataLocalId()
                            }
                            Accessible.role: Accessible.Button
                            Accessible.name: "Copiar ID local"
                        }
                    }
                }
            }

            // Discreet confirmation, no modal.
            Rectangle {
                id: infoToast
                function show() { opacity = 1; infoToastTimer.restart() }
                anchors.horizontalCenter: parent.horizontalCenter
                y: Math.min(parent.height - root.__dp(84) - height,
                            peekPanel.y + peekPanel.height + root.__dp(14))
                width: infoToastText.implicitWidth + root.__dp(28)
                height: root.__dp(34)
                radius: height / 2
                color: infoPeek.dark ? "#F6F6F7" : Mobile.InGeCoreFlow.colors.ingemaDeep
                opacity: 0
                visible: opacity > 0
                Behavior on opacity { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
                Label {
                    id: infoToastText
                    anchors.centerIn: parent
                    text: "ID copiado"
                    font.pixelSize: root.__sp(13)
                    color: infoPeek.dark ? Mobile.InGeCoreFlow.colors.ingemaDeep : "#FFFFFF"
                }
                Timer { id: infoToastTimer; interval: 1600; onTriggered: infoToast.opacity = 0 }
            }
        }
        onClosed: {
            infoToast.opacity = 0
            console.info("INGE_CALICATA_INFO_PEEK_TRANSITION phase=close-end")
        }
    }

    Popup {
        id: nameMismatchPopup
        // Fondo del peek "Información de la calicata" (captura 0.5x desenfocada + atenuación).
        property Item glassBackdropItem: null
        Overlay.modal: CalGlassScrim { popupItem: nameMismatchPopup }
        parent: Overlay.overlay
        modal: true
        focus: true
        closePolicy: Popup.NoAutoClose

        width: Math.min(root.width * 0.92, 560)

        // ✅ altura automática (si el contenido es grande, se limita y aparece scroll)
        implicitHeight: Math.min(root.height * 0.78, col.implicitHeight + 28)
        height: implicitHeight

        x: Math.round((root.width - width) / 2)
        y: Math.round((root.height - height) / 2)

        background: CalicataLiquidGlass {
            backdrop: nameMismatchPopup.glassBackdropItem
            // Hoja de vidrio real (primaria); sus controles usan el tratamiento anidado.
            dark: root.darkMode; accent: root.calGenBlue
            radius: root.__dp(20)
            level: "sheet"
        }

        contentItem: Flickable {
            anchors.fill: parent
            clip: true
            boundsBehavior: Flickable.StopAtBounds

            contentWidth: width
            contentHeight: col.implicitHeight + 28

            ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

            ColumnLayout {
                id: col
                x: 14
                y: 14
                width: parent.width - 28
                spacing: 10

                Label {
                    text: "Nombre diferente"
                    font.bold: true
                    font.pixelSize: root.__sp(16)
                    color: root.calTextColor()
                }

                Label {
                    Layout.fillWidth: true
                    wrapMode: Text.WrapAnywhere
                    color: root.calMutedColor()
                    text:
                        "El nombre interno de la calicata no coincide con el nombre del archivo.\n\n" +
                        "Archivo: " + _mismatch_fileStem + "\n" +
                        "Código de calicata: " + _mismatch_headerStem + "\n\n" +
                        "¿Qué deseas hacer?"
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 8

                    Button {
                        id: btnCancel
                        background: CalicataLiquidGlass { dark: root.darkMode; accent: root.calGenBlue; radius: root.__dp(12); tone: "glass"; pressed: btnCancel.down; enabledLook: btnCancel.enabled }
                        Layout.fillWidth: true
                        text: "Cancelar"
                        contentItem: Text {
                            anchors.fill: parent
                            text: btnCancel.text
                            wrapMode: Text.WordWrap
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                        }
                        onClicked: {
                            nameMismatchPopup.close()
                            root._clearPendingSave()
                            if (root._pendingCloseAfterSave) {
                                root._pendingCloseAfterSave = false
                                root._pendingCloseTid = -1
                            }
                        }
                    }

                    Button {
                        id: btnKeep
                        background: CalicataLiquidGlass { dark: root.darkMode; accent: root.calGenBlue; radius: root.__dp(12); tone: "glass"; pressed: btnKeep.down; enabledLook: btnKeep.enabled }
                        Layout.fillWidth: true
                        text: "Mantener nombre del archivo"
                        contentItem: Text {
                            anchors.fill: parent
                            text: btnKeep.text
                            wrapMode: Text.WordWrap
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                        }
                        onClicked: {
                            nameMismatchPopup.close()
                            var saveIndex = root._pendingSaveIndex()
                            var d = root._docAt(saveIndex)
                            var saveTid = root._pendingSaveTid
                            var saveDocId = root._pendingSaveDocId
                            if (!d || !d.save()) {
                                console.warn("[InGe+ M09] save end ok=false tid="
                                             + saveTid + " instanceId=" + saveDocId)
                                root._clearPendingSave()
                                root.showMsg("No se pudo guardar", "Falló el guardado del archivo.")
                                return
                            }
                            root._syncTabFromDoc(saveIndex)
                            console.info("[InGe+ M09] save end ok=true tid="
                                         + saveTid + " instanceId=" + saveDocId)
                            root._clearPendingSave()
                            root._notifySaved("Ficha guardada")
                            root._finishPendingCloseIfAny()
                        }
                    }

                    Button {
                        id: btnRename
                        background: CalicataLiquidGlass { dark: root.darkMode; accent: root.calGenBlue; radius: root.__dp(12); tone: "tinted"; pressed: btnRename.down; enabledLook: btnRename.enabled }
                        Layout.fillWidth: true
                        text: "Renombrar archivo al nombre interno"
                        contentItem: Text {
                            anchors.fill: parent
                            text: btnRename.text
                            wrapMode: Text.WordWrap
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                        }
                        onClicked: {
                            var saveIndex = root._pendingSaveIndex()
                            var d = root._docAt(saveIndex)
                            var saveTid = root._pendingSaveTid
                            var saveDocId = root._pendingSaveDocId
                            if (!d || !d.fileUrl || !d.fileUrl.toString().length) {
                                nameMismatchPopup.close()
                                root._clearPendingSave()
                                return
                            }

                            // ===== datos base =====
                            var oldUrl = d.fileUrl.toString()
                            var oldAbs = root._fileUrlToAbs(oldUrl).replace(/\\/g,"/")
                            var folderAbs = (root._mismatch_folderAbs || "").toString()
                            if (!folderAbs.length) {
                                var p0 = oldAbs.lastIndexOf("/")
                                folderAbs = (p0 >= 0) ? oldAbs.substring(0, p0) : ""
                            }

                            var oldStem = (root._mismatch_fileStem || "").toString()
                            var newStem = (root._mismatch_headerStem || "").toString()
                            if (!newStem.length) {
                                root.showMsg("No se puede renombrar", "El nombre interno está vacío.")
                                return
                            }

                            var newAbs = folderAbs + "/" + newStem + ".calicata.json"

                            // ===== si ya existe el destino, NO sigas (te está pasando ahora) =====
                            if (FS.exists && FS.exists(newAbs)) {
                                root.showMsg("No se puede renombrar",
                                             "Ya existe un archivo con ese nombre:\n\n" + newAbs +
                                             "\n\nBorra el duplicado desde Documentos o elige otro nombre.")
                                return
                            }

                            var newUrl = root._toFileUrl(newAbs)

                            // ===== 1) guardar como nuevo nombre =====
                            var ok = d.saveAs(Qt.resolvedUrl(newUrl), false, true)
                            if (!ok) {
                                console.warn("[InGe+ M09] save end ok=false tid="
                                             + saveTid + " instanceId=" + saveDocId)
                                root._clearPendingSave()
                                root.showMsg("No se pudo renombrar",
                                             "Falló el guardado con el nuevo nombre.\n\n" + newAbs)
                                return
                            }

                            // ===== 2) renombrar carpeta de fotos (Edit/fotos/<stem>) =====
                            // (Solo si existe y si tienes FS.rename; si no, te aviso)
                            var fotosBase = FS.join(folderAbs, "fotos")
                            var oldFotos = FS.join(fotosBase, oldStem)
                            var newFotos = FS.join(fotosBase, newStem)

                            if (FS.exists && FS.exists(oldFotos)) {
                                // oldFotos = ".../fotos/<oldStem>"
                                // newName = "<newStem>"
                                var okDir = DocsOps.renameInPlace(oldFotos, newStem)
                                if (!okDir) {
                                    console.log("⚠️ No se pudo renombrar carpeta fotos:", DocsOps.lastError)
                                }
                            }

                            // ===== 3) mover thumb (Edit/.thumbs/<stem>.png) =====
                            var thumbsDir = FS.join(folderAbs, ".thumbs")
                            var oldThumb = FS.join(thumbsDir, oldStem + ".png")
                            var newThumb = FS.join(thumbsDir, newStem + ".png")

                            if (FS.exists && FS.exists(oldThumb)) {
                                var okThumb = DocsOps.renameInPlace(oldThumb, newStem + ".png")
                                if (!okThumb) {
                                    console.log("⚠️ No se pudo renombrar thumb:", DocsOps.lastError)
                                }
                            }

                            // ===== 4) borrar el archivo anterior (para que NO queden duplicados) =====
                            // OJO: en OneDrive a veces bloquear borrar/rename. Si falla, lo informamos.
                            var oldCmp = (Qt.platform.os === "windows") ? oldAbs.toLowerCase() : oldAbs
                            var newCmp = (Qt.platform.os === "windows") ? newAbs.toLowerCase() : newAbs

                            if (oldCmp !== newCmp) {
                                var rmOk = DocsOps.removePath(oldAbs)
                                if (!rmOk) {
                                    root.showMsg("Renombrado parcial",
                                                 "Se creó el nuevo archivo pero NO se pudo borrar el anterior.\n" +
                                                 "Motivo: " + DocsOps.lastError + "\n\n" +
                                                 "Viejo:\n" + oldAbs + "\n\nNuevo:\n" + newAbs)
                                }
                            }

                            // ===== 5) refrescar UI =====
                            root._syncTabFromDoc(saveIndex)
                            nameMismatchPopup.close()
                            console.info("[InGe+ M09] save end ok=true tid="
                                         + saveTid + " instanceId=" + saveDocId)
                            root._clearPendingSave()
                            root._notifySaved("Ficha guardada con el nuevo nombre")
                            root._finishPendingCloseIfAny()
                        }
                    }
                }
            }
        }
    }

    App.CalicataSaveOpenDialog {
        id: calDlg
        parent: Overlay.overlay

        // ✅ root cerrado del usuario
        rootPath: docs.basePath

        // ✅ donde normalmente están las calicatas editables
        initialDir: FS.join(docs.basePath, "Proyecto_Local/Calicata/Edit")

        // Open
        onAcceptedOpen: function(fileAbs) {
            if (!fileAbs || !fileAbs.length) return
            var selectedFile = fileAbs
            var openTargetTid = root.currentTab ? root.currentTab.tid : -1
            var openTargetDocId = root._docInstanceId(root.currentDoc)

            Qt.callLater(function() {
                if (openTargetTid >= 0) {
                    var targetIndex = root._indexForTid(openTargetTid)
                    if (targetIndex < 0
                            || targetIndex !== root.currentIndex
                            || root._docInstanceId(root._docAt(targetIndex))
                               !== openTargetDocId) {
                        console.warn("[InGe+ M09] apertura cancelada: cambió la ficha destino")
                        return
                    }
                }
                var urlStr = root._toFileUrl(selectedFile)
                var key = root._openKeyFromUrl(urlStr)

                // ✅ si ya existe, solo enfoca
                var existing = root._findTabByKey(key)
                if (existing >= 0) {
                    root.selectTab(existing)

                    // ✅ si el open venía desde el organizador, cierra y limpia
                    if (root._openFromTabsPopup) {
                        root._openFromTabsPopup = false
                        root.resumeView = "doc"
                        tabsPopup.close()
                    }
                    return
                }

                // ✅ si NO existe, recién decide si abrir en nueva pestaña
                if (root.currentTab && (root.currentTab.dirty || (root.currentTab.fileUrl && root.currentTab.fileUrl.length))) {
                    root.addNewTab()
                }

                if (root._openFromTabsPopup) {
                    root._openFromTabsPopup = false
                    root.resumeView = "doc"
                    tabsPopup.close()
                }



                root.applyPickedFile(selectedFile)
            })
        }

        onRejected: {
            root._openFromTabsPopup = false
            root._clearPendingSave()
            if (root._pendingCloseAfterSave) {
                root._pendingCloseAfterSave = false
                root._pendingCloseTid = -1
            }
        }

        // Save
        onAcceptedSave: function(folderAbs, fileName) {
            root._syncDocsList()
            var saveIndex = root._pendingSaveIndex()
            var doc = root._docAt(saveIndex)
            var saveTid = root._pendingSaveTid
            var saveDocId = root._pendingSaveDocId
            if (!doc) {
                root._clearPendingSave()
                return
            }
            if (root._docInstanceId(root.currentDoc) === saveDocId)
                root._syncFormIntoDoc(doc, true)

            // normaliza extensión
            var fn = (fileName || "").toString().trim()
            if (!fn.length) {
                console.warn("[InGe+ M09] save end ok=false tid=" + saveTid
                             + " instanceId=" + saveDocId)
                root._clearPendingSave()
                return
            }
            if (!fn.endsWith(".calicata.json")) fn += ".calicata.json"

            var abs = FS.join(folderAbs, fn)

            // ✅ si existe: popup claro y no intentes saveAs
            if (FS.exists && FS.exists(abs)) {
                console.warn("[InGe+ M09] save end ok=false tid=" + saveTid
                             + " instanceId=" + saveDocId)
                root._clearPendingSave()
                root.showMsg("Nombre repetido",
                             "Ya existe una ficha con ese nombre en esa carpeta:\n\n" + abs +
                             "\n\nElige otro nombre.")
                return
            }

            var urlStr = root._toFileUrl(abs)

            var ok = doc.saveAs(Qt.resolvedUrl(urlStr), false, true)
            if (!ok) {
                console.warn("[InGe+ M09] save end ok=false tid=" + saveTid
                             + " instanceId=" + saveDocId)
                root._clearPendingSave()
                root.showMsg("No se pudo guardar",
                             "No se pudo crear el archivo.\n\n" +
                             "Verifica permisos o que el nombre sea válido.")
                console.log("❌ saveAs falló:", abs)
                return
            }

            root._syncTabFromDoc(saveIndex)
            console.info("[InGe+ M09] save end ok=true tid=" + saveTid
                         + " instanceId=" + saveDocId)
            root._clearPendingSave()
            root._notifySaved("Ficha guardada")
            root._finishPendingCloseIfAny()
        }
    }

    onVisibleChanged: {
        if (visible) {
            if (_workspaceInitialized && tabsModel.count === 0) {
                var restoreUrl = calicatasSettingsM09.lastDocumentUrl
                var restoreAbs = restoreUrl && restoreUrl.length
                               ? _fileUrlToAbs(restoreUrl) : ""
                var canRestore = restoreUrl && restoreUrl.length
                               && (!FS.exists || FS.exists(restoreAbs))
                if (canRestore) {
                    createScratchTab()
                    if (currentTab) _pushHistory(currentTab.tid)
                    var restoreTid = currentTab ? currentTab.tid : -1
                    var restoreDocId = _docInstanceId(currentDoc)
                    Qt.callLater(function() {
                        var restoreIndex = root._indexForTid(restoreTid)
                        if (restoreIndex < 0
                                || restoreIndex !== root.currentIndex
                                || root._docInstanceId(root._docAt(restoreIndex))
                                   !== restoreDocId) {
                            return
                        }
                        if (!root.applyPickedFile(restoreUrl))
                            root.workspaceStatusText = "No se pudo restaurar la ficha anterior"
                        else
                            root.workspaceStatusText = "Borrador recuperado automáticamente"
                    })
                } else {
                    createInitialScratchTab()
                    if (currentTab) _pushHistory(currentTab.tid)
                }
            }
            if (resumeView === "tabs") {
                Qt.callLater(function(){ tabsPopup.open() })
            }
            return
        }

        // visible == false
        if (root.autoSaveEnabled) root.autoSaveCurrentM09(true)
        if (_pendingCloseAfterSave) {
            var pendingIndex = _indexForTid(_pendingCloseTid)
            if (pendingIndex >= 0) {
                var pendingTab = tabsModel.get(pendingIndex)
                if (pendingTab && pendingTab.dirty) {
                    _pendingCloseAfterSave = false
                    _pendingCloseTid = -1
                }
            }
        }
    }




    Popup {
        id: confirmCloseTab
        // Fondo del peek "Información de la calicata" (captura 0.5x desenfocada + atenuación).
        property Item glassBackdropItem: null
        Overlay.modal: CalGlassScrim { popupItem: confirmCloseTab }
        parent: Overlay.overlay
        modal: true
        focus: true
        closePolicy: Popup.NoAutoClose

        width: Math.min(root.width * 0.90, 420)
        x: (root.width - width) / 2
        y: (root.height - height) / 2

        background: CalicataLiquidGlass {
            backdrop: confirmCloseTab.glassBackdropItem
            // Hoja de vidrio real (primaria); sus controles usan el tratamiento anidado.
            dark: root.darkMode; accent: root.calGenBlue
            radius: root.__dp(20)
            level: "sheet"
        }

        contentItem: ColumnLayout {
            anchors.fill: parent
            anchors.margins: 14
            spacing: 10

            Label { text: "Cambios sin guardar"; font.bold: true; font.pixelSize: root.__sp(16); color: root.calTextColor() }
            Label {
                text: "Esta ficha tiene cambios sin guardar.\n¿Deseas guardarlos antes de cerrar?"
                wrapMode: Text.WordWrap
                color: root.calMutedColor()
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 10

                Button {
                    id: calGlassButton3904
                    background: CalicataLiquidGlass { dark: root.darkMode; accent: root.calGenBlue; radius: root.__dp(12); tone: "glass"; pressed: calGlassButton3904.down; enabledLook: calGlassButton3904.enabled }
                    Layout.fillWidth: true
                    text: "Cancelar"
                    onClicked: {
                        confirmCloseTab.close()
                        root._pendingCloseTid = -1
                        root._pendingCloseAfterSave = false
                    }
                }

                Button {
                    id: calGlassButton3914
                    background: CalicataLiquidGlass { dark: root.darkMode; accent: root.calGenBlue; radius: root.__dp(12); tone: "danger"; pressed: calGlassButton3914.down; enabledLook: calGlassButton3914.enabled }
                    Layout.fillWidth: true
                    text: "No guardar"
                    onClicked: {
                        confirmCloseTab.close()
                        var tid = root._pendingCloseTid
                        var idx = root._indexForTid(tid)
                        var discardDoc = idx >= 0 ? root._docAt(idx) : null
                        if (discardDoc && discardDoc.clearDraft)
                            discardDoc.clearDraft()
                        root._pendingCloseTid = -1
                        root._pendingCloseAfterSave = false
                        Qt.callLater(function() { root._closeTabsByTids([tid], true) })
                    }
                }

                Button {
                    id: calGlassButton3930
                    background: CalicataLiquidGlass { dark: root.darkMode; accent: root.calGenBlue; radius: root.__dp(12); tone: "tinted"; pressed: calGlassButton3930.down; enabledLook: calGlassButton3930.enabled }
                    Layout.fillWidth: true
                    text: "Guardar"
                    onClicked: {
                        confirmCloseTab.close()
                        var idx = root._indexForTid(root._pendingCloseTid)
                        if (idx < 0) {
                            root._pendingCloseTid = -1
                            root._pendingCloseAfterSave = false
                            return
                        }
                        if (idx !== root.currentIndex) root.selectTab(idx)
                        root._pendingCloseAfterSave = true
                        var saveTid = root._pendingCloseTid
                        var saveDocId = root._docInstanceId(root._docAt(idx))
                        // Guardar normal (si no tiene URL abrirá Guardar Como)
                        Qt.callLater(function() {
                            var saveIndex = root._indexForTid(saveTid)
                            if (saveIndex < 0
                                    || saveIndex !== root.currentIndex
                                    || root._docInstanceId(root._docAt(saveIndex))
                                       !== saveDocId) {
                                return
                            }
                            root.doSave(false)
                        })
                    }
                }
            }
        }
    }


    Connections {
        id: currentDocConnections
        target: root.currentDoc
        enabled: !root._closeOperationActive
                 && target !== null
                 && target.closed !== true
        ignoreUnknownSignals: true

        function onDirtyChanged() {
            var index = root._indexForDocId(root._docInstanceId(currentDocConnections.target))
            if (index >= 0) root._syncTabFromDoc(index)
        }
        function onFileUrlChanged() {
            var index = root._indexForDocId(root._docInstanceId(currentDocConnections.target))
            if (index >= 0) root._syncTabFromDoc(index)
        }
        function onDisplayNameChanged() {
            var index = root._indexForDocId(root._docInstanceId(currentDocConnections.target))
            if (index >= 0) root._syncTabFromDoc(index)
        }

        // opcional: si tu doc emite titleSuggested(string)
        function onTitleSuggested(t) {
            var targetDocId = root._docInstanceId(currentDocConnections.target)
            var targetIndex = root._indexForDocId(targetDocId)
            if (targetIndex < 0 || targetIndex !== root.currentIndex) return
            var s = (t || "").toString().trim()
            if (!s.length) return
            tabsModel.setProperty(targetIndex, "title", s)
        }
    }

    // P0 AUTOSAVE:
    // - cada cambio reinicia un debounce corto;
    // - al quedar la app Inactive/Suspended se fuerza un checkpoint inmediato;
    // - el timer de 20 s queda como red de seguridad.
    Connections {
        id: p0FormAutosaveConnections
        target: formLoader.item
        enabled: root.autoSaveEnabled && target !== null
        ignoreUnknownSignals: true

        function onDocumentMarkedDirty(targetDoc) {
            if (!targetDoc || targetDoc.closed === true) return
            if (root._docInstanceId(targetDoc)
                    !== root._docInstanceId(root.currentDoc)) return
            p0AutoSaveDebounce.restart()
        }
    }

    Connections {
        id: p0ApplicationStateConnections
        target: Qt.application

        function onStateChanged() {
            if (Qt.application.state === Qt.ApplicationActive)
                return

            p0AutoSaveDebounce.stop()
            if (root.autoSaveEnabled)
                root.autoSaveCurrentM09(true)
        }
    }

    Timer {
        id: p0AutoSaveDebounce
        interval: 800
        repeat: false
        onTriggered: {
            if (root.autoSaveEnabled)
                root.autoSaveCurrentM09()
        }
    }

    Timer {
        id: autoSaveTimer
        interval: 20000
        repeat: true
        running: root.autoSaveEnabled
        onTriggered: root.autoSaveCurrentM09()
    }

    Timer {
        id: deferredWorkspaceInit
        interval: 32
        repeat: false
        onTriggered: root.initializeWorkspaceDeferred()
    }

    Popup {
        id: overflowPopup
        // Fondo del peek "Información de la calicata" (captura 0.5x desenfocada + atenuación).
        property Item glassBackdropItem: null
        Overlay.modal: CalGlassScrim { popupItem: overflowPopup }
        parent: Overlay.overlay
        modal: true
        focus: true
        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside

        width: Math.min(root.width - 24, root.__dp(286))
        height: Math.min(menuColumn.implicitHeight + 20, root.height - 24)
        padding: 10
        onOpened: {
            overflowReveal.reset()
            overflowReveal.play()
        }

        background: CalicataLiquidGlass {
            backdrop: overflowPopup.glassBackdropItem
            // Hoja de vidrio real (primaria); sus botones usan el tratamiento anidado.
            dark: root.darkMode; accent: root.calGenBlue
            radius: root.__dp(16)
            level: "sheet"
        }

        contentItem: ScrollView {
            id: menuScroll
            clip: true
            ScrollBar.horizontal.policy: ScrollBar.AlwaysOff

            ColumnLayout {
                id: menuColumn
                width: menuScroll.availableWidth
                spacing: 4

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 6

                    NavFichaMenuButton {
                        Layout.fillWidth: true
                        text: "Anterior"
                        svgSource: root.navAsset("ic_nav_previous.svg")
                        enabled: root.canGoBack()
                        onClicked: {
                            overflowPopup.close()
                            root.goBackHistory()
                        }
                    }
                    NavFichaMenuButton {
                        Layout.fillWidth: true
                        text: "Siguiente"
                        svgSource: root.navAsset("ic_nav_next.svg")
                        enabled: root.canGoForward()
                        onClicked: {
                            overflowPopup.close()
                            root.goForwardHistory()
                        }
                    }
                }

                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 1
                    color: root.calBorderColor()
                }

                WorkspaceMenuButton {
                    Layout.fillWidth: true
                    text: "Archivar calicata"
                    iconName: "documents.folder"
                    enabled: !!root.currentDoc
                    onClicked: { overflowPopup.close(); root.archiveCurrentCalicata() }
                }
                WorkspaceMenuButton {
                    Layout.fillWidth: true
                    text: root.autoSaveEnabled ? "Auto-guardado: activo" : "Auto-guardado: manual"
                    iconName: "status.sync"
                    active: root.autoSaveEnabled
                    onClicked: {
                        root.autoSaveEnabled = !root.autoSaveEnabled
                        overflowPopup.close()
                    }
                }
                WorkspaceMenuButton {
                    Layout.fillWidth: true
                    text: root.gpsEnabled ? "GPS compartido: activo" : "Activar GPS compartido"
                    iconName: "status.gps"
                    active: root.gpsEnabled
                    onClicked: {
                        root.gpsEnabled = !root.gpsEnabled
                        root.requestGpsAutoShare(root.gpsEnabled)
                        overflowPopup.close()
                    }
                }
                NavFichaMenuButton {
                    Layout.fillWidth: true
                    text: "Abrir ficha · InGeDrive"
                    svgSource: root.navAsset("ic_nav_open_file.svg")
                    onClicked: {
                        overflowPopup.close()
                        root.openDialogAbrirCalicata()
                    }
                }
                NavFichaMenuButton {
                    Layout.fillWidth: true
                    visible: false
                    text: "Abrir ficha online..."
                    svgSource: root.navAsset("ic_nav_open_file.svg")
                    enabled: !!root.currentDoc
                    onClicked: {
                        overflowPopup.close()
                        root.openCloudCalicataBrowser()
                    }
                }
                WorkspaceMenuButton {
                    Layout.fillWidth: true
                    text: "Guardar como..."
                    iconName: "action.save"
                    enabled: tabsModel.count > 0
                    onClicked: {
                        overflowPopup.close()
                        root.doSave(true)
                    }
                }
                WorkspaceMenuButton {
                    Layout.fillWidth: true
                    text: "Exportar PDF"
                    visible: root.canExportPdf
                    iconName: "documents.pdf"
                    enabled: tabsModel.count > 0
                    onClicked: {
                        overflowPopup.close()
                        var form = formLoader.item
                        if (form && typeof form.exportPdfFlow === "function") {
                            form.exportPdfFlow()
                        } else {
                            root.showMsg("Exportación PDF no disponible",
                                         "El formulario actual no expone exportPdfFlow().")
                        }
                    }
                }
                WorkspaceMenuButton {
                    Layout.fillWidth: true
                    text: "Duplicar ficha"
                    iconName: "action.copy"
                    enabled: tabsModel.count > 0
                    onClicked: {
                        overflowPopup.close()
                        root.duplicateCurrentTabM09()
                    }
                }
                NavFichaMenuButton {
                    Layout.fillWidth: true
                    text: "Abrir mapa / GPS"
                    svgSource: root.navAsset("ic_nav_open_map_gps.svg")
                    onClicked: {
                        overflowPopup.close()
                        root.requestOpenMap()
                    }
                }
                NavFichaMenuButton {
                    Layout.fillWidth: true
                    text: "Cerrar ficha activa"
                    svgSource: root.navAsset("ic_nav_close_active_file.svg")
                    enabled: tabsModel.count > 0
                    onClicked: {
                        overflowPopup.close()
                        root.tryCloseTab(root.currentIndex)
                    }
                }
                NavFichaMenuButton {
                    Layout.fillWidth: true
                    text: "Administrar fichas abiertas"
                    svgSource: root.navAsset("ic_nav_manage_open_files.svg")
                    enabled: tabsModel.count > 0
                    onClicked: {
                        overflowPopup.close()
                        root.resumeView = "tabs"
                        tabsPopup.open()
                    }
                }
            }
        }
    }

    Popup {
        id: inGeDriveCalicataPopup
        parent: Overlay.overlay
        modal: true
        focus: true
        closePolicy: Popup.NoAutoClose
        width: parent ? parent.width : root.width
        height: parent ? parent.height : root.height
        x: 0
        y: 0
        background: Rectangle {
            // Ambiente de pantalla completa que refractan los controles de vidrio.
            objectName: "calicataGlassBackdrop"
            color: root.calBgColor()
            gradient: Gradient {
                GradientStop { position: 0.0; color: root.darkMode ? "#182440" : Mobile.InGeCoreFlow.colors.ingemaBlueWash }
                GradientStop { position: 1.0; color: root.darkMode ? Mobile.InGeCoreFlow.colors.ingemaDeep : "#F8FAFD" }
            }
        }

        contentItem: Documents.NothingDocumentsRoot {
            id: driveCalicataBrowser
            contextEnabled: false
            // Un <código>.calicata.json de InGeDrive se abre como ficha (deserializador existente).
            routeCalicataJson: true
            onCalicataJsonOpenRequested: function(spaceId, nodeId, versionId) {
                CalicataCloud.openDriveJson(spaceId, nodeId, versionId)
            }
            onCalicataExcelOpenRequested: function(localPath, source) {
                inGeDriveCalicataPopup.close()
                root.importCalicataExcel(localPath, source)
            }
            anchors.fill: parent
            flow: root.flow
            systemDark: root.darkMode
            motionAllowed: root.flow ? root.flow.motionAllowed : true
            bottomSafeInset: 0
            onCalicataOpenRequested: function(projectId, calicataId) {
                if (!projectId || !calicataId) {
                    root.showMsg("No se pudo abrir la calicata",
                                 "El Smart Document no devolvió una identidad válida.")
                    return
                }
                inGeDriveCalicataPopup.close()
                root.openCloudCalicata(String(projectId), String(calicataId))
            }
        }
    }

    CalPopup {
        id: cloudCalicatasPopup
        // Con filas visibles se conservan (una recarga no vacía la lista).
        readonly property string listState: {
            if (cloudCalicatasList.count > 0) return "DATA"
            if (CalicataCloud.busy) return "LOADING"
            if (String(CalicataCloud.listedProjectId || "") === String(root._remoteLoadingProjectId || ""))
                return "EMPTY"
            if (String(CalicataCloud.lastError || "").length) return "ERROR"
            return "LOADING"
        }
        // Estados separados: LOADING / EMPTY / ERROR / DATA.
        readonly property string stateMessage:
            listState === "LOADING" ? "Consultando servidor…"
            : listState === "ERROR"
              ? "No se pudo consultar el servidor. Tus fichas locales se conservan; puedes reintentar."
            : listState === "EMPTY"
              ? (root._cloudListArchived ? "No hay calicatas archivadas en este proyecto."
                                         : "No hay fichas activas en este proyecto.")
            : (root._cloudListArchived
               ? "Al abrir una ficha archivada se restaura a su estado anterior. Sus datos se conservan."
               : "Selecciona la ficha canónica que quieres abrir.")
        width: Math.min(root.width - 24, root.__dp(400))
        height: Math.min(root.height - 48, root.__dp(620))
        x: ((parent ? parent.width : root.width) - width) / 2
        baseY: ((parent ? parent.height : root.height) - height) / 2

        contentItem: ColumnLayout {
            spacing: root.__dp(12)
            RowLayout {
                Layout.fillWidth: true
                spacing: root.__dp(10)
                Rectangle {
                    Layout.preferredWidth: root.__dp(40)
                    Layout.preferredHeight: root.__dp(40)
                    radius: root.__dp(11)
                    color: root.calGenBlueSoft
                    Components.FlowIcon {
                        anchors.centerIn: parent
                        width: root.__dp(20)
                        height: width
                        name: root._cloudListArchived ? "archive.item" : "documents.folder"
                        flow: root.flow
                        tintColor: root.calGenBlue
                        activeTintColor: root.calGenBlue
                        inactiveOpacity: 1
                    }
                }
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: root.__dp(1)
                    Label {
                        Layout.fillWidth: true
                        text: root._cloudListArchived ? "Calicatas archivadas del proyecto"
                                                      : "Calicatas online del proyecto"
                        color: root.calTextColor()
                        font.pixelSize: root.__sp(17)
                        font.bold: true
                        wrapMode: Text.WordWrap
                    }
                    Label {
                        Layout.fillWidth: true
                        visible: cloudCalicatasPopup.listState === "DATA" || cloudCalicatasPopup.listState === "LOADING"
                        text: cloudCalicatasPopup.stateMessage
                        color: root.calMutedColor()
                        font.pixelSize: root.__sp(12)
                        wrapMode: Text.WordWrap
                    }
                }
            }
            Item {
                Layout.fillWidth: true
                Layout.fillHeight: true
                visible: cloudCalicatasPopup.listState === "LOADING"
                Column {
                    id: cloudSkeletonV600
                    width: parent.width
                    spacing: root.__dp(6)
                    SequentialAnimation {
                        running: cloudSkeletonV600.visible && cloudCalicatasPopup.opened
                                 && (!root.flow || root.flow.motionAllowed)
                        loops: Animation.Infinite
                        OpacityAnimator { target: cloudSkeletonV600; from: 1.0; to: 0.55; duration: 720; easing.type: Easing.InOutSine }
                        OpacityAnimator { target: cloudSkeletonV600; from: 0.55; to: 1.0; duration: 720; easing.type: Easing.InOutSine }
                    }
                    Repeater {
                        model: 4
                        Rectangle {
                            required property int index
                            width: cloudSkeletonV600.width
                            height: root.__dp(64)
                            radius: root.__dp(14)
                            color: root.calBorderColor()
                            opacity: 0.45
                            Column {
                                x: root.__dp(14)
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: root.__dp(8)
                                Rectangle { width: cloudSkeletonV600.width * (0.55 - (index % 2) * 0.12); height: root.__dp(10); radius: height / 2; color: root.calMutedColor(); opacity: 0.35 }
                                Rectangle { width: cloudSkeletonV600.width * 0.28; height: root.__dp(8); radius: height / 2; color: root.calMutedColor(); opacity: 0.25 }
                            }
                        }
                    }
                }
            }
            // Vacío / error: bloque centrado en lugar de un panel en blanco.
            Item {
                Layout.fillWidth: true
                Layout.fillHeight: true
                visible: cloudCalicatasPopup.listState === "EMPTY" || cloudCalicatasPopup.listState === "ERROR"
                Column {
                    anchors.centerIn: parent
                    width: parent.width - root.__dp(24)
                    spacing: root.__dp(10)
                    Rectangle {
                        anchors.horizontalCenter: parent.horizontalCenter
                        width: root.__dp(56)
                        height: width
                        radius: root.__dp(16)
                        color: cloudCalicatasPopup.listState === "ERROR" ? (root.darkMode ? "#3A2A16" : "#FCE8CC") : root.calGenBlueSoft
                        Components.FlowIcon {
                            anchors.centerIn: parent
                            width: root.__dp(26)
                            height: width
                            name: cloudCalicatasPopup.listState === "ERROR" ? "status.offline"
                                  : (root._cloudListArchived ? "archive.item" : "documents.folder")
                            flow: root.flow
                            tintColor: cloudCalicatasPopup.listState === "ERROR" ? (root.darkMode ? "#FFC58A" : "#C2580A") : root.calGenBlue
                            activeTintColor: tintColor
                            inactiveOpacity: 1
                        }
                    }
                    Label {
                        width: parent.width
                        horizontalAlignment: Text.AlignHCenter
                        text: cloudCalicatasPopup.stateMessage
                        color: cloudCalicatasPopup.listState === "ERROR" ? root.calTextColor() : root.calMutedColor()
                        font.pixelSize: root.__sp(14)
                        wrapMode: Text.WordWrap
                    }
                }
            }
            ListView {
                id: cloudCalicatasList
                Layout.fillWidth: true
                Layout.fillHeight: true
                visible: cloudCalicatasPopup.listState === "DATA"
                clip: true
                spacing: root.__dp(8)
                boundsBehavior: Flickable.StopAtBounds
                model: root._cloudListArchived ? root.archivedCalicataEntries : CalicataCloud.projectCalicatas
                delegate: CalRow {
                    required property var modelData
                    readonly property var tone: root._statusTone(modelData.status || "BORRADOR")
                    width: cloudCalicatasList.width
                    enabled: !root._remoteLoadingDocId.length && !root._restoringDocId.length
                    iconName: root._cloudListArchived ? "archive.item" : "calgen.code"
                    title: String(modelData.code || "Sin código")
                    subtitle: root._cloudListArchived ? "Archivada · tocar para restaurar"
                                                      : String(modelData.title || modelData.location || "")
                    chipText: root._cloudListArchived ? "Archivada" : root.statusLabel(modelData.status || "BORRADOR")
                    chipBg: tone.bg
                    chipFg: tone.fg
                    showChevron: true
                    onActivated: {
                        if (root._cloudListArchived) root.openArchivedEntry(modelData)
                        else root.loadCloudCalicata(modelData)
                    }
                }
            }
            RowLayout {
                Layout.fillWidth: true
                spacing: root.__dp(8)
                CalButton {
                    Layout.fillWidth: true
                    Layout.preferredWidth: 1
                    tone: "soft"
                    iconName: "nav.sync"
                    text: "Actualizar"
                    enabled: !CalicataCloud.busy && root._remoteLoadingProjectId.length > 0
                    onClicked: CalicataCloud.listProjectCalicatas(root._remoteLoadingProjectId)
                }
                CalButton {
                    Layout.fillWidth: true
                    Layout.preferredWidth: 1
                    text: root._cloudListArchived ? "Activas" : "Archivadas"
                    onClicked: root._cloudListArchived = !root._cloudListArchived
                }
                CalButton {
                    Layout.fillWidth: true
                    Layout.preferredWidth: 1
                    tone: "primary"
                    text: "Cerrar"
                    onClicked: cloudCalicatasPopup.close()
                }
            }
        }
    }

    Popup {
        id: sectionsPopup
        // Fondo del peek "Información de la calicata" (captura 0.5x desenfocada + atenuación).
        property Item glassBackdropItem: null
        Overlay.modal: CalGlassScrim { popupItem: sectionsPopup }
        parent: Overlay.overlay
        modal: true
        focus: true
        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
        padding: root.__dp(10)
        width: Math.min(parent.width - root.__dp(28), root.__dp(480))
        height: Math.min(sectionsPopupContent.implicitHeight + root.__dp(20),
                         parent.height - root.__dp(80))
        x: Math.round((parent.width - width) / 2)
        y: Math.round((parent.height - height) / 2)

        background: CalicataLiquidGlass {
            backdrop: sectionsPopup.glassBackdropItem
            // Hoja de vidrio real (primaria); sus botones usan el tratamiento anidado.
            dark: root.darkMode; accent: root.calGenBlue
            radius: root.__dp(20)
            level: "sheet"
        }

        contentItem: ColumnLayout {
            id: sectionsPopupContent
            spacing: root.__dp(8)

            Text {
                Layout.fillWidth: true
                text: "Etapas de la calicata"
                color: root.calTextColor()
                font.pixelSize: root.__sp(14)
                font.bold: true
            }

            GridLayout {
                Layout.fillWidth: true
                columns: 2
                columnSpacing: root.__dp(6)
                rowSpacing: root.__dp(6)

                Repeater {
                    model: formLoader.item ? formLoader.item.sectionNavigation : []

                    delegate: WorkspaceMenuButton {
                        required property var modelData
                        Layout.fillWidth: true
                        Layout.preferredWidth: 1
                        text: modelData.label
                        active: !!formLoader.item && formLoader.item.sectionNavCurrent === modelData.n
                        iconName: modelData.icon
                        onClicked: {
                            var sectionNumber = modelData.n
                            sectionsPopup.close()
                            Qt.callLater(function() {
                                var form = formLoader.item
                                if (form && typeof form.scrollToSection === "function")
                                    form.scrollToSection(sectionNumber)
                            })
                        }
                    }
                }
            }
        }
    }

    Popup {
        id: exportPopup
        // Fondo del peek "Información de la calicata" (captura 0.5x desenfocada + atenuación).
        property Item glassBackdropItem: null
        Overlay.modal: CalGlassScrim { popupItem: exportPopup }
        parent: Overlay.overlay
        modal: true
        focus: true
        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
        padding: root.__dp(10)
        height: exportPopupContent.implicitHeight + root.__dp(20)

        background: CalicataLiquidGlass {
            backdrop: exportPopup.glassBackdropItem
            // Hoja de vidrio real (primaria); sus botones usan el tratamiento anidado.
            dark: root.darkMode; accent: root.calGenBlue
            radius: root.__dp(20)
            level: "sheet"
        }

        contentItem: ColumnLayout {
            id: exportPopupContent
            spacing: root.__dp(7)

            Text {
                Layout.fillWidth: true
                text: "¿Dónde guardar el Excel?"
                color: root.calTextColor()
                font.pixelSize: root.__sp(14)
                font.bold: true
            }

            WorkspaceMenuButton {
                Layout.fillWidth: true
                text: "Google Drive"
                iconName: "export.excel"
                onClicked: {
                    exportPopup.close()
                    root.exportCurrentExcel("GOOGLE_DRIVE")
                }
            }

            WorkspaceMenuButton {
                Layout.fillWidth: true
                text: "InGeDrive"
                iconName: "documents.folder"
                onClicked: {
                    exportPopup.close()
                    root.exportCurrentExcel("SUPABASE")
                }
            }

            WorkspaceMenuButton {
                Layout.fillWidth: true
                text: "PDF"
                visible: root.canExportPdf
                iconName: "documents.pdf"
                onClicked: {
                    exportPopup.close()
                    root.exportPdfIfOpen()
                }
            }
        }
    }





    Component.onCompleted: {
        __armUpdateLayoutSize()
        autoSaveEnabled = calicatasSettingsM09.autoSave
        _workspaceInitialized = true
        // Paint the shell first; drafts, filesystem probing and CalicataFormPage
        // construction run only after the initial interactive frame.
        deferredWorkspaceInit.start()
    }

    // ===== CABECERA FINAL DEL EDITABLE MÓVIL =====
    Item { id: topBar; anchors.top: parent.top; width: parent.width; height: 0 }

    // ===== PESTAÑAS HORIZONTALES =====
    Item { id: workspaceStrip; anchors.top: topBar.bottom; width: parent.width; height: 0 }

    // Estado vacío del workspace; la barra de pestañas conserva el botón "+".
    Label {
        anchors.centerIn: parent
        visible: root.initializationComplete && tabsModel.count === 0
        text: "Calicatas · Abre o crea una ficha"
        color: root.calMutedColor()
        width: parent.width - 32
        wrapMode: Text.WordWrap
        horizontalAlignment: Text.AlignHCenter
    }

    // Selección de posición exacta: mapa a pantalla completa + hoja inferior
    // con el punto real y Cancelar / Confirmar (misma lógica que antes).
    CalPopup {
        id: coordinatePicker
        property string documentId: ""
        width: parent ? parent.width : root.width
        height: parent ? parent.height : root.height
        x: 0
        baseY: 0
        padding: 0
        closePolicy: Popup.CloseOnEscape
        background: Rectangle {
            // Ambiente de pantalla completa que refractan los controles de vidrio.
            objectName: "calicataGlassBackdrop"
            color: root.calBgColor()
            gradient: Gradient {
                GradientStop { position: 0.0; color: root.darkMode ? "#182440" : Mobile.InGeCoreFlow.colors.ingemaBlueWash }
                GradientStop { position: 1.0; color: root.darkMode ? Mobile.InGeCoreFlow.colors.ingemaDeep : "#F8FAFD" }
            }
        }
        contentItem: ColumnLayout {
            spacing: 0
            Loader {
                id: coordinateMap
                Layout.fillWidth: true
                Layout.fillHeight: true
                active: coordinatePicker.opened
                // Resolve the optional map module only after the user opens the picker.
                // A sourceComponent would still resolve its imports during app startup.
                onActiveChanged: {
                    if (!active) {
                        source = ""
                        return
                    }
                    setSource(Qt.resolvedUrl("CalicataPointPicker.qml"), {
                        auth: Qt.binding(function() { return root.auth }),
                        flow: Qt.binding(function() { return root.flow }),
                        darkMode: Qt.binding(function() { return root.darkMode }),
                        themeMode: Qt.binding(function() { return root.darkMode ? 1 : 0 }),
                        coordinatePickerMode: true,
                        statusCardOnly: true,
                        gpsOnly: true,
                        pageActive: Qt.binding(function() { return coordinatePicker.opened }),
                        followGps: false,
                        navigationInset: 0,
                        gpsHasFix: Qt.binding(function() { return typeof Perms !== "undefined" && Perms.nativeHasFix }),
                        gpsLat: Qt.binding(function() { return typeof Perms !== "undefined" ? Number(Perms.nativeLatitude) : NaN }),
                        gpsLon: Qt.binding(function() { return typeof Perms !== "undefined" ? Number(Perms.nativeLongitude) : NaN }),
                        gpsAlt: Qt.binding(function() { return typeof Perms !== "undefined" ? Number(Perms.nativeAltitude) : NaN }),
                        gpsAccuracy: Qt.binding(function() { return typeof Perms !== "undefined" ? Number(Perms.nativeAccuracy) : NaN }),
                        gpsTimestampMs: Qt.binding(function() { return typeof Perms !== "undefined" ? Number(Perms.nativeTimestampMs) : 0 })
                    })
                }
                onLoaded: {
                    var map = item
                    var h = root.currentDoc ? root.currentDoc.header : {}
                    // Abrir el mapa solo inspecciona: el punto de la ficha (UTM
                    // manual o lectura previa) es el candidato inicial. Sin GPS.
                    if (h.latitude !== undefined && h.latitude !== null && h.latitude !== "" && h.longitude !== undefined && h.longitude !== null && h.longitude !== "")
                        Qt.callLater(function() {
                            if (coordinateMap.item !== map) return
                            map.selectCoordinate(Number(h.latitude), Number(h.longitude),
                                                 NaN, NaN, "Punto de la ficha")
                            map.centerOn(Number(h.latitude), Number(h.longitude))
                        })
                }
            }
            Label {
                Layout.fillWidth: true
                Layout.margins: 12
                visible: coordinateMap.status === Loader.Error
                text: "No se pudo cargar el selector de ubicación. Comprueba el módulo de GPS."
                wrapMode: Text.WordWrap
            }
            // Hoja de la ubicación GPS: estado real de la lectura y confirmación.
            // La única posición posible es la lectura GPS actual del dispositivo.
            Rectangle {
                id: coordinateSheet
                readonly property var pickerMap: coordinateMap.item
                readonly property string gpsState: pickerMap ? String(pickerMap.gpsState || "idle") : "idle"
                // Candidato vigente: punto de la ficha o lectura de "Mi ubicación".
                readonly property bool hasPoint: !!pickerMap && pickerMap.selected === true
                readonly property bool fromDevice: hasPoint && gpsState === "fixed"
                readonly property string sheetZ: {
                    var h = root.currentDoc && root.currentDoc.header ? root.currentDoc.header : {}
                    var z = h.utm_z !== undefined && h.utm_z !== null && String(h.utm_z).trim().length ? h.utm_z : h.altitud
                    return z === undefined || z === null ? "" : String(z).trim()
                }
                readonly property bool sheetZManual: {
                    var h = root.currentDoc && root.currentDoc.header ? root.currentDoc.header : {}
                    var source = String(h.altitude_source || "")
                    return sheetZ.length > 0 && (source === "MANUAL" || source === "")
                }
                readonly property color stateColor: gpsState === "fixed" ? (root.darkMode ? Mobile.InGeCoreFlow.colors.ingemaGreenTint : Mobile.InGeCoreFlow.colors.ingemaGreen)
                                                  : gpsState === "searching" ? (root.darkMode ? "#FFB35C" : "#DE7A12")
                                                  : gpsState === "error" ? (root.darkMode ? "#FF8A80" : "#C9302C")
                                                  : root.calMutedColor()
                Layout.fillWidth: true
                implicitHeight: coordinateSheetColumn.implicitHeight + root.__dp(36)
                radius: root.__dp(22)
                color: "transparent"
                // Hoja inferior: el mismo vidrio real de los emergentes (con su velo de lectura).
                CalicataLiquidGlass { dark: root.darkMode; accent: root.calGenBlue; anchors.fill: parent; radius: parent.radius; level: "sheet" }
                // Esquinas inferiores rectas (la hoja apoya en el borde de la pantalla).
                Rectangle {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    height: parent.radius
                    color: parent.color
                }
                ColumnLayout {
                    id: coordinateSheetColumn
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.leftMargin: root.__dp(16)
                    anchors.rightMargin: root.__dp(16)
                    anchors.topMargin: root.__dp(14)
                    spacing: root.__dp(12)
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: root.__dp(8)
                        Label {
                            Layout.fillWidth: true
                            text: "Ubicación de la calicata"
                            color: root.calTextColor()
                            font.pixelSize: root.__sp(18)
                            font.bold: true
                            elide: Text.ElideRight
                        }
                        Button {
                            id: coordinateCloseButton
                            Layout.preferredWidth: root.__dp(40)
                            Layout.preferredHeight: root.__dp(40)
                            padding: 0
                            focusPolicy: Qt.NoFocus
                            Accessible.name: "Cancelar"
                            onClicked: coordinatePicker.close()
                            background: CalicataLiquidGlass { dark: root.darkMode; accent: root.calGenBlue; radius: width / 2; pressed: coordinateCloseButton.down }
                            contentItem: Item {
                                Components.FlowIcon {
                                    anchors.centerIn: parent
                                    width: root.__dp(20)
                                    height: width
                                    name: "calgen.close"
                                    flow: root.flow
                                    tintColor: root.calTextColor()
                                    activeTintColor: root.calTextColor()
                                    inactiveOpacity: 1
                                }
                            }
                        }
                    }
                    // Estado GPS: buscando / ubicación actual / error / sin lectura.
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: root.__dp(8)
                        Rectangle {
                            id: coordinateStateDot
                            Layout.preferredWidth: root.__dp(8)
                            Layout.preferredHeight: root.__dp(8)
                            radius: width / 2
                            color: coordinateSheet.stateColor
                            SequentialAnimation on opacity {
                                running: coordinateSheet.gpsState === "searching"
                                loops: Animation.Infinite
                                NumberAnimation { to: 0.3; duration: 520; easing.type: Easing.InOutSine }
                                NumberAnimation { to: 1.0; duration: 520; easing.type: Easing.InOutSine }
                                onRunningChanged: if (!running) coordinateStateDot.opacity = 1
                            }
                        }
                        Label {
                            Layout.fillWidth: true
                            text: coordinateSheet.gpsState === "fixed" ? "Ubicación actual del dispositivo"
                                  : coordinateSheet.gpsState === "searching"
                                    ? (coordinateSheet.pickerMap.referenceFramed ? "Actualizando ubicación… (última posición conocida)" : "Buscando ubicación GPS…")
                                  : coordinateSheet.gpsState === "error" ? String(coordinateSheet.pickerMap.gpsError || "")
                                  : coordinateSheet.hasPoint && coordinateSheet.pickerMap.selectedSource === "Punto fijado en mapa"
                                    ? "Punto elegido en el mapa. Pulsa Usar esta ubicación para guardarlo."
                                  : coordinateSheet.hasPoint ? "Punto registrado en la ficha. Toca el mapa o pulsa Mi ubicación para cambiarlo."
                                  : "Pulsa Mi ubicación para obtener la posición GPS del dispositivo."
                            color: coordinateSheet.gpsState === "error" ? coordinateSheet.stateColor : root.calMutedColor()
                            font.pixelSize: root.__sp(13)
                            wrapMode: Text.WordWrap
                        }
                    }
                    Rectangle {
                        Layout.fillWidth: true
                        visible: coordinateSheet.hasPoint
                        implicitHeight: coordinateValues.implicitHeight + root.__dp(24)
                        radius: root.__dp(14)
                        color: root.calGenBlueSoft
                        Grid {
                            id: coordinateValues
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            anchors.leftMargin: root.__dp(14)
                            anchors.rightMargin: root.__dp(14)
                            columns: 2
                            rowSpacing: root.__dp(8)
                            Repeater {
                                model: {
                                    var m = coordinateSheet.pickerMap
                                    if (!coordinateSheet.hasPoint || !m) return []
                                    return [["Latitud", m.selectedLat.toFixed(6)],
                                            ["Longitud", m.selectedLon.toFixed(6)],
                                            ["Precisión", isFinite(m.selectedAccuracy) ? "± " + Math.round(m.selectedAccuracy) + " m" : "No informada"],
                                            // Z: una cota manual se conserva; si no, al confirmar se
                                            // obtiene la elevación del terreno (DEM) del punto.
                                            ["Cota Z", coordinateSheet.sheetZManual ? coordinateSheet.sheetZ + " m (manual, se conserva)"
                                                       : "Se obtiene del terreno al confirmar"]]
                                }
                                delegate: Column {
                                    required property var modelData
                                    width: coordinateValues.width / 2
                                    spacing: root.__dp(1)
                                    Text { text: modelData[0]; color: root.calMutedColor(); font.pixelSize: root.__sp(12) }
                                    Text { text: modelData[1]; color: root.calTextColor(); font.pixelSize: root.__sp(16); font.weight: Font.DemiBold }
                                }
                            }
                        }
                    }
                    Label {
                        Layout.fillWidth: true
                        visible: coordinateSheet.hasPoint
                        text: "X / Y UTM y la zona se calculan al confirmar, con la conversión de la ficha."
                        color: root.calMutedColor()
                        font.pixelSize: root.__sp(12)
                        wrapMode: Text.WordWrap
                    }
                    RowLayout {
                        Layout.fillWidth: true
                        Layout.bottomMargin: root.__dp(8)
                        spacing: root.__dp(10)
                        CalButton {
                            Layout.fillWidth: true
                            Layout.preferredWidth: 1
                            text: "Cancelar"
                            onClicked: coordinatePicker.close()
                        }
                        CalButton {
                            Layout.fillWidth: true
                            Layout.preferredWidth: 1
                            tone: "primary"
                            text: "Usar esta ubicación"
                            // "Usar esta ubicación" = commit del candidato vigente (GPS o
                            // punto tocado en el mapa). Solo el punto de la ficha sin
                            // cambios se acepta sin reescribir (conserva Z/zona manuales).
                            enabled: coordinateSheet.hasPoint && coordinateSheet.gpsState !== "searching"
                            onClicked: {
                                if (coordinatePicker.documentId !== root._docInstanceId(root.currentDoc)) { coordinatePicker.close(); return }
                                var map = coordinateMap.item
                                if (map.selectedSource === "Punto de la ficha") { coordinatePicker.close(); return }
                                // Punto elegido a mano lejos de una lectura GPS real y reciente:
                                // se pide confirmación solo ahora, al confirmar.
                                var distance = map.selectedSource === map.gpsSourceLabel ? NaN
                                             : map.distanceToRecentFix(map.selectedLat, map.selectedLon)
                                if (isFinite(distance) && distance > 5000) {
                                    distantPointConfirm.distanceKm = distance / 1000
                                    distantPointConfirm.open()
                                    return
                                }
                                root._commitCoordinateCandidate()
                            }
                        }
                    }
                }
            }
            // Confirmación de distancia con el lenguaje de Calicatas (vidrio, tokens).
            CalPopup {
                id: distantPointConfirm
                property real distanceKm: 0
                width: Math.min(root.width - root.__dp(48), root.__dp(380))
                x: (root.width - width) / 2
                baseY: (root.height - height) / 2
                padding: root.__dp(20)
                contentItem: ColumnLayout {
                    spacing: root.__dp(8)
                    Label {
                        Layout.fillWidth: true
                        text: "Punto distante del GPS"
                        font.bold: true
                        font.pixelSize: root.__sp(17)
                        color: root.calTextColor()
                        wrapMode: Text.WordWrap
                    }
                    Label {
                        Layout.fillWidth: true
                        text: "El punto elegido está a " + distantPointConfirm.distanceKm.toFixed(1)
                              + " km de la ubicación actual del dispositivo. ¿Confirmas esta ubicación?"
                        font.pixelSize: root.__sp(14)
                        color: root.calMutedColor()
                        wrapMode: Text.WordWrap
                    }
                    RowLayout {
                        Layout.fillWidth: true
                        Layout.topMargin: root.__dp(8)
                        spacing: root.__dp(10)
                        CalButton {
                            Layout.fillWidth: true
                            Layout.preferredWidth: 1
                            text: "Cancelar"
                            onClicked: distantPointConfirm.close()
                        }
                        CalButton {
                            Layout.fillWidth: true
                            Layout.preferredWidth: 1
                            tone: "primary"
                            text: "Confirmar"
                            onClicked: {
                                distantPointConfirm.close()
                                root._commitCoordinateCandidate()
                            }
                        }
                    }
                }
            }
            Connections {
                target: coordinateMap.item
                ignoreUnknownSignals: true
                function onRequestGpsEnabled(on) { root.requestGpsAutoShare(on) }
                function onRequestGpsRefresh() {
                    root.requestGpsAutoShare(true)
                }
            }
        }
    }

    // ===== CONTENIDO =====
    Loader {
        id: formLoader
        anchors.top: workspaceStrip.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: bottomBar.top
        active: tabsModel.count > 0 && root._formLoaderReady && !root._suspendFormLoader
        visible: active
        // Continuidad de ficha: el formulario (re)creado aparece con un fade corto.
        onLoaded: root.playFormSwapV600(0.0)

        sourceComponent: Component {
            CalicataFormPage {
                id: formPage
                auth: root.auth
                flow: root.flow
                flowMotionEnabled: root.flowMotionEnabled
                flowReduceMotion: root.flowReduceMotion
                flowMotionLevel: root.flowMotionLevel
                doc:  root.currentDoc
                fileUrl: (root.currentTab && root.currentTab.fileUrl) ? root.currentTab.fileUrl : ""
                darkMode: root.darkMode
                themeMode: root.themeMode
                persistenceStatus: root.persistenceStatus
                persistenceError: root.persistenceHasError
                onRequestExportExcel: root.exportCurrentExcel()
                openMapAction: root.openCoordinatePicker
                coordinatePickerOpen: coordinatePicker.opened

                onDirtyChanged: {
                    if (root._closeOperationActive
                            || !formPage.doc
                            || formPage.doc.closed === true) return
                    var formDocId = root._docInstanceId(formPage.doc)
                    var formIndex = root._indexForDocId(formDocId)
                    if (formIndex < 0
                            || root._docInstanceId(root._docAt(formIndex)) !== formDocId) {
                        root._mappingError("form dirty", formIndex, formDocId,
                                           root._docInstanceId(root._docAt(formIndex)))
                        return
                    }
                    tabsModel.setProperty(formIndex, "dirty", !!dirty)
                }
                onRequestGpsRefresh: root.requestGpsAutoShare(true)
                onFlushRequested: root.autoSaveCurrentM09(true)
                onRequestOpenEarth: function(latitude, longitude, altitude, label) {
                    root.requestOpenEarth(latitude, longitude, altitude, label)
                }
                onDocumentMarkedDirty: function(targetDoc) {
                    if (!targetDoc || targetDoc.closed === true || root._closeOperationActive) return
                    var targetDocId = root._docInstanceId(targetDoc)
                    if (root.draftCheckpointDocId === targetDocId)
                        root.draftCheckpointDocId = ""
                    var targetIndex = root._indexForDocId(targetDocId)
                    if (targetIndex >= 0
                            && root._docInstanceId(root._docAt(targetIndex)) === targetDocId)
                        tabsModel.setProperty(targetIndex, "dirty", true)
                }

                onTitleSuggested: function(title) {
                    if (root._closeOperationActive
                            || !formPage.doc
                            || formPage.doc.closed === true) return
                    var formDocId = root._docInstanceId(formPage.doc)
                    var formIndex = root._indexForDocId(formDocId)
                    if (formIndex < 0 || formIndex !== root.currentIndex) return
                    var formTab = tabsModel.get(formIndex)

                    // ✅ si ya existe archivo, NO tocar title (se basa en nombre de archivo)
                    if (formTab.fileUrl && formTab.fileUrl.length)
                        return

                    var newTitle = (title || "").toString().trim()
                    if (newTitle.length)
                        tabsModel.setProperty(formIndex, "title", newTitle)
                }
            }
        }
    }

    // ===== BOTTOM BAR =====
    Item { id: bottomBar; anchors.bottom: parent.bottom; width: parent.width; height: 0 }


    // ===== GPS flotante =====
    Item {
        id: gpsFab
        visible: false
        width: root.__dp(84)
        height: root.__dp(84)
        anchors.right: parent.right
        anchors.rightMargin: 14
        anchors.bottom: bottomBar.top
        anchors.bottomMargin: 12
        z: 20

        Rectangle {
            anchors.fill: parent
            radius: width / 2
            color: root.gpsEnabled ? "#24302D" : Mobile.InGeCoreFlow.colors.ingemaNavy

            border.width: root.gpsEnabled ? 3 : 2           // ✅ antes 5 / 0
            border.color: root.gpsEnabled ? Mobile.InGeCoreFlow.colors.ingemaGreenTint : Mobile.InGeCoreFlow.colors.ingemaDeep  // ✅ borde oscuro cuando OFF
        }


        Column {
            anchors.centerIn: parent
            spacing: 2   // ✅ antes 6 (muy separado)

            Text {
                text: "GPS"
                color: "white"
                font.bold: true
                font.pixelSize: 22
                horizontalAlignment: Text.AlignHCenter
                width: parent.width
            }

            Item {
                width: 30
                height: 26
                anchors.horizontalCenter: parent.horizontalCenter

                // ✅ Activo: más grande
                Image {
                    anchors.centerIn: parent
                    width: 26
                    height: 26
                    source: root.calAsset("icon_gps_on.svg")
                    visible: root.gpsEnabled
                    // playing removed for static SVG
                    fillMode: Image.PreserveAspectFit
                }

                // ✅ Inactivo: más pequeño
                Image {
                    anchors.centerIn: parent
                    width: 9
                    height: 9
                    sourceSize.width: 9
                    sourceSize.height: 9
                    source: root.calAsset("icon_gps_off.svg")
                    visible: !root.gpsEnabled
                    fillMode: Image.PreserveAspectFit
                    smooth: true
                }
            }
        }


        MouseArea {
            anchors.fill: parent
            onClicked: {
                root.gpsEnabled = !root.gpsEnabled
                root.requestGpsAutoShare(root.gpsEnabled)
            }
        }
    }






    Popup {
        id: exportProgressPopup
        // Fondo del peek "Información de la calicata" (captura 0.5x desenfocada + atenuación).
        property Item glassBackdropItem: null
        Overlay.modal: CalGlassScrim { popupItem: exportProgressPopup }
        parent: Overlay.overlay
        modal: true
        focus: true
        closePolicy: Popup.NoAutoClose
        x: Math.max(12, Math.round((parent.width - width) / 2))
        y: Math.max(12, Math.round((parent.height - height) / 2))
        width: Math.min(root.width - 32, 360)
        height: 240

        background: CalicataLiquidGlass {
            backdrop: exportProgressPopup.glassBackdropItem
            // Hoja de vidrio real (primaria); sus controles usan el tratamiento anidado.
            dark: root.darkMode; accent: root.calGenBlue
            radius: root.__dp(22)
            level: "sheet"
        }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 18
            spacing: 12

            Image {
                Layout.alignment: Qt.AlignHCenter
                Layout.preferredWidth: 72
                Layout.preferredHeight: 72
                source: root.exportAsset("export_progress.svg")
                fillMode: Image.PreserveAspectFit

                RotationAnimation on rotation {
                    running: exportProgressPopup.visible
                    loops: Animation.Infinite
                    from: 0
                    to: 360
                    duration: 1300
                }
            }

            Text {
                Layout.fillWidth: true
                text: "Exportando Excel"
                color: root.calTextColor()
                font.pixelSize: root.__sp(18)
                font.bold: true
                horizontalAlignment: Text.AlignHCenter
            }

            Text {
                Layout.fillWidth: true
                text: root.exportProgressText
                color: root.calMutedColor()
                font.pixelSize: root.__sp(12)
                wrapMode: Text.WordWrap
                horizontalAlignment: Text.AlignHCenter
            }
        }
    }

    Popup {
        id: exportResultPopup
        // Fondo del peek "Información de la calicata" (captura 0.5x desenfocada + atenuación).
        property Item glassBackdropItem: null
        Overlay.modal: CalGlassScrim { popupItem: exportResultPopup }
        parent: Overlay.overlay
        modal: true
        focus: true
        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
        x: Math.max(12, Math.round((parent.width - width) / 2))
        y: Math.max(12, Math.round((parent.height - height) / 2))
        width: Math.min(root.width - 32, 390)
        height: 306

        background: CalicataLiquidGlass {
            backdrop: exportResultPopup.glassBackdropItem
            // Hoja de vidrio real (primaria); sus controles usan el tratamiento anidado.
            dark: root.darkMode; accent: root.calGenBlue
            radius: root.__dp(22)
            level: "sheet"
        }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 18
            spacing: 10

            Image {
                Layout.alignment: Qt.AlignHCenter
                Layout.preferredWidth: 74
                Layout.preferredHeight: 74
                source: root.exportAsset("export_success.svg")
                fillMode: Image.PreserveAspectFit
            }

            Text {
                Layout.fillWidth: true
                text: "Excel exportado"
                color: root.calTextColor()
                font.pixelSize: root.__sp(18)
                font.bold: true
                horizontalAlignment: Text.AlignHCenter
            }

            Text {
                Layout.fillWidth: true
                Layout.fillHeight: true
                text: root.exportResultText
                color: root.calMutedColor()
                font.pixelSize: root.__sp(11)
                wrapMode: Text.WrapAnywhere
                horizontalAlignment: Text.AlignHCenter
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                Button {
                    Layout.fillWidth: true
                    text: "Cerrar"
                    onClicked: exportResultPopup.close()
                }

                Button {
                    Layout.fillWidth: true
                    text: "Ver ruta"
                    onClicked: root.showMsg("Ruta de exportación", root.lastExcelPath.length ? root.lastExcelPath : "Sin ruta registrada")
                }
            }
        }
    }

    Popup {
        id: exportErrorPopup
        // Fondo del peek "Información de la calicata" (captura 0.5x desenfocada + atenuación).
        property Item glassBackdropItem: null
        Overlay.modal: CalGlassScrim { popupItem: exportErrorPopup }
        parent: Overlay.overlay
        modal: true
        focus: true
        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
        x: Math.max(12, Math.round((parent.width - width) / 2))
        y: Math.max(12, Math.round((parent.height - height) / 2))
        width: Math.min(root.width - 32, 390)
        height: 260

        background: CalicataLiquidGlass {
            backdrop: exportErrorPopup.glassBackdropItem
            // Hoja de vidrio real (primaria); sus controles usan el tratamiento anidado.
            dark: root.darkMode; accent: root.calGenBlue
            radius: root.__dp(22)
            level: "sheet"
        }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 18
            spacing: 10

            Image {
                Layout.alignment: Qt.AlignHCenter
                Layout.preferredWidth: 72
                Layout.preferredHeight: 72
                source: root.exportAsset("export_error.svg")
                fillMode: Image.PreserveAspectFit
            }

            Text {
                Layout.fillWidth: true
                text: "No se pudo exportar"
                color: root.calTextColor()
                font.pixelSize: root.__sp(18)
                font.bold: true
                horizontalAlignment: Text.AlignHCenter
            }

            Text {
                Layout.fillWidth: true
                Layout.fillHeight: true
                text: root.exportResultText
                color: root.calMutedColor()
                font.pixelSize: root.__sp(11)
                wrapMode: Text.WordWrap
                horizontalAlignment: Text.AlignHCenter
            }

            Button {
                id: calGlassButton5231
                background: CalicataLiquidGlass { dark: root.darkMode; accent: root.calGenBlue; radius: root.__dp(12); tone: "glass"; pressed: calGlassButton5231.down; enabledLook: calGlassButton5231.enabled }
                Layout.fillWidth: true
                text: "Cerrar"
                onClicked: exportErrorPopup.close()
            }
        }
    }
    // ===== TAB SWITCHER (Popup) =====
    CalPopup {
        id: tabsPopup
        glass: true
        width: Math.min(root.width - 28, root.__dp(380))
        height: Math.min((parent ? parent.height : root.height) * 0.7, switcherBody.implicitHeight + topPadding + bottomPadding)
        x: ((parent ? parent.width : root.width) - width) / 2
        baseY: Math.max(12, (parent ? parent.height : root.height) - height - root.__dp(104))
        onClosed: root._backAtWorkspace = false
        contentItem: ColumnLayout {
            id: switcherBody
            spacing: root.__dp(12)
            RowLayout {
                Layout.fillWidth: true
                spacing: root.__dp(8)
                Label {
                    text: "Calicatas"
                    color: root.calTextColor()
                    font.pixelSize: root.__sp(19)
                    font.bold: true
                }
                Rectangle {
                    Layout.preferredHeight: root.__dp(24)
                    Layout.preferredWidth: Math.max(height, tabsCountLabel.implicitWidth + root.__dp(14))
                    radius: height / 2
                    color: root.calGenBlueSoft
                    Text {
                        id: tabsCountLabel
                        anchors.centerIn: parent
                        text: tabsModel.count
                        color: root.calGenBlue
                        font.pixelSize: root.__sp(12)
                        font.weight: Font.DemiBold
                    }
                }
                Item { Layout.fillWidth: true }
                CalButton {
                    implicitHeight: root.__dp(38)
                    tone: "soft"
                    text: "Listo"
                    onClicked: tabsPopup.close()
                }
            }
            ListView {
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.preferredHeight: Math.min(root.__dp(360), contentHeight)
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                model: tabsModel
                spacing: root.__dp(8)
                delegate: CalRow {
                    id: tabRow
                    required property int index
                    required property var model
                    readonly property bool dirty: !!model.dirty
                    width: ListView.view.width
                    title: String(model.title || "")
                    selected: index === root.currentIndex
                    iconName: "documents.file"
                    subtitle: dirty ? "Cambios en borrador" : "Sin cambios pendientes"
                    dotColor: dirty ? (root.darkMode ? "#FFB35C" : "#DE7A12") : (root.darkMode ? Mobile.InGeCoreFlow.colors.ingemaGreenTint : Mobile.InGeCoreFlow.colors.ingemaGreen)
                    trailingInset: root.__dp(40)
                    onActivated: { root.selectTab(index); if (root.currentIndex === index) tabsPopup.close() }
                    Button {
                        id: tabCloseButton
                        anchors.right: parent.right
                        anchors.rightMargin: root.__dp(6)
                        anchors.verticalCenter: parent.verticalCenter
                        width: root.__dp(40)
                        height: root.__dp(40)
                        padding: 0
                        focusPolicy: Qt.NoFocus
                        Accessible.name: "Cerrar " + tabRow.title
                        onClicked: root.tryCloseTab(tabRow.index)
                        background: CalicataLiquidGlass { dark: root.darkMode; accent: root.calGenBlue; radius: width / 2; pressed: tabCloseButton.down }
                        contentItem: Item {
                            Components.FlowIcon {
                                anchors.centerIn: parent
                                width: root.__dp(16)
                                height: width
                                name: "calgen.close"
                                flow: root.flow
                                tintColor: root.calMutedColor()
                                activeTintColor: root.calMutedColor()
                                inactiveOpacity: 1
                            }
                        }
                    }
                }
            }
            RowLayout {
                Layout.fillWidth: true
                spacing: root.__dp(8)
                CalButton {
                    Layout.fillWidth: true
                    Layout.preferredWidth: 1
                    tone: "primary"
                    iconName: "action.add"
                    text: "Nueva"
                    onClicked: { root.addNewTab(); tabsPopup.close() }
                }
                CalButton {
                    Layout.fillWidth: true
                    Layout.preferredWidth: 1
                    iconName: "documents.folder"
                    text: "Abrir…"
                    onClicked: { root._openFromTabsPopup = true; root.openDialogAbrirCalicata() }
                }
            }
        }
    }

    // ===== InGeDrive: JSON versionado de la ficha (Guardar / Guardar en…) =====
    // Guardar = sincronización canónica existente (fila + Smart Document) y copia
    // JSON versionada en 04_PROYECTOS/<proyecto>/06_GABINETE (CalicataCloud).
    // "Al día" solo cuando ambas están confirmadas por el servidor.
    property bool _driveJsonBusy: false
    property string _driveJsonDocId: ""
    property bool _driveJsonManual: false
    property bool _applyingDriveIdentity: false
    property string _driveJsonError: ""
    property string _driveJsonSavedDocId: ""
    readonly property bool driveJsonCurrent: _driveJsonSavedDocId.length > 0
        && _driveJsonSavedDocId === root._docInstanceId(root.currentDoc)
        && root.contextSyncState === "SYNCED"
    // Laboratorio/clasificación que el servidor aún no admite (migración no aplicada):
    // el valor local se conserva y la ficha nunca se declara "Al día".
    readonly property bool labCloudPending: {
        var cortes = root.currentDoc && root.currentDoc.cortes ? root.currentDoc.cortes : []
        for (var i = 0; i < cortes.length; ++i) {
            var row = cortes[i] || {}, extra = {}
            try { extra = JSON.parse(String(row._extraJson || "{}")) } catch (e) { extra = {} }
            var pending = row.lab_cloud_pending || (row._extra && row._extra.lab_cloud_pending) || extra.lab_cloud_pending
            if (pending && pending.length) return true
        }
        return false
    }
    readonly property string saveStateLabel: (_driveJsonBusy || root._savingCloudDocId.length) ? "Guardando…"
        : _driveJsonError.length ? "Error"
        : root.contextSyncState === "CONFLICT" ? "Conflicto"
        : root.labCloudPending ? "Lab pendiente"
        : driveJsonCurrent ? "Al día" : "Pendiente"

    // Guardar = un solo flujo: sync de la fila (+ 06_GABINETE/FIELD + Smart
    // Document en syncDocument) → este JSON. Solo el JSON lanzado por el Guardar
    // manual lo cierra; un autoguardado JSON concurrente nunca lo sustituye.
    property string _driveJsonSaveDocId: ""
    property string _driveJsonQueuedDocId: ""
    function _startManualDriveJson(docId, doc) {
        root._driveJsonSaveDocId = docId
        if (!doc || !root.saveDriveJson("", true, doc)) {
            root._driveJsonSaveDocId = ""
            if (docId === root._savingCloudDocId) {
                root._savingCloudDocId = ""
                root._clearPendingSave()
            }
        }
    }
    function _runQueuedDriveJson() {
        var queued = root._driveJsonQueuedDocId
        if (!queued.length) return
        root._driveJsonQueuedDocId = ""
        root._startManualDriveJson(queued, root._docAt(root._indexForDocId(queued)))
    }

    function saveDriveJson(folderId, manual, targetDoc) {
        var doc = targetDoc || root.currentDoc
        if (!doc || doc.closed === true || root._driveJsonBusy) return false
        if (doc === root.currentDoc && formLoader.item && !formLoader.item.commitPendingField()) return false
        root._driveJsonManual = !!manual
        root._driveJsonBusy = true
        root._driveJsonDocId = root._docInstanceId(doc)
        root._driveJsonError = ""
        var reason = CalicataCloud.saveJsonToDrive(doc, String(root.docs && root.docs.basePath || ""), String(folderId || ""))
        if (reason.length) {
            root._driveJsonBusy = false
            root._driveJsonDocId = ""
            root._driveJsonError = reason
            if (manual) root.showMsg("No se pudo guardar en InGeDrive", reason)
            return false
        }
        return true
    }

    // Autoguardado remoto: solo con identidad ya resuelta (primer Guardar manual),
    // agrupado 20 s tras el último cambio; el autosave local no cambia.
    Timer {
        id: driveJsonAutosave
        interval: 20000
        repeat: false
        onTriggered: {
            var d = root.currentDoc
            if (!d || d.closed === true || !String(d.header.remoteCalicataId || "").length) return
            if (root._driveJsonBusy || root._savingCloudDocId.length || root._autoSyncDocId.length
                    || root._publishingDocId.length || String(d.syncState) === "SYNCING") { restart(); return }
            root.saveDriveJson("", false)
        }
    }
    Connections {
        target: root.currentDoc
        ignoreUnknownSignals: true
        function onDataChanged() {
            if (root._applyingDriveIdentity || !root.currentDoc || root.currentDoc.applyingCloudState
                    || root._remoteLoadingDocId.length || String(root.currentDoc.syncState) !== "PENDING") return
            if (String(root.currentDoc.header.drive_json_node_id || "").length) {
                root._driveJsonSavedDocId = ""
                driveJsonAutosave.restart()
            }
        }
    }

    // "Guardar en…": carpetas del espacio del proyecto de la ficha (no de otro).
    property string _driveFolderParent: ""
    property var _driveFolderTrail: []
    property var _driveFolders: []
    property bool _driveFoldersLoading: false
    property string _driveFoldersError: ""
    function openDriveFolderPicker() {
        var doc = root.currentDoc
        if (!doc) return
        if (!String(doc.header.projectId || "").length) {
            root.showMsg("Selecciona un proyecto", "Selecciona un proyecto antes de guardar en InGeDrive.")
            return
        }
        root._driveFolderTrail = []
        root.loadDriveFolders("")
        driveFolderPopup.open()
    }
    function loadDriveFolders(parentId) {
        root._driveFolderParent = String(parentId || "")
        root._driveFolders = []
        root._driveFoldersError = ""
        root._driveFoldersLoading = true
        CalicataCloud.listDriveFolders(String(root.currentDoc ? root.currentDoc.header.projectId || "" : ""), root._driveFolderParent)
    }

    Connections {
        target: CalicataCloud
        ignoreUnknownSignals: true
        function onDriveJsonSaved(localId, result) {
            if (localId !== root._driveJsonDocId) return
            root._driveJsonBusy = false
            root._driveJsonDocId = ""
            root._driveJsonError = ""
            var index = root._indexForDocId(localId)
            var d = index >= 0 ? root._docAt(index) : null
            if (d && d.closed !== true) {
                var h = Object.assign({}, d.header)
                for (var key in result) h[key] = result[key]
                root._applyingDriveIdentity = true
                d.header = h
                d.saveDraft()
                root._applyingDriveIdentity = false
            }
            root._driveJsonSavedDocId = localId
            root.workspaceStatusText = "Guardado en InGeDrive · " + String(result.drive_json_name || "")
                                       + " · v" + String(result.drive_json_version_number || "")
            if (localId === root._driveJsonSaveDocId) {
                root._driveJsonSaveDocId = ""
                if (localId === root._savingCloudDocId) {
                    root._savingCloudDocId = ""
                    root._clearPendingSave()
                    root._notifySaved("Ficha guardada en el proyecto online")
                    root._finishPendingCloseIfAny()
                }
            }
            root._resumeQueuedSave(localId)
            root._runQueuedDriveJson()
        }
        function onDriveJsonSaveFailed(localId, message) {
            if (localId !== root._driveJsonDocId) return
            root._driveJsonBusy = false
            root._driveJsonDocId = ""
            root._driveJsonError = message
            if (localId === root._driveJsonSaveDocId) {
                root._driveJsonSaveDocId = ""
                if (localId === root._savingCloudDocId) {
                    root._savingCloudDocId = ""
                    root._clearPendingSave()
                }
            }
            if (root._driveJsonManual) root.showMsg("No se pudo guardar en InGeDrive", message)
            root._resumeQueuedSave(localId)
            root._runQueuedDriveJson()
        }
        function onDriveFoldersListed(projectId, parentId, spaceId, folders) {
            if (String(parentId || "") !== root._driveFolderParent) return
            root._driveFoldersLoading = false
            root._driveFolders = folders
        }
        function onDriveFoldersFailed(message) {
            root._driveFoldersLoading = false
            root._driveFoldersError = message
        }
        function onDriveJsonDownloaded(localPath) {
            inGeDriveCalicataPopup.close()
            if (!root.applyPickedFile(localPath))
                root.showMsg("No se pudo abrir la ficha", "El JSON de InGeDrive no es una ficha de calicata válida.")
        }
        function onDriveJsonDownloadFailed(message) {
            root.showMsg("No se pudo abrir la ficha", message)
        }
    }

    CalPopup {
        id: driveFolderPopup
        width: Math.min(root.width - 24, root.__dp(400))
        height: Math.min(root.height - 48, root.__dp(560))
        x: ((parent ? parent.width : root.width) - width) / 2
        baseY: ((parent ? parent.height : root.height) - height) / 2

        contentItem: ColumnLayout {
            spacing: root.__dp(12)
            Label {
                Layout.fillWidth: true
                text: "Guardar en…"
                color: root.calTextColor()
                font.pixelSize: root.__sp(17)
                font.bold: true
            }
            Label {
                Layout.fillWidth: true
                text: "Proyecto" + root._driveFolderTrail.map(function(f) { return " / " + f.name }).join("")
                color: root.calMutedColor()
                font.pixelSize: root.__sp(12)
                elide: Text.ElideMiddle
            }
            CalRow {
                Layout.fillWidth: true
                visible: root._driveFolderTrail.length > 0
                title: "Volver"
                subtitle: "Carpeta anterior"
                iconName: "calgen.chevronLeft"
                onActivated: {
                    var trail = root._driveFolderTrail.slice(0, root._driveFolderTrail.length - 1)
                    root._driveFolderTrail = trail
                    root.loadDriveFolders(trail.length ? trail[trail.length - 1].id : "")
                }
            }
            ListView {
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                spacing: root.__dp(8)
                boundsBehavior: Flickable.StopAtBounds
                model: root._driveFolders
                delegate: CalRow {
                    required property var modelData
                    width: ListView.view.width
                    title: String(modelData.name || "")
                    iconName: "documents.folder"
                    showChevron: true
                    onActivated: {
                        root._driveFolderTrail = root._driveFolderTrail.concat([{ id: String(modelData.id), name: String(modelData.name) }])
                        root.loadDriveFolders(String(modelData.id))
                    }
                }
            }
            Label {
                Layout.fillWidth: true
                visible: root._driveFoldersLoading || root._driveFoldersError.length > 0
                         || (!root._driveFoldersLoading && root._driveFolders.length === 0)
                text: root._driveFoldersLoading ? "Consultando InGeDrive…"
                      : root._driveFoldersError.length ? root._driveFoldersError
                      : "Sin subcarpetas. Puedes guardar aquí."
                color: root.calMutedColor()
                wrapMode: Text.WordWrap
            }
            RowLayout {
                Layout.fillWidth: true
                spacing: root.__dp(8)
                CalButton {
                    Layout.fillWidth: true
                    Layout.preferredWidth: 1
                    text: "Cancelar"
                    onClicked: driveFolderPopup.close()
                }
                CalButton {
                    Layout.fillWidth: true
                    Layout.preferredWidth: 1
                    tone: "primary"
                    text: "Guardar aquí"
                    // Solo dentro de una carpeta del proyecto (no en la raíz del espacio).
                    enabled: root._driveFolderParent.length > 0 && !root._driveJsonBusy
                    onClicked: {
                        if (root.saveDriveJson(root._driveFolderParent, true))
                            driveFolderPopup.close()
                    }
                }
            }
        }
    }

    // ===== Emergentes del flujo Calicatas (multiarchivo, abrir del proyecto,
    // alertas): mismo lenguaje que Ficha > General. Superficie limpia; solo
    // el multiarchivo (`glass: true`) usa Liquid Glass, con preset sutil por
    // instancia. Se animan opacity/scale/slideY; el backdrop se captura una vez.
    readonly property color calGenBlue: darkMode ? Mobile.InGeCoreFlow.colors.ingemaBlueTint : Mobile.InGeCoreFlow.colors.ingemaBlue
    readonly property color calGenBlueSoft: darkMode ? "#102B52" : Mobile.InGeCoreFlow.colors.ingemaBlueWash
    function calSolidSurface() { return flow ? flow.theme.surface : (darkMode ? "#081827" : "#FFFFFF") }

    // Fondo de los emergentes = el modal del peek "Información de la calicata": una
    // captura congelada 0.5x del contenido de la ventana (hermano del Overlay, nunca
    // incluye el emergente), desenfocada una vez con parámetros fijos, y una atenuación
    // ligera. Sigue la opacidad del emergente y se libera al cerrarlo.
    component CalGlassScrim: Item {
        id: calScrim
        // Fondo opaco y ya desenfocado: lo refractan los controles del emergente.
        objectName: "calicataGlassBackdrop"
        property var popupItem: null
        // Capa estable (no hereda la animación de opacidad de la raíz) para capturar.
        property Item glassLayer: null
        opacity: calScrim.popupItem ? calScrim.popupItem.opacity : 1
        Loader {
            anchors.fill: parent
            active: !!calScrim.popupItem && calScrim.popupItem.visible === true
            sourceComponent: Item {
                id: calScrimBlurLayer
                Rectangle { anchors.fill: parent; color: root.calBgColor() }
                Component.onCompleted: {
                    calScrim.glassLayer = calScrimBlurLayer
                    if (calScrim.popupItem && calScrim.popupItem.glassBackdropItem !== undefined)
                        calScrim.popupItem.glassBackdropItem = calScrimBlurLayer
                }
                Component.onDestruction: {
                    if (calScrim.glassLayer === calScrimBlurLayer) calScrim.glassLayer = null
                    if (calScrim.popupItem && calScrim.popupItem.glassBackdropItem === calScrimBlurLayer)
                        calScrim.popupItem.glassBackdropItem = null
                }
                ShaderEffectSource {
                    id: calScrimCapture
                    anchors.fill: parent
                    sourceItem: root._peekBackdropSource
                    textureSize: Qt.size(Math.max(1, Math.round(width * 0.5)), Math.max(1, Math.round(height * 0.5)))
                    live: false
                    hideSource: false
                    visible: false
                    Component.onCompleted: scheduleUpdate()
                }
                MultiEffect {
                    anchors.fill: parent
                    source: calScrimCapture
                    autoPaddingEnabled: false
                    blurEnabled: true
                    blurMax: 48
                    blur: 0.62
                    saturation: 0.30
                }
            }
        }
        Rectangle {
            anchors.fill: parent
            color: root.darkMode ? Mobile.InGeCoreFlow.colors.ingemaDeepShade : Mobile.InGeCoreFlow.colors.ingemaDeep
            opacity: root.darkMode ? 0.20 : 0.07
        }
    }

    component CalPopup: Popup {
        id: calPopup
        // Capa ya desenfocada que refracta el vidrio del panel (la registra su modal).
        property Item glassBackdropItem: null
        property real baseY: 0
        property real slideY: 0
        // Liquid Glass para todos los emergentes de Calicatas (mismo preset del peek).
        property bool glass: true
        readonly property int openMs: root.flow && root.flow.motionAllowed === false ? 0 : 200
        readonly property int closeMs: root.flow && root.flow.motionAllowed === false ? 0 : 150
        parent: Overlay.overlay
        modal: true
        focus: true
        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
        y: baseY + slideY
        padding: root.__dp(16)

        // Flat popups: plain dim. Glass popup (multiarchivo): the info peek's
        // backdrop — one frozen 0.5x grab, fixed blur, light dim — faded with the popup.
        Overlay.modal: Item {
            // Fondo ya desenfocado: lo refractan los controles del emergente (su capa
            // estable, que no hereda la animación de opacidad de este modal).
            objectName: "calicataGlassBackdrop"
            readonly property Item glassLayer: calPopup.glassBackdropItem
            opacity: calPopup.opacity
            Loader {
                anchors.fill: parent
                active: calPopup.glass && calPopup.visible
                sourceComponent: Item {
                    id: calPopupBlurLayer
                    Rectangle { anchors.fill: parent; color: root.calBgColor() }
                    Component.onCompleted: calPopup.glassBackdropItem = calPopupBlurLayer
                    Component.onDestruction: if (calPopup.glassBackdropItem === calPopupBlurLayer) calPopup.glassBackdropItem = null
                    ShaderEffectSource {
                        id: calBackdropCapture
                        anchors.fill: parent
                        sourceItem: root._peekBackdropSource
                        textureSize: Qt.size(Math.max(1, Math.round(width * 0.5)),
                                             Math.max(1, Math.round(height * 0.5)))
                        live: false
                        hideSource: false
                        visible: false
                        Component.onCompleted: scheduleUpdate()
                    }
                    MultiEffect {
                        anchors.fill: parent
                        source: calBackdropCapture
                        autoPaddingEnabled: false
                        blurEnabled: true
                        blurMax: 48
                        blur: 0.62
                        saturation: 0.30
                    }
                }
            }
            Rectangle {
                anchors.fill: parent
                color: calPopup.glass ? (infoPeek.dark ? Mobile.InGeCoreFlow.colors.ingemaDeepShade : Mobile.InGeCoreFlow.colors.ingemaDeep)
                                      : (root.darkMode ? Qt.rgba(0, 0, 0, 0.50) : Qt.rgba(0.0824, 0.102, 0.1882, 0.32))
                opacity: calPopup.glass ? (infoPeek.dark ? 0.22 : 0.10) : 1
            }
        }
        enter: Transition {
            ParallelAnimation {
                NumberAnimation { target: calPopup; property: "opacity"; from: 0; to: 1; duration: calPopup.openMs; easing.type: Easing.OutCubic }
                NumberAnimation { target: calPopup; property: "scale"; from: 0.975; to: 1; duration: calPopup.openMs; easing.type: Easing.OutCubic }
                NumberAnimation { target: calPopup; property: "slideY"; from: root.__dp(10); to: 0; duration: calPopup.openMs; easing.type: Easing.OutCubic }
            }
        }
        exit: Transition {
            ParallelAnimation {
                NumberAnimation { target: calPopup; property: "opacity"; to: 0; duration: calPopup.closeMs; easing.type: Easing.InCubic }
                NumberAnimation { target: calPopup; property: "scale"; to: 0.98; duration: calPopup.closeMs; easing.type: Easing.InCubic }
                NumberAnimation { target: calPopup; property: "slideY"; to: root.__dp(6); duration: calPopup.closeMs; easing.type: Easing.InCubic }
            }
        }

        background: Item {
            // Superficie primaria del emergente: lo anidado no la vuelve a capturar.
            objectName: "calicataGlassPrimary"
            RectangularShadow {
                anchors.fill: parent
                visible: !calPopup.glass
                radius: root.__dp(20)
                offset: Qt.vector2d(0, 4)
                blur: 18
                spread: -4
                color: Qt.rgba(0.0824, 0.102, 0.1882, root.darkMode ? 0.30 : 0.12)
            }
            Loader {
                anchors.fill: parent
                active: calPopup.glass
                sourceComponent: Component {
                    Item {
                        // Same material as the info peek: its tokens (shared with the
                        // Dock menu), its surface preset and its veil. Only the
                        // visibility/backdrop binding is this popup's.
                        QtObject {
                            id: calGlassTokens
                            readonly property bool shown: calPopup.visible
                            readonly property Item glassBackdrop: calPopup.visible
                                ? (calPopup.glassBackdropItem ? calPopup.glassBackdropItem : root._peekBackdropSource) : null
                            readonly property real materialPosition: 0
                            readonly property bool lowCostGlass: peekGlassTokens.lowCostGlass
                            readonly property color glassTint: peekGlassTokens.glassTint
                            // Opaco: Qt premultiplica los colores de un ShaderEffect; translúcido se pintaría gris.
                            readonly property color fallbackGlass: infoPeek.dark ? Qt.rgba(0.14, 0.16, 0.20, 1.0) : Qt.rgba(0.985, 0.99, 1.0, 1.0)
                            readonly property real rimLight: peekGlassTokens.rimLight
                            readonly property real rimShade: peekGlassTokens.rimShade
                            readonly property real rimSheen: peekGlassTokens.rimSheen
                            readonly property real edgeContrast: peekGlassTokens.edgeContrast
                            readonly property real glassSaturation: peekGlassTokens.glassSaturation
                            readonly property color shadowColor: peekGlassTokens.shadowColor
                        }
                        FlowCore.LiquidGlassSurface {
                            anchors.fill: parent
                            tokens: calGlassTokens
                            cornerRadius: root.__dp(30)
                            surfaceName: "calicata-tabs"
                            lens: 0.3
                            frost: 8
                            frostTaps: 6
                            magnify: 0
                            bevel: root.__dp(14)
                            elevation: true
                            // Captura viva justificada: fondo registrado estático (imagen congelada
                            // desenfocada); dirigida por eventos, se rehace solo al registrarse.
                            liveCapture: true
                            // Rect final sin transformar, recortado dentro del fondo.
                            captureRect: {
                                var b = calGlassTokens.glassBackdrop
                                if (!b || !calPopup.parent) return Qt.rect(0, 0, 0, 0)
                                var r = calPopup.parent.mapToItem(b, calPopup.x, calPopup.baseY, calPopup.width, calPopup.height)
                                var m = 6
                                var w = Math.min(r.width, b.width - 2 * m), h = Math.min(r.height, b.height - 2 * m)
                                return Qt.rect(Math.max(m, Math.min(r.x, b.width - w - m)), Math.max(m, Math.min(r.y, b.height - h - m)),
                                               Math.max(1, w), Math.max(1, h))
                            }
                        }
                    }
                }
            }
            Rectangle {
                anchors.fill: parent
                radius: root.__dp(calPopup.glass ? 30 : 20)
                // Glass: the info peek's legibility veil and hairline, verbatim.
                color: calPopup.glass
                       ? (infoPeek.dark ? Qt.rgba(0.0824, 0.102, 0.1882, 0.26) : Qt.rgba(0.98, 0.99, 1.0, 0.24))
                       : root.calSolidSurface()
                border.width: 1
                border.color: calPopup.glass
                              ? (infoPeek.dark ? Qt.rgba(1, 1, 1, 0.06) : Qt.rgba(1, 1, 1, 0.30))
                              : root.calBorderColor()
            }
        }
    }

    // tone: "plain" (borde) | "soft" (azul suave) | "primary" (azul lleno).
    component CalButton: Button {
        id: calBtn
        property string tone: "plain"
        property string iconName: ""
        readonly property color labelColor: calBtn.tone === "primary" ? (root.darkMode ? Mobile.InGeCoreFlow.colors.ingemaDeep : "#FFFFFF")
                                           : calBtn.tone === "soft" ? root.calGenBlue : root.calTextColor()
        implicitHeight: root.__dp(46)
        Layout.preferredHeight: implicitHeight
        padding: root.__dp(10)
        focusPolicy: Qt.NoFocus
        font.pixelSize: root.__sp(14)
        font.weight: Font.DemiBold
        scale: calBtn.down ? 0.985 : 1
        Behavior on scale { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
        background: CalicataLiquidGlass {
            dark: root.darkMode; accent: root.calGenBlue
            radius: root.__dp(12)
            tone: calBtn.tone === "primary" ? "primary" : calBtn.tone === "soft" ? "tinted" : "glass"
            pressed: calBtn.down
            enabledLook: calBtn.enabled
        }
        contentItem: Item {
            implicitWidth: calBtnRow.implicitWidth
            implicitHeight: calBtnRow.implicitHeight
            Row {
                id: calBtnRow
                anchors.centerIn: parent
                spacing: root.__dp(6)
                Components.FlowIcon {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: calBtn.iconName.length > 0
                    width: root.__dp(16)
                    height: root.__dp(16)
                    name: calBtn.iconName
                    flow: root.flow
                    tintColor: calBtn.labelColor
                    activeTintColor: calBtn.labelColor
                    inactiveOpacity: 1
                }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: calBtn.text
                    font: calBtn.font
                    color: calBtn.labelColor
                }
            }
        }
    }

    // Fila seleccionable (fichas abiertas / calicatas del proyecto).
    component CalRow: Rectangle {
        id: calRow
        property string title: ""
        property string subtitle: ""
        property string iconName: "calgen.code"
        property bool selected: false
        property color dotColor: "transparent"
        property string chipText: ""
        property color chipBg: "transparent"
        property color chipFg: root.calMutedColor()
        property bool showChevron: false
        property real trailingInset: 0
        signal activated()
        implicitHeight: Math.max(root.__dp(64), calRowText.implicitHeight + root.__dp(20))
        radius: root.__dp(14)
        color: "transparent"
        opacity: calRow.enabled ? 1 : 0.5
        scale: calRowTap.pressed ? 0.985 : 1
        Accessible.role: Accessible.Button
        Accessible.name: calRow.title
        Behavior on scale { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }

        CalicataLiquidGlass {
            dark: root.darkMode; accent: root.calGenBlue
            anchors.fill: parent
            radius: calRow.radius
            tone: calRow.selected ? "tinted" : "glass"
            selected: calRow.selected
            pressed: calRowTap.pressed
        }

        Rectangle {
            id: calRowBadge
            anchors.left: parent.left
            anchors.leftMargin: root.__dp(10)
            anchors.verticalCenter: parent.verticalCenter
            width: root.__dp(40)
            height: width
            radius: root.__dp(11)
            // La fila ya es vidrio: el contenedor del icono es solo la capa de acento.
            color: Qt.rgba(root.calGenBlue.r, root.calGenBlue.g, root.calGenBlue.b, calRow.selected ? 0.20 : (root.darkMode ? 0.18 : 0.10))
            Components.FlowIcon {
                anchors.centerIn: parent
                width: root.__dp(20)
                height: width
                name: calRow.iconName
                flow: root.flow
                tintColor: root.calGenBlue
                activeTintColor: root.calGenBlue
                inactiveOpacity: 1
            }
        }
        Column {
            id: calRowText
            anchors.left: calRowBadge.right
            anchors.leftMargin: root.__dp(12)
            anchors.right: calRowTrailing.left
            anchors.rightMargin: root.__dp(8)
            anchors.verticalCenter: parent.verticalCenter
            spacing: root.__dp(3)
            Text {
                width: parent.width
                text: calRow.title
                color: calRow.selected ? root.calGenBlue : root.calTextColor()
                font.pixelSize: root.__sp(15)
                font.weight: Font.DemiBold
                elide: Text.ElideRight
            }
            Item {
                width: parent.width
                height: calRowSubtitle.implicitHeight
                visible: calRow.subtitle.length > 0
                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: calRow.dotColor.a > 0
                    width: root.__dp(6)
                    height: width
                    radius: width / 2
                    color: calRow.dotColor
                }
                Text {
                    id: calRowSubtitle
                    x: calRow.dotColor.a > 0 ? root.__dp(12) : 0
                    width: parent.width - x
                    text: calRow.subtitle
                    color: root.calMutedColor()
                    font.pixelSize: root.__sp(12)
                    elide: Text.ElideRight
                }
            }
        }
        Row {
            id: calRowTrailing
            anchors.right: parent.right
            anchors.rightMargin: root.__dp(12) + calRow.trailingInset
            anchors.verticalCenter: parent.verticalCenter
            spacing: root.__dp(6)
            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                visible: calRow.chipText.length > 0
                width: calRowChip.implicitWidth + root.__dp(16)
                height: root.__dp(24)
                radius: height / 2
                color: calRow.chipBg
                Text {
                    id: calRowChip
                    anchors.centerIn: parent
                    text: calRow.chipText
                    color: calRow.chipFg
                    font.pixelSize: root.__sp(11)
                    font.weight: Font.DemiBold
                }
            }
            Components.FlowIcon {
                anchors.verticalCenter: parent.verticalCenter
                visible: calRow.showChevron
                width: root.__dp(16)
                height: width
                name: "calgen.chevron"
                flow: root.flow
                tintColor: root.calMutedColor()
                activeTintColor: root.calMutedColor()
                inactiveOpacity: 1
            }
        }
        MouseArea {
            id: calRowTap
            anchors.fill: parent
            anchors.rightMargin: calRow.trailingInset
            onClicked: calRow.activated()
        }
    }

    component WorkspaceMenuButton: Button {
        id: workspaceButton

        property bool primary: false
        property bool active: false
        property string iconName: ""

        implicitHeight: 44
        leftPadding: 10
        rightPadding: 10
        topPadding: 0
        bottomPadding: 0

        contentItem: RowLayout {
            spacing: root.__dp(8)

            Components.FlowIcon {
                visible: workspaceButton.iconName.length > 0
                Layout.preferredWidth: visible ? root.__dp(19) : 0
                Layout.preferredHeight: root.__dp(19)
                name: workspaceButton.iconName
                mirror: workspaceButton.iconName === "system.forward"
                flow: root.flow
                pressed: workspaceButton.down
                tintColor: workspaceButton.primary ? "#FFFFFF" : root.calAccentColor()
                activeTintColor: workspaceButton.active
                                 ? root.calAccentColor()
                                 : (workspaceButton.primary ? "#FFFFFF" : root.calAccentColor())
                active: workspaceButton.active
                inactiveOpacity: workspaceButton.enabled ? 1.0 : 0.42
            }

            Text {
                Layout.fillWidth: true
                text: workspaceButton.text
                color: !workspaceButton.enabled
                       ? root.calMutedColor()
                       : (workspaceButton.primary
                          ? "#FFFFFF"
                           : (workspaceButton.active
                              ? root.calAccentColor()
                             : root.calTextColor()))
                font.pixelSize: root.__sp(11)
                font.bold: workspaceButton.primary || workspaceButton.active
                horizontalAlignment: workspaceButton.iconName.length > 0
                                     ? Text.AlignLeft : Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
                elide: Text.ElideRight
            }
        }

        background: CalicataLiquidGlass {
            dark: root.darkMode
            accent: root.calAccentColor()
            radius: root.__dp(12)
            tone: workspaceButton.primary ? "primary" : workspaceButton.active ? "tinted" : "glass"
            selected: workspaceButton.active
            pressed: workspaceButton.down
            enabledLook: workspaceButton.enabled
        }
    }

    component NavFichaMenuButton: Button {
        id: navFichaButton

        property url svgSource: ""

        implicitHeight: 44
        leftPadding: 10
        rightPadding: 10
        topPadding: 0
        bottomPadding: 0

        contentItem: RowLayout {
            spacing: root.__dp(8)

            Image {
                Layout.preferredWidth: root.__dp(24)
                Layout.preferredHeight: root.__dp(24)
                source: navFichaButton.svgSource
                sourceSize.width: root.__dp(24)
                sourceSize.height: root.__dp(24)
                fillMode: Image.PreserveAspectFit
                smooth: true
                asynchronous: false
                opacity: navFichaButton.enabled ? 1.0 : 0.42
            }

            Text {
                Layout.fillWidth: true
                text: navFichaButton.text
                color: navFichaButton.enabled ? root.calTextColor() : root.calMutedColor()
                font.pixelSize: root.__sp(11)
                horizontalAlignment: Text.AlignLeft
                verticalAlignment: Text.AlignVCenter
                elide: Text.ElideRight
            }
        }

        background: CalicataLiquidGlass {
            dark: root.darkMode; accent: root.calGenBlue
            radius: root.__dp(12)
            pressed: navFichaButton.down
            enabledLook: navFichaButton.enabled
        }
    }

}

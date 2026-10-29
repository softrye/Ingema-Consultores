import QtQuick
import QtQuick.Controls
import QtQuick.Effects
import "RStyle.js" as S
import "../flowcore" as FlowCore

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
    readonly property bool editorActive: editorPopup.visible || draftPopup.visible || expandedId.length > 0
    readonly property bool renderInteractionBusy: editorActive || tileMenu.visible || sortMenu.visible
    ListModel { id: expensesModel }
    onVisibleExpensesChanged: S.syncRows(expensesModel, visibleExpenses, ["localId"])

    // ============ Edición de cajas (mismo sistema del Home, sin widgets) ============
    // Pulsación larga = modo edición; arrastrar reordena; ··· = tamaño y presentación.
    // Diseño por cuenta en el almacén local existente (saveEditorDraft, clave propia).
    readonly property string layoutKey: "layout:renditionsExpenses"
    property bool editMode: false
    property string dragKey: ""
    property bool dragChanged: false
    readonly property bool reduced: ui.reducedMotion === true
    property var layout: ({ metrics: { order: [], cfg: {} }, drafts: { order: [], cfg: {} } })
    readonly property var metricKeys: ["pen", "usd", "balance", "count"]
    ListModel { id: metricsModel }
    ListModel { id: draftsModel }
    function cfg(kind, key) {
        var c = ((layout[kind] || {}).cfg || {})[key] || {}
        var size = c.size
        if (!size) {                                  // por defecto: el último borrador impar ocupa todo el ancho
            size = "compact"
            if (kind === "drafts" && draftsModel.count % 2 === 1 && draftsModel.count > 0
                    && draftsModel.get(draftsModel.count - 1).itemKey === key) size = "wide"
        }
        return { size: size, presentation: c.presentation || "full" }
    }
    // Anchos que suman exactamente la fila (−0.5 px evita que el redondeo envíe una
    // caja a la fila siguiente y deje huecos horizontales).
    function tileWidth(kind, key, total, spacing) {
        var c = cfg(kind, key)
        var n = c.presentation === "icon" ? 4 : c.size === "small" ? 3 : c.size === "wide" ? 1 : 2
        return Math.floor((total - (n - 1) * spacing) / n) - (n > 1 ? 0.5 : 0)
    }
    property string focusKey: ""                 // caja con su menú 3D Touch abierto
    property Item focusTileItem: null            // la misma caja (la eleva el anfitrión global)
    function spanFor(kind, key) {
        var c = cfg(kind, key)
        return c.presentation === "icon" ? 3 : c.size === "small" ? 4 : c.size === "wide" ? 12 : 6
    }
    function syncModel(model, kind, keys) {
        var order = ((layout[kind] || {}).order || []).filter(function(k) { return keys.indexOf(k) >= 0 })
        keys.forEach(function(k) { if (order.indexOf(k) < 0) order.push(k) })
        for (var i = model.count - 1; i >= 0; --i) if (order.indexOf(model.get(i).itemKey) < 0) model.remove(i)
        for (var j = 0; j < order.length; ++j) {
            var at = -1
            for (var m = 0; m < model.count; ++m) if (model.get(m).itemKey === order[j]) at = m
            if (at < 0) model.insert(j, { itemKey: order[j] })
            else if (at !== j && dragKey.length === 0) model.move(at, j, 1)
        }
    }
    function syncAll() {
        syncModel(metricsModel, "metrics", metricKeys)
        syncModel(draftsModel, "drafts", drafts.map(function(d) { return String(d.id) }))
    }
    function loadLayout() {
        var stored = (app.st.editorDrafts || {})[layoutKey]
        if (stored && stored.metrics) layout = { metrics: stored.metrics, drafts: stored.drafts || { order: [], cfg: {} } }
        syncAll()
    }
    function saveLayout() {
        var l = { metrics: { order: [], cfg: (layout.metrics || {}).cfg || {} }, drafts: { order: [], cfg: (layout.drafts || {}).cfg || {} } }
        for (var i = 0; i < metricsModel.count; ++i) l.metrics.order.push(metricsModel.get(i).itemKey)
        for (var j = 0; j < draftsModel.count; ++j) l.drafts.order.push(draftsModel.get(j).itemKey)
        layout = l
        app.call("saveEditorDraft", { key: layoutKey, draft: l }, "")
    }
    function setCfg(kind, key, field, value) {
        var l = JSON.parse(JSON.stringify(layout))
        if (!l[kind]) l[kind] = { order: [], cfg: {} }
        var c = l[kind].cfg[key] || {}
        c[field] = value
        l[kind].cfg[key] = c
        layout = l
        saveLayout()
    }
    property var menuTile: null
    function enterEdit(tile) {
        editMode = true
        app.haptic("selection")
        if (tile) openTileMenu(tile)
    }
    function exitEdit() { editMode = false; dragKey = ""; focusKey = ""; focusTileItem = null; tileMenu.close() }
    function moveTo(kind, key, toStart) {
        var model = kind === "metrics" ? metricsModel : draftsModel
        for (var i = 0; i < model.count; ++i)
            if (model.get(i).itemKey === key) { model.move(i, toStart ? 0 : model.count - 1, 1); break }
        saveLayout()
    }
    function resetLayout() {
        layout = { metrics: { order: [], cfg: {} }, drafts: { order: [], cfg: {} } }
        metricsModel.clear(); draftsModel.clear()
        syncAll()
        saveLayout()
    }
    function chooseSize(size) {
        if (size === "icon") setCfg(menuTile.kind, menuTile.key, "presentation", "icon")
        else { setCfg(menuTile.kind, menuTile.key, "presentation", "full"); setCfg(menuTile.kind, menuTile.key, "size", size) }
        app.haptic("selection")
    }
    function openTileMenu(tile) {
        menuTile = { kind: tile.kind, key: tile.key }
        focusKey = tile.kind + ":" + tile.key
        focusTileItem = tileMenu.hosted ? tile : null
        if (tile.kind === "drafts") { selectedDraftId = tile.key; selectedDraftRenditionId = tab.detail.localId }
        // El menú sale pegado a la caja (debajo o, si no cabe, encima).
        var host = tileMenu.parent
        var p = tile.mapToItem(host, tile.width / 2, tile.height)
        tileMenu.anchorX = p.x; tileMenu.anchorY = p.y
        tileMenu.above = p.y > host.height * 0.55
        if (tileMenu.above) tileMenu.anchorY = tile.mapToItem(host, 0, 0).y
        tileMenu.open = true
    }
    function dragOver(tile, point) {
        var model = tile.kind === "metrics" ? metricsModel : draftsModel
        var siblings = tile.parent ? tile.parent.children : []
        for (var i = 0; i < siblings.length; ++i) {
            var other = siblings[i]
            if (other === tile || other.kind !== tile.kind || !other.key) continue
            if (point.x >= other.x && point.x <= other.x + other.width && point.y >= other.y && point.y <= other.y + other.height) {
                var from = -1, to = -1
                for (var m = 0; m < model.count; ++m) {
                    if (model.get(m).itemKey === tile.key) from = m
                    if (model.get(m).itemKey === other.key) to = m
                }
                if (from >= 0 && to >= 0 && from !== to) { model.move(from, to, 1); dragChanged = true }
                break
            }
        }
    }
    function endDrag() {
        dragKey = ""
        if (dragChanged) { dragChanged = false; saveLayout() }
    }
    function draftById(id) {
        for (var i = 0; i < drafts.length; ++i) if (String(drafts[i].id) === id) return drafts[i]
        return null
    }
    onDraftsChanged: syncAll()
    Component.onCompleted: {
        loadLayout()
        S.syncRows(expensesModel, visibleExpenses, ["localId"])
    }
    // Buscar del Dock (imagen 2): texto y orden sobre los gastos REALES de la ficha.
    property string query: ""
    property string sortBy: "date"              // concept | date | category | beneficiary | project
    property string expandedId: ""              // identidad estable del gasto en la ventana de edición
    property var editingExpense: null
    property bool closingEditor: false
    function handleBack() {
        if (editorMenu.open) { editorMenu.close(); return true }       // «···» del editor
        if (tileMenu.open) { tileMenu.close(); return true }
        if (editMode) { exitEdit(); return true }             // Atrás sale del modo edición (como el Home)
        if (draftPopup.visible) { draftMenu.close(); return true }
        if (!expandedId.length) return false
        if (closingEditor) return true
        if (quickForm.saving) return true
        quickForm.requestClose()
        return true
    }
    function expand(row) {
        if (quickForm.saving) return
        if (expandedId.length) return
        tab.app.closeMenus()
        editingExpense = row
        expandedId = String(row.localId)
        quickForm.section = 0
        editorPopup.open()
    }
    function finishEditor() {
        closingEditor = true
        editorPopup.close()
        if (!editorPopup.visible) clearEditor()
        Qt.inputMethod.hide()
    }
    function clearEditor() {
        expandedId = ""
        editingExpense = null
        closingEditor = false
    }
    function persistExpanded() { if (expandedId.length) quickForm.persistLocal() }
    readonly property bool expenseSaveInProgress: quickForm.saving
    function decimalCents(value) {
        var digits = String(Math.abs(value)).padStart(3, "0")
        return (value < 0 ? "-" : "") + digits.slice(0, -2) + "." + digits.slice(-2)
    }
    readonly property real pull: Math.max(0, expenseFlick.originY - expenseFlick.contentY)
    function expenseIcon(row) {
        var label = catalogLabel("CATEGORY", S.text_(row, "categoryCode", "category_code")).toLowerCase()
        // Iconos de pago/documento ya utilizados por el editor completo.
        return label.indexOf("transport") >= 0 || label.indexOf("pasaje") >= 0 ? 0xE0AA
             : label.indexOf("comida") >= 0 || label.indexOf("alimenta") >= 0 ? 0xE052 : 0xE0CC
    }
    function registeredCategory(row) {
        var label = catalogLabel("CATEGORY", S.text_(row, "categoryCode", "category_code")).toLowerCase()
        return label.indexOf("transport") >= 0 || label.indexOf("pasaje") >= 0 || label.indexOf("taxi") >= 0
            ? { glyph: 0xE1D5, tone: S.accentSoft }
            : label.indexOf("comida") >= 0 || label.indexOf("alimenta") >= 0
            ? { glyph: 0xE2F6, tone: "#F28C28" } : { glyph: 0xE0CC, tone: S.accentSoft }
    }
    // Gasto nuevo en el editor modal aprobado (misma copia local que el «+»).
    function createExpense() {
        if (quickForm.saving || expandedId.length) return
        tab.app.closeMenus()
        editingExpense = null
        expandedId = "new"
        quickForm.section = 0
        editorPopup.open()
        editorFlick.contentY = 0
        quickForm.focusConcept()
    }
    readonly property var expandedRow: {
        if (!expandedId.length) return null
        var rows = tab.app.st.expenses || []
        for (var i = 0; i < rows.length; ++i)
            if (String(rows[i].localId) === expandedId) return rows[i]
        return editingExpense
    }
    readonly property var sortLabels: ({ concept: "concepto", date: "fecha", category: "categoría", beneficiary: "proveedor", project: "proyecto" })
    function catalogLabel(kind, code) {
        var rows = ctl.catalog(kind)
        for (var i = 0; i < rows.length; ++i) if (S.text_(rows[i], "code") === code) return S.text_(rows[i], "name") || S.text_(rows[i], "label") || code
        return code
    }
    function keyOf(e, key) {
        if (key === "date") return S.text_(e, "expenseDate", "expense_date")
        if (key === "category") return catalogLabel("CATEGORY", S.text_(e, "categoryCode", "category_code")).toLowerCase()
        if (key === "beneficiary") return S.text_(e, "beneficiary").toLowerCase()
        if (key === "project") return ctl.projectLabel(S.text_(e, "projectId", "project_id")).toLowerCase()
        return S.text_(e, "concept").toLowerCase()
    }
    readonly property var visibleExpenses: {
        var q = query.trim().toLowerCase()
        var list = expenses.filter(function(e) {
            if (!q.length) return true
            return ["concept", "beneficiary", "category", "project", "date"].some(function(k) { return tab.keyOf(e, k).indexOf(q) >= 0 })
                   || S.date(S.text_(e, "expenseDate", "expense_date")).indexOf(q) >= 0
        })
        if (sortBy.length) list = list.slice().sort(function(a, b) {
            var x = tab.keyOf(a, sortBy), y = tab.keyOf(b, sortBy)
            return sortBy === "date" ? (x < y ? 1 : x > y ? -1 : 0) : (x < y ? -1 : x > y ? 1 : 0)
        })
        return list
    }
    // Borradores en la nube (Working Document): filas sin terminar, propias o de
    // otra sesión/dispositivo. No son gastos contables hasta registrarse.
    readonly property var drafts: detail.selected ? (app.st.workingRows || []) : []
    // Identidad estable fuera del delegado: la sincronización puede recrear las boxes.
    property string selectedDraftId: ""
    property string selectedDraftRenditionId: ""
    readonly property var menuDraft: currentDraft()
    function currentDraft() {
        if (!tab.detail.selected || tab.selectedDraftRenditionId !== tab.detail.localId) return null
        for (var i = 0; i < tab.drafts.length; ++i)
            if (String(tab.drafts[i].id) === tab.selectedDraftId) return tab.drafts[i]
        return null
    }
    function draftActionAllowed(d, action) {
        return !!d && tab.detail.writable && d.syncState !== "CONFLICT"
            && !d.promoteRequested && !d.archiveRequested && !tab.app.busy("working:" + d.id)
            && ["Continuar", "Registrar", "Descartar"].indexOf(action) >= 0
            && (action !== "Registrar" || Number(d.missingSources || 0) === 0)
    }
    function runDraftAction(action) {
        var d = tab.currentDraft()
        if (!tab.draftActionAllowed(d, action)) return
        draftMenu.close()
        if (action === "Continuar") tab.app.openExpense(tab.detail.localId, String(d.expenseLocalId || ""), d.id)
        else if (action === "Registrar") tab.promote(d)
        else tab.discard(d)
    }
    function openDraftMenu(d, source, x, y) {
        if (draftPopup.visible || tab.app.modalOpen) return
        tab.app.closeMenus()
        selectedDraftId = String(d.id)
        selectedDraftRenditionId = tab.detail.localId
        var point = source.mapToItem(draftPopup.parent, x, y)
        draftMenu.anchorX = point.x
        draftMenu.originY = point.y
        draftPopup.open()
        draftMenu.open = true
    }
    onMenuDraftChanged: if (!menuDraft) draftMenu.close()
    onVisibleChanged: if (!visible) draftMenu.close()
    // Borradores en boxes de dos columnas. Los conflictos ocupan el ancho entero
    // para que las diferencias y acciones de reconciliación sean legibles.
    readonly property var draftRows: {
        var groups = [], pair = []
        for (var i = 0; i < drafts.length; ++i) {
            if (String(drafts[i].syncState || "") === "CONFLICT") {
                if (pair.length) { groups.push(pair); pair = [] }
                groups.push([drafts[i]])
            } else {
                pair.push(drafts[i])
                if (pair.length === 2) { groups.push(pair); pair = [] }
            }
        }
        if (pair.length) groups.push(pair)
        return groups
    }
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
                if (ok && tab.life.alive && tab.expandedId === String(expense.localId)) tab.finishEditor()
                tab.app.toast(ok ? "Gasto eliminado en el equipo · pendiente de sincronizar." : tab.app.errorText(code, message),
                              ok ? "success" : "error")
            })
        })
    }

    // La capa modal pertenece sólo al selector: bloquea gestos incluso sobre el Dock
    // sin cambiar su diseño, sus acciones ni el RGlassMenu compartido.
    Popup {
        // Entrada/salida suaves (fundido + leve escala), como el resto de hojas.
        enter: Transition { NumberAnimation { property: "opacity"; from: 0; to: 1; duration: 180; easing.type: Easing.OutCubic }
                            NumberAnimation { property: "scale"; from: 0.96; to: 1; duration: 220; easing.type: Easing.OutCubic } }
        exit: Transition { NumberAnimation { property: "opacity"; from: 1; to: 0; duration: 140; easing.type: Easing.InCubic } }
        id: draftPopup
        objectName: "draftContextPopup"
        parent: Overlay.overlay
        x: 0; y: 0
        width: parent ? parent.width : 0
        height: parent ? parent.height : 0
        padding: 0
        margins: 0
        modal: true
        dim: false
        focus: true
        closePolicy: Popup.CloseOnEscape
        background: null
        onAboutToHide: draftMenu.close()
        contentItem: RGlassMenu {
            id: draftMenu
            objectName: "draftContextMenu"
            ui: tab.ui
            cardWidth: 272 * tab.ui.u
            property real originY: 0
            // Coordenadas de la misma capa que el Popup. La reserva sigue al Dock real.
            readonly property real dockTop: tab.app.dockAnchor
                ? Math.min(height - tab.ui.dockArea,
                           tab.app.dockAnchor.mapToItem(draftPopup.parent, 0, 0).y)
                : height - tab.ui.dockArea
            viewportBottom: Math.max(0, Math.min(height, dockTop - 8 * tab.ui.u))
            readonly property real actionHeight: Math.max(0, Math.min(52 * tab.ui.u,
                (viewportBottom - 2 * margin - 38 * tab.ui.u) / 3))
            // RGlassMenu emerge hacia arriba; subir el origen evita desbordes arriba.
            anchorY: Math.max(3 * actionHeight + 38 * tab.ui.u + margin,
                             Math.min(originY, viewportBottom - margin))
            onVisibleChanged: if (!visible) draftPopup.close()
            Keys.onEscapePressed: close()
            Repeater {
                model: ["Continuar", "Registrar", "Descartar"]
                delegate: RButton {
                    required property string modelData
                    objectName: "draftAction:" + modelData
                    ui: tab.ui
                    width: parent.width
                    height: draftMenu.actionHeight
                    label: modelData
                    primary: modelData === "Registrar"
                    danger: modelData === "Descartar"
                    color: primary ? S.accent : S.glass(0.62)
                    enabledButton: tab.draftActionAllowed(tab.menuDraft, modelData)
                    onActivated: tab.runDraftAction(modelData)
                }
            }
        }
    }

    // Mismo Popup modal empleado por los controles y confirmaciones existentes.
    // La instancia del formulario vive fuera de los delegados y del scroll de fondo.
    Popup {
        id: editorPopup
        objectName: "expenseEditorPopup"
        parent: Overlay.overlay
        readonly property bool compactViewport: height < 400 * tab.ui.u
        readonly property real safeTop: tab.ui.topInset + 8 * tab.ui.u
        readonly property real keyboardTop: {
            var rect = Qt.inputMethod.keyboardRectangle
            if (!parent || !Qt.inputMethod.visible || rect.height <= 0) return parent ? parent.height : 0
            return Math.max(0, Math.min(parent.height, parent.mapFromItem(null, rect.x, rect.y).y))
        }
        readonly property real safeBottom: Math.min(keyboardTop,
            parent ? parent.height - (Qt.inputMethod.visible ? 0 : tab.ui.dockArea) : 0)
        width: Math.max(0, Math.min(parent ? parent.width - 20 * tab.ui.u : 0, 860 * tab.ui.u))
        height: Math.max(0, Math.min(760 * tab.ui.u, safeBottom - safeTop - 8 * tab.ui.u))
        x: parent ? (parent.width - width) / 2 : 0
        y: Math.max(safeTop, safeBottom - height - 8 * tab.ui.u)
        padding: 16 * tab.ui.u
        modal: true
        dim: true
        focus: true
        closePolicy: Popup.NoAutoClose
        // Vidrio: la subapp de fondo se desenfoca y la hoja translúcida deja verla.
        Overlay.modal: Item {
            opacity: editorPopup.opacity
            // Freeze the same blurred backdrop while typing. Sampling the
            // live subapp repainted its animated auras and RPC updates behind
            // every keystroke even though the modal already blocks input.
            ShaderEffectSource {
                id: editorBackdrop
                objectName: "expenseEditorBackdrop"
                width: tab.app ? tab.app.width : 0
                height: tab.app ? tab.app.height : 0
                sourceItem: editorPopup.visible ? tab.app : null
                live: false
                hideSource: false
                visible: false
                smooth: true
            }
            MultiEffect {
                readonly property point origin: tab.app ? tab.app.mapToItem(null, 0, 0) : Qt.point(0, 0)
                x: origin.x; y: origin.y
                width: tab.app ? tab.app.width : 0; height: tab.app ? tab.app.height : 0
                visible: editorBackdrop.sourceItem !== null
                source: visible ? editorBackdrop : null
                autoPaddingEnabled: false
                blurEnabled: true; blurMax: 48; blur: 0.8
                saturation: -0.1
            }
            Rectangle { anchors.fill: parent; color: Qt.rgba(21 / 255, 26 / 255, 48 / 255, 0.26) }
        }
        background: Rectangle {
            radius: 30 * tab.ui.u
            gradient: Gradient {
                GradientStop { position: 0.0; color: S.glass(0.86) }
                GradientStop { position: 1.0; color: S.lite(243, 246, 251, 0.80) }
            }
            border.width: 2; border.color: S.edge(0.95)
            Rectangle { anchors.fill: parent; anchors.margins: -2 * tab.ui.u; radius: parent.radius + 2 * tab.ui.u
                        color: "transparent"; border.width: 2; border.color: Qt.rgba(6 / 255, 84 / 255, 162 / 255, 0.18) }
        }
        enter: Transition {
            NumberAnimation { properties: "opacity,scale"; from: 0.95; to: 1; duration: tab.ui.reducedMotion ? 0 : 180; easing.type: Easing.OutCubic }
        }
        exit: Transition {
            NumberAnimation { property: "opacity"; from: 1; to: 0; duration: tab.ui.reducedMotion ? 0 : 140 }
        }
        onOpened: editorContent.forceActiveFocus()
        onClosed: if (tab.closingEditor) tab.clearEditor()
        contentItem: Item {
            id: editorContent
            Keys.onEscapePressed: quickForm.requestClose()
            Rectangle {
                id: dragGrip
                width: parent.width; height: (editorPopup.compactViewport ? 12 : 18) * tab.ui.u
                color: "transparent"
                Rectangle { anchors.horizontalCenter: parent.horizontalCenter; y: 2 * tab.ui.u
                            width: 36 * tab.ui.u; height: 4 * tab.ui.u; radius: height / 2; color: S.ink(0.20) }
                DragHandler {
                    target: null
                    xAxis.enabled: false
                    onActiveChanged: if (!active && translation.y > 48 * tab.ui.u && !quickForm.dirty && !quickForm.saving) quickForm.requestClose()
                }
            }
            Item {
                id: expenseHeader
                anchors.top: dragGrip.bottom
                width: parent.width; height: 52 * tab.ui.u
                RButton {
                    anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter
                    width: 44 * tab.ui.u; height: width; radius: width / 2
                    ui: tab.ui; glyph: 0xE1B2; enabledButton: !quickForm.saving
                    color: S.glass(0.6)
                    Accessible.name: "Cerrar edición"
                    onActivated: quickForm.requestClose()
                }
                Column {
                    anchors.centerIn: parent
                    width: parent.width - 120 * tab.ui.u
                    Text { width: parent.width; horizontalAlignment: Text.AlignHCenter; text: quickForm.isNew ? "Nuevo gasto" : "Editar gasto"
                           color: S.text; font.family: tab.ui.fontFamily; font.pixelSize: 16 * tab.ui.u; font.weight: Font.Bold }
                    Text { width: parent.width; horizontalAlignment: Text.AlignHCenter; text: quickForm.dirty ? "Cambios sin guardar" : "Sin cambios"
                           color: S.muted; font.family: tab.ui.fontFamily; font.pixelSize: 12 * tab.ui.u }
                }
                RButton {
                    objectName: "expenseEditorMore"
                    anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                    width: 44 * tab.ui.u; height: width; radius: width / 2
                    ui: tab.ui; glyph: 0xE0B6; enabledButton: !quickForm.saving
                    color: S.glass(0.6)
                    Accessible.name: "Más opciones"
                    onActivated: {
                        var p = mapToItem(editorContent, width / 2, height)
                        editorMenu.anchorX = p.x; editorMenu.anchorY = p.y
                        editorMenu.open = true
                    }
                }
            }
            FlowCore.ImeAwareFlickable {
                id: editorFlick
                objectName: "expenseEditorScroll"
                flow: tab.app.flow
                restoreOnImeClose: false
                imeTopMargin: stickyTabs.visible ? stickyTabs.height + 8 * tab.ui.u : 12
                anchors.top: expenseHeader.bottom; anchors.topMargin: 6 * tab.ui.u
                anchors.bottom: editorActions.top; anchors.bottomMargin: 10 * tab.ui.u
                width: parent.width
                contentWidth: width; contentHeight: quickForm.implicitHeight + 8 * tab.ui.u
                clip: true; boundsBehavior: Flickable.StopAtBounds
                RExpenseQuickForm {
                    id: quickForm
                    objectName: "expandedExpenseForm"
                    width: parent.width
                    app: tab.app; renditionLocalId: tab.detail.localId; expense: tab.expandedRow
                    modalEditor: true
                    onFinished: function(saved) { tab.finishEditor() }
                    onDeleteRequested: if (tab.expandedRow && !saving) tab.remove(tab.expandedRow)
                    onOpenFullForm: quickForm.openAdvanced()
                    // La pantalla no salta: si la barra estaba fijada arriba, la
                    // sección nueva empieza justo debajo de ella.
                    onSectionChanged: Qt.callLater(function() {
                        var y = Math.min(editorFlick.contentY, quickForm.tabsBarY)
                        editorFlick.contentY = Math.max(0, Math.min(y, editorFlick.contentHeight - editorFlick.height))
                    })
                }
            }
            // Pestañas fijas: aparecen pegadas arriba cuando la barra real sale de la vista.
            Rectangle {
                id: stickyTabs
                objectName: "expenseEditorStickyTabs"
                anchors.top: editorFlick.top
                width: parent.width; height: quickForm.tabsBarHeight; radius: 16 * tab.ui.u
                color: S.track
                visible: editorPopup.visible && quickForm.modalEditor && editorFlick.contentY > quickForm.tabsBarY + 1
                z: 5
                Rectangle { anchors.fill: parent; anchors.topMargin: -editorFlick.anchors.topMargin; z: -1; color: S.glass(0.92); radius: 16 * tab.ui.u }
                Rectangle {                                  // píldora deslizante del selector
                    readonly property real cell: (stickyRow.width - (4 - 1) * stickyRow.spacing) / Math.max(1, 4)
                    visible: true
                    x: stickyRow.x + (quickForm.section) * (cell + stickyRow.spacing)
                    y: stickyRow.y
                    width: cell; height: stickyRow.height; radius: 12 * tab.ui.u
                    color: S.pill()
                    Behavior on x { enabled: tab.ui.reducedMotion !== true
                                    SpringAnimation { spring: 4.2; damping: 0.38; epsilon: 0.25 } }
                }
                TextMetrics { id: stickyMetrics; font.family: tab.ui.fontFamily; font.pixelSize: 11 * tab.ui.u; font.bold: true; text: "Comprobante" }
                Row {
                    id: stickyRow
                    readonly property real labelPx: Math.min(11 * tab.ui.u, 11 * tab.ui.u * ((width - 3 * spacing) / 4 - 8 * tab.ui.u) / Math.max(1, stickyMetrics.advanceWidth))
                    anchors.fill: parent; anchors.margins: 4 * tab.ui.u; spacing: 4 * tab.ui.u
                    Repeater {
                        model: ["General", "Comprobante", "Pago", "Sustentos"]
                        delegate: Rectangle {
                            id: stickyCell
                            required property string modelData
                            required property int index
                            readonly property bool selected: quickForm.section === index
                            width: (stickyRow.width - 3 * stickyRow.spacing) / 4; height: stickyRow.height
                            radius: 12 * tab.ui.u
                            color: "transparent"
                            Text { anchors.centerIn: parent; width: parent.width - 6 * tab.ui.u; horizontalAlignment: Text.AlignHCenter
                                   text: stickyCell.modelData; color: stickyCell.selected ? S.accent : S.text
                                   elide: Text.ElideRight
                                   font.family: tab.ui.fontFamily; font.pixelSize: stickyRow.labelPx; font.weight: stickyCell.selected ? Font.Bold : Font.DemiBold }
                            MouseArea { anchors.fill: parent; onClicked: quickForm.selectSection(stickyCell.index) }
                            Accessible.role: Accessible.Button
                            Accessible.name: modelData
                            Accessible.checked: selected
                        }
                    }
                }
            }
            Rectangle {                                   // aviso del dato que falta (antes no se veía)
                visible: quickForm.error.length > 0
                anchors.bottom: editorActions.top; anchors.bottomMargin: 8 * tab.ui.u
                width: parent.width; height: editorError.implicitHeight + 16 * tab.ui.u; radius: 12 * tab.ui.u
                color: S.dark ? "#3A1A1F" : "#FDECEE"; border.width: 1; border.color: Qt.rgba(198 / 255, 47 / 255, 62 / 255, 0.35)
                Text { id: editorError; x: 12 * tab.ui.u; width: parent.width - 24 * tab.ui.u; anchors.verticalCenter: parent.verticalCenter
                       text: quickForm.error; color: S.danger; wrapMode: Text.WordWrap
                       font.family: tab.ui.fontFamily; font.pixelSize: 13.5 * tab.ui.u; font.weight: Font.DemiBold }
            }
            Row {
                id: editorActions
                anchors.bottom: parent.bottom
                width: parent.width; height: 52 * tab.ui.u; spacing: 10 * tab.ui.u
                // Sólo dos acciones; Eliminar vive en «···» lejos de Guardar.
                RButton { ui: tab.ui; width: (editorActions.width - editorActions.spacing) / 3; height: parent.height; label: "Cancelar"; radius: 16 * tab.ui.u
                          enabledButton: !quickForm.saving; color: S.cardGlass; onActivated: quickForm.requestClose() }
                RButton { objectName: "modalExpenseSave"; ui: tab.ui; width: (editorActions.width - editorActions.spacing) * 2 / 3; height: parent.height
                          label: "Guardar"; glyph: 0xE06C; primary: true; radius: 16 * tab.ui.u
                          enabledButton: quickForm.writable; busy: quickForm.saving; onActivated: quickForm.save() }
            }
            RGlassMenu {
                id: editorMenu
                objectName: "expenseEditorMenu"
                ui: tab.ui
                above: false
                cardWidth: 250 * tab.ui.u
                bottomInset: 0
                RMenuItem { ui: tab.ui; label: "Formulario completo (IGV)"; glyph: 0xE0CC; glyphColor: S.accent
                            enabledItem: !quickForm.saving
                            onActivated: { editorMenu.close(); quickForm.openAdvanced() } }
                RMenuItem { objectName: "expenseEditorDelete"; ui: tab.ui; label: "Eliminar gasto"; glyph: 0xE18E; glyphColor: S.danger; separator: false
                            visible: !quickForm.isNew
                            enabledItem: quickForm.writable && !quickForm.saving && !tab.app.busy("deleteExpense:" + tab.expandedId)
                            onActivated: { editorMenu.close(); if (tab.expandedRow) tab.remove(tab.expandedRow) } }
            }
        }
        Connections {
            target: tab
            function onVisibleChanged() {
                if (!tab.visible && editorPopup.visible) {
                    if (quickForm.saving || tab.closingEditor) return
                    // El editor avanzado ya recibió y confirmó el borrador local.
                    if (quickForm.suspendedForAdvanced) {
                        editorPopup.close()
                        return
                    }
                    // Al cambiar de pestaña jamás cerrar antes de que la copia
                    // local confirme la revisión exacta que estaba en pantalla.
                    var revision = quickForm.editRevision
                    var key = quickForm.draftKey
                    quickForm.persistLocal(function(ok) {
                        if (ok && !tab.visible && tab.expandedId.length
                                && quickForm.draftKey === key
                                && quickForm.editRevision === revision && !quickForm.saving)
                            tab.finishEditor()
                        else if (ok && !tab.visible)
                            quickForm.error = "Hay cambios posteriores. Revisa la edición antes de cerrar."
                    })
                } else if (tab.visible && tab.expandedId.length && quickForm.suspendedForAdvanced) {
                    editorPopup.open()
                }
            }
        }
    }

    FlowCore.ImeAwareFlickable {
        id: expenseFlick
        flow: tab.app.flow
        anchors.fill: parent
        interactive: !tab.app.modalOpen && !draftPopup.visible && !editorPopup.visible
        contentWidth: width
        contentHeight: column.height + 140 * tab.ui.u
        boundsBehavior: Flickable.DragOverBounds
        onDraggingChanged: if (!dragging && tab.pull >= tab.detail.pullThreshold) tab.detail.refreshFromPull()
        clip: true
        Column {
            id: column
            x: tab.ui.gutter
            width: parent.width - 2 * tab.ui.gutter
            spacing: 12 * tab.ui.u

            RChip {                                   // salir del modo edición (como "Listo" del Home)
                objectName: "editBoxesDone"
                visible: tab.editMode
                ui: tab.ui
                label: "Listo"
                selected: true
                onActivated: tab.exitEdit()
            }
            // Resumen financiero compacto (imagen 2, vista general): valores REALES.
            RCard {
                objectName: "expenseSummaryContainer"
                width: parent.width
                ui: tab.ui
                color: S.cardGlass
                radius: 26 * tab.ui.u
                border.color: S.edge(0.93)
                RPackedLayout {
                    id: summaryGrid
                    objectName: "expenseSummary"
                    width: parent.width
                    spacing: 10 * tab.ui.u
                    spanOf: function(it) { return tab.spanFor(it.kind, it.key) }
                    layoutTrigger: tab.layout
                    readonly property var bal: tab.detail.balance || ({})
                    // Conversión de presentación mediante el mismo cálculo entero C++
                    // del saldo común; no altera totales, IGV ni importes guardados.
                    readonly property var equivalent: tab.totals.error ? ({}) : tab.ctl.fundBalance({
                        funding: { enabled: true, pen: "0", usd: "0" }, exchangeRate: tab.detail.rate,
                        totalPen: tab.decimalCents(tab.totals.penCents), totalUsd: tab.decimalCents(tab.totals.usdCents)
                    })
                    readonly property var metricData: ({ pen: { value: !tab.detail.expensesKnown || tab.totals.error ? "—"
                                     : summaryGrid.equivalent.penCents !== undefined && summaryGrid.equivalent.penCents !== null
                                     ? tab.ctl.formatCents(-summaryGrid.equivalent.penCents, "PEN") : "Definir en Finanzas", label: "Gastos (Soles)", glyph: 0xE204, tone: S.accent },
                                 usd: { value: !tab.detail.expensesKnown ? "—" : summaryGrid.equivalent.usdCents !== undefined && summaryGrid.equivalent.usdCents !== null
                                     ? tab.ctl.formatCents(-summaryGrid.equivalent.usdCents, "USD") : "Definir en Finanzas", label: "Equivalente en dólares", glyph: 0xE47D, tone: "#2EB872" },
                                 balance: { value: summaryGrid.bal.enabled && summaryGrid.bal.penCents !== undefined && summaryGrid.bal.penCents !== null
                                     ? tab.ctl.formatCents(summaryGrid.bal.penCents, "PEN") : summaryGrid.bal.enabled ? "No disponible" : "Sin fondo", label: "Saldo del fondo", glyph: 0xE3BE, tone: "#F28C28" },
                                 count: { value: tab.detail.expensesKnown ? String(tab.totals.count || 0) : "—", label: "N.º de gastos", glyph: 0xE106, tone: "#8B5CF6" } })
                    Repeater {
                        model: metricsModel
                        delegate: REditableTile {
                            id: metricTile
                            required property string itemKey
                            required property int index
                            ui: tab.ui; owner: tab; kind: "metrics"; key: itemKey; order: index
                            readonly property bool iconOnly: tab.cfg("metrics", itemKey).presentation === "icon"
                            iconPresentation: iconOnly
                            width: tab.tileWidth("metrics", itemKey, summaryGrid.width, summaryGrid.spacing)
                        Rectangle {
                            id: metric
                            readonly property var modelData: summaryGrid.metricData[metricTile.itemKey]
                            readonly property color tone: modelData.tone
                            objectName: "expenseMetric:" + modelData.label
                            width: parent.width
                            Accessible.name: modelData.label + ": " + modelData.value
                            height: 72 * tab.ui.u
                            radius: 18 * tab.ui.u
                            color: S.cardGlass
                            border.width: 1; border.color: S.edge(0.9)
                            Rectangle {
                                id: metricIcon
                                x: metricTile.iconOnly ? (metric.width - width) / 2 : 9 * tab.ui.u
                                width: (metric.width < 148 * tab.ui.u ? 32 : 42) * tab.ui.u
                                height: width
                                radius: 15 * tab.ui.u
                                anchors.verticalCenter: parent.verticalCenter
                                color: Qt.rgba(metric.tone.r, metric.tone.g, metric.tone.b, 0.18)
                                // Misma selección tintada y borde claro de las boxes de Rendiciones.
                                border.width: 2 * tab.ui.u
                                border.color: S.edge(0.85)
                                Text { anchors.centerIn: parent; text: String.fromCharCode(metric.modelData.glyph)
                                       color: metric.tone; font.family: tab.ui.iconFamily; font.pixelSize: parent.width * 0.58 }
                            }
                            Column {
                                visible: !metricTile.iconOnly
                                x: metricIcon.x + metricIcon.width + 7 * tab.ui.u
                                width: parent.width - x - 8 * tab.ui.u
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: 4 * tab.ui.u
                                Text { width: parent.width; text: metric.modelData.label; color: S.muted; wrapMode: Text.WordWrap
                                       font.family: tab.ui.fontFamily; font.pixelSize: 10.5 * tab.ui.u }
                                Text { width: parent.width; height: 29 * tab.ui.u; text: metric.modelData.value; color: S.text
                                       font.family: tab.ui.fontFamily; font.pixelSize: 20 * tab.ui.u; font.weight: Font.Bold
                                       fontSizeMode: Text.Fit; minimumPixelSize: 10 * tab.ui.u; wrapMode: Text.WrapAtWordBoundaryOrAnywhere }
                            }
                        }
                        }
                    }
                }
            }
            Text {
                width: parent.width
                visible: !!tab.totals.error
                text: "Hay un importe no válido en los gastos."
                color: S.danger; wrapMode: Text.WordWrap
                font.family: tab.ui.fontFamily; font.pixelSize: 13 * tab.ui.u
            }

            // ---- Borradores sin registrar (Working Document)
            Text {
                width: parent.width
                visible: tab.drafts.length > 0
                topPadding: 4 * tab.ui.u
                text: tab.drafts.length === 1 ? "1 borrador sin registrar" : tab.drafts.length + " borradores sin registrar"
                color: S.text; font.family: tab.ui.fontFamily; font.pixelSize: 17 * tab.ui.u; font.weight: Font.DemiBold
            }
            RPackedLayout {
                id: draftFlow
                objectName: "draftBoxes"
                width: parent.width
                spacing: 10 * tab.ui.u
                spanOf: function(it) { return tab.spanFor(it.kind, it.key) }
                layoutTrigger: tab.layout
                Repeater {
                    model: draftsModel
                    delegate: REditableTile {
                        id: draftTile
                        required property string itemKey
                        required property int index
                        readonly property var draft: tab.draftById(itemKey)
                        // El contenido de la tarjeta usa modelData sin calificar (raíz del delegado).
                        readonly property var modelData: draft || ({ form: {} })
                        readonly property bool iconOnly: tab.cfg("drafts", itemKey).presentation === "icon"
                        iconPresentation: iconOnly
                        fillRow: iconOnly
                        ui: tab.ui; owner: tab; kind: "drafts"; key: itemKey; order: index
                        longPressEnters: false
                        visible: draft !== null
                        width: tab.tileWidth("drafts", itemKey, draftFlow.width, draftFlow.spacing)
                        Rectangle {                    // presentación "Solo icono"
                            visible: draftTile.iconOnly
                            width: parent.width; height: visible ? Math.max(76 * tab.ui.u, draftTile.rowHeight) : 0
                            radius: 18 * tab.ui.u
                            color: S.cardGlass; border.width: 1; border.color: S.edge(0.93)
                            Text { anchors.centerIn: parent; text: String.fromCharCode(tab.expenseIcon(draftTile.draft ? draftTile.draft.form : {}))
                                   color: S.accent; font.family: tab.ui.iconFamily; font.pixelSize: parent.width * 0.42 }
                            MouseArea {
                                anchors.fill: parent
                                enabled: !tab.editMode && !tab.app.modalOpen
                                pressAndHoldInterval: 380
                                onPressed: draftTile.beginPress()
                                onReleased: draftTile.releasePressure()
                                onCanceled: draftTile.releasePressure()
                                onClicked: function(mouse) { tab.openDraftMenu(draftTile.draft, parent, mouse.x, mouse.y) }
                                onPressAndHold: draftTile.deepPress()
                            }
                            Accessible.role: Accessible.Button
                            Accessible.name: draftTile.draft ? (S.text_(draftTile.draft.form, "concept") || "Borrador sin concepto") : ""
                        }
                        RCard {
                        id: draftCard
                        readonly property var modelData: draftTile.draft || ({ form: {} })
                        readonly property bool compact: tab.cfg("drafts", draftTile.itemKey).size !== "wide"
                        visible: !draftTile.iconOnly
                        height: visible ? implicitHeight : 0
                        objectName: "draft:" + modelData.id
                        width: parent.width
                        ui: tab.ui
                        color: S.cardGlass
                        border.color: S.edge(0.93)
                        readonly property var st: tab.draftState(modelData)
                        readonly property var server: tab.inspected[modelData.id] || null       // versión vigente consultada
                        readonly property string inspectError: tab.inspectErrors[modelData.id] || ""
                        function inspect() { tab.inspect(modelData.id) }
                        function resolve(keepLocal) { tab.resolve(modelData.id, keepLocal) }
                        MouseArea {
                            // Bajo el contenido para conservar los controles especiales del conflicto.
                            parent: draftCard
                            anchors.fill: parent
                            z: -1
                            enabled: !tab.app.modalOpen && !draftPopup.visible
                            property bool held: false
                            pressAndHoldInterval: 380                   // Deep Press del Home
                        onPressed: { held = false; draftTile.beginPress() }
                        onReleased: draftTile.releasePressure()
                        onCanceled: draftTile.releasePressure()
                            onPressAndHold: function(mouse) {
                                held = true
                                draftTile.deepPress()                  // mismo gesto del Home: editar cajas
                            }
                            onClicked: function(mouse) {
                                if (!held) tab.openDraftMenu(draftCard.modelData, draftCard, mouse.x, mouse.y)
                            }
                            Accessible.role: Accessible.Button
                            Accessible.name: "Acciones de " + (S.text_(draftCard.modelData.form, "concept") || "borrador sin concepto")
                            Accessible.onPressAction: tab.openDraftMenu(draftCard.modelData, draftCard, draftCard.width / 2, draftCard.height / 2)
                        }
                        // Encabezado Metro compacto: icono registrado + importe.
                        Row {
                            width: parent.width
                            height: 38 * tab.ui.u
                            spacing: 6 * tab.ui.u
                            Rectangle {
                                width: 38 * tab.ui.u
                                height: width
                                radius: 12 * tab.ui.u
                                color: S.tintSoft
                                Text {
                                    anchors.centerIn: parent
                                    text: String.fromCharCode(tab.expenseIcon(draftCard.modelData.form))
                                    font.family: tab.ui.iconFamily
                                    font.pixelSize: 23 * tab.ui.u
                                    color: S.accent
                                }
                            }
                            Item {
                                width: Math.max(0, parent.width - 38 * tab.ui.u - 6 * tab.ui.u)
                                height: parent.height
                                Rectangle {
                                    anchors.right: parent.right
                                    anchors.verticalCenter: parent.verticalCenter
                                    height: 32 * tab.ui.u
                                    width: Math.min(parent.width, (draftCard.compact ? 110 : 140) * tab.ui.u)
                                    radius: 16 * tab.ui.u
                                    color: S.glass(0.78)
                                    border.width: 1
                                    border.color: S.fieldBorder
                                    Text {
                                        id: draftAmount
                                        anchors.fill: parent
                                        anchors.leftMargin: 9 * tab.ui.u
                                        anchors.rightMargin: 9 * tab.ui.u
                                        verticalAlignment: Text.AlignVCenter
                                        horizontalAlignment: Text.AlignHCenter
                                        text: S.text_(draftCard.modelData.form, "amount").length
                                              && !tab.ctl.amountError(S.text_(draftCard.modelData.form, "amount")).length
                                              ? tab.ctl.formatMoney(S.text_(draftCard.modelData.form, "amount"),
                                                                    S.text_(draftCard.modelData.form, "currencyCode") || "PEN") : "—"
                                        color: S.text
                                        font.family: tab.ui.fontFamily
                                        font.pixelSize: 13 * tab.ui.u
                                        font.weight: Font.DemiBold
                                        fontSizeMode: Text.Fit
                                        minimumPixelSize: 10 * tab.ui.u
                                        elide: Text.ElideRight
                                    }
                                }
                            }
                        }
                        Text {
                            width: parent.width
                            height: draftCard.compact ? 44 * tab.ui.u : implicitHeight
                            text: S.text_(draftCard.modelData.form, "concept") || "Borrador sin concepto"
                            color: S.text
                            wrapMode: Text.WordWrap
                            elide: Text.ElideRight
                            maximumLineCount: 2
                            verticalAlignment: Text.AlignTop
                            font.family: tab.ui.fontFamily
                            font.pixelSize: 15 * tab.ui.u
                            font.weight: Font.DemiBold
                        }
                        Text {
                            width: parent.width
                            text: (S.text_(draftCard.modelData.form, "expenseDate").length
                                   ? S.date(S.text_(draftCard.modelData.form, "expenseDate")) : "Sin fecha")
                                  + " · " + (S.text_(draftCard.modelData.form, "beneficiary") || "Sin proveedor")
                            color: S.muted
                            wrapMode: Text.WordWrap
                            elide: Text.ElideRight
                            maximumLineCount: draftCard.compact ? 2 : 1
                            font.family: tab.ui.fontFamily
                            font.pixelSize: 12 * tab.ui.u
                        }
                        Flow {
                            width: parent.width
                            spacing: 6 * tab.ui.u
                            visible: !(draftCard.modelData.syncState === "SYNCED" && draftCard.modelData.inCloud)
                                     || draftCard.modelData.kind === "EDIT" || Number(draftCard.modelData.missingSources || 0) > 0
                            RBadge {
                                ui: tab.ui
                                visible: !(modelData.syncState === "SYNCED" && modelData.inCloud)
                                label: !draftCard.compact ? draftCard.st.label
                                       : draftCard.st.label === "Borrador en la nube" ? "En la nube"
                                       : draftCard.st.label === "Pendiente de subir" ? "Por subir"
                                       : draftCard.st.label === "Solo en este equipo" ? "Local"
                                       : draftCard.st.label === "Registro pendiente" ? "Por registrar"
                                       : draftCard.st.label === "Descarte pendiente" ? "Por descartar"
                                       : draftCard.st.label
                                tone: draftCard.st.tone
                            }
                            RBadge { ui: tab.ui; visible: modelData.kind === "EDIT"; label: draftCard.compact ? "Edición" : "Edición de gasto"; tone: S.accentSoft }
                            RBadge {
                                ui: tab.ui; visible: Number(modelData.missingSources || 0) > 0
                                label: modelData.missingSources + (draftCard.compact ? " faltantes" : " por volver a adjuntar"); tone: S.warning
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

                    }
                    }
                }
            }
            Item {
                width: parent.width
                height: Math.max(44 * tab.ui.u, registeredHeading.implicitHeight)
                Text {
                    id: registeredHeading
                    width: parent.width - filterControl.width - 10 * tab.ui.u
                    anchors.verticalCenter: parent.verticalCenter
                    text: "Gastos registrados"
                    wrapMode: Text.WordWrap
                    color: S.text; font.family: tab.ui.fontFamily; font.pixelSize: 16 * tab.ui.u; font.weight: Font.Bold
                }
                Rectangle {
                    id: filterControl
                    objectName: "expenseFilterControl"
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    width: 44 * tab.ui.u; height: width; radius: width / 2
                    color: S.cardGlass; border.width: 1; border.color: S.edge(1)
                    Text { anchors.centerIn: parent; text: String.fromCharCode(0xE0DC)
                           font.family: tab.ui.iconFamily; font.pixelSize: 22 * tab.ui.u; color: S.navy }
                    // Punto: hay orden distinto al habitual o búsqueda activa.
                    Rectangle { visible: tab.sortBy !== "date" || tab.query.length > 0
                                anchors.right: parent.right; anchors.top: parent.top; anchors.margins: 4 * tab.ui.u
                                width: 9 * tab.ui.u; height: width; radius: width / 2; color: S.accent; border.width: 1.5; border.color: S.edge(1) }
                    MouseArea { anchors.fill: parent; enabled: !tab.app.modalOpen
                                onClicked: {
                                    var p = filterControl.mapToItem(tab, filterControl.width / 2, filterControl.height)
                                    sortMenu.anchorX = p.x; sortMenu.anchorY = p.y; sortMenu.above = false
                                    sortMenu.open = true
                                } }
                    Accessible.role: Accessible.Button
                    Accessible.name: "Ordenar y filtrar gastos"
                }
            }

            Text {
                width: parent.width
                visible: !tab.detail.selected
                text: "Cargando los gastos de la rendición…"
                color: S.muted
                font.family: tab.ui.fontFamily; font.pixelSize: 15 * tab.ui.u
            }
            RCard {
                objectName: "expensesEmptyState"
                width: parent.width
                visible: tab.detail.selected && tab.expenses.length === 0
                ui: tab.ui
                color: S.glass(0.80); border.color: S.edge(1); radius: 26 * tab.ui.u
                Item { width: 1; height: 8 * tab.ui.u }
                Rectangle {
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: 64 * tab.ui.u; height: width; radius: 20 * tab.ui.u; color: S.tintSoft
                    Text { anchors.centerIn: parent; text: String.fromCharCode(0xE3D3); color: S.accent
                           font.family: tab.ui.iconFamily; font.pixelSize: 30 * tab.ui.u }
                }
                Text { width: parent.width; horizontalAlignment: Text.AlignHCenter; text: "Aún no hay gastos"; color: S.text
                       font.family: tab.ui.fontFamily; font.pixelSize: 19 * tab.ui.u; font.weight: Font.ExtraBold }
                Text { width: parent.width; horizontalAlignment: Text.AlignHCenter; wrapMode: Text.WordWrap; color: S.muted
                       text: tab.detail.writable ? "Registra cada compra con su boleta o factura. La fecha y el proyecto ya vienen puestos."
                                                 : "Esta rendición no tiene gastos registrados."
                       font.family: tab.ui.fontFamily; font.pixelSize: 14 * tab.ui.u }
                RButton {
                    objectName: "emptyNewExpense"
                    visible: tab.detail.writable
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: Math.min(parent.width, 220 * tab.ui.u); height: 54 * tab.ui.u; radius: 16 * tab.ui.u
                    ui: tab.ui; primary: true; glyph: 0xE13D; label: "Nuevo gasto"
                    enabledButton: tab.detail.editable
                    onActivated: tab.createExpense()
                }
                Text { visible: tab.detail.writable; width: parent.width; horizontalAlignment: Text.AlignHCenter
                       text: "También con el «+» del Dock"; color: S.muted
                       font.family: tab.ui.fontFamily; font.pixelSize: 12.5 * tab.ui.u }
                Item { width: 1; height: 4 * tab.ui.u }
            }

            Row {                                       // filtro activo (Buscar del Dock)
                id: filterSummary
                width: parent.width
                visible: tab.query.length > 0
                spacing: 10 * tab.ui.u
                Text {
                    width: parent.width - clearFilter.width - parent.spacing
                    anchors.verticalCenter: parent.verticalCenter
                    text: (tab.query.length ? "Buscando «" + tab.query + "»" : "Todos los gastos")
                          + (tab.sortBy.length ? " · por " + tab.sortLabels[tab.sortBy] : "")
                          + " · " + tab.visibleExpenses.length + " de " + tab.expenses.length
                    color: S.corporateBlue
                    wrapMode: Text.WordWrap
                    font.family: tab.ui.fontFamily; font.pixelSize: 14 * tab.ui.u
                }
                RChip { id: clearFilter; ui: tab.ui; label: "Quitar filtro"; onActivated: { tab.query = ""; tab.sortBy = "date" } }
            }
            Repeater { model: expensesModel; delegate: expenseCardComponent }
            Component {
                id: expenseCardComponent
                RCard {
                        id: expenseCard
                        required property string rowJson
                        readonly property var modelData: JSON.parse(rowJson)
                        objectName: "expense:" + modelData.localId
                        width: column.width
                        ui: tab.ui
                        color: expanded ? S.glass(0.86) : S.cardGlass
                        radius: 24 * tab.ui.u
                        border.width: expanded ? 2 : 1
                        border.color: expanded ? Qt.rgba(6 / 255, 84 / 255, 162 / 255, 0.45) : S.edge(0.93)
                        readonly property var category: tab.registeredCategory(modelData)
                        readonly property color categoryTone: category.tone
                        readonly property bool expanded: tab.expandedId === String(modelData.localId)
                        clickable: !expanded
                        onActivated: tab.expand(modelData)
                        Row {
                            id: expenseLine
                            width: parent.width
                            spacing: 8 * tab.ui.u
                            Rectangle {
                                id: ordinal
                                width: 26 * tab.ui.u; height: width; radius: width / 2
                                anchors.verticalCenter: parent.verticalCenter
                                color: S.tintSoft
                                Text { anchors.centerIn: parent; text: String(tab.expenses.findIndex(function(e) { return String(e.localId) === String(expenseCard.modelData.localId) }) + 1)   // n.º del gasto (por identidad)
                                       color: S.accent; font.family: tab.ui.fontFamily; font.pixelSize: 12 * tab.ui.u; font.weight: Font.Bold }
                            }
                            Rectangle {
                                id: categoryIcon
                                width: (expenseLine.width < 300 * tab.ui.u ? 34 : 42) * tab.ui.u
                                height: width; radius: 13 * tab.ui.u
                                anchors.verticalCenter: parent.verticalCenter
                                color: Qt.rgba(expenseCard.categoryTone.r, expenseCard.categoryTone.g, expenseCard.categoryTone.b, 0.17)
                                border.width: 1; border.color: S.edge(0.8)
                                Text { anchors.centerIn: parent; text: String.fromCharCode(expenseCard.category.glyph)
                                       color: expenseCard.categoryTone; font.family: tab.ui.iconFamily; font.pixelSize: parent.width * 0.65 }
                            }
                            Column {
                                width: Math.max(0, expenseLine.width - ordinal.width - categoryIcon.width - amount.width - chevron.width - 4 * expenseLine.spacing)
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: 4 * tab.ui.u
                                Text { width: parent.width; text: S.date(S.text_(expenseCard.modelData, "expenseDate", "expense_date")) || "Sin fecha"
                                       color: S.muted; font.family: tab.ui.fontFamily; font.pixelSize: 11 * tab.ui.u }
                                Text { width: parent.width; text: S.text_(expenseCard.modelData, "concept") || "Gasto sin concepto"
                                       color: S.text; wrapMode: Text.WrapAtWordBoundaryOrAnywhere; font.family: tab.ui.fontFamily
                                       font.pixelSize: 14 * tab.ui.u; font.weight: Font.DemiBold }
                            }
                            Text {
                                id: amount
                                objectName: "expenseAmount"
                                width: Math.min(implicitWidth, expenseLine.width * 0.30)
                                anchors.verticalCenter: parent.verticalCenter
                                text: tab.ctl.formatMoney(expenseCard.modelData.amount, S.text_(expenseCard.modelData, "currencyCode", "currency_code"))
                                color: S.text; horizontalAlignment: Text.AlignRight; wrapMode: Text.WrapAtWordBoundaryOrAnywhere
                                font.family: tab.ui.fontFamily; font.pixelSize: 16 * tab.ui.u; font.weight: Font.Bold
                            }
                            Text { id: chevron; width: 16 * tab.ui.u; anchors.verticalCenter: parent.verticalCenter
                                   text: String.fromCharCode(expenseCard.expanded ? 0xE06C : 0xE06F)
                                   color: S.accent; font.family: tab.ui.iconFamily; font.pixelSize: 18 * tab.ui.u }
                        }
                        RBadge {
                            ui: tab.ui
                            readonly property string state: tab.app.syncState(expenseCard.modelData)
                            visible: ["CONFLICT", "ERROR", "NEEDS_RECONCILIATION"].indexOf(state) >= 0
                            label: tab.ctl.syncLabel(state); tone: S.syncColor(state)
                        }
                        Text {
                            width: parent.width
                            visible: S.text_(modelData, "reviewComment", "review_comment").length > 0
                            text: "Observación: " + S.text_(modelData, "reviewComment", "review_comment")
                            color: S.warning; wrapMode: Text.WordWrap
                            font.family: tab.ui.fontFamily; font.pixelSize: 13 * tab.ui.u
                        }

                    }
            }
        }
    }

    // Opciones de la caja (mismo contenido que el menú de edición del Home, sin widgets).
    RGlassMenu {
        id: tileMenu
        objectName: "boxEditMenu"
        ui: tab.ui
        cardWidth: 250 * tab.ui.u
        readonly property var c: tab.menuTile ? tab.cfg(tab.menuTile.kind, tab.menuTile.key) : ({ size: "compact", presentation: "full" })
        // Alojado en la capa global de HomeScreen (sobre el desenfoque y el Dock);
        // en pruebas de escritorio, dentro de la pestaña.
        readonly property bool hosted: !!tab.app && !!tab.app.touchLayer
        parent: hosted ? tab.app.touchLayer : tab
        dimBackground: !hosted
        onDismissed: { tab.focusKey = ""; tab.focusTileItem = null }
        readonly property bool forDraft: !!tab.menuTile && tab.menuTile.kind === "drafts"
        // Acciones reales del borrador como filas compactas (estilo 3D Touch de iOS).
        Repeater {
            model: tileMenu.forDraft && !tab.editMode ? [
                { a: "Continuar", g: 0xE12F, c: S.navy }, { a: "Registrar", g: 0xE06C, c: S.accent },
                { a: "Descartar", g: 0xE18E, c: S.danger } ] : []
            delegate: RMenuItem {
                required property var modelData
                objectName: "tileDraftAction:" + modelData.a
                ui: tab.ui
                label: modelData.a
                glyph: modelData.g
                glyphColor: modelData.c
                enabledItem: tab.draftActionAllowed(tab.menuDraft, modelData.a)
                onActivated: { tileMenu.close(); tab.runDraftAction(modelData.a) }
            }
        }
        Item { width: 1; height: tileMenu.forDraft && !tab.editMode ? 6 * tab.ui.u : 0 }
        Row {                                        // tamaño: selector segmentado bajo
            id: sizeRow
            width: parent.width
            spacing: 4 * tab.ui.u
            Repeater {
                model: [{ v: "icon", l: "Icono" }, { v: "small", l: "1/3" }, { v: "compact", l: "1/2" }, { v: "wide", l: "Ancho" }]
                delegate: Rectangle {
                    required property var modelData
                    readonly property bool active: modelData.v === "icon" ? tileMenu.c.presentation === "icon"
                                                   : tileMenu.c.presentation !== "icon" && tileMenu.c.size === modelData.v
                    width: (sizeRow.width - 3 * sizeRow.spacing) / 4
                    height: 32 * tab.ui.u
                    radius: 10 * tab.ui.u
                    color: active ? S.accent : (sizeTap.pressed ? S.ink(0.10) : S.ink(0.05))
                    Behavior on color { ColorAnimation { duration: 120 } }
                    Text { anchors.centerIn: parent; text: modelData.l; color: parent.active ? S.onAccent : S.text
                           font.family: tab.ui.fontFamily; font.pixelSize: 12 * tab.ui.u; font.weight: Font.DemiBold }
                    MouseArea { id: sizeTap; anchors.fill: parent; onClicked: tab.chooseSize(modelData.v) }
                    Accessible.role: Accessible.Button
                    Accessible.name: "Tamaño " + modelData.l
                }
            }
        }
        Item { width: 1; height: 6 * tab.ui.u }
        Row {                                        // acciones de diseño en una sola fila de iconos
            id: layoutRow
            width: parent.width
            spacing: 4 * tab.ui.u
            Repeater {
                model: [{ k: "start", g: 0xE04A, l: "Inicio" }, { k: "end", g: 0xE042, l: "Final" },
                        { k: "reorder", g: 0xE146, l: tab.editMode ? "Listo" : "Ordenar" }, { k: "reset", g: 0xE148, l: "Restablecer" }]
                delegate: Rectangle {
                    required property var modelData
                    width: (layoutRow.width - 3 * layoutRow.spacing) / 4
                    height: 48 * tab.ui.u
                    radius: 10 * tab.ui.u
                    color: layoutTap.pressed ? S.ink(0.10) : "transparent"
                    Column {
                        anchors.centerIn: parent
                        spacing: 2 * tab.ui.u
                        Text { anchors.horizontalCenter: parent.horizontalCenter; text: String.fromCharCode(modelData.g); color: S.navy
                               font.family: tab.ui.iconFamily; font.pixelSize: 18 * tab.ui.u }
                        Text { anchors.horizontalCenter: parent.horizontalCenter; text: modelData.l; color: S.muted
                               font.family: tab.ui.fontFamily; font.pixelSize: 10.5 * tab.ui.u }
                    }
                    MouseArea {
                        id: layoutTap
                        anchors.fill: parent
                        onClicked: {
                            var t = tab.menuTile
                            tileMenu.close()
                            if (!t) return
                            if (modelData.k === "start" || modelData.k === "end") tab.moveTo(t.kind, t.key, modelData.k === "start")
                            else if (modelData.k === "reorder") { if (tab.editMode) tab.exitEdit(); else tab.enterEdit(null) }
                            else tab.resetLayout()
                        }
                    }
                    Accessible.role: Accessible.Button
                    Accessible.name: modelData.l
                }
            }
        }
    }

    // Un solo icono: ordenar + buscar en un menú compacto (3D Touch).
    RGlassMenu {
        id: sortMenu
        objectName: "expenseSortMenu"
        ui: tab.ui
        cardWidth: 240 * tab.ui.u
        Text { leftPadding: 10 * tab.ui.u; topPadding: 4 * tab.ui.u; bottomPadding: 4 * tab.ui.u; text: "Ordenar por"; color: S.muted
               font.family: tab.ui.fontFamily; font.pixelSize: 12 * tab.ui.u; font.weight: Font.DemiBold }
        Repeater {
            model: [{ k: "date", l: "Fecha (más reciente)" }, { k: "concept", l: "Concepto" }, { k: "category", l: "Categoría" },
                    { k: "beneficiary", l: "Proveedor" }, { k: "project", l: "Proyecto" }]
            delegate: RMenuItem {
                required property var modelData
                ui: tab.ui
                label: modelData.l
                glyph: tab.sortBy === modelData.k ? 0xE06C : 0
                glyphColor: S.accent
                onActivated: { tab.sortBy = modelData.k; sortMenu.close() }
            }
        }
        RMenuItem { ui: tab.ui; label: "Buscar…"; glyph: 0xE151; glyphColor: S.accent
                    onActivated: { sortMenu.close(); tab.app.dockCommand("renditions.search") } }
        RMenuItem { ui: tab.ui; label: "Quitar filtros"; glyph: 0xE1B2; glyphColor: S.danger; separator: false
                    visible: tab.sortBy !== "date" || tab.query.length > 0
                    onActivated: { tab.sortBy = "date"; tab.query = ""; sortMenu.close() } }
    }
}

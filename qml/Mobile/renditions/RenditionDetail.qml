import QtQuick
import QtQuick.Shapes
import "RStyle.js" as S

// Rendición abierta = RESUMEN TOTAL (2026-10-15). Una sola pantalla ejecutiva
// con datos reales: declarado/validado, conteos de gastos, estado de gastos
// (dona), finanzas, documentos y revisión. Gastos, Finanzas, Documentos y
// Revisión siguen existentes como secciones secundarias (se abren desde los
// bloques y desde el Dock contextual); Atrás vuelve al resumen.
// Sin botones de sincronización: deslizar hacia abajo ejecuta el `sync` real
// en modo silencioso (mismo patrón que la lista principal).
// La fuente es el estado publicado por el bridge para la selección (`select`).
Item {
    id: page
    property var app
    property string localId: ""
    property int selectionToken: 0                    // apertura (select) que muestra esta página
    readonly property var ui: app.ui
    readonly property var ctl: app.ctl
    readonly property bool ownHeader: true              // el shell no dibuja su barra
    readonly property bool isRenditionDetail: true      // contexto de Dock «rendición abierta»
    readonly property bool selected: String(app.st.selectedLocalId || "") === localId
    readonly property var current: {
        if (selected && app.st.current && app.st.current.localId === localId) return app.st.current
        var rows = app.st.renditions || []
        for (var i = 0; i < rows.length; ++i)
            if (rows[i].localId === localId) return rows[i]
        return ({})
    }
    readonly property bool exists: String(current.localId || "").length > 0
    readonly property bool writable: exists && ctl.canEdit(current)
    readonly property bool syncing: String(current.syncState || "") === "SYNCING"
    // Conflicto = SÓLO un rechazo CAS real del servidor. NEEDS_RECONCILIATION no es
    // conflicto: "DETAIL_NOT_LOADED" = el detalle aún no se descargó (p. ej. sin red);
    // "AMBIGUOUS" = respuesta perdida, se confirma automáticamente con el próximo pull.
    readonly property bool conflict: String(current.syncState || "") === "CONFLICT"
    readonly property bool reconciling: String(current.syncState || "") === "NEEDS_RECONCILIATION"
                                        && String(current.reconcileReason || "") === "AMBIGUOUS"
    // SYNCING es un indicador global (alguna petición en vuelo), no un bloqueo de la
    // ficha: el almacén local protege las operaciones realmente en curso. Así un
    // servidor lento o reintentos sin red no interrumpen la edición offline.
    readonly property bool editable: writable && !conflict && !reconciling
    readonly property string code: S.text_(current, "visibleCode", "visible_code")
    readonly property string title: S.renditionDisplayName(S.text_(current, "displayName", "display_name"), code)
    // "summary" o una sección secundaria: expenses | financial | documents | review
    property string tab: "summary"
    readonly property var sectionTitles: ({ expenses: "Gastos", financial: "Finanzas", documents: "Documentos", review: "Revisión" })

    // ------------------------------------------------------------- Datos reales
    readonly property string remoteId: String(current.remoteId || "")
    readonly property var expenses: selected ? (app.st.expenses || []).filter(function(e) { return e.archived !== true }) : []
    // Conteos fiables sólo con los gastos cargados (local, o detalle descargado).
    readonly property bool expensesKnown: selected && (expenses.length > 0 || current.expensesLoaded === true
                                                       || !remoteId.length || Number(current.expenseCount) === 0)
    readonly property var totals: ctl.totals(expenses)
    readonly property int withSupport: expenses.filter(function(e) {
        return (e.attachments || []).some(function(a) { return !S.text_(a, "archived_at").length })
    }).length
    readonly property var funding: current.funding || ({})
    readonly property var rate: current.exchangeRate || ({})
    readonly property var balance: ctl.fundBalance(current)
    readonly property bool hasFolder: String(current.documentParentNodeId || "").length > 0
    readonly property bool exportable: remoteId.length > 0 && String(current.currentVersionId || "").length > 0
                                       && ["BORRADOR", "OBSERVADO"].indexOf(String(current.status || "BORRADOR")) < 0
    readonly property var completion: ctl.completion(current)
    readonly property string projectId: {
        var id = String(current.primaryProjectId || "")
        if (id.length) return id
        var ids = current.projectIds || []
        return ids.length ? String(ids[0]) : ""
    }
    readonly property var project: projectId.length ? ctl.project(projectId) : ({})
    readonly property string projectLine: {
        var parts = [S.text_(project, "code", "project_code"), S.text_(project, "name", "project_name") || S.text_(current, "primaryProjectName", "primary_project_name")]
                .filter(function(s) { return s.length })
        if (parts.length) return parts.join("  •  ")
        return current.projectIds !== undefined ? "Sin proyecto" : "Proyecto por cargar"
    }

    // ----------------------------------------- Acción contextual (determinista)
    // Prioridad fija y explicable, sólo con datos reales:
    //  1 conflicto de sincronización        -> traer versión vigente (sync)
    //  2 sin carpeta documental (editable)  -> elegir carpeta (editor)
    //  3 gastos con datos incompletos       -> completar gastos
    //  4 gastos sin sustento (editable)     -> adjuntar sustentos
    //  5 gastos observados                  -> revisar observaciones
    //  6 completitud 100 % y sin pendientes -> presentar (Revisión)
    //  si nada aplica                       -> ver documentos
    // Siempre se añaden accesos estables: documentos, finanzas, revisión y
    // editar datos (si hay permiso). La IA de Rendiciones no interviene.
    readonly property var suggestions: {
        var list = []
        var c = completion
        var invalid = c.known ? Number(c.activeExpenses) - Number(c.validExpenses) : 0
        var missingSupport = expensesKnown ? expenses.length - withSupport : 0
        if (conflict) list.push({ key: "sync", label: "Traer versión vigente", icon: "status.sync" })
        var drafts = Number(current.workingCount || 0)
        if (drafts > 0) list.push({ key: "drafts", label: "Completar borradores (" + drafts + ")", icon: "action.edit" })
        if (editable && !hasFolder) list.push({ key: "folder", label: "Elegir carpeta documental", icon: "documents.folder" })
        if (editable && invalid > 0) list.push({ key: "complete", label: "Completar gastos incompletos (" + invalid + ")", icon: "action.edit" })
        if (editable && missingSupport > 0) list.push({ key: "support", label: "Adjuntar sustentos (" + missingSupport + ")", icon: "calgen.attach" })
        if (Number(totals.observed || 0) > 0) list.push({ key: "observed", label: "Revisar observaciones (" + totals.observed + ")", icon: "earth.info" })
        if (editable && c.known && Number(c.percent) === 100 && Number(current.pendingCount || 0) === 0 && drafts === 0)
            list.push({ key: "present", label: "Presentar rendición", icon: "action.check" })
        var fixed = [{ key: "documents", label: "Ver documentos", icon: "documents.file" },
                     { key: "financial", label: "Fondo y tipo de cambio", icon: "earth.layers" },
                     { key: "review", label: "Revisión y versiones", icon: "calgen.history" }]
        if (writable) fixed.push({ key: "edit", label: "Editar datos de la rendición", icon: "action.edit" })
        for (var i = 0; i < fixed.length; ++i)
            if (!list.some(function(x) { return x.key === fixed[i].key })) list.push(fixed[i])
        return list.slice(0, 10)
    }
    function runSuggestion(key) {
        if (key === "sync") { refreshFromPull(); return }
        if (key === "folder" || key === "edit") { if (editable) app.openEditor(current); return }
        if (key === "complete" || key === "drafts") { showSection("expenses"); return }
        if (key === "support") {
            for (var i = 0; i < expenses.length; ++i) {
                var has = (expenses[i].attachments || []).some(function(a) { return !S.text_(a, "archived_at").length })
                if (!has) { app.openExpense(localId, String(expenses[i].localId)); return }
            }
            showSection("expenses"); return
        }
        if (key === "observed" || key === "present" || key === "review") { showSection("review"); return }
        if (key === "documents") { showSection("documents"); return }
        if (key === "financial") { showSection("financial"); return }
    }

    function showSection(name) { tab = name; app.closeMenus() }
    function handleBack() {
        if (tab !== "summary") { tab = "summary"; replayIntro(); return true }
        return false
    }

    // ------------------------------------------------------------ Animación
    // Una sola animación (0..1) escalona bloques, contadores y la dona.
    // Sólo opacidad/traslación: barata en gama baja; movimiento reducido = final.
    property real intro: 0
    NumberAnimation { id: introAnim; target: page; property: "intro"; from: 0; to: 1; duration: 1100; easing.type: Easing.OutCubic }
    function replayIntro() {
        if (page.ui.reducedMotion === true) { intro = 1; return }
        introAnim.restart()
    }
    Component.onCompleted: replayIntro()
    function reveal(i) { return Math.max(0, Math.min(1, (intro - i * 0.11) / 0.45)) }

    // ------------------------------------------------- Deslizar para actualizar
    readonly property real pullThreshold: 76 * ui.u
    readonly property real pull: Math.max(0, flick.originY - flick.contentY - flick.topMargin)
    readonly property bool syncBusy: app.busy("sync") || app.phase !== "IDLE"
    property bool refreshing: false
    readonly property var life: ({ alive: true })
    function refreshFromPull() {
        if (refreshing || syncBusy) return
        refreshing = true
        app.haptic("light")
        var life = page.life
        // 1) sync silenciosa; 2) sólo si terminó bien, cotización BCRP/SBS vigente.
        var id = app.synchronize(true, function(ok) {
            if (!life.alive) return
            if (ok !== true) { page.refreshing = false; return }
            page.refreshQuote(function() { if (life.alive) page.refreshing = false })
        })
        if (!id.length) refreshing = false
    }

    // ------------------------------------------- Tipo de cambio BCRP/SBS vigente
    // Reutiliza `exchangeQuote` (API Web autenticada, fuente BCRP_SBS_VENTA) y el
    // guardado autorizado `saveFinancial`/`exchange_set` (outbox, CAS por
    // rowVersion, request_id). Reglas:
    //  - sólo copia editable (Borrador/Observada con permiso), con id remoto,
    //    en modo AUTOMÁTICO y sin cambios locales pendientes; nunca pisa un
    //    cambio MANUAL ni toca versiones presentadas o congeladas;
    //  - valida fuente, fecha publicada (no futura, <= 45 días: fines de semana
    //    y feriados conservan la última fecha publicada), hora de consulta y
    //    rango del tipo; nunca inventa una cotización;
    //  - si la ficha cambió durante la consulta (rowVersion) no guarda;
    //  - si tipo y fecha coinciden con lo guardado, no escribe (sin duplicados);
    //  - ante fallo conserva el valor y su fecha reales y lo indica discretamente.
    property string quoteNotice: ""
    function quoteDayValid(text) {
        var s = String(text || "")
        if (!ctl.validDate(s)) return false
        var today = ctl.today()
        if (s > today) return false
        var age = (new Date(today + "T00:00:00Z") - new Date(s + "T00:00:00Z")) / 86400000
        return age >= 0 && age <= 45
    }
    function refreshQuote(done) {
        if (!editable || String(rate.mode || "") !== "AUTOMATIC" || !remoteId.length
                || Number(current.pendingCount || 0) > 0) { done(); return }
        var base = Number(current.rowVersion || 0)
        var lid = localId
        var life = page.life
        app.call("exchangeQuote", { renditionId: remoteId }, "quote:" + lid, function(ok, q, code, message) {
            if (!life.alive) return
            if (!ok) {
                page.quoteNotice = code === "QUOTE_ORIGIN_NOT_CONFIGURED"
                        ? "Consulta BCRP/SBS no configurada en este equipo; se muestra el valor guardado."
                        : "No se pudo consultar BCRP/SBS; se muestra el valor guardado."
                done(); return
            }
            if (q.source !== "BCRP_SBS_VENTA" || !page.quoteDayValid(q.quotedOn) || !String(q.checkedAt || "").length
                    || page.ctl.rateError(String(q.rate)).length) {
                page.quoteNotice = "La cotización recibida no es válida; se conserva el valor guardado."
                done(); return
            }
            if (Number(page.current.rowVersion || 0) !== base || !page.editable || String(page.rate.mode || "") !== "AUTOMATIC") {
                page.quoteNotice = "La rendición cambió durante la consulta; se conserva el valor guardado."
                done(); return
            }
            if (String(page.rate.quoted_on || "") === String(q.quotedOn) && Number(page.rate.rate) === Number(q.rate)) {
                page.quoteNotice = ""                    // ya vigente: sin escritura
                done(); return
            }
            page.app.call("saveFinancial", { localId: lid, kind: "exchange_set", expectedRowVersion: base,
                                            values: { mode: "AUTOMATIC", rate: String(q.rate), quoted_on: q.quotedOn, checked_at: q.checkedAt } },
                          "financial:exchange_set:" + lid, function(saved, result, c2, m2) {
                if (life.alive)
                    page.quoteNotice = saved ? "" : "No se pudo guardar la cotización: " + page.app.errorText(c2, m2)
                done()
            })
        })
    }
    Component.onDestruction: {
        life.alive = false
        // Con su identidad: la destrucción ocurre al terminar la transición y puede
        // llegar DESPUÉS de seleccionar otra rendición; no debe borrar esa selección.
        if (page.ctl) page.ctl.send("closeDetail", { localId: page.localId, selectionToken: page.selectionToken }, "")
    }

    // ------------------------------------------------------------- Encabezado
    Item {
        id: header
        width: parent.width
        height: page.ui.topInset + headerText.height + 34 * page.ui.u
        Item {                                              // retroceso (patrón de Calicatas)
            x: 10 * page.ui.u
            y: page.ui.topInset + 4 * page.ui.u
            width: 48 * page.ui.u; height: 48 * page.ui.u
            Text {
                anchors.centerIn: parent
                text: String.fromCharCode(0xE06E)
                font.family: page.ui.iconFamily
                font.pixelSize: 28 * page.ui.u
                color: S.text
                scale: backTap.pressed ? 0.88 : 1
                Behavior on scale { NumberAnimation { duration: 110 } }
            }
            MouseArea { id: backTap; anchors.fill: parent; onClicked: if (!page.handleBack()) page.app.closePage() }
            Accessible.role: Accessible.Button
            Accessible.name: "Atrás"
        }
        Column {
            id: headerText
            x: 60 * page.ui.u
            width: parent.width - 120 * page.ui.u
            y: page.ui.topInset + 10 * page.ui.u
            spacing: 4 * page.ui.u
            opacity: page.reveal(0)
            Text {
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                text: page.title
                color: S.text
                elide: Text.ElideRight
                font.family: page.ui.fontFamily; font.pixelSize: 30 * page.ui.u; font.weight: Font.Bold
            }
            Text {
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                text: page.tab === "summary" ? "Período " + S.period(page.current.periodStart, page.current.periodEnd)
                                             : page.sectionTitles[page.tab]
                color: page.tab === "summary" ? S.muted : S.corporateBlue
                font.family: page.ui.fontFamily; font.pixelSize: 16 * page.ui.u
                font.weight: page.tab === "summary" ? Font.Normal : Font.DemiBold
            }
            Text {
                width: parent.width
                visible: page.tab === "summary"
                horizontalAlignment: Text.AlignHCenter
                text: page.projectLine
                color: S.muted
                elide: Text.ElideRight
                font.family: page.ui.fontFamily; font.pixelSize: 16 * page.ui.u
            }
        }
    }

    // ------------------------------------------------- Secciones secundarias
    Item {
        anchors.top: header.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        visible: page.tab !== "summary"
        RenditionExpenses { objectName: "expensesTab"; anchors.fill: parent; visible: page.tab === "expenses"; detail: page }
        RenditionFinancial { objectName: "financialTab"; anchors.fill: parent; visible: page.tab === "financial"; detail: page }
        RenditionDocuments { objectName: "documentsTab"; anchors.fill: parent; visible: page.tab === "documents"; detail: page }
        RenditionReview { objectName: "reviewTab"; anchors.fill: parent; visible: page.tab === "review"; detail: page }
    }

    // ------------------------------------------------------------ Resumen total
    // Bloque del resumen: SOLO informativo (sin MouseArea, sin señales): los
    // toques y arrastres llegan íntegros al Flickable (scroll y actualizar).
    // Gastos, Finanzas, Documentos y Revisión se abren sólo desde el Dock.
    component Block: Item {
        id: block
        property int order: 0
        default property alias content: blockBody.data
        width: parent ? parent.width : 0
        height: blockBody.implicitHeight + 28 * page.ui.u
        opacity: page.reveal(order)
        transform: Translate { y: (1 - page.reveal(block.order)) * 18 * page.ui.u }
        Column { id: blockBody; x: 0; y: 14 * page.ui.u; width: parent.width; spacing: 10 * page.ui.u }
    }
    component Divider: Rectangle { width: parent ? parent.width : 0; height: 1; color: S.ink(0.08) }
    component IconBadge: Rectangle {
        property int glyph: 0xE0CC
        property color tone: S.corporateBlue
        width: 54 * page.ui.u; height: width; radius: width / 2
        color: Qt.rgba(tone.r, tone.g, tone.b, 0.10)
        Text { anchors.centerIn: parent; text: String.fromCharCode(parent.glyph); font.family: page.ui.iconFamily; font.pixelSize: 26 * page.ui.u; color: parent.tone }
    }
    component Stat: Rectangle {
        id: stat
        property int value: 0
        property string label: ""
        property color tone: S.corporateBlue
        property int glyph: 0xE0CC
        width: (summaryColumn.width - 3 * 8 * page.ui.u) / 4
        height: 104 * page.ui.u
        radius: 16 * page.ui.u
        color: Qt.rgba(tone.r, tone.g, tone.b, 0.08)
        Column {
            anchors.centerIn: parent
            spacing: 4 * page.ui.u
            Text { anchors.horizontalCenter: parent.horizontalCenter; text: String.fromCharCode(stat.glyph); font.family: page.ui.iconFamily; font.pixelSize: 24 * page.ui.u; color: stat.tone }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: page.expensesKnown ? Math.round(stat.value * page.reveal(2)) : "—"
                color: S.text
                font.family: page.ui.fontFamily; font.pixelSize: 24 * page.ui.u; font.weight: Font.DemiBold
            }
            Text { anchors.horizontalCenter: parent.horizontalCenter; text: stat.label; color: S.muted; font.family: page.ui.fontFamily; font.pixelSize: 13 * page.ui.u }
        }
    }
    component LegendRow: Item {
        property color tone: S.muted
        property string label: ""
        property int value: 0
        width: parent ? parent.width : 0
        height: 26 * page.ui.u
        Rectangle { width: 14 * page.ui.u; height: width; radius: width / 2; color: parent.tone; anchors.verticalCenter: parent.verticalCenter }
        Text { x: 26 * page.ui.u; anchors.verticalCenter: parent.verticalCenter; text: parent.label; color: S.muted; font.family: page.ui.fontFamily; font.pixelSize: 15 * page.ui.u }
        Text {
            anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
            text: page.expensesKnown ? String(parent.value) : "—"
            color: S.text; font.family: page.ui.fontFamily; font.pixelSize: 16 * page.ui.u; font.weight: Font.DemiBold
        }
    }
    component Check: Row {
        property bool ok: false
        property string label: ""
        spacing: 10 * page.ui.u
        Rectangle {
            width: 20 * page.ui.u; height: width; radius: width / 2
            color: parent.ok ? S.corporateGreen : S.ink(0.12)
            anchors.verticalCenter: parent.verticalCenter
            Text { anchors.centerIn: parent; text: String.fromCharCode(0xE06C); font.family: page.ui.iconFamily; font.pixelSize: 13 * page.ui.u; color: "#FFFFFF" }
        }
        Text { text: parent.label; color: S.muted; font.family: page.ui.fontFamily; font.pixelSize: 15 * page.ui.u; anchors.verticalCenter: parent.verticalCenter }
    }

    // La superficie redondeada es ESTÁTICA; el contenido se desplaza en un
    // visor interior inscrito (20u laterales, 14u verticales dentro del radio
    // de 28u): el recorte rectangular del Flickable nunca alcanza las esquinas
    // (el punto (20,14) queda a 16u del centro del arco, dentro del radio).
    // Sin máscaras ni capturas. Termina sobre el área reservada al Dock global.
    Rectangle {
        id: card
        anchors.top: header.bottom
        anchors.topMargin: 4 * page.ui.u
        x: 12 * page.ui.u
        width: parent.width - 24 * page.ui.u
        readonly property real maxHeight: Math.max(160 * page.ui.u,
            page.height - header.height - 4 * page.ui.u - page.ui.dockArea - 8 * page.ui.u)
        height: Math.min(summaryColumn.height + 36 * page.ui.u, maxHeight)
        visible: page.tab === "summary"
        radius: 28 * page.ui.u
        color: Qt.rgba(1, 1, 1, 0.80)
        border.width: 1
        border.color: Qt.rgba(1, 1, 1, 0.95)

        Flickable {
            id: flick
            anchors.fill: parent
            anchors.leftMargin: 20 * page.ui.u
            anchors.rightMargin: 20 * page.ui.u
            anchors.topMargin: 14 * page.ui.u
            anchors.bottomMargin: 14 * page.ui.u
            contentWidth: width
            contentHeight: summaryColumn.height + 8 * page.ui.u
            // Vertical explícito: deslizar para actualizar funciona aunque el
            // resumen quepa entero en la tarjeta.
            flickableDirection: Flickable.VerticalFlick
            boundsBehavior: Flickable.DragOverBounds
            topMargin: page.refreshing ? 52 * page.ui.u : 0
            Behavior on topMargin { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
            clip: true
            onDragEnded: if (page.pull >= page.pullThreshold) page.refreshFromPull()

            Column {
                id: summaryColumn
                width: parent.width
                spacing: 4 * page.ui.u

                Text {
                    width: parent.width
                    visible: !page.exists
                    topPadding: 10 * page.ui.u
                    text: "La rendición ya no está disponible en esta cuenta."
                    color: S.danger; wrapMode: Text.WordWrap
                    font.family: page.ui.fontFamily; font.pixelSize: 15 * page.ui.u
                }
                // Sólo situaciones que requieren acción: conflicto CAS REAL o un rechazo
                // del servidor. La pérdida de conexión nunca llega aquí (aura roja).
                Text {
                    width: parent.width
                    readonly property string rejection: page.ctl.visibleSyncError(String(page.current.syncError || ""))
                    visible: page.conflict || rejection.length > 0
                    topPadding: 10 * page.ui.u
                    // Línea de estado (no recuadro rojo): el detalle, la causa y la acción
                    // de recuperación están en Estado de Rendiciones (toque).
                    text: (page.conflict ? "Conflicto con el servidor: desliza hacia abajo para traer la versión vigente; tus cambios locales se conservan."
                                         : "El servidor rechazó un cambio: " + page.ctl.errorText("", rejection))
                          + "  ·  Ver estado"
                    color: S.navy; wrapMode: Text.WordWrap
                    font.family: page.ui.fontFamily; font.pixelSize: 13 * page.ui.u
                    MouseArea { anchors.fill: parent; onClicked: if (page.app.toggleStatus !== undefined) page.app.toggleStatus() }
                }

                // ---- Declarado / validado
                Block {
                    order: 1
                    Row {
                        width: parent.width
                        spacing: 16 * page.ui.u
                        IconBadge { glyph: 0xE0CC }
                        Column {
                            width: parent.width - 70 * page.ui.u
                            spacing: 2 * page.ui.u
                            Text { text: "Declarado"; color: S.muted; font.family: page.ui.fontFamily; font.pixelSize: 15 * page.ui.u }
                            Text {
                                width: parent.width
                                text: page.expensesKnown ? page.ctl.formatCents(page.totals.penCents, "PEN") + "  •  " + page.ctl.formatCents(page.totals.usdCents, "USD")
                                                         : "Gastos por cargar"
                                color: S.text; elide: Text.ElideRight
                                font.family: page.ui.fontFamily; font.pixelSize: 25 * page.ui.u; font.weight: Font.Bold
                            }
                            Text { topPadding: 6 * page.ui.u; text: "Validado"; color: S.muted; font.family: page.ui.fontFamily; font.pixelSize: 15 * page.ui.u }
                            Text {
                                width: parent.width
                                text: page.expensesKnown ? page.ctl.formatCents(page.totals.validatedPenCents, "PEN") + "  •  " + page.ctl.formatCents(page.totals.validatedUsdCents, "USD") : "—"
                                color: S.text; elide: Text.ElideRight
                                font.family: page.ui.fontFamily; font.pixelSize: 21 * page.ui.u; font.weight: Font.DemiBold
                            }
                        }
                    }
                }
                Divider {}

                // ---- Conteos
                Item {
                    width: parent.width
                    height: 104 * page.ui.u + 24 * page.ui.u
                    opacity: page.reveal(2)
                    transform: Translate { y: (1 - page.reveal(2)) * 18 * page.ui.u }
                    Row {
                        y: 12 * page.ui.u
                        spacing: 8 * page.ui.u
                        Stat { value: page.totals.count || 0; label: "gastos"; glyph: 0xE0CC; tone: S.corporateBlue }
                        Stat { value: page.totals.pending || 0; label: "pendientes"; glyph: 0xE1F5; tone: S.warning }
                        Stat { value: page.totals.observed || 0; label: "observados"; glyph: 0xE0F9; tone: S.danger }
                        Stat { value: page.totals.validated || 0; label: "validados"; glyph: 0xE06C; tone: S.corporateGreen }
                    }
                }

                // ---- Estado de gastos (dona animada)
                Block {
                    order: 3
                    Text { text: "Estado de gastos"; color: S.text; font.family: page.ui.fontFamily; font.pixelSize: 18 * page.ui.u; font.weight: Font.DemiBold }
                    Row {
                        width: parent.width
                        spacing: 22 * page.ui.u
                        Item {
                            id: donut
                            width: 132 * page.ui.u; height: width
                            readonly property real r: 52 * page.ui.u
                            readonly property real cx: width / 2
                            readonly property real total: Math.max(1, Number(page.totals.count || 0))
                            readonly property real t: page.reveal(3)
                            readonly property real aValid: 360 * Number(page.totals.validated || 0) / total * t
                            readonly property real aPending: 360 * Number(page.totals.pending || 0) / total * t
                            readonly property real aObserved: 360 * Number(page.totals.observed || 0) / total * t
                            Shape {
                                anchors.fill: parent
                                ShapePath {
                                    strokeColor: S.track; strokeWidth: 20 * page.ui.u; fillColor: "transparent"
                                    PathAngleArc { centerX: donut.cx; centerY: donut.cx; radiusX: donut.r; radiusY: donut.r; startAngle: 0; sweepAngle: 360 }
                                }
                                ShapePath {
                                    strokeColor: S.corporateGreen; strokeWidth: 20 * page.ui.u; fillColor: "transparent"
                                    PathAngleArc { centerX: donut.cx; centerY: donut.cx; radiusX: donut.r; radiusY: donut.r; startAngle: -90; sweepAngle: donut.aValid }
                                }
                                ShapePath {
                                    strokeColor: S.warning; strokeWidth: 20 * page.ui.u; fillColor: "transparent"
                                    PathAngleArc { centerX: donut.cx; centerY: donut.cx; radiusX: donut.r; radiusY: donut.r; startAngle: -90 + donut.aValid; sweepAngle: donut.aPending }
                                }
                                ShapePath {
                                    strokeColor: S.danger; strokeWidth: 20 * page.ui.u; fillColor: "transparent"
                                    PathAngleArc { centerX: donut.cx; centerY: donut.cx; radiusX: donut.r; radiusY: donut.r; startAngle: -90 + donut.aValid + donut.aPending; sweepAngle: donut.aObserved }
                                }
                            }
                            Column {
                                anchors.centerIn: parent
                                Text {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    text: page.expensesKnown ? Math.round(Number(page.totals.count || 0) * donut.t) : "—"
                                    color: S.text; font.family: page.ui.fontFamily; font.pixelSize: 26 * page.ui.u; font.weight: Font.Bold
                                }
                                Text { anchors.horizontalCenter: parent.horizontalCenter; text: "gastos"; color: S.muted; font.family: page.ui.fontFamily; font.pixelSize: 14 * page.ui.u }
                            }
                        }
                        Column {
                            width: parent.width - donut.width - 22 * page.ui.u
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 8 * page.ui.u
                            LegendRow { tone: S.corporateGreen; label: "Validados"; value: page.totals.validated || 0 }
                            LegendRow { tone: S.warning; label: "Pendientes"; value: page.totals.pending || 0 }
                            LegendRow { tone: S.danger; label: "Observados"; value: page.totals.observed || 0 }
                            Text {
                                width: parent.width
                                visible: page.completion.known === true
                                text: "Completitud " + Math.round(Number(page.completion.percent || 0) * donut.t) + " %"
                                color: S.corporateBlue
                                font.family: page.ui.fontFamily; font.pixelSize: 14 * page.ui.u; font.weight: Font.DemiBold
                            }
                        }
                    }
                }
                Divider {}

                // ---- Finanzas
                Block {
                    order: 4
                    Row {
                        width: parent.width
                        spacing: 16 * page.ui.u
                        IconBadge { glyph: 0xE529 }
                        Column {
                            width: parent.width - 70 * page.ui.u
                            spacing: 6 * page.ui.u
                            Text { text: "Finanzas"; color: S.text; font.family: page.ui.fontFamily; font.pixelSize: 18 * page.ui.u; font.weight: Font.DemiBold }
                            Row {
                                width: parent.width
                                spacing: 10 * page.ui.u
                                Column {
                                    width: (parent.width - 20 * page.ui.u) / 3
                                    Text { text: "Fondo total"; color: S.muted; font.family: page.ui.fontFamily; font.pixelSize: 13 * page.ui.u }
                                    Text {
                                        width: parent.width; wrapMode: Text.WordWrap
                                        text: !page.balance.enabled ? "Sin fondo"
                                              : page.ctl.formatCents(page.balance.fundPenCents, "PEN")
                                                + (Number(page.balance.fundUsdCents || 0) !== 0 ? "\n" + page.ctl.formatCents(page.balance.fundUsdCents, "USD") : "")
                                        color: S.text; font.family: page.ui.fontFamily; font.pixelSize: 16 * page.ui.u; font.weight: Font.DemiBold
                                    }
                                }
                                Column {
                                    width: (parent.width - 20 * page.ui.u) / 3
                                    Text { text: "Disponible"; color: S.muted; font.family: page.ui.fontFamily; font.pixelSize: 13 * page.ui.u }
                                    Text {
                                        width: parent.width; wrapMode: Text.WordWrap
                                        text: !page.balance.enabled ? "—"
                                              : page.balance.error ? "No calculable"
                                              : (page.balance.penCents === undefined || page.balance.penCents === null ? "S/ —" : page.ctl.formatCents(page.balance.penCents, "PEN"))
                                                + "\n" + (page.balance.usdCents === undefined || page.balance.usdCents === null ? "US$ —" : page.ctl.formatCents(page.balance.usdCents, "USD"))
                                        color: S.text; font.family: page.ui.fontFamily; font.pixelSize: 16 * page.ui.u; font.weight: Font.DemiBold
                                    }
                                }
                                Column {
                                    width: (parent.width - 20 * page.ui.u) / 3
                                    Text { text: "Tipo de cambio"; color: S.muted; font.family: page.ui.fontFamily; font.pixelSize: 13 * page.ui.u }
                                    Text {
                                        width: parent.width; wrapMode: Text.WordWrap
                                        text: page.rate.rate === undefined || page.rate.rate === null ? "Sin registrar" : String(page.rate.rate) + " PEN/USD"
                                        color: S.text; font.family: page.ui.fontFamily; font.pixelSize: 16 * page.ui.u; font.weight: Font.DemiBold
                                    }
                                    Text {
                                        width: parent.width; wrapMode: Text.WordWrap
                                        visible: page.rate.rate !== undefined && page.rate.rate !== null
                                        text: page.rate.mode === "AUTOMATIC"
                                              ? "BCRP/SBS" + (S.text_(page.rate, "quoted_on").length ? " venta del " + S.date(page.rate.quoted_on) : "")
                                              : "Manual"
                                        color: S.muted; font.family: page.ui.fontFamily; font.pixelSize: 12 * page.ui.u
                                    }
                                    Text {                       // estado de la consulta actual (no del valor guardado)
                                        width: parent.width; wrapMode: Text.WordWrap
                                        visible: page.quoteNotice.length > 0
                                        text: page.quoteNotice
                                        color: S.danger; font.family: page.ui.fontFamily; font.pixelSize: 11 * page.ui.u
                                    }
                                }
                            }
                        }
                    }
                }
                Divider {}

                // ---- Documentos
                Block {
                    order: 5
                    Row {
                        width: parent.width
                        spacing: 16 * page.ui.u
                        IconBadge { glyph: 0xE0CC; tone: S.corporateGreen }
                        Column {
                            width: parent.width - 70 * page.ui.u
                            spacing: 8 * page.ui.u
                            Text { text: "Documentos"; color: S.text; font.family: page.ui.fontFamily; font.pixelSize: 18 * page.ui.u; font.weight: Font.DemiBold }
                            Check { ok: page.hasFolder; label: page.hasFolder ? "Carpeta en InGe Drive conectada" : "Sin carpeta en InGe Drive" }
                            Check { ok: page.exportable; label: page.exportable ? "Exportación PDF/Excel disponible" : "Exportación al presentar la rendición" }
                            Text {
                                width: parent.width
                                text: page.expensesKnown ? page.withSupport + " con sustento  •  " + (page.expenses.length - page.withSupport) + " sin sustento"
                                                         : "Sustentos por cargar"
                                color: S.muted; font.family: page.ui.fontFamily; font.pixelSize: 15 * page.ui.u
                            }
                        }
                    }
                }
                Divider {}

                // ---- Revisión
                Block {
                    order: 6
                    Row {
                        width: parent.width
                        spacing: 16 * page.ui.u
                        IconBadge { glyph: 0xE1F5; tone: S.statusColor(page.current.status) }
                        Column {
                            width: parent.width - 70 * page.ui.u
                            spacing: 4 * page.ui.u
                            Text { text: "Revisión"; color: S.text; font.family: page.ui.fontFamily; font.pixelSize: 18 * page.ui.u; font.weight: Font.DemiBold }
                            Row {
                                spacing: 8 * page.ui.u
                                Rectangle { width: 12 * page.ui.u; height: width; radius: width / 2; color: S.statusColor(page.current.status); anchors.verticalCenter: parent.verticalCenter }
                                Text {
                                    text: page.ctl.statusLabel(String(page.current.status || "BORRADOR"))
                                          + (Number(page.current.versionNumber || 0) > 0 ? "  •  Versión " + page.current.versionNumber : "  •  Sin versión presentada")
                                    color: S.text; font.family: page.ui.fontFamily; font.pixelSize: 15 * page.ui.u
                                }
                            }
                            Text {
                                width: parent.width; wrapMode: Text.WordWrap
                                text: page.writable ? "Edición autorizada" : "Solo lectura"
                                color: S.muted; font.family: page.ui.fontFamily; font.pixelSize: 13 * page.ui.u
                            }
                        }
                    }
                }
            }
        }
    }

    // ---- Indicador circular de actualización (mismo patrón que la lista).
    Item {
        id: spinner
        width: 34 * page.ui.u; height: width
        anchors.horizontalCenter: parent.horizontalCenter
        visible: page.tab === "summary" && opacity > 0.01
        y: header.height + (page.refreshing ? 10 * page.ui.u : -34 * page.ui.u + Math.min(page.pull, page.pullThreshold) * 0.6)
        opacity: page.refreshing ? 1 : Math.min(1, page.pull / page.pullThreshold)
        Behavior on opacity { enabled: !flick.dragging; NumberAnimation { duration: 220 } }
        Behavior on y { enabled: !flick.dragging; NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
        Rectangle { anchors.fill: parent; radius: width / 2; color: "#FFFFFF"; border.width: 1; border.color: S.ink(0.06) }
        Item {
            anchors.fill: parent
            anchors.margins: 8 * page.ui.u
            rotation: page.refreshing ? 0 : page.pull * 3
            Shape {
                anchors.fill: parent
                RotationAnimator on rotation {
                    from: 0; to: 360; duration: 900
                    loops: Animation.Infinite
                    running: page.refreshing && page.visible
                }
                ShapePath {
                    strokeColor: S.corporateBlue
                    strokeWidth: 3 * page.ui.u
                    fillColor: "transparent"
                    capStyle: ShapePath.RoundCap
                    PathAngleArc {
                        centerX: 9 * page.ui.u; centerY: 9 * page.ui.u
                        radiusX: 7.5 * page.ui.u; radiusY: 7.5 * page.ui.u
                        startAngle: -90
                        sweepAngle: page.refreshing ? 280 : 300 * Math.min(1, page.pull / page.pullThreshold)
                    }
                }
            }
        }
    }
}

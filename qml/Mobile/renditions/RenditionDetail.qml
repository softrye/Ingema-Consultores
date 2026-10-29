import QtQuick
import "RStyle.js" as S

// Vista inicial aprobada: resumen compacto y gastos expandibles.
// Finanzas, documentos y revisión conservan sus componentes y contratos.
Item {
    id: page
    property var app
    property string localId: ""
    property int selectionToken: 0                    // apertura (select) que muestra esta página
    readonly property var ui: app.ui
    readonly property var ctl: app.ctl
    readonly property bool ownHeader: true              // el shell no dibuja su barra
    readonly property bool isRenditionDetail: true      // contexto de Dock «rendición abierta»
    readonly property bool renderInteractionBusy: expensesTabItem.renderInteractionBusy
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
    // Gastos es la vista inicial; las secciones existentes siguen accesibles.
    property string tab: "expenses"

    // ---- Transición entre secciones (direccional, con paralaje y profundidad).
    // La sección nueva entra desde el lado del icono elegido (OutQuint, 460 ms)
    // mientras la anterior retrocede, se reduce y se desvanece (OutCubic, 280 ms).
    // Sólo transformaciones y opacidad (sin blur ni relayout): apto para el A12.
    // Movimiento reducido: cambio directo.
    readonly property var sectionOrder: ["expenses", "financial", "documents", "review"]
    property string shownTab: "expenses"            // sección asentada (antes del cambio)
    property string leavingTab: ""
    property real sectionDir: 1
    property real tIn: 1
    property real tOut: 1
    readonly property bool sectionAnimating: sectionAnim.running
    onTabChanged: {
        if (tab === shownTab) return
        if (ui.reducedMotion === true) { leavingTab = ""; shownTab = tab; tIn = 1; tOut = 1; return }
        sectionAnim.stop()
        sectionDir = sectionOrder.indexOf(tab) >= sectionOrder.indexOf(shownTab) ? 1 : -1
        leavingTab = shownTab
        shownTab = tab
        tIn = 0; tOut = 0
        sectionAnim.start()
    }
    ParallelAnimation {
        id: sectionAnim
        NumberAnimation { target: page; property: "tIn"; from: 0; to: 1; duration: 460; easing.type: Easing.OutQuint }
        NumberAnimation { target: page; property: "tOut"; from: 0; to: 1; duration: 280; easing.type: Easing.OutCubic }
        onFinished: page.leavingTab = ""
    }
    function sectionVisible(key) { return tab === key || (leavingTab === key && tOut < 1) }
    function sectionX(key, w) {
        if (key === tab) return w * 0.30 * sectionDir * (1 - tIn)
        if (key === leavingTab) return -w * 0.18 * sectionDir * tOut
        return 0
    }
    function sectionOpacity(key) {
        if (key === tab) return Math.min(1, 0.15 + tIn * 1.1)
        if (key === leavingTab) return Math.max(0, 1 - tOut * 1.25)
        return 1
    }
    function sectionScale(key) {
        if (key === tab) return 0.97 + 0.03 * tIn
        if (key === leavingTab) return 1 - 0.04 * tOut
        return 1
    }
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

    readonly property string clientName: S.text_(current, "clientName", "client_name") || S.text_(project, "clientName", "client_name")
    readonly property string locationName: S.text_(current, "location", "locationName") || S.text_(project, "location", "locationName")

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
    readonly property var expensesTab: expensesTabItem          // Buscar del Dock (filtro/orden reales)
    function handleBack() {
        if (tab === "expenses" && expensesTabItem.handleBack()) return true
        if (tab !== "expenses") { tab = "expenses"; return true }
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
    readonly property real pull: page.tab === "review" ? reviewTabItem.pull : expensesTabItem.pull
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
        height: page.ui.topInset + Math.max(headerText.height, 48 * page.ui.u) + 74 * page.ui.u
        Rectangle {
            x: page.ui.gutter
            y: page.ui.topInset + 4 * page.ui.u
            width: 42 * page.ui.u; height: width; radius: width / 2
            color: S.cardGlass
            border.width: 1; border.color: S.edge(1)
            Text {
                anchors.centerIn: parent
                text: String.fromCharCode(0xE06E)
                font.family: page.ui.iconFamily; font.pixelSize: 26 * page.ui.u
                color: S.navy
            }
            MouseArea { anchors.fill: parent; anchors.margins: -1 * page.ui.u; onClicked: if (!page.handleBack()) page.app.closePage() }
            Accessible.role: Accessible.Button
            Accessible.name: "Atrás"
        }
        Column {
            id: headerText
            x: page.ui.gutter + 54 * page.ui.u
            width: parent.width - x - page.ui.gutter
            y: page.ui.topInset + 6 * page.ui.u
            spacing: 6 * page.ui.u
            opacity: page.reveal(0)
            Text {
                // Título completo: se ajusta al ancho antes de recortarse (sin «Prueba Usabilid…»).
                width: parent.width
                text: page.title
                color: S.text; elide: Text.ElideRight
                fontSizeMode: Text.HorizontalFit; minimumPixelSize: 16 * page.ui.u
                font.family: page.ui.fontFamily; font.pixelSize: 24 * page.ui.u; font.weight: Font.Bold
            }
            Text {
                width: parent.width
                text: [page.clientName.length ? "Cliente: " + page.clientName : "",
                       page.locationName.length ? "Ubicación: " + page.locationName : ""].filter(function(v) { return v.length }).join("  |  ")
                visible: text.length > 0
                color: S.muted; wrapMode: Text.WordWrap
                font.family: page.ui.fontFamily; font.pixelSize: 11 * page.ui.u
            }
            Text {
                width: parent.width; visible: page.tab !== "expenses"
                text: page.projectLine; color: S.muted; elide: Text.ElideRight
                font.family: page.ui.fontFamily; font.pixelSize: 12 * page.ui.u
            }
            Rectangle {                               // comentario del revisor (último), como en la Web
                readonly property var note: (page.app.reviewNotes || []).length ? page.app.reviewNotes[page.app.reviewNotes.length - 1] : null
                visible: note !== null && String(page.current.status || "") === "OBSERVADO"
                width: parent.width; height: visible ? noteText.implicitHeight + 16 * page.ui.u : 0
                radius: 12 * page.ui.u; color: Qt.rgba(242 / 255, 178 / 255, 27 / 255, S.dark ? 0.18 : 0.14)
                border.width: 1; border.color: Qt.rgba(242 / 255, 178 / 255, 27 / 255, 0.45)
                Text { id: noteText; x: 10 * page.ui.u; width: parent.width - 20 * page.ui.u; anchors.verticalCenter: parent.verticalCenter
                       wrapMode: Text.WordWrap; maximumLineCount: 3; elide: Text.ElideRight; color: S.text
                       text: parent.note ? "Observación del revisor: " + String(parent.note.body || "") : ""
                       font.family: page.ui.fontFamily; font.pixelSize: 12.5 * page.ui.u }
                MouseArea { anchors.fill: parent; onClicked: page.app.dockCommand("renditions.review.notes") }
            }
            Row {                                     // en vivo: quién más tiene abierta la rendición
                visible: (page.app.livePeers || []).length > 0
                spacing: 8 * page.ui.u
                Row {
                    spacing: -6 * page.ui.u
                    Repeater {
                        model: (page.app.livePeers || []).slice(0, 3)
                        delegate: Rectangle {
                            required property var modelData
                            width: 24 * page.ui.u; height: width; radius: width / 2
                            color: S.accent; border.width: 2; border.color: S.background
                            Text { anchors.centerIn: parent; text: String(parent.modelData.initials || "?"); color: S.onAccent
                                   font.family: page.ui.fontFamily; font.pixelSize: 9.5 * page.ui.u; font.weight: Font.Bold }
                        }
                    }
                }
                Rectangle { anchors.verticalCenter: parent.verticalCenter; width: 7 * page.ui.u; height: width; radius: width / 2
                            color: page.app.liveJoined ? "#3DA35D" : "#E8A21A" }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: {
                        var p = page.app.livePeers || []
                        var first = String((p[0] || {}).name || "").split(" ")[0]
                        return p.length === 1 ? first + " también la tiene abierta" : p.length + " personas la tienen abierta"
                    }
                    color: S.muted; font.family: page.ui.fontFamily; font.pixelSize: 11.5 * page.ui.u
                }
            }
        }
        // Sin botones de cabecera: Documentos está en la barra de secciones e
        // Información en el Dock (se evitan accesos duplicados).
        Rectangle {
            id: sectionBar
            objectName: "renditionSectionBar"
            x: page.ui.gutter; width: parent.width - 2 * x
            anchors.bottom: parent.bottom; anchors.bottomMargin: 12 * page.ui.u
            height: 50 * page.ui.u; radius: height / 2
            color: "transparent"
            Rectangle {                                  // píldora retirada: sólo brilla el icono
                id: sectionPill
                visible: false
                readonly property real cell: sectionLayout.width / 4
                readonly property int index: Math.max(0, page.sectionOrder.indexOf(page.tab))
                property real stretch: 0
                y: 3 * page.ui.u
                height: parent.height - 6 * page.ui.u
                radius: height / 2
                x: 3 * page.ui.u + index * cell - stretch * cell * 0.10
                width: cell + stretch * cell * 0.20
                color: S.glass(0.92)
                border.width: 1; border.color: Qt.rgba(6 / 255, 84 / 255, 162 / 255, 0.10)
                Behavior on x { enabled: page.ui.reducedMotion !== true
                                SpringAnimation { spring: 4.2; damping: 0.36; epsilon: 0.25 } }
                onIndexChanged: if (page.ui.reducedMotion !== true) pillStretch.restart()
                SequentialAnimation {
                    id: pillStretch
                    NumberAnimation { target: sectionPill; property: "stretch"; to: 1; duration: 120; easing.type: Easing.OutQuad }
                    NumberAnimation { target: sectionPill; property: "stretch"; to: 0; duration: 340; easing.type: Easing.OutBack; easing.overshoot: 1.6 }
                }
                Rectangle {                              // subrayado que acompaña a la píldora
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.bottom: parent.bottom
                    width: parent.width - 20 * page.ui.u
                    height: 3 * page.ui.u; radius: height / 2
                    color: S.accentSoft
                }
            }
            Row {
                id: sectionLayout
                anchors.fill: parent; anchors.margins: 3 * page.ui.u
                Repeater {
                    model: ["expenses", "financial", "documents", "review"]
                    delegate: Rectangle {
                        id: sectionTile
                        required property string modelData
                        objectName: "renditionSection:" + modelData
                        readonly property bool selected: page.tab === modelData
                        readonly property int glyph: modelData === "expenses" ? 0xE086
                            : modelData === "financial" ? 0xE06B : modelData === "documents" ? 0xE12D : 0xE16A
                        width: sectionLayout.width / 4; height: sectionLayout.height; radius: height / 2
                        color: "transparent"
                        // Barra sólo de iconos: el nombre queda en Accessible.name (lectores de pantalla).
                        Rectangle {                      // brillo suave del icono activo
                            anchors.centerIn: parent
                            width: 40 * page.ui.u; height: width; radius: width / 2
                            color: S.accent
                            opacity: sectionTile.selected ? 0.14 : 0
                            Behavior on opacity { NumberAnimation { duration: 220 } }
                        }
                        Text { anchors.centerIn: parent; text: String.fromCharCode(sectionTile.glyph)
                               font.family: page.ui.iconFamily; font.pixelSize: 22 * page.ui.u
                               color: sectionTile.selected ? S.accent : S.muted
                               scale: sectionTile.selected ? 1.12 : (tileTap.pressed ? 0.9 : 1)
                               Behavior on color { ColorAnimation { duration: 220 } }
                               Behavior on scale { enabled: page.ui.reducedMotion !== true
                                                   NumberAnimation { duration: 260; easing.type: Easing.OutBack; easing.overshoot: 2.0 } } }
                        MouseArea {
                            id: tileTap
                            anchors.fill: parent; enabled: !page.app.modalOpen
                            onClicked: {
                                if (page.tab === sectionTile.modelData) return
                                page.app.haptic("selection")
                                page.expensesTab.persistExpanded()
                                page.showSection(sectionTile.modelData)
                            }
                        }
                        Accessible.role: Accessible.Button
                        Accessible.name: page.sectionTitles[sectionTile.modelData]
                        Accessible.checked: sectionTile.selected
                    }
                }
            }
        }
    }

    // ------------------------------------------------- Secciones secundarias
    Item {
        anchors.top: header.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        visible: true
        id: sectionStage
        clip: page.sectionAnimating
        RenditionExpenses { id: expensesTabItem; objectName: "expensesTab"; width: parent.width; height: parent.height; detail: page
                            visible: page.sectionVisible("expenses"); x: page.sectionX("expenses", width)
                            opacity: page.sectionOpacity("expenses"); scale: page.sectionScale("expenses")
                            z: page.tab === "expenses" ? 1 : 0 }
        RenditionFinancial { objectName: "financialTab"; width: parent.width; height: parent.height; detail: page
                             visible: page.sectionVisible("financial"); x: page.sectionX("financial", width)
                             opacity: page.sectionOpacity("financial"); scale: page.sectionScale("financial")
                             z: page.tab === "financial" ? 1 : 0 }
        RenditionDocuments { objectName: "documentsTab"; width: parent.width; height: parent.height; detail: page
                             visible: page.sectionVisible("documents"); x: page.sectionX("documents", width)
                             opacity: page.sectionOpacity("documents"); scale: page.sectionScale("documents")
                             z: page.tab === "documents" ? 1 : 0 }
        RenditionReview { id: reviewTabItem; objectName: "reviewTab"; width: parent.width; height: parent.height; detail: page
                          visible: page.sectionVisible("review"); x: page.sectionX("review", width)
                          opacity: page.sectionOpacity("review"); scale: page.sectionScale("review")
                          z: page.tab === "review" ? 1 : 0 }
    }

}

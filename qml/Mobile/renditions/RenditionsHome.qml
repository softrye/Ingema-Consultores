import QtQuick
import QtQuick.Shapes
import "RStyle.js" as S

// Pantalla principal aprobada (variante clara): título centrado, panel
// «Tus proyectos» (menú de proyectos) con All / ••• (estado de ficha o
// Recibidas), tarjetas reales y deslizar para actualizar con el comando real
// `sync` (indicador circular, sin aviso de éxito). Los dos filtros son
// independientes: All sólo restablece el estado/vista; «Todos los proyectos»
// sólo restablece el proyecto. Filtrar nunca cambia el estado de una ficha.
Item {
    id: page
    objectName: "renditionsHome"
    property var app
    readonly property var ui: app.ui
    readonly property var ctl: app.ctl
    readonly property string title: "Rendiciones"
    property string statusFilter: ""            // "" = All | BORRADOR | OBSERVADO | EN_REVISION | APROBADO | RECEIVED
    property string projectFilter: ""           // "" = todos los proyectos (UUID real)
    readonly property bool receivedView: statusFilter === "RECEIVED"
    readonly property var life: ({ alive: true })
    Component.onDestruction: life.alive = false

    readonly property var own: {
        app.st                                   // dependencia del último estado
        return ctl && !receivedView ? ctl.filterRenditions("", statusFilter, projectFilter) : []
    }
    readonly property var receivedVisible: receivedView
        ? received.filter(function(r) { return !projectFilter.length || S.text_(r, "primary_project_id") === projectFilter })
        : []
    ListModel { id: ownModel }
    ListModel { id: receivedModel }
    onOwnChanged: S.syncRows(ownModel, own, ["localId"])
    onReceivedVisibleChanged: S.syncRows(receivedModel, receivedVisible, ["rendition_id", "version_number"])
    Component.onCompleted: {
        S.syncRows(ownModel, own, ["localId"])
        S.syncRows(receivedModel, receivedVisible, ["rendition_id", "version_number"])
    }
    readonly property bool syncBusy: app.busy("sync") || app.phase !== "IDLE"
    readonly property var filterLabels: ({ "BORRADOR": "Borrador", "OBSERVADO": "Observadas",
                                           "EN_REVISION": "En revisión", "APROBADO": "Aprobadas",
                                           "RECEIVED": "Recibidas" })
    readonly property string projectFilterLabel: projectFilter.length && ctl ? ctl.projectLabel(projectFilter) : ""

    function handleBack() {
        if (filterMenu.open) { filterMenu.close(); return true }
        if (projectMenu.open) { projectMenu.close(); return true }
        return false
    }
    function closeMenus() { filterMenu.close(); projectMenu.close() }
    readonly property bool listInteractive: flick.interactive
    readonly property bool renderInteractionBusy: filterMenu.visible || projectMenu.visible || cardMenu.visible
    function selectStatus(value) {
        statusFilter = value
        if (value === "RECEIVED" && !receivedLoaded) loadReceived()
    }

    // ------------------------------------------- Recibidas (vista del filtro)
    // Misma fuente real (list_received_renditions_v02, paginada); se consulta
    // al elegir «Recibidas» y al actualizar desde esa vista.
    property var received: []
    property bool receivedLoading: false
    property bool receivedLoaded: false
    property string receivedError: ""
    function loadReceived(done) {
        if (receivedLoading) { if (done) done(); return }
        receivedLoading = true
        receivedError = ""
        fetchReceived({}, [], {}, done)
    }
    function fetchReceived(cursor, rows, seen, done) {
        var life = page.life
        app.call("receivedList", cursor, "receivedList", function(ok, result, code, message) {
            if (!life.alive) return
            if (!ok) {
                page.receivedLoading = false
                page.receivedLoaded = true
                page.receivedError = String(code).indexOf("FORBIDDEN") >= 0 || String(code).indexOf("403") >= 0
                        ? "Tu cuenta no tiene rendiciones recibidas para revisar."
                        : page.app.errorText(code, message)
                if (done) done()
                return
            }
            var pageRows = result.rows || []
            for (var i = 0; i < pageRows.length; ++i) {
                var id = S.text_(pageRows[i], "rendition_id")
                if (seen[id]) continue                 // sin duplicados
                seen[id] = true
                rows.push(pageRows[i])
            }
            if (pageRows.length >= 200) {
                var last = pageRows[pageRows.length - 1]
                page.fetchReceived({ afterSubmittedAt: S.text_(last, "submitted_at"), afterId: S.text_(last, "rendition_id") }, rows, seen, done)
                return
            }
            page.received = rows
            page.receivedLoading = false
            page.receivedLoaded = true
            if (done) done()
        })
    }

    // -------------------------------------------- Deslizar para actualizar
    readonly property real pullThreshold: 76 * ui.u
    readonly property real pull: Math.max(0, flick.originY - flick.contentY - flick.topMargin)
    property bool refreshing: false
    function refreshFromPull() {
        if (refreshing || syncBusy) return            // nunca dos sincronizaciones
        refreshing = true
        page.app.haptic("light")
        var life = page.life
        var id = page.app.synchronize(true, function() {
            if (!life.alive) return
            if (page.receivedView) page.loadReceived(function() { page.refreshing = false })
            else page.refreshing = false
        })
        if (!id.length) refreshing = false
    }

    Flickable {
        id: flick
        anchors.fill: parent
        contentWidth: width
        contentHeight: panel.y + panel.height
        boundsBehavior: Flickable.DragOverBounds
        // Con la hoja «Nueva rendición» (u otro menú modal) abierta, la lista no se mueve.
        interactive: !(page.app && page.app.modalOpen === true)
        // Mientras sincroniza, la lista deja un hueco superior para el indicador.
        topMargin: page.refreshing ? 56 * page.ui.u : 0
        Behavior on topMargin { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
        clip: true
        onDragEnded: if (page.pull >= page.pullThreshold) page.refreshFromPull()

        Column {
            id: header
            width: parent.width
            y: page.ui.topInset + 26 * page.ui.u
            spacing: 6 * page.ui.u
            Text {
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                text: "Rendiciones"
                color: S.text
                font.family: page.ui.fontFamily
                font.pixelSize: 44 * page.ui.u
                font.weight: Font.Bold
                font.letterSpacing: -1.2 * page.ui.u
            }
            Text {
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                text: "Track your reports"
                color: S.muted
                font.family: page.ui.fontFamily
                font.pixelSize: 19 * page.ui.u
            }
        }

        Rectangle {                                     // panel «Tus proyectos»
            id: panel
            x: 12 * page.ui.u
            width: parent.width - 24 * page.ui.u
            y: header.y + header.height + 30 * page.ui.u
            // Reserva final = altura del dock flotante + respiro: la última
            // tarjeta puede desplazarse por completo sobre el dock.
            height: Math.max(column.height + 22 * page.ui.u + page.ui.dockArea + 12 * page.ui.u,
                             flick.height - y + 30 * page.ui.u)
            radius: 30 * page.ui.u
            color: S.glass(0.38)              // deja percibir las auras (tarjetas siguen al 90%)
            border.width: 1
            border.color: S.edge(0.95)
        }

        Column {
            id: column
            x: panel.x + 18 * page.ui.u
            width: panel.width - 36 * page.ui.u
            y: panel.y + 22 * page.ui.u
            spacing: 18 * page.ui.u

            Item {
                width: parent.width
                height: 40 * page.ui.u
                Row {                                              // «Tus proyectos» ▾ = selector
                    id: projectsTitle
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 6 * page.ui.u
                    Text {
                        text: "Tus proyectos"
                        color: S.text
                        font.family: page.ui.fontFamily
                        font.pixelSize: 22 * page.ui.u
                        font.weight: Font.DemiBold
                    }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: String.fromCharCode(0xE06F)
                        rotation: projectMenu.open ? 270 : 90
                        Behavior on rotation { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
                        font.family: page.ui.iconFamily
                        font.pixelSize: 16 * page.ui.u
                        color: page.projectFilter.length ? S.corporateBlue : S.muted
                    }
                    Accessible.role: Accessible.Button
                    Accessible.name: "Filtrar por proyecto"
                }
                MouseArea {
                    anchors.fill: projectsTitle
                    anchors.margins: -10 * page.ui.u
                    onClicked: {
                        if (projectMenu.open) { projectMenu.close(); return }
                        page.closeMenus()
                        var p = projectsTitle.mapToItem(page, projectsTitle.width * 0.35, projectsTitle.height)
                        projectMenu.anchorX = p.x
                        projectMenu.anchorY = p.y
                        page.app.haptic("light")
                        projectMenu.open = true
                    }
                }
                Text {
                    id: allButton
                    anchors.right: dots.left
                    anchors.rightMargin: 18 * page.ui.u
                    anchors.verticalCenter: parent.verticalCenter
                    text: "All"
                    color: S.corporateBlue
                    font.family: page.ui.fontFamily
                    font.pixelSize: 21 * page.ui.u
                    font.weight: page.statusFilter.length ? Font.Normal : Font.DemiBold
                    MouseArea {
                        anchors.fill: parent; anchors.margins: -12 * page.ui.u
                        onClicked: { page.statusFilter = ""; page.closeMenus() }   // conserva el proyecto
                    }
                    Accessible.role: Accessible.Button
                    Accessible.name: "Mostrar todos los estados"
                }
                Item {
                    id: dots
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    width: 40 * page.ui.u; height: 40 * page.ui.u
                    Repeater {                                      // ••• (vertical con el menú abierto)
                        model: 3
                        delegate: Rectangle {
                            required property int index
                            width: 6 * page.ui.u; height: width; radius: width / 2
                            color: S.ink(0.55)
                            x: filterMenu.open ? (dots.width - width) / 2 : (dots.width - width) / 2 + (index - 1) * 10 * page.ui.u
                            y: filterMenu.open ? (dots.height - height) / 2 + (index - 1) * 9 * page.ui.u : (dots.height - height) / 2
                            Behavior on x { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
                            Behavior on y { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
                        }
                    }
                    MouseArea {
                        anchors.fill: parent
                        onClicked: {
                            if (filterMenu.open) { filterMenu.close(); return }
                            page.closeMenus()
                            var p = dots.mapToItem(page, dots.width / 2, dots.height)
                            filterMenu.anchorX = p.x - 80 * page.ui.u
                            filterMenu.anchorY = p.y
                            page.app.haptic("light")
                            filterMenu.open = true
                        }
                    }
                    Accessible.role: Accessible.Button
                    Accessible.name: "Filtrar por estado"
                }
            }
            Text {                                                   // filtros activos
                width: parent.width
                visible: page.projectFilter.length > 0 || page.statusFilter.length > 0
                text: [page.projectFilterLabel, page.filterLabels[page.statusFilter] || ""].filter(function(s) { return s.length }).join("  ·  ")
                color: S.corporateBlue
                elide: Text.ElideRight
                font.family: page.ui.fontFamily; font.pixelSize: 14 * page.ui.u
            }

            // Sesión expirada, desconexión y fallas de arranque NO se anuncian con
            // recuadros: las comunica el aura y se consultan (con su acción real)
            // en "Estado de Rendiciones" desde el Dock.

            Text {
                width: parent.width
                visible: !page.ctl || !page.ctl.ready || (page.receivedView && page.receivedLoading && !page.receivedLoaded)
                horizontalAlignment: Text.AlignHCenter
                text: page.receivedView ? "Consultando rendiciones recibidas…" : "Cargando tus rendiciones…"
                color: S.muted
                font.family: page.ui.fontFamily; font.pixelSize: 15 * page.ui.u
            }
            Column {                                                 // estado vacío
                width: parent.width
                visible: !!page.ctl && page.ctl.ready
                         && (page.receivedView ? page.receivedLoaded && page.receivedVisible.length === 0 : page.own.length === 0)
                spacing: 8 * page.ui.u
                topPadding: 24 * page.ui.u
                bottomPadding: 24 * page.ui.u
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: String.fromCharCode(0xE0CC)
                    font.family: page.ui.iconFamily; font.pixelSize: 34 * page.ui.u
                    color: S.faint
                }
                Text {
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.WordWrap
                    text: page.receivedView && page.receivedError.length ? page.receivedError
                          : page.statusFilter.length || page.projectFilter.length
                            ? "No hay rendiciones para " + [page.filterLabels[page.statusFilter] || "", page.projectFilterLabel].filter(function(s) { return s.length }).join(" · ") + "."
                            : "Aún no tienes rendiciones. Crea la primera con el botón +."
                    color: S.muted
                    font.family: page.ui.fontFamily; font.pixelSize: 15 * page.ui.u
                }
            }

            Repeater {                                              // propias
                model: ownModel
                delegate: RenditionCard {
                    required property string rowJson
                    readonly property var modelData: JSON.parse(rowJson)
                    width: column.width
                    ui: page.ui
                    ctl: page.ctl
                    row: modelData
                    onActivated: page.app.openDetail(String(modelData.localId))
                    onHeld: page.openCardMenu(modelData, this)
                }
            }
            Repeater {                                              // recibidas (vista «Recibidas»)
                model: receivedModel
                delegate: RenditionCard {
                    required property string rowJson
                    readonly property var modelData: JSON.parse(rowJson)
                    width: column.width
                    ui: page.ui
                    ctl: page.ctl
                    progressOverride: null
                    row: ({ visibleCode: S.text_(modelData, "visible_code") + " · v" + (modelData.version_number || "?"),
                             displayName: S.text_(modelData, "displayName", "display_name"),
                            primaryProjectId: S.text_(modelData, "primary_project_id"),
                            primaryProjectName: [S.text_(modelData, "owner_name"), S.text_(modelData, "primary_project_name")].filter(function(s) { return s.length }).join(" · "),
                            periodStart: modelData.period_start, periodEnd: modelData.period_end,
                            totalPen: modelData.total_declared_pen, totalUsd: modelData.total_declared_usd,
                            expenseCount: modelData.expense_count, status: modelData.status })
                    onActivated: page.app.openReceived(modelData)
                }
            }
        }
    }

    // ---- Indicador circular de actualización (azul corporativo).
    Item {
        id: spinner
        width: 34 * page.ui.u; height: width
        anchors.horizontalCenter: parent.horizontalCenter
        y: page.refreshing ? page.ui.topInset + 14 * page.ui.u
                           : page.ui.topInset - 30 * page.ui.u + Math.min(page.pull, page.pullThreshold) * 0.6
        opacity: page.refreshing ? 1 : Math.min(1, page.pull / page.pullThreshold)
        visible: opacity > 0.01
        Behavior on opacity { enabled: !flick.dragging; NumberAnimation { duration: 220 } }
        Behavior on y { enabled: !flick.dragging; NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
        Rectangle { anchors.fill: parent; radius: width / 2; color: S.glass(1); border.width: 1; border.color: S.ink(0.06) }
        Item {                                              // giro del gesto (antes de soltar)
            anchors.fill: parent
            anchors.margins: 8 * page.ui.u
            rotation: page.refreshing ? 0 : page.pull * 3
        Shape {                                             // giro continuo mientras sincroniza
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

    // ---- Menú de estado / vista (tipo Haptic Touch).
    RGlassMenu {
        id: filterMenu
        ui: page.ui
        above: false
        cardWidth: 250 * page.ui.u
        Repeater {
            model: [["BORRADOR", "Borrador", 0xE0CC], ["OBSERVADO", "Observadas", 0xE0F9],
                    ["EN_REVISION", "En revisión", 0xE1F5], ["APROBADO", "Aprobadas", 0xE06C],
                    ["RECEIVED", "Recibidas", 0xE0B2]]
            delegate: RMenuItem {
                required property var modelData
                required property int index
                ui: page.ui
                label: modelData[1]
                glyph: modelData[2]
                glyphColor: page.statusFilter === modelData[0] ? S.corporateBlue : S.muted
                separator: index < 4
                onActivated: {
                    page.selectStatus(modelData[0])
                    page.app.haptic("selection")
                    filterMenu.close()
                }
            }
        }
    }

    // ---- Menú de proyectos autorizados (imagen 3): lista compacta con nombres
    // descriptivos reales; la selección se indica con AURA (sin check ni carpeta).
    // ··· = «Nueva rendición en este proyecto» (abre la hoja con el proyecto marcado).
    function newRenditionIn(projectId) {
        projectMenu.close()
        page.app.openCreate()
        if (!projectId.length) return
        Qt.callLater(function() {
            var e = page.app.createSheetEditor
            if (!e || e.projects.indexOf(projectId) >= 0) return
            e.toggleProject(projectId)
            e.setPrimary(projectId)
        })
    }
    component ProjectRow: Item {
        id: row
        property var ui
        property string title: ""
        property string subtitle: ""
        property bool selected: false
        property bool separator: true
        signal activated()
        signal more()
        width: parent ? parent.width : 0
        height: (subtitle.length ? 76 : 62) * ui.u
        Rectangle {                                  // aura de selección
            anchors.fill: parent; anchors.margins: 3 * row.ui.u
            radius: 22 * row.ui.u
            color: row.selected ? Qt.rgba(59 / 255, 130 / 255, 214 / 255, 0.16) : (rowTap.pressed ? S.ink(0.05) : "transparent")
            border.width: row.selected ? 1 : 0
            border.color: Qt.rgba(59 / 255, 130 / 255, 214 / 255, 0.30)
            Behavior on color { ColorAnimation { duration: 160 } }
        }
        Column {
            x: 18 * row.ui.u; width: parent.width - x - 56 * row.ui.u
            anchors.verticalCenter: parent.verticalCenter
            spacing: 2 * row.ui.u
            Text { width: parent.width; text: row.title; color: row.selected ? S.navyDark : S.text; elide: Text.ElideRight
                   font.family: row.ui.fontFamily; font.pixelSize: 18 * row.ui.u; font.weight: Font.DemiBold }
            Text { width: parent.width; visible: row.subtitle.length > 0; text: row.subtitle; color: S.muted; elide: Text.ElideRight
                   font.family: row.ui.fontFamily; font.pixelSize: 13 * row.ui.u }
        }
        MouseArea { id: rowTap; anchors.fill: parent; onClicked: row.activated() }
        Rectangle {
            width: 44 * row.ui.u; height: width; radius: width / 2
            anchors.right: parent.right; anchors.rightMargin: 6 * row.ui.u
            anchors.verticalCenter: parent.verticalCenter
            color: moreTap.pressed ? S.ink(0.08) : "transparent"
            Text { anchors.centerIn: parent; text: String.fromCharCode(0xE0B6); color: S.muted
                   font.family: row.ui.iconFamily; font.pixelSize: 20 * row.ui.u }
            MouseArea { id: moreTap; anchors.fill: parent; onClicked: row.more() }
            Accessible.role: Accessible.Button
            Accessible.name: "Nueva rendición en " + row.title
        }
        Rectangle { visible: row.separator; x: 18 * row.ui.u; width: parent.width - 36 * row.ui.u; height: 1; anchors.bottom: parent.bottom; color: S.ink(0.07) }
    }
    // ---- Pulsación prolongada sobre una rendición (3D Touch: desenfoque global,
    // tarjeta elevada y menú pegado a ella).
    property var cardMenuRow: null
    readonly property bool cardExportable: !!cardMenuRow && String(cardMenuRow.remoteId || "").length > 0
                                           && String(cardMenuRow.currentVersionId || "").length > 0
    // Archivar / Papelera / Eliminar: sólo el dueño (el servidor lo exige).
    readonly property bool cardIsMine: {
        if (!cardMenuRow) return false
        var owner = S.text_(cardMenuRow, "owner_user_id", "ownerUserId")
        var me = typeof auth !== "undefined" && auth ? String(auth.userId || "") : ""
        return !owner.length || !me.length || owner === me
    }
    readonly property bool cardIsDraft: !!cardMenuRow && String(cardMenuRow.status || "BORRADOR").toUpperCase() === "BORRADOR"
    function openCardMenu(row, card) {
        cardMenuRow = row
        page.app.haptic("medium")
        page.app.homeTouchItem = cardMenu.hosted ? card : null
        page.app.homeTouchMenu = cardMenu
        var host = cardMenu.parent
        var p = card.mapToItem(host, card.width / 2, card.height)
        cardMenu.above = p.y > host.height * 0.55
        cardMenu.anchorX = p.x
        cardMenu.anchorY = cardMenu.above ? card.mapToItem(host, 0, 0).y : p.y
        cardMenu.open = true
    }
    RGlassMenu {
        id: cardMenu
        objectName: "renditionCardMenu"
        readonly property bool hosted: !!page.app.touchLayer
        parent: hosted ? page.app.touchLayer : page
        dimBackground: !hosted
        ui: page.ui
        cardWidth: 260 * page.ui.u
        onDismissed: page.app.homeTouchItem = null
        RMenuItem { ui: page.ui; label: "Abrir"; glyph: 0xE0BA; glyphColor: S.accent
                    onActivated: { var id = String(page.cardMenuRow.localId); cardMenu.close(); page.app.openDetail(id) } }
        RMenuItem { ui: page.ui; label: page.cardExportable ? "Exportar PDF" : "Exportar · al presentar"; glyph: 0xE0CC; glyphColor: S.danger
                    enabledItem: page.cardExportable
                    onActivated: { var id = String(page.cardMenuRow.localId); cardMenu.close(); page.app.exportFromList(id, "pdf") } }
        RMenuItem { ui: page.ui; label: "Exportar Excel"; glyph: 0xE086; glyphColor: S.success; visible: page.cardExportable
                    onActivated: { var id = String(page.cardMenuRow.localId); cardMenu.close(); page.app.exportFromList(id, "xlsx") } }
        RMenuItem { objectName: "cardMenuArchive"; ui: page.ui; label: "Archivar"; glyph: 0xE0D7; glyphColor: S.accent
                    visible: page.cardIsMine
                    onActivated: {
                        var row = page.cardMenuRow
                        cardMenu.close()
                        page.app.confirm("Archivar rendición",
                                         "«" + (S.text_(row, "displayName", "display_name") || "La rendición") + "» pasará al Archivero (solo consulta). Podrás reactivarla desde Carpeta › Archivero.",
                                         "Archivar", false, function() {
                            page.app.call("archiveRendition", { localId: String(row.localId) }, "archiveRendition:" + row.localId, function(ok, result, code, message) {
                                if (!ok) page.app.toast(page.app.errorText(code, message), "error")
                            })
                        })
                    } }
        RMenuItem { objectName: "cardMenuTrash"; ui: page.ui; label: "Mover a la Papelera"; glyph: 0xE18E; glyphColor: S.danger
                    visible: page.cardIsDraft && page.cardIsMine
                    onActivated: {
                        var row = page.cardMenuRow
                        cardMenu.close()
                        page.app.confirm("Mover a la Papelera",
                                         "«" + (S.text_(row, "displayName", "display_name") || "La rendición") + "» irá a la Papelera con sus gastos. Podrás restaurarla desde Carpeta › Papelera.",
                                         "Mover", true, function() {
                            page.app.call("trashDraft", { localId: String(row.localId) }, "trashDraft:" + row.localId, function(ok, result, code, message) {
                                if (!ok) page.app.toast(page.app.errorText(code, message), "error")
                            })
                        })
                    } }
        RMenuItem { objectName: "cardMenuDelete"; ui: page.ui; label: "Eliminar borrador"; glyph: 0xE18E; glyphColor: S.danger; separator: false
                    visible: page.cardIsDraft && page.cardIsMine
                    onActivated: {
                        var row = page.cardMenuRow
                        cardMenu.close()
                        page.app.confirm("Eliminar borrador",
                                         "Se eliminará «" + (S.text_(row, "displayName", "display_name") || "la rendición") + "» con sus gastos.",
                                         "Eliminar", true, function() {
                            page.app.call("deleteDraft", { localId: String(row.localId) }, "deleteDraft:" + row.localId, function(ok, result, code, message) {
                                if (!ok) page.app.toast(page.app.errorText(code, message), "error")
                            })
                        })
                    } }
    }

    RGlassMenu {
        id: projectMenu
        objectName: "projectMenu"
        ui: page.ui
        above: false
        cardWidth: 340 * page.ui.u
        ProjectRow {
            ui: page.ui
            title: "Todos los proyectos"
            subtitle: "Sin filtro de proyecto"
            selected: page.projectFilter.length === 0
            onActivated: { page.projectFilter = ""; page.app.haptic("selection"); projectMenu.close() }
            onMore: page.newRenditionIn("")
        }
        Flickable {
            width: parent.width
            height: Math.min(projectList.height, 5 * 62 * page.ui.u)
            contentHeight: projectList.height
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            interactive: contentHeight > height
            Column {
                id: projectList
                width: parent.width
                Repeater {
                    model: page.app.st.projects || []
                    delegate: ProjectRow {
                        required property var modelData
                        required property int index
                        readonly property string projectId: S.text_(modelData, "id", "project_id")
                        width: projectList.width
                        ui: page.ui
                        title: (S.text_(modelData, "name") || page.ctl.projectLabel(projectId)).toUpperCase()
                        selected: page.projectFilter === projectId
                        separator: index < (page.app.st.projects || []).length - 1
                        onActivated: { page.projectFilter = projectId; page.app.haptic("selection"); projectMenu.close() }
                        onMore: page.newRenditionIn(projectId)
                    }
                }
            }
        }
    }
}

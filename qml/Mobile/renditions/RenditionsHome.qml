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
    readonly property bool renderInteractionBusy: filterMenu.visible || projectMenu.visible
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
            color: Qt.rgba(1, 1, 1, 0.38)              // deja percibir las auras (tarjetas siguen al 90%)
            border.width: 1
            border.color: Qt.rgba(1, 1, 1, 0.95)
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
        Rectangle { anchors.fill: parent; radius: width / 2; color: "#FFFFFF"; border.width: 1; border.color: S.ink(0.06) }
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

    // ---- Menú de proyectos autorizados (IDs reales del modelo).
    RGlassMenu {
        id: projectMenu
        ui: page.ui
        above: false
        cardWidth: 300 * page.ui.u
        RMenuItem {
            ui: page.ui
            label: "Todos los proyectos"
            glyph: 0xE0D7
            glyphColor: page.projectFilter.length ? S.muted : S.corporateBlue
            onActivated: { page.projectFilter = ""; page.app.haptic("selection"); projectMenu.close() }
        }
        Flickable {
            width: parent.width
            height: Math.min(projectList.height, 5 * 58 * page.ui.u)
            contentHeight: projectList.height
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            Column {
                id: projectList
                width: parent.width
                Repeater {
                    model: page.app.st.projects || []
                    delegate: RMenuItem {
                        required property var modelData
                        required property int index
                        readonly property string projectId: S.text_(modelData, "id", "project_id")
                        ui: page.ui
                        label: page.ctl.projectLabel(projectId)
                        glyph: page.projectFilter === projectId ? 0xE06C : 0
                        glyphColor: S.corporateBlue
                        separator: index < (page.app.st.projects || []).length - 1
                        onActivated: { page.projectFilter = projectId; page.app.haptic("selection"); projectMenu.close() }
                    }
                }
            }
        }
    }
}

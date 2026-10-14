import QtQuick
import QtQuick.Controls
import "RStyle.js" as S

// Pantalla principal: rendiciones propias (LocalStore + list_renditions_effective_v06)
// y recibidas (list_received_renditions_v02) según los permisos del usuario.
Item {
    id: page
    objectName: "renditionsHome"
    property var app
    readonly property var ui: app.ui
    readonly property var ctl: app.ctl
    readonly property string title: "Rendiciones"
    property string tab: "own"                   // own | received
    property string query: ""
    property string statusFilter: ""
    property string projectFilter: ""
    readonly property var life: ({ alive: true })
    Component.onDestruction: life.alive = false

    readonly property var own: {
        app.st                                   // dependencia del último estado
        return ctl ? ctl.filterRenditions(query, statusFilter, projectFilter) : []
    }
    readonly property var projectOptions: {
        var rows = (app.st.projects || [])
        var options = [{ value: "", label: "Todos los proyectos" }]
        for (var i = 0; i < rows.length; ++i) {
            var id = S.text_(rows[i], "id", "project_id")
            options.push({ value: id, label: ctl.projectLabel(id) })
        }
        return options
    }

    // -------------------------------------------------------------- Recibidas
    property var received: []
    property bool receivedLoaded: false
    property bool receivedLoading: false
    property string receivedError: ""
    function loadReceived() {
        if (receivedLoading) return
        receivedLoading = true
        receivedError = ""
        received = []
        fetchReceived({}, [], {})
    }
    function fetchReceived(cursor, rows, seen) {
        var life = page.life
        app.call("receivedList", cursor, "receivedList", function(ok, result, code, message) {
            if (!life.alive) return
            if (!ok) {
                page.receivedLoading = false
                page.receivedLoaded = true
                page.receivedError = String(code).indexOf("FORBIDDEN") >= 0 || String(code).indexOf("403") >= 0
                        ? "Tu cuenta no tiene autorización para revisar rendiciones recibidas."
                        : app.errorText(code, message)
                return
            }
            var pageRows = result.rows || []
            for (var i = 0; i < pageRows.length; ++i) {
                var id = S.text_(pageRows[i], "rendition_id")
                if (seen[id]) {
                    page.receivedLoading = false
                    page.receivedError = "El servidor repitió una página; actualiza la bandeja."
                    return
                }
                seen[id] = true
                rows.push(pageRows[i])
            }
            if (pageRows.length >= 200) {
                var last = pageRows[pageRows.length - 1]
                page.fetchReceived({ afterSubmittedAt: S.text_(last, "submitted_at"), afterId: S.text_(last, "rendition_id") }, rows, seen)
                return
            }
            page.received = rows
            page.receivedLoading = false
            page.receivedLoaded = true
        })
    }
    readonly property var receivedVisible: {
        var needle = query.trim().toLowerCase()
        if (!needle.length) return received
        return received.filter(function(row) {
            return [row.visible_code, row.owner_name, row.primary_project_code, row.primary_project_name,
                    row.period_start, row.period_end, row.status].join(" ").toLowerCase().indexOf(needle) >= 0
        })
    }

    Flickable {
        anchors.fill: parent
        contentWidth: width
        contentHeight: column.height + 120 * page.ui.u
        boundsBehavior: Flickable.StopAtBounds
        clip: true

        Column {
            id: column
            x: page.ui.gutter
            width: parent.width - 2 * page.ui.gutter
            y: 8 * page.ui.u
            spacing: 12 * page.ui.u

            Row {
                spacing: 8 * page.ui.u
                RChip { ui: page.ui; label: "Mis rendiciones"; selected: page.tab === "own"; onActivated: page.tab = "own" }
                RChip {
                    ui: page.ui; label: "Recibidas"; selected: page.tab === "received"
                    onActivated: { page.tab = "received"; if (!page.receivedLoaded) page.loadReceived() }
                }
            }

            RField {
                width: parent.width
                ui: page.ui
                placeholder: page.tab === "own" ? "Buscar por código, período o proyecto" : "Buscar por código, responsable o proyecto"
                onEdited: page.query = text
            }

            // ---- Estados de conexión / sincronización (siempre visibles)
            Rectangle {
                width: parent.width
                visible: page.app.connection === "OFFLINE" || page.app.connection === "AUTH_REQUIRED" || page.app.bootError.length > 0
                height: visible ? bannerText.implicitHeight + 24 * page.ui.u : 0
                radius: 14 * page.ui.u
                color: Qt.rgba(1, 0.54, 0.5, 0.14)
                border.width: 1; border.color: S.danger
                Text {
                    id: bannerText
                    x: 14 * page.ui.u; width: parent.width - 28 * page.ui.u
                    anchors.verticalCenter: parent.verticalCenter
                    wrapMode: Text.WordWrap
                    color: S.text
                    font.family: page.ui.fontFamily; font.pixelSize: 14 * page.ui.u
                    text: page.app.connection === "OFFLINE"
                          ? "Sin conexión. Trabajas con los datos guardados en el equipo; los cambios quedan pendientes de sincronizar."
                          : page.app.connection === "AUTH_REQUIRED"
                            ? "La sesión expiró. Vuelve a iniciar sesión para sincronizar."
                            : page.app.bootError
                }
            }

            // ================================================== Propias
            Column {
                width: parent.width
                visible: page.tab === "own"
                spacing: 12 * page.ui.u

                Flow {
                    width: parent.width
                    spacing: 8 * page.ui.u
                    Repeater {
                        model: [["", "Todas"], ["BORRADOR", "Borrador"], ["OBSERVADO", "Observadas"],
                                ["EN_REVISION", "En revisión"], ["APROBADO", "Aprobadas"]]
                        delegate: RChip {
                            required property var modelData
                            ui: page.ui
                            label: modelData[1]
                            selected: page.statusFilter === modelData[0]
                            onActivated: page.statusFilter = modelData[0]
                        }
                    }
                }
                RSelect {
                    width: parent.width
                    ui: page.ui
                    options: page.projectOptions
                    value: page.projectFilter
                    placeholder: "Todos los proyectos"
                    onPicked: function(v) { page.projectFilter = v }
                }
                Row {
                    width: parent.width
                    spacing: 10 * page.ui.u
                    RButton {
                        ui: page.ui
                        width: (parent.width - 10 * page.ui.u) * 0.58
                        primary: true
                        glyph: 0xE13D
                        label: "Nueva rendición"
                        enabledButton: page.ctl && page.ctl.ready
                        onActivated: page.app.openCreate()
                    }
                    RButton {
                        ui: page.ui
                        width: (parent.width - 10 * page.ui.u) * 0.42
                        glyph: 0xE145
                        label: "Actualizar"
                        busy: page.app.busy("refresh") || page.app.busy("bootstrap")
                        onActivated: page.app.refresh()
                    }
                }

                Text {
                    width: parent.width
                    visible: !page.ctl || !page.ctl.ready || (page.own.length === 0 && page.app.phase === "PULLING")
                    text: "Cargando tus rendiciones…"
                    color: S.muted
                    font.family: page.ui.fontFamily; font.pixelSize: 15 * page.ui.u
                }
                Text {
                    width: parent.width
                    visible: page.ctl && page.ctl.ready && page.own.length === 0 && page.app.phase !== "PULLING"
                    wrapMode: Text.WordWrap
                    text: page.query.length || page.statusFilter.length || page.projectFilter.length
                          ? "Ninguna rendición coincide con la búsqueda o los filtros."
                          : "Aún no tienes rendiciones. Crea la primera con «Nueva rendición»."
                    color: S.muted
                    font.family: page.ui.fontFamily; font.pixelSize: 15 * page.ui.u
                }

                Repeater {
                    model: page.own
                    delegate: RCard {
                        required property var modelData
                        width: column.width
                        ui: page.ui
                        clickable: true
                        onActivated: page.app.openDetail(String(modelData.localId))
                        Row {
                            width: parent.width
                            spacing: 8 * page.ui.u
                            Text {
                                width: parent.width - statusBadge.width - 8 * page.ui.u
                                text: S.text_(modelData, "visibleCode", "visible_code") || "Borrador sin código"
                                color: S.text
                                font.family: page.ui.fontFamily; font.pixelSize: 17 * page.ui.u; font.weight: Font.DemiBold
                                elide: Text.ElideRight
                            }
                            RBadge {
                                id: statusBadge
                                ui: page.ui
                                label: page.ctl.statusLabel(String(modelData.status || "BORRADOR"))
                                tone: S.statusColor(modelData.status)
                            }
                        }
                        Text {
                            width: parent.width
                            text: "Período " + S.period(modelData.periodStart, modelData.periodEnd)
                            color: S.muted
                            font.family: page.ui.fontFamily; font.pixelSize: 14 * page.ui.u
                        }
                        Text {
                            width: parent.width
                            text: page.ctl.projectLabel(String(modelData.primaryProjectId || ""))
                            color: S.muted
                            elide: Text.ElideRight
                            font.family: page.ui.fontFamily; font.pixelSize: 14 * page.ui.u
                        }
                        Text {
                            width: parent.width
                            text: page.ctl.formatMoney(modelData.totalPen === undefined ? 0 : modelData.totalPen, "PEN")
                                  + "   ·   " + page.ctl.formatMoney(modelData.totalUsd === undefined ? 0 : modelData.totalUsd, "USD")
                                  + "   ·   " + Number(modelData.expenseCount || 0) + " gastos"
                            color: S.text
                            font.family: page.ui.fontFamily; font.pixelSize: 15 * page.ui.u
                        }
                        RBadge {
                            ui: page.ui
                            label: page.ctl.syncLabel(String(modelData.syncState || ""))
                                   + (Number(modelData.pendingCount || 0) > 0 ? " · " + modelData.pendingCount : "")
                            tone: S.syncColor(modelData.syncState)
                        }
                    }
                }
            }

            // ================================================== Recibidas
            Column {
                width: parent.width
                visible: page.tab === "received"
                spacing: 12 * page.ui.u

                RButton {
                    ui: page.ui
                    width: parent.width
                    glyph: 0xE145
                    label: "Actualizar bandeja"
                    busy: page.receivedLoading
                    onActivated: page.loadReceived()
                }
                Text {
                    width: parent.width
                    visible: page.receivedLoading
                    text: "Consultando rendiciones recibidas…"
                    color: S.muted
                    font.family: page.ui.fontFamily; font.pixelSize: 15 * page.ui.u
                }
                Text {
                    width: parent.width
                    visible: page.receivedError.length > 0
                    text: page.receivedError
                    wrapMode: Text.WordWrap
                    color: S.danger
                    font.family: page.ui.fontFamily; font.pixelSize: 15 * page.ui.u
                }
                Text {
                    width: parent.width
                    visible: page.receivedLoaded && !page.receivedLoading && !page.receivedError.length && page.receivedVisible.length === 0
                    text: "No hay rendiciones recibidas para revisar."
                    color: S.muted
                    font.family: page.ui.fontFamily; font.pixelSize: 15 * page.ui.u
                }
                Repeater {
                    model: page.receivedVisible
                    delegate: RCard {
                        required property var modelData
                        width: column.width
                        ui: page.ui
                        clickable: true
                        onActivated: page.app.openReceived(modelData)
                        Row {
                            width: parent.width
                            spacing: 8 * page.ui.u
                            Text {
                                width: parent.width - receptionBadge.width - 8 * page.ui.u
                                text: (S.text_(modelData, "visible_code") || "Rendición") + " · v" + (modelData.version_number || "?")
                                color: S.text
                                font.family: page.ui.fontFamily; font.pixelSize: 17 * page.ui.u; font.weight: Font.DemiBold
                                elide: Text.ElideRight
                            }
                            RBadge {
                                id: receptionBadge
                                ui: page.ui
                                label: S.text_(modelData, "received_at").length ? "Recibida" : "Por recibir"
                                tone: S.text_(modelData, "received_at").length ? S.success : S.warning
                            }
                        }
                        Text { width: parent.width; text: S.text_(modelData, "owner_name"); color: S.muted; elide: Text.ElideRight; font.family: page.ui.fontFamily; font.pixelSize: 14 * page.ui.u }
                        Text {
                            width: parent.width
                            text: [S.text_(modelData, "primary_project_code"), S.text_(modelData, "primary_project_name")].filter(function(s) { return s.length }).join(" · ")
                            color: S.muted; elide: Text.ElideRight
                            font.family: page.ui.fontFamily; font.pixelSize: 14 * page.ui.u
                        }
                        Text {
                            width: parent.width
                            text: "Período " + S.period(modelData.period_start, modelData.period_end) + " · " + page.ctl.statusLabel(S.text_(modelData, "status"))
                            color: S.muted
                            font.family: page.ui.fontFamily; font.pixelSize: 14 * page.ui.u
                        }
                        Text {
                            width: parent.width
                            text: page.ctl.formatMoney(modelData.total_declared_pen, "PEN") + "   ·   " + page.ctl.formatMoney(modelData.total_declared_usd, "USD")
                            color: S.text
                            font.family: page.ui.fontFamily; font.pixelSize: 15 * page.ui.u
                        }
                    }
                }
            }
        }
    }
}

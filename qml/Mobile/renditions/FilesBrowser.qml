import QtQuick
import QtQuick.Controls
import "RStyle.js" as S

// Archivero (sólo lectura) y Papelera global de Files v07 (Web PR #5/#6).
// Navegación jerárquica AUTORIZADA (el servidor filtra por ACL), apertura de
// binarios con acceso efímero revalidado y recuperación REVERSIBLE con vista
// previa + token + request_id idempotente. No existe purga ni borrado desde el
// móvil: TRASH, ARCHIVE y PURGE son estados distintos y aquí sólo se consulta
// y se recupera lo que el servidor permite.
Item {
    id: page
    objectName: "filesBrowser"
    property var app
    property string mode: "archive"                       // archive | trash
    property bool compact: false                          // popup 3D Touch del Dock (filas finas)
    property string expandedId: ""                        // fila desplegada con sus acciones
    // Nombre visible de los documentos inteligentes (.rend → nombre de la rendición),
    // recibido en ambos listados; el contexto resuelve listados anteriores del Archivero.
    property var displayNames: ({})
    function displayName(item) {
        if (item.kind === "SMART_DOCUMENT" && String(item.display_name || "").length)
            return String(item.display_name)
        var id = String(item.id)
        if (displayNames[id] !== undefined) return displayNames[id]
        if (item.kind !== "SMART_DOCUMENT") return String(item.name || "Sin nombre")
        if (archive) {
            displayNames[id] = "Rendición…"
            var life = page.life
            app.call("filesArchivedContext", { nodeId: item.id }, "filesName:" + id, function(ok, result) {
                if (!life.alive) return
                var c = ok ? ((result.rows || [])[0] || {}) : {}
                var copy = Object.assign({}, page.displayNames)
                copy[id] = String(c.display_name || c.name || "").length
                         ? String(c.display_name || c.name) : "Rendición archivada"
                page.displayNames = copy
            })
            return displayNames[id]
        }
        return String(item.name || "Sin nombre").replace(/\.rend$/i, "")
    }
    // Alto del popup: lo que ocupa la lista; la recuperación usa todo el espacio.
    readonly property real compactHeight: recovering ? 440 * ui.u : column.height + 8 * ui.u
    readonly property var ui: app.ui
    readonly property var ctl: app.ctl
    readonly property var life: ({ alive: true })
    readonly property bool archive: mode === "archive"
    readonly property string title: archive ? "Archivero" : "Papelera"
    // Papelera: sin botón "Sincronizado" en el encabezado (el estado lo indica el aura).
    readonly property bool hideSync: mode === "trash"
    readonly property string verb: archive ? "Reactivar" : "Restaurar"
    Component.onDestruction: life.alive = false

    property string contractState: "CHECKING"            // CHECKING | READY | UNAVAILABLE
    property var items: []
    property bool hasMore: false
    property string nextId: ""
    property var breadcrumb: []
    property string parentId: ""
    property bool loading: false
    property string loadError: ""

    // ---- Recuperación (vista previa -> confirmación)
    property var recovering: null
    property var plan: null
    property string planError: ""
    property string requestId: ""
    property var destination: null                       // { spaceId, nodeId, label }
    property bool choosingDestination: false
    property string destSpace: ""
    property var destPath: []
    property var destFolders: []

    readonly property var kindLabels: ({ FOLDER: "Carpeta", BINARY_DOCUMENT: "Documento", SMART_DOCUMENT: "Documento de InGe+", SPACE: "Espacio" })

    function isNotDeployed(code) { return code === "PGRST202" || code === "42883" }
    // Las listas que llegan del bridge son secuencias tipo arreglo (no Array de JS).
    function toArray(value) {
        if (value === undefined || value === null || typeof value.length !== "number") return null
        var out = []
        for (var i = 0; i < value.length; ++i) out.push(value[i])
        return out
    }
    function checkContract() {
        contractState = "CHECKING"
        var life = page.life
        app.call("filesContract", {}, "filesContract:" + mode, function(ok, result, code, message) {
            if (!life.alive) return
            if (!ok) {
                if (page.isNotDeployed(code)) { page.contractState = "UNAVAILABLE"; return }
                page.contractState = "READY"                 // se reintenta al consultar la lista
                page.loadError = page.app.errorText(code, message)
                return
            }
            var c = (result.rows || [])[0] || {}
            page.contractState = c.version === 7 && c.archive === true && c.restore === true ? "READY" : "UNAVAILABLE"
            if (page.contractState === "READY") page.load("", false)
        })
    }
    function load(parent, append) {
        if (loading) return
        loading = true
        loadError = ""
        var life = page.life
        app.call(archive ? "filesArchive" : "filesTrash", { parentId: parent, afterId: append ? nextId : "" },
                 "filesPage:" + mode, function(ok, result, code, message) {
            if (!life.alive) return
            page.loading = false
            if (!ok) {
                page.loadError = String(code).indexOf("FORBIDDEN") >= 0 || String(code) === "42501"
                        ? "Tu cuenta no tiene acceso a " + (page.archive ? "el Archivero." : "la Papelera global.")
                        : page.app.errorText(code, message)
                return
            }
            var p = (result.rows || [])[0] || {}
            var rows = page.toArray(p.items)
            if (rows === null) { page.loadError = "El servidor devolvió una lista no válida."; return }
            page.parentId = parent
            page.items = append ? page.items.concat(rows) : rows
            page.hasMore = p.has_more === true
            page.nextId = String(p.next_id || "")
            page.breadcrumb = page.toArray(p.breadcrumb) || []
        })
    }
    function refresh() { load(parentId, false) }
    function up() {
        if (!parentId.length) return
        var parent = breadcrumb.length >= 2 ? String(breadcrumb[breadcrumb.length - 2].id) : ""
        load(parent, false)
    }
    function openItem(item) {
        if (item.can_browse === true) { load(String(item.id), false); return }
        if (item.kind === "BINARY_DOCUMENT") {
            app.openAuthorized("filesOpenBinary", { spaceId: item.space_id, nodeId: item.id }, "filesOpen:" + item.id)
            return
        }
        if (item.kind === "SMART_DOCUMENT" && archive) {
            var life = page.life
            app.call("filesArchivedContext", { nodeId: item.id }, "filesContext:" + item.id, function(ok, result, code, message) {
                if (!life.alive) return
                if (!ok) { page.app.toast(page.app.errorText(code, message), "error"); return }
                var c = (result.rows || [])[0] || {}
                page.app.toast((c.target_type === "RENDITION" ? "Rendición archivada" : c.target_type === "CALICATA" ? "Calicata archivada" : "Documento archivado")
                               + " «" + String(c.name || item.name) + "» · solo lectura. Reactívala para editarla.", "info")
            })
        }
    }
    function canRecover(item) {
        return item.started !== true && (archive ? item.can_reactivate === true : item.can_restore === true)
    }
    function statusText(item) {
        if (item.started === true) return "Eliminación iniciada: sólo puede continuarse desde la Web."
        if (archive) return item.can_reactivate === true ? "En Archivero · puede reactivarse" : "En Archivero · solo lectura"
        return item.can_restore === true ? "En Papelera · restaurable"
                                         : "En Papelera · restaura primero su ubicación o revisa tus permisos"
    }

    // ------------------------------------------------- Recuperación reversible
    function startRecovery(item) {
        recovering = item
        plan = null
        planError = ""
        destination = null
        choosingDestination = false
        requestId = ctl.newId()                  // idempotente para ESTE elemento
        preview()
    }
    function closeRecovery() { recovering = null; plan = null; choosingDestination = false }
    function recoveryArgs() {
        var a = { entityId: String(recovering.id), expectedVersion: Number(recovering.node_version) }
        if (destination) { a.destinationSpaceId = destination.spaceId; a.destinationNodeId = destination.nodeId }
        return a
    }
    function preview() {
        if (!recovering) return
        planError = ""
        var life = page.life
        var target = recovering
        app.call("filesPreviewRecovery", recoveryArgs(), "filesPreview", function(ok, result, code, message) {
            if (!life.alive || page.recovering !== target) return
            if (!ok) { page.planError = page.app.errorText(code, message); return }
            var p = (result.rows || [])[0] || {}
            if (!p.entity || p.entity.id !== target.id || Number(p.entity.version) !== Number(target.node_version)) {
                page.planError = "La vista previa no corresponde a este elemento. Actualiza la lista."
                return
            }
            page.plan = p
            if (p.requires_destination === true) page.choosingDestination = true
        })
    }
    function recover() {
        if (!recovering || !plan || plan.requires_destination === true || !String(plan.token || "").length) return
        var args = recoveryArgs()
        args.requestId = requestId
        args.previewToken = plan.token
        var life = page.life
        var target = recovering
        app.call("filesRecover", args, "filesRecover", function(ok, result, code, message) {
            if (!life.alive) return
            if (!ok) { page.planError = page.app.errorText(code, message); return }
            var r = (result.rows || [])[0] || {}
            if (r.success !== true || r.id !== target.id) { page.planError = "El servidor no confirmó la recuperación."; return }
            page.items = page.items.filter(function(i) { return i.id !== target.id })
            page.closeRecovery()
        })
    }
    // Destino alternativo (origen movido o inexistente): proyecto -> espacio -> carpeta,
    // validado por el servidor (can_select_files_recovery_destination_v07).
    function chooseProject(projectId) {
        var life = page.life
        app.call("projectWorkspace", { projectId: projectId }, "workspace", function(ok, result, code, message) {
            if (!life.alive) return
            if (!ok) { page.planError = page.app.errorText(code, message); return }
            page.destSpace = S.text_(result, "spaceId", "space_id")
            page.destPath = []
            page.loadDestFolders("", null)
        })
    }
    function loadDestFolders(parentId, entered) {
        var life = page.life
        app.call("listFolders", { spaceId: destSpace, parentId: parentId }, "folders", function(ok, result, code, message) {
            if (!life.alive) return
            if (!ok) { page.planError = page.app.errorText(code, message); return }
            page.destFolders = result.folders || []
            if (entered) { var p = page.destPath.slice(); p.push(entered); page.destPath = p }
        })
    }
    function useDestination() {
        var nodeId = destPath.length ? String(destPath[destPath.length - 1].id) : ""
        var label = destPath.map(function(r) { return S.text_(r, "name") }).join(" / ") || "Raíz del proyecto"
        var life = page.life
        app.call("filesCanChoose", { entityId: String(recovering.id), spaceId: destSpace, nodeId: nodeId }, "filesCanChoose",
                 function(ok, result, code, message) {
            if (!life.alive) return
            if (!ok) { page.planError = page.app.errorText(code, message); return }
            var allowed = (result.rows || [])[0]
            if (allowed !== true) { page.planError = "No tienes permiso para recuperar en esa ubicación. Elige otra."; return }
            page.destination = { spaceId: page.destSpace, nodeId: nodeId, label: label }
            page.choosingDestination = false
            page.preview()
        })
    }

    function handleBack() {
        if (recovering) { closeRecovery(); return true }
        if (parentId.length) { up(); return true }
        return false
    }
    Component.onCompleted: checkContract()

    Flickable {
        anchors.fill: parent
        contentWidth: width
        contentHeight: column.height + 160 * page.ui.u
        boundsBehavior: Flickable.StopAtBounds
        clip: true
        Column {
            id: column
            x: page.compact ? 0 : page.ui.gutter
            y: page.compact ? 0 : 8 * page.ui.u
            width: parent.width - 2 * x
            spacing: (page.compact ? 2 : 12) * page.ui.u

            Item {                                            // encabezado del popup
                visible: page.compact
                width: parent.width; height: 34 * page.ui.u
                Text { x: 10 * page.ui.u; anchors.verticalCenter: parent.verticalCenter; text: page.title; color: S.text
                       font.family: page.ui.fontFamily; font.pixelSize: 15 * page.ui.u; font.weight: Font.ExtraBold }
                Text { anchors.right: parent.right; anchors.rightMargin: 10 * page.ui.u; anchors.verticalCenter: parent.verticalCenter
                       text: page.items.length + (page.hasMore ? "+" : "") + " elementos"; color: S.muted
                       font.family: page.ui.fontFamily; font.pixelSize: 12.5 * page.ui.u }
            }
            Text {
                visible: !page.compact
                width: parent.width
                text: page.archive ? "Elementos archivados para consulta y descarga. Para editarlos, primero reactívalos."
                                   : "Elementos retirados de todas las ubicaciones autorizadas. Cada uno conserva su origen y sus permisos."
                color: S.muted; wrapMode: Text.WordWrap
                font.family: page.ui.fontFamily; font.pixelSize: 14 * page.ui.u
            }
            Text {
                width: parent.width
                visible: page.breadcrumb.length > 0
                text: page.breadcrumb.map(function(b) { return String(b.name) }).join(" / ")
                color: S.corporateBlue; elide: Text.ElideLeft
                font.family: page.ui.fontFamily; font.pixelSize: 14 * page.ui.u
            }
            RButton {
                ui: page.ui; glyph: 0xE06E; label: "Subir un nivel"
                visible: page.parentId.length > 0
                onActivated: page.up()
            }
            Text {
                width: parent.width
                visible: page.contractState === "UNAVAILABLE"
                text: (page.archive ? "El Archivero" : "La Papelera global") + " aún no está disponible en este entorno."
                color: S.muted; wrapMode: Text.WordWrap
                font.family: page.ui.fontFamily; font.pixelSize: 15 * page.ui.u
            }
            Text {
                width: parent.width
                visible: page.contractState === "CHECKING" || (page.loading && page.items.length === 0)
                leftPadding: page.compact ? 10 * page.ui.u : 0
                text: "Consultando…"
                color: S.muted
                font.family: page.ui.fontFamily; font.pixelSize: 15 * page.ui.u
            }
            Text {
                width: parent.width
                visible: page.loadError.length > 0
                text: page.loadError
                color: S.danger; wrapMode: Text.WordWrap
                font.family: page.ui.fontFamily; font.pixelSize: 14 * page.ui.u
            }
            Text {
                width: parent.width
                visible: page.contractState === "READY" && !page.loading && page.loadError.length === 0 && page.items.length === 0
                leftPadding: page.compact ? 10 * page.ui.u : 0
                text: page.compact ? "Vacío" : page.archive ? "No hay elementos archivados en esta ubicación." : "La Papelera está vacía en esta ubicación."
                color: S.muted; wrapMode: Text.WordWrap
                font.family: page.ui.fontFamily; font.pixelSize: 15 * page.ui.u
            }
            // Filas finas del popup: tocar despliega «Reactivar/Restaurar» y «Ver».
            Repeater {
                model: page.compact ? page.items : []
                delegate: Rectangle {
                    id: row
                    required property var modelData
                    readonly property bool open: page.expandedId === String(modelData.id)
                    width: column.width
                    height: rowBody.implicitHeight
                    radius: 14 * page.ui.u
                    color: open ? Qt.rgba(6 / 255, 84 / 255, 162 / 255, 0.06) : (rowTap.pressed ? S.ink(0.05) : "transparent")
                    Behavior on height { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
                    Column {
                        id: rowBody
                        width: parent.width
                        Item {
                            width: parent.width; height: 56 * page.ui.u
                            Rectangle {                       // icono del tipo (sin códigos DOC/DIR)
                                id: kindTile
                                x: 8 * page.ui.u; anchors.verticalCenter: parent.verticalCenter
                                width: 38 * page.ui.u; height: width; radius: 11 * page.ui.u
                                readonly property color tone: page.archive ? "#D08A12" : "#D64550"
                                color: Qt.rgba(tone.r, tone.g, tone.b, 0.12)
                                Text { anchors.centerIn: parent; color: kindTile.tone; font.family: page.ui.iconFamily; font.pixelSize: 18 * page.ui.u
                                       text: String.fromCharCode(({ FOLDER: 0xE0D7, SMART_DOCUMENT: 0xE3D3 })[row.modelData.kind] || 0xE0C0) }
                            }
                            Column {
                                x: kindTile.x + kindTile.width + 12 * page.ui.u; width: parent.width - x - (restoreQuick.visible ? 54 : 12) * page.ui.u
                                anchors.verticalCenter: parent.verticalCenter; spacing: 1 * page.ui.u
                                Text { width: parent.width; text: page.displayName(row.modelData); elide: Text.ElideRight; color: S.text
                                       font.family: page.ui.fontFamily; font.pixelSize: 14.5 * page.ui.u; font.weight: row.open ? Font.Bold : Font.DemiBold }
                                Text { width: parent.width; elide: Text.ElideRight; color: S.muted
                                       text: ({ FOLDER: "Carpeta", SMART_DOCUMENT: "Rendición", BINARY_DOCUMENT: "Archivo" })[row.modelData.kind] || "Elemento"
                                       font.family: page.ui.fontFamily; font.pixelSize: 12 * page.ui.u }
                            }
                            MouseArea { id: rowTap; anchors.fill: parent
                                        onClicked: page.expandedId = row.open ? "" : String(row.modelData.id) }
                            RButton {                         // Papelera: restaurar directo (botón circular)
                                id: restoreQuick
                                visible: !page.archive && page.canRecover(row.modelData)
                                anchors.right: parent.right; anchors.rightMargin: 6 * page.ui.u; anchors.verticalCenter: parent.verticalCenter
                                width: 40 * page.ui.u; height: width; radius: width / 2
                                ui: page.ui; glyph: 0xE148; color: Qt.rgba(31 / 255, 111 / 255, 214 / 255, 0.12)
                                Accessible.name: "Restaurar " + String(row.modelData.name || "")
                                onActivated: page.startRecovery(row.modelData)
                            }
                            Text { visible: !page.archive && !page.canRecover(row.modelData)
                                   anchors.right: parent.right; anchors.rightMargin: 12 * page.ui.u; anchors.verticalCenter: parent.verticalCenter
                                   text: "Sin destino"; color: S.muted; font.family: page.ui.fontFamily; font.pixelSize: 11.5 * page.ui.u }
                        }
                        Row {
                            visible: row.open
                            x: 8 * page.ui.u; width: parent.width - 16 * page.ui.u; height: visible ? 48 * page.ui.u : 0
                            spacing: 6 * page.ui.u
                            RButton { width: (parent.width - parent.spacing) / 2; height: 40 * page.ui.u; radius: 11 * page.ui.u
                                      ui: page.ui; primary: true; label: page.verb
                                      enabledButton: page.canRecover(row.modelData)
                                      onActivated: page.startRecovery(row.modelData) }
                            RButton { width: (parent.width - parent.spacing) / 2; height: 40 * page.ui.u; radius: 11 * page.ui.u
                                      ui: page.ui; label: row.modelData.can_browse === true ? "Abrir" : "Ver"; color: S.glass(1)
                                      enabledButton: row.modelData.can_browse === true || row.modelData.kind === "BINARY_DOCUMENT"
                                      busy: page.app.busy("filesOpen:" + row.modelData.id)
                                      onActivated: page.openItem(row.modelData) }
                        }
                    }
                }
            }
            Repeater {
                model: page.compact ? [] : page.items
                delegate: RCard {
                    required property var modelData
                    width: column.width
                    ui: page.ui
                    clickable: modelData.can_browse === true || modelData.kind === "BINARY_DOCUMENT" || (modelData.kind === "SMART_DOCUMENT" && page.archive)
                    onActivated: page.openItem(modelData)
                    Text {
                        width: parent.width
                        text: String(modelData.name || "Sin nombre")
                        color: S.text; elide: Text.ElideRight
                        font.family: page.ui.fontFamily; font.pixelSize: 16 * page.ui.u; font.weight: Font.DemiBold
                    }
                    Text {
                        width: parent.width
                        text: (page.kindLabels[modelData.kind] || "Elemento") + " · " + String(modelData.origin || modelData.space_name || "")
                        color: S.muted; elide: Text.ElideRight
                        font.family: page.ui.fontFamily; font.pixelSize: 13 * page.ui.u
                    }
                    Text {
                        width: parent.width
                        text: page.statusText(modelData)
                        color: modelData.started === true ? S.warning : S.muted
                        wrapMode: Text.WordWrap
                        font.family: page.ui.fontFamily; font.pixelSize: 13 * page.ui.u
                    }
                    Flow {
                        width: parent.width
                        spacing: 8 * page.ui.u
                        RButton {
                            ui: page.ui; label: modelData.can_browse === true ? "Abrir" : "Ver"
                            visible: modelData.can_browse === true || modelData.kind === "BINARY_DOCUMENT"
                            busy: page.app.busy("filesOpen:" + modelData.id)
                            onActivated: page.openItem(modelData)
                        }
                        RButton {
                            ui: page.ui; primary: true; label: page.verb
                            visible: page.canRecover(modelData)
                            onActivated: page.startRecovery(modelData)
                        }
                    }
                }
            }
            RButton {
                width: parent.width
                ui: page.ui; label: "Cargar más"
                visible: page.hasMore
                busy: page.loading
                onActivated: page.load(page.parentId, true)
            }
        }
    }

    // ------------------------------------------------ Hoja de recuperación
    // Tarjeta de vidrio centrada (mismo lenguaje que RConfirm): icono, nombre
    // visible, ruta corta de destino y dos botones anchos.
    function shortPath(label) {
        var parts = String(label || "").split("/").map(function(x) { return x.trim() }).filter(function(x) { return x.length })
        return parts.slice(-2).join(" › ")
    }
    Item {
        id: sheet
        objectName: "recoverySheet"
        anchors.fill: parent
        visible: opacity > 0.01
        opacity: page.recovering !== null ? 1 : 0
        z: 20
        Behavior on opacity { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
        Rectangle { anchors.fill: parent; radius: 24 * page.ui.u; color: Qt.rgba(14 / 255, 24 / 255, 44 / 255, 0.22) }
        MouseArea { anchors.fill: parent; onClicked: page.closeRecovery() }
        Rectangle {
            width: parent.width - 20 * page.ui.u
            x: 10 * page.ui.u
            height: Math.min(parent.height - 20 * page.ui.u, sheetColumn.implicitHeight + 44 * page.ui.u)
            y: (parent.height - height) / 2
            radius: 26 * page.ui.u
            color: S.dark ? Qt.rgba(18 / 255, 22 / 255, 32 / 255, 0.97) : S.glass(0.94)
            border.width: 1
            border.color: S.edge(1)
            scale: page.recovering !== null ? 1 : 0.92
            Behavior on scale { NumberAnimation { duration: 340; easing.type: Easing.OutBack; easing.overshoot: 1.15 } }
            Rectangle {                                   // brillo superior del vidrio
                anchors.fill: parent; anchors.margins: 1; radius: parent.radius - 1
                gradient: Gradient {
                    GradientStop { position: 0.0; color: S.glass(0.6) }
                    GradientStop { position: 0.3; color: S.glass(0.0) }
                }
            }
            MouseArea { anchors.fill: parent }
            Flickable {
                anchors.fill: parent
                anchors.margins: 22 * page.ui.u
                contentHeight: sheetColumn.implicitHeight
                boundsBehavior: Flickable.StopAtBounds
                clip: true
                Column {
                    id: sheetColumn
                    width: parent.width
                    spacing: 8 * page.ui.u
                    Rectangle {
                        anchors.horizontalCenter: parent.horizontalCenter
                        width: 52 * page.ui.u; height: width; radius: width / 2
                        color: Qt.rgba(31 / 255, 111 / 255, 214 / 255, 0.12)
                        Text { anchors.centerIn: parent; text: String.fromCharCode(0xE148); color: "#1F6FD6"
                               font.family: page.ui.iconFamily; font.pixelSize: 24 * page.ui.u }
                    }
                    Text {
                        width: parent.width; horizontalAlignment: Text.AlignHCenter; wrapMode: Text.WordWrap
                        text: "¿" + page.verb + "?"
                        color: S.text; font.family: page.ui.fontFamily; font.pixelSize: 19 * page.ui.u; font.weight: Font.Bold
                    }
                    Text {
                        width: parent.width; horizontalAlignment: Text.AlignHCenter; wrapMode: Text.WordWrap
                        maximumLineCount: 2; elide: Text.ElideRight
                        text: page.recovering ? page.displayName(page.recovering) : ""
                        color: S.text; font.family: page.ui.fontFamily; font.pixelSize: 15.5 * page.ui.u; font.weight: Font.DemiBold
                    }
                    Text {
                        width: parent.width; horizontalAlignment: Text.AlignHCenter; wrapMode: Text.WordWrap
                        text: "Conserva sus datos y permisos."
                        color: S.muted; font.family: page.ui.fontFamily; font.pixelSize: 13 * page.ui.u
                    }
                    Item { width: 1; height: 2 * page.ui.u }
                    Rectangle {                               // a dónde vuelve (ruta corta)
                        width: parent.width; height: 52 * page.ui.u; radius: 14 * page.ui.u
                        color: Qt.rgba(21 / 255, 26 / 255, 48 / 255, 0.05)
                        Text { id: destIcon; x: 12 * page.ui.u; anchors.verticalCenter: parent.verticalCenter; text: String.fromCharCode(0xE0D7)
                               color: "#1F6FD6"; font.family: page.ui.iconFamily; font.pixelSize: 18 * page.ui.u }
                        Column {
                            x: destIcon.x + destIcon.width + 10 * page.ui.u; width: parent.width - x - 12 * page.ui.u
                            anchors.verticalCenter: parent.verticalCenter; spacing: 1 * page.ui.u
                            Text { text: "Vuelve a"; color: S.muted; font.family: page.ui.fontFamily; font.pixelSize: 11.5 * page.ui.u }
                            Text {
                                width: parent.width; elide: Text.ElideLeft; color: S.text
                                font.family: page.ui.fontFamily; font.pixelSize: 14 * page.ui.u; font.weight: Font.DemiBold
                                text: !page.plan ? (page.planError.length ? "—" : "Comprobando…")
                                      : (page.shortPath((page.plan.destination || page.plan.origin || {}).label) || "Elige un destino")
                                SequentialAnimation on opacity {
                                    running: !page.plan && !page.planError.length && sheet.visible; loops: Animation.Infinite
                                    NumberAnimation { to: 0.4; duration: 600 }
                                    NumberAnimation { to: 1; duration: 600 }
                                }
                            }
                        }
                    }
                    Text {
                        width: parent.width
                        visible: !!page.plan && (page.plan.origin || {}).state !== "AVAILABLE"
                        text: page.plan && (page.plan.origin || {}).state === "UNKNOWN"
                              ? "No se puede confirmar la ubicación original. Elige dónde se guardará."
                              : "Su ubicación original ya no existe. Elige dónde se guardará."
                        color: S.warning; wrapMode: Text.WordWrap; horizontalAlignment: Text.AlignHCenter
                        font.family: page.ui.fontFamily; font.pixelSize: 13 * page.ui.u
                    }
                    Text {
                        width: parent.width; horizontalAlignment: Text.AlignHCenter
                        visible: !!page.plan && (page.plan.nodes || []).length > 1
                        text: page.plan ? (page.plan.nodes || []).length + " elementos incluidos" : ""
                        color: S.muted; font.family: page.ui.fontFamily; font.pixelSize: 13 * page.ui.u
                    }
                    // Destino alternativo
                    Column {
                        width: parent.width
                        spacing: 8 * page.ui.u
                        visible: page.choosingDestination
                        Text {
                            width: parent.width
                            text: !page.destSpace.length ? "Elige el proyecto de destino:" : "Carpeta: " + (page.destPath.map(function(r) { return S.text_(r, "name") }).join(" / ") || "Raíz del proyecto")
                            color: S.text; wrapMode: Text.WordWrap
                            font.family: page.ui.fontFamily; font.pixelSize: 14 * page.ui.u
                        }
                        Repeater {
                            model: page.destSpace.length ? [] : (page.app.st.projects || [])
                            delegate: RMenuItem {
                                required property var modelData
                                width: parent.width
                                ui: page.ui
                                label: [S.text_(modelData, "code", "project_code"), S.text_(modelData, "name", "project_name")].filter(function(s) { return s.length }).join(" · ")
                                onActivated: page.chooseProject(S.text_(modelData, "id", "project_id"))
                            }
                        }
                        Repeater {
                            model: page.destSpace.length ? page.destFolders : []
                            delegate: RMenuItem {
                                required property var modelData
                                width: parent.width
                                ui: page.ui
                                label: S.text_(modelData, "name")
                                onActivated: page.loadDestFolders(S.text_(modelData, "id"), modelData)
                            }
                        }
                        RButton {
                            ui: page.ui; primary: true; label: "Usar esta ubicación"
                            visible: page.destSpace.length > 0
                            onActivated: page.useDestination()
                        }
                    }
                    Text {
                        width: parent.width
                        visible: page.planError.length > 0
                        text: page.planError
                        color: S.danger; wrapMode: Text.WordWrap
                        font.family: page.ui.fontFamily; font.pixelSize: 14 * page.ui.u
                    }
                    Item { width: 1; height: 6 * page.ui.u }
                    Row {
                        id: sheetActions
                        width: parent.width
                        spacing: 10 * page.ui.u
                        RButton { ui: page.ui; label: "Cancelar"; width: (sheetActions.width - sheetActions.spacing) / 2; height: 48 * page.ui.u
                                  radius: height / 2; color: Qt.rgba(21 / 255, 26 / 255, 48 / 255, 0.07)
                                  onActivated: page.closeRecovery() }
                        RButton {
                            objectName: "recoverButton"
                            width: (sheetActions.width - sheetActions.spacing) / 2; height: 48 * page.ui.u; radius: height / 2
                            ui: page.ui; primary: true; label: page.verb
                            enabledButton: !!page.plan && page.plan.requires_destination !== true && String(page.plan.token || "").length > 0
                            busy: page.app.busy("filesRecover")
                            onActivated: page.recover()
                        }
                    }
                }
            }
        }
    }
}

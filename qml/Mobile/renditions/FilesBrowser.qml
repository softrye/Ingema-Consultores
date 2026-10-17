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
            page.app.toast((page.archive ? "Reactivado: " : "Restaurado: ") + target.name, "success")
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
            x: page.ui.gutter
            y: 8 * page.ui.u
            width: parent.width - 2 * page.ui.gutter
            spacing: 12 * page.ui.u

            Text {
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
                text: page.archive ? "No hay elementos archivados en esta ubicación." : "La Papelera está vacía en esta ubicación."
                color: S.muted; wrapMode: Text.WordWrap
                font.family: page.ui.fontFamily; font.pixelSize: 15 * page.ui.u
            }
            Repeater {
                model: page.items
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
    Item {
        id: sheet
        objectName: "recoverySheet"
        anchors.fill: parent
        visible: page.recovering !== null
        z: 20
        MouseArea { anchors.fill: parent; onClicked: page.closeRecovery() }
        Rectangle {
            width: parent.width - 20 * page.ui.u
            x: 10 * page.ui.u
            height: Math.min(parent.height * 0.82, sheetColumn.implicitHeight + 48 * page.ui.u)
            y: parent.height - height - page.ui.dockArea + 8 * page.ui.u
            radius: 30 * page.ui.u
            color: Qt.rgba(1, 1, 1, 0.97)
            border.width: 1
            border.color: S.border
            MouseArea { anchors.fill: parent }
            Flickable {
                anchors.fill: parent
                anchors.margins: 22 * page.ui.u
                contentHeight: sheetColumn.implicitHeight
                clip: true
                Column {
                    id: sheetColumn
                    width: parent.width
                    spacing: 10 * page.ui.u
                    Text {
                        width: parent.width
                        text: page.verb + " desde " + (page.archive ? "el Archivero" : "la Papelera")
                        color: S.text; font.family: page.ui.fontFamily; font.pixelSize: 21 * page.ui.u; font.weight: Font.DemiBold
                    }
                    Text {
                        width: parent.width
                        text: page.recovering ? String(page.recovering.name) : ""
                        color: S.text; wrapMode: Text.WordWrap
                        font.family: page.ui.fontFamily; font.pixelSize: 16 * page.ui.u
                    }
                    Text {
                        width: parent.width
                        text: "Se conservan la identidad, los datos y los permisos originales."
                        color: S.muted; wrapMode: Text.WordWrap
                        font.family: page.ui.fontFamily; font.pixelSize: 13 * page.ui.u
                    }
                    Text {
                        width: parent.width
                        visible: !page.plan && !page.planError.length
                        text: "Comprobando la ubicación y los permisos…"
                        color: S.muted; font.family: page.ui.fontFamily; font.pixelSize: 14 * page.ui.u
                    }
                    Text {
                        width: parent.width
                        visible: !!page.plan
                        text: page.plan ? "Ubicación original: " + String((page.plan.origin || {}).label || "") : ""
                        color: S.text; wrapMode: Text.WordWrap
                        font.family: page.ui.fontFamily; font.pixelSize: 14 * page.ui.u
                    }
                    Text {
                        width: parent.width
                        visible: !!page.plan && (page.plan.origin || {}).state !== "AVAILABLE"
                        text: page.plan && (page.plan.origin || {}).state === "UNKNOWN"
                              ? "No se puede confirmar la ubicación original. Elige dónde se guardará."
                              : "Su ubicación original ya no existe, fue movida o está en la Papelera. Elige dónde se guardará."
                        color: S.warning; wrapMode: Text.WordWrap
                        font.family: page.ui.fontFamily; font.pixelSize: 14 * page.ui.u
                    }
                    Text {
                        width: parent.width
                        visible: !!page.plan && !!page.plan.destination
                        text: page.plan && page.plan.destination ? "Destino: " + String(page.plan.destination.label || "") : ""
                        color: S.corporateBlue; wrapMode: Text.WordWrap
                        font.family: page.ui.fontFamily; font.pixelSize: 14 * page.ui.u
                    }
                    Text {
                        width: parent.width
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
                    Flow {
                        width: parent.width
                        spacing: 8 * page.ui.u
                        RButton { ui: page.ui; label: "Cerrar"; onActivated: page.closeRecovery() }
                        RButton {
                            objectName: "recoverButton"
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

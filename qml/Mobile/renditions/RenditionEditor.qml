import QtQuick
import QtQuick.Controls
import "RStyle.js" as S

// Crear / editar la cabecera: período, proyectos asociados y principal, y
// carpeta documental de InGe Drive (projectWorkspace -> listFolders ->
// folderCapabilities). Guarda con create/update (outbox + CAS) y conserva lo
// escrito con saveEditorDraft mientras el usuario navega.
Item {
    id: page
    readonly property bool editingInProgress: true
    property var app
    property var original: null
    property bool embedded: false              // dentro de la hoja «Nueva rendición»
    readonly property var ui: app.ui
    readonly property var ctl: app.ctl
    readonly property bool editing: original !== null && original !== undefined
    readonly property string title: editing ? "Editar rendición" : "Nueva rendición"
    readonly property string draftKey: "header:" + (editing ? String(original.localId) : "new")
    readonly property bool writable: !editing || ctl.canEdit(original)
    readonly property var life: ({ alive: true })

    property string displayName: ""
    property string start: ""
    property string end: ""
    property var projects: []
    property string primary: ""
    property string folder: ""
    property string folderName: ""
    property string space: ""
    property string error: ""
    property bool restored: false
    property bool finished: false

    // Navegación de carpetas (InGe Drive)
    property bool browsing: false
    property bool browsingBusy: false
    property string browseSpace: ""
    property var folders: []
    property var path: []

    function handleBack() {
        if (browsing) { browsing = false; return true }
        return false
    }

    Component.onCompleted: {
        var draft = (app.st.editorDrafts || {})[draftKey]
        var source = draft && draft.periodStart ? draft : null
        var b = editing ? original : {}
        displayName = source ? String(source.displayName || "") : S.text_(b, "displayName", "display_name")
        start = source ? String(source.periodStart) : String(b.periodStart || ctl.today())
        end = source ? String(source.periodEnd) : String(b.periodEnd || ctl.today())
        projects = source ? (source.projectIds || []).slice() : (b.projectIds || []).slice()
        primary = source ? String(source.primaryProjectId || "") : String(b.primaryProjectId || "")
        folder = source ? String(source.documentParentNodeId || "") : String(b.documentParentNodeId || "")
        folderName = source ? String(source.folderName || "") : String(b.documentParentNodeName || b.folderName || "")
        space = source ? String(source.spaceId || "") : String(b.spaceId || "")
        restored = source !== null
    }
    Component.onDestruction: life.alive = false

    function payload() {
        var p = {
            displayName: displayName.trim(), periodStart: start, periodEnd: end, projectIds: projects.slice(), primaryProjectId: primary,
            documentParentNodeId: folder, spaceId: space, synchronize: true
        }
        if (editing) {
            p.localId = String(original.localId)
            p.expectedRowVersion = Number(original.rowVersion || 0)
        }
        return p
    }
    function changed() {
        error = ""
        if (writable && !finished) autosave.restart()
    }
    Timer {
        id: autosave
        interval: 600
        onTriggered: {
            var draft = page.payload()
            draft.folderName = page.folderName
            if (page.editing) draft.renditionLocalId = String(page.original.localId)
            page.app.call("saveEditorDraft", { key: page.draftKey, draft: draft }, "")
        }
    }

    function toggleProject(id) {
        var list = projects.slice()
        var i = list.indexOf(id)
        if (i >= 0) {
            list.splice(i, 1)
            if (primary === id) { primary = list.length ? list[0] : ""; folder = folderName = space = "" }
        } else {
            list.push(id)
            if (!primary.length) primary = id
        }
        projects = list
        changed()
    }
    function setPrimary(id) {
        if (projects.indexOf(id) < 0 || primary === id) return
        primary = id
        folder = folderName = space = ""          // la carpeta pertenece al proyecto principal
        changed()
    }

    // ------------------------------------------------------- InGe Drive
    function openFolders() {
        if (!primary.length) { error = "Elige primero el proyecto principal."; return }
        var life = page.life
        browsingBusy = true
        app.call("projectWorkspace", { projectId: primary }, "workspace", function(ok, result, code, message) {
            if (!life.alive) return
            if (!ok) { page.browsingBusy = false; page.error = page.app.errorText(code, message); return }
            var spaceId = S.text_(result, "spaceId", "space_id")
            if (!spaceId.length) { page.browsingBusy = false; page.error = "El proyecto no tiene un espacio documental disponible."; return }
            page.browseSpace = spaceId
            page.path = []
            page.loadFolders("", null)
        })
    }
    function loadFolders(parentId, enteredRow) {
        var life = page.life
        browsingBusy = true
        app.call("listFolders", { spaceId: browseSpace, parentId: parentId }, "folders", function(ok, result, code, message) {
            if (!life.alive) return
            page.browsingBusy = false
            if (!ok) { page.error = page.app.errorText(code, message); return }
            page.folders = result.folders || []
            if (enteredRow) { var p = page.path.slice(); p.push(enteredRow); page.path = p }
            page.browsing = true
        })
    }
    function folderUp() {
        if (!path.length) return
        var parent = path.length < 2 ? "" : S.text_(path[path.length - 2], "id")
        var p = path.slice(); p.pop()
        var life = page.life
        browsingBusy = true
        app.call("listFolders", { spaceId: browseSpace, parentId: parent }, "folders", function(ok, result, code, message) {
            if (!life.alive) return
            page.browsingBusy = false
            if (!ok) { page.error = page.app.errorText(code, message); return }
            page.folders = result.folders || []
            page.path = p
        })
    }
    function chooseFolder(row) {
        var life = page.life
        var nodeId = S.text_(row, "id")
        browsingBusy = true
        app.call("folderCapabilities", { spaceId: browseSpace, nodeId: nodeId }, "folderCapabilities",
                 function(ok, result, code, message) {
            if (!life.alive) return
            page.browsingBusy = false
            if (!ok) { page.error = page.app.errorText(code, message); return }
            if (result.node_kind !== "FOLDER" || result.lifecycle !== "ACTIVE" || result.can_accept_child !== true
                    || result.space_id !== page.browseSpace || result.node_id !== nodeId) {
                page.error = "Esta carpeta no está activa o no admite documentos. Elige otra ubicación."
                return
            }
            page.folder = nodeId
            page.folderName = page.path.map(function(r) { return S.text_(r, "name") }).concat([S.text_(row, "name")]).join(" / ")
            page.space = page.browseSpace
            page.browsing = false
            page.changed()
        })
    }

    // ------------------------------------------------------------ Guardar
    function save() {
        if (!editing && (!displayName.trim().length || displayName.trim().length > 160)) {
            error = "Escribe un nombre para la rendición (máximo 160 caracteres)."
            return
        }
        var header = payload()
        var problem = ctl.headerError(header)
        if (problem.length) { error = problem; return }
        var life = page.life
        app.call(editing ? "update" : "create", header, "header:" + (editing ? original.localId : "new"),
                 function(ok, result, code, message) {
            if (!ok) { if (life.alive) page.error = page.app.errorText(code, message); return }
            var saved = result.current || {}
            if (!String(saved.localId || "").length || (page.editing && saved.localId !== page.original.localId)) {
                if (life.alive) page.error = "No se pudo confirmar la identidad guardada."
                return
            }
            page.finished = true
            autosave.stop()
            page.app.call("saveEditorDraft", { key: page.draftKey, draft: {} }, "")
            page.app.toast("Rendición guardada en el equipo · pendiente de sincronizar con el servidor.", "success")
            if (!life.alive) return
            if (page.editing) page.app.closePage()
            else page.app.openCreated(String(saved.localId))
        })
    }

    Flickable {
        anchors.fill: parent
        visible: !page.browsing
        contentWidth: width
        contentHeight: form.height + (page.embedded ? 30 : 140) * page.ui.u
        boundsBehavior: Flickable.StopAtBounds
        clip: true
        Column {
            id: form
            x: page.embedded ? 22 * page.ui.u : page.ui.gutter
            y: page.embedded ? 12 * page.ui.u : 8 * page.ui.u
            width: parent.width - 2 * x
            spacing: 14 * page.ui.u

            Text {
                width: parent.width
                visible: page.restored
                text: "Se recuperaron los datos que estabas escribiendo."
                color: S.accentSoft
                wrapMode: Text.WordWrap
                font.family: page.ui.fontFamily; font.pixelSize: 14 * page.ui.u
            }
            Text {
                width: parent.width
                visible: !page.writable
                text: "Esta rendición está en solo lectura: el servidor no concede permiso de edición."
                color: S.warning
                wrapMode: Text.WordWrap
                font.family: page.ui.fontFamily; font.pixelSize: 14 * page.ui.u
            }

            RField {
                width: parent.width
                ui: page.ui
                label: "Nombre de la rendición"
                text: page.displayName
                placeholder: "Ej.: Visita de campo — Huarmey"
                maxLength: 160
                readOnly: page.editing || !page.writable
                onEdited: { page.displayName = text; page.changed() }
            }
            Text {
                width: parent.width
                visible: page.editing
                text: "El nombre existente se administra desde el archivo .rend en InGeDrive/Web. El código se conserva como identificador."
                color: S.muted; wrapMode: Text.WordWrap
                font.family: page.ui.fontFamily; font.pixelSize: 13 * page.ui.u
            }
            Text { visible: !page.embedded; text: "Proyectos asociados"; color: S.text; font.family: page.ui.fontFamily; font.pixelSize: 17 * page.ui.u; font.weight: Font.DemiBold }
            Text {
                width: parent.width
                visible: (page.app.st.projects || []).length === 0
                text: "No hay proyectos autorizados para rendiciones en tu cuenta (o aún se están cargando)."
                color: S.muted; wrapMode: Text.WordWrap
                font.family: page.ui.fontFamily; font.pixelSize: 14 * page.ui.u
            }
            Repeater {
                model: page.app.st.projects || []
                delegate: Rectangle {
                    required property var modelData
                    readonly property string projectId: S.text_(modelData, "id", "project_id")
                    readonly property bool checked: page.projects.indexOf(projectId) >= 0
                    width: form.width
                    height: 60 * page.ui.u
                    radius: 16 * page.ui.u
                    color: checked ? Qt.rgba(6 / 255, 84 / 255, 162 / 255, 0.08) : "#FFFFFF"
                    border.width: 1; border.color: checked ? Qt.rgba(6 / 255, 84 / 255, 162 / 255, 0.35) : S.ink(0.07)
                    Text {
                        x: 22 * page.ui.u
                        width: parent.width - (parent.checked ? primaryChip.width : 0) - 64 * page.ui.u
                        anchors.verticalCenter: parent.verticalCenter
                        text: (parent.checked ? "✓  " : "") + page.ctl.projectLabel(parent.projectId)
                        color: S.text; elide: Text.ElideRight
                        font.family: page.ui.fontFamily; font.pixelSize: 17 * page.ui.u
                    }
                    Text {
                        visible: !parent.checked
                        anchors.right: parent.right; anchors.rightMargin: 18 * page.ui.u
                        anchors.verticalCenter: parent.verticalCenter
                        text: String.fromCharCode(0xE06F)
                        font.family: page.ui.iconFamily; font.pixelSize: 20 * page.ui.u
                        color: S.muted
                    }
                    MouseArea { anchors.fill: parent; enabled: page.writable; onClicked: page.toggleProject(parent.projectId) }
                    RChip {
                        id: primaryChip
                        anchors.right: parent.right; anchors.rightMargin: 10 * page.ui.u
                        anchors.verticalCenter: parent.verticalCenter
                        ui: page.ui
                        visible: parent.checked
                        label: page.primary === parent.projectId ? "Principal" : "Hacer principal"
                        selected: page.primary === parent.projectId
                        enabledChip: page.writable
                        onActivated: page.setPrimary(parent.projectId)
                    }
                }
            }

            Text { text: "Período"; color: S.text; font.family: page.ui.fontFamily; font.pixelSize: 19 * page.ui.u; font.weight: Font.DemiBold }
            Row {
                width: parent.width
                spacing: 10 * page.ui.u
                RDateField {
                    width: (parent.width - 10 * page.ui.u) / 2
                    ui: page.ui; label: "Desde"; value: page.start; readOnly: !page.writable
                    onPicked: function(v) { page.start = v; page.changed() }
                }
                RDateField {
                    width: (parent.width - 10 * page.ui.u) / 2
                    ui: page.ui; label: "Hasta"; value: page.end; minimum: page.start; readOnly: !page.writable
                    onPicked: function(v) { page.end = v; page.changed() }
                }
            }

            Text { text: "Carpeta documental"; color: S.text; font.family: page.ui.fontFamily; font.pixelSize: 19 * page.ui.u; font.weight: Font.DemiBold }
            Text {
                width: parent.width
                text: page.folder.length ? (page.folderName.length ? page.folderName : "Carpeta seleccionada") : "Sin carpeta seleccionada"
                color: page.folder.length ? S.text : S.muted
                wrapMode: Text.WordWrap
                font.family: page.ui.fontFamily; font.pixelSize: 15 * page.ui.u
            }
            RButton {
                width: parent.width
                ui: page.ui
                glyph: 0xE0D7
                label: page.folder.length ? "Cambiar carpeta" : "Elegir carpeta del proyecto principal"
                busy: page.browsingBusy
                enabledButton: page.writable && page.primary.length > 0
                onActivated: page.openFolders()
            }

            Text {
                width: parent.width
                visible: page.error.length > 0
                text: page.error
                color: S.danger; wrapMode: Text.WordWrap
                font.family: page.ui.fontFamily; font.pixelSize: 14 * page.ui.u
            }
            RButton {
                width: parent.width
                ui: page.ui
                primary: true
                glyph: 0xE14D
                label: page.editing ? "Guardar cambios" : "Crear rendición"
                busy: page.app.busy("header:" + (page.editing ? page.original.localId : "new"))
                enabledButton: page.writable
                onActivated: page.save()
            }
            Text {
                width: parent.width
                text: "Se guarda primero en el equipo y luego se sincroniza con el servidor; el estado de sincronización se muestra en la ficha."
                color: S.faint; wrapMode: Text.WordWrap
                font.family: page.ui.fontFamily; font.pixelSize: 13 * page.ui.u
            }
        }
    }

    // ------------------------------------------------ Explorador de carpetas
    Item {
        anchors.fill: parent
        visible: page.browsing
        Column {
            id: browserHeader
            x: page.ui.gutter
            y: 8 * page.ui.u
            width: parent.width - 2 * page.ui.gutter
            spacing: 10 * page.ui.u
            Text {
                width: parent.width
                text: "Carpeta: " + (page.path.length ? page.path.map(function(r) { return S.text_(r, "name") }).join(" / ") : "raíz del proyecto")
                color: S.text; wrapMode: Text.WordWrap
                font.family: page.ui.fontFamily; font.pixelSize: 15 * page.ui.u
            }
            Row {
                spacing: 10 * page.ui.u
                RButton { ui: page.ui; glyph: 0xE06E; label: "Subir"; enabledButton: page.path.length > 0 && !page.browsingBusy; onActivated: page.folderUp() }
                RButton {
                    ui: page.ui; label: "Usar esta carpeta"; primary: true
                    enabledButton: page.path.length > 0 && !page.browsingBusy
                    busy: page.browsingBusy
                    onActivated: {
                        var current = page.path[page.path.length - 1]
                        var p = page.path.slice(); p.pop()
                        page.path = p
                        page.chooseFolder(current)
                    }
                }
                RButton { ui: page.ui; label: "Cancelar"; onActivated: page.browsing = false }
            }
            Text {
                width: parent.width
                visible: page.error.length > 0
                text: page.error
                color: S.danger; wrapMode: Text.WordWrap
                font.family: page.ui.fontFamily; font.pixelSize: 14 * page.ui.u
            }
            Text {
                width: parent.width
                visible: !page.browsingBusy && page.folders.length === 0
                text: "No hay subcarpetas aquí."
                color: S.muted
                font.family: page.ui.fontFamily; font.pixelSize: 14 * page.ui.u
            }
        }
        ListView {
            anchors.top: browserHeader.bottom
            anchors.topMargin: 10 * page.ui.u
            anchors.bottom: parent.bottom
            x: page.ui.gutter
            width: parent.width - 2 * page.ui.gutter
            clip: true
            spacing: 8 * page.ui.u
            model: page.folders
            delegate: Rectangle {
                required property var modelData
                width: ListView.view.width
                height: 56 * page.ui.u
                radius: 14 * page.ui.u
                color: folderTap.pressed ? S.surfaceStrong : S.surface
                border.width: 1; border.color: S.border
                Text {
                    x: 14 * page.ui.u
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width - 28 * page.ui.u
                    text: String.fromCharCode(0xE0D7)
                    font.family: page.ui.iconFamily; font.pixelSize: 20 * page.ui.u
                    color: S.accentSoft
                }
                Text {
                    x: 48 * page.ui.u
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width - 64 * page.ui.u
                    text: S.text_(modelData, "name")
                    color: S.text; elide: Text.ElideRight
                    font.family: page.ui.fontFamily; font.pixelSize: 15 * page.ui.u
                }
                MouseArea {
                    id: folderTap
                    anchors.fill: parent
                    enabled: !page.browsingBusy
                    onClicked: page.loadFolders(S.text_(modelData, "id"), modelData)
                }
            }
        }
    }
}

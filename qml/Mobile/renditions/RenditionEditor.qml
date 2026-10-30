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
    // Nueva rendición en 3 pasos (Proyecto → Período → Detalles).
    readonly property bool stepped: !editing
    property int step: 1
    function iso(d) { return d.getFullYear() + "-" + ("0" + (d.getMonth() + 1)).slice(-2) + "-" + ("0" + d.getDate()).slice(-2) }
    function parseIso(v) { var m = /^(\d{4})-(\d{2})-(\d{2})/.exec(String(v || "")); return m ? new Date(+m[1], +m[2] - 1, +m[3]) : new Date() }
    function presetRange(kind) {
        var t = parseIso(ctl.today())
        if (kind === "month") return [iso(new Date(t.getFullYear(), t.getMonth(), 1)), iso(new Date(t.getFullYear(), t.getMonth() + 1, 0))]
        var monday = new Date(t.getFullYear(), t.getMonth(), t.getDate() - ((t.getDay() + 6) % 7))
        return [iso(monday), iso(new Date(monday.getFullYear(), monday.getMonth(), monday.getDate() + 6))]
    }
    readonly property string activePreset: {
        var w = presetRange("week"), m = presetRange("month")
        return start === w[0] && end === w[1] ? "week" : start === m[0] && end === m[1] ? "month" : "custom"
    }
    readonly property int periodDays: Math.max(0, Math.round((parseIso(end) - parseIso(start)) / 86400000) + 1)
    function primaryName() {
        var rows = app.st.projects || []
        for (var i = 0; i < rows.length; ++i) if (S.text_(rows[i], "id", "project_id") === primary) return String(S.text_(rows[i], "name") || ctl.projectLabel(primary))
        return primary.length ? ctl.projectLabel(primary) : ""
    }
    function shortDate(v) {
        var d = parseIso(v)
        return d.getDate() + " " + ["ene", "feb", "mar", "abr", "may", "jun", "jul", "ago", "set", "oct", "nov", "dic"][d.getMonth()]
    }
    function nextStep() {
        error = ""
        if (step === 1 && !primary.length) { error = "Elige el proyecto de la rendición."; return }
        if (step === 2 && (!start.length || !end.length || start > end)) { error = "Revisa el período: la fecha final no puede ser anterior a la inicial."; return }
        if (step === 2 && !displayName.trim().length)              // nombre sugerido (editable)
            displayName = primaryName() + " · " + shortDate(start) + (start !== end ? " – " + shortDate(end) : "")
        if (step < 3) { step++; formFlick.contentY = 0 } else save()
    }
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
        var week = presetRange("week")
        start = source ? String(source.periodStart) : String(b.periodStart || (editing ? ctl.today() : week[0]))
        end = source ? String(source.periodEnd) : String(b.periodEnd || (editing ? ctl.today() : week[1]))
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
        error = ""                                    // el aviso de carpeta no sigue visible al elegirla
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
        error = ""
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
            if (!life.alive) return
            if (page.editing) page.app.closePage()
            else page.app.openCreated(String(saved.localId))
        })
    }

    // Composición aprobada (imagen 1): «1. Proyecto» en mosaicos con aura de color,
    // «2. Período» compacto (dos fechas verticales a la izquierda; carpeta y nombre
    // apilados a la derecha) y «Crear rendición». Vidrio claro existente; sin fondos.
    readonly property var tileTones: [S.corporateBlue, "#F28C28", "#2EB872", "#8B5CF6"]
    component Block: Rectangle {
        id: block
        property var ui
        property int glyph: 0
        property string heading: ""
        property string subtitle: ""
        default property alias content: blockBody.data
        width: parent ? parent.width : 0
        height: blockColumn.implicitHeight + 32 * ui.u
        radius: 24 * ui.u
        color: S.cardGlass
        border.width: 1; border.color: S.edge(0.9)
        Column {
            id: blockColumn
            x: 14 * block.ui.u; y: 16 * block.ui.u
            width: parent.width - 28 * block.ui.u
            spacing: 14 * block.ui.u
            Row {
                spacing: 12 * block.ui.u
                Rectangle {
                    width: 44 * block.ui.u; height: width; radius: 12 * block.ui.u
                    color: S.tintSoft
                    Text { anchors.centerIn: parent; text: String.fromCharCode(block.glyph); color: S.navy
                           font.family: block.ui.iconFamily; font.pixelSize: 22 * block.ui.u }
                }
                Column {
                    anchors.verticalCenter: parent.verticalCenter
                    Text { text: block.heading; color: S.text; font.family: block.ui.fontFamily; font.pixelSize: 18 * block.ui.u; font.weight: Font.DemiBold }
                    Text { text: block.subtitle; color: S.muted; font.family: block.ui.fontFamily; font.pixelSize: 14 * block.ui.u }
                }
            }
            Column { id: blockBody; width: parent.width; spacing: 10 * block.ui.u }
        }
    }

    Rectangle {
        anchors.fill: parent
        visible: page.embedded && page.stepped
        radius: 22 * page.ui.u
        color: S.lite(246, 248, 252, 0.97)
    }
    Flickable {
        id: formFlick
        anchors.fill: parent
        anchors.bottomMargin: page.stepped ? stepActions.height + 8 * page.ui.u : 0
        visible: !page.browsing
        contentWidth: width
        contentHeight: form.height + (page.embedded ? 30 : 140) * page.ui.u
        boundsBehavior: Flickable.StopAtBounds
        clip: true
        Column {
            id: form
            x: page.embedded ? 12 * page.ui.u : page.ui.gutter
            y: page.embedded ? 8 * page.ui.u : 8 * page.ui.u
            width: parent.width - 2 * x
            spacing: 12 * page.ui.u

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

            Row {
                id: stepBar
                objectName: "renditionStepBar"
                visible: page.stepped
                width: parent.width; spacing: 6 * page.ui.u
                Repeater {
                    model: ["Proyecto", "Período", "Detalles"]
                    delegate: Column {
                        id: stepCell
                        required property string modelData
                        required property int index
                        width: (stepBar.width - 2 * stepBar.spacing) / 3; spacing: 6 * page.ui.u
                        Rectangle { width: stepCell.width; height: 5 * page.ui.u; radius: height / 2
                                    color: stepCell.index < page.step ? S.accent : S.ink(0.10)
                                    Behavior on color { ColorAnimation { duration: 240 } } }
                        Text { text: stepCell.modelData; color: stepCell.index < page.step ? S.text : S.muted
                               font.family: page.ui.fontFamily; font.pixelSize: 12 * page.ui.u; font.weight: Font.DemiBold }
                    }
                }
            }

            // ------------------------------------------------------ 1. Proyecto
            Block {
                visible: !page.stepped || page.step === 1
                ui: page.ui; glyph: 0xE0D7; heading: page.stepped ? "¿Para qué proyecto?" : "1. Proyecto"
                subtitle: page.stepped ? "Toca un proyecto; con «···» lo marcas como principal" : "Selecciona el proyecto de la rendición"
                Text {
                    width: parent.width
                    visible: (page.app.st.projects || []).length === 0
                    text: "No hay proyectos autorizados para rendiciones en tu cuenta (o aún se están cargando)."
                    color: S.muted; wrapMode: Text.WordWrap
                    font.family: page.ui.fontFamily; font.pixelSize: 14 * page.ui.u
                }
                Grid {
                    id: projectGrid
                    width: parent.width
                    columns: page.stepped ? 1 : 2
                    spacing: 10 * page.ui.u
                    Repeater {
                        model: page.app.st.projects || []
                        delegate: Item {
                            id: tile
                            required property var modelData
                            required property int index
                            readonly property string projectId: S.text_(modelData, "id", "project_id")
                            readonly property bool checked: page.projects.indexOf(projectId) >= 0
                            readonly property bool isPrimary: page.primary === projectId
                            readonly property color tone: page.tileTones[index % page.tileTones.length]
                            width: (projectGrid.width - (projectGrid.columns - 1) * projectGrid.spacing) / projectGrid.columns
                            height: 70 * page.ui.u
                            Rectangle {                    // aura de color (selección)
                                anchors.fill: parent; anchors.margins: -3 * page.ui.u
                                radius: 22 * page.ui.u
                                color: "transparent"
                                border.width: 3 * page.ui.u
                                border.color: Qt.rgba(tile.tone.r, tile.tone.g, tile.tone.b, tile.checked ? 0.38 : 0.14)
                                Behavior on border.color { ColorAnimation { duration: 160 } }
                            }
                            Rectangle {
                                anchors.fill: parent
                                radius: 20 * page.ui.u
                                color: tileTap.pressed ? S.glass(0.75) : S.glass(0.92)
                                border.width: 1
                                border.color: Qt.rgba(tile.tone.r, tile.tone.g, tile.tone.b, tile.checked ? 0.85 : 0.30)
                            }
                            Text {
                                id: folderGlyph
                                x: 14 * page.ui.u; anchors.verticalCenter: parent.verticalCenter
                                text: String.fromCharCode(0xE0D7); color: tile.tone
                                font.family: page.ui.iconFamily; font.pixelSize: 26 * page.ui.u
                            }
                            Column {
                                x: 50 * page.ui.u
                                width: parent.width - x - 48 * page.ui.u
                                anchors.verticalCenter: parent.verticalCenter
                                Text { width: parent.width; text: String(S.text_(tile.modelData, "name") || page.ctl.projectLabel(tile.projectId)).toUpperCase()
                                       color: S.text; elide: Text.ElideRight
                                       font.family: page.ui.fontFamily; font.pixelSize: 15 * page.ui.u; font.weight: Font.DemiBold }
                                Text { visible: tile.checked; text: tile.isPrimary ? "Principal" : "Asociado"
                                       color: tile.isPrimary ? tile.tone : S.muted
                                       font.family: page.ui.fontFamily; font.pixelSize: 12 * page.ui.u }
                            }
                            MouseArea { id: tileTap; anchors.fill: parent; enabled: page.writable; onClicked: page.toggleProject(tile.projectId) }
                            Rectangle {                    // ··· : hacer principal (sólo si está asociado)
                                width: 40 * page.ui.u; height: width; radius: width / 2
                                anchors.right: parent.right; anchors.rightMargin: 8 * page.ui.u
                                anchors.verticalCenter: parent.verticalCenter
                                color: moreTap.pressed ? S.ink(0.12) : S.ink(0.05)
                                Text { anchors.centerIn: parent; text: String.fromCharCode(0xE0B6); color: S.text
                                       font.family: page.ui.iconFamily; font.pixelSize: 18 * page.ui.u }
                                MouseArea {
                                    id: moreTap; anchors.fill: parent; enabled: page.writable
                                    onClicked: { if (!tile.checked) page.toggleProject(tile.projectId); page.setPrimary(tile.projectId) }
                                }
                                Accessible.role: Accessible.Button
                                Accessible.name: "Hacer principal"
                            }
                        }
                    }
                }
            }

            // ------------------------------------------------------- 2. Período
            Block {
                visible: page.stepped && page.step === 2
                ui: page.ui; glyph: 0xE063; heading: "¿Qué período cubre?"
                subtitle: page.periodDays + (page.periodDays === 1 ? " día" : " días") + " · gastos dentro de este rango"
                Row {
                    id: presetRow
                    width: parent.width; spacing: 8 * page.ui.u
                    Repeater {
                        model: [{ k: "week", l: "Esta semana" }, { k: "month", l: "Este mes" }, { k: "custom", l: "Otro" }]
                        delegate: Rectangle {
                            id: presetCell
                            required property var modelData
                            readonly property bool on: page.activePreset === modelData.k
                            width: (presetRow.width - 2 * presetRow.spacing) / 3; height: 48 * page.ui.u; radius: 14 * page.ui.u
                            color: on ? Qt.rgba(6 / 255, 84 / 255, 162 / 255, 0.10) : S.glass(0.9)
                            border.width: on ? 2 : 1; border.color: on ? S.accent : S.fieldBorder
                            Behavior on color { ColorAnimation { duration: 160 } }
                            Text { anchors.centerIn: parent; text: presetCell.modelData.l; color: presetCell.on ? S.accent : S.text
                                   font.family: page.ui.fontFamily; font.pixelSize: 14 * page.ui.u; font.weight: presetCell.on ? Font.Bold : Font.Normal }
                            MouseArea { anchors.fill: parent; enabled: page.writable
                                        onClicked: {
                                            if (presetCell.modelData.k === "custom") { startPicker.openPicker(); return }
                                            var r = page.presetRange(presetCell.modelData.k); page.start = r[0]; page.end = r[1]; page.changed()
                                        } }
                            Accessible.role: Accessible.RadioButton
                            Accessible.name: modelData.l
                            Accessible.checked: on
                        }
                    }
                }
                Row {
                    id: stepDates
                    width: parent.width; spacing: 8 * page.ui.u
                    Repeater {
                        model: [{ key: "start", label: "Desde" }, { key: "end", label: "Hasta" }]
                        delegate: Rectangle {
                            id: stepDate
                            required property var modelData
                            width: (stepDates.width - stepDates.spacing) / 2; height: 64 * page.ui.u; radius: 16 * page.ui.u
                            color: stepDateTap.pressed ? S.glass(0.7) : S.glass(0.9)
                            border.width: 1; border.color: S.fieldBorder
                            Column {
                                x: 14 * page.ui.u; anchors.verticalCenter: parent.verticalCenter; spacing: 2 * page.ui.u
                                Text { text: stepDate.modelData.label; color: S.muted; font.family: page.ui.fontFamily; font.pixelSize: 12 * page.ui.u; font.weight: Font.DemiBold }
                                Text { text: S.date(stepDate.modelData.key === "start" ? page.start : page.end); color: S.text
                                       font.family: page.ui.fontFamily; font.pixelSize: 17 * page.ui.u; font.weight: Font.Bold }
                            }
                            Text { anchors.right: parent.right; anchors.rightMargin: 12 * page.ui.u; anchors.verticalCenter: parent.verticalCenter
                                   text: String.fromCharCode(0xE063); color: S.accent; font.family: page.ui.iconFamily; font.pixelSize: 20 * page.ui.u }
                            MouseArea { id: stepDateTap; anchors.fill: parent; enabled: page.writable
                                        onClicked: (stepDate.modelData.key === "start" ? startPicker : endPicker).openPicker() }
                            Accessible.role: Accessible.Button
                            Accessible.name: modelData.label
                        }
                    }
                }
            }

            // ---------------------------------------------- 3. Detalles (al crear)
            Block {
                visible: page.stepped && page.step === 3
                ui: page.ui; glyph: 0xE0CC; heading: "Últimos detalles"; subtitle: "Nombre y carpeta de InGe Drive"
                RField {
                    id: stepName
                    objectName: "renditionStepName"
                    width: parent.width
                    ui: page.ui; formStyle: true; label: "Nombre de la rendición"; maxLength: 160
                    text: page.displayName
                    readOnly: !page.writable
                    onEdited: { page.displayName = text; page.changed() }
                }
                Rectangle {
                    width: parent.width; height: 68 * page.ui.u; radius: 16 * page.ui.u
                    color: stepFolderTap.pressed ? S.glass(0.7) : S.glass(0.9)
                    border.width: page.folder.length ? 1 : 1.5
                    border.color: page.folder.length ? S.fieldBorder : S.accentSoft
                    Text { x: 14 * page.ui.u; anchors.verticalCenter: parent.verticalCenter; text: String.fromCharCode(0xE0D7); color: S.accent
                           font.family: page.ui.iconFamily; font.pixelSize: 24 * page.ui.u }
                    Column {
                        x: 50 * page.ui.u; width: parent.width - x - 90 * page.ui.u
                        anchors.verticalCenter: parent.verticalCenter; spacing: 2 * page.ui.u
                        Text { text: "Carpeta en InGe Drive"; color: S.muted; font.family: page.ui.fontFamily; font.pixelSize: 12 * page.ui.u; font.weight: Font.DemiBold }
                        Text { width: parent.width; elide: page.folder.length ? Text.ElideMiddle : Text.ElideRight
                               text: page.browsingBusy ? "Abriendo InGe Drive…" : page.folder.length ? (page.folderName.length ? page.folderName : "Carpeta seleccionada") : "Elige una carpeta"
                               color: page.folder.length ? S.text : S.accent
                               font.family: page.ui.fontFamily; font.pixelSize: 15 * page.ui.u; font.weight: Font.Bold }
                    }
                    Text { anchors.right: parent.right; anchors.rightMargin: 14 * page.ui.u; anchors.verticalCenter: parent.verticalCenter
                           text: page.folder.length ? "Cambiar" : "Elegir"; color: S.accent
                           font.family: page.ui.fontFamily; font.pixelSize: 14 * page.ui.u; font.weight: Font.Bold }
                    MouseArea { id: stepFolderTap; anchors.fill: parent; enabled: page.writable && !page.browsingBusy; onClicked: page.openFolders() }
                    Accessible.role: Accessible.Button
                    Accessible.name: "Carpeta en InGe Drive"
                }
                Text {
                    width: parent.width; wrapMode: Text.WordWrap; color: S.muted
                    text: "Proyecto: " + page.primaryName() + "\nPeríodo: " + S.date(page.start) + " – " + S.date(page.end)
                    font.family: page.ui.fontFamily; font.pixelSize: 13.5 * page.ui.u
                }
            }

            // Composición aprobada al editar (sin pasos).
            Block {
                visible: !page.stepped
                ui: page.ui; glyph: 0xE063; heading: "2. Período"; subtitle: "Define el rango de fechas de la rendición"
                Row {
                    id: periodRow
                    width: parent.width
                    spacing: 10 * page.ui.u
                    readonly property real dateWidth: Math.max(86 * page.ui.u, (width - 2 * spacing) * 0.22)
                    readonly property real blockHeight: 2 * 96 * page.ui.u + 10 * page.ui.u
                    Repeater {
                        model: [{ key: "start", label: "Fecha\ninicio", tone: S.accentSoft }, { key: "end", label: "Fecha\nfin", tone: "#8B5CF6" }]
                        delegate: Rectangle {
                            id: dateBox
                            required property var modelData
                            readonly property string value: modelData.key === "start" ? page.start : page.end
                            readonly property color tone: modelData.tone
                            width: periodRow.dateWidth
                            height: periodRow.blockHeight
                            radius: 18 * page.ui.u
                            color: dateTap.pressed ? S.glass(0.7) : S.glass(0.9)
                            border.width: 1.5
                            border.color: Qt.rgba(dateBox.tone.r, dateBox.tone.g, dateBox.tone.b, 0.55)
                            Column {
                                anchors.horizontalCenter: parent.horizontalCenter
                                y: 18 * page.ui.u
                                width: parent.width - 8 * page.ui.u
                                spacing: 10 * page.ui.u
                                Text { anchors.horizontalCenter: parent.horizontalCenter; text: String.fromCharCode(0xE063); color: S.navy
                                       font.family: page.ui.iconFamily; font.pixelSize: 26 * page.ui.u }
                                Text { width: parent.width; horizontalAlignment: Text.AlignHCenter; text: dateBox.modelData.label; color: S.text
                                       font.family: page.ui.fontFamily; font.pixelSize: 15 * page.ui.u }
                                Text { width: parent.width; horizontalAlignment: Text.AlignHCenter; text: dateBox.value.length ? S.date(dateBox.value) : "—"
                                       color: S.text; fontSizeMode: Text.HorizontalFit; minimumPixelSize: 10
                                       font.family: page.ui.fontFamily; font.pixelSize: 15 * page.ui.u; font.weight: Font.DemiBold }
                            }
                            Rectangle { x: 6 * page.ui.u; width: parent.width - 12 * page.ui.u; height: 1; y: parent.height - 52 * page.ui.u; color: S.ink(0.08) }
                            Text { anchors.horizontalCenter: parent.horizontalCenter; y: parent.height - 38 * page.ui.u
                                   text: String.fromCharCode(0xE06D); color: S.navy; font.family: page.ui.iconFamily; font.pixelSize: 20 * page.ui.u }
                            MouseArea { id: dateTap; anchors.fill: parent; enabled: page.writable
                                        onClicked: (dateBox.modelData.key === "start" ? startPicker : endPicker).openPicker() }
                            Accessible.role: Accessible.Button
                            Accessible.name: dateBox.modelData.label.replace("\n", " ") + " " + dateBox.value
                        }
                    }
                    Column {
                        width: parent.width - 2 * periodRow.dateWidth - 2 * periodRow.spacing
                        spacing: 10 * page.ui.u
                        Rectangle {                        // Carpeta documental (selector real InGe Drive)
                            width: parent.width; height: 96 * page.ui.u
                            radius: 18 * page.ui.u
                            color: folderBoxTap.pressed ? S.glass(0.7) : S.glass(0.9)
                            border.width: 1.5; border.color: Qt.rgba(46 / 255, 184 / 255, 114 / 255, 0.50)
                            opacity: page.writable && page.primary.length > 0 ? 1 : 0.6
                            Text { x: 12 * page.ui.u; anchors.verticalCenter: parent.verticalCenter; text: String.fromCharCode(0xE0D7); color: S.navy
                                   font.family: page.ui.iconFamily; font.pixelSize: 26 * page.ui.u }
                            Column {
                                x: 48 * page.ui.u; width: parent.width - x - 30 * page.ui.u
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: 3 * page.ui.u
                                Text { width: parent.width; text: "Carpeta documental"; color: S.text; elide: Text.ElideRight
                                       font.family: page.ui.fontFamily; font.pixelSize: 15 * page.ui.u; font.weight: Font.DemiBold }
                                Text { width: parent.width; maximumLineCount: 2; wrapMode: Text.WordWrap; elide: Text.ElideRight
                                       text: page.browsingBusy ? "Abriendo InGe Drive…"
                                             : page.folder.length ? (page.folderName.length ? page.folderName : "Carpeta seleccionada")
                                             : !page.primary.length ? "Elige primero el proyecto" : "Selecciona la carpeta donde se guardarán los documentos"
                                       color: page.folder.length ? S.text : S.muted
                                       font.family: page.ui.fontFamily; font.pixelSize: 12 * page.ui.u }
                            }
                            Text { anchors.right: parent.right; anchors.rightMargin: 8 * page.ui.u; anchors.verticalCenter: parent.verticalCenter
                                   text: String.fromCharCode(0xE06D); color: S.navy; font.family: page.ui.iconFamily; font.pixelSize: 18 * page.ui.u }
                            MouseArea { id: folderBoxTap; anchors.fill: parent; enabled: page.writable && !page.browsingBusy; onClicked: page.openFolders() }
                            Accessible.role: Accessible.Button
                            Accessible.name: "Carpeta documental"
                        }
                        Rectangle {                        // Nombre de la rendición (editable)
                            width: parent.width; height: 96 * page.ui.u
                            radius: 18 * page.ui.u
                            color: S.glass(0.9)
                            border.width: 1.5
                            border.color: nameInput.activeFocus ? S.accentSoft : Qt.rgba(59 / 255, 130 / 255, 214 / 255, 0.45)
                            Text { x: 12 * page.ui.u; anchors.verticalCenter: parent.verticalCenter; text: String.fromCharCode(0xE0CC); color: S.navy
                                   font.family: page.ui.iconFamily; font.pixelSize: 26 * page.ui.u }
                            Column {
                                x: 48 * page.ui.u; width: parent.width - x - 10 * page.ui.u
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: 2 * page.ui.u
                                Text { width: parent.width; text: "Nombre de la rendición"; color: S.text; elide: Text.ElideRight
                                       font.family: page.ui.fontFamily; font.pixelSize: 15 * page.ui.u; font.weight: Font.DemiBold }
                                TextField {
                                    id: nameInput
                                    objectName: "renditionNameInput"
                                    width: parent.width
                                    height: 48 * page.ui.u
                                    padding: 0; leftPadding: 0
                                    background: null
                                    text: page.displayName
                                    placeholderText: "Asigna un nombre identificativo"
                                    placeholderTextColor: S.faint
                                    readOnly: page.editing || !page.writable
                                    maximumLength: 160
                                    color: S.text
                                    selectByMouse: true
                                    inputMethodHints: Qt.ImhNoPredictiveText
                                    font.family: page.ui.fontFamily; font.pixelSize: 16 * page.ui.u
                                    onTextEdited: { page.displayName = text; page.changed() }
                                }
                            }
                        }
                    }
                }
                // Calendarios reales (lógica de RDateField: mínimo/máximo); sin caja propia.
                RDateField { id: startPicker; visible: false; width: 0; ui: page.ui; value: page.start; readOnly: !page.writable; animatePicker: true
                             onPicked: function(v) { page.start = v; page.changed() } }
                RDateField { id: endPicker; visible: false; width: 0; ui: page.ui; value: page.end; minimum: page.start; readOnly: !page.writable; animatePicker: true
                             onPicked: function(v) { page.end = v; page.changed() } }
            }
            Text {
                width: parent.width
                visible: page.editing
                text: "El nombre existente se administra desde el archivo .rend en InGeDrive/Web. El código se conserva como identificador."
                color: S.muted; wrapMode: Text.WordWrap
                font.family: page.ui.fontFamily; font.pixelSize: 13 * page.ui.u
            }

            Text {
                width: parent.width
                visible: page.error.length > 0
                text: page.error
                color: S.danger; wrapMode: Text.WordWrap
                font.family: page.ui.fontFamily; font.pixelSize: 14 * page.ui.u
            }
            RButton {
                visible: !page.stepped
                width: parent.width
                height: 56 * page.ui.u
                radius: 18 * page.ui.u
                ui: page.ui
                primary: true
                glyph: 0xE0C8                           // file-plus (Lucide)
                label: page.editing ? "Guardar cambios" : "Crear rendición"
                busy: page.app.busy("header:" + (page.editing ? page.original.localId : "new"))
                enabledButton: page.writable
                onActivated: page.save()
            }
        }
    }

    // Acciones de los pasos: siempre visibles al pie de la hoja.
    Row {
        id: stepActions
        objectName: "renditionStepActions"
        visible: page.stepped && !page.browsing
        anchors.bottom: parent.bottom; anchors.bottomMargin: 4 * page.ui.u
        x: page.embedded ? 12 * page.ui.u : page.ui.gutter
        width: parent.width - 2 * x
        height: 54 * page.ui.u
        spacing: 10 * page.ui.u
        RButton {
            visible: page.step > 1
            width: (parent.width - parent.spacing) / 3; height: parent.height; radius: 16 * page.ui.u
            ui: page.ui; label: "Atrás"; color: S.ink(0.06)
            onActivated: { page.error = ""; page.step--; formFlick.contentY = 0 }
        }
        RButton {
            objectName: "renditionStepNext"
            width: page.step > 1 ? (parent.width - parent.spacing) * 2 / 3 : parent.width; height: parent.height; radius: 16 * page.ui.u
            ui: page.ui; primary: true
            glyph: page.step === 3 ? 0xE0C8 : 0
            label: page.step === 3 ? "Crear rendición" : "Continuar"
            busy: page.app.busy("header:new")
            enabledButton: page.writable
            onActivated: page.nextStep()
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
            Flow {
                width: parent.width
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

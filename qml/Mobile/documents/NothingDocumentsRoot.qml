// SPDX-License-Identifier: GPL-3.0-only
// Native QML adaptation of Nothing Files MainActivity.kt. Scope: Documents only.
pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import InGe.Mobile as MobileBackend
import "../flowcore" as FlowCore
import "../components" as Components
import "../pages" as Pages

Rectangle {
    id: root
    signal renditionOpenRequested(string renditionId)
    signal calicataOpenRequested(string projectId, string calicataId)
    signal calicataJsonOpenRequested(string spaceId, string nodeId, string versionId)
    // .xlsx → Calicatas: ruta LOCAL de lectura (copia espejo de InGeDrive o el
    // archivo local) + metadatos de origen. El original nunca se modifica.
    signal calicataExcelOpenRequested(string localPath, var source)
    property var pendingCalicataExcel: null
    // Solo la subapp Calicatas enruta <código>.calicata.json; InGeDrive general no cambia.
    property bool routeCalicataJson: false
    property bool pendingOpenDrive: false
    property bool systemDark: false
    property bool motionAllowed: true
    required property var flow
    // One static backdrop for grouped controls; rows never capture the list.

    property real bottomSafeInset: 0
    property bool contextEnabled: true
    readonly property bool dark: files.theme === "dark" || (files.theme === "system" && systemDark)
    // Identidad INGEMA: el modo oscuro propio de InGeDrive usa Deep/Navy y
    // el tinte derivado de Blue; el claro consume FlowTheme directamente.
    readonly property color surface: dark ? root.flow.colors.ingemaNavy : root.flow.theme.surfaceSecondary
    readonly property color ink: dark ? "#ffffff" : root.flow.theme.textPrimary
    readonly property color accent: dark ? root.flow.colors.ingemaBlueTint : root.flow.theme.accent
    readonly property color muted: dark ? root.flow.colors.ingemaPaperTertiary : root.flow.theme.textTertiary
    readonly property color danger: dark ? "#FF8A91" : root.flow.theme.error
    readonly property bool home: files.route === "home"
    property var currentFile: ({})
    property var pendingPaths: []
    property string dialogKind: ""
    property string dialogTitle: ""
    property string detailText: ""
    property string resultPath: ""
    property bool createFolder: true
    // Primera carga real: ocupado y sin contenido que conservar.
    readonly property bool firstLoadPending: files.busy && files.count === 0 && !root.home
                                             && root.driveOperationLabel.length === 0
    // Operación de archivo en curso (texto contextual; se limpia al terminar).
    property string driveOperationLabel: ""
    readonly property bool driveBusy: files.busy
    onDriveBusyChanged: if (!driveBusy) driveOperationLabel = ""
    function beginDriveOperation(label) {
        driveOperationLabel = label
        // Si la operación terminó (o falló) sin pasar por busy, no dejar
        // el texto pegado para la siguiente recarga.
        Qt.callLater(function() { if (!files.busy) root.driveOperationLabel = "" })
    }
    property bool clipboardCutV600: false
    function rememberClipboardV600(paths, cut) {
        clipboardCutV600 = cut === true
        files.clipboard(paths, cut)
    }
    readonly property var driveOperation: files.busy && driveOperationLabel.length
        ? ({ id: "DRIVE-" + driveOperationLabel, kind: "DRIVE_FILE_OPERATION",
             title: driveOperationLabel, detail: "", blocking: true, cover: false })
        : null
    property string toastText: ""
    property string currentRoute: files.route

    color: dark ? (files.oled ? "#000000" : root.flow.colors.ingemaDeep) : root.flow.theme.surfaceElevated
    clip: true

    MobileBackend.NothingDocuments {
        id: files
    }
    function openDriveRoot() {
        if (files.busy) {
            pendingOpenDrive = true
            return
        }
        pendingOpenDrive = false
        if (files.route !== "drive")
            files.navigate("drive")
    }
    function handleBack() {
        if (popup.visible) {
            popup.close();
            return true;
        }
        if (actionMenu.visible) {
            actionMenu.close();
            return true;
        }
        if (sortMenu.visible) {
            sortMenu.close();
            return true;
        }
        if (selectionMenu.visible) {
            selectionMenu.close();
            return true;
        }
        return root.home ? false : files.back();
    }
    function showDialog(kind, title) {
        dialogKind = kind;
        dialogTitle = title;
        input.text = "";
        popup.open();
    }
    // ===== InGe Drive: fuente única de acciones =====
    // itemActions(file) alimenta el "…" de la fila, el long press y el "…" del
    // Dock. Capacidades: get_document_structural_capabilities_v02 (servidor);
    // la UI solo oculta/deshabilita, inge_drive_mutate_v03 es la autoridad final.
    property string heldPath: ""
    function capsFor(file) {
        var rev = files.capabilitiesRevision
        if (!file || !file.remote) return {}
        if (file.path === files.currentFolderPath) return files.folderCapabilities || {}
        return files.capabilitiesFor(file.path) || {}
    }
    function itemActions(file) {
        if (!file || !file.path) return []
        var caps = root.capsFor(file)
        var remote = file.remote === true
        var dir = file.directory === true
        var xlsx = !dir && /\.xlsx$/i.test(String(file.name || file.path || ""))
        var list = []
        function add(id, glyph, dockIcon, supported, capability, destructive) {
            var allowed = !capability || !remote || caps[capability] === true
            list.push({ id: id, label: id, glyph: glyph, dockIcon: dockIcon, capability: capability || "",
                        allowed: supported && allowed, enabled: supported && allowed && !files.busy,
                        visible: true, destructive: destructive === true })
        }
        if (files.route === "trash") {
            add("RESTAURAR", "restore", "status.sync", true, "")
            add("ELIMINAR DEFINITIVAMENTE", "delete_forever", "action.delete", true, "", true)
            add("DETALLES", "info", "documents.file", true, "")
        } else if (remote) {
            add("ABRIR", "open_in_new", "documents.open", true, "")
            if (xlsx && file.kind !== "SMART_DOCUMENT")
                add("ABRIR CON CALICATAS", "description", "documents.open", true, "")
            if (file.kind !== "SMART_DOCUMENT") {
                add("DESCARGAR", "download", "documents.download", !dir, "")
                add("RENOMBRAR", "edit", "action.edit", true, "canRenameFolder")
                add("CORTAR", "content_cut", "action.paste", true, "canMoveFolder")
                add("MOVER A PAPELERA", "delete", "action.delete", true, "canDeleteFolder", true)
            }
            add("DETALLES", "info", "documents.file", true, "canViewFolderInfo")
        } else {
            add("ABRIR CON", "open_in_new", "documents.open", !dir, "")
            if (xlsx) add("ABRIR CON CALICATAS", "description", "documents.open", true, "")
            add("CORTAR", "content_cut", "action.paste", true, "")
            add("COPIAR", "content_copy", "action.copy", true, "")
            add("RENOMBRAR", "edit", "action.edit", true, "")
            add("COMPARTIR", "share", "documents.upload", !dir, "")
            if (file.extension === "zip") add("EXTRAER", "unarchive", "documents.file", true, "")
            else add("COMPRIMIR", "archive", "documents.file", true, "")
            if (["txt", "log", "json", "xml"].indexOf(file.extension) >= 0)
                add("LEER TEXTO", "menu_book", "documents.file", !dir, "")
            add("DETALLES", "info", "documents.file", true, "")
            add("SUBIR A INGE DRIVE", "upload", "documents.upload", !dir, "")
            add("MOVER A PAPELERA", "delete", "action.delete", true, "", true)
        }
        add("SELECCIONAR", "check", "action.check", true, "")
        return list
    }
    // Abrir con Calicatas: un remoto se materializa con la descarga existente
    // (copia espejo, sin abrir visor externo); al completarse se entrega la ruta.
    function openWithCalicatas(file) {
        var source = { fileId: String(file.id || ""), name: String(file.name || ""),
                       path: String(file.path || ""), remote: file.remote === true,
                       folderPath: String(files.breadcrumb ? files.breadcrumb() : "") }
        if (file.remote !== true) {
            root.calicataExcelOpenRequested(String(file.path), source)
            return
        }
        root.pendingCalicataExcel = source
        root.beginDriveOperation("Preparando Excel…")
        files.download(file)
    }
    Connections {
        target: files
        function onCompleted(message, path) {
            var source = root.pendingCalicataExcel
            if (!source || !path) return
            var name = String(path).replace(/\\/g, "/").split("/").pop()
            if (name !== source.name) return
            root.pendingCalicataExcel = null
            root.calicataExcelOpenRequested(String(path), source)
        }
        // `error` notifica por changed(): un fallo de descarga cancela la importación pendiente.
        function onChanged() {
            if (root.pendingCalicataExcel && String(files.error || "").length) root.pendingCalicataExcel = null
        }
    }
    function runItemAction(id, file) {
        if (!file || !file.path) return
        var actions = root.itemActions(file)
        var action = null
        for (var i = 0; i < actions.length; ++i)
            if (actions[i].id === id) action = actions[i]
        if (!action || action.enabled !== true) return
        root.currentFile = file
        var p = file.path
        if (id === "ABRIR" || id === "ABRIR CON")
            files.open(file, id === "ABRIR CON")
        else if (id === "ABRIR CON CALICATAS")
            root.openWithCalicatas(file)
        else if (id === "DESCARGAR") {
            root.beginDriveOperation("Descargando…")
            files.download(file)
        } else if (id === "CORTAR" || id === "COPIAR")
            root.rememberClipboardV600([p], id === "CORTAR")
        else if (id === "RENOMBRAR") {
            root.showDialog("rename", file.directory ? "RENOMBRAR CARPETA" : "RENOMBRAR")
            input.text = String(file.name || "")
        } else if (id === "COMPARTIR")
            files.open(file, false, true)
        else if (id === "COMPRIMIR" || id === "EXTRAER")
            files.archive(p, id === "EXTRAER")
        else if (id === "LEER TEXTO")
            files.readText(p)
        else if (id === "DETALLES")
            root.details(file)
        else if (id === "RESTAURAR")
            files.restore([p])
        else if (id === "SUBIR A INGE DRIVE") {
            root.showDialog("upload", "SUBIR A INGE DRIVE")
            input.text = String(file.name || "")
        } else if (id === "SELECCIONAR")
            files.toggleSelection(p)
        else if (id === "MOVER A PAPELERA" || id === "ELIMINAR DEFINITIVAMENTE")
            root.confirmDelete([p], id === "ELIMINAR DEFINITIVAMENTE")
    }
    // "…" del Dock: menú Liquid Glass (children). Solo acciones autorizadas por
    // el servidor para la carpeta abierta + Ordenar (submenú).
    function dockMoreActions() {
        var children = []
        var rev = files.capabilitiesRevision
        if (files.route === "drive" && files.selectedCount === 0) {
            var caps = files.folderCapabilities || {}
            if (caps.canCreateFolder === true)
                children.push({ id: "docNewFolder", label: "Nueva carpeta", icon: "action.add",
                                command: "documents.folderNew", enabled: !files.busy })
            var current = files.currentFolderPath.length > 0 ? files.currentFolderEntry() : null
            if (current && current.path) {
                var labels = { "DETALLES": "Información", "RENOMBRAR": "Renombrar carpeta",
                               "CORTAR": "Mover carpeta", "MOVER A PAPELERA": "Mover a papelera" }
                var acts = root.itemActions(current)
                for (var i = 0; i < acts.length; ++i) {
                    var label = labels[acts[i].id]
                    if (label === undefined || acts[i].allowed !== true) continue
                    children.push({ id: "docCurrent" + i, label: label, icon: acts[i].dockIcon,
                                    command: "documents.current:" + acts[i].id, enabled: !files.busy,
                                    destructive: acts[i].destructive })
                }
            }
        }
        var order = files.sortOrder
        children.push({ id: "docSort", label: "Ordenar", icon: "action.menu", command: "", enabled: !files.busy, children: [
            { id: "docSortName", label: "Por nombre", icon: order === "name" ? "action.check" : "documents.file", command: "documents.sort:name", selected: order === "name" },
            { id: "docSortDate", label: "Por fecha", icon: order === "date" ? "action.check" : "documents.file", command: "documents.sort:date", selected: order === "date" },
            { id: "docSortSize", label: "Por tamaño", icon: order === "size" ? "action.check" : "documents.file", command: "documents.sort:size", selected: order === "size" }
        ] })
        return children
    }
    function openNewFolder() {
        root.createFolder = true
        root.showDialog("create", "NUEVA CARPETA")
        input.text = ""
    }
    // Long press: selecciona (lift), un háptico y abre el mismo menú de la fila.
    // Nunca durante scroll (el Flickable cancela el MouseArea; además se verifica aquí).
    function longPress(file, view) {
        if (!file || !file.path || (view && (view.moving || view.dragging || view.flicking))) return
        console.info("INGE_DOC_LONGPRESS kind=" + (file.directory ? "folder" : "file") + " remote=" + (file.remote === true))
        root.heldPath = file.path
        if (root.flow && typeof root.flow.triggerHaptic === "function")
            root.flow.triggerHaptic("medium")
        root.fileMenu(file)
    }
    function confirmDelete(paths, forever) {
        pendingPaths = paths;
        showDialog(forever ? "permanent" : "delete", forever ? "ELIMINAR DEFINITIVAMENTE" : "MOVER A PAPELERA");
    }
    function fileMenu(file) {
        // Abrir el menú no debe devolver el foco (ni el IME) a la búsqueda.
        if (search.activeFocus) {
            search.focus = false;
            Qt.inputMethod.hide();
        }
        currentFile = file;
        actionMenu.popup();
    }
    function activate(file) {
        // Calicatas: un JSON de ficha en InGeDrive se abre en la subapp, no en un visor.
        var name = String(file.name || "");
        var path = String(file.path || "");
        // Nodo JSON de ficha (reserve_my_calicata_json_v01): ficha-<código>-<8 hex>,
        // o calicata-<uuid> (nombre previo); el listado puede traer o no ".json".
        var calicataJson = /^(ficha-(.+-)?[0-9a-f]{8}|calicata-[0-9a-f-]{36})(\.json)?$/i.test(name)
                           || /\.calicata\.json$/i.test(name);
        if (root.routeCalicataJson && !file.directory && calicataJson && path.indexOf("DRIVE:") === 0) {
            var parts = path.split(":");
            root.calicataJsonOpenRequested(parts[1], String(file.id || ""), String(file.current_version_id || ""));
            return;
        }
        files.open(file);
    }
    // DETALLES: solo datos reales del listado/servidor; lo que el servidor no
    // expone se indica como tal (nunca undefined, null ni 0 ficticio).
    function details(file) {
        if (!file || !file.path) return;
        var nl = String.fromCharCode(10);
        var caps = root.capsFor(file);
        var unavailable = "No informado por el servidor";
        var type = file.directory ? (file.kind === "SPACE" ? "ESPACIO" : "CARPETA")
                 : file.kind === "SMART_DOCUMENT" ? "DOCUMENTO INTELIGENTE"
                 : (file.extension ? "ARCHIVO ." + String(file.extension).toUpperCase() : "ARCHIVO");
        var modified = Number(file.modified || 0) > 0 ? Qt.formatDateTime(new Date(Number(file.modified)), "dd/MM/yyyy HH:mm")
                     : (file.date ? String(file.date) : unavailable);
        var parts = ["NOMBRE" + nl + String(file.name || ""), "TIPO" + nl + type];
        if (!file.directory) parts.push("TAMAÑO" + nl + files.formatSize(file.bytes || 0));
        parts.push("MODIFICADO" + nl + modified);
        if (file.remote) {
            var crumbs = files.breadcrumb();
            var segments = crumbs.split(" / ");
            var sync = ({ "SYNCED": "Sincronizado", "PENDING": "Pendiente de sincronizar", "RETRY": "Reintento pendiente",
                          "CONFLICT": "En conflicto", "REJECTED": "Rechazado por el servidor" })[String(file.sync_state || "")];
            var gov = caps.ready === true ? (({ "FLEXIBLE": "Flexible", "GOVERNED": "Gobernada (estructura protegida)" })[String(caps.governance || "")] || unavailable)
                                          : "Sin datos de permisos (sin conexión)";
            var perms = [];
            if (caps.canCreateFolder === true) perms.push("crear carpetas");
            if (caps.canRenameFolder === true) perms.push("renombrar");
            if (caps.canMoveFolder === true) perms.push("mover");
            if (caps.canDeleteFolder === true) perms.push("enviar a papelera");
            parts.push("CREADO" + nl + unavailable);
            parts.push("PROPIETARIO" + nl + unavailable);
            parts.push("UBICACIÓN" + nl + crumbs);
            parts.push("ESPACIO / PROYECTO" + nl + (segments.length > 1 ? segments[1] : unavailable));
            parts.push("SINCRONIZACIÓN" + nl + (sync || unavailable));
            parts.push("GOBERNANZA" + nl + gov);
            parts.push("PERMISOS" + nl + (caps.ready === true ? (perms.length ? perms.join(", ") : "Solo lectura") : gov));
        } else {
            parts.push("RUTA" + nl + String(file.path));
        }
        detailText = parts.join(nl + nl);
        console.info("INGE_DOC_INFO_OPEN kind=" + (file.directory ? "folder" : "file") + " remote=" + (file.remote === true)
                     + " capsReady=" + (caps.ready === true));
        showDialog("details", "DETALLES");
    }
    Connections {
        target: files
        function onRenditionOpenRequested(renditionId) {
            root.renditionOpenRequested(renditionId)
        }
        function onCalicataOpenRequested(projectId, calicataId) {
            root.calicataOpenRequested(projectId, calicataId)
        }
        function onChanged() {
            if (root.pendingOpenDrive && !files.busy)
                root.openDriveRoot()
        }
        function onTextReady(content) {
            root.detailText = content;
            root.showDialog("text", root.currentFile.name || "LECTOR DE TEXTO");
        }
        function onCompleted(message, path) {
            root.toastText = message;
            toastTimer.restart();
            if (path && String(path).toLowerCase().endsWith(".zip")) {
                root.resultPath = path;
                root.detailText = "UBICACIÓN\n" + path;
                root.showDialog("done", "COMPLETADO");
            }
        }
    }
    Connections {
        target: Qt.application
        function onStateChanged() {
            if (Qt.application.state === Qt.ApplicationActive && !files.busy)
                files.refresh();
        }
    }
    Timer {
        id: toastTimer
        interval: 3500
        onTriggered: root.toastText = ""
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.bottomMargin: root.bottomSafeInset
        spacing: 0
        RowLayout {
            Layout.fillWidth: true
            Layout.leftMargin: root.home ? 24 : 8
            Layout.rightMargin: 8
            Layout.preferredHeight: root.home ? 80 : 64
            spacing: 0
            NothingButton {
                foreground: root.accent
                visible: !root.home
                glyph: files.selectedCount ? "close" : "arrow_back"
                Accessible.name: "Atrás"
                onClicked: root.handleBack()
            }
            Text {
                Layout.fillWidth: true
                elide: Text.ElideRight
                text: files.selectedCount ? files.selectedCount + " SELECCIONADOS" : root.home ? "INGE DRIVE" : files.route === "drive" ? "INGE DRIVE" : files.route === "trash" ? "PAPELERA" : files.route === "recents" ? "RECIENTES" : files.category || String(files.folder).split('/').pop().toUpperCase()
                font.family: root.flow.typography.family
                font.bold: true
                font.pixelSize: root.home ? 40 : 18
                color: root.ink
            }
            NothingButton {
                foreground: root.accent
                visible: root.home
                glyph: "settings"
                Accessible.name: "Ajustes de Documentos"
                onClicked: root.showDialog("settings", "AJUSTES")
            }
            NothingButton {
                foreground: root.accent
                visible: files.selectedCount > 0
                glyph: "select_all"
                Accessible.name: "Seleccionar todo"
                onClicked: files.selectAll()
            }
            NothingButton {
                foreground: root.accent
                visible: files.selectedCount > 0
                glyph: "more_vert"
                Accessible.name: "Acciones de selección"
                onClicked: selectionMenu.popup()
            }
            NothingButton {
                foreground: root.accent
                visible: !root.home && !files.selectedCount
                glyph: files.grid ? "list" : "grid_view"
                Accessible.name: "Cambiar vista"
                onClicked: files.grid = !files.grid
            }
            NothingButton {
                foreground: root.accent
                visible: !root.home && !files.selectedCount && !root.contextEnabled
                glyph: "sort"
                Accessible.name: "Ordenar"
                onClicked: sortMenu.popup()
            }
            NothingButton {
                foreground: root.accent
                visible: files.route === "trash" && !files.selectedCount
                glyph: "delete_sweep"
                Accessible.name: "Vaciar papelera"
                onClicked: root.showDialog("emptyTrash", "VACIAR PAPELERA")
            }
        }
        Rectangle {
            Layout.fillWidth: true
            Layout.leftMargin: 20
            Layout.rightMargin: 20
            Layout.preferredHeight: errorColumn.implicitHeight + 24
            radius: 20
            color: root.surface
            visible: files.error.length > 0
            Column {
                id: errorColumn
                x: 12
                y: 12
                width: parent.width - 24
                spacing: 6
                Text {
                    width: parent.width
                    text: files.error
                    color: (root.dark ? root.flow.theme.surfaceElevated : root.flow.theme.accent)
                    wrapMode: Text.Wrap
                    font.pixelSize: 13
                }
                Row {
                    NothingButton {
                        foreground: root.accent
                        text: "REINTENTAR"
                        enabled: !files.busy
                        onClicked: files.refresh()
                    }
                    NothingButton {
                        foreground: root.accent
                        text: "PERMISO"
                        visible: false
                        onClicked: files.requestStorageAccess()
                    }
                }
            }
        }
        RowLayout {
            visible: files.pendingSync > 0
            Layout.fillWidth: true
            Layout.leftMargin: 24
            Text { text: files.pendingSync + " cambio pendiente de sincronizar"; color: root.ink; Layout.fillWidth: true }
            NothingButton { foreground: root.accent; text: "REINTENTAR"; enabled: !files.busy; onClicked: files.retrySync() }
            NothingButton { foreground: root.accent; text: "CONSERVAR REMOTO"; enabled: !files.busy; onClicked: files.keepServerVersion() }
        }
        TextField {
            id: search
            visible: !root.home
            Layout.fillWidth: true
            Layout.margins: 16
            Layout.leftMargin: 24
            Layout.rightMargin: 24
            implicitHeight: 50
            leftPadding: 44
            rightPadding: 36
            color: root.ink
            text: files.query
            placeholderText: files.route === "drive" ? "BUSCAR NOMBRE O CONTENIDO..." : "BUSCAR..."
            placeholderTextColor: root.muted
            font.pixelSize: 13
            selectByMouse: true
            onTextEdited: files.query = text
            background: Rectangle { color: root.surface; border.width: 1; border.color: "#D1D5DB" }
            NothingIcon {
                ink: root.accent
                x: 14
                anchors.verticalCenter: parent.verticalCenter
                name: "search"
                size: 20
            }
            NothingButton {
                foreground: root.accent
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                glyph: "close"
                visible: search.text.length > 0
                onClicked: files.query = ""
            }
        }
        RowLayout {
            visible: files.clipboardCount > 0
            Layout.fillWidth: true
            Layout.leftMargin: 24
            Layout.rightMargin: 16
            Text {
                Layout.fillWidth: true
                text: files.clipboardCount + " en portapapeles"
                color: root.ink
                font.pixelSize: 12
            }
            NothingButton {
                foreground: root.accent
                text: "PEGAR"
                enabled: files.route === "drive" && !files.busy
                onClicked: {
                    root.beginDriveOperation(root.clipboardCutV600 ? "Moviendo…" : "Copiando…")
                    files.paste()
                }
            }
            NothingButton {
                foreground: root.accent
                glyph: "close"
                onClicked: files.cancelClipboard()
            }
        }
        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true
            Column {
                anchors.fill: parent
                anchors.margins: 16
                spacing: 12
                visible: root.home
                Text { text: "Documentos"; color: root.ink; font.pixelSize: 18; font.bold: true }
                Button { width: parent.width; text: "InGeDrive"; onClicked: files.navigate("drive") }
                Button { width: parent.width; text: "Recientes"; onClicked: files.navigate("recents") }
                Button { width: parent.width; text: "Papelera"; onClicked: files.navigate("trash") }
                Text { text: files.busy ? "Cargando..." : ""; color: root.ink }
            }
            ListView {
                id: list
                anchors.fill: parent
                visible: !root.home && !files.grid
                model: files
                clip: true
                bottomMargin: 90
                boundsBehavior: Flickable.StopAtBounds
                cacheBuffer: 200
                delegate: NothingEntry {
                    width: list.width - 32
                    x: 16
                    controller: files
                    heldPath: root.heldPath
                    onLongPressed: file => root.longPress(file, list)
                    ink: root.ink
                    surface: root.surface
                    accent: root.accent
                    muted: root.muted
                    onActivated: file => root.activate(file)
                    onMenuRequested: file => root.fileMenu(file)
                }
                footer: NothingButton {
                    foreground: root.accent
                    visible: files.moreRemote
                    text: "CARGAR MÁS"
                    enabled: !files.busy
                    onClicked: files.loadMore()
                }
            }
            GridView {
                id: grid
                anchors.fill: parent
                anchors.margins: 16
                visible: !root.home && files.grid
                model: files
                clip: true
                bottomMargin: 90
                cellWidth: width / Math.max(1, Math.floor(width / 126))
                cellHeight: 158
                cacheBuffer: 200
                boundsBehavior: Flickable.StopAtBounds
                delegate: NothingEntry {
                    width: grid.cellWidth
                    grid: true
                    controller: files
                    heldPath: root.heldPath
                    onLongPressed: file => root.longPress(file, grid)
                    ink: root.ink
                    surface: root.surface
                    accent: root.accent
                    muted: root.muted
                    onActivated: file => root.activate(file)
                    onMenuRequested: file => root.fileMenu(file)
                }
                footer: NothingButton {
                    foreground: root.accent
                    visible: files.moreRemote
                    text: "CARGAR MÁS"
                    enabled: !files.busy
                    onClicked: files.loadMore()
                }
            }
            Column {
                anchors.centerIn: parent
                visible: !root.home && !files.busy && files.count === 0 && !files.error.length
                spacing: 16
                NothingIcon {
                    anchors.horizontalCenter: parent.horizontalCenter
                    name: "folder_open"
                    size: 64
                    ink: root.muted
                }
                Text {
                    text: "NO SE ENCONTRARON ARCHIVOS"
                    color: root.muted
                    font.family: root.flow.typography.family
                    font.pixelSize: 11
                }
            }
            NothingButton {
                foreground: root.accent
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                anchors.margins: 24
                width: 56
                height: 56
                glyph: "add"
                filled: true
                visible: files.route === "files" && !files.selectedCount
                enabled: !files.busy
                Accessible.name: "Crear carpeta o archivo"
                onClicked: {
                    root.createFolder = true;
                    root.showDialog("create", "CREAR");
                }
            }
            // ===== Estados de carga (sin reemplazar contenido existente) =====
            // Primera carga: skeleton estático con un único pulso compartido.
            Text {
                anchors.centerIn: parent
                visible: root.firstLoadPending
                text: "Cargando documentos..."
                color: root.ink
            }

            // Recarga con contenido: el contenido se queda; barra fina + guard.
            MouseArea {
                anchors.fill: parent
                enabled: files.busy && !root.firstLoadPending
                visible: enabled
                preventStealing: true
            }
            Text {
                anchors.top: parent.top
                anchors.horizontalCenter: parent.horizontalCenter
                visible: files.busy && !root.firstLoadPending
                text: "Procesando..."
                color: root.ink
            }

        }
    }
    // Semantic dock context for the current documents state.
    FlowCore.ContextPublisher {
        ownerId: "documents"
        active: root.contextEnabled
        contextId: "documents/" + (files.selectedCount > 0 ? "selection" : root.home ? "home" : "folder")
        actions: files.selectedCount > 0 ? [
            { id: "back", label: "Atrás", icon: "nav.back", command: "documents.back", priority: 10, enabled: !files.busy },
            { id: "selectAll", label: "Seleccionar todo", icon: "action.check", command: "documents.selectAll", priority: 20, enabled: !files.busy },
            { id: "selectionMenu", label: "Acciones", icon: "action.more", command: "documents.selectionMenu", priority: 30, enabled: !files.busy }
        ] : root.home ? [
            { id: "drive", label: "InGe Drive", icon: "nav.documents", command: "documents.drive", priority: 10, enabled: !files.busy },
            { id: "recents", label: "Recientes", icon: "nav.documents", command: "documents.recents", priority: 20, enabled: !files.busy },
            { id: "settings", label: "Ajustes", icon: "nav.settings", command: "documents.settings", priority: 30, enabled: !files.busy }
        ] : [
            { id: "back", label: "Atrás", icon: "nav.back", command: "documents.back", priority: 10, enabled: !files.busy },
            { id: "folders", label: "Carpetas", icon: "nav.documents", command: "documents.folders", priority: 20, enabled: !files.busy },
            { id: "view", label: "Cambiar vista", icon: "map.layers", command: "documents.view", priority: 30, enabled: !files.busy, selected: files.grid },
            { id: "more", label: "Más acciones", icon: "action.more", command: "", priority: 40, enabled: !files.busy,
              children: root.dockMoreActions() }
        ]
        onCommand: function(commandId) {
            if (commandId === "documents.back") root.handleBack()
            else if (commandId === "documents.selectAll") files.selectAll()
            else if (commandId === "documents.selectionMenu") selectionMenu.popup()
            else if (commandId === "documents.settings") root.showDialog("settings", "AJUSTES")
            else if (commandId === "documents.view") files.grid = !files.grid
            else if (commandId === "documents.drive" && files.route !== "drive") files.navigate("drive")
            else if (commandId === "documents.recents" && files.route !== "recents") files.navigate("recents")
            else if (commandId === "documents.folders" && files.route !== "home") files.navigate("home")
            else if (commandId === "documents.folderNew") root.openNewFolder()
            else if (commandId.indexOf("documents.current:") === 0) root.runItemAction(commandId.slice(18), files.currentFolderEntry())
            else if (commandId.indexOf("documents.sort:") === 0) files.sortOrder = commandId.slice(15)
        }
    }
    Menu {
        id: sortMenu
        palette.window: root.surface
        palette.text: root.ink
        Repeater {
            model: [
                {
                    name: "POR NOMBRE",
                    key: "name"
                },
                {
                    name: "POR FECHA",
                    key: "date"
                },
                {
                    name: "POR TAMAÑO",
                    key: "size"
                }
            ]
            MenuItem {
                required property var modelData
                text: modelData.name
                font.family: root.flow.typography.family
                onTriggered: files.sortOrder = modelData.key
            }
        }
    }
    Menu {
        id: selectionMenu
        palette.window: root.surface
        palette.text: root.ink
        MenuItem {
            text: "COPIAR"
            enabled: files.route !== "trash"
            onTriggered: root.rememberClipboardV600(files.selection(), false)
        }
        MenuItem {
            text: "CORTAR"
            enabled: files.route !== "trash"
            onTriggered: root.rememberClipboardV600(files.selection(), true)
        }
        MenuItem {
            text: "RESTAURAR"
            visible: files.route === "trash"
            height: visible ? implicitHeight : 0
            onTriggered: files.restore(files.selection())
        }
        MenuItem {
            text: files.route === "trash" ? "ELIMINAR DEFINITIVAMENTE" : "MOVER A PAPELERA"
            onTriggered: root.confirmDelete(files.selection(), files.route === "trash")
        }
    }
    Menu {
        id: actionMenu
        onAboutToShow: {
            console.info("INGE_DOC_CONTEXT_OPEN kind=" + (root.currentFile.directory ? "folder" : "file") + " remote=" + (root.currentFile.remote === true));
            if (root.currentFile.remote && root.currentFile.path !== files.currentFolderPath)
                files.requestCapabilities(root.currentFile.path);
        }
        onClosed: {
            root.heldPath = "";
            console.info("INGE_DOC_CONTEXT_CLOSE");
        }
        background: Rectangle { color: root.surface; border.width: 1; border.color: "#D1D5DB" }
        width: 230
        palette.window: root.surface
        palette.text: root.ink
        Repeater {
            model: root.itemActions(root.currentFile)
            MenuItem {
                id: fileAction
                required property var modelData
                contentItem: Row {
                    spacing: 12
                    NothingIcon {
                        ink: root.accent
                        size: 18
                        name: fileAction.modelData.glyph
                    }
                    Text {
                        text: fileAction.modelData.label
                        color: !fileAction.enabled ? root.muted : fileAction.modelData.destructive ? root.danger : root.ink
                        font.family: root.flow.typography.family
                        font.pixelSize: 10
                    }
                }
                text: modelData.label
                font.family: root.flow.typography.family
                font.pixelSize: 11
                enabled: fileAction.modelData.enabled === true
                onTriggered: root.runItemAction(fileAction.modelData.id, root.currentFile)
            }
        }
    }
    Popup {
        id: popup
        parent: root
        modal: true
        focus: true
        width: Math.min(root.width - 32, 480)
        height: Math.min(root.height - 32, dialogColumn.implicitHeight + 48)
        x: (root.width - width) / 2
        y: Math.max(16, (root.height - height) / 2)
        padding: 24
        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
        background: Rectangle { color: root.surface; border.width: 1; border.color: "#D1D5DB" }
        Overlay.modal: Rectangle {
            color: root.flow.theme.scrim
        }
        contentItem: Flickable {
            contentWidth: width
            contentHeight: dialogColumn.implicitHeight
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            ColumnLayout {
                id: dialogColumn
                width: parent.width
                spacing: 16
                Text {
                    Layout.fillWidth: true
                    text: root.dialogTitle
                    color: root.ink
                    font.family: root.flow.typography.family
                    font.bold: true
                    font.pixelSize: 20
                    wrapMode: Text.Wrap
                }
                Row {
                    visible: root.dialogKind === "create"
                    spacing: 8
                    NothingButton {
                        foreground: root.accent
                        text: "CARPETA"
                        filled: root.createFolder
                        onClicked: root.createFolder = true
                    }
                    NothingButton {
                        foreground: root.accent
                        text: "ARCHIVO"
                        filled: !root.createFolder
                        onClicked: root.createFolder = false
                    }
                }
                // Destino canónico (Files Core): la última carpeta de InGe Drive abierta.
                Text {
                    Layout.fillWidth: true
                    visible: root.dialogKind === "upload"
                    text: files.uploadTargetLabel.length ? "Destino: " + files.uploadTargetLabel
                                                         : "Abre en InGe Drive la carpeta de destino y vuelve a intentarlo."
                    color: files.uploadTargetLabel.length ? root.ink : root.muted
                    font.family: root.flow.typography.family
                    font.pixelSize: 11
                    wrapMode: Text.WordWrap
                }
                TextField {
                    id: input
                    Layout.fillWidth: true
                    visible: ["create", "rename", "upload"].indexOf(root.dialogKind) >= 0
                    placeholderText: root.dialogKind === "upload" ? "Nombre del archivo" : "Nombre"
                    color: root.ink
                    selectByMouse: true
                    background: Rectangle {
                        radius: 16
                        color: root.color
                        border.color: root.muted
                    }
                }
                Text {
                    Layout.fillWidth: true
                    visible: ["delete", "permanent", "emptyTrash"].indexOf(root.dialogKind) >= 0
                    text: root.dialogKind === "delete" ? "Se moverán a la papelera los elementos seleccionados. Si hay carpetas, también se ocultará todo su contenido hasta restaurarlas. ¿Deseas continuar?" : "Esta acción elimina los archivos definitivamente. No se puede deshacer."
                    color: root.ink
                    wrapMode: Text.Wrap
                    font.pixelSize: 14
                }
                Text {
                    Layout.fillWidth: true
                    visible: ["details", "text", "done"].indexOf(root.dialogKind) >= 0
                    text: root.detailText
                    textFormat: Text.PlainText
                    wrapMode: Text.WrapAnywhere
                    color: root.muted
                    font.pixelSize: 13
                }
                ColumnLayout {
                    visible: root.dialogKind === "settings"
                    Layout.fillWidth: true
                    spacing: 16
                    Text {
                        text: "TEMA"
                        color: (root.dark ? root.flow.theme.surfaceElevated : root.flow.theme.accent)
                        font.family: root.flow.typography.family
                        font.pixelSize: 10
                    }
                    RowLayout {
                        Layout.fillWidth: true
                        Repeater {
                            model: [
                                {
                                    label: "SISTEMA",
                                    key: "system"
                                },
                                {
                                    label: "CLARO",
                                    key: "light"
                                },
                                {
                                    label: "OSCURO",
                                    key: "dark"
                                }
                            ]
                            NothingButton {
                                foreground: root.accent
                                required property var modelData
                                text: modelData.label
                                filled: files.theme === modelData.key
                                onClicked: files.theme = modelData.key
                                Layout.fillWidth: true
                            }
                        }
                    }
                    Switch {
                        visible: root.dark
                        text: "EXTRA DARK (OLED)"
                        checked: files.oled
                        onToggled: files.oled = checked
                        palette.windowText: root.ink
                        palette.highlight: (root.dark ? root.flow.theme.surfaceElevated : root.flow.theme.accent)
                    }
                }
                ColumnLayout {
                    visible: root.dialogKind === "analysis"
                    Layout.fillWidth: true
                    spacing: 20
                    Repeater {
                        model: [
                            {
                                name: "ARCHIVOS BASURA",
                                key: "junk"
                            },
                            {
                                name: "ARCHIVOS GRANDES",
                                key: "large"
                            },
                            {
                                name: "DUPLICADOS",
                                key: "duplicates"
                            },
                            {
                                name: "DESCARGAS ANTIGUAS",
                                key: "oldDownloads"
                            },
                            {
                                name: "CAPTURAS DE PANTALLA",
                                key: "screenshots"
                            }
                        ]
                        ColumnLayout {
                            required property var modelData
                            property var items: files.stats[modelData.key] || []
                            Layout.fillWidth: true
                            spacing: 4
                            RowLayout {
                                Layout.fillWidth: true
                                Text {
                                    Layout.fillWidth: true
                                    text: modelData.name
                                    color: (root.dark ? root.flow.theme.surfaceElevated : root.flow.theme.accent)
                                    font.family: root.flow.typography.family
                                    font.pixelSize: 10
                                    wrapMode: Text.Wrap
                                }
                                NothingButton {
                                    foreground: root.accent
                                    text: "LIMPIAR"
                                    visible: items.length > 0
                                    onClicked: {
                                        var paths = [];
                                        for (var i = 0; i < items.length; i++)
                                            paths.push(items[i].path);
                                        root.confirmDelete(paths, false);
                                    }
                                }
                            }
                            Text {
                                Layout.fillWidth: true
                                text: items.length ? items.slice(0, 3).map(function (f) {
                                    return f.name;
                                }).join("\n") + (items.length > 3 ? "\n...Y " + (items.length - 3) + " MÁS" : "") : "SIN ARCHIVOS PARA LIMPIAR"
                                color: root.muted
                                font.pixelSize: 12
                                wrapMode: Text.Wrap
                            }
                        }
                    }
                    Text {
                        Layout.fillWidth: true
                        visible: files.stats.duplicateLimit === true
                        text: "Búsqueda de duplicados limitada a 512 MB de lectura por análisis."
                        color: root.muted
                        font.pixelSize: 11
                        wrapMode: Text.Wrap
                    }
                }
                RowLayout {
                    Layout.fillWidth: true
                    NothingButton {
                        foreground: root.accent
                        text: "CERRAR"
                        onClicked: popup.close()
                    }
                    Item {
                        Layout.fillWidth: true
                    }
                    NothingButton {
                        foreground: root.accent
                        visible: ["create", "rename", "upload", "delete", "permanent", "emptyTrash", "done"].indexOf(root.dialogKind) >= 0
                        text: root.dialogKind === "done" ? "COMPARTIR" : "CONFIRMAR"
                        filled: true
                        enabled: !files.busy && (["create", "rename", "upload"].indexOf(root.dialogKind) < 0 || input.text.trim().length > 0) && (root.dialogKind !== "upload" || files.uploadTargetLabel.length > 0)
                        onClicked: {
                            var kind = root.dialogKind;
                            popup.close();
                            if (kind === "create")
                                files.create(input.text, root.createFolder);
                            else if (kind === "rename")
                                files.rename(root.currentFile.path, input.text);
                            else if (kind === "upload") {
                                root.beginDriveOperation("Subiendo…");
                                files.upload(root.currentFile.path, "", input.text);
                            } else if (kind === "delete") {
                                root.beginDriveOperation("Eliminando…");
                                files.trash(root.pendingPaths);
                            } else if (kind === "permanent") {
                                root.beginDriveOperation("Eliminando…");
                                files.removeForever(root.pendingPaths);
                            } else if (kind === "emptyTrash") {
                                root.beginDriveOperation("Eliminando…");
                                files.emptyTrash();
                            }
                            else if (kind === "done")
                                files.open({
                                    path: root.resultPath,
                                    directory: false,
                                    remote: false
                                }, false, true);
                        }
                    }
                }
            }
        }
    }
    Rectangle {
        visible: root.toastText.length > 0
        anchors.bottom: parent.bottom
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottomMargin: 16
        width: Math.min(parent.width - 32, 360)
        height: toastLabel.implicitHeight + 24
        radius: 20
        color: root.surface
        border.color: (root.dark ? root.flow.theme.surfaceElevated : root.flow.theme.accent)
        Text {
            id: toastLabel
            anchors.centerIn: parent
            width: parent.width - 24
            text: root.toastText
            color: root.ink
            wrapMode: Text.Wrap
            font.pixelSize: 13
        }
    }

    Pages.CalicataOperationOverlay {
        id: driveOperationOverlay
        z: 2000
        operation: root.driveOperation
        pageColor: root.color
        surfaceColor: root.dark ? root.flow.colors.ingemaNavy : root.flow.theme.surfaceElevated
        textColor: root.ink
        mutedColor: root.muted
        accentColor: root.accent
        borderColor: root.dark ? Qt.rgba(1, 1, 1, 0.16) : root.flow.theme.border
    }
}

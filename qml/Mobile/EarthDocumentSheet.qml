pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Dialogs
import InGe.Mobile as Backend

// Earth adapter: all local/account paths, Files Core reservations and mirrors
// are provided by the existing NothingDocuments controller.
Column {
    id: root
    property var controller
    property string exportedPath: ""
    property string pendingImport: ""
    property bool initialized: false
    property string operationMessage: ""
    spacing: 8
    Backend.NothingDocuments { id: files }
    property string pendingIntent: ""
    function initialize() {
        if (initialized || files.busy || !files.rootPath.length) return
        initialized = true
        files.navigate("files", files.rootPath)
    }
    // Accesos del menú "···" del Dock (InGe Earth UX 5.0), sobre los mismos flujos:
    //  import = selector del sistema (dispositivo / Google Drive)
    //  drive  = abrir KML/KMZ desde InGeDrive
    //  save   = elegir carpeta de InGeDrive para Guardar + Subir
    //  export = guardar KML/KMZ en los documentos locales de la cuenta
    function applyIntent(intent) {
        if (intent === "import") { picker.open(); return }
        if (intent !== "drive" && intent !== "save" && intent !== "export") return
        if (files.busy) { pendingIntent = intent; return }
        pendingIntent = ""
        if (intent === "export") {
            if (initialized && files.rootPath.length) files.navigate("files", files.rootPath)
            else initialize()
            operationMessage = "Escribe el nombre, elige KML o KMZ y pulsa Guardar en documentos de esta cuenta."
            return
        }
        initialized = true                      // la raíz local no sustituye a InGeDrive
        files.navigate("drive")
        operationMessage = intent === "save"
            ? "Abre el espacio y la carpeta de destino de InGeDrive; después Guardar y Subir."
            : "Elige un KML o KMZ de InGeDrive para abrirlo en el planeta."
    }
    Component.onCompleted: initialize()
    Connections {
        target: files
        function onChanged() {
            root.initialize()
            if (!files.busy && files.error.length) root.pendingImport = ""
            if (!files.busy && root.pendingIntent.length) root.applyIntent(root.pendingIntent)
        }
        function onCompleted(message, path) {
            root.operationMessage = message
            if (root.pendingImport.length && path.length) {
                root.pendingImport = ""
                root.controller.importDocument(path)
            }
        }
    }
    FileDialog {
        id: picker
        title: "Abrir KML / KMZ desde dispositivo o Drive"
        fileMode: FileDialog.OpenFile
        nameFilters: ["Geografia (*.kml *.kmz)", "Todos los archivos (*)"]
        onAccepted: root.controller.importDocument(selectedFile.toString())
    }
    Row {
        spacing: 6
        Button { text: "Dispositivo"; enabled: !files.busy; onClicked: files.navigate("files",files.rootPath) }
        Button { text: "InGeDrive"; enabled: !files.busy; onClicked: files.navigate("drive") }
    }
    Button { width: parent.width; text: "Abrir archivo / Google Drive"; onClicked: picker.open() }
    Text {
        width: parent.width
        text: { var location = files.location; return files.breadcrumb() }
        color: "#344A62"; wrapMode: Text.WordWrap
    }
    Row {
        spacing: 6
        Button { text: "Carpeta anterior"; enabled: !files.busy; onClicked: files.back() }
        Button { text: "Actualizar"; enabled: !files.busy; onClicked: files.refresh() }
    }
    BusyIndicator { running: files.busy; visible: running; height: 28; width: 28 }
    // The parent sheet scrolls; this list keeps a bounded viewport and can page remotely.
    ListView {
        width: parent.width; height: 160; clip: true; model: files
        delegate: ItemDelegate {
            required property var entry
            width: ListView.view.width
            text: (entry.directory || entry.kind === "SPACE" || entry.kind === "FOLDER" ? "[Carpeta] " : "") + entry.name
            enabled: !files.busy && (entry.directory || entry.kind === "SPACE" || entry.kind === "FOLDER" || /\.(kml|kmz)$/i.test(entry.name))
            onClicked: {
                if (entry.remote && entry.directory) files.navigate("drive",entry.path)
                else if (entry.directory) files.navigate("files",entry.path)
                else if (entry.remote) { root.pendingImport = entry.path; files.download(entry) }
                else root.controller.importDocument(entry.path)
            }
        }
    }
    Button { text: "Mas archivos"; visible: files.moreRemote; enabled: !files.busy; onClicked: files.loadMore() }
    TextField { id: filename; width: parent.width; placeholderText: "Nombre para guardar"; text: "InGe Earth" }
    CheckBox { id: zipped; text: "Guardar KMZ (doc.kml comprimido)" }
    Button {
        width: parent.width; text: "Guardar en documentos de esta cuenta"; enabled: !files.busy && files.rootPath.length > 0
        onClicked: {
            var folder = files.route === "files" ? files.folder : files.rootPath
            root.exportedPath = root.controller.exportDocument(folder,filename.text,zipped.checked)
            if (root.exportedPath.length && files.route === "files") files.refresh()
        }
    }
    Button {
        width: parent.width; text: "Subir a " + (files.uploadTargetLabel || "InGeDrive")
        enabled: !files.busy && root.exportedPath.length > 0 && files.uploadTargetLabel.length > 0
        onClicked: files.upload(root.exportedPath,"",root.exportedPath.split(/[\\/]/).pop())
    }
    Button {
        width: parent.width; text: "Compartir / Guardar en Google Drive"; enabled: root.exportedPath.length > 0 && !files.busy
        onClicked: files.open({path:root.exportedPath,remote:false},false,true)
    }
    Text { width: parent.width; text: "Para subir, abre primero el espacio y carpeta de destino de InGeDrive. Google Drive aparece en el selector o al compartir si esta instalado y conectado."; color: "#344A62"; wrapMode: Text.WordWrap; font.pixelSize: 12 }
    Text { width: parent.width; visible: files.error.length > 0; text: files.error; color: "#A52D35"; wrapMode: Text.WordWrap }
    Text { width: parent.width; text: root.operationMessage; color: "#344A62"; wrapMode: Text.WordWrap }
    Text { width: parent.width; text: root.controller ? root.controller.documentMessage : ""; color: "#344A62"; wrapMode: Text.WordWrap }
}

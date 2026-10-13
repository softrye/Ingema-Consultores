import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15
import Qt.labs.folderlistmodel 2.15
import QtCore   // ✅ reemplaza Qt.labs.settings
// (si QtCreator te pide versión: import QtCore 6.5)
import InGe.CoreFlow 3.0 as Mobile
import "flowcore" as FlowCore

Dialog {
    id: dlg
    parent: Overlay.overlay
    modal: true
    focus: true
    closePolicy: Popup.NoAutoClose

    // ✅ padding real del Dialog (evita “tapado” arriba)
    padding: 12

    width:  Math.min(parent ? parent.width  * 0.92 : 520, 560)
    height: Math.min(parent ? parent.height * 0.82 : 720, 720)

    x: parent ? Math.round((parent.width  - width)  / 2) : 0
    y: parent ? Math.round((parent.height - height) / 2) : 0

    // "save" | "open"
    property string mode: "save"

    // root ABSOLUTO ya scopeado (ej: .../Usuario_nouid)
    property string rootPath: ""

    // carpeta inicial sugerida (ej: root/Proyecto_Local/Calicata/Edit)
    property string initialDir: ""

    // sugerencia nombre archivo (sin extensión también vale)
    property string defaultFileName: "calicata"

    // filtro en open
    property var openNameFilters: ["*.calicata.json"]

    // outputs
    property string selectedDir: ""
    property string selectedFile: ""

    signal acceptedSave(string folderAbs, string fileName)
    signal acceptedOpen(string fileAbs)
    signal canceled()

    readonly property var dialogFlow: Mobile.InGeCoreFlow

    enter: Transition {
        ParallelAnimation {
            NumberAnimation { property: "opacity"; from: 0.0; to: 1.0; duration: dialogFlow.dialogDuration; easing.type: dialogFlow.easeOut }
            NumberAnimation { property: "scale"; from: dialogFlow.sheetStartScale; to: 1.0; duration: dialogFlow.dialogDuration; easing.type: dialogFlow.easeOvershoot }
        }
    }
    exit: Transition {
        ParallelAnimation {
            NumberAnimation { property: "opacity"; from: 1.0; to: 0.0; duration: dialogFlow.normalDuration; easing.type: dialogFlow.easeIn }
            NumberAnimation { property: "scale"; from: 1.0; to: 0.985; duration: dialogFlow.normalDuration; easing.type: dialogFlow.easeIn }
        }
    }


    onCurrentDirChanged: _recalcSaveNameState()

    Connections {
        target: saveFilesModel
        function onCountChanged() { dlg._recalcSaveNameState() }
        function onFolderChanged() { dlg._recalcSaveNameState() }
    }

    Settings {
        id: st
        category: "CalicataSaveOpenDialog"
        property string lastDirSave: ""
        property string lastDirOpen: ""
    }

    // ===== helpers =====
    function _norm(p) {
        var s = (p || "").toString().trim()
        s = s.replace(/\\/g, "/").replace(/\/+/g, "/")
        // quita trailing "/" salvo raíz tipo "C:/" o "/"
        if (s.length > 1 && s.endsWith("/")) s = s.substring(0, s.length - 1)
        if (Qt.platform.os === "windows") s = s.toLowerCase()   // ✅ clave
        return s
    }

    function _rootClean() { return _norm(rootPath) }

    function _isUnderRoot(p) {
        var rp = _rootClean()
        var pp = _norm(p)
        if (!rp.length || !pp.length) return false
        var rpSlash = rp.endsWith("/") ? rp : (rp + "/")
        return (pp === rp) || pp.startsWith(rpSlash)
    }

    function _parentDir(p) {
        var s = _norm(p)
        var rp = _rootClean()
        if (!s.length) return rp
        if (s === rp) return rp
        var i = s.lastIndexOf("/")
        if (i <= 0) return rp
        var up = s.substring(0, i)
        return _isUnderRoot(up) ? up : rp
    }

    function _ensureExt(name) {
        var n = (name || "").trim()
        if (!n.length) return ""
        var low = n.toLowerCase()
        if (low.endsWith(".calicata.json")) return n
        if (low.endsWith(".json")) n = n.substring(0, n.length - 5)
        if (n.toLowerCase().endsWith(".calicata")) n = n.substring(0, n.length - 8)
        return n + ".calicata.json"
    }

    // ===== SAVE validation state =====
    property string _saveCandidateName: ""
    property string _saveCandidateAbs: ""
    property bool   _saveNameExists: false
    property string _saveNameError: ""
    property bool   _saveNameOk: false

    function _stemFromUserText(s) {
        var n = (s || "").toString().trim()
        // quita extensiones conocidas si el usuario las escribió
        n = n.replace(/\.calicata\.json$/i, "")
             .replace(/\.json$/i, "")
             .replace(/\.calicata$/i, "")
        return n.trim()
    }

    function _isWindowsReserved(stemUpper) {
        // CON, PRN, AUX, NUL, COM1..COM9, LPT1..LPT9
        if (!stemUpper || !stemUpper.length) return false
        if (stemUpper === "CON" || stemUpper === "PRN" || stemUpper === "AUX" || stemUpper === "NUL")
            return true
        if (/^COM[1-9]$/.test(stemUpper)) return true
        if (/^LPT[1-9]$/.test(stemUpper)) return true
        return false
    }

    function _fileExistsInCurrentDir(fileNameWithExt) {
        var want = (fileNameWithExt || "").toString()
        if (!want.length) return false
        if (Qt.platform.os === "windows") want = want.toLowerCase()

        for (var i = 0; i < saveFilesModel.count; ++i) {
            var fn = saveFilesModel.get(i, "fileName")   // ✅ role
            fn = (fn || "").toString()
            if (Qt.platform.os === "windows") fn = fn.toLowerCase()
            if (fn === want) return true
        }
        return false
    }

    function _recalcSaveNameState() {
        if (mode !== "save") {
            _saveCandidateName = ""
            _saveCandidateAbs = ""
            _saveNameExists = false
            _saveNameError = ""
            _saveNameOk = false
            return
        }

        var raw = fileNameField.text
        var stem = _stemFromUserText(raw)

        _saveNameError = ""
        _saveNameExists = false
        _saveCandidateName = ""
        _saveCandidateAbs = ""
        _saveNameOk = false

        if (!stem.length) {
            _saveNameError = "Escribe un nombre (ej: CT-17+000)."
            return
        }

        // inválidos Windows: <>:"/\|?* y control chars
        if (/[<>:"\/\\|?*\x00-\x1F]/.test(stem)) {
            _saveNameError = "El nombre contiene caracteres no permitidos: <>:\"/\\|?*"
            return
        }

        // no terminar con punto o espacio
        if (/[\. ]$/.test(stem)) {
            _saveNameError = "El nombre no puede terminar en punto o espacio."
            return
        }

        if (Qt.platform.os === "windows") {
            var up = stem.toUpperCase()
            if (_isWindowsReserved(up)) {
                _saveNameError = "Nombre reservado en Windows (CON, PRN, AUX, NUL, COM1.., LPT1..)."
                return
            }
        }

        var fn = _ensureExt(stem)   // => "CT-17+000.calicata.json"
        _saveCandidateName = fn

        // arma abs “bonito” (currentDir está normalizado sin trailing "/")
        var dirAbs = _norm(currentDir)
        _saveCandidateAbs = dirAbs.length ? (dirAbs + "/" + fn) : fn

        // ✅ existencia en carpeta
        _saveNameExists = _fileExistsInCurrentDir(fn)
        if (_saveNameExists) {
            _saveNameError = "Ya existe un archivo con ese nombre en esta carpeta."
            return
        }

        _saveNameOk = true
    }

    function _folderUrlFor(absDir) {
        var d = _norm(absDir)
        if (!d.length) d = _rootClean()
        if (!d.length) return ""

        // ✅ FolderListModel funciona mejor con trailing "/"
        if (!d.endsWith("/")) d += "/"

        var url = (Qt.platform.os === "windows") ? ("file:///" + d) : ("file://" + d)
        return encodeURI(url)
    }

    function _initOnOpen() {
        var rp = _rootClean()
        if (!rp.length) return

        var start = (mode === "save") ? st.lastDirSave : st.lastDirOpen
        if (!start || !_isUnderRoot(start)) {
            start = (initialDir && _isUnderRoot(initialDir)) ? initialDir : rp
        }
        if (!start.length) start = rp

        currentDir = _norm(start)
        selectedFile = ""
        selectedDir = currentDir

        if (mode === "save") {
            fileNameField.text = (defaultFileName || "calicata")
        }

        _recalcSaveNameState()
    }

    function _baseName(p) {
        var s = _norm(p)
        var i = s.lastIndexOf("/")
        return (i >= 0) ? s.substring(i+1) : s
    }

    function _prettyPath(abs) {
        var rp = _rootClean()
        var pp = _norm(abs)
        if (!rp.length) return pp

        var base = _baseName(rp)
        if (pp === rp) return base

        var rpSlash = rp.endsWith("/") ? rp : (rp + "/")
        if (pp.startsWith(rpSlash)) {
            return base + "/" + pp.substring(rpSlash.length)
        }
        return pp
    }

    title: (mode === "save") ? "Guardar ficha de calicata" : "Abrir ficha de calicata"

    onOpened: _initOnOpen()

    property string currentDir: ""

    FolderListModel {
        id: model
        folder: dlg._folderUrlFor(dlg.currentDir)
        showDirs: true
        showFiles: (dlg.mode === "open")
        showDotAndDotDot: false
        nameFilters: (dlg.mode === "open") ? dlg.openNameFilters : []
        sortField: FolderListModel.Name
    }

    // ✅ Solo para validar duplicados en SAVE (lista de archivos existentes)
    FolderListModel {
        id: saveFilesModel
        folder: dlg._folderUrlFor(dlg.currentDir)
        showDirs: false
        showFiles: true
        showDotAndDotDot: false
        nameFilters: ["*.calicata.json"]
        sortField: FolderListModel.Name
    }

    footer: DialogButtonBox {
        alignment: Qt.AlignRight

        Button {
            text: "Cancelar"
            onClicked: {
                if (dlg.mode === "save") st.lastDirSave = dlg.currentDir
                else st.lastDirOpen = dlg.currentDir
                dlg.close()
                dlg.canceled()
            }
        }

        Button {
            text: "OK"
            enabled: (dlg.mode === "save")
                     ? dlg._saveNameOk
                     : dlg.selectedFile.length > 0
            onClicked: {
                if (dlg.mode === "save") {
                    dlg._recalcSaveNameState()
                    if (!dlg._saveNameOk) return

                    st.lastDirSave = dlg.currentDir
                    dlg.acceptedSave(dlg.currentDir, dlg._saveCandidateName)
                    dlg.close()
                } else {
                    st.lastDirOpen = dlg.currentDir
                    dlg.acceptedOpen(dlg.selectedFile)
                    dlg.close()
                }
            }
        }
    }

    contentItem: ColumnLayout {
        spacing: 10

        Label {
            Layout.fillWidth: true
            wrapMode: Text.WordWrap
            text: (dlg.mode === "save")
                  ? "Selecciona la carpeta donde guardar la ficha y escribe el nombre del archivo:"
                  : "Selecciona una ficha .calicata.json y presiona OK."
        }

        // (solo SAVE) Nombre arriba
        RowLayout {
            Layout.fillWidth: true
            visible: (dlg.mode === "save")
            spacing: 10

            Label { text: "Nombre:" }

            TextField {
                id: fileNameField
                Layout.fillWidth: true
                placeholderText: "Ej: CT-X+XXX"
                onTextChanged: dlg._recalcSaveNameState()
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            visible: (dlg.mode === "save")
            spacing: 4

            Label {
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                color: "#4B5A73"
                text: dlg._saveCandidateName.length
                      ? ("Se guardará como: " + dlg._saveCandidateName)
                      : ""
            }

            Label {
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                visible: dlg._saveNameError.length > 0
                color: "#B00020"
                text: dlg._saveNameError
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            Button {
                text: "⬅"
                enabled: dlg._norm(dlg.currentDir) !== dlg._rootClean()
                onClicked: {
                    var up = dlg._parentDir(dlg.currentDir)
                    dlg.currentDir = up
                    dlg.selectedFile = ""
                    dlg.selectedDir = dlg.currentDir
                }
            }

            Label {
                Layout.fillWidth: true
                elide: Text.ElideMiddle
                text: dlg._prettyPath(dlg.currentDir)
            }
        }

        Frame {
            Layout.fillWidth: true
            Layout.fillHeight: true

            ListView {
                id: lv
                anchors.fill: parent
                clip: true
                model: model

                delegate: ItemDelegate {
                    width: lv.width
                    highlighted: (dlg.mode === "open" && !fileIsDir && (filePath === dlg.selectedFile))

                    contentItem: RowLayout {
                        spacing: 10
                        Label { text: fileIsDir ? "📁" : "📄" }
                        Label {
                            Layout.fillWidth: true
                            text: fileName
                            elide: Text.ElideRight
                        }
                    }

                    onClicked: {
                        if (fileIsDir) {
                            // ✅ navegar a carpeta
                            dlg.currentDir = dlg._norm(filePath)
                            dlg.selectedFile = ""
                            dlg.selectedDir = dlg.currentDir
                        } else if (dlg.mode === "open") {
                            dlg.selectedFile = filePath
                        }
                    }
                }
            }
        }
    }
}

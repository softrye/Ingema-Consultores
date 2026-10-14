import QtQuick
import QtQuick.Controls
import "RStyle.js" as S

// Subapp Rendiciones (QML nativo, misma APK). Arquitectura:
// HomeScreen -> RenditionsApp -> RenditionsUi (C++) -> RenditionFlutterBridge
// -> Repository / LocalStore / SyncController -> Supabase.
// Toda acción usa un comando real del bridge, correlacionado por requestId.
Item {
    id: shell
    property var ui
    property var ctl: null
    property bool active: false
    readonly property var st: ctl ? ctl.state : ({})
    readonly property string connection: String(st.connectionState || "UNKNOWN")
    readonly property string phase: String(st.syncPhase || "IDLE")
    readonly property int pendingCount: Number(st.pendingCount || 0)
    property string bootError: ""
    property bool booted: false
    property var callbacks: ({})
    signal requestBack()

    // ------------------------------------------------------------ Comandos
    // done(ok, result, code, message). key = formulario/acción (anti doble toque).
    function call(operation, args, key, done) {
        if (!ctl) {
            toast("Rendiciones no está disponible en esta sesión.", "error")
            return ""
        }
        var id = ctl.send(operation, args || {}, key || "")
        if (!id.length) {
            if (key && ctl.isPending(key))
                return ""                       // pulsación repetida: se ignora
            toast("No se pudo enviar la solicitud a Rendiciones.", "error")
            return ""
        }
        if (done)
            callbacks[id] = done
        return id
    }
    function busy(key) { return !!ctl && ctl.pendingKeys.indexOf(key) >= 0 }
    function errorText(code, message) { return ctl ? ctl.errorText(code, message) : String(message || code) }

    function bootstrap() {
        bootError = ""
        call("bootstrap", {}, "bootstrap", function(ok, result, code, message) {
            shell.booted = true
            if (!ok) shell.bootError = shell.errorText(code, message)
        })
    }
    function refresh() {
        call("refresh", {}, "refresh", function(ok, result, code, message) {
            if (!ok) shell.toast(shell.errorText(code, message), "error")
        })
    }
    function synchronize() {
        call("sync", {}, "sync", function(ok, result, code, message) {
            if (ok) shell.toast("Sincronizado con el servidor.", "success")
            else shell.toast(shell.errorText(code, message), "error")
        })
    }

    // ---------------------------------------------------------- Navegación
    function openDetail(localId) {
        call("select", { localId: localId }, "select", function(ok, result, code, message) {
            if (!ok) { shell.toast(shell.errorText(code, message), "error"); return }
            stack.push(detailComponent, { localId: localId })
        })
    }
    function openCreate() { stack.push(editorComponent, { original: null }) }
    function openEditor(rendition) { stack.push(editorComponent, { original: rendition }) }
    function openCreated(localId) { stack.replace(detailComponent, { localId: localId }) }
    function openExpense(renditionLocalId, expenseLocalId) {
        stack.push(expenseComponent, { renditionLocalId: renditionLocalId, expenseLocalId: expenseLocalId || "" })
    }
    function openReceived(row) { stack.push(receivedComponent, { row: row }) }
    function closePage() { if (stack.depth > 1) stack.pop() }

    function handleBack() {
        if (confirmDialog.opened) { confirmDialog.close(); return true }
        if (stack.busy) return true
        var item = stack.currentItem
        if (item && item.handleBack !== undefined && item.handleBack()) return true
        if (stack.depth > 1) { stack.pop(); return true }
        return false
    }
    function confirm(title, message, label, destructive, callback) {
        confirmDialog.ask(title, message, label, destructive, callback)
    }

    // --------------------------------------------------------------- Avisos
    property string toastText: ""
    property string toastKind: "info"
    function toast(text, kind) {
        toastText = String(text || "")
        toastKind = kind || "info"
        toastTimer.restart()
    }
    Timer { id: toastTimer; interval: 4200; onTriggered: shell.toastText = "" }

    Connections {
        target: shell.ctl
        ignoreUnknownSignals: true
        function onFinished(requestId, operation, key, ok, result, code, message) {
            var done = shell.callbacks[requestId]
            if (done === undefined) return
            delete shell.callbacks[requestId]
            done(ok, result, code, message)
        }
        function onBridgeError(code, message) { shell.toast(shell.errorText(code, message), "error") }
        function onBridgeEvent(type, event) {
            if (type === "receivedReset") {            // cambio de cuenta
                shell.callbacks = ({})
                if (stack.depth > 1) stack.popToIndex(0, StackView.Immediate)
                shell.bootstrap()
            }
        }
    }

    onActiveChanged: if (active && booted && ctl && ctl.ready) refresh()
    Component.onCompleted: bootstrap()

    // ------------------------------------------------------------- Interfaz
    Rectangle { anchors.fill: parent; color: S.background; opacity: 0.97 }

    Item {
        id: header
        width: parent.width
        height: shell.ui.topInset + 64 * shell.ui.u
        Row {
            x: 8 * shell.ui.u
            y: shell.ui.topInset + 8 * shell.ui.u
            height: 48 * shell.ui.u
            spacing: 4 * shell.ui.u
            RButton {
                ui: shell.ui
                glyph: 0xE06E
                width: 48 * shell.ui.u
                color: "transparent"
                border.width: 0
                onActivated: if (!shell.handleBack()) shell.requestBack()
                Accessible.name: "Atrás"
            }
            Text {
                width: header.width - 190 * shell.ui.u
                anchors.verticalCenter: parent.verticalCenter
                text: stack.currentItem && stack.currentItem.title !== undefined ? stack.currentItem.title : "Rendiciones"
                color: S.text
                font.family: shell.ui.fontFamily
                font.pixelSize: 21 * shell.ui.u
                font.weight: Font.DemiBold
                elide: Text.ElideRight
            }
        }
        RButton {
            id: syncButton
            anchors.right: parent.right
            anchors.rightMargin: 12 * shell.ui.u
            y: shell.ui.topInset + 8 * shell.ui.u
            ui: shell.ui
            glyph: 0xE145
            busy: shell.busy("sync") || shell.phase === "PUSHING"
            label: shell.connection === "OFFLINE" ? "Sin conexión"
                 : shell.phase === "PULLING" ? "Actualizando"
                 : shell.phase === "PRESENTING" ? "Presentando"
                 : shell.pendingCount > 0 ? shell.pendingCount + " pendientes"
                 : shell.connection === "ONLINE" ? "Sincronizado" : "Sincronizar"
            onActivated: shell.synchronize()
            Accessible.name: "Sincronizar rendiciones"
        }
    }

    StackView {
        id: stack
        anchors.top: header.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.bottomMargin: Qt.inputMethod.visible ? 0 : shell.ui.dockArea
        clip: true
        initialItem: homeComponent
    }

    Component { id: homeComponent; RenditionsHome { app: shell } }
    Component { id: detailComponent; RenditionDetail { app: shell } }
    Component { id: editorComponent; RenditionEditor { app: shell } }
    Component { id: expenseComponent; ExpenseEditor { app: shell } }
    Component { id: receivedComponent; RenditionReceived { app: shell } }

    RConfirm { id: confirmDialog; objectName: "confirmDialog"; ui: shell.ui }

    Rectangle {
        visible: shell.toastText.length > 0
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: shell.ui.dockArea + 12 * shell.ui.u
        width: Math.min(parent.width - 32 * shell.ui.u, toastLabel.implicitWidth + 32 * shell.ui.u)
        height: toastLabel.implicitHeight + 24 * shell.ui.u
        radius: 14 * shell.ui.u
        color: "#1E2A48"
        border.width: 1
        border.color: shell.toastKind === "error" ? S.danger : shell.toastKind === "success" ? S.success : S.border
        z: 20
        Text {
            id: toastLabel
            anchors.centerIn: parent
            width: Math.min(implicitWidth, shell.width - 64 * shell.ui.u)
            text: shell.toastText
            color: S.text
            wrapMode: Text.WordWrap
            font.family: shell.ui.fontFamily
            font.pixelSize: 14 * shell.ui.u
        }
        MouseArea { anchors.fill: parent; onClicked: shell.toastText = "" }
    }
}

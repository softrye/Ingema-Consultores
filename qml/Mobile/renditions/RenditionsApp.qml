import QtQuick
import QtQuick.Controls
import QtQuick.Shapes
import "RStyle.js" as S
import "../flowcore" as FlowCore

// Subapp Rendiciones (QML nativo, misma APK). Arquitectura:
// HomeScreen -> RenditionsApp -> RenditionsUi (C++) -> RenditionFlutterBridge
// -> Repository / LocalStore / SyncController -> Supabase.
// Toda acción usa un comando real del bridge, correlacionado por requestId.
Item {
    id: shell
    property var ui
    property var ctl: null
    property bool active: false
    property bool navigationTransitionActive: false
    property bool dockMenuVisible: false
    readonly property var st: ctl ? ctl.state : ({})
    readonly property string connection: String(st.connectionState || "UNKNOWN")
    readonly property string phase: String(st.syncPhase || "IDLE")
    readonly property int pendingCount: Number(st.pendingCount || 0)
    property string bootError: ""
    property bool booted: false
    property var callbacks: ({})
    property var haptics: null                 // FlowHaptics (motor háptico existente), opcional
    property Item dockAnchor: null             // dock contextual global (HomeScreen), sólo para anclar paneles
    property var flow: null                    // motor único InGeCoreFlow (teclado/IME), opcional
    property var authSession: typeof auth !== "undefined" ? auth : null   // AuthSession real (renovar sesión)
    signal requestBack()
    signal requestOpenDrive()
    signal requestOpenProfile()

    function haptic(intent) {
        if (haptics && haptics.trigger) haptics.trigger(intent || "selection")
    }

    // Estado REAL para las auras. Fuente única: modelo CENTRALIZADO de
    // incidencias (RenditionsUi.diagnostics, C++) + RenditionConnectivity.
    // Prioridad: ROJO > AMARILLO > verde.
    //   offline   <- connectionState OFFLINE (sin red o servidor inaccesible con
    //                evidencia real). Rojo persistente sin avisos; sale sólo con
    //                una respuesta real del servidor.
    //   error     <- incidencia bloqueante (sesión expirada, conflicto real,
    //                rechazo/permiso del servidor, acción fallida vigente). Azul + rojo.
    //   attention <- incidencia localizada y corregible (gasto incompleto, sustento
    //                pendiente, observación, borrador sin bytes). Azul + amarillo.
    //   syncing   <- syncPhase PUSHING/PULLING/PRESENTING
    //   pending   <- operaciones locales aún no confirmadas por el servidor
    //   synced    <- ONLINE, sin pendientes y con un pull confirmado. Azul + verde.
    //   unknown   <- sin estado confirmado todavía
    readonly property var diagnostics: ctl && ctl.diagnostics ? ctl.diagnostics : ({})
    readonly property int incidentCount: Number(diagnostics.errors || 0) + Number(diagnostics.attention || 0)
    readonly property string syncMode: {
        if (!ctl || !ctl.ready) return "unknown"
        if (connection === "OFFLINE") return "offline"
        if (String(diagnostics.level || "") === "error") return "error"
        if (String(diagnostics.level || "") === "attention") return "attention"
        var rows = st.renditions || []
        var i, state
        if (phase !== "IDLE") return "syncing"
        if (pendingCount > 0) return "pending"
        for (i = 0; i < rows.length; ++i) {
            state = String(rows[i].syncState || "").toUpperCase()
            if (Number(rows[i].pendingCount || 0) > 0
                    || ["PENDING_CREATE", "PENDING_UPDATE", "LOCAL_ONLY", "SYNCING"].indexOf(state) >= 0)
                return "pending"
        }
        if (connection === "ONLINE" && String(st.lastPullAt || "").length) return "synced"
        return "unknown"
    }

    // Balance global: conteos del modelo publicado (alcance del usuario).
    // Métrica explícita: % = aprobadas / total de rendiciones propias.
    readonly property var balanceCounts: {
        var c = { total: 0, APROBADO: 0, EN_REVISION: 0, OBSERVADO: 0, BORRADOR: 0 }
        var rows = st.renditions || []
        for (var i = 0; i < rows.length; ++i) {
            if (rows[i].archived === true) continue
            var k = String(rows[i].status || "BORRADOR").toUpperCase()
            c.total++
            if (c[k] !== undefined) c[k]++
        }
        return c
    }

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
    // Punto ÚNICO de texto de error para toda la subapp. Pérdida de conexión,
    // timeouts y reintentos automáticos devuelven "": ningún toast, banner ni
    // recuadro; el estado lo comunica el aura (syncMode "offline"). Los errores
    // que requieren acción (conflicto real, permisos, validación) sí se muestran.
    function errorText(code, message) {
        if (ctl && ctl.silentError(String(code || ""))) return ""
        return ctl ? ctl.errorText(code, message) : String(message || code)
    }
    function syncState(row) { return ctl && row ? ctl.effectiveSyncState(row) : String(row && row.syncState || "") }

    function bootstrap() {
        bootError = ""
        call("bootstrap", {}, "bootstrap", function(ok, result, code, message) {
            shell.booted = true
            if (!ok) {
                shell.bootError = shell.errorText(code, message)
                // Sin recuadro en la lista: la falla se consulta en Estado de Rendiciones.
                if (shell.bootError.length) shell.reportProblem(shell.bootError, "Rendiciones · Inicio", "bootstrap")
            } else if (shell.ctl) {
                shell.ctl.resolveIssue("bootstrap")
            }
        })
    }
    function refresh() {
        call("refresh", {}, "refresh", function(ok, result, code, message) {
            if (!ok) shell.toast(shell.errorText(code, message), "error")
        })
    }
    // silent: deslizar para actualizar (sin aviso de éxito; los errores sí se
    // informan). done(ok) permite al llamador cerrar su indicador. Devuelve el
    // requestId, o "" si ya hay una sincronización en curso (no se duplica).
    function synchronize(silent, done) {
        return call("sync", {}, "sync", function(ok, result, code, message) {
            var alreadyRunning = code === "SYNC_BUSY" || code === "PULL_BUSY"
            if (!ok && !(silent === true && alreadyRunning)) shell.toast(shell.errorText(code, message), "error")
            else if (ok && silent !== true) shell.toast("Sincronizado con el servidor.", "success")
            if (done) done(ok)
        })
    }

    // ---------------------------------------------------------- Navegación
    function openDetail(localId) {
        call("select", { localId: localId }, "select", function(ok, result, code, message) {
            if (!ok) { shell.toast(shell.errorText(code, message), "error"); return }
            stack.push(detailComponent, { localId: localId, selectionToken: Number(result.selectionToken || 0) })
        })
    }
    // Nueva rendición: hoja contextual sobre la lista (misma lógica del editor).
    function openCreate() { closeMenus(); createSheet.open = true }
    function openEditor(rendition) { stack.push(editorComponent, { original: rendition }) }
    function openCreated(localId) {
        if (createSheet.open) {                     // creada desde la hoja: abrir su ficha
            createSheet.open = false
            stack.push(detailComponent, { localId: localId })
        } else {
            stack.replace(detailComponent, { localId: localId })
        }
    }
    readonly property bool modalOpen: createSheet.open || balanceMenu.open || folderMenu.open || statusPanel.open
    readonly property bool pageInteractionBusy: !!stack.currentItem && stack.currentItem.renderInteractionBusy === true
    readonly property bool editorActive: createSheet.visible
        || (!!stack.currentItem && stack.currentItem.editingInProgress === true)
    readonly property bool overlaysVisible: createSheet.visible || balanceMenu.visible || folderMenu.visible
        || statusPanel.visible || confirmDialog.visible || dockMenuVisible || pageInteractionBusy
    function closeMenus() {
        balanceMenu.close()
        folderMenu.close()
        statusPanel.close()
        if (stack.currentItem && stack.currentItem.closeMenus !== undefined) stack.currentItem.closeMenus()
    }
    // workingId: continuar un borrador en la nube (Working Document) en el MISMO editor.
    // section: abrir directamente en General | Comprobante | Pago e importe | Sustentos.
    function openExpense(renditionLocalId, expenseLocalId, workingId, section, prefill) {
        stack.push(expenseComponent, { renditionLocalId: renditionLocalId, expenseLocalId: expenseLocalId || "",
                                       workingId: workingId || "", initialSection: section || "", prefill: prefill || null })
    }
    // "Registrar otro gasto" / recuperar un borrador: reemplaza el formulario actual.
    function replaceExpense(renditionLocalId, expenseLocalId, workingId) {
        stack.replace(expenseComponent, { renditionLocalId: renditionLocalId, expenseLocalId: expenseLocalId || "",
                                          workingId: workingId || "" })
    }
    // Navegación desde el diagnóstico: abre la ficha afectada (o reutiliza la abierta)
    // y después ejecuta [then(detail)]. Nunca abre ni modifica nada sin el toque del usuario.
    function goToRendition(localId, then) {
        closeMenus(); createSheet.open = false
        for (var i = stack.depth - 1; i >= 1; --i) {
            var item = stack.get(i, StackView.DontLoad)
            if (item && item.isRenditionDetail === true && item.localId === localId) {
                if (i < stack.depth - 1) stack.popToIndex(i, StackView.Immediate)
                if (then) then(item)
                return
            }
        }
        if (stack.depth > 1) stack.popToIndex(0, StackView.Immediate)
        call("select", { localId: localId }, "select", function(ok, result, code, message) {
            if (!ok) { shell.toast(shell.errorText(code, message), "error"); return }
            var detail = stack.push(detailComponent, { localId: localId, selectionToken: Number(result.selectionToken || 0) })
            if (then && detail) then(detail)
        })
    }
    // Acceso efímero a un archivo autorizado (sustento de borrador / binario archivado):
    // el servidor revalida el permiso; la URL firmada no se guarda en ningún sitio.
    function openAuthorized(operation, args, key) {
        return call(operation, args, key, function(ok, result, code, message) {
            if (!ok) { shell.toast(shell.errorText(code, message), "error"); return }
            var row = (result.rows || [])[0] || {}
            if (!String(row.signedUrl || "").length) { shell.toast("El servidor no devolvió un acceso al archivo.", "error"); return }
            Qt.openUrlExternally(row.signedUrl)
        })
    }
    function openReceived(row) { stack.push(receivedComponent, { row: row }) }
    function closePage() { if (stack.depth > 1) stack.pop() }

    function handleBack() {
        if (confirmDialog.opened) { confirmDialog.close(); return true }
        if (statusPanel.open) { statusPanel.close(); return true }
        if (balanceMenu.open) { balanceMenu.close(); return true }
        if (folderMenu.open) { folderMenu.close(); return true }
        if (createSheet.open) {
            if (createSheet.editor && createSheet.editor.handleBack()) return true
            createSheet.open = false
            return true
        }
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
    // Política (inventario de avisos):
    //   1 estado automático (conexión, reintentos, sesión) -> sólo aura + panel
    //   2 error que requiere intervención                  -> panel Estado de Rendiciones
    //   3 validación de campo                              -> en el propio formulario
    //   4 confirmación                                     -> RConfirm
    //   5 éxito / información breve                        -> aviso breve (este toast)
    // Ningún recuadro de las categorías 1-2 se dibuja sobre las pantallas.
    property string toastText: ""
    property string toastKind: "info"
    function currentArea() {
        var item = stack.currentItem
        if (detailPage) return renditionName(detailPage.current)
        return item && item.title !== undefined ? "Rendiciones · " + item.title : "Rendiciones"
    }
    function reportProblem(text, area, key) {
        if (!ctl || !String(text || "").length) return
        ctl.reportIssue(key || ("msg:" + text), { what: String(text), area: area || currentArea(),
                                                 title: "Operación no completada", severity: "error",
                                                 renditionLocalId: detailPage ? String(detailPage.localId) : "" })
    }
    function toast(text, kind) {
        if (!String(text || "").length) return          // error silencioso (conexión): sólo aura
        if (kind === "error" && ctl) { reportProblem(text); return }   // categoría 2: al panel
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
    Timer {
        interval: 1000; repeat: true; running: S.renderDiagnostics
        onTriggered: {
            S.renderReport()
            console.info("INGE_REND_RENDER viewport=" + Math.round(shell.width) + "x" + Math.round(shell.height)
                         + " ime=" + (shell.flow && shell.flow.imeVisible === true ? 1 : 0)
                         + " ime_height=" + Math.round(shell.flow ? shell.flow.imeHeight || 0 : 0)
                         + " available=" + Math.round(shell.flow ? shell.flow.availableContentHeight || 0 : shell.height))
        }
    }

    // ------------------------------------------------------------- Interfaz
    // Fondo blanco real de la app con las auras de sincronización detrás de todo.
    Item {                                          // superficie real: blanco + auras
        id: backdropLayer
        anchors.fill: parent
        Rectangle { anchors.fill: parent; color: S.background }
        RendicionesSyncAura {
            objectName: "syncAura"
            anchors.fill: parent
            mode: shell.syncMode
            running: shell.active && shell.visible
            reducedMotion: shell.ui.reducedMotion === true
            lowCost: shell.ui.dockLowCostGlass === true
        }
    }

    // Liquid Glass de las tarjetas: el mismo material del Dock
    // (GlassSurface) muestreando sólo el fondo vivo, nunca el contenido.
    // Claro y oscuro (vidrio esmerilado de la versión anterior de la app).
    readonly property bool cardGlassLive: shell.ui.liquidGlass !== false && shell.visible
    readonly property bool renderCaptureBlocked: !shell.active || !shell.visible
        || navigationTransitionActive || stack.busy || overlaysVisible || editorActive
        || (!!stack.currentItem && stack.currentItem.sectionAnimating === true)
        || (flow ? flow.imeVisible === true : Qt.inputMethod.visible) || Qt.inputMethod.animating
        || Qt.application.state !== Qt.ApplicationActive
    readonly property bool cardCaptureAllowed: cardGlassLive && !renderCaptureBlocked
    property int glassTick: 0
    QtObject {
        id: cardGlassUi
        readonly property Item backdrop: backdropLayer
        // A valid producer must reach the shader before the first capture can finish.
        readonly property bool glassReady: shell.cardGlassLive && backdropCapture.sourceItem !== null && backdropCapture.width > 0 && backdropCapture.height > 0
        readonly property var glassTexture: glassReady ? backdropCapture : null
        readonly property int glassTick: shell.glassTick
    }
    ShaderEffectSource {
        id: backdropCapture
        width: backdropLayer.width; height: backdropLayer.height
        sourceItem: shell.visible && (textureReady || updatePending || shell.cardCaptureAllowed) ? backdropLayer : null
        property bool textureReady: false
        property bool updatePending: false
        property size captureSize: Qt.size(1, 1)
        onSourceItemChanged: {
            textureReady = false
            updatePending = false
            if (shell.cardCaptureAllowed) Qt.callLater(shell.captureBackdrop)
        }
        onScheduledUpdateCompleted: {
            updatePending = false
            textureReady = sourceItem !== null
        }
        // Fluidez: el fondo (aurora/universo) se mueve lento; se recaptura a ~20 fps
        // y a baja resolución (el vidrio lo esmerila igual), no en cada cuadro.
        live: false
        hideSource: false; visible: false; smooth: true
        readonly property int divisor: shell.ui.dockLowCostGlass === true ? 8 : 6
        textureSize: captureSize
    }
    function captureBackdrop() {
        if (!cardCaptureAllowed || backdropCapture.updatePending || !backdropCapture.sourceItem
                || backdropCapture.width <= 0 || backdropCapture.height <= 0) return
        backdropCapture.captureSize = Qt.size(Math.max(1, Math.round(backdropCapture.width / backdropCapture.divisor)),
                                             Math.max(1, Math.round(backdropCapture.height / backdropCapture.divisor)))
        backdropCapture.updatePending = true
        S.renderCount("backdrop_capture")
        backdropCapture.scheduleUpdate()
    }
    onCardCaptureAllowedChanged: if (cardCaptureAllowed) Qt.callLater(shell.captureBackdrop)
    Timer {
        interval: 50; repeat: true
        running: shell.cardCaptureAllowed && shell.ui.reducedMotion !== true
        onTriggered: shell.captureBackdrop()
    }
    // La posición de cada tarjeta (desplazamiento) sí se sigue en cada cuadro: es barato.
    FrameAnimation { running: shell.cardCaptureAllowed; onTriggered: shell.glassTick++ }
    Binding { target: shell.ui; property: "cardGlassUi"; value: shell.cardGlassLive ? cardGlassUi : null; when: shell.visible || shell.active }

    // El Liquid Glass del Dock global NO se configura aquí: HomeScreen captura
    // esta subapp (renditionsLoader) como fondo del Dock con su motor único.

    Item {                                          // barra sólo en pantallas internas
        id: header
        width: parent.width
        // Pantallas con encabezado propio (rendición abierta) no usan esta barra.
        readonly property bool shown: stack.depth > 1 && !(stack.currentItem && stack.currentItem.ownHeader === true)
        height: shown ? shell.ui.topInset + 64 * shell.ui.u : 0
        visible: shown
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
                id: headerTitle
                objectName: "headerTitle"
                width: header.width - (headerChip.visible ? headerChip.width + 90 * shell.ui.u : syncButton.visible ? 190 * shell.ui.u : 70 * shell.ui.u)
                anchors.verticalCenter: parent.verticalCenter
                text: stack.currentItem && stack.currentItem.title !== undefined ? stack.currentItem.title : "Rendiciones"
                color: S.text
                font.family: shell.ui.fontFamily
                font.pixelSize: (headerChip.visible ? 25 : 21) * shell.ui.u    // Nuevo gasto: título de sección del preview
                font.weight: Font.DemiBold
                elide: Text.ElideRight
                // Cambio de sección: fundido corto del nombre (sin desplazar el encabezado).
                onTextChanged: if (!shell.ui.reducedMotion) titleFade.restart()
                NumberAnimation { id: titleFade; target: headerTitle; property: "opacity"; from: 0.25; to: 1; duration: 220; easing.type: Easing.OutCubic }
            }
        }
        // Indicador REAL del borrador (Nuevo gasto): lo calcula la página con el
        // estado Working/outbox; aquí sólo se presenta.
        Rectangle {
            id: headerChip
            objectName: "headerChip"
            readonly property var chip: stack.currentItem && stack.currentItem.headerChip !== undefined ? stack.currentItem.headerChip : null
            visible: header.shown && chip !== null
            anchors.right: parent.right
            anchors.rightMargin: 14 * shell.ui.u
            y: shell.ui.topInset + 13 * shell.ui.u
            height: 38 * shell.ui.u
            width: chipRow.implicitWidth + 30 * shell.ui.u
            radius: height / 2
            readonly property color tone: chip ? chip.tone : S.muted
            color: Qt.rgba(tone.r, tone.g, tone.b, 0.10)
            border.width: 1
            border.color: Qt.rgba(tone.r, tone.g, tone.b, 0.12)
            Behavior on width { enabled: !shell.ui.reducedMotion; NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
            Row {
                id: chipRow
                anchors.centerIn: parent
                spacing: 6 * shell.ui.u
                Rectangle { width: 8 * shell.ui.u; height: width; radius: width / 2; color: headerChip.tone; anchors.verticalCenter: parent.verticalCenter }
                Text {
                    id: chipLabel
                    objectName: "headerChipLabel"
                    text: headerChip.chip ? headerChip.chip.label : ""
                    // Texto en el tono del estado (ámbar oscurecido para legibilidad).
                    color: headerChip.tone === S.warning ? "#8A6100" : Qt.darker(headerChip.tone, 1.1)
                    font.weight: Font.DemiBold
                    font.family: shell.ui.fontFamily
                    font.pixelSize: 15 * shell.ui.u
                    anchors.verticalCenter: parent.verticalCenter
                    onTextChanged: if (!shell.ui.reducedMotion) chipPulse.restart()
                }
            }
            SequentialAnimation {
                id: chipPulse
                NumberAnimation { target: headerChip; property: "scale"; to: 1.06; duration: 110; easing.type: Easing.OutQuad }
                NumberAnimation { target: headerChip; property: "scale"; to: 1.0; duration: 180; easing.type: Easing.OutCubic }
            }
        }
        RButton {
            id: syncButton
            objectName: "headerSyncButton"
            // Sin botón de sincronizar donde no aporta (Papelera) o donde el
            // encabezado muestra el estado propio del borrador.
            visible: !headerChip.visible && !(stack.currentItem && stack.currentItem.hideSync === true)
            anchors.right: parent.right
            anchors.rightMargin: 12 * shell.ui.u
            y: shell.ui.topInset + 8 * shell.ui.u
            ui: shell.ui
            glyph: 0xE145
            busy: shell.busy("sync") || shell.phase === "PUSHING"
            // Sin conexión no hay texto propio (lo indica el aura): pendientes o neutro.
            label: shell.phase === "PULLING" ? "Actualizando"
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
        clip: true
        initialItem: homeComponent
        background: null
        onCurrentItemChanged: shell.closeMenus()
    }

    Component { id: homeComponent; RenditionsHome { app: shell } }
    Component { id: detailComponent; RenditionDetail { app: shell } }
    Component { id: editorComponent; RenditionEditor { app: shell } }
    Component { id: expenseComponent; ExpenseEditor { app: shell } }
    Component { id: receivedComponent; RenditionReceived { app: shell } }
    Component { id: filesComponent; FilesBrowser { app: shell } }
    // Archivero (sólo lectura) y Papelera global de Files v07, desde el menú Carpeta.
    function openFiles(mode) { closeMenus(); stack.push(filesComponent, { mode: mode }) }

    RConfirm { id: confirmDialog; objectName: "confirmDialog"; ui: shell.ui }

    // ---------------------------------------------- Nueva rendición (hoja)
    Item {
        id: createSheet
        objectName: "createSheet"
        property bool open: false
        readonly property var editor: sheetLoader.item
        anchors.fill: parent
        z: 30
        visible: open || sheetCard.y < height
        MouseArea {                                  // tocar fuera cierra (lo escrito queda en borrador)
            anchors.fill: parent
            enabled: createSheet.open
            onClicked: createSheet.open = false
        }
        Rectangle {
            id: sheetCard
            width: parent.width - 20 * shell.ui.u
            x: 10 * shell.ui.u
            height: Math.min(parent.height * 0.76, 640 * shell.ui.u)
            y: createSheet.open ? parent.height - height - shell.ui.dockArea + 8 * shell.ui.u : parent.height + 20 * shell.ui.u
            Behavior on y { NumberAnimation { duration: createSheet.open ? 260 : 180; easing.type: Easing.OutCubic } }
            radius: 30 * shell.ui.u
            gradient: Gradient {
                GradientStop { position: 0.0; color: Qt.rgba(1, 1, 1, 0.97) }
                GradientStop { position: 1.0; color: Qt.rgba(246 / 255, 249 / 255, 253 / 255, 0.95) }
            }
            border.width: 1
            border.color: Qt.rgba(1, 1, 1, 0.95)
            MouseArea { anchors.fill: parent }          // no atraviesa a la lista
            Rectangle {                                 // asa
                width: 40 * shell.ui.u; height: 5 * shell.ui.u; radius: height / 2
                anchors.horizontalCenter: parent.horizontalCenter
                y: 10 * shell.ui.u
                color: S.ink(0.18)
            }
            Column {
                id: sheetTitle
                x: 22 * shell.ui.u
                y: 28 * shell.ui.u
                width: parent.width - 44 * shell.ui.u
                spacing: 6 * shell.ui.u
                Text { text: "Nueva rendición"; color: S.text; font.family: shell.ui.fontFamily; font.pixelSize: 24 * shell.ui.u; font.weight: Font.DemiBold }
                Text {
                    width: parent.width
                    text: "¿Qué proyectos quiere asociar a la rendición?"
                    color: S.muted; wrapMode: Text.WordWrap
                    font.family: shell.ui.fontFamily; font.pixelSize: 16 * shell.ui.u
                }
            }
            Loader {
                id: sheetLoader
                anchors.top: sheetTitle.bottom
                anchors.topMargin: 4 * shell.ui.u
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                anchors.bottomMargin: 10 * shell.ui.u
                active: createSheet.visible          // vive durante la animación de cierre
                sourceComponent: Component { RenditionEditor { app: shell; original: null; embedded: true } }
            }
        }
    }

    // ------------------------------------- Dock contextual global (oficial)
    // Rendiciones no dibuja dock: publica sus tres acciones en el
    // DockContextController (ContextPublisher, canal "qml") y el dock global de
    // HomeScreen las muestra con su geometría, Liquid Glass, Deep Press y
    // hápticos. DockCommandRouter despacha cada toque como `command` aquí;
    // ContextPublisher completa siempre el despacho (éxito o error). Con
    // Rendiciones inactiva el contexto se retira y el router rechaza toques
    // de otro propietario.
    //
    // Contextos (mismo propietario "rendiciones", distinto contextId):
    //  rendiciones/home   -> Balance, Nueva rendición, Carpeta (lista)
    //  rendiciones/detail -> Atrás, Editar gastos, Agregar gasto y una acción
    //                        contextual cuyo menú (Deep Press / toque) lista las
    //                        sugerencias deterministas de RenditionDetail.suggestions
    //  rendiciones/page   -> Atrás (formularios y consultas internas)
    //  rendiciones/expense -> Nuevo gasto: [Volver][Borrador][Siguiente|Registrar][···]
    //                        publicado por la propia página (ExpenseEditor.dockActions)
    // "Estado de Rendiciones": herramienta PERMANENTE de consulta (4.ª posición
    // del Home desde la primera entrada, haya o no fallos; en la ficha, dentro del
    // menú de sugerencias). Sin quinto botón: el Dock conserva su geometría.
    readonly property var statusAction: ({ id: "renditions.status", label: "Estado de Rendiciones", icon: "renditions.status",
                                           command: "renditions.status", enabled: true, priority: 4 })
    readonly property var homeDockActions: {
        var list = [
            { id: "renditions.balance", label: "Balance de rendiciones", icon: "renditions.balance",
              command: "renditions.balance", enabled: true, priority: 1 },
            { id: "renditions.create", label: "Nueva rendición", icon: "renditions.create",
              command: "renditions.create", enabled: true, priority: 2 },
            { id: "renditions.folder", label: "Carpeta documental", icon: "renditions.folder",
              command: "renditions.folder", enabled: true, priority: 3 }
        ]
        list.push(statusAction)
        return list
    }
    readonly property var pageDock: stack.currentItem && stack.currentItem.dockActions !== undefined ? stack.currentItem : null
    readonly property var detailPage: stack.currentItem && stack.currentItem.isRenditionDetail === true ? stack.currentItem : null
    readonly property string liveRenditionId: detailPage ? String(detailPage.remoteId || "") : ""
    onLiveRenditionIdChanged: { liveReload.stop(); liveReloadPending = false }
    property var liveChannel: null
    readonly property var livePeers: liveChannel ? liveChannel.members : []
    readonly property bool liveJoined: !!liveChannel && liveChannel.state === "JOINED"
    property string livePrevPhase: "IDLE"
    readonly property string liveOrigin: ctl ? ctl.newId() : ""
    property bool liveReloadPending: false
    readonly property bool liveReloadBlocked: !shell.active || !shell.visible || stack.busy
        || navigationTransitionActive || editorActive || overlaysVisible || phase !== "IDLE"
        || busy("sync") || busy("refresh") || busy("bootstrap")
        || (flow ? flow.imeVisible === true : Qt.inputMethod.visible)
        || Qt.application.state !== Qt.ApplicationActive
    function requestLiveReload() {
        if (!liveRenditionId.length) return
        liveReloadPending = true
        if (!liveReloadBlocked) liveReload.restart()
    }
    onLiveReloadBlockedChanged: {
        if (liveReloadBlocked) liveReload.stop()
        else if (liveReloadPending) liveReload.restart()
    }
    onPhaseChanged: {
        // Guardado propio terminado: avisa a los demás que recarguen.
        if (livePrevPhase === "PUSHING" && phase !== "PUSHING" && liveJoined)
            liveChannel.broadcast("invalidate", { origin: liveOrigin })
        livePrevPhase = phase
    }
    Item {
        Component.onCompleted: {
            try { shell.liveChannel = Qt.createQmlObject("import InGe.Mobile; SupabaseRealtimeChannel {}", shell, "renditionLive") }
            catch (e) { shell.liveChannel = null }
        }
    }
    Binding { target: shell.liveChannel; property: "topic"; when: shell.liveChannel !== null
              value: shell.liveRenditionId.length ? "rendition:" + shell.liveRenditionId : "" }
    Binding { target: shell.liveChannel; property: "active"; when: shell.liveChannel !== null
              value: shell.active && Qt.application.state === Qt.ApplicationActive }
    Binding { target: shell.liveChannel; property: "trackMeta"; when: shell.liveChannel !== null
              value: ({ routeIds: shell.liveRenditionId.length ? [shell.liveRenditionId] : [] }) }
    Connections {
        target: shell.liveChannel
        ignoreUnknownSignals: true
        function onBroadcastReceived(event, payload) {
            if (event === "invalidate" && (!payload || payload.origin !== shell.liveOrigin)) shell.requestLiveReload()
        }
        function onRejoined() { shell.requestLiveReload() }
    }
    Timer {
        id: liveReload
        interval: 200
        onTriggered: {
            if (!shell.liveReloadPending || shell.liveReloadBlocked) return
            if (shell.synchronize(true).length) shell.liveReloadPending = false
        }
    }
    readonly property string dockContextId: stack.depth <= 1 ? "rendiciones/home"
                                          : detailPage ? "rendiciones/detail"
                                          : pageDock ? String(pageDock.dockContextKey || "rendiciones/page") : "rendiciones/page"
    readonly property var dockActions: {
        var back = { id: "renditions.back", label: "Atrás", icon: "system.back",
                     command: "renditions.back", enabled: true, priority: 1 }
        if (stack.depth <= 1) return homeDockActions
        if (pageDock) return pageDock.dockActions
        if (!detailPage) return [back]
        var d = detailPage
        var suggestions = d.suggestions || []
        var top = suggestions.length ? suggestions[0] : null
        var children = suggestions.map(function(x, i) {
            return { id: "renditions.suggest." + x.key, label: (i === 0 ? "Sugerido: " : "") + x.label,
                     icon: x.icon, command: "renditions.suggest." + x.key, enabled: true, priority: i + 1 }
        })
        // «Editar gastos» es una RAMA sin comando propio: toque o Deep Press sólo
        // abren el Quick Bubble oficial (dockSlotTap -> dockOpenMenu) y, al no
        // tener `command`, dockMenuItems no inserta una entrada primaria. Sólo
        // las subacciones elegidas ejecutan algo. Escritura sólo con permiso.
        var expenseItems = [{ id: "renditions.expenses.list", label: "Ver todos los gastos", icon: "documents.file",
                              command: "renditions.expenses.list", enabled: true, priority: 1 }]
        var rows = (d.expenses || []).slice(-7).reverse()               // los más recientes
        for (var i = 0; i < rows.length; ++i) {
            var e = rows[i]
            var concept = String(e.concept || "Gasto sin concepto")
            expenseItems.push({ id: "renditions.expenses.open." + e.localId,
                                label: (d.writable ? "Editar: " : "Ver: ") + concept + " · "
                                       + (shell.ctl ? shell.ctl.formatMoney(e.amount, String(e.currencyCode || e.currency_code || "PEN")) : ""),
                                icon: d.writable ? "action.edit" : "documents.file",
                                command: "renditions.expenses.open." + e.localId, enabled: true, priority: i + 2 })
        }
        if (d.editable)
            expenseItems.push({ id: "renditions.expenses.add", label: "Agregar gasto", icon: "action.add",
                                command: "renditions.expenses.add", enabled: true, priority: 9 })
        var list = [back,
            { id: "renditions.editExpenses", label: "Editar gastos", icon: "action.edit",
              children: expenseItems, enabled: d.exists, priority: 2 },
            { id: "renditions.addExpense", label: "Agregar gasto", icon: "action.add",
              command: "renditions.addExpense", enabled: d.editable, priority: 3 }]
        children.push({ id: "renditions.status", label: "Estado de Rendiciones", icon: "renditions.status",
                        command: "renditions.status", enabled: true, priority: children.length + 1 })
        if (top)
            list.push({ id: "renditions.suggest", label: top.label, icon: top.icon,
                        command: "renditions.suggest." + top.key, children: children, enabled: true, priority: 4 })
        else
            list.push(statusAction)
        return list
    }
    // El texto JSON sólo cambia cuando cambia el contenido: el dock no se
    // regenera (ni se cierra su menú) por cada estado publicado por el bridge.
    readonly property string dockActionsJson: JSON.stringify(dockActions)
    FlowCore.ContextPublisher {
        id: dockPublisher
        ownerId: "rendiciones"
        contextId: shell.dockContextId
        actions: JSON.parse(shell.dockActionsJson)
        active: shell.active
        onCommand: function(commandId) {
            if (!shell.active || !shell.visible) return
            shell.dockCommand(String(commandId))
        }
    }
    // Despacho ÚNICO de los comandos del Dock global para esta subapp.
    function dockCommand(commandId) {
        var name = String(commandId)
        if (name === "renditions.balance") shell.toggleBalance()
        else if (name === "renditions.create") shell.toggleCreate()
        else if (name === "renditions.folder") shell.toggleFolder()
        else if (name === "renditions.status") shell.toggleStatus()
        else if (name.indexOf("renditions.page.") === 0 || name.indexOf("renditions.tool.") === 0) {
            if (shell.pageDock && shell.pageDock.dockCommand !== undefined) shell.pageDock.dockCommand(name)
        }
        else if (name === "renditions.back") { if (!shell.handleBack()) shell.requestBack() }
        else if (name === "renditions.expenses.list") { if (shell.detailPage) shell.detailPage.showSection("expenses") }
        else if (name === "renditions.expenses.add") {
            if (shell.detailPage && shell.detailPage.editable) shell.openExpense(shell.detailPage.localId, "")
        }
        else if (name.indexOf("renditions.expenses.open.") === 0) {
            if (shell.detailPage)
                shell.openExpense(shell.detailPage.localId, name.substring("renditions.expenses.open.".length))
        }
        else if (name === "renditions.addExpense") {
            if (shell.detailPage && shell.detailPage.editable) shell.openExpense(shell.detailPage.localId, "")
        }
        else if (name.indexOf("renditions.suggest.") === 0) {
            if (shell.detailPage) shell.detailPage.runSuggestion(name.substring("renditions.suggest.".length))
        }
    }

    // Punto de anclaje sobre la celda [index] del dock global (3 ó 4 posiciones);
    // sin dock (pruebas de host), el centro inferior de la pantalla.
    function dockCellPoint(index) {
        if (dockAnchor) {
            var slots = ui.dockSlots !== undefined && ui.dockSlots ? ui.dockSlots.length : 3
            var cell = ui.dockCellWidth !== undefined ? ui.dockCellWidth : dockAnchor.width / slots
            return dockAnchor.mapToItem(shell, dockAnchor.width / 2 + (index - (slots - 1) / 2) * (cell + 1), 0)
        }
        return Qt.point(width / 2, height - (ui.dockBottom || 0) - (ui.dockHeight || 0))
    }
    function toggleStatus() {
        var open = !statusPanel.open
        closeMenus(); createSheet.open = false
        if (!open) return
        var p = dockCellPoint(stack.depth <= 1 ? 3 : 1)
        statusPanel.anchorX = p.x; statusPanel.anchorY = p.y
        statusPanel.open = true
    }
    // ------------------------------------------------ InGe IA (contexto)
    // La interfaz y la conversación son GLOBALES (HomeScreen). Rendiciones sólo
    // publica su contexto mínimo autorizado y su herramienta nativa "Registrar
    // gasto": la IA PREPARA propuestas; el usuario las revisa en el formulario
    // existente (ExpenseEditor) y registra con su validación y confirmación.
    // Nunca se inserta un gasto desde el texto del modelo. Independiente de
    // INGE_RENDITIONS_AI_ENABLED (que protege las operaciones de IA del bridge).
    readonly property var editableRenditions: (st.renditions || []).filter(function(r) {
        return r.archived !== true && !!ctl && ctl.canEdit(r) })
    property string assistantTarget: ""
    readonly property var assistantRendition: {
        var rows = editableRenditions
        var want = assistantTarget.length ? assistantTarget : String(detailPage ? detailPage.localId : (st.selectedLocalId || ""))
        for (var i = 0; i < rows.length; ++i) if (rows[i].localId === want) return rows[i]
        return rows.length ? rows[0] : null
    }
    function renditionName(r) { return r ? S.renditionDisplayName(S.text_(r, "displayName", "display_name"), S.text_(r, "visibleCode", "visible_code"))
                                     + " · " + String(r.visibleCode || "Código pendiente") + " · " + S.period(r.periodStart, r.periodEnd) : "" }
    function catalogText(kind) {
        if (!ctl) return ""
        return ctl.catalog(kind).map(function(r) { return S.text_(r, "code") + "=" + (S.text_(r, "name") || S.text_(r, "label") || S.text_(r, "code")) }).join("; ")
    }
    readonly property var assistantModule: ({
        id: "rendiciones", name: "Rendiciones",
        instructions: "Contexto: módulo Rendiciones (rendición de gastos de campo). Ayuda con dudas financieras y de comprobantes "
                      + "(boleta, factura, IGV, medios de pago) y guía el registro de gastos. Si el usuario quiere registrar gastos, "
                      + "pide los datos que falten (concepto, importe, fecha, medio de pago, comprobante) y recuérdale que puede tocar "
                      + "«Registrar gasto» para preparar el formulario; tú no registras nada.",
        data: assistantRendition ? "Rendición destino: " + renditionName(assistantRendition)
                                   + ". Rendiciones editables: " + editableRenditions.length + "." : "No hay rendiciones editables.",
        tools: [{ id: "renditions.assistant.expense", label: "Registrar gasto", glyph: 0xE412, primary: true,
                  enabled: assistantRendition !== null },
                { id: "renditions.assistant.target", label: assistantRendition ? "Rendición: " + renditionName(assistantRendition) : "Sin rendición editable",
                  glyph: 0xE0D7, offline: true, enabled: editableRenditions.length > 1 }]
    })
    function assistantRunTool(toolId, assistant) {
        if (toolId === "renditions.assistant.target") {           // alterna entre rendiciones editables reales
            var rows = editableRenditions
            if (rows.length < 2) return
            var current = assistantRendition ? assistantRendition.localId : ""
            var at = 0
            for (var i = 0; i < rows.length; ++i) if (rows[i].localId === current) at = i
            assistantTarget = rows[(at + 1) % rows.length].localId
            assistant.setProposals(assistant.proposals.map(function(p) { return shell.assistantValidate(p) }))
            return
        }
        if (toolId !== "renditions.assistant.expense" || !assistantRendition) return
        var instruction = "TAREA DE EXTRACCIÓN (no conversacional). Devuelve SOLO un arreglo JSON, sin texto adicional, con los gastos "
            + "que el usuario pidió registrar en esta conversación (máximo 10). Cada elemento: {\"concept\": texto, \"amount\": número con punto decimal, "
            + "\"currency\": \"PEN\"|\"USD\"|null, \"date\": \"AAAA-MM-DD\"|null, \"category\": código|null, \"paymentMethod\": código|null, "
            + "\"supportType\": código|null, \"beneficiary\": texto|null}. Usa SOLO estos códigos y null si el usuario no lo dijo; no inventes valores. "
            + "Categorías: " + catalogText("CATEGORY") + ". Medios de pago: " + catalogText("PAYMENT_METHOD")
            + ". Tipos de comprobante: " + catalogText("SUPPORT_TYPE") + ". Si no hay gastos claros, devuelve []."
        assistant.ask(instruction, function(raw) {
            var open = raw.indexOf("["), close = raw.lastIndexOf("]")
            var list = []
            if (open >= 0 && close > open) { try { list = JSON.parse(raw.slice(open, close + 1)) } catch (e) { list = [] } }
            if (!Array.isArray(list)) list = []
            var proposals = list.slice(0, 10).map(function(x) { return shell.assistantValidate(shell.assistantProposal(x)) })
            assistant.setProposals(proposals)
            assistant.note(proposals.length
                ? proposals.length + (proposals.length === 1 ? " gasto preparado" : " gastos preparados")
                  + " para " + shell.renditionName(shell.assistantRendition) + ". Revisa cada uno y ábrelo en el formulario para registrarlo."
                : "No identifiqué un gasto con concepto e importe. Escribe, por ejemplo: almuerzo S/ 18 en efectivo.")
        })
    }
    function catalogHas(kind, code) {
        return !!ctl && String(code || "").length > 0 && ctl.catalog(kind).some(function(r) { return S.text_(r, "code") === String(code) })
    }
    // Normaliza lo propuesto por el modelo SIN inventar: códigos inexistentes,
    // fechas inválidas o fuera del período se descartan (se completan en el formulario).
    function assistantProposal(x) {
        x = x || {}
        var amount = x.amount === null || x.amount === undefined ? "" : String(x.amount).replace(",", ".").trim()
        return { concept: String(x.concept || "").trim().slice(0, 200), amount: amount,
                 currencyCode: x.currency === "USD" ? "USD" : x.currency === "PEN" ? "PEN" : "",
                 expenseDate: /^\d{4}-\d{2}-\d{2}$/.test(String(x.date || "")) ? String(x.date) : "",
                 categoryCode: catalogHas("CATEGORY", x.category) ? String(x.category) : "",
                 paymentMethodCode: catalogHas("PAYMENT_METHOD", x.paymentMethod) ? String(x.paymentMethod) : "",
                 supportTypeCode: catalogHas("SUPPORT_TYPE", x.supportType) ? String(x.supportType) : "",
                 beneficiary: String(x.beneficiary || "").trim().slice(0, 200) }
    }
    function assistantValidate(p) {
        var out = Object.assign({}, p)
        var r = assistantRendition
        if (out.expenseDate && r && (out.expenseDate < String(r.periodStart || "") || out.expenseDate > String(r.periodEnd || ""))) out.expenseDate = ""
        var problems = []
        if (!String(out.concept || "").trim().length) problems.push("falta el concepto")
        var amountProblem = ctl ? ctl.amountError(String(out.amount || "")) : ""
        if (amountProblem.length) problems.push(amountProblem.charAt(0).toLowerCase() + amountProblem.slice(1).replace(/\.$/, ""))
        var missing = []
        if (!out.categoryCode) missing.push("categoría")
        if (!out.paymentMethodCode) missing.push("medio de pago")
        if (!out.supportTypeCode) missing.push("tipo de comprobante")
        out.renditionLocalId = r ? r.localId : ""
        out.ready = !!r && problems.length === 0
        out.problem = !r ? "No hay una rendición editable con permiso de edición." : problems.length ? "Corrige: " + problems.join("; ") + "." : ""
        out.summary = (out.currencyCode || "PEN") + (out.expenseDate ? " · " + S.date(out.expenseDate) : "")
                      + (missing.length ? " · En el formulario completarás: " + missing.join(", ") : " · Datos de catálogo completos")
                      + (out.opened ? " · Abierto en el formulario" : "")
        out.actionLabel = out.opened ? "Abrir de nuevo en el formulario" : "Revisar y registrar"
        return out
    }
    // "Revisar y registrar": abre el formulario EXISTENTE prellenado; el registro
    // definitivo lo confirma el usuario allí (validación C++, outbox, confirmación).
    function assistantOpen(index, proposal, assistant) {
        var p = assistantValidate(proposal)
        if (!p.ready) return false
        var list = assistant.proposals.slice()
        if (index >= 0 && index < list.length) { list[index] = assistantValidate(Object.assign({}, p, { opened: true })); assistant.setProposals(list) }
        var prefill = { concept: p.concept, amount: p.amount }
        ;["currencyCode", "expenseDate", "categoryCode", "paymentMethodCode", "supportTypeCode", "beneficiary"].forEach(function(k) {
            if (String(p[k] || "").length) prefill[k] = p[k]
        })
        goToRendition(p.renditionLocalId, function(d) {
            if (d.editable === false) return
            shell.openExpense(p.renditionLocalId, "", "", "general", prefill)
        })
        return true
    }

    // ------------------------------------------- Acciones del diagnóstico
    property bool renewingSession: false
    function runIncident(item) {
        var act = item.action || {}
        var kind = String(act.kind || "")
        var rendition = String(item.renditionLocalId || "")
        if (kind === "retry") { statusPanel.busyKey = item.key; synchronize(true, function() { statusPanel.busyKey = "" }); return }
        if (kind === "dismiss") { if (ctl) ctl.resolveIssue(String(item.key).replace(/^action:/, "")); return }
        if (kind === "renewSession") { renewSession(); return }
        statusPanel.close()
        if (!rendition.length) return
        if (kind === "openRendition") { goToRendition(rendition, null); return }
        if (kind === "openExpenses") { goToRendition(rendition, function(d) { d.showSection("expenses") }); return }
        if (kind === "openExpense" || kind === "openDraft") {
            var expense = String(item.expenseLocalId || ""), working = String(item.workingId || ""), section = String(item.section || "")
            goToRendition(rendition, function(d) { shell.openExpense(rendition, expense, working, section) })
        }
    }
    // Sesión expirada (AUTH_REQUIRED con red efectiva): renovación REAL con el token de
    // renovación de AuthSession. Si el servidor la rechaza, AuthSession cierra la sesión
    // y la app vuelve al inicio de sesión (datos locales intactos); por eso se confirma.
    function renewSession() {
        if (!authSession) { statusPanel.close(); requestOpenProfile(); return }
        if (connection !== "AUTH_REQUIRED") return
        confirm("Renovar sesión", "Se renovará tu sesión con el servidor. Si ya no es válida, tendrás que volver a iniciar sesión; tus cambios guardados en el equipo se conservan.",
                "Renovar", false, function() {
            shell.renewingSession = true
            statusPanel.busyKey = "link"
            shell.authSession.refreshSessionWithRefreshToken()
        })
    }
    Connections {
        target: shell.authSession
        ignoreUnknownSignals: true
        function onLoginOk() {
            if (!shell.renewingSession) return
            shell.renewingSession = false
            statusPanel.busyKey = ""
            shell.synchronize(true)
        }
        function onLoggedChanged() {
            if (shell.renewingSession && shell.authSession && !shell.authSession.logged) {
                shell.renewingSession = false
                statusPanel.busyKey = ""
            }
        }
    }
    function toggleBalance() {
        var open = !balanceMenu.open
        closeMenus(); createSheet.open = false
        if (!open) return
        var p = dockCellPoint(0)
        balanceMenu.anchorX = p.x; balanceMenu.anchorY = p.y
        balanceMenu.open = true
    }
    function toggleCreate() {
        if (createSheet.open) { createSheet.open = false; return }
        openCreate()
    }
    function toggleFolder() {
        var open = !folderMenu.open
        closeMenus(); createSheet.open = false
        if (!open) return
        var p = dockCellPoint(2)
        folderMenu.anchorX = p.x; folderMenu.anchorY = p.y
        folderMenu.open = true
    }

    // ------------------------------------------- Avance global (balance)
    RGlassMenu {
        id: balanceMenu
        objectName: "balanceMenu"
        ui: shell.ui
        z: 45
        cardWidth: 360 * shell.ui.u
        readonly property var c: shell.balanceCounts
        readonly property real ratio: c.total > 0 ? c.APROBADO / c.total : 0
        Text {
            width: parent.width
            leftPadding: 8 * shell.ui.u
            topPadding: 4 * shell.ui.u
            text: "Avance global de rendiciones"
            color: S.text
            font.family: shell.ui.fontFamily; font.pixelSize: 19 * shell.ui.u; font.weight: Font.DemiBold
        }
        Row {
            width: parent.width
            topPadding: 14 * shell.ui.u
            bottomPadding: 6 * shell.ui.u
            spacing: 18 * shell.ui.u
            Item {
                width: 118 * shell.ui.u; height: width
                Shape {
                    anchors.fill: parent
                    ShapePath {
                        strokeColor: Qt.rgba(6 / 255, 84 / 255, 162 / 255, 0.14)
                        strokeWidth: 12 * shell.ui.u
                        fillColor: "transparent"
                        capStyle: ShapePath.RoundCap
                        PathAngleArc { centerX: 59 * shell.ui.u; centerY: 59 * shell.ui.u; radiusX: 50 * shell.ui.u; radiusY: 50 * shell.ui.u; startAngle: 0; sweepAngle: 360 }
                    }
                    ShapePath {
                        strokeColor: S.corporateBlue
                        strokeWidth: 12 * shell.ui.u
                        fillColor: "transparent"
                        capStyle: ShapePath.RoundCap
                        PathAngleArc {
                            centerX: 59 * shell.ui.u; centerY: 59 * shell.ui.u; radiusX: 50 * shell.ui.u; radiusY: 50 * shell.ui.u
                            startAngle: -90
                            sweepAngle: 360 * balanceMenu.ratio
                        }
                    }
                }
                Text {
                    anchors.centerIn: parent
                    text: balanceMenu.c.total > 0 ? Math.round(balanceMenu.ratio * 100) + "%" : "—"
                    color: S.text
                    font.family: shell.ui.fontFamily; font.pixelSize: 26 * shell.ui.u; font.weight: Font.DemiBold
                }
            }
            Column {
                width: parent.width - 136 * shell.ui.u
                anchors.verticalCenter: parent.verticalCenter
                spacing: 10 * shell.ui.u
                Repeater {
                    model: [["APROBADO", "Aprobadas", S.corporateGreen], ["EN_REVISION", "En revisión", S.corporateBlue],
                            ["OBSERVADO", "Observadas", S.danger], ["BORRADOR", "Borrador", S.warning]]
                    delegate: Item {
                        required property var modelData
                        width: parent.width
                        height: 24 * shell.ui.u
                        Rectangle { width: 12 * shell.ui.u; height: width; radius: width / 2; color: modelData[2]; anchors.verticalCenter: parent.verticalCenter }
                        Text {
                            x: 22 * shell.ui.u
                            anchors.verticalCenter: parent.verticalCenter
                            text: modelData[1]
                            color: S.muted
                            font.family: shell.ui.fontFamily; font.pixelSize: 16 * shell.ui.u
                        }
                        Text {
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            text: String(balanceMenu.c[modelData[0]])
                            color: S.text
                            font.family: shell.ui.fontFamily; font.pixelSize: 17 * shell.ui.u; font.weight: Font.DemiBold
                        }
                    }
                }
            }
        }
        Text {
            width: parent.width
            leftPadding: 8 * shell.ui.u
            bottomPadding: 4 * shell.ui.u
            text: balanceMenu.c.total > 0 ? "Aprobadas sobre " + balanceMenu.c.total + " rendiciones" : "Aún no hay rendiciones."
            color: S.faint
            font.family: shell.ui.fontFamily; font.pixelSize: 13 * shell.ui.u
        }
    }

    // ------------------------------------------------- Carpeta documental
    RGlassMenu {
        id: folderMenu
        objectName: "folderMenu"
        ui: shell.ui
        z: 45
        cardWidth: 330 * shell.ui.u
        RMenuItem {
            ui: shell.ui
            label: "Abrir desde InGe Drive"
            glyph: 0xE0D7
            glyphColor: S.navy
            onActivated: { folderMenu.close(); shell.requestOpenDrive() }
        }
        RMenuItem {
            ui: shell.ui
            label: "Abrir desde Google Drive"
            onActivated: {
                folderMenu.close()
                // BLOQUEADO: no existe un formato ni un servicio de importación de
                // rendiciones; abrir un archivo de Drive no puede crear una rendición válida.
                shell.toast("Abrir desde Google Drive aún no está disponible: InGe+ no tiene un formato de importación de rendiciones.", "info")
            }
            Item {                                         // logotipo genérico de Drive (tres trazos)
                anchors.centerIn: parent
                width: 26 * shell.ui.u; height: 22 * shell.ui.u
                Rectangle { width: 6 * shell.ui.u; height: 20 * shell.ui.u; radius: 2; color: "#1FA463"; rotation: 30; x: 5 * shell.ui.u; y: 1 }
                Rectangle { width: 6 * shell.ui.u; height: 20 * shell.ui.u; radius: 2; color: "#FFD04B"; rotation: -30; x: 15 * shell.ui.u; y: 1 }
                Rectangle { width: 20 * shell.ui.u; height: 6 * shell.ui.u; radius: 2; color: "#4688F4"; x: 4 * shell.ui.u; y: 16 * shell.ui.u }
            }
        }
        RMenuItem {
            objectName: "menuArchive"
            ui: shell.ui
            label: "Archivero"
            glyph: 0xE0D7
            glyphColor: S.navy
            onActivated: { folderMenu.close(); shell.openFiles("archive") }
        }
        RMenuItem {
            objectName: "menuTrash"
            ui: shell.ui
            label: "Papelera"
            glyph: 0xE18E                               // trash-2 (Lucide)
            glyphColor: S.muted
            onActivated: { folderMenu.close(); shell.openFiles("trash") }
        }
        RMenuItem {
            ui: shell.ui
            label: "Importar rendición"
            glyph: 0xE0B2
            glyphColor: S.corporateBlue
            separator: false
            onActivated: {
                folderMenu.close()
                shell.toast("Importar rendición aún no está disponible: no existe un formato de importación validado.", "info")
            }
        }
    }

    // ------------------------------------------ Estado de Rendiciones
    RenditionsDiagnostics {
        id: statusPanel
        ui: shell.ui
        app: shell
        z: 46
        diagnostics: shell.diagnostics
        aiEnabled: !!shell.ctl && shell.ctl.aiEnabled === true
        onRunAction: function(incident) { shell.runIncident(incident) }
    }

    Rectangle {
        visible: shell.toastText.length > 0
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: shell.ui.dockArea + 12 * shell.ui.u
        width: Math.min(parent.width - 32 * shell.ui.u, toastLabel.implicitWidth + 32 * shell.ui.u)
        z: 60
        height: toastLabel.implicitHeight + 24 * shell.ui.u
        radius: 14 * shell.ui.u
        color: S.popup
        border.width: 1
        border.color: shell.toastKind === "error" ? S.danger : shell.toastKind === "success" ? S.success : S.border
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

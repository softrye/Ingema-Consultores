import QtQuick
import QtQuick.Controls
import QtQuick.Effects
import QtQuick.Dialogs
import "../renditions"

// Configuración (diseño claro aprobado; base convertida de SettingsApp.swift de
// iOS-26-clone, Apache 2.0). Foto del Home desenfocada + velo claro + auras de
// estado (RendicionesSyncAura). Tarjetas de vidrio por fila. Sin lógica propia:
// los datos entran por propiedades y las acciones salen por señales.
Item {
    id: app
    property var ui                                    // u, fontFamily, iconFamily, topInset, reducedMotion
    property url backgroundSource: ""
    property string userName: ""
    property string userEmail: ""
    property string appVersion: Qt.application.version
    property bool reduceMotion: false
    property bool liquidGlass: true
    property string syncMode: "unknown"
    property string syncText: ""
    property string notificationsText: "Activadas"
    // Seguridad
    property bool biometricAvailable: false
    property bool biometricEnabled: false
    property bool biometricBusy: false
    property string securityNotice: ""
    // Almacenamiento del SERVIDOR (inge_drive_storage_usage_v03)
    property var storageStats: ({})
    property bool storageBusy: false
    property string storageError: ""
    // Cuenta (Mi cuenta, Información personal, sesiones y cuentas guardadas)
    property url avatarSource: ""
    property string firstName: ""
    property string lastName: ""
    property string userPhone: ""
    property string userPosition: ""
    property string userArea: ""
    property string accountNotice: ""
    property bool profileSaving: false
    property var sessions: []                          // list_my_auth_sessions_v01
    property bool sessionsBusy: false
    property var savedAccounts: []
    property string currentAccountId: ""
    signal profileSaveRequested(string nombre, string apellido, string phone)
    signal avatarChosen(url file)
    signal sessionsRefreshRequested()
    signal sessionRevokeRequested(string sessionId)
    signal signOutOthersRequested()
    signal accountSwitchRequested(string accountId)
    signal addAccountRequested()
    // Sincronización (estados de las subapps: synced | pending | syncing | attention | error | offline | unknown)
    property string renditionsSync: "unknown"
    property int renditionsPending: 0
    property string calicatasSync: "unknown"
    property bool syncBusy: false
    signal syncNowRequested()
    // Verificación en dos pasos (TOTP)
    property bool mfaEnabled: false
    property var mfaEnrollment: null                  // { factorId, qr, secret, uri } mientras se activa
    signal mfaEnrollRequested()
    signal mfaConfirmRequested(string factorId, string code)
    signal mfaDisableRequested()
    onMfaEnrollmentChanged: {
        if (mfaEnrollment) stack.push(mfaPage)
        else if (stack.currentItem && stack.currentItem.objectName === "mfaPage") stack.pop()
    }
    function syncLabel(m) {
        return ({ synced: "Al día", pending: "Pendiente", syncing: "Sincronizando", attention: "Revisar",
                  error: "Con errores", offline: "Sin conexión" })[m] || "Sin datos"
    }
    function syncColor(m) {
        return m === "error" || m === "offline" ? "#D64550" : m === "attention" ? "#E8A21A"
             : m === "synced" ? (dark ? "#8DB85A" : "#3DA35D") : (dark ? "#A3A9B6" : "#7A8299")
    }
    // Estado general: el peor de los módulos (rojo > amarillo > pendiente > al día).
    readonly property string overallSync: {
        var order = ["error", "offline", "attention", "syncing", "pending", "synced", "unknown"]
        var a = order.indexOf(renditionsSync), b = order.indexOf(calicatasSync)
        if (a < 0) a = order.length - 1
        if (b < 0) b = order.length - 1
        return order[Math.min(a, b)]
    }
    signal closeRequested()
    signal signOutRequested()
    signal notificationsToggled()
    signal liquidGlassToggled(bool value)
    signal reduceMotionToggled(bool value)
    signal biometricToggled(bool value)
    signal passwordResetRequested()
    signal storageRefreshRequested()
    signal sectionRequested(string key)

    // Tema: claro u oscuro (ui.darkTheme lo resuelve HomeScreen, incluido «Automático»).
    property string theme: "light"
    signal themeSelected(string key)
    property string skin: "none"                     // none | galaxias | ingema
    signal skinSelected(string key)
    readonly property bool dark: !!ui && ui.darkTheme === true
    readonly property color ink: dark ? "#F2F4F8" : "#151A30"
    readonly property color muted: dark ? "#A3A9B6" : "#5A6378"
    // Azul corporativo #0654A2 → azul claro en oscuro; verde #486426 → verde claro.
    readonly property color accent: dark ? "#8AB8FF" : "#0654A2"
    // Verde Ingema (#486426) en tono medio para acentos del modo oscuro.
    readonly property color green: "#5F8A36"
    readonly property color accentSoft: dark ? Qt.rgba(138 / 255, 184 / 255, 255 / 255, 0.14) : Qt.rgba(31 / 255, 111 / 255, 214 / 255, 0.10)
    function initials(name) {
        var parts = String(name || "").trim().split(/\s+/)
        return String((parts[0] || "").charAt(0) + (parts.length > 1 ? parts[parts.length - 1].charAt(0) : "")).toUpperCase()
    }
    function bytes(v) {
        var n = Number(v)
        if (!isFinite(n) || n < 0) return "—"
        var units = ["B", "KB", "MB", "GB", "TB"], i = 0
        while (n >= 1024 && i < units.length - 1) { n /= 1024; i++ }
        return (i === 0 ? n.toFixed(0) : n.toFixed(n >= 100 ? 0 : 1)) + " " + units[i]
    }
    // «Hace 2 horas», «Hace 3 días»… a partir de una fecha ISO.
    function ago(iso) {
        var t = Date.parse(String(iso || ""))
        if (isNaN(t)) return ""
        var m = Math.max(0, Math.round((Date.now() - t) / 60000))
        if (m < 2) return "Ahora"
        if (m < 60) return "Hace " + m + " min"
        var h = Math.round(m / 60)
        if (h < 24) return "Hace " + h + (h === 1 ? " hora" : " horas")
        var d = Math.round(h / 24)
        return "Hace " + d + (d === 1 ? " día" : " días")
    }
    function deviceGlyph(platform) {
        var p = String(platform || "").toLowerCase()
        return p === "android" || p === "ios" ? 0xE163 : (p === "web" ? 0xE1CD : 0xE11D)
    }
    // Abre una sección directamente (p. ej. el antiguo acceso «Perfil» → Mi cuenta).
    function openPage(key) {
        var pages = { account: accountPage, personal: personalPage, devices: devicesPage,
                      accounts: accountsPage, security: privacyPage, storage: storagePage,
                      about: aboutPage, company: companyPage, sync: syncPage, appearance: appearancePage }
        if (pages[key]) stack.push(pages[key], key === "security" ? { title: "Inicio de sesión y seguridad" } : {})
    }
    function handleBack() { if (stack.depth > 1) { stack.pop(); return true } return false }
    // Al abrir: vuelve a la raíz y repite la entrada del contenido.
    onVisibleChanged: if (visible) {
        if (stack.depth > 1) stack.pop(null, StackView.Immediate)
        if (stack.currentItem && stack.currentItem.replay) stack.currentItem.replay()
        if (pendingPage.length) { openPage(pendingPage); pendingPage = "" }
    }
    property string pendingPage: ""                   // sección a abrir al mostrarse

    // ---- Fondo: foto del Home desenfocada, velo claro y auras de estado
    Rectangle { anchors.fill: parent; color: app.dark ? "#0A0A0A" : "#F3F6FB" }
    Image { id: photo; anchors.fill: parent; source: app.backgroundSource; fillMode: Image.PreserveAspectCrop; visible: false; asynchronous: true }
    MultiEffect { anchors.fill: parent; source: photo; visible: photo.status === Image.Ready && !app.dark; blurEnabled: app.liquidGlass; blurMax: 64; blur: 1.0; autoPaddingEnabled: false }
    Rectangle { anchors.fill: parent; color: app.dark ? "transparent"
                                                      : Qt.rgba(243 / 255, 246 / 255, 251 / 255, app.liquidGlass ? 0.62 : 0.90) }
    RendicionesSyncBackdrop {                          // claro: auras · oscuro: aurora · skin Galaxias: universo
        anchors.fill: parent
        mode: app.syncMode
        dark: app.dark
        skin: app.skin
        running: app.visible
        reducedMotion: app.reduceMotion || app.ui.reducedMotion === true
    }

    StackView {
        id: stack
        anchors.fill: parent
        initialItem: homePage
        pushEnter: Transition { ParallelAnimation {
            NumberAnimation { property: "x"; from: stack.width * 0.3; to: 0; duration: app.ui.reducedMotion ? 0 : 340; easing.type: Easing.OutQuint }
            NumberAnimation { property: "opacity"; from: 0; to: 1; duration: app.ui.reducedMotion ? 0 : 240 } } }
        pushExit: Transition { NumberAnimation { property: "opacity"; from: 1; to: 0; duration: app.ui.reducedMotion ? 0 : 200 } }
        popEnter: Transition { NumberAnimation { property: "opacity"; from: 0; to: 1; duration: app.ui.reducedMotion ? 0 : 240 } }
        popExit: Transition { ParallelAnimation {
            NumberAnimation { property: "x"; from: 0; to: stack.width * 0.3; duration: app.ui.reducedMotion ? 0 : 280; easing.type: Easing.InCubic }
            NumberAnimation { property: "opacity"; from: 1; to: 0; duration: app.ui.reducedMotion ? 0 : 220 } } }
    }

    component SectionLabel: Text {
        leftPadding: 4 * app.ui.u; topPadding: 4 * app.ui.u; color: app.muted
        font.family: app.ui.fontFamily; font.pixelSize: 12 * app.ui.u; font.weight: Font.DemiBold; font.capitalization: Font.AllUppercase
    }
    component Avatar: Rectangle {
        property real size: 56
        width: size * app.ui.u; height: width; radius: width / 2
        gradient: Gradient { GradientStop { position: 0; color: app.dark ? "#6E9A42" : "#2F7BD0" } GradientStop { position: 1; color: app.dark ? app.green : "#0654A2" } }
        id: avatarRoot
        property bool camera: false                    // insignia de cámara: abre el selector de foto
        Text { anchors.centerIn: parent; visible: avatarPhoto.status !== Image.Ready; text: app.initials(app.userName); color: "white"
               font.family: app.ui.fontFamily; font.pixelSize: parent.width * 0.36; font.weight: Font.Bold }
        Image { id: avatarPhoto; anchors.fill: parent; source: app.avatarSource; visible: false; asynchronous: true
                fillMode: Image.PreserveAspectCrop; sourceSize.width: 256; sourceSize.height: 256 }
        Rectangle { id: avatarMask; anchors.fill: parent; radius: width / 2; visible: false; layer.enabled: true }
        MultiEffect { anchors.fill: parent; source: avatarPhoto; visible: avatarPhoto.status === Image.Ready
                      maskEnabled: true; maskSource: avatarMask }
        Rectangle {
            visible: avatarRoot.camera
            anchors.right: parent.right; anchors.bottom: parent.bottom
            width: parent.width * 0.32; height: width; radius: width / 2
            color: app.accent; border.width: 2 * app.ui.u; border.color: "white"
            Text { anchors.centerIn: parent; text: String.fromCharCode(0xE064); color: "white"
                   font.family: app.ui.iconFamily; font.pixelSize: parent.width * 0.5 }
        }
        MouseArea { anchors.fill: parent; enabled: avatarRoot.camera; onClicked: avatarDialog.open() }
    }
    component ActionButton: Rectangle {             // botón ancho: «Guardar cambios» o «Cerrar sesión»
        id: actionRoot
        property string label: ""
        property int glyph: 0
        property bool danger: false
        property bool busy: false
        signal activated()
        width: parent ? parent.width : 0; height: 54 * app.ui.u; radius: 16 * app.ui.u
        color: danger ? (app.dark ? Qt.rgba(0.45, 0.10, 0.14, 0.45) : Qt.rgba(1, 0.92, 0.92, 0.85)) : (app.dark ? app.green : "#0654A2")
        border.width: danger ? 1.5 : 0; border.color: "#E7838B"
        opacity: busy ? 0.6 : 1
        scale: actionTap.pressed ? 0.98 : 1
        Behavior on scale { NumberAnimation { duration: 110; easing.type: Easing.OutCubic } }
        Row {
            anchors.centerIn: parent; spacing: 10 * app.ui.u
            Text { visible: actionRoot.glyph > 0; anchors.verticalCenter: parent.verticalCenter; text: String.fromCharCode(actionRoot.glyph)
                   color: actionRoot.danger ? "#D64550" : "white"; font.family: app.ui.iconFamily; font.pixelSize: 19 * app.ui.u }
            Text { anchors.verticalCenter: parent.verticalCenter; text: actionRoot.label; color: actionRoot.danger ? "#D64550" : "white"
                   font.family: app.ui.fontFamily; font.pixelSize: 16 * app.ui.u; font.weight: Font.DemiBold }
        }
        MouseArea { id: actionTap; anchors.fill: parent; enabled: !actionRoot.busy; onClicked: actionRoot.activated() }
        Accessible.role: Accessible.Button
        Accessible.name: label
    }
    component FieldBox: Rectangle {                 // campo con etiqueta (editable o solo lectura)
        id: fieldRoot
        property string label: ""
        property alias text: fieldInput.text
        property bool editable: true
        property int inputHints: Qt.ImhNone
        property int glyph: 0                          // icono en baldosa a la izquierda
        property bool chevron: false
        readonly property real textX: glyph > 0 ? 70 * app.ui.u : 16 * app.ui.u
        width: parent ? parent.width : 0; height: 72 * app.ui.u; radius: 16 * app.ui.u
        color: app.dark ? Qt.rgba(28 / 255, 45 / 255, 80 / 255, (editable ? 0.70 : 0.45))
                        : (editable ? Qt.rgba(1, 1, 1, 0.92) : Qt.rgba(236 / 255, 241 / 255, 248 / 255, 0.85))
        border.width: fieldInput.activeFocus ? 2 : 1
        border.color: fieldInput.activeFocus ? "#2F7BD0" : (app.dark ? Qt.rgba(1, 1, 1, 0.10) : Qt.rgba(21 / 255, 26 / 255, 48 / 255, 0.08))
        Rectangle {
            visible: fieldRoot.glyph > 0
            x: 14 * app.ui.u; anchors.verticalCenter: parent.verticalCenter
            width: 42 * app.ui.u; height: width; radius: 12 * app.ui.u
            color: app.accentSoft
            Text { anchors.centerIn: parent; text: String.fromCharCode(fieldRoot.glyph); color: app.accent
                   font.family: app.ui.iconFamily; font.pixelSize: 20 * app.ui.u }
        }
        Text { visible: fieldRoot.chevron; anchors.right: parent.right; anchors.rightMargin: 12 * app.ui.u; anchors.verticalCenter: parent.verticalCenter
               text: String.fromCharCode(0xE06F); color: "#5A6378"; font.family: app.ui.iconFamily; font.pixelSize: 18 * app.ui.u }
        Text { x: fieldRoot.textX; y: 12 * app.ui.u; text: fieldRoot.label; color: app.muted
               font.family: app.ui.fontFamily; font.pixelSize: 13 * app.ui.u }
        TextInput {
            id: fieldInput
            x: fieldRoot.textX; y: 36 * app.ui.u; width: parent.width - x - (fieldRoot.chevron ? 34 : 14) * app.ui.u
            readOnly: !fieldRoot.editable; clip: true; autoScroll: activeFocus
            color: fieldRoot.editable ? app.ink : (app.dark ? "#C9D1E2" : "#3A4258"); selectByMouse: fieldRoot.editable
            inputMethodHints: fieldRoot.inputHints
            font.family: app.ui.fontFamily; font.pixelSize: 16.5 * app.ui.u
        }
    }
    component Card: SettingsGroup { ui: app.ui }
    component Pill: Rectangle {
        property alias text: pillText.text
        property color tone: app.dark ? "#A8CF7F" : "#486426"
        width: pillText.implicitWidth + 26 * app.ui.u; height: 24 * app.ui.u; radius: height / 2
        color: Qt.rgba(tone.r, tone.g, tone.b, 0.12)
        Rectangle { x: 9 * app.ui.u; anchors.verticalCenter: parent.verticalCenter; width: 7 * app.ui.u; height: width; radius: width / 2; color: parent.tone }
        Text { id: pillText; x: 20 * app.ui.u; anchors.verticalCenter: parent.verticalCenter; color: parent.tone
               font.family: app.ui.fontFamily; font.pixelSize: 12 * app.ui.u; font.weight: Font.DemiBold }
    }
    component InfoCard: Card {
        property int glyph: 0xE0F9
        property color tone: app.accent
        property string heading: ""
        property string body: ""
        Item {
            width: parent.width; height: Math.max(76 * app.ui.u, infoText.implicitHeight + 28 * app.ui.u)
            Rectangle { id: infoTile; x: 14 * app.ui.u; anchors.verticalCenter: parent.verticalCenter; width: 44 * app.ui.u; height: width; radius: width / 2
                        color: Qt.rgba(infoCardRoot.tone.r, infoCardRoot.tone.g, infoCardRoot.tone.b, 0.12)
                        Text { anchors.centerIn: parent; text: String.fromCharCode(infoCardRoot.glyph); color: infoCardRoot.tone
                               font.family: app.ui.iconFamily; font.pixelSize: 21 * app.ui.u } }
            Column { id: infoText; x: 72 * app.ui.u; width: parent.width - x - 16 * app.ui.u; anchors.verticalCenter: parent.verticalCenter; spacing: 3 * app.ui.u
                     Text { width: parent.width; visible: text.length > 0; text: infoCardRoot.heading; color: infoCardRoot.tone; wrapMode: Text.WordWrap
                            font.family: app.ui.fontFamily; font.pixelSize: 15 * app.ui.u; font.weight: Font.Bold }
                     Text { width: parent.width; text: infoCardRoot.body; color: app.muted; wrapMode: Text.WordWrap
                            font.family: app.ui.fontFamily; font.pixelSize: 13 * app.ui.u } }
        }
        id: infoCardRoot
    }

    // ================================================================ Inicio
    Component {
        id: homePage
        SettingsPage {
            ui: app.ui; title: "Configuración"
            onBack: app.closeRequested()
            Card {
                Item {
                    width: parent.width; height: 96 * app.ui.u
                    Avatar { x: 16 * app.ui.u; anchors.verticalCenter: parent.verticalCenter }
                    Column {
                        x: 86 * app.ui.u; width: parent.width - x - 40 * app.ui.u; anchors.verticalCenter: parent.verticalCenter; spacing: 4 * app.ui.u
                        Text { width: parent.width; text: app.userName; elide: Text.ElideRight; color: app.ink
                               font.family: app.ui.fontFamily; font.pixelSize: 17 * app.ui.u; font.weight: Font.Bold }
                        Text { width: parent.width; text: app.userEmail; elide: Text.ElideRight; color: app.muted
                               font.family: app.ui.fontFamily; font.pixelSize: 13 * app.ui.u }
                        Pill { text: "Cuenta actual" }
                    }
                    Text { anchors.right: parent.right; anchors.rightMargin: 16 * app.ui.u; anchors.verticalCenter: parent.verticalCenter
                           text: String.fromCharCode(0xE06F); color: "#7A8299"; font.family: app.ui.iconFamily; font.pixelSize: 18 * app.ui.u }
                    MouseArea { anchors.fill: parent; onClicked: stack.push(accountPage) }
                }
            }
            SectionLabel { text: "Configuración de la app" }
            Card { SettingsRow { ui: app.ui; glyph: 0xE1DD; tone: "#2F7BD0"; title: "Apariencia"; subtitle: "Tema y efectos visuales"; value: ({ light: "Claro", dark: "Oscuro", auto: "Automático" })[app.theme] || "Claro"; last: true
                                 onClicked: stack.push(appearancePage) } }
            Card { SettingsRow { ui: app.ui; glyph: 0xE059; tone: "#D64550"; title: "Notificaciones"; subtitle: "Alertas y avisos"; value: app.notificationsText; last: true
                                 onClicked: app.notificationsToggled() } }
            Card { SettingsRow { ui: app.ui; glyph: 0xE145; tone: "#3DA35D"; title: "Sincronización"; subtitle: "Datos locales y servidor"; last: true
                                 value: app.syncText.length ? app.syncText + " ●" : ""
                                 valueColor: app.syncMode === "error" || app.syncMode === "offline" ? "#C62F3E"
                                           : app.syncMode === "attention" || app.syncMode === "pending" ? "#B7860F" : "#3DA35D"
                                 onClicked: stack.push(syncPage) } }
            Card { SettingsRow { ui: app.ui; glyph: 0xE10B; tone: "#7B61D1"; title: "Privacidad y seguridad"; subtitle: "Acceso y protección"; last: true
                                 onClicked: stack.push(privacyPage) } }
            Card { SettingsRow { ui: app.ui; glyph: 0xE088; tone: "#E8A21A"; title: "Almacenamiento"; subtitle: "Espacio en el servidor"; last: true
                                 value: app.storageStats && app.storageStats.used !== undefined ? app.bytes(app.storageStats.used) : ""
                                 onClicked: { app.storageRefreshRequested(); stack.push(storagePage) } } }
            Card { SettingsRow { ui: app.ui; glyph: 0xE0F9; tone: "#2F7BD0"; title: "Acerca de InGe+"; subtitle: "Versión y soporte"; last: true
                                 onClicked: stack.push(aboutPage) } }
            InfoCard { glyph: 0xE412; heading: "Consejo"; body: "Mantén tu app sincronizada para trabajar siempre con la información más reciente." }
        }
    }

    FileDialog {
        id: avatarDialog
        title: "Foto de perfil"
        fileMode: FileDialog.OpenFile
        nameFilters: ["Imágenes (*.png *.jpg *.jpeg)"]
        onAccepted: app.avatarChosen(selectedFile)
    }
    component Notice: Text {                        // aviso de resultado (guardado, sesiones…)
        width: parent ? parent.width : 0; visible: text.length > 0; wrapMode: Text.WordWrap
        leftPadding: 4 * app.ui.u; color: app.muted; font.family: app.ui.fontFamily; font.pixelSize: 13 * app.ui.u
    }

    // ============================================================= Mi cuenta
    Component {
        id: accountPage
        SettingsPage {
            ui: app.ui; title: "Mi cuenta"
            onBack: stack.pop()
            Component.onCompleted: app.sessionsRefreshRequested()
            Column {
                width: parent.width; topPadding: 6 * app.ui.u; bottomPadding: 6 * app.ui.u; spacing: 8 * app.ui.u
                Avatar { size: 96; camera: true; anchors.horizontalCenter: parent.horizontalCenter }
                Text { width: parent.width; horizontalAlignment: Text.AlignHCenter; text: app.userName; color: app.ink; elide: Text.ElideRight
                       font.family: app.ui.fontFamily; font.pixelSize: 22 * app.ui.u; font.weight: Font.Bold }
                Text { width: parent.width; horizontalAlignment: Text.AlignHCenter; text: app.userEmail; color: app.muted; elide: Text.ElideMiddle
                       font.family: app.ui.fontFamily; font.pixelSize: 14 * app.ui.u }
                Pill { anchors.horizontalCenter: parent.horizontalCenter; text: "Cuenta activa" }
            }
            Card {
                SettingsRow { ui: app.ui; glyph: 0xE19F; tone: "#2F7BD0"; title: "Información personal"; subtitle: "Nombre, correo, foto de perfil"
                              onClicked: stack.push(personalPage) }
                SettingsRow { ui: app.ui; glyph: 0xE158; tone: app.accent; title: "Inicio de sesión y seguridad"; subtitle: "Contraseña, verificación en dos pasos"
                              onClicked: stack.push(privacyPage, { title: "Inicio de sesión y seguridad" }) }
                SettingsRow { ui: app.ui; glyph: 0xE11D; tone: "#3DA35D"; title: "Dispositivos"; subtitle: "Dispositivos donde iniciaste sesión"
                              value: app.sessions.length > 0 ? String(app.sessions.length) : ""
                              onClicked: stack.push(devicesPage) }
                SettingsRow { ui: app.ui; glyph: 0xE1A4; tone: "#7A8299"; title: "Cuentas"; subtitle: "Cuentas guardadas en InGe+"; last: true
                              value: app.savedAccounts.length > 0 ? String(app.savedAccounts.length) : ""
                              onClicked: stack.push(accountsPage) }
            }
            Card {
                SettingsRow { ui: app.ui; glyph: 0xE1DA; tone: "#3DA35D"; title: "Encuéntrame"; subtitle: "Próximamente"; enabledRow: false; chevron: false }
                SettingsRow { ui: app.ui; glyph: 0xE1A4; tone: "#2F7BD0"; title: "Compartir con equipo"; subtitle: "Próximamente"; enabledRow: false; chevron: false; last: true }
            }
            ActionButton { danger: true; glyph: 0xE10E; label: "Cerrar sesión"; onActivated: app.signOutRequested() }
        }
    }

    // =================================================== Información personal
    Component {
        id: personalPage
        SettingsPage {
            id: personal
            ui: app.ui; title: ""
            onBack: stack.pop()
            bottomBar: Component {
                ActionButton {
                    label: app.profileSaving ? "Guardando…" : "Guardar cambios"; busy: app.profileSaving
                    onActivated: {
                        Qt.inputMethod.hide()
                        app.profileSaveRequested(personal.nameField.text.trim(), personal.lastField.text.trim(), personal.phoneField.text.trim())
                    }
                }
            }
            property alias nameField: nameField
            property alias lastField: lastField
            property alias phoneField: phoneField
            Column {
                width: parent.width; spacing: 4 * app.ui.u; bottomPadding: 6 * app.ui.u
                Text { text: "Información personal"; color: app.ink
                       font.family: app.ui.fontFamily; font.pixelSize: 30 * app.ui.u; font.weight: Font.Bold }
                Text { width: parent.width; wrapMode: Text.WordWrap; text: "Administra los datos visibles en tu perfil."; color: app.muted
                       font.family: app.ui.fontFamily; font.pixelSize: 15 * app.ui.u }
            }
            Card {                                         // foto de perfil
                Item {
                    width: parent.width; height: 132 * app.ui.u
                    Rectangle {                            // brillo diagonal del vidrio
                        anchors.fill: parent; radius: 22 * app.ui.u; opacity: app.dark ? 0 : 0.55
                        gradient: Gradient { orientation: Gradient.Horizontal
                            GradientStop { position: 0.0; color: Qt.rgba(1, 1, 1, 0) }
                            GradientStop { position: 1.0; color: Qt.rgba(197 / 255, 220 / 255, 248 / 255, 0.7) } }
                    }
                    Avatar { id: bigAvatar; size: 92; camera: true; x: 22 * app.ui.u; anchors.verticalCenter: parent.verticalCenter }
                    Rectangle { id: photoDivider; x: bigAvatar.x + bigAvatar.width + 20 * app.ui.u; anchors.verticalCenter: parent.verticalCenter
                                width: 1; height: 72 * app.ui.u; color: Qt.rgba(21 / 255, 26 / 255, 48 / 255, 0.10) }
                    Column {
                        x: photoDivider.x + 20 * app.ui.u; width: parent.width - x - 14 * app.ui.u
                        anchors.verticalCenter: parent.verticalCenter; spacing: 6 * app.ui.u
                        Text { text: "Foto de perfil"; color: app.ink; font.family: app.ui.fontFamily; font.pixelSize: 16 * app.ui.u; font.weight: Font.Bold }
                        Text { text: "PNG, JPG · Máx. 5 MB"; color: app.muted; font.family: app.ui.fontFamily; font.pixelSize: 13 * app.ui.u }
                        Rectangle {
                            width: Math.min(parent.width, updateRow.implicitWidth + 28 * app.ui.u); height: 40 * app.ui.u; radius: 12 * app.ui.u
                            color: updateTap.pressed ? Qt.rgba(6 / 255, 84 / 255, 162 / 255, 0.08) : "transparent"
                            border.width: 1.5; border.color: app.accent
                            scale: updateTap.pressed ? 0.97 : 1
                            Behavior on scale { NumberAnimation { duration: 110 } }
                            Row { id: updateRow; anchors.centerIn: parent; spacing: 8 * app.ui.u
                                  Text { anchors.verticalCenter: parent.verticalCenter; text: String.fromCharCode(0xE064); color: app.accent
                                         font.family: app.ui.iconFamily; font.pixelSize: 18 * app.ui.u }
                                  Text { anchors.verticalCenter: parent.verticalCenter; text: "Actualizar foto"; color: app.accent
                                         font.family: app.ui.fontFamily; font.pixelSize: 14.5 * app.ui.u; font.weight: Font.DemiBold } }
                            MouseArea { id: updateTap; anchors.fill: parent; onClicked: avatarDialog.open() }
                        }
                    }
                }
            }
            Item {                                         // encabezado de sección
                width: parent.width; height: 52 * app.ui.u
                Rectangle { id: secTile; x: 2 * app.ui.u; anchors.verticalCenter: parent.verticalCenter
                            width: 42 * app.ui.u; height: width; radius: 12 * app.ui.u; color: app.accentSoft
                            Text { anchors.centerIn: parent; text: String.fromCharCode(0xE19F); color: app.accent
                                   font.family: app.ui.iconFamily; font.pixelSize: 20 * app.ui.u } }
                Text { x: secTile.x + secTile.width + 16 * app.ui.u; anchors.verticalCenter: parent.verticalCenter; text: "Datos de la cuenta"
                       color: app.ink; font.family: app.ui.fontFamily; font.pixelSize: 18 * app.ui.u; font.weight: Font.Bold }
            }
            Row {
                width: parent.width; spacing: 12 * app.ui.u
                FieldBox { id: nameField; width: (parent.width - parent.spacing) / 2; label: "Nombres"; text: app.firstName
                           inputHints: Qt.ImhNoPredictiveText }
                FieldBox { id: lastField; width: (parent.width - parent.spacing) / 2; label: "Apellidos"; text: app.lastName
                           inputHints: Qt.ImhNoPredictiveText }
            }
            FieldBox { label: "Correo principal"; text: app.userEmail; editable: false; glyph: 0xE10F }
            Row {
                width: parent.width; spacing: 12 * app.ui.u
                FieldBox { width: (parent.width - parent.spacing) / 2; label: "Cargo"; editable: false; glyph: 0xE062; chevron: true
                           text: app.userPosition.length ? app.userPosition : "Sin asignar" }
                FieldBox { width: (parent.width - parent.spacing) / 2; label: "Área"; editable: false; glyph: 0xE1A4; chevron: true
                           text: app.userArea.length ? app.userArea : "Sin asignar" }
            }
            FieldBox { id: phoneField; label: "Teléfono (opcional)"; text: app.userPhone; glyph: 0xE133
                       inputHints: Qt.ImhDialableCharactersOnly }
            Rectangle {                                    // nota informativa
                width: parent.width; height: Math.max(60 * app.ui.u, noteText.implicitHeight + 28 * app.ui.u); radius: 16 * app.ui.u
                color: app.dark ? Qt.rgba(95 / 255, 138 / 255, 54 / 255, 0.28) : app.accentSoft
                Text { id: noteIcon; x: 18 * app.ui.u; anchors.verticalCenter: parent.verticalCenter; text: String.fromCharCode(0xE0F9)
                       color: app.dark ? "#9CC46F" : "#0654A2"; font.family: app.ui.iconFamily; font.pixelSize: 22 * app.ui.u }
                Rectangle { id: noteDivider; x: noteIcon.x + noteIcon.width + 14 * app.ui.u; anchors.verticalCenter: parent.verticalCenter
                            width: 1; height: 30 * app.ui.u; color: (app.dark ? Qt.rgba(156 / 255, 196 / 255, 111 / 255, 0.35) : Qt.rgba(6 / 255, 84 / 255, 162 / 255, 0.2)) }
                Text { id: noteText; x: noteDivider.x + 14 * app.ui.u; width: parent.width - x - 14 * app.ui.u; anchors.verticalCenter: parent.verticalCenter
                       wrapMode: Text.WordWrap; text: "El cargo y el área los asigna la administración de Ingema."
                       color: app.muted; font.family: app.ui.fontFamily; font.pixelSize: 13.5 * app.ui.u }
            }
            Notice { text: app.accountNotice }
        }
    }

    // Cierra la sesión en todos los demás dispositivos (doble toque para confirmar).
    component SignOutOthersCard: Card {
        id: othersCard
        property bool armed: false
        color: app.dark ? Qt.rgba(0.45, 0.10, 0.14, 0.35) : Qt.rgba(1, 0.93, 0.93, 0.85)
        border.color: app.dark ? Qt.rgba(0.9, 0.4, 0.45, 0.35) : "#F2B8BD"
        SettingsRow { ui: app.ui; glyph: 0xE10E; tone: "#D64550"; titleColor: "#C62F3E"; last: true
                      title: "Cerrar sesión en todos los dispositivos"
                      subtitle: othersCard.armed ? "Toca otra vez para confirmar"
                                                 : "Este teléfono sigue con la sesión abierta"
                      onClicked: {
                          if (!othersCard.armed) { othersCard.armed = true; othersDisarm.restart(); return }
                          othersCard.armed = false
                          app.signOutOthersRequested()
                      } }
        Timer { id: othersDisarm; interval: 4000; onTriggered: othersCard.armed = false }
    }
    // =================================================== Dispositivos (sesiones)
    component DeviceRow: SettingsRow {
        id: deviceRow
        required property var session
        property bool last2: false
        property bool armed: false                     // segundo toque confirma el cierre
        ui: app.ui; glyph: app.deviceGlyph(session.platform); tone: session.current ? app.accent : "#7A8299"
        title: String(session.device_label || "Dispositivo")
        subtitle: armed ? "Toca otra vez para cerrar la sesión ahí"
                        : (session.current ? "Este dispositivo" : [String(session.platform_label || ""), String(session.location || "")]
                                                              .filter(function(x) { return x.length > 0 }).join(" · "))
        value: session.current ? "Actual" : app.ago(session.last_active_at)
        valueColor: session.current ? "#3DA35D" : app.muted
        chevron: !session.current
        onClicked: {
            if (session.current) return
            if (!armed) { armed = true; disarm.restart(); return }
            armed = false
            app.sessionRevokeRequested(String(session.id))
        }
        Timer { id: disarm; interval: 4000; onTriggered: deviceRow.armed = false }
    }
    Component {
        id: devicesPage
        SettingsPage {
            ui: app.ui; title: "Dispositivos"
            onBack: stack.pop()
            Component.onCompleted: app.sessionsRefreshRequested()
            SignOutOthersCard { visible: app.sessions.length > 1 }
            Notice { text: app.securityNotice }
            SectionLabel { text: "Dispositivos con acceso" }
            Card {
                Repeater {
                    model: app.sessions
                    delegate: DeviceRow { required property int index; session: modelData; required property var modelData
                                          last: index === app.sessions.length - 1 }
                }
                Item { visible: app.sessions.length === 0; width: parent.width; height: 64 * app.ui.u
                       Text { anchors.centerIn: parent; text: app.sessionsBusy ? "Consultando el servidor…" : "Sin información de sesiones"
                              color: app.muted; font.family: app.ui.fontFamily; font.pixelSize: 14 * app.ui.u } }
            }
            Notice { text: "Toca un dispositivo para cerrar su sesión. Incluye InGe+ en el teléfono y la versión web en PC." }
        }
    }

    // ===================================================== Cuentas guardadas
    Component {
        id: accountsPage
        SettingsPage {
            ui: app.ui; title: "Cuentas"
            onBack: stack.pop()
            SectionLabel { text: "Cuentas guardadas en este teléfono" }
            Card {
                Repeater {
                    model: app.savedAccounts
                    delegate: SettingsRow {
                        required property var modelData
                        required property int index
                        readonly property bool mine: String(modelData.id) === app.currentAccountId
                        ui: app.ui; glyph: 0xE19F; tone: mine ? app.accent : "#7A8299"
                        title: String(modelData.name || modelData.fullName || modelData.email || "Cuenta")
                        subtitle: String(modelData.email || "")
                        value: mine ? "Actual" : ""; valueColor: "#3DA35D"; chevron: !mine
                        last: index === app.savedAccounts.length - 1
                        onClicked: if (!mine) app.accountSwitchRequested(String(modelData.id))
                    }
                }
            }
            Card { SettingsRow { ui: app.ui; glyph: 0xE1A4; tone: app.accent; title: "Agregar cuenta"; titleColor: app.accent
                                 subtitle: "Inicia sesión con otra cuenta; esta queda guardada"; last: true
                                 onClicked: app.addAccountRequested() } }
            Notice { text: "Toca una cuenta para cambiar a ella." }
        }
    }

    // ============================================== Verificación en dos pasos
    Component {
        id: mfaPage
        SettingsPage {
            objectName: "mfaPage"
            ui: app.ui; title: "Verificación en dos pasos"
            onBack: { app.mfaEnrollment = null }
            readonly property var e: app.mfaEnrollment || ({})
            InfoCard { glyph: 0xE158; heading: "Protege tu cuenta"
                       body: "Al iniciar sesión te pediremos un código de 6 dígitos de una app autenticadora (Google Authenticator, Microsoft Authenticator u otra)." }
            SectionLabel { text: "1. Agrega InGe+ a tu app autenticadora" }
            Card {
                Column {
                    width: parent.width; padding: 16 * app.ui.u; spacing: 12 * app.ui.u
                    Rectangle {                            // QR para escanear desde otro teléfono
                        visible: qrImage.status === Image.Ready
                        anchors.horizontalCenter: parent.horizontalCenter
                        width: 176 * app.ui.u; height: width; radius: 16 * app.ui.u; color: "white"
                        Image { id: qrImage; anchors.fill: parent; anchors.margins: 12 * app.ui.u; source: String(e.qr || "")
                                fillMode: Image.PreserveAspectFit; smooth: false; sourceSize.width: 400; sourceSize.height: 400 }
                    }
                    ActionButton { width: parent.width - 32 * app.ui.u; glyph: 0xE0F9; label: "Abrir en mi app autenticadora"
                                   onActivated: if (String(e.uri || "").length) Qt.openUrlExternally(e.uri) }
                    FieldBox { width: parent.width - 32 * app.ui.u; label: "O escribe esta clave a mano"; editable: false; text: String(e.secret || "") }
                }
            }
            SectionLabel { text: "2. Escribe el código que aparece" }
            FieldBox { id: mfaCode; label: "Código de 6 dígitos"; inputHints: Qt.ImhDigitsOnly }
            ActionButton { label: "Activar verificación"
                           onActivated: { Qt.inputMethod.hide(); app.mfaConfirmRequested(String(e.factorId || ""), mfaCode.text.replace(/\s+/g, "")) } }
            Notice { text: app.securityNotice }
        }
    }

    // ========================================================= Sincronización
    Component {
        id: syncPage
        SettingsPage {
            ui: app.ui; title: "Sincronización"
            onBack: stack.pop()
            Card {
                Column {
                    width: parent.width; topPadding: 22 * app.ui.u; bottomPadding: 22 * app.ui.u; spacing: 8 * app.ui.u
                    Rectangle {
                        anchors.horizontalCenter: parent.horizontalCenter
                        width: 64 * app.ui.u; height: width; radius: width / 2
                        readonly property color tone: app.syncColor(app.overallSync)
                        color: Qt.rgba(tone.r, tone.g, tone.b, 0.16)
                        Behavior on color { ColorAnimation { duration: 300 } }
                        Text {
                            anchors.centerIn: parent; text: String.fromCharCode(app.overallSync === "offline" ? 0xE088 : 0xE145)
                            color: parent.tone; font.family: app.ui.iconFamily; font.pixelSize: 30 * app.ui.u
                            RotationAnimation on rotation { running: app.syncBusy || app.overallSync === "syncing"; loops: Animation.Infinite
                                                            from: 0; to: 360; duration: 1000 }
                        }
                    }
                    Text { width: parent.width; horizontalAlignment: Text.AlignHCenter; color: app.ink
                           font.family: app.ui.fontFamily; font.pixelSize: 20 * app.ui.u; font.weight: Font.Bold
                           text: ({ synced: "Todo al día", pending: "Hay cambios por subir", syncing: "Sincronizando…",
                                    attention: "Hay algo por revisar", error: "Hay errores de sincronización",
                                    offline: "Sin conexión" })[app.overallSync] || "Aún sin datos" }
                    Text { width: parent.width - 40 * app.ui.u; anchors.horizontalCenter: parent.horizontalCenter
                           horizontalAlignment: Text.AlignHCenter; wrapMode: Text.WordWrap; color: app.muted
                           font.family: app.ui.fontFamily; font.pixelSize: 13.5 * app.ui.u
                           text: app.overallSync === "offline" ? "Tus cambios se guardan en el teléfono y se subirán al recuperar la conexión."
                               : app.overallSync === "synced" ? "Tus datos están iguales en el teléfono y en el servidor."
                               : "Abre el módulo marcado para ver el detalle." }
                }
            }
            SectionLabel { text: "Módulos" }
            Card {
                SettingsRow { ui: app.ui; glyph: 0xE3D3; tone: "#2F7BD0"; title: "Rendiciones"; chevron: false
                              subtitle: app.renditionsPending > 0 ? app.renditionsPending + " cambios pendientes" : "Gastos, fondos y documentos"
                              value: app.syncLabel(app.renditionsSync) + " ●"; valueColor: app.syncColor(app.renditionsSync) }
                SettingsRow { ui: app.ui; glyph: 0xE298; tone: "#3DA35D"; title: "Calicatas"; chevron: false; last: true
                              subtitle: "Fichas, fotos y laboratorio"
                              value: app.syncLabel(app.calicatasSync) + " ●"; valueColor: app.syncColor(app.calicatasSync) }
            }
            ActionButton { glyph: 0xE145; label: app.syncBusy ? "Sincronizando…" : "Sincronizar ahora"; busy: app.syncBusy
                           onActivated: app.syncNowRequested() }
            InfoCard { glyph: 0xE088; heading: "Sincronización automática"
                       body: "InGe+ sincroniza solo cuando hay conexión. Lo que hagas sin internet queda guardado en el teléfono." }
        }
    }

    // ============================================================ Apariencia
    Component {
        id: appearancePage
        SettingsPage {
            ui: app.ui; title: "Apariencia"
            onBack: stack.pop()
            SectionLabel { text: "Tema de la app" }
            Row {
                id: themes
                width: parent.width; spacing: 10 * app.ui.u
                Repeater {
                    // Sólo «Claro» por ahora: el tema oscuro aún no tiene diseño aprobado.
                    model: [{ k: "light", l: "Claro", g: 0xE178, bg: "#F3F6FB", bar: "white", on: true },
                            { k: "dark", l: "Oscuro", g: 0xE11E, bg: "#1C2D50", bar: "#2B3A5E", on: true },
                            { k: "auto", l: "Automático", g: 0xE163, bg: "#5A6B8C", bar: "#8FA0BF", on: true }]
                    delegate: Rectangle {
                        id: themeCell
                        required property var modelData
                        readonly property bool on: modelData.k === app.theme
                        width: (themes.width - 2 * themes.spacing) / 3; height: 156 * app.ui.u; radius: 18 * app.ui.u
                        color: on ? Qt.rgba(47 / 255, 123 / 255, 208 / 255, app.dark ? 0.22 : 0.08) : (app.dark ? Qt.rgba(28 / 255, 45 / 255, 80 / 255, 0.55) : Qt.rgba(1, 1, 1, 0.80))
                        border.width: on ? 2 : 1; border.color: on ? "#2F7BD0" : (app.dark ? Qt.rgba(1, 1, 1, 0.10) : "white")
                        scale: cellTap.pressed ? 0.97 : 1
                        Behavior on scale { NumberAnimation { duration: 110 } }
                        Behavior on color { ColorAnimation { duration: 200 } }
                        MouseArea { id: cellTap; anchors.fill: parent; onClicked: app.themeSelected(themeCell.modelData.k) }
                        Text { anchors.horizontalCenter: parent.horizontalCenter; y: 10 * app.ui.u; text: String.fromCharCode(themeCell.modelData.g)
                               color: app.ink; font.family: app.ui.iconFamily; font.pixelSize: 20 * app.ui.u }
                        Rectangle {
                            x: 10 * app.ui.u; y: 40 * app.ui.u; width: parent.width - 20 * app.ui.u; height: 66 * app.ui.u
                            radius: 10 * app.ui.u; color: themeCell.modelData.bg; border.width: 1; border.color: Qt.rgba(0, 0, 0, 0.06)
                            Column { anchors.centerIn: parent; width: parent.width - 16 * app.ui.u; spacing: 6 * app.ui.u
                                     Rectangle { width: parent.width * 0.6; height: 5 * app.ui.u; radius: 3; color: themeCell.modelData.bar }
                                     Rectangle { width: parent.width; height: 16 * app.ui.u; radius: 6; color: themeCell.modelData.bar }
                                     Rectangle { width: parent.width; height: 11 * app.ui.u; radius: 5; color: themeCell.modelData.bar } }
                        }
                        Column {
                            anchors.horizontalCenter: parent.horizontalCenter; anchors.bottom: parent.bottom; anchors.bottomMargin: 10 * app.ui.u
                            Text { anchors.horizontalCenter: parent.horizontalCenter; text: themeCell.modelData.l; color: app.ink
                                   font.family: app.ui.fontFamily; font.pixelSize: 14 * app.ui.u; font.weight: themeCell.on ? Font.Bold : Font.Normal }
                                                    }
                        Rectangle { visible: themeCell.on; anchors.right: parent.right; anchors.top: parent.top; anchors.margins: 8 * app.ui.u
                                    width: 20 * app.ui.u; height: width; radius: width / 2; color: app.accent
                                    Text { anchors.centerIn: parent; text: String.fromCharCode(0xE06C); color: "white"
                                           font.family: app.ui.iconFamily; font.pixelSize: 12 * app.ui.u } }
                        Accessible.role: Accessible.RadioButton
                        Accessible.name: modelData.l
                        Accessible.checked: on
                    }
                }
            }
            SectionLabel { text: "Skins" }
            Flow {
                id: skins
                width: parent.width; spacing: 10 * app.ui.u
                Repeater {
                    model: [{ k: "none", l: "Ninguna", d: "Auras", bg: "#0A0A0A" },
                            { k: "ingema", l: "Ingema", d: "Consultores", bg: "#071A33" },
                            { k: "galaxias", l: "Galaxias", d: "Universo vivo", bg: "#0B0F1E" },
                            { k: "halloween", l: "Halloween", d: "Calabazas y fantasmas", bg: "#2B1047" }]
                    delegate: Rectangle {
                        id: skinCell
                        required property var modelData
                        readonly property bool on: modelData.k === app.skin
                        width: (skins.width - skins.spacing) / 2; height: 132 * app.ui.u; radius: 18 * app.ui.u
                        color: on ? Qt.rgba(47 / 255, 123 / 255, 208 / 255, app.dark ? 0.22 : 0.08) : (app.dark ? Qt.rgba(28 / 255, 45 / 255, 80 / 255, 0.55) : Qt.rgba(1, 1, 1, 0.80))
                        border.width: on ? 2 : 1; border.color: on ? "#2F7BD0" : (app.dark ? Qt.rgba(1, 1, 1, 0.10) : "white")
                        scale: skinTap.pressed ? 0.97 : 1
                        Behavior on scale { NumberAnimation { duration: 110 } }
                        Rectangle {                        // miniatura
                            x: 10 * app.ui.u; y: 10 * app.ui.u; width: parent.width - 20 * app.ui.u; height: 70 * app.ui.u
                            radius: 10 * app.ui.u; color: skinCell.modelData.bg; clip: true
                            Image {
                                anchors.fill: parent; anchors.margins: 10 * app.ui.u
                                visible: skinCell.modelData.k === "ingema"
                                source: "qrc:/images/INGEMA_CONSULTORES_LOGO_NEGATIVO.png"
                                fillMode: Image.PreserveAspectFit
                                smooth: true
                            }
                            Text {                         // miniatura Halloween
                                anchors.centerIn: parent
                                visible: skinCell.modelData.k === "halloween"
                                text: "🎃 👻 🦇"; font.pixelSize: 26 * app.ui.u
                            }
                            Repeater {                     // estrellas de la miniatura Galaxias
                                model: skinCell.modelData.k === "galaxias" ? 18 : 0
                                delegate: Rectangle { required property int index
                                    x: (index * 37 % 97) / 97 * parent.width; y: (index * 53 % 89) / 89 * parent.height
                                    width: index % 5 === 0 ? 3 : 1.6; height: width; radius: width / 2; color: "white"; opacity: 0.85 }
                            }
                            Rectangle {                    // aura de la miniatura «Ninguna»
                                visible: skinCell.modelData.k === "none"
                                width: parent.width * 0.9; height: width; radius: width / 2; x: -width * 0.3; y: -height * 0.55
                                gradient: Gradient { GradientStop { position: 0.0; color: Qt.rgba(138 / 255, 184 / 255, 1, 0.55) }
                                                     GradientStop { position: 1.0; color: Qt.rgba(138 / 255, 184 / 255, 1, 0.0) } }
                            }
                        }
                        Column {
                            anchors.horizontalCenter: parent.horizontalCenter; anchors.bottom: parent.bottom; anchors.bottomMargin: 8 * app.ui.u
                            Text { anchors.horizontalCenter: parent.horizontalCenter; text: skinCell.modelData.l; color: app.ink
                                   font.family: app.ui.fontFamily; font.pixelSize: 14 * app.ui.u; font.weight: skinCell.on ? Font.Bold : Font.Normal }
                            Text { anchors.horizontalCenter: parent.horizontalCenter; color: app.muted
                                   text: skinCell.modelData.d
                                   font.family: app.ui.fontFamily; font.pixelSize: 11 * app.ui.u }
                        }
                        MouseArea { id: skinTap; anchors.fill: parent; onClicked: app.skinSelected(skinCell.modelData.k) }
                        Accessible.role: Accessible.RadioButton
                        Accessible.name: "Skin " + modelData.l
                        Accessible.checked: on
                    }
                }
            }
            SectionLabel { text: "Efectos visuales" }
            Card {
                SettingsRow { ui: app.ui; glyph: 0xE412; tone: "#2F7BD0"; title: "Liquid Glass"; subtitle: "Vidrio, transparencia y desenfoque"; toggle: true
                              checked: app.liquidGlass; onToggled: function(v) { app.liquidGlassToggled(v) } }
                SettingsRow { ui: app.ui; glyph: 0xE297; tone: "#3DA35D"; title: "Reducir movimiento"; subtitle: "Menos animaciones de interfaz"; toggle: true; last: true
                              checked: app.reduceMotion; onToggled: function(v) { app.reduceMotionToggled(v) } }
            }
        }
    }

    // =============================================== Privacidad y seguridad
    Component {
        id: privacyPage
        SettingsPage {
            ui: app.ui; title: "Privacidad y seguridad"
            onBack: stack.pop()
            InfoCard { glyph: 0xE10B; tone: app.accent; heading: "Tu información está segura"; body: "Protegemos tus datos y mantenemos el control en tus manos." }
            SectionLabel { text: "Seguridad de la cuenta" }
            Card {
                SettingsRow { ui: app.ui; glyph: 0xE10F; tone: "#2F7BD0"; title: "Cambiar contraseña"; subtitle: "Te enviamos un enlace a tu correo"
                              onClicked: app.passwordResetRequested() }
                SettingsRow { ui: app.ui; glyph: 0xE297; tone: "#7B61D1"; title: "Desbloqueo con huella o rostro"; last: true
                              subtitle: app.biometricAvailable ? "Desbloquea InGe+ sin escribir tu contraseña" : "No disponible en este dispositivo"
                              toggle: true; enabledRow: app.biometricAvailable && !app.biometricBusy
                              checked: app.biometricEnabled && app.biometricAvailable; onToggled: function(v) { app.biometricToggled(v) } }
            }
            Card {
                SettingsRow { ui: app.ui; glyph: 0xE158; tone: "#2F7BD0"; title: "Verificación en dos pasos"
                              subtitle: app.mfaEnabled ? "Activada con tu app autenticadora" : "Pide un código al iniciar sesión"
                              toggle: true; checked: app.mfaEnabled
                              onToggled: function(v) { app.securityNotice = ""; if (v) app.mfaEnrollRequested(); else app.mfaDisableRequested() } }
                SettingsRow { ui: app.ui; glyph: 0xE087; tone: "#3DA35D"; title: "Sesiones activas"; subtitle: "Revisa los dispositivos con acceso"; last: true
                              value: app.sessions.length > 0 ? String(app.sessions.length) : ""
                              onClicked: stack.push(devicesPage) }
            }
            SectionLabel { text: "Dispositivos de confianza"; visible: app.sessions.length > 0 }
            Card {
                visible: app.sessions.length > 0
                Repeater {
                    model: app.sessions.slice(0, 3)
                    delegate: DeviceRow { required property int index; required property var modelData; session: modelData
                                          last: index === Math.min(3, app.sessions.length) - 1 }
                }
            }
            SignOutOthersCard {}
            Notice { text: app.securityNotice }
            Component.onCompleted: app.sessionsRefreshRequested()
        }
    }

    // ======================================== Almacenamiento (del servidor)
    Component {
        id: storagePage
        SettingsPage {
            id: storageView
            ui: app.ui; title: "Almacenamiento"
            onBack: stack.pop()
            readonly property var stats: app.storageStats || ({})
            readonly property real used: Number(stats.used || 0)
            readonly property real total: Number(stats.total || 0)
            readonly property var parts: Array.isArray(stats.breakdown) ? stats.breakdown : []
            readonly property var palette: ["#2F7BD0", "#3DA35D", "#E8A21A", "#7B61D1", "#D64550"]
            Card {
                Column {
                    x: 16 * app.ui.u; width: parent.width - 32 * app.ui.u; topPadding: 16 * app.ui.u; bottomPadding: 16 * app.ui.u; spacing: 12 * app.ui.u
                    Item {
                        width: parent.width; height: 22 * app.ui.u
                        Text { text: "Espacio en el servidor"; color: app.ink; font.family: app.ui.fontFamily; font.pixelSize: 15 * app.ui.u; font.weight: Font.Bold }
                        Text { anchors.right: parent.right; text: String.fromCharCode(0xE145); color: app.accent; font.family: app.ui.iconFamily; font.pixelSize: 18 * app.ui.u
                               rotation: app.storageBusy ? 360 : 0
                               RotationAnimation on rotation { running: app.storageBusy; loops: Animation.Infinite; from: 0; to: 360; duration: 900 }
                               MouseArea { anchors.fill: parent; anchors.margins: -12 * app.ui.u; onClicked: app.storageRefreshRequested() } }
                    }
                    Row {
                        spacing: 8 * app.ui.u
                        Text { text: app.bytes(storageView.used); color: app.ink; font.family: app.ui.fontFamily; font.pixelSize: 30 * app.ui.u; font.weight: Font.ExtraBold }
                        Text { anchors.baseline: parent.children[0].baseline; text: storageView.total > 0 ? "de " + app.bytes(storageView.total) : "sin límite asignado"
                               color: app.muted; font.family: app.ui.fontFamily; font.pixelSize: 14 * app.ui.u }
                    }
                    Rectangle {                                    // barra de uso con su desglose
                        width: parent.width; height: 12 * app.ui.u; radius: height / 2; color: Qt.rgba(21 / 255, 26 / 255, 48 / 255, 0.08); clip: true
                        Row {
                            height: parent.height
                            Repeater {
                                model: storageView.parts
                                delegate: Rectangle {
                                    required property var modelData
                                    required property int index
                                    readonly property real size: Number(modelData.bytes || modelData.used || modelData.size || 0)
                                    height: parent.height; color: storageView.palette[index % storageView.palette.length]
                                    width: storageView.total > 0 ? parent.parent.width * size / storageView.total : 0
                                    Behavior on width { NumberAnimation { duration: 600; easing.type: Easing.OutCubic } }
                                }
                            }
                        }
                        Rectangle { visible: storageView.parts.length === 0; height: parent.height; radius: parent.radius; color: "#2F7BD0"
                                    width: storageView.total > 0 ? parent.width * Math.min(1, storageView.used / storageView.total) : 0
                                    Behavior on width { NumberAnimation { duration: 600; easing.type: Easing.OutCubic } } }
                    }
                    Repeater {
                        model: storageView.parts
                        delegate: Item {
                            required property var modelData
                            required property int index
                            width: parent.width; height: 24 * app.ui.u
                            Rectangle { anchors.verticalCenter: parent.verticalCenter; width: 10 * app.ui.u; height: width; radius: width / 2
                                        color: storageView.palette[index % storageView.palette.length] }
                            Text { x: 20 * app.ui.u; anchors.verticalCenter: parent.verticalCenter; color: app.ink
                                   text: String(modelData.label || modelData.category || modelData.kind || modelData.name || "Otros")
                                   font.family: app.ui.fontFamily; font.pixelSize: 14 * app.ui.u }
                            Text { anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter; color: app.muted
                                   text: app.bytes(modelData.bytes || modelData.used || modelData.size || 0)
                                   font.family: app.ui.fontFamily; font.pixelSize: 14 * app.ui.u }
                        }
                    }
                    Text { visible: storageView.total > 0; width: parent.width; color: app.muted
                           text: "Disponible: " + app.bytes(storageView.stats.remaining) + " · " + Math.round(100 * storageView.used / storageView.total) + " % usado"
                           font.family: app.ui.fontFamily; font.pixelSize: 13 * app.ui.u }
                    Text { visible: app.storageBusy && storageView.used === 0; text: "Consultando el servidor…"; color: app.muted
                           font.family: app.ui.fontFamily; font.pixelSize: 13 * app.ui.u }
                    Text { visible: app.storageError.length > 0; width: parent.width; text: app.storageError; wrapMode: Text.WordWrap; color: "#C62F3E"
                           font.family: app.ui.fontFamily; font.pixelSize: 13 * app.ui.u }
                }
            }
            InfoCard { glyph: 0xE088; heading: ""; body: "Este es el espacio del servidor de InGe+ (InGe Drive y documentos del proyecto). No incluye lo guardado solo en este teléfono." }
        }
    }

    // ============================================================= Acerca de
    Component {
        id: aboutPage
        SettingsPage {
            ui: app.ui; title: "Acerca de InGe+"
            onBack: stack.pop()
            Card {                                     // marca InGe+ sobre vidrio
                Column {
                    width: parent.width; topPadding: 22 * app.ui.u; bottomPadding: 22 * app.ui.u; spacing: 8 * app.ui.u
                    Item {
                        anchors.horizontalCenter: parent.horizontalCenter
                        width: 150 * app.ui.u; height: width
                        Rectangle {                    // halo suave detrás del logo
                            anchors.centerIn: parent; width: parent.width * 0.9; height: width; radius: width / 2
                            color: app.accentSoft
                        }
                        Image {
                            id: brandLogo
                            anchors.fill: parent; source: "qrc:/images/INGEPLUS_LOGO_2026.png"
                            fillMode: Image.PreserveAspectFit; smooth: true; mipmap: true; asynchronous: true
                            sourceSize.width: 512; sourceSize.height: 512
                            transform: Translate { id: logoFloat }
                            SequentialAnimation on opacity {   // aparece al abrir
                                running: true
                                NumberAnimation { from: 0; to: 1; duration: app.ui.reducedMotion ? 0 : 520; easing.type: Easing.OutCubic }
                            }
                        }
                        SequentialAnimation {          // flota levemente
                            running: !app.ui.reducedMotion && app.visible; loops: Animation.Infinite
                            NumberAnimation { target: logoFloat; property: "y"; from: 0; to: -5 * app.ui.u; duration: 2200; easing.type: Easing.InOutSine }
                            NumberAnimation { target: logoFloat; property: "y"; from: -5 * app.ui.u; to: 0; duration: 2200; easing.type: Easing.InOutSine }
                        }
                    }
                    Text { anchors.horizontalCenter: parent.horizontalCenter; text: "InGe<font color='" + app.accent + "'>+</font>"; textFormat: Text.StyledText
                           color: app.dark ? app.ink : "#0B1F4D"; font.family: app.ui.fontFamily; font.pixelSize: 46 * app.ui.u; font.weight: Font.Black }
                    Text { anchors.horizontalCenter: parent.horizontalCenter; text: "Gestión geotécnica en campo"; color: app.ink
                           font.family: app.ui.fontFamily; font.pixelSize: 17 * app.ui.u }
                    Rectangle {
                        anchors.horizontalCenter: parent.horizontalCenter
                        width: tagText.implicitWidth + 28 * app.ui.u; height: 30 * app.ui.u; radius: height / 2
                        color: Qt.rgba(31 / 255, 111 / 255, 214 / 255, 0.12); border.width: 1; border.color: Qt.rgba(31 / 255, 111 / 255, 214 / 255, 0.25)
                        Text { id: tagText; anchors.centerIn: parent; text: "Tecnología aplicada a la ingeniería"; color: app.accent
                               font.family: app.ui.fontFamily; font.pixelSize: 13.5 * app.ui.u; font.weight: Font.DemiBold }
                    }
                }
            }
            Card {
                SettingsRow { ui: app.ui; glyph: 0xE0F9; tone: "#2F7BD0"; title: "Versión"; subtitle: "Versión actual de la aplicación"; value: app.appVersion; chevron: false }
                SettingsRow { ui: app.ui; glyph: 0xE163; tone: "#2F7BD0"; title: "Sistema"; subtitle: "Plataforma de la aplicación"
                              value: Qt.platform.os === "android" ? "Android" : Qt.platform.os; chevron: false }
                SettingsRow { ui: app.ui; glyph: 0xE1CC; tone: "#2F7BD0"; title: "Empresa"; subtitle: "Desarrollado para"; value: "INGEMA"; last: true
                              onClicked: stack.push(companyPage) }
            }
        }
    }

    // ===================================================== INGEMA Consultores
    Component {
        id: companyPage
        SettingsPage {
            ui: app.ui; title: "INGEMA Consultores"
            onBack: stack.pop()
            Card {
                Column {
                    width: parent.width; padding: 22 * app.ui.u; spacing: 14 * app.ui.u
                    Row {                                  // Ingema (hija) junto a HVA Group (matriz)
                        id: brandRow
                        readonly property real avail: parent.width - 44 * app.ui.u
                        anchors.horizontalCenter: parent.horizontalCenter
                        spacing: 14 * app.ui.u
                        Image { width: brandRow.avail * 0.64; height: width * 237 / 977; anchors.verticalCenter: parent.verticalCenter
                                source: app.dark ? "qrc:/images/INGEMA_CONSULTORES_LOGO_NEGATIVO.png" : "qrc:/images/INGEMA_CONSULTORES_LOGO.png"
                                fillMode: Image.PreserveAspectFit; smooth: true; mipmap: true; asynchronous: true }
                        Rectangle { width: 1; height: 44 * app.ui.u; anchors.verticalCenter: parent.verticalCenter
                                    color: app.dark ? Qt.rgba(1, 1, 1, 0.18) : Qt.rgba(21 / 255, 26 / 255, 48 / 255, 0.15) }
                        Image { width: brandRow.avail * 0.36 - 2 * brandRow.spacing - 1; height: width * 376 / 928; anchors.verticalCenter: parent.verticalCenter
                                source: app.dark ? "qrc:/images/HVA_GROUP_LOGO_NEGATIVO.png" : "qrc:/images/HVA_GROUP_LOGO.png"
                                fillMode: Image.PreserveAspectFit; smooth: true; mipmap: true; asynchronous: true }
                    }
                    Text { width: parent.width - 44 * app.ui.u; horizontalAlignment: Text.AlignHCenter; wrapMode: Text.WordWrap
                           text: "Ingema Consultores es parte de HVA Group"
                           color: app.muted; font.family: app.ui.fontFamily; font.pixelSize: 12.5 * app.ui.u }
                    Text { width: parent.width - 44 * app.ui.u; horizontalAlignment: Text.AlignHCenter; text: "Tecnología aplicada a la ingeniería"
                           color: app.ink; font.family: app.ui.fontFamily; font.pixelSize: 16 * app.ui.u }
                }
            }
            InfoCard { glyph: 0xE180; tone: app.accent; heading: "Nuestra visión"
                       body: "Ser reconocidos como líderes nacionales en consultoría, con tecnologías innovadoras, impacto positivo en la sociedad y crecimiento sostenible, impulsando el talento de nuestros colaboradores." }
            Card {
                SettingsRow { ui: app.ui; glyph: 0xE1A4; tone: app.accent; title: "Equipo de desarrollo"; subtitle: "Personas detrás de InGe+"; chevron: false }
                Repeater {
                    model: [{ n: "Paola Rosas Gonzales", r: "CEO", c: app.accent },
                            { n: "JuanPablo Ramos", r: "Programador", c: "#0B4AA2" },
                            { n: "Fernando Quispe", r: "Programador", c: app.accent }]
                    delegate: Item {
                        required property var modelData
                        required property int index
                        width: parent.width; height: 68 * app.ui.u
                        Rectangle { id: dev; x: 16 * app.ui.u; anchors.verticalCenter: parent.verticalCenter; width: 46 * app.ui.u; height: width; radius: width / 2
                                    color: modelData.c
                                    Text { anchors.centerIn: parent; text: app.initials(modelData.n); color: "white"
                                           font.family: app.ui.fontFamily; font.pixelSize: 17 * app.ui.u; font.weight: Font.Bold } }
                        Column { x: dev.x + dev.width + 14 * app.ui.u; anchors.verticalCenter: parent.verticalCenter; spacing: 2 * app.ui.u
                                 Text { text: modelData.n; color: app.ink; font.family: app.ui.fontFamily; font.pixelSize: 16 * app.ui.u; font.weight: Font.DemiBold }
                                 Text { text: modelData.r; color: app.muted; font.family: app.ui.fontFamily; font.pixelSize: 13 * app.ui.u } }
                        Rectangle { anchors.top: parent.top; x: 16 * app.ui.u; width: parent.width - 32 * app.ui.u; height: 1
                                    color: Qt.rgba(21 / 255, 26 / 255, 48 / 255, 0.08) }
                    }
                }
            }
            Column {
                width: parent.width; topPadding: 8 * app.ui.u; spacing: 4 * app.ui.u
                Text { anchors.horizontalCenter: parent.horizontalCenter; text: String.fromCharCode(0xE0A0); color: app.muted
                       font.family: app.ui.iconFamily; font.pixelSize: 22 * app.ui.u }
                Text { width: parent.width; horizontalAlignment: Text.AlignHCenter; color: app.muted; font.family: app.ui.fontFamily; font.pixelSize: 13 * app.ui.u
                       text: "© 2026 INGEMA Consultores.
Todos los derechos reservados." }
            }
        }
    }
}

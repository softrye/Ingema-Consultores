import QtQuick 2.15
import QtQuick 6.9 as Qt69
import QtQuick.Controls 2.15
import QtQuick.Effects
import QtQuick.Layouts 1.15
import QtQuick.Shapes 1.15
import QtPositioning
import QtLocation
import QtCore
import QtQuick.Dialogs
import QtQml 2.15
import InGe.CoreFlow 3.0 as Mobile
import "flowcore" as FlowCore
import "components" as Components
import "onboarding" as Onboarding
import "pages" as Pages
import "documents" as NothingFiles
import "lib/IconCatalog.js" as IconCatalog
import "lib/GpsBus.js" as GpsBus

ApplicationWindow {

// M01S02_ACCOUNT_FLOW_V20_START
// Perfil, avatares y multicuenta estabilizados sobre el proyecto real.

property bool profileOverlayOpenV18: false
property bool accountSwitchSheetOpenV18: false
property bool loginRedirectOpenV18: false
property bool manageAccountsModeV18: false
property bool addingAccountModeV20: false
property bool accountSwitchBusyV20: false
property bool authBootstrapDoneV20: false
property bool authRestoreDecisionTakenV70: false
property string previousAccountIdV20: ""
property var savedAccountsModelV20: []
property string loginRedirectTitleV18: "Sesión cerrada"
property string loginRedirectSubtitleV18: "Vuelve a iniciar sesión para continuar."
property string localToastTextV18: ""
property bool localToastVisibleV18: false
property bool sessionEntryTransitionActiveV501: false
property bool sessionEntryIdentityCommittedV501: false
property bool sessionEntryClosingV501: false
property string sessionEntryTextV501:
    "Iniciando sesi" + String.fromCharCode(0xF3) + "n"
property real sessionEntryHomeRevealV501: 1.0
// Bienvenida (auto-login) y espera real del primer frame de Flutter Home.
property bool sessionEntryWelcomeV600: false
// Cubre la pantalla QML (con la bienvenida) desde que termina la transición
// de sesión hasta el primer frame real de Flutter Home. Auth y Home comparten
// una FlutterView: Home solo se pide DESPUÉS de ocultar Auth (orden original).
property bool sessionWelcomeHoldV600: false
property double sessionEntryStartedAtV501: 0
property bool flutterHomeActiveV60: false
property bool flutterSecurityOpenV70: false
property string flutterAuthErrorV70: ""
property string flutterAuthLastMethodV70: ""
property string biometricStatusV70: "Disponible"

// AUTH_FLOW_V800 — única fuente de verdad del flujo de sesión.
// Solo un estado visual principal a la vez:
//   BOOTSTRAP, AUTOLOGIN_WELCOME, LOGIN, AUTHENTICATING, HOME, LOGGING_OUT,
//   SESSION_CLOSED, ACCOUNT_PICKER, ADDING_ACCOUNT, ACCOUNT_SWITCHING.
// La superficie Flutter compartida (Auth/Home) se deriva de este estado; los
// overlays QML "Sesión cerrada" y el selector de cuentas también. Cada
// operación asíncrona abre una generación y solo la operación pendiente
// vigente puede cambiar el estado (los callbacks tardíos se descartan).
property string authFlowStateV800: "BOOTSTRAP"
property int authGenerationV800: 0
property int sessionEntryGenerationV800: -1
property string authPendingOpV800: ""        // restore|password|switch|biometric|restore-cancelled
property int authPendingGenV800: -1
property string accountPickerSourceV800: ""  // home|sessionClosed
property string accountSwitchSourceV800: ""  // home|sessionClosed|auth
property string accountSwitchFromIdV800: ""
property bool accountSwitchRollbackV800: false
property bool flutterHomeHandoffV800: false
readonly property bool authSurfaceStateV800:
    authFlowStateV800 === "BOOTSTRAP"
    || authFlowStateV800 === "AUTOLOGIN_WELCOME"
    || authFlowStateV800 === "LOGIN"
    || authFlowStateV800 === "AUTHENTICATING"
    || authFlowStateV800 === "ADDING_ACCOUNT"
    || (authFlowStateV800 === "ACCOUNT_SWITCHING"
        && accountSwitchSourceV800 === "auth")
readonly property bool authWelcomePhaseV800:
    authFlowStateV800 === "BOOTSTRAP"
    || authFlowStateV800 === "AUTOLOGIN_WELCOME"

function uid8V800(value) {
    var s = String(value || "")
    return s.length > 0 ? s.substring(0, 8) : "-"
}

function activeAccountIdV800() {
    try {
        if (typeof auth !== "undefined" && auth && auth.logged)
            return accountTrimV18(auth.userId, "")
    } catch(e) {}
    return ""
}

function setAuthFlowStateV800(to, reason) {
    var from = authFlowStateV800
    if (from === to) return
    console.info("AUTH_FLOW_STATE from=" + from + " to=" + to
                 + " reason=" + reason + " gen=" + authGenerationV800)
    if (from === "AUTOLOGIN_WELCOME")
        console.info("AUTOLOGIN_WELCOME_HIDE gen=" + authGenerationV800)
    if (to === "AUTOLOGIN_WELCOME")
        console.info("AUTOLOGIN_WELCOME_SHOW gen=" + authGenerationV800)
    authFlowStateV800 = to

    // Overlays QML derivados del estado: nunca sobreviven a su estado.
    loginRedirectOpenV18 = to === "SESSION_CLOSED"
    if (to !== "ACCOUNT_PICKER" && to !== "ACCOUNT_SWITCHING") {
        accountSwitchSheetOpenV18 = false
        manageAccountsModeV18 = false
    }
    if (to === "LOGGING_OUT" || to === "SESSION_CLOSED" || to === "LOGIN"
            || to === "AUTOLOGIN_WELCOME" || to === "ADDING_ACCOUNT"
            || (to === "ACCOUNT_PICKER" && accountPickerSourceV800 !== "home"))
        profileOverlayOpenV18 = false
    if (to !== "AUTOLOGIN_WELCOME")
        authRestoreTimeoutV800.stop()
    addingAccountModeV20 = to === "ADDING_ACCOUNT"
    syncFlutterAuthStateV70(false)
}

function nextAuthGenerationV800(reason) {
    authGenerationV800 += 1
    console.info("AUTH_GENERATION gen=" + authGenerationV800 + " reason=" + reason)
    return authGenerationV800
}

function beginAuthOperationV800(kind) {
    var gen = nextAuthGenerationV800(kind)
    authPendingOpV800 = kind
    authPendingGenV800 = gen
    return gen
}

function clearAuthOperationV800() {
    authPendingOpV800 = ""
    authPendingGenV800 = -1
}

function logStaleAuthCallbackV800(callback, callbackGen) {
    console.info("AUTH_STALE_CALLBACK_IGNORED callback=" + callback
                 + " callbackGen=" + callbackGen
                 + " currentGen=" + authGenerationV800
                 + " state=" + authFlowStateV800
                 + " pending=" + (authPendingOpV800.length ? authPendingOpV800 : "none"))
}

// Estado de formulario al que vuelve un login fallido.
function authFormStateV800() {
    return authFlowStateV800 === "ADDING_ACCOUNT" ? "ADDING_ACCOUNT" : "LOGIN"
}

// Sesión no disponible: formulario limpio, sin identidad visible.
function enterLoginStateV800(reason, errorMessage) {
    clearAuthOperationV800()
    accountSwitchBusyV20 = false
    serverBusy = false
    accountSwitchRollbackV800 = false
    flutterHomeHandoffV800 = false
    clearVisibleSessionV18()
    flutterAuthErrorV70 = errorMessage ? String(errorMessage) : ""
    setAuthFlowStateV800("LOGIN", reason)
}

// Auth → Home en la MISMA FlutterView: Home reclama la superficie mientras
// Auth aún la posee, y Flutter hace el crossfade interno (sin aparcar la
// vista ni dejar ver QML entre ambos).
function handoffFlutterSurfaceToHomeV800() {
    if (Qt.platform.os !== "android") return
    flutterHomeHandoffV800 = true
    console.info("AUTH_OWNER from=auth to=home gen=" + authGenerationV800)
    try {
        syncFlutterAuthStateV70(false)
        Perms.setFlutterHomeVisible(true,
                                    darkMode ? "dark" : "light",
                                    inGeCoreFlow.motionAllowed ? 1.0 : 0.0,
                                    liquidGlass ? 0.72 : 0.0,
                                    String(inGeCoreFlow.performance.profile))
    } catch(e) {
        flutterHomeHandoffV800 = false
    }
}

function hideFlutterHomeForAuthV800() {
    if (Qt.platform.os !== "android") return
    flutterHomeHandoffV800 = false
    try { Perms.setFlutterHomeVisible(false, "light", 1.0, 0.0, "balanced") }
    catch(e) {}
}

onGuestModeChanged: {
    if (guestMode && authFlowStateV800 !== "HOME")
        setAuthFlowStateV800("HOME", "guest")
}

Timer {
    id: authRestoreTimeoutV800
    // Seguridad: una restauración que no responde nunca deja la bienvenida
    // colgada. Agotarla no es un éxito: se vuelve al formulario.
    interval: 9000
    repeat: false
    property int generation: -1
    onTriggered: {
        if (generation !== app.authGenerationV800
                || app.authFlowStateV800 !== "AUTOLOGIN_WELCOME") {
            app.logStaleAuthCallbackV800("restoreTimeout", generation)
            return
        }
        console.info("AUTOLOGIN_TIMEOUT gen=" + generation)
        app.nextAuthGenerationV800("restore-timeout")
        // Una respuesta tardía de esta restauración se descarta en onLoginOk.
        app.authPendingOpV800 = "restore-cancelled"
        app.authPendingGenV800 = app.authGenerationV800
        app.serverBusy = false
        app.flutterAuthErrorV70 = ""
        app.setAuthFlowStateV800("LOGIN", "restore-timeout")
    }
}

function accountTrimV18(v, fallbackValue) {
    try {
        if (v === undefined || v === null) return fallbackValue
        var s = String(v).replace(/^\s+|\s+$/g, "")
        return s.length > 0 ? s : fallbackValue
    } catch(e) { return fallbackValue }
}

function accountNameV18() {
    return inGeCoreFlow.displayPersonName(currentUserName, "Invitado")
}

function homeHeaderFirstNameV50() {
    if (guestMode || !loggedIn)
        return "Invitado"

    var fullName = ""
    var devOffline = false
    try {
        var authSession = app.authContextV23
        if (authSession && typeof authSession.devOffline !== "undefined")
            devOffline = authSession.devOffline === true
        if (authSession && typeof authSession.fullName !== "undefined")
            fullName = accountTrimV18(authSession.fullName, "")
        if (fullName.length === 0 && authSession
                && typeof authSession.nombre !== "undefined")
            fullName = accountTrimV18(authSession.nombre, "")
    } catch(e) {}

    if (fullName.length === 0) {
        var visibleName = accountTrimV18(currentUserName, "")
        if (visibleName.indexOf("@") < 0)
            fullName = visibleName
    }

    if (fullName.length === 0)
        return "Usuario"

    if (devOffline)
        return inGeCoreFlow.displayPersonName(fullName, "InGe Developer")

    var firstName = fullName.split(/\s+/)[0]
    return inGeCoreFlow.displayPersonName(firstName, "Usuario")
}

function beginSessionTransitionV501(message, closing) {
    sessionEntryMinimumTimerV501.stop()
    sessionEntryRevealV501.stop()
    sessionEntryHomeTimeoutV600.stop()
    sessionWelcomeHoldV600 = false
    sessionEntryWelcomeV600 = false
    flutterHomeHandoffV800 = false
    sessionEntryGenerationV800 = authGenerationV800
    sessionEntryTransitionActiveV501 = true
    sessionEntryIdentityCommittedV501 = false
    sessionEntryClosingV501 = closing === true
    sessionEntryTextV501 = String(message
                                  || ("Iniciando sesi"
                                      + String.fromCharCode(0xF3) + "n"))
    sessionEntryStartedAtV501 = Date.now()
    sessionEntryHomeRevealV501 = 0.0
    sessionEntryOverlayV501.opacity = 1.0
}

function beginSessionEntryV501() {
    beginSessionTransitionV501("Iniciando sesi"
                               + String.fromCharCode(0xF3) + "n", false)
}

function welcomeBackgroundV600() {
    return themeMode === 1
            ? inGeCoreFlow.colors.ingemaDeep
            : (liquidGlass ? inGeCoreFlow.theme.background : "#F6F8FB")
}

// Composicion unica de bienvenida: bootstrap y auto-login la comparten para
// que el paso entre ambas sea invisible. La actividad solo aparece si la
// espera supera ~700 ms; nunca se retrasa la entrada real.
component WelcomeSplashV600: Item {
    id: welcomeSplash
    property bool active: false
    property color backgroundColor: "#F6F8FB"
    property url logoSource
    property color titleColor: inGeCoreFlow.theme.textPrimary
    property color accentColor: inGeCoreFlow.theme.accent
    property bool motionAllowed: true
    property int titlePixelSize: 20
    property bool showActivity: false

    onActiveChanged: {
        showActivity = false
        if (active) welcomeActivityDelay.restart()
        else welcomeActivityDelay.stop()
    }
    Component.onCompleted: if (active) welcomeActivityDelay.restart()

    Timer {
        id: welcomeActivityDelay
        interval: 700
        repeat: false
        onTriggered: welcomeSplash.showActivity = welcomeSplash.active
    }

    Rectangle { anchors.fill: parent; color: welcomeSplash.backgroundColor }

    Column {
        anchors.centerIn: parent
        anchors.verticalCenterOffset: -20
        spacing: 16

        Image {
            width: Math.min(welcomeSplash.width * 0.58, 240)
            height: 84
            anchors.horizontalCenter: parent.horizontalCenter
            source: welcomeSplash.logoSource
            fillMode: Image.PreserveAspectFit
            smooth: true
        }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: "Bienvenido a InGe+"
            color: welcomeSplash.titleColor
            font.pixelSize: welcomeSplash.titlePixelSize
            font.weight: Font.DemiBold
        }
        Item {
            width: 36
            height: 20
            anchors.horizontalCenter: parent.horizontalCenter
            // FluentUI FluProgressRing (MIT) — mismo recurso que la bienvenida
            // Flutter (FluentProgressRing en home.dart).
            FlowCore.FlowProgressRing {
                anchors.centerIn: parent
                width: 20
                height: 20
                strokeWidth: 2.5
                running: welcomeSplash.showActivity
                color: welcomeSplash.accentColor
                backgroundColor: Qt.rgba(welcomeSplash.accentColor.r,
                                         welcomeSplash.accentColor.g,
                                         welcomeSplash.accentColor.b, 0.18)
            }
        }
    }
}

function beginSessionWelcomeV600() {
    beginSessionTransitionV501("Bienvenido a InGe+", false)
    sessionEntryWelcomeV600 = true
}

function beginSessionExitV501() {
    beginSessionTransitionV501("Cerrando sesi"
                               + String.fromCharCode(0xF3) + "n", true)
}

function commitSessionIdentityV501() {
    sessionEntryIdentityCommittedV501 = true
    tryFinishSessionEntryV501()
}

function tryFinishSessionEntryV501() {
    if (!sessionEntryTransitionActiveV501
            || !sessionEntryIdentityCommittedV501)
        return

    var elapsed = Math.max(0, Date.now() - sessionEntryStartedAtV501)
    sessionEntryMinimumTimerV501.interval = Math.max(1, 240 - elapsed)
    sessionEntryMinimumTimerV501.restart()
}

function revealSessionWorkspaceV501() {
    if (!sessionEntryTransitionActiveV501
            || !sessionEntryIdentityCommittedV501)
        return
    // Una transición de una generación anterior solo se retira visualmente:
    // no transfiere la superficie a Home ni cambia el estado.
    var currentGen = sessionEntryGenerationV800 === authGenerationV800
    if (!currentGen)
        logStaleAuthCallbackV800("sessionReveal", sessionEntryGenerationV800)
    // Home es Flutter: la misma FlutterView pasa de Auth a Home con
    // crossfade interno; la cubierta QML solo protege si Home no responde.
    if (currentGen && !sessionEntryClosingV501 && Qt.platform.os === "android"
            && pageIndex === 0 && (loggedIn || guestMode) && !flutterHomeActiveV60) {
        handoffFlutterSurfaceToHomeV800()
        sessionWelcomeHoldV600 = true
        sessionEntryHomeTimeoutV600.restart()
    }
    sessionEntryRevealV501.restart()
}

// Final real de la entrada de sesión: identidad comprometida, Home dueño de
// la superficie y transición terminada → HOME.
function finishSessionEntryStateV800() {
    if (sessionEntryGenerationV800 !== authGenerationV800) {
        logStaleAuthCallbackV800("sessionEntryFinished", sessionEntryGenerationV800)
        return
    }
    if (!loggedIn && !guestMode) return
    var s = authFlowStateV800
    if (s === "AUTOLOGIN_WELCOME" || s === "AUTHENTICATING" || s === "LOGIN"
            || s === "ADDING_ACCOUNT" || s === "ACCOUNT_SWITCHING"
            || s === "ACCOUNT_PICKER" || s === "BOOTSTRAP")
        setAuthFlowStateV800("HOME", "session-entry-revealed")
}

onFlutterHomeActiveV60Changed: {
    if (flutterHomeActiveV60 && sessionWelcomeHoldV600) {
        sessionEntryHomeTimeoutV600.stop()
        sessionWelcomeHoldV600 = false
    }
}

function accountEmailV18() {
    var mail = inGeCoreFlow.displayEmailExact(userEmail, "")
    try {
        if (!inGeCoreFlow.hasVisibleText(mail)
                && typeof auth !== "undefined" && auth)
            mail = inGeCoreFlow.displayEmailExact(auth.email, "")
    } catch(e) {}
    return inGeCoreFlow.hasVisibleText(mail) ? mail : "Cuenta local"
}

function accountRoleV25() {
    try {
        if (guestMode)
            return "Trabajo local"

        if (typeof auth !== "undefined" && auth) {
            var candidates = [auth.role, auth.userRole, auth.profileRole]
            for (var i = 0; i < candidates.length; ++i) {
                var value = accountTrimV18(candidates[i], "")
                if (value.length > 0)
                    return value
            }
        }
    } catch(e) {}

    return "Sin rol asignado"
}

function accountPositionV50() {
    try {
        if (!guestMode && auth)
            return accountTrimV18(auth.position, "Sin cargo registrado")
    } catch(e) {}
    return guestMode ? "Trabajo local" : "Sin cargo registrado"
}

function accountPhoneV50() {
    try {
        if (!guestMode && auth)
            return accountTrimV18(auth.phone, "No registrado")
    } catch(e) {}
    return "No registrado"
}

function accountProfileStatusV50() {
    try {
        if (guestMode) return "LOCAL"
        if (auth)
            return accountTrimV18(auth.profileStatus, "SIN PERFIL").toUpperCase()
    } catch(e) {}
    return "SIN PERFIL"
}

function accountProjectCountV50() {
    try {
        return (!guestMode && auth && auth.assignedProjects)
                ? auth.assignedProjects.length : 0
    } catch(e) { return 0 }
}

function accountPrimaryProjectV50() {
    try {
        if (accountProjectCountV50() > 0) {
            var project = auth.assignedProjects[0]
            return accountTrimV18(project.name,
                   accountTrimV18(project.code, "Proyecto asignado"))
        }
    } catch(e) {}
    return guestMode ? "Sin proyecto en modo local" : "Sin proyecto asignado"
}

function accountPhotoV18() {
    return accountTrimV18(profilePhotoSource, "")
}

function accountHasPhotoV18() {
    var source = accountPhotoV18()
    return source.length > 0 && source.indexOf("blank_profile") < 0
}

function savedAccountDisplayNameV20(account) {
    if (!account) return "Cuenta"
    var first = accountTrimV18(account.name, "")
    var last = accountTrimV18(account.lastName, "")
    var full = (first + " " + last).replace(/^\s+|\s+$/g, "")
    if (full.length > 0)
        return inGeCoreFlow.displayPersonName(full, "Cuenta")

    var mail = inGeCoreFlow.displayEmailExact(account.email, "")
    var localPart = mail.indexOf("@") > 0 ? mail.split("@")[0] : ""
    return inGeCoreFlow.displayPersonName(localPart, "Cuenta InGe+")
}

function savedAccountPhotoV20(account) {
    if (!account) return ""
    return accountTrimV18(account.avatarUrl, "")
}

function accountInitialsV20(nameValue) {
    return inGeCoreFlow.personInitials(nameValue, 2)
}

function refreshSavedAccountsV20() {
    try {
        if (typeof auth !== "undefined" && auth && auth.savedAccounts !== undefined) {
            var items = auth.savedAccounts
            savedAccountsModelV20 = items ? items : []
            return
        }
    } catch(e) {}
    savedAccountsModelV20 = []
}

property bool calicataProjectPickerOpen: false
Connections {
    target: renditionFlutterBridge
    function onCalicataProjectPickerRequested() {
        app.calicataProjectPickerOpen = true
        Qt.inputMethod.hide()
        Perms.setFlutterRenditionsVisible(true, app.darkMode ? "dark" : "light",
                                         inGeCoreFlow.motionAllowed ? 1.0 : 0.0,
                                         app.liquidGlass ? 0.72 : 0.0,
                                         String(inGeCoreFlow.performance.profile))
    }
    function onCalicataProjectPicked(documentId, project) {
        app.calicataProjectPickerOpen = false
        Perms.setFlutterRenditionsVisible(false, app.darkMode ? "dark" : "light", 0, 0,
                                         String(inGeCoreFlow.performance.profile))
    }
    function onGlobalActionRequested(action) {
        if (app.pageIndex !== 6) return
        if (action === "home") app.navigateToPage(0)
        else if (action === "documents") app.navigateToPage(3)
        else if (action === "create") app.showToast("Nueva rendición estará disponible en el flujo V2")
    }
}

function flutterAuthStateJsonV70(biometricFailed) {
    var accountId = ""
    try {
        if (app.authContextV23)
            accountId = accountTrimV18(app.authContextV23.currentAccountId,
                                       accountTrimV18(app.authContextV23.userId, ""))
    } catch(e) {}
    return JSON.stringify({
        accounts: savedAccountsModelV20,
        currentAccountId: accountId,
        logged: loggedIn,
        busy: serverBusy || accountSwitchBusyV20,
        error: flutterAuthErrorV70,
        biometricFailed: biometricFailed === true,
        // La bienvenida de auto-inicio vive en la superficie visible (Auth
        // Flutter); los colores replican WelcomeSplashV600.
        phase: authWelcomePhaseV800 ? "welcome" : "login",
        flowState: authFlowStateV800,
        welcome: {
            dark: themeMode === 1,
            background: String(welcomeBackgroundV600()),
            title: String(textColor()),
            accent: String(primaryColor()),
            titleSize: fs(20)
        },
        homeProjection: {
            header: {
                name: homeHeaderFirstNameV50(),
                role: accountRoleV25(),
                avatar: accountPhotoV18(),
                guest: guestMode
            }
        }
    })
}

function syncFlutterAuthStateV70(biometricFailed) {
    try { return Perms.updateFlutterAuthState(flutterAuthStateJsonV70(biometricFailed)) }
    catch(e) { return false }
}

function setFlutterAuthSurfaceV70(visible) {
    if (Qt.platform.os !== "android") return
    if (!visible) {
        try { Perms.setFlutterAuthVisible(false, "{}", "light", 0.0, 0.0, "balanced") }
        catch(e0) {}
        // Ocultar Auth vacía el estado compartido; Home nunca debe quedarse
        // sin su proyección de identidad (nombre, rol, avatar).
        syncFlutterAuthStateV70(false)
        return
    }
    refreshSavedAccountsV20()
    console.log("AUTH_FLUTTER_VISIBLE_REQUEST")
    try {
        Perms.setFlutterAuthVisible(
                    true,
                    flutterAuthStateJsonV70(false),
                    darkMode ? "dark" : "light",
                    inGeCoreFlow.motionAllowed ? 1.0 : 0.0,
                    liquidGlass ? 0.72 : 0.0,
                    String(inGeCoreFlow.performance.profile))
    } catch(e1) {
        console.warn("[InGe+ Auth] Flutter host no disponible")
    }
}

function setFlutterSecuritySurfaceV70(visible) {
    flutterSecurityOpenV70 = visible
    try {
        Perms.setFlutterSecurityVisible(
                    visible,
                    flutterAuthStateJsonV70(false),
                    darkMode ? "dark" : "light",
                    inGeCoreFlow.motionAllowed ? 1.0 : 0.0,
                    liquidGlass ? 0.72 : 0.0,
                    String(inGeCoreFlow.performance.profile))
    } catch(e) {
        flutterSecurityOpenV70 = false
        showToast("No se pudo abrir Seguridad")
    }
}

function consumeFlutterAuthRequestV70(rawRequest) {
    var request = null
    try { request = JSON.parse(String(rawRequest || "")) }
    catch(e0) { return }
    if (!request || !request.type) return

    if (request.type === "password") {
        if (serverBusy) return
        var formStateV800 = authFlowStateV800
        if (formStateV800 !== "LOGIN" && formStateV800 !== "ADDING_ACCOUNT") {
            logStaleAuthCallbackV800("passwordRequest", authGenerationV800)
            return
        }
        var exactEmailV70 = String(request.email || "")
        var exactPasswordV70 = String(request.password || "")
        if (exactEmailV70.replace(/^\s+|\s+$/g, "").length === 0
                || exactPasswordV70.length === 0) {
            flutterAuthErrorV70 = "Ingresa tu correo y contraseña."
            syncFlutterAuthStateV70(false)
            return
        }
        flutterAuthLastMethodV70 = "password"
        flutterAuthErrorV70 = ""
        clearPersistedGuestV41()
        beginAuthOperationV800("password")
        if (formStateV800 === "LOGIN")
            setAuthFlowStateV800("AUTHENTICATING", "password")
        serverBusy = true
        try {
            if (auth && auth.setRememberFor30Days)
                auth.setRememberFor30Days(request.remember === true)
            // El valor exacto se conserva; nunca se transforma ni capitaliza.
            userEmail = exactEmailV70
            auth.signInWithPassword(userEmail, exactPasswordV70)
            exactPasswordV70 = ""
        } catch(e1) {
            clearAuthOperationV800()
            serverBusy = false
            flutterAuthErrorV70 = "No se pudo iniciar sesión."
            setAuthFlowStateV800(formStateV800, "password-dispatch-failed")
            syncFlutterAuthStateV70(false)
        }
    } else if (request.type === "biometric") {
        if (accountSwitchBusyV20 || serverBusy) return
        if (authFlowStateV800 !== "LOGIN" && authFlowStateV800 !== "ADDING_ACCOUNT") {
            logStaleAuthCallbackV800("biometricRequest", authGenerationV800)
            return
        }
        flutterAuthLastMethodV70 = "biometric"
        flutterAuthErrorV70 = ""
        var biometricAccountId = String(request.accountId || "")
        try {
            if (auth && auth.restoreSavedAccountWithBiometric) {
                accountPickerSourceV800 = ""
                accountSwitchSourceV800 = "auth"
                accountSwitchFromIdV800 = ""
                accountSwitchRollbackV800 = false
                var bioGen = beginAuthOperationV800("biometric")
                console.info("ACCOUNT_SWITCH_BEGIN fromUid8=- toUid8="
                             + uid8V800(biometricAccountId) + " gen=" + bioGen)
                setAuthFlowStateV800("ACCOUNT_SWITCHING", "biometric")
                accountSwitchBusyV20 = true
                serverBusy = true
                syncFlutterAuthStateV70(false)
                auth.restoreSavedAccountWithBiometric(biometricAccountId)
            } else {
                switchSavedAccountV20(biometricAccountId)
            }
        } catch(e2) {
            enterLoginStateV800("biometric-dispatch-failed",
                                "No se pudo validar la sesión biométrica.")
            syncFlutterAuthStateV70(true)
        }
    } else if (request.type === "clientError") {
        flutterAuthErrorV70 = String(request.message || "Completa los campos requeridos.")
        syncFlutterAuthStateV70(false)
    } else if (request.type === "biometricStatus") {
        var state = String(request.status || "available")
        biometricStatusV70 = state === "enabled" ? "Activado"
                            : (state === "enabled-unavailable" ? "Requiere biometría"
                            : (state === "unavailable" ? "No disponible" : "Disponible")
                              )
        if (state === "enabled" && loggedIn) {
            try {
                // El owner C++ conserva la única sesión Supabase. Flutter
                // almacena sólo el vínculo cifrado que la biometría habilita.
                auth.setRememberFor30Days(true)
                auth.saveToDisk()
            } catch(e3) {}
        }
        // La pantalla permanece visible mientras se decide el método. Con
        // biometría activa Flutter solicita la verificación; en los demás
        // casos se restaura directamente la única sesión recordada.
        // Solo se decide una vez por arranque y únicamente mientras el flujo
        // sigue en su estado inicial; nunca reabre Auth desde otro estado.
        if (!authRestoreDecisionTakenV70 && !loggedIn
                && (authFlowStateV800 === "BOOTSTRAP"
                    || authFlowStateV800 === "AUTOLOGIN_WELCOME"
                    || authFlowStateV800 === "LOGIN")) {
            authRestoreDecisionTakenV70 = true
            if (state === "enabled" || state === "enabled-unavailable") {
                // Con biometría activa la verificación la solicita Flutter
                // sobre la cuenta conocida: la bienvenida cede al método.
                if (authFlowStateV800 !== "LOGIN")
                    setAuthFlowStateV800("LOGIN", "biometric-required")
            } else if (authFlowStateV800 === "AUTOLOGIN_WELCOME"
                       && !serverBusy) {
                try {
                    if (auth && auth.tryAutoLogin) {
                        var restoreGen = beginAuthOperationV800("restore")
                        authRestoreTimeoutV800.generation = restoreGen
                        authRestoreTimeoutV800.restart()
                        serverBusy = true
                        syncFlutterAuthStateV70(false)
                        auth.tryAutoLogin()
                    } else {
                        enterLoginStateV800("restore-unavailable", "")
                    }
                } catch(e4) {
                    enterLoginStateV800("restore-dispatch-failed", "")
                }
            } else if (authFlowStateV800 === "BOOTSTRAP") {
                setAuthFlowStateV800("LOGIN", "no-restorable-session")
            }
        }
    } else if (request.type === "closeSecurity") {
        setFlutterSecuritySurfaceV70(false)
    }
}

function showLocalToastV18(message) {
    localToastTextV18 = message
    localToastVisibleV18 = true
    localToastTimerV18.restart()
}

function openProfileOverlayV18() {
    refreshSavedAccountsV20()
    profileOverlayOpenV18 = true
}

function closeProfileOverlayV18() { profileOverlayOpenV18 = false }

// Selector de cuentas. Dos casos distintos, nunca mezclados:
//  home          → acción voluntaria con sesión activa; Home queda detrás.
//  sessionClosed → pertenece a Auth; no existe Home activo detrás.
function openAccountSwitchSheetV18() {
    openAccountPickerV800(loggedIn && authFlowStateV800 === "HOME"
                          ? "home" : "sessionClosed")
}

function openAccountPickerV800(source) {
    if (accountSwitchBusyV20) return
    if (source === "home" && authFlowStateV800 !== "HOME") return
    if (source === "sessionClosed" && authFlowStateV800 !== "SESSION_CLOSED"
            && authFlowStateV800 !== "ACCOUNT_PICKER") return
    refreshSavedAccountsV20()
    manageAccountsModeV18 = false
    accountPickerSourceV800 = source
    console.info("ACCOUNT_PICKER_OPEN source=" + source + " gen=" + authGenerationV800)
    setAuthFlowStateV800("ACCOUNT_PICKER", "open-" + source)
    accountSwitchSheetOpenV18 = true
}

function closeAccountSwitchSheetV18() {
    // Durante un cambio en curso el selector no se cierra (sin estados
    // intermedios ni dos autenticaciones).
    if (accountSwitchBusyV20 || authFlowStateV800 === "ACCOUNT_SWITCHING") return
    accountSwitchSheetOpenV18 = false
    manageAccountsModeV18 = false
    if (authFlowStateV800 === "ACCOUNT_PICKER")
        setAuthFlowStateV800(accountPickerSourceV800 === "home" && loggedIn
                             ? "HOME" : "SESSION_CLOSED", "picker-cancel")
}

// "Iniciar sesión" desde Sesión cerrada: formulario Flutter limpio.
function openLoginFromSessionClosedV800() {
    if (authFlowStateV800 !== "SESSION_CLOSED" && authFlowStateV800 !== "ACCOUNT_PICKER")
        return
    nextAuthGenerationV800("session-closed-login")
    clearAuthOperationV800()
    flutterAuthErrorV70 = ""
    setAuthFlowStateV800("LOGIN", "session-closed-login")
}

function clearVisibleSessionV18() {
    try { profilePhotoSource = icon("blank_profile.png") } catch(e0) {}
    try { profilePhotoStatus = "Avatar predeterminado" } catch(e1) {}
    try { currentUserName = "Invitado" } catch(e2) {}
    try { userEmail = "" } catch(e3) {}
    try { userPassword = "" } catch(e4) {}
    try { loggedIn = false } catch(e5) {}
    try { guestMode = false } catch(e6) {}
    try { serverConnected = false } catch(e7) {}
    try { serverBusy = false } catch(e8) {}
    try { setupComplete = true } catch(e9) {}
    try { setPageImmediate(0) } catch(e10) { pageIndex = 0 }
}

function goToLoginV18(message) {
    clearPersistedGuestV41()
    authBootstrapDoneV20 = true
    enterLoginStateV800("go-to-login", "")
    if (message && String(message).length > 0) showLocalToastV18(message)
}

// HOME → LOGGING_OUT → SESSION_CLOSED. Cierra solo la sesión activa; las
// cuentas recordadas se conservan. Home deja de ser dueño de la superficie
// antes de mostrar "Sesión cerrada" y ningún callback previo puede volver.
function performLogoutV18() {
    if (authFlowStateV800 === "LOGGING_OUT" || authFlowStateV800 === "SESSION_CLOSED")
        return
    var gen = nextAuthGenerationV800("logout")
    clearAuthOperationV800()
    console.info("LOGOUT_BEGIN gen=" + gen)
    setAuthFlowStateV800("LOGGING_OUT", "user")
    beginSessionExitV501()
    hideFlutterHomeForAuthV800()
    clearPersistedGuestV41()
    previousAccountIdV20 = ""
    accountSwitchBusyV20 = false
    accountSwitchRollbackV800 = false
    clearVisibleSessionV18()

    var logoutPending = false
    try {
        if (typeof auth !== "undefined" && auth && auth.signOut) {
            logoutPending = true
            auth.signOut()
        }
    } catch(e) { logoutPending = false }

    if (!logoutPending)
        commitSessionIdentityV501()

    refreshSavedAccountsV20()
    loginRedirectTitleV18 = "Sesión cerrada"
    loginRedirectSubtitleV18 = savedAccountsModelV20.length > 0
            ? "Tu cuenta recordada sigue disponible para acceso rápido."
            : "Vuelve a iniciar sesión para continuar."
    if (gen === authGenerationV800) {
        console.info("LOGOUT_COMMIT gen=" + gen)
        setAuthFlowStateV800("SESSION_CLOSED", "logout-commit")
    }
    showLocalToastV18("Sesión cerrada")
}

// Añadir cuenta: la sesión A se conserva hasta que B se autentique.
function performAddAccountV18() {
    if (accountSwitchBusyV20 || serverBusy) return
    clearPersistedGuestV41()
    previousAccountIdV20 = activeAccountIdV800()
    nextAuthGenerationV800("add-account")
    clearAuthOperationV800()
    clearVisibleSessionV18()
    authBootstrapDoneV20 = true
    authView.rememberLogin = true
    flutterAuthErrorV70 = ""
    hideFlutterHomeForAuthV800()
    setAuthFlowStateV800("ADDING_ACCOUNT", "add-account")
    showLocalToastV18("Inicia sesión con la cuenta que deseas añadir")
}

function cancelAddAccountV20() {
    if (authFlowStateV800 !== "ADDING_ACCOUNT") return
    if (serverBusy || accountSwitchBusyV20 || sessionEntryTransitionActiveV501) return
    var restoreId = previousAccountIdV20
    previousAccountIdV20 = ""
    nextAuthGenerationV800("add-account-cancel")
    clearAuthOperationV800()

    // Mientras se añade otra cuenta, la sesión anterior se conserva en memoria.
    // Si sigue activa, se restaura sin red ni nuevo inicio de sesión. Si no,
    // se recurre a la copia recordada del dispositivo.
    try {
        if (restoreId.length > 0 && typeof auth !== "undefined" && auth
                && auth.logged && String(auth.userId) === restoreId) {
            loggedIn = true
            guestMode = false
            serverConnected = !(auth.devOffline === true)
            authBootstrapDoneV20 = true
            updateWelcomeFromAuth()
            refreshSavedAccountsV20()
            setAuthFlowStateV800("HOME", "add-account-cancel")
            showLocalToastV18("Volviste a tu cuenta anterior")
            return
        }
    } catch(e) {}

    if (restoreId.length > 0 && auth && auth.hasSavedAccount
            && auth.hasSavedAccount(restoreId)) {
        accountPickerSourceV800 = ""
        startAccountSwitchV800(restoreId, "auth", "")
    } else {
        enterLoginStateV800("add-account-cancel", "")
    }
}

function openManageAccountsV18() {
    if (authFlowStateV800 !== "ACCOUNT_PICKER" || accountSwitchBusyV20) return
    refreshSavedAccountsV20()
    manageAccountsModeV18 = !manageAccountsModeV18
    accountSwitchSheetOpenV18 = true
}

function switchSavedAccountV20(accountId) {
    var id = String(accountId || "")
    if (accountSwitchBusyV20 || serverBusy || id.length === 0) return
    // Misma cuenta ya activa: sin logout, sin login, sin recrear Home.
    if (loggedIn && id === activeAccountIdV800()) {
        closeAccountSwitchSheetV18()
        return
    }
    var source = authFlowStateV800 === "ACCOUNT_PICKER"
            ? accountPickerSourceV800 : "auth"
    startAccountSwitchV800(id, source,
                           source === "home" ? activeAccountIdV800() : "")
}

// Cambio atómico: la identidad visible solo cambia cuando C++ confirma la
// nueva sesión completa (tokens + perfil + proyectos → loginOk).
function startAccountSwitchV800(accountId, source, fromId) {
    clearPersistedGuestV41()
    try {
        if (typeof auth !== "undefined" && auth && auth.switchToSavedAccount) {
            accountSwitchSourceV800 = source
            accountSwitchFromIdV800 = fromId || ""
            var gen = beginAuthOperationV800("switch")
            console.info("ACCOUNT_SWITCH_BEGIN fromUid8=" + uid8V800(fromId)
                         + " toUid8=" + uid8V800(accountId) + " gen=" + gen
                         + " source=" + source)
            setAuthFlowStateV800("ACCOUNT_SWITCHING", "switch-" + source)
            accountSwitchBusyV20 = true
            serverBusy = true
            syncFlutterAuthStateV70(false)
            auth.switchToSavedAccount(String(accountId))
            return
        }
    } catch(e) {}
    clearAuthOperationV800()
    accountSwitchBusyV20 = false
    serverBusy = false
    showLocalToastV18("No se pudo cambiar de cuenta")
}

// Olvida solo la entrada recordada (y sus credenciales persistentes). La
// sesión viva, si es la misma cuenta, continúa.
function removeSavedAccountV20(accountId) {
    if (accountSwitchBusyV20) return
    try {
        if (typeof auth !== "undefined" && auth && auth.removeSavedAccount) {
            console.info("ACCOUNT_REMEMBERED_REMOVE uid8=" + uid8V800(accountId))
            auth.removeSavedAccount(String(accountId))
            refreshSavedAccountsV20()
            showLocalToastV18("Cuenta eliminada del dispositivo")
        }
    } catch(e) { showLocalToastV18("No se pudo eliminar la cuenta") }
}

function useDefaultAvatarV18() {
    try {
        if (typeof auth !== "undefined" && auth && auth.logged && auth.clearUserAvatar) {
            auth.clearUserAvatar()
            showLocalToastV18("Eliminando foto...")
            return
        }
    } catch(e) {}
    profilePhotoSource = icon("blank_profile.png")
    profilePhotoStatus = "Avatar predeterminado"
    showLocalToastV18("Avatar predeterminado")
}

function changePhotoV18() {
    try { profilePicker.open() }
    catch(e) { showLocalToastV18("No se pudo abrir el selector de fotos") }
}

Timer {
    id: localToastTimerV18
    interval: 2200
    repeat: false
    onTriggered: localToastVisibleV18 = false
}

Rectangle {
    id: profileOverlayV18
    anchors.fill: parent
    z: 99950
    visible: profileOverlayOpenV18 || opacity > 0.01
    enabled: profileOverlayOpenV18
    opacity: profileOverlayOpenV18 ? 1.0 : 0.0
    y: profileOverlayOpenV18 ? 0 : 15
    color: bgColor()

    Behavior on opacity { NumberAnimation { duration: inGeCoreFlow.normalDuration; easing.type: inGeCoreFlow.easeStandard } }
    Behavior on y { NumberAnimation { duration: inGeCoreFlow.normalDuration; easing.type: inGeCoreFlow.easeStandard } }
    MouseArea { anchors.fill: parent }

    Rectangle {
        id: profileBackdropV18
        anchors.fill: parent
        color: profileOverlayV18.color
        Image {
            anchors.fill: parent
            // Decoracion solo del tema Glass (liquidGlass es hoy la constante
            // false). opacity 0 no evita decodificar el SVG de 1080x2400 (~10 MB
            // RGBA residentes desde el arranque): sin Glass no se carga.
            source: liquidGlass ? "qrc:/ui/v2/backgrounds/bg_topographic_lines.svg" : ""
            sourceSize: Qt.size(Math.max(1, width), Math.max(1, height))
            asynchronous: true
            fillMode: Image.PreserveAspectCrop
            opacity: liquidGlass ? 0.13 : 0.0
        }
    }

    Rectangle {
        id: profileHeaderV20
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        height: 76
        color: panelColor()
        border.color: borderColor()
        border.width: 1

        Column {
            anchors.left: parent.left
            anchors.leftMargin: 16
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width - 92
            spacing: 4
            Text { width: parent.width; text: "Perfil"; color: textColor(); font.pixelSize: fs(22); font.bold: true; elide: Text.ElideRight }
            Text { width: parent.width; text: "Cuenta vinculada a InGe+"; color: mutedColor(); font.pixelSize: fs(11); elide: Text.ElideRight }
        }

        Rectangle {
            width: 40; height: 40; radius: 13
            anchors.right: parent.right; anchors.rightMargin: 18
            anchors.verticalCenter: parent.verticalCenter
            color: closeMouseV18.pressed ? inGeCoreFlow.theme.pressed : inGeCoreFlow.theme.selected
            border.color: borderColor(); border.width: 1
            scale: closeMouseV18.pressed ? 0.96 : 1.0
            Behavior on scale { NumberAnimation { duration: inGeCoreFlow.fastDuration; easing.type: inGeCoreFlow.easeOut } }
            Components.FlowIcon { anchors.centerIn: parent; width: 20; height: 20; name: "system.close"; flow: inGeCoreFlow; active: true }
            MouseArea { id: closeMouseV18; anchors.fill: parent; onClicked: closeProfileOverlayV18() }
        }
    }

    Flickable {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: profileHeaderV20.bottom
        anchors.bottom: parent.bottom
        contentWidth: width
        contentHeight: profileColumnV18.height + 34
        clip: true
        flickableDirection: Flickable.VerticalFlick
        pressDelay: inGeCoreFlow.touchPressDelay
        flickDeceleration: inGeCoreFlow.flickDeceleration
        maximumFlickVelocity: inGeCoreFlow.scrollVelocity(contentHeight, height)
        boundsBehavior: inGeCoreFlow.motionAllowed
                        ? Flickable.DragAndOvershootBounds
                        : Flickable.StopAtBounds

        Column {
            id: profileColumnV18
            x: 14; y: 14
            width: parent.width - 28
            spacing: 12

            FlowCore.FlowGlassSurface {
                width: parent.width
                height: 314
                radius: 30
                flow: inGeCoreFlow
                darkMode: app.darkMode
                materialRole: "emphasized"
                blurSource: profileBackdropV18

                Components.CircularAvatar {
                    id: largeAvatarV18
                    width: 92; height: 92
                    anchors.horizontalCenter: parent.horizontalCenter
                    y: 22
                    source: accountPhotoV18()
                    hasImage: accountHasPhotoV18()
                    borderColor: primaryColor()
                    borderWidth: 3
                    fallbackText: accountInitialsV20(accountNameV18())
                    showStatus: true
                    statusColor: inGeCoreFlow.theme.textSecondary

                    MouseArea { anchors.fill: parent; onClicked: changePhotoV18() }
                }

                Column {
                    x: 18; y: 126
                    width: parent.width - 36
                    spacing: 4
                    Text { width: parent.width; text: accountNameV18(); color: textColor(); font.pixelSize: fs(21); font.bold: true; horizontalAlignment: Text.AlignHCenter; elide: Text.ElideRight }
                    Text { width: parent.width; text: accountPositionV50(); color: mutedColor(); font.pixelSize: fs(11); horizontalAlignment: Text.AlignHCenter; elide: Text.ElideRight }
                    Text { width: parent.width; text: accountEmailV18(); color: mutedColor(); font.pixelSize: fs(10); horizontalAlignment: Text.AlignHCenter; elide: Text.ElideRight }
                }

                Rectangle {
                    width: profileRoleTextV70.implicitWidth + 24
                    height: 28; radius: 14
                    anchors.horizontalCenter: parent.horizontalCenter
                    y: 196
                    color: inGeCoreFlow.theme.selected
                    border.color: borderColor()
                    Text {
                        id: profileRoleTextV70
                        anchors.centerIn: parent
                        text: accountRoleV25().toUpperCase()
                        color: primaryColor(); font.pixelSize: fs(9); font.bold: true
                        font.letterSpacing: 0.8
                    }
                }

                Row {
                    x: 18; y: 244
                    width: parent.width - 36
                    height: 46
                    spacing: 12

                    Rectangle {
                        width: (parent.width - 12) / 2; height: parent.height; radius: 14
                        color: avatarDefaultMouseV18.pressed ? inGeCoreFlow.theme.pressed : card2Color()
                        border.color: borderColor(); border.width: 1
                        scale: avatarDefaultMouseV18.pressed ? 0.97 : 1.0
                        Behavior on scale { NumberAnimation { duration: inGeCoreFlow.fastDuration; easing.type: inGeCoreFlow.easeOut } }
                        Text { anchors.centerIn: parent; text: "Usar avatar"; color: textColor(); font.pixelSize: fs(11); font.bold: true }
                        MouseArea { id: avatarDefaultMouseV18; anchors.fill: parent; onClicked: useDefaultAvatarV18() }
                    }

                    Rectangle {
                        width: (parent.width - 12) / 2; height: parent.height; radius: 14
                        color: changePhotoMouseV18.pressed ? Qt.darker(inGeCoreFlow.theme.actionPrimary, 1.12) : inGeCoreFlow.theme.actionPrimary
                        scale: changePhotoMouseV18.pressed ? 0.97 : 1.0
                        Behavior on scale { NumberAnimation { duration: inGeCoreFlow.fastDuration; easing.type: inGeCoreFlow.easeOut } }
                        Text { anchors.centerIn: parent; text: "Cambiar foto"; color: inGeCoreFlow.theme.onActionPrimary; font.pixelSize: fs(11); font.bold: true }
                        MouseArea { id: changePhotoMouseV18; anchors.fill: parent; onClicked: changePhotoV18() }
                    }
                }
            }

            Rectangle {
                width: parent.width; height: 204; radius: 18
                color: cardColor(); border.color: borderColor(); border.width: 1
                Text { x: 18; y: 14; width: parent.width - 36; text: "Datos de cuenta"; color: textColor(); font.pixelSize: fs(16); font.bold: true }
                Text { x: 18; y: 52; width: parent.width * 0.34; text: "Nombre"; color: mutedColor(); font.pixelSize: fs(11) }
                Text { x: parent.width * 0.38; y: 52; width: parent.width * 0.56; text: accountNameV18(); color: textColor(); font.pixelSize: fs(11); font.bold: true; horizontalAlignment: Text.AlignRight; elide: Text.ElideRight }
                Text { x: 18; y: 82; width: parent.width * 0.34; text: "Correo"; color: mutedColor(); font.pixelSize: fs(11) }
                Text { x: parent.width * 0.38; y: 82; width: parent.width * 0.56; text: accountEmailV18(); color: textColor(); font.pixelSize: fs(11); font.bold: true; horizontalAlignment: Text.AlignRight; elide: Text.ElideRight }
                Text { x: 18; y: 112; width: parent.width * 0.34; text: "Teléfono"; color: mutedColor(); font.pixelSize: fs(11) }
                Text { x: parent.width * 0.38; y: 112; width: parent.width * 0.56; text: accountPhoneV50(); color: textColor(); font.pixelSize: fs(11); font.bold: true; horizontalAlignment: Text.AlignRight; elide: Text.ElideRight }
                Text { x: 18; y: 142; width: parent.width * 0.34; text: "Rol"; color: mutedColor(); font.pixelSize: fs(11) }
                Text { x: parent.width * 0.38; y: 142; width: parent.width * 0.56; text: accountRoleV25(); color: primaryColor(); font.pixelSize: fs(11); font.bold: true; horizontalAlignment: Text.AlignRight; elide: Text.ElideRight }
                Text { x: 18; y: 172; width: parent.width * 0.34; text: "Estado"; color: mutedColor(); font.pixelSize: fs(11) }
                Text { x: parent.width * 0.38; y: 172; width: parent.width * 0.56; text: accountProfileStatusV50(); color: inGeCoreFlow.theme.success; font.pixelSize: fs(11); font.bold: true; horizontalAlignment: Text.AlignRight; elide: Text.ElideRight }
            }

            Rectangle {
                width: parent.width; height: 116; radius: 18
                color: cardColor(); border.color: borderColor(); border.width: 1
                Rectangle {
                    x: 16; y: 16; width: 42; height: 42; radius: 13
                    color: inGeCoreFlow.theme.selected
                    Components.FlowIcon { anchors.centerIn: parent; width: 22; height: 22; name: "project.current"; flow: inGeCoreFlow; active: true }
                }
                Column {
                    x: 70; y: 16; width: parent.width - 86; spacing: 4
                    Text { width: parent.width; text: "Proyecto principal"; color: mutedColor(); font.pixelSize: fs(10); font.bold: true }
                    Text { width: parent.width; text: accountPrimaryProjectV50(); color: textColor(); font.pixelSize: fs(14); font.bold: true; elide: Text.ElideRight }
                    Text { width: parent.width; text: accountProjectCountV50() === 1 ? "1 proyecto asignado" : accountProjectCountV50() + " proyectos asignados"; color: primaryColor(); font.pixelSize: fs(10); elide: Text.ElideRight }
                }
                Text { x: 16; y: 82; width: parent.width - 32; text: "La información proviene de tu acceso actual."; color: mutedColor(); font.pixelSize: fs(9); elide: Text.ElideRight }
            }

            Rectangle {
                width: parent.width; height: 222; radius: 18
                color: cardColor(); border.color: borderColor(); border.width: 1
                Text { x: 18; y: 14; width: parent.width - 36; text: "Acciones de cuenta"; color: textColor(); font.pixelSize: fs(16); font.bold: true }

                Rectangle {
                    x: 18; y: 52; width: (parent.width - 48) / 2; height: 42; radius: 13
                    color: profileSecurityMouseV70.pressed ? inGeCoreFlow.theme.pressed : inGeCoreFlow.theme.selected
                    border.color: borderColor(); border.width: 1
                    scale: profileSecurityMouseV70.pressed ? 0.97 : 1.0
                    Behavior on scale { NumberAnimation { duration: inGeCoreFlow.fastDuration; easing.type: inGeCoreFlow.easeOut } }
                    Row {
                        anchors.centerIn: parent; spacing: 7
                        Components.FlowIcon { width: 18; height: 18; name: "security.biometric"; flow: inGeCoreFlow; active: true; tintColor: primaryColor(); activeTintColor: primaryColor(); inactiveOpacity: 1.0 }
                        Text { text: "Seguridad"; color: textColor(); font.pixelSize: fs(10); font.bold: true; anchors.verticalCenter: parent.verticalCenter }
                    }
                    MouseArea { id: profileSecurityMouseV70; anchors.fill: parent; onClicked: setFlutterSecuritySurfaceV70(true) }
                }

                Rectangle {
                    x: (parent.width / 2) + 6; y: 52; width: (parent.width - 48) / 2; height: 42; radius: 13
                    color: profileSettingsMouseV70.pressed ? inGeCoreFlow.theme.pressed : card2Color()
                    border.color: borderColor(); border.width: 1
                    scale: profileSettingsMouseV70.pressed ? 0.97 : 1.0
                    Behavior on scale { NumberAnimation { duration: inGeCoreFlow.fastDuration; easing.type: inGeCoreFlow.easeOut } }
                    Row {
                        anchors.centerIn: parent; spacing: 7
                        Components.FlowIcon { width: 18; height: 18; name: "nav.settings"; flow: inGeCoreFlow; tintColor: primaryColor(); inactiveOpacity: 1.0 }
                        Text { text: "Ajustes"; color: textColor(); font.pixelSize: fs(10); font.bold: true; anchors.verticalCenter: parent.verticalCenter }
                    }
                    MouseArea {
                        id: profileSettingsMouseV70
                        anchors.fill: parent
                        onClicked: {
                            closeProfileOverlayV18()
                            navigateToPage(4)
                        }
                    }
                }

                Rectangle {
                    x: 18; y: 108; width: parent.width - 36; height: 42; radius: 13
                    color: switchAccountMouseV18.pressed ? inGeCoreFlow.theme.pressed : inGeCoreFlow.theme.selected
                    border.color: borderColor(); border.width: 1
                    scale: switchAccountMouseV18.pressed ? 0.97 : 1.0
                    Behavior on scale { NumberAnimation { duration: inGeCoreFlow.fastDuration; easing.type: inGeCoreFlow.easeOut } }
                    Text { anchors.centerIn: parent; text: "Cambiar o añadir cuenta"; color: primaryColor(); font.pixelSize: fs(11); font.bold: true }
                    MouseArea { id: switchAccountMouseV18; anchors.fill: parent; onClicked: openAccountSwitchSheetV18() }
                }

                Rectangle {
                    x: 18; y: 164; width: parent.width - 36; height: 42; radius: 13
                    color: logoutMouseV18.pressed ? inGeCoreFlow.theme.errorContainer : card2Color()
                    border.color: borderColor(); border.width: 1
                    scale: logoutMouseV18.pressed ? 0.97 : 1.0
                    Behavior on scale { NumberAnimation { duration: inGeCoreFlow.fastDuration; easing.type: inGeCoreFlow.easeOut } }
                    Text { anchors.centerIn: parent; text: "Cerrar sesión"; color: inGeCoreFlow.theme.error; font.pixelSize: fs(11); font.bold: true }
                    MouseArea { id: logoutMouseV18; anchors.fill: parent; onClicked: performLogoutV18() }
                }
            }
            Item { width: parent.width; height: 28 }
        }
    }
}

Rectangle {
    id: accountSwitchSheetV18
    anchors.fill: parent
    z: 100000
    visible: accountSwitchSheetOpenV18 || opacity > 0.01
    enabled: accountSwitchSheetOpenV18
    // Sin sesión (selector de Auth) no hay Home detrás: fondo opaco.
    color: accountPickerSourceV800 === "sessionClosed"
           ? bgColor() : inGeCoreFlow.theme.scrim
    opacity: accountSwitchSheetOpenV18 ? 1.0 : 0.0
    Behavior on opacity { NumberAnimation { duration: inGeCoreFlow.normalDuration; easing.type: inGeCoreFlow.easeStandard } }
    MouseArea { anchors.fill: parent; onClicked: closeAccountSwitchSheetV18() }

    Rectangle {
        id: accountPanelV18
        x: 16
        width: parent.width - 32
        height: Math.min(parent.height - 24,
                         Math.max(420, 250 + Math.min(3, savedAccountsModelV20.length) * 90))
        radius: 24
        color: liquidGlass ? inGeCoreFlow.theme.surfaceOverlay : cardColor()
        border.color: borderColor()
        border.width: 1
        y: accountSwitchSheetOpenV18 ? parent.height - height - 16 : parent.height + 24
        scale: accountSwitchSheetOpenV18 ? 1.0 : inGeCoreFlow.sheetStartScale
        transformOrigin: Item.Bottom
        Behavior on y { NumberAnimation { duration: inGeCoreFlow.sheetDuration; easing.type: inGeCoreFlow.easeEmphasized } }
        Behavior on scale { NumberAnimation { duration: inGeCoreFlow.sheetDuration; easing.type: inGeCoreFlow.easeOvershoot } }
        MouseArea { anchors.fill: parent }

        Rectangle { width: 48; height: 5; radius: 3; anchors.horizontalCenter: parent.horizontalCenter; y: 10; color: borderColor() }
        Text { x: 22; y: 30; width: parent.width - 86; text: manageAccountsModeV18 ? "Gestionar cuentas" : "Cambiar de cuenta"; color: textColor(); font.pixelSize: fs(20); font.bold: true; elide: Text.ElideRight }
        Rectangle {
            width: 40; height: 40; radius: 13; x: parent.width - width - 18; y: 22
            color: closeSheetMouseV18.pressed ? inGeCoreFlow.theme.pressed : inGeCoreFlow.theme.selected
            scale: closeSheetMouseV18.pressed ? 0.96 : 1.0
            Behavior on scale { NumberAnimation { duration: inGeCoreFlow.fastDuration; easing.type: inGeCoreFlow.easeOut } }
            Components.FlowIcon { anchors.centerIn: parent; width: 19; height: 19; name: "system.close"; flow: inGeCoreFlow; active: true }
            MouseArea { id: closeSheetMouseV18; anchors.fill: parent; onClicked: closeAccountSwitchSheetV18() }
        }

        ListView {
            id: accountsListV20
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.bottom: addAccountBtnV18.top
            anchors.leftMargin: 18
            anchors.rightMargin: 18
            anchors.topMargin: 82
            anchors.bottomMargin: 14
            clip: true
            spacing: 8
            model: savedAccountsModelV20
            boundsBehavior: Flickable.StopAtBounds

            delegate: Rectangle {
                id: accountRowV20
                property var accountData: modelData
                width: accountsListV20.width
                height: 82
                radius: 15
                color: accountMouseV20.pressed ? inGeCoreFlow.theme.pressed : (accountData && accountData.isCurrent ? inGeCoreFlow.theme.selected : card2Color())
                border.color: accountData && accountData.isCurrent ? primaryColor() : borderColor()
                border.width: 1
                scale: accountMouseV20.pressed ? 0.985 : 1.0
                Behavior on scale { NumberAnimation { duration: inGeCoreFlow.fastDuration; easing.type: inGeCoreFlow.easeOut } }

                Components.CircularAvatar {
                    width: 54; height: 54; x: 12; y: 14
                    source: savedAccountPhotoV20(accountData)
                    hasImage: savedAccountPhotoV20(accountData).length > 0
                    borderColor: app.borderColor()
                    borderWidth: 1
                    fallbackText: savedAccountDisplayNameV20(accountData).length > 0
                                  ? accountInitialsV20(savedAccountDisplayNameV20(accountData)) : ""
                    showStatus: accountData && accountData.isCurrent
                }

                Column {
                    x: 78; y: 17
                    width: parent.width - (manageAccountsModeV18 ? 132 : 100)
                    spacing: 5
                    Text { width: parent.width; text: savedAccountDisplayNameV20(accountData); color: textColor(); font.pixelSize: fs(13); font.bold: true; elide: Text.ElideRight }
                    Text { width: parent.width; text: accountData ? inGeCoreFlow.displayEmailExact(accountData.email, "Cuenta guardada") : "Cuenta guardada"; color: mutedColor(); font.pixelSize: fs(10); elide: Text.ElideRight }
                    Text { width: parent.width; text: accountData && accountData.isCurrent ? "Cuenta actual" : "Toca para cambiar"; color: accountData && accountData.isCurrent ? inGeCoreFlow.theme.success : primaryColor(); font.pixelSize: fs(9); font.bold: true }
                }

                Rectangle {
                    visible: manageAccountsModeV18 && accountData && !accountData.transient
                    width: 38; height: 38; radius: 12
                    anchors.right: parent.right; anchors.rightMargin: 12
                    anchors.verticalCenter: parent.verticalCenter
                    color: deleteAccountMouseV20.pressed ? inGeCoreFlow.theme.pressed : inGeCoreFlow.theme.errorContainer
                    Components.FlowIcon {
                        anchors.centerIn: parent
                        width: 20
                        height: 20
                        name: "action.delete"
                        flow: inGeCoreFlow
                        pressed: deleteAccountMouseV20.pressed
                        tintColor: inGeCoreFlow.theme.error
                        activeTintColor: inGeCoreFlow.theme.error
                        inactiveOpacity: 1.0
                    }
                    MouseArea { id: deleteAccountMouseV20; anchors.fill: parent; onClicked: removeSavedAccountV20(accountData.id) }
                }

                MouseArea {
                    id: accountMouseV20
                    anchors.fill: parent
                    anchors.rightMargin: manageAccountsModeV18 ? 58 : 0
                    enabled: !accountSwitchBusyV20
                    onClicked: {
                        if (accountData && accountData.isCurrent) closeAccountSwitchSheetV18()
                        else if (accountData) switchSavedAccountV20(accountData.id)
                    }
                }
            }

            Text {
                anchors.centerIn: parent
                visible: savedAccountsModelV20.length === 0
                width: parent.width - 24
                text: "Aún no hay cuentas recordadas. Activa “Recordarme” al iniciar sesión."
                color: mutedColor(); font.pixelSize: fs(11); wrapMode: Text.WordWrap; horizontalAlignment: Text.AlignHCenter
            }
        }

        Rectangle {
            id: addAccountBtnV18
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: manageAccountsBtnV18.top
            anchors.leftMargin: 18
            anchors.rightMargin: 18
            anchors.bottomMargin: 14
            height: 58
            radius: 15
            color: addAccountMouseV18.pressed ? Qt.darker(inGeCoreFlow.theme.actionPrimary, 1.12) : inGeCoreFlow.theme.actionPrimary
            scale: addAccountMouseV18.pressed ? 0.98 : 1.0
            Behavior on scale { NumberAnimation { duration: inGeCoreFlow.fastDuration; easing.type: inGeCoreFlow.easeOut } }
            Components.FlowIcon {
                x: 18
                anchors.verticalCenter: parent.verticalCenter
                width: 27
                height: 27
                name: "profile.add"
                flow: inGeCoreFlow
                pressed: addAccountMouseV18.pressed
                tintColor: inGeCoreFlow.theme.onActionPrimary
                activeTintColor: inGeCoreFlow.theme.onActionPrimary
                inactiveOpacity: 1.0
            }
            Text { x: 56; width: parent.width - 74; anchors.verticalCenter: parent.verticalCenter; text: "Añadir otra cuenta"; color: inGeCoreFlow.theme.onActionPrimary; font.pixelSize: fs(13); font.bold: true; elide: Text.ElideRight }
            MouseArea { id: addAccountMouseV18; anchors.fill: parent; enabled: !accountSwitchBusyV20; onClicked: performAddAccountV18() }
        }

        Rectangle {
            id: manageAccountsBtnV18
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.leftMargin: 18
            anchors.rightMargin: 18
            anchors.bottomMargin: 18
            height: 58
            radius: 15
            color: manageAccountsMouseV18.pressed ? inGeCoreFlow.theme.pressed : card2Color()
            border.color: borderColor(); border.width: 1
            scale: manageAccountsMouseV18.pressed ? 0.98 : 1.0
            Behavior on scale { NumberAnimation { duration: inGeCoreFlow.fastDuration; easing.type: inGeCoreFlow.easeOut } }
            Components.FlowIcon {
                x: 18
                anchors.verticalCenter: parent.verticalCenter
                width: 23
                height: 23
                name: manageAccountsModeV18 ? "system.check" : "profile.account"
                flow: inGeCoreFlow
                active: manageAccountsModeV18
                pressed: manageAccountsMouseV18.pressed
                tintColor: primaryColor()
                activeTintColor: inGeCoreFlow.theme.success
                inactiveOpacity: 1.0
            }
            Text { x: 56; width: parent.width - 74; anchors.verticalCenter: parent.verticalCenter; text: manageAccountsModeV18 ? "Terminar gestión" : "Gestionar cuentas guardadas"; color: textColor(); font.pixelSize: fs(12); font.bold: true; elide: Text.ElideRight }
            MouseArea { id: manageAccountsMouseV18; anchors.fill: parent; onClicked: openManageAccountsV18() }
        }

        FlowCore.FlowBusyIndicator {
            anchors.centerIn: accountsListV20
            running: accountSwitchBusyV20
            visible: accountSwitchBusyV20
            width: 42
            height: 42
            flow: inGeCoreFlow
        }
    }
}

Rectangle {
    id: loginRedirectOverlayV18
    anchors.fill: parent
    z: 100010
    visible: loginRedirectOpenV18 || opacity > 0.01
    enabled: loginRedirectOpenV18
    opacity: loginRedirectOpenV18 ? 1.0 : 0.0
    color: bgColor()
    Behavior on opacity { NumberAnimation { duration: inGeCoreFlow.normalDuration; easing.type: inGeCoreFlow.easeStandard } }

    Rectangle {
        x: 18; y: Math.max(72, (parent.height - height) / 2 - 30)
        width: parent.width - 36; height: 340; radius: 24
        color: cardColor(); border.color: borderColor(); border.width: 1
        Image {
            width: 150; height: 76; anchors.horizontalCenter: parent.horizontalCenter; y: 24
            source: darkMode ? "qrc:/ui/v2/branding/logo_oficial_ingeplus_dark.png" : "qrc:/ui/v2/branding/logo_oficial_ingeplus_light.png"
            fillMode: Image.PreserveAspectFit; smooth: true
        }
        Text { x: 24; y: 126; width: parent.width - 48; text: loginRedirectTitleV18; color: textColor(); font.pixelSize: fs(22); font.bold: true; horizontalAlignment: Text.AlignHCenter; elide: Text.ElideRight }
        Text { x: 30; y: 172; width: parent.width - 60; text: loginRedirectSubtitleV18; color: mutedColor(); font.pixelSize: fs(12); wrapMode: Text.WordWrap; horizontalAlignment: Text.AlignHCenter }
        Rectangle {
            x: 24; y: 242; width: parent.width - 48; height: 48; radius: 15; color: inGeCoreFlow.theme.actionPrimary
            Text { anchors.centerIn: parent; text: "Iniciar sesión"; color: inGeCoreFlow.theme.onActionPrimary; font.pixelSize: fs(12); font.bold: true }
            MouseArea { anchors.fill: parent; onClicked: openLoginFromSessionClosedV800() }
        }
        Text {
            x: 24; y: 308; width: parent.width - 48; text: "Ver cuentas recordadas"; color: primaryColor(); font.pixelSize: fs(12); font.bold: true; horizontalAlignment: Text.AlignHCenter
            visible: savedAccountsModelV20.length > 0
            MouseArea { anchors.fill: parent; onClicked: openAccountPickerV800("sessionClosed") }
        }
    }
}

Rectangle {
    id: localToastV18
    z: 100020
    width: Math.min(parent.width - 40, Math.max(220, toastTextV18.implicitWidth + 42))
    height: Math.max(44, toastTextV18.implicitHeight + 20); radius: Math.min(22, height / 2)
    x: (parent.width - width) / 2
    y: (profileOverlayOpenV18 || accountSwitchSheetOpenV18) ? 118 : parent.height - height - 92
    color: inGeCoreFlow.colors.ingemaDeep
    opacity: localToastVisibleV18 ? 0.96 : 0.0
    visible: localToastVisibleV18 || opacity > 0.01
    transform: Translate { y: localToastVisibleV18 ? 0 : 10; Behavior on y { NumberAnimation { duration: inGeCoreFlow.normalDuration; easing.type: inGeCoreFlow.easeOut } } }
    Behavior on opacity { NumberAnimation { duration: inGeCoreFlow.normalDuration; easing.type: inGeCoreFlow.easeOut } }
    Text {
        id: toastTextV18
        anchors.fill: parent
        anchors.margins: 10
        text: localToastTextV18
        color: "#FFFFFF"
        font.pixelSize: 13
        font.bold: true
        wrapMode: Text.WordWrap
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
    }
}

// M01S02_ACCOUNT_FLOW_V20_END














// M01S02_FINAL_V5_HELPERS
function authAccentColor() {
    return inGeCoreFlow.theme.accent
}

function authAccentSoftColor() {
    return inGeCoreFlow.theme.infoContainer
}

// INGE_AUTH_BRANDING_V40: recursos definitivos Light/Dark.
// Mantiene el mismo flujo funcional y solo sustituye la identidad visual.
readonly property bool authUseCompactBackgroundV40: Math.max(width, height) <= 1800

function authBackgroundSourceV40() {
    if (darkMode)
        return authUseCompactBackgroundV40
                ? "qrc:/ui/v2/backgrounds/bg_auth_forest_dark_720x1600.png"
                : "qrc:/ui/v2/backgrounds/bg_auth_forest_dark_1080x2400.png"

    return authUseCompactBackgroundV40
            ? "qrc:/ui/v2/backgrounds/bg_auth_forest_light_720x1600.png"
            : "qrc:/ui/v2/backgrounds/bg_auth_forest_light_1080x2400.png"
}

function authBrandSourceV40() {
    return themeMode === 1
            ? "qrc:/ui/v2/branding/logo_oficial_ingeplus_dark.png"
            : "qrc:/ui/v2/branding/logo_oficial_ingeplus_light.png"
}

function authPrimaryTextV40() { return inGeCoreFlow.theme.textPrimary }
function authMutedTextV40() { return inGeCoreFlow.theme.textSecondary }
function authLinkColorV40() { return inGeCoreFlow.theme.accent }
function authDividerColorV40() { return inGeCoreFlow.theme.separator }

function openProfilePage() {
    try { if (sideDrawer && sideDrawer.close) sideDrawer.close() } catch(e) {}
    try { if (mainDrawer && mainDrawer.close) mainDrawer.close() } catch(e) {}
    try { if (drawer && drawer.close) drawer.close() } catch(e) {}
    navigateToPage(4)
}

// M01_LIMPIEZA_PERFIL_V25_2_FINAL: drawer de Ajustes eliminado completamente.
// M03_HOME_V27_FINAL: Home definitivo, limpio y con navegación controlada.
// M04_ICONOS_V28_FINAL: catalogo semantico y microinteracciones InGeCoreFlow.
// M04_V28_1_FIX_ARRANQUE: corrige propiedades AuthInlineField y ModuleCardV2.
// INGECOREFLOW_TEXTO_V29: nombres visuales corregidos; correos exactos.
// M05_INGECOREFLOW_V31: gestos táctiles, física adaptativa y translucidez.
// INGECOREFLOW_V32_DEEPPRESS: globo contextual y ajustes rápidos.
// Acciones contextuales de Configuracion.
// M06_BUSCADOR_GLOBAL_V30_FINAL: búsqueda real con categorías y acciones.


id: app
property var activeCalicataEditor: null
// P0: {projectId, calicataId} pedido desde Documentos/InGeDrive mientras la
// subapp Calicatas aún no existe; el editor lo consume al crearse.
property var pendingCloudCalicataOpen: null
property var pendingCalicataExcelOpen: null
// ===== Salida segura de Calicatas (crash SIGSEGV en QQuickFlickable::touchEvent) =====
// El Back nativo cambiaba pageIndex en el mismo delivery: el Loader destruía el
// editor mientras su Flickable seguía con el grab táctil. Ahora: guard, se
// suelta el input (editor deshabilitado + cancelFlick) y la navegación ocurre
// en un turno posterior del event loop.
property bool leavingCalicatas: false
property bool calicataDockSuppressed: false
function setCalicataDockSuppressed(suppressed, reason) {
    if (calicataDockSuppressed === suppressed) return
    calicataDockSuppressed = suppressed
    console.info(suppressed ? "INGE_CALICATA_DOCK_SUPPRESS reason=" + reason : "INGE_CALICATA_DOCK_RESTORE")
}
function leaveCalicatasSafely() {
    if (leavingCalicatas) {
        console.info("INGE_CALICATA_LEAVE_IGNORED leaving=true")
        return true
    }
    leavingCalicatas = true
    var editor = app.activeCalicataEditor
    var state = editor && typeof editor.prepareForLeave === "function" ? editor.prepareForLeave() : ({})
    console.info("INGE_CALICATA_LEAVE_BEGIN touchActive=" + (state.touchActive === true)
                 + " flickActive=" + (state.flickActive === true) + " leaving=true")
    console.info("INGE_CALICATA_LEAVE_DEFERRED")
    calicataLeaveTimer.restart()
    return true
}
Timer {
    id: calicataLeaveTimer
    interval: 48          // > 1 frame: el pointer event actual termina antes
    repeat: false
    onTriggered: {
        console.info("INGE_CALICATA_LEAVE_EXECUTE")
        app.setCalicataDockSuppressed(false, "")
        if (app.pageIndex === 1) app.navigateToPage(0)
        calicataLeaveDone.restart()
    }
}
Timer {
    id: calicataLeaveDone
    interval: 1
    repeat: false
    onTriggered: {
        app.leavingCalicatas = false
        console.info("INGE_CALICATA_LEAVE_DONE")
    }
}
onActiveCalicataEditorChanged: {
    if (activeCalicataEditor && pendingCloudCalicataOpen) {
        var request = pendingCloudCalicataOpen
        pendingCloudCalicataOpen = null
        activeCalicataEditor.openCloudCalicata(request.projectId, request.calicataId)
    }
    if (activeCalicataEditor && pendingCalicataExcelOpen) {
        var excel = pendingCalicataExcelOpen
        pendingCalicataExcelOpen = null
        activeCalicataEditor.importCalicataExcel(excel.path, excel.source)
    }
}
// InGeDrive → "Abrir con Calicatas" (.xlsx): importa en el editor real.
function openCalicataExcel(localPath, source) {
    console.info("INGE_CALICATA_EXCEL_OPEN_REQUEST")
    if (activeCalicataEditor) activeCalicataEditor.importCalicataExcel(String(localPath), source)
    else pendingCalicataExcelOpen = { path: String(localPath), source: source }
    navigateToPage(1)
}
function openCloudCalicata(projectId, calicataId) {
    console.info("INGE_CALICATA_OPEN_REQUEST projectId=" + projectId + " calicataId=" + calicataId)
    if (activeCalicataEditor) activeCalicataEditor.openCloudCalicata(projectId, calicataId)
    else pendingCloudCalicataOpen = { projectId: String(projectId), calicataId: String(calicataId) }
    navigateToPage(1)
}

// Qt 6.9 expone el inset real de barras/gestos mediante SafeArea. Se
// importa con alias para conservar el resto del archivo en QtQuick 2.15.
readonly property real safeBottomInsetV49:
    Math.max(0.0, Qt69.SafeArea.margins.bottom)

// =============================================================
// V41 — Persistencia, ciclo de vida y navegación segura
// =============================================================
Settings {
    id: appSettingsV41
    category: "InGePlus/Main"
    property bool guestSessionActive: false
    property real lastFontScale: 1.0
    property bool lastReduceMotion: false
    property int lastPerformanceLevel: -1
    // "auto": the level follows the device tier; "user": lastPerformanceLevel
    // was picked in Ajustes. Empty only on installs before this key existed.
    property string performanceSource: ""
}

property bool appActiveV41: Qt.application.state === Qt.ApplicationActive
property double lastBackPressEpochV41: 0

function persistUiStateV41() {
    appSettingsV41.lastFontScale = fontScale
    appSettingsV41.lastReduceMotion = reduceMotion
    if (!performanceAutomaticV90)
        appSettingsV41.lastPerformanceLevel = flowPerformanceLevel
}

// =============================================================
// V90 — Perfil de rendimiento automatico por dispositivo
// =============================================================
// Until the user picks a level in Ajustes it follows the device tier that
// Android computes (InGeCoreFlow.automaticPerformanceLevel), live: battery
// saver or heat lower it and it comes back on its own. A picked level is
// kept and persisted. Severe thermal throttling caps any level.
readonly property bool performanceAutomaticV90: appSettingsV41.performanceSource !== "user"
readonly property int effectivePerformanceLevelV90:
    Math.min(flowPerformanceLevel, Mobile.InGeCoreFlow.systemPerformanceCap)

// Installs before performanceSource persisted the old default (2) on their
// own, indistinguishable from a picked "Alto". Keep a stored level, except on
// LOW/ULTRA_LOW devices, where that default is what overloaded the GPU.
function resolvePerformanceSourceV90() {
    if (appSettingsV41.performanceSource !== "")
        return
    if (Qt.platform.os === "android" && Mobile.InGeCoreFlow.deviceTier === "UNKNOWN")
        return
    var legacyLevel = appSettingsV41.lastPerformanceLevel
    var source = legacyLevel >= 0 && Mobile.InGeCoreFlow.automaticPerformanceLevel > 0
            ? "user" : "auto"
    appSettingsV41.performanceSource = source
    if (source === "user")
        flowPerformanceLevel = Math.max(0, Math.min(2, legacyLevel))
    console.info("INGE_PERFORMANCE_SOURCE_MIGRATED source=" + source
                 + " legacyLevel=" + legacyLevel
                 + " tier=" + Mobile.InGeCoreFlow.deviceTier)
}

Binding {
    target: app
    property: "flowPerformanceLevel"
    value: Mobile.InGeCoreFlow.automaticPerformanceLevel
    when: app.performanceAutomaticV90
    restoreMode: Binding.RestoreNone
}

Connections {
    target: Mobile.InGeCoreFlow
    function onDeviceTierChanged() { app.resolvePerformanceSourceV90() }
}

function cyclePerformanceLevelV90() {
    // Automatico -> Ahorro -> Balance -> Alto -> Automatico
    if (performanceAutomaticV90) {
        appSettingsV41.performanceSource = "user"
        flowPerformanceLevel = 0
    } else if (flowPerformanceLevel < 2) {
        flowPerformanceLevel = flowPerformanceLevel + 1
    } else {
        appSettingsV41.performanceSource = "auto"
    }
    if (!performanceAutomaticV90) {
        appSettingsV41.lastPerformanceLevel = flowPerformanceLevel
        try { firstExperience.performanceLevel = flowPerformanceLevel } catch(e) {}
    }
}

function performanceLevelNameV90(level) {
    return level <= 0 ? "Ahorro" : (level >= 2 ? "Alto" : "Balance")
}

function clearPersistedGuestV41() {
    appSettingsV41.guestSessionActive = false
}

// Devuelve true cuando el evento Atrás fue consumido por la navegación interna.
// Solo se permite cerrar QtActivity desde la raíz y con doble pulsación.
function routeAndroidBack() {
    var contexts = ["HOME", "CALICATAS", "EARTH", "DOCUMENTS", "SETTINGS", "INVENTORY", "RENDITIONS"]
    console.info("INGE_BACK_CONTEXT=" + (contexts[pageIndex] || "SUBAPP"))
    var result = handleBackNavigationV41(true)
    if (typeof result === "string")
        return result
    console.info("INGE_BACK_CONSUMED=" + (result ? "YES" : "NO"))
    return result ? "CONSUMED" : "EXIT_HOME"
}

function handleBackNavigationV41(nativeRequest) {
    // Mientras se sale de Calicatas, cualquier Back extra se consume sin efecto.
    if (leavingCalicatas) {
        console.info("INGE_CALICATA_LEAVE_IGNORED back=repeat")
        return true
    }
    // V50: el primer Back pertenece siempre al IME. La navegacion y el
    // cierre de QtActivity solo se evaluan en una segunda pulsacion.
    if (inGeCoreFlow.imeVisible) {
        Qt.inputMethod.hide()
        return true
    }

    // The dock context menu is the topmost transient layer: Back walks one
    // branch level up, then closes it.
    if (globalContextDockV1.handleBack()) {
        console.info("INGE_BACK_ACTION=DOCK_MENU_LEVEL")
        return true
    }

    if (profileOverlayOpenV18) {
        closeProfileOverlayV18()
        return true
    }

    if (accountSwitchSheetOpenV18) {
        closeAccountSwitchSheetV18()
        return true
    }

    if (loginRedirectOpenV18) {
        openLoginFromSessionClosedV800()
        return true
    }

    // Durante LOGGING_OUT o un cambio de cuenta el Back no dispara otra
    // operación ni revela estados intermedios.
    if (authFlowStateV800 === "LOGGING_OUT"
            || authFlowStateV800 === "ACCOUNT_SWITCHING")
        return true

    if (flowSuccessVisible) {
        try { flowSuccessSequence.stop() } catch(e0) {}
        flowSuccessVisible = false
        flowSuccessOverlay.opacity = 0.0
        return true
    }

    try {
        if (quickBubbleV32.presented) {
            quickBubbleV32.close()
            return true
        }
    } catch(e1) {}

    try {
        if (globalSearchOverlayV30.presented) {
            globalSearchOverlayV30.close()
            return true
        }
    } catch(e2) {}

    if (addingAccountModeV20) {
        cancelAddAccountV20()
        return true
    }

    if (flutterSecurityOpenV70) {
        setFlutterSecuritySurfaceV70(false)
        console.info("INGE_BACK_ACTION=CLOSE_SECURITY")
        return true
    }

    if (nativeRequest === true && app.calicataProjectPickerOpen) return "RENDITIONS"
    if (nativeRequest === true && (pageIndex === 2 || pageIndex === 6))
        return pageIndex === 2 ? "EARTH" : "RENDITIONS"

    if (pageIndex !== 0) {
        var currentPage = pageIndex === 1 ? app.activeCalicataEditor : pageLoader.item

        // Nunca invoques handleBack() a ciegas. En cargas parciales el
        // Loader puede existir antes de que la página exponga el método.
        if (currentPage && typeof currentPage.handleBack === "function"
                && currentPage.handleBack()) {
            console.info("INGE_BACK_ACTION=INTERNAL_BACK")
            return true
        }

        // En Calicatas canGoBack() es historial de pestañas, no de etapas:
        // en General el Back debe volver al Home, no saltar a otra ficha.
        if (pageIndex !== 1 && currentPage && typeof currentPage.canGoBack === "function"
                && currentPage.canGoBack()
                && typeof currentPage.goBackHistory === "function") {
            currentPage.goBackHistory()
            console.info("INGE_BACK_ACTION=INTERNAL_BACK")
            return true
        }

        console.info("INGE_BACK_ACTION=RETURN_HOME")

        if (pageIndex === 1) return leaveCalicatasSafely()
        navigateToPage(0)
        return true
    }

    console.info("INGE_BACK_ACTION=HOME_EXIT_POLICY")
    var now = Date.now()
    if (now - lastBackPressEpochV41 > 1800) {
        lastBackPressEpochV41 = now
        showToast("Presiona Atrás otra vez para salir")
        return true
    }

    return false
}

onClosing: function(close) {
    if (handleBackNavigationV41())
        close.accepted = false
}

// Referencias explícitas a los objetos de contexto compartidos.
readonly property var authContextV23: (typeof auth !== "undefined" ? auth : null)
readonly property var dropboxContextV23: (typeof dropbox !== "undefined" ? dropbox : null)

// =============================================================
// InGeCoreFlow - motor interno de fluidez visual y microinteracciones
// Basado en la identidad técnica definida para INGEMA Flow Core.
// Solo anima propiedades baratas en GPU: opacity, scale y translate.
// =============================================================
property bool flowCoreEnabled: true
property bool reduceMotion: false
// 0 = sin movimiento, 1 = discreto, 2 = completo. Se deja en 2 por defecto.
property int flowMotionLevel: 2
// Perfil equilibrado por defecto. El perfil "high" se reserva para equipos
// que lo seleccionen explícitamente; evita sobrecargar GPU/main thread al arrancar.
property int flowPerformanceLevel: 1
function setPageImmediate(targetPage) {
    pageIndex = inGeCoreFlow.clampPage(targetPage, 0, 6)
}

function playPageEnterV600() {
    pageEnterAnimationV600.stop()
    if (!inGeCoreFlow.motionAllowed) {
        pageLoader.opacity = 1.0
        pageEnterTranslateV600.y = 0
        return
    }
    pageLoader.opacity = 0.0
    pageEnterTranslateV600.y = 7
    pageEnterAnimationV600.start()
}

ParallelAnimation {
    id: pageEnterAnimationV600
    OpacityAnimator {
        target: pageLoader
        from: 0.0; to: 1.0
        duration: inGeCoreFlow.pageInDuration
        easing.type: Easing.OutCubic
    }
    NumberAnimation {
        target: pageEnterTranslateV600
        property: "y"
        from: 7; to: 0
        duration: inGeCoreFlow.pageInDuration
        easing.type: Easing.OutCubic
    }
    onStopped: {
        pageLoader.opacity = 1.0
        pageEnterTranslateV600.y = 0
    }
}

function navigateToPage(targetPage) {
    targetPage = inGeCoreFlow.clampPage(targetPage, 0, 6)
    navigationStartedAtV80 = Date.now()
    navigationTargetV80 = targetPage
    if (targetPage === 6 && pageIndex !== 6)
        console.info("RENDITIONS_ROUTE_OPEN")
    // Crossfade real: la página saliente se congela en una textura (un frame)
    // y se desvanece encima mientras la nueva entra. Sin motion: inmediato.
    if (targetPage === pageIndex || !inGeCoreFlow.motionAllowed
            || !pageLoader.item || !(loggedIn || guestMode)) {
        pageSwitchCommitV600.stop()
        pendingPageV600 = -1
        setPageImmediate(targetPage)
        return
    }
    pendingPageV600 = targetPage
    if (pageSwitchCommitV600.running)
        return
    pageSnapshotFadeV600.stop()
    pageSnapshotV600.sourceItem = pageLoader
    pageSnapshotV600.opacity = 0.004
    pageSnapshotV600.scheduleUpdate()
    pageSwitchCommitV600.restart()
}

property int pendingPageV600: -1

Timer {
    id: pageSwitchCommitV600
    // Dos frames: el snapshot se captura en el siguiente sync del render.
    interval: 34
    repeat: false
    onTriggered: {
        var target = app.pendingPageV600
        app.pendingPageV600 = -1
        if (target < 0)
            return
        pageSnapshotV600.opacity = 1.0
        app.setPageImmediate(target)
        // Hacia superficies nativas (Home/Rendiciones/Earth) la vista nativa
        // entra encima; la saliente permanece un poco más debajo.
        pageSnapshotFadeV600.duration = (target === 0 || target === 2 || target === 6) ? 240 : 130
        pageSnapshotFadeV600.restart()
    }
}

OpacityAnimator {
    id: pageSnapshotFadeV600
    target: pageSnapshotV600
    from: 1.0
    to: 0.0
    duration: 130
    easing.type: Easing.InCubic
    onFinished: {
        pageSnapshotV600.opacity = 0.0
        pageSnapshotV600.sourceItem = null
    }
}

property double navigationStartedAtV80: 0
property int navigationTargetV80: -1
property bool forceFirstExperiencePreview: false
property bool forceFirstExperienceShowcase: false

readonly property var inGeCoreFlow: Mobile.InGeCoreFlow
readonly property var geminiAssistantTransport: InGeAssistant

// The web console consumes the existing global material and motion tokens.
function assistantVisuals() {
    var t = inGeCoreFlow.theme
    function css(c) {
        return "rgba(" + Math.round(c.r * 255) + "," + Math.round(c.g * 255) + ","
            + Math.round(c.b * 255) + "," + c.a + ")"
    }
    return { glass: css(t.glassRegular), glassStrong: css(t.glassEmphasized),
        line: css(t.glassBorder), highlight: css(t.glassHighlight), shadow: css(t.glassShadow),
        text: css(t.textPrimary), muted: css(t.textSecondary), accent: css(t.accent),
        error: css(t.error), fast: inGeCoreFlow.fastDuration, normal: inGeCoreFlow.normalDuration,
        sheet: inGeCoreFlow.sheetDuration, motion: inGeCoreFlow.motionAllowed,
        blur: inGeCoreFlow.performanceLevel > 0 ? 18 : 0 }
}
Connections {
    target: app.geminiAssistantTransport
    function onOpeningRequested() { app.geminiAssistantTransport.open(app.assistantVisuals()) }
}
Connections {
    target: app.inGeCoreFlow
    function onMotionAllowedChanged() { app.geminiAssistantTransport.updateVisuals(app.assistantVisuals()) }
    function onPerformanceLevelChanged() { app.geminiAssistantTransport.updateVisuals(app.assistantVisuals()) }
    function onDarkModeChanged() { app.geminiAssistantTransport.updateVisuals(app.assistantVisuals()) }
}

Binding {
    target: Mobile.InGeCoreFlow
    property: "enabled"
    value: app.flowCoreEnabled
}

Binding {
    target: Mobile.InGeCoreFlow
    property: "reduceMotion"
    value: app.reduceMotion
}

Binding {
    target: Mobile.InGeCoreFlow
    property: "motionLevel"
    value: app.flowMotionLevel
}

Binding {
    target: Mobile.InGeCoreFlow
    property: "performanceLevel"
    value: app.effectivePerformanceLevelV90
}

Binding {
    target: Mobile.InGeCoreFlow
    property: "imeViewportHeight"
    value: app.height
}

Binding {
    target: Mobile.InGeCoreFlow.performance
    property: "profile"
    value: app.effectivePerformanceLevelV90 >= 2
           ? Mobile.InGeCoreFlow.performance.high
           : (app.effectivePerformanceLevelV90 <= 0
              ? Mobile.InGeCoreFlow.performance.safe
              : Mobile.InGeCoreFlow.performance.balanced)
}

// Misma escala efectiva que fs(): FlowText, FlowField y FlowIconButton la
// aplican con accessibility.scaledTextSize().
Binding {
    target: Mobile.InGeCoreFlow.accessibility
    property: "textScale"
    value: app.effectiveTextScale
}










// =============================================================
// Módulo 06 — Buscador global
// =============================================================
function openGlobalSearchV30(initialText) {
    if (!(loggedIn || guestMode))
        return

    globalSearchOverlayV30.open(initialText || "")
}

function handleGlobalSearchResultV30(kind, payload, titleText) {
    if (payload === "calicata_new" || payload === "calicata_editor") {
        navigateToPage(1)
        return
    }

    if (payload === "map") {
        navigateToPage(2)
        return
    }

    if (payload === "docs") {
        navigateToPage(3)
        return
    }

    if (payload === "renditions") {
        navigateToPage(6)
        return
    }

    if (payload === "exports_excel") {
        navigateToPage(3)
        return
    }

    if (payload === "profile") {
        openProfileOverlayV18()
        return
    }

    if (payload === "settings") {
        navigateToPage(4)
        return
    }

    showToast(titleText && String(titleText).length > 0
              ? String(titleText)
              : "Resultado abierto")
}

visible: true
width: 412
height: 860
title: "InGe+ Mobile 1.0.8"
color: bgColor()

property bool setupComplete: true
property int setupStep: 0
// Base visual temporal única: apariencia normal clara.
property int themeMode: 0
property bool themeSyncing: false
property bool darkMode: false
readonly property bool liquidGlass: false
property bool loggedIn: false
property bool guestMode: false
property bool serverBusy: false
property bool serverConnected: false
property int pageIndex: 0
property string toastText: ""
property string flowSuccessText: ""
property bool flowSuccessVisible: false

property string userEmail: ""
property string userPassword: ""
property string currentUserName: "Invitado"
property string welcomeText: "Te damos la bienvenida a InGe+"
property url profilePhotoSource: icon("blank_profile.png")
property string profilePhotoStatus: "Foto de perfil local"
property real fontScale: 1.0
// Escala de texto unica: ajuste A-/A+ de la app (fontScale, el unico que se
// persiste) por el tamaño de fuente de Android (Configuration.fontScale, en
// vivo via GraphicsCore). El tope 1.30 es el mismo maximo que A+ ya permitia:
// una fuente del sistema al 130-200 % no lleva fs() mas alla del tamaño que
// ya alcanzaba con A+ y que soportan sus filas de alto fijo. La usan fs() y,
// por el Binding de InGeCoreFlow.accessibility, FlowText/FlowField.
readonly property real effectiveTextScale:
    Math.max(0.85, Math.min(1.30, fontScale * Mobile.InGeCoreFlow.systemFontScale))
property string languageCode: "es"

property string fichaTipo: "Calicata"
property string calCode: ""
property string calProject: ""
property string calSupervisor: ""
property string calPk: ""
property string calDate: Qt.formatDate(new Date(), "dd/MM/yyyy")
property string calDepth: ""
property string calLat: ""
property string calLng: ""
property string calAlt: ""
property string calLayer1: ""
property string calLayer2: ""
property string calLayer3: ""
property string calObs: ""

property url logoMtcSource: icon("Logo_MTC.jpeg")
property url logoProjectSource: icon("app_logo_company.png")
property string logoTarget: "mtc"

property int photoTarget: 1
property url photo1Source: ""
property url photo2Source: ""
property url photo3Source: ""
property string photo1Name: ""
property string photo2Name: ""
property string photo3Name: ""

property real mapCenterLat: -11.9611889
property real mapCenterLng: -77.0457117
property int mapZoom: 16
property real mapOffsetX: 0
property real mapOffsetY: 0
property int mapTilesReady: 0
property int mapTilesError: 0
property bool mapGestureBusy: false
property int mapStyle: 0
property bool mapReady: false
property bool gpsFollow: false
property bool gpsHasFix: false
property real gpsLat: NaN
property real gpsLng: NaN
property real gpsAlt: NaN
property string gpsStatus: "GPS pendiente"
// MODULOS_08_09_V35: coordinador GPS unico para Mapa y Calicatas.
property bool gpsRequestedM0809: false
// Permite reiniciar el proveedor nativo sin perder la intencion del usuario.
// Es necesario al volver de Ajustes o al reintentar despues de un ClosedError.
property bool gpsProviderGateM0809: true
property bool gpsServiceEnabledM0809: false
property bool gpsActivationPromptShownM0809: false
// V38.7: acepta una primera ubicación híbrida razonable para mostrar
// el punto azul de inmediato, pero sigue rechazando lecturas de kilómetros.
// El servicio combina GPS, Wi-Fi y red del dispositivo.
// V38.6: una lectura de red con ±2000 m ya no se presenta como GPS real.
// Solo las lecturas recientes y suficientemente precisas actualizan el
// punto azul. Las imprecisas se conservan únicamente como diagnóstico.
readonly property real gpsMaximumAcceptedAccuracyM0809: 250.0
readonly property real gpsExcellentAccuracyM0809: 30.0
property real gpsAccuracyM0809: NaN
property real gpsRawAccuracyM0809: NaN
property real gpsLastAcceptedEpochM0809: 0
property int gpsRejectedFixCountM0809: 0
property string gpsLastUpdateM0809: "--:--:--"
property string gpsProviderM0809: ""
property string gpsErrorM0809: ""
readonly property bool gpsPermissionGrantedM0809: !!Perms.nativePermissionGranted
readonly property string gpsPermissionStateM0809: String(Perms.nativePermissionStatus || "undetermined")

property string serverStatus: "Servidor listo"
property string assistantStatus: "Listo"

property string dropboxFolder: "/INGEMA/InGePlus/Fichas"
property bool dropboxConnected: false
property string dropboxStatus: "Dropbox pendiente"
property string lastExcelPath: ""
property bool googleLoginAvailable: true
property string googleLoginStatus: "Google listo"

property string assistantText: "InGe+ 1.0.2 corrige el interfaz: las pantallas usan Flickable estable, sin capas invisibles encima."

function icon(name) { return IconCatalog.legacy(name) }
function propA(path) { return "qrc:/ui/ingeplus/propuesta_a/" + path }
function propAThemeDir() { return darkMode ? "02_icons_dark" : "01_icons_light" }
function propAThemeName() { return darkMode ? "dark" : "light" }
function propAIcon(category, base) { return propA(propAThemeDir() + "/" + category + "/png_3x/" + base + "_" + propAThemeName() + "@3x.png") }
function propACalIcon(base) { return propAIcon("calicatas", base) }
function propAActionIcon(base) { return propAIcon("actions", base) }
function primaryColor() { return inGeCoreFlow.theme.accent }
function greenColor() { return inGeCoreFlow.theme.success }
function orangeColor() { return inGeCoreFlow.theme.warning }
function bgColor() { return inGeCoreFlow.theme.background }
function panelColor() { return inGeCoreFlow.theme.surface }
function cardColor() { return inGeCoreFlow.theme.surface }
function card2Color() { return inGeCoreFlow.theme.surfaceSecondary }
function borderColor() { return inGeCoreFlow.theme.border }
function textColor() { return inGeCoreFlow.theme.textPrimary }
function mutedColor() { return inGeCoreFlow.theme.textSecondary }
function fs(n) { return Math.max(9, Math.round(n * effectiveTextScale)) }
function pageThemeModeV70() { return 0 }

function setVisualThemeMode(mode, announce) {
    themeSyncing = true
    themeMode = 0
    darkMode = false
    inGeCoreFlow.setThemeMode(0)
    themeSyncing = false
    persistUiStateV41()

    if (announce === true)
        showToast("Apariencia normal activa")
}

onThemeModeChanged: {
    if (!themeSyncing)
        setVisualThemeMode(themeMode, false)
}

onDarkModeChanged: {
    if (!themeSyncing)
        setVisualThemeMode(darkMode ? 1 : 0, false)
}

onFontScaleChanged: {
    if (appSettingsV41)
        appSettingsV41.lastFontScale = fontScale
}

onReduceMotionChanged: {
    if (appSettingsV41)
        appSettingsV41.lastReduceMotion = reduceMotion
}

onFlowPerformanceLevelChanged: {
    if (appSettingsV41 && !performanceAutomaticV90)
        appSettingsV41.lastPerformanceLevel = flowPerformanceLevel
}

function settingsQuickActionsV32() {
    return [
        {
            key: "motion",
            label: reduceMotion
                   ? "Activar animaciones"
                   : "Reducir movimiento",
            subtitle: reduceMotion
                      ? "Restaurar transiciones"
                      : "Menos efectos visuales",
            icon: "system.check"
        },
        {
            key: "text",
            label: fontScale >= 1.14
                   ? "Restablecer texto"
                   : "Aumentar texto",
            subtitle: "Tamaño actual: "
                      + Math.round(fontScale * 100)
                      + "%",
            icon: "action.add"
        },
        {
            key: "settings",
            label: "Abrir configuración",
            subtitle: "Ver todos los ajustes",
            icon: "nav.settings"
        }
    ]
}

function openSettingsQuickBubbleV32(anchorItem) {
    if (!anchorItem || globalSearchOverlayV30.presented)
        return

    if (quickBubbleV32.presented) {
        quickBubbleV32.close()
        return
    }

    quickBubbleV32.openFor(
                anchorItem,
                "Ajustes rápidos",
                settingsQuickActionsV32()
            )
}

// Impide que un swipe horizontal quite el foco mientras el usuario está
// escribiendo. Los controles de texto de Qt exponen cursorPosition,
// selectionStart o echoMode; la comprobación no altera el dato escrito.
function textEntryActiveV34() {
    try {
        var item = app.activeFocusItem
        if (!item || item.focus !== true)
            return false

        return item.cursorPosition !== undefined
                || item.selectionStart !== undefined
                || item.echoMode !== undefined
                || item.inputMethodHints !== undefined
    } catch (e) {
        return false
    }
}

// P0 global IME/foco (V61). Un TextInput/TextEdit que RECUPERA el foco activo
// vuelve a pedir el teclado (focusOnPress -> InsetsController.show(ime)).
// Esa recuperación implícita ocurría (1) al cerrar un Popup, porque Qt
// devuelve el foco al ítem/ámbito que lo tenía antes de abrirse, y (2) porque
// el Done de Android puede solo ocultar el IME sin quitar el foco al editor.
// Limpiar `focus` (V60) no basta si Qt reenfoca el ítem guardado. Contrato
// único de la ventana QML (Auth es Flutter y aplica el suyo en home.dart):
//  A) Enter/Done en una línea (`accepted`) o teclado cerrado -> commit
//     (editingFinished) y el foco pasa a un dueño neutro real.
//  B) Un Popup que toma el foco libera al editor y cierra el IME.
//  C) Si al cerrarse ese Popup Qt reenfoca a ese mismo editor sin que el
//     usuario lo haya tocado, es restauración implícita: vuelve al neutro.
//  D) TextArea/TextEdit no emiten `accepted`: Enter = salto de línea.
//  E) Siguiente: si onAccepted movió el foco a otro editor, se respeta.
// La validación que reclama el foco (forceActiveFocus) también se respeta.
Item {
    id: textFocusNeutralV61
    width: 0
    height: 0
    activeFocusOnTab: false
}

// Marca cualquier toque sobre el contenido (no sobre Popups modales): así un
// reenfoque tocado por el usuario nunca se confunde con una restauración.
Item {
    anchors.fill: parent
    z: 100000
    PointHandler {
        onActiveChanged: if (active) app.popupReleasedEditorV61 = null
    }
}

property Item textFocusOwnerV60: null
property Item popupReleasedEditorV61: null

function isTextEditorV60(item) {
    return !!item && item.cursorPosition !== undefined && item.selectionStart !== undefined
}

// Acceso dinámico a miembros de TextInput/TextEdit desde un Item genérico.
function textMemberV60(editor, name) {
    return editor ? editor[name] : undefined
}

// commit/hide del IME (Qt.inputMethod no expone metadata estática completa).
function imeCallV61(name) {
    try {
        var method = app.textMemberV60(Qt.inputMethod, name)
        if (method)
            method.call(Qt.inputMethod)
    } catch (e) {}
}

function inOverlayV61(item) {
    var overlay = textFocusNeutralV61.Overlay.overlay
    for (var node = item; node; node = node.parent)
        if (node === overlay)
            return true
    return false
}

// Suelta el editor activo: commit, sin foco de ámbito y foco en el neutro.
function releaseTextFocusV61() {
    var editor = app.activeFocusItem
    if (!app.isTextEditorV60(editor))
        return
    app.imeCallV61("commit")
    editor.focus = false
    // La validación puede reclamar el foco (forceActiveFocus): se respeta.
    if (editor.activeFocus)
        return
    // Dentro de un Popup el foco queda en el propio Popup (Back sigue ahí).
    if (!app.inOverlayV61(editor))
        textFocusNeutralV61.forceActiveFocus()
    app.imeCallV61("hide")
}

function releaseAcceptedTextV60() {
    var editor = app.textFocusOwnerV60
    Qt.callLater(function() {
        // E) onAccepted pudo mover el foco a otro editor (Siguiente).
        if (editor && editor.activeFocus)
            app.releaseTextFocusV61()
    })
}

onActiveFocusItemChanged: {
    var previous = app.textFocusOwnerV60
    var next = app.activeFocusItem
    if (previous === next)
        return
    if (previous) {
        try { app.textMemberV60(previous, "accepted").disconnect(app.releaseAcceptedTextV60) } catch (e) {}
        if (!previous.activeFocus) {
            previous.focus = false
            // B) Un Popup tomó el foco: se recuerda el editor y se cierra el IME.
            if (next && app.inOverlayV61(next) && !app.inOverlayV61(previous)) {
                app.popupReleasedEditorV61 = previous
                app.imeCallV61("hide")
            }
        }
    }
    // C) Qt reenfoca el editor liberado por el Popup sin toque del usuario.
    if (next && next === app.popupReleasedEditorV61) {
        app.popupReleasedEditorV61 = null
        app.textFocusOwnerV60 = null
        Qt.callLater(app.releaseTextFocusV61)
        return
    }
    app.textFocusOwnerV60 = app.isTextEditorV60(next) ? next : null
    // Solo editores de una línea (TextInput/TextField exponen echoMode/accepted).
    var singleLine = app.textFocusOwnerV60
    if (singleLine && app.textMemberV60(singleLine, "echoMode") !== undefined) {
        try { app.textMemberV60(singleLine, "accepted").connect(app.releaseAcceptedTextV60) } catch (e) {}
    }
}

// A) Teclado cerrado (Done sin `accepted`, Back): el editor no conserva el
// foco. Breve espera para no reaccionar al cambio de teclado entre campos.
Connections {
    target: Mobile.InGeCoreFlow
    function onImeVisibleChanged() {
        if (Mobile.InGeCoreFlow.imeVisible)
            imeClosedReleaseV61.stop()
        else
            imeClosedReleaseV61.restart()
    }
}

Timer {
    id: imeClosedReleaseV61
    interval: 250
    repeat: false
    onTriggered: {
        if (!Mobile.InGeCoreFlow.imeVisible)
            app.releaseTextFocusV61()
    }
}

function cycleTextScaleV32() {
    if (fontScale < 1.14)
        fontScale = 1.15
    else
        fontScale = 1.0

    persistUiStateV41()
    showToast("Tamaño de texto: "
              + Math.round(fontScale * 100)
              + "%")
}

function handleQuickBubbleActionV32(actionKey) {
    var key = String(actionKey || "")

    if (key === "motion") {
        reduceMotion = !reduceMotion
        persistUiStateV41()
        showToast(reduceMotion
                  ? "Movimiento reducido"
                  : "Animaciones activadas")
        return
    }

    if (key === "text") {
        cycleTextScaleV32()
        return
    }

    if (key === "settings") {
        navigateToPage(4)
        return
    }
}

function showToast(msg) {
    toastText = msg
    toastTimer.restart()
}

// Dispatcher único compartido por Accesos rápidos.
// No navega a otra Sub App ni crea un segundo motor de sincronización.
function renditionPendingCountV60() {
    try {
        if (typeof renditionLocalStore !== "undefined"
                && renditionLocalStore
                && typeof renditionLocalStore.pendingCount !== "undefined")
            return Math.max(0, Number(renditionLocalStore.pendingCount) || 0)
    } catch (e) {}
    return 0
}

function dispatchGlobalSyncV60() {
    var controllerReady = false
    try {
        controllerReady = typeof renditionSyncController !== "undefined"
                && renditionSyncController
                && typeof renditionSyncController.synchronize === "function"
        if (controllerReady)
            renditionSyncController.synchronize()
    } catch (e) {
        controllerReady = false
    }

    var pending = renditionPendingCountV60()
    showToast(controllerReady
              ? (pending > 0
                 ? "Sincronizando cambios pendientes"
                 : "No hay cambios pendientes por sincronizar")
              : "Sincronización de Rendiciones no disponible")
}

function showFlowSuccess(msg) {
    flowSuccessText = String(msg || "Listo")
    flowSuccessVisible = true
    flowSuccessSequence.restart()
}

function safeUserNameFromEmail(mail) {
    var e = String(mail || "")
    if (e.indexOf("@") > 0) return e.split("@")[0]
    if (e.length > 0) return e
    return "usuario"
}

function updateWelcomeFromAuth() {
    var name = ""
    try {
        if (typeof auth !== "undefined" && auth) {
            if (typeof auth.fullName !== "undefined" && String(auth.fullName).length > 0)
                name = String(auth.fullName)
            if (name.length === 0 && typeof auth.nombre !== "undefined" && String(auth.nombre).length > 0)
                name = String(auth.nombre)
            if (name.length === 0 && typeof auth.email !== "undefined" && String(auth.email).length > 0)
                name = safeUserNameFromEmail(auth.email)
        }
    } catch (e) {}
    if (name.length === 0)
        name = safeUserNameFromEmail(userEmail)

    try {
        if (typeof auth !== "undefined" && auth) {
            if (typeof auth.avatarUrl !== "undefined" && String(auth.avatarUrl).length > 0) {
                profilePhotoSource = String(auth.avatarUrl)
                profilePhotoStatus = "Foto de perfil guardada"
            } else {
                // avatarPath es una ruta interna de Supabase Storage, no una URL
                // renderizable por Image. Solo se usa avatarUrl/cache local.
                profilePhotoSource = icon("blank_profile.png")
                profilePhotoStatus = "Avatar predeterminado"
            }
        }
    } catch (e) {
        profilePhotoSource = icon("blank_profile.png")
        profilePhotoStatus = "Foto predeterminada"
    }

    currentUserName = name
    welcomeText = "Te damos la bienvenida, " + inGeCoreFlow.displayPersonName(currentUserName, "Usuario")
}

function dismissLoginKeyboardV503() {
    try {
        Qt.inputMethod.commit()
        if (app.activeFocusItem)
            app.activeFocusItem.focus = false
        if (app.contentItem)
            app.contentItem.forceActiveFocus()
        Qt.inputMethod.hide()
    } catch(e) {}
}

function pageTitle() {
    if (pageIndex === 0) return "Inicio"
    if (pageIndex === 1) return "Calicatas"
    if (pageIndex === 2) return "Mapa GPS"
    if (pageIndex === 3) return "Explorar"
    if (pageIndex === 4) return "Ajustes"
    if (pageIndex === 5) return "Inventario"
    return "Rendiciones"
}


function loginWithGoogle() {
    googleLoginStatus = "Abriendo Google..."
    try {
        if (typeof auth !== "undefined" && auth && auth.signInWithGoogle) {
            auth.signInWithGoogle()
            showToast("Abriendo Google")
            assistantText = "Se abrió Google con Supabase OAuth. Requiere que Google Provider y redirect com.ingema.ingeplus://login-callback estén configurados en Supabase."
            return
        }
    } catch (e) {
        googleLoginStatus = "Google OAuth no disponible"
    }
    showToast("Google OAuth requiere configuración")
    assistantText = "Para activar Google real, configura el proveedor Google en Supabase y el redirect móvil."
}





function uploadLastFichaToDropbox() {
    if (lastExcelPath.length < 1) {
        showToast("Primero exporta Excel")
        return
    }
    var path = dropboxFolder + "/FICHA_" + calCode + ".xlsx"
    try {
        if (typeof dropbox !== "undefined" && dropbox && dropbox.uploadFile) {
            dropbox.uploadFile(lastExcelPath, path)
            dropboxStatus = "Subiendo ficha..."
            showToast("Subiendo a Dropbox")
            return
        }
    } catch (e) {}
    showToast("Dropbox no disponible")
}

function finishInitialSetup() {
    setupComplete = true
    showToast("Configuración inicial lista")
}






function login() {
    if (serverBusy)
        return
    clearPersistedGuestV41()
    if (userEmail.length < 3 || userPassword.length < 1) {
        showToast("Ingresa correo y contraseña")
        return
    }

    serverBusy = true
    serverStatus = "Conectando con servidor..."
    assistantStatus = "Conectando"
    assistantText = "Conectando con servidor INGEMA/Supabase."

    try {
        if (typeof auth !== "undefined" && auth && auth.signInWithPassword) {
            if (auth.setRememberFor30Days)
                auth.setRememberFor30Days(authView.rememberLogin)
            auth.signInWithPassword(userEmail, userPassword)
            return
        }
    } catch (e) {
        serverStatus = "Servidor no disponible"
    }

    serverBusy = false
    showToast("Servidor no disponible")
}

function coordOk() {
    var la = Number(calLat)
    var lo = Number(calLng)
    if (isNaN(la) || isNaN(lo)) return false
    if (la < -90 || la > 90) return false
    if (lo < -180 || lo > 180) return false
    return true
}

function gpsAccuracyLabelM0809(accuracyValue) {
    return isFinite(accuracyValue) && accuracyValue > 0
            ? "±" + Math.round(accuracyValue) + " m"
            : "sin precisión"
}

function acceptNativeGpsPositionM0809(latitudeValue, longitudeValue,
                                         altitudeValue, accuracyValue,
                                         timestampMsValue, providerValue) {
    var latitude = Number(latitudeValue)
    var longitude = Number(longitudeValue)
    var accuracy = Number(accuracyValue)
    var timestampMs = Number(timestampMsValue)

    if (!isFinite(latitude) || !isFinite(longitude)
            || latitude < -90 || latitude > 90
            || longitude < -180 || longitude > 180)
        return false

    gpsRawAccuracyM0809 = accuracy
    if (!isFinite(accuracy) || accuracy <= 0
            || accuracy > gpsMaximumAcceptedAccuracyM0809) {
        gpsRejectedFixCountM0809 += 1
        gpsStatus = gpsHasFix
                ? "Conservando la última ubicación válida"
                : "Esperando una ubicación válida"
        gpsErrorM0809 = ""
        return false
    }

    var ageMs = isFinite(timestampMs) && timestampMs > 0
            ? Math.max(0, Date.now() - timestampMs)
            : 0
    if (ageMs > 5 * 60 * 1000) {
        gpsRejectedFixCountM0809 += 1
        gpsStatus = gpsHasFix
                ? "Última ubicación conservada"
                : "Esperando una ubicación reciente"
        return false
    }

    // El puente Android ya combina fused/GPS/red y elige la mejor lectura.
    // Aquí solo se evita un salto claramente imposible durante pocos segundos.
    if (gpsHasFix && gpsLastAcceptedEpochM0809 > 0
            && isFinite(gpsLat) && isFinite(gpsLng)) {
        var previous = QtPositioning.coordinate(gpsLat, gpsLng)
        var current = QtPositioning.coordinate(latitude, longitude)
        var distance = previous.distanceTo(current)
        var elapsedSeconds = Math.max(1,
                (Date.now() - gpsLastAcceptedEpochM0809) / 1000.0)
        var allowedDistance = Math.max(600.0,
                                       accuracy * 3.0,
                                       elapsedSeconds * 80.0)
        if (isFinite(distance) && distance > allowedDistance) {
            gpsRejectedFixCountM0809 += 1
            gpsStatus = "Lectura inestable descartada; conservando ubicación"
            return false
        }
    }

    console.log("[InGe+ GPS] coordenadas aceptadas:", latitude, longitude,
                "±" + accuracy + "m", providerValue || "Android")
    gpsHasFix = true
    gpsLat = latitude
    gpsLng = longitude
    gpsAlt = isFinite(Number(altitudeValue)) ? Number(altitudeValue) : NaN
    gpsAccuracyM0809 = accuracy
    gpsProviderM0809 = String(providerValue || "Android")
    gpsLastAcceptedEpochM0809 = Date.now()
    gpsLastUpdateM0809 = isFinite(timestampMs) && timestampMs > 0
            ? Qt.formatTime(new Date(timestampMs), "hh:mm:ss")
            : Qt.formatTime(new Date(), "hh:mm:ss")
    gpsStatus = accuracy <= gpsExcellentAccuracyM0809
            ? "Ubicación precisa · " + gpsAccuracyLabelM0809(accuracy)
            : (accuracy <= 100
               ? "Ubicación estable · " + gpsAccuracyLabelM0809(accuracy)
               : "Ubicación aproximada · " + gpsAccuracyLabelM0809(accuracy))
    gpsErrorM0809 = ""
    gpsFixFreshTimerM0809.restart()

    // Mantiene Mapa y Fichas sobre la misma lectura real. Antes el mapa
    // aceptaba la coordenada, pero CalicataFormPage podía seguir esperando
    // porque GpsBus solo se publicaba en acciones puntuales.
    GpsBus.updateFromGeo(gpsLat, gpsLng, gpsAlt, isFinite(gpsAlt),
                         gpsLastUpdateM0809, gpsAccuracyM0809,
                         gpsProviderM0809 || "GPS del dispositivo")

    if (gpsFollow) {
        mapCenterLat = gpsLat
        mapCenterLng = gpsLng
    }
    return true
}

function refreshLocationServiceM0809(showActivationPanel) {
    var enabled = false
    try {
        enabled = Perms.isLocationServiceEnabled()
    } catch (serviceError) {
        console.warn("[InGe+ V38.9] No se pudo consultar ubicación:", serviceError)
    }

    gpsServiceEnabledM0809 = enabled
    if (enabled) {
        gpsActivationPromptShownM0809 = false
        gpsErrorM0809 = ""
        return true
    }

    try { Perms.stopNativeLocationUpdates() } catch (stopError) {}
    gpsProviderGateM0809 = false
    // Igual que Google Maps: conserva la última posición conocida, pero
    // deja claro que ya no está actualizándose.
    gpsStatus = gpsHasFix
            ? "Ubicación desactivada · última posición conservada"
            : "Ubicación del dispositivo desactivada"
    gpsErrorM0809 = ""

    if (showActivationPanel && !gpsActivationPromptShownM0809) {
        gpsActivationPromptShownM0809 = true
        Qt.callLater(function() {
            var opened = false
            try { opened = Perms.openLocationSettings() } catch (openError) {
                console.warn("[InGe+ V38.9] No se pudo abrir ubicación:", openError)
            }
            if (!opened)
                showToast("Activa la ubicación del dispositivo y vuelve a InGe+")
        })
    }
    return false
}

function requestGpsM0809(on, requestFresh) {
    gpsRequestedM0809 = !!on
    gpsErrorM0809 = ""
    gpsFollow = gpsRequestedM0809

    if (!gpsRequestedM0809) {
        gpsRestartTimerM0809.stop()
        gpsFixFreshTimerM0809.stop()
        try { Perms.stopNativeLocationUpdates() } catch (stopError) {}
        gpsProviderGateM0809 = false
        gpsStatus = gpsHasFix ? "Ubicación pausada; última posición conservada"
                              : "Ubicación pausada"
        return
    }

    // PermissionHelper es la única autoridad de permisos. El antiguo
    // LocationPermission QML pedía ubicación APROXIMADA por defecto y
    // dejaba a Android entregando lecturas de ±2000 m.
    if (!Perms.nativePermissionGranted) {
        gpsStatus = "Solicitando ubicación precisa"
        gpsErrorM0809 = ""
        try { Perms.requestLocationPermission() } catch (permissionError) {
            gpsStatus = "Permiso de ubicación requerido"
            gpsErrorM0809 = "No se pudo solicitar la ubicación precisa"
        }
        return
    }

    if (!refreshLocationServiceM0809(true))
        return

    gpsProviderGateM0809 = true
    var started = false
    try { started = Perms.startNativeLocationUpdates() } catch (startError) {
        console.warn("[InGe+ V38.9] No se pudo iniciar ubicación nativa:", startError)
    }

    if (!started) {
        gpsStatus = "No se pudo iniciar la ubicación"
        gpsErrorM0809 = Perms.nativeLocationError || "Android no inició el proveedor"
        return
    }

    gpsStatus = gpsHasFix ? "Ubicación en tiempo real activa"
                          : "Buscando ubicación en tiempo real..."
    // Un refresh puntual solo se solicita por una acción explícita. Las
    // actualizaciones continuas nunca vuelven a iniciar el watcher.
    if (!!requestFresh) {
        try { Perms.refreshNativeLocation() } catch (refreshError) {
            console.warn("[InGe+ GPS] No se pudo solicitar fix fresco:", refreshError)
        }
    }
}

function publishGpsToBusM0809(sourceLabel) {
    if (!gpsHasFix || !isFinite(gpsLat) || !isFinite(gpsLng)) return
    GpsBus.updateFromGeo(gpsLat, gpsLng, gpsAlt, isFinite(gpsAlt),
                         gpsLastUpdateM0809, gpsAccuracyM0809,
                         sourceLabel || "GPS del dispositivo")
}

function useSelectedMapPointM0809(latValue, lonValue, altValue, sourceLabel) {
    var latitude = Number(latValue)
    var longitude = Number(lonValue)
    var altitude = Number(altValue)
    if (!isFinite(latitude) || !isFinite(longitude)
            || latitude < -90 || latitude > 90
            || longitude < -180 || longitude > 180) {
        showToast("Punto de mapa inválido")
        return
    }

    // El punto elegido por el ingeniero es la coordenada de trabajo.
    // También actualiza el estado legacy para evitar que mapa, revisión o
    // exportación lean coordenadas antiguas mientras GpsBus ya tiene otras.
    calLat = latitude.toFixed(7)
    calLng = longitude.toFixed(7)
    if (isFinite(altitude))
        calAlt = altitude.toFixed(1)
    mapCenterLat = latitude
    mapCenterLng = longitude
    mapOffsetX = 0
    mapOffsetY = 0

    GpsBus.updateFromGeo(latitude, longitude, altitude, isFinite(altitude),
                         Qt.formatTime(new Date(), "hh:mm:ss"), NaN,
                         sourceLabel || "Punto del mapa")
    showToast("Punto enviado a Calicatas")
    assistantStatus = "Coordenada lista"
    assistantText = "Punto seleccionado: " + calLat + ", " + calLng
    navigateToPage(1)
}

function useEarthPointInCalicataM0809(latValue, lonValue, altValue,
                                       accuracyValue, timestampValue,
                                       sourceLabel) {
    if (!isFinite(latValue) || !isFinite(lonValue)) return
    var accuracy = Number(accuracyValue)
    GpsBus.updateFromGeo(Number(latValue), Number(lonValue), Number(altValue),
                         isFinite(Number(altValue)),
                         String(timestampValue || Qt.formatTime(new Date(), "hh:mm:ss")),
                         isFinite(accuracy) && accuracy >= 0 ? accuracy : NaN,
                         sourceLabel || "InGe Earth")
    showToast("Punto enviado a Calicatas")
    assistantStatus = "Coordenada lista"
    assistantText = "La coordenada de InGe Earth está lista en la ficha. Si reemplaza datos existentes, se solicitará confirmación."
    navigateToPage(1)
}

function startGpsFollow() {
    requestGpsM0809(true, true)
    if (gpsHasFix) {
        mapCenterLat = gpsLat
        mapCenterLng = gpsLng
        calLat = gpsLat.toFixed(7)
        calLng = gpsLng.toFixed(7)
        if (!isNaN(gpsAlt)) calAlt = gpsAlt.toFixed(1)
        publishGpsToBusM0809("GPS del dispositivo")
        showToast("GPS real actualizado")
    } else {
        gpsStatus = "Buscando GPS real"
        showToast("Buscando GPS real...")
    }
}

function reviewFicha() {
    var missing = ""
    if (calCode.length < 2) missing += "código, "
    if (calProject.length < 3) missing += "proyecto, "
    if (calPk.length < 1) missing += "PK, "
    if (calDepth.length < 1 || isNaN(Number(calDepth))) missing += "profundidad, "
    if (!coordOk()) missing += "coordenadas, "
    if (missing.length > 0) {
        assistantStatus = "Ficha incompleta"
        assistantText = "Revisa antes de exportar: " + missing
        showToast("Ficha incompleta")
        return false
    }
    assistantStatus = "Ficha lista"
    assistantText = "Ficha lista para mapa, fotos y Excel."
    showToast("Ficha lista")
    return true
}

function goMapFromFicha() {
    if (!reviewFicha()) return
    mapCenterLat = Number(calLat)
    mapCenterLng = Number(calLng)
    gpsFollow = false
    navigateToPage(2)
}

function legacyCalicataCutsV80() {
    // Este estado legacy solo debe exportar datos realmente escritos.
    // Los estratos reales viven en CalicataDocument/CalicatasEditorPage.
    var cuts = []
    if (String(calLayer1 || "").trim().length > 0)
        cuts.push({ desde: "", hasta: "", descripcion: calLayer1 })
    if (String(calLayer2 || "").trim().length > 0)
        cuts.push({ desde: "", hasta: "", descripcion: calLayer2 })
    if (String(calLayer3 || "").trim().length > 0)
        cuts.push({ desde: "", hasta: "", descripcion: calLayer3 })
    return cuts
}

function calicataState() {
    return {
        header: {
            tipo: fichaTipo,
            codigo: calCode,
            proyecto: calProject,
            supervisor: calSupervisor,
            pk: calPk,
            fecha: calDate,
            latitud: calLat,
            longitud: calLng,
            altitud: calAlt,
            profundidad: calDepth,
            logo_mtc: String(logoMtcSource),
            logo_proyecto: String(logoProjectSource)
        },
        cortes: legacyCalicataCutsV80(),
        fotos: {
            foto_1: String(photo1Source),
            foto_2: String(photo2Source),
            foto_3: String(photo3Source),
            foto_1_nombre: photo1Name,
            foto_2_nombre: photo2Name,
            foto_3_nombre: photo3Name
        }
    }
}

function exportCalicataExcel() {
    if (!reviewFicha()) return
    try {
        if (typeof excelExporter !== "undefined" && excelExporter && excelExporter.exportStateToXlsx) {
            var out = excelExporter.exportStateToXlsx(calicataState(), "FICHA_" + calCode)
            if (out && out.length > 0) {
                lastExcelPath = String(out)
                showToast("Excel exportado")
                showFlowSuccess("Excel exportado")
                assistantStatus = "Excel generado"
                assistantText = "Excel generado con ficha, coordenadas, logos y referencias de fotos."
                return
            }
            showToast("No se pudo exportar")
            return
        }
        showToast("Exportador Excel no disponible")
    } catch (e) {
        showToast("Error Excel")
    }
}


function tileHost(x, y) {
    var n = Math.abs(x + y) % 4
    if (n === 0) return "a"
    if (n === 1) return "b"
    if (n === 2) return "c"
    return "d"
}

function tileUrl(z, x, y) {
    var host = tileHost(x, y)
    if (mapStyle === 0)
        return "https://" + host + ".basemaps.cartocdn.com/rastertiles/voyager/" + z + "/" + x + "/" + y + ".png"
    return "https://" + host + ".basemaps.cartocdn.com/light_all/" + z + "/" + x + "/" + y + ".png"
}

function lonToTileX(lon, z) {
    return (lon + 180.0) / 360.0 * Math.pow(2, z)
}

function latToTileY(lat, z) {
    var rad = lat * Math.PI / 180.0
    return (1.0 - Math.log(Math.tan(rad) + 1.0 / Math.cos(rad)) / Math.PI) / 2.0 * Math.pow(2, z)
}

function tileXToLon(x, z) {
    return x / Math.pow(2, z) * 360.0 - 180.0
}

function tileYToLat(y, z) {
    var n = Math.PI - 2.0 * Math.PI * y / Math.pow(2, z)
    return 180.0 / Math.PI * Math.atan(0.5 * (Math.exp(n) - Math.exp(-n)))
}

function currentMapLng() {
    return tileXToLon(lonToTileX(mapCenterLng, mapZoom) - mapOffsetX / 256.0, mapZoom)
}

function currentMapLat() {
    return tileYToLat(latToTileY(mapCenterLat, mapZoom) - mapOffsetY / 256.0, mapZoom)
}

function panMap(dx, dy) {
    mapOffsetX += dx
    mapOffsetY += dy

    var cx = lonToTileX(mapCenterLng, mapZoom)
    var cy = latToTileY(mapCenterLat, mapZoom)

    while (mapOffsetX > 256) { cx -= 1; mapOffsetX -= 256 }
    while (mapOffsetX < -256) { cx += 1; mapOffsetX += 256 }
    while (mapOffsetY > 256) { cy -= 1; mapOffsetY -= 256 }
    while (mapOffsetY < -256) { cy += 1; mapOffsetY += 256 }

    mapCenterLng = tileXToLon(cx, mapZoom)
    mapCenterLat = tileYToLat(cy, mapZoom)
}

function zoomMap(delta) {
    var z = mapZoom + delta
    if (z < 3) z = 3
    if (z > 20) z = 20
    if (z !== mapZoom) {
        mapZoom = z
        mapOffsetX = 0
        mapOffsetY = 0
        mapTilesReady = 0
        mapTilesError = 0
    }
}

function useMapPointForFicha() {
    var la = currentMapLat()
    var lo = currentMapLng()
    calLat = la.toFixed(7)
    calLng = lo.toFixed(7)
    mapCenterLat = la
    mapCenterLng = lo
    mapOffsetX = 0
    mapOffsetY = 0
    showToast("Coordenadas enviadas a ficha")
    assistantText = "Punto del mapa enviado a la ficha: " + calLat + ", " + calLng
}


Timer { id: toastTimer; interval: 2600; repeat: false; onTriggered: toastText = "" }

Timer {
    id: gpsRestartTimerM0809
    interval: 500
    repeat: false
    onTriggered: {
        if (!gpsRequestedM0809 || !gpsPermissionGrantedM0809
                || !gpsServiceEnabledM0809)
            return
        gpsProviderGateM0809 = true
        var started = false
        try { started = Perms.startNativeLocationUpdates() } catch (error) {}
        gpsStatus = started ? "Buscando ubicación en tiempo real..."
                            : "No se pudo iniciar la ubicación"
    }
}

Timer {
    id: gpsFixFreshTimerM0809
    interval: 120000
    repeat: false
    onTriggered: {
        if (!gpsRequestedM0809)
            return
        gpsStatus = gpsHasFix
                ? "Última ubicación conservada; esperando actualización"
                : "Buscando ubicación en tiempo real..."
        gpsErrorM0809 = ""
    }
}

Timer {
    id: gpsResumeTimerM0809
    interval: 500
    repeat: false
    onTriggered: {
        if (!gpsRequestedM0809 || !gpsPermissionGrantedM0809
                || (pageIndex !== 1 && pageIndex !== 2))
            return
        if (refreshLocationServiceM0809(false))
            requestGpsM0809(true)
    }
}

Connections {
    target: Qt.application

    function onStateChanged() {
        appActiveV41 = Qt.application.state === Qt.ApplicationActive

        if (!appActiveV41) {
            mapGestureBusy = false

            return
        }

        if (!gpsRequestedM0809 || !gpsPermissionGrantedM0809
                || (pageIndex !== 1 && pageIndex !== 2))
            return
        gpsResumeTimerM0809.restart()
    }
}

// V38.13: no se crea LocationPermission en QML. PermissionHelper solicita
// QLocationPermission::Precise y expone su estado mediante propiedades.


// V38.9: una sola fuente de verdad para Android. LocationManager nativo
// mantiene fused/GPS/red activos; QML ya no crea ni reinicia PositionSource.
Connections {
    target: Perms

    function onNativePermissionChanged() {
        console.log("[InGe+ GPS] permiso:", Perms.nativePermissionStatus,
                    "preciso=", Perms.nativePermissionGranted)
        if (Perms.nativePermissionGranted) {
            gpsErrorM0809 = ""
            if (gpsRequestedM0809 && refreshLocationServiceM0809(false))
                requestGpsM0809(true)
        } else if (Perms.nativePermissionStatus === "denied") {
            gpsStatus = "Permiso de ubicación precisa requerido"
            gpsErrorM0809 = "Activa 'Usar ubicación precisa' en Android"
        } else if (Perms.nativePermissionStatus === "requesting") {
            gpsStatus = "Solicitando ubicación precisa..."
        }
    }

    function onNativeTrackingChanged() {
        gpsProviderGateM0809 = Perms.nativeTracking
        if (gpsRequestedM0809 && !Perms.nativeTracking
                && Perms.nativeLocationError && Perms.nativeLocationError.length)
            gpsErrorM0809 = Perms.nativeLocationError
    }

    function onNativeLocationStatusChanged() {
        var status = String(Perms.nativeLocationStatus || "")
        console.log("[InGe+ GPS] estado nativo:", status,
                    Perms.nativeLocationError || "")
        if (status === "service_disabled") {
            gpsServiceEnabledM0809 = false
            gpsStatus = gpsHasFix
                    ? "Ubicación desactivada · última posición conservada"
                    : "Ubicación del dispositivo desactivada"
        } else if (status === "permission_denied") {
            gpsStatus = "Permiso de ubicación precisa requerido"
        } else if (status === "requesting_permission") {
            gpsStatus = "Solicitando ubicación precisa..."
        } else if (status === "tracking_precise") {
            gpsStatus = "Ubicación precisa en tiempo real"
        } else if (status === "tracking_approximate") {
            gpsStatus = "Ubicación aproximada · esperando mejor precisión"
        } else if (status === "tracking") {
            gpsStatus = gpsHasFix ? "Ubicación en tiempo real activa"
                                  : "Buscando ubicación en tiempo real..."
        } else if (status === "searching" || status === "starting") {
            if (!gpsHasFix)
                gpsStatus = "Buscando ubicación en tiempo real..."
        }
        if (Perms.nativeLocationError && Perms.nativeLocationError.length)
            gpsErrorM0809 = Perms.nativeLocationError
    }

    function onNativeLocationChanged() {
        if (!Perms.nativeHasFix)
            return
        acceptNativeGpsPositionM0809(Perms.nativeLatitude,
                                     Perms.nativeLongitude,
                                     Perms.nativeAltitude,
                                     Perms.nativeAccuracy,
                                     Perms.nativeTimestampMs,
                                     Perms.nativeProvider)
    }
}

FileDialog {
    id: logoPicker
    title: "Seleccionar logo"
    nameFilters: ["Imágenes (*.png *.jpg *.jpeg *.webp)", "Todos los archivos (*)"]
    onAccepted: {
        if (logoTarget === "mtc") {
            logoMtcSource = selectedFile
            showToast("Logo MTC adjuntado")
        } else {
            logoProjectSource = selectedFile
            showToast("Logo proyecto adjuntado")
        }
    }
}

FileDialog {
    id: photoPicker
    title: "Adjuntar foto de ficha"
    nameFilters: ["Imágenes (*.png *.jpg *.jpeg *.webp)", "Todos los archivos (*)"]
    onAccepted: {
        var src = selectedFile
        var name = String(src).split("/").pop()
        if (photoTarget === 1) {
            photo1Source = src
            photo1Name = name
        } else if (photoTarget === 2) {
            photo2Source = src
            photo2Name = name
        } else {
            photo3Source = src
            photo3Name = name
        }
        showToast("Foto adjuntada")
    }
}


FileDialog {
    id: profilePicker
    title: "Cambiar foto de perfil"
    nameFilters: ["Imágenes (*.png *.jpg *.jpeg *.webp)", "Todos los archivos (*)"]
    onAccepted: {
        // Vista previa inmediata. AuthSession recorta, corrige orientación y
        // guarda una copia interna por cuenta antes de actualizar la UI final.
        profilePhotoSource = selectedFile
        profilePhotoStatus = "Procesando foto..."
        showLocalToastV18("Procesando foto de perfil...")
        try {
            if (typeof auth !== "undefined" && auth && auth.logged && auth.updateUserAvatar) {
                auth.updateUserAvatar(selectedFile)
            } else {
                profilePhotoStatus = "Foto local temporal"
                showLocalToastV18("Inicia sesión para guardar la foto")
            }
        } catch (e) {
            profilePhotoStatus = "No se pudo guardar la foto"
            showLocalToastV18("No se pudo guardar la foto")
        }
    }
}

Dialog {
    id: mtcLogoDialog
    modal: true
    title: "Logo MTC"
    standardButtons: Dialog.Close
    enter: Transition {
        ParallelAnimation {
            NumberAnimation { property: "opacity"; from: 0.0; to: 1.0; duration: inGeCoreFlow.dialogDuration; easing.type: inGeCoreFlow.easeOut }
            NumberAnimation { property: "scale"; from: inGeCoreFlow.sheetStartScale; to: 1.0; duration: inGeCoreFlow.dialogDuration; easing.type: inGeCoreFlow.easeOvershoot }
        }
    }
    exit: Transition {
        ParallelAnimation {
            NumberAnimation { property: "opacity"; from: 1.0; to: 0.0; duration: inGeCoreFlow.normalDuration; easing.type: inGeCoreFlow.easeIn }
            NumberAnimation { property: "scale"; from: 1.0; to: 0.985; duration: inGeCoreFlow.normalDuration; easing.type: inGeCoreFlow.easeIn }
        }
    }
    width: Math.min(app.width - 36, 360)

    Column {
        width: parent.width
        spacing: 10
        padding: 8

        Text { width: parent.width; text: "Selecciona el logo MTC desde recursos internos o adjunta otro archivo."; color: textColor(); wrapMode: Text.WordWrap }
        SecondaryButton { width: parent.width; label: "Usar logo MTC interno"; onClicked: { logoMtcSource = icon("Logo_MTC.jpeg"); mtcLogoDialog.close(); showToast("Logo MTC interno") } }
        GhostButton { width: parent.width; label: "Adjuntar otro logo MTC"; onClicked: { logoTarget = "mtc"; mtcLogoDialog.close(); logoPicker.open() } }
    }
}

Dialog {
    id: projectLogoDialog
    modal: true
    title: "Logo de proyecto"
    standardButtons: Dialog.Close
    enter: Transition {
        ParallelAnimation {
            NumberAnimation { property: "opacity"; from: 0.0; to: 1.0; duration: inGeCoreFlow.dialogDuration; easing.type: inGeCoreFlow.easeOut }
            NumberAnimation { property: "scale"; from: inGeCoreFlow.sheetStartScale; to: 1.0; duration: inGeCoreFlow.dialogDuration; easing.type: inGeCoreFlow.easeOvershoot }
        }
    }
    exit: Transition {
        ParallelAnimation {
            NumberAnimation { property: "opacity"; from: 1.0; to: 0.0; duration: inGeCoreFlow.normalDuration; easing.type: inGeCoreFlow.easeIn }
            NumberAnimation { property: "scale"; from: 1.0; to: 0.985; duration: inGeCoreFlow.normalDuration; easing.type: inGeCoreFlow.easeIn }
        }
    }
    width: Math.min(app.width - 36, 360)

    Column {
        width: parent.width
        spacing: 10
        padding: 8

        Text { width: parent.width; text: "Usa el recurso interno o adjunta el logo del proyecto."; color: textColor(); wrapMode: Text.WordWrap }
        SecondaryButton { width: parent.width; label: "Usar logo proyecto interno"; onClicked: { logoProjectSource = icon("app_logo_company.png"); projectLogoDialog.close(); showToast("Logo proyecto interno") } }
        PrimaryButton { width: parent.width; label: "Adjuntar logo del proyecto"; onClicked: { logoTarget = "project"; projectLogoDialog.close(); logoPicker.open() } }
    }
}

Connections {
    target: (typeof auth !== "undefined" ? auth : null)
    ignoreUnknownSignals: true

    function onLoginOk() {
        var opV800 = authPendingOpV800
        var flowV800 = authFlowStateV800
        if (opV800 === "restore-cancelled") {
            // La restauración agotó su tiempo: su éxito tardío no es válido.
            logStaleAuthCallbackV800("loginOk", authPendingGenV800)
            clearAuthOperationV800()
            return
        }
        if (opV800 === "" && flowV800 === "HOME") {
            // Renovación de la misma sesión (refresh): identidad al día, sin
            // transición ni reapertura de Auth.
            updateWelcomeFromAuth()
            refreshSavedAccountsV20()
            syncFlutterAuthStateV70(false)
            return
        }
        if (opV800 === "" && flowV800 !== "LOGIN" && flowV800 !== "AUTHENTICATING"
                && flowV800 !== "ADDING_ACCOUNT" && flowV800 !== "BOOTSTRAP"
                && flowV800 !== "AUTOLOGIN_WELCOME") {
            // Ninguna operación vigente espera sesión (p.ej. ya se cerró).
            logStaleAuthCallbackV800("loginOk", -1)
            return
        }
        if (opV800 === "restore")
            authRestoreTimeoutV800.stop()
        // switch/biometric se cierran en onAccountSwitchOk (emitido después).
        if (opV800 !== "switch" && opV800 !== "biometric")
            clearAuthOperationV800()
        dismissLoginKeyboardV503()
        var restoringV600 = opV800 === "restore" || flowV800 === "AUTOLOGIN_WELCOME"
        if (restoringV600)
            beginSessionWelcomeV600()
        else
            beginSessionEntryV501()
        clearPersistedGuestV41()
        forceFirstExperiencePreview = false
        forceFirstExperienceShowcase = false
        authBootstrapDoneV20 = true
        serverBusy = false
        flutterAuthErrorV70 = ""
        accountSwitchBusyV20 = false
        var offlineDev = false
        try { offlineDev = auth && auth.devOffline === true } catch(e0) {}
        serverConnected = !offlineDev
        loggedIn = true
        guestMode = false
        serverStatus = offlineDev ? "DEV OFFLINE" : "OK"
        previousAccountIdV20 = ""
        console.info("AUTH_IDENTITY_COMMIT uid8=" + uid8V800(activeAccountIdV800())
                     + " gen=" + authGenerationV800 + " op=" + (opV800.length ? opV800 : "external"))
        try { userEmail = accountTrimV18(auth.email, userEmail) } catch(e) {}
        updateWelcomeFromAuth()
        refreshSavedAccountsV20()
        assistantStatus = offlineDev ? "DEV offline" : "Sesión activa"
        assistantText = offlineDev
                ? "Modo DEV local activo. No se usará el backend."
                : welcomeText + ". Ya puedes registrar fichas, mapa, fotos y Excel."
        commitSessionIdentityV501()
        syncFlutterAuthStateV70(false)
        console.log("FIRST_LOGIN_HOME_READY")
        console.log("ONBOARDING_OVERLAY_VISIBLE=0")
        showToast(welcomeText)
    }

    function onLoginFail(message) {
        var opV800 = authPendingOpV800
        var flowV800 = authFlowStateV800
        // Cambio/biometría y restauración resuelven en accountSwitchFail /
        // autoLoginFinished (emitidos a continuación por el mismo fallo).
        if (opV800 === "switch" || opV800 === "biometric"
                || opV800 === "restore" || opV800 === "restore-cancelled")
            return
        if (opV800 === "" && flowV800 !== "LOGIN" && flowV800 !== "AUTHENTICATING"
                && flowV800 !== "ADDING_ACCOUNT") {
            // Fallo de verificación en segundo plano (p.ej. perfil tras una
            // restauración rápida): solo si C++ ya no tiene sesión, la
            // identidad visible deja de existir y se invalida la transición.
            var stillLogged = true
            try { stillLogged = auth && auth.logged === true } catch(eL) {}
            if (!stillLogged && (loggedIn || flowV800 === "HOME")) {
                nextAuthGenerationV800("session-invalidated")
                hideFlutterHomeForAuthV800()
                enterLoginStateV800("session-invalidated",
                                    message && String(message).length
                                    ? String(message) : "Tu sesión ya no es válida.")
            } else {
                logStaleAuthCallbackV800("loginFail", -1)
            }
            return
        }
        clearAuthOperationV800()
        if (flowV800 === "AUTHENTICATING")
            setAuthFlowStateV800("LOGIN", "password-failed")
        authBootstrapDoneV20 = true
        serverBusy = false
        accountSwitchBusyV20 = false
        serverConnected = false
        serverStatus = "Error de login"
        assistantStatus = "Login falló"
        assistantText = "No se pudo iniciar sesión: " + message
        flutterAuthErrorV70 = message && String(message).length
                              ? String(message) : "No se pudo iniciar sesión."
        syncFlutterAuthStateV70(flutterAuthLastMethodV70 === "biometric")
        showToast(message && String(message).length ? String(message) : "Login falló")
    }

    function onAutoLoginFinished(restored) {
        var opV800 = authPendingOpV800
        authBootstrapDoneV20 = true
        if (opV800 === "restore-cancelled") {
            clearAuthOperationV800()
            logStaleAuthCallbackV800("autoLoginFinished", -1)
            return
        }
        if (restored) {
            // loginOk ya llegó antes y gobierna la transición.
            refreshSavedAccountsV20()
            return
        }
        if (opV800 !== "restore" && authFlowStateV800 !== "AUTOLOGIN_WELCOME") {
            logStaleAuthCallbackV800("autoLoginFinished", -1)
            return
        }
        // Sesión expirada, revocada o no restaurable: bienvenida → LOGIN.
        console.info("AUTOLOGIN_RESULT restored=NO gen=" + authGenerationV800)
        enterLoginStateV800("restore-failed", "")
        guestMode = false
        serverConnected = false
        refreshSavedAccountsV20()
        syncFlutterAuthStateV70(false)
    }

    function onAccountSwitchStarted(accountId) {
        if (authPendingOpV800 !== "switch" && authPendingOpV800 !== "biometric") {
            logStaleAuthCallbackV800("accountSwitchStarted", -1)
            return
        }
        accountSwitchBusyV20 = true
        serverBusy = true
    }

    function onAccountSwitchOk(accountId) {
        var opV800 = authPendingOpV800
        if (opV800 !== "switch" && opV800 !== "biometric") {
            logStaleAuthCallbackV800("accountSwitchOk", -1)
            return
        }
        var switchGen = authPendingGenV800
        clearAuthOperationV800()
        clearPersistedGuestV41()
        accountSwitchBusyV20 = false
        serverBusy = false
        loggedIn = true
        guestMode = false
        previousAccountIdV20 = ""
        flutterAuthErrorV70 = ""
        var rolledBack = accountSwitchRollbackV800
        accountSwitchRollbackV800 = false
        updateWelcomeFromAuth()
        refreshSavedAccountsV20()
        // El selector se retira sin cambiar el estado: la transición de
        // entrada (ya iniciada por loginOk) termina en HOME.
        accountSwitchSheetOpenV18 = false
        manageAccountsModeV18 = false
        profileOverlayOpenV18 = false
        console.info("ACCOUNT_SWITCH_COMMIT uid8=" + uid8V800(accountId)
                     + " gen=" + switchGen)
        syncFlutterAuthStateV70(false)
        if (!rolledBack)
            showLocalToastV18("Cuenta cambiada")
    }

    function onAccountSwitchFail(accountId, message) {
        var opV800 = authPendingOpV800
        if (opV800 !== "switch" && opV800 !== "biometric") {
            logStaleAuthCallbackV800("accountSwitchFail", -1)
            return
        }
        var text = message && String(message).length
                ? String(message)
                : "La sesión guardada ya no es válida. Ingresa tu contraseña."
        console.info("ACCOUNT_SWITCH_FAIL toUid8=" + uid8V800(accountId)
                     + " gen=" + authPendingGenV800 + " source=" + accountSwitchSourceV800)
        clearAuthOperationV800()
        accountSwitchBusyV20 = false
        serverBusy = false
        refreshSavedAccountsV20()

        // Desde Home: se intenta volver a la cuenta anterior (una sola vez)
        // para no dejar la app sin identidad ni mezclar A con B.
        var fromId = accountSwitchFromIdV800
        var canRollback = false
        try {
            canRollback = accountSwitchSourceV800 === "home" && !accountSwitchRollbackV800
                    && fromId.length > 0 && fromId !== String(accountId)
                    && auth && auth.hasSavedAccount && auth.hasSavedAccount(fromId)
        } catch(eR) { canRollback = false }
        if (canRollback) {
            accountSwitchRollbackV800 = true
            showLocalToastV18(text)
            console.info("ACCOUNT_SWITCH_ROLLBACK toUid8=" + uid8V800(fromId))
            startAccountSwitchV800(fromId, "home", "")
            return
        }
        accountSwitchRollbackV800 = false

        if (accountSwitchSourceV800 === "sessionClosed"
                && savedAccountsModelV20.length > 0) {
            // Sigue sin sesión: se vuelve al selector de Auth.
            clearVisibleSessionV18()
            accountPickerSourceV800 = "sessionClosed"
            setAuthFlowStateV800("ACCOUNT_PICKER", "switch-failed")
            accountSwitchSheetOpenV18 = true
            showLocalToastV18(text)
            return
        }

        hideFlutterHomeForAuthV800()
        enterLoginStateV800("switch-failed", text)
        syncFlutterAuthStateV70(flutterAuthLastMethodV70 === "biometric"
                                && accountSwitchSourceV800 === "auth")
        showLocalToastV18(text)
    }

    function onSavedAccountsChanged() {
        refreshSavedAccountsV20()
        syncFlutterAuthStateV70(false)
    }

    function onUserInfoChanged() {
        try {
            if (auth && auth.logged) {
                userEmail = accountTrimV18(auth.email, userEmail)
                updateWelcomeFromAuth()
            }
        } catch(e) {}
        refreshSavedAccountsV20()
    }

    function onBackendProfileChanged() {
        try {
            if (auth && auth.logged)
                updateWelcomeFromAuth()
        } catch(e) {}
    }

    function onProfileUpdatedOk() {
        updateWelcomeFromAuth()
        refreshSavedAccountsV20()
        profilePhotoStatus = "Foto de perfil actualizada"
        showLocalToastV18("Foto de perfil actualizada")
    }

    function onProfileUpdatedFail(message) {
        updateWelcomeFromAuth()
        profilePhotoStatus = "No se pudo actualizar la foto"
        showLocalToastV18(message && String(message).length ? String(message) : "No se pudo actualizar la foto")
    }

    function onProfileAvatarSynced() {
        profilePhotoStatus = "Foto sincronizada"
    }

    function onProfileAvatarSyncWarning(message) {
        profilePhotoStatus = "Guardada en este dispositivo"
        showLocalToastV18(message && String(message).length ? String(message) : "Foto guardada localmente")
    }

    function onOauthStarted(provider, url) {
        googleLoginStatus = "OAuth abierto"
        assistantText = "OAuth " + provider + " abierto. Si no vuelve automáticamente, revisa redirect deep link en Supabase."
    }

    function onLoggedOut() {
        if (authFlowStateV800 === "HOME"
                || (authFlowStateV800 === "ACCOUNT_PICKER"
                    && accountPickerSourceV800 === "home")) {
            // Cierre no iniciado por el usuario (C++ invalidó la sesión):
            // se sale de Home de forma explícita, sin estados superpuestos.
            nextAuthGenerationV800("logged-out-external")
            hideFlutterHomeForAuthV800()
            enterLoginStateV800("logged-out-external", "")
        }
        loggedIn = false
        guestMode = false
        authBootstrapDoneV20 = true
        setPageImmediate(0)
        serverConnected = false
        currentUserName = "Invitado"
        userEmail = ""
        profilePhotoSource = icon("blank_profile.png")
        welcomeText = "Te damos la bienvenida a InGe+"
        refreshSavedAccountsV20()
        flutterAuthErrorV70 = ""
        syncFlutterAuthStateV70(false)
        if (sessionEntryTransitionActiveV501
                && sessionEntryClosingV501)
            commitSessionIdentityV501()
    }
}

Connections {
    target: (typeof dropbox !== "undefined" ? dropbox : null)
    ignoreUnknownSignals: true

    function onConnectedOk() {
        dropboxConnected = true
        dropboxStatus = "Dropbox listo"
        showToast("Dropbox conectado")
    }

    function onUploadOk(path) {
        dropboxStatus = "Ficha subida"
        showToast("Subido a Dropbox")
        assistantText = "Ficha subida a Dropbox: " + path
    }

    function onUploadFail(message) {
        dropboxConnected = false
        dropboxStatus = "Dropbox error"
        assistantText = "Dropbox: " + message
        showToast("Error Dropbox")
    }

    function onOauthUrlOpened(url) {
        dropboxStatus = "Autoriza Dropbox y copia el token"
        assistantText = "Se abrió Dropbox OAuth. Copia el access_token y pégalo en Ajustes > Dropbox."
    }
}


Component.onCompleted: {
    // Preferencias reales elegidas en la Primera Experiencia.
    // Si no están disponibles, usa la última configuración persistida.
    try {
        languageCode = firstExperience.languageCode
        flowMotionLevel = firstExperience.motionLevel
        // V90: automatic levels come from the Binding on flowPerformanceLevel;
        // only a level picked in Ajustes is restored here.
        resolvePerformanceSourceV90()
        if (!performanceAutomaticV90)
            flowPerformanceLevel = Math.max(0, Math.min(2, appSettingsV41.lastPerformanceLevel))
        reduceMotion = firstExperience.motionLevel === 0
        fontScale = appSettingsV41.lastFontScale > 0
                    ? appSettingsV41.lastFontScale : 1.0
        setVisualThemeMode(0, false)
    } catch (experienceError) {
        reduceMotion = appSettingsV41.lastReduceMotion
        resolvePerformanceSourceV90()
        if (!performanceAutomaticV90)
            flowPerformanceLevel = Math.max(0, Math.min(2, appSettingsV41.lastPerformanceLevel))
        fontScale = appSettingsV41.lastFontScale > 0
                    ? appSettingsV41.lastFontScale : 1.0
        setVisualThemeMode(0, false)
    }
    loggedIn = false
    refreshSavedAccountsV20()
    clearPersistedGuestV41()
    guestMode = false
    // Flutter informa primero si el vault biométrico está habilitado. Ese
    // estado decide entre verificación biométrica o restauración normal.
    authRestoreDecisionTakenV70 = false
    // AUTH_FLOW_V800: con una sesión recordada restaurable, el arranque
    // muestra "Bienvenido a InGe+" (nunca el formulario) hasta resolverla.
    nextAuthGenerationV800("boot")
    var restorableV800 = false
    try {
        restorableV800 = Qt.platform.os === "android"
                && typeof auth !== "undefined" && auth
                && auth.hasRestorableSession && auth.hasRestorableSession() === true
    } catch(eRestore) { restorableV800 = false }
    if (restorableV800) {
        setAuthFlowStateV800("AUTOLOGIN_WELCOME", "boot-restorable-session")
        // Seguridad también antes de que Flutter informe el estado biométrico.
        authRestoreTimeoutV800.generation = authGenerationV800
        authRestoreTimeoutV800.restart()
    } else {
        setAuthFlowStateV800("LOGIN", "boot-no-restorable-session")
    }
    authBootstrapDoneV20 = true
    console.log("AUTH_QML_RESTORE_PENDING")
}

Rectangle { anchors.fill: parent; color: bgColor() }


// La Primera Experiencia se carga de forma aislada. Si una escena futura
// contiene un error, Main.qml y el resto de InGe+ continúan abriendo.
Loader {
    id: firstExperienceLoader
    anchors.fill: parent
    z: 200000

    property bool failed: false
    readonly property bool shouldOpen: false // Dormant until final onboarding phase.

    active: shouldOpen && !failed
    visible: active
    enabled: active
    asynchronous: false
    source: active ? "onboarding/FirstExperience.qml" : ""

    onLoaded: {
        if (!item)
            return
        console.log("[InGe+ V24] Primera Experiencia Premium cargada correctamente.")
        item.flow = inGeCoreFlow
        item.experience = (typeof firstExperience !== "undefined" ? firstExperience : null)
        item.narrator = (typeof narrator !== "undefined" ? narrator : null)
        item.experienceAudio = (typeof experienceAudio !== "undefined" ? experienceAudio : null)
        item.previewMode = forceFirstExperiencePreview
        item.showcaseMode = forceFirstExperienceShowcase
    }

    onStatusChanged: {
        if (status === Loader.Error) {
            console.warn("[InGe+ SAFE START] La introducción no cargó; se continúa con la aplicación principal.")
            failed = true
            forceFirstExperiencePreview = false
            forceFirstExperienceShowcase = false
        }
    }
}

Connections {
    target: firstExperienceLoader.item
    enabled: firstExperienceLoader.status === Loader.Ready && firstExperienceLoader.item !== null

    function onFinished(selectedLanguage, selectedTheme, selectedMotion, selectedPerformance) {
        languageCode = selectedLanguage
        reduceMotion = selectedMotion === 0
        flowMotionLevel = selectedMotion
        // The onboarding has no performance choice (it always reports 2):
        // the level stays automatic or the one picked in Ajustes.
        setVisualThemeMode(0, false)
        persistUiStateV41()
        forceFirstExperiencePreview = false
        forceFirstExperienceShowcase = false
    }

    function onDismissed() {
        forceFirstExperiencePreview = false
        forceFirstExperienceShowcase = false
    }
}

Item {
    id: setupWizard
    anchors.fill: parent
    visible: false // Reemplazado por FirstExperience de InGeCoreFlow.
    z: 900

    Rectangle { anchors.fill: parent; color: inGeCoreFlow.theme.background }

    Flickable {
        anchors.fill: parent
        clip: true
        contentWidth: width
        contentHeight: setupCol.height + 80

        Column {
            id: setupCol
            width: Math.min(app.width - 38, 430)
            x: (app.width - width) / 2
            y: 28
            spacing: 14

            Image {
                width: 150
                height: 58
                source: icon("ingema_logo.png")
                fillMode: Image.PreserveAspectFit
                anchors.horizontalCenter: parent.horizontalCenter
            }

            Text {
                width: parent.width
                text: "Configurar InGe+"
                color: inGeCoreFlow.theme.accent
                font.pixelSize: fs(30)
                font.bold: true
                horizontalAlignment: Text.AlignHCenter
            }

            Text {
                width: parent.width
                text: setupStep === 0 ? "Elige el idioma de trabajo" :
                      setupStep === 1 ? "Ajusta la lectura" :
                      setupStep === 2 ? "Personaliza tu avatar" :
                      "Conecta tu cuenta"
                color: mutedColor()
                font.pixelSize: fs(14)
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.WordWrap
            }

            Rectangle {
                width: parent.width
                height: 420
                radius: 28
                color: inGeCoreFlow.theme.surfaceElevated
                border.color: borderColor()

                StackLayout {
                    anchors.fill: parent
                    anchors.margins: 18
                    currentIndex: setupStep

                    Column {
                        spacing: 12
                        Text { text: "Idioma"; color: textColor(); font.pixelSize: fs(22); font.bold: true }
                        SecondaryButton { width: parent.width; label: "Español"; onClicked: { languageCode = "es"; showToast("Idioma: Español") } }
                        SecondaryButton { width: parent.width; label: "English"; onClicked: { languageCode = "en"; showToast("Language: English") } }
                        Text { width: parent.width; text: "Luego podrás cambiarlo desde Configuración."; color: mutedColor(); font.pixelSize: fs(13); wrapMode: Text.WordWrap }
                    }

                    Column {
                        spacing: 12
                        Text { text: "Lectura"; color: textColor(); font.pixelSize: fs(22); font.bold: true }
                        Text { width: parent.width; text: "InGe+ usa la apariencia normal clara."; color: mutedColor(); font.pixelSize: fs(13); wrapMode: Text.WordWrap }
                        Row {
                            spacing: 8
                            SecondaryButton { width: 76; label: "A-"; onClicked: fontScale = Math.max(0.85, fontScale - 0.05) }
                            Text { width: 100; text: Math.round(fontScale * 100) + "%"; color: textColor(); font.pixelSize: fs(14); horizontalAlignment: Text.AlignHCenter; anchors.verticalCenter: parent.verticalCenter }
                            SecondaryButton { width: 76; label: "A+"; onClicked: fontScale = Math.min(1.30, fontScale + 0.05) }
                        }
                    }

                    Column {
                        spacing: 12
                        Text { text: "Avatar"; color: textColor(); font.pixelSize: fs(22); font.bold: true }
                        Components.CircularAvatar {
                            width: 112
                            height: 112
                            anchors.horizontalCenter: parent.horizontalCenter
                            source: profilePhotoSource
                            hasImage: accountHasPhotoV18()
                            borderColor: inGeCoreFlow.theme.accent
                            borderWidth: 2
                            fallbackText: "IG"
                            fallbackTextColor: inGeCoreFlow.theme.accent
                            backgroundColor: inGeCoreFlow.theme.infoContainer
                        }
                        PrimaryButton { width: parent.width; label: "Elegir foto"; onClicked: profilePicker.open() }
                        GhostButton { width: parent.width; label: "Usar avatar en blanco"; onClicked: { profilePhotoSource = icon("blank_profile.png"); profilePhotoStatus = "Avatar predeterminado" } }
                    }

                    Column {
                        spacing: 10
                        Text { text: "Cuenta"; color: textColor(); font.pixelSize: fs(22); font.bold: true }
                        PrimaryButton { width: parent.width; label: "Iniciar sesión con correo"; onClicked: finishInitialSetup() }
                        SecondaryButton { width: parent.width; label: "Continuar con Google"; onClicked: { finishInitialSetup(); loginWithGoogle() } }
                        Text { width: parent.width; text: "Google y Dropbox requieren que las credenciales OAuth estén configuradas por INGEMA."; color: mutedColor(); font.pixelSize: fs(12); wrapMode: Text.WordWrap }
                    }
                }
            }

            Row {
                width: parent.width
                spacing: 8
                SecondaryButton {
                    width: (parent.width - 8) / 2
                    label: setupStep > 0 ? "Atrás" : "Saltar"
                    onClicked: {
                        if (setupStep > 0) setupStep -= 1
                        else finishInitialSetup()
                    }
                }
                PrimaryButton {
                    width: (parent.width - 8) / 2
                    label: setupStep < 3 ? "Siguiente" : "Terminar"
                    onClicked: {
                        if (setupStep < 3) setupStep += 1
                        else finishInitialSetup()
                    }
                }
            }
        }
    }
}

Item {
    id: authBootstrapViewV20
    anchors.fill: parent
    z: 950
    // También durante la bienvenida de auto-inicio: hasta que la FlutterView
    // (con la misma bienvenida) pinta encima, QML nunca deja ver el fondo
    // del formulario de login.
    readonly property bool presented: setupComplete
                                      && (!authBootstrapDoneV20 || app.authWelcomePhaseV800)
    visible: opacity > 0.01
    opacity: presented ? 1.0 : 0.0
    Behavior on opacity {
        OpacityAnimator { duration: inGeCoreFlow.motionAllowed ? 180 : 0; easing.type: Easing.OutCubic }
    }

    WelcomeSplashV600 {
        anchors.fill: parent
        active: authBootstrapViewV20.presented
        backgroundColor: app.welcomeBackgroundV600()
        logoSource: app.authBrandSourceV40()
        titleColor: app.textColor()
        accentColor: app.primaryColor()
        motionAllowed: inGeCoreFlow.motionAllowed
        titlePixelSize: fs(20)
    }
}

Item {
    id: authView
    anchors.fill: parent
    // Derivado de AUTH_FLOW_V800: Auth solo posee la superficie en sus estados
    // (bienvenida, login, autenticando, añadir cuenta, biometría). "Sesión
    // cerrada", el selector y el cierre son QML y nunca quedan tapados.
    visible: setupComplete && authBootstrapDoneV20 && !guestMode
             && app.authSurfaceStateV800
    opacity: sessionEntryTransitionActiveV501
             ? (sessionEntryClosingV501
                ? sessionEntryHomeRevealV501
                : 1.0 - sessionEntryHomeRevealV501)
             : 1.0
    enabled: visible && !sessionEntryTransitionActiveV501
    z: 100

    property bool rememberLogin: true

    onVisibleChanged: app.setFlutterAuthSurfaceV70(visible)

    Timer {
        interval: 55
        repeat: true
        running: authView.visible || app.flutterSecurityOpenV70
        onTriggered: {
            var request = ""
            try { request = Perms.takeFlutterAuthRequest() } catch(e) {}
            if (request.length > 0)
                app.consumeFlutterAuthRequestV70(request)
        }
    }

    Image {
        id: authBackground
        anchors.fill: parent
        source: app.authBackgroundSourceV40()
        fillMode: Image.PreserveAspectCrop
        smooth: true
        scale: 1.0
        transformOrigin: Item.Center
    }

    Rectangle {
        anchors.fill: parent
        color: darkMode ? "#38151A30" : "#10FFFFFF"
    }

    SequentialAnimation {
        id: authEntrance
        ScriptAction {
            script: {
                authColumn.opacity = 0.0
                authColumn.scale = inGeCoreFlow.revealStartScale
                authBackground.scale = 1.025
            }
        }
        ParallelAnimation {
            NumberAnimation { target: authColumn; property: "opacity"; to: 1.0; duration: inGeCoreFlow.pageInDuration; easing.type: inGeCoreFlow.easeOut }
            NumberAnimation { target: authColumn; property: "scale"; to: 1.0; duration: inGeCoreFlow.pageInDuration; easing.type: inGeCoreFlow.easeEmphasized }
            NumberAnimation { target: authBackground; property: "scale"; to: 1.0; duration: inGeCoreFlow.emphasizedDuration; easing.type: inGeCoreFlow.easeOut }
        }
    }

    Component.onCompleted: app.setFlutterAuthSurfaceV70(visible)

    FlowCore.ImeAwareFlickable {
        id: authFlickableV50
        // Android uses Flutter; Desktop uses the existing QML session UI.
        visible: Qt.platform.os !== "android"
        anchors.fill: parent
        flow: inGeCoreFlow
        clip: true
        interactive: true
        boundsBehavior: Flickable.StopAtBounds
        flickableDirection: Flickable.VerticalFlick
        contentWidth: width
        contentHeight: Math.max(authColumn.height + 56, height + 1)

        Column {
            id: authColumn
            width: Math.min(app.width - 44, 430)
            x: (app.width - width) / 2
            y: 54
            spacing: 20
            transformOrigin: Item.Center

            Behavior on y { NumberAnimation { duration: inGeCoreFlow.normalDuration; easing.type: inGeCoreFlow.easeOut } }
            Behavior on spacing { NumberAnimation { duration: inGeCoreFlow.normalDuration; easing.type: inGeCoreFlow.easeOut } }

            Rectangle {
                width: parent.width
                height: 46
                radius: 15
                color: inGeCoreFlow.colors.blue050
                border.color: inGeCoreFlow.theme.border
                border.width: 1
                visible: addingAccountModeV20

                Text {
                    x: 14
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width - 110
                    text: "Añadiendo otra cuenta"
                    color: inGeCoreFlow.theme.textPrimary
                    font.pixelSize: fs(13)
                    font.bold: true
                    elide: Text.ElideRight
                }
                Text {
                    anchors.right: parent.right
                    anchors.rightMargin: 14
                    anchors.verticalCenter: parent.verticalCenter
                    text: "Cancelar"
                    color: inGeCoreFlow.theme.link
                    font.pixelSize: fs(13)
                    font.bold: true
                    MouseArea { anchors.fill: parent; anchors.margins: -10; onClicked: cancelAddAccountV20() }
                }
            }

            Image {
                width: parent.width * 0.86
                height: 112
                anchors.horizontalCenter: parent.horizontalCenter
                source: app.authBrandSourceV40()
                    fillMode: Image.PreserveAspectFit
                smooth: true
            }

            Text {
                width: parent.width
                text: "Iniciar sesión"
                color: app.authPrimaryTextV40()
                font.pixelSize: fs(34)
                font.bold: true
                horizontalAlignment: Text.AlignHCenter
            }

            Text {
                width: parent.width
                text: "Accede a tu espacio de trabajo geotécnico"
                color: app.authMutedTextV40()
                font.pixelSize: fs(16)
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.WordWrap
            }

            Column {
                width: parent.width
                spacing: 16

                Rectangle {
                    width: parent.width
                    height: rememberedAccountsColumnV20.height + 30
                    radius: 20
                    color: inGeCoreFlow.colors.blue050
                    border.color: inGeCoreFlow.theme.border
                    border.width: 1
                    visible: savedAccountsModelV20.length > 0 && !addingAccountModeV20

                    Column {
                        id: rememberedAccountsColumnV20
                        x: 12
                        y: 15
                        width: parent.width - 24
                        spacing: 8

                        Text {
                            width: parent.width
                            text: "Cuentas recordadas"
                            color: inGeCoreFlow.theme.textPrimary
                            font.pixelSize: fs(13)
                            font.bold: true
                        }

                        Repeater {
                            model: Math.min(3, savedAccountsModelV20.length)
                            delegate: Rectangle {
                                property var accountData: savedAccountsModelV20[index]
                                width: rememberedAccountsColumnV20.width
                                height: 58
                                radius: 15
                                color: quickAccountMouseV20.pressed ? inGeCoreFlow.theme.selected : inGeCoreFlow.theme.surfaceElevated
                                border.color: inGeCoreFlow.theme.border
                                border.width: 1
                                scale: quickAccountMouseV20.pressed ? 0.985 : 1.0
                                Behavior on scale { NumberAnimation { duration: inGeCoreFlow.fastDuration; easing.type: inGeCoreFlow.easeOut } }

                                Components.CircularAvatar {
                                    width: 42
                                    height: 42
                                    x: 8
                                    y: 8
                                    source: savedAccountPhotoV20(accountData)
                                    hasImage: savedAccountPhotoV20(accountData).length > 0
                                    borderWidth: 1
                                    fallbackText: accountInitialsV20(savedAccountDisplayNameV20(accountData))
                                }
                                Column {
                                    x: 60
                                    y: 10
                                    width: parent.width - 74
                                    spacing: 3
                                    Text { width: parent.width; text: savedAccountDisplayNameV20(accountData); color: inGeCoreFlow.theme.textPrimary; font.pixelSize: fs(13); font.bold: true; elide: Text.ElideRight }
                                    Text { width: parent.width; text: accountData ? inGeCoreFlow.displayEmailExact(accountData.email, "Cuenta guardada") : "Cuenta guardada"; color: inGeCoreFlow.theme.textSecondary; font.pixelSize: fs(11); elide: Text.ElideRight }
                                }
                                MouseArea {
                                    id: quickAccountMouseV20
                                    anchors.fill: parent
                                    enabled: !accountSwitchBusyV20
                                    onClicked: switchSavedAccountV20(accountData.id)
                                }
                            }
                        }
                    }
                }

                Rectangle {
                    width: parent.width
                    height: 142
                    radius: 24
                    color: "#FAFFFFFF"
                    border.color: inGeCoreFlow.theme.border
                    border.width: 1

                    Column {
                        anchors.fill: parent
                        anchors.leftMargin: 22
                        anchors.rightMargin: 22
                        anchors.topMargin: 10
                        anchors.bottomMargin: 10
                        spacing: 0

                        AuthInlineField {
                            id: loginEmailFieldV50
                            width: parent.width
                            height: 58
                            iconSource: "qrc:/ui/v2/icons/auth/ic_auth_mail.svg"
                            inputMethodHints: Qt.ImhEmailCharactersOnly
                                              | Qt.ImhNoAutoUppercase
                            enterKeyType: Qt.EnterKeyNext
                            placeholderText: "Correo electrónico"
                            text: userEmail
                            onTextChanged: userEmail = text
                            onAccepted: loginPasswordFieldV50.forceInputFocus()
                        }

                        Rectangle { width: parent.width; height: 1; color: inGeCoreFlow.theme.separator }

                        AuthInlineField {
                            id: loginPasswordFieldV50
                            width: parent.width
                            height: 58
                            iconSource: "qrc:/ui/v2/icons/auth/ic_auth_lock.svg"
                            trailingIconSource: passwordVisible ? "qrc:/ui/v2/icons/auth/ic_auth_eye_off.svg" : "qrc:/ui/v2/icons/auth/ic_auth_eye.svg"
                            placeholderText: "Contraseña"
                            passwordField: true
                            inputMethodHints: Qt.ImhNoPredictiveText
                                              | Qt.ImhNoAutoUppercase
                                              | Qt.ImhSensitiveData
                            enterKeyType: Qt.EnterKeyDone
                            text: userPassword
                            onTextChanged: userPassword = text
                            onAccepted: {
                                Qt.inputMethod.hide()
                                login()
                            }
                        }
                    }
                }

                RowLayout {
                    width: parent.width
                    height: 34
                    spacing: 8

                    Rectangle {
                        Layout.preferredWidth: 26
                        Layout.preferredHeight: 26
                        Layout.alignment: Qt.AlignVCenter
                        radius: 7
                        color: authView.rememberLogin ? inGeCoreFlow.theme.infoContainer : "transparent"
                        border.color: authView.rememberLogin ? inGeCoreFlow.theme.accent : inGeCoreFlow.theme.textSecondary
                        border.width: 1.6
                        scale: authView.rememberLogin ? 1.0 : 0.94
                        Behavior on scale { NumberAnimation { duration: inGeCoreFlow.normalDuration; easing.type: inGeCoreFlow.easeOvershoot } }
                        Behavior on color { ColorAnimation { duration: inGeCoreFlow.fastDuration } }
                        Components.FlowIcon {
                            anchors.centerIn: parent
                            width: 18
                            height: 18
                            name: "system.check"
                            flow: inGeCoreFlow
                            active: true
                            tintColor: primaryColor()
                            activeTintColor: primaryColor()
                            inactiveOpacity: 1.0
                            visible: authView.rememberLogin
                        }
                        MouseArea { anchors.fill: parent; onClicked: authView.rememberLogin = !authView.rememberLogin }
                    }

                    Text {
                        Layout.alignment: Qt.AlignVCenter
                        text: "Recordarme"
                        color: inGeCoreFlow.theme.textSecondary
                        font.pixelSize: fs(14)
                    }

                    Item { Layout.fillWidth: true; height: 1 }

                    Text {
                        Layout.alignment: Qt.AlignVCenter
                        text: "¿Olvidaste tu contraseña?"
                        color: inGeCoreFlow.theme.link
                        font.pixelSize: fs(12)
                        MouseArea { anchors.fill: parent; onClicked: showToast("Recuperación pendiente") }
                    }
                }

                PrimaryButton {
                    width: parent.width
                    height: 58
                    radius: 17
                    label: serverBusy ? "Ingresando..." : "Ingresar"
                    enabled: !serverBusy
                    onClicked: login()
                }
                Button {
                    width: parent.width
                    visible: Qt.platform.os !== "android"
                    text: "Trabajar localmente"
                    enabled: !serverBusy
                    onClicked: {
                        app.guestMode = true
                        app.setPageImmediate(0)
                    }
                }

                Row {
                    width: parent.width
                    height: 34
                    spacing: 12
                    Rectangle { width: (parent.width - 54) / 2; height: 1; color: inGeCoreFlow.theme.separator; anchors.verticalCenter: parent.verticalCenter }
                    Components.FlowIcon {
                        width: 30; height: 30
                        name: "security.account"
                        flow: inGeCoreFlow
                        active: true
                        tintColor: primaryColor()
                        activeTintColor: primaryColor()
                        inactiveOpacity: 1.0
                        anchors.verticalCenter: parent.verticalCenter
                    }
                    Rectangle { width: (parent.width - 54) / 2; height: 1; color: inGeCoreFlow.theme.separator; anchors.verticalCenter: parent.verticalCenter }
                }

            }

        }
    }
}

Item {
    id: sessionWorkspaceV501
    anchors.fill: parent
    visible: loggedIn || guestMode
    opacity: sessionEntryTransitionActiveV501
             ? (sessionEntryClosingV501
                ? 1.0 - sessionEntryHomeRevealV501
                : sessionEntryHomeRevealV501)
             : 1.0
    enabled: visible && !sessionEntryTransitionActiveV501

    // El Header conserva su componente visual y sus acciones en una capa
    // superpuesta. Este Item no tiene MouseArea: fuera del Header el
    // contenido recibe el touch.
    Item {
        id: navigationShellV51
        anchors.fill: parent
        z: 120

        readonly property string currentContext:
            app.profileOverlayOpenV18 ? "profile"
            : (app.pageIndex === 0 ? "home"
            : (app.pageIndex === 1 ? "calicataEditor"
            : (app.pageIndex === 2 ? "earth"
            : (app.pageIndex === 3 ? "global"
            : (app.pageIndex === 4 ? "settings"
            : (app.pageIndex === 5 ? "inventory" : "renditions"))))))
        readonly property bool headerVisible: currentContext === "home"
        // Foreground surface declared by the shell. The dock controller only
        // uses it to decide which published snapshot is the active one.
        readonly property string foregroundSurface:
            !(app.loggedIn || app.guestMode) || app.profileOverlayOpenV18 ? ""
            : (app.pageIndex === 0 ? "home"
            : (app.pageIndex === 1 ? "calicatas"
            : (app.pageIndex === 2 ? "earth"
            : (app.pageIndex === 3 ? "documents"
            : (app.pageIndex === 4 ? ""
            : (app.pageIndex === 5 ? "" : "renditions"))))))
    }

    Binding {
        target: dockContextController
        property: "foregroundOwner"
        value: navigationShellV51.foregroundSurface
    }

    // The single physical dock of the application.
    Binding {
        target: app.inGeCoreFlow
        property: "glassMaterial"
        value: globalContextDockV1
    }

    FlowCore.GlobalContextDock {
        id: globalContextDockV1
        parent: navigationShellV51
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        z: 140
        flow: inGeCoreFlow
        bottomSafeInset: app.safeBottomInsetV49
        // Supresión temporal durante una operación bloqueante de Calicatas: usa
        // el mismo camino de ocultación que el teclado (sin tocar el Dock).
        // Con InGe+ IA abierta (estado real GeminiAssistant.active) el Dock
        // global cede el borde inferior al panel de la IA por el mismo camino.
        keyboardVisible: inGeCoreFlow.imeVisible || Qt.inputMethod.visible
                         || (app.pageIndex === 1 && app.calicataDockSuppressed)
                         || app.geminiAssistantTransport.active === true
        backdropItem: pageViewport
        nativeSurface: app.flutterHomeActiveV60 || app.pageIndex === 2 || app.pageIndex === 6
        // Earth's WebView exposes the dock through apertures over MapNativePage
        // (#02050A), so the material behind the glass is dark.
        darkBackdrop: app.pageIndex === 2
    }

    Item {
        id: accountHeaderV20
        parent: navigationShellV51
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        height: visible ? 72 : 0
        visible: navigationShellV51.headerVisible
                 && !(navigationShellV51.currentContext === "home"
                      && app.flutterHomeActiveV60)
        enabled: visible
        z: 120

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 14
            anchors.rightMargin: 14
            anchors.topMargin: 10
            anchors.bottomMargin: 10
            spacing: 8

            Item {
                id: homeIdentityCapsuleV50
                readonly property real leftPaddingV502: 13
                readonly property real rightPaddingV502: 6
                readonly property real contentSpacingV502: 9
                readonly property real avatarSizeV502: 32
                readonly property real contentWidthV502:
                    leftPaddingV502
                    + Math.max(homeIdentityNameV50.implicitWidth,
                               homeIdentityRoleV50.implicitWidth)
                    + contentSpacingV502
                    + avatarSizeV502
                    + rightPaddingV502
                Layout.fillWidth: false
                Layout.minimumWidth: 112
                Layout.maximumWidth: accountRoleV25() === "DEV" ? 190 : 160
                Layout.preferredWidth: accountRoleV25() === "DEV"
                                       ? 190
                                       : Math.max(Layout.minimumWidth,
                                                  Math.min(Layout.maximumWidth,
                                                           contentWidthV502))
                Layout.preferredHeight: 44
                Layout.alignment: Qt.AlignLeft | Qt.AlignVCenter

                Rectangle {
                    anchors.fill: parent
                    anchors.topMargin: 3
                    radius: height / 2
                    color: app.darkMode ? "#59000000" : "#1C151A30"
                    opacity: app.liquidGlass ? 0.40 : 1.0
                }

                FlowCore.FlowGlassSurface {
                    anchors.fill: parent
                    flow: inGeCoreFlow
                    darkMode: app.darkMode
                    materialRole: "emphasized"
                    strength: 0.94
                    elevationEnabled: app.liquidGlass
                    blurSource: pageViewport
                    blurEnabled: app.liquidGlass
                    blurAmount: 0.36
                    blurSaturation: -0.04
                    radius: height / 2
                    fallbackLight: inGeCoreFlow.theme.surfaceElevated
                    fallbackDark: inGeCoreFlow.theme.surfaceElevated

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: homeIdentityCapsuleV50.leftPaddingV502
                        anchors.rightMargin: homeIdentityCapsuleV50.rightPaddingV502
                        spacing: homeIdentityCapsuleV50.contentSpacingV502

                        ColumnLayout {
                            Layout.fillWidth: true
                            Layout.alignment: Qt.AlignVCenter
                            spacing: -2

                            FlowCore.FlowText {
                                id: homeIdentityNameV50
                                Layout.fillWidth: true
                                text: homeHeaderFirstNameV50()
                                color: inGeCoreFlow.theme.textPrimary
                                role: "body"
                                font.pixelSize: fs(14)
                                font.weight: inGeCoreFlow.typography.semiboldWeight
                                elide: Text.ElideRight
                                maximumLineCount: 1
                                wrapMode: Text.NoWrap
                            }

                            FlowCore.FlowText {
                                id: homeIdentityRoleV50
                                Layout.fillWidth: true
                                text: accountRoleV25()
                                color: inGeCoreFlow.theme.textSecondary
                                role: "caption"
                                font.pixelSize: fs(9)
                                elide: Text.ElideRight
                                maximumLineCount: 1
                                wrapMode: Text.NoWrap
                            }
                        }

                        Components.CircularAvatar {
                            id: homeIdentityAvatarV50
                            Layout.preferredWidth: homeIdentityCapsuleV50.avatarSizeV502
                            Layout.preferredHeight: homeIdentityCapsuleV50.avatarSizeV502
                            Layout.alignment: Qt.AlignVCenter
                            source: accountPhotoV18()
                            hasImage: accountHasPhotoV18()
                            backgroundColor: app.liquidGlass
                                             ? Qt.rgba(1.0, 1.0, 1.0, 0.18)
                                             : inGeCoreFlow.theme.selected
                            borderColor: app.liquidGlass
                                         ? inGeCoreFlow.theme.glassHighlight
                                         : inGeCoreFlow.theme.border
                            borderWidth: 1
                            fallbackText: guestMode
                                          ? "" : accountInitialsV20(homeHeaderFirstNameV50())
                            fallbackColor: inGeCoreFlow.theme.textPrimary
                            fallbackTextColor: inGeCoreFlow.theme.accent
                            showStatus: !guestMode
                            statusColor: inGeCoreFlow.theme.success
                        }
                    }
                }

                MouseArea {
                    id: homeIdentityCapsuleMouseV50
                    anchors.fill: parent
                    onClicked: openProfileOverlayV18()
                    Accessible.name: "Abrir perfil de " + homeHeaderFirstNameV50()
                    Accessible.role: Accessible.Button
                }

                scale: homeIdentityCapsuleMouseV50.pressed
                       ? inGeCoreFlow.compactPressScale : 1.0

                Behavior on scale {
                    NumberAnimation {
                        duration: inGeCoreFlow.fastDuration
                        easing.type: inGeCoreFlow.easeOut
                    }
                }
            }

            Item { Layout.fillWidth: true }

            HeaderGlassIconButton {
                id: globalSearchButtonV30
                Layout.preferredWidth: 50
                Layout.preferredHeight: 50
                Layout.alignment: Qt.AlignVCenter
                iconName: "action.search"
                materialSource: pageViewport
                accessibleName: "Buscar"
                onClicked: app.openGlobalSearchV30("")
            }

            HeaderGlassIconButton {
                id: homeNotificationsButtonV50
                Layout.preferredWidth: 50
                Layout.preferredHeight: 50
                Layout.alignment: Qt.AlignVCenter
                iconName: "profile.notifications"
                materialSource: pageViewport
                accessibleName: "Notificaciones"
                onClicked: {}
            }
        }
    }


    Item {
        id: pageViewport
        anchors.fill: parent
        // Content continues behind the single dock; no flat reserved tray.
        clip: true

        // Existing InGe+ surface token remains visible while Loader or a
        // native Flutter/WebView surface produces its first real frame.
        Rectangle {
            anchors.fill: parent
            color: app.darkMode ? inGeCoreFlow.colors.ingemaDeep : "#F8FAFD"
        }

        Loader {
            id: pageLoader
            active: app.loggedIn || app.guestMode
            anchors.fill: parent
            opacity: 1.0
            // Entrada de sub-app: el item nuevo nace invisible 7dp abajo y se
            // asienta en ~220 ms. Sin salida (el Loader único ya destruyó la
            // anterior); el token de superficie de debajo evita el frame vacío.
            transform: Translate { id: pageEnterTranslateV600; y: 0 }
            sourceComponent: pageIndex === 0 ? homePage :
                             pageIndex === 1 ? fichaPage :
                             pageIndex === 2 ? mapPage :
                             pageIndex === 3 ? documentsPage :
                             pageIndex === 4 ? settingsSoonPage :
                             pageIndex === 5 ? inventoryPage :
                             pageIndex === 6 ? renditionPage : homePage



            onLoaded: {
                app.playPageEnterV600()
                Qt.callLater(function() {
                    if (app.navigationTargetV80 === app.pageIndex
                            && app.navigationStartedAtV80 > 0) {
                        console.info("SUBAPP_FIRST_FRAME target=" + app.pageIndex
                                     + " navigationToFirstFrameMs="
                                     + Math.max(0, Date.now()
                                                - app.navigationStartedAtV80))
                        app.navigationStartedAtV80 = 0
                        app.navigationTargetV80 = -1
                    }
                })
            }
        }



        // Página saliente congelada (solo durante el cambio de sub-app).
        ShaderEffectSource {
            id: pageSnapshotV600
            anchors.fill: parent
            live: false
            hideSource: false
            sourceItem: null
            visible: sourceItem !== null
            opacity: 0.0
            z: 5
        }



    }

}

Item {
    id: sessionWelcomeHoldCoverV600
    anchors.fill: parent
    z: 2290
    visible: opacity > 0.01
    opacity: app.sessionWelcomeHoldV600 ? 1.0 : 0.0
    Behavior on opacity {
        OpacityAnimator { duration: inGeCoreFlow.motionAllowed ? 200 : 0; easing.type: Easing.OutCubic }
    }
    MouseArea { anchors.fill: parent; enabled: app.sessionWelcomeHoldV600; preventStealing: true }
    WelcomeSplashV600 {
        anchors.fill: parent
        active: app.sessionWelcomeHoldV600
        backgroundColor: app.welcomeBackgroundV600()
        logoSource: app.authBrandSourceV40()
        titleColor: app.textColor()
        accentColor: app.primaryColor()
        motionAllowed: inGeCoreFlow.motionAllowed
        titlePixelSize: fs(20)
    }
}

Item {
    id: sessionEntryOverlayV501
    anchors.fill: parent
    z: 2300
    visible: app.sessionEntryTransitionActiveV501
    opacity: 0.0
    enabled: visible

    Rectangle {
        anchors.fill: parent
        color: inGeCoreFlow.theme.scrim
        visible: !app.sessionEntryWelcomeV600
    }

    MouseArea {
        anchors.fill: parent
        preventStealing: true
    }

    WelcomeSplashV600 {
        anchors.fill: parent
        visible: app.sessionEntryWelcomeV600
        active: app.sessionEntryWelcomeV600 && sessionEntryOverlayV501.visible
        backgroundColor: app.welcomeBackgroundV600()
        logoSource: app.authBrandSourceV40()
        titleColor: app.textColor()
        accentColor: app.primaryColor()
        motionAllowed: inGeCoreFlow.motionAllowed
        titlePixelSize: fs(20)
    }

    Column {
        anchors.centerIn: parent
        spacing: 16
        visible: !app.sessionEntryWelcomeV600

        FlowCore.FlowBusyIndicator {
            width: 48
            height: 48
            anchors.horizontalCenter: parent.horizontalCenter
            flow: inGeCoreFlow
            running: sessionEntryOverlayV501.visible
            accent: "#FFFFFF"
            track: "#3DFFFFFF"
            stroke: 3
        }

        FlowCore.FlowText {
            width: Math.min(app.width - 64, 260)
            text: app.sessionEntryTextV501
            role: "subtitle"
            color: "#FFFFFF"
            font.pixelSize: fs(17)
            font.weight: inGeCoreFlow.typography.semiboldWeight
            horizontalAlignment: Text.AlignHCenter
        }
    }
}

Timer {
    id: sessionEntryHomeTimeoutV600
    // Seguridad: nunca retener la cubierta si Flutter Home no responde.
    interval: 1800
    repeat: false
    onTriggered: app.sessionWelcomeHoldV600 = false
}

Timer {
    id: sessionEntryMinimumTimerV501
    interval: 240
    repeat: false
    onTriggered: app.revealSessionWorkspaceV501()
}

ParallelAnimation {
    id: sessionEntryRevealV501

    NumberAnimation {
        target: sessionEntryOverlayV501
        property: "opacity"
        to: 0.0
        duration: inGeCoreFlow.motionAllowed ? 230 : 180
        easing.type: inGeCoreFlow.easeOut
    }

    NumberAnimation {
        target: app
        property: "sessionEntryHomeRevealV501"
        to: 1.0
        duration: inGeCoreFlow.motionAllowed ? 230 : 180
        easing.type: inGeCoreFlow.easeOut
    }

    onFinished: {
        // HOME se confirma antes de soltar la transición: Auth deja de ser
        // visible con Home ya dueño de la superficie (sin parpadeo).
        if (!app.sessionEntryClosingV501)
            app.finishSessionEntryStateV800()
        app.sessionEntryHomeRevealV501 = 1.0
        app.sessionEntryWelcomeV600 = false
        app.sessionEntryTransitionActiveV501 = false
        app.sessionEntryIdentityCommittedV501 = false
        app.sessionEntryClosingV501 = false
        app.flutterHomeHandoffV800 = false
        sessionEntryOverlayV501.opacity = 0.0
    }
}

FlowCore.FlowQuickBubble {
    id: quickBubbleV32
    anchors.fill: parent
    z: 1950
    flow: inGeCoreFlow
    darkMode: app.darkMode

    onActionTriggered: function(actionKey) {
        app.handleQuickBubbleActionV32(actionKey)
    }
}

GlobalSearchOverlay {
    id: globalSearchOverlayV30
    anchors.fill: parent
    z: 1800
    flow: inGeCoreFlow
    darkMode: app.darkMode
    currentUserName: accountNameV18()
    currentEmailExact: guestMode ? "" : accountEmailV18()
    currentCalicataCode: calCode
    currentCalicataProject: calProject
    guestMode: app.guestMode

    onResultActivated: function(kind, payload, title) {
        app.handleGlobalSearchResultV30(kind, payload, title)
    }
}

Component {
    id: homePhase1Page

    Pages.HomePagePhase1 {
        anchors.fill: parent
        flow: inGeCoreFlow
        themeMode: app.pageThemeModeV70()
        darkMode: app.darkMode
        calCode: app.calCode
        calProject: app.calProject
        navigationInset: app.safeBottomInsetV49
        onNavigateRequested: function(page) { app.navigateToPage(page) }
        onMessageRequested: function(message) { app.showToast(message) }
    }
}

Component {
    id: homePage

    Item {
        id: homeRoot
        anchors.fill: parent

        function requestFlutterHomeV60() {
            if (!flutterHomeShouldShowV60()) {
                syncFlutterHomeVisibilityV60()
                return
            }
            var accepted = false
            try {
                app.syncFlutterAuthStateV70(false)
                accepted = Perms.setFlutterHomeVisible(
                            true,
                            app.darkMode ? "dark" : "light",
                            inGeCoreFlow.motionAllowed ? 1.0 : 0.0,
                            app.liquidGlass ? 0.72 : 0.0,
                            String(inGeCoreFlow.performance.profile))
            } catch (error) {
                console.warn("[InGe+ Home] Flutter host no disponible:", error)
            }
            if (accepted)
                flutterHomeReadyPollV60.start()
        }

        function flutterHomeShouldShowV60() {
            return Qt.platform.os === "android" && navigationShellV51.currentContext === "home"
                    && (app.loggedIn || app.guestMode)
                    && (app.flutterHomeHandoffV800
                        || (!app.sessionEntryTransitionActiveV501
                            && !authView.visible
                            && (app.authFlowStateV800 === "HOME"
                                || app.authFlowStateV800 === "ACCOUNT_PICKER")))
                    && !app.profileOverlayOpenV18
                    && !app.accountSwitchSheetOpenV18
                    && !app.loginRedirectOpenV18
                    && !globalSearchOverlayV30.presented
                    && !quickBubbleV32.presented
        }

        function syncFlutterHomeVisibilityV60() {
            var shouldShow = flutterHomeShouldShowV60()
            if (!app.flutterHomeActiveV60) {
                if (shouldShow) {
                    requestFlutterHomeV60()
                } else {
                    try {
                        Perms.setFlutterHomeVisible(
                                    false, "light", 1.0, 0.0, "balanced")
                    } catch (error) {}
                }
                return
            }
            try {
                Perms.setFlutterHomeVisible(
                            shouldShow,
                            app.darkMode ? "dark" : "light",
                            inGeCoreFlow.motionAllowed ? 1.0 : 0.0,
                            app.liquidGlass ? 0.72 : 0.0,
                            String(inGeCoreFlow.performance.profile))
            } catch (error) {}
        }

        function consumeFlutterHomeActionV60(action) {
            if (action === "home") {
                app.navigateToPage(0)
            } else if (action === "profile") {
                app.openProfileOverlayV18()
            } else if (action === "search") {
                app.openGlobalSearchV30("")
            } else if (action === "notifications") {
                // Conserva el callback actualmente vacío del Header QML.
            } else if (action === "calicatas" || action === "newProject") {
                app.navigateToPage(1)
            } else if (action === "documents" || action === "templates") {
                app.navigateToPage(3)
            } else if (action === "earth") {
                app.navigateToPage(2)
            } else if (action === "renditions") {
                app.navigateToPage(6)
            } else if (action === "sync") {
                app.dispatchGlobalSyncV60()
            } else if (action === "settings") {
                app.navigateToPage(4)
            }
        }

        Component.onCompleted: Qt.callLater(requestFlutterHomeV60)
        Component.onDestruction: {
            flutterHomeReadyPollV60.stop()
            flutterHomeActionPollV60.stop()
            app.flutterHomeActiveV60 = false
            try {
                Perms.setFlutterHomeVisible(false, "light", 1.0, 0.0, "balanced")
            } catch (error) {}
        }

        Timer {
            id: flutterHomeReadyPollV60
            interval: 100
            repeat: true
            onTriggered: {
                var ready = false
                try { ready = Perms.isFlutterHomeReady() } catch (error) {}
                if (!ready)
                    return
                stop()
                app.flutterHomeActiveV60 = true
                flutterHomeActionPollV60.start()
                homeRoot.syncFlutterHomeVisibilityV60()
            }
        }

        Connections {
            target: app
            function onProfileOverlayOpenV18Changed() {
                homeRoot.syncFlutterHomeVisibilityV60()
            }
            function onAccountSwitchSheetOpenV18Changed() {
                homeRoot.syncFlutterHomeVisibilityV60()
            }
            function onLoginRedirectOpenV18Changed() {
                homeRoot.syncFlutterHomeVisibilityV60()
            }
            function onLoggedInChanged() {
                homeRoot.syncFlutterHomeVisibilityV60()
            }
            function onGuestModeChanged() {
                homeRoot.syncFlutterHomeVisibilityV60()
            }
            function onSessionEntryTransitionActiveV501Changed() {
                homeRoot.syncFlutterHomeVisibilityV60()
            }
            function onPageIndexChanged() {
                homeRoot.syncFlutterHomeVisibilityV60()
            }
            function onAuthFlowStateV800Changed() {
                homeRoot.syncFlutterHomeVisibilityV60()
            }
            // V90: live profile (device tier, battery saver, heat, user pick).
            // callLater: the profile Binding on InGeCoreFlow settles first.
            function onEffectivePerformanceLevelV90Changed() {
                Qt.callLater(homeRoot.syncFlutterHomeVisibilityV60)
            }
        }

        Connections {
            target: Mobile.InGeCoreFlow
            function onMotionAllowedChanged() {
                Qt.callLater(homeRoot.syncFlutterHomeVisibilityV60)
            }
        }

        Connections {
            target: authView
            function onVisibleChanged() {
                homeRoot.syncFlutterHomeVisibilityV60()
            }
        }

        Connections {
            target: globalSearchOverlayV30
            function onPresentedChanged() {
                homeRoot.syncFlutterHomeVisibilityV60()
            }
        }

        Connections {
            target: quickBubbleV32
            function onPresentedChanged() {
                homeRoot.syncFlutterHomeVisibilityV60()
            }
        }

        Timer {
            id: flutterHomeActionPollV60
            interval: 60
            repeat: true
            onTriggered: {
                var action = ""
                try { action = Perms.takeFlutterHomeAction() } catch (error) {}
                if (action.length > 0)
                    homeRoot.consumeFlutterHomeActionV60(action)
            }
        }

        Rectangle {
            anchors.fill: parent
            // Fondo del renderer QML de respaldo. Durante Home activo la
            // superficie Flutter ocupa el viewport completo y proyecta sus
            // propios controles flotantes, sin bandas nativas reservadas.
            color: app.flutterHomeActiveV60 && app.liquidGlass
                   ? (app.darkMode ? inGeCoreFlow.colors.ingemaDeepShade : inGeCoreFlow.colors.blue100)
                   : inGeCoreFlow.theme.background
            visible: true
            z: -10
        }

        Image {
            anchors.fill: parent
            visible: app.liquidGlass
                     && !app.flutterHomeActiveV60
            source: app.liquidGlass ? "qrc:/ui/v2/backgrounds/bg_topographic_lines.svg" : ""
            sourceSize: Qt.size(Math.max(1, width), Math.max(1, height))
            asynchronous: true
            fillMode: Image.PreserveAspectCrop
            opacity: 0.34
            smooth: true
        }

        Rectangle {
            anchors.fill: parent
            visible: app.liquidGlass
                     && !app.flutterHomeActiveV60
            gradient: Gradient {
                GradientStop { position: 0.0; color: "#4D8FB2D5" }
                GradientStop { position: 1.0; color: "#661C2D50" }
            }
        }

        // Todo el movimiento continúa gobernado por InGeCoreFlow.
        // Este módulo solo define estructura, contenido y navegación.


        Flickable {
            id: homeFlickable
            anchors.fill: parent
            visible: !app.flutterHomeActiveV60
            clip: true
            interactive: contentHeight > height
            flickableDirection: Flickable.VerticalFlick
            pressDelay: inGeCoreFlow.touchPressDelay
            flickDeceleration: inGeCoreFlow.flickDeceleration
            maximumFlickVelocity: inGeCoreFlow.scrollVelocity(contentHeight, height)
            boundsBehavior: inGeCoreFlow.motionAllowed
                            ? Flickable.DragAndOvershootBounds
                            : Flickable.StopAtBounds
            contentWidth: width
            contentHeight: homeCol.height + app.safeBottomInsetV49

            Column {
                id: homeCol
                width: homeFlickable.width
                spacing: 14
                padding: 16
                // Conserva la posicion visual de Home; solo su fondo ocupa
                // ahora la superficie completa por debajo del Header overlay.
                topPadding: accountHeaderV20.height + 16

                Text {
                    id: homeTitle
                    width: parent.width - 32
                    text: "Herramientas de campo"
                    opacity: 1.0
                    scale: 1.0
                    transformOrigin: Item.Left
                    color: textColor()
                    font.pixelSize: fs(22)
                    font.bold: true
                    maximumLineCount: 1
                    elide: Text.ElideRight
                }

                ModuleCardV2 {
                    id: homeCardCalicatas
                    width: parent.width - 32
                    featured: true
                    revealProgress: 1.0
                    moduleAvailable: true
                    statusLabel: "Disponible"
                    actionLabel: "Abrir Calicatas"
                    title: "Calicatas"
                    subtitle: "Crea, edita y administra registros geotécnicos de campo."
                    iconName: "module.calicatas"
                    imageSource: "qrc:/ui/v2/illustrations/illus_module_calicatas.svg"
                    accent: inGeCoreFlow.colors.ingemaBlue
                    onClicked: navigateToPage(1)
                }

                Text {
                    width: parent.width - 32
                    text: "Módulos en desarrollo"
                    color: mutedColor()
                    font.pixelSize: fs(13)
                    font.bold: true
                    topPadding: 2
                }

                ModuleCardV2 {
                    id: homeCardTaludes
                    width: parent.width - 32
                    featured: false
                    revealProgress: 1.0
                    moduleAvailable: false
                    statusLabel: "Próximamente"
                    title: "Taludes"
                    subtitle: "Evaluación y registro técnico de taludes y laderas."
                    iconName: "module.taludes"
                    accent: inGeCoreFlow.colors.ingemaGreen
                }

                ModuleCardV2 {
                    id: homeCardEstratos
                    width: parent.width - 32
                    featured: false
                    revealProgress: 1.0
                    moduleAvailable: false
                    statusLabel: "Próximamente"
                    title: "Perfiles estratigráficos"
                    subtitle: "Construcción y organización de perfiles del terreno."
                    iconName: "module.stratigraphy"
                    accent: inGeCoreFlow.colors.ingemaBlue
                }

                ModuleCardV2 {
                    id: homeCardGeomecanica
                    width: parent.width - 32
                    featured: false
                    revealProgress: 1.0
                    moduleAvailable: false
                    statusLabel: "Próximamente"
                    title: "Estaciones geomecánicas"
                    subtitle: "Registro técnico de estaciones y macizos rocosos."
                    iconName: "module.geomechanics"
                    accent: inGeCoreFlow.colors.ingemaGreen
                }

                Item {
                    width: 1
                    height: app.safeBottomInsetV49
                }
            }
        }
    }
}


    Component {
    id: fichaPage

    Pages.CalicatasEditorPage {
        id: activeEditor
        Component.onCompleted: app.activeCalicataEditor = activeEditor
        Component.onDestruction: {
            if (app.activeCalicataEditor === activeEditor) app.activeCalicataEditor = null
            app.setCalicataDockSuppressed(false, "")
        }
        onDockSuppressedChanged: app.setCalicataDockSuppressed(dockSuppressed,
                                     foregroundOperation ? String(foregroundOperation.kind || "") : "")
        anchors.fill: parent
        auth: app.authContextV23
        darkMode: app.darkMode
        themeMode: app.pageThemeModeV70()
        flow: inGeCoreFlow
        flowMotionEnabled: inGeCoreFlow.enabled
        flowReduceMotion: inGeCoreFlow.reduceMotion
        flowMotionLevel: inGeCoreFlow.motionLevel
        gpsEnabled: app.gpsRequestedM0809 && app.gpsPermissionGrantedM0809

        onRequestGpsAutoShare: function(on) {
            app.requestGpsM0809(on)
        }

        onRequestBack: {
            // El Back nativo ya pasó por handleBack() para cerrar popups reales.
            // Si llegó hasta aquí debe abandonar Calicatas, nunca recorrer etapas.
            // Puede venir de un clic (p. ej. "Volver" del overlay): salida diferida.
            app.leaveCalicatasSafely()
        }
    }
}

    Component {
    id: mapPage

    Pages.MapNativePage {
        anchors.fill: parent
        auth: app.authContextV23
        graphicsCore: inGeCoreFlow.graphicsCore
        flow: inGeCoreFlow
        darkMode: app.darkMode
        themeMode: app.pageThemeModeV70()
        navigationInset: 0
        pageActive: app.pageIndex === 2
        gpsEnabled: app.gpsRequestedM0809 && app.gpsServiceEnabledM0809
        gpsServiceEnabled: app.gpsServiceEnabledM0809
        gpsHasFix: app.gpsHasFix
        gpsFollow: app.gpsFollow
        gpsPermissionState: app.gpsPermissionStateM0809
        gpsStatusText: app.gpsStatus
        gpsErrorText: app.gpsErrorM0809
        gpsLat: app.gpsLat
        gpsLon: app.gpsLng
        gpsAlt: app.gpsAlt
        gpsAccuracy: app.gpsAccuracyM0809
        gpsLastUpdate: app.gpsLastUpdateM0809
        gpsProvider: app.gpsProviderM0809
        currentCalicataCode: app.calCode
        currentProjectId: ""
        currentProjectName: app.calProject

        onRequestGpsEnabled: function(on) {
            app.requestGpsM0809(on, false)
        }

        onRequestGpsRefresh: {
            try { Perms.refreshNativeLocation() } catch (refreshError) {
                console.warn("[InGe+ GPS] No se pudo refrescar desde el mapa:", refreshError)
            }
        }

        onRequestGpsFollow: function(enabled) {
            app.gpsFollow = enabled
            if (enabled && !app.gpsRequestedM0809)
                app.requestGpsM0809(true, false)
        }

        onRequestUsePoint: function(latitude, longitude, altitude, sourceLabel) {
            app.useSelectedMapPointM0809(latitude, longitude, altitude, sourceLabel)
        }

        onMapInteractionChanged: function(active) {
            app.mapGestureBusy = active
        }

        Component.onDestruction: app.mapGestureBusy = false

        onRequestOpenCalicatas: app.navigateToPage(1)
        onRequestExitMap: app.navigateToPage(0)
        onRequestMeasure: app.showToast("Medición preparada para la siguiente fase")
        onRequestGlobalSearch: function(initialText) {
            app.openGlobalSearchV30(initialText)
        }

        onRequestOpenLocationSettings: {
            var opened = false
            try {
                opened = app.gpsPermissionStateM0809 === "denied"
                        ? Perms.openApplicationSettings()
                        : Perms.openLocationSettings()
                if (opened)
                    app.gpsActivationPromptShownM0809 = true
            } catch (error) {
                console.warn("[InGe+ V38.9] No se pudo abrir ubicación:", error)
            }

            if (!opened)
                app.showToast("Activa la ubicación del dispositivo y vuelve a InGe+")
        }
    }
}


Component {
    id: documentsPage

    NothingFiles.NothingDocumentsRoot {
        onRenditionOpenRequested: function(renditionId) {
            renditionFlutterBridge.openDocumentTarget(renditionId)
            app.navigateToPage(6)
        }
        onCalicataOpenRequested: function(projectId, calicataId) {
            app.openCloudCalicata(projectId, calicataId)
        }
        onCalicataExcelOpenRequested: function(localPath, source) {
            app.openCalicataExcel(localPath, source)
        }
        anchors.fill: parent
        systemDark: app.darkMode
        motionAllowed: inGeCoreFlow.motionAllowed
        flow: inGeCoreFlow
        bottomSafeInset: globalContextDockV1.shown ? 0 : app.safeBottomInsetV49
    }
}

Component {
    id: settingsSoonPage

    Item {
        id: settingsRoot
        anchors.fill: parent
        function f(px) { return fs(px) }

        Item {
            id: settingsBackdropV70
            anchors.fill: parent
            Rectangle {
                anchors.fill: parent
                color: inGeCoreFlow.theme.backgroundGrouped
            }
            Image {
                anchors.fill: parent
                source: liquidGlass ? "qrc:/ui/v2/backgrounds/bg_topographic_lines.svg" : ""
                sourceSize: Qt.size(Math.max(1, width), Math.max(1, height))
                asynchronous: true
                fillMode: Image.PreserveAspectCrop
                opacity: liquidGlass ? 0.34 : 0.0
            }
        }

        Flickable {
            anchors.fill: parent
            contentWidth: width
            contentHeight: settingsColumn.height + 30
            clip: true
            boundsBehavior: inGeCoreFlow.motionAllowed
                            ? Flickable.DragAndOvershootBounds
                            : Flickable.StopAtBounds

            Column {
                id: settingsColumn
                x: 16; y: 14
                width: parent.width - 32
                spacing: 12

                FlowCore.FlowGlassSurface {
                    width: parent.width; height: 72; radius: 24
                    flow: inGeCoreFlow; darkMode: app.darkMode
                    materialRole: "emphasized"
                    strength: 0.98
                    elevationEnabled: liquidGlass
                    blurSource: settingsBackdropV70
                    fallbackLight: inGeCoreFlow.theme.surfaceElevated
                    fallbackDark: inGeCoreFlow.theme.surfaceElevated
                    Row {
                        anchors.fill: parent
                        anchors.margins: 11
                        spacing: 12
                    Rectangle {
                        width: 46; height: 46; radius: 15
                        color: inGeCoreFlow.theme.selected
                        anchors.verticalCenter: parent.verticalCenter
                        Components.FlowIcon {
                            anchors.centerIn: parent
                            width: 22; height: 22
                            name: "nav.settings"
                            flow: inGeCoreFlow
                            active: true
                        }
                    }
                    Column {
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width - 58; spacing: 2
                        Text { width: parent.width; text: "Ajustes"; color: textColor(); font.pixelSize: settingsRoot.f(21); font.bold: true }
                        Text { width: parent.width; text: "Personaliza InGe+ y tu flujo de trabajo"; color: mutedColor(); font.pixelSize: settingsRoot.f(11); elide: Text.ElideRight }
                    }
                    }
                }

                FlowCore.FlowGlassSurface {
                    width: parent.width; height: 104; radius: 24
                    flow: inGeCoreFlow; darkMode: false
                    materialRole: "regular"
                    strength: 1.0
                    elevationEnabled: false
                    blurSource: null
                    SettingsActionRow {
                        anchors.fill: parent
                        anchors.margins: 8
                        title: "Apariencia normal"
                        subtitle: "Tema claro y superficies limpias"
                        iconName: "nav.settings"
                    }
                }

                FlowCore.FlowGlassSurface {
                    width: parent.width; height: 176; radius: 24
                    flow: inGeCoreFlow; darkMode: app.darkMode
                    materialRole: "regular"
                    strength: 0.96
                    elevationEnabled: liquidGlass
                    blurSource: settingsBackdropV70
                    Column {
                        anchors.fill: parent; anchors.margins: 14; spacing: 0
                        Text { height: 30; text: "Accesibilidad"; color: textColor(); font.pixelSize: settingsRoot.f(15); font.bold: true }
                        SettingsActionRow {
                            width: parent.width; title: "Reducir movimiento"
                            subtitle: reduceMotion ? "Activado" : "Transiciones fluidas"
                            iconName: reduceMotion ? "system.check" : "nav.settings"
                            showSwitch: true
                            checked: reduceMotion
                            onClicked: {
                                reduceMotion = !reduceMotion
                                persistUiStateV41()
                                showToast(reduceMotion ? "Movimiento reducido" : "Animaciones activadas")
                            }
                        }
                        Rectangle { width: parent.width; height: 1; color: borderColor() }
                        SettingsActionRow {
                            width: parent.width; title: "Tamaño del texto"
                            subtitle: Math.round(fontScale * 100) + "%"
                            iconName: "action.search"; trailingText: fontScale >= 1.14 ? "Restablecer" : "Aumentar"
                            onClicked: cycleTextScaleV32()
                        }
                    }
                }

                FlowCore.FlowGlassSurface {
                    width: parent.width; height: 118; radius: 24
                    flow: inGeCoreFlow; darkMode: app.darkMode
                    materialRole: "regular"
                    strength: 0.96
                    elevationEnabled: liquidGlass
                    blurSource: settingsBackdropV70
                    Column {
                        anchors.fill: parent; anchors.margins: 14; spacing: 0
                        Text { height: 30; text: "Rendimiento"; color: textColor(); font.pixelSize: settingsRoot.f(15); font.bold: true }
                        SettingsActionRow {
                            width: parent.width
                            title: "Perfil visual"
                            subtitle: app.performanceAutomaticV90
                                      ? "Según este dispositivo"
                                      : (flowPerformanceLevel <= 0 ? "Ahorro y máxima compatibilidad"
                                         : (flowPerformanceLevel >= 2 ? "Alta fluidez" : "Equilibrado"))
                            iconName: "nav.settings"
                            trailingText: app.performanceAutomaticV90
                                          ? "Auto · " + app.performanceLevelNameV90(flowPerformanceLevel)
                                          : app.performanceLevelNameV90(flowPerformanceLevel)
                            onClicked: {
                                app.cyclePerformanceLevelV90()
                                showToast(app.performanceAutomaticV90
                                          ? "Perfil automático: " + app.performanceLevelNameV90(flowPerformanceLevel)
                                          : (flowPerformanceLevel <= 0 ? "Perfil de ahorro"
                                             : (flowPerformanceLevel >= 2 ? "Rendimiento alto" : "Rendimiento equilibrado")))
                            }
                        }
                    }
                }

                FlowCore.FlowGlassSurface {
                    width: parent.width; height: 118; radius: 24
                    flow: inGeCoreFlow; darkMode: app.darkMode
                    materialRole: "regular"
                    strength: 0.96
                    elevationEnabled: liquidGlass
                    blurSource: settingsBackdropV70
                    Column {
                        anchors.fill: parent; anchors.margins: 14; spacing: 0
                        Text { height: 30; text: "Seguridad"; color: textColor(); font.pixelSize: settingsRoot.f(15); font.bold: true }
                        SettingsActionRow {
                            width: parent.width
                            title: "Ingreso biométrico"
                            subtitle: biometricStatusV70
                            iconName: "security.biometric"
                            trailingText: "Configurar"
                            onClicked: {
                                if (!loggedIn) {
                                    showToast("Inicia sesión para configurar biometría")
                                    return
                                }
                                setFlutterSecuritySurfaceV70(true)
                            }
                        }
                    }
                }

                FlowCore.FlowGlassSurface {
                    width: parent.width; height: 118; radius: 24
                    flow: inGeCoreFlow; darkMode: app.darkMode
                    materialRole: "regular"
                    strength: 0.96
                    elevationEnabled: liquidGlass
                    blurSource: settingsBackdropV70
                    Column {
                        anchors.fill: parent; anchors.margins: 14; spacing: 0
                        Text { height: 30; text: "Sincronización"; color: textColor(); font.pixelSize: settingsRoot.f(15); font.bold: true }
                        SettingsActionRow {
                            width: parent.width; title: "Estado de datos"
                            subtitle: renditionPendingCountV60() > 0
                                      ? renditionPendingCountV60() + " cambios pendientes"
                                      : "Datos locales al día"
                            iconName: serverConnected ? "status.online" : "status.offline"
                            trailingText: renditionPendingCountV60() > 0 ? "Sincronizar" : "Al día"
                            onClicked: dispatchGlobalSyncV60()
                        }
                    }
                }

                FlowCore.FlowGlassSurface {
                    width: parent.width; height: 232; radius: 24
                    flow: inGeCoreFlow; darkMode: app.darkMode
                    materialRole: "regular"
                    strength: 0.96
                    elevationEnabled: liquidGlass
                    blurSource: settingsBackdropV70
                    Column {
                        anchors.fill: parent; anchors.margins: 14; spacing: 0
                        Text { height: 30; text: "Cuenta y datos"; color: textColor(); font.pixelSize: settingsRoot.f(15); font.bold: true }
                        SettingsActionRow {
                            width: parent.width; title: "Perfil"; subtitle: accountNameV18()
                            iconName: "profile.user"; trailingText: "Abrir"
                            onClicked: openProfileOverlayV18()
                        }
                        Rectangle { width: parent.width; height: 1; color: borderColor() }
                        SettingsActionRow {
                            // INGE_DRIVE_ONLY_HIDE_LEGACY_DOCS
                            visible: false
                            enabled: false

                            width: parent.width; title: "Documentos"; subtitle: "Archivos locales y nube"
                            iconName: "nav.documents"; trailingText: "Gestionar"
                            onClicked: navigateToPage(3)
                        }
                        Rectangle { width: parent.width; height: 1; color: borderColor() }
                        SettingsActionRow {
                            width: parent.width; title: "Cerrar sesión"
                            subtitle: "Finaliza la cuenta actual de forma segura"
                            iconName: "system.close"; trailingText: "Salir"
                            accentColor: inGeCoreFlow.theme.error
                            onClicked: performLogoutV18()
                        }
                    }
                }

                FlowCore.FlowGlassSurface {
                    width: parent.width; height: 118; radius: 24
                    flow: inGeCoreFlow; darkMode: app.darkMode
                    materialRole: "regular"
                    strength: 0.96
                    elevationEnabled: liquidGlass
                    blurSource: settingsBackdropV70
                    Column {
                        anchors.fill: parent; anchors.margins: 14; spacing: 0
                        Text { height: 30; text: "Privacidad"; color: textColor(); font.pixelSize: settingsRoot.f(15); font.bold: true }
                        SettingsActionRow {
                            width: parent.width; title: "Privacidad y permisos"
                            subtitle: "Cámara, ubicación y archivos en Android"
                            iconName: "security.account"; trailingText: "Abrir"
                            onClicked: {
                                var opened = false
                                try { opened = Perms.openApplicationSettings() } catch(e) {}
                                if (!opened) showToast("No se pudieron abrir los ajustes de Android")
                            }
                        }
                    }
                }

                FlowCore.FlowGlassSurface {
                    width: parent.width; height: 118; radius: 24
                    flow: inGeCoreFlow; darkMode: app.darkMode
                    materialRole: "clear"
                    strength: 0.92
                    elevationEnabled: liquidGlass
                    blurSource: settingsBackdropV70
                    Column {
                        anchors.fill: parent; anchors.margins: 14; spacing: 0
                        Text { height: 30; text: "Información"; color: textColor(); font.pixelSize: settingsRoot.f(15); font.bold: true }
                        SettingsActionRow {
                            width: parent.width; title: "InGe+ para Android"; subtitle: "Versión 1.0.0 · Qt 6.9.3"
                            iconName: "module.calicatas"; trailingText: "Acerca de"
                            onClicked: showToast("InGe+ 1.0.0 para Android")
                        }
                    }
                }

                Item {
                    width: parent.width
                    height: app.safeBottomInsetV49
                }
            }
        }
    }
}

Component {
    id: renditionPage

    Item {
        id: flutterRenditionsRootV70
        anchors.fill: parent

        function syncFlutterRenditionsV70() {
            var visible = app.pageIndex === 6
                    && (app.loggedIn || app.guestMode)
                    && !authView.visible
                    && !app.profileOverlayOpenV18
                    && !globalSearchOverlayV30.presented
                    && !quickBubbleV32.presented
            try {
                app.syncFlutterAuthStateV70(false)
                Perms.setFlutterRenditionsVisible(
                            visible,
                            app.darkMode ? "dark" : "light",
                            inGeCoreFlow.motionAllowed ? 1.0 : 0.0,
                            app.liquidGlass ? 0.72 : 0.0,
                            String(inGeCoreFlow.performance.profile))
            } catch (error) {
                console.warn("[InGe+ Renditions] Flutter host no disponible:", error)
            }
        }

        Component.onCompleted: Qt.callLater(syncFlutterRenditionsV70)
        Component.onDestruction: {
            try {
                Perms.setFlutterRenditionsVisible(
                            false, "light", 1.0, 0.0, "balanced")
            } catch (error) {}
        }

        Connections {
            target: app
            function onPageIndexChanged() {
                flutterRenditionsRootV70.syncFlutterRenditionsV70()
            }
            function onDarkModeChanged() {
                flutterRenditionsRootV70.syncFlutterRenditionsV70()
            }
            function onLiquidGlassChanged() {
                flutterRenditionsRootV70.syncFlutterRenditionsV70()
            }
            function onProfileOverlayOpenV18Changed() {
                flutterRenditionsRootV70.syncFlutterRenditionsV70()
            }
            function onEffectivePerformanceLevelV90Changed() {
                Qt.callLater(flutterRenditionsRootV70.syncFlutterRenditionsV70)
            }
        }

        Connections {
            target: authView
            function onVisibleChanged() {
                flutterRenditionsRootV70.syncFlutterRenditionsV70()
            }
        }

        Connections {
            target: globalSearchOverlayV30
            function onPresentedChanged() {
                flutterRenditionsRootV70.syncFlutterRenditionsV70()
            }
        }

        Connections {
            target: quickBubbleV32
            function onPresentedChanged() {
                flutterRenditionsRootV70.syncFlutterRenditionsV70()
            }
        }

        Rectangle {
            anchors.fill: parent
            color: inGeCoreFlow.theme.background
        }
    }
}

// M01_LIMPIEZA_PERFIL_V25: perfil duplicado eliminado.

Component {
    id: inventoryPage
    Item {
        anchors.fill: parent

        Flickable {
            anchors.fill: parent
            clip: true
            interactive: true
            flickableDirection: Flickable.VerticalFlick
            pressDelay: inGeCoreFlow.touchPressDelay
            flickDeceleration: inGeCoreFlow.flickDeceleration
            maximumFlickVelocity: inGeCoreFlow.scrollVelocity(contentHeight, height)
            boundsBehavior: inGeCoreFlow.motionAllowed
                            ? Flickable.DragAndOvershootBounds
                            : Flickable.StopAtBounds
            contentWidth: width
            contentHeight: invCol.height + 32

            Column {
                id: invCol
                width: parent.width
                spacing: 14
                padding: 16

                Text { text: "Inventario"; color: textColor(); font.pixelSize: fs(24); font.bold: true }

                Rectangle {
                    width: parent.width - 32
                    height: 190
                    radius: 22
                    color: cardColor()
                    border.color: borderColor()

                    Column {
                        anchors.fill: parent
                        anchors.margins: 18
                        spacing: 10
                        Components.FlowIcon {
                            width: 54; height: 54
                            name: "documents.folder"
                            flow: inGeCoreFlow
                            active: true
                            tintColor: primaryColor()
                            activeTintColor: primaryColor()
                            inactiveOpacity: 1.0
                        }
                        Text { text: "Próximamente"; color: primaryColor(); font.pixelSize: fs(24); font.bold: true }
                        Text { width: parent.width; text: "Reservado para una siguiente versión. La 1.0.2 prioriza Fichas, Mapa, GPS, Fotos, Servidor y Excel."; color: mutedColor(); font.pixelSize: fs(13); wrapMode: Text.WordWrap }
                    }
                }

                SecondaryButton { width: parent.width - 32; label: "Volver a Inicio"; onClicked: navigateToPage(0) }
            }
        }
    }
}




Rectangle {
    id: flowToast
    visible: opacity > 0.01
    z: 200
    width: Math.min(parent.width - 40, 370)
    height: 52
    radius: 18
    color: app.liquidGlass
           ? inGeCoreFlow.theme.surfaceOverlay
           : inGeCoreFlow.theme.surfaceElevated
    border.color: inGeCoreFlow.theme.border
    border.width: 1
    opacity: toastText.length > 0 ? 1.0 : 0.0
    scale: toastText.length > 0 ? 1.0 : 0.94
    anchors.horizontalCenter: parent.horizontalCenter
    anchors.bottom: parent.bottom
    anchors.bottomMargin: (loggedIn || guestMode)
                          ? app.safeBottomInsetV49
                          : inGeCoreFlow.spacing.xl
    property real toastShift: toastText.length > 0 ? 0.0 : 16.0
    transformOrigin: Item.Center
    transform: Translate { y: flowToast.toastShift }

    Behavior on opacity { NumberAnimation { duration: inGeCoreFlow.normalDuration; easing.type: inGeCoreFlow.easeOut } }
    Behavior on scale { NumberAnimation { duration: inGeCoreFlow.normalDuration; easing.type: inGeCoreFlow.easeEmphasized } }
    Behavior on toastShift { NumberAnimation { duration: inGeCoreFlow.normalDuration; easing.type: inGeCoreFlow.easeEmphasized } }

    Text {
        anchors.centerIn: parent
        width: parent.width - 20
        text: toastText
        color: app.darkMode || app.liquidGlass
               ? inGeCoreFlow.theme.textPrimary
                : inGeCoreFlow.theme.textPrimary
        font.pixelSize: fs(12)
        horizontalAlignment: Text.AlignHCenter
        elide: Text.ElideRight
    }
}

Item {
    id: flowSuccessOverlay
    anchors.fill: parent
    z: 600
    visible: flowSuccessVisible || opacity > 0.01
    opacity: 0.0
    enabled: false

    Rectangle {
        id: flowSuccessCard
        width: Math.min(parent.width - 72, 280)
        height: 168
        radius: 28
        color: inGeCoreFlow.theme.surfaceElevated
        border.color: inGeCoreFlow.theme.border
        border.width: 1
        anchors.centerIn: parent
        scale: 0.72
        transformOrigin: Item.Center

        Rectangle {
            id: flowSuccessHalo
            width: 92
            height: 92
            radius: 46
            anchors.horizontalCenter: parent.horizontalCenter
            y: 20
            color: inGeCoreFlow.theme.successContainer
            border.color: inGeCoreFlow.theme.success
            border.width: 2
            scale: 0.45

            Components.FlowIcon {
                anchors.centerIn: parent
                width: 52
                height: 52
                name: "system.check"
                flow: inGeCoreFlow
                active: flowSuccessVisible
                tintColor: inGeCoreFlow.theme.success
                activeTintColor: inGeCoreFlow.theme.success
                inactiveOpacity: 1.0
            }
        }

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 22
            width: parent.width - 28
            text: flowSuccessText
            color: inGeCoreFlow.theme.textPrimary
            font.pixelSize: fs(15)
            font.bold: true
            horizontalAlignment: Text.AlignHCenter
            elide: Text.ElideRight
        }
    }

    SequentialAnimation {
        id: flowSuccessSequence
        running: false

        ScriptAction {
            script: {
                flowSuccessOverlay.opacity = 0.0
                flowSuccessCard.scale = 0.72
                flowSuccessHalo.scale = 0.45
            }
        }
        ParallelAnimation {
            NumberAnimation { target: flowSuccessOverlay; property: "opacity"; to: 1.0; duration: inGeCoreFlow.normalDuration; easing.type: inGeCoreFlow.easeOut }
            NumberAnimation { target: flowSuccessCard; property: "scale"; to: 1.0; duration: inGeCoreFlow.successDuration; easing.type: inGeCoreFlow.easeOvershoot }
            NumberAnimation { target: flowSuccessHalo; property: "scale"; to: 1.0; duration: inGeCoreFlow.successDuration; easing.type: inGeCoreFlow.easeOvershoot }
        }
        PauseAnimation { duration: inGeCoreFlow.successHoldDuration }
        ParallelAnimation {
            NumberAnimation { target: flowSuccessOverlay; property: "opacity"; to: 0.0; duration: inGeCoreFlow.normalDuration; easing.type: inGeCoreFlow.easeIn }
            NumberAnimation { target: flowSuccessCard; property: "scale"; to: 0.96; duration: inGeCoreFlow.normalDuration; easing.type: inGeCoreFlow.easeIn }
        }
        ScriptAction { script: flowSuccessVisible = false }
    }
}

component AuthInlineField: Item {
    id: inlineRoot
    property alias text: inlineInput.text
    property alias placeholderText: inlineInput.placeholderText
    property alias inputMethodHints: inlineInput.inputMethodHints
    property url iconSource: ""
    property url trailingIconSource: ""
    property bool passwordField: false
    property bool passwordVisible: false
    property int enterKeyType: Qt.EnterKeyDefault
    signal accepted()
    function forceInputFocus() { inlineInput.forceActiveFocus() }
    height: 58
    scale: inlineInput.activeFocus ? inGeCoreFlow.focusScale : 1.0
    transformOrigin: Item.Center
    Behavior on scale { NumberAnimation { duration: inGeCoreFlow.normalDuration; easing.type: inGeCoreFlow.easeOut } }

    Rectangle {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        height: inlineInput.activeFocus ? 2 : 0
        color: app.primaryColor()
        Behavior on height { NumberAnimation { duration: inGeCoreFlow.fastDuration; easing.type: inGeCoreFlow.easeOut } }
    }

    Row {
        anchors.fill: parent
        spacing: 14

        Image {
            width: 25
            height: 25
            anchors.verticalCenter: parent.verticalCenter
            source: inlineRoot.iconSource
            fillMode: Image.PreserveAspectFit
            smooth: true
        }

        TextField {
            id: inlineInput
            anchors.verticalCenter: parent.verticalCenter
            height: parent.height
            width: parent.width - 96
            color: inGeCoreFlow.theme.textPrimary
            placeholderTextColor: inGeCoreFlow.theme.textTertiary
            font.pixelSize: fs(16)
            echoMode: inlineRoot.passwordField && !inlineRoot.passwordVisible ? TextInput.Password : TextInput.Normal
            background: Item {}
            leftPadding: 0
            rightPadding: 0
            verticalAlignment: TextInput.AlignVCenter
            EnterKey.type: inlineRoot.enterKeyType
            onAccepted: inlineRoot.accepted()
        }

        Item {
            width: inlineRoot.passwordField ? 36 : 0
            height: 36
            anchors.verticalCenter: parent.verticalCenter
            visible: inlineRoot.passwordField

            Image {
                anchors.centerIn: parent
                width: 25
                height: 25
                source: inlineRoot.trailingIconSource
                fillMode: Image.PreserveAspectFit
                smooth: true
            }

            MouseArea {
                anchors.fill: parent
                onClicked: inlineRoot.passwordVisible = !inlineRoot.passwordVisible
            }
        }
    }
}

component LoginField: Item {
    id: loginFieldRoot
    property alias text: input.text
    property alias placeholderText: input.placeholderText
    property alias inputMethodHints: input.inputMethodHints
    property alias maximumLength: input.maximumLength
    property url leadingIconSource: ""
    property bool passwordField: false
    property bool revealPassword: false
    property int enterKeyType: Qt.EnterKeyDefault
    signal accepted()
    function forceInputFocus() { input.forceActiveFocus() }
    width: 200
    height: 58

    Rectangle {
        anchors.fill: parent
        color: inGeCoreFlow.theme.surfaceElevated
        radius: 18
        border.color: input.activeFocus ? inGeCoreFlow.theme.focus : inGeCoreFlow.theme.border
        border.width: 1
    }

    Row {
        anchors.fill: parent
        anchors.leftMargin: 16
        anchors.rightMargin: 16
        spacing: 12

        Image {
            anchors.verticalCenter: parent.verticalCenter
            width: 22
            height: 22
            source: leadingIconSource
            visible: source.toString().length > 0
            fillMode: Image.PreserveAspectFit
            smooth: true
        }

        TextField {
            id: input
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width - (leadingIconSource.toString().length > 0 ? 58 : 24) - (passwordField ? 36 : 0)
            height: parent.height
            color: inGeCoreFlow.theme.textPrimary
            placeholderTextColor: inGeCoreFlow.theme.textTertiary
            echoMode: loginFieldRoot.passwordField && !loginFieldRoot.revealPassword ? TextInput.Password : TextInput.Normal
            background: Item {}
            leftPadding: 0
            rightPadding: 0
            font.pixelSize: fs(13)
            verticalAlignment: TextInput.AlignVCenter
            EnterKey.type: loginFieldRoot.enterKeyType
            onAccepted: loginFieldRoot.accepted()
        }

        Item {
            anchors.verticalCenter: parent.verticalCenter
            width: passwordField ? 28 : 0
            height: 28
            visible: passwordField
            Image {
                anchors.centerIn: parent
                width: 22
                height: 22
                source: loginFieldRoot.revealPassword ? "qrc:/ui/v2/icons/auth/ic_auth_eye_off.svg" : "qrc:/ui/v2/icons/auth/ic_auth_eye.svg"
                fillMode: Image.PreserveAspectFit
            }
            MouseArea {
                anchors.fill: parent
                onClicked: loginFieldRoot.revealPassword = !loginFieldRoot.revealPassword
            }
        }
    }
}

component InputBox: TextField {
    id: inputBoxRoot
    height: 54
    color: inGeCoreFlow.theme.textPrimary
    scale: activeFocus ? inGeCoreFlow.focusScale : 1.0
    Behavior on scale { NumberAnimation { duration: inGeCoreFlow.normalDuration; easing.type: inGeCoreFlow.easeOut } }
    placeholderTextColor: inGeCoreFlow.theme.textTertiary
    background: Rectangle {
        color: inGeCoreFlow.theme.field
        border.color: inputBoxRoot.activeFocus ? app.primaryColor() : app.borderColor()
        border.width: inputBoxRoot.activeFocus ? 2 : 1
        radius: 10
        Behavior on border.color { ColorAnimation { duration: inGeCoreFlow.fastDuration } }
    }
    leftPadding: 14
    rightPadding: 14
}

component AreaBox: TextArea {
    id: areaBoxRoot
    color: inGeCoreFlow.theme.textPrimary
    scale: activeFocus ? inGeCoreFlow.focusScale : 1.0
    Behavior on scale { NumberAnimation { duration: inGeCoreFlow.normalDuration; easing.type: inGeCoreFlow.easeOut } }
    placeholderTextColor: inGeCoreFlow.theme.textTertiary
    wrapMode: TextEdit.Wrap
    background: Rectangle {
        color: inGeCoreFlow.theme.field
        border.color: areaBoxRoot.activeFocus ? app.primaryColor() : app.borderColor()
        border.width: areaBoxRoot.activeFocus ? 2 : 1
        radius: 10
        Behavior on border.color { ColorAnimation { duration: inGeCoreFlow.fastDuration } }
    }
    leftPadding: 12
    rightPadding: 12
    topPadding: 10
    bottomPadding: 10
}

component PrimaryButton: Rectangle {
    id: primaryRoot
    property string label: ""
    property url iconSource: ""
    signal clicked()
    height: 54
    radius: 12
    color: primaryMouse.pressed ? Qt.darker(inGeCoreFlow.theme.actionPrimary, 1.12) : inGeCoreFlow.theme.actionPrimary
    scale: primaryMouse.pressed ? inGeCoreFlow.pressScale : 1.0
    transformOrigin: Item.Center

    Behavior on scale {
        NumberAnimation { duration: inGeCoreFlow.fastDuration; easing.type: inGeCoreFlow.easeOut }
    }
    Behavior on color { ColorAnimation { duration: inGeCoreFlow.fastDuration } }

    Row { anchors.centerIn: parent; spacing: 8
        Image { width: 24; height: 24; source: iconSource; visible: iconSource.toString().length > 0; fillMode: Image.PreserveAspectFit; smooth: true }
        Text { text: label; color: inGeCoreFlow.theme.onActionPrimary; font.bold: true; font.pixelSize: fs(14) }
    }
    FlowCore.FlowRipple {
        id: primaryMouseRipple
        flow: inGeCoreFlow
        rippleColor: "#55FFFFFF"
        enabled: inGeCoreFlow.motionAllowed
    }
    MouseArea {
        id: primaryMouse
        anchors.fill: parent
        hoverEnabled: true
        onPressed: function(mouse) { primaryMouseRipple.trigger(mouse.x, mouse.y) }
        onClicked: primaryRoot.clicked()
    }
}

component SecondaryButton: Rectangle {
    id: secondaryRoot
    property string label: ""
    property url iconSource: ""
    signal clicked()
    height: 54
    radius: 12
    color: secondaryMouse.pressed
           ? inGeCoreFlow.theme.pressed
           : app.card2Color()
    border.color: app.borderColor()
    scale: secondaryMouse.pressed ? inGeCoreFlow.pressScale : 1.0
    transformOrigin: Item.Center

    Behavior on scale {
        NumberAnimation { duration: inGeCoreFlow.fastDuration; easing.type: inGeCoreFlow.easeOut }
    }
    Behavior on color { ColorAnimation { duration: inGeCoreFlow.fastDuration } }

    Row { anchors.centerIn: parent; spacing: 8
        Image { width: 24; height: 24; source: iconSource; visible: iconSource.toString().length > 0; fillMode: Image.PreserveAspectFit; smooth: true }
        Text { text: label; color: app.textColor(); font.bold: true; font.pixelSize: fs(14) }
    }
    FlowCore.FlowRipple {
        id: secondaryMouseRipple
        flow: inGeCoreFlow
        rippleColor: inGeCoreFlow.rippleLight
        enabled: inGeCoreFlow.motionAllowed
    }
    MouseArea {
        id: secondaryMouse
        anchors.fill: parent
        hoverEnabled: true
        onPressed: function(mouse) { secondaryMouseRipple.trigger(mouse.x, mouse.y) }
        onClicked: secondaryRoot.clicked()
    }
}

component GhostButton: Rectangle {
    id: ghostRoot
    property string label: ""
    property url iconSource: ""
    signal clicked()
    height: 54
    radius: 12
    color: ghostMouse.pressed ? inGeCoreFlow.theme.selected : "transparent"
    border.color: app.primaryColor()
    scale: ghostMouse.pressed ? inGeCoreFlow.pressScale : 1.0
    transformOrigin: Item.Center

    Behavior on scale {
        NumberAnimation { duration: inGeCoreFlow.fastDuration; easing.type: inGeCoreFlow.easeOut }
    }
    Behavior on color { ColorAnimation { duration: inGeCoreFlow.fastDuration } }

    Row {
        anchors.centerIn: parent
        spacing: 8
        Image { width: 22; height: 22; source: iconSource; visible: iconSource.toString().length > 0; fillMode: Image.PreserveAspectFit; smooth: true }
        Text { text: label; color: app.primaryColor(); font.bold: true; font.pixelSize: fs(14) }
    }
    FlowCore.FlowRipple {
        id: ghostMouseRipple
        flow: inGeCoreFlow
        rippleColor: inGeCoreFlow.rippleLight
        enabled: inGeCoreFlow.motionAllowed
    }
    MouseArea {
        id: ghostMouse
        anchors.fill: parent
        hoverEnabled: true
        onPressed: function(mouse) { ghostMouseRipple.trigger(mouse.x, mouse.y) }
        onClicked: ghostRoot.clicked()
    }
}

component HeaderGlassIconButton: FlowCore.FlowGlassSurface {
    id: headerGlassButtonRoot
    property string iconName: "nav.settings"
    property string accessibleName: iconName
    property Item materialSource: null
    signal clicked()

    implicitWidth: 50
    implicitHeight: 50
    flow: inGeCoreFlow
    darkMode: app.darkMode
    materialRole: "clear"
    strength: 0.94
    blurSource: materialSource
    blurAmount: 0.42
    elevationEnabled: app.liquidGlass
    radius: height / 2
    fallbackLight: inGeCoreFlow.theme.surfaceElevated
    fallbackDark: inGeCoreFlow.theme.surfaceElevated
    Accessible.name: accessibleName
    Accessible.role: Accessible.Button

    Components.FlowIconButton {
        anchors.fill: parent
        iconName: headerGlassButtonRoot.iconName
        flow: inGeCoreFlow
        variant: inGeCoreFlow.variant.buttonIcon
        iconSize: 24
        iconColor: inGeCoreFlow.theme.textPrimary
        selectedIconColor: inGeCoreFlow.theme.accent
        idleColor: "transparent"
        pressedColor: inGeCoreFlow.theme.pressed
        cornerRadius: parent.radius
        border.width: 0
        border.color: "transparent"
        onClicked: headerGlassButtonRoot.clicked()
    }
}

component SettingsActionRow: Item {
    id: settingsActionRoot
    property string title: ""
    property string subtitle: ""
    property string iconName: "nav.settings"
    property string trailingText: ""
    property color accentColor: primaryColor()
    property bool showSwitch: false
    property bool checked: false
    signal clicked()

    height: 57

    FlowCore.FlowGlassSurface {
        anchors.fill: parent
        anchors.margins: -6
        radius: 12
        flow: inGeCoreFlow
        darkMode: app.darkMode
        materialRole: "clear"
        pressed: true
        blurEnabled: false
        elevationEnabled: false
        fallbackLight: inGeCoreFlow.theme.pressed
        fallbackDark: inGeCoreFlow.theme.pressed
        opacity: settingsActionMouse.pressed ? 1.0 : 0.0
        visible: opacity > 0.001

        Behavior on opacity {
            NumberAnimation { duration: inGeCoreFlow.fastDuration }
        }
    }

    Rectangle {
        x: 0; width: 34; height: 34; radius: 11
        anchors.verticalCenter: parent.verticalCenter
        color: Qt.rgba(settingsActionRoot.accentColor.r,
                       settingsActionRoot.accentColor.g,
                       settingsActionRoot.accentColor.b,
                       darkMode ? 0.18 : 0.10)
        Components.FlowIcon {
            anchors.centerIn: parent
            width: 18; height: 18
            name: settingsActionRoot.iconName
            flow: inGeCoreFlow
            active: true
            tintColor: settingsActionRoot.accentColor
            activeTintColor: settingsActionRoot.accentColor
        }
    }

    Column {
        x: 46
        width: parent.width - 46 - (settingsActionRoot.showSwitch ? 52 : 82)
        anchors.verticalCenter: parent.verticalCenter
        spacing: 2
        Text { width: parent.width; text: settingsActionRoot.title; color: textColor(); font.pixelSize: fs(12); font.bold: true; elide: Text.ElideRight }
        Text { width: parent.width; text: settingsActionRoot.subtitle; color: mutedColor(); font.pixelSize: fs(9); elide: Text.ElideRight }
    }

    Rectangle {
        visible: settingsActionRoot.showSwitch
        width: 43; height: 24; radius: 12
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        color: settingsActionRoot.checked ? primaryColor() : inGeCoreFlow.theme.field
        border.color: settingsActionRoot.checked ? primaryColor() : borderColor()
        Rectangle {
            width: 18; height: 18; radius: 9
            y: 3
            x: settingsActionRoot.checked ? parent.width - width - 3 : 3
            color: "#FFFFFF"
            Behavior on x { NumberAnimation { duration: inGeCoreFlow.fastDuration; easing.type: inGeCoreFlow.easeOut } }
        }
    }

    Row {
        visible: !settingsActionRoot.showSwitch
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        spacing: 5
        Text { text: settingsActionRoot.trailingText; color: settingsActionRoot.accentColor; font.pixelSize: fs(9); font.bold: true; anchors.verticalCenter: parent.verticalCenter }
        Components.FlowIcon { width: 15; height: 15; name: "system.chevronRight"; flow: inGeCoreFlow; active: true; anchors.verticalCenter: parent.verticalCenter }
    }

    MouseArea { id: settingsActionMouse; anchors.fill: parent; onClicked: settingsActionRoot.clicked() }
}

component HomeQuickAction: Rectangle {
    id: quickActionRoot
    property string label: "Acción"
    property string subtitle: ""
    property string iconKey: "action.add"
    property color accentColor: inGeCoreFlow.theme.accent
    signal clicked()

    height: 100
    radius: 16
    color: quickActionMouse.pressed
           ? inGeCoreFlow.theme.pressed
           : cardColor()
    border.color: borderColor()
    border.width: 1
    scale: quickActionMouse.pressed ? inGeCoreFlow.cardPressScale : 1.0

    Behavior on color { ColorAnimation { duration: inGeCoreFlow.fastDuration } }
    Behavior on scale { NumberAnimation { duration: inGeCoreFlow.fastDuration; easing.type: inGeCoreFlow.easeOut } }

    Column {
        anchors.fill: parent
        anchors.margins: 10
        spacing: 5

        Components.FlowIcon {
            width: 28
            height: 28
            anchors.horizontalCenter: parent.horizontalCenter
            name: quickActionRoot.iconKey
            flow: inGeCoreFlow
            tintEnabled: true
            tintColor: quickActionRoot.accentColor
            activeTintColor: quickActionRoot.accentColor
            inactiveOpacity: 1.0
        }
        Text {
            width: parent.width
            text: quickActionRoot.label
            color: textColor()
            font.pixelSize: fs(10)
            font.bold: true
            horizontalAlignment: Text.AlignHCenter
            elide: Text.ElideRight
        }
        Text {
            width: parent.width
            text: quickActionRoot.subtitle
            color: mutedColor()
            font.pixelSize: fs(8)
            horizontalAlignment: Text.AlignHCenter
            elide: Text.ElideRight
        }
    }

    MouseArea {
        id: quickActionMouse
        anchors.fill: parent
        onClicked: {
            inGeCoreFlow.triggerHaptic("selection")
            quickActionRoot.clicked()
        }
    }
}

component StatCard: Rectangle {
    property string label: ""
    property string value: ""
    property string sub: ""
    property string iconName: ""
    height: 88
    radius: 15
    color: cardColor()
    border.color: borderColor()

    Row {
        anchors.fill: parent
        anchors.margins: 10
        spacing: 10
        Components.FlowIcon {
            width: 34; height: 34
            anchors.verticalCenter: parent.verticalCenter
            name: iconName
            flow: inGeCoreFlow
            tintColor: primaryColor()
            inactiveOpacity: 1.0
        }
        Column {
            anchors.verticalCenter: parent.verticalCenter
            Text { text: label; color: mutedColor(); font.pixelSize: fs(12) }
            Text { text: value; color: textColor(); font.pixelSize: fs(20); font.bold: true }
            Text { text: sub; color: mutedColor(); font.pixelSize: fs(10); width: 100; elide: Text.ElideRight }
        }
    }
}


component AssistantCard: Rectangle {
    height: 110
    radius: 18
    color: card2Color()
    border.color: borderColor()

    Row {
        anchors.fill: parent
        anchors.margins: 12
        spacing: 10
        Components.FlowIcon {
            width: 34; height: 34
            anchors.verticalCenter: parent.verticalCenter
            name: "security.biometric"
            flow: inGeCoreFlow
            active: true
            tintColor: primaryColor()
            activeTintColor: primaryColor()
            inactiveOpacity: 1.0
        }
        Text { width: parent.width - 52; text: assistantText; color: mutedColor(); font.pixelSize: fs(12); wrapMode: Text.WordWrap; anchors.verticalCenter: parent.verticalCenter }
    }
}




component ModuleCardV2: Rectangle {
    id: moduleRoot

    property string title: ""
    property string subtitle: ""
    property string actionLabel: "Abrir módulo"
    property string iconName: ""
    property url imageSource: ""
    property color accent: inGeCoreFlow.colors.ingemaBlue
    property bool featured: false
    property bool moduleAvailable: true
    property string statusLabel: moduleAvailable ? "Disponible" : "Próximamente"
    property real revealProgress: 1.0
    property real rippleCenterX: width / 2
    property real rippleCenterY: height / 2

    signal clicked()

    height: featured ? 162 : 92
    radius: featured ? 20 : 16
    color: moduleMouse.pressed && moduleAvailable
           ? inGeCoreFlow.theme.pressed
           : cardColor()
    border.color: borderColor()
    border.width: 1
    clip: true
    opacity: revealProgress

    readonly property real revealScale:
        inGeCoreFlow.revealStartScale
        + (1.0 - inGeCoreFlow.revealStartScale) * revealProgress

    scale: moduleMouse.pressed && moduleAvailable
           ? inGeCoreFlow.cardPressScale
           : 1.0
    transformOrigin: Item.Center

    transform: [
        Translate {
            y: (1.0 - moduleRoot.revealProgress)
               * inGeCoreFlow.cardRevealOffset
        },
        Scale {
            origin.x: moduleRoot.width / 2
            origin.y: moduleRoot.height / 2
            xScale: moduleRoot.revealScale
            yScale: moduleRoot.revealScale
        }
    ]

    Behavior on color {
        ColorAnimation {
            duration: inGeCoreFlow.fastDuration
        }
    }

    Behavior on scale {
        NumberAnimation {
            duration: inGeCoreFlow.fastDuration
            easing.type: inGeCoreFlow.easeOut
        }
    }

    Rectangle {
        anchors.left: parent.left
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        width: moduleAvailable ? 3 : 0
        color: moduleAvailable
               ? moduleRoot.accent
               : inGeCoreFlow.theme.textDisabled
    }

    Rectangle {
        id: moduleRipple
        z: 0
        width: 0
        height: width
        radius: width / 2
        x: moduleRoot.rippleCenterX - width / 2
        y: moduleRoot.rippleCenterY - height / 2
        color: Qt.rgba(0.02, 0.33, 0.64, 0.16)
        opacity: 0.0
    }

    ParallelAnimation {
        id: moduleRippleAnimation

        NumberAnimation {
            target: moduleRipple
            property: "width"
            from: 0
            to: Math.max(moduleRoot.width, moduleRoot.height) * 2.2
            duration: inGeCoreFlow.rippleDuration
            easing.type: inGeCoreFlow.easeOut
        }

        SequentialAnimation {
            NumberAnimation {
                target: moduleRipple
                property: "opacity"
                from: 0.0
                to: 1.0
                duration: inGeCoreFlow.fastDuration
            }
            NumberAnimation {
                target: moduleRipple
                property: "opacity"
                from: 1.0
                to: 0.0
                duration: inGeCoreFlow.rippleFadeDuration
            }
        }
    }

    RowLayout {
        z: 1
        visible: moduleRoot.featured
        anchors.fill: parent
        anchors.leftMargin: 17
        anchors.rightMargin: 14
        anchors.topMargin: 14
        anchors.bottomMargin: 14
        spacing: 12

        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 7

            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                Rectangle {
                    Layout.preferredWidth: 42
                    Layout.preferredHeight: 42
                    radius: 13
                    color: moduleRoot.accent

                    Components.FlowIcon {
                        anchors.centerIn: parent
                        width: 27
                        height: 27
                        name: moduleRoot.iconName
                        flow: inGeCoreFlow
                        active: moduleRoot.moduleAvailable
                        tintEnabled: false
                        inactiveOpacity: 0.88
                    }
                }

                Item {
                    Layout.fillWidth: true
                }

                Rectangle {
                    Layout.preferredWidth: featuredStatusText.implicitWidth + 18
                    Layout.preferredHeight: 26
                    radius: 13
                    color: inGeCoreFlow.theme.successContainer
                    border.color: inGeCoreFlow.theme.success
                    border.width: 1

                    Text {
                        id: featuredStatusText
                        anchors.centerIn: parent
                        text: moduleRoot.statusLabel
                        color: inGeCoreFlow.theme.success
                        font.pixelSize: fs(9)
                        font.bold: true
                    }
                }
            }

            Text {
                Layout.fillWidth: true
                text: moduleRoot.title
                color: textColor()
                font.pixelSize: fs(20)
                font.bold: true
                maximumLineCount: 1
                elide: Text.ElideRight
            }

            Text {
                Layout.fillWidth: true
                text: moduleRoot.subtitle
                color: mutedColor()
                font.pixelSize: fs(11)
                wrapMode: Text.WordWrap
                maximumLineCount: 2
                elide: Text.ElideRight
            }

            Item {
                Layout.fillHeight: true
            }

            Text {
                Layout.fillWidth: true
                text: moduleRoot.actionLabel
                color: moduleRoot.accent
                font.pixelSize: fs(11)
                font.bold: true
            }
        }

        Image {
            Layout.preferredWidth: Math.min(128, moduleRoot.width * 0.34)
            Layout.preferredHeight: 128
            Layout.alignment: Qt.AlignVCenter
            source: moduleRoot.imageSource
            fillMode: Image.PreserveAspectFit
            smooth: true
            mipmap: false
        }
    }

    RowLayout {
        z: 1
        visible: !moduleRoot.featured
        anchors.fill: parent
        anchors.leftMargin: 17
        anchors.rightMargin: 14
        anchors.topMargin: 13
        anchors.bottomMargin: 13
        spacing: 12

        Rectangle {
            Layout.preferredWidth: 42
            Layout.preferredHeight: 42
            Layout.alignment: Qt.AlignVCenter
            radius: 12
            color: card2Color()

            Components.FlowIcon {
                anchors.centerIn: parent
                width: 26
                height: 26
                name: moduleRoot.iconName
                flow: inGeCoreFlow
                active: false
                tintEnabled: false
                inactiveOpacity: 0.82
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignVCenter
            spacing: 4

            Text {
                Layout.fillWidth: true
                text: moduleRoot.title
                color: textColor()
                font.pixelSize: fs(13)
                font.bold: true
                wrapMode: Text.WordWrap
                maximumLineCount: 2
                elide: Text.ElideRight
            }

            Text {
                Layout.fillWidth: true
                text: moduleRoot.subtitle
                color: mutedColor()
                font.pixelSize: fs(9)
                wrapMode: Text.WordWrap
                maximumLineCount: 2
                elide: Text.ElideRight
            }
        }

        Rectangle {
            Layout.preferredWidth: compactStatusText.implicitWidth + 16
            Layout.preferredHeight: 24
            Layout.alignment: Qt.AlignVCenter
            radius: 12.5
            color: moduleRoot.moduleAvailable
                   ? inGeCoreFlow.theme.successContainer
                   : inGeCoreFlow.theme.warningContainer
            border.color: moduleRoot.moduleAvailable
                          ? inGeCoreFlow.theme.success
                          : inGeCoreFlow.theme.warning
            border.width: 1

            Text {
                id: compactStatusText
                anchors.centerIn: parent
                text: moduleRoot.statusLabel
                color: moduleRoot.moduleAvailable
                       ? inGeCoreFlow.theme.success
                       : inGeCoreFlow.theme.warning
                font.pixelSize: fs(8)
                font.bold: true
            }
        }
    }

    MouseArea {
        id: moduleMouse
        z: 2
        anchors.fill: parent
        enabled: moduleRoot.moduleAvailable

        onPressed: function(mouse) {
            moduleRoot.rippleCenterX = mouse.x
            moduleRoot.rippleCenterY = mouse.y
            moduleRippleAnimation.restart()
        }

        onClicked: moduleRoot.clicked()
    }
}


component SectionTitle: Row {
    property string title: ""
    property url iconSource: ""
    height: 34
    spacing: 9
    Image { width: 30; height: 30; source: iconSource; fillMode: Image.PreserveAspectFit; smooth: true; anchors.verticalCenter: parent.verticalCenter }
    Text { text: title; color: app.textColor(); font.pixelSize: fs(17); font.bold: true; anchors.verticalCenter: parent.verticalCenter }
}

component LogoBox: Rectangle {
    id: logoBoxRoot
    property string title: ""
    property url imgSource: ""
    property url iconSource: ""
    signal clicked()
    height: 132
    radius: 16
    color: logoBoxMouse.pressed ? inGeCoreFlow.theme.pressed : cardColor()
    border.color: logoBoxMouse.pressed ? primaryColor() : borderColor()
    scale: logoBoxMouse.pressed ? inGeCoreFlow.cardPressScale : 1.0
    clip: true
    Behavior on scale { NumberAnimation { duration: inGeCoreFlow.fastDuration; easing.type: inGeCoreFlow.easeOut } }
    Behavior on color { ColorAnimation { duration: inGeCoreFlow.fastDuration } }
    Behavior on border.color { ColorAnimation { duration: inGeCoreFlow.fastDuration } }

    Column {
        anchors.fill: parent
        anchors.margins: 9
        spacing: 5
        Row { width: parent.width; height: 24; spacing: 5
            Image { width: 24; height: 24; source: iconSource; fillMode: Image.PreserveAspectFit; smooth: true }
            Text { text: title; color: textColor(); font.pixelSize: fs(11); font.bold: true; width: parent.width - 30; elide: Text.ElideRight; anchors.verticalCenter: parent.verticalCenter }
        }
        Rectangle { width: parent.width; height: 76; radius: 12; color: inGeCoreFlow.theme.surfacePrimary; border.color: app.borderColor(); clip: true
            Image { anchors.centerIn: parent; width: parent.width - 10; height: parent.height - 8; source: imgSource; fillMode: Image.PreserveAspectFit; smooth: true }
        }
    }
    FlowCore.FlowRipple { id: logoBoxRipple; flow: inGeCoreFlow; rippleColor: inGeCoreFlow.rippleLight; enabled: inGeCoreFlow.motionAllowed }
    MouseArea {
        id: logoBoxMouse
        anchors.fill: parent
        onPressed: function(mouse) { logoBoxRipple.trigger(mouse.x, mouse.y) }
        onClicked: logoBoxRoot.clicked()
    }
}

component PhotoBox: Rectangle {
    id: photoBoxRoot
    property string label: ""
    property url imgSource: ""
    property url iconSource: ""
    signal clicked()
    height: width
    radius: 14
    color: photoBoxMouse.pressed ? inGeCoreFlow.theme.pressed : card2Color()
    border.color: imgSource.toString().length > 0 ? greenColor() : borderColor()
    clip: true
    scale: photoBoxMouse.pressed ? inGeCoreFlow.cardPressScale : 1.0
    Behavior on scale { NumberAnimation { duration: inGeCoreFlow.fastDuration; easing.type: inGeCoreFlow.easeOut } }
    Behavior on color { ColorAnimation { duration: inGeCoreFlow.fastDuration } }

    Image {
        anchors.fill: parent
        source: imgSource.toString().length > 0 ? imgSource : ""
        fillMode: Image.PreserveAspectCrop
        visible: imgSource.toString().length > 0
        opacity: 0.9
    }

    Column {
        anchors.centerIn: parent
        spacing: 5
        Image { width: 36; height: 36; anchors.horizontalCenter: parent.horizontalCenter; source: iconSource.toString().length > 0 ? iconSource : propACalIcon("ic_cal_camera"); visible: imgSource.toString().length === 0; fillMode: Image.PreserveAspectFit; smooth: true }
        Text { text: label; color: imgSource.toString().length > 0 ? "white" : mutedColor(); font.pixelSize: fs(10); font.bold: true; anchors.horizontalCenter: parent.horizontalCenter }
    }
    FlowCore.FlowRipple { id: photoBoxRipple; flow: inGeCoreFlow; rippleColor: inGeCoreFlow.rippleLight; enabled: inGeCoreFlow.motionAllowed }
    MouseArea {
        id: photoBoxMouse
        anchors.fill: parent
        onPressed: function(mouse) { photoBoxRipple.trigger(mouse.x, mouse.y) }
        onClicked: photoBoxRoot.clicked()
    }
}

component MapChip: Rectangle {
    id: mapChipRoot
    property string label: ""
    signal clicked()
    height: 34
    radius: 10
    color: mapChipMouse.pressed ? Qt.darker(inGeCoreFlow.theme.actionPrimary, 1.12) : inGeCoreFlow.theme.actionPrimary
    scale: mapChipMouse.pressed ? inGeCoreFlow.pressScale : 1.0
    clip: true
    Behavior on scale { NumberAnimation { duration: inGeCoreFlow.fastDuration; easing.type: inGeCoreFlow.easeOut } }
    Behavior on color { ColorAnimation { duration: inGeCoreFlow.fastDuration } }
    Text { anchors.centerIn: parent; text: label; color: "white"; font.pixelSize: fs(11); font.bold: true }
    FlowCore.FlowRipple { id: mapChipRipple; flow: inGeCoreFlow; rippleColor: "#55FFFFFF"; enabled: inGeCoreFlow.motionAllowed }
    MouseArea {
        id: mapChipMouse
        anchors.fill: parent
        onPressed: function(mouse) { mapChipRipple.trigger(mouse.x, mouse.y) }
        onClicked: mapChipRoot.clicked()
    }
}

component FloatingMapButton: Rectangle {
    id: floatingMapRoot
    property string iconName: ""
    signal clicked()
    width: 54
    height: 48
    radius: 14
    color: floatingMapMouse.pressed ? inGeCoreFlow.theme.infoContainer : "#F4FFFFFF"
    border.color: floatingMapMouse.pressed ? primaryColor() : borderColor()
    scale: floatingMapMouse.pressed ? inGeCoreFlow.compactPressScale : 1.0
    clip: true
    Behavior on scale { NumberAnimation { duration: inGeCoreFlow.fastDuration; easing.type: inGeCoreFlow.easeOut } }
    Behavior on color { ColorAnimation { duration: inGeCoreFlow.fastDuration } }

    Components.FlowIcon {
        anchors.centerIn: parent
        width: 24
        height: 24
        name: floatingMapRoot.iconName
        flow: inGeCoreFlow
        pressed: floatingMapMouse.pressed
        tintColor: inGeCoreFlow.theme.textPrimary
        activeTintColor: primaryColor()
        inactiveOpacity: 1.0
    }

    FlowCore.FlowRipple {
        id: floatingMapRipple
        flow: inGeCoreFlow
        rippleColor: inGeCoreFlow.rippleLight
        enabled: inGeCoreFlow.motionAllowed
    }

    MouseArea {
        id: floatingMapMouse
        anchors.fill: parent
        onPressed: function(mouse) { floatingMapRipple.trigger(mouse.x, mouse.y) }
        onClicked: floatingMapRoot.clicked()
    }
}

component CoordBox: Rectangle {
    property string label: ""
    property string value: ""
    height: 46
    radius: 10
    color: inGeCoreFlow.colors.ingemaNavy
    border.color: Qt.rgba(1, 1, 1, 0.16)

    Column {
        anchors.fill: parent
        anchors.margins: 6
        Text { text: label; color: inGeCoreFlow.colors.ingemaBlueTint; font.pixelSize: fs(10) }
        Text { text: value; color: "white"; font.pixelSize: fs(12); font.bold: true; elide: Text.ElideRight }
    }
}

component DocRow: Rectangle {
    property string titleText: ""
    property string subText: ""
    property string iconName: ""
    height: 74
    radius: 14
    color: cardColor()
    border.color: borderColor()

    Row {
        anchors.fill: parent
        anchors.margins: 12
        spacing: 12
        Components.FlowIcon {
            width: 34; height: 34
            anchors.verticalCenter: parent.verticalCenter
            name: iconName
            flow: inGeCoreFlow
            tintColor: primaryColor()
            inactiveOpacity: 1.0
        }
        Column {
            width: parent.width - 70
            anchors.verticalCenter: parent.verticalCenter
            Text { text: titleText; color: textColor(); font.pixelSize: fs(14); font.bold: true; elide: Text.ElideRight }
            Text { text: subText; color: mutedColor(); font.pixelSize: fs(11); elide: Text.ElideRight }
        }
    }
}


}

import QtQuick
import QtQuick.Window
import QtQuick.Shapes
import QtCore
import InGe 1.0
import InGe.CoreFlow 3.0 as CoreFlowModule
import "lib/AccountText.js" as AccountText

// InGe+ — Acceso (Login V1 + First-run Welcome, 2026-10-12).
//
// Máquina de estados (screenState):
//   RESTORING_SESSION         restauración de la sesión recordada
//   FIRST_RUN_LOGIN_USER      instalación nueva, paso "usuario"
//   FIRST_RUN_LOGIN_PASSWORD  instalación nueva, paso "contraseña"
//   RETURNING_LOGIN_USER      ingeniero ya autenticado antes, paso "usuario"
//   RETURNING_LOGIN_PASSWORD  ídem, paso "contraseña"
//   AUTHENTICATING            Let's Go enviado, esperando AuthSession
//   FIRST_RUN_WELCOME         primera autenticación sin Get Started
//   AUTHENTICATED             estado autenticado existente
//
// Reglas: el correo se envía exactamente como fue escrito; los campos usuario
// y contraseña nunca se muestran a la vez; la contraseña no se registra y se
// borra en cada intento; la capitalización solo se aplica al nombre visible.
// Persistencia local (QSettings) en OnboardingState: bienvenida completada y
// nombre verificado por userId.
Window {
    id: root
    visible: true
    color: root.auroraBase
    title: "InGe+"
    // The real window owns the viewport; Android adjustResize is already
    // reflected in this height before CoreFlow computes keyboard overlap.
    Binding {
        target: CoreFlowModule.InGeCoreFlow
        property: "imeViewportHeight"
        value: root.height
    }

    // ------------------------------------------------------------ Paleta
    readonly property color navy: "#151A30"
    readonly property color navy2: "#1C2D50"
    readonly property color brandBlue: "#0654A2"
    readonly property color brandGreen: "#486426"
    readonly property color errorRed: "#D9483B"     // color de error existente
    readonly property color white: "#FFFFFF"
    // Tema oscuro (Configuración › Apariencia, preferencia leída por HomeScreen):
    // el Login mantiene sus auras con la paleta Ingema invertida sobre negro.
    readonly property bool darkTheme: authenticatedLayer.darkTheme
    readonly property bool halloween: authenticatedLayer.appSkin === "halloween"
    readonly property color auroraBase: halloween ? "#2B1047" : darkTheme ? "#0A0A0A" : navy
    readonly property color auroraDeep: halloween ? "#170A28" : darkTheme ? "#101A2E" : navy2
    readonly property color auroraPrimary: halloween ? "#6B2FA0" : darkTheme ? "#8AB8FF" : brandBlue
    readonly property color auroraAccent: halloween ? "#FF8A1F" : darkTheme ? "#8DB85A" : brandGreen
    readonly property color ctaColor: halloween ? "#FF8A1F" : darkTheme ? brandGreen : brandBlue        // botón principal

    // ------------------------------------------------------- Dependencias
    readonly property bool authReady: typeof auth !== "undefined" && auth !== null
    readonly property bool onboardingReady: typeof onboarding !== "undefined" && onboarding !== null
    readonly property bool reducedMotion: !GraphicsCore.systemAnimationsEnabled
    readonly property bool lowPower: GraphicsCore.deviceTier === "LOW"
                                     || GraphicsCore.deviceTier === "ULTRA_LOW"

    // -------------------------------------------------------------- Estado
    property string step: "USER"            // USER | PASSWORD | MFA (código de la app autenticadora)
    property bool submitting: false
    property string attemptEmail: ""        // correo exacto en curso
    // Perfil PENDIENTE de aprobación (AuthSession): pantalla de espera en el Login.
    readonly property bool accountPending: authReady && auth.accountPending === true
    property string serviceMessage: ""      // fallos que no son credenciales
    property string announcement: ""        // lectores de pantalla
    property bool leavingWelcome: false
    property string focusHandoff: ""        // USER | PASSWORD durante el traspaso de foco
    function moveFocusTo(next) {
        focusHandoff = next
        if (next === "PASSWORD") passwordField.input.forceActiveFocus()
        else userField.input.forceActiveFocus()
        step = next
        focusHandoff = ""
    }

    readonly property bool returningUser: onboardingReady && onboarding.returningUser
    // Gracia de 60 s vencida: solo contraseña del usuario recordado.
    readonly property bool sessionLocked: onboardingReady && onboarding.sessionLocked
    readonly property string screenState: {
        if (!authReady || auth.autoLoginInProgress)
            return "RESTORING_SESSION"
        if (submitting)
            return "AUTHENTICATING"
        if (sessionLocked)
            return "RETURNING_LOGIN_PASSWORD"         // nunca Welcome ni el correo
        if (auth.logged)
            return onboardingReady && !onboarding.welcomeCompleted
                    ? "FIRST_RUN_WELCOME" : "AUTHENTICATED"
        return (returningUser ? "RETURNING" : "FIRST_RUN")
                + (step === "PASSWORD" ? "_LOGIN_PASSWORD" : "_LOGIN_USER")
    }
    readonly property bool loginVisible: screenState === "RESTORING_SESSION"
                                         || screenState === "AUTHENTICATING"
                                         || screenState.indexOf("_LOGIN_") > 0
    readonly property bool welcomeVisible: screenState === "FIRST_RUN_WELCOME"
    readonly property bool authenticatedVisible: screenState === "AUTHENTICATED"

    readonly property string greetingName: onboardingReady ? onboarding.greetingName : ""
    readonly property string greetingFirstLine: returningUser ? "Hola de nuevo," : "Te damos la bienvenida a InGe+,"
    readonly property string greetingSecondLine: returningUser
            ? (AccountText.hasVisibleText(greetingName) ? greetingName : "colega")
            : "colega"

    // Escala tipográfica respecto de un teléfono de 390 px lógicos.
    readonly property real u: Math.max(0.82, Math.min(width, 520) / 390)
    readonly property real gutter: 28 * u

    onScreenStateChanged: console.info("INGE_ACCESS_STATE " + screenState)

    property real stableHeight: height
    onHeightChanged: stableHeight = Math.max(stableHeight, height)
    onWidthChanged: stableHeight = height              // rotación: nueva referencia
    // Al salir del acceso el teclado se cierra y ningún campo oculto retiene el foco.
    onLoginVisibleChanged: if (!loginVisible) {
        userField.input.focus = false
        passwordField.input.focus = false
        Qt.inputMethod.hide()
    }

    // ----------------------------------------------------------- Acciones
    function verifiedProfileName() {
        if (!authReady || !auth.logged)
            return ""
        var source = AccountText.hasVisibleText(auth.nombre) ? auth.nombre
                   : (auth.profileReady ? auth.fullName : "")
        return AccountText.greetingFirstName(source)
    }

    function recordAuthenticatedUser() {
        if (!authReady || !onboardingReady || !auth.logged
                || !AccountText.hasVisibleText(auth.userId))
            return
        onboarding.recordAuthenticatedUser(auth.userId, verifiedProfileName())
    }

    function continueToPassword() {
        if (step !== "USER" || continueFlow.running || submitting)
            return
        if (!AccountText.isAllowedLoginEmail(userField.input.text)) {
            announcement = "Ingresa un correo de Gmail válido."
            rejectLogin()                             // auras rojas + temblor, sin cuadro
            return
        }
        attemptEmail = userField.input.text          // exacto, sin recortes
        serviceMessage = ""
        announcement = ""
        if (reducedMotion) {
            moveFocusTo("PASSWORD")
        } else {
            continueFlow.restart()
        }
    }

    function submitPassword() {
        if (!authReady || submitting || step !== "PASSWORD")
            return
        var password = passwordField.input.text
        if (password.length === 0)
            return
        passwordField.input.text = ""                 // fuera de la vista de inmediato
        serviceMessage = ""
        announcement = ""
        submitting = true
        Qt.inputMethod.hide()
        // Persistencia segura existente (refresh token de AuthSession); el acceso
        // sin contraseña lo limita la gracia de 60 s de OnboardingState.
        auth.setRememberFor30Days(true)
        console.info("INGE_ACCESS_LOGIN submit")
        auth.signInWithPassword(attemptEmail, password)
    }

    // Google (Supabase OAuth PKCE en una Custom Tab). La regla @gmail.com sólo
    // aplica al correo escrito; el correo de Google lo entrega Supabase tal cual.
    function signInWithGoogle() {
        if (!authReady || submitting || continueFlow.running)
            return
        clearLoginError()
        serviceMessage = ""
        announcement = ""
        attemptEmail = ""
        passwordField.input.text = ""
        passwordEntry = false
        submitting = true
        Qt.inputMethod.hide()
        auth.setRememberFor30Days(true)
        console.info("INGE_ACCESS_LOGIN google")
        auth.signInWithGoogle()
    }

    function recheckApproval() {
        if (!authReady || submitting)
            return
        serviceMessage = ""
        submitting = true
        auth.recheckAccountApproval()
    }

    // Verificación en dos pasos: el código de 6 dígitos completa el inicio de sesión.
    function submitMfa() {
        if (!authReady || submitting || step !== "MFA")
            return
        var code = mfaField.input.text.replace(/\s+/g, "")
        if (code.length < 6)
            return
        serviceMessage = ""
        announcement = ""
        submitting = true
        Qt.inputMethod.hide()
        auth.verifyLoginTotp(code)
    }
    function cancelMfa() {
        auth.cancelMfaLogin()
        mfaField.input.text = ""
        submitting = false
        step = AccountText.hasVisibleText(attemptEmail) ? "PASSWORD" : "USER"   // Google: sin contraseña
    }

    // Correo verificado del último usuario (cuenta actual de AuthSession).
    function rememberedEmail() {
        if (!authReady)
            return ""
        if (auth.logged && AccountText.hasEmailFormat(auth.email))
            return auth.email
        var accounts = auth.savedAccounts || []
        for (var i = 0; i < accounts.length; ++i)
            if (accounts[i].id === auth.currentAccountId && AccountText.hasEmailFormat(accounts[i].email))
                return accounts[i].email
        // Identidad recordada de OnboardingState (misma cuenta que "Hola de nuevo").
        if (onboardingReady && AccountText.hasEmailFormat(onboarding.lastEmail))
            return onboarding.lastEmail
        return ""
    }
    // Usuario recordado: solo contraseña. Con sesión cargada sin gracia, bloqueo.
    function prefillRememberedUser() {
        var email = rememberedEmail()
        if (email.length === 0) {
            if (authReady && auth.logged)
                signOutToLogin()                  // sin identidad verificable
            return false
        }
        if (authReady && auth.logged) {
            onboarding.lockSession("startup_grace_expired")
            return true
        }
        attemptEmail = email
        serviceMessage = ""
        step = "PASSWORD"
        return true
    }
    // "Cambiar de cuenta": única forma de volver a pedir el correo.
    function switchAccount() {
        if (submitting)
            return
        console.info("INGE_ACCESS_SWITCH_ACCOUNT")
        if (onboardingReady)
            onboarding.forgetAccountEmail()
        attemptEmail = ""
        if (authReady && (auth.logged || sessionLocked)) {
            signOutToLogin()
        } else {
            passwordField.input.text = ""
            moveFocusTo("USER")
        }
        userField.input.text = ""
        userField.input.forceActiveFocus()
    }
    function enterLockedPassword() {
        var email = rememberedEmail()
        if (email.length === 0) {
            // Sin identidad verificable: autenticación completa, sin acceso.
            if (auth.logged) signOutToLogin(); else onboarding.endSession()
            return
        }
        attemptEmail = email
        serviceMessage = ""
        passwordField.input.text = ""
        step = "PASSWORD"
    }

    // Navegación única del botón Atrás cuando ningún elemento lo aceptó
    // (lo invoca el guardián nativo de main_mobile.cpp). true = consumido.
    function handleSystemBack() {
        console.info("INGE_NAV_BACK_SOURCE system state=" + screenState)
        if (authenticatedVisible)
            return authenticatedLayer.handleBack("system")
        if (loginVisible && step === "PASSWORD" && !submitting && !sessionLocked) {
            backToUser()
            return true
        }
        return false
    }

    // Acceso con usuario/contraseña: la barra aparece solo al tocar el ícono de
    // Supabase; tocar fuera o Atrás la oculta. El flujo de pasos no cambia.
    property bool passwordEntry: false
    readonly property bool credentialFieldShown: passwordEntry || step === "MFA"
    readonly property bool loginControlsShown: screenState !== "RESTORING_SESSION" && !accountPending
    function openPasswordEntry() {
        if (submitting || continueFlow.running)
            return
        passwordEntry = true
        moveFocusTo(step === "PASSWORD" ? "PASSWORD" : "USER")
    }
    function closePasswordEntry() {
        if (submitting || step === "MFA")
            return
        passwordField.input.text = ""                 // nunca queda una contraseña oculta escrita
        passwordEntry = false
        Qt.inputMethod.hide()
        userField.input.focus = false
        passwordField.input.focus = false
    }

    function backToUser() {
        if (step !== "PASSWORD" || submitting)
            return
        passwordField.input.text = ""
        serviceMessage = ""
        moveFocusTo("USER")
    }

    function signOutToLogin() {
        if (!authReady)
            return
        submitting = false
        passwordField.input.text = ""
        step = "USER"
        if (onboardingReady)
            onboarding.endSession()             // sin gracia tras cerrar sesión
        auth.signOut()
    }

    // Frase del día: determinista por día del año, fija mientras se muestra.
    readonly property var dailyPhrases: [
        "Desde hoy, tu asistente de ingeniería te ayuda a trabajar mejor cada día.",
        "Como tu asistente de ingeniería, espero serte de gran ayuda. Sigue con el buen trabajo.",
        "Tus ideas construyen el mañana.",
        "Precisión hoy. Progreso mañana.",
        "Cada detalle importa.",
        "Diseña con propósito. Construye con confianza.",
        "La buena ingeniería empieza con la curiosidad."
    ]
    property string welcomePhrase: ""
    function phraseForToday() {
        var now = new Date()
        var start = new Date(now.getFullYear(), 0, 1)
        var dayOfYear = Math.floor((now - start) / 86400000) + 1
        return dailyPhrases[(dayOfYear - 1) % dailyPhrases.length]
    }
    onWelcomeVisibleChanged: if (welcomeVisible) {
        welcomePhrase = phraseForToday()
        leavingWelcome = false
    }

    Connections {
        target: root.authReady ? auth : null
        function onMfaRequired() {
            root.submitting = false
            root.announcement = "Ingresa el código de tu app autenticadora."
            root.step = "MFA"
            mfaField.input.text = ""
            Qt.callLater(function() { mfaField.input.forceActiveFocus() })
        }
        function onMfaFail(message) {
            if (root.step !== "MFA")
                return
            root.submitting = false
            mfaField.input.text = ""
            root.announcement = message
            root.rejectLogin()
        }
        function onAccountPendingApproval() {
            root.submitting = false
            root.serviceMessage = ""
            root.announcement = "Tu cuenta está pendiente de aprobación."
            console.info("INGE_ACCESS_LOGIN pending")
        }
        function onLoginOk() {
            root.submitting = false
            root.clearLoginError()
            root.serviceMessage = ""
            root.recordAuthenticatedUser()
            if (root.onboardingReady) {
                onboarding.rememberAccountEmail(auth.userId,
                    AccountText.hasVisibleText(root.attemptEmail) ? root.attemptEmail : auth.email)
                onboarding.unlockSession()
                onboarding.setSessionTracked(true)
            }
            console.info("INGE_ACCESS_LOGIN ok")
        }
        function onLoginFail(message) {
            if (!root.submitting)
                return                       // respuesta tardía tras cerrar sesión
            root.submitting = false
            var failure = auth.lastLoginFailure
            console.info("INGE_ACCESS_LOGIN fail cause=" + failure)
            if (failure === "INVALID_CREDENTIALS") {
                root.announcement = "Contraseña incorrecta. Inténtalo de nuevo."
                root.serviceMessage = ""
                root.rejectLogin()
                passwordField.input.forceActiveFocus()
            } else {
                root.serviceMessage = AccountText.hasVisibleText(message)
                        ? message : "No se pudo iniciar sesión."
                root.announcement = root.serviceMessage
            }
        }
        function onBackendProfileChanged() { root.recordAuthenticatedUser() }
        function onUserInfoChanged() { root.recordAuthenticatedUser() }
        function onLoggedOut() {
            root.submitting = false
            root.step = "USER"
            passwordField.input.text = ""
            console.info("INGE_ACCESS_LOGGED_OUT")
            if (root.onboardingReady)
                onboarding.endSession()
        }
        function onLoggedChanged() {
            if (auth.logged && root.onboardingReady && !onboarding.sessionLocked)
                onboarding.setSessionTracked(true)
            if (auth.logged && root.onboardingReady && AccountText.hasEmailFormat(auth.email))
                onboarding.rememberAccountEmail(auth.userId, auth.email)
        }
        function onAutoLoginFinished(restored) {
            console.info("INGE_SESSION_RESTORED restored=" + restored)
        }
    }
    Connections {
        target: root.onboardingReady ? onboarding : null
        function onSessionLockChanged() {
            if (onboarding.sessionLocked) {
                root.enterLockedPassword()
                root.tryBiometricUnlock()
            }
        }
    }

    // ---- Desbloqueo con huella o rostro (Configuración › Privacidad y seguridad).
    // Sólo abre la sesión ya autenticada y bloqueada por la gracia; nunca reemplaza
    // la contraseña de un inicio de sesión nuevo.
    Settings { id: securityPrefs; category: "security"; property bool biometricUnlock: false }
    readonly property bool biometricReady: securityPrefs.biometricUnlock
                                           && typeof biometric !== "undefined" && biometric !== null && biometric.available
                                           && sessionLocked && authReady && auth.logged
    function tryBiometricUnlock() {
        if (biometricReady && !biometric.busy) biometric.authenticate()
    }
    Connections {
        target: typeof biometric !== "undefined" ? biometric : null
        ignoreUnknownSignals: true
        function onFinished(ok) {
            if (!ok || !root.sessionLocked || !root.authReady || !auth.logged) return
            console.info("INGE_ACCESS_BIOMETRIC_UNLOCK ok")
            onboarding.unlockSession()
            onboarding.setSessionTracked(true)
        }
    }

    Component.onCompleted: {
        var grace = onboardingReady && onboarding.consumeStartupGrace()
        if (authReady && auth.hasRestorableSession() && grace) {
            console.info("INGE_ACCESS_SESSION_RESTORE begin")
            auth.tryAutoLogin()
        } else if (prefillRememberedUser()) {
            console.info("INGE_ACCESS_SESSION_RESTORE password_required")
            Qt.callLater(tryBiometricUnlock)
        } else {
            console.info("INGE_ACCESS_SESSION_RESTORE none")
        }
        recordAuthenticatedUser()
    }

    // ===================================================== Aurora del Login
    AuroraField {
        id: loginAurora
        width: parent.width
        height: Math.max(parent.height, root.stableHeight)
        mode: 0
        motion: !root.reducedMotion
        lowPower: root.lowPower
        baseColor: root.auroraBase
        deepColor: root.auroraDeep
        primaryColor: root.auroraPrimary
        accentColor: root.auroraAccent
        tintColor: root.errorRed
        // Se detiene cuando el Home (opaco) ya cubre la pantalla.
        visible: (!root.welcomeVisible || welcomeLayer.opacity < 1)
                 && !(root.authenticatedVisible && authenticatedLayer.opacity >= 1)
    }

    // ---------------------------------------------- Continue: luz verde
    SequentialAnimation {
        id: continueFlow
        NumberAnimation { target: loginAurora; property: "boost"; to: 0.3; duration: 260; easing.type: Easing.InOutSine }
        ScriptAction { script: root.moveFocusTo("PASSWORD") }
        NumberAnimation { target: loginAurora; property: "boost"; to: 0.0; duration: 420; easing.type: Easing.OutCubic }
    }

    // ------------- Rechazo del acceso (correo no permitido o credenciales inválidas)
    // Sin cuadro de diálogo: las auras pasan a rojo (tintAmount) y quedan así
    // hasta editar el campo; el formulario tiembla ~400 ms. Con reducedMotion,
    // sólo el rojo.
    property bool loginErrorHeld: false
    function rejectLogin() {
        loginErrorClear.stop()
        loginErrorHeld = true
        if (reducedMotion) {
            formShake.x = 0
            errorTintOnly.restart()
        } else {
            credentialError.restart()
        }
    }
    function clearLoginError() {
        if (!loginErrorHeld)
            return
        loginErrorHeld = false
        credentialError.stop()
        errorTintOnly.stop()
        formShake.x = 0
        loginErrorClear.restart()
    }
    ParallelAnimation {
        id: credentialError
        NumberAnimation { target: loginAurora; property: "tintAmount"; to: 1.0; duration: 120; easing.type: Easing.OutQuad }
        SequentialAnimation {                           // 0→-12→12→-8→8→-4→0 u (≈400 ms)
            NumberAnimation { target: formShake; property: "x"; to: -12 * root.u; duration: 60; easing.type: Easing.OutQuad }
            NumberAnimation { target: formShake; property: "x"; to: 12 * root.u; duration: 70; easing.type: Easing.InOutQuad }
            NumberAnimation { target: formShake; property: "x"; to: -8 * root.u; duration: 70; easing.type: Easing.InOutQuad }
            NumberAnimation { target: formShake; property: "x"; to: 8 * root.u; duration: 70; easing.type: Easing.InOutQuad }
            NumberAnimation { target: formShake; property: "x"; to: -4 * root.u; duration: 65; easing.type: Easing.InOutQuad }
            NumberAnimation { target: formShake; property: "x"; to: 0; duration: 65; easing.type: Easing.OutQuad }
        }
    }
    NumberAnimation { id: errorTintOnly; target: loginAurora; property: "tintAmount"; to: 1.0; duration: 160 }
    NumberAnimation { id: loginErrorClear; target: loginAurora; property: "tintAmount"; to: 0.0; duration: 300; easing.type: Easing.InOutSine }
    // Las auras vuelven a la normalidad al editar cualquier campo del acceso.
    Connections { target: userField.input; function onTextEdited() { root.clearLoginError() } }
    Connections { target: passwordField.input; function onTextEdited() { root.clearLoginError() } }
    Connections { target: mfaField.input; function onTextEdited() { root.clearLoginError() } }

    // ================================================================ LOGIN
    Flickable {
        id: loginLayer
        anchors.fill: parent
        contentWidth: width
        contentHeight: Math.max(height, loginForm.height + 2 * root.gutter)
        boundsBehavior: Flickable.StopAtBounds
        interactive: contentHeight > height
        opacity: root.loginVisible ? 1 : 0
        visible: opacity > 0
        Behavior on opacity { NumberAnimation { duration: root.reducedMotion ? 0 : 520; easing.type: Easing.InOutCubic } }
        scale: 1 + (1 - opacity) * 0.05

        // Paso contraseña: Back vuelve al usuario sin salir de la app.
        Keys.onBackPressed: function(event) {
            if (root.step === "MFA" && !root.submitting) {
                root.cancelMfa()
                event.accepted = true
            } else if (root.step === "PASSWORD" && !root.submitting && !root.sessionLocked) {
                root.backToUser()
                event.accepted = true
            } else if (root.passwordEntry && !root.submitting) {
                root.closePasswordEntry()
                event.accepted = true
            } else {
                event.accepted = false
            }
        }

        Item {
            id: formShake
            width: loginLayer.width
            height: loginLayer.contentHeight

            MouseArea {                                   // tocar fuera oculta la barra de usuario
                anchors.fill: parent
                enabled: root.passwordEntry && root.step !== "MFA" && !root.submitting
                onClicked: root.closePasswordEntry()
            }

            Column {
                id: loginForm
                x: root.gutter
                width: parent.width - 2 * root.gutter
                // Bloque inferior como en el preview; con teclado (adjustResize)
                // la ventana se reduce y el bloque sube sin recortarse.
                // Saludo centrado arriba (~30 % de alto); botones-ícono hacia el 75 %.
                y: Math.max(root.gutter, Math.min(loginLayer.contentHeight * 0.30,
                            loginLayer.contentHeight - height
                            - Math.max(42 * root.u, loginLayer.height * 0.085)))

                // Saludo con destellos
                Item {
                    width: loginForm.width
                    height: greeting.implicitHeight
                    Text {
                        id: greeting
                        width: parent.width
                        text: root.greetingFirstLine + "\n" + root.greetingSecondLine
                        color: root.white
                        font.family: rubik.font.family
                        font.weight: Font.Light
                        font.pixelSize: 31 * root.u
                        lineHeight: 1.08
                        wrapMode: Text.WordWrap
                        Accessible.role: Accessible.Heading
                        Accessible.name: root.greetingFirstLine + " " + root.greetingSecondLine
                    }
                    TextMetrics {
                        id: firstLineMetrics
                        font: greeting.font
                        text: root.greetingFirstLine
                    }
                    Sparkles {
                        x: Math.min(firstLineMetrics.advanceWidth + 6 * root.u, parent.width - width)
                        y: -14 * root.u
                        unit: root.u
                    }
                }

                Item {                                    // separa saludo y botones cuando no hay campo
                    width: 1
                    height: (root.credentialFieldShown || root.step === "MFA")
                            ? 34 * root.u : Math.max(34 * root.u, loginLayer.contentHeight * 0.24)
                    Behavior on height { NumberAnimation { duration: root.reducedMotion ? 0 : CoreFlowModule.InGeCoreFlow.duration(240); easing.type: Easing.OutCubic } }
                }

                // Un solo campo visible: usuario o contraseña, en la misma posición.
                Item {
                    id: fieldSlot
                    readonly property bool shown: root.loginControlsShown && root.credentialFieldShown
                    readonly property int motionMs: root.reducedMotion ? 0 : CoreFlowModule.InGeCoreFlow.duration(240)
                    width: loginForm.width
                    height: shown ? 52 * root.u : 0
                    opacity: shown ? 1 : 0
                    visible: opacity > 0.01
                    clip: !shown
                    transform: Translate { y: fieldSlot.shown ? 0 : 14 * root.u
                                           Behavior on y { NumberAnimation { duration: fieldSlot.motionMs; easing.type: Easing.OutCubic } } }
                    Behavior on height { NumberAnimation { duration: fieldSlot.motionMs; easing.type: Easing.OutCubic } }
                    Behavior on opacity { NumberAnimation { duration: fieldSlot.motionMs; easing.type: Easing.OutCubic } }

                    LineField {
                        id: userField
                        anchors.fill: parent
                        placeholder: "usuario"
                        shown: root.step === "USER" || root.focusHandoff === "USER"
                        unit: root.u
                        fontFamily: rubik.font.family
                        accent: root.brandGreen
                        input.inputMethodHints: Qt.ImhEmailCharactersOnly | Qt.ImhNoAutoUppercase | Qt.ImhNoPredictiveText
                        input.enabled: (root.step === "USER" || root.focusHandoff === "USER") && !root.submitting
                        Accessible.name: "usuario"
                        onAccepted: root.continueToPassword()
                    }
                    LineField {
                        id: passwordField
                        anchors.fill: parent
                        placeholder: "contraseña"
                        shown: root.step === "PASSWORD" || root.focusHandoff === "PASSWORD"
                        unit: root.u
                        fontFamily: rubik.font.family
                        accent: root.brandGreen
                        input.echoMode: TextInput.Password
                        input.inputMethodHints: Qt.ImhHiddenText | Qt.ImhSensitiveData | Qt.ImhNoPredictiveText | Qt.ImhNoAutoUppercase
                        input.enabled: (root.step === "PASSWORD" || root.focusHandoff === "PASSWORD") && !root.submitting
                        Accessible.name: "contraseña"
                        onAccepted: root.submitPassword()
                    }
                    LineField {
                        id: mfaField
                        anchors.fill: parent
                        placeholder: "código de 6 dígitos"
                        shown: root.step === "MFA"
                        unit: root.u
                        fontFamily: rubik.font.family
                        accent: root.brandGreen
                        input.inputMethodHints: Qt.ImhDigitsOnly | Qt.ImhNoPredictiveText
                        input.maximumLength: 6
                        input.enabled: root.step === "MFA" && !root.submitting
                        Accessible.name: "código de verificación"
                        onAccepted: root.submitMfa()
                    }
                }

                // Hueco del segundo campo del preview: los campos se muestran de uno
                // en uno, pero el botón conserva la posición aprobada.
                Item {
                    width: loginForm.width
                    height: (root.biometricReady || root.credentialFieldShown ? 92 : 28) * root.u
                    visible: root.loginControlsShown
                    Text {   // Usar huella o rostro (sesión bloqueada con desbloqueo activado)
                        y: (root.credentialFieldShown ? 54 : 6) * root.u
                        visible: root.biometricReady && !root.submitting
                        text: "Usar huella o rostro"
                        color: Qt.rgba(1, 1, 1, 0.9)
                        font.family: rubik.font.family
                        font.pixelSize: 15 * root.u
                        font.underline: true
                        MouseArea { anchors.fill: parent; anchors.margins: -10 * root.u; onClicked: root.tryBiometricUnlock() }
                        Accessible.role: Accessible.Button
                        Accessible.name: "Usar huella o rostro"
                    }
                    Text {   // Volver: cancela el código y regresa a la contraseña
                        y: 18 * root.u
                        visible: root.step === "MFA" && !root.submitting
                        text: "Volver"
                        color: Qt.rgba(1, 1, 1, 0.78)
                        font.family: rubik.font.family
                        font.pixelSize: 15 * root.u
                        font.underline: true
                        MouseArea { anchors.fill: parent; anchors.margins: -10 * root.u; onClicked: root.cancelMfa() }
                        Accessible.role: Accessible.Button
                        Accessible.name: "Volver a la contraseña"
                    }
                    Text {   // Cambiar de cuenta: solo en el paso contraseña
                        y: 18 * root.u
                        visible: root.step === "PASSWORD" && !root.submitting
                        text: "Cambiar de cuenta"
                        color: Qt.rgba(1, 1, 1, 0.78)
                        font.family: rubik.font.family
                        font.pixelSize: 15 * root.u
                        font.underline: true
                        MouseArea { anchors.fill: parent; anchors.margins: -10 * root.u; onClicked: root.switchAccount() }
                        Accessible.role: Accessible.Button
                        Accessible.name: "Cambiar de cuenta"
                    }
                }

                // Accesos: Supabase (usuario/contraseña) y Google como botones-ícono de
                // vidrio, centrados. Supabase abre la barra de usuario; Google, el OAuth.
                Item {
                    width: loginForm.width
                    height: 84 * root.u
                    visible: root.loginControlsShown && root.step !== "MFA"
                    Row {
                        anchors.centerIn: parent
                        spacing: 40 * root.u
                        Repeater {
                            model: [{ key: "supabase", source: "qrc:/images/supabase_mark.png", name: "Iniciar sesión con usuario y contraseña" },
                                    { key: "google", source: "qrc:/images/google_mark.png", name: "Continuar con Google" }]
                            delegate: Rectangle {
                                id: accessIcon
                                required property var modelData
                                readonly property bool active: modelData.key === "supabase" && root.passwordEntry
                                function trigger() {
                                    if (modelData.key === "google") root.signInWithGoogle()
                                    else root.openPasswordEntry()
                                }
                                width: 84 * root.u
                                height: width
                                radius: width / 2
                                color: "transparent"
                                border.width: accessIcon.active ? 2 : 0
                                border.color: root.brandGreen
                                opacity: root.submitting ? 0.6 : 1
                                scale: accessTap.pressed ? 0.92 : 1
                                Behavior on scale { NumberAnimation { duration: root.reducedMotion ? 0 : 120; easing.type: Easing.OutCubic } }
                                Image {
                                    anchors.centerIn: parent
                                    width: 60 * root.u
                                    height: width
                                    source: accessIcon.modelData.source
                                    sourceSize: Qt.size(192, 192)
                                    fillMode: Image.PreserveAspectFit
                                    smooth: true
                                    mipmap: true
                                }
                                MouseArea {
                                    id: accessTap
                                    anchors.fill: parent
                                    anchors.margins: -6 * root.u
                                    enabled: !root.submitting && !continueFlow.running
                                    onClicked: accessIcon.trigger()
                                }
                                Accessible.role: Accessible.Button
                                Accessible.name: modelData.name
                                Accessible.onPressAction: accessIcon.trigger()
                            }
                        }
                    }
                }

                // Fallos que no son de credenciales (conexión, servicio, cuenta).
                Text {
                    width: loginForm.width
                    topPadding: 14 * root.u
                    visible: root.serviceMessage.length > 0 && root.loginControlsShown
                    text: root.serviceMessage
                    color: Qt.rgba(1, 1, 1, 0.78)
                    font.family: rubik.font.family
                    font.pixelSize: 14 * root.u
                    wrapMode: Text.WordWrap
                    horizontalAlignment: Text.AlignHCenter
                }
                // Cuenta PENDIENTE de aprobación (como en la web): no entra al Home.
                Rectangle {
                    id: pendingPanel
                    width: loginForm.width
                    height: pendingColumn.implicitHeight + 44 * root.u
                    radius: 22 * root.u
                    visible: root.accountPending && root.screenState !== "RESTORING_SESSION"
                    color: Qt.rgba(1, 1, 1, root.darkTheme ? 0.12 : 0.18)
                    border.width: 1
                    border.color: Qt.rgba(1, 1, 1, 0.38)
                    Accessible.role: Accessible.Dialog
                    Accessible.name: "Tu cuenta está pendiente de aprobación"
                    Column {
                        id: pendingColumn
                        x: 22 * root.u; y: 22 * root.u
                        width: parent.width - 44 * root.u
                        spacing: 12 * root.u
                        Text {
                            width: parent.width
                            text: "Tu cuenta está pendiente de aprobación"
                            color: root.white
                            font.family: rubik.font.family
                            font.pixelSize: 21 * root.u
                            font.weight: Font.DemiBold
                            wrapMode: Text.WordWrap
                            Accessible.role: Accessible.Heading
                        }
                        Text {
                            width: parent.width
                            text: "Un administrador de InGe+ debe aprobar tu acceso. Te avisaremos al volver a comprobar."
                                  + (AccountText.hasVisibleText(auth.email)
                                     ? "\n" + AccountText.displayEmailExact(auth.email, "") : "")
                            color: Qt.rgba(1, 1, 1, 0.86)
                            font.family: rubik.font.family
                            font.pixelSize: 15 * root.u
                            wrapMode: Text.WordWrap
                        }
                        Item { width: 1; height: 4 * root.u }
                        Rectangle {
                            width: parent.width
                            height: 54 * root.u
                            radius: 15 * root.u
                            color: root.ctaColor
                            opacity: root.submitting ? 0.7 : (recheckTap.pressed ? 0.88 : 1)
                            Text {
                                anchors.centerIn: parent
                                text: auth.accountPendingChecking ? "Comprobando…" : "Volver a comprobar"
                                color: root.halloween ? "#2B1047" : root.white
                                font.family: rubik.font.family
                                font.pixelSize: 17 * root.u
                            }
                            MouseArea { id: recheckTap; anchors.fill: parent; enabled: !root.submitting; onClicked: root.recheckApproval() }
                            Accessible.role: Accessible.Button
                            Accessible.name: "Volver a comprobar"
                            Accessible.onPressAction: root.recheckApproval()
                        }
                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: "Cerrar sesión"
                            color: Qt.rgba(1, 1, 1, 0.86)
                            font.family: rubik.font.family
                            font.pixelSize: 15 * root.u
                            font.underline: true
                            MouseArea { anchors.fill: parent; anchors.margins: -10 * root.u; onClicked: root.signOutToLogin() }
                            Accessible.role: Accessible.Button
                            Accessible.name: "Cerrar sesión"
                        }
                        Text {
                            width: parent.width
                            visible: root.serviceMessage.length > 0
                            text: root.serviceMessage
                            color: Qt.rgba(1, 1, 1, 0.78)
                            font.family: rubik.font.family
                            font.pixelSize: 14 * root.u
                            wrapMode: Text.WordWrap
                            horizontalAlignment: Text.AlignHCenter
                        }
                    }
                }
                Text {
                    width: loginForm.width
                    visible: root.screenState === "RESTORING_SESSION"
                    text: "Restaurando sesión…"
                    color: Qt.rgba(1, 1, 1, 0.78)
                    font.family: rubik.font.family
                    font.pixelSize: 15 * root.u
                }
            }
        }
    }

    // ============================================================= WELCOME
    Item {
        id: welcomeLayer
        anchors.fill: parent
        opacity: root.welcomeVisible && !root.leavingWelcome ? 1 : 0
        visible: opacity > 0
        Behavior on opacity { NumberAnimation { duration: root.reducedMotion ? 0 : 560; easing.type: Easing.InOutCubic } }
        scale: 1 + (1 - opacity) * 0.06                 // se aleja hacia el usuario al salir

        AuroraField {
            anchors.fill: parent
            mode: 1
            motion: !root.reducedMotion
            lowPower: root.lowPower
            baseColor: root.auroraBase
            deepColor: root.auroraDeep
            primaryColor: root.auroraPrimary
            accentColor: root.auroraAccent
            visible: welcomeLayer.visible
        }

        Column {
            id: welcomeColumn
            x: root.gutter
            width: parent.width - 2 * root.gutter
            y: Math.max(root.gutter, Math.min(parent.height * 0.40,
                                               parent.height - height - Math.max(40 * root.u, parent.height * 0.08)))
            spacing: 0

            Image {
                anchors.horizontalCenter: parent.horizontalCenter
                source: "qrc:/InGe/Mobile/assets/inge_symbol_white.png"
                width: 74 * root.u
                height: width
                sourceSize: Qt.size(Math.round(width * Screen.devicePixelRatio),
                                    Math.round(height * Screen.devicePixelRatio))
                fillMode: Image.PreserveAspectFit
                smooth: true
                mipmap: true
                Accessible.role: Accessible.Graphic
                Accessible.name: "InGe+"
            }
            Item { width: 1; height: 16 * root.u }
            Text {
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                text: "Te damos la bienvenida a InGe+"
                color: root.white
                font.family: rubik.font.family
                font.weight: Font.DemiBold
                font.pixelSize: 29 * root.u
                Accessible.role: Accessible.Heading
            }
            Item { width: 1; height: 16 * root.u }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                width: parent.width * 0.9
                horizontalAlignment: Text.AlignHCenter
                text: root.welcomePhrase
                color: Qt.rgba(1, 1, 1, 0.92)
                font.family: rubik.font.family
                font.pixelSize: 17 * root.u
                lineHeight: 1.22
                wrapMode: Text.WordWrap
            }
            Item { width: 1; height: 44 * root.u }
            Rectangle {
                width: parent.width
                height: 58 * root.u
                radius: height / 2
                color: root.white
                opacity: getStartedTap.pressed ? 0.88 : 1
                Text {
                    anchors.centerIn: parent
                    text: "Comenzar"
                    color: root.navy
                    font.family: rubik.font.family
                    font.weight: Font.DemiBold
                    font.pixelSize: 18 * root.u
                }
                MouseArea {
                    id: getStartedTap
                    anchors.fill: parent
                    enabled: !root.leavingWelcome
                    onClicked: getStartedFlow.restart()
                }
                Accessible.role: Accessible.Button
                Accessible.name: "Comenzar"
                Accessible.onPressAction: getStartedFlow.restart()
            }
            Item { width: 1; height: 30 * root.u }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                textFormat: Text.StyledText
                text: "¿Ya tienes cuenta? <b>Inicia sesión</b>"
                color: root.white
                font.family: rubik.font.family
                font.pixelSize: 16 * root.u
                MouseArea {
                    anchors.fill: parent
                    anchors.margins: -10 * root.u
                    enabled: !root.leavingWelcome
                    onClicked: root.signOutToLogin()
                }
                Accessible.role: Accessible.Button
                Accessible.name: "Iniciar sesión con otra cuenta"
            }
        }
    }

    // Get Started: fundido y bienvenida completada (persistida en QSettings).
    SequentialAnimation {
        id: getStartedFlow
        ScriptAction { script: root.leavingWelcome = true }
        PauseAnimation { duration: root.reducedMotion ? 0 : 380 }
        ScriptAction {
            script: {
                if (root.onboardingReady)
                    onboarding.completeWelcome()
                root.leavingWelcome = false
            }
        }
    }

    // ===================================================== AUTENTICADO
    // Home V1 (HomeScreen.qml). El primer dibujado del Home es pesado (~1 s en el
    // A12): si el fundido empezaba a la vez, terminaba antes del primer cuadro y el
    // Home aparecía de golpe tras un fondo vacío. Ahora el Home se prepara de forma
    // invisible (1 % de opacidad, sin recibir toques) mientras se autentica o se
    // muestra la bienvenida, y el fundido empieza cuando ya dibujó sus cuadros.
    // A12: el Home precalentado (visible a 1 %) durante AUTHENTICATING/FIRST_RUN_WELCOME
    // dejaba pasar sus popups de Overlay.overlay (que no heredan la opacidad) sobre la
    // bienvenida. Ahora queda oculto (visible false) hasta AUTHENTICATED y sólo se
    // funde cuando el Login y la bienvenida (opacos) ya terminaron de salir.
    property bool homeRevealed: false
    property int revealFrames: 0
    readonly property bool homeWarming: authReady && authenticatedVisible
    readonly property bool accessCleared: loginLayer.opacity === 0 && welcomeLayer.opacity === 0
    readonly property bool homeShown: authenticatedVisible && homeRevealed && accessCleared
    onHomeShownChanged: if (homeShown) authenticatedLayer.forceActiveFocus()   // ya habilitado
    function revealHome() {
        revealFrames = 0
        revealFallback.stop()
        homeRevealed = true
        authenticatedLayer.forceActiveFocus()
    }
    onAuthenticatedVisibleChanged: {
        if (authenticatedVisible) {
            if (reducedMotion) { revealHome() }
            else { revealFrames = 3; revealFallback.restart() }
        } else {
            revealFrames = 0
            revealFallback.stop()
            homeRevealed = false
            loginAurora.boost = 0
        }
    }
    Connections {
        target: root
        enabled: root.revealFrames > 0
        function onFrameSwapped() { if (--root.revealFrames <= 0) root.revealHome() }
    }
    Timer { id: revealFallback; interval: 900; onTriggered: root.revealHome() }

    HomeScreen {
        id: authenticatedLayer
        anchors.fill: parent
        u: root.u
        fontFamily: rubik.font.family
        iconFamily: lucide.font.family
        systemReducedMotion: root.reducedMotion
        opacity: root.homeShown ? 1 : (root.homeWarming ? 0.011 : 0)
        visible: root.authenticatedVisible && opacity > 0
        enabled: root.homeShown
        Behavior on opacity { NumberAnimation { duration: root.reducedMotion ? 0 : 750; easing.type: Easing.InOutCubic } }
        scale: root.homeShown ? 1 : 1.08
        Behavior on scale { NumberAnimation { duration: root.reducedMotion ? 0 : 1100; easing.type: Easing.OutQuint } }
        onSignOutRequested: root.signOutToLogin()
    }

    // Cinematic opening: cover the live access state during the ORIGINAL
    // 10-second MP4; a white-blue glint smoothly reveals the prepared login.
    // One launch only, never replayed on sign-out, page changes or re-auth.
    StartupIntro {
        id: startupIntro
        anchors.fill: parent
        fontFamily: rubik.font.family
    }

    // Anuncio para lectores de pantalla (el error de contraseña no es visible).
    Item {
        width: 1
        height: 1
        opacity: 0.01
        Accessible.role: Accessible.AlertMessage
        Accessible.name: root.announcement
        Accessible.ignored: root.announcement.length === 0
    }

    // Tipografía corporativa INGEMA: Rubik (SIL OFL 1.1, fonts/OFL.txt).
    FontLoader { id: rubik; source: "qrc:/InGe/Mobile/fonts/Rubik-Regular.ttf" }
    FontLoader { source: "qrc:/InGe/Mobile/fonts/Rubik-Light.ttf" }
    FontLoader { source: "qrc:/InGe/Mobile/fonts/Rubik-SemiBold.ttf" }
    // Iconos Lucide (ISC; fonts/lucide/LICENSE), trazo fino como los previews.
    FontLoader { id: lucide; source: "qrc:/InGe/Mobile/fonts/lucide/Lucide-w300.ttf" }

    // ------------------------------------------------ Componentes locales
    // Campo de línea del preview: etiqueta, texto y subrayado degradado.
    component LineField: Item {
        id: lineField
        property alias input: field
        property string placeholder: ""
        property bool shown: true
        property real unit: 1
        property string fontFamily: ""
        property color accent: "#486426"
        signal accepted()

        opacity: shown ? 1 : 0
        visible: shown || opacity > 0
        Behavior on opacity { OpacityAnimator { duration: 160 } }

        TextInput {
            id: field
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.leftMargin: 3 * lineField.unit
            anchors.bottom: underline.top
            anchors.bottomMargin: 10 * lineField.unit
            color: "#FFFFFF"
            selectionColor: Qt.rgba(1, 1, 1, 0.3)
            font.family: lineField.fontFamily
            font.pixelSize: 19 * lineField.unit
            clip: true
            onAccepted: lineField.accepted()
        }
        Text {
            anchors.left: field.left
            anchors.verticalCenter: field.verticalCenter
            text: lineField.placeholder
            color: Qt.rgba(1, 1, 1, 0.85)
            font.family: lineField.fontFamily
            font.pixelSize: 19 * lineField.unit
            visible: field.text.length === 0
        }
        Rectangle {
            id: underline
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            height: field.activeFocus ? 2 : 1.4
            gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop { position: 0.0; color: Qt.rgba(1, 1, 1, 0.9) }
                GradientStop { position: 1.0; color: Qt.tint(Qt.rgba(1, 1, 1, 0.9), Qt.rgba(lineField.accent.r, lineField.accent.g, lineField.accent.b, 0.55)) }
            }
        }
        MouseArea {
            anchors.fill: parent
            onClicked: field.forceActiveFocus()
        }
    }

    // Destellos del saludo (dos estrellas de cuatro puntas, como el preview).
    component Sparkles: Item {
        id: sparkles
        property real unit: 1
        width: 44 * unit
        height: 40 * unit
        Shape {
            x: 0
            y: 12 * sparkles.unit
            width: 28 * sparkles.unit
            height: 28 * sparkles.unit
            preferredRendererType: Shape.CurveRenderer
            ShapePath {
                id: bigStar
                strokeWidth: -1
                fillColor: Qt.tint("#0654A2", Qt.rgba(0.55, 0.78, 1.0, 0.55))
                property real s: 14 * sparkles.unit
                startX: bigStar.s; startY: 0
                PathQuad { x: 2 * bigStar.s * 1.0; y: bigStar.s; controlX: bigStar.s * 1.12; controlY: bigStar.s * 0.88 }
                PathQuad { x: bigStar.s; y: 2 * bigStar.s; controlX: bigStar.s * 1.12; controlY: bigStar.s * 1.12 }
                PathQuad { x: 0; y: bigStar.s; controlX: bigStar.s * 0.88; controlY: bigStar.s * 1.12 }
                PathQuad { x: bigStar.s; y: 0; controlX: bigStar.s * 0.88; controlY: bigStar.s * 0.88 }
            }
        }
        Shape {
            x: 24 * sparkles.unit
            y: 0
            width: 16 * sparkles.unit
            height: 16 * sparkles.unit
            preferredRendererType: Shape.CurveRenderer
            ShapePath {
                id: smallStar
                strokeWidth: -1
                fillColor: Qt.tint("#486426", Qt.rgba(0.85, 1.0, 0.35, 0.6))
                property real s: 8 * sparkles.unit
                startX: smallStar.s; startY: 0
                PathQuad { x: 2 * smallStar.s; y: smallStar.s; controlX: smallStar.s * 1.12; controlY: smallStar.s * 0.88 }
                PathQuad { x: smallStar.s; y: 2 * smallStar.s; controlX: smallStar.s * 1.12; controlY: smallStar.s * 1.12 }
                PathQuad { x: 0; y: smallStar.s; controlX: smallStar.s * 0.88; controlY: smallStar.s * 1.12 }
                PathQuad { x: smallStar.s; y: 0; controlX: smallStar.s * 0.88; controlY: smallStar.s * 0.88 }
            }
        }
        Accessible.ignored: true
    }
}

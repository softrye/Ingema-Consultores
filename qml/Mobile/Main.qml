import QtQuick
import QtQuick.Window
import QtQuick.Shapes
import InGe 1.0
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
    color: root.navy
    title: "InGe+"

    // ------------------------------------------------------------ Paleta
    readonly property color navy: "#151A30"
    readonly property color navy2: "#1C2D50"
    readonly property color brandBlue: "#0654A2"
    readonly property color brandGreen: "#486426"
    readonly property color errorRed: "#D9483B"     // color de error existente
    readonly property color white: "#FFFFFF"

    // ------------------------------------------------------- Dependencias
    readonly property bool authReady: typeof auth !== "undefined" && auth !== null
    readonly property bool onboardingReady: typeof onboarding !== "undefined" && onboarding !== null
    readonly property bool reducedMotion: !GraphicsCore.systemAnimationsEnabled
    readonly property bool lowPower: GraphicsCore.deviceTier === "LOW"
                                     || GraphicsCore.deviceTier === "ULTRA_LOW"

    // -------------------------------------------------------------- Estado
    property string step: "USER"            // USER | PASSWORD
    property bool submitting: false
    property string attemptEmail: ""        // correo exacto en curso
    property string serviceMessage: ""      // fallos que no son credenciales
    property string announcement: ""        // lectores de pantalla
    property bool leavingWelcome: false

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
    readonly property string greetingFirstLine: returningUser ? "Welcome back," : "Welcome to InGe+,"
    readonly property string greetingSecondLine: returningUser
            ? (AccountText.hasVisibleText(greetingName) ? greetingName : "Engineer")
            : "Engineer"

    // Escala tipográfica respecto de un teléfono de 390 px lógicos.
    readonly property real u: Math.max(0.82, Math.min(width, 520) / 390)
    readonly property real gutter: 28 * u

    onScreenStateChanged: console.info("INGE_ACCESS_STATE " + screenState)

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
        if (!AccountText.hasEmailFormat(userField.input.text)) {
            announcement = "Ingresa un correo válido."
            if (!reducedMotion)
                shakeOnly.restart()
            return
        }
        attemptEmail = userField.input.text          // exacto, sin recortes
        serviceMessage = ""
        announcement = ""
        if (reducedMotion) {
            step = "PASSWORD"
            passwordField.input.forceActiveFocus()
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
        // Persistencia segura existente (refresh token de AuthSession); el acceso
        // sin contraseña lo limita la gracia de 60 s de OnboardingState.
        auth.setRememberFor30Days(true)
        console.info("INGE_ACCESS_LOGIN submit")
        auth.signInWithPassword(attemptEmail, password)
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
        // Identidad recordada de OnboardingState (misma cuenta que "Welcome back").
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
            step = "USER"
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

    function backToUser() {
        if (step !== "PASSWORD" || submitting)
            return
        passwordField.input.text = ""
        serviceMessage = ""
        step = "USER"
        userField.input.forceActiveFocus()
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
        "Starting today, your engineering assistant helps you work smarter every day.",
        "As your engineering assistant, I hope to be of great help. Keep up the good work.",
        "Your ideas build tomorrow.",
        "Precision today. Progress tomorrow.",
        "Every detail matters.",
        "Design with purpose. Build with confidence.",
        "Great engineering begins with curiosity."
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
        function onLoginOk() {
            root.submitting = false
            root.serviceMessage = ""
            root.recordAuthenticatedUser()
            if (root.onboardingReady) {
                onboarding.rememberAccountEmail(auth.userId, root.attemptEmail)
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
                if (root.reducedMotion) errorTintOnly.restart(); else credentialError.restart()
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
            if (onboarding.sessionLocked)
                root.enterLockedPassword()
        }
    }

    Component.onCompleted: {
        var grace = onboardingReady && onboarding.consumeStartupGrace()
        if (authReady && auth.hasRestorableSession() && grace) {
            console.info("INGE_ACCESS_SESSION_RESTORE begin")
            auth.tryAutoLogin()
        } else if (prefillRememberedUser()) {
            console.info("INGE_ACCESS_SESSION_RESTORE password_required")
        } else {
            console.info("INGE_ACCESS_SESSION_RESTORE none")
        }
        recordAuthenticatedUser()
    }

    // ===================================================== Aurora del Login
    AuroraField {
        id: loginAurora
        anchors.fill: parent
        mode: 0
        motion: !root.reducedMotion
        lowPower: root.lowPower
        primaryColor: root.brandBlue
        accentColor: root.brandGreen
        tintColor: root.errorRed
        // Se detiene cuando el Home (opaco) ya cubre la pantalla.
        visible: (!root.welcomeVisible || welcomeLayer.opacity < 1)
                 && !(root.authenticatedVisible && authenticatedLayer.opacity >= 1)
    }

    // ---------------------------------------------- Continue: luz verde
    SequentialAnimation {
        id: continueFlow
        NumberAnimation { target: loginAurora; property: "boost"; to: 1.0; duration: 340; easing.type: Easing.InOutQuad }
        ScriptAction {
            script: {
                root.step = "PASSWORD"
                passwordField.input.forceActiveFocus()
            }
        }
        PauseAnimation { duration: 60 }
        NumberAnimation { target: loginAurora; property: "boost"; to: 0.0; duration: 400; easing.type: Easing.OutCubic }
    }

    // ------------------------------- Credenciales inválidas (sin mensaje)
    SequentialAnimation {
        id: credentialError
        ColorAnimation { target: loginAurora; property: "primaryColor"; to: root.brandGreen; duration: 150; easing.type: Easing.InOutSine }
        ColorAnimation { target: loginAurora; property: "primaryColor"; to: root.brandBlue; duration: 150; easing.type: Easing.InOutSine }
        ParallelAnimation {
            NumberAnimation { target: loginAurora; property: "tintAmount"; to: 1.0; duration: 120; easing.type: Easing.OutQuad }
            SequentialAnimation {
                NumberAnimation { target: formShake; property: "x"; to: -9 * root.u; duration: 55; easing.type: Easing.OutQuad }
                NumberAnimation { target: formShake; property: "x"; to: 8 * root.u; duration: 75; easing.type: Easing.InOutQuad }
                NumberAnimation { target: formShake; property: "x"; to: -5 * root.u; duration: 65; easing.type: Easing.InOutQuad }
                NumberAnimation { target: formShake; property: "x"; to: 3 * root.u; duration: 55; easing.type: Easing.InOutQuad }
                NumberAnimation { target: formShake; property: "x"; to: 0; duration: 50; easing.type: Easing.OutQuad }
            }
        }
        NumberAnimation { target: loginAurora; property: "tintAmount"; to: 0.0; duration: 240; easing.type: Easing.InOutSine }
    }
    SequentialAnimation {
        id: errorTintOnly
        NumberAnimation { target: loginAurora; property: "tintAmount"; to: 0.8; duration: 160 }
        PauseAnimation { duration: 200 }
        NumberAnimation { target: loginAurora; property: "tintAmount"; to: 0.0; duration: 300 }
    }
    SequentialAnimation {
        id: shakeOnly
        NumberAnimation { target: formShake; property: "x"; to: -6 * root.u; duration: 60 }
        NumberAnimation { target: formShake; property: "x"; to: 5 * root.u; duration: 80 }
        NumberAnimation { target: formShake; property: "x"; to: -3 * root.u; duration: 60 }
        NumberAnimation { target: formShake; property: "x"; to: 0; duration: 60 }
    }

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
        Behavior on opacity { OpacityAnimator { duration: root.reducedMotion ? 0 : 280 } }

        // Paso contraseña: Back vuelve al usuario sin salir de la app.
        Keys.onBackPressed: function(event) {
            if (root.step === "PASSWORD" && !root.submitting && !root.sessionLocked) {
                root.backToUser()
                event.accepted = true
            } else {
                event.accepted = false
            }
        }

        Item {
            id: formShake
            width: loginLayer.width
            height: loginLayer.contentHeight

            Column {
                id: loginForm
                x: root.gutter
                width: parent.width - 2 * root.gutter
                // Bloque inferior como en el preview; con teclado (adjustResize)
                // la ventana se reduce y el bloque sube sin recortarse.
                y: Math.max(root.gutter, loginLayer.contentHeight - height
                            - Math.max(42 * root.u, loginLayer.height * 0.085))

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

                Item { width: 1; height: 34 * root.u }

                Text {
                    text: "Login"
                    color: root.white
                    font.family: rubik.font.family
                    font.pixelSize: 25 * root.u
                    Accessible.role: Accessible.Heading
                }
                Item { width: 1; height: 6 * root.u }
                Text {
                    width: loginForm.width
                    text: "Por favor ingrese su usuario y contraseña"
                    color: Qt.rgba(1, 1, 1, 0.88)
                    font.family: rubik.font.family
                    font.pixelSize: 15 * root.u
                    wrapMode: Text.WordWrap
                }

                Item { width: 1; height: 36 * root.u }

                // Un solo campo visible: usuario o contraseña, en la misma posición.
                Item {
                    id: fieldSlot
                    width: loginForm.width
                    height: 52 * root.u
                    visible: root.screenState !== "RESTORING_SESSION"

                    LineField {
                        id: userField
                        anchors.fill: parent
                        placeholder: "usuario"
                        shown: root.step === "USER"
                        unit: root.u
                        fontFamily: rubik.font.family
                        accent: root.brandGreen
                        input.inputMethodHints: Qt.ImhEmailCharactersOnly | Qt.ImhNoAutoUppercase | Qt.ImhNoPredictiveText
                        input.enabled: root.step === "USER" && !root.submitting
                        Accessible.name: "usuario"
                        onAccepted: root.continueToPassword()
                    }
                    LineField {
                        id: passwordField
                        anchors.fill: parent
                        placeholder: "contraseña"
                        shown: root.step === "PASSWORD"
                        unit: root.u
                        fontFamily: rubik.font.family
                        accent: root.brandGreen
                        input.echoMode: TextInput.Password
                        input.inputMethodHints: Qt.ImhHiddenText | Qt.ImhSensitiveData | Qt.ImhNoPredictiveText | Qt.ImhNoAutoUppercase
                        input.enabled: root.step === "PASSWORD" && !root.submitting
                        Accessible.name: "contraseña"
                        onAccepted: root.submitPassword()
                    }
                }

                // Hueco del segundo campo del preview: los campos se muestran de uno
                // en uno, pero el botón conserva la posición aprobada.
                Item {
                    width: loginForm.width
                    height: 112 * root.u
                    visible: fieldSlot.visible
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

                // Botón: Continue → Let's Go (mismo tamaño, estilo y lugar).
                Rectangle {
                    id: primaryButton
                    width: loginForm.width
                    height: 60 * root.u
                    radius: 15 * root.u
                    visible: fieldSlot.visible
                    opacity: root.submitting ? 0.7 : (tap.pressed ? 0.88 : 1)
                    border.width: 1
                    border.color: Qt.rgba(0.55, 0.78, 1.0, 0.75)
                    gradient: Gradient {
                        GradientStop { position: 0.0; color: Qt.tint(root.brandBlue, Qt.rgba(1, 1, 1, 0.06)) }
                        GradientStop { position: 0.62; color: root.brandBlue }
                        GradientStop { position: 1.0; color: Qt.tint(root.brandBlue, Qt.rgba(0.62, 0.86, 1.0, 0.55)) }
                    }
                    Text {
                        anchors.centerIn: parent
                        text: root.step === "PASSWORD" ? "Let's Go" : "Continue"
                        color: root.white
                        font.family: rubik.font.family
                        font.pixelSize: 19 * root.u
                    }
                    MouseArea {
                        id: tap
                        anchors.fill: parent
                        enabled: !root.submitting && !continueFlow.running
                        onClicked: root.step === "PASSWORD" ? root.submitPassword()
                                                            : root.continueToPassword()
                    }
                    Accessible.role: Accessible.Button
                    Accessible.name: root.step === "PASSWORD" ? "Let's Go" : "Continue"
                    Accessible.onPressAction: root.step === "PASSWORD" ? root.submitPassword()
                                                                      : root.continueToPassword()
                }

                // Fallos que no son de credenciales (conexión, servicio, cuenta).
                Text {
                    width: loginForm.width
                    topPadding: 14 * root.u
                    visible: root.serviceMessage.length > 0 && fieldSlot.visible
                    text: root.serviceMessage
                    color: Qt.rgba(1, 1, 1, 0.78)
                    font.family: rubik.font.family
                    font.pixelSize: 14 * root.u
                    wrapMode: Text.WordWrap
                    horizontalAlignment: Text.AlignHCenter
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
        Behavior on opacity { OpacityAnimator { duration: root.reducedMotion ? 0 : 420; easing.type: Easing.InOutSine } }

        AuroraField {
            anchors.fill: parent
            mode: 1
            motion: !root.reducedMotion
            lowPower: root.lowPower
            primaryColor: root.brandBlue
            accentColor: root.brandGreen
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
                text: "Welcome to InGe+"
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
                    text: "Get Started"
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
                Accessible.name: "Get Started"
                Accessible.onPressAction: getStartedFlow.restart()
            }
            Item { width: 1; height: 30 * root.u }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                textFormat: Text.StyledText
                text: "Already have an account? <b>Log in</b>"
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
                Accessible.name: "Log in con otra cuenta"
            }
        }
    }

    // Get Started: fundido y bienvenida completada (persistida en QSettings).
    SequentialAnimation {
        id: getStartedFlow
        ScriptAction { script: root.leavingWelcome = true }
        PauseAnimation { duration: root.reducedMotion ? 0 : 420 }
        ScriptAction {
            script: {
                if (root.onboardingReady)
                    onboarding.completeWelcome()
                root.leavingWelcome = false
            }
        }
    }

    // ===================================================== AUTENTICADO
    // Home V1 (HomeScreen.qml). Entrada: la misma luz de la aurora del Login
    // (boost) crece desde la esquina superior derecha y, en su pico, aparece
    // el Home; luego la luz se desvanece y la aurora se detiene.
    property bool homeRevealed: false
    onAuthenticatedVisibleChanged: {
        if (authenticatedVisible) {
            if (reducedMotion) { homeRevealed = true } else { homeEntry.restart() }
        } else {
            homeEntry.stop()
            homeRevealed = false
            loginAurora.boost = 0
        }
    }
    SequentialAnimation {
        id: homeEntry
        NumberAnimation { target: loginAurora; property: "boost"; to: 0.8; duration: 280; easing.type: Easing.InQuad }
        ScriptAction { script: root.homeRevealed = true }
        NumberAnimation { target: loginAurora; property: "boost"; to: 0.0; duration: 320; easing.type: Easing.OutCubic }
    }

    HomeScreen {
        id: authenticatedLayer
        anchors.fill: parent
        u: root.u
        fontFamily: rubik.font.family
        iconFamily: lucide.font.family
        reducedMotion: root.reducedMotion
        opacity: root.authenticatedVisible && root.homeRevealed ? 1 : 0
        visible: opacity > 0
        Behavior on opacity { OpacityAnimator { duration: root.reducedMotion ? 0 : 300 } }
        onVisibleChanged: if (visible) forceActiveFocus()
        onSignOutRequested: root.signOutToLogin()
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
        visible: opacity > 0
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

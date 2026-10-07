import QtQuick 2.15
import QtQuick.Controls 2.15

Page {
    id: root

    // === ARM HYBRID PHONE/TABLET HELPERS ===
    readonly property real __armWidth:  width  > 0 ? width  : 420
    readonly property real __armHeight: height > 0 ? height : 820
    readonly property real __armMinSide: Math.min(__armWidth, __armHeight)
    readonly property bool __armPhone: __armMinSide < 600
    readonly property bool __armTablet: !__armPhone
    readonly property real __armScale: __armPhone
        ? Math.max(0.95, Math.min(1.16, __armMinSide / 390.0))
        : Math.max(1.05, Math.min(1.32, __armMinSide / 720.0))
    readonly property int __touchTarget: Math.round((__armPhone ? 56 : 60) * __armScale)
    readonly property int __touchPressDelay: 140
    readonly property real __flickVelocity: __armPhone ? 1600 : 2200
    function __dp(v) { return Math.round(v * __armScale) }
    function __sp(v) { return Math.max(12, Math.round(v * __armScale)) }

    title: "Iniciar sesión"

    signal requestEnterApp()
    signal requestEnterOffline()
    signal requestRegister()

    // ✅ ahora SÍ existe, por eso ya no sale "Invalid property name auth"
    property var auth: null

    property bool busy: false

    LoginPageForm {
        id: ui
        anchors.fill: parent
        busy: root.busy
    }

    function setError(msg, ok) {
        ui.txtError.text = msg
        ui.txtError.color = ok ? "#1b5e20" : "red"
        ui.txtError.opacity = (msg && msg.length) ? 1 : 0
    }

    function isValidEmail(s) {
        s = (s || "").trim()
        return /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(s)
    }

    function markLoginInvalid(emailBad, passBad) {
        ui.emailInvalid = !!emailBad
        ui.passInvalid  = !!passBad
        ui.recalcValidation()
    }

    function doLogin() {
        if (root.busy) return
        if (!root.auth) { setError("Auth no inicializado (auth == null).", false); return }

        ui.clearValidation()
        setError("", true)

        var email = (ui.emailField.text || "").trim()
        var pass  = (ui.passField.text  || "")

        if (!email.length || !pass.length) {
            markLoginInvalid(!email.length, !pass.length)
            setError("Ingresa usuario/email y contraseña.", false)
            return
        }

        if (!isValidEmail(email)) {
            markLoginInvalid(true, false)
            setError("Correo inválido.", false)
            return
        }

        root.busy = true
        root.auth.signInWithPassword(email, pass)
    }

    // clicks
    Connections { target: ui.btnLogin;   function onClicked() { doLogin() } }

    Connections {
        target: ui.btnOffline
        function onClicked() {
            if (root.auth) root.auth.signOut()
            root.requestEnterOffline()
        }
    }

    Connections { target: ui.btnCreate;  function onClicked() { root.requestRegister() } }

    // Enter flow
    Connections { target: ui.emailField; function onAccepted() { ui.passField.forceActiveFocus() } }
    Connections { target: ui.passField;  function onAccepted() { doLogin() } }

    // señales C++ AuthSession
    Connections {
        target: root.auth ? root.auth : null

        function onLoginOk() {
            root.busy = false
            ui.clearValidation()
            setError("", true)
            root.requestEnterApp()
        }

        function onLoginFail(msg) {
            root.busy = false
            markLoginInvalid(false, true)
            setError(msg && msg.length ? msg : "No se pudo iniciar sesión.", false)
        }
    }

    onVisibleChanged: if (visible) {
        root.busy = false
        ui.clearValidation()
        setError("", true)
    }
}

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

    title: "Registro"

    signal requestBack()
    signal requestGoLogin()

    // ✅ ahora SÍ existe, por eso ya no sale "Invalid property name auth"
    property var auth: null

    property bool busy: false

    RegisterPageForm {
        id: ui
        anchors.fill: parent
        busy: root.busy
    }

    function setMsg(msg, ok) {
        ui.txtError.text = msg
        ui.txtError.color = ok ? "#1b5e20" : "red"
        ui.txtError.opacity = (msg && msg.length) ? 1 : 0
    }

    function isValidEmail(s) {
        s = (s || "").trim()
        return /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(s)
    }

    function passwordPolicyMessage(p) {
        var miss = []
        if ((p || "").length < 8) miss.push("mínimo 8 caracteres")
        if (!/[A-Z]/.test(p || "")) miss.push("1 mayúscula")
        if (!/[a-z]/.test(p || "")) miss.push("1 minúscula")
        if (!/[0-9]/.test(p || "")) miss.push("1 número")
        return miss.length ? ("La contraseña debe incluir: " + miss.join(", ") + ".") : ""
    }

    function markRegisterInvalids(nombre, apellido, email, phone, pass1, pass2) {
        ui.nombreInvalid   = !nombre.length
        ui.apellidoInvalid = !apellido.length
        ui.emailInvalid    = !email.length || !isValidEmail(email)
        ui.phoneInvalid    = !phone.length
        ui.pass1Invalid    = !pass1.length
        ui.pass2Invalid    = !pass2.length
        ui.recalcValidation()
    }

    function doRegister() {
        if (root.busy) return
        if (!root.auth) { setMsg("Auth no inicializado.", false); return }

        ui.clearValidation()
        setMsg("", true)

        var nombre   = (ui.nombreField.text  || "").trim()
        var apellido = (ui.apellidoField.text|| "").trim()
        var email    = (ui.emailField.text   || "").trim()
        var phone    = (ui.phoneField.text   || "").trim()
        var pass1    = (ui.pass1Field.text   || "")
        var pass2    = (ui.pass2Field.text   || "")

        if (!nombre || !apellido || !email || !phone || !pass1 || !pass2) {
            markRegisterInvalids(nombre, apellido, email, phone, pass1, pass2)
            setMsg("Completa todos los campos.", false)
            return
        }

        if (!isValidEmail(email)) {
            ui.emailInvalid = true
            ui.recalcValidation()
            setMsg("Correo inválido.", false)
            return
        }

        if (pass1 !== pass2) {
            ui.pass1Invalid = true
            ui.pass2Invalid = true
            ui.recalcValidation()
            setMsg("Las contraseñas no coinciden.", false)
            return
        }

        var pol = passwordPolicyMessage(pass1)
        if (pol.length) {
            ui.pass1Invalid = true
            ui.recalcValidation()
            setMsg(pol, false)
            return
        }

        setMsg("Enviando enlace de confirmación a " + email + "...", true)
        root.busy = true
        root.auth.signUpWithEmail(email, pass1, nombre, apellido, phone)
    }

    Connections {
        target: ui.btnBack
        function onClicked() {
            root.busy = false
            ui.clearValidation()
            setMsg("", true)
            root.requestBack()
        }
    }

    Connections { target: ui.btnRegister; function onClicked() { doRegister() } }

    // Enter flow
    Connections { target: ui.nombreField;   function onAccepted(){ ui.apellidoField.forceActiveFocus() } }
    Connections { target: ui.apellidoField; function onAccepted(){ ui.emailField.forceActiveFocus() } }
    Connections { target: ui.emailField;    function onAccepted(){ ui.phoneField.forceActiveFocus() } }
    Connections { target: ui.phoneField;    function onAccepted(){ ui.pass1Field.forceActiveFocus() } }
    Connections { target: ui.pass1Field;    function onAccepted(){ ui.pass2Field.forceActiveFocus() } }
    Connections { target: ui.pass2Field;    function onAccepted(){ doRegister() } }

    // ✅ Señales C++ AuthSession (antes estaba: target: auth -> podía ser null o el global)
    Connections {
        target: root.auth ? root.auth : null

        function onSignUpOk() {
            root.busy = false
            ui.clearValidation()
            setMsg("✅ Registro enviado. Revisa tu correo.", true)
            root.requestGoLogin()
        }

        function onSignUpFail(msg) {
            root.busy = false
            setMsg(msg && msg.length ? msg : "No se pudo crear la cuenta.", false)
        }
    }

    onVisibleChanged: if (visible) {
        root.busy = false
        ui.clearValidation()
        setMsg("", true)
    }
}

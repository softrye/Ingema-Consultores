import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15
import InGe.CoreFlow 3.0 as Mobile
import "../flowcore" as FlowCore

Page {
    id: root

    required property var auth

    property bool flowMotionEnabled: true
    property bool flowReduceMotion: false
    property int flowMotionLevel: 2

    property string greetingText: "Hola, " + displayName()
    property string subGreetingText: "Perfil y estado de sesión"
    property bool showSearch: false

    signal requestLogout()

    function valueOf(name) {
        if (!auth || auth[name] === undefined || auth[name] === null)
            return ""
        var value = auth[name]
        return (typeof value === "function") ? value() : value
    }

    function clean(value, fallbackValue) {
        try {
            var textValue = value === undefined || value === null ? "" : String(value)
            textValue = textValue.replace(/^\s+|\s+$/g, "")
            return textValue.length > 0 ? textValue : fallbackValue
        } catch(e) {
            return fallbackValue
        }
    }

    function isLogged() {
        return Boolean(auth && auth.logged === true)
    }

    function displayName() {
        var firstName = clean(valueOf("nombre"), "")
        var lastName = clean(valueOf("apellido"), "")
        var fullName = clean(firstName + " " + lastName, "")
        if (fullName.length > 0)
            return fullName

        var email = clean(valueOf("email"), "")
        if (email.length > 0)
            return email.indexOf("@") > 0 ? email.split("@")[0] : email

        return isLogged() ? "Usuario" : "Invitado"
    }

    function emailText() {
        return clean(valueOf("email"), "No registrado")
    }

    function phoneText() {
        return clean(valueOf("phone"), "No registrado")
    }

    function roleText() {
        if (!isLogged())
            return "Invitado"

        var candidates = [valueOf("role"), valueOf("userRole"), valueOf("profileRole")]
        for (var i = 0; i < candidates.length; ++i) {
            var candidate = clean(candidates[i], "")
            if (candidate.length > 0)
                return candidate
        }
        return "No registrado"
    }

    function initials() {
        var raw = clean(displayName(), "U")
        var parts = raw.split(/\s+/)
        if (parts.length >= 2)
            return (parts[0].charAt(0) + parts[1].charAt(0)).toUpperCase()
        return raw.substring(0, Math.min(2, raw.length)).toUpperCase()
    }

    function closeSession() {
        if (!isLogged())
            return

        try {
            if (auth && auth.signOut)
                auth.signOut()
            else if (auth && auth.logout)
                auth.logout()
        } catch(e) {}

        root.requestLogout()
    }


    background: Rectangle { color: "#FFFFFF" }
    ScrollView {
        anchors.fill: parent
        clip: true
        contentWidth: availableWidth
        ColumnLayout {
            width: parent.width
            spacing: 10
            anchors.margins: 12
            Label { Layout.fillWidth: true; text: "Perfil"; font.bold: true }
            Label { Layout.fillWidth: true; text: "Nombre: " + root.displayName(); wrapMode: Text.Wrap }
            Label { Layout.fillWidth: true; text: "Correo: " + root.emailText(); wrapMode: Text.Wrap }
            Label { Layout.fillWidth: true; text: "Telefono: " + root.phoneText(); wrapMode: Text.Wrap }
            Label { Layout.fillWidth: true; text: "Rol: " + root.roleText(); wrapMode: Text.Wrap }
            Label { Layout.fillWidth: true; text: root.isLogged() ? "Sesion activa" : "Sesion cerrada" }
            Button {
                Layout.fillWidth: true
                text: "Cerrar sesion"
                enabled: root.isLogged()
                onClicked: root.closeSession()
            }
        }
    }
}

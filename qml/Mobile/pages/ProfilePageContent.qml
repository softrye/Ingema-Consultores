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

    readonly property var pageFlow: Mobile.InGeCoreFlow



    background: Rectangle {
        color: "#F4F7FB"
    }

    ScrollView {
        anchors.fill: parent
        clip: true
        contentWidth: availableWidth

        ColumnLayout {
            width: parent.width
            spacing: 14
            anchors.margins: 16

            Rectangle {
                Layout.fillWidth: true
                implicitHeight: 154
                radius: 22
                color: "#FFFFFF"
                border.color: "#DDE7F2"
                border.width: 1

                RowLayout {
                    anchors.fill: parent
                    anchors.margins: 18
                    spacing: 16

                    Rectangle {
                        Layout.preferredWidth: 86
                        Layout.preferredHeight: 86
                        radius: 43
                        color: "#EAF4FF"
                        border.color: "#0654A2"
                        border.width: 2

                        Label {
                            anchors.centerIn: parent
                            text: root.initials()
                            color: "#0654A2"
                            font.pixelSize: 28
                            font.bold: true
                        }
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 5

                        Label {
                            Layout.fillWidth: true
                            text: root.displayName()
                            color: "#151A30"
                            font.pixelSize: 21
                            font.bold: true
                            elide: Text.ElideRight
                        }

                        Label {
                            Layout.fillWidth: true
                            text: root.emailText()
                            color: "#667085"
                            font.pixelSize: 13
                            elide: Text.ElideRight
                        }

                        Label {
                            Layout.fillWidth: true
                            text: root.isLogged() ? "Sesión activa" : "Sin sesión iniciada"
                            color: root.isLogged() ? "#496426" : "#667085"
                            font.pixelSize: 12
                            font.bold: true
                        }
                    }
                }
            }

            Rectangle {
                Layout.fillWidth: true
                implicitHeight: 168
                radius: 22
                color: "#FFFFFF"
                border.color: "#DDE7F2"
                border.width: 1

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 18
                    spacing: 12

                    Label {
                        Layout.fillWidth: true
                        text: "Datos de cuenta"
                        color: "#151A30"
                        font.pixelSize: 19
                        font.bold: true
                    }

                    Label {
                        Layout.fillWidth: true
                        text: "Correo: " + root.emailText()
                        color: "#151A30"
                        font.pixelSize: 13
                        wrapMode: Text.WordWrap
                    }

                    Label {
                        Layout.fillWidth: true
                        text: "Teléfono: " + root.phoneText()
                        color: "#151A30"
                        font.pixelSize: 13
                        wrapMode: Text.WordWrap
                    }

                    Label {
                        Layout.fillWidth: true
                        text: "Rol: " + root.roleText()
                        color: "#0654A2"
                        font.pixelSize: 13
                        font.bold: true
                        wrapMode: Text.WordWrap
                    }
                }
            }

            Button {
                Layout.fillWidth: true
                visible: root.isLogged()
                text: "Cerrar sesión"
                onClicked: root.closeSession()

                background: Rectangle {
                    radius: 14
                    color: parent.down ? "#FFF0EE" : "#FFFFFF"
                    border.color: "#DDE7F2"
                    border.width: 1
                }

                contentItem: Label {
                    text: parent.text
                    color: "#B42318"
                    font.pixelSize: 13
                    font.bold: true
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                }
            }

            Label {
                Layout.fillWidth: true
                visible: !root.isLogged()
                text: "Inicia sesión desde la pantalla principal para administrar tu cuenta."
                color: "#667085"
                font.pixelSize: 12
                wrapMode: Text.WordWrap
                horizontalAlignment: Text.AlignHCenter
            }

            Item {
                Layout.fillWidth: true
                implicitHeight: 20
            }
        }
    }
}

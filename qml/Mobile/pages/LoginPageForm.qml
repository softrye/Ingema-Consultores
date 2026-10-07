import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15
import InGe.CoreFlow 3.0 as Mobile
import "../flowcore" as FlowCore

Item {
    id: root

    property bool flowMotionEnabled: true
    property bool flowReduceMotion: false
    property int flowMotionLevel: 2

    readonly property var pageFlow: Mobile.InGeCoreFlow



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

    width:  StackView.view ? StackView.view.width  : (parent ? parent.width  : 420)
    height: StackView.view ? StackView.view.height : (parent ? parent.height : 820)

    property bool busy: false

    // ===== Validación visual =====
    property bool showValidation: false
    property bool emailInvalid: false
    property bool passInvalid: false

    function recalcValidation() { showValidation = emailInvalid || passInvalid }
    function clearValidation() {
        emailInvalid = false
        passInvalid = false
        showValidation = false
    }

    // Exponer widgets al wrapper
    property alias emailField: tfEmail
    property alias passField:  tfPass
    property alias btnLogin:   bLogin
    property alias btnOffline: bOffline
    property alias btnCreate:  bCreate
    property alias txtError:   lblError

    Rectangle {
        anchors.fill: parent
        gradient: Gradient {
            GradientStop { position: 0.0; color: "#E3F2FD" }
            GradientStop { position: 1.0; color: "#FFFFFF" }
        }
    }

    ColumnLayout {
        id: col
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.verticalCenter: parent.verticalCenter
        anchors.verticalCenterOffset: root.__armPhone ? -root.__dp(4) : -root.__dp(10)

        property real desiredW: parent.width * (root.__armPhone ? 0.90 : 0.62)
        width: Math.min(root.__dp(root.__armPhone ? 420 : 520), desiredW)
        spacing: root.__dp(12)

        // ✅ FIX: limitar ancho del logo (evita “cortado”)
        Image {
            source: "qrc:/ui/v2/branding/logo_oficial_ingeplus_light.png"
            sourceClipRect: Qt.rect(297, 175, 397, 150)
            fillMode: Image.PreserveAspectFit
            smooth: true
            Layout.alignment: Qt.AlignHCenter

            Layout.preferredWidth: (col.width > 360 ? 360 : col.width)
            Layout.maximumWidth:  (col.width > 360 ? 360 : col.width)
            Layout.preferredHeight: root.__dp(root.__armPhone ? 112 : 132)
        }

        TextField {
            id: tfEmail
            scale: activeFocus ? pageFlow.focusScale : 1.0
            transformOrigin: Item.Center
            Behavior on scale { NumberAnimation { duration: pageFlow.normalDuration; easing.type: pageFlow.easeOut } }
            Layout.fillWidth: true
            placeholderText: "Correo Electrónico"
            enabled: !root.busy

            color: "#0D47A1"
            font.pixelSize: root.__sp(14)
            inputMethodHints: Qt.ImhEmailCharactersOnly | Qt.ImhNoAutoUppercase
            padding: root.__dp(12)

            // ✅ mejor que textEdited (también cubre “pegar” y set programático)
            onTextChanged: {
                if (root.emailInvalid) root.emailInvalid = false
                root.recalcValidation()
            }

            background: Rectangle {
                radius: 10
                color: (root.showValidation && root.emailInvalid) ? "#fffafa"
                      : (tfEmail.activeFocus ? "#E3F2FD" : "#FFFFFF")
                border.width: 2
                border.color: (root.showValidation && root.emailInvalid) ? "#d93025"
                             : (tfEmail.activeFocus ? "#1E88E5" : "#90CAF9")
            }
        }

        // Password + ojo
        Item {
            Layout.fillWidth: true
            height: tfPass.implicitHeight

            TextField {
                id: tfPass
            scale: activeFocus ? pageFlow.focusScale : 1.0
            transformOrigin: Item.Center
            Behavior on scale { NumberAnimation { duration: pageFlow.normalDuration; easing.type: pageFlow.easeOut } }
                anchors.fill: parent
                placeholderText: "Contraseña"
                enabled: !root.busy

                echoMode: eye.checked ? TextInput.Normal : TextInput.Password
                color: "#0D47A1"
                font.pixelSize: root.__sp(14)
                padding: root.__dp(12)
                rightPadding: root.__touchTarget
                inputMethodHints: Qt.ImhNoPredictiveText | Qt.ImhNoAutoUppercase | Qt.ImhSensitiveData

                onTextChanged: {
                    if (root.passInvalid) root.passInvalid = false
                    root.recalcValidation()
                }

                background: Rectangle {
                    radius: 10
                    color: (root.showValidation && root.passInvalid) ? "#fffafa"
                          : (tfPass.activeFocus ? "#E3F2FD" : "#FFFFFF")
                    border.width: 2
                    border.color: (root.showValidation && root.passInvalid) ? "#d93025"
                                 : (tfPass.activeFocus ? "#1E88E5" : "#90CAF9")
                }
            }

            ToolButton {
                id: eye
                scale: down ? pageFlow.compactPressScale : 1.0
                Behavior on scale { NumberAnimation { duration: pageFlow.fastDuration; easing.type: pageFlow.easeOut } }
                width: root.__touchTarget; height: root.__touchTarget
                anchors.right: parent.right
                anchors.rightMargin: root.__dp(4)
                anchors.verticalCenter: parent.verticalCenter
                checkable: true
                checked: false
                enabled: !root.busy

                // IMPORTANTE: no uses icon.source (evita el tint)
                background: Rectangle { color: "transparent" }

                contentItem: Image {
                    anchors.centerIn: parent
                    source: eye.checked ? "qrc:/icons/OJO_OPEN.png" : "qrc:/icons/OJO_CLOSE.png"
                    sourceSize.width: root.__dp(24)
                    sourceSize.height: root.__dp(24)
                    width: root.__dp(24)
                    height: root.__dp(24)
                    fillMode: Image.PreserveAspectFit
                    smooth: true
                    mipmap: true
                    opacity: eye.enabled ? 1.0 : 0.4
                }
            }

        }

        Text {
            id: lblError
            Layout.fillWidth: true
            text: ""
            color: "red"
            font.pixelSize: root.__sp(13)
            font.bold: true
            opacity: 0.0
            wrapMode: Text.Wrap
            Behavior on opacity { NumberAnimation { duration: 250 } }
        }

        // ✅ COMO PC: el botón SIEMPRE habilitado (salvo busy). La validación se hace en el wrapper.
        Button {
            id: bLogin
            scale: down ? pageFlow.pressScale : 1.0
            transformOrigin: Item.Center
            Behavior on scale { NumberAnimation { duration: down ? pageFlow.instantDuration : pageFlow.normalDuration; easing.type: down ? pageFlow.easeOut : pageFlow.easeOvershoot } }
            Layout.preferredHeight: root.__touchTarget
            Layout.fillWidth: true
            text: root.busy ? "Procesando..." : "Iniciar sesión"
            enabled: !root.busy

            background: Rectangle {
                radius: 12
                color: !bLogin.enabled ? "#90CAF9"
                     : (bLogin.down ? "#1565C0" : (bLogin.hovered ? "#1976D2" : "#2196F3"))
            }
            contentItem: Text {
                text: bLogin.text
                color: "white"
                font.pixelSize: root.__sp(14)
                font.bold: true
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
            }
        }

        Button {
            id: bOffline
            scale: down ? pageFlow.pressScale : 1.0
            transformOrigin: Item.Center
            Behavior on scale { NumberAnimation { duration: down ? pageFlow.instantDuration : pageFlow.normalDuration; easing.type: down ? pageFlow.easeOut : pageFlow.easeOvershoot } }
            Layout.preferredHeight: root.__touchTarget
            Layout.fillWidth: true
            text: "Modo Local"
            enabled: !root.busy

            background: Rectangle {
                radius: 12
                color: !bOffline.enabled ? "#BBDEFB"
                     : (bOffline.down ? "#1565C0" : (bOffline.hovered ? "#1976D2" : "#2196F3"))
            }
            contentItem: Text {
                text: bOffline.text
                color: "white"
                font.pixelSize: root.__sp(14)
                font.bold: true
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
            }
        }

        Button {
            id: bCreate
            scale: down ? pageFlow.pressScale : 1.0
            transformOrigin: Item.Center
            Behavior on scale { NumberAnimation { duration: down ? pageFlow.instantDuration : pageFlow.normalDuration; easing.type: down ? pageFlow.easeOut : pageFlow.easeOvershoot } }
            Layout.preferredHeight: root.__touchTarget
            Layout.fillWidth: true
            text: "Crear una Cuenta"
            enabled: !root.busy

            background: Rectangle {
                radius: 12
                color: !bCreate.enabled ? "#BBDEFB"
                     : (bCreate.down ? "#1565C0" : (bCreate.hovered ? "#1976D2" : "#2196F3"))
            }
            contentItem: Text {
                text: bCreate.text
                color: "white"
                font.pixelSize: root.__sp(14)
                font.bold: true
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
            }
        }
    }

    Text {
        text: "© Imgema SAC"
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 10
        anchors.horizontalCenter: parent.horizontalCenter
        color: "#0D47A1"
        opacity: 0.7
        font.pixelSize: root.__sp(13)
        font.italic: true
    }
}

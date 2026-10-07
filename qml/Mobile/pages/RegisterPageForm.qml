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
    property bool nombreInvalid: false
    property bool apellidoInvalid: false
    property bool emailInvalid: false
    property bool phoneInvalid: false
    property bool pass1Invalid: false
    property bool pass2Invalid: false

    function recalcValidation() {
        showValidation = nombreInvalid || apellidoInvalid || emailInvalid || phoneInvalid || pass1Invalid || pass2Invalid
    }
    function clearValidation() {
        nombreInvalid = false
        apellidoInvalid = false
        emailInvalid = false
        phoneInvalid = false
        pass1Invalid = false
        pass2Invalid = false
        showValidation = false
    }

    // ===== Aliases (compatibles con RegisterPage.qml) =====
    property alias nombreField:  tfNombre
    property alias apellidoField: tfApellido
    property alias phoneField:   tfPhone
    property alias pass1Field:   tfPass1
    property alias pass2Field:   tfPass2

    property alias emailField:   tfCorreo
    property alias correoField:  tfCorreo

    property alias txtError:     lblMsg
    property alias txtMsg:       lblMsg

    property alias btnRegister:  bReg
    property alias btnBack:      bBack

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
        anchors.verticalCenterOffset: root.__armPhone ? -root.__dp(2) : -root.__dp(10)

        property real desiredW: parent.width * (root.__armPhone ? 0.92 : 0.70)
        width: Math.min(root.__dp(root.__armPhone ? 520 : 680), desiredW)
        spacing: root.__dp(10)

        Image {
            source: "qrc:/ui/v2/branding/logo_oficial_ingeplus_light.png"
            sourceClipRect: Qt.rect(297, 175, 397, 150)
            fillMode: Image.PreserveAspectFit
            smooth: true
            Layout.alignment: Qt.AlignHCenter
            Layout.preferredWidth: (col.width > 360 ? 360 : col.width)
            Layout.maximumWidth:  (col.width > 360 ? 360 : col.width)
            Layout.preferredHeight: root.__dp(root.__armPhone ? 104 : 128)
        }

        GridLayout {
            columns: 2
            columnSpacing: root.__dp(10)
            rowSpacing: root.__dp(10)
            Layout.fillWidth: true

            TextField {
                id: tfNombre
            scale: activeFocus ? pageFlow.focusScale : 1.0
            transformOrigin: Item.Center
            Behavior on scale { NumberAnimation { duration: pageFlow.normalDuration; easing.type: pageFlow.easeOut } }
                Layout.fillWidth: true
                placeholderText: "Nombre"
                enabled: !root.busy
                color: "#0D47A1"
                padding: root.__dp(12)
                onTextChanged: { if (root.nombreInvalid) root.nombreInvalid = false; root.recalcValidation() }
                background: Rectangle {
                    radius: 10
                    color: (root.showValidation && root.nombreInvalid) ? "#fffafa" : (tfNombre.activeFocus ? "#E3F2FD" : "#FFFFFF")
                    border.width: 2
                    border.color: (root.showValidation && root.nombreInvalid) ? "#d93025" : (tfNombre.activeFocus ? "#1E88E5" : "#90CAF9")
                }
            }

            TextField {
                id: tfApellido
            scale: activeFocus ? pageFlow.focusScale : 1.0
            transformOrigin: Item.Center
            Behavior on scale { NumberAnimation { duration: pageFlow.normalDuration; easing.type: pageFlow.easeOut } }
                Layout.fillWidth: true
                placeholderText: "Apellido"
                enabled: !root.busy
                color: "#0D47A1"
                padding: root.__dp(12)
                onTextChanged: { if (root.apellidoInvalid) root.apellidoInvalid = false; root.recalcValidation() }
                background: Rectangle {
                    radius: 10
                    color: (root.showValidation && root.apellidoInvalid) ? "#fffafa" : (tfApellido.activeFocus ? "#E3F2FD" : "#FFFFFF")
                    border.width: 2
                    border.color: (root.showValidation && root.apellidoInvalid) ? "#d93025" : (tfApellido.activeFocus ? "#1E88E5" : "#90CAF9")
                }
            }
        }

        TextField {
            id: tfCorreo
            scale: activeFocus ? pageFlow.focusScale : 1.0
            transformOrigin: Item.Center
            Behavior on scale { NumberAnimation { duration: pageFlow.normalDuration; easing.type: pageFlow.easeOut } }
            Layout.fillWidth: true
            placeholderText: "Correo Electrónico"
            enabled: !root.busy
            color: "#0D47A1"
            padding: root.__dp(12)
            inputMethodHints: Qt.ImhEmailCharactersOnly | Qt.ImhNoAutoUppercase
            onTextChanged: { if (root.emailInvalid) root.emailInvalid = false; root.recalcValidation() }
            background: Rectangle {
                radius: 10
                color: (root.showValidation && root.emailInvalid) ? "#fffafa" : (tfCorreo.activeFocus ? "#E3F2FD" : "#FFFFFF")
                border.width: 2
                border.color: (root.showValidation && root.emailInvalid) ? "#d93025" : (tfCorreo.activeFocus ? "#1E88E5" : "#90CAF9")
            }
        }

        TextField {
            id: tfPhone
            scale: activeFocus ? pageFlow.focusScale : 1.0
            transformOrigin: Item.Center
            Behavior on scale { NumberAnimation { duration: pageFlow.normalDuration; easing.type: pageFlow.easeOut } }
            Layout.fillWidth: true
            placeholderText: "Teléfono"
            enabled: !root.busy
            color: "#0D47A1"
            padding: root.__dp(12)
            inputMethodHints: Qt.ImhDigitsOnly
            onTextChanged: { if (root.phoneInvalid) root.phoneInvalid = false; root.recalcValidation() }
            background: Rectangle {
                radius: 10
                color: (root.showValidation && root.phoneInvalid) ? "#fffafa" : (tfPhone.activeFocus ? "#E3F2FD" : "#FFFFFF")
                border.width: 2
                border.color: (root.showValidation && root.phoneInvalid) ? "#d93025" : (tfPhone.activeFocus ? "#1E88E5" : "#90CAF9")
            }
        }

        // Pass 1
        Item {
            Layout.fillWidth: true
            height: tfPass1.implicitHeight

            TextField {
                id: tfPass1
            scale: activeFocus ? pageFlow.focusScale : 1.0
            transformOrigin: Item.Center
            Behavior on scale { NumberAnimation { duration: pageFlow.normalDuration; easing.type: pageFlow.easeOut } }
                anchors.fill: parent
                placeholderText: "Contraseña Nueva"
                enabled: !root.busy
                echoMode: eye1.checked ? TextInput.Normal : TextInput.Password
                color: "#0D47A1"
                padding: root.__dp(12)
                rightPadding: root.__touchTarget
                inputMethodHints: Qt.ImhNoPredictiveText | Qt.ImhNoAutoUppercase | Qt.ImhSensitiveData
                onTextChanged: { if (root.pass1Invalid) root.pass1Invalid = false; root.recalcValidation() }
                background: Rectangle {
                    radius: 10
                    color: (root.showValidation && root.pass1Invalid) ? "#fffafa" : (tfPass1.activeFocus ? "#E3F2FD" : "#FFFFFF")
                    border.width: 2
                    border.color: (root.showValidation && root.pass1Invalid) ? "#d93025" : (tfPass1.activeFocus ? "#1E88E5" : "#90CAF9")
                }
            }

            ToolButton {
                id: eye1
                scale: down ? pageFlow.compactPressScale : 1.0
                Behavior on scale { NumberAnimation { duration: pageFlow.fastDuration; easing.type: pageFlow.easeOut } }
                width: root.__touchTarget; height: root.__touchTarget
                anchors.right: parent.right
                anchors.rightMargin: root.__dp(4)
                anchors.verticalCenter: parent.verticalCenter
                checkable: true
                checked: false
                enabled: !root.busy

                icon.source: ""
                background: Rectangle { color: "transparent" }

                contentItem: Image {
                    anchors.centerIn: parent
                    source: eye1.checked ? "qrc:/icons/OJO_OPEN.png" : "qrc:/icons/OJO_CLOSE.png"
                    sourceSize.width: root.__dp(24)
                    sourceSize.height: root.__dp(24)
                    width: root.__dp(24)
                    height: root.__dp(24)
                    fillMode: Image.PreserveAspectFit
                    smooth: true
                    mipmap: true
                    opacity: eye1.enabled ? 1.0 : 0.4
                }
            }

        }

        // Pass 2
        Item {
            Layout.fillWidth: true
            height: tfPass2.implicitHeight

            TextField {
                id: tfPass2
            scale: activeFocus ? pageFlow.focusScale : 1.0
            transformOrigin: Item.Center
            Behavior on scale { NumberAnimation { duration: pageFlow.normalDuration; easing.type: pageFlow.easeOut } }
                anchors.fill: parent
                placeholderText: "Confirmar la Contraseña"
                enabled: !root.busy
                echoMode: eye2.checked ? TextInput.Normal : TextInput.Password
                color: "#0D47A1"
                padding: root.__dp(12)
                rightPadding: root.__touchTarget
                inputMethodHints: Qt.ImhNoPredictiveText | Qt.ImhNoAutoUppercase | Qt.ImhSensitiveData
                onTextChanged: { if (root.pass2Invalid) root.pass2Invalid = false; root.recalcValidation() }
                background: Rectangle {
                    radius: 10
                    color: (root.showValidation && root.pass2Invalid) ? "#fffafa" : (tfPass2.activeFocus ? "#E3F2FD" : "#FFFFFF")
                    border.width: 2
                    border.color: (root.showValidation && root.pass2Invalid) ? "#d93025" : (tfPass2.activeFocus ? "#1E88E5" : "#90CAF9")
                }
            }

            ToolButton {
                id: eye2
                scale: down ? pageFlow.compactPressScale : 1.0
                Behavior on scale { NumberAnimation { duration: pageFlow.fastDuration; easing.type: pageFlow.easeOut } }
                width: root.__touchTarget; height: root.__touchTarget
                anchors.right: parent.right
                anchors.rightMargin: root.__dp(4)
                anchors.verticalCenter: parent.verticalCenter
                checkable: true
                checked: false
                enabled: !root.busy

                icon.source: ""
                background: Rectangle { color: "transparent" }

                contentItem: Image {
                    anchors.centerIn: parent
                    source: eye2.checked ? "qrc:/icons/OJO_OPEN.png" : "qrc:/icons/OJO_CLOSE.png"
                    sourceSize.width: root.__dp(24)
                    sourceSize.height: root.__dp(24)
                    width: root.__dp(24)
                    height: root.__dp(24)
                    fillMode: Image.PreserveAspectFit
                    smooth: true
                    mipmap: true
                    opacity: eye2.enabled ? 1.0 : 0.4
                }
            }

        }

        Text {
            Layout.fillWidth: true
            text: "Requisitos: 8+ caracteres, 1 mayúscula, 1 minúscula y 1 número."
            color: "#607d8b"
            font.pixelSize: root.__sp(12)
            wrapMode: Text.Wrap
        }

        Text {
            id: lblMsg
            Layout.fillWidth: true
            text: ""
            color: "red"
            font.pixelSize: root.__sp(13)
            font.bold: true
            opacity: 0.0
            wrapMode: Text.Wrap
            Behavior on opacity { NumberAnimation { duration: 250 } }
        }

        // ✅ COMO PC: siempre habilitado salvo busy
        Button {
            id: bReg
            scale: down ? pageFlow.pressScale : 1.0
            transformOrigin: Item.Center
            Behavior on scale { NumberAnimation { duration: down ? pageFlow.instantDuration : pageFlow.normalDuration; easing.type: down ? pageFlow.easeOut : pageFlow.easeOvershoot } }
            Layout.preferredHeight: root.__touchTarget
            Layout.fillWidth: true
            text: root.busy ? "Procesando..." : "Registrarme"
            enabled: !root.busy

            background: Rectangle {
                radius: 12
                color: !bReg.enabled ? "#90CAF9"
                     : (bReg.down ? "#1565C0" : (bReg.hovered ? "#1976D2" : "#2196F3"))
            }
            contentItem: Text {
                text: bReg.text
                color: "white"
                font.pixelSize: root.__sp(14)
                font.bold: true
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
            }
        }

        Button {
            id: bBack
            scale: down ? pageFlow.pressScale : 1.0
            transformOrigin: Item.Center
            Behavior on scale { NumberAnimation { duration: down ? pageFlow.instantDuration : pageFlow.normalDuration; easing.type: down ? pageFlow.easeOut : pageFlow.easeOvershoot } }
            Layout.preferredHeight: root.__touchTarget
            Layout.fillWidth: true
            text: "Volver a Iniciar"
            enabled: !root.busy

            background: Rectangle {
                radius: 12
                color: !bBack.enabled ? "#BBDEFB"
                     : (bBack.down ? "#1565C0" : (bBack.hovered ? "#1976D2" : "#2196F3"))
            }
            contentItem: Text {
                text: bBack.text
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

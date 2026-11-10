import QtQuick
import QtQuick.Controls
import "RStyle.js" as S

// Botón táctil de la subapp. Deshabilitado = sin acción (nunca decorativo).
Rectangle {
    id: button
    property var ui
    property string label: ""
    property int glyph: 0
    property bool primary: false
    property bool danger: false
    property bool busy: false
    property bool enabledButton: true
    signal activated()

    implicitHeight: 48 * ui.u
    // Medida independiente del Row: evita el ciclo ancho del texto <-> ancho del botón.
    readonly property real glyphSpace: glyph > 0 || busy ? 28 * ui.u : 0
    implicitWidth: glyphSpace + (label.length > 0 ? metrics.advanceWidth : 0) + 32 * ui.u
    TextMetrics {
        id: metrics
        text: button.label
        font.family: button.ui.fontFamily
        font.pixelSize: 15 * button.ui.u
        font.weight: button.primary ? Font.DemiBold : Font.Normal
    }
    radius: 14 * ui.u
    // Respuesta táctil: se hunde levemente al presionar.
    scale: tap.pressed && tap.enabled ? 0.96 : 1
    Behavior on scale { enabled: button.ui && button.ui.reducedMotion !== true
                        NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
    color: primary ? (tap.pressed ? Qt.darker(S.accent, 1.2) : S.accent)
                   : S.ink(tap.pressed ? 0.12 : 0.05)
    border.width: primary ? 0 : 1
    border.color: danger ? S.danger : S.border
    opacity: enabledButton ? 1 : 0.45

    Row {
        id: content
        anchors.centerIn: parent
        spacing: 8 * button.ui.u
        BusyIndicator {
            visible: button.busy
            running: button.busy
            width: 22 * button.ui.u
            height: width
            anchors.verticalCenter: parent.verticalCenter
        }
        Text {
            visible: button.glyph > 0 && !button.busy
            text: String.fromCharCode(button.glyph)
            font.family: button.ui.iconFamily
            font.pixelSize: 20 * button.ui.u
            color: button.danger ? S.danger : (button.primary ? S.onAccent : S.text)
            anchors.verticalCenter: parent.verticalCenter
        }
        Text {
            visible: button.label.length > 0
            text: button.label
            color: button.danger ? S.danger : (button.primary ? S.onAccent : S.text)
            font.family: button.ui.fontFamily
            font.pixelSize: 15 * button.ui.u
            font.weight: button.primary ? Font.DemiBold : Font.Normal
            anchors.verticalCenter: parent.verticalCenter
            elide: Text.ElideRight
            width: Math.max(0, Math.min(metrics.advanceWidth + 2, button.width - 32 * button.ui.u - button.glyphSpace))
        }
    }
    MouseArea {
        id: tap
        anchors.fill: parent
        enabled: button.enabledButton && !button.busy
        onClicked: button.activated()
    }
    Accessible.role: Accessible.Button
    Accessible.name: label
}

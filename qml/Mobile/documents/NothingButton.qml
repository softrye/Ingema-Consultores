// SPDX-License-Identifier: GPL-3.0-only
import QtQuick
import QtQuick.Controls
import InGe.CoreFlow 3.0 as Mobile

Button {
    id: control
    property string glyph: ""
    property bool filled: false
    // Identidad INGEMA: contorno/texto en el acento; relleno en la accion
    // primaria (INGEMA Blue) con texto blanco en cualquier modo.
    property color foreground: Mobile.InGeCoreFlow.theme.accent
    property color fill: Mobile.InGeCoreFlow.theme.actionPrimary
    property color onFill: Mobile.InGeCoreFlow.theme.onActionPrimary
    implicitHeight: 44
    implicitWidth: text.length ? Math.max(70, label.implicitWidth + 28) : 44
    padding: 10
    opacity: enabled ? 1 : 0.35
    background: Rectangle {
        radius: control.text.length ? 22 : width / 2
        color: control.filled ? control.fill : control.down ? Qt.rgba(control.foreground.r, control.foreground.g, control.foreground.b, 0.15) : "transparent"
    }
    contentItem: Item {
        implicitWidth: label.implicitWidth
        NothingIcon {
            anchors.centerIn: parent
            name: control.glyph
            visible: control.glyph.length > 0
            ink: control.filled ? control.onFill : control.foreground
        }
        Text {
            id: label
            anchors.centerIn: parent
            text: control.text
            visible: !control.glyph.length
            font.family: Mobile.InGeCoreFlow.typography.family
            font.pixelSize: 11
            font.bold: true
            color: control.filled ? control.onFill : control.foreground
        }
    }
    Accessible.name: text.length ? text : glyph
    ToolTip.visible: hovered && text.length === 0
    ToolTip.text: Accessible.name
}

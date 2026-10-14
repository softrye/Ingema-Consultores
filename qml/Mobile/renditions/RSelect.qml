import QtQuick
import QtQuick.Controls
import "RStyle.js" as S

// Selector táctil: opciones [{value, label, detail}] en una hoja modal.
Column {
    id: select
    property var ui
    property string label: ""
    property var options: []
    property string value: ""
    property string placeholder: "Seleccionar"
    property string error: ""
    property bool readOnly: false
    signal picked(string value)

    spacing: 6 * ui.u

    function labelFor(v) {
        for (var i = 0; i < options.length; ++i)
            if (String(options[i].value) === String(v))
                return String(options[i].label)
        return ""
    }

    Text {
        visible: select.label.length > 0
        text: select.label
        color: S.muted
        font.family: select.ui.fontFamily
        font.pixelSize: 13 * select.ui.u
    }
    Rectangle {
        width: parent.width
        height: 48 * select.ui.u
        radius: 12 * select.ui.u
        color: Qt.rgba(1, 1, 1, select.readOnly ? 0.03 : (fieldTap.pressed ? 0.14 : 0.08))
        border.width: 1
        border.color: select.error.length > 0 ? S.danger : S.border
        Text {
            x: 14 * select.ui.u
            width: parent.width - 52 * select.ui.u
            anchors.verticalCenter: parent.verticalCenter
            text: select.labelFor(select.value) || select.placeholder
            color: select.labelFor(select.value).length > 0 ? S.text : S.faint
            font.family: select.ui.fontFamily
            font.pixelSize: 16 * select.ui.u
            elide: Text.ElideRight
        }
        Text {
            visible: !select.readOnly
            anchors.right: parent.right
            anchors.rightMargin: 14 * select.ui.u
            anchors.verticalCenter: parent.verticalCenter
            text: String.fromCharCode(0xE06F)
            rotation: 90
            font.family: select.ui.iconFamily
            font.pixelSize: 18 * select.ui.u
            color: S.muted
        }
        MouseArea {
            id: fieldTap
            anchors.fill: parent
            enabled: !select.readOnly && select.options.length > 0
            onClicked: sheet.open()
        }
        Accessible.role: Accessible.ComboBox
        Accessible.name: select.label
    }
    Text {
        visible: select.error.length > 0
        width: parent.width
        text: select.error
        color: S.danger
        wrapMode: Text.WordWrap
        font.family: select.ui.fontFamily
        font.pixelSize: 13 * select.ui.u
    }

    Popup {
        id: sheet
        parent: Overlay.overlay
        modal: true
        focus: true
        width: Math.min(parent ? parent.width - 32 * select.ui.u : 360, 520 * select.ui.u)
        height: Math.min(list.contentHeight + 76 * select.ui.u, (parent ? parent.height : 640) * 0.7)
        x: parent ? (parent.width - width) / 2 : 0
        y: parent ? (parent.height - height) / 2 : 0
        padding: 0
        background: Rectangle { radius: 18 * select.ui.u; color: "#1A2440"; border.width: 1; border.color: S.border }
        Text {
            x: 18 * select.ui.u
            y: 16 * select.ui.u
            width: parent.width - 36 * select.ui.u
            text: select.label || select.placeholder
            color: S.text
            font.family: select.ui.fontFamily
            font.pixelSize: 17 * select.ui.u
            font.weight: Font.DemiBold
            elide: Text.ElideRight
        }
        ListView {
            id: list
            y: 52 * select.ui.u
            width: parent.width
            height: parent.height - y - 12 * select.ui.u
            clip: true
            model: select.options
            delegate: Rectangle {
                required property var modelData
                width: list.width
                height: Math.max(52 * select.ui.u, optionText.implicitHeight + 20 * select.ui.u)
                color: optionTap.pressed ? Qt.rgba(1, 1, 1, 0.10)
                     : (String(modelData.value) === String(select.value) ? Qt.rgba(47 / 255, 111 / 255, 224 / 255, 0.30) : "transparent")
                Column {
                    id: optionText
                    x: 18 * select.ui.u
                    width: parent.width - 36 * select.ui.u
                    anchors.verticalCenter: parent.verticalCenter
                    Text { width: parent.width; text: String(modelData.label); color: S.text; font.family: select.ui.fontFamily; font.pixelSize: 16 * select.ui.u; wrapMode: Text.WordWrap }
                    Text { width: parent.width; visible: !!modelData.detail; text: String(modelData.detail || ""); color: S.muted; font.family: select.ui.fontFamily; font.pixelSize: 13 * select.ui.u; wrapMode: Text.WordWrap }
                }
                MouseArea {
                    id: optionTap
                    anchors.fill: parent
                    onClicked: {
                        select.value = String(modelData.value)
                        sheet.close()
                        select.picked(select.value)
                    }
                }
            }
        }
    }
}

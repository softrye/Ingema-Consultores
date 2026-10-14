import QtQuick
import QtQuick.Controls
import "RStyle.js" as S

// Campo de texto etiquetado con error visible. Los valores se validan en C++.
Column {
    id: field
    property var ui
    property string label: ""
    property alias text: input.text
    property string placeholder: ""
    property string error: ""
    property bool numeric: false
    property bool readOnly: false
    property int maxLength: 500
    signal edited()

    spacing: 6 * ui.u

    Text {
        visible: field.label.length > 0
        text: field.label
        color: S.muted
        font.family: field.ui.fontFamily
        font.pixelSize: 13 * field.ui.u
    }
    TextField {
        id: input
        width: parent.width
        height: 48 * field.ui.u
        color: S.text
        placeholderText: field.placeholder
        placeholderTextColor: S.faint
        font.family: field.ui.fontFamily
        font.pixelSize: 16 * field.ui.u
        readOnly: field.readOnly
        maximumLength: field.maxLength
        inputMethodHints: field.numeric ? Qt.ImhFormattedNumbersOnly : Qt.ImhNone
        leftPadding: 14 * field.ui.u
        rightPadding: 14 * field.ui.u
        selectByMouse: true
        background: Rectangle {
            radius: 12 * field.ui.u
            color: Qt.rgba(1, 1, 1, field.readOnly ? 0.03 : 0.08)
            border.width: 1
            border.color: field.error.length > 0 ? S.danger
                        : (input.activeFocus ? S.accentSoft : S.border)
        }
        onTextEdited: field.edited()
    }
    Text {
        visible: field.error.length > 0
        width: parent.width
        text: field.error
        color: S.danger
        wrapMode: Text.WordWrap
        font.family: field.ui.fontFamily
        font.pixelSize: 13 * field.ui.u
    }
}

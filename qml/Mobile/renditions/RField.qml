import QtQuick
import QtQuick.Controls
import "RStyle.js" as S

// Campo de texto etiquetado con error visible. Los valores se validan en C++.
// formStyle: variante aprobada de Nuevo gasto (etiqueta fuerte, caja de 56 dp
// con icono Lucide [glyph] o prefijo [prefix], p. ej. "S/"). Por defecto, el
// aspecto previo (Nueva rendición y demás pantallas no cambian).
Column {
    id: field
    property var ui
    // Desplaza el Flickable contenedor para que el campo quede visible (teclado incluido).
    function reveal() {
        var f = field.parent
        while (f && !(f.contentY !== undefined && f.flicking !== undefined)) f = f.parent
        if (!f || !f.contentItem) return
        if (typeof f.__queueEnsure === "function") { f.__queueEnsure(); return true }
        if (typeof f.ensureActiveFocusVisible === "function") { f.ensureActiveFocusVisible(); return true }
        var y = field.mapToItem(f.contentItem, 0, 0).y
        var margin = 16 * field.ui.u
        var target = f.contentY
        if (y - margin < f.contentY) target = y - margin
        else if (y + field.height + margin > f.contentY + f.height) target = y + field.height + margin - f.height
        f.contentY = Math.max(0, Math.min(target, Math.max(0, f.contentHeight - f.height)))
    }
    Timer { id: revealLater; interval: 320; onTriggered: field.reveal() }   // tras ajustar el teclado
    function focusField() { if (!field.readOnly) input.forceActiveFocus(); field.reveal() }
    property string label: ""
    property alias text: input.text
    property string placeholder: ""
    property string error: ""
    property bool numeric: false
    property bool readOnly: false
    property int maxLength: 500
    property bool formStyle: false
    property int glyph: 0
    property string prefix: ""
    readonly property real leadSpace: glyph > 0 || prefix.length > 0 ? 52 * ui.u : 0
    signal edited()

    spacing: 6 * ui.u

    Text {
        visible: field.label.length > 0
        text: field.label
        color: field.formStyle ? S.text : S.muted
        font.family: field.ui.fontFamily
        font.pixelSize: (field.formStyle ? 15 : 13) * field.ui.u
        font.weight: field.formStyle ? Font.DemiBold : Font.Normal
    }
    TextField {
        id: input
        width: parent.width
        height: (field.formStyle ? 56 : 48) * field.ui.u
        color: S.text
        placeholderText: field.placeholder
        placeholderTextColor: S.faint
        font.family: field.ui.fontFamily
        font.pixelSize: 16 * field.ui.u
        readOnly: field.readOnly
        onActiveFocusChanged: {
            if (activeFocus) Qt.callLater(function() { if (input.activeFocus && !field.reveal()) revealLater.restart() })
            else revealLater.stop()
        }
        onTextChanged: if (!activeFocus) cursorPosition = 0
        maximumLength: field.maxLength
        inputMethodHints: field.numeric ? Qt.ImhFormattedNumbersOnly : Qt.ImhNone
        leftPadding: 14 * field.ui.u + field.leadSpace
        rightPadding: 14 * field.ui.u
        selectByMouse: true
        EnterKey.type: Qt.EnterKeyNext
        onAccepted: {
            var next = input.nextItemInFocusChain(true)
            for (var guard = 0; next && next !== input && guard < 40; ++guard) {
                if (next.visible && next.enabled && next.cursorPosition !== undefined && !next.readOnly) {
                    // Qt updates the input hints for the new focus. Hiding the
                    // IME here resized the Android surface and restored scroll
                    // to its old baseline before reopening it 220 ms later.
                    next.forceActiveFocus()
                    Qt.inputMethod.update(Qt.ImHints | Qt.ImQueryInput)
                    // Android Qt 6.9.3 update() only queries hints. show() sends
                    // the new keyboard type without hiding/resizing the IME.
                    if (next.inputMethodHints !== input.inputMethodHints)
                        Qt.callLater(function() { if (next && next.activeFocus) Qt.inputMethod.show() })
                    return
                }
                next = next.nextItemInFocusChain(true)
            }
            Qt.inputMethod.hide()
            input.focus = false
        }
        background: Rectangle {
            radius: (field.formStyle ? 16 : 12) * field.ui.u
            color: field.formStyle ? S.glass(field.readOnly ? 0.45 : 0.78) : S.ink(field.readOnly ? 0.03 : 0.08)
            border.width: 1
            border.color: field.error.length > 0 ? S.danger
                        : (input.activeFocus ? S.accentSoft : (field.formStyle ? S.fieldBorder : S.border))
            Text {                                   // icono o prefijo inicial
                visible: field.leadSpace > 0
                x: 16 * field.ui.u
                width: 28 * field.ui.u
                anchors.verticalCenter: parent.verticalCenter
                horizontalAlignment: Text.AlignHCenter
                text: field.glyph > 0 ? String.fromCharCode(field.glyph) : field.prefix
                color: S.navy
                font.family: field.glyph > 0 ? field.ui.iconFamily : field.ui.fontFamily
                font.pixelSize: (field.glyph > 0 ? 22 : 16) * field.ui.u
                font.weight: field.glyph > 0 ? Font.Normal : Font.DemiBold
            }
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

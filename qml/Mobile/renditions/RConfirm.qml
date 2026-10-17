import QtQuick
import QtQuick.Controls
import "RStyle.js" as S

// Diálogo de confirmación para acciones irreversibles o remotas.
Popup {
    id: confirm
    property var ui
    property string title: ""
    property string message: ""
    property string acceptLabel: "Confirmar"
    property bool destructive: false
    property var acceptCallback: null

    function ask(titleText, messageText, label, destructiveAction, callback) {
        title = titleText
        message = messageText
        acceptLabel = label || "Confirmar"
        destructive = destructiveAction === true
        acceptCallback = callback
        open()
    }

    parent: Overlay.overlay
    modal: true
    focus: true
    width: Math.min(parent ? parent.width - 40 * ui.u : 360, 460 * ui.u)
    x: parent ? (parent.width - width) / 2 : 0
    y: parent ? (parent.height - height) / 2 : 0
    padding: 20 * ui.u
    background: Rectangle { radius: 20 * confirm.ui.u; color: S.popup; border.width: 1; border.color: S.border }
    contentItem: Column {
        spacing: 14 * confirm.ui.u
        Text {
            width: parent.width
            text: confirm.title
            color: S.text
            wrapMode: Text.WordWrap
            font.family: confirm.ui.fontFamily
            font.pixelSize: 19 * confirm.ui.u
            font.weight: Font.DemiBold
        }
        Text {
            width: parent.width
            text: confirm.message
            color: S.muted
            wrapMode: Text.WordWrap
            font.family: confirm.ui.fontFamily
            font.pixelSize: 15 * confirm.ui.u
        }
        Row {
            anchors.right: parent.right
            spacing: 10 * confirm.ui.u
            RButton { ui: confirm.ui; label: "Cancelar"; onActivated: confirm.close() }
            RButton {
                ui: confirm.ui
                label: confirm.acceptLabel
                primary: !confirm.destructive
                danger: confirm.destructive
                onActivated: {
                    var callback = confirm.acceptCallback
                    confirm.acceptCallback = null
                    confirm.close()
                    if (callback) callback()
                }
            }
        }
    }
}

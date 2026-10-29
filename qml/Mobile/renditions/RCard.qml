import QtQuick
import "RStyle.js" as S

// Tarjeta de vidrio con columna de contenido; tocable si [clickable].
Rectangle {
    id: card
    Component.onCompleted: S.renderCount(objectName.indexOf("expense:") === 0 ? "expense_delegate_created" : "section_card_created")
    property var ui
    property bool clickable: false
    default property alias content: body.data
    signal activated()

    implicitHeight: body.implicitHeight + 32 * ui.u
    radius: 18 * ui.u
    color: tap.pressed ? S.surfaceStrong : S.surface
    border.width: 1
    border.color: S.border
    Column {
        id: body
        x: 16 * card.ui.u
        y: 16 * card.ui.u
        width: card.width - 32 * card.ui.u
        spacing: 8 * card.ui.u
    }
    MouseArea {
        id: tap
        anchors.fill: parent
        enabled: card.clickable
        z: -1
        onClicked: card.activated()
    }
}

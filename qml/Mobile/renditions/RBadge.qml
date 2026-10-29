import QtQuick
import "RStyle.js" as S

// Etiqueta de estado (rendición, gasto o sincronización).
Rectangle {
    id: badge
    property var ui
    property string label: ""
    property color tone: S.muted
    implicitHeight: 26 * ui.u
    implicitWidth: badgeText.implicitWidth + 18 * ui.u
    radius: height / 2
    color: Qt.rgba(tone.r, tone.g, tone.b, 0.16)
    border.width: 1
    border.color: Qt.rgba(tone.r, tone.g, tone.b, 0.55)
    Text {
        id: badgeText
        anchors.centerIn: parent
        text: badge.label
        color: badge.tone
        font.family: badge.ui.fontFamily
        font.pixelSize: 12 * badge.ui.u
        font.weight: Font.DemiBold
    }
}

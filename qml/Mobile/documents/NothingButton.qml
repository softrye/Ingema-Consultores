import QtQuick
import QtQuick.Controls

Button {
    id: control
    property string glyph: ""
    property bool filled: false
    property color foreground: "#111827"
    property color fill: "#E5E7EB"
    property color onFill: "#111827"
    implicitWidth: Math.max(44, displayText.implicitWidth + 20)
    implicitHeight: 42
    readonly property string glyphLabel: glyph === "arrow_back" ? "<"
                                 : glyph === "more_vert" ? "..."
                                 : glyph === "close" ? "X"
                                 : glyph === "add" ? "+"
                                 : glyph === "search" ? "?"
                                 : glyph === "refresh" ? "Refrescar"
                                 : glyph === "grid_view" ? "Cuadricula"
                                 : glyph === "list" ? "Lista"
                                 : glyph === "sort" ? "Ordenar" : glyph
    background: Rectangle { color: control.down ? "#D1D5DB" : "#F3F4F6"; border.color: "#9CA3AF" }
    contentItem: Text {
        id: displayText
        text: control.text.length ? control.text : control.glyphLabel
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
        color: "#111827"
        font.pixelSize: 12
        elide: Text.ElideRight
    }
    Accessible.name: text.length ? text : glyph
}

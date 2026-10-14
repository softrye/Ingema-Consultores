import QtQuick
import QtQuick.Controls
import "RStyle.js" as S

// Selector de fecha (calendario mensual). Valor en ISO aaaa-mm-dd; las
// fechas fuera de [minimum, maximum] no se pueden elegir.
Column {
    id: dateField
    property var ui
    property string label: ""
    property string value: ""
    property string minimum: ""
    property string maximum: ""
    property string error: ""
    property bool readOnly: false
    signal picked(string value)

    spacing: 6 * ui.u

    function iso(d) {
        function two(n) { return n < 10 ? "0" + n : "" + n }
        return d.getFullYear() + "-" + two(d.getMonth() + 1) + "-" + two(d.getDate())
    }
    function parse(text) {
        var s = String(text || "")
        if (s.length !== 10) return null
        var d = new Date(Number(s.substring(0, 4)), Number(s.substring(5, 7)) - 1, Number(s.substring(8, 10)))
        return isNaN(d.getTime()) ? null : d
    }
    function allowed(text) {
        return (minimum.length === 0 || text >= minimum) && (maximum.length === 0 || text <= maximum)
    }

    Text {
        visible: dateField.label.length > 0
        text: dateField.label
        color: S.muted
        font.family: dateField.ui.fontFamily
        font.pixelSize: 13 * dateField.ui.u
    }
    Rectangle {
        width: parent.width
        height: 48 * dateField.ui.u
        radius: 12 * dateField.ui.u
        color: Qt.rgba(1, 1, 1, dateField.readOnly ? 0.03 : (tap.pressed ? 0.14 : 0.08))
        border.width: 1
        border.color: dateField.error.length > 0 ? S.danger : S.border
        Text {
            x: 14 * dateField.ui.u
            anchors.verticalCenter: parent.verticalCenter
            text: dateField.value.length ? S.date(dateField.value) : "dd/mm/aaaa"
            color: dateField.value.length ? S.text : S.faint
            font.family: dateField.ui.fontFamily
            font.pixelSize: 16 * dateField.ui.u
        }
        MouseArea {
            id: tap
            anchors.fill: parent
            enabled: !dateField.readOnly
            onClicked: {
                var d = dateField.parse(dateField.value) || dateField.parse(dateField.minimum) || new Date()
                grid.month = d.getMonth()
                grid.year = d.getFullYear()
                calendar.open()
            }
        }
        Accessible.role: Accessible.Button
        Accessible.name: dateField.label + " " + dateField.value
    }
    Text {
        visible: dateField.error.length > 0
        width: parent.width
        text: dateField.error
        color: S.danger
        wrapMode: Text.WordWrap
        font.family: dateField.ui.fontFamily
        font.pixelSize: 13 * dateField.ui.u
    }

    Popup {
        id: calendar
        parent: Overlay.overlay
        modal: true
        focus: true
        width: Math.min(parent ? parent.width - 32 * dateField.ui.u : 360, 420 * dateField.ui.u)
        height: 420 * dateField.ui.u
        x: parent ? (parent.width - width) / 2 : 0
        y: parent ? (parent.height - height) / 2 : 0
        padding: 14 * dateField.ui.u
        background: Rectangle { radius: 18 * dateField.ui.u; color: "#1A2440"; border.width: 1; border.color: S.border }
        Column {
            anchors.fill: parent
            spacing: 8 * dateField.ui.u
            Row {
                width: parent.width
                height: 44 * dateField.ui.u
                RButton {
                    ui: dateField.ui; glyph: 0xE06E; width: 48 * dateField.ui.u
                    onActivated: { if (grid.month === 0) { grid.month = 11; grid.year-- } else grid.month-- }
                    Accessible.name: "Mes anterior"
                }
                Text {
                    width: parent.width - 96 * dateField.ui.u
                    height: parent.height
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                    text: grid.title
                    color: S.text
                    font.family: dateField.ui.fontFamily
                    font.pixelSize: 17 * dateField.ui.u
                    font.capitalization: Font.Capitalize
                }
                RButton {
                    ui: dateField.ui; glyph: 0xE06F; width: 48 * dateField.ui.u
                    onActivated: { if (grid.month === 11) { grid.month = 0; grid.year++ } else grid.month++ }
                    Accessible.name: "Mes siguiente"
                }
            }
            DayOfWeekRow {
                width: parent.width
                locale: grid.locale
                delegate: Text {
                    required property string shortName
                    text: shortName
                    horizontalAlignment: Text.AlignHCenter
                    color: S.muted
                    font.family: dateField.ui.fontFamily
                    font.pixelSize: 12 * dateField.ui.u
                }
            }
            MonthGrid {
                id: grid
                width: parent.width
                height: parent.height - 160 * dateField.ui.u
                locale: Qt.locale("es_PE")
                delegate: Rectangle {
                    required property var model
                    readonly property string isoValue: dateField.iso(model.date)
                    readonly property bool selectable: model.month === grid.month && dateField.allowed(isoValue)
                    radius: height / 2
                    color: isoValue === dateField.value ? S.accent : "transparent"
                    opacity: selectable ? 1 : 0.3
                    Text {
                        anchors.centerIn: parent
                        text: model.day
                        color: S.text
                        font.family: dateField.ui.fontFamily
                        font.pixelSize: 15 * dateField.ui.u
                    }
                }
                onClicked: function(date) {
                    var text = dateField.iso(date)
                    if (date.getMonth() !== grid.month || !dateField.allowed(text)) return
                    dateField.value = text
                    calendar.close()
                    dateField.picked(text)
                }
            }
            RButton {
                ui: dateField.ui
                width: parent.width
                label: "Hoy"
                enabledButton: dateField.allowed(dateField.iso(new Date()))
                onActivated: {
                    var text = dateField.iso(new Date())
                    dateField.value = text
                    calendar.close()
                    dateField.picked(text)
                }
            }
        }
    }
}

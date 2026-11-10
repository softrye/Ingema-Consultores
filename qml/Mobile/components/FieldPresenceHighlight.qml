import QtQuick

// Ilumina un campo o sector que otra persona está editando: borde y halo de su
// color de presencia y una etiqueta con su nombre sobre el borde superior.
// Uso: hijo del campo/sector, `anchors.fill: parent`, con `field` = la misma
// etiqueta que ese sector publica con setField (p. ej. "Gasto 3"). Solo pinta;
// no captura toques.
Item {
    id: glow
    property var members: []
    property string field: ""
    property real radius: 12
    property string fontFamily: ""
    property real u: 1
    property bool reducedMotion: false
    readonly property var holders: {
        var key = String(field || "")
        if (!key.length) return []
        return (members || []).filter(function(m) { return m && m.self !== true && String(m.field || "") === key })
    }
    readonly property var lead: holders.length ? holders[0] : null
    readonly property color tone: lead ? String(lead.color || "#38BDF8") : "transparent"

    z: 50
    enabled: false
    opacity: lead ? 1 : 0
    visible: opacity > 0.01
    Behavior on opacity { NumberAnimation { duration: glow.reducedMotion ? 0 : 160; easing.type: Easing.OutCubic } }
    Accessible.role: Accessible.StaticText
    Accessible.name: lead ? String(lead.name || "Usuario") + " está editando aquí" : ""

    Rectangle {                                    // halo
        anchors.fill: parent
        anchors.margins: -4 * glow.u
        radius: glow.radius + 4 * glow.u
        color: "transparent"
        border.width: 4 * glow.u
        border.color: Qt.rgba(glow.tone.r, glow.tone.g, glow.tone.b, 0.28)
    }
    Rectangle {                                    // borde
        anchors.fill: parent
        radius: glow.radius
        color: Qt.rgba(glow.tone.r, glow.tone.g, glow.tone.b, 0.06)
        border.width: 2 * glow.u
        border.color: glow.tone
    }
    Rectangle {                                    // etiqueta con el nombre
        x: 12 * glow.u
        y: -height / 2
        height: 20 * glow.u
        width: Math.min(label.implicitWidth + 14 * glow.u, glow.width - 24 * glow.u)
        radius: height / 2
        color: glow.tone
        Text {
            id: label
            anchors.centerIn: parent
            width: parent.width - 14 * glow.u
            horizontalAlignment: Text.AlignHCenter
            elide: Text.ElideRight
            text: glow.lead ? String(glow.lead.name || "Usuario").split(" ")[0]
                              + (glow.holders.length > 1 ? " +" + (glow.holders.length - 1) : "") : ""
            color: "#0F172A"
            font.family: glow.fontFamily
            font.pixelSize: 11 * glow.u
            font.weight: Font.Bold
        }
    }
}

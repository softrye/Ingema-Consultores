import QtQuick
import QtQuick.Effects

// Avatares apilados de la presencia en vivo (Rendiciones y Calicatas).
// `members`: lista de SupabaseRealtimeChannel.members / CalicataCloud.presenceMembers
// ({ name, initials, color, avatarSource, field }). Foto del perfil si ya está en la
// caché (file://, sin tokens); si no, las iniciales sobre el color de la persona
// (mismo color que la Web). Solo presentación: sin animaciones propias.
Row {
    id: stack
    property var members: []
    property int limit: 3
    property real size: 24
    property color rim: "#0D1729"                  // separa avatares superpuestos
    property color ink: "#0F172A"                  // iniciales oscuras sobre el disco -400
    property string fontFamily: ""
    readonly property int overflow: Math.max(0, (members || []).length - limit)

    spacing: -size * 0.25
    Accessible.role: Accessible.List
    Accessible.name: "Personas con el documento abierto"

    Repeater {
        model: (stack.members || []).slice(0, stack.limit)
        delegate: Item {
            id: avatar
            required property var modelData
            width: stack.size; height: width
            Accessible.role: Accessible.StaticText
            Accessible.name: String(modelData.name || "Usuario")
                             + (String(modelData.field || "").length ? ", en " + modelData.field : "")
            Rectangle {
                anchors.fill: parent
                radius: width / 2
                color: String(avatar.modelData.color || "#38BDF8")
                border.width: Math.max(1.5, stack.size * 0.08)
                border.color: stack.rim
            }
            Text {
                anchors.centerIn: parent
                visible: photo.status !== Image.Ready
                text: String(avatar.modelData.initials || "?")
                color: stack.ink
                font.family: stack.fontFamily
                font.pixelSize: stack.size * 0.4
                font.weight: Font.Bold
            }
            Image {
                id: photo
                anchors.fill: parent
                anchors.margins: Math.max(1.5, stack.size * 0.08)
                source: String(avatar.modelData.avatarSource || "")
                sourceSize: Qt.size(stack.size * 2, stack.size * 2)
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                visible: false
            }
            Item {
                id: photoMask
                anchors.fill: photo
                layer.enabled: true
                visible: false
                Rectangle { anchors.fill: parent; radius: width / 2; color: "black" }
            }
            MultiEffect {
                anchors.fill: photo
                source: photo
                visible: photo.status === Image.Ready
                maskEnabled: true
                maskSource: photoMask
                maskThresholdMin: 0.5
                maskSpreadAtMin: 1.0
            }
        }
    }
    Rectangle {                                    // +N
        visible: stack.overflow > 0
        width: stack.size; height: width; radius: width / 2
        color: "#334155"
        border.width: Math.max(1.5, stack.size * 0.08)
        border.color: stack.rim
        Text {
            anchors.centerIn: parent
            text: "+" + stack.overflow
            color: "#FFFFFF"
            font.family: stack.fontFamily
            font.pixelSize: stack.size * 0.38
            font.weight: Font.Bold
        }
        Accessible.name: (stack.members || []).slice(stack.limit).map(function(m) { return m.name }).join(", ")
    }
}

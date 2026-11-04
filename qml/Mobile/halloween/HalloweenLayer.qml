pragma ComponentBehavior: Bound
import QtQuick

// Bounded SVG rasterizations; transforms only, no per-sprite timers or effects.
Item {
    id: halloweenLayer
    property var controller: null
    property bool running: true
    readonly property real seconds: moving ? controller.visualSeconds : 0
    readonly property bool moving: visible && running && controller && controller.motionActive
    readonly property int animatedSpriteCount: moving ? 10 : 0
    enabled: false
    clip: true
    Image {
        x: halloweenLayer.width * 0.69; y: halloweenLayer.height * 0.065
        width: Math.min(halloweenLayer.width * 0.27, 128); height: width
        source: "qrc:/images/halloween/moon.svg"
        sourceSize: Qt.size(128, 128); opacity: 0.75
    }
    Image {
        anchors.top: parent.top; anchors.left: parent.left
        width: Math.min(108, parent.width * 0.25); height: width
        source: "qrc:/images/halloween/web.svg"; sourceSize: Qt.size(108, 108); opacity: 0.44
    }
    Image {
        anchors.top: parent.top; anchors.right: parent.right
        width: Math.min(80, parent.width * 0.2); height: width; mirror: true
        source: "qrc:/images/halloween/web.svg"; sourceSize: Qt.size(80, 80); opacity: 0.32
    }
    Repeater {
        model: [ { art: "ghost", px: 0.82, py: 0.42, size: 52 },
                 { art: "ghost", px: 0.03, py: 0.65, size: 36 },
                 { art: "pumpkin", px: 0.06, py: 0.85, size: 58 },
                 { art: "pumpkin", px: 0.77, py: 0.88, size: 43 },
                 { art: "bat", px: 0.3, py: 0.22, size: 64 },
                 { art: "cat", px: 0.89, py: 0.72, size: 40 },
                 { art: "candy", px: 0.12, py: 0.32, size: 32 },
                 { art: "star", px: 0.26, py: 0.13, size: 14 },
                 { art: "star", px: 0.58, py: 0.52, size: 11 },
                 { art: "star", px: 0.94, py: 0.28, size: 16 } ]
        delegate: Image {
            id: sprite
            required property var modelData
            required property int index
            readonly property bool ghost: modelData.art === "ghost"
            readonly property bool bat: modelData.art === "bat"
            readonly property bool star: modelData.art === "star"
            readonly property real t: halloweenLayer.seconds
            readonly property real flight: (t + 7) % 36 / 9
            readonly property real offsetX: ghost && halloweenLayer.controller ? (halloweenLayer.controller.gentlePoint.x - 0.5) * 36 : 0
            readonly property real offsetY: ghost && halloweenLayer.controller ? (halloweenLayer.controller.gentlePoint.y - 0.5) * 24 : 0
            width: Math.min(modelData.size, halloweenLayer.width * 0.17); height: width
            source: "qrc:/images/halloween/" + modelData.art + ".svg"
            sourceSize: Qt.size(128, 128)
            x: bat && halloweenLayer.moving ? -width + Math.min(1.2, flight) * (halloweenLayer.width + 2 * width)
               : halloweenLayer.width * modelData.px - width * 0.25 + offsetX
            y: star ? ((modelData.py + t / (45 + index * 3)) % 1) * halloweenLayer.height
               : halloweenLayer.height * modelData.py - height / 2 + offsetY
                 + (bat ? Math.sin(flight * Math.PI * 2) * 24 : Math.sin(t * 0.8 + index) * (ghost ? 9 : 3))
            visible: !bat || !halloweenLayer.moving || flight <= 1.15
            rotation: star ? t * 5 + index * 19 : bat ? Math.cos(flight * Math.PI * 2) * 9 : 0
            opacity: modelData.art === "pumpkin" ? 0.48 + 0.07 * Math.sin(t * 2.3 + index) : ghost ? 0.32 : 0.42
        }
    }
}

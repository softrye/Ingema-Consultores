import QtQuick
Item {
    id: decor
    property var controller: null
    property bool active: false
    property bool vertical: false
    property real u: 1
    enabled: false
    visible: active
    KawaiiMascot {
        active: decor.active; frame: 0; tilePixels: 96
        width: 44*decor.u; height: width
        x: -5*decor.u; y: -28*decor.u
        opacity: 0.92
    }
    KawaiiMascot {
        active: decor.active; frame: 1; tilePixels: 96
        width: 46*decor.u; height: width
        x: parent.width-width+5*decor.u
        y: decor.vertical ? parent.height-height+8*decor.u : -30*decor.u
        opacity: 0.92
    }
    // Approved walking/waving Pompompurin, isolated from the sample Dock background.
    // One 12-second transparent GIF, driven by the existing shared seasonal clock.
    // The content never handles touch, and stops when the safe surface disappears.
    AnimatedImage {
        id: guest
        readonly property bool showing: decor.active && !decor.vertical && decor.controller
            && decor.controller.kawaiiGuestVisible
        readonly property real progress: showing ? Math.max(0, Math.min(1,
            1 - decor.controller.kawaiiClock.remainingMs / 12000)) : 0
        readonly property real restingX: Math.max(16 * decor.u,
            Math.min(parent.width - width - 12 * decor.u, parent.width * 0.48))
        readonly property real entrance: Math.min(1, progress / 0.40)
        readonly property real departure: Math.max(0, Math.min(1, (progress - 0.77) / 0.23))
        source: decor.active ? "qrc:/images/kawaii/pompompurin-dock-walk-wave.gif" : ""
        visible: showing
        enabled: false
        playing: showing
        cache: true
        width: 94 * decor.u
        height: 99 * decor.u
        fillMode: Image.PreserveAspectFit
        // Walk in from the left, wave in the middle, walk off to the right.
        x: progress < 0.40 ? -width + (restingX + width) * entrance
            : restingX + (parent.width - restingX + width) * departure
        y: -height + 15 * decor.u
            - (progress < 0.40 || progress > 0.77
                ? Math.abs(Math.sin(progress * 33)) * 3 * decor.u : 0)
        opacity: Math.max(0, Math.min(1, progress * 28, (1 - progress) * 28))
        onShowingChanged: if (showing && status === Image.Ready) currentFrame = 0
        onStatusChanged: if (showing && status === Image.Ready) currentFrame = 0
    }
}

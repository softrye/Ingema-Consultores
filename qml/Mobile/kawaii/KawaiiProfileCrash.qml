pragma ComponentBehavior: Bound
import QtQuick

// Pure presentation: never writes CalicataDocument, stratum models, or layer geometry.
// One ten-second AFK surprise per idle period on every fidelity tier.
Item {
    id: crash
    property bool allowed: false
    property double lastInputMs: Date.now()
    property real columnX: 0
    property real columnWidth: 100
    property real topPad: 0
    property real plotHeight: 100
    property real uiScale: 1

    property bool eventActive: false
    property bool playedThisIdle: false
    property double eligibleSince: Date.now()
    property double startedAt: 0
    property int elapsedMs: 0
    readonly property real progress: eventActive ? Math.max(0, Math.min(1, elapsedMs / 10000)) : 0
    readonly property bool damaged: eventActive && elapsedMs >= 2500 && elapsedMs < 8050

    anchors.fill: parent
    clip: true
    enabled: false
    visible: allowed

    function cancel() {
        eventActive = false
        elapsedMs = 0
    }
    function resetIdle() {
        cancel()
        playedThisIdle = false
        eligibleSince = Date.now()
    }
    function isReallyVisible() {
        var win = crash.Window.window
        if (!win || !win.contentItem) return false
        var p = crash.mapToItem(win.contentItem, 0, 0)
        var visibleHeight = Math.min(win.height, p.y + crash.height) - Math.max(0, p.y)
        return visibleHeight >= Math.min(crash.height * 0.65, 140)
    }
    function begin() {
        startedAt = Date.now()
        elapsedMs = 0
        playedThisIdle = true
        eventActive = true
        console.info("INGE_KAWAII_CALICATA_CRASH_START visualOnly=true")
    }
    onAllowedChanged: resetIdle()
    onLastInputMsChanged: resetIdle()

    Timer {
        interval: 250
        repeat: true
        running: crash.allowed && !crash.eventActive && !crash.playedThisIdle
        onTriggered: {
            if (!crash.isReallyVisible()) return
            if (Date.now() - Math.max(crash.lastInputMs, crash.eligibleSince) >= 10000)
                crash.begin()
        }
    }
    Timer {
        interval: 80
        repeat: true
        running: crash.eventActive
        onTriggered: {
            crash.elapsedMs = Math.min(10000, Date.now() - crash.startedAt)
            if (crash.elapsedMs >= 10000) {
                crash.cancel()
                console.info("INGE_KAWAII_CALICATA_CRASH_END restored=true")
            }
        }
    }

    // Visual fracture over E1. It is an overlay, NOT a mutation of the actual bands.
    Canvas {
        id: fractures
        x: crash.columnX
        y: crash.topPad
        width: Math.max(1, crash.columnWidth)
        height: Math.max(1, Math.min(crash.plotHeight * 0.45, 180))
        visible: crash.damaged
        onVisibleChanged: if (visible) requestPaint()
        opacity: crash.elapsedMs < 3300 ? Math.min(1, (crash.elapsedMs - 2500) / 800)
            : crash.elapsedMs > 7500 ? Math.max(0, (8050 - crash.elapsedMs) / 550) : 1
        onPaint: {
            var ctx = getContext("2d")
            ctx.clearRect(0, 0, width, height)
            var w = width, h = height
            ctx.strokeStyle = "#563A33"
            ctx.lineWidth = Math.max(1.3, w / 56)
            ctx.lineJoin = "round"
            ctx.beginPath()
            ctx.moveTo(w * 0.82, 0)
            ctx.lineTo(w * 0.56, h * 0.24)
            ctx.lineTo(w * 0.72, h * 0.38)
            ctx.lineTo(w * 0.43, h * 0.55)
            ctx.lineTo(w * 0.58, h * 0.80)
            ctx.lineTo(w * 0.35, h)
            ctx.moveTo(w * 0.72, h * 0.38)
            ctx.lineTo(w * 0.95, h * 0.53)
            ctx.lineTo(w * 0.80, h * 0.70)
            ctx.moveTo(w * 0.43, h * 0.55)
            ctx.lineTo(w * 0.17, h * 0.69)
            ctx.stroke()
        }
    }
    // Green-screen video pre-keyed into a small, transparent, native Qt GIF.
    // The actual profile/level labels remain live underneath this image.
    AnimatedImage {
        id: animation
        // Keep the entire 10s cartoon near the first stratum, rather than
        // covering most of the stratigraphic preview, depth ticks and labels.
        readonly property real targetWidth: Math.min(240 * crash.uiScale,
            Math.max(140 * crash.uiScale, crash.width * 0.44))
        width: targetWidth
        height: width * 9 / 16
        x: Math.max(0, Math.min(crash.width - width,
            crash.columnX + crash.columnWidth * 0.15))
        y: Math.max(0, Math.min(crash.height - height,
            crash.topPad + crash.plotHeight * 0.04))
        source: crash.allowed ? "qrc:/images/kawaii/pompompurin-calicata-crash-10s.gif" : ""
        visible: crash.eventActive
        playing: crash.eventActive
        cache: true
        enabled: false
        fillMode: Image.PreserveAspectFit
        onPlayingChanged: if (playing && status === Image.Ready) currentFrame = 0
        onStatusChanged: if (status === Image.Ready && crash.eventActive) currentFrame = 0
    }
}
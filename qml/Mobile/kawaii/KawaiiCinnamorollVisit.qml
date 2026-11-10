pragma ComponentBehavior: Bound
import QtQuick
import QtMultimedia

// Native MP4 + AAC: no GIF, frame re-encoding or replacement audio.
// GPU chroma masks green; the interactive scene underneath is untouched.
Item {
    id: visitor
    required property bool allowed
    // Stable across touches/navigation: do not unload/reload the FFmpeg codec
    // on every touch while deciding if the one-shot AFK visit is eligible.
    required property bool mediaEnabled
    required property double lastInteractionAt
    // One visit per genuine idle session, NOT a 20s repeating loop.
    // A new visit requires fresh user input followed by 20 seconds idle.
    property int idleDelayMs: 20000
    property bool playedThisIdle: false
    property bool showing: false
    property bool playbackFailed: false
    property double nextEligibleMs: Date.now() + idleDelayMs

    anchors.fill: parent
    enabled: false
    visible: showing
    z: 78

    function endVisit() {
        movie.stop()
        showing = false
        // Keep playedThisIdle latched after the clip ends or is interrupted.
    }
    function cancelVisit() {
        if (showing) endVisit()
        nextEligibleMs = Date.now() + idleDelayMs
    }
    function tryStart() {
        if (!allowed || showing || playbackFailed || playedThisIdle)
            return
        var now = Date.now()
        if (now - lastInteractionAt < idleDelayMs || now < nextEligibleMs)
            return
        // Latch BEFORE starting the player: EndOfMedia or an error cannot
        // re-arm the AFK surprise without another real user interaction.
        playedThisIdle = true
        showing = true
        console.info("INGE_KAWAII_CINNAMOROLL_START mp4=original sound=true")
        movie.stop()
        movie.position = 0
        movie.play()
    }
    onAllowedChanged: {
        // Losing focus, opening a menu or thermal pressure must not re-arm.
        if (!allowed) {
            if (showing) endVisit()
        } else {
            nextEligibleMs = Math.max(nextEligibleMs, Date.now() + idleDelayMs)
        }
    }
    onLastInteractionAtChanged: {
        // Only an actual input timestamp from Home starts a fresh idle session.
        playedThisIdle = false
        cancelVisit()
    }

    Timer {
        interval: 250
        repeat: true
        running: visitor.allowed && !visitor.showing && !visitor.playbackFailed
            && !visitor.playedThisIdle
        onTriggered: visitor.tryStart()
    }
    // Abort a stalled codec instead of leaving a forever-visible overlay.
    Timer {
        interval: 11500
        repeat: false
        running: visitor.showing
        onTriggered: visitor.endVisit()
    }

    Item {
        id: cinema
        width: Math.min(visitor.width, 820)
        height: width * 9 / 16
        anchors.horizontalCenter: parent.horizontalCenter
        y: Math.max(36, Math.min(visitor.height - height - 48, visitor.height * 0.25))
        enabled: false

        VideoOutput {
            id: nativeVideo
            anchors.fill: parent
            fillMode: VideoOutput.Stretch
            enabled: false
        }
        ShaderEffectSource {
            id: videoTexture
            anchors.fill: parent
            sourceItem: nativeVideo
            hideSource: true
            live: true
            visible: false
            enabled: false
        }
        ShaderEffect {
            anchors.fill: parent
            property var source: videoTexture
            fragmentShader: "qrc:/InGe/Mobile/shaders/kawaii_chroma.frag.qsb"
        }
    }

    MediaPlayer {
        id: movie
        source: visitor.mediaEnabled ? "qrc:/images/kawaii/cinnamoroll-knock-clean-10s.mp4" : ""
        loops: 1
        playbackRate: 1
        videoOutput: nativeVideo
        audioOutput: AudioOutput {
            volume: 1.0
            muted: false
        }
        onMediaStatusChanged: {
            if (mediaStatus === MediaPlayer.EndOfMedia && visitor.showing)
                visitor.endVisit()
        }
        onErrorOccurred: function(error, errorString) {
            console.warn("INGE_KAWAII_CINNAMOROLL_MEDIA_ERROR", error, errorString)
            visitor.playbackFailed = true
            visitor.cancelVisit()
        }
    }
}

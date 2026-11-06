pragma ComponentBehavior: Bound
import QtQuick
import QtMultimedia

// Native MP4 + AAC: no GIF, frame re-encoding or replacement audio.
// GPU chroma masks green; the interactive scene underneath is untouched.
Item {
    id: visitor
    required property bool allowed
    required property double lastInteractionAt
    // One complete MP4 at most once per 20-second window (start-to-start).
    // Its 10-second playback is followed by approximately 10 seconds quiet.
    property int idleDelayMs: 20000
    property int repeatDelayMs: 20000
    property bool showing: false
    property bool playbackFailed: false
    property double lastStartedMs: -1
    property double nextEligibleMs: Date.now() + idleDelayMs

    anchors.fill: parent
    enabled: false
    visible: showing
    z: 78

    function endVisit() {
        movie.stop()
        showing = false
        // Never restart immediately if MediaPlayer finishes or stops early.
        nextEligibleMs = Math.max(nextEligibleMs, lastStartedMs + repeatDelayMs)
    }
    function cancelVisit() {
        if (showing) endVisit()
        // User activity, switching themes or reopening the app resets idle.
        // Preserve the last-played cooldown across such transitions.
        nextEligibleMs = Math.max(Date.now() + idleDelayMs,
                                  lastStartedMs + repeatDelayMs)
    }
    function tryStart() {
        if (!allowed || showing || playbackFailed)
            return
        var now = Date.now()
        if (now - lastInteractionAt < idleDelayMs
                || now < nextEligibleMs
                || (lastStartedMs >= 0 && now - lastStartedMs < repeatDelayMs))
            return
        lastStartedMs = now
        nextEligibleMs = now + repeatDelayMs
        showing = true
        console.info("INGE_KAWAII_CINNAMOROLL_START mp4=original sound=true")
        movie.stop()
        movie.position = 0
        movie.play()
    }
    onAllowedChanged: {
        if (!allowed) cancelVisit()
        else nextEligibleMs = Math.max(nextEligibleMs, Date.now() + idleDelayMs)
    }
    onLastInteractionAtChanged: cancelVisit()

    Timer {
        interval: 250
        repeat: true
        running: visitor.allowed && !visitor.showing && !visitor.playbackFailed
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
        source: visitor.allowed ? "qrc:/images/kawaii/cinnamoroll-knock-clean-10s.mp4" : ""
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

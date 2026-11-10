pragma ComponentBehavior: Bound
import QtQuick
import QtMultimedia

// App-launch-only movie. Stays ABOVE the login/first-run/authenticated layers.
// Never affects AuthSession, OnboardingState or the current login step.
// Original Gemini H.264/AAC stream; no GIF, transcoding or audio replacement.
Item {
    id: intro
    property bool finished: false
    property bool transitioning: false
    property string fontFamily: ""
    signal completed()

    anchors.fill: parent
    visible: !finished
    enabled: !finished
    clip: true
    z: 10000

    function exitWithGlint(reason) {
        if (finished || transitioning) return
        transitioning = true
        console.info("INGE_STARTUP_INTRO_EXIT reason=" + reason)
        glintTransition.start()
    }
    Component.onCompleted: {
        console.info("INGE_STARTUP_INTRO_START originalMp4=true audio=true")
        movie.play()
    }

    Rectangle {
        anchors.fill: parent
        color: "#151A30" // official navy behind the portrait video on wide displays
    }
    VideoOutput {
        id: introVideo
        anchors.fill: parent
        fillMode: VideoOutput.PreserveAspectCrop
        // Cover the entire phone viewport. Crop a little at the sides instead
        // of showing navy letterbox bands above/below the 9:16 source.
    }
    MediaPlayer {
        id: movie
        source: "qrc:/images/intro/ingeplus-opening-10s.mp4"
        loops: 1
        playbackRate: 1
        videoOutput: introVideo
        audioOutput: AudioOutput { volume: 1.0; muted: false }

        // Start the glint slightly BEFORE the video finishes, so the codec's
        // final-frame release cannot flash black between movie and login.
        onPositionChanged: {
            if (!intro.transitioning && duration > 0 &&
                    position >= Math.max(0, duration - 320))
                intro.exitWithGlint("end")
        }
        onMediaStatusChanged: {
            if (mediaStatus === MediaPlayer.EndOfMedia)
                intro.exitWithGlint("endOfMedia")
            if (mediaStatus === MediaPlayer.InvalidMedia)
                intro.exitWithGlint("invalidMedia")
        }
        onErrorOccurred: function(error, message) {
            console.warn("INGE_STARTUP_INTRO_MEDIA_ERROR", error, message)
            intro.exitWithGlint("mediaError")
        }
    }

    // A single pastel-blue WHITE glint masks the cut, then fades away to
    // reveal the already-prepared login (or restored-session screen).
    Rectangle {
        id: glint
        anchors.fill: parent
        opacity: 0
        gradient: Gradient {
            GradientStop { position: 0.0; color: "#FFFFFF" }
            GradientStop { position: 0.52; color: "#F5FBFF" }
            GradientStop { position: 1.0; color: "#D9EEFF" }
        }
    }
    SequentialAnimation {
        id: glintTransition
        running: false
        NumberAnimation {
            target: glint
            property: "opacity"
            from: 0
            to: 1
            duration: 240
            easing.type: Easing.OutCubic
        }
        PauseAnimation { duration: 60 }
        ScriptAction {
            script: {
                // The login is fully obscured by the bright frame here.
                introVideo.visible = false
                movie.stop()
            }
        }
        NumberAnimation {
            target: glint
            property: "opacity"
            from: 1
            to: 0
            duration: 850
            easing.type: Easing.InOutCubic
        }
        ScriptAction {
            script: {
                intro.finished = true
                intro.completed()
                console.info("INGE_STARTUP_INTRO_COMPLETED loginOrRestoredSession=true")
            }
        }
    }
    // The movie is a presentation only: it must not prevent startup forever
    // if the Android decoder stalls or the media resource cannot be loaded.
    Timer {
        interval: 14500
        repeat: false
        running: intro.visible && !intro.transitioning
        onTriggered: intro.exitWithGlint("timeout")
    }
    // Tapping skips with the SAME glint instead of an abrupt hard cut.
    MouseArea {
        anchors.fill: parent
        enabled: !intro.transitioning
        onClicked: intro.exitWithGlint("skip")
    }
    Text {
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.rightMargin: 23
        anchors.topMargin: 38
        text: "Omitir"
        font.family: intro.fontFamily
        font.pixelSize: 13
        color: "#FFFFFF"
        opacity: intro.transitioning ? 0 : 0.72
    }
}

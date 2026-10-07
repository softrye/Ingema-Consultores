import QtQuick 2.15
import "../flowcore" as CoreFlow

Item {
    id: root
    property bool active: false
    property var flow
    property var words: ["Hola", "Rimaykullayki", "Welcome"]
    property color color: "#FFFFFF"
    property int wordIndex: 0
    property string currentWord: words.length ? words[wordIndex % words.length] : "Hola"

    height: 108

    Item {
        id: reveal
        anchors.centerIn: parent
        width: 0
        height: greeting.implicitHeight + 10
        clip: true
        CoreFlow.FlowText {
            id: greeting
            text: root.currentWord
            role: "display"
            color: root.color
            font.pixelSize: Math.round(Math.min(58, Math.max(42, root.width * 0.13)))
            font.italic: true
            font.weight: Font.Light
            font.letterSpacing: -0.8
            opacity: 1.0
        }
    }

    SequentialAnimation {
        id: cycle
        running: false
        loops: Animation.Infinite
        ScriptAction { script: { reveal.width = 0; greeting.opacity = 1.0 } }
        NumberAnimation { target: reveal; property: "width"; to: greeting.implicitWidth + 8; duration: root.flow ? root.flow.duration(820) : 820; easing.type: Easing.InOutCubic }
        PauseAnimation { duration: root.flow ? root.flow.duration(620) : 620 }
        NumberAnimation { target: greeting; property: "opacity"; to: 0.0; duration: root.flow ? root.flow.duration(260) : 260; easing.type: Easing.InCubic }
        ScriptAction { script: root.wordIndex = (root.wordIndex + 1) % root.words.length }
        PauseAnimation { duration: 80 }
    }

    onActiveChanged: {
        if (active) {
            wordIndex = 0
            cycle.restart()
        } else {
            cycle.stop()
            reveal.width = 0
        }
    }
}

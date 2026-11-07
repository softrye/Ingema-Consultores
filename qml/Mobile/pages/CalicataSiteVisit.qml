import QtQuick
import QtMultimedia
import ".." as Mobile
import "../components" as Components

// Portada de la ficha: el porcentaje procede del validador del formulario.
Item {
    id: visit
    property var ui
    property var flow
    property var editor
    property var snapshot: null
    signal openSection(int section)
    signal back()
    readonly property real u: ui ? ui.u : 1
    readonly property bool dark: editor ? editor.darkMode === true : false
    readonly property bool motion: !!flow && flow.motionAllowed && !flow.reduceMotion
    readonly property int percent: snapshot ? Math.max(0, Math.min(100, Number(snapshot.percent) || 0)) : 0
    readonly property string code: snapshot && snapshot.code ? String(snapshot.code) : "Sin código"
    readonly property real gutter: Math.max(20 * u, width * 0.065)
    property real flashOpacity: 0
    property bool openingEditor: false
    property int stillEngineerIndex: Math.floor(Math.random() * 3)
    readonly property var stillEngineerSources: ["qrc:/images/calicata/site-engineer.png",
        "qrc:/images/calicata/site-engineer-field.png", "qrc:/images/calicata/site-engineer-ingema.png"]
    Connections {
        target: visit.editor
        ignoreUnknownSignals: true
        function onSiteVisitActiveChanged() {
            if (visit.editor && visit.editor.siteVisitActive)
                visit.stillEngineerIndex = Math.floor(Math.random() * visit.stillEngineerSources.length)
        }
    }
    readonly property bool engineerAllowed: !!flow && flow.appSkin !== "ingenieros"
    readonly property string fidelity: flow && flow.graphicsCore ? String(flow.graphicsCore.fidelity || "") : ""
    readonly property bool videoTier: ["HIGH", "VERY_HIGH", "EXTREME"].indexOf(fidelity) >= 0
    readonly property bool playEngineer: engineerAllowed && videoTier && motion && visible
                                          && !!editor && editor.siteVisitActive
                                          && Qt.application["state"] === Qt.ApplicationActive

    // Captura la misma capa de auras de Calicatas, sin duplicar el motor visual.
    ShaderEffectSource {
        id: auraTexture
        sourceItem: visit.editor ? visit.editor.background : null
        hideSource: false
        visible: false
        live: visit.visible && !!sourceItem
        smooth: true
    }
    QtObject {
        id: glassHost
        readonly property var backdrop: visit.editor ? visit.editor.background : null
        readonly property var glassTexture: backdrop ? auraTexture : null
        readonly property bool glassReady: !!backdrop
        property int glassTick: 0
    }

    // Las auras existentes permanecen visibles bajo el tinte de la referencia.
    Rectangle {
        anchors.fill: parent
        color: visit.dark ? Qt.rgba(0.02, 0.22, 0.13, 0.72) : Qt.rgba(0.03, 0.35, 0.21, 0.65)
    }
    MouseArea { anchors.fill: parent }

    Item {
        id: backButton
        x: visit.gutter
        y: (visit.ui ? visit.ui.topInset : 0) + 10 * visit.u
        width: 48 * visit.u; height: width
        Mobile.DockGlassPanel { glassUi: glassHost; radius: backButton.width / 2; u: visit.u; lowFallback: false }
        Components.FlowIcon {
            anchors.centerIn: parent; width: 24 * visit.u; height: width
            name: "system.back"; flow: visit.flow; tintColor: "white"; activeTintColor: "white"; inactiveOpacity: 1
        }
        TapHandler { enabled: !visit.openingEditor; onTapped: visit.back() }
        Accessible.role: Accessible.Button
        Accessible.name: "Volver"
    }

    Column {
        id: titleColumn
        x: visit.gutter
        y: backButton.y + backButton.height + 24 * visit.u
        width: visit.width - 2 * visit.gutter
        spacing: 0
        Text {
            text: "Calicata"; color: "white"; font.family: visit.ui ? visit.ui.fontFamily : ""
            font.pixelSize: Math.min(42 * visit.u, visit.width * 0.105); font.bold: true
        }
        Text {
            width: parent.width; text: visit.code; color: "white"; elide: Text.ElideRight
            font.family: visit.ui ? visit.ui.fontFamily : ""
            font.pixelSize: Math.min(42 * visit.u, visit.width * 0.105); font.bold: true
        }
    }

    Column {
        id: progressColumn
        x: visit.gutter
        y: titleColumn.y + titleColumn.height + 22 * visit.u
        width: visit.width * 0.43
        Text {
            text: visit.snapshot ? visit.percent + "%" : "—"
            color: "white"; font.family: visit.ui ? visit.ui.fontFamily : ""
            font.pixelSize: Math.min(48 * visit.u, visit.width * 0.12); font.bold: true
        }
        Text {
            width: parent.width; text: "Estimación de\nrellenado"; wrapMode: Text.WordWrap
            color: Qt.rgba(1, 1, 1, 0.80); font.pixelSize: 16 * visit.u
        }
    }

    // Un solo reproductor, creado únicamente con el preset y ciclo de vida permitidos.
    Item {
        id: engineer
        width: Math.min(visit.width * 0.65, 340 * visit.u)
        height: Math.max(0, Math.min(visit.height * 0.47, editButton.y - progressColumn.y - 12 * visit.u))
        anchors.right: parent.right
        anchors.rightMargin: visit.gutter * 0.45
        y: Math.max(progressColumn.y + 10 * visit.u, editButton.y - height - 14 * visit.u)
        clip: true
        visible: visit.engineerAllowed
        enabled: false
        Image {
            anchors.fill: parent
            visible: visit.engineerAllowed && (!visit.videoTier || !visit.motion)
            source: visible ? visit.stillEngineerSources[visit.stillEngineerIndex] : ""
            asynchronous: true; cache: true; fillMode: Image.PreserveAspectFit
        }
        Loader {
            anchors.fill: parent
            active: visit.playEngineer
            sourceComponent: Component {
                Item {
                    clip: true
                    // El video permanece 16:9; se recortan solo los laterales verdes.
                    Item {
                        id: videoFrame
                        height: parent.height
                        width: height * 16 / 9
                        anchors.centerIn: parent
                        VideoOutput { id: engineerVideoOutput; anchors.fill: parent; fillMode: VideoOutput.PreserveAspectFit }
                        ShaderEffectSource {
                            id: videoTexture
                            anchors.fill: parent
                            sourceItem: engineerVideoOutput
                            hideSource: true; live: true; visible: false
                        }
                        ShaderEffect {
                            anchors.fill: parent
                            property var source: videoTexture
                            fragmentShader: "qrc:/InGe/Mobile/shaders/kawaii_chroma.frag.qsb"
                        }
                    }
                    MediaPlayer {
                        id: engineerPlayer
                        source: "qrc:/images/calicata/site-engineer-animated.mp4"
                        videoOutput: engineerVideoOutput
                        audioOutput: AudioOutput { muted: true; volume: 0 }
                        loops: MediaPlayer.Infinite
                        autoPlay: true
                        onErrorOccurred: function(error, errorString) {
                            console.warn("INGE_CALICATA_ENGINEER_MEDIA_ERROR", error, errorString)
                        }
                    }
                }
            }
        }
    }

    Item {
        id: editButton
        x: visit.gutter
        y: visit.height - height - Math.max(28 * visit.u, visit.ui && visit.ui.bottomInset !== undefined ? visit.ui.bottomInset : 0)
        width: visit.width - 2 * visit.gutter
        height: 76 * visit.u
        Mobile.DockGlassPanel {
            glassUi: glassHost; radius: editButton.height / 2; u: visit.u
            lowFallback: false; liquidTouch: true; reducedMotion: !visit.motion
        }
        Rectangle {
            width: 56 * visit.u; height: width; radius: width / 2
            anchors.left: parent.left; anchors.leftMargin: 9 * visit.u; anchors.verticalCenter: parent.verticalCenter
            color: Qt.rgba(1, 1, 1, 0.15); border.color: Qt.rgba(1, 1, 1, 0.45)
            Components.FlowIcon { anchors.centerIn: parent; width: 26 * visit.u; height: width; name: "action.edit"; flow: visit.flow; tintColor: "white"; activeTintColor: "white"; inactiveOpacity: 1 }
        }
        Text { anchors.centerIn: parent; text: "Editar"; color: "white"; font.pixelSize: 24 * visit.u; font.bold: true }
        Text { anchors.right: parent.right; anchors.rightMargin: 24 * visit.u; anchors.verticalCenter: parent.verticalCenter; text: "›››"; color: Qt.rgba(1, 1, 1, 0.7); font.pixelSize: 29 * visit.u }
        TapHandler {
            enabled: !visit.openingEditor
            onTapped: {
                visit.openingEditor = true
                if (visit.motion) flashTransition.start()
                else { visit.openSection(1); visit.openingEditor = false }
            }
        }
        Accessible.role: Accessible.Button
        Accessible.name: "Editar calicata"
    }
    Rectangle { anchors.fill: parent; z: 100; color: "white"; opacity: visit.flashOpacity; visible: opacity > 0; enabled: false }
    SequentialAnimation {
        id: flashTransition
        NumberAnimation { target: visit; property: "flashOpacity"; to: 0.72; duration: visit.flow ? visit.flow.duration(90) : 90; easing.type: Easing.OutQuad }
        ScriptAction { script: visit.openSection(1) }
        NumberAnimation { target: visit; property: "flashOpacity"; to: 0; duration: visit.flow ? visit.flow.duration(180) : 180; easing.type: Easing.InOutQuad }
        ScriptAction { script: visit.openingEditor = false }
    }
}

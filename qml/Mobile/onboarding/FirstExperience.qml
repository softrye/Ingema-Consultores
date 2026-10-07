pragma ComponentBehavior: Bound

import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15
import "../components" as Components
import "../flowcore" as CoreFlow
import "scenes" as Scenes

Item {
    id: root
    property var flow
    property var experience
    property var narrator
    property var experienceAudio
    property bool previewMode: false
    property bool showcaseMode: false
    property bool soundscapeEnabled: false
    property bool subtitlesEnabled: true
    property bool narrating: false
    property bool ambientStarted: false
    property int currentIndex: 0
    property int previousIndex: 0
    property string languageCode: experience ? experience.languageCode : "es"
    property int themeMode: 0
    property bool narrationEnabled: false
    readonly property int pageCount: 12
    property bool darkPresentation: false

    signal finished(string languageCode, int themeMode, int motionLevel, int performanceLevel)
    signal dismissed()

    function localeTag() {
        return languageCode === "en" ? "en-US" : (languageCode === "qu" ? "qu-PE" : "es-PE")
    }

    function tr(es, qu, en) {
        return languageCode === "en" ? en : (languageCode === "qu" ? qu : es)
    }

    function stopCurrentVoice() {
        narrationTimer.stop()
        narrationStateTimer.stop()
        narrating = false

        if (experienceAudio)
            experienceAudio.stopNarration()

        if (narrator)
            narrator.stop()
    }

    function ensureAmbient() {
        if (!visible || !soundscapeEnabled || ambientStarted)
            return

        if (experienceAudio && experienceAudio.available) {
            experienceAudio.playAmbient()
            ambientStarted = true
        }
    }

    function narrationFor(index) {
        var es = [
            "Hola. Bienvenido a InGe más. Una experiencia creada para transformar el trabajo de campo en información clara, segura y útil.",
            "InGe más nace del compromiso de INGEMA Consultores: precisión técnica, responsabilidad, eficiencia, confianza, seguridad e innovación.",
            "Elige tu idioma. La interfaz, las ayudas y la narración se adaptarán a tu forma de trabajar.",
            "Personaliza la apariencia, la voz y la intensidad del movimiento. El modo Premium está optimizado para mostrar todo el potencial de InGeCoreFlow.",
            "InGeCoreFlow conecta cada gesto, transición y respuesta visual. El movimiento no es adorno: ayuda a comprender, orientar y confirmar cada acción.",
            "En Inicio encontrarás tus módulos, el proyecto activo, el estado del GPS y la sincronización. Todo lo importante, en un solo lugar.",
            "Con el botón Crear puedes iniciar una ficha, registrar datos, tomar fotografías, capturar coordenadas y validar el trabajo sin perder el contexto.",
            "El mapa vincula ubicación, evidencia y puntos técnicos. Cada registro queda conectado con el proyecto y listo para regresar a oficina.",
            "Cuando no hay internet, InGe más continúa. Guarda localmente, muestra el estado de cada cambio y sincroniza cuando vuelve la señal.",
            "Convierte tus fichas en Excel editable, PDF, fotografías organizadas y documentos listos para compartir o respaldar en la nube.",
            "Tu información merece claridad y control. Cámara, ubicación y archivos se solicitan solo cuando son necesarios y con un propósito visible.",
            "Todo está listo. InGe más fue desarrollado por JuanPablo Ramos Rosas y Fernando Quispe Rosas, con el liderazgo de Paola Rosas Gonzales, CEO de INGEMA Consultores."
        ]
        var en = [
            "Hello. Welcome to InGe Plus, an experience designed to turn field work into clear, secure and useful information.",
            "InGe Plus reflects the commitment of INGEMA Consultores: technical precision, responsibility, efficiency, trust, safety and innovation.",
            "Choose your language. The interface, guidance and narration will adapt to the way you work.",
            "Personalize appearance, voice and motion intensity. Premium mode is optimized to demonstrate the full potential of InGeCoreFlow.",
            "InGeCoreFlow connects every gesture, transition and visual response. Motion is not decoration. It guides, explains and confirms each action.",
            "Home brings together your modules, active project, GPS status and synchronization. Everything important, in one place.",
            "Use the Create button to start a field record, enter data, take photos, capture coordinates and validate the work without losing context.",
            "The map links location, evidence and technical points. Every record stays connected to the project and ready for the office.",
            "When the internet is unavailable, InGe Plus keeps working. It saves locally, shows every status and synchronizes when the signal returns.",
            "Turn field records into editable Excel files, PDF reports, organized photographs and cloud-ready documents.",
            "Your information deserves clarity and control. Camera, location and files are requested only when needed, with a visible purpose.",
            "Everything is ready. InGe Plus was developed by JuanPablo Ramos Rosas and Fernando Quispe Rosas, under the leadership of Paola Rosas Gonzales, CEO of INGEMA Consultores."
        ]
        var qu = [
            "Rimaykullayki. InGe másman allin hamusqayki. Campo llamk'ayta sut'i, seguro, allin informaciónman tikraypaqmi kay experiencia.",
            "InGe másqa INGEMA Consultorespa compromiso nisqanta rikuchin: yachay, responsabilidad, eficiencia, confianza, seguridad, innovación.",
            "Rimayniykita akllay. Interfaz, yanapaynin, rimayninpas llamk'aynikiwan tupachikunqa.",
            "Rikch'ayta, rimayta, kuyuriyninta akllay. Premium modoqa InGeCoreFlowpa tukuy atiyta rikuchin.",
            "InGeCoreFlowqa sapa gesto, transición, respuesta visualta huñun. Kuyuriyqa mana adornollachu; yanapan, sut'ichan, confirmanku.",
            "Iniciopi módulos, proyecto activo, GPS, sincronizaciónta hukllapi tarinki.",
            "Crear botónwan ficha qallariy, datos qillqay, foto hap'iy, coordenada chaskiy, llamk'ayta validayta atinki.",
            "Mapaqa ubicación, evidencia, punto técnicokunata proyectowan huñun.",
            "Internet mana kaptinpas InGe más llamk'an. Localpi waqaychan, estado rikuchin, señal kutimuptin sincronizan.",
            "Fichaqa Excel editable, PDF, foto ordenasqa, nube documentoman tikrakun.",
            "Informaciónniykiqa controlta munan. Cámara, ubicación, archivokunaqa necesario kaptinlla mañakun.",
            "Tukuy wakichisqañam. InGe másqa JuanPablo Ramos Rosas, Fernando Quispe Rosas ruwasqan, Paola Rosas Gonzalespa umalliqninwan."
        ]
        var list = languageCode === "en" ? en : (languageCode === "qu" ? qu : es)
        return list[Math.max(0, Math.min(index, list.length - 1))]
    }

    function sceneSfx(index) {
        var cues = ["sfx_logo", "sfx_select", "sfx_select", "sfx_select", "sfx_pulse", "sfx_tap", "sfx_success", "sfx_map_ping", "sfx_offline", "sfx_sync", "sfx_privacy", "sfx_ready"]
        return cues[Math.max(0, Math.min(index, cues.length - 1))]
    }

    function speakCurrent() {
        if (!narrationEnabled) return
        narrating = true
        narrationStateTimer.restart()
        var usedBundled = false
        if (experienceAudio && experienceAudio.available) {
            experienceAudio.stopNarration()
            usedBundled = experienceAudio.playNarration(currentIndex, languageCode)
        }
        if (!usedBundled && narrator && narrator.available) {
            narrator.stop()
            narrator.speak(narrationFor(currentIndex), localeTag(), 0.92, 1.0)
        }
    }

    function playSceneCue() {
        if (experienceAudio && experienceAudio.available && soundscapeEnabled)
            experienceAudio.playSfx(sceneSfx(currentIndex), 0.82)
    }

    function setIndex(index) {
        var nextIndex = Math.max(0, Math.min(pageCount - 1, index))
        if (nextIndex === currentIndex)
            return

        stopCurrentVoice()
        previousIndex = currentIndex
        currentIndex = nextIndex
        pager.currentIndex = currentIndex
        transitionFlash.restart()
    }

    function next() {
        if (currentIndex >= pageCount - 1) {
            finishExperience()
            return
        }
        if (experienceAudio && soundscapeEnabled) experienceAudio.playSfx("sfx_scene_forward", 0.66)
        setIndex(currentIndex + 1)
    }

    function previous() {
        if (currentIndex <= 0) return
        if (experienceAudio && soundscapeEnabled) experienceAudio.playSfx("sfx_scene_back", 0.62)
        setIndex(currentIndex - 1)
    }

    function finishExperience() {
        stopCurrentVoice()
        ambientStarted = false
        if (experienceAudio)
            experienceAudio.stopAll()
        if (experience) {
            experience.setLanguageCode(languageCode)
            experience.setThemeMode(0)
            experience.setMotionLevel(2)
            experience.setPerformanceLevel(2)
            experience.setNarrationEnabled(narrationEnabled)
            experience.complete()
        }
        completionVeil.restart()
    }

    function skip() {
        stopCurrentVoice()
        ambientStarted = false
        if (experienceAudio)
            experienceAudio.stopAll()
        if (previewMode) {
            root.dismissed()
            return
        }
        finishExperience()
    }

    Component.onCompleted: {
        currentIndex = previewMode ? 0 : Math.max(0, Math.min(pageCount - 1, experience ? experience.lastScene : 0))
        pager.currentIndex = currentIndex
        if (visible) startupTimer.restart()
    }

    onVisibleChanged: {
        if (visible) {
            startupTimer.restart()
        } else {
            stopCurrentVoice()
            autoplayTimer.stop()
            ambientStarted = false
            if (experienceAudio)
                experienceAudio.stopAll()
        }
    }

    onCurrentIndexChanged: {
        stopCurrentVoice()

        if (experience && !previewMode)
            experience.setLastScene(currentIndex)

        narrationTimer.restart()
        playSceneCue()

        if (showcaseMode)
            autoplayTimer.restart()
    }

    onLanguageCodeChanged: {
        stopCurrentVoice()
        narrationTimer.restart()
    }
    onNarrationEnabledChanged: {
        if (!narrationEnabled) {
            narrating = false
            if (narrator) narrator.stop()
            if (experienceAudio) experienceAudio.stopNarration()
        } else narrationTimer.restart()
    }

    Timer {
        id: startupTimer
        interval: 260
        repeat: false
        onTriggered: {
            root.ensureAmbient()
            narrationTimer.restart()
            root.playSceneCue()
        }
    }

    Timer {
        id: narrationTimer
        interval: 900
        repeat: false
        onTriggered: {
            if (root.visible)
                root.speakCurrent()
        }
    }

    Timer {
        id: narrationStateTimer
        interval: 9000
        repeat: false
        onTriggered: root.narrating = false
    }
    Timer { id: autoplayTimer; interval: 9000; repeat: false; onTriggered: { if (!root.showcaseMode) return; if (root.currentIndex < root.pageCount - 1) root.next(); else root.finishExperience() } }

    Rectangle {
        anchors.fill: parent
        color: root.darkPresentation ? "#06101D" : "#F4F9FD"
    }

    SwipeView {
        id: pager
        anchors.fill: parent
        visible: true
        enabled: true
        currentIndex: root.currentIndex
        interactive: !root.showcaseMode
        clip: true
        onCurrentIndexChanged: {
            if (root.currentIndex !== currentIndex) {
                root.previousIndex = root.currentIndex
                root.currentIndex = currentIndex
            }
        }

        Scenes.WelcomeScene {
            active: SwipeView.isCurrentItem
            flow: root.flow
            languageCode: root.languageCode
            dark: root.darkPresentation
        }

        Scenes.CommitmentScene {
            active: SwipeView.isCurrentItem
            flow: root.flow
            languageCode: root.languageCode
            dark: root.darkPresentation
        }

        Scenes.LanguageScene {
            active: SwipeView.isCurrentItem
            flow: root.flow
            languageCode: root.languageCode
            dark: root.darkPresentation

            onLanguageSelected: function(code) {
                root.stopCurrentVoice()
                root.languageCode = code

                if (root.experience)
                    root.experience.setLanguageCode(code)

                if (root.experienceAudio && root.soundscapeEnabled)
                    root.experienceAudio.playSfx("sfx_select", 0.8)

                narrationTimer.restart()
            }
        }

        Scenes.PersonalizationScene {
            active: SwipeView.isCurrentItem
            flow: root.flow
            languageCode: root.languageCode
            dark: root.darkPresentation
            themeMode: root.themeMode
            narrationEnabled: root.narrationEnabled

            onThemeSelected: function(mode) {
                root.themeMode = 0

                if (root.experience)
                    root.experience.setThemeMode(0)

                if (root.experienceAudio && root.soundscapeEnabled)
                    root.experienceAudio.playSfx("sfx_select", 0.75)
            }

            onNarrationSelected: function(enabled) {
                root.narrationEnabled = enabled

                if (root.experience)
                    root.experience.setNarrationEnabled(enabled)
            }
        }

        Scenes.MotionLabScene {
            active: SwipeView.isCurrentItem
            flow: root.flow
            languageCode: root.languageCode
            dark: root.darkPresentation
        }

        Scenes.HomeTourScene {
            active: SwipeView.isCurrentItem
            flow: root.flow
            languageCode: root.languageCode
            dark: root.darkPresentation
        }

        Scenes.CreateTourScene {
            active: SwipeView.isCurrentItem
            flow: root.flow
            languageCode: root.languageCode
            dark: root.darkPresentation
        }

        Scenes.MapTourScene {
            active: SwipeView.isCurrentItem
            flow: root.flow
            languageCode: root.languageCode
            dark: root.darkPresentation
        }

        Scenes.OfflineScene {
            active: SwipeView.isCurrentItem
            flow: root.flow
            languageCode: root.languageCode
            dark: root.darkPresentation
        }

        Scenes.DocumentsScene {
            active: SwipeView.isCurrentItem
            flow: root.flow
            languageCode: root.languageCode
            dark: root.darkPresentation
        }

        Scenes.PrivacyScene {
            active: SwipeView.isCurrentItem
            flow: root.flow
            languageCode: root.languageCode
            dark: root.darkPresentation
        }

        Scenes.ReadyScene {
            active: SwipeView.isCurrentItem
            flow: root.flow
            languageCode: root.languageCode
            dark: root.darkPresentation
        }
    }

    Rectangle {
        id: transitionVeil
        anchors.fill: parent
        color: root.currentIndex % 3 === 0 ? "#8FB2D5" : (root.currentIndex % 3 === 1 ? "#0654A2" : "#486426")
        opacity: 0
        z: 18
    }
    SequentialAnimation {
        id: transitionFlash
        NumberAnimation {
            target: transitionVeil
            property: "opacity"
            from: 0
            to: 0.075
            duration: root.flow
                      ? root.flow.motion.policy(root.flow.motion.navigationForward).duration
                      : 180
            easing.type: root.flow
                         ? root.flow.motion.policy(root.flow.motion.navigationForward).easing
                         : Easing.OutCubic
        }
        NumberAnimation {
            target: transitionVeil
            property: "opacity"
            from: 0.075
            to: 0
            duration: root.flow ? root.flow.normalDuration : 180
            easing.type: Easing.OutCubic
        }
    }

    Item {
        id: topChrome
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        height: Math.max(68, Math.min(82, root.height * 0.09))
        z: 20

        Rectangle {
            anchors.fill: parent
            gradient: Gradient {
                GradientStop {
                    position: 0.0
                    color: root.darkPresentation ? "#E006101D" : "#F8F4F9FD"
                }
                GradientStop {
                    position: 1.0
                    color: "transparent"
                }
            }
        }

        Row {
            anchors.left: parent.left
            anchors.leftMargin: Math.max(12, parent.width * 0.032)
            anchors.verticalCenter: parent.verticalCenter
            spacing: 8

            ControlPill {
                label: root.narrationEnabled ? root.tr("Voz", "Rimay", "Voice") : root.tr("Sin voz", "Mana rimay", "Muted")
                selected: root.narrationEnabled
                onClicked: root.narrationEnabled = !root.narrationEnabled

                NarrationWave {
                    anchors.right: parent.right
                    anchors.rightMargin: 9
                    anchors.verticalCenter: parent.verticalCenter
                    active: root.narrating && root.narrationEnabled
                    flow: root.flow
                    color: root.darkPresentation ? "#8FB2D5" : "#0654A2"
                }
            }

            ControlPill {
                label: root.showcaseMode ? root.tr("Demo ON", "Demo ON", "Demo ON") : root.tr("Demo", "Demo", "Demo")
                selected: root.showcaseMode
                onClicked: {
                    root.showcaseMode = !root.showcaseMode
                    if (root.showcaseMode) autoplayTimer.restart(); else autoplayTimer.stop()
                    if (root.experienceAudio && root.soundscapeEnabled) root.experienceAudio.playSfx("sfx_select", 0.65)
                }
            }
        }

        CoreFlow.FlowGlassButton {
            id: skipButton
            anchors.right: parent.right
            anchors.rightMargin: Math.max(12, parent.width * 0.032)
            anchors.verticalCenter: parent.verticalCenter
            width: Math.max(82, implicitWidth)
            height: 42
            text: root.previewMode
                  ? root.tr("Cerrar", "Wichq'ay", "Close")
                  : root.tr("Omitir", "Saqiy", "Skip")
            iconName: root.previewMode ? "action.close" : ""
            onClicked: root.skip()
        }
    }

    CoreFlow.FlowGlassSurface {
        id: bottomChrome
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.leftMargin: Math.max(10, parent.width * 0.024)
        anchors.rightMargin: Math.max(10, parent.width * 0.024)
        anchors.bottomMargin: Math.max(8, Math.min(16, parent.height * 0.014))
        height: Math.max(116, Math.min(128, root.height * 0.15))
        radius: Math.min(30, height * 0.24)
        flow: root.flow
        darkMode: root.darkPresentation
        strength: 1.0
        z: 20

        OnboardingProgress {
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.top: parent.top
            anchors.topMargin: 10
            count: root.pageCount
            currentIndex: root.currentIndex
            flow: root.flow
            dark: root.darkPresentation
        }

        Row {
            id: swipeHint
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.top: parent.top
            anchors.topMargin: 32
            height: 18
            spacing: 5
            opacity: root.currentIndex === 0 ? 0.82 : 0.0
            visible: opacity > 0

            Behavior on opacity {
                NumberAnimation {
                    duration: root.flow
                              ? root.flow.motion.policy(root.flow.motion.enterFade).duration
                              : 180
                }
            }

            CoreFlow.FlowText {
                anchors.verticalCenter: parent.verticalCenter
                text: root.tr("Desliza hacia el costado", "Waqta lawman suchuy", "Swipe sideways")
                role: "caption"
                color: root.darkPresentation ? "#D6E7F5" : "#536176"
                font.letterSpacing: 0.15
            }

            Components.FlowIcon {
                anchors.verticalCenter: parent.verticalCenter
                width: 14
                height: 14
                name: "system.chevronRight"
                flow: root.flow
                tintColor: root.darkPresentation ? "#D6E7F5" : "#0654A2"
                activeTintColor: tintColor
                inactiveOpacity: 1.0
                pulseOnActive: false

                transform: Translate {
                    id: swipeHintOffset
                }
            }

            SequentialAnimation {
                running: Boolean(root.currentIndex === 0
                                 && root.visible
                                 && root.flow
                                 && root.flow.motionAllowed)
                loops: Animation.Infinite

                NumberAnimation {
                    target: swipeHintOffset
                    property: "x"
                    from: -2
                    to: 5
                    duration: root.flow ? root.flow.duration(700) : 700
                    easing.type: Easing.InOutSine
                }

                NumberAnimation {
                    target: swipeHintOffset
                    property: "x"
                    from: 5
                    to: -2
                    duration: root.flow ? root.flow.duration(700) : 700
                    easing.type: Easing.InOutSine
                }
            }
        }

        RowLayout {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 10
            anchors.leftMargin: 12
            anchors.rightMargin: 12
            spacing: 12

            CoreFlow.FlowGlassButton {
                Layout.preferredWidth: root.currentIndex > 0
                                       ? Math.max(92, Math.min(112, bottomChrome.width * 0.28))
                                       : 0
                Layout.preferredHeight: 48
                visible: root.currentIndex > 0
                enabled: root.currentIndex > 0
                text: root.tr("Atrás", "Qhipa", "Back")
                iconName: "system.back"
                onClicked: root.previous()
            }

            CoreFlow.FlowButton {
                Layout.fillWidth: true
                Layout.preferredHeight: 48
                variant: root.flow
                         ? root.flow.variant.buttonPrimary
                         : "button.primary"
                text: root.currentIndex === root.pageCount - 1
                      ? root.tr("Comenzar", "Qallariy", "Start")
                      : root.tr("Continuar", "Qatiy", "Continue")
                iconName: root.currentIndex === root.pageCount - 1
                          ? "status.success"
                          : ""
                onClicked: root.next()
            }
        }
    }

    Rectangle {
        id: completionLayer
        anchors.fill: parent
        color: "#07111F"
        opacity: 0
        visible: opacity > 0
        z: 100
        Image { anchors.centerIn: parent; width: Math.min(parent.width * 0.62, 290); height: width; source: "qrc:/raw/qml/Mobile/onboarding/assets/ready_constellation.svg"; fillMode: Image.PreserveAspectFit }
    }
    SequentialAnimation {
        id: completionVeil
        NumberAnimation { target: completionLayer; property: "opacity"; from: 0; to: 1; duration: root.flow ? root.flow.duration(420) : 420; easing.type: Easing.InCubic }
        PauseAnimation { duration: 180 }
        ScriptAction { script: root.finished(root.languageCode, 0, 2, 2) }
    }

    component ControlPill: CoreFlow.FlowGlassSurface {
        id: pill
        property string label: ""
        property bool selected: false
        signal clicked()
        width: Math.max(74, pillLabel.implicitWidth + (selected ? 44 : 24))
        height: 40
        radius: 16
        flow: root.flow
        darkMode: root.darkPresentation
        strength: selected ? 1.18 : 0.92
        border.color: selected
                      ? "#8FB2D5"
                      : (root.darkPresentation ? "#38FFFFFF" : "#55FFFFFF")
        scale: pillMouse.pressed && root.flow ? root.flow.pressScale : 1

        Behavior on scale {
            NumberAnimation {
                duration: root.flow
                          ? root.flow.motion.policy(root.flow.motion.pressStandard).duration
                          : 105
                easing.type: Easing.OutCubic
            }
        }

        CoreFlow.FlowText {
            id: pillLabel
            anchors.left: parent.left
            anchors.leftMargin: 12
            anchors.verticalCenter: parent.verticalCenter
            text: pill.label
            role: "caption"
            color: root.darkPresentation ? "white" : "#151A30"
            font.weight: Font.DemiBold
        }

        MouseArea {
            id: pillMouse
            anchors.fill: parent
            onClicked: pill.clicked()
        }
    }
}

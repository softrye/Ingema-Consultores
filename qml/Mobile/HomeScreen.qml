import QtQuick
import QtQuick.Effects
import QtQuick.Shapes
import QtCore
import InGe 1.0
import "lib/AccountText.js" as AccountText

// Home V1 de InGe+ (2026-10-12; Preview 1). Fondo fotográfico real
// (assets/home, fotos originales del usuario), saludo verificado, tarjetas de
// material glass sobrio (sin Liquid Glass), cuadrícula dinámica persistida
// por userId, dock Home/Perfil/Ajustes y botón InGe IA. El Home es estático:
// sin animaciones permanentes. Datos reales: CalicataCloud (proyectos y
// calicatas), AuthSession, OnboardingState e InGeAssistant (si disponible).
Item {
    id: home

    property real u: 1
    property string fontFamily: ""
    property string iconFamily: ""
    property bool reducedMotion: false
    signal signOutRequested()

    // ------------------------------------------------------------ Paleta
    readonly property color navy: "#151A30"
    readonly property color navy2: "#1C2D50"
    readonly property color brandBlue: "#0654A2"
    readonly property color brandGreen: "#486426"
    readonly property color glassFill: Qt.rgba(28 / 255, 45 / 255, 80 / 255, 0.50)
    readonly property color glassBorder: Qt.rgba(1, 1, 1, 0.22)

    // Material glass: textura desenfocada COMPARTIDA de la fotografía
    // (GlassSurface.qml + shaders/glass.frag). glassTick avisa a cada
    // superficie de que su posición sobre la foto cambió.
    readonly property Item backdrop: photoImage
    readonly property var glassTexture: glassTextureSource
    property int glassTick: 0
    onWidthChanged: glassTick++
    onHeightChanged: glassTick++

    // ---------------------------------------------------------- Identidad
    readonly property bool authReady: typeof auth !== "undefined" && auth !== null
    readonly property string userId: authReady && auth.logged ? auth.userId : ""
    readonly property string firstName: {
        if (!authReady || !auth.logged)
            return ""
        if (typeof onboarding !== "undefined" && onboarding) {
            var stored = onboarding.verifiedNameFor(auth.userId)
            if (AccountText.hasVisibleText(stored))
                return stored
        }
        return AccountText.greetingFirstName(AccountText.hasVisibleText(auth.nombre) ? auth.nombre
                                             : (auth.profileReady ? auth.fullName : ""))
    }

    // --------------------------------------------------------- Navegación
    property string page: "home"            // home | profile | settings | calicatas | earth | rendiciones | drive
    property bool addOpen: false
    property string calicataProjectId: ""
    property var selectedCalicata: null
    function navigate(target) {
        if (isComingSoonPage(target)) {           // ninguna ruta del Home lo elude
            notifyComingSoon(target)
            return
        }
        addOpen = false
        page = target
    }
    function openCalicatas(projectId, calicataId) {
        page = "calicatas"
        calicataProjectId = projectId || ""
        selectedCalicata = null
        pendingCalicataId = calicataId || ""
        if (calicataProjectId.length > 0)
            CalicataCloud.listProjectCalicatas(calicataProjectId)
        else
            CalicataCloud.refreshProjects()
    }
    property string pendingCalicataId: ""

    // Back de Android: cierra el panel o vuelve al inicio antes de salir.
    // Prioridad: transición en curso > editor (handleBack) > menús > páginas.
    // true = consumido. Nunca cierra la Activity ni termina Qt.
    property double lastBackMs: 0
    property bool lastBackResult: false
    function handleBack(source) {
        var now = Date.now()
        if (now - lastBackMs < 300)
            return lastBackResult                // misma pulsación por otra ruta
        lastBackMs = now
        lastBackResult = handleBackStep(source)
        return lastBackResult
    }
    function handleBackStep(source) {
        console.info("INGE_NAV_BACK_SOURCE " + source + " page=" + page)
        if (subAppEnter.running || subAppExit.running)
            return true
        if ((page === "calicatas" || page === "earth") && dockPath.length > 0) {   // submenú del dock
            dockPath = dockPath.slice(0, -1)
            return true
        }
        if (page === "calicatas" && calicatasEditor.item) {
            // Atrás pasa primero por el editor original (popups, etapas, guardado).
            var handled = calicatasEditor.item.handleBack !== undefined && calicatasEditor.item.handleBack()
            if (!handled)
                page = "home"
            return true
        }
        if (optionsCard) { closeOptions(); return true }
        else if (menuKey.length > 0) { closeMenu(false); return true }
        else if (editMode) { exitEditMode(); return true }
        else if (addOpen) { closeAdd(); return true }
        else if (selectedCalicata) { selectedCalicata = null; return true }
        else if (page === "calicatas" && calicataProjectId.length > 0) { calicataProjectId = ""; return true }
        else if (page === "earth") { page = earthReturnPage; earthReturnPage = "home"; return true }
        else if (page !== "home") { page = "home"; return true }
        else return false
    }
    Keys.onBackPressed: function(event) { event.accepted = home.handleBack("key") }

    // ----------------------------------------------- Personalización local
    // Preferencias por userId (QSettings vía QtCore.Settings). Sin datos
    // sensibles: solo claves, tipos e identificadores estables de destino.
    Settings {
        id: store
        category: "home_v1"
        property bool dockHintShown: false   // guía breve del dock de subapps
        property string layoutsJson: "{}"
        property string greetingsJson: "{}"
        property bool remindersEnabled: true
        onRemindersEnabledChanged: home.syncReminders()
    }
    // Recordatorios: solo con una acción pendiente verificable (cambios de
    // calicatas sin sincronizar, dato real de CalicataCloud).
    function syncReminders() {
        if (typeof Perms === "undefined" || !Perms || userId.length === 0)
            return
        Perms.updateReminders(store.remindersEnabled, CalicataCloud.pendingActivityCount)
    }
    // Tarjetas del Home (V2): ListModel por usuario. Las cuatro predeterminadas
    // también se pueden quitar, reordenar y personalizar. Quitar una tarjeta
    // solo cambia el Home: nunca borra proyectos, calicatas ni datos remotos.
    ListModel { id: homeModel }
    property bool animateAdds: false
    property var items: []                        // claves visibles (Agregar)
    property var pendingCard: null
    readonly property var defaultCards: [
        { key: "app:calicatas", type: "app", kind: "calicatas_app", title: "Calicatas", subtitle: "Registro y gestión de calicatas", primary: true },
        { key: "app:rendiciones", type: "app", kind: "rendiciones_app", title: "Rendiciones", subtitle: "Control de gastos de campo", primary: false },
        { key: "app:earth", type: "app", kind: "earth_app", title: "InGe Earth", subtitle: "Visor de información geotécnica", primary: false },
        { key: "app:drive", type: "app", kind: "drive_app", title: "InGe Drive", subtitle: "Gestión de proyectos en campo", primary: false }
    ]
    readonly property var removedApps: defaultCards.filter(function(c) { return items.indexOf(c.key) < 0 })
    function readMap(json) { try { var m = JSON.parse(json); return m && typeof m === "object" ? m : {} } catch (e) { return {} } }
    function normalizeCard(c) {
        var sizes = ["compact", "normal", "wide"]
        var presentations = ["full", "iconName", "icon", "name"]
        var type = String(c.type || "tool")
        return {
            key: String(c.key || ""), type: type, kind: String(c.kind || ""),
            title: String(c.title || ""), subtitle: String(c.subtitle || ""),
            customTitle: String(c.customTitle || ""),
            presentation: presentations.indexOf(c.presentation) >= 0 ? c.presentation : "full",
            size: sizes.indexOf(c.size) >= 0 ? c.size
                  : (c.span === 2 ? "wide" : (type === "app" || type === "widget" ? "normal" : "compact")),
            targetId: String(c.targetId || ""), projectId: String(c.projectId || ""),
            primary: c.primary === true
        }
    }
    function cardAt(i) {
        var m = homeModel.get(i)
        return { key: m.key, type: m.type, kind: m.kind, title: m.title, subtitle: m.subtitle,
                 customTitle: m.customTitle, presentation: m.presentation, size: m.size,
                 targetId: m.targetId, projectId: m.projectId, primary: m.primary }
    }
    function indexOfKey(key) {
        for (var i = 0; i < homeModel.count; ++i)
            if (homeModel.get(i).key === key)
                return i
        return -1
    }
    function refreshKeys() {
        var keys = []
        for (var i = 0; i < homeModel.count; ++i)
            keys.push(homeModel.get(i).key)
        items = keys
    }
    function loadItems() {
        animateAdds = false
        homeModel.clear()
        var stored = userId.length > 0 ? readMap(store.layoutsJson)[userId] : undefined
        var cards
        if (stored && stored.v === 2 && Array.isArray(stored.cards))
            cards = stored.cards
        else
            cards = defaultCards.concat(Array.isArray(stored) ? stored : [])   // migración V1
        var seen = {}
        for (var i = 0; i < cards.length; ++i) {
            var c = normalizeCard(cards[i] || {})
            if (c.key.length === 0 || seen[c.key])
                continue
            seen[c.key] = true
            homeModel.append(c)
        }
        refreshKeys()
        Qt.callLater(function() { home.animateAdds = true })
    }
    function saveItems() {
        refreshKeys()
        if (userId.length === 0)
            return
        var cards = []
        for (var i = 0; i < homeModel.count; ++i)
            cards.push(cardAt(i))
        var all = readMap(store.layoutsJson)
        all[userId] = { v: 2, cards: cards }
        store.layoutsJson = JSON.stringify(all)
    }
    function itemKeys() { return items }
    // Confirmación en el panel: se cierra y luego aparece la tarjeta (popup).
    function addItem(item) {
        if (!item || items.indexOf(item.key) >= 0)
            return                                  // sin duplicados
        pendingCard = normalizeCard(item)
        closeAdd()
    }
    function flushPendingCard() {
        if (!pendingCard)
            return
        if (items.indexOf(pendingCard.key) < 0)
            homeModel.append(pendingCard)
        pendingCard = null
        saveItems()
    }
    function removeItem(key) {
        var i = indexOfKey(key)
        if (i >= 0)
            homeModel.remove(i)
        saveItems()
    }
    function updateCard(key, field, value) {
        var i = indexOfKey(key)
        if (i < 0)
            return
        homeModel.setProperty(i, field, value)
        saveItems()
        if (optionsCard && optionsCard.key === key)
            optionsCard = cardAt(i)
    }

    // Arrastre: pulsación prolongada eleva la tarjeta; al pasar sobre otra se
    // reordena el modelo (las vecinas se acomodan con animación).
    property string dragKey: ""
    property real dragDx: 0
    property real dragDy: 0
    property bool dragMoved: false
    property point dragGrab: Qt.point(0, 0)
    function beginDrag(tile, mouse) {
        editMode = true                       // reorganizar = modo edición (como iOS)
        dragKey = tile.cardKey
        dragMoved = false
        dragGrab = Qt.point(mouse.x, mouse.y)
        dragDx = 0
        dragDy = 0
    }
    function dragTo(tile, mouse) {
        var p = tile.mapToItem(grid, mouse.x, mouse.y)
        dragDx = p.x - (tile.x + dragGrab.x)
        dragDy = p.y - (tile.y + dragGrab.y)
        if (Math.abs(dragDx) + Math.abs(dragDy) > 12 * u)
            dragMoved = true
        // La tarjeta arrastrada no sale de la cuadrícula.
        dragDx = Math.max(-tile.x, Math.min(grid.width - tile.width - tile.x, dragDx))
        dragDy = Math.max(-tile.y, Math.min(grid.height - tile.height - tile.y, dragDy))
        glassTick++
        for (var i = 0; i < grid.children.length; ++i) {
            var other = grid.children[i]
            if (other === tile || other.cardKey === undefined || other.cardKey.length === 0
                    || other.modelIndex < 0 || !other.visible)
                continue
            if (p.x >= other.x && p.x <= other.x + other.width && p.y >= other.y && p.y <= other.y + other.height) {
                if (other.modelIndex !== tile.modelIndex)
                    homeModel.move(tile.modelIndex, other.modelIndex, 1)
                break
            }
        }
    }
    function endDrag(tile) {
        var moved = dragMoved
        dragKey = ""
        dragDx = 0
        dragDy = 0
        if (moved)
            saveItems()
    }

    // ---------------------------------- Menú contextual (estilo Haptic Touch)
    // Pulsación prolongada (450 ms): la tarjeta se comprime (0.97), una copia
    // elevada (liftGhost) crece hasta 1.03 por delante del entorno atenuado y
    // desenfocado, y aparece el menú junto a ella. Si el dedo se desplaza
    // antes de soltar, el menú se cierra y empieza el arrastre (nunca ambos).
    property var optionsCard: null
    property string menuKey: ""                 // tarjeta con menú abierto
    property bool menuArmed: false              // la misma pulsación sigue activa
    property string liftKey: ""                 // tarjeta representada por liftGhost
    property var liftCard: null
    property rect menuRect: Qt.rect(0, 0, 0, 0) // tarjeta de origen (coords. de home)
    property real menuProgress: 0
    property real ghostLift: 0
    property real ghostFrom: 0.97
    property real overlayLevel: 0               // atenuación + desenfoque del entorno
    property real sheetGrow: 0                  // expansión de Personalizar
    property rect sheetFrom: Qt.rect(0, 0, 0, 0)
    property bool editMode: false               // Jiggle Mode
    function lerpValue(a, b, t) { return a + (b - a) * t }
    function haptic() {
        if (typeof Perms !== "undefined" && Perms)
            Perms.hapticLongPress()
    }
    function cardRect(key) {
        for (var i = 0; i < grid.children.length; ++i) {
            var t = grid.children[i]
            if (t.cardKey === key) {
                var p = grid.mapToItem(home, t.x, t.y)
                return Qt.rect(p.x, p.y, t.width, t.height)
            }
        }
        return menuRect
    }
    function openMenu(tile) {
        var i = indexOfKey(tile.cardKey)
        if (i < 0 || optionsCard)
            return
        liftCard = cardAt(i)
        var p = tile.parent.mapToItem(home, tile.x, tile.y)   // sin la compresión
        menuRect = Qt.rect(p.x, p.y, tile.width, tile.height)
        menuCloseAnim.stop()
        ghostDropAnim.stop()
        menuKey = tile.cardKey
        liftKey = tile.cardKey
        menuArmed = true
        ghostFrom = 0.97
        if (reducedMotion) { ghostLift = 1; menuProgress = 1; overlayLevel = 1; return }
        ghostLift = 0
        menuProgress = 0
        menuOpenAnim.restart()
    }
    function closeMenu(immediate) {
        menuArmed = false
        if (menuKey.length === 0 && liftKey.length === 0)
            return
        menuOpenAnim.stop()
        if (immediate || reducedMotion) {
            menuCloseAnim.stop()
            ghostDropAnim.stop()
            menuProgress = 0
            ghostLift = 0
            menuKey = ""
            liftKey = ""
            if (!optionsCard)
                overlayLevel = 0
            return
        }
        if (menuCloseAnim.running)
            return
        ghostFrom = 1.0
        menuCloseAnim.restart()
    }
    function menuAction(action) {
        if (action === "custom") {
            openPersonalize()
        } else if (action === "edit") {
            closeMenu(false)
            editMode = true
        } else if (action === "remove") {
            var key = menuKey
            closeMenu(true)
            requestRemove(key)
        }
    }
    // Personalizar: el menú se expande hasta el panel existente.
    function openPersonalize() {
        var i = indexOfKey(menuKey)
        if (i < 0) { closeMenu(false); return }
        optionsCard = cardAt(i)
        sheetFrom = Qt.rect(menuBox.x, menuBox.y, menuBox.width, menuBox.height)
        menuOpenAnim.stop()
        menuKey = ""
        menuArmed = false
        menuProgress = 0
        overlayLevel = 1
        ghostFrom = 1.0
        if (reducedMotion) { ghostLift = 0; liftKey = ""; sheetGrow = 1; return }
        ghostDropAnim.restart()
        sheetGrow = 0
        sheetOpenAnim.restart()
    }
    function closeOptions() {
        if (!optionsCard || sheetCloseAnim.running)
            return
        renameInput.focus = false              // confirma el nombre en edición
        Qt.inputMethod.hide()
        sheetFrom = cardRect(optionsCard.key)  // se contrae hacia su tarjeta
        sheetOpenAnim.stop()
        if (reducedMotion) { sheetGrow = 0; overlayLevel = 0; optionsCard = null; return }
        sheetCloseAnim.restart()
    }
    // Quitar: contracción y fundido de la tarjeta; solo cambia el Home.
    function requestRemove(key) {
        for (var i = 0; i < grid.children.length; ++i) {
            var t = grid.children[i]
            if (t.cardKey === key && t.removeCard !== undefined) {
                t.removeCard()
                return
            }
        }
        removeItem(key)
    }
    // Salida única del modo edición (Listo, toque en cualquier parte, dock,
    // Atrás). Idempotente: toques repetidos durante la animación no hacen nada.
    // Con un arrastre activo no sale (al soltar, el arrastre no cuenta como toque).
    property double editExitAt: 0
    property bool editTapGuard: false          // el toque fue sobre un control X
    function exitEditMode() {
        if (!editMode || dragKey.length > 0)
            return
        editExitAt = Date.now()
        closeMenu(true)
        menuArmed = false
        editTapGuard = false
        editMode = false                       // jiggleAmp/X/lift vuelven a 0 con sus Behaviors
        saveItems()
    }
    function exitEdit() { exitEditMode() }
    // Para los controles con acción propia: en modo edición (o justo al salir
    // por este mismo toque) el toque solo termina la edición.
    function consumeEditTap() {
        if (editMode) {
            exitEditMode()
            return true
        }
        return Date.now() - editExitAt < 350
    }
    // Segundo plano o cambio de página: sin tarjetas elevadas ni bloqueadas.
    function resetTransient() {
        closeMenu(true)
        if (dragKey.length > 0) {
            dragKey = ""
            dragDx = 0
            dragDy = 0
            saveItems()
        }
    }
    Connections {
        target: Qt.application
        function onStateChanged() {
            if (Qt.application.state !== Qt.ApplicationActive)
                home.resetTransient()
        }
    }
    Connections {
        target: home
        function onPageChanged() {
            if (home.page !== "home") {
                home.resetTransient()
                home.editMode = false
            }
        }
    }
    ParallelAnimation {
        id: menuOpenAnim
        NumberAnimation { target: home; property: "ghostLift"; from: 0; to: 1; duration: 300; easing.type: Easing.OutBack; easing.overshoot: 1.2 }
        NumberAnimation { target: home; property: "overlayLevel"; to: 1; duration: 260; easing.type: Easing.OutCubic }
        SequentialAnimation {
            PauseAnimation { duration: 40 }
            NumberAnimation { target: home; property: "menuProgress"; from: 0; to: 1; duration: 260; easing.type: Easing.OutCubic }
        }
    }
    SequentialAnimation {
        id: menuCloseAnim
        ParallelAnimation {
            NumberAnimation { target: home; property: "menuProgress"; to: 0; duration: 180; easing.type: Easing.InCubic }
            NumberAnimation { target: home; property: "ghostLift"; to: 0; duration: 220; easing.type: Easing.OutCubic }
            NumberAnimation { target: home; property: "overlayLevel"; to: 0; duration: 220; easing.type: Easing.OutCubic }
        }
        ScriptAction { script: { home.menuKey = ""; home.liftKey = "" } }
    }
    SequentialAnimation {
        id: ghostDropAnim
        NumberAnimation { target: home; property: "ghostLift"; to: 0; duration: 220; easing.type: Easing.OutCubic }
        ScriptAction { script: home.liftKey = "" }
    }
    NumberAnimation {
        id: sheetOpenAnim
        target: home; property: "sheetGrow"; from: 0; to: 1
        duration: 380; easing.type: Easing.OutBack; easing.overshoot: 0.8
    }
    SequentialAnimation {
        id: sheetCloseAnim
        ParallelAnimation {
            NumberAnimation { target: home; property: "sheetGrow"; to: 0; duration: 260; easing.type: Easing.InCubic }
            NumberAnimation { target: home; property: "overlayLevel"; to: 0; duration: 260; easing.type: Easing.OutCubic }
        }
        ScriptAction { script: home.optionsCard = null }
    }
    onUserIdChanged: {
        EarthNative.close()
        earthRequestedTarget = ({})
        earthReturnPage = "home"
        earthDiagnosticsShown = false
        earthCoordinateEntryShown = false
        earthSourceEntryShown = false
        if (page === "earth") page = "home"
        closeMenu(true); editMode = false; optionsCard = null; sheetGrow = 0; overlayLevel = 0
        loadItems(); refreshGreeting(); syncReminders()
    }

    // Disponibilidad real de los destinos (sin abrir otro por aproximación).
    property bool projectsLoaded: false
    Connections {
        target: CalicataCloud
        function onProjectsChanged() { home.projectsLoaded = true }
        function onPendingActivityChanged() { home.syncReminders() }
        function onProjectCalicatasChanged() {
            if (home.pendingCalicataId.length === 0)
                return
            var rows = CalicataCloud.projectCalicatas || []
            for (var i = 0; i < rows.length; ++i) {
                if (String(rows[i].id) === home.pendingCalicataId) {
                    home.selectedCalicata = rows[i]
                    break
                }
            }
            home.pendingCalicataId = ""
        }
    }
    function projectAvailable(projectId) {
        if (!projectsLoaded)
            return true
        var list = CalicataCloud.projects || []
        for (var i = 0; i < list.length; ++i)
            if (String(list[i].id) === String(projectId))
                return true
        return false
    }
    function itemAvailable(it) {
        if (it.kind === "project" || it.kind === "calicatasProject")
            return projectAvailable(it.targetId)
        if (it.kind === "calicata")
            return projectAvailable(it.projectId)
        return true
    }
    function activateItem(it) {
        if (!itemAvailable(it))
            return
        var k = it.kind
        if (k === "calicatas_app" || k === "calicatas") openCalicatas("", "")
        else if (k === "calicatasProject") openCalicatas(it.targetId, "")
        else if (k === "rendiciones_app") notifyComingSoon(k)
        else if (k === "earth_app") openEarth("home")
        else if (k === "drive_app") navigate("drive")
        else if (k === "project" || k === "calicatasProject") openCalicatas(it.targetId, "")
        else if (k === "calicata") openCalicatas(it.projectId, it.targetId)
        else if (k === "settings") navigate("settings")
        else if (k === "profile") navigate("profile")
    }
    // Solo Rendiciones mantiene la entrada en pausa; Earth usa Retroplasma.
    function isComingSoon(kind) { return kind === "rendiciones_app" }
    function isComingSoonPage(target) { return target === "rendiciones" }
    function notify(message) {
        iaStatus = message
        iaStatusTimer.restart()
    }
    function notifyComingSoon(target) {
        notify((target === "earth" || target === "earth_app" ? "InGe Earth" : "Rendiciones")
               + " estará disponible próximamente.")
    }
    function glyphFor(kind) {
        if (kind === "rendiciones_app") return 0xE3D3
        if (kind === "earth_app") return 0xE0E8
        if (kind === "drive_app" || kind === "project") return 0xE0D7
        if (kind === "settings") return 0xE154
        if (kind === "profile") return 0xE19F
        return 0xE0EE
    }
    function subtitleFor(it) {
        if (!itemAvailable(it))
            return "No disponible · mantén pulsado para quitar"
        if (it.kind === "calicatas")
            return projectsLoaded ? (CalicataCloud.projects || []).length + " proyectos · "
                                    + CalicataCloud.pendingActivityCount + " cambios por sincronizar"
                                  : "Cargando datos de tu cuenta…"
        return it.subtitle
    }

    // -------------------------------------------------------------- Saludo
    // Frases de InGe IA (Gemini vía InGeAssistant, contrato de inge-ai-gemini:
    // messages[{role,text}] -> {ok, respuesta}). Un lote de frases por cuenta
    // y por día (caché local); se rotan cada 4 s sin consultar al servidor.
    // Sin IA: saludo local estable y sin atribución.
    property var aiPhrases: []
    property int aiIndex: 0
    property string greetingRequestId: ""
    readonly property bool greetingFromAi: aiPhrases.length > 0
    property string greetingText: localGreeting()
    function todayKey() {
        var d = new Date()
        return d.getFullYear() + "-" + ("0" + (d.getMonth() + 1)).slice(-2) + "-" + ("0" + d.getDate()).slice(-2)
    }
    function localGreeting() {
        return "Welcome back, " + (AccountText.hasVisibleText(firstName) ? firstName : "Engineer")
                + ".\nWhat's new to do today?"
    }
    function cleanPhrases(list) {
        var out = []
        for (var i = 0; i < list.length && out.length < 8; ++i) {
            if (typeof list[i] !== "string")
                continue
            var lines = list[i].replace(/\r/g, "").split("\n").map(function(l) { return l.trim() })
                               .filter(function(l) { return l.length > 0 }).slice(0, 2)
            var text = lines.join("\n")
            if (text.length >= 8 && text.length <= 110 && out.indexOf(text) < 0)
                out.push(text)
        }
        return out
    }
    function refreshGreeting() {
        greetingRequestId = ""
        aiPhrases = []
        aiIndex = 0
        greetingText = localGreeting()
        if (userId.length === 0)
            return
        var cache = readMap(store.greetingsJson)[userId]
        if (cache && cache.date === todayKey() && Array.isArray(cache.phrases)) {
            var cached = cleanPhrases(cache.phrases)
            if (cached.length > 0) {
                aiPhrases = cached
                greetingText = cached[0]
                return
            }
        }
        if (cache && cache.date === todayKey() && cache.failed === true)
            return                                   // un intento por día
        if (typeof InGeAssistant === "undefined" || !InGeAssistant || !InGeAssistant.available)
            return
        var name = AccountText.hasVisibleText(firstName) ? firstName : "Engineer"
        greetingRequestId = "home-greetings-" + Date.now()
        var accepted = InGeAssistant.request({
            operation: "chat",
            id: greetingRequestId,
            messages: [{ role: "user", text:
                "Write 6 different short greetings for an engineer named " + name + " who opens the InGe+ field engineering app. "
                + "English only. Each greeting has exactly two lines separated by a newline: line 1 greets " + name
                + " by name (for example 'Welcome back, " + name + ".' or 'Good afternoon, " + name + ".'); line 2 is an original, "
                + "professional and motivating sentence of at most 45 characters about engineering, field work, projects or productivity. "
                + "No emojis, no quotes inside the lines. Answer ONLY with a JSON array of 6 strings." }]
        })
        if (!accepted)
            greetingRequestId = ""
    }
    // Cuando InGeAssistant pasa a disponible (sesión lista), se pide el lote.
    Connections {
        target: typeof InGeAssistant !== "undefined" ? InGeAssistant : null
        function onAvailableChanged() {
            if (InGeAssistant.available && !home.greetingFromAi && home.greetingRequestId.length === 0)
                home.refreshGreeting()
        }
        function onReplyReady(reply) {
            if (!reply || reply.id !== home.greetingRequestId)
                return
            home.greetingRequestId = ""
            var raw = String(reply.respuesta || "")
            var list = []
            var open = raw.indexOf("["), close = raw.lastIndexOf("]")
            if (!reply.error && open >= 0 && close > open) {
                try { list = JSON.parse(raw.slice(open, close + 1)) } catch (e) { list = [] }
            }
            var phrases = Array.isArray(list) ? home.cleanPhrases(list) : []
            var all = home.readMap(store.greetingsJson)
            all[home.userId] = phrases.length > 0 ? { date: home.todayKey(), phrases: phrases }
                                                  : { date: home.todayKey(), failed: true }
            store.greetingsJson = JSON.stringify(all)
            if (phrases.length === 0)
                return                               // queda el saludo local
            home.aiPhrases = phrases
            home.aiIndex = 0
            home.greetingText = phrases[0]
        }
    }
    // Rotación local: solo con frases reales, en el inicio, en primer plano.
    Timer {
        interval: 4000
        repeat: true
        running: home.greetingFromAi && home.aiPhrases.length > 1 && home.visible
                 && home.page === "home" && !home.addOpen
                 && Qt.application.state === Qt.ApplicationActive
        onTriggered: phraseSwap.restart()
    }
    Component.onCompleted: { loadItems(); refreshGreeting(); CalicataCloud.refreshProjects(); syncReminders() }

    // Foto del día entre las fotografías originales (recorte proporcional).
    readonly property var photos: [
        { source: "qrc:/InGe/Mobile/assets/home/field_03.webp", align: Image.AlignRight },
        { source: "qrc:/InGe/Mobile/assets/home/field_01.webp", align: Image.AlignHCenter },
        { source: "qrc:/InGe/Mobile/assets/home/field_02.webp", align: Image.AlignRight }
    ]
    readonly property var photo: {
        var d = new Date()
        var start = new Date(d.getFullYear(), 0, 1)
        return photos[Math.floor((d - start) / 86400000) % photos.length]
    }

    // Cambio de frase (~420 ms): sale con menos opacidad y un leve ascenso,
    // entra desde un poco más abajo. No mueve tarjetas ni el encabezado.
    SequentialAnimation {
        id: phraseSwap
        ParallelAnimation {
            NumberAnimation { target: greetingLabel; property: "opacity"; to: 0.0; duration: 180; easing.type: Easing.InQuad }
            NumberAnimation { target: greetingShift; property: "y"; to: -8 * home.u; duration: 180; easing.type: Easing.InQuad }
        }
        ScriptAction {
            script: {
                if (home.aiPhrases.length > 1) {
                    home.aiIndex = (home.aiIndex + 1) % home.aiPhrases.length
                    home.greetingText = home.aiPhrases[home.aiIndex]
                }
                greetingShift.y = 10 * home.u
            }
        }
        ParallelAnimation {
            NumberAnimation { target: greetingLabel; property: "opacity"; to: 1.0; duration: 240; easing.type: Easing.OutCubic }
            NumberAnimation { target: greetingShift; property: "y"; to: 0; duration: 240; easing.type: Easing.OutCubic }
        }
    }

    // ============================================================== HOME
    Item {
        id: homeContent
        anchors.fill: parent
        layer.enabled: blur.visible
        visible: !blur.visible

        Image {
            id: photoImage
            anchors.fill: parent
            source: home.photo.source
            fillMode: Image.PreserveAspectCrop
            horizontalAlignment: home.photo.align
            asynchronous: true
            cache: true
            sourceSize.height: Math.min(2400, Math.round(home.height * 1.5))
        }
        // Desenfoque real de la foto, una sola vez en GPU (la foto es estática)
        // y a media resolución; todas las superficies glass lo reutilizan.
        MultiEffect {
            id: photoBlur
            anchors.fill: photoImage
            source: photoImage
            blurEnabled: true
            blurMax: 64
            blur: 1.0
            autoPaddingEnabled: false
        }
        ShaderEffectSource {
            id: glassTextureSource
            sourceItem: photoBlur
            hideSource: true
            visible: false
            smooth: true
            textureSize: Qt.size(Math.max(1, Math.round(photoBlur.width / 2)),
                                 Math.max(1, Math.round(photoBlur.height / 2)))
        }
        Rectangle {   // legibilidad: transparencia del azul oscuro corporativo
            anchors.fill: parent
            gradient: Gradient {
                GradientStop { position: 0.0; color: Qt.rgba(21 / 255, 26 / 255, 48 / 255, 0.10) }
                GradientStop { position: 0.45; color: Qt.rgba(21 / 255, 26 / 255, 48 / 255, 0.18) }
                GradientStop { position: 1.0; color: Qt.rgba(21 / 255, 26 / 255, 48 / 255, 0.62) }
            }
        }

        Flickable {
            id: homeScroll
            onContentYChanged: home.glassTick++
            anchors.fill: parent
            contentWidth: width
            contentHeight: Math.max(height, homeColumn.y + homeColumn.height + home.dockArea)
            boundsBehavior: Flickable.StopAtBounds
            interactive: contentHeight > height && home.dragKey.length === 0 && home.menuKey.length === 0
            opacity: home.page === "home" ? 1 : 0
            visible: opacity > 0
            Behavior on opacity { OpacityAnimator { duration: home.reducedMotion ? 0 : 260 } }

            Column {
                id: homeColumn
                onYChanged: home.glassTick++
                x: home.gutter
                width: home.width - 2 * home.gutter
                y: Math.max(home.topInset + 80 * home.u,
                            home.height - home.dockArea - height)
                spacing: 0

                // Área reservada de dos líneas: el cambio de frase no mueve la cuadrícula.
                Item {
                    id: greetingArea
                    width: parent.width
                    height: Math.ceil(29 * home.u * 1.08 * 2) + 6 * home.u
                    Text {
                        id: greetingLabel
                        width: parent.width
                        anchors.bottom: parent.bottom
                        text: home.greetingText
                        color: "white"
                        font.family: home.fontFamily
                        font.pixelSize: 29 * home.u
                        lineHeight: 1.08
                        wrapMode: Text.WordWrap
                        maximumLineCount: 2
                        elide: Text.ElideRight
                        textFormat: Text.PlainText
                        style: Text.Raised
                        styleColor: Qt.rgba(0, 0, 0, 0.18)
                        transform: Translate { id: greetingShift }
                        Accessible.role: Accessible.Heading
                    }
                }
                Text {
                    topPadding: 4 * home.u
                    opacity: home.greetingFromAi ? 0.9 : 0
                    text: "bienvenida generada por InGe IA"
                    color: "white"
                    font.family: home.fontFamily
                    font.pixelSize: 11 * home.u
                    Accessible.ignored: !home.greetingFromAi
                }
                Item { width: 1; height: 16 * home.u }

                Flow {
                    id: grid
                    onPositioningComplete: home.glassTick++
                    width: parent.width
                    spacing: home.gap

                    move: Transition {
                        NumberAnimation { properties: "x,y"; duration: home.reducedMotion ? 0 : 320; easing.type: Easing.OutCubic }
                    }
                    add: Transition {
                        enabled: home.animateAdds && !home.reducedMotion
                        NumberAnimation { property: "pop"; from: 0.0; to: 1.0; duration: 560; easing.type: Easing.OutBack; easing.overshoot: 2.4 }
                    }

                    Repeater {
                        model: homeModel
                        delegate: Tile {
                            ui: home
                            cardKey: model.key
                            modelIndex: index
                            primary: model.primary
                            size: model.size
                            presentation: model.presentation
                            glyph: home.glyphFor(model.kind)
                            title: model.customTitle.length > 0 ? model.customTitle : model.title
                            subtitle: home.subtitleFor(model)
                            enabledTile: home.itemAvailable(model)
                            comingSoon: home.isComingSoon(model.kind)
                            onActivated: home.activateItem(model)
                        }
                    }

                    Tile { ui: home; size: "compact"; addStyle: true; glyph: 0xE173; title: "Agregar"; subtitle: "Más herramientas"; onActivated: home.openAdd() }
                }
            }
        }

        // Notificaciones (arriba a la derecha)
        GlassCircle {
            ui: home
            x: home.width - width - home.gutter
            y: home.topInset + 12 * home.u
            size: 56 * home.u
            glyph: 0xE059
            accessibleName: "Notificaciones y recordatorios"
            visible: home.page === "home"
            onActivated: home.navigate("settings")
        }

        // ------------------------------------------------- Páginas básicas
        PageFrame {
            ui: home
            shown: home.page === "profile"
            title: "Perfil"
            Column {
                width: parent.width
                spacing: 12 * home.u
                Text {
                    width: parent.width
                    text: home.authReady && auth.logged
                          ? AccountText.displayPersonName(auth.fullName.length > 0 ? auth.fullName
                                : (auth.nombre + " " + auth.apellido), "", true) : ""
                    visible: text.length > 0
                    color: "white"; font.family: home.fontFamily; font.pixelSize: 21 * home.u
                    wrapMode: Text.WordWrap
                }
                Text {
                    width: parent.width
                    text: home.authReady && auth.logged ? AccountText.displayEmailExact(auth.email, "") : ""
                    color: Qt.rgba(1, 1, 1, 0.78); font.family: home.fontFamily; font.pixelSize: 16 * home.u
                    wrapMode: Text.WrapAnywhere
                }
                Item { width: 1; height: 8 * home.u }
                ActionButton { ui: home; width: parent.width; label: "Cerrar sesión"; onActivated: home.signOutRequested() }
            }
        }
        PageFrame {
            ui: home
            shown: home.page === "settings"
            title: "Ajustes"
            Column {
                width: parent.width
                spacing: 12 * home.u
                GlassRow {
                    ui: home
                    width: parent.width
                    title: "Recordatorios"
                    subtitle: store.remindersEnabled ? "Activados" : "Desactivados"
                    trailing: store.remindersEnabled ? "ON" : "OFF"
                    onActivated: store.remindersEnabled = !store.remindersEnabled
                }
                Text {
                    width: parent.width
                    text: "Un aviso al día como máximo (nunca entre 21:00 y 8:00), solo cuando tus calicatas tienen cambios pendientes de sincronizar. Android puede pedir permiso para mostrar notificaciones."
                    color: Qt.rgba(1, 1, 1, 0.72); font.family: home.fontFamily; font.pixelSize: 14 * home.u
                    wrapMode: Text.WordWrap
                }
            }
        }
        PageFrame {
            ui: home
            shown: home.page === "earth"
            title: "InGe Earth"
            Loader {
                width: parent.width
                active: home.page === "earth" && home.visible
                sourceComponent: Component {
                    RetroplasmaEarthView {
                        controller: EarthNative
                        u: home.u
                        fontFamily: home.fontFamily
                        viewportHeight: Math.max(240 * home.u, home.height * 0.50)
                        diagnosticsShown: home.earthDiagnosticsShown
                        coordinatesShown: home.earthCoordinatesShown
                        coordinateEntryShown: home.earthCoordinateEntryShown
                        sourceEntryShown: home.earthSourceEntryShown
                        onCoordinateEntryFinished: home.earthCoordinateEntryShown = false
                    }
                }
            }
        }
        PageFrame {
            ui: home
            shown: home.page === "rendiciones" || home.page === "drive"
            title: home.page === "drive" ? "InGe Drive" : "Rendiciones"
            Text {
                width: parent.width
                text: "Los servicios de este módulo siguen activos; su interfaz está pendiente de integración."
                color: Qt.rgba(1, 1, 1, 0.8); font.family: home.fontFamily; font.pixelSize: 16 * home.u
                wrapMode: Text.WordWrap
            }
        }
        PageFrame {
            ui: home
            shown: false   // sustituida por el editor original restaurado (calicatasEditor)
            title: home.selectedCalicata ? "Calicata"
                 : (home.calicataProjectId.length > 0 ? "Calicatas del proyecto" : "Calicatas")
            Column {
                width: parent.width
                spacing: 10 * home.u
                Text {
                    width: parent.width
                    visible: CalicataCloud.busy
                    text: "Cargando datos de tu cuenta…"
                    color: Qt.rgba(1, 1, 1, 0.75); font.family: home.fontFamily; font.pixelSize: 15 * home.u
                }
                Text {
                    width: parent.width
                    visible: !CalicataCloud.busy && CalicataCloud.lastError.length > 0
                    text: CalicataCloud.lastError
                    color: Qt.rgba(1, 1, 1, 0.75); font.family: home.fontFamily; font.pixelSize: 15 * home.u
                    wrapMode: Text.WordWrap
                }
                // Proyectos autorizados
                Repeater {
                    model: home.page === "calicatas" && home.calicataProjectId.length === 0 && !home.selectedCalicata
                           ? (CalicataCloud.projects || []) : []
                    delegate: GlassRow {
                        required property var modelData
                        ui: home
                        width: parent.width
                        title: String(modelData.name || modelData.code || "")
                        subtitle: String(modelData.code || "")
                        trailing: String.fromCharCode(0xE06F)
                        trailingIsGlyph: true
                        onActivated: home.openCalicatas(String(modelData.id), "")
                    }
                }
                // Calicatas del proyecto
                Repeater {
                    model: home.page === "calicatas" && home.calicataProjectId.length > 0 && !home.selectedCalicata
                           ? (CalicataCloud.projectCalicatas || []) : []
                    delegate: GlassRow {
                        required property var modelData
                        ui: home
                        width: parent.width
                        title: String(modelData.code || modelData.calicata_code || modelData.name || modelData.id || "")
                        subtitle: String(modelData.status || "")
                        trailing: String.fromCharCode(0xE06F)
                        trailingIsGlyph: true
                        onActivated: home.selectedCalicata = modelData
                    }
                }
                // Detalle real de la calicata seleccionada (solo lectura)
                Repeater {
                    model: home.selectedCalicata ? Object.keys(home.selectedCalicata).filter(function(k) {
                        var v = home.selectedCalicata[k]
                        return v !== null && v !== undefined && typeof v !== "object" && String(v).length > 0
                    }) : []
                    delegate: Text {
                        required property var modelData
                        width: parent.width
                        text: modelData + ": " + String(home.selectedCalicata[modelData])
                        color: "white"; font.family: home.fontFamily; font.pixelSize: 15 * home.u
                        wrapMode: Text.WrapAnywhere
                    }
                }
                ActionButton {
                    ui: home
                    visible: home.selectedCalicata !== null
                    width: parent.width
                    label: "Abrir en el editor · pendiente de integración"
                    enabledButton: false
                }
            }
        }
    }

    // ================================ Calicatas: editor original restaurado
    // CalicatasEditorPage (respaldo previo a Visual Zero) con sus servicios
    // reales: CalicataCloud, ExcelExporter, FS, Perms, auth e InGeCoreFlow.
    // Se conserva cargado tras la primera apertura (como AppShell): volver al
    // inicio no reinicia formularios ni pierde borradores.
    property bool calicatasEditorEverLoaded: false
    Loader {
        id: calicatasEditor
        z: 60
        anchors.fill: parent
        active: home.page === "calicatas" || home.calicatasEditorEverLoaded
        visible: home.subAppProgress > 0.001 && status === Loader.Ready
        enabled: home.page === "calicatas" && home.subAppProgress >= 0.999
        focus: home.page === "calicatas"
        opacity: home.subAppProgress
        transform: Translate { x: (1 - home.subAppProgress) * 48 * home.u }
        onActiveChanged: if (active && status === Loader.Null) load()
        Component.onCompleted: if (active && status === Loader.Null) load()
        function load() {
            setSource(Qt.resolvedUrl("pages/CalicatasEditorPage.qml"), {
                auth: (typeof auth !== "undefined" ? auth : null),
                flowMotionEnabled: !home.reducedMotion,
                flowReduceMotion: home.reducedMotion,
                gpsEnabled: false
            })
        }
        onStatusChanged: {
            if (status === Loader.Ready) {
                home.calicatasEditorEverLoaded = true
                item.forceActiveFocus()
            } else if (status === Loader.Error) {
                console.error("INGE_CALICATAS_EDITOR_LOAD_ERROR pages/CalicatasEditorPage.qml")
                home.page = "home"
                home.notify("No se pudo abrir el editor de Calicatas. Revisa el registro de la aplicación.")
            }
        }
        onVisibleChanged: if (visible && item) item.forceActiveFocus()
    }
    Connections {
        target: calicatasEditor.item
        ignoreUnknownSignals: true
        function onRequestBack() { home.page = "home" }
        function onRequestGpsAutoShare(on) {
            if (typeof Perms === "undefined" || !Perms)
                return
            if (on)
                Perms.startNativeLocationUpdates()
            else
                Perms.stopNativeLocationUpdates()
            calicatasEditor.item.gpsEnabled = on && Perms.hasLocationPermission()
        }
        function onRequestOpenEarth(latitude, longitude, altitude, label) {
            home.openEarthAt(latitude, longitude, label, "calicatas", altitude)
        }
        function onRequestOpenMap() { home.openEarth("calicatas") }
    }

    // ================================ Transición de subaplicaciones
    // Común a todas las subaplicaciones (hoy Calicatas): entra por encima del
    // Home con desplazamiento corto y opacidad; al volver, sale y el Home se
    // recupera. El editor no se destruye: su estado y borradores se conservan.
    property real subAppProgress: 0
    property string previousPage: "home"
    readonly property var subAppPages: ["calicatas"]
    function runSubAppTransition(entering, from, to) {
        console.info("INGE_NAV_TRANSITION_START from=" + from + " to=" + to)
        subAppEnter.stop()
        subAppExit.stop()
        if (reducedMotion) {
            subAppProgress = entering ? 1 : 0
            finishSubAppTransition(entering)
        } else if (entering) {
            subAppEnter.restart()
        } else {
            subAppExit.restart()
        }
    }
    function finishSubAppTransition(entering) {
        console.info("INGE_NAV_TRANSITION_END page=" + page)
        if (entering && calicatasEditor.item)
            calicatasEditor.item.forceActiveFocus()   // ya habilitado al terminar
        else if (!entering)
            home.forceActiveFocus()             // Back vuelve a pasar por el Home
    }
    NumberAnimation {
        id: subAppEnter
        target: home; property: "subAppProgress"; to: 1
        duration: 340; easing.type: Easing.OutCubic
        onFinished: home.finishSubAppTransition(true)
    }
    NumberAnimation {
        id: subAppExit
        target: home; property: "subAppProgress"; to: 0
        duration: 380; easing.type: Easing.InOutCubic
        onFinished: home.finishSubAppTransition(false)
    }
    Connections {
        target: home
        function onPageChanged() {
            var from = home.previousPage
            home.previousPage = home.page
            console.info("INGE_NAV_FROM " + from + " INGE_NAV_TO " + home.page)
            var wasSub = home.subAppPages.indexOf(from) >= 0
            var isSub = home.subAppPages.indexOf(home.page) >= 0
            if (isSub && !wasSub)
                home.runSubAppTransition(true, from, home.page)
            else if (wasSub && !isSub)
                home.runSubAppTransition(false, from, home.page)
            else if (home.page === "home")
                home.forceActiveFocus()
        }
    }

    // InGe Earth: se conserva la navegación desde Home y Calicatas.
    property string earthReturnPage: "home"
    property var earthRequestedTarget: ({})
    property bool earthDiagnosticsShown: false
    property bool earthCoordinatesShown: true
    property bool earthCoordinateEntryShown: false
    property bool earthSourceEntryShown: false
    property bool earthDockReady: false
    property bool earthDockNavigation: false
    readonly property var earthDockPreset: [
        {id: "earth.zoomIn", label: "Acercar", icon: "earth.zoomIn", command: "earth.zoomIn", enabled: earthDockReady, priority: 1},
        {id: "earth.zoomOut", label: "Alejar", icon: "earth.zoomOut", command: "earth.zoomOut", enabled: earthDockReady, priority: 2},
        {id: "earth.rotate", label: "Rotar e inclinar", icon: "earth.rotate", command: "", priority: 3, children: [
            {id: "earth.rotateLeft", label: "Girar a la izquierda", icon: "earth.rotateLeft", command: "earth.rotateLeft", enabled: earthDockReady},
            {id: "earth.rotateRight", label: "Girar a la derecha", icon: "earth.rotate", command: "earth.rotateRight", enabled: earthDockReady},
            {id: "earth.tiltUp", label: "Elevar vista", icon: "earth.rotate", command: "earth.tiltUp", enabled: earthDockReady},
            {id: "earth.tiltDown", label: "Bajar vista", icon: "earth.rotate", command: "earth.tiltDown", enabled: earthDockReady},
            {id: "earth.north", label: "Orientar al norte", icon: "earth.pan", command: "earth.north", enabled: earthDockReady}
        ]},
        {id: "earth.pan", label: "Desplazar", icon: "earth.pan", command: "", priority: 4, children: [
            {id: "earth.panLeft", label: "Izquierda", icon: "earth.pan", command: "earth.panLeft", enabled: earthDockReady},
            {id: "earth.panRight", label: "Derecha", icon: "earth.pan", command: "earth.panRight", enabled: earthDockReady},
            {id: "earth.panUp", label: "Adelante", icon: "earth.pan", command: "earth.forward", enabled: earthDockReady},
            {id: "earth.panDown", label: "Atrás", icon: "earth.pan", command: "earth.backward", enabled: earthDockReady}
        ]},
        {id: "earth.reset", label: "Vista inicial", icon: "earth.rotateLeft", command: "earth.reset", enabled: earthDockReady, priority: 5},
        {id: "earth.goTo", label: "Ir a coordenadas", icon: "earth.pan", command: "earth.goTo", priority: 6},
        {id: "earth.navigation", label: "Modo navegación", icon: "earth.pan", command: "earth.navigation", selected: earthDockNavigation, priority: 7},
        {id: "earth.coordinates", label: "Mostrar coordenadas", icon: "earth.pan", command: "earth.coordinates", priority: 8},
        {id: "earth.diagnostics", label: "Métricas del visor", icon: "earth.diagnostics", command: "earth.diagnostics", priority: 9},
        {id: "earth.source", label: "Escena local", icon: "earth.diagnostics", command: "earth.source", priority: 10}
    ]
    function openEarth(returnPage) {
        earthReturnPage = returnPage || "home"
        earthRequestedTarget = ({})
        navigate("earth")
    }
    function openEarthAt(latitude, longitude, label, returnPage, altitude) {
        openEarth(returnPage)
        if (isFinite(latitude) && isFinite(longitude) && Math.abs(latitude) <= 90 && Math.abs(longitude) <= 180) {
            var height = isFinite(altitude) ? Number(altitude) : 0
            earthRequestedTarget = ({ latitude: Number(latitude), longitude: Number(longitude),
                                      altitude: height, label: String(label || "Calicata") })
            EarthNative.goTo(Number(latitude), Number(longitude), height)
        }
    }
    function publishEarthDock() {
        if (dockCtx) dockCtx.publishContext("earth", "earth/retroplasma", earthDockPreset, "qml")
    }
    function syncEarthSession() {
        if (page === "earth" && visible) {
            EarthNative.open()
            if (earthRequestedTarget.latitude !== undefined)
                EarthNative.goTo(earthRequestedTarget.latitude, earthRequestedTarget.longitude, earthRequestedTarget.altitude)
            earthDockReady = EarthNative.ready
            earthDockNavigation = EarthNative.navigationMode
            publishEarthDock()
        } else {
            EarthNative.close()
            if (dockCtx) dockCtx.clearContext("earth")
        }
    }
    Connections {
        target: EarthNative
        function onChanged() {
            if (home.page !== "earth" || !home.visible) return
            // Telemetry must not regenerate the Dock every 500 ms or close Quick Bubble.
            if (home.earthDockReady !== EarthNative.ready || home.earthDockNavigation !== EarthNative.navigationMode) {
                home.earthDockReady = EarthNative.ready
                home.earthDockNavigation = EarthNative.navigationMode
                home.publishEarthDock()
            }
        }
    }
    Connections {
        target: home
        function onPageChanged() { home.syncEarthSession() }
        function onVisibleChanged() { home.syncEarthSession() }
    }
    Component.onDestruction: EarthNative.close()
    Connections {
        target: home.dockRouter
        ignoreUnknownSignals: true
        function onQmlCommand(ownerId, contextId, commandId, dispatchId) {
            if (ownerId !== "earth") return
            try {
                if (home.page !== "earth" || !home.visible) return
                var name = String(commandId)
                if (name === "earth.diagnostics") home.earthDiagnosticsShown = !home.earthDiagnosticsShown
                else if (name === "earth.coordinates") home.earthCoordinatesShown = !home.earthCoordinatesShown
                else if (name === "earth.goTo") home.earthCoordinateEntryShown = !home.earthCoordinateEntryShown
                else if (name === "earth.source") home.earthSourceEntryShown = !home.earthSourceEntryShown
                else if (!EarthNative.command(name.indexOf("earth.") === 0 ? name.substring(6) : name))
                    home.notify("La escena 3D aún no está disponible para este control.")
            } finally {
                home.dockRouter.complete(dispatchId)
            }
        }
    }

    // ================================ Dock contextual global
    // Contrato recuperado de GlobalContextDock.qml (respaldo
    // physical_cleanup_full_20261009), presentado en el dock aprobado del Home:
    //  - La subapp publica su árbol (ContextPublisher -> DockContextController).
    //  - Toque: ejecuta el comando de la herramienta; si no tiene comando, abre
    //    su rama. Mantener 380 ms (Haptic Touch): subfunciones.
    //  - En el menú, una entrada con hijos desciende; una hoja se despacha con
    //    la generación capturada. Si la generación cambia, el menú se cierra.
    readonly property var dockCtx: typeof dockContextController !== "undefined" ? dockContextController : null
    readonly property var dockRouter: typeof dockCommandRouter !== "undefined" ? dockCommandRouter : null
    readonly property bool dockForeground: page === "calicatas" && subAppProgress >= 0.999
                                           && calicatasEditor.status === Loader.Ready
    readonly property int dockGeneration: dockCtx ? dockCtx.generation : 0
    readonly property var dockActions: {
        if (!dockCtx || dockCtx.ownerId !== dockOwner)
            return []
        return (dockCtx.actions || []).filter(function(a) { return a.visible !== false })
    }
    Binding {
        target: home.dockCtx
        property: "foregroundOwner"
        value: home.dockForeground ? "calicatas" : (home.page === "earth" ? "earth" : "")
        when: home.dockCtx !== null
    }

    // Presets: el diseño no cambia; solo las herramientas.
    readonly property var homeDockPreset: [
        { key: "home", glyph: 0xE0F5, page: "home", name: "Inicio" },
        { key: "profile", glyph: 0xE19F, page: "profile", name: "Perfil" },
        { key: "settings", glyph: 0xE154, page: "settings", name: "Ajustes" }
    ]
    readonly property string dockOwner: page === "earth" ? "earth" : "calicatas"
    readonly property string dockMode: (page === "calicatas" || page === "earth") && dockActions.length > 0
                                       ? "subapp" : "home"
    // Distribución intencional del preset (contrato UX 4.0): los roles de
    // navegación tienen posición fija; no dependen de la prioridad.
    //   [Anterior] [herramienta de la sección] [Siguiente | Exportar | Listo] [Más]
    // La primera herramienta no navegacional es la de la sección; el resto va
    // a "Más". Sin navegación publicada (sin ficha), se muestran tal cual.
    readonly property var dockRoles: {
        var roles = { previous: null, right: null, tools: [] }
        for (var i = 0; i < dockActions.length; ++i) {
            var a = dockActions[i]
            if (a.id === "previous") roles.previous = a
            else if (a.id === "next" || a.id === "export" || a.id === "returnReview") roles.right = a
            else roles.tools.push(a)
        }
        return roles
    }
    readonly property bool dockHasNavigation: dockRoles.previous !== null || dockRoles.right !== null
    readonly property var dockSecondary: dockHasNavigation ? dockRoles.tools.slice(1)
                                       : (dockRoles.tools.length > 4 ? dockRoles.tools.slice(3) : [])
    readonly property var dockMoreNode: ({ id: "__more", label: "Más herramientas", enabled: dockSecondary.length > 0,
                                           visible: true, command: "", children: dockSecondary })
    function dockSlotFor(a) {
        return { key: String(a.id), glyph: dockGlyph(a), name: String(a.label || ""),
                 enabled: a.enabled !== false, selected: a.selected === true, action: a,
                 branch: dockChildren(a).length > 0, rotate: 0 }
    }
    function dockPlaceholder(key, name, glyph) {
        return { key: key, glyph: glyph, name: name, enabled: false, branch: false, rotate: 0,
                 action: { id: key, label: name, enabled: false, command: "", children: [] } }
    }
    readonly property var dockSlots: {
        if (dockMode !== "subapp")
            return homeDockPreset
        if (!dockHasNavigation) {
            // Preset sin navegación (InGe Earth, Calicatas sin ficha): hasta 4
            // herramientas; con más, 3 visibles + "Más" con el resto.
            if (dockActions.length <= 4)
                return dockActions.map(function(a) { return home.dockSlotFor(a) })
            return dockActions.slice(0, 3).map(function(a) { return home.dockSlotFor(a) }).concat([
                { key: "__more", glyph: 0, more: true, name: "Más herramientas",
                  enabled: true, branch: true, rotate: 0, action: dockMoreNode }])
        }
        var tool = dockRoles.tools.length > 0 ? dockSlotFor(dockRoles.tools[0])
                                              : dockPlaceholder("__tool", "Herramientas", 0xE0CC)
        tool.center = true
        return [
            dockRoles.previous ? dockSlotFor(dockRoles.previous)
                               : dockPlaceholder("__previous", "Sección anterior", 0xE06E),
            tool,
            dockRoles.right ? dockSlotFor(dockRoles.right)
                            : dockPlaceholder("__next", "Sección siguiente", 0xE06F),
            { key: "__more", glyph: 0, more: true, name: "Más herramientas",
              enabled: dockSecondary.length > 0, branch: true, rotate: 0, action: dockMoreNode }
        ]
    }
    readonly property real dockCellWidth: dockSlots.length >= 4 ? (232 * u - 3) / 4 : 76 * u
    readonly property real dockIconSize: dockSlots.length >= 4 ? 26 * u : 30 * u
    onDockModeChanged: {
        dockPath = []
        console.info("INGE_DOCK_PRESET " + dockMode)
        if (dockMode === "subapp" && page === "calicatas" && !store.dockHintShown) {
            store.dockHintShown = true
            notify("‹ › cambian de sección. Toca el icono central para ver sus herramientas; mantén pulsado para acceso rápido.")
        }
        if (!reducedMotion)
            dockSwap.restart()
    }

    // Menú jerárquico (Quick Bubble): una sola rama visible, ids estables.
    property var dockPath: []
    property int dockMenuGeneration: -1
    function dockChildren(a) {
        return (a && a.children ? a.children : []).filter(function(c) { return c.visible !== false })
    }
    readonly property var dockMenu: {
        if (dockPath.length === 0)
            return null
        var list = dockActions.concat([dockMoreNode])
        var node = null
        for (var i = 0; i < dockPath.length; ++i) {
            node = null
            for (var k = 0; k < list.length; ++k)
                if (String(list[k].id) === String(dockPath[i])) { node = list[k]; break }
            if (!node)
                return null
            list = dockChildren(node)
        }
        return node
    }
    // Herramienta sin subfunciones mantenida pulsada: su propia acción.
    readonly property bool dockQuickLeaf: dockMenu !== null && dockChildren(dockMenu).length === 0
    readonly property var dockMenuItems: {
        if (!dockMenu)
            return []
        if (dockQuickLeaf)
            return [dockMenu]
        var kids = dockChildren(dockMenu)
        // Una rama con comando propio (p. ej. Ubicación -> mapa) lo conserva
        // como primera entrada: el mismo id publicado, no una acción nueva.
        var own = String(dockMenu.command || "")
        if (dockMenu.id !== "__more" && own.length > 0
                && !kids.some(function(c) { return String(c.command || "") === own }))
            kids = [Object.assign({}, dockMenu, { children: [] })].concat(kids)
        return kids
    }
    onDockMenuChanged: Qt.callLater(dockValidateMenu)
    onDockGenerationChanged: Qt.callLater(dockValidateMenu)
    function dockValidateMenu() {
        if (dockPath.length > 0 && (dockMenuGeneration !== dockGeneration || dockMenu === null)) {
            console.info("INGE_DOCK_MENU closed reason=context-changed")
            dockPath = []
        }
    }
    Connections {
        target: home.dockCtx
        ignoreUnknownSignals: true
        function onContextChanged() {
            console.info("INGE_DOCK_CONTEXT_CHANGED generation=" + home.dockCtx.generation
                         + " context=" + home.dockCtx.contextId + " actions=" + home.dockActions.length)
            if (!home.reducedMotion && dock.visible)
                dockSwap.restart()
        }
    }

    // Hápticos: servicio global FlowHaptics (Core Flow), mismas intenciones
    // que GlobalContextDock: medium = abrir, selection = navegar, light = ejecutar.
    function dockHaptic(intent) {
        if (typeof FlowHaptics !== "undefined" && FlowHaptics)
            FlowHaptics.trigger(intent)
    }
    readonly property var dockIconGlyphs: ({
        "earth.zoomIn": 0xE1B6, "earth.zoomOut": 0xE1B7,
        "earth.pan": 0xE111, "earth.rotate": 0xE149, "earth.rotateLeft": 0xE148,
        "earth.diagnostics": 0xE154,

        "documents.file": 0xE0CC, "documents.folder": 0xE0D7, "documents.open": 0xE247,
        "documents.template": 0xE207, "profile.user": 0xE617, "map.location": 0xE1DB,
        "nav.map": 0xE111, "nav.earth": 0xE1F3, "action.addStratum": 0xE529,
        "action.add": 0xE13D, "action.insert": 0xE592, "action.copy": 0xE09E,
        "action.menu": 0xE37D, "action.edit": 0xE1D0, "action.check": 0xE06C,
        "action.export": 0xE32A, "action.camera": 0xE064, "lab.flask": 0xE0D5,
        "module.stratigraphy": 0xE2A3, "system.forward": 0xE06F, "system.back": 0xE06E,
        "status.sync": 0xE145, "documents.image": 0xE0F6, "calgen.history": 0xE1F5, "calgen.close": 0xE1B2, "calgen.attach": 0xE12D, "archive.item": 0xE041, "action.save": 0xE14D, "action.more": 0xE0B6
    })
    function dockGlyph(action) {
        var id = String(action.id || "")
        if (id === "tabs") return 0xE0D7                 // folder
        if (id === "information") return 0xE0F9          // info
        if (id === "returnReview") return 0xE06C         // check
        var glyph = dockIconGlyphs[String(action.icon || "")]
        if (glyph !== undefined) return glyph
        if (id.indexOf("photo") === 0) return 0xE0F6    // image
        if (id.indexOf("lab") === 0) return 0xE405      // test-tube
        return 0xE0CC                                   // file-text
    }
    function dockDisabledReason(action) {
        var editor = calicatasEditor.item
        var id = String(action.id || "")
        if (id.indexOf("export") === 0 && editor) {
            if (!editor.hasOpenDocument)
                return "Exportar: abre o crea una ficha de calicata primero."
            if (editor.exportBusy)
                return "Exportar: ya hay una exportación en curso."
        }
        if (id === "__previous")
            return dockRoles.right && dockRoles.right.id === "returnReview"
                   ? "Termina la corrección con Listo para volver a Revisión."
                   : "Ya estás en la primera sección."
        if (id === "__next")
            return "No hay una sección siguiente."
        if (id === "__more")
            return "No hay más herramientas en esta sección."
        return String(action.label || "Acción") + ": no disponible en el estado actual de la ficha."
    }
    // Quick Bubble anclado a la herramienta que lo abre (coordenadas de home).
    property real dockMenuAnchorX: width / 2
    property int dockHoverIndex: -1                 // fila bajo el dedo (selección deslizando)
    function dockOpenMenu(id, anchorItem, viaHold) {
        if (!dockRouter || dockRouter.busy || (dockCtx && dockCtx.transitionPending))
            return false
        if (anchorItem)
            dockMenuAnchorX = anchorItem.mapToItem(home, anchorItem.width / 2, 0).x
        dockMenuGeneration = dockGeneration
        dockHoverIndex = -1
        dockPath = [String(id)]
        dockHaptic(viaHold ? "medium" : "light")    // Deep Press reconocido / apertura por toque
        console.info("INGE_DOCK_MENU open action=" + id + " via=" + (viaHold ? "hold" : "tap")
                     + " generation=" + dockGeneration)
        return true
    }
    function dockMenuBack() {
        dockPath = dockPath.length <= 1 ? [] : dockPath.slice(0, -1)
        dockHoverIndex = -1
        dockHaptic("selection")
    }
    function dockDispatch(action, generation) {
        if (!dockRouter || !dockCtx) {
            console.warn("INGE_DOCK_INTEGRATION_ERROR router-unavailable action=" + action.id)
            notify("Error de integración del dock: acción no disponible.")
            dockHaptic("error")
            return
        }
        var accepted = dockRouter.dispatch(String(action.id), generation)
        dockHaptic(accepted ? "success" : "error")
        if (!accepted) {
            console.warn("INGE_DOCK_TAP rejected action=" + action.id + " generation=" + generation)
            notify("La acción no se ejecutó: la sección cambió. Inténtalo de nuevo.")
        }
    }
    function dockUnavailable(action) {
        dockHaptic("warning")
        notify(dockDisabledReason(action))
    }
    // Toque normal: con subfunciones abre el Quick Bubble (descubrible sin
    // Deep Press); sin subfunciones ejecuta el comando.
    function dockSlotTap(slot, pressGeneration, anchorItem) {
        if (!slot.action) {
            if (!consumeEditTap())
                navigate(slot.page)
            return
        }
        var a = slot.action
        if (a.enabled === false) {
            dockUnavailable(a)
            return
        }
        if (dockPath.length > 0 && dockPath[0] === slot.key) {   // segundo toque: cierra
            dockPath = []
            return
        }
        dockPath = []
        if (dockChildren(a).length > 0) {
            if (pressGeneration === dockGeneration)
                dockOpenMenu(slot.key, anchorItem, false)
        } else if (a.command && String(a.command).length > 0) {
            dockDispatch(a, pressGeneration)
        }
    }
    // Deep Press (380 ms): subfunciones, o la propia acción si no tiene. Nunca
    // ejecuta nada por sí solo ni genera además un toque normal.
    function dockSlotHold(slot, pressGeneration, anchorItem) {
        if (!slot.action) {
            dockHaptic("light")
            notify(slot.name)
            return false
        }
        if (slot.action.enabled === false) {
            dockUnavailable(slot.action)
            return false
        }
        if (pressGeneration !== dockGeneration)
            return false
        return dockOpenMenu(slot.key, anchorItem, true)
    }
    // Selección deslizando: el dedo sigue pulsado tras el Deep Press.
    function dockHoverAt(sourceItem, x, y) {
        if (!dockMenuBox.open) {
            dockHoverIndex = -1
            return
        }
        var p = sourceItem.mapToItem(dockMenuColumn, x, y)
        var row = -1
        if (p.x >= 0 && p.x <= dockMenuColumn.width && p.y >= dockMenuHeaderHeight)
            row = Math.floor((p.y - dockMenuHeaderHeight) / dockMenuRowHeight)
        if (row >= dockMenuItems.length)
            row = -1
        if (row !== dockHoverIndex) {
            dockHoverIndex = row
            if (row >= 0)
                dockHaptic("selection")
        }
    }
    function dockReleaseHover() {
        var row = dockHoverIndex
        dockHoverIndex = -1
        if (row >= 0 && row < dockMenuItems.length)
            dockMenuActivate(dockMenuItems[row])
        // Soltar fuera de una opción deja el menú abierto: nunca ejecuta nada.
    }
    function dockMenuActivate(entry) {
        if (!entry || dockMenuGeneration !== dockGeneration) {
            dockPath = []
            return
        }
        if (entry.enabled === false) {
            dockUnavailable(entry)
            return
        }
        if (!dockQuickLeaf && dockChildren(entry).length > 0) {
            dockPath = dockPath.concat([String(entry.id)])
            dockHoverIndex = -1
            dockHaptic("selection")
            return
        }
        var generation = dockMenuGeneration
        dockPath = []
        dockDispatch(entry, generation)
    }
    readonly property real dockMenuHeaderHeight: 44 * u
    readonly property real dockMenuRowHeight: 52 * u

    property real dockSwapFade: 1
    SequentialAnimation {
        id: dockSwap
        NumberAnimation { target: home; property: "dockSwapFade"; to: 0.4; duration: 90; easing.type: Easing.OutQuad }
        NumberAnimation { target: home; property: "dockSwapFade"; to: 1.0; duration: 200; easing.type: Easing.OutCubic }
    }

    // Material del dock sobre una subapp: la MISMA GlassSurface, con el
    // contenido real de detrás (captura a 1/4 + desenfoque) como fondo, como
    // hacía GlobalContextDock con backdropItem. En gama baja (deviceTier LOW /
    // ULTRA_LOW) no se captura: cristal de la foto con tinte azul noche denso.
    readonly property bool dockLowCostGlass: GraphicsCore.deviceTier === "LOW"
                                             || GraphicsCore.deviceTier === "ULTRA_LOW"
    readonly property bool subAppGlassActive: subAppProgress > 0.001
                                              && calicatasEditor.status === Loader.Ready
                                              && !dockLowCostGlass
    readonly property var dockGlassUi: subAppGlassActive ? subAppGlass : home
    readonly property color dockGlassTint: subAppGlassActive ? Qt.rgba(21 / 255, 26 / 255, 48 / 255, 0.56)
                                         : subAppProgress > 0.001 ? Qt.rgba(21 / 255, 26 / 255, 48 / 255, 0.84)
                                         : Qt.rgba(28 / 255, 45 / 255, 80 / 255, 0.38)
    Item {
        id: subAppGlass
        anchors.fill: calicatasEditor
        readonly property Item backdrop: subAppGlass
        readonly property var glassTexture: home.subAppGlassActive ? subAppGlassTexture : null
        readonly property int glassTick: home.glassTick
        ShaderEffectSource {
            id: subAppCapture
            width: parent.width
            height: parent.height
            sourceItem: home.subAppGlassActive ? calicatasEditor : null
            live: true
            hideSource: false
            visible: false
            textureSize: Qt.size(Math.max(1, Math.round(width / 4)), Math.max(1, Math.round(height / 4)))
        }
        MultiEffect {
            id: subAppBlur
            anchors.fill: parent
            source: subAppCapture
            blurEnabled: true
            blurMax: 32
            blur: 1.0
            autoPaddingEnabled: false
        }
        ShaderEffectSource {
            id: subAppGlassTexture
            sourceItem: subAppBlur
            hideSource: true
            visible: false
            smooth: true
            textureSize: Qt.size(Math.max(1, Math.round(subAppBlur.width / 4)),
                                 Math.max(1, Math.round(subAppBlur.height / 4)))
        }
    }

    // Tocar fuera cierra el menú sin ejecutar nada.
    MouseArea {
        z: 61
        anchors.fill: parent
        visible: dockMenuBox.open
        onClicked: home.dockPath = []
    }
    // Quick Bubble: subfunciones de la herramienta, sobre el dock.
    Rectangle {
        id: dockMenuBox
        z: 65
        readonly property bool open: dock.visible && home.dockMode === "subapp" && home.dockMenu !== null
        property real shown: open ? 1 : 0
        Behavior on shown {
            NumberAnimation {
                duration: home.reducedMotion ? 0 : (dockMenuBox.open ? 260 : 160)
                easing.type: dockMenuBox.open ? Easing.OutBack : Easing.InCubic
                easing.overshoot: 1.15                // asentamiento elástico moderado
            }
        }
        visible: shown > 0.01
        opacity: Math.min(1, shown)
        transform: Scale {
            origin.x: Math.max(0, Math.min(dockMenuBox.width, home.dockMenuAnchorX - dockMenuBox.x))
            origin.y: dockMenuBox.height + 10 * home.u
            xScale: 0.82 + 0.18 * dockMenuBox.shown
            yScale: 0.82 + 0.18 * dockMenuBox.shown
        }
        onShownChanged: home.glassTick++
        width: Math.min(312 * home.u, home.width - 2 * home.gutter)
        height: Math.max(0, Math.min(dockMenuColumn.implicitHeight + 12 * home.u,
                                     dock.y - home.topInset - 20 * home.u))
        x: Math.max(home.gutter, Math.min(home.width - home.gutter - width, home.dockMenuAnchorX - width / 2))
        y: dock.y - height - 10 * home.u
        radius: 20 * home.u
        color: "transparent"
        onXChanged: home.glassTick++
        onYChanged: home.glassTick++
        GlassSurface {
            ui: home.dockGlassUi
            radius: dockMenuBox.radius
            margin: 10 * home.u
            tint: home.dockGlassTint
        }
        MouseArea { anchors.fill: parent }
        Flickable {
            anchors.fill: parent
            clip: true
            contentWidth: width
            contentHeight: dockMenuColumn.implicitHeight + 12 * home.u
            interactive: contentHeight > height
            boundsBehavior: Flickable.StopAtBounds
            Column {
                id: dockMenuColumn
                y: 6 * home.u
                width: dockMenuBox.width
                Item {   // encabezado: herramienta abierta; en submenús, volver
                    width: parent.width
                    height: home.dockMenuHeaderHeight
                    Text {
                        x: 16 * home.u
                        width: parent.width - 32 * home.u
                        anchors.verticalCenter: parent.verticalCenter
                        text: (home.dockPath.length > 1 ? "‹  " : "") + (home.dockMenu ? String(home.dockMenu.label || "") : "")
                        elide: Text.ElideRight
                        color: Qt.rgba(1, 1, 1, 0.78)
                        font.family: home.fontFamily
                        font.weight: Font.DemiBold
                        font.pixelSize: 13 * home.u
                    }
                    MouseArea {
                        anchors.fill: parent
                        enabled: home.dockPath.length > 1
                        onClicked: home.dockMenuBack()
                    }
                    Accessible.role: Accessible.Button
                    Accessible.name: home.dockPath.length > 1 ? "Volver" : (home.dockMenu ? String(home.dockMenu.label || "") : "")
                }
                Repeater {
                    model: home.dockMenuItems
                    delegate: Item {
                        required property var modelData
                        required property int index
                        readonly property bool hasChildren: !home.dockQuickLeaf && home.dockChildren(modelData).length > 0
                        width: dockMenuColumn.width
                        height: home.dockMenuRowHeight
                        opacity: modelData.enabled === false ? 0.4 : 1
                        Rectangle {
                            x: 14 * home.u
                            width: parent.width - 28 * home.u
                            height: 1
                            color: Qt.rgba(1, 1, 1, 0.14)
                        }
                        Rectangle {
                            anchors.fill: parent
                            anchors.margins: 4 * home.u
                            radius: 12 * home.u
                            color: Qt.rgba(1, 1, 1, menuRowTap.pressed || home.dockHoverIndex === index ? 0.16 : 0)
                            Behavior on color { ColorAnimation { duration: 90 } }
                        }
                        Text {   // icono de la acción
                            x: 18 * home.u
                            anchors.verticalCenter: parent.verticalCenter
                            text: String.fromCharCode(home.dockGlyph(modelData))
                            color: "white"
                            font.family: home.iconFamily
                            font.pixelSize: 20 * home.u
                        }
                        Text {
                            x: 52 * home.u
                            width: parent.width - 96 * home.u
                            anchors.verticalCenter: parent.verticalCenter
                            text: (modelData.selected === true ? "● " : "") + String(modelData.label || "")
                            elide: Text.ElideRight
                            color: "white"
                            font.family: home.fontFamily
                            font.pixelSize: 16 * home.u
                        }
                        Text {   // con subfunciones: desciende
                            visible: hasChildren
                            anchors.right: parent.right
                            anchors.rightMargin: 18 * home.u
                            anchors.verticalCenter: parent.verticalCenter
                            text: String.fromCharCode(0xE06F)
                            color: Qt.rgba(1, 1, 1, 0.8)
                            font.family: home.iconFamily
                            font.pixelSize: 18 * home.u
                        }
                        MouseArea { id: menuRowTap; anchors.fill: parent; onClicked: home.dockMenuActivate(modelData) }
                        Accessible.role: Accessible.MenuItem
                        Accessible.name: String(modelData.label || "")
                                         + (modelData.enabled === false ? ". No disponible" : "")
                    }
                }
            }
        }
    }

    // ================================ Personalización de una tarjeta
    Rectangle {   // entorno atenuado (la fotografía no se modifica)
        z: 40
        anchors.fill: parent
        color: home.navy
        opacity: 0.42 * home.overlayLevel
        visible: opacity > 0.001
        MouseArea {
            anchors.fill: parent
            enabled: home.menuKey.length > 0 || home.optionsCard !== null
            onClicked: home.optionsCard !== null ? home.closeOptions() : home.closeMenu(false)
        }
    }

    // Copia elevada de la tarjeta pulsada, por delante del entorno.
    Tile {
        id: liftGhost
        ui: home
        z: 42
        visible: home.liftKey.length > 0 && home.liftCard !== null
        x: home.menuRect.x
        y: home.menuRect.y
        size: home.liftCard ? home.liftCard.size : "normal"
        presentation: home.liftCard ? home.liftCard.presentation : "full"
        primary: home.liftCard ? home.liftCard.primary : false
        glyph: home.liftCard ? home.glyphFor(home.liftCard.kind) : 0
        title: home.liftCard ? (home.liftCard.customTitle.length > 0 ? home.liftCard.customTitle : home.liftCard.title) : ""
        subtitle: home.liftCard ? home.subtitleFor(home.liftCard) : ""
        enabledTile: home.liftCard ? home.itemAvailable(home.liftCard) : true
        comingSoon: home.liftCard ? home.isComingSoon(home.liftCard.kind) : false
        scale: home.ghostFrom + (1.03 - home.ghostFrom) * home.ghostLift
        MouseArea {
            anchors.fill: parent
            enabled: home.menuKey.length > 0
            onClicked: {
                var it = home.liftCard
                home.closeMenu(true)
                if (it && home.itemAvailable(it))
                    home.activateItem(it)
            }
        }
    }

    // Menú contextual compacto: debajo o encima de la tarjeta, siempre visible
    // entera (barra de estado, dock y márgenes laterales).
    Rectangle {
        id: menuBox
        z: 44
        readonly property real rowH: 50 * home.u
        readonly property bool alignRight: home.menuRect.x + home.menuRect.width / 2 > home.width / 2
        readonly property real minY: home.topInset + 8 * home.u
        readonly property real maxY: home.height - home.dockArea - height
        readonly property real belowY: home.menuRect.y + home.menuRect.height * 1.03 + 10 * home.u
        readonly property real aboveY: home.menuRect.y - height - 10 * home.u
        readonly property bool above: belowY > maxY && aboveY >= minY
        width: Math.min(236 * home.u, home.width - 2 * home.gutter)
        height: 3 * rowH + 12 * home.u
        x: Math.max(home.gutter, Math.min(home.width - home.gutter - width,
                    alignRight ? home.menuRect.x + home.menuRect.width - width : home.menuRect.x))
        y: Math.max(minY, Math.min(maxY, above ? aboveY : belowY))
        radius: 20 * home.u
        color: "transparent"
        visible: home.menuKey.length > 0 && home.menuProgress > 0.001
        opacity: home.menuProgress
        scale: 0.86 + 0.14 * home.menuProgress
        transformOrigin: above ? (alignRight ? Item.BottomRight : Item.BottomLeft)
                               : (alignRight ? Item.TopRight : Item.TopLeft)
        onXChanged: home.glassTick++
        onYChanged: home.glassTick++
        onScaleChanged: home.glassTick++
        GlassSurface {
            ui: home
            radius: menuBox.radius
            margin: 10 * home.u
            tint: Qt.rgba(28 / 255, 45 / 255, 80 / 255, 0.62)
        }
        Column {
            y: 6 * home.u
            width: parent.width
            Repeater {
                model: [ { g: 0xE154, l: "Personalizar", a: "custom" },
                         { g: 0xE0F5, l: "Editar inicio", a: "edit" },
                         { g: 0xE1B2, l: "Quitar del inicio", a: "remove" } ]
                delegate: Item {
                    required property var modelData
                    required property int index
                    width: menuBox.width
                    height: menuBox.rowH
                    Rectangle {
                        visible: index > 0
                        x: 14 * home.u
                        width: parent.width - 28 * home.u
                        height: 1
                        color: Qt.rgba(1, 1, 1, 0.14)
                    }
                    Rectangle {
                        anchors.fill: parent
                        anchors.margins: 4 * home.u
                        radius: 12 * home.u
                        color: Qt.rgba(1, 1, 1, rowTap.pressed ? 0.12 : 0)
                    }
                    Text {
                        x: 18 * home.u
                        anchors.verticalCenter: parent.verticalCenter
                        text: modelData.l
                        color: "white"
                        font.family: home.fontFamily
                        font.pixelSize: 17 * home.u
                    }
                    Text {
                        anchors.right: parent.right
                        anchors.rightMargin: 18 * home.u
                        anchors.verticalCenter: parent.verticalCenter
                        text: String.fromCharCode(modelData.g)
                        color: "white"
                        font.family: home.iconFamily
                        font.pixelSize: 21 * home.u
                    }
                    MouseArea { id: rowTap; anchors.fill: parent; onClicked: home.menuAction(modelData.a) }
                    Accessible.role: Accessible.MenuItem
                    Accessible.name: modelData.l
                }
            }
        }
    }

    // Panel Personalizar: crece desde el menú y se contrae hacia su tarjeta.
    Rectangle {
        id: optionsSheet
        z: 43
        readonly property real kbTop: Qt.inputMethod.visible && Qt.inputMethod.keyboardRectangle.height > 0
                                      ? Math.min(home.height, Qt.inputMethod.keyboardRectangle.y) : home.height
        readonly property real finalW: home.width - 20 * home.u
        readonly property real finalH: Math.min(optionsColumn.implicitHeight + 36 * home.u,
                                                kbTop - home.topInset - 22 * home.u)
        readonly property real finalX: 10 * home.u
        readonly property real finalY: kbTop - finalH - 14 * home.u
        visible: home.optionsCard !== null && home.sheetGrow > 0.001 && home.page === "home"
        x: home.lerpValue(home.sheetFrom.x, finalX, home.sheetGrow)
        y: home.lerpValue(home.sheetFrom.y, finalY, home.sheetGrow)
        width: Math.max(0, home.lerpValue(home.sheetFrom.width, finalW, home.sheetGrow))
        height: Math.max(0, home.lerpValue(home.sheetFrom.height, finalH, home.sheetGrow))
        radius: 26 * home.u
        color: "transparent"
        onXChanged: home.glassTick++
        onYChanged: home.glassTick++
        MouseArea { anchors.fill: parent }          // no cierra al tocar dentro
        GlassSurface {
            ui: home
            radius: 26 * home.u
            margin: 12 * home.u
            tint: Qt.rgba(28 / 255, 45 / 255, 80 / 255, 0.62)
        }
        Flickable {
            anchors.fill: parent
            clip: true
            contentWidth: width
            contentHeight: optionsColumn.implicitHeight + 36 * home.u
            interactive: contentHeight > height + 1 && home.sheetGrow >= 0.999
            boundsBehavior: Flickable.StopAtBounds
            opacity: Math.max(0, Math.min(1, (home.sheetGrow - 0.35) / 0.65))
            Column {
                id: optionsColumn
                x: 18 * home.u
                y: 18 * home.u + (1 - Math.min(1, home.sheetGrow)) * 14 * home.u
                width: optionsSheet.finalW - 36 * home.u
                spacing: 10 * home.u
                Text {
                    width: parent.width
                    text: home.optionsCard ? (home.optionsCard.customTitle || home.optionsCard.title) : ""
                    color: "white"; font.family: home.fontFamily; font.weight: Font.DemiBold
                    font.pixelSize: 20 * home.u; elide: Text.ElideRight
                }
                Text { text: "PRESENTACIÓN"; color: Qt.rgba(1, 1, 1, 0.7); font.family: home.fontFamily; font.pixelSize: 12 * home.u }
                Flow {
                    width: parent.width
                    spacing: 8 * home.u
                    Repeater {
                        model: [ { v: "icon", l: "Solo icono" }, { v: "name", l: "Solo nombre" },
                                 { v: "iconName", l: "Icono y nombre" }, { v: "full", l: "Con descripción" } ]
                        delegate: Chip {
                            required property var modelData
                            ui: home
                            label: modelData.l
                            selected: home.optionsCard !== null && home.optionsCard.presentation === modelData.v
                            onPicked: home.updateCard(home.optionsCard.key, "presentation", modelData.v)
                        }
                    }
                }
                Text { text: "NOMBRE VISIBLE"; color: Qt.rgba(1, 1, 1, 0.7); font.family: home.fontFamily; font.pixelSize: 12 * home.u }
                Row {
                    width: parent.width
                    spacing: 8 * home.u
                    Rectangle {
                        width: parent.width - resetChip.width - 8 * home.u
                        height: 40 * home.u
                        radius: 12 * home.u
                        color: "transparent"
                        border.width: 1; border.color: Qt.rgba(1, 1, 1, 0.4)
                        TextInput {
                            id: renameInput
                            anchors.fill: parent
                            anchors.leftMargin: 12 * home.u
                            anchors.rightMargin: 12 * home.u
                            verticalAlignment: TextInput.AlignVCenter
                            text: home.optionsCard ? (home.optionsCard.customTitle || home.optionsCard.title) : ""
                            color: "white"; font.family: home.fontFamily; font.pixelSize: 16 * home.u
                            maximumLength: 32
                            clip: true
                            onEditingFinished: {
                                if (!home.optionsCard)
                                    return
                                var value = text.trim()
                                home.updateCard(home.optionsCard.key, "customTitle",
                                                value === home.optionsCard.title ? "" : value)
                            }
                        }
                    }
                    Chip {
                        id: resetChip
                        ui: home
                        label: "Restablecer"
                        onPicked: if (home.optionsCard) home.updateCard(home.optionsCard.key, "customTitle", "")
                    }
                }
                Text { text: "TAMAÑO"; color: Qt.rgba(1, 1, 1, 0.7); font.family: home.fontFamily; font.pixelSize: 12 * home.u }
                Row {
                    spacing: 8 * home.u
                    Repeater {
                        model: [ { v: "compact", l: "Compacto" }, { v: "normal", l: "Normal" }, { v: "wide", l: "Ancho" } ]
                        delegate: Chip {
                            required property var modelData
                            ui: home
                            label: modelData.l
                            selected: home.optionsCard !== null && home.optionsCard.size === modelData.v
                            onPicked: home.updateCard(home.optionsCard.key, "size", modelData.v)
                        }
                    }
                }
                Item { width: 1; height: 4 * home.u }
                Row {
                    spacing: 8 * home.u
                    Chip {
                        ui: home
                        label: "Quitar del inicio"
                        onPicked: { var key = home.optionsCard.key; home.closeOptions(); home.requestRemove(key) }
                    }
                    Chip { ui: home; label: "Listo"; selected: true; onPicked: home.closeOptions() }
                }
            }
        }
    }

    // Jiggle Mode: un toque breve en cualquier parte termina la edición.
    Item {
        id: editExitCatcher
        z: 29                                   // bajo "Listo" (30) y bajo menús (40+)
        anchors.fill: parent
        visible: home.editMode
        TapHandler {
            gesturePolicy: TapHandler.DragThreshold   // agarre pasivo
            longPressThreshold: 0.35                  // mantener/arrastrar no es toque
            onPressedChanged: if (pressed) home.editTapGuard = false
            onTapped: {
                if (home.editTapGuard) {                  // fue la X de una tarjeta
                    home.editTapGuard = false
                    return
                }
                home.exitEditMode()
            }
        }
    }

    // Jiggle Mode: acción discreta para terminar la edición.
    Rectangle {
        id: editDone
        z: 30
        opacity: home.editMode && home.page === "home" && home.optionsCard === null ? 1 : 0
        visible: opacity > 0.01
        Behavior on opacity { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
        width: editDoneText.implicitWidth + 40 * home.u
        height: 44 * home.u
        radius: height / 2
        x: (home.width - width) / 2
        y: home.topInset + 14 * home.u
        color: "transparent"
        GlassSurface { ui: home; radius: editDone.radius; margin: 8 * home.u }
        Text {
            id: editDoneText
            anchors.centerIn: parent
            text: "Listo"
            color: "white"
            font.family: home.fontFamily
            font.weight: Font.DemiBold
            font.pixelSize: 16 * home.u
        }
        MouseArea { anchors.fill: parent; anchors.margins: -6 * home.u; enabled: home.editMode; onClicked: home.exitEditMode() }
        Accessible.role: Accessible.Button
        Accessible.name: "Terminar la edición del inicio"
    }

    // ===================================== Panel Agregar (Preview 2)
    MultiEffect {
        id: blur
        anchors.fill: homeContent
        source: homeContent
        blurEnabled: true
        blurMax: 48
        blur: Math.max(home.blurAmount, 0.3 * home.overlayLevel)
        visible: home.blurAmount > 0.001 || home.overlayLevel > 0.001
    }
    property real blurAmount: 0
    property real glowAmount: 0
    property real panelProgress: 0

    function openAdd() {
        if (addOpen)
            return
        addOpen = true
        CalicataCloud.refreshProjects()
        if (reducedMotion) { blurAmount = 1; panelProgress = 1; return }
        addOpenFlow.restart()
    }
    function closeAdd() {
        if (!addOpen)
            return
        addPanel.picking = ""
        if (reducedMotion) { blurAmount = 0; panelProgress = 0; addOpen = false; flushPendingCard(); return }
        addCloseFlow.restart()
    }

    ParallelAnimation {
        id: addOpenFlow
        SequentialAnimation {
            NumberAnimation { target: home; property: "glowAmount"; to: 1; duration: 220; easing.type: Easing.OutQuad }
            NumberAnimation { target: home; property: "glowAmount"; to: 0; duration: 280; easing.type: Easing.InOutSine }
        }
        NumberAnimation { target: home; property: "blurAmount"; to: 1; duration: 420; easing.type: Easing.InOutSine }
        SequentialAnimation {
            PauseAnimation { duration: 90 }
            NumberAnimation { target: home; property: "panelProgress"; to: 1; duration: 400; easing.type: Easing.OutCubic }
        }
    }
    SequentialAnimation {
        id: addCloseFlow
        ParallelAnimation {
            NumberAnimation { target: home; property: "panelProgress"; to: 0; duration: 260; easing.type: Easing.InCubic }
            NumberAnimation { target: home; property: "blurAmount"; to: 0; duration: 320; easing.type: Easing.InOutSine }
        }
        ScriptAction { script: { home.addOpen = false; home.flushPendingCard() } }
    }

    // Brillo verde/azul desde el centro inferior (saturación moderada).
    Shape {
        anchors.fill: parent
        visible: home.glowAmount > 0.001
        opacity: 0.75 * home.glowAmount
        preferredRendererType: Shape.GeometryRenderer
        ShapePath {
            strokeWidth: -1
            fillGradient: RadialGradient {
                centerX: home.width / 2; centerY: home.height
                focalX: centerX; focalY: centerY
                centerRadius: home.height * (0.25 + 0.55 * home.glowAmount)
                GradientStop { position: 0.0; color: Qt.rgba(72 / 255, 100 / 255, 38 / 255, 0.95) }
                GradientStop { position: 0.45; color: Qt.rgba(6 / 255, 84 / 255, 162 / 255, 0.55) }
                GradientStop { position: 1.0; color: Qt.rgba(6 / 255, 84 / 255, 162 / 255, 0.0) }
            }
            startX: 0; startY: 0
            PathLine { x: home.width; y: 0 }
            PathLine { x: home.width; y: home.height }
            PathLine { x: 0; y: home.height }
            PathLine { x: 0; y: 0 }
        }
    }

    Rectangle {
        id: addSheet
        visible: home.addOpen
        x: 10 * home.u
        width: home.width - 20 * home.u
        y: home.topInset + 8 * home.u + (1 - home.panelProgress) * 60 * home.u
        height: home.height - y - home.dockArea + 6 * home.u
        radius: 30 * home.u
        opacity: home.panelProgress
        scale: 0.92 + 0.08 * home.panelProgress
        transformOrigin: Item.Bottom
        color: "transparent"
        onYChanged: home.glassTick++
        onScaleChanged: home.glassTick++
        GlassSurface {
            ui: home
            radius: 30 * home.u
            margin: 14 * home.u
            tint: Qt.rgba(28 / 255, 45 / 255, 80 / 255, 0.46)
        }
        AddToolPanel {
            id: addPanel
            glass: home
            anchors.fill: parent
            u: home.u
            fontFamily: home.fontFamily
            iconFamily: home.iconFamily
            existingKeys: home.itemKeys()
            removedApps: home.removedApps
            onAddRequested: function(item) { home.addItem(item) }
            onCloseRequested: home.closeAdd()
        }
    }

    // ========================================================== DOCK
    readonly property real gutter: 18 * u
    readonly property real gap: 12 * u
    readonly property real topInset: 36 * u          // barra de estado (edge-to-edge)
    readonly property real dockHeight: 58 * u
    readonly property real dockBottom: 22 * u        // flota sobre el borde inferior
    readonly property real dockArea: dockHeight + dockBottom + 22 * u

    // ============================ Dock global (único componente visual)
    // Diseño aprobado del Home V2 (cápsula de 232 dp, celdas, separadores,
    // glifos Lucide, GlassSurface). Cada subapp aporta solo su preset.
    // Solo iconos: los nombres viven en el menú y en la accesibilidad.
    Rectangle {
        id: dock
        z: home.subAppProgress > 0.001 ? 64 : 0     // también sobre la subapp
        readonly property bool hiddenForInput: home.dockMode === "subapp"
            && (Qt.inputMethod.visible
                || (calicatasEditor.item !== null && calicatasEditor.item.dockSuppressed === true))
        property real shown: hiddenForInput ? 0 : 1
        Behavior on shown { NumberAnimation { duration: home.reducedMotion ? 0 : 280; easing.type: Easing.OutCubic } }
        visible: shown > 0.01
        opacity: shown
        width: 232 * home.u
        height: home.dockHeight
        x: iaButton.x - 24 * home.u - width
        y: home.height - home.dockBottom - height + (1 - shown) * 28 * home.u
        radius: height / 2
        color: "transparent"
        onYChanged: home.glassTick++
        GlassSurface {
            ui: home.dockGlassUi
            radius: dock.height / 2
            margin: 10 * home.u
            tint: home.dockGlassTint
        }
        MouseArea { anchors.fill: parent; enabled: home.dockMode !== "home" }   // no atraviesa al editor
        Row {
            anchors.centerIn: parent
            opacity: home.dockSwapFade
            Repeater {
                model: home.dockSlots
                delegate: Row {
                    required property var modelData
                    required property int index
                    Rectangle {   // separador
                        visible: index > 0
                        width: 1; height: 26 * home.u
                        anchors.verticalCenter: parent.verticalCenter
                        color: Qt.rgba(1, 1, 1, 0.30)
                    }
                    Item {
                        id: dockCell
                        readonly property bool active: modelData.page !== undefined
                                                       ? home.page === modelData.page
                                                       : (modelData.selected === true
                                                          || (home.dockPath.length > 0 && home.dockPath[0] === modelData.key))
                        width: home.dockCellWidth
                        height: home.dockHeight
                        opacity: modelData.enabled === false ? 0.4 : 1
                        // Deep Press: el icono se hunde progresivamente durante 380 ms
                        // y se recupera con un rebote moderado al reconocerse o soltar.
                        property real press: 0
                        scale: 1 - 0.12 * press
                        NumberAnimation {
                            id: pressIn
                            target: dockCell; property: "press"; to: 1
                            duration: 380; easing.type: Easing.InOutQuad
                        }
                        NumberAnimation {
                            id: pressOut
                            target: dockCell; property: "press"; to: 0
                            duration: home.reducedMotion ? 0 : 280
                            easing.type: Easing.OutBack; easing.overshoot: 2.2
                        }
                        Rectangle {   // realce de la herramienta pulsada / abierta
                            z: -1
                            anchors.centerIn: parent
                            width: Math.min(parent.width, parent.height) - 8 * home.u
                            height: width
                            radius: width / 2
                            color: "white"
                            opacity: Math.max(0.16 * dockCell.press,
                                              home.dockPath.length > 0 && home.dockPath[0] === modelData.key ? 0.14 : 0)
                        }
                        Text {
                            visible: modelData.more !== true
                            anchors.centerIn: parent
                            text: String.fromCharCode(modelData.glyph)
                            rotation: modelData.rotate || 0
                            font.family: home.iconFamily
                            font.pixelSize: home.dockIconSize
                            color: Qt.rgba(1, 1, 1, dockCell.active ? 1.0 : 0.82)
                        }
                        Row {   // "Más herramientas"
                            visible: modelData.more === true
                            anchors.centerIn: parent
                            spacing: 4 * home.u
                            Repeater {
                                model: 3
                                Rectangle {
                                    width: 5 * home.u; height: width; radius: width / 2
                                    color: Qt.rgba(1, 1, 1, dockCell.active ? 1.0 : 0.82)
                                }
                            }
                        }
                        Rectangle {   // tiene subfunciones
                            visible: modelData.branch === true && modelData.more !== true
                            anchors.horizontalCenter: parent.horizontalCenter
                            anchors.bottom: parent.bottom
                            anchors.bottomMargin: 8 * home.u
                            width: 4 * home.u; height: width; radius: width / 2
                            color: Qt.rgba(1, 1, 1, 0.55)
                        }
                        MouseArea {
                            id: dockCellTap
                            property int pressGeneration: -1
                            property bool held: false
                            property real startX: 0
                            property real startY: 0
                            anchors.fill: parent
                            pressAndHoldInterval: 380
                            preventStealing: held
                            onPressed: function(mouse) {
                                pressGeneration = home.dockGeneration
                                held = false
                                startX = mouse.x
                                startY = mouse.y
                                pressOut.stop()
                                if (!home.reducedMotion && modelData.enabled !== false)
                                    pressIn.restart()
                            }
                            onPositionChanged: function(mouse) {
                                if (held) {
                                    home.dockHoverAt(dockCellTap, mouse.x, mouse.y)
                                } else if (Math.abs(mouse.x - startX) + Math.abs(mouse.y - startY) > 14 * home.u) {
                                    pressIn.stop()          // desplazamiento: cancela el Deep Press
                                    pressOut.restart()
                                }
                            }
                            onPressAndHold: function() {
                                pressIn.stop()
                                pressOut.restart()
                                held = home.dockSlotHold(modelData, pressGeneration, dockCell)
                            }
                            onClicked: home.dockSlotTap(modelData, pressGeneration, dockCell)
                            onReleased: {
                                pressIn.stop()
                                pressOut.restart()
                                if (held)
                                    home.dockReleaseHover()
                                held = false
                            }
                            onCanceled: {
                                pressIn.stop()
                                pressOut.restart()
                                held = false
                                home.dockHoverIndex = -1
                            }
                        }
                        Accessible.role: Accessible.Button
                        Accessible.name: modelData.name + (modelData.enabled === false ? ". No disponible" : "")
                        Accessible.description: modelData.branch === true ? "Mantén pulsado para más acciones" : ""
                    }
                }
            }
        }
    }

    // Botón InGe IA (punto de entrada; el servicio está deshabilitado hoy).
    property string iaStatus: ""
    Rectangle {
        id: iaButton
        z: home.subAppProgress > 0.001 ? 64 : 0   // permanente en todas las subapps
        width: 68 * home.u
        height: width
        radius: width / 2
        x: home.width - home.gutter - width
        y: dock.y + (dock.height - height) / 2
        color: "transparent"
        GlassSurface { ui: home.dockGlassUi; radius: iaButton.width / 2; margin: 10 * home.u; tint: home.dockGlassTint }
        Column {
            anchors.centerIn: parent
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: String.fromCharCode(0xE412)
                font.family: home.iconFamily
                font.pixelSize: 28 * home.u
                color: "white"
            }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "InGe IA"
                font.family: home.fontFamily
                font.pixelSize: 11 * home.u
                color: "white"
            }
        }
        MouseArea {
            anchors.fill: parent
            onClicked: {
                if (home.consumeEditTap())
                    return
                var on = typeof InGeAssistant !== "undefined" && InGeAssistant && InGeAssistant.available
                home.iaStatus = on ? "InGe IA está activa; su interfaz de conversación está pendiente de integración."
                                   : "InGe IA no está disponible en esta versión."
                iaStatusTimer.restart()
            }
        }
        Accessible.role: Accessible.Button
        Accessible.name: "InGe IA"
    }
    Rectangle {
        visible: home.iaStatus.length > 0
        z: 70                                   // también sobre el editor de Calicatas
        x: home.gutter
        width: home.width - 2 * home.gutter
        y: dock.y - height - 12 * home.u
        height: iaText.implicitHeight + 20 * home.u
        radius: 14 * home.u
        color: home.glassFill
        border.width: 1; border.color: home.glassBorder
        Text {
            id: iaText
            anchors.fill: parent
            anchors.margins: 10 * home.u
            text: home.iaStatus
            color: "white"; font.family: home.fontFamily; font.pixelSize: 14 * home.u
            wrapMode: Text.WordWrap
        }
        Timer { id: iaStatusTimer; interval: 3200; onTriggered: home.iaStatus = "" }
    }

    // ================================================= Componentes locales
    // (los componentes inline no ven ids externos: reciben `ui: home`).
    component Tile: Rectangle {
        id: tile
        property var ui
        property string size: "normal"              // compact | normal | wide
        property string presentation: "full"        // icon | name | iconName | full
        property bool primary: false
        property bool addStyle: false
        property bool enabledTile: true
        property int glyph: 0
        property string title: ""
        property string subtitle: ""
        property string cardKey: ""                 // "" = Agregar (no editable)
        property int modelIndex: -1
        property bool comingSoon: false            // módulo en pausa (Earth, Rendiciones)
        signal activated()

        // Pulsación: compresión gradual hasta 0.97 mientras se mantiene.
        property real press: tap.pressed && !dragging && cardKey.length > 0 ? 1 : 0
        Behavior on press { NumberAnimation { duration: tap.pressed ? 420 : 160; easing.type: Easing.OutCubic } }
        // Jiggle Mode: rotación ±1.5° y leve vaivén, fase distinta por tarjeta.
        readonly property bool jiggling: ui.editMode === true && cardKey.length > 0 && !dragging
                                         && !ui.reducedMotion && Qt.application.state === Qt.ApplicationActive
        property real jiggleAmp: jiggling ? 1 : 0
        Behavior on jiggleAmp { NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }
        property real wobble: 0
        property real bob: 0
        SequentialAnimation {
            running: tile.jiggleAmp > 0.001
            loops: Animation.Infinite
            NumberAnimation { target: tile; property: "wobble"; to: tile.modelIndex % 2 === 0 ? 1.5 : -1.5
                              duration: 150 + (tile.modelIndex % 3) * 30; easing.type: Easing.InOutSine }
            NumberAnimation { target: tile; property: "wobble"; to: tile.modelIndex % 2 === 0 ? -1.5 : 1.5
                              duration: 150 + (tile.modelIndex % 3) * 30; easing.type: Easing.InOutSine }
        }
        SequentialAnimation {
            running: tile.jiggleAmp > 0.001
            loops: Animation.Infinite
            NumberAnimation { target: tile; property: "bob"; to: 0.7; duration: 190 + (tile.modelIndex % 4) * 20; easing.type: Easing.InOutSine }
            NumberAnimation { target: tile; property: "bob"; to: -0.7; duration: 190 + (tile.modelIndex % 4) * 20; easing.type: Easing.InOutSine }
        }
        // Al soltar, la tarjeta se asienta en su lugar en vez de saltar.
        property bool settling: false
        property real dragOffsetX: dragging ? ui.dragDx : 0
        property real dragOffsetY: dragging ? ui.dragDy : 0
        Behavior on dragOffsetX { enabled: tile.settling; NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
        Behavior on dragOffsetY { enabled: tile.settling; NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
        Timer { id: settleTimer; interval: 260; onTriggered: tile.settling = false }
        function finishDrag() {
            if (dragging) {
                settling = true
                ui.endDrag(tile)
                settleTimer.restart()
            }
            ui.menuArmed = false
        }
        // Quitar: contracción y fundido; luego solo se quita del Home.
        property bool removing: false
        function removeCard() {
            if (removing)
                return
            removing = true
            if (ui.reducedMotion)
                ui.removeItem(cardKey)
            else
                removeAnim.start()
        }
        SequentialAnimation {
            id: removeAnim
            NumberAnimation { target: tile; property: "pop"; to: 0; duration: 220; easing.type: Easing.InCubic }
            ScriptAction { script: tile.ui.removeItem(tile.cardKey) }
        }

        readonly property bool compact: size === "compact"
        readonly property bool dragging: cardKey.length > 0 && ui.dragKey === cardKey
        readonly property bool showIcon: presentation !== "name"
        readonly property bool showName: presentation !== "icon"
        readonly property bool centered: presentation === "icon" || presentation === "name"
        readonly property bool showDescription: presentation === "full"
        readonly property real colWidth: (ui.width - 2 * ui.gutter - ui.gap) / 2
        width: size === "wide" ? ui.width - 2 * ui.gutter : colWidth
        height: compact ? 82 * ui.u : 142 * ui.u
        // Cambio de tamaño: interpolación geométrica (la cuadrícula se reacomoda).
        Behavior on width { enabled: tile.cardKey.length > 0 && !tile.ui.reducedMotion; NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }
        Behavior on height { enabled: tile.cardKey.length > 0 && !tile.ui.reducedMotion; NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }
        radius: 18 * ui.u
        // pop: lo anima la transición de alta del Flow (gota elástica); lift: arrastre.
        property real pop: 1
        property real lift: dragging ? 1 : 0
        Behavior on lift { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
        opacity: Math.max(0, Math.min(1, pop)) * (enabledTile ? 1 : 0.55) * (tap.pressed && !dragging ? 0.9 : 1)
                 * (cardKey.length > 0 && ui.liftKey === cardKey ? 0 : 1)   // la representa liftGhost
        z: dragging ? 10 : 0
        scale: (0.72 + 0.28 * pop) * (1 + 0.04 * lift) * (1 - 0.03 * press)
        onScaleChanged: ui.glassTick++
        onXChanged: ui.glassTick++                  // reacomodo animado: el cristal acompaña
        onYChanged: ui.glassTick++
        transform: [
            Translate { x: tile.dragOffsetX; y: tile.dragOffsetY + tile.bob * tile.jiggleAmp * tile.ui.u },
            Rotation { origin.x: tile.width / 2; origin.y: tile.height / 2; angle: tile.wobble * tile.jiggleAmp }
        ]
        border.width: primary ? 1 : 0
        border.color: Qt.rgba(1, 1, 1, 0.28)
        gradient: Gradient {
            GradientStop { position: 0.0; color: tile.primary ? Qt.tint(tile.ui.brandBlue, Qt.rgba(1, 1, 1, 0.10)) : "transparent" }
            GradientStop { position: 1.0; color: tile.primary ? tile.ui.brandBlue : "transparent" }
        }
        GlassSurface {
            ui: tile.ui
            visible: !tile.primary && tile.ui.glassTexture !== null
            radius: tile.radius
            margin: 10 * tile.ui.u
        }

        // Presentación centrada: solo icono o solo nombre.
        Column {
            visible: tile.centered
            anchors.centerIn: parent
            width: parent.width - 24 * tile.ui.u
            spacing: 4 * tile.ui.u
            Text {
                visible: tile.showIcon
                anchors.horizontalCenter: parent.horizontalCenter
                text: String.fromCharCode(tile.glyph)
                font.family: tile.ui.iconFamily
                font.pixelSize: (tile.compact ? 34 : 44) * tile.ui.u
                color: "white"
            }
            Text {
                visible: tile.showName
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                text: tile.title
                color: "white"
                font.family: tile.ui.fontFamily
                font.weight: Font.Medium
                font.pixelSize: (tile.compact ? 20 : 22) * tile.ui.u
                elide: Text.ElideRight
            }
        }

        // Presentación estándar: icono y nombre, con descripción opcional.
        Text {   // icono
            id: tileIcon
            visible: !tile.centered && tile.showIcon
            x: 18 * tile.ui.u
            y: tile.compact ? (tile.height - height) / 2 : 16 * tile.ui.u
            text: String.fromCharCode(tile.glyph)
            font.family: tile.ui.iconFamily
            font.pixelSize: (tile.compact ? 34 : 36) * tile.ui.u
            color: "white"
        }
        Column {
            visible: !tile.centered
            x: tile.compact ? tileIcon.x + tileIcon.width + 16 * tile.ui.u : 18 * tile.ui.u
            width: tile.width - x - 14 * tile.ui.u
            y: tile.compact ? (tile.height - height) / 2 : tile.height - height - 16 * tile.ui.u
            spacing: 2 * tile.ui.u
            Text {
                width: parent.width
                text: tile.title
                color: "white"
                font.family: tile.ui.fontFamily
                font.weight: Font.Medium
                font.pixelSize: (tile.compact ? 20 : 22) * tile.ui.u
                elide: Text.ElideRight
            }
            Text {
                width: parent.width
                visible: tile.showDescription && tile.subtitle.length > 0
                text: tile.subtitle
                color: Qt.rgba(1, 1, 1, 0.78)
                font.family: tile.ui.fontFamily
                font.pixelSize: 14.5 * tile.ui.u
                wrapMode: Text.WordWrap
                maximumLineCount: tile.compact ? 1 : 2
                elide: Text.ElideRight
            }
        }
        Rectangle {   // indicador PRÓXIMAMENTE
            visible: tile.comingSoon
            anchors.top: parent.top
            anchors.right: parent.right
            anchors.topMargin: 10 * tile.ui.u
            anchors.rightMargin: 10 * tile.ui.u
            width: soonText.implicitWidth + 14 * tile.ui.u
            height: 20 * tile.ui.u
            radius: height / 2
            color: Qt.rgba(21 / 255, 26 / 255, 48 / 255, 0.55)
            border.width: 1
            border.color: Qt.rgba(1, 1, 1, 0.45)
            Text {
                id: soonText
                anchors.centerIn: parent
                text: "PRÓXIMAMENTE"
                color: "white"
                font.family: tile.ui.fontFamily
                font.weight: Font.Medium
                font.pixelSize: 10 * tile.ui.u
                font.letterSpacing: 0.6
            }
        }
        // Gestos: toque = abrir; pulsación prolongada = menú (o arrastre en
        // modo edición); pulsación + desplazamiento > 14 dp = arrastre.
        MouseArea {
            id: tap
            anchors.fill: parent
            property real startX: 0
            property real startY: 0
            preventStealing: tile.dragging || (tile.ui.menuArmed && tile.ui.menuKey === tile.cardKey)
            pressAndHoldInterval: 450
            onPressed: function(mouse) { startX = mouse.x; startY = mouse.y }
            onClicked: {
                if (tile.ui.consumeEditTap())       // en edición: solo termina la edición
                    return
                if (tile.enabledTile)
                    tile.activated()
            }
            onPressAndHold: function(mouse) {
                if (tile.cardKey.length === 0 || tile.removing)
                    return
                tile.ui.haptic()
                if (tile.ui.editMode)
                    tile.ui.beginDrag(tile, mouse)
                else
                    tile.ui.openMenu(tile)
            }
            onPositionChanged: function(mouse) {
                if (tile.dragging) {
                    tile.ui.dragTo(tile, mouse)
                    return
                }
                if (tile.ui.menuArmed && tile.ui.menuKey === tile.cardKey
                        && Math.abs(mouse.x - startX) + Math.abs(mouse.y - startY) > 14 * tile.ui.u) {
                    tile.ui.closeMenu(true)
                    tile.ui.beginDrag(tile, Qt.point(startX, startY))
                    tile.ui.dragTo(tile, mouse)
                }
            }
            onReleased: tile.finishDrag()
            onCanceled: tile.finishDrag()
        }
        // Modo edición: control discreto para quitar la tarjeta.
        Rectangle {
            id: removeBadge
            z: 3
            opacity: tile.ui.editMode === true && tile.cardKey.length > 0 && !tile.dragging ? 1 : 0
            visible: opacity > 0.01
            Behavior on opacity { NumberAnimation { duration: 180 } }
            x: -8 * tile.ui.u
            y: -8 * tile.ui.u
            width: 26 * tile.ui.u
            height: width
            radius: width / 2
            color: Qt.rgba(21 / 255, 26 / 255, 48 / 255, 0.88)
            border.width: 1
            border.color: Qt.rgba(1, 1, 1, 0.55)
            Text {
                anchors.centerIn: parent
                text: String.fromCharCode(0xE1B2)   // lucide x
                font.family: tile.ui.iconFamily
                font.pixelSize: 15 * tile.ui.u
                color: "white"
            }
            MouseArea {
                anchors.fill: parent
                anchors.margins: -9 * tile.ui.u
                enabled: removeBadge.opacity > 0.5
                onPressed: tile.ui.editTapGuard = true
                onClicked: tile.removeCard()
            }
            Accessible.role: Accessible.Button
            Accessible.name: "Quitar " + tile.title + " del inicio"
        }
        Accessible.role: Accessible.Button
        Accessible.name: tile.title + ". " + (tile.comingSoon ? "Próximamente. " : "") + tile.subtitle
    }

    component Chip: Rectangle {
        id: chip
        property var ui
        property string label: ""
        property bool selected: false
        signal picked()
        width: chipText.implicitWidth + 28 * ui.u
        height: 38 * ui.u
        radius: height / 2
        color: selected ? Qt.rgba(6 / 255, 84 / 255, 162 / 255, 0.85) : "transparent"
        border.width: 1
        border.color: Qt.rgba(1, 1, 1, selected ? 0.5 : 0.35)
        opacity: chipTap.pressed ? 0.8 : 1
        Text {
            id: chipText
            anchors.centerIn: parent
            text: chip.label
            color: "white"
            font.family: chip.ui.fontFamily
            font.pixelSize: 14 * chip.ui.u
        }
        MouseArea { id: chipTap; anchors.fill: parent; onClicked: chip.picked() }
        Accessible.role: Accessible.Button
        Accessible.name: chip.label
    }

    component GlassCircle: Rectangle {
        id: circle
        property var ui
        property real size: 56
        property int glyph: 0
        property string accessibleName: ""
        signal activated()
        width: size; height: size; radius: size / 2
        color: "transparent"
        GlassSurface { ui: circle.ui; radius: circle.size / 2; margin: 8 * circle.ui.u }
        Text {
            anchors.centerIn: parent
            text: String.fromCharCode(circle.glyph)
            font.family: circle.ui.iconFamily
            font.pixelSize: circle.size * 0.48
            color: "white"
        }
        MouseArea { anchors.fill: parent; onClicked: if (!circle.ui || !circle.ui.consumeEditTap || !circle.ui.consumeEditTap()) circle.activated() }
        Accessible.role: Accessible.Button
        Accessible.name: accessibleName
    }

    component GlassRow: Rectangle {
        id: grow
        property var ui
        property string title: ""
        property string subtitle: ""
        property string trailing: ""
        property bool trailingIsGlyph: false
        signal activated()
        height: 68 * ui.u
        radius: 16 * ui.u
        color: ui.glassFill
        border.width: 1; border.color: ui.glassBorder
        Column {
            x: 18 * grow.ui.u
            width: grow.width - x - 70 * grow.ui.u
            anchors.verticalCenter: parent.verticalCenter
            Text { width: parent.width; text: grow.title; color: "white"; font.family: grow.ui.fontFamily; font.pixelSize: 17 * grow.ui.u; elide: Text.ElideRight }
            Text { width: parent.width; visible: grow.subtitle.length > 0; text: grow.subtitle; color: Qt.rgba(1, 1, 1, 0.72); font.family: grow.ui.fontFamily; font.pixelSize: 13.5 * grow.ui.u; elide: Text.ElideRight }
        }
        Text {
            anchors.right: parent.right
            anchors.rightMargin: 18 * grow.ui.u
            anchors.verticalCenter: parent.verticalCenter
            text: grow.trailing
            font.family: grow.trailingIsGlyph ? grow.ui.iconFamily : grow.ui.fontFamily
            font.pixelSize: (grow.trailingIsGlyph ? 24 : 15) * grow.ui.u
            color: "white"
        }
        MouseArea { anchors.fill: parent; onClicked: grow.activated() }
        Accessible.role: Accessible.Button
        Accessible.name: grow.title
    }

    component ActionButton: Rectangle {
        id: action
        property var ui
        property string label: ""
        property bool enabledButton: true
        signal activated()
        height: 56 * ui.u
        radius: 16 * ui.u
        color: "transparent"
        border.width: 1; border.color: Qt.rgba(1, 1, 1, enabledButton ? 0.7 : 0.3)
        opacity: enabledButton ? (actionTap.pressed ? 0.75 : 1) : 0.55
        Text {
            anchors.centerIn: parent
            width: parent.width - 24 * action.ui.u
            horizontalAlignment: Text.AlignHCenter
            text: action.label
            color: "white"; font.family: action.ui.fontFamily; font.pixelSize: 16 * action.ui.u
            elide: Text.ElideRight
        }
        MouseArea { id: actionTap; anchors.fill: parent; enabled: action.enabledButton; onClicked: action.activated() }
        Accessible.role: Accessible.Button
        Accessible.name: action.label
    }

    // Página de módulo: fondo azul oscuro translúcido, fundido + leve desplazamiento.
    component PageFrame: Rectangle {
        id: frame
        property var ui
        property bool shown: false
        property string title: ""
        default property alias content: body.data
        anchors.fill: parent
        color: Qt.rgba(21 / 255, 26 / 255, 48 / 255, 0.86)
        opacity: shown ? 1 : 0
        visible: opacity > 0
        Behavior on opacity { OpacityAnimator { duration: frame.ui.reducedMotion ? 0 : 260 } }
        transform: Translate { y: frame.shown ? 0 : 14 * frame.ui.u; Behavior on y { NumberAnimation { duration: frame.ui.reducedMotion ? 0 : 260; easing.type: Easing.OutCubic } } }
        Flickable {
            anchors.fill: parent
            contentWidth: width
            contentHeight: body.y + body.height + frame.ui.dockArea
            boundsBehavior: Flickable.StopAtBounds
            Text {
                id: pageTitle
                x: frame.ui.gutter
                y: frame.ui.topInset + 24 * frame.ui.u
                text: frame.title
                color: "white"
                font.family: frame.ui.fontFamily
                font.weight: Font.DemiBold
                font.pixelSize: 30 * frame.ui.u
            }
            Column {
                id: body
                x: frame.ui.gutter
                width: frame.width - 2 * frame.ui.gutter
                y: pageTitle.y + pageTitle.height + 20 * frame.ui.u
                spacing: 12 * frame.ui.u
            }
        }
    }
}

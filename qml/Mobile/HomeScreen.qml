import QtQuick
import QtQuick.Window
import QtQuick.Effects
import QtQuick.Shapes
import QtQuick.Controls as Controls
import "halloween" as Halloween
import "kawaii" as Kawaii
import QtCore
import InGe 1.0
import "lib/AccountText.js" as AccountText
import "renditions/RStyle.js" as RStyle
import "renditions" as Renditions
import "assistant" as Assistant
import "settings" as AppSettings
import InGe.Mobile as MobileBackend
import InGe.CoreFlow 3.0 as CoreFlowModule

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
    // Movimiento: el del sistema (Main) o la preferencia «Reducir movimiento».
    property bool systemReducedMotion: false
    readonly property bool reducedMotion: systemReducedMotion || appearancePrefs.reduceMotion
    // Hero (InGeCoreFlow.hero): sólo con advancedMotion (Muy alta / Extrema); si no, null.
    readonly property var heroMotion: CoreFlowModule.InGeCoreFlow.advancedMotion === true && !reducedMotion
                                      ? CoreFlowModule.InGeCoreFlow.hero : null
    // «Extrema» (GraphicsCore.extremeGlass): zoom hero mosaico <-> app, cascada,
    // parallax y realce al pulsar, con las curvas Hero de InGeCoreFlow.
    readonly property bool extremeMotion: !reducedMotion && GraphicsCore.extremeGlass === true
    readonly property var heroCurves: CoreFlowModule.InGeCoreFlow.hero
    signal cascadeRequested()
    readonly property real parallaxY: extremeMotion && page === "home" && typeof homeScroll !== "undefined"
                                      ? -Math.min(height * 0.05, homeScroll.contentY * 0.12) : 0
    property rect heroOrigin: Qt.rect(0, 0, 0, 0)
    property real heroOriginRadius: 18 * u
    property string heroPrevPage: "home"
    property real editColumnY: -1               // columna fija durante el modo edición
    function heroLaunch(item) {
        if (!extremeMotion || !item) return
        var p = item.mapToItem(home, 0, 0)
        heroOrigin = Qt.rect(p.x, p.y, item.width, item.height)
        heroOriginRadius = item.radius !== undefined ? item.radius : 18 * u
        heroZoom.run(true)
    }
    Connections {
        target: home
        function onEditModeChanged() { home.editColumnY = home.editMode ? homeColumn.naturalY : -1 }
        function onPageChanged() {
            if (home.page === "home" && home.heroPrevPage !== "home" && home.extremeMotion) {
                if (home.heroOrigin.width > 0) heroZoom.run(false)
                home.cascadeRequested()
            }
            home.heroPrevPage = home.page
        }
    }
    Timer { interval: 60; running: true; onTriggered: if (home.extremeMotion) home.cascadeRequested() }
    // Píldora líquida del Dock (Muy alta / Extrema): viaja entre pestañas como líquido.
    readonly property bool liquidPill: !reducedMotion
        && (GraphicsCore.advancedMotion === true || GraphicsCore.extremeGlass === true)
    // Apariencia (Configuración › Apariencia). El tema oscuro aplica por ahora a Configuración.
    readonly property bool liquidGlass: appearancePrefs.liquidGlass
    readonly property string appSkin: halloweenController.resolvedSkin
    readonly property var seasonalController: halloweenController
    readonly property bool darkTheme: appearancePrefs.theme === "dark"
                                      || (appearancePrefs.theme === "auto" && Application.styleHints.colorScheme === Qt.ColorScheme.Dark)
    // El tema oscuro se aplica a la paleta de Rendiciones antes de crearla; al
    // cambiar de tema la subapp se recrea (si no está en pantalla) con la nueva paleta.
    onAppSkinChanged: {
        RStyle.setSkin(appSkin)
        if (page !== "rendiciones") renditionsEverLoaded = false
        if (page !== "calicatas") calicatasEditorEverLoaded = false
    }
    onDarkThemeChanged: {
        RStyle.setDark(darkTheme)
        if (page !== "rendiciones") renditionsEverLoaded = false
        if (page !== "calicatas") calicatasEditorEverLoaded = false
    }
    Settings { id: appearancePrefs; category: "appearance"
               property bool reduceMotion: false; property bool liquidGlass: true; property string theme: "light"
               property string skin: "none"
               property bool halloweenScares: true; property bool halloweenSound: false }

    Binding { target: CoreFlowModule.InGeCoreFlow; property: "appSkin"; value: home.appSkin }
    Binding { target: CoreFlowModule.InGeCoreFlow; property: "halloweenController"; value: halloweenController }
    Binding { target: CoreFlowModule.InGeCoreFlow; property: "liquidGlassMaterial"; value: home.liquidGlassMaterial }
    // Controls popup items and scrims live here, including nested page dialogs.
    readonly property bool halloweenPopupVisible: {
        var overlay = Controls.Overlay.overlay
        if (!overlay) return false
        for (var i = 0; i < overlay.children.length; ++i)
            if (overlay.children[i].visible) return true
        return false
    }
    Halloween.HalloweenController {
        id: halloweenController
        flow: CoreFlowModule.InGeCoreFlow
        choice: appearancePrefs.skin
        foreground: home.visible && home.authReady && auth.logged && Qt.application.state === Qt.ApplicationActive
            && ["home", "rendiciones", "calicatas", "drive", "settings"].indexOf(home.page) >= 0
        reducedMotion: home.reducedMotion
        scaresEnabled: appearancePrefs.halloweenScares
        soundEnabled: appearancePrefs.halloweenSound
        guestSurfaceReady: dock.visible && dock.opacity>0.99 && !home.dockVertical && !dockMenuBox.open
        safeSurface: !home.halloweenPopupVisible && !flow.imeVisible && !flow.imeAnimating
            && !home.addOpen && !home.dockPressActive && home.dockPath.length === 0
            && !home.optionsCard && home.sheetGrow <= 0 && home.menuKey.length === 0
            && home.liftKey.length === 0 && home.overlayLevel <= 0 && !home.editMode
            && !home.touchFocusActive && !assistantSheet.open && !subAppEnter.running && !subAppExit.running
            && !CalicataCloud.busy && !settingsApp.halloweenBlocked
            && (!renditionsLoader.item || !renditionsLoader.item.halloweenBlocked)
            && (!calicatasEditor.item || !calicatasEditor.item.halloweenBlocked)
        onScarePresented: home.dockHaptic("light")
    }
    // Observe genuine input even inside Calicatas editing and Rendiciones:
    // Halloween's motionActive/safeSurface are deliberately disabled there.
    // This handler is passive and never takes the gesture away from a control.
    property double kawaiiLastInteractionAt: Date.now()
    readonly property bool kawaiiAppForeground: home.visible && home.authReady
        && auth.logged && Qt.application.state === Qt.ApplicationActive
    PointHandler {
        enabled: halloweenController.motionActive
                 || (home.appSkin === "ingenieros" && home.kawaiiAppForeground)
        target: null
        onActiveChanged: {
            halloweenController.touchActive = active
            home.kawaiiLastInteractionAt = Date.now()
        }
        onPointChanged: halloweenController.touchPoint = Qt.point(point.position.x / Math.max(1, home.width), point.position.y / Math.max(1, home.height))
    }
    // Original 10s MP4/AAC: one visit after 20s of genuine AFK, on every
    // authenticated InGe+ page. Do NOT gate with Halloween.safe/motionActive:
    // those exclude the Calicatas editor and other valid Kawaii surfaces.
    Kawaii.KawaiiCinnamorollVisit {
        parent: Controls.Overlay.overlay ? Controls.Overlay.overlay : home
        anchors.fill: parent
        mediaEnabled: home.appSkin === "ingenieros" && home.kawaiiAppForeground
        allowed: home.appSkin === "ingenieros" && home.kawaiiAppForeground
            && !home.reducedMotion && !halloweenController.touchActive
        lastInteractionAt: home.kawaiiLastInteractionAt
    }
    Halloween.HalloweenScare {
        anchors.fill: parent; z: 79
        controller: halloweenController
        bottomInset: home.dockArea
    }
    signal signOutRequested()

    // ------------------------------------------------------------ Paleta
    readonly property color navy: "#151A30"
    readonly property color navy2: "#1C2D50"
    readonly property color brandBlue: "#0654A2"
    readonly property color brandGreen: "#486426"
    readonly property color glassFill: appSkin === "halloween" ? RStyle.glass(0.9) : darkTheme ? Qt.rgba(8 / 255, 10 / 255, 16 / 255, 0.62) : Qt.rgba(28 / 255, 45 / 255, 80 / 255, 0.50)
    readonly property color glassBorder: appSkin === "halloween" ? RStyle.edge(0.95) : darkTheme ? Qt.rgba(1, 1, 1, 0.12) : Qt.rgba(1, 1, 1, 0.22)

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
        addOpen = false
        if (target === "profile") {                         // Perfil se integró en Configuración › Mi cuenta
            settingsApp.pendingPage = "account"
            target = "settings"
        }
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
        if (assistantSheet.open) { assistantSheet.close(); return true }   // InGe IA global
        if (page === "settings" && settingsApp.handleBack()) return true
        if (subAppEnter.running || subAppExit.running)
            return true
        if ((page === "calicatas" || page === "earth" || page === "rendiciones") && dockPath.length > 0) {   // submenú del dock
            dockPath = dockPath.slice(0, -1)
            return true
        }
        if (page === "rendiciones") {
            // Atrás recorre la pila interna de Rendiciones antes de volver al Home.
            if (renditionsLoader.item && renditionsLoader.item.handleBack()) return true
            page = "home"
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
        else if (page === "earth") { if (earthNativeLoader.item && earthNativeLoader.item.handleBack()) return true; page = earthReturnPage; earthReturnPage = "home"; return true }
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
    // Dedo en coordenadas de la cuadrícula: la ficha lo sigue aunque la cuadrícula
    // la cambie de hueco (antes saltaba al reordenar). Su hueco real queda como
    // hueco fantasma (Tile.dropGhost) y las vecinas se apartan con la transición
    // move del Flow: sin huecos ni solapes.
    property point dragPoint: Qt.point(0, 0)
    property point dragStart: Qt.point(0, 0)
    property string dragSwapGuard: ""         // histéresis: no reordena dos veces sobre la misma ficha
    property Item dragTile: null              // ficha arrastrada (hueco fantasma)
    function beginDrag(tile, mouse) {
        editMode = true                       // reorganizar = modo edición (como iOS)
        dragKey = tile.cardKey
        dragTile = tile
        dragMoved = false
        dragGrab = Qt.point(mouse.x, mouse.y)
        dragPoint = tile.mapToItem(grid, mouse.x, mouse.y)
        dragStart = dragPoint
        dragSwapGuard = ""
        dragDx = 0
        dragDy = 0
    }
    function dragTo(tile, mouse) {
        var p = tile.mapToItem(grid, mouse.x, mouse.y)
        dragPoint = p
        if (Math.abs(p.x - dragStart.x) + Math.abs(p.y - dragStart.y) > 12 * u)
            dragMoved = true
        dragDx = p.x - (tile.x + dragGrab.x)
        dragDy = p.y - (tile.y + dragGrab.y)
        glassTick++
        var over = ""
        for (var i = 0; i < grid.children.length; ++i) {
            var other = grid.children[i]
            if (other === tile || other.cardKey === undefined || other.cardKey.length === 0
                    || other.modelIndex < 0 || !other.visible)
                continue
            if (p.x >= other.x && p.x <= other.x + other.width && p.y >= other.y && p.y <= other.y + other.height) {
                over = other.cardKey
                if (other.cardKey !== dragSwapGuard && other.modelIndex !== tile.modelIndex) {
                    homeModel.move(tile.modelIndex, other.modelIndex, 1)
                    dragSwapGuard = other.cardKey
                }
                break
            }
        }
        if (over !== dragSwapGuard) dragSwapGuard = over
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
    // Hoja Personalizar: el Home sigue visible detrás (vidrio del Dock), sin desenfoque ni velo negro.
    readonly property bool optionsSheetOpen: optionsCard !== null && menuKey.length === 0
    property real overlayBlurLevel: optionsSheetOpen ? 0 : 0.85 * overlayLevel
    Behavior on overlayBlurLevel { enabled: !home.reducedMotion; NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
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
        EarthNative.clearGeoLayers()
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
        else if (k === "rendiciones_app") navigate("rendiciones")
        else if (k === "earth_app") openEarth("home")
        else if (k === "drive_app") navigate("drive")
        else if (k === "project" || k === "calicatasProject") openCalicatas(it.targetId, "")
        else if (k === "calicata") openCalicatas(it.projectId, it.targetId)
        else if (k === "settings") navigate("settings")
        else if (k === "profile") navigate("profile")
    }
    // Ningún módulo en pausa: Rendiciones es una subapp QML real (2026-10-14).
    function isComingSoon(kind) { return false }
    function notify(message) {
        iaStatus = message
        iaStatusTimer.restart()
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
    // y por día (caché local); se rotan cada 5 s sin consultar al servidor.
    // Fallos transitorios: hasta 3 intentos al día, espaciados (30 s, 2 min),
    // nunca un bloqueo de todo el día por un solo fallo; mientras tanto se
    // conserva el último lote válido de la cuenta. Sin IA: saludo local
    // estable y sin atribución.
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
        // Español y neutro en género (la app es en español; se retiró el inglés de bienvenida).
        return (AccountText.hasVisibleText(firstName) ? "Te damos la bienvenida, " + firstName + "." : "Te damos la bienvenida.")
                + "\n¿Qué avanzamos hoy?"
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
        greetingRetry.stop()
        greetingRequestId = ""
        aiPhrases = []
        aiIndex = 0
        greetingText = localGreeting()
        if (userId.length === 0)
            return
        var cache = readMap(store.greetingsJson)[userId]
        if (cache && cache.lang !== "es") cache = null    // lotes antiguos en inglés: se piden de nuevo
        var cached = cache && Array.isArray(cache.phrases) ? cleanPhrases(cache.phrases) : []
        if (cached.length > 0) {                     // último lote válido de ESTA cuenta
            aiPhrases = cached
            greetingText = cached[0]
        }
        if (cache && cache.date === todayKey() && cached.length > 0)
            return                                   // lote de hoy: sin consultas
        requestGreetings()
    }
    readonly property int greetingMaxAttempts: 3
    function greetingAttemptsToday() {
        var cache = readMap(store.greetingsJson)[userId] || {}
        return cache.attemptDate === todayKey() ? Number(cache.attempts || 0) : 0
    }
    function requestGreetings() {
        if (greetingRequestId.length > 0 || userId.length === 0)
            return
        if (typeof InGeAssistant === "undefined" || !InGeAssistant || !InGeAssistant.available)
            return                                   // se reintenta en onAvailableChanged
        var attempts = greetingAttemptsToday()
        if (attempts >= greetingMaxAttempts)
            return                                   // límite diario: sin solicitudes infinitas
        var name = AccountText.hasVisibleText(firstName) ? firstName : "equipo"
        greetingRequestId = "home-greetings-" + Date.now()
        var accepted = InGeAssistant.request({
            operation: "chat",
            id: greetingRequestId,
            messages: [{ role: "user", text:
                "Escribe 6 saludos breves y distintos para " + name + ", que abre InGe+, una app de ingeniería de campo. "
                + "Solo en español y con lenguaje neutro en género. Cada saludo tiene exactamente dos líneas separadas por un salto de línea: "
                + "la línea 1 saluda a " + name + " por su nombre (por ejemplo 'Hola de nuevo, " + name + ".' o 'Buenas tardes, " + name + ".'); "
                + "la línea 2 es una frase original, profesional y motivadora de 45 caracteres como máximo sobre ingeniería, trabajo de campo, proyectos o productividad. "
                + "Sin emojis ni comillas dentro de las líneas. Responde SOLO con un arreglo JSON de 6 cadenas." }]
        })
        if (!accepted) {
            greetingRequestId = ""
            return
        }
        // El intento se registra al enviarlo (un cierre de la app no reinicia el contador).
        var all = readMap(store.greetingsJson)
        var entry = all[userId] || {}
        entry.attemptDate = todayKey()
        entry.attempts = attempts + 1
        all[userId] = entry
        store.greetingsJson = JSON.stringify(all)
    }
    function greetingFailed() {
        var attempts = greetingAttemptsToday()
        if (attempts < greetingMaxAttempts) {
            greetingRetry.interval = attempts <= 1 ? 30000 : 120000
            greetingRetry.restart()
        }
    }
    Timer {
        id: greetingRetry
        repeat: false
        onTriggered: home.requestGreetings()
    }
    // Cuando InGeAssistant pasa a disponible (sesión lista), se pide el lote.
    Connections {
        target: typeof InGeAssistant !== "undefined" ? InGeAssistant : null
        function onAvailableChanged() {
            if (InGeAssistant.available && home.greetingRequestId.length === 0)
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
            if (phrases.length < 2) {
                // Fallo transitorio o lote insuficiente: se conserva el último lote
                // válido (o el saludo local) y se reintenta de forma espaciada.
                home.greetingFailed()
                return
            }
            var all = home.readMap(store.greetingsJson)
            var entry = all[home.userId] || {}
            entry.date = home.todayKey()
            entry.phrases = phrases
            entry.lang = "es"
            all[home.userId] = entry
            store.greetingsJson = JSON.stringify(all)
            home.aiPhrases = phrases
            home.aiIndex = 0
            home.greetingText = phrases[0]
        }
    }
    // Rotación local: solo con frases reales, en el inicio, en primer plano.
    Timer {
        interval: 5000
        repeat: true
        running: home.greetingFromAi && home.aiPhrases.length > 1 && home.visible
                 && home.page === "home" && !home.addOpen && !home.editMode   // edición: saludo fijo
                 && Qt.application.state === Qt.ApplicationActive
        onTriggered: {
            if (phraseSwap.running)
                return                               // no reinicia una transición en curso
            if (home.reducedMotion) {                // movimiento reducido: cambio directo
                home.aiIndex = (home.aiIndex + 1) % home.aiPhrases.length
                home.greetingText = home.aiPhrases[home.aiIndex]
                return
            }
            phraseSwap.restart()
        }
    }
    Component.onCompleted: { dockDisplayedSlots = dockSlots; RStyle.setSkin(appSkin); RStyle.setDark(darkTheme); loadItems(); refreshGreeting(); CalicataCloud.refreshProjects(); syncReminders() }

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

        Renditions.RendicionesSyncBackdrop {
            id: corporateHomeBackdrop
            anchors.fill: parent
            visible: home.appSkin === "ingema" || home.appSkin === "halloween" || home.appSkin === "ingenieros"
            skin: home.appSkin
            halloweenController: home.seasonalController
            dark: true                       // Home retains white labels over the Web's navy background.
            mode: "synced"
            running: visible && home.visible && home.page === "home"
            reducedMotion: home.reducedMotion
            lowCost: home.dockLowCostGlass
            // «Extrema»: parallax de las auras con el desplazamiento.
            transform: [Scale { origin.x: corporateHomeBackdrop.width / 2; xScale: home.extremeMotion ? 1.06 : 1; yScale: xScale },
                        Translate { y: home.parallaxY }]
        }
        Image {
            id: photoImage
            anchors.fill: parent
            // «Extrema»: parallax del fondo; el vidrio lo sigue (GlassSurface mapea sobre photoImage).
            transform: [Scale { origin.x: photoImage.width / 2; xScale: home.extremeMotion ? 1.06 : 1; yScale: xScale },
                        Translate { y: home.parallaxY }]
            visible: home.appSkin !== "ingema" && home.appSkin !== "halloween" && home.appSkin !== "ingenieros"
            source: home.photo.source
            fillMode: Image.PreserveAspectCrop
            horizontalAlignment: home.photo.align
            asynchronous: true
            cache: true
            sourceSize.height: Math.min(2400, Math.round(home.height * 1.5))
        }
        Rectangle {                                    // tema oscuro: foto atenuada
            anchors.fill: photoImage; color: "#000000"
            opacity: home.darkTheme ? 0.45 : 0
            Behavior on opacity { NumberAnimation { duration: 400 } }
        }
        // Desenfoque real de la foto, una sola vez en GPU (la foto es estática)
        // y a media resolución; todas las superficies glass lo reutilizan.
        MultiEffect {
            id: photoBlur
            anchors.fill: photoImage
            source: home.appSkin === "ingema" || home.appSkin === "halloween" || home.appSkin === "ingenieros" ? corporateHomeBackdrop : photoImage
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
            scale: home.page === "settings" ? 0.95 : 1          // Home se aleja al entrar a Configuración
            visible: opacity > 0
            Behavior on opacity { OpacityAnimator { duration: home.reducedMotion ? 0 : 260 } }
            Behavior on scale { ScaleAnimator { duration: home.reducedMotion ? 0 : 560; easing.type: Easing.OutQuint } }

            Rectangle {                                // hueco fantasma: donde caerá la ficha arrastrada
                z: -1
                visible: home.dragKey.length > 0 && home.dragTile !== null
                x: visible ? homeColumn.x + grid.x + home.dragTile.x : 0
                y: visible ? homeColumn.y + grid.y + home.dragTile.y : 0
                width: visible ? home.dragTile.width : 0
                height: visible ? home.dragTile.height : 0
                radius: 18 * home.u
                color: Qt.rgba(1, 1, 1, 0.07)
                border.width: 1.5
                border.color: Qt.rgba(1, 1, 1, 0.42)
                Behavior on x { enabled: !home.reducedMotion; NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
                Behavior on y { enabled: !home.reducedMotion; NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
            }
            Column {
                id: homeColumn
                onYChanged: home.glassTick++
                x: home.gutter
                width: home.width - 2 * home.gutter
                readonly property real naturalY: Math.max(home.topInset + 80 * home.u,
                                                          home.height - home.dockArea - height)
                // Edición: la columna queda fija (el saludo no sube ni se corta al reordenar).
                y: home.editMode && home.editColumnY >= 0 ? home.editColumnY : naturalY
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
                        wrapMode: home.editMode ? Text.NoWrap : Text.WordWrap
                        // Edición: una sola línea que se ajusta al ancho, sin cortarse.
                        maximumLineCount: home.editMode ? 1 : 2
                        // Nunca «…»: el texto reduce su tamaño (mín. 16 u) dentro de sus 2 líneas reservadas.
                        height: home.editMode ? implicitHeight : greetingArea.height
                        verticalAlignment: Text.AlignBottom
                        fontSizeMode: home.editMode ? Text.HorizontalFit : Text.Fit
                        minimumPixelSize: (home.editMode ? 14 : 16) * home.u
                        elide: Text.ElideNone
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
                            id: homeTile
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
                            onActivated: {
                                if (home.itemAvailable(model)) home.heroLaunch(homeTile)   // «Extrema»: zoom hero
                                home.activateItem(model)
                            }
                        }
                    }

                }
            }
        }

        // Notificaciones (arriba a la derecha)
        GlassCircle {
            id: settingsCircle
            ui: home
            x: home.width - width - home.gutter
            y: home.topInset + 12 * home.u
            size: 56 * home.u
            glyph: 0xE059
            accessibleName: "Notificaciones y recordatorios"
            visible: home.page === "home"
            onActivated: { home.heroLaunch(settingsCircle); home.navigate("settings") }
        }

        // Configuración (incluye la cuenta; Perfil ya no es una página aparte) (diseño claro aprobado con auras de estado).
        Settings {                                     // QtCore: preferencias de seguridad
            id: securityPrefs
            category: "security"
            property bool biometricUnlock: false
        }
        Loader {                                       // espacio del servidor (InGe Drive), sólo con Configuración abierta
            id: storageProbe
            active: settingsApp.shown
            sourceComponent: Component { MobileBackend.NothingDocuments { Component.onCompleted: navigate("home") } }
        }
        AppSettings.SettingsApp {
            id: settingsApp
            anchors.fill: parent
            ui: home
            readonly property bool shown: home.page === "settings"
            opacity: shown ? 1 : 0
            scale: shown ? 1 : 1.045
            visible: opacity > 0
            Behavior on opacity { OpacityAnimator { duration: home.reducedMotion ? 0 : 460; easing.type: Easing.OutCubic } }
            Behavior on scale { ScaleAnimator { duration: home.reducedMotion ? 0 : 640; easing.type: Easing.OutQuint } }
            backgroundSource: home.photo.source
            userName: home.authReady && auth.logged
                      ? AccountText.displayPersonName(auth.fullName.length > 0 ? auth.fullName : (auth.nombre + " " + auth.apellido), "", true) : ""
            userEmail: home.authReady && auth.logged ? String(auth.email || "") : ""
            avatarSource: home.authReady && auth.logged ? String(auth.avatarUrl || "") : ""
            // Sin nombre/apellido en Auth: se separa el nombre completo del perfil.
            readonly property var nameParts: home.authReady ? String(auth.fullName || "").trim().split(/\s+/) : []
            firstName: home.authReady ? (String(auth.nombre || "").length ? String(auth.nombre) : (nameParts[0] || "")) : ""
            lastName: home.authReady ? (String(auth.apellido || "").length ? String(auth.apellido) : nameParts.slice(1).join(" ")) : ""
            userPhone: home.authReady ? String(auth.phone || "") : ""
            userPosition: home.authReady ? String(auth.position || "") : ""
            userArea: home.authReady ? String(auth.area || "") : ""
            sessions: home.authReady ? (auth.activeSessions || []) : []
            sessionsBusy: home.authReady && auth.sessionsBusy
            savedAccounts: home.authReady ? (auth.savedAccounts || []) : []
            currentAccountId: home.authReady ? String(auth.currentAccountId || "") : ""
            onSessionsRefreshRequested: if (home.authReady && auth.logged) auth.refreshActiveSessions()
            onSessionRevokeRequested: function(sessionId) { securityNotice = "Cerrando sesión…"; auth.revokeSession(sessionId) }
            onSignOutOthersRequested: { securityNotice = "Cerrando las otras sesiones…"; auth.signOutOtherSessions() }
            onAccountSwitchRequested: function(accountId) { auth.switchToSavedAccount(accountId) }
            onAddAccountRequested: home.signOutRequested()      // al login; las cuentas guardadas se conservan
            onAvatarChosen: function(file) { accountNotice = "Subiendo foto…"; auth.updateUserAvatar(file) }
            onProfileSaveRequested: function(nombre, apellido, phone) {
                if (!nombre.length) { accountNotice = "Escribe tu nombre."; return }
                accountNotice = ""
                profileSaving = true
                auth.updateUserProfile(nombre, apellido, phone)
            }
            appVersion: Qt.application.version
            reduceMotion: appearancePrefs.reduceMotion
            liquidGlass: appearancePrefs.liquidGlass
            theme: appearancePrefs.theme
            onReduceMotionToggled: function(value) { appearancePrefs.reduceMotion = value }
            onLiquidGlassToggled: function(value) { appearancePrefs.liquidGlass = value }
            onThemeSelected: function(key) { appearancePrefs.theme = key }
            skin: appearancePrefs.skin
            effectiveSkin: home.appSkin
            halloweenScares: appearancePrefs.halloweenScares
            halloweenSound: appearancePrefs.halloweenSound
            onHalloweenScaresToggled: function(value) { appearancePrefs.halloweenScares = value }
            onHalloweenSoundToggled: function(value) { appearancePrefs.halloweenSound = value }
            onSkinSelected: function(key) { appearancePrefs.skin = key }
            syncMode: renditionsLoader.item && renditionsLoader.item.syncMode !== undefined ? renditionsLoader.item.syncMode : "unknown"
            syncText: syncMode === "synced" ? "Al día" : syncMode === "error" ? "Con errores" : syncMode === "offline" ? "Sin conexión"
                    : syncMode === "attention" ? "Revisar" : syncMode === "syncing" ? "Sincronizando" : ""
            notificationsText: store.remindersEnabled ? "Activadas" : "Desactivadas"
            renditionsSync: syncMode
            renditionsPending: renditionsLoader.item && renditionsLoader.item.pendingCount !== undefined ? renditionsLoader.item.pendingCount : 0
            calicatasSync: calicatasEditor.item && calicatasEditor.item.healthAuraMode !== undefined ? calicatasEditor.item.healthAuraMode : "unknown"
            syncBusy: !!renditionsLoader.item && renditionsLoader.item.phase !== undefined
                      && (renditionsLoader.item.phase === "PUSHING" || renditionsLoader.item.phase === "PULLING")
            mfaEnabled: home.authReady && auth.mfaEnabled === true
            onMfaEnrollRequested: { securityNotice = "Preparando…"; auth.enrollTotp() }
            onMfaConfirmRequested: function(factorId, code) {
                if (code.length < 6) { securityNotice = "Escribe los 6 dígitos del código."; return }
                securityNotice = "Verificando…"
                auth.confirmTotpEnrollment(factorId, code)
            }
            onMfaDisableRequested: { securityNotice = "Desactivando…"; auth.disableTotp() }
            onSyncNowRequested: {
                if (renditionsLoader.item && renditionsLoader.item.synchronize) renditionsLoader.item.synchronize(true)
                CalicataCloud.refreshProjects()
            }
            biometricAvailable: typeof biometric !== "undefined" && biometric !== null && biometric.available
            biometricBusy: typeof biometric !== "undefined" && biometric !== null && biometric.busy
            biometricEnabled: securityPrefs.biometricUnlock
            storageStats: storageProbe.item ? storageProbe.item.stats : ({})
            storageBusy: storageProbe.item ? storageProbe.item.busy : false
            storageError: storageProbe.item ? String(storageProbe.item.error || "") : ""
            onShownChanged: if (shown && typeof biometric !== "undefined" && biometric) biometric.refresh()
            onCloseRequested: home.page = "home"
            onSignOutRequested: home.signOutRequested()
            onNotificationsToggled: store.remindersEnabled = !store.remindersEnabled
            onStorageRefreshRequested: if (storageProbe.item) storageProbe.item.refresh()
            onPasswordResetRequested: {
                if (!home.authReady || !String(auth.email || "").length) return
                home.passwordResetPending = true
                securityNotice = "Enviando enlace…"
                auth.requestPasswordReset(String(auth.email))
            }
            // Activar exige confirmar con la huella o el rostro; desactivar es directo.
            onBiometricToggled: function(value) {
                securityNotice = ""
                if (!value) { securityPrefs.biometricUnlock = false; return }
                home.biometricEnrollPending = true
                biometric.authenticate()
            }
        }
        Connections {
            target: typeof biometric !== "undefined" ? biometric : null
            ignoreUnknownSignals: true
            function onFinished(ok) {
                if (!home.biometricEnrollPending) return
                home.biometricEnrollPending = false
                securityPrefs.biometricUnlock = ok
                settingsApp.securityNotice = ok ? "Listo: podrás desbloquear InGe+ con tu huella o rostro."
                                                : "No se activó: la verificación no se completó."
            }
        }
        // El aviso de envío solo aparece cuando el servidor lo confirma.
        Connections {
            target: auth
            ignoreUnknownSignals: true
            function onProfileUpdatedOk() { settingsApp.profileSaving = false; settingsApp.accountNotice = "Cambios guardados." }
            function onProfileUpdatedFail(message) { settingsApp.profileSaving = false; settingsApp.accountNotice = "No se guardó: " + message }
            function onProfileAvatarSynced() { settingsApp.accountNotice = "Foto de perfil actualizada." }
            function onProfileAvatarSyncWarning(message) { settingsApp.accountNotice = message }
            function onSessionsActionOk(message) { settingsApp.securityNotice = message }
            function onMfaEnrollReady(factorId, qrImage, secret, uri) {
                settingsApp.securityNotice = ""
                settingsApp.mfaEnrollment = { factorId: factorId, qr: qrImage, secret: secret, uri: uri }
            }
            function onMfaOk(message) { settingsApp.mfaEnrollment = null; settingsApp.securityNotice = message }
            function onMfaFail(message) { settingsApp.securityNotice = message }
            function onSessionsActionFail(message) { settingsApp.securityNotice = message }
            function onPasswordResetRequestedOk(email) {
                if (!home.passwordResetPending) return
                home.passwordResetPending = false
                settingsApp.securityNotice = "Te enviamos un enlace para cambiar tu contraseña a " + email + "."
            }
            function onPasswordResetRequestedFail(message) {
                if (!home.passwordResetPending) return
                home.passwordResetPending = false
                settingsApp.securityNotice = "No se pudo enviar el enlace: " + message
            }
        }
        Loader {
            id: earthNativeLoader
            anchors.fill: parent
            active: home.page === "earth" && home.visible
            visible: active
            // Entrada con fundido (antes aparecía de golpe sobre el Home).
            opacity: active && status === Loader.Ready ? 1 : 0
            Behavior on opacity { OpacityAnimator { duration: home.reducedMotion ? 0 : 280; easing.type: Easing.OutCubic } }
            sourceComponent: Component {
                RetroplasmaEarthView {
                    controller: EarthNative
                    performanceProfile: GraphicsCore.fidelity
                    performancePressure: GraphicsCore.powerSaveMode || GraphicsCore.thermalStatus >= 3
                                         || (GraphicsCore.memoryTrimLevel >= 10 && GraphicsCore.memoryTrimLevel <= 15)
                                         || GraphicsCore.memoryTrimLevel >= 60
                    otherGpsClientActive: function() { return home.page === "calicatas" && calicatasEditor.item && calicatasEditor.item.gpsEnabled }
                    u: home.u
                    fontFamily: home.fontFamily
                    iconFamily: home.iconFamily
                    lowCostGlass: home.dockLowCostGlass
                    glassTint: home.earthGlassTint
                    externalGlassTick: home.glassTick
                    requestedTarget: home.earthRequestedTarget
                    safeTop: home.topInset
                    safeBottom: Qt.inputMethod.visible ? 14 * home.u : home.dockArea
                    reducedMotion: home.reducedMotion
                    diagnosticsShown: home.earthDiagnosticsShown
                    coordinatesShown: home.earthCoordinatesShown
                    coordinateEntryShown: home.earthCoordinateEntryShown
                    sourceEntryShown: home.earthSourceEntryShown
                    onCoordinateEntryFinished: home.earthCoordinateEntryShown = false
                }
            }
        }
        // Subapp Rendiciones: QML nativo sobre RenditionsUi -> bridge -> dominio.
        // Se conserva cargada tras la primera apertura (borradores y navegación).
        Loader {
            id: renditionsLoader
            anchors.fill: parent
            active: home.page === "rendiciones" || home.renditionsEverLoaded
            // Transición propia (no usa subAppProgress, que gobierna Calicatas y
            // su material): misma duración/easing corporativa y desplazamiento
            // corto. El Loader no se recrea: formularios y pila se conservan.
            visible: home.renditionsProgress > 0.001 && status === Loader.Ready
            enabled: home.page === "rendiciones"
            opacity: home.renditionsProgress
            transform: Translate { x: (1 - home.renditionsProgress) * 48 * home.u }
            sourceComponent: Component {
                Renditions.RenditionsApp {
                    ui: home
                    ctl: typeof RenditionsUi !== "undefined" ? RenditionsUi : null
                    active: home.page === "rendiciones"
                    navigationTransitionActive: home.renditionsProgress > 0.001 && home.renditionsProgress < 0.999
                                                || renditionsEnter.running || renditionsExit.running
                    dockMenuVisible: dockMenuBox.visible
                    haptics: typeof FlowHaptics !== "undefined" ? FlowHaptics : null
                    dockAnchor: dock
                    touchLayer: touchMenuHost                  // menús 3D Touch sobre el desenfoque
                    flow: CoreFlowModule.InGeCoreFlow          // motor único (geometría del teclado)
                    onRequestBack: home.page = "home"
                    onRequestOpenDrive: home.navigate("drive")
                    onRequestOpenProfile: home.navigate("profile")
                }
            }
            onStatusChanged: {
                if (status === Loader.Ready) {
                    home.renditionsEverLoaded = true
                    if (home.page === "rendiciones") home.runRenditionsTransition(true)
                } else if (status === Loader.Error) {
                    console.error("INGE_RENDITIONS_LOAD_ERROR renditions/RenditionsApp.qml")
                    home.page = "home"
                    home.notify("No se pudo abrir Rendiciones. Revisa el registro de la aplicación.")
                }
            }
        }
        PageFrame {
            ui: home
            shown: home.page === "drive"
            title: "InGe Drive"
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
    property bool renditionsEverLoaded: false
    property real renditionsProgress: 0
    function runRenditionsTransition(entering) {
        renditionsEnter.stop()
        renditionsExit.stop()
        if (reducedMotion) { renditionsProgress = entering ? 1 : 0; return }
        if (entering) renditionsEnter.restart()
        else if (renditionsProgress > 0) renditionsExit.restart()
    }
    NumberAnimation {
        id: renditionsEnter
        target: home; property: "renditionsProgress"; to: 1
        duration: 340; easing.type: Easing.OutCubic
    }
    NumberAnimation {
        id: renditionsExit
        target: home; property: "renditionsProgress"; to: 0
        duration: 260; easing.type: Easing.InOutCubic
    }
    Connections {
        target: home
        function onPageChanged() {
            if (home.page === "rendiciones") {
                // Primera apertura: espera a que el Loader esté listo (onStatusChanged).
                if (renditionsLoader.status === Loader.Ready) home.runRenditionsTransition(true)
            } else if (home.renditionsProgress > 0) {
                home.runRenditionsTransition(false)
            }
        }
    }
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
            home.calicatasMark("LOADER_START")
            setSource(Qt.resolvedUrl("pages/CalicatasEditorPage.qml"), {
                auth: (typeof auth !== "undefined" ? auth : null),
                flowMotionEnabled: !home.reducedMotion,
                flowReduceMotion: home.reducedMotion,
                gpsEnabled: false,
                // Estado de Calicatas: mismo `ui` y anclaje de Dock que Rendiciones.
                ui: home,
                dockAnchor: dock
            })
        }
        onStatusChanged: {
            if (status === Loader.Ready) {
                home.calicatasMark("LOADER_READY")
                home.calicatasEditorEverLoaded = true
                item.darkMode = Qt.binding(function() { return home.darkTheme })
                item.forceActiveFocus()
                if (home.calicatasEnterPendingFrom.length && home.page === "calicatas") {
                    var from = home.calicatasEnterPendingFrom
                    home.calicatasEnterPendingFrom = ""
                    Qt.callLater(function() { home.runSubAppTransition(true, from, "calicatas") })
                }
            } else if (status === Loader.Error) {
                console.error("INGE_CALICATAS_EDITOR_LOAD_ERROR pages/CalicatasEditorPage.qml")
                home.calicatasEnterPendingFrom = ""
                // Diferido: el error llega dentro de onActiveChanged -> setSource; cambiar
                // page ahí reevalúa `active` en plena notificación (binding loop).
                Qt.callLater(function() { home.page = "home" })
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
    property string calicatasEnterPendingFrom: ""      // primera apertura: espera al Loader listo
    // Marcas de apertura de Calicatas: ms desde INGE_CALICATAS_ENTER_REQUEST.
    property double calicatasEnterAt: 0
    property bool calicatasAwaitFirstFrame: false
    function calicatasMark(eventName) {
        console.info("INGE_CALICATAS_" + eventName + " t=" + (calicatasEnterAt > 0 ? Date.now() - calicatasEnterAt : -1))
    }
    Connections {
        target: home.Window.window
        enabled: home.calicatasAwaitFirstFrame
        ignoreUnknownSignals: true
        function onFrameSwapped() { home.calicatasAwaitFirstFrame = false; home.calicatasMark("FIRST_VISIBLE") }
    }
    property string previousPage: "home"
    property bool biometricEnrollPending: false
    property bool passwordResetPending: false
    readonly property var subAppPages: ["calicatas"]
    function runSubAppTransition(entering, from, to) {
        console.info("INGE_NAV_TRANSITION_START from=" + from + " to=" + to)
        if (entering && to === "calicatas") { home.calicatasMark("ANIMATION_START"); home.calicatasAwaitFirstFrame = true }
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
        if (entering && page === "calicatas") home.calicatasMark("ANIMATION_END")
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
            if (isSub && !wasSub) {
                home.calicatasEnterAt = Date.now()
                home.calicatasMark("ENTER_REQUEST loaded=" + (calicatasEditor.status === Loader.Ready))
                // Como Rendiciones: la entrada empieza con la página ya cargada. La
                // primera carga del editor es síncrona; animar antes la dejaría
                // saltar al final en el primer fotograma visible.
                if (calicatasEditor.status === Loader.Ready) home.runSubAppTransition(true, from, home.page)
                else home.calicatasEnterPendingFrom = from
            }
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
    // UX 5.0: DockContextController admite 8 nodos raíz (kMaxActions), 10 hijos y
    // 3 niveles. El Dock muestra los tres primeros por prioridad (Acercar,
    // Alejar, Restablecer vista) y "···" agrupa todo lo que antes vivía en las
    // barras propias del visor: Buscar, Lugares, Archivos, Info y Herramientas.
    readonly property var earthDockPreset: [
        {id: "earth.zoomIn", label: "Acercar", icon: "earth.zoomIn", command: "earth.zoomIn", enabled: earthDockReady, priority: 1},
        {id: "earth.zoomOut", label: "Alejar", icon: "earth.zoomOut", command: "earth.zoomOut", enabled: earthDockReady, priority: 2},
        {id: "earth.reset", label: "Restablecer vista", icon: "earth.rotateLeft", command: "earth.reset", enabled: earthDockReady, priority: 3},
        {id: "earth.search", label: "Buscar lugares y coordenadas", icon: "earth.search", command: "earth.search", priority: 4},
        {id: "earth.places", label: "Lugares guardados", icon: "earth.place", command: "earth.savedPlaces", priority: 5, children: [
            {id: "earth.southAmerica", label: "Sudamérica", icon: "earth.globe", command: "earth.southAmerica", enabled: earthDockReady},
            {id: "earth.peru", label: "Perú", icon: "earth.place", command: "earth.peru", enabled: earthDockReady},
            {id: "earth.lima", label: "Lima", icon: "earth.place", command: "earth.lima", enabled: earthDockReady}
        ]},
        {id: "earth.files", label: "Archivos KML / KMZ", icon: "earth.files", command: "earth.files", priority: 6, children: [
            {id: "earth.filesImport", label: "Importar KML / KMZ", icon: "earth.import", command: "earth.filesImport"},
            {id: "earth.driveOpen", label: "Abrir desde InGeDrive", icon: "earth.drive", command: "earth.driveOpen"},
            {id: "earth.driveSave", label: "Guardar en InGeDrive", icon: "earth.export", command: "earth.driveSave"},
            {id: "earth.export", label: "Exportar KML / KMZ", icon: "earth.export", command: "earth.export"}
        ]},
        {id: "earth.diagnostics", label: "Información geográfica", icon: "earth.info", command: "earth.diagnostics", priority: 7},
        {id: "earth.tools", label: "Herramientas", icon: "earth.tools", command: "", priority: 8, children: [
            {id: "earth.measure", label: "Medir distancia", icon: "earth.measure", command: "earth.measure"},
            {id: "earth.source", label: "Fuentes y capas", icon: "earth.layers", command: "earth.source"},
            {id: "earth.gps", label: "Mi ubicación GPS", icon: "earth.gps", command: "earth.gps"},
            {id: "earth.rotate", label: "Girar planeta", icon: "earth.rotate", command: "", children: [
                {id: "earth.rotateLeft", label: "Girar a la izquierda", icon: "earth.rotateLeft", command: "earth.rotateLeft", enabled: earthDockReady},
                {id: "earth.rotateRight", label: "Girar a la derecha", icon: "earth.rotate", command: "earth.rotateRight", enabled: earthDockReady},
                {id: "earth.tiltUp", label: "Mover vista al norte", icon: "earth.rotate", command: "earth.tiltUp", enabled: earthDockReady},
                {id: "earth.tiltDown", label: "Mover vista al sur", icon: "earth.rotate", command: "earth.tiltDown", enabled: earthDockReady},
                {id: "earth.north", label: "Orientar al norte", icon: "earth.compass", command: "earth.north", enabled: earthDockReady}
            ]},
            {id: "earth.pan", label: "Desplazar", icon: "earth.pan", command: "", children: [
                {id: "earth.panLeft", label: "Izquierda", icon: "earth.pan", command: "earth.panLeft", enabled: earthDockReady},
                {id: "earth.panRight", label: "Derecha", icon: "earth.pan", command: "earth.panRight", enabled: earthDockReady},
                {id: "earth.panUp", label: "Adelante", icon: "earth.pan", command: "earth.forward", enabled: earthDockReady},
                {id: "earth.panDown", label: "Atrás", icon: "earth.pan", command: "earth.backward", enabled: earthDockReady}
            ]},
            {id: "earth.navigation", label: "Modo navegación", icon: "earth.compass", command: "earth.navigation", selected: earthDockNavigation},
            {id: "earth.coordinates", label: "Mostrar coordenadas", icon: "earth.globe", command: "earth.coordinates", selected: earthCoordinatesShown}
        ]}
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
                if (name === "earth.diagnostics" && earthNativeLoader.item) earthNativeLoader.item.showSheet("info")
                else if (name === "earth.coordinates") { home.earthCoordinatesShown = !home.earthCoordinatesShown; home.publishEarthDock() }
                else if ((name === "earth.search" || name === "earth.goTo") && earthNativeLoader.item) earthNativeLoader.item.showSheet("search")
                else if (earthNativeLoader.item && (name === "earth.filesImport" || name === "earth.driveOpen" || name === "earth.driveSave" || name === "earth.export"))
                    earthNativeLoader.item.openFiles(({"earth.filesImport": "import", "earth.driveOpen": "drive",
                                                       "earth.driveSave": "save", "earth.export": "export"})[name])
                else if (name === "earth.source" && earthNativeLoader.item) earthNativeLoader.item.showSheet("layers")
                else if (earthNativeLoader.item && (name === "earth.files" || name === "earth.measure" || name === "earth.savedPlaces")) earthNativeLoader.item.showSheet(name === "earth.savedPlaces" ? "places" : name.substring(6))
                else if (name === "earth.gps" && earthNativeLoader.item) earthNativeLoader.item.requestGps()
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
    // Contexto temporal (InGeCoreFlow.dockOverride, p. ej. mapa de Ubicación): el
    // Dock real muestra sus acciones (en vertical si lo pide) hasta que vuelve a null.
    readonly property var dockOverride: CoreFlowModule.InGeCoreFlow.dockOverride || null
    readonly property bool dockVertical: dockOverride !== null && dockOverride.vertical === true
                                         && page === "calicatas"
    // Únicamente para el contexto vertical del mapa: icono y etiqueta
    // como la referencia aprobada. El Dock horizontal conserva sus medidas.
    // Contexto del mapa: cápsula estilizada, no el Dock horizontal.
    // Ancho 60u (antes 76u) y celdas más compactas con icono+etiqueta.
    readonly property real dockVCellWidth: 60 * u
    readonly property real dockVCellHeight: 65 * u
    // Al entrar o salir del contexto temporal, el Dock se rehace EXACTO desde su
    // contexto (sin pulsación ni menú colgados de la otra disposición).
    onDockOverrideChanged: {
        dockPath = []
        // No destruir los delegados durante el tap. El onReleased/onClicked
        // debe finalizar primero; onDockPressActiveChanged actualizará slots.
        if (!dockPressActive)
            dockDisplayedSlots = dockSlots
    }
    readonly property var dockActions: {
        if (dockOverride && page === "calicatas")
            return (dockOverride.actions || []).filter(function(a) { return a.visible !== false })
        if (!dockCtx || dockCtx.ownerId !== dockOwner)
            return []
        return (dockCtx.actions || []).filter(function(a) { return a.visible !== false })
    }
    Binding {
        target: home.dockCtx
        property: "foregroundOwner"
        value: home.dockForeground ? "calicatas"
             : (home.page === "earth" ? "earth" : (home.page === "rendiciones" ? "rendiciones" : ""))
        when: home.dockCtx !== null
    }

    // Presets: el diseño no cambia; solo las herramientas.
    readonly property var homeDockPreset: [
        { key: "home", glyph: 0xE0F5, page: "home", name: "Inicio" },
        { key: "addTools", glyph: 0xE173, name: "Agregar herramientas" },
        { key: "settings", glyph: 0xE154, page: "settings", name: "Ajustes" }
    ]
    readonly property string dockOwner: page === "earth" ? "earth" : (page === "rendiciones" ? "rendiciones" : "calicatas")
    readonly property string dockMode: (page === "calicatas" || page === "earth" || page === "rendiciones") && dockActions.length > 0
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
    readonly property var dockMoreNode: ({ id: "__more", label: dockOwner === "rendiciones" ? "Herramientas" : "Más herramientas", enabled: dockSecondary.length > 0,
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
    // No cambiar el modelo del Repeater durante un press: incluso asignarle
    // un snapshot idéntico puede recrear el delegado y perder onClicked.
    // Las acciones reales siguen validándose en dockDispatch (incluido Deep Press).
    property bool dockPressActive: false
    // Sin binding: QML no debe recomputar este modelo durante una pulsación,
    // porque destruiría el delegado MouseArea antes de recibir onClicked.
    property var dockDisplayedSlots: []
    onDockSlotsChanged: if (!dockPressActive) dockDisplayedSlots = dockSlots
    onDockPressActiveChanged: if (!dockPressActive) dockDisplayedSlots = dockSlots
    function dockFinishPress() { dockPressActive = false }
    // Layout contextual amplio: solo Android tablet o plegable DESPLEGADO.
    // El lado menor del display >= 600 dp es el mismo umbral de la ficha
    // Calicatas. Se mide en Screen, no en el viewport que reduce el teclado;
    // al plegarse la pantalla vuelve automáticamente al dock de teléfono.
    readonly property bool expandedContextDock: Qt.platform.os === "android"
        && Screen.width > 0 && Screen.height > 0
        && Math.min(Screen.width, Screen.height) >= 600
        && dockMode === "subapp"
    // Compacto y centrado: el vidrio ya no sobresale de los márgenes
    // de la barra de referencia. Limitar el ancho también en multiventana.
    readonly property real expandedDockGroupWidth: Math.min(420 * u, Math.max(0, width - 2 * gutter))
    readonly property real expandedDockPlusGap: 12 * u
    readonly property real expandedDockPlusWidth: 62 * u
    readonly property real dockIconSize: expandedContextDock ? 32 * u
        : dockDisplayedSlots.length >= 4 ? 36 * u : 42 * u
    readonly property real dockCellWidth: expandedContextDock
        ? (expandedDockGroupWidth - expandedDockPlusWidth - expandedDockPlusGap - 16 * u
           - Math.max(0, dockDisplayedSlots.length - 1)) / Math.max(1, dockDisplayedSlots.length)
        : dockIconSize + 20 * u
    readonly property real dockCapsuleWidth: Math.max(1, dockDisplayedSlots.length) * dockCellWidth
                                             + Math.max(0, dockDisplayedSlots.length - 1) + 16 * u
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
        if (dockMenu.id !== "__more" && own.length > 0 && dockMenu.tapCommand !== true
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
        // Menú "···" de InGe Earth (glifos Lucide de la misma fuente del Dock).
        "earth.search": 0xE151, "earth.place": 0xE111, "earth.globe": 0xE0E8,
        "earth.files": 0xE247, "earth.import": 0xE0B2, "earth.drive": 0xE0ED,
        "earth.export": 0xE19E, "earth.info": 0xE0F9, "earth.tools": 0xE1B1,
        "earth.measure": 0xE14B, "earth.layers": 0xE529, "earth.gps": 0xE1DB,
        "earth.compass": 0xE09B,

        "documents.file": 0xE0CC, "documents.folder": 0xE0D7, "documents.open": 0xE247,
        "documents.template": 0xE207, "profile.user": 0xE617, "map.location": 0xE1DB,
        "nav.map": 0xE111, "nav.earth": 0xE1F3, "action.addStratum": 0xE529,
        "action.add": 0xE13D, "action.insert": 0xE592, "action.copy": 0xE09E,
        "action.menu": 0xE37D, "action.edit": 0xE1D0, "action.check": 0xE06C,
        "action.export": 0xE32A, "action.camera": 0xE064, "lab.flask": 0xE0D5,
        "module.stratigraphy": 0xE2A3, "system.forward": 0xE06F, "system.back": 0xE06E,
        "status.sync": 0xE145, "documents.image": 0xE0F6, "calgen.history": 0xE1F5, "calgen.close": 0xE1B2, "calgen.attach": 0xE12D, "archive.item": 0xE041, "action.save": 0xE14D, "action.more": 0xE0B6,
        // Rendiciones: barras ascendentes, más, carpeta.
        "renditions.balance": 0xE06A, "renditions.create": 0xE13D, "renditions.folder": 0xE0D7,
        // Herramientas de Nuevo gasto y diagnóstico (glifos Lucide de la misma fuente).
        // (iconografía de los previews aprobados: square-check, list, refresh-cw...)
        "renditions.today": 0xE063, "renditions.period": 0xE16A, "renditions.reuse": 0xE1F5,
        "renditions.requirements": 0xE16A, "renditions.noReceipt": 0xE0C6, "renditions.help": 0xE082,
        "renditions.calculator": 0xE1BC, "renditions.validate": 0xE16A, "renditions.breakdown": 0xE106,
        "renditions.attachments": 0xE0F6, "renditions.replace": 0xE145, "renditions.retry": 0xE19E,
        "renditions.status": 0xE193, "renditions.trash": 0xE18E, "renditions.ai": 0xE412,
        "renditions.exit": 0xE1B2,
        // Navegación de Nuevo gasto: arrow-left, arrow-right, home, log-out, circle-x, list, refresh-cw.
        "renditions.arrowBack": 0xE048, "renditions.forward": 0xE049, "renditions.home": 0xE0F5,
        "renditions.logout": 0xE10E, "renditions.cancel": 0xE084, "renditions.list": 0xE106,
        "renditions.recover": 0xE145,
        // Rendición abierta: buscar (search), información (info), actividad (clock).
        "renditions.search": 0xE151, "renditions.info": 0xE0F9, "renditions.activity": 0xE087
    })
    function dockGlyph(action) {
        if (action.glyph !== undefined) return action.glyph   // contexto temporal: glifo explícito
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
    function dockActiveDetailId() {
        var subapp = renditionsLoader.item
        return page === "rendiciones" && subapp && subapp.detailPage
               ? String(subapp.detailPage.localId || "") : ""
    }
    function dockDispatch(action, generation, pressedOwner, pressedContext, pressedDetailId) {
        if (dockOverride && page === "calicatas") { // mapa fullscreen: el Dock real
            if (typeof dockOverride.command !== "function") {
                console.warn("INGE_CALICATA_MAP_DOCK_ERROR reason=missing_override_handler action=" + action.id)
                dockHaptic("error")
                return
            }
            console.info("INGE_CALICATA_MAP_DOCK_DISPATCH action=" + action.id
                         + " command=" + String(action.command || ""))
            dockOverride.command(String(action.id))
            dockHaptic("success")
            return
        }
        if (!dockRouter || !dockCtx) {
            console.warn("INGE_DOCK_INTEGRATION_ERROR router-unavailable action=" + action.id)
            notify("Error de integración del dock: acción no disponible.")
            dockHaptic("error")
            return
        }
        // La ficha puede republicar sus acciones entre press/release (gastos cargados,
        // permisos, sincronización). Sólo un tapCommand conserva su toque si sigue
        // siendo la MISMA acción habilitada en el MISMO contexto activo.
        // No se aplica al Deep Press ni a saltos entre páginas/propietarios.
        if (action.tapCommand === true && generation !== dockGeneration
                && pressedOwner !== undefined && pressedContext !== undefined
                && !dockCtx.transitionPending
                && dockCtx.ownerId === pressedOwner && dockCtx.contextId === pressedContext
                && (pressedContext !== "rendiciones/detail"
                    || (pressedDetailId && pressedDetailId === dockActiveDetailId()))) {
            for (var i = 0; i < dockActions.length; ++i) {
                var live = dockActions[i]
                if (live.id === action.id && live.command === action.command
                        && live.enabled !== false && live.visible !== false) {
                    generation = dockGeneration
                    break
                }
            }
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
    function dockSlotTap(slot, pressGeneration, anchorItem, pressedOwner, pressedContext, pressedDetailId) {
        if (!slot.action) {
            if (!consumeEditTap()) {
                if (slot.key === "addTools") openAdd()
                else navigate(slot.page)
            }
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
        // tapCommand (opt-in de la subapp): el toque ejecuta la acción principal y
        // sus subfunciones quedan en el Deep Press (380 ms). Sin la marca: igual que antes.
        if (dockChildren(a).length > 0 && !(a.tapCommand === true && String(a.command || "").length > 0)) {
            if (pressGeneration === dockGeneration)
                dockOpenMenu(slot.key, anchorItem, false)
        } else if (a.command && String(a.command).length > 0) {
            dockDispatch(a, pressGeneration, pressedOwner, pressedContext, pressedDetailId)
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
    // Menús 3D Touch compactos (estilo iOS): filas finas, cabecera corta.
    readonly property real dockMenuHeaderHeight: 34 * u
    readonly property real dockMenuRowHeight: 44 * u

    property real dockSwapFade: 1
    SequentialAnimation {
        id: dockSwap
        NumberAnimation { target: home; property: "dockSwapFade"; to: 0.4; duration: 90; easing.type: Easing.OutQuad }
        NumberAnimation { target: home; property: "dockSwapFade"; to: 1.0; duration: 200; easing.type: Easing.OutCubic }
    }

    // ======================= Liquid Glass del Dock Contextual (motor ÚNICO)
    // El Dock global es el único dueño de su material. Las subapps sólo
    // publican acciones y, de forma pasiva, su contenido visual; ninguna
    // decide color, transparencia, óptica, respaldo ni calidad.
    //  1. FUENTE (una por pantalla, elegida aquí):
    //       Home y páginas del Home -> contenido real del Home (homeContent)
    //       Calicatas               -> editor (calicatasEditor)
    //       InGe Earth              -> vista del globo (earthNativeLoader)
    //       Rendiciones             -> subapp completa (renditionsLoader)
    //     UNA ShaderEffectSource (dockBackdropCapture) captura sólo la franja
    //     inferior detrás de la cápsula, el botón InGe IA y el Quick Bubble.
    //     El Dock vive fuera de esas fuentes: sin captura recursiva.
    //  2. MATERIAL: mismo shader (glass.frag) y mismo preset en las tres
    //     superficies (dockGlass* abajo); el color sólo varía con el fondo real.
    //  3. RENDIMIENTO (GraphicsCore.deviceTier, automático): la óptica es la
    //     misma en todas las gamas; sólo baja la resolución de la captura
    //     (completa HIGH, 1/2 MEDIUM_HIGH, 1/3 media, 1/5 baja, 1/7 ultra baja).
    //     El esmerilado lo hace el shader (5 muestras sobre mipmaps): sin pasadas
    //     de blur. HIGH y MEDIUM_HIGH capturan en vivo también en transiciones
    //     y con el menú abierto; la captura se detiene con el Dock oculto o la
    //     app en segundo plano.
    //  4. RESPALDO ÚNICO (DockGlassPanel/GlassSurface): en LOW o mientras la fuente de una
    //     subapp aún no está lista; cristal neutro claro, igual en todas.
    readonly property bool dockLowCostGlass: GraphicsCore.deviceTier === "LOW"
                                             || GraphicsCore.deviceTier === "ULTRA_LOW"
    // Gama alta: el vidrio sigue en vivo durante el paso Home -> mapa, las
    // transiciones de subapp y con el menú abierto. En LOW la captura se congela.
    readonly property bool dockLiveGlass: GraphicsCore.deviceTier === "HIGH"
                                          || GraphicsCore.deviceTier === "MEDIUM_HIGH"
    // Mientras el mapa o Rendiciones entran sobre el Home se captura homeContent
    // (los contiene a ambos): el vidrio ve la mezcla real del fundido.
    readonly property bool dockBackdropBlending: dockLiveGlass && homeContent.visible
        && ((page === "earth" && (earthNativeLoader.status !== Loader.Ready || earthNativeLoader.opacity < 0.999))
            || (renditionsProgress > 0.001 && renditionsProgress < 0.999))
    // Calicatas (subAppProgress) conserva su transición; ya no gobierna el material.
    readonly property bool subAppGlassActive: subAppProgress > 0.001
    // Home y sus páginas: el contenido REAL del Home (foto con su degradado de
    // legibilidad, tarjetas y saludo), no sólo la foto desenfocada. Si
    // homeContent está oculto (desenfoque del panel Agregar), se usa la foto.
    readonly property Item dockBackdropSource: dockBackdropBlending ? homeContent
                                             : page === "calicatas" && calicatasEditor.status === Loader.Ready ? calicatasEditor
                                             : page === "earth" && earthNativeLoader.status === Loader.Ready && earthNativeLoader.item ? earthNativeLoader.item.glassBackdropItem
                                             : page === "rendiciones" && renditionsLoader.status === Loader.Ready ? renditionsLoader
                                             : page !== "calicatas" && page !== "earth" && page !== "rendiciones" && homeContent.visible
                                               ? homeContent
                                             : null
    // Expose the producer before its first render: waiting for completion here
    // hides every consumer that would cause Qt to render the captured texture.
    readonly property bool dockBackdropReady: dockBackdropSource !== null && dockBackdropSource.width > 0 && dockBackdropSource.height > 0
    readonly property bool dockGlassFallback: (page === "calicatas" || page === "earth" || page === "rendiciones")
                                              && !dockBackdropReady
    readonly property color earthGlassTint: Qt.rgba(10 / 255, 14 / 255, 20 / 255, 0.20)   // controles laterales de Earth
    // Preset óptico ÚNICO de la cápsula, el botón InGe IA y el Quick Bubble.
    // Cristal BLANCO transparente: tinte blanco de opacidad muy baja (la
    // transparencia la da el muestreo del fondo real), sin velo oscuro.
    // Legibilidad ÚNICA del Dock compartido (cápsula, InGe IA y Quick Bubble en
    // Home, Calicatas, Rendiciones, InGeDrive y Earth): el cristal blanco puro no
    // separaba los glifos blancos de fondos claros ni de fotos con detalle. Un
    // velo azul marino corporativo bajo (#151A30 al 22 %) da contraste en fondos
    // claros y apenas cambia los oscuros; sigue siendo vidrio con refracción.
    // Halloween: velo morado leve. RStyle.glass(0.98) era casi opaco (blanco en
    // claro, morado al 74 % en oscuro) y la lente lo mezclaba encima del fondo.
    readonly property color dockGlassTint: appSkin === "ingenieros" ? Qt.rgba(1,0.65,0.82,0.08) : appSkin === "halloween" ? Qt.rgba(107 / 255, 47 / 255, 160 / 255, 0.16) : Qt.rgba(0, 0, 0, 0)   // vidrio transparente
    readonly property real dockGlassRefraction: dockLowCostGlass || reducedMotion ? 0 : 21 * u   // refractPx adaptativo (58 dp)
    readonly property real dockGlassSpecular: 1.8            // >= 0,95 activa la lente; filo grueso como 15.png
    readonly property real dockGlassBevel: 17 * u            // bisel adaptativo: 0,3 × 58 dp
    readonly property real dockGlassContrast: 0              // sin «smoked»: era la película gris
    readonly property color dockGlassEdge: appSkin === "halloween" ? Qt.rgba(1, 150 / 255, 50 / 255, 0.40) : darkTheme ? Qt.rgba(1, 1, 1, 0.22) : Qt.rgba(1, 1, 1, 0.55)       // bisel luminoso blanco
    readonly property real dockGlassShadowAlpha: 0.22                   // separación del fondo
    // Legibilidad sin oscurecer el cristal: contorno muy fino de los glifos y
    // textos blancos del Dock (se dibuja con el propio texto, sin pasadas GPU).
    readonly property color dockGlyphOutline: Qt.rgba(21 / 255, 26 / 255, 48 / 255, 0.95)   // legibilidad con tinte al 9 %
    readonly property color dockSeparatorColor: Qt.rgba(130 / 255, 140 / 255, 160 / 255, 0.55)
    // Difuminado leve (2 u) que oculta el mosaico de la captura reducida; en LOW, 0
    // (sin mipmaps ni esmerilado). No toca refracción, filo ni tinte.
    readonly property real dockGlassFrost: dockLowCostGlass ? 0 : 2 * u
    readonly property var dockGlassUi: dockBackdropSource !== null ? dockBackdrop : home
    // Material Liquid Glass de las tarjetas de una subapp (lo publica la subapp: su fondo vivo).
    property var cardGlassUi: null
    // Liquid Glass OFICIAL para toda la app (GlassSurface.material): el preset del
    // Dock. Claro = Dock; oscuro = tinte negro sutil (12 %). LOW = respaldo neutro.
    readonly property QtObject liquidGlassMaterial: QtObject {
        readonly property color tint: home.darkTheme && home.appSkin !== "halloween" && home.appSkin !== "ingenieros" ? Qt.rgba(0, 0, 0, 0.12) : home.dockGlassTint
        readonly property color edge: home.dockGlassEdge
        readonly property real refraction: home.dockGlassRefraction
        readonly property real specular: home.dockGlassSpecular
        readonly property real bevel: home.dockGlassBevel
        readonly property real contrast: home.dockGlassContrast
        readonly property real frost: home.dockGlassFrost
        readonly property real shadowAlpha: home.dockGlassShadowAlpha
        readonly property bool fallback: home.dockLowCostGlass
        readonly property color fallbackEdge: home.darkTheme ? Qt.rgba(1, 1, 1, 0.16) : Qt.rgba(1, 1, 1, 0.45)
        readonly property color fallbackTop: home.darkTheme ? Qt.rgba(1, 1, 1, 0.12) : Qt.rgba(1, 1, 1, 0.34)
        readonly property color fallbackMid: home.darkTheme ? Qt.rgba(1, 1, 1, 0.06) : Qt.rgba(1, 1, 1, 0.18)
        readonly property color fallbackBottom: home.darkTheme ? Qt.rgba(1, 1, 1, 0.08) : Qt.rgba(1, 1, 1, 0.24)
    }
    Item {
        id: dockBackdrop
        readonly property real band: home.dockVertical ? home.height : Math.min(home.height, home.dockArea + 440 * home.u)
        x: 0
        y: home.height - band
        width: home.width
        height: band
        readonly property Item backdrop: dockBackdrop
        readonly property bool glassReady: home.dockBackdropReady
        readonly property var glassTexture: home.dockBackdropReady ? dockBackdropCapture : null
        readonly property int glassTick: home.glassTick + Math.round(y + height)
        ShaderEffectSource {
            id: dockBackdropCapture
            readonly property bool captureAllowed: home.dockBackdropSource !== null && home.visible
                && dock.visible && Qt.application.state === Qt.ApplicationActive
                && (home.dockLiveGlass || !dockMenuBox.visible) && !Qt.inputMethod.visible && !Qt.inputMethod.animating
                && (home.dockLiveGlass || !(home.renditionsProgress > 0.001 && home.renditionsProgress < 0.999))
                // Calicatas: en vivo durante lista <-> mapa en HIGH/MEDIUM_HIGH; congelada en LOW.
                && (home.dockLiveGlass || home.page !== "calicatas" || !calicatasEditor.item
                    || calicatasEditor.item.homeSliding !== true)
                && !((home.page === "rendiciones" || home.renditionsProgress > 0.001)
                     && renditionsLoader.item && renditionsLoader.item.renderCaptureBlocked === true)
            onSourceItemChanged: {
                if (captureAllowed) Qt.callLater(captureIfAllowed)
            }
            onCaptureAllowedChanged: if (captureAllowed) Qt.callLater(captureIfAllowed)
            function captureIfAllowed() { if (captureAllowed && sourceItem) scheduleUpdate() }
            width: dockBackdrop.width
            height: dockBackdrop.height
            sourceItem: home.dockBackdropSource
            // Las fuentes ocupan toda la pantalla desde (0,0): la franja coincide
            // con la posición real de la cápsula, el botón IA y el Quick Bubble.
            sourceRect: Qt.rect(0, dockBackdrop.y, dockBackdrop.width, dockBackdrop.height)
            live: captureAllowed
            hideSource: false
            visible: false
            smooth: true
            // Mipmaps: el shader esmerila leyendo un nivel reducido (sin mosaico).
            mipmap: !home.dockLowCostGlass
            // HIGH captura a resolución completa; LOW y ULTRA_LOW, versión ligera.
            readonly property real divisor: GraphicsCore.deviceTier === "HIGH" ? 1
                                          : GraphicsCore.deviceTier === "MEDIUM_HIGH" ? 2
                                          : GraphicsCore.deviceTier === "ULTRA_LOW" ? 7
                                          : home.dockLowCostGlass ? 5 : 3
            textureSize: Qt.size(Math.max(1, Math.round(width / divisor)), Math.max(1, Math.round(height / divisor)))
        }
    }


    // Dock contextual = superposición sobre la interfaz que lo invocó.
    // Sin scrim ni fondo opaco a pantalla completa: el DockGlassPanel
    // refracta directamente el contenido activo capturado por dockBackdrop.
    // El toque exterior sigue cerrando el Quick Bubble sin ejecutar acciones.
    MouseArea {
        z: 61
        anchors.fill: parent
        visible: dockMenuBox.open
        onClicked: home.dockPath = []
    }
    // Quick Bubble: subfunciones de la herramienta, sobre el dock.
    Rectangle {
        id: dockMenuBox
        Image {
            visible: home.appSkin === "halloween"
            anchors.right: parent.right; anchors.top: parent.top; anchors.margins: 8 * home.u
            width: 24 * home.u; height: width; z: 2
            source: visible ? "qrc:/images/halloween/bat.svg" : ""; sourceSize: Qt.size(48, 48)
            enabled: false; opacity: 0.7
        }
        z: 65
        readonly property bool open: dock.visible && home.dockMode === "subapp" && home.dockMenu !== null
        property real shown: open ? 1 : 0
        Behavior on shown {
            NumberAnimation {
                // Hero (vista emparejada cápsula -> panel): .standard y optimizedDurationTo
                // con el desplazamiento + cambio de tamaño reales.
                duration: home.reducedMotion ? 0
                          : home.heroMotion ? home.heroMotion.duration(Math.abs(dockMenuBox.targetW - dock.width)
                                                                       + Math.abs(dockMenuBox.targetH - dock.height) + dockMenuBox.dockLift)
                          : (dockMenuBox.open ? 260 : 160)
                easing.type: home.heroMotion ? Easing.BezierSpline : dockMenuBox.open ? Easing.OutBack : Easing.InCubic
                easing.bezierCurve: home.heroMotion ? home.heroMotion.standard : []
                easing.overshoot: 1.15                // asentamiento elástico moderado
            }
        }
        visible: shown > 0.01
        // Desvanecimiento solo al final del cierre; el vidrio se estira desde la cápsula.
        opacity: Math.min(1, shown * 2.5)
        onShownChanged: home.glassTick++
        // Panel final: nace de la cápsula y se eleva por encima del Dock (sin franja
        // inferior reservada: el 3D Touch sobre el Dock sigue sin elegir nada).
        readonly property real dockLift: dock.height + 8 * home.u
        readonly property real targetW: Math.min(312 * home.u, home.width - 2 * home.gutter)
        readonly property real targetH: Math.max(0, Math.min(dockMenuColumn.implicitHeight + 12 * home.u,
                                                             dock.y - 8 * home.u - home.topInset - 20 * home.u))
        readonly property real targetX: Math.max(home.gutter, Math.min(home.width - home.gutter - targetW, home.dockMenuAnchorX - targetW / 2))
        readonly property real morph: Math.max(0, Math.min(1.06, shown))
        width: dock.width + (targetW - dock.width) * morph
        height: dock.height + (targetH - dock.height) * morph
        x: dock.x + (targetX - dock.x) * morph
        y: dock.y + dock.height - height - dockLift * Math.min(1, morph)
        radius: dock.height / 2 + (20 * home.u - dock.height / 2) * Math.min(1, morph)
        color: "transparent"
        onXChanged: home.glassTick++
        onYChanged: home.glassTick++
        DockGlassPanel { glassUi: home.dockGlassUi; radius: dockMenuBox.radius; u: home.u; tint: home.dockGlassTint; lowFallback: false
                         reducedMotion: home.reducedMotion; gel: 4 * Math.min(1, dockMenuBox.shown) * (1 - Math.min(1, dockMenuBox.shown)) }   // «Extrema»: gel
        MouseArea { anchors.fill: parent }
        Flickable {
            anchors.fill: parent
            clip: true
            // La lista aparece cuando el vidrio ya se estiró; al cerrar se desenfoca
            // (sin blur en tier LOW: solo desvanecimiento).
            opacity: Math.max(0, Math.min(1, (dockMenuBox.shown - 0.45) / 0.55))
            layer.enabled: !home.dockLowCostGlass && !home.reducedMotion && dockMenuBox.shown > 0.02 && dockMenuBox.shown < 0.98
            layer.effect: MultiEffect { blurEnabled: true; blurMax: 24; blur: Math.max(0, 1 - dockMenuBox.shown) }
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
                        style: Text.Outline; styleColor: home.dockGlyphOutline
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
                            style: Text.Outline; styleColor: home.dockGlyphOutline
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
                            style: Text.Outline; styleColor: home.dockGlyphOutline
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
                            style: Text.Outline; styleColor: home.dockGlyphOutline
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
        opacity: (home.optionsSheetOpen ? 0.12 : 0.42) * home.overlayLevel
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
        // Vidrio del Dock (preset único; en LOW, su respaldo) con el velo de legibilidad
        // del Dock (#151A30 al 22 %) para los textos blancos.
        DockGlassPanel { glassUi: home; radius: 26 * home.u; u: home.u; tint: home.dockGlassTint
                         reducedMotion: home.reducedMotion; gel: 4 * Math.min(1, home.sheetGrow) * (1 - Math.min(1, home.sheetGrow)) }
        Rectangle { anchors.fill: parent; radius: parent.radius; color: Qt.rgba(21 / 255, 26 / 255, 48 / 255, 0.22) }
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
        blurEnabled: home.liquidGlass
        blurMax: 64
        blur: Math.max(home.blurAmount, home.overlayBlurLevel)   // 3D Touch: desenfoque marcado
        visible: home.blurAmount > 0.001 || home.overlayBlurLevel > 0.001
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
        z: home.subAppProgress > 0.001 ? 66 : 0          // sobre la subapp y su Dock
        visible: home.addOpen
        x: 10 * home.u
        width: home.width - 20 * home.u
        y: home.topInset + 8 * home.u + (1 - home.panelProgress) * 60 * home.u
        height: home.height - y - home.dockArea + 6 * home.u
        radius: 30 * home.u
        opacity: Math.min(1, home.panelProgress * 1.4)
        scale: 0.55 + 0.45 * home.panelProgress
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
    readonly property real dockHeight: (expandedContextDock ? 58 : 64) * u // Compacto solo en tablet/plegable abierto
    readonly property real dockBottom: 22 * u        // flota sobre el borde inferior
    readonly property real dockArea: dockHeight + dockBottom + 22 * u

    // ============================ Dock global (único componente visual)
    // Diseño aprobado del Home V2 (cápsula de 232 dp, celdas, separadores,
    // glifos Lucide, GlassSurface). Cada subapp aporta solo su preset.
    // Solo iconos: los nombres viven en el menú y en la accesibilidad.
    // ---- «Extrema»: el mosaico tocado crece con su vidrio hasta la pantalla (Hero,
    // vista emparejada: .standard + optimizedDurationTo) y se funde en la app; al
    // volver, el vidrio se encoge hacia su mosaico.
    Item {
        id: heroZoom
        z: 63
        enabled: false
        property real t: 0                       // 0 = mosaico, 1 = pantalla completa
        property real fade: 0
        visible: fade > 0.001
        opacity: fade
        x: home.heroOrigin.x * (1 - t)
        y: home.heroOrigin.y * (1 - t)
        width: home.heroOrigin.width + (home.width - home.heroOrigin.width) * t
        height: home.heroOrigin.height + (home.height - home.heroOrigin.height) * t
        readonly property real radius: home.heroOriginRadius * (1 - t)
        readonly property int travel: home.heroCurves.duration(home.heroOrigin.x + home.heroOrigin.y
                                                               + (home.width - home.heroOrigin.width)
                                                               + (home.height - home.heroOrigin.height))
        onXChanged: home.glassTick++
        onWidthChanged: home.glassTick++
        DockGlassPanel { glassUi: home; radius: heroZoom.radius; u: home.u; tint: home.dockGlassTint; lowFallback: false
                         reducedMotion: home.reducedMotion; gel: 4 * heroZoom.t * (1 - heroZoom.t) }
        function run(opening) {
            heroOpen.stop(); heroClose.stop()
            if (opening) heroOpen.start(); else heroClose.start()
        }
        SequentialAnimation {
            id: heroOpen
            ScriptAction { script: { heroZoom.t = 0; heroZoom.fade = 1 } }
            NumberAnimation { target: heroZoom; property: "t"; to: 1; duration: heroZoom.travel
                              easing.type: Easing.BezierSpline; easing.bezierCurve: home.heroCurves.standard }
            NumberAnimation { target: heroZoom; property: "fade"; to: 0; duration: 180
                              easing.type: Easing.BezierSpline; easing.bezierCurve: home.heroCurves.acceleration }
        }
        SequentialAnimation {
            id: heroClose
            ScriptAction { script: { heroZoom.t = 1; heroZoom.fade = 1 } }
            NumberAnimation { target: heroZoom; property: "t"; to: 0; duration: heroZoom.travel
                              easing.type: Easing.BezierSpline; easing.bezierCurve: home.heroCurves.standard }
            NumberAnimation { target: heroZoom; property: "fade"; to: 0; duration: 160
                              easing.type: Easing.BezierSpline; easing.bezierCurve: home.heroCurves.acceleration }
        }
    }
    Rectangle {
        id: dock
        z: home.subAppProgress > 0.001 ? 64 : 0     // también sobre la subapp
        readonly property bool hiddenForInput: home.dockMode === "subapp"
            && (Qt.inputMethod.visible
                || (calicatasEditor.item !== null && calicatasEditor.item.dockSuppressed === true))
        property real shown: hiddenForInput || home.touchFocusActive || home.page === "settings" ? 0 : 1
        // Hero .slide(.up): deceleration y duración por distancia (28 u).
        Behavior on shown { NumberAnimation { duration: home.reducedMotion ? 0 : home.heroMotion ? home.heroMotion.duration(28 * home.u) : 280
                                              easing.type: home.heroMotion ? Easing.BezierSpline : Easing.OutCubic
                                              easing.bezierCurve: home.heroMotion ? home.heroMotion.deceleration : [] } }
        visible: shown > 0.01
        // Al abrir «+» la cápsula se funde en el panel (video de referencia).
        opacity: shown * (1 - 0.85 * home.panelProgress)
        // Vertical (contexto temporal): columna a la derecha, centrada en altura.
        width: home.dockVertical ? home.dockVCellWidth + 4 * home.u : home.dockCapsuleWidth
        height: home.dockVertical ? Math.max(1, home.dockDisplayedSlots.length) * home.dockVCellHeight + 8 * home.u
                                  : home.dockHeight
        // Tablet / plegable abierto: cápsula + botón + forman un grupo centrado,
        // con el ancho de la referencia. En teléfono: geometría original.
        x: home.dockVertical ? home.width - width - 8 * home.u            // pegado al borde derecho
           : home.expandedContextDock
           ? (home.width - home.expandedDockGroupWidth) / 2
           : plusButton.x - 24 * home.u - width
        y: home.dockVertical ? Math.round((home.height - height) / 2)       // centrado en altura
           : home.height - home.dockBottom - height + (1 - shown) * 28 * home.u
        radius: Math.min(width, height) / 2
        color: "transparent"
        onYChanged: home.glassTick++
        DockGlassPanel { id: dockLiquidGlass; glassUi: home.dockGlassUi; radius: dock.radius; u: home.u; tint: home.dockGlassTint; lowFallback: false
                         reducedMotion: home.reducedMotion; liquidTouch: true }   // «Extrema»: gotas
        // ---- Píldora líquida (home.liquidPill): una sola lente que viaja. El borde
        // delantero llega en 220 ms y el trasero en 380 ms (se estira sobre ambas
        // pestañas); al llegar, squash vertical 0,92 -> 1 y el icono se tiñe de azul.
        property Item pillOwner: null
        property real pillLeft: 0
        property real pillRight: 0
        property int pillDir: 1
        property bool pillAnimate: false
        property bool pillArrived: true
        property real pillSquash: 1
        Behavior on pillLeft { enabled: dock.pillAnimate
            NumberAnimation { duration: dock.pillDir > 0 ? 380 : 220
                              easing.type: home.heroMotion ? Easing.BezierSpline : Easing.OutCubic
                              easing.bezierCurve: home.heroMotion ? home.heroMotion.deceleration : [] } }
        Behavior on pillRight { enabled: dock.pillAnimate
            NumberAnimation { duration: dock.pillDir > 0 ? 220 : 380
                              easing.type: home.heroMotion ? Easing.BezierSpline : Easing.OutCubic
                              easing.bezierCurve: home.heroMotion ? home.heroMotion.deceleration : [] } }
        function pillTo(cell) {
            if (!home.liquidPill || !cell) return
            var p = cell.mapToItem(dock, 3 * home.u, 0)
            var l = p.x, r = p.x + cell.width - 6 * home.u
            var travel = !!pillOwner && pillOwner !== cell && Math.abs(l - pillLeft) > 1
            pillDir = l >= pillLeft ? 1 : -1
            pillAnimate = travel
            pillOwner = cell
            pillLeft = l; pillRight = r
            pillAnimate = false
            if (!travel) return
            pillArrived = false
            pillArrival.restart()
            pillDrops.edge = 0; pillDrops.restart()
        }
        // Diferido: si la nueva pestaña se activa en el mismo cambio, la píldora viaja.
        function pillRelease(cell) {
            if (pillOwner !== cell) return
            Qt.callLater(function() { if (dock.pillOwner === cell && !(cell && cell.pillCell)) dock.pillOwner = null })
        }
        SequentialAnimation {
            id: pillArrival
            PauseAnimation { duration: 300 }
            NumberAnimation { target: dock; property: "pillSquash"; to: 0.92; duration: 80; easing.type: Easing.OutQuad }
            ScriptAction { script: dock.pillArrived = true }
            NumberAnimation { target: dock; property: "pillSquash"; to: 1; duration: 260; easing.type: Easing.OutBack; easing.overshoot: 2.0 }
        }
        Timer {   // «Extrema»: gotas en el borde que viaja (spawnDrop no hace nada fuera de Extrema)
            id: pillDrops
            property int edge: 0
            interval: 70; repeat: true
            onTriggered: {
                if (++edge > 3) { stop(); return }
                var x = dock.pillDir > 0 ? dockPill.x + dockPill.width : dockPill.x
                dockLiquidGlass.spawnDrop(x, dock.height / 2, dock.pillDir * 160 * home.u, 0)
            }
        }
        Rectangle {
            id: dockPill
            visible: home.liquidPill && dock.pillOwner !== null && !home.dockVertical
            opacity: dockRow.opacity
            x: dock.pillLeft
            width: Math.max(0, dock.pillRight - dock.pillLeft)
            height: home.dockHeight - 10 * home.u
            y: (dock.height - height) / 2
            radius: height / 2
            color: Qt.rgba(1, 1, 1, 0.18)        // misma lente interior que la píldora por celda
            border.width: 1
            border.color: Qt.rgba(1, 1, 1, 0.42)
            transform: Scale { origin.x: dockPill.width / 2; origin.y: dockPill.height / 2; yScale: dock.pillSquash }
        }
        Kawaii.KawaiiDockDecoration {
            anchors.fill: parent; z: 4
            active: home.appSkin === "ingenieros"
            controller: home.seasonalController
            vertical: home.dockVertical
            u: home.u
        }
        Image {
            visible: home.appSkin === "halloween"
            anchors.right: parent.right; anchors.top: parent.top; anchors.margins: 5 * home.u
            width: 28 * home.u; height: width
            source: visible ? "qrc:/images/halloween/web.svg" : ""; sourceSize: Qt.size(56, 56); opacity: 0.65
        }
        MouseArea { anchors.fill: parent; enabled: home.dockMode !== "home" }   // no atraviesa al editor
        Grid {                                   // fila (Dock) o columna (contexto vertical)
            id: dockRow
            anchors.centerIn: parent
            columns: home.dockVertical ? 1 : Math.max(1, home.dockDisplayedSlots.length)
            opacity: home.dockSwapFade * (1 - Math.min(1, dockMenuBox.shown))   // reaparecen al cerrar el panel
            onXChanged: if (dock.pillOwner) dock.pillTo(dock.pillOwner)
            onWidthChanged: if (dock.pillOwner) dock.pillTo(dock.pillOwner)
            Repeater {
                model: home.dockDisplayedSlots
                delegate: Row {
                    required property var modelData
                    required property int index
                    onXChanged: if (dockCell.active) dock.pillTo(dockCell)
                    Rectangle {   // separador
                        visible: index > 0 && !home.dockVertical
                        width: 1; height: 26 * home.u
                        anchors.verticalCenter: parent.verticalCenter
                        color: home.dockSeparatorColor
                    }
                    Item {
                        id: dockCell
                        readonly property bool active: modelData.page !== undefined
                                                       ? home.page === modelData.page
                                                       : (modelData.selected === true
                                                          || (home.dockPath.length > 0 && home.dockPath[0] === modelData.key))
                        width: home.dockVertical ? home.dockVCellWidth : home.dockCellWidth
                        height: home.dockVertical ? home.dockVCellHeight : home.dockHeight
                        opacity: modelData.enabled === false ? 0.4 : 1
                        readonly property bool pillCell: active && modelData.more !== true
                        onPillCellChanged: pillCell ? dock.pillTo(dockCell) : dock.pillRelease(dockCell)
                        Component.onCompleted: if (pillCell) dock.pillTo(dockCell)
                        Component.onDestruction: dock.pillRelease(dockCell)
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
                        Rectangle {   // indicador activo: píldora de vidrio más oscura
                            z: -2
                            visible: dockCell.pillCell && (!home.liquidPill || home.dockVertical)   // perfil líquido: dockPill
                            anchors.centerIn: parent
                            width: parent.width - 6 * home.u
                            height: home.dockVertical ? parent.height - 6 * home.u : home.dockHeight - 10 * home.u
                            radius: home.dockVertical ? 12 * home.u : height / 2
                            // Un realce verde suave, más fino, sobre el vidrio esmerilado.
                            color: home.dockVertical ? Qt.rgba(76 / 255, 175 / 255, 80 / 255, 0.20) : Qt.rgba(1, 1, 1, 0.18)
                            border.width: 1
                            border.color: home.dockVertical ? Qt.rgba(76 / 255, 175 / 255, 80 / 255, 0.26)
                                                             : Qt.rgba(1, 1, 1, 0.42)
                        }
                        Rectangle {   // realce de la herramienta pulsada / abierta
                            z: -1
                            anchors.centerIn: parent
                            // Círculo de presión (referencia): 0,8 del Dock; se va en 160 ms
                            // al soltar o al abrir el panel.
                            width: Math.min(parent.width, home.dockHeight * 0.8)
                            height: width
                            radius: width / 2
                            color: home.darkTheme ? "white" : "#1C2D50"
                            opacity: Math.max(dockCellTap.pressed && !dockMenuBox.open ? (home.darkTheme ? 0.18 : 0.10) : 0,
                                              home.dockPath.length > 0 && home.dockPath[0] === modelData.key ? 0.14 : 0)
                            Behavior on opacity { NumberAnimation { duration: home.reducedMotion ? 0 : 160; easing.type: Easing.OutCubic } }
                        }
                        Text {
                            visible: modelData.more !== true
                            anchors.centerIn: parent
                            text: String.fromCharCode(modelData.glyph)
                            rotation: modelData.rotate || 0
                            anchors.verticalCenterOffset: home.dockVertical ? -10 * home.u : 0
                            font.family: home.iconFamily
                            font.pixelSize: home.dockVertical ? 20 * home.u : home.dockIconSize
                            // Perfil líquido: el icono activo se tiñe de azul al llegar la píldora.
                            color: home.liquidPill && dockCell.pillCell && dock.pillArrived && dock.pillOwner === dockCell
                                   ? "#0A84FF" : Qt.rgba(1, 1, 1, dockCell.active ? 1.0 : 0.92)
                            Behavior on color { enabled: home.liquidPill; ColorAnimation { duration: 180 } }
                            style: Text.Outline; styleColor: home.dockGlyphOutline
                        }
                        // En el mapa la barra derecha muestra cuatro iconos
                        // con sus etiquetas. En cualquier Dock horizontal este
                        // elemento no ocupa espacio ni modifica la geometría.
                        Text {
                            visible: home.dockVertical && modelData.more !== true
                            anchors.horizontalCenter: parent.horizontalCenter
                            anchors.bottom: parent.bottom
                            anchors.bottomMargin: 6 * home.u
                            width: parent.width - 6 * home.u
                            height: 24 * home.u
                            text: String(modelData.name || "")
                            wrapMode: Text.WrapAtWordBoundaryOrAnywhere
                            maximumLineCount: 2
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                            font.pixelSize: 9 * home.u
                            font.weight: dockCell.active ? Font.DemiBold : Font.Normal
                            color: home.darkTheme ? "white" : "#152129"
                            elide: Text.ElideRight
                        }
                        Image {
                            visible: home.appSkin === "ingenieros" && dockCell.active
                            anchors.right: parent.right; y: -5*home.u
                            width: 19*home.u; height: 17*home.u
                            source: visible ? "qrc:/images/kawaii/helmet.svg" : ""
                            sourceSize: Qt.size(48,40)
                            enabled: false
                        }
                        Image {
                            visible: home.appSkin === "halloween" && dockCell.active
                            anchors.horizontalCenter: parent.horizontalCenter; y: -15 * home.u
                            width: 32 * home.u; height: width; rotation: -12
                            source: visible ? "qrc:/images/halloween/hat.svg" : ""; sourceSize: Qt.size(64, 64)
                        }
                        Image {
                            visible: home.appSkin === "halloween" && modelData.more === true
                            anchors.centerIn: parent; width: 28 * home.u; height: width
                            source: visible ? "qrc:/images/halloween/bat.svg" : ""; sourceSize: Qt.size(64, 64)
                        }
                        Row {   // "Más herramientas"
                            visible: modelData.more === true && home.appSkin !== "halloween"
                            anchors.centerIn: parent
                            spacing: 4 * home.u
                            Repeater {
                                model: 3
                                Rectangle {
                                    width: 5 * home.u; height: width; radius: width / 2
                                    color: Qt.rgba(1, 1, 1, dockCell.active ? 1.0 : 0.92)
                                    border.width: 1; border.color: home.dockGlyphOutline
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
                            property string pressOwner: ""
                            property string pressContext: ""
                            property string pressDetailId: ""
                            property bool held: false
                            property real startX: 0
                            property real startY: 0
                            anchors.fill: parent
                            pressAndHoldInterval: 380
                            preventStealing: held
                            onPressed: function(mouse) {
                                pressGeneration = home.dockGeneration
                                pressOwner = home.dockCtx ? home.dockCtx.ownerId : ""
                                pressContext = home.dockCtx ? home.dockCtx.contextId : ""
                                pressDetailId = home.dockActiveDetailId()
                                home.dockPressActive = true
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
                            onClicked: home.dockSlotTap(modelData, pressGeneration, dockCell, pressOwner, pressContext, pressDetailId)
                            onReleased: {
                                pressIn.stop()
                                pressOut.restart()
                                if (held)
                                    home.dockReleaseHover()
                                held = false
                                // onClicked se emite al soltar: actualizar el modelo
                                // antes destruiría el delegado que aún debe despachar.
                                Qt.callLater(home.dockFinishPress)
                            }
                            onCanceled: {
                                pressIn.stop()
                                pressOut.restart()
                                held = false
                                home.dockHoverIndex = -1
                                home.dockFinishPress()
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

    // Botón «+» (donde estaba InGe IA): abre/cierra el panel de herramientas del
    // Home (AddToolPanel). Gira a «×» con el mismo panelProgress de openAdd/closeAdd.
    Rectangle {
        id: plusButton
        objectName: "dockPlusButton"
        z: dock.z
        width: home.expandedContextDock ? home.expandedDockPlusWidth : 68 * home.u
        height: width
        radius: width / 2
        x: home.expandedContextDock
           ? dock.x + dock.width + home.expandedDockPlusGap
           : home.width - home.gutter - width
        y: dock.y + (dock.height - height) / 2
        color: "transparent"
        opacity: home.dockVertical ? 0 : dock.shown       // Dock único; el contexto vertical no lleva «+»
        visible: opacity > 0.01
        scale: plusTap.pressed ? 0.94 : 1 + 0.06 * home.panelProgress
        Behavior on scale { NumberAnimation { duration: home.reducedMotion ? 0 : 140; easing.type: Easing.OutCubic } }
        DockGlassPanel { glassUi: home.dockGlassUi; radius: plusButton.width / 2; u: home.u; tint: home.dockGlassTint; lowFallback: false
                         reducedMotion: home.reducedMotion; liquidTouch: true }   // «Extrema»: gotas
        Text {
            anchors.centerIn: parent
            text: "+"
            rotation: 45 * home.panelProgress           // + → ×
            font.family: home.fontFamily
            font.pixelSize: 38 * home.u
            font.weight: Font.Light
            color: "white"
            style: Text.Outline; styleColor: home.dockGlyphOutline
        }
        MouseArea {
            id: plusTap
            anchors.fill: parent
            onClicked: {
                if (home.consumeEditTap())
                    return
                if (home.addOpen) home.closeAdd(); else home.openAdd()
            }
        }
        Accessible.role: Accessible.Button
        Accessible.name: home.addOpen ? "Cerrar herramientas" : "Agregar herramientas"
    }

    // Aviso breve (notify); el botón dedicado InGe IA se retiró del Dock (2026-11-02).
    property string iaStatus: ""
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
        // Sigue al dedo desde su hueco ACTUAL y nunca sale de la cuadrícula.
        property real dragOffsetX: dragging && parent ? Math.max(-x, Math.min(parent.width - width - x, ui.dragPoint.x - ui.dragGrab.x - x)) : 0
        property real dragOffsetY: dragging && parent ? Math.max(-y, Math.min(parent.height - height - y, ui.dragPoint.y - ui.dragGrab.y - y)) : 0
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
        // «Extrema»: entrada en cascada (opacidad + desplazamiento, 30 ms por mosaico, Hero deceleration).
        property real cascade: 1
        Connections {
            target: tile.ui
            function onCascadeRequested() { if (tile.ui.extremeMotion && tile.cardKey.length > 0) cascadeIn.restart() }
        }
        SequentialAnimation {
            id: cascadeIn
            ScriptAction { script: tile.cascade = 0 }
            PauseAnimation { duration: Math.max(0, tile.modelIndex) * 30 }
            NumberAnimation { target: tile; property: "cascade"; to: 1; duration: tile.ui.heroCurves.duration(18 * tile.ui.u)
                              easing.type: Easing.BezierSpline; easing.bezierCurve: tile.ui.heroCurves.deceleration }
        }
        opacity: cascade * Math.max(0, Math.min(1, pop)) * (enabledTile ? 1 : 0.55) * (tap.pressed && !dragging ? 0.9 : 1)
                 * (cardKey.length > 0 && ui.liftKey === cardKey ? 0 : 1)   // la representa liftGhost
        z: dragging ? 10 : 0
        scale: (0.72 + 0.28 * pop) * (1 + 0.04 * lift) * (1 - 0.03 * press)
        onScaleChanged: ui.glassTick++
        onXChanged: ui.glassTick++                  // reacomodo animado: el cristal acompaña
        onYChanged: ui.glassTick++
        transform: [
            Translate { x: tile.dragOffsetX; y: tile.dragOffsetY + tile.bob * tile.jiggleAmp * tile.ui.u + (1 - tile.cascade) * 18 * tile.ui.u },
            Rotation { origin.x: tile.width / 2; origin.y: tile.height / 2; angle: tile.wobble * tile.jiggleAmp }
        ]
        // Vidrio EXACTO del Dock (preset único, sin tinte), también en Calicatas;
        // textos e iconos blancos con el contorno del Dock (dockGlyphOutline).
        color: "transparent"
        DockGlassPanel { glassUi: tile.ui; radius: tile.radius; u: tile.ui.u; tint: tile.ui.dockGlassTint; lowFallback: false }
        Rectangle {                                 // «Extrema»: realce del vidrio al pulsar (escala 0,97 ya existente)
            anchors.fill: parent
            radius: tile.radius
            visible: tile.ui.extremeMotion && tile.press > 0.01
            color: Qt.rgba(1, 1, 1, 0.14 * tile.press)
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
                style: Text.Outline; styleColor: tile.ui.dockGlyphOutline
            }
            Text {
                visible: tile.showName
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                text: tile.title
                color: "white"
                style: Text.Outline; styleColor: tile.ui.dockGlyphOutline
                font.family: tile.ui.fontFamily
                font.weight: Font.Medium
                font.pixelSize: (tile.compact ? 20 : 22) * tile.ui.u
                fontSizeMode: Text.HorizontalFit             // nombre completo («InGe Drive»): reduce antes de cortar
                minimumPixelSize: 14 * tile.ui.u
                elide: Text.ElideRight
            }
            Text {   // «Solo icono» en edición: rótulo corto para distinguir fichas con el mismo icono
                visible: tile.ui.editMode === true && tile.presentation === "icon" && tile.cardKey.length > 0
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                text: tile.title
                color: Qt.rgba(1, 1, 1, 0.92)
                style: Text.Outline; styleColor: tile.ui.dockGlyphOutline
                font.family: tile.ui.fontFamily
                font.pixelSize: 12 * tile.ui.u
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
            style: Text.Outline; styleColor: tile.ui.dockGlyphOutline
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
                style: Text.Outline; styleColor: tile.ui.dockGlyphOutline
                font.family: tile.ui.fontFamily
                font.weight: Font.Medium
                font.pixelSize: (tile.compact ? 20 : 22) * tile.ui.u
                fontSizeMode: Text.HorizontalFit             // nombre completo («InGe Drive»): reduce antes de cortar
                minimumPixelSize: 14 * tile.ui.u
                elide: Text.ElideRight
            }
            Text {
                width: parent.width
                visible: tile.showDescription && tile.subtitle.length > 0
                text: tile.subtitle
                color: Qt.rgba(1, 1, 1, 0.78)
                style: Text.Outline; styleColor: tile.ui.dockGlyphOutline
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
            z: 5                                    // sobre el contenido y la zona táctil de la ficha
            opacity: tile.ui.editMode === true && tile.cardKey.length > 0 && !tile.dragging ? 1 : 0
            visible: opacity > 0.01
            Behavior on opacity { NumberAnimation { duration: tile.ui.reducedMotion ? 0 : 180 } }
            // Dentro de la esquina superior derecha de SU ficha (libre de icono y texto): no invade la vecina.
            x: tile.width - width - 7 * tile.ui.u
            y: 7 * tile.ui.u
            width: 24 * tile.ui.u
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
            MouseArea {                             // zona táctil propia (38 u), dentro de la ficha
                anchors.fill: parent
                anchors.margins: -7 * tile.ui.u
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

    // ================================================= InGe IA (global)
    // Un solo controlador y una sola hoja, como el Dock contextual: el módulo
    // visible publica identidad, instrucciones, datos mínimos autorizados y
    // herramientas nativas. La hoja se superpone sin destruir la subapp.
    readonly property var assistantProfiles: ({
        home: { name: "InGe+ · Inicio", question: "¿En qué te ayudo hoy?",
                intro: "Pregúntame sobre ingeniería, topografía, geotecnia o cómo usar InGe+.",
                example: "¿Qué diferencia hay entre una calicata y una perforación?",
                instructions: "Contexto: pantalla de inicio. Conversa libremente y orienta sobre InGe+: Calicatas (registro geotécnico de "
                              + "calicatas y estratos), Rendiciones (gastos de campo), InGe Earth (globo y coordenadas) e InGe Drive (documentos)." },
        calicatas: { name: "Calicatas", question: "¿Qué revisamos de tus calicatas?",
                     intro: "Puedo explicar estratigrafía, clasificación de suelos y ensayos de la calicata abierta.",
                     example: "Explícame cómo interpretar los estratos de esta calicata.",
                     instructions: "Contexto: módulo Calicatas. Actúa como asistente geotécnico (estratigrafía, SUCS/AASHTO, humedad, compacidad, "
                                   + "ensayos). No inventes resultados de ensayos ni modifiques parámetros: sólo explica y sugiere." },
        rendiciones: { name: "Rendiciones", question: "¿Qué gastos rellenamos hoy?",
                       intro: "InGe IA puede ayudarte a registrar tus gastos de forma rápida y sencilla.",
                       example: "Quiero registrar estos gastos: almuerzo S/ 18, taxi S/ 12 y útiles S/ 24." },
        earth: { name: "InGe Earth", question: "¿Qué ubicamos hoy?",
                 intro: "Puedo explicar coordenadas y distancias, y usar tu ubicación o las coordenadas que escribas.",
                 example: "Distancia entre -12.0464, -77.0428 y -13.5320, -71.9675",
                 instructions: "Contexto: InGe Earth (globo 3D). Responde sobre coordenadas, sistemas de referencia, distancias y terreno. "
                               + "No inventes coordenadas ni mediciones: usa sólo las que dé el usuario o las del contexto." }
    })
    readonly property string assistantContextId: page === "calicatas" || page === "rendiciones" || page === "earth" ? page : "home"
    readonly property var assistantProfile: assistantProfiles[assistantContextId]
    // Datos mínimos autorizados de la calicata abierta (sin ids, rutas ni datos personales).
    function safeScalars(map, limit) {
        var out = []
        var keys = Object.keys(map || {})
        for (var i = 0; i < keys.length && out.length < limit; ++i) {
            var k = keys[i], v = map[k]
            if (/(^id$|_id$|Id$|uuid|user|email|token|owner|path|url|phone|created_by|updated_by)/i.test(k)) continue
            if (v === null || v === undefined || typeof v === "object") continue
            var t = String(v).trim()
            if (t.length && t.length <= 80) out.push(k + ": " + t)
        }
        return out.join(", ")
    }
    readonly property var activeCalicataDoc: page === "calicatas" && calicatasEditor.item && calicatasEditor.item.currentDoc
                                             ? calicatasEditor.item.currentDoc : null
    function calicataSummary(doc) {
        if (!doc) return ""
        var cortes = doc.cortes || []
        var lines = []
        for (var i = 0; i < cortes.length && i < 12; ++i)
            lines.push("Estrato " + (i + 1) + ": " + safeScalars(cortes[i], 10))
        return ("Calicata: " + String(doc.displayName || "") + ". Cabecera: " + safeScalars(doc.header, 10)
                + ". " + lines.join(" | ") + (doc.observaciones ? ". Observaciones: " + String(doc.observaciones).slice(0, 400) : "")).slice(0, 3500)
    }
    readonly property var earthItem: page === "earth" && earthNativeLoader.item ? earthNativeLoader.item : null
    readonly property var assistantModule: {
        var p = assistantProfile
        if (assistantContextId === "rendiciones" && renditionsLoader.item && renditionsLoader.item.assistantModule !== undefined)
            return renditionsLoader.item.assistantModule
        if (assistantContextId === "calicatas")
            return { id: "calicatas", name: p.name, instructions: p.instructions,
                     data: activeCalicataDoc ? "Calicata abierta: " + String(activeCalicataDoc.displayName || "") : "Sin calicata abierta.",
                     tools: [{ id: "calicatas.explain", label: "Interpretar la calicata abierta", glyph: 0xE0CC, enabled: activeCalicataDoc !== null }] }
        if (assistantContextId === "earth") {
            var t = earthItem ? earthItem.selectedTarget : null
            var hasTarget = !!t && t.latitude !== undefined
            return { id: "earth", name: p.name, instructions: p.instructions,
                     data: hasTarget ? "Punto seleccionado: " + String(t.label || "") + " (" + Number(t.latitude).toFixed(6) + ", " + Number(t.longitude).toFixed(6) + ")" : "",
                     tools: [{ id: "earth.gps", label: "Mi ubicación", glyph: 0xE111, offline: true, enabled: earthItem !== null },
                             { id: "earth.goTo", label: "Ir a las coordenadas del mensaje", glyph: 0xE0E8, offline: true, enabled: earthItem !== null },
                             { id: "earth.distance", label: "Distancia entre puntos", glyph: 0xE14B, offline: true }] }
        }
        return { id: "home", name: p.name, instructions: p.instructions, data: "", tools: [] }
    }
    // Coordenadas escritas por el USUARIO en su último mensaje (nunca inventadas por el modelo).
    function lastUserCoordinates() {
        var list = assistantController.messages
        for (var i = list.length - 1; i >= 0; --i) {
            if (list[i].role !== "user") continue
            var re = /(-?\d{1,2}(?:[.]\d+)?)\s*[,;]\s*(-?\d{1,3}(?:[.]\d+)?)/g
            var out = [], m
            while ((m = re.exec(String(list[i].text))) !== null) {
                var lat = Number(m[1]), lon = Number(m[2])
                if (Math.abs(lat) <= 90 && Math.abs(lon) <= 180) out.push({ latitude: lat, longitude: lon })
            }
            return out
        }
        return []
    }
    function haversineKm(a, b) {
        var r = 6371.0088, rad = Math.PI / 180
        var dLat = (b.latitude - a.latitude) * rad, dLon = (b.longitude - a.longitude) * rad
        var h = Math.sin(dLat / 2) * Math.sin(dLat / 2)
              + Math.cos(a.latitude * rad) * Math.cos(b.latitude * rad) * Math.sin(dLon / 2) * Math.sin(dLon / 2)
        return 2 * r * Math.asin(Math.min(1, Math.sqrt(h)))
    }
    // Registro de herramientas nativas: sólo comandos existentes y validados.
    function assistantRunTool(toolId) {
        var a = assistantController
        if (toolId.indexOf("renditions.") === 0) {
            if (renditionsLoader.item && renditionsLoader.item.assistantRunTool !== undefined) renditionsLoader.item.assistantRunTool(toolId, a)
            return
        }
        if (toolId === "calicatas.explain") {
            if (!activeCalicataDoc) return
            a.note("Se enviaron a InGe IA los datos de la calicata abierta (cabecera, estratos y observaciones), sin identificadores personales.")
            a.ask("Interpreta técnicamente los estratos de esta calicata (posibles tipos de suelo, consistencia, nivel freático y "
                  + "observaciones relevantes). Si un dato falta, dilo; no inventes ensayos.\n" + calicataSummary(activeCalicataDoc),
                  function(text) { a.push(a.key, { role: "assistant", text: text, kind: "chat" }) })
            return
        }
        if (toolId === "earth.gps") { if (earthItem) { earthItem.requestGps(); a.note("Buscando tu posición GPS en InGe Earth…") } return }
        var pts = lastUserCoordinates()
        if (toolId === "earth.goTo") {
            if (!earthItem) return
            if (!pts.length) { a.note("Escribe primero las coordenadas en tu mensaje (latitud, longitud en grados decimales)."); return }
            earthItem.requestedTarget = { latitude: pts[0].latitude, longitude: pts[0].longitude, altitude: 0, label: "coordenadas del chat" }
            a.note("InGe Earth centrado en " + pts[0].latitude.toFixed(6) + ", " + pts[0].longitude.toFixed(6) + ".")
            return
        }
        if (toolId === "earth.distance") {
            var t = earthItem ? earthItem.selectedTarget : null
            if (pts.length === 1 && t && t.latitude !== undefined) pts = [{ latitude: Number(t.latitude), longitude: Number(t.longitude) }, pts[0]]
            if (pts.length < 2) { a.note("Necesito dos puntos: escríbelos en tu mensaje (lat, lon y lat, lon) o selecciona uno en InGe Earth y escribe el otro."); return }
            a.note("Distancia geodésica (haversine, radio medio 6371 km) entre " + pts[0].latitude.toFixed(5) + ", " + pts[0].longitude.toFixed(5)
                   + " y " + pts[1].latitude.toFixed(5) + ", " + pts[1].longitude.toFixed(5) + ": " + haversineKm(pts[0], pts[1]).toFixed(3) + " km.")
        }
    }
    Assistant.InGeAssistantController {
        id: assistantController
        userId: home.userId
        module: home.assistantModule
        toolRunner: function(toolId) { home.assistantRunTool(toolId) }
        proposalValidator: function(p) {
            return renditionsLoader.item && renditionsLoader.item.assistantValidate !== undefined ? renditionsLoader.item.assistantValidate(p) : p
        }
    }
    Assistant.InGeAssistantSheet {
        id: assistantSheet
        z: 80                                          // sobre subapps, Dock y editores
        ui: home
        flow: CoreFlowModule.InGeCoreFlow
        controller: assistantController
        userName: AccountText.hasVisibleText(home.firstName) ? home.firstName : ""
        question: home.assistantProfile.question
        intro: home.assistantProfile.intro
        example: home.assistantProfile.example
        onProposalAction: function(index, proposal) {
            if (renditionsLoader.item && renditionsLoader.item.assistantOpen !== undefined
                    && renditionsLoader.item.assistantOpen(index, proposal, assistantController))
                assistantSheet.close()
        }
    }

    // ================================================ 3D Touch (foco global)
    // Al abrir el menú de una caja de Rendiciones: toda la pantalla se desenfoca
    // (también encabezado, Dock e InGe IA, que además se ocultan), la caja
    // presionada se muestra nítida y elevada, y el menú se aloja encima.
    readonly property Item renditionsTouchTile: page === "rendiciones" && renditionsLoader.item
                                                && renditionsLoader.item.touchFocusItem !== undefined
                                                ? renditionsLoader.item.touchFocusItem : null
    readonly property bool touchFocusActive: renditionsTouchTile !== null
                                             || (menuKey.length > 0 && overlayLevel > 0.01)
    Item {
        id: touchFocusLayer
        objectName: "touchFocusLayer"
        anchors.fill: parent
        z: 66
        property real level: home.renditionsTouchTile !== null ? 1 : 0
        Behavior on level { NumberAnimation { duration: home.reducedMotion ? 0 : (touchFocusLayer.level < 0.5 ? 240 : 180); easing.type: Easing.OutCubic } }
        visible: level > 0.01 && renditionsLoader.visible
        MultiEffect {
            anchors.fill: parent
            source: renditionsLoader
            autoPaddingEnabled: false
            blurEnabled: home.liquidGlass
            blurMax: 64
            blur: 0.9 * touchFocusLayer.level
            saturation: -0.15 * touchFocusLayer.level
        }
        Rectangle { anchors.fill: parent; color: "#0A1020"; opacity: 0.22 * touchFocusLayer.level }
        MouseArea { anchors.fill: parent }          // el contenido desenfocado no recibe toques
        ShaderEffectSource {                         // copia viva y nítida de la caja presionada
            id: liftedTile
            readonly property Item tile: home.renditionsTouchTile
            readonly property point origin: tile ? tile.mapToItem(touchFocusLayer, 0, 0) : Qt.point(0, 0)
            sourceItem: tile
            live: true
            visible: tile !== null
            x: origin.x; y: origin.y
            width: tile ? tile.width : 0
            height: tile ? tile.height : 0
            scale: 1 + 0.04 * touchFocusLayer.level
            opacity: touchFocusLayer.level
        }
    }
    Item {                                           // anfitrión de los menús 3D Touch de las subapps
        id: touchMenuHost
        objectName: "touchMenuHost"
        anchors.fill: parent
        z: 67
    }
}

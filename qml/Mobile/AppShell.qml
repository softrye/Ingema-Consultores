import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15
import QtPositioning
import InGe 1.0
import InGe.CoreFlow 3.0 as Mobile
import "pages" as Pages
import "lib/GpsBus.js" as GpsBus
import "flowcore" as FlowCore


Item {
    id: shell

    property bool flowMotionEnabled: true
    property bool flowReduceMotion: false
    property int flowMotionLevel: 2

    readonly property var pageFlow: Mobile.InGeCoreFlow


    width:  StackView.view ? StackView.view.width  : (parent ? parent.width  : 420)
    height: StackView.view ? StackView.view.height : (parent ? parent.height : 820)

    Component.onCompleted: console.log("[AppShell] _perms=", shell._perms)

    // Te llega desde Main.qml
    property var auth: null
    property var _perms: (typeof Perms !== "undefined") ? Perms : null

    property bool darkMode: false



    // ===== Estado Drawer (móvil) =====
    property string projectsFolderLabel: "InGePlusProyectos"
    readonly property bool hasSession: !!(shell.auth && shell.auth.logged === true)

    property bool isOnline: true
    property bool autoLogoutWhenOffline: true

    // ===== GPS GLOBAL (persistente entre páginas) =====
    property bool gpsAutoShare: false
    property bool gpsHasPermission: false
    property bool _gpsPendingOn: false

    property var  gpsCoord: QtPositioning.coordinate(-5.19449, -80.63282)
    property real gpsAltitude: NaN

    property bool _checkingOnline: false
    property int  _onlineSeq: 0
    property bool _offlineAutoLogoutDone: false

    // ===== Señales acciones =====
    signal requestShowLogin()
    signal requestLogout()
    signal requestChangeProjectsFolder()
    signal requestOpenProjectsFolder()
    signal requestResetProjectsFolder()
    signal requestAbout()
    signal requestExportLog()


    // --- arriba (propiedades) ---
    property bool calicatasEditorShown: false
    property bool calicatasEditorEverLoaded: false

    function openCalicatasEditor() {
        calicatasEditorShown = true
        calicatasEditorEverLoaded = true
    }

    Component {
        id: calicatasEditorComp
        Pages.CalicatasEditorPage {           // <-- OJO: plural, coincide con tu archivo
            auth: shell.auth
            gpsEnabled: shell.gpsAutoShare
            darkMode: shell.darkMode

            // para que no se vea Home “detrás” si algo es transparente
            background: Rectangle { color: "white" }

            onRequestBack: {
                shell.calicatasEditorShown = false
                shell.goHome()
            }
            onRequestGpsAutoShare: (on) => shell.setGpsAutoShareRequested(on)
        }
    }

    // --- Loader persistente ---
    Loader {
        id: calicatasEditorL
        anchors.fill: parent
        z: 1500

        active: shell.calicatasEditorShown || shell.calicatasEditorEverLoaded
        visible: shell.calicatasEditorShown
        enabled: shell.calicatasEditorShown

        sourceComponent: calicatasEditorComp

        onStatusChanged: {
            console.log("[CalicatasEditorL] status=", status, " item=", item)
            if (status === Loader.Error)
                console.error("[CalicatasEditorL] ERROR:", errorString())
            if (status === Loader.Ready)
                shell.calicatasEditorEverLoaded = true
        }
    }

    // overlay simple mientras carga (opcional pero útil)
    Rectangle {
        anchors.fill: parent
        z: 1499
        visible: shell.calicatasEditorShown && calicatasEditorL.status === Loader.Loading
        color: "white"
        BusyIndicator { anchors.centerIn: parent; running: true }
    }

    Connections {
        target: calicatasEditorL.item
        ignoreUnknownSignals: true
        function onRequestBack() {
            shell.calicatasEditorShown = false
            shell.goHome()
        }
        function onRequestGpsAutoShare(on) {
            shell.setGpsAutoShareRequested(on)
        }
    }





    function syncGpsToModal() {
        // Si tienes otros modales en modalNav, esto lo puedes dejar
        if (modalNav.depth > 0 && modalNav.currentItem && modalNav.currentItem.gpsEnabled !== undefined) {
            modalNav.currentItem.gpsEnabled = shell.gpsAutoShare
        }

        // ✅ NUEVO: si estás usando el loader persistente de CalicatasEditor
        if (calicatasEditorL.item && calicatasEditorL.item.gpsEnabled !== undefined) {
            calicatasEditorL.item.gpsEnabled = shell.gpsAutoShare
        }
    }
    onGpsAutoShareChanged: {
        syncGpsToModal()
        if (!gpsAutoShare) GpsBus.clear()
    }

    onGpsHasPermissionChanged: {
        if (!gpsHasPermission) GpsBus.clear()
    }





    function setGpsAutoShareRequested(on) {
        on = !!on
        if (!on) {
            gpsAutoShare = false
            _gpsPendingOn = false
            return
        }
        if (gpsHasPermission) {
            gpsAutoShare = true
            return
        }
        _gpsPendingOn = true

        if (shell._perms && shell._perms.requestLocation) {
            shell._perms.requestLocation()
        } else {
            console.warn("[GPS] Perms no disponible. Asumiendo permiso OK (desktop).")
            gpsHasPermission = true
            gpsAutoShare = true
            _gpsPendingOn = false
        }
    }

    function resolveUserName() {
        if (!shell.auth || shell.auth.logged !== true) return "Invitado"
        var dn = ""
        if (shell.auth.displayName !== undefined)
            dn = (typeof shell.auth.displayName === "function")
                 ? shell.auth.displayName()
                 : shell.auth.displayName
        dn = (dn || "").toString().trim()
        return dn.length ? dn : "Invitado"
    }

    function checkOnline() {
        if (_checkingOnline) return
        _checkingOnline = true
        var seq = ++_onlineSeq

        var xhr = new XMLHttpRequest()
        xhr.timeout = 2500

        function finish(ok) {
            if (seq !== _onlineSeq) return
            shell.isOnline = ok
            _checkingOnline = false
        }

        xhr.onreadystatechange = function() {
            if (xhr.readyState === XMLHttpRequest.DONE)
                finish(xhr.status > 0)
        }
        xhr.ontimeout = function() { finish(false) }
        xhr.onerror   = function() { finish(false) }

        xhr.open("GET", "https://www.gstatic.com/generate_204", true)
        xhr.send()
    }

    Timer {
        interval: 5000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: shell.checkOnline()
    }


    onIsOnlineChanged: {
        if (!shell.isOnline) {
            toast.show("Conexión perdida. Modo offline.")

            if (shell.autoLogoutWhenOffline && shell.hasSession && shell.auth && !_offlineAutoLogoutDone) {
                _offlineAutoLogoutDone = true
                Qt.callLater(function() {
                    if (shell.auth.signOutLocal)
                        shell.auth.signOutLocal()
                    else
                        shell.auth.signOut()
                })
            }
        } else {
            _offlineAutoLogoutDone = false
            toast.show("Conexión restablecida.")
        }
    }

    Loader {
        active: !!shell._perms
        sourceComponent: Component {
            Connections {
                target: shell._perms
                ignoreUnknownSignals: true

                function onLocationPermissionResult(granted) {
                    shell.gpsHasPermission = !!granted
                    if (granted && shell._gpsPendingOn) {
                        shell.gpsAutoShare = true
                        shell._gpsPendingOn = false
                    } else if (!granted) {
                        shell.gpsAutoShare = false
                        shell._gpsPendingOn = false
                        toast.show("Permiso de ubicación DENEGADO")
                    }
                }

                function onLocationPermissionChanged(granted) {
                    onLocationPermissionResult(granted)
                }
            }
        }
    }

    PositionSource {
        id: gpsSrc
        active: shell.gpsAutoShare && shell.gpsHasPermission
        updateInterval: 1000

        onPositionChanged: {
            if (!position || !position.coordinate) return

            shell.gpsCoord = position.coordinate
            shell.gpsAltitude = position.coordinate.altitude

            // ✅ alimenta el bus SI GPS está activo
            if (shell.gpsAutoShare && shell.gpsHasPermission) {
                var c = position.coordinate
                var alt = c.altitude
                var altOk = isFinite(alt)
                var t = Qt.formatTime(new Date(), "hh:mm:ss")
                GpsBus.updateFromGeo(c.latitude, c.longitude, alt, altOk, t)
            }
        }
        onSourceErrorChanged: {
            if (sourceError !== PositionSource.NoError)
                console.warn("[GPS] PositionSource error:", sourceError)
        }
    }

    // ====== NAV (TABS) ======
    property string currentKey: "home"
    property bool _mapLoaded: false
    property bool _profileLoaded: false

    function keyIndex(k) {
        switch (k) {
        case "home":    return 0
        case "map":     return 1
        case "docs":    return 2
        case "profile": return 3
        default:        return 0
        }
    }

    function goKey(k) {
        if (k === shell.currentKey) return
        shell.currentKey = k
    }
    function goHome()    { goKey("home") }
    function goMap()     { goKey("map") }
    function goDocs()    { goKey("docs") }
    function goProfile() { goKey("profile") }


    function openTaludEditor() {
        toast.show("Ficha de Talud: pendiente")
    }

    function openPE() {
        toast.show("Perfiles Estratigráficos: pendiente")
    }

    function openEG() {
        toast.show("Estaciones Geomecánicas: pendiente")
    }



// ===== Componentes contenido (SOLO UNA VEZ) =====
    Component {
        id: homeComp
        Pages.HomePage {
            auth: shell.auth
            darkMode: shell.darkMode
            onRequestOpenCalicata: shell.openCalicatasEditor()
            onRequestOpenTalud:    shell.openTaludEditor()
            onRequestOpenPE:       shell.openPE()
            onRequestOpenEG:       shell.openEG()
            onRequestOpenMap:      shell.goMap()
            onRequestOpenDocs:     shell.goDocs()
        }
    }


    Component {
        id: mapComp
        Pages.MapPageContent {
            auth: shell.auth
            darkMode: shell.darkMode
            gpsAutoShare: shell.gpsAutoShare
            gpsHasPermission: shell.gpsHasPermission
            gpsCoord: shell.gpsCoord
            gpsAltitude: shell.gpsAltitude
            onRequestGpsAutoShare: (on) => shell.setGpsAutoShareRequested(on)
        }
    }

    Component { id: profileComp; Pages.ProfilePageContent { auth: shell.auth } }

    // Página actual real (para HeaderBar)
    property var currentPage: (modalNav.depth > 0) ? modalNav.currentItem
                         : (currentKey==="home")    ? homeL.item
                         : (currentKey==="map")     ? mapL.item
                         : (currentKey==="docs")    ? documentsModuleSlot
                         : (currentKey==="profile") ? profileL.item
                         : null



    function openGlobalSearch(text) {
        if (globalSearchOverlay)
            globalSearchOverlay.open(text || "")
    }

    function handleGlobalSearchResult(kind, payload, title) {
        if (payload === "calicata_new" || payload === "calicata_editor") {
            shell.openCalicatasEditor()
            return
        }

        if (payload === "map") {
            shell.goMap()
            return
        }

        if (payload === "docs" || payload === "exports_excel" || payload === "field_photos" || payload === "reports") {
            shell.goDocs()
            return
        }

        if (payload === "profile") {
            shell.goKey("profile")
            return
        }

        if (payload === "settings" || payload === "speed_test") {
            shell.goKey("profile")
            toast.show("Configuración está en fase 02")
            return
        }

        if (payload === "support") {
            toast.show("Asistencia de software: próximamente")
            return
        }

        toast.show(title || "Resultado abierto")
    }
    // ===== HEADER =====
    HeaderBar {
        id: header
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        online: shell.isOnline
        motionEnabled: shell.flowMotionEnabled
        reduceMotion: shell.flowReduceMotion
        motionLevel: shell.flowMotionLevel
        visible: modalNav.depth === 0
                 && !shell.calicatasEditorShown
                 && shell.currentKey !== "docs"

        greetingText: "Hola, " + shell.resolveUserName()

        subGreetingText: (shell.currentPage && shell.currentPage.subGreetingText !== undefined)
                         ? shell.currentPage.subGreetingText
                         : ""

        showSearch: (shell.currentPage && shell.currentPage.showSearch !== undefined)
                    ? shell.currentPage.showSearch
                    : true

        onMenuClicked: drawer.open()

        onSearchAccepted: (text) => { shell.openGlobalSearch(text) }
    }


    GlobalSearchOverlay {
        id: globalSearchOverlay
        anchors.fill: parent
        z: 99999
        darkMode: shell.darkMode
        flowMotionEnabled: shell.flowMotionEnabled
        flowReduceMotion: shell.flowReduceMotion
        flowMotionLevel: shell.flowMotionLevel
        onResultActivated: function(kind, payload, title) {
            shell.handleGlobalSearchResult(kind, payload, title)
        }
    }
    // ===== FOOTER =====
    BottomNav {
        id: footer
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        visible: modalNav.depth === 0 && !shell.calicatasEditorShown
        currentKey: shell.currentKey
        motionEnabled: shell.flowMotionEnabled
        reduceMotion: shell.flowReduceMotion
        motionLevel: shell.flowMotionLevel

        onTabClicked: function(key) {
            shell.goKey(key)   // "home" | "map" | "docs" | "profile"
        }
    }


    // ===== CONTENIDO (TABS) =====
    StackLayout {
        id: content
        anchors.top: shell.currentKey === "docs" ? parent.top : header.bottom
        anchors.bottom: footer.top
        anchors.left: parent.left
        anchors.right: parent.right

        currentIndex: keyIndex(shell.currentKey)
        opacity: 1.0
        scale: 1.0
        transformOrigin: Item.Center
        onCurrentIndexChanged: {
            pageEntrance.stop()
            if (pageFlow.motionAllowed) pageEntrance.start()
            else { opacity = 1.0; scale = 1.0 }
        }
        ParallelAnimation {
            id: pageEntrance
            NumberAnimation { target: content; property: "opacity"; from: 0.0; to: 1.0; duration: pageFlow.pageInDuration; easing.type: pageFlow.easeOut }
            NumberAnimation { target: content; property: "scale"; from: 0.985; to: 1.0; duration: pageFlow.pageInDuration; easing.type: pageFlow.easeOut }
        }

        Loader {
            id: homeL
            asynchronous: true
            active: true
            sourceComponent: homeComp
        }

        Loader {
            id: mapL
            asynchronous: true
            active: (shell.currentKey==="map") || shell._mapLoaded
            sourceComponent: mapComp
            onLoaded: shell._mapLoaded = true
        }

        Item {
            id: documentsModuleSlot
            Layout.fillWidth: true
            Layout.fillHeight: true
        }



        Loader {
            id: profileL
            asynchronous: true
            active: (shell.currentKey==="profile") || shell._profileLoaded
            sourceComponent: profileComp
            onLoaded: shell._profileLoaded = true
        }
    }

    StackView {
        id: modalNav
        anchors.fill: parent     // ✅ antes estaba desde header.bottom
        z: 999
        visible: depth > 0

        replaceEnter: null
        replaceExit: null
        pushEnter: null
        pushExit: null
        popEnter: null
        popExit: null
    }













    // ===== Drawer =====
    Drawer {
        id: drawer
        edge: Qt.RightEdge
        width: (shell.width * 0.82 < 360) ? shell.width * 0.82 : 360
        height: shell.height
        modal: true
        enter: Transition {
            NumberAnimation { property: "position"; from: 0.0; to: 1.0; duration: pageFlow.sheetDuration; easing.type: pageFlow.easeEmphasized }
        }
        exit: Transition {
            NumberAnimation { property: "position"; from: 1.0; to: 0.0; duration: pageFlow.normalDuration; easing.type: pageFlow.easeIn }
        }

        contentItem: Rectangle {
            color: "white"

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 14
                spacing: 10

                Label { text: "Opciones"; font.pixelSize: 18; font.bold: true; color: "#1B2A4E" }
                Rectangle { height: 1; Layout.fillWidth: true; color: "#D0D4E4" }

                Label {
                    text: shell.hasSession
                          ? ("Sesión: ACTIVA (" + shell.resolveUserName() + ")")
                          : "Sesión: OFFLINE"
                    color: "#7A8CA4"
                }

                Rectangle { height: 1; Layout.fillWidth: true; color: "#D0D4E4" }

                Label { text: "Carpeta de proyectos"; font.bold: true; color: "#1B2A4E" }
                Label {
                    text: "Actual: " + shell.projectsFolderLabel
                    color: "#4B5A73"
                    wrapMode: Text.WordWrap
                }

                Button { Layout.fillWidth: true; text: "Cambiar carpeta de proyectos..."; onClicked: { drawer.close(); shell.requestChangeProjectsFolder() } }
                Button { Layout.fillWidth: true; text: "Abrir carpeta de proyectos"; onClicked: { drawer.close(); shell.requestOpenProjectsFolder() } }
                Button { Layout.fillWidth: true; text: "Restaurar ubicación por defecto"; onClicked: { drawer.close(); shell.requestResetProjectsFolder() } }

                Rectangle { height: 1; Layout.fillWidth: true; color: "#D0D4E4" }

                Label { text: "GPS"; font.bold: true; color: "#1B2A4E" }
                RowLayout {
                    Layout.fillWidth: true
                    Label { Layout.fillWidth: true; text: "Compartir ubicación automática (GPS)"; color: "#4B5A73"; wrapMode: Text.WordWrap }
                    Switch { checked: !!shell.gpsAutoShare; onToggled: shell.setGpsAutoShareRequested(checked) }
                }

                Rectangle { height: 1; Layout.fillWidth: true; color: "#D0D4E4" }

                Label { text: "Soporte"; font.bold: true; color: "#1B2A4E" }
                Button { Layout.fillWidth: true; text: "Acerca de"; onClicked: { drawer.close(); shell.requestAbout() } }
                Button { Layout.fillWidth: true; text: "Exportar log..."; onClicked: { drawer.close(); shell.requestExportLog() } }

                Item { Layout.fillHeight: true }
                Rectangle { height: 1; Layout.fillWidth: true; color: "#D0D4E4" }

                Button {
                    Layout.fillWidth: true
                    text: "Iniciar sesión"
                    enabled: !shell.hasSession
                    opacity: enabled ? 1 : 0.45
                    onClicked: {
                        if (!shell.isOnline) { toast.show("Necesitas conexión para iniciar sesión."); return }
                        drawer.close()
                        shell.requestShowLogin()
                    }
                }

                Button {
                    Layout.fillWidth: true
                    text: "Cerrar sesión (modo offline)"
                    enabled: shell.hasSession
                    opacity: enabled ? 1 : 0.45
                    onClicked: confirmLogout.open()
                }

                Button { Layout.fillWidth: true; text: "Cerrar"; onClicked: drawer.close() }
            }
        }
    }

    // ===== Toast =====
    Popup {
        id: toast
        x: (shell.width - width) / 2
        y: shell.height - height - 84
        width: Math.min(shell.width * 0.9, 360)
        modal: false
        focus: false

        background: Rectangle { radius: 10; color: "#1B2A4E"; opacity: 0.92 }

        contentItem: Label {
            id: toastLabel
            text: ""
            color: "white"
            wrapMode: Text.WordWrap
            padding: 12
        }

        Timer { id: toastTimer; interval: 2200; onTriggered: toast.close() }

        function show(msg) {
            toastLabel.text = msg
            toast.open()
            toastTimer.restart()
        }
    }

    // ===== Confirmación Logout =====
    Popup {
        id: confirmLogout
        modal: true
        focus: true
        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside

        width: Math.min(shell.width * 0.85, 360)
        x: (shell.width - width) / 2
        y: (shell.height - height) / 2

        background: Rectangle {
            radius: 12
            color: "white"
            border.width: 1
            border.color: "#D0D4E4"
        }

        contentItem: Column {
            spacing: 10
            padding: 14

            Label { text: "Cerrar sesión"; font.bold: true; color: "#1B2A4E" }
            Label { text: "¿Deseas cerrar la sesión y pasar a modo offline?"; wrapMode: Text.WordWrap; color: "#1B2A4E" }
            Label { text: "Podrás seguir usando la app en modo local como Invitado."; wrapMode: Text.WordWrap; color: "#7A8CA4" }

            Row {
                spacing: 10
                anchors.horizontalCenter: parent.horizontalCenter

                Button { text: "Cancelar"; onClicked: confirmLogout.close() }
                Button {
                    text: "Cerrar sesión"
                    onClicked: {
                        confirmLogout.close()
                        drawer.close()
                        shell.requestLogout()
                        toast.show("Sesión cerrada. Modo offline activado.")
                    }
                }
            }
        }
    }
}

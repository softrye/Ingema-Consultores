import QtQuick
import QtTest
import InGe 1.0
import "../pages" as P
import "../renditions" as R
import "../renditions/RStyle.js" as S
import "../lib/CalicataDiagnostics.js" as CalDiag
import "../lib/IconCatalog.js" as IconCatalog

// Comportamiento del Home REAL de Calicatas (CalicatasHome.qml y
// CalicatasTopoMap.qml copiados sin cambios por run_home_qml_tests.cjs) contra
// un CalicataCloud simulado y el motor Qt Location REAL con una pirámide de
// teselas locales distintas (z3..z17). La cobertura cartográfica se mide en
// capturas del mapa: run_home_qml_tests.cjs decodifica cada captura
// "cov_<etiqueta>_max<porcentaje>.png" y falla si el fondo vacío supera el
// porcentaje. Lo físico (GPU Mali, red real, gestos del sistema) queda para el equipo.
Item {
    id: root
    width: 360; height: 760

    QtObject { id: uiStub; property real u: 1; property string fontFamily: ""; property string iconFamily: ""
               property real topInset: 24; property real dockArea: 110; property real dockBottom: 16; property real dockHeight: 64
               property var subAppProgress: undefined
               property var marks: []
               function calicatasMark(e) { marks.push(String(e).split(" ")[0]) } }
    QtObject {
        id: docStub
        property var header: ({ projectId: "" })
        property var drafts: []
        function listDrafts() { return drafts }
        function listProjectDrafts(pid, includeShared) { return [] }
    }
    QtObject {
        id: editorStub
        property var currentDoc: docStub
        property var dockAnchor: null
        property bool flowReduceMotion: false
        property var calls: []
        function openHomeRow(r) { calls.push("open:" + r.key) }
        function createFromHome(v) { calls.push("create"); return "" }
        function openFromHomeDrive() {}
        function openFromSystemPicker() {}
        function openArchivedForProject(p) {}
        function showMsg(t, m) {}
        property var stagedLogos: ({})
        function openLogoStaging() {}
        function cancelLogoStaging() {}
    }

    // Aura real de Rendiciones detrás del Home, como en CalicatasEditorPage.background.
    R.RendicionesSyncAura { id: aura; anchors.fill: parent; running: true }
    Loader {
        id: loader
        anchors.fill: parent
        active: false
        sourceComponent: Component {
            P.CalicatasHome { ui: uiStub; editor: editorStub; projectsTimeoutMs: 300; listTimeoutMs: 300 }
        }
    }
    readonly property var home: loader.item
    readonly property var map: home ? home.mapItem : null
    readonly property string tileHost: Qt.resolvedUrl("../fixtures/tiles/").toString()
    readonly property string cacheDir: Qt.resolvedUrl("../cache").toString().replace(/^file:\/\/\/?/, "")
    property int shot: 0

    function healthState() {
        return { loaded: home.loaded, refreshing: home.refreshing, projectsError: home.projectsError,
                 listError: home.listError, loadErrors: home.loadErrors, syncFailures: [],
                 pendingMedia: CalicataCloud.pendingMediaCount, localPending: home.localPendingCount,
                 conflicts: home.conflictCount }
    }
    function diagnostics() { return CalDiag.buildHome(healthState()) }
    function auraMode() { return CalDiag.auraModeHome(healthState(), diagnostics()) }

    function pid(n) { return "aaaaaaa" + n + "-0000-4000-8000-00000000000" + n }
    function eightProjects() {
        var out = []
        for (var i = 1; i <= 8; ++i) out.push({ id: pid(i), code: "P0" + i, name: "Proyecto " + i })
        return out
    }
    // 21 calicatas (13 con coordenadas UTM 18S reales), como el equipo del registro.
    function serverRows() {
        var st = ["APROBADO", "EN_REVISION", "BORRADOR", "OBSERVADO", "EXPORTADO", "REVISADO"]
        var out = []
        for (var i = 1; i <= 21; ++i) {
            var n = (i < 10 ? "0" : "") + i
            var r = { id: "b00000" + n + "-0000-4000-8000-0000000000" + n, project_id: i <= 18 ? pid(1) : pid(2),
                      code: "C-" + n, status: st[i % st.length], updated_at: "2026-10-" + n + "T10:00:00Z" }
            if (i <= 13) { r.easting = String(280000 + i * 900); r.northing = String(8660000 + i * 700); r.utm_zone = 18 }
            out.push(r)
        }
        return out
    }

    TestCase {
        id: tc
        name: "CalicatasHome"
        when: windowShown

        function find(name) { var o = findChild(root.home, name); verify(o, "no existe " + name); return o }
        function start(projectsMode, listMode, cached) {
            loader.active = false
            CalicataCloud.reset()
            docStub.drafts = []
            editorStub.calls = []
            CalicataCloud.serverProjects = eightProjects()
            CalicataCloud.serverRows = serverRows()
            CalicataCloud.projectsMode = projectsMode || "ok"
            CalicataCloud.listMode = listMode || "ok"
            if (cached) CalicataCloud.projects = eightProjects()
            loader.active = true
            tryVerify(function() { return root.home !== null }, 2000)
            root.map.tileHostOverride = root.tileHost                // nunca la red en pruebas
            root.map.cacheDirectoryOverride = root.cacheDir
        }
        function waitIdle() {
            tryVerify(function() { return root.home.loaded && !root.home.refreshing }, 3000, "el ciclo no terminó")
        }
        function settlePages() {
            tryVerify(function() { return Math.abs(root.home.pagePos - (root.home.view === "map" ? 1 : 0)) < 1e-9 }, 2000)
        }
        function openMap() {
            root.home.view = "map"; settlePages()
            tryVerify(function() { return root.map.mapReady }, 5000, "Qt Location no quedó listo")
            wait(400)
        }
        // Captura del mapa; el runner exige que el fondo vacío no supere maxPct.
        function coverage(label, maxPct) {
            root.shot++
            var f = Qt.resolvedUrl("../shots/cov_" + (root.shot < 10 ? "0" : "") + root.shot + "_" + label + "_max" + maxPct + ".png")
                        .toString().replace(/^file:\/\/\/?/, "")
            var saved = null
            root.map.grabToImage(function(g) { saved = g.saveToFile(f) })
            tryVerify(function() { return saved !== null }, 3000)
            verify(saved, "no se pudo guardar " + f)
        }
        function selectProject(index) {
            mouseClick(find("homeFilterButton"))
            tryVerify(function() { return find("homeFilterMenu").open }, 1000)
            wait(300)                                             // animación de apertura (220 ms)
            var item = index < 0 ? find("homeFilterAll") : find("homeFilterProjects").itemAt(index)
            verify(item)
            mouseClick(item)
            tryVerify(function() { return !find("homeFilterMenu").open }, 1000)
        }
        // Gesto real: presionar en (x, y), mover en pasos y soltar.
        // Las coordenadas del dedo son de pantalla (root fijo): la página se mueve con
        // el dedo y mouseMove(item, ...) relativo a ella exageraría el recorrido.
        function swipe(item, x, y, dx, dy, steps, stepMs) {
            var s = item.mapToItem(root, x, y)
            mousePress(root, s.x, s.y)
            for (var i = 1; i <= steps; ++i) mouseMove(root, s.x + dx * i / steps, s.y + dy * i / steps, stepMs)
            mouseRelease(root, s.x + dx, s.y + dy, Qt.LeftButton, Qt.NoModifier, stepMs)
            wait(80)                                              // decisión diferida (callLater)
            settlePages()
        }
        function listSwipe(dx, dy, x, steps, stepMs) {
            swipe(find("homeListFlick"), x === undefined ? (dx < 0 ? 300 : 80) : x, 430, dx, dy || 0, steps || 10, stepMs === undefined ? 16 : stepMs)
        }
        function edge() { var e = find("homeMapEdge"); return e.mapToItem(root.map, e.width / 2, e.height / 2) }
        function mapSwipe(dx, dy, steps, stepMs) {
            var p = edge()
            swipe(root.map, p.x, p.y, dx, dy || 0, steps || 10, stepMs === undefined ? 16 : stepMs)
        }
        function detailCard() { return find("calicataMapDetail").children[1] }
        function insideScreen(item) {
            var p = item.mapToItem(root, 0, 0)
            return p.x >= -0.5 && p.y >= -0.5 && p.x + item.width <= root.width + 0.5 && p.y + item.height <= root.height + 0.5
        }

        // ===================== Carga, filtro y auras (regresión)
        function test_load_eight_projects_single_query() {
            start(); waitIdle()
            compare(root.home.projects.length, 8)
            compare(CalicataCloud.listCalls, 1)
            compare(CalicataCloud.lastListIds.length, 8)
            compare(CalicataCloud.editorListCalls, 0)
            compare(root.home.rows.length, 21)
            compare(root.home.markers.length, 13)
            compare(root.home.loadState, "data")
        }
        function test_load_failing_and_timeout_finish() {
            start("ok", "fail"); waitIdle()
            compare(root.home.loadState, "error")
            compare(root.auraMode(), "error")
            start("silent", "silent", true); waitIdle()
            compare(root.home.loadState, "offline")
            compare(root.auraMode(), "attention")
        }
        function test_filter_updates_cards_and_markers() {
            start(); waitIdle()
            selectProject(1)
            compare(root.home.rows.length, 3)
            compare(root.home.markers.length, 0)
            selectProject(0)
            compare(root.home.rows.length, 18)
            compare(root.home.markers.length, 13)
            selectProject(-1)
            compare(root.home.rows.length, 21)
        }
        function test_aura_states() {
            start(); waitIdle()
            compare(root.auraMode(), "synced")
            aura.mode = root.auraMode(); wait(700)
            verify(aura.children[0].visible && aura.children[1].visible)
            verify(Qt.colorEqual(aura.children[1].tint, S.corporateGreen))
        }
        function test_header_scrolls_out_and_pull_returns() {
            start(); waitIdle()
            var header = find("homeHeader"), flick = find("homeListFlick")
            var y0 = header.mapToItem(root, 0, 0).y
            mouseDrag(flick, 180, 640, 0, -420, Qt.LeftButton, Qt.NoModifier, 10)
            tryVerify(function() { return !flick.moving }, 4000)
            verify(header.mapToItem(root, 0, 0).y + header.height < 0)
            flick.contentY = flick.originY; wait(100)
            var calls = CalicataCloud.refreshCalls
            mousePress(flick, 180, 260)
            for (var i = 1; i <= 12; ++i) mouseMove(flick, 180, 260 + i * 20, 16)
            mouseRelease(flick, 180, 500)
            tryVerify(function() { return CalicataCloud.refreshCalls === calls + 1 }, 2000)
            waitIdle()
            tryVerify(function() { return !flick.moving && Math.abs(header.mapToItem(root, 0, 0).y - y0) < 1 }, 3000)
        }

        // ===================== DEFECTO 1 · Gesto lista -> mapa
        // Contrato definitivo: desde la lista, arrastrar a la IZQUIERDA trae el mapa.
        function test_g01_left_swipe_opens_map_slow_and_fast() {
            start(); waitIdle()
            listSwipe(-200, 0, 300, 12, 40)                       // lento (~0,5 s)
            compare(root.home.view, "map")
            compare(root.map.x, 0)
            root.home.view = "list"; settlePages()
            listSwipe(-160, 0, 300, 3, 5)                         // rápido
            compare(root.home.view, "map")
        }
        function test_g02_map_enters_from_right() {
            start(); waitIdle()
            compare(root.map.x, root.width)
            var list = find("homeListPage")
            mousePress(root, 300, 430)
            for (var i = 1; i <= 8; ++i) mouseMove(root, 300 - i * 25, 430, 20)
            verify(Math.abs(root.home.pagePos - 200 / root.width) < 0.03, "la página no acompañó al dedo: " + root.home.pagePos)
            verify(root.map.x < root.width && root.map.x > 0)     // asoma por la derecha
            mouseRelease(root, 100, 430)
            wait(60)
            verify(root.map.x > 0 && root.map.x < root.width, "map.x=" + root.map.x)   // entra desde la derecha
            verify(list.x < 0)                                    // la lista sale por la izquierda
            compare(list.x + list.width, root.map.x)              // sin hueco entre páginas
            settlePages()
            compare(root.home.view, "map")
        }
        // Desde la lista, arrastrar a la DERECHA no abre el mapa.
        function test_g03_right_swipe_on_list_does_not_open() {
            start(); waitIdle()
            listSwipe(160, 0, 80)
            compare(root.home.view, "list")
            compare(root.home.pagePos, 0)
            compare(root.home.swipeDecision("list", 160, 0, 800, 80, false).reason, "opposite")
        }
        // Gestos cortos, verticales y desde el borde de gestos del sistema: no navegan.
        function test_g04_short_vertical_edge_do_not_navigate() {
            start(); waitIdle()
            listSwipe(-40, 0, 300, 8, 40)                         // corto y lento
            compare(root.home.view, "list")
            listSwipe(-60, -320, 300, 10, 16)                     // vertical
            compare(root.home.view, "list")
            listSwipe(-220, 0, 352, 10, 16)                       // empieza en el borde de Android
            compare(root.home.view, "list")
            compare(root.home.pagePos, 0)
            compare(root.home.swipeDecision("list", -220, 0, -900, 352, false).reason, "system_edge")
            compare(root.home.swipeDecision("list", -220, 0, -900, 300, true).reason, "canceled")
        }
        // Un gesto horizontal iniciado sobre una tarjeta navega sin abrir la ficha.
        function test_g05_swipe_from_card_does_not_open_card() {
            start(); waitIdle()
            var card = find("homeCards").itemAt(1)                // columna derecha
            var p = card.mapToItem(find("homeListFlick"), card.width - 24, card.height / 2)
            listSwipe(-200, 0, p.x, 10, 16)
            compare(root.home.view, "map")
            compare(editorStub.calls.length, 0)
        }
        // Mapa: gesto inverso (izquierda) desde la franja interior vuelve a la lista;
        // derecha desde la franja o paneo del mapa no navegan.
        function test_g06_map_left_swipe_returns_and_pan_does_not() {
            start(); waitIdle(); openMap()
            mapSwipe(-200, 0)                                     // sentido contrario: no vuelve
            compare(root.home.view, "map")
            var lat = root.map.centerLat, lon = root.map.centerLon
            swipe(root.map, 220, 300, -160, 0, 8, 16)             // paneo fuera de la franja
            compare(root.home.view, "map")
            verify(Math.abs(root.map.centerLon - lon) > 1e-9, "el paneo no movió el mapa")
            mapSwipe(0, 160)                                      // vertical en la franja
            compare(root.home.view, "map")
            mapSwipe(180, 0)
            compare(root.home.view, "list")
            compare(root.map.x, root.width)
        }
        // Tabla del contrato definitivo (coordenadas físicas exactas), repetida.
        function test_g11_contract_table() {
            start(); waitIdle()
            for (var i = 0; i < 3; ++i) {
                swipe(find("homeListFlick"), 280, 430, -160, 0, 10, 16)
                compare(root.home.view, "map", "lista 280->120 (" + i + ")")
                mapSwipe(160, 0)
                compare(root.home.view, "list", "mapa 80->240 (" + i + ")")
                swipe(find("homeListFlick"), 300, 430, -150, 0, 10, 16)
                compare(root.home.view, "map", "lista 300->150 (" + i + ")")
                root.home.view = "list"; settlePages()
                swipe(find("homeListFlick"), 80, 430, 160, 0, 10, 16)
                compare(root.home.view, "list", "lista 80->240 (" + i + ")")
            }
            var e = find("homeMapEdge").mapToItem(root.map, 0, 0)
            verify(e.x <= 80 - 40 && e.x + find("homeMapEdge").width >= 80 + 30, "la zona del mapa no cubre x=80")
            swipe(find("homeListFlick"), 300, 520, -170, -120, 10, 20)     // arco de pulgar
            compare(root.home.view, "map", "un arco hacia la izquierda debe abrir el mapa")
        }
        // Apertura: el Home queda listo y muestra «Cargando» sin esperar a la red;
        // la consulta empieza tras la animación de entrada; los datos llegan después.
        function test_o01_home_shown_before_remote() {
            loader.active = false
            CalicataCloud.reset()
            CalicataCloud.serverProjects = eightProjects()
            CalicataCloud.serverRows = serverRows()
            CalicataCloud.delayMs = 200                           // menor que el plazo del Home (300 ms)
            uiStub.marks = []
            uiStub.subAppProgress = 0.2                          // entrada en curso
            loader.active = true
            tryVerify(function() { return root.home !== null }, 2000)
            verify(uiStub.marks.indexOf("HOME_READY") >= 0)
            compare(root.home.loadState, "loading")
            verify(find("homeLoadingText").visible)
            wait(150)
            compare(CalicataCloud.refreshCalls, 0)                // no compite con la animación
            uiStub.subAppProgress = 1
            tryVerify(function() { return CalicataCloud.refreshCalls === 1 }, 1000)
            waitIdle()
            compare(root.home.loadState, "data")
            verify(uiStub.marks.indexOf("DATA_READY") > uiStub.marks.indexOf("HOME_READY"))
            uiStub.subAppProgress = undefined
        }
        // Repetición: diez ciclos lista -> mapa -> lista con gestos reales.
        function test_g07_repeated_cycles() {
            start(); waitIdle()
            for (var i = 0; i < 10; ++i) {
                listSwipe(-(160 + (i % 3) * 20), (i % 2) * 12, 310 - i * 4, i % 2 ? 4 : 10, i % 2 ? 6 : 24)
                compare(root.home.view, "map", "ciclo " + i + ": la izquierda no abrió el mapa")
                mapSwipe(170, 0, i % 2 ? 4 : 10, i % 2 ? 6 : 24)
                compare(root.home.view, "list", "ciclo " + i + ": la derecha no volvió")
            }
        }
        // Lista vacía y cargando: el gesto sigue funcionando.
        function test_g08_empty_and_loading() {
            start(); waitIdle()
            selectProject(2)
            compare(root.home.rows.length, 0)
            listSwipe(-200)
            compare(root.home.view, "map")
            start("silent", "silent")
            root.home.projectsTimeoutMs = 5000
            verify(root.home.loadState === "loading")
            listSwipe(-200)
            compare(root.home.view, "map")
        }
        // Atrás de Android: menú -> mapa -> lista -> salir de la subapp.
        function test_g09_android_back_order() {
            start(); waitIdle(); openMap()
            mouseClick(findChild(root.map, "mapPin_" + root.home.markers[0].key), 16, 16)
            tryVerify(function() { return find("calicataMapDetail").open }, 1000)
            verify(root.home.handleBack())
            verify(!find("calicataMapDetail").open)
            compare(root.home.view, "map")
            verify(root.home.handleBack())
            settlePages()
            compare(root.home.view, "list")
            verify(!root.home.handleBack())
        }
        // Conmutación reiterada: misma instancia de mapa, cámara y filtro intactos.
        function test_g10_switches_keep_camera() {
            start(); waitIdle()
            selectProject(0)
            openMap()
            root.map.setCamera(-12.03, -76.98, 13.4)
            var mapObj = root.map.geoMap
            for (var i = 0; i < 8; ++i) { root.home.view = i % 2 ? "map" : "list"; wait(35) }
            settlePages()
            compare(root.home.view, "map")
            verify(root.map.geoMap === mapObj, "el Map se recreó")
            compare(root.map.zoom.toFixed(3), "13.400")
            compare(root.map.centerLat.toFixed(5), "-12.03000")
            compare(root.home.filterProjectId, pid(1))
        }

        // ===================== DEFECTO 2 · Motor Qt Location sin vacíos
        function test_m01_engine_lazy_and_ready() {
            start(); waitIdle()
            verify(!root.map.everActive)                          // nada se crea durante la entrada
            compare(root.map.geoMap, null)
            openMap()
            verify(root.map.mapReady)
            compare(root.map.mapError, "")
            compare(root.map.geoMap.activeMapType.style, 100)    // MapType.CustomMap (servidor configurado)
            compare(root.map.geoMap.maximumZoomLevel, 17)         // límite real de OpenTopoMap
        }
        // Zoom alternando 3 -> 7 -> 11 -> 15 -> 17 -> 11 -> 3 -> 17 en saltos bruscos:
        // capturas a ~60 ms (en plena carga) y tras asentarse.
        function test_m02_zoom_jumps_keep_coverage() {
            start(); waitIdle(); openMap()
            var seq = [3, 7, 11, 15, 17, 11, 3, 17, 13]
            for (var i = 0; i < seq.length; ++i) {
                var c = root.map._cameraFor(-12.03, -76.98, seq[i])
                root.map.setCamera(c.lat, c.lon, seq[i])
                wait(60)
                coverage("zoom" + seq[i] + "_60ms", 5)
                wait(500)
                coverage("zoom" + seq[i] + "_settled", 1)
            }
        }
        // Zoom continuo (pellizco simulado) arriba y abajo alrededor de un punto.
        function test_m03_continuous_zoom_keeps_coverage() {
            start(); waitIdle(); openMap()
            root.map.setCamera(-12.03, -76.98, 11)
            wait(500)
            for (var z = 11; z <= 16.5; z += 0.25) { root.map.zoomAround(z, 180, 330); wait(16) }
            coverage("pinch_in_end", 5)
            for (var z2 = 16.5; z2 >= 9; z2 -= 0.25) { root.map.zoomAround(z2, 200, 300); wait(16) }
            coverage("pinch_out_end", 5)
            root.map.animateZoomTo(14, 180, 300)                  // doble toque / botones
            wait(300)
            coverage("animated_zoom", 5)
        }
        // Paneo durante la descarga, incluso hacia zonas sin teselas propias (fallo
        // del proveedor): se conserva la cobertura del nivel anterior.
        function test_m04_pan_during_load_and_missing_tiles() {
            start(); waitIdle(); openMap()
            root.map.setCamera(-12.03, -76.98, 12)
            wait(600)
            root.map.setCamera(root.map.centerLat, root.map.centerLon, 15)
            for (var i = 0; i < 12; ++i) { root.map.panBy(-60, 25); wait(20) }
            coverage("pan_while_loading", 5)
            for (var j = 0; j < 20; ++j) { root.map.panBy(-120, 0); wait(16) }
            wait(600)
            coverage("pan_outside_pyramid", 5)                   // z15 inexistente aquí: respaldo del z12
            compare(root.map.mapError, "")
        }
        // Volver desde la lista conserva centro y zoom, y el mapa sigue cubierto.
        function test_m05_return_from_list_keeps_camera_and_tiles() {
            start(); waitIdle(); openMap()
            root.map.setCamera(-12.03, -76.98, 14.2)
            wait(600)
            root.home.view = "list"; settlePages()
            verify(!root.map.running)
            root.home.view = "map"; settlePages()
            wait(60)
            compare(root.map.zoom.toFixed(3), "14.200")
            coverage("return_from_list", 2)
        }

        // ===================== Marcadores y 3D Touch
        function test_k01_marker_opens_correct_detail() {
            start(); waitIdle(); openMap()
            var m = root.home.markers[5]
            root.map.centerOn(m.lat, m.lon, 14); wait(200)
            var pin = findChild(root.map, "mapPin_" + m.key)
            verify(pin)
            mouseClick(pin, 16, 16)
            tryVerify(function() { return find("calicataMapDetail").open }, 1000)
            compare(find("calicataMapDetail").rowKey, m.key)
            compare(find("calicataMapDetail").row.code, m.code)
            wait(700)                                             // intervalo de doble toque del fondo
            verify(find("calicataMapDetail").open, "el fondo cerró el detalle recién abierto")
            mouseClick(root.map, 60, 640)
            tryVerify(function() { return !find("calicataMapDetail").open }, 1500)
        }
        // Posición geográfica: la punta de cada marcador visible coincide con su coordenada.
        function test_k02_markers_on_coordinates() {
            start(); waitIdle(); openMap()
            root.map.fitToMarkers(); wait(300)
            var checked = 0
            for (var i = 0; i < root.home.markers.length; ++i) {
                var m = root.home.markers[i]
                var pin = findChild(root.map, "mapPin_" + m.key)
                verify(pin)
                var tip = pin.mapToItem(root.map, 16, 40)
                var p = root.map.screenPoint(m.lat, m.lon)
                verify(Math.abs(tip.x - p.x) < 1 && Math.abs(tip.y - p.y) < 1, m.code + " desplazado")
                checked++
            }
            compare(checked, 13)
            root.map.bearing = 60; wait(50)
            var m0 = root.home.markers[0], pin0 = findChild(root.map, "mapPin_" + m0.key)
            var t0 = pin0.mapToItem(root.map, 16, 40), p0 = root.map.screenPoint(m0.lat, m0.lon)
            verify(Math.abs(t0.x - p0.x) < 1 && Math.abs(t0.y - p0.y) < 1, "rotación desalineó el marcador")
            root.map.resetNorth()
        }
        // Panel dentro de la pantalla y siguiendo a su marcador.
        function test_k03_detail_inside_screen_and_follows() {
            start(); waitIdle(); openMap()
            var m = root.home.markers[0]
            root.map.centerOn(m.lat, m.lon, 14); wait(200)
            var targets = [[40, 110], [40, root.map.height - root.map.bottomInset - 40], [root.width - 120, 400]]
            for (var i = 0; i < targets.length; ++i) {
                var p = root.map.markerScreenPoint(m.key)
                root.map.panBy(targets[i][0] - p.x, targets[i][1] - p.y)
                wait(50)
                mouseClick(findChild(root.map, "mapPin_" + m.key), 16, 16)
                tryVerify(function() { return find("calicataMapDetail").open }, 1000)
                wait(320)
                verify(insideScreen(detailCard()), "panel fuera de la pantalla en el caso " + i)
                var ax = find("calicataMapDetail").anchorX
                root.map.panBy(12, 0)
                verify(Math.abs(find("calicataMapDetail").anchorX - (ax + 12)) < 0.6, "el panel no siguió al marcador")
                compare(root.map.selectedKey, m.key)
                find("calicataMapDetail").close()
                wait(200)
            }
        }
        function test_k04_gps_without_service_does_not_move_map() {
            start(); waitIdle(); openMap()
            compare(root.map.gpsState, "unavailable")
            var lat = root.map.centerLat, lon = root.map.centerLon
            root.map.centerOnDeviceOrMarkers()
            compare(root.map.centerLat, lat)
            compare(root.map.centerLon, lon)
            verify(root.map.gpsMessage.length > 0)
        }
        function test_icons_registered() {
            start(); waitIdle()
            var names = []
            function walk(it) {
                if (!it) return
                if (it.inactiveOpacity !== undefined && it.name !== undefined && String(it.name).length) names.push(String(it.name))
                if (it.iconName !== undefined && String(it.iconName).length) names.push(String(it.iconName))
                for (var i = 0; i < it.children.length; ++i) walk(it.children[i])
            }
            walk(root.home)
            verify(names.length >= 4)
            for (var n = 0; n < names.length; ++n)
                verify(IconCatalog.has(names[n]), "icono no registrado: " + names[n])
        }
    }
}

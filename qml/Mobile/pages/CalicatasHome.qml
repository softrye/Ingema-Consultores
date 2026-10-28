import QtQuick
import QtQuick.Shapes
import InGe 1.0                                   // singleton CalicataCloud (main_mobile.cpp)
import "../components" as Components
import "../renditions" as Renditions
import "../renditions/RStyle.js" as S
import "../lib/CalicataRules.js" as Rules
import "../lib/CalicataDiagnostics.js" as CalDiag

// Home de Calicatas: lista de calicatas recientes + mapa topográfico.
// Presentación nueva sobre los sistemas reales (sin backend paralelo):
//   remotas  -> CalicataCloud.listHomeCalicatas(ids, serial) (una consulta, fila calicatas)
//   locales  -> CalicataDocument.listDrafts()/listProjectDrafts() (borradores)
//   proyectos-> CalicataCloud.projects (autorizados)
// Abrir y crear usan el editor existente (CalicatasEditorPage). Material,
// menús 3D Touch, balance y deslizar-para-actualizar: los de Rendiciones.
Item {
    id: home
    property var ui
    property var flow
    property var editor                           // CalicatasEditorPage
    readonly property alias mapItem: topoMap
    readonly property real u: ui ? ui.u : 1

    // ------------------------------------------------------------- Estado
    property string view: "list"                  // list | map
    property string filterProjectId: ""
    property var remoteByProject: ({})            // projectId -> filas (no archivadas)
    property var loadErrors: ({})                 // "home" -> mensaje del listado (diagnóstico)
    property string projectsError: ""
    property string listError: ""
    property bool loaded: false                   // hubo al menos un ciclo terminado
    property double lastSuccessfulRefreshMs: 0  // reutiliza datos recientes al navegar
    property bool refreshing: false
    property int revision: 0                      // relee borradores locales
    property string phase: "idle"                 // idle | projects | listing
    property int _serial: 0                       // ciclo vigente; respuestas viejas se ignoran
    property string _listedKey: ""                // proyectos consultados en el último listado

    readonly property bool serviceAvailable: typeof CalicataCloud !== "undefined" && CalicataCloud !== null
    readonly property var projects: serviceAvailable ? (CalicataCloud.projects || []) : []
    function projectIds() {
        return projects.map(function(p) { return String(p.id || "") }).filter(function(s) { return s.length })
    }
    // Estado terminal visible: loading | data | empty | error | offline.
    readonly property string loadState: {
        if (rows.length > 0) return "data"
        if (!loaded) return "loading"
        var err = projectsError.length ? projectsError : listError
        if (err.length) return CalDiag.isOfflineMessage(err) ? "offline" : "error"
        return "empty"
    }
    // Miniaturas de calicatas remotas: calicataId -> url local ("" = sin foto).
    property var covers: ({})
    function coverFor(row) {
        if (!row) return ""
        if (String(row.photoUrl || "").length) return row.photoUrl         // la copia local (pendiente o no) manda
        return String(row.remoteId || "").length ? String(home.covers[row.remoteId] || "") : ""
    }
    function requestCover(row) {
        if (!row || String(row.photoUrl || "").length || !String(row.remoteId || "").length) return
        if (home.covers[row.remoteId] !== undefined || typeof CalicataCloud === "undefined" || !CalicataCloud.requestCalicataCover) return
        CalicataCloud.requestCalicataCover(String(row.projectId), String(row.remoteId))
    }

    function projectById(id) {
        id = String(id || "")
        for (var i = 0; i < projects.length; ++i)
            if (String(projects[i].id || "") === id) return projects[i]
        return null
    }
    function projectLabel(id, fallbackName, fallbackCode) {
        var p = projectById(id)
        var name = p ? String(p.name || p.code || "") : ""
        return name.length ? name : String(fallbackName || fallbackCode || "")
    }
    function _num(v) { var n = Rules.parseDecimalSafe(v); return isFinite(n) ? n : NaN }
    function _geo(lat, lon, utmX, utmY, zone, datum) {
        var la = _num(lat), lo = _num(lon)
        if (!(isFinite(la) && isFinite(lo))) {
            var g = (String(utmX || "").length && String(utmY || "").length)
                    ? Rules.utmToGeoForDatum(utmX, utmY, zone, datum === "PSAD56" ? "PSAD56" : "WGS84") : null
            if (g) { la = g.latitude; lo = g.longitude }
        }
        var ok = isFinite(la) && isFinite(lo) && Math.abs(la) <= 90 && Math.abs(lo) <= 180 && !(la === 0 && lo === 0)
        return ok ? { lat: la, lon: lo } : null
    }
    function _location(progresiva, tramo) {
        var t = String(tramo || "").trim()
        if (t.length) return t
        var pk = String(progresiva || "").trim()
        return pk.length ? "Km " + pk : ""
    }

    // Calicatas reales sin duplicados (fila remota + su borrador local = una).
    readonly property var allRows: {
        var dep = home.revision
        var byKey = {}, out = []
        function put(key, row) { byKey[key] = row; out.push(row) }
        for (var pid in home.remoteByProject) {
            var rows = home.remoteByProject[pid] || []
            for (var i = 0; i < rows.length; ++i) {
                var r = rows[i]
                var rid = String(r.id || "").toLowerCase()
                if (!rid.length || byKey["r:" + rid]) continue
                put("r:" + rid, {
                    key: "r:" + rid, remoteId: rid, instanceId: "", fileUrl: "",
                    code: String(r.code || "").trim(), projectId: String(r.project_id || pid),
                    location: _location(r.progresiva, ""), status: String(r.status || "BORRADOR"),
                    syncState: "SYNCED", geo: _geo(null, null, r.easting, r.northing, r.utm_zone, "WGS84"),
                    altitude: String(r.altitude_m === null || r.altitude_m === undefined ? "" : r.altitude_m),
                    supervisor: String(r.supervisor || ""), startDate: String(r.start_date || ""),
                    observations: String(r.observations || ""), photoUrl: "",
                    updatedMs: Date.parse(String(r.updated_at || r.created_at || "")) || 0
                })
            }
        }
        var probe = home.editor ? home.editor.currentDoc : null
        var drafts = []
        if (probe && probe.listDrafts) drafts = drafts.concat(probe.listDrafts())
        if (probe && probe.listProjectDrafts)
            for (var p = 0; p < projects.length; ++p)
                drafts = drafts.concat(probe.listProjectDrafts(String(projects[p].id || ""), true))
        var seenLocal = {}
        for (var d = 0; d < drafts.length; ++d) {
            var l = drafts[d]
            var lid = String(l.instanceId || "")
            if (!lid.length || seenLocal[lid] || String(l.status || "") === "ARCHIVADO") continue
            seenLocal[lid] = true
            var remote = String(l.remoteCalicataId || "").toLowerCase()
            var existing = remote.length ? byKey["r:" + remote] : null
            if (existing) {                                   // mismo UUID remoto: una sola tarjeta
                existing.instanceId = lid
                existing.fileUrl = String(l.fileUrl || "")
                // La nube no guarda el datum: la copia local (WGS84/PSAD56 real) manda.
                var localGeo = _geo(l.latitude, l.longitude, l.utmX, l.utmY, l.utmZone, String(l.datum || ""))
                if (localGeo) existing.geo = localGeo
                if (String(l.photoUrl || "").length) existing.photoUrl = String(l.photoUrl)
                var ls = String(l.syncState || "")
                if (ls === "PENDING" || ls === "CONFLICT") existing.syncState = ls
                continue
            }
            var code = String(l.code || "").trim()
            if (!code.length && !String(l.projectId || "").length) continue   // pestaña vacía sin datos
            put("l:" + lid, {
                key: "l:" + lid, remoteId: remote, instanceId: lid, fileUrl: String(l.fileUrl || ""),
                code: code, projectId: String(l.projectId || ""),
                projectFallback: String(l.projectName || l.projectCode || ""),
                location: _location(l.progresiva, l.location), status: String(l.status || "BORRADOR"),
                syncState: String(l.syncState || "LOCAL") || "LOCAL",
                geo: _geo(l.latitude, l.longitude, l.utmX, l.utmY, l.utmZone, String(l.datum || "")),
                altitude: String(l.altitudeM || ""), supervisor: String(l.supervisor || ""),
                startDate: String(l.startDate || ""), observations: String(l.observations || ""),
                photoUrl: String(l.photoUrl || ""), updatedMs: Number(l.lastModifiedMs || 0)
            })
        }
        for (var k = 0; k < out.length; ++k)
            out[k].project = projectLabel(out[k].projectId, out[k].projectFallback, "")
        out.sort(function(a, b) { return b.updatedMs - a.updatedMs })
        return out
    }
    readonly property var rows: filterProjectId.length
        ? allRows.filter(function(r) { return r.projectId === home.filterProjectId }) : allRows
    readonly property var markers: rows.filter(function(r) { return !!r.geo }).map(function(r) {
        return { key: r.key, lat: r.geo.lat, lon: r.geo.lon, code: r.code, status: r.status }
    })
    // Avance global: grupos explícitos del ciclo de vida real (statusTransitionsFrom):
    //   BORRADOR -> EN_REVISION -> OBSERVADO | REVISADO -> APROBADO -> EXPORTADO
    //   Aprobadas   = APROBADO + EXPORTADO (EXPORTADO solo se alcanza desde APROBADO)
    //   En revisión = EN_REVISION + REVISADO (revisada, aún sin aprobar)
    //   Observadas  = OBSERVADO;  Borrador = BORRADOR (y cualquier otro valor, igual
    //   que canonicalStatus del servidor). ARCHIVADO no se lista ni cuenta.
    // Los cuatro grupos suman exactamente el total: un único denominador.
    readonly property var statusGroups: ({ APROBADO: "APROBADO", EXPORTADO: "APROBADO",
                                            EN_REVISION: "EN_REVISION", REVISADO: "EN_REVISION",
                                            OBSERVADO: "OBSERVADO", BORRADOR: "BORRADOR" })
    readonly property var statusCounts: {
        var c = { total: allRows.length, APROBADO: 0, EN_REVISION: 0, OBSERVADO: 0, BORRADOR: 0 }
        for (var i = 0; i < allRows.length; ++i)
            c[home.statusGroups[allRows[i].status] || "BORRADOR"] += 1
        return c
    }
    // Estado para las auras del Home (lo consume CalicatasEditorPage).
    // Solo fichas que SÍ pueden sincronizar (proyecto + código) y aún no lo hicieron:
    // un borrador sin proyecto o sin código no debe dejar el aura en gris para siempre.
    readonly property int localPendingCount: allRows.filter(function(r) {
        return (r.syncState === "LOCAL" || r.syncState === "PENDING")
               && String(r.projectId || "").length > 0 && String(r.code || "").length > 0
    }).length
    readonly property int conflictCount: allRows.filter(function(r) { return r.syncState === "CONFLICT" }).length
    readonly property var failedProjects: Object.keys(loadErrors)
    readonly property int remoteCount: allRows.filter(function(r) { return r.key.indexOf("r:") === 0 }).length
    readonly property int localCount: allRows.length - remoteCount

    function rowByKey(key) {
        for (var i = 0; i < allRows.length; ++i) if (allRows[i].key === key) return allRows[i]
        return null
    }
    function statusLabel(s) {
        return ({ BORRADOR: "Borrador", EN_REVISION: "En revisión", OBSERVADO: "Observado", REVISADO: "Revisado",
                  APROBADO: "Aprobado", EXPORTADO: "Exportado", ARCHIVADO: "Archivado" })[s] || s
    }
    function dateLabel(iso) {
        var s = String(iso || "")
        return /^\d{4}-\d{2}-\d{2}/.test(s) ? s.substring(8, 10) + "/" + s.substring(5, 7) + "/" + s.substring(0, 4) : s
    }
    function haptic(kind) {
        if (home.flow && typeof home.flow.triggerHaptic === "function") home.flow.triggerHaptic(kind || "light")
    }

    // ------------------------------------------------ Carga y actualización
    // Un ciclo = proyectos autorizados (refreshProjects -> projectsLoaded |
    // projectsLoadFailed | 12 s) + UNA consulta de calicatas de todos ellos
    // (listHomeCalicatas -> homeCalicatasLoaded | homeCalicatasLoadFailed | 15 s).
    // Siempre termina (loaded = true) y nunca vacía lo ya listado ante un error.
    readonly property string timeoutPrefix: "Tiempo de espera agotado"
    property int projectsTimeoutMs: 12000
    property int listTimeoutMs: 15000
    function _trace(msg) { console.info("INGE_CALICATA_HOME_" + msg) }
    function refresh() {
        if (!serviceAvailable) {                   // error visible, no «Cargando» eterno
            projectsError = "El servicio de Calicatas no está disponible."
            refreshing = false; phase = "idle"; loaded = true
            _trace("LOAD_ABORT reason=service_unavailable")
            return
        }
        if (refreshing) return
        refreshing = true
        phase = "projects"
        _serial++
        revision++
        _trace("PROJECTS_START serial=" + _serial + " cached=" + projects.length)
        stepTimer.interval = projectsTimeoutMs
        stepTimer.restart()
        CalicataCloud.refreshProjects()            // puede responder en el acto (sin sesión)
    }
    function _projectsDone(error) {
        if (phase !== "projects") return
        projectsError = String(error || "")
        _trace("PROJECTS_END serial=" + _serial + " count=" + projects.length
               + (projectsError.length ? " error=1" : ""))
        _list()
    }
    function _list() {
        phase = "listing"
        var ids = projectIds()
        _listedKey = ids.slice().sort().join(",")
        if (!ids.length) {                         // sin proyectos autorizados: nada remoto
            remoteByProject = ({})
            _finish("")
            return
        }
        _trace("LIST_START serial=" + _serial + " projects=" + ids.length)
        stepTimer.interval = listTimeoutMs
        stepTimer.restart()
        CalicataCloud.listHomeCalicatas(ids, _serial)
    }
    function _finish(error) {
        stepTimer.stop()
        listError = String(error || "")
        loadErrors = listError.length ? ({ home: listError }) : ({})
        phase = "idle"
        refreshing = false
        loaded = true
        if (!listError.length && !projectsError.length)
            lastSuccessfulRefreshMs = Date.now()
        revision++
        if (filterProjectId.length && projects.length && !projectById(filterProjectId)) filterProjectId = ""
        if (ui && ui.calicatasMark) ui.calicatasMark("DATA_READY rows=" + rows.length)
        _trace("LIST_END serial=" + _serial + " remote=" + remoteCount + " local=" + localCount
               + " state=" + loadState + (listError.length ? " error=1" : ""))
        // Cambió la lista de proyectos mientras se listaba: un listado más.
        if (projectIds().slice().sort().join(",") !== _listedKey) Qt.callLater(home._relist)
    }
    function _relist() {
        if (refreshing || !serviceAvailable) return
        refreshing = true
        _serial++
        _trace("RELIST serial=" + _serial)
        _list()
    }
    Timer {                                        // una consulta colgada no bloquea el Home
        id: stepTimer
        onTriggered: {
            if (home.phase === "projects")         // sigue con los proyectos en caché
                home._projectsDone(home.timeoutPrefix + " al consultar tus proyectos.")
            else if (home.phase === "listing")
                home._finish(home.timeoutPrefix + " al listar las calicatas.")
        }
    }
    Connections {
        target: home.serviceAvailable ? CalicataCloud : null
        ignoreUnknownSignals: true
        function onProjectsLoaded(count) { home._projectsDone("") }
        function onProjectsLoadFailed(message) { home._projectsDone(String(message || "No se pudieron cargar los proyectos.")) }
        // Cambio de cuenta o refresco hecho por el editor con otro conjunto de proyectos.
        function onProjectsChanged() {
            if (home.refreshing || !home.loaded) return
            if (home.projectIds().slice().sort().join(",") !== home._listedKey) Qt.callLater(home._relist)
        }
        function onHomeCalicatasLoaded(serial, rows) {
            if (serial !== home._serial || home.phase !== "listing") return
            var m = {}
            var list = rows || []
            for (var i = 0; i < list.length; ++i) {
                var pid = String(list[i].project_id || "").toLowerCase()
                if (!pid.length) continue
                if (!m[pid]) m[pid] = []
                m[pid].push(list[i])
            }
            home.remoteByProject = m
            home._finish("")
        }
        function onHomeCalicatasLoadFailed(serial, message) {
            if (serial !== home._serial || home.phase !== "listing") return
            home._finish(String(message || "No se pudieron listar las calicatas."))
        }
        function onCalicataCoverReady(calicataId, localUrl) {
            var next = Object.assign({}, home.covers)
            next[String(calicataId).toLowerCase()] = localUrl && localUrl.toString ? localUrl.toString() : ""
            home.covers = next
        }
    }
    // Entrada desde el Home general: la carga (red + lectura de borradores) espera a
    // que termine la transición de la subapp, como Rendiciones, para no competir
    // con sus primeros fotogramas.
    readonly property bool settled: !ui || ui.subAppProgress === undefined || ui.subAppProgress >= 0.999
    property bool _refreshPending: false
    function requestRefresh() {
        if (settled) refresh()
        else _refreshPending = true
    }
    onSettledChanged: if (settled && _refreshPending) { _refreshPending = false; refresh() }
    Component.onCompleted: { if (ui && ui.calicatasMark) ui.calicatasMark("HOME_READY"); Qt.callLater(home.requestRefresh) }
    // Reabrir la subapp no debe repetir consultas recientes; el refresh manual
    // sigue disponible mediante refresh() y no usa este limite.
    onVisibleChanged: if (visible && !refreshing && loaded) {
        revision++                   // borradores locales editados siempre frescos
        if (!lastSuccessfulRefreshMs || Date.now() - lastSuccessfulRefreshMs >= 30000)
            requestRefresh()
    }
    onFilterProjectIdChanged: Qt.callLater(function() { home._trace("FILTER selected=" + (filterProjectId.length ? "project" : "todos")
                                     + " rows=" + home.rows.length + " markers=" + home.markers.length) })
    onViewChanged: {
        _trace("VIEW view=" + view + " rows=" + rows.length + " markers=" + markers.length)
        _animatePages()
    }

    // ------------------------------------------------------ Navegación
    function openRow(row) {
        if (!row || !home.editor) return
        closeMenus()
        home.editor.openHomeRow(row)
    }
    function closeMenus() {
        filterMenu.close(); cardMenu.close(); detailMenu.close()
        balanceMenu.close(); createMenu.close(); openMenu.close()
    }
    function anyMenuOpen() {
        return filterMenu.open || cardMenu.open || detailMenu.open || balanceMenu.open || createMenu.open || openMenu.open
    }
    function handleBack() {
        if (anyMenuOpen()) { closeMenus(); return true }
        if (view === "map") { view = "list"; return true }
        return false
    }
    // Celda [index] del Dock global (misma geometría que Rendiciones).
    function dockCellPoint(index) {
        var dock = home.editor ? home.editor.dockAnchor : null
        if (dock && home.ui) {
            var slots = home.ui.dockSlots !== undefined && home.ui.dockSlots ? home.ui.dockSlots.length : 4
            var cell = home.ui.dockCellWidth !== undefined ? home.ui.dockCellWidth : dock.width / slots
            return dock.mapToItem(home, dock.width / 2 + (index - (slots - 1) / 2) * (cell + 1), 0)
        }
        return Qt.point(width / 2, height - (home.ui ? (home.ui.dockBottom || 0) + (home.ui.dockHeight || 0) : 96))
    }
    function _toggle(menu, index) {
        var open = !menu.open
        closeMenus()
        if (!open) return
        var p = dockCellPoint(index)
        menu.anchorX = p.x; menu.anchorY = p.y
        haptic("light")
        menu.open = true
    }
    function toggleBalance() { _toggle(balanceMenu, 0) }
    function toggleCreate() { if (!createMenu.open) createMenu.reset(); _toggle(createMenu, 1) }
    function toggleOpen() { _toggle(openMenu, 2) }

    // ------------------------------------------------- Páginas: lista · mapa
    // Un solo estado de navegación para las dos páginas: pagePos 0 = lista,
    // 1 = mapa. El mapa está a la DERECHA de la lista: entra desde la derecha y
    // la lista sale por la izquierda, con la misma interpolación (lista.x y
    // mapa.x salen del mismo pagePos: nunca hay huecos ni páginas sueltas).
    //
    // Gesto (contrato definitivo): el mapa está a la DERECHA y se trae con el dedo.
    //   Lista -> Mapa: arrastrar hacia la IZQUIERDA (dx < 0) desde la zona interior.
    //   Mapa -> Lista: arrastrar hacia la DERECHA (dx > 0) desde la franja interior
    //   izquierda del mapa (el resto del mapa es paneo).
    // Las páginas acompañan al dedo mientras el gesto es horizontal; al soltar se
    // decide (distancia o lanzamiento) y la animación completa o devuelve la página.
    // Corto, vertical, contrario, cancelado por el sistema o iniciado en un borde
    // de gestos de Android: no navega y la página vuelve a su sitio.
    property real pagePos: 0
    readonly property real swipeDistance: 56 * u                 // umbral de distancia
    readonly property real swipeFlingVelocity: 650 * u           // o lanzamiento rápido (px/s)
    readonly property real systemEdge: 34 * u                    // borde de gestos de Android (~32 dp)
    readonly property bool reducedMotion: !!editor && editor.flowReduceMotion === true
    function _animatePages() {
        var to = view === "map" ? 1 : 0
        pageAnim.stop()
        if (reducedMotion || Math.abs(pagePos - to) < 0.001) { pagePos = to; return }
        pageAnim.from = pagePos
        pageAnim.to = to
        pageAnim.duration = Math.round(160 + 200 * Math.abs(to - pagePos))     // lo que falta recorrer
        _trace("PAGE_ANIM_START from=" + (to === 1 ? "list" : "map") + " to=" + view + " pos=" + pagePos.toFixed(2))
        pageAnim.start()
    }
    NumberAnimation {
        id: pageAnim
        target: home; property: "pagePos"
        easing.type: Easing.OutCubic
        onFinished: home._trace("PAGE_ANIM_END page=" + home.view)
    }
    // Decisión al soltar. startX en coordenadas de esta página.
    function swipeDecision(fromPage, dx, dy, vx, startX, canceled) {
        var dir = dx > 0 ? "right" : dx < 0 ? "left" : "none"
        var wanted = fromPage === "list" ? dx < 0 : dx > 0
        var horizontal = Math.abs(dx) > Math.abs(dy)
        var far = Math.abs(dx) >= swipeDistance
        var fling = Math.abs(vx) >= swipeFlingVelocity && Math.abs(dx) >= 24 * u && (vx > 0) === (dx > 0)
        var edge = fromPage === "list" && (startX < systemEdge || startX > width - systemEdge)
        var reason = canceled ? "canceled" : edge ? "system_edge" : !horizontal ? "vertical"
                   : !wanted ? "opposite" : !(far || fling) ? "short" : "ok"
        return { dir: dir, commit: reason === "ok", reason: reason,
                 target: reason === "ok" ? (fromPage === "list" ? "map" : "list") : fromPage }
    }
    property bool pageTracking: false
    function _pageTrack(fromPage, dx, dy, startX) {
        if (home.view !== fromPage) return
        if (fromPage === "list" && (startX < systemEdge || startX > width - systemEdge)) return
        if (!pageTracking) {
            if (Math.abs(dx) <= Math.abs(dy) || Math.abs(dx) < 12 * u) return   // aún no es horizontal
            pageTracking = true
            pageAnim.stop()
            closeMenus()
        }
        var p = fromPage === "list" ? Math.max(0, -dx) / width : 1 - Math.max(0, dx) / width
        pagePos = Math.max(0, Math.min(1, p))
    }
    function _pageSwipeEnd(fromPage, dx, dy, vx, startX, canceled) {
        var tracked = pageTracking
        pageTracking = false
        if (home.view !== fromPage) { if (tracked) _animatePages(); return }
        var d = swipeDecision(fromPage, dx, dy, vx, startX, canceled)
        _trace("SWIPE dir=" + d.dir + " from=" + fromPage + " to=" + d.target + " commit=" + d.commit
               + " reason=" + d.reason + " startX=" + Math.round(startX) + " endX=" + Math.round(startX + dx)
               + " dx=" + Math.round(dx) + " dy=" + Math.round(dy) + " vx=" + Math.round(vx))
        if (d.commit) { closeMenus(); view = d.target }               // onViewChanged anima desde pagePos
        else if (tracked) _animatePages()                             // vuelve suavemente
    }
    component PageSwipe: DragHandler {
        id: swipe
        property string fromPage: "list"
        property real dx: 0
        property real dy: 0
        property real vx: 0
        property real startX: 0
        property bool wasCanceled: false
        target: null
        xAxis.enabled: true
        yAxis.enabled: false
        // Se mide con el centroide desde el toque: un gesto rápido activa el
        // handler en su último movimiento y translation no llega a avanzar.
        // Desplazamiento del dedo en coordenadas del Home (fijas). El toque se
        // registra aquí mismo: pressPosition/scenePressPosition del centroide se
        // recalculan con la página ya desplazada y exageraban el gesto (×3) cuando
        // la página sigue al dedo.
        property real pressHomeX: NaN
        property real pressHomeY: NaN
        function _homePoint() { return parent ? parent.mapToItem(home, centroid.position.x, centroid.position.y) : Qt.point(0, 0) }
        onCentroidChanged: {
            if (!active && centroid.position.x === centroid.pressPosition.x
                    && centroid.position.y === centroid.pressPosition.y) {
                var p0 = _homePoint()                            // al tocar
                pressHomeX = p0.x; pressHomeY = p0.y
                startX = centroid.pressPosition.x                // en la página: bordes de Android
                return
            }
            if (!isFinite(pressHomeX)) return
            var p = _homePoint()
            dx = p.x - pressHomeX
            dy = p.y - pressHomeY
            if (centroid.velocity.x !== 0) vx = centroid.velocity.x
            if (active) home._pageTrack(fromPage, dx, dy, startX)
        }
        onCanceled: wasCanceled = true                       // Atrás del sistema u otro dueño del gesto
        onActiveChanged: {
            if (active) { wasCanceled = false; home._pageTrack(fromPage, dx, dy, startX); return }
            // El aviso de cancelación puede llegar justo después de desactivarse.
            var f = fromPage, x = dx, y = dy, v = vx, sx = startX
            dx = 0; dy = 0; vx = 0
            Qt.callLater(function() { home._pageSwipeEnd(f, x, y, v, sx, swipe.wasCanceled); swipe.wasCanceled = false })
        }
    }
    // Indicador de páginas (refleja la posición real, también durante la animación).
    component PageDots: Row {
        spacing: 8 * home.u
        Repeater {
            model: ["list", "map"]
            delegate: Rectangle {
                required property string modelData
                required property int index
                readonly property real weight: index === 1 ? home.pagePos : 1 - home.pagePos
                width: (8 + 14 * weight) * home.u
                height: 8 * home.u
                radius: height / 2
                color: weight > 0.5 ? S.corporateBlue : S.ink(0.18)
                MouseArea { anchors.fill: parent; anchors.margins: -10 * home.u; onClicked: home.view = parent.modelData }
                Accessible.role: Accessible.Button
                Accessible.name: modelData === "list" ? "Ver lista" : "Ver mapa"
            }
        }
    }

    // ---------------------------------------------- Vista 1 · Lista reciente
    // Mismo contrato que RenditionsHome: el título forma parte del Flickable, sube
    // con las tarjetas, acompaña el rebote y el Pull-to-Refresh, y sale por arriba.
    Item {
        id: listView
        objectName: "homeListPage"
        width: parent.width
        height: parent.height
        x: -home.pagePos * width
        visible: home.pagePos < 0.999

        readonly property real pullThreshold: 76 * home.u
        readonly property real pull: Math.max(0, flick.originY - flick.contentY - flick.topMargin)

        Flickable {
            id: flick
            objectName: "homeListFlick"
            anchors.fill: parent
            contentWidth: width
            contentHeight: panel.y + panel.height
            boundsBehavior: Flickable.DragOverBounds
            // Mientras actualiza, la lista deja un hueco superior para el indicador.
            topMargin: home.refreshing ? 56 * home.u : 0
            Behavior on topMargin { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
            clip: true
            // Al terminar de actualizar el hueco del indicador se cierra, pero el
            // Flickable no corrige solo su contentY: sin esto la cabecera quedaba
            // 56 px más abajo (franja superior permanente).
            Timer {
                id: settleTop
                interval: 240                            // tras la animación de topMargin
                onTriggered: {
                    if (flick.dragging) return
                    if (flick.moving) { settleTop.restart(); return }       // rebote en curso
                    if (flick.contentY < flick.originY - flick.topMargin - 0.5) flick.returnToBounds()
                }
            }
            Connections {
                target: home
                function onRefreshingChanged() { if (!home.refreshing) settleTop.restart() }
            }
            // El Flickable puede rebotar antes de notificar dragEnded. Registrar
            // el máximo desplazamiento observado mientras el dedo arrastra evita
            // perder actualizaciones válidas en dispositivos Android lentos.
            property real maxPullDuringDrag: 0
            onDragStarted: maxPullDuringDrag = 0
            onMovementEnded: if (!home.refreshing) settleTop.restart()
            // Traza del encabezado desplazable: solo al salir o volver a entrar.
            readonly property bool headerOut: contentY > header.y + header.height
            onHeaderOutChanged: home._trace("HEADER state=" + (headerOut ? "scrolled_out" : "visible"))
            onContentYChanged: {
                if (dragging) maxPullDuringDrag = Math.max(maxPullDuringDrag, listView.pull)
            }
            onDragEnded: {
                var completed = Math.max(maxPullDuringDrag, listView.pull) >= listView.pullThreshold
                maxPullDuringDrag = 0
                if (completed && !home.refreshing) { home.haptic("light"); home._trace("PULL_REFRESH"); home.refresh() }
            }

            Column {                                     // cabecera desplazable
                id: header
                objectName: "homeHeader"
                width: parent.width
                y: (home.ui ? home.ui.topInset : 0) + 22 * home.u
                spacing: 8 * home.u
                Text {
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    text: "Calicatas"
                    color: S.text
                    font.family: home.ui ? home.ui.fontFamily : ""
                    font.pixelSize: 40 * home.u
                    font.weight: Font.Bold
                    font.letterSpacing: -1 * home.u
                }
                PageDots { anchors.horizontalCenter: parent.horizontalCenter }
            }

            Rectangle {                                  // panel de vidrio (deja ver las auras)
                id: panel
                x: 12 * home.u
                width: parent.width - 24 * home.u
                y: header.y + header.height + 24 * home.u
                // Reserva final = Dock flotante + respiro (como Rendiciones).
                height: Math.max(column.height + 22 * home.u + (home.ui ? home.ui.dockArea : 96) + 12 * home.u,
                                 flick.height - y + 30 * home.u)
                radius: 30 * home.u
                color: S.glass(0.38)
                border.width: 1
                border.color: S.edge(0.95)
            }

            Column {
                id: column
                x: panel.x + 16 * home.u
                width: panel.width - 32 * home.u
                y: panel.y + 18 * home.u
                spacing: 14 * home.u

                Item {
                    width: parent.width
                    height: 44 * home.u
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: "Calicatas recientes"
                        color: S.text
                        opacity: 0.72
                        font.family: home.ui ? home.ui.fontFamily : ""
                        font.pixelSize: 21 * home.u
                    }
                    Rectangle {                          // filtro (3D Touch)
                        id: filterButton
                        objectName: "homeFilterButton"
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        width: 44 * home.u; height: width; radius: width / 2
                        color: filterTap.pressed ? S.glass(0.98) : S.glass(0.82)
                        border.width: 1
                        border.color: home.filterProjectId.length ? S.corporateBlue : S.ink(0.06)
                        scale: filterTap.pressed ? 0.94 : 1
                        Behavior on scale { NumberAnimation { duration: 120 } }
                        Components.FlowIcon {
                            anchors.centerIn: parent
                            width: 22 * home.u; height: width
                            name: "project.current"           // registrado en IconCatalog
                            flow: home.flow
                            tintColor: home.filterProjectId.length ? S.corporateBlue : S.navy
                            activeTintColor: S.corporateBlue
                            onDark: S.dark
                            inactiveOpacity: 1
                        }
                        MouseArea {
                            id: filterTap
                            anchors.fill: parent
                            anchors.margins: -6 * home.u
                            onClicked: {
                                if (filterMenu.open) { filterMenu.close(); return }
                                home.closeMenus()
                                var p = filterButton.mapToItem(home, filterButton.width / 2, filterButton.height)
                                filterMenu.anchorX = p.x - 100 * home.u
                                filterMenu.anchorY = p.y
                                home.haptic("light")
                                filterMenu.open = true
                            }
                        }
                        Accessible.role: Accessible.Button
                        Accessible.name: "Filtrar por proyecto"
                    }
                }
                Text {                                   // filtro activo
                    width: parent.width
                    visible: home.filterProjectId.length > 0
                    text: home.projectLabel(home.filterProjectId, "", "")
                    color: S.corporateBlue
                    elide: Text.ElideRight
                    font.family: home.ui ? home.ui.fontFamily : ""
                    font.pixelSize: 14 * home.u
                }
                Text {
                    objectName: "homeLoadingText"
                    width: parent.width
                    visible: home.loadState === "loading"
                    horizontalAlignment: Text.AlignHCenter
                    text: "Cargando tus calicatas…"
                    color: S.muted
                    font.family: home.ui ? home.ui.fontFamily : ""
                    font.pixelSize: 15 * home.u
                }
                Text {
                    objectName: "homeStateText"
                    width: parent.width
                    visible: home.loadState === "empty" || home.loadState === "error" || home.loadState === "offline"
                    topPadding: 24 * home.u
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.WordWrap
                    text: CalDiag.isHomeTimeout(home.projectsError.length ? home.projectsError : home.listError)
                          ? "El servidor no respondió a tiempo. Desliza hacia abajo para reintentar."
                          : home.loadState === "offline"
                          ? "Sin conexión. No se pudieron consultar tus calicatas en el servidor; desliza hacia abajo para reintentar."
                          : home.loadState === "error"
                          ? "No se pudieron cargar tus calicatas. Desliza hacia abajo para reintentar."
                          : home.filterProjectId.length ? "No hay calicatas en este proyecto."
                          : "Aún no hay calicatas. Crea la primera con el botón +."
                    color: S.muted
                    font.family: home.ui ? home.ui.fontFamily : ""
                    font.pixelSize: 15 * home.u
                }
                Grid {
                    id: cards
                    width: parent.width
                    columns: 2
                    columnSpacing: 12 * home.u
                    rowSpacing: 12 * home.u
                    readonly property real cellW: (width - columnSpacing) / 2
                    Repeater {
                        objectName: "homeCards"
                        // Las celdas de dos columnas tienen siempre el mismo ancho.
                        // El elemento impar de ancho completo va FUERA del Grid para
                        // que Qt Grid no lo desplace ni produzca una tercera columna.
                        model: home.rows.length % 2 ? home.rows.slice(0, -1) : home.rows
                        delegate: CalicataCard {
                            required property var modelData
                            required property int index
                            row: modelData
                            wide: false
                            width: cards.cellW
                        }
                    }
                }
                CalicataCard {
                    visible: home.rows.length % 2 === 1
                    row: home.rows.length ? home.rows[home.rows.length - 1] : ({})
                    wide: true
                    width: column.width
                }
            }
        }

        // Indicador de actualización (mismo de Rendiciones).
        Item {
            objectName: "homeRefreshIndicator"
            width: 34 * home.u; height: width
            anchors.horizontalCenter: parent.horizontalCenter
            y: home.refreshing ? (home.ui ? home.ui.topInset : 0) + 14 * home.u
                               : (home.ui ? home.ui.topInset : 0) - 30 * home.u + Math.min(listView.pull, listView.pullThreshold) * 0.6
            opacity: home.refreshing ? 1 : Math.min(1, listView.pull / listView.pullThreshold)
            visible: opacity > 0.01
            z: 5
            Behavior on opacity { enabled: !flick.dragging; NumberAnimation { duration: 220 } }
            Behavior on y { enabled: !flick.dragging; NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
            Rectangle { anchors.fill: parent; radius: width / 2; color: S.glass(1); border.width: 1; border.color: S.ink(0.06) }
            Item {                                       // giro del gesto (antes de soltar)
                anchors.fill: parent
                anchors.margins: 8 * home.u
                rotation: home.refreshing ? 0 : listView.pull * 3
                Shape {                                  // giro continuo mientras actualiza
                    anchors.fill: parent
                    RotationAnimator on rotation { from: 0; to: 360; duration: 900; loops: Animation.Infinite; running: home.refreshing && home.visible }
                    ShapePath {
                        strokeColor: S.corporateBlue
                        strokeWidth: 3 * home.u
                        fillColor: "transparent"
                        capStyle: ShapePath.RoundCap
                        PathAngleArc {
                            centerX: 9 * home.u; centerY: 9 * home.u
                            radiusX: 7.5 * home.u; radiusY: 7.5 * home.u
                            startAngle: -90
                            sweepAngle: home.refreshing ? 280 : 300 * Math.min(1, listView.pull / listView.pullThreshold)
                        }
                    }
                }
            }
        }
        // Deslizar a la IZQUIERDA trae el mapa desde la derecha. Cubre toda la página
        // (también vacía o cargando); el vertical sigue en el Flickable y, si el
        // gesto se vuelve horizontal, el handler toma el toque y la tarjeta no se abre.
        // Una vez reconocido como horizontal, ni el Flickable (por una leve deriva
        // vertical) ni una tarjeta se lo quitan; el sistema aún puede cancelarlo.
        PageSwipe { id: listSwipe; objectName: "homeListSwipe"; fromPage: "list"
                    grabPermissions: PointerHandler.CanTakeOverFromAnything | PointerHandler.ApprovesCancellation }
    }

    // ------------------------------------------- Vista 2 · Mapa topográfico
    // Ocupa toda la pantalla (sin franja fija de título). Solo pide teselas
    // mientras se ve o entra (active), y conserva las listas al volver a la lista.
    CalicatasTopoMap {
        id: topoMap
        objectName: "homeMapPage"
        width: parent.width
        height: parent.height
        x: (1 - home.pagePos) * width
        visible: home.pagePos > 0.001
        active: visible
        ui: home.ui
        flow: home.flow
        markers: home.markers
        selectedKey: detailMenu.open ? detailMenu.rowKey : ""
        bottomInset: home.ui ? home.ui.dockArea : 96
        property bool fitted: false
        onVisibleChanged: if (visible && !fitted) { fitted = true; Qt.callLater(topoMap.fitToMarkers) }
        // Los resultados del filtro y de la nube llegan de forma asíncrona.
        // Nunca conservar el encuadre del filtro anterior cuando cambia la selección.
        onMarkersChanged: {
            if (home.view === "map" && visible)
                Qt.callLater(topoMap.fitToMarkers)
        }
        onMarkerTapped: function(marker, x, y) {
            home.closeMenus()
            detailMenu.rowKey = marker.key
            home._placeDetail()
            home.haptic("light")
            home._trace("MARKER_SELECT found=" + (home.rowByKey(marker.key) ? 1 : 0))
            detailMenu.open = true
        }
        onBackgroundTapped: detailMenu.close()
        // El detalle acompaña a su marcador durante paneo, zoom y rotación.
        onCenterLatChanged: if (detailMenu.open) home._placeDetail()
        onCenterLonChanged: if (detailMenu.open) home._placeDetail()
        onZoomChanged: if (detailMenu.open) home._placeDetail()
        onBearingChanged: if (detailMenu.open) home._placeDetail()

        // Cabecera compacta flotante: título e indicador sin ocupar el mapa.
        Rectangle {
            objectName: "homeMapHeader"
            anchors.horizontalCenter: parent.horizontalCenter
            y: (home.ui ? home.ui.topInset : 0) + 10 * home.u
            width: mapHeaderRow.width + 28 * home.u
            height: 40 * home.u
            radius: height / 2
            color: S.glass(0.86)
            border.width: 1
            border.color: S.ink(0.06)
            Row {
                id: mapHeaderRow
                anchors.centerIn: parent
                spacing: 12 * home.u
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "Calicatas"
                    color: S.text
                    font.family: home.ui ? home.ui.fontFamily : ""
                    font.pixelSize: 17 * home.u
                    font.weight: Font.DemiBold
                }
                PageDots { anchors.verticalCenter: parent.verticalCenter }
            }
        }
        // Deslizar a la DERECHA vuelve a la lista: franja interior izquierda, fuera
        // del borde de gestos del sistema Android (el resto del mapa es paneo).
        // Atrás del sistema también vuelve a la lista.
        Item {
            objectName: "homeMapEdge"
            anchors.left: parent.left
            anchors.leftMargin: 40 * home.u                           // fuera del borde de gestos de Android
            y: (home.ui ? home.ui.topInset : 0) + 300 * home.u
            width: 72 * home.u
            height: Math.max(0, parent.height - y - topoMap.bottomInset - 150 * home.u)
            // El Map de Qt Location toma el toque que pasa por debajo: una vez activo,
            // el gesto de página no se deja quitar (el sistema aún puede cancelarlo).
            PageSwipe { id: mapSwipe; objectName: "homeMapSwipe"; fromPage: "map"
                        grabPermissions: PointerHandler.CanTakeOverFromAnything | PointerHandler.ApprovesCancellation }
        }
    }
    // Detalle del marcador: sobre la gota si hay espacio arriba; si no, debajo.
    // Si el marcador sale del mapa visible, el detalle se cierra.
    function _placeDetail() {
        var p = topoMap.markerScreenPoint(detailMenu.rowKey)
        if (!p || p.x < 0 || p.y < 0 || p.x > topoMap.width || p.y > topoMap.height - topoMap.bottomInset * 0.5) {
            if (detailMenu.open) { _trace("MARKER_DETAIL_CLOSE reason=offscreen"); detailMenu.close() }
            return
        }
        var a = topoMap.mapToItem(home, p.x, p.y)
        detailMenu.above = a.y > home.height * 0.5
        detailMenu.anchorX = a.x
        detailMenu.anchorY = detailMenu.above ? a.y - 6 * home.u : a.y + 44 * home.u
    }

    // ------------------------------------------------------- Tarjeta
    component CalicataCard: Rectangle {
        id: card
        property var row: ({})
        property bool wide: false
        height: wide ? 124 * home.u : 186 * home.u
        radius: 22 * home.u
        color: S.dark ? (tap.pressed ? Qt.rgba(24 / 255, 30 / 255, 44 / 255, 0.78) : Qt.rgba(12 / 255, 16 / 255, 26 / 255, 0.62))
                      : (tap.pressed ? S.lite(247, 249, 252, 0.95) : S.glass(0.90))
        border.width: 1
        border.color: S.dark ? Qt.rgba(1, 1, 1, 0.12) : S.ink(0.05)
        scale: tap.pressed ? 0.98 : 1
        Behavior on scale { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
        Rectangle { z: -1; anchors.fill: parent; anchors.topMargin: 6 * home.u; anchors.margins: -1; radius: card.radius
                    color: S.dark ? Qt.rgba(0, 0, 0, 0.35) : S.ink(0.045) }
        Rectangle {                                       // brillo superior del vidrio oscuro
            visible: S.dark
            anchors.fill: parent; anchors.margins: 1; radius: card.radius - 1
            gradient: Gradient {
                GradientStop { position: 0.0; color: Qt.rgba(1, 1, 1, 0.10) }
                GradientStop { position: 0.45; color: Qt.rgba(1, 1, 1, 0.0) }
            }
        }
        MouseArea { id: tap; anchors.fill: parent; onClicked: home.openRow(card.row) }
        readonly property string photoSource: home.coverFor(card.row)
        Component.onCompleted: home.requestCover(card.row)
        onRowChanged: home.requestCover(card.row)

        Rectangle {                                       // fotografía real o marcador neutro
            id: photo
            x: 12 * home.u; y: 12 * home.u
            width: card.wide ? 118 * home.u : 96 * home.u
            height: card.wide ? card.height - 24 * home.u : 76 * home.u
            radius: 14 * home.u
            color: S.ink(0.05)
            clip: true
            Image {
                id: cardImage
                anchors.fill: parent
                visible: source.toString().length > 0 && status === Image.Ready
                source: card.photoSource
                sourceSize: Qt.size(240, 240)
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
            }
            Components.FlowIcon {
                anchors.centerIn: parent
                visible: !card.photoSource.length || cardImage.status === Image.Error
                width: 26 * home.u; height: width
                name: "documents.image"
                flow: home.flow
                tintColor: S.dark ? "#A3A9B6" : S.faint
                activeTintColor: S.dark ? "#A3A9B6" : S.faint
                onDark: S.dark
                inactiveOpacity: 1
            }
        }
        Rectangle {                                       // ⋯ acciones de la tarjeta
            id: more
            anchors.right: parent.right
            anchors.rightMargin: 10 * home.u
            y: 10 * home.u
            width: 34 * home.u; height: width; radius: width / 2
            color: moreTap.pressed ? S.ink(0.10) : S.ink(0.05)
            Components.FlowIcon {
                anchors.centerIn: parent
                width: 18 * home.u; height: width
                name: "action.more"
                flow: home.flow
                tintColor: S.navy
                activeTintColor: S.navy
                onDark: S.dark
                inactiveOpacity: 1
            }
            MouseArea {
                id: moreTap
                anchors.fill: parent
                anchors.margins: -6 * home.u
                onClicked: {
                    home.closeMenus()
                    var p = more.mapToItem(home, more.width / 2, more.height)
                    cardMenu.rowKey = card.row.key
                    cardMenu.anchorX = p.x - 60 * home.u
                    cardMenu.anchorY = p.y
                    home.haptic("light")
                    cardMenu.open = true
                }
            }
            Accessible.role: Accessible.Button
            Accessible.name: "Acciones de " + (card.row.code || "calicata")
        }
        Column {
            x: card.wide ? photo.x + photo.width + 14 * home.u : 14 * home.u
            y: card.wide ? (card.height - height) / 2 : photo.y + photo.height + 12 * home.u
            width: card.width - x - (card.wide ? 52 * home.u : 14 * home.u)
            spacing: 4 * home.u
            Text {
                width: parent.width
                text: card.row.code || "Sin código"
                color: S.text
                elide: Text.ElideRight
                font.family: home.ui ? home.ui.fontFamily : ""
                font.pixelSize: 21 * home.u
                font.weight: Font.Bold
            }
            Row {
                visible: String(card.row.location || "").length > 0
                spacing: 6 * home.u
                width: parent.width
                Components.FlowIcon { width: 15 * home.u; height: width; name: "map.location"; flow: home.flow
                                      tintColor: S.muted; activeTintColor: S.muted; inactiveOpacity: 1
                                      anchors.verticalCenter: parent.verticalCenter }
                Text { width: parent.width - 21 * home.u; text: card.row.location || ""; color: S.muted; elide: Text.ElideRight
                       font.family: home.ui ? home.ui.fontFamily : ""; font.pixelSize: 14 * home.u }
            }
            Row {
                visible: String(card.row.project || "").length > 0
                spacing: 6 * home.u
                width: parent.width
                Components.FlowIcon { width: 15 * home.u; height: width; name: "documents.folder"; flow: home.flow
                                      tintColor: S.muted; activeTintColor: S.muted; inactiveOpacity: 1
                                      anchors.verticalCenter: parent.verticalCenter }
                Text { width: parent.width - 21 * home.u; text: card.row.project || ""; color: S.muted; elide: Text.ElideRight
                       font.family: home.ui ? home.ui.fontFamily : ""; font.pixelSize: 14 * home.u }
            }
        }
        Accessible.role: Accessible.Button
        Accessible.name: "Abrir calicata " + (row.code || "")
    }

    // ------------------------------------------------- Menús 3D Touch
    Renditions.RGlassMenu {                               // filtro por proyecto/carpeta
        id: filterMenu
        objectName: "homeFilterMenu"
        ui: home.ui
        above: false
        z: 45
        cardWidth: 260 * home.u
        Renditions.RMenuItem {
            ui: home.ui
            objectName: "homeFilterAll"
            label: "Todos"
            glyph: home.filterProjectId.length ? 0 : 0xE06C
            glyphColor: S.corporateBlue
            onActivated: { home.filterProjectId = ""; home.haptic("selection"); filterMenu.close() }
        }
        Flickable {
            width: parent.width
            height: Math.min(projectList.height, 5 * 58 * home.u)
            contentHeight: projectList.height
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            Column {
                id: projectList
                width: parent.width
                Repeater {
                    objectName: "homeFilterProjects"
                    model: home.projects
                    delegate: Renditions.RMenuItem {
                        required property var modelData
                        required property int index
                        readonly property string projectId: String(modelData.id || "")
                        ui: home.ui
                        label: String(modelData.name || modelData.code || "")
                        glyph: home.filterProjectId === projectId ? 0xE06C : 0
                        glyphColor: S.corporateBlue
                        separator: index < home.projects.length - 1
                        onActivated: { home.filterProjectId = projectId; home.haptic("selection"); filterMenu.close() }
                    }
                }
            }
        }
    }

    Renditions.RGlassMenu {                               // ⋯ de una tarjeta
        id: cardMenu
        property string rowKey: ""
        readonly property var row: home.rowByKey(rowKey)
        ui: home.ui
        above: false
        z: 45
        cardWidth: 240 * home.u
        Renditions.RMenuItem {
            ui: home.ui
            label: "Abrir ficha"
            glyph: 0xE0CC
            glyphColor: S.navy
            separator: !!(cardMenu.row && cardMenu.row.geo)
            onActivated: { var r = cardMenu.row; cardMenu.close(); home.openRow(r) }
        }
        Renditions.RMenuItem {
            visible: !!(cardMenu.row && cardMenu.row.geo)
            ui: home.ui
            label: "Ver en el mapa"
            glyph: 0xE1DB
            glyphColor: S.navy
            separator: false
            onActivated: {
                var r = cardMenu.row
                cardMenu.close()
                if (!r || !r.geo) return
                home.view = "map"
                topoMap.fitted = true
                topoMap.centerOn(r.geo.lat, r.geo.lon, 14)
            }
        }
    }

    Renditions.RGlassMenu {                               // detalle de la calicata del marcador
        id: detailMenu
        objectName: "calicataMapDetail"
        property string rowKey: ""
        readonly property var row: home.rowByKey(rowKey) || ({})
        ui: home.ui
        above: true
        z: 45
        cardWidth: 340 * home.u
        Item {
            width: parent.width
            height: Math.max(detailPhoto.height, detailHead.height) + 8 * home.u
            Rectangle {
                id: detailPhoto
                visible: home.coverFor(detailMenu.row).length > 0
                width: visible ? 86 * home.u : 0
                height: 86 * home.u
                radius: 14 * home.u
                clip: true
                color: S.ink(0.05)
                Image { anchors.fill: parent; source: home.coverFor(detailMenu.row); fillMode: Image.PreserveAspectCrop
                        sourceSize: Qt.size(240, 240); asynchronous: true }
            }
            Column {
                id: detailHead
                x: detailPhoto.width + (detailPhoto.visible ? 12 * home.u : 4 * home.u)
                width: parent.width - x - 44 * home.u
                spacing: 3 * home.u
                Text { width: parent.width; text: detailMenu.row.code || "Sin código"; color: S.text; elide: Text.ElideRight
                       font.family: home.ui ? home.ui.fontFamily : ""; font.pixelSize: 20 * home.u; font.weight: Font.Bold }
                Text { width: parent.width; visible: text.length > 0; text: detailMenu.row.location || ""; color: S.muted
                       elide: Text.ElideRight; font.family: home.ui ? home.ui.fontFamily : ""; font.pixelSize: 14 * home.u }
                Text { width: parent.width; visible: text.length > 0; text: detailMenu.row.project || ""; color: S.muted
                       elide: Text.ElideRight; font.family: home.ui ? home.ui.fontFamily : ""; font.pixelSize: 14 * home.u }
                Text { width: parent.width; visible: text.length > 0; text: home.dateLabel(detailMenu.row.startDate); color: S.muted
                       font.family: home.ui ? home.ui.fontFamily : ""; font.pixelSize: 14 * home.u }
            }
            Rectangle {
                anchors.right: parent.right
                width: 34 * home.u; height: width; radius: width / 2
                color: S.ink(0.05)
                Text { anchors.centerIn: parent; text: String.fromCharCode(0xE1B2); color: S.text
                       font.family: home.ui ? home.ui.iconFamily : ""; font.pixelSize: 17 * home.u }
                MouseArea { anchors.fill: parent; anchors.margins: -6 * home.u; onClicked: detailMenu.close() }
                Accessible.role: Accessible.Button
                Accessible.name: "Cerrar"
            }
        }
        Repeater {
            model: {
                var r = detailMenu.row, out = []
                if (r.geo) out.push(["Coordenadas", r.geo.lat.toFixed(6) + ", " + r.geo.lon.toFixed(6)])
                if (String(r.altitude || "").length) out.push(["Cota", r.altitude + " m.s.n.m."])
                if (r.status) out.push(["Estado", home.statusLabel(r.status)
                                        + (r.syncState === "LOCAL" || r.syncState === "PENDING" ? " · solo en este equipo" : "")])
                if (String(r.supervisor || "").length) out.push(["Supervisor", r.supervisor])
                if (String(r.observations || "").length) out.push(["Observaciones", r.observations])
                return out
            }
            delegate: Item {
                required property var modelData
                width: detailMenu.cardWidth - 24 * home.u
                height: Math.max(26 * home.u, valueText.implicitHeight + 6 * home.u)
                Text { width: parent.width * 0.36; text: modelData[0]; color: S.muted
                       font.family: home.ui ? home.ui.fontFamily : ""; font.pixelSize: 14 * home.u }
                Row {
                    x: parent.width * 0.38
                    width: parent.width * 0.62
                    spacing: 6 * home.u
                    Rectangle {
                        visible: modelData[0] === "Estado"
                        width: visible ? 9 * home.u : 0; height: 9 * home.u; radius: width / 2
                        anchors.verticalCenter: parent.verticalCenter
                        color: S.statusColor(detailMenu.row.status)
                    }
                    Text { id: valueText; width: parent.width - 15 * home.u; text: modelData[1]; color: S.text; wrapMode: Text.WordWrap
                           maximumLineCount: 3; elide: Text.ElideRight
                           font.family: home.ui ? home.ui.fontFamily : ""; font.pixelSize: 14 * home.u }
                }
            }
        }
        Renditions.RButton {
            ui: home.ui
            primary: true
            label: "Abrir ficha"
            onActivated: { var r = detailMenu.row; detailMenu.close(); home.openRow(r) }
        }
    }

    // ---- Dock 1 · Avance global de calicatas (balance de Rendiciones).
    Renditions.RGlassMenu {
        id: balanceMenu
        objectName: "calicatasBalanceMenu"
        ui: home.ui
        z: 45
        cardWidth: 360 * home.u
        readonly property var c: home.statusCounts
        readonly property real ratio: c.total > 0 ? c.APROBADO / c.total : 0
        Text {
            width: parent.width
            leftPadding: 8 * home.u
            topPadding: 4 * home.u
            text: "Avance global de calicatas"
            color: S.text
            font.family: home.ui ? home.ui.fontFamily : ""; font.pixelSize: 19 * home.u; font.weight: Font.DemiBold
        }
        Row {
            width: parent.width
            topPadding: 14 * home.u
            bottomPadding: 6 * home.u
            spacing: 18 * home.u
            Item {
                width: 118 * home.u; height: width
                Shape {
                    anchors.fill: parent
                    ShapePath {
                        strokeColor: Qt.rgba(6 / 255, 84 / 255, 162 / 255, 0.14)
                        strokeWidth: 12 * home.u
                        fillColor: "transparent"
                        capStyle: ShapePath.RoundCap
                        PathAngleArc { centerX: 59 * home.u; centerY: 59 * home.u; radiusX: 50 * home.u; radiusY: 50 * home.u; startAngle: 0; sweepAngle: 360 }
                    }
                    ShapePath {
                        strokeColor: S.corporateBlue
                        strokeWidth: 12 * home.u
                        fillColor: "transparent"
                        capStyle: ShapePath.RoundCap
                        PathAngleArc { centerX: 59 * home.u; centerY: 59 * home.u; radiusX: 50 * home.u; radiusY: 50 * home.u
                                       startAngle: -90; sweepAngle: 360 * balanceMenu.ratio }
                    }
                }
                Text {
                    anchors.centerIn: parent
                    text: balanceMenu.c.total > 0 ? Math.round(balanceMenu.ratio * 100) + "%" : "—"
                    color: S.text
                    font.family: home.ui ? home.ui.fontFamily : ""; font.pixelSize: 26 * home.u; font.weight: Font.DemiBold
                }
            }
            Column {
                width: parent.width - 136 * home.u
                anchors.verticalCenter: parent.verticalCenter
                spacing: 10 * home.u
                Repeater {
                    model: [["APROBADO", "Aprobadas / exportadas", S.corporateGreen],
                            ["EN_REVISION", "En revisión / revisadas", S.corporateBlue],
                            ["OBSERVADO", "Observadas", S.danger], ["BORRADOR", "Borrador", S.warning]]
                    delegate: Item {
                        required property var modelData
                        width: parent.width
                        height: 24 * home.u
                        Rectangle { width: 12 * home.u; height: width; radius: width / 2; color: modelData[2]; anchors.verticalCenter: parent.verticalCenter }
                        Text { x: 22 * home.u; width: parent.width - 22 * home.u - 34 * home.u
                               anchors.verticalCenter: parent.verticalCenter; text: modelData[1]; color: S.muted
                               elide: Text.ElideRight; fontSizeMode: Text.HorizontalFit; minimumPixelSize: 12 * home.u
                               font.family: home.ui ? home.ui.fontFamily : ""; font.pixelSize: 16 * home.u }
                        Text { anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                               text: String(balanceMenu.c[modelData[0]]); color: S.text
                               font.family: home.ui ? home.ui.fontFamily : ""; font.pixelSize: 17 * home.u; font.weight: Font.DemiBold }
                    }
                }
            }
        }
        Text {
            width: parent.width
            leftPadding: 8 * home.u
            bottomPadding: 4 * home.u
            text: balanceMenu.c.total > 0 ? "Aprobadas o exportadas sobre " + balanceMenu.c.total + " calicatas activas"
                                          : "Aún no hay calicatas."
            color: S.faint
            font.family: home.ui ? home.ui.fontFamily : ""; font.pixelSize: 13 * home.u
        }
    }

    // ---- Dock 2 · Nueva calicata (selector compacto + Crear).
    Renditions.RGlassMenu {
        id: createMenu
        objectName: "calicatasCreateMenu"
        ui: home.ui
        z: 45
        cardWidth: 380 * home.u
        property string projectId: ""
        property string sheetType: "FICHA DE CALICATA"
        property string startDate: ""
        property string endDate: ""
        property string error: ""
        property bool busy: false
        function reset() {
            if (home.editor && home.editor.cancelLogoStaging) home.editor.cancelLogoStaging()
            codeField.text = ""; fullNameField.text = ""; supervisorField.text = ""
            projectId = home.filterProjectId
            sheetType = "FICHA DE CALICATA"
            startDate = ""; endDate = ""; error = ""; busy = false
        }
        function create() {
            if (busy || !home.editor) return
            busy = true
            error = home.editor.createFromHome({
                code: codeField.text.trim(), projectFullName: fullNameField.text.trim(),
                supervisor: supervisorField.text.trim(), project: home.projectById(projectId),
                sheetType: sheetType, startDate: startDate, endDate: endDate,
                knownRows: home.allRows
            })
            busy = false
            if (!error.length) { createMenu.close(); home.revision++ }
        }
        Text {
            width: parent.width
            leftPadding: 8 * home.u
            topPadding: 4 * home.u
            text: "Nueva calicata"
            color: S.text
            font.family: home.ui ? home.ui.fontFamily : ""; font.pixelSize: 19 * home.u; font.weight: Font.DemiBold
        }
        Flickable {
            width: parent.width
            height: Math.min(createFields.height, home.height * 0.52)
            contentHeight: createFields.height
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            Column {
                id: createFields
                width: parent.width
                topPadding: 10 * home.u
                spacing: 10 * home.u
                Renditions.RField { id: codeField; width: parent.width; ui: home.ui; label: "Código"; placeholder: "Sin registrar"; maxLength: 80 }
                Renditions.RField { id: fullNameField; width: parent.width; ui: home.ui; label: "Nombre del proyecto"
                                    placeholder: "Denominación oficial completa del proyecto"; maxLength: 600 }
                Renditions.RField { id: supervisorField; width: parent.width; ui: home.ui; label: "Supervisor"
                                    placeholder: "Sin registrar"; maxLength: Rules.SUPERVISOR_MAX_LENGTH }
                Renditions.RSelect {
                    width: parent.width
                    ui: home.ui
                    label: "Seleccionar carpeta"
                    placeholder: home.projects.length ? "Seleccionar carpeta" : "Sin proyectos disponibles"
                    value: createMenu.projectId
                    options: home.projects.map(function(p) {
                        return { value: String(p.id || ""), label: String(p.name || p.code || ""), detail: String(p.code || "") }
                    })
                    onPicked: function(v) { createMenu.projectId = v }
                }
                Renditions.RSelect {
                    width: parent.width
                    ui: home.ui
                    label: "Tipo de ficha"
                    value: createMenu.sheetType
                    options: [{ value: "FICHA DE CALICATA", label: "FICHA DE CALICATA" },
                              { value: "FICHA DE CANTERA", label: "FICHA DE CANTERA" }]
                    onPicked: function(v) { createMenu.sheetType = v }
                }
                Renditions.RDateField { width: parent.width; ui: home.ui; label: "Fecha inicio"; value: createMenu.startDate
                                        clearable: true; onPicked: function(v) { createMenu.startDate = v } }
                Renditions.RDateField { width: parent.width; ui: home.ui; label: "Fecha fin"; value: createMenu.endDate
                                        minimum: createMenu.startDate; clearable: true
                                        onPicked: function(v) { createMenu.endDate = v } }
                Column {                                  // abre el selector real de logos (preparación)
                    id: logosRow
                    readonly property var staged: home.editor ? home.editor.stagedLogos : null
                    width: parent.width
                    spacing: 6 * home.u
                    Text { text: "Identidad del reporte y logos"; color: S.muted
                           font.family: home.ui ? home.ui.fontFamily : ""; font.pixelSize: 13 * home.u }
                    Rectangle {                           // mismo aspecto que RSelect
                        width: parent.width
                        height: 48 * home.u
                        radius: 12 * home.u
                        color: S.ink(logosTap.pressed ? 0.14 : 0.08)
                        border.width: 1
                        border.color: S.border
                        Text {
                            x: 16 * home.u
                            width: parent.width - 52 * home.u
                            anchors.verticalCenter: parent.verticalCenter
                            elide: Text.ElideRight
                            text: (logosRow.staged && String(logosRow.staged.mtc || "").length ? "MTC elegido" : "Sin MTC")
                                  + " · " + (logosRow.staged && String(logosRow.staged.pro || "").length ? "Proyecto elegido" : "Sin proyecto")
                            color: S.text
                            font.family: home.ui ? home.ui.fontFamily : ""; font.pixelSize: 15 * home.u
                        }
                        Text {
                            anchors.right: parent.right; anchors.rightMargin: 16 * home.u
                            anchors.verticalCenter: parent.verticalCenter
                            text: String.fromCharCode(0xE06F)
                            color: S.muted
                            font.family: home.ui ? home.ui.iconFamily : ""; font.pixelSize: 16 * home.u
                        }
                        MouseArea { id: logosTap; anchors.fill: parent; onClicked: { if (home.editor) home.editor.openLogoStaging() } }
                        Accessible.role: Accessible.Button
                        Accessible.name: "Elegir logos MTC y del proyecto"
                    }
                }
            }
        }
        Text {
            width: parent.width
            visible: createMenu.error.length > 0
            topPadding: 6 * home.u
            text: createMenu.error
            color: S.danger
            wrapMode: Text.WordWrap
            font.family: home.ui ? home.ui.fontFamily : ""; font.pixelSize: 14 * home.u
        }
        Item { width: 1; height: 8 * home.u }
        Renditions.RButton {
            objectName: "calicatasCreateButton"
            width: parent.width
            ui: home.ui
            primary: true
            busy: createMenu.busy
            label: "Crear"
            onActivated: createMenu.create()
        }
    }

    // ---- Dock 3 · Abrir calicatas (sin Papelera ni Importar rendición).
    Renditions.RGlassMenu {
        id: openMenu
        objectName: "calicatasOpenMenu"
        ui: home.ui
        z: 45
        cardWidth: 330 * home.u
        readonly property var recent: home.allRows.length ? home.allRows[0] : null
        Renditions.RMenuItem {
            visible: openMenu.recent !== null
            ui: home.ui
            label: openMenu.recent ? (openMenu.recent.code || "Sin código")
                                     + (openMenu.recent.project ? " · " + openMenu.recent.project : "") : ""
            glyph: 0xE0CC
            glyphColor: S.corporateBlue
            onActivated: { var r = openMenu.recent; openMenu.close(); home.openRow(r) }
        }
        Renditions.RMenuItem {
            ui: home.ui
            label: "Abrir desde InGe Drive"
            glyph: 0xE0D7
            glyphColor: S.navy
            onActivated: { openMenu.close(); if (home.editor) home.editor.openFromHomeDrive() }
        }
        Renditions.RMenuItem {
            ui: home.ui
            label: "Abrir desde Google Drive"
            onActivated: {
                openMenu.close()
                // Selector de documentos del sistema (Google Drive si está instalado).
                if (home.editor) home.editor.openFromSystemPicker()
            }
            Item {                                         // logotipo genérico de Drive (mismo de Rendiciones)
                anchors.centerIn: parent
                width: 26 * home.u; height: 22 * home.u
                Rectangle { width: 6 * home.u; height: 20 * home.u; radius: 2; color: "#1FA463"; rotation: 30; x: 5 * home.u; y: 1 }
                Rectangle { width: 6 * home.u; height: 20 * home.u; radius: 2; color: "#FFD04B"; rotation: -30; x: 15 * home.u; y: 1 }
                Rectangle { width: 20 * home.u; height: 6 * home.u; radius: 2; color: "#4688F4"; x: 4 * home.u; y: 16 * home.u }
            }
        }
        Renditions.RMenuItem {
            objectName: "calicatasMenuArchive"
            ui: home.ui
            label: "Archivador"
            glyph: 0xE0D7
            glyphColor: S.navy
            separator: false
            onActivated: {
                openMenu.close()
                if (home.editor) home.editor.openArchivedForProject(home.filterProjectId)
            }
        }
    }
}

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

    // ----------------------------------------------- Portada
    readonly property var latestRow: rows.length ? rows[0] : null
    // Avance = datos de la ficha ya registrados (8 campos reales del listado).
    function progressOf(r) {
        if (!r) return 0
        var f = [r.code, r.project, r.location, r.geo ? "1" : "", r.altitude, r.supervisor, r.startDate, r.observations]
        var n = 0
        for (var i = 0; i < f.length; ++i) if (String(f[i] || "").trim().length) ++n
        return n / f.length
    }
    function dash(v) { var t = String(v || "").trim(); return t.length ? t : "—" }
    function _meters(v) { var n = _num(v); return isFinite(n) ? n.toLocaleString(Qt.locale("es_PE"), "f", 3) + " m" : "" }
    // Coordenadas WGS84: UTM real si la ficha es WGS84; si no, lat/lon convertidas.
    function coordLines(r) {
        if (!r) return ["—"]
        var n = _meters(r.utmN), e = _meters(r.utmE)
        if (n.length && e.length && String(r.datum || "WGS84") !== "PSAD56") return ["N: " + n, "E: " + e]
        if (r.geo) return ["Lat: " + r.geo.lat.toFixed(6), "Lon: " + r.geo.lon.toFixed(6)]
        return ["—"]
    }

    // ----- Diseño final: vidrio del Dock sobre el mapa (misma GlassSurface / glass.frag) -----
    property string query: ""
    // Tinta del vidrio del Home: oscuro = blanco; claro = navy y gris pizarra.
    readonly property color inkMain: S.dark ? "white" : "#151A30"
    readonly property color inkSoft: S.dark ? Qt.rgba(1, 1, 1, 0.70) : "#5A6378"
    readonly property color accentLime: S.dark ? "#B8E986" : "#486426"
    readonly property bool extreme: !!flow && flow.extremeMotion === true   // ganchos «Extrema» de InGeCoreFlow
    readonly property var searchRows: {
        var q = query.trim().toLowerCase()
        if (!q.length) return rows
        return rows.filter(function(r) {
            return [r.code, r.project, r.location].join(" ").toLowerCase().indexOf(q) >= 0
        })
    }
    function timeOf(r) { return r && r.updatedMs > 0 ? Qt.formatTime(new Date(r.updatedMs), "hh:mm") : "—" }
    // Primera sección con datos pendientes (mismos 8 campos del avance).
    function nextSection(r) {
        if (!r) return "—"
        function has(v) { return String(v || "").trim().length > 0 }
        if (!has(r.code) || !has(r.project)) return "Datos generales"
        if (!has(r.location) || !r.geo || !has(r.altitude)) return "Ubicación"
        if (!has(r.supervisor) || !has(r.startDate)) return "Registro de campo"
        if (!has(r.observations)) return "Observaciones"
        return "Revisión"
    }
    function openFilterFrom(item) {
        if (filterMenu.open) { filterMenu.close(); return }
        closeMenus()
        var p = item.mapToItem(home, item.width / 2, item.height)
        filterMenu.anchorX = p.x - 100 * u; filterMenu.anchorY = p.y
        haptic("light"); filterMenu.open = true
    }
    readonly property bool sheetNoMotion: !!ui && ui.reducedMotion === true
    readonly property bool sheetLowTier: !!ui && ui.dockLowCostGlass === true
    // Vidrio de Calicatas (hoja, píldora, filtro y popup). Las teselas del Map de
    // QtLocation no las captura ShaderEffectSource (solo sus MapItems), así que un
    // blur del mapa sale vacío y el panel queda transparente. Material sólido
    // translúcido en todos los tiers: blanco 72 % / grafito 75 %, borde y filo del Dock.
    component FinalGlass: Item {
        id: fg
        property real radius: 22 * home.u
        anchors.fill: parent
        z: -1
        Rectangle {
            anchors.fill: parent
            radius: fg.radius
            color: S.dark ? Qt.rgba(28 / 255, 28 / 255, 30 / 255, 0.75) : Qt.rgba(1, 1, 1, 0.72)
            border.width: 1
            border.color: S.dark ? Qt.rgba(1, 1, 1, 0.18) : Qt.rgba(1, 1, 1, 0.85)
        }
        Rectangle {                                    // filo especular superior (como el Dock)
            anchors.fill: parent
            radius: fg.radius
            gradient: Gradient {
                GradientStop { position: 0.0; color: Qt.rgba(1, 1, 1, S.dark ? 0.12 : 0.45) }
                GradientStop { position: Math.min(0.5, 28 * home.u / Math.max(1, fg.height)); color: Qt.rgba(1, 1, 1, 0) }
            }
        }
    }
    component Helmet: Shape {                        // casco de obra (sin asset)
        property real size: 20
        property color tone: "white"
        width: size; height: size
        ShapePath {
            strokeColor: tone; strokeWidth: Math.max(1.4, size * 0.09); fillColor: "transparent"
            capStyle: ShapePath.RoundCap; joinStyle: ShapePath.RoundJoin
            startX: size * 0.18; startY: size * 0.70
            PathArc { x: size * 0.82; y: size * 0.70; radiusX: size * 0.32; radiusY: size * 0.36 }
            PathMove { x: size * 0.06; y: size * 0.74 }
            PathLine { x: size * 0.94; y: size * 0.74 }
            PathMove { x: size * 0.50; y: size * 0.30 }
            PathLine { x: size * 0.50; y: size * 0.52 }
        }
    }

    function isRemotePurged(remoteId) {
        var ids = serviceAvailable ? CalicataCloud.purgedCalicataIds : []
        return ids.indexOf(String(remoteId || "").toLowerCase()) >= 0
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
                if (!rid.length || byKey["r:" + rid] || isRemotePurged(rid)) continue
                put("r:" + rid, {
                    key: "r:" + rid, remoteId: rid, instanceId: "", fileUrl: "",
                    code: String(r.code || "").trim(), projectId: String(r.project_id || pid),
                    location: _location(r.progresiva, ""), status: String(r.status || "BORRADOR"),
                    syncState: "SYNCED", geo: _geo(null, null, r.easting, r.northing, r.utm_zone, "WGS84"),
                    utmE: String(r.easting === null || r.easting === undefined ? "" : r.easting),
                    utmN: String(r.northing === null || r.northing === undefined ? "" : r.northing), datum: "WGS84",
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
            if (isRemotePurged(remote)) continue // retain the draft on disk; omit its active tile
            var existing = remote.length ? byKey["r:" + remote] : null
            if (existing) {                                   // mismo UUID remoto: una sola tarjeta
                existing.instanceId = lid
                existing.fileUrl = String(l.fileUrl || "")
                // La nube no guarda el datum: la copia local (WGS84/PSAD56 real) manda.
                var localGeo = _geo(l.latitude, l.longitude, l.utmX, l.utmY, l.utmZone, String(l.datum || ""))
                if (localGeo) existing.geo = localGeo
                if (String(l.utmX || "").length && String(l.utmY || "").length) {
                    existing.utmE = String(l.utmX); existing.utmN = String(l.utmY); existing.datum = String(l.datum || "")
                }
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
                utmE: String(l.utmX || ""), utmN: String(l.utmY || ""), datum: String(l.datum || ""),
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
        if (home.editor && typeof home.editor.closeHealthPanel === "function")
            home.editor.closeHealthPanel()               // un solo emergente a la vez
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
        // Desde el mapa: claramente horizontal (|dx| > 2·|dy|) y con velocidad de lanzamiento.
        var horizontal = fromPage === "map" ? Math.abs(dx) > 2 * Math.abs(dy) : Math.abs(dx) > Math.abs(dy)
        var far = Math.abs(dx) >= swipeDistance
        var fling = Math.abs(vx) >= swipeFlingVelocity && Math.abs(dx) >= 24 * u && (vx > 0) === (dx > 0)
        var edge = fromPage === "list" && (startX < systemEdge || startX > width - systemEdge)
        var reason = canceled ? "canceled" : edge ? "system_edge" : !horizontal ? "vertical"
                   : !wanted ? "opposite" : !(fromPage === "map" ? fling : (far || fling)) ? "short" : "ok"
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
            visible: false; enabled: false           // diseño final: hoja inferior «Mis calicatas»
            contentWidth: width
            contentHeight: Math.max(height, column.y + column.height)
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

            Column {                                     // portada (sobre las auras)
                id: header
                objectName: "homeHeader"
                x: 22 * home.u
                width: parent.width - 44 * home.u
                // Centrado vertical en el espacio libre sobre la tarjeta (como el preview).
                readonly property real headerTop: (home.ui ? home.ui.topInset : 0) + 16 * home.u
                y: headerTop + Math.max(0, (panel.restY - headerTop - height) / 2)
                spacing: 10 * home.u
                Rectangle { width: 34 * home.u; height: 5 * home.u; radius: height / 2; color: S.corporateGreen }
                Text {
                    width: parent.width
                    text: "Crea tu\ncalicata en\npasos simples"
                    color: S.text
                    wrapMode: Text.WordWrap
                    lineHeight: 1.08
                    font.family: home.ui ? home.ui.fontFamily : ""
                    font.pixelSize: 32 * home.u
                    font.weight: Font.Medium
                    font.letterSpacing: -0.3 * home.u
                }
                Text {
                    width: parent.width
                    text: "Datos geotécnicos organizados por proyecto."
                    color: S.muted
                    wrapMode: Text.WordWrap
                    font.family: home.ui ? home.ui.fontFamily : ""
                    font.pixelSize: 16 * home.u
                }
                PageDots { opacity: 0.55 }
            }

            // Tarjeta «Último reciente»: la calicata modificada más recientemente.
            Rectangle {
                id: panel
                objectName: "homeLatestCard"
                x: 14 * home.u
                width: parent.width - 28 * home.u
                // Anclada abajo, sobre el Dock; nunca se monta sobre el título.
                readonly property real restY: flick.height - (home.ui ? home.ui.dockArea : 96) - 14 * home.u - height
                y: Math.max(restY, header.y + header.height + 24 * home.u)
                height: latestCol.height + 40 * home.u
                radius: 28 * home.u
                visible: home.latestRow !== null
                gradient: Gradient {
                    GradientStop { position: 0.0; color: "#1C2D50" }
                    GradientStop { position: 1.0; color: "#151A30" }
                }
                border.width: 1
                border.color: Qt.rgba(1, 1, 1, S.dark ? 0.10 : 0.0)
                scale: latestTap.pressed ? 0.98 : 1
                Behavior on scale { NumberAnimation { duration: home.flow ? home.flow.duration(120) : 120 } }
                MouseArea { id: latestTap; anchors.fill: parent; onClicked: home.openRow(home.latestRow) }
                Column {
                    id: latestCol
                    x: 20 * home.u; y: 20 * home.u
                    width: parent.width - 40 * home.u
                    spacing: 10 * home.u
                    Row {
                        spacing: 10 * home.u
                        Rectangle {
                            width: 30 * home.u; height: width; radius: width / 2; color: "#486426"
                            Text { anchors.centerIn: parent; text: "✓"; color: "white"; font.pixelSize: 16 * home.u; font.bold: true }
                        }
                        Text { anchors.verticalCenter: parent.verticalCenter; text: "Último reciente"; color: "white"
                               font.family: home.ui ? home.ui.fontFamily : ""; font.pixelSize: 15 * home.u }
                    }
                    Text {
                        width: parent.width; elide: Text.ElideRight
                        text: home.latestRow ? home.dash(home.latestRow.code.length ? "Calicata " + home.latestRow.code : "") : ""
                        color: "white"
                        font.family: home.ui ? home.ui.fontFamily : ""; font.pixelSize: 30 * home.u; font.weight: Font.Bold
                    }
                    Text {
                        width: parent.width; elide: Text.ElideRight
                        text: home.latestRow ? home.dash(home.latestRow.project) : ""
                        color: Qt.rgba(1, 1, 1, 0.82)
                        font.family: home.ui ? home.ui.fontFamily : ""; font.pixelSize: 16 * home.u
                    }
                    Item { width: 1; height: 2 * home.u }
                    Rectangle {                              // avance de la ficha
                        width: parent.width; height: 28 * home.u; radius: height / 2
                        color: Qt.rgba(1, 1, 1, 0.16)
                        readonly property real ratio: home.progressOf(home.latestRow)
                        Rectangle {
                            width: Math.max(height, parent.width * parent.ratio); height: parent.height; radius: height / 2
                            color: "white"
                            Behavior on width { NumberAnimation { duration: home.flow ? home.flow.duration(320) : 320; easing.type: Easing.OutCubic } }
                        }
                        Text { x: 12 * home.u; anchors.verticalCenter: parent.verticalCenter
                               text: Math.round(parent.ratio * 100) + "%"; color: "#1C2D50"
                               font.family: home.ui ? home.ui.fontFamily : ""; font.pixelSize: 14 * home.u; font.weight: Font.Bold }
                    }
                    Item {
                        width: parent.width; height: 36 * home.u
                        Text { anchors.verticalCenter: parent.verticalCenter; text: "Datos de la ficha registrados"
                               color: Qt.rgba(1, 1, 1, 0.62); font.family: home.ui ? home.ui.fontFamily : ""; font.pixelSize: 12 * home.u }
                        Rectangle {                          // editar = abrir la ficha
                            anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                            height: 36 * home.u; radius: height / 2
                            color: "#486426"
                            width: editRow.implicitWidth + 30 * home.u
                            Row {
                                id: editRow; anchors.centerIn: parent; spacing: 6 * home.u
                                Text { anchors.verticalCenter: parent.verticalCenter; text: "Editar"; color: "white"
                                       font.family: home.ui ? home.ui.fontFamily : ""; font.pixelSize: 14 * home.u; font.weight: Font.DemiBold }
                                Components.FlowIcon { anchors.verticalCenter: parent.verticalCenter; width: 16 * home.u; height: width
                                                      name: "action.edit"; flow: home.flow; tintColor: "white"; activeTintColor: "white"
                                                      onDark: true; inactiveOpacity: 1 }
                            }
                        }
                    }
                }
                Accessible.role: Accessible.Button
                Accessible.name: "Abrir la calicata más reciente"
            }

            Column {
                id: column
                x: 22 * home.u
                width: parent.width - 44 * home.u
                y: (panel.visible ? panel.y + panel.height : header.y + header.height) + 18 * home.u
                spacing: 10 * home.u
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
                    topPadding: 12 * home.u
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
                Item { width: 1; height: (home.ui ? home.ui.dockArea : 96) + 12 * home.u }
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
        // ====== Diseño final (2026-11-02): mapa topográfico de fondo + vidrio del Dock ======
        Item {                                       // barra superior
            id: finalTop
            opacity: 1 - 0.55 * sheet.expandProgress
            scale: 1 - 0.06 * sheet.expandProgress
            transformOrigin: Item.Left
            x: 18 * home.u; width: parent.width - 36 * home.u
            y: (home.ui ? home.ui.topInset : 0) + 8 * home.u
            height: 54 * home.u
            Text {                                   // título a la izquierda; la píldora es el filtro
                anchors.left: parent.left; anchors.leftMargin: 4 * home.u
                anchors.verticalCenter: parent.verticalCenter
                textFormat: Text.StyledText
                text: "Calicatas"
                color: home.inkMain
                font.family: home.ui ? home.ui.fontFamily : ""; font.pixelSize: 24 * home.u; font.weight: Font.Medium
            }
        }
        Item {                                       // píldora de calicatas con ubicación
            id: nearPill
            opacity: 1 - sheet.expandProgress
            visible: opacity > 0.02
            anchors.right: finalTop.right
            y: finalTop.y + finalTop.height + 14 * home.u
            width: nearText.implicitWidth + 64 * home.u; height: 46 * home.u
            FinalGlass { radius: height / 2 }
            Text {
                id: nearText
                x: 22 * home.u; anchors.verticalCenter: parent.verticalCenter
                text: home.markers.length + (home.markers.length === 1 ? " calicata en el mapa" : " calicatas en el mapa") + "  ˅"
                color: home.inkMain; font.family: home.ui ? home.ui.fontFamily : ""; font.pixelSize: 16 * home.u
            }
            MouseArea { anchors.fill: parent; onClicked: home.openFilterFrom(nearPill) }
        }
        Rectangle {                                  // el mapa se atenúa al expandir la hoja
            anchors.fill: parent
            color: "black"
            opacity: 0.30 * sheet.expandProgress
        }
        Item {                                       // hoja inferior: buscador + Mis calicatas
            id: sheet
            x: 0; width: parent.width
            property bool expanded: false
            property real dragY: 0
            readonly property real restY: parent.height * (expanded ? 0.15 : 0.57)
            y: Math.max(parent.height * 0.12, Math.min(parent.height * 0.62, restY + dragY))
            Behavior on y { enabled: !sheetDrag.active
                NumberAnimation { duration: home.sheetNoMotion ? 0 : 380; easing.type: Easing.OutCubic } }
            // Alto fijo (sin re-maquetar durante el arrastre): solo cambia y.
            height: parent.height * 0.88 + 30 * home.u
            readonly property real expandProgress: Math.max(0, Math.min(1, (parent.height * 0.57 - y) / (parent.height * 0.42)))
            FinalGlass { radius: 30 * home.u }
            Rectangle {                              // tirador
                anchors.horizontalCenter: parent.horizontalCenter; y: 8 * home.u
                width: (sheetDrag.active ? 56 : 40) * home.u; height: 5 * home.u; radius: height / 2
                color: Qt.rgba(1, 1, 1, sheetDrag.active ? 0.90 : 0.45)
                Behavior on width { NumberAnimation { duration: home.sheetNoMotion ? 0 : 160; easing.type: Easing.OutCubic } }
                Behavior on color { ColorAnimation { duration: home.sheetNoMotion ? 0 : 160 } }
            }
            // Arrastre vertical de la hoja; el horizontal sigue siendo el paso al mapa.
            DragHandler {
                id: sheetDrag
                // Con un emergente abierto (Nueva calicata, filtros, etc.) la hoja queda quieta:
                // antes subía/bajaba por detrás y se superponía al diálogo.
                enabled: !(filterMenu.open || cardMenu.open || detailMenu.open || balanceMenu.open
                           || createMenu.open || openMenu.open)
                target: null
                xAxis.enabled: false
                property real base: 0
                onTranslationChanged: if (active) sheet.dragY = translation.y - base
                onActiveChanged: {
                    if (active) { base = translation.y; return }   // 1:1 desde que se reconoce el gesto
                    var v = centroid.velocity.y
                    if (sheet.dragY < -60 * home.u || v < -600) sheet.expanded = true
                    else if (sheet.dragY > 60 * home.u || v > 600) sheet.expanded = false
                    sheet.dragY = 0
                    home.haptic("light")
                }
            }
            Item {
                id: searchBox
                x: 20 * home.u; y: 20 * home.u; width: parent.width - 40 * home.u; height: 50 * home.u
                Rectangle { anchors.fill: parent; radius: height / 2; color: Qt.rgba(1, 1, 1, 0.10); border.width: 1; border.color: Qt.rgba(1, 1, 1, 0.22) }
                Components.FlowIcon { x: 18 * home.u; anchors.verticalCenter: parent.verticalCenter; width: 20 * home.u; height: width
                                      name: "action.search"; flow: home.flow; tintColor: "white"; activeTintColor: "white"; onDark: true; inactiveOpacity: 1 }
                TextInput {
                    id: searchInput
                    x: 50 * home.u; width: parent.width - 66 * home.u; anchors.verticalCenter: parent.verticalCenter
                    color: home.inkMain; clip: true
                    font.family: home.ui ? home.ui.fontFamily : ""; font.pixelSize: 16 * home.u
                    onTextChanged: home.query = text
                    Text { anchors.fill: parent; visible: !parent.text.length && !parent.activeFocus; text: "¿Qué calicata buscas?"
                           color: home.inkSoft; font: parent.font }
                }
            }
            Text {
                x: 22 * home.u; y: searchBox.y + searchBox.height + 18 * home.u
                text: "Mis calicatas"; color: home.inkMain
                font.family: home.ui ? home.ui.fontFamily : ""; font.pixelSize: 24 * home.u; font.weight: Font.Medium
            }
            ListView {
                id: finalList
                x: 14 * home.u; width: parent.width - 28 * home.u
                y: searchBox.y + searchBox.height + 60 * home.u
                // Alto del área visible con la hoja expandida (fijo).
                height: sheet.height - y - 30 * home.u - home.height * 0.03
                clip: true; boundsBehavior: Flickable.DragOverBounds
                interactive: sheet.expanded                  // scroll interno solo con la hoja expandida
                onContentYChanged: if (sheet.expanded && contentY < -50 * home.u) sheet.expanded = false
                model: home.searchRows
                footer: Item { width: 1; height: (home.ui ? home.ui.dockArea : 96) + 8 * home.u }
                delegate: Item {
                    id: frow
                    required property var modelData
                    required property int index
                    width: ListView.view.width; height: 74 * home.u
                    // Cascada al expandir: 0→1 y +12 u→0, 30 ms entre filas (15 en LOW).
                    property real enter: 1
                    opacity: enter
                    transform: Translate { y: (1 - frow.enter) * 12 * home.u }
                    scale: frowTap.pressed ? (home.extreme ? home.flow.pressScale : 0.98) : 1
                    Behavior on scale { NumberAnimation { duration: home.sheetNoMotion ? 0 : 120; easing.type: Easing.OutCubic } }
                    SequentialAnimation {
                        id: frowIn
                        PauseAnimation { duration: Math.min(frow.index, 10) * (home.extreme ? home.flow.staggerDuration : home.sheetLowTier ? 15 : 30) }
                        NumberAnimation { target: frow; property: "enter"; from: 0; to: 1; duration: 280; easing.type: Easing.OutCubic }
                    }
                    Connections {
                        target: sheet
                        function onExpandedChanged() {
                            if (!sheet.expanded || home.sheetNoMotion) { frowIn.stop(); frow.enter = 1; return }
                            frow.enter = 0; frowIn.restart()
                        }
                    }
                    Rectangle { anchors.fill: parent; anchors.margins: 3 * home.u; radius: 16 * home.u
                                color: Qt.rgba(1, 1, 1, frowTap.pressed ? (home.extreme ? home.flow.pressHighlight : 0.10) : 0) }    // realce del vidrio
                    Rectangle { visible: frow.index > 0; x: 66 * home.u; width: parent.width - 66 * home.u; height: 1; color: Qt.rgba(1, 1, 1, 0.12) }
                    Rectangle { x: 6 * home.u; anchors.verticalCenter: parent.verticalCenter; width: 46 * home.u; height: width; radius: width / 2
                                color: Qt.rgba(1, 1, 1, 0.10); border.width: 1; border.color: Qt.rgba(1, 1, 1, 0.18)
                                Helmet { anchors.centerIn: parent; size: 20 * home.u; tone: home.inkMain } }
                    Column {
                        x: 66 * home.u; width: parent.width - 140 * home.u; anchors.verticalCenter: parent.verticalCenter; spacing: 3 * home.u
                        Text { width: parent.width; elide: Text.ElideRight; color: home.inkMain
                               text: home.dash(frow.modelData.code) + " · " + home.dash(frow.modelData.project)
                               font.family: home.ui ? home.ui.fontFamily : ""; font.pixelSize: 16 * home.u }
                        Text { width: parent.width; elide: Text.ElideRight; color: home.inkSoft
                               text: home.dash(frow.modelData.location) + " · " + home.timeOf(frow.modelData)
                               font.family: home.ui ? home.ui.fontFamily : ""; font.pixelSize: 14 * home.u }
                    }
                    Text { anchors.right: parent.right; anchors.rightMargin: 6 * home.u; anchors.verticalCenter: parent.verticalCenter
                           text: Math.round(home.progressOf(frow.modelData) * 100) + "%"; color: home.accentLime
                           font.family: home.ui ? home.ui.fontFamily : ""; font.pixelSize: 20 * home.u; font.weight: S.dark ? Font.Medium : Font.DemiBold }
                    MouseArea { id: frowTap; anchors.fill: parent; onClicked: home.openRow(frow.modelData) }
                }
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter; y: 16 * home.u
                    visible: home.searchRows.length === 0
                    text: home.loadState === "loading" ? "Cargando tus calicatas…" : home.query.length ? "Sin resultados." : "Aún no hay calicatas."
                    color: home.inkSoft; font.family: home.ui ? home.ui.fontFamily : ""; font.pixelSize: 15 * home.u
                }
            }
            Item {                                   // barra de desplazamiento de vidrio
                id: listBar
                visible: finalList.contentHeight > finalList.height
                x: sheet.width - width - 2 * home.u
                y: finalList.y; width: 24 * home.u; height: finalList.height
                readonly property bool hot: finalList.moving || barTap.pressed
                opacity: hot ? 0.95 : 0.30
                Behavior on opacity { NumberAnimation { duration: listBar.hot ? 120 : 700; easing.type: Easing.OutQuad } }
                Rectangle {
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: 4 * home.u; radius: width / 2
                    height: Math.max(36 * home.u, parent.height * finalList.visibleArea.heightRatio)
                    y: Math.max(0, Math.min(parent.height - height, parent.height * finalList.visibleArea.yPosition))
                    color: Qt.rgba(1, 1, 1, 0.75); border.width: 1; border.color: Qt.rgba(1, 1, 1, 0.35)
                }
                MouseArea {
                    id: barTap
                    anchors.fill: parent
                    preventStealing: true
                    function scrollTo(py) {
                        var maxY = Math.max(0, finalList.contentHeight - finalList.height)
                        finalList.contentY = finalList.originY + Math.max(0, Math.min(1, py / height)) * maxY
                    }
                    onPressed: function(m) { if (!sheet.expanded) sheet.expanded = true; scrollTo(m.y) }
                    onPositionChanged: function(m) { if (pressed) scrollTo(m.y) }
                }
                Accessible.role: Accessible.ScrollBar; Accessible.name: "Desplazar Mis calicatas"
            }
        }
        PageSwipe { id: listSwipe; objectName: "homeListSwipe"; fromPage: "list"
                    grabPermissions: PointerHandler.CanTakeOverFromAnything | PointerHandler.ApprovesCancellation }
    }

    // ------------------------------------------- Vista 2 · Mapa topográfico
    // Ocupa toda la pantalla (sin franja fija de título). Solo pide teselas
    // mientras se ve o entra (active), y conserva las listas al volver a la lista.
    CalicatasTopoMap {
        id: topoMap
        scale: 1 // QtLocation GPU surface must never be continuously rescaled
        objectName: "homeMapPage"
        width: parent.width
        height: parent.height
        z: -1                                      // fondo del Home (misma instancia del mapa)
        x: 0
        // The map is the LIVE BACKGROUND of both Home views: list + map.
        // Hiding it on "list" removed the topo terrain behind the glass sheet.
        // Release its QtLocation renderer only when opening a Calicata form,
        // so the form and Home never have two live GPU maps simultaneously.
        visible: home.visible && !!home.editor && home.editor.homeMode
        active: home.visible && !!home.editor && home.editor.homeMode
        // In list mode the sheet/swipe owns touch; in map mode QtLocation pans.
        enabled: active && home.view === "map"
        ui: home.ui
        flow: home.flow
        markers: home.markers
        selectedKey: detailMenu.open ? detailMenu.rowKey : (home.view !== "map" && home.latestRow ? home.latestRow.key : "")
        bottomInset: home.ui ? home.ui.dockArea : 96
        controlsInset: 0
        // Con el popup de la calicata abierto, los controles se ocultan (orden de DIOS).
        controlsVisible: home.pagePos > 0.5 && !detailMenu.open
        property bool fitted: false
        // Página del mapa: encuadra marcadores; en el Home se centra en la calicata activa.
        Connections {
            target: home
            function onViewChanged() { if (home.view === "map" && !topoMap.fitted) { topoMap.fitted = true; Qt.callLater(topoMap.fitToMarkers) } }
            function onLatestRowChanged() {
                // Do not recenter an inactive renderer on every async list update.
                if (topoMap.active && home.latestRow && home.latestRow.geo
                        && !topoMap.fitted)
                    topoMap.setCamera(home.latestRow.geo.lat, home.latestRow.geo.lon, 14)
            }
        }
        // Los resultados del filtro y de la nube llegan de forma asíncrona.
        // Nunca conservar el encuadre del filtro anterior cuando cambia la selección.
        onMarkersChanged: {
            if (topoMap.active && !topoMap.fitted)
                Qt.callLater(function() { if (topoMap.active && !topoMap.fitted) topoMap.fitToMarkers() })
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
            opacity: home.pagePos
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
            // Franja de 16 u justo después del borde de gestos de Android: el resto del
            // mapa (también cerca del borde) es paneo del mapa.
            anchors.leftMargin: home.systemEdge
            y: (home.ui ? home.ui.topInset : 0) + 300 * home.u
            width: 16 * home.u
            height: Math.max(0, parent.height - y - topoMap.bottomInset - 150 * home.u)
            // El Map de Qt Location toma el toque que pasa por debajo: una vez activo,
            // el gesto de página no se deja quitar (el sistema aún puede cancelarlo).
            PageSwipe { id: mapSwipe; objectName: "homeMapSwipe"; fromPage: "map"
                        grabPermissions: PointerHandler.CanTakeOverFromAnything | PointerHandler.ApprovesCancellation }
        }
    }
    // Detalle del marcador: sobre la gota si hay espacio arriba; si no, debajo.
    // Si el marcador sale del mapa visible, el detalle se cierra.
    // La tarjeta de detalle es fija sobre el Dock: el zoom o el paneo ya no la cierran.
    // (Antes, al salir el marcador de la vista durante el zoom, se cerraba, controlsInset
    // volvía a 0 y los botones +/− saltaban bajo el dedo.)
    function _placeDetail() {}

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
    // Filtro por proyecto/carpeta: mismo vidrio verde oscuro del Home (FinalGlass),
    // textos blancos y check lima. Misma API que el menú anterior (open/close/anchor).
    Item {
        id: filterMenu
        objectName: "homeFilterMenu"
        property bool open: false
        property real anchorX: 0
        property real anchorY: 0
        function close() { open = false }
        anchors.fill: parent
        z: 45
        visible: filterCard.opacity > 0.01
        MouseArea { anchors.fill: parent; enabled: filterMenu.open; onClicked: filterMenu.close() }
        Item {
            id: filterCard
            width: Math.min(260 * home.u, home.width - 24 * home.u)
            height: filterCol.height + 16 * home.u
            x: Math.max(12 * home.u, Math.min(home.width - width - 12 * home.u, filterMenu.anchorX - width / 2))
            y: filterMenu.anchorY + 10 * home.u
            transformOrigin: Item.Top
            scale: filterMenu.open ? 1 : (home.extreme ? home.flow.sheetStartScale : 0.9)   // «Extrema»: desde la píldora
            opacity: filterMenu.open ? 1 : 0
            Behavior on scale { NumberAnimation { duration: filterMenu.open ? 240 : 150; easing.type: filterMenu.open ? Easing.OutBack : Easing.InCubic; easing.overshoot: 1.3 } }
            Behavior on opacity { NumberAnimation { duration: filterMenu.open ? 180 : 140; easing.type: Easing.OutQuad } }
            FinalGlass { radius: 18 * home.u }
            MouseArea { anchors.fill: parent }
            component FilterRow: Item {
                id: frow
                property string label: ""
                property bool checked: false
                property bool separator: true
                signal activated()
                width: filterCol.width; height: 52 * home.u
                Rectangle { anchors.fill: parent; anchors.margins: 2 * home.u; radius: 12 * home.u; color: rowTap.pressed ? Qt.rgba(1, 1, 1, 0.10) : "transparent" }
                Text { x: 14 * home.u; anchors.verticalCenter: parent.verticalCenter; visible: frow.checked; text: "✓"
                       color: home.accentLime; font.pixelSize: 18 * home.u; font.bold: true }
                Text { x: 44 * home.u; width: parent.width - 54 * home.u; anchors.verticalCenter: parent.verticalCenter; elide: Text.ElideRight
                       text: frow.label; color: home.inkMain; font.family: home.ui ? home.ui.fontFamily : ""; font.pixelSize: 16 * home.u }
                Rectangle { visible: frow.separator; x: 44 * home.u; width: parent.width - 54 * home.u; height: 1; anchors.bottom: parent.bottom; color: Qt.rgba(1, 1, 1, 0.12) }
                MouseArea { id: rowTap; anchors.fill: parent; onClicked: frow.activated() }
                Accessible.role: Accessible.Button; Accessible.name: frow.label
            }
            Column {
                id: filterCol
                x: 8 * home.u; y: 8 * home.u; width: parent.width - 16 * home.u
                FilterRow {
                    objectName: "homeFilterAll"
                    label: "Todos"
                    checked: !home.filterProjectId.length
                    onActivated: { home.filterProjectId = ""; home.haptic("selection"); filterMenu.close() }
                }
                Flickable {
                    width: parent.width
                    height: Math.min(projectList.height, 5 * 52 * home.u)
                    contentHeight: projectList.height
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds
                    Column {
                        id: projectList
                        width: parent.width
                        Repeater {
                            objectName: "homeFilterProjects"
                            model: home.projects
                            delegate: FilterRow {
                                required property var modelData
                                required property int index
                                readonly property string projectId: String(modelData.id || "")
                                label: String(modelData.name || modelData.code || "")
                                checked: home.filterProjectId === projectId
                                separator: index < home.projects.length - 1
                                onActivated: { home.filterProjectId = projectId; home.haptic("selection"); filterMenu.close() }
                            }
                        }
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

    // Detalle de la calicata del marcador: tarjeta de vidrio del Dock (diseño final).
    // Fija sobre el Dock; el mapa suma su alto a bottomInset para que sus controles
    // queden siempre por encima. Misma API que el menú anterior (open/close/rowKey).
    Item {
        id: detailMenu
        objectName: "calicataMapDetail"
        property string rowKey: ""
        readonly property var row: home.rowByKey(rowKey) || ({})
        property bool open: false
        property real anchorX: 0
        property real anchorY: 0
        property bool above: true
        function close() { open = false }
        z: 45
        x: 16 * home.u
        width: parent.width - 32 * home.u
        height: detailCol.height + 32 * home.u
        y: parent.height - (home.ui ? home.ui.dockArea : 96) - 12 * home.u - height + (open ? 0 : 24 * home.u)
        opacity: open ? 1 : 0
        visible: opacity > 0.01
        Behavior on opacity { NumberAnimation { duration: home.flow ? home.flow.duration(200) : 200; easing.type: Easing.OutCubic } }
        Behavior on y { NumberAnimation { duration: home.flow ? home.flow.duration(240) : 240; easing.type: Easing.OutCubic } }
        // «Extrema»: nace desde el marcador (escala desde el origen); en lo demás, sin escala.
        transform: Scale {
            origin.x: detailMenu.anchorX > 0 ? Math.max(0, Math.min(detailMenu.width, detailMenu.anchorX - detailMenu.x)) : detailMenu.width / 2
            origin.y: detailMenu.height
            xScale: detailMenu.open || !home.extreme ? 1 : home.flow.sheetStartScale
            yScale: xScale
            Behavior on xScale { NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }
        }
        FinalGlass { radius: 22 * home.u }
        MouseArea { anchors.fill: parent }
        Column {
            id: detailCol
            x: 16 * home.u; y: 16 * home.u; width: parent.width - 32 * home.u
            spacing: 8 * home.u
            Item {
                width: parent.width; height: 26 * home.u
                Row {
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 8 * home.u
                    Rectangle { anchors.verticalCenter: parent.verticalCenter; width: 10 * home.u; height: width; radius: width / 2
                                color: detailMenu.row.status === "BORRADOR" ? "#FF3B30" : "#B8E986" }
                    Text { text: detailMenu.row.status ? home.statusLabel(detailMenu.row.status)
                                 + (detailMenu.row.syncState === "LOCAL" || detailMenu.row.syncState === "PENDING" ? " · solo en este equipo" : "") : "—"
                           color: home.inkMain; font.family: home.ui ? home.ui.fontFamily : ""; font.pixelSize: 15 * home.u }
                }
                Rectangle {                              // ✕ cerrar
                    anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                    width: 30 * home.u; height: width; radius: width / 2; color: Qt.rgba(1, 1, 1, 0.14)
                    Shape {                              // ✕ dibujado
                        anchors.centerIn: parent; width: 12 * home.u; height: width
                        ShapePath {
                            strokeColor: home.inkMain; strokeWidth: 2 * home.u; capStyle: ShapePath.RoundCap; fillColor: "transparent"
                            startX: 0; startY: 0
                            PathLine { x: 12 * home.u; y: 12 * home.u }
                            PathMove { x: 12 * home.u; y: 0 }
                            PathLine { x: 0; y: 12 * home.u }
                        }
                    }
                    MouseArea { anchors.fill: parent; anchors.margins: -8 * home.u; onClicked: detailMenu.close() }
                    Accessible.role: Accessible.Button; Accessible.name: "Cerrar"
                }
            }
            Text { width: parent.width; elide: Text.ElideRight; color: home.inkMain
                   text: "Calicata " + home.dash(detailMenu.row.code)
                   font.family: home.ui ? home.ui.fontFamily : ""; font.pixelSize: 22 * home.u; font.weight: Font.Medium }
            Text { width: parent.width; elide: Text.ElideRight; color: home.inkSoft
                   text: home.dash(detailMenu.row.location) + " · " + home.dash(detailMenu.row.project) + " · " + home.dash(home.dateLabel(detailMenu.row.startDate))
                   font.family: home.ui ? home.ui.fontFamily : ""; font.pixelSize: 14 * home.u }
            Item {
                width: parent.width; height: 22 * home.u
                readonly property real ratio: home.progressOf(detailMenu.row)
                Rectangle { anchors.verticalCenter: parent.verticalCenter; width: parent.width; height: 6 * home.u; radius: height / 2; color: Qt.rgba(1, 1, 1, 0.22) }
                Rectangle { anchors.verticalCenter: parent.verticalCenter; width: parent.width * parent.ratio; height: 6 * home.u; radius: height / 2; color: "#B8E986" }
                Rectangle {
                    x: Math.max(0, Math.min(parent.width - width, parent.width * parent.ratio - width / 2))
                    anchors.verticalCenter: parent.verticalCenter
                    width: 22 * home.u; height: width; radius: width / 2; color: "#2E3B22"; border.width: 2; border.color: "#B8E986"
                    Helmet { anchors.centerIn: parent; size: 13 * home.u; tone: "#B8E986" }
                }
            }
            Text { width: parent.width; elide: Text.ElideRight; color: home.inkMain
                   text: "Siguiente: " + home.nextSection(detailMenu.row)
                   font.family: home.ui ? home.ui.fontFamily : ""; font.pixelSize: 13 * home.u }
            Repeater {                                   // filas compactas
                model: [["Coordenadas", detailMenu.row.geo ? detailMenu.row.geo.lat.toFixed(6) + ", " + detailMenu.row.geo.lon.toFixed(6) : "—"],
                        ["Cota", String(detailMenu.row.altitude || "").length ? detailMenu.row.altitude + " m.s.n.m." : "—"],
                        ["Supervisor", home.dash(detailMenu.row.supervisor)]]
                delegate: Item {
                    required property var modelData
                    width: detailCol.width; height: 22 * home.u
                    Text { text: modelData[0]; color: home.inkSoft; font.family: home.ui ? home.ui.fontFamily : ""; font.pixelSize: 13 * home.u }
                    Text { anchors.right: parent.right; width: parent.width * 0.62; horizontalAlignment: Text.AlignRight; elide: Text.ElideRight
                           text: modelData[1]; color: home.inkMain; font.family: home.ui ? home.ui.fontFamily : ""; font.pixelSize: 13 * home.u }
                }
            }
            Rectangle {                                  // «Abrir ficha» lima
                width: parent.width; height: 46 * home.u; radius: height / 2
                color: openTap.pressed ? "#9FD06C" : "#B8E986"
                Text { anchors.centerIn: parent; text: "Abrir ficha"; color: "#1A2A10"
                       font.family: home.ui ? home.ui.fontFamily : ""; font.pixelSize: 16 * home.u; font.weight: Font.DemiBold }
                MouseArea { id: openTap; anchors.fill: parent; onClicked: { var r = detailMenu.row; detailMenu.close(); home.openRow(r) } }
                Accessible.role: Accessible.Button; Accessible.name: "Abrir ficha"
            }
        }
    }

    Renditions.RGlassMenu {
        id: balanceMenu
        objectName: "calicatasBalanceMenu"
        ui: home.ui
        frostedFallback: true
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
            codeField.text = ""; fullNameField.text = ""; supervisorField.text = ""; extraFields.visible = false
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
        Item {
            width: parent.width
            height: 56 * home.u
            Column {
                anchors.left: parent.left
                anchors.right: closeCreate.left
                anchors.verticalCenter: parent.verticalCenter
                spacing: 3 * home.u
                Text { text: "Nueva calicata"; color: S.text; font.family: home.ui ? home.ui.fontFamily : ""; font.pixelSize: 21 * home.u; font.bold: true }
                Text { text: "Completa solo los datos esenciales"; color: S.muted; font.family: home.ui ? home.ui.fontFamily : ""; font.pixelSize: 13 * home.u }
            }
            Rectangle {
                id: closeCreate
                anchors.right: parent.right; anchors.top: parent.top
                width: 36 * home.u; height: width; radius: width / 2
                color: S.ink(0.06)
                Text { anchors.centerIn: parent; text: "×"; color: S.muted; font.pixelSize: 25 * home.u }
                MouseArea { anchors.fill: parent; onClicked: createMenu.close() }
                Accessible.role: Accessible.Button; Accessible.name: "Cerrar"
            }
        }
        Text { width: parent.width; text: "* Campos obligatorios"; color: S.muted; font.family: home.ui ? home.ui.fontFamily : ""; font.pixelSize: 13 * home.u; topPadding: 4 * home.u; bottomPadding: 4 * home.u }
        Column {
            id: createFields
            width: parent.width
            spacing: 12 * home.u
            Row {
                width: parent.width; spacing: 10 * home.u
                Renditions.RField { id: codeField; width: (parent.width - parent.spacing) / 2; ui: home.ui; label: "Código *"; placeholder: "Código"; maxLength: 80; formStyle: true }
                Renditions.RDateField { width: (parent.width - parent.spacing) / 2; ui: home.ui; label: "Fecha inicio"; value: createMenu.startDate
                                        clearable: true; onPicked: function(v) { createMenu.startDate = v } }
            }
            Renditions.RSelect {
                width: parent.width; ui: home.ui; label: "Proyecto / carpeta *"
                placeholder: home.projects.length ? "Seleccionar proyecto" : "Sin proyectos disponibles"
                value: createMenu.projectId
                options: home.projects.map(function(p) {
                    return { value: String(p.id || ""), label: String(p.name || p.code || ""), detail: String(p.code || "") }
                })
                onPicked: function(v) { createMenu.projectId = v }
            }
            Renditions.RField { id: supervisorField; width: parent.width; ui: home.ui; label: "Supervisor"
                                placeholder: "Sin registrar"; maxLength: Rules.SUPERVISOR_MAX_LENGTH }
            Text {
                width: parent.width; text: extraFields.visible ? "Menos opciones  −" : "Más opciones  +"
                color: S.accent; font.family: home.ui ? home.ui.fontFamily : ""; font.pixelSize: 13 * home.u
                topPadding: 4 * home.u; bottomPadding: 4 * home.u
                MouseArea { anchors.fill: parent; onClicked: extraFields.visible = !extraFields.visible }
                Accessible.role: Accessible.Button; Accessible.name: text
            }
            Column {
                id: extraFields
                width: parent.width; spacing: 10 * home.u; visible: false
                Renditions.RField { id: fullNameField; width: parent.width; ui: home.ui; label: "Nombre del proyecto"
                                    placeholder: "Denominación oficial completa del proyecto"; maxLength: 600 }
                Renditions.RSelect {
                    width: parent.width; ui: home.ui; label: "Tipo de ficha"; value: createMenu.sheetType
                    options: [{ value: "FICHA DE CALICATA", label: "FICHA DE CALICATA" },
                              { value: "FICHA DE CANTERA", label: "FICHA DE CANTERA" }]
                    onPicked: function(v) { createMenu.sheetType = v }
                }
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
            id: createError
            width: parent.width
            visible: createMenu.error.length > 0
            topPadding: 6 * home.u
            text: createMenu.error
            color: S.danger
            wrapMode: Text.WordWrap
            font.family: home.ui ? home.ui.fontFamily : ""; font.pixelSize: 14 * home.u
        }
        Item { id: createGap; width: 1; height: 8 * home.u }
        Row {
            width: parent.width; spacing: 10 * home.u
            Renditions.RButton { width: (parent.width - parent.spacing) / 2; ui: home.ui; label: "Cancelar"; onActivated: createMenu.close() }
            Renditions.RButton {
                id: createButton; objectName: "calicatasCreateButton"
                width: (parent.width - parent.spacing) / 2; ui: home.ui
                primary: true; color: "#a90068"; busy: createMenu.busy; label: "Crear"
                onActivated: createMenu.create()
            }
        }
    }

    // ---- Dock 3 · Abrir calicatas (sin Papelera ni Importar rendición).
    Renditions.RGlassMenu {
        id: openMenu
        objectName: "calicatasOpenMenu"
        ui: home.ui
        frostedFallback: true
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

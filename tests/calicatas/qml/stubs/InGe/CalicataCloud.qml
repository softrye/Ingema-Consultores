pragma Singleton
import QtQuick

// SOLO ARNÉS DE ESCRITORIO: imita la superficie pública de CalicataCloudService
// que usa el Home (mismas señales y firmas). No existe en la app ni en el APK.
QtObject {
    id: cloud
    property var projects: []
    property int pendingMediaCount: 0

    // Configuración de cada escenario.
    property var serverProjects: []
    property var serverRows: []
    property string projectsMode: "ok"   // ok | fail | offline | silent | auth
    property string listMode: "ok"       // ok | fail | offline | silent
    property int delayMs: 40
    property int refreshCalls: 0
    property int listCalls: 0
    property int editorListCalls: 0
    property var lastListIds: []

    signal projectsLoaded(int count)
    signal projectsLoadFailed(string message)
    signal homeCalicatasLoaded(int serial, var rows)
    signal homeCalicatasLoadFailed(int serial, string message)
    signal projectCalicatasLoaded(string projectId, var rows)
    signal projectCalicatasLoadFailed(string projectId, string message)
    signal calicataCoverReady(string calicataId, url localUrl)

    function reset() {
        projects = []; pendingMediaCount = 0; serverProjects = []; serverRows = []
        projectsMode = "ok"; listMode = "ok"; delayMs = 40
        refreshCalls = 0; listCalls = 0; editorListCalls = 0; lastListIds = []
    }
    function _later(fn) {
        var t = Qt.createQmlObject("import QtQuick; Timer { repeat: false }", cloud)
        t.interval = cloud.delayMs
        t.triggered.connect(function() { fn(); t.destroy() })
        t.start()
    }
    function refreshProjects() {
        refreshCalls++
        var mode = projectsMode
        if (mode === "auth") { projectsLoadFailed("Inicia sesión para acceder a Calicatas."); return }  // síncrono, como getJson
        _later(function() {
            if (mode === "ok") { projects = serverProjects.slice(); projectsLoaded(projects.length) }
            else if (mode === "fail") projectsLoadFailed("El servidor respondió HTTP 500 (PGRST).")
            else if (mode === "offline") projectsLoadFailed("Sin conexión de red.")
        })
    }
    function listHomeCalicatas(ids, serial) {
        listCalls++
        lastListIds = ids
        var mode = listMode
        _later(function() {
            if (mode === "ok") {
                homeCalicatasLoaded(serial, serverRows.filter(function(r) { return ids.indexOf(r.project_id) >= 0 }))
            } else if (mode === "fail") homeCalicatasLoadFailed(serial, "Permiso denegado (42501).")
            else if (mode === "offline") homeCalicatasLoadFailed(serial, "Sin conexión de red.")
        })
    }
    function listProjectCalicatas(projectId) { editorListCalls++ }
    function requestCalicataCover(projectId, calicataId) {}
}

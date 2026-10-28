.pragma library

// Modelo de incidencias de Calicatas para el panel "Estado de Calicatas" y las
// auras (mismo contrato que RenditionsUi.diagnostics de Rendiciones):
//   { level: "ok" | "attention" | "error", errors, attention,
//     incidents: [{ key, severity, title, area, code, what, cause, how, action }] }
// Solo se construye con fuentes REALES que ya publica el editor (errores de
// persistencia local, syncFailed de CalicataCloud, syncState CONFLICT, JSON de
// InGeDrive, laboratorio no admitido por el servidor). Un borrador, un campo
// opcional pendiente o trabajar sin conexión NO son fallos.
// Cada causa tiene una clave estable: la misma causa nunca se lista dos veces y
// desaparece en cuanto su fuente deja de estar activa.

// Textos deterministas de CalicataCloud (humanCloudError / validación previa).
var SYNC_CATALOG = [
    { match: "no tiene permiso", key: "sync-permission", severity: "error", code: "CAL-SYNC-42501",
      title: "Sin permiso para sincronizar", area: "Sincronización · proyecto",
      what: "El servidor rechazó la ficha: tu usuario no puede modificar calicatas en este proyecto.",
      how: "Pide acceso de escritura al proyecto o elige otro proyecto en General. El borrador se conserva en este equipo." },
    { match: "Inicia sesión", key: "sync-auth", severity: "error", code: "CAL-SYNC-AUTH",
      title: "Sesión requerida", area: "Sincronización · cuenta",
      what: "No hay una sesión válida para enviar la ficha al servidor.",
      how: "Inicia sesión de nuevo desde Perfil y vuelve a guardar. El borrador se conserva en este equipo." },
    { match: "cambió en el servidor", key: "sync-conflict", severity: "error", code: "CAL-SYNC-40001",
      title: "Conflicto de versiones", area: "Sincronización · versión",
      what: "Otra versión de esta calicata se guardó en el servidor.",
      how: "Vuelve a abrir la ficha desde el proyecto antes de guardar de nuevo; no se sobrescribe nada automáticamente." },
    { match: "Ya existe una calicata con ese código", key: "sync-code", severity: "attention", code: "CAL-SYNC-23505",
      title: "Código duplicado", area: "General · Código",
      what: "Ya hay otra calicata con este código en el proyecto.",
      how: "Cambia el código en General y vuelve a guardar." },
    { match: "Selecciona un proyecto", key: "sync-project", severity: "attention", code: "CAL-VAL-PROJECT",
      title: "Falta el proyecto", area: "General · Proyecto",
      what: "La ficha no tiene proyecto, así que no puede guardarse online.",
      how: "Elige la carpeta del proyecto en General y vuelve a guardar." },
    { match: "código de la calicata es obligatorio", key: "sync-code-missing", severity: "attention", code: "CAL-VAL-CODE",
      title: "Falta el código", area: "General · Código",
      what: "La ficha no tiene código, así que no puede guardarse online.",
      how: "Escribe el código en General y vuelve a guardar." },
    { match: "está archivada", key: "sync-archived", severity: "attention", code: "CAL-VAL-ARCHIVED",
      title: "Ficha archivada", area: "Estado de la ficha",
      what: "Las fichas archivadas no sincronizan cambios.",
      how: "Restáurala (Calicatas abiertas › Estado › Restaurar) antes de editarla o sincronizarla." }
]

// Sin red o servidor inaccesible: no es un fallo, la ficha queda pendiente.
var OFFLINE_HINTS = ["sin red", "de red", "network", "conexi", "connection", "host", "timeout", "tiempo de espera",
                     "unreachable", "offline", "dns"]

function _text(v) { return String(v === undefined || v === null ? "" : v).trim() }

function isOfflineMessage(message) {
    var m = _text(message).toLowerCase()
    if (!m.length) return false
    if (/ssl|tls|certificate|certificad|handshake|http[_ ]?[45][0-9][0-9]|42501|pgrst/.test(m)) return false
    for (var i = 0; i < SYNC_CATALOG.length; ++i)
        if (m.indexOf(SYNC_CATALOG[i].match.toLowerCase()) >= 0) return false
    for (var j = 0; j < OFFLINE_HINTS.length; ++j)
        if (m.indexOf(OFFLINE_HINTS[j]) >= 0) return true
    return false
}

function classifySyncFailure(message) {
    var m = _text(message)
    var lower = m.toLowerCase()
    for (var i = 0; i < SYNC_CATALOG.length; ++i) {
        var c = SYNC_CATALOG[i]
        if (lower.indexOf(c.match.toLowerCase()) >= 0)
            return { key: c.key, severity: c.severity, code: c.code, title: c.title, area: c.area,
                     what: c.what, cause: m, how: c.how,
                     action: c.severity === "error" ? { kind: "retry", label: "Reintentar guardado" } : {} }
    }
    return { key: "sync-failed", severity: "error", code: "CAL-SYNC",
             title: "La sincronización falló", area: "Sincronización",
             what: "La ficha no se pudo enviar al servidor.", cause: m,
             how: "El borrador se conserva en este equipo. Revisa la conexión y vuelve a guardar.",
             action: { kind: "retry", label: "Reintentar guardado" } }
}

// state: { hasDocument, persistenceError, syncState, syncFailure, driveJsonError, labCloudPending }
function build(state) {
    var s = state || {}
    var byKey = {}
    var order = []
    function add(inc) {
        if (byKey[inc.key]) return               // misma causa: una sola incidencia
        byKey[inc.key] = inc
        order.push(inc)
    }
    if (s.hasDocument) {
        var persistence = _text(s.persistenceError)
        if (persistence.length)
            add({ key: "local-save", severity: "error", code: "CAL-LOCAL-SAVE",
                  title: "No se pudo guardar en el equipo", area: "Guardado local",
                  what: "El último cambio no se escribió en el almacenamiento del teléfono.",
                  cause: persistence,
                  how: "No cierres la app. Libera espacio si el equipo está lleno y vuelve a guardar.",
                  action: { kind: "retry", label: "Reintentar guardado" } })
        if (_text(s.syncState) === "CONFLICT")
            add({ key: "sync-conflict", severity: "error", code: "CAL-SYNC-CONFLICT",
                  title: "Conflicto de versiones", area: "Sincronización · versión",
                  what: "La copia del servidor y la de este equipo no coinciden.",
                  cause: "",
                  how: "Vuelve a abrir la ficha desde el proyecto antes de guardar de nuevo; no se sobrescribe nada automáticamente.",
                  action: {} })
        var failure = s.syncFailure || null
        if (failure && _text(failure.message).length && !isOfflineMessage(failure.message))
            add(classifySyncFailure(failure.message))
        var drive = _text(s.driveJsonError)
        if (drive.length && !isOfflineMessage(drive))
            add({ key: "drive-json", severity: "error", code: "CAL-DRIVE-JSON",
                  title: "No se pudo guardar la copia en InGeDrive", area: "Guardado · InGeDrive",
                  what: "La ficha portable (JSON) no se subió a la carpeta del proyecto.",
                  cause: drive,
                  how: "El borrador se conserva. Revisa la carpeta elegida en «Guardar en…» y vuelve a guardar.",
                  action: { kind: "retry", label: "Reintentar guardado" } })
        var exp = s.exportIssue || null
        if (exp && _text(exp.message).length)
            add(exp.severity === "error"
                ? { key: "export-failed", severity: "error", code: "CAL-EXPORT",
                    title: "La exportación falló", area: "Revisión · Exportar",
                    what: "El Excel no se pudo publicar en el proyecto.",
                    cause: _text(exp.message),
                    how: "Revisa el mensaje y vuelve a exportar desde Revisión. Los datos de la ficha no se modificaron.",
                    action: {} }
                : { key: "export-pending", severity: "attention", code: "CAL-EXPORT-PENDING",
                    title: "Exportación pendiente de subida", area: "Revisión · Exportar",
                    what: "El Excel se generó, pero aún no se subió al proyecto.",
                    cause: _text(exp.message),
                    how: "No hace falta repetirla: la cola la subirá al recuperar conexión.",
                    action: {} })
        var media = s.mediaIssue || null
        if (media && _text(media.message).length) {
            var logo = media.kind === "logo"
            var permission = /permiso|permission/i.test(_text(media.message) + " " + _text(media.code))
            add({ key: "media-selection", severity: "attention",
                  code: logo ? "CAL-LOGO-SELECT" : "CAL-PHOTO-SELECT",
                  title: permission ? "Permiso de cámara o archivos denegado"
                                    : (logo ? "No se pudo cargar el logo" : "No se pudo cargar la fotografía"),
                  area: logo ? "General · Identidad del reporte" : "Fotos",
                  what: permission ? "Android no permitió a InGe+ usar la cámara o los archivos."
                                   : "La imagen elegida no se pudo cargar en la ficha.",
                  cause: _text(media.message),
                  how: permission ? "Concede el permiso en Ajustes de Android › Aplicaciones › InGe+ › Permisos y vuelve a intentarlo."
                                  : "Elige otra imagen o vuelve a intentarlo.",
                  action: {} })
        }
        var mediaIssues = s.mediaIssues || []
        for (var mi = 0; mi < mediaIssues.length; ++mi) {
            var issue = mediaIssues[mi]
            if (!issue || !_text(issue.message).length || isOfflineMessage(issue.message)) continue
            add({ key: "media-" + _text(issue.key), severity: "error",
                  code: _text(issue.code) || "CAL-MEDIA-READ",
                  title: "No se pudo recuperar o sincronizar un medio",
                  area: _text(issue.area) || "Media Cloud",
                  what: "El recurso no está confirmado en este equipo; no se presenta como una ranura vacía ni sincronizada.",
                  cause: _text(issue.message),
                  how: "Revisa el permiso o el archivo de origen y vuelve a abrir el panel. Las selecciones locales y el historial se conservan.",
                  action: {} })
        }
        if (s.labCloudPending === true)
            add({ key: "lab-cloud-pending", severity: "attention", code: "CAL-LAB-PENDING",
                  title: "Laboratorio pendiente en el servidor", area: "Laboratorio",
                  what: "Algunos datos de laboratorio se guardaron en el equipo, pero el servidor aún no los admite.",
                  cause: "",
                  how: "No borres esos datos: se conservan localmente y se enviarán cuando el servidor los acepte.",
                  action: {} })
    }
    var opening = _text(s.openFailure)
    if (opening.length)
        add({ key: "open-remote", severity: isHomeTimeout(opening) || isOfflineMessage(opening) ? "attention" : "error",
              code: "CAL-OPEN-REMOTE", title: "No se pudo abrir la ficha", area: "Calicatas · Apertura",
              what: "No terminó la recuperación de la ficha solicitada; las copias locales se conservan.",
              cause: opening, how: "Verifica la conexión y vuelve a abrir la ficha desde Calicatas recientes.",
              action: {} })
    var errors = 0, attention = 0
    for (var i = 0; i < order.length; ++i) {
        if (order[i].severity === "error") ++errors
        else ++attention
    }
    return { level: errors > 0 ? "error" : attention > 0 ? "attention" : "ok",
             errors: errors, attention: attention, incidents: order }
}

// Modo de RendicionesSyncAura con la misma prioridad que Rendiciones:
// rojo > amarillo > sincronizando/pendiente > verde. Sin ficha: neutro.
function auraMode(state, diagnostics) {
    var s = state || {}
    var d = diagnostics || {}
    if (!s.hasDocument) return "unknown"
    if (d.level === "error") return "error"
    if (d.level === "attention") return "attention"
    if (s.busy === true || _text(s.syncState) === "SYNCING") return "syncing"
    if (s.syncFailure && isOfflineMessage(s.syncFailure.message)) return "pending"
    if (isOfflineMessage(s.driveJsonError)) return "pending"
    var mediaIssues = s.mediaIssues || []
    if (s.mediaPending === true || mediaIssues.length) return "pending"
    var sync = _text(s.syncState)
    if (sync === "SYNCED") return "synced"
    return "pending"                              // LOCAL / PENDING / sin red: trabajo normal
}

// Texto del panel cuando no hay incidencias (explica el estado normal real).
function emptyText(state) {
    var s = state || {}
    if (!s.hasDocument) return "No hay una calicata abierta."
    var sync = _text(s.syncState)
    var failure = s.syncFailure || null
    var base = "Todo en orden. No hay fallos técnicos activos."
    if ((failure && isOfflineMessage(failure.message)) || isOfflineMessage(s.driveJsonError) || (s.mediaIssues || []).length)
        return base + "\nSin conexión: la ficha se guarda en este equipo y se sincronizará al recuperar la red."
    if (s.mediaPending === true) return base + "\nHay medios pendientes de recuperar o sincronizar; sus cambios locales se conservan."
    if (sync === "SYNCED") return base + "\nLa ficha está sincronizada."
    if (sync === "SYNCING" || s.busy === true) return base + "\nSincronizando la ficha…"
    return base + "\nLa ficha está guardada en este equipo y pendiente de sincronizar; un borrador no es un fallo."
}

// ---------------------------------------------------------------- Home
// Estado del Home de Calicatas (lista de todas las fichas). Fuentes reales:
// carga de proyectos/calicatas (CalicataCloud), syncFailed vigentes de
// cualquier ficha (mismo catálogo que la ficha), cola de medios pendiente y
// borradores locales sin confirmar. Sin red no es un fallo: queda en gris.
// state: { loaded, projectsError, loadErrors:{pid:msg}, syncFailures:[msg],
//          pendingMedia, localPending }
function buildHome(state) {
    var s = state || {}
    var byKey = {}, order = []
    function add(inc) { if (byKey[inc.key]) return; byKey[inc.key] = inc; order.push(inc) }
    var failures = s.syncFailures || []
    for (var i = 0; i < failures.length; ++i)
        if (_text(failures[i]).length && !isOfflineMessage(failures[i])) add(classifySyncFailure(failures[i]))
    var conflicts = Number(s.conflicts || 0)
    if (conflicts > 0)
        add({ key: "sync-conflict", severity: "error", code: "CAL-SYNC-CONFLICT",
              title: "Conflicto de versiones", area: "Calicatas · " + conflicts + " ficha(s)",
              what: "La copia del servidor y la de este equipo no coinciden.", cause: "",
              how: "Abre la ficha marcada desde el proyecto antes de guardar de nuevo; no se sobrescribe nada automáticamente.",
              action: {} })
    var pe = _text(s.projectsError)
    if (isHomeTimeout(pe))
        add({ key: "home-projects-timeout", severity: "attention", code: "CAL-HOME-PROJECTS-TIMEOUT",
              title: "El servidor no respondió a tiempo", area: "Calicatas · Inicio",
              what: "La lista de proyectos autorizados no llegó a tiempo; se usan los proyectos ya conocidos.",
              cause: pe, how: "Desliza hacia abajo para reintentar.", action: {} })
    else if (pe.length && !isOfflineMessage(pe))
        add({ key: "home-projects", severity: "error", code: "CAL-HOME-PROJECTS",
              title: "No se pudieron cargar los proyectos", area: "Calicatas · Inicio",
              what: "La lista de proyectos autorizados no llegó del servidor.", cause: pe,
              how: "Desliza hacia abajo para reintentar. Las fichas guardadas en el equipo siguen disponibles.",
              action: {} })
    var errs = s.loadErrors || {}
    var keys = Object.keys(errs)
    for (var k = 0; k < keys.length; ++k) {
        var msg = _text(errs[keys[k]])
        if (isHomeTimeout(msg))
            add({ key: "home-list-timeout", severity: "attention", code: "CAL-HOME-LIST-TIMEOUT",
                  title: "El servidor no respondió a tiempo", area: "Calicatas · Inicio",
                  what: "El listado de calicatas no llegó a tiempo; se conserva lo ya mostrado.", cause: msg,
                  how: "Desliza hacia abajo para reintentar.", action: {} })
        else if (msg.length && !isOfflineMessage(msg))
            add({ key: "home-list", severity: "error", code: "CAL-HOME-LIST",
                  title: "No se pudieron listar las calicatas", area: "Calicatas · Inicio",
                  what: "El servidor rechazó o no completó el listado de calicatas.", cause: msg,
                  how: "Desliza hacia abajo para reintentar. Las fichas guardadas en el equipo siguen disponibles.",
                  action: {} })
    }
    var opening = _text(s.openFailure)
    if (opening.length)
        add({ key: "open-remote", severity: isHomeTimeout(opening) || isOfflineMessage(opening) ? "attention" : "error",
              code: "CAL-OPEN-REMOTE", title: "No se pudo abrir la ficha", area: "Calicatas · Apertura",
              what: "La ficha seleccionada no se pudo recuperar del servidor.",
              cause: opening, how: "Reintenta abrirla desde la lista. No se han eliminado las copias locales.",
              action: {} })
    var errors = 0, attention = 0
    for (var n = 0; n < order.length; ++n) { if (order[n].severity === "error") ++errors; else ++attention }
    return { level: errors > 0 ? "error" : attention > 0 ? "attention" : "ok",
             errors: errors, attention: attention, incidents: order }
}

// Plazo propio del Home (CalicatasHome.timeoutPrefix): advertencia, no «sin red».
function isHomeTimeout(message) { return _text(message).indexOf("Tiempo de espera agotado") === 0 }

// Rojo error > amarillo advertencia > gris (consultando, sin red, pendiente,
// sin confirmar) > verde solo con datos confirmados por el servidor y nada pendiente.
function auraModeHome(state, diagnostics) {
    var s = state || {}
    var d = diagnostics || {}
    if (d.level === "error") return "error"
    if (d.level === "attention") return "attention"
    if (s.refreshing === true) return "syncing"
    if (!s.loaded) return "unknown"
    var offline = isOfflineMessage(s.projectsError) || isOfflineMessage(s.listError)
    if (offline || Number(s.pendingMedia || 0) > 0 || Number(s.localPending || 0) > 0) return "pending"
    return "synced"
}

function emptyTextHome(state) {
    var s = state || {}
    var base = "Todo en orden. No hay fallos técnicos activos."
    if (isOfflineMessage(s.projectsError) || isOfflineMessage(s.listError))
        return base + "\nSin conexión: se muestran las fichas guardadas en este equipo; se sincronizarán al recuperar la red."
    var pending = Number(s.localPending || 0) + Number(s.pendingMedia || 0)
    if (pending > 0)
        return base + "\nHay " + pending + " elemento(s) guardados en el equipo pendientes de sincronizar; no es un fallo."
    if (!s.loaded || s.refreshing === true) return "Consultando el estado de tus calicatas…"
    return base + "\nTus calicatas están sincronizadas con el servidor."
}

import QtQuick

// Controlador ÚNICO de conversación de InGe IA (como el Dock contextual: un
// solo componente global; cambia el contexto, no la interfaz). Usa el servicio
// real InGeAssistant (GeminiAssistant -> /functions/v1/inge-ai-gemini, sesión
// autenticada). Contrato: request({operation:"chat", id, messages:[{role:
// "user"|"assistant", text}]}) -> replyReady({id, ok, respuesta} | {id, error}).
//  - Historial por usuario Y módulo durante la sesión (sin persistencia).
//  - Sólo se enrutan respuestas con id propio ("chat-…"): el saludo del Home
//    usa otros ids y nunca se mezcla.
//  - Ventana acotada (5 turnos, 4000 caracteres por turno; el servicio rechaza >32 KB).
//  - Un turno a la vez (sin solicitudes duplicadas); errores reales con Reintentar.
//  - Las herramientas nativas las publica el módulo activo [module.tools] y las
//    ejecuta el anfitrión (HomeScreen) con comandos existentes y validados.
Item {
    id: assistant
    visible: false
    property var service: typeof InGeAssistant !== "undefined" ? InGeAssistant : null
    property string userId: ""
    // Módulo activo: { id, name, instructions, data, tools:[{id,label,glyph,primary,enabled}] }
    property var module: ({ id: "home", name: "InGe+", instructions: "", data: "", tools: [] })
    readonly property string contextId: String(module && module.id || "home")
    readonly property bool available: !!service && service.available === true
    readonly property string key: userId + "|" + contextId

    property var histories: ({})               // key -> [{role, text, kind}]
    property int revision: 0
    readonly property var messages: { revision; return histories[key] || [] }
    property string pendingId: ""
    property string pendingKey: ""
    property var pendingDone: null
    readonly property bool busy: pendingId.length > 0
    property string lastError: ""
    property var retryAction: null
    // Respeta el enfriamiento indicado por Gemini ante HTTP 429.
    property int cooldownSeconds: 0
    Timer {
        interval: 1000
        repeat: true
        running: assistant.cooldownSeconds > 0
        onTriggered: assistant.cooldownSeconds = Math.max(0, assistant.cooldownSeconds - 1)
    }
    property var proposals: []                 // propuestas estructuradas del módulo (p. ej. gastos)
    property string proposalsKey: ""
    property var toolRunner: null               // function(toolId) del anfitrión

    onUserIdChanged: resetAll()
    function resetAll() {                       // cambio de cuenta: nada se arrastra
        if (service && pendingId.length) service.cancelAll()
        histories = ({}); revision++
        pendingId = ""; pendingKey = ""; pendingDone = null
        lastError = ""; retryAction = null; cooldownSeconds = 0
        proposals = []; proposalsKey = ""
    }
    function push(k, message) {
        var all = histories
        var list = (all[k] || []).slice()
        list.push(message)
        if (list.length > 60) list = list.slice(list.length - 60)
        all[k] = list
        histories = all
        revision++
    }
    // Nota local (resultado de una herramienta nativa): se muestra, no se envía al modelo.
    function note(text) { push(key, { role: "tool", text: String(text), kind: "tool" }) }

    function preamble() {
        var m = module || {}
        var p = "[Contexto InGe+ · " + String(m.name || "InGe+") + "] Eres InGe IA, el asistente de la app de ingeniería InGe+. "
                + "Responde en español, claro y breve. No inventes datos, resultados ni registros; si falta información, pregúntala. "
                + "No puedes guardar ni modificar datos: las acciones las confirma el usuario en la app. "
                + String(m.instructions || "")
        if (String(m.data || "").length) p += "\nDatos autorizados del contexto: " + String(m.data).slice(0, 2500)
        return p
    }
    // Ventana enviada: últimos turnos user/assistant; el primero siempre es del usuario
    // y lleva el contexto del módulo (sin tokens ni identificadores internos).
    function buildTurns(list, extraUserText) {
        var turns = list.filter(function(m) { return m.role === "user" || m.role === "assistant" })
                        .map(function(m) { return { role: m.role, text: String(m.text).slice(0, 4000) } })
        if (extraUserText) turns.push({ role: "user", text: String(extraUserText).slice(0, 4000) })
        turns = turns.slice(-5)
        while (turns.length && turns[0].role !== "user") turns.shift()
        if (turns.length) turns[0] = { role: "user", text: (preamble() + "\n\nMensaje del usuario:\n" + turns[0].text).slice(0, 4000) }
        return turns
    }
    function call(turns, done) {
        if (!available) { lastError = "InGe IA no está disponible: inicia sesión con conexión a Internet."; return false }
        if (busy || cooldownSeconds > 0) return false
        var id = "chat-" + Date.now() + "-" + Math.floor(Math.random() * 1000)
        pendingId = id; pendingKey = key; pendingDone = done
        lastError = ""
        if (!service.request({ operation: "chat", id: id, messages: turns })) {
            pendingId = ""; pendingKey = ""; pendingDone = null
            lastError = "No se pudo enviar la consulta. Revisa la sesión y vuelve a intentarlo."
            return false
        }
        return true
    }
    function send(text) {
        var t = String(text || "").trim()
        if (!t.length || busy || !available || cooldownSeconds > 0) return false
        var k = key
        push(k, { role: "user", text: t.slice(0, 4000), kind: "chat" })
        var turns = buildTurns(histories[k] || [])
        var ok = call(turns, function(reply) {
            if (reply.error) { assistant.fail(String(reply.error), function() { assistant.resend(k) }, reply); return }
            assistant.push(k, { role: "assistant", text: String(reply.respuesta), kind: "chat" })
        })
        if (!ok) retryAction = function() { assistant.resend(k) }
        return ok
    }
    // Reintento del último mensaje del usuario (sin duplicarlo en el historial).
    function resend(k) {
        if (k !== key || busy || cooldownSeconds > 0) return
        var turns = buildTurns(histories[k] || [])
        if (!turns.length) return
        call(turns, function(reply) {
            if (reply.error) { assistant.fail(String(reply.error), function() { assistant.resend(k) }, reply); return }
            assistant.push(k, { role: "assistant", text: String(reply.respuesta), kind: "chat" })
        })
    }
    // Consulta estructurada (herramienta nativa): la respuesta va al módulo, no al chat.
    function ask(instruction, done) {
        var k = key
        return call(buildTurns(histories[k] || [], instruction), function(reply) {
            if (reply.error) { assistant.fail(String(reply.error), null, reply); return }
            done(String(reply.respuesta))
        })
    }
    function fail(text, retry, detail) {
        lastError = text.length ? text : "InGe IA no respondió."
        retryAction = retry
        var d = detail || {}
        var isLimited = String(d.code || "") === "GEMINI_RATE_LIMIT" || String(d.code || "") === "RATE_LIMIT"
                        || Number(d.provider_status || 0) === 429
        cooldownSeconds = isLimited ? Math.max(30, Math.min(300, Math.ceil(Number(d.retry_after_seconds || 60)))) : 0
    }
    function retry() {
        if (busy || cooldownSeconds > 0) return
        var r = retryAction; retryAction = null; lastError = ""
        if (r) r()
    }
    function runTool(toolId) { if (toolRunner) toolRunner(String(toolId)) }
    function setProposals(list) { proposals = list || []; proposalsKey = key }
    property var proposalValidator: null       // function(p) -> p revalidada (módulo)
    function editProposal(index, field, value) {
        var list = proposals.slice()
        if (index < 0 || index >= list.length) return
        var p = Object.assign({}, list[index])
        p[field] = String(value)
        list[index] = proposalValidator ? proposalValidator(p) : p
        proposals = list
    }

    Connections {
        target: assistant.service
        ignoreUnknownSignals: true
        function onReplyReady(reply) {
            if (!reply || String(reply.id || "") !== assistant.pendingId || !assistant.pendingId.length) return
            var done = assistant.pendingDone
            assistant.pendingId = ""; assistant.pendingKey = ""; assistant.pendingDone = null
            var ok = !reply.error && reply.ok !== false && String(reply.respuesta || "").length > 0
            if (done) done(ok ? reply : Object.assign({}, reply, { error: String(reply.error || "InGe IA no devolvió una respuesta.") }))
        }
        function onAvailableChanged() { if (!assistant.available && assistant.pendingId.length) { assistant.pendingId = ""; assistant.pendingDone = null } }
    }
}

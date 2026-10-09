import QtQuick 2.15
import QtQuick.Controls
import QtQuick.Layouts 1.15
import QtQuick.Effects
import QtQuick.Shapes as Shapes
import QtQml.Models 2.15
import Qt.labs.folderlistmodel 2.1
import InGe 1.0
import "../lib/GpsBus.js" as GpsBus
import "../lib/CalicataRules.js" as Rules
import "../lib/CalicataElevation.js" as Elevation
import "../lib/PropACalicataIconMap.js" as CalIcons
import "../flowcore" as FlowCore
import "../components" as Components
import InGe.CoreFlow 3.0 as Mobile


Item {
    id: root
    property var flow: null
    property bool flowMotionEnabled: true
    property bool flowReduceMotion: false
    property int flowMotionLevel: 2
    property string coreReviewId: ""
    property string coreSnapshot: ""
    property string coreFeedback: ""
    property var coreFindings: []
    property string coreInterpretation: ""
    property string _coreReviewPurpose: "review"
    readonly property bool coreReviewBusy: coreReviewId.length > 0
    readonly property bool coreReviewAvailable:
        typeof CoreRemote !== "undefined" && CoreRemote !== null && CoreRemote.online === true
    property bool _coreReviewRetryPending: false
    property bool _derivingLab: false

    function setLabEvidence(index, key, value) {
        if(index<0 || index>=cortesModel.count) return
        var extra=JSON.parse(cortesModel.get(index)._extraJson || "{}")
        extra[key]=value
        cortesModel.setProperty(index,"_extraJson",JSON.stringify(extra))
        root._markDirty()
    }

    // Web parity: la clasificación de laboratorio (primary_sucs, is_composite,
    // secondary_sucs, aashto) la decide el técnico en Laboratorio. La revisión
    // (soilClassification) solo sugiere: nunca escribe mientras se escribe.
    function deriveLabFields() {
        if(_derivingLab || _loading) return
        _derivingLab=true
        for(var i=0;i<cortesModel.count;++i) {
            var row=cortesModel.get(i), extra=root._labAuthority(JSON.parse(row._extraJson || "{}"))
            var review=Rules.webLabValidate(row, extra)
            extra.web_lab_valid=review.valid
            extra.web_lab_errors=review.errors
            extra.web_lab_projection=review.projection
            // Identidad del laboratorio = UUID del estrato (remoto si existe),
            // nunca la posición: viaja con la fila al mover/insertar/eliminar.
            if(!extra.local_stratum_id) extra.local_stratum_id=extra.remote_stratum_id || root._newLabUuid()
            var form=Rules.labForm(row, extra), web=Rules.reviewLaboratorySample(form)
            extra.web_lab_review={
                status: Rules.laboratoryReviewStatus(form, web),
                ip: web.ip === null ? "" : String(web.ip),
                aashto: web.aashto, sucs: web.sucs, observations: web.observations
            }
            var serialized=JSON.stringify(extra)
            if(serialized!==row._extraJson) cortesModel.setProperty(i,"_extraJson",serialized)
        }
        _derivingLab=false
    }

    function adoptStratumIdentities(cortes) {
        cortes = cortes || []
        for (var c = 0; c < cortes.length; ++c) {
            var remote = String(cortes[c].remote_stratum_id || ""), local = String(cortes[c].local_stratum_id || "")
            if (!remote.length || !local.length) continue
            root._adoptStratumIdentity(local, remote)
        }
    }

    function _adoptStratumIdentity(localId, remoteId) {
        for (var i = 0; i < cortesModel.count; ++i) {
            var extra = JSON.parse(cortesModel.get(i)._extraJson || "{}")
            if (extra.local_stratum_id !== localId) continue
            if (extra.remote_stratum_id === remoteId) return
            extra.remote_stratum_id = remoteId
            cortesModel.setProperty(i, "_extraJson", JSON.stringify(extra))
            return
        }
    }

    Connections {
        target: root.doc
        ignoreUnknownSignals: true
        function onStratumIdentityBound(localId, remoteId) { root._adoptStratumIdentity(localId, remoteId) }
    }

    function _newLabUuid() {
        return "xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx".replace(/[xy]/g, function(c) {
            var r = Math.random() * 16 | 0
            return (c === "x" ? r : (r & 0x3 | 0x8)).toString(16)
        })
    }

    // Autoridad del laboratorio = primary_sucs / is_composite / secondary_sucs
    // (calicata_lab_results). Fichas anteriores solo guardaban la combinación
    // confirmada en lab_confirmed_sucs ("GW-SC", "Pt"): se lee una vez, sin
    // borrarla. lab_confirmed_sucs queda como espejo de compatibilidad.
    function _labAuthority(extra) {
        var legacy = String(extra.lab_confirmed_sucs || "").trim().toUpperCase()
        if (!String(extra.primary_sucs || "").length && legacy.length) {
            var parts = legacy.split("-")
            extra.primary_sucs = Rules.webSucsCodes.indexOf(parts[0]) >= 0 ? parts[0] : ""
            extra.secondary_sucs = parts.length > 1 && Rules.webSucsCodes.indexOf(parts[1]) >= 0 ? parts[1] : ""
            extra.is_composite = extra.primary_sucs.length > 0 && extra.secondary_sucs.length > 0
        }
        var primary = String(extra.primary_sucs || "").toUpperCase(), secondary = String(extra.secondary_sucs || "").toUpperCase()
        extra.lab_confirmed_sucs = primary.length
            ? primary + (extra.is_composite === true && secondary.length && secondary !== primary ? "-" + secondary : "") : ""
        return extra
    }

    // ===== Laboratorio (autoridad de SUCS/AASHTO) =====
    // Ensayos -> sugerencia (Web soilClassification) -> el técnico adopta con un
    // clic o elige en los selectores -> se guarda -> Estrato y patrón lo proyectan.
    property string labTab: "lab"
    function labInfo(i) {
        if (i < 0 || i >= cortesModel.count) return null
        var p = root.corteToPlainObject(cortesModel.get(i))
        var form = Rules.labForm(p, p)
        var web = Rules.reviewLaboratorySample(form)
        var hasTests = Rules.hasLabTestData(form)
        var sample = Rules.labSampleSummary(p, i)
        var hasSample = sample.hasSample
        var projection = Rules.labProjection(p)
        var classified = projection.primary.length > 0 || projection.aashto.length > 0
        var stage = Rules.labStage({ hasSample: hasSample, hasTests: hasTests,
                                     suggestion: !!(web.sucs || web.aashto), confirmed: classified })
        var sampleType = sample.type
        var pendingList = Array.isArray(p.lab_cloud_pending) ? p.lab_cloud_pending : []
        return {
            key: root._liveStratumId(p) || ("row:" + i), index: i, pending: pendingList.length > 0, sample: sample,
            plain: p, form: form, review: web, suggestion: Rules.labSuggestion(form, web), projection: projection,
            reviewStatus: Rules.laboratoryReviewStatus(form, web), validation: Rules.webLabValidate(p, p),
            hasTests: hasTests, hasSample: hasSample, origin: root.labOriginLabel(p),
            stage: stage, stageLabel: Rules.LAB_STAGE_LABELS[stage],
            labText: classified ? (projection.sucs || "—") + " · " + (projection.aashto || "—") : "",
            sampleType: sampleType,
            sampleText: hasSample ? (sampleType || "Muestra") + " · " + sample.reference
                                    + (sample.interval.length ? " · " + sample.interval : "")
                                  : "Sin muestra"
        }
    }
    // Origen = el mismo sistema global de Perfil: material_origin (Natural /
    // Antrópico / Mixto); si no se eligió, lo implican sus propios datos de Perfil
    // (trama RA o datos de relleno -> Antrópico; origen geológico -> Natural).
    function labOriginLabel(p) {
        var origin = root.prfOriginLabel(p.material_origin)
        if (origin.length) return origin
        if (p.pattern_anthropic === true || String(p.fill_type || "").length || String(p.fill_context || "").length)
            return "Antrópico"
        if (String(p.natural_origin || "").length) return "Natural"
        return ""
    }

    // ===== Laboratorio: acciones únicas (pantalla y Dock usan estas funciones) =====
    property string labFilterKey: ""   // "" todos | "pending" | UUID del estrato
    property string labView: "strata"  // "strata" (Estratos y muestras) | "results" (Resultados y seguimiento)
    // Detalle de Laboratorio abierto: estado propio. profileMode lo reinician las
    // transiciones de etapa (scrollToSection), lo que dejaba la cabecera genérica "Listo".
    property bool labSheetActive: false
    // Cierre en curso: la ventana anima su salida (Popup.exit) y solo al terminar
    // (onClosed) se limpia el estado. Nunca visible=false directo.
    property bool labDetailClosing: false
    property bool labOriginValid: false
    property real labOriginX: 0
    property real labOriginY: 0
    Connections {
        target: stratumSheet
        function onClosed() {
            root.labSheetActive = false
            root.labDetailClosing = false
            stratumSheet.offsetX = 0
            stratumSheet.offsetY = 0
            // La salida deja opacity/scale en su valor final: se restauran para la
            // siguiente apertura (Profundidad de Perfil abre sin transición).
            stratumSheet.opacity = 1
            stratumSheet.scale = 1
        }
    }
    // Única vía de cierre del detalle (flecha, Back del sistema, toque fuera).
    function closeLabDetail() {
        if (!root.labSheetActive || root.labDetailClosing || !stratumSheet.visible) return false
        if (!root.commitPendingField()) return false
        root.labDetailClosing = true
        root.dismissInputForNavigation()
        root.finishStratum(false)   // guarda y llama stratumSheet.close() -> transición de salida
        return true
    }
    // Tabs: indicador desplazable + cambio de contenido con fundido/desplazamiento corto.
    property real labTabFade: 1
    property real labTabShift: 0
    property string _labTabNext: "lab"
    property int _labTabDir: 1
    SequentialAnimation {
        id: labTabSwitch
        NumberAnimation { target: root; property: "labTabFade"; to: 0; duration: root.flow ? root.flow.duration(90) : 90; easing.type: Easing.InQuad }
        ScriptAction { script: { root.labTab = root._labTabNext; root.labTabShift = root._labTabDir * root.dp(10) } }
        ParallelAnimation {
            NumberAnimation { target: root; property: "labTabFade"; to: 1; duration: root.flow ? root.flow.duration(170) : 170; easing.type: Easing.OutCubic }
            NumberAnimation { target: root; property: "labTabShift"; to: 0; duration: root.flow ? root.flow.duration(200) : 200; easing.type: Easing.OutCubic }
        }
    }
    function setLabTab(key) {
        if (["lab", "context", "history"].indexOf(key) < 0 || (key === root.labTab && !labTabSwitch.running)) return
        var order = ["lab", "context", "history"]
        root._labTabDir = order.indexOf(key) >= order.indexOf(root.labTab) ? 1 : -1
        root._labTabNext = key
        if (!root.flow || !root.flow.motionAllowed || !stratumSheet.visible) {
            labTabSwitch.stop(); root.labTab = key; root.labTabFade = 1; root.labTabShift = 0
            return
        }
        labTabSwitch.restart()
    }
    // Registrar/editar muestra = el MISMO editor de Perfil (misma fila y campos).
    function labEditSampleInProfile(index) {
        if (index < 0 || index >= cortesModel.count) return
        if (stratumSheet.opened) root.finishStratum(false)
        root.selectStratum(index, "field")
    }
    property bool _labActionGuard: false
    Timer { id: labActionGuardTimer; interval: 450; repeat: false; onTriggered: root._labActionGuard = false }
    readonly property bool labDetailOpen: stratumSheet.visible && root.labSheetActive && !root.labDetailClosing
    readonly property var labInfosAll: {
        root._cortesRevision
        var list = []
        for (var i = 0; i < cortesModel.count; ++i) list.push(root.labInfo(i))
        return list
    }
    readonly property int labPendingCount: root.labInfosAll.filter(function(x) { return x && x.pending }).length
    readonly property int labDataCount: root.labInfosAll.filter(function(x) { return x && (x.hasSample || x.hasTests) }).length
    readonly property var labStrataEntries: root.labInfosAll.map(function(x, i) {
        return { key: x ? x.key : "row:" + i, label: "Estrato " + (i + 1) }
    })
    function labIndexForKey(key) {
        root._flushCortesRevision()
        for (var i = 0; i < root.labInfosAll.length; ++i)
            if (root.labInfosAll[i] && root.labInfosAll[i].key === key) return i
        return -1
    }
    function labCardVisible(info) {
        if (!info) return false
        if (root.labFilterKey === "") return true
        if (root.labFilterKey === "pending") return info.pending
        return info.key === root.labFilterKey
    }
    function labSetFilter(key) {
        root._flushCortesRevision()
        root.labFilterKey = key === "pending" && root.labPendingCount === 0 ? "" : String(key || "")
    }
    function _labGuarded() {
        if (root._labActionGuard) return false
        root._labActionGuard = true
        labActionGuardTimer.restart()
        return true
    }
    // Nueva muestra: abre la sección Muestra del estrato filtrado o del primero
    // sin muestra. Sin estratos lleva a Perfil. Nunca crea filas duplicadas.
    function labNewSample() {
        root._flushCortesRevision()
        if (!root._labGuarded()) return
        if (cortesModel.count === 0) { root.labGoProfile(); return }
        var byFilter = root.labFilterKey.length && root.labFilterKey !== "pending" ? root.labIndexForKey(root.labFilterKey) : -1
        var index = byFilter >= 0 ? byFilter : root.labFirstCandidate()
        if (index < 0) return
        root.openLabForStratum(index)
        root.labTab = "lab"
    }
    function labGoProfile() {
        if (stratumSheet.opened) root.finishStratum(false)
        root.scrollToSection(4)
    }
    function labOpenHistory() {
        var index = root.selectedStratum >= 0 && root.selectedStratum < cortesModel.count ? root.selectedStratum : -1
        if (index < 0)
            for (var i = 0; i < root.labInfosAll.length && index < 0; ++i)
                if (root.labInfosAll[i] && (root.labInfosAll[i].hasSample || root.labInfosAll[i].hasTests)) index = i
        if (index < 0) index = cortesModel.count ? 0 : -1
        if (index < 0) return
        if (!root.labDetailOpen || root.selectedStratum !== index) root.openLabForStratum(index)
        root.labTab = "history"
    }
    function labSummaryText() {
        var n = { strata: 0, sample: 0, tested: 0, suggested: 0, confirmed: 0, pending: 0 }
        for (var i = 0; i < root.labInfosAll.length; ++i) {
            var x = root.labInfosAll[i]
            if (!x) continue
            n.strata++
            if (x.hasSample) n.sample++
            if (x.hasTests) n.tested++
            if (x.stage === "suggested") n.suggested++
            if (x.stage === "confirmed") n.confirmed++
            if (x.pending) n.pending++
        }
        var nl = String.fromCharCode(10)
        return n.strata + " estratos" + nl + n.sample + " con muestra" + nl + n.tested + " ensayados" + nl
             + n.suggested + " con clasificación sugerida" + nl + n.confirmed + " con clasificación adoptada" + nl
             + n.pending + " pendientes de sincronizar"
    }
    // Comandos del Dock (contexto Laboratorio): mismas funciones que la pantalla.
    function runLabCommand(command) {
        var c = String(command || "")
        if (c === "new") root.labNewSample()
        else if (c === "profile") root.labGoProfile()
        else if (c === "pending") root.labSetFilter("pending")
        else if (c.indexOf("filter:") === 0) root.labSetFilter(c.substring(7))
        else if (c === "summary") { if (stratumSheet.opened) root.finishStratum(true); root.labView = "results" }
        else if (c === "strata") root.labView = "strata"
        else if (c === "history") root.labOpenHistory()
        else if (c === "close") root.closeLabDetail()
        else if (c.indexOf("tab:") === 0) root.setLabTab(c.substring(4))
        else if (c === "editSample") root.labEditSampleInProfile(root.selectedStratum)
    }
    function labKindChip(info) {
        if (!info) return ""
        return info.origin === "Antrópico" ? "RA" : info.origin === "Natural" ? "NAT"
             : info.origin === "Mixto / intervenido" ? "MIX" : ""
    }
    function labContextText(info) {
        if (!info) return ""
        var base = info.origin === "Antrópico" ? "Relleno antrópico" : info.origin === "Natural" ? "Suelo natural"
                 : info.origin === "Mixto / intervenido" ? "Mixto / intervenido"
                 : info.origin.length ? info.origin : "Sin origen en Perfil"
        return base + " · " + (info.hasSample ? (info.sampleType || "Muestra") : "Sin muestra")
    }
    function labStageColor(stage, soft) {
        if (stage === "confirmed") return soft ? root.cGenGreenSoft : root.cGenGreen
        if (stage === "suggested") return soft ? root.cGenOrangeSoft : root.cGenOrange
        if (stage === "in_progress") return soft ? root.cGenBlueSoft : root.cGenBlue
        return soft ? root.cSurfaceAlt : root.cMuted
    }
    // IP = LL − LP derivado (Web): sin un límite no hay índice, nunca un cero.
    function labIpText(info) {
        if (!info) return "—"
        return info.review.ip === null || info.review.ip === undefined ? "—" : String(info.review.ip)
    }
    function labContextRows(info) {
        if (!info) return []
        var p = info.plain
        function v(x) { var t = String(x === undefined || x === null ? "" : x).trim(); return t.length ? t : "—" }
        var rows = [
            { label: "Profundidad", value: v(p.de) + " – " + v(p.a) + " m" },
            { label: "Origen", value: info.origin === "Antrópico" ? "Antrópico" + (String(p.fill_type || "").length ? " · " + p.fill_type : "")
                                                         + (String(p.fill_context || "").length ? " · " + p.fill_context : "")
                                    : v(info.origin) + (String(p.natural_origin || "").length ? " · " + p.natural_origin : "") },
            { label: "Patrón gráfico", value: info.projection.sucs.length ? info.projection.sucs : "Pendiente de laboratorio" },
            { label: "Descripción", value: v(p.descripcion) },
            { label: "Humedad de campo", value: p.humedad >= 0 && p.humedad < root.humItems.length ? root.humItems[p.humedad] : "—" },
            { label: "Consistencia", value: v(p.consistency) },
            { label: "Excavabilidad", value: p.excavabilidad >= 0 && p.excavabilidad < root.excItems.length ? root.excItems[p.excavabilidad] : "—" },
            { label: "Muestra de campo", value: info.sampleText + (String(p.sample_code || "").length ? " · " + p.sample_code : "") }
        ]
        // Valor anterior del estrato (calicata_strata.sucs/aashto): se conserva y
        // solo se muestra; la clasificación vigente es la del laboratorio.
        var legacy = [String(p.sucs || "").trim(), String(p.aashto || "").trim()].filter(function(x) { return x.length })
        if (legacy.length) rows.push({ label: "Clasificación anterior del estrato", value: legacy.join(" · ") })
        if (String(p.color || "").length) rows.splice(4, 0, { label: "Color", value: String(p.color) })
        return rows
    }
    function labHistoryRows(info) {
        if (!info) return []
        var p = info.plain, rows = []
        if (String(p.test_date || "").length)
            rows.push({ label: String(p.test_date), value: "Ensayo registrado" + (String(p.laboratory_source || "").length ? " · " + p.laboratory_source : "") })
        if (String(p.lab_confirmed_at || "").length)
            rows.push({ label: String(p.lab_confirmed_at).slice(0, 10), value: "Clasificación adoptada en laboratorio"
                        + (info.projection.sucs.length ? " · SUCS " + info.projection.sucs : "")
                        + (info.projection.aashto.length ? " · AASHTO " + info.projection.aashto : "") })
        return rows
    }
    function labFirstCandidate() {
        for (var i = 0; i < cortesModel.count; ++i) {
            var info = root.labInfo(i)
            if (info && !info.hasSample && !info.hasTests) return i
        }
        return cortesModel.count ? 0 : -1
    }
    // Selectores y chips del laboratorio = Web update("primarySucs" | "isComposite"
    // | "secondarySucs" | "aashto", value). Un chip sugerido solo escribe al tocarlo.
    function setLabClassification(index, key, value) {
        if (index < 0 || index >= cortesModel.count) return false
        var extra = root._labAuthority(JSON.parse(cortesModel.get(index)._extraJson || "{}"))
        if (key === "primary_sucs" || key === "secondary_sucs") {
            var code = String(value || "").toUpperCase()
            if (code.length && Rules.webSucsCodes.indexOf(code) < 0) return false
            extra[key] = code
        } else if (key === "is_composite") {
            extra.is_composite = value === true
        } else if (key === "aashto") {
            var aashto = String(value || "")
            if (aashto.length && Rules.webAashtoCodes.indexOf(aashto) < 0) return false
            extra.lab_confirmed_aashto = aashto
        } else {
            return false
        }
        extra.lab_confirmed_at = new Date().toISOString()
        cortesModel.setProperty(index, "_extraJson", JSON.stringify(root._labAuthority(extra)))
        root._markDirty()
        root.deriveLabFields()
        console.info("INGE_LAB_ADOPT field=" + key + " stratum=" + (index + 1))
        return true
    }
    function adoptLabSucs(index, code) { return root.setLabClassification(index, "primary_sucs", code) }
    function adoptLabAashto(index, code) { return root.setLabClassification(index, "aashto", code) }
    function pickLabClassification(index, key) {
        if (index < 0 || index >= cortesModel.count) return
        var form = root.labInfo(index).form
        if (key === "aashto")
            root.prfPick("AASHTO", Rules.webAashtoCodes, form.aashto, "map.layers",
                         function(v) { root.setLabClassification(index, "aashto", v) })
        else if (key === "secondary_sucs")
            root.prfPick("Segundo SUCS", Rules.webSucsCodes.filter(function(c) { return c !== form.primarySucs }),
                         form.secondarySucs, "geotechnical.stratigraphy",
                         function(v) { root.setLabClassification(index, "secondary_sucs", v) })
        else
            root.prfPick("SUCS principal", Rules.webSucsCodes, form.primarySucs, "geotechnical.stratigraphy",
                         function(v) { root.setLabClassification(index, "primary_sucs", v) })
    }
    // LL / LP: enteros (Web validateInteger; columnas integer en el servidor).
    function commitLabLimit(index, key, text) {
        if (index < 0 || index >= cortesModel.count) return false
        var value = Rules.webLabNormalizeLimit(text)
        if (value === null) {
            root.showInfo("Plasticidad", "LL y LP son números enteros ≥ 0 (p. ej. 32), igual que en InGe+ Web.")
            return false
        }
        var row = cortesModel.get(index)
        var ll = Rules.parseDecimalSafe(key === "wl" ? value : row.wl), lp = Rules.parseDecimalSafe(key === "lp" ? value : row.lp)
        if (isFinite(ll) && isFinite(lp) && lp > ll) {
            root.showInfo("Plasticidad", "LP debe ser menor o igual que WL.")
            return false
        }
        cortesModel.setProperty(index, key, value)
        root._markDirty()
        root.deriveLabFields()
        return true
    }
    function setLabSampleType(index, value) {
        if (index < 0 || index >= cortesModel.count) return
        cortesModel.setProperty(index, "tipo_muestra", value)
        if (value !== "Otro") cortesModel.setProperty(index, "tipo_otro", "")
        cortesModel.setProperty(index, "tipoText", value === "Otro" ? String(cortesModel.get(index).tipo_otro || "") : value)
        var row = cortesModel.get(index)
        root._inheritSampleInterval(index, row.de, row.a)
        root._markDirty()
    }

    // +/- (Web stepLaboratoryPercentDraft): límites vivos de la secuencia
    // granulométrica; LL/LP enteros >= 0. Pasa por el mismo commit validado.
    function stepLabField(index, key, direction, step) {
        if (index < 0 || index >= cortesModel.count) return
        var row = cortesModel.get(index), extra = JSON.parse(row._extraJson || "{}")
        if (key === "wl" || key === "lp") {
            var next = Rules.stepLabInteger(row[key], direction * Math.max(1, Math.round(step)), 999)
            cortesModel.setProperty(index, key, next)
            root._markDirty()
            root.deriveLabFields()
            return
        }
        var snapshot = Object.assign({}, row, { passing_no4: extra.passing_no4 })
        var current = key === "passing_no4" ? extra.passing_no4 : row[key]
        var value = Rules.stepLabPercent(current, Rules.webLabBounds(snapshot, key), direction, step)
        if (value !== String(current === undefined || current === null ? "" : current))
            root.commitWebLabPercent(index, key, value)
    }

    function requestAssistedReview(purpose) {
        // La IA se solicita desde Interpretación; el asistente del Dock no revisa la ficha.
        if (purpose !== "interpretation") return false
        if (root._loading || root._documentClosing || root.coreReviewBusy)
            return false
        if (!root.commitPendingField()) return false

        root._coreReviewPurpose = "interpretation"
        root.reviewForExport()
        root.coreFindings = []
        root.coreInterpretation = ""
        aiReviewDialog.open()

        if (typeof CoreRemote === "undefined" || CoreRemote === null) {
            root.coreFeedback = "InGe AI no está disponible en esta compilación. La revisión técnica local sigue activa."
            return false
        }

        if (CoreRemote.online !== true) {
            root.coreFeedback = "Conectando con InGe AI…"
            root._coreReviewRetryPending = true
            try { CoreRemote.start() } catch (startError) {}
            coreReviewRetry.restart()
            return false
        }

        var state = root.exportState()
        if (!state.cortes || !state.cortes.length) {
            root.coreFeedback = "Agrega al menos un estrato antes de solicitar la revisión asistida."
            return false
        }

        var serialized = JSON.stringify(state)
        root.coreSnapshot = serialized
        root._coreReviewRetryPending = false
        try {
            root.coreReviewId = String(CoreRemote.interpretCalicata(state) || "")
        } catch (reviewError) {
            root.coreReviewId = ""
            root.coreFeedback = "InGe AI no pudo iniciar el análisis. La revisión técnica local sigue disponible."
            return false
        }

        if (!root.coreReviewId.length) {
            root.coreFeedback = "InGe AI no aceptó la solicitud. Puedes reintentar sin perder la ficha."
            return false
        }

        root.coreFeedback = root._coreReviewPurpose === "interpretation"
                ? "InGe AI está preparando la interpretación del perfil…" : "InGe AI está revisando la ficha…"
        coreReviewTimeout.restart()
        return true
    }

    function cancelCoreReview() {
        var id = root.coreReviewId
        root.coreReviewId = ""
        root._coreReviewRetryPending = false
        coreReviewTimeout.stop()
        coreReviewRetry.stop()
        if (id.length && typeof CoreRemote !== "undefined" && CoreRemote !== null) {
            try { CoreRemote.cancel(id) } catch (cancelError) {}
        }
    }

    function acceptCoreInterpretation() {
        if (root._loading || root._documentClosing || !root.coreInterpretation.length
                || root.coreInterpretation.length > 1000 || JSON.stringify(root.exportState()) !== root.coreSnapshot) {
            root.coreFeedback = "La ficha cambió. Genera una nueva interpretación antes de aplicarla."
            return false
        }
        var interpretation = root.coreInterpretation
        root.coreSnapshot = ""
        root.coreFeedback = ""
        root.coreFindings = []
        root.updateProfileSetup({ interpretation: interpretation })
        aiReviewDialog.close()
        return true
    }

    // Una solicitud sin respuesta nunca deja la Revisión ocupada para siempre.
    Timer {
        id: coreReviewTimeout
        interval: 90000
        repeat: false
        onTriggered: {
            if (!root.coreReviewId.length) return
            root.cancelCoreReview()
            root.coreSnapshot = ""
            root.coreFeedback = "InGe AI no respondió a tiempo. Puedes reintentar; la revisión local sigue disponible."
        }
    }

    Dialog {
        id: aiReviewDialog
        property Item glassBackdropItem: null
        parent: Overlay.overlay
        modal: true
        focus: true
        title: "InGe AI"
        width: Math.min(root.width - 24, root.dp(480))
        height: Math.min(parent.height - 48, body.implicitHeight + 120)
        x: (parent.width - width) / 2
        y: (parent.height - height) / 2
        standardButtons: Dialog.Close
        Overlay.modal: GenGlassScrim { popupItem: aiReviewDialog }
        background: GenPopupGlass { popupItem: aiReviewDialog; surfaceName: "calicata-ai-dialog" }
        header: GenDialogTitle { text: aiReviewDialog.title }
        footer: GenDialogButtonBox { standardButtons: aiReviewDialog.standardButtons }
        enter: Transition { NumberAnimation { property: "opacity"; from: 0; to: 1; duration: root.flow && root.flow.motionAllowed ? root.flow.fastDuration : 0 } }
        exit: Transition { NumberAnimation { property: "opacity"; to: 0; duration: root.flow && root.flow.motionAllowed ? root.flow.fastDuration : 0 } }
        contentItem: ScrollView {
            clip: true
            contentWidth: availableWidth
            ColumnLayout {
                id: body
                width: parent.width
                spacing: 10
                // Actividad de InGe AI: indicador inline único (no overlay).
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 12
                    visible: root.coreReviewBusy || root._coreReviewRetryPending
                    FlowCore.FlowThreeBalls {
                        Layout.alignment: Qt.AlignVCenter
                        running: aiReviewDialog.opened
                                 && (root.coreReviewBusy || root._coreReviewRetryPending)
                        color: root.cAccent
                        ballSize: 8
                        reduceMotion: !!root.flow && !root.flow.motionAllowed
                    }
                    Label {
                        Layout.fillWidth: true
                        text: root.coreFeedback
                        color: root.cText
                        wrapMode: Text.WordWrap
                    }
                }
                Label {
                    Layout.fillWidth: true
                    visible: !(root.coreReviewBusy || root._coreReviewRetryPending)
                    text: root.coreFeedback
                    color: root.cText
                    wrapMode: Text.WordWrap
                }
            }
        }
        onClosed: {
            coreReviewRetry.stop()
            if (root.coreReviewId.length || root._coreReviewRetryPending) {
                // Cerrar mientras analiza cancela la solicitud (una respuesta tardía se ignora).
                root.cancelCoreReview()
                root.coreSnapshot = ""
                root.coreFeedback = ""
                root.coreFindings = []
            }
            // Un análisis terminado se conserva en Revisión hasta que la ficha cambie (_markDirty).
        }
    }

    Timer {
        id: coreReviewRetry
        interval: 10000
        repeat: false
        onTriggered: {
            if (!root._coreReviewRetryPending) return
            root._coreReviewRetryPending = false
            if (typeof CoreRemote !== "undefined" && CoreRemote !== null
                    && CoreRemote.online === true) {
                root.requestAssistedReview(root._coreReviewPurpose)
            } else {
                root.coreFeedback = "InGe AI sigue sin conexión. La revisión técnica local y la exportación continúan disponibles."
            }
        }
    }

    Connections {
        target: typeof CoreRemote !== "undefined" ? CoreRemote : null
        ignoreUnknownSignals: true
        function onHealthChanged() {
            if (root._coreReviewRetryPending && CoreRemote.online === true) {
                coreReviewRetry.stop()
                root.requestAssistedReview(root._coreReviewPurpose)
            }
        }
        function onCompleted(id,result,error) {
            if(!root.coreReviewId.length || id!==root.coreReviewId) return
            root.coreReviewId=""
            coreReviewTimeout.stop()

            if(JSON.stringify(root.exportState())!==root.coreSnapshot) {
                root.coreFeedback="La ficha cambió durante el análisis. Vuelve a ejecutar InGe AI para revisar la versión actual."
                return
            }

            if(error) {
                root.coreFeedback="InGe AI no pudo completar el análisis (" + String(error)
                                 + "). La ficha se conserva; puedes reintentar."
                return
            }

            var interpretation = String((result || {}).summary || "").trim()
            if (!interpretation.length || interpretation.length > 1000) {
                root.coreFeedback = "InGe AI no devolvió una interpretación válida de hasta 1000 caracteres. Puedes reintentar."
                return
            }
            // Solo el resumen va al campo; los hallazgos de revisión no se concatenan.
            root.coreInterpretation = interpretation
            root.acceptCoreInterpretation()
        }
    }



    // =========================================================
    // Modo híbrido táctil: phone / tablet / desktop-kit
    // =========================================================
    // El teclado (adjustResize) solo encoge el alto; nunca el ancho. Mientras
    // escribe (IME visible o un campo de texto con foco, que llega antes que el
    // resize) se conserva el alto previo: abrir el IME ya no cambia phone/tablet
    // ni uiScale (re-maquetaba toda la ficha con el campo enfocado en tablets,
    // plegables y landscape). Cualquier otro cambio (rotar, split arriba/abajo,
    // ventanas libres) se acepta. El alto retenido solo se usa con el mismo
    // ancho, asi que una rotacion se clasifica en el mismo frame.
    property real _layoutWidth: 0
    property real _layoutHeight: 0
    function _imeLikely() {
        // Acceso indexado, como InGeCoreFlow: existen en runtime aunque la
        // metadata estatica de qmllint no las enumere.
        if (Qt.inputMethod["visible"] === true)
            return true
        var focusItem = root.Window.activeFocusItem
        return !!focusItem && focusItem["cursorPosition"] !== undefined
    }
    function _updateLayoutSize() {
        if (Math.abs(root.width - root._layoutWidth) > 0.5
                || root.height > root._layoutHeight || !root._imeLikely()) {
            root._layoutHeight = root.height
            root._layoutWidth = root.width
        }
    }
    onWidthChanged: Qt.callLater(root._updateLayoutSize)
    onHeightChanged: Qt.callLater(root._updateLayoutSize)
    readonly property real _layoutMinSide: {
        var w = root.width, h = root.height
        if (Math.abs(w - root._layoutWidth) <= 0.5 && root._layoutHeight > h)
            h = root._layoutHeight
        return Math.min(w, h)
    }
    readonly property bool isPhone: root.width > 0 && root._layoutMinSide < 600
    readonly property bool isTablet: root.width > 0 && root._layoutMinSide >= 600
    readonly property real uiScale: root.isPhone
                                    ? Math.max(0.82, Math.min(1.00, root._layoutMinSide / 430.0))
                                    : Math.max(0.92, Math.min(1.12, root._layoutMinSide / 760.0))
    function dp(v) { return Math.round(v * root.uiScale) }
    // Texto: misma regla que __sp() de CalicatasEditorPage. En telefonos de
    // 360 dp uiScale baja a 0.84 y dp(11) quedaba en 9 px; ninguna fuente de
    // la ficha baja de 12 px. La geometria sigue escalando con dp().
    function sp(v) { return Math.max(12, root.dp(v)) }

    property double _lastTapMs: 0
    readonly property int tapGuardMs: 280
    function safeTap(fn) {
        var now = Date.now()
        if (now - root._lastTapMs < root.tapGuardMs) return
        root._lastTapMs = now
        if (fn) fn()
    }

    width:  parent ? parent.width  : 420
    height: parent ? parent.height : 820

    // ✅ singleton
    readonly property var docsCtl: Docs

    property int _pendingStampIdx: 1
    property url _pendingPickedUrl: ""
    property var _pendingPhotoDoc: null
    property string _pendingPhotoDocId: ""
    property string _pendingPhotoSourceKind: ""
    property bool _photoRequestPending: false
    // Slots cuya imagen se está generando en segundo plano (persistPhoto → photoPersisted).
    property var _photoProcessing: ({})
    // Copias locales provisionales; no cambian la revisión guardada ni la outbox.
    property var _photoLocalPreviews: ({})
    property bool _photoDialogOpenPending: false
    property int _photoRequestSerial: 0
    property bool gpsCaptureActive: false
    property string gpsCaptureStatus: "Listo para actualizar coordenadas"
    property string gpsCaptureTone: "idle"
    property double _gpsBaselineTimestampMs: 0
    property string _pendingGpsDocId: ""
    property int _gpsRequestSerial: 0
    property bool _documentClosing: false
    property real gpsCaptureAccuracyTargetMeters: 25.0
    readonly property int gpsCaptureDeadlineMs: 15000
    property double _gpsDeadlineAtMs: 0
    property var _activeCommitField: null
    property var _pendingCommitFields: []
    signal flushRequested()

    function commitPendingField() {
        // Lo escrito en áreas de texto se confirma al documento antes de seguir.
        flushTypingDirty()
        var pending = _pendingCommitFields.slice()
        for (var i = 0; i < pending.length; ++i)
            if (pending[i] && pending[i].commitPending && !pending[i].commitPending())
                return false
        return true
    }
    property string photoFeedbackText: ""
    property bool _logoRequestPending: false
    property string _pendingLogoPickTarget: ""
    property string _pendingLogoDocId: ""
    property string logoFeedbackText: ""

    function _docInstanceId(candidate) {
        if (!candidate || candidate.instanceId === undefined || candidate.instanceId === null)
            return ""
        return String(candidate.instanceId)
    }

    // === Estado del documento ===
    property string filePath: ""
    property bool dirty: false
    signal titleSuggested(string title)

    property var auth
    property bool darkMode: false
    property int themeMode: 0
    readonly property bool liquidGlass: themeMode === 2

    // ✅ compat con el editor (tabs usan fileUrl)
    property url fileUrl: ""

    // === (opcional) fuentes de logos en móvil ===
    property url logoMtcSource: ""
    property url logoProyectoSource: ""

    property int _pendingDeleteIdx: -1

    // === Paleta: identidad corporativa INGEMA (FlowColors) ===
    // Valores derivados documentados en docs/INGEMA_DESIGN_SYSTEM_APP_20261006.md.
    readonly property var brand: Mobile.InGeCoreFlow.colors
    readonly property color cNavy:   root.darkMode ? "#FFFFFF" : root.brand.ingemaNavy
    readonly property color cTeal:   root.brand.ingemaBlue
    readonly property color cOrange: "#FDAC11"
    readonly property color cLight:  root.cSurfaceAlt
    readonly property color cLight2: root.cSurfaceAlt
    readonly property color cTextDark: root.brand.ingemaDeep
    readonly property color cWhite: "#FFFFFF"

    // Superficies del formulario técnico (claro / oscuro)
    readonly property color cPage: darkMode ? root.brand.ingemaDeep : "#FCFCFC"
    readonly property color cSurface: darkMode ? root.brand.ingemaNavy : "#FFFFFF"
    readonly property color cSurfaceAlt: darkMode ? "#2A3A5A" : "#F1F1EE"
    readonly property color cBorder: darkMode ? "#404F6C" : "#DFE2E6"
    readonly property color cText: darkMode ? "#FFFFFF" : root.brand.ingemaDeep
    readonly property color cMuted: darkMode ? root.brand.ingemaPaperSecondary : root.brand.ingemaInkTertiary
    readonly property color cField: darkMode ? "#182440" : "#FFFFFF"
    readonly property color cAccent: darkMode ? root.brand.ingemaBlueTint : root.brand.ingemaBlue
    // Acentos semánticos de Ficha > General: planos, sin glass ni gradientes.
    // Blue = interacción/en curso, Green = confirmado, Navy = categorías
    // secundarias (antes violeta/turquesa). Naranja se conserva como
    // advertencia semántica ("sugerido").
    readonly property color cGenBlue: darkMode ? root.brand.ingemaBlueTint : root.brand.ingemaBlue
    readonly property color cGenBlueSoft: darkMode ? "#102B52" : root.brand.ingemaBlueWash
    readonly property color cGenOrange: darkMode ? "#FFB35C" : "#DE7A12"
    readonly property color cGenOrangeSoft: darkMode ? "#33271A" : "#FDF2E5"
    readonly property color cGenViolet: darkMode ? root.brand.ingemaPaperSecondary : root.brand.ingemaNavy
    readonly property color cGenVioletSoft: darkMode ? "#2A3A5A" : "#EDEEF1"
    readonly property color cGenTeal: darkMode ? root.brand.ingemaPaperSecondary : root.brand.ingemaNavy
    readonly property color cGenTealSoft: darkMode ? "#2A3A5A" : "#EDEEF1"
    readonly property color cGenGreen: darkMode ? root.brand.ingemaGreenTint : root.brand.ingemaGreen
    readonly property color cGenGreenSoft: darkMode ? "#24302D" : root.brand.ingemaGreenWash

    // The six stages project the existing document. Historical section IDs
    // remain valid for review links.
    property int stageIndex: 0
    property int sectionNavCurrent: 1

    property int _lastStageIndex: 0
    // Mientras una etapa entra (toque o swipe) sus alturas pasan de "sin ancho" al ancho
    // final: esas Behaviors de altura NO se animan entonces (cada frame re-maquetaría toda
    // la columna y re-capturaría el vidrio); siguen animando los cambios del usuario.
    readonly property bool _stageSettling: stageRevealAnimation.running || stageSettleAnimation.running
                                          || stagePeekFade.running || _swipeNavigating
    // El panel de Ubicación se crea en la primera visita y se conserva oculto
    // (no se dibuja fuera de su etapa): antes se destruía y recreaba en cada entrada,
    // dentro del mismo toque (instancia Map + estilo + contexto de render, y los avisos
    // "Timers cannot have negative intervals" que emite QtLocation al crear cada Map).
    property bool _locationMapWarm: false
    onStageIndexChanged: {
        if (stageIndex === 1) _locationMapWarm = true
        // Transición direccional corta: avanzar entra desde la derecha,
        // retroceder entra desde la izquierda.
        var forward = stageIndex > _lastStageIndex
        _lastStageIndex = stageIndex
        if (!_ready) return
        vFlick.cancelFlick()
        vFlick.contentY = 0
        // El swipe ya llevó la página a su sitio siguiendo el dedo.
        if (_swipeNavigating) return
        stageSlideTranslate.x = 0
        finalPageCol.opacity = 1.0
        if (root.flow && root.flow.motionAllowed) {
            // Misma transición visual (fundido + desplazamiento de 56 dp, 220 ms), pero
            // sobre UNA textura del tamaño del viewport (stageMotionSnapshot): la etapa
            // nueva se rasteriza al asentarse y cada frame solo mueve/funde un quad,
            // en vez de re-procesar todo el árbol de la etapa (cientos de nodos y vidrio).
            stageMotionSnapshot.opacity = 0.0
            stageMotionTranslate.x = forward ? root.dp(56) : -root.dp(56)
            stageRevealAnimation.restart()
        } else {
            stageRevealAnimation.stop()
            stageMotionSnapshot.opacity = 1.0
            stageMotionTranslate.x = 0
        }
    }

    // === Swipe horizontal interno entre etapas (manipulación directa) ===
    // Independiente del Back Android. Solo eje X: el scroll vertical sigue
    // perteneciendo a vFlick. La página sigue al dedo desde el touch slop;
    // al soltar se completa o cancela desde la posición actual según
    // distancia (28 % del viewport) o velocidad. Un drag = máximo una etapa,
    // y la navegación real sigue siendo goNextStage()/goPreviousStage().
    readonly property real stageSwipeViewportWidth: Math.max(1, vFlick.width)
    readonly property real stageSwipeCommitRatio: 0.28
    readonly property real stageSwipeFlingVelocity: root.dp(520)
    property bool _swipeNavigating: false
    property bool _swipeCommitPending: false
    property bool _swipePeekFrozen: false
    property int _swipeState: 0          // 0 reposo, 1 siguiendo, -1 rechazado
    property int _swipeDir: 0            // +1 siguiente (entra por la derecha), -1 anterior
    property int _swipePeekStage: -1
    property real _swipeOriginX: 0
    property real _swipeVx: 0

    function _swipeTargetStage(dir) {
        // Mismas reglas que goNextStage/goPreviousStage: en corrección desde
        // Revisión solo se puede volver a Revisión (finishReviewCorrection).
        if (dir > 0)
            return (reviewCorrectionActive || stageIndex >= sectionNavigation.length - 1)
                ? -1 : stageIndex + 1
        if (reviewCorrectionActive) return sectionNavigation.length - 1
        return stageIndex > 0 ? stageIndex - 1 : -1
    }

    function _applySwipeOffset(dx) {
        var dir = dx < 0 ? 1 : -1
        var target = dx === 0 ? -1 : _swipeTargetStage(dir)
        if (target < 0) {
            // Resistencia de borde (General→derecha, Revisión→izquierda):
            // acompaña unos pocos px y vuelve; nunca navega ni sale.
            var limit = root.dp(28)
            var soft = limit * (1 - 1 / (1 + Math.abs(dx) / root.dp(120)))
            _swipeDir = 0
            _swipePeekStage = -1
            stageSlideTranslate.x = (dx < 0 ? -1 : 1) * soft
            return
        }
        _swipeDir = dir
        _swipePeekStage = target
        stageSlideTranslate.x = dx
    }

    function _syncSwipeProgress() {
        if (_swipeState !== 1 && !stageSettleAnimation.running) return
        var p = Math.min(1, Math.abs(stageSlideTranslate.x) / stageSwipeViewportWidth)
        finalPageCol.opacity = 1 - 0.2 * p
    }

    function _settleSwipe(vx) {
        var w = stageSwipeViewportWidth
        var x = stageSlideTranslate.x
        var commit = false
        if (_swipePeekStage >= 0 && _swipeDir !== 0) {
            var along = -_swipeDir   // signo de x que avanza hacia el commit
            var fling = vx * along > stageSwipeFlingVelocity && x * along > root.dp(16)
            var farEnough = x * along > w * stageSwipeCommitRatio
                    && vx * along > -stageSwipeFlingVelocity
            commit = fling || farEnough
        }
        var to = commit ? -_swipeDir * w : 0
        var remaining = Math.abs(to - x)
        // Duración según distancia restante y velocidad del dedo (OutCubic
        // arranca a ~3x la velocidad media): continuidad sin salto.
        var d = remaining / w * 280
        if (Math.abs(vx) > 1) d = Math.min(d, 3000 * remaining / Math.abs(vx))
        var motion = !!(root.flow && root.flow.motionAllowed)
        _swipeCommitPending = commit
        stageSettleAnimation.to = to
        stageSettleAnimation.duration = motion ? Math.round(Math.max(120, Math.min(280, d))) : 0
        stageSettleAnimation.restart()
    }

    function _finishSwipeSettle() {
        var commit = _swipeCommitPending
        _swipeCommitPending = false
        if (!commit) { _resetSwipeVisual(); return }
        var dir = _swipeDir
        _swipeNavigating = true
        var moved = dir > 0 ? goNextStage() : goPreviousStage()
        _swipeNavigating = false
        if (!moved) {
            // Validación pendiente: la página vuelve desde donde está.
            _syncSwipeProgress()
            stageSettleAnimation.to = 0
            stageSettleAnimation.duration = root.flow && root.flow.motionAllowed ? 200 : 0
            stageSettleAnimation.restart()
            return
        }
        // La etapa real ya está debajo del peek, en la misma posición y con
        // la misma cabecera: se desvanece solo la capa del peek.
        _swipePeekFrozen = true
        stageRevealAnimation.stop()
        stageMotionSnapshot.opacity = 1.0
        stageMotionTranslate.x = 0
        stageSlideTranslate.x = 0
        finalPageCol.opacity = 1.0
        stagePeekFade.duration = root.flow && root.flow.motionAllowed ? 140 : 0
        stagePeekFade.restart()
    }

    function _resetSwipeVisual() {
        stageSlideTranslate.x = 0
        finalPageCol.opacity = 1.0
        _swipePeekFrozen = false
        _swipePeekStage = -1
        _swipeDir = 0
        stagePeekLayer.opacity = 1.0
    }

    NumberAnimation {
        id: stageSettleAnimation
        target: stageSlideTranslate
        property: "x"
        easing.type: Easing.OutCubic
        onFinished: root._finishSwipeSettle()
    }

    NumberAnimation {
        id: stagePeekFade
        target: stagePeekLayer
        property: "opacity"
        from: 1.0
        to: 0.0
        easing.type: Easing.OutCubic
        onFinished: root._resetSwipeVisual()
    }

    DragHandler {
        id: stageSwipeHandler
        target: null
        yAxis.enabled: false
        // Touch slop propio (10 dp): solo decide eje. Los controles que
        // retienen el grab (Flickable vertical en movimiento, sliders,
        // mapas con handlers propios) no pueden ser robados.
        dragThreshold: Math.round(root.dp(10))
        acceptedButtons: Qt.LeftButton
        minimumPointCount: 1
        maximumPointCount: 1
        enabled: root._ready && !stageSettleAnimation.running && !stagePeekFade.running
        onActiveChanged: {
            if (active) {
                var dx = centroid.scenePosition.x - centroid.scenePressPosition.x
                var dy = centroid.scenePosition.y - centroid.scenePressPosition.y
                root._swipeVx = 0
                root._swipeOriginX = centroid.scenePosition.x
                // Intención horizontal clara; si no, este gesto no mueve nada.
                root._swipeState = (vFlick.moving || Math.abs(dx) <= Math.abs(dy) * 1.2) ? -1 : 1
                return
            }
            var tracking = root._swipeState === 1
            root._swipeState = 0
            if (tracking) root._settleSwipe(root._swipeVx)
        }
        onCentroidChanged: {
            if (!active || root._swipeState !== 1) return
            root._swipeVx = centroid.velocity.x
            root._applySwipeOffset(centroid.scenePosition.x - root._swipeOriginX)
        }
    }
    property int selectedStratum: -1
    property string profileMode: "overview"
    property bool identityEditing: false
    property int activePhotoCategory: 1
    readonly property int visibleStrataCount: cortesModel.count

    function addStratumFromProfile() {
        if (!commitPendingField()) return
        var count = cortesModel.count
        addCorte()
        if (cortesModel.count > count) selectStratum(cortesModel.count - 1, "field")
    }

    // ===== Perfil: configuración a nivel de ficha =====
    // header.profile_setup viaja con la ficha (JSON local / InGeDrive). Aún no
    // tiene columnas cloud propias: la sincronización de la fila no lo usa.
    property var profileSetup: ({})
    function updateProfileSetup(changes, typing) {
        if (root._loading) return
        root.profileSetup = Object.assign({}, root.profileSetup || {}, changes || {})
        if (typing) root._markDirtySoon()
        else root._markDirty()
    }
    function profileSetupText(key) {
        var value = (root.profileSetup || {})[key]
        return value === undefined || value === null ? "" : String(value)
    }

    readonly property var prfOriginOptions: ["Natural", "Antrópico", "Mixto / intervenido"]
    readonly property var prfNaturalOrigins: ["Residual", "Coluvial", "Aluvial", "Fluvial", "Lacustre",
        "Marino / litoral", "Eólico", "Glaciar / fluvioglaciar", "Volcánico / piroclástico",
        "Orgánico / palustre", "Roca meteorizada", "Otro"]
    readonly property var prfFillTypes: ["Relleno no controlado", "Relleno controlado / compactado",
        "Relleno de demolición", "Relleno de préstamo", "Relleno sanitario / orgánico alterado",
        "Material de desecho / escombro", "Material de nivelación", "Subbase / base granular artificial", "Otro"]
    readonly property var prfFillContexts: ["Urbano", "Vial / carretera", "Cantera", "Edificación",
        "Infraestructura", "Botadero / depósito", "Ribera / defensa", "Otro"]
    readonly property var prfFillControls: ["Sin control", "Parcialmente controlado", "Controlado"]
    readonly property var prfCompactions: ["Suelta", "Media", "Densa", "Muy densa"]
    readonly property var prfFillMatrix: ["Arcilloso", "Limoso", "Arenoso", "Grava", "Grava-arena", "Mixto heterogéneo"]
    readonly property var prfFillComponents: ["Concreto", "Ladrillo", "Asfalto", "Plástico", "Vidrio",
        "Metal", "Madera", "Materia orgánica", "Desmonte", "Otros"]
    readonly property var prfStructures: ["Homogénea", "Heterogénea", "Estratificada", "Laminada",
        "Lenticular", "Fisurada", "Masiva", "Cementada"]
    readonly property var prfGranularDensity: ["Muy suelta", "Suelta", "Medianamente densa", "Densa", "Muy densa"]
    readonly property var prfCohesiveConsistency: ["Muy blanda", "Blanda", "Media", "Firme", "Muy firme", "Dura"]
    readonly property var prfFeatures: [
        { key: "odor", label: "Olor" }, { key: "organic", label: "Materia orgánica" },
        { key: "stains", label: "Manchas / contaminación" }, { key: "roots", label: "Presencia de raíces" },
        { key: "voids", label: "Vacíos" }, { key: "other", label: "Otros" }]
    readonly property var prfColors: [
        { name: "Marrón", hex: "#B97A56" }, { name: "Marrón claro", hex: "#D9B08C" },
        { name: "Marrón oscuro", hex: "#7A4E32" }, { name: "Beige", hex: "#E8D5B0" },
        { name: "Amarillento", hex: "#E6C86E" }, { name: "Rojizo", hex: "#C0674A" },
        { name: "Gris claro", hex: "#CFD2CE" }, { name: "Gris", hex: "#A7A9A6" },
        { name: "Gris oscuro", hex: "#6E716E" }, { name: "Verdoso", hex: "#9DB89A" },
        { name: "Negro", hex: "#3A3A38" }, { name: "Blanco / crema", hex: "#F2EEE3" }]
    readonly property var prfTemplates: [
        { key: "carretera", title: "Carretera", detail: "Subrasante, terraplenes y rellenos viales",
          method: "AASHTO", context: "Vial / carretera", aashtoFirst: true, featuresHint: false },
        { key: "edificacion", title: "Edificación", detail: "Cimentaciones y rellenos urbanos (E.050)",
          method: "SUCS", context: "Edificación", aashtoFirst: false, featuresHint: false },
        { key: "cantera", title: "Cantera", detail: "Potencia útil, desbroce y material de préstamo",
          method: "SUCS", context: "Cantera", aashtoFirst: false, featuresHint: false },
        { key: "ambiental", title: "Ambiental / exploración", detail: "Depósitos, contaminación y rellenos",
          method: "SUCS", context: "", aashtoFirst: false, featuresHint: true },
        { key: "vacia", title: "Plantilla vacía", detail: "Sin valores sugeridos", method: "", context: "",
          aashtoFirst: false, featuresHint: false }]
    // Plantilla activa: solo configura presentación (orden, método, contexto
    // explícito al elegir Antrópico). Nunca escribe observaciones de campo.
    readonly property var prfActiveTemplate: prfTemplate(profileSetupText("template"))
    readonly property var prfGeneralClasses: ["Perfil granular", "Perfil granular con limo",
        "Perfil granular con arcilla", "Perfil fino limoso", "Perfil fino arcilloso", "Perfil orgánico",
        "Perfil con relleno antrópico", "Perfil mixto / heterogéneo"]

    function prfTemplate(key) {
        for (var i = 0; i < prfTemplates.length; ++i)
            if (prfTemplates[i].key === key) return prfTemplates[i]
        return null
    }
    function prfTemplateTitle(key) {
        var t = prfTemplate(key)
        return t ? t.title : ""
    }

    // Selector de lista (optionPickerPopup) con índice 0 = sin valor.
    function prfPick(title, list, value, iconName, commit) {
        root._openOptionPicker(title, ["Sin seleccionar"].concat(list),
                               Math.max(0, list.indexOf(String(value || "")) + 1), iconName,
                               root.cGenBlue, root.cGenBlueSoft,
                               function(i) { commit(i > 0 ? list[i - 1] : "") })
    }

    // Origen visible <-> material_origin (el relleno conserva "Relleno antrópico"
    // para que Excel/PDF/perfil sigan reconociendo el código RA).
    function prfOriginLabel(materialOrigin) {
        var origin = String(materialOrigin || "").trim()
        if (!origin.length) return ""
        if (Rules.isAnthropicFill(origin)) return "Antrópico"
        if (/^mixto/i.test(origin)) return "Mixto / intervenido"
        return origin
    }
    function setStratumOrigin(index, label) {
        if (index < 0 || index >= cortesModel.count) return
        var value = label === "Antrópico" ? "Relleno antrópico" : label
        cortesModel.setProperty(index, "material_origin", value)
        if (label === "Antrópico" || label === "Mixto / intervenido") {
            var extra = JSON.parse(cortesModel.get(index)._extraJson || "{}")
            var template = prfTemplate(profileSetupText("template"))
            if (!String(extra.fill_context || "").length && template && template.context.length) {
                extra.fill_context = template.context
                cortesModel.setProperty(index, "_extraJson", JSON.stringify(extra))
            }
        }
        root._markDirty()
    }
    function setStratumExtra(index, key, value) {
        root.setLabEvidence(index, key, value)
    }
    function toggleStratumListValue(index, key, value) {
        if (index < 0 || index >= cortesModel.count) return
        var extra = JSON.parse(cortesModel.get(index)._extraJson || "{}")
        var list = Array.isArray(extra[key]) ? extra[key].slice() : []
        var at = list.indexOf(value)
        if (at >= 0) list.splice(at, 1); else list.push(value)
        root.setLabEvidence(index, key, list)
    }
    function toggleStratumFeature(index, key) {
        if (index < 0 || index >= cortesModel.count) return
        var extra = JSON.parse(cortesModel.get(index)._extraJson || "{}")
        var features = Object.assign({}, extra.features || {})
        features[key] = features[key] !== true
        root.setLabEvidence(index, "features", features)
    }

    // Color del estrato: elegido por el usuario o, si no hay, tono de su grupo.
    function prfColorHex(name) {
        for (var i = 0; i < prfColors.length; ++i)
            if (prfColors[i].name === name) return prfColors[i].hex
        return ""
    }
    function stratumColorFor(plain) {
        var chosen = prfColorHex(plain.stratum_color)
        if (chosen.length) return chosen
        if (Rules.isAnthropicFill(plain.material_origin)) return "#E7B98F"
        var code = String(Rules.labProjection(plain).primary || plain.sucs || "").toUpperCase()
        if (/^G/.test(code)) return "#E3D8C3"
        if (/^S/.test(code)) return "#F0D2B4"
        if (/^M/.test(code)) return "#C9D8C0"
        if (/^C/.test(code)) return "#C7CAD9"
        if (/^(O|PT)/.test(code)) return "#9C8B6E"
        return "#E7E7E4"
    }
    function prfInkOn(tone) {
        return tone.r * 0.299 + tone.g * 0.587 + tone.b * 0.114 < 0.55 ? "#FFFFFF" : "#111311"
    }
    // Patrón, SUCS y AASHTO del estrato = proyección del laboratorio (Web
    // resolveCalicataSucsPattern / formatSucsProjection). Solo lectura: se
    // cambian adoptando en Laboratorio. Una capa por código (compuesto = dos).
    function stratumPatternFilesFor(plain) {
        return Rules.labProjection(plain).pattern.layers.map(function(layer) { return layer.url })
    }
    // Vista del perfil: trama, color y rótulo de una banda en una sola lectura.
    function stratumBandInfo(index) {
        if (index < 0 || index >= cortesModel.count) return { files: [], color: "#E7E7E4", label: "" }
        var plain = corteToPlainObject(cortesModel.get(index))
        return { files: stratumPatternFilesFor(plain), color: stratumColorFor(plain),
                 label: Rules.labProjection(plain).sucs }
    }
    function stratumPatternLabel(plain) {
        return Rules.labProjection(plain).sucs
    }
    // Clasificación que muestra la tabla según el método del perfil (proyección
    // del laboratorio; vacío = pendiente de laboratorio).
    function stratumClassText(plain) {
        var projection = Rules.labProjection(plain)
        return profileSetupText("description_method") === "AASHTO" ? projection.aashto : projection.sucs
    }
    function stratumTypeText(plain) {
        var origin = prfOriginLabel(plain.material_origin)
        if (origin === "Antrópico" || origin === "Mixto / intervenido")
            return String(plain.fill_type || "")
        if (origin === "Natural") return String(plain.natural_origin || "")
        return ""
    }
    function stratumConsistencyOptions(plain) {
        var code = String(Rules.labProjection(plain).primary || plain.sucs || "").toUpperCase()
        if (/^[GS]/.test(code)) return prfGranularDensity
        if (/^(M|C|O|PT)/.test(code)) return prfCohesiveConsistency
        return prfGranularDensity.concat(prfCohesiveConsistency)
    }

    // Estrato seleccionado como objeto plano (se recalcula con cada cambio).
    readonly property var prfSel: {
        root._cortesRevision
        return selectedStratum >= 0 && selectedStratum < cortesModel.count
                ? corteToPlainObject(cortesModel.get(selectedStratum)) : null
    }

    function requestDeleteStratum(index) {
        if (index < 0 || index >= cortesModel.count) return
        vFlick.forceActiveFocus()
        if (cortesModel.count <= 1) {
            root.removeCorte(index)
        } else if (root.corteHasMeaningfulData(index)) {
            root._pendingDeleteIdx = index
            deleteConfirm.open()
        } else {
            root.removeCorte(index)
        }
    }

    // Añadir debajo del último estrato conserva los intervalos medidos.
    // El nuevo Hasta queda pendiente; nunca se inventa un espesor.
    function insertStratumBelow(index) {
        if (!commitPendingField() || index < 0 || index >= cortesModel.count) return
        if (index !== cortesModel.count - 1) {
            showInfo("Insertar estrato", "Selecciona el último estrato para añadir debajo sin cambiar los espesores registrados.")
            return
        }
        var before = cortesModel.count
        addCorte()
        if (cortesModel.count === before) return
        root._markDirty()
        selectStratum(cortesModel.count - 1, "field")
    }

    // Duplicar = nuevo estrato al final con la descripción de campo del origen
    // (sin intervalo, muestra ni laboratorio, que pertenecen a cada estrato).
    function duplicateStratum(index) {
        if (!commitPendingField() || index < 0 || index >= cortesModel.count) return
        var source = corteToPlainObject(cortesModel.get(index))
        var before = cortesModel.count
        addCorte()
        if (cortesModel.count <= before) return
        var target = cortesModel.count - 1
        var roles = ["material_origin", "descripcion", "humedad", "excavabilidad", "estabilidad", "aashto", "sucs"]
        for (var r = 0; r < roles.length; ++r) cortesModel.setProperty(target, roles[r], source[roles[r]])
        var extra = JSON.parse(cortesModel.get(target)._extraJson || "{}")
        var keys = ["natural_origin", "fill_type", "fill_context", "fill_control", "fill_compaction", "fill_matrix",
                    "fill_components", "fill_components_other", "structure", "consistency", "stratum_color",
                    "pattern_primary", "pattern_secondary", "pattern_anthropic", "features_enabled", "features", "features_other"]
        for (var k = 0; k < keys.length; ++k)
            if (source[keys[k]] !== undefined) extra[keys[k]] = source[keys[k]]
        cortesModel.setProperty(target, "_extraJson", JSON.stringify(extra))
        root._markDirty()
        selectStratum(target, "field")
    }

    property bool prfReorderMode: false

    function applyProfileTemplate(key, createFirstStratum) {
        var template = prfTemplate(key)
        if (!template) return
        var changes = { template: key }
        if (template.method.length) changes.description_method = template.method
        updateProfileSetup(changes)
        if (createFirstStratum === true && !cortesModel.count) addStratumFromProfile()
    }

    // Acciones del Perfil publicadas en el Dock (mismo wiring que la barra).
    function toggleProfileReorder() {
        if (cortesModel.count > 1) root.prfReorderMode = !root.prfReorderMode
    }
    function openProfileTemplates() { prfTemplatePopup.openPicker() }
    function openProfileGraph() {
        if (!cortesModel.count || !root.commitPendingField()) return
        prfGraphPopup.open()
    }
    // Punto único de entrada de las acciones de Perfil del Dock.
    function runProfileCommand(command) {
        if (command === "duplicate") root.duplicateStratum(root.selectedStratum)
        else if (command === "insert") root.insertStratumBelow(root.selectedStratum)
        else if (command === "reorder") root.toggleProfileReorder()
        else if (command === "templates") root.openProfileTemplates()
        else if (command === "graph") root.openProfileGraph()
    }

    // Selector por índice (enums de campo: -1 = sin valor).
    function prfPickIndex(title, list, currentIndex, iconName, commit) {
        root._openOptionPicker(title, ["Sin seleccionar"].concat(list),
                               Math.max(0, Number(currentIndex) + 1), iconName,
                               root.cGenBlue, root.cGenBlueSoft,
                               function(i) { commit(i - 1) })
    }

    function commitProfileDepth(text) {
        var depth = String(text || "").length ? Rules.parseDecimalSafe(text) : 0
        if (!isFinite(depth) || depth < 0) return false
        if (depth > 0 && depth < root.totalDepthM) {
            root.showInfo("Profundidad total", "No puede ser menor que los estratos registrados.")
            return false
        }
        root.requestedDepthM = depth
        root._markDirty()
        return true
    }

    // Nivel freático: vacío o igual al derivado = derivado (primer AGUA);
    // cualquier otro valor queda como Personalizado.
    function commitProfileGroundwater(text) {
        root._flushCortesRevision()
        var value = String(text || "").trim()
        var number = Rules.parseDecimalSafe(value)
        if (value.length && (!isFinite(number) || number < 0)) {
            root.showInfo("Nivel freático", "Ingresa una profundidad decimal mayor o igual que 0 m.")
            return false
        }
        var derived = Rules.parseDecimalSafe(root.derivedGroundwaterText)
        if (!value.length || (isFinite(derived) && Math.abs(derived - number) < 0.000001)) {
            root.groundwaterCustom = false
            txtWaterTableDepth.text = ""
        } else {
            root.groundwaterCustom = true
            txtWaterTableDepth.text = value
        }
        root._markDirty()
        return true
    }

    readonly property real prfWaterDepth: {
        var value = String(root.effectiveGroundwaterText || "").trim()
        return value.length ? Rules.parseDecimalSafe(value) : NaN
    }
    readonly property real prfGraphDepth: Rules.profileDepth(root.requestedDepthM, root.totalDepthM)

    // Resumen del perfil (espesores por grupo) a partir de los intervalos válidos.
    readonly property var prfStats: {
        root._cortesRevision
        var stats = { anthropicCount: 0, anthropicThickness: 0, total: 0,
                      coarse: 0, silt: 0, clay: 0, organic: 0, classified: 0 }
        for (var i = 0; i < cortesModel.count; ++i) {
            var row = cortesModel.get(i)
            var from = Rules.parseDecimalSafe(row.de), to = Rules.parseDecimalSafe(row.a)
            var thickness = isFinite(from) && isFinite(to) && to > from ? to - from : 0
            stats.total += thickness
            if (Rules.isAnthropicFill(row.material_origin)) {
                stats.anthropicCount++
                stats.anthropicThickness += thickness
                continue
            }
            var code = Rules.labProjection(root.corteToPlainObject(row)).primary
            if (!code.length) continue
            stats.classified += thickness
            if (/^[GS]/.test(code)) stats.coarse += thickness
            if (/^(O|PT)/.test(code)) stats.organic += thickness
            if (/(^|-)(M|GM|SM)/.test(code) || /^ML|^MH/.test(code)) stats.silt += thickness
            if (/(^|-)(C|GC|SC)/.test(code) || /^CL|^CH/.test(code)) stats.clay += thickness
        }
        return stats
    }

    function suggestedGeneralClass() {
        var s = root.prfStats
        if (s.total <= 0) return ""
        if (s.anthropicThickness / s.total >= 0.5) return "Perfil con relleno antrópico"
        if (s.classified <= 0) return ""
        if (s.organic / s.classified >= 0.4) return "Perfil orgánico"
        var coarseShare = s.coarse / s.classified
        if (coarseShare >= 0.7)
            return s.clay > s.silt ? "Perfil granular con arcilla"
                 : s.silt > 0 ? "Perfil granular con limo" : "Perfil granular"
        if (coarseShare <= 0.3) return s.clay > s.silt ? "Perfil fino arcilloso" : "Perfil fino limoso"
        return "Perfil mixto / heterogéneo"
    }

    function autoProfileInterpretation() {
        if (!cortesModel.count) return ""
        var s = root.prfStats
        var parts = []
        parts.push("Perfil de " + Math.max(root.totalDepthM, 0).toFixed(2) + " m con " + cortesModel.count
                   + (cortesModel.count === 1 ? " estrato." : " estratos."))
        if (s.anthropicCount > 0)
            parts.push("Relleno antrópico en " + s.anthropicThickness.toFixed(2) + " m de espesor.")
        var groups = [{ label: "material granular", value: s.coarse }, { label: "limos", value: s.silt },
                      { label: "arcillas", value: s.clay }, { label: "suelos orgánicos", value: s.organic }]
        groups.sort(function(x, y) { return y.value - x.value })
        if (groups[0].value > 0) parts.push("Predominio de " + groups[0].label + ".")
        parts.push(isFinite(root.prfWaterDepth) ? "Nivel freático a " + root.prfWaterDepth.toFixed(2) + " m."
                                                : "Sin nivel freático registrado.")
        return parts.join(" ")
    }

    function dismissInputForNavigation() {
        // Android consulta el InputConnection durante el cierre del IME.
        // Primero commit/hide y solo en el siguiente turno movemos el foco
        // fuera del editor; así no dejamos un TextInput inactivo bajo consulta.
        try { Qt.inputMethod.commit() } catch (commitError) {}
        try { Qt.inputMethod.hide() } catch (hideError) {}
        Qt.callLater(function() {
            if (root.visible && vFlick)
                vFlick.forceActiveFocus(Qt.OtherFocusReason)
        })
    }

    function finishReviewCorrection() {
        if (!reviewCorrectionActive) return false
        if (!commitPendingField()) return false
        flushRequested()
        reviewCorrectionActive = false
        reviewNotesEditing = false
        identityEditing = false
        profileMode = "overview"
        if (stratumSheet.opened) stratumSheet.close()
        scrollToSection(9)
        return true
    }

    function finishStratum(returnToReview) {
        var commitStarted = Date.now()
        console.info("INGE_CALICATA_PROFILE_COMMIT_BEGIN")
        if (!commitPendingField()) return false
        console.info("INGE_CALICATA_PROFILE_LOCAL_APPLIED elapsedMs=" + (Date.now() - commitStarted))
        // LOCAL FIRST: el Perfil se muestra ya; guardado local + cola cloud
        // ocurren en el siguiente frame (coalescidos si hay varios cambios).
        profileMode = "overview"
        stratumSheet.close()
        root._scheduleFlush(commitStarted)
        if (returnToReview === true && reviewCorrectionActive) {
            Qt.callLater(function() { root.finishReviewCorrection() })
        }
        return true
    }

    // Navegación interna explícita (swipe horizontal). Back Android no las usa. Cada llamada = una etapa.
    function goNextStage() {
        if (reviewCorrectionActive) return false
        if (stageIndex >= sectionNavigation.length - 1) return false
        scrollToSection(sectionNavigation[stageIndex + 1].n)
        return true
    }

    // Un solo flush diferido para cambios seguidos (Listo, cambio de etapa…).
    function _scheduleFlush(startedAt) {
        if (!deferredFlush.running) deferredFlush.startedAt = startedAt || Date.now()
        deferredFlush.restart()
    }
    Timer {
        id: deferredFlush
        property double startedAt: 0
        // Después de la transición de etapa (220 ms): el guardado síncrono a disco no
        // compite con los frames de la animación.
        interval: 260
        repeat: false
        onTriggered: {
            console.info("INGE_CALICATA_PROFILE_VISIBLE elapsedMs=" + (Date.now() - startedAt))
            root.flushRequested()
            console.info("INGE_CALICATA_PROFILE_SYNC_ENQUEUED elapsedMs=" + (Date.now() - startedAt))
        }
    }

    function goPreviousStage() {
        if (!commitPendingField()) return false
        if (reviewCorrectionActive)
            return finishReviewCorrection()
        if (stageIndex <= 0) return false
        root._scheduleFlush(Date.now())
        var previousStage = Math.max(0, stageIndex - 1)
        stageIndex = previousStage
        sectionNavCurrent = sectionNavigation[previousStage].n
        identityEditing = false
        reviewNotesEditing = false
        profileMode = "overview"
        dismissInputForNavigation()
        scrollToTop()
        return true
    }

    function handleBack() {
        // Back Android solo cierra superficies/modales temporales. No recorre
        // General/Ubicación/Perfil/Laboratorio/Fotos/Revisión.
        if (aiReviewDialog.opened) { aiReviewDialog.close(); return true }
        if (tsDlg.visible) {
            tsDlg.close()
            _releasePendingPhotoImport()
            return true
        }
        if (root.photoEditorItem && root.photoEditorItem.opened) {
            // Editor de fotos: Back cancela primero la herramienta activa (recorte, perspectiva, anotación).
            var photoEditor = root.photoEditorItem
            if (photoEditor.photoOperation && photoEditor.photoOperation.blocking && !photoEditor.photoOperation.result) return true
            if (photoEditor.mode.length) photoEditor.cancelTool(); else photoEditor.close()
            return true
        }
        if (photoActionsSheet.opened) { photoActionsSheet.close(); return true }
        if (photoViewer.opened) { photoViewer.close(); return true }
        if (popFechaPicker.opened) { popFechaPicker.close(); return true }
        if (machinePickerPopup.opened) { machinePickerPopup.close(); return true }
        if (optionPickerPopup.opened) { optionPickerPopup.close(); return true }
        if (deleteConfirm.opened) { deleteConfirm.close(); return true }
        if (stratumActionsPopup.opened) { stratumActionsPopup.close(); return true }
        if (prfTemplatePopup.opened) { prfTemplatePopup.close(); return true }
        if (prfGraphPopup.opened) { prfGraphPopup.close(); return true }
        if (infoDlg.opened) { infoDlg.close(); return true }
        if (projectPickerPopup.opened) { projectPickerPopup.close(); return true }
        if (identityPopup.opened) { identityPopup.close(); return true }
        if (root.labSheetActive && stratumSheet.visible) { root.closeLabDetail(); return true }
        if (stratumSheet.opened) { finishStratum(false); return true }
        if (!commitPendingField()) return true
        return false
    }

    function acceptMapPoint(latitude, longitude, altitude, accuracy, source) {
        if (!doc || doc.closed || !commitPendingField()) return false
        if (!isFinite(latitude) || !isFinite(longitude) || latitude < -80 || latitude > 84 || Math.abs(longitude) > 180) return false
        // latitude = Y, longitude = X; la precisión solo existe para lecturas GPS.
        // X/Y se confirman aquí; la Z se resuelve después con la elevación del
        // terreno (DEM) y solo de respaldo con la altura GPS del fix (elipsoidal).
        // Una Z manual nunca se reemplaza sin confirmación. Nunca se estima.
        var altitudeOk = isFinite(altitude) && altitude > -500 && altitude < 9000
        GpsBus.updateFromGeo(latitude, longitude, altitudeOk ? altitude : NaN, altitudeOk,
                             Qt.formatTime(new Date(), "hh:mm:ss"),
                             isFinite(accuracy) ? Number(accuracy) : NaN,
                             source ? String(source) : "Punto fijado en mapa")
        var applied = _applyCoordsFromGps(_docInstanceId(doc), 0)
        if (applied) flushRequested()
        return applied
    }
    property bool reviewNotesEditing: false
    readonly property var sectionNavigation: [
        { n: 1, label: "Datos generales", shortLabel: "General", icon: root.iconGeneralName },
        { n: 2, label: "Ubicación", shortLabel: "Ubicación", icon: root.iconLocationName },
        { n: 4, label: "Perfil estratigráfico", shortLabel: "Perfil", icon: root.iconStrataName },
        { n: 5, label: "Muestras / Laboratorio", shortLabel: "Laboratorio", icon: root.iconSamplesName },
        { n: 7, label: "Fotografías", shortLabel: "Fotos", icon: root.iconPhotosName },
        { n: 9, label: "Revisión final", shortLabel: "Revisión", icon: root.iconNotesName }
    ]
    property string persistenceStatus: ""
    property bool persistenceError: false
    signal requestExportExcel()
    // Calls the editor's existing map action; no map provider is created here.
    property var openMapAction: null
    property bool coordinatePickerOpen: false
    property bool reviewRequested: false
    property string reviewMessage: ""
    property bool reviewReady: false
    property var reviewIssues: []
    // Revisión de cierre: todo derivado de la misma instantánea (exportState) y del
    // mismo validador que exporta/aprueba (Rules.validateDocument vía doc).
    property var reviewSummaryData: ({ components: [], percent: 0, pendingCount: 0, blockerCount: 0, warningCount: 0, complete: false })
    property var reviewFactsData: ({ strata: 0, segments: [], finalDepth: 0 })
    property var reviewRecommendationsData: []
    property string reviewConclusionText: ""
    function _applyReview(state) {
        var issues = _exportIssues(state)
        var facts = Rules.reviewFacts(state)
        // Mismo color de estrato que Perfil (elegido o tono del grupo).
        var rows = state.cortes || []
        facts.segments = facts.segments.map(function(segment) {
            return Object.assign({}, segment, { color: String(root.stratumColorFor(rows[segment.index] || {})) })
        })
        reviewIssues = issues
        reviewSummaryData = Rules.reviewSummary(state, issues)
        reviewFactsData = facts
        reviewRecommendationsData = Rules.reviewRecommendations(state, facts)
        reviewConclusionText = Rules.reviewConclusion(reviewSummaryData, facts)
        reviewMessage = Rules.blockers(issues).length ? Rules.blockers(issues)[0].message : ""
        reviewReady = Rules.blockers(issues).length === 0
        reviewRequested = true
    }
    // Cuando una corrección nace desde Revisión, Listo/Guardar debe volver
    // directamente a la pantalla final sin obligar a recorrer las etapas.
    property bool reviewCorrectionActive: false
    readonly property int photoCount: (root._hasPhoto(1) ? 1 : 0)
                                     + (root._hasPhoto(2) ? 1 : 0)
                                     + (root._hasPhoto(3) ? 1 : 0)

    function sectionPosition(number) {
        if (number === 3) return 2
        if (number === 6) return 0
        if (number === 8) return 5
        for (var i = 0; i < sectionNavigation.length; ++i)
            if (sectionNavigation[i].n === number) return i
        return -1
    }

    function sectionVisible(number) {
        switch (number) {
        case 1: return stageIndex === 0 && !identityEditing
        case 6: return stageIndex === 0 && identityEditing
        case 2: return stageIndex === 1
        case 3: return stageIndex === 2 && profileMode === "depth"
        case 4: return stageIndex === 2
        case 5: return stageIndex === 3
        case 7: return stageIndex === 4
        case 8: return stageIndex === 5 && reviewNotesEditing
        }
        return false
    }

    function reviewForExport() {
        if (!commitPendingField()) return false
        root._scheduleFlush(Date.now())
        _applyReview(exportState())
        return true
    }

    function invalidateReview() {
        if (reviewRequested || reviewReady || reviewMessage.length || reviewIssues.length) {
            reviewRequested = false
            reviewReady = false
            reviewMessage = ""
            reviewIssues = []
        }
        if (stageIndex === 5) reviewRefresh.restart()
    }
    Timer {
        id: reviewRefresh
        interval: 120
        onTriggered: {
            if (root._loading || root.stageIndex !== 5) return
            root._applyReview(root.exportState())
        }
    }

    function openLabForStratum(index, originItem) {
        if (index < 0 || index >= cortesModel.count || !commitPendingField()) return
        // Shared-origin: la ventana nace desde la tarjeta tocada (sin tarjeta: centro + 24 dp).
        var origin = originItem && originItem.mapToItem ? originItem.mapToItem(null, originItem.width / 2, originItem.height / 2) : null
        labOriginValid = !!origin && isFinite(origin.x) && isFinite(origin.y)
        labOriginX = labOriginValid ? origin.x : 0
        labOriginY = labOriginValid ? origin.y : 0
        flushRequested()
        selectedStratum = index
        stageIndex = 3
        sectionNavCurrent = 5
        labTab = "lab"
        dismissInputForNavigation()
        profileMode = "samples"
        labSheetActive = true
        labDetailClosing = false
        labTabSwitch.stop(); labTabFade = 1; labTabShift = 0
        stratumSheet.open()
        scrollToTop()
    }

    function selectStratum(index, mode) {
        if (mode === "samples") {
            openLabForStratum(index)
            return
        }
        if (index < 0 || index >= cortesModel.count || !commitPendingField()) return
        flushRequested()
        var stageChanged = stageIndex !== 2
        selectedStratum = index
        stageIndex = 2
        labSheetActive = false
        profileMode = mode || "field"
        sectionNavCurrent = 4
        dismissInputForNavigation()
        // El editor del estrato vive dentro de la etapa Perfil (sin hoja modal).
        if (stratumSheet.opened) stratumSheet.close()
        if (stageChanged) scrollToTop()
        prfEditorScroll.restart()
    }

    // Lleva el editor del estrato a la vista solo si no está visible.
    Timer {
        id: prfEditorScroll
        interval: 60
        onTriggered: {
            if (typeof prfEditorCard === "undefined" || !prfEditorCard.visible || !vFlick) return
            var top = prfEditorCard.mapToItem(vFlick.contentItem, 0, 0).y
            var viewTop = vFlick.contentY, viewBottom = vFlick.contentY + vFlick.height
            if (top >= viewTop + root.dp(8) && top <= viewBottom - root.dp(160)) return
            vFlick.contentY = Math.max(0, Math.min(top - root.dp(12), vFlick.contentHeight - vFlick.height))
        }
    }

    function openReviewSection(sectionNumber) {
        reviewCorrectionActive = true
        scrollToSection(sectionNumber)
    }

    function openReviewIssue(issue) {
        reviewCorrectionActive = true
        if (issue.stratum >= 0) {
            if (issue.section === 5) openLabForStratum(issue.stratum)
            else selectStratum(issue.stratum, "field")
        } else {
            scrollToSection(issue.section)
        }
    }

    function scrollToSection(sectionNumber) {
        var position = sectionPosition(sectionNumber)
        if (position < 0 || !commitPendingField()) return
        if (stratumSheet.opened) stratumSheet.close()
        // El guardado (exportState + comparación + escritura a disco) ya no va dentro del
        // toque: se agrupa y corre DESPUÉS de la transición (los valores ya están
        // confirmados en el modelo por commitPendingField()).
        root._scheduleFlush(Date.now())
        dismissInputForNavigation()
        if (sectionNumber === 6) { identityPopup.open(); return }

        stageIndex = position
        sectionNavCurrent = sectionNavigation[position].n
        identityEditing = false
        reviewNotesEditing = sectionNumber === 8

        if (position === 2) {
            profileMode = sectionNumber === 3 ? "depth" : "overview"
            if (profileMode === "depth") stratumSheet.open()
        } else if (position === 3) {
            profileMode = "overview"
            if (selectedStratum < 0 && cortesModel.count)
                selectedStratum = 0
        }

        if (position === 5) reviewForExport()
        scrollToTop()
    }

    readonly property bool hasLogoMtc: (root.logoMtcSource && root.logoMtcSource.toString().length > 0)
    readonly property bool hasLogoProyecto: (root.logoProyectoSource && root.logoProyectoSource.toString().length > 0)

    // Header del corte (más mobile-friendly)
    readonly property int corteHdrH: root.dp(root.isPhone ? 50 : 54)
    readonly property int corteHdrBtn: root.dp(root.isPhone ? 48 : 52)
    readonly property int corteHdrFont: root.dp(root.isPhone ? 15 : 16)
    readonly property int corteHdrBtnGap: root.dp(10)



    // =========================================================
    // CORTES / GRANULOMETRÍA — escala visual (más “PC-like”)
    // =========================================================
    readonly property int cortesGap: root.dp(root.isPhone ? 8 : 10)
    readonly property int cortesPad: root.dp(root.isPhone ? 8 : 12)

    // Alturas (contenedores azules más grandes)
    readonly property int fsHdr: root.dp(root.isPhone ? 13 : 14)
    // Compacto Android: menos altura y menos sensación de formulario tosco.
    readonly property int hGrp: root.dp(root.isPhone ? 70 : 78)
    readonly property int hSub: root.dp(root.isPhone ? 62 : 70)
    readonly property int hCell: root.dp(root.isPhone ? 58 : 66)

    // Márgenes de texto (más separación a bordes dentro de contenedores)
    readonly property int hdrTxtMargin: root.dp(14)
    readonly property int hdrTxtMarginSm: root.dp(12)

    // Anchos (contenedores azules más grandes)
    readonly property int wDesc: root.dp(root.isPhone ? 260 : 310)

    // Verticales: contenedor más ancho + PNG más “pequeño” (más aire)
    readonly property int wVHum: root.dp(root.isPhone ? 104 : 118)
    readonly property int wVExc: root.dp(root.isPhone ? 112 : 126)
    readonly property int wVEst: root.dp(root.isPhone ? 104 : 118)


    readonly property int wTipo:  root.wStdCol
    readonly property int wDE: root.dp(root.isPhone ? 92 : 104)
    readonly property int wA: root.dp(root.isPhone ? 100 : 112)

    // Clasificaciones (AASHTO / SUCS) MÁS GRANDES
    readonly property int wClasi: root.dp(root.isPhone ? 110 : 126)

    // Ensayos laboratorio (un poquito más ancho para que todo “respire” igual)
    readonly property int wMax:   root.wStdCol
    readonly property int w2mm:   root.wStdCol
    readonly property int w04mm:  root.wStdCol
    readonly property int w008mm: root.wStdCol
    readonly property int wWL:    root.wStdCol
    readonly property int wLP:    root.wStdCol
    readonly property int wHum2: root.dp(root.isPhone ? 130 : 150)

    // ✅ 3 primeros PNG verticales MÁS pequeños + MÁS separación del borde
    readonly property int padHumImg: root.dp(root.isPhone ? 36 : 42)
    readonly property int padExcImg: root.dp(root.isPhone ? 40 : 46)
    readonly property int padEstImg: root.dp(root.isPhone ? 38 : 44)


    // --- AASHTO normal / SUCS más grande ---
    readonly property int wClasiAashto: root.wStdCol // deja AASHTO como está (usa tu valor actual)
    readonly property int wClasiSucs: root.dp(root.isPhone ? 130 : 150)


    // ✅ ancho estándar = igual al de SUCS
    readonly property int wStdCol: root.wClasiSucs



    // AASHTO/SUCS: contenedor más grande pero que el PNG también se vea grande
    readonly property int padClasiImg: root.dp(10)

    // padding de clasificaciones (buen aire sin “encoger” demasiado)
    readonly property int padClasiAashtoImg: root.dp(12)
    readonly property int padClasiSucsImg: root.dp(12)



    // === Tamaños (móvil) ===
    readonly property int fsLabel: Math.max(12, root.dp(root.isPhone ? 12 : 14))
    readonly property int fsField: Math.max(14, root.dp(root.isPhone ? 14 : 16))
    readonly property int hField: Math.max(44, root.dp(root.isPhone ? 44 : 50))
    // Objetivo tactil minimo de Android (48 dp), tambien con uiScale < 1.
    readonly property int hBtn: Math.max(48, root.dp(root.isPhone ? 46 : 52))
    readonly property int hBtnCompact: root.dp(root.isPhone ? 42 : 48)
    readonly property int fsBtn: root.dp(root.isPhone ? 13 : 15)
    readonly property int rField: root.dp(10)

    readonly property int labelW: root.dp(root.isPhone ? 92 : 118)
    readonly property int gapLF: root.dp(7)


    // ✅ NUEVO: columna de labels (para filas label+campo)
    readonly property int wLabel: root.dp(root.isPhone ? 92 : 112)

    // Compacto Android: logos menos altos y más fáciles de navegar.
    readonly property int hLogoBlock: root.dp(root.isPhone ? 78 : 96)
    readonly property int hLogoBtn: root.dp(root.isPhone ? 58 : 70)
    readonly property int hLogoClear: root.dp(root.isPhone ? 42 : 50)

    // === Protección para no “ensuciar” cuando cargamos datos ===
    on_LoadingChanged: { if (_loading) invalidateReview() }
    property bool _loading: false
    property bool _syncingDocument: false

    // === Ajuste táctil ARM/híbrido ===
    // Se deja activo también en Windows porque Qt Creator puede probar el target móvil con kit desktop.
    readonly property bool touchOptimized: true
    readonly property int touchPressDelay: 140
    readonly property int touchMinTarget: Math.max(48, root.dp(root.isPhone ? 48 : 54))
    readonly property real touchMaxVelocity: root.isPhone ? 1600 : 2200

    readonly property string dateFmt: "dd/MM/yyyy"

    readonly property var humItems: ["Seco", "Bajo", "Medio", "Agua"]
    readonly property var excItems: ["Rend. bajo", "Rend. medio", "Rend. alto", "Rend. muy alto"]
    readonly property var estItems: ["Baja", "Media", "Alta", "Muy Alta"]
    readonly property var sampleTypeItems: ["—", "MA", "MS", "MI", "MW", "Otro"]

    // ===== Profundidades (DE/A) =====
    readonly property real depthMaxM: Number.POSITIVE_INFINITY
    property real totalDepthM: 0.0
    property var strataGroundwaterDepth: null
    property real requestedDepthM: 0.0

    // ===== Identidad Web (P5) =====
    // `location` (Web "Lado de la vía"); may hold a historical free-text value.
    property string roadSideValue: ""
    readonly property string roadSideHistorical: roadSideValue.length
            && !Rules.catalogValue(roadSideValue, Rules.ROAD_SIDE_OPTIONS).length ? roadSideValue : ""
    readonly property var roadSideModel: ["-- Seleccione lado --"].concat(Rules.ROAD_SIDE_OPTIONS)
            .concat(roadSideHistorical.length ? [roadSideHistorical + " (histórico)"] : [])
    readonly property string machineHistorical: txtMaquina.text.trim().length
            && !Rules.catalogValue(txtMaquina.text, Rules.MACHINE_OPTIONS).length ? txtMaquina.text.trim() : ""
    readonly property var machineModel: ["-- Seleccione maquinaria --"].concat(Rules.MACHINE_OPTIONS)
            .concat(machineHistorical.length ? [machineHistorical + " (histórico)"] : [])

    function _catalogIndex(value, options, historical) {
        var canonical = Rules.catalogValue(value, options)
        if (canonical.length) return options.indexOf(canonical) + 1
        return historical.length ? options.length + 1 : 0
    }

    // Nivel freático: derivado del primer corte con humedad AGUA salvo que el
    // ingeniero marque Personalizado (txtWaterTableDepth guarda ese valor).
    property bool groundwaterCustom: false
    property int _cortesRevision: 0
    readonly property string derivedGroundwaterText: {
        root._cortesRevision
        return root._derivedGroundwater() || ""
    }
    readonly property string effectiveGroundwaterText: groundwaterCustom
            ? txtWaterTableDepth.text.trim() : derivedGroundwaterText
    readonly property string derivedDepthText: totalDepthM > 0 ? totalDepthM.toFixed(3) : ""

    function _derivedGroundwater() {
        var strata = []
        for (var i = 0; i < cortesModel.count; ++i) {
            var row = cortesModel.get(i)
            strata.push({ moistureCondition: Number(row.humedad) === 3 ? "AGUA" : "",
                          fromDepthM: String(row.de || "") })
        }
        return Rules.derivedGroundwaterDepth(strata)
    }

    // Revisión del modelo de estratos: de ella dependen labInfosAll (análisis de
    // laboratorio de TODOS los estratos), prfSel, prfStats, el nivel freático derivado y
    // la ficha de cada tarjeta. Una edición de celda (cada tecla de una descripción, cada
    // fila que toca deriveLabFields) ya no recalcula todo al instante: se agrupa en UNA
    // subida por vuelta del bucle de eventos. Los cambios estructurales siguen siendo
    // inmediatos y quien lee esos valores de forma síncrona llama antes a
    // _flushCortesRevision() (exportar, nivel freático, live, acciones de laboratorio).
    // Nunca desde una función evaluada en un binding: escribiría la revisión de la que
    // ese binding depende (binding loop de PrfCard.suggested).
    property bool _cortesRevisionPending: false
    function _flushCortesRevision() {
        if (!root._cortesRevisionPending) return
        root._cortesRevisionPending = false
        root._cortesRevision++
    }
    function _bumpCortesRevisionNow() {
        root._cortesRevisionPending = false
        root._cortesRevision++
    }
    Connections {
        target: cortesModel
        function onDataChanged() {
            if (root._cortesRevisionPending) return
            root._cortesRevisionPending = true
            Qt.callLater(root._flushCortesRevision)
        }
        function onRowsInserted() { root._bumpCortesRevisionNow() }
        function onRowsRemoved() { root._bumpCortesRevisionNow() }
        function onRowsMoved() { root._bumpCortesRevisionNow() }
        function onModelReset() { root._bumpCortesRevisionNow() }
    }
    readonly property real allowedDepthM: root.requestedDepthM > 0 ? root.requestedDepthM : root.depthMaxM
    readonly property var sucsPatternCodes: [
        "GW", "GP", "GM", "GC",
        "SW", "SP", "SM", "SC",
        "ML", "MH", "CL", "OL", "CH", "OH", "Pt"
    ]

    function _headerCode(header) {
        var h = header || {}
        return String(h.codigo || h.calicata || h.pk || h.progresiva || "").trim()
    }

    function _headerPk(header) {
        var h = header || {}
        if (h.codigo !== undefined && h.codigo !== null)
            return String(h.pk || h.progresiva || "").trim()
        if (String(h.calicata || "").trim().length)
            return String(h.progresiva || (h.pk !== h.calicata ? h.pk : "") || "").trim()
        return String(h.progresiva || h.pk || "").trim()
    }

    function _setCanonicalCalicataCode(value) {
        var t = String(value === undefined || value === null ? "" : value)

        if (txtCodigo.text !== t)
            txtCodigo.text = t

        var visibleCode = t.trim()
        root.titleSuggested(visibleCode.length ? visibleCode : "Calicata")

        root._markDirty()

        if (doc && doc.closed !== true) {
            var h = Object.assign({}, (doc.header || {}))
            h.codigo = t
            h.calicata = t
            // Alias que normalizeHeader prioriza sobre `calicata`: un valor viejo
            // aquí reemplazaría el código recién escrito al recargar.
            if (h.code !== undefined) h.code = t
            doc.header = h

            // Las fotos deben usar el mismo código visible del documento.
            var ts = Object.assign({}, (doc.timestamp || {}))
            ts.calicata = t
            doc.timestamp = ts
        }
    }

    // Progresiva (Web normalizeProgresiva). El editor llama siempre con
    // composeCode=false: código y progresiva son campos independientes
    // (C-AA-01 + 00+620 -> archivo C-AA-01.xlsx, nunca C-AA-01-00+620.xlsx).
    // El camino inverso (código -> progresiva) tampoco compone.
    function _setProgresiva(value, composeCode) {
        var t = Rules.normalizeProgresiva(value)
        if (txtPk.text !== t)
            txtPk.text = t

        root._markDirty()

        if (doc && doc.closed !== true) {
            var h = Object.assign({}, (doc.header || {}))
            h.pk = t
            h.progresiva = t
            h.depth_max_m = null // Sin tope; JSON solo almacena profundidades finitas.
            doc.header = h
        }

        if (composeCode && Rules.isValidProgresiva(t)) {
            var composed = Rules.composeCalicataCode(txtCodigo.text, t)
            if (composed !== txtCodigo.text.trim())
                root._setCanonicalCalicataCode(composed)
        }
    }

    function _enumIndex(value, labels) {
        var numeric = Number(value)
        if (value !== "" && value !== undefined && value !== null && isFinite(numeric) && numeric >= 0 && numeric < labels.length)
            return Math.floor(numeric)
        var wanted = String(value || "").trim().toLowerCase()
        for (var i = 0; i < labels.length; ++i) {
            if (String(labels[i]).toLowerCase() === wanted)
                return i
        }
        return -1
    }

    function _sampleTypeIndex(typeCode) {
        var wanted = String(typeCode || "").trim().toUpperCase()
        for (var i = 1; i <= 4; ++i) {
            if (root.sampleTypeItems[i] === wanted)
                return i
        }
        return wanted.length ? 5 : 0
    }

    function _inheritSampleInterval(index, previousDe, previousA) {
        var changes = Rules.inheritSampleInterval(cortesModel.get(index), previousDe, previousA)
        for (var key in changes) cortesModel.setProperty(index, key, changes[key])
    }

    function commitSampleInterval(index, key, text) {
        var row = cortesModel.get(index)
        var otherKey = key === "muestra_desde" ? "muestra_hasta" : "muestra_desde"
        var otherText = Rules.sampleIntervalValue(row, otherKey)
        var other = Rules.parseDecimalSafe(otherText)
        var number = Rules.parseDecimalSafe(text)
        var top = Rules.parseDecimalSafe(row.de), bottom = Rules.parseDecimalSafe(row.a)
        if (isFinite(number) && ((isFinite(top) && number < top) || (isFinite(bottom) && number > bottom))) {
            showInfo("Intervalo de muestra", "El intervalo debe estar dentro del estrato ("
                     + String(row.de || "—") + " – " + String(row.a || "—") + " m).")
            return false
        }
        if (isFinite(number) && isFinite(other)
                && (key === "muestra_desde" ? number >= other : number <= other)) {
            showInfo("Intervalo de muestra", "Desde debe ser menor que Hasta.")
            return false
        }
        cortesModel.setProperty(index, key, text)
        cortesModel.setProperty(index, otherKey, otherText)
        root._markDirty()
        return true
    }

    function commitLabPercentage(index, key, value) {
        var fields = JSON.parse(cortesModel.get(index)._percentageFieldsJson || "[]")
        if (fields.indexOf(key) < 0) fields.push(key)
        cortesModel.setProperty(index, "_percentageFieldsJson", JSON.stringify(fields))
        cortesModel.setProperty(index, key, value)
        root._markDirty()
        root.deriveLabFields()
        return true
    }

    function commitWebLabPercent(index, key, value) {
        if (index < 0 || index >= cortesModel.count) return false
        var row = cortesModel.get(index), extra = JSON.parse(row._extraJson || "{}")
        var snapshot = Object.assign({}, row, { passing_no4: extra.passing_no4 })
        var bounds = Rules.webLabBounds(snapshot, key)
        var normalized = Rules.webLabNormalizePercent(value, bounds)
        if (normalized === null) {
            showInfo("Ensayo de laboratorio", "Valor inválido. Debe respetar 0–100 % y la secuencia Máx. ≥ Nº4 ≥ Nº10 ≥ Nº40 ≥ Nº200.")
            return false
        }
        if (key === "passing_no4") root.setLabEvidence(index, key, normalized)
        else root.commitLabPercentage(index, key, normalized)
        root.deriveLabFields()
        return true
    }

    function setWebLabMeta(index, key, value) {
        if (key === "primary_sucs" || key === "secondary_sucs" || key === "is_composite") {
            root.setLabClassification(index, key, value)
            return
        }
        root.setLabEvidence(index, key, value)
        root.deriveLabFields()
    }

    // ===== Cortes (alturas) =====
    readonly property int corteMinH: 104      // altura mínima del “cuerpo” del corte
    readonly property int descMinH: 86        // alto mínimo visible de la descripción
    readonly property int descPad: 10         // padding interno descripción
    readonly property int corteHeaderH: 34    // barra azul “Corte N”

    // === Fotos (urls para preview) ===

    // Acciones (las conectas a tu lógica real)
    signal requestCapturePhoto(int idx) // tap en preview grande
    signal requestPickPhoto(int idx)    // botón Galería
    signal requestClearPhoto(int idx)   // botón Borrar
    signal requestGpsRefresh()
    signal requestOpenEarth(real latitude, real longitude, real altitude,
                            string label)
    signal documentMarkedDirty(var targetDoc)

    // === Icons (QRC) ===
    readonly property url icCamera: CalIcons.action("camera", root.darkMode)
    readonly property url icGeneral: CalIcons.icon("date", root.darkMode)
    readonly property url icLocation: CalIcons.icon("coordinates", root.darkMode)
    readonly property url icPhotos: CalIcons.action("addPhoto", root.darkMode)
    readonly property url icGallery: CalIcons.action("addPhoto", root.darkMode)

    readonly property string iconGeneralName: "profile.account"
    readonly property string iconLocationName: "map.marker"
    readonly property string iconExcavationName: "module.calicatas"
    readonly property string iconStrataName: "module.stratigraphy"
    readonly property string iconSamplesName: "lab.flask"
    readonly property string iconIdentityName: "profile.edit"
    readonly property string iconPhotosName: "documents.image"
    readonly property string iconNotesName: "action.edit"


    // === Pendientes (permiten editar aun si doc==null) ===
    property string _pendingExcelTitle: ""
    property string _pendingLogoMtcRel: ""
    property string _pendingLogoProRel: ""
    property bool _hasPendingExcelTitle: false
    property bool _hasPendingLogoMtc: false
    property bool _hasPendingLogoProyecto: false

    function _applyPendingToDocIfAny() {
        if (!doc || doc.closed === true) return

        if (_hasPendingExcelTitle) {
            var h = Object.assign({}, (doc.header || {}))
            h.project_full_name = (_pendingExcelTitle || "")
            doc.header = h
            _pendingExcelTitle = ""
            _hasPendingExcelTitle = false
        }

        if (_hasPendingLogoMtc || _hasPendingLogoProyecto) {
            var imgs = Object.assign({}, (doc.images || {}))
            if (_hasPendingLogoMtc) {
                imgs.logo_mtc_path = _pendingLogoMtcRel
                imgs.logo_mtc_custom = (_pendingLogoMtcRel || "").length > 0
                _pendingLogoMtcRel = ""
                _hasPendingLogoMtc = false
            }
            if (_hasPendingLogoProyecto) {
                imgs.logo_proyecto_path = _pendingLogoProRel
                imgs.logo_proyecto_custom = (_pendingLogoProRel || "").length > 0
                _pendingLogoProRel = ""
                _hasPendingLogoProyecto = false
            }
            doc.images = imgs
        }
    }

    function _applyPendingToUI() {
        var header = (doc && doc.closed !== true) ? (doc.header || {}) : {}
        var images = (doc && doc.closed !== true) ? (doc.images || {}) : {}
        var title = _hasPendingExcelTitle ? _pendingExcelTitle
                                          : (header.project_full_name || header.excel_title || "")
        var logoMtc = _hasPendingLogoMtc ? _pendingLogoMtcRel : (images.logo_mtc_path || "")
        var logoProyecto = _hasPendingLogoProyecto
                ? _pendingLogoProRel : (images.logo_proyecto_path || "")

        btnTituloCalicata.text = String(title).trim().length
                ? "Nombre del proyecto ✓" : "Nombre del proyecto"
        root.logoMtcSource = root._resolvedLogo(logoMtc, images.logo_mtc_removed, "mtc")
        root.logoProyectoSource = root._resolvedLogo(logoProyecto, images.logo_proyecto_removed, "pro")
    }


    function _readAuthString(propName) {
        if (!auth) return ""
        if (auth[propName] === undefined) return ""
        var v = (typeof auth[propName] === "function") ? auth[propName]() : auth[propName]
        return (v || "").toString().trim()
    }

    function ensureDocsRoots() {
        // base local de tu app (ya existe porque DocsOps lo usas en Documentos)
        var base = DocsOps.ingeBasePath()
        if (!base || !base.length) return

        var logged = !!(auth && auth.logged)
        var uid = _readAuthString("userId")
        if (!uid.length) uid = _readAuthString("uid")
        var dn  = _readAuthString("displayName")

        // Esto te arma Usuario_xxx y te deja resourcesPath listo
        docsCtl.applyUserRoot(logged, uid, dn, base)
    }

    function absToFileUrl(abs) {
        var p = (abs || "").toString().replace(/\\/g,"/")
        if (!p.length) return ""
        if (Qt.platform.os === "windows") return encodeURI("file:///" + p)
        if (p[0] === "/") return encodeURI("file://" + p)
        return encodeURI(p)
    }

    function logoAbsUrlFromRel(rel) {
        rel = (rel || "").toString().trim().replace(/\\/g,"/")
        if (!rel.length) return ""
        if (rel.startsWith("file://")
                || rel.startsWith("content://")
                || rel.startsWith("qrc:/"))
            return rel
        if (rel.startsWith("/") || /^[A-Za-z]:\//.test(rel))
            return absToFileUrl(rel)
        var base = (docsCtl.basePath || "").toString().replace(/\\/g,"/")
        if (!base.length) return ""
        return absToFileUrl(base + "/" + rel)
    }

    function _relativeToDocsBase(absOrUrl) {
        var base = _normPath(docsCtl.basePath || "").replace(/\/+$/, "")
        var full = _normPath(absOrUrl || "")
        if (!base.length || !full.length) return ""
        var prefix = base + "/"
        if (full.toLowerCase().indexOf(prefix.toLowerCase()) !== 0)
            return ""
        return full.substring(prefix.length).replace(/\\/g, "/")
    }

    function _resolvedLogo(path, removed, target) {
        if (removed === true) return ""
        return logoAbsUrlFromRel(path || (target === "mtc"
            ? "qrc:/images/ICONO_LOGO_MTC.jpeg" : "qrc:/images/INGEMA_LOGO_COMPLETO.png"))
    }

    function _storeLogoRelative(target, rel) {
        rel = String(rel || "").trim().replace(/\\/g, "/")
        if (target === "mtc")
            root.logoMtcSource = rel.length ? logoAbsUrlFromRel(rel) : ""
        else if (target === "pro")
            root.logoProyectoSource = rel.length ? logoAbsUrlFromRel(rel) : ""
        else
            return

        if (doc && doc.closed !== true) {
            var imgs = Object.assign({}, (doc.images || {}))
            if (rel.length)
                imgs[root._logoHistoryKey(target)] = root._logoHistoryWith(target, imgs, rel)
            if (target === "mtc") {
                imgs.logo_mtc_path = rel
                imgs.logo_mtc_custom = rel.length > 0
                imgs.logo_mtc_removed = rel.length === 0
                root._pendingLogoMtcRel = ""
                root._hasPendingLogoMtc = false
            } else {
                imgs.logo_proyecto_path = rel
                imgs.logo_proyecto_custom = rel.length > 0
                imgs.logo_proyecto_removed = rel.length === 0
                root._pendingLogoProRel = ""
                root._hasPendingLogoProyecto = false
            }
            doc.images = imgs
            if (typeof CalicataCloud !== "undefined")
                CalicataCloud.enqueueLogoSync(doc, target === "mtc" ? "ENTITY" : "PROJECT")
        } else if (target === "mtc") {
            root._pendingLogoMtcRel = rel
            root._hasPendingLogoMtc = true
        } else {
            root._pendingLogoProRel = rel
            root._hasPendingLogoProyecto = true
        }
        root._markDirty()
    }

    function _useDefaultLogo(target) {
        root._storeLogoRelative(target, target === "mtc"
                                ? "qrc:/images/ICONO_LOGO_MTC.jpeg"
                                : "qrc:/images/INGEMA_LOGO_COMPLETO.png")
        root.logoFeedbackText = target === "mtc"
                ? "Se usará el logo institucional predeterminado."
                : "Se usará el logo de proyecto predeterminado."
    }

    function _deleteLogo(target) {
        root._storeLogoRelative(target, "")
        root.logoFeedbackText = target === "mtc"
                ? "Logo MTC / entidad vacío. Las versiones anteriores se conservan."
                : "Logo del proyecto vacío. Las versiones anteriores se conservan."
    }

    // Logos de la ficha, igual que Web (CALICATA_LOGO_SLOTS):
    //   "pro" = PROJECT "Logo del proyecto"; "mtc" = ENTITY "Logo MTC / entidad".
    // Cada ranura guarda su historial local de versiones (más reciente
    // primero). Vaciar la ranura no borra el historial ni los archivos.
    function _logoHistoryKey(target) {
        return target === "mtc" ? "logo_mtc_history" : "logo_proyecto_history"
    }

    function _logoHistoryWith(target, imgs, rel) {
        var previous = root._logoHistoryFrom(target, imgs)
        var next = [{ path: rel, added_at: new Date().toISOString() }]
        for (var i = 0; i < previous.length && next.length < 20; ++i) {
            if (previous[i].path !== rel)
                next.push({ path: String(previous[i].path), added_at: String(previous[i].added_at || "") })
        }
        return next
    }

    function _logoHistoryFrom(target, imgs) {
        imgs = imgs || {}
        var stored = imgs[root._logoHistoryKey(target)]
        var list = []
        if (stored && stored.length !== undefined) {
            for (var i = 0; i < stored.length; ++i) {
                var p = String((stored[i] && stored[i].path) || "").trim()
                if (p.length) list.push({ path: p, added_at: String(stored[i].added_at || "") })
            }
        }
        // Ficha anterior al historial: el logo actual es la versión conocida.
        var current = String((target === "mtc" ? imgs.logo_mtc_path : imgs.logo_proyecto_path) || "").trim()
        var known = false
        for (var j = 0; j < list.length; ++j) if (list[j].path === current) known = true
        if (current.length && !known) list.unshift({ path: current, added_at: "" })
        return list
    }

    function logoHistory(target) {
        if (!doc || doc.closed === true) return []
        return root._logoHistoryFrom(target, doc.images || {})
    }

    function logoInUse(target, path) {
        if (!doc || doc.closed === true) return false
        var imgs = doc.images || {}
        var removed = target === "mtc" ? imgs.logo_mtc_removed : imgs.logo_proyecto_removed
        var current = String((target === "mtc" ? imgs.logo_mtc_path : imgs.logo_proyecto_path) || "").trim()
        return removed !== true && current === String(path || "")
    }

    function _restoreLogoVersion(target, path) {
        if (root._logoRequestPending || root.logoInUse(target, path)) return
        root._storeLogoRelative(target, path)
        root.logoFeedbackText = target === "mtc"
                ? "Logo MTC / entidad: versión anterior en uso."
                : "Logo del proyecto: versión anterior en uso."
    }

    function _logoPickerIndex(target) {
        return target === "mtc" ? 1 : target === "pro" ? 2 : -1
    }

    function _releasePendingLogoRequest() {
        root._logoRequestPending = false
        root._pendingLogoPickTarget = ""
        root._pendingLogoDocId = ""
    }

    function _beginLogoRequest(target) {
        if (root._logoRequestPending || root._photoRequestPending
                || root._documentClosing)
            return
        if (!doc || doc.closed === true) {
            root.showInfo("No se pudo adjuntar el logo",
                          "No hay una ficha abierta para asociar la imagen.")
            return
        }

        var pickerIndex = root._logoPickerIndex(target)
        if (pickerIndex < 0) return
        ensureDocsRoots()
        if (!docsCtl.resourcesPath || !String(docsCtl.resourcesPath).length) {
            root.showInfo("No se pudo adjuntar el logo",
                          "No se encontró la carpeta persistente Recursos.")
            return
        }

        root._logoRequestPending = true
        root._pendingLogoPickTarget = target
        root._pendingLogoDocId = root._docInstanceId(doc)
        root.logoFeedbackText = "Abriendo el selector de imágenes…"
        Perms.pickPhoto(pickerIndex)
    }

    function _persistPickedLogo(localUrl) {
        var target = root._pendingLogoPickTarget
        var targetDocId = root._pendingLogoDocId
        if (!root._logoRequestPending
                || !targetDocId.length
                || root._docInstanceId(root.doc) !== targetDocId
                || !doc
                || doc.closed === true) {
            Perms.releaseImportedPhoto(localUrl)
            root._releasePendingLogoRequest()
            return
        }

        ensureDocsRoots()
        var sourceAbs = root._fileUrlToAbs(localUrl)
        var copiedAbs = DocsOps.copyToDir(sourceAbs, docsCtl.resourcesPath)
        Perms.releaseImportedPhoto(localUrl)

        if (!copiedAbs || !String(copiedAbs).length) {
            var copyError = DocsOps.lastError || "No se pudo copiar la imagen."
            root._releasePendingLogoRequest()
            root.logoFeedbackText = ""
            root.showInfo("No se pudo guardar el logo", copyError)
            return
        }

        var rel = root._relativeToDocsBase(copiedAbs)
        if (!rel.length) {
            root._releasePendingLogoRequest()
            root.logoFeedbackText = ""
            root.showInfo("No se pudo guardar el logo",
                          "La imagen copiada quedó fuera de la carpeta persistente del usuario.")
            return
        }

        root._storeLogoRelative(target, rel)
        root.logoFeedbackText = "Logo incorporado y guardado en Recursos"
        root._releasePendingLogoRequest()
    }


    Connections {
        target: auth
        ignoreUnknownSignals: true
        function onLoggedChanged() { ensureDocsRoots() }
    }

    // ===== P1: fotografías avanzadas + Media Cloud =====
    readonly property var photoSlotTitles: ["Zona de ejecución", "Interior de calicata", "Acopios"]

    // ===== Fotos: estado real y acciones (una sola fuente: tarjeta, hoja y Dock) =====
    readonly property var photoCategoryIcons: ["map.location", "module.stratigraphy", "documents.folder"]
    property int photoSheetSlot: 1
    // Tarjetas de Fotos por categoría: origen visual del visor y del editor.
    property var _photoCardItems: ({})
    property int _photoEditorStartTab: 0
    // Editor cargado (Loader.item no está tipado): una sola referencia para abrir/Back.
    readonly property var photoEditorItem: photoEditorLoader.item
    function photoOriginPoint(idx) {
        var card = root._photoCardItems[idx]
        if (!card || !card.visible || !card.mapToItem || card.width <= 0) return null
        var p = card.mapToItem(null, card.width / 2, card.height / 2)
        return isFinite(p.x) && isFinite(p.y) ? p : null
    }
    // Coordenadas geográficas reales (WGS84) desde la UTM de la ficha; null si no hay datos válidos.
    // Raíz de Documentos del usuario: los logos de la ficha se guardan relativos a ella
    // (misma base que logoAbsUrlFromRel), y el render C++ la necesita para leerlos.
    function photoResourcesBase() {
        return String(docsCtl.basePath || "")
    }
    function photoGeoFromUtm(meta) {
        if (!meta) return null
        var datum = root.doc && root.doc.header ? String(root.doc.header.datum || "") : ""
        var g = Rules.utmToGeoForDatum(meta.easting, meta.northing, meta.zone, datum)
        return g && isFinite(g.latitude) && isFinite(g.longitude) ? g : null
    }
    function photoHasAction(idx, id) {
        var list = root.photoActions(idx)
        for (var i = 0; i < list.length; ++i) if (list[i].id === id && list[i].enabled !== false) return true
        return false
    }
    function photoSlotInfo(idx) {
        var has = root._hasPhoto(idx)
        var state = root._photoProcessing[idx] ? "PROCESSING" : root._photoSyncState(idx)
        var entry = root._photoMediaEntry(idx)
        var slot = root.doc && root.doc.closed !== true ? root.doc.photoSlot(idx) : ({})
        var versions = slot.versions || []
        var active = null
        for (var i = 0; i < versions.length; ++i)
            if (versions[i].local_version_id === slot.activeVersionId) active = versions[i]
        var hasOriginal = !!root.doc && root.doc.closed !== true && String(root.doc.originalPhotoUrl(idx)).length > 0
        // Versión anotada = derivado guardado distinto del original (Web: linkedPhoto.derivative).
        var hasAnnotated = hasOriginal && String(slot.derivedUrl || "").length > 0
                           && String(slot.derivedUrl) !== String(slot.originalUrl)
        var label = "", tone = "muted"
        if (state === "PROCESSING") { label = "Procesando…"; tone = "blue" }
        else if (state === "SYNCED") { label = "Sincronizada"; tone = "green" }
        else if (state === "SYNCING") { label = "Publicando…"; tone = "blue" }
        else if (state === "PENDING") { label = "Pendiente"; tone = "orange" }
        else if (state === "CONFLICT") { label = "Otra versión en la nube"; tone = "orange" }
        else if (state === "FAILED") { label = "Error de envío"; tone = "red" }
        else if (state === "CONFLICT_KEPT_REMOTE") { label = "Versión remota en uso"; tone = "blue" }
        else if (has) { label = "Cambios locales"; tone = "blue" }
        return {
            has: has, hasOriginal: hasOriginal, hasAnnotated: hasAnnotated, state: state, entry: entry, label: label, tone: tone,
            date: active && active.created_at ? String(active.created_at).replace("T", " ").substring(0, 16) : "",
            versionCount: versions.length,
            conflict: state === "CONFLICT" && !!entry,
            failed: state === "FAILED" && !!entry,
            error: entry && entry.error ? String(entry.error) : ""
        }
    }
    function photoToneColor(tone, soft) {
        var c = tone === "green" ? root.cGenGreen : tone === "orange" ? root.cGenOrange
              : tone === "red" ? (root.flow ? root.flow.theme.error : "#B4232E") : tone === "blue" ? root.cGenBlue : root.cMuted
        return soft ? Qt.rgba(c.r, c.g, c.b, root.darkMode ? 0.22 : 0.12) : c
    }
    function photoActions(idx) {
        var info = root.photoSlotInfo(idx), busy = root._photoRequestPending || !!root._photoProcessing[idx], list = []
        function add(id, label, icon, extra) {
            list.push(Object.assign({ id: id, label: label, icon: icon, enabled: true, destructive: false }, extra || {}))
        }
        if (info.conflict) {
            add("keepMine", "Conservar la mía", "action.check")
            add("keepRemote", "Mantener la remota", "status.sync")
        }
        if (info.failed) {
            add("retry", "Reintentar envío", "status.sync")
            add("discardSend", "Descartar envío", "action.close")
        }
        add("capture", info.has ? "Reemplazar con cámara" : "Tomar foto", "action.camera", { enabled: !busy })
        add("pick", info.has ? "Reemplazar desde galería" : "Importar de galería", "documents.upload", { enabled: !busy })
        if (info.has) add("view", "Ver foto", "action.search")
        if (info.hasOriginal) add("edit", "Editar y publicar", "action.edit", { enabled: !busy })
        if (info.hasOriginal) add("versions", "Versiones", "documents.folder", { enabled: !busy })
        // Web CalicataPhotos: descargar el original o la versión anotada ya guardada.
        if (info.hasOriginal) add("downloadOriginal", "Descargar original", "documents.download", { enabled: !busy })
        if (info.hasAnnotated) add("downloadAnnotated", "Descargar versión anotada", "documents.download", { enabled: !busy })
        if (info.has && (info.state === "" || info.state === "LOCAL" || (info.state === "PENDING" && !info.entry)))
            add("publish", "Publicar ahora", "documents.upload", { enabled: !busy })
        if (info.has) add("empty", "Dejar vacío", "action.delete", { destructive: true, enabled: !busy })
        return list
    }
    function runPhotoAction(id, idx) {
        if (idx < 1 || idx > 3 || !root.doc || root.doc.closed === true) return
        if (!root.photoHasAction(idx, id)) return
        root.activePhotoCategory = idx
        var info = root.photoSlotInfo(idx)
        if (id === "capture") root.requestCapturePhoto(idx)
        else if (id === "pick") root.requestPickPhoto(idx)
        else if (id === "view") { if (info.has) root.openPhotoViewer(idx) }
        else if (id === "edit") { if (info.hasOriginal) root.openPhotoEditor(idx, 0) }
        else if (id === "versions") { if (info.hasOriginal) root.openPhotoEditor(idx, 7) }
        else if (id === "downloadOriginal" || id === "downloadAnnotated") {
            var error = root.doc.savePhotoToGallery(idx, id === "downloadAnnotated")
            root.photoFeedbackText = error.length ? error
                : (id === "downloadAnnotated" ? "Versión anotada guardada en Imágenes/InGePlus. El original no cambia."
                                              : "Original guardado en Imágenes/InGePlus.")
        }
        else if (id === "publish") root._queuePhotoSync(root.doc, idx)
        else if (id === "empty") root._emptyPhotoSlot(idx)
        else if ((id === "keepMine" || id === "retry") && info.entry)
            CalicataCloud.resolveMediaConflict(info.entry.id, true)
        else if (id === "keepRemote" && info.entry) {
            CalicataCloud.resolveMediaConflict(info.entry.id, false)
            root.doc.setPhotoCloudState(idx, { sync: "CONFLICT_KEPT_REMOTE", pending_op: "" })
            root._reconcileMediaCloud()   // adopta la versión remota vigente (la local se conserva en versiones)
        } else if (id === "discardSend" && info.entry) {
            CalicataCloud.resolveMediaConflict(info.entry.id, false)
            root.doc.setPhotoCloudState(idx, { sync: "LOCAL", pending_op: "", sync_error: "" })
        }
    }
    function openPhotoActions(idx) {
        root.activePhotoCategory = idx
        root.photoSheetSlot = idx
        photoActionsSheet.open()
    }
    // Comandos del Dock (contexto Fotos): mismas acciones que tarjetas y hoja.
    function runPhotoCommand(command) {
        var c = String(command || "")
        if (c.indexOf("cat:") === 0) root.activePhotoCategory = Math.max(1, Math.min(3, Number(c.substring(4))))
        else if (c.indexOf("act:") === 0) root.runPhotoAction(c.substring(4), root.activePhotoCategory)
    }

    function _queuePhotoSync(targetDoc, idx) {
        if (!targetDoc || targetDoc.closed === true || typeof CalicataCloud === "undefined") return
        CalicataCloud.enqueuePhotoSync(targetDoc, idx)
    }

    function _photoSyncState(idx) {
        if (!doc || doc.closed === true) return ""
        var images = doc.images   // dependencia de binding
        return String(doc.photoSlot(idx).syncState || "")
    }

    function _photoMediaEntry(idx) {
        if (!doc || typeof CalicataCloud === "undefined") return null
        var count = CalicataCloud.pendingMediaCount   // dependencia de binding
        var entries = CalicataCloud.mediaEntriesFor(doc.instanceId)
        for (var i = entries.length - 1; i >= 0; --i)
            if (Number(entries[i].idx) === idx) return entries[i]
        return null
    }

    // tab: pestaña inicial del editor (0 Datos … 7 Versiones). Nace desde la tarjeta.
    function openPhotoEditor(idx, tab) {
        if (!doc || doc.closed === true) return
        root.activePhotoCategory = idx
        root._photoEditorStartTab = tab === undefined ? 0 : tab
        if (root.photoEditorItem)
            root.photoEditorItem.openFor(doc, idx, root.photoSlotTitles[idx - 1], root._photoEditorStartTab, root.photoOriginPoint(idx))
        else
            photoEditorLoader.active = true   // onLoaded abre el editor
    }
    function openPhotoViewer(idx) {
        root.activePhotoCategory = idx
        var p = root.photoOriginPoint(idx)
        var host = photoViewer.parent
        photoViewer.originDX = p && host ? p.x - host.width / 2 : 0
        photoViewer.originDY = p && host ? p.y - host.height / 2 : root.dp(24)
        photoViewer.open()
    }

    function _emptyPhotoSlot(idx) {
        if (!doc || doc.closed === true) return
        if (doc.emptyPhotoSlot(idx)) {
            root._queuePhotoSync(doc, idx)
            root.invalidateReview()
            root.photoFeedbackText = "Categoría vacía. La original y sus versiones se conservan."
        }
    }

    // Resultados confirmados mientras la ficha estaba cerrada o el proceso murió.
    function _reconcileMediaCloud() {
        if (!doc || doc.closed === true || typeof CalicataCloud === "undefined") return
        var confirmed = CalicataCloud.takeConfirmedMedia(doc.instanceId)
        for (var i = 0; i < confirmed.length; ++i) {
            var c = confirmed[i]
            var idx = Number(c.idx)
            if (idx >= 1 && idx <= 3) {
                var changes = Object.assign({}, c)
                delete changes.idx
                delete changes.category_code
                doc.setPhotoCloudState(idx, changes)
            }
        }
        CalicataCloud.bindMediaIdentity(doc)
        CalicataCloud.flushMedia()
        // Web -> Android: fotos y logos publicados en la nube sin copia local.
        CalicataCloud.joinPresence(doc)   // sin calicatas.id sale del canal
        if (String(doc.header.remoteCalicataId || "").length) {
            for (var slotIdx = 1; slotIdx <= 3; ++slotIdx)
                if (!String(doc.originalPhotoUrl(slotIdx)).length && root._photoSyncState(slotIdx) !== "PENDING")
                    CalicataCloud.downloadRemotePhoto(doc, slotIdx, "")
            ensureDocsRoots()
            if (docsCtl.resourcesPath && String(docsCtl.resourcesPath).length)
                CalicataCloud.loadRemoteLogos(doc, String(docsCtl.resourcesPath))
            root.activityRows = []
            CalicataCloud.loadActivity(doc, 0)
        }
    }

    property bool _assignedStratumIds: false
    // CalicatasEditorPage: beginOperation/phaseOperation/endOperation.
    property var operationHost: null
    // Suelta el input antes de salir de Calicatas (sin destruir nada aquí).
    function releaseInputForLeave() {
        var state = { touchActive: vFlick.dragging || vFlick.moving, flickActive: vFlick.flicking }
        vFlick.cancelFlick()
        vFlick.interactive = false
        return state
    }
    property string _projectOperationId: ""

    // P6: la línea de tiempo se recarga cuando la cola de actividad confirma
    // inserciones (foto, logo, estrato, estado…), sin reabrir la ficha.
    Timer {
        id: activityRefresh
        interval: 1200
        repeat: false
        onTriggered: if (root.doc && root.doc.closed !== true && typeof CalicataCloud !== "undefined")
                         CalicataCloud.loadActivity(root.doc, 0)
    }
    Connections {
        target: typeof CalicataCloud !== "undefined" ? CalicataCloud : null
        ignoreUnknownSignals: true
        function onPendingActivityChanged() { activityRefresh.restart() }
    }

    // ===== P6: PDF de la ficha =====
    // Misma ficha portable que el Excel. El archivo se nombra por el hash del
    // estado: repetir el tap sobre la misma ficha = mismo archivo y mismo job.
    // La publicación va a InGeDrive del proyecto por la cola persistente de
    // exportación (sobrevive offline, cierre y muerte del proceso).
    property bool _pdfExporting: false
    function exportPdfFlow() {
        var busyHost = root.operationHost
        if (root._pdfExporting || (busyHost && (busyHost._exportFlowActive || busyHost.foregroundBusy || busyHost.leaving))) {
            console.info("INGE_CALICATA_EXPORT_IGNORED_ALREADY_RUNNING format=PDF")
            return
        }
        if (!doc || doc.closed === true || typeof ExcelExporter === "undefined") return
        if (!root.commitPendingField()) return
        root.flushRequested()
        root._pdfExporting = true
        if (busyHost) busyHost._exportFlowActive = true
        var host = root.operationHost
        var opId = host ? host.beginOperation("EXPORT_PDF", "Exportando PDF…", "Generando la ficha…", { immediate: true }) : ""
        console.info("INGE_CALICATA_EXPORT_BEGIN format=PDF")
        pdfKickoff.opId = opId
        pdfKickoff.docId = root._docInstanceId(doc)
        pdfKickoff.restart()   // un frame para pintar el overlay antes de generar
    }
    Timer {
        id: pdfKickoff
        property string opId: ""
        property string docId: ""
        interval: 32
        repeat: false
        onTriggered: root._runPdfExport(opId, docId)
    }
    // Libera el flujo PDF pase lo que pase (éxito, error, excepción, cambio de ficha).
    function _releasePdfFlow() {
        root._pdfExporting = false
        if (root.operationHost) root.operationHost._exportFlowActive = false
    }
    function _runPdfExport(opId, docId) {
        var host = root.operationHost
        var path = "", state = null
        try {
            if (!doc || doc.closed === true || root._docInstanceId(doc) !== docId) {
                // La ficha cambió o se cerró antes de generar: se cancela sin archivo.
                console.warn("INGE_CALICATA_EXPORT_CANCELLED format=PDF reason=DOCUMENT_CHANGED")
                root._releasePdfFlow()
                if (host) host.endOperation(opId, "OK")
                return
            }
            ensureDocsRoots()
            var base = String(docsCtl.basePath || "")
            state = doc.portableState(base)
            path = String(ExcelExporter.exportCalicataToPdf(state, base) || "")
        } catch (pdfError) {
            console.warn("INGE_CALICATA_EXPORT_FAILED format=PDF " + pdfError)
            path = ""
        }
        root._releasePdfFlow()
        if (!path.length) {
            // El motivo real (qué foto o logo falta) llega al usuario.
            var reason = String(ExcelExporter.lastError || "")
            if (host) host.endOperation(opId, "ERROR", { title: "No se pudo crear el PDF",
                detail: (reason.length ? reason : "Error técnico al generar el archivo.") + "\nLa ficha se conserva.",
                actions: [{ id: "close", label: "Cerrar" }] })
            else root.showInfo("No se pudo generar el PDF", reason)
            return
        }
        var projectId = String(doc.header.projectId || "")
        var queued = projectId.length ? ExcelExporter.publishCalicataPdf(state, path) : false
        var fileName = path.replace(/\\/g, "/").split("/").pop()
        console.info("INGE_CALICATA_PDF_GENERATED localPhysicalPath=" + path + " remoteLogicalPath=Calicatas/PDF/" + fileName)
        if (queued) console.info("INGE_CALICATA_EXPORT_QUEUED")
        // Abrir automáticamente una sola vez (puente Android seguro, application/pdf).
        console.info("INGE_CALICATA_PDF_OPEN_REQUEST")
        var opened = ExcelExporter.openExportedFile(path, false)
        console.info(opened ? "INGE_CALICATA_PDF_OPEN_OK" : "INGE_CALICATA_PDF_OPEN_UNAVAILABLE")
        var detail = fileName + "\n\n" + (projectId.length
                ? "InGeDrive: " + String(doc.header.projectName || "Proyecto") + " › Calicatas › PDF › " + fileName
                  + "\nEstado: " + (queued ? "Pendiente de sincronización" : "Solo en el dispositivo")
                : "Selecciona un proyecto para publicarlo en InGeDrive.")
        if (!opened) detail += "\nNo hay un visor de PDF compatible; el archivo se conserva."
        if (host) host.endOperation(opId, "SUCCESS", { title: "PDF exportado", detail: detail, filePath: path,
                                                       actions: [{ id: "open", label: "Abrir" }, { id: "share", label: "Compartir" },
                                                                 { id: "close", label: "Cerrar" }] })
        else root.showInfo("PDF generado", detail)
    }

    // ===== P5: versiones cloud de logos (PROJECT / ENTITY) =====
    property var cloudLogoHistory: ({ PROJECT: [], ENTITY: [] })
    function restoreCloudLogo(target, entry) {
        if (!doc || !entry || typeof CalicataCloud === "undefined") return
        ensureDocsRoots()
        CalicataCloud.restoreRemoteLogo(doc, target === "mtc" ? "ENTITY" : "PROJECT",
                                        String(entry.original_storage_path || ""), String(docsCtl.resourcesPath || ""))
        root.logoFeedbackText = "Descargando la versión elegida…"
    }

    // ===== P6: actividad (activity_logs) =====
    property var activityRows: []
    property bool activityHasMore: false

    // P5: el logo en uso en la nube manda, salvo un envío local pendiente.
    function _adoptRemoteLogo(category, absPath) {
        if (!doc || doc.closed === true || !absPath.length) return
        var entries = CalicataCloud.mediaEntriesFor(doc.instanceId)
        for (var i = 0; i < entries.length; ++i)
            if (entries[i].category_code === category) return
        var rel = root._relativeToDocsBase(absPath)
        if (!rel.length) return
        var imgs = Object.assign({}, doc.images || {})
        var key = category === "ENTITY" ? "logo_mtc_path" : "logo_proyecto_path"
        if (imgs[key] === rel) return
        imgs[key] = rel
        imgs[category === "ENTITY" ? "logo_mtc_removed" : "logo_proyecto_removed"] = false
        imgs[root._logoHistoryKey(category === "ENTITY" ? "mtc" : "pro")] =
                root._logoHistoryWith(category === "ENTITY" ? "mtc" : "pro", imgs, rel)
        doc.images = imgs
        root._applyPendingToUI()
    }

    Connections {
        target: root
        function onDocChanged() {
            if (!root.doc && typeof CalicataCloud !== "undefined") CalicataCloud.leavePresence()
            root._reconcileMediaCloud()
        }
        // Presencia: EDITING mientras un campo tiene una edición en curso.
        function on_ActiveCommitFieldChanged() {
            if (typeof CalicataCloud !== "undefined") CalicataCloud.setPresenceField(root._presenceFieldLabel())
        }
    }
    Connections {
        target: root.Window.window
        ignoreUnknownSignals: true
        function onActiveFocusItemChanged() {
            if (typeof CalicataCloud !== "undefined") CalicataCloud.setPresenceField(root._presenceFieldLabel())
        }
    }
    Connections {
        target: Qt.application
        function onStateChanged() {
            if (typeof CalicataCloud !== "undefined")
                CalicataCloud.setPresenceActive(Qt.application.state === Qt.ApplicationActive)
        }
    }
    Component.onDestruction: if (typeof CalicataCloud !== "undefined") CalicataCloud.leavePresence()

    Connections {
        target: typeof CalicataCloud !== "undefined" ? CalicataCloud : null
        ignoreUnknownSignals: true
        function onRemoteLogoLoaded(localId, category, localPath, history) {
            if (!root.doc || localId !== root.doc.instanceId) return
            var next = Object.assign({}, root.cloudLogoHistory)
            next[category] = history || []
            root.cloudLogoHistory = next
            root._adoptRemoteLogo(category, localPath)
        }
        // Restaurar = volver a publicar esos bytes como logo nuevo (contrato Web).
        function onRemoteLogoRestored(localId, category, localPath, error) {
            if (!root.doc || localId !== root.doc.instanceId) return
            var rel = localPath.length ? root._relativeToDocsBase(localPath) : ""
            if (!rel.length) { root.logoFeedbackText = "No se pudo recuperar el logo: " + error; return }
            root._storeLogoRelative(category === "ENTITY" ? "mtc" : "pro", rel)
            root.logoFeedbackText = "Versión restaurada; se publicará como logo en uso."
            CalicataCloud.loadRemoteLogos(root.doc, String(docsCtl.resourcesPath || ""))
        }
        function onActivityLoaded(localId, rows, offset, hasMore) {
            if (!root.doc || localId !== root.doc.instanceId) return
            root.activityRows = offset > 0 ? root.activityRows.concat(rows) : rows
            root.activityHasMore = hasMore
        }
        function onMediaSyncChanged(localId, idx, state, message, changes) {
            if (!root.doc || root.doc.closed === true || localId !== root.doc.instanceId || idx < 1) return
            if (state === "REMOTE_EMPTY" || state === "REMOTE_FAILED") return
            if (state === "SYNCED") {
                CalicataCloud.takeConfirmedMedia(localId)   // aplicado aquí; no repetir al reabrir
                root.doc.setPhotoCloudState(idx, changes)
            } else {
                root.doc.setPhotoCloudState(idx, { sync: state, sync_error: message || "" })
            }
        }
        function onSyncSucceeded(localId, result) {
            if (!root.doc || localId !== root.doc.instanceId) return
            CalicataCloud.bindMediaIdentity(root.doc)
            // Fotos creadas antes de que la ficha tuviera identidad cloud.
            for (var idx = 1; idx <= 3; ++idx)
                if (root._photoSyncState(idx) === "PENDING" && !root._photoMediaEntry(idx))
                    root._queuePhotoSync(root.doc, idx)
        }
    }

    Loader {
        id: photoEditorLoader
        active: false
        source: active ? Qt.resolvedUrl("CalicataPhotoEditor.qml") : ""
        onLoaded: {
            var photoEditor = root.photoEditorItem
            photoEditor.form = root
            photoEditor.cloud = typeof CalicataCloud !== "undefined" ? CalicataCloud : null
            photoEditor.openFor(root.doc, root.activePhotoCategory, root.photoSlotTitles[root.activePhotoCategory - 1],
                                root._photoEditorStartTab, root.photoOriginPoint(root.activePhotoCategory))
        }
    }

    function _photoSource(idx) {
        if (!doc || doc.closed || idx < 1 || idx > 3) return ""
        var preview = root._photoLocalPreviews[idx]
        if (preview && preview.docId === root._docInstanceId(doc)) return preview.url
        // Read notify-backed properties so UI always observes the document model.
        var images = doc.images
        var fileUrl = doc.fileUrl
        return doc.cachedPhotoUrl(idx)
    }
    function _photoPreviewReady(idx, url) {
        var preview = root._photoLocalPreviews[idx]
        if (!preview || preview.ready || preview.docId !== root._docInstanceId(doc)
                || String(preview.url) !== String(url)) return
        preview.ready = true
        console.info("[InGe+ M09] LOCAL_PREVIEW_READY instanceId=" + preview.docId
                     + " idx=" + idx + " elapsedMs=" + (Date.now() - preview.acceptedMs))
    }
    function _hasPhoto(idx) {
        var s = _photoSource(idx)
        return !!(s && s.toString && s.toString().length > 0)
    }

    // === Observaciones (texto libre) ===
    property string observacionesText: ""

    // =========================================================
    // ComboBox estilo "TextField" (blanco, bordes teal, misma altura)
    // =========================================================
    component FieldComboBox: ComboBox {
        id: cb

        // Ajustables
        property int fieldHeight: Math.max(root.hField, cb.font.pixelSize + 24)
        property int fieldRadius: root.rField
        property bool centerText: false

        implicitHeight: fieldHeight
        height: fieldHeight

        font.pixelSize: root.fsField

        // Espacio para texto y flecha
        leftPadding: 12
        rightPadding: 34
        padding: 0

        background: CalicataLiquidGlass {
            dark: root.darkMode; accent: root.cGenBlue; danger: root.flow ? root.flow.theme.error : "#D9483B"
            radius: cb.fieldRadius
            pressed: cb.pressed
            focused: cb.activeFocus || (cb.popup && cb.popup.visible)
            enabledLook: cb.enabled
        }

        // Desplegable del mismo material (vidrio claro, filas translúcidas).
        delegate: ItemDelegate {
            id: cbOption
            required property int index
            width: ListView.view ? ListView.view.width : cb.width
            height: Math.max(root.dp(44), cbOptionText.implicitHeight + root.dp(16))
            highlighted: cb.highlightedIndex === cbOption.index
            padding: 0
            background: CalicataLiquidGlass {
                dark: root.darkMode; accent: root.cGenBlue; danger: root.flow ? root.flow.theme.error : "#D9483B"
                anchors.fill: parent
                anchors.margins: root.dp(2)
                radius: root.dp(10)
                tone: cb.currentIndex === cbOption.index ? "tinted" : "clear"
                pressed: cbOption.down || cbOption.highlighted
            }
            contentItem: Text {
                id: cbOptionText
                leftPadding: root.dp(12)
                rightPadding: root.dp(12)
                text: cb.textAt(cbOption.index)
                color: cb.currentIndex === cbOption.index ? root.cGenBlue : root.cText
                font.pixelSize: cb.font.pixelSize
                font.weight: cb.currentIndex === cbOption.index ? Font.DemiBold : Font.Normal
                elide: Text.ElideRight
                verticalAlignment: Text.AlignVCenter
            }
        }
        popup: Popup {
            y: cb.height + root.dp(4)
            width: cb.width
            implicitHeight: Math.min(cbList.contentHeight + topPadding + bottomPadding, root.dp(320))
            padding: root.dp(4)
            contentItem: ListView {
                id: cbList
                clip: true
                implicitHeight: contentHeight
                model: cb.popup.visible ? cb.delegateModel : null
                currentIndex: cb.highlightedIndex
                boundsBehavior: Flickable.StopAtBounds
                ScrollIndicator.vertical: ScrollIndicator {}
            }
            background: CalicataLiquidGlass {
                dark: root.darkMode; accent: root.cGenBlue; danger: root.flow ? root.flow.theme.error : "#D9483B"
                level: "sheet"
                radius: root.dp(14)
            }
            enter: Transition { NumberAnimation { property: "opacity"; from: 0; to: 1; duration: root.flow && root.flow.motionAllowed === false ? 0 : 140; easing.type: Easing.OutCubic } }
            exit: Transition { NumberAnimation { property: "opacity"; to: 0; duration: root.flow && root.flow.motionAllowed === false ? 0 : 120; easing.type: Easing.InCubic } }
        }

        // Texto del valor seleccionado
        contentItem: Item {
            anchors.fill: parent
            Text {
                anchors.fill: parent
                anchors.leftMargin: cb.leftPadding
                anchors.rightMargin: cb.rightPadding
                text: cb.displayText
                color: root.cText
                font.pixelSize: cb.font.pixelSize
                elide: Text.ElideRight
                verticalAlignment: Text.AlignVCenter
                horizontalAlignment: cb.centerText ? Text.AlignHCenter : Text.AlignLeft
            }
        }

        // Flecha simple (evita el indicador tipo “spin”)
        indicator: Components.FlowIcon {
            name: "system.up"
            flow: root.flow
            rotation: cb.popup && cb.popup.visible ? 0 : 180
            width: root.dp(18)
            height: root.dp(18)
            anchors.right: parent.right
            anchors.rightMargin: 12
            anchors.verticalCenter: parent.verticalCenter
            tintColor: root.cMuted
            activeTintColor: root.cAccent
            active: cb.popup && cb.popup.visible
            inactiveOpacity: 1.0
            Behavior on rotation {
                NumberAnimation {
                    duration: root.flow ? root.flow.fastDuration : 0
                    easing.type: root.flow ? root.flow.easeOut : Easing.OutCubic
                }
            }
        }
    }

    // ✅ ComboBox con binding seguro (modelo -> UI cuando NO está abierto)
    component BoundComboBox: FieldComboBox {
        id: bc
        property int modelIndex: 0
        property var onCommit: null   // function(idx)

        Binding {
            target: bc
            property: "currentIndex"
            value: bc.modelIndex
            when: (!bc.popup || !bc.popup.visible) && !root._loading
            restoreMode: Binding.RestoreNone
        }

        onActivated: function(idx) {
            if (bc.onCommit) bc.onCommit(idx)
            root._markDirty()
        }
    }

    // ✅ TextField con binding seguro (modelo -> UI cuando NO tiene foco)
    component BoundTextField: TextField {
        id: tf
        property string modelText: ""
        property var onCommit: null   // function(text)
        property bool numbersOnly: false
        property string numericKind: numbersOnly ? Rules.PERCENTAGE : Rules.FREE_TEXT
        property bool allowNP: false
        property real minimumValue: 0
        property real maximumValue: numericKind === Rules.PERCENTAGE ? 100 : Number.POSITIVE_INFINITY
        property bool editPending: false
        property string validationError: ""
        // function(previousText, nextText) -> accepted text (máscara en vivo).
        property var inputFilter: null
        property string _filterPrevious: ""
        property bool editorial: root.stageIndex === 0 && !identityPopup.opened
        property int fieldRadius: 10
        implicitHeight: Math.max(root.hField, contentHeight + topPadding + bottomPadding) + (validationError.length ? fieldError.implicitHeight + 6 : 0)
        bottomPadding: validationError.length ? fieldError.implicitHeight + 12 : 8

        font.pixelSize: root.fsField
        leftPadding: 10; rightPadding: 10
        inputMethodHints: numericKind !== Rules.FREE_TEXT && !allowNP
                          ? Qt.ImhFormattedNumbersOnly : Qt.ImhNone

        Binding {
            target: tf
            property: "text"
            value: tf.modelText
            when: !tf.editPending && !root._loading
            restoreMode: Binding.RestoreNone
        }

        onActiveFocusChanged: if (activeFocus) _filterPrevious = text
        onTextEdited: {
            if (root._loading) return
            root.invalidateReview()
            editPending = true
            validationError = ""
            if (tf.inputFilter) {
                var accepted = tf.inputFilter(tf._filterPrevious, text)
                if (accepted !== text) {
                    text = accepted
                    cursorPosition = text.length
                }
                tf._filterPrevious = text
            }
            if (root._pendingCommitFields.indexOf(tf) < 0)
                root._pendingCommitFields = root._pendingCommitFields.concat([tf])
            root._activeCommitField = tf
        }
        function commitPending() {
            if (!editPending || root._loading) return true
            var normalized = Rules.normalizeDecimalText(text, numericKind, allowNP)
            if (isNaN(minimumValue) || isNaN(maximumValue)) {
                validationError = "Completa primero Desde y Hasta del estrato."
                forceActiveFocus()
                return false
            }
            if (normalized === null || (normalized !== "" && normalized !== "NP"
                    && numericKind !== Rules.FREE_TEXT && numericKind !== Rules.CHAINAGE_PK
                    && !Rules.validateDecimalRange(normalized, minimumValue, maximumValue))) {
                validationError = (placeholderText || "Valor")
                    + (isFinite(maximumValue) ? ": valor entre " + minimumValue + " y " + maximumValue + "." : ": ingresa un decimal válido.")
                forceActiveFocus()
                return false
            }
            root.setDirty(true)
            if (tf.onCommit && tf.onCommit(normalized) === false) return false
            validationError = ""
            text = normalized
            editPending = false
            root._pendingCommitFields = root._pendingCommitFields.filter(function(field) { return field !== tf })
            if (root._activeCommitField === tf) root._activeCommitField = null
            root._markDirty()
            return true
        }
        onEnabledChanged: {
            if (enabled || !editPending) return
            // A disabled NP-only field cannot keep blocking the form with a stale edit.
            editPending = false
            validationError = ""
            root._pendingCommitFields = root._pendingCommitFields.filter(function(field) { return field !== tf })
            if (root._activeCommitField === tf) root._activeCommitField = null
        }
        onEditingFinished: commitPending()
        Component.onDestruction: {
            root._pendingCommitFields = root._pendingCommitFields.filter(function(field) { return field !== tf })
            if (root._activeCommitField === tf) root._activeCommitField = null
        }

        Text {
            id: fieldError
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.margins: 5
            visible: tf.validationError.length > 0
            text: tf.validationError
            color: root.flow ? root.flow.theme.error : "#B4232E"
            font.pixelSize: root.fsLabel
            wrapMode: Text.WordWrap
        }
        background: CalicataLiquidGlass {
            dark: root.darkMode; accent: root.cGenBlue; danger: root.flow ? root.flow.theme.error : "#D9483B"
            radius: tf.fieldRadius
            focused: tf.activeFocus
            error: tf.validationError.length > 0
            enabledLook: tf.enabled
        }
        color: root.cText
        placeholderTextColor: root.cMuted
    }

    // TextArea enlazado al mismo modelo oculto usado por la serialización.
    // Pensado para el nombre contractual: multilínea, editable y sin overflow.
    component BoundTextArea: TextArea {
        id: ta
        property string modelText: ""
        property var onCommit: null   // function(text)
        property bool editorial: root.stageIndex === 0 && !identityPopup.opened
        property int fieldRadius: 10

        font.pixelSize: root.fsField
        leftPadding: root.dp(10)
        rightPadding: root.dp(10)
        topPadding: root.dp(8)
        bottomPadding: root.dp(8)
        wrapMode: TextEdit.Wrap
        selectByMouse: true
        clip: true

        Binding {
            target: ta
            property: "text"
            value: ta.modelText
            when: !ta.activeFocus && !root._loading
            restoreMode: Binding.RestoreNone
        }

        onTextChanged: {
            if (root._loading || !ta.activeFocus) return
            if (ta.onCommit) ta.onCommit(ta.text)
        }

        background: CalicataLiquidGlass {
            dark: root.darkMode; accent: root.cGenBlue; danger: root.flow ? root.flow.theme.error : "#D9483B"
            radius: ta.fieldRadius
            focused: ta.activeFocus
            enabledLook: ta.enabled
        }
        color: root.cText
        placeholderTextColor: root.cMuted
    }

    // A stage body has no collapsed state. Its controls stay instantiated so
    // changing context never discards a pending field or a document binding.
    component MobileStageBody: Rectangle {
        id: sectionCard
        property int sectionNumber: 0
        property string sectionTitle: ""
        property string sectionSubtitle: ""
        // Superficie primaria única de la etapa (como "Información de la calicata"):
        // los campos, selectores y acciones de dentro son controles anidados del
        // mismo material. Las etapas que componen sus propias tarjetas primarias
        // (Fotos, Perfil, Laboratorio) la desactivan para no apilar vidrio.
        property bool glassPanel: true
        readonly property real panelPadding: sectionCard.glassPanel ? root.dp(14) : 0
        default property alias sectionContent: sectionBody.data
        visible: root.sectionVisible(sectionNumber)
        width: parent ? parent.width : 0
        implicitHeight: sectionLayout.implicitHeight + root.dp(12) + 2 * sectionCard.panelPadding
        height: implicitHeight
        radius: root.dp(24)
        color: "transparent"
        CalicataLiquidGlass {
            visible: sectionCard.glassPanel
            anchors.fill: parent
            dark: root.darkMode
            accent: root.cGenBlue
            radius: sectionCard.radius
            level: "card"
        }
        ColumnLayout {
            id: sectionLayout
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: sectionCard.panelPadding
            spacing: root.dp(12)
            Text {
                visible: false
                Layout.fillWidth: true
                text: sectionCard.sectionTitle
                color: root.cText
                font.bold: true
                font.pixelSize: root.sp(18)
                wrapMode: Text.WordWrap
            }
            Text {
                Layout.fillWidth: true
                visible: false
                text: sectionCard.sectionSubtitle
                color: root.cMuted
                font.pixelSize: root.fsLabel
                wrapMode: Text.WordWrap
            }
            ColumnLayout {
                id: sectionBody
                Layout.fillWidth: true
                spacing: root.dp(12)
            }
        }
    }

    component StageButton: Button {
        id: stageButton
        property bool primary: false
        implicitHeight: root.hBtn
        Layout.preferredHeight: implicitHeight
        padding: root.dp(12)
        font.pixelSize: root.fsField
        background: CalicataLiquidGlass {
            dark: root.darkMode; accent: root.cGenBlue; danger: root.flow ? root.flow.theme.error : "#D9483B"
            radius: root.rField
            tone: stageButton.primary ? "primary" : "glass"
            pressed: stageButton.down
            enabledLook: stageButton.enabled
        }
        contentItem: Text {
            text: stageButton.text
            color: stageButton.primary ? (root.darkMode ? root.brand.ingemaDeep : "#FFFFFF") : root.cText
            font: stageButton.font
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            wrapMode: Text.WordWrap
        }
    }

    component MobileStatusChip: Rectangle {
        id: statusChip
        property string label: ""
        implicitWidth: statusLabel.implicitWidth + root.dp(18)
        implicitHeight: Math.max(28, statusLabel.implicitHeight + root.dp(10))
        radius: height / 2
        color: "transparent"
        CalicataLiquidGlass { dark: root.darkMode; accent: root.cGenBlue; danger: root.flow ? root.flow.theme.error : "#D9483B"; anchors.fill: parent; radius: statusChip.radius; tone: "tinted" }
        Text {
            id: statusLabel
            anchors.centerIn: parent
            text: statusChip.label
            color: root.cMuted
            font.pixelSize: root.fsLabel
        }
    }

    // Historial de versiones de una ranura de logo, colapsado por defecto.
    // Filas de _logoVersionRows (nube y local, más reciente primero); la
    // versión en uso muestra "En uso", el resto la acción "Usar" real.
    component LogoHistoryStrip: ColumnLayout {
        id: logoHistoryStrip
        property string target: ""
        property bool expanded: false
        readonly property var rows: root._logoVersionRows(target)
        readonly property int rowHeight: root.dp(56)
        spacing: root.dp(6)
        visible: rows.length > 0

        Button {
            id: logoHistoryToggle
            Layout.fillWidth: true
            Layout.preferredHeight: root.dp(44)
            padding: root.dp(10)
            focusPolicy: Qt.NoFocus
            Accessible.name: "Cambios recientes, " + logoHistoryStrip.rows.length + " versiones"
            onClicked: logoHistoryStrip.expanded = !logoHistoryStrip.expanded
            background: CalicataLiquidGlass { dark: root.darkMode; accent: root.cGenBlue; danger: root.flow ? root.flow.theme.error : "#D9483B"; radius: root.dp(12); pressed: logoHistoryToggle.down }
            contentItem: RowLayout {
                spacing: root.dp(10)
                Components.FlowIcon {
                    Layout.preferredWidth: root.dp(18)
                    Layout.preferredHeight: root.dp(18)
                    name: "calgen.history"
                    flow: root.flow
                    tintColor: root.cGenBlue
                    activeTintColor: root.cGenBlue
                    inactiveOpacity: 1
                }
                Text {
                    Layout.fillWidth: true
                    text: "Cambios recientes"
                    color: root.cText
                    font.pixelSize: root.fsLabel
                    font.weight: Font.DemiBold
                    elide: Text.ElideRight
                }
                Text {
                    text: logoHistoryStrip.rows.length
                    color: root.cMuted
                    font.pixelSize: root.fsLabel
                    font.weight: Font.DemiBold
                }
                Components.FlowIcon {
                    Layout.preferredWidth: root.dp(16)
                    Layout.preferredHeight: root.dp(16)
                    name: "calgen.chevron"
                    flow: root.flow
                    tintColor: root.cMuted
                    activeTintColor: root.cMuted
                    inactiveOpacity: 1
                    rotation: logoHistoryStrip.expanded ? 90 : 0
                    Behavior on rotation { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
                }
            }
        }

        // Máximo 4 filas visibles; más versiones desplazan dentro de la lista.
        ListView {
            Layout.fillWidth: true
            Layout.preferredHeight: Math.min(count, 4) * logoHistoryStrip.rowHeight
            visible: opacity > 0
            opacity: logoHistoryStrip.expanded ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
            clip: true
            interactive: count > 4
            boundsBehavior: Flickable.StopAtBounds
            model: logoHistoryStrip.expanded ? logoHistoryStrip.rows : []
            delegate: Item {
                id: logoVersionRow
                required property var modelData
                width: ListView.view.width
                height: logoHistoryStrip.rowHeight

                Rectangle {
                    id: logoVersionThumb
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    width: root.dp(44)
                    height: root.dp(44)
                    radius: root.dp(10)
                    color: "transparent"
                    CalicataLiquidGlass { dark: root.darkMode; accent: root.cGenBlue; danger: root.flow ? root.flow.theme.error : "#D9483B"; anchors.fill: parent; radius: parent.radius; selected: logoVersionRow.modelData.inUse }
                    Image {
                        anchors.fill: parent
                        anchors.margins: root.dp(5)
                        visible: logoVersionRow.modelData.thumb.length > 0
                        source: logoVersionRow.modelData.thumb
                        sourceSize.width: 96
                        sourceSize.height: 96
                        fillMode: Image.PreserveAspectFit
                        asynchronous: true
                        cache: false
                    }
                    Components.FlowIcon {
                        anchors.centerIn: parent
                        visible: logoVersionRow.modelData.thumb.length === 0
                        width: root.dp(20)
                        height: root.dp(20)
                        name: "calgen.identity"
                        flow: root.flow
                        tintColor: root.cMuted
                        activeTintColor: root.cMuted
                        inactiveOpacity: 1
                    }
                }
                Column {
                    anchors.left: logoVersionThumb.right
                    anchors.leftMargin: root.dp(10)
                    anchors.right: logoVersionAction.left
                    anchors.rightMargin: root.dp(8)
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: root.dp(1)
                    Text {
                        width: parent.width
                        text: logoVersionRow.modelData.name
                        color: root.cText
                        font.pixelSize: root.fsLabel
                        font.weight: Font.DemiBold
                        elide: Text.ElideRight
                    }
                    Text {
                        width: parent.width
                        text: logoVersionRow.modelData.detail
                        color: logoVersionRow.modelData.inUse ? root.cGenBlue : root.cMuted
                        font.pixelSize: root.sp(11)
                        elide: Text.ElideRight
                    }
                }
                Item {
                    id: logoVersionAction
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    width: root.dp(72)
                    height: root.dp(32)
                    Rectangle {
                        anchors.fill: parent
                        visible: logoVersionRow.modelData.inUse
                        radius: height / 2
                        color: root.cGenGreenSoft
                        Text {
                            anchors.centerIn: parent
                            text: "En uso"
                            color: root.cGenGreen
                            font.pixelSize: root.sp(11)
                            font.weight: Font.DemiBold
                        }
                    }
                    GenDialogButton {
                        anchors.fill: parent
                        visible: !logoVersionRow.modelData.inUse
                        soft: true
                        text: "Usar"
                        font.pixelSize: root.fsLabel
                        enabled: logoVersionRow.modelData.cloud || !root._logoRequestPending
                        onClicked: {
                            if (logoVersionRow.modelData.cloud)
                                root.restoreCloudLogo(logoHistoryStrip.target, logoVersionRow.modelData.entry)
                            else
                                root._restoreLogoVersion(logoHistoryStrip.target, logoVersionRow.modelData.path)
                        }
                    }
                }
                Rectangle {
                    anchors.bottom: parent.bottom
                    anchors.left: logoVersionThumb.right
                    anchors.leftMargin: root.dp(10)
                    anchors.right: parent.right
                    height: 1
                    color: root.cBorder
                    opacity: 0.6
                }
            }
        }
    }

    // Filas presentables del historial de una ranura: primero las versiones de
    // la nube (la primera no retirada es la en uso), luego las locales, cada
    // modelo ya en orden más reciente primero. Solo presentación; las acciones
    // siguen siendo restoreCloudLogo / _restoreLogoVersion.
    function _logoVersionRows(target) {
        var rows = []
        var cloud = root.cloudLogoHistory[target === "mtc" ? "ENTITY" : "PROJECT"] || []
        for (var i = 0; i < cloud.length; ++i) {
            var c = cloud[i]
            var cloudInUse = !c.discarded_at && i === 0
            rows.push({ cloud: true, entry: c, path: "", thumb: "", inUse: cloudInUse,
                        name: root._logoVersionName(c.original_file_name),
                        detail: root._logoVersionDate(c.updated_at)
                                + (cloudInUse ? "Nube · en uso" : c.discarded_at ? "Nube · retirado" : "Nube") })
        }
        var local = root.logoHistory(target)
        for (var j = 0; j < local.length; ++j) {
            var path = String(local[j].path)
            var localInUse = root.logoInUse(target, path)
            rows.push({ cloud: false, entry: null, path: path, inUse: localInUse,
                        thumb: String(root.logoAbsUrlFromRel(path) || ""),
                        name: root._logoVersionName(path.split("/").pop()),
                        detail: root._logoVersionDate(local[j].added_at)
                                + (localInUse ? "Local · en uso" : "Local") })
        }
        return rows
    }

    function _logoVersionName(fileName) {
        var name = String(fileName || "").replace(/\.[A-Za-z0-9]+$/, "").replace(/[_-]+/g, " ").trim()
        return name.length ? name : "Logo"
    }

    // "21 sep 2026 · " o vacío si la versión no trae fecha.
    function _logoVersionDate(iso) {
        var d = new Date(String(iso || ""))
        return isNaN(d.getTime()) ? "" : Qt.locale("es_PE").toString(d, "d MMM yyyy") + " · "
    }

    // Acción compacta de Laboratorio ("Usar", "Registrar muestra"): pill del
    // sistema de Calicatas (azul), no un Button genérico.
    component LabDetailScrimBlocker: MouseArea {
        anchors.fill: parent
        hoverEnabled: false
    }

    component PhotoPill: Rectangle {
        id: photoPill
        property string text: ""
        property bool primary: false
        // Dentro de una PhotoGlassBar oscura (visor): sin fondo sólido, solo luz del vidrio.
        property bool onGlass: false
        signal clicked()
        Layout.fillWidth: true
        implicitHeight: root.dp(photoPill.onGlass ? 42 : 38)
        radius: root.dp(photoPill.onGlass ? 14 : 12)
        color: photoPill.onGlass ? Qt.rgba(1, 1, 1, photoPillTap.pressed ? 0.22 : 0.10) : "transparent"
        border.width: photoPill.onGlass ? 1 : 0
        border.color: Qt.rgba(1, 1, 1, 0.16)
        CalicataLiquidGlass {
            dark: root.darkMode; accent: root.cGenBlue; danger: root.flow ? root.flow.theme.error : "#D9483B"
            visible: !photoPill.onGlass
            anchors.fill: parent
            radius: photoPill.radius
            tone: photoPill.primary ? "primary" : "glass"
            pressed: photoPillTap.pressed
        }
        scale: photoPillTap.pressed ? 0.975 : 1
        Behavior on scale { NumberAnimation { duration: photoPillTap.pressed ? 70 : 170; easing.type: Easing.OutCubic } }
        Behavior on color { ColorAnimation { duration: 140 } }
        Text { anchors.centerIn: parent; text: photoPill.text; color: photoPill.primary || photoPill.onGlass ? "#FFFFFF" : root.cText; font.bold: true; font.pixelSize: root.fsLabel }
        TapHandler { id: photoPillTap; gesturePolicy: TapHandler.ReleaseWithinBounds; onTapped: photoPill.clicked() }
        Accessible.role: Accessible.Button
        Accessible.name: photoPill.text
    }
    // Liquid Glass de Fotos: UNA sola superficie para tarjeta, panel vacío, barra de
    // acciones, visor y hoja de acciones. Es el material del sistema
    // (FlowCore.LiquidGlassSurface con los tokens de los flotantes de Ubicación / peek
    // de Información) + velo de legibilidad translúcido. `backdrop` es lo que la
    // superficie tiene detrás y nunca un ancestro (sin recursión de captura).
    component PhotoGlassBar: Item {
        id: glassBar
        // Superficie primaria de Fotos: lo anidado no la vuelve a capturar.
        objectName: "calicataGlassPrimary"
        property Item backdrop: null
        // Sobre la foto a pantalla completa (visor): velo oscuro y contenido claro.
        property bool onDark: false
        property real barRadius: root.dp(18)
        // Superficies grandes (tarjeta, hoja) dejan pasar los toques a su contenedor.
        property bool absorbTaps: true
        property real frost: 6
        property real lens: 0.15
        property string surfaceName: "calicata-photo-actions"
        // Hoja modal: un único grab estable mientras anima (como el popup de General).
        property bool frozen: false
        property rect captureRect: Qt.rect(0, 0, 0, 0)
        readonly property rect _clampedCapture: {
            var b = glassBar.backdrop
            var dependency = glassBar.x + glassBar.y + glassBar.width + glassBar.height + (glassBar.visible ? 1 : 0)
            if (!b || b.width <= 12 || b.height <= 12) return Qt.rect(0, 0, 0, 0)
            var m = 6
            var p = glassBar.mapToItem(b, 0, 0)
            var w = Math.min(glassBar.width, b.width - 2 * m)
            var h = Math.min(glassBar.height, b.height - 2 * m)
            return Qt.rect(Math.max(m, Math.min(p.x, b.width - w - m)),
                           Math.max(m, Math.min(p.y, b.height - h - m)), Math.max(1, w), Math.max(1, h))
        }
        // Superficie anidada dentro de otro vidrio: material de bajo coste (2 taps, sin
        // segunda sombra); el vidrio exterior ya da profundidad.
        property bool lowCost: false
        property color veilColor: glassBar.onDark ? Qt.rgba(0.05, 0.07, 0.10, 0.42)
                                  : root.darkMode ? Qt.rgba(0.0824, 0.102, 0.1882, 0.52) : Qt.rgba(0.98, 0.99, 1.0, 0.58)
        property color rimColor: glassBar.onDark || root.darkMode ? Qt.rgba(1, 1, 1, 0.10) : Qt.rgba(1, 1, 1, 0.62)
        default property alias content: glassBarContent.data
        QtObject {
            id: glassBarTokens
            // Al regresar de cámara/galería se vuelve a capturar el ambiente, incluso en hojas congeladas.
            readonly property bool shown: glassBar.visible && glassBar.opacity > 0
                                          && Qt.application.state === Qt.ApplicationActive
            readonly property Item glassBackdrop: glassBar.backdrop
            readonly property real materialPosition: 0
            readonly property bool lowCostGlass: glassBar.lowCost
            readonly property color glassTint: root.darkMode || glassBar.onDark ? Qt.rgba(0.0824, 0.102, 0.1882, 0.10) : Qt.rgba(0.95, 0.97, 1.0, 0.02)
            // Opaco: Qt premultiplica los colores de un ShaderEffect; translúcido se pintaría gris.
            readonly property color fallbackGlass: root.darkMode || glassBar.onDark ? Qt.rgba(0.14, 0.16, 0.20, 1.0) : Qt.rgba(0.985, 0.99, 1.0, 1.0)
            readonly property real rimLight: root.darkMode || glassBar.onDark ? 0.18 : 0.20
            readonly property real rimShade: root.darkMode || glassBar.onDark ? 0.04 : 0.035
            readonly property real rimSheen: root.darkMode || glassBar.onDark ? 0.03 : 0.015
            readonly property real edgeContrast: root.darkMode || glassBar.onDark ? 0.0 : 0.03
            readonly property real glassSaturation: 1.12
            readonly property color shadowColor: Qt.rgba(0.0824, 0.102, 0.1882, root.darkMode || glassBar.onDark ? 0.22 : 0.10)
        }
        FlowCore.LiquidGlassSurface {
            anchors.fill: parent
            tokens: glassBarTokens
            cornerRadius: glassBar.barRadius
            surfaceName: glassBar.surfaceName
            lens: glassBar.lens
            frost: glassBar.frost
            frostTaps: 6
            magnify: 0
            bevel: root.dp(6)
            elevation: true
            liveCapture: !glassBar.frozen
            // Sin rect explícito, la captura se recorta DENTRO del fondo: con fondo el
            // shader pinta opaco y el margen de 6 px fuera del ambiente saldría negro
            // (la tarjeta ocupa todo su ambiente).
            captureRect: glassBar.captureRect.width > 0 ? glassBar.captureRect : glassBar._clampedCapture
        }
        // Velo de legibilidad translúcido (deja ver lo de detrás; no es un bloque gris).
        Rectangle {
            anchors.fill: parent
            radius: glassBar.barRadius
            color: glassBar.veilColor
            border.width: 1
            border.color: glassBar.rimColor
        }
        // La barra absorbe toques en huecos o acciones deshabilitadas (no llegan a la foto).
        MouseArea { anchors.fill: parent; enabled: glassBar.absorbTaps; acceptedButtons: Qt.LeftButton }
        Item { id: glassBarContent; anchors.fill: parent }
    }

    // Ambiente propio de cada tarjeta de Fotos: lo que el vidrio de la tarjeta, del panel
    // vacío y de la barra refracta (la página es ancestro y no puede ser backdrop).
    // Estático: gradiente + manchas radiales suaves (Shapes, sin pase de desenfoque).
    component PhotoGlassAmbient: Rectangle {
        id: ambient
        gradient: Gradient {
            GradientStop { position: 0.0; color: root.darkMode ? "#182440" : root.brand.ingemaBlueWash }
            GradientStop { position: 1.0; color: root.darkMode ? root.brand.ingemaDeep : "#F8FAFD" }
        }
        Shapes.Shape {
            anchors.fill: parent
            Shapes.ShapePath {
                strokeWidth: -1
                fillGradient: Shapes.RadialGradient {
                    centerX: ambient.width * 0.22; centerY: ambient.height * 0.55
                    centerRadius: ambient.width * 0.55
                    focalX: centerX; focalY: centerY
                    GradientStop { position: 0.0; color: Qt.rgba(root.cGenBlue.r, root.cGenBlue.g, root.cGenBlue.b, root.darkMode ? 0.32 : 0.30) }
                    GradientStop { position: 1.0; color: Qt.rgba(root.cGenBlue.r, root.cGenBlue.g, root.cGenBlue.b, 0) }
                }
                startX: 0; startY: 0
                PathLine { x: ambient.width; y: 0 }
                PathLine { x: ambient.width; y: ambient.height }
                PathLine { x: 0; y: ambient.height }
                PathLine { x: 0; y: 0 }
            }
            Shapes.ShapePath {
                strokeWidth: -1
                fillGradient: Shapes.RadialGradient {
                    centerX: ambient.width * 0.82; centerY: ambient.height * 0.18
                    centerRadius: ambient.width * 0.42
                    focalX: centerX; focalY: centerY
                    GradientStop { position: 0.0; color: Qt.rgba(1, 1, 1, root.darkMode ? 0.07 : 0.85) }
                    GradientStop { position: 1.0; color: Qt.rgba(1, 1, 1, 0) }
                }
                startX: 0; startY: 0
                PathLine { x: ambient.width; y: 0 }
                PathLine { x: ambient.width; y: ambient.height }
                PathLine { x: 0; y: ambient.height }
                PathLine { x: 0; y: 0 }
            }
            Shapes.ShapePath {
                strokeWidth: -1
                fillGradient: Shapes.RadialGradient {
                    centerX: ambient.width * 0.78; centerY: ambient.height * 0.86
                    centerRadius: ambient.width * 0.38
                    focalX: centerX; focalY: centerY
                    GradientStop { position: 0.0; color: Qt.rgba(0.38, 0.78, 1.0, root.darkMode ? 0.24 : 0.32) }
                    GradientStop { position: 1.0; color: Qt.rgba(0.38, 0.78, 1.0, 0) }
                }
                startX: 0; startY: 0
                PathLine { x: ambient.width; y: 0 }
                PathLine { x: ambient.width; y: ambient.height }
                PathLine { x: 0; y: ambient.height }
                PathLine { x: 0; y: 0 }
            }
        }
    }

    // Insignia circular de vidrio para iconos de Fotos (barra, panel vacío, hoja).
    component PhotoGlassBadge: Rectangle {
        id: badge
        property string iconName: ""
        property color iconColor: root.cText
        property real iconSize: root.dp(20)
        property bool pressed: false
        radius: width / 2
        color: root.darkMode ? Qt.rgba(1, 1, 1, badge.pressed ? 0.16 : 0.08) : Qt.rgba(1, 1, 1, badge.pressed ? 0.82 : 0.55)
        border.width: 1
        border.color: root.darkMode ? Qt.rgba(1, 1, 1, 0.14) : Qt.rgba(1, 1, 1, 0.92)
        scale: badge.pressed ? 0.94 : 1
        Behavior on scale { NumberAnimation { duration: badge.pressed ? 70 : 170; easing.type: Easing.OutCubic } }
        Behavior on color { ColorAnimation { duration: 140 } }
        Components.FlowIcon {
            anchors.centerIn: parent
            width: badge.iconSize; height: width
            name: badge.iconName; flow: root.flow
            tintColor: badge.iconColor; activeTintColor: badge.iconColor; inactiveOpacity: 1
        }
    }

    // Acción de la barra de Fotos dentro del vidrio: insignia circular + texto (sin fondo
    // propio). Pulsación: luz suave + escala 0.975 (opacity/scale, baratas en A12).
    component PhotoActionTile: Item {
        id: tile
        property string label: ""
        property string iconName: ""
        property bool wide: false
        property bool onDark: false
        property bool divider: false
        signal clicked()
        readonly property color ink: tile.onDark ? "#FFFFFF" : root.cGenBlue
        readonly property bool compact: tile.width < root.dp(76)
        Layout.fillWidth: true
        Layout.fillHeight: true
        implicitHeight: tile.wide ? root.dp(52) : root.dp(60)
        opacity: enabled ? 1 : 0.38
        scale: tileTap.pressed ? 0.975 : 1
        Behavior on scale { NumberAnimation { duration: tileTap.pressed ? 70 : 170; easing.type: Easing.OutCubic } }
        Behavior on opacity { NumberAnimation { duration: 140 } }
        // Separador sutil entre acciones de la misma superficie.
        Rectangle {
            visible: tile.divider
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            width: 1; height: parent.height * 0.52
            color: tile.onDark || root.darkMode ? Qt.rgba(1, 1, 1, 0.14) : Qt.rgba(0.10, 0.16, 0.26, 0.12)
        }
        Rectangle {
            anchors.fill: parent
            anchors.margins: root.dp(3)
            radius: root.dp(16)
            color: tile.onDark ? Qt.rgba(1, 1, 1, 0.14) : Qt.rgba(root.cGenBlue.r, root.cGenBlue.g, root.cGenBlue.b, 0.10)
            opacity: tileTap.pressed ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: tileTap.pressed ? 60 : 200; easing.type: Easing.OutCubic } }
        }
        Column {
            visible: !tile.wide
            anchors.centerIn: parent
            spacing: root.dp(3)
            PhotoGlassBadge {
                anchors.horizontalCenter: parent.horizontalCenter
                width: root.dp(tile.compact ? 30 : 32); height: width
                iconName: tile.iconName
                iconSize: root.dp(tile.compact ? 16 : 17)
                pressed: tileTap.pressed
            }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: tile.label
                color: tile.ink
                font.pixelSize: root.sp(tile.compact ? 10.5 : 11.5)
                font.weight: Font.DemiBold
            }
        }
        Row {
            visible: tile.wide
            anchors.centerIn: parent
            spacing: root.dp(tile.compact ? 6 : 10)
            PhotoGlassBadge {
                anchors.verticalCenter: parent.verticalCenter
                width: root.dp(tile.width < root.dp(150) ? 34 : 40); height: width
                iconName: tile.iconName
                iconSize: root.dp(tile.width < root.dp(150) ? 17 : 20)
                pressed: tileTap.pressed
            }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: tile.label
                color: tile.ink
                font.pixelSize: root.sp(tile.width < root.dp(150) ? 13 : 15)
                font.weight: Font.Bold
            }
        }
        // Toque exclusivo: la acción no se propaga a la foto que está debajo (visor).
        TapHandler { id: tileTap; enabled: tile.enabled; gesturePolicy: TapHandler.ReleaseWithinBounds; onTapped: tile.clicked() }
        Accessible.role: Accessible.Button
        Accessible.name: tile.label
        Accessible.onPressAction: tile.clicked()
    }

    component LabActionPill: Rectangle {
        id: labPill
        property string text: ""
        signal clicked()
        implicitWidth: labPillText.implicitWidth + root.dp(26)
        implicitHeight: root.dp(34)
        Layout.preferredWidth: implicitWidth
        Layout.preferredHeight: implicitHeight
        radius: height / 2
        color: "transparent"
        scale: labPillTap.pressed ? 0.97 : 1
        CalicataLiquidGlass { dark: root.darkMode; accent: root.cGenBlue; danger: root.flow ? root.flow.theme.error : "#D9483B"; anchors.fill: parent; radius: labPill.radius; tone: "tinted"; pressed: labPillTap.pressed }
        Behavior on scale { NumberAnimation { duration: root.flow ? root.flow.instantDuration : 70; easing.type: Easing.OutQuad } }
        Behavior on color { ColorAnimation { duration: root.flow ? root.flow.duration(140) : 140 } }
        Accessible.role: Accessible.Button
        Accessible.name: labPill.text
        Text {
            id: labPillText
            anchors.centerIn: parent
            text: labPill.text
            color: root.cGenBlue
            font.pixelSize: root.fsLabel
            font.bold: true
        }
        TapHandler { id: labPillTap; onTapped: labPill.clicked() }
    }

    // Web SuggestionChip: el código sugerido; tocarlo lo adopta. El valor ya
    // seleccionado se muestra marcado y no es un botón.
    component LabSuggestionChip: Rectangle {
        id: chip
        property string code: ""
        property bool current: false
        signal adopt()
        implicitWidth: chipText.implicitWidth + root.dp(18)
        implicitHeight: root.dp(30)
        Layout.preferredWidth: implicitWidth
        Layout.preferredHeight: implicitHeight
        radius: root.dp(8)
        color: chip.current ? root.cGenBlueSoft : "transparent"
        border.width: 1
        border.color: chip.current ? root.cGenBlue : root.cBorder
        scale: chipTap.pressed ? 0.96 : 1
        Behavior on scale { NumberAnimation { duration: root.flow ? root.flow.instantDuration : 70; easing.type: Easing.OutQuad } }
        Accessible.role: chip.current ? Accessible.StaticText : Accessible.Button
        Accessible.name: chip.current ? chip.code + " ya está seleccionado" : "Adoptar " + chip.code
        Text {
            id: chipText
            anchors.centerIn: parent
            text: chip.code
            color: chip.current ? root.cGenBlue : root.cText
            font.pixelSize: root.fsLabel
            font.bold: true
        }
        TapHandler { id: chipTap; enabled: !chip.current; onTapped: chip.adopt() }
    }

    component GenGlassCheckBox: CheckBox {
        id: glassCheck
        font.pixelSize: root.fsLabel
        spacing: root.dp(10)
        indicator: Item {
            implicitWidth: root.dp(22)
            implicitHeight: root.dp(22)
            x: glassCheck.leftPadding
            y: glassCheck.topPadding + (glassCheck.availableHeight - height) / 2
            CalicataLiquidGlass {
                dark: root.darkMode; accent: root.cGenBlue; danger: root.flow ? root.flow.theme.error : "#D9483B"
                anchors.fill: parent
                radius: root.dp(6)
                tone: glassCheck.checked ? "primary" : "glass"
                pressed: glassCheck.down
                enabledLook: glassCheck.enabled
            }
            Text {
                anchors.centerIn: parent
                visible: glassCheck.checked
                text: "✓"
                color: root.darkMode ? root.brand.ingemaDeep : "#FFFFFF"
                font.pixelSize: root.sp(13)
                font.bold: true
            }
        }
        contentItem: Text {
            leftPadding: glassCheck.indicator.width + glassCheck.spacing
            text: glassCheck.text
            color: root.cText
            font: glassCheck.font
            wrapMode: Text.WordWrap
            verticalAlignment: Text.AlignVCenter
        }
    }

    component LabStepper: RowLayout {
        id: labStepper
        property int corteIdx: -1
        property string key: ""
        property int repeats: 0
        spacing: root.dp(4)
        function step(direction) {
            // Un texto a medio escribir se confirma antes de sumar/restar.
            if (!root.commitPendingField()) return
            repeats++
            // Aceleración controlada: pasos de 5 tras ~1.5 s manteniendo pulsado.
            root.stepLabField(labStepper.corteIdx, labStepper.key, direction, repeats > 15 ? 5 : 1)
        }
        Repeater {
            model: [[-1, "−"], [1, "+"]]
            delegate: Button {
                id: labStepButton
                required property var modelData
                Layout.fillWidth: true
                Layout.preferredHeight: root.dp(34)
                flat: true   // secundario: no domina sobre el campo editable
                text: modelData[1]
                background: CalicataLiquidGlass {
                    dark: root.darkMode; accent: root.cGenBlue; danger: root.flow ? root.flow.theme.error : "#D9483B"
                    radius: root.dp(10)
                    pressed: labStepButton.down
                    enabledLook: labStepButton.enabled
                }
                font.pixelSize: root.sp(18)
                focusPolicy: Qt.NoFocus
                autoRepeat: true
                autoRepeatDelay: 350
                autoRepeatInterval: 90
                Accessible.name: (modelData[0] > 0 ? "Aumentar " : "Disminuir ") + labStepper.key
                onPressedChanged: if (!pressed) labStepper.repeats = 0
                onClicked: labStepper.step(modelData[0])
            }
        }
    }

    // =============================================================
    // Ficha de calicata > General: filas planas con acento semántico.
    // Sin glass ni sombras; solo color de apoyo, borde fino y radio moderado.
    // =============================================================
    component GenIconBadge: Rectangle {
        id: genBadge
        property string iconName: ""
        property string glyph: ""
        property color accent: root.cGenBlue
        property color accentSoft: root.cGenBlueSoft
        // Sobre un control que ya es vidrio, el contenedor es solo la capa semántica
        // (acento): no se apila otra superficie de material bajo el icono.
        property bool onGlassControl: false
        implicitWidth: root.dp(36)
        implicitHeight: root.dp(36)
        radius: root.dp(10)
        color: genBadge.onGlassControl
               ? Qt.rgba(genBadge.accent.r, genBadge.accent.g, genBadge.accent.b, root.darkMode ? 0.22 : 0.12)
               : "transparent"
        CalicataLiquidGlass {
            visible: !genBadge.onGlassControl
            dark: root.darkMode
            accent: genBadge.accent
            anchors.fill: parent
            radius: genBadge.radius
            tone: "tinted"
        }
        Components.FlowIcon {
            anchors.centerIn: parent
            width: Math.round(parent.width * 0.55)
            height: width
            visible: genBadge.glyph.length === 0 && genBadge.iconName.length > 0
            name: genBadge.iconName
            flow: root.flow
            tintColor: genBadge.accent
            activeTintColor: genBadge.accent
            inactiveOpacity: 1
        }
        Text {
            anchors.centerIn: parent
            visible: genBadge.glyph.length > 0
            text: genBadge.glyph
            color: genBadge.accent
            font.pixelSize: Math.round(genBadge.height * 0.46)
            font.bold: true
        }
    }

    component GenGroupHeader: RowLayout {
        id: genGroup
        property string title: ""
        property color accent: root.cGenBlue
        Layout.fillWidth: true
        Layout.topMargin: root.dp(10)
        spacing: root.dp(8)
        Rectangle {
            Layout.preferredWidth: root.dp(4)
            Layout.preferredHeight: root.dp(14)
            radius: root.dp(2)
            color: genGroup.accent
        }
        Text {
            text: genGroup.title
            color: root.cText
            font.pixelSize: root.sp(12)
            font.weight: Font.DemiBold
            font.letterSpacing: 1.4
        }
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 1
            color: root.cBorder
        }
    }

    // Fila de General: etiqueta + caja con badge de icono, valor/entrada y
    // chevron opcional. `tappable` la convierte en disparador de selector.
    component GenFieldShell: ColumnLayout {
        id: genShell
        property string label: ""
        property bool labelCaps: true
        property string caption: ""
        property string iconName: ""
        property string glyph: ""
        property color accent: root.cGenBlue
        property color accentSoft: root.cGenBlueSoft
        property bool focused: false
        property bool tappable: false
        property bool emphasized: false
        property bool readOnly: false
        property string valueText: ""
        property string placeholder: ""
        property real contentHeight: genValue.visible ? genValue.implicitHeight + root.dp(14) : 0
        readonly property bool pressed: genTap.pressed
        default property alias content: genSlot.data
        signal activated()

        Layout.fillWidth: true
        spacing: root.dp(5)

        Text {
            Layout.fillWidth: true
            Layout.leftMargin: root.dp(2)
            visible: genShell.label.length > 0
            text: genShell.labelCaps ? genShell.label.toUpperCase() : genShell.label
            color: genShell.focused ? genShell.accent : root.cMuted
            font.pixelSize: genShell.labelCaps ? root.sp(11) : root.sp(12)
            font.letterSpacing: genShell.labelCaps ? 1.6 : 0.2
            font.weight: Font.DemiBold
            wrapMode: Text.WordWrap
            Behavior on color { ColorAnimation { duration: 140 } }
        }

        Rectangle {
            id: genBox
            Layout.fillWidth: true
            implicitHeight: Math.max(root.dp(54), genShell.contentHeight + root.dp(6))
            radius: root.dp(12)
            color: "transparent"
            scale: genShell.pressed ? 0.985 : 1
            Accessible.role: genShell.tappable ? Accessible.Button : Accessible.Grouping
            Accessible.name: genShell.label
            Behavior on scale { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }

            CalicataLiquidGlass {
                dark: root.darkMode
                accent: genShell.accent
                anchors.fill: parent
                radius: genBox.radius
                tone: genShell.emphasized ? "tinted" : "glass"
                pressed: genShell.pressed
                focused: genShell.focused
                enabledLook: !genShell.readOnly || genShell.tappable || genShell.valueText.length > 0
            }

            GenIconBadge {
                id: genShellBadge
                onGlassControl: true
                anchors.left: parent.left
                anchors.leftMargin: root.dp(9)
                anchors.verticalCenter: parent.verticalCenter
                iconName: genShell.iconName
                glyph: genShell.glyph
                accent: genShell.accent
                accentSoft: genShell.accentSoft
            }
            Item {
                id: genSlot
                anchors.left: genShellBadge.right
                anchors.leftMargin: root.dp(12)
                anchors.right: genChevron.visible ? genChevron.left : parent.right
                anchors.rightMargin: genChevron.visible ? root.dp(6) : root.dp(12)
                anchors.top: parent.top
                anchors.bottom: parent.bottom
            }
            Text {
                id: genValue
                anchors.left: genSlot.left
                anchors.right: genSlot.right
                anchors.verticalCenter: parent.verticalCenter
                visible: genShell.valueText.length > 0 || genShell.placeholder.length > 0
                text: genShell.valueText.length ? genShell.valueText : genShell.placeholder
                color: genShell.valueText.length ? root.cText : root.cMuted
                font.pixelSize: root.fsField
                font.weight: genShell.valueText.length && genShell.emphasized ? Font.DemiBold : Font.Normal
                wrapMode: Text.WordWrap
                maximumLineCount: 2
                elide: Text.ElideRight
            }
            Components.FlowIcon {
                id: genChevron
                anchors.right: parent.right
                anchors.rightMargin: root.dp(12)
                anchors.verticalCenter: parent.verticalCenter
                width: root.dp(16)
                height: root.dp(16)
                visible: genShell.tappable
                name: "calgen.chevron"
                flow: root.flow
                tintColor: genShell.pressed ? genShell.accent : root.cMuted
                activeTintColor: genShell.accent
                inactiveOpacity: 1
            }
            MouseArea {
                id: genTap
                anchors.fill: parent
                enabled: genShell.tappable
                visible: genShell.tappable
                onClicked: genShell.activated()
            }
        }

        Text {
            Layout.fillWidth: true
            Layout.leftMargin: root.dp(2)
            visible: genShell.caption.length > 0
            text: genShell.caption
            color: root.cMuted
            font.pixelSize: root.sp(11)
            wrapMode: Text.WordWrap
        }
    }

    // Campo de texto directo de General. Por defecto enlaza `doc.header[headerKey]`
    // (placeholder = etiqueta para los mensajes de validación); Código y Supervisor
    // sustituyen `boundText` / `commitHandler` con su contrato previo.
    component GenHeaderField: GenFieldShell {
        id: genHeaderField
        property string headerKey: ""
        property bool numeric: false
        // Tipo numérico y mínimo del campo interno (por defecto, el contrato previo).
        property string inputKind: genHeaderField.numeric ? Rules.DEPTH_METERS : Rules.FREE_TEXT
        property real inputMinimum: 0
        property string hint: ""
        property string boundText: root.doc ? String(root.doc.header[genHeaderField.headerKey] || "") : ""
        property var commitHandler: function(t) {
            var h = Object.assign({}, root.doc.header)
            h[genHeaderField.headerKey] = t
            root.doc.header = h
        }
        // Ajustes del campo interno (sin acceso agrupado a un tipo de componente inline).
        property string inputPlaceholder: genHeaderField.label
        property int inputMaximumLength: 32767
        property alias inputValidationError: genHeaderInput.validationError
        labelCaps: false
        focused: genHeaderInput.activeFocus
        contentHeight: genHeaderInput.implicitHeight

        BoundTextField {
            id: genHeaderInput
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            leftPadding: 0
            rightPadding: 0
            background: Item {}
            modelText: genHeaderField.boundText
            numericKind: genHeaderField.inputKind
            minimumValue: genHeaderField.inputMinimum
            placeholderText: genHeaderField.inputPlaceholder
            maximumLength: genHeaderField.inputMaximumLength
            placeholderTextColor: genHeaderField.hint.length ? "transparent" : root.cMuted
            onCommit: function(t) { return genHeaderField.commitHandler(t) }
        }
        Text {
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            visible: genHeaderField.hint.length > 0 && genHeaderInput.length === 0
                     && genHeaderInput.preeditText.length === 0
            text: genHeaderField.hint
            color: root.cMuted
            font.pixelSize: root.fsField
        }
    }

    component GenRoundIconButton: Button {
        id: genRoundBtn
        property string iconName: ""
        Layout.preferredWidth: root.dp(44)
        Layout.preferredHeight: root.dp(44)
        padding: 0
        focusPolicy: Qt.NoFocus
        scale: genRoundBtn.down ? 0.94 : 1
        Behavior on scale { NumberAnimation { duration: genRoundBtn.down ? 70 : 170; easing.type: Easing.OutCubic } }
        background: CalicataLiquidGlass {
            dark: root.darkMode; accent: root.cGenBlue; danger: root.flow ? root.flow.theme.error : "#D9483B"
            radius: width / 2
            pressed: genRoundBtn.down
            enabledLook: genRoundBtn.enabled
        }
        contentItem: Item {
            Components.FlowIcon {
                anchors.centerIn: parent
                width: root.dp(20)
                height: root.dp(20)
                name: genRoundBtn.iconName
                flow: root.flow
                tintColor: root.cText
                activeTintColor: root.cText
                inactiveOpacity: 1
            }
        }
    }

    component GenDialogHeader: RowLayout {
        id: genDialogHeader
        property string title: ""
        property string subtitle: ""
        signal closeRequested()
        Layout.fillWidth: true
        spacing: root.dp(8)
        ColumnLayout {
            Layout.fillWidth: true
            spacing: root.dp(2)
            Text {
                Layout.fillWidth: true
                text: genDialogHeader.title
                color: root.cText
                font.pixelSize: root.sp(18)
                font.bold: true
                elide: Text.ElideRight
            }
            Text {
                Layout.fillWidth: true
                visible: text.length > 0
                text: genDialogHeader.subtitle
                color: root.cMuted
                font.pixelSize: root.fsLabel
                elide: Text.ElideRight
            }
        }
        GenRoundIconButton {
            Layout.preferredWidth: root.dp(40)
            Layout.preferredHeight: root.dp(40)
            iconName: "calgen.close"
            Accessible.name: "Cerrar"
            onClicked: genDialogHeader.closeRequested()
        }
    }

    // `stacked` coloca el icono sobre la etiqueta (acciones compactas de logo).
    component GenDialogButton: Button {
        id: genBtn
        property bool primary: false
        property bool soft: false
        property bool stacked: false
        property color accent: root.cGenBlue
        property color accentSoft: root.cGenBlueSoft
        property string iconName: ""
        Layout.fillWidth: true
        implicitHeight: genBtn.stacked ? root.dp(58) : root.dp(46)
        Layout.preferredHeight: implicitHeight
        padding: root.dp(genBtn.stacked ? 6 : 10)
        focusPolicy: Qt.NoFocus
        font.pixelSize: genBtn.stacked ? root.fsLabel : root.fsField
        font.weight: Font.DemiBold
        scale: genBtn.down ? 0.985 : 1
        Behavior on scale { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
        background: CalicataLiquidGlass {
            dark: root.darkMode
            accent: genBtn.accent
            radius: root.dp(12)
            tone: genBtn.primary ? "primary" : genBtn.soft ? "tinted" : "glass"
            pressed: genBtn.down
            enabledLook: genBtn.enabled
        }
        contentItem: Item {
            implicitHeight: genBtnContent.implicitHeight
            Grid {
                id: genBtnContent
                anchors.centerIn: parent
                columns: genBtn.stacked ? 1 : 2
                spacing: root.dp(genBtn.stacked ? 4 : 6)
                horizontalItemAlignment: Grid.AlignHCenter
                verticalItemAlignment: Grid.AlignVCenter
                Components.FlowIcon {
                    visible: genBtn.iconName.length > 0
                    width: root.dp(genBtn.stacked ? 18 : 16)
                    height: width
                    name: genBtn.iconName
                    flow: root.flow
                    tintColor: genBtnLabel.color
                    activeTintColor: genBtnLabel.color
                    inactiveOpacity: 1
                }
                Text {
                    id: genBtnLabel
                    text: genBtn.text
                    font: genBtn.font
                    color: genBtn.primary ? (root.darkMode ? root.brand.ingemaDeep : "#FFFFFF")
                         : genBtn.soft ? genBtn.accent : root.cText
                }
            }
        }
    }

    component GenSearchField: TextField {
        id: genSearch
        Layout.fillWidth: true
        implicitHeight: root.dp(44)
        leftPadding: root.dp(40)
        rightPadding: root.dp(12)
        font.pixelSize: root.fsField
        color: root.cText
        placeholderTextColor: root.cMuted
        inputMethodHints: Qt.ImhNoPredictiveText
        background: Item {
            CalicataLiquidGlass {
                dark: root.darkMode; accent: root.cGenBlue; danger: root.flow ? root.flow.theme.error : "#D9483B"
                anchors.fill: parent
                radius: root.dp(12)
                focused: genSearch.activeFocus
            }
            Components.FlowIcon {
                anchors.left: parent.left
                anchors.leftMargin: root.dp(13)
                anchors.verticalCenter: parent.verticalCenter
                width: root.dp(18)
                height: root.dp(18)
                name: "calgen.search"
                flow: root.flow
                tintColor: root.cMuted
                activeTintColor: root.cMuted
                inactiveOpacity: 1
            }
        }
    }

    // Opción de lista para selectores (proyecto / maquinaria) con radio.
    component GenChoiceRow: Rectangle {
        id: genChoice
        property string title: ""
        property string detail: ""
        property string iconName: ""
        property bool selected: false
        property color accent: root.cGenBlue
        property color accentSoft: root.cGenBlueSoft
        signal picked()
        implicitHeight: Math.max(root.dp(54), genChoiceText.implicitHeight + root.dp(18))
        radius: root.dp(12)
        color: "transparent"
        Accessible.role: Accessible.RadioButton
        Accessible.name: genChoice.title
        Accessible.checked: genChoice.selected
        CalicataLiquidGlass {
            dark: root.darkMode
            accent: genChoice.accent
            anchors.fill: parent
            radius: genChoice.radius
            tone: genChoice.selected ? "tinted" : "clear"
            pressed: genChoiceTap.pressed
        }

        Components.FlowIcon {
            id: genChoiceIcon
            anchors.left: parent.left
            anchors.leftMargin: root.dp(12)
            anchors.verticalCenter: parent.verticalCenter
            width: root.dp(22)
            height: root.dp(22)
            name: genChoice.iconName
            flow: root.flow
            tintColor: genChoice.selected ? genChoice.accent : root.cText
            activeTintColor: genChoice.accent
            inactiveOpacity: 1
        }
        Column {
            id: genChoiceText
            anchors.left: genChoiceIcon.right
            anchors.leftMargin: root.dp(12)
            anchors.right: genChoiceRadio.left
            anchors.rightMargin: root.dp(10)
            anchors.verticalCenter: parent.verticalCenter
            spacing: root.dp(1)
            Text {
                width: parent.width
                text: genChoice.title
                color: genChoice.selected ? genChoice.accent : root.cText
                font.pixelSize: root.fsField
                font.weight: genChoice.selected ? Font.DemiBold : Font.Normal
                wrapMode: Text.WordWrap
                maximumLineCount: 2
                elide: Text.ElideRight
            }
            Text {
                width: parent.width
                visible: text.length > 0
                text: genChoice.detail
                color: root.cMuted
                font.pixelSize: root.fsLabel
                elide: Text.ElideRight
            }
        }
        Rectangle {
            id: genChoiceRadio
            anchors.right: parent.right
            anchors.rightMargin: root.dp(12)
            anchors.verticalCenter: parent.verticalCenter
            width: root.dp(22)
            height: width
            radius: width / 2
            color: "transparent"
            border.width: genChoice.selected ? 2 : 1.5
            border.color: genChoice.selected ? genChoice.accent : root.cBorder
            Rectangle {
                anchors.centerIn: parent
                width: parent.width - root.dp(10)
                height: width
                radius: width / 2
                color: genChoice.accent
                visible: genChoice.selected
            }
        }
        Rectangle {
            anchors.bottom: parent.bottom
            anchors.left: genChoiceText.left
            anchors.right: parent.right
            height: 1
            color: root.cBorder
            opacity: 0.6
            visible: !genChoice.selected
        }
        MouseArea {
            id: genChoiceTap
            anchors.fill: parent
            onClicked: genChoice.picked()
        }
    }

    // Base única de los emergentes de General (proyecto, maquinaria, fecha,
    // identidad): centrado sobre el área libre del teclado, transición
    // opacity/scale/translate y material Liquid Glass casi imperceptible.
    // Solo se animan opacity, scale y slideY; el backdrop se captura una vez
    // (liveCapture=false) sobre el rect final, sin blur animado.
    readonly property Item _genGlassBackdrop: ApplicationWindow.contentItem ? ApplicationWindow.contentItem : root
    component GenPopup: Popup {
        id: genPopup
        property Item glassBackdropItem: null
        property real preferredWidth: root.dp(480)
        property real preferredHeight: root.dp(620)
        property real slideY: 0
        readonly property int openMs: root.flow && root.flow.motionAllowed === false ? 0 : 200
        readonly property int closeMs: root.flow && root.flow.motionAllowed === false ? 0 : 150
        readonly property real imeInset: root.flow && root.flow.imeHeight !== undefined ? root.flow.imeHeight : 0
        readonly property real freeHeight: (parent ? parent.height : root.height) - imeInset
        readonly property real baseY: Math.max(root.dp(12), (freeHeight - height) / 2)
        parent: Overlay.overlay
        modal: true
        focus: true
        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
        width: Math.min((parent ? parent.width : root.width) - root.dp(24), preferredWidth)
        height: Math.min(preferredHeight, freeHeight - root.dp(24))
        x: Math.max(0, ((parent ? parent.width : root.width) - width) / 2)
        y: baseY + slideY
        padding: root.dp(16)

        Overlay.modal: GenGlassScrim { popupItem: genPopup }

        enter: Transition {
            ParallelAnimation {
                NumberAnimation { target: genPopup; property: "opacity"; from: 0; to: 1; duration: genPopup.openMs; easing.type: Easing.OutCubic }
                NumberAnimation { target: genPopup; property: "scale"; from: 0.975; to: 1; duration: genPopup.openMs; easing.type: Easing.OutCubic }
                NumberAnimation { target: genPopup; property: "slideY"; from: root.dp(10); to: 0; duration: genPopup.openMs; easing.type: Easing.OutCubic }
            }
        }
        exit: Transition {
            ParallelAnimation {
                NumberAnimation { target: genPopup; property: "opacity"; to: 0; duration: genPopup.closeMs; easing.type: Easing.InCubic }
                NumberAnimation { target: genPopup; property: "scale"; to: 0.98; duration: genPopup.closeMs; easing.type: Easing.InCubic }
                NumberAnimation { target: genPopup; property: "slideY"; to: root.dp(6); duration: genPopup.closeMs; easing.type: Easing.InCubic }
            }
        }

        background: GenPopupGlass {
            popupItem: genPopup
            finalY: genPopup.baseY
            surfaceName: "calicata-general-popup"
        }
    }

    // Material Liquid Glass de TODOS los emergentes de Calicatas = la composición de
    // "Información de la calicata" (CalicatasEditorPage, infoPeek), sin reinterpretar:
    //  · fondo: GenGlassScrim (captura congelada 0.5x de la ventana + MultiEffect
    //    blur 0.26 + atenuación ligera), como el modal del peek;
    //  · panel: FlowCore.LiquidGlassSurface con los tokens del peek (los del primer
    //    menú 3D Touch del Dock) y su preset: lens 0.3, frost 8, 6 taps, bisel 14,
    //    captura congelada del rect FINAL sin transformar (un grab estable);
    //  · velo de lectura del peek (0.42 claro / 0.30 oscuro) + filo casi invisible.
    // El contenido va encima, nítido; los controles NO vuelven a capturar.
    component GenPopupGlass: Item {
        id: popupGlass
        // Superficie primaria del emergente: lo que vive dentro (filas, botones,
        // campos) usa el tratamiento de control anidado y NO la vuelve a capturar.
        objectName: "calicataGlassPrimary"
        property var popupItem: null
        property real radius: root.dp(28)
        property real finalX: popupGlass.popupItem ? popupGlass.popupItem.x : 0
        property real finalY: popupGlass.popupItem ? popupGlass.popupItem.y : 0
        property string surfaceName: "calicata-popup"
        // Fondo que refracta: la capa ya desenfocada de su scrim; si el emergente no
        // tiene scrim (no modal), el contenido de la ventana como el peek.
        readonly property Item activeBackdrop: popupGlass.popupItem && popupGlass.popupItem.glassBackdropItem
                                               ? popupGlass.popupItem.glassBackdropItem : root._genGlassBackdrop
        QtObject {
            id: popupGlassTokens
            readonly property bool shown: !!popupGlass.popupItem && popupGlass.popupItem.visible === true
            readonly property Item glassBackdrop: shown ? popupGlass.activeBackdrop : null
            readonly property real materialPosition: 0
            readonly property bool lowCostGlass: Mobile.InGeCoreFlow.lowMemoryMode
                || Mobile.InGeCoreFlow.performance.profile >= Mobile.InGeCoreFlow.performance.safe
            readonly property color glassTint: root.darkMode ? Qt.rgba(0.0824, 0.102, 0.1882, 0.10) : Qt.rgba(0.95, 0.97, 1.0, 0.02)
            // Opaco: Qt premultiplica los colores de un ShaderEffect; translúcido se pintaría gris.
            readonly property color fallbackGlass: root.darkMode ? Qt.rgba(0.14, 0.16, 0.20, 1.0) : Qt.rgba(0.985, 0.99, 1.0, 1.0)
            readonly property real rimLight: root.darkMode ? 0.18 : 0.20
            readonly property real rimShade: root.darkMode ? 0.04 : 0.035
            readonly property real rimSheen: root.darkMode ? 0.03 : 0.015
            readonly property real edgeContrast: root.darkMode ? 0.0 : 0.03
            readonly property real glassSaturation: 1.12
            readonly property color shadowColor: Qt.rgba(0.0824, 0.102, 0.1882, root.darkMode ? 0.22 : 0.10)
        }
        FlowCore.LiquidGlassSurface {
            anchors.fill: parent
            tokens: popupGlassTokens
            cornerRadius: popupGlass.radius
            surfaceName: popupGlass.surfaceName
            lens: 0.3
            frost: 8
            frostTaps: 6
            magnify: 0
            bevel: root.dp(14)
            elevation: true
            // Captura viva justificada: el fondo registrado es estático (imagen congelada
            // ya desenfocada); solo se re-renderiza cuando cambia (al registrarse); sin timers.
            liveCapture: true
            captureRect: {
                var b = popupGlass.activeBackdrop
                var dependency = popupGlass.finalX + popupGlass.finalY + popupGlass.width + popupGlass.height
                if (!b || !popupGlass.popupItem || !popupGlass.popupItem.parent) return Qt.rect(0, 0, 0, 0)
                var r = popupGlass.popupItem.parent.mapToItem(b, popupGlass.finalX, popupGlass.finalY, popupGlass.width, popupGlass.height)
                // Dentro del fondo (+ margen del shader): nunca se muestrea fuera (sería negro).
                var m = 6
                var w = Math.min(r.width, b.width - 2 * m), h = Math.min(r.height, b.height - 2 * m)
                return Qt.rect(Math.max(m, Math.min(r.x, b.width - w - m)), Math.max(m, Math.min(r.y, b.height - h - m)),
                               Math.max(1, w), Math.max(1, h))
            }
        }
        // Tinte de lectura LIGERO sobre el vidrio (el fondo ya llega desenfocado, así que
        // no hace falta un velo lechoso para tapar texto) y filo de luz.
        Rectangle {
            anchors.fill: parent
            radius: popupGlass.radius
            color: root.darkMode ? Qt.rgba(0.0824, 0.102, 0.1882, 0.26) : Qt.rgba(0.98, 0.99, 1.0, 0.24)
            border.width: 1
            border.color: root.darkMode ? Qt.rgba(1, 1, 1, 0.10) : Qt.rgba(1, 1, 1, 0.55)
        }
    }

    // Fondo de los emergentes (como el modal del peek "Información de la calicata"):
    // captura congelada a 0.5x del contenido de la ventana (hermano del Overlay, nunca
    // incluye el emergente), desenfocada UNA vez y con más color (vibrancia), sobre una
    // base opaca de la página: así no hay texels transparentes en ningún borde.
    // Esa capa se REGISTRA en el emergente (glassBackdropItem) y es lo que refracta su
    // vidrio: fondo → desenfoque → vidrio → contenido, sin texto fantasma.
    // La atenuación va fuera de la capa registrada (solo oscurece alrededor del panel).
    component GenGlassScrim: Item {
        id: glassScrim
        // Fondo opaco y ya desenfocado: lo refractan los controles del emergente.
        objectName: "calicataGlassBackdrop"
        property var popupItem: null
        // Capa estable (no hereda la animación de opacidad de la raíz) para capturar.
        property Item glassLayer: null
        opacity: glassScrim.popupItem ? glassScrim.popupItem.opacity : 1
        Loader {
            anchors.fill: parent
            active: !!glassScrim.popupItem && glassScrim.popupItem.visible === true
            sourceComponent: Item {
                id: scrimBlurLayer
                Rectangle { anchors.fill: parent; color: root.cPage }
                ShaderEffectSource {
                    id: scrimCapture
                    anchors.fill: parent
                    sourceItem: root._genGlassBackdrop
                    textureSize: Qt.size(Math.max(1, Math.round(width * 0.5)), Math.max(1, Math.round(height * 0.5)))
                    live: false
                    hideSource: false
                    visible: false
                    Component.onCompleted: scheduleUpdate()
                }
                MultiEffect {
                    anchors.fill: parent
                    source: scrimCapture
                    autoPaddingEnabled: false
                    blurEnabled: true
                    blurMax: 48
                    blur: 0.62
                    saturation: 0.30
                }
                Component.onCompleted: {
                    glassScrim.glassLayer = scrimBlurLayer
                    if (glassScrim.popupItem && glassScrim.popupItem.glassBackdropItem !== undefined)
                        glassScrim.popupItem.glassBackdropItem = scrimBlurLayer
                }
                Component.onDestruction: {
                    if (glassScrim.glassLayer === scrimBlurLayer) glassScrim.glassLayer = null
                    if (glassScrim.popupItem && glassScrim.popupItem.glassBackdropItem === scrimBlurLayer)
                        glassScrim.popupItem.glassBackdropItem = null
                }
            }
        }
        Rectangle {
            anchors.fill: parent
            color: root.darkMode ? root.brand.ingemaDeepShade : root.brand.ingemaDeep
            opacity: root.darkMode ? 0.20 : 0.07
        }
    }

    // Cabecera y botonera de los Dialog de Calicatas (sin la franja blanca de Basic).
    component GenDialogTitle: Label {
        padding: root.dp(18)
        bottomPadding: root.dp(6)
        color: root.cText
        font.pixelSize: root.sp(18)
        font.bold: true
        elide: Label.ElideRight
        visible: text.length > 0
        background: Item {}
    }
    component GenDialogButtonBox: DialogButtonBox {
        padding: root.dp(14)
        spacing: root.dp(8)
        background: Item {}
        delegate: GenDialogButton {
            Layout.fillWidth: false
            implicitWidth: Math.max(root.dp(96), implicitContentWidth + leftPadding + rightPadding)
            soft: DialogButtonBox.buttonRole === DialogButtonBox.AcceptRole
        }
    }

    // Cabecera de la etapa General: contexto de la ficha y título de la etapa.
    component GenStageHeader: Column {
        id: genHeader
        property string codeText: ""
        property string projectText: ""
        property bool projectAssigned: false
        property string stageText: "General"
        property string stageIcon: "calgen.code"
        spacing: root.dp(6)

        Text {
            width: parent.width
            text: genHeader.codeText || "NUEVA CALICATA"
            color: root.cMuted
            font.pixelSize: root.sp(11)
            font.letterSpacing: 2.4
            font.weight: Font.DemiBold
            elide: Text.ElideRight
        }
        Row {
            width: parent.width
            spacing: root.dp(8)
            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                width: root.dp(8)
                height: width
                radius: width / 2
                color: genHeader.projectAssigned ? root.cGenBlue : root.cGenOrange
            }
            Text {
                width: parent.width - root.dp(16)
                text: genHeader.projectText
                color: root.cText
                font.pixelSize: root.sp(17)
                maximumLineCount: 2
                wrapMode: Text.WordWrap
                elide: Text.ElideRight
            }
        }
        Item { width: 1; height: root.dp(10) }
        Row {
            width: parent.width
            spacing: root.dp(14)
            GenIconBadge {
                width: root.dp(54)
                height: root.dp(54)
                radius: root.dp(15)
                iconName: genHeader.stageIcon
            }
            Column {
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width - root.dp(68)
                spacing: root.dp(2)
                Text {
                    text: "FICHA DE CALICATA"
                    color: root.cMuted
                    font.pixelSize: root.sp(11)
                    font.letterSpacing: 3
                    font.weight: Font.DemiBold
                }
                Text {
                    width: parent.width
                    text: genHeader.stageText
                    color: root.cText
                    font.pixelSize: root.sp(34)
                    font.bold: true
                    wrapMode: Text.WordWrap
                }
            }
        }
    }

    // ===== Perfil (rediseño): piezas visuales propias de la etapa =====
    // Superficies sólidas (sin glass); los emergentes usan GenPopup.
    component PrfCard: Rectangle {
        id: prfCard
        property string title: ""
        property string iconName: ""
        property color iconTint: root.cText
        default property alias cardContent: prfCardBody.data
        property alias headerTrailing: prfCardTrailing.data
        Layout.fillWidth: true
        implicitHeight: prfCardLayout.implicitHeight + root.dp(32)
        radius: root.dp(18)
        color: "transparent"
        CalicataLiquidGlass { dark: root.darkMode; accent: root.cGenBlue; danger: root.flow ? root.flow.theme.error : "#D9483B"; anchors.fill: parent; radius: prfCard.radius; level: "card" }
        ColumnLayout {
            id: prfCardLayout
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: root.dp(16)
            spacing: root.dp(14)
            RowLayout {
                Layout.fillWidth: true
                visible: prfCard.title.length > 0
                spacing: root.dp(10)
                GenIconBadge {
                    Layout.preferredWidth: root.dp(32)
                    Layout.preferredHeight: root.dp(32)
                    visible: prfCard.iconName.length > 0
                    iconName: prfCard.iconName
                    accent: Qt.colorEqual(prfCard.iconTint, root.cText) ? root.cGenBlue : prfCard.iconTint
                }
                Text {
                    Layout.fillWidth: true
                    text: prfCard.title
                    color: root.cText
                    font.pixelSize: root.sp(17)
                    font.weight: Font.DemiBold
                    elide: Text.ElideRight
                }
                Row {
                    id: prfCardTrailing
                    spacing: root.dp(6)
                }
            }
            ColumnLayout {
                id: prfCardBody
                Layout.fillWidth: true
                spacing: root.dp(12)
            }
        }
    }

    // Subsección del editor del estrato (icono + título + contenido).
    component PrfSubsection: Rectangle {
        id: prfSub
        property string title: ""
        property string iconName: ""
        property color accent: root.cGenBlue
        default property alias subContent: prfSubBody.data
        // Alto manual (asa inferior). Nunca menor que su contenido.
        property bool resizable: false
        property real manualHeight: -1
        property real maxHeight: Math.max(root.dp(240), root.height * (root.isPhone ? 0.8 : 0.9))
        readonly property real naturalHeight: prfSubLayout.implicitHeight + root.dp(28)
        Layout.fillWidth: true
        Layout.alignment: Qt.AlignTop
        implicitHeight: prfSub.resizable && prfSub.manualHeight > 0
                        ? Math.max(prfSub.naturalHeight, Math.min(prfSub.manualHeight, prfSub.maxHeight))
                        : prfSub.naturalHeight
        radius: root.dp(14)
        color: "transparent"
        CalicataLiquidGlass { dark: root.darkMode; accent: prfSub.accent; anchors.fill: parent; radius: prfSub.radius }
        ColumnLayout {
            id: prfSubLayout
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: root.dp(14)
            spacing: root.dp(10)
            RowLayout {
                Layout.fillWidth: true
                spacing: root.dp(8)
                GenIconBadge {
                    Layout.preferredWidth: root.dp(28)
                    Layout.preferredHeight: root.dp(28)
                    radius: root.dp(8)
                    onGlassControl: true
                    iconName: prfSub.iconName
                    accent: prfSub.accent
                }
                Text {
                    Layout.fillWidth: true
                    text: prfSub.title
                    color: root.cText
                    font.pixelSize: root.sp(14)
                    font.weight: Font.DemiBold
                    elide: Text.ElideRight
                }
            }
            ColumnLayout {
                id: prfSubBody
                Layout.fillWidth: true
                spacing: root.dp(10)
            }
        }
        PrfResizeGrip {
            visible: prfSub.resizable
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            targetItem: prfSub
            minHeight: prfSub.naturalHeight
            maxHeight: prfSub.maxHeight
        }
    }

    // Asa de redimensionado vertical (esquina inferior derecha). Arrastrar
    // hacia abajo agranda, hacia arriba achica; doble toque vuelve al alto
    // natural. preventStealing evita que el scroll de la ficha robe el gesto.
    component PrfResizeGrip: MouseArea {
        id: prfGrip
        property var targetItem: null
        property real minHeight: 0
        property real maxHeight: 0
        property real startHeight: 0
        property real startSceneY: 0
        width: root.dp(40)
        height: root.dp(26)
        enabled: visible
        preventStealing: true
        cursorShape: Qt.SizeVerCursor
        Accessible.role: Accessible.Button
        Accessible.name: "Redimensionar bloque"
        onPressed: function(mouse) {
            if (!prfGrip.targetItem) return
            prfGrip.startHeight = prfGrip.targetItem.height
            prfGrip.startSceneY = prfGrip.mapToItem(null, mouse.x, mouse.y).y
        }
        onPositionChanged: function(mouse) {
            if (!prfGrip.pressed || !prfGrip.targetItem) return
            var sceneY = prfGrip.mapToItem(null, mouse.x, mouse.y).y
            prfGrip.targetItem.manualHeight = Math.max(prfGrip.minHeight,
                Math.min(prfGrip.maxHeight, prfGrip.startHeight + sceneY - prfGrip.startSceneY))
        }
        onDoubleClicked: if (prfGrip.targetItem) prfGrip.targetItem.manualHeight = -1
        Repeater {
            model: 3
            delegate: Rectangle {
                required property int index
                width: root.dp(4 + index * 5)
                height: root.dp(2)
                radius: height / 2
                rotation: -45
                antialiasing: true
                color: prfGrip.pressed ? root.cGenBlue : root.cMuted
                opacity: prfGrip.pressed ? 1 : 0.7
                x: prfGrip.width - width / 2 - root.dp(8) - root.dp(index)
                y: prfGrip.height - root.dp(8) - root.dp(index * 2)
            }
        }
    }

    // Selector compacto (etiqueta arriba o a la izquierda) que abre un GenPopup.
    component PrfPickField: GridLayout {
        id: prfPickField
        property string label: ""
        property string valueText: ""
        property string placeholder: "Seleccionar"
        property bool sideLabel: false
        property real labelWidth: root.dp(116)
        property real boxHeight: root.dp(42)
        property color swatch: "transparent"
        property var patterns: []
        readonly property bool pressed: prfPickTap.pressed
        signal activated()
        Layout.fillWidth: true
        columns: sideLabel ? 2 : 1
        columnSpacing: root.dp(10)
        rowSpacing: root.dp(4)
        Text {
            Layout.preferredWidth: prfPickField.sideLabel ? prfPickField.labelWidth : -1
            Layout.fillWidth: !prfPickField.sideLabel
            Layout.alignment: Qt.AlignVCenter
            visible: prfPickField.label.length > 0
            text: prfPickField.label
            color: root.cMuted
            font.pixelSize: root.fsLabel
            wrapMode: Text.WordWrap
        }
        Rectangle {
            Layout.fillWidth: true
            implicitHeight: prfPickField.boxHeight
            radius: root.dp(10)
            color: "transparent"
            CalicataLiquidGlass {
                dark: root.darkMode; accent: root.cGenBlue; danger: root.flow ? root.flow.theme.error : "#D9483B"
                anchors.fill: parent
                radius: parent.radius
                pressed: prfPickField.pressed
                focused: prfPickField.pressed
                enabledLook: prfPickField.enabled
            }
            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: root.dp(10)
                anchors.rightMargin: root.dp(10)
                spacing: root.dp(8)
                Rectangle {
                    Layout.preferredWidth: root.dp(prfPickField.patterns.length ? 44 : 22)
                    Layout.preferredHeight: root.dp(22)
                    visible: prfPickField.swatch.a > 0 || prfPickField.patterns.length > 0
                    radius: root.dp(5)
                    color: prfPickField.swatch
                    border.width: 1
                    border.color: root.cBorder
                    clip: true
                    Row {
                        anchors.fill: parent
                        Repeater {
                            model: prfPickField.patterns
                            delegate: Image {
                                required property string modelData
                                width: parent ? parent.width / Math.max(1, prfPickField.patterns.length) : 0
                                height: parent ? parent.height : 0
                                source: modelData
                                fillMode: Image.Tile
                                sourceSize.width: root.dp(26)
                                sourceSize.height: root.dp(26)
                                cache: true
                            }
                        }
                    }
                }
                Text {
                    Layout.fillWidth: true
                    text: prfPickField.valueText.length ? prfPickField.valueText : prfPickField.placeholder
                    color: prfPickField.valueText.length ? root.cText : root.cMuted
                    font.pixelSize: root.fsLabel + 1
                    elide: Text.ElideRight
                }
                Components.FlowIcon {
                    Layout.preferredWidth: root.dp(14)
                    Layout.preferredHeight: root.dp(14)
                    name: "calgen.chevron"
                    rotation: 90
                    flow: root.flow
                    tintColor: root.cMuted
                    activeTintColor: root.cGenBlue
                    inactiveOpacity: 1
                }
            }
            MouseArea {
                id: prfPickTap
                anchors.fill: parent
                enabled: prfPickField.enabled
                onClicked: prfPickField.activated()
            }
        }
    }

    // Etiqueta + campo enlazado (BoundTextField existente como contenido).
    component PrfLabeledInput: ColumnLayout {
        id: prfInput
        property string label: ""
        default property alias inputContent: prfInputSlot.data
        Layout.fillWidth: true
        spacing: root.dp(4)
        Text {
            Layout.fillWidth: true
            text: prfInput.label
            color: root.cMuted
            font.pixelSize: root.fsLabel
            elide: Text.ElideRight
        }
        ColumnLayout {
            id: prfInputSlot
            Layout.fillWidth: true
            spacing: 0
        }
    }

    // Opción grande (tipo de excavación / método / origen).
    component PrfSegment: Rectangle {
        id: prfSegment
        property string label: ""
        property string iconName: ""
        property bool isOn: false
        property color accent: root.cGenBlue
        property color accentSoft: root.cGenBlueSoft
        signal picked()
        Layout.fillWidth: true
        implicitHeight: root.dp(50)
        radius: root.dp(12)
        color: "transparent"
        scale: prfSegmentTap.pressed ? 0.985 : 1
        Behavior on scale { NumberAnimation { duration: 130; easing.type: Easing.OutCubic } }
        Accessible.role: Accessible.RadioButton
        Accessible.name: prfSegment.label
        Accessible.checked: prfSegment.isOn
        CalicataLiquidGlass {
            dark: root.darkMode
            accent: prfSegment.accent
            anchors.fill: parent
            radius: prfSegment.radius
            tone: prfSegment.isOn ? "tinted" : "glass"
            selected: prfSegment.isOn
            pressed: prfSegmentTap.pressed
        }
        Row {
            anchors.centerIn: parent
            spacing: root.dp(8)
            Components.FlowIcon {
                anchors.verticalCenter: parent.verticalCenter
                width: root.dp(20)
                height: root.dp(20)
                visible: prfSegment.iconName.length > 0
                name: prfSegment.iconName
                flow: root.flow
                tintColor: prfSegment.isOn ? prfSegment.accent : root.cText
                activeTintColor: prfSegment.accent
                inactiveOpacity: 1
            }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: prfSegment.label
                color: prfSegment.isOn ? prfSegment.accent : root.cText
                font.pixelSize: root.fsLabel + 1
                font.weight: prfSegment.isOn ? Font.DemiBold : Font.Normal
            }
        }
        MouseArea {
            id: prfSegmentTap
            anchors.fill: parent
            onClicked: prfSegment.picked()
        }
    }

    component PrfSwitch: RowLayout {
        id: prfSwitch
        property string label: ""
        property bool isOn: false
        signal flipped()
        Layout.fillWidth: true
        spacing: root.dp(10)
        Accessible.role: Accessible.CheckBox
        Accessible.name: prfSwitch.label
        Accessible.checked: prfSwitch.isOn
        Rectangle {
            Layout.preferredWidth: root.dp(42)
            Layout.preferredHeight: root.dp(24)
            radius: height / 2
            color: "transparent"
            CalicataLiquidGlass { dark: root.darkMode; accent: root.cGenBlue; danger: root.flow ? root.flow.theme.error : "#D9483B"; anchors.fill: parent; radius: parent.radius; tone: prfSwitch.isOn ? "primary" : "glass" }
            Rectangle {
                width: parent.height - root.dp(6)
                height: width
                radius: width / 2
                y: root.dp(3)
                x: prfSwitch.isOn ? parent.width - width - root.dp(3) : root.dp(3)
                color: "#FFFFFF"
                Behavior on x { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
            }
        }
        Text {
            Layout.fillWidth: true
            text: prfSwitch.label
            color: root.cText
            font.pixelSize: root.fsLabel
            wrapMode: Text.WordWrap
        }
        TapHandler { onTapped: prfSwitch.flipped() }
    }

    component PrfCheck: RowLayout {
        id: prfCheck
        property string label: ""
        property bool isOn: false
        property bool strong: false
        signal flipped()
        Layout.fillWidth: true
        spacing: root.dp(8)
        Accessible.role: Accessible.CheckBox
        Accessible.name: prfCheck.label
        Accessible.checked: prfCheck.isOn
        Rectangle {
            Layout.preferredWidth: root.dp(18)
            Layout.preferredHeight: root.dp(18)
            radius: root.dp(5)
            color: "transparent"
            CalicataLiquidGlass { dark: root.darkMode; accent: root.cGenBlue; danger: root.flow ? root.flow.theme.error : "#D9483B"; anchors.fill: parent; radius: parent.radius; tone: prfCheck.isOn ? "primary" : "glass" }
            Text {
                anchors.centerIn: parent
                visible: prfCheck.isOn
                text: "✓"
                color: "#FFFFFF"
                font.pixelSize: root.sp(12)
                font.bold: true
            }
        }
        Text {
            Layout.fillWidth: true
            text: prfCheck.label
            color: root.cText
            font.pixelSize: root.fsLabel
            font.weight: prfCheck.strong ? Font.DemiBold : Font.Normal
            wrapMode: Text.WordWrap
        }
        TapHandler { onTapped: prfCheck.flipped() }
    }

    component PrfChip: Rectangle {
        id: prfChip
        property string label: ""
        property bool isOn: false
        signal flipped()
        implicitWidth: prfChipText.implicitWidth + root.dp(24)
        implicitHeight: root.dp(32)
        radius: height / 2
        color: "transparent"
        Accessible.role: Accessible.CheckBox
        Accessible.name: prfChip.label
        Accessible.checked: prfChip.isOn
        CalicataLiquidGlass {
            dark: root.darkMode; accent: root.cGenBlue; danger: root.flow ? root.flow.theme.error : "#D9483B"
            anchors.fill: parent
            radius: prfChip.radius
            tone: prfChip.isOn ? "tinted" : "glass"
            selected: prfChip.isOn
            pressed: prfChipTap.pressed
        }
        Text {
            id: prfChipText
            anchors.centerIn: parent
            text: prfChip.label + (prfChip.isOn ? "  ×" : "")
            color: prfChip.isOn ? root.cGenBlue : root.cText
            font.pixelSize: root.fsLabel
            font.weight: prfChip.isOn ? Font.DemiBold : Font.Normal
        }
        MouseArea {
            id: prfChipTap
            anchors.fill: parent
            onClicked: prfChip.flipped()
        }
    }

    component PrfToolButton: Button {
        id: prfTool
        property string iconName: ""
        property bool primaryTone: false
        property bool iconOnly: false
        implicitHeight: root.dp(40)
        leftPadding: root.dp(prfTool.iconOnly ? 10 : 12)
        rightPadding: root.dp(prfTool.iconOnly ? 10 : 14)
        topPadding: 0
        bottomPadding: 0
        focusPolicy: Qt.NoFocus
        Accessible.name: prfTool.text
        background: CalicataLiquidGlass {
            dark: root.darkMode; accent: root.cGenBlue; danger: root.flow ? root.flow.theme.error : "#D9483B"
            radius: prfTool.iconOnly ? height / 2 : root.dp(12)
            tone: prfTool.primaryTone || prfTool.checked ? "tinted" : "glass"
            selected: prfTool.checked
            pressed: prfTool.down
            enabledLook: prfTool.enabled
        }
        contentItem: Item {
            implicitWidth: prfToolRow.implicitWidth
            implicitHeight: prfToolRow.implicitHeight
            Row {
                id: prfToolRow
                anchors.centerIn: parent
                spacing: root.dp(6)
                Components.FlowIcon {
                    anchors.verticalCenter: parent.verticalCenter
                    width: root.dp(17)
                    height: root.dp(17)
                    name: prfTool.iconName
                    flow: root.flow
                    tintColor: prfToolLabel.color
                    activeTintColor: prfToolLabel.color
                    inactiveOpacity: 1
                }
                Text {
                    id: prfToolLabel
                    anchors.verticalCenter: parent.verticalCenter
                    visible: !prfTool.iconOnly
                    text: prfTool.text
                    color: prfTool.primaryTone || prfTool.checked ? root.cGenBlue : root.cText
                    font.pixelSize: root.fsLabel + 1
                    font.weight: prfTool.primaryTone ? Font.DemiBold : Font.Normal
                }
            }
        }
    }

    // Área de texto con contador (descripción, observaciones, interpretación).
    component PrfTextArea: Rectangle {
        id: prfArea
        property string label: ""   // presence: nombre legible del campo
        property string modelText: ""
        property int maxLength: 500
        property string placeholder: ""
        property real minHeight: root.dp(96)
        // Alto manual (asa inferior); nunca menor que el texto escrito.
        property real manualHeight: -1
        property real maxHeight: Math.max(prfArea.minHeight, root.height * (root.isPhone ? 0.55 : 0.7))
        property var onCommit: null   // function(text)
        readonly property real naturalHeight: Math.max(prfArea.minHeight, prfAreaEdit.contentHeight + root.dp(44))
        Layout.fillWidth: true
        implicitHeight: prfArea.manualHeight > 0
                        ? Math.max(prfArea.naturalHeight, Math.min(prfArea.manualHeight, prfArea.maxHeight))
                        : prfArea.naturalHeight
        radius: root.dp(12)
        color: "transparent"
        CalicataLiquidGlass { dark: root.darkMode; accent: root.cGenBlue; danger: root.flow ? root.flow.theme.error : "#D9483B"; anchors.fill: parent; radius: prfArea.radius; focused: prfAreaEdit.activeFocus }
        TextArea {
            id: prfAreaEdit
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.bottom: prfAreaCount.top
            anchors.margins: root.dp(10)
            wrapMode: TextEdit.Wrap
            placeholderText: prfArea.placeholder
            placeholderTextColor: root.cMuted
            color: root.cText
            font.pixelSize: root.fsLabel + 1
            padding: 0
            background: Item {}
            Binding {
                target: prfAreaEdit
                property: "text"
                value: prfArea.modelText
                when: !prfAreaEdit.activeFocus && !root._loading
                restoreMode: Binding.RestoreNone
            }
            onTextChanged: {
                if (root._loading || !activeFocus) return
                if (text.length > prfArea.maxLength) {
                    var position = Math.min(cursorPosition, prfArea.maxLength)
                    text = text.substring(0, prfArea.maxLength)
                    cursorPosition = position
                    return
                }
                if (prfArea.onCommit) prfArea.onCommit(text)
            }
        }
        PrfResizeGrip {
            id: prfAreaGrip
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            targetItem: prfArea
            minHeight: prfArea.minHeight
            maxHeight: prfArea.maxHeight
        }
        Text {
            id: prfAreaCount
            anchors.right: prfAreaGrip.left
            anchors.bottom: parent.bottom
            anchors.margins: root.dp(8)
            text: prfAreaEdit.length + " / " + prfArea.maxLength
            color: root.cMuted
            font.pixelSize: root.sp(11)
        }
    }

    // Fila de resumen (icono, etiqueta, valor).
    component PrfStatRow: RowLayout {
        id: prfStat
        property string iconName: ""
        property string label: ""
        property string value: ""
        Layout.fillWidth: true
        spacing: root.dp(10)
        Components.FlowIcon {
            Layout.preferredWidth: root.dp(18)
            Layout.preferredHeight: root.dp(18)
            name: prfStat.iconName
            flow: root.flow
            tintColor: root.cMuted
            activeTintColor: root.cMuted
            inactiveOpacity: 1
        }
        Text {
            Layout.fillWidth: true
            text: prfStat.label
            color: root.cMuted
            font.pixelSize: root.fsLabel
            elide: Text.ElideRight
        }
        Text {
            text: prfStat.value
            color: root.cText
            font.pixelSize: root.fsLabel + 1
            font.weight: Font.DemiBold
        }
    }

    // Número del estrato sobre su color.
    component PrfStratumBadge: Rectangle {
        id: prfBadge
        property int number: 0
        property color tone: "#E7E7E4"
        radius: root.dp(9)
        color: prfBadge.tone
        border.width: 1
        border.color: Qt.rgba(0, 0, 0, 0.08)
        Text {
            anchors.centerIn: parent
            text: prfBadge.number
            color: root.prfInkOn(prfBadge.tone)
            font.pixelSize: root.sp(13)
            font.bold: true
        }
    }

    // Símbolo del estrato: capas SUCS del laboratorio (qrc:/SUCS/web, = Web) sobre su color.
    component PrfStratumSymbol: Rectangle {
        id: prfSymbol
        property color tone: "#E7E7E4"
        property var files: []
        radius: root.dp(6)
        color: Qt.rgba(prfSymbol.tone.r, prfSymbol.tone.g, prfSymbol.tone.b, 0.6)
        border.width: 1
        border.color: root.cText
        clip: true
        Row {
            anchors.fill: parent
            anchors.margins: 1
            Repeater {
                model: prfSymbol.files
                delegate: Image {
                    required property string modelData
                    width: parent ? parent.width / Math.max(1, prfSymbol.files.length) : 0
                    height: parent ? parent.height : 0
                    source: modelData
                    fillMode: Image.Tile
                    // Web: background-size 24px por capa (resolveCalicataSucsPattern).
                    sourceSize.width: root.dp(24)
                    sourceSize.height: root.dp(24)
                    cache: true
                }
            }
        }
        Text {
            anchors.centerIn: parent
            visible: prfSymbol.files.length === 0
            text: "?"
            color: root.cMuted
            font.pixelSize: root.sp(13)
        }
    }

    // Acciones por fila: menú (⋮) o flechas en modo Reordenar.
    component PrfRowActions: Row {
        id: prfRowActions
        property int rowIdx: -1
        spacing: root.dp(4)
        MobileIconButton {
            visible: root.prfReorderMode
            iconName: "system.up"
            enabled: prfRowActions.rowIdx > 0
            Accessible.name: "Subir estrato " + (prfRowActions.rowIdx + 1)
            onClicked: root.moveCorteUp(prfRowActions.rowIdx)
        }
        MobileIconButton {
            visible: root.prfReorderMode
            iconName: "system.up"
            iconRotation: 180
            enabled: prfRowActions.rowIdx < cortesModel.count - 1
            Accessible.name: "Bajar estrato " + (prfRowActions.rowIdx + 1)
            onClicked: root.moveCorteDown(prfRowActions.rowIdx)
        }
        GenRoundIconButton {
            visible: !root.prfReorderMode
            width: root.dp(40)
            height: root.dp(40)
            iconName: "action.more"
            Accessible.name: "Acciones del estrato " + (prfRowActions.rowIdx + 1)
            onClicked: stratumActionsPopup.openFor(prfRowActions.rowIdx)
        }
    }

    component MobileReadOnlyField: ColumnLayout {
        id: readOnlyField
        property string fieldLabel: ""
        property string fieldText: ""
        property int maximumLineCount: 1
        spacing: root.dp(4)

        Text {
            Layout.fillWidth: true
            text: readOnlyField.fieldLabel
            color: root.cMuted
            font.pixelSize: root.fsLabel
            elide: Text.ElideRight
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: readOnlyField.maximumLineCount > 1
                                    ? Math.max(root.hField,
                                               root.fsField * 1.35
                                               * readOnlyField.maximumLineCount
                                               + root.dp(16))
                                    : root.hField
            radius: root.rField
            color: "transparent"
            clip: true

            CalicataLiquidGlass { dark: root.darkMode; accent: root.cGenBlue; danger: root.flow ? root.flow.theme.error : "#D9483B"; anchors.fill: parent; radius: parent.radius }

            Text {
                id: fieldValue
                anchors.fill: parent
                anchors.leftMargin: root.dp(12)
                anchors.rightMargin: root.dp(12)
                anchors.topMargin: readOnlyField.maximumLineCount > 1 ? root.dp(8) : 0
                anchors.bottomMargin: readOnlyField.maximumLineCount > 1 ? root.dp(8) : 0
                text: readOnlyField.fieldText.length ? readOnlyField.fieldText : "—"
                color: readOnlyField.fieldText.length ? root.cText : root.cMuted
                font.pixelSize: root.fsField
                wrapMode: readOnlyField.maximumLineCount > 1 ? Text.WordWrap : Text.NoWrap
                maximumLineCount: readOnlyField.maximumLineCount
                elide: Text.ElideRight
                verticalAlignment: Text.AlignVCenter
                clip: true
            }
        }
    }

    component MobileIconButton: ToolButton {
        id: mobileIconButton
        property string iconName: "action.edit"
        property bool danger: false
        property real iconRotation: 0
        implicitWidth: root.dp(44)
        implicitHeight: root.dp(44)
        padding: root.dp(8)

        scale: mobileIconButton.down ? 0.94 : 1
        Behavior on scale { NumberAnimation { duration: mobileIconButton.down ? 70 : 170; easing.type: Easing.OutCubic } }
        background: CalicataLiquidGlass {
            dark: root.darkMode; accent: root.cGenBlue; danger: root.flow ? root.flow.theme.error : "#D9483B"
            radius: root.dp(12)
            tone: mobileIconButton.danger ? "danger" : "glass"
            pressed: mobileIconButton.down
            enabledLook: mobileIconButton.enabled
        }

        contentItem: Components.FlowIcon {
            name: mobileIconButton.iconName
            flow: root.flow
            pressed: mobileIconButton.down
            tintColor: mobileIconButton.danger ? "#B4232E" : root.cAccent
            activeTintColor: mobileIconButton.danger ? "#B4232E" : root.cAccent
            inactiveOpacity: 1.0
            rotation: mobileIconButton.iconRotation
        }
    }

    // Acción táctil de fotografía compatible con el Flickable principal.
    // TapHandler mantiene un agarre pasivo: un toque ejecuta la acción,
    // mientras un desplazamiento vertical se entrega al scroll de la ficha.
    component MobilePhotoActionTile: Rectangle {
        id: photoActionTile
        property string actionText: ""
        property url iconSource: ""
        property bool accentBorder: false
        signal triggered()

        Layout.fillWidth: true
        Layout.preferredHeight: root.hField
        enabled: !root._photoRequestPending
        opacity: enabled ? 1.0 : 0.5
        Accessible.role: Accessible.Button
        Accessible.name: actionText
        Accessible.onPressAction: { if (enabled) triggered() }
        radius: root.dp(12)
        color: "transparent"

        CalicataLiquidGlass {
            dark: root.darkMode; accent: root.cGenBlue; danger: root.flow ? root.flow.theme.error : "#D9483B"
            anchors.fill: parent
            radius: photoActionTile.radius
            tone: photoActionTile.accentBorder ? "tinted" : "glass"
            pressed: photoTapHandler.pressed
        }

        FlowCore.FlowRipple {
            id: photoActionRipple
            flow: root.flow
            enabled: !!root.flow && root.flow.motionAllowed
            cornerRadius: photoActionTile.radius
            rippleColor: root.darkMode
                         ? Qt.rgba(0.15, 0.73, 0.86, 0.22)
                         : Qt.rgba(0.04, 0.45, 0.92, 0.16)
        }

        RowLayout {
            anchors.fill: parent
            spacing: root.dp(4)

            Item { Layout.fillWidth: true }

            Components.FlowIcon {
                Layout.alignment: Qt.AlignVCenter
                Layout.preferredWidth: root.dp(20)
                Layout.preferredHeight: root.dp(20)
                sourceOverride: photoActionTile.iconSource
                flow: root.flow
                pressed: photoTapHandler.pressed
                tintEnabled: false
            }

            Text {
                Layout.alignment: Qt.AlignVCenter
                text: photoActionTile.actionText
                color: root.cAccent
                font.bold: true
                font.pixelSize: root.fsLabel
            }

            Item { Layout.fillWidth: true }
        }

        TapHandler {
            id: photoTapHandler
            acceptedButtons: Qt.LeftButton
            gesturePolicy: TapHandler.DragThreshold

            onPressedChanged: {
                if (pressed) {
                    photoActionRipple.trigger(point.position.x,
                                               point.position.y)
                }
            }

            onTapped: photoActionTile.triggered()
        }
    }




    // =========================
    // CORTES (modelo)
    // =========================
    ListModel { id: cortesModel }

    function addCorte() {
        if (cortesModel.count > 0) {
            var last = cortesModel.get(cortesModel.count - 1)
            var aRaw = ((last.a || "") + "").trim()
            var aVal = _parseDepthText(aRaw)

            if (!aRaw.length || isNaN(aVal)) {
                showInfo("Falta completar intervalo",
                         "Primero escribe el valor 'A' del último corte antes de agregar uno nuevo.")
                return
            }

            var rows = []
            for (var i = 0; i < cortesModel.count; ++i) rows.push(cortesModel.get(i))
            var error = Rules.boundaryError(rows, rows.length - 1, aRaw, root.allowedDepthM)
            if (error) {
                showInfo("Intervalo inválido", error)
                return
            }

            if (isFinite(root.allowedDepthM) && aVal >= root.allowedDepthM - 0.000001) {
                showInfo("Profundidad total", "Ya llegaste a la profundidad total. Amplíala antes de añadir otro estrato.")
                return
            }

        }

        cortesModel.append({
            id: "stratum-" + Date.now() + "-" + Math.random().toString(36).slice(2),
            material_origin: "",
            _extraJson: JSON.stringify({ local_stratum_id: root._newLabUuid() }),
            _percentageFieldsJson: "[]",
            remote_sample_id: "",
            sample_code: "",
            descripcion: "",
            humedad: -1,
            excavabilidad: -1,
            estabilidad: -1,
            tipoText: "",
            tipo_muestra: "",
            tipo_otro: "",

            de: "",      // ✅ lo calcula renumerarCortesYIntervalos
            a:  "",      // ✅ lo escribe el usuario
            muestra_desde: "",
            muestra_hasta: "",
            resultados: "",

            aashto: "",
            sucs: "",
            gmax: "",
            g2: "",
            g04: "",
            g008: "",
            g002: "",
            wl: "",
            lp: "",
            hum2: ""
        })

        renumerarCortesYIntervalos(true)
    }


    function removeCorte(i) {
        if (!commitPendingField()) return
        if (i < 0 || i >= cortesModel.count) return
        if (cortesModel.count <= 1) { showInfo("Estratos", "La ficha debe conservar al menos un estrato."); return }
        var remoteIdentity = JSON.parse(cortesModel.get(i)._extraJson || "{}").remote_stratum_id
        if (remoteIdentity && doc && doc.closed !== true) {
            // P3: lápida persistente; la próxima sincronización lo borra en la
            // nube por UUID con CAS (delete_my_calicata_stratum_v02), también offline.
            root._markDirty()
            var h = Object.assign({}, doc.header || {})
            var tombstones = (h.deleted_remote_strata || []).slice()
            if (tombstones.indexOf(remoteIdentity) < 0) tombstones.push(remoteIdentity)
            h.deleted_remote_strata = tombstones
            doc.header = h
        }
        cortesModel.remove(i)
        selectedStratum = Math.min(selectedStratum, cortesModel.count - 1)
        if (i < cortesModel.count)
            cortesModel.setProperty(i, "de", i > 0 ? cortesModel.get(i - 1).a : "0.00")
        if (!cortesModel.count) finishStratum()
        root._markDirty()

        renumerarCortesYIntervalos(true)
    }



    function ensureCortesPrehechos(n) {
        while (cortesModel.count < n)
            addCorte()
    }


    // ✅ Doc real (1 por pestaña)
    property var doc: null   // CalicataDocument (lo dejamos var para no pelear con el tipo)

    // Selector de proyecto (Ficha > General). La selección se confirma con
    // "Seleccionar" y ejecuta exactamente el mismo flujo que el tap directo previo.
    property string _pendingProjectId: ""
    property var _pendingProject: null

    // Nombre visible del proyecto asignado. Si la ficha solo guarda el id
    // (projectName vacío), se resuelve con la lista real de proyectos.
    function _projectDisplayName() {
        if (!root.doc || !root.doc.header.projectId) return "Proyecto sin asignar"
        var h = root.doc.header
        var name = String(h.projectName || "")
        if (name.length) return name
        var list = typeof CalicataCloud !== "undefined" ? (CalicataCloud.projects || []) : []
        for (var i = 0; i < list.length; ++i)
            if (String(list[i].id || "") === String(h.projectId))
                return String(list[i].name || list[i].code || "")
        return String(h.projectCode || "Proyecto asignado")
    }

    function _openProjectPicker() {
        if (!root.commitPendingField() || !root.doc) return
        root.flushRequested()
        if (!root.doc.saveDraft()) {
            root.showInfo("No se pudo guardar", root.doc.errorString)
            return
        }
        Qt.inputMethod.hide()
        projectPickerPopup.open()
        CalicataCloud.refreshProjects()
    }

    function _filteredProjects(projects, query) {
        var list = projects || []
        var q = String(query || "").trim().toLowerCase()
        if (!q.length) return list
        var out = []
        for (var i = 0; i < list.length; ++i) {
            var p = list[i]
            if ((String(p.code || "") + " " + String(p.name || "")).toLowerCase().indexOf(q) >= 0)
                out.push(p)
        }
        return out
    }

    function _applyProjectSelection(project) {
        if (!root.doc || !project) return
        var selection = {
            projectId: String(project.id || ""),
            projectCode: String(project.code || ""),
            projectName: String(project.name || "")
        }
        if (!root.doc.selectProject(selection)) {
            root.showInfo("No se pudo seleccionar el proyecto", root.doc.errorString)
            return
        }
        if (root.operationHost)
            root._projectOperationId = root.operationHost.beginOperation("PROJECT_LOAD",
                "Cargando proyecto…", "Recuperando fichas y archivos",
                { retry: function() { CalicataCloud.resolveProjectWorkspace(selection.projectId) } })
        CalicataCloud.resolveProjectWorkspace(selection.projectId)
        // Project mirror for the fast UNIQUE(project_id, code) check.
        CalicataCloud.listProjectCalicatas(selection.projectId)
        projectPickerPopup.close()
        root.importFromDoc()
    }

    GenPopup {
        id: projectPickerPopup
        preferredWidth: root.dp(520)
        onAboutToShow: {
            projectSearchField.text = ""
            root._pendingProjectId = root.doc ? String(root.doc.header.projectId || "") : ""
            root._pendingProject = null
        }

        contentItem: ColumnLayout {
            spacing: root.dp(12)
            GenDialogHeader {
                title: "Seleccionar proyecto"
                onCloseRequested: projectPickerPopup.close()
            }
            GenSearchField {
                id: projectSearchField
                placeholderText: "Buscar proyecto…"
            }
            Text {
                Layout.fillWidth: true
                visible: CalicataCloud.busy && CalicataCloud.projects.length === 0
                text: "Cargando proyectos…"
                color: root.cMuted
            }
            ListView {
                id: projectPickerList
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                spacing: root.dp(2)
                boundsBehavior: Flickable.StopAtBounds
                model: root._filteredProjects(CalicataCloud.projects, projectSearchField.text)
                delegate: GenChoiceRow {
                    required property var modelData
                    width: ListView.view.width
                    title: String(modelData.name || "") || String(modelData.code || "")
                    detail: String(modelData.code || "")
                    iconName: "calgen.project"
                    selected: String(modelData.id || "") === root._pendingProjectId
                    onPicked: {
                        root._pendingProjectId = String(modelData.id || "")
                        root._pendingProject = modelData
                    }
                }
            }
            Text {
                Layout.fillWidth: true
                visible: !CalicataCloud.busy && CalicataCloud.projects.length === 0
                text: "No hay proyectos disponibles para esta cuenta."
                color: root.cMuted
                wrapMode: Text.WordWrap
            }
            Text {
                Layout.fillWidth: true
                visible: CalicataCloud.projects.length > 0 && projectPickerList.count === 0
                text: "Ningún proyecto coincide con la búsqueda."
                color: root.cMuted
                wrapMode: Text.WordWrap
            }
            RowLayout {
                Layout.fillWidth: true
                spacing: root.dp(10)
                GenDialogButton {
                    text: "Cancelar"
                    onClicked: projectPickerPopup.close()
                }
                GenDialogButton {
                    text: "Seleccionar"
                    primary: true
                    enabled: root._pendingProject !== null
                    onClicked: root._applyProjectSelection(root._pendingProject)
                }
            }
        }
    }

    // Selector de maquinaria (Ficha > General). Mismo modelo y mismo commit
    // que el ComboBox previo: índice 0 limpia, catálogo escribe, histórico se conserva.
    property int _pendingMachineIndex: 0

    function _openMachinePicker() {
        if (!root.commitPendingField()) return
        Qt.inputMethod.hide()
        machinePickerPopup.open()
    }

    function _machineChoices(query) {
        var q = String(query || "").trim().toLowerCase()
        var out = []
        for (var i = 0; i < root.machineModel.length; ++i) {
            var label = String(root.machineModel[i])
            if (!q.length || label.toLowerCase().indexOf(q) >= 0)
                out.push({ index: i, label: label })
        }
        return out
    }

    function _commitMachineIndex(i) {
        if (i <= 0) txtMaquina.text = ""
        else if (i <= Rules.MACHINE_OPTIONS.length) txtMaquina.text = Rules.MACHINE_OPTIONS[i - 1]
        // El histórico se conserva tal cual.
        root._markDirty()
    }

    GenPopup {
        id: machinePickerPopup
        preferredHeight: root.dp(640)
        onAboutToShow: {
            machineSearchField.text = ""
            root._pendingMachineIndex = root._catalogIndex(txtMaquina.text, Rules.MACHINE_OPTIONS, root.machineHistorical)
        }

        contentItem: ColumnLayout {
            spacing: root.dp(12)
            GenDialogHeader {
                title: "Seleccionar maquinaria"
                onCloseRequested: machinePickerPopup.close()
            }
            GenSearchField {
                id: machineSearchField
                placeholderText: "Buscar maquinaria…"
            }
            ListView {
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                spacing: root.dp(2)
                boundsBehavior: Flickable.StopAtBounds
                model: root._machineChoices(machineSearchField.text)
                delegate: GenChoiceRow {
                    required property var modelData
                    width: ListView.view.width
                    title: modelData.label
                    iconName: modelData.index === 0 ? "calgen.clear" : "calgen.machine"
                    accent: root.cGenTeal
                    accentSoft: root.cGenTealSoft
                    selected: modelData.index === root._pendingMachineIndex
                    onPicked: root._pendingMachineIndex = modelData.index
                }
            }
            RowLayout {
                Layout.fillWidth: true
                spacing: root.dp(10)
                GenDialogButton {
                    text: "Cancelar"
                    onClicked: machinePickerPopup.close()
                }
                GenDialogButton {
                    text: "Seleccionar"
                    primary: true
                    accent: root.cGenTeal
                    onClicked: {
                        root._commitMachineIndex(root._pendingMachineIndex)
                        machinePickerPopup.close()
                    }
                }
            }
        }
    }

    // Selector de opciones de Ubicación (Datum / Lado de la vía): mismo ADN que
    // maquinaria. `commit(index)` aplica exactamente el contrato del combo previo
    // (índice 0 = sin valor); el histórico, si existe, va como última opción.
    property int _pendingOptionIndex: 0
    property var _optionCommit: null

    function _openOptionPicker(title, options, currentIndex, iconName, accent, accentSoft, commit) {
        if (!root.commitPendingField()) return
        Qt.inputMethod.hide()
        optionPickerPopup.titleText = title
        optionPickerPopup.options = options
        optionPickerPopup.optionIcon = iconName
        optionPickerPopup.accentColor = accent
        optionPickerPopup.accentSoftColor = accentSoft
        root._pendingOptionIndex = currentIndex
        root._optionCommit = commit
        optionPickerPopup.open()
    }

    GenPopup {
        id: optionPickerPopup
        property string titleText: ""
        property var options: []
        property string optionIcon: "calgen.code"
        property color accentColor: root.cGenBlue
        property color accentSoftColor: root.cGenBlueSoft
        preferredHeight: root.dp(56) * options.length + root.dp(150)

        contentItem: ColumnLayout {
            spacing: root.dp(12)
            GenDialogHeader {
                title: optionPickerPopup.titleText
                onCloseRequested: optionPickerPopup.close()
            }
            ListView {
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                spacing: root.dp(2)
                boundsBehavior: Flickable.StopAtBounds
                model: optionPickerPopup.options
                delegate: GenChoiceRow {
                    required property var modelData
                    required property int index
                    width: ListView.view.width
                    title: String(modelData)
                    iconName: index === 0 ? "calgen.clear" : optionPickerPopup.optionIcon
                    accent: optionPickerPopup.accentColor
                    accentSoft: optionPickerPopup.accentSoftColor
                    selected: index === root._pendingOptionIndex
                    onPicked: root._pendingOptionIndex = index
                }
            }
            RowLayout {
                Layout.fillWidth: true
                spacing: root.dp(10)
                GenDialogButton {
                    text: "Cancelar"
                    onClicked: optionPickerPopup.close()
                }
                GenDialogButton {
                    text: "Seleccionar"
                    primary: true
                    accent: optionPickerPopup.accentColor
                    onClicked: {
                        var commit = root._optionCommit
                        var index = root._pendingOptionIndex
                        optionPickerPopup.close()
                        if (commit) commit(index)
                    }
                }
            }
        }
    }

    // ===== Perfil: emergentes (mismo GenPopup de General/Ubicación) =====
    GenPopup {
        id: stratumActionsPopup
        property int corteIdx: -1
        preferredWidth: root.dp(400)
        preferredHeight: root.dp(470)
        function openFor(index) {
            if (index < 0 || index >= cortesModel.count || !root.commitPendingField()) return
            Qt.inputMethod.hide()
            corteIdx = index
            open()
        }
        function run(action) {
            var index = corteIdx
            close()
            action(index)
        }
        contentItem: ColumnLayout {
            spacing: root.dp(8)
            GenDialogHeader {
                title: "Estrato " + (stratumActionsPopup.corteIdx + 1)
                subtitle: stratumActionsPopup.corteIdx >= 0 && stratumActionsPopup.corteIdx < cortesModel.count
                          ? String(cortesModel.get(stratumActionsPopup.corteIdx).de || "—") + " – "
                            + String(cortesModel.get(stratumActionsPopup.corteIdx).a || "—") + " m" : ""
                onCloseRequested: stratumActionsPopup.close()
            }
            GenDialogButton {
                text: "Editar detalle"
                iconName: "action.edit"
                onClicked: stratumActionsPopup.run(function(i) { root.selectStratum(i, "field") })
            }
            RowLayout {
                Layout.fillWidth: true
                spacing: root.dp(8)
                GenDialogButton {
                    text: "Subir ↑"
                    enabled: stratumActionsPopup.corteIdx > 0
                    onClicked: stratumActionsPopup.run(function(i) { root.moveCorteUp(i) })
                }
                GenDialogButton {
                    text: "Bajar ↓"
                    enabled: stratumActionsPopup.corteIdx >= 0 && stratumActionsPopup.corteIdx < cortesModel.count - 1
                    onClicked: stratumActionsPopup.run(function(i) { root.moveCorteDown(i) })
                }
            }
            GenDialogButton {
                text: "Insertar debajo (dividir)"
                iconName: "action.add"
                onClicked: stratumActionsPopup.run(function(i) { root.insertStratumBelow(i) })
            }
            GenDialogButton {
                text: "Duplicar descripción"
                iconName: "action.copy"
                onClicked: stratumActionsPopup.run(function(i) { root.duplicateStratum(i) })
            }
            GenDialogButton {
                text: "Eliminar estrato"
                iconName: "action.delete"
                soft: true
                accent: root.flow ? root.flow.theme.error : "#B4232E"
                accentSoft: root.darkMode ? "#3A1E1E" : "#FDECEC"
                onClicked: stratumActionsPopup.run(function(i) { root.requestDeleteStratum(i) })
            }
            Item { Layout.fillHeight: true }
        }
    }

    GenPopup {
        id: prfTemplatePopup
        property string pendingKey: ""
        preferredWidth: root.dp(480)
        preferredHeight: root.dp(560)
        function openPicker() {
            if (!root.commitPendingField()) return
            Qt.inputMethod.hide()
            pendingKey = root.profileSetupText("template") || "vacia"
            open()
        }
        contentItem: ColumnLayout {
            spacing: root.dp(12)
            GenDialogHeader {
                title: "Plantillas globales"
                subtitle: "Preconfiguran método y contexto del relleno"
                onCloseRequested: prfTemplatePopup.close()
            }
            ListView {
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                spacing: root.dp(2)
                boundsBehavior: Flickable.StopAtBounds
                model: root.prfTemplates
                delegate: GenChoiceRow {
                    required property var modelData
                    width: ListView.view.width
                    title: modelData.title
                    detail: modelData.detail
                    iconName: modelData.key === "vacia" ? "documents.file" : root.iconStrataName
                    selected: prfTemplatePopup.pendingKey === modelData.key
                    onPicked: prfTemplatePopup.pendingKey = modelData.key
                }
            }
            RowLayout {
                Layout.fillWidth: true
                spacing: root.dp(10)
                GenDialogButton {
                    text: "Cancelar"
                    onClicked: prfTemplatePopup.close()
                }
                GenDialogButton {
                    text: cortesModel.count ? "Aplicar" : "Aplicar y crear estrato"
                    primary: true
                    onClicked: {
                        var key = prfTemplatePopup.pendingKey
                        prfTemplatePopup.close()
                        root.applyProfileTemplate(key, true)
                    }
                }
            }
        }
    }

    GenPopup {
        id: prfGraphPopup
        preferredWidth: root.dp(560)
        preferredHeight: root.dp(900)
        contentItem: ColumnLayout {
            spacing: root.dp(12)
            GenDialogHeader {
                title: "Vista del perfil"
                subtitle: root.prfGraphDepth.toFixed(2) + " m · " + cortesModel.count
                          + (cortesModel.count === 1 ? " estrato" : " estratos")
                onCloseRequested: prfGraphPopup.close()
            }
            CalicataProfile {
                Layout.fillWidth: true
                Layout.fillHeight: true
                model: cortesModel
                bandInfo: root.stratumBandInfo
                selectedIndex: root.selectedStratum
                totalDepth: root.prfGraphDepth
                waterDepth: root.prfWaterDepth
                showWater: root.profileSetup.show_water_table !== false
                scaleFactor: root.uiScale
                ink: root.cText
                muted: root.cMuted
                gridColor: root.cBorder
                accent: root.cGenBlue
                waterColor: root.cGenBlue
                paper: Qt.rgba(root.cSurface.r, root.cSurface.g, root.cSurface.b, root.darkMode ? 0.18 : 0.40)   // papel del gráfico sobre el vidrio de la tarjeta
                onSelected: function(index) {
                    prfGraphPopup.close()
                    root.selectStratum(index, "field")
                }
            }
        }
    }

    // ===== Altitud / Cota Z: servicio de elevación del backend =====
    // La app NO consulta proveedores: pide la cota a la Edge Function
    // resolve-calicata-elevation (evidencias geoespaciales + validación Gemini)
    // y decide qué mostrar con CalicataElevation.js. Prioridad: Z manual >
    // servicio de elevación > GPS (elipsoidal) > vacío. Nunca bloquea: 25 s de
    // espera máxima y la Z siempre se puede escribir a mano.
    property int _elevationSerial: 0
    property string _elevationRequestId: ""
    property var _elevationContext: null
    property bool elevationBusy: false
    property string elevationStatus: ""
    property string elevationWarning: ""
    property var _pendingAltitudeDecision: null
    Timer {
        id: elevationWatchdog
        interval: 25000
        repeat: false
        onTriggered: root._finishElevation(root._elevationRequestId,
                                           { ok: false, error: "El servicio de altitud no respondió. Ingresa la cota manualmente." })
    }
    Connections {
        target: typeof CalicataCloud !== "undefined" ? CalicataCloud : null
        ignoreUnknownSignals: true
        function onElevationResolved(requestId, result) { root._finishElevation(requestId, result) }
    }
    // trigger: "explicit" (Obtener altitud) | "location" (Mi ubicación / punto confirmado).
    // deviceAltitude: altura GPS del fix (NaN si no hay); evidencia y respaldo elipsoidal.
    function resolveAltitude(trigger, deviceAltitude, deviceAccuracy) {
        if (!doc || doc.closed === true) return false
        var point = root._locationPoint()
        if (!Elevation.validCoordinate(point.lat, point.lon)) {
            root.elevationStatus = "Primero registra coordenadas válidas."
            return false
        }
        // Automático sobre una Z manual: no se consulta ni se pregunta (solo "Obtener altitud").
        if (trigger !== "explicit" && !Elevation.autoWriteAllowed(doc.header)) {
            root.elevationStatus = "Cota manual conservada. Pulsa Obtener altitud para compararla o reemplazarla."
            return false
        }
        var requestId = "elev-" + (++root._elevationSerial) + "-" + Date.now()
        var body = Elevation.requestBody(doc.header, point, deviceAltitude, deviceAccuracy)
        root._elevationRequestId = requestId
        root._elevationContext = { trigger: trigger, docId: _docInstanceId(doc), deviceAltitude: deviceAltitude,
                                   key: point.lat.toFixed(6) + "," + point.lon.toFixed(6) }
        root.elevationBusy = true
        root.elevationWarning = ""
        root.elevationStatus = "Consultando la elevación del terreno…"
        console.info("INGE_ELEVATION_REQUEST trigger=" + trigger)
        if (typeof CalicataCloud === "undefined" || !CalicataCloud.resolveElevation(requestId, body)) {
            root._finishElevation(requestId, { ok: false, error: "Inicia sesión para obtener la altitud automática." })
            return false
        }
        elevationWatchdog.restart()
        return true
    }
    function _finishElevation(requestId, result) {
        if (!requestId.length || requestId !== root._elevationRequestId) return   // respuesta vieja
        root._elevationRequestId = ""
        elevationWatchdog.stop()
        root.elevationBusy = false
        var context = root._elevationContext || {}
        if (!doc || doc.closed === true || _docInstanceId(doc) !== context.docId) return
        var current = root._locationPoint()
        if (!Elevation.validCoordinate(current.lat, current.lon)
                || current.lat.toFixed(6) + "," + current.lon.toFixed(6) !== context.key) {
            root.elevationStatus = "La ubicación cambió; vuelve a obtener la altitud."
            return
        }
        var h = doc.header || {}
        // El técnico pudo escribir Z mientras tanto: lo automático no la pisa.
        if (context.trigger !== "explicit" && !Elevation.autoWriteAllowed(h)) {
            root.elevationStatus = "Cota manual conservada. Pulsa Obtener altitud para compararla o reemplazarla."
            return
        }
        var decision = Elevation.outcome(result, h, context.trigger, context.deviceAltitude, new Date().toISOString())
        if (decision.action === "none") { root.elevationStatus = decision.message; return }
        if (decision.action === "confirm") {
            root._pendingAltitudeDecision = decision
            root.elevationWarning = decision.warning || ""
            altitudeReplaceDialog.open()
            return
        }
        root._applyAltitudePatch(decision.patch)
        root.elevationWarning = decision.warning || ""
        if (decision.message) root.elevationStatus = decision.message
    }
    function _applyAltitudePatch(patch) {
        if (!patch || !doc || doc.closed === true) return
        txtUTMZ.text = patch.utm_z
        var h = Object.assign({}, doc.header)
        for (var key in patch) h[key] = patch[key]
        doc.header = h
        var ts = Object.assign({}, doc.timestamp || {})
        ts.altitud = patch.utm_z
        doc.timestamp = ts
        root.elevationStatus = ""
        root._markDirty()
    }

    // Punto de la ficha en grados: lat/lon guardados o, si faltan y el datum
    // no es PSAD56, derivados de la UTM WGS84 (misma regla que el mapa previo).
    function _locationPoint() {
        var h = root.doc ? root.doc.header : {}
        var lat = Rules.parseDecimalSafe(h.latitude), lon = Rules.parseDecimalSafe(h.longitude)
        if (!isFinite(lat) || !isFinite(lon)) {
            // Fila cloud sin lat/lon: se derivan de las UTM en su datum (WGS84 por defecto).
            var fromUtm = Rules.utmToGeoForDatum(h.utm_x, h.utm_y, h.zona || h.utm_zone,
                                                 h.datum === "PSAD56" ? "PSAD56" : "WGS84")
            if (fromUtm) { lat = fromUtm.latitude; lon = fromUtm.longitude }
        }
        return { lat: lat, lon: lon }
    }

    function _openDatePicker(button, title) {
        if (!root.commitPendingField()) return
        Qt.inputMethod.hide()
        popFechaPicker.openFor(button, title)
    }

    Connections {
        target: CalicataCloud
        function onProjectsLoadFailed(message) {
            if (projectPickerPopup.opened)
                root.showInfo("No se pudieron cargar los proyectos", message)
        }
        function onWorkspaceResolveFailed(projectId, message) {
            if (!root.operationHost || !root._projectOperationId.length) return
            root.operationHost.endOperation(root._projectOperationId, "ERROR", { title: "No se pudo cargar el proyecto",
                detail: "El proyecto quedó seleccionado; reintenta cuando haya conexión.",
                actions: [{ id: "retry", label: "Reintentar" }, { id: "close", label: "Volver" }] })
            root._projectOperationId = ""
        }
        function onWorkspaceResolved(projectId, spaceId) {
            if (root.operationHost && root._projectOperationId.length) {
                root.operationHost.endOperation(root._projectOperationId, "OK")
                root._projectOperationId = ""
            }
            if (!root.doc || String(root.doc.header.projectId || "") !== String(projectId)) return
            var p = {
                projectId: String(root.doc.header.projectId || ""),
                projectCode: String(root.doc.header.projectCode || ""),
                projectName: String(root.doc.header.projectName || ""),
                spaceId: String(spaceId || "")
            }
            root.doc.selectProject(p)
        }
    }


    // helper (porque tu form todavía usa filePath string)
    function _fileUrlToAbs(u) {
        var s = (u || "").toString()
        if (!s.length) return ""
        if (s.startsWith("file:///"))
            return decodeURIComponent(s.substring(Qt.platform.os === "windows" ? 8 : 7))
        if (s.startsWith("file://"))  return decodeURIComponent(s.substring(7))
        return decodeURIComponent(s)
    }

    Component.onCompleted: {
        root._updateLayoutSize()
        _ready = true
        ensureDocsRoots()

        if (doc) {
            importFromDoc()
            Qt.callLater(root._recoverInterruptedCapture)
        } else {
            cortesModel.clear()
            renumerarCortesYIntervalos(false)
            // aquí también conviene limpiar fotos/obs si es "nuevo"
            observacionesText = ""
            setDirty(false)
        }

    }


    // Alto visible del “body” (como tu scrollArea de PC)
    readonly property int cortesViewportMinH: 220
    readonly property int cortesViewportMaxH: 420


    function _fmtDate(d) {
        return Qt.formatDate(d, dateFmt)
    }

    function _parseDMY(s) {
        if (!s || s.indexOf("/") === -1) return null
        var p = s.split("/")
        if (p.length !== 3) return null
        var dd = parseInt(p[0], 10)
        var mm = parseInt(p[1], 10) - 1
        var yy = parseInt(p[2], 10)
        if (isNaN(dd) || isNaN(mm) || isNaN(yy)) return null
        var dt = new Date(yy, mm, dd)
        // valida fecha real (evita 32/13/2025)
        if (dt.getFullYear() !== yy || dt.getMonth() !== mm || dt.getDate() !== dd) return null
        return dt
    }

    function _dateFromTextOrToday(s) {
        var d = _parseDMY(s)
        return d ? d : new Date()
    }


    function setDirty(v) {
        v = !!v
        if (dirty === v) return
        dirty = v
    }
    // ===================== Live field changes (contrato Web canónico) =====================
    // docs/CALICATAS_LIVE_COLLAB_V1.md. Eco local inmediato (la UI ya cambió);
    // cada campo CALICATA/STRATUM no-prose cambiado se envía a la RPC durable
    // apply_calicata_field_change_v02 y solo el cambio vigente que devuelve se
    // anuncia ("calicata-field-change", lo hace CalicataCloudService). Los campos
    // prose (Yjs "calicata-prose" en Web) no viajan en vivo desde Android.
    // La persistencia completa (autosave/Guardar/revisión) no cambia.
    property bool _applyingLivePatch: false
    property var _liveBaseline: null
    property var _livePendingState: null
    readonly property var liveCalicataFields: ["code", "title", "location", "progresiva", "easting", "northing",
        "altitude_m", "depth_m", "groundwater_depth_m", "utm_zone", "supervisor", "machine", "start_date",
        "end_date", "description", "observations"]
    readonly property var liveStratumFields: ["to_depth_m", "description", "moisture_condition",
        "consistency_compaction", "excavability", "color", "sample_type", "observations"]
    // Prose: edición simultánea real con Yjs en Web. Android no la implementa
    // todavía: nunca envía estos campos como cadena completa en vivo.
    readonly property var liveProseFields: ({ CALICATA: ["title", "description", "observations"],
                                              STRATUM: ["description", "observations"] })
    // LAB_RESULT (target.id = id del estrato): columna Android por campo del servidor.
    readonly property var liveLabColumns: ({ sieve_max_pct: "gmax", sieve_2mm_pct: "g2", sieve_04mm_pct: "g04",
                                             sieve_008mm_pct: "g008", liquid_limit: "wl", plastic_limit: "lp",
                                             natural_moisture_pct: "hum2" })
    function _liveLabFields(row) {
        // Mismos campos que Web (CalicataLaboratoryFormState -> calicata_lab_results):
        // la clasificación es la autoridad del laboratorio (primary/secondary/
        // is_composite/aashto). WL/LP son enteros: un decimal no viaja (y el
        // commit ya lo rechaza); nunca se redondea.
        function limit(v) { var t = root._liveValue(v); return t !== null && /.d*[1-9]/.test(t) ? undefined : t }
        var primary = String(row.primary_sucs || "").toUpperCase(), secondary = String(row.secondary_sucs || "").toUpperCase()
        return {
            sieve_max_pct: root._liveValue(row.gmax), sieve_no4_pct: root._liveValue(row.passing_no4),
            sieve_2mm_pct: root._liveValue(row.g2), sieve_04mm_pct: root._liveValue(row.g04),
            sieve_008mm_pct: root._liveValue(row.g008), liquid_limit: limit(row.wl),
            plastic_limit: limit(row.lp),
            natural_moisture_pct: root._liveValue(row.hum2),
            primary_sucs: primary.length ? primary : null,
            secondary_sucs: row.is_composite === true && secondary.length ? secondary : null,
            is_composite: row.is_composite === true ? "true" : "false",
            aashto: root._liveValue(row.lab_confirmed_aashto),
            laboratory_source: root._liveValue(row.laboratory_source),
            test_date: root._liveValue(row.test_date)
        }
    }
    readonly property var liveHumidity: ["SECO", "BAJO", "MEDIO", "AGUA"]
    readonly property var liveExcavability: ["RENDIMIENTO_BAJO", "RENDIMIENTO_MEDIO", "RENDIMIENTO_ALTO", "RENDIMIENTO_MUY_ALTO"]

    // Presence `field` (meta canónica Web): etiqueta legible de la celda en
    // edición ("Supervisor", "Corte 2, Descripción"); "" (-> null) si no hay.
    function _itemMember(object, name) { return object ? object[name] : undefined }
    function _presenceFieldLabel() {
        var item = root.Window.activeFocusItem
        if (!item || root._itemMember(item, "cursorPosition") === undefined) return ""
        var label = "", inside = false, inStratumEditor = false
        for (var node = item; node; node = node.parent) {
            var nodeLabel = root._itemMember(node, "label")
            if (!label.length && typeof nodeLabel === "string" && nodeLabel.length) label = nodeLabel
            if (node === prfEditorCard) inStratumEditor = true
            if (node === root) { inside = true; break }
        }
        if (!inside || !label.length) return ""
        label = label.replace(/\s*\((m|%)\)\s*$/, "")
        return inStratumEditor && root.selectedStratum >= 0
                ? "Corte " + (root.selectedStratum + 1) + ", " + label : label
    }
    function _liveStratumId(plain) {
        return String(plain.remote_stratum_id || plain.local_stratum_id || "")
    }
    // Valor canónico: texto o null (p_value es text).
    function _liveValue(value) {
        return value === undefined || value === null || String(value) === "" ? null : String(value)
    }
    function _liveIsProse(type, field) {
        return (root.liveProseFields[type] || []).indexOf(field) >= 0
    }
    function _liveSnapshot(state) {
        var h = (state && state.header) || {}
        var snap = { calicata: {}, strata: [] }
        for (var k = 0; k < root.liveCalicataFields.length; ++k) {
            var key = root.liveCalicataFields[k]
            snap.calicata[key] = root._liveValue(key === "observations" ? (state && state.observaciones) : h[key])
        }
        var cortes = (state && state.cortes) || []
        for (var i = 0; i < cortes.length; ++i) {
            var row = cortes[i]
            var hum = Number(row.humedad), exc = Number(row.excavabilidad)
            snap.strata.push({
                id: root._liveStratumId(row),
                remote: String(row.remote_stratum_id || ""),
                fields: {
                    to_depth_m: root._liveValue(row.a),
                    description: root._liveValue(row.descripcion),
                    moisture_condition: hum >= 0 && hum < root.liveHumidity.length ? root.liveHumidity[hum] : null,
                    consistency_compaction: root._liveValue(row.consistency_compaction),
                    excavability: exc >= 0 && exc < root.liveExcavability.length ? root.liveExcavability[exc] : null,
                    color: root._liveValue(row.color),
                    sample_type: root._liveValue(row.tipo_muestra),
                    observations: root._liveValue(row.observations)
                },
                lab: root._liveLabFields(row)
            })
        }
        return snap
    }
    function _queueLiveTx(state) {
        if (root._applyingLivePatch) return
        root._livePendingState = state
        liveTxDebounce.restart()
    }
    Timer {
        id: liveTxDebounce
        interval: 150   // agrupa commits seguidos; cada campo va una vez a la RPC
        repeat: false
        onTriggered: root._flushLiveTx()
    }
    function _flushLiveTx() {
        var state = root._livePendingState
        root._livePendingState = null
        if (!state || !root.doc) return
        var next = root._liveSnapshot(state), prev = root._liveBaseline
        root._liveBaseline = next
        if (!prev || typeof CalicataCloud === "undefined") return
        var calicataId = String(root.doc.header.remoteCalicataId || "")
        if (!calicataId.length) return
        for (var k in next.calicata) {
            if (next.calicata[k] === prev.calicata[k] || root._liveIsProse("CALICATA", k)) continue
            CalicataCloud.applyFieldChange(root.doc, "CALICATA", calicataId, k, next.calicata[k])
        }
        var before = {}
        for (var b = 0; b < prev.strata.length; ++b) before[prev.strata[b].id] = prev.strata[b]
        for (var s = 0; s < next.strata.length; ++s) {
            var cur = next.strata[s], old = before[cur.id]
            // Solo estratos que el servidor ya conoce; altas/bajas/orden = estructura (guardado completo).
            if (!old || !cur.remote.length) continue
            for (var f in cur.fields) {
                if (cur.fields[f] === old.fields[f] || root._liveIsProse("STRATUM", f)) continue
                CalicataCloud.applyFieldChange(root.doc, "STRATUM", cur.remote, f, cur.fields[f])
            }
            // Laboratorio del estrato: mismo contrato (RPC durable -> broadcast canónico).
            for (var lf in cur.lab) {
                if (cur.lab[lf] === undefined || !old.lab || cur.lab[lf] === old.lab[lf]) continue
                CalicataCloud.applyFieldChange(root.doc, "LAB_RESULT", cur.remote, lf, cur.lab[lf])
            }
        }
    }

    // Cambio canónico de otra persona, o el vigente devuelto como SUPERSEDED.
    // Aplica SOLO ese campo: sin dirty, sin autosave, sin re-emisión, sin
    // reconstruir el formulario.
    function applyRemoteFieldChange(change) {
        if (!change || !root.doc || root._loading || root._documentClosing) return false
        var target = change.target || {}
        var type = String(target.type || ""), field = String(change.field || "")
        var value = change.value === undefined ? null : change.value
        var applied = false
        root._applyingLivePatch = true
        try {
            if (type === "CALICATA") applied = root._applyLiveCalicata(field, value)
            else if (type === "STRATUM") applied = root._applyLiveStratum(String(target.id || ""), field, value)
            else if (type === "LAB_RESULT") applied = root._applyLiveLab(String(target.id || ""), field, value)
        } finally {
            root._applyingLivePatch = false
        }
        if (applied && root._liveBaseline) {
            // La línea base absorbe SOLO ese campo (no re-emisión, sin tragarse
            // commits locales pendientes del debounce).
            var now = root._liveSnapshot(root.exportState())
            if (type === "CALICATA") root._liveBaseline.calicata[field] = now.calicata[field]
            else {
                var id = String(target.id || "").toLowerCase()
                for (var i = 0; i < now.strata.length; ++i) {
                    if (now.strata[i].remote.toLowerCase() !== id) continue
                    for (var j = 0; j < root._liveBaseline.strata.length; ++j)
                        if (root._liveBaseline.strata[j].remote.toLowerCase() === id)
                            root._liveBaseline.strata[j][type === "LAB_RESULT" ? "lab" : "fields"][field]
                                    = now.strata[i][type === "LAB_RESULT" ? "lab" : "fields"][field]
                }
            }
        }
        return applied
    }
    function _applyLiveCalicata(field, value) {
        root._flushCortesRevision()
        var text = value === null ? "" : String(value).substring(0, 4000)
        function isoToDMY(iso) {
            return iso && iso.length >= 10 ? iso.substring(8, 10) + "/" + iso.substring(5, 7) + "/" + iso.substring(0, 4)
                                           : "Seleccionar fecha"
        }
        switch (field) {
        case "code": txtCodigo.text = text; return true
        case "supervisor": txtSupervisor.text = text; return true
        case "machine": txtMaquina.text = text; return true
        case "progresiva": txtPk.text = text; return true
        case "easting": txtUTMX.text = text; return true
        case "northing": txtUTMY.text = text; return true
        case "altitude_m": txtUTMZ.text = text; return true
        case "location": root.roadSideValue = text; return true
        case "start_date": btnFechaInicio.text = isoToDMY(text); return true
        case "end_date": btnFechaFin.text = isoToDMY(text); return true
        case "observations": root.observacionesText = text; return true
        case "utm_zone":
            // Android guarda número + banda ("18L"); la banda local se conserva.
            var band = /([C-HJ-NP-X])$/i.exec(String(txtZona.text || "").trim())
            txtZona.text = text.length ? text + (band ? band[1].toUpperCase() : "") : ""
            return true
        case "groundwater_depth_m":
            txtWaterTableDepth.text = text
            root.groundwaterCustom = text.length > 0 && text !== root.derivedGroundwaterText
            return true
        case "title":
        case "description":
            return !!root.doc.applyLiveHeaderField && root.doc.applyLiveHeaderField(field, value)
        default:
            // depth_m: Android la deriva de los estratos (se refleja al revalidar).
            return false
        }
    }
    // LAB_RESULT remoto: aplica SOLO ese campo del laboratorio del estrato y
    // recalcula derivados (IP, sugeridos) sin dirty, sin autosave y sin
    // re-emisión. primary_sucs / secondary_sucs / is_composite / aashto son la
    // autoridad del laboratorio (igual que Web): Estrato y patrón la proyectan.
    function _applyLiveLab(stratumId, field, value) {
        var id = stratumId.toLowerCase()
        for (var i = 0; i < cortesModel.count; ++i) {
            var row = cortesModel.get(i), extra = JSON.parse(row._extraJson || "{}")
            if (String(extra.remote_stratum_id || "").toLowerCase() !== id) continue
            var text = value === null ? "" : String(value).substring(0, 500)
            var column = root.liveLabColumns[field]
            if (column !== undefined) {
                if (text.length && !isFinite(Rules.parseDecimalSafe(text))) return false
                cortesModel.setProperty(i, column, text)
            } else if (field === "sieve_no4_pct" || field === "laboratory_source" || field === "test_date") {
                extra[field === "sieve_no4_pct" ? "passing_no4" : field] = text
                cortesModel.setProperty(i, "_extraJson", JSON.stringify(extra))
            } else if (field === "aashto") {
                if (text.length && Rules.webAashtoCodes.indexOf(text) < 0) return false
                extra = root._labAuthority(extra)
                extra.lab_confirmed_aashto = text
                cortesModel.setProperty(i, "_extraJson", JSON.stringify(extra))
            } else if (field === "primary_sucs" || field === "secondary_sucs" || field === "is_composite") {
                extra = root._labAuthority(extra)
                if (field === "is_composite") extra.is_composite = text === "true"
                else {
                    var code = text.toUpperCase()
                    if (code.length && Rules.webSucsCodes.indexOf(code) < 0) return false
                    extra[field] = code
                }
                cortesModel.setProperty(i, "_extraJson", JSON.stringify(root._labAuthority(extra)))
            } else {
                return false
            }
            root.deriveLabFields()
            return true
        }
        return false   // estrato aún no presente aquí: llega al revalidar
    }
    function _applyLiveStratum(stratumId, field, value) {
        var id = stratumId.toLowerCase()
        for (var i = 0; i < cortesModel.count; ++i) {
            var extra = JSON.parse(cortesModel.get(i)._extraJson || "{}")
            if (String(extra.remote_stratum_id || "").toLowerCase() !== id) continue
            var text = value === null ? "" : String(value).substring(0, 4000)
            switch (field) {
            case "to_depth_m":
                cortesModel.setProperty(i, "a", text.length && isFinite(Number(text)) ? Number(text).toFixed(2) : text)
                root.renumerarCortesYIntervalos(false)   // from_depth_m es derivado
                return true
            case "description": cortesModel.setProperty(i, "descripcion", text); return true
            case "moisture_condition": cortesModel.setProperty(i, "humedad", root.liveHumidity.indexOf(text.toUpperCase())); return true
            case "excavability": cortesModel.setProperty(i, "excavabilidad", root.liveExcavability.indexOf(text.toUpperCase())); return true
            case "sample_type":
                cortesModel.setProperty(i, "tipo_muestra", text)
                cortesModel.setProperty(i, "tipoText", text)
                return true
            case "consistency_compaction":
            case "color":
            case "observations":
                extra[field] = value === null ? null : text
                cortesModel.setProperty(i, "_extraJson", JSON.stringify(extra))
                return true
            }
            return false
        }
        return false   // estrato aún no presente aquí: llega al revalidar
    }

    Timer {
        id: typingDirtyTimer
        interval: 280
        repeat: false
        onTriggered: root._markDirty()
    }
    function _markDirtySoon() {
        if (_loading || _documentClosing || _applyingLivePatch || (doc && doc.applyingCloudState)) return
        setDirty(true)
        typingDirtyTimer.restart()
    }
    function flushTypingDirty() {
        if (!typingDirtyTimer.running) return
        typingDirtyTimer.stop()
        root._markDirty()
    }

    function _markDirty() {
        // Un parche live remoto no es edición del usuario (ni dirty ni autosave).
        if (_loading || _documentClosing || _derivingLab || _applyingLivePatch
                || (doc && doc.applyingCloudState)) return
        invalidateReview()
        deriveLabFields()
        if (root.coreSnapshot.length || root.coreFeedback.length) {
            root.coreSnapshot = ""
            root.cancelCoreReview()
            root.coreInterpretation = ""
            root.coreFeedback = "La ficha cambió. Vuelve a ejecutar InGe AI para revisar la versión actual."
        }
        setDirty(true)

        if (!doc || doc.closed === true) return
        if (doc.markDirty) {
            // Commit accepted UI values to the document before scheduling disk I/O.
            // dirty is already true, so dataChanged cannot re-import the form here.
            var state = exportState()
            doc.header = state.header
            doc.cortes = state.cortes
            doc.observaciones = state.observaciones
            doc.markDirty()
            // P0 autosave: se emite en CADA cambio, incluso si dirty ya era true.
            documentMarkedDirty(doc)
            // Live: campos CALICATA/STRATUM no-prose -> RPC durable -> anuncio canónico.
            root._queueLiveTx(state)
        } else {
            console.warn("[InGe+ M09] documento sin contrato markDirty instanceId="
                         + _docInstanceId(doc))
        }
    }

    function loadFromFile(path) {
        if (!doc || !doc.load || !commitPendingField()) return false
        var ok = doc.load(absToFileUrl(path))
        if (ok) importFromDoc()
        return ok
    }

    function saveToFile(path) {
        if (!doc || !commitPendingField()) return false
        var state = exportState()
        root.setDirty(true)
        doc.header = state.header
        doc.cortes = state.cortes
        doc.observaciones = state.observaciones
        doc.uiState = state.uiState
        return doc.saveAs(absToFileUrl(path), true, true)
    }

    function saveFlow(currentPath) {
        if (!currentPath || !currentPath.length)
            return saveAsFlow()
        return (saveToFile(currentPath) ? currentPath : "")
    }

    function saveAsFlow() {
        // TODO: flujo real Guardar Como
        return ""
    }

    function _parseLooseNumber(value) {
        return Rules.parseDecimalSafe(String(value === undefined || value === null ? "" : value)
            .replace(/m\s*s\.?\s*n\.?\s*m\.?/gi, "").replace("%", "").trim())
    }

    // One validator feeds both review and the existing export gate. Every
    // condition/message below comes from the previous _validateExportState.
    function _exportIssues(state) {
        return doc ? doc.validationIssues(state) : Rules.validateDocument(state)
    }

    function _validateExportState(state) {
        var issues = Rules.blockers(_exportIssues(state))
        return issues.length ? issues[0].message : ""
    }

    function exportExcelFlow(provider) {
        if (!commitPendingField()) return false
        flushRequested()
        var st = exportState()
        // Keep document identity internal; two fichas may share the same visible code.
        if (doc) st.instance_id = root._docInstanceId(doc)
        // V5: conserva los cambios en memoria y pasa la ubicación del JSON solo
        // para resolver logos/fotografías almacenados con rutas relativas.
        if (doc && doc.fileUrl)
            st._source_json_url = doc.fileUrl
        if (docsCtl.basePath && String(docsCtl.basePath).length)
            st._resources_base_path = docsCtl.basePath
        if (st.header === undefined || st.header === null)
            st.header = {}

        if ((st.header.project_full_name || "").toString().trim().length === 0
                && _hasPendingExcelTitle) {
            st.header.project_full_name = (_pendingExcelTitle || "")
        }

        // Revisión = aviso, nunca compuerta: la ficha incompleta se exporta
        // con celdas vacías (sin inventar datos).
        var validationError = root._validateExportState(st)
        if (validationError.length)
            console.info("INGE_CALICATA_EXPORT_ADVISORY " + validationError)

        var baseName = (txtCodigo && txtCodigo.text && txtCodigo.text.length)
                     ? txtCodigo.text : "calicata"

        var exporter = (typeof ExcelExporter !== "undefined") ? ExcelExporter
                     : (typeof CalicataExporter !== "undefined") ? CalicataExporter
                     : (typeof calicataExporter !== "undefined") ? calicataExporter
                     : null

        if (!exporter) {
            showInfo("Exportación no disponible",
                     "No se encontró el exportador Android. Revisa main_mobile.cpp y CMakeLists.txt.")
            return ""
        }

        var out = exporter.exportStateToXlsx(st, baseName, provider)
        if (out && out.length) {
            return out
        } else {
            console.warn("INGE_CALICATA_EXPORT_FAILED " + String(exporter.lastError || ""))
            return ""
        }
    }

    function clearCorte(i) {
        if (i < 0 || i >= cortesModel.count) return

        cortesModel.setProperty(i, "material_origin", "")
        // Limpiar contenido nunca borra la identidad del estrato.
        var keptIdentity = JSON.parse(cortesModel.get(i)._extraJson || "{}")
        cortesModel.setProperty(i, "_extraJson", JSON.stringify({
            local_stratum_id: keptIdentity.local_stratum_id || root._newLabUuid(),
            remote_stratum_id: keptIdentity.remote_stratum_id }))
        cortesModel.setProperty(i, "_percentageFieldsJson", "[]")
        cortesModel.setProperty(i, "descripcion", "")
        cortesModel.setProperty(i, "humedad", -1)
        cortesModel.setProperty(i, "excavabilidad", -1)
        cortesModel.setProperty(i, "estabilidad", -1)

        cortesModel.setProperty(i, "tipoText", "")
        cortesModel.setProperty(i, "tipo_muestra", "")
        cortesModel.setProperty(i, "tipo_otro", "")

        cortesModel.setProperty(i, "de", "")
        cortesModel.setProperty(i, "a",  "")
        cortesModel.setProperty(i, "muestra_desde", "")
        cortesModel.setProperty(i, "muestra_hasta", "")
        cortesModel.setProperty(i, "resultados", "")

        cortesModel.setProperty(i, "aashto", "")
        cortesModel.setProperty(i, "sucs", "")

        cortesModel.setProperty(i, "gmax", "")
        cortesModel.setProperty(i, "g2",   "")
        cortesModel.setProperty(i, "g04",  "")
        cortesModel.setProperty(i, "g008", "")
        cortesModel.setProperty(i, "g002", "")

        cortesModel.setProperty(i, "wl",   "")
        cortesModel.setProperty(i, "lp",   "")
        cortesModel.setProperty(i, "hum2", "")

        renumerarCortesYIntervalos(true)
    }





    // ✅ qué campos SÍ se intercambian (DE/A NO van aquí)
    readonly property var corteSwapKeys: [
        "material_origin","_extraJson","_percentageFieldsJson",
        "descripcion","humedad","excavabilidad","estabilidad",
        "tipoText","tipo_muestra","tipo_otro",
        "muestra_desde","muestra_hasta","resultados",
        "aashto","sucs",
        "gmax","g2","g04","g008","g002",
        "wl","lp","hum2"
    ]

    // Move complete local entities. Cloud synchronization refuses unsupported order changes.
    function _swapCorteContent(i, j) {
        var rows = []
        for (var n = 0; n < cortesModel.count; ++n) rows.push(corteToPlainObject(cortesModel.get(n)))
        var moved = Rules.moveStratumEntities(rows, i, j)
        if (!moved) { showInfo("Mover estrato", "Completa todos los intervalos antes de mover."); return false }
        cortesModel.clear()
        for (n = 0; n < moved.length; ++n) cortesModel.append(_normalizeCorte(moved[n]))
        renumerarCortesYIntervalos(true)
        return true
    }

    function moveCorteUp(i) {
        if (!commitPendingField() || i <= 0) return
        if (_swapCorteContent(i, i - 1)) selectedStratum = i - 1
    }

    function moveCorteDown(i) {
        if (!commitPendingField() || i < 0 || i >= cortesModel.count - 1) return
        if (_swapCorteContent(i, i + 1)) selectedStratum = i + 1
    }

    function importFromDoc() {
        if (!doc || doc.closed === true) { resetForm(); return }
        importState({
            header: doc.header,
            uiState: doc.uiState,
            cortes: doc.cortes,
            observaciones: doc.observaciones,
            timestamp: doc.timestamp,
            images: doc.images
        })
    }

    function _defaultCorte() {
        return {
            id: "stratum-" + Date.now() + "-" + Math.random().toString(36).slice(2),
            material_origin: "",
            _extraJson: JSON.stringify({ local_stratum_id: root._newLabUuid() }),
            _percentageFieldsJson: "[]",
            remote_sample_id: "",
            sample_code: "",
            descripcion: "",
            humedad: -1,
            excavabilidad: -1,
            estabilidad: -1,
            tipoText: "",
            tipo_muestra: "",
            tipo_otro: "",
            de: "",
            a: "",
            muestra_desde: "",
            muestra_hasta: "",
            resultados: "",
            aashto: "",
            sucs: "",
            gmax: "",
            g2: "",
            g04: "",
            g008: "",
            g002: "",
            wl: "",
            lp: "",
            hum2: ""
        }
    }

    function _normalizeCorte(x) {
        var input = (x && typeof x === "object") ? x : {}
        var o = Object.assign({}, JSON.parse(input._extraJson || "{}"), input)
        delete o._extraJson
        var d = _defaultCorte()
        // Esquema de PRESENTACIÓN estable: ListModel no crea rol para un miembro
        // null ("Adding an object with a null member..."). Un null conserva el
        // valor tipado por defecto (o no crea rol si es un dato extra); el dato
        // canónico, null incluido, sigue intacto en _extraJson.
        // Listas/objetos anidados (remote_samples, percentage_fields…) viven solo en
        // _extraJson (corteToPlainObject los restaura): como rol, ListModel los
        // convierte en submodelos y sus miembros null ("observations") generan el
        // mismo warning en cada hidratación.
        var r = Object.assign({}, d)
        for (var key in o)
            if (o[key] !== null && o[key] !== undefined && typeof o[key] !== "object") r[key] = o[key]
        // Estrato heredado sin identidad local: se le asigna una vez y se
        // persiste en el siguiente autosave (ver importState).
        if (!o.local_stratum_id) {
            o.local_stratum_id = o.remote_stratum_id || root._newLabUuid()
            if (!o.remote_stratum_id) root._assignedStratumIds = true
        }
        r.local_stratum_id = String(o.local_stratum_id)
        r.remote_sample_id = String(o.remote_sample_id || "")
        r.sample_code = String(o.sample_code || "")
        r._extraJson = JSON.stringify(o)
        r._percentageFieldsJson = JSON.stringify(o.percentage_fields || [])
        // "A1a", "A 2 4"… -> código canónico; un valor desconocido se conserva tal cual.
        r.aashto = Rules.normalizeAashtoCode(r.aashto) || String(r.aashto || "")
        r.humedad = root._enumIndex(r.humedad, root.humItems)
        r.excavabilidad = root._enumIndex(r.excavabilidad, root.excItems)
        r.estabilidad = root._enumIndex(r.estabilidad, root.estItems)
        r.de = (r.de === undefined || r.de === null) ? "" : String(r.de)
        r.a  = (r.a  === undefined || r.a  === null) ? "" : String(r.a)
        var legacyType = String(o.tipo_muestra || o.muestra || o.tipoText || "").trim()
        var legacyTypeUpper = legacyType.toUpperCase()
        if (["MA", "MS", "MI", "MW"].indexOf(legacyTypeUpper) >= 0) {
            r.tipo_muestra = legacyTypeUpper
        } else if (legacyType.length && !String(r.tipo_muestra || "").length) {
            r.tipo_muestra = "Otro"
            r.tipo_otro = legacyType
        }
        r.muestra_desde = (o.muestra_desde !== undefined && o.muestra_desde !== null)
                ? String(o.muestra_desde) : r.de
        r.muestra_hasta = (o.muestra_hasta !== undefined && o.muestra_hasta !== null)
                ? String(o.muestra_hasta) : r.a
        r.resultados = String(o.resultados || o.resultado || "")
        r.g002 = String(o.g002 || o.g2micra || o.g2_micra || "")
        return r
    }

    function corteToPlainObject(row) {
        var source = (row && typeof row === "object") ? row : {}
        return Object.assign({}, JSON.parse(source._extraJson || "{}"), {
            id: String(source.id || ""),
            material_origin: String(source.material_origin || ""),
            ip: JSON.parse(source._extraJson || "{}").nonplastic_confirmed === true ? "NP" : Rules.plasticityIndex(source.wl, source.lp),
            percentage_fields: JSON.parse(source._percentageFieldsJson || "[]"),
            descripcion: String(source.descripcion || ""),
            humedad: isFinite(Number(source.humedad)) ? Number(source.humedad) : -1,
            excavabilidad: isFinite(Number(source.excavabilidad)) ? Number(source.excavabilidad) : -1,
            estabilidad: isFinite(Number(source.estabilidad)) ? Number(source.estabilidad) : -1,
            tipoText: String(source.tipo_muestra === "Otro"
                             ? (source.tipo_otro || "") : (source.tipo_muestra || "")),
            tipo_muestra: String(source.tipo_muestra || ""),
            tipo_otro: String(source.tipo_otro || ""),
            de: String(source.de === undefined || source.de === null ? "" : source.de),
            a: String(source.a === undefined || source.a === null ? "" : source.a),
            muestra_desde: source.tipo_muestra || source.tipoText || source.sample_code || source.remote_sample_id
                          ? Rules.sampleIntervalValue(source, "muestra_desde") : String(source.muestra_desde || ""),
            muestra_hasta: source.tipo_muestra || source.tipoText || source.sample_code || source.remote_sample_id
                          ? Rules.sampleIntervalValue(source, "muestra_hasta") : String(source.muestra_hasta || ""),
            resultados: String(source.resultados || ""),
            aashto: String(source.aashto || ""),
            sucs: String(source.sucs || ""),
            gmax: String(source.gmax === undefined || source.gmax === null ? "" : source.gmax),
            g2: String(source.g2 === undefined || source.g2 === null ? "" : source.g2),
            g04: String(source.g04 === undefined || source.g04 === null ? "" : source.g04),
            g008: String(source.g008 === undefined || source.g008 === null ? "" : source.g008),
            g002: String(source.g002 === undefined || source.g002 === null ? "" : source.g002),
            wl: String(source.wl === undefined || source.wl === null ? "" : source.wl),
            lp: String(source.lp === undefined || source.lp === null ? "" : source.lp),
            hum2: String(source.hum2 === undefined || source.hum2 === null ? "" : source.hum2)
        })
    }

    function corteHasMeaningfulData(i) {
        if (i < 0 || i >= cortesModel.count) return false
        var r = cortesModel.get(i)
        function hasText(x){ return x !== undefined && x !== null && String(x).trim().length > 0 }

        return hasText(r.descripcion) || hasText(r.tipo_muestra) || hasText(r.tipo_otro) ||
               hasText(r.a) || hasText(r.aashto) || hasText(r.sucs) ||
               hasText(r.muestra_desde) || hasText(r.muestra_hasta) || hasText(r.resultados) ||
               hasText(r.gmax) || hasText(r.g2) || hasText(r.g04) || hasText(r.g008) ||
               hasText(r.g002) ||
               hasText(r.wl) || hasText(r.lp) || hasText(r.hum2)
    }


    function resetForm() {
        liveTxDebounce.stop()
        root._livePendingState = null
        root._liveBaseline = null
        root.requestedDepthM = 0
        root.profileSetup = ({})
        root.prfReorderMode = false
        root._activeCommitField = null
        root._pendingCommitFields = []
        _loading = true

        // header
        if (typeof txtSupervisor !== "undefined") txtSupervisor.text = ""
        if (typeof txtMaquina !== "undefined")    txtMaquina.text = ""
        root.roadSideValue = ""
        if (typeof txtCodigo !== "undefined")     txtCodigo.text = ""
        if (typeof txtPk !== "undefined")         txtPk.text = ""
        if (typeof txtUbicacion !== "undefined")  txtUbicacion.text = ""
        if (typeof txtUTMX !== "undefined")       txtUTMX.text = ""
        if (typeof txtUTMY !== "undefined")       txtUTMY.text = ""
        if (typeof txtUTMZ !== "undefined")       txtUTMZ.text = ""
        if (typeof txtZona !== "undefined")       txtZona.text = ""
        root.groundwaterCustom = false
        if (typeof txtWaterTableDepth !== "undefined") txtWaterTableDepth.text = ""
        if (typeof txtProjectFullName !== "undefined") txtProjectFullName.text = ""
        if (typeof btnFechaInicio !== "undefined") btnFechaInicio.text = "Seleccionar fecha"
        if (typeof btnFechaFin !== "undefined")    btnFechaFin.text = "Seleccionar fecha"

        // identidad contractual
        if (typeof btnTituloCalicata !== "undefined")
            btnTituloCalicata.text = "Nombre del proyecto"

        // logos / fotos / obs
        logoMtcSource = ""
        logoProyectoSource = ""
        observacionesText = ""

        // cortes
        cortesModel.clear()
        renumerarCortesYIntervalos(false)

        _loading = false
        setDirty(false)
    }

    function importState(st) {
        if (!st) { resetForm(); return }
        _loading = true

        var h = st.header || {}
        root.requestedDepthM = Rules.parseDecimalSafe(h.requested_depth_m) || 0
        root.profileSetup = (h.profile_setup && typeof h.profile_setup === "object")
                ? Object.assign({}, h.profile_setup) : ({})
        root.prfReorderMode = false
        root._activeCommitField = null
        root._pendingCommitFields = []
        var ts = st.timestamp || {}

        if (typeof txtSupervisor !== "undefined") txtSupervisor.text = (h.supervisor || "")
        if (typeof txtMaquina    !== "undefined") txtMaquina.text    = (h.maquina || h.machine || "")
        if (typeof txtCodigo     !== "undefined") txtCodigo.text     = root._headerCode(h)
        if (typeof txtPk         !== "undefined") txtPk.text         = root._headerPk(h)
        if (typeof txtUbicacion  !== "undefined") txtUbicacion.text  = (h.ubicacion || h.tramo || "")
        if (typeof txtUTMX       !== "undefined") txtUTMX.text       = h.utm_x === undefined || h.utm_x === null ? "" : String(h.utm_x)
        if (typeof txtUTMY       !== "undefined") txtUTMY.text       = h.utm_y === undefined || h.utm_y === null ? "" : String(h.utm_y)
        if (typeof txtUTMZ       !== "undefined") txtUTMZ.text       = (h.utm_z || h.altitud || ts.altitud || "")
        if (typeof txtZona       !== "undefined") txtZona.text       = (h.zona || "")
        // Valor freático guardado (legacy ENCONTRADO o override Personalizado).
        // El modo se decide después de cargar los cortes.
        if (typeof txtWaterTableDepth !== "undefined")
            txtWaterTableDepth.text = (h.water_table_depth !== undefined
                                       && h.water_table_depth !== null)
                    ? String(h.water_table_depth)
                    : (h.waterTableDepth !== undefined && h.waterTableDepth !== null)
                      ? String(h.waterTableDepth) : ""
        if (typeof txtProjectFullName !== "undefined") {
            // Nombre contractual (dato de la ficha). projectName es el espacio de
            // guardado y nunca se usa como nombre del proyecto.
            var projectName = String(h.project_full_name || h.nombre_proyecto_completo
                                     || h.excel_title || ts.proyecto || "").trim()
            txtProjectFullName.text = projectName
        }

        // lado de vía = calicatas.location (CalicataDocument ya separó el
        // tramo legacy). Valores fuera del catálogo se conservan como históricos.
        root.roadSideValue = String(h.location || h.lado_via || "").trim()

        // fechas ISO -> DMY
        function isoToDMY(iso) {
            if (!iso || iso.length < 10) return "Seleccionar fecha"
            return iso.substring(8,10) + "/" + iso.substring(5,7) + "/" + iso.substring(0,4)
        }
        if (typeof btnFechaInicio !== "undefined") btnFechaInicio.text = isoToDMY(h.fecha_inicio || "")
        if (typeof btnFechaFin !== "undefined")    btnFechaFin.text    = isoToDMY(h.fecha_fin || "")

        // identidad contractual
        if (typeof btnTituloCalicata !== "undefined") {
            var projectTitle = (txtProjectFullName.text || "").toString().trim()
            btnTituloCalicata.text = projectTitle.length ? "Nombre del proyecto ✓"
                                                         : "Nombre del proyecto"
        }

        // cortes
        cortesModel.clear()
        var cs = st.cortes || []
        for (var i = 0; i < cs.length; ++i) cortesModel.append(_normalizeCorte(cs[i]))
        renumerarCortesYIntervalos(false)

        // Personalizado: flag local explícito; si no existe (ficha antigua o
        // recién leída de la nube) se infiere como en Web: un valor guardado
        // que difiere del derivado es un override y se conserva.
        if (h.groundwater_custom === true || h.groundwater_custom === false) {
            root.groundwaterCustom = h.groundwater_custom
        } else {
            var storedWater = String(txtWaterTableDepth.text || "").trim().replace(",", ".")
            var derivedWater = root._derivedGroundwater()
            root.groundwaterCustom = storedWater.length > 0
                    && (derivedWater === null || Number(storedWater) !== Number(derivedWater))
        }
        var view = (st.uiState || {}).calicatasView || {}
        // La navegación (sección / estrato) es estado del EDITOR: se restaura solo la
        // primera vez que se importa esta ficha. Guardar, sincronizar, confirmar una
        // foto o rehidratar re-importan datos y nunca deben devolver a General.
        var importedDocId = root._docInstanceId(root.doc)
        if (!importedDocId.length || importedDocId !== root._navigationDocId) {
            root._navigationDocId = importedDocId
            var savedStage = Number(view.stage || 0)
            if (Number(view.stageSchema || 0) >= 2) {
                stageIndex = Math.max(0, Math.min(5, savedStage))
            } else {
                // Migración de documentos guardados con el flujo anterior de 5 etapas:
                // 0 General, 1 Ubicación, 2 Perfil, 3 Fotos, 4 Revisión.
                stageIndex = savedStage === 3 ? 4 : (savedStage === 4 ? 5 : Math.max(0, Math.min(2, savedStage)))
            }
            sectionNavCurrent = sectionNavigation[stageIndex].n
            selectedStratum = Math.min(Number(view.selectedStratum === undefined ? -1 : view.selectedStratum), cortesModel.count - 1)
        } else if (selectedStratum >= cortesModel.count) {
            selectedStratum = cortesModel.count - 1
        }
        profileMode = "overview"
        activePhotoCategory = Math.max(1, Math.min(3, Number(view.photoCategory || 1)))

        // observaciones
        observacionesText = (st.observaciones !== undefined) ? (st.observaciones || "") : ""

        // logos
        var imgs = st.images || {}
        logoMtcSource = root._resolvedLogo(imgs.logo_mtc_path, imgs.logo_mtc_removed, "mtc")
        logoProyectoSource = root._resolvedLogo(imgs.logo_proyecto_path, imgs.logo_proyecto_removed, "pro")

        // fotos (desde doc, porque resuelve REL y valida existencia)

        _loading = false
        // Revisión de laboratorio (derivado/sugerido) disponible al reabrir la ficha.
        deriveLabFields()
        if (root._assignedStratumIds) {
            root._assignedStratumIds = false
            if (!doc || !doc.applyingCloudState) root._markDirty()
        }
        setDirty(doc ? !!doc.dirty : false)
        if (stageIndex === 5) reviewRefresh.restart()
        // Live: lo cargado (local, hydrate o revalidación) es la línea base; cargar no emite.
        liveTxDebounce.stop()
        root._livePendingState = null
        root._liveBaseline = root._liveSnapshot(root.exportState())
    }


    function exportState() {
        root._flushCortesRevision()
        // ✅ IMPORTANTÍSIMO: parte del header actual para no perder campos (excel_title, pk, etc)
        var baseHeader = (doc && doc.header) ? doc.header : {}
        var code = (typeof txtCodigo !== "undefined") ? txtCodigo.text.trim() : ""
        var pk = (typeof txtPk !== "undefined") ? txtPk.text.trim() : ""
        var projectFullName = (typeof txtProjectFullName !== "undefined")
                ? txtProjectFullName.text.trim() : ""
        // Si el campo local está vacío se conserva el nombre contractual guardado;
        // nunca se sustituye por el espacio/carpeta (projectName).
        if (!projectFullName.length)
            projectFullName = String(baseHeader.project_full_name || "").trim()

        var h = Object.assign({}, baseHeader, {
            supervisor: (typeof txtSupervisor !== "undefined") ? txtSupervisor.text : "",
            maquina:    (typeof txtMaquina    !== "undefined") ? txtMaquina.text    : "",
            codigo:     code,
            calicata:   code,
            pk:         pk,
            progresiva: pk,
            ubicacion:  (typeof txtUbicacion !== "undefined") ? txtUbicacion.text : "",
            utm_x:      (typeof txtUTMX       !== "undefined") ? txtUTMX.text       : "",
            utm_y:      (typeof txtUTMY       !== "undefined") ? txtUTMY.text       : "",
            utm_z:      (typeof txtUTMZ       !== "undefined") ? txtUTMZ.text       : "",
            altitud:    (typeof txtUTMZ       !== "undefined") ? txtUTMZ.text       : "",
            zona:       (typeof txtZona       !== "undefined") ? txtZona.text       : "",
            project_full_name: projectFullName,
            depth_max_m: null, // Sin tope; no serializar Infinity.
            requested_depth_m: root.requestedDepthM,
            final_depth_m: root.totalDepthM
        })

        // Canonical Web aliases. Legacy keys remain for the current UI/XLSX,
        // but cloud sync only needs one deterministic domain vocabulary.
        h.code = code
        h.title = String(h.title || "").trim()
        // calicatas.location = lado de la vía. `ubicacion` (tramo) queda local.
        h.location = root.roadSideValue.trim()
        h.lado_via = h.location
        h.easting = String(h.utm_x || "").trim()
        h.northing = String(h.utm_y || "").trim()
        h.altitude_m = String(h.utm_z || "").trim()
        // Profundidad canónica derivada de los cortes; la objetivo manual
        // (requested/final_depth_m) sigue siendo solo local (Excel).
        h.depth_m = root.derivedDepthText
        // Configuración del perfil (Perfil > columna izquierda/derecha).
        h.profile_setup = Object.assign({}, root.profileSetup || {})
        // Nivel freático: derivado del primer AGUA o override Personalizado.
        // El estado legacy se mantiene coherente para Excel/validaciones.
        var water = root.effectiveGroundwaterText
        var previousWater = String(baseHeader.water_table_status || "")
        h.groundwater_custom = root.groundwaterCustom
        h.water_table_depth = water
        h.groundwater_depth_m = water
        h.water_table_present = water.length > 0
        h.water_table_status = water.length ? "ENCONTRADO"
                : previousWater === "NO_ENCONTRADO" ? "NO_ENCONTRADO" : "NO_EVALUADO"
        // utm_zone numérico 1..60; `zona` conserva la banda local ("18L").
        var zoneMatch = /^(\d{1,2})\s*[C-HJ-NP-X]?$/i.exec(String(h.zona || "").trim())
        var zoneNumber = zoneMatch ? Number(zoneMatch[1]) : 0
        h.utm_zone = zoneNumber >= 1 && zoneNumber <= 60 ? zoneNumber : null
        h.machine = String(h.maquina || "").trim()
        // description = "Título de la ficha / testificación"; se edita en
        // General y no se deriva de la descripción técnica local.
        h.description = String(h.description || "").trim()

        function dmyToIso(dmy) {
            var d = root._parseDMY(dmy)
            if (!d) return ""
            var mm = (d.getMonth()+1); if (mm < 10) mm = "0"+mm
            var dd = d.getDate();      if (dd < 10) dd = "0"+dd
            return d.getFullYear() + "-" + mm + "-" + dd
        }

        h.fecha_inicio = dmyToIso(btnFechaInicio.text)
        h.fecha_fin    = dmyToIso(btnFechaFin.text)
        h.start_date = h.fecha_inicio
        h.end_date = h.fecha_fin
        // Hora de la ficha: hora_inicio (local) = start_time (columna remota).
        h.hora_inicio = Rules.normalizeOptionalTime(h.hora_inicio) || ""
        h.start_time = h.hora_inicio

        var cortes = []
        for (var i = 0; i < cortesModel.count; ++i)
            cortes.push(corteToPlainObject(cortesModel.get(i)))

        return {
            header: h,
            uiState: Object.assign({}, (doc ? (doc.uiState || {}) : {}), {
                calicatasView: { stageSchema: 2, stage: stageIndex, selectedStratum: selectedStratum,
                                 photoCategory: activePhotoCategory,
                                 validation: { reviewed: reviewRequested, issues: reviewIssues } }
            }),
            cortes: cortes,
            observaciones: observacionesText,
            timestamp: Object.assign({}, (doc ? (doc.timestamp || {}) : {})),
            images: Object.assign({}, (doc ? (doc.images || {}) : {}))
        }
    }

    // ✅ Interval rules (PC-like)
    readonly property real depthEpsM: 0.01
    property bool _updatingIntervals: false

    function _parseDepthText(s) {
        return Rules.parseDecimalSafe(s)
    }

    function commitBoundary(index, text) {
        var rows = []
        for (var i = 0; i < cortesModel.count; ++i) rows.push(cortesModel.get(i))
        var error = Rules.boundaryError(rows, index, text, allowedDepthM)
        if (error) { showInfo("Intervalo del estrato", error); return false }

        var row = cortesModel.get(index)
        var previousDe = String(row.de || ""), previousA = String(row.a || "")
        cortesModel.setProperty(index, "a", Rules.normalizeDecimalText(text, Rules.DEPTH_METERS, false))
        root._inheritSampleInterval(index, previousDe, previousA)
        renumerarCortesYIntervalos(true)
        return true
    }

    function _fmtDepth(v) {
        return (Math.round(v * 100) / 100).toFixed(2)
    }

    // Replica la lógica de renumerarCortesYIntervalos de PC
    function renumerarCortesYIntervalos(markDirty) {

        if (_updatingIntervals) return
        _updatingIntervals = true

        var wasLoading = _loading

        var prevA = 0.0
        var prevKnown = true
        var maxA = 0.0

        for (var i = 0; i < cortesModel.count; ++i) {
            var row = cortesModel.get(i)

            // DE automático
            var previousDe = String(row.de || "")
            var deTxt = prevKnown ? _fmtDepth(prevA) : ""
            if (String(row.de || "") !== deTxt)
                cortesModel.setProperty(i, "de", deTxt)
            root._inheritSampleInterval(i, previousDe, row.a)

            // Si la cadena ya se rompió, fuerza A vacío
            if (!prevKnown) {
                continue
            }

            var aRaw = ((row.a || "") + "").trim()
            var aVal = _parseDepthText(aRaw)

            if (!aRaw.length || isNaN(aVal)) {
                prevKnown = false
                continue
            }

            // Invalid historical intervals remain visible for correction; never clamp or erase.
            if (aVal <= prevA || Math.abs(aVal * 20 - Math.round(aVal * 20)) > 0.000001) {
                prevKnown = false
                continue
            }

            aVal = Math.round(aVal * 100) / 100
            var aTxt = _fmtDepth(aVal)
            if ((row.a || "") !== aTxt)
                cortesModel.setProperty(i, "a", aTxt)

            prevA = aVal
            maxA = Math.max(maxA, aVal)
        }

        root.totalDepthM = maxA
        var derivedRows = []
        for (var d = 0; d < cortesModel.count; ++d) derivedRows.push(cortesModel.get(d))
        root.strataGroundwaterDepth = Rules.strataDerived(derivedRows).groundwaterDepth
        _updatingIntervals = false

        if (markDirty && !wasLoading) _markDirty()
    }

    function _softWrapPaths(s) {
        return String(s || "")
            .replace(/\\/g, "\\\u200B")   // zero-width break
            .replace(/\//g, "/\u200B")
    }

    function showInfo(t, msg) {
        infoDlg.title = t
        infoText.text = _softWrapPaths(msg)
        infoDlg.open()
    }

    function _syncTimestampNow() {
        if (!doc || doc.closed === true) return
        var ts = Object.assign({}, (doc.timestamp || {}))

        ts.zona = txtZona.text
        ts.este = txtUTMX.text
        ts.norte = txtUTMY.text
        ts.calicata = txtCodigo.text

        ts.proyecto = txtProjectFullName.text
        ts.altitud = txtUTMZ.text

        // fecha/hora “ahora”
        var now = new Date()
        // dd/MM/yy
        var dd = (now.getDate() < 10 ? "0" : "") + now.getDate()
        var mm = ((now.getMonth()+1) < 10 ? "0" : "") + (now.getMonth()+1)
        var yy = (now.getFullYear() % 100); yy = (yy < 10 ? "0" : "") + yy
        ts.fecha = dd + "/" + mm + "/" + yy

        // HH:mm:ss
        var hh = (now.getHours() < 10 ? "0" : "") + now.getHours()
        var mi = (now.getMinutes() < 10 ? "0" : "") + now.getMinutes()
        var ss = (now.getSeconds() < 10 ? "0" : "") + now.getSeconds()
        ts.hora = hh + ":" + mi + ":" + ss

        doc.timestamp = ts
    }

    function _normPath(p) {
        var s = (p || "").toString()
        s = s.replace(/\\/g, "/")
        if (s.startsWith("file:///"))
            s = s.substring(Qt.platform.os === "windows" ? 8 : 7)
        else if (s.startsWith("file://")) s = s.substring(7)
        try { s = decodeURIComponent(s) } catch(e) {}
        return s
    }

    function _baseNamePath(p) {
        var s = _normPath(p)
        var i = s.lastIndexOf("/")
        return (i >= 0) ? s.substring(i+1) : s
    }

    // Muestra "Usuario_nouid/..." usando docsCtl.basePath como raíz
    function _prettyFromUserRoot(absOrUrl) {
        var base = _normPath(docsCtl.basePath || "")
        var full = _normPath(absOrUrl || "")
        if (!base.length || !full.length) return full

        var bn = _baseNamePath(base)
        if (full === base) return bn

        var baseSlash = base.endsWith("/") ? base : (base + "/")
        if (full.startsWith(baseSlash)) return bn + "/" + full.substring(baseSlash.length)
        return full
    }

    function _manualCoordinatesChanged() {
        if (_loading || !doc) return
        var h = Object.assign({}, doc.header)
        // Las UTM escritas se interpretan en el datum activo (WGS84 o PSAD56) y se
        // guardan también como grados WGS84 para el mapa.
        var point = (h.datum === "WGS84" || h.datum === "PSAD56")
                ? Rules.utmToGeoForDatum(txtUTMX.text, txtUTMY.text, txtZona.text, h.datum) : null
        h.latitude = point ? point.latitude : null
        h.longitude = point ? point.longitude : null
        h.coordinate_source = "MANUAL_UTM"
        h.coordinate_timestamp = new Date().toISOString()
        h.horizontal_accuracy_m = null
        doc.header = h
        gpsCaptureTone = point ? "success" : "error"
        gpsCaptureStatus = point ? "Ubicación manual actualizada"
                                 : "Completa Este, Norte, zona con banda y datum."
    }

    // Cambio de datum: misma ubicación física, otra representación UTM. La fuente
    // es lat/lon WGS84 guardados (sin deriva entre cambios); si faltan, las UTM en
    // el datum anterior. La cota no cambia. Sin ubicación válida solo cambia el datum.
    function _changeDatum(newDatum) {
        if (_loading || !doc) return
        var h = Object.assign({}, doc.header)
        var oldDatum = String(h.datum || "")
        var known = oldDatum === "WGS84" || oldDatum === "PSAD56"
        if (!known || !(newDatum === "WGS84" || newDatum === "PSAD56") || newDatum === oldDatum) {
            h.datum = newDatum
            doc.header = h
            // Sin datum previo, las UTM existentes pasan a leerse en el nuevo datum.
            if (!known) _manualCoordinatesChanged()
            return
        }
        var lat = Rules.parseDecimalSafe(h.latitude), lon = Rules.parseDecimalSafe(h.longitude)
        if (!isFinite(lat) || !isFinite(lon)) {
            var geo = Rules.utmToGeoForDatum(txtUTMX.text, txtUTMY.text, txtZona.text, oldDatum)
            if (geo) { lat = geo.latitude; lon = geo.longitude }
        }
        var utm = isFinite(lat) && isFinite(lon) ? Rules.geoToUtmForDatum(lat, lon, newDatum) : null
        h.datum = newDatum
        if (!utm) {
            doc.header = h
            return
        }
        // Contrato de zona existente: se conserva la forma usada (con o sin banda).
        var zoneText = /[C-HJ-NP-X]$/i.test(txtZona.text.trim()) || !txtZona.text.trim().length
                ? String(utm.zone) + utm.band : String(utm.zone)
        txtUTMX.text = utm.easting.toFixed(2)
        txtUTMY.text = utm.northing.toFixed(2)
        txtZona.text = zoneText
        h.utm_x = txtUTMX.text
        h.utm_y = txtUTMY.text
        h.zona = zoneText
        h.latitude = lat
        h.longitude = lon
        doc.header = h
        gpsCaptureTone = "success"
        gpsCaptureStatus = "Coordenadas transformadas a " + newDatum
    }

    function _hasCurrentCoords() {
        return (txtZona.text.trim() !== "" || txtUTMX.text.trim() !== "" || txtUTMY.text.trim() !== "")
    }

    function _gpsFailure(title, message, showDialog) {
        _gpsRequestSerial++
        gpsCaptureActive = false
        gpsCaptureTone = "error"
        gpsCaptureStatus = message
        _pendingGpsDocId = ""
        // Los timeouts se muestran dentro de la sección para no bloquear la
        // ficha. Permisos/GPS desactivado todavía pueden abrir un aviso claro.
        if (showDialog !== false)
            showInfo(title, message)
    }

    function _gpsRequestMatches(targetDocId, requestSerial) {
        var id = String(targetDocId || "")
        return gpsCaptureActive
                && requestSerial === _gpsRequestSerial
                && id.length > 0
                && id === _pendingGpsDocId
                && id === _docInstanceId(doc)
                && doc
                && doc.closed !== true
    }

    function _nativeGpsIsValid(requireNewTimestamp, maximumAccuracy) {
        if (!Perms.nativeHasFix) return false
        return Rules.gpsFixValid(Number(Perms.nativeLatitude), Number(Perms.nativeLongitude),
            Number(Perms.nativeAccuracy), Number(Perms.nativeTimestampMs), Date.now(),
            _gpsBaselineTimestampMs, requireNewTimestamp, maximumAccuracy)
    }

    function _publishNativeGpsToBus() {
        var timestampMs = Number(Perms.nativeTimestampMs)
        var timeText = isFinite(timestampMs) && timestampMs > 0
                ? Qt.formatTime(new Date(timestampMs), "hh:mm:ss")
                : Qt.formatTime(new Date(), "hh:mm:ss")
        var altitude = Number(Perms.nativeAltitude)
        GpsBus.updateFromGeo(Number(Perms.nativeLatitude),
                             Number(Perms.nativeLongitude),
                             altitude, isFinite(altitude), timeText,
                             Number(Perms.nativeAccuracy),
                             String(Perms.nativeProvider || "GPS del dispositivo"))
    }

    function _applyCoordsFromGps(targetDocId, requestSerial) {
        if (_documentClosing || !GpsBus.hasFix() || !GpsBus.hasGeoFix()
                || GpsBus.latitude < -80 || GpsBus.latitude > 84 || Math.abs(GpsBus.longitude) > 180) return false
        var targetId = String(targetDocId || _docInstanceId(doc))
        var target = doc
        if (!target || target.closed === true
                || !targetId.length
                || _docInstanceId(target) !== targetId) {
            return false
        }
        if (requestSerial > 0 && !_gpsRequestMatches(targetId, requestSerial))
            return false

        // El GPS entrega grados WGS84. Las UTM se escriben en el datum activo:
        // WGS84 (o sin datum) usa GpsBus; PSAD56 transforma el mismo punto.
        var datum = String((target.header || {}).datum || "") === "PSAD56" ? "PSAD56" : "WGS84"
        var zone = String(GpsBus.utmZone || "")
        var easting = Number(GpsBus.utmX).toFixed(2)
        var northing = Number(GpsBus.utmY).toFixed(2)
        if (datum === "PSAD56") {
            var psad = Rules.geoToUtmForDatum(Number(GpsBus.latitude), Number(GpsBus.longitude), "PSAD56")
            if (!psad) return false
            zone = String(psad.zone) + psad.band
            easting = psad.easting.toFixed(2)
            northing = psad.northing.toFixed(2)
        }

        txtZona.text = zone
        txtUTMX.text = easting
        txtUTMY.text = northing
        // Cota Z: no se escribe aquí. Tras fijar X/Y se resuelve con la
        // elevación del terreno (resolveAltitude); la altura GPS del fix
        // (elipsoidal) solo sirve de respaldo y una Z manual nunca se pisa.
        var deviceAltitude = GpsBus.altitudeOk ? Number(GpsBus.altitude) : NaN

        var h = Object.assign({}, (target.header || {}))
        h.zona = zone
        h.datum = datum
        h.utm_x = easting
        h.utm_y = northing
        if (GpsBus.hasGeoFix()) {
            h.latitude = Number(GpsBus.latitude)
            h.longitude = Number(GpsBus.longitude)
            h.horizontal_accuracy_m = isFinite(GpsBus.horizontalAccuracy)
                    ? Number(GpsBus.horizontalAccuracy) : null
            h.coordinate_source = String(GpsBus.sourceLabel || "GPS")
            h.coordinate_timestamp = String(GpsBus.timeText || "")
        }
        target.header = h

        var ts = Object.assign({}, (target.timestamp || {}))
        ts.zona = zone
        ts.este = easting
        ts.norte = northing
        ts.calicata = txtCodigo.text
        if (ts.proyecto === undefined) ts.proyecto = ""

        var now = new Date()
        var dd = (now.getDate() < 10 ? "0" : "") + now.getDate()
        var mm = ((now.getMonth()+1) < 10 ? "0" : "") + (now.getMonth()+1)
        var yy = (now.getFullYear() % 100); yy = (yy < 10 ? "0" : "") + yy
        ts.fecha = dd + "/" + mm + "/" + yy
        var hh = (now.getHours() < 10 ? "0" : "") + now.getHours()
        var mi = (now.getMinutes() < 10 ? "0" : "") + now.getMinutes()
        var ss = (now.getSeconds() < 10 ? "0" : "") + now.getSeconds()
        ts.hora = hh + ":" + mi + ":" + ss
        target.timestamp = ts
        target.markDirty()
        documentMarkedDirty(target)

        setDirty(true)
        GpsBus.markApplied()
        gpsCaptureActive = false
        gpsCaptureTone = "success"
        gpsCaptureStatus = "Coordenadas actualizadas · " + zone
        _pendingGpsDocId = ""
        console.info("[InGe+ M09] GPS apply instanceId=" + targetId)
        // Ubicación confirmada ("Mi ubicación" o punto del mapa): cota del terreno.
        root.resolveAltitude("location", deviceAltitude)
        return true
    }

    function _openCurrentCoordinateInEarth() {
        if (!doc || doc.closed === true) return
        var h = doc.header || {}
        var latitude = Number(h.latitude)
        var longitude = Number(h.longitude)
        if (!isFinite(latitude) || !isFinite(longitude)) return
        var altitude = Number(h.utm_z !== undefined ? h.utm_z : h.altitud)
        requestOpenEarth(latitude, longitude, isFinite(altitude) ? altitude : 0,
                         String(txtCodigo.text || "Calicata"))
    }

    function _applyOrConfirmCoordsFromGps(targetDocId, requestSerial) {
        if (_hasCurrentCoords()) {
            coordsConfirmText.text = "La ficha ya contiene coordenadas. ¿Deseas reemplazarlas con "
                    + String(GpsBus.sourceLabel || "la ubicación seleccionada")
                    + " (precisión " + GpsBus.accuracyText() + ")?"
            gpsCaptureStatus = "Esperando confirmación para reemplazar coordenadas"
            if (!coordsConfirm.visible) coordsConfirm.open()
            return true
        }
        return _applyCoordsFromGps(targetDocId, requestSerial)
    }

    function _consumeNativeGpsFix(requireNewTimestamp, targetDocId, requestSerial) {
        if (!_gpsRequestMatches(targetDocId, requestSerial)
                || !_nativeGpsIsValid(requireNewTimestamp, gpsCaptureAccuracyTargetMeters))
            return false
        _publishNativeGpsToBus()
        return _applyOrConfirmCoordsFromGps(targetDocId, requestSerial)
    }

    function _requestFreshNativeGps(targetDocId, requestSerial) {
        if (!_gpsRequestMatches(targetDocId, requestSerial)) return
        requestGpsRefresh()

        if (!Perms.nativePermissionGranted) {
            gpsCaptureStatus = "Solicitando permiso de ubicación precisa…"
            return
        }
        if (!Perms.isLocationServiceEnabled()) {
            _gpsFailure("GPS desactivado", "Activa la ubicación del dispositivo e inténtalo nuevamente.")
            return
        }

        var callbackDocId = String(targetDocId || "")
        var callbackSerial = requestSerial
        Qt.callLater(function() {
            if (!root._gpsRequestMatches(callbackDocId, callbackSerial)) return
            try {
                Perms.refreshNativeLocation()
                root.gpsCaptureStatus = "Buscando una coordenada actual…"
            } catch (error) {
                root._gpsFailure("Proveedor GPS no disponible",
                                 "No se pudo solicitar una lectura al proveedor de ubicación.")
            }
        })
    }

    function _tryUpdateCoordsFromGps() {
        if (_documentClosing || !doc || doc.closed === true) return
        _gpsRequestSerial++
        var requestSerial = _gpsRequestSerial
        var targetDocId = _docInstanceId(doc)
        if (!targetDocId.length) return
        _pendingGpsDocId = targetDocId
        gpsCaptureTone = "capturing"
        gpsCaptureStatus = "Preparando captura GPS…"
        _gpsDeadlineAtMs = Date.now() + gpsCaptureDeadlineMs
        gpsCaptureActive = true

        _gpsBaselineTimestampMs = Number(Perms.nativeTimestampMs) || 0
        if (Perms.nativePermissionGranted
                && _nativeGpsIsValid(false, gpsCaptureAccuracyTargetMeters)
                && Date.now() - Number(Perms.nativeTimestampMs) <= 30000) {
            _publishNativeGpsToBus()
            _applyOrConfirmCoordsFromGps(targetDocId, requestSerial)
            return
        }
        _requestFreshNativeGps(targetDocId, requestSerial)
    }

    function scrollToTop() {
        if (typeof vFlick !== "undefined")
            vFlick.contentY = 0
    }

    property bool _ready: false

    property string _navigationDocId: ""
    property string _boundDocId: ""
    onDocChanged: {
        // Solo un cambio de IDENTIDAD de ficha reinicia la navegación. Una
        // reemisión del mismo documento (binding var de currentDoc al volver de la
        // cámara, guardar o sincronizar) no debe llevar a General.
        var boundId = _docInstanceId(doc)
        if (boundId.length && boundId === _boundDocId) return
        _boundDocId = boundId
        _navigationDocId = ""
        _photoProcessing = ({})   // los avisos de otra ficha ya no llegan aquí
        _photoLocalPreviews = ({})
        if (aiReviewDialog.opened) aiReviewDialog.close()
        invalidateReview()

        if (identityPopup.opened) identityPopup.close()
        if (stratumSheet.opened) stratumSheet.close()
        stageIndex = 0
        sectionNavCurrent = 1
        selectedStratum = -1
        profileMode = "overview"
        identityEditing = false
        reviewNotesEditing = false
        if (!_ready) return
        var changedDocId = _docInstanceId(doc)
        if (_pendingGpsDocId.length && _pendingGpsDocId !== changedDocId) {
            _gpsRequestSerial++
            gpsCaptureActive = false
            _pendingGpsDocId = ""
            gpsCaptureTone = "idle"
            gpsCaptureStatus = "Captura GPS cancelada al cambiar de ficha"
        }
        if (_pendingPhotoDocId.length && _pendingPhotoDocId !== changedDocId) {
            if (tsDlg.visible) tsDlg.close()
            _releasePendingPhotoImport()
        }
        if (_pendingLogoDocId.length && _pendingLogoDocId !== changedDocId) {
            _releasePendingLogoRequest()
            logoFeedbackText = "Selección de logo cancelada al cambiar de ficha"
        }
        _documentClosing = false
        if (doc && doc.closed !== true) {
            importFromDoc()
            Qt.callLater(root._recoverInterruptedCapture)
        } else {
            resetForm()
        }

        // ✅ clave:
        _applyPendingToDocIfAny()
        _applyPendingToUI()
    }

    function prepareForDocumentClose(targetDoc) {
        if (!targetDoc) return
        var targetDocId = _docInstanceId(targetDoc)

        if (_pendingGpsDocId.length && _pendingGpsDocId === targetDocId) {
            _gpsRequestSerial++
            gpsCaptureActive = false
            _pendingGpsDocId = ""
            gpsCaptureTone = "idle"
            gpsCaptureStatus = "Captura GPS cancelada al cerrar la ficha"
        }

        if (_pendingPhotoDocId.length && _pendingPhotoDocId === targetDocId) {
            if (tsDlg.visible) tsDlg.close()
            _releasePendingPhotoImport()
            photoFeedbackText = "Selección de fotografía cancelada al cerrar la ficha"
        }
        if (_pendingLogoDocId.length && _pendingLogoDocId === targetDocId) {
            _releasePendingLogoRequest()
            logoFeedbackText = "Selección de logo cancelada al cerrar la ficha"
        }

        if (doc === targetDoc) {
            _documentClosing = true
            _gpsRequestSerial++
            gpsCaptureActive = false
            _pendingGpsDocId = ""
            if (tsDlg.visible) tsDlg.close()
        }
    }

    function _releasePendingPhotoImport() {
        _photoRequestSerial++
        _photoDialogOpenPending = false
        if (_pendingPickedUrl && _pendingPickedUrl.toString().length)
            Perms.releaseImportedPhoto(_pendingPickedUrl)
        _pendingPickedUrl = ""
        _pendingPhotoDoc = null
        _pendingPhotoDocId = ""
        _pendingPhotoSourceKind = ""
        _photoRequestPending = false
    }

    function _openPendingPhotoDialogWhenReady() {
        if (!_photoDialogOpenPending || !_photoRequestPending) return
        if (Qt.application.state !== Qt.ApplicationActive) return

        var expectedDocId = _pendingPhotoDocId
        var expectedSerial = _photoRequestSerial
        Qt.callLater(function() {
            if (!root._photoDialogOpenPending
                    || !root._photoRequestPending
                    || Qt.application.state !== Qt.ApplicationActive
                    || expectedDocId !== root._pendingPhotoDocId
                    || expectedSerial !== root._photoRequestSerial)
                return
            root._photoDialogOpenPending = false
            tsDlg.openFor(expectedDocId, expectedSerial)
        })
    }

    function _beginPhotoRequest(idx, sourceKind) {
        if (_photoRequestPending || _logoRequestPending || _documentClosing) return
        if (!doc || doc.closed === true) {
            photoFeedbackText = "No hay una ficha abierta para incorporar la imagen"
            return
        }

        if (!commitPendingField()) return
        flushRequested()
        if (!doc.saveDraft()) { photoFeedbackText = "Error al guardar: " + doc.errorString; return }
        _releasePendingPhotoImport()
        _pendingStampIdx = idx
        _pendingPhotoDoc = doc
        _pendingPhotoDocId = _docInstanceId(doc)
        _photoRequestSerial++
        _pendingPhotoSourceKind = sourceKind
        _photoRequestPending = true
        photoFeedbackText = sourceKind === "camera"
                ? "Abriendo cámara del dispositivo…"
                : "Abriendo galería de imágenes…"

        if (sourceKind === "camera") {
            // Identidad estable de la ficha: si Android mata InGe+ con la
            // camara delante, la foto se recupera al reabrir esta ficha.
            if (Perms.setPhotoCaptureContext)
                Perms.setPhotoCaptureContext(String(doc.fileUrl))
            Perms.capturePhoto(idx)
        } else {
            Perms.pickPhoto(idx)
        }
    }

    // Captura interrumpida por la muerte del proceso (camara del OEM con poca
    // RAM): se ofrece por el mismo camino que una captura normal, con el
    // dialogo de datos impresos, y solo en la ficha que la pidio.
    function _recoverInterruptedCapture() {
        if (!doc || doc.closed === true || _photoRequestPending || _logoRequestPending
                || _documentClosing || typeof Perms === "undefined" || !Perms.pendingCaptureSlot)
            return
        var contextKey = String(doc.fileUrl)
        var slot = Perms.pendingCaptureSlot(contextKey)
        if (slot < 0)
            return
        _releasePendingPhotoImport()
        _pendingStampIdx = slot
        _pendingPhotoDoc = doc
        _pendingPhotoDocId = _docInstanceId(doc)
        _photoRequestSerial++
        _pendingPhotoSourceKind = "camera"
        _photoRequestPending = true
        photoFeedbackText = "Recuperando la fotografía tomada antes de que Android cerrara InGe+…"
        console.info("[InGe+ M09] recovering interrupted camera capture slot=" + slot)
        Perms.recoverPendingCapture(contextKey)
    }

    onRequestCapturePhoto: function(idx) {
        _beginPhotoRequest(idx, "camera")
    }

    onRequestPickPhoto: function(idx) {
        _beginPhotoRequest(idx, "gallery")
    }

    onRequestClearPhoto: function(idx) {
        if (!doc || doc.closed || !commitPendingField()) return
        flushRequested()
        doc.clearPhoto(idx)
        invalidateReview()
        photoFeedbackText = doc.errorString.length ? "Error al guardar: " + doc.errorString
                                                  : "Fotografía eliminada de la categoría"
    }

    function _commitPendingPhoto(withPrintedData) {
        var targetDoc = root._pendingPhotoDoc
        var commitDocId = root._pendingPhotoDocId

        if (!root._photoRequestPending
                || !targetDoc
                || targetDoc.closed === true
                || root._documentClosing
                || !commitDocId.length
                || root._docInstanceId(targetDoc) !== commitDocId
                || root._docInstanceId(root.doc) !== commitDocId
                || !root._pendingPickedUrl
                || !root._pendingPickedUrl.toString().length) {
            root._releasePendingPhotoImport()
            return false
        }

        if (withPrintedData) root._syncTimestampNow()
        var slotIdx = root._pendingStampIdx
        var acceptedMs = Date.now()
        // Altitud/posición propias de la foto: solo si ya hay un fix fresco del
        // dispositivo (no se enciende el GPS). C++ la descarta si no es reciente.
        if (targetDoc.setNextPhotoCaptureLocation && typeof Perms !== "undefined" && Perms.nativeHasFix)
            targetDoc.setNextPhotoCaptureLocation({ latitude: Number(Perms.nativeLatitude), longitude: Number(Perms.nativeLongitude),
                                                    altitude: Number(Perms.nativeAltitude), timestampMs: Number(Perms.nativeTimestampMs) })
        var outUrl = targetDoc.persistPhoto(slotIdx,
                                             root._pendingPickedUrl, withPrintedData)
        if (outUrl && outUrl.toString().length) {
            // El original ya está copiado; la imagen con/sin datos se genera fuera del
            // hilo de UI y la ficha se actualiza en onPhotoPersisted (ahí se encola la
            // publicación, una sola vez). La UI sigue respondiendo mientras tanto.
            var processing = Object.assign({}, root._photoProcessing)
            processing[slotIdx] = withPrintedData ? "stamped" : "plain"
            root._photoProcessing = processing
            var previews = Object.assign({}, root._photoLocalPreviews)
            previews[slotIdx] = { url: outUrl, docId: commitDocId, acceptedMs: acceptedMs, ready: false }
            root._photoLocalPreviews = previews
            root.photoFeedbackText = withPrintedData
                    ? "Procesando fotografía con datos de ubicación…"
                    : "Procesando fotografía…"
            console.info("[InGe+ M09] photo accepted instanceId=" + commitDocId
                         + " stamped=" + (withPrintedData ? "YES" : "NO"))
            root._releasePendingPhotoImport()
            return true
        }

        root._releasePendingPhotoImport()
        root.showInfo("No se pudo guardar la fotografía",
                      "La imagen no era válida o no pudo copiarse al almacenamiento local.")
        return false
    }

    Connections {
        target: Qt.application
        function onStateChanged() {
            if (Qt.application.state === Qt.ApplicationActive)
                root._openPendingPhotoDialogWhenReady()
        }
    }

    Connections {
        target: Perms
        ignoreUnknownSignals: true

        function onPhotoSelected(targetIdx, localUrl, sourceKind) {
            if (root._logoRequestPending
                    && targetIdx === root._logoPickerIndex(root._pendingLogoPickTarget)
                    && sourceKind === "gallery") {
                root._persistPickedLogo(localUrl)
                return
            }

            var targetDoc = root._pendingPhotoDoc
            var targetDocId = root._pendingPhotoDocId
            if (!root._photoRequestPending
                    || !targetDoc
                    || targetDoc.closed === true
                    || !targetDocId.length
                    || root._docInstanceId(targetDoc) !== targetDocId
                    || root._docInstanceId(root.doc) !== targetDocId
                    || targetIdx !== root._pendingStampIdx
                    || sourceKind !== root._pendingPhotoSourceKind) {
                Perms.releaseImportedPhoto(localUrl)
                return
            }
            root._pendingPickedUrl = localUrl
            root._pendingPhotoSourceKind = sourceKind
            root.photoFeedbackText = "Imagen recibida · elige si deseas imprimir los datos de ubicación"
            // El resultado puede llegar desde onActivityResult antes de que la
            // Surface de Qt esté completamente reexpuesta. No abrir un Dialog
            // durante ese hueco de lifecycle: esperar ApplicationActive.
            root._photoDialogOpenPending = true
            root._openPendingPhotoDialogWhenReady()
        }

        function onPhotoSelectionCanceled(targetIdx, sourceKind) {
            if (root._logoRequestPending
                    && targetIdx === root._logoPickerIndex(root._pendingLogoPickTarget)
                    && sourceKind === "gallery") {
                root.logoFeedbackText = "Selección de logo cancelada"
                root._releasePendingLogoRequest()
                return
            }

            if (root._photoRequestPending
                    && root._pendingPhotoDocId === root._docInstanceId(root.doc)
                    && targetIdx === root._pendingStampIdx
                    && sourceKind === root._pendingPhotoSourceKind) {
                root.photoFeedbackText = "Selección cancelada"
                root._releasePendingPhotoImport()
            }
        }

        function onPhotoSelectionError(targetIdx, code, message) {
            if (root._logoRequestPending
                    && targetIdx === root._logoPickerIndex(root._pendingLogoPickTarget)) {
                root._releasePendingLogoRequest()
                root.logoFeedbackText = ""
                root.showInfo("No se pudo cargar el logo", message)
                return
            }

            if (!root._photoRequestPending
                    || root._pendingPhotoDocId !== root._docInstanceId(root.doc)
                    || targetIdx !== root._pendingStampIdx) {
                return
            }
            root._releasePendingPhotoImport()
            root.showInfo("No se pudo cargar la fotografía", message)
        }

        function onNativePermissionChanged() {
            if (!root.gpsCaptureActive) return
            if (Perms.nativePermissionStatus === "denied") {
                root._gpsFailure("Permiso de ubicación denegado",
                                 "Concede el permiso de ubicación precisa para actualizar la ficha.")
            } else if (Perms.nativePermissionGranted) {
                root._requestFreshNativeGps(root._pendingGpsDocId,
                                            root._gpsRequestSerial)
            }
        }

        function onNativeLocationChanged() {
            if (!Perms.nativeHasFix || !root._nativeGpsIsValid(false, 5000))
                return

            if (!root.gpsCaptureActive) {
                // Main.qml ya publica el fix aceptado en GpsBus. Aquí solo se
                // elimina un error viejo, sin modificar automáticamente la ficha.
                if (root.gpsCaptureTone === "error") {
                    root.gpsCaptureTone = "ready"
                    root.gpsCaptureStatus = "Ubicación disponible · pulsa Actualizar coordenadas"
                }
                return
            }
            var accuracy = Number(Perms.nativeAccuracy)
            if (isFinite(accuracy) && accuracy > root.gpsCaptureAccuracyTargetMeters) {
                root.gpsCaptureStatus = "Mejorando precisión GPS · ±"
                        + Number(accuracy).toFixed(1) + " m"
                return
            }
            var callbackDocId = root._pendingGpsDocId
            var callbackSerial = root._gpsRequestSerial
            Qt.callLater(function() {
                root._consumeNativeGpsFix(true, callbackDocId, callbackSerial)
            })
        }

        function onNativeImmediateRequestPendingChanged() {
            if (!root.gpsCaptureActive || Perms.nativeImmediateRequestPending) return
            var callbackDocId = root._pendingGpsDocId
            var callbackSerial = root._gpsRequestSerial
            Qt.callLater(function() {
                if (!root._gpsRequestMatches(callbackDocId, callbackSerial)) return

                // Primero exige una lectura posterior al clic. Si el proveedor
                // confirmó la misma posición por estar quieto, acepta también
                // el fix reciente y válido para evitar un falso timeout.
                if (root._consumeNativeGpsFix(true, callbackDocId, callbackSerial)) return
                if (root._consumeNativeGpsFix(false, callbackDocId, callbackSerial)) return

                root.gpsCaptureStatus = "Esperando una coordenada con precisión de hasta 25 m…"
            })
        }

        function onNativeLocationStatusChanged() {
            if (!root.gpsCaptureActive) return
            var status = String(Perms.nativeLocationStatus || "")
            var detail = String(Perms.nativeLocationError || "")
            if (status === "service_disabled") {
                root._gpsFailure("GPS desactivado",
                                 detail.length ? detail : "Activa la ubicación del dispositivo.")
            } else if (status === "permission_denied") {
                root._gpsFailure("Permiso de ubicación denegado",
                                 detail.length ? detail : "Concede el permiso de ubicación precisa.")
            } else if (status === "no_provider") {
                root._gpsFailure("Proveedor GPS no disponible",
                                 detail.length ? detail : "Android no encontró un proveedor de ubicación disponible.")
            } else if (status === "searching" || status === "starting") {
                root.gpsCaptureStatus = "Buscando una coordenada actual…"
            }
        }
    }

    Timer {
        interval: 200
        repeat: true
        running: root.gpsCaptureActive
        onTriggered: {
            var id = root._pendingGpsDocId
            var serial = root._gpsRequestSerial
            if (!root._gpsRequestMatches(id, serial)) return
            if (root._consumeNativeGpsFix(false, id, serial)) return
            if (Date.now() >= root._gpsDeadlineAtMs)
                root._gpsFailure("Tiempo de espera agotado",
                    "No se recibió un GPS con precisión de hasta 25 m en 15 segundos.", false)
        }
    }

    Dialog {
        id: replaceDlg
        property Item glassBackdropItem: null
        parent: Overlay.overlay
        modal: true
        title: "Ya existe un archivo"
        standardButtons: Dialog.NoButton
        palette.windowText: root.cText
        palette.text: root.cText
        palette.buttonText: root.cText
        palette.base: root.cField
        palette.button: root.cSurfaceAlt
        palette.highlight: root.cAccent
        Overlay.modal: GenGlassScrim { popupItem: replaceDlg }
        background: GenPopupGlass { popupItem: replaceDlg; surfaceName: "calicata-replace-dialog" }
        header: GenDialogTitle { text: replaceDlg.title }

        property string dstPretty: ""

        width: Math.min(560, parent ? parent.width * 0.94 : 560)
        height: 260
        x: parent ? Math.round((parent.width  - width)  / 2) : 0
        y: parent ? Math.round((parent.height - height) / 2) : 0

        contentItem: ColumnLayout {
            anchors.fill: parent
            anchors.margins: 16
            spacing: 12

            Label {
                Layout.fillWidth: true
                wrapMode: Text.WrapAnywhere
                text: "Ya existe una ficha con ese nombre:\n\n" + replaceDlg.dstPretty +
                      "\n\n¿Qué deseas hacer?"
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 10

                GenDialogButton {
                    soft: true
                    text: "Crear nuevo"
                    onClicked: { replaceDlg.close(); root._renameMode = "copy"; root._doRenameNow(); }
                }
                GenDialogButton {
                    primary: true
                    text: "Reemplazar"
                    onClicked: { replaceDlg.close(); root._renameMode = "replace"; root._doRenameNow(); }
                }
                GenDialogButton {
                    text: "Cancelar"
                    onClicked: replaceDlg.close()
                }
            }
        }
    }

    // Decisión del técnico ante una cota automática con discrepancia o frente a una
    // cota MANUAL: "Usar automática" o "Ingresar manual" (nunca se reemplaza sola).
    Dialog {
        id: altitudeReplaceDialog
        property Item glassBackdropItem: null
        parent: Overlay.overlay
        modal: true
        title: "Cota automática"
        standardButtons: Dialog.NoButton
        palette.windowText: root.cText
        palette.text: root.cText
        palette.buttonText: root.cText
        palette.base: root.cField
        palette.button: root.cSurfaceAlt
        palette.highlight: root.cAccent
        Overlay.modal: GenGlassScrim { popupItem: altitudeReplaceDialog }
        background: GenPopupGlass { popupItem: altitudeReplaceDialog; surfaceName: "calicata-altitude-dialog" }
        header: GenDialogTitle { text: altitudeReplaceDialog.title }
        width: Math.min(560, parent ? parent.width * 0.94 : 560)
        x: parent ? Math.round((parent.width  - width)  / 2) : 0
        y: parent ? Math.round((parent.height - height) / 2) : 0
        onClosed: root._pendingAltitudeDecision = null

        contentItem: ColumnLayout {
            spacing: 12
            Label {
                Layout.fillWidth: true
                Layout.margins: 16
                wrapMode: Text.WordWrap
                text: root._pendingAltitudeDecision
                      ? Elevation.decisionText(root.doc ? root.doc.header : {}, root._pendingAltitudeDecision) : ""
            }
            RowLayout {
                Layout.fillWidth: true
                Layout.leftMargin: 16
                Layout.rightMargin: 16
                Layout.bottomMargin: 16
                spacing: 10
                GenDialogButton {
                    text: "Ingresar manual"
                    onClicked: {
                        altitudeReplaceDialog.close()
                        root.elevationStatus = "Cota automática descartada: escribe la cota en Z UTM / Cota."
                    }
                }
                GenDialogButton {
                    primary: true
                    text: "Usar automática"
                    onClicked: {
                        var decision = root._pendingAltitudeDecision
                        altitudeReplaceDialog.close()
                        if (decision) root._applyAltitudePatch(decision.patch)
                    }
                }
            }
        }
    }

    Dialog {
        id: coordsConfirm
        property Item glassBackdropItem: null
        parent: Overlay.overlay
        modal: true
        title: "Capturar ubicación actual"
        standardButtons: Dialog.NoButton
        palette.windowText: root.cText
        palette.text: root.cText
        palette.buttonText: root.cText
        palette.base: root.cField
        palette.button: root.cSurfaceAlt
        palette.highlight: root.cAccent
        Overlay.modal: GenGlassScrim { popupItem: coordsConfirm }
        background: GenPopupGlass { popupItem: coordsConfirm; surfaceName: "calicata-coords-dialog" }
        header: GenDialogTitle { text: coordsConfirm.title }

        implicitWidth: Math.min(560, parent ? parent.width * 0.94 : 560)
        implicitHeight: Math.min(420, parent ? parent.height * 0.70 : 420)
        x: parent ? Math.round((parent.width  - width)  / 2) : 0
        y: parent ? Math.round((parent.height - height) / 2) : 0

        contentItem: Item {
            implicitWidth: coordsConfirm.implicitWidth
            implicitHeight: coordsConfirm.implicitHeight

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 16
                spacing: 10

                Label {
                    id: coordsConfirmText
                    Layout.fillWidth: true
                    wrapMode: Text.WordWrap
                }
            }
        }

        onAccepted: {
            var targetDocId = root._pendingGpsDocId.length
                    ? root._pendingGpsDocId : root._docInstanceId(root.doc)
            var requestSerial = root._pendingGpsDocId.length
                    ? root._gpsRequestSerial : 0
            root._applyCoordsFromGps(targetDocId, requestSerial)
        }
        onRejected: {
            root._gpsRequestSerial++
            root.gpsCaptureActive = false
            root.gpsCaptureTone = "idle"
            root.gpsCaptureStatus = "Reemplazo de coordenadas cancelado"
            root._pendingGpsDocId = ""
        }
    }

    // Aviso del formulario (showInfo): mismo lenguaje y animación que los
    // emergentes de General; superficie mate (GenPopup), sin Liquid Glass.
    GenPopup {
        id: infoDlg
        property string title: "Info"
        preferredWidth: root.dp(400)
        preferredHeight: infoDlgColumn.implicitHeight + topPadding + bottomPadding
        padding: root.dp(20)

        contentItem: ColumnLayout {
            id: infoDlgColumn
            spacing: root.dp(12)
            RowLayout {
                Layout.fillWidth: true
                spacing: root.dp(12)
                GenIconBadge {
                    Layout.preferredWidth: root.dp(40)
                    Layout.preferredHeight: root.dp(40)
                    Layout.alignment: Qt.AlignTop
                    iconName: "status.warning"
                    accent: root.cGenOrange
                    accentSoft: root.cGenOrangeSoft
                }
                Label {
                    Layout.fillWidth: true
                    Layout.alignment: Qt.AlignVCenter
                    text: infoDlg.title
                    color: root.cText
                    font.pixelSize: root.sp(17)
                    font.bold: true
                    wrapMode: Text.WordWrap
                }
            }
            // Mensajes largos (rutas) desplazan dentro; el aviso no crece sin límite.
            Flickable {
                Layout.fillWidth: true
                Layout.preferredHeight: Math.min(infoText.implicitHeight, root.dp(320))
                contentWidth: width
                contentHeight: infoText.implicitHeight
                interactive: contentHeight > height
                boundsBehavior: Flickable.StopAtBounds
                clip: true
                Label {
                    id: infoText
                    width: parent.width
                    color: root.cMuted
                    font.pixelSize: root.fsField
                    wrapMode: Text.WrapAtWordBoundaryOrAnywhere   // ✅ rutas largas no se salen
                }
            }
            GenDialogButton {
                Layout.topMargin: root.dp(4)
                text: "Entendido"
                primary: true
                onClicked: infoDlg.close()
            }
        }
    }
    GenPopup {
        id: deleteConfirm
        preferredWidth: root.dp(420)
        preferredHeight: root.dp(280)

        contentItem: ColumnLayout {
            spacing: root.dp(14)
            GenDialogHeader {
                title: "Eliminar estrato"
                subtitle: root._pendingDeleteIdx >= 0 ? "Estrato " + (root._pendingDeleteIdx + 1) : ""
                onCloseRequested: deleteConfirm.close()
            }
            Text {
                Layout.fillWidth: true
                text: "Se perderá la información registrada en este estrato."
                color: root.cText
                font.pixelSize: root.fsField
                wrapMode: Text.WordWrap
            }
            Item { Layout.fillHeight: true }
            RowLayout {
                Layout.fillWidth: true
                spacing: root.dp(10)
                GenDialogButton {
                    text: "Cancelar"
                    onClicked: deleteConfirm.close()
                }
                GenDialogButton {
                    text: "Sí, eliminar"
                    iconName: "action.delete"
                    primary: true
                    accent: root.flow ? root.flow.theme.error : "#B4232E"
                    onClicked: {
                        var idx = root._pendingDeleteIdx
                        root._pendingDeleteIdx = -1
                        deleteConfirm.close()
                        if (idx >= 0)
                            root.removeCorte(idx)
                    }
                }
            }
        }

        onClosed: {
            if (root._pendingDeleteIdx >= 0)
                root._pendingDeleteIdx = -1
        }
    }

    Connections {
        id: docConnections
        target: root.doc
        enabled: !root._documentClosing && target !== null && target.closed !== true
        ignoreUnknownSignals: true

        function onDataChanged() {
            if (root._loading || root._syncingDocument || root._applyingLivePatch
                    || (root.operationHost && root.operationHost._remoteLoadingDocId.length)
                    || root._documentClosing
                    || !docConnections.target
                    || docConnections.target.closed === true
                    || root._docInstanceId(root.doc)
                       !== root._docInstanceId(docConnections.target)) return
            if (root.dirty || root._pendingCommitFields.length) return    // si el usuario está editando, no re-importes
            root.importFromDoc()
        }
        function onDirtyChanged() {
            if (!docConnections.target || docConnections.target.closed === true) return
            root.setDirty(root.doc ? root.doc.dirty : false)
        }
        // Fin de la importación en segundo plano: copia local confirmada → publicar
        // (asíncrono, outbox de Media). Un fallo local nunca toca la foto anterior.
        function onPhotoPersisted(idx, url, error) {
            var processing = Object.assign({}, root._photoProcessing)
            var mode = processing[idx]
            delete processing[idx]
            root._photoProcessing = processing
            var previews = Object.assign({}, root._photoLocalPreviews)
            var preview = previews[idx]
            delete previews[idx]
            root._photoLocalPreviews = previews
            if (!docConnections.target || docConnections.target.closed === true) return
            if (error && String(error).length) {
                root.photoFeedbackText = ""
                root.showInfo("No se pudo guardar la fotografía", String(error) + " La fotografía anterior se conserva.")
                return
            }
            if (preview) console.info("[InGe+ M09] LOCAL_COMMIT_OK instanceId=" + preview.docId
                                      + " idx=" + idx + " elapsedMs=" + (Date.now() - preview.acceptedMs))
            console.info("[InGe+ M09] photo commit instanceId=" + root._docInstanceId(docConnections.target)
                         + " stamped=" + (mode === "stamped" ? "YES" : "NO"))
            root._queuePhotoSync(docConnections.target, idx)
            root.invalidateReview()
            root.photoFeedbackText = mode === "stamped"
                    ? "Fotografía incorporada con datos de ubicación"
                    : "Fotografía incorporada sin datos impresos"
        }
        function onDisplayNameChanged() {
            if (docConnections.target && docConnections.target.closed !== true
                    && root._docInstanceId(root.doc)
                       === root._docInstanceId(docConnections.target)) {
                root.titleSuggested(docConnections.target.displayName)
            }
        }
    }

    // Una sola decisión: con datos / sin datos / cancelar (sin botones estándar No/Yes).
    Popup {
        id: tsDlg
        property Item glassBackdropItem: null
        property string targetDocId: ""
        property int requestSerial: 0
        parent: Overlay.overlay
        modal: true
        dim: true
        focus: true
        closePolicy: Popup.NoAutoClose
        padding: root.dp(18)
        background: GenPopupGlass { popupItem: tsDlg; surfaceName: "calicata-photo-data-dialog" }
        Overlay.modal: GenGlassScrim { popupItem: tsDlg }
        enter: Transition {
            ParallelAnimation {
                NumberAnimation { property: "opacity"; from: 0; to: 1; duration: root.flow ? root.flow.duration(200) : 200; easing.type: Easing.OutCubic }
                NumberAnimation { property: "scale"; from: 0.94; to: 1; duration: root.flow ? root.flow.duration(300) : 300; easing.type: Easing.OutQuint }
            }
        }
        exit: Transition {
            NumberAnimation { property: "opacity"; from: 1; to: 0; duration: root.flow ? root.flow.duration(160) : 160; easing.type: Easing.InCubic }
        }

        width: Math.min(root.dp(430), parent ? parent.width - root.dp(32) : root.dp(430))
        x: parent ? Math.round((parent.width - width) / 2) : 0
        y: parent ? Math.round((parent.height - height) / 2) : 0

        function openFor(expectedDocId, expectedSerial) {
            var targetDoc = root._pendingPhotoDoc || root.doc
            if (!targetDoc
                    || targetDoc.closed === true
                    || !expectedDocId
                    || root._docInstanceId(targetDoc) !== expectedDocId
                    || root._docInstanceId(root.doc) !== expectedDocId
                    || expectedSerial !== root._photoRequestSerial) {
                root._releasePendingPhotoImport()
                return
            }
            targetDocId = expectedDocId
            requestSerial = expectedSerial
            open()
        }

        // withData: true/false = guardar; null = cancelar (libera la importación pendiente).
        function resolve(withData) {
            var expectedDocId = targetDocId
            var expectedSerial = requestSerial
            targetDocId = ""
            requestSerial = 0
            close()
            if (withData === null
                    || expectedDocId !== root._pendingPhotoDocId
                    || expectedSerial !== root._photoRequestSerial) {
                root._releasePendingPhotoImport()
                return
            }
            root._commitPendingPhoto(withData === true)
        }

        contentItem: ColumnLayout {
            spacing: root.dp(10)
            Text {
                Layout.fillWidth: true
                text: "¿Rellenar datos en la foto?"
                color: root.cText
                font.pixelSize: root.sp(17)
                font.bold: true
                wrapMode: Text.WordWrap
            }
            Text {
                Layout.fillWidth: true
                Layout.bottomMargin: root.dp(4)
                text: "Los datos de la ficha (coordenadas, código, proyecto, fecha) se imprimen en la derivada; la original se conserva."
                color: root.cMuted
                font.pixelSize: root.sp(12)
                wrapMode: Text.WordWrap
            }
            PhotoPill { primary: true; text: "Guardar con datos"; onClicked: tsDlg.resolve(true) }
            PhotoPill { text: "Guardar sin datos"; onClicked: tsDlg.resolve(false) }
            PhotoPill { text: "Cancelar"; onClicked: tsDlg.resolve(null) }
        }

        onClosed: {
            targetDocId = ""
            requestSerial = 0
        }
    }

    Dialog {
        id: resourcesPicker
        property Item glassBackdropItem: null
        parent: Overlay.overlay
        modal: true
        title: "Elegir logo (Recursos)"
        standardButtons: Dialog.Ok | Dialog.Cancel
        palette.windowText: root.cText
        palette.text: root.cText
        palette.buttonText: root.cText
        palette.base: root.cField
        palette.button: root.cSurfaceAlt
        palette.highlight: root.cAccent
        Overlay.modal: GenGlassScrim { popupItem: resourcesPicker }
        background: GenPopupGlass { popupItem: resourcesPicker; surfaceName: "calicata-resources-dialog" }
        header: GenDialogTitle { text: resourcesPicker.title }
        footer: GenDialogButtonBox { standardButtons: resourcesPicker.standardButtons }

        padding: 12

        width:  Math.min(460, parent ? parent.width * 0.94 : 460)
        height: Math.min(640, parent ? parent.height * 0.90 : 640)
        x: parent ? Math.max(8, Math.round((parent.width  - width)  / 2)) : 0
        y: parent ? Math.max(8, Math.round((parent.height - height) / 2)) : 0

        // "mtc" | "pro"
        property string pickTarget: ""
        property string selectedFileName: ""
        property url selectedUrl: ""

        function _folderUrlForResources() {
            var p = (docsCtl.resourcesPath || "").toString().replace(/\\/g, "/")
            if (!p.length) return ""
            if (!p.endsWith("/")) p += "/"
            var url = (Qt.platform.os === "windows") ? ("file:///" + p) : ("file://" + p)
            return encodeURI(url)
        }

        FolderListModel {
            id: resModel
            folder: resourcesPicker._folderUrlForResources()
            nameFilters: ["*.png", "*.jpg", "*.jpeg", "*.webp", "*.bmp"]
            showDirs: false
            showFiles: true
            showDotAndDotDot: false
            sortField: FolderListModel.Name
        }

        contentItem: ColumnLayout {
            spacing: 10

            Label {
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                color: root.cMuted
                text: (docsCtl.resourcesPath && docsCtl.resourcesPath.length)
                      ? ("Selecciona un logo dentro de:\n" + root._prettyFromUserRoot(docsCtl.resourcesPath))
                      : "No se pudo ubicar la carpeta Recursos."
            }

            ListView {
                id: resList
                Layout.fillWidth: true
                Layout.preferredHeight: Math.min(240, resourcesPicker.height * 0.35)
                clip: true
                model: resModel
                currentIndex: -1

                delegate: Item {
                    width: resList.width
                    height: 44

                    Rectangle {
                        anchors.fill: parent
                        radius: 10
                        color: (index === resList.currentIndex)
                               ? (root.flow ? root.flow.theme.selected : root.cSurfaceAlt)
                               : "transparent"
                    }

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.left: parent.left
                        anchors.leftMargin: 10
                        anchors.right: parent.right
                        anchors.rightMargin: 10
                        text: fileName
                        elide: Text.ElideRight
                        color: root.cText
                    }

                    MouseArea {
                        anchors.fill: parent
                        onClicked: {
                            resList.currentIndex = index
                            resourcesPicker.selectedFileName = fileName
                            resourcesPicker.selectedUrl = fileUrl   // ✅ role correcto
                        }
                    }
                }
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.fillHeight: true
                radius: 12
                color: "transparent"
                CalicataLiquidGlass { dark: root.darkMode; accent: root.cGenBlue; danger: root.flow ? root.flow.theme.error : "#D9483B"; anchors.fill: parent; radius: parent.radius }

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 10
                    spacing: 10

                    Label {
                        Layout.fillWidth: true
                        text: resourcesPicker.selectedFileName.length
                              ? resourcesPicker.selectedFileName
                              : "Vista previa"
                        elide: Text.ElideRight
                        color: root.cMuted
                    }

                    Image {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        fillMode: Image.PreserveAspectFit
                        asynchronous: true
                        source: resourcesPicker.selectedUrl
                        sourceSize: Qt.size(512, 512)
                    }
                }
            }
        }

        onOpened: {
            ensureDocsRoots()

            selectedFileName = ""
            selectedUrl = ""
            resList.currentIndex = -1

            // ✅ refresca folder si resourcesPath recién se calculó
            resModel.folder = _folderUrlForResources()
        }

        onAccepted: {
            if (!selectedFileName || !selectedFileName.length) return

            var rel = "Recursos/" + selectedFileName
            root._storeLogoRelative(pickTarget, rel)
            root.logoFeedbackText = "Logo elegido desde Recursos"
        }
    }


    // Ranura de logo del panel Identidad del reporte (misma pieza para
    // entidad y proyecto). Acciones reales: adjuntar (también tocando la
    // vista previa), predeterminado, dejar vacío (solo con logo) e historial.
    component GenLogoSlot: Rectangle {
        id: genLogoSlot
        property string target: ""
        property string title: ""
        property string subtitle: ""
        property bool hasLogo: false
        property url logoSource: ""
        // Los predeterminados son ICONO_LOGO_MTC / INGEMA_LOGO_COMPLETO (_useDefaultLogo).
        readonly property string logoState: {
            if (!genLogoSlot.hasLogo) return "Sin logo"
            var s = String(genLogoSlot.logoSource)
            return s.indexOf("ICONO_LOGO_MTC") >= 0 || s.indexOf("INGEMA_LOGO_COMPLETO") >= 0
                    ? "Predeterminado" : "Personalizado"
        }
        Layout.fillWidth: true
        implicitHeight: genLogoLayout.implicitHeight + root.dp(24)
        radius: root.dp(14)
        color: "transparent"
        CalicataLiquidGlass { dark: root.darkMode; accent: root.cGenBlue; danger: root.flow ? root.flow.theme.error : "#D9483B"; anchors.fill: parent; radius: parent.radius }

        ColumnLayout {
            id: genLogoLayout
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: root.dp(12)
            spacing: root.dp(10)

            RowLayout {
                Layout.fillWidth: true
                spacing: root.dp(8)
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: root.dp(1)
                    Text {
                        Layout.fillWidth: true
                        text: genLogoSlot.title
                        color: root.cText
                        font.bold: true
                        font.pixelSize: root.fsField
                        elide: Text.ElideRight
                    }
                    Text {
                        Layout.fillWidth: true
                        text: genLogoSlot.subtitle
                        color: root.cMuted
                        font.pixelSize: root.fsLabel
                        elide: Text.ElideRight
                    }
                }
                Rectangle {
                    Layout.preferredHeight: root.dp(24)
                    Layout.preferredWidth: genLogoState.implicitWidth + root.dp(16)
                    radius: height / 2
                    color: genLogoSlot.hasLogo ? root.cGenGreenSoft : root.cGenOrangeSoft
                    Text {
                        id: genLogoState
                        anchors.centerIn: parent
                        text: genLogoSlot.logoState
                        color: genLogoSlot.hasLogo ? root.cGenGreen : root.cGenOrange
                        font.pixelSize: root.sp(11)
                        font.weight: Font.DemiBold
                    }
                }
            }

            Button {
                id: genLogoPreview
                Layout.fillWidth: true
                Layout.preferredHeight: root.dp(84)
                padding: 0
                enabled: !root._logoRequestPending
                Accessible.name: "Adjuntar " + genLogoSlot.title
                onClicked: root._beginLogoRequest(genLogoSlot.target)
                background: CalicataLiquidGlass {
                    dark: root.darkMode; accent: root.cGenBlue; danger: root.flow ? root.flow.theme.error : "#D9483B"
                    radius: root.dp(12)
                    pressed: genLogoPreview.down
                    focused: genLogoPreview.down
                    enabledLook: genLogoPreview.enabled
                }
                contentItem: Item {
                    Image {
                        anchors.fill: parent
                        anchors.margins: root.dp(8)
                        visible: genLogoSlot.hasLogo
                        source: genLogoSlot.logoSource
                        // Logo: miniatura acotada (no se decodifica a resolución completa).
                        sourceSize: Qt.size(512, 512)
                        fillMode: Image.PreserveAspectFit
                        asynchronous: true
                        cache: false
                    }
                    Column {
                        anchors.centerIn: parent
                        spacing: root.dp(4)
                        visible: !genLogoSlot.hasLogo
                        Components.FlowIcon {
                            anchors.horizontalCenter: parent.horizontalCenter
                            width: root.dp(24)
                            height: root.dp(24)
                            name: "calgen.identity"
                            flow: root.flow
                            tintColor: root.cMuted
                            activeTintColor: root.cMuted
                            inactiveOpacity: 1
                        }
                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: "Sin logo adjunto"
                            color: root.cMuted
                            font.pixelSize: root.fsLabel
                        }
                    }
                }
            }

            // Acciones compactas: mismo tamaño, radio e iconografía.
            RowLayout {
                Layout.fillWidth: true
                spacing: root.dp(8)
                Repeater {
                    model: [
                        { label: "Adjuntar", full: "Adjuntar", icon: "calgen.attach", action: "attach" },
                        { label: "Predeterminado", full: "Usar predeterminado", icon: "calgen.default", action: "default" },
                        { label: "Dejar vacío", full: "Dejar vacío", icon: "calgen.clear", action: "clear" }
                    ]
                    delegate: GenDialogButton {
                        required property var modelData
                        Layout.preferredWidth: 1
                        visible: modelData.action !== "clear" || genLogoSlot.hasLogo
                        stacked: true
                        soft: modelData.action !== "clear"
                        text: modelData.label
                        iconName: modelData.icon
                        Accessible.name: modelData.full
                        enabled: !root._logoRequestPending
                        onClicked: {
                            if (modelData.action === "attach") root._beginLogoRequest(genLogoSlot.target)
                            else if (modelData.action === "default") root._useDefaultLogo(genLogoSlot.target)
                            else root._deleteLogo(genLogoSlot.target)
                        }
                    }
                }
            }

            LogoHistoryStrip {
                Layout.fillWidth: true
                target: genLogoSlot.target
            }
        }
    }

    function _closeIdentityPopup() {
        identityPopup.close()
        if (root.reviewCorrectionActive)
            Qt.callLater(function() { root.finishReviewCorrection() })
    }

    GenPopup {
        id: identityPopup
        preferredHeight: root.dp(680)
        contentItem: ColumnLayout {
            spacing: root.dp(12)

            GenDialogHeader {
                title: "Identidad del reporte"
                subtitle: "Código, proyecto y logos usados al exportar"
                onCloseRequested: root._closeIdentityPopup()
            }

            ScrollView {
                id: identityScroll
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                contentWidth: availableWidth

                ColumnLayout {
                    id: mobileIdentitySection
                    width: identityScroll.availableWidth
                    spacing: root.dp(12)

                    Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: identityInfoColumn.implicitHeight + root.dp(20)
                        radius: root.dp(12)
                        color: "transparent"
                        CalicataLiquidGlass { dark: root.darkMode; accent: root.cGenBlue; danger: root.flow ? root.flow.theme.error : "#D9483B"; anchors.fill: parent; radius: parent.radius; tone: "tinted" }
                        ColumnLayout {
                            id: identityInfoColumn
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.top: parent.top
                            anchors.margins: root.dp(10)
                            spacing: root.dp(4)
                            Repeater {
                                model: [
                                    { label: "Código", value: txtCodigo.text || "Sin definir" },
                                    { label: "Proyecto", value: txtProjectFullName.text || "Sin definir" }
                                ]
                                delegate: RowLayout {
                                    required property var modelData
                                    Layout.fillWidth: true
                                    spacing: root.dp(8)
                                    Text {
                                        Layout.preferredWidth: root.dp(70)
                                        text: modelData.label
                                        color: root.cMuted
                                        font.pixelSize: root.fsLabel
                                    }
                                    Text {
                                        Layout.fillWidth: true
                                        text: modelData.value
                                        color: root.cText
                                        font.pixelSize: root.fsLabel
                                        font.weight: Font.DemiBold
                                        wrapMode: Text.WordWrap
                                    }
                                }
                            }
                            Text {
                                Layout.fillWidth: true
                                text: "Puedes editarlos en Datos generales."
                                color: root.cGenBlue
                                font.pixelSize: root.fsLabel
                                wrapMode: Text.WordWrap
                            }
                        }
                    }

                    Text {
                        Layout.fillWidth: true
                        visible: root.logoFeedbackText.length > 0
                        text: root.logoFeedbackText
                        color: root.cMuted
                        font.pixelSize: root.fsLabel
                        wrapMode: Text.WordWrap
                    }

                    GridLayout {
                        Layout.fillWidth: true
                        columns: width >= root.dp(520) ? 2 : 1
                        columnSpacing: root.dp(10)
                        rowSpacing: root.dp(10)

                        GenLogoSlot {
                            target: "mtc"
                            title: "Logo MTC / entidad"
                            subtitle: "ENTITY · Entidad / cliente"
                            hasLogo: root.hasLogoMtc
                            logoSource: root.logoMtcSource
                        }
                        GenLogoSlot {
                            target: "pro"
                            title: "Logo del proyecto"
                            subtitle: "PROJECT · Proyecto / empresa"
                            hasLogo: root.hasLogoProyecto
                            logoSource: root.logoProyectoSource
                        }
                    }
                }
            }

            GenDialogButton {
                text: "Cerrar"
                onClicked: root._closeIdentityPopup()
            }
        }
    }

    // === Ambiente de la ficha (Liquid Glass) ===
    // El mismo ambiente estático de Fotos/Revisión: base blanca, luz azul suave.
    // Sin desenfoque ni animación: los controles de vidrio lo dejan ver.
    PhotoGlassAmbient {
        objectName: "calicataGlassBackdrop"
        anchors.fill: parent
    }

    Image {
        anchors.fill: parent
        source: "qrc:/ui/v2/backgrounds/bg_topographic_lines.svg"
        fillMode: Image.PreserveAspectCrop
        opacity: root.liquidGlass ? 0.12 : 0.0
    }

    // Visor de fotografía: fondo oscuro, zoom con pellizco/doble toque, acciones claras.
    Popup {
        id: photoViewer
        parent: Overlay.overlay
        property real originDX: 0
        property real originDY: 0
        property real offsetX: 0
        property real offsetY: 0
        x: offsetX; y: offsetY
        width: parent ? parent.width : 400
        height: parent ? parent.height : 800
        modal: true
        focus: true
        padding: 0
        closePolicy: Popup.CloseOnEscape
        readonly property var info: root.photoSlotInfo(root.activePhotoCategory)
        onOpened: { viewerImage.scale = 1; viewerImage.x = 0; viewerImage.y = 0 }
        onClosed: { offsetX = 0; offsetY = 0 }
        background: Rectangle { color: "#F20A0D12" }
        enter: Transition {
            ParallelAnimation {
                NumberAnimation { property: "opacity"; from: 0; to: 1; duration: root.flow ? root.flow.duration(220) : 220; easing.type: Easing.OutCubic }
                NumberAnimation { property: "scale"; from: 0.6; to: 1; duration: root.flow ? root.flow.duration(360) : 360; easing.type: Easing.OutQuint }
                NumberAnimation { property: "offsetX"; from: photoViewer.originDX; to: 0; duration: root.flow ? root.flow.duration(360) : 360; easing.type: Easing.OutQuint }
                NumberAnimation { property: "offsetY"; from: photoViewer.originDY; to: 0; duration: root.flow ? root.flow.duration(360) : 360; easing.type: Easing.OutQuint }
            }
        }
        exit: Transition {
            ParallelAnimation {
                NumberAnimation { property: "opacity"; from: 1; to: 0; duration: root.flow ? root.flow.duration(200) : 200; easing.type: Easing.InCubic }
                NumberAnimation { property: "scale"; from: 1; to: 0.6; duration: root.flow ? root.flow.duration(240) : 240; easing.type: Easing.InCubic }
                NumberAnimation { property: "offsetX"; from: 0; to: photoViewer.originDX; duration: root.flow ? root.flow.duration(240) : 240; easing.type: Easing.InCubic }
                NumberAnimation { property: "offsetY"; from: 0; to: photoViewer.originDY; duration: root.flow ? root.flow.duration(240) : 240; easing.type: Easing.InCubic }
            }
        }
        contentItem: Item {
            Item {
                id: viewerStage
                anchors.fill: parent
                anchors.topMargin: root.dp(64)
                // La foto continúa bajo la barra Liquid Glass flotante (la refracta).
                anchors.bottomMargin: root.dp(12)
                clip: true
                Image {
                    id: viewerImage
                    width: viewerStage.width
                    height: viewerStage.height
                    source: photoViewer.visible ? root._photoSource(root.activePhotoCategory) : ""
                    fillMode: Image.PreserveAspectFit
                    asynchronous: true
                    // Decodificación acotada (≈16 MB máx. en vez de ~48 MB de una foto de 12 MP);
                    // de sobra para pantalla completa y el zoom del visor.
                    sourceSize: Qt.size(2048, 2048)
                    autoTransform: true
                    Behavior on scale { enabled: !viewerPinch.active; NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
                }
                PinchHandler {
                    id: viewerPinch
                    target: viewerImage
                    minimumScale: 1
                    maximumScale: 4
                    rotationAxis.enabled: false
                }
                TapHandler {
                    onDoubleTapped: {
                        viewerImage.scale = viewerImage.scale > 1 ? 1 : 2.5
                        if (viewerImage.scale === 1) { viewerImage.x = 0; viewerImage.y = 0 }
                    }
                }
                DragHandler { target: viewerImage; enabled: viewerImage.scale > 1 }
            }
            RowLayout {
                anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top
                anchors.margins: root.dp(12)
                spacing: root.dp(10)
                Rectangle {
                    Layout.preferredWidth: root.dp(40); Layout.preferredHeight: root.dp(40); radius: width / 2
                    color: viewerBackTap.pressed ? "#33FFFFFF" : "#1FFFFFFF"
                    Behavior on color { ColorAnimation { duration: 120 } }
                    Components.FlowIcon {
                        anchors.centerIn: parent
                        width: root.dp(22); height: width
                        name: "calgen.chevronLeft"; flow: root.flow
                        tintColor: "#FFFFFF"; activeTintColor: "#FFFFFF"; inactiveOpacity: 1
                    }
                    TapHandler { id: viewerBackTap; onTapped: photoViewer.close() }
                    Accessible.role: Accessible.Button
                    Accessible.name: "Cerrar fotografía"
                }
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 0
                    Text { text: root.photoSlotTitles[root.activePhotoCategory - 1] || ""; color: "white"; font.bold: true; font.pixelSize: root.sp(16) }
                    Text { text: photoViewer.info.label + (photoViewer.info.date.length ? " · " + photoViewer.info.date : ""); color: "#B8C0CC"; font.pixelSize: root.sp(11) }
                }
            }
            // Acciones del visor sobre la misma barra Liquid Glass de Fotos (variante oscura).
            PhotoGlassBar {
                id: viewerActionBar
                anchors.left: parent.left; anchors.right: parent.right; anchors.bottom: parent.bottom
                anchors.margins: root.dp(12)
                height: viewerActions.implicitHeight + root.dp(20)
                onDark: true
                barRadius: root.dp(22)
                backdrop: viewerStage
                // Captura viva justificada: la foto se amplía/desplaza bajo la barra (pinch/pan);
                // sin gesto el backdrop no cambia y no se re-renderiza.
                ColumnLayout {
                    id: viewerActions
                    anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top
                    anchors.margins: root.dp(10)
                    spacing: root.dp(8)
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: root.dp(8)
                        PhotoPill {
                            primary: true
                            visible: photoViewer.info.hasOriginal
                            text: "Editar y publicar"
                            onClicked: { photoViewer.close(); root.runPhotoAction("edit", root.activePhotoCategory) }
                        }
                        PhotoPill {
                            onGlass: true
                            visible: photoViewer.info.hasOriginal
                            text: "Versiones"
                            onClicked: { photoViewer.close(); root.runPhotoAction("versions", root.activePhotoCategory) }
                        }
                    }
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: root.dp(8)
                        PhotoPill {
                            onGlass: true
                            // Mismo criterio que la hoja de acciones y el Dock (photoActions).
                            visible: photoViewer.opened && root.photoHasAction(root.activePhotoCategory, "publish")
                            text: "Publicar"
                            onClicked: { photoViewer.close(); root.runPhotoAction("publish", root.activePhotoCategory) }
                        }
                        PhotoPill {
                            onGlass: true
                            text: "Reemplazar"
                            onClicked: { photoViewer.close(); root.openPhotoActions(root.activePhotoCategory) }
                        }
                        PhotoPill {
                            onGlass: true
                            text: "Dejar vacío"
                            onClicked: { photoViewer.close(); root.runPhotoAction("empty", root.activePhotoCategory) }
                        }
                    }
                }
            }
        }
    }

    // Hoja de acciones por categoría (flotante sobre Fotos; acciones según estado real).
    Popup {
        id: photoActionsSheet
        property Item glassBackdropItem: null
        parent: Overlay.overlay
        readonly property var actions: root.photoActions(root.photoSheetSlot)
        width: Math.min(parent ? parent.width - root.dp(28) : 360, root.dp(520))
        height: Math.min(sheetColumn.implicitHeight + root.dp(28), parent ? parent.height * 0.8 : 600)
        x: parent ? Math.round((parent.width - width) / 2) : 0
        y: parent ? parent.height - height - root.dp(96) : 0
        modal: true
        dim: true
        focus: true
        padding: root.dp(14)
        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
        transformOrigin: Popup.Bottom
        // Hoja de acciones = el mismo Liquid Glass de Fotos sobre la ventana (como el
        // popup de General): un grab estable mientras anima la entrada.
        background: PhotoGlassBar {
            backdrop: photoActionsSheet.visible ? (photoActionsSheet.glassBackdropItem ? photoActionsSheet.glassBackdropItem : root._genGlassBackdrop) : null
            frozen: false   // el fondo registrado (ya desenfocado) es estático: captura dirigida por eventos
            captureRect: photoActionsSheet.parent
                         ? photoActionsSheet.parent.mapToItem(photoActionsSheet.glassBackdropItem ? photoActionsSheet.glassBackdropItem : root._genGlassBackdrop,
                                                              photoActionsSheet.x, photoActionsSheet.y,
                                                              photoActionsSheet.width, photoActionsSheet.height)
                         : Qt.rect(photoActionsSheet.x, photoActionsSheet.y, photoActionsSheet.width, photoActionsSheet.height)
            barRadius: root.dp(26)
            absorbTaps: false
            surfaceName: "calicata-photo-sheet"
            // Preset y velo del peek "Información de la calicata".
            frost: 8
            lens: 0.3
            veilColor: root.darkMode ? Qt.rgba(0.0824, 0.102, 0.1882, 0.30) : Qt.rgba(0.98, 0.99, 1.0, 0.42)
            rimColor: root.darkMode ? Qt.rgba(1, 1, 1, 0.06) : Qt.rgba(1, 1, 1, 0.30)
        }
        Overlay.modal: GenGlassScrim { popupItem: photoActionsSheet }
        enter: Transition {
            ParallelAnimation {
                NumberAnimation { property: "opacity"; from: 0; to: 1; duration: root.flow ? root.flow.duration(200) : 200; easing.type: Easing.OutCubic }
                NumberAnimation { property: "scale"; from: 0.94; to: 1; duration: root.flow ? root.flow.duration(300) : 300; easing.type: Easing.OutQuint }
            }
        }
        exit: Transition {
            ParallelAnimation {
                NumberAnimation { property: "opacity"; from: 1; to: 0; duration: root.flow ? root.flow.duration(180) : 180; easing.type: Easing.InCubic }
                NumberAnimation { property: "scale"; from: 1; to: 0.96; duration: root.flow ? root.flow.duration(180) : 180; easing.type: Easing.InCubic }
            }
        }
        contentItem: Flickable {
            contentHeight: sheetColumn.implicitHeight
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            ColumnLayout {
                id: sheetColumn
                width: parent.width
                spacing: root.dp(4)
                Text {
                    Layout.bottomMargin: root.dp(6)
                    text: root.photoSlotTitles[root.photoSheetSlot - 1] || ""
                    color: root.cText; font.bold: true; font.pixelSize: root.fsField
                }
                Repeater {
                    model: photoActionsSheet.actions
                    delegate: Rectangle {
                        id: sheetRow
                        required property var modelData
                        Layout.fillWidth: true
                        implicitHeight: root.dp(52)
                        radius: root.dp(16)
                        color: sheetRowTap.pressed ? Qt.rgba(root.cGenBlue.r, root.cGenBlue.g, root.cGenBlue.b, 0.10) : "transparent"
                        opacity: modelData.enabled ? 1 : 0.4
                        scale: sheetRowTap.pressed ? 0.98 : 1
                        Behavior on scale { NumberAnimation { duration: sheetRowTap.pressed ? 70 : 170; easing.type: Easing.OutCubic } }
                        Behavior on color { ColorAnimation { duration: 130 } }
                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: root.dp(8); anchors.rightMargin: root.dp(10)
                            spacing: root.dp(12)
                            PhotoGlassBadge {
                                Layout.preferredWidth: root.dp(38); Layout.preferredHeight: root.dp(38)
                                iconName: sheetRow.modelData.icon
                                iconSize: root.dp(19)
                                iconColor: sheetRow.modelData.destructive ? (root.flow ? root.flow.theme.error : "#B4232E") : root.cGenBlue
                                pressed: sheetRowTap.pressed
                            }
                            Text {
                                Layout.fillWidth: true
                                text: sheetRow.modelData.label
                                color: sheetRow.modelData.destructive ? (root.flow ? root.flow.theme.error : "#B4232E") : root.cText
                                font.pixelSize: root.fsLabel
                            }
                        }
                        TapHandler {
                            id: sheetRowTap
                            enabled: sheetRow.modelData.enabled
                            gesturePolicy: TapHandler.ReleaseWithinBounds
                            onTapped: { var id = sheetRow.modelData.id; photoActionsSheet.close(); root.runPhotoAction(id, root.photoSheetSlot) }
                        }
                        Accessible.role: Accessible.Button
                        Accessible.name: sheetRow.modelData.label
                    }
                }
            }
        }
    }

    Popup {
        id: stratumSheet
        parent: Overlay.overlay
        // Capa desenfocada que refracta la ventana flotante (labDetailBackdrop).
        property Item glassBackdropItem: null
        // Laboratorio: ventana flotante grande sobre la lista (márgenes, radio 26,
        // máx. 780 dp, termina sobre la zona del Dock). Profundidad (Perfil) conserva
        // su hoja completa.
        readonly property bool floating: root.labSheetActive
        readonly property real dockInset: root.dp(92)
        readonly property real sideMargin: root.dp(14)
        readonly property real baseX: Math.round((parent.width - width) / 2)
        readonly property real baseY: Math.max(root.dp(22), parent.height - dockInset - height)
        property real offsetX: 0
        property real offsetY: 0
        // Desde/hacia la tarjeta de origen; sin tarjeta: centro con 24 dp de subida.
        readonly property real originDX: root.labOriginValid ? root.labOriginX - (baseX + width / 2) : 0
        readonly property real originDY: root.labOriginValid ? root.labOriginY - (baseY + height / 2) : root.dp(24)
        readonly property real originScale: root.labOriginValid ? 0.86 : 0.94
        x: floating ? baseX + offsetX : 0
        y: floating ? baseY + offsetY : 0
        width: floating ? Math.min(parent.width - 2 * sideMargin, root.dp(780)) : parent.width
        height: floating ? Math.max(root.dp(320), Math.min(parent.height * 0.88, parent.height - root.dp(22) - dockInset)) : parent.height
        // No modal en Laboratorio: el velo propio (labDetailScrim) cubre solo la página,
        // así el Dock del shell sigue visible y contextual (calicatas/.../lab-detail).
        modal: !floating
        focus: true
        padding: floating ? root.dp(16) : root.dp(14)
        closePolicy: Popup.NoAutoClose
        transformOrigin: Popup.Center
        enter: Transition {
            enabled: stratumSheet.floating && !!root.flow && root.flow.motionAllowed
            ParallelAnimation {
                NumberAnimation { property: "opacity"; from: 0; to: 1; duration: root.flow ? root.flow.duration(260) : 260; easing.type: Easing.OutCubic }
                NumberAnimation { property: "scale"; from: stratumSheet.originScale; to: 1; duration: root.flow ? root.flow.duration(420) : 420; easing.type: Easing.OutQuint }
                NumberAnimation { property: "offsetX"; from: stratumSheet.originDX; to: 0; duration: root.flow ? root.flow.duration(420) : 420; easing.type: Easing.OutQuint }
                NumberAnimation { property: "offsetY"; from: stratumSheet.originDY; to: 0; duration: root.flow ? root.flow.duration(420) : 420; easing.type: Easing.OutQuint }
            }
        }
        exit: Transition {
            enabled: stratumSheet.floating && !!root.flow && root.flow.motionAllowed
            ParallelAnimation {
                NumberAnimation { property: "opacity"; from: 1; to: 0; duration: root.flow ? root.flow.duration(280) : 280; easing.type: Easing.InCubic }
                NumberAnimation { property: "scale"; from: 1; to: root.labOriginValid ? 0.9 : 0.96; duration: root.flow ? root.flow.duration(300) : 300; easing.type: Easing.InCubic }
                // Vuelve hacia su tarjeta (o baja 20 dp sin tarjeta de origen).
                NumberAnimation { property: "offsetX"; from: 0; to: stratumSheet.originDX; duration: root.flow ? root.flow.duration(300) : 300; easing.type: Easing.InCubic }
                NumberAnimation { property: "offsetY"; from: 0; to: root.labOriginValid ? stratumSheet.originDY : root.dp(20); duration: root.flow ? root.flow.duration(300) : 300; easing.type: Easing.InCubic }
            }
        }
        background: Item {
            // Hoja completa (Profundidad): el ambiente de la ficha, con controles de vidrio.
            PhotoGlassAmbient {
                objectName: "calicataGlassBackdrop"
                visible: !stratumSheet.floating
                anchors.fill: parent
                radius: stratumSheet.floating ? root.dp(26) : 0
            }
            // Ventana flotante de Laboratorio: el material de los emergentes, un grab
            // estable sobre su rect final mientras anima desde la tarjeta de origen.
            GenPopupGlass {
                visible: stratumSheet.floating
                anchors.fill: parent
                popupItem: stratumSheet
                radius: root.dp(26)
                finalX: stratumSheet.baseX
                finalY: stratumSheet.baseY
                surfaceName: "calicata-lab-window"
            }
        }
        contentItem: ColumnLayout {
            spacing: stratumSheet.floating ? root.dp(10) : 12
            Rectangle { visible: !stratumSheet.floating; Layout.alignment: Qt.AlignHCenter; width: 36; height: 4; radius: 2; color: root.cBorder }
            RowLayout {
                Layout.fillWidth: true
                PrfToolButton {
                    visible: root.labSheetActive
                    iconOnly: true
                    iconName: "calgen.chevronLeft"
                    Accessible.name: "Volver a la lista de laboratorio"
                    onClicked: root.closeLabDetail()
                }
                Label {
                    Layout.fillWidth: true
                    text: root.profileMode === "depth"
                          ? "Profundidad y agua"
                          : (root.labSheetActive
                             ? "Estrato " + (root.selectedStratum + 1) + " · "
                               + (root.prfSel ? String(root.prfSel.de || "—") + " – " + String(root.prfSel.a || "—") + " m" : "")
                             : "Estrato " + (root.selectedStratum + 1))
                    color: root.cText
                    font.pixelSize: root.labSheetActive ? root.sp(18) : 20
                    font.bold: root.labSheetActive
                    elide: Text.ElideRight
                }
                Rectangle {
                    visible: root.labSheetActive && root.labKindChip(root.labInfo(root.selectedStratum)).length > 0
                    Layout.preferredWidth: sheetKindText.implicitWidth + root.dp(16)
                    Layout.preferredHeight: root.dp(24)
                    radius: height / 2
                    color: root.cGenTealSoft
                    Text { id: sheetKindText; anchors.centerIn: parent; text: root.labKindChip(root.labInfo(root.selectedStratum)); color: root.cGenTeal; font.bold: true; font.pixelSize: root.sp(11) }
                }
                GenDialogButton { visible: !root.labSheetActive; Layout.fillWidth: false; primary: true; text: "Listo"; onClicked: root.finishStratum(true) }
            }
            Text {
                Layout.fillWidth: true
                visible: root.labSheetActive
                text: root.labContextText(root.labInfo(root.selectedStratum))
                color: root.cMuted
                font.pixelSize: root.fsLabel
                elide: Text.ElideRight
            }
            // Tabs (sticky, fuera del scroll): indicador azul que se desplaza entre pestañas.
            Item {
                id: labTabBar
                Layout.fillWidth: true
                visible: root.labSheetActive
                implicitHeight: root.dp(40)
                readonly property var tabs: [{ key: "lab", label: "Laboratorio" }, { key: "context", label: "Contexto" }, { key: "history", label: "Historial" }]
                readonly property int current: Math.max(0, ["lab", "context", "history"].indexOf(root.labTab))
                readonly property real slotWidth: (width - root.dp(6)) / 3
                CalicataLiquidGlass { dark: root.darkMode; accent: root.cGenBlue; danger: root.flow ? root.flow.theme.error : "#D9483B"; anchors.fill: parent; radius: height / 2 }
                Rectangle {
                    y: root.dp(3)
                    height: parent.height - root.dp(6)
                    width: labTabBar.slotWidth
                    x: root.dp(3) + labTabBar.current * labTabBar.slotWidth
                    radius: height / 2
                    color: root.cGenBlue
                    Behavior on x { NumberAnimation { duration: root.flow ? root.flow.duration(220) : 220; easing.type: Easing.OutCubic } }
                }
                Row {
                    x: root.dp(3)
                    y: root.dp(3)
                    Repeater {
                        model: labTabBar.tabs
                        delegate: Item {
                            id: labTabSlot
                            required property var modelData
                            required property int index
                            width: labTabBar.slotWidth
                            height: labTabBar.height - root.dp(6)
                            scale: labTabTap.pressed ? 0.97 : 1
                            Behavior on scale { NumberAnimation { duration: root.flow ? root.flow.instantDuration : 70 } }
                            Text {
                                anchors.centerIn: parent
                                text: labTabSlot.modelData.label
                                color: labTabBar.current === labTabSlot.index ? "#FFFFFF" : root.cText
                                font.pixelSize: root.fsLabel
                                font.bold: labTabBar.current === labTabSlot.index
                                Behavior on color { ColorAnimation { duration: root.flow ? root.flow.duration(160) : 160 } }
                            }
                            TapHandler { id: labTabTap; onTapped: root.setLabTab(labTabSlot.modelData.key) }
                            Accessible.role: Accessible.PageTab
                            Accessible.name: labTabSlot.modelData.label
                        }
                    }
                }
            }
            RowLayout {
                visible: false
                GenDialogButton { Layout.fillWidth: false; soft: root.profileMode === "field"; text: "Campo"; onClicked: { if (root.commitPendingField()) root.profileMode = "field" } }
                GenDialogButton { Layout.fillWidth: false; soft: root.profileMode === "samples"; text: "Muestras / Lab"; onClicked: { if (root.commitPendingField()) root.profileMode = "samples" } }
            }
            FlowCore.ImeAwareFlickable {
                Layout.fillWidth: true
                Layout.fillHeight: true
                flow: root.flow
                clip: true
                contentWidth: width
                contentHeight: stratumSheetBody.implicitHeight + root.dp(32)
                ColumnLayout {
                    id: stratumSheetBody
                    width: parent.width
                // El editor de campo del estrato vive ahora en la etapa Perfil
                // (prfEditorCard). Esta hoja solo aloja Profundidad y Muestras/Lab.
            MobileStageBody {
                id: mobileExcavationSection
                Layout.fillWidth: true
                glassPanel: !stratumSheet.floating
                sectionNumber: 3
                sectionTitle: "Profundidad y agua"
                sectionSubtitle: "Profundidad registrada derivada de los intervalos"


                GridLayout {
                    Layout.fillWidth: true
                    columns: width >= root.dp(340) ? 2 : 1
                    columnSpacing: root.dp(10)
                    rowSpacing: root.dp(10)

                    MobileReadOnlyField {
                        Layout.fillWidth: true
                        fieldLabel: "Límite de profundidad"
                        fieldText: "Sin límite"
                    }
                    ColumnLayout {
                        Layout.fillWidth: true
                        Text { text: "Profundidad objetivo (opcional, m)"; color: root.cMuted; font.pixelSize: root.fsLabel }
                        BoundTextField {
                            Layout.fillWidth: true
                            placeholderText: "Profundidad final (m)"
                            numericKind: Rules.DEPTH_METERS
                            minimumValue: 0.01
                            maximumValue: root.depthMaxM
                            modelText: root.requestedDepthM > 0 ? root.requestedDepthM.toFixed(2) : ""
                            onCommit: function(t) { return root.commitProfileDepth(t) }
                        }
                    }
                    MobileReadOnlyField {
                        Layout.fillWidth: true
                        fieldLabel: "Estratos registrados"
                        fieldText: String(root.visibleStrataCount)
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        Layout.columnSpan: parent.columns
                        spacing: root.dp(4)
                        RowLayout {
                            Layout.fillWidth: true
                            Text { Layout.fillWidth: true; text: "Nivel freático (m)"; color: root.cMuted; font.pixelSize: root.fsLabel }
                            GenGlassCheckBox {
                                text: "Personalizado"
                                checked: root.groundwaterCustom
                                onToggled: {
                                    root.groundwaterCustom = checked
                                    // Al volver a derivado, el valor manual deja de ser canónico.
                                    if (!checked) txtWaterTableDepth.text = ""
                                    else if (!txtWaterTableDepth.text.trim().length)
                                        txtWaterTableDepth.text = root.derivedGroundwaterText
                                    root._markDirty()
                                }
                            }
                        }
                        MobileReadOnlyField {
                            Layout.fillWidth: true
                            visible: !root.groundwaterCustom
                            fieldLabel: root.derivedGroundwaterText.length
                                        ? "Derivado del primer corte con humedad AGUA."
                                        : "Ningún corte registra AGUA. Marca Personalizado para declararlo."
                            fieldText: root.derivedGroundwaterText.length ? root.derivedGroundwaterText : "—"
                        }
                        BoundTextField {
                            Layout.fillWidth: true
                            visible: root.groundwaterCustom
                            numericKind: Rules.DEPTH_METERS
                            maximumValue: root.allowedDepthM
                            placeholderText: "Profundidad del nivel freático"
                            modelText: txtWaterTableDepth.text
                            onCommit: function(t) { txtWaterTableDepth.text = t }
                        }
                    }

                    MobileReadOnlyField {
                        Layout.fillWidth: true
                        Layout.columnSpan: parent.columns
                        fieldLabel: "Profundidad (m) · derivada de los cortes"
                        fieldText: root.derivedDepthText.length ? root.derivedDepthText : "Sin cortes completos"
                    }
                }
            }
            MobileStageBody {
                id: mobileSamplesSection
                Layout.fillWidth: true
                glassPanel: !stratumSheet.floating
                sectionNumber: 5
                sectionTitle: "Muestras y ensayos"
                sectionSubtitle: "Datos de laboratorio por intervalo"


                Repeater {
                    model: cortesModel

                    delegate: Rectangle {
                        id: mobileSampleCard
                        visible: corteIdx === root.selectedStratum
                        function labExtra() {
                            if(corteIdx<0 || corteIdx>=cortesModel.count) return {}
                            return JSON.parse(cortesModel.get(corteIdx)._extraJson || "{}")
                        }
                        property int corteIdx: index
                        readonly property var info: { root._cortesRevision; return root.labInfo(corteIdx) }
                        // Repeater delegates can outlive their removed ListModel row
                        // until deferred destruction. Never dereference that row.
                        function boundary(key) {
                            if (corteIdx < 0 || corteIdx >= cortesModel.count) return NaN
                            var row = cortesModel.get(corteIdx)
                            return Rules.parseDecimalSafe(row ? row[key] : null)
                        }
                        Layout.fillWidth: true
                        implicitHeight: mobileSampleLayout.implicitHeight + root.dp(20)
                        radius: root.dp(11)
                        color: "transparent"   // los bloques internos ya son tarjetas
                        border.width: 0
                        border.color: root.cBorder

                        ColumnLayout {
                            id: mobileSampleLayout
                            opacity: root.labSheetActive ? root.labTabFade : 1
                            transform: Translate { x: root.labSheetActive ? root.labTabShift : 0 }
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.top: parent.top
                            anchors.margins: root.dp(10)
                            spacing: root.dp(10)

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: root.dp(8)
                                Components.FlowIcon {
                                    Layout.preferredWidth: root.dp(21)
                                    Layout.preferredHeight: root.dp(21)
                                    name: root.iconSamplesName
                                    flow: root.flow
                                    tintColor: root.cAccent
                                    activeTintColor: root.cAccent
                                    inactiveOpacity: 1.0
                                }
                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 1
                                    Text {
                                        Layout.fillWidth: true
                                        text: "Estrato " + (mobileSampleCard.corteIdx + 1)
                                        color: root.cText
                                        font.bold: true
                                        font.pixelSize: root.sp(root.isPhone ? 14 : 16)
                                    }
                                    Text {
                                        Layout.fillWidth: true
                                        text: "Estrato " + ((de || "—") + " – " + (a || "—") + " m")
                                        color: root.cMuted
                                        font.pixelSize: root.fsLabel
                                    }
                                }
                            }

                            // CONTEXTO: heredado de Perfil, solo lectura.
                            PrfSubsection {
                                Layout.fillWidth: true
                                visible: root.labTab === "context"
                                title: "Contexto del estrato (desde Perfil)"
                                iconName: root.iconStrataName
                                accent: root.cGenTeal
                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: root.dp(10)
                                    ColumnLayout {
                                        Layout.fillWidth: true
                                        spacing: root.dp(4)
                                        Repeater {
                                            model: root.labContextRows(mobileSampleCard.info)
                                            delegate: RowLayout {
                                                required property var modelData
                                                Layout.fillWidth: true
                                                spacing: root.dp(8)
                                                Text { Layout.preferredWidth: root.dp(118); text: modelData.label; color: root.cMuted; font.pixelSize: root.fsLabel; wrapMode: Text.WordWrap }
                                                Text { Layout.fillWidth: true; text: modelData.value; color: root.cText; font.pixelSize: root.fsLabel; wrapMode: Text.WordWrap }
                                            }
                                        }
                                    }
                                    Rectangle {
                                        readonly property var files: mobileSampleCard.info ? root.stratumPatternFilesFor(mobileSampleCard.info.plain) : []
                                        visible: files.length > 0
                                        Layout.alignment: Qt.AlignTop
                                        Layout.preferredWidth: root.dp(40)
                                        Layout.preferredHeight: root.dp(96)
                                        color: "#FFFFFF"
                                        border.width: 1
                                        border.color: root.cBorder
                                        clip: true
                                        Row {
                                            id: labPatternLayers
                                            readonly property var layerFiles: parent.files
                                            anchors.fill: parent
                                            anchors.margins: 1
                                            Repeater {
                                                model: labPatternLayers.layerFiles
                                                delegate: Image {
                                                    required property string modelData
                                                    width: labPatternLayers.width / Math.max(1, labPatternLayers.layerFiles.length)
                                                    height: labPatternLayers.height
                                                    source: modelData
                                                    fillMode: Image.Tile
                                                    sourceSize.width: root.dp(24)
                                                    sourceSize.height: root.dp(24)
                                                    asynchronous: true
                                                }
                                            }
                                        }
                                    }
                                }
                                Text {
                                    Layout.fillWidth: true
                                    text: "Solo lectura: estos datos se editan en Perfil."
                                    color: root.cMuted
                                    font.pixelSize: root.sp(11)
                                    wrapMode: Text.WordWrap
                                }
                            }

                            // HISTORIAL: solo hitos reales guardados en la ficha (sin backend de versiones).
                            PrfSubsection {
                                Layout.fillWidth: true
                                visible: root.labTab === "history"
                                title: "Historial"
                                iconName: "status.sync"
                                accent: root.cGenBlue
                                Repeater {
                                    model: root.labHistoryRows(mobileSampleCard.info)
                                    delegate: RowLayout {
                                        required property var modelData
                                        Layout.fillWidth: true
                                        spacing: root.dp(8)
                                        Text { Layout.preferredWidth: root.dp(88); text: modelData.label; color: root.cMuted; font.pixelSize: root.fsLabel }
                                        Text { Layout.fillWidth: true; text: modelData.value; color: root.cText; font.pixelSize: root.fsLabel; wrapMode: Text.WordWrap }
                                    }
                                }
                                Text {
                                    Layout.fillWidth: true
                                    visible: root.labHistoryRows(mobileSampleCard.info).length === 0
                                    text: "Sin eventos de laboratorio registrados en esta ficha."
                                    color: root.cMuted
                                    font.pixelSize: root.fsLabel
                                    wrapMode: Text.WordWrap
                                }
                                Text {
                                    Layout.fillWidth: true
                                    text: mobileSampleCard.info && (mobileSampleCard.info.plain.lab_cloud_pending || []).length
                                          ? "Pendiente de sincronizar con el servidor: "
                                            + mobileSampleCard.info.plain.lab_cloud_pending.map(function(reason) {
                                                  return reason === "LAB_LIMITS" ? "WL/LP con decimales (el servidor admite enteros)"
                                                       : reason === "LAB_INVALID" ? "ensayo con errores de validación" : reason }).join(", ")
                                            + ". El valor local se conserva."
                                          : "Sin historial sincronizado desde el servidor."
                                    color: root.cMuted
                                    font.pixelSize: root.sp(11)
                                    wrapMode: Text.WordWrap
                                }
                            }

                            // MUESTRA (Campo/Perfil, solo lectura). Contrato Web: "M-XX, intervalo y
                            // tipo proceden de Campo". Registrar/editar abre el MISMO editor de Perfil.
                            Rectangle {
                                id: sampleSummaryCard
                                readonly property var s: mobileSampleCard.info ? mobileSampleCard.info.sample : null
                                Layout.fillWidth: true
                                visible: root.labTab === "lab"
                                implicitHeight: sampleSummaryRow.implicitHeight + root.dp(24)
                                Behavior on implicitHeight { enabled: !root._stageSettling; NumberAnimation { duration: root.flow ? root.flow.duration(180) : 180; easing.type: Easing.OutCubic } }
                                radius: root.dp(14)
                                color: "transparent"
                                CalicataLiquidGlass { dark: root.darkMode; accent: root.cGenBlue; danger: root.flow ? root.flow.theme.error : "#D9483B"; anchors.fill: parent; radius: parent.radius; level: "card" }
                                RowLayout {
                                    id: sampleSummaryRow
                                    anchors.left: parent.left; anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                                    anchors.leftMargin: root.dp(12); anchors.rightMargin: root.dp(12)
                                    spacing: root.dp(12)
                                    Components.FlowIcon {
                                        Layout.preferredWidth: root.dp(22)
                                        Layout.preferredHeight: root.dp(22)
                                        name: "calgen.attach"
                                        flow: root.flow
                                        tintColor: root.cGenViolet
                                        activeTintColor: root.cGenViolet
                                        inactiveOpacity: 1
                                    }
                                    ColumnLayout {
                                        Layout.fillWidth: true
                                        spacing: root.dp(2)
                                        Text { text: "Muestra"; color: root.cMuted; font.pixelSize: root.sp(11); font.bold: true }
                                        Text {
                                            Layout.fillWidth: true
                                            elide: Text.ElideRight
                                            color: root.cText
                                            font.pixelSize: root.fsField
                                            font.bold: true
                                            text: !sampleSummaryCard.s ? "" : sampleSummaryCard.s.hasSample
                                                  ? (sampleSummaryCard.s.type || "Muestra") + " · " + sampleSummaryCard.s.reference
                                                  : "Sin muestra registrada"
                                        }
                                        Text {
                                            Layout.fillWidth: true
                                            wrapMode: Text.WordWrap
                                            color: root.cMuted
                                            font.pixelSize: root.sp(11)
                                            text: !sampleSummaryCard.s ? ""
                                                  : (sampleSummaryCard.s.interval.length ? sampleSummaryCard.s.interval
                                                                                         : "Intervalo del estrato: " + sampleSummaryCard.s.stratumInterval)
                                                    + (!sampleSummaryCard.s.hasSample ? ""
                                                       : mobileSampleCard.info.hasTests ? " · ✓ Registrada y ensayada" : " · ✓ Registrada")
                                        }
                                    }
                                    LabActionPill {
                                        text: sampleSummaryCard.s && sampleSummaryCard.s.hasSample ? "Editar" : "Registrar muestra"
                                        onClicked: root.labEditSampleInProfile(mobileSampleCard.corteIdx)
                                    }
                                }
                            }

                            // Canonical Web laboratory contract. One laboratory row belongs to one stratum.
                            ColumnLayout {
                                Layout.fillWidth: true
                                visible: root.labTab === "lab" && !!mobileSampleCard.info
                                spacing: root.dp(10)

                                Text { text: "Granulometría (MTC E107) · % que pasa"; color: root.cText; font.bold: true; font.pixelSize: root.fsLabel }
                                GridLayout {
                                    Layout.fillWidth: true
                                    columns: 1
                                    columnSpacing: root.dp(8)
                                    rowSpacing: root.dp(8)

                                    RowLayout {
                                        Layout.fillWidth: true
                                        Text { Layout.fillWidth: true; text: "Máx. · tamaño máx."; color: root.cMuted; font.pixelSize: root.fsLabel }
                                        BoundTextField {
                                            Layout.preferredWidth: root.dp(104); numericKind: Rules.PERCENTAGE; minimumValue: 0; maximumValue: 100
                                            placeholderText: "0–100"; modelText: String(gmax === undefined || gmax === null ? "" : gmax)
                                            onCommit: function(t) { return root.commitWebLabPercent(mobileSampleCard.corteIdx, "gmax", t) }
                                        }
                                        Text { text: "%"; color: root.cMuted; font.pixelSize: root.fsLabel }
                                    }
                                    RowLayout {
                                        Layout.fillWidth: true
                                        Text { Layout.fillWidth: true; text: "Nº 4 · 4.75 mm"; color: root.cMuted; font.pixelSize: root.fsLabel }
                                        BoundTextField {
                                            Layout.preferredWidth: root.dp(104); numericKind: Rules.PERCENTAGE; minimumValue: 0; maximumValue: 100
                                            placeholderText: "0–100"; modelText: String(JSON.parse(_extraJson || "{}").passing_no4 === undefined ? "" : JSON.parse(_extraJson || "{}").passing_no4)
                                            onCommit: function(t) { return root.commitWebLabPercent(mobileSampleCard.corteIdx, "passing_no4", t) }
                                        }
                                        Text { text: "%"; color: root.cMuted; font.pixelSize: root.fsLabel }
                                    }
                                    RowLayout {
                                        Layout.fillWidth: true
                                        Text { Layout.fillWidth: true; text: "Nº 10 · 2.00 mm"; color: root.cMuted; font.pixelSize: root.fsLabel }
                                        BoundTextField {
                                            Layout.preferredWidth: root.dp(104); numericKind: Rules.PERCENTAGE; minimumValue: 0; maximumValue: 100
                                            placeholderText: "0–100"; modelText: String(g2 === undefined || g2 === null ? "" : g2)
                                            onCommit: function(t) { return root.commitWebLabPercent(mobileSampleCard.corteIdx, "g2", t) }
                                        }
                                        Text { text: "%"; color: root.cMuted; font.pixelSize: root.fsLabel }
                                    }
                                    RowLayout {
                                        Layout.fillWidth: true
                                        Text { Layout.fillWidth: true; text: "Nº 40 · 0.425 mm"; color: root.cMuted; font.pixelSize: root.fsLabel }
                                        BoundTextField {
                                            Layout.preferredWidth: root.dp(104); numericKind: Rules.PERCENTAGE; minimumValue: 0; maximumValue: 100
                                            placeholderText: "0–100"; modelText: String(g04 === undefined || g04 === null ? "" : g04)
                                            onCommit: function(t) { return root.commitWebLabPercent(mobileSampleCard.corteIdx, "g04", t) }
                                        }
                                        Text { text: "%"; color: root.cMuted; font.pixelSize: root.fsLabel }
                                    }
                                    RowLayout {
                                        Layout.fillWidth: true
                                        Text { Layout.fillWidth: true; text: "Nº 200 · 0.075 mm"; color: root.cMuted; font.pixelSize: root.fsLabel }
                                        BoundTextField {
                                            Layout.preferredWidth: root.dp(104); numericKind: Rules.PERCENTAGE; minimumValue: 0; maximumValue: 100
                                            placeholderText: "0–100"; modelText: String(g008 === undefined || g008 === null ? "" : g008)
                                            onCommit: function(t) { return root.commitWebLabPercent(mobileSampleCard.corteIdx, "g008", t) }
                                        }
                                        Text { text: "%"; color: root.cMuted; font.pixelSize: root.fsLabel }
                                    }
                                }

                                // Plasticidad (MTC E110 / E111): WL y LP enteros, como Web.
                                Text { text: "Plasticidad (MTC E110 / E111)"; color: root.cText; font.bold: true; font.pixelSize: root.fsLabel }
                                GridLayout {
                                    Layout.fillWidth: true
                                    columns: 1
                                    columnSpacing: root.dp(8); rowSpacing: root.dp(8)
                                    RowLayout {
                                        Layout.fillWidth: true
                                        Text { Layout.fillWidth: true; text: "Límite líquido (WL)"; color: root.cMuted; font.pixelSize: root.fsLabel }
                                        BoundTextField {
                                            Layout.preferredWidth: root.dp(104); numericKind: Rules.PERCENTAGE; minimumValue: 0; maximumValue: 999
                                            placeholderText: "Ej. 32"; modelText: String(wl === undefined || wl === null ? "" : wl)
                                            onCommit: function(t) { return root.commitLabLimit(mobileSampleCard.corteIdx, "wl", t) }
                                        }
                                    }
                                    RowLayout {
                                        Layout.fillWidth: true
                                        Text { Layout.fillWidth: true; text: "Límite plástico (LP)"; color: root.cMuted; font.pixelSize: root.fsLabel }
                                        BoundTextField {
                                            Layout.preferredWidth: root.dp(104); numericKind: Rules.PERCENTAGE; minimumValue: 0; maximumValue: 999
                                            placeholderText: "Ej. 18"; modelText: String(lp === undefined || lp === null ? "" : lp)
                                            onCommit: function(t) { return root.commitLabLimit(mobileSampleCard.corteIdx, "lp", t) }
                                        }
                                    }
                                    RowLayout {
                                        Layout.fillWidth: true
                                        Text { Layout.fillWidth: true; text: "Índice de plasticidad (IP)"; color: root.cMuted; font.pixelSize: root.fsLabel }
                                        Text { text: root.labIpText(mobileSampleCard.info); color: root.cText; font.bold: true; font.pixelSize: root.fsField }
                                        Rectangle {
                                            Layout.preferredWidth: autoTag.implicitWidth + root.dp(12)
                                            Layout.preferredHeight: root.dp(20)
                                            radius: height / 2
                                            color: "transparent"
                                            CalicataLiquidGlass { dark: root.darkMode; accent: root.cGenBlue; danger: root.flow ? root.flow.theme.error : "#D9483B"; anchors.fill: parent; radius: parent.radius; tone: "tinted" }
                                            Text { id: autoTag; anchors.centerIn: parent; text: "Auto"; color: root.cGenBlue; font.pixelSize: root.sp(10); font.bold: true }
                                        }
                                    }
                                }

                                // Humedad natural: dato de ensayo, nunca la humedad de campo.
                                RowLayout {
                                    Layout.fillWidth: true
                                    Text { Layout.fillWidth: true; text: "Humedad natural (MTC E108)"; color: root.cMuted; font.pixelSize: root.fsLabel }
                                    BoundTextField {
                                        Layout.preferredWidth: root.dp(104); numericKind: Rules.PERCENTAGE; minimumValue: 0; maximumValue: 500
                                        placeholderText: "—"; modelText: String(hum2 === undefined || hum2 === null ? "" : hum2)
                                        onCommit: function(t) { var n=Rules.webLabNormalizePercent(t,{min:0,max:500}); if(n===null){root.showInfo("Humedad natural","Usa un valor entre 0 y 500 %.");return false}; cortesModel.setProperty(mobileSampleCard.corteIdx,"hum2",n);root._markDirty();root.deriveLabFields();return true }
                                    }
                                    Text { text: "%"; color: root.cMuted; font.pixelSize: root.fsLabel }
                                }

                                // Clasificación sugerida (Web SuggestedClassification): chips
                                // derivados de los ensayos. Solo escriben al tocarlos.
                                Rectangle {
                                    id: labReviewPanel
                                    readonly property var info: mobileSampleCard.info
                                    readonly property var suggestion: info ? info.suggestion : null
                                    Layout.fillWidth: true
                                    implicitHeight: labReviewColumn.implicitHeight + root.dp(20)
                                    radius: root.dp(12)
                                    color: "transparent"
                                    CalicataLiquidGlass {
                                        dark: root.darkMode
                                        accent: labReviewPanel.info && labReviewPanel.info.reviewStatus === "revisar" ? root.cGenOrange : root.cGenBlue
                                        anchors.fill: parent
                                        radius: parent.radius
                                        tone: "tinted"
                                        selected: true
                                    }
                                    ColumnLayout {
                                        id: labReviewColumn
                                        anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top
                                        anchors.margins: root.dp(10)
                                        spacing: root.dp(6)
                                        RowLayout {
                                            Layout.fillWidth: true
                                            Text { Layout.fillWidth: true; text: "Clasificación sugerida"; color: root.cText; font.bold: true; font.pixelSize: root.fsLabel }
                                            Text {
                                                text: labReviewPanel.info ? Rules.LAB_REVIEW_LABELS[labReviewPanel.info.reviewStatus] : "Sin datos"
                                                color: labReviewPanel.info && labReviewPanel.info.reviewStatus === "conforme" ? root.cGenGreen
                                                       : labReviewPanel.info && labReviewPanel.info.reviewStatus === "revisar" ? root.cGenOrange : root.cMuted
                                                font.bold: true; font.pixelSize: root.fsLabel
                                            }
                                        }
                                        RowLayout {
                                            Layout.fillWidth: true
                                            spacing: root.dp(6)
                                            Text { Layout.preferredWidth: root.dp(56); text: "AASHTO"; color: root.cMuted; font.pixelSize: root.sp(11); font.bold: true }
                                            LabSuggestionChip {
                                                visible: !!(labReviewPanel.suggestion && labReviewPanel.suggestion.aashto)
                                                code: labReviewPanel.suggestion && labReviewPanel.suggestion.aashto ? labReviewPanel.suggestion.aashto.code : ""
                                                current: !!(labReviewPanel.suggestion && labReviewPanel.suggestion.aashto && labReviewPanel.suggestion.aashto.current)
                                                onAdopt: root.adoptLabAashto(mobileSampleCard.corteIdx, code)
                                            }
                                            Text {
                                                visible: !(labReviewPanel.suggestion && labReviewPanel.suggestion.aashto)
                                                text: "Datos insuficientes"; color: root.cMuted; font.pixelSize: root.sp(11)
                                            }
                                            Item { Layout.fillWidth: true }
                                        }
                                        RowLayout {
                                            Layout.fillWidth: true
                                            spacing: root.dp(6)
                                            Text { Layout.preferredWidth: root.dp(56); text: "SUCS"; color: root.cMuted; font.pixelSize: root.sp(11); font.bold: true }
                                            Repeater {
                                                model: labReviewPanel.suggestion ? labReviewPanel.suggestion.sucs : []
                                                delegate: LabSuggestionChip {
                                                    required property var modelData
                                                    code: modelData.code
                                                    current: modelData.current
                                                    onAdopt: root.adoptLabSucs(mobileSampleCard.corteIdx, code)
                                                }
                                            }
                                            Text {
                                                visible: !!labReviewPanel.suggestion && labReviewPanel.suggestion.hidden > 0
                                                text: labReviewPanel.suggestion ? "+" + labReviewPanel.suggestion.hidden : ""
                                                color: root.cMuted; font.pixelSize: root.sp(11)
                                            }
                                            Text {
                                                visible: !!labReviewPanel.suggestion && labReviewPanel.suggestion.sucs.length === 0
                                                text: "Datos insuficientes"; color: root.cMuted; font.pixelSize: root.sp(11)
                                            }
                                            Item { Layout.fillWidth: true }
                                        }
                                        Text {
                                            Layout.fillWidth: true
                                            visible: text.length > 0
                                            text: labReviewPanel.suggestion ? labReviewPanel.suggestion.note : ""
                                            color: root.cMuted; font.pixelSize: root.sp(11)
                                        }
                                        Text {
                                            Layout.fillWidth: true
                                            visible: text.length > 0
                                            text: labReviewPanel.suggestion ? labReviewPanel.suggestion.reason : ""
                                            wrapMode: Text.WordWrap; color: root.cMuted; font.pixelSize: root.sp(11)
                                        }
                                        Repeater {
                                            model: labReviewPanel.info ? labReviewPanel.info.review.observations : []
                                            delegate: Text {
                                                required property var modelData
                                                Layout.fillWidth: true
                                                wrapMode: Text.WordWrap
                                                font.pixelSize: root.fsLabel
                                                color: modelData.severity === "conflict" ? root.cGenOrange : root.cMuted
                                                text: (modelData.severity === "conflict" ? "⚠ " : "• ") + modelData.message
                                            }
                                        }
                                    }
                                }

                                // Clasificación del laboratorio (autoridad): mismos campos que
                                // la tabla Web. Estrato y patrón la proyectan en solo lectura.
                                Rectangle {
                                    id: labClassPanel
                                    readonly property var info: mobileSampleCard.info
                                    readonly property var form: info ? info.form : null
                                    readonly property var fieldErrors: info ? info.validation.fieldErrors : ({})
                                    Layout.fillWidth: true
                                    implicitHeight: labClassColumn.implicitHeight + root.dp(20)
                                    radius: root.dp(12)
                                    color: "transparent"
                                    CalicataLiquidGlass { dark: root.darkMode; accent: root.cGenBlue; danger: root.flow ? root.flow.theme.error : "#D9483B"; anchors.fill: parent; radius: parent.radius; level: "card" }
                                    ColumnLayout {
                                        id: labClassColumn
                                        anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top
                                        anchors.margins: root.dp(10)
                                        spacing: root.dp(8)
                                        RowLayout {
                                            Layout.fillWidth: true
                                            Text { Layout.fillWidth: true; text: "Clasificación del laboratorio"; color: root.cText; font.bold: true; font.pixelSize: root.fsLabel }
                                            Rectangle {
                                                readonly property string stage: labClassPanel.info ? labClassPanel.info.stage : ""
                                                Layout.preferredWidth: estadoText.implicitWidth + root.dp(16)
                                                Layout.preferredHeight: root.dp(22)
                                                radius: height / 2
                                                color: root.labStageColor(stage, true)
                                                Behavior on color { ColorAnimation { duration: root.flow ? root.flow.duration(220) : 220 } }
                                                Text {
                                                    id: estadoText
                                                    anchors.centerIn: parent
                                                    text: (parent.stage === "confirmed" ? "✓ " : "") + (labClassPanel.info ? labClassPanel.info.stageLabel : "")
                                                    color: root.labStageColor(parent.stage, false)
                                                    font.bold: true
                                                    font.pixelSize: root.sp(11)
                                                    Behavior on color { ColorAnimation { duration: root.flow ? root.flow.duration(220) : 220 } }
                                                }
                                            }
                                        }
                                        RowLayout {
                                            Layout.fillWidth: true
                                            spacing: root.dp(8)
                                            PrfPickField {
                                                Layout.fillWidth: true
                                                label: labClassPanel.form && labClassPanel.form.isComposite ? "1.º SUCS principal" : "SUCS principal"
                                                valueText: labClassPanel.form ? labClassPanel.form.primarySucs : ""
                                                placeholder: "Sin seleccionar"
                                                onActivated: root.pickLabClassification(mobileSampleCard.corteIdx, "primary_sucs")
                                            }
                                            PrfPickField {
                                                Layout.fillWidth: true
                                                visible: !!labClassPanel.form && labClassPanel.form.isComposite
                                                label: "2.º Segundo SUCS"
                                                valueText: labClassPanel.form ? labClassPanel.form.secondarySucs : ""
                                                placeholder: "Sin seleccionar"
                                                onActivated: root.pickLabClassification(mobileSampleCard.corteIdx, "secondary_sucs")
                                            }
                                        }
                                        RowLayout {
                                            Layout.fillWidth: true
                                            spacing: root.dp(6)
                                            Repeater {
                                                model: [{ key: false, label: "SUCS simple" }, { key: true, label: "Clasificación compuesta" }]
                                                delegate: PrfSegment {
                                                    required property var modelData
                                                    implicitHeight: root.dp(38)
                                                    label: modelData.label
                                                    isOn: !!(labClassPanel.form && labClassPanel.form.isComposite) === modelData.key
                                                    accent: root.cGenBlue
                                                    accentSoft: root.cGenBlueSoft
                                                    onPicked: root.setLabClassification(mobileSampleCard.corteIdx, "is_composite", modelData.key)
                                                }
                                            }
                                        }
                                        PrfPickField {
                                            Layout.fillWidth: true
                                            label: "AASHTO"
                                            valueText: labClassPanel.form ? labClassPanel.form.aashto : ""
                                            placeholder: "Sin seleccionar"
                                            onActivated: root.pickLabClassification(mobileSampleCard.corteIdx, "aashto")
                                        }
                                        Repeater {
                                            model: ["primarySucs", "secondarySucs"]
                                            delegate: Text {
                                                required property var modelData
                                                Layout.fillWidth: true
                                                visible: text.length > 0
                                                text: String(labClassPanel.fieldErrors[modelData] || "")
                                                color: root.flow ? root.flow.theme.error : "#B4232E"
                                                font.pixelSize: root.sp(11)
                                                wrapMode: Text.WordWrap
                                            }
                                        }
                                        Text {
                                            Layout.fillWidth: true
                                            wrapMode: Text.WordWrap
                                            color: root.cMuted
                                            font.pixelSize: root.sp(11)
                                            text: "Estrato muestra: SUCS " + (labClassPanel.info && labClassPanel.info.projection.sucs.length ? labClassPanel.info.projection.sucs : "Pendiente de laboratorio")
                                                  + " · AASHTO " + (labClassPanel.info && labClassPanel.info.projection.aashto.length ? labClassPanel.info.projection.aashto : "Pendiente de laboratorio")
                                        }
                                    }
                                }

                                // Laboratorio / procedencia: filas compactas; lo guardado se muestra tal cual.
                                Text { text: "Laboratorio / procedencia"; color: root.cText; font.bold: true; font.pixelSize: root.fsLabel }
                                RowLayout {
                                    Layout.fillWidth: true
                                    Text { Layout.fillWidth: true; text: "Fecha de ensayo"; color: root.cMuted; font.pixelSize: root.fsLabel }
                                    BoundTextField {
                                        Layout.preferredWidth: root.dp(150)
                                        placeholderText: "AAAA-MM-DD"
                                        modelText: String(mobileSampleCard.labExtra().test_date || "")
                                        onCommit: function(t) { if(String(t).length && !/^\d{4}-\d{2}-\d{2}$/.test(String(t))){root.showInfo("Fecha de ensayo","Usa AAAA-MM-DD.");return false}; root.setWebLabMeta(mobileSampleCard.corteIdx,"test_date",t); return true }
                                    }
                                }
                                RowLayout {
                                    Layout.fillWidth: true
                                    Text { Layout.fillWidth: true; text: "Laboratorio"; color: root.cMuted; font.pixelSize: root.fsLabel }
                                    BoundTextField {
                                        Layout.preferredWidth: root.dp(190)
                                        placeholderText: "Nombre"
                                        modelText: String(mobileSampleCard.labExtra().laboratory_source || "")
                                        onCommit: function(t) { root.setWebLabMeta(mobileSampleCard.corteIdx,"laboratory_source",String(t).trim().replace(/\s+/g," ")); return true }
                                    }
                                }
                                Text {
                                    Layout.fillWidth: true
                                    wrapMode: Text.WordWrap
                                    color: mobileSampleCard.info && !mobileSampleCard.info.validation.valid ? (root.flow ? root.flow.theme.error : "#B4232E") : root.cMuted
                                    text: !mobileSampleCard.info ? ""
                                          : !mobileSampleCard.info.validation.valid ? "Revisar ensayos: " + mobileSampleCard.info.validation.errors.join(" · ")
                                          : "Contrato de laboratorio válido."
                                }
                            }
                        }
                    }
                }
            }
                }
            }
        }
    }

    // Capa visual mínima de la etapa entrante durante el swipe. Replica la
    // cabecera real de finalPageCol (misma posición con contentY = 0) para
    // que al confirmar la etapa real aparezca exactamente debajo. Sin input.
    Item {
        id: stagePeekLayer
        anchors.fill: vFlick
        z: 1
        clip: true
        enabled: false
        visible: root._swipePeekStage >= 0

        Rectangle {
            width: parent.width
            height: parent.height
            x: root._swipePeekFrozen ? 0
               : stageSlideTranslate.x + root._swipeDir * parent.width
            opacity: 1 - 0.2 * Math.min(1, Math.abs(x) / Math.max(1, parent.width))
            color: root.cPage
            PhotoGlassAmbient { anchors.fill: parent }

            Column {
                x: Math.round((parent.width - width) / 2)
                y: root.dp(12)
                width: parent.width - root.dp(28)
                spacing: root.dp(7)
                GenStageHeader {
                    width: parent.width
                    visible: root._swipePeekStage >= 0
                    codeText: txtCodigo.text
                    projectText: root._projectDisplayName()
                    projectAssigned: !!(root.doc && root.doc.header.projectId)
                    stageText: root.sectionNavigation[Math.max(0, root._swipePeekStage)].shortLabel
                    stageIcon: root._swipePeekStage === 5 ? root.iconNotesName : root._swipePeekStage === 4 ? root.iconPhotosName
                             : root._swipePeekStage === 3 ? root.iconSamplesName : root._swipePeekStage === 2 ? root.iconStrataName
                             : root._swipePeekStage === 1 ? "map.location" : "calgen.code"
                }
            }
        }
    }

    // Instantánea del viewport para la transición de etapa por toque. Mientras corre
    // stageRevealAnimation, vFlick se dibuja SOLO a través de esta textura (hideSource):
    // se rasteriza cuando la etapa nueva cambia (primer frame, capturas de vidrio) y la
    // animación solo transforma un quad. La entrada sigue llegando a vFlick. Fuera de la
    // transición no existe textura (sourceItem null) ni trabajo extra.
    ShaderEffectSource {
        id: stageMotionSnapshot
        x: vFlick.x
        y: vFlick.y
        width: vFlick.width
        height: vFlick.height
        z: 0.5
        readonly property bool active: stageRevealAnimation.running
        sourceItem: active ? vFlick : null
        hideSource: active
        live: true
        visible: active
        transform: Translate { id: stageMotionTranslate; x: 0 }
    }

    // === Un solo scroll vertical para TODA la ficha ===
    FlowCore.ImeAwareFlickable {
        id: vFlick
        flow: root.flow
        anchors.fill: parent
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        pressDelay: root.touchPressDelay
        synchronousDrag: false
        pixelAligned: true
        flickableDirection: Flickable.VerticalFlick

        contentWidth: width
        contentHeight: finalPageCol.implicitHeight + root.dp(110)

        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
        ScrollBar.horizontal: ScrollBar { policy: ScrollBar.AlwaysOff }

        // Fondo que refracta el Liquid Glass de la ficha: HERMANO del contenido (nunca
        // ancestro) y se desplaza con él, así cada superficie conserva su zona de captura
        // durante el scroll (sin re-captura por frame). Mosaico de ambientes de una
        // pantalla (alternos en espejo para que el degradado sea continuo): luz y color
        // a lo largo de toda la ficha, opaco en todo punto (sin texels transparentes).
        Column {
            id: formGlassAmbient
            objectName: "calicataGlassBackdrop"
            readonly property real tileHeight: Math.max(vFlick.height, root.dp(560))
            width: vFlick.width
            Repeater {
                model: Math.max(1, Math.ceil(Math.max(vFlick.height, vFlick.contentHeight) / formGlassAmbient.tileHeight))
                delegate: PhotoGlassAmbient {
                    required property int index
                    width: formGlassAmbient.width
                    height: formGlassAmbient.tileHeight
                    rotation: index % 2 === 1 ? 180 : 0
                }
            }
        }

        // Puente no visual para las claves/IDs que consume la serialización
        // histórica del documento. No contiene presentación ni interacción.
        Item {
            id: documentStateBridge
            visible: false
            width: 0
            height: 0

            TextField { id: txtSupervisor; text: "" }
            TextField { id: txtMaquina; text: "" }
            TextField { id: txtCodigo; text: "" }
            TextField { id: txtPk; text: "" }
            TextField { id: txtUbicacion; text: "" }
            TextField { id: txtUTMX; text: "" }
            TextField { id: txtUTMY; text: "" }
            TextField { id: txtUTMZ; text: "" }
            TextField { id: txtZona; text: "" }
            TextField { id: txtWaterTableDepth; text: "" }
            TextField { id: txtProjectFullName; text: "" }
            Button { id: btnFechaInicio; text: "Seleccionar fecha" }
            Button { id: btnFechaFin; text: "Seleccionar fecha" }
            Button { id: btnTituloCalicata; text: "Nombre del proyecto" }
        }

        GenPopup {
            id: popFechaPicker
            property var targetButton: null
            property string titleText: "Fecha"
            property date selectedDate: new Date()
            property date monthDate: new Date()
            preferredWidth: root.dp(380)
            preferredHeight: calendarColumn.implicitHeight + topPadding + bottomPadding
            function openFor(button, title) {
                targetButton = button
                titleText = title
                selectedDate = root._dateFromTextOrToday(button.text)
                monthDate = selectedDate
                open()
            }
            contentItem: ColumnLayout {
                id: calendarColumn
                spacing: root.dp(10)
                GenDialogHeader {
                    title: "Seleccionar fecha"
                    subtitle: (popFechaPicker.titleText.length
                               ? popFechaPicker.titleText.charAt(0) + popFechaPicker.titleText.slice(1).toLowerCase() + " · "
                               : "")
                              + Qt.formatDate(popFechaPicker.selectedDate, "dd/MM/yyyy")
                    onCloseRequested: popFechaPicker.close()
                }
                RowLayout {
                    Layout.fillWidth: true
                    spacing: root.dp(4)
                    GenRoundIconButton {
                        iconName: "calgen.chevronLeft"
                        Accessible.name: "Mes anterior"
                        onClicked: popFechaPicker.monthDate = new Date(popFechaPicker.monthDate.getFullYear(), popFechaPicker.monthDate.getMonth() - 1, 1)
                    }
                    Text {
                        Layout.fillWidth: true
                        horizontalAlignment: Text.AlignHCenter
                        text: {
                            // Mismo locale que DayOfWeekRow/MonthGrid (evita "September").
                            var s = Qt.locale("es_PE").toString(popFechaPicker.monthDate, "MMMM yyyy")
                            return s.length ? s.charAt(0).toUpperCase() + s.slice(1) : s
                        }
                        color: root.cText
                        font.pixelSize: root.fsField + 2
                        font.bold: true
                    }
                    GenRoundIconButton {
                        iconName: "calgen.chevron"
                        Accessible.name: "Mes siguiente"
                        onClicked: popFechaPicker.monthDate = new Date(popFechaPicker.monthDate.getFullYear(), popFechaPicker.monthDate.getMonth() + 1, 1)
                    }
                }
                DayOfWeekRow {
                    Layout.fillWidth: true
                    locale: Qt.locale("es_PE")
                    delegate: Text {
                        required property string narrowName
                        text: narrowName.toUpperCase()
                        color: root.cMuted
                        font.pixelSize: root.fsLabel
                        font.weight: Font.DemiBold
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                    }
                }
                MonthGrid {
                    Layout.fillWidth: true
                    Layout.preferredHeight: root.dp(252)
                    month: popFechaPicker.monthDate.getMonth()
                    year: popFechaPicker.monthDate.getFullYear()
                    locale: Qt.locale("es_PE")
                    onClicked: function(date) { popFechaPicker.selectedDate = date }
                    delegate: Item {
                        id: dayCell
                        required property var model
                        readonly property bool inMonth: dayCell.model.month === popFechaPicker.monthDate.getMonth()
                        readonly property bool isSelected: dayCell.model.year === popFechaPicker.selectedDate.getFullYear()
                                                           && dayCell.model.month === popFechaPicker.selectedDate.getMonth()
                                                           && dayCell.model.day === popFechaPicker.selectedDate.getDate()
                        implicitWidth: root.dp(40)
                        implicitHeight: root.dp(36)
                        Rectangle {
                            anchors.centerIn: parent
                            width: Math.min(parent.width, parent.height, root.dp(40))
                            height: width
                            radius: width / 2
                            color: dayCell.isSelected ? root.cGenBlue : "transparent"
                            border.width: dayCell.model.today && !dayCell.isSelected ? 1 : 0
                            border.color: root.cGenBlue
                            Behavior on color { ColorAnimation { duration: 140 } }
                        }
                        Text {
                            anchors.centerIn: parent
                            text: dayCell.model.day
                            color: dayCell.isSelected ? (root.darkMode ? root.brand.ingemaDeep : "#FFFFFF")
                                 : dayCell.model.today ? root.cGenBlue : root.cText
                            opacity: dayCell.inMonth ? 1 : 0.35
                            font.pixelSize: root.fsField
                            font.bold: dayCell.isSelected || dayCell.model.today
                        }
                    }
                }
                RowLayout {
                    Layout.fillWidth: true
                    spacing: root.dp(10)
                    GenDialogButton { text: "Cancelar"; onClicked: popFechaPicker.close() }
                    GenDialogButton {
                        primary: true
                        text: "Aceptar"
                        onClicked: {
                            if (!popFechaPicker.targetButton) return
                            var formatted = Qt.formatDate(popFechaPicker.selectedDate, "dd/MM/yyyy")

                            if (popFechaPicker.targetButton === btnFechaFin) {
                                var startDate = root._parseDMY(btnFechaInicio.text)
                                if (startDate && popFechaPicker.selectedDate.getTime() < startDate.getTime()) {
                                    root.showInfo("Fecha no válida",
                                                  "La fecha de fin no puede ser anterior a la fecha de inicio.")
                                    return
                                }
                            }

                            popFechaPicker.targetButton.text = formatted

                            if (popFechaPicker.targetButton === btnFechaInicio) {
                                var existingEnd = root._parseDMY(btnFechaFin.text)
                                if (existingEnd && existingEnd.getTime() < popFechaPicker.selectedDate.getTime()) {
                                    btnFechaFin.text = formatted
                                    root.showInfo("Fecha fin ajustada",
                                                  "La fecha fin se ajustó para que no quede antes de la fecha de inicio.")
                                }
                            }

                            root._markDirty()
                            popFechaPicker.close()
                        }
                    }
                }
            }
        }

        // =============================================================
        // DISEÑO FINAL MÓVIL
        // Una sola columna adaptable, sin tablas de escritorio ni scroll
        // horizontal. Todos los controles escriben en los mismos modelos.
        // =============================================================
        ParallelAnimation {
            id: stageRevealAnimation
            NumberAnimation {
                target: stageMotionSnapshot
                property: "opacity"
                from: 0.0
                to: 1.0
                duration: root.flow && root.flow.motionAllowed ? 220 : 0
                easing.type: Easing.OutCubic
            }
            NumberAnimation {
                target: stageMotionTranslate
                property: "x"
                to: 0
                duration: root.flow && root.flow.motionAllowed ? 220 : 0
                easing.type: Easing.OutCubic
            }
        }

        Column {
            id: finalPageCol
            opacity: 1.0
            transform: Translate {
                id: stageSlideTranslate
                x: 0
                onXChanged: root._syncSwipeProgress()
            }
            x: Math.round((vFlick.width - width) / 2)
            y: root.dp(12)
            width: vFlick.width - root.dp(28)
            spacing: root.dp(12)

            Column {
                width: parent.width
                spacing: root.dp(7)
                // Una sola cabecera para TODAS las etapas (General … Revisión): código,
                // proyecto, "FICHA DE CALICATA", insignia de vidrio con el icono y título.
                GenStageHeader {
                    width: parent.width
                    codeText: txtCodigo.text
                    projectText: root._projectDisplayName()
                    projectAssigned: !!(root.doc && root.doc.header.projectId)
                    stageText: root.sectionNavigation[root.stageIndex].shortLabel
                    stageIcon: root.stageIndex === 5 ? root.iconNotesName : root.stageIndex === 4 ? root.iconPhotosName
                             : root.stageIndex === 3 ? root.iconSamplesName : root.stageIndex === 2 ? root.iconStrataName
                             : root.stageIndex === 1 ? "map.location" : "calgen.code"
                }
                // Presencia (Supabase Realtime): quién está en esta ficha.
                Flow {
                    width: parent.width
                    spacing: root.dp(8)
                    visible: typeof CalicataCloud !== "undefined" && CalicataCloud.presenceMembers.length > 0
                    Repeater {
                        model: typeof CalicataCloud !== "undefined" ? CalicataCloud.presenceMembers : []
                        delegate: Row {
                            required property var modelData
                            spacing: root.dp(4)
                            Rectangle {
                                width: root.dp(22); height: width; radius: width / 2
                                color: "transparent"
                                CalicataLiquidGlass { dark: root.darkMode; accent: root.cGenBlue; danger: root.flow ? root.flow.theme.error : "#D9483B"; anchors.fill: parent; radius: parent.radius; tone: modelData.mode === "EDITING" ? "primary" : "glass" }
                                Text { anchors.centerIn: parent; text: modelData.initial; color: root.cText; font.pixelSize: root.sp(11); font.bold: true }
                            }
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: (modelData.self ? "Tú" : modelData.name) + " · " + (modelData.mode === "EDITING" ? "editando" : "viendo")
                                color: root.cMuted; font.pixelSize: root.fsLabel
                            }
                        }
                    }
                }
            }



            MobileStageBody {
                id: mobileGeneralSection
                sectionNumber: 1

                // ---- Identificación ----
                GenGroupHeader { title: "IDENTIFICACIÓN"; accent: root.cGenBlue }

                GenHeaderField {
                    label: "Código"
                    labelCaps: true
                    iconName: "calgen.code"
                    boundText: txtCodigo.text
                    inputPlaceholder: "Sin registrar"
                    commitHandler: function(t) {
                        root._setCanonicalCalicataCode(t)
                        // Un código que termina en progresiva válida la refleja.
                        var pkFromCode = Rules.progresivaFromCode(t)
                        if (pkFromCode.length && pkFromCode !== txtPk.text.trim())
                            root._setProgresiva(pkFromCode, false)
                    }
                }

                // Proyecto = projects.name (contrato Web: una sola fuente para la
                // ficha, el rótulo de fotos y la exportación). Ni nombre largo ni
                // nombre corto se editan por ficha; los valores antiguos
                // (project_full_name / project_short_name) se conservan en el
                // documento y solo se muestran si la ficha aún no tiene proyecto.
                GenFieldShell {
                    label: "Proyecto"
                    caption: "Nombre del proyecto en InGe+. Elegirlo define dónde se guarda y sincroniza la ficha."
                    iconName: "calgen.project"
                    tappable: true
                    emphasized: true
                    valueText: root._projectDisplayName()
                    onActivated: root._openProjectPicker()
                }
                Text {
                    Layout.fillWidth: true
                    Layout.leftMargin: root.dp(4)
                    Layout.topMargin: -root.dp(6)
                    text: root.doc ? String(root.doc.header.projectCode || "") : ""
                    visible: text.length > 0
                    color: root.cMuted
                    font.pixelSize: root.fsLabel
                    wrapMode: Text.WordWrap
                }
                Text {
                    Layout.fillWidth: true
                    Layout.leftMargin: root.dp(4)
                    readonly property string legacyName: root.doc && !root.doc.header.projectId
                        ? String(root.doc.header.project_full_name || root.doc.header.excel_title || "").trim() : ""
                    text: "Nombre registrado antes de asignar proyecto: " + legacyName
                    visible: legacyName.length > 0
                    color: root.cMuted
                    font.pixelSize: root.fsLabel
                    wrapMode: Text.WordWrap
                }

                // ---- Fechas y responsable ----
                GenGroupHeader { title: "FECHAS Y RESPONSABLE"; accent: root.cGenOrange }

                GenFieldShell {
                    label: "Fecha inicio"
                    iconName: "calgen.date"
                    accent: root.cGenOrange
                    accentSoft: root.cGenOrangeSoft
                    tappable: true
                    valueText: btnFechaInicio.text === "Seleccionar fecha" ? "" : btnFechaInicio.text
                    placeholder: "Seleccionar fecha"
                    onActivated: root._openDatePicker(btnFechaInicio, "FECHA INICIO")
                }
                // Hora de la ficha (opcional, HH:mm:ss): rótulo de las fotografías.
                // Vacía = cada foto conserva la hora del sistema fijada al tomarla.
                GenHeaderField {
                    id: horaInicioField
                    label: "Hora (opcional)"
                    iconName: "calgen.date"
                    accent: root.cGenOrange
                    accentSoft: root.cGenOrangeSoft
                    headerKey: "hora_inicio"
                    inputPlaceholder: "HH:mm:ss"
                    inputMaximumLength: 8
                    commitHandler: function(t) {
                        var normalized = Rules.normalizeOptionalTime(t)
                        if (normalized === null) {
                            horaInicioField.inputValidationError = "Usa el formato HH:mm:ss (por ejemplo 20:06:33) o déjala vacía."
                            return false
                        }
                        var h = Object.assign({}, root.doc.header)
                        h.hora_inicio = normalized
                        h.start_time = normalized   // columna remota (cross-device)
                        root.doc.header = h
                    }
                }
                GenFieldShell {
                    label: "Fecha fin"
                    iconName: "calgen.date"
                    accent: root.cGenOrange
                    accentSoft: root.cGenOrangeSoft
                    tappable: true
                    valueText: btnFechaFin.text === "Seleccionar fecha" ? "" : btnFechaFin.text
                    placeholder: "Seleccionar fecha"
                    onActivated: root._openDatePicker(btnFechaFin, "FECHA FIN")
                }
                Text {
                    Layout.fillWidth: true
                    visible: text.length > 0
                    text: Rules.validateFieldDates(root.doc ? String(root.doc.header.fecha_inicio || "") : "",
                                                   root.doc ? String(root.doc.header.fecha_fin || "") : "")
                    color: root.flow ? root.flow.theme.error : "#B4232E"
                    font.pixelSize: root.fsLabel
                    wrapMode: Text.WordWrap
                }

                GenHeaderField {
                    label: "Supervisor"
                    labelCaps: true
                    iconName: "calgen.supervisor"
                    accent: root.cGenViolet
                    accentSoft: root.cGenVioletSoft
                    boundText: txtSupervisor.text
                    inputMaximumLength: Rules.SUPERVISOR_MAX_LENGTH
                    inputPlaceholder: "Sin registrar"
                    commitHandler: function(t) { txtSupervisor.text = t }
                }

                GenFieldShell {
                    readonly property int machineIndex: root._catalogIndex(txtMaquina.text, Rules.MACHINE_OPTIONS, root.machineHistorical)
                    label: "Maquinaria"
                    iconName: "calgen.machine"
                    accent: root.cGenTeal
                    accentSoft: root.cGenTealSoft
                    tappable: true
                    valueText: machineIndex > 0 ? String(root.machineModel[machineIndex]) : ""
                    placeholder: String(root.machineModel[0])
                    onActivated: root._openMachinePicker()
                }

                // ---- Ficha ----
                // `description` es el "Título de la ficha / testificación" de Web.
                // `title` solo se fija al crear (Web: "Título" del alta) y no se
                // edita en el detalle; su valor se conserva y viaja tal cual.
                GenGroupHeader { title: "FICHA"; accent: root.cGenBlue }

                GenHeaderField {
                    label: "Título de la ficha / testificación"
                    glyph: "T"
                    headerKey: "description"
                }

                // ---- Excavación ----
                GenGroupHeader { title: "EXCAVACIÓN"; accent: root.cGenGreen }

                GridLayout {
                    Layout.fillWidth: true
                    columns: width >= root.dp(300) ? 2 : 1
                    columnSpacing: root.dp(10)
                    rowSpacing: root.dp(10)
                    GenHeaderField {
                        Layout.preferredWidth: 1
                        Layout.alignment: Qt.AlignTop
                        label: "Largo de excavación (m)"
                        iconName: "calgen.length"
                        accent: root.cGenGreen
                        accentSoft: root.cGenGreenSoft
                        headerKey: "length_m"
                        numeric: true
                        hint: "Ej. 2.5"
                    }
                    GenHeaderField {
                        Layout.preferredWidth: 1
                        Layout.alignment: Qt.AlignTop
                        label: "Ancho de excavación (m)"
                        iconName: "calgen.width"
                        accent: root.cGenGreen
                        accentSoft: root.cGenGreenSoft
                        headerKey: "width_m"
                        numeric: true
                        hint: "Ej. 1.8"
                    }
                }

                GenHeaderField {
                    label: "Descripción técnica (solo Android)"
                    iconName: "calgen.description"
                    accent: root.cGenGreen
                    accentSoft: root.cGenGreenSoft
                    headerKey: "technical_description"
                }

                GridLayout {
                    Layout.fillWidth: true
                    columns: width >= root.dp(300) ? 2 : 1
                    columnSpacing: root.dp(10)
                    rowSpacing: root.dp(10)
                    GenFieldShell {
                        Layout.preferredWidth: 1
                        Layout.alignment: Qt.AlignTop
                        label: "Profundidad (m)"
                        labelCaps: false
                        caption: "Derivada de los cortes"
                        iconName: "calgen.depth"
                        accent: root.cGenGreen
                        accentSoft: root.cGenGreenSoft
                        readOnly: true
                        valueText: root.derivedDepthText
                        placeholder: "Sin cortes completos"
                    }
                    GenFieldShell {
                        Layout.preferredWidth: 1
                        Layout.alignment: Qt.AlignTop
                        label: "Nivel freático (m)"
                        labelCaps: false
                        caption: root.groundwaterCustom ? "Personalizado" : "Primer corte con AGUA"
                        iconName: "calgen.water"
                        accent: root.cGenGreen
                        accentSoft: root.cGenGreenSoft
                        readOnly: true
                        valueText: root.effectiveGroundwaterText
                        placeholder: "No registrado"
                    }
                }

                // ---- Identidad del reporte ----
                Button {
                    id: genIdentityEntry
                    Layout.fillWidth: true
                    Layout.topMargin: root.dp(10)
                    implicitHeight: Math.max(root.dp(76), genIdentityRow.implicitHeight + topPadding + bottomPadding)
                    padding: root.dp(12)
                    onClicked: identityPopup.open()
                    scale: down ? 0.985 : 1
                    Behavior on scale { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
                    background: CalicataLiquidGlass { dark: root.darkMode; accent: root.cGenBlue; danger: root.flow ? root.flow.theme.error : "#D9483B"; radius: root.dp(14); tone: "tinted"; selected: true; pressed: genIdentityEntry.down }
                    contentItem: RowLayout {
                        id: genIdentityRow
                        spacing: root.dp(12)
                        GenIconBadge {
                            Layout.preferredWidth: root.dp(44)
                            Layout.preferredHeight: root.dp(44)
                            Layout.alignment: Qt.AlignVCenter
                            radius: root.dp(12)
                            iconName: "calgen.identity"
                            accentSoft: root.cField
                        }
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: root.dp(3)
                            Text {
                                Layout.fillWidth: true
                                text: "Identidad del reporte"
                                color: root.cText
                                font.bold: true
                                font.pixelSize: root.fsField + 1
                                elide: Text.ElideRight
                            }
                            Text {
                                Layout.fillWidth: true
                                text: "Configura logos e información del reporte"
                                color: root.cMuted
                                font.pixelSize: root.fsLabel
                                wrapMode: Text.WordWrap
                            }
                            Flow {
                                Layout.fillWidth: true
                                Layout.topMargin: root.dp(3)
                                spacing: root.dp(6)
                                Repeater {
                                    model: [
                                        { ok: root.hasLogoProyecto, text: root.hasLogoProyecto ? "Proyecto listo" : "Proyecto pendiente" },
                                        { ok: root.hasLogoMtc, text: root.hasLogoMtc ? "MTC / entidad listo" : "MTC / entidad pendiente" }
                                    ]
                                    delegate: Rectangle {
                                        required property var modelData
                                        width: identityChipRow.implicitWidth + root.dp(16)
                                        height: root.dp(24)
                                        radius: height / 2
                                        color: "transparent"
                                        CalicataLiquidGlass { dark: root.darkMode; accent: root.cGenBlue; danger: root.flow ? root.flow.theme.error : "#D9483B"; anchors.fill: parent; radius: parent.radius }
                                        Row {
                                            id: identityChipRow
                                            anchors.centerIn: parent
                                            spacing: root.dp(5)
                                            Rectangle {
                                                anchors.verticalCenter: parent.verticalCenter
                                                width: root.dp(6)
                                                height: width
                                                radius: width / 2
                                                color: modelData.ok ? root.cGenGreen : root.cGenOrange
                                            }
                                            Text {
                                                anchors.verticalCenter: parent.verticalCenter
                                                text: modelData.text
                                                color: root.cText
                                                font.pixelSize: root.sp(11)
                                            }
                                        }
                                    }
                                }
                            }
                        }
                        Components.FlowIcon {
                            Layout.preferredWidth: root.dp(18)
                            Layout.preferredHeight: root.dp(18)
                            Layout.alignment: Qt.AlignVCenter
                            name: "calgen.chevron"
                            flow: root.flow
                            tintColor: root.cGenBlue
                            activeTintColor: root.cGenBlue
                            inactiveOpacity: 1
                        }
                    }
                }
            }

            MobileStageBody {
                id: mobileLocationSection
                sectionNumber: 2
                sectionTitle: "Ubicación"
                sectionSubtitle: "Coordenadas UTM del documento"

                // ---- Mapa (protagonista) ----
                Item {
                    id: locationMapCard
                    readonly property var point: root.doc ? root._locationPoint() : ({ lat: NaN, lon: NaN })
                    readonly property bool hasPoint: isFinite(point.lat) && isFinite(point.lon)
                    readonly property real cardRadius: root.dp(16)
                    Layout.fillWidth: true
                    Layout.preferredHeight: root.dp(300)
                    visible: Qt.platform.os === "android"

                    Rectangle {
                        anchors.fill: parent
                        radius: locationMapCard.cardRadius
                        color: "transparent"
                        CalicataLiquidGlass { dark: root.darkMode; accent: root.cGenBlue; danger: root.flow ? root.flow.theme.error : "#D9483B"; anchors.fill: parent; radius: parent.radius }
                    }

                    Loader {
                        id: locationPreview
                        anchors.fill: parent
                        active: Qt.platform.os === "android" && root._locationMapWarm && !root.coordinatePickerOpen
                        // Creación incremental: no bloquea el frame de la transición a Ubicación.
                        asynchronous: true
                        source: active ? Qt.resolvedUrl("CalicataPointPicker.qml") : ""
                        function updatePoint() {
                            if (!item) return
                            var p = root._locationPoint()
                            var h = root.doc ? root.doc.header : {}
                            item.selected = false
                            if (isFinite(p.lat) && isFinite(p.lon))
                                item.selectCoordinate(p.lat, p.lon, Rules.parseDecimalSafe(h.utm_z))
                        }
                        onLoaded: {
                            item.interactive = false
                            item.statusCardOnly = true
                            item.darkMode = root.darkMode
                            updatePoint()
                        }
                        Connections {
                            target: root.doc
                            function onDataChanged() { locationPreview.updatePoint() }
                        }
                        TapHandler { onTapped: if (root.openMapAction) root.openMapAction() }
                    }

                    // Esquinas redondeadas sin capa/máscara sobre el panel de ubicación: un
                    // anillo del color de página recorta visualmente el mapa.
                    Rectangle {
                        anchors.fill: parent
                        anchors.margins: -root.dp(8)
                        radius: locationMapCard.cardRadius + root.dp(8)
                        color: "transparent"
                        border.width: root.dp(8)
                        border.color: root.cPage
                    }
                    Rectangle {
                        anchors.fill: parent
                        radius: locationMapCard.cardRadius
                        color: "transparent"
                        border.width: 1
                        border.color: root.cBorder
                    }

                    // Material de los flotantes: tokens del peek "Información de
                    // la calicata"; el backdrop es solo el mapa de esta tarjeta.
                    QtObject {
                        id: locationGlassTokens
                        readonly property bool shown: locationMapCard.visible && locationPreview.status === Loader.Ready
                        readonly property Item glassBackdrop: locationPreview.status === Loader.Ready ? locationPreview : null
                        readonly property real materialPosition: 0
                        readonly property bool lowCostGlass: Mobile.InGeCoreFlow.lowMemoryMode
                            || Mobile.InGeCoreFlow.performance.profile >= Mobile.InGeCoreFlow.performance.safe
                        readonly property color glassTint: root.darkMode ? Qt.rgba(0.0824, 0.102, 0.1882, 0.10) : Qt.rgba(0.95, 0.97, 1.0, 0.02)
                        // Opaco: Qt premultiplica los colores de un ShaderEffect; translúcido se pintaría gris.
                        readonly property color fallbackGlass: root.darkMode ? Qt.rgba(0.14, 0.16, 0.20, 1.0) : Qt.rgba(0.985, 0.99, 1.0, 1.0)
                        readonly property real rimLight: root.darkMode ? 0.18 : 0.20
                        readonly property real rimShade: root.darkMode ? 0.04 : 0.035
                        readonly property real rimSheen: root.darkMode ? 0.03 : 0.015
                        readonly property real edgeContrast: root.darkMode ? 0.0 : 0.03
                        readonly property real glassSaturation: 1.12
                        readonly property color shadowColor: Qt.rgba(0.0824, 0.102, 0.1882, root.darkMode ? 0.22 : 0.10)
                    }

                    // Ubicación de la calicata (lat/lon reales guardados en la ficha).
                    Item {
                        x: root.dp(10)
                        y: root.dp(10)
                        // El rotulo tiene texto minimo de 12 px (sp): el recuadro crece
                        // con el y nunca pasa del ancho disponible del mapa.
                        width: Math.min(parent.width - root.dp(20),
                                        Math.max(root.dp(230), locationPointTitle.implicitWidth + root.dp(24)))
                        height: locationPointColumn.implicitHeight + root.dp(20)
                        FlowCore.LiquidGlassSurface {
                            anchors.fill: parent
                            tokens: locationGlassTokens
                            cornerRadius: root.dp(14)
                            surfaceName: "calicata-location-point"
                            // Captura viva justificada: el mapa carga teselas y se desplaza bajo el vidrio
                            // (ShaderEffectSource solo re-renderiza cuando el mapa cambia).
                            liveCapture: true
                            lens: 0.15
                            frost: 6
                            frostTaps: 6
                            magnify: 0
                            bevel: root.dp(6)
                            elevation: true
                        }
                        Rectangle {
                            anchors.fill: parent
                            radius: root.dp(14)
                            color: root.darkMode ? Qt.rgba(0.0824, 0.102, 0.1882, 0.62) : Qt.rgba(0.98, 0.99, 1.0, 0.78)
                            border.width: 1
                            border.color: root.darkMode ? Qt.rgba(1, 1, 1, 0.08) : Qt.rgba(1, 1, 1, 0.55)
                        }
                        Column {
                            id: locationPointColumn
                            x: root.dp(12)
                            y: root.dp(10)
                            width: parent.width - root.dp(24)
                            spacing: root.dp(2)
                            Text {
                                id: locationPointTitle
                                width: Math.min(implicitWidth, parent.width)
                                elide: Text.ElideRight
                                text: "UBICACIÓN DE LA CALICATA"
                                color: root.cMuted
                                font.pixelSize: root.sp(10)
                                font.letterSpacing: 1.4
                                font.weight: Font.DemiBold
                            }
                            Repeater {
                                model: locationMapCard.hasPoint
                                       ? [{ k: "Lat", v: locationMapCard.point.lat.toFixed(6) },
                                          { k: "Lon", v: locationMapCard.point.lon.toFixed(6) }]
                                       : [{ k: "", v: "Sin ubicación GPS" }]
                                delegate: Row {
                                    required property var modelData
                                    spacing: root.dp(8)
                                    Text {
                                        visible: modelData.k.length > 0
                                        width: root.dp(28)
                                        text: modelData.k
                                        color: root.cMuted
                                        font.pixelSize: root.fsLabel
                                    }
                                    Text {
                                        text: modelData.v
                                        color: root.cText
                                        font.pixelSize: root.fsField
                                        font.weight: Font.DemiBold
                                    }
                                }
                            }
                        }
                    }

                    // Acción real: abre la pantalla de ubicación GPS del dispositivo.
                    Item {
                        id: locationAdjust
                        anchors.right: parent.right
                        anchors.bottom: parent.bottom
                        anchors.margins: root.dp(10)
                        width: locationAdjustRow.implicitWidth + root.dp(28)
                        height: root.dp(42)
                        scale: locationAdjustTap.pressed ? 0.985 : 1
                        Behavior on scale { NumberAnimation { duration: 130; easing.type: Easing.OutCubic } }
                        Accessible.role: Accessible.Button
                        Accessible.name: locationMapCard.hasPoint ? "Actualizar ubicación GPS" : "Obtener ubicación GPS"
                        FlowCore.LiquidGlassSurface {
                            anchors.fill: parent
                            tokens: locationGlassTokens
                            cornerRadius: height / 2
                            surfaceName: "calicata-location-adjust"
                            // Captura viva justificada: el mapa carga teselas y se desplaza bajo el vidrio
                            // (ShaderEffectSource solo re-renderiza cuando el mapa cambia).
                            liveCapture: true
                            lens: 0.15
                            frost: 6
                            frostTaps: 6
                            magnify: 0
                            bevel: root.dp(6)
                            elevation: true
                        }
                        Rectangle {
                            anchors.fill: parent
                            radius: height / 2
                            color: locationAdjustTap.pressed ? root.cGenBlueSoft
                                   : (root.darkMode ? Qt.rgba(0.0824, 0.102, 0.1882, 0.62) : Qt.rgba(0.98, 0.99, 1.0, 0.78))
                            border.width: 1
                            border.color: root.darkMode ? Qt.rgba(1, 1, 1, 0.08) : Qt.rgba(1, 1, 1, 0.55)
                            Behavior on color { ColorAnimation { duration: 130 } }
                        }
                        Row {
                            id: locationAdjustRow
                            anchors.centerIn: parent
                            spacing: root.dp(6)
                            Components.FlowIcon {
                                anchors.verticalCenter: parent.verticalCenter
                                width: root.dp(18)
                                height: root.dp(18)
                                name: "map.location"
                                flow: root.flow
                                tintColor: root.cGenBlue
                                activeTintColor: root.cGenBlue
                                inactiveOpacity: 1
                            }
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: locationMapCard.hasPoint ? "Actualizar ubicación" : "Obtener ubicación GPS"
                                color: root.cGenBlue
                                font.pixelSize: root.fsLabel
                                font.weight: Font.DemiBold
                            }
                        }
                        MouseArea {
                            id: locationAdjustTap
                            anchors.fill: parent
                            onClicked: if (root.openMapAction) root.openMapAction()
                        }
                    }
                }
                Label { Layout.fillWidth: true; visible: locationPreview.status === Loader.Error; text: "No se pudo cargar el panel de ubicación. Revisa el módulo de GPS."; color: root.cMuted; wrapMode: Text.WordWrap }
                Label { Layout.fillWidth: true; visible: Qt.platform.os !== "android"; text: "Mapa disponible en Android. En Desktop puedes editar las coordenadas UTM."; color: root.cMuted; wrapMode: Text.WordWrap }

                Rectangle {
                    visible: root.gpsCaptureTone !== "idle"
                    Layout.fillWidth: true
                    Layout.preferredHeight: root.dp(40)
                    radius: root.dp(12)
                    color: root.gpsCaptureTone === "success"
                           ? (root.darkMode ? "#24302D" : root.brand.ingemaGreenWash)
                           : (root.gpsCaptureTone === "error"
                              ? (root.darkMode ? "#402326" : "#FDECEC")
                              : root.cSurfaceAlt)
                    border.width: 1
                    border.color: root.gpsCaptureTone === "success"
                                  ? (root.darkMode ? "#34462A" : "#BFC9B3")
                                  : (root.gpsCaptureTone === "error"
                                     ? (root.darkMode ? "#8B454C" : "#F2B9BE")
                                     : root.cBorder)

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: root.dp(10)
                        anchors.rightMargin: root.dp(10)
                        spacing: root.dp(8)

                        FlowCore.FlowBusyIndicator {
                            Layout.preferredWidth: root.dp(18)
                            Layout.preferredHeight: root.dp(18)
                            flow: root.flow
                            running: root.gpsCaptureActive
                                     && (!root.flow || root.flow.motionAllowed)
                            accent: root.cAccent
                            track: root.cBorder
                            stroke: 2
                        }
                        Components.FlowIcon {
                            visible: !root.gpsCaptureActive
                                     || (root.flow && !root.flow.motionAllowed)
                            Layout.preferredWidth: root.dp(18)
                            Layout.preferredHeight: root.dp(18)
                            sourceOverride: root.icLocation
                            flow: root.flow
                            active: root.gpsCaptureTone === "success"
                            tintEnabled: false
                        }
                        Text {
                            Layout.fillWidth: true
                            text: root.gpsCaptureStatus
                            color: root.gpsCaptureTone === "success"
                                   ? (root.darkMode ? root.brand.ingemaGreenTint : root.brand.ingemaGreen)
                                   : (root.gpsCaptureTone === "error"
                                      ? (root.darkMode ? "#FFADB4" : "#A93640")
                                      : root.cMuted)
                            font.pixelSize: root.fsLabel
                            elide: Text.ElideRight
                        }
                    }
                }

                // ---- Coordenadas UTM (2 × 2, editables como antes) ----
                GenGroupHeader { title: "COORDENADAS UTM"; accent: root.cGenBlue }

                GridLayout {
                    Layout.fillWidth: true
                    columns: width >= root.dp(300) ? 2 : 1
                    columnSpacing: root.dp(10)
                    rowSpacing: root.dp(10)
                    GenHeaderField {
                        Layout.preferredWidth: 1
                        Layout.alignment: Qt.AlignTop
                        label: "X UTM (Este)"
                        iconName: "calgen.length"
                        inputKind: Rules.COORDINATE
                        inputPlaceholder: "X UTM"
                        boundText: txtUTMX.text
                        commitHandler: function(t) { txtUTMX.text = t; root._manualCoordinatesChanged() }
                    }
                    GenHeaderField {
                        Layout.preferredWidth: 1
                        Layout.alignment: Qt.AlignTop
                        label: "Y UTM (Norte)"
                        iconName: "calgen.width"
                        inputKind: Rules.COORDINATE
                        inputPlaceholder: "Y UTM"
                        boundText: txtUTMY.text
                        commitHandler: function(t) { txtUTMY.text = t; root._manualCoordinatesChanged() }
                    }
                    GenHeaderField {
                        Layout.preferredWidth: 1
                        Layout.alignment: Qt.AlignTop
                        label: "Z UTM / Cota"
                        iconName: "calgen.depth"
                        accent: root.cGenGreen
                        accentSoft: root.cGenGreenSoft
                        inputKind: Rules.ELEVATION
                        inputMinimum: -12000
                        inputPlaceholder: "Z UTM / Cota"
                        boundText: txtUTMZ.text
                        // Escrita a mano = fuente MANUAL (nunca se reemplaza en silencio).
                        commitHandler: function(t) { root._applyAltitudePatch(Elevation.manualHeaderPatch(t)) }
                    }
                    GenHeaderField {
                        Layout.preferredWidth: 1
                        Layout.alignment: Qt.AlignTop
                        label: "Zona UTM"
                        iconName: "nav.map"
                        accent: root.cGenTeal
                        accentSoft: root.cGenTealSoft
                        inputPlaceholder: "Zona (ej. 18L)"
                        boundText: txtZona.text
                        commitHandler: function(t) { txtZona.text = t.toUpperCase(); root._manualCoordinatesChanged() }
                    }
                }
                // Altitud / Cota Z: valor, origen y acción explícita "Obtener altitud".
                RowLayout {
                    Layout.fillWidth: true
                    spacing: root.dp(10)
                    Text {
                        Layout.fillWidth: true
                        text: (root.elevationStatus.length ? root.elevationStatus
                              : Elevation.statusText(root.doc ? root.doc.header : {}))
                              + (root.elevationWarning.length ? "\nAdvertencia: " + root.elevationWarning : "")
                        color: root.elevationWarning.length ? (root.flow ? root.flow.theme.warning : "#B26A00") : root.cMuted
                        font.pixelSize: root.fsLabel
                        wrapMode: Text.WordWrap
                    }
                    GenDialogButton {
                        text: root.elevationBusy ? "Consultando…" : "Obtener altitud"
                        enabled: !root.elevationBusy && !!root.doc
                        onClicked: root.resolveAltitude("explicit", NaN)
                    }
                }
                // La nube guarda solo el número (utm_zone 1..60); la banda es local.
                Text {
                    Layout.fillWidth: true
                    Layout.leftMargin: root.dp(2)
                    Layout.topMargin: -root.dp(4)
                    readonly property var zoneMatch: /^(\d{1,2})\s*([C-HJ-NP-X])?$/i.exec(txtZona.text.trim())
                    readonly property bool zoneValid: !!zoneMatch && Number(zoneMatch[1]) >= 1 && Number(zoneMatch[1]) <= 60
                    visible: txtZona.text.trim().length > 0
                    text: zoneValid ? "Nube: zona " + Number(zoneMatch[1]) + " · " + (root.doc && root.doc.header.datum === "PSAD56" ? "PSAD56" : "WGS84")
                                    : "Zona no reconocida: se conserva localmente y no se envía a la nube."
                    color: zoneValid ? root.cMuted : (root.flow ? root.flow.theme.error : "#B4232E")
                    font.pixelSize: root.sp(11)
                    wrapMode: Text.WordWrap
                }

                // ---- Sistema geodésico ----
                GenGroupHeader { title: "SISTEMA GEODÉSICO"; accent: root.cGenTeal }

                GenFieldShell {
                    readonly property var datumOptions: ["Seleccionar datum", "WGS84", "PSAD56"]
                    readonly property int datumIndex: root.doc && root.doc.header.datum === "WGS84" ? 1
                                                      : root.doc && root.doc.header.datum === "PSAD56" ? 2 : 0
                    label: "Datum"
                    iconName: "map.layers"
                    accent: root.cGenTeal
                    accentSoft: root.cGenTealSoft
                    tappable: true
                    valueText: datumIndex > 0 ? datumOptions[datumIndex] : ""
                    placeholder: datumOptions[0]
                    onActivated: root._openOptionPicker("Seleccionar datum", datumOptions, datumIndex,
                                                        "map.layers", root.cGenTeal, root.cGenTealSoft,
                                                        function(i) {
                                                            root._changeDatum(i === 1 ? "WGS84" : i === 2 ? "PSAD56" : "")
                                                            root._markDirty()
                                                        })
                }

                // ---- Referencia vial ----
                GenGroupHeader { title: "REFERENCIA VIAL"; accent: root.cGenOrange }

                GenFieldShell {
                    readonly property int roadIndex: root._catalogIndex(root.roadSideValue, Rules.ROAD_SIDE_OPTIONS, root.roadSideHistorical)
                    label: "Lado de la vía"
                    iconName: "map.marker"
                    accent: root.cGenOrange
                    accentSoft: root.cGenOrangeSoft
                    tappable: true
                    valueText: roadIndex > 0 ? String(root.roadSideModel[roadIndex]) : ""
                    placeholder: String(root.roadSideModel[0])
                    onActivated: root._openOptionPicker("Lado de la vía", root.roadSideModel, roadIndex,
                                                        "map.marker", root.cGenOrange, root.cGenOrangeSoft,
                                                        function(i) {
                                                            if (i <= 0) root.roadSideValue = ""
                                                            else if (i <= Rules.ROAD_SIDE_OPTIONS.length) root.roadSideValue = Rules.ROAD_SIDE_OPTIONS[i - 1]
                                                            // El valor histórico se conserva tal cual.
                                                            root._markDirty()
                                                        })
                }

                GenFieldShell {
                    label: "Progresiva (XX+XXX)"
                    labelCaps: false
                    glyph: "PK"
                    accent: root.cGenOrange
                    accentSoft: root.cGenOrangeSoft
                    focused: progresivaField.activeFocus
                    contentHeight: progresivaField.implicitHeight
                    BoundTextField {
                        id: progresivaField
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        leftPadding: 0
                        rightPadding: 0
                        background: Item {}
                        placeholderText: "Progresiva"
                        numericKind: Rules.CHAINAGE_PK
                        inputMethodHints: Qt.ImhDigitsOnly
                        modelText: txtPk.text
                        inputFilter: function(previous, next) { return Rules.acceptProgresivaDraft(previous, next) }
                        onCommit: function(t) {
                            var normalized = Rules.normalizeProgresiva(t)
                            if (normalized.length && !Rules.isValidProgresiva(normalized)
                                    && normalized !== txtPk.text.trim()) {
                                progresivaField.validationError = "Completa la progresiva con el formato XX+XXX o XXX+XXX."
                                return false
                            }
                            // La progresiva es un campo propio de la ficha: nunca
                            // se agrega al código (ni, por tanto, al nombre del XLSX).
                            root._setProgresiva(normalized, false)
                        }
                    }
                }
                ListView {
                    id: progresivaSuggestionList
                    Layout.fillWidth: true
                    Layout.preferredHeight: root.dp(34)
                    Layout.topMargin: -root.dp(4)
                    visible: progresivaField.activeFocus || progresivaField.editPending
                    orientation: ListView.Horizontal
                    spacing: root.dp(6)
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds
                    model: visible ? Rules.progresivaSuggestions(progresivaField.text) : []
                    delegate: Button {
                        id: progresivaChip
                        required property string modelData
                        readonly property bool isCurrent: modelData === progresivaField.text
                        height: root.dp(32)
                        leftPadding: root.dp(12)
                        rightPadding: root.dp(12)
                        text: modelData
                        font.pixelSize: root.fsLabel
                        font.weight: Font.DemiBold
                        focusPolicy: Qt.NoFocus
                        scale: down ? 0.985 : 1
                        Behavior on scale { NumberAnimation { duration: 130; easing.type: Easing.OutCubic } }
                        background: CalicataLiquidGlass {
                            dark: root.darkMode
                            accent: root.cGenOrange
                            radius: height / 2
                            tone: progresivaChip.isCurrent ? "tinted" : "glass"
                            selected: progresivaChip.isCurrent
                            pressed: progresivaChip.down
                        }
                        contentItem: Text {
                            text: progresivaChip.text
                            font: progresivaChip.font
                            color: progresivaChip.isCurrent ? root.cGenOrange : root.cText
                            verticalAlignment: Text.AlignVCenter
                        }
                        onClicked: {
                            progresivaField.text = modelData
                            progresivaField.editPending = true
                            progresivaField.commitPending()
                        }
                    }
                }

                GenHeaderField {
                    label: "Ubicación / Tramo"
                    iconName: "calgen.description"
                    accent: root.cGenOrange
                    accentSoft: root.cGenOrangeSoft
                    inputPlaceholder: "Ubicación o tramo"
                    boundText: txtUbicacion.text
                    commitHandler: function(t) { txtUbicacion.text = t }
                }
            }

            MobileStageBody {
                id: mobilePhotosSection
                glassPanel: false   // compone sus propias superficies primarias
                sectionNumber: 7
                sectionTitle: "Fotografías"
                sectionSubtitle: "Cámara y archivos por categoría"


                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: root.dp(38)
                    visible: root.photoFeedbackText.length > 0
                    radius: root.dp(10)
                    color: "transparent"
                    CalicataLiquidGlass { dark: root.darkMode; accent: root.cGenBlue; danger: root.flow ? root.flow.theme.error : "#D9483B"; anchors.fill: parent; radius: parent.radius }

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: root.dp(10)
                        anchors.rightMargin: root.dp(10)
                        spacing: root.dp(8)
                        FlowCore.FlowBusyIndicator {
                            Layout.preferredWidth: root.dp(18)
                            Layout.preferredHeight: root.dp(18)
                            flow: root.flow
                            running: root._photoRequestPending
                                     && (!root.flow || root.flow.motionAllowed)
                            accent: root.cAccent
                            track: root.cBorder
                            stroke: 2
                        }
                        Components.FlowIcon {
                            visible: !root._photoRequestPending
                                     || (root.flow && !root.flow.motionAllowed)
                            Layout.preferredWidth: root.dp(18)
                            Layout.preferredHeight: root.dp(18)
                            sourceOverride: root.icPhotos
                            flow: root.flow
                            active: root.photoFeedbackText.indexOf("incorporada") >= 0
                            tintEnabled: false
                        }
                        Text {
                            Layout.fillWidth: true
                            text: root.photoFeedbackText
                            color: root.cMuted
                            font.pixelSize: root.fsLabel
                            elide: Text.ElideRight
                        }
                    }
                }

                Repeater {
                    model: root.photoSlotTitles
                    delegate: Rectangle {
                        id: photoCard
                        required property int index
                        required property string modelData
                        readonly property int slot: index + 1
                        readonly property var info: root.photoSlotInfo(slot)
                        readonly property bool selected: root.activePhotoCategory === slot
                        Layout.fillWidth: true
                        implicitHeight: photoCardColumn.implicitHeight + root.dp(28)
                        radius: root.dp(22)
                        // Tarjeta = Liquid Glass (ambiente propio + superficie del sistema).
                        color: "transparent"
                        Behavior on implicitHeight { enabled: !root._stageSettling; NumberAnimation { duration: root.flow ? root.flow.duration(180) : 180; easing.type: Easing.OutCubic } }
                        scale: photoCardTap.pressed ? 0.99 : 1
                        Behavior on scale { NumberAnimation { duration: root.flow ? root.flow.instantDuration : 70 } }
                        // Seleccionar la categoría NUNCA abre cámara, galería ni visor.
                        TapHandler { id: photoCardTap; onTapped: root.activePhotoCategory = photoCard.slot }
                        Component.onCompleted: root._photoCardItems[photoCard.slot] = photoCard
                        Component.onDestruction: if (root._photoCardItems[photoCard.slot] === photoCard) delete root._photoCardItems[photoCard.slot]
                        PhotoGlassAmbient {
                            id: photoCardAmbient
                            anchors.fill: parent
                            radius: photoCard.radius
                        }
                        PhotoGlassBar {
                            anchors.fill: parent
                            backdrop: photoCardAmbient
                            barRadius: photoCard.radius
                            absorbTaps: false
                            frozen: false  // conserva el ambiente al cambiar foto o regresar de cámara/galería
                            surfaceName: "calicata-photo-card"
                            frost: 8
                            lens: 0.08
                            veilColor: root.darkMode ? Qt.rgba(0.08, 0.10, 0.14, 0.40) : Qt.rgba(1, 1, 1, 0.40)
                            rimColor: root.darkMode ? Qt.rgba(1, 1, 1, 0.08) : Qt.rgba(1, 1, 1, 0.85)
                        }
                        // Categoría activa: contorno azul sobre el vidrio (transición suave).
                        Rectangle {
                            anchors.fill: parent
                            radius: photoCard.radius
                            color: "transparent"
                            border.width: photoCard.selected ? root.dp(2) : 0
                            border.color: root.cGenBlue
                            opacity: photoCard.selected ? 1 : 0
                            Behavior on opacity { NumberAnimation { duration: root.flow ? root.flow.duration(160) : 160 } }
                        }
                        ColumnLayout {
                            id: photoCardColumn
                            anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top
                            anchors.margins: root.dp(14)
                            spacing: root.dp(12)
                            RowLayout {
                                Layout.fillWidth: true
                                spacing: root.dp(10)
                                Rectangle {
                                    Layout.preferredWidth: root.dp(36); Layout.preferredHeight: root.dp(36)
                                    radius: root.dp(12)
                                    color: root.darkMode ? Qt.rgba(1, 1, 1, 0.08) : Qt.rgba(1, 1, 1, 0.55)
                                    border.width: 1
                                    border.color: root.darkMode ? Qt.rgba(1, 1, 1, 0.12) : Qt.rgba(1, 1, 1, 0.9)
                                    Components.FlowIcon {
                                        anchors.centerIn: parent
                                        width: root.dp(19); height: width
                                        name: root.photoCategoryIcons[photoCard.index]
                                        flow: root.flow
                                        tintColor: root.cText; activeTintColor: root.cGenBlue; inactiveOpacity: 1
                                    }
                                }
                                Text { Layout.fillWidth: true; text: photoCard.modelData; color: root.cText; font.bold: true; font.pixelSize: root.fsField; elide: Text.ElideRight }
                                Rectangle {
                                    Layout.preferredWidth: photoCountText.implicitWidth + root.dp(20); Layout.preferredHeight: root.dp(26)
                                    radius: height / 2
                                    color: root.darkMode ? Qt.rgba(1, 1, 1, 0.08) : Qt.rgba(1, 1, 1, 0.55)
                                    border.width: 1
                                    border.color: root.darkMode ? Qt.rgba(1, 1, 1, 0.10) : Qt.rgba(1, 1, 1, 0.85)
                                    Text { id: photoCountText; anchors.centerIn: parent; text: photoCard.info.has ? "1 foto" : "0 fotos"; color: root.cMuted; font.pixelSize: root.sp(11) }
                                }
                                Rectangle {
                                    Layout.preferredWidth: root.dp(34); Layout.preferredHeight: root.dp(34)
                                    radius: width / 2
                                    color: photoMenuTap.pressed ? Qt.rgba(root.cGenBlue.r, root.cGenBlue.g, root.cGenBlue.b, 0.12) : "transparent"
                                    Behavior on color { ColorAnimation { duration: 120 } }
                                    scale: photoMenuTap.pressed ? 0.94 : 1
                                    Behavior on scale { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
                                    Components.FlowIcon {
                                        anchors.centerIn: parent
                                        width: root.dp(20); height: width
                                        name: "action.more"; flow: root.flow
                                        tintColor: root.cText; activeTintColor: root.cGenBlue; inactiveOpacity: 1
                                    }
                                    TapHandler { id: photoMenuTap; onTapped: root.openPhotoActions(photoCard.slot) }
                                    Accessible.role: Accessible.Button
                                    Accessible.name: "Acciones de " + photoCard.modelData
                                }
                            }
                            // Foto (protagonista) o panel vacío de vidrio; la barra de acciones
                            // Liquid Glass flota sobre su borde inferior y refracta lo de detrás.
                            Item {
                                id: photoHero
                                Layout.fillWidth: true
                                Layout.preferredHeight: photoCard.info.has
                                                        ? Math.round(Math.min(width * 0.62, root.dp(260)))
                                                        : photoEmptyContent.implicitHeight + photoActionBar.height + root.dp(46)
                                Behavior on Layout.preferredHeight { enabled: !root._stageSettling; NumberAnimation { duration: root.flow ? root.flow.duration(200) : 200; easing.type: Easing.OutCubic } }
                                // Con foto: la imagen es el backdrop del vidrio (nunca la barra).
                                Item {
                                    id: photoHeroBackdrop
                                    anchors.fill: parent
                                    visible: photoCard.info.has
                                    Image {
                                        id: photoHeroImage
                                        anchors.fill: parent
                                        source: photoCard.info.has ? root._photoSource(photoCard.slot) : ""
                                        sourceSize: Qt.size(720, 720)
                                        fillMode: Image.PreserveAspectCrop
                                        asynchronous: true
                                        autoTransform: true
                                        onStatusChanged: if (status === Image.Ready)
                                                             root._photoPreviewReady(photoCard.slot, source)
                                        opacity: status === Image.Ready ? 1 : 0
                                        Behavior on opacity { NumberAnimation { duration: root.flow ? root.flow.duration(220) : 220 } }
                                        // Esquinas redondeadas reales (máscara estática: se recalcula solo
                                        // cuando cambia la foto, no por fotograma).
                                        layer.enabled: true
                                        layer.effect: MultiEffect {
                                            maskEnabled: true
                                            maskSource: photoHeroMask
                                            maskThresholdMin: 0.5
                                            maskSpreadAtMin: 1.0
                                        }
                                    }
                                    Rectangle {
                                        id: photoHeroMask
                                        anchors.fill: parent
                                        radius: root.dp(16)
                                        visible: false
                                        layer.enabled: true
                                    }
                                    TapHandler { enabled: photoCard.info.has; onTapped: root.runPhotoAction("view", photoCard.slot) }
                                }
                                // Sin foto: panel interior de vidrio (no un bloque gris).
                                PhotoGlassBar {
                                    id: photoEmptyPanel
                                    anchors.fill: parent
                                    visible: !photoCard.info.has
                                    backdrop: photoCardAmbient
                                    barRadius: root.dp(20)
                                    absorbTaps: false
                                    frozen: false
                                    lowCost: true
                                    surfaceName: "calicata-photo-empty"
                                    frost: 8
                                    lens: 0.08
                                    veilColor: root.darkMode ? Qt.rgba(0.10, 0.12, 0.16, 0.30) : Qt.rgba(1, 1, 1, 0.34)
                                    rimColor: root.darkMode ? Qt.rgba(1, 1, 1, 0.10) : Qt.rgba(1, 1, 1, 0.92)
                                    opacity: visible ? 1 : 0
                                    Behavior on opacity { NumberAnimation { duration: root.flow ? root.flow.duration(200) : 200 } }
                                    Column {
                                        id: photoEmptyContent
                                        anchors.horizontalCenter: parent.horizontalCenter
                                        y: root.dp(18)
                                        width: parent.width - root.dp(32)
                                        spacing: root.dp(6)
                                        PhotoGlassBadge {
                                            anchors.horizontalCenter: parent.horizontalCenter
                                            width: root.dp(58); height: width
                                            iconName: "documents.image"
                                            iconSize: root.dp(28)
                                        }
                                        Item { width: 1; height: root.dp(2) }
                                        Text {
                                            width: parent.width
                                            horizontalAlignment: Text.AlignHCenter
                                            text: "Sin fotografía"
                                            color: root.cText
                                            font.bold: true
                                            font.pixelSize: root.fsField
                                        }
                                        Text {
                                            width: parent.width
                                            horizontalAlignment: Text.AlignHCenter
                                            text: "Toma o adjunta una foto para esta categoría."
                                            color: root.cMuted
                                            font.pixelSize: root.fsLabel
                                            wrapMode: Text.WordWrap
                                        }
                                    }
                                }
                                // Acciones rápidas (mismas acciones que la hoja y el Dock).
                                PhotoGlassBar {
                                    id: photoActionBar
                                    anchors.left: parent.left; anchors.right: parent.right; anchors.bottom: parent.bottom
                                    anchors.margins: root.dp(photoHero.width < root.dp(330) ? 6 : 10)
                                    height: photoCard.info.has ? root.dp(66) : root.dp(60)
                                    barRadius: height / 2
                                    backdrop: photoCard.info.has ? photoHeroBackdrop : photoCardAmbient
                                    // Ambiente vivo también sin foto: no conservar una textura vacía al volver
                                    // de cámara/galería. Sin foto se mantiene el material de bajo coste.
                                    frozen: false
                                    lowCost: !photoCard.info.has
                                    RowLayout {
                                        anchors.fill: parent
                                        anchors.leftMargin: root.dp(6); anchors.rightMargin: root.dp(6)
                                        anchors.topMargin: root.dp(3); anchors.bottomMargin: root.dp(3)
                                        spacing: 0
                                        Repeater {
                                            model: photoCard.info.has
                                                   ? [["view", "Ver", "action.search"], ["edit", "Editar", "action.edit"],
                                                      ["capture", "Tomar foto", "action.camera"], ["pick", "Importar", "documents.upload"]]
                                                   : [["capture", "Tomar foto", "action.camera"], ["pick", "Importar", "documents.upload"]]
                                            delegate: PhotoActionTile {
                                                required property var modelData
                                                required property int index
                                                label: modelData[1]
                                                iconName: modelData[2]
                                                wide: !photoCard.info.has
                                                divider: index > 0
                                                enabled: !root._photoRequestPending && (modelData[0] !== "edit" || photoCard.info.hasOriginal)
                                                onClicked: root.runPhotoAction(modelData[0], photoCard.slot)
                                            }
                                        }
                                    }
                                }
                            }
                            // Estado real de la foto.
                            ColumnLayout {
                                Layout.fillWidth: true
                                visible: photoCard.info.has
                                spacing: root.dp(4)
                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: root.dp(8)
                                    Rectangle {
                                        visible: photoCard.info.label.length > 0
                                        Layout.preferredWidth: photoStateRow.implicitWidth + root.dp(18); Layout.preferredHeight: root.dp(24)
                                        radius: height / 2
                                        color: root.photoToneColor(photoCard.info.tone, true)
                                        Behavior on color { ColorAnimation { duration: root.flow ? root.flow.duration(220) : 220 } }
                                        Row {
                                            id: photoStateRow
                                            anchors.centerIn: parent
                                            spacing: root.dp(4)
                                            Components.FlowIcon {
                                                visible: photoCard.info.state === "SYNCED"
                                                anchors.verticalCenter: parent.verticalCenter
                                                width: root.dp(12); height: width
                                                name: "action.check"; flow: root.flow
                                                tintColor: root.photoToneColor(photoCard.info.tone, false)
                                                activeTintColor: root.photoToneColor(photoCard.info.tone, false)
                                                inactiveOpacity: 1
                                            }
                                            Text {
                                                anchors.verticalCenter: parent.verticalCenter
                                                text: photoCard.info.label
                                                color: root.photoToneColor(photoCard.info.tone, false)
                                                font.bold: true
                                                font.pixelSize: root.sp(11)
                                            }
                                        }
                                    }
                                    Text { visible: photoCard.info.date.length > 0; text: photoCard.info.date; color: root.cText; font.pixelSize: root.fsLabel }
                                    Item { Layout.fillWidth: true }
                                    Text {
                                        visible: photoCard.info.versionCount > 1
                                        text: photoCard.info.versionCount + " versiones"
                                        color: root.cMuted; font.pixelSize: root.sp(11)
                                    }
                                }
                                Text {
                                    Layout.fillWidth: true
                                    visible: photoCard.info.versionCount > 1
                                    text: "Original conservada"
                                    color: root.cMuted; font.pixelSize: root.sp(11)
                                }
                                Text {
                                    Layout.fillWidth: true
                                    visible: photoCard.info.error.length > 0 && !photoCard.info.conflict
                                    text: photoCard.info.error
                                    color: root.cMuted; font.pixelSize: root.sp(11)
                                    wrapMode: Text.WordWrap; maximumLineCount: 2; elide: Text.ElideRight
                                }
                            }
                            // Decisión pendiente: otra versión en la nube / envío fallido.
                            Rectangle {
                                Layout.fillWidth: true
                                visible: photoCard.info.conflict || photoCard.info.failed
                                implicitHeight: photoDecision.implicitHeight + root.dp(20)
                                radius: root.dp(12)
                                color: root.photoToneColor(photoCard.info.conflict ? "orange" : "red", true)
                                ColumnLayout {
                                    id: photoDecision
                                    anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top
                                    anchors.margins: root.dp(10)
                                    spacing: root.dp(8)
                                    Text {
                                        Layout.fillWidth: true
                                        wrapMode: Text.WordWrap
                                        color: root.cText
                                        font.pixelSize: root.fsLabel
                                        text: photoCard.info.conflict
                                              ? "Otro dispositivo publicó una versión de esta categoría. Tu foto se conserva: elige cuál queda en uso."
                                              : "No se pudo publicar. La foto está guardada en el dispositivo."
                                    }
                                    RowLayout {
                                        Layout.fillWidth: true
                                        spacing: root.dp(8)
                                        PhotoPill {
                                            primary: true
                                            text: photoCard.info.conflict ? "Conservar la mía" : "Reintentar"
                                            onClicked: root.runPhotoAction(photoCard.info.conflict ? "keepMine" : "retry", photoCard.slot)
                                        }
                                        PhotoPill {
                                            text: photoCard.info.conflict ? "Mantener la remota" : "Descartar envío"
                                            onClicked: root.runPhotoAction(photoCard.info.conflict ? "keepRemote" : "discardSend", photoCard.slot)
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }

            MobileStageBody {
                id: mobileStrataSection
                glassPanel: false   // compone sus propias superficies primarias
                sectionNumber: 4
                sectionTitle: "Perfil estratigráfico"
                sectionSubtitle: root.totalDepthM.toFixed(2) + " m · "
                                 + root.visibleStrataCount
                                 + (cortesModel.count === 1 ? " estrato" : " estratos")

                // Perfil: configuración (izq.) · estratigrafía + editor (centro) ·
                // vista y resumen (der.). 3 columnas en tablet horizontal, 2 en
                // tablet vertical y una sola columna en teléfono.
                GridLayout {
                    id: prfLayout
                    Layout.fillWidth: true
                    readonly property int mode: width >= root.dp(1180) ? 3 : width >= root.dp(760) ? 2 : 1
                    readonly property real sideWidth: mode === 3 ? root.dp(300) : root.dp(290)
                    columns: mode === 3 ? 3 : mode === 2 ? 2 : 1
                    columnSpacing: root.dp(16)
                    rowSpacing: root.dp(16)

                    // ---------------- Columna izquierda: configuración ----------------
                    ColumnLayout {
                        id: prfLeftCol
                        Layout.row: 0
                        Layout.column: 0
                        Layout.preferredWidth: prfLayout.mode === 1 ? -1 : prfLayout.sideWidth
                        Layout.maximumWidth: prfLayout.mode === 1 ? Number.POSITIVE_INFINITY : prfLayout.sideWidth
                        Layout.fillWidth: prfLayout.mode === 1
                        Layout.alignment: Qt.AlignTop
                        spacing: root.dp(16)

                        PrfCard {
                            title: "Configuración del perfil"
                            iconName: "calgen.depth"

                            GenHeaderField {
                                label: "Profundidad total (m)"
                                iconName: "calgen.depth"
                                numeric: true
                                boundText: root.requestedDepthM > 0 ? root.requestedDepthM.toFixed(2) : ""
                                hint: root.totalDepthM > 0 ? root.totalDepthM.toFixed(2) : "0.00"
                                inputPlaceholder: "Profundidad total"
                                caption: "Registrada por estratos: " + root.totalDepthM.toFixed(2)
                                         + " m · sin límite de profundidad"
                                commitHandler: function(t) { return root.commitProfileDepth(t) }
                            }
                            GenHeaderField {
                                label: "Nivel freático (m)"
                                iconName: "calgen.water"
                                accent: root.cGenTeal
                                accentSoft: root.cGenTealSoft
                                numeric: true
                                boundText: root.effectiveGroundwaterText
                                hint: "Sin registrar"
                                inputPlaceholder: "Nivel freático"
                                caption: root.groundwaterCustom ? "Valor personalizado"
                                         : root.derivedGroundwaterText.length
                                           ? "Derivado del primer estrato con humedad Agua"
                                           : "Ningún estrato registra Agua"
                                commitHandler: function(t) { return root.commitProfileGroundwater(t) }
                            }
                            PrfSwitch {
                                label: "Mostrar nivel freático"
                                isOn: root.profileSetup.show_water_table !== false
                                onFlipped: root.updateProfileSetup({ show_water_table: !isOn })
                            }
                        }

                        PrfCard {
                            title: "Tipo de excavación"
                            iconName: "geotechnical.calicata"

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: root.dp(10)
                                PrfSegment {
                                    label: "Cielo abierto"
                                    iconName: "geotechnical.calicata"
                                    isOn: root.profileSetupText("excavation_type") === "Cielo abierto"
                                    onPicked: root.updateProfileSetup({ excavation_type: "Cielo abierto" })
                                }
                                PrfSegment {
                                    label: "Otro"
                                    iconName: "action.more"
                                    isOn: root.profileSetupText("excavation_type") === "Otro"
                                    onPicked: root.updateProfileSetup({ excavation_type: "Otro" })
                                }
                            }
                            BoundTextField {
                                Layout.fillWidth: true
                                visible: root.profileSetupText("excavation_type") === "Otro"
                                placeholderText: "Describe la excavación"
                                modelText: root.profileSetupText("excavation_other")
                                onCommit: function(t) { root.updateProfileSetup({ excavation_other: t }) }
                            }
                        }

                        PrfCard {
                            title: "Método de descripción"
                            iconName: "calgen.description"

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: root.dp(10)
                                PrfSegment {
                                    label: "SUCS"
                                    iconName: root.iconStrataName
                                    isOn: root.profileSetupText("description_method") === "SUCS"
                                    onPicked: root.updateProfileSetup({ description_method: "SUCS" })
                                }
                                PrfSegment {
                                    label: "AASHTO"
                                    iconName: "map.layers"
                                    isOn: root.profileSetupText("description_method") === "AASHTO"
                                    onPicked: root.updateProfileSetup({ description_method: "AASHTO" })
                                }
                            }
                            Text {
                                Layout.fillWidth: true
                                text: root.profileSetupText("description_method") === "AASHTO"
                                      ? "La tabla de estratos muestra la clasificación AASHTO."
                                      : root.profileSetupText("description_method") === "SUCS"
                                        ? "La tabla de estratos muestra la clasificación SUCS."
                                        : "No registrado. La tabla muestra SUCS mientras no se elija."
                                color: root.cMuted
                                font.pixelSize: root.sp(11)
                                wrapMode: Text.WordWrap
                            }
                        }

                        PrfCard {
                            title: "Plantillas globales"
                            iconName: "documents.file"
                            headerTrailing: [
                                GenRoundIconButton {
                                    width: root.dp(36)
                                    height: root.dp(36)
                                    iconName: "calgen.chevron"
                                    Accessible.name: "Ver plantillas globales"
                                    onClicked: prfTemplatePopup.openPicker()
                                }
                            ]

                            Flow {
                                Layout.fillWidth: true
                                spacing: root.dp(8)
                                Repeater {
                                    model: root.prfTemplates
                                    delegate: PrfChip {
                                        required property var modelData
                                        label: modelData.title
                                        isOn: root.profileSetupText("template") === modelData.key
                                        onFlipped: root.applyProfileTemplate(isOn ? "vacia" : modelData.key, false)
                                    }
                                }
                            }
                            Text {
                                Layout.fillWidth: true
                                text: {
                                    var template = root.prfTemplate(root.profileSetupText("template"))
                                    return template ? template.detail
                                                    : "Carretera, edificación, cantera, ambiental / exploración o plantilla vacía."
                                }
                                color: root.cMuted
                                font.pixelSize: root.sp(11)
                                wrapMode: Text.WordWrap
                            }
                        }

                        PrfCard {
                            title: "Observaciones generales"
                            iconName: "calgen.description"
                            PrfTextArea {
                                label: "Observaciones generales"
                                modelText: root.observacionesText
                                maxLength: 500
                                placeholder: "Observaciones generales del perfil…"
                                onCommit: function(t) {
                                    root.observacionesText = t
                                    root._markDirtySoon()
                                }
                            }
                        }
                    }

                    // ---------------- Centro: estratigrafía + editor ----------------
                    ColumnLayout {
                        id: prfCenterCol
                        Layout.row: prfLayout.mode === 1 ? 1 : 0
                        Layout.column: prfLayout.mode === 1 ? 0 : 1
                        Layout.rowSpan: prfLayout.mode === 2 ? 2 : 1
                        Layout.fillWidth: true
                        Layout.alignment: Qt.AlignTop
                        spacing: root.dp(16)
                        readonly property bool tableMode: width >= root.dp(700)
                        readonly property bool hasSelection: root.selectedStratum >= 0
                                                             && root.selectedStratum < cortesModel.count

                        PrfCard {
                            title: "Estratigrafía"
                            iconName: root.iconStrataName

                            Flow {
                                Layout.fillWidth: true
                                visible: cortesModel.count > 0
                                spacing: root.dp(8)
                                PrfToolButton {
                                    text: "Añadir estrato"
                                    iconName: "action.addStratum"
                                    primaryTone: true
                                    onClicked: root.addStratumFromProfile()
                                }
                                PrfToolButton {
                                    text: "Insertar"
                                    iconName: "action.add"
                                    enabled: prfCenterCol.hasSelection
                                    onClicked: root.insertStratumBelow(root.selectedStratum)
                                }
                                PrfToolButton {
                                    text: "Eliminar"
                                    iconName: "action.delete"
                                    enabled: prfCenterCol.hasSelection
                                    onClicked: root.requestDeleteStratum(root.selectedStratum)
                                }
                                PrfToolButton {
                                    text: "Duplicar"
                                    iconName: "action.copy"
                                    enabled: prfCenterCol.hasSelection
                                    onClicked: root.duplicateStratum(root.selectedStratum)
                                }
                                PrfToolButton {
                                    text: "Reordenar"
                                    iconName: "action.menu"
                                    enabled: cortesModel.count > 1
                                    checked: root.prfReorderMode
                                    onClicked: root.prfReorderMode = !root.prfReorderMode
                                }
                            }

                            // Estado vacío: una acción principal y acceso a plantillas.
                            ColumnLayout {
                                Layout.fillWidth: true
                                visible: cortesModel.count === 0
                                spacing: root.dp(12)
                                Item { Layout.preferredHeight: root.dp(8) }
                                GenIconBadge {
                                    Layout.alignment: Qt.AlignHCenter
                                    Layout.preferredWidth: root.dp(64)
                                    Layout.preferredHeight: root.dp(64)
                                    radius: root.dp(18)
                                    iconName: root.iconStrataName
                                }
                                Text {
                                    Layout.fillWidth: true
                                    text: "Aún no hay estratos"
                                    color: root.cText
                                    font.pixelSize: root.sp(19)
                                    font.weight: Font.DemiBold
                                    horizontalAlignment: Text.AlignHCenter
                                    wrapMode: Text.WordWrap
                                }
                                Text {
                                    Layout.fillWidth: true
                                    Layout.maximumWidth: root.dp(460)
                                    Layout.alignment: Qt.AlignHCenter
                                    text: "Registra el primer estrato desde la superficie (0.00 m). Una plantilla global "
                                          + "preconfigura el método de descripción y el contexto del relleno."
                                    color: root.cMuted
                                    font.pixelSize: root.fsLabel
                                    horizontalAlignment: Text.AlignHCenter
                                    wrapMode: Text.WordWrap
                                }
                                GridLayout {
                                    Layout.alignment: Qt.AlignHCenter
                                    Layout.preferredWidth: Math.min(parent.width, root.dp(480))
                                    columns: prfCenterCol.width >= root.dp(460) ? 2 : 1
                                    columnSpacing: root.dp(10)
                                    rowSpacing: root.dp(10)
                                    GenDialogButton {
                                        text: "Crear primer estrato"
                                        iconName: "action.addStratum"
                                        primary: true
                                        onClicked: root.addStratumFromProfile()
                                    }
                                    GenDialogButton {
                                        text: "Usar plantilla global"
                                        iconName: "documents.file"
                                        soft: true
                                        onClicked: prfTemplatePopup.openPicker()
                                    }
                                }
                                Item { Layout.preferredHeight: root.dp(8) }
                            }

                            // Encabezado de la tabla (solo en ancho de tablet).
                            RowLayout {
                                Layout.fillWidth: true
                                visible: prfCenterCol.tableMode && cortesModel.count > 0
                                spacing: root.dp(8)
                                Repeater {
                                    model: [
                                        { t: "", w: 22 }, { t: "#", w: 32 }, { t: "De (m)", w: 58 }, { t: "A (m)", w: 58 },
                                        { t: "Espesor", w: 64 }, { t: "Símbolo", w: 58 }, { t: "Origen / tipo", w: 0, s: 2 },
                                        { t: root.profileSetupText("description_method") === "AASHTO" ? "AASHTO" : "SUCS", w: 92 },
                                        { t: "Descripción", w: 0, s: 3 }, { t: "", w: root.prfReorderMode ? 96 : 40 }]
                                    delegate: Text {
                                        required property var modelData
                                        Layout.preferredWidth: modelData.w > 0 ? root.dp(modelData.w) : 1
                                        Layout.fillWidth: modelData.w === 0
                                        Layout.horizontalStretchFactor: modelData.w === 0 ? (modelData.s || 1) : -1
                                        text: modelData.t
                                        color: root.cMuted
                                        font.pixelSize: root.sp(12)
                                        font.weight: Font.DemiBold
                                        elide: Text.ElideRight
                                    }
                                }
                            }
                            Rectangle {
                                Layout.fillWidth: true
                                Layout.preferredHeight: 1
                                visible: prfCenterCol.tableMode && cortesModel.count > 0
                                color: root.cBorder
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                visible: cortesModel.count > 0
                                spacing: root.dp(4)
                                Repeater {
                                    model: cortesModel
                                    delegate: Rectangle {
                                        id: prfRow
                                        readonly property int rowIdx: index
                                        readonly property var plain: {
                                            var evidence = _extraJson + material_origin + sucs + aashto + descripcion + de + a
                                            return root.corteToPlainObject(cortesModel.get(index))
                                        }
                                        readonly property bool isSel: rowIdx === root.selectedStratum
                                        readonly property real fromDepth: Rules.parseDecimalSafe(de)
                                        readonly property real toDepth: Rules.parseDecimalSafe(a)
                                        readonly property bool validInterval: isFinite(fromDepth) && isFinite(toDepth) && toDepth > fromDepth
                                        readonly property color tone: root.stratumColorFor(plain)
                                        readonly property var files: root.stratumPatternFilesFor(plain)
                                        readonly property string originText: root.prfOriginLabel(material_origin)
                                        readonly property string typeText: root.stratumTypeText(plain)
                                        readonly property string classText: root.stratumClassText(plain)
                                        readonly property string descText: String(descripcion || "")
                                        function depthText(value) { return isFinite(value) ? value.toFixed(2) : "—" }
                                        Layout.fillWidth: true
                                        // Loader publica el alto implícito de la variante cargada.
                                        readonly property real contentImplicitHeight: prfRowLoader.implicitHeight
                                        implicitHeight: prfCenterCol.tableMode
                                                        ? Math.max(root.dp(64), contentImplicitHeight + root.dp(16))
                                                        : Math.max(root.dp(76), contentImplicitHeight + root.dp(20))
                                        radius: root.dp(10)
                                        color: "transparent"
                                        CalicataLiquidGlass {
                                            dark: root.darkMode; accent: root.cGenBlue; danger: root.flow ? root.flow.theme.error : "#D9483B"
                                            anchors.fill: parent
                                            radius: parent.radius
                                            tone: isSel ? "tinted" : "clear"
                                            selected: isSel
                                            pressed: prfRowTap.pressed
                                        }
                                        Accessible.role: Accessible.Button
                                        Accessible.name: "Estrato " + (rowIdx + 1) + ", " + depthText(fromDepth) + " a "
                                                         + depthText(toDepth) + " m, " + (classText || "sin clasificar")

                                        MouseArea {
                                            id: prfRowTap
                                            anchors.fill: parent
                                            onClicked: root.selectStratum(prfRow.rowIdx, "field")
                                        }

                                        // Solo se instancia la variante visible (tabla o tarjeta):
                                        // una sola trama/imagen por fila.
                                        Loader {
                                            id: prfRowLoader
                                            anchors.fill: parent
                                            anchors.topMargin: root.dp(prfCenterCol.tableMode ? 8 : 10)
                                            anchors.bottomMargin: root.dp(prfCenterCol.tableMode ? 8 : 10)
                                            anchors.leftMargin: root.dp(prfCenterCol.tableMode ? 4 : 8)
                                            anchors.rightMargin: root.dp(4)
                                            sourceComponent: prfCenterCol.tableMode ? prfRowTableComponent : prfRowCompactComponent
                                        }

                                        // Fila de tabla (tablet).
                                        Component {
                                        id: prfRowTableComponent
                                        RowLayout {
                                            spacing: root.dp(8)
                                            Text {
                                                Layout.preferredWidth: root.dp(22)
                                                text: "⋮"
                                                color: root.cMuted
                                                font.pixelSize: root.sp(18)
                                                horizontalAlignment: Text.AlignHCenter
                                            }
                                            PrfStratumBadge {
                                                number: prfRow.rowIdx + 1
                                                tone: prfRow.tone
                                                Layout.preferredWidth: root.dp(32)
                                                Layout.preferredHeight: root.dp(44)
                                                Layout.fillHeight: true
                                            }
                                            Text { Layout.preferredWidth: root.dp(58); text: prfRow.depthText(prfRow.fromDepth); color: root.cText; font.pixelSize: root.fsLabel }
                                            Text { Layout.preferredWidth: root.dp(58); text: prfRow.depthText(prfRow.toDepth); color: root.cText; font.pixelSize: root.fsLabel }
                                            Text {
                                                Layout.preferredWidth: root.dp(64)
                                                text: prfRow.validInterval ? (prfRow.toDepth - prfRow.fromDepth).toFixed(2) : "—"
                                                color: root.cText
                                                font.pixelSize: root.fsLabel
                                            }
                                            PrfStratumSymbol {
                                                tone: prfRow.tone
                                                files: prfRow.files
                                                Layout.preferredWidth: root.dp(50)
                                                Layout.preferredHeight: root.dp(44)
                                            }
                                            ColumnLayout {
                                                Layout.fillWidth: true
                                                Layout.preferredWidth: 1
                                                Layout.horizontalStretchFactor: 2
                                                spacing: root.dp(2)
                                                Text {
                                                    Layout.fillWidth: true
                                                    text: prfRow.originText.length ? prfRow.originText : "Sin origen"
                                                    color: prfRow.originText.length ? root.cText : root.cMuted
                                                    font.pixelSize: root.fsLabel
                                                    font.weight: Font.DemiBold
                                                    elide: Text.ElideRight
                                                }
                                                Text {
                                                    Layout.fillWidth: true
                                                    visible: prfRow.typeText.length > 0
                                                    text: prfRow.typeText
                                                    color: root.cMuted
                                                    font.pixelSize: root.sp(12)
                                                    wrapMode: Text.WordWrap
                                                    maximumLineCount: 2
                                                    elide: Text.ElideRight
                                                }
                                            }
                                            Text {
                                                Layout.preferredWidth: root.dp(92)
                                                text: prfRow.classText.length ? prfRow.classText : "Sin clasificar"
                                                color: prfRow.classText.length ? root.cText : root.cMuted
                                                font.pixelSize: root.fsLabel
                                                font.weight: Font.DemiBold
                                                horizontalAlignment: Text.AlignHCenter
                                            }
                                            Text {
                                                Layout.fillWidth: true
                                                Layout.preferredWidth: 1
                                                Layout.horizontalStretchFactor: 3
                                                text: !prfRow.validInterval ? "Completa o corrige el intervalo"
                                                      : prfRow.descText.length ? prfRow.descText : "Sin descripción"
                                                color: !prfRow.validInterval ? (root.flow ? root.flow.theme.error : "#B4232E")
                                                       : prfRow.descText.length ? root.cText : root.cMuted
                                                font.pixelSize: root.sp(12)
                                                wrapMode: Text.WordWrap
                                                maximumLineCount: 3
                                                elide: Text.ElideRight
                                            }
                                            PrfRowActions {
                                                rowIdx: prfRow.rowIdx
                                                Layout.preferredWidth: root.prfReorderMode ? root.dp(96) : root.dp(40)
                                            }
                                        }
                                        }

                                        // Tarjeta compacta (teléfono): misma información, en bloque.
                                        Component {
                                        id: prfRowCompactComponent
                                        RowLayout {
                                            spacing: root.dp(10)
                                            PrfStratumBadge {
                                                number: prfRow.rowIdx + 1
                                                tone: prfRow.tone
                                                Layout.preferredWidth: root.dp(28)
                                                Layout.preferredHeight: root.dp(52)
                                            }
                                            PrfStratumSymbol {
                                                tone: prfRow.tone
                                                files: prfRow.files
                                                Layout.preferredWidth: root.dp(48)
                                                Layout.preferredHeight: root.dp(52)
                                            }
                                            ColumnLayout {
                                                Layout.fillWidth: true
                                                spacing: root.dp(2)
                                                Text {
                                                    Layout.fillWidth: true
                                                    text: prfRow.depthText(prfRow.fromDepth) + " – " + prfRow.depthText(prfRow.toDepth) + " m"
                                                          + (prfRow.validInterval ? "  ·  e = " + (prfRow.toDepth - prfRow.fromDepth).toFixed(2) + " m" : "")
                                                    color: root.cMuted
                                                    font.pixelSize: root.sp(12)
                                                    elide: Text.ElideRight
                                                }
                                                Text {
                                                    Layout.fillWidth: true
                                                    text: (prfRow.originText.length ? prfRow.originText : "Sin origen")
                                                          + (prfRow.typeText.length ? " · " + prfRow.typeText : "")
                                                          + (prfRow.classText.length ? " · " + prfRow.classText : "")
                                                    color: root.cText
                                                    font.pixelSize: root.fsLabel
                                                    font.weight: Font.DemiBold
                                                    wrapMode: Text.WordWrap
                                                    maximumLineCount: 2
                                                    elide: Text.ElideRight
                                                }
                                                Text {
                                                    Layout.fillWidth: true
                                                    text: !prfRow.validInterval ? "Completa o corrige el intervalo"
                                                          : prfRow.descText.length ? prfRow.descText : "Sin descripción"
                                                    color: !prfRow.validInterval ? (root.flow ? root.flow.theme.error : "#B4232E") : root.cMuted
                                                    font.pixelSize: root.sp(12)
                                                    wrapMode: Text.WordWrap
                                                    maximumLineCount: 2
                                                    elide: Text.ElideRight
                                                }
                                            }
                                            PrfRowActions { rowIdx: prfRow.rowIdx }
                                        }
                                        }

                                        Rectangle {
                                            anchors.left: parent.left
                                            anchors.right: parent.right
                                            anchors.bottom: parent.bottom
                                            anchors.bottomMargin: -root.dp(2)
                                            height: 1
                                            color: root.cBorder
                                            opacity: 0.6
                                            visible: !prfRow.isSel && prfRow.rowIdx < cortesModel.count - 1
                                        }
                                    }
                                }
                            }
                        }

                        // ---------------- Editor detallado del estrato ----------------
                        PrfCard {
                            id: prfEditorCard
                            visible: cortesModel.count > 0
                            readonly property int idx: root.selectedStratum
                            readonly property var s: root.prfSel || ({})
                            readonly property bool hasStratum: !!root.prfSel
                            readonly property string origin: root.prfOriginLabel(s.material_origin)
                            readonly property bool anthropicLike: origin === "Antrópico" || origin === "Mixto / intervenido"
                            readonly property real innerWidth: width - root.dp(32)
                            readonly property int subColumns: innerWidth >= root.dp(860) ? 3 : innerWidth >= root.dp(560) ? 2 : 1
                            readonly property real subWidth: (innerWidth - (subColumns - 1) * root.dp(12)) / subColumns
                            readonly property bool sideLabels: subWidth >= root.dp(300)
                            readonly property var projection: Rules.labProjection(s)
                            readonly property real fromDepth: Rules.parseDecimalSafe(s.de)
                            readonly property real toDepth: Rules.parseDecimalSafe(s.a)
                            readonly property var features: s.features || ({})
                            readonly property var components: Array.isArray(s.fill_components) ? s.fill_components : []

                            Text {
                                Layout.fillWidth: true
                                visible: !prfEditorCard.hasStratum
                                text: "Selecciona un estrato de la tabla para editar su detalle."
                                color: root.cMuted
                                font.pixelSize: root.fsLabel
                                wrapMode: Text.WordWrap
                            }

                            // Cabecera: estrato activo + navegación entre estratos.
                            RowLayout {
                                Layout.fillWidth: true
                                visible: prfEditorCard.hasStratum
                                spacing: root.dp(10)
                                Rectangle {
                                    Layout.preferredWidth: root.dp(32)
                                    Layout.preferredHeight: root.dp(32)
                                    radius: root.dp(8)
                                    color: root.stratumColorFor(prfEditorCard.s)
                                    Text {
                                        anchors.centerIn: parent
                                        text: prfEditorCard.idx + 1
                                        color: root.prfInkOn(parent.color)
                                        font.pixelSize: root.sp(14)
                                        font.bold: true
                                    }
                                }
                                Text {
                                    Layout.fillWidth: true
                                    text: "Estrato " + (prfEditorCard.idx + 1)
                                          + (prfEditorCard.origin.length ? " – " + prfEditorCard.origin : "")
                                          + (root.stratumTypeText(prfEditorCard.s).length
                                             ? " (" + root.stratumTypeText(prfEditorCard.s) + ")" : "")
                                    color: root.cText
                                    font.pixelSize: root.sp(17)
                                    font.weight: Font.DemiBold
                                    wrapMode: Text.WordWrap
                                    maximumLineCount: 2
                                    elide: Text.ElideRight
                                }
                                PrfToolButton {
                                    visible: root.reviewCorrectionActive
                                    text: "Volver a revisión"
                                    iconName: "action.check"
                                    primaryTone: true
                                    onClicked: root.finishReviewCorrection()
                                }
                                GenRoundIconButton {
                                    iconName: "calgen.chevronLeft"
                                    enabled: prfEditorCard.idx > 0
                                    opacity: enabled ? 1 : 0.35
                                    Accessible.name: "Estrato anterior"
                                    onClicked: root.selectStratum(prfEditorCard.idx - 1, "field")
                                }
                                GenRoundIconButton {
                                    iconName: "calgen.chevron"
                                    enabled: prfEditorCard.idx < cortesModel.count - 1
                                    opacity: enabled ? 1 : 0.35
                                    Accessible.name: "Estrato siguiente"
                                    onClicked: root.selectStratum(prfEditorCard.idx + 1, "field")
                                }
                            }

                            // 1. Rango y geometría.
                            GridLayout {
                                Layout.fillWidth: true
                                visible: prfEditorCard.hasStratum
                                columns: prfEditorCard.innerWidth >= root.dp(760) ? 5 : prfEditorCard.innerWidth >= root.dp(460) ? 3 : 2
                                columnSpacing: root.dp(10)
                                rowSpacing: root.dp(10)
                                MobileReadOnlyField {
                                    Layout.fillWidth: true
                                    fieldLabel: "Desde (m)"
                                    fieldText: String(prfEditorCard.s.de || "")
                                }
                                PrfLabeledInput {
                                    label: "Hasta (m)"
                                    BoundTextField {
                                        Layout.fillWidth: true
                                        numericKind: Rules.DEPTH_METERS
                                        maximumValue: root.allowedDepthM
                                        placeholderText: "Hasta (m)"
                                        modelText: String(prfEditorCard.s.a || "")
                                        onCommit: function(t) { return root.commitBoundary(prfEditorCard.idx, t) }
                                    }
                                }
                                MobileReadOnlyField {
                                    Layout.fillWidth: true
                                    fieldLabel: "Espesor (m)"
                                    fieldText: isFinite(prfEditorCard.fromDepth) && isFinite(prfEditorCard.toDepth)
                                               && prfEditorCard.toDepth > prfEditorCard.fromDepth
                                               ? (prfEditorCard.toDepth - prfEditorCard.fromDepth).toFixed(2) : ""
                                }
                                // Patrón = proyección del laboratorio (solo lectura).
                                PrfPickField {
                                    label: "Símbolo / patrón (Laboratorio)"
                                    boxHeight: root.hField
                                    patterns: root.stratumPatternFilesFor(prfEditorCard.s)
                                    swatch: root.stratumColorFor(prfEditorCard.s)
                                    valueText: root.stratumPatternLabel(prfEditorCard.s)
                                    placeholder: "Pendiente de laboratorio"
                                    onActivated: root.openLabForStratum(prfEditorCard.idx)
                                }
                                PrfPickField {
                                    label: "Color"
                                    boxHeight: root.hField
                                    swatch: root.stratumColorFor(prfEditorCard.s)
                                    valueText: String(prfEditorCard.s.stratum_color || "")
                                    placeholder: "Automático"
                                    onActivated: root.prfPick("Color del estrato",
                                                              root.prfColors.map(function(c) { return c.name }),
                                                              prfEditorCard.s.stratum_color, "calgen.default",
                                                              function(v) { root.setStratumExtra(prfEditorCard.idx, "stratum_color", v) })
                                }
                            }

                            GridLayout {
                                Layout.fillWidth: true
                                visible: prfEditorCard.hasStratum
                                columns: prfEditorCard.subColumns
                                columnSpacing: root.dp(12)
                                rowSpacing: root.dp(12)

                                // 2-3. Origen del estrato y sistema global de relleno antrópico.
                                PrfSubsection {
                                    title: "Origen del estrato"
                                    iconName: "map.marker"
                                    accent: root.cGenOrange

                                    RowLayout {
                                        Layout.fillWidth: true
                                        spacing: root.dp(6)
                                        Repeater {
                                            model: root.prfOriginOptions
                                            delegate: PrfSegment {
                                                required property var modelData
                                                implicitHeight: root.dp(40)
                                                label: modelData === "Mixto / intervenido" ? "Mixto" : modelData
                                                isOn: prfEditorCard.origin === modelData
                                                accent: root.cGenOrange
                                                accentSoft: root.cGenOrangeSoft
                                                onPicked: root.setStratumOrigin(prfEditorCard.idx, isOn ? "" : modelData)
                                            }
                                        }
                                    }
                                    PrfPickField {
                                        visible: prfEditorCard.origin === "Natural"
                                        sideLabel: prfEditorCard.sideLabels
                                        label: "Origen geológico"
                                        valueText: String(prfEditorCard.s.natural_origin || "")
                                        onActivated: root.prfPick("Origen geológico", root.prfNaturalOrigins,
                                                                  prfEditorCard.s.natural_origin, "map.marker",
                                                                  function(v) { root.setStratumExtra(prfEditorCard.idx, "natural_origin", v) })
                                    }
                                    Text {
                                        Layout.fillWidth: true
                                        visible: !prfEditorCard.origin.length
                                        text: "Elige el origen. Antrópico o Mixto habilita el detalle del relleno."
                                        color: root.cMuted
                                        font.pixelSize: root.sp(11)
                                        wrapMode: Text.WordWrap
                                    }
                                    ColumnLayout {
                                        Layout.fillWidth: true
                                        visible: prfEditorCard.anthropicLike
                                        spacing: root.dp(8)
                                        PrfPickField {
                                            sideLabel: prfEditorCard.sideLabels
                                            label: "Tipo de relleno"
                                            valueText: String(prfEditorCard.s.fill_type || "")
                                            onActivated: root.prfPick("Tipo de relleno", root.prfFillTypes, prfEditorCard.s.fill_type,
                                                                      root.iconStrataName,
                                                                      function(v) { root.setStratumExtra(prfEditorCard.idx, "fill_type", v) })
                                        }
                                        PrfPickField {
                                            sideLabel: prfEditorCard.sideLabels
                                            label: "Contexto / procedencia"
                                            valueText: String(prfEditorCard.s.fill_context || "")
                                            onActivated: root.prfPick("Contexto / procedencia", root.prfFillContexts, prfEditorCard.s.fill_context,
                                                                      "map.marker",
                                                                      function(v) { root.setStratumExtra(prfEditorCard.idx, "fill_context", v) })
                                        }
                                        PrfPickField {
                                            sideLabel: prfEditorCard.sideLabels
                                            label: "Control de colocación"
                                            valueText: String(prfEditorCard.s.fill_control || "")
                                            onActivated: root.prfPick("Control de colocación", root.prfFillControls, prfEditorCard.s.fill_control,
                                                                      "action.check",
                                                                      function(v) { root.setStratumExtra(prfEditorCard.idx, "fill_control", v) })
                                        }
                                        PrfPickField {
                                            sideLabel: prfEditorCard.sideLabels
                                            label: "Compactación"
                                            valueText: String(prfEditorCard.s.fill_compaction || "")
                                            onActivated: root.prfPick("Compactación", root.prfCompactions, prfEditorCard.s.fill_compaction,
                                                                      "calgen.depth",
                                                                      function(v) { root.setStratumExtra(prfEditorCard.idx, "fill_compaction", v) })
                                        }
                                        PrfPickField {
                                            sideLabel: prfEditorCard.sideLabels
                                            label: "Material matriz"
                                            valueText: String(prfEditorCard.s.fill_matrix || "")
                                            onActivated: root.prfPick("Material matriz", root.prfFillMatrix, prfEditorCard.s.fill_matrix,
                                                                      root.iconStrataName,
                                                                      function(v) { root.setStratumExtra(prfEditorCard.idx, "fill_matrix", v) })
                                        }
                                        Text {
                                            Layout.fillWidth: true
                                            Layout.topMargin: root.dp(4)
                                            text: "Componentes antrópicos"
                                            color: root.cMuted
                                            font.pixelSize: root.fsLabel
                                        }
                                        Flow {
                                            Layout.fillWidth: true
                                            spacing: root.dp(6)
                                            Repeater {
                                                model: root.prfFillComponents
                                                delegate: PrfChip {
                                                    required property var modelData
                                                    label: modelData
                                                    isOn: prfEditorCard.components.indexOf(modelData) >= 0
                                                    onFlipped: root.toggleStratumListValue(prfEditorCard.idx, "fill_components", modelData)
                                                }
                                            }
                                        }
                                        BoundTextField {
                                            Layout.fillWidth: true
                                            visible: prfEditorCard.components.indexOf("Otros") >= 0
                                            placeholderText: "Especifica otros componentes"
                                            modelText: String(prfEditorCard.s.fill_components_other || "")
                                            onCommit: function(t) { root.setStratumExtra(prfEditorCard.idx, "fill_components_other", t) }
                                        }
                                    }
                                }

                                // 4. Clasificación geotécnica.
                                PrfSubsection {
                                    title: "Clasificación geotécnica"
                                    iconName: "geotechnical.stratigraphy"
                                    accent: root.cGenBlue

                                    RowLayout {
                                        Layout.fillWidth: true
                                        spacing: root.dp(8)
                                        // Carretera prioriza AASHTO (orden visual; los datos no cambian).
                                        layoutDirection: root.prfActiveTemplate && root.prfActiveTemplate.aashtoFirst
                                                         ? Qt.RightToLeft : Qt.LeftToRight
                                        // SUCS / AASHTO = proyección del laboratorio (Web
                                        // LaboratoryProjection). Se adoptan en Laboratorio.
                                        PrfPickField {
                                            label: "SUCS"
                                            valueText: prfEditorCard.projection.sucs
                                            placeholder: "Pendiente de laboratorio"
                                            onActivated: root.openLabForStratum(prfEditorCard.idx)
                                        }
                                        PrfPickField {
                                            label: "AASHTO"
                                            valueText: prfEditorCard.projection.aashto
                                            placeholder: "Pendiente de laboratorio"
                                            onActivated: root.openLabForStratum(prfEditorCard.idx)
                                        }
                                    }
                                    Text {
                                        Layout.fillWidth: true
                                        text: "SUCS, AASHTO y patrón vienen del Laboratorio: se cambian adoptando la clasificación allí."
                                        color: root.cMuted
                                        font.pixelSize: root.sp(11)
                                        wrapMode: Text.WordWrap
                                    }
                                    Text {
                                        Layout.fillWidth: true
                                        text: "Descripción"
                                        color: root.cMuted
                                        font.pixelSize: root.fsLabel
                                    }
                                    PrfTextArea {
                                        label: "Descripción"
                                        modelText: String(prfEditorCard.s.descripcion || "")
                                        maxLength: 500
                                        placeholder: "Material, color, textura, compacidad, humedad…"
                                        onCommit: function(t) {
                                            cortesModel.setProperty(prfEditorCard.idx, "descripcion", t)
                                            root._markDirtySoon()
                                        }
                                    }
                                    PrfPickField {
                                        sideLabel: prfEditorCard.sideLabels
                                        label: "Estructura"
                                        valueText: String(prfEditorCard.s.structure || "")
                                        onActivated: root.prfPick("Estructura", root.prfStructures, prfEditorCard.s.structure,
                                                                  root.iconStrataName,
                                                                  function(v) { root.setStratumExtra(prfEditorCard.idx, "structure", v) })
                                    }
                                    PrfPickField {
                                        sideLabel: prfEditorCard.sideLabels
                                        label: "Humedad"
                                        valueText: prfEditorCard.s.humedad >= 0 && prfEditorCard.s.humedad < root.humItems.length
                                                   ? root.humItems[prfEditorCard.s.humedad] : ""
                                        onActivated: root.prfPickIndex("Humedad", root.humItems, prfEditorCard.s.humedad, "calgen.water",
                                                                       function(i) {
                                                                           cortesModel.setProperty(prfEditorCard.idx, "humedad", i)
                                                                           root._markDirty()
                                                                       })
                                    }
                                    PrfPickField {
                                        sideLabel: prfEditorCard.sideLabels
                                        label: "Consistencia / densidad"
                                        valueText: String(prfEditorCard.s.consistency || "")
                                        onActivated: root.prfPick("Consistencia / densidad",
                                                                  root.stratumConsistencyOptions(prfEditorCard.s),
                                                                  prfEditorCard.s.consistency, "calgen.depth",
                                                                  function(v) { root.setStratumExtra(prfEditorCard.idx, "consistency", v) })
                                    }
                                    PrfPickField {
                                        sideLabel: prfEditorCard.sideLabels
                                        label: "Estabilidad"
                                        valueText: prfEditorCard.s.estabilidad >= 0 && prfEditorCard.s.estabilidad < root.estItems.length
                                                   ? root.estItems[prfEditorCard.s.estabilidad] : ""
                                        onActivated: root.prfPickIndex("Estabilidad", root.estItems, prfEditorCard.s.estabilidad,
                                                                       "status.warning",
                                                                       function(i) {
                                                                           cortesModel.setProperty(prfEditorCard.idx, "estabilidad", i)
                                                                           root._markDirty()
                                                                       })
                                    }
                                    PrfPickField {
                                        sideLabel: prfEditorCard.sideLabels
                                        label: "Excavabilidad"
                                        valueText: prfEditorCard.s.excavabilidad >= 0 && prfEditorCard.s.excavabilidad < root.excItems.length
                                                   ? root.excItems[prfEditorCard.s.excavabilidad] : ""
                                        onActivated: root.prfPickIndex("Excavabilidad", root.excItems, prfEditorCard.s.excavabilidad,
                                                                       "calgen.machine",
                                                                       function(i) {
                                                                           cortesModel.setProperty(prfEditorCard.idx, "excavabilidad", i)
                                                                           root._markDirty()
                                                                       })
                                    }
                                }

                                ColumnLayout {
                                    Layout.fillWidth: true
                                    Layout.alignment: Qt.AlignTop
                                    spacing: root.dp(12)

                                    // 5. Muestreo (opcional). Fuente de verdad; Laboratorio la lee.
                                    PrfSubsection {
                                        title: "Muestra (opcional)"
                                        iconName: "calgen.attach"
                                        accent: root.cGenViolet
                                        resizable: true

                                        PrfPickField {
                                            label: "Tipo de muestra"
                                            valueText: String(prfEditorCard.s.tipo_muestra || "") === "Otro"
                                                       ? "Otro · " + String(prfEditorCard.s.tipo_otro || "")
                                                       : String(prfEditorCard.s.tipo_muestra || "")
                                            onActivated: root.prfPick("Tipo de muestra", root.sampleTypeItems.slice(1),
                                                                      prfEditorCard.s.tipo_muestra, "calgen.attach",
                                                                      function(v) {
                                                                          var index = prfEditorCard.idx
                                                                          cortesModel.setProperty(index, "tipo_muestra", v)
                                                                          if (v !== "Otro") cortesModel.setProperty(index, "tipo_otro", "")
                                                                          cortesModel.setProperty(index, "tipoText",
                                                                                                  v === "Otro" ? String(cortesModel.get(index).tipo_otro || "") : v)
                                                                          root._markDirty()
                                                                      })
                                        }
                                        BoundTextField {
                                            Layout.fillWidth: true
                                            visible: String(prfEditorCard.s.tipo_muestra || "") === "Otro"
                                            placeholderText: "Especifica el tipo"
                                            modelText: String(prfEditorCard.s.tipo_otro || "")
                                            onCommit: function(t) {
                                                cortesModel.setProperty(prfEditorCard.idx, "tipo_otro", t)
                                                cortesModel.setProperty(prfEditorCard.idx, "tipoText", t)
                                            }
                                        }
                                        RowLayout {
                                            Layout.fillWidth: true
                                            spacing: root.dp(8)
                                            PrfLabeledInput {
                                                label: "Desde (m)"
                                                BoundTextField {
                                                    Layout.fillWidth: true
                                                    numericKind: Rules.DEPTH_METERS
                                                    minimumValue: isFinite(prfEditorCard.fromDepth) ? prfEditorCard.fromDepth : 0
                                                    maximumValue: isFinite(prfEditorCard.toDepth) ? prfEditorCard.toDepth : root.depthMaxM
                                                    placeholderText: "Desde"
                                                    modelText: Rules.sampleIntervalValue(prfEditorCard.s, "muestra_desde")
                                                    onCommit: function(t) { return root.commitSampleInterval(prfEditorCard.idx, "muestra_desde", t) }
                                                }
                                            }
                                            PrfLabeledInput {
                                                label: "Hasta (m)"
                                                BoundTextField {
                                                    Layout.fillWidth: true
                                                    numericKind: Rules.DEPTH_METERS
                                                    minimumValue: isFinite(prfEditorCard.fromDepth) ? prfEditorCard.fromDepth : 0
                                                    maximumValue: isFinite(prfEditorCard.toDepth) ? prfEditorCard.toDepth : root.depthMaxM
                                                    placeholderText: "Hasta"
                                                    modelText: Rules.sampleIntervalValue(prfEditorCard.s, "muestra_hasta")
                                                    onCommit: function(t) { return root.commitSampleInterval(prfEditorCard.idx, "muestra_hasta", t) }
                                                }
                                            }
                                        }
                                        PrfLabeledInput {
                                            label: "ID de muestra"
                                            BoundTextField {
                                                Layout.fillWidth: true
                                                placeholderText: (txtCodigo.text.trim().length ? txtCodigo.text.trim() : "CALICATA")
                                                                 + "-M" + (prfEditorCard.idx + 1)
                                                maximumLength: 40
                                                modelText: String(prfEditorCard.s.sample_code || "")
                                                onCommit: function(t) { root.setStratumExtra(prfEditorCard.idx, "sample_code", t) }
                                            }
                                        }
                                    }

                                    // 6. Características adicionales.
                                    PrfSubsection {
                                        title: "Características adicionales"
                                        iconName: "action.check"
                                        accent: root.cGenGreen

                                        Text {
                                            Layout.fillWidth: true
                                            visible: !!root.prfActiveTemplate && root.prfActiveTemplate.featuresHint === true
                                            text: "Plantilla Ambiental: registra olor, manchas o contaminación solo si se observan."
                                            color: root.cMuted
                                            font.pixelSize: root.sp(11)
                                            wrapMode: Text.WordWrap
                                        }
                                        PrfCheck {
                                            label: "Registrar características adicionales"
                                            strong: true
                                            isOn: prfEditorCard.s.features_enabled === true
                                            onFlipped: root.setStratumExtra(prfEditorCard.idx, "features_enabled", !isOn)
                                        }
                                        GridLayout {
                                            Layout.fillWidth: true
                                            columns: prfEditorCard.subWidth >= root.dp(260) ? 2 : 1
                                            columnSpacing: root.dp(10)
                                            rowSpacing: root.dp(8)
                                            enabled: prfEditorCard.s.features_enabled === true
                                            opacity: enabled ? 1 : 0.45
                                            Repeater {
                                                model: root.prfFeatures
                                                delegate: PrfCheck {
                                                    required property var modelData
                                                    label: modelData.label
                                                    isOn: prfEditorCard.features[modelData.key] === true
                                                    onFlipped: root.toggleStratumFeature(prfEditorCard.idx, modelData.key)
                                                }
                                            }
                                        }
                                        BoundTextField {
                                            Layout.fillWidth: true
                                            visible: prfEditorCard.s.features_enabled === true && prfEditorCard.features.other === true
                                            placeholderText: "Detalle de otras características"
                                            modelText: String(prfEditorCard.s.features_other || "")
                                            onCommit: function(t) { root.setStratumExtra(prfEditorCard.idx, "features_other", t) }
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // ---------------- Columna derecha: vista y resumen ----------------
                    ColumnLayout {
                        id: prfRightCol
                        Layout.row: prfLayout.mode === 1 ? 2 : prfLayout.mode === 2 ? 1 : 0
                        Layout.column: prfLayout.mode === 3 ? 2 : 0
                        Layout.preferredWidth: prfLayout.mode === 1 ? -1 : prfLayout.sideWidth
                        Layout.maximumWidth: prfLayout.mode === 1 ? Number.POSITIVE_INFINITY : prfLayout.sideWidth
                        Layout.fillWidth: prfLayout.mode === 1
                        Layout.alignment: Qt.AlignTop
                        spacing: root.dp(16)

                        PrfCard {
                            title: "Vista del perfil"
                            iconName: root.iconStrataName
                            headerTrailing: [
                                GenRoundIconButton {
                                    width: root.dp(36)
                                    height: root.dp(36)
                                    iconName: "documents.open"
                                    enabled: cortesModel.count > 0
                                    opacity: enabled ? 1 : 0.35
                                    Accessible.name: "Ampliar vista del perfil"
                                    onClicked: prfGraphPopup.open()
                                }
                            ]
                            CalicataProfile {
                                Layout.fillWidth: true
                                Layout.preferredHeight: root.dp(prfLayout.mode === 1 ? 320 : 420)
                                model: cortesModel
                                bandInfo: root.stratumBandInfo
                                selectedIndex: root.selectedStratum
                                totalDepth: root.prfGraphDepth
                                waterDepth: root.prfWaterDepth
                                showWater: root.profileSetup.show_water_table !== false
                                scaleFactor: root.uiScale
                                ink: root.cText
                                muted: root.cMuted
                                gridColor: root.cBorder
                                accent: root.cGenBlue
                                waterColor: root.cGenBlue
                                paper: Qt.rgba(root.cSurface.r, root.cSurface.g, root.cSurface.b, root.darkMode ? 0.18 : 0.40)   // papel del gráfico sobre el vidrio de la tarjeta
                                onSelected: function(index) { root.selectStratum(index, "field") }
                            }
                        }

                        PrfCard {
                            title: "Resumen del perfil"
                            iconName: "calgen.description"
                            PrfStatRow {
                                iconName: "calgen.depth"
                                label: "Profundidad total"
                                value: root.prfGraphDepth > 0 ? root.prfGraphDepth.toFixed(2) + " m" : "—"
                            }
                            PrfStatRow {
                                iconName: "calgen.water"
                                label: "Nivel freático"
                                value: isFinite(root.prfWaterDepth) ? root.prfWaterDepth.toFixed(2) + " m" : "No registrado"
                            }
                            PrfStatRow {
                                iconName: root.iconStrataName
                                label: "N.º de estratos"
                                value: String(cortesModel.count)
                            }
                            PrfStatRow {
                                iconName: "geotechnical.calicata"
                                label: "Relleno antrópico"
                                value: root.prfStats.anthropicCount > 0
                                       ? root.prfStats.anthropicThickness.toFixed(2) + " m (" + root.prfStats.anthropicCount + ")"
                                       : "—"
                            }
                            PrfStatRow {
                                iconName: "calgen.machine"
                                label: "Excavación"
                                value: root.profileSetupText("excavation_type").length
                                       ? root.profileSetupText("excavation_type") : "No registrado"
                            }
                        }

                        PrfCard {
                            id: prfInterpretationCard
                            title: "Interpretación geotécnica"
                            iconName: "calgen.description"
                            PrfTextArea {
                                label: "Interpretación geotécnica"
                                modelText: root.profileSetupText("interpretation")
                                maxLength: 1000
                                minHeight: root.dp(120)
                                placeholder: "Escribe una interpretación o genera una propuesta con InGe AI…"
                                onCommit: function(t) { root.updateProfileSetup({ interpretation: t }, true) }
                            }
                            PrfToolButton {
                                visible: cortesModel.count > 0
                                enabled: !root.coreReviewBusy && !root._coreReviewRetryPending
                                text: root.profileSetupText("interpretation").length ? "Revisar interpretación con IA" : "Generar interpretación con IA"
                                iconName: "calgen.default"
                                onClicked: {
                                    root._flushCortesRevision()
                                    root.requestAssistedReview("interpretation")
                                }
                            }
                        }

                        PrfCard {
                            id: prfGeneralClassCard
                            title: "Clasificación general"
                            iconName: "calgen.identity"
                            readonly property string suggested: root.suggestedGeneralClass()
                            PrfPickField {
                                valueText: root.profileSetupText("general_classification")
                                onActivated: root.prfPick("Clasificación general", root.prfGeneralClasses,
                                                          root.profileSetupText("general_classification"), root.iconStrataName,
                                                          function(v) { root.updateProfileSetup({ general_classification: v }) })
                            }
                            Text {
                                Layout.fillWidth: true
                                text: "Clasificación representativa del perfil completo."
                                color: root.cMuted
                                font.pixelSize: root.sp(11)
                                wrapMode: Text.WordWrap
                            }
                            PrfToolButton {
                                visible: prfGeneralClassCard.suggested.length > 0
                                         && prfGeneralClassCard.suggested !== root.profileSetupText("general_classification")
                                text: "Sugerida: " + prfGeneralClassCard.suggested
                                iconName: "calgen.default"
                                onClicked: root.updateProfileSetup({ general_classification: prfGeneralClassCard.suggested })
                            }
                        }
                    }
                }
            }

            MobileStageBody {
                id: mobileLaboratoryOverview
                glassPanel: false   // compone sus propias superficies primarias
                sectionNumber: 5
                sectionTitle: "Muestras / Laboratorio"
                sectionSubtitle: "Ensayos y clasificación por estrato"

                // Laboratorio (preview final): estado vacío o lista de estratos con
                // Perfil / Campo separado de Laboratorio.
                readonly property var labInfos: root.labInfosAll
                readonly property int labCount: {
                    var n = 0
                    for (var i = 0; i < labInfos.length; ++i) if (labInfos[i] && (labInfos[i].hasSample || labInfos[i].hasTests)) ++n
                    return n
                }

                // Estado vacío (0 estratos): sin estratos no hay muestras ni ensayos.
                // Con estratos y sin ensayos se muestran las tarjetas ("Sin ensayo registrado").
                ColumnLayout {
                    Layout.fillWidth: true
                    visible: cortesModel.count === 0
                    spacing: root.dp(12)
                    Item { Layout.preferredHeight: root.dp(12) }
                    Rectangle {
                        Layout.alignment: Qt.AlignHCenter
                        Layout.preferredWidth: root.dp(116)
                        Layout.preferredHeight: root.dp(116)
                        radius: width / 2
                        color: "transparent"
                        CalicataLiquidGlass { dark: root.darkMode; accent: root.cGenBlue; danger: root.flow ? root.flow.theme.error : "#D9483B"; anchors.fill: parent; radius: parent.radius; tone: "tinted" }
                        Components.FlowIcon {
                            anchors.centerIn: parent
                            width: root.dp(54)
                            height: root.dp(54)
                            name: root.iconSamplesName
                            flow: root.flow
                            tintColor: root.cGenBlue
                            activeTintColor: root.cGenBlue
                            inactiveOpacity: 1.0
                        }
                    }
                    Text {
                        Layout.fillWidth: true
                        horizontalAlignment: Text.AlignHCenter
                        text: "Aún no hay estratos\npara laboratorio"
                        color: root.cText
                        font.bold: true
                        font.pixelSize: root.sp(20)
                        wrapMode: Text.WordWrap
                    }
                    Text {
                        Layout.fillWidth: true
                        horizontalAlignment: Text.AlignHCenter
                        text: "Primero agrega al menos un estrato en Perfil para registrar muestras y ensayos."
                        color: root.cMuted
                        font.pixelSize: root.fsLabel
                        wrapMode: Text.WordWrap
                    }
                    PrfToolButton {
                        Layout.alignment: Qt.AlignHCenter
                        primaryTone: true
                        iconName: root.iconStrataName
                        text: "Ir a Perfil"
                        onClicked: root.labGoProfile()
                    }
                    Item { Layout.preferredHeight: root.dp(12) }
                }

                RowLayout {
                    Layout.fillWidth: true
                    visible: cortesModel.count > 0
                    spacing: root.dp(8)
                    Text { Layout.fillWidth: true; text: "Estratos y muestras"; color: root.cText; font.bold: true; font.pixelSize: root.fsField }
                    PrfToolButton {
                        primaryTone: true
                        iconName: "action.add"
                        text: "Nueva muestra"
                        onClicked: root.labNewSample()
                    }
                }
                RowLayout {
                    Layout.fillWidth: true
                    visible: cortesModel.count > 0
                    spacing: root.dp(6)
                    Repeater {
                        model: [{ key: "strata", label: "Estratos y muestras" }, { key: "results", label: "Resultados" }]
                        delegate: PrfSegment {
                            required property var modelData
                            implicitHeight: root.dp(36)
                            label: modelData.label
                            isOn: root.labView === modelData.key
                            accent: root.cGenBlue
                            accentSoft: root.cGenBlueSoft
                            onPicked: root.labView = modelData.key
                        }
                    }
                }
                Flow {
                    Layout.fillWidth: true
                    visible: cortesModel.count > 0
                    spacing: root.dp(6)
                    // Un solo estado de filtro (root.labFilterKey), compartido con el Dock.
                    Repeater {
                        model: cortesModel.count > 0
                               ? [{ key: "", label: "Todos (" + cortesModel.count + ")" }]
                                 .concat(root.labStrataEntries.map(function(e, i) {
                                     var x = root.labInfosAll[i]
                                     return { key: e.key, label: e.label + " (" + (x && (x.hasSample || x.hasTests) ? 1 : 0) + ")" }
                                 }))
                                 .concat(root.labPendingCount > 0 ? [{ key: "pending", label: "Pendientes (" + root.labPendingCount + ")" }] : [])
                               : []
                        delegate: PrfChip {
                            required property var modelData
                            label: modelData.label
                            isOn: root.labFilterKey === modelData.key
                            onFlipped: root.labSetFilter(modelData.key)
                        }
                    }
                }

                Repeater {
                    model: cortesModel
                    delegate: Rectangle {
                        id: labCard
                        property int corteIdx: index
                        readonly property var info: corteIdx < mobileLaboratoryOverview.labInfos.length ? mobileLaboratoryOverview.labInfos[corteIdx] : null
                        readonly property string kind: root.labKindChip(info)
                        visible: root.labView === "strata" && root.labCardVisible(info)
                        Layout.fillWidth: true
                        implicitHeight: labCardColumn.implicitHeight + root.dp(24)
                        radius: root.dp(16)
                        color: "transparent"
                        CalicataLiquidGlass {
                            dark: root.darkMode; accent: root.cGenBlue; danger: root.flow ? root.flow.theme.error : "#D9483B"
                            anchors.fill: parent
                            radius: parent.radius
                            level: "card"
                            pressed: labCardTap.pressed
                            selected: root.labDetailOpen && root.selectedStratum === corteIdx
                        }
                        border.width: 0
                        border.color: root.cBorder
                        Accessible.role: Accessible.Button
                        Accessible.name: "Estrato " + (corteIdx + 1) + ", laboratorio " + (info ? info.stageLabel : "")
                        Rectangle {
                            anchors.left: parent.left
                            anchors.top: parent.top
                            anchors.bottom: parent.bottom
                            anchors.margins: root.dp(10)
                            width: root.dp(3)
                            radius: width / 2
                            color: root.labStageColor(labCard.info ? labCard.info.stage : "", false)
                        }
                        scale: labCardTap.pressed ? 0.985 : 1.0
                        Behavior on scale { NumberAnimation { duration: root.flow ? root.flow.instantDuration : 70; easing.type: Easing.OutQuad } }
                        TapHandler { id: labCardTap; onTapped: root.openLabForStratum(labCard.corteIdx, labCard) }
                        ColumnLayout {
                            id: labCardColumn
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.top: parent.top
                            anchors.leftMargin: root.dp(22)
                            anchors.rightMargin: root.dp(12)
                            anchors.topMargin: root.dp(12)
                            spacing: root.dp(6)
                            RowLayout {
                                Layout.fillWidth: true
                                spacing: root.dp(8)
                                Text {
                                    Layout.fillWidth: true
                                    text: "Estrato " + (labCard.corteIdx + 1) + " · " + String(de || "—") + " – " + String(a || "—") + " m"
                                    color: root.cText
                                    font.bold: true
                                    font.pixelSize: root.fsField
                                    elide: Text.ElideRight
                                }
                                Rectangle {
                                    visible: labCard.kind.length > 0
                                    Layout.preferredWidth: kindText.implicitWidth + root.dp(16)
                                    Layout.preferredHeight: root.dp(22)
                                    radius: height / 2
                                    color: labCard.kind === "RA" ? root.cGenOrangeSoft : labCard.kind === "ROCA" ? (root.darkMode ? Qt.rgba(1, 1, 1, 0.08) : Qt.rgba(1, 1, 1, 0.62))
                                         : labCard.kind === "ORG" ? root.cGenGreenSoft : root.cGenTealSoft
                                    Text {
                                        id: kindText
                                        anchors.centerIn: parent
                                        text: labCard.kind
                                        color: labCard.kind === "RA" ? root.cGenOrange : labCard.kind === "ROCA" ? root.cMuted
                                             : labCard.kind === "ORG" ? root.cGenGreen : root.cGenTeal
                                        font.bold: true
                                        font.pixelSize: root.sp(11)
                                    }
                                }
                                Text { text: "›"; color: root.cMuted; font.pixelSize: root.sp(22) }
                            }
                            Text {
                                Layout.fillWidth: true
                                text: root.labContextText(labCard.info)
                                color: root.cMuted
                                font.pixelSize: root.fsLabel
                                elide: Text.ElideRight
                            }
                            RowLayout {
                                Layout.fillWidth: true
                                spacing: root.dp(12)
                                ColumnLayout {
                                    Layout.fillWidth: true
                                    Layout.preferredWidth: 1
                                    Layout.alignment: Qt.AlignTop
                                    spacing: 1
                                    Text { text: "Estrato (proyección)"; color: root.cMuted; font.bold: true; font.pixelSize: root.sp(11) }
                                    Text { Layout.fillWidth: true; elide: Text.ElideRight; color: root.cText; font.pixelSize: root.fsLabel
                                           text: "SUCS: " + (labCard.info && labCard.info.projection.sucs.length ? labCard.info.projection.sucs : "Pendiente de laboratorio") }
                                    Text { Layout.fillWidth: true; elide: Text.ElideRight; color: root.cText; font.pixelSize: root.fsLabel
                                           text: "AASHTO: " + (labCard.info && labCard.info.projection.aashto.length ? labCard.info.projection.aashto : "Pendiente de laboratorio") }
                                }
                                ColumnLayout {
                                    Layout.fillWidth: true
                                    Layout.preferredWidth: 1
                                    Layout.alignment: Qt.AlignTop
                                    spacing: 2
                                    Text {
                                        text: "Laboratorio"
                                        color: root.cMuted; font.bold: true; font.pixelSize: root.sp(11)
                                    }
                                    Text {
                                        Layout.fillWidth: true
                                        wrapMode: Text.WordWrap
                                        color: labCard.info && labCard.info.labText.length ? root.cText : root.cMuted
                                        font.pixelSize: root.fsLabel
                                        text: !labCard.info ? "" : labCard.info.labText.length ? labCard.info.labText
                                              : labCard.info.hasTests ? "Ensayo sin clasificación" : "Sin ensayo registrado"
                                    }
                                    Rectangle {
                                        visible: !!labCard.info && ["confirmed", "suggested", "in_progress"].indexOf(labCard.info.stage) >= 0
                                        Layout.preferredWidth: stageText.implicitWidth + root.dp(16)
                                        Layout.preferredHeight: root.dp(22)
                                        radius: height / 2
                                        color: root.labStageColor(labCard.info ? labCard.info.stage : "", true)
                                        Text {
                                            id: stageText
                                            anchors.centerIn: parent
                                            text: labCard.info ? labCard.info.stageLabel : ""
                                            color: root.labStageColor(labCard.info ? labCard.info.stage : "", false)
                                            font.bold: true
                                            font.pixelSize: root.sp(11)
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
                // Resultados y seguimiento: una tarjeta por muestra/ensayo real (sin datos inventados).
                Text {
                    Layout.fillWidth: true
                    visible: root.labView === "results" && cortesModel.count > 0
                    text: root.labDataCount === 0 ? "Sin muestras ni ensayos registrados todavía."
                          : root.labSummaryText().split(String.fromCharCode(10)).join(" · ")
                    color: root.cMuted
                    font.pixelSize: root.fsLabel
                    wrapMode: Text.WordWrap
                }
                Repeater {
                    model: root.labView === "results" ? root.labInfosAll : []
                    delegate: Rectangle {
                        id: resultCard
                        required property var modelData
                        required property int index
                        readonly property var p: modelData ? modelData.plain : ({})
                        readonly property string code: String(p.sample_code || "").length ? String(p.sample_code) : "M-" + (index + 1 < 10 ? "0" : "") + (index + 1)
                        function num(v) { var t = String(v === undefined || v === null ? "" : v); return t.length ? t : "—" }
                        visible: !!modelData && (modelData.hasSample || modelData.hasTests) && root.labCardVisible(modelData)
                        Layout.fillWidth: true
                        implicitHeight: resultColumn.implicitHeight + root.dp(24)
                        radius: root.dp(16)
                        color: "transparent"
                        CalicataLiquidGlass { dark: root.darkMode; accent: root.cGenBlue; danger: root.flow ? root.flow.theme.error : "#D9483B"; anchors.fill: parent; radius: parent.radius; level: "card" }
                        Rectangle {
                            anchors.left: parent.left; anchors.top: parent.top; anchors.bottom: parent.bottom
                            anchors.margins: root.dp(10)
                            width: root.dp(3); radius: width / 2
                            color: root.labStageColor(resultCard.modelData ? resultCard.modelData.stage : "", false)
                        }
                        scale: resultCardTap.pressed ? 0.985 : 1.0
                        Behavior on scale { NumberAnimation { duration: root.flow ? root.flow.instantDuration : 70; easing.type: Easing.OutQuad } }
                        TapHandler { id: resultCardTap; onTapped: root.openLabForStratum(resultCard.index, resultCard) }
                        ColumnLayout {
                            id: resultColumn
                            anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top
                            anchors.leftMargin: root.dp(22); anchors.rightMargin: root.dp(12); anchors.topMargin: root.dp(12)
                            spacing: root.dp(4)
                            RowLayout {
                                Layout.fillWidth: true
                                spacing: root.dp(8)
                                Text { text: resultCard.code; color: root.cText; font.bold: true; font.pixelSize: root.fsField }
                                Rectangle {
                                    Layout.preferredWidth: resultStage.implicitWidth + root.dp(16)
                                    Layout.preferredHeight: root.dp(22)
                                    radius: height / 2
                                    color: root.labStageColor(resultCard.modelData ? resultCard.modelData.stage : "", true)
                                    Text { id: resultStage; anchors.centerIn: parent; text: resultCard.modelData ? resultCard.modelData.stageLabel : ""
                                           color: root.labStageColor(resultCard.modelData ? resultCard.modelData.stage : "", false); font.bold: true; font.pixelSize: root.sp(11) }
                                }
                                Item { Layout.fillWidth: true }
                                Text { text: "›"; color: root.cMuted; font.pixelSize: root.sp(22) }
                            }
                            Text { Layout.fillWidth: true; text: "Estrato " + (resultCard.index + 1) + " · " + resultCard.num(resultCard.p.de) + " – " + resultCard.num(resultCard.p.a) + " m"
                                   color: root.cText; font.pixelSize: root.fsLabel; font.bold: true; elide: Text.ElideRight }
                            Text { Layout.fillWidth: true; text: root.labContextText(resultCard.modelData); color: root.cMuted; font.pixelSize: root.fsLabel; elide: Text.ElideRight }
                            Repeater {
                                model: resultCard.modelData && resultCard.modelData.hasTests ? [
                                    { l: "Humedad natural", v: resultCard.num(resultCard.p.hum2) + (String(resultCard.p.hum2 || "").length ? " %" : "") },
                                    { l: "Límite líquido / plástico", v: resultCard.num(resultCard.p.wl) + " / " + resultCard.num(resultCard.p.lp) },
                                    { l: "Granulometría (N.º 4/10/40/200)", v: resultCard.num(resultCard.p.passing_no4) + " / " + resultCard.num(resultCard.p.g2)
                                                                             + " / " + resultCard.num(resultCard.p.g04) + " / " + resultCard.num(resultCard.p.g008) },
                                    { l: "Clasificación", v: resultCard.modelData.labText.length ? resultCard.modelData.labText : "Pendiente" }
                                ] : [{ l: "Ensayos", v: "Sin ensayos registrados" }]
                                delegate: RowLayout {
                                    required property var modelData
                                    Layout.fillWidth: true
                                    spacing: root.dp(8)
                                    Text { Layout.fillWidth: true; text: modelData.l; color: root.cMuted; font.pixelSize: root.sp(11); elide: Text.ElideRight }
                                    Text { text: modelData.v; color: root.cText; font.pixelSize: root.sp(11) }
                                }
                            }
                        }
                    }
                }
            }

            CalicataReview {
                width: parent.width
                viewport: vFlick
                visible: root.stageIndex === 5 && !root.reviewNotesEditing
                flow: root.flow
                scaleFactor: root.uiScale
                darkMode: root.darkMode
                ink: root.cText
                muted: root.cMuted
                accent: root.cGenBlue
                accentSoft: root.cGenBlueSoft
                good: root.cGenGreen
                warn: root.cGenOrange
                danger: root.flow ? root.flow.theme.error : "#D9483B"
                reviewed: root.reviewRequested
                summary: root.reviewSummaryData
                facts: root.reviewFactsData
                recommendations: root.reviewRecommendationsData
                conclusion: root.reviewConclusionText
                observations: root.observacionesText
                excavabilityLabels: root.excItems
                stabilityLabels: root.estItems
                aiText: root.coreFeedback
                aiBusy: root.coreReviewBusy || root._coreReviewRetryPending
                aiFindings: root.coreFindings
                codeText: txtCodigo.text
                onSectionSelected: function(section) { root.openReviewSection(section) }
                onIssueSelected: function(issue) { root.openReviewIssue(issue) }
                onRefreshRequested: root.reviewForExport()
            }

            MobileStageBody {
                id: mobileActivitySection
                sectionNumber: 8
                sectionTitle: "Actividad"
                sectionSubtitle: "Eventos confirmados en la nube"
                Label {
                    Layout.fillWidth: true
                    visible: root.activityRows.length === 0
                    text: root.doc && String(root.doc.header.remoteCalicataId || "").length
                          ? "Sin actividad registrada todavía." : "La actividad aparece cuando la ficha existe en la nube."
                    color: root.cMuted
                    wrapMode: Text.WordWrap
                }
                Repeater {
                    model: root.activityRows
                    delegate: ColumnLayout {
                        required property var modelData
                        Layout.fillWidth: true
                        spacing: 0
                        Text {
                            Layout.fillWidth: true
                            text: String(modelData.action || "") + " · " + String(modelData.platform || "")
                            color: root.cText; font.bold: true; font.pixelSize: root.fsLabel
                        }
                        Text {
                            Layout.fillWidth: true
                            text: String(modelData.description || "")
                                  + "\n" + String(modelData.created_at || "").replace("T", " ").substring(0, 19)
                                  + (modelData.actor_id ? " · " + String(modelData.actor_id).substring(0, 8) : "")
                            color: root.cMuted; font.pixelSize: root.fsLabel; wrapMode: Text.WordWrap
                        }
                    }
                }
                GenDialogButton {
                    visible: root.activityHasMore
                    soft: true
                    iconName: "status.sync"
                    text: "Cargar más"
                    onClicked: CalicataCloud.loadActivity(root.doc, root.activityRows.length)
                }
            }

            MobileStageBody {
                id: mobileObservationsSection
                sectionNumber: 8
                sectionTitle: "Observaciones"
                sectionSubtitle: "Notas generales de la calicata"


                StageButton {
                    Layout.fillWidth: true
                    text: "Volver a revisión"
                    onClicked: {
                        if (!root.finishReviewCorrection())
                            root.scrollToSection(9)
                    }
                }

                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: Math.max(root.dp(130), mobileObservations.contentHeight + root.dp(30))
                    radius: root.rField
                    color: "transparent"
                    CalicataLiquidGlass { dark: root.darkMode; accent: root.cGenBlue; danger: root.flow ? root.flow.theme.error : "#D9483B"; anchors.fill: parent; radius: parent.radius; focused: mobileObservations.activeFocus }

                    TextArea {
                        id: mobileObservations
                        anchors.fill: parent
                        anchors.margins: root.dp(11)
                        wrapMode: TextEdit.Wrap
                        placeholderText: "Escriba observaciones generales..."
                        color: root.cText
                        padding: 0
                        Binding {
                            target: mobileObservations
                            property: "text"
                            value: (root.observacionesText !== undefined && root.observacionesText !== null)
                                   ? String(root.observacionesText) : ""
                            when: !mobileObservations.activeFocus && !root._loading
                            restoreMode: Binding.RestoreNone
                        }
                        onTextChanged: {
                            if (root._loading || !activeFocus) return
                            root.observacionesText = text
                            root._markDirtySoon()
                        }
                        background: Rectangle { color: "transparent" }
                    }
                }

                Text {
                    Layout.fillWidth: true
                    text: mobileObservations.length + " caracteres"
                    color: root.cMuted
                    font.pixelSize: root.sp(root.isPhone ? 10 : 12)
                    horizontalAlignment: Text.AlignRight
                }
            }


            Rectangle {
                width: parent.width
                visible: root.persistenceError && root.persistenceStatus.length > 0
                implicitHeight: visible ? saveStatus.implicitHeight + root.dp(24) : 0
                radius: root.rField
                color: "transparent"
                CalicataLiquidGlass { dark: root.darkMode; accent: root.cGenBlue; danger: root.flow ? root.flow.theme.error : "#D9483B"; anchors.fill: parent; radius: parent.radius; level: "card" }
                Text {
                    id: saveStatus
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.margins: root.dp(12)
                    text: root.persistenceStatus
                    color: root.persistenceError ? (root.flow ? root.flow.theme.error : "#B4232E") : root.cMuted
                    font.pixelSize: root.fsLabel
                    wrapMode: Text.WordWrap
                    Accessible.role: Accessible.StaticText
                }
            }

            Item { width: 1; height: root.dp(8) }
        }
    }

    // Fondo desenfocado del detalle de Laboratorio. Captura vFlick (no la página: la
    // capa vive en ella) una sola vez, sobre base opaca; se registra en la ventana.
    Loader {
        id: labDetailBackdrop
        anchors.fill: vFlick
        z: 899
        active: stratumSheet.visible && stratumSheet.floating
        opacity: stratumSheet.opacity
        sourceComponent: Item {
            id: labBlurLayer
            Rectangle { anchors.fill: parent; color: root.cPage }
            ShaderEffectSource {
                id: labBlurCapture
                anchors.fill: parent
                sourceItem: vFlick
                textureSize: Qt.size(Math.max(1, Math.round(width * 0.5)), Math.max(1, Math.round(height * 0.5)))
                live: false
                hideSource: false
                visible: false
                Component.onCompleted: scheduleUpdate()
            }
            MultiEffect {
                anchors.fill: parent
                source: labBlurCapture
                autoPaddingEnabled: false
                blurEnabled: true
                blurMax: 48
                blur: 0.62
                saturation: 0.30
            }
            Component.onCompleted: stratumSheet.glassBackdropItem = labBlurLayer
            Component.onDestruction: if (stratumSheet.glassBackdropItem === labBlurLayer) stratumSheet.glassBackdropItem = null
        }
    }

    // Velo del detalle de Laboratorio: atenúa la lista base (sigue reconocible) y
    // bloquea sus gestos; tocarlo cierra con la misma animación que Back.
    Rectangle {
        id: labDetailScrim
        anchors.fill: parent
        z: 900
        color: "#000000"
        opacity: root.labSheetActive && !root.labDetailClosing ? (root.darkMode ? 0.42 : 0.26) : 0
        visible: opacity > 0.001
        Behavior on opacity { NumberAnimation { duration: root.flow ? root.flow.duration(220) : 220; easing.type: Easing.OutCubic } }
        LabDetailScrimBlocker {
            enabled: labDetailScrim.visible
            onClicked: root.closeLabDetail()
            onWheel: function(wheel) { wheel.accepted = true }
        }
    }
}

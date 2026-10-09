import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../components" as Components

// Editor avanzado de una fotografía de Calicata (contrato Web photoDerivative.ts /
// photoOverlayStyle.ts). La ORIGINAL nunca se toca. "Después" es una vista previa
// REAL generada por el mismo pipeline C++ que la derivada final
// (CalicataDocument::requestPhotoPreview -> applyPhotoImageEdit + paintPhotoDerivative),
// así cada herramienta afecta exactamente al resultado publicado. Solo
// "Regenerar y publicar" crea una versión; abrir, previsualizar, cancelar o guardar
// borrador no.
Popup {
    id: editor

    property var form: null          // CalicataFormPage (tokens de color, dp, conversión UTM)
    property var doc: null
    property int slotIndex: 1
    property string slotTitle: ""
    property var cloud: null         // CalicataCloud

    // Estado editable (shape Web: fields/metadata/style + logo) + image/watermark/annotations.
    property var edit: ({})
    property var undoStack: []
    property var redoStack: []
    property bool rendering: false
    property string statusText: ""
    property int tab: 0
    property int shownTab: 0
    property var cloudVersions: []
    property var slot: ({})
    property real comparePos: 0.5
    property real zoom: 1
    property real panX: 0
    property real panY: 0
    // Vista previa real (C++, ≤1280 px, debounce + coalescencia por ranura).
    property url previewUrl: ""
    property url shownPreviewUrl: ""
    property int previewToken: 0
    property bool previewBusy: false
    property url baseUrl: ""
    property int baseToken: 0
    // Herramientas interactivas: "" | "crop" | "perspective" | "draw".
    property string mode: ""
    property var cropDraft: ({ x: 0, y: 0, w: 1, h: 1 })
    property real cropAspect: 0
    property var perspDraft: [[0, 0], [1, 0], [1, 1], [0, 1]]
    property var strokes: []
    property var strokeUndo: []
    property var strokeRedo: []
    property var liveStroke: null
    property string drawTool: "pen"
    property string drawColor: "#ff3b30"
    property real drawWidth: 0.8
    // Posición directa sobre la vista previa: "" | "label" | "logo" | "watermark".
    property string dragTarget: ""
    // Gesto continuo (deslizador, arrastre, escritura): una sola entrada de deshacer.
    property var activeGesture: null
    property var lastUndoGesture: null
    // Logos reales de la ficha, resueltos por C++ (la misma ruta que usa el render).
    property string logoProjectUrl: ""
    property string logoEntityUrl: ""
    property double renderStartedAt: 0
    property string previewWarning: ""
    // Qt.inputMethod como var: sus miembros (visible/hide) no están tipados para qmllint.
    readonly property var inputMethod: Qt.inputMethod
    readonly property bool imeOpen: !!inputMethod && inputMethod.visible === true
    // Origen visual (tarjeta) de la apertura.
    property real originDX: 0
    property real originDY: 0
    property real offsetX: 0
    property real offsetY: 0
    // Operación foreground del editor (mismo componente que Calicatas).
    property var photoOperation: null
    function _photoResult(result, title, detail, closeEditor) {
        var op = photoOperation || {}
        if (op.id && !op.result)
            console.info("INGE_CALICATA_OPERATION_END kind=" + (op.kind === "MEDIA_RESTORE" ? "MEDIA_RESTORE" : "PHOTO_RENDER")
                         + " id=" + op.id + " result=" + result
                         + " elapsedMs=" + Math.round(Date.now() - (renderStartedAt || Date.now())))
        photoOperation = Object.assign({}, op, { result: result, title: title, detail: detail,
            closeEditor: closeEditor === true, actions: [{ id: "close", label: "Cerrar" }] })
        rendering = false
    }

    // Tokens (sistema Calicatas).
    readonly property color cPage: form ? form.cPage : "#101418"
    // Tema del material Liquid Glass de Calicatas (CalicataSurface).
    readonly property bool dark: form ? form.darkMode === true : true
    readonly property color cSurface: form ? form.cSurface : "#1B2128"
    readonly property color cSurfaceAlt: form ? form.cSurfaceAlt : "#232A33"
    readonly property color cText: form ? form.cText : "#F2F5F8"
    readonly property color cMuted: form ? form.cMuted : "#9AA6B2"
    readonly property color cBorder: form ? form.cBorder : "#2C343D"
    readonly property color cBlue: form ? form.cGenBlue : "#1F5BD6"
    readonly property color cBlueSoft: form ? form.cGenBlueSoft : "#1C2740"
    readonly property color cGreen: form ? form.cGenGreen : "#2E8B4E"
    readonly property color cOrange: form ? form.cGenOrange : "#DE7A12"
    readonly property int motion: form && form.flow ? form.flow.duration(200) : 200

    // [clave, etiqueta, visible por defecto] — mismos defaults que photoOverlayLines (C++).
    readonly property var photoFields: [
        ["zone", "Zona", true], ["easting", "Este", true], ["northing", "Norte", true], ["altitude", "Altitud", true],
        ["calicata", "Código de calicata", true], ["project", "Proyecto", true], ["date", "Fecha", true],
        ["time", "Hora", true], ["depth", "Profundidad", false], ["category", "Categoría", false], ["user", "Responsable", false]
    ]
    readonly property var fonts: [["sans", "Sans", "sans-serif"], ["serif", "Serif", "serif"],
        ["mono", "Mono", "monospace"], ["condensed", "Estrecha", "sans-serif-condensed"]]
    readonly property var backdrops: [["shadow", "Sombra"], ["panel", "Panel"], ["none", "Sin fondo"]]
    readonly property var anchorIds: ["top-left", "top-center", "top-right", "middle-left", "middle-center",
        "middle-right", "bottom-left", "bottom-center", "bottom-right"]
    readonly property var colors: ["#ffffff", "#ffe066", "#7cf3c0", "#8ecbff", "#ff9b9b", "#111827"]
    readonly property var drawColors: ["#ff3b30", "#ffcc00", "#34c759", "#0a84ff", "#ffffff", "#111827"]
    readonly property var defaultStyle: ({ fontId: "sans", bold: false, sizePct: 4, color: "#ffffff",
        backdrop: "shadow", anchor: "bottom-right", offsetXPct: 0, offsetYPct: 0, coordFormat: "utm",
        logoAnchor: "top-left", logoScalePct: 100, logoOpacityPct: 100, logoMarginPct: 0, enlargeSmall: true })
    // Herramientas de imagen (solo la derivada; ver applyPhotoImageEdit en C++).
    readonly property var defaultImage: ({ rotation: 0, angle: 0, flipH: false, flipV: false, aspect: "free",
        exposure: 0, brightness: 0, contrast: 0, highlights: 0, shadows: 0, warmth: 0, tint: 0, saturation: 0,
        clarity: 0, sharpness: 0, vignette: 0, vignetteSize: 50, vignetteSoftness: 50, vignetteX: 0.5, vignetteY: 0.5,
        preset: "original", presetIntensity: 100, resolution: "max" })
    readonly property var presets: [["original", "Original"], ["natural", "Natural"], ["contrast", "Contraste"],
        ["documentary", "Documental"], ["technical", "Técnico"], ["bw", "Blanco y negro"]]
    readonly property var tabs: [["Datos", "documents.file"], ["Estilo", "action.edit"], ["Composición", "map.layers"],
        ["Logo", "documents.image"], ["Filtros", "status.sync"], ["Ajustes", "action.check"],
        ["Avanzado", "action.menu"], ["Versiones", "documents.folder"]]

    function dp(v) { return form ? form.dp(v) : v }
    function clone(v) { return JSON.parse(JSON.stringify(v === undefined || v === null ? {} : v)) }
    readonly property var img: edit.image || defaultImage
    readonly property var st: edit.style || defaultStyle
    readonly property var wm: edit.watermark || ({})
    readonly property var meta: edit.metadata || ({})
    readonly property bool hasGeo: String(meta.latitude || "").length > 0 && String(meta.longitude || "").length > 0

    // Metadatos reales de la ficha (autofill): nunca se piden al usuario.
    function freshMetadata() {
        // Ficha vigente + datos propios de ESTA foto: fecha = fecha de la ficha;
        // hora = hora manual de la ficha o la hora del sistema fijada una vez
        // para esta foto (se persiste la primera vez; regenerar no la cambia).
        if (doc && doc.ensurePhotoSystemTime) doc.ensurePhotoSystemTime(slotIndex)
        var m = doc ? (doc.photoMetadata ? doc.photoMetadata(slotIndex) : doc.photoSheetMetadata()) : ({})
        m.category = slotTitle
        if ((!String(m.latitude || "").length || !String(m.longitude || "").length) && form && form.photoGeoFromUtm) {
            var g = form.photoGeoFromUtm(m)
            if (g) { m.latitude = g.latitude.toFixed(7); m.longitude = g.longitude.toFixed(7) }
        }
        return m
    }
    // Instantánea coherente del estado vigente: los datos de la ficha (código,
    // proyecto corto, UTM) y de la captura (fecha/hora, altitud) mandan; lo
    // guardado solo completa claves que la ficha no aporta (p. ej. lat/lon).
    readonly property var captureOwnedKeys: ["date", "time", "time_source", "altitude", "altitude_source", "project", "calicata"]
    function currentMetadata(stored) {
        var merged = freshMetadata()
        stored = stored || {}
        for (var key in stored) {
            if (captureOwnedKeys.indexOf(key) >= 0) continue
            var value = stored[key]
            if (String(merged[key] || "").trim().length) continue
            if (value !== undefined && value !== null && String(value).trim().length) merged[key] = value
        }
        merged.category = slotTitle
        return merged
    }
    function normalized(e) {
        var n = clone(e)
        n.withMetadata = n.withMetadata !== false
        var f = n.fields || {}
        for (var i = 0; i < photoFields.length; ++i)
            if (f[photoFields[i][0]] === undefined) f[photoFields[i][0]] = photoFields[i][2]
        n.fields = f
        n.metadata = n.metadata || freshMetadata()
        var s = n.style || {}
        for (var k in defaultStyle) if (s[k] === undefined) s[k] = defaultStyle[k]
        s.sizePct = Math.max(2, Math.min(10, Number(s.sizePct)))
        s.offsetXPct = Math.max(-45, Math.min(45, Number(s.offsetXPct)))
        s.offsetYPct = Math.max(-45, Math.min(45, Number(s.offsetYPct)))
        s.logoScalePct = Math.max(40, Math.min(300, Number(s.logoScalePct)))
        s.logoOpacityPct = Math.max(10, Math.min(100, Number(s.logoOpacityPct)))
        s.logoMarginPct = Math.max(0, Math.min(15, Number(s.logoMarginPct)))
        n.style = s
        n.logo = n.logo || { enabled: false, source: "PROJECT" }
        var im = n.image || {}
        for (var j in defaultImage) if (im[j] === undefined) im[j] = defaultImage[j]
        im.rotation = ((Math.round(Number(im.rotation) / 90) * 90) % 360 + 360) % 360
        im.angle = Math.max(-45, Math.min(45, Number(im.angle) || 0))
        var adjust = ["exposure", "brightness", "contrast", "highlights", "shadows", "warmth", "tint", "saturation", "clarity", "vignette"]
        for (var a = 0; a < adjust.length; ++a) im[adjust[a]] = Math.max(-100, Math.min(100, Number(im[adjust[a]]) || 0))
        im.sharpness = Math.max(0, Math.min(100, Number(im.sharpness) || 0))
        n.image = im
        var w = n.watermark || {}
        if (w.enabled === undefined) w.enabled = false
        if (w.text === undefined) w.text = String((n.metadata || {}).project || "")
        if (w.opacityPct === undefined) w.opacityPct = 30
        if (w.sizePct === undefined) w.sizePct = 6
        if (w.anchor === undefined) w.anchor = "middle-center"
        if (w.tiled === undefined) w.tiled = false
        n.watermark = w
        n.annotations = n.annotations || []
        return n
    }

    // originPoint: centro de la tarjeta de origen en coordenadas de escena (opcional).
    function openFor(document, index, title, startTab, originPoint) {
        doc = document
        slotIndex = index
        slotTitle = title
        slot = doc ? doc.photoSlot(index) : ({})
        var start = clone(slot.edit)
        // Autofill: la instantánea guardada con la foto (fecha/hora de captura) manda;
        // lo que esté vacío se completa con la ficha vigente (p. ej. lat/lon desde UTM).
        start.metadata = editor.currentMetadata(start.metadata)
        start.metadata.category = title
        edit = normalized(start)
        undoStack = []
        redoStack = []
        statusText = ""
        tab = startTab !== undefined && startTab >= 0 && startTab < tabs.length ? startTab : 0
        shownTab = tab
        comparePos = 0.5
        zoom = 1
        panX = 0
        panY = 0
        mode = ""
        previewUrl = ""
        shownPreviewUrl = ""
        cloudVersions = []
        dragTarget = ""
        activeGesture = null
        lastUndoGesture = null
        if (doc && form && form.photoResourcesBase) doc.setResourcesBase(form.photoResourcesBase())
        refreshLogos()
        var host = editor.parent
        var valid = !!host && !!originPoint && isFinite(originPoint.x) && isFinite(originPoint.y)
        originDX = valid ? originPoint.x - host.width / 2 : 0
        originDY = valid ? originPoint.y - host.height / 2 : editor.dp(24)
        if (cloud) cloud.loadPhotoHistory(doc, index)
        open()
        requestPreview()
    }

    // Toda modificación pasa por aquí: una entrada de deshacer por cambio (un gesto
    // continuo —deslizar, arrastrar, escribir— produce una sola entrada).
    function change(mutator) {
        var before = JSON.stringify(edit)
        var next = clone(edit)
        mutator(next)
        next = normalized(next)
        if (JSON.stringify(next) === before) return
        if (!activeGesture || activeGesture !== lastUndoGesture) {
            undoStack = undoStack.concat([before]).slice(-60)
            redoStack = []
        }
        lastUndoGesture = activeGesture
        edit = next
    }
    function beginGesture() { activeGesture = ({}) }
    function endGesture() { activeGesture = null }
    function undo() {
        if (!undoStack.length) return
        lastUndoGesture = null
        redoStack = redoStack.concat([JSON.stringify(edit)])
        edit = JSON.parse(undoStack[undoStack.length - 1])
        undoStack = undoStack.slice(0, -1)
    }
    function redo() {
        if (!redoStack.length) return
        lastUndoGesture = null
        undoStack = undoStack.concat([JSON.stringify(edit)])
        edit = JSON.parse(redoStack[redoStack.length - 1])
        redoStack = redoStack.slice(0, -1)
    }

    // Logos disponibles (miniaturas + disponibilidad). Sin logo: "" y el control lo dice.
    function refreshLogos() {
        logoProjectUrl = doc ? String(doc.photoLogoUrl("PROJECT") || "") : ""
        logoEntityUrl = doc ? String(doc.photoLogoUrl("ENTITY") || "") : ""
    }
    function logoAvailable(source) { return logoUrl(source).length > 0 }
    function setLogoEnabled(on) {
        change(function(n) {
            n.logo.enabled = on
            // Si la fuente elegida no tiene logo, usa la que sí lo tiene (nunca un toggle vacío).
            if (on && !editor.logoAvailable(n.logo.source))
                n.logo.source = editor.logoAvailable("PROJECT") ? "PROJECT" : "ENTITY"
        })
    }
    // Posición directa: el centro del elemento sigue al dedo (normalizado sobre la foto final).
    function placeDragged(nx, ny) {
        var p = [Math.round(Math.max(0, Math.min(1, nx)) * 1000) / 1000, Math.round(Math.max(0, Math.min(1, ny)) * 1000) / 1000]
        var target = dragTarget
        change(function(n) {
            if (target === "logo") n.style.logoPos = p
            else if (target === "watermark") n.watermark.pos = p
            else if (target === "label") n.style.labelPos = p
        })
    }
    function toggleDrag(target) {
        dragTarget = dragTarget === target ? "" : target
        if (dragTarget.length) { zoom = 1; panX = 0; panY = 0 }
    }
    function setTab(i) {
        if (i === tab) return
        dragTarget = ""
        tab = i
        tabSwitch.restart()
    }
    SequentialAnimation {
        id: tabSwitch
        NumberAnimation { target: panel; property: "opacity"; to: 0; duration: editor.motion * 0.45; easing.type: Easing.InQuad }
        ScriptAction { script: { editor.shownTab = editor.tab; panelFlick.contentY = 0 } }
        NumberAnimation { target: panel; property: "opacity"; to: 1; duration: editor.motion; easing.type: Easing.OutCubic }
    }

    // ---- teclado: el campo activo queda visible (la ventana se redimensiona con el IME)
    property var fieldFocusTarget: null   // EdTextField activo (propiedad editing)
    function ensureFieldVisible(item) {
        fieldFocusTarget = item
        ensureVisibleTimer.restart()
    }
    function _scrollToField() {
        var it = fieldFocusTarget
        if (!it || !it.editing || !panelFlick.visible) return
        var p = it.mapToItem(panel, 0, 0)
        var top = panel.y + p.y
        var maxY = Math.max(0, panelFlick.contentHeight - panelFlick.height)
        scrollToField.to = Math.max(0, Math.min(maxY, top - Math.max(editor.dp(8), (panelFlick.height - it.height) * 0.3)))
        scrollToField.restart()
    }
    // Espera a que termine el redimensionado por el teclado antes de desplazar.
    Timer { id: ensureVisibleTimer; interval: 280; repeat: false; onTriggered: editor._scrollToField() }
    onHeightChanged: if (fieldFocusTarget && fieldFocusTarget.editing) ensureVisibleTimer.restart()
    NumberAnimation { id: scrollToField; target: panelFlick; property: "contentY"; duration: 200; easing.type: Easing.OutCubic }
    readonly property bool typing: imeOpen && !!fieldFocusTarget && fieldFocusTarget.editing

    // ---- zoom / desplazamiento de la vista previa
    function setZoom(z) {
        zoom = Math.max(1, Math.min(4, z))
        clampPan()
    }
    function clampPan() {
        var mx = (zoom - 1) * previewBox.width / 2, my = (zoom - 1) * previewBox.height / 2
        panX = Math.max(-mx, Math.min(mx, panX))
        panY = Math.max(-my, Math.min(my, panY))
    }
    function resetView() { zoom = 1; panX = 0; panY = 0 }

    // ---- vista previa real (throttle en QML + coalescencia en C++); nunca crea versiones.
    // Throttle (no debounce): durante un gesto continuo la vista previa se actualiza cada
    // ~140 ms en lugar de esperar a que el dedo se detenga.
    onEditChanged: if (editor.visible && editor.mode === "" && !previewDebounce.running) previewDebounce.start()
    Timer { id: previewDebounce; interval: 140; repeat: false; onTriggered: editor.requestPreview() }
    function requestPreview() {
        if (!doc) return
        previewBusy = true
        previewToken = doc.requestPhotoPreview(slotIndex, edit, "result")
        if (!previewToken) previewBusy = false
    }
    // Base de una herramienta: la imagen en la etapa previa a esa herramienta.
    function requestBase(stage) {
        if (!doc) return
        baseUrl = ""
        baseToken = doc.requestPhotoPreview(slotIndex, edit, stage)
    }
    Connections {
        target: editor.doc
        ignoreUnknownSignals: true
        function onPhotoPreviewReady(idx, token, url, error) {
            if (idx !== editor.slotIndex) return
            var ok = String(url).length > 0
            if (token === editor.previewToken) {
                editor.previewBusy = false
                if (ok) editor.previewUrl = url
                // Con vista previa válida, "error" es un aviso (p. ej. logo no legible).
                editor.previewWarning = String(error || "")
            } else if (token === editor.baseToken) {
                if (ok) editor.baseUrl = url
                else if (error) editor.statusText = error
            }
        }
    }

    // ---- herramientas interactivas
    function beginCrop() {
        var c = editor.img.crop
        cropDraft = c ? { x: c.x, y: c.y, w: c.w, h: c.h } : { x: 0, y: 0, w: 1, h: 1 }
        cropAspect = 0
        resetView()
        dragTarget = ""
        mode = "crop"
        requestBase("geometry")
    }
    function applyCropAspect(ratio) {
        cropAspect = ratio
        if (ratio <= 0) return
        var r = baseFrame.imgRect
        if (r.width <= 0 || r.height <= 0) return
        var target = ratio * r.height / r.width   // relación ancho/alto en coordenadas normalizadas
        var w = 1, h = 1
        if (target > 1) h = 1 / target; else w = target
        cropDraft = { x: (1 - w) / 2, y: (1 - h) / 2, w: w, h: h }
    }
    function commitCrop() {
        var c = cropDraft
        var full = c.x <= 0.001 && c.y <= 0.001 && c.w >= 0.999 && c.h >= 0.999
        mode = ""
        change(function(n) { if (full) delete n.image.crop; else n.image.crop = c; n.image.aspect = "free" })
        requestPreview()
    }
    function beginPerspective() {
        var p = editor.img.perspective
        perspDraft = p && p.length === 4 ? clone(p) : [[0, 0], [1, 0], [1, 1], [0, 1]]
        resetView()
        dragTarget = ""
        mode = "perspective"
        requestBase("source")
    }
    function commitPerspective() {
        var p = perspDraft
        var identity = p[0][0] < 0.002 && p[0][1] < 0.002 && p[1][0] > 0.998 && p[1][1] < 0.002
                       && p[2][0] > 0.998 && p[2][1] > 0.998 && p[3][0] < 0.002 && p[3][1] > 0.998
        mode = ""
        change(function(n) { if (identity) delete n.image.perspective; else n.image.perspective = p })
        requestPreview()
    }
    function beginDraw() {
        strokes = clone(edit.annotations || [])
        strokeUndo = []
        strokeRedo = []
        liveStroke = null
        drawTool = "pen"
        dragTarget = ""
        mode = "draw"
        requestBase("annotate")
    }
    function commitDraw() {
        var s = strokes
        mode = ""
        change(function(n) { n.annotations = s })
        requestPreview()
    }
    function cancelTool() {
        mode = ""
        liveStroke = null
        requestPreview()
    }
    function pushStrokes(next) {
        strokeUndo = strokeUndo.concat([JSON.stringify(strokes)]).slice(-60)
        strokeRedo = []
        strokes = next
    }
    function undoStroke() {
        if (!strokeUndo.length) return
        strokeRedo = strokeRedo.concat([JSON.stringify(strokes)])
        strokes = JSON.parse(strokeUndo[strokeUndo.length - 1])
        strokeUndo = strokeUndo.slice(0, -1)
    }
    function redoStroke() {
        if (!strokeRedo.length) return
        strokeUndo = strokeUndo.concat([JSON.stringify(strokes)])
        strokes = JSON.parse(strokeRedo[strokeRedo.length - 1])
        strokeRedo = strokeRedo.slice(0, -1)
    }
    // Goma: elimina el trazo completo bajo el dedo (radio fijo en pantalla, compensa zoom).
    function eraseAt(x, y) {
        var radius = 0.03 / zoom
        var keep = [], removed = false
        for (var i = 0; i < strokes.length; ++i) {
            var hit = false, pts = strokes[i].points
            for (var j = 0; j < pts.length && !hit; ++j)
                hit = Math.abs(pts[j][0] - x) < radius && Math.abs(pts[j][1] - y) < radius
            if (hit) removed = true; else keep.push(strokes[i])
        }
        if (removed) pushStrokes(keep)
    }

    // Curva tonal (misma interpolación monótona Fritsch–Carlson que C++ photoCurveLut).
    function curvePoints() {
        var c = editor.img.curve
        return c && c.length >= 2 ? c : [[0, 0], [1, 1]]
    }
    function curveSample(points, x) {
        var p = points.slice().sort(function(a, b) { return a[0] - b[0] })
        var n = p.length
        if (n < 2) return x
        var dx = [], m = [], t = []
        for (var i = 0; i < n - 1; ++i) { dx.push(Math.max(1e-4, p[i + 1][0] - p[i][0])); m.push((p[i + 1][1] - p[i][1]) / dx[i]) }
        t.push(m[0])
        for (i = 1; i < n - 1; ++i) t.push(m[i - 1] * m[i] <= 0 ? 0 : (m[i - 1] + m[i]) / 2)
        t.push(m[n - 2])
        for (i = 0; i < n - 1; ++i) {
            if (m[i] === 0) { t[i] = 0; t[i + 1] = 0; continue }
            var a = t[i] / m[i], b = t[i + 1] / m[i], s = a * a + b * b
            if (s > 9) { var tau = 3 / Math.sqrt(s); t[i] = tau * a * m[i]; t[i + 1] = tau * b * m[i] }
        }
        if (x <= p[0][0]) return p[0][1]
        if (x >= p[n - 1][0]) return p[n - 1][1]
        var k = 0
        while (k < n - 2 && x > p[k + 1][0]) ++k
        var h = dx[k], u = Math.max(0, Math.min(1, (x - p[k][0]) / h))
        var y = (2 * u * u * u - 3 * u * u + 1) * p[k][1] + (u * u * u - 2 * u * u + u) * h * t[k]
              + (-2 * u * u * u + 3 * u * u) * p[k + 1][1] + (u * u * u - u * u) * h * t[k + 1]
        return Math.max(0, Math.min(1, y))
    }
    function setCurve(points) {
        var pts = points.slice().sort(function(a, b) { return a[0] - b[0] })
        var identity = pts.length === 2 && pts[0][0] === 0 && pts[0][1] === 0 && pts[1][0] === 1 && pts[1][1] === 1
        change(function(n) { if (identity) delete n.image.curve; else n.image.curve = pts })
    }

    function logoUrl(source) {
        return source === "ENTITY" ? logoEntityUrl : logoProjectUrl
    }

    // Ciclo de vida trazable: BEGIN → PHASE RENDER_OK|RENDER_ERROR → END (siempre uno).
    function publish() {
        if (!doc || rendering) return   // doble toque: una sola operación por ficha
        if (edit.logo && edit.logo.enabled && !logoAvailable(edit.logo.source)) {
            statusText = "La fuente de logo elegida no tiene logo disponible. Elige otra o desactiva el logo."
            return
        }
        rendering = true
        statusText = ""
        renderStartedAt = Date.now()
        // Snapshot del job: metadatos de la ficha/captura vigentes AL INICIAR
        // (un cambio de código o proyecto no deja datos viejos en el rótulo).
        var job = clone(edit)
        job.metadata = currentMetadata(job.metadata)
        edit = normalized(job)
        photoOperation = { id: "PHOTO_RENDER-" + Date.now(), kind: "PHOTO_RENDER", title: "Generando fotografía…",
                           detail: "Aplicando imagen, datos, composición, anotaciones y logotipo", blocking: true }
        console.info("INGE_CALICATA_OPERATION_BEGIN kind=PHOTO_RENDER id=" + photoOperation.id)
        photoRenderWatchdog.restart()
        var started = false
        try {
            started = doc.renderDerivedPhoto(slotIndex, edit)
        } catch (failure) {
            console.warn("INGE_PHOTO_COMPOSE_FAILED reason=" + failure)
        }
        if (!started) {
            photoRenderWatchdog.stop()
            _logRenderPhase("RENDER_ERROR", doc ? doc.errorString : "sin documento")
            _photoResult("ERROR", "No se pudo generar la fotografía",
                         (doc && doc.errorString ? doc.errorString + " " : "") + "La original se conserva sin cambios.", false)
        }
    }
    function _logRenderPhase(phase, error) {
        console.info("INGE_CALICATA_OPERATION_PHASE kind=PHOTO_RENDER phase=" + phase
                     + " elapsedMs=" + Math.round(Date.now() - renderStartedAt)
                     + (error ? " error=" + String(error).replace(/\s+/g, "_") : ""))
    }
    // Un render que no responde nunca deja el editor bloqueado.
    Timer {
        id: photoRenderWatchdog
        interval: 60000
        repeat: false
        onTriggered: if (editor.photoOperation && editor.photoOperation.kind === "PHOTO_RENDER" && !editor.photoOperation.result) {
                         editor._logRenderPhase("RENDER_ERROR", "timeout")
                         editor._photoResult("ERROR", "La generación no respondió",
                                             "La configuración se conserva; puedes volver a intentarlo.", false)
                     }
    }
    // Borrador: guarda la receta en la ficha (sin render, sin versión, sin envío).
    function saveDraft() {
        if (!doc || rendering) return
        if (doc.savePhotoEditDraft(slotIndex, edit)) {
            undoStack = []
            redoStack = []
            statusText = "Borrador guardado en la ficha. No se publicó ninguna versión."
        } else {
            statusText = "No se pudo guardar el borrador."
        }
    }

    Connections {
        target: editor.doc
        ignoreUnknownSignals: true
        // Los logos de la ficha pueden cambiar (Perfil / nube): miniaturas y disponibilidad al día.
        function onDataChanged() { if (editor.visible) editor.refreshLogos() }
        // La ficha se cerró/reemplazó durante el render: el job termina en ERROR.
        function onClosedChanged() {
            if (!editor.rendering || !editor.doc || editor.doc.closed !== true) return
            photoRenderWatchdog.stop()
            editor._logRenderPhase("RENDER_ERROR", "document_closed")
            editor._photoResult("ERROR", "No se pudo generar la fotografía",
                                "La ficha cambió durante la generación. Vuelve a intentarlo.", false)
        }
        function onDerivedPhotoReady(idx, url, localVersionId, error) {
            if (idx !== editor.slotIndex || !editor.rendering) return
            photoRenderWatchdog.stop()
            if (error && error.length) {
                editor._logRenderPhase("RENDER_ERROR", error)
                editor._photoResult("ERROR", "No se pudo generar la fotografía",
                                    error + " La original y la configuración se conservan; puedes reintentar.", false)
                return
            }
            editor._logRenderPhase("RENDER_OK", "")
            editor.slot = editor.doc.photoSlot(editor.slotIndex)
            // La versión ya está guardada en la ficha (derivada + receta). La publicación es
            // del outbox de Media (asíncrona, con reintento): el editor NO espera a Storage.
            // El estado real (Publicando / Pendiente / Error de envío + Reintentar) se ve en
            // la tarjeta de Fotos. La versión activa en la nube solo cambia al confirmarse.
            var entryId = editor.cloud ? editor.cloud.enqueuePhotoSync(editor.doc, editor.slotIndex) : ""
            var online = !!entryId && String(editor.doc.header.remoteCalicataId || "").length > 0
            if (editor.form)
                editor.form.photoFeedbackText = online
                        ? "Versión guardada en el dispositivo · publicando en segundo plano"
                        : "Versión guardada en el dispositivo · se publicará cuando haya conexión"
            console.info("INGE_CALICATA_OPERATION_END kind=PHOTO_RENDER id=" + (editor.photoOperation ? editor.photoOperation.id : "")
                         + " result=LOCAL_OK publish=" + (online ? "QUEUED" : "DEFERRED")
                         + " elapsedMs=" + Math.round(Date.now() - (editor.renderStartedAt || Date.now())))
            editor.photoOperation = null
            editor.rendering = false
            editor.close()
        }
    }
    // Restaurar una versión de la nube ("Usar") sí es una operación en primer plano:
    // nunca queda bloqueada más de 25 s (la descarga sigue y se confirma en Fotos).
    Timer {
        id: photoPublishTimeout
        interval: 25000
        repeat: false
        onTriggered: if (editor.photoOperation && editor.photoOperation.kind === "MEDIA_RESTORE" && !editor.photoOperation.result)
                         editor._photoResult("INFO", "Restauración en curso",
                                             "La versión se confirmará en Fotos cuando termine la descarga.", true)
    }
    Connections {
        target: editor.cloud
        ignoreUnknownSignals: true
        function onMediaSyncChanged(localId, idx, state, message, changes) {
            var op = editor.photoOperation
            if (!op || op.result || !editor.doc || localId !== editor.doc.instanceId || idx !== editor.slotIndex) return
            if (op.kind !== "MEDIA_RESTORE") return
            if (state === "SYNCING") return
            photoPublishTimeout.stop()
            editor.slot = editor.doc.photoSlot(editor.slotIndex)
            if (state === "SYNCED")
                editor._photoResult("SUCCESS", op.kind === "MEDIA_RESTORE" ? "Versión restaurada" : "Fotografía publicada",
                                    "La versión quedó en uso en la nube.", false)
            else if (state === "PENDING")
                editor._photoResult("INFO", "Guardada en el dispositivo", "Se publicará cuando vuelva la conexión.", false)
            else if (state === "CONFLICT")
                editor._photoResult("ERROR", "Otra versión en la nube", "Otro dispositivo publicó esta categoría. Elige en Fotos cuál conservar.", false)
            else {
                // FAILED / REMOTE_FAILED: la causa real del servidor (fase registrada en
                // INGE_CALICATA_MEDIA_FAILED), no un genérico. La derivada y su versión local
                // siguen en la ficha y "Reintentar envío" queda disponible en Fotos.
                var cause = String(message || "").trim()
                editor._photoResult("ERROR", op.kind === "MEDIA_RESTORE" ? "No se pudo restaurar" : "No se pudo publicar la fotografía",
                                    (cause.length ? cause + "\n" : "")
                                    + "La versión local se conserva; puedes reintentar desde Fotos.", false)
            }
        }
        function onPhotoHistoryLoaded(localId, idx, versions) {
            if (editor.doc && localId === editor.doc.instanceId && idx === editor.slotIndex)
                editor.cloudVersions = versions
        }
    }

    parent: Overlay.overlay
    x: offsetX
    y: offsetY
    width: parent ? parent.width : 400
    height: parent ? parent.height : 800
    modal: true
    focus: true
    padding: 0
    closePolicy: Popup.CloseOnEscape
    background: Rectangle {
        // Fondo que refractan los controles Liquid Glass del editor.
        objectName: "calicataGlassBackdrop"
        color: editor.cPage
        gradient: Gradient {
            GradientStop { position: 0.0; color: editor.dark ? "#18202B" : "#EEF4FF" }
            GradientStop { position: 1.0; color: editor.dark ? "#11161D" : "#F8FAFD" }
        }
    }
    // Se expande desde la tarjeta tocada y vuelve hacia ella al cerrar.
    enter: Transition {
        ParallelAnimation {
            NumberAnimation { property: "opacity"; from: 0; to: 1; duration: editor.motion + 60; easing.type: Easing.OutCubic }
            NumberAnimation { property: "scale"; from: 0.6; to: 1; duration: editor.motion + 220; easing.type: Easing.OutQuint }
            NumberAnimation { property: "offsetX"; from: editor.originDX; to: 0; duration: editor.motion + 220; easing.type: Easing.OutQuint }
            NumberAnimation { property: "offsetY"; from: editor.originDY; to: 0; duration: editor.motion + 220; easing.type: Easing.OutQuint }
        }
    }
    exit: Transition {
        ParallelAnimation {
            NumberAnimation { property: "opacity"; from: 1; to: 0; duration: editor.motion + 60; easing.type: Easing.InCubic }
            NumberAnimation { property: "scale"; from: 1; to: 0.6; duration: editor.motion + 80; easing.type: Easing.InCubic }
            NumberAnimation { property: "offsetX"; from: 0; to: editor.originDX; duration: editor.motion + 80; easing.type: Easing.InCubic }
            NumberAnimation { property: "offsetY"; from: 0; to: editor.originDY; duration: editor.motion + 80; easing.type: Easing.InCubic }
        }
    }
    onClosed: {
        offsetX = 0
        offsetY = 0
        mode = ""
        dragTarget = ""
        liveStroke = null
        previewDebounce.stop()
        editor.inputMethod.hide()
    }

    // ---------------------------------------------------------------- controles propios (sin Qt genérico)
    // Botón de icono: solo iconos vectoriales del catálogo (sin glifos de fuente, que en
    // Android pueden no existir y dibujarse como cajas vacías).
    component EdIconButton: Rectangle {
        id: eib
        property string icon: ""
        property bool mirror: false
        property bool on: false
        signal clicked()
        implicitWidth: editor.dp(44); implicitHeight: editor.dp(44)
        radius: width / 2
        color: "transparent"
        opacity: enabled ? 1 : 0.35
        CalicataSurface { dark: editor.dark; accent: editor.cBlue; anchors.fill: parent; radius: eib.radius; tone: eib.on ? "tinted" : "glass"; selected: eib.on; pressed: eibTap.pressed }
        scale: eibTap.pressed ? 0.92 : 1

        Components.FlowIcon {
            anchors.centerIn: parent
            width: editor.dp(22); height: width
            name: eib.icon
            mirror: eib.mirror
            flow: editor.form ? editor.form.flow : null
            tintColor: eib.on ? editor.cBlue : editor.cText
            activeTintColor: editor.cBlue
            inactiveOpacity: 1
        }
        TapHandler { id: eibTap; enabled: eib.enabled; onTapped: eib.clicked() }
        Accessible.role: Accessible.Button
        Accessible.onPressAction: eib.clicked()
    }
    component EdPill: Rectangle {
        id: pill
        property string text: ""
        property bool selected: false
        property bool primary: false
        signal clicked()
        Layout.fillWidth: true
        implicitHeight: editor.dp(44)
        implicitWidth: pillText.implicitWidth + editor.dp(24)
        radius: editor.dp(12)
        color: "transparent"
        opacity: enabled ? 1 : 0.4
        scale: pillTap.pressed ? 0.97 : 1

        CalicataSurface {
            dark: editor.dark; accent: editor.cBlue
            anchors.fill: parent
            radius: pill.radius
            tone: pill.primary ? "primary" : pill.selected ? "tinted" : "glass"
            selected: pill.selected && !pill.primary
            pressed: pillTap.pressed
        }
        Text {
            id: pillText
            anchors.centerIn: parent
            text: pill.text
            color: pill.primary ? "#FFFFFF" : pill.selected ? editor.cBlue : editor.cText
            font.pixelSize: editor.dp(13)
            font.bold: pill.selected || pill.primary
        }
        TapHandler { id: pillTap; enabled: pill.enabled; onTapped: pill.clicked() }
        Accessible.role: Accessible.Button
        Accessible.name: pill.text
    }
    component EdSwitch: Rectangle {
        id: sw
        property bool checked: false
        signal toggled(bool value)
        implicitWidth: editor.dp(44); implicitHeight: editor.dp(26)
        radius: height / 2
        color: "transparent"
        opacity: enabled ? 1 : 0.4
        CalicataSurface { dark: editor.dark; accent: editor.cBlue; anchors.fill: parent; radius: sw.radius; tone: sw.checked ? "primary" : "glass" }
        Rectangle {
            width: parent.height - editor.dp(6); height: width; radius: width / 2
            y: editor.dp(3)
            x: sw.checked ? parent.width - width - editor.dp(3) : editor.dp(3)
            color: "#FFFFFF"

        }
        TapHandler { enabled: sw.enabled; margin: editor.dp(10); onTapped: sw.toggled(!sw.checked) }
        Accessible.role: Accessible.CheckBox
        Accessible.checked: sw.checked
    }
    component EdRow: RowLayout {
        id: row
        property string label: ""
        property string detail: ""
        default property alias trailing: rowSlot.data
        Layout.fillWidth: true
        Layout.minimumHeight: editor.dp(40)
        spacing: editor.dp(10)
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 0
            Text { Layout.fillWidth: true; text: row.label; color: editor.cText; font.pixelSize: editor.dp(13); elide: Text.ElideRight }
            Text { Layout.fillWidth: true; visible: row.detail.length > 0; text: row.detail; color: editor.cMuted; font.pixelSize: editor.dp(11); elide: Text.ElideRight }
        }
        RowLayout { id: rowSlot; spacing: editor.dp(6) }
    }
    // Deslizador: aplica en vivo mientras se arrastra (vista previa C++ con throttle y
    // una sola entrada de deshacer por gesto) y ofrece restablecer su valor por defecto.
    component EdSlider: Item {
        id: sl
        property string label: ""
        property real from: 0
        property real to: 100
        property real stepSize: 1
        property real value: 0
        property real resetValue: 0
        property string suffix: ""
        property real _live: value
        property bool _dragging: false
        signal committed(real v)
        onValueChanged: if (!_dragging) _live = value
        Layout.fillWidth: true
        implicitHeight: editor.dp(sl.label.length ? 58 : 40)
        opacity: enabled ? 1 : 0.4
        function _at(x) {
            var t = Math.max(0, Math.min(1, x / Math.max(1, track.width)))
            var v = from + t * (to - from)
            return Math.round(v / stepSize) * stepSize
        }
        Text { visible: sl.label.length > 0; text: sl.label; color: editor.cText; font.pixelSize: editor.dp(13) }
        Row {
            anchors.right: parent.right
            height: editor.dp(24)
            spacing: editor.dp(4)
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: (Math.round(sl._live * 10) / 10) + sl.suffix
                color: editor.cMuted
                font.pixelSize: editor.dp(12)
            }
            Item {
                // Restablecer solo este control (icono vectorial; área táctil de 36 dp).
                width: editor.dp(24); height: editor.dp(24)
                visible: Math.abs(sl.value - sl.resetValue) > 0.0001
                Components.FlowIcon {
                    anchors.centerIn: parent
                    width: editor.dp(16); height: width
                    name: "history.restore"
                    flow: editor.form ? editor.form.flow : null
                    tintColor: editor.cBlue
                    inactiveOpacity: 1
                }
                TapHandler {
                    enabled: sl.enabled
                    margin: editor.dp(8)
                    onTapped: { sl._live = sl.resetValue; sl.committed(sl.resetValue) }
                }
                Accessible.role: Accessible.Button
                Accessible.name: "Restablecer " + sl.label
            }
        }
        Rectangle {
            id: track
            anchors.left: parent.left; anchors.right: parent.right
            anchors.bottom: parent.bottom; anchors.bottomMargin: editor.dp(12)
            height: editor.dp(4); radius: 2
            color: editor.cBorder
            readonly property real t: (sl._live - sl.from) / Math.max(0.0001, sl.to - sl.from)
            Rectangle { width: parent.width * parent.t; height: parent.height; radius: 2; color: editor.cBlue }
            Rectangle {
                width: editor.dp(20); height: width; radius: width / 2
                anchors.verticalCenter: parent.verticalCenter
                x: parent.width * parent.t - width / 2
                color: "#FFFFFF"
                border.width: 2; border.color: editor.cBlue
                scale: sl._dragging ? 1.18 : 1

            }
            MouseArea {
                anchors.fill: parent
                anchors.topMargin: -editor.dp(16); anchors.bottomMargin: -editor.dp(16)
                enabled: sl.enabled
                preventStealing: true
                function _apply(x) {
                    var v = sl._at(x)
                    if (v === sl._live) return
                    sl._live = v
                    sl.committed(v)
                }
                onPressed: function(m) { editor.beginGesture(); sl._dragging = true; _apply(m.x) }
                onPositionChanged: function(m) { if (pressed) _apply(m.x) }
                onReleased: { sl._dragging = false; sl.committed(sl._live); editor.endGesture() }
                onCanceled: { sl._dragging = false; sl._live = sl.value; editor.endGesture() }
            }
        }
        Accessible.role: Accessible.Slider
        Accessible.name: sl.label
    }
    // Posición 3x3 a lo ancho del panel: celdas de 48 dp de alto (objetivo táctil cómodo).
    // "free" = el elemento se colocó arrastrándolo en la foto (ninguna celda activa).
    component EdAnchorGrid: GridLayout {
        id: grid
        property string current: ""
        property bool free: false
        signal picked(string anchor)
        Layout.fillWidth: true
        columns: 3
        columnSpacing: editor.dp(6)
        rowSpacing: editor.dp(6)
        Repeater {
            model: editor.anchorIds
            delegate: Rectangle {
                id: anchorCell
                required property string modelData
                readonly property bool active: !grid.free && grid.current === anchorCell.modelData
                readonly property var parts: anchorCell.modelData.split("-")
                Layout.fillWidth: true
                Layout.preferredHeight: editor.dp(48)
                radius: editor.dp(10)
                color: "transparent"
                scale: cellTap.pressed ? 0.96 : 1

                CalicataSurface {
                    dark: editor.dark; accent: editor.cBlue
                    anchors.fill: parent
                    radius: anchorCell.radius
                    tone: anchorCell.active ? "tinted" : "glass"
                    selected: anchorCell.active
                    pressed: cellTap.pressed
                }
                // Marcador ubicado donde quedará el elemento dentro de la celda.
                Rectangle {
                    width: editor.dp(anchorCell.active ? 14 : 8); height: width; radius: width / 2
                    x: anchorCell.parts[1] === "left" ? editor.dp(10)
                       : anchorCell.parts[1] === "center" ? (parent.width - width) / 2 : parent.width - width - editor.dp(10)
                    y: anchorCell.parts[0] === "top" ? editor.dp(8)
                       : anchorCell.parts[0] === "middle" ? (parent.height - height) / 2 : parent.height - height - editor.dp(8)
                    color: anchorCell.active ? editor.cBlue : editor.cMuted

                }
                TapHandler { id: cellTap; onTapped: grid.picked(anchorCell.modelData) }
                Accessible.role: Accessible.RadioButton
                Accessible.checked: anchorCell.active
                Accessible.name: "Posición " + anchorCell.modelData
            }
        }
    }
    component EdSection: Rectangle {
        id: sec
        property string title: ""
        default property alias body: secBody.data
        Layout.fillWidth: true
        implicitHeight: secBody.implicitHeight + editor.dp(sec.title.length ? 44 : 20)
        radius: editor.dp(16)
        color: "transparent"
        CalicataSurface { dark: editor.dark; accent: editor.cBlue; anchors.fill: parent; radius: sec.radius; level: "card" }
        Text {
            visible: sec.title.length > 0
            x: editor.dp(14); y: editor.dp(12)
            text: sec.title
            color: editor.cText
            font.bold: true
            font.pixelSize: editor.dp(13)
        }
        ColumnLayout {
            id: secBody
            x: editor.dp(14)
            y: editor.dp(sec.title.length ? 36 : 10)
            width: parent.width - editor.dp(28)
            spacing: editor.dp(6)
        }
    }
    // Fuente del logo con su miniatura real (la misma imagen que se imprime en la foto).
    component EdLogoChoice: Rectangle {
        id: choice
        property string source: ""
        property string title: ""
        readonly property string url: editor.logoUrl(choice.source)
        readonly property bool available: choice.url.length > 0
        readonly property bool selected: !!editor.edit.logo && editor.edit.logo.source === choice.source
        readonly property bool inUse: choice.selected && !!editor.edit.logo.enabled
        Layout.fillWidth: true
        implicitHeight: editor.dp(112)
        radius: editor.dp(12)
        color: "transparent"
        opacity: choice.available ? 1 : 0.6
        scale: choiceTap.pressed ? 0.97 : 1

        CalicataSurface {
            dark: editor.dark; accent: editor.cBlue
            anchors.fill: parent
            radius: choice.radius
            tone: choice.inUse ? "tinted" : "glass"
            selected: choice.inUse
            pressed: choiceTap.pressed
        }
        ColumnLayout {
            anchors.fill: parent
            anchors.margins: editor.dp(8)
            spacing: editor.dp(6)
            Rectangle {
                Layout.fillWidth: true
                Layout.fillHeight: true
                radius: editor.dp(8)
                color: "#F4F6F8"
                clip: true
                Image {
                    anchors.fill: parent
                    anchors.margins: editor.dp(6)
                    visible: choice.available
                    source: choice.url
                    fillMode: Image.PreserveAspectFit
                    asynchronous: true
                    sourceSize: Qt.size(240, 120)
                }
                Text {
                    anchors.centerIn: parent
                    width: parent.width - editor.dp(12)
                    visible: !choice.available
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.WordWrap
                    text: "Sin logo disponible"
                    color: "#6B7280"
                    font.pixelSize: editor.dp(11)
                }
            }
            Text {
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignHCenter
                text: choice.title
                color: choice.inUse ? editor.cBlue : editor.cText
                font.bold: choice.inUse
                font.pixelSize: editor.dp(12)
                elide: Text.ElideRight
            }
        }
        // Elegir una fuente con logo lo activa directamente.
        TapHandler {
            id: choiceTap
            enabled: choice.available
            onTapped: editor.change(function(n) { n.logo.source = choice.source; n.logo.enabled = true })
        }
        Accessible.role: Accessible.RadioButton
        Accessible.checked: choice.inUse
        Accessible.name: choice.title + (choice.available ? "" : ", sin logo disponible")
    }
    // Campo de texto cómodo: alto 52 dp, borrar, "Hecho" (cierra el teclado), vista previa
    // en vivo mientras se escribe (una sola entrada de deshacer por edición) y se mantiene
    // visible sobre el teclado.
    component EdTextField: Rectangle {
        id: tf
        property string text: ""
        property string placeholder: ""
        readonly property bool editing: input.activeFocus
        signal committed(string value)
        Layout.fillWidth: true
        implicitHeight: editor.dp(52)
        radius: editor.dp(12)
        color: "transparent"
        CalicataSurface { dark: editor.dark; accent: editor.cBlue; anchors.fill: parent; radius: tf.radius; focused: input.activeFocus }
        onTextChanged: if (!input.activeFocus && input.text !== tf.text) input.text = tf.text
        onEditingChanged: {
            if (editing) { editor.beginGesture(); editor.ensureFieldVisible(tf) }
            else { liveCommit.stop(); if (input.text !== tf.text) tf.committed(input.text); editor.endGesture() }
        }
        Timer { id: liveCommit; interval: 250; repeat: false; onTriggered: tf.committed(input.text) }
        TextInput {
            id: input
            anchors.left: parent.left; anchors.right: fieldActions.left
            anchors.top: parent.top; anchors.bottom: parent.bottom
            anchors.leftMargin: editor.dp(14); anchors.rightMargin: editor.dp(6)
            verticalAlignment: TextInput.AlignVCenter
            color: editor.cText
            selectionColor: editor.cBlue
            selectedTextColor: "#FFFFFF"
            cursorVisible: activeFocus
            font.pixelSize: editor.dp(15)
            maximumLength: 80
            clip: true
            inputMethodHints: Qt.ImhNoAutoUppercase
            Component.onCompleted: text = tf.text
            onTextEdited: liveCommit.restart()
            onAccepted: { liveCommit.stop(); tf.committed(text); input.focus = false; editor.inputMethod.hide() }
        }
        Text {
            anchors.fill: input
            verticalAlignment: Text.AlignVCenter
            visible: !input.text.length
            text: tf.placeholder
            color: editor.cMuted
            font.pixelSize: editor.dp(15)
            elide: Text.ElideRight
        }
        Row {
            id: fieldActions
            anchors.right: parent.right; anchors.rightMargin: editor.dp(4)
            anchors.verticalCenter: parent.verticalCenter
            spacing: editor.dp(2)
            EdIconButton {
                visible: input.text.length > 0
                icon: "action.close"
                Accessible.name: "Borrar texto"
                onClicked: { input.text = ""; input.forceActiveFocus(); liveCommit.restart() }
            }
            Rectangle {
                visible: input.activeFocus
                width: doneLabel.implicitWidth + editor.dp(20); height: editor.dp(36)
                anchors.verticalCenter: parent.verticalCenter
                radius: editor.dp(10)
                color: doneTap.pressed ? Qt.darker(editor.cBlue, 1.15) : editor.cBlue
                Text { id: doneLabel; anchors.centerIn: parent; text: "Hecho"; color: "#FFFFFF"; font.bold: true; font.pixelSize: editor.dp(13) }
                TapHandler { id: doneTap; onTapped: input.accepted() }
                Accessible.role: Accessible.Button
                Accessible.name: "Hecho"
            }
        }
    }
    // Asa arrastrable (recorte / perspectiva); informa la posición en coordenadas del padre.
    component ToolHandle: Rectangle {
        id: handle
        property real cx: 0
        property real cy: 0
        signal moved(real x, real y)
        width: editor.dp(26); height: width; radius: width / 2
        x: cx - width / 2; y: cy - height / 2
        color: "#FFFFFF"
        border.width: 2; border.color: editor.cBlue
        scale: handleArea.pressed ? 1.2 : 1

        MouseArea {
            id: handleArea
            anchors.fill: parent
            anchors.margins: -editor.dp(10)
            preventStealing: true
            onPositionChanged: function(m) {
                if (!pressed) return
                var p = handleArea.mapToItem(handle.parent, m.x, m.y)
                handle.moved(p.x, p.y)
            }
        }
    }

    contentItem: Item {
    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        // Cabecera: atrás · título/estado · Guardar borrador.
        RowLayout {
            Layout.fillWidth: true
            Layout.leftMargin: editor.dp(8); Layout.rightMargin: editor.dp(12)
            Layout.topMargin: editor.dp(8); Layout.bottomMargin: editor.dp(4)
            spacing: editor.dp(6)
            EdIconButton {
                icon: "calgen.chevronLeft"
                Accessible.name: editor.mode.length ? "Cancelar herramienta" : "Volver a Fotos"
                onClicked: editor.mode.length ? editor.cancelTool() : editor.close()
            }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0
                Text { Layout.fillWidth: true; text: editor.slotTitle; color: editor.cText; font.bold: true; font.pixelSize: editor.dp(17); elide: Text.ElideRight }
                Text {
                    Layout.fillWidth: true
                    elide: Text.ElideRight
                    text: editor.mode === "crop" ? "Recorte libre · arrastra el marco o sus esquinas"
                          : editor.mode === "perspective" ? "Corrección de perspectiva · 4 puntos"
                          : editor.mode === "draw" ? "Anotación sobre la derivada"
                          : editor.undoStack.length ? "Cambios sin publicar" : "Original conservada · derivada editable"
                    color: editor.undoStack.length && !editor.mode.length ? editor.cOrange : editor.cMuted
                    font.pixelSize: editor.dp(11)
                }
            }
            EdPill {
                Layout.fillWidth: false
                visible: !editor.mode.length
                text: "Guardar borrador"
                enabled: !editor.rendering && editor.undoStack.length > 0
                onClicked: editor.saveDraft()
            }
        }

        // Vista previa: Antes (original) | Después (derivada real C++) o base de la herramienta.
        Item {
            id: previewBox
            Layout.fillWidth: true
            Layout.leftMargin: editor.dp(12); Layout.rightMargin: editor.dp(12)
            // Con el teclado abierto la vista previa se compacta (sigue visible) y cede
            // espacio al campo que se está escribiendo.
            Layout.preferredHeight: editor.typing ? Math.min(editor.height * 0.28, width * 0.7)
                                                  : Math.min(editor.height * 0.42, width * 1.05)
            Behavior on Layout.preferredHeight { NumberAnimation { duration: editor.motion; easing.type: Easing.OutCubic } }
            clip: true
            onWidthChanged: editor.clampPan()
            Rectangle { anchors.fill: parent; radius: editor.dp(16); color: "#0B0E12" }

            Item {
                id: stage
                x: editor.panX
                y: editor.panY
                width: previewBox.width
                height: previewBox.height
                scale: editor.zoom


                // --- comparación
                Item {
                    anchors.fill: parent
                    visible: !editor.mode.length
                    Image {
                        id: beforeImage
                        anchors.fill: parent
                        source: editor.slot.originalUrl || ""
                        fillMode: Image.PreserveAspectFit
                        asynchronous: true
                        autoTransform: true
                        sourceSize: Qt.size(1280, 1280)
                    }
                    Item {
                        // Al mover un elemento sobre la foto se ve la derivada completa.
                        x: stage.width * (editor.dragTarget.length ? 0 : editor.comparePos)
                        width: stage.width - x
                        height: stage.height
                        clip: true
                        Rectangle { anchors.fill: parent; color: "#0B0E12" }
                        Image {
                            // Solo muestra un resultado ya decodificado (sin parpadeo entre versiones).
                            id: afterImage
                            x: -parent.x
                            width: stage.width
                            height: stage.height
                            source: editor.shownPreviewUrl
                            fillMode: Image.PreserveAspectFit
                            asynchronous: false
                            // Mismo tamaño que el decodificador oculto: reutiliza su imagen en caché.
                            sourceSize: Qt.size(1600, 1600)
                        }
                    }
                }
                Image {
                    // Decodifica la vista previa nueva fuera de pantalla; al estar lista se muestra.
                    visible: false
                    source: editor.previewUrl
                    asynchronous: true
                    sourceSize: Qt.size(1600, 1600)
                    onStatusChanged: if (status === Image.Ready) editor.shownPreviewUrl = source
                }

                // --- base de las herramientas (etapa correspondiente del pipeline)
                Item {
                    id: baseFrame
                    anchors.fill: parent
                    visible: editor.mode.length > 0
                    readonly property rect imgRect: Qt.rect((width - baseImage.paintedWidth) / 2, (height - baseImage.paintedHeight) / 2,
                                                            baseImage.paintedWidth, baseImage.paintedHeight)
                    Image {
                        id: baseImage
                        anchors.fill: parent
                        source: editor.baseUrl
                        fillMode: Image.PreserveAspectFit
                        asynchronous: true
                        // Las herramientas usan paintedWidth/Height (espacio de pantalla, misma
                        // proporción): acotar la decodificación no cambia sus coordenadas.
                        sourceSize: Qt.size(1600, 1600)
                    }
                    Text {
                        anchors.centerIn: parent
                        visible: baseImage.status !== Image.Ready
                        text: "Preparando herramienta…"
                        color: "#FFFFFF"
                        font.pixelSize: editor.dp(12)
                    }

                    // Recorte libre: marco con asas, mover, límites y bloqueo de proporción.
                    Item {
                        id: cropLayer
                        anchors.fill: parent
                        visible: editor.mode === "crop" && baseImage.status === Image.Ready
                        readonly property rect r: baseFrame.imgRect
                        readonly property real fx: r.x + editor.cropDraft.x * r.width
                        readonly property real fy: r.y + editor.cropDraft.y * r.height
                        readonly property real fw: editor.cropDraft.w * r.width
                        readonly property real fh: editor.cropDraft.h * r.height
                        function setCorner(corner, px, py) {
                            var r = cropLayer.r
                            var c = editor.cropDraft
                            var nx = Math.max(0, Math.min(1, (px - r.x) / r.width)), ny = Math.max(0, Math.min(1, (py - r.y) / r.height))
                            var x0 = c.x, y0 = c.y, x1 = c.x + c.w, y1 = c.y + c.h, min = 0.08
                            if (corner === 0 || corner === 3) x0 = Math.min(nx, x1 - min); else x1 = Math.max(nx, x0 + min)
                            if (corner === 0 || corner === 1) y0 = Math.min(ny, y1 - min); else y1 = Math.max(ny, y0 + min)
                            if (editor.cropAspect > 0) {
                                // Proporción bloqueada: el alto sigue al ancho (limitado al marco).
                                var targetH = (x1 - x0) * r.width / editor.cropAspect / r.height
                                if (corner === 0 || corner === 1) y0 = Math.max(0, y1 - targetH); else y1 = Math.min(1, y0 + targetH)
                                var realW = (y1 - y0) * r.height * editor.cropAspect / r.width
                                if (corner === 0 || corner === 3) x0 = x1 - realW; else x1 = x0 + realW
                            }
                            editor.cropDraft = { x: x0, y: y0, w: x1 - x0, h: y1 - y0 }
                        }
                        Rectangle { x: 0; y: 0; width: cropLayer.width; height: cropLayer.fy; color: "#99000000" }
                        Rectangle { x: 0; y: cropLayer.fy + cropLayer.fh; width: cropLayer.width; height: cropLayer.height - y; color: "#99000000" }
                        Rectangle { x: 0; y: cropLayer.fy; width: cropLayer.fx; height: cropLayer.fh; color: "#99000000" }
                        Rectangle { x: cropLayer.fx + cropLayer.fw; y: cropLayer.fy; width: cropLayer.width - x; height: cropLayer.fh; color: "#99000000" }
                        Rectangle {
                            id: cropFrame
                            x: cropLayer.fx; y: cropLayer.fy; width: cropLayer.fw; height: cropLayer.fh
                            color: "transparent"
                            border.width: 2; border.color: "#FFFFFF"
                            // Regla de tercios.
                            Rectangle { x: cropFrame.width / 3; width: 1; height: cropFrame.height; color: "#80FFFFFF" }
                            Rectangle { x: cropFrame.width * 2 / 3; width: 1; height: cropFrame.height; color: "#80FFFFFF" }
                            Rectangle { y: cropFrame.height / 3; height: 1; width: cropFrame.width; color: "#80FFFFFF" }
                            Rectangle { y: cropFrame.height * 2 / 3; height: 1; width: cropFrame.width; color: "#80FFFFFF" }
                            MouseArea {
                                id: cropMove
                                anchors.fill: parent
                                preventStealing: true
                                property point startPoint
                                property var startDraft: ({})
                                onPressed: function(m) { startPoint = cropMove.mapToItem(cropLayer, m.x, m.y); startDraft = editor.cropDraft }
                                onPositionChanged: function(m) {
                                    if (!pressed) return
                                    var p = cropMove.mapToItem(cropLayer, m.x, m.y)
                                    var dx = (p.x - startPoint.x) / cropLayer.r.width, dy = (p.y - startPoint.y) / cropLayer.r.height
                                    editor.cropDraft = { x: Math.max(0, Math.min(1 - startDraft.w, startDraft.x + dx)),
                                                         y: Math.max(0, Math.min(1 - startDraft.h, startDraft.y + dy)),
                                                         w: startDraft.w, h: startDraft.h }
                                }
                            }
                        }
                        Repeater {
                            model: 4
                            delegate: ToolHandle {
                                required property int index
                                cx: index === 0 || index === 3 ? cropLayer.fx : cropLayer.fx + cropLayer.fw
                                cy: index === 0 || index === 1 ? cropLayer.fy : cropLayer.fy + cropLayer.fh
                                onMoved: function(px, py) { cropLayer.setCorner(index, px, py) }
                            }
                        }
                    }

                    // Perspectiva: cuatro puntos arrastrables sobre la imagen sin corregir.
                    Item {
                        id: perspLayer
                        anchors.fill: parent
                        visible: editor.mode === "perspective" && baseImage.status === Image.Ready
                        readonly property rect r: baseFrame.imgRect
                        onRChanged: perspCanvas.requestPaint()
                        Canvas {
                            id: perspCanvas
                            anchors.fill: parent
                            onPaint: {
                                var ctx = getContext("2d")
                                ctx.clearRect(0, 0, width, height)
                                var r = perspLayer.r, p = editor.perspDraft
                                ctx.fillStyle = "rgba(31,91,214,0.16)"
                                ctx.strokeStyle = "#FFFFFF"
                                ctx.lineWidth = 2
                                ctx.beginPath()
                                for (var i = 0; i < 4; ++i) {
                                    var x = r.x + p[i][0] * r.width, y = r.y + p[i][1] * r.height
                                    if (i === 0) ctx.moveTo(x, y); else ctx.lineTo(x, y)
                                }
                                ctx.closePath()
                                ctx.fill()
                                ctx.stroke()
                            }
                            Connections { target: editor; function onPerspDraftChanged() { perspCanvas.requestPaint() } }
                        }
                        Repeater {
                            model: 4
                            delegate: ToolHandle {
                                required property int index
                                cx: perspLayer.r.x + editor.perspDraft[index][0] * perspLayer.r.width
                                cy: perspLayer.r.y + editor.perspDraft[index][1] * perspLayer.r.height
                                onMoved: function(px, py) {
                                    var r = perspLayer.r
                                    var next = editor.clone(editor.perspDraft)
                                    next[index] = [Math.max(0, Math.min(1, (px - r.x) / r.width)), Math.max(0, Math.min(1, (py - r.y) / r.height))]
                                    editor.perspDraft = next
                                }
                            }
                        }
                    }

                    // Anotación: lápiz, marcador y goma sobre la imagen final (coordenadas
                    // normalizadas: el trazo cae en el mismo lugar con cualquier zoom).
                    Item {
                        id: drawLayer
                        anchors.fill: parent
                        visible: editor.mode === "draw" && baseImage.status === Image.Ready
                        readonly property rect r: baseFrame.imgRect
                        onRChanged: drawCanvas.requestPaint()
                        Canvas {
                            id: drawCanvas
                            anchors.fill: parent
                            function paintStroke(ctx, s) {
                                var r = drawLayer.r, pts = s.points
                                if (!pts || pts.length < 2) return
                                var shortEdge = Math.min(r.width, r.height)
                                var marker = s.tool === "marker"
                                ctx.globalAlpha = marker ? 0.43 : 1
                                ctx.strokeStyle = s.color
                                ctx.lineWidth = Math.max(1, s.width * shortEdge / 100 * (marker ? 2.5 : 1))
                                ctx.lineCap = marker ? "square" : "round"
                                ctx.lineJoin = "round"
                                ctx.beginPath()
                                for (var i = 0; i < pts.length; ++i) {
                                    var x = r.x + pts[i][0] * r.width, y = r.y + pts[i][1] * r.height
                                    if (i === 0) ctx.moveTo(x, y); else ctx.lineTo(x, y)
                                }
                                ctx.stroke()
                                ctx.globalAlpha = 1
                            }
                            onPaint: {
                                var ctx = getContext("2d")
                                ctx.clearRect(0, 0, width, height)
                                for (var i = 0; i < editor.strokes.length; ++i) paintStroke(ctx, editor.strokes[i])
                                if (editor.liveStroke) paintStroke(ctx, editor.liveStroke)
                            }
                            Connections {
                                target: editor
                                function onStrokesChanged() { drawCanvas.requestPaint() }
                                function onLiveStrokeChanged() { drawCanvas.requestPaint() }
                            }
                        }
                        MouseArea {
                            id: drawArea
                            anchors.fill: parent
                            preventStealing: true
                            property point panStart
                            property point panOrigin
                            function norm(m) {
                                var r = drawLayer.r
                                return [Math.max(0, Math.min(1, (m.x - r.x) / r.width)), Math.max(0, Math.min(1, (m.y - r.y) / r.height))]
                            }
                            onPressed: function(m) {
                                if (editor.drawTool === "pan") {
                                    panStart = drawArea.mapToItem(previewBox, m.x, m.y)
                                    panOrigin = Qt.point(editor.panX, editor.panY)
                                    return
                                }
                                var p = norm(m)
                                if (editor.drawTool === "eraser") { editor.eraseAt(p[0], p[1]); return }
                                editor.liveStroke = { tool: editor.drawTool, color: editor.drawColor, width: editor.drawWidth, points: [p] }
                            }
                            onPositionChanged: function(m) {
                                if (!pressed) return
                                if (editor.drawTool === "pan") {
                                    var q = drawArea.mapToItem(previewBox, m.x, m.y)
                                    editor.panX = panOrigin.x + q.x - panStart.x
                                    editor.panY = panOrigin.y + q.y - panStart.y
                                    editor.clampPan()
                                    return
                                }
                                var p = norm(m)
                                if (editor.drawTool === "eraser") { editor.eraseAt(p[0], p[1]); return }
                                var s = editor.liveStroke
                                if (!s) return
                                var last = s.points[s.points.length - 1]
                                if (Math.abs(last[0] - p[0]) + Math.abs(last[1] - p[1]) < 0.003 / editor.zoom) return
                                editor.liveStroke = { tool: s.tool, color: s.color, width: s.width, points: s.points.concat([p]) }
                            }
                            onReleased: {
                                var s = editor.liveStroke
                                editor.liveStroke = null
                                if (s && s.points.length > 1) editor.pushStrokes(editor.strokes.concat([s]))
                            }
                            onCanceled: editor.liveStroke = null
                        }
                    }
                }
            }

            // Divisor Antes | Después (arrastrable). Doble toque: zoom 2,5× / volver a 1×.
            Rectangle {
                visible: !editor.mode.length && !editor.dragTarget.length && beforeImage.status === Image.Ready
                         && editor.zoom <= 1 && editor.comparePos > 0 && editor.comparePos < 1
                x: previewBox.width * editor.comparePos - width / 2
                width: 2; height: parent.height
                color: "#FFFFFF"
                Rectangle {
                    anchors.centerIn: parent
                    width: editor.dp(36); height: width; radius: width / 2
                    color: "#FFFFFF"
                    Row {
                        anchors.centerIn: parent
                        Components.FlowIcon {
                            width: editor.dp(14); height: width
                            name: "calgen.chevronLeft"
                            flow: editor.form ? editor.form.flow : null
                            tintColor: "#111827"
                            inactiveOpacity: 1
                        }
                        Components.FlowIcon {
                            width: editor.dp(14); height: width
                            name: "calgen.chevron"
                            flow: editor.form ? editor.form.flow : null
                            tintColor: "#111827"
                            inactiveOpacity: 1
                        }
                    }
                }
            }
            MouseArea {
                anchors.fill: parent
                enabled: !editor.mode.length && !editor.dragTarget.length && beforeImage.status === Image.Ready && editor.zoom <= 1
                onPressed: function(m) { editor.comparePos = Math.max(0, Math.min(1, m.x / width)) }
                onPositionChanged: function(m) { if (pressed) editor.comparePos = Math.max(0, Math.min(1, m.x / width)) }
                onDoubleClicked: editor.setZoom(2.5)
            }
            // Mover rótulo / logo / marca de agua directamente sobre la foto: el centro del
            // elemento sigue al dedo; la vista previa C++ se actualiza durante el gesto.
            MouseArea {
                id: placeArea
                anchors.fill: parent
                enabled: !editor.mode.length && editor.dragTarget.length > 0 && afterImage.status === Image.Ready
                preventStealing: true
                function place(m) {
                    var pw = afterImage.paintedWidth, ph = afterImage.paintedHeight
                    if (pw <= 0 || ph <= 0) return
                    editor.placeDragged((m.x - (width - pw) / 2) / pw, (m.y - (height - ph) / 2) / ph)
                }
                onPressed: function(m) { editor.beginGesture(); place(m) }
                onPositionChanged: function(m) { if (pressed) place(m) }
                onReleased: editor.endGesture()
                onCanceled: editor.endGesture()
            }
            Rectangle {
                // Indicación del modo mover (y salida directa).
                visible: editor.dragTarget.length > 0 && !editor.mode.length
                anchors.top: parent.top; anchors.horizontalCenter: parent.horizontalCenter; anchors.topMargin: editor.dp(10)
                width: Math.min(parent.width - editor.dp(20), dragHint.implicitWidth + doneMove.width + editor.dp(30))
                height: editor.dp(40); radius: height / 2
                color: "#CC0B0E12"
                Text {
                    id: dragHint
                    anchors.left: parent.left; anchors.leftMargin: editor.dp(14)
                    anchors.right: doneMove.left; anchors.rightMargin: editor.dp(8)
                    anchors.verticalCenter: parent.verticalCenter
                    elide: Text.ElideRight
                    color: "#FFFFFF"
                    font.pixelSize: editor.dp(12)
                    text: "Arrastra en la foto para mover " + (editor.dragTarget === "logo" ? "el logo"
                          : editor.dragTarget === "watermark" ? "la marca de agua" : "el rótulo")
                }
                Rectangle {
                    id: doneMove
                    anchors.right: parent.right; anchors.rightMargin: editor.dp(4)
                    anchors.verticalCenter: parent.verticalCenter
                    width: doneMoveText.implicitWidth + editor.dp(22); height: editor.dp(32); radius: height / 2
                    color: doneMoveTap.pressed ? Qt.darker(editor.cBlue, 1.15) : editor.cBlue
                    Text { id: doneMoveText; anchors.centerIn: parent; text: "Listo"; color: "#FFFFFF"; font.bold: true; font.pixelSize: editor.dp(12) }
                    TapHandler { id: doneMoveTap; onTapped: editor.dragTarget = "" }
                    Accessible.role: Accessible.Button
                    Accessible.name: "Terminar de mover"
                }
            }
            DragHandler {
                // Con zoom: un dedo desplaza la imagen.
                id: panDrag
                target: null
                enabled: !editor.mode.length && editor.zoom > 1
                property point origin
                onActiveChanged: if (active) origin = Qt.point(editor.panX, editor.panY)
                onActiveTranslationChanged: {
                    if (!active) return
                    editor.panX = origin.x + activeTranslation.x
                    editor.panY = origin.y + activeTranslation.y
                    editor.clampPan()
                }
            }
            TapHandler {
                enabled: !editor.mode.length && editor.zoom > 1
                onDoubleTapped: editor.resetView()
            }
            PinchHandler {
                id: stagePinch
                target: null
                enabled: editor.mode === "" || editor.mode === "draw"
                property real startZoom: 1
                onActiveChanged: if (active) startZoom = editor.zoom
                onActiveScaleChanged: if (active) editor.setZoom(startZoom * activeScale)
            }
            Rectangle {
                visible: !editor.mode.length && !editor.dragTarget.length && editor.comparePos > 0.12 && editor.zoom <= 1 && beforeImage.status === Image.Ready
                anchors.left: parent.left; anchors.bottom: parent.bottom; anchors.margins: editor.dp(10)
                width: beforeText.implicitWidth + editor.dp(16); height: editor.dp(24); radius: height / 2
                color: "#99000000"
                Text { id: beforeText; anchors.centerIn: parent; text: "Antes"; color: "white"; font.pixelSize: editor.dp(11) }
            }
            Rectangle {
                visible: !editor.mode.length && (editor.dragTarget.length > 0 || editor.comparePos < 0.88) && beforeImage.status === Image.Ready
                anchors.right: parent.right; anchors.bottom: parent.bottom; anchors.margins: editor.dp(10)
                width: afterText.implicitWidth + editor.dp(16); height: editor.dp(24); radius: height / 2
                color: "#99000000"
                Text { id: afterText; anchors.centerIn: parent; text: editor.previewBusy ? "Después · actualizando…" : "Después"; color: "white"; font.pixelSize: editor.dp(11) }
            }
            Text {
                anchors.centerIn: parent
                visible: !editor.slot.originalUrl || String(editor.slot.originalUrl).length === 0
                text: "Sin fotografía original"
                color: editor.cMuted
            }
        }

        // Barra de vista: deshacer/rehacer · zoom · comparar.
        RowLayout {
            Layout.fillWidth: true
            Layout.leftMargin: editor.dp(12); Layout.rightMargin: editor.dp(12); Layout.topMargin: editor.dp(4)
            visible: (editor.mode === "" || editor.mode === "draw") && !editor.typing
            spacing: editor.dp(2)
            EdIconButton {
                icon: "history.restore"
                enabled: editor.mode === "draw" ? editor.strokeUndo.length > 0 : editor.undoStack.length > 0
                Accessible.name: "Deshacer"
                onClicked: editor.mode === "draw" ? editor.undoStroke() : editor.undo()
            }
            EdIconButton {
                icon: "history.restore"
                mirror: true
                enabled: editor.mode === "draw" ? editor.strokeRedo.length > 0 : editor.redoStack.length > 0
                Accessible.name: "Rehacer"
                onClicked: editor.mode === "draw" ? editor.redoStroke() : editor.redo()
            }
            Item { Layout.fillWidth: true }
            EdIconButton { icon: "map.zoomOut"; enabled: editor.zoom > 1; Accessible.name: "Alejar"; onClicked: editor.setZoom(editor.zoom - 0.5) }
            Text { text: Math.round(editor.zoom * 100) + "%"; color: editor.cText; font.pixelSize: editor.dp(12); Layout.preferredWidth: editor.dp(44); horizontalAlignment: Text.AlignHCenter }
            EdIconButton { icon: "map.zoomIn"; enabled: editor.zoom < 4; Accessible.name: "Acercar"; onClicked: editor.setZoom(editor.zoom + 0.5) }
            Item { Layout.fillWidth: true }
            EdIconButton {
                visible: editor.mode === ""
                icon: "map.layers"
                on: editor.comparePos > 0 && editor.comparePos < 1
                Accessible.name: "Comparar antes y después"
                onClicked: editor.comparePos = (editor.comparePos > 0 && editor.comparePos < 1) ? 0 : 0.5
            }
            EdIconButton {
                icon: "map.recenter"
                enabled: editor.zoom > 1 || editor.panX !== 0 || editor.panY !== 0
                Accessible.name: "Restablecer vista (100 %)"
                onClicked: editor.resetView()
            }
        }
        // Recorte: proporciones y restablecer.
        RowLayout {
            Layout.fillWidth: true
            Layout.leftMargin: editor.dp(12); Layout.rightMargin: editor.dp(12); Layout.topMargin: editor.dp(8)
            visible: editor.mode === "crop"
            spacing: editor.dp(6)
            Repeater {
                model: [[0, "Libre"], [1, "1:1"], [4 / 3, "4:3"], [16 / 9, "16:9"]]
                delegate: EdPill {
                    required property var modelData
                    text: modelData[1]
                    selected: Math.abs(editor.cropAspect - modelData[0]) < 0.001
                    onClicked: editor.applyCropAspect(modelData[0])
                }
            }
            EdPill { text: "Restablecer"; onClicked: { editor.cropAspect = 0; editor.cropDraft = { x: 0, y: 0, w: 1, h: 1 } } }
        }
        // Anotación: herramienta, color, grosor, limpiar.
        ColumnLayout {
            Layout.fillWidth: true
            Layout.leftMargin: editor.dp(12); Layout.rightMargin: editor.dp(12); Layout.topMargin: editor.dp(4)
            visible: editor.mode === "draw"
            spacing: editor.dp(6)
            RowLayout {
                Layout.fillWidth: true
                spacing: editor.dp(6)
                EdPill { text: "Lápiz"; selected: editor.drawTool === "pen"; onClicked: editor.drawTool = "pen" }
                EdPill { text: "Marcador"; selected: editor.drawTool === "marker"; onClicked: editor.drawTool = "marker" }
                EdPill { text: "Goma"; selected: editor.drawTool === "eraser"; onClicked: editor.drawTool = "eraser" }
                EdPill { text: "Mover"; selected: editor.drawTool === "pan"; enabled: editor.zoom > 1; onClicked: editor.drawTool = "pan" }
            }
            RowLayout {
                Layout.fillWidth: true
                spacing: editor.dp(8)
                Repeater {
                    model: editor.drawColors
                    delegate: Rectangle {
                        id: drawSwatch
                        required property string modelData
                        width: editor.dp(28); height: width; radius: width / 2
                        color: drawSwatch.modelData
                        border.width: editor.drawColor === drawSwatch.modelData ? 3 : 1
                        border.color: editor.drawColor === drawSwatch.modelData ? editor.cBlue : editor.cBorder
                        TapHandler {
                            onTapped: {
                                editor.drawColor = drawSwatch.modelData
                                if (editor.drawTool === "eraser" || editor.drawTool === "pan") editor.drawTool = "pen"
                            }
                        }
                    }
                }
                EdSlider {
                    from: 0.2; to: 3; stepSize: 0.1; resetValue: 0.8; suffix: " grosor"
                    value: editor.drawWidth
                    onCommitted: function(v) { editor.drawWidth = v }
                }
            }
            EdPill { text: "Limpiar anotaciones"; enabled: editor.strokes.length > 0; onClicked: editor.pushStrokes([]) }
        }
        // Perspectiva: ayuda y restablecer.
        RowLayout {
            Layout.fillWidth: true
            Layout.leftMargin: editor.dp(12); Layout.rightMargin: editor.dp(12); Layout.topMargin: editor.dp(8)
            visible: editor.mode === "perspective"
            spacing: editor.dp(6)
            Text { Layout.fillWidth: true; text: "Lleva cada punto a una esquina del plano a enderezar (pared, cartel, regla)."; color: editor.cMuted; font.pixelSize: editor.dp(11); wrapMode: Text.WordWrap }
            EdPill { Layout.fillWidth: false; text: "Restablecer"; onClicked: editor.perspDraft = [[0, 0], [1, 0], [1, 1], [0, 1]] }
        }

        // Pestañas de herramientas con indicador animado.
        Item {
            Layout.fillWidth: true
            Layout.preferredHeight: editor.dp(58)
            visible: !editor.mode.length
            Flickable {
                anchors.fill: parent
                contentWidth: tabRow.width + editor.dp(16)
                flickableDirection: Flickable.HorizontalFlick
                boundsBehavior: Flickable.StopAtBounds
                clip: true
                Row {
                    id: tabRow
                    x: editor.dp(8)
                    height: parent.height
                    Repeater {
                        id: tabRepeater
                        model: editor.tabs
                        delegate: Item {
                            id: tabItem
                            required property var modelData
                            required property int index
                            width: Math.max(editor.dp(68), tabLabel.implicitWidth + editor.dp(16))
                            height: tabRow.height
                            scale: tabTap.pressed ? 0.95 : 1

                            Components.FlowIcon {
                                anchors.horizontalCenter: parent.horizontalCenter
                                y: editor.dp(8)
                                width: editor.dp(20); height: width
                                name: tabItem.modelData[1]
                                flow: editor.form ? editor.form.flow : null
                                tintColor: editor.tab === tabItem.index ? editor.cBlue : editor.cMuted
                                activeTintColor: editor.cBlue
                                inactiveOpacity: 1
                            }
                            Text {
                                id: tabLabel
                                anchors.horizontalCenter: parent.horizontalCenter
                                y: editor.dp(32)
                                text: tabItem.modelData[0]
                                color: editor.tab === tabItem.index ? editor.cBlue : editor.cMuted
                                font.pixelSize: editor.dp(11)
                                font.bold: editor.tab === tabItem.index

                            }
                            TapHandler { id: tabTap; onTapped: editor.setTab(tabItem.index) }
                            Accessible.role: Accessible.PageTab
                            Accessible.name: tabItem.modelData[0]
                        }
                    }
                }
                Rectangle {
                    // Indicador que se desplaza bajo la pestaña activa (fuera del Row).
                    readonly property Item target: tabRepeater.count > editor.tab ? tabRepeater.itemAt(editor.tab) : null
                    y: tabRow.height - height
                    x: target ? tabRow.x + target.x + editor.dp(10) : 0
                    width: target ? target.width - editor.dp(20) : 0
                    height: editor.dp(3); radius: 2
                    color: editor.cBlue


                }
            }
            Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: editor.cBorder }
        }

        Flickable {
            id: panelFlick
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: !editor.mode.length
            contentHeight: panel.implicitHeight + editor.dp(20)
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            ColumnLayout {
                id: panel
                width: parent.width - editor.dp(24)
                x: editor.dp(12)
                y: editor.dp(12)
                spacing: editor.dp(10)

                // --- Datos (autofill de la ficha; nada se vuelve a escribir) ---
                EdSection {
                    visible: editor.shownTab === 0
                    title: "Datos del rótulo"
                    EdRow {
                        label: "Mostrar datos en la foto"
                        detail: "Tomados de la ficha (" + editor.slotTitle + ")"
                        EdSwitch { checked: editor.edit.withMetadata !== false; onToggled: function(v) { editor.change(function(n) { n.withMetadata = v }) } }
                    }
                    Repeater {
                        model: editor.photoFields
                        delegate: EdRow {
                            id: fieldRow
                            required property var modelData
                            readonly property bool hasValue: String(editor.meta[modelData[0]] || "").length > 0
                            label: modelData[1]
                            detail: hasValue ? String(editor.meta[modelData[0]]) : "Sin dato en la ficha"
                            opacity: editor.edit.withMetadata !== false && hasValue ? 1 : 0.45
                            EdSwitch {
                                enabled: editor.edit.withMetadata !== false && fieldRow.hasValue
                                checked: !!editor.edit.fields && editor.edit.fields[fieldRow.modelData[0]] === true
                                onToggled: function(v) { var k = fieldRow.modelData[0]; editor.change(function(n) { n.fields[k] = v }) }
                            }
                        }
                    }
                }
                EdSection {
                    visible: editor.shownTab === 0
                    title: "Formato de coordenadas"
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: editor.dp(6)
                        Repeater {
                            model: [["utm", "UTM"], ["decimal", "Decimal"], ["dms", "GMS"]]
                            delegate: EdPill {
                                required property var modelData
                                text: modelData[1]
                                enabled: modelData[0] === "utm" || editor.hasGeo
                                selected: editor.st.coordFormat === modelData[0]
                                onClicked: { var f = modelData[0]; editor.change(function(n) { n.style.coordFormat = f }) }
                            }
                        }
                    }
                    Text {
                        Layout.fillWidth: true
                        wrapMode: Text.WordWrap
                        color: editor.cMuted
                        font.pixelSize: editor.dp(11)
                        text: editor.hasGeo ? "WGS84 · Lat " + editor.meta.latitude + " · Lon " + editor.meta.longitude
                                            : "La ficha no tiene coordenadas geográficas válidas: se usa UTM."
                    }
                }

                // --- Estilo del rótulo ---
                EdSection {
                    visible: editor.shownTab === 1
                    title: "Tipografía"
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: editor.dp(6)
                        Repeater {
                            model: editor.fonts
                            delegate: EdPill {
                                required property var modelData
                                text: modelData[1]
                                selected: editor.st.fontId === modelData[0]
                                onClicked: { var id = modelData[0]; editor.change(function(n) { n.style.fontId = id }) }
                            }
                        }
                    }
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: editor.dp(6)
                        EdPill { text: "Normal"; selected: !editor.st.bold; onClicked: editor.change(function(n) { n.style.bold = false }) }
                        EdPill { text: "Negrita"; selected: !!editor.st.bold; onClicked: editor.change(function(n) { n.style.bold = true }) }
                    }
                    EdSlider {
                        label: "Tamaño"; suffix: " %"
                        from: 2; to: 10; stepSize: 0.5; resetValue: 4
                        value: editor.st.sizePct
                        onCommitted: function(v) { editor.change(function(n) { n.style.sizePct = v }) }
                    }
                }
                EdSection {
                    visible: editor.shownTab === 1
                    title: "Color y fondo del rótulo"
                    Row {
                        spacing: editor.dp(10)
                        Repeater {
                            model: editor.colors
                            delegate: Rectangle {
                                id: swatch
                                required property string modelData
                                width: editor.dp(32); height: width; radius: width / 2
                                color: swatch.modelData
                                border.width: editor.st.color === swatch.modelData ? 3 : 1
                                border.color: editor.st.color === swatch.modelData ? editor.cBlue : editor.cBorder
                                scale: swatchTap.pressed ? 0.9 : 1

                                TapHandler { id: swatchTap; onTapped: { var c = swatch.modelData; editor.change(function(n) { n.style.color = c }) } }
                            }
                        }
                    }
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: editor.dp(6)
                        Repeater {
                            model: editor.backdrops
                            delegate: EdPill {
                                required property var modelData
                                text: modelData[1]
                                selected: editor.st.backdrop === modelData[0]
                                onClicked: { var id = modelData[0]; editor.change(function(n) { n.style.backdrop = id }) }
                            }
                        }
                    }
                    EdRow {
                        label: "Ampliar fotos pequeñas"
                        EdSwitch { checked: editor.st.enlargeSmall !== false; onToggled: function(v) { editor.change(function(n) { n.style.enlargeSmall = v }) } }
                    }
                }

                // --- Composición: rótulo + geometría ---
                EdSection {
                    visible: editor.shownTab === 2
                    title: "Posición del rótulo"
                    EdAnchorGrid {
                        current: editor.st.anchor
                        free: !!editor.st.labelPos
                        onPicked: function(a) { editor.change(function(n) { n.style.anchor = a; n.style.offsetXPct = 0; n.style.offsetYPct = 0; delete n.style.labelPos }) }
                    }
                    EdPill {
                        text: editor.dragTarget === "label" ? "Terminar de mover" : "Mover sobre la foto"
                        selected: editor.dragTarget === "label"
                        onClicked: editor.toggleDrag("label")
                    }
                    Text {
                        Layout.fillWidth: true
                        visible: !!editor.st.labelPos
                        wrapMode: Text.WordWrap
                        color: editor.cMuted
                        font.pixelSize: editor.dp(11)
                        text: "Colocado arrastrando sobre la foto. Elige una celda para volver a una posición fija."
                    }
                    EdSlider { label: "Ajuste fino X"; suffix: " %"; from: -45; to: 45; value: editor.st.offsetXPct
                               visible: !editor.st.labelPos
                               onCommitted: function(v) { editor.change(function(n) { n.style.offsetXPct = v }) } }
                    EdSlider { label: "Ajuste fino Y"; suffix: " %"; from: -45; to: 45; value: editor.st.offsetYPct
                               visible: !editor.st.labelPos
                               onCommitted: function(v) { editor.change(function(n) { n.style.offsetYPct = v }) } }
                }
                EdSection {
                    visible: editor.shownTab === 2
                    title: "Orientación"
                    GridLayout {
                        Layout.fillWidth: true
                        columns: 2
                        columnSpacing: editor.dp(6)
                        rowSpacing: editor.dp(6)
                        EdPill { text: "-90°"; onClicked: editor.change(function(n) { n.image.rotation = n.image.rotation - 90 }) }
                        EdPill { text: "+90°"; onClicked: editor.change(function(n) { n.image.rotation = n.image.rotation + 90 }) }
                        EdPill { text: "Voltear horizontal"; selected: !!editor.img.flipH; onClicked: editor.change(function(n) { n.image.flipH = !n.image.flipH }) }
                        EdPill { text: "Voltear vertical"; selected: !!editor.img.flipV; onClicked: editor.change(function(n) { n.image.flipV = !n.image.flipV }) }
                    }
                    EdSlider { label: "Rotación libre"; suffix: "°"; from: -45; to: 45; stepSize: 0.5; value: editor.img.angle
                               onCommitted: function(v) { editor.change(function(n) { n.image.angle = v }) } }
                }
                EdSection {
                    visible: editor.shownTab === 2
                    title: "Recorte y perspectiva"
                    EdRow {
                        label: "Recorte libre"
                        detail: editor.img.crop ? "Aplicado · " + Math.round(editor.img.crop.w * 100) + "% × " + Math.round(editor.img.crop.h * 100) + "%" : "Sin recorte"
                        EdPill { Layout.fillWidth: false; text: "Recortar"; onClicked: editor.beginCrop() }
                        EdPill { Layout.fillWidth: false; visible: !!editor.img.crop; text: "Quitar"
                                 onClicked: editor.change(function(n) { delete n.image.crop }) }
                    }
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: editor.dp(6)
                        Repeater {
                            // Proporción centrada rápida (sin recorte libre activo).
                            model: [["free", "Original"], ["1:1", "1:1"], ["4:3", "4:3"], ["16:9", "16:9"]]
                            delegate: EdPill {
                                required property var modelData
                                text: modelData[1]
                                selected: !editor.img.crop && editor.img.aspect === modelData[0]
                                onClicked: { var a = modelData[0]; editor.change(function(n) { delete n.image.crop; n.image.aspect = a }) }
                            }
                        }
                    }
                    EdRow {
                        label: "Corrección de perspectiva"
                        detail: editor.img.perspective ? "Aplicada (4 puntos)" : "Sin corrección"
                        EdPill { Layout.fillWidth: false; text: "Corregir"; onClicked: editor.beginPerspective() }
                        EdPill { Layout.fillWidth: false; visible: !!editor.img.perspective; text: "Quitar"
                                 onClicked: editor.change(function(n) { delete n.image.perspective }) }
                    }
                }
                EdSection {
                    visible: editor.shownTab === 2
                    title: "Resolución de salida"
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: editor.dp(6)
                        Repeater {
                            model: [["normal", "Normal"], ["high", "Alta"], ["max", "Máxima"]]
                            delegate: EdPill {
                                required property var modelData
                                text: modelData[1]
                                selected: editor.img.resolution === modelData[0]
                                onClicked: { var r = modelData[0]; editor.change(function(n) { n.image.resolution = r }) }
                            }
                        }
                    }
                    Text { Layout.fillWidth: true; wrapMode: Text.WordWrap; color: editor.cMuted; font.pixelSize: editor.dp(11)
                           text: "Normal 1600 px · Alta 2560 px · Máxima conserva la resolución de la original." }
                }

                // --- Logo y marca de agua ---
                EdSection {
                    visible: editor.shownTab === 3
                    title: "Logo"
                    EdRow {
                        label: "Incluir logo"
                        detail: editor.logoAvailable("PROJECT") || editor.logoAvailable("ENTITY")
                                ? "Imagen de la ficha sobre la fotografía"
                                : "La ficha no tiene logos disponibles (se configuran en Perfil)"
                        EdSwitch {
                            enabled: editor.logoAvailable("PROJECT") || editor.logoAvailable("ENTITY")
                            checked: !!(editor.edit.logo && editor.edit.logo.enabled)
                            onToggled: function(v) { editor.setLogoEnabled(v) }
                        }
                    }
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: editor.dp(8)
                        EdLogoChoice { source: "PROJECT"; title: "Proyecto" }
                        EdLogoChoice { source: "ENTITY"; title: "MTC / entidad" }
                    }
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: editor.dp(6)
                        enabled: !!(editor.edit.logo && editor.edit.logo.enabled)
                        opacity: enabled ? 1 : 0.45

                        EdSlider { label: "Tamaño"; suffix: " %"; from: 40; to: 300; stepSize: 5; resetValue: 100; value: editor.st.logoScalePct
                                   onCommitted: function(v) { editor.change(function(n) { n.style.logoScalePct = v }) } }
                        EdSlider { label: "Opacidad"; suffix: " %"; from: 10; to: 100; resetValue: 100; value: editor.st.logoOpacityPct
                                   onCommitted: function(v) { editor.change(function(n) { n.style.logoOpacityPct = v }) } }
                        EdSlider { label: "Margen"; suffix: " %"; from: 0; to: 15; stepSize: 0.5; value: editor.st.logoMarginPct
                                   onCommitted: function(v) { editor.change(function(n) { n.style.logoMarginPct = v }) } }
                        Text { text: "Posición"; color: editor.cText; font.pixelSize: editor.dp(13) }
                        EdAnchorGrid {
                            current: editor.st.logoAnchor
                            free: !!editor.st.logoPos
                            onPicked: function(a) { editor.change(function(n) { n.style.logoAnchor = a; delete n.style.logoPos }) }
                        }
                        EdPill {
                            text: editor.dragTarget === "logo" ? "Terminar de mover" : "Mover sobre la foto"
                            selected: editor.dragTarget === "logo"
                            onClicked: editor.toggleDrag("logo")
                        }
                    }
                }
                EdSection {
                    visible: editor.shownTab === 3
                    title: "Marca de agua"
                    EdRow {
                        label: "Incluir marca de agua"
                        detail: "Texto sobre la foto; independiente del logo"
                        EdSwitch { checked: !!editor.wm.enabled; onToggled: function(v) { editor.change(function(n) { n.watermark.enabled = v }) } }
                    }
                    EdTextField {
                        text: String(editor.wm.text || "")
                        placeholder: "Ej.: Uso interno · Proyecto"
                        // Escribir un texto implica querer verlo: activa la marca de agua.
                        onCommitted: function(v) {
                            editor.change(function(n) {
                                n.watermark.text = v
                                if (String(v).trim().length) n.watermark.enabled = true
                            })
                        }
                    }
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: editor.dp(6)
                        enabled: !!editor.wm.enabled
                        opacity: enabled ? 1 : 0.45

                        EdSlider { label: "Opacidad"; suffix: " %"; from: 5; to: 100; resetValue: 30; value: editor.wm.opacityPct || 30
                                   onCommitted: function(v) { editor.change(function(n) { n.watermark.opacityPct = v }) } }
                        EdSlider { label: "Tamaño"; suffix: " %"; from: 2; to: 20; stepSize: 0.5; resetValue: 6; value: editor.wm.sizePct || 6
                                   onCommitted: function(v) { editor.change(function(n) { n.watermark.sizePct = v }) } }
                        EdRow {
                            label: "Mosaico diagonal"
                            detail: "Repite el texto en toda la foto"
                            EdSwitch { checked: !!editor.wm.tiled; onToggled: function(v) { editor.change(function(n) { n.watermark.tiled = v }) } }
                        }
                        Text { visible: !editor.wm.tiled; text: "Posición"; color: editor.cText; font.pixelSize: editor.dp(13) }
                        EdAnchorGrid {
                            visible: !editor.wm.tiled
                            current: String(editor.wm.anchor || "middle-center")
                            free: !!editor.wm.pos
                            onPicked: function(a) { editor.change(function(n) { n.watermark.anchor = a; delete n.watermark.pos }) }
                        }
                        EdPill {
                            visible: !editor.wm.tiled
                            text: editor.dragTarget === "watermark" ? "Terminar de mover" : "Mover sobre la foto"
                            selected: editor.dragTarget === "watermark"
                            onClicked: editor.toggleDrag("watermark")
                        }
                    }
                }

                // --- Filtros (presets reales con intensidad) ---
                EdSection {
                    visible: editor.shownTab === 4
                    title: "Estilo de imagen"
                    GridLayout {
                        Layout.fillWidth: true
                        columns: 3
                        columnSpacing: editor.dp(6)
                        rowSpacing: editor.dp(6)
                        Repeater {
                            model: editor.presets
                            delegate: EdPill {
                                required property var modelData
                                text: modelData[1]
                                selected: editor.img.preset === modelData[0]
                                onClicked: { var p = modelData[0]; editor.change(function(n) { n.image.preset = p }) }
                            }
                        }
                    }
                    EdSlider { label: "Intensidad"; suffix: " %"; from: 0; to: 100; resetValue: 100; value: editor.img.presetIntensity
                               enabled: editor.img.preset !== "original"
                               onCommitted: function(v) { editor.change(function(n) { n.image.presetIntensity = v }) } }
                }

                // --- Ajustes (luz, detalle, color y balance de blancos) ---
                EdSection {
                    visible: editor.shownTab === 5
                    title: "Luz"
                    EdSlider { label: "Exposición"; from: -100; to: 100; value: editor.img.exposure
                               onCommitted: function(v) { editor.change(function(n) { n.image.exposure = v }) } }
                    EdSlider { label: "Brillo"; from: -100; to: 100; value: editor.img.brightness
                               onCommitted: function(v) { editor.change(function(n) { n.image.brightness = v }) } }
                    EdSlider { label: "Contraste"; from: -100; to: 100; value: editor.img.contrast
                               onCommitted: function(v) { editor.change(function(n) { n.image.contrast = v }) } }
                    EdSlider { label: "Luces"; from: -100; to: 100; value: editor.img.highlights
                               onCommitted: function(v) { editor.change(function(n) { n.image.highlights = v }) } }
                    EdSlider { label: "Sombras"; from: -100; to: 100; value: editor.img.shadows
                               onCommitted: function(v) { editor.change(function(n) { n.image.shadows = v }) } }
                }
                EdSection {
                    visible: editor.shownTab === 5
                    title: "Detalle y color"
                    EdSlider { label: "Claridad"; from: -100; to: 100; value: editor.img.clarity
                               onCommitted: function(v) { editor.change(function(n) { n.image.clarity = v }) } }
                    EdSlider { label: "Nitidez"; from: 0; to: 100; value: editor.img.sharpness
                               onCommitted: function(v) { editor.change(function(n) { n.image.sharpness = v }) } }
                    EdSlider { label: "Saturación"; from: -100; to: 100; value: editor.img.saturation
                               onCommitted: function(v) { editor.change(function(n) { n.image.saturation = v }) } }
                }
                EdSection {
                    visible: editor.shownTab === 5
                    title: "Balance de blancos"
                    EdSlider { label: "Temperatura"; from: -100; to: 100; value: editor.img.warmth
                               onCommitted: function(v) { editor.change(function(n) { n.image.warmth = v }) } }
                    EdSlider { label: "Tinte"; from: -100; to: 100; value: editor.img.tint
                               onCommitted: function(v) { editor.change(function(n) { n.image.tint = v }) } }
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: editor.dp(6)
                        EdPill {
                            text: "Automático"
                            enabled: !!editor.doc
                            onClicked: {
                                var s = editor.doc.suggestAutoWhiteBalance(editor.slotIndex)
                                if (s && s.warmth !== undefined)
                                    editor.change(function(n) { n.image.warmth = s.warmth; n.image.tint = s.tint })
                                else
                                    editor.statusText = "No se pudo analizar la original para el balance automático."
                            }
                        }
                        EdPill {
                            text: "Restablecer ajustes"
                            onClicked: editor.change(function(n) {
                                var keys = ["exposure", "brightness", "contrast", "highlights", "shadows", "clarity", "sharpness", "saturation", "warmth", "tint"]
                                for (var i = 0; i < keys.length; ++i) n.image[keys[i]] = 0
                            })
                        }
                    }
                }

                // --- Avanzado: curvas, viñeta, anotación ---
                EdSection {
                    visible: editor.shownTab === 6
                    title: "Curva tonal"
                    Item {
                        id: curveBox
                        Layout.fillWidth: true
                        Layout.preferredHeight: Math.min(width, editor.dp(220))
                        readonly property var pts: editor.curvePoints()
                        property var draft: null
                        readonly property var shown: draft || pts
                        onShownChanged: curveCanvas.requestPaint()
                        onWidthChanged: curveCanvas.requestPaint()
                        onHeightChanged: curveCanvas.requestPaint()
                        CalicataSurface { dark: editor.dark; accent: editor.cBlue; anchors.fill: parent; radius: editor.dp(10) }
                        Canvas {
                            id: curveCanvas
                            anchors.fill: parent
                            onPaint: {
                                var ctx = getContext("2d")
                                ctx.clearRect(0, 0, width, height)
                                ctx.strokeStyle = "rgba(128,128,128,0.35)"
                                ctx.lineWidth = 1
                                for (var g = 1; g < 4; ++g) {
                                    ctx.beginPath(); ctx.moveTo(width * g / 4, 0); ctx.lineTo(width * g / 4, height); ctx.stroke()
                                    ctx.beginPath(); ctx.moveTo(0, height * g / 4); ctx.lineTo(width, height * g / 4); ctx.stroke()
                                }
                                ctx.beginPath(); ctx.moveTo(0, height); ctx.lineTo(width, 0); ctx.stroke()
                                ctx.strokeStyle = String(editor.cBlue)
                                ctx.lineWidth = 2.5
                                ctx.beginPath()
                                for (var i = 0; i <= 64; ++i) {
                                    var x = i / 64, y = editor.curveSample(curveBox.shown, x)
                                    if (i === 0) ctx.moveTo(x * width, (1 - y) * height); else ctx.lineTo(x * width, (1 - y) * height)
                                }
                                ctx.stroke()
                            }
                        }
                        // Tocar el área agrega un punto (máx. 8).
                        TapHandler {
                            onTapped: function(ev) {
                                if (curveBox.pts.length >= 8) return
                                var p = ev.position
                                var next = curveBox.pts.concat([[Math.max(0.02, Math.min(0.98, p.x / curveBox.width)), Math.max(0, Math.min(1, 1 - p.y / curveBox.height))]])
                                editor.setCurve(next)
                            }
                        }
                        Repeater {
                            model: curveBox.shown
                            delegate: Rectangle {
                                id: curvePoint
                                required property var modelData
                                required property int index
                                readonly property bool endpoint: index === 0 || index === curveBox.shown.length - 1
                                width: editor.dp(22); height: width; radius: width / 2
                                x: modelData[0] * curveBox.width - width / 2
                                y: (1 - modelData[1]) * curveBox.height - height / 2
                                color: "#FFFFFF"
                                border.width: 2; border.color: editor.cBlue
                                MouseArea {
                                    id: curvePointArea
                                    anchors.fill: parent
                                    anchors.margins: -editor.dp(8)
                                    preventStealing: true
                                    onPositionChanged: function(m) {
                                        if (!pressed) return
                                        var p = curvePointArea.mapToItem(curveBox, m.x, m.y)
                                        var next = editor.clone(curveBox.draft || curveBox.pts)
                                        var nx = curvePoint.endpoint ? next[curvePoint.index][0] : Math.max(0.02, Math.min(0.98, p.x / curveBox.width))
                                        next[curvePoint.index] = [nx, Math.max(0, Math.min(1, 1 - p.y / curveBox.height))]
                                        curveBox.draft = next
                                    }
                                    onReleased: { if (curveBox.draft) { var d = curveBox.draft; curveBox.draft = null; editor.setCurve(d) } }
                                    onCanceled: curveBox.draft = null
                                    // Doble toque en un punto intermedio lo elimina.
                                    onDoubleClicked: {
                                        if (curvePoint.endpoint) return
                                        var next = editor.clone(curveBox.pts)
                                        next.splice(curvePoint.index, 1)
                                        editor.setCurve(next)
                                    }
                                }
                            }
                        }
                    }
                    RowLayout {
                        Layout.fillWidth: true
                        Text { Layout.fillWidth: true; text: "Toca para agregar un punto · arrastra para mover · doble toque para quitar"; color: editor.cMuted; font.pixelSize: editor.dp(11); wrapMode: Text.WordWrap }
                        EdPill { Layout.fillWidth: false; text: "Restablecer curva"; enabled: !!editor.img.curve; onClicked: editor.setCurve([[0, 0], [1, 1]]) }
                    }
                }
                EdSection {
                    visible: editor.shownTab === 6
                    title: "Viñeta"
                    EdSlider { label: "Intensidad"; from: -100; to: 100; value: editor.img.vignette
                               onCommitted: function(v) { editor.change(function(n) { n.image.vignette = v }) } }
                    EdSlider { label: "Tamaño"; from: 0; to: 100; resetValue: 50; value: editor.img.vignetteSize
                               onCommitted: function(v) { editor.change(function(n) { n.image.vignetteSize = v }) } }
                    EdSlider { label: "Suavidad"; from: 0; to: 100; resetValue: 50; value: editor.img.vignetteSoftness
                               onCommitted: function(v) { editor.change(function(n) { n.image.vignetteSoftness = v }) } }
                    EdSlider { label: "Centro X"; suffix: " %"; from: 0; to: 100; resetValue: 50; value: Math.round(editor.img.vignetteX * 100)
                               onCommitted: function(v) { editor.change(function(n) { n.image.vignetteX = v / 100 }) } }
                    EdSlider { label: "Centro Y"; suffix: " %"; from: 0; to: 100; resetValue: 50; value: Math.round(editor.img.vignetteY * 100)
                               onCommitted: function(v) { editor.change(function(n) { n.image.vignetteY = v / 100 }) } }
                }
                EdSection {
                    visible: editor.shownTab === 6
                    title: "Anotación"
                    EdRow {
                        label: "Lápiz, marcador y goma"
                        detail: (editor.edit.annotations || []).length ? (editor.edit.annotations.length + " trazos en la derivada") : "Sin anotaciones"
                        EdPill { Layout.fillWidth: false; text: "Anotar"; onClicked: editor.beginDraw() }
                        EdPill { Layout.fillWidth: false; visible: (editor.edit.annotations || []).length > 0; text: "Quitar"
                                 onClicked: editor.change(function(n) { n.annotations = [] }) }
                    }
                }

                // --- Versiones ---
                EdSection {
                    visible: editor.shownTab === 7
                    title: "Versión actual"
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: editor.dp(10)
                        Rectangle {
                            Layout.preferredWidth: editor.dp(84); Layout.preferredHeight: editor.dp(64); radius: editor.dp(10)
                            color: editor.dark ? Qt.rgba(1, 1, 1, 0.06) : Qt.rgba(1, 1, 1, 0.55); clip: true
                            Image { anchors.fill: parent; source: editor.form ? editor.form._photoSource(editor.slotIndex) : ""
                                    sourceSize: Qt.size(220, 220); fillMode: Image.PreserveAspectCrop; asynchronous: true }
                        }
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: editor.dp(4)
                            Text {
                                text: editor.cloudVersions.length ? editor.cloudVersions.length + " versiones en la nube" : "Solo en el dispositivo"
                                color: editor.cText; font.bold: true; font.pixelSize: editor.dp(13)
                            }
                            Text {
                                visible: editor.undoStack.length > 0
                                text: "Borrador en edición (sin publicar)"
                                color: editor.cOrange; font.pixelSize: editor.dp(11)
                            }
                            Rectangle {
                                readonly property string s: String(editor.slot.syncState || "LOCAL")
                                implicitWidth: syncLabel.implicitWidth + editor.dp(16); implicitHeight: editor.dp(22); radius: height / 2
                                color: s === "SYNCED" ? Qt.rgba(editor.cGreen.r, editor.cGreen.g, editor.cGreen.b, 0.16)
                                     : s === "CONFLICT" || s === "FAILED" ? Qt.rgba(editor.cOrange.r, editor.cOrange.g, editor.cOrange.b, 0.18)
                                     : editor.cBlueSoft
                                Text {
                                    id: syncLabel
                                    anchors.centerIn: parent
                                    text: parent.s === "SYNCED" ? "Publicada" : parent.s === "SYNCING" ? "Publicando…"
                                          : parent.s === "PENDING" ? "Pendiente" : parent.s === "CONFLICT" ? "Otra versión remota"
                                          : parent.s === "FAILED" ? "Error de envío" : parent.s === "CONFLICT_KEPT_REMOTE" ? "Remota en uso" : "Local"
                                    color: parent.s === "SYNCED" ? editor.cGreen : parent.s === "CONFLICT" || parent.s === "FAILED" ? editor.cOrange : editor.cBlue
                                    font.bold: true; font.pixelSize: editor.dp(11)
                                }
                            }
                        }
                    }
                }
                EdSection {
                    visible: editor.shownTab === 7 && editor.cloudVersions.length > 0
                    title: "Historial en la nube"
                    Repeater {
                        model: editor.shownTab === 7 ? editor.cloudVersions : []
                        delegate: RowLayout {
                            id: cloudRow
                            required property var modelData
                            readonly property bool inUse: String(modelData.version_id) === String(editor.slot.cloudActiveVersionId || "")
                            Layout.fillWidth: true
                            spacing: editor.dp(8)
                            Rectangle { Layout.preferredWidth: editor.dp(10); Layout.preferredHeight: editor.dp(10); radius: width / 2
                                        color: cloudRow.inUse ? editor.cBlue : editor.cBorder }
                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 0
                                Text { text: "v" + cloudRow.modelData.version_number + (cloudRow.inUse ? " · En uso" : ""); color: editor.cText; font.bold: true; font.pixelSize: editor.dp(13) }
                                Text { text: String(cloudRow.modelData.finalized_at || "").replace("T", " ").substring(0, 16); color: editor.cMuted; font.pixelSize: editor.dp(11) }
                            }
                            EdPill {
                                Layout.fillWidth: false
                                visible: !cloudRow.inUse && !!editor.cloud
                                text: "Usar"
                                onClicked: {
                                    editor.renderStartedAt = Date.now()
                                    editor.photoOperation = { id: "MEDIA_RESTORE-" + Date.now(), kind: "MEDIA_RESTORE",
                                        title: "Restaurando versión…", detail: "Descargando desde Media Cloud", blocking: true }
                                    photoPublishTimeout.restart()
                                    editor.cloud.activateCloudPhotoVersion(editor.doc, editor.slotIndex, cloudRow.modelData.version_id)
                                }
                            }
                            EdPill {
                                Layout.fillWidth: false
                                visible: !cloudRow.inUse && !!editor.cloud
                                text: "Descartar"
                                onClicked: editor.cloud.discardCloudPhotoVersion(editor.doc, editor.slotIndex, cloudRow.modelData.version_id, true)
                            }
                        }
                    }
                }
                EdSection {
                    visible: editor.shownTab === 7 && (editor.slot.versions || []).length > 0
                    title: "Versiones en el dispositivo"
                    Repeater {
                        model: editor.shownTab === 7 ? (editor.slot.versions || []) : []
                        delegate: RowLayout {
                            id: localRow
                            required property var modelData
                            readonly property bool inUse: modelData.local_version_id === editor.slot.activeVersionId
                            Layout.fillWidth: true
                            spacing: editor.dp(10)
                            Rectangle {
                                Layout.preferredWidth: editor.dp(72); Layout.preferredHeight: editor.dp(54); radius: editor.dp(8)
                                color: editor.dark ? Qt.rgba(1, 1, 1, 0.06) : Qt.rgba(1, 1, 1, 0.55); clip: true
                                Image { anchors.fill: parent; source: localRow.modelData.url || ""; sourceSize: Qt.size(200, 200)
                                        fillMode: Image.PreserveAspectCrop; asynchronous: true }
                            }
                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 0
                                Text { text: String(localRow.modelData.created_at || "").replace("T", " ").substring(0, 16); color: editor.cText; font.pixelSize: editor.dp(12) }
                                Text { text: (localRow.inUse ? "En uso · " : "") + (localRow.modelData.state || "PENDIENTE"); color: editor.cMuted; font.pixelSize: editor.dp(11) }
                            }
                            EdPill {
                                Layout.fillWidth: false
                                text: localRow.inUse ? "En uso" : "Usar"
                                enabled: !localRow.inUse
                                onClicked: {
                                    if (editor.doc.restorePhotoVersion(editor.slotIndex, localRow.modelData.local_version_id)) {
                                        if (editor.cloud) editor.cloud.enqueuePhotoSync(editor.doc, editor.slotIndex)
                                        editor.slot = editor.doc.photoSlot(editor.slotIndex)
                                        editor.edit = editor.normalized(editor.slot.edit)
                                        editor.undoStack = []; editor.redoStack = []
                                    }
                                }
                            }
                        }
                    }
                }
                EdSection {
                    visible: editor.shownTab === 7
                    title: "Original (siempre conservada)"
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: editor.dp(10)
                        Rectangle {
                            Layout.preferredWidth: editor.dp(72); Layout.preferredHeight: editor.dp(54); radius: editor.dp(8)
                            color: editor.dark ? Qt.rgba(1, 1, 1, 0.06) : Qt.rgba(1, 1, 1, 0.55); clip: true
                            Image { anchors.fill: parent; source: editor.slot.originalUrl || ""; sourceSize: Qt.size(200, 200)
                                    fillMode: Image.PreserveAspectCrop; asynchronous: true; autoTransform: true }
                        }
                        Text {
                            Layout.fillWidth: true; wrapMode: Text.WordWrap
                            color: editor.cMuted; font.pixelSize: editor.dp(12)
                            text: "Sin ediciones: cada edición genera una derivada nueva y versionada."
                        }
                    }
                }
            }
        }

        Text {
            Layout.fillWidth: true
            Layout.leftMargin: editor.dp(14); Layout.rightMargin: editor.dp(14)
            Layout.topMargin: editor.dp(4)
            visible: text.length > 0 && !editor.typing
            // Aviso de la vista previa (p. ej. logo no legible) antes que el estado general.
            text: editor.previewWarning.length ? editor.previewWarning : editor.statusText
            wrapMode: Text.WordWrap
            color: editor.previewWarning.length ? editor.cOrange : editor.cMuted
            font.pixelSize: editor.dp(12)
        }
        // Acciones: herramienta activa (cancelar/aplicar) o actualizar · restablecer · publicar.
        Rectangle {
            Layout.fillWidth: true
            Layout.fillHeight: editor.mode.length > 0
            Layout.preferredHeight: actionRow.implicitHeight + editor.dp(20)
            // Escribiendo, el espacio es del campo (el teclado ocupa la mitad inferior);
            // reaparece al pulsar "Hecho" o cerrar el teclado.
            visible: !editor.typing
            color: "transparent"
            // Barra de acciones del editor: el material de las hojas flotantes de Calicatas.
            CalicataSurface { dark: editor.dark; accent: editor.cBlue; anchors.fill: parent; radius: 0; level: "sheet" }
            GridLayout {
                id: actionRow
                // Teléfono: acción principal a lo ancho en su propia fila (etiquetas legibles).
                readonly property bool narrow: width < editor.dp(440)
                anchors.left: parent.left; anchors.right: parent.right; anchors.bottom: parent.bottom
                anchors.margins: editor.dp(10)
                columns: narrow ? 2 : 3
                columnSpacing: editor.dp(8)
                rowSpacing: editor.dp(8)
                EdPill { visible: editor.mode.length > 0; text: "Cancelar"; onClicked: editor.cancelTool() }
                EdPill {
                    visible: editor.mode.length > 0
                    primary: true
                    enabled: baseImage.status === Image.Ready
                    text: editor.mode === "draw" ? "Finalizar" : "Aplicar"
                    onClicked: editor.mode === "crop" ? editor.commitCrop() : editor.mode === "perspective" ? editor.commitPerspective() : editor.commitDraw()
                }
                EdPill {
                    visible: !editor.mode.length
                    text: "Actualizar ficha"
                    Accessible.name: "Actualizar datos del rótulo con la ficha"
                    onClicked: editor.change(function(n) { n.metadata = editor.freshMetadata() })
                }
                EdPill {
                    visible: !editor.mode.length
                    text: "Restablecer"
                    Accessible.name: "Restablecer estilo, datos, imagen y anotaciones por defecto"
                    onClicked: {
                        editor.dragTarget = ""
                        editor.change(function(n) {
                            n.style = editor.clone(editor.defaultStyle)
                            n.image = editor.clone(editor.defaultImage)
                            n.fields = {}
                            n.withMetadata = true
                            n.metadata = editor.freshMetadata()
                            n.logo = { enabled: false, source: n.logo && n.logo.source ? n.logo.source : "PROJECT" }
                            n.watermark = {}
                            n.annotations = []
                        })
                    }
                }
                EdPill {
                    visible: !editor.mode.length
                    Layout.columnSpan: actionRow.narrow ? 2 : 1
                    primary: true
                    enabled: !editor.rendering && !!editor.slot.originalUrl && String(editor.slot.originalUrl).length > 0
                    text: editor.rendering ? "Generando…" : "Regenerar y publicar"
                    onClicked: editor.publish()
                }
            }
        }
    }
        CalicataOperationOverlay {
            operation: editor.photoOperation
            pageColor: editor.cPage
            surfaceColor: editor.cSurface
            textColor: editor.cText
            mutedColor: editor.cMuted
            accentColor: editor.cBlue
            borderColor: editor.cBorder
            onActionTriggered: function(actionId, op) {
                editor.photoOperation = null
                if (op && op.closeEditor) editor.close()
            }
        }
    }
}

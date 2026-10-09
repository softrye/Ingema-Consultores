// Invariantes de rendimiento de Calicatas (static only; no build, no device).
// node tests/calicatas/performance_static.cjs
const fs = require("fs"), path = require("path"), assert = require("assert");
const root = path.resolve(__dirname, "..", "..");
const read = p => fs.readFileSync(path.join(root, p), "utf8").replace(/\r\n/g, "\n");
const form = read("qml/Mobile/pages/CalicataFormPage.qml");
const editor = read("qml/Mobile/pages/CalicatasEditorPage.qml");
const photoEditor = read("qml/Mobile/pages/CalicataPhotoEditor.qml");
const picker = read("qml/Mobile/pages/CalicataPointPicker.qml");
const cloud = read("calicatacloudservice.cpp");
let passed = 0;
const check = (name, f) => { f(); passed++; console.log("PASS", name); };
function body(src, name) {
    const i = src.indexOf("function " + name + "(");
    assert.ok(i >= 0, "missing " + name);
    let depth = 0;
    for (let k = src.indexOf("{", i); k < src.length; ++k) {
        if (src[k] === "{") depth++;
        else if (src[k] === "}" && --depth === 0) return src.slice(i, k + 1);
    }
    return "";
}

check("typing in text areas: one _markDirty per burst, flushed before any commit", () => {
    assert.ok(/id: typingDirtyTimer\s*\n\s*interval: 280\s*\n\s*repeat: false\s*\n\s*onTriggered: root\._markDirty\(\)/.test(form));
    assert.ok(body(form, "commitPendingField").includes("flushTypingDirty()"), "no lost keystrokes");
    // Observaciones, observaciones del perfil, descripción del estrato, interpretación.
    assert.ok(/root\.observacionesText = text\s*\n\s*root\._markDirtySoon\(\)/.test(form));
    assert.ok(/root\.observacionesText = t\s*\n\s*root\._markDirtySoon\(\)/.test(form));
    assert.ok(/setProperty\(prfEditorCard\.idx, "descripcion", t\)\s*\n\s*root\._markDirtySoon\(\)/.test(form));
    assert.ok(form.includes("root.updateProfileSetup({ interpretation: t }, true)"));
    // invalidateReview idempotente (antes: 4 asignaciones + array nuevo por tecla).
    assert.ok(/if \(reviewRequested \|\| reviewReady \|\| reviewMessage\.length \|\| reviewIssues\.length\)/.test(body(form, "invalidateReview")));
    assert.ok(/id: reviewRefresh\s*\n\s*interval: 120/.test(form));
});

check("strata revision: coalesced cell edits, immediate structure, fresh synchronous reads", () => {
    assert.ok(/function onDataChanged\(\) \{\s*\n\s*if \(root\._cortesRevisionPending\) return\s*\n\s*root\._cortesRevisionPending = true\s*\n\s*Qt\.callLater\(root\._flushCortesRevision\)/.test(form));
    for (const sig of ["onRowsInserted", "onRowsRemoved", "onRowsMoved", "onModelReset"])
        assert.ok(form.includes("function " + sig + "() { root._bumpCortesRevisionNow() }"), sig);
    for (const fn of ["exportState", "commitProfileGroundwater", "_applyLiveCalicata", "labIndexForKey", "labSetFilter", "labNewSample"])
        assert.ok(/^\s*function [^\n]*\n\s*root\._flushCortesRevision\(\)/.test(body(form, fn)), fn + " flushes first");
    // Evaluadas dentro de bindings (PrfCard.suggested/suggestion, resumen de laboratorio):
    // escribir _cortesRevision ahí es un binding loop (logcat: CalicataFormPage.qml:13097).
    for (const fn of ["suggestedGeneralClass", "autoProfileInterpretation", "labSummaryText"])
        assert.ok(!body(form, fn).includes("_flushCortesRevision()"), fn + " must not write the revision it depends on");
    assert.ok(/onClicked: \{\s*\n\s*root\._flushCortesRevision\(\)\s*\n\s*root\.requestAssistedReview\("interpretation"\)/.test(form));
});

check("photos: bounded decode sizes (viewer, editor, logos)", () => {
    assert.ok(/source: photoViewer\.visible \? root\._photoSource\(root\.activePhotoCategory\) : ""[\s\S]{0,300}sourceSize: Qt\.size\(2048, 2048\)/.test(form));
    assert.ok(/source: genLogoSlot\.logoSource[\s\S]{0,140}sourceSize: Qt\.size\(512, 512\)/.test(form));
    for (const src of ["editor.shownPreviewUrl", "editor.previewUrl", "editor.baseUrl"])
        assert.ok(new RegExp("source: " + src.replace(".", "\\.") + "[\\s\\S]{0,420}sourceSize: Qt\\.size\\(1600, 1600\\)").test(photoEditor), src);
});

check("project picker keeps the same account's list while refreshing (no empty flash / offline)", () => {
    const refresh = cloud.slice(cloud.indexOf("void CalicataCloudService::refreshProjects()"), cloud.indexOf("void CalicataCloudService::listProjectCalicatas("));
    assert.ok(refresh.includes("syncAccountContext();") && !refresh.includes("m_projects.clear();"));
    // El cambio de cuenta sigue vaciando la lista.
    assert.ok(/void CalicataCloudService::syncAccountContext[\s\S]{0,1200}m_projects\.clear\(\);/.test(cloud));
});

check("no dead hidden UI and no ungated infinite animations", () => {
    assert.ok(!form.includes("Legacy laboratory controls are preserved only as hidden migration state"));
    assert.ok(!form.includes("id: mobileGpsButton"));
    for (const [src, name] of [[form, "form"], [editor, "editor"], [picker, "picker"], [photoEditor, "photoEditor"]]) {
        const blocks = src.split("loops: Animation.Infinite").slice(0, -1);
        for (const before of blocks)
            assert.ok(/running: [^\n]+\n[^\n]*$/.test(before.slice(-400)) || /running: [^\n]+/.test(before.slice(-300)), name + " infinite animation gated by running:");
    }
});

// ---------------------------------------------------------------- Fase 2: frame time
check("validation: one compiled rules engine per thread (no QJSEngine + 70 KB parse per call)", () => {
    const v = read("calicatavalidation.h");
    assert.ok(v.includes("thread_local RulesEngine *instance = new RulesEngine;"));
    const issues = v.slice(v.indexOf("inline QVariantList issues("));
    assert.ok(!issues.includes("QJSEngine engine;") && !issues.includes("engine.evaluate("), "no per-call engine/parse");
    assert.ok(issues.includes("rules.validate.call({rules.engine.toScriptValue(state)})"));
});

check("stage change: no synchronous save inside the tap; deferred after the 220 ms reveal", () => {
    const scroll = body(form, "scrollToSection");
    assert.ok(!scroll.includes("flushRequested()") && scroll.includes("root._scheduleFlush(Date.now())"));
    assert.ok(scroll.indexOf("commitPendingField()") >= 0, "values still committed synchronously");
    assert.ok(!body(form, "reviewForExport").includes("flushRequested()"));
    assert.ok(/id: deferredFlush[\s\S]{0,260}interval: 260/.test(form));
});

check("stage change is immediate: no snapshot texture or reveal animation", () => {
    for (const t of ["stageMotionSnapshot", "stageRevealAnimation", "stageMotionTranslate"]) assert.ok(!form.includes(t), t);
    assert.ok(form.includes("readonly property bool _stageSettling: stageSettleAnimation.running"));
    // Las alturas que dependen del ancho no se animan mientras la etapa se asienta (swipe).
    assert.strictEqual((form.match(/enabled: !root\._stageSettling; NumberAnimation/g) || []).length, 3);
});

check("Ubicación map: created once (async), not recreated on every stage entry", () => {
    const loader = form.slice(form.indexOf("id: locationPreview"), form.indexOf("function updatePoint()", form.indexOf("id: locationPreview")));
    assert.ok(loader.includes("root._locationMapWarm") && !loader.includes("root.stageIndex === 1") && loader.includes("asynchronous: true"));
    assert.ok(/onStageIndexChanged: \{\s*\n\s*if \(stageIndex === 1\) _locationMapWarm = true/.test(form));
});

check("popups: flat dim + solid surface, no capture plumbing", () => {
    assert.ok(/component GenScrim: Rectangle \{\n\s*property var popupItem: null\n\s*color: Qt\.rgba/.test(form));
    assert.ok(/component CalScrim: Rectangle \{\n\s*property var popupItem: null\n\s*color: /.test(editor));
    for (const t of ["glassLayer", "glassBackdropItem", "ShaderEffectSource", "MultiEffect"]) {
        assert.ok(!form.includes(t), "form " + t);
        assert.ok(!editor.includes(t), "editor " + t);
    }
});

// ---------------------------------------------------------------- P0: Lab / Fotos / Revisión
check("lab detail window: plain dim scrim, full-width sections", () => {
    assert.ok(!form.includes("labDetailBackdrop") && !form.includes("labBlurLayer"));
    assert.ok(/id: labDetailScrim[\s\S]{0,200}color: "#000000"/.test(form));
    for (const id of ["mobileExcavationSection", "mobileSamplesSection"])
        assert.ok(new RegExp("id: " + id + "\\s*\\n\\s*Layout\\.fillWidth: true\\s*\\n\\s*glassPanel: !stratumSheet\\.floating").test(form), id);
});

check("photo publish: real failing phase + Storage reason surfaced, never swallowed", () => {
    assert.ok(cloud.includes('"INGE_CALICATA_MEDIA_FAILED op="') && cloud.includes('"INGE_CALICATA_MEDIA_UPLOAD_REJECTED http="'));
    for (const phase of ["SLOT_CHECK", "CREATE", "RESERVE", "UPLOAD_ORIGINAL", "UPLOAD_DERIVATIVE", "FINALIZE", "ACTIVATE"])
        assert.ok(cloud.includes('QStringLiteral("' + phase + '")'), phase);
    // Subida rechazada: termina en esa fase, sin finalize (la reserva se reutiliza al reintentar).
    assert.ok(!cloud.includes("uploadFailure") && cloud.includes('QStringLiteral("El almacenamiento rechazó la fotografía original (%1).")'));
    for (const stage of ["PUBLISH_BEGIN", "RESERVE_OK", "UPLOAD_ORIGINAL_BEGIN", "UPLOAD_ORIGINAL_OK", "UPLOAD_DERIVATIVE_BEGIN",
                         "UPLOAD_DERIVATIVE_OK", "FINALIZE_BEGIN", "FINALIZE_OK"])
        assert.ok(cloud.includes('trace("' + stage + '")'), stage);
    assert.ok(cloud.includes('"INGE_CALICATA_MEDIA_PUBLISH_ERROR op="') && cloud.includes('" elapsedMs="'));
    // Reintentar un FAILED no fuerza (solo un CONFLICT resuelto con "Conservar la mía").
    assert.ok(/if \(entry\.value\(QStringLiteral\("state"\)\)\.toString\(\) == QLatin1String\("CONFLICT"\)\)\s*\n\s*entry\[QStringLiteral\("force"\)\] = true;/.test(cloud));
    assert.ok(/var cause = String\(message \|\| ""\)\.trim\(\)/.test(photoEditor) && !photoEditor.includes('"No se pudo completar"'));
    // El cliente nunca llama a la función de Rendiciones (la invoca una política de Storage).
    assert.ok(!cloud.includes("rendition_attachment_storage_uploadable"));
});

check("photos: capture + regenerate never block the UI on render or publish", () => {
    const doc = read("calicatadocument.cpp");
    const persist = doc.slice(doc.indexOf("QUrl CalicataDocument::persistPhoto("), doc.indexOf("bool CalicataDocument::setPhotoFromCache"));
    const fast = persist.slice(0, persist.indexOf("Sin copia del original"));
    assert.ok(fast.includes("QThreadPool::globalInstance()->start(") && fast.includes("probe.canRead()"));
    assert.ok(fast.indexOf("paintPhotoDerivative") > fast.indexOf("QThreadPool::globalInstance()->start("), "stamp painted off the UI thread");
    assert.ok(fast.includes("m_photoPersistLatest.value(idx) != token") && fast.includes("emit self->photoPersisted(idx, self->cachedPhotoUrl(idx), QString());"));
    // QML: la publicación se encola una sola vez, al confirmarse la copia local.
    const commit = form.slice(form.indexOf("function _commitPendingPhoto("), form.indexOf("function _commitPendingPhoto(") + 2600);
    assert.ok(!commit.includes("_queuePhotoSync("));
    assert.ok(body(form, "onPhotoPersisted").includes("root._queuePhotoSync(docConnections.target, idx)"));
    // Editor: tras RENDER_OK cierra; no espera "Publicando fotografía…".
    assert.ok(!photoEditor.includes("Publicando fotografía…") && /editor\.photoOperation = null\s*\n\s*editor\.rendering = false\s*\n\s*editor\.close\(\)/.test(photoEditor));
});

check("Revisión uses the same stage header as General…Fotos", () => {
    assert.ok(!form.includes("visible: root.stageIndex >= 0 && root.stageIndex <= 4"));
    assert.ok(!form.includes("visible: root.stageIndex > 4"));
    assert.ok(/stageIcon: root\.stageIndex === 5 \? root\.iconNotesName/.test(form));
});

console.log(`PERFORMANCE_STATIC PASS ${passed} checks`);

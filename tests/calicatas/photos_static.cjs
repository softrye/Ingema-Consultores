// Static checks for Calicatas / Fotos (no app build).
// Run: node tests/calicatas/photos_static.cjs
"use strict";
const fs = require("fs");
const path = require("path");
const assert = require("assert");

const root = path.resolve(__dirname, "..", "..");
const read = p => fs.readFileSync(path.join(root, p), "utf8").replace(/\r\n/g, "\n");
const form = read("qml/Mobile/pages/CalicataFormPage.qml");
const editorPage = read("qml/Mobile/pages/CalicatasEditorPage.qml");
const photoEditor = read("qml/Mobile/pages/CalicataPhotoEditor.qml");
const cloud = read("calicatacloudservice.cpp");
const doc = read("calicatadocument.cpp");
// Definición (no la declaración adelantada que usa persistPhoto).
const paintDef = doc.indexOf("QImage paintPhotoDerivative(const QImage &originalInput, const QVariantMap &edit, const QImage &logo)\n{");
assert.ok(paintDef > 0, "paintPhotoDerivative definition");
const body = (src, name) => { const i = src.indexOf("function " + name + "("); const e = src.indexOf("\n    }\n", i); assert.ok(i >= 0 && e > i, name); return src.slice(i, e); };
let passed = 0;
const check = (name, f) => { f(); passed++; console.log("PASS", name); };

// R1 — return to General after camera/save/sync: navigation only restored per document identity.
check("importState restores stage only on first import of a document", () => {
    const i = form.indexOf("function importState(st)");
    const block = form.slice(i, form.indexOf("sectionNavCurrent = sectionNavigation[stageIndex].n", i) + 60);
    assert.ok(block.includes("importedDocId !== root._navigationDocId"), "guarded by document identity");
});
check("onDocChanged ignores re-emission of the same document", () => {
    const i = form.indexOf("    onDocChanged: {");
    const head = form.slice(i, i + 600);
    assert.ok(/if \(boundId\.length && boundId === _boundDocId\) return/.test(head));
    assert.ok(head.indexOf("return") < head.indexOf("stageIndex = 0") || !head.includes("stageIndex = 0"));
});

// R3/R4 — false "changed on another device" + retry identity.
const enqueue = cloud.slice(cloud.indexOf("QString CalicataCloudService::enqueuePhotoSync"), cloud.indexOf("QVariantList CalicataCloudService::takeConfirmedMedia"));
check("pending server confirmations are applied before the conflict base", () => {
    const apply = enqueue.indexOf("document->setPhotoCloudState(confirmedIdx, change)");
    const base = enqueue.indexOf('entry[QStringLiteral("base_cloud_version_id")]');
    assert.ok(apply > 0 && base > apply);
});
check("same local revision keeps media_id/version_id on re-enqueue", () => {
    assert.ok(/entry\[QStringLiteral\("version_id"\)\] = other\.value\(QStringLiteral\("version_id"\)\)/.test(enqueue));
});
check("a cloud version this device knows is never 'another device'", () => {
    assert.ok(enqueue.includes("known_cloud_version_ids"));
    assert.ok(/replacedElsewhere = [^;]*!remoteIsKnown/.test(cloud) && /revisedElsewhere = [^;]*!remoteIsKnown/.test(cloud));
});

// Image tools reach the derivative (original untouched).
check("derivative applies rotation/flip/aspect/adjustments/preset/resolution", () => {
    const f = doc.slice(doc.indexOf("QImage applyPhotoImageEdit("), paintDef);
    for (const k of ["rotation", "flipH", "flipV", "aspect", "brightness", "contrast", "saturation", "warmth", "preset", "resolution"])
        assert.ok(f.includes(`"${k}"`), k);
    assert.ok(doc.includes('const QImage original = applyPhotoImageEdit(originalInput, edit.value(QStringLiteral("image")).toMap());'));
});

// Editor: professional tools, no generic Qt controls.
check("photo editor has no generic Qt controls and exposes the tool tabs", () => {
    for (const legacy of ["TabBar", "TabButton", "ComboBox", "RadioButton", "CheckBox", "Switch", "ToolButton", "Button", "Slider"])
        assert.ok(!new RegExp("(^|[^A-Za-z.])" + legacy + " \\{").test(photoEditor), legacy);
    for (const tab of ["Datos", "Estilo", "Composición", "Logo", "Filtros", "Ajustes", "Avanzado", "Versiones"])
        assert.ok(photoEditor.includes(`["${tab}"`), tab);
    assert.ok(/enter: Transition/.test(photoEditor) && /id: tabSwitch/.test(photoEditor), "animated open + tab switch");
});

// "Después" es la derivada REAL (mismo pipeline C++), no una aproximación QML.
check("editor preview comes from the C++ derivative pipeline (debounced, token-guarded)", () => {
    assert.ok(!photoEditor.includes("MultiEffect") && !photoEditor.includes("QtQuick.Effects"), "no QML approximation");
    assert.ok(photoEditor.includes('doc.requestPhotoPreview(slotIndex, edit, "result")'));
    assert.ok(/function onPhotoPreviewReady\(idx, token, url, error\)[\s\S]{0,300}token === editor\.previewToken/.test(photoEditor));
    assert.ok(/id: previewDebounce; interval: 140/.test(photoEditor) && photoEditor.includes("comparePos"));
    const req = doc.slice(doc.indexOf("int CalicataDocument::requestPhotoPreview"), doc.indexOf("QVariantMap CalicataDocument::suggestAutoWhiteBalance"));
    assert.ok(req.includes("m_photoPreviewPending[idx] = edit") && req.includes("m_photoPreviewLatest[idx] = token"), "coalesced per slot");
    assert.ok(req.includes("CacheLocation") && req.includes("paintPhotoDerivative(original, edit, logo)"), "same painter, cache only");
    for (const forbidden of ["persistPhoto", "setDirty", "emit dataChanged", "versions", "enqueue"])
        assert.ok(!req.includes(forbidden), "preview never creates versions: " + forbidden);
    assert.ok(req.includes("1280"), "preview resolution bounded");
});
check("pipeline implements every image tool on the derivative", () => {
    const f = doc.slice(doc.indexOf("QImage applyPhotoImageEdit("), paintDef);
    for (const k of ["angle", "perspective", "crop", "exposure", "highlights", "shadows", "clarity", "sharpness", "tint",
                     "vignette", "vignetteSize", "vignetteSoftness", "vignetteX", "vignetteY", "presetIntensity", "curve"])
        assert.ok(f.includes(`"${k}"`), k);
    assert.ok(f.includes("QTransform::quadToQuad") && f.includes("photoCurveLut(") && f.includes("photoLocalContrast("));
    for (const p of ["natural", "contrast", "documentary", "technical", "bw"]) assert.ok(f.includes(`"${p}"`), "preset " + p);
    const paint = doc.slice(paintDef, doc.indexOf("int CalicataDocument::requestPhotoPreview"));
    assert.ok(paint.includes('edit.value(QStringLiteral("annotations"))') && paint.includes('edit.value(QStringLiteral("watermark"))'));
    assert.ok(paint.includes('QStringLiteral("tiled")') && paint.includes("logoOpacityPct") && paint.includes("logoMarginPct"));
});
check("coordinates UTM / decimal / DMS come from real sheet data", () => {
    const f = doc.slice(doc.indexOf("QStringList photoOverlayLines("), doc.indexOf("bool photoCurveLut("));
    assert.ok(f.includes('"coordFormat"') && f.includes("photoDmsText(lat, true)") && f.includes("WGS84 (decimal)"));
    assert.ok(/geographic = format != QLatin1String\("utm"\) && okLat && okLon/.test(f), "never invents coordinates");
    for (const k of ["depth", "category", "user"]) assert.ok(new RegExp(`\\{"${k}", "[^"]+", "[^"]*", false\\}`).test(f), k + " off by default");
    const meta = doc.slice(doc.indexOf("QVariantMap CalicataDocument::photoSheetMetadata"), doc.indexOf("int CalicataDocument::requestPhotoPreview"));
    for (const k of ["latitude", "longitude", "depth", "user"]) assert.ok(meta.includes(`meta[QStringLiteral("${k}")]`), k);
    assert.ok(body(form, "photoGeoFromUtm").includes("Rules.utmToGeoForDatum(meta.easting, meta.northing, meta.zone, datum)"));
    assert.ok(body(photoEditor, "freshMetadata").includes("doc.photoSheetMetadata()") && photoEditor.includes("form.photoGeoFromUtm(m)"));
    assert.ok(photoEditor.includes('[["utm", "UTM"], ["decimal", "Decimal"], ["dms", "GMS"]]'));
});
check("interactive crop / perspective / annotation / curves edit the recipe", () => {
    assert.ok(body(photoEditor, "beginCrop").includes('requestBase("geometry")') && body(photoEditor, "commitCrop").includes("n.image.crop = c"));
    assert.ok(photoEditor.includes('[[0, "Libre"], [1, "1:1"], [4 / 3, "4:3"], [16 / 9, "16:9"]]'), "crop aspect presets");
    assert.ok(body(photoEditor, "beginPerspective").includes('requestBase("source")') && body(photoEditor, "commitPerspective").includes("n.image.perspective = p"));
    assert.ok(body(photoEditor, "beginDraw").includes('requestBase("annotate")') && body(photoEditor, "commitDraw").includes("n.annotations = s"));
    for (const t of ['"pen"', '"marker"', '"eraser"']) assert.ok(photoEditor.includes("drawTool === " + t), t);
    assert.ok(photoEditor.includes("function undoStroke()") && photoEditor.includes("function redoStroke()") && photoEditor.includes("editor.pushStrokes([])"));
    assert.ok(photoEditor.includes("function curveSample(") && body(photoEditor, "setCurve").includes("n.image.curve = pts"));
    assert.ok(photoEditor.includes("next.splice(curvePoint.index, 1)"), "remove curve point");
    assert.ok(photoEditor.includes("component ToolHandle") && (photoEditor.match(/delegate: ToolHandle/g) || []).length === 2);
    assert.ok(photoEditor.includes("doc.suggestAutoWhiteBalance(editor.slotIndex)"), "auto white balance");
    assert.ok(/property real resetValue/.test(photoEditor) && /name: "history.restore"[\s\S]{0,400}sl\.committed\(sl\.resetValue\)/.test(photoEditor), "per-slider reset (vector icon)");
    assert.ok(photoEditor.includes("PinchHandler") && photoEditor.includes("onDoubleClicked: editor.setZoom(2.5)"), "pinch + double tap zoom");
});
check("curve preview (JS) is monotone Fritsch–Carlson like the C++ LUT", () => {
    const src = photoEditor.slice(photoEditor.indexOf("function curveSample("), photoEditor.indexOf("    function setCurve("));
    const curveSample = new Function(src + "; return curveSample;")();
    for (let x = 0; x <= 1.0001; x += 0.05) assert.ok(Math.abs(curveSample([[0, 0], [1, 1]], x) - x) < 1e-9, "identity");
    const pts = [[0, 0], [0.25, 0.4], [0.6, 0.62], [1, 1]];
    let prev = -1;
    for (let x = 0; x <= 1.0001; x += 0.01) { const y = curveSample(pts, x); assert.ok(y >= prev - 1e-9 && y >= 0 && y <= 1, "monotone"); prev = y; }
    assert.ok(Math.abs(curveSample(pts, 0.25) - 0.4) < 1e-9 && Math.abs(curveSample(pts, 0.6) - 0.62) < 1e-9, "passes through points");
    assert.ok(doc.includes("t[i] = (m[i - 1] * m[i] <= 0) ? 0 : (m[i - 1] + m[i]) / 2.0") && doc.includes("if (s > 9.0)"), "same tangents in C++");
});
check("draft saves the recipe without rendering or publishing", () => {
    const save = body(photoEditor, "saveDraft");
    assert.ok(save.includes("doc.savePhotoEditDraft(slotIndex, edit)"));
    assert.ok(!save.includes("setPhotoCloudState") && !save.includes("renderDerivedPhoto"));
    const d = doc.slice(doc.indexOf("bool CalicataDocument::savePhotoEditDraft"), doc.indexOf("bool CalicataDocument::renderDerivedPhoto"));
    assert.ok(d.includes('photoSlotKey(idx, QStringLiteral("edit"))') && !d.includes("persistPhoto") && !d.includes("enqueue"));
});
check("viewer and editor open from their card and return to it", () => {
    assert.ok(/"offsetX"; from: editor\.originDX; to: 0/.test(photoEditor) && /"offsetY"; from: 0; to: editor\.originDY/.test(photoEditor));
    const viewer = form.slice(form.indexOf("id: photoViewer"), form.indexOf("id: photoActionsSheet"));
    assert.ok(/"offsetX"; from: photoViewer\.originDX; to: 0/.test(viewer) && /"offsetY"; from: 0; to: photoViewer\.originDY/.test(viewer));
    assert.ok(form.includes("root._photoCardItems[photoCard.slot] = photoCard") && body(form, "photoOriginPoint").includes("mapToItem(null"));
    assert.ok(body(form, "openPhotoEditor").includes("root.photoOriginPoint(idx)"));
    assert.ok(viewer.includes('runPhotoAction("versions"') && viewer.includes('root.photoHasAction(root.activePhotoCategory, "publish")'));
});
check("Android Back closes the photo editor (active tool first) before other surfaces", () => {
    const back = body(form, "handleBack");
    const ed = back.indexOf("root.photoEditorItem.opened");
    assert.ok(ed > 0 && ed < back.indexOf("photoActionsSheet.opened") && ed < back.indexOf("photoViewer.opened"));
    assert.ok(back.includes("if (photoEditor.mode.length) photoEditor.cancelTool(); else photoEditor.close()"));
});

// Fotos: single action source for cards, sheet and Dock; real states.
check("photo actions: one source shared by cards, sheet and Dock", () => {
    const actions = body(form, "photoActions");
    for (const id of ["keepMine", "keepRemote", "retry", "discardSend", "capture", "pick", "view", "edit", "versions", "publish", "empty"])
        assert.ok(actions.includes(`"${id}"`), id);
    assert.ok(body(form, "runPhotoAction").includes('id === "versions") { if (info.hasOriginal) root.openPhotoEditor(idx, 7) }'));
    assert.ok(editorPage.includes("calicatas.photo.act:"), "Dock routes every photo action");
    assert.ok(editorPage.includes('root.formValue(form, "runPhotoCommand")("act:capture")')
              && editorPage.includes('root.formValue(form, "runPhotoCommand")("act:pick")'), "Dock tap uses the same action source");
    assert.ok(editorPage.includes('var actionsFor = root.formValue(form, "photoActions")'));
    assert.ok(editorPage.includes('root.formValue(form, "runPhotoCommand")'));
    assert.ok(form.includes("model: photoActionsSheet.actions") && form.includes("readonly property var actions: root.photoActions(root.photoSheetSlot)"));
});
check("keep remote adopts the remote version; viewer never hard-deletes", () => {
    assert.ok(/id === "keepRemote"[\s\S]{0,300}root\._reconcileMediaCloud\(\)/.test(body(form, "runPhotoAction")));
    const viewer = form.slice(form.indexOf("id: photoViewer"), form.indexOf("id: photoActionsSheet"));
    assert.ok(!viewer.includes("requestClearPhoto") && viewer.includes('runPhotoAction("empty"'));
});
check("Fotos cards: no generic Button; header uses the shared stage header", () => {
    const a = form.indexOf("model: root.photoSlotTitles");
    const b = form.indexOf("MobileStageBody {", a);
    assert.ok(a > 0 && b > a && !/\bButton \{/.test(form.slice(a, b)));
    assert.ok(form.includes("root.stageIndex === 4 ? root.iconPhotosName"));
});

// ---------------- cierre: logo, pipeline único, posición directa, diálogo, iconos
check("one logo resolver for preview, final render and editor thumbnails", () => {
    const resolver = doc.slice(doc.indexOf("QString CalicataDocument::photoLogoPath("), doc.indexOf("QVariantMap CalicataDocument::suggestAutoWhiteBalance"));
    assert.ok(resolver.includes('":/images/ICONO_LOGO_MTC.jpeg"') && resolver.includes('":/images/INGEMA_LOGO_COMPLETO.png"'), "bundled defaults as the UI");
    assert.ok(resolver.includes("logo_mtc_removed") && resolver.includes("m_resourcesBase"), "removed flag + Documents root");
    const launch = doc.slice(doc.indexOf("void CalicataDocument::launchPhotoPreview"), doc.indexOf("QVariantMap CalicataDocument::suggestAutoWhiteBalance"));
    const render = doc.slice(doc.indexOf("bool CalicataDocument::renderDerivedPhoto"), doc.indexOf("bool CalicataDocument::renderDerivedPhoto") + 4000);
    for (const src of [launch, render]) {
        assert.ok(src.includes("photoLogoPath(logoEdit.value(QStringLiteral(\"source\")).toString())"));
        assert.ok(!src.includes("resolveMaybeRelToAbs(logoPath)"), "no second resolver");
    }
    assert.ok(render.includes("La ficha no tiene logo disponible para esta fuente.") && render.includes("No se pudo leer el logo seleccionado."), "never publishes a silently missing logo");
    assert.ok(launch.includes("El logo seleccionado no está disponible en este dispositivo."), "preview warns");
    assert.ok(body(photoEditor, "refreshLogos").includes('doc.photoLogoUrl("PROJECT")') && body(photoEditor, "openFor").includes("doc.setResourcesBase(form.photoResourcesBase())"));
    assert.ok(body(form, "photoResourcesBase").includes("docsCtl.basePath"), "same base as logoAbsUrlFromRel");
    assert.ok(photoEditor.includes("component EdLogoChoice") && photoEditor.includes('text: "Sin logo disponible"'));
    assert.ok(body(photoEditor, "publish").includes("!logoAvailable(edit.logo.source)"));
});
check("capture 'con datos' uses the editor pipeline; no second stamp renderer", () => {
    const header = read("calicatadocument.h");
    assert.ok(!doc.includes("stampPhoto") && !header.includes("stampPhoto"), "legacy stamp renderer removed");
    const persist = doc.slice(doc.indexOf("QUrl CalicataDocument::persistPhoto("), doc.indexOf("bool CalicataDocument::setPhotoFromCache"));
    assert.ok(persist.includes("paintPhotoDerivative(source, initialEdit, QImage())"));
    assert.ok(persist.includes('images[QString("foto%1_edit").arg(idx)] = initialEdit;'), "editor reopens the saved recipe");
    const def = doc.slice(doc.indexOf("QVariantMap CalicataDocument::defaultPhotoEdit("), doc.indexOf("QUrl CalicataDocument::persistStampedPhotoToCache"));
    assert.ok(def.includes("photoSheetMetadata()") && def.includes('"withMetadata")] = withData'));
});
check("logo / watermark / label move directly on the photo (same free position in C++)", () => {
    const paint = doc.slice(paintDef, doc.indexOf("int CalicataDocument::requestPhotoPreview"));
    for (const key of ['style.value(QStringLiteral("labelPos"))', 'watermark.value(QStringLiteral("pos"))', 'style.value(QStringLiteral("logoPos"))'])
        assert.ok(paint.includes("placePhotoOverlayFree(") && paint.includes(key), key);
    const place = body(photoEditor, "placeDragged");
    assert.ok(place.includes("n.style.logoPos = p") && place.includes("n.watermark.pos = p") && place.includes("n.style.labelPos = p"));
    assert.ok(photoEditor.includes("editor.placeDragged((m.x - (width - pw) / 2) / pw, (m.y - (height - ph) / 2) / ph)"), "finger mapped onto the painted derivative");
    assert.ok(photoEditor.includes("delete n.style.logoPos") && photoEditor.includes("delete n.watermark.pos") && photoEditor.includes("delete n.style.labelPos"), "grid returns to fixed anchor");
    assert.ok(/Layout\.preferredHeight: editor\.dp\(48\)/.test(photoEditor), "3x3 cells are comfortable touch targets");
});
check("continuous gestures: live preview (throttle) and one undo entry per gesture", () => {
    assert.ok(/onEditChanged: if \(editor\.visible && editor\.mode === "" && !previewDebounce\.running\) previewDebounce\.start\(\)/.test(photoEditor));
    const change = body(photoEditor, "change");
    assert.ok(change.includes("if (!activeGesture || activeGesture !== lastUndoGesture)"));
    assert.ok(photoEditor.includes("onPressed: function(m) { editor.beginGesture(); sl._dragging = true; _apply(m.x) }"));
});
check("watermark text: comfortable field, live preview, stays above the keyboard", () => {
    assert.ok(photoEditor.includes("component EdTextField") && photoEditor.includes('text: "Hecho"') && photoEditor.includes('icon: "action.close"'));
    assert.ok(photoEditor.includes("onTextEdited: liveCommit.restart()") && photoEditor.includes("editor.ensureFieldVisible(tf)"));
    assert.ok(photoEditor.includes("readonly property bool typing: imeOpen && !!fieldFocusTarget && fieldFocusTarget.editing"));
    assert.ok(/visible: !editor\.typing/.test(photoEditor), "action bar yields to the keyboard");
    assert.ok(/editor\.typing \? Math\.min\(editor\.height \* 0\.28/.test(photoEditor), "preview compacts while typing");
});
check("render lifecycle: BEGIN, RENDER_OK|RENDER_ERROR, END; watchdog; no double render", () => {
    const pub = body(photoEditor, "publish");
    assert.ok(pub.includes("if (!doc || rendering) return") && pub.includes("INGE_CALICATA_OPERATION_BEGIN kind=PHOTO_RENDER"));
    assert.ok(photoEditor.includes('"INGE_CALICATA_OPERATION_END kind="') && photoEditor.includes('_logRenderPhase("RENDER_OK"'));
    assert.ok(photoEditor.includes("id: photoRenderWatchdog") && photoEditor.includes("photoRenderWatchdog.stop()"));
});
check("single photo-data dialog: three actions, no standard No/Yes", () => {
    const dlg = form.slice(form.indexOf("id: tsDlg"), form.indexOf("id: resourcesPicker"));
    assert.ok(!dlg.includes("standardButtons") && !dlg.includes("Button {"), "no Qt standard/generic buttons");
    for (const t of ['"Guardar con datos"; onClicked: tsDlg.resolve(true)', '"Guardar sin datos"; onClicked: tsDlg.resolve(false)', '"Cancelar"; onClicked: tsDlg.resolve(null)'])
        assert.ok(dlg.includes(t), t);
});
check("editor uses vector icons only (no font glyphs that render as boxes)", () => {
    assert.ok(!/\bglyph\s*:/.test(photoEditor));
    const code = photoEditor.split("\n").map(l => l.split("//")[0]).join("\n");
    const risky = [...code].filter(c => c.codePointAt(0) >= 0x2190 || c === "\u2212");
    assert.deepStrictEqual(risky, [], "no arrows/symbols outside Latin text");
    for (const icon of ['icon: "history.restore"', 'icon: "map.zoomOut"', 'icon: "map.zoomIn"', 'icon: "map.layers"', 'icon: "map.recenter"'])
        assert.ok(photoEditor.includes(icon), icon);
});
check("hydration never builds nested ListModel roles (observations is null)", () => {
    const n = body(form, "_normalizeCorte");
    assert.ok(n.includes('typeof o[key] !== "object"') && n.includes("r._extraJson = JSON.stringify(o)"));
});
check("Fotos action bars: flat surfaces, vector icons, same actions", () => {
    const bar = form.slice(form.indexOf("component PhotoBar: Item {"), form.indexOf("component PhotoAmbient:"));
    assert.ok(bar.includes("default property alias content: photoBarContent.data") && bar.includes("enabled: photoBar.absorbTaps"), "bar keeps content slot and tap absorption");
    assert.ok(!bar.includes("LiquidGlassSurface") && !bar.includes("backdrop"), "no glass in the bar");
    const tile = form.slice(form.indexOf("component PhotoActionTile: Item {"), form.indexOf("component LabActionPill"));
    assert.ok(!tile.includes("root.cSurfaceAlt") && tile.includes("gesturePolicy: TapHandler.ReleaseWithinBounds"));
    assert.ok(tile.includes("PhotoBadge {") && tile.includes("property bool divider: false") && tile.includes("visible: tile.divider"), "icon badges + divider");
    const badge = form.slice(form.indexOf("component PhotoBadge: Rectangle {"), form.indexOf("component PhotoActionTile: Item {"));
    assert.ok(badge.includes("Components.FlowIcon") && !badge.includes("Behavior on"), "vector icons, no press animation");
    const cards = form.slice(form.indexOf("model: root.photoSlotTitles"), form.indexOf("MobileStageBody {", form.indexOf("model: root.photoSlotTitles")));
    assert.ok(cards.includes("PhotoAmbient {") && cards.includes("id: photoEmptyPanel") && cards.includes('text: "Sin fotografía"'), "card + empty state");
    assert.ok(cards.includes("root._photoPreviewReady(photoCard.slot, source)"), "photo preview readiness callback kept");
    assert.ok(!cards.includes("maskSource") && !cards.includes("MultiEffect"), "no mask effect");
    for (const a of ['["view", "Ver", "action.search"]', '["edit", "Editar", "action.edit"]', '["capture", "Tomar foto", "action.camera"]', '["pick", "Importar", "documents.upload"]'])
        assert.ok(cards.includes(a), a);
    assert.ok(cards.includes("onClicked: root.runPhotoAction(modelData[0], photoCard.slot)"), "same actions as sheet and action bar");
    assert.ok(!cards.includes('"⋮"') && !cards.includes('"✓ "'), "no font glyphs on cards");
    const viewer = form.slice(form.indexOf("id: photoViewer"), form.indexOf("id: photoActionsSheet"));
    assert.ok(viewer.includes("PhotoBar {") && viewer.includes("onDark: true") && !viewer.includes('text: "‹"'));
    const sheet = form.slice(form.indexOf("id: photoActionsSheet"), form.indexOf("id: stratumSheet"));
    assert.ok(sheet.includes("background: PhotoBar {") && sheet.includes("Overlay.modal: GenScrim { popupItem: photoActionsSheet }"));
    assert.ok(sheet.includes("model: photoActionsSheet.actions") && sheet.includes("PhotoBadge {"), "same actions");
});
console.log(`OK ${passed} checks`);

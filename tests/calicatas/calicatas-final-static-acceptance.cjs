// CALICATAS_FINAL_STATIC_ACCEPTANCE — static checks only (no build, no device).
// node tests/calicatas/calicatas-final-static-acceptance.cjs
const fs = require('fs'), path = require('path'), assert = require('assert'), vm = require('vm');
const root = path.resolve(__dirname, '..', '..');
const read = (p) => fs.readFileSync(path.join(root, p), 'utf8').replace(/\r\n/g, '\n');
const form = read('qml/Mobile/pages/CalicataFormPage.qml');
const editor = read('qml/Mobile/pages/CalicatasEditorPage.qml');
const cloud = read('calicatacloudservice.cpp');
const docCpp = read('calicatadocument.cpp');
const exporter = read('androidcalicataexporter.cpp');
const exportQueue = read('src/cpp/renditionexportservice.h');
const rulesSrc = read('qml/Mobile/lib/CalicataRules.js').replace('.pragma library', '');
let passed = 0;
const check = (name, fn) => { fn(); passed++; console.log('PASS', name); };

function extract(src, name) {
  const i = src.indexOf('function ' + name + '(');
  assert.ok(i >= 0, 'missing function ' + name);
  let depth = 0;
  for (let k = src.indexOf('{', i); k < src.length; ++k) {
    if (src[k] === '{') depth++;
    else if (src[k] === '}' && --depth === 0) return src.slice(i, k + 1);
  }
}
const P = '11111111-1111-4111-8111-111111111111', C = 'aaaaaaaa-2222-4222-8222-222222222222';

// ---------------- P0 ----------------
function editorHarness(tabs, drafts) {
  const log = { loads: [], cloudLoads: [], opened: [], selected: [], syncs: [] };
  const ctx = { console: { info() {} }, String, Number, Date, JSON,
    hydrateTimeout: { restart() {}, stop() {} },
    tabsModel: { get count() { return tabs.length } },
    CalicataCloud: { loadRemoteDocument: (d, p, c) => log.cloudLoads.push([d.id, p, c]),
                     syncDocument: (d, r) => { log.syncs.push([d.id, r]); return 'x' } } };
  const root = { initializationComplete: true, _pendingCloudOpen: null, _remoteLoadingProjectId: '', _remoteLoadingDocId: '',
    _autoSyncDocId: '', _autoSyncCreating: false, _savingCloudDocId: '', _publishingDocId: '', _archivingCloudDocId: '',
    _lastAutoSyncMs: 0, currentDoc: { listProjectDrafts: () => drafts },
    _docAt: i => tabs[i], selectTab: i => log.selected.push(i), _docInstanceId: d => d.id, showMsg() {},
    loadCloudCalicata: row => log.loads.push(row.id), _workspaceCodeConflict: () => '',
    _openLocalDraftTab: (id) => { log.opened.push(id); return { id, syncState: 'SYNCED' } },
    beginOperation: (k) => { log.ops = (log.ops || []).concat([k]); return k + '-1' }, phaseOperation() {}, endOperation() {} };
  ctx.root = root; vm.createContext(ctx);
  vm.runInContext(extract(editor, 'openCloudCalicata') + extract(editor, '_queueAutoCloudSync')
    + ';root.openCloudCalicata=openCloudCalicata;root._queueAutoCloudSync=_queueAutoCloudSync;', ctx);
  return { root, log };
}
check('P0_01 Web ficha never seen opens with the same ids', () => {
  const h = editorHarness([{ id: 't', header: {} }], []); h.root.openCloudCalicata(P, C);
  assert.deepStrictEqual(h.log.loads, [C]);
});
check('P0_02/04 existing local draft of the same UUID is reused (no new draft)', () => {
  const h = editorHarness([{ id: 't', header: {} }], [{ instanceId: 'draft-7', remoteCalicataId: C.toUpperCase() }]);
  h.root.openCloudCalicata(P, C);
  assert.deepStrictEqual(h.log.opened, ['draft-7']); assert.strictEqual(h.log.loads.length, 0);
  assert.strictEqual(h.log.cloudLoads.length, 1); assert.strictEqual(h.log.cloudLoads[0][0], 'draft-7');
});
check('P0_03 open tab bound to UUID is reused; pending local edits are not hydrated over', () => {
  const h = editorHarness([{ id: 'x', header: { remoteCalicataId: C }, dirty: false, syncState: 'PENDING' }], []);
  h.root.openCloudCalicata(P, C);
  assert.deepStrictEqual(h.log.selected, [0]); assert.strictEqual(h.log.cloudLoads.length, 0); assert.strictEqual(h.log.loads.length, 0);
});
check('P0_05/06 automatic draft needs real project + code; one create in flight; CONFLICT never overwritten', () => {
  const h = editorHarness([], []);
  const d = (hd, st) => ({ id: 'd', header: hd, syncState: st, dirty: true, status: 'BORRADOR' });
  h.root._queueAutoCloudSync(d({ code: 'C' }, 'LOCAL'));
  h.root._queueAutoCloudSync(d({ projectId: P, code: 'C' }, 'LOCAL'));
  h.root._queueAutoCloudSync(d({ projectId: P, code: 'C' }, 'LOCAL'));
  assert.strictEqual(h.log.syncs.length, 1);
  h.root._autoSyncDocId = ''; h.root._lastAutoSyncMs = 0;
  h.root._queueAutoCloudSync(d({ projectId: P, code: 'C', remoteCalicataId: C }, 'CONFLICT'));
  assert.strictEqual(h.log.syncs.length, 1);
});
check('P0_07 autosave queues cloud after every local save', () => {
  assert.ok(/INGE_CALICATA_AUTOSAVE_LOCAL[\s\S]{0,200}_queueAutoCloudSync\(doc\)/.test(editor));
});

// ---------------- P1 ----------------
check('P1 remote cache keyed by media id / version id, never a bare filename', () => {
  assert.ok(cloud.includes('"remote_original_") + mediaId') && cloud.includes('"remote_derivada_") + activeVersion'));
});
check('P1 remote adoption refuses to replace an unpublished local edit (conflict)', () => {
  assert.ok(/bool CalicataDocument::adoptRemotePhoto[\s\S]{0,700}if \(unpublished[\s\S]{0,120}return false;/.test(docCpp));
});
check('P1 history / restore (CAS) / discard / empty use the Web RPCs', () => {
  for (const rpc of ['calicata_media_versions', 'set_my_calicata_media_active_version_v01', 'p_expected_row_version',
                     'discard_my_calicata_media_version_v01', 'empty_my_calicata_media_slot_v01', 'object/sign/calicata-media/'])
    assert.ok(cloud.includes(rpc), rpc);
});

// ---------------- P2 ----------------
check('P2 stratum gets a stable local UUID at creation and keeps it on clear', () => {
  assert.strictEqual((form.match(/_extraJson: JSON\.stringify\(\{ local_stratum_id: root\._newLabUuid\(\) \}\)/g) || []).length, 2);
  assert.ok(/function clearCorte[\s\S]{0,600}local_stratum_id: keptIdentity\.local_stratum_id/.test(form));
  // Al aplicar estado remoto no se marca sucio (evita re-emitir lo recibido).
  assert.ok(/root\._assignedStratumIds = false\s*\n\s*if \(!doc \|\| !doc\.applyingCloudState\) root\._markDirty\(\)/.test(form));
});
check('P2 laboratorio = autoridad; fichas antiguas (lab_confirmed_sucs) migran sin inventar', () => {
  const rows = [{ sucs: 'SC', _extraJson: '{"lab_confirmed_sucs":"GW-GM"}' },
                { sucs: 'GW-GM', _extraJson: '{}' }];
  const lab = { JSON, String };
  vm.createContext(lab); vm.runInContext(rulesSrc, lab); lab.Rules = { webSucsCodes: lab.webSucsCodes };
  vm.runInContext(extract(form, '_labAuthority'), lab);
  const x = lab._labAuthority(JSON.parse(rows[0]._extraJson));
  assert.strictEqual(x.primary_sucs + '/' + x.secondary_sucs, 'GW/GM');
  assert.strictEqual(x.is_composite, true);
  // Sin clasificación de laboratorio no se inventa desde el SUCS anterior del estrato.
  const y = lab._labAuthority(JSON.parse(rows[1]._extraJson));
  assert.strictEqual(String(y.primary_sucs || '') + '/' + String(y.secondary_sucs || ''), '/');
  assert.ok(!form.includes('function acceptSuggestedSucs('), 'adoptar escribe el laboratorio, no el estrato');
});

// ---------------- P3 ----------------
check('P3 delete tombstone + adopt remote UUID by local id (never by index)', () => {
  const rows = [{ _extraJson: '{"local_stratum_id":"L1","remote_stratum_id":"R1"}' }, { _extraJson: '{"local_stratum_id":"L2"}' }];
  const doc = { closed: false, header: {} };
  const ctx = { JSON, String, Object, Math, doc, selectedStratum: 0,
    cortesModel: { get count() { return rows.length }, get: i => rows[i], remove: i => rows.splice(i, 1), setProperty: (i, k, v) => rows[i][k] = v },
    commitPendingField: () => true, showInfo() {}, finishStratum() {}, renumerarCortesYIntervalos() {}, _markDirty() {} };
  ctx.root = ctx; vm.createContext(ctx);
  vm.runInContext(extract(form, 'removeCorte') + extract(form, '_adoptStratumIdentity'), ctx);
  ctx._adoptStratumIdentity('L2', 'R2');
  assert.strictEqual(JSON.parse(rows[1]._extraJson).remote_stratum_id, 'R2');
  ctx.removeCorte(0);
  assert.deepStrictEqual(JSON.parse(JSON.stringify(doc.header.deleted_remote_strata)), ['R1']);
});
check('P3 CAS delete, immediate identity bind, no index fallback, bounded recursion', () => {
  assert.ok(/delete_my_calicata_stratum_v02[\s\S]{0,400}p_expected_calicata_row_version[\s\S]{0,200}p_confirm_nonempty/.test(cloud));
  assert.ok(cloud.includes('bindStratumIdentity(localStratumId, id)'));
  assert.ok(!cloud.includes('no se permite recuperar identidad por posición'));
  assert.ok(cloud.includes('++ctx->strataPasses > 64') && cloud.includes('weakSyncStrata.lock()'));
  assert.ok(docCpp.includes('"deleted_remote_strata_confirmed"'));
});

// ---------------- P4 ----------------
check('P4 Web -> Android refreshes the aliases the UI reads; 18L local / 18 cloud', () => {
  for (const pair of ['{"easting", "utm_x"}', '{"northing", "utm_y"}', '{"altitude_m", "utm_z"}', '{"progresiva", "pk"}',
                      '{"machine", "maquina"}', '{"start_date", "fecha_inicio"}', '{"end_date", "fecha_fin"}', '{"location", "lado_via"}'])
    assert.ok(docCpp.includes(pair), pair);
  assert.ok(cloud.includes('canonicalUtmZone(value("utm_zone", "zona"))'));
  const r = {}; vm.createContext(r); vm.runInContext(rulesSrc, r);
  const a = r.utmToGeo('500000', '8500000', '18L'), b = r.utmToGeo('500000', '8500000', '18');
  assert.ok(a && b && a.latitude < 0 && Math.abs(a.latitude - b.latitude) < 1e-9);
});

// ---------------- P5 ----------------
check('P5 logo cloud versions, restore = republish, cache keyed by media id', () => {
  assert.ok(form.includes('cloudLogoHistory') && form.includes('function restoreCloudLogo'));
  assert.ok(/function onRemoteLogoRestored[\s\S]{0,400}_storeLogoRelative/.test(form));
  assert.ok(cloud.includes('"logo_%1_%2_%3"'));
});

// ---------------- P6 ----------------
check('P6 activity only uses real Web actions (42501 fix) and refreshes the timeline', () => {
  for (const a of ['"ADD_STRATUM"', '"DELETE_STRATUM"', '"UPLOAD_PHOTO_VERSION"']) assert.ok(!cloud.includes(a), a);
  assert.ok(form.includes('function onPendingActivityChanged() { activityRefresh.restart() }'));
});
check('P6 PDF flow exists, paginates and publishes through the persistent export queue', () => {
  assert.ok(form.includes('function exportPdfFlow()'));
  assert.ok(exporter.includes('QString AndroidCalicataExporter::exportCalicataToPdf') && exporter.includes('newPageIfNeeded'));
  const pdfPublish = exporter.slice(exporter.indexOf('bool AndroidCalicataExporter::publishCalicataPdf'));
  assert.ok(pdfPublish.includes('enqueueDocument(pdfPath, project, remotePdf'));
});
check('P6 export dedup: project + logical path + content hash, isolated Google provider', () => {
  assert.ok(exportQueue.includes("const QString id=digest((project+'/'+logicalPath+'/'+hash"));
  assert.ok(exportQueue.includes('+(provider=="GOOGLE_DRIVE"?"/GOOGLE_DRIVE":QString())).toUtf8());'));
  assert.ok(exportQueue.includes('if(m_rows.contains(id))'));
});
check('P6 presence: Web contract over RFC 6455, heartbeat, token refresh, leave, backoff', () => {
  for (const s of ['realtime:calicata:', '"phx_join"', 'config[QStringLiteral("private")] = true', '"heartbeat"', '"access_token"',
                   '"untrack"', '"phx_leave"', '"presence_state"', '"presence_diff"', 'Sec-WebSocket-Key', 'kPresenceRetryMs'])
    assert.ok(cloud.includes(s), s);
  assert.ok(form.includes('CalicataCloud.setPresenceActive(Qt.application.state === Qt.ApplicationActive)'));
});


// ---------------- RUNTIME ROUND: operations, export, warnings ----------------
const overlay = read('qml/Mobile/pages/CalicataOperationOverlay.qml');
const photo = read('qml/Mobile/pages/CalicataPhotoEditor.qml');
const exportFn = extract(editor, 'exportCurrentExcel');
const finishFn = extract(editor, '_finishExcelExport');
check('R01 PROJECT_LOAD begins on selection and ends on workspace resolved/failed', () => {
  assert.ok(form.includes('beginOperation("PROJECT_LOAD"') && /function onWorkspaceResolved[\s\S]{0,200}endOperation\(root\._projectOperationId, "OK"\)/.test(form));
  assert.ok(/function onWorkspaceResolveFailed[\s\S]{0,300}"ERROR"/.test(form));
});
check('R02/R18 CALICATA_OPEN covers the editor and ends on HYDRATE_OK / failure (atomic reveal)', () => {
  assert.ok(editor.includes('beginOperation("CALICATA_OPEN", "Abriendo ficha…"') && editor.includes('cover: true'));
  assert.ok(/hydrateTimeout\.stop\(\)\s*\n\s*if \(root\.foregroundOperation && root\.foregroundOperation\.kind === "CALICATA_OPEN"\)\s*\n\s*root\.endOperation\(root\.foregroundOperation\.id, "OK"\)/.test(editor));
  assert.ok(editor.includes('kind: "APP_INIT"') && editor.includes('title: "Preparando Calicatas"'));
  assert.ok(/initializationComplete = true\s*\n\s*if \(root\.foregroundOperation && root\.foregroundOperation\.kind === "APP_INIT"\)\s*\n\s*root\.endOperation\(root\.foregroundOperation\.id, "OK"\)/.test(editor));
});
check('R03 fast operation never flashes; min visible; no negative timer', () => {
  assert.ok(overlay.includes('property int showDelayMs: 150') && overlay.includes('property int minVisibleMs: 380'));
  assert.ok(overlay.includes('hideTimer.interval = Math.max(1, minVisibleMs - (Date.now() - shownAt))'));
});
check('R04 failed operation exposes retry', () => {
  assert.ok(editor.includes('{ id: "retry", label: "Reintentar" }') && editor.includes('actionId === "retry" && typeof op.retry === "function"'));
});
check('R05 autosave never opens the full-screen loader', () => {
  const autosave = extract(editor, 'autoSaveCurrentM09') + extract(editor, '_queueAutoCloudSync');
  assert.ok(!autosave.includes('beginOperation'));
});
check('R06-R08/R15 export is never gated by review (empty, blockers, warnings, PDF)', () => {
  assert.ok(!exportFn.includes('reviewForExport') && !exportFn.includes('stageIndex !== 5'));
  assert.ok(!exporter.includes('if (!blocker.isEmpty()) { setLastError(blocker); return false; }'));
  assert.ok(exporter.includes('INGE_CALICATA_EXPORT_ADVISORY'));
  assert.ok(extract(form, 'exportExcelFlow').includes('INGE_CALICATA_EXPORT_ADVISORY'));
  assert.ok(!extract(form, '_runPdfExport').includes('_validateExportState'));
});
check('R09 repeated tap = one flow (command-layer guard)', () => {
  const log = [];
  const ctx = { console: { info: m => log.push(m), warn() {} }, root: { _exportFlowActive: true, exportBusy: false, _exportPreparing: false, _publishingDocId: '' } };
  vm.createContext(ctx); vm.runInContext(exportFn + ';root.run = exportCurrentExcel;', ctx);
  for (let i = 0; i < 20; ++i) ctx.root.run();
  assert.strictEqual(log.filter(m => m === 'INGE_CALICATA_EXPORT_IGNORED_ALREADY_RUNNING').length, 20);
});
check('R10/R11 XLSX generated with blanks; offline still queued', () => {
  const syncFailed = extract(editor, 'onSyncFailed');
  const publishingBranch = syncFailed.slice(syncFailed.indexOf('if (localDocumentId === root._publishingDocId)'));
  assert.ok(publishingBranch.length < syncFailed.length);
  assert.ok(/pendingXlsx\.length\) \{\s*\n\s*var queuedOffline = ExcelExporter\.publishCalicata\(/.test(publishingBranch));
  assert.ok(/root\._publishingDocId = ""[\s\S]{0,80}root\._pendingCloudXlsxPath = ""/.test(publishingBranch), 'guard released on offline failure');
  assert.ok(finishFn.includes('ExcelExporter.publishCalicata(doc.portableState('));
});
check('R12 result exposes the InGeDrive logical path, not the device path', () => {
  assert.ok(finishFn.includes('"InGeDrive: " + drivePath') && finishFn.includes('result.remoteLogicalPath'));
});
check('R13 export never auto-opens; R14 published workbook is viewed from InGeDrive', () => {
  assert.strictEqual((finishFn.match(/openLastExport\(false\)/g) || []).length, 0);
  assert.ok(finishFn.includes('descárgalo desde InGeDrive para verlo.'));
  assert.ok(!finishFn.includes('label: "Abrir archivo"'));
});
check('R16 sample roles are always typed (no undefined roles on hydrate)', () => {
  assert.strictEqual((form.match(/remote_sample_id: "",\n\s*sample_code: "",/g) || []).length, 2);
});
check('R17 photo render/publish/restore report a final state (no endless spinner)', () => {
  assert.ok(photo.includes('kind: "PHOTO_RENDER"') && photo.includes('kind: "MEDIA_RESTORE"'));
  // P0 Fotos: el render termina en un estado local final (LOCAL_OK) y el editor se cierra;
  // la publicación sigue en el outbox de Media (sin espinner esperando a Storage).
  assert.ok(!photo.includes('kind: "PHOTO_UPLOAD"') && photo.includes('result=LOCAL_OK publish='));
  // Restaurar versión (primer plano) sigue acotado por el timeout.
  assert.ok(photo.includes('photoPublishTimeout') && photo.includes('editor.photoOperation.kind === "MEDIA_RESTORE"'));
});

// ---------------- FINAL RUNTIME ROUND: back crash, dock, PDF, placeholder ----------------
const mainQml = read('qml/Mobile/Main.qml');
const docsCpp = read('src/documents/nothingdocuments.cpp');
check('C01 Back from Calicatas is deferred and releases input first (no destroy in delivery)', () => {
  assert.ok(mainQml.includes('if (pageIndex === 1) return leaveCalicatasSafely()'));
  assert.ok(/id: calicataLeaveTimer\s*\n\s*interval: 48/.test(mainQml));
  const prep = extract(editor, 'prepareForLeave');
  assert.ok(prep.includes('root.enabled = false') && prep.includes('releaseInputForLeave'));
  const rel = extract(form, 'releaseInputForLeave');
  assert.ok(rel.includes('vFlick.cancelFlick()') && rel.includes('vFlick.interactive = false'));
  assert.ok(/onRequestBack:[\s\S]{0,300}app\.leaveCalicatasSafely\(\)/.test(mainQml));
});
check('C02 Back x5 = one leave (reentrancy guard)', () => {
  const log = []; let restarts = 0;
  const ctx = { console: { info: m => log.push(m) }, calicataLeaveTimer: { restart: () => restarts++ },
                app: { activeCalicataEditor: { prepareForLeave: () => ({ touchActive: true, flickActive: true }) } }, leavingCalicatas: false };
  vm.createContext(ctx); vm.runInContext(extract(mainQml, 'leaveCalicatasSafely'), ctx);
  for (let i = 0; i < 5; ++i) ctx.leaveCalicatasSafely();
  assert.strictEqual(restarts, 1); assert.strictEqual(log.filter(m => m.startsWith('INGE_CALICATA_LEAVE_IGNORED')).length, 4);
  assert.ok(/function handleBackNavigationV41\(nativeRequest\) \{\s*\n\s*\/\/[^\n]*\n\s*if \(leavingCalicatas\)/.test(mainQml));
});
check('C03 empty placeholder never autosaves / syncs', () => {
  const ctx = { String }; vm.createContext(ctx); vm.runInContext(extract(editor, '_isPlaceholderDoc'), ctx);
  assert.strictEqual(ctx._isPlaceholderDoc({ header: {}, cortes: [{}], images: {} }), true);
  assert.strictEqual(ctx._isPlaceholderDoc({ header: { projectId: P }, cortes: [], images: {} }), false);
  assert.strictEqual(ctx._isPlaceholderDoc({ header: {}, cortes: [{ descripcion: 'arcilla' }], images: {} }), false);
  assert.ok(/_syncFormIntoDoc\(doc, false\)\) return false\s*\n\s*if \(root\._isPlaceholderDoc\(doc\)\) return true/.test(editor));
});
check('C04 stale async callbacks are dropped after leave', () => {
  const prep = extract(editor, 'prepareForLeave');
  assert.ok(prep.includes('hydrateTimeout.stop()') && prep.includes('exportKickoff.task = null') && prep.includes('root.foregroundOperation = null'));
  for (const fn of ['openCloudCalicata', 'exportCurrentExcel', '_queueAutoCloudSync', 'handleBack'])
    assert.ok(extract(editor, fn).includes('root.leaving'), fn);
});
check('C05-C07 blocking operation suppresses the Dock; end/error/leave restore it', () => {
  assert.ok(mainQml.includes('&& !(app.pageIndex === 1 && app.calicataDockSuppressed)'));
  assert.ok(editor.includes('readonly property bool dockSuppressed: operationOverlay.shown'));
  assert.ok(mainQml.includes('onDockSuppressedChanged: app.setCalicataDockSuppressed(dockSuppressed'));
  assert.ok(/Component\.onDestruction: \{[\s\S]{0,200}app\.setCalicataDockSuppressed\(false, ""\)/.test(mainQml));
  assert.ok(/INGE_CALICATA_LEAVE_EXECUTE"\)\s*\n\s*app\.setCalicataDockSuppressed\(false, ""\)/.test(mainQml));
  assert.ok(overlay.includes('hideTimer; interval: 1; repeat: false; onTriggered: overlay.shown = false'));
});
const pdfRun = extract(form, '_runPdfExport');
check('C08-C10 PDF opens once, share via safe bridge, missing viewer keeps file', () => {
  assert.strictEqual((pdfRun.match(/openExportedFile\(path, false\)/g) || []).length, 1);
  assert.ok(pdfRun.includes('filePath: path') && pdfRun.includes('{ id: "share", label: "Compartir" }'));
  const openFile = exporter.slice(exporter.indexOf('bool AndroidCalicataExporter::openExportedFile'));
  assert.ok(openFile.includes('com/ingema/ingeplus/NothingFileBridge') && !openFile.includes('"file://'));
  assert.ok(pdfRun.includes('No hay un visor de PDF compatible; el archivo se conserva.'));
  assert.ok(extract(editor, '_operationAction').includes('root.foregroundOperation = op'));
});
check('C11 external viewer pause/resume does not cancel exports', () => {
  const stateHandlers = (form + editor).split('function onStateChanged()').slice(1).map(x => x.slice(0, 400));
  for (const h of stateHandlers) assert.ok(!/endOperation|_exportFlowActive|foregroundOperation\s*=/.test(h));
});
check('C12 .calicata (and .calicata.json) opens through Smart Document access', () => {
  assert.ok(docsCpp.includes('endsWith(".calicata")') && docsCpp.includes('endsWith(".calicata.json")'));
  assert.ok(/get_smart_document_access_v01[\s\S]{0,1400}emit calicataOpenRequested\(projectId,targetId\)/.test(docsCpp));
});
check('C13/C14 overlay blocks input only while visible', () => {
  assert.ok(overlay.includes('readonly property bool blocking: shown && (!displayed || displayed.blocking !== false)'));
  assert.ok(/MouseArea \{\s*\n\s*anchors\.fill: parent\s*\n\s*enabled: overlay\.blocking/.test(overlay));
  assert.ok(overlay.includes('visible: opacity > 0.001'));
  assert.ok(photo.includes('contentItem: Item {') && /ColumnLayout \{\s*\n\s*anchors\.fill: parent/.test(photo));
});
check('C15 repeated PDF tap = one job', () => {
  const log = [];
  const ctx = { console: { info: m => log.push(m) }, root: { _pdfExporting: true, operationHost: null } };
  vm.createContext(ctx); vm.runInContext(extract(form, 'exportPdfFlow') + ';root.run = exportPdfFlow;', ctx);
  for (let i = 0; i < 10; ++i) ctx.root.run();
  assert.strictEqual(log.filter(m => m === 'INGE_CALICATA_EXPORT_IGNORED_ALREADY_RUNNING format=PDF').length, 10);
});

// ---------------- RA / Excel identity / FileProvider / local-first ----------------
const profileQml = read('qml/Mobile/pages/CalicataProfile.qml');
const bridge = read('android/src/com/ingema/ingeplus/NothingFileBridge.java');
// Convergencia Web (feature/calicatas-cloud-media-04a): la trama, el SUCS y el
// AASHTO del perfil y del reporte son la clasificación del laboratorio
// (resolveCalicataSucsPattern / exportModel). La trama RA solo Android ya no
// sustituye esa clasificación; el origen del estrato se conserva como dato.
check('RA: el origen antrópico se conserva pero no sustituye la clasificación del laboratorio', () => {
  const r = {}; vm.createContext(r); vm.runInContext(rulesSrc, r);
  const cls = r.exportClassification({ material_origin: 'Relleno antrópico', sucs: 'GM', primary_sucs: 'SM' });
  assert.strictEqual(cls.label, 'SM');
  assert.strictEqual(r.exportClassification({ material_origin: 'Relleno antrópico', sucs: 'GM' }).label, 'GM');
  const setter = extract(form, 'setStratumOrigin');
  assert.ok(setter.includes('cortesModel.setProperty(index, "material_origin", value)'));
  assert.ok(!/setProperty\(index, "sucs"/.test(setter), 'origin never rewrites stored SUCS');
  assert.ok(extract(form, 'stratumPatternFilesFor').includes('Rules.labProjection(plain).pattern.layers'));
  assert.ok(!/usesRaPattern|kReportRaPattern/.test(exporter));
});
check('XLS01-XLS03 project name and testification are distinct and both written', () => {
  // AG4 = projects.name (Web exportModel.projectName); el nombre antiguo de la
  // ficha solo si aún no tiene proyecto asignado.
  assert.ok(exporter.includes('QString title = exportProjectName(header, timestamp);')
            && exporter.includes('xlsx.write(QStringLiteral("AG4"), title, titleFmt);'));
  assert.ok(exporter.includes('firstText(header, { QStringLiteral("description") })') && /xlsx\.write\(QStringLiteral\("AG1"\), QStringLiteral\("TESTIFICACIÓN DE CALICATA[^"]*"\) \+ testification/.test(exporter));
});
check('URI01-URI04 read grant on target and chooser, ClipData, explicit grants, resolvable activity first', () => {
  assert.ok(bridge.includes('queryIntentActivities(target, PackageManager.MATCH_DEFAULT_ONLY)'));
  assert.ok(bridge.includes('if (receivers == null || receivers.isEmpty()) return "No hay una aplicación compatible instalada."'));
  assert.ok(bridge.includes('context.grantUriPermission(receiver.activityInfo.packageName, uri,'));
  assert.ok(/launch = Intent\.createChooser[\s\S]{0,200}launch\.setClipData[\s\S]{0,80}launch\.addFlags\(Intent\.FLAG_GRANT_READ_URI_PERMISSION\)/.test(bridge));
  assert.ok(bridge.includes('"pdf".equals(ext) ? "application/pdf"') && bridge.includes('spreadsheetml.sheet'));
  assert.ok(!read('android/AndroidManifest.xml').match(/nothingfiles"[\s\S]{0,200}android:exported="true"/));
});
check('PERF01-PERF03 stratum commit is local-first; flush deferred and coalesced', () => {
  const fin = extract(form, 'finishStratum');
  assert.ok(fin.indexOf('stratumSheet.close()') < fin.indexOf('_scheduleFlush') && !fin.includes('flushRequested()'));
  assert.ok(extract(form, 'goPreviousStage').includes('_scheduleFlush') && !extract(form, 'goPreviousStage').includes('flushRequested()'));
  assert.ok(extract(form, '_scheduleFlush').includes('if (!deferredFlush.running)'));
});
check('TIMER01 app-controlled timers never receive a negative interval', () => {
  assert.ok(overlay.includes('Math.max(1, minVisibleMs'));
  assert.ok(!/interval:\s*-|\.interval\s*=\s*[^M\n]*-\s*\(Date/.test(form + editor + mainQml.replace('Math.max(1, 240 - elapsed)', '')));
});

console.log('CALICATAS_FINAL_STATIC_ACCEPTANCE PASS ' + passed + ' checks');

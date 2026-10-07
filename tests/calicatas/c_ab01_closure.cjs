// Interpreted only: node tests/calicatas/c_ab01_closure.cjs
// Cierre C-AB-01: altitud (servicio de elevación del backend + Gemini validador),
// fecha/hora de las fotos, persistencia remota y coordinador de sincronización (40001).
// La lectura real del DEM vive en supabase/functions/resolve-calicata-elevation/handler.test.mjs.
'use strict';
const fs = require('node:fs');
const vm = require('node:vm');
const assert = require('node:assert/strict');
const path = require('node:path');
const root = path.resolve(__dirname, '../..');
const read = file => fs.readFileSync(path.join(root, file), 'utf8').replace(/\r\n/g, '\n');
function library(file) {
    const context = vm.createContext({});
    vm.runInContext(read(file).replace(/^\.pragma library\s*/m, ''), context);
    return context;
}
const elevation = library('qml/Mobile/lib/CalicataElevation.js');
const rules = library('qml/Mobile/lib/CalicataRules.js');
const form = read('qml/Mobile/pages/CalicataFormPage.qml');
const editorPhoto = read('qml/Mobile/pages/CalicataPhotoEditor.qml');
const doc = read('calicatadocument.cpp');
const cloud = read('calicatacloudservice.cpp');
const policy = read('calicatasyncpolicy.h');
function block(source, start, end) {
    const i = source.indexOf(start);
    assert.ok(i >= 0, 'falta ' + start);
    const j = source.indexOf(end, i + start.length);
    return source.slice(i, j < 0 ? undefined : j);
}
const plain = value => JSON.parse(JSON.stringify(value));
let count = 0;
async function test(name, fn) { await fn(); ++count; console.log('PASS ' + name); }

// C-AB-01: 18L 661554 E 8561476 N (conversión canónica de la ficha).
const point = rules.utmToGeo('661554', '8561476', '18L');
const NOW = '2026-10-07T18:00:00.000Z';
// Respuesta real del backend para C-AB-01 (handler.test.mjs, Copernicus leído el 2026-10-07).
const serverResult = (overrides = {}) => Object.assign({
    ok: true, elevation_m: 706.4, vertical_reference: 'terrain_msl', source: 'DEM',
    provider: 'Copernicus DEM GLO-30 (ESA, AWS Open Data)', confidence: 'ALTA', accuracy_m: 4,
    status: 'consistent', warning: '', resolved_at: NOW,
    evidence: [{ id: 'copernicus_glo30', provider: 'Copernicus DEM GLO-30 (ESA, AWS Open Data)', value: 706.4, vertical_reference: 'terrain_msl', accuracy_m: 4, resolution_m: 30 },
               { id: 'copernicus_glo90', provider: 'Copernicus DEM GLO-90 (ESA, AWS Open Data)', value: 707.4, vertical_reference: 'terrain_msl', accuracy_m: 4, resolution_m: 90 }],
    assessment: { by: 'gemini' } }, overrides);

(async () => {
// =================================================================== ALTITUD
await test('ALTITUD 6 · Z manual sobrevive a la resolución automática salvo confirmación', async () => {
    for (const header of [{ utm_z: '747', altitude_source: 'MANUAL' }, { utm_z: '718' }]) {   // 718 legado = manual
        assert.equal(elevation.isManual(header), true);
        assert.equal(elevation.autoWriteAllowed(header), false);
        const decision = plain(elevation.outcome(serverResult(), header, 'explicit', NaN, NOW));
        assert.equal(decision.action, 'confirm', 'nunca se reemplaza sin confirmar');
    }
    const resolver = block(form, 'function resolveAltitude(trigger, deviceAltitude, deviceAccuracy)', 'function _applyAltitudePatch(');
    assert.ok(/if \(trigger !== "explicit" && !Elevation\.autoWriteAllowed\(doc\.header\)\)/.test(resolver), 'automático no consulta sobre Z manual');
    assert.ok(/if \(context\.trigger !== "explicit" && !Elevation\.autoWriteAllowed\(h\)\)/.test(resolver), 're-chequeo al llegar el resultado');
    assert.ok(/decision\.action === "confirm"\) \{[\s\S]*?altitudeReplaceDialog\.open\(\)/.test(resolver));
    assert.ok(form.includes('text: "Usar automática"') && form.includes('text: "Ingresar manual"'));
    assert.equal(plain(elevation.manualHeaderPatch('747')).altitude_mode, 'MANUAL');
    assert.ok(form.includes('commitHandler: function(t) { root._applyAltitudePatch(Elevation.manualHeaderPatch(t)) }'));
});
await test('ALTITUD 7 · coordenadas -> backend (Android nunca consulta proveedores)', async () => {
    const body = plain(elevation.requestBody({ utm_z: '747', altitude_source: 'MANUAL' }, { lat: point.latitude, lon: point.longitude }, 747.2, 5));
    assert.deepEqual(body, { latitude: point.latitude, longitude: point.longitude, gpsAltitude: 747.2, gpsVerticalReference: 'ellipsoid',
                             gpsAccuracy: 5, referenceAltitude: 747, referenceSource: 'Cota manual de la ficha' });
    const lib = read('qml/Mobile/lib/CalicataElevation.js').replace(/\/\/.*$/gm, '');
    assert.ok(!/https?:\/\/|XMLHttpRequest|opentopodata|open-meteo|amazonaws/i.test(lib), 'sin proveedores en el cliente');
    assert.ok(!/XMLHttpRequest|opentopodata|open-meteo/i.test(form), 'la página tampoco consulta proveedores');
    assert.ok(form.includes('CalicataCloud.resolveElevation(requestId, body)'));
    assert.ok(cloud.includes('"/functions/v1/resolve-calicata-elevation"') && cloud.includes('auth->accessToken(), 25000'));
    const apply = block(form, 'function _applyCoordsFromGps(', 'function _openCurrentCoordinateInEarth');
    assert.ok(apply.includes('root.resolveAltitude("location", deviceAltitude)'));
    assert.ok(form.includes('onClicked: root.resolveAltitude("explicit", NaN)') && form.includes('"Obtener altitud"'));
    assert.ok(/id: elevationWatchdog\s*interval: 25000/.test(form), 'nunca bloquea: 25 s y luego manual');
});
await test('ALTITUD 8 · evidencias y metadato se guardan (header = columnas remotas)', async () => {
    const decision = plain(elevation.outcome(serverResult(), { utm_z: '' }, 'location', NaN, NOW));
    assert.equal(decision.action, 'apply');
    assert.deepEqual(Object.keys(decision.patch).sort(), ['altitud', 'altitude_accuracy_m', 'altitude_confidence', 'altitude_evidence', 'altitude_m',
        'altitude_mode', 'altitude_resolved_at', 'altitude_source', 'altitude_source_detail', 'altitude_vertical_reference', 'utm_z']);
    assert.equal(decision.patch.altitude_m, '706.4');
    assert.equal(decision.patch.altitude_vertical_reference, 'terrain_msl');
    assert.equal(decision.patch.altitude_evidence.length, 2);
    for (const column of ['altitude_source', 'altitude_mode', 'altitude_confidence', 'altitude_accuracy_m', 'altitude_vertical_reference',
                          'altitude_resolved_at', 'altitude_evidence', 'start_time'])
        assert.ok(cloud.includes('changes[QStringLiteral("' + column + '")]'), 'CAS sube ' + column);
    assert.match(elevation.statusText(decision.patch), /^706\.4 m · Automática · DEM \(Copernicus DEM GLO-30/);
});
await test('ALTITUD 9 · el número del cliente sale solo de la respuesta (evidencias), nunca de texto', async () => {
    const decision = plain(elevation.outcome(serverResult({ status: 'discrepant', warning: 'La referencia indica 747 m. Existe una diferencia de 41 m con la cota automática (706.4 m).' }),
                                             { utm_z: '747', altitude_source: 'MANUAL' }, 'explicit', NaN, NOW));
    assert.equal(decision.patch.utm_z, '706.4');
    assert.ok(decision.patch.altitude_evidence.some((e) => e.value === 706.4));
    const lib = read('qml/Mobile/lib/CalicataElevation.js');
    assert.ok(!/parseFloat\(.*warning|Number\(.*warning/.test(lib), 'el aviso nunca se convierte en número');
});
await test('ALTITUD 10 · discrepancia (C-AB-01 747 vs DEM) => aviso y decisión', async () => {
    const warning = 'La referencia indica 747 m. Existe una diferencia de 41 m con la cota automática (706.4 m).';
    const decision = plain(elevation.outcome(serverResult({ status: 'discrepant', confidence: 'MEDIA', warning }), { utm_z: '' }, 'location', NaN, NOW));
    assert.equal(decision.action, 'confirm', 'con discrepancia decide el técnico aunque la Z esté vacía');
    const text = elevation.decisionText({ utm_z: '747', altitude_source: 'MANUAL' }, decision);
    assert.match(text, /Cota automática: 706\.4 m/);
    assert.match(text, /Fuente: Automática · DEM/);
    assert.match(text, /Advertencia: La referencia indica 747 m\. Existe una diferencia de 41 m/);
    assert.ok(form.includes('"\\nAdvertencia: " + root.elevationWarning'));
});
await test('ALTITUD 11 · backend caído => edición manual (o GPS elipsoidal si no hay Z manual)', async () => {
    const down = plain(elevation.outcome({ ok: false, error: 'Sin conexión con el servicio de altitud. Ingresa la cota manualmente.' }, { utm_z: '747', altitude_source: 'MANUAL' }, 'explicit', NaN, NOW));
    assert.equal(down.action, 'none');
    assert.match(down.message, /Ingresa la cota manualmente/);
    const gps = plain(elevation.outcome({ ok: false }, { utm_z: '' }, 'location', 747.2, NOW));
    assert.equal(gps.action, 'apply');
    assert.equal(gps.patch.altitude_source, 'GPS_ELIPSOIDAL');
    assert.equal(gps.patch.altitude_vertical_reference, 'ellipsoid');
    assert.match(elevation.statusText(gps.patch), /GPS · altura elipsoidal \(no m\.s\.n\.m\.\)/);
    assert.equal(plain(elevation.outcome({ ok: false }, { utm_z: '747', altitude_source: 'MANUAL' }, 'location', 747.2, NOW)).action, 'none',
                 'el GPS nunca pisa una Z manual');
    assert.ok(doc.includes('QStringLiteral("Altitud GPS: %1 m (elipsoidal)")'));
});
await test('ALTITUD 12 · pull cross-device conserva valor y metadato', async () => {
    const adopt = block(doc, 'bool CalicataDocument::applyCloudSync(', 'void CalicataDocument::setUiState');
    for (const column of ['start_time', 'altitude_source', 'altitude_mode', 'altitude_confidence', 'altitude_accuracy_m',
                          'altitude_vertical_reference', 'altitude_resolved_at', 'altitude_evidence'])
        assert.ok(adopt.includes('QStringLiteral("' + column + '")'), 'pull adopta ' + column);
    assert.ok(adopt.includes('{"start_time", "hora_inicio"}') && adopt.includes('{"altitude_m", "utm_z"}'));
    for (const select of cloud.match(/"id,project_id,code,title[^"]*"/g))
        assert.ok(select.includes('start_time') && select.includes('altitude_evidence'), 'select remoto completo');
    const migration = read('supabase/migrations/20261007181000_calicata_altitude_time_metadata.sql');
    assert.ok(migration.includes('ADD COLUMN IF NOT EXISTS start_time time') && migration.includes('ADD COLUMN IF NOT EXISTS altitude_evidence jsonb'));
});

// =================================================================== ERROR 2
await test('FECHA/HORA A · fecha ficha 13/03/26 + hora 20:06:33 => rótulo 13/03/26 20:06:33', async () => {
    assert.equal(rules.normalizeOptionalTime('20:06:33'), '20:06:33');
    assert.equal(rules.normalizeOptionalTime('9:42'), '09:42:00');
    assert.equal(rules.normalizeOptionalTime(''), '');
    for (const bad of ['25:00', '20:61:00', 'abc', '20:06:33:1']) assert.equal(rules.normalizeOptionalTime(bad), null);
    assert.ok(form.includes('headerKey: "hora_inicio"') && form.includes('label: "Hora (opcional)"'));
    const apply = block(doc, 'void applyPhotoCapture(', '} // namespace');
    assert.ok(apply.includes('"fecha_inicio"') && apply.includes('sheetTime(header)'));
    // El rótulo convierte dd/MM/yyyy -> dd/MM/yy ("13/03/26  20:06:33").
    assert.ok(doc.includes('date.isValid() ? date.toString(QStringLiteral("dd/MM/yy"))') && doc.includes('when.join(QStringLiteral("  "))'));
});
await test('FECHA/HORA B · hora vacía => fecha ficha + hora del sistema fijada para la foto', async () => {
    const capture = block(doc, 'QVariantMap photoCaptureMeta(', 'void mergeCaptureLocation(');
    assert.ok(capture.includes('capture[QStringLiteral("system_time")] = receivedAt.toString(QStringLiteral("HH:mm:ss"))'));
    const apply = block(doc, 'void applyPhotoCapture(', '} // namespace');
    assert.ok(/manual\.isValid\(\) \? manual\.toString\(QStringLiteral\("HH:mm:ss"\)\) : photoSystemTime\(capture\)/.test(apply));
});
await test('FECHA/HORA C · regenerar más tarde conserva la hora fijada', async () => {
    const ensure = block(doc, 'bool CalicataDocument::ensurePhotoSystemTime(int idx)', '\n}\n');
    assert.ok(/if \(QTime::fromString\(capture\.value\(QStringLiteral\("system_time"\)\)\.toString\(\), QStringLiteral\("HH:mm:ss"\)\)\.isValid\(\)\)\s*return true;/.test(ensure),
              'una hora ya fijada nunca se reescribe');
    assert.ok(ensure.includes('commitPhotoImages(images)'), 'la primera determinación se persiste');
    assert.ok(editorPhoto.includes('if (doc && doc.ensurePhotoSystemTime) doc.ensurePhotoSystemTime(slotIndex)'));
    assert.ok(editorPhoto.includes('"date", "time", "time_source", "altitude", "altitude_source"'), 'lo guardado no pisa fecha/hora vigentes');
});
await test('FECHA/HORA D · la fecha del sistema nunca reemplaza la fecha de la ficha', async () => {
    const apply = block(doc, 'void applyPhotoCapture(', '} // namespace');
    assert.ok(!apply.includes('currentDate'), 'sin fecha/hora actual en el rótulo');
    assert.ok(/meta\[QStringLiteral\("date"\)\] = sheetDate\.isValid\(\)/.test(apply), 'la fecha de ficha manda');
});

// =================================================================== PERSISTENCIA REMOTA / PDF
await test('FECHA/HORA 17 · hora_inicio viaja cross-device (start_time)', async () => {
    assert.ok(form.includes('h.start_time = h.hora_inicio'), 'exportState mantiene la columna canónica al día');
    assert.ok(form.includes('h.start_time = normalized   // columna remota (cross-device)'));
    assert.ok(cloud.includes('changes[QStringLiteral("start_time")] = nullableTime(value("start_time", "hora_inicio"));'));
    assert.ok(doc.includes('{"start_time", "hora_inicio"}'), 'pull devuelve la hora al campo de la ficha');
});
await test('FOTO 15/16 · hora fija por foto y fecha/hora documental viajan con la versión', async () => {
    const enqueue = block(cloud, 'QVariantMap annotation = images.value(key("edit")).toMap();', 'entry[QStringLiteral("annotation")] = annotation;');
    assert.ok(enqueue.includes('"photo_document_date"') && enqueue.includes('"photo_document_time"'), 'fecha/hora DOCUMENTAL');
    assert.ok(enqueue.includes('annotation[QStringLiteral("capture")] = capture'), 'CAPTURA separada (EXIF / hora del sistema fijada)');
    const adopt = block(doc, 'bool CalicataDocument::adoptRemotePhoto(', 'return commitPhotoImages(images);');
    assert.ok(adopt.includes('if (!remoteCapture.isEmpty()) images[key("capture")] = remoteCapture;'),
              'otro dispositivo regenera con la misma hora fijada');
});
await test('PDF 18 · largo/ancho vacíos => sin " × " incompleto', async () => {
    const exporter = read('androidcalicataexporter.cpp');
    assert.ok(!exporter.includes('pdfText(header, {"length_m"}) + QStringLiteral(" × ")'), 'expresión anterior eliminada');
    const helper = block(exporter, 'QString pdfExcavationSize(const QVariantMap &header)', '\n}\n');
    assert.ok(/return ok && value > 0 \? text : QString\(\);/.test(helper), 'vacío o 0 = no informado');
    assert.ok(/if \(!length\.isEmpty\(\) && !width\.isEmpty\(\)\) return length \+ QStringLiteral\(" × "\) \+ width;/.test(helper));
    assert.ok(helper.includes('return QStringLiteral("Largo ") + length;') && helper.includes('return QStringLiteral("Ancho ") + width;'));
    assert.ok(/return QString\(\);\s*$/.test(helper.trim() + '\n') || helper.trim().endsWith('return QString();'), 'ambos vacíos => nada');
    // Emulación exacta de la regla (mismo algoritmo).
    const size = (l, w) => { const d = (t) => { const s = String(t ?? '').trim().replace(',', '.'); return Number(s) > 0 ? s : ''; };
        const L = d(l), W = d(w); return L && W ? `${L} × ${W}` : L ? `Largo ${L}` : W ? `Ancho ${W}` : ''; };
    assert.equal(size('', ''), ''); assert.equal(size('0', ''), ''); assert.equal(size('2.5', ''), 'Largo 2.5');
    assert.equal(size('', '1,8'), 'Ancho 1.8'); assert.equal(size('2.5', '1.8'), '2.5 × 1.8');
});
await test('SERVIDOR · migraciones y prueba SQL versionadas en el repo', async () => {
    const live = read('supabase/migrations/20261007180000_calicata_live_noop_keeps_revision.sql');
    assert.ok(live.includes("'SELECT %I IS NOT DISTINCT FROM $1::%s FROM public.calicatas WHERE id = $2'"));
    assert.ok(/IF NOT COALESCE\(v_unchanged, false\) THEN[\s\S]*?UPDATE public\.calicatas SET %I/.test(live), 'no-op => sin UPDATE');
    assert.ok(live.includes('count(*) <= 1') && live.includes('COALESCE(pg_catalog.bool_and(private.is_calicata_live_field_v01(key)), true)'));
    assert.ok(!/CREATE OR REPLACE FUNCTION private\.enforce_calicata_invariants/.test(live), 'el trigger global no se toca');
    assert.ok(fs.existsSync(path.join(root, 'supabase/rollback/20261007180000_calicata_live_noop_keeps_revision.rollback.sql')));
    assert.ok(!fs.readdirSync(path.join(root, 'supabase/migrations')).some((f) => f.includes('rollback')), 'la reversión no es una migración');
    const sql = read('tests/calicatas/sql/live_noop_revision_test.sql');
    assert.ok(sql.includes("raise exception 'TEST_RESULT %', v_out;"), 'la prueba siempre se revierte');
    const fn = read('supabase/functions/resolve-calicata-elevation/handler.mjs');
    assert.ok(fn.includes("env('GOOGLE_MAPS_ELEVATION_API_KEY')") && fn.includes("env('GEMINI_API_KEY')"), 'claves solo en secretos del servidor');
});

// =================================================================== ERROR 3
await test('SYNC A · autosaves concurrentes => una escritura; B/C coalescidas', async () => {
    const sync = block(cloud, 'QString CalicataCloudService::syncDocument(', 'auto ctx = std::make_shared<SyncContext>();');
    assert.ok(/if \(lane\.busy\(\)\) \{\s*lane\.requestSync\(requestedReason\);\s*qInfo\(\)\.noquote\(\) << "INGE_CALICATA_SYNC_COALESCED/.test(sync));
    assert.ok(/Request requestSync\(const QString &reason\)[\s\S]*?if \(tryAcquire\(\)\) \{ \+\+m_generation; return Request::Started; \}/.test(policy));
    assert.ok(!/m_syncingDocuments/.test(cloud), 'sin el guardia anterior');
});
await test('SYNC B · Guardar durante autosave => espera (sin 40001 propio)', async () => {
    const ok = block(cloud, 'auto &lane = m_lanes[ctx->localId];\n            noteConfirmedRevision', 'releaseLane(ctx->localId);');
    assert.ok(ok.includes('if (lane.queuedSync().isEmpty()) emit syncSucceeded(ctx->localId, result);'),
              'la petición coalescida termina con el snapshot más nuevo');
    assert.ok(/int reasonRank[\s\S]*?"export"\)\) return 3;[\s\S]*?"save"\)\) return 2;/.test(policy));
    const release = block(cloud, 'void CalicataCloudService::releaseLane(', 'void CalicataCloudService::noteConfirmedRevision');
    assert.ok(release.includes('syncDocument(doc, reason)') && release.includes('QTimer::singleShot(0, this, next.operation)'));
});
await test('SYNC C · éxito 22→23 => la siguiente escritura usa 23', async () => {
    const sync = block(cloud, 'const qint64 documentRevision =', 'ctx->startRevision');
    assert.ok(sync.includes('CalicataSync::expectedRevision(documentRevision, m_confirmedRevisions.value(ctx->remoteId))'));
    const ok = block(cloud, 'auto &lane = m_lanes[ctx->localId];\n            noteConfirmedRevision', 'releaseLane(ctx->localId);');
    assert.ok(ok.indexOf('noteConfirmedRevision') < ok.indexOf('emit syncSucceeded'), 'registrada ANTES de liberar el carril');
    // Cada paso CAS sigue verificando +1 y persistiendo la revisión al instante.
    assert.ok((cloud.match(/checkpointCloudRevision\(ctx->projectId, ctx->remoteId, version\)/g) || []).length >= 5);
});
await test('SYNC D · 40001 por revisión propia => rebase + reintento único', async () => {
    const fail = block(cloud, 'const auto fail = [this, ctx, finishFailure]', 'auto syncStrata');
    assert.ok(fail.includes('probeRoot(ctx->projectId, ctx->remoteId'));
    assert.ok(fail.includes('CalicataSync::classifyStale(ctx->rowVersion, serverRevision, lane.uncertainOwnBumps, consistent, ctx->retried)'));
    assert.ok(/lane\.retryAfterRebase = true;\s*lane\.requestSync\(ctx->reason\);/.test(fail));
    assert.ok(fail.includes('INGE_CALICATA_SYNC_REBASE reason=own_unverified_write'));
    // El cambio live de la ficha (+1 silencioso del servidor) se atribuye al instante.
    const live = block(cloud, 'void CalicataCloudService::runLiveCalicataChange(', 'void CalicataCloudService::rtHandleBroadcast');
    assert.ok(live.indexOf('probeRoot') < live.indexOf('send(') && live.lastIndexOf('probeRoot') > live.indexOf('send('), 'antes y después');
    assert.ok(live.includes('INGE_CALICATA_SYNC_REBASE reason=live_field_noop'));
});
await test('SYNC E · cambio externo real => conflicto real, sin sobrescribir', async () => {
    const fail = block(cloud, 'const auto fail = [this, ctx, finishFailure]', 'auto syncStrata');
    assert.ok(fail.includes('INGE_CALICATA_SYNC_REAL_CONFLICT') && fail.includes('finishFailure(codeValue, message, true)'));
    assert.ok(/if \(!ok\) \{[\s\S]*?finishFailure\(codeValue, message, false\);/.test(fail), 'sin poder leer la fila: pendiente, no conflicto');
    assert.ok(/if \(alreadyRetried \|\| server <= expected\) return Stale::RealConflict;/.test(policy));
    const finish = block(cloud, 'const auto finishFailure = [this, ctx, bindIdentity]', 'const auto fail =');
    assert.ok(finish.includes('m_lanes[ctx->localId].dropQueuedSync();'), 'sin más escrituras tras el conflicto');
});
await test('SYNC F · edición rápida 30–60 s => ninguna escritura paralela de la misma ficha', async () => {
    // Toda ruta que mueve calicatas.row_version pasa por el carril: sync, estado/archivo/restaurar y live de la FICHA.
    assert.ok(cloud.includes('lane.requestSync(requestedReason);   // carril libre: Started'));
    assert.ok(block(cloud, 'void CalicataCloudService::patchRemoteStatus(', 'const QVariantMap header = document->header();').includes('lane.tryAcquire()'));
    assert.ok(block(cloud, 'void CalicataCloudService::runLiveCalicataChange(', 'probeRoot(').includes('if (!lane.tryAcquire()) {'));
    // STRATUM / LAB_RESULT no tocan public.calicatas (verificado en el servidor): fuera del carril.
    assert.ok(cloud.includes('// STRATUM / LAB_RESULT no tocan public.calicatas: no mueven row_version.'));
    for (const log of ['INGE_CALICATA_SYNC_BEGIN', 'INGE_CALICATA_SYNC_OK', 'INGE_CALICATA_SYNC_COALESCED',
                       'INGE_CALICATA_SYNC_REBASE', 'INGE_CALICATA_SYNC_REAL_CONFLICT'])
        assert.ok(cloud.includes(log), 'traza ' + log);
});

console.log(count + ' casos C-AB-01 OK (comportamiento C++ del carril y fecha/hora: tests/calicatas/checks.cpp, requiere compilar)');
})().catch(error => { console.error(error); process.exit(1); });

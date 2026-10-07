'use strict';
// Convergencia Web ↔ Android de Laboratorio / Estrato / patrón / exportación.
// Fuente de verdad: E1PT04m0/ingeplus-web feature/calicatas-cloud-media-04a.
// 1) Reproduce 500 casos dorados calculados con el motor Web real
//    (soilClassification.ts + laboratoryContract.ts) y exige igualdad exacta.
// 2) Teselas SUCS idénticas a sucsSymbols.ts.
// 3) Contratos estáticos de UI, sincronización y exportación.
// Run: node tests/calicatas/web_lab_parity_static.cjs
const fs = require('fs');
const path = require('path');
const vm = require('vm');
const assert = require('assert');

const root = path.resolve(__dirname, '..', '..');
const read = (p) => fs.readFileSync(path.join(root, p), 'utf8');
const rulesSrc = read('qml/Mobile/lib/CalicataRules.js').split(/\r?\n/).filter((l) => !/^\s*\.(pragma|import)\b/.test(l)).join('\n');
const rules = vm.createContext({ console, Math, JSON, Number, String, isFinite, parseFloat, Date, RegExp, Object, Array });
vm.runInContext(rulesSrc, rules);
const plain = (v) => JSON.parse(JSON.stringify(v));
let passed = 0;
const check = (name, fn) => { fn(); passed++; console.log('PASS', name); };
const block = (src, start, end) => { const a = src.indexOf(start); assert.ok(a >= 0, 'falta ' + start); const b = src.indexOf(end, a + start.length); return src.slice(a, b < 0 ? undefined : b); };

const form = read('qml/Mobile/pages/CalicataFormPage.qml');
const cloud = read('calicatacloudservice.cpp');
const exporter = read('androidcalicataexporter.cpp');

check('motor de laboratorio = Web (500 casos dorados, sin diferencias)', () => {
    const golden = JSON.parse(read('tests/calicatas/fixtures/web_lab_golden_04a.json'));
    assert.ok(golden.cases.length >= 500);
    for (const [i, c] of golden.cases.entries()) {
        const labForm = rules.labForm(c.input.row, c.input.extra);
        const review = rules.reviewLaboratorySample(labForm);
        const validation = rules.validateLaboratoryForm(labForm);
        const pattern = rules.resolveCalicataSucsPattern(labForm.primarySucs, labForm.isComposite, labForm.secondarySucs);
        const android = plain({
            aashto: review.aashto, sucs: review.sucs, observations: review.observations,
            status: rules.laboratoryReviewStatus(labForm, review), errors: validation.errors, changes: validation.changes,
            projection: rules.formatSucsProjection(labForm.primarySucs, labForm.isComposite, labForm.secondarySucs),
            patternKey: pattern.key, patternCodes: pattern.layers.map((l) => l.code),
        });
        assert.deepStrictEqual(android, c.web, 'caso ' + i + ': ' + JSON.stringify(c.input));
    }
});

check('sin GW/GP/SW/SP inventados: grueso limpio sin Cu/Cc = conjunto', () => {
    const r = rules.reviewLaboratorySample(rules.labForm({ gmax: '100', g2: '80', g04: '40', g008: '3' },
        { passing_no4: '95', d10: '0.1', d30: '0.3', d60: '0.6' }));
    assert.deepStrictEqual(plain(r.sucs.candidates), ['SW', 'SP']);
    assert.strictEqual(r.sucs.conclusive, false);
    assert.ok(!/gradationCoefficients|nonplastic_confirmed/.test(block(rulesSrc, 'function labForm(', 'function labSampleSummary(')),
              'NP y D10/D30/D60 no entran al motor');
});

check('Nº 4 separa grava de arena (recommendSucs)', () => {
    const gravel = rules.reviewLaboratorySample(rules.labForm({ g2: '30', g04: '20', g008: '15', wl: '30', lp: '25' }, { passing_no4: '40' }));
    assert.deepStrictEqual(plain(gravel.sucs.candidates), ['GM']);
    const sand = rules.reviewLaboratorySample(rules.labForm({ g2: '70', g04: '50', g008: '15', wl: '30', lp: '25' }, { passing_no4: '90' }));
    assert.deepStrictEqual(plain(sand.sucs.candidates), ['SM']);
    const unknown = rules.reviewLaboratorySample(rules.labForm({ g2: '70', g04: '50', g008: '15', wl: '30', lp: '25' }, {}));
    assert.deepStrictEqual(plain(unknown.sucs.candidates), ['GM', 'SM']);
});

check('WL/LP enteros como Web (decimal = error visible, nunca redondeo)', () => {
    assert.strictEqual(rules.webLabNormalizeLimit('32'), '32');
    assert.strictEqual(rules.webLabNormalizeLimit('32.5'), null);
    const v = rules.webLabValidate({ wl: '32.5', lp: '18' }, {});
    assert.strictEqual(v.valid, false);
    assert.strictEqual(v.fieldErrors.liquidLimit, 'Debe ser un número entero.');
    assert.match(cloud, /upsert_my_calicata_lab_result_v02/);
    assert.ok(!/upsert_my_calicata_lab_result_v03|set_my_calicata_lab_extension_v01|set_my_calicata_stratum_field_classification_v01/.test(cloud),
              'sin RPC inexistentes en DEV/Web');
    assert.match(cloud, /LAB_LIMITS_NOT_INTEGER/);
});

check('teselas SUCS idénticas a Web sucsSymbols.ts', () => {
    const tiles = require('./web_sucs_symbols.cjs');
    for (const code of tiles.CODES) {
        assert.strictEqual(read(`SUCS/web/${code}.svg`), tiles.display(code), code);
        assert.strictEqual(read(`SUCS/web/export/${code}.svg`), tiles.exported(code), 'export ' + code);
    }
    const qrc = read('resources.qrc');
    assert.ok(qrc.includes('<qresource prefix="/SUCS/web">') && qrc.includes('<qresource prefix="/SUCS/web/export">'));
    assert.strictEqual(rules.sucsSymbolUrl('PT'), 'qrc:/SUCS/web/PT.svg');
    assert.strictEqual(rules.sucsSymbolUrl('Pt'), 'qrc:/SUCS/web/PT.svg', 'Pt antiguo -> catálogo Web');
});

check('Estrato = proyección de solo lectura ("Pendiente de laboratorio")', () => {
    const editor = block(form, '// 4. Clasificación geotécnica.', 'label: "Descripción"');
    assert.ok(editor.includes('valueText: prfEditorCard.projection.sucs') && editor.includes('valueText: prfEditorCard.projection.aashto'));
    assert.ok(editor.includes('placeholder: "Pendiente de laboratorio"'));
    assert.ok(!/prfPick\("Clasificación (SUCS|AASHTO)"/.test(form), 'sin selectores SUCS/AASHTO en Estrato');
    assert.ok(!form.includes('profilePatternPicker'), 'sin selector de patrón libre');
    assert.ok(form.includes('label: "Símbolo / patrón (Laboratorio)"'));
    assert.ok(!form.includes('function setSucsForCorte('), 'Estrato ya no escribe row.sucs');
    const p = rules.labProjection({ primary_sucs: 'SP', is_composite: true, secondary_sucs: 'SM', lab_confirmed_aashto: 'A-2-4', sucs: 'CL' });
    assert.strictEqual(p.sucs, 'SP + SM');
    assert.strictEqual(p.aashto, 'A-2-4');
    assert.deepStrictEqual(plain(p.pattern.layers.map((l) => l.url)), ['qrc:/SUCS/web/SP.svg', 'qrc:/SUCS/web/SM.svg']);
    assert.strictEqual(rules.labProjection({ sucs: 'CL', aashto: 'A-6' }).sucs, '', 'el valor anterior del estrato no es proyección');
});

check('Laboratorio: sugerencia nunca adopta sola; chips adoptan con un toque', () => {
    const derive = block(form, 'function deriveLabFields() {', 'function adoptStratumIdentities(');
    assert.ok(!/primary_sucs\s*=|lab_confirmed_aashto\s*=/.test(derive), 'derivar no escribe la clasificación');
    assert.ok(form.includes('onAdopt: root.adoptLabAashto(mobileSampleCard.corteIdx, code)'));
    assert.ok(form.includes('onAdopt: root.adoptLabSucs(mobileSampleCard.corteIdx, code)'));
    assert.ok(form.includes('TapHandler { id: chipTap; enabled: !chip.current; onTapped: chip.adopt() }'), 'el valor vigente no es botón');
    const s = rules.labSuggestion(rules.labForm({ g2: '70', g04: '50', g008: '8' }, {}), rules.reviewLaboratorySample(rules.labForm({ g2: '70', g04: '50', g008: '8' }, {})));
    assert.strictEqual(s.sucs.length, 4);
    assert.strictEqual(s.hidden, 4, 'VISIBLE_SUCS_CANDIDATES = 4 y "+N"');
    for (const label of ['"SUCS principal"', '"2.º Segundo SUCS"', '"Clasificación compuesta"', 'label: "AASHTO"', '"Clasificación sugerida"'])
        assert.ok(form.includes(label), label);
});

check('Autoridad del laboratorio: migración de fichas antiguas sin borrar', () => {
    const auth = block(form, 'function _labAuthority(extra) {', '// ===== Laboratorio (autoridad de SUCS/AASHTO)');
    assert.ok(auth.includes('extra.lab_confirmed_sucs') && !/delete\s+extra/.test(auth));
    const pull = block(cloud, '// Contrato Web: la clasificación vigente es la del laboratorio', 'local[QStringLiteral("gmax")]');
    assert.ok(pull.includes('local[QStringLiteral("sucs")] = stratum.value(QStringLiteral("sucs"))'), 'pull conserva el valor del estrato');
    assert.ok(cloud.includes('"d10", "d30", "d60", "nonplastic_confirmed", "lab_observations", "lab_visual_aashto"'),
              'datos solo locales antiguos se conservan en el pull');
});

check('Exportación = Web exportModel (laboratorio primero, estrato solo si vacío)', () => {
    assert.deepStrictEqual(plain(rules.exportClassification({ primary_sucs: 'SP', is_composite: true, secondary_sucs: 'SM', lab_confirmed_aashto: 'A-1-b', sucs: 'CL', aashto: 'A-6' })),
        { primary: 'SP', secondary: 'SM', label: 'SP-SM', aashto: 'A-1-b', fromLaboratory: true });
    assert.deepStrictEqual(plain(rules.exportClassification({ sucs: 'CL', aashto: 'A-6' })),
        { primary: 'CL', secondary: '', label: 'CL', aashto: 'A-6', fromLaboratory: false });
    const cpp = block(exporter, 'ExportClassification exportClassificationFor(const QVariantMap &corte)', 'QImage webSucsExportTile(');
    assert.ok(cpp.includes('QStringLiteral("primary_sucs")') && cpp.includes('QStringLiteral("lab_confirmed_aashto")'));
    assert.ok(exporter.includes('constexpr int kWebSucsTilePx = 17;'), 'CALICATA_SUCS_TILE_PX');
    assert.ok(exporter.includes('sucsPattern(5, 7, classification.primary) && sucsPattern(8, 9, classification.secondary)'), 'compuesta E:G | H:I');
    assert.ok(!/usesRaPattern|kReportRaPattern|pattern_primary/.test(exporter), 'sin tramas RA/MTC paralelas');
    assert.ok(!/nonplastic_confirmed/.test(exporter), 'Web no imprime LP = NP');
});

check('Encabezado: proyecto = projects.name (sin nombres duplicados por ficha)', () => {
    assert.ok(!form.includes('label: "Nombre corto del proyecto"') && !form.includes('label: "Nombre corto (interno)"'));
    assert.ok(!form.includes('headerKey: "project_short_name"') && !form.includes('id: projectNameArea'));
    assert.ok(form.includes('label: "Proyecto"') && form.includes('label: "Título de la ficha / testificación"'));
    assert.ok(exporter.includes('QString exportProjectName(const QVariantMap &header'));
    assert.strictEqual((exporter.match(/exportProjectName\(header/g) || []).length, 3, 'Excel AG4 + PDF (título corrido y portada)');
    const doc = read('calicatadocument.cpp');
    assert.ok(doc.includes(': text({"projectName", "project_name"});'), 'rótulo de fotos = projects.name');
});

check('Fotos: descargar versión anotada = derivado existente, sin repintar', () => {
    const doc = read('calicatadocument.cpp');
    const fn = block(doc, 'QString CalicataDocument::savePhotoToGallery(int idx, bool annotated)', '// Live values of the ficha');
    assert.ok(fn.includes('cachedPhotoUrl(idx)') && !/paintPhotoDerivative|renderDerivedPhoto|QImage/.test(fn), 'copia el archivo, no lo pinta');
    assert.ok(fn.includes('-anotada.jpg'));
    const java = read('android/src/com/ingema/ingeplus/NothingFileBridge.java');
    assert.ok(java.includes('MediaStore.MediaColumns.RELATIVE_PATH') && java.includes('IS_PENDING'), 'MediaStore (Android 10+)');
    assert.ok(java.includes('MediaScannerConnection.scanFile') && java.includes('WRITE_EXTERNAL_STORAGE'), 'Android 9');
    assert.ok(!/Bitmap|compress\(/.test(block(java, 'public static String saveToPictures(', 'private static void copy(')), 'sin recompresión');
    assert.ok(form.includes('add("downloadAnnotated", "Descargar versión anotada"') && form.includes('add("downloadOriginal", "Descargar original"'));
});

check('Estado: transiciones ofrecidas por el servidor (get_my_calicata_status_actions_v01)', () => {
    const change = block(cloud, 'QString CalicataCloudService::changeStatus(', 'void CalicataCloudService::commitStatusChange(');
    assert.ok(change.includes('get_my_calicata_status_actions_v01') && change.includes('allowed.contains(next)'));
    const restore = block(cloud, 'QString CalicataCloudService::restoreDocument(', 'QString CalicataCloudService::codeConflict(');
    assert.ok(restore.includes('remoteId.isEmpty() ? document->restoreTargetStatus() : QStringLiteral("OBSERVADO")'));
});

console.log(`web_lab_parity_static: ${passed} PASS`);

// Interpreted only: node tests/calicatas/stability_static.cjs
const fs = require('node:fs');
const vm = require('node:vm');
const assert = require('node:assert/strict');
const path = require('node:path');
const root = path.resolve(__dirname, '../..');
const read = file => fs.readFileSync(path.join(root, file), 'utf8').replace(/\r\n/g, '\n');
function library(file) {
    const context = vm.createContext({});
    vm.runInContext(read(file).replace('.pragma library', ''), context);
    return context;
}
const rules = library('qml/Mobile/lib/CalicataRules.js');
const gps = library('qml/Mobile/lib/GpsBus.js');
let count = 0;
function test(name, fn) { fn(); ++count; console.log('STATIC_OK ' + name); }
const valid = () => ({header: {
    projectId: 'aa43f6c1-782b-4728-96a2-123456789abc', projectName: 'Proyecto A', projectCode: 'PA',
    codigo: 'C-01', status: 'BORRADOR', fecha_inicio: '2026-09-21',
    latitude: -12, longitude: -77, utm_x: '282241.15', utm_y: '8672655.94', zona: '18L', datum: 'WGS84',
    length_m: '1.50', width_m: '1,20', requested_depth_m: 2, final_depth_m: 2,
    water_table_status: 'NO_ENCONTRADO'
}, cortes: [{de: '0', a: '1'}, {de: '1', a: '2'}],
images: {foto1_path: 'a.jpg', foto2_path: 'b.jpg', foto3_path: 'c.jpg'}});
const blockers = state => rules.blockers(rules.validateDocument(state));
test('complete document has no blockers', () => assert.equal(blockers(valid()).length, 0));
test('decimals accept comma/dot and preserve precision', () => {
    for (const text of ['1,50', '1.50']) assert.equal(rules.parseDecimalSafe(text), 1.5);
    assert.equal(rules.normalizeDecimalText('123456,789', rules.COORDINATE, false), '123456.789');
    for (const text of ['', null, undefined, '1.2.3', '1,234.56', '12garbage', 'Infinity'])
        assert.ok(Number.isNaN(rules.parseDecimalSafe(text)));
    assert.equal(rules.parseDecimalSafe('0'), 0);
});
test('project is required for final actions, never for keeping a draft', () => {
    const s = valid(); delete s.header.projectId;
    assert.ok(blockers(s).some(i => i.message === 'Proyecto no asignado.'));
});
test('found groundwater requires a number and allows zero', () => {
    const s = valid(); s.header.water_table_status = 'ENCONTRADO';
    for (const value of ['', null, '3', 'invalid']) {
        s.header.water_table_depth = value;
        assert.ok(blockers(s).some(i => i.message.includes('Nivel freático encontrado')));
    }
    s.header.water_table_depth = 0;
    assert.equal(blockers(s).length, 0);
    s.header.water_table_status = 'NO_EVALUADO';
    assert.equal(blockers(s).length, 0);
    assert.ok(rules.validateDocument(s).some(i => i.severity === 'WARNING'));
});
test('laboratorio: el mismo validador que Web (enteros, LP <= WL); NP antiguo no bloquea', () => {
    const s = valid(); Object.assign(s.cortes[0], {nonplastic_confirmed: true, wl: '', lp: ''});
    assert.equal(blockers(s).length, 0);
    s.cortes[0].wl = '35'; s.cortes[0].lp = '40';
    assert.ok(blockers(s).some(i => i.message.includes('LP debe ser menor o igual que WL.')));
    s.cortes[0].lp = '20'; assert.equal(blockers(s).length, 0);
    s.cortes[0].wl = '35.5';
    assert.ok(blockers(s).some(i => i.message.includes('Debe ser un número entero.')));
});
test('overlap, gap, inversion and escaped sample are blockers', () => {
    for (const from of ['0.8', '1.2', '2.1']) {
        const s = valid(); s.cortes[1].de = from; assert.ok(blockers(s).length > 0);
    }
    const s = valid(); Object.assign(s.cortes[0], {muestra_desde:'0.5', muestra_hasta:'1.5'});
    assert.ok(blockers(s).some(i => i.section === 5));
});
test('missing image file is distinct from filled photo reference', () => {
    const s = valid(); s.photoAvailability = {'1':true,'2':false,'3':true};
    assert.ok(blockers(s).some(i => i.message.includes('No se encuentra el archivo')));
    delete s.images.foto1_path;
    // foto1 = categoría 1 de Fotos ("Zona de ejecución"; Web EXECUTION).
    assert.ok(blockers(s).some(i => i.message === 'Falta Zona de ejecución.'));
});
test('empty/null coordinates cannot become zero or valid map location', () => {
    for (const value of ['', null, undefined, '90']) {
        const s = valid(); s.header.latitude = value;
        assert.ok(blockers(s).some(i => i.section === 2));
    }
});
test('WGS84 UTM round trip across Peru and both hemispheres', () => {
    for (const [lat, lon] of [[-12,-77],[-16.4,-71.5],[-3.75,-73.25],[40,-74],[0,15]]) {
        const u = gps.latLonToUTM(lat, lon);
        const point = rules.utmToGeo(u.easting, u.northing, String(u.zone)+u.band);
        assert.ok(point, `${lat},${lon}`);
        assert.ok(Math.abs(point.latitude-lat) < 0.00001);
        assert.ok(Math.abs(point.longitude-lon) < 0.00001);
    }
    for (const args of [['',1,'18L'],[1,1,'18L'],[500000,9000000,'bad'],[500000,9000000,'18N']])
        assert.equal(rules.utmToGeo(...args), null);
});
test('shared validation and transactional source contracts', () => {
    const cpp = read('calicatadocument.cpp'), form = read('qml/Mobile/pages/CalicataFormPage.qml');
    const exporter = read('androidcalicataexporter.cpp');
    assert.ok(form.includes('doc.validationIssues(state)'));
    assert.ok(exporter.includes('CalicataValidation::firstBlocker(state)'));
    assert.ok(cpp.includes('validationIssues(buildFullJson())'));
    assert.ok(cpp.includes('m_images = previous;'));
    assert.ok(cpp.includes('return persistPhoto(idx, sourceImageUrl, true);'));
    assert.ok(!form.includes('foto1Source'));
    assert.ok(!form.includes('DocsOps.copyToDir(sourceAbs, cacheFolderAbs)'));
    // Cancelar (o un documento/serie ya obsoletos) libera la importación pendiente.
    const resolve = form.slice(form.indexOf('function resolve(withData)'), form.indexOf('contentItem: ColumnLayout', form.indexOf('function resolve(withData)')));
    assert.ok(/withData === null[\s\S]{0,200}root\._releasePendingPhotoImport\(\)\s*\n\s*return/.test(resolve));
    assert.ok(form.includes('text: "Cancelar"; onClicked: tsDlg.resolve(null)'));
    const begin = form.slice(form.indexOf('function _beginPhotoRequest'),form.indexOf('onRequestCapturePhoto:'));
    assert.ok(!begin.includes('clearPhoto'));
    assert.ok(cpp.includes('pure["calicataId"] = m_instanceId;'));
    assert.ok(cpp.includes('selection["projectCode"]'));
    assert.ok(read('CMakeLists.txt').includes('"${MOBILE_QML_DIR}/lib/CalicataRules.js"'));
});
test('camera JNI uses the return type declared by Android', () => {
    const source = read('permissionhelper.cpp');
    assert.ok(!/callObjectMethod\s*\(\s*"[^"]+"\s*,\s*"\([^"\n]*\)V"/.test(source));
    assert.match(source, /callMethod<void>\("setClipData",\s*"\(Landroid\/content\/ClipData;\)V"/);
});

test('exporter default logos resolve through production QRC to real files', () => {
    const resources = new Map();
    for (const group of read('resources.qrc').matchAll(/<qresource prefix="([^"]*)">([\s\S]*?)<\/qresource>/g)) {
        for (const entry of group[2].matchAll(/<file(?: alias="([^"]*)")?>([^<]*)<\/file>/g)) {
            resources.set(':' + group[1] + '/' + (entry[1] || entry[2]), entry[2]);
        }
    }
    for (const url of [':/images/ICONO_LOGO_MTC.jpeg', ':/images/INGEMA_LOGO_COMPLETO.png']) {
        assert.ok(read('androidcalicataexporter.cpp').includes(url));
        assert.ok(resources.has(url), `Missing production resource: ${url}`);
        assert.ok(fs.statSync(path.join(root, resources.get(url))).size > 0);
    }
});

// Regla C-AB-01 (2026-10-07): aplicar una ubicación fija X/Y y NUNCA escribe Z
// directamente; delega en resolveAltitude (DEM validado > altura GPS elipsoidal),
// que conserva una Z manual. La altura del fix viaja solo como respaldo.
function applyFix(altitude) {
    const source = read('qml/Mobile/pages/CalicataFormPage.qml');
    const fn = source.slice(source.indexOf('function _applyCoordsFromGps('),
        source.indexOf('function _openCurrentCoordinateInEarth('));
    const doc = {header: {utm_z: '718', altitud: '718'}, timestamp: {altitud: '718'}, markDirty() {}};
    const calls = [];
    const ctx = vm.createContext({doc, _documentClosing: false, _docInstanceId: () => 'fixture',
        GpsBus: {hasFix: () => true, hasGeoFix: () => true, latitude: -13.007932, longitude: -73.513005,
            utmZone: '18L', utmX: 661263, utmY: 8561516, altitudeOk: Number.isFinite(altitude), altitude,
            altitudeText: () => (Number.isFinite(altitude) ? altitude.toFixed(1) : ''), markApplied() {}},
        txtZona: {}, txtUTMX: {}, txtUTMY: {}, txtUTMZ: {text: '718'}, txtCodigo: {text: 'C-AA-01'},
        root: {resolveAltitude: (trigger, value) => calls.push([trigger, value])},
        setDirty() {}, documentMarkedDirty() {}, console: {info() {}}});
    vm.runInContext(fn, ctx);
    assert.equal(ctx._applyCoordsFromGps('fixture', 0), true);
    return {doc, ctx, calls};
}
test('applying a GPS fix without altitude keeps Z=718 and asks the terrain elevation', () => {
    const {doc, ctx, calls} = applyFix(NaN);
    assert.equal(doc.header.utm_z, '718');
    assert.equal(doc.header.altitud, '718');
    assert.equal(doc.timestamp.altitud, '718');
    assert.equal(ctx.txtUTMZ.text, '718');
    assert.equal(doc.header.utm_x, '661263.00');
    assert.equal(calls.length, 1);
    assert.equal(calls[0][0], 'location');
    assert.ok(Number.isNaN(calls[0][1]));
});
test('applying a GPS fix with device altitude never writes it as Z directly', () => {
    const {doc, ctx, calls} = applyFix(706.4);
    assert.equal(doc.header.utm_z, '718');
    assert.equal(ctx.txtUTMZ.text, '718');
    assert.deepEqual(calls, [['location', 706.4]], 'la altura del fix solo es respaldo de resolveAltitude');
});
console.log(`${count} interpreted/static checks completed; runtime USER_BUILD_REQUIRED`);

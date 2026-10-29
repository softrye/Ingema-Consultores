// Interpreted only: node tests/calicatas/c_aa01_closure_static.cjs
// Cierre físico C-AA-01: nombre XLSX, cota Z/mapa, tramas sin stretch,
// largo/ancho opcionales, diálogo de distancia y timers del mapa.
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
const exporter = read('androidcalicataexporter.cpp');
const form = read('qml/Mobile/pages/CalicataFormPage.qml');
const editor = read('qml/Mobile/pages/CalicatasEditorPage.qml');
const picker = read('qml/Mobile/pages/CalicataPointPicker.qml');
function block(source, start, end) {
    const i = source.indexOf(start);
    assert.ok(i >= 0, 'falta ' + start);
    const j = source.indexOf(end, i + start.length);
    return source.slice(i, j < 0 ? undefined : j);
}
let count = 0;
function test(name, fn) { fn(); ++count; console.log('PASS ' + name); }

// ------------------------------------------------------------------ CASO A
test('A · código C-AA-01 + progresiva 00+620 => C-AA-01.xlsx', () => {
    // 1) El editor nunca compone el código con la progresiva.
    assert.ok(!/_setProgresiva\([^)]*,\s*true\)/.test(form), 'ninguna llamada compone código+progresiva');
    assert.ok(/root\._setProgresiva\(normalized, false\)/.test(form));
    // Flujo del editor: escribir código y luego progresiva deja el código intacto.
    let code = 'C-AA-01';
    const pk = rules.normalizeProgresiva('00+620');
    assert.equal(pk, '00+620');
    const composeCode = false; // valor real de la llamada del campo Progresiva
    if (composeCode && rules.isValidProgresiva(pk)) code = rules.composeCalicataCode(code, pk);
    assert.equal(code, 'C-AA-01');
    // 2) El nombre visible sale solo del código (codigo antes que cualquier pk).
    const canon = block(exporter, 'QString canonicalCalicataCode(', '\n}\n');
    const keys = [...canon.matchAll(/QStringLiteral\("(\w+)"\)/g)].map(m => m[1]);
    assert.equal(keys[0], 'codigo');
    assert.ok(keys.indexOf('pk') > keys.indexOf('calicata') && keys.indexOf('progresiva') > keys.indexOf('calicata'),
              'la progresiva solo se usa si NO hay código');
    const header = { codigo: code, calicata: code, pk, progresiva: pk };
    const pick = keys.map(k => header[k]).find(v => v && String(v).trim());
    const fileName = pick.replace(/[<>:"/\\|?*\x00-\x1F]/g, '_') + '.xlsx';
    assert.equal(fileName, 'C-AA-01.xlsx');
    assert.notEqual(fileName, 'C-AA-01-00+620.xlsx');
    // 3) Google Drive, InGeDrive y publicación usan el mismo builder.
    assert.ok(exporter.includes('const QString visibleFileName = safeFileName(QString(reportCode).remove(\'*\')) + ".xlsx";'));
    assert.ok(exporter.includes('safeFileName(QString(canonicalCalicataCode(header)).remove(\'*\')) + ".xlsx"'));
    assert.ok(!/visibleFileName\s*=.*(pk|progresiva)/.test(exporter));
});

// ------------------------------------------------------------------ CASOS B/C + GPS con altitud
const accept = block(form, 'function acceptMapPoint(', 'property bool reviewNotesEditing');
const apply = block(form, 'function _applyCoordsFromGps(', 'function _openCurrentCoordinateInEarth');
test('B · Z manual 718: abrir/explorar/cancelar el mapa no la toca', () => {
    // Abrir: el candidato inicial es el punto de la ficha y no escribe la ficha.
    const loaded = block(editor, 'onLoaded: {\n                    var map = item', 'Label {');
    assert.ok(loaded.includes('"Punto de la ficha"'));
    assert.ok(!/header\s*=|acceptMapPoint|utm_z|txtUTMZ/.test(loaded), 'abrir no persiste nada');
    // Confirmar el punto de la ficha sin cambios = cerrar sin reescribir.
    assert.ok(/if \(map\.selectedSource === "Punto de la ficha"\) \{ coordinatePicker\.close\(\); return \}/.test(editor));
    // Cancelar = cerrar (cero persistencia).
    const sheet = block(editor, 'text: "Cancelar"\n                            onClicked: coordinatePicker.close()', '}');
    assert.ok(sheet.includes('coordinatePicker.close()'));
    // Un solo motor cartográfico: el selector usa el WebView Cesium de InGe
    // Earth (modo selector); Calicatas no instancia un mapa propio.
    assert.ok(picker.includes('GraphicsCore.openEarthPicker(') && !/\bMap\s*\{|MapLibre|QtLocation/.test(picker),
              'sin selección cartográfica duplicada dentro de Calicatas');
    assert.ok(picker.includes('function onEarthPickerPointSelected(latitude, longitude)'), 'el toque llega desde Cesium');
    assert.ok(picker.includes('function centerOn(lat, lon)'), 'el host puede restaurar el punto de la ficha');
    // Abrir el selector no pide GPS.
    const opened = block(picker, 'Component.onCompleted: {', 'Component.onDestruction');
    assert.ok(!/centerGps|requestGpsEnabled|requestFreshFix/.test(opened));
});
test('C · GPS/punto sin altitud => Z existente intacta', () => {
    assert.ok(!/txtUTMZ\.text = ""/.test(accept), 'acceptMapPoint ya no borra Z');
    assert.ok(!/utm_z = ""/.test(accept));
    // Regla C-AB-01: aplicar una ubicación nunca escribe Z directamente; la
    // resuelve resolveAltitude (DEM > GPS elipsoidal) y una Z manual se conserva.
    assert.ok(!/txtUTMZ\.text\s*=|h\.utm_z\s*=|h\.altitud\s*=/.test(apply), 'apply no escribe Z');
    assert.ok(/root\.resolveAltitude\("location", deviceAltitude\)/.test(apply));
    // GpsBus: sin altitud válida el texto es vacío => la rama de Z no se ejecuta.
    gps.updateFromGeo(-13.007932, -73.513005, NaN, false, '10:00:00', 4, 'Punto fijado en mapa');
    assert.equal(gps.altitudeText(), '');
    gps.updateFromGeo(-13.007932, -73.513005, 0, false, '10:00:00', 4, 'GPS del dispositivo');
    assert.equal(gps.altitudeText(), '', 'altValid=false nunca produce una cota');
});
test('GPS explícito con altitud válida + confirmar => Z actualizada', () => {
    assert.ok(/var altitudeOk = isFinite\(altitude\) && altitude > -500 && altitude < 9000/.test(accept));
    gps.updateFromGeo(-13.007932, -73.513005, 706.4, true, '10:00:00', 4, 'GPS del dispositivo');
    assert.equal(gps.altitudeText(), '706.4');
    // X/Y con la conversión canónica de la ficha (C-AA-01: 661263 E, 8561516 N, 18L).
    assert.equal(gps.utmZone, '18L');
    assert.ok(Math.abs(gps.utmX - 661263) < 2 && Math.abs(gps.utmY - 8561516) < 2);
    // La confirmación es el único camino que persiste el candidato.
    const commit = block(editor, 'function _commitCoordinateCandidate()', '\n    }\n');
    assert.ok(commit.includes('formLoader.item.acceptMapPoint(map.selectedLat, map.selectedLon, map.selectedAlt,'));
    // "Mi ubicación" pasa la altitud del fix (NaN si el dispositivo no la entrega).
    assert.ok(picker.includes('selectCoordinate(gpsLat, gpsLon, gpsAlt, gpsAccuracy,'));
    assert.ok(!/[Gg]emini|elevation\s*api/i.test(accept + apply), 'la cota nunca se estima');
});

// ------------------------------------------------------------------ CASO D
test('D · largo/ancho vacíos o 0 => sin pendiente ni advisory', () => {
    const base = () => ({ header: {
        projectId: 'aa43f6c1-782b-4728-96a2-123456789abc', projectName: 'Proyecto A', codigo: 'C-AA-01',
        status: 'BORRADOR', fecha_inicio: '2026-05-14', latitude: -13.007932, longitude: -73.513005,
        utm_x: '661263', utm_y: '8561516', utm_z: '718', zona: '18L', datum: 'WGS84',
        water_table_status: 'ENCONTRADO', water_table_depth: '1.40'
    }, cortes: [{ de: '0', a: '2' }, { de: '2', a: '3' }], images: {} });
    const dimensionIssues = s => rules.validateDocument(s).filter(i => /Largo|Ancho/.test(i.message));
    for (const value of [undefined, '', null, '0', 0]) {
        const s = base(); s.header.length_m = value; s.header.width_m = value;
        assert.equal(dimensionIssues(s).length, 0, 'valor ' + JSON.stringify(value));
    }
    const s = base(); s.header.length_m = 'abc'; s.header.width_m = '-1';
    assert.equal(dimensionIssues(s).length, 2, 'un valor escrito inválido sí se informa');
    // El exportador no escribe largo/ancho en el XLSX (no se inventan).
    const fill = block(exporter, 'bool fillOfficialCalicataTemplate(', '\n}\n');
    assert.ok(!/length_m|width_m/.test(fill));
});

// ------------------------------------------------------------------ CASO E
test('E · tramas 0–2 m y 2–3 m: misma escala, más/menos repeticiones, sin stretch', () => {
    const engine = block(exporter, 'QImage tiledProfilePattern(', '\n}\n');
    assert.ok(engine.includes('scaledToWidth(tileWidth, Qt::SmoothTransformation)'), 'escala uniforme');
    assert.ok(!/IgnoreAspectRatio|scaled\(\s*box|scaled\([^)]*,[^)]*,/.test(engine), 'sin escalado no proporcional');
    assert.ok(/for \(int y = 0; y < out\.height\(\); y \+= unit\.height\(\)\)/.test(engine), 'repetición vertical');
    const profile = block(exporter, 'bool writeScaledProfile(', 'QString desc =');
    // Convergencia Web: tesela SUCS fija de 17 px (CALICATA_SUCS_TILE_PX) a 2x.
    assert.ok(profile.includes('const QImage fill = tiledProfilePattern(tile, box, 0.5);'));
    assert.ok(!profile.includes('patterns.value(resource)) > 0'), 'el recurso crudo ya no se ancla estirado');
    assert.ok(exporter.includes('reader.setScaledSize(QSize(kWebSucsTilePx * 2, kWebSucsTilePx * 2));'), 'escala fija por tesela Web');
    // Simulación con la geometría de C-AA-01 (E:I = 1120775 EMU ≈ 118 px; 60 filas × 21.75 pt = 3.00 m).
    const pxPerRow = 21.75 * 96 / 72, width = 118, supersample = 2;
    const strata = [{ de: 0, a: 2 }, { de: 2, a: 3 }].map(s => Math.round((s.a - s.de) / 3 * 60 * pxPerRow));
    for (const [w, h] of [[64, 64], [288, 463]]) { // tile MTC (svg 64×64) y panel SUCS GP.png
        const scale = Math.min(1, width / w);
        const unitW = Math.max(1, Math.round(w * scale * supersample));
        const unitH = Math.round(h * unitW / w);
        assert.ok(Math.abs(unitW / unitH - w / h) < 0.01, 'el símbolo conserva su proporción');
        const reps = strata.map(boxH => Math.ceil(boxH * supersample / unitH));
        assert.ok(reps[0] > reps[1], 'el estrato de 2 m repite más que el de 1 m');
        // Antes: el mismo bitmap estirado al rectángulo (factor vertical ≠ horizontal).
        const before = strata.map(boxH => (boxH / h) / (width / w));
        assert.ok(before.every(f => f > 1.5), 'la versión anterior deformaba (x' + before.map(f => f.toFixed(1)) + ')');
    }
});

// ------------------------------------------------------------------ P0-5 / P0-6
test('Ubicación: ningún Timer QML del flujo usa intervalo negativo', () => {
    for (const source of [picker, block(editor, 'CalPopup {\n        id: coordinatePicker', 'component CalPopup')]) {
        for (const m of source.matchAll(/interval:\s*([^\n]+)/g))
            assert.ok(/^\d+$/.test(m[1].trim()) && Number(m[1]) > 0, 'intervalo fijo positivo: ' + m[1]);
    }
});
test('Punto distante: solo al confirmar, con fix real reciente, diálogo Calicatas Cancelar/Confirmar', () => {
    // El toque de selección solo llega desde el mapa Cesium (no hay superficie QML que lo simule).
    assert.ok(picker.includes('selectCoordinate(lat, lon, NaN, NaN, mapSourceLabel, true)')
              && picker.includes('readonly property string mapSourceLabel: "Punto fijado en mapa"'),
              'toque en el mapa = candidato sin persistir');
    assert.ok(!/standardButtons|Dialog \{/.test(picker), 'sin diálogo Qt plano');
    assert.ok(/function distanceToRecentFix\(lat, lon\)/.test(picker));
    const confirm = block(editor, 'id: distantPointConfirm', 'Connections {');
    assert.ok(confirm.includes('text: "Cancelar"') && confirm.includes('text: "Confirmar"'));
    assert.ok(confirm.includes('root._commitCoordinateCandidate()'));
    const use = block(editor, 'text: "Usar esta ubicación"', 'Connections {');
    assert.ok(use.includes('map.distanceToRecentFix(map.selectedLat, map.selectedLon)'));
    assert.ok(use.includes('map.selectedSource === map.gpsSourceLabel ? NaN'), 'el propio fix no se compara consigo mismo');
});

// ------------------------------------------------------------------ P1-1 sync 40001
test('Sync 40001: estado y sync del mismo dispositivo no compiten por row_version', () => {
    const cloud = read('calicatacloudservice.cpp');
    const status = block(cloud, 'void CalicataCloudService::patchRemoteStatus(', '\nnamespace {');
    // Mismo carril por ficha que la sync: espera su turno (no falla) y libera en TODA salida.
    assert.ok(/if \(!lane\.tryAcquire\(\)\) \{[\s\S]*?lane\.defer\(/.test(status), 'estado en cola, sin CAS paralelo');
    assert.ok(/const StatusCallback done = \[this, localId, callerDone\]\([^)]*\) \{\s*callerDone\(ok, code, message\);\s*releaseLane\(localId\);/.test(status));
    assert.ok(!/callerDone\(true/.test(status), 'éxitos/errores pasan por done (que libera el carril)');
    const sync = block(cloud, 'QString CalicataCloudService::syncDocument(', 'auto ctx = std::make_shared<SyncContext>();');
    assert.ok(/if \(lane\.busy\(\)\) \{\s*lane\.requestSync\(requestedReason\);/.test(sync), 'otra sync se coalesce');
    // Un rechazo real (otra sesión/Web) sigue en CONFLICT: nunca sobrescribe en silencio.
    const fail = block(cloud, 'const auto finishFailure = [this, ctx, bindIdentity]', 'auto syncStrata');
    assert.ok(fail.includes('conflict ? QStringLiteral("CONFLICT")') && fail.includes('INGE_CALICATA_SYNC_REAL_CONFLICT'));
    // Y el código que viaja al servidor es el editado (alias `code` sincronizado).
    assert.ok(/if \(h\.code !== undefined\) h\.code = t/.test(form));
});

console.log(count + ' casos C-AA-01 OK');

// Calicatas — proyecto ≠ carpeta + importación de Excel (CalicataExcelImport.js).
// Ejecuta: node tests/calicatas/excel_import.cjs
// Fixtures: tests/calicatas/fixtures/excel_import_*.json generados con
// make_excel_import_fixtures.py desde los libros reales (mismo contrato que
// AndroidCalicataExporter::readWorkbookCells: celdas de texto + rangos combinados).
'use strict';
const assert = require('assert');
const fs = require('fs');
const path = require('path');
const vm = require('vm');

const root = path.resolve(__dirname, '..', '..');
const read = rel => fs.readFileSync(path.join(root, rel), 'utf8').replace(/\r\n/g, '\n');
const lib = {};
vm.createContext(lib);
vm.runInContext(read('qml/Mobile/lib/CalicataExcelImport.js').replace(/^\.pragma library\s*/m, ''), lib);
const fixture = name => JSON.parse(read('tests/calicatas/fixtures/' + name));
const pass = msg => console.log('PASS ' + msg);
// Los valores del contexto vm tienen otros prototipos: se comparan como JSON plano.
const deepEq = (actual, expected, msg) => assert.deepStrictEqual(JSON.parse(JSON.stringify(actual)), expected, msg);

const LONG_PROJECT = 'Creación del Servicio de Transitabilidad Vial Interurbana en Puente y Accesos entre '
  + 'Villa Virgen-Lechemayo Distrito de Villa Virgen de la Provincia de la Convención del Departamento de Cusco';

// Emulación del mapeo de celdas de fillOfficialCalicataTemplate (androidcalicataexporter.cpp):
// AG4 proyecto, AY9 código, AJ9-11, AT8-11, AW10, AU8/AU9, escala C21..C81,
// estrato J (de–a m + origen + descripción), AD tipo, AE intervalo, AG AASHTO,
// AH SUCS, AI..AP laboratorio, fila FIN y AH84 observaciones estructuradas.
function emulateNativeExport(state) {
  const h = state.header, cells = {}, merges = ['AG4:BC6', 'AY9:AZ11', 'AH84:BC89'];
  const put = (ref, v) => { if (v !== undefined && v !== null && String(v).length) cells[ref] = String(v); };
  Object.assign(cells, {
    AG1: 'TESTIFICACIÓN DE CALICATA' + (h.description ? '\n' + h.description : ''), AY8: 'CALICATA',
    AH9: 'Supervisor:', AR9: 'X UTM:', J13: 'DESCRIPCIÓN DEL TERRENO', AG13: 'CLASIFICACIÓN AASHTO',
    AH13: 'CLASIFICACIÓN SUCS', AR8: 'P.K.:', AR10: 'Y UTM:', AR11: 'Z UTM:', AU10: 'Zona: '
  });
  put('AG4', h.project_full_name); put('AY9', h.codigo); put('AJ9', h.supervisor); put('AJ10', h.maquina);
  put('AJ11', h.lado_via); put('AT8', h.pk || '---'); put('AT9', h.utm_x); put('AT10', h.utm_y); put('AT11', h.utm_z);
  put('AW10', h.zona);
  const dmy = iso => iso.slice(8, 10) + '/' + iso.slice(5, 7) + '/' + iso.slice(0, 4);
  put('AU8', 'Fecha inicio: ' + dmy(h.fecha_inicio)); put('AU9', 'Fecha fin: ' + dmy(h.fecha_fin));
  const axis = Number(h.requested_depth_m);
  for (let i = 0; i <= 6; i++) put('C' + (21 + i * 10), String(Number((axis * i / 6).toPrecision(15))));
  const row = d => Math.round(22 + d / axis * 60);
  for (const c of state.cortes) {
    const r1 = row(Number(c.de)), r2 = row(Number(c.a)) - 1;
    merges.push('J' + r1 + ':P' + r2, 'AD' + r1 + ':AD' + r2, 'AG' + r1 + ':AG' + r2, 'AH' + r1 + ':AH' + r2);
    put('J' + r1, Number(c.de).toFixed(2) + '–' + Number(c.a).toFixed(2) + ' m\n'
        + (c.material_origin ? c.material_origin + (c.descripcion ? '\n' : '') : '') + c.descripcion);
    put('AD' + r1, c.tipo_muestra === 'Otro' ? c.tipo_otro : c.tipo_muestra);
    put('AE' + r1, Number(c.muestra_desde || 0).toFixed(2) + '-' + Number(c.muestra_hasta || 0).toFixed(2));
    put('AG' + r1, c.aashto); put('AH' + r1, c.sucs);
    ['gmax', 'g2', 'g04', 'g008', 'g002', 'wl', 'lp', 'hum2'].forEach((k, n) => put(String.fromCharCode(73 + n).replace(/^/, 'A') + r1, c[k]));
  }
  put('Q82', 'FIN DE LA CALICATA — ' + axis.toFixed(2) + ' m');
  put('AH84', ['Ubicación: ' + h.ubicacion, 'Nivel freático: ' + (h.water_table_present ? Number(h.water_table_depth).toFixed(2) + ' m' : 'NP'),
               'Profundidad final: ' + axis.toFixed(2) + ' m', state.observaciones].filter(Boolean).join('\n'));
  return { ok: true, fileName: (h.codigo || 'calicata') + '.xlsx', sha256: 'emulated', sheets: [{ name: 'Calicata', cells, merges }] };
}

// ---------------------------------------------------------------- TEST 1
{
  const doc = read('calicatadocument.cpp'), exp = read('androidcalicataexporter.cpp');
  const form = read('qml/Mobile/pages/CalicataFormPage.qml');
  assert.ok(!/selection\["project_full_name"\]\s*=/.test(doc), 'selectProject no escribe el nombre contractual');
  assert.ok(!/selection\[QStringLiteral\("project_full_name"\)\]/.test(doc), 'proyecto principal no escribe el nombre contractual');
  assert.ok(!/merged\[QStringLiteral\("project_full_name"\)\]\s*=\s*remoteRoot/.test(doc), 'la hidratación no pisa el nombre contractual');
  assert.ok(!/header\[QStringLiteral\("projectName"\)\] = header\.value\(QStringLiteral\("project_name"\),\s*header\.value\(QStringLiteral\("project_full_name"/.test(doc),
            'normalización: el espacio no se deriva del nombre contractual');
  // Convergencia Web (exportModel.projectName = projects.name): AG4 usa el
  // proyecto; el nombre antiguo de la ficha solo si aún no tiene proyecto.
  const nameFn = exp.slice(exp.indexOf('QString exportProjectName(const QVariantMap &header'), exp.indexOf('\n}\n', exp.indexOf('QString exportProjectName(')));
  assert.ok(/projectId[\s\S]*QStringLiteral\("projectName"\)[\s\S]*"project_full_name"/.test(nameFn), 'AG4 = projects.name');
  const titleBlock = exp.slice(exp.indexOf('QString title = exportProjectName(header, timestamp);'), exp.indexOf('xlsx.write(QStringLiteral("AG4")'));
  assert.ok(titleBlock.length > 0, 'AG4 usa exportProjectName');
  assert.ok(titleBlock.includes('setShrinkToFit(false)') && titleBlock.includes('setTextWrap(true)') && !/title\.left\(/.test(titleBlock),
            'AG4 con wrap, sin shrink y sin truncar');
  assert.ok(/writeTemplateValue|xlsx\.write\(QStringLiteral\("AY9"\), calicata, codeFmt\)/.test(exp), 'AY9 con el código visible');
  assert.ok(!/baseHeader\.projectName\s*\|\|\s*baseHeader\.project_full_name/.test(form), 'exportState sin fallback a la carpeta');
  assert.ok(!/h\.projectName\s*\|\|\s*h\.project_full_name\s*\|\|\s*h\.nombre_proyecto_completo/.test(form), 'importFromDoc sin carpeta');
  // Importar desde una carpeta "01_CALICATAS" no cambia el proyecto del contenido.
  const r = lib.importWorkbook(fixture('excel_import_C-AA-02.json'), { folderPath: 'LECHEMAYO/01_CALICATAS', name: 'C-AA-02.xlsx' });
  assert.strictEqual(r.state.header.project_full_name, LONG_PROJECT);
  assert.notStrictEqual(r.state.header.project_full_name, '01_CALICATAS');
  assert.strictEqual(r.source.sourceFolderPath, 'LECHEMAYO/01_CALICATAS');
  assert.ok(!('projectName' in r.state.header), 'la importación no toca el espacio de guardado');
  pass('TEST 1 proyecto/carpeta desacoplados (exportador, modelo, formulario e importación)');
}

// ---------------------------------------------------------------- TEST 2
{
  // (a) Excel REAL generado por el exportador de InGe+.
  const r = lib.importWorkbook(fixture('excel_import_ingeplus_native.json'), {});
  assert.strictEqual(r.status, 'OK'); assert.strictEqual(r.adapter, 'InGePlusExcelAdapter');
  const h = r.state.header;
  assert.strictEqual(h.project_full_name, 'Proyecto prueba actualización automática');
  assert.strictEqual(h.description, 'exacavacion manual');
  assert.strictEqual(h.supervisor, 'paola'); assert.strictEqual(h.maquina, 'Miniexcavadora');
  assert.strictEqual(h.utm_x, '277457.45'); assert.strictEqual(h.utm_y, '8677278.16'); assert.strictEqual(h.utm_z, '180.3');
  assert.strictEqual(h.zona, '18L'); assert.strictEqual(h.fecha_inicio, '2026-10-14'); assert.strictEqual(h.fecha_fin, '2026-10-21');
  assert.strictEqual(h.water_table_status, 'NO_ENCONTRADO'); assert.strictEqual(h.requested_depth_m, 10);
  assert.strictEqual(r.state.cortes.length, 2);
  deepEq([r.state.cortes[0].de, r.state.cortes[0].a, r.state.cortes[0].material_origin], ['0.00', '1.00', 'Relleno antrópico']);
  deepEq([r.state.cortes[1].de, r.state.cortes[1].a, r.state.cortes[1].material_origin,
                          r.state.cortes[1].descripcion, r.state.cortes[1].sucs, r.state.cortes[1].aashto,
                          r.state.cortes[1].tipo_muestra, r.state.cortes[1].muestra_desde, r.state.cortes[1].muestra_hasta],
                         ['1.00', '3.00', 'Natural', 'arenoso no es antropico', 'SP', 'A-1-a', 'MI', '1.00', '3.00']);
  deepEq([r.state.cortes[0].tipo_muestra, r.state.cortes[0].tipo_otro], ['Otro', 'relleno antropico']);
  assert.ok(r.state.cortes.every(c => c.id && c.local_stratum_id), 'identidad local nueva por estrato');
  // (b) modelo → (mapeo del exportador) → importador → modelo.
  const model = {
    header: { project_full_name: 'Proyecto prueba', codigo: 'CT-51+425', supervisor: 'Ing. Pérez', maquina: 'Retroexcavadora',
              lado_via: 'Derecho', pk: '51+425', utm_x: '661263.5', utm_y: '8561516', utm_z: '718.2', zona: '18L',
              fecha_inicio: '2026-09-01', fecha_fin: '2026-09-02', ubicacion: 'Tramo II', water_table_present: true,
              water_table_depth: '1.20', requested_depth_m: 3, description: '' },
    cortes: [
      { de: '0.00', a: '0.40', material_origin: 'Relleno antrópico', descripcion: 'Material de afirmado', tipo_muestra: '', tipo_otro: '', aashto: '', sucs: '' },
      { de: '0.40', a: '1.50', material_origin: 'Natural', descripcion: 'Arena limosa, húmeda, color pardo', tipo_muestra: 'MA', tipo_otro: '',
        muestra_desde: '0.40', muestra_hasta: '1.50', aashto: 'A-2-4', sucs: 'SM', gmax: '100', g2: '85', g04: '60', g008: '28', wl: '24', lp: '18', hum2: '12' },
      { de: '1.50', a: '3.00', material_origin: '', descripcion: 'Grava mal gradada con arena', tipo_muestra: 'MS', tipo_otro: '',
        muestra_desde: '1.50', muestra_hasta: '3.00', aashto: 'A-1-a', sucs: 'GP' }
    ],
    observaciones: 'Excavación sin derrumbes.'
  };
  const back = lib.importWorkbook(emulateNativeExport(model), { name: 'CT-51+425.xlsx' });
  assert.strictEqual(back.status, 'OK'); assert.strictEqual(back.adapter, 'InGePlusExcelAdapter');
  for (const k of ['project_full_name', 'codigo', 'supervisor', 'maquina', 'lado_via', 'pk', 'utm_x', 'utm_y', 'utm_z', 'zona',
                   'fecha_inicio', 'fecha_fin', 'ubicacion', 'water_table_depth'])
    assert.strictEqual(back.state.header[k], model.header[k], 'roundtrip ' + k);
  assert.strictEqual(back.state.header.requested_depth_m, 3);
  assert.strictEqual(back.state.observaciones, model.observaciones);
  assert.strictEqual(back.state.cortes.length, 3);
  model.cortes.forEach((c, i) => {
    for (const k of ['de', 'a', 'material_origin', 'descripcion', 'tipo_muestra', 'aashto', 'sucs', 'gmax', 'g2', 'g04', 'g008', 'wl', 'lp', 'hum2'])
      assert.strictEqual(back.state.cortes[i][k], c[k] || '', 'roundtrip estrato ' + (i + 1) + ' ' + k);
  });
  pass('TEST 2 roundtrip nativo (Excel real de InGe+ y modelo CT-51+425 con 3 estratos)');
}

// ---------------------------------------------------------------- TEST 3
{
  const r = lib.importWorkbook(fixture('excel_import_C-AA-02.json'), { name: 'C-AA-02.xlsx' });
  assert.strictEqual(r.status, 'OK'); assert.strictEqual(r.adapter, 'IngemaTestificacionAdapter');
  const h = r.state.header;
  assert.strictEqual(h.project_full_name, LONG_PROJECT);
  assert.strictEqual(h.codigo, 'C-AA-02'); assert.strictEqual(h.code, 'C-AA-02');
  // Celda AT8 "0+620" → formato canónico de la ficha; AW10 "18" → banda derivada (HEURISTIC).
  assert.strictEqual(h.pk, '00+620'); assert.strictEqual(h.supervisor, 'Jessica Sulca'); assert.strictEqual(h.maquina, 'Retroexcavadora');
  assert.strictEqual(h.lado_via, 'Izquierdo'); assert.strictEqual(h.utm_x, '661263'); assert.strictEqual(h.utm_y, '8561516');
  assert.strictEqual(h.utm_z, '718'); assert.strictEqual(h.zona, '18L'); assert.strictEqual(h.fecha_inicio, '2026-05-14');
  assert.strictEqual(r.report.fields.zona.confidence, 'HEURISTIC');
  assert.strictEqual(h.ubicacion, 'Puente Lechemayo - Villa Virgen');
  assert.strictEqual(h.water_table_status, 'ENCONTRADO'); assert.strictEqual(h.water_table_depth, '0.50');
  assert.strictEqual(h.requested_depth_m, 3);
  deepEq(r.state.cortes.map(c => [c.de, c.a]), [['0.00', '0.50'], ['0.50', '2.00'], ['2.00', '3.00']]);
  assert.ok(r.state.cortes[0].descripcion.startsWith('Depósito fluvial'));
  assert.strictEqual(r.state.cortes[2].tipo_muestra, 'MS');
  assert.strictEqual(r.report.fields.projectName.confidence, 'EXACT');
  assert.strictEqual(r.report.fields.calicataCode.confidence, 'EXACT');
  assert.strictEqual(r.report.fields.cortes.confidence, 'HEURISTIC', 'intervalo "300 m" corregido por geometría');
  assert.ok(r.report.warnings.some(w => w.includes('300 m')));
  assert.ok(r.report.warnings.includes(lib.IMAGES_WARNING));
  pass('TEST 3 ficha real C-AA-02 (proyecto, código, cabecera, NF, 3 estratos)');
}

// ---------------------------------------------------------------- TEST 4
{
  const exp = read('androidcalicataexporter.cpp');
  const fn = exp.slice(exp.indexOf('int projectTitleFontSize'), exp.indexOf('bool fillOfficialCalicataTemplate'));
  const sizeFor = new Function('title', fn.replace(/^int projectTitleFontSize\(const QString &title\)\s*/, '')
      .replace('const int n = title.trimmed().size();', 'const n = title.trim().length;'));
  assert.strictEqual(sizeFor(LONG_PROJECT), 22, 'mismo cuerpo que la ficha oficial (22 pt, wrap)');
  assert.ok(sizeFor('x'.repeat(500)) >= 14, 'reducción moderada, nunca ilegible');
  const r = lib.importWorkbook(emulateNativeExport({ header: { project_full_name: LONG_PROJECT, codigo: 'C-AA-02', fecha_inicio: '2026-05-14',
    fecha_fin: '2026-05-14', requested_depth_m: 3, water_table_present: false, ubicacion: 'Lechemayo' },
    cortes: [{ de: '0.00', a: '3.00', descripcion: 'Depósito fluvial', material_origin: '', tipo_muestra: '' }], observaciones: '' }), {});
  assert.strictEqual(r.state.header.project_full_name, LONG_PROJECT, 'texto completo, sin truncar ni carpeta');
  assert.strictEqual(r.state.header.project_full_name.length, LONG_PROJECT.length);
  pass('TEST 4 proyecto largo (AG4 completo con wrap; reimportación íntegra)');
}

// ---------------------------------------------------------------- TEST 5
{
  const unknown = { ok: true, fileName: 'gastos.xlsx', sha256: 'x', sheets: [{ name: 'Hoja1', cells: { A1: 'Fecha', B1: 'Monto', A2: '2026-01-01', B2: '120' }, merges: [] }] };
  const r = lib.importWorkbook(unknown, {});
  assert.strictEqual(r.status, 'NOT_RECOGNIZED'); assert.strictEqual(r.message, 'No pudimos reconocer este formato de calicata.');
  assert.ok(!r.state, 'sin borrador');
  assert.strictEqual(lib.importWorkbook({ ok: false, error: 'Solo se pueden abrir archivos .xlsx.' }, {}).status, 'FAILED');
  assert.strictEqual(lib.importWorkbook(null, {}).status, 'FAILED');
  // Plantilla reconocida pero vacía: no se crea una ficha basura.
  const empty = fixture('excel_import_C-AA-02.json');
  const cells = empty.sheets[0].cells;
  delete cells.AG4; delete cells.AY9;
  assert.strictEqual(lib.importWorkbook(empty, {}).status, 'NOT_RECOGNIZED');
  // Genérico: con etiquetas reconocibles y tabla de estratos.
  const generic = { ok: true, sheets: [{ name: 'Datos', merges: [], cells: {
    A1: 'Proyecto:', B1: 'Mejoramiento vial Tramo III', A2: 'Calicata', B2: 'C-07', A3: 'Este', B3: '500100', A4: 'Norte', B4: '8600200',
    A6: 'Desde', B6: 'Hasta', C6: 'Descripción', D6: 'SUCS', A7: '0', B7: '0.6', C7: 'Limo arenoso', D7: 'ML', A8: '0.6', B8: '1.5', C8: 'Grava', D8: 'GW' } }] };
  const g = lib.importWorkbook(generic, {});
  assert.strictEqual(g.status, 'OK'); assert.strictEqual(g.adapter, 'GenericCalicataExcelAdapter');
  assert.strictEqual(g.state.header.codigo, 'C-07'); assert.strictEqual(g.state.header.project_full_name, 'Mejoramiento vial Tramo III');
  assert.strictEqual(g.state.cortes.length, 2); assert.strictEqual(g.report.fields.calicataCode.confidence, 'HEURISTIC');
  pass('TEST 5 formato desconocido → NOT_RECOGNIZED, lectura fallida → FAILED, genérico con etiquetas');
}

// ---------------------------------------------------------------- TEST 6 · C-AA-01 real
{
  // Fixture generado desde la ficha real C-AA-01.xlsx (solo lectura) con make_excel_import_fixtures.py.
  const r = lib.importWorkbook(fixture('excel_import_C-AA-01.json'), { name: 'C-AA-01.xlsx' });
  assert.strictEqual(r.status, 'OK'); assert.strictEqual(r.adapter, 'IngemaTestificacionAdapter');
  const h = r.state.header;
  // Código y progresiva separados (nunca concatenados).
  assert.strictEqual(h.codigo, 'C-AA-01'); assert.strictEqual(h.code, 'C-AA-01'); assert.strictEqual(h.calicata, 'C-AA-01');
  assert.strictEqual(h.pk, '00+620'); assert.strictEqual(h.progresiva, '00+620');
  assert.strictEqual(h.project_full_name, LONG_PROJECT);
  assert.strictEqual(h.utm_x, '661263'); assert.strictEqual(h.utm_y, '8561516'); assert.strictEqual(h.utm_z, '718');
  assert.strictEqual(h.zona, '18L');
  assert.ok(Math.abs(h.latitude - -13.007932) < 1e-6 && Math.abs(h.longitude - -73.513005) < 1e-6, 'lat/lon canónicas');
  assert.ok(!('datum' in h), 'el datum no está en la ficha: no se inventa');
  assert.strictEqual(h.fecha_inicio, '2026-05-14'); assert.strictEqual(h.fecha_fin, '2026-05-14');
  assert.strictEqual(h.ubicacion, 'Puente Lechemayo - Villa Virgen');
  assert.strictEqual(h.water_table_status, 'ENCONTRADO'); assert.strictEqual(h.water_table_depth, '1.40');
  assert.strictEqual(h.requested_depth_m, 3);
  const [e1, e2] = r.state.cortes;
  assert.strictEqual(r.state.cortes.length, 2);
  deepEq([e1.de, e1.a, e2.de, e2.a], ['0.00', '2.00', '2.00', '3.00']);
  assert.ok(e1.descripcion.includes('muy suelta') && e1.descripcion.includes('saturada'));
  assert.ok(e2.descripcion.includes('Gravas mal gradada') && e2.descripcion.includes('suelta'));
  // Estrato 1: laboratorio presente (fracciones → %), NP; sin muestra.
  deepEq([e1.gmax, e1.g2, e1.g04, e1.g008, e1.hum2, e1.nonplastic_confirmed, e1.tipo_muestra], ['100', '39', '26', '4', '6', true, '']);
  // Estrato 2: muestra en saco, SIN laboratorio inventado.
  assert.strictEqual(e2.tipo_muestra, 'MS'); deepEq([e2.muestra_desde, e2.muestra_hasta], ['2.00', '3.00']);
  for (const k of ['gmax', 'g2', 'g04', 'g008', 'g002', 'wl', 'lp', 'hum2']) assert.strictEqual(e2[k], '', 'estrato 2 sin ' + k);
  // AASHTO/SUCS no están en celdas (solo en las tramas): MISSING, nunca deducidos del dibujo.
  for (const c of r.state.cortes) { assert.strictEqual(c.aashto, ''); assert.strictEqual(c.sucs, ''); }
  assert.strictEqual(r.report.fields['estratos.aashto'].confidence, 'MISSING');
  assert.strictEqual(r.report.fields['estratos.sucs'].confidence, 'MISSING');
  assert.strictEqual(r.report.fields['estratos.humedad_excavabilidad_estabilidad'].confidence, 'MISSING');
  assert.strictEqual(r.report.fields['estratos.laboratorio'].confidence, 'HEURISTIC');
  assert.ok(r.report.warnings.includes(lib.IMAGES_WARNING), 'no finge importar imágenes');
  pass('TEST 6 ficha real C-AA-01 (código/progresiva separados, 18L + lat/lon, NF, estratos, laboratorio sin inventar)');
}

// ---------------------------------------------------------------- integración
{
  const drive = read('qml/Mobile/documents/NothingDocumentsRoot.qml');
  const editor = read('qml/Mobile/pages/CalicatasEditorPage.qml');
  const reader = read('androidcalicataexporter.cpp');
  assert.ok(drive.includes('"ABRIR CON CALICATAS"') && drive.includes('files.download(file)'), 'acción en InGeDrive con la descarga existente');
  assert.ok(editor.includes('function importCalicataExcel(') && editor.includes('root.addNewTab()') && editor.includes('doc.saveDraft()'),
            'editor real + borrador normal');
  assert.ok(read('qml/Mobile/Main.qml').includes('onCalicataExcelOpenRequested'), 'InGeDrive global enruta a Calicatas');
  assert.ok(read('CMakeLists.txt').includes('lib/CalicataExcelImport.js'), 'JS empaquetado en el módulo QML');
  const fnReader = reader.slice(reader.indexOf('QVariantMap AndroidCalicataExporter::readWorkbookCells'));
  for (const guard of ['kMaxBytes', 'kMaxSheets', 'kMaxRows', 'kMaxColumns', 'kMaxCells', '"xlsx"', 'QByteArrayLiteral("PK")', 'Sha256'])
    assert.ok(fnReader.includes(guard), 'lector seguro: ' + guard);
  pass('Integración InGeDrive → Abrir con Calicatas → editor real (estática)');
}

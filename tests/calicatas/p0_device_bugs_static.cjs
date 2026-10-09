// Calicatas — cierre P0 de bugs confirmados en dispositivo (GPS al abrir el mapa,
// nivel freático gráfico, metadatos de foto, nombre corto, generación de foto).
// Ejecuta: node tests/calicatas/p0_device_bugs_static.cjs
'use strict';
const assert = require('assert');
const fs = require('fs');
const path = require('path');
const root = path.resolve(__dirname, '..', '..');
const read = rel => fs.readFileSync(path.join(root, rel), 'utf8').replace(/\r\n/g, '\n');
const pass = msg => console.log('PASS ' + msg);
const between = (src, from, to) => { const a = src.indexOf(from); assert.ok(a >= 0, from); const b = src.indexOf(to, a + from.length); return src.slice(a, b < 0 ? undefined : b); };

const picker = read('qml/Mobile/pages/CalicataPointPicker.qml');
const editor = read('qml/Mobile/pages/CalicatasEditorPage.qml');
const form = read('qml/Mobile/pages/CalicataFormPage.qml');
const exporter = read('androidcalicataexporter.cpp');
const doc = read('calicatadocument.cpp');
const photoEditor = read('qml/Mobile/pages/CalicataPhotoEditor.qml');

// ---------------------------------------------------------------- GPS
{
  const completed = between(picker, 'Component.onCompleted: {', 'Component.onDestruction');
  assert.ok(!completed.includes('centerGps'), 'abrir el selector no pide GPS');
  assert.ok(!/gpsLat|gpsHasFix/.test(completed), 'abrir el selector no reemplaza el punto de la ficha');
  assert.ok(completed.includes('INGE_LOCATION_PICKER_OPEN'));
  const apply = between(picker, 'function applyGpsFix()', 'function gpsDiagnostic');
  assert.ok(apply.includes('if (!awaitingGps || !gpsFixIsFresh())'), 'un fix solo se acepta tras solicitud explícita');
  assert.ok(!apply.includes('var live'), 'sin seguimiento continuo del punto');
  const stop = between(picker, 'function _stopGpsSearch()', 'function applyGpsFix()');
  assert.ok(apply.includes('_stopGpsSearch()') && stop.includes('requestGpsEnabled(false)') && stop.includes('_startedTracking'),
            'one-shot: apaga el tracking que encendió');
  const center = between(picker, 'function centerGps()', 'Timer {');
  assert.ok(center.includes('requestGpsEnabled(true)') && center.includes('requestFreshFix()'), 'la captura GPS se solicita explícitamente');
  assert.ok(picker.includes('"Mi ubicación"') && picker.includes('onTapped: root.centerGps()'), 'GPS explícito');
  assert.ok(picker.includes('GraphicsCore.openEarthPicker(') && !/\bMap\s*\{|MapLibre|QtLocation/.test(picker),
            'sin selección cartográfica duplicada dentro de Calicatas');
  const loaded = between(editor, 'onLoaded: {\n                    var map = item', 'Label {');
  assert.ok(loaded.includes('map.selectCoordinate(') && loaded.includes('"Punto de la ficha"') && !loaded.includes('centerGps'),
            'el host conserva el punto técnico de la ficha como candidato');
  const commit = between(editor, 'text: "Usar esta ubicación"', 'Connections {');
  assert.ok(commit.includes('if (map.selectedSource === "Punto de la ficha") { coordinatePicker.close(); return }')
            && !commit.includes('fromDevice) {'), 'commit del candidato de ficha o GPS');
  const commitFn = between(editor, 'function _commitCoordinateCandidate()', '\n    }\n');
  assert.ok(commit.includes('root._commitCoordinateCandidate()') && commitFn.includes('INGE_LOCATION_COMMIT')
            && commitFn.includes('acceptMapPoint('), 'solo "Usar esta ubicación" persiste');
  const sheet = editor.slice(editor.indexOf('id: coordinateSheet'));
  const cancel = between(sheet, 'text: "Cancelar"', 'CalButton {');
  assert.ok(cancel.includes('coordinatePicker.close()') && !cancel.includes('acceptMapPoint'), 'cancelar no toca la ficha');
  pass('GPS: abrir selector ≠ captura GPS; solicitud one-shot y confirmar/cancelar correctos');
}

// ---------------------------------------------------------------- Nivel freático
{
  const water = between(exporter, 'const QVariantMap profileSetup = header.value(QStringLiteral("profile_setup"))', 'return true;');
  assert.ok(water.includes('show_water_table'), 'respeta Perfil > Mostrar nivel freático');
  assert.ok(water.includes('layout->boundaryRow(waterDepth)') && water.includes('layout->endRow'),
            'misma transformación profundidad → fila que los estratos, hasta el fondo');
  assert.ok(water.includes('"#C6D9F1"'), 'mismo color que C-AA-01 (tema 3 = 1F497D, tinte 0.8)');
  assert.ok(water.includes('setShrinkToFit(false)') && water.includes('setRotation(0)') && !water.includes('BorderMedium'),
            'valor horizontal, sin reducir y sin borde ajeno a la referencia');
  assert.ok(water.includes('PatternSolid') && water.includes('setPatternBackgroundColor') && water.includes('mergeCells'),
            'relleno azul claro combinado NF → fondo');
  assert.ok(water.includes('#FF0000') && water.includes("QString::number(waterDepth, 'g', 4)"), 'indicador rojo con la cota (1.4, 0.75…)');
  assert.ok(!/\b50\b|Q50/.test(water), 'sin filas fijas');
  assert.ok(exporter.includes('lines << QStringLiteral("Nivel freático: ") + waterText;'), 'se mantiene el texto en Observaciones');
  // Plantilla base: filas 22..81 (60 filas) = 0..profundidad final; C-AA-01: 1.40 m de 3.00 → fila 50 (Q50:Q81).
  const row = (d, axis) => 22 + Math.round(d / axis * 60);
  assert.strictEqual(row(1.40, 3.00), 50);
  assert.strictEqual(row(0.75, 3.00), 37);
  assert.strictEqual(row(2.35, 3.00), 69);
  pass('Nivel freático: relleno proporcional (1.40 → Q50:Q81 como C-AA-01; 0.75 → fila 37) + indicador + texto');
}

// ---------------------------------------------------------------- Foto: altitud, proyecto corto, captura
{
  // Regla C-AB-01 (2026-10-07): altitud del rótulo = cota de la calicata (manual o
  // elevación del terreno) con su origen; fecha = fecha de la ficha; hora = hora
  // manual de la ficha o la hora del sistema fijada una vez para ESA foto.
  const sheetMeta = between(doc, 'QVariantMap CalicataDocument::photoSheetMetadata() const', 'meta[QStringLiteral("latitude")]');
  assert.ok(sheetMeta.includes('text({"utm_z", "altitud", "altitude_m"})') && sheetMeta.includes('text({"altitude_source"})'),
            'la altitud de la foto es la cota de la calicata, con su origen');
  // Convergencia Web (CalicataPhotos): rótulo = projects.name; nombre antiguo solo sin proyecto.
  assert.ok(sheetMeta.includes(': text({"projectName", "project_name"});'), 'foto = projects.name');
  assert.ok(!sheetMeta.includes('m_timestamp.value(QStringLiteral("hora"))'), 'sin hora del timestamp de la ficha');
  const apply = between(doc, 'void applyPhotoCapture(', '} // namespace');
  assert.ok(apply.includes('"fecha_inicio"') && apply.includes('sheetTime(header)') && apply.includes('photoSystemTime(capture)')
            && !apply.includes('currentDateTime'), 'fecha de ficha + hora manual/fijada; nunca la hora de composición');
  assert.ok(!/meta\[QStringLiteral\("altitude"\)\]/.test(apply), 'la altitud de captura (elipsoidal) no rotula la foto');
  assert.ok(doc.includes('images[QString("foto%1_capture").arg(idx)] = capture;')
            && doc.includes('QVariantMap syncCapture = photoCaptureMeta(originalStored')
            && doc.includes('images[QString("foto%1_capture").arg(idx)] = syncCapture;'),
            'la captura se registra al tomar/importar la foto (ambas rutas)');
  const exif = between(doc, 'QVariantMap readPhotoExif(', 'QVariantMap photoCaptureMeta(');
  for (const tag of ['0x9003', '0x8825', '0x0006', '0x0002', '0x0004']) assert.ok(exif.includes(tag), 'EXIF ' + tag);
  assert.ok(photoEditor.includes('doc.photoMetadata(slotIndex)'), 'el editor usa los metadatos de ESA foto');
  const titleKeys = between(exporter, 'QString exportProjectName(const QVariantMap &header', '\n}\n');
  assert.ok(titleKeys.includes('QStringLiteral("projectName")') && titleKeys.includes('"project_full_name"'),
            'Excel = projects.name (nombre antiguo solo sin proyecto)');
  assert.ok(form.includes('headerKey: "project_short_name"') && form.includes('headerKey: "project_full_name"')
            && form.includes('readonly property var sheetTypes: ["FICHA DE CALICATA", "FICHA DE CANTERA"]'),
            'nombre largo, nombre corto y tipo de ficha (2 opciones) separados');
  pass('Foto: altitud = cota de la ficha con origen, proyecto = projects.name, fecha de ficha + hora manual/fijada');
}

// ---------------------------------------------------------------- Generación de foto
{
  const done = between(doc, 'QMetaObject::invokeMethod(QCoreApplication::instance(), [self, idx, edit, outPath, versionId, error]()', 'return true;');
  assert.ok(done.includes('if (self->m_closed) {') && done.includes('emit self->derivedPhotoReady(idx, QUrl(), QString(),'),
            'ficha cerrada/reemplazada → ERROR (antes: retorno silencioso = spinner)');
  assert.ok(done.includes('INGE_PHOTO_COMPOSE_FAILED') && done.includes('INGE_PHOTO_COMPOSE_SUCCESS'));
  assert.ok(doc.includes('INGE_PHOTO_COMPOSE_START'));
  const publish = between(photoEditor, 'function publish()', 'function _logRenderPhase');
  assert.ok(publish.includes('try {') && publish.includes('catch (failure)') && publish.includes('_photoResult("ERROR"'),
            'excepción → ERROR, nunca rendering=true permanente');
  assert.ok(publish.includes('job.metadata = currentMetadata(job.metadata)'), 'snapshot coherente al iniciar el job');
  assert.ok(photoEditor.includes('function onClosedChanged()') && photoEditor.includes('interval: 60000'), 'watchdog + cierre de ficha');
  const result = between(photoEditor, 'function _photoResult(', 'readonly property color cPage');
  assert.ok(result.includes('rendering = false'), 'cleanup en todo resultado');
  const wrap = between(doc, 'const QStringList rawLines = photoOverlayLines(edit);', 'qreal textWidth = 0;');
  assert.ok(wrap.includes("split(QLatin1Char(' ')") && wrap.includes('wrapped.size() > 2') && wrap.includes('elidedText'),
            'rótulo: wrap por palabras, máx. 2 líneas por dato, elipsis solo en pantalla');
  pass('Generación de foto: siempre SUCCESS/ERROR; snapshot por job; rótulo acotado');
}

// ---------------------------------------------------------------- C-AA-01 (segunda pasada)
{
  // Valores medidos en C-AA-01.xlsx (hoja Calicata): N.F. = columna Q (ancho 5.33),
  // perfil filas 22..81 (alto 21.75), relleno Q50:Q81 tema 3 tinte 0.8, AH84 con título.
  const template = { firstRow: 22, rows: 60 };
  const fill = (nf, depth) => [template.firstRow + Math.round(nf / depth * template.rows), template.firstRow + template.rows - 1];
  assert.deepStrictEqual(fill(1.40, 3.00), [50, 81], 'equivale a Q50:Q81 de C-AA-01');
  const obs = between(exporter, 'QString structuredObservations(', 'QString imagePathFromState(');
  assert.ok(obs.includes('QStringList lines{QStringLiteral("OBSERVACIONES")};') && !obs.includes('lines << QString();'),
            'AH84: "OBSERVACIONES" + líneas estructuradas + libres, sin línea en blanco');
  assert.ok(/\|\^\\+s\*observaciones\\+s\*\$/.test(obs), 'no duplica el título si viene en el texto libre');
  // Rótulo de C-AA-01: "ZONA 18 661263 E 8561516 N" / "Altitud: 706 m.s.n.m" / "C-AA-01  Proyecto Lechemayo" / "14/05/26  11:02:46".
  const caption = between(doc, 'QStringList photoOverlayLines(', '// Curva tonal');
  assert.ok(caption.includes('QStringLiteral("ZONA ")') && caption.includes('QStringLiteral(" E")') && caption.includes('QStringLiteral(" N")'));
  assert.ok(caption.includes('QStringLiteral("Altitud: %1 m.s.n.m")'));
  assert.ok(caption.includes('identity.join(QStringLiteral("  "))'), 'código y proyecto corto en una línea, sin concatenar la progresiva');
  assert.ok(caption.includes('QStringLiteral("dd/MM/yy")') && caption.includes('when.join(QStringLiteral("  "))'));
  assert.ok(!caption.includes('"UTM WGS84"'), 'sin encabezados que la referencia no tiene');
  const capture = between(doc, 'void applyPhotoCapture(', '} // namespace');
  assert.ok(capture.includes('"photo_latitude"') && !capture.includes('meta[QStringLiteral("latitude")] ='),
            'C-AA-01 muestra las coordenadas de la calicata en todas las fotos');
  assert.ok(doc.includes('mergeCaptureLocation(capture, m_nextCaptureLocation') && form.includes('setNextPhotoCaptureLocation('),
            'altitud del dispositivo en la captura (sin encender GPS)');
  pass('C-AA-01: NF Q50:Q81 #C6D9F1, observaciones con título, rótulo de 4 líneas, coordenadas de la calicata');
}

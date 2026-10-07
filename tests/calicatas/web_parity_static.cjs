// Interpreted/static Web parity checks. No Qt build, network or ADB required.
const fs = require('node:fs');
const path = require('node:path');
const assert = require('node:assert/strict');
const root = path.resolve(__dirname, '../..');
const read = file => fs.readFileSync(path.join(root, file), 'utf8').replace(/\r\n/g, '\n');
let count = 0;
function test(name, fn) { fn(); ++count; console.log('WEB_PARITY_OK ' + name); }

const cloud = read('calicatacloudservice.cpp');
const cloudH = read('calicatacloudservice.h');
const doc = read('calicatadocument.cpp');
const form = read('qml/Mobile/pages/CalicataFormPage.qml');
const editor = read('qml/Mobile/pages/CalicatasEditorPage.qml');
const rules = read('qml/Mobile/lib/CalicataRules.js');
const cmake = read('CMakeLists.txt');
const main = read('main_mobile.cpp');

test('cloud service is compiled and exposed to QML', () => {
  assert.ok(cmake.includes('calicatacloudservice.cpp'));
  assert.ok(main.includes('qmlRegisterSingletonInstance("InGe", 1, 0, "CalicataCloud"'));
  assert.ok(cloudH.includes('Q_INVOKABLE QString syncDocument'));
  assert.ok(cloudH.includes('Q_INVOKABLE void loadRemoteDocument'));
});

test('project selector is no longer coupled to Renditions', () => {
  // Proyectos = membresías activas y vigentes de la cuenta (RPC Web), sin duplicados.
  const refresh = cloud.slice(cloud.indexOf('void CalicataCloudService::refreshProjects()'), cloud.indexOf('void CalicataCloudService::listProjectCalicatas('));
  assert.ok(refresh.includes('postRpc(QStringLiteral("list_my_project_memberships_v01")'));
  assert.ok(refresh.includes('membership_status")).toString() != QLatin1String("ACTIVO")) continue'));
  assert.ok(refresh.includes('(starts.isValid() && starts > now) || (ends.isValid() && ends <= now)'));
  assert.ok(refresh.includes('seen.contains(id)'));
  const projectArea = form.slice(form.indexOf('id: projectPickerPopup'), form.indexOf('// helper (porque tu form'));
  assert.ok(projectArea.includes('CalicataCloud.projects'));
  // La selección vive en _applyProjectSelection (justo antes del popup) y el popup la invoca.
  const applySelection = form.slice(form.indexOf('function _applyProjectSelection(project)'), form.indexOf('id: projectPickerPopup'));
  assert.ok(applySelection.includes('if (!root.doc.selectProject(selection)) {'));
  assert.ok(applySelection.includes('CalicataCloud.resolveProjectWorkspace(selection.projectId)'));
  assert.ok(!applySelection.includes('RenditionFlutterBridge'));
  assert.ok(projectArea.includes('root._applyProjectSelection('));
  assert.ok(!projectArea.includes('RenditionFlutterBridge'));
});

test('canonical root identity is project_id + calicata id + row_version', () => {
  assert.ok(cloud.includes('create_my_project_calicata_v02'));
  assert.ok(cloud.includes('query.addQueryItem(QStringLiteral("project_id"), QStringLiteral("eq.") + ctx->projectId)'));
  assert.ok(cloud.includes('query.addQueryItem(QStringLiteral("row_version"), QStringLiteral("eq.") + QString::number(ctx->rowVersion))'));
  // La ficha remota se abre por snapshot atómico y se rechaza si no coincide la identidad.
  assert.ok(cloud.includes('postRpc(QStringLiteral("get_my_calicata_snapshot_v01"),\n            {{QStringLiteral("p_project_id"), pid}, {QStringLiteral("p_calicata_id"), cid}}'));
  assert.ok(/remoteRoot\.value\(QStringLiteral\("id"\)\)\.toString\(\) != cid\s*\n\s*\|\| remoteRoot\.value\(QStringLiteral\("project_id"\)\)\.toString\(\) != pid\s*\n\s*\|\| remoteRoot\.value\(QStringLiteral\("row_version"\)\)\.toLongLong\(\) < 1/.test(cloud));
});

test('list is scoped to project and excludes archived rows', () => {
  // Se consulta por proyecto; las archivadas se separan a la vista "Archivadas"
  // (conservan su código UNIQUE por proyecto) y nunca entran en la lista principal.
  const list = cloud.slice(cloud.indexOf('void CalicataCloudService::listProjectCalicatas('), cloud.indexOf('void CalicataCloudService::resolveProjectWorkspace('));
  assert.ok(list.includes('query.addQueryItem(QStringLiteral("project_id"), QStringLiteral("eq.") + pid)'));
  assert.ok(list.includes('QStringLiteral("created_at.desc")'));
  assert.ok(/== QLatin1String\("ARCHIVADO"\)\)\s*\n\s*m_archivedProjectCalicatas\.append\(value\);\s*\n\s*else\s*\n\s*m_projectCalicatas\.append\(value\);/.test(list));
  assert.ok(list.includes('emit projectCalicatasLoaded(pid, m_projectCalicatas)'));
});

test('canonical strata, samples and lab RPCs are wired', () => {
  for (const rpc of [
    'add_my_calicata_stratum_v03', 'update_my_calicata_stratum_v03',
    'add_my_calicata_sample_v01', 'update_my_calicata_sample_v01',
    'delete_my_calicata_sample_v01', 'upsert_my_calicata_lab_result_v02',
    'get_my_calicata_snapshot_v01'
  ]) assert.ok(cloud.includes(rpc), rpc);
  // Convergencia Web: sin RPC que no existen en DEV ni en el contrato Web.
  for (const rpc of ['upsert_my_calicata_lab_result_v03', 'set_my_calicata_lab_extension_v01',
                     'set_my_calicata_stratum_field_classification_v01'])
    assert.ok(!cloud.includes(rpc), rpc);
  // Los resultados de laboratorio llegan en el mismo snapshot que estratos y muestras.
  for (const key of ['strata', 'samples', 'labs'])
    assert.ok(cloud.includes(`snapshot.value(QStringLiteral("${key}")).toList()`), key);
  assert.ok(cloud.includes('p_expected_calicata_row_version'));
  assert.ok(cloud.includes('remote_stratum_id'));
  assert.ok(cloud.includes('remote_sample_id'));
});

test('stratum depths obey canonical 0.05m contract', () => {
  assert.ok(cloud.includes('depth / 0.05'));
  assert.ok(cloud.includes('Los límites de estrato deben usar pasos de 0.05 m'));
  assert.ok(rules.includes('to / 0.05'));
  assert.ok(rules.includes('Hasta debe avanzar en pasos de 0.05 m.'));
});

test('smart document is materialized after canonical data sync', () => {
  assert.ok(cloud.includes('ensure_calicata_smart_document_v01'));
  assert.ok(cloud.includes('document_node_id'));
  assert.ok(cloud.includes('parent_node_id'));
  assert.ok(cloud.includes('IDEMPOTENT_REPLAY'));
  assert.ok(doc.includes('documentNodeId'));
  assert.ok(doc.includes('documentSpaceId'));
});

test('remote sheet can be listed and opened from Android', () => {
  assert.ok(editor.includes('Abrir ficha online...'));
  assert.ok(editor.includes('CalicataCloud.listProjectCalicatas(projectId)'));
  assert.ok(editor.includes('CalicataCloud.loadRemoteDocument'));
  assert.ok(editor.includes('onRemoteLoadSucceeded'));
});

test('remote archive is CAS and local archive remains non-destructive', () => {
  assert.ok(cloud.includes('QStringLiteral("ARCHIVADO")'));
  assert.ok(cloud.includes('archiveDocument(CalicataDocument *document)'));
  assert.ok(editor.includes('CalicataCloud.archiveDocument(currentDoc)'));
  const archive = cloud.slice(cloud.indexOf('QString CalicataCloudService::archiveDocument('));
  // Borrador nunca sincronizado: archivo local, conserva los datos.
  assert.ok(/remoteId\.isEmpty\(\)\) \{[\s\S]{0,200}document->transitionStatus\(QStringLiteral\("ARCHIVADO"\)\)/.test(archive));
  // Sincronizado: CAS remoto por id + project_id + row_version; sin red no archiva.
  const patch = cloud.slice(cloud.indexOf('::patchRemoteStatus('));
  assert.ok(patch.includes('query.addQueryItem(QStringLiteral("row_version"), QStringLiteral("eq.") + QString::number(rowVersion))'));
  assert.ok(archive.includes('Archivar una calicata sincronizada requiere conexión. Los datos locales se conservan.'));
});

test('duplicate error is mapped to project-scoped human message', () => {
  assert.ok(cloud.includes('23505'));
  assert.ok(cloud.includes('Ya existe una calicata con ese código en este proyecto.'));
});

test('Web canonical observations and remote identity are adopted locally', () => {
  assert.ok(doc.includes('remoteRoot.contains(QStringLiteral("observations"))'));
  assert.ok(doc.includes('remoteCalicataId'));
  assert.ok(doc.includes('remoteRowVersion'));
});

console.log(`${count} Web-parity static checks completed; Qt/Android runtime USER_BUILD_REQUIRED`);

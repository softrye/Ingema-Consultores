const fs = require('fs');
const path = require('path');
const assert = require('assert');
const root = path.resolve(__dirname, '../..');
const read = rel => fs.readFileSync(path.join(root, rel), 'utf8');
let count = 0;
function test(name, fn) { fn(); count++; console.log('PRE_MAPLIBRE_OK', name); }

test('camera uses app-private FileProvider output instead of pending MediaStore row', () => {
  const cpp = read('permissionhelper.cpp');
  const paths = read('android/res/xml/nothing_file_paths.xml');
  const manifest = read('android/AndroidManifest.xml');
  assert.ok(cpp.includes('FileProvider", "getUriForFile"'));
  assert.ok(cpp.includes('getCacheDir'));
  assert.ok(cpp.includes('calicata_camera'));
  assert.ok(cpp.includes('grantUriPermission'));
  assert.ok(cpp.includes('setClipData'));
  assert.ok(cpp.includes('camera_empty_output'));
  assert.ok(cpp.includes('camera_invalid_output'));
  assert.ok(paths.includes('<cache-path name="inge_camera_captures" path="calicata_camera/"'));
  assert.ok(manifest.includes('android.media.action.IMAGE_CAPTURE'));
});

test('photo slot only receives photoSelected after validated private import', () => {
  const cpp = read('permissionhelper.cpp');
  const qml = read('qml/Mobile/pages/CalicataFormPage.qml');
  const finish = cpp.slice(cpp.indexOf('void PermissionHelper::finishPhotoActivity'), cpp.indexOf('bool PermissionHelper::isLocationServiceEnabled'));
  assert.ok(finish.indexOf('QImageReader probe') < finish.indexOf('emit photoSelected'));
  assert.ok(finish.indexOf('copyContentUriToPrivateCache') < finish.indexOf('emit photoSelected'));
  assert.ok(qml.includes('function _commitPendingPhoto(withPrintedData)'));
  assert.ok(qml.includes('!root._pendingPickedUrl'));
  assert.ok(qml.includes('Perms.releaseImportedPhoto(localUrl)'));
});

test('open sheet is redirected to InGeDrive Smart Documents, not Proyecto_Local', () => {
  const editor = read('qml/Mobile/pages/CalicatasEditorPage.qml');
  const docsQml = read('qml/Mobile/documents/NothingDocumentsRoot.qml');
  const docsCpp = read('src/documents/nothingdocuments.cpp');
  const fn = editor.slice(editor.indexOf('function openDialogAbrirCalicata()'), editor.indexOf('// ===== DOC FACTORY'));
  assert.ok(fn.includes('inGeDriveCalicataPopup.open()'));
  assert.ok(fn.includes('driveCalicataBrowser.openDriveRoot()'));
  assert.ok(!fn.includes('Proyecto_Local'));
  assert.ok(docsQml.includes('signal calicataOpenRequested'));
  assert.ok(docsCpp.includes('targetType=="CALICATA"'));
  assert.ok(docsCpp.includes('emit calicataOpenRequested(projectId,targetId)'));
});

test('project source falls back to projects RLS when memberships are empty', () => {
  const cpp = read('authsession.cpp');
  const hdr = read('authsession.h');
  assert.ok(hdr.includes('loadAssignedProjectsByRls'));
  assert.ok(cpp.includes('PROJECT_MEMBERSHIPS_EMPTY fallback=SUPABASE_RLS_PROJECTS'));
  assert.ok(cpp.includes('PROJECT_SOURCE=SUPABASE_RLS'));
  assert.ok(cpp.includes('m_api->restUrl(QStringLiteral("projects"))'));
  assert.ok(cpp.includes('loadProjectCapabilities(0, generation)'));
});

test('default Ingema logo is the full horizontal production asset', () => {
  const qrc = read('resources.qrc');
  const form = read('qml/Mobile/pages/CalicataFormPage.qml');
  const icons = read('qml/Mobile/lib/PropACalicataIconMap.js');
  const exporter = read('androidcalicataexporter.cpp');
  const asset = path.join(root, 'images/INGEMA_LOGO_COMPLETO.png');
  assert.ok(qrc.includes('alias="INGEMA_LOGO_COMPLETO.png"'));
  assert.ok(form.includes('qrc:/images/INGEMA_LOGO_COMPLETO.png'));
  assert.ok(icons.includes('qrc:/images/INGEMA_LOGO_COMPLETO.png'));
  assert.ok(exporter.includes(':/images/INGEMA_LOGO_COMPLETO.png'));
  assert.ok(fs.statSync(asset).size > 1000);
});

test('application QML timers in current pre-MapLibre scope are non-negative', () => {
  const files = [
    'qml/Mobile/pages/CalicataFormPage.qml',
    'qml/Mobile/pages/CalicatasEditorPage.qml',
    'qml/Mobile/documents/NothingDocumentsRoot.qml'
  ];
  for (const rel of files) {
    const src = read(rel);
    for (const m of src.matchAll(/\binterval\s*:\s*(-?\d+(?:\.\d+)?)/g)) {
      assert.ok(Number(m[1]) >= 1, `${rel} contains unsafe timer interval ${m[1]}`);
    }
  }
});

console.log(`${count} pre-MapLibre fix checks completed; Android runtime USER_BUILD_REQUIRED`);

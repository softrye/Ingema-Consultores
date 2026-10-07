const fs = require('fs');
const path = require('path');

const root = path.resolve(__dirname, '..', '..');
const read = rel => fs.readFileSync(path.join(root, rel), 'utf8');
const form = read('qml/Mobile/pages/CalicataFormPage.qml');
const editor = read('qml/Mobile/pages/CalicatasEditorPage.qml');
const permsH = read('permissionhelper.h');
const permsCpp = read('permissionhelper.cpp');
const graphicsH = read('src/graphics/InGeGraphicsCore.h');
const graphicsCpp = read('src/graphics/InGeGraphicsCore.cpp');
const nativeMain = read('main_mobile.cpp');
const mainQml = read('qml/Mobile/Main.qml');

function ok(name, condition) {
  if (!condition) {
    console.error('CLOSURE_1_4_FAIL ' + name);
    process.exit(1);
  }
  console.log('CLOSURE_1_4_OK ' + name);
}

// Diseño vigente (commit 03563ad): Back Android NO recorre etapas; solo cierra
// superficies temporales. Las etapas se recorren con Dock "Anterior"/swipe,
// que retroceden exactamente una etapa vía goPreviousStage().
function fnBody(src, name) {
  const i = src.indexOf('function ' + name + '(');
  if (i < 0) return '';
  let depth = 0;
  for (let k = src.indexOf('{', i); k < src.length; ++k) {
    if (src[k] === '{') depth++;
    else if (src[k] === '}' && --depth === 0) return src.slice(i, k + 1);
  }
  return '';
}
const formBack = fnBody(form, 'handleBack');
const previousStage = fnBody(form, 'goPreviousStage');
ok('Back closes temporary surfaces and never walks Calicatas stages',
   formBack.length > 0 && !/stageIndex\s*=/.test(formBack) && !formBack.includes('goPreviousStage') &&
   formBack.includes('if (photoViewer.opened) { photoViewer.close(); return true }') &&
   /if \(!commitPendingField\(\)\) return true\s*\n\s*return false\s*\n\s*\}$/.test(formBack));
ok('Previous stage moves exactly one stage (Dock Anterior / swipe)',
   previousStage.includes('if (stageIndex <= 0) return false') &&
   previousStage.includes('var previousStage = Math.max(0, stageIndex - 1)') &&
   previousStage.includes('stageIndex = previousStage') &&
   /commandId === "calicatas\.previous"\)\s*\n\s*form\.goPreviousStage\(\)/.test(editor));

ok('Editor clears stale workspace-exit arm after internal Back',
   editor.includes('if (formLoader.item && formLoader.item.handleBack()) {') &&
   editor.includes('_backAtWorkspace = false'));

ok('Main gives Calicatas internal surfaces the Back first, then leaves safely (autosave, deferred)',
   mainQml.includes('var currentPage = pageIndex === 1 ? app.activeCalicataEditor : pageLoader.item') &&
   /typeof currentPage\.handleBack === "function"\s*\n\s*&& currentPage\.handleBack\(\)\) \{/.test(mainQml) &&
   mainQml.includes('if (pageIndex !== 1 && currentPage && typeof currentPage.canGoBack === "function"') &&
   mainQml.includes('if (pageIndex === 1) return leaveCalicatasSafely()') &&
   /function leaveCalicatasSafely\(\) \{\s*\n\s*if \(leavingCalicatas\)/.test(mainQml));

const legacySlotAutoAction = form.includes('onClicked: { root.activePhotoCategory = photoCategory.slot; if (root._hasPhoto(photoCategory.slot)) photoViewer.open(); else root.requestPickPhoto(photoCategory.slot) }');
ok('Photo slot selection no longer auto-opens gallery', !legacySlotAutoAction &&
   form.includes('TapHandler { id: photoCardTap; onTapped: root.activePhotoCategory = photoCard.slot }'));

const runPhotoAction = fnBody(form, 'runPhotoAction');
ok('Selected photo slot exposes explicit camera and gallery actions',
   form.includes('["capture", "Tomar foto", "action.camera"], ["pick", "Importar", "documents.upload"]') &&
   form.includes('onClicked: root.runPhotoAction(modelData[0], photoCard.slot)') &&
   runPhotoAction.includes('if (id === "capture") root.requestCapturePhoto(idx)') &&
   runPhotoAction.includes('else if (id === "pick") root.requestPickPhoto(idx)'));

ok('Photo result dialog is deferred until Qt application is active',
   form.includes('_photoDialogOpenPending') &&
   form.includes('Qt.application.state !== Qt.ApplicationActive') &&
   form.includes('_openPendingPhotoDialogWhenReady()'));

ok('External photo Activity lifecycle is bridged to GraphicsCore',
   permsH.includes('externalPhotoActivityStarted') &&
   permsH.includes('externalPhotoActivityFinished') &&
   permsCpp.includes('emit externalPhotoActivityStarted();') &&
   permsCpp.includes('emit externalPhotoActivityFinished();') &&
   nativeMain.includes('&PermissionHelper::externalPhotoActivityStarted') &&
   nativeMain.includes('&InGeGraphicsCore::prepareForExternalActivity') &&
   nativeMain.includes('&PermissionHelper::externalPhotoActivityFinished') &&
   nativeMain.includes('&InGeGraphicsCore::completeExternalActivity'));

ok('Graphics resources are non-persistent only during external photo Activity and restored after ApplicationActive',
   graphicsH.includes('prepareForExternalActivity') &&
   graphicsH.includes('completeExternalActivity') &&
   graphicsCpp.includes('setPersistentGraphics(false)') &&
   graphicsCpp.includes('setPersistentSceneGraph(false)') &&
   graphicsCpp.includes('applicationState() != Qt::ApplicationActive') &&
   graphicsCpp.includes('setPersistentGraphics(true)') &&
   graphicsCpp.includes('setPersistentSceneGraph(true)'));

const qmlScope = [
  form,
  editor,
  mainQml
];
let negativeLiteral = false;
for (const source of qmlScope) {
  if (/interval\s*:\s*-\s*\d/.test(source)) negativeLiteral = true;
}
ok('Calicatas/Main QML contains no literal negative Timer interval', !negativeLiteral);

console.log('9 closure static checks completed; Android runtime USER_BUILD_REQUIRED');

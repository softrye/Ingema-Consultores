'use strict';
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const root = path.resolve(__dirname, '../..');
const read = rel => fs.readFileSync(path.join(root,rel),'utf8');
const main = read('qml/Mobile/Main.qml');
const documents = read('qml/Mobile/documents/NothingDocumentsRoot.qml');
const entry = read('qml/Mobile/documents/NothingEntry.qml');
const profile = read('qml/Mobile/pages/ProfilePageContent.qml');
const earth = read('android/assets/cesium/index.html');
const css = read('android/assets/cesium/ui/inge-earth-ui.css');
const java = read('android/src/com/ingema/ingeplus/InGeQtActivity.java');
assert.ok(documents.includes('MobileBackend.NothingDocuments'), 'Document controller must remain');
for(const token of ['files.navigate("drive")','files.open(file)','files.download(file)','files.archive','files.retrySync','files.paste','files.toggleSelection','FlowCore.ContextPublisher'])
  assert.ok(documents.includes(token), 'Document operation missing: '+token);
assert.ok(entry.includes('cell.activated(cell.entry)') && entry.includes('cell.menuRequested(cell.entry)'));
assert.ok(profile.includes('root.closeSession()'), 'Profile sign-out must remain');
assert.ok(main.includes('openAccountSwitchSheetV18()') && main.includes('switchSavedAccountV20(accountData.id)'));
assert.ok(!main.includes('text: "InGe+ IA"') && !main.includes('text: "InGe Core"'));
assert.match(java, /public static boolean showAssistant\(String visuals\)\s*\{\s*return false;/);
assert.ok(!earth.includes('id="earthBoot"'));
assert.ok(earth.includes('window.InGeEarthBoot'), 'Phase contract retained');
assert.ok(!/@keyframes|\banimation\s*:|\btransition\s*:|\bbox-shadow\s*:|\bbackdrop-filter\s*:/.test(css));
for(const f of ['CalicataFormPage.qml','CalicatasEditorPage.qml','CalicataReview.qml','CalicataPhotoEditor.qml']){
  const c=read('qml/Mobile/pages/'+f);
  assert.ok(!/Behavior on\s+\w+\s*\{/.test(c), f+' still contains decorative Behaviors');
}
console.log('PASS visual_zero_continuation_static');

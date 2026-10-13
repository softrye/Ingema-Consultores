const fs = require('node:fs');
const vm = require('node:vm');
const assert = require('node:assert/strict');
const path = require('node:path');
const source = fs.readFileSync(path.join(__dirname, '../../qml/Mobile/pages/CalicatasEditorPage.qml'), 'utf8');
function method(name) {
  const found = source.match(new RegExp('function ' + name + '\\([^]*?^    }', 'm'));
  assert.ok(found, name); return found[0];
}
let syncs = 0;
const doc = {instanceId:'doc', header:{projectId:'project'}, saveDraft:()=>true};
const root = {_savingCloudDocId:'', _autoSyncDocId:'doc', _driveJsonBusy:false,
  _queuedSaveDocId:'', currentDoc:doc, currentIndex:0, currentTab:{tid:1,docId:'doc'},
  _docInstanceId:()=> 'doc', _workspaceCodeConflict:()=>'', showMsg(){}, _syncTabFromDoc(){}};
const deferred=[];
const ctx = vm.createContext({root,currentTab:root.currentTab,currentIndex:0,console,
  _syncDocsList(){},_docAt:()=>doc,_docInstanceId:()=> 'doc',_syncFormIntoDoc:()=>true,
  _finishReviewCorrectionAfterSave(){},_syncTabFromDoc(){},_clearPendingSave(){},
  driveJsonAutosave:{stop(){}}, Qt:{callLater:fn=>deferred.push(fn)},
  CalicataCloud:{syncDocument(){syncs++;return 'doc';}}});
vm.runInContext(method('doSave'),ctx);
ctx.doSave(false); ctx.doSave(false);
assert.equal(syncs,0,'manual save waits for autosave instead of racing its row_version');
assert.equal(root._queuedSaveDocId,'doc','repeated manual request is coalesced');
vm.runInContext(method('_resumeQueuedSave'),ctx);
root.doSave=()=>syncs++;
root._autoSyncDocId='';
ctx._resumeQueuedSave('other');
assert.equal(deferred.length,0,'another document cannot consume the request');
ctx._resumeQueuedSave('doc'); ctx._resumeQueuedSave('doc');
assert.equal(deferred.length,1,'one completion releases one manual save');
deferred.shift()();
assert.equal(syncs,1);
root._queuedSaveDocId='doc';
root._docInstanceId=()=> 'another-tab';
ctx._resumeQueuedSave('doc');
assert.equal(deferred.length,0,'tab switch never saves a different document');
console.log('PASS save waits/coalesces across autosave and document changes');

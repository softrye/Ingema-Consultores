const fs = require('node:fs');
const vm = require('node:vm');
const assert = require('node:assert/strict');
const path = require('node:path');
const form = fs.readFileSync(path.join(__dirname,'../../qml/Mobile/pages/CalicataFormPage.qml'),'utf8');
const editor = fs.readFileSync(path.join(__dirname,'../../qml/Mobile/pages/CalicatasEditorPage.qml'),'utf8');
function method(source,name) {
  const found = source.match(new RegExp('function '+name+'\\([^]*?^    }','m'));
  assert.ok(found,name); return found[0];
}
const root = {_assignedStratumIds:false,_enumIndex:()=>-1,_newLabUuid:()=>{throw Error('remote row generated a new identity');}};
// _normalizeCorte canonicaliza AASHTO con la librería real de reglas (sin stubs).
const Rules = vm.createContext({});
vm.runInContext(fs.readFileSync(path.join(__dirname,'../../qml/Mobile/lib/CalicataRules.js'),'utf8').replace('.pragma library',''),Rules);
const model = vm.createContext({root,Rules,_defaultCorte:()=>({}),JSON,Object,String});
vm.runInContext(method(form,'_normalizeCorte'),model);
const row = model._normalizeCorte({id:'stratum',remote_stratum_id:'stratum',
  sample_code:undefined,remote_sample_id:undefined,
  _extraJson:JSON.stringify({passing_no4:73,primary_sucs:'SM'})});
assert.equal(row.sample_code,'');
assert.equal(row.remote_sample_id,'');
assert.equal(row.local_stratum_id,'stratum');
assert.equal(root._assignedStratumIds,false,'remote identities must not trigger dirty migration');
assert.equal(JSON.parse(row._extraJson).passing_no4,73,'lab metadata survives normalization');
assert.equal(model._normalizeCorte(row).local_stratum_id,'stratum');
let writes=0;
const doc = {closed:false,dirty:false,applyingCloudState:false,instanceId:'local',header:{remoteCalicataId:'cloud'}};
const item = {dirty:false,_loading:false,doc,_docInstanceId:d=>d.instanceId,exportState(){writes++;return {};}};
// formValue: mismo helper que CalicatasEditorPage (lectura segura del formulario cargado).
const state = {currentDoc:doc,_remoteLoadingDocId:'',_docInstanceId:d=>d.instanceId,
  formValue:(form,name)=>form ? form[name] : undefined};
const sync = vm.createContext({root:state,formLoader:{item},_docInstanceId:d=>d.instanceId,console});
vm.runInContext(method(editor,'_syncFormIntoDoc'),sync);
assert.equal(sync._syncFormIntoDoc(doc,false),true);
assert.equal(writes,0,'clean hydrate must not export presentation defaults into the domain');
item.dirty=true;
state._remoteLoadingDocId='local';
assert.equal(sync._syncFormIntoDoc(doc,false),true);
assert.equal(writes,0,'hydrate suppresses autosave even while a previous form is dirty');
state._remoteLoadingDocId='';
assert.equal(sync._syncFormIntoDoc(doc,false),true);
assert.equal(writes,1,'a real user edit is exported normally');
let synced=0;
Object.assign(state,{leaving:false,_autoSyncDocId:'',_savingCloudDocId:'',_publishingDocId:'',
  _driveJsonBusy:false,_archivingCloudDocId:'',_workspaceCodeConflict:()=>'',_lastAutoSyncMs:0});
Object.assign(doc,{syncState:'SYNCED',status:'BORRADOR',header:{projectId:'project',code:'C-1',remoteCalicataId:'cloud'}});
const queue=vm.createContext({root:state,CalicataCloud:{syncDocument(){synced++;return 'local';}},Date,String});
vm.runInContext(method(editor,'_queueAutoCloudSync'),queue);
queue._queueAutoCloudSync(doc);
assert.equal(synced,0,'remote hydrate remains up to date without a write');
doc.syncState='PENDING'; doc.dirty=true;
queue._queueAutoCloudSync(doc);
assert.equal(synced,1,'the subsequent user edit is enqueued');
console.log('PASS absent samples, stable stratum identity, lab metadata, hydrate suppression, next user edit');

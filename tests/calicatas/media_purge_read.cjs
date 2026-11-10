'use strict';
const test=require('node:test'),assert=require('node:assert/strict'),fs=require('node:fs'),path=require('node:path'),vm=require('node:vm');
const base=path.join(__dirname,'../..');
const read=p=>fs.readFileSync(path.join(base,p),'utf8');
const native=read('calicatacloudservice.cpp'),form=read('qml/Mobile/pages/CalicataFormPage.qml'),home=read('qml/Mobile/pages/CalicatasHome.qml');
function block(source,marker){const start=source.indexOf(marker);assert(start>=0,'missing '+marker);let a=source.indexOf('{',start),depth=1,b=a+1;for(;depth&&b<source.length;b++){if(source[b]==='{')depth++;if(source[b]==='}')depth--;}return source.slice(a+1,b-1);}
test('signing has an authenticated lifecycle preflight and no direct PURGED download',()=>{
 const source=block(native,'void CalicataCloudService::downloadStorageObject(');
 assert.match(source,/readCalicataState/);assert.match(source,/PURGED/);assert.match(source,/downloadStorageObjectReady/);
});
test('a missing object never triggers a new upload from a read callback',()=>{
 const photo=block(native,'void CalicataCloudService::downloadRemotePhotoReady('),logo=block(native,'void CalicataCloudService::loadRemoteLogosReady(');
 assert.doesNotMatch(photo,/enqueuePhotoSync/);assert.doesNotMatch(logo,/enqueueLogoSync/);
});
test('outbox checks the same lifecycle before publishing',()=>{
 const source=block(native,'void CalicataCloudService::processMediaEntry(');
 assert.match(source,/readCalicataState/);assert.match(source,/PURGED/);assert.match(source,/processMediaEntryReady/);
 assert.match(source,/m_mediaFlushing = false/);assert.match(source,/flushMedia\(\)/);
});
test('PURGED logo clears the read error without touching the cached selection',()=>{
 const states={},ctx={root:{doc:{instanceId:'local'},_setLogoReadState:(k,state,message)=>{states[k]={state,message};}}};vm.createContext(ctx);
 vm.runInContext('function handle(localId,category,message){'+block(form,'function onRemoteLogoReadFailed(')+'}',ctx);
 ctx.handle('local','PROJECT','PURGED');assert.deepEqual(states.PROJECT,{state:'PURGED',message:''});
 ctx.handle('local','PROJECT','HTTP_403');assert.equal(states.PROJECT.state,'ERROR');
});
test('active lists exclude purged local mirrors but retain unsynchronized drafts',()=>{
 const ctx={CalicataCloud:{purgedCalicataIds:['gone']},home:{serviceAvailable:true},serviceAvailable:true};vm.createContext(ctx);
 vm.runInContext('function isRemotePurged(remoteId){'+block(home,'function isRemotePurged(')+'}',ctx);
 const rows=[{remoteId:'gone'},{remoteId:'live'},{remoteId:''}];assert.equal(rows.filter(r=>!ctx.isRemotePurged(r.remoteId)).length,2);assert.equal(rows.length,3);
 assert.match(block(home,'readonly property var allRows:'),/isRemotePurged\(rid\)/);
 assert.match(block(home,'readonly property var allRows:'),/isRemotePurged\(remote\)/);
});

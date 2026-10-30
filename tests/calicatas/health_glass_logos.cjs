'use strict';
// Sin Qt, red ni escrituras de datos: reglas reales de diagnóstico y logos QML.
const assert = require('assert');
const fs = require('fs');
const path = require('path');
const vm = require('vm');
const read = p => fs.readFileSync(path.join(__dirname, '../..', p), 'utf8');
const diag = {};
vm.createContext(diag);
vm.runInContext(read('qml/Mobile/lib/CalicataDiagnostics.js').replace('.pragma library', ''), diag);
const cases = [
  ['borrador normal', {hasDocument:true,syncState:'LOCAL'}, 'ok', 'pending'],
  ['offline tras sincronizar', {hasDocument:true,syncState:'SYNCED',syncFailure:{message:'Sin conexión de red'}}, 'ok', 'pending'],
  ['error real de logo', {hasDocument:true,syncState:'SYNCED',mediaIssues:[{key:'logo-ENTITY',message:'HTTP_404',area:'Logos'}]}, 'error', 'error'],
  ['SSL no es offline normal', {hasDocument:true,syncFailure:{message:'SSL handshake failed'}}, 'error', 'error'],
  ['incidencia resuelta', {hasDocument:true,syncState:'SYNCED',mediaIssues:[]}, 'ok', 'synced'],
  ['atención de laboratorio', {hasDocument:true,syncState:'SYNCED',labCloudPending:true}, 'attention', 'attention'],
];
let failures = 0;
function check(name, run) { try {run();console.log('PASS '+name);} catch(e) {failures++;console.error('FAIL '+name+': '+e.message);} }
for (const [name,state,level,mode] of cases) check(name,()=>{
  const result=diag.build(state); assert.equal(result.level,level); assert.equal(diag.auraMode(state,result),mode);
});
check('incidencias de medios no duplicadas',()=>{
  const issue={key:'logo-ENTITY',message:'HTTP_404'};
  assert.equal(diag.build({hasDocument:true,mediaIssues:[issue,issue]}).incidents.length,1);
});
const form=read('qml/Mobile/pages/CalicataFormPage.qml');
function qmlFunction(name) {
  const start=form.indexOf('    function '+name+'(');assert(start>=0);
  const end=form.indexOf('\n    }',start);return form.slice(start,end+6);
}
const root={mediaQueueRevision:0,doc:{instanceId:'local'},cloudLogoHistory:{PROJECT:[]},
  logoReadStates:{PROJECT:{state:'ERROR',message:'HTTP_404'}}};
const ctx={root,CalicataCloud:{mediaEntriesFor:()=>[]}};vm.createContext(ctx);
vm.runInContext(qmlFunction('logoSlotSyncState'),ctx);
check('descarga fallida no se presenta como Sin logo',()=>assert.match(ctx.logoSlotSyncState('pro',false),/recuperar|Error|Fallo/i));
root.logoReadStates={PROJECT:{state:'EMPTY'}};
check('ranura vacía confirmada',()=>assert.equal(ctx.logoSlotSyncState('pro',false),'Sin logo'));
root.logoReadStates={PROJECT:{state:'READY'}};
root.cloudLogoHistory.PROJECT=[{media_id:'remote',original_storage_path:'real.png'}];
check('copia local distinta no se anuncia sincronizada',()=>assert.equal(ctx.logoSlotSyncState('pro',true),'Solo local'));
root._relativeToDocsBase=p=>p;
root._logoHistoryKey=t=>t==='mtc'?'logo_mtc_history':'logo_proyecto_history';
root._logoHistoryFrom=(t,images)=>images[root._logoHistoryKey(t)]||[];
root._logoHistoryWith=(t,images,p)=>[{path:p},...root._logoHistoryFrom(t,images)];
root._applyPendingToUI=()=>{};
ctx.doc=root.doc;
let adopted=0;
root.doc.cacheLogoFromCloud=(category,p,id,history)=>{adopted++;root.doc.images={logo_proyecto_path:p,logo_proyecto_cloud_media_id:id,logo_proyecto_cloud_path:p,logo_proyecto_history:history};};
vm.runInContext(qmlFunction('_adoptRemoteLogo'),ctx);
vm.runInContext(qmlFunction('_legacyCloudLogoId'),ctx);
root._legacyCloudLogoId=ctx._legacyCloudLogoId;
check('una selección local no publicada sobrevive al pull',()=>{
  root.doc.images={logo_proyecto_path:'seleccion-local.png'};
  ctx._adoptRemoteLogo('PROJECT','cloud.png');assert.equal(adopted,0);
});
check('vaciar en Web retira sólo el caché confirmado y conserva el historial',()=>{
  root.doc.images={logo_proyecto_path:'cloud.png',logo_proyecto_cloud_path:'cloud.png',logo_proyecto_cloud_media_id:'remote',logo_proyecto_history:[{path:'anterior.png'}]};
  ctx._adoptRemoteLogo('PROJECT','');assert.equal(root.doc.images.logo_proyecto_path,'');assert.equal(root.doc.images.logo_proyecto_history.length,1);
});
check('una operación pendiente impide adoptar otra versión',()=>{
  ctx.CalicataCloud.mediaEntriesFor=()=>[{category_code:'PROJECT',state:'PENDING'}];
  const before=adopted;ctx._adoptRemoteLogo('PROJECT','new.png');assert.equal(adopted,before);
});
check('el caché de una versión antigua también converge sin fingir selección local',()=>{
  ctx.CalicataCloud.mediaEntriesFor=()=>[];
  root.cloudLogoHistory.PROJECT=[{media_id:'12345678-aaaa-bbbb-cccc-dddddddddddd',original_storage_path:'original/image.png'}];
  root.doc.images={logo_proyecto_path:'Recursos/logo_project_12345678.png'};
  ctx._adoptRemoteLogo('PROJECT','current.png');assert.equal(root.doc.images.logo_proyecto_path,'current.png');
});
check('recuperar caché no marca la ficha como edición ni altera sync_state',()=>{
  const source=read('calicatadocument.cpp');const start=source.indexOf('void CalicataDocument::cacheLogoFromCloud');
  const body=source.slice(start,source.indexOf('void CalicataDocument::setPhotoCloudState',start));
  assert(!body.includes('markDirty('));assert(!body.includes('setSyncState('));assert(body.includes('wasDirty')&&body.includes('saveDraft()'));
});
check('una publicación confirmada permite converger el logo que antes era local',()=>{
  vm.runInContext(qmlFunction('_confirmLogoPublication'),ctx);
  root._fileUrlToAbs=p=>p;root.logoAbsUrlFromRel=p=>p;
  root.doc.images={logo_proyecto_path:'seleccion.png'};
  ctx._confirmLogoPublication({category_code:'PROJECT',media_id:'published',original_abs:'seleccion.png'});
  assert.equal(root.doc.images.logo_proyecto_cloud_media_id,'published');
  ctx._adoptRemoteLogo('PROJECT','cloud-confirmed.png');
  assert.equal(root.doc.images.logo_proyecto_path,'cloud-confirmed.png');
});
check('reintentar no borra el fallo hasta una respuesta confirmada',()=>{
  vm.runInContext(qmlFunction('_setLogoReadState'),ctx);
  ctx._setLogoReadState('ENTITY','ERROR','HTTP_404');
  ctx._setLogoReadState('ENTITY','LOADING','');
  assert.equal(root.logoReadStates.ENTITY.message,'HTTP_404');assert.equal(root.logoReadStates.ENTITY.failed,true);
  ctx._setLogoReadState('ENTITY','READY','');assert.equal(root.logoReadStates.ENTITY.failed,false);
});
if(failures) process.exitCode=1;

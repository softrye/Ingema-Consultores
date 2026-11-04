'use strict';
// Exercise the production C++ boolean predicates with Qt value adapters.
// This checks contract behavior without compiling; it is not a native Qt test.
const fs=require('node:fs'),path=require('node:path'),vm=require('node:vm');
const assert=require('node:assert/strict'),test=require('node:test');
const source=fs.readFileSync(path.join(__dirname,'../../calicatacloudservice.cpp'),'utf8');
const fixture=require('./fixtures/smart_document_rpc_dev_20261104.json');
const a=source.indexOf('const QVariantMap smart = firstRow(document);');
const body=source.slice(a,source.indexOf('\n            QVariantMap result;',a));
function uuid(value){const s=String(value??'').replace(/^\{|\}$/g,'').toLowerCase();return /^[\da-f]{8}(?:-[\da-f]{4}){3}-[\da-f]{12}$/.test(s)&&!/^0{8}(?:-0{4}){3}-0{12}$/.test(s)?s:'';}
function text(value){const s=String(value??'');return {isEmpty:()=>!s,valueOf:()=>s,toString:()=>s};}
function issues(row,expectedTarget=row.target_id,expectedProject=fixture.project_id){
 const ctx={QStringLiteral:s=>s,QLatin1String:s=>s,smart:{contains:k=>Object.hasOwn(row,k),value:k=>({isNull:()=>row[k]===null||!Object.hasOwn(row,k)})},
  documentNodeId:text(uuid(row.document_node_id)),spaceId:text(uuid(row.space_id)),parentNodeId:text(uuid(row.parent_node_id)),
  projectId:uuid(row.project_id),targetId:uuid(row.target_id),targetType:String(row.target_type??'').trim().toUpperCase(),
  name:text(String(row.name??'').trim()),nodeVersion:Number(row.node_version)||0,
  lifecycle:String(row.lifecycle??'').trim().toUpperCase(),resultCode:String(row.result_code??'').trim().toUpperCase(),
  ctx:{projectId:expectedProject,remoteId:expectedTarget}};
 const lifecycles=body.match(/const bool validLifecycle = QSet<QString>\{([\s\S]*?)\}\.contains\(lifecycle\);/)[1];
 ctx.validLifecycle=Array.from(lifecycles.matchAll(/QStringLiteral\("([^"]+)"\)/g),m=>m[1]).includes(ctx.lifecycle);
 vm.createContext(ctx);
 const resultExpression=body.match(/const bool validResult = ([\s\S]*?);/)[1];
 ctx.validResult=vm.runInContext(resultExpression,ctx);
 const parentExpression=body.match(/const bool validParentNode = ([\s\S]*?);/);
 ctx.validParentNode=parentExpression?vm.runInContext(parentExpression[1],ctx):!ctx.parentNodeId.isEmpty();
 const checks=Array.from(body.matchAll(/if \(([^]*?)\) invalidFields\.append\(QStringLiteral\("([^"]+)"\)\);/g));
 if(!checks.length){
  // The pre-fix validator's legacy parent condition is enough for the red test.
  assert.match(body,/parentNodeId\.isEmpty\(\)/);return ctx.validParentNode?[]:['parent_node_id'];
 }
 return checks.filter(m=>vm.runInContext(m[1].replaceAll('ctx->','ctx.'),ctx)).map(m=>m[2]);
}
test('real RPC c+00+11 remains valid',()=>assert.deepEqual(issues(fixture.cases[0].rpc_response),[]));
test('real authorized root Smart Document accepts explicit JSON null',()=>assert.deepEqual(issues(fixture.cases[1].rpc_response),[]));
test('missing parent column, empty string and malformed UUID remain invalid',()=>{
 for(const value of [undefined,'','not-a-uuid']){const row={...fixture.cases[0].rpc_response,parent_node_id:value};if(value===undefined)delete row.parent_node_id;assert(issues(row).includes('parent_node_id'));}
});
test('project, target, type and all other guards remain mandatory',()=>{
 const row=fixture.cases[0].rpc_response;
 for(const [field,value] of Object.entries({document_node_id:'',space_id:'',project_id:'',target_id:'',target_type:'RENDITION',name:' ',node_version:0,lifecycle:'PURGED',result_code:'UNKNOWN'}))
  assert(issues({...row,[field]:value},row.target_id).includes(field),field+' must be rejected');
 assert(issues(row,'00000000-0000-4000-8000-000000000001').includes('target_id'));
 assert(issues(row,row.target_id,'00000000-0000-4000-8000-000000000001').includes('project_id'));
});
test('rejection logs field names and response shape without raw data',()=>{
 assert.match(body,/INGE_CALICATA_SMART_DOCUMENT_INVALID/);assert.match(body,/invalidFields\.join/);assert.match(body,/responseShape/);
 const diagnostic=body.slice(body.indexOf('qWarning()'),body.indexOf('fail(',body.indexOf('qWarning()')));
 assert(!/toJson\(|<< smart\b|<< document\b|<< name\b|<< projectId\b|<< targetId\b/.test(diagnostic));
});

const fs=require('node:fs'),vm=require('node:vm'),assert=require('node:assert/strict');
const editor=fs.readFileSync('qml/Mobile/pages/CalicatasEditorPage.qml','utf8');
const cpp=fs.readFileSync('androidcalicataexporter.cpp','utf8');
const queue=fs.readFileSync('src/cpp/renditionexportservice.h','utf8');
const form=fs.readFileSync('qml/Mobile/pages/CalicataFormPage.qml','utf8');
const method=name=>{const m=editor.match(new RegExp('function '+name+'\\([^]*?^    }','m'));assert.ok(m,name);return m[0];};
assert.match(editor,/id: "export\.google"[^]*?command: "calicatas\.exportGoogle"/);
assert.match(editor,/id: "export\.inge"[^]*?command: "calicatas\.exportInGe"/);
assert.ok(!editor.includes('Excel y publicar en el proyecto'),'remove the ambiguous old command');
assert.ok(!editor.includes('text: "Exportar Excel"'),'remove the duplicate primary overflow action');
for(const destination of ['GOOGLE_DRIVE','SUPABASE']) {
  let selected,done=0,phases=[];
  const root={leaving:false,_exportFlowActive:false,exportBusy:false,_exportPreparing:false,_publishingDocId:'',_remoteLoadingDocId:'',
    currentTab:{tid:1},currentIndex:0,currentDoc:{},_docInstanceId:()=> 'doc',_syncDocsList:()=>{},_docAt:()=>null,
    _indexForTid:()=>0,beginOperation:()=> 'op',phaseOperation:(id,phase)=>phases.push(phase),
    _finishExcelExport:()=>done++,endOperation:()=>{throw Error('unexpected export failure');}};
  const formLoader={item:{doc:{},exportExcelFlow:provider=>{selected=provider;return '/private/CT-51+425.xlsx';}}};
  const exportKickoff={restart(){this.task();}};
  const c=vm.createContext({root,formLoader,exportKickoff,console});
  vm.runInContext(method('exportCurrentExcel'),c);c.exportCurrentExcel(destination);
  assert.equal(selected,destination);assert.equal(done,1);assert.equal(root._exportPreparing,false);
}
{
  let chosen=0;
  const root={leaving:false,_exportFlowActive:false,exportBusy:false,_exportPreparing:false,_publishingDocId:'',
    currentTab:{},openAnchoredPopup:()=>chosen++};
  const c=vm.createContext({root,exportPopup:{},console});vm.runInContext(method('exportCurrentExcel'),c);c.exportCurrentExcel();
  assert.equal(chosen,1,'old callers must ask for a destination, never default silently');
}
const start=cpp.indexOf('QString AndroidCalicataExporter::exportStateToXlsx('),end=cpp.indexOf('QString AndroidCalicataExporter::exportGenericWorkbookToXlsx(',start);
const generation=cpp.slice(start,end);
assert.match(generation,/provider != "GOOGLE_DRIVE" && provider != "SUPABASE"/);
assert.ok(generation.includes('workbooks/'),'identical filenames must live in separate private operation directories');
assert.ok(generation.includes('visibleFileName'),'display code and internal hash identities must be separate');
assert.ok(generation.includes('calicataId, provider, true, visibleFileName'),'selected provider and clean name must reach the durable queue');
assert.match(queue,/"fileName",displayFileName\.isEmpty\(\)\?QFileInfo\(logicalPath\)\.fileName\(\):displayFileName/);
assert.ok(queue.includes('intent.value("displayFileName").toString()'),'restart recovery must preserve the clean name');
assert.ok(form.includes('exporter.exportStateToXlsx(st, baseName, provider)'));
assert.ok(queue.includes('rpc/reserve_binary_document_version_v01'),'repeat exports must retain the name and preserve previous versions');
assert.ok(queue.includes('if(checkpoint(current)) reserveWorkbookVersion()'),'the reservation mode must be durable before the RPC');
console.log('PASS hybrid Excel: explicit destinations, preserved providers, code-only names and durable recovery');

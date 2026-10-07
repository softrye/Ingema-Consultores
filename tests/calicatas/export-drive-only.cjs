const fs=require('node:fs'), vm=require('node:vm'), assert=require('node:assert/strict');
const source=fs.readFileSync('qml/Mobile/pages/CalicatasEditorPage.qml','utf8');
const method=name=>{const m=source.match(new RegExp('function '+name+'\\([^]*?^    }','m'));assert.ok(m,name);return m[0];};
function scenario(syncState, online) {
  const doc={header:{projectId:'project',projectName:'Proyecto'},portableState:()=>({})};
  const phases=[]; let finished, published=0, openings=0;
  const root={_docAt:()=>doc,_indexForDocId:()=>0,_exportOperationId:'export',
    phaseOperation:(id,phase)=>phases.push(phase),endOperation:(id,state,result)=>{finished={state,...result};}};
  const exporter={lastExportResult:{syncState,remoteFolderPath:'06_GABINETE/exports'},
    openLastExport:()=>{openings++;return true;},publishCalicata:()=>{published++;return true;}};
  const c=vm.createContext({root,ExcelExporter:exporter,CalicataCloud:{syncDocument:()=>online},console});
  for(const name of ['_excelDrivePath','_finishExcelExport'])vm.runInContext(method(name),c);
  root._excelDrivePath=c._excelDrivePath;
  c._finishExcelExport('/private/export.xlsx','doc');
  assert.equal(openings,0,'exporting must never launch Excel');
  assert.ok(!phases.includes('OPENING'));
  assert.deepEqual(JSON.parse(JSON.stringify(finished.actions)),[{id:'close',label:'Cerrar'}], 'view/download belongs to InGeDrive');
  assert.ok(finished.detail.includes('InGeDrive'));
  assert.ok(finished.detail.includes('06_GABINETE'));
  return {finished,published};
}
assert.equal(scenario('PENDING_SYNC',false).published,1,'offline export stays in the persistent queue');
assert.ok(scenario('SYNCED',true).finished.detail.includes('Sincronizado'));
assert.equal(scenario('ERROR',true).finished.state,'ERROR','failed upload must not be called synced');
const cpp=fs.readFileSync('androidcalicataexporter.cpp','utf8');
const start=cpp.indexOf('QString AndroidCalicataExporter::exportStateToXlsx(');
const end=cpp.indexOf('QString AndroidCalicataExporter::exportGenericWorkbookToXlsx(',start);
assert.ok(!cpp.slice(start,end).includes('copyFileToMediaStoreDownloads('),'private staging must not publish another automatic Downloads copy');
console.log('PASS export: no viewer, no public copy, retained queue, truthful sync state');

const fs = require('node:fs');
const vm = require('node:vm');
const assert = require('node:assert/strict');
const qml = fs.readFileSync('qml/Mobile/pages/CalicatasEditorPage.qml', 'utf8');
const method = name => {
  const m = qml.match(new RegExp('function ' + name + '\\([^]*?^    }', 'm'));
  assert.ok(m, 'Missing Google Drive result handler: ' + name);
  return m[0];
};
// Execute production QML JavaScript: queue/auth/network are external dependencies.
// A premature success message or automatic launch must fail these scenarios.
for (const state of ['PENDING_SYNC', 'UPLOADING', 'ERROR', 'SYNCED']) {
  let finished = null, opened = 0;
  const result = {provider:'GOOGLE_DRIVE', syncState:state, fileName:'CA.xlsx',
    remoteId:state === 'SYNCED' ? 'confirmed-id' : '', error:'Sin permiso',
    webViewLink:'https://drive.google.com/file/d/confirmed-id/view'};
  const root = {_exportOperationId:'export', _exportFlowActive:true,
    phaseOperation:()=>{}, endOperation:(id,status,sheet)=>{finished={status,...sheet};},
    _retryGoogleExcelExport:()=>{}, _googleExportPath:'/private/CA.xlsx'};
  const context = vm.createContext({root, ExcelExporter:{lastExportResult:result,
    openLastExport:()=>{opened++;}}, console});
  vm.runInContext(method('_refreshGoogleExcelExport'), context);
  context._refreshGoogleExcelExport();
  assert.equal(opened, 0, 'Google export must never launch Excel');
  if (state === 'PENDING_SYNC' || state === 'UPLOADING') {
    assert.equal(finished, null, 'Queued/uploading is not cloud success');
    assert.equal(root._exportFlowActive, true);
  } else if (state === 'ERROR') {
    assert.equal(finished.status, 'ERROR');
    assert.ok(finished.actions.some(a=>a.id==='retry'));
    assert.ok(finished.detail.includes('Sin permiso'));
  } else {
    assert.equal(finished.status, 'SUCCESS');
    assert.ok(finished.detail.includes('01_CALICATAS'));
  }
}
// Do not report cloud success if metadata confirmation has no file identity.
{
  let finished;
  const root={_exportFlowActive:true,_exportOperationId:'export',_googleExportPath:'/private/CA.xlsx',phaseOperation:()=>{},
    endOperation:(id,status)=>{finished=status;},_retryGoogleExcelExport:()=>{}};
  const c=vm.createContext({root,ExcelExporter:{lastExportResult:{provider:'GOOGLE_DRIVE',syncState:'SYNCED'}},console});
  vm.runInContext(method('_refreshGoogleExcelExport'),c);c._refreshGoogleExcelExport();
  assert.notEqual(finished,'SUCCESS','No confirmed remote identity means no success');
}
// Execute the real entry point: Google must not publish the XLSX to Supabase.
{
  let refresh=0, published=0;
  const root={_refreshGoogleExcelExport:()=>{refresh++;}};
  const c=vm.createContext({root,ExcelExporter:{lastExportResult:{provider:'GOOGLE_DRIVE'},
    publishCalicata:()=>{published++;}}});
  vm.runInContext(method('_finishExcelExport'),c);c._finishExcelExport('/private/CA.xlsx','doc');
  assert.equal(root._googleExportPath,'/private/CA.xlsx');
  assert.equal(refresh,1);assert.equal(published,0);
}
// Retry reuses the durable operation instead of regenerating the workbook.
{
  let retries=0;
  const root={_exportFlowActive:false,_googleExportPath:'/private/CA.xlsx',beginOperation:()=> 'retry'};
  const c=vm.createContext({root,ExcelExporter:{retryPendingExports:()=>{retries++;}}});
  vm.runInContext(method('_retryGoogleExcelExport'),c);c._retryGoogleExcelExport();c._retryGoogleExcelExport();
  assert.equal(retries,1);assert.equal(root._exportFlowActive,true);
}
// Offline retries release the foreground UI while retaining the pending outbox.
{
  let result;
  const root={_exportFlowActive:true,_googleExportPath:'/private/CA.xlsx',_exportOperationId:'export',
    endOperation:(id,state)=>{result=state;},_retryGoogleExcelExport:()=>{}};
  const c=vm.createContext({root,ExcelExporter:{lastExportResult:{provider:'GOOGLE_DRIVE',
    syncState:'PENDING_SYNC',awaitingRetry:true,error:'Sin conexión'}}});
  vm.runInContext(method('_refreshGoogleExcelExport'),c);c._refreshGoogleExcelExport();
  assert.equal(result,'ERROR');assert.equal(root._exportFlowActive,false);
}
const queue = fs.readFileSync('src/cpp/renditionexportservice.h','utf8');
const transportPath='src/cpp/googledriveexporttransport.cpp';
assert.ok(fs.existsSync(transportPath),'Native Google Drive transport must exist');
const transport=fs.readFileSync(transportPath,'utf8');
const java=fs.readFileSync('android/src/com/ingema/ingeplus/GoogleDriveAuthorization.java','utf8');
assert.ok(queue.includes('GOOGLE_DRIVE'), 'Google operations need a distinct durable destination');
assert.ok(queue.includes('googleFileId'), 'Reserve and persist a remote identity before upload');
assert.ok(transport.includes('md5Checksum') && transport.includes('parents'), 'Verify uploaded binary and folder');
assert.ok(transport.includes('canAddChildren'), 'Check write access before sending XLSX');
assert.ok(transport.includes('1UJnOr5Ef5TYdtP_g0HTRcRGIr0TgfeuX'), 'Use the confirmed actual folder ID');
assert.ok(java.includes('PICKER_OAUTH_TRIGGER') && java.includes('PICKER_ALLOW_FOLDER_SELECTION'));
assert.ok(!java.includes('.addResourceParameter(AuthorizationRequest.ResourceParameter.PICKER_FILE_IDS'),
  'Folder authorization must let the user browse/search when the target is absent from the initial view');
assert.ok(transport.includes("picked.split(',', Qt::SkipEmptyParts) != QStringList{folderId}"),
  'Browsing other folders must not allow changing the fixed export destination');
assert.ok(java.includes('drive.file') && !java.includes('auth/drive"'), 'Do not request all Drive access');
assert.ok(!java.includes('Log.') && !transport.includes('qDebug()'), 'Never log Google credentials');
assert.ok(!java.includes('SharedPreferences'), 'Keep access tokens out of persistent storage');
assert.ok(transport.includes('m_epoch') && queue.includes('m_google.cancel()'), 'Cancel work on InGe account change');
console.log('PASS Google Drive: real UI state handling + native transport integration contracts');

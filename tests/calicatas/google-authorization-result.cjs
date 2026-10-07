const fs=require('node:fs'), vm=require('node:vm'), assert=require('node:assert/strict');
const source=fs.readFileSync('android/src/com/ingema/ingeplus/GoogleDriveAuthorization.java','utf8');
// Run the production callback control flow, adapting only Java declarations.
// Google SDK is a boundary: it returns a result or throws its real status.
const match=source.match(/public static boolean onActivityResult\([^]*?^    }/m);
assert.ok(match);
const callback=match[0]
  .replace(/public static boolean onActivityResult\([^)]*\)/,'function onActivityResult(activity, code, resultCode, data)')
  .replace(/\bString request =/g,'let request =')
  .replace(/request\.isEmpty\(\)/g,'request.length === 0')
  .replace(/catch\s*\(Exception e\)/g,'catch (e)');
function run(resultCode,data,code=29173){
  const calls=[];
  const c=vm.createContext({REQUEST:29173,pending:'operation',cancelled:false,Activity:{RESULT_OK:-1},
    Identity:{getAuthorizationClient:()=>({getAuthorizationResultFromIntent:intent=>{
      calls.push('decode');if(intent.status)throw {status:intent.status};return {token:'in-memory'};
    }})},deliver:(id,result)=>calls.push(['delivered',id,result.token]),
    finish:(id,token,picked,message)=>calls.push(['failed',message]),
    error:(...args)=>'Google status '+args.at(-1).status});
  vm.runInContext(callback,c);
  return {handled:c.onActivityResult({},code,resultCode,data),calls};
}
let result=run(0,{status:10});
assert.deepEqual(result.calls,['decode',['failed','Google status 10']],
  'A canceled Android result with SDK data must expose OAuth failure, not claim user canceled');
result=run(0,{status:16});assert.deepEqual(result.calls,['decode',['failed','Google status 16']]);
result=run(-1,{});assert.deepEqual(result.calls,['decode',['delivered','operation','in-memory']]);
result=run(0,null);assert.equal(result.calls.length,1);assert.ok(result.calls[0][1].includes('sin devolver datos'));
assert.ok(!result.calls[0][1].includes('cancelada'),'No data is not proof the user canceled');
result=run(0,{status:10},123);assert.equal(result.handled,false);assert.deepEqual(result.calls,[]);
assert.ok(source.includes('getApkContentsSigners()') && source.includes('MessageDigest.getInstance("SHA-1")'),
  'OAuth diagnostics must use the installed app certificate, not the PC debug keystore');
const exporter=fs.readFileSync('androidcalicataexporter.cpp','utf8');
const retry=exporter.match(/void AndroidCalicataExporter::retryPendingExports\(\)[^]*?\n}/)[0];
assert.ok(retry.includes('retryDocument(m_exportProject, m_exportLogicalPath,')
    && retry.includes('m_exportResult.value("provider", "SUPABASE").toString()'),
  'Retry must only authorize the workbook the user is retrying');
const queue=fs.readFileSync('src/cpp/renditionexportservice.h','utf8');
const genericRetry=queue.slice(queue.indexOf('    void retry()'),queue.indexOf('    // Aggregate ordering'));
assert.ok(!genericRetry.includes('m_googleInteractive.insert'),
  'Generic/background retries must not open consent for old Google workbooks');
console.log('PASS Google callback: decode errors, null result, success and unrelated request');

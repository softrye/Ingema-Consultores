const fs=require('node:fs'); const vm=require('node:vm'); const assert=require('node:assert/strict');
const qml=fs.readFileSync('qml/Mobile/pages/CalicataFormPage.qml','utf8');
function method(name) { const m=qml.match(new RegExp('function '+name+'\\([^]*?^    }','m')); assert.ok(m,name); return m[0]; }
assert.ok(qml.includes('CoreRemote.interpretCalicata(state)'), 'interpretation must reach the existing global AI');
assert.ok(!qml.includes('readonly property string suggestion: root.autoProfileInterpretation()'), 'a programmed sentence is not AI');
const state={header:{projectId:'project'},cortes:[{de:'0',a:'3',descripcion:'Arena fina'}]};
const root={_loading:false,_documentClosing:false,coreReviewBusy:false,coreInterpretation:'',
  commitPendingField:()=>true,reviewForExport(){},exportState:()=>state};
let calls=0; let reviews=0; let updated=null; let closes=0;
const context=vm.createContext({root,CoreRemote:{online:true,reviewCalicata(){reviews++;return 'review-id';},interpretCalicata:s=>{assert.equal(s,state);calls++;return 'request-id';}},
  aiReviewDialog:{open(){},close(){closes++;}},coreReviewTimeout:{restart(){},stop(){}},String,JSON});
vm.runInContext(method('requestAssistedReview'),context);
assert.equal(context.requestAssistedReview(),false,'the dedicated assistant cannot start a ficha review');
assert.equal(context.requestAssistedReview('review'),false);
assert.equal(calls,0);
assert.equal(reviews,0);
context.requestAssistedReview('interpretation');
assert.equal(calls,1); assert.equal(root.coreSnapshot,JSON.stringify(state));
root.updateProfileSetup=changes=>{updated=changes;};
vm.runInContext(method('acceptCoreInterpretation'),context);
root.acceptCoreInterpretation=()=>context.acceptCoreInterpretation();
root.coreInterpretation='Perfil de arena fina observado.';
assert.equal(context.acceptCoreInterpretation(),true);
assert.equal(updated.interpretation,'Perfil de arena fina observado.');
updated=null; root.coreSnapshot='old-state';
assert.equal(context.acceptCoreInterpretation(),false); assert.equal(updated,null,'stale AI output cannot overwrite the current profile');
console.log('PASS interpretation-only request and stale response blocked');

// Exercise the production completion handler: errors, other requests and stale output never become profile text.
const handler=qml.match(/function onCompleted\(id,result,error\) \{[^]*?^        }/m);
assert.ok(handler);
Object.assign(root,{coreReviewId:'mine',coreSnapshot:JSON.stringify(state),_coreReviewPurpose:'interpretation',
  coreInterpretation:'',reviewSummaryData:{blockerCount:0}});
context.Rules={contextWarnings:()=>[]};
vm.runInContext(handler[0],context);
context.onCompleted('another',{summary:'wrong sheet'},'');
assert.equal(root.coreInterpretation,''); assert.equal(root.coreReviewId,'mine');
const beforeCloses=closes;
updated=null;
context.onCompleted('mine',{summary:'Perfil de arena fina observado.',findings:[{message:'Do not copy findings into interpretation'}],preliminary:[]},'');
assert.equal(root.coreInterpretation,'Perfil de arena fina observado.');
assert.ok(updated,'completion must update the interpretation field');
assert.equal(updated.interpretation,'Perfil de arena fina observado.','completion must fill the field without another click');
assert.equal(closes,beforeCloses+1,'successful generation closes its activity dialog');
assert.equal(root.coreFindings.length,0,'generation must not expose review action buttons');
assert.equal(root.coreFeedback,'');
updated=null;
root.coreInterpretation=''; root.coreReviewId='next'; root.coreSnapshot='changed';
context.onCompleted('next',{summary:'stale'},'');
assert.equal(root.coreInterpretation,'');
root.coreReviewId='error'; root.coreSnapshot=JSON.stringify(state);
context.onCompleted('error',{},'ConnectError');
assert.equal(root.coreInterpretation,''); assert.ok(root.coreFeedback.includes('ConnectError'));
assert.equal(updated,null,'failed and stale results preserve the field');
for(const summary of ['', 'x'.repeat(1001)]) {
  root.coreReviewId='invalid'; root.coreSnapshot=JSON.stringify(state);
  context.onCompleted('invalid',{summary},'');
  assert.equal(updated,null,'invalid summary must not overwrite the field');
}
root.coreReviewId='limit'; root.coreSnapshot=JSON.stringify(state);
context.onCompleted('limit',{summary:'x'.repeat(1000)},'');
assert.equal(updated.interpretation.length,1000);
updated=null;
context.onCompleted('',{summary:'late output'},'');
assert.equal(updated,null,'an empty/cancelled request ID cannot apply a result');
console.log('PASS automatic fill, exact summary, 1000-character boundary, correlation, errors and stale responses');

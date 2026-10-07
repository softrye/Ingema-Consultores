const fs = require('node:fs');
const vm = require('node:vm');
const assert = require('node:assert/strict');
const Rules = vm.createContext({});
vm.runInContext(fs.readFileSync('qml/Mobile/lib/CalicataRules.js','utf8').replace(/^\.pragma library\s*/,''), Rules);
assert.equal(typeof Rules.sampleIntervalValue, 'function', 'sample bounds must inherit the stratum');
const row = {de:'1.60',a:'3.00',muestra_desde:'',muestra_hasta:''};
assert.equal(Rules.sampleIntervalValue(row,'muestra_desde'),'1.60');
assert.equal(Rules.sampleIntervalValue(row,'muestra_hasta'),'3.00');
assert.equal(Rules.sampleIntervalValue({...row,de:'0.00'},'muestra_desde'),'0.00');
assert.equal(Rules.sampleIntervalValue({...row,muestra_desde:'1.85'},'muestra_desde'),'1.85');
const read = r => JSON.parse(JSON.stringify(r));
assert.deepEqual(read(Rules.inheritSampleInterval({...row,a:'3.50',tipo_muestra:'MA'},'1.60','3.00')),
  {muestra_desde:'1.60',muestra_hasta:'3.50'});
assert.deepEqual(read(Rules.inheritSampleInterval({...row,de:'1.80',muestra_desde:'1.60',muestra_hasta:'3.00'},'1.60','3.00')),
  {muestra_desde:'1.80',muestra_hasta:'3.00'});
assert.deepEqual(read(Rules.inheritSampleInterval({...row,muestra_desde:'1.85',muestra_hasta:'2.30',a:'3.50'},'1.60','3.00')),
  {muestra_desde:'1.85',muestra_hasta:'2.30'});
assert.deepEqual(read(Rules.inheritSampleInterval(row,'1.60','3.00')), {}, 'a displayed default must not create an optional sample');
const qml=fs.readFileSync('qml/Mobile/pages/CalicataFormPage.qml','utf8');
function method(name) { const m=qml.match(new RegExp('function '+name+'\\([^]*?^    }','m')); assert.ok(m,name); return m[0]; }
const model=vm.createContext({Rules,root:{},JSON,Object,String,isFinite});
vm.runInContext(method('corteToPlainObject'),model);
assert.equal(model.corteToPlainObject({...row,tipo_muestra:'MA'}).muestra_hasta,'3.00', 'saved samples include inherited bounds');
assert.equal(model.corteToPlainObject(row).muestra_hasta,'', 'no phantom sample on an unselected field');
const rows=[{...row,tipo_muestra:'MA'}];
const cortesModel={get:i=>rows[i],setProperty:(i,k,v)=>{rows[i][k]=v;}};
const commit=vm.createContext({Rules,cortesModel,root:{_markDirty(){}},showInfo(){throw Error('valid default rejected');}});
vm.runInContext(method('commitSampleInterval'),commit);
assert.equal(commit.commitSampleInterval(0,'muestra_desde','2.00'),true, 'manual lower bound validates against inherited upper bound');
assert.equal(rows[0].muestra_hasta,'3.00');
console.log('PASS sample default, persistence, changed strata, manual subinterval, no phantom sample');

// Changing a stratum boundary also changes the next stratum's inherited sample.
const chain=[{de:'0.00',a:'1.60',_extraJson:'{}'},
  {de:'1.60',a:'3.00',tipo_muestra:'MA',muestra_desde:'1.60',muestra_hasta:'3.00',_extraJson:'{}'}];
const chainModel={get count(){return chain.length;},get:i=>chain[i],setProperty:(i,k,v)=>{chain[i][k]=v;}};
const chainRoot={_markDirty(){}};
const chainContext=vm.createContext({Rules,root:chainRoot,cortesModel:chainModel,allowedDepthM:3,
  _updatingIntervals:false,_loading:false,showInfo(){throw Error('valid boundary rejected');},_markDirty(){}});
for(const name of ['_inheritSampleInterval','commitBoundary','renumerarCortesYIntervalos','_fmtDepth','_parseDepthText'])
  vm.runInContext(method(name),chainContext);
chainRoot._inheritSampleInterval=chainContext._inheritSampleInterval;
assert.equal(chainContext.commitBoundary(0,'2.00'),true);
assert.equal(chain[1].de,'2.00'); assert.equal(chain[1].muestra_desde,'2.00');
assert.equal(chain[1].muestra_hasta,'3.00');
chain[1].muestra_desde='2.20'; chain[1].muestra_hasta='2.80';
assert.equal(chainContext.commitBoundary(0,'2.10'),true);
assert.equal(chain[1].muestra_desde,'2.20'); assert.equal(chain[1].muestra_hasta,'2.80');
console.log('PASS actual boundary event updates the following sample and preserves a manual subinterval');

const fs = require('node:fs');
const vm = require('node:vm');
const assert = require('node:assert/strict');
const source = fs.readFileSync('qml/Mobile/lib/CalicataRules.js','utf8').replace(/^\.pragma library\s*/, '');
const rules = vm.createContext({}); vm.runInContext(source,rules);
let count=0;
function test(name,fn){ fn(); count++; console.log(name+' OK'); }
// Motor único = port exacto de Web soilClassification.ts (paridad dorada en
// tests/calicatas/web_lab_parity_static.cjs).
const review = (row, extra) => rules.reviewLaboratorySample(rules.labForm(row, extra || {}));
const fine = { g2: '95', g04: '90', g008: '80' };
test('CALICATA_DETERMINISTIC_SUCS',()=>{
  assert.deepEqual([...review({...fine,wl:'40',lp:'20'}).sucs.candidates],['CL']);
  assert.deepEqual([...review({...fine,wl:'60',lp:'30'}).sucs.candidates],['CH']);
});
test('CALICATA_BOUNDARIES',()=>{
  assert.deepEqual([...review({...fine,g008:'50',wl:'25',lp:'20'}).sucs.candidates],['CL','ML']);
  assert.equal(review({...fine,g008:'50',wl:'25',lp:'20'}).sucs.conclusive,false);
  assert.ok(review({...fine,wl:'20',lp:'30'}).observations.some(o=>o.id==='atterberg-order'));
});
test('CALICATA_NO_SIEVE_SUBSTITUTION',()=>{
  assert.equal(review({wl:'40',lp:'20'}).sucs,null);
  assert.equal(review({...fine,g008:''}).sucs,null);
});
test('CALICATA_AASHTO',()=>{
  assert.equal(review({...fine,wl:'60',lp:'30'}).aashto.code,'A-7-5');
  assert.equal(review({...fine,wl:'60',lp:'20'}).aashto.code,'A-7-6');
});
test('CALICATA_PATTERN_DERIVED',()=>assert.equal(JSON.stringify(rules.patternCodes('SW-SM')),'["SW","SM"]'));
test('CALICATA_CONTEXT_WARNINGS',()=>assert.ok(rules.contextWarnings([{de:0,a:1,descripcion:'Arena limosa húmeda'},{de:2,a:3,descripcion:'Arcilla'}]).length>=2));
test('CALICATA_DECIMAL_AND_PI',()=>{
  assert.ok(Number.isNaN(rules.parseDecimalSafe('3abc')));
  assert.equal(rules.plasticityIndex('40','20'),'20.00');
});
console.log(JSON.stringify({tests:count,status:'OK',compilation:false}));

const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const path = require('node:path');
const rules = {};
vm.createContext(rules);
vm.runInContext(fs.readFileSync(path.join(__dirname, '../../qml/Mobile/lib/CalicataRules.js'), 'utf8').replace(/^\.pragma library\s*/, ''), rules);
// Moving an entity must carry its laboratory/UUID and preserve thickness.
const input = [{id:'A', remote_stratum_id:'uuid-a', de:'0.00', a:'0.40', lab:{stratum_id:'uuid-a'}},
 {id:'B', remote_stratum_id:'uuid-b', de:'0.40', a:'1.00', lab:{stratum_id:'uuid-b'}}];
const moved = rules.moveStratumEntities(input, 0, 1);
assert.deepEqual(JSON.parse(JSON.stringify(moved.map(r => [r.id,r.de,r.a,r.lab.stratum_id]))),
 [['B','0.00','0.60','uuid-b'],['A','0.60','1.00','uuid-a']]);
assert.equal(input[0].a,'0.40');
assert.equal(rules.boundaryError([{a:'4.00'}],0,'4.00'), '');
assert.notEqual(rules.boundaryError([{a:'4.00'}],0,'4.03'), '');
assert.equal(rules.strataDerived([{a:'0.40',humedad:0},{a:'4.00',humedad:3}]).groundwaterDepth, '0.40');
assert.equal(rules.strataDerived([{a:'0.40'},{a:'4.00'}]).depth,4);
assert.equal(rules.moveStratumEntities([{id:'A',a:''},{id:'B',a:'1'}],0,1),null);
console.log('P3 pure strata checks passed');

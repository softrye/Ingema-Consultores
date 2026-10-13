const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const path = require('node:path');
const base = path.resolve(__dirname, '../..');
const read = name => fs.readFileSync(path.join(base, name), 'utf8');
const form = read('qml/Mobile/pages/CalicataFormPage.qml');
const graph = read('qml/Mobile/pages/CalicataProfile.qml');
const rules = vm.createContext({});
vm.runInContext(read('qml/Mobile/lib/CalicataRules.js').replace(/^\.pragma library\s*/, ''), rules);
function extract(source, name) {
    const start = source.indexOf('function ' + name + '(');
    assert.ok(start >= 0, name);
    let end = source.indexOf('{', start) + 1, braces = 1;
    while (braces && end < source.length) {
        if (source[end] === '{') braces++;
        if (source[end] === '}') braces--;
        end++;
    }
    return source.slice(start, end);
}
const rows = [{de:'0.00', a:'1.50', muestra_desde:'0.20', muestra_hasta:'0.60', _extraJson:'{}'}];
const model = {get count() {return rows.length}, get(i) {return rows[i]},
    append(row) {rows.push(row)}, insert(i,row) {rows.splice(i,0,row)},
    setProperty(i,key,value) {rows[i][key]=value}};
const root = {_newLabUuid() {return 'test-uuid'}, _markDirty() {}, totalDepthM:1.5};
const c = vm.createContext({root, Rules:rules, cortesModel:model, _updatingIntervals:false,
    _loading:false, commitPendingField() {return true}, showInfo() {},
    selectStratum() {}, _markDirty() {}});
for (const name of ['insertStratumBelow','addCorte','renumerarCortesYIntervalos','_fmtDepth','_parseDepthText','_defaultCorte','_inheritSampleInterval'])
    vm.runInContext(extract(form,name),c);
root._inheritSampleInterval = c._inheritSampleInterval;
const before = JSON.stringify(rows[0]);
c.insertStratumBelow(0);
assert.equal(JSON.stringify(rows[0]),before,'Insertar must preserve the completed layer and its sample');
assert.equal(rows[1].de,'1.50');
assert.equal(rows[1].a,'','New layer is a draft, not a zero-thickness interval');
const count = rows.length;
c.insertStratumBelow(0);
assert.equal(rows.length,count,'Must not silently split an interior layer');
rows[1].a='3.05';
c.renumerarCortesYIntervalos(true);
assert.equal(root.totalDepthM,3.05,'Valid boundary must update total depth');
assert.equal(rules.boundaryError(rows,1,'3.05'), '');
assert.notEqual(rules.boundaryError(rows,1,'3.03'),'','Preserve the current synchronization precision contract');
rows[1].a='9.00';
c.renumerarCortesYIntervalos(true);
assert.equal(root.totalDepthM,9);
assert.equal(rows[0].a,'1.50');
console.log('PASS append draft, preserve data, compatible intervals, 9 m total');

// Evaluate the actual graph bindings and transformation; one axis uses total depth.
function binding(name, scope) {
    const match = graph.match(new RegExp('readonly property (?:real|int) '+name+': ([^\\r\\n]+)'));
    assert.ok(match,name);
    return vm.runInNewContext(match[1],scope);
}
assert.equal(binding('axisDepth',{totalDepth:9}),9);
assert.equal(binding('axisDepth',{totalDepth:10000}),10000);
const profile = {topPad:10,plotHeight:300,axisDepth:60};
const g = vm.createContext({profile,topPad:10,plotHeight:300,axisDepth:60});
vm.runInContext(extract(graph,'depthY'),g);
assert.equal(g.depthY(30)-g.depthY(0),150);
assert.equal(g.depthY(1.5)-g.depthY(0),7.5);
assert.equal(g.depthY(60),310,'Entered depth remains the bottom boundary');
assert.equal(binding('tickStep',{axisDepth:60}),10);
console.log('PASS single proportional axis and bounded axis marks');

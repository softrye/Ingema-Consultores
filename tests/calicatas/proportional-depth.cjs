// Run: node tests/calicatas/proportional-depth.cjs
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const path = require('node:path');
const repo = path.resolve(__dirname, '../..');
const graph = fs.readFileSync(path.join(repo, 'qml/Mobile/pages/CalicataProfile.qml'), 'utf8');
const form = fs.readFileSync(path.join(repo, 'qml/Mobile/pages/CalicataFormPage.qml'), 'utf8');
const rules = vm.createContext({});
vm.runInContext(fs.readFileSync(path.join(repo, 'qml/Mobile/lib/CalicataRules.js'), 'utf8').replace(/^\.pragma library\s*/, ''), rules);
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
function binding(source, name, scope) {
    const match = source.match(new RegExp('readonly property (?:real|int) ' + name + ': ([^\\r\\n]+)'));
    assert.ok(match, name);
    return vm.runInNewContext(match[1], scope);
}
for (const [totalDepth, at, want] of [[3, 1.5, 150], [60, 30, 150], [100, 1.6, 4.8], [1000, 3, 0.9], [1000000, 3, 0.0009]]) {
    const axisDepth = binding(graph, 'axisDepth', {totalDepth});
    const scope = vm.createContext({topPad: 10, plotHeight: 300, axisDepth, pageStartM: 0});
    vm.runInContext(extract(graph, 'depthY'), scope);
    assert.ok(Math.abs(scope.depthY(at) - 10 - want) < 1e-9, `Position ${at} / ${totalDepth}`);
    assert.equal(scope.depthY(totalDepth), 310, 'Entered depth always at the bottom');
}
assert.equal(rules.profileDepth(60, 30), 60, 'Partial description must not shorten the axis');
assert.equal(rules.profileDepth(60, 75), 75, 'Web totalDepthM = max(declared, last stratum): no cap');
assert.equal(rules.profileDepth(0, 9), 9, 'Legacy unspecified depth follows existing strata');
assert.equal(rules.boundaryError([{a:'60'}], 0, '60', 60), '');
assert.equal(rules.boundaryError([{a:'60'}], 0, '60.05', Infinity), '', 'Hasta may exceed the entered (declared) depth');
assert.equal(rules.boundaryError([{a:'1000000'}], 0, '1000000', Infinity), '', 'No arbitrary global depth cap');
assert.equal(binding(form, 'allowedDepthM', {root:{requestedDepthM:60, depthMaxM:Infinity}}), Infinity, 'Declared depth is not a cap');
assert.equal(binding(form, 'allowedDepthM', {root:{requestedDepthM:0, depthMaxM:Infinity}}), Infinity);
const issues = rules.validateDocument({header:{requested_depth_m:60, final_depth_m:60.05}, cortes:[{de:'0',a:'60.05'}]});
assert.ok(!issues.some(i => i.section === 4 && i.stratum === 0 && /profundidad total/i.test(i.message)), 'Layers below the declared depth are valid (Web)');
const rows = [{de:'0.00', a:'3.00', _extraJson:'{}'}];
const root = {requestedDepthM:60, allowedDepthM:Infinity, totalDepthM:3, _markDirty(){}};
const model = {get count(){return rows.length}, get(i){return rows[i]},
    setProperty(i,key,value){rows[i][key]=value}, append(row){rows.push(row)}};
const context = vm.createContext({root, Rules:rules, cortesModel:model, allowedDepthM:Infinity,
    _loading:false, _updatingIntervals:false, showInfo(){}, _markDirty(){}});
for (const name of ['commitBoundary','renumerarCortesYIntervalos','_parseDepthText','_fmtDepth','addCorte','_inheritSampleInterval'])
    vm.runInContext(extract(form,name),context);
root._inheritSampleInterval = context._inheritSampleInterval;
assert.equal(context.commitBoundary(0,'60.05'),true,'No depth cap: Hasta may pass the declared depth');
assert.equal(root.totalDepthM,60.05);
console.log('PASS proportional positions, partial profile, legacy depth and uncapped boundary');

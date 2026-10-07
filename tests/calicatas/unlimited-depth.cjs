// Run: node tests/calicatas/unlimited-depth.cjs
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');

const repo = path.resolve(__dirname, '../..');
const form = fs.readFileSync(path.join(repo, 'qml/Mobile/pages/CalicataFormPage.qml'), 'utf8');
const rules = vm.createContext({});
vm.runInContext(fs.readFileSync(path.join(repo, 'qml/Mobile/lib/CalicataRules.js'), 'utf8')
    .replace(/^\.pragma library\s*/, ''), rules);

function functionSource(name) {
    const start = form.indexOf('function ' + name + '(');
    assert.ok(start >= 0, 'Missing function ' + name);
    const open = form.indexOf('{', start);
    let braces = 1, end = open + 1;
    while (braces && end < form.length) {
        if (form[end] === '{') braces++;
        if (form[end] === '}') braces--;
        end++;
    }
    assert.equal(braces, 0);
    return form.slice(start, end);
}

const root = {
    totalDepthM: 3,
    requestedDepthM: 0,
    derivedGroundwaterText: '',
    groundwaterCustom: false,
    _loading: false,
    _pendingCommitFields: [],
    _flushCortesRevision() {},
    _markDirty() {},
    setDirty() {},
    showInfo() {}
};
const context = vm.createContext({ root, totalDepthM: root.totalDepthM, Rules: rules, txtWaterTableDepth: {text: ''} });
for (const name of ['depthMaxM', 'allowedDepthM']) {
    const expression = form.match(new RegExp('readonly property real ' + name + ': ([^\\r\\n]+)'))[1];
    root[name] = vm.runInContext(expression, context);
}
for (const name of ['commitProfileDepth', 'commitProfileGroundwater', 'commitPending'])
    vm.runInContext(functionSource(name), context);

// Total depth and the actual Hasta field must accept jumps above both old caps.
for (const depth of ['20', '500', '10000', '20,50']) {
    assert.equal(context.commitProfileDepth(depth), true, 'Total depth must accept ' + depth);
    const field = {
        editPending: true, text: depth, numericKind: rules.DEPTH_METERS,
        allowNP: false, minimumValue: 0, maximumValue: root.allowedDepthM,
        placeholderText: 'Hasta (m)', validationError: '',
        forceActiveFocus() {}, onCommit(value) {
            return !rules.boundaryError([{de: '0.00', a: '3.00'}], 0, value, root.allowedDepthM);
        }
    };
    context.tf = field;
    Object.assign(context, field);
    assert.equal(context.commitPending(), true, 'Hasta field must accept ' + depth);
    assert.equal(context.validationError, '');
}
assert.equal(context.commitProfileGroundwater('20'), true);
assert.equal(context.txtWaterTableDepth.text, '20');

// Removing a cap does not allow invalid numbers or inconsistent intervals.
for (const invalid of ['-1', 'Infinity', 'NaN', 'texto']) {
    assert.equal(context.commitProfileDepth(invalid), false);
    assert.equal(context.commitProfileGroundwater(invalid), false);
}
assert.equal(context.commitProfileDepth('2'), false, 'Cannot truncate existing strata');
assert.equal(context.commitProfileDepth(''), true, 'Optional objective may stay empty');
assert.notEqual(rules.boundaryError([{a: '20'}], 0, '20.03', root.allowedDepthM), '');
assert.notEqual(rules.boundaryError([{a: '20'}, {a: '30'}], 0, '30', root.allowedDepthM), '');
assert.equal(rules.validateDecimalRange('20.50', 0, 20), false, 'Samples stay inside their layer');
console.log('PASS unlimited depth: total, Hasta, groundwater, numeric and interval validation');

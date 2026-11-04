// Production policy, deterministic time: no five-minute sleeps in host tests.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const path = require('node:path');
const source = path.resolve(__dirname, '../../qml/Mobile/halloween/HalloweenLogic.js');
assert.ok(fs.existsSync(source), 'Halloween production policy must exist');
const p = vm.createContext({});
vm.runInContext(fs.readFileSync(source, 'utf8').replace(/^\.pragma library\s*/, ''), p);
for (const day of [14, 15, 31])
    assert.equal(p.resolveSkin('auto', new Date(2026, 9, day)), day === 14 ? 'none' : 'halloween');
assert.equal(p.resolveSkin('auto', new Date(2026, 10, 1)), 'none');
for (const skin of ['none', 'ingema', 'galaxias', 'halloween'])
    assert.equal(p.resolveSkin(skin, new Date(2026, 9, 30)), skin, 'manual choice wins');
let s = { activeMs: 0, remainingMs: 0, serial: 0 };
s = p.stepClock(s, 299999, true, true, true);
assert.equal(s.serial, 0);
s = p.stepClock(s, 600000, false, true, true);
assert.equal(s.activeMs, 299999, 'background never counts');
s = p.stepClock(s, 1, true, false, true);
assert.equal(s.serial, 0, 'due scare waits for IME, modal, sync or thermal to clear');
s = p.stepClock(s, 250, true, true, true);
assert.equal(s.serial, 1);
assert.equal(s.remainingMs, 1800);
s = p.stepClock(s, 50, true, false, true);
assert.equal(s.remainingMs, 0, 'a new blocker immediately dismisses the scare');
s = p.stepClock(s, 300000, true, true, true);
assert.equal(s.serial, 2, 'two scares over ten active minutes');
s = p.stepClock(s, 300000, true, true, false);
assert.equal(s.serial, 2, 'opt-out suppresses scares');
assert.equal(s.activeMs, 0, 'opt-out resets the interval');
assert.equal(p.motionPermitted(true, true, false, 0), true);
assert.equal(p.motionPermitted(false, true, false, 0), false);
assert.equal(p.motionPermitted(true, false, false, 0), false);
assert.equal(p.motionPermitted(true, true, true, 0), false);
assert.equal(p.motionPermitted(true, true, false, 2), false);
console.log('PASS Halloween: calendar, manual priority, active clock, deferred scares, opt-out, thermal/motion');

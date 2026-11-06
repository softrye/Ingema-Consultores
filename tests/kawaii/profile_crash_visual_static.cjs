const fs = require('node:fs');
const path = require('node:path');
const assert = require('node:assert/strict');
const root = path.resolve(__dirname, '../..');
const read = (rel) => fs.readFileSync(path.join(root, rel), 'utf8');

const crash = read('qml/Mobile/kawaii/KawaiiProfileCrash.qml');
const profile = read('qml/Mobile/pages/CalicataProfile.qml');
const qrc = read('resources_mobile_kawaii.qrc');

assert.match(crash, /enabled:\s*false/);
assert.match(crash, /clip:\s*true/);
assert.match(crash, /readonly property real targetWidth:\s*Math\.min\(240 \* crash\.uiScale/);
assert.ok(crash.includes('crash.width * 0.44'));
assert.ok(crash.includes('crash.columnX + crash.columnWidth * 0.15'));
assert.ok(crash.includes('crash.topPad + crash.plotHeight * 0.04'));
assert.ok(crash.includes('onLastInputMsChanged: resetIdle()'));
assert.ok(crash.includes('eventActive = false'));
assert.ok(crash.includes('readonly property bool damaged: eventActive'));
assert.ok(profile.includes('uiScale: profile.scaleFactor'));
assert.ok(qrc.includes('alias="pompompurin-calicata-crash-10s.gif"'));
assert.ok(crash.includes('qrc:/images/kawaii/pompompurin-calicata-crash-10s.gif'));
assert.ok(!crash.includes('crash.width * 0.96'), 'must not cover full technical chart');
console.log('PASS: Kawaii crash overlay bounded, read-only, non-interactive, idle-cancelled and correctly sourced');

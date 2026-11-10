// Regression: the five graphical fidelity modes must not gate Kawaii events.
// User accessibility and runtime protections remain authoritative.
const fs = require('node:fs');
const path = require('node:path');
const assert = require('node:assert/strict');
const vm = require('node:vm');
const root = path.resolve(__dirname, '../..');
const read = rel => fs.readFileSync(path.join(root, rel), 'utf8').replace(/\r\n/g, '\n');

const settings = read('qml/Mobile/settings/SettingsApp.qml');
const home = read('qml/Mobile/HomeScreen.qml');
const season = read('qml/Mobile/halloween/HalloweenController.qml');
const calicata = read('qml/Mobile/pages/CalicataFormPage.qml');
const crash = read('qml/Mobile/kawaii/KawaiiProfileCrash.qml');
const cinna = read('qml/Mobile/kawaii/KawaiiCinnamorollVisit.qml');
const dock = read('qml/Mobile/kawaii/KawaiiDockDecoration.qml');
const tierNames = ['AUTO', 'LOW', 'HIGH', 'VERY_HIGH', 'EXTREME'];
for (const tier of tierNames)
    assert.ok(settings.includes('k: "' + tier + '"'), 'fidelity tier absent: ' + tier);

assert.match(home, /allowed: home\.appSkin === "ingenieros" && home\.kawaiiAppForeground/);
assert.match(home, /enabled: halloweenController\.motionActive\s+\|\| \(home\.appSkin === "ingenieros" && home\.kawaiiAppForeground\)/);
assert.match(home, /parent: Controls\.Overlay\.overlay \? Controls\.Overlay\.overlay : home/);
assert.doesNotMatch(home.slice(home.indexOf('Kawaii.KawaiiCinnamorollVisit {'),
                               home.indexOf('Halloween.HalloweenScare {')), /extremeMotion|advancedMotion/);
assert.match(season, /readonly property bool kawaiiGuestVisible:/);
assert.match(season, /&& motionActive && kawaiiClock\.remainingMs>0/);
assert.doesNotMatch(season, /kawaiiEnabled && foreground && motionActive && flow\.extremeMotion/);
assert.match(season, /kawaiiEnabled && safeSurface && !flow\.powerSaveMode/);
assert.match(season, /season\.flow\.advancedMotion \? 16 : 50/);
assert.match(season, /flow\.motionAllowed, reducedMotion, flow\.thermalStatus/);
assert.match(season, /safeSurface && flow\.thermalStatus < 2/);

assert.match(calicata, /enabled: root\.flow && root\.flow\.appSkin === "ingenieros"\s+&& root\.flow\.motionAllowed && !root\.flow\.powerSaveMode/);
assert.match(calicata, /&& root\.flow\.motionAllowed\s+&& !root\.flow\.powerSaveMode && !root\.flow\.bareUi/);
assert.doesNotMatch(calicata.slice(calicata.indexOf('kawaiiCrashAllowed:'),
                                   calicata.indexOf('onHeld: function(index)',calicata.indexOf('kawaiiCrashAllowed:'))), /extremeMotion|advancedMotion/);
assert.match(crash, /onLastInputMsChanged: resetIdle\(\)/);
assert.match(crash, /enabled: false/);
assert.match(cinna, /idleDelayMs: 20000/);
assert.match(cinna, /property bool playedThisIdle: false/);
assert.doesNotMatch(cinna, /repeatDelayMs/);
assert.match(cinna, /AudioOutput\s*\{/);
assert.match(cinna, /onLastInteractionAtChanged:\s*\{/);
assert.match(cinna, /playedThisIdle = false/);
assert.match(dock, /decor\.controller\.kawaiiGuestVisible/);

// The scheduler itself is independent of all five graphics quality tiers.
const context = vm.createContext({});
vm.runInContext(read('qml/Mobile/kawaii/KawaiiLogic.js').replace(/^\s*\.pragma.*$/mg, ''), context);
vm.runInContext(read('qml/Mobile/halloween/HalloweenLogic.js').replace(/^\s*\.pragma.*$/mg, ''), context);
for (const tier of tierNames) {
    const begin = {elapsedMs: 0, remainingMs: 0, serial: 0};
    const started = context.stepGuest(begin, 25000, true, true);
    assert.equal(started.serial, 1, tier + ' should schedule Dock guest');
    assert.equal(started.remainingMs, 12000, tier + ' should preserve 12s Dock GIF');
    assert.equal(context.motionPermitted(true, true, false, 0), true, tier + ' should animate');
    assert.equal(context.motionPermitted(true, true, true, 0), false, 'respect reduced motion');
    assert.equal(context.motionPermitted(true, true, false, 2), false, 'respect thermal safety');
    assert.equal(context.stepGuest(started, 80, false, true).remainingMs, 0, 'stop on disallow');
}
console.log('PASS: Kawaii animations available across AUTO/LOW/HIGH/VERY_HIGH/EXTREME; safety and 20s cooldown intact');

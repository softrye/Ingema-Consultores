// Behavior-level test of the real QML scheduler methods with a deterministic clock.
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const assert = require('node:assert/strict');
const qml = fs.readFileSync(path.resolve(__dirname,
  '../../qml/Mobile/kawaii/KawaiiCinnamorollVisit.qml'), 'utf8');

function qmlFunction(name) {
  const start = qml.indexOf('    function ' + name + '(');
  assert.ok(start >= 0, 'missing ' + name);
  const brace = qml.indexOf('{', start);
  let depth = 0;
  for (let i = brace; i < qml.length; i++) {
    if (qml[i] === '{') depth++;
    else if (qml[i] === '}') {
      depth--;
      if (depth === 0) return qml.slice(start, i + 1);
    }
  }
  throw new Error('Unclosed function ' + name);
}
let now = 0, playCount = 0, stopCount = 0;
const s = {
  Date: { now: () => now },
  console: { info() {} },
  movie: {
    stop() { stopCount++; },
    play() { playCount++; },
    position: 0
  },
  allowed: true,
  showing: false,
  playbackFailed: false,
  playedThisIdle: false,
  lastInteractionAt: 0,
  idleDelayMs: 20000,
  nextEligibleMs: 20000
};
vm.createContext(s);
for (const n of ['endVisit', 'cancelVisit', 'tryStart'])
  vm.runInContext(qmlFunction(n), s);

function tick(t) { now = t; s.tryStart(); }
tick(19999);
assert.equal(playCount, 0, 'not before 20s AFK');
tick(20000);
assert.equal(playCount, 1, 'first 20s idle visit starts');
assert.equal(s.showing, true);
assert.equal(s.playedThisIdle, true);
now = 30000;
s.endVisit();
assert.equal(s.showing, false);

for (const t of [30001, 40000, 60000, 120000, 180000, 600000]) tick(t);
assert.equal(playCount, 1, 'no repeat during the same idle session, even after 10 minutes');

// Changing safe-surface or allowed can stop playback but cannot re-arm.
s.allowed = false;
tick(610000);
s.allowed = true;
tick(640000);
assert.equal(playCount, 1, 'no repeat after returning to safe surface');

now = 650000;
// This is the handler equivalent of onLastInteractionAtChanged, actual user input.
s.lastInteractionAt = now;
s.playedThisIdle = false;
s.cancelVisit();
tick(669999);
assert.equal(playCount, 1, 'wait 20s after the new interaction');
tick(670000);
assert.equal(playCount, 2, 'one new visit after a real new idle session');
now = 680000;
s.endVisit();
tick(700000);
tick(900000);
assert.equal(playCount, 2, 'second idle session also permits one visit only');

// No graphics-tier override, no conversions and user accessibility still gate it.
assert.match(qml, /source: visitor\.mediaEnabled \? "qrc:\/images\/kawaii\/cinnamoroll-knock-clean-10s\.mp4"/);
assert.match(qml, /required property bool mediaEnabled/);
assert.match(qml, /AudioOutput\s*\{/);
assert.match(qml, /onLastInteractionAtChanged:\s*\{\s*\/\/[^\n]*\n\s*playedThisIdle = false/);
assert.match(qml, /running: visitor\.allowed && !visitor\.showing && !visitor\.playbackFailed/);
assert.ok(qml.includes('!visitor.playedThisIdle'), 'timer must not keep polling after the one shot');
assert.doesNotMatch(qml, /repeatDelayMs|lastStartedMs/);
console.log('PASS: Cinnamoroll once per 20s AFK session; no 20s replay loop, no media changes');

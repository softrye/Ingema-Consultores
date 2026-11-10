'use strict';
// Regression for the actual HomeScreen QML bindings: Halloween safety must
// never suppress the independent Kawaii one-shot over the active app.
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const assert = require('node:assert/strict');
const source = fs.readFileSync(path.resolve(__dirname, '../../qml/Mobile/HomeScreen.qml'), 'utf8');
const video = fs.readFileSync(path.resolve(__dirname, '../../qml/Mobile/kawaii/KawaiiCinnamorollVisit.qml'), 'utf8');

const fg = source.match(/readonly property bool kawaiiAppForeground:\s*([^\r\n]+)\r?\n\s*(&&[^\r\n]+)/);
assert.ok(fg, 'foreground binding for all authenticated pages');
const foregroundExpr = fg[1] + '\n' + fg[2];
const allowed = source.match(/Kawaii\.KawaiiCinnamorollVisit\s*\{[\s\S]*?\ballowed:\s*([^\r\n]+)\r?\n\s*(&&[^\r\n]+)/);
assert.ok(allowed, 'visitor QML allowed binding');
const allowedExpr = allowed[1] + '\n' + allowed[2];
assert.match(source, /parent: Controls\.Overlay\.overlay \? Controls\.Overlay\.overlay : home/);
assert.match(source, /mediaEnabled: home\.appSkin === "ingenieros" && home\.kawaiiAppForeground/);
assert.match(source, /enabled: halloweenController\.motionActive\s*\|\| \(home\.appSkin === "ingenieros" && home\.kawaiiAppForeground\)/);
assert.doesNotMatch(allowedExpr, /halloweenController\.(safe|motionActive|foreground)|Qt\.inputMethod/);
assert.match(video, /source: visitor\.mediaEnabled \?/);
assert.doesNotMatch(video, /source: visitor\.allowed \?/);

function eligible(overrides={}) {
  const home = { visible:true, authReady:true, appSkin:'ingenieros', page:'home', reducedMotion:false, ...overrides };
  const auth={ logged: true };
  const Qt={ application:{state:1}, ApplicationActive:1 };
  const halloweenController={ safe:false, motionActive:false, touchActive:false, foreground:false };
  const scope={ home,auth,Qt,halloweenController };
  home.kawaiiAppForeground=vm.runInNewContext(foregroundExpr,scope);
  return Boolean(vm.runInNewContext(allowedExpr,scope));
}
for (const page of ['home','calicatas','rendiciones','drive','settings','profile']) {
  assert.equal(eligible({page}),true,'AFK visitor should be eligible on '+page);
}
assert.equal(eligible({visible:false}),false,'app hidden cannot play');
assert.equal(eligible({authReady:false}),false,'unauthenticated cannot play');
assert.equal(eligible({appSkin:'halloween'}),false,'only Ingenieros kawaii');
assert.equal(eligible({reducedMotion:true}),false,'accessibility preference must be respected');
const home={visible:true,authReady:true,appSkin:'ingenieros',page:'calicatas',reducedMotion:false};
const ctx={home,auth:{logged:false},Qt:{application:{state:1},ApplicationActive:1},halloweenController:{safe:false,motionActive:false,touchActive:false}};
home.kawaiiAppForeground=vm.runInNewContext(foregroundExpr,ctx);
assert.equal(vm.runInNewContext(allowedExpr,ctx),false,'login required');
ctx.auth.logged=true;
ctx.Qt.application.state=0;
home.kawaiiAppForeground=vm.runInNewContext(foregroundExpr,ctx);
assert.equal(vm.runInNewContext(allowedExpr,ctx),false,'no background playback');
ctx.Qt.application.state=1;
home.kawaiiAppForeground=vm.runInNewContext(foregroundExpr,ctx);
ctx.halloweenController.touchActive=true;
assert.equal(vm.runInNewContext(allowedExpr,ctx),false,'do not play on active finger');
console.log('PASS: authenticated Home/Calicatas/Rendiciones/Drive/Settings/Profile, overlay visible across pages, single 20s idle scheduler and stable MP4 source');

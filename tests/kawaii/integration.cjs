// Static integration check: Kawaii appearance and Extreme-only passive Dock guest.
// Does not build, deploy, or run the Qt application.
const fs = require('node:fs');
const path = require('node:path');
const assert = require('node:assert/strict');
const root = path.resolve(__dirname, '..', '..');
const read = rel => fs.readFileSync(path.join(root, rel), 'utf8');
const includes = (rel, re) => assert.match(read(rel), re, rel);

const images = [
  'pompompurin-engineer.png',
  'cinnamoroll-engineer.png',
  'pompompurin-dock-sit.png',
  'pompompurin-dock-play.png',
];
// Dedicated mobile QRC is linked to AppCalicatasMobile; legacy resources.qrc is Desktop-only.
const qrc = read('resources_mobile_kawaii.qrc');
const cmake = read('CMakeLists.txt');
assert.ok(cmake.includes('set(INGE_MOBILE_KAWAII_QRC'));
assert.ok(cmake.includes('INGE_MOBILE_KAWAII_QRC}'));
for (const name of images) {
  const rel = 'images/kawaii/' + name;
  const png = fs.readFileSync(path.join(root, rel));
  assert.equal(png.toString('hex', 0, 8), '89504e470d0a1a0a', rel);
  assert.equal(png.readUInt32BE(16), 627, rel);
  assert.equal(png.readUInt32BE(20), 627, rel);
  assert.ok(qrc.includes('<file alias="' + name + '">' + rel + '</file>'));
}
assert.ok(!qrc.includes('<file alias="engineers-atlas.png">'), 'do not ship full atlas twice');
includes('qml/Mobile/kawaii/KawaiiMascot.qml', /sourceSize: Qt.size\(tilePixels, tilePixels\)/);
assert.doesNotMatch(read('qml/Mobile/kawaii/KawaiiMascot.qml'), /sourceClipRect/);
includes('qml/Mobile/kawaii/KawaiiLayer.qml', /Mobile\.AuroraField/);
assert.doesNotMatch(read('qml/Mobile/kawaii/KawaiiLayer.qml'), /Mobile\.NothingAuras|id: layer\b/);

includes('qml/Mobile/settings/SettingsApp.qml', /k: "ingenieros", l: "Ingenieros kawaii"/);
includes('qml/Mobile/HomeScreen.qml', /guestSurfaceReady: dock\.visible/);
includes('qml/Mobile/HomeScreen.qml', /Kawaii\.KawaiiDockDecoration/);
includes('qml/Mobile/HomeScreen.qml', /appearancePrefs\.skin/);
includes('qml/Mobile/halloween/HalloweenController.qml', /kawaiiEnabled: resolvedSkin === "ingenieros"/);
includes('qml/Mobile/halloween/HalloweenController.qml', /flow\.extremeMotion && motionActive && kawaiiClock\.remainingMs>0/);
includes('qml/Mobile/halloween/HalloweenController.qml', /safe && guestSurfaceReady && !touchActive/);
includes('qml/Mobile/halloween/HalloweenController.qml', /KawaiiLogic\.stepGuest/);
includes('qml/Mobile/renditions/RendicionesSyncBackdrop.qml', /Kawaii\.KawaiiLayer/);
includes('qml/Mobile/renditions/RStyle.js', /kawaii = name === "ingenieros"/);
includes('qml/Mobile/flowcore/FlowTheme.qml', /skin === "ingenieros"/);
includes('qml/Mobile/renditions/RGlassMenu.qml', /Kawaii\.KawaiiMascot/);
for (const name of ['KawaiiLogic.js', 'KawaiiMascot.qml', 'KawaiiLayer.qml', 'KawaiiDockDecoration.qml'])
  assert.ok(read('CMakeLists.txt').includes('/kawaii/' + name), name);
for (const name of ['helmet.svg', 'sparkle.svg']) {
  assert.ok(qrc.includes('alias="' + name + '"'), name);
  assert.ok(fs.existsSync(path.join(root, 'images/kawaii', name)), name);
}
console.log('PASS: Kawaii QML, appearance, Extreme-only guest, PNG and Qt resource wiring');

const fs = require('node:fs');
const path = require('node:path');
const assert = require('node:assert/strict');
const root = path.resolve(__dirname, '..', '..');
const read = rel => fs.readFileSync(path.join(root, rel), 'utf8');
const name = 'pompompurin-calicata-crash-10s.gif';
const file = fs.readFileSync(path.join(root, 'images/kawaii', name));
assert.equal(file.toString('ascii',0,6), 'GIF89a');
assert.equal(file.readUInt16LE(6),280);
assert.equal(file.readUInt16LE(8),156);
let p=13,frames=0,ms=0,delay=0,transparent=false;
if(file[10]&128) p+=3*(1<<((file[10]&7)+1));
function skipBlocks() {
    while(true) {
        assert.ok(p<file.length,'GIF truncated');
        const length=file[p++];
        if(length===0)break;
        p+=length;
    }
}
while(p<file.length) {
    const tag=file[p++];
    if(tag===0x3b)break;
    if(tag===0x21) {
        const label=file[p++];
        if(label===0xf9) {
            assert.equal(file[p++],4);
            transparent||=(file[p]&1)!==0; p++;
            delay=file.readUInt16LE(p)*10;p+=4;
        } else skipBlocks();
    } else if(tag===0x2c) {
        const packed=file[p+8];p+=9;
        if(packed&128)p+=3*(1<<((packed&7)+1));
        p++;skipBlocks();frames++;ms+=delay;delay=0;
    } else throw new Error('unexpected GIF block '+tag);
}
assert.equal(frames,80,'8-fps keyframed Gemini animation');
assert.equal(ms,10000,'exact 10-second loop');
assert.ok(transparent,'green-screen must be removed');
const qrc=read('resources_mobile_kawaii.qrc');
assert.ok(qrc.includes('alias="'+name+'"'));
const qml=read('qml/Mobile/kawaii/KawaiiProfileCrash.qml');
assert.ok(qml.includes('qrc:/images/kawaii/'+name));
assert.ok(qml.includes('Date.now() - Math.max(crash.lastInputMs, crash.eligibleSince) >= 10000'));
assert.ok(qml.includes('playing: crash.eventActive'));
assert.ok(qml.includes('enabled: false'));
assert.ok(qml.includes('crash.cancel()'));
assert.doesNotMatch(qml,/\.setProperty\(|\.append\(|_markDirty/);
const profile=read('qml/Mobile/pages/CalicataProfile.qml');
assert.ok(profile.includes('Kawaii.KawaiiProfileCrash'));
assert.ok(profile.includes('profile.kawaiiLastInputMs'));
const form=read('qml/Mobile/pages/CalicataFormPage.qml');
assert.ok(form.includes('onActiveChanged: if (active) root.kawaiiLastInteractionAt'));
assert.ok(form.includes('root.flow.appSkin === "ingenieros"'));
assert.ok(form.includes('root.flow.extremeMotion && root.flow.motionAllowed'));
assert.ok(form.includes('!root.labDetailOpen && !root.ubicacionMapOpen'));
assert.ok(form.includes('Qt.application.state === Qt.ApplicationActive'));
assert.ok(read('CMakeLists.txt').includes('/kawaii/KawaiiProfileCrash.qml'));
console.log('PASS: Gemini Calicata GIF 80 frames/10s, AFK 10s, Extreme-only, visual reset and Android RCC');

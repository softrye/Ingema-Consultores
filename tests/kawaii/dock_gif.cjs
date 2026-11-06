const fs = require('node:fs');
const path = require('node:path');
const assert = require('node:assert/strict');

const root = path.resolve(__dirname, '..', '..');
const name = 'pompompurin-dock-walk-wave.gif';
const filename = path.join(root, 'images', 'kawaii', name);
const bytes = fs.readFileSync(filename);
assert.equal(bytes.toString('ascii', 0, 6), 'GIF89a');
const width = bytes.readUInt16LE(6), height = bytes.readUInt16LE(8);
assert.equal(width, 82);
assert.equal(height, 86);

let pos = 13, count = 0, durationMs = 0, delayMs = 0, transparent = false;
const packed = bytes[10];
if (packed & 0x80) pos += 3 * (1 << ((packed & 7) + 1));
const skipBlocks = () => {
  for (;;) {
    assert.ok(pos < bytes.length, 'GIF data truncated');
    const size = bytes[pos++];
    if (size === 0) break;
    pos += size;
  }
};
while (pos < bytes.length) {
  const tag = bytes[pos++];
  if (tag === 0x3b) break;
  if (tag === 0x21) {
    const extension = bytes[pos++];
    if (extension === 0xf9) {
      assert.equal(bytes[pos++], 4);
      transparent ||= (bytes[pos] & 1) !== 0;
      ++pos;
      delayMs = bytes.readUInt16LE(pos) * 10;
      pos += 2;
      pos += 2; // transparent index, block terminator
    } else skipBlocks();
  } else if (tag === 0x2c) {
    const localPacked = bytes[pos + 8];
    pos += 9; // image descriptor following separator
    if (localPacked & 0x80) pos += 3 * (1 << ((localPacked & 7) + 1));
    ++pos; // LZW minimum code size
    skipBlocks();
    count++;
    durationMs += delayMs;
    delayMs = 0;
  } else throw new Error('Unexpected GIF block ' + tag + ' at ' + (pos - 1));
}
assert.equal(count, 30);
assert.equal(durationMs, 12000);
assert.ok(transparent, 'Dock animation must not contain the rendered example Dock');
const qrc = fs.readFileSync(path.join(root, 'resources_mobile_kawaii.qrc'), 'utf8');
assert.ok(qrc.includes('alias="' + name + '"'), 'Mobile Android RCC must pack GIF');
const qml = fs.readFileSync(path.join(root, 'qml/Mobile/kawaii/KawaiiDockDecoration.qml'), 'utf8');
assert.ok(qml.includes('AnimatedImage {'));
assert.ok(qml.includes('qrc:/images/kawaii/' + name));
assert.ok(qml.includes('remainingMs / 12000'));
assert.match(qml, /playing: showing/);
console.log('PASS: 30-frame, 12-second transparent Dock GIF and Android QRC wiring');
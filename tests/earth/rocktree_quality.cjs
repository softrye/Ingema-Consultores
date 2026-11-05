const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const source = path.resolve(__dirname, '../../qml/Mobile/lib/EarthQuality.js');
assert(fs.existsSync(source), 'Earth debe usar una política de detalle enlazada a GraphicsCore');
const context = vm.createContext({});
vm.runInContext(fs.readFileSync(source, 'utf8').replace(/^\.pragma library\s*/m, ''), context);
const low = context.budget('LOW', false), high = context.budget('HIGH', false);
const very = context.budget('VERY_HIGH', false), extreme = context.budget('EXTREME', false);
assert(low.cpuMiB < very.cpuMiB && low.gpuMiB < very.gpuMiB);
assert(low.maxLevel < very.maxLevel && high.maxLevel < very.maxLevel);
assert(low.pixelError > high.pixelError && high.pixelError > very.pixelError);
assert(very.pixelError >= extreme.pixelError);
for (const profile of ['ULTRA_LOW', 'LOW', 'MEDIUM', 'MEDIUM_HIGH', 'HIGH', 'VERY_HIGH', 'EXTREME', 'UNKNOWN', '', null]) {
    const b = context.budget(profile, false);
    assert(b.cpuMiB >= 24 && b.cpuMiB <= 192 && b.gpuMiB >= 24 && b.gpuMiB <= 160);
    assert(b.parallel >= 1 && b.parallel <= 4 && b.maxLevel <= 21);
    const constrained = context.budget(profile, true);
    assert(constrained.cpuMiB <= low.cpuMiB && constrained.gpuMiB <= low.gpuMiB);
    assert(constrained.maxLevel <= low.maxLevel);
}
assert(context.budget('UNKNOWN', false).maxLevel <= low.maxLevel);
console.log('PASS Earth: perfiles, presión térmica/memoria y detalle máximo explícito');

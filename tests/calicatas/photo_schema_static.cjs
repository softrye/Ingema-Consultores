// Esquema de edición/sello de fotos (PhotoEditSchema.js), extraído de
// CalicataPhotoEditor.qml y verificado contra el original el 2026-10-10.
const fs = require("fs"), path = require("path"), vm = require("vm"), assert = require("assert");
const root = path.resolve(__dirname, "..", "..");
const strip = (s) => s.split(/\r?\n/).filter(l => !/^\s*\.(pragma|import)\b/.test(l)).join("\n");
const lib = vm.createContext({ Math, Number, String, JSON });
vm.runInContext(strip(fs.readFileSync(path.join(root, "qml/Mobile/lib/PhotoEditSchema.js"), "utf8")), lib);
let passed = 0;
const check = (name, fn) => { fn(); passed++; console.log("PASS", name); };
check("valores por defecto y rangos válidos", () => {
    const n = lib.normalizeEdit({ style: { sizePct: 50, offsetXPct: -99 }, image: { rotation: 271, angle: 80, exposure: 300, sharpness: -5 } }, () => ({ project: "P" }));
    assert.strictEqual(n.withMetadata, true);
    assert.strictEqual(n.style.sizePct, 10); assert.strictEqual(n.style.offsetXPct, -45);
    assert.strictEqual(n.image.rotation, 270); assert.strictEqual(n.image.angle, 45);
    assert.strictEqual(n.image.exposure, 100); assert.strictEqual(n.image.sharpness, 0);
    assert.strictEqual(n.watermark.text, "P"); assert.strictEqual(n.fields.depth, false); assert.strictEqual(n.fields.zone, true);
});
check("los datos de la captura no se sobrescriben con lo guardado", () => {
    const m = lib.mergeMetadata({ date: "2025-03-05", project: "Real" }, { date: "otra", project: "otro", user: "Ana" }, "Perfil");
    assert.strictEqual(m.date, "2025-03-05"); assert.strictEqual(m.project, "Real");
    assert.strictEqual(m.user, "Ana"); assert.strictEqual(m.category, "Perfil");
});
console.log("PHOTO_SCHEMA_STATIC PASS " + passed + " checks");

// Reglas del espacio de trabajo (CalicataWorkspaceLogic.js), extraídas de
// CalicatasEditorPage.qml y verificadas contra el original el 2026-10-10.
const fs = require("fs"), path = require("path"), vm = require("vm"), assert = require("assert");
const root = path.resolve(__dirname, "..", "..");
const strip = (s) => s.split(/\r?\n/).filter(l => !/^\s*\.(pragma|import)\b/.test(l)).join("\n");
const lib = vm.createContext({ Math, JSON, Number, String, Date, Object, Array });
vm.runInContext(strip(fs.readFileSync(path.join(root, "qml/Mobile/lib/CalicataWorkspaceLogic.js"), "utf8")), lib);
let passed = 0;
const check = (name, fn) => { fn(); passed++; console.log("PASS", name); };
check("ficha vacía se reconoce; cualquier dato la conserva", () => {
    assert.strictEqual(lib.isPlaceholderDoc(null), true);
    assert.strictEqual(lib.isPlaceholderDoc({ header: {}, cortes: [{ descripcion: " " }], observaciones: " " }), true);
    assert.strictEqual(lib.isPlaceholderDoc({ header: { codigo: "C-1" } }), false);
    assert.strictEqual(lib.isPlaceholderDoc({ header: {}, images: { foto2_path: "a.jpg" } }), false);
});
check("conflicto de código entre fichas abiertas del mismo proyecto", () => {
    const a = { header: { code: "C-1", projectId: "p1" } }, b = { header: { codigo: "C-1", projectId: "p1" } };
    assert.ok(lib.codeConflict(a, [a, b], (x, y) => x === y).includes("C-1"));
    assert.strictEqual(lib.codeConflict(a, [a, { header: { code: "C-1", projectId: "p2" } }], (x, y) => x === y), "");
    assert.strictEqual(lib.codeConflict(a, [a, { header: { code: "C-1", projectId: "p1" }, status: "ARCHIVADO" }], (x, y) => x === y), "");
});
check("nombres de archivo seguros y derivados de la cabecera", () => {
    assert.strictEqual(lib.safeStem('a<b>c:d"e/f|g?h*i'), "a_b_c_d_e_f_g_h_i");
    assert.strictEqual(lib.safeStem("name. . "), "name");
    assert.strictEqual(lib.headerStem({ header: { pk: "Km 1:2" } }), "Km 1_2");
    assert.strictEqual(lib.stemForSaveAs({ header: {} }), "calicata");
});
check("estados, sincronización y comparación estructural", () => {
    assert.deepStrictEqual(Array.from(lib.STATUS_LIFECYCLE), ["BORRADOR", "EN_REVISION", "OBSERVADO", "REVISADO", "APROBADO", "EXPORTADO"]);
    assert.strictEqual(lib.statusLabel("EN_REVISION"), "En revisión");
    assert.strictEqual(lib.syncLabel("CONFLICT"), "Conflicto con el servidor");
    assert.strictEqual(lib.deepEqual({ x: [1, "2"] }, { x: [1, "2"] }), true);
    assert.strictEqual(lib.deepEqual({ x: [1] }, { x: ["1"] }), false); // tipos distintos
    assert.strictEqual(lib.excelDrivePath({ remoteFolderPath: "a/b" }, "P", "f.xlsx"), "P › a › b › f.xlsx");
    assert.strictEqual(lib.todayIso(new Date(2025, 0, 5)), "2025-01-05");
});
console.log("WORKSPACE_LOGIC_STATIC PASS " + passed + " checks");

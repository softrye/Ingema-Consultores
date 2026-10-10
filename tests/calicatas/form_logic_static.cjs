// Lógica de dominio de la ficha (CalicataFormLogic.js), extraída de
// CalicataFormPage.qml antes de eliminar la interfaz. La instantánea
// fixtures/form_logic_snapshot.json se verificó contra las funciones originales
// (exportState, normalización, renumeración, laboratorio, datum...) el 2026-10-10.
const fs = require("fs"), path = require("path"), vm = require("vm"), assert = require("assert");
const root = path.resolve(__dirname, "..", "..");
const strip = (s) => s.split(/\r?\n/).filter(l => !/^\s*\.(pragma|import)\b/.test(l)).join("\n");
const base = { console, Math, JSON, Number, String, isFinite, isNaN, parseFloat, parseInt, Date, Object, Array, RegExp };
const rules = vm.createContext(Object.assign({}, base));
vm.runInContext(strip(fs.readFileSync(path.join(root, "qml/Mobile/lib/CalicataRules.js"), "utf8")), rules);
const lib = vm.createContext(Object.assign({}, base, { Rules: rules }));
vm.runInContext(strip(fs.readFileSync(path.join(root, "qml/Mobile/lib/CalicataFormLogic.js"), "utf8")), lib);
const snap = JSON.parse(fs.readFileSync(path.join(__dirname, "fixtures/form_logic_snapshot.json"), "utf8"));
const J = (v) => JSON.parse(JSON.stringify(v));
let seq = 0;
const uuid = () => "uuid-" + (++seq);
const noId = (r) => { const c = Object.assign({}, r); delete c.id; return c; };
let passed = 0;
const check = (name, fn) => { fn(); passed++; console.log("PASS", name); };

const normalized = snap.fixtures.map(f => lib.normalizeCorte(f, { newUuid: uuid }));
check("normalizeCorte / corteToPlainObject", () => {
    assert.deepStrictEqual(J(normalized.map(noId)), snap.normalized);
    assert.deepStrictEqual(J(normalized.map(r => noId(lib.corteToPlainObject(r)))), snap.plain);
});
check("renumberIntervals: DE automático, A normalizado, cadena rota conservada", () => {
    const r = lib.renumberIntervals(normalized);
    assert.deepStrictEqual(J(Array.from(r.rows, noId)), snap.renumbered);
    assert.strictEqual(r.totalDepthM, snap.totalDepthM);
    assert.ok(r.changes.length > 0 && r.changes.every(c => typeof c.index === "number" && typeof c.key === "string"));
});
check("perfil: estadísticas, clase general, nivel freático", () => {
    const rows = Array.from(lib.renumberIntervals(normalized).rows);
    const stats = lib.profileStats(rows);
    assert.deepStrictEqual(J(stats), snap.stats);
    assert.strictEqual(lib.suggestedGeneralClass(stats), snap.generalClass);
    assert.deepStrictEqual(J(lib.derivedGroundwater(rows)), J(snap.groundwater));
});
check("cabecera canónica: alias Web, zona UTM, fechas ISO, freático", () => {
    const h = lib.canonicalHeader({ baseHeader: { project_full_name: "Contrato", water_table_status: "NO_ENCONTRADO" },
        fields: { code: " C-1 ", pk: "Km 1", zona: "18L", fechaInicio: "05/03/2025", fechaFin: "31/02/2025", maquina: " Retro " },
        totalDepthM: 2.5, roadSide: " Izquierdo ", groundwaterText: "", groundwaterCustom: false });
    assert.strictEqual(h.code, "C-1"); assert.strictEqual(h.project_full_name, "Contrato");
    assert.strictEqual(h.utm_zone, 18); assert.strictEqual(h.start_date, "2025-03-05"); assert.strictEqual(h.end_date, "");
    assert.strictEqual(h.water_table_status, "NO_ENCONTRADO"); assert.strictEqual(h.depth_m, "2.500");
    assert.strictEqual(h.location, "Izquierdo"); assert.strictEqual(h.machine, "Retro");
});
check("laboratorio: autoridad SUCS e identidad estable", () => {
    assert.strictEqual(lib.labAuthority({ lab_confirmed_sucs: "gp-gm" }).lab_confirmed_sucs, "GP-GM"); // compuesto válido
    const extra = JSON.parse(lib.deriveLabExtraJson(normalized[0], uuid));
    assert.ok(extra.local_stratum_id && extra.web_lab_review && "status" in extra.web_lab_review);
});
check("datum: WGS84 <-> PSAD56 conserva la forma de zona", () => {
    const r = lib.changeDatum({ datum: "WGS84" }, "PSAD56", { x: "280000.00", y: "8650000.00", zone: "18L" });
    assert.ok(r.utm && /^\d+[C-HJ-NP-X]$/.test(r.utm.zone) && r.header.datum === "PSAD56");
    assert.strictEqual(lib.changeDatum({ datum: "" }, "WGS84", {}).reread, true);
});
console.log("FORM_LOGIC_STATIC PASS " + passed + " checks");

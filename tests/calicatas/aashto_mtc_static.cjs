// Static checks for Perfil AASHTO (MTC MC-05-14, Cuadro 4.3) and the Group Index.
// Runs with plain Node (no app build): node tests/calicatas/aashto_mtc_static.cjs
"use strict";
const fs = require("fs");
const path = require("path");
const vm = require("vm");
const assert = require("assert");

const root = path.resolve(__dirname, "..", "..");
const rulesSrc = fs.readFileSync(path.join(root, "qml/Mobile/lib/CalicataRules.js"), "utf8")
    .split(/\r?\n/).filter(l => !/^\s*\.(pragma|import)\b/.test(l)).join("\n");
const ctx = vm.createContext({ console, Math, JSON, Number, String, isFinite, parseFloat, Date });
vm.runInContext(rulesSrc, ctx);
let passed = 0;
const check = (name, fn) => { fn(); passed++; console.log("PASS", name); };

// Group Index (AASHTO M 145 general formula; negative -> 0).
check("IG F=55 LL=40 PI=25 -> 10", () => assert.strictEqual(ctx.aashtoGroupIndex("A-7-6", 55, 40, 25), 10));
// Web soilClassification: (F-35) y (F-15) acotados a 0..40, (LL-40) y (PI-10) a 0..20.
check("IG F=80 LL=90 PI=50 -> 20 (topes Web)", () => assert.strictEqual(ctx.aashtoGroupIndex("A-7-5", 80, 90, 50), 20));
check("IG F=60 LL=25 PI=1 -> 5 (Web: LL-40 y PI-10 negativos se acotan a 0)", () => assert.strictEqual(ctx.aashtoGroupIndex("A-4", 60, 25, 1), 5));
check("IG A-2-7 F=30 LL=50 PI=30 -> PI term only = 3", () => assert.strictEqual(ctx.aashtoGroupIndex("A-2-7", 30, 50, 30), 3));
check("IG granular groups -> 0", () => ["A-1-a", "A-1-b", "A-3", "A-2-4", "A-2-5"]
    .forEach(c => assert.strictEqual(ctx.aashtoGroupIndex(c, 20, 30, 5), 0)));
check("IG without data -> null", () => {
    assert.strictEqual(ctx.aashtoGroupIndex("A-6", null, 30, 12), null);
    assert.strictEqual(ctx.aashtoGroupIndex("A-6", 50, null, 12), null);
    assert.strictEqual(ctx.aashtoGroupIndex("", 50, 30, 12), null);
});

// A-7 split and classifier from laboratory data only.
check("A-7-5 when PI <= LL-30", () => assert.strictEqual(ctx.classifyAashto(
    { passing10: 90, passing40: 80, passing200: 70, liquidLimit: 60, plasticLimit: 35, plasticityIndex: 25 }).code, "A-7-5"));
check("A-7-6 when PI > LL-30", () => assert.strictEqual(ctx.classifyAashto(
    { passing10: 90, passing40: 80, passing200: 70, liquidLimit: 50, plasticLimit: 20, plasticityIndex: 30 }).code, "A-7-6"));
check("no AASHTO from SUCS alone (SM, no lab data)", () => {
    const r = ctx.reviewLaboratorySample(ctx.labForm({ sucs: "SM" }, { primary_sucs: "SM" }));
    assert.strictEqual(r.aashto, null, "AASHTO must stay empty without laboratory data");
});

// Code normalization (defensive, no mass DB change).
check("normalize AASHTO codes", () => {
    const cases = { "A1a": "A-1-a", "A-1-A": "A-1-a", "A 1 a": "A-1-a", "A1-b": "A-1-b", "A 2 4": "A-2-4",
                    "A-2 4": "A-2-4", "a-7-6": "A-7-6", "A3": "A-3", "A-6": "A-6", "A-8": "", "SM": "", "": "" };
    for (const [input, expected] of Object.entries(cases)) assert.strictEqual(ctx.normalizeAashtoCode(input), expected, input);
});

// Assets: file -> qrc alias -> consumer URL.
const codes = ["A-1-a", "A-1-b", "A-3", "A-2-4", "A-2-5", "A-2-6", "A-2-7", "A-4", "A-5", "A-6", "A-7-5", "A-7-6",
               "ORGANIC", "ROCK_SOUND", "ROCK_WEATHERED"];
const qrc = fs.readFileSync(path.join(root, "resources.qrc"), "utf8");
check("Cuadro 4.3 assets exist, are vector-only and registered", () => {
    for (const code of codes) {
        const file = path.join(root, "SUCS/mtc/cuadro43", code + ".svg");
        const svg = fs.readFileSync(file, "utf8");
        assert.ok(/viewBox="0 0 64 64"/.test(svg), code + " viewBox");
        assert.ok(!/<image|<text|base64/i.test(svg), code + " must not embed raster/text");
        assert.ok(qrc.includes(`<file alias="cuadro43/${code}.svg">SUCS/mtc/cuadro43/${code}.svg</file>`), code + " in qrc");
    }
    const prefixIndex = qrc.indexOf('<qresource prefix="/SUCS/mtc">');
    assert.ok(prefixIndex >= 0 && qrc.indexOf("cuadro43/A-1-a.svg") > prefixIndex, "under /SUCS/mtc");
});
const form = fs.readFileSync(path.join(root, "qml/Mobile/pages/CalicataFormPage.qml"), "utf8");
const exporter = fs.readFileSync(path.join(root, "androidcalicataexporter.cpp"), "utf8");
// Convergencia Web: la trama del perfil y del reporte es la del laboratorio
// (resolveCalicataSucsPattern). Las tramas del Cuadro 4.3 se conservan como
// recurso, pero ya no hay un selector paralelo que las imponga.
check("sin selector de tramas MTC paralelo a la clasificación del laboratorio", () => {
    assert.ok(!form.includes('"qrc:/SUCS/mtc/cuadro43/"') && !exporter.includes('":/SUCS/mtc/cuadro43/"'));
    for (const code of codes.slice(0, 12)) assert.ok(!form.includes(`"AASHTO:${code}"`), code);
});

// Realtime reconciliation guards.
const cloud = fs.readFileSync(path.join(root, "calicatacloudservice.cpp"), "utf8");
// Servidor DEV (private.enforce_calicata_invariants): un cambio live de la FICHA
// que no cambia ninguna columna (valor ya vigente) SÍ suma 1 a row_version. La
// premisa anterior ("el live nunca mueve row_version") era falsa y causaba 40001.
check("RPC parser prioritizes id; live RPC never adopts a revision it cannot attribute", () => {
    assert.ok(cloud.includes('pick({"id", "change_id", "changeId"})'));
    const live = cloud.slice(cloud.indexOf("bool CalicataCloudService::applyFieldChange"),
                             cloud.indexOf("void CalicataCloudService::runLiveCalicataChange"));
    assert.ok(live.length > 0);
    const liveCode = live.replace(/\/\/.*$/gm, "");
    // El envío en sí no lee ni escribe revisiones; la FICHA va por el carril.
    assert.ok(!/row_version|checkpointCloudRevision|getJson\(/.test(liveCode), "el envío live no toca row_version");
    assert.ok(/runLiveCalicataChange\(target, field, textValue, send\)/.test(liveCode));
    const lane = cloud.slice(cloud.indexOf("void CalicataCloudService::runLiveCalicataChange"),
                             cloud.indexOf("void CalicataCloudService::rtHandleBroadcast"));
    // Solo adopta una revisión si el +1 se demuestra propio (antes/después y resto de columnas iguales).
    const adopt = lane.indexOf("checkpointCloudRevision");
    assert.ok(adopt > lane.indexOf("CalicataSync::attributeLiveWrite(") && adopt > lane.indexOf("case CalicataSync::LiveWrite::OwnNoopBump"));
    assert.strictEqual((lane.match(/checkpointCloudRevision/g) || []).length, 1, "un único punto de adopción");
});
check("old Android live events are gone", () => {
    const all = form + cloud + fs.readFileSync(path.join(root, "qml/Mobile/pages/CalicatasEditorPage.qml"), "utf8");
    assert.strictEqual((all.match(/calicata_field_patch|calicata_structure_changed|calicata_persisted/g) || []).length, 0);
});
console.log(`OK ${passed} checks`);

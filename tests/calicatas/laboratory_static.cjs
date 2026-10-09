// Static checks for Calicatas / Laboratorio (pass 1). No app build.
// Run: node tests/calicatas/laboratory_static.cjs
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
const review = (row, extra) => ctx.reviewLaboratorySample(ctx.labForm(row, extra || {}));

// CASE 4 / 24: LL or LP empty -> IP null (never 0).
check("LL/LP empty -> IP null", () => {
    assert.strictEqual(review({ wl: "", lp: "" }).ip, null);
    assert.strictEqual(review({ wl: "32.5", lp: "" }).ip, null);
});
// CASE 5: decimals accepted; IP = LL - LP.
check("LL/LP enteros (Web validateInteger) -> IP derivado", () => {
    assert.strictEqual(review({ wl: "32", lp: "18" }).ip, 14);
    assert.strictEqual(ctx.webLabNormalizeLimit("32"), "32");
    assert.strictEqual(ctx.webLabNormalizeLimit("32,5"), null, "decimal = error, no redondeo");
    assert.strictEqual(ctx.webLabNormalizeLimit("-1"), null);
    assert.strictEqual(ctx.webLabNormalizeLimit(""), "");
    assert.ok(ctx.webLabValidate({ wl: "32", lp: "18" }, {}).valid);
    assert.ok(!ctx.webLabValidate({ wl: "32.5", lp: "18.4" }, {}).valid);
});
// CASE 6: NP is its own state (not LP = 0, not "no test").
check("NP no existe en Web: no altera la clasificación (dato antiguo se conserva)", () => {
    const np = review({ wl: "", lp: "" }, { nonplastic_confirmed: true });
    assert.ok(np.observations.some(o => o.id === "atterberg-missing"), "sin LL/LP Web pide límites");
    assert.strictEqual(ctx.labForm({ lp: "0" }, { nonplastic_confirmed: true }).plasticLimit, "0");
    assert.strictEqual(ctx.hasLabTestData(ctx.labForm({}, { nonplastic_confirmed: true })), false);
    assert.strictEqual(ctx.hasLabTestData(ctx.labForm({}, {})), false);
});
// CASE 7: granulometry 0–100 and monotonic.
check("granulometry range/monotonic", () => {
    assert.strictEqual(ctx.webLabNormalizePercent("101", { min: 0, max: 100 }), null);
    assert.strictEqual(ctx.webLabNormalizePercent("-2", { min: 0, max: 100 }), null);
    assert.strictEqual(ctx.webLabNormalizePercent("", { min: 0, max: 100 }), "");
    const v = ctx.webLabValidate({ gmax: "100", g2: "40", g04: "60" }, { passing_no4: "85" });
    assert.ok(!v.valid, "N.º 40 > N.º 10 must be detected");
});
// CASE 8 / 9: Cu / Cc only with data; no division by zero.
check("Cu/Cc no existen en Web: D10/D30/D60 no cambian la sugerencia", () => {
    assert.strictEqual(typeof ctx.gradationCoefficients, "undefined");
});
check("grueso limpio + D10/D30/D60 -> sigue siendo conjunto (Web)", () => {
    const r = review({ gmax: "100", g2: "80", g04: "40", g008: "3" },
                     { passing_no4: "95", d10: "0.1", d30: "0.3", d60: "0.6" });
    assert.deepStrictEqual(Array.from(r.sucs.candidates), ["SW", "SP"]);
    assert.strictEqual(r.sucs.conclusive, false);
});
// CASE 13: AASHTO is never derived from SUCS alone.
check("AASHTO not from SUCS", () => {
    assert.strictEqual(review({ sucs: "SM" }, { primary_sucs: "SM" }).aashto, null);
});
check("granular con LL/LP -> A-1-b con IG 0", () => {
    const r = review({ gmax: "100", g2: "70", g04: "40", g008: "12", wl: "20", lp: "18" }, { passing_no4: "85" });
    assert.strictEqual(r.aashto.code, "A-1-b");
    assert.strictEqual(r.aashto.groupIndex, 0);
});
// Single state vocabulary.
check("lab stages", () => {
    assert.strictEqual(ctx.labStage({ hasSample: false, hasTests: false }), "no_data");
    assert.strictEqual(ctx.labStage({ hasSample: true, hasTests: false }), "no_test");
    assert.strictEqual(ctx.labStage({ hasTests: true, suggestion: false }), "in_progress");
    assert.strictEqual(ctx.labStage({ hasTests: true, suggestion: true }), "suggested");
    assert.strictEqual(ctx.labStage({ hasTests: true, suggestion: true, confirmed: true }), "confirmed");
});
check("LL/LP stepper en enteros", () => {
    assert.strictEqual(ctx.stepLabInteger("32", 1), "33");
    assert.strictEqual(ctx.stepLabInteger("", -1), "0");
});
// QML wiring (source-level).
const form = fs.readFileSync(path.join(root, "qml/Mobile/pages/CalicataFormPage.qml"), "utf8").replace(/\r\n/g, "\n");
const body = name => {
    const i = form.indexOf("function " + name + "("), e = form.indexOf("\n    }\n", i);
    assert.ok(i >= 0 && e > i, name);
    return form.slice(i, e);
};
check("laboratorio = autoridad; adoptar es explícito", () => {
    const info = body("labInfo");
    assert.ok(/projection/.test(info) && /suggestion/.test(info));
    assert.ok(!/setProperty/.test(info), "labInfo must be read-only");
    const set = body("setLabClassification");
    assert.ok(/primary_sucs/.test(set) && /lab_confirmed_aashto/.test(set) && !/setProperty\(index, "(sucs|aashto)"/.test(set),
              "adoptar escribe el laboratorio, nunca el valor del estrato");
});
check("A-8 visual (solo Android) ya no se ofrece; el dato antiguo se conserva", () => {
    assert.ok(!form.includes("function confirmOrganicA8("));
});
check("sample interval stays inside the stratum", () => {
    assert.ok(/dentro del estrato/.test(body("commitSampleInterval")));
});
check("natural moisture never inherits field humidity", () => {
    assert.ok(!/hum2[^\n]*humedad\b/.test(form.replace(/\/\/.*$/gm, "")));
});
check("LL/LP: el commit valida enteros con mensaje explícito", () => {
    assert.ok(body("commitLabLimit").includes("webLabNormalizeLimit") && form.includes("LL y LP son números enteros"));
});
const cloud = fs.readFileSync(path.join(root, "calicatacloudservice.cpp"), "utf8");
const strip = t => t.replace(/\/\/.*$/gm, "");
const syncLab = strip(cloud.slice(cloud.indexOf("*syncLab = ["), cloud.indexOf("if (sampleType.isEmpty())", cloud.indexOf("*syncLab = ["))));
// C1-C4: decimals are never rounded and never fail the whole calicata.
check("cloud: LL/LP decimales antiguos -> pendiente aislado, sin redondeo ni v03", () => {
    assert.ok(!syncLab.includes("upsert_my_calicata_lab_result_v03") && syncLab.includes("upsert_my_calicata_lab_result_v02"));
    assert.ok(syncLab.includes("\"LAB_LIMITS\""));
    assert.ok(!/qRound|std::round|toInt\(/.test(syncLab), "no rounding of LL/LP");
    assert.ok(/decimalLimits\) \{[\s\S]{0,300}markPending\(QStringLiteral\("LAB_LIMITS"\), true\);[\s\S]{0,40}done\(\)/.test(syncLab),
              "decimal -> pendiente + continúa con el resto");
});
// F4: lab primary_sucs / aashto never invented from the field SUCS.
check("no blind mirror field -> lab", () => {
    assert.ok(!/localRow\.value\(QStringLiteral\("sucs"\)\)/.test(syncLab), "syncLab must not read stratum SUCS");
    assert.ok(syncLab.includes("lab_confirmed_aashto"));
    const auth = body("_labAuthority");
    assert.ok(auth.includes("lab_confirmed_sucs") && !/row\.sucs/.test(auth));
});
// R1-R10: LAB_RESULT realtime on the canonical contract.
check("LAB_RESULT live: whitelist, send, receive without dirty/rebroadcast", () => {
    for (const f of ["sieve_max_pct", "sieve_no4_pct", "sieve_2mm_pct", "sieve_04mm_pct", "sieve_008mm_pct", "liquid_limit",
                     "plastic_limit", "natural_moisture_pct", "primary_sucs", "is_composite", "secondary_sucs", "aashto",
                     "laboratory_source", "test_date"]) assert.ok(cloud.includes(`QStringLiteral("${f}")`), f);
    assert.ok(/type == QLatin1String\("LAB_RESULT"\)\) return kLabResultFields\.contains/.test(cloud));
    assert.ok(form.includes('CalicataCloud.applyFieldChange(root.doc, "LAB_RESULT", cur.remote'));
    const apply = strip(body("_applyLiveLab"));
    assert.ok(!/_markDirty|saveDraft|applyFieldChange|syncDocument|hydrate/.test(apply), "remote apply must stay local");
    assert.ok(/deriveLabFields\(\)/.test(apply), "derived values recomputed");
    assert.ok(form.includes('else if (type === "LAB_RESULT") applied = root._applyLiveLab('));
});
check("decimal LL/LP never sent live while server is integer", () => {
    const re = /\.\d*[1-9]/;
    assert.ok(re.test("32.5") && re.test("18.40") && !re.test("32") && !re.test("32.00"));
    assert.ok(body("_liveLabFields").includes("[1-9]/.test(t) ? undefined : t"));
});
// Migraciones solo Android (LL/LP numeric, campos durables) no aplicadas y
// contrarias al contrato Web: fuera de supabase/migrations (no se empujan).
check("migraciones Android-only fuera del flujo de migraciones", () => {
    for (const f of ["20260930200000_calicata_lab_limits_numeric.sql", "20260930200100_calicata_lab_durable_fields.sql"]) {
        assert.ok(!fs.existsSync(path.join(root, "supabase/migrations", f)), f);
        assert.ok(fs.existsSync(path.join(root, "supabase/superseded", f)), "conservada: " + f);
    }
});
// Final pass: header, Dock context, single handlers, origin mapping.
const editor = fs.readFileSync(path.join(root, "qml/Mobile/pages/CalicatasEditorPage.qml"), "utf8").replace(/\r\n/g, "\n");
const mainQml = fs.readFileSync(path.join(root, "qml/Mobile/Main.qml"), "utf8").replace(/\r\n/g, "\n");
check("H1-H6: Laboratorio uses the shared GenStageHeader (blue dot + icon tile)", () => {
    // P0-C: una sola cabecera para todas las etapas (Revisión ya no usa la legacy).
    assert.strictEqual((form.match(/GenStageHeader \{/g) || []).length, 2);   // ficha + vista previa del swipe
    assert.ok(!form.includes("root._swipePeekStage > 4"));
    assert.ok(!form.includes("root.stageIndex >= 0 && root.stageIndex <= 4") && !form.includes("visible: root.stageIndex > 4"));
    assert.ok(form.includes("root.stageIndex === 3 ? root.iconSamplesName"));
    assert.ok(form.includes('readonly property string iconSamplesName: "lab.flask"'));
    assert.ok(fs.readFileSync(path.join(root, "qml/Mobile/lib/IconCatalog.js"), "utf8").includes('"lab.flask": "beaker"'));
});
check("D1-D14: Dock publishes a real Laboratorio context with long-press children", () => {
    assert.ok(editor.includes("else if (stage === 3)\n            actions.push(root.labContextAction())"));
    const action = editor.slice(editor.indexOf("function labContextAction()"), editor.indexOf("function runContextCommand("));
    for (const c of ["calicatas.lab.new", "calicatas.lab.filter:", "calicatas.lab.pending", "calicatas.lab.summary",
                     "calicatas.lab.history", "calicatas.lab.profile", "calicatas.lab.tab:context"])
        assert.ok(action.includes(c), c);
    assert.ok(/children:/.test(action), "children -> Liquid Glass submenu via press-and-hold");
    assert.ok(/if \(strata === 0\)[\s\S]{0,300}calicatas\.lab\.profile/.test(action), "0 strata: no dead Nueva muestra");
    assert.ok(!/confirmLab/.test(action), "no classification change from the Dock");
    assert.ok(editor.includes('root.formValue(form, "runLabCommand")'));
    // Submenús (Laboratorio/Fotos) llegan a la barra de acciones por el árbol publicado.
    assert.ok(mainQml.includes("function hasChildren(action)") && mainQml.includes("actionMenuV1.openFor(modelData)"));
});
check("single handlers: Nueva muestra / filter shared by screen and Dock", () => {
    assert.strictEqual((form.match(/onClicked: root\.labNewSample\(\)/g) || []).length, 1);
    assert.ok(body("runLabCommand").includes('if (c === "new") root.labNewSample()'));
    assert.ok(body("runLabCommand").includes("root.labSetFilter("));
    assert.ok(form.includes("onFlipped: root.labSetFilter(modelData.key)"));
    assert.ok(!/mobileLaboratoryOverview\.labFilter/.test(form), "no parallel filter state");
    assert.ok(body("labNewSample").includes("_labGuarded()"), "double-tap guard");
    assert.ok(/labFilterKey === "pending"\) return info\.pending/.test(form), "pending filter uses lab_cloud_pending");
});
check("L5: origin comes from the Perfil global fields", () => {
    const origin = body("labOriginLabel");
    assert.ok(origin.includes("prfOriginLabel(p.material_origin)") && origin.includes("natural_origin") && origin.includes("pattern_anthropic"));
    assert.ok(!form.includes("Origen sin registrar"));
});
check("E1-E4: 0 strata vs 0 tests", () => {
    assert.ok(form.includes('text: "Ir a Perfil"') && form.includes("onClicked: root.labGoProfile()"));
    assert.ok(!/visible: cortesModel\.count > 0 && mobileLaboratoryOverview\.labCount === 0/.test(form));
});
// Web contract (feature/calicatas-cloud-media-04a, CalicataLaboratoryResultsTable):
// "M-XX, intervalo y tipo proceden de Campo y son de solo lectura".
check("AUTOFILL: shared sample M-02 / MS / 1.20–1.40 shown without asking", () => {
    const x = ctx.labSampleSummary({ de: "1.05", a: "1.50", tipo_muestra: "MS", sample_code: "M-02",
                                     muestra_desde: "1.20", muestra_hasta: "1.40" }, 1);
    assert.strictEqual(x.hasSample, true);
    assert.strictEqual(x.type, "MS");
    assert.strictEqual(x.reference, "M-02");
    assert.strictEqual(x.referenceIsPresentational, false);
    assert.strictEqual(x.interval, "1.20 – 1.40 m");
});
check("WEB-COMPAT: M-01 is presentational only; stratum interval is not a sample interval", () => {
    const x = ctx.labSampleSummary({ de: "0.00", a: "1.05", tipo_muestra: "MA", muestra_desde: "0.00", muestra_hasta: "1.05" }, 0);
    assert.strictEqual(x.reference, "M-01");
    assert.strictEqual(x.referenceIsPresentational, true);
    assert.strictEqual(x.code, "", "M-01 never becomes the canonical code");
    assert.strictEqual(x.interval, "", "inherited stratum interval is not invented as sample interval");
    assert.strictEqual(x.stratumInterval, "0.00 – 1.05 m");
    const none = ctx.labSampleSummary({ de: "0.00", a: "1.05" }, 0);
    assert.strictEqual(none.hasSample, false);
});
check("NO DOUBLE CAPTURE: Lab detail has no editable sample type/from/to/ID", () => {
    const a = form.indexOf("// MUESTRA (Campo/Perfil, solo lectura)");
    const b = form.indexOf("// Canonical Web laboratory contract", a);
    assert.ok(a > 0 && b > a);
    const block = form.slice(a, b);
    for (const bad of ['label: "Tipo de muestra"', "commitSampleInterval", '"ID de muestra"', 'label: "Desde (m)"',
                       'label: "Hasta (m)"', "BoundTextField", "prfPick("])
        assert.ok(!block.includes(bad), bad);
    assert.ok(block.includes("root.labEditSampleInProfile(mobileSampleCard.corteIdx)"), "edits the same Perfil sample");
    assert.ok(body("labEditSampleInProfile").includes('root.selectStratum(index, "field")'));
});
check("NO LEGACY: no 'Listo' in the Lab detail; adopt chips instead of confirm buttons", () => {
    // "Listo" (botón de vidrio de Calicatas) solo fuera del detalle de Laboratorio.
    assert.ok(form.includes('GenDialogButton { visible: !root.labSheetActive; Layout.fillWidth: false; primary: true; text: "Listo"'));
    assert.ok(!/Confirmar SUCS "|Confirmar AASHTO "|confirmLabSucs|confirmLabAashto/.test(form));
    assert.ok(/delegate: LabSuggestionChip \{[\s\S]{0,300}root\.adoptLabSucs\(/.test(form));
    assert.ok(/LabSuggestionChip \{[\s\S]{0,900}root\.adoptLabAashto\(/.test(form));
    assert.ok(body("openLabForStratum").includes("labSheetActive = true"), "explicit lab-detail state");
    assert.ok(form.includes("readonly property bool labDetailOpen: stratumSheet.visible && root.labSheetActive && !root.labDetailClosing"));
});
check("Lab source/date rows hydrate saved values (Web: sin observaciones de laboratorio)", () => {
    for (const k of ["test_date", "laboratory_source"])
        assert.ok(form.includes(`modelText: String(mobileSampleCard.labExtra().${k} || "")`), k);
    assert.ok(!form.includes("mobileSampleCard.labExtra().lab_observations"));
});
// Floating Lab detail + motion (final visual pass).
const sheet = form.slice(form.indexOf("        id: stratumSheet"), form.indexOf("id: stratumSheetBody"));
check("A3: Lab detail is a floating window, not fullscreen geometry", () => {
    assert.ok(sheet.includes("width: floating ? Math.min(parent.width - 2 * sideMargin, root.dp(780)) : parent.width"));
    assert.ok(/height: floating \? Math\.max\(root\.dp\(320\), Math\.min\(parent\.height \* 0\.88/.test(sheet));
    assert.ok(sheet.includes("radius: stratumSheet.floating ? root.dp(26) : 0"));
    assert.ok(sheet.includes("modal: !floating"), "Dock stays visible: own scrim instead of modal overlay");
    assert.ok(form.includes("id: labDetailScrim") && /labDetailScrim[\s\S]{0,900}onClicked: root\.closeLabDetail\(\)/.test(form));
});
check("A4: no 'Listo' in the floating Lab detail", () => {
    assert.ok(/GenDialogButton \{ visible: !root\.labSheetActive;[^\n]*text: "Listo"/.test(sheet));
});
check("A5-A7/A15: single animated close path; no direct visible=false", () => {
    const close = body("closeLabDetail");
    assert.ok(close.includes("root.finishStratum(false)") && close.includes("labDetailClosing = true"));
    assert.ok(!/stratumSheet\.visible\s*=\s*false/.test(form));
    assert.ok(/exit: Transition \{[\s\S]{0,300}enabled: stratumSheet\.floating[\s\S]{0,400}"scale"; from: 1; to: root\.labOriginValid \? 0\.9 : 0\.96/.test(sheet));
    assert.ok(/enter: Transition \{[\s\S]{0,700}"scale"; from: stratumSheet\.originScale; to: 1/.test(sheet));
    // Shared-origin (tarjeta) o centro + translateY 24 dp; solo opacity/scale/traslación (ligero).
    assert.ok(/"offsetY"; from: stratumSheet\.originDY; to: 0/.test(sheet) && /"offsetX"; from: 0; to: stratumSheet\.originDX/.test(sheet));
    assert.ok(sheet.includes("readonly property real originDY: root.labOriginValid ? root.labOriginY - (baseY + height / 2) : root.dp(24)"));
    assert.ok(form.includes("root.openLabForStratum(labCard.corteIdx, labCard)"), "card is the open origin");
    assert.ok(!/Timer \{[^}]*labDetail/.test(form), "no timer hack");
    assert.ok(form.includes("if (root.labSheetActive && stratumSheet.visible) { root.closeLabDetail(); return true }"), "Back");
    assert.ok(form.includes('onClicked: root.closeLabDetail()'), "arrow/scrim");
    assert.ok(/function onClosed\(\) \{[\s\S]{0,400}stratumSheet\.opacity = 1/.test(form), "no zombie opacity after exit");
    assert.ok(body("openLabForStratum").includes("labDetailClosing = false"), "reopen during exit is clean");
});
check("state does not depend on profileMode", () => {
    assert.ok(!/labDetailOpen:[^\n]*profileMode/.test(form));
    assert.ok(!/floating: [^\n]*profileMode/.test(sheet));
});
check("A9/A10: tabs switch immediately (same commands)", () => {
    assert.ok(/function setLabTab\(key\) \{\n\s*if \(\["lab", "context", "history"\]\.indexOf\(key\) < 0 \|\| key === root\.labTab\) return\n\s*root\.labTab = key/.test(form));
    assert.ok(!form.includes("labTabSwitch") && !form.includes("labTabFade"));
    assert.ok(body("runLabCommand").includes("root.setLabTab("));
});
check("A11: sin gradación avanzada D10/D30/D60 (Web no la registra)", () => {
    assert.ok(!form.includes("labAdvancedOpen") && !form.includes('"Gradación avanzada (opcional)"'));
});
check("A1: card press feedback", () => {
    assert.ok(/scale: labCardTap\.pressed \? 0\.985 : 1\.0/.test(form) && /scale: labPillTap\.pressed \? 0\.97 : 1/.test(form));
});
console.log(`OK ${passed} checks`);

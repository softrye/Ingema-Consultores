// Static checks: Android InGe Drive consumes Files Core 01E (no app build).
// Run: node tests/documents/drive_files_core_static.cjs
"use strict";
const fs = require("fs");
const path = require("path");
const assert = require("assert");

const root = path.resolve(__dirname, "..", "..");
const read = p => fs.readFileSync(path.join(root, p), "utf8").replace(/\r\n/g, "\n");
const cpp = read("src/documents/nothingdocuments.cpp");
const docs = read("clouddocs.cpp");
const qml = read("qml/Mobile/documents/NothingDocumentsRoot.qml");
const form = read("qml/Mobile/pages/CalicataFormPage.qml");
const fn = name => { const i = cpp.indexOf(name); assert.ok(i >= 0, name); return cpp.slice(i, cpp.indexOf("\n}\n", i)); };
let passed = 0;
const check = (name, f) => { f(); passed++; console.log("PASS", name); };

check("ID-2/ID-9: current version resolved by the server (version NULL), not the listing", () => {
    const d = fn("void NothingDocuments::download(");
    assert.ok(/get_binary_document_access_v01[\s\S]{0,200}"p_document_version_id",QVariant\(\)/.test(d));
    assert.ok(!d.includes("La versión cambió"), "no stale-listing failure");
});
check("ID-1/ID-10: mirror identity = (space_id, node_id); content by content_version", () => {
    assert.ok(fn("QString NothingDocuments::mirrorDir(").includes('"/mirror/"+space+"/"+nodeId'));
    const d = fn("void NothingDocuments::download(");
    assert.ok(d.includes('cached.value("content_version").toLongLong()==content'), "no re-download when equal");
    assert.ok(d.includes("STALE_LOCAL"));
    assert.ok(!/storage_path"\)\.toString\(\)\s*\+|mirror\/"\+.*name/.test(d), "storage_path/name never identity");
});
check("ID-5/ID-6: offline opens cache or reports without crash", () => {
    const d = fn("void NothingDocuments::download(");
    assert.ok(d.includes('openMirrored(cached.value("file").toString(),"LOCAL_AVAILABLE_OFFLINE")'));
    assert.ok(d.includes("Sin conexión y sin copia local de este archivo."));
});
check("ID-7: Android upload = reserve -> begin -> exact Storage (no upsert) -> finalize; no raw orphan", () => {
    const u = fn("void NothingDocuments::upload(");
    const order = ["reserve_binary_document_upload_v01", "begin_binary_document_upload_v01", "uploadExact(", "finalize_binary_document_upload_v01"]
        .map(k => u.indexOf(k));
    assert.ok(order.every((v, i) => v > 0 && (i === 0 || v > order[i - 1])), "canonical order");
    assert.ok(!u.includes("uploadFile("), "legacy raw upload not used");
    const exact = docs.slice(docs.indexOf("void CloudDocs::uploadExact("), docs.indexOf("void CloudDocs::uploadFile("));
    assert.ok(exact.includes('"x-upsert", "false"') && exact.includes("objectKey"));
});
check("upload dialog no longer asks for a raw project id", () => {
    assert.ok(!qml.includes("projectInput") && qml.includes("files.uploadTargetLabel"));
});
check("LAB-16: presentation rows never append null members", () => {
    const n = form.slice(form.indexOf("function _normalizeCorte("), form.indexOf("function corteToPlainObject("));
    // Ni miembros null ni listas/objetos anidados (remote_samples → "observations is null").
    assert.ok(n.includes('if (o[key] !== null && o[key] !== undefined && typeof o[key] !== "object") r[key] = o[key]'));
    assert.ok(n.includes("r._extraJson = JSON.stringify(o)"), "canonical nulls preserved in _extraJson");
});
check("LAB-17: horizontalStretchFactor only with fillWidth", () => {
    assert.ok(form.includes("Layout.horizontalStretchFactor: modelData.w === 0 ? (modelData.s || 1) : -1"));
});
check("LAB-15: no legacy −/+ steppers in the Laboratorio editor", () => {
    const a = form.indexOf('Text { text: "Granulometría (MTC E107) · % que pasa"');
    const b = form.indexOf("// Humedad natural: dato de ensayo", a);
    assert.ok(a > 0 && b > a && !form.slice(a, b).includes("LabStepper {"));
});
console.log(`OK ${passed} checks`);

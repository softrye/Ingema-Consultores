// Exercises the real QML functions at the document/render boundary.
// Run: node tests/calicatas/photo_local_preview.cjs
"use strict";
const fs = require("node:fs");
const path = require("node:path");
const vm = require("node:vm");
const assert = require("node:assert/strict");
const source = fs.readFileSync(path.resolve(__dirname, "../../qml/Mobile/pages/CalicataFormPage.qml"), "utf8");
function functionSource(name, indent = 4) {
    const start = source.indexOf("function " + name + "(");
    assert.ok(start >= 0, "Production function " + name);
    const end = source.indexOf("\n" + " ".repeat(indent) + "}", start);
    assert.ok(end > start, "Function end " + name);
    return source.slice(start, end + indent + 2);
}
function fixture() {
    const published = [], errors = [];
    let committed = "file:///previous.jpg";
    const doc = {
        instanceId: "sheet-a", closed: false, images: {}, fileUrl: "file:///sheet.json",
        persistPhoto: () => "file:///copied-original.jpg",
        cachedPhotoUrl: () => committed,
        originalPhotoUrl: () => "file:///previous-original.jpg",
        photoSlot: () => ({ syncState: "SYNCED", versions: [], activeVersionId: "" })
    };
    const root = {
        doc, _pendingPhotoDoc: doc, _pendingPhotoDocId: "sheet-a",
        _pendingStampIdx: 2, _pendingPickedUrl: "file:///camera-temp.jpg",
        _photoRequestPending: true, _documentClosing: false,
        _photoProcessing: {}, _photoLocalPreviews: {},
        _syncTimestampNow() {},
        _releasePendingPhotoImport() { this._photoRequestPending = false; this._pendingPickedUrl = ""; },
        _photoMediaEntry: () => null,
        _queuePhotoSync(target, idx) { published.push([target.instanceId, idx]); },
        invalidateReview() {},
        showInfo(title, message) { errors.push([title, message]); }
    };
    const context = vm.createContext({ root, doc, docConnections: { target: doc }, console: { info() {} } });
    for (const name of ["_docInstanceId", "_commitPendingPhoto", "_photoSource", "_hasPhoto", "_photoSyncState", "photoSlotInfo", "photoActions", "runPhotoAction", "photoHasAction", "onPhotoPersisted"]) {
        vm.runInContext(functionSource(name, name === "onPhotoPersisted" ? 8 : 4), context);
        root[name] = context[name];
    }
    return { root, doc, context, published, errors, commit(url) { committed = url; } };
}
let passed = 0;
function check(name, test) { test(); ++passed; console.log("PASS", name); }

// Missing preview binding would leave an empty/old card until the full render ends.
check("accepted copy is shown while the committed photo and outbox are unchanged", () => {
    const f = fixture();
    assert.equal(f.root._commitPendingPhoto(true), true);
    assert.equal(f.root._photoSource(2), "file:///copied-original.jpg");
    assert.equal(f.doc.cachedPhotoUrl(2), "file:///previous.jpg");
    assert.equal(f.root._photoSource(1), "file:///previous.jpg");
    assert.equal(f.published.length, 0);
    assert.equal(f.root.photoSlotInfo(2).label, "Procesando…");
});
// Editing/deleting/publishing the previous revision while its replacement renders is unsafe.
check("processing copy cannot be edited, deleted or prematurely published", () => {
    const f = fixture();
    f.root._commitPendingPhoto(false);
    for (const id of ["capture", "pick", "edit", "versions", "publish", "empty", "retry", "discardSend", "keepMine", "keepRemote"])
        assert.equal(f.root.photoHasAction(2, id), false, id);
    f.root.runPhotoAction("publish", 2);
    assert.equal(f.published.length, 0);
});
check("successful render replaces the preview and enqueues exactly one committed revision", () => {
    const f = fixture();
    f.root._commitPendingPhoto(true);
    f.commit("file:///stamped-derivative.jpg");
    f.root.onPhotoPersisted(2, "file:///stamped-derivative.jpg", "");
    assert.equal(f.root._photoSource(2), "file:///stamped-derivative.jpg");
    assert.deepEqual(f.published, [["sheet-a", 2]]);
    assert.equal(f.root._photoLocalPreviews[2], undefined);
    assert.equal(f.root._photoProcessing[2], undefined);
});
check("render failure removes only the provisional view and preserves the previous photo", () => {
    const f = fixture();
    f.root._commitPendingPhoto(true);
    f.root.onPhotoPersisted(2, "", "Disk full");
    assert.equal(f.root._photoSource(2), "file:///previous.jpg");
    assert.equal(f.root._photoLocalPreviews[2], undefined);
    assert.equal(f.published.length, 0);
    assert.equal(f.errors.length, 1);
});
check("a preview never leaks into another document", () => {
    const f = fixture();
    f.root._commitPendingPhoto(false);
    const other = { ...f.doc, instanceId: "sheet-b", cachedPhotoUrl: () => "file:///other-sheet.jpg" };
    f.context.doc = other;
    f.root.doc = other;
    assert.equal(f.root._photoSource(2), "file:///other-sheet.jpg");
    other.closed = true;
    assert.equal(f.root._photoSource(2), "");
    assert.equal(f.root._photoSource(0), "");
});
check("failed copy creates neither a preview nor a publication", () => {
    const f = fixture();
    f.doc.persistPhoto = () => "";
    assert.equal(f.root._commitPendingPhoto(false), false);
    assert.equal(f.root._photoSource(2), "file:///previous.jpg");
    assert.equal(f.root._photoLocalPreviews[2], undefined);
    assert.equal(f.published.length, 0);
});
console.log(`${passed} photo local preview checks passed.`);

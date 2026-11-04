'use strict';
// Execute the actual QML startup handlers without building or touching user data.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const test = require('node:test');
const path = require('node:path');
const base = path.join(__dirname, '../..');
const form = fs.readFileSync(path.join(base, 'qml/Mobile/pages/CalicataFormPage.qml'), 'utf8');
const native = fs.readFileSync(path.join(base, 'calicatacloudservice.cpp'), 'utf8');
function blockAfter(source, marker) {
  const start = source.indexOf(marker);
  assert(start >= 0, `Missing ${marker}`);
  const open = source.indexOf('{', start);
  let depth = 1, end = open + 1;
  // These startup blocks contain no braces inside string literals.
  for (; depth && end < source.length; end++) {
    if (source[end] === '{') depth++;
    else if (source[end] === '}') depth--;
  }
  return source.slice(open + 1, end - 1);
}
function context() {
  const calls = [];
  const root = {
    _ready: false, doc: {}, _updateLayoutSize() {}, _recoverInterruptedCapture() {},
    _scheduleMediaCloudReconcile() { calls.push('schedule'); },
  };
  const ctx = { root, doc: root.doc, calls, _ready: false,
    ensureDocsRoots() {}, importFromDoc() { calls.push('import'); },
    Qt: { callLater(fn) { if (fn) fn(); } },
  };
  vm.createContext(ctx);
  return { ctx, calls, root };
}
test('already-loaded ficha starts media and presence after importing the form', () => {
  const {ctx, calls} = context();
  vm.runInContext(blockAfter(form, '    Component.onCompleted: {'), ctx);
  assert.deepEqual(calls, ['import', 'schedule']);
});
test('late remote identity and restored account trigger reconciliation', () => {
  const scope = form.match(/readonly property string mediaCloudScope:[\s\S]*?onMediaCloudScopeChanged:/)?.[0] || '';
  assert.match(scope, /instanceId/);
  assert.match(scope, /header\.projectId/);
  assert.match(scope, /header\.remoteCalicataId/);
  assert.match(scope, /auth\.logged/);
  assert.match(scope, /auth\.userId/);
  const handler = form.match(/onMediaCloudScopeChanged:\s*([^\n]+)/)?.[1] || '';
  assert.match(handler, /_scheduleMediaCloudReconcile/);
});
test('startup requests coalesce until the component is ready', () => {
  let starts = 0;
  const {ctx, root} = context();
  ctx.mediaCloudReconcile = { restart() { starts++; } };
  vm.runInContext('function schedule() {' + blockAfter(form, 'function _scheduleMediaCloudReconcile(') + '}', ctx);
  ctx.schedule();
  assert.equal(starts, 0);
  root._ready = true;
  ctx.schedule();
  assert.equal(starts, 1);
  assert.match(form, /id: mediaCloudReconcile\s+interval: 0\s+repeat: false/);
});
test('initial socket failure clears the failed attempt and schedules retry', () => {
  const start = native.indexOf('void CalicataCloudService::rtConnect()');
  const errorHandler = blockAfter(native.slice(start), 'connect(socket, &QSslSocket::errorOccurred');
  assert.match(errorHandler, /rtDisconnect\(false\)/);
  assert.match(errorHandler, /rtScheduleRetry\(\)/);
});
test('private presence keeps the documented Supabase wire contract', () => {
  assert.match(native, /config\[QStringLiteral\("private"\)\] = true/);
});
test('first reconciliation joins presence and pulls missing photos without a peer broadcast', () => {
  const {ctx, root, calls} = context();
  root._ready = true;
  root.auth = {logged: true};
  Object.assign(root.doc, {
    header: {remoteCalicataId: 'remote'}, instanceId: 'local',
    originalPhotoUrl: slot => slot === 2 ? 'local.jpg' : '',
  });
  root._photoSyncState = slot => slot === 3 ? 'PENDING' : 'LOCAL';
  root._refreshRemoteLogos = () => calls.push('logos');
  ctx.docsCtl = {resourcesPath: '/resources'};
  ctx.CalicataCloud = {
    takeConfirmedMedia: () => [], bindMediaIdentity() {}, flushMedia() {},
    joinPresence: doc => { assert.equal(doc, root.doc); calls.push('presence'); },
    downloadRemotePhoto: (doc, slot) => calls.push('photo-' + slot),
    loadRemoteLogos: () => calls.push('logos'),
    loadActivity() {},
  };
  vm.runInContext('function reconcile() {' + blockAfter(form, 'function _reconcileMediaCloud(') + '}', ctx);
  ctx.reconcile();
  assert.deepEqual(calls, ['presence', 'photo-1', 'logos']);
  root.auth.logged = false;
  ctx.reconcile();
  assert.equal(calls.length, 3, 'wait for authentication, preserve pending/local photos');
});

const fs = require('node:fs');
const vm = require('node:vm');
const assert = require('node:assert/strict');
const path = require('node:path');
const base = path.resolve(__dirname, '../..');
const editor = fs.readFileSync(path.join(base, 'qml/Mobile/pages/CalicatasEditorPage.qml'), 'utf8');
const dock = fs.readFileSync(path.join(base, 'qml/Mobile/flowcore/GlobalContextDock.qml'), 'utf8');
function method(source, name) {
  const match = source.match(new RegExp('function ' + name + '\\([^]*?^    }', 'm'));
  assert.ok(match, name);
  return match[0];
}
const deferred = [];
// Arquitectura actual: la generación se difiere un frame con exportKickoff (Timer)
// y el progreso es la operación foreground (beginOperation/endOperation).
const form = { stageIndex: 5, reviewReady: true, reviewForExport: () => true, doc: {},
  exportExcelFlow: () => { throw Error('generator unavailable'); } };
const ended = [];
const root = { _publishingDocId: '', _exportPreparing: false, _exportFlowActive: false, exportBusy: false,
  leaving: false, _remoteLoadingDocId: '', currentTab: {tid: 1}, currentIndex: 0,
  currentDoc: {}, _syncDocsList() {}, _docAt: () => ({}), _syncFormIntoDoc() {},
  autoSaveCurrentM09: () => true, _docInstanceId: () => 'doc', _indexForTid: () => 0,
  beginOperation: () => 'op', phaseOperation() {}, _finishExcelExport() {},
  endOperation: (id, result) => { ended.push(result); }, showMsg() {} };
const exportKickoff = { task: null, restart() { deferred.push(() => { const t = this.task; this.task = null; if (t) t(); }); } };
const context = vm.createContext({root, formLoader: {item: form}, console, exportKickoff,
  Qt: { callLater: fn => deferred.push(fn) }});
vm.runInContext(method(editor, 'exportCurrentExcel'), context);
context.exportCurrentExcel('GOOGLE_DRIVE'); context.exportCurrentExcel('SUPABASE');
assert.equal(deferred.length, 1, 'two taps before deferred work must enqueue one generation');
deferred.shift()();
assert.equal(root._exportPreparing, false, 'generator exception releases guard');
assert.equal(root._exportFlowActive, false, 'generator exception releases the flow guard');
assert.deepEqual(ended, ['ERROR'], 'generator failure ends the operation with an error (no endless progress)');
context.exportCurrentExcel('GOOGLE_DRIVE');
assert.equal(deferred.length, 1, 'retry permitted after generation failure');
root.currentIndex = 1;
deferred.shift()();
assert.equal(root._exportPreparing, false, 'changed document releases guard');
assert.match(dock, /onMenuNodeChanged:\s*Qt.callLater\(validateMenu\)/,
  'menu validation must not mutate its dependency during binding evaluation');
assert.match(dock, /menuGeneration !== generation/, 'stale displayed branches cannot dispatch');
const leaf = {id: 'leaf', visible: true, enabled: true};
const nested = {id: 'nested', visible: true, enabled: true, children: [leaf]};
const parent = {id: 'parent', visible: true, enabled: true, children: [nested]};
let dispatched = 0;
const menu = vm.createContext({visibleActions: [parent], menuPath: [], generation: 4,
  menuGeneration: -1, menuAvailable: true, transitionPending: false, width: 400,
  flow: null, console: {info() {}}, Qt: {point: (x, y) => ({x, y})},
  router: {busy: false, dispatch() {dispatched++; return true;}}});
const resolver = dock.match(/readonly property var menuNode: (\{[^]*?^    \})/m)[1];
for (const name of ['visibleChildren', 'haptic', 'openMenu', 'pushMenu', 'popMenu',
                    'closeMenu', 'handleBack', 'activateMenuEntry', 'validateMenu'])
  vm.runInContext(method(dock, name), menu);
Object.defineProperties(menu, {
  menuNode: {get: () => vm.runInContext('(function() ' + resolver + ')()', menu)},
  menuEntries: {get: () => menu.menuNode ? menu.visibleChildren(menu.menuNode) : []},
  menuOpen: {get: () => menu.menuGeneration === menu.generation && menu.menuPath.length > 0 && !!menu.menuNode}
});
assert.equal(menu.openMenu('parent', null), true);
assert.equal(menu.menuEntries[0].id, 'nested');
menu.activateMenuEntry(nested);
assert.equal(menu.menuPath.length, 2);
assert.equal(menu.handleBack(), true);
assert.equal(menu.menuPath.length, 1, 'Back pops exactly one level');
menu.activateMenuEntry(nested);
menu.activateMenuEntry(leaf);
assert.equal(dispatched, 1);
assert.equal(menu.menuPath.length, 0, 'leaf dispatch closes branch');
menu.openMenu('parent', null);
menu.generation++;
menu.activateMenuEntry(leaf);
assert.equal(dispatched, 1, 'stale branch cannot dispatch in a new generation');
menu.validateMenu();
assert.equal(menu.menuPath.length, 0);
menu.openMenu('parent', null);
parent.children = [];
menu.validateMenu();
assert.equal(menu.menuPath.length, 0, 'removed children close the branch');
root.calicataBranch = () => [];
root.statusLabel = s => s;
root.contextStatus = 'BORRADOR';
root.hasOpenDocument = true;
// Helpers reales del EditorPage que buildContextActions usa hoy (Laboratorio/Fotos con submenú).
root.formValue = (f, name) => f ? f[name] : undefined;
root.labContextAction = () => ({id: 'lab'});
root.photoContextAction = () => ({id: 'photos'});
vm.runInContext(method(editor, 'buildContextActions'), context);
const counts = [0,1,2,3,4,5].map(stage => context.buildContextActions(stage, false, true).length);
// Laboratorio (etapa 3) tiene hoy su propia acción contextual, igual que Fotos (etapa 4).
assert.deepEqual(counts, [4,5,5,5,5,5]);
assert.ok(context.buildContextActions(3, false, true).some(a => a.id === 'lab'), 'Laboratorio expone su acción');
assert.ok(context.buildContextActions(4, false, true).some(a => a.id === 'photos'), 'Fotos expone su acción');
assert.ok(context.buildContextActions(5, false, true).some(a => a.id === 'export'), 'Revisión conserva Exportar en el Dock');
for (let stage = 0; stage < 6; stage++) {
  const actions = context.buildContextActions(stage, true, true);
  assert.ok(actions.length >= 3 && actions.length <= 6);
}
console.log('P6 dock/export regression checks passed (JS/static; no Qt runtime).');

const fs = require('node:fs');
const vm = require('node:vm');
const assert = require('node:assert/strict');
const path = require('node:path');
const base = path.resolve(__dirname, '../..');
const editor = fs.readFileSync(path.join(base, 'qml/Mobile/pages/CalicatasEditorPage.qml'), 'utf8');
const mainQml = fs.readFileSync(path.join(base, 'qml/Mobile/Main.qml'), 'utf8').replace(/\r\n/g, '\n');
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
// Barra de acciones + menú jerárquico (sustituyen al Dock): mismas reglas de
// toque, submenús por niveles, generación vigente y enabled === true.
const fnSrc = (name, indent) => {
  const re = new RegExp('\\n' + indent + 'function ' + name + '\\([^)]*\\) \\{(?:[^\\n]*\\}\\n|[^]*?\\n' + indent + '\\}\\n)');
  const m = mainQml.match(re);
  assert.ok(m, name);
  return m[0];
};
const dispatchedIds = [];
const bar = vm.createContext({});
for (const name of ['visibleOf', 'hasCommand', 'hasChildren', 'tapKind']) vm.runInContext(fnSrc(name, '        '), bar);
const leaf = {id: 'leaf', command: 'leaf', visible: true, enabled: true};
const hidden = {id: 'hidden', command: 'hidden', visible: false, enabled: true};
const nested = {id: 'nested', visible: true, enabled: true, children: [leaf, hidden]};
const parent = {id: 'parent', visible: true, enabled: true, children: [nested]};
const direct = {id: 'direct', command: 'direct', visible: true, enabled: true};
assert.equal(bar.tapKind(direct), 'dispatch');
assert.equal(bar.tapKind(parent), 'menu');
assert.equal(bar.tapKind({id: 'off', command: 'off', enabled: false}), 'none', 'disabled actions do nothing');
assert.equal(bar.tapKind({id: 'empty', enabled: true, children: [hidden]}), 'none', 'hidden children do not open a menu');
const menu = vm.createContext({path: [], generation: 4, closed: 0,
  bareNavBarV1: bar, dockContextController: {generation: 4},
  dockCommandRouter: {dispatch(id, gen) { dispatchedIds.push(id + '@' + gen); return true; }}});
menu.close = () => { menu.closed++; menu.path = []; };
vm.runInContext(fnSrc('back', '        '), menu);
vm.runInContext(fnSrc('activate', '        '), menu);
menu.path = [parent];
menu.activate(nested);
assert.equal(menu.path.length, 2, 'entry with children opens the next level');
menu.back();
assert.equal(menu.path.length, 1, 'Back pops exactly one level');
menu.activate(nested);
menu.activate(leaf);
assert.deepEqual(dispatchedIds, ['leaf@4'], 'leaf dispatches with the menu generation');
assert.equal(menu.closed, 1, 'leaf dispatch closes the menu');
menu.path = [parent, nested];
menu.dockContextController.generation = 5;
menu.activate(leaf);
assert.equal(dispatchedIds.length, 1, 'stale generation cannot dispatch');
menu.path = [parent];
menu.back();
assert.equal(menu.closed, 3, 'Back on the first level closes the menu');
assert.ok(mainQml.includes('if (actionMenuV1.visible) {\n        actionMenuV1.back()'), 'Android Back walks the menu');
assert.ok(mainQml.includes('dockCommandRouter.dispatch(String(modelData.id), dockContextController.generation)'), 'bar dispatches through the router');
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

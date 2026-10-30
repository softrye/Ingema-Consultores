'use strict'
// Contratos de la ruta activa y ejecución de funciones QML con datos sintéticos.
// Sin compilación, dispositivo, red ni datos de usuario.
const fs = require('fs')
const path = require('path')
const vm = require('vm')
const assert = require('assert')
const read = name => fs.readFileSync(path.join(__dirname, '../../qml/Mobile/renditions/', name), 'utf8')
const detail = read('RenditionDetail.qml'), list = read('RenditionExpenses.qml')
const quick = read('RExpenseQuickForm.qml'), app = read('RenditionsApp.qml')
let failures = 0, passed = 0
function check(name, fn) { try { fn(); passed++; console.log('PASS ' + name) } catch (e) { failures++; console.error('FAIL ' + name + ': ' + e.message) } }
function fn(name) {
  const start = quick.indexOf('    function ' + name + '(')
  assert(start >= 0, 'falta función ' + name)
  const next = quick.indexOf('\n    function ', start + 1)
  return quick.slice(start, next < 0 ? quick.length : next).trim()
}
check('abrir rendición muestra Gastos y elimina la vista Declarado/Validado', () => {
  assert(detail.includes('property string tab: "expenses"'))
  assert(!detail.includes('text: "Declarado"'))
  assert(app.includes('stack.push(detailComponent, { localId: localId'))
  assert(detail.includes('RenditionExpenses {'))
})
check('lista activa ofrece icono y una única instancia expandida', () => {
  assert.strictEqual((list.match(/RExpenseQuickForm\s*\{/g) || []).length, 1)
  assert(list.includes('expenseIcon'))
  assert(list.includes('interactive: !tab.app.modalOpen'))
})
check('UI04 está en el formulario rápido activo con catálogo real', () => {
  for (const id of ['quickSupportTypes', 'quickPaymentMethods', 'supportNumberField', 'rucField', 'paymentDetailField']) assert(quick.includes(id), id)
  assert(quick.includes('form.options("SUPPORT_TYPE")'))
  assert(quick.includes('form.options("PAYMENT_METHOD")'))
  assert(!quick.includes('label: "Fecha de pago"'), 'no inventar campos sin contrato')
})
check('Información no añade diagnósticos ni sugerencias', () => {
  const panel = app.slice(app.indexOf('id: infoPanel'), app.indexOf('id: activityPanel'))
  assert(!panel.includes('Estado de Rendiciones'))
  assert(!panel.includes('suggestions'))
  assert(panel.includes('columns: 2'))
})
check('una publicación de rowVersion no recarga el formulario', () => {
  const identity = quick.match(/readonly property string expenseKey:[^\n]+/)[0]
  assert(!identity.includes('rowVersion'))
  assert(quick.includes('baseRowVersion'))
})
check('sustentos confirmados se retiran por identidad aunque cambie la cola', () => {
  const a = {localUri:'content://a'}, b = {localUri:'content://b'}
  let callback
  const context = {pending:[a], saving:true, form:null, persistLocal:() => {}, attachFile:(_id, _file, cb) => { callback = cb }}
  context.form = context; context.life = {alive:true}
  vm.runInNewContext(fn('attachPending'), context)
  let done = false
  context.attachPending('expense', () => { done = true })
  context.pending = [b, a]
  callback(true)
  assert.deepStrictEqual(context.pending.map(p => p.localUri), ['content://b'])
  assert(!done, 'no cerrar mientras queda otro sustento')
})
check('guardar conserva cambios escritos en vuelo y la identidad confirmada', () => {
  assert(quick.includes('form.editRevision !== revision'))
  assert(quick.includes('form.savedId = localId'))
  assert(quick.includes('expenseLocalId: savedId ||'))
  assert(quick.includes('args.expectedExpenseRowVersion = baseRowVersion'))
  assert(!quick.includes('onActivated: { form.load(); form.finished(false) }'))
})
function saveHarness() {
  const calls = [], finished = []
  const context = {
    saving:false, writable:true, rendition:{}, expense:null, savedId:'', renditionLocalId:'rendition', busyKey:'quick', baseRowVersion:0,
    editRevision:1, error:'', isNew:true, autosave:{stop(){}}, persistLocal(){}, values:() => ({amount:'10.00'}),
    ctl:{amountError:() => '', expenseError:() => ''}, life:{alive:true}, attachPending:(_id, done) => done(),
    app:{st:{expenses:[{localId:'expense',rowVersion:7}]}, errorText:(_code,msg) => msg, toast(){},
      call:(operation,args,key,done) => { calls.push({operation,args,done}); return 'request' }},
    finished:saved => finished.push(saved)
  }
  context.form = context
  vm.runInNewContext(fn('save'), context)
  return {context,calls,finished}
}
check('una respuesta antigua no cierra ni acredita texto escrito en vuelo (QML ejecutado)', () => {
  const {context,calls,finished} = saveHarness()
  context.save()
  context.editRevision++
  calls[0].done(true,{localId:'expense'},'', '')
  assert.strictEqual(context.savedId,'expense')
  assert.strictEqual(context.baseRowVersion,7)
  assert.strictEqual(context.saving,false)
  assert.strictEqual(finished.length,0)
  context.save()
  assert.strictEqual(calls[1].args.expenseLocalId,'expense', 'reintento debe editar la misma fila')
  assert.strictEqual(calls[1].args.expectedExpenseRowVersion,7)
})
check('un adjunto fallido conserva el id para reintentar sin crear otro gasto (QML ejecutado)', () => {
  const {context,calls,finished} = saveHarness()
  context.attachPending = () => { context.saving = false }
  context.save(); calls[0].done(true,{localId:'expense'},'', '')
  assert.strictEqual(finished.length,0)
  context.save()
  assert.strictEqual(calls[1].args.expenseLocalId,'expense')
})
check('CAS usa la versión abierta, incluso si se publica una versión posterior (QML ejecutado)', () => {
  const {context,calls} = saveHarness()
  context.expense = {localId:'expense',rowVersion:8}
  context.baseRowVersion = 3
  context.save()
  assert.strictEqual(calls[0].args.expectedExpenseRowVersion,3)
})
check('el cierre tras guardar no restaura el gasto anterior como Nuevo', () => {
  assert(quick.includes('completedSave ||'))
  assert(quick.includes('form.completedSave = true'))
  assert(app.includes('if (saved) quickExpenseForm.load(true)'))
})
check('el editor rápido comparte borrador y conserva subtotal e IGV del completo', () => {
  assert(quick.includes('readonly property string draftKey: "expense:"'))
  assert(quick.includes('draft.subtotal === undefined ? preservedValues.subtotal : draft.subtotal'))
  assert(quick.includes('draft.igv === undefined ? preservedValues.igv : draft.igv'))
  assert(quick.includes('suspendedForAdvanced'))
})
check('los céntimos se entregan al cálculo C++ sin conversión decimal flotante', () => {
  const start = list.indexOf('    function decimalCents(')
  const end = list.indexOf('\n    }', start + 1) + 6
  const context = {}
  vm.runInNewContext(list.slice(start, end).trim(), context)
  assert.strictEqual(context.decimalCents(1),'0.01')
  assert.strictEqual(context.decimalCents(0),'0.00')
  assert.strictEqual(context.decimalCents(9007199254740991),'90071992547409.91')
  assert.strictEqual(context.decimalCents(-105),'-1.05')
})
check('las vistas previas convierten rutas locales a URL y conservan content://', () => {
  const context = {}
  vm.runInNewContext(fn('localUrl'), context)
  assert.strictEqual(context.localUrl('/data/receipt.jpg'),'file:///data/receipt.jpg')
  assert.strictEqual(context.localUrl('C:\\receipts\\a.jpg'),'file:///C:/receipts/a.jpg')
  assert.strictEqual(context.localUrl('content://receipt/a'),'content://receipt/a')
})
check('un adjunto READY sigue visible hasta que aparece su propia fila remota', () => {
  const start = quick.indexOf('readonly property var files: {')
  const block = quick.slice(quick.indexOf('{',start), quick.indexOf('    function sizeText(',start)).trim()
  const context = {
    attachmentExpense:{remoteId:'expense-remote',attachments:[{remoteId:'new',phase:'READY',fileName:'new.jpg',localUri:'/new.jpg'}]},
    pending:[], app:{st:{attachments:[{id:'old',expense_id:'expense-remote',file_name:'old.jpg'}]}},
    S:{text_:(row,a,b) => String(row[a] || (b ? row[b] : '') || '')}
  }
  vm.runInNewContext('function fileRows() ' + block, context)
  assert.strictEqual(context.fileRows().length,2)
  context.app.st.attachments.push({id:'new',expense_id:'expense-remote',file_name:'new.jpg'})
  const rows = context.fileRows()
  assert.strictEqual(rows.length,2, 'sin duplicar la copia local cuando llega su fila remota')
  assert.strictEqual(rows[1].uri,'/new.jpg', 'la miniatura conserva el mirror local')
})
console.log(`ACTIVE_UI_STATIC ${passed} passed, ${failures} failed`)
process.exitCode = failures ? 1 : 0

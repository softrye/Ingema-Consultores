// Paridad Web PR #11 (ADR-023/052) en el editor de gastos Android: un guardado
// sólo acredita la instantánea que envió. Comprueba el archivo REAL
// (qml/Mobile/renditions/ExpenseEditor.qml) y reproduce en JS las tres reglas
// con datos sintéticos. Sin red, sin Supabase y sin compilar.
//   node tests/renditions/expense_editor_checkpoint_static.cjs
'use strict'
const fs = require('fs')
const path = require('path')
const assert = require('assert')

const src = fs.readFileSync(path.resolve(__dirname, '../../qml/Mobile/renditions/ExpenseEditor.qml'), 'utf8')
let n = 0
function check(name, fn) { fn(); n++; console.log('PASS ' + name) }

check('cada edición avanza la revisión', () => {
  assert(/property int editRevision: 0/.test(src))
  assert(/if \(applying\) return\s+editRevision\+\+/.test(src), 'changed() debe incrementar editRevision')
})
check('«Borrador guardado» sólo si no hubo cambios durante el guardado local', () => {
  assert(/var revision = editRevision\s+app\.call\("saveEditorDraft"/.test(src))
  assert(/page\.editRevision === revision\) page\.localSaved = true/.test(src))
  // Simulación: escribir mientras el guardado está en curso.
  const page = { editRevision: 0, localSaved: false }
  const revision = page.editRevision            // persistLocal()
  page.editRevision++                           // el usuario escribe
  if (page.editRevision === revision) page.localSaved = true   // respuesta OK
  assert.strictEqual(page.localSaved, false, 'no debe acreditar texto escrito en vuelo')
})
check('el borrador explícito sólo retira los sustentos que envió', () => {
  assert(/var sentUris = explicitSave === true \? pending\.map\(function\(a\) \{ return a\.localUri \}\) : \[\]/.test(src))
  assert(/page\.pending = page\.pending\.filter\(function\(a\) \{ return sentUris\.indexOf\(a\.localUri\) < 0 \}\)/.test(src))
  assert(!/if \(explicitSave === true\) page\.pending = \[\]/.test(src), 'vaciar todo perdería adjuntos añadidos en vuelo')
  let pending = [{ localUri: 'content://qa/a.jpg' }]
  const sentUris = pending.map(a => a.localUri)
  pending = pending.concat([{ localUri: 'content://qa/b.pdf' }])      // añadido durante el guardado
  pending = pending.filter(a => sentUris.indexOf(a.localUri) < 0)
  assert.deepStrictEqual(pending.map(a => a.localUri), ['content://qa/b.pdf'])
})
check('un sustento confirmado se retira por su identidad, no por posición', () => {
  assert(/page\.pending = page\.pending\.filter\(function\(p\) \{ return p\.localUri !== a\.localUri \}\)/.test(src))
  assert(!/var done = list\.shift\(\)/.test(src))
})
check('sin cambios en contratos financieros (mismas llamadas del bridge)', () => {
  for (const op of ['"saveExpense"', '"attachSupport"', '"saveWorking"', '"promoteWorking"', '"saveEditorDraft"'])
    assert(src.includes('app.call(' + op), 'falta ' + op)
  assert(/args\.expectedExpenseRowVersion = Number\(expense\.rowVersion \|\| 0\)/.test(src), 'CAS de gasto')
  assert(/clientIntentId: intentId \+ ":" \+ a\.localUri/.test(src), 'idempotencia de adjuntos')
})
console.log('EXPENSE_EDITOR_CHECKPOINT_OK ' + n)

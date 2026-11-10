'use strict'
// Executes the production QML action guards with synthetic rows; no backend/device.
const fs = require('fs')
const path = require('path')
const vm = require('vm')
const assert = require('node:assert/strict')
const { test } = require('node:test')
const source = fs.readFileSync(path.join(__dirname, '../../qml/Mobile/renditions/RenditionExpenses.qml'), 'utf8')
function harness() {
  const calls = []
  const tab = {
    selectedDraftId: 'b', selectedDraftRenditionId: 'rendition',
    detail: { localId: 'rendition', selected: true, writable: true },
    drafts: [{ id: 'a' }, { id: 'b', expenseLocalId: 'expense-b', form: { concept: 'Original' } }],
    app: { busy: () => false, openExpense: (...args) => calls.push(['continue', ...args]) },
    promote: row => calls.push(['promote', row]), discard: row => calls.push(['discard', row])
  }
  const context = vm.createContext({ tab, draftMenu: { close: () => calls.push(['close']) } })
  for (const name of ['currentDraft', 'draftActionAllowed', 'runDraftAction']) {
    const start = source.indexOf('    function ' + name + '(')
    assert(start >= 0, 'Missing production behavior: ' + name)
    const end = source.indexOf('\n    }', start) + 6
    vm.runInContext(source.slice(start, end), context)
    tab[name] = context[name]
  }
  return { tab, calls }
}
test('continue uses the selected working identity, even after a reorder', () => {
  const { tab, calls } = harness()
  tab.drafts.reverse()
  tab.runDraftAction('Continuar')
  assert.deepEqual(calls, [['close'], ['continue', 'rendition', 'expense-b', 'b']])
})
test('register and discard use the current row after synchronization', () => {
  for (const [action, operation] of [['Registrar', 'promote'], ['Descartar', 'discard']]) {
    const { tab, calls } = harness()
    const fresh = { id: 'b', form: { concept: 'Updated' }, row_version: 8 }
    tab.drafts = [fresh]
    tab.runDraftAction(action)
    assert.equal(calls[1][0], operation)
    assert.equal(calls[1][1], fresh)
  }
})
test('conflicts, permissions, pending operations and busy rows prevent all ordinary actions', () => {
  for (const action of ['Continuar', 'Registrar', 'Descartar']) {
    for (const block of [
      h => { h.tab.detail.writable = false },
      h => { h.tab.drafts[1].syncState = 'CONFLICT' },
      h => { h.tab.drafts[1].promoteRequested = true },
      h => { h.tab.drafts[1].archiveRequested = true },
      h => { h.tab.app.busy = key => key === 'working:b' },
      h => { h.tab.drafts = [] },
      h => { h.tab.detail.localId = 'other' },
      h => { h.tab.detail.selected = false }
    ]) {
      const h = harness(); block(h); h.tab.runDraftAction(action)
      assert.equal(h.calls.length, 0, action)
    }
  }
})
test('missing sources block register while preserving recovery and safe discard', () => {
  const { tab, calls } = harness()
  tab.drafts[1].missingSources = 1
  tab.runDraftAction('Registrar')
  assert.equal(calls.length, 0)
  assert.equal(tab.draftActionAllowed(tab.currentDraft(), 'Continuar'), true)
  assert.equal(tab.draftActionAllowed(tab.currentDraft(), 'Descartar'), true)
  assert.equal(tab.draftActionAllowed(tab.currentDraft(), 'unknown'), false)
})

'use strict'
// Execute the production QML function; the RPC boundary supplies server responses.
const fs = require('node:fs')
const path = require('node:path')
const vm = require('node:vm')
const assert = require('node:assert/strict')
const { test } = require('node:test')
const source = fs.readFileSync(path.join(__dirname, '../../qml/Mobile/renditions/FilesBrowser.qml'), 'utf8')
const start = source.indexOf('    function displayName(')
const end = source.indexOf('\n    }', start) + 6
function harness(archive, response = {}) {
  const page = { displayNames: {}, life: { alive: true } }
  const calls = []
  const app = { call: (...args) => calls.push(args) }
  const context = vm.createContext({ page, displayNames: page.displayNames, archive, app })
  vm.runInContext(source.slice(start, end), context)
  return { page, calls, name: context.displayName, reply: () => calls[0][3](true, { rows: [response] }) }
}
for (const archive of [true, false]) {
  test(`${archive ? 'archive' : 'trash'} prefers the rendition display_name from the listing`, () => {
    const h = harness(archive)
    h.page.displayNames.rend = 'Outdated name'
    assert.equal(h.name({ id: 'rend', kind: 'SMART_DOCUMENT', name: 'RDC-2026-000037.rend', display_name: 'Viáticos – Lima' }), 'Viáticos – Lima')
    assert.equal(h.calls.length, 0)
  })
  test(`${archive ? 'archive' : 'trash'} keeps ordinary file and folder names`, () => {
    const h = harness(archive)
    for (const kind of ['FOLDER', 'BINARY_DOCUMENT'])
      assert.equal(h.name({ id: kind, kind, name: 'Informe.rend' }), 'Informe.rend')
  })
}
test('archive context resolves the rendition display_name when the listing lacks it', () => {
  const h = harness(true, { name: 'RDC-2026-000037.rend', display_name: 'Gastos de campo' })
  h.name({ id: 'rend', kind: 'SMART_DOCUMENT', name: 'RDC-2026-000037.rend' })
  h.reply()
  assert.equal(h.page.displayNames.rend, 'Gastos de campo')
})
test('archive retains the node name for a context without display_name', () => {
  const h = harness(true, { name: 'Calicata antigua' })
  h.name({ id: 'calicata', kind: 'SMART_DOCUMENT', name: 'Calicata antigua' })
  h.reply()
  assert.equal(h.page.displayNames.calicata, 'Calicata antigua')
})
test('trash keeps the legacy label if display_name is empty or absent', () => {
  for (const display_name of [undefined, null, '']) {
    const h = harness(false)
    assert.equal(h.name({ id: 'rend', kind: 'SMART_DOCUMENT', name: 'RDC-2026-000037.rend', display_name }), 'RDC-2026-000037')
  }
})

'use strict'
// Execute the production QML readiness bindings. A hidden texture producer
// must be exposed to its shader before the first scheduled capture completes.
const { test } = require('node:test')
const assert = require('node:assert/strict')
const fs = require('node:fs')
const path = require('node:path')
const vm = require('node:vm')
const read = p => fs.readFileSync(path.join(__dirname, '../..', p), 'utf8').replace(/\r\n/g, '\n')
const home = read('qml/Mobile/HomeScreen.qml')
const renditions = read('qml/Mobile/renditions/RenditionsApp.qml')
function binding(source, declaration, scope) {
  const line = source.split(/\r?\n/).find(line => line.trim().startsWith(declaration))
  assert(line, 'missing production binding: ' + declaration)
  return vm.runInNewContext(line.trim().slice(declaration.length).trim(), scope)
}
function dock(source) {
  const capture = { sourceItem: source, width: 720, height: 400, textureReady: false }
  const ready = binding(home, 'readonly property bool dockBackdropReady:', {
    dockBackdropSource: source, dockBackdropCapture: capture
  })
  return { ready, texture: binding(home.slice(home.indexOf('        id: dockBackdrop\n')), 'readonly property var glassTexture:', {
    home: { dockBackdropReady: ready }, dockBackdropCapture: capture
  }), capture }
}
test('Home Dock exposes the existing producer before its first frame completes', () => {
  const result = dock({ width: 720, height: 1524 })
  assert.equal(result.ready, true)
  assert.equal(result.texture, result.capture)
})
test('Dock rejects a missing or empty backdrop', () => {
  for (const source of [null, {width: 0, height: 1524}, {width: 720, height: 0}]) {
    assert.equal(dock(source).ready, false)
    assert.equal(dock(source).texture, null)
  }
})
test('Rendiciones exposes a valid producer without waiting for its own consumer', () => {
  const scope = { shell: {cardGlassLive: false, visible: false, ui: {liquidGlass:true}}, backdropCapture: {
    sourceItem: {}, width: 720, height: 1524, textureReady: false
  }}
  assert.equal(binding(renditions, 'readonly property bool glassReady:', scope), true)
  scope.backdropCapture.sourceItem = null
  assert.equal(binding(renditions, 'readonly property bool glassReady:', scope), false)
})

'use strict'
const {test} = require('node:test')
const assert = require('node:assert/strict')
const fs = require('node:fs')
const path = require('node:path')
const vm = require('node:vm')
const read = p => fs.readFileSync(path.join(__dirname, '../..', p), 'utf8')
const field = read('qml/Mobile/renditions/RField.qml')
function body(source, marker) {
  const at = source.indexOf(marker)
  assert(at >= 0, marker)
  const start = source.indexOf('{', at)
  let depth = 1, end = start + 1
  while (depth && end < source.length) {
    if (source[end] === '{') ++depth
    if (source[end] === '}') --depth
    ++end
  }
  assert.equal(depth, 0)
  return source.slice(start + 1, end - 1)
}
test('Next changes editor/hints without hiding and reopening the IME', () => {
  let focused = 0, hidden = 0, queued = 0, updated = 0
  const next = {visible:true, enabled:true, readOnly:false, cursorPosition:0, inputMethodHints:0,
    forceActiveFocus() {++focused}}
  const input = {focus:true, inputMethodHints:1, nextItemInFocusChain() {return next}}
  const scope = {input, reshowKeyboard:{restart(){++queued}}, Qt:{ImQueryInput:1, ImHints:2,
    inputMethod:{hide(){++hidden}, update(queries){updated = queries}}}}
  vm.runInNewContext('(function(){' + body(field, 'onAccepted:') + '})()', scope)
  assert.equal(focused, 1)
  assert.equal(hidden, 0)
  assert.equal(queued, 0)
  assert.equal(updated & scope.Qt.ImHints, scope.Qt.ImHints)
})
test('field reveal enters the existing CoreFlow queue instead of starting competing scrolls', () => {
  let queued = 0, immediate = 0
  const flick = {contentY:0, flicking:false, contentItem:{}, __queueEnsure(){++queued},
    ensureActiveFocusVisible(){++immediate}}
  const scope = {field:{parent:flick}}
  vm.runInNewContext('(function(){'+body(field, 'function reveal()')+'})()', scope)
  assert.equal(queued, 1)
  assert.equal(immediate, 0)
})
test('the real Main window binds its resized height to the one CoreFlow viewport', () => {
  const main = read('qml/Mobile/Main.qml')
  const binding = body(main, 'Binding {')
  assert.match(binding, /target:\s*CoreFlowModule\.InGeCoreFlow/)
  assert.match(binding, /property:\s*"imeViewportHeight"/)
  assert.match(binding, /value:\s*root\.height/)
})
test('the expense modal samples one frozen backdrop while keeping its original blur', () => {
  const source = read('qml/Mobile/renditions/RenditionExpenses.qml')
  const overlay = body(source, 'Overlay.modal: Item')
  assert.match(overlay, /id:\s*editorBackdrop/)
  assert.match(overlay, /sourceItem:\s*editorPopup\.visible\s*\?\s*tab\.app\s*:\s*null/)
  assert.match(overlay, /live:\s*false/)
  assert.match(overlay, /source:\s*visible\s*\?\s*editorBackdrop\s*:\s*null/)
  assert.match(overlay, /blurEnabled:\s*true;\s*blurMax:\s*48;\s*blur:\s*0\.8/)
  assert.doesNotMatch(overlay, /\bsource:\s*tab\.app\b/)
  const scroll = body(source, 'FlowCore.ImeAwareFlickable {')
  assert.match(scroll, /restoreOnImeClose:\s*false/)
  assert.match(scroll, /imeTopMargin:\s*stickyTabs\.visible/)
})

'use strict'
const { test } = require('node:test')
const assert = require('node:assert/strict')
const fs = require('node:fs')
const path = require('node:path')
const vm = require('node:vm')

const home = fs.readFileSync(path.join(__dirname, '../../qml/Mobile/HomeScreen.qml'), 'utf8')
const app = fs.readFileSync(path.join(__dirname, '../../qml/Mobile/renditions/RenditionsApp.qml'), 'utf8')
const fnStart = home.indexOf('    function dockDispatch(')
const fnEnd = home.indexOf('    function dockUnavailable(', fnStart)
assert(fnStart >= 0 && fnEnd > fnStart, 'dockDispatch must exist')
const fn = home.slice(fnStart, fnEnd)

function fixture(options = {}) {
  const calls = [], notices = []
  const current = { id: 'renditions.new', command: 'renditions.quickExpense', enabled: true }
  const state = {
    dockCtx: { ownerId: 'rendiciones', contextId: 'rendiciones/detail', transitionPending: false },
    page: 'rendiciones',
    renditionsLoader: { item: { detailPage: { localId: 'r1' } } },
    dockActiveDetailId: () => state.renditionsLoader.item.detailPage.localId,
    dockGeneration: 12,
    dockActions: [current],
    dockRouter: {
      dispatch(id, generation) {
        calls.push({ id, generation })
        return generation === state.dockGeneration
      }
    },
    dockHaptic() {},
    notify(message) { notices.push(message) },
    console: { warn() {} },
    ...options
  }
  vm.createContext(state)
  vm.runInContext(fn, state)
  const tapped = { ...current, tapCommand: true }
  return { state, calls, notices, tapped }
}

test('revalidates only the same enabled tapCommand when the detail snapshot updates mid-tap', () => {
  const f = fixture()
  f.state.dockDispatch(f.tapped, 11, 'rendiciones', 'rendiciones/detail', 'r1')
  assert.equal(f.calls.length, 1)
  assert.equal(f.calls[0].id, 'renditions.new')
  assert.equal(f.calls[0].generation, 12)
  assert.equal(f.notices.length, 0)
})

test('does not resurrect a tap after a page or owner change', () => {
  for (const property of ['ownerId', 'contextId']) {
    const f = fixture()
    f.state.dockCtx[property] = 'another-page'
    f.state.dockDispatch(f.tapped, 11, 'rendiciones', 'rendiciones/detail', 'r1')
    assert.equal(f.calls[0].generation, 11)
  }
})

test('does not bypass disabled or repurposed actions or pending transitions', () => {
  for (const changed of [
    { dockActions: [{ id: 'renditions.new', command: 'renditions.quickExpense', enabled: false }] },
    { dockActions: [{ id: 'renditions.new', command: 'another-command', enabled: true }] },
    { dockCtx: { ownerId: 'rendiciones', contextId: 'rendiciones/detail', transitionPending: true } }
  ]) {
    const f = fixture(changed)
    f.state.dockDispatch(f.tapped, 11, 'rendiciones', 'rendiciones/detail', 'r1')
    assert.equal(f.calls[0].generation, 11)
  }
})

test('a quick tap cannot carry over to another rendition with the same dock context', () => {
  const f = fixture({ renditionsLoader: { item: { detailPage: { localId: 'r2' } } } })
  f.state.dockDispatch(f.tapped, 11, 'rendiciones', 'rendiciones/detail', 'r1')
  assert.equal(f.calls[0].generation, 11)
})

test('ordinary taps and Deep Press are not granted a new generation', () => {
  const f = fixture()
  f.state.dockDispatch({ ...f.tapped, tapCommand: false }, 11, 'rendiciones', 'rendiciones/detail', 'r1')
  assert.equal(f.calls[0].generation, 11)
  assert.match(home, /onPressAndHold:\s*function\(\)\s*\{[\s\S]*?home\.dockSlotHold\(modelData, pressGeneration, dockCell\)/)
  assert.match(home, /onClicked:\s*home\.dockSlotTap\(modelData, pressGeneration, dockCell, pressOwner, pressContext, pressDetailId\)/)
})

test('a press does not rebind the dock Repeater model before onClicked', () => {
  assert.match(home, /property var dockDisplayedSlots: \[\]/)
  assert.match(home, /Component\.onCompleted: \{ dockDisplayedSlots = dockSlots;/)
  assert.doesNotMatch(home, /property var dockDisplayedSlots: dockSlots/)
  assert.match(home, /onDockSlotsChanged: if \(!dockPressActive\) dockDisplayedSlots = dockSlots/)
  assert.match(home, /onDockPressActiveChanged: if \(!dockPressActive\) dockDisplayedSlots = dockSlots/)
  assert.match(home, /model: home\.dockDisplayedSlots/)
  assert.doesNotMatch(home, /dockPressSnapshot/)
  assert.match(home, /onPressed:[\s\S]*?home\.dockPressActive = true/)
  assert.match(home, /onReleased:[\s\S]*?Qt\.callLater\(home\.dockFinishPress\)/)
  assert.match(home, /onCanceled:[\s\S]*?home\.dockFinishPress\(\)/)
})

test('dock context refresh waits until after the gesture has finished', () => {
  const update = home.match(/onDockSlotsChanged: (if \(!dockPressActive\) dockDisplayedSlots = dockSlots)/)
  const release = home.match(/onDockPressActiveChanged: (if \(!dockPressActive\) dockDisplayedSlots = dockSlots)/)
  assert.ok(update && release, 'handlers must hold refreshes during the press')
  const initial = [{ key: 'renditions.new', command: 'renditions.quickExpense' }]
  const changed = [{ key: 'renditions.new', command: 'renditions.quickExpense', enabled: true }]
  const state = { dockSlots: changed, dockDisplayedSlots: initial, dockPressActive: true }
  vm.createContext(state)
  vm.runInContext(update[1], state)
  assert.strictEqual(state.dockDisplayedSlots, initial, 'press should not destroy its MouseArea')
  state.dockPressActive = false
  vm.runInContext(release[1], state)
  assert.strictEqual(state.dockDisplayedSlots, changed, 'release must flush the new context')
})

test('renditions.new remains mapped to the same quick editor', () => {
  assert.match(app, /id:\s*"renditions\.new"[\s\S]*?tapCommand:\s*true/)
  assert.match(app, /name === "renditions\.quickExpense"[\s\S]*?expensesTab\.createExpense\(\)/)
})

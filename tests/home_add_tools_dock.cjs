'use strict'
const {test} = require('node:test')
const assert = require('node:assert/strict')
const fs = require('node:fs')
const vm = require('node:vm')
const path = require('node:path')
const source = fs.readFileSync(path.join(__dirname,'../qml/Mobile/HomeScreen.qml'),'utf8')
const preset = vm.runInNewContext('(' + source.match(/homeDockPreset:\s*(\[[\s\S]*?\n    \])/)[1] + ')')
const tap = source.slice(source.indexOf('    function dockSlotTap('),source.indexOf('    function dockSlotHold('))
test('Agregar herramientas is offered by the Dock without a duplicate Home tile',()=>{
  assert.doesNotMatch(source,/Tile\s*\{[^\n]*addStyle:\s*true[^\n]*onActivated:\s*home\.openAdd\(\)/)
})
test('Home Dock includes Inicio, Agregar herramientas and Ajustes',()=>{
  assert.deepEqual(Array.from(preset,s=>s.key),['home','addTools','settings'])
  assert.equal(preset[1].name,'Agregar herramientas')
  assert.equal(preset[1].glyph,0xE173)
})
test('Agregar opens the existing panel without navigating; edit mode consumes the tap',()=>{
  for(const editing of [false,true]) {
    let opened=0,navigated=0
    const scope={consumeEditTap:()=>editing,openAdd:()=>++opened,navigate:()=>++navigated}
    vm.createContext(scope); vm.runInContext(tap,scope)
    scope.dockSlotTap(preset.find(s=>s.key==='addTools') || {},0,null,'','','')
    assert.equal(opened,editing?0:1)
    assert.equal(navigated,0)
  }
})

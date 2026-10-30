'use strict'
const fs = require('node:fs')
const vm = require('node:vm')
const path = require('node:path')
const assert = require('node:assert/strict')
const { test } = require('node:test')
const source = fs.readFileSync(path.join(__dirname, '../../qml/Mobile/renditions/RExpenseQuickForm.qml'), 'utf8')
function harness() {
  const sent = [], finished = []
  let confirm
  const form = {
    ready:true, completedSave:false, renditionLocalId:'r', dirty:true, saving:false,
    modalEditor:true, editRevision:3, savedId:'', pending:[], intentId:'intent', baseRowVersion:7,
    draftKey:'expense:r:e', life:{alive:true}, values:() => ({concept:'Unsaved', amount:'12.80'}),
    app:{call:(op,args,key,callback) => sent.push({op,args,callback}),
      confirm:(_title,_text,_label,_danger,callback) => { confirm=callback }, errorText:()=>'Local write failed'},
    finished:saved => finished.push(saved)
  }
  const context = vm.createContext({...form, imagePreview:{opened:false}, autosave:{stop(){}}})
  context.form=context
  for (const name of ['persistLocal','requestClose']) {
    const start=source.indexOf('    function '+name+'('), end=source.indexOf('\n    }',start)+6
    vm.runInContext(source.slice(start,end),context)
  }
  return {form:context,sent,finished,accept:()=>confirm()}
}
test('dirty close waits for confirmation and acknowledged durable local storage',()=>{
  const h=harness(); h.form.requestClose()
  assert.equal(h.sent.length,0); assert.equal(h.finished.length,0)
  h.accept()
  assert.equal(h.sent[0].op,'saveEditorDraft')
  assert.equal(h.sent[0].args.key,'expense:r:e')
  assert.equal(h.sent[0].args.draft.baseRowVersion,7)
  assert.equal(h.finished.length,0)
  h.sent[0].callback(true)
  assert.deepEqual(h.finished,[false])
})
test('failed local storage or newer edits keep the editor open',()=>{
  for(const newer of [false,true]) {
    const h=harness(); h.form.requestClose(); h.accept()
    if(newer) h.form.editRevision++
    h.sent[0].callback(newer)
    assert.equal(h.finished.length,0)
    assert(h.form.error.length>0)
  }
})
test('save in progress blocks cancellation',()=>{
  const h=harness();h.form.saving=true;h.form.requestClose()
  assert.equal(h.sent.length,0);assert.equal(h.finished.length,0)
})

test('clean editor with an unacknowledged saved identity waits for local checkpoint',()=>{
  const h=harness()
  h.form.dirty=false
  h.form.savedId='expense-id'
  h.form.editRevision=0
  h.form.requestClose()
  assert.equal(h.sent.length,1)
  assert.equal(h.sent[0].op,'saveEditorDraft')
  assert.equal(h.finished.length,0)
  h.sent[0].callback(true)
  assert.deepEqual(h.finished,[false])
})
test('rejected checkpoint initiation leaves the editor open',()=>{
  const h=harness()
  h.form.app.call=()=> ''
  h.form.requestClose()
  h.accept()
  assert.equal(h.finished.length,0)
  assert.match(h.form.error,/copia local/)
})
test('late snapshot callback cannot close another expense editor',()=>{
  const h=harness()
  h.form.requestClose()
  h.accept()
  h.form.draftKey='expense:r:other'
  h.sent[0].callback(true)
  assert.equal(h.finished.length,0)
})

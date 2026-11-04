'use strict'
const {test} = require('node:test')
const assert = require('node:assert/strict')
const fs = require('node:fs')
const path = require('node:path')
const vm = require('node:vm')
const shader = fs.readFileSync(path.join(__dirname, '../../qml/Mobile/shaders/glass.frag'), 'utf8')
const mix = (a,b,t) => a*(1-t)+b*t
const tintExpression = shader.match(/vec3 glass = ([^;]+);/)[1]
const edgeExpression = shader.slice(shader.indexOf('// Borde fino')).match(/glass = ([^;]+);/)[1]
test('white glass over white stays white for Qt premultiplied QColor uniforms', () => {
  for (const alpha of [0,0.22,0.42,0.78,1]) {
    const result = vm.runInNewContext(tintExpression, {backdrop:1,tint:{rgb:alpha,a:alpha},mix})
    assert.ok(Math.abs(result-1)<1e-9, `alpha=${alpha}: ${result}`)
  }
})
test('tint and edge composite premultiplied color once on each RGB channel', () => {
  for (const channel of [0.1,0.4,1]) {
    const alpha=0.42, backdrop=0.7
    const glass=vm.runInNewContext(tintExpression,{backdrop,tint:{rgb:channel*alpha,a:alpha},mix})
    assert.ok(Math.abs(glass-(backdrop*(1-alpha)+channel*alpha))<1e-9)
    const edgeMask=0.6, edge={rgb:0.55,a:0.55}
    const result=vm.runInNewContext(edgeExpression,{glass,edge,edgeMask,mix})
    assert.ok(Math.abs(result-(glass*(1-edge.a*edgeMask)+edge.rgb*edgeMask))<1e-9)
  }
})

const fs = require('node:fs');
const vm = require('node:vm');
const assert = require('node:assert/strict');
const rules = vm.createContext({});
vm.runInContext(fs.readFileSync('qml/Mobile/lib/CalicataRules.js','utf8').replace(/^\.pragma library\s*/,''), rules);
let count = 0;
function test(name, run) { run(); ++count; console.log(name+' OK'); }
// Un único motor SUCS/AASHTO: el port exacto de Web (soilClassification.ts),
// verificado contra casos dorados en tests/calicatas/web_lab_parity_static.cjs.
const review = (row, extra) => rules.reviewLaboratorySample(rules.labForm(row, extra || {}));
test('CALICATA_SUCS_SINGLE_ENGINE',()=> {
  assert.equal(typeof rules.classifyLaboratory, 'undefined');
  assert.deepEqual([...review({g2:'90',g04:'85',g008:'80',wl:'40',lp:'20'}).sucs.candidates], ['CL']);
  assert.deepEqual([...review({g2:'90',g04:'85',g008:'80',wl:'60',lp:'30'}).sucs.candidates], ['CH']);
  assert.deepEqual([...review({g2:'60',g04:'40',g008:'4'},{passing_no4:'40'}).sucs.candidates], ['GW','GP']);
});
test('CALICATA_SECOND_PATTERN',()=> {
  const stored = {sucs:'OH',pattern_primary:'OH',pattern_secondary:'Pt'};
  assert.equal(JSON.stringify(rules.selectedPatternCodes(JSON.parse(JSON.stringify(stored)))),'["OH","Pt"]');
  assert.equal(JSON.stringify(rules.selectedPatternCodes({...stored,pattern_secondary:''})),'["OH"]');
  assert.equal(JSON.stringify(rules.selectedPatternCodes({sucs:'SW-SM'})),'["SW","SM"]');
  assert.equal(JSON.stringify(rules.selectedPatternCodes({sucs:'SW-SM',pattern_primary:'SW',pattern_secondary:''})),'["SW"]');
  assert.equal(JSON.stringify(rules.selectedPatternCodes({...stored,pattern_secondary:'OH'})),'["OH"]');
  assert.equal(stored.sucs,'OH');
});
test('CALICATA_PATTERN_MAPPING',()=> {
  for (const code of rules.sucsCodes) for (const part of rules.patternCodes(code)) {
    const ext=['CH','OH','Pt'].includes(part)?'svg':'png';
    assert.ok(fs.existsSync(`SUCS/${part}.${ext}`),part);
  }
});
const qml = fs.readFileSync('qml/Mobile/pages/CalicataFormPage.qml','utf8');
// El campo editable de código usa BoundTextField (boundText) como única fuente visible.
test('CALICATA_CODE_SINGLE_SOURCE',()=> {
  assert.equal((qml.match(/boundText: txtCodigo\.text/g)||[]).length,1);
  assert.equal((qml.match(/modelText: txtCodigo\.text/g)||[]).length,0);
});
// El proyecto ya no se escribe a mano: solo se fija al elegirlo (selectProject) y se lee de la ficha.
test('CALICATA_PROJECT_SINGLE_SOURCE',()=> {
  assert.equal((qml.match(/(?:modelText|boundText): txtProjectFullName\.text/g)||[]).length,0);
  assert.ok(qml.includes('if (!root.doc.selectProject(selection)) {'));
  assert.ok(!qml.includes('titleDialog'));
});
test('CALICATA_NO_INLINE_PROFILE_PREVIEW',()=> {
  assert.ok(!qml.includes('text: "Perfil estratigráfico"'));
  assert.ok(!qml.includes('mobileProfilePreviewTap'));
});
test('CALICATA_PATTERN_EXPORT_CONTRACT',()=> {
  const cpp=fs.readFileSync('androidcalicataexporter.cpp','utf8');
  assert.ok(cpp.includes('bool writeScaledProfile(QXlsx::Document &xlsx, const QVariantList &cortes,'));
  assert.ok(cpp.includes('const ExportClassification classification = exportClassificationFor(corte);'));
  assert.ok(!cpp.includes('QStringLiteral("pattern_primary")'), 'la trama sale del laboratorio, no de pattern_primary');
});
console.log(JSON.stringify({tests:count,status:'STATIC_VALIDATED',compilation:false}));

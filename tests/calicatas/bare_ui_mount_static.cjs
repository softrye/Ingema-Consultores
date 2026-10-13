// Bare Metal UI, fase 3: comprueba las CONDICIONES DE CREACIÓN (Loader.active,
// layer.enabled, guardas Java/JNI), no la visibilidad.
const fs = require('fs');
const path = require('path');
const assert = require('assert');
const root = path.resolve(__dirname, '..', '..');
const read = (p) => fs.readFileSync(path.join(root, p), 'utf8').replace(/\r\n/g, '\n');
const check = (name, fn) => { fn(); console.log('PASS ' + name); };

const java = read('android/src/com/ingema/ingeplus/InGeQtActivity.java');
const cpp = read('src/graphics/InGeGraphicsCore.cpp');
const hdr = read('src/graphics/InGeGraphicsCore.h');
const flow = read('qml/Mobile/flowcore/InGeCoreFlow.qml');
const main = read('qml/Mobile/Main.qml');
const editor = read('qml/Mobile/pages/CalicatasEditorPage.qml');
const form = read('qml/Mobile/pages/CalicataFormPage.qml');

check('puente JNI: firma, clase, include y fallback ON', () => {
  assert.ok(/public static boolean isBareUiEnabled\(\) \{\n\s+return BARE_UI;/.test(java));
  assert.ok(cpp.includes('"com/ingema/ingeplus/InGeQtActivity", "isBareUiEnabled", "()Z"'));
  assert.ok(cpp.includes('#include <QJniObject>') && cpp.includes('#include <QJniEnvironment>'));
  assert.ok(cpp.includes('INGE_PERFORMANCE_BARE_UI_JNI_FAILED fallback=ON";\n            return true;'));
  assert.ok(hdr.includes('Q_PROPERTY(bool bareUiEnabled READ bareUiEnabled CONSTANT)'));
  assert.ok(flow.includes('bareUiSwitch: graphicsCore.bareUiEnabled === true'));
  assert.ok(!/bareUiSwitch: true/.test(flow), 'segunda fuente de configuración');
});
check('Dock original y Home Flutter no se crean', () => {
  assert.ok(!main.includes('GlobalContextDock'));
  assert.ok(main.includes('sourceComponent: pageIndex === 0 ? homePage :'));
  assert.ok(/boolean visible[^)]*\) \{\n\s+if \(visible && BARE_UI\) \{\n[^\n]*INGE_FLUTTER_HOME_BLOCKED[^\n]*\n\s+return false;/.test(java));
});
check('Liquid Glass eliminado físicamente (archivo, shader, CMake, QRC)', () => {
  assert.ok(!fs.existsSync(path.join(root, 'qml/Mobile/flowcore/LiquidGlassSurface.qml')));
  assert.ok(!fs.existsSync(path.join(root, 'qml/Mobile/shaders/liquidglass.frag')));
  const cmake = read('CMakeLists.txt');
  assert.ok(!cmake.includes('LiquidGlassSurface') && !cmake.includes('liquidglass') && !cmake.includes('ShaderTools'));
  assert.ok(!read('resources_mobile_raw.qrc').includes('LiquidGlassSurface'));
});
check('Calicatas: sin desenfoques de emergentes ni máscara de foto', () => {
  for (const t of ['infoPeek.reveal', 'calPopup.glass', 'calScrimBlurLayer', 'peekBackdropCapture', 'MultiEffect', 'ShaderEffectSource'])
    assert.ok(!editor.includes(t), 'editor ' + t);
  for (const t of ['labDetailBackdrop', 'photoHeroMask', 'MultiEffect', 'ShaderEffectSource'])
    assert.ok(!form.includes(t), 'form ' + t);
});
check('Rendiciones conserva su navegación (ocultar resetea homeRequested)', () => {
  assert.ok(/if \(!"renditions"\.equals\(activity\.homeSurfaceMode\)\)\n\s+return true;\n\s+activity\.homeRequested = false;/.test(java));
  assert.ok(main.includes('Perms.setFlutterRenditionsVisible('));
});
check('Login y video siguen habilitados', () => {
  assert.ok(read('flutter/inge_earth/lib/home.dart').includes('animate: !MediaQuery.disableAnimationsOf(context)'));
  assert.ok(main.includes('inGeCoreFlow.motionAllowedBase ? 1.0 : 0.0'));
});

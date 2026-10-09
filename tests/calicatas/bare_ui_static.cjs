// Operación Bare Metal UI: el modo mínimo no monta Dock flotante, Home Flutter
// ni pantallas de carga animadas, y conserva acciones y navegación reales.
const fs = require('fs');
const path = require('path');
const assert = require('assert');
const root = path.resolve(__dirname, '..', '..');
const read = (p) => fs.readFileSync(path.join(root, p), 'utf8').replace(/\r\n/g, '\n');
const check = (name, fn) => { fn(); console.log('PASS ' + name); };

const flow = read('qml/Mobile/flowcore/InGeCoreFlow.qml');
const main = read('qml/Mobile/Main.qml');
const java = read('android/src/com/ingema/ingeplus/InGeQtActivity.java');
const authHome = read('flutter/inge_earth/lib/home.dart');

check('interruptor único, global en Android (sin filtro por tier)', () => {
  assert.ok(flow.includes('readonly property bool bareUiSwitch: graphicsCore.bareUiEnabled === true'));
  assert.ok(java.includes('public static final boolean BARE_UI = true;'));
  assert.ok(java.includes('MAP_LOADING_STATIC = BARE_UI;'));
  assert.ok(java.includes('public static boolean isBareUiEnabled()'));
  assert.ok(/readonly property bool bareUi: bareUiSwitch && Qt\.platform\.os === "android"\n/.test(flow));
  assert.ok(flow.includes('motionAllowed:\n        !bareUi'));
  assert.ok(flow.includes('liquidGlass: theme.isGlass && !bareUi'));
});
check('Dock anterior eliminado físicamente (archivo, CMake, QRC, referencias)', () => {
  assert.ok(!fs.existsSync(path.join(root, 'qml/Mobile/flowcore/GlobalContextDock.qml')));
  assert.ok(!read('CMakeLists.txt').includes('GlobalContextDock.qml'));
  assert.ok(!read('resources_mobile_raw.qrc').includes('GlobalContextDock.qml'));
  for (const t of ['GlobalContextDock', 'globalContextDock', 'glassMaterial']) assert.ok(!main.includes(t), t);
});
check('barra estática usa el mismo controlador y router del Dock', () => {
  assert.ok(main.includes('id: bareNavBarV1'));
  assert.ok(main.includes('dockContextController.actions'));
  assert.ok(main.includes('dockCommandRouter.dispatch(String(modelData.id)'));
});
check('Home única en QML; host de Home Flutter y HomePagePhase1 eliminados', () => {
  assert.ok(main.includes('sourceComponent: pageIndex === 0 ? homePage :'));
  assert.ok(!fs.existsSync(path.join(root, 'qml/Mobile/pages/HomePagePhase1.qml')));
  for (const t of ['flutterHomeActiveV60', 'flutterHomeHandoffV800', 'requestFlutterHomeV60', 'homePhase1Page']) assert.ok(!main.includes(t), t);
  for (const page of [1, 2, 3, 4, 6]) assert.ok(main.includes('page: ' + page + ' }'), 'page ' + page);
  assert.ok(main.includes('app.performLogoutV18()'));
  assert.ok(main.includes('function releaseAuthSurfaceToQmlHomeV800()'));
  assert.ok(main.includes('readonly property bool homeReadyV900'));
  assert.ok(read('main_mobile.cpp').includes('"homeReadyV900", StartupEvent::HOME_READY'));
});
check('carga del mapa: texto estático, sin spinner ni fundido; lógica intacta', () => {
  assert.ok(java.includes('MAP_LOADING_STATIC = BARE_UI;'));
  assert.ok(java.includes('MAP_LOADING_STATIC ? View.GONE : View.VISIBLE'));
  assert.ok(java.includes('if (MAP_LOADING_STATIC || !android.animation.ValueAnimator.areAnimatorsEnabled()'));
  for (const t of ['INGE_MAP_LOAD_TIMEOUT', 'INGE_MAP_LOAD_CANCELLED', 'session != mapLoadingSession'])
    assert.ok(java.includes(t), t);
});
check('Earth -> Home se completa sin Home Flutter', () => {
  assert.ok(java.includes('} else if (BARE_UI) {'));
  assert.ok(java.includes('|| (!BARE_UI && (!homeRequested'));
});
check('vidrio de Calicatas y genérico no se crean en modo mínimo', () => {
  for (const p of ['qml/Mobile/pages/CalicataLiquidGlass.qml', 'qml/Mobile/flowcore/LiquidGlassSurface.qml', 'qml/Mobile/shaders/liquidglass.frag'])
    assert.ok(!fs.existsSync(path.join(root, p)), p + ' eliminado');
  const fgs = read('qml/Mobile/flowcore/FlowGlassSurface.qml');
  for (const t of ['MultiEffect', 'ShaderEffect', 'Loader', 'layer.', 'glassMaterial'])
    assert.ok(!fgs.includes(t), 'FlowGlassSurface ' + t);
});
check('Earth HTML sin animaciones ni captura para el Dock', () => {
  assert.ok(java.includes("classList.add('bare-ui')"));
  assert.ok(read('android/assets/cesium/ui/inge-earth-ui.css').includes('body.bare-ui *'));
  assert.ok(read('android/assets/cesium/ui/inge-earth-ui.js').includes("if (document.body.classList.contains('bare-ui')) return;"));
});
check('Auth conserva su video y su movimiento propio', () => {
  assert.ok(authHome.includes('animate: !MediaQuery.disableAnimationsOf(context)'));
  assert.ok(main.includes('inGeCoreFlow.motionAllowedBase ? 1.0 : 0.0'));
});

'use strict';
// Selector de coordenadas de Calicatas sobre InGe Earth (CesiumJS): contrato
// estático entre QML ↔ C++ (GraphicsCore/InGeEarthHostController) ↔ JNI ↔
// Java (InGeQtActivity) ↔ JS (inge-earth-picker.js). No sustituye la prueba
// en dispositivo. Run: node tests/calicatas/earth_picker_static.cjs
const fs = require('fs');
const path = require('path');
const assert = require('assert');

const root = path.resolve(__dirname, '..', '..');
const read = (p) => fs.readFileSync(path.join(root, p), 'utf8').replace(/\r\n/g, '\n');
const java = read('android/src/com/ingema/ingeplus/InGeQtActivity.java');
const host = read('src/graphics/InGeEarthHostController.cpp');
const hostH = read('src/graphics/InGeEarthHostController.h');
const core = read('src/graphics/InGeGraphicsCore.cpp');
const coreH = read('src/graphics/InGeGraphicsCore.h');
const picker = read('qml/Mobile/pages/CalicataPointPicker.qml');
const editor = read('qml/Mobile/pages/CalicatasEditorPage.qml');
const js = read('android/assets/cesium/ui/inge-earth-picker.js');
const details = read('android/assets/cesium/ui/inge-earth-map-details.js');
const html = read('android/assets/cesium/index.html');
const css = read('android/assets/cesium/ui/inge-earth-ui.css');
let passed = 0;
const check = (name, fn) => { fn(); passed++; console.log('PASS', name); };

check('JNI Qt -> Java: métodos estáticos y firmas coinciden', () => {
  const calls = [
    ['showEarthPicker', '(Ljava/lang/String;IIII)Z', /public static boolean showEarthPicker\(String json, int left, int top, int width, int height\)/],
    ['updateEarthPickerRect', '(IIII)V', /public static void updateEarthPickerRect\(int left, int top, int width, int height\)/],
    ['setEarthPickerPoint', '(Ljava/lang/String;)V', /public static void setEarthPickerPoint\(String json\)/],
    ['setEarthPickerSuspended', '(Z)V', /public static void setEarthPickerSuspended\(boolean suspended\)/],
    ['hideEarthPicker', '()V', /public static void hideEarthPicker\(\)/],
  ];
  for (const [name, sig, decl] of calls) {
    assert.ok(host.includes(`"${name}", "${sig}"`) || host.includes(`"${name}",\n                                       "${sig}"`), `C++ llama ${name}${sig}`);
    assert.ok(decl.test(java), `Java declara ${name}`);
  }
});

check('JNI Java -> Qt: nativos declarados = funciones exportadas', () => {
  assert.ok(java.includes('private static native void nativeEarthPickerSelected(double latitude, double longitude);'));
  assert.ok(java.includes('private static native void nativeEarthPickerState(String state);'));
  assert.ok(host.includes('Java_com_ingema_ingeplus_InGeQtActivity_nativeEarthPickerSelected(\n    JNIEnv *, jclass, jdouble latitude, jdouble longitude)'));
  assert.ok(host.includes('Java_com_ingema_ingeplus_InGeQtActivity_nativeEarthPickerState(\n    JNIEnv *, jclass, jstring state)'));
  assert.ok(/Qt::QueuedConnection/.test(host), 'señales a Qt en su hilo');
});

check('GraphicsCore expone el selector a QML y reenvía las señales', () => {
  for (const m of ['openEarthPicker', 'updateEarthPickerRect', 'setEarthPickerPoint', 'setEarthPickerSuspended', 'closeEarthPicker'])
    assert.ok(new RegExp(`Q_INVOKABLE [^;]*\\b${m}\\(`).test(coreH), m);
  assert.ok(coreH.includes('void earthPickerPointSelected(double latitude, double longitude);'));
  assert.ok(hostH.includes('void pickerPointSelected(double latitude, double longitude);'));
  assert.ok(core.includes('&InGeEarthHostController::pickerPointSelected,\n                this, &InGeGraphicsCore::earthPickerPointSelected'));
});

check('Un solo motor: el selector reutiliza el WebView de Earth (sin WebView nuevo)', () => {
  const enter = java.slice(java.indexOf('private void enterEarthPicker('), java.indexOf('private void applyEarthPickerLayout('));
  assert.ok(enter.includes('ensureDirectEarthWebView();') && !/new WebView\(/.test(enter));
  assert.ok(enter.includes('if (earthRequested)'), 'no convive con Earth a pantalla completa');
  assert.ok(java.includes('if (earthPickerActive)\n            exitEarthPicker();'), 'abrir Earth cierra el selector');
  assert.ok(!/\bMap\s*\{|MapLibre|QtLocation/.test(picker), 'sin mapa QML paralelo');
  assert.ok(java.includes('private volatile boolean earthPickerActive;'), 'leído desde el hilo JS');
});

check('Ciclo de vida: pausa/reanudación y salida liberan el WebView', () => {
  assert.ok(java.includes('} else if (earthPickerActive && earthWebView != null) {\n            earthWebView.onPause();'));
  assert.ok(java.includes('if (earthPickerActive && earthWebView != null) {\n            earthWebView.onResume();'));
  const exit = java.slice(java.indexOf('private void exitEarthPicker()'), java.indexOf('private void notifyEarthPickerState('));
  assert.ok(exit.includes('InGeEarthPicker.exit()') && exit.includes('View.GONE') && exit.includes('webView.onPause()'));
  assert.ok(exit.includes('applyContextDockBand(webView)'), 'Earth recupera su geometría');
  assert.ok(picker.includes('Component.onDestruction: {\n        root._closeMap()'), 'cerrar el popup cierra el mapa');
});

check('Dock nativo no recorta ni roba toques en modo selector', () => {
  assert.ok(java.includes('if (!earthPickerActive)\n                    clipNativeDock(canvas, getWidth(), getHeight());'));
  assert.ok(java.includes('dockGesture = !earthPickerActive\n                            && dockOwnsTouch('));
});

check('Ficha intacta hasta «Usar esta ubicación»; Cancelar descarta', () => {
  const tap = picker.slice(picker.indexOf('function _onMapPointSelected('), picker.indexOf('function _hostRect()'));
  assert.ok(!/acceptMapPoint|header|currentDoc/.test(tap));
  assert.ok(editor.includes('formLoader.item.acceptMapPoint(map.selectedLat, map.selectedLon, map.selectedAlt,'));
  assert.ok(editor.includes('onOpened: if (coordinateMap.item) coordinateMap.item.mapSuspended = true'), 'diálogo de distancia visible');
});

check('JS: entrar/salir conserva el estado de Earth; tap = solo candidato', () => {
  assert.ok(html.includes('<script src="ui/inge-earth-picker.js"></script>'));
  assert.ok(/saved = \{[\s\S]*destination[\s\S]*mapType[\s\S]*tilesetShow/.test(js));
  assert.ok(js.includes("ui.setInteraction('PICKER', choose, null);"));
  assert.ok(js.includes("bridgeCall('pickerSelected', coordinates.latitude, coordinates.longitude)"));
  assert.ok(js.includes('if (tileset) tileset.show = false;'), 'sin teselas 3D en el selector');
  assert.ok(css.includes('body.picker-mode #earthUi'));
});

check('Mapa base sin claves: OSM público si no hay DEFAULT_MAP_URL; satélite solo con ion', () => {
  assert.ok(details.includes("const PUBLIC_OSM_TILES = 'https://tile.openstreetmap.org/{z}/{x}/{y}.png';"));
  assert.ok(details.includes('normalizedXyzUrl(config.defaultMapUrl) || PUBLIC_OSM_TILES'));
  assert.ok(details.includes("if (!runtime.ionConfigured) setMapType('DEFAULT');"));
  assert.ok(js.includes("button.disabled = !runtime.ionConfigured;"));
  for (const f of [js, details, html]) assert.ok(!/eyJhbGciOi|AIza[0-9A-Za-z_-]{20}/.test(f), 'sin tokens embebidos');
});

console.log(`earth_picker_static: ${passed} PASS`);

// Pantalla de carga cartográfica ÚNICA (host Android) para InGe Earth y el
// selector de Calicatas. Verificación estática del contrato.
const fs = require('fs');
const path = require('path');
const assert = require('assert');
const root = path.resolve(__dirname, '..', '..');
const read = (p) => fs.readFileSync(path.join(root, p), 'utf8').replace(/\r\n/g, '\n');
const check = (name, fn) => { fn(); console.log('PASS ' + name); };

const loader = read('android/assets/cesium/ui/inge-map-loading.js');
const picker = read('android/assets/cesium/ui/inge-earth-picker.js');
const html = read('android/assets/cesium/index.html');
const css = read('android/assets/cesium/ui/inge-earth-ui.css');
const java = read('android/src/com/ingema/ingeplus/InGeQtActivity.java');
const qmlPicker = read('qml/Mobile/pages/CalicataPointPicker.qml');
const qmlEarth = read('qml/Mobile/pages/MapNativePage.qml');

check('coordinador cargado una vez, después del selector', () => {
  const tags = html.match(/ui\/inge-map-loading\.js/g) || [];
  assert.strictEqual(tags.length, 1);
  assert.ok(html.indexOf('ui/inge-earth-picker.js') < html.indexOf('ui/inge-map-loading.js'));
});
check('revelado: capas + globo + 3D + cámara quieta + fotogramas estables + lienzo no vacío', () => {
  for (const token of ['globe.tilesLoaded', 'layer.ready', 'tileset.tilesLoaded', 'cameraStill',
    'STABLE_FRAMES', 'canvasHasContent', "post('VISUAL_READY')", 'requestRender'])
    assert.ok(loader.includes(token), token);
});
check('el selector ya no tiene pantalla de carga propia', () => {
  for (const token of ['pickerLoading', 'setLoading', 'startLoading', "LOADING_READY"])
    assert.ok(!picker.includes(token), token);
  assert.ok(picker.includes("beginLoading('picker')") && picker.includes("beginLoading('layer')"));
});
check('miniatura satelital solo con VISUAL_READY', () => {
  assert.ok(/tilesReady = viewer\.scene\.globe\.tilesLoaded\s*&& !!window\.InGeMapLoading && window\.InGeMapLoading\.isReady\(\)/.test(picker));
});
check('arranque HTML de Earth oculto', () => {
  assert.ok(css.includes('#earthBoot { display: none !important; }'));
});
check('host Android: overlay único, timeout, reintento, cancelación, sesiones', () => {
  for (const token of ['INGE_MAP_LOAD_BEGIN', 'INGE_MAP_REVEALED', 'INGE_MAP_LOAD_TIMEOUT',
    'INGE_MAP_LOAD_CANCELLED', 'session != mapLoadingSession', 'areAnimatorsEnabled',
    'MAP_LOADING_FADE_MS = 260L', 'showMapLoading("picker")', 'showMapLoading("earth")',
    'cancelMapLoading("picker_closed")', 'cancelMapLoading("earth_closed")', 'public void mapLoading('])
    assert.ok(java.includes(token), token);
  assert.strictEqual((java.match(/new FrameLayout\(this\);\n        overlay\.setBackgroundColor/g) || []).length, 1);
});
check('QML sin cargadores propios', () => {
  assert.ok(!qmlPicker.includes('Abriendo el mapa') && !qmlPicker.includes('Iniciando InGe Earth'));
  assert.ok(!qmlPicker.includes('BusyIndicator'));
  assert.ok(!qmlEarth.includes('Preparando InGe Earth') && !qmlEarth.includes('FlowProgressRing'));
});
check('sin secretos en los registros de carga', () => {
  assert.ok(!/token|apikey|key=/i.test(loader));
});

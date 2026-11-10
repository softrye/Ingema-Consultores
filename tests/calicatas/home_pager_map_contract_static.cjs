// Contrato estático del Home de Calicatas (complementa tests/calicatas/qml,
// que prueba el comportamiento). Falla si vuelve alguno de los defectos vistos
// en el equipo: título fuera del Flickable, mapa que entra por la izquierda,
// cuadrícula de teselas por índice o Rendiciones alterado para parecerse.
'use strict'
const fs = require('fs')
const path = require('path')
const { execFileSync } = require('child_process')
const assert = require('assert')

const repo = path.resolve(__dirname, '../..')
const read = rel => fs.readFileSync(path.join(repo, rel), 'utf8')
const home = read('qml/Mobile/pages/CalicatasHome.qml')
const map = read('qml/Mobile/pages/CalicatasTopoMap.qml')
const screen = read('qml/Mobile/HomeScreen.qml')
let n = 0
function check(name, fn) { fn(); n++; console.log('PASS ' + name) }

check('el título vive dentro del Flickable de la lista (contrato de RenditionsHome)', () => {
  const flick = home.indexOf('objectName: "homeListFlick"')
  const header = home.indexOf('objectName: "homeHeader"')
  const panel = home.indexOf('id: panel')
  assert(flick > 0 && header > flick && panel > header)
  assert(/y: header\.y \+ header\.height \+ 24 \* home\.u/.test(home))
  assert(!/y: header\.y \+ header\.height \+ 12 \* home\.u/.test(home), 'franja fija bajo un encabezado externo')
})
check('Pull-to-Refresh devuelve el Flickable a sus límites al terminar', () => {
  assert(/function onRefreshingChanged\(\) \{ if \(!home\.refreshing\) settleTop\.restart\(\) \}/.test(home))
  assert(/flick\.returnToBounds\(\)/.test(home))
})
check('un solo estado de páginas: el mapa a la DERECHA de la lista', () => {
  assert(/x: -home\.pagePos \* width/.test(home), 'la lista debe salir por la izquierda')
  assert(/x: \(1 - home\.pagePos\) \* width/.test(home), 'el mapa debe entrar desde la derecha')
  assert(!/x: home\.view === "map" \? 0 : -width/.test(home))
})
check('gesto: el dedo trae el mapa desde la derecha (lista + izquierda = mapa)', () => {
  assert(/var wanted = fromPage === "list" \? dx < 0 : dx > 0/.test(home), 'lista: izquierda abre el mapa; mapa: derecha vuelve')
  assert(/function _pageSwipeEnd\(/.test(home) && /Math\.max\(0, -dx\) \/ width/.test(home), 'la página acompaña al dedo')
  assert(/startX < systemEdge \|\| startX > width - systemEdge/.test(home), 'gestos desde el borde de Android')
  assert(/onCanceled: wasCanceled = true/.test(home), 'gesto cancelado por el sistema')
  assert(/PageSwipe \{ id: listSwipe;[^}]*fromPage: "list"[^}]*CanTakeOverFromAnything/.test(home))
  assert(/PageSwipe \{ id: mapSwipe;[^}]*fromPage: "map"[^}]*CanTakeOverFromAnything/.test(home))
})
check('el mapa se crea solo al mostrarse y no pide teselas oculto', () => {
  assert(/active: visible/.test(home))
  assert(/readonly property bool running: active && visible/.test(map))
  assert(/active: map\.everActive && !map\._reloading/.test(map))
})
check('motor Qt Location (sin cuadrícula QML propia)', () => {
  assert(/^import QtLocation$/m.test(map) && /^import QtPositioning$/m.test(map))
  assert(/name: "osm"/.test(map) && /osm\.mapping\.custom\.host/.test(map))
  assert(/osm\.mapping\.providersrepository\.disabled/.test(map))
  assert(/style === MapType\.CustomMap/.test(map))
  assert(/osm\.useragent/.test(map))
  assert(!/ListModel \{ id: tiles \}|_pruneFallback|firstX|viewportCoverage/.test(map), 'quedó el motor anterior')
  assert(/MapItemView \{/.test(map) && /MapQuickItem \{/.test(map))
})
check('CMake enlaza Qt Location en el objetivo móvil (empaquetado Android)', () => {
  const cm = read('CMakeLists.txt')
  assert(/find_package\(Qt\$\{QT_VERSION_MAJOR\} REQUIRED COMPONENTS Location\)/.test(cm))
  assert(/::QuickControls2\s+Qt\$\{QT_VERSION_MAJOR\}::Positioning\s+Qt\$\{QT_VERSION_MAJOR\}::Location/.test(cm),
         'AppCalicatasMobile debe enlazar Qt::Location')
})
check('proveedor y atribución cartográfica conservados', () => {
  assert(map.includes('https://tile.opentopomap.org/'))
  assert(map.includes('© OpenTopoMap (CC-BY-SA) · © OpenStreetMap'))
  assert(/maxZoom: topoLayer \? 17 : 19/.test(map))
})
check('el GPS no inventa posición ni mueve el mapa sin un fix real', () => {
  assert(/readonly property string gpsState/.test(map))
  assert(!/deviceFixTimeout[\s\S]{0,400}fitToMarkers\(\)/.test(map), 'el timeout no debe encuadrar en silencio')
})
check('la entrada a Calicatas empieza con el editor ya cargado (como Rendiciones)', () => {
  assert(/if \(calicatasEditor\.status === Loader\.Ready\) home\.runSubAppTransition\(true, from, home\.page\)/.test(screen))
  assert(/calicatasEnterPendingFrom/.test(screen))
})
check('Rendiciones no fue modificado para parecerse a Calicatas', () => {
  const files = ['RenditionsHome.qml', 'RenditionsApp.qml', 'RendicionesSyncAura.qml', 'RGlassMenu.qml', 'RMenuItem.qml']
    .map(f => 'qml/Mobile/renditions/' + f)
  let diff = ''
  try { diff = execFileSync('git', ['diff', '--name-only', 'HEAD', '--', ...files], { cwd: repo, encoding: 'utf8' }) }
  catch (e) { console.log('SKIP git no disponible'); return }
  assert.strictEqual(diff.trim(), '', 'archivos de Rendiciones modificados: ' + diff)
  const ref = read('qml/Mobile/renditions/RenditionsHome.qml')
  assert(ref.indexOf('id: header') > ref.indexOf('Flickable {'), 'RenditionsHome cambió su contrato de cabecera')
})
console.log('HOME_PAGER_MAP_CONTRACT_OK ' + n)

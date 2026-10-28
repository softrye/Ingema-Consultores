// Pruebas de comportamiento del Home de Calicatas (QML de escritorio).
// Copia los archivos REALES del Home, el mapa y los componentes de Rendiciones
// a un espejo temporal, agrega solo los stubs de prueba (módulo InGe con un
// CalicataCloud simulado y FlowIcon sin módulo nativo), genera una pirámide de
// teselas locales distintas (tile_fixtures.cjs) para el motor Qt Location real
// y ejecuta qmltestrunner en modo offscreen. Después decodifica las capturas
// cov_<etiqueta>_max<pct>.png del mapa y falla si el fondo vacío supera <pct>.
// No compila Android ni usa la red. KEEP=1 conserva el espejo (capturas).
//   node tests/calicatas/qml/run_home_qml_tests.cjs
// QT_DIR (opcional): kit Qt de escritorio; por defecto C:/Qt/6.9.3/mingw_64.
'use strict'
const fs = require('fs')
const os = require('os')
const path = require('path')
const { spawnSync } = require('child_process')
const fixtures = require('./tile_fixtures.cjs')

const repo = path.resolve(__dirname, '../../..')
const here = __dirname
const qtDir = process.env.QT_DIR || 'C:/Qt/6.9.3/mingw_64'
const runner = path.join(qtDir, 'bin', process.platform === 'win32' ? 'qmltestrunner.exe' : 'qmltestrunner')
if (!fs.existsSync(runner)) {
  console.log('SKIP qmltestrunner no encontrado en ' + runner + ' (define QT_DIR)')
  process.exit(0)
}

const mirror = fs.mkdtempSync(path.join(os.tmpdir(), 'calicatas-home-qml-'))
function copy(from, to) {
  fs.mkdirSync(path.dirname(to), { recursive: true })
  fs.copyFileSync(from, to)
}
const real = {
  'pages/CalicatasHome.qml': 'qml/Mobile/pages/CalicatasHome.qml',
  'pages/CalicatasTopoMap.qml': 'qml/Mobile/pages/CalicatasTopoMap.qml',
  'lib/CalicataRules.js': 'qml/Mobile/lib/CalicataRules.js',
  'lib/CalicataDiagnostics.js': 'qml/Mobile/lib/CalicataDiagnostics.js',
  'lib/IconCatalog.js': 'qml/Mobile/lib/IconCatalog.js',
  'renditions/RStyle.js': 'qml/Mobile/renditions/RStyle.js'
}
for (const name of ['RGlassMenu', 'RMenuItem', 'RButton', 'RField', 'RDateField', 'RSelect', 'RendicionesSyncAura'])
  real['renditions/' + name + '.qml'] = 'qml/Mobile/renditions/' + name + '.qml'
for (const [to, from] of Object.entries(real)) copy(path.join(repo, from), path.join(mirror, to))
copy(path.join(here, 'stubs/components/FlowIcon.qml'), path.join(mirror, 'components/FlowIcon.qml'))
copy(path.join(here, 'stubs/InGe/qmldir'), path.join(mirror, 'InGe/qmldir'))
copy(path.join(here, 'stubs/InGe/CalicataCloud.qml'), path.join(mirror, 'InGe/CalicataCloud.qml'))
const tileCount = fixtures.writePyramid(path.join(mirror, 'fixtures/tiles'))
fs.mkdirSync(path.join(mirror, 'shots'), { recursive: true })
fs.mkdirSync(path.join(mirror, 'cache'), { recursive: true })
console.log('FIXTURES tiles=' + tileCount)
for (const f of fs.readdirSync(here).filter(f => /^tst_.*\.qml$/.test(f)))
  copy(path.join(here, f), path.join(mirror, 'tests', f))

const env = Object.assign({}, process.env, {
  QT_QPA_PLATFORM: 'offscreen', QT_FORCE_STDERR_LOGGING: '1', QT_QUICK_CONTROLS_STYLE: 'Basic'
})
const args = ['-maxwarnings', '1000000', '-import', mirror, '-input', path.join(mirror, 'tests')]
const filter = process.argv.slice(2)
if (filter.length) args.push(...filter.map(f => f.includes('::') ? f : 'CalicatasHome::' + f))
const res = spawnSync(runner, args, { env, encoding: 'utf8', maxBuffer: 64 * 1024 * 1024, timeout: 600000 })
const out = (res.stdout || '') + (res.stderr || '')
const lines = out.split(/\r?\n/)
const verbose = process.env.VERBOSE === '1'
for (const l of lines) {
  if (verbose || /^(PASS|FAIL|SKIP|Totals|XFAIL|XPASS)|Actual|Expected|failure location|QML.*(Error|error)|TypeError|ReferenceError/.test(l))
    console.log(l)
}
// Cobertura cartográfica medida en las capturas reales del mapa.
let coverageFailed = 0
const shots = fs.readdirSync(path.join(mirror, 'shots')).filter(f => /^cov_.*_max\d+\.png$/.test(f)).sort()
for (const f of shots) {
  const max = Number(/_max(\d+)\.png$/.exec(f)[1]) / 100
  // Se excluyen los controles superpuestos: cabecera flotante (arriba), Dock y
  // atribución (abajo) y la columna de botones de vidrio (derecha).
  const empty = fixtures.emptyFraction(path.join(mirror, 'shots', f), null, 84, 150, 76)
  const ok = empty <= max
  if (!ok) coverageFailed++
  console.log((ok ? 'PASS' : 'FAIL!') + '   : coverage ' + f + ' empty=' + (empty * 100).toFixed(1) + '% max=' + (max * 100) + '%')
}
console.log('COVERAGE shots=' + shots.length + ' failed=' + coverageFailed)
if (process.env.KEEP === '1' || coverageFailed) console.log('MIRROR ' + mirror)
else fs.rmSync(mirror, { recursive: true, force: true })
if (res.error) { console.error(res.error.message); process.exit(1) }
process.exit(res.status === 0 && coverageFailed === 0 ? 0 : 1)

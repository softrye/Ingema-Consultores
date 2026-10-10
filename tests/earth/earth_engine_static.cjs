// Motor de InGe Earth sin interfaz (Visual Zero, 2026-10-10): funciones puras
// extraídas de la UI web retirada. Equivalencia verificada contra los
// originales el 2026-10-10; aquí se fijan sus resultados.
const fs = require("fs"), path = require("path"), vm = require("vm"), assert = require("assert");
const root = path.resolve(__dirname, "..", "..");
const cesiumDir = path.join(root, "android/assets/cesium");
const engineDir = path.join(cesiumDir, "engine");
const ctx = vm.createContext({ Math, Number, String, Date, Error, Promise, Map, Set, JSON, Uint8Array,
  Blob: class { constructor(parts, options) { this.parts = parts; this.type = options && options.type; } },
  File: class {}, atob, btoa, crypto: { randomUUID: () => "uuid" }, fetch: async () => ({}), console });
ctx.window = ctx;
ctx.Cesium = new Proxy({}, { get: () => function () { return {}; } });
ctx.window.viewer = { scene: { requestRender() {}, globe: {} }, imageryLayers: { addImageryProvider: () => ({}) }, camera: {} };
ctx.window.InGeEarthBaseRuntime = { ionConfigured: true, getPhotorealisticTileset: () => null, naturalEarthLayer: {}, ellipsoidTerrain: {} };
ctx.window.InGeEarthStorage = {};
for (const f of ["inge-earth-coordinates.js", "inge-earth-map-engine.js", "inge-earth-project-engine.js"])
  vm.runInContext(fs.readFileSync(path.join(engineDir, f), "utf8"), ctx, { filename: f });
const M = ctx.InGeEarthMapEngine, P = ctx.InGeEarthProjectEngine, C = ctx.InGeEarthCoordinates;
const plain = (v) => JSON.parse(JSON.stringify(v));
let passed = 0;
const check = (name, fn) => { fn(); passed++; console.log("PASS", name); };

check("index.html carga sólo el motor (sin UI, selector ni pantalla de carga)", () => {
  const html = fs.readFileSync(path.join(cesiumDir, "index.html"), "utf8");
  for (const forbidden of ["ui/", "earthUi", "earthBoot", "earthHdChip", "streetView", "<button", "<input", "<form", "<main"])
    assert(!html.includes(forbidden), forbidden);
  const scripts = [...html.matchAll(/<script src="([^"]+)"/g)].map((m) => m[1]);
  assert.deepStrictEqual(scripts, ["Cesium.js", "engine/inge-earth-storage.js", "engine/inge-earth-coordinates.js",
    "engine/inge-earth-map-engine.js", "engine/inge-earth-project-engine.js"]);
  assert(html.includes("geocoder: false"));
  for (const f of fs.readdirSync(engineDir)) {
    const src = fs.readFileSync(path.join(engineDir, f), "utf8");
    assert(!/getElementById|querySelector|createElement|innerHTML|textContent|classList/.test(src), f + " usa DOM");
  }
});
check("URL XYZ del mapa base", () => {
  assert.strictEqual(M.normalizedXyzUrl(""), "");
  assert.strictEqual(M.normalizedXyzUrl("https://t.x/tiles///"), "https://t.x/tiles/{z}/{x}/{y}.png");
  assert.strictEqual(M.normalizedXyzUrl("https://t.x/{Z}/a"), "https://t.x/{Z}/a");
});
check("decodificación polyline6 de Valhalla", () => {
  assert.deepStrictEqual(plain(M.decodePolyline6("_p~iF~ps|U_ulLnnqC_mqNvxq`@")),
    [[-12.02, 3.85], [-12.095, 4.07], [-12.6453, 4.3252]]);
  assert.deepStrictEqual(plain(M.decodePolyline6("")), []);
  assert.throws(() => M.decodePolyline6("_"), /INVALID_ROUTE_SHAPE/);
});
check("fix GPS nativo normalizado", () => {
  assert.deepStrictEqual(plain(M.normalizeLocationFix({ latitude: -12.04, longitude: -77.03, altitude: 150, accuracy: 4.2,
    timestampMs: 1760000000000, provider: "gps" })), { latitude: -12.04, longitude: -77.03, height: 150, accuracy: 4.2,
    timestamp: "2025-10-09T08:53:20.000Z", source: "InGe Earth GPS (gps)" });
  assert.strictEqual(M.normalizeLocationFix({ latitude: "x", longitude: 1 }), null);
  assert.strictEqual(M.normalizeLocationFix({ latitude: 1, longitude: 2 }, 0).timestamp, "1970-01-01T00:00:00.000Z");
  assert.strictEqual(M.isFinalFix({ final: true }, 40), true);
  assert.strictEqual(M.isFinalFix({}, 5), true);
  assert.strictEqual(M.isFinalFix({}, 5.1), false);
});
check("modelo de proyecto y capas", () => {
  const p = P.createProjectModel("Obra", "");
  assert.deepStrictEqual(plain(p.layers.map((l) => l.kind)), ["POINT", "POLYLINE", "POLYGON", "MEASUREMENT", "IMPORTED"]);
  assert.strictEqual(P.featureCount({ features: [1, 2], measurements: [3], imports: [4] }), 4);
  assert.strictEqual(P.defaultLayerName("X"), "Importados");
  assert.strictEqual(P.nextFeatureName(p, "POINT"), "Puntos 1");
  const layer = P.applyLayerStyle(P.createLayer("L", "POINT"), { color: "#fff", width: "40", opacity: "150" });
  assert.deepStrictEqual(plain([layer.style.width, layer.opacity]), [12, 1]);
  P.applyLayerStyle(layer, { color: "#fff", width: "x", opacity: "-5" });
  assert.deepStrictEqual(plain([layer.style.width, layer.opacity]), [4, 0]);
  assert.strictEqual(P.toggleLayerVisibility(layer), false);
  assert.strictEqual(P.minimumVertices("POLYGON"), 3);
});
check("metadatos GPS, nombres de archivo y MIME de exportación", () => {
  assert.deepStrictEqual(plain(P.gpsPointMetadata({ accuracy: 3, timestamp: "T", source: "S" })),
    { accuracy: 3, coordinateTimestamp: "T", coordinateSource: "S" });
  assert.strictEqual(P.gpsPointMetadata({ accuracy: 9, timestampMs: 1760000000000, provider: "fused" }).coordinateSource, "InGe Earth GPS (fused)");
  assert.strictEqual(P.sanitizeFilename('a/b:c*d?"e<f>g|h  i'), "a_b_c_d__e_f_g_h_i");
  assert.strictEqual(P.sanitizeFilename(""), "Proyecto");
  assert.strictEqual(P.exportMime(true), "application/vnd.google-earth.kmz");
  assert.strictEqual(P.isKmlName("Mapa.KMZ"), true);
  assert.strictEqual(P.isKmlName("mapa.zip"), false);
});
check("coordenadas UTM/WGS84 (búsqueda)", () => {
  const wgs = C.parse("-12.046374, -77.042793");
  assert.strictEqual(Math.round(wgs.latitude * 1e6), -12046374);
  assert.strictEqual(C.formatUtm({ latitude: -12.046374, longitude: -77.042793 }).startsWith("UTM 18S"), true);
});
console.log(`EARTH_ENGINE_STATIC_OK ${passed}`);

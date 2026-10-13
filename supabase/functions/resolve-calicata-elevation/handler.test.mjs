// node supabase/functions/resolve-calicata-elevation/handler.test.mjs
// Reglas, validación de Gemini y contrato HTTP con dependencias simuladas; el
// último caso lee el Copernicus DEM real (se omite con INGE_SKIP_NETWORK=1).
import assert from 'node:assert/strict';
import { createHandler, decide, validateAssessment, allowedNumbers } from './handler.mjs';
import { sampleCopernicus } from './copernicus.mjs';

const ENV = { SUPABASE_URL: 'https://dev.example', SUPABASE_ANON_KEY: 'anon', GEMINI_API_KEY: 'gemini-test' };
const env = (extra = {}) => (name) => ({ ...ENV, ...extra })[name];
// C-AB-01: 18L 661554 E 8561476 N -> -13.008278, -73.510320; lecturas reales 2026-10-07.
const CAB01 = { latitude: -13.008278, longitude: -73.510320 };
const fakeSample = (values) => async (dataset) => {
  const v = values[dataset.id];
  if (v instanceof Error) throw v;
  return v === undefined ? null : v;
};
function fakeFetch({ user = 200, quota = true, gemini = null, google = null, realDem = false } = {}) {
  const calls = [];
  const fetcher = async (url, init = {}) => {
    calls.push({ url, body: init.body });
    if (url.endsWith('/auth/v1/user')) return new Response('{}', { status: user });
    if (url.endsWith('/rpc/consume_inge_gemini_quota')) return new Response(JSON.stringify(quota), { status: 200 });
    if (url.includes('generativelanguage.googleapis.com')) {
      if (!gemini) return new Response('{}', { status: 503 });
      return new Response(JSON.stringify({ candidates: [{ content: { parts: [{ text: JSON.stringify(gemini) }] } }] }), { status: 200 });
    }
    if (url.includes('maps.googleapis.com')) return new Response(JSON.stringify(google), { status: 200 });
    if (realDem && url.includes('.s3.eu-central-1.amazonaws.com/')) return fetch(url, init);   // Copernicus real
    return new Response('', { status: 404 });
  };
  return { fetcher, calls };
}
const request = (body, auth = 'Bearer user-jwt') => new Request('https://fn/resolve-calicata-elevation',
  { method: 'POST', headers: auth ? { Authorization: auth } : {}, body: JSON.stringify(body) });
const run = async (body, opts = {}) => {
  const { fetcher, calls } = fakeFetch(opts);
  const handler = createHandler({ env: env(opts.env), fetcher, sample: opts.sample || fakeSample({ copernicus_glo30: 706.4, copernicus_glo90: 707.4 }),
                                  now: () => new Date('2026-10-07T18:00:00Z'), log: () => {} });
  const response = await handler(request(body, opts.auth === undefined ? 'Bearer user-jwt' : opts.auth));
  return { status: response.status, data: await response.json(), calls };
};
let count = 0;
const test = async (name, fn) => { await fn(); ++count; console.log('PASS ' + name); };

await test('auth, entrada y cuota', async () => {
  assert.equal((await run(CAB01, { auth: '' })).status, 401);
  assert.equal((await run(CAB01, { user: 401 })).status, 401);
  assert.equal((await run({ latitude: 95, longitude: 0 })).status, 400);
  assert.equal((await run({ ...CAB01, gpsAltitude: 'abc' })).status, 400);
  assert.equal((await run(CAB01, { quota: false })).status, 429);
});

await test('7/8 · coordenadas -> backend -> evidencias guardables (C-AB-01)', async () => {
  const { status, data } = await run({ ...CAB01, gpsAltitude: 747, gpsAccuracy: 5, gpsVerticalReference: 'ellipsoid' });
  assert.equal(status, 200);
  assert.equal(data.elevation_m, 706.4);
  assert.equal(data.vertical_reference, 'terrain_msl');
  assert.equal(data.source, 'DEM');
  assert.equal(data.confidence, 'ALTA');
  assert.equal(data.accuracy_m, 4);
  assert.deepEqual(data.evidence.map((e) => [e.id, e.value, e.vertical_reference]),
                   [['copernicus_glo30', 706.4, 'terrain_msl'], ['copernicus_glo90', 707.4, 'terrain_msl'], ['device_gps', 747, 'ellipsoid']]);
  assert.ok(data.rationale_codes.includes('GPS_ELLIPSOIDAL_NOT_COMPARABLE'), 'GPS elipsoidal no se compara con m.s.n.m.');
  assert.equal(data.status, 'consistent', 'una altura elipsoidal no genera discrepancia');
  assert.match(data.attribution, /COPERNICUS/);
  assert.equal(data.resolved_at, '2026-10-07T18:00:00.000Z');
});

await test('10 · discrepancia con la referencia 747 => aviso', async () => {
  const { data } = await run({ ...CAB01, referenceAltitude: 747, referenceSource: 'Cota manual de la ficha' });
  assert.equal(data.elevation_m, 706.4, 'el número sigue saliendo de las evidencias');
  assert.equal(data.status, 'discrepant');
  assert.equal(data.confidence, 'MEDIA');
  assert.ok(data.rationale_codes.includes('REFERENCE_DIFFERS'));
  assert.equal(data.warning, 'La referencia indica 747 m. Existe una diferencia de 41 m con la cota automática (706.4 m).');
  // Fuentes de terreno en desacuerdo => BAJA + aviso.
  const split = await run(CAB01, { sample: fakeSample({ copernicus_glo30: 706.4, copernicus_glo90: 760 }) });
  assert.equal(split.data.confidence, 'BAJA');
  assert.equal(split.data.status, 'discrepant');
  assert.match(split.data.warning, /difieren 54 m/);
});

await test('9 · Gemini nunca aporta una cifra ausente de las evidencias', async () => {
  // Inventa 735: se descarta su evaluación; el número y el aviso son de las reglas.
  const invented = await run({ ...CAB01, referenceAltitude: 747 }, { gemini: {
    status: 'discrepant', preferredSource: 'copernicus_glo30', rationaleCode: 'REFERENCE_DIFFERS', warning: 'La cota real es 735 m.' } });
  assert.equal(invented.data.assessment.by, 'rules');
  assert.equal(invented.data.assessment.rejected, 'NUMBER_NOT_IN_EVIDENCE');
  assert.equal(invented.data.elevation_m, 706.4);
  assert.ok(!JSON.stringify(invented.data).includes('735'));
  // Intenta devolver una elevación: el esquema no la admite y se ignora.
  const sneaky = await run(CAB01, { gemini: { status: 'consistent', preferredSource: 'copernicus_glo30',
    rationaleCode: 'SOURCES_AGREE', warning: '', elevation_m: 812 } });
  assert.equal(sneaky.data.assessment.by, 'gemini');
  assert.equal(sneaky.data.elevation_m, 706.4);
  assert.ok(!JSON.stringify(sneaky.data).includes('812'));
  // Fuente preferida inexistente => rechazada.
  assert.equal(validateAssessment({ status: 'consistent', preferredSource: 'srtm_inventado', rationaleCode: 'SOURCES_AGREE', warning: '' },
    [{ id: 'copernicus_glo30', value: 706.4, vertical_reference: 'terrain_msl' }]).reason, 'PREFERRED_NOT_IN_EVIDENCE');
  // Cifras citables: valores, diferencias y precisiones de las evidencias.
  const allowed = allowedNumbers([{ id: 'a', value: 706.4, vertical_reference: 'terrain_msl', accuracy_m: 4 }, { id: 'b', value: 747 }]);
  for (const n of ['706.4', '706', '747', '41', '40.6', '4']) assert.ok(allowed.has(n), n);
  // Gemini válido puede ENDURECER el estado (más severo), nunca relajarlo.
  const stricter = await run(CAB01, { gemini: { status: 'discrepant', preferredSource: 'copernicus_glo90',
    rationaleCode: 'SOURCES_DISAGREE', warning: 'Revisa: 706.4 m y 707.4 m provienen del mismo productor.' } });
  assert.equal(stricter.data.status, 'discrepant');
  assert.equal(stricter.data.elevation_m, 706.4);
  const relaxed = await run({ ...CAB01, referenceAltitude: 747 }, { gemini: { status: 'consistent', preferredSource: 'copernicus_glo30',
    rationaleCode: 'SOURCES_AGREE', warning: '' } });
  assert.equal(relaxed.data.status, 'discrepant', 'Gemini no puede ocultar una discrepancia de las reglas');
  // El prompt solo lleva evidencias numéricas (sin coordenadas ni datos del proyecto).
  const gem = relaxed.calls.find((c) => c.url.includes('generativelanguage'));
  assert.ok(gem && !gem.body.includes('-13.008278') && !gem.body.includes('-73.51032'));
});

await test('Google Elevation (si hay clave de servidor) es la fuente preferida', async () => {
  const { data, calls } = await run(CAB01, { env: { GOOGLE_MAPS_ELEVATION_API_KEY: 'server-key' },
    google: { status: 'OK', results: [{ elevation: 709.2, resolution: 19.1 }] } });
  assert.equal(data.source, 'GOOGLE_ELEVATION');
  assert.equal(data.elevation_m, 709.2);
  assert.equal(data.provider, 'Google Maps Elevation API');
  assert.ok(calls.some((c) => c.url.startsWith('https://maps.googleapis.com/maps/api/elevation/json?locations=-13.0082780,-73.5103200&key=')));
  assert.ok(!JSON.stringify(data).includes('server-key'), 'la clave nunca sale en la respuesta');
});

await test('11 · fuentes caídas => sin cota (manual), sin cifras inventadas', async () => {
  const { status, data } = await run({ ...CAB01, gpsAltitude: 747 },
    { sample: fakeSample({ copernicus_glo30: new Error('DEM_HTTP_503'), copernicus_glo90: null }) });
  assert.equal(status, 200);
  assert.equal(data.elevation_m, null);
  assert.equal(data.status, 'insufficient');
  assert.match(data.warning, /Ingresa la cota manualmente/);
  assert.deepEqual(data.failures, [{ id: 'copernicus_glo30', code: 'DEM_HTTP_503' }]);
  assert.equal(data.assessment.by, 'rules');
  assert.equal(decide([]).elevation_m, null);
});

await test('lectura REAL del Copernicus DEM (C-AB-01)', async () => {
  if (process.env.INGE_SKIP_NETWORK === '1') { console.log('  (omitido)'); return; }
  try {
    const { data } = await run({ ...CAB01, referenceAltitude: 747 }, { sample: sampleCopernicus, realDem: true });
    console.log('  evidencias reales:', JSON.stringify(data.evidence.map((e) => [e.id, e.value])), '→', data.elevation_m, data.status, '|', data.warning);
    assert.ok(data.elevation_m > 690 && data.elevation_m < 725, 'valle del río (no se fuerza 747)');
    assert.equal(data.status, 'discrepant');
  } catch (error) {
    if (/fetch failed|ENOTFOUND|ECONN/.test(String(error))) { console.log('  (sin red)'); return; }
    throw error;
  }
});

console.log(count + ' casos resolve-calicata-elevation OK');

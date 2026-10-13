// resolve-calicata-elevation — cota del terreno para una calicata.
//
//   coordenadas ─┬─ Google Maps Elevation API   (si GOOGLE_MAPS_ELEVATION_API_KEY está configurada)
//                ├─ Copernicus DEM GLO-30 (ESA)  (AWS Open Data, lectura directa del COG)
//                ├─ Copernicus DEM GLO-90 (ESA)  (validación cruzada)
//                ├─ GPS del teléfono (opcional; referencia vertical declarada)
//                └─ cota actual de la ficha (opcional; referencia a contrastar)
//                        │ evidencias estructuradas
//                        ▼
//          reglas deterministas ── eligen elevation_m SOLO entre las evidencias de terreno
//                        │
//                        ▼
//          Gemini (validador, salida JSON con esquema) ── clasifica consistencia y
//          redacta el aviso; NO puede aportar ni cambiar ninguna cifra: su aviso se
//          descarta si contiene un número que no esté en las evidencias.
//
// Privacidad: las coordenadas nunca salen hacia Gemini con datos del proyecto
// (solo números de las evidencias); Copernicus se lee como archivo público (rango
// HTTP del tile de 1°×1°), sin API de terceros ni clave. Las claves viven solo en
// los secretos de la Edge Function.
import { COPERNICUS_ATTRIBUTION, DATASETS, sampleCopernicus as defaultSample } from './copernicus.mjs';

export const TERRAIN_AGREEMENT_M = 15;      // GLO-30 vs GLO-90 vs Google
export const REFERENCE_DISCREPANCY_M = 10;  // cota de la ficha / referencia vs terreno
const STATUS = ['consistent', 'discrepant', 'insufficient'];
const RATIONALE = ['SOURCES_AGREE', 'SOURCES_DISAGREE', 'REFERENCE_DIFFERS', 'GPS_ELLIPSOIDAL_NOT_COMPARABLE',
                   'SINGLE_SOURCE', 'NO_TERRAIN_SOURCE'];
const DEFAULT_MODEL = 'gemini-3.8-flash';
const SEVERITY = { consistent: 0, discrepant: 1, insufficient: 2 };

const json = (body, status = 200) => new Response(JSON.stringify(body),
  { status, headers: { 'Content-Type': 'application/json', 'Cache-Control': 'no-store' } });
const finite = (v) => typeof v === 'number' ? Number.isFinite(v) : (v !== null && v !== undefined && v !== '' && Number.isFinite(Number(v)));
const round1 = (v) => Math.round(v * 10) / 10;

export function validateInput(body) {
  if (!body || typeof body !== 'object') return 'Solicitud inválida.';
  const lat = Number(body.latitude), lon = Number(body.longitude);
  if (!finite(body.latitude) || !finite(body.longitude) || lat < -80 || lat > 84 || Math.abs(lon) > 180)
    return 'Coordenadas fuera de rango.';
  for (const key of ['gpsAltitude', 'gpsAccuracy', 'referenceAltitude'])
    if (body[key] !== undefined && body[key] !== null && body[key] !== '' && !finite(body[key])) return `${key} inválido.`;
  if (body.gpsVerticalReference !== undefined && !['ellipsoid', 'unknown', 'terrain_msl'].includes(body.gpsVerticalReference))
    return 'gpsVerticalReference inválido.';
  return '';
}

// ------------------------------------------------------------------ evidencias
async function googleElevation(apiKey, lat, lon, fetcher) {
  const url = `https://maps.googleapis.com/maps/api/elevation/json?locations=${lat.toFixed(7)},${lon.toFixed(7)}&key=${encodeURIComponent(apiKey)}`;
  const response = await fetcher(url, { signal: AbortSignal.timeout(8000) });
  const data = await response.json();
  const row = data && data.status === 'OK' && data.results && data.results[0];
  if (!row || !finite(row.elevation)) throw new Error(`GOOGLE_${data && data.status || response.status}`);
  return { id: 'google_elevation', provider: 'Google Maps Elevation API', value: round1(row.elevation),
           vertical_reference: 'terrain_msl', resolution_m: finite(row.resolution) ? round1(row.resolution) : null, accuracy_m: null };
}

export async function collectEvidence(input, { env, fetcher, sample }) {
  const lat = Number(input.latitude), lon = Number(input.longitude);
  const failures = [];
  const tasks = [];
  const googleKey = env('GOOGLE_MAPS_ELEVATION_API_KEY');
  if (googleKey) tasks.push(googleElevation(googleKey, lat, lon, fetcher).catch((e) => { failures.push({ id: 'google_elevation', code: String(e.message).slice(0, 60) }); return null; }));
  for (const dataset of [DATASETS.glo30, DATASETS.glo90]) {
    tasks.push(sample(dataset, lat, lon, fetcher, 8000).then((value) => value === null ? null : {
      id: dataset.id, provider: `${dataset.label} (ESA, AWS Open Data)`, value, vertical_reference: 'terrain_msl',
      resolution_m: dataset.resolution_m, accuracy_m: dataset.accuracy_m,
    }).catch((e) => { failures.push({ id: dataset.id, code: String(e.message).slice(0, 60) }); return null; }));
  }
  const evidence = (await Promise.all(tasks)).filter(Boolean);
  if (finite(input.gpsAltitude))
    evidence.push({ id: 'device_gps', provider: 'GPS del dispositivo', value: round1(Number(input.gpsAltitude)),
                    vertical_reference: input.gpsVerticalReference || 'ellipsoid', resolution_m: null,
                    accuracy_m: finite(input.gpsAccuracy) ? round1(Number(input.gpsAccuracy)) : null });
  if (finite(input.referenceAltitude))
    evidence.push({ id: 'sheet_reference', provider: String(input.referenceSource || 'Cota actual de la ficha').slice(0, 60),
                    value: round1(Number(input.referenceAltitude)), vertical_reference: 'unknown', resolution_m: null, accuracy_m: null });
  return { evidence, failures };
}

// ------------------------------------------------------------------ reglas deterministas
const TERRAIN_PRIORITY = ['google_elevation', 'copernicus_glo30', 'copernicus_glo90'];

export function decide(evidence) {
  const terrain = TERRAIN_PRIORITY.map((id) => evidence.find((e) => e.id === id)).filter(Boolean);
  const reference = evidence.find((e) => e.id === 'sheet_reference');
  const gps = evidence.find((e) => e.id === 'device_gps');
  const codes = [];
  if (!terrain.length) {
    return { elevation_m: null, chosen: null, status: 'insufficient', confidence: null, codes: ['NO_TERRAIN_SOURCE'],
             warning: 'No se obtuvo la elevación del terreno. Ingresa la cota manualmente.' };
  }
  const chosen = terrain[0];
  const values = terrain.map((e) => e.value);
  const spread = Math.max(...values) - Math.min(...values);
  let status = 'consistent';
  let confidence = terrain.length >= 2 ? 'ALTA' : 'MEDIA';
  const warnings = [];
  if (terrain.length >= 2 && spread > TERRAIN_AGREEMENT_M) {
    status = 'discrepant'; confidence = 'BAJA'; codes.push('SOURCES_DISAGREE');
    warnings.push(`Las fuentes de elevación difieren ${Math.round(spread)} m (${terrain.map((e) => `${e.value} m`).join(' / ')}).`);
  } else codes.push(terrain.length >= 2 ? 'SOURCES_AGREE' : 'SINGLE_SOURCE');
  if (reference && Math.abs(reference.value - chosen.value) > REFERENCE_DISCREPANCY_M) {
    status = 'discrepant';
    if (confidence === 'ALTA') confidence = 'MEDIA';
    codes.push('REFERENCE_DIFFERS');
    warnings.push(`La referencia indica ${reference.value} m. Existe una diferencia de ${Math.round(Math.abs(reference.value - chosen.value))} m con la cota automática (${chosen.value} m).`);
  }
  // Altura elipsoidal: no comparable con m.s.n.m. sin ondulación del geoide.
  if (gps && gps.vertical_reference === 'ellipsoid') codes.push('GPS_ELLIPSOIDAL_NOT_COMPARABLE');
  return { elevation_m: chosen.value, chosen, status, confidence, codes, warning: warnings.join(' ') };
}

// Todas las cifras que un texto puede citar: valores, diferencias y precisiones de las evidencias.
export function allowedNumbers(evidence) {
  const set = new Set();
  const add = (v) => { if (finite(v)) { set.add(String(Math.round(v))); set.add(String(round1(v))); } };
  for (const e of evidence) { add(e.value); add(e.accuracy_m); add(e.resolution_m); }
  for (const a of evidence) for (const b of evidence) if (a !== b) add(Math.abs(a.value - b.value));
  return set;
}

// Valida la respuesta de Gemini: solo enums y un aviso sin cifras ajenas a las evidencias.
export function validateAssessment(raw, evidence) {
  if (!raw || typeof raw !== 'object') return { ok: false, reason: 'NOT_JSON' };
  if (!STATUS.includes(raw.status)) return { ok: false, reason: 'BAD_STATUS' };
  const terrainIds = evidence.filter((e) => e.vertical_reference === 'terrain_msl').map((e) => e.id);
  const preferred = raw.preferredSource === 'none' || terrainIds.includes(raw.preferredSource) ? raw.preferredSource : null;
  if (preferred === null) return { ok: false, reason: 'PREFERRED_NOT_IN_EVIDENCE' };
  const rationale = RATIONALE.includes(raw.rationaleCode) ? raw.rationaleCode : null;
  if (!rationale) return { ok: false, reason: 'BAD_RATIONALE' };
  let warning = typeof raw.warning === 'string' ? raw.warning.trim().slice(0, 240) : '';
  const allowed = allowedNumbers(evidence);
  const cited = warning.match(/\d+(?:[.,]\d+)?/g) || [];
  if (cited.some((n) => !allowed.has(n.replace(',', '.')))) return { ok: false, reason: 'NUMBER_NOT_IN_EVIDENCE' };
  return { ok: true, status: raw.status, preferredSource: preferred, rationaleCode: rationale, warning };
}

const SYSTEM = 'Eres el validador de cotas de InGe+ (INGEMA). Recibes EVIDENCIAS numéricas de fuentes de elevación. '
  + 'No calculas ni estimas altitudes. Clasifica si las evidencias son consistentes, elige una fuente de terreno de la lista '
  + 'o "none", y redacta un aviso breve en español solo con cifras que aparezcan en las evidencias. Una altura GPS '
  + 'elipsoidal no es comparable con m.s.n.m.';

export async function assessWithGemini(evidence, rules, { env, fetcher }) {
  const apiKey = env('GEMINI_API_KEY');
  if (!apiKey) return { by: 'rules', skipped: 'NO_GEMINI_KEY' };
  const model = env('GEMINI_ELEVATION_MODEL') || DEFAULT_MODEL;
  const terrainIds = evidence.filter((e) => e.vertical_reference === 'terrain_msl').map((e) => e.id);
  const payload = {
    systemInstruction: { parts: [{ text: SYSTEM }] },
    contents: [{ role: 'user', parts: [{ text: JSON.stringify({
      evidence: evidence.map(({ id, value, vertical_reference, accuracy_m, resolution_m }) => ({ id, value, vertical_reference, accuracy_m, resolution_m })),
      terrain_agreement_m: TERRAIN_AGREEMENT_M, reference_discrepancy_m: REFERENCE_DISCREPANCY_M, rules_codes: rules.codes,
    }) }] }],
    generationConfig: { temperature: 0, responseMimeType: 'application/json', responseSchema: {
      type: 'OBJECT', required: ['status', 'preferredSource', 'rationaleCode', 'warning'],
      properties: {
        status: { type: 'STRING', enum: STATUS },
        preferredSource: { type: 'STRING', enum: [...terrainIds, 'none'] },
        rationaleCode: { type: 'STRING', enum: RATIONALE },
        warning: { type: 'STRING' },
      } } },
  };
  try {
    const response = await fetcher(`https://generativelanguage.googleapis.com/v1beta/models/${encodeURIComponent(model)}:generateContent`, {
      method: 'POST', headers: { 'Content-Type': 'application/json', 'x-goog-api-key': apiKey },
      body: JSON.stringify(payload), signal: AbortSignal.timeout(7000),
    });
    if (!response.ok) return { by: 'rules', skipped: `GEMINI_HTTP_${response.status}` };
    const data = await response.json();
    const text = data?.candidates?.[0]?.content?.parts?.map((p) => p.text || '').join('') || '';
    let parsed = null;
    try { parsed = JSON.parse(text); } catch { parsed = null; }
    const verdict = validateAssessment(parsed, evidence);
    return verdict.ok ? { by: 'gemini', model, ...verdict } : { by: 'rules', model, rejected: verdict.reason };
  } catch (failure) {
    return { by: 'rules', skipped: failure?.name === 'TimeoutError' ? 'GEMINI_TIMEOUT' : 'GEMINI_UNREACHABLE' };
  }
}

// ------------------------------------------------------------------ handler HTTP
export function createHandler({ env, fetcher = fetch, sample = defaultSample, now = () => new Date(), log = console.log }) {
  return async (request) => {
    if (request.method !== 'POST') return json({ error: 'Método no permitido.' }, 405);
    const url = env('SUPABASE_URL'), anon = env('SUPABASE_ANON_KEY');
    const authorization = request.headers.get('Authorization') || '';
    if (!url || !anon) return json({ error: 'Servicio no configurado.' }, 503);
    if (!/^Bearer\s+\S+$/.test(authorization)) return json({ error: 'Inicia sesión.' }, 401);
    const headers = { Authorization: authorization, apikey: anon, 'Content-Type': 'application/json' };
    try {
      const user = await fetcher(`${url}/auth/v1/user`, { headers, signal: AbortSignal.timeout(10000) });
      if (!user.ok) return json({ error: 'La sesión venció. Vuelve a iniciar sesión.' }, 401);
      let body = null;
      try { body = await request.json(); } catch { body = null; }
      const invalid = validateInput(body);
      if (invalid) return json({ error: invalid }, 400);
      const quota = await fetcher(`${url}/rest/v1/rpc/consume_inge_gemini_quota`, {
        method: 'POST', headers, body: JSON.stringify({ p_operation: 'elevation' }), signal: AbortSignal.timeout(10000),
      }).then(async (r) => r.ok ? await r.json() : null).catch(() => null);
      if (quota === false) return json({ error: 'Llegaste al límite de consultas de altitud. Espera un minuto.', code: 'RATE_LIMIT' }, 429);
      const started = Date.now();
      const { evidence, failures } = await collectEvidence(body, { env, fetcher, sample });
      const rules = decide(evidence);
      // Sin cuota confirmada no se llama a Gemini; las reglas siguen siendo la autoridad.
      const assessment = quota === true && evidence.some((e) => e.vertical_reference === 'terrain_msl')
        ? await assessWithGemini(evidence, rules, { env, fetcher }) : { by: 'rules', skipped: quota === true ? 'NO_TERRAIN' : 'QUOTA_UNAVAILABLE' };
      // Estado final = el más severo; el número SIEMPRE sale de las reglas (evidencias).
      const status = assessment.by === 'gemini' && SEVERITY[assessment.status] > SEVERITY[rules.status] ? assessment.status : rules.status;
      const warning = rules.warning || (assessment.by === 'gemini' && status !== 'consistent' ? assessment.warning : '');
      const chosen = rules.chosen;
      log(`INGE_ELEVATION_RESOLVED status=${status} source=${chosen ? chosen.id : 'none'} evidence=${evidence.length} failures=${failures.map((f) => f.id + ':' + f.code).join(',') || 'none'} by=${assessment.by}${assessment.rejected ? ' rejected=' + assessment.rejected : ''}${assessment.skipped ? ' skipped=' + assessment.skipped : ''} ms=${Date.now() - started}`);
      return json({
        ok: true,
        elevation_m: rules.elevation_m,
        vertical_reference: chosen ? 'terrain_msl' : 'unknown',
        source: chosen ? (chosen.id === 'google_elevation' ? 'GOOGLE_ELEVATION' : 'DEM') : '',
        provider: chosen ? chosen.provider : '',
        confidence: rules.confidence,
        accuracy_m: chosen ? chosen.accuracy_m : null,
        status, warning, rationale_codes: rules.codes,
        evidence, failures,
        assessment: { by: assessment.by, model: assessment.model || null, status: assessment.status || null,
                      preferredSource: assessment.preferredSource || null, rationaleCode: assessment.rationaleCode || null,
                      rejected: assessment.rejected || null, skipped: assessment.skipped || null },
        attribution: evidence.some((e) => e.id.startsWith('copernicus_')) ? COPERNICUS_ATTRIBUTION : '',
        resolved_at: now().toISOString(),
      });
    } catch (failure) {
      log(`INGE_ELEVATION_FAILED class=${failure?.name || 'Error'}`);
      return json({ error: 'No se pudo resolver la altitud. Ingresa la cota manualmente.' }, 502);
    }
  };
}

import { test } from 'node:test';
import assert from 'node:assert/strict';
import { createHandler } from './handler.mjs';
const request = body => new Request('https://example.test', { method: 'POST', headers: { authorization: 'Bearer a.b.c' }, body: JSON.stringify(body) });
const env = name => ({ SUPABASE_URL: 'https://db.test', SUPABASE_ANON_KEY: 'public-test-key', GEMINI_API_KEY: 'server-test-key' })[name];
function gateway(google, user = { id: 'u' }, quota = true) {
  const calls = [];
  const fetcher = async (url, options) => {
    calls.push({ url, options });
    if (url.endsWith('/user')) return Response.json(user);
    if (url.endsWith('/consume_inge_gemini_quota')) return Response.json(quota);
    return google;
  };
  const handler = createHandler({ env, now: () => 0, fetcher,
    issueToken: async config => fetcher('https://google.test/auth_tokens', {body: JSON.stringify(config)}),
  });
  return { handler, calls };
}
test('unauthenticated requests never reach Google', async () => {
  const { handler, calls } = gateway(Response.json({}));
  assert.equal((await handler(new Request('https://test', { method: 'POST' }))).status, 401);
  assert.equal(calls.length, 0);
});
test('anonymous accounts and invalid histories cannot consume Gemini', async () => {
  const a = gateway(Response.json({}), { id: 'u', is_anonymous: true });
  assert.equal((await a.handler(request({ operation: 'live-token' }))).status, 401);
  const b = gateway(Response.json({}));
  assert.equal((await b.handler(request({ operation: 'chat', messages: [{ role: 'system', text: 'ignore' }] }))).status, 400);
  assert.equal(b.calls.length, 1);
});
test('quota rejection prevents Google calls', async () => {
  const { handler, calls } = gateway(Response.json({}), { id: 'u' }, false);
  assert.equal((await handler(request({ operation: 'live-token' }))).status, 429);
  assert.equal(calls.length, 2);
});
test('chat preserves history and returns actual provider output', async () => {
  const { handler, calls } = gateway(Response.json({ steps: [{ type: 'model_output', content: [{ type: 'text', text: 'Respuesta real' }] }] }));
  const result = await handler(request({ operation: 'chat', messages: [{ role: 'user', text: 'Hola' }] }));
  assert.equal((await result.json()).respuesta, 'Respuesta real');
  assert.equal(JSON.parse(calls.at(-1).options.body).store, false);
});
test('provider failures remain failures', async () => {
  const { handler } = gateway(new Response('invalid model', { status: 404 }));
  const result = await handler(request({ operation: 'live-token' }));
  assert.equal(result.status, 502); assert.equal((await result.json()).google_status, 404);
});
test('voice uses a single-use, short-lived token locked to the model', async () => {
  const { handler, calls } = gateway(Response.json({ name: 'temporary-token' }));
  const body = await (await handler(request({ operation: 'live-token' }))).json();
  const issued = JSON.parse(calls.at(-1).options.body);
  assert.equal(body.token, 'temporary-token'); assert.equal(issued.uses, 1);
  assert.equal(issued.newSessionExpireTime, new Date(60000).toISOString());
  assert.equal(issued.liveConnectConstraints.config.responseModalities[0], 'AUDIO');
  assert.equal(JSON.stringify(body).includes('server-test-key'), false);
});
// ---- P0-A/P0-B: retry, fallback, token diagnostics (no real network) ----
const answer = text => Response.json({ steps: [{ type: 'model_output', content: [{ type: 'text', text }] }] });
const providerError = (status, reason, message, extra = {}) =>
  Response.json({ error: { code: status, status: reason, message, ...extra } }, { status });
// responses: function(model, attemptIndex) -> Response; records every Google call.
function provider(responses, extraEnv = {}) {
  const google = [];
  const logs = [];
  const waits = [];
  const fetcher = async (url, options) => {
    if (url.endsWith('/user')) return Response.json({ id: 'u' });
    if (url.endsWith('/consume_inge_gemini_quota')) { provider.quota = (provider.quota ?? 0) + 1; return Response.json(true); }
    const sent = JSON.parse(options.body);
    google.push(sent);
    return responses(sent.model, google.length - 1);
  };
  const handler = createHandler({ env: name => name in extraEnv ? extraEnv[name] : env(name), now: () => 0, fetcher,
    random: () => 0.5, sleep: async ms => { waits.push(ms); }, log: line => logs.push(line),
    issueToken: async (config, key) => { google.push({ config, keyUsed: key === 'server-test-key' }); return responses('live', google.length - 1, config); } });
  return { handler, google, logs, waits };
}
const history = [{ role: 'user', text: 'hola' }, { role: 'assistant', text: 'Hola, ¿en qué te ayudo?' }, { role: 'user', text: '¿Cómo completo una calicata?' }];
const chat = () => request({ operation: 'chat', messages: history });
const live = () => request({ operation: 'live-token' });

test('CHAT: 200 on the primary model answers with one call', async () => {
  const p = provider(() => answer('Pasos'));
  const result = await p.handler(chat()); const body = await result.json();
  assert.equal(result.status, 200); assert.equal(body.respuesta, 'Pasos'); assert.equal(body.model, 'gemini-3.8-flash');
  assert.equal(p.google.length, 1); assert.equal(p.google[0].model, 'gemini-3.8-flash');
  assert.ok(p.logs.includes('INGE_AI_CHAT_ATTEMPT model=gemini-3.8-flash attempt=1'));
  assert.ok(p.logs.some(l => l.startsWith('INGE_AI_CHAT_OK model=gemini-3.8-flash')));
});
test('CHAT: primary 503 -> retry -> 200, short jittered backoff', async () => {
  const p = provider((model, i) => i === 0 ? providerError(503, 'UNAVAILABLE', 'overloaded') : answer('Pasos'));
  const body = await (await p.handler(chat())).json();
  assert.equal(body.respuesta, 'Pasos'); assert.equal(p.google.length, 2);
  assert.deepEqual(p.google.map(g => g.model), ['gemini-3.8-flash', 'gemini-3.8-flash']);
  assert.ok(p.waits[0] >= 350 && p.waits[0] <= 600);
  assert.ok(p.logs.includes('INGE_AI_CHAT_RETRY status=503 attempt=1 wait_ms=475'));
});
test('CHAT: persistent primary 503 -> fallback model -> 200', async () => {
  const p = provider(model => model === 'gemini-3.8-flash' ? providerError(503, 'UNAVAILABLE', 'overloaded') : answer('Desde respaldo'));
  const result = await p.handler(chat()); const body = await result.json();
  assert.equal(result.status, 200); assert.equal(body.respuesta, 'Desde respaldo'); assert.equal(body.model, 'gemini-3.6-flash');
  assert.deepEqual(p.google.map(g => g.model), ['gemini-3.8-flash', 'gemini-3.8-flash', 'gemini-3.8-flash', 'gemini-3.6-flash']);
  assert.ok(p.logs.includes('INGE_AI_CHAT_FALLBACK from=gemini-3.8-flash to=gemini-3.6-flash status=503'));
  assert.ok(p.waits[1] >= 800 && p.waits[1] <= 1300);
});
test('CHAT: 429 is retried and can fall back as well', async () => {
  const p = provider(model => model === 'gemini-3.8-flash' ? providerError(429, 'RESOURCE_EXHAUSTED', 'busy') : answer('ok'));
  const body = await (await p.handler(chat())).json();
  assert.equal(body.respuesta, 'ok'); assert.equal(p.google.length, 4);
});
test('CHAT: 400 is permanent: no retry, no fallback', async () => {
  const p = provider(() => providerError(400, 'INVALID_ARGUMENT', 'bad'));
  const result = await p.handler(chat()); const body = await result.json();
  assert.equal(result.status, 502); assert.equal(p.google.length, 1); assert.equal(p.waits.length, 0);
  assert.equal(body.retryable, false); assert.equal(body.provider_status, 400);
  assert.ok(p.logs.some(l => l.startsWith('INGE_AI_CHAT_FAIL status=400')));
});
test('CHAT: everything busy -> sanitized retryable failure, no secrets', async () => {
  const p = provider(() => providerError(503, 'UNAVAILABLE', 'Overloaded key=AIzaSyFAKEFAKEFAKEFAKE123 Bearer abc'));
  const result = await p.handler(chat()); const body = await result.json();
  assert.equal(result.status, 502); assert.equal(p.google.length, 5); assert.equal(body.attempts, 5);
  assert.equal(body.error, 'El servicio de IA está temporalmente ocupado. Intenta nuevamente.');
  assert.equal(body.code, 'GEMINI_UNAVAILABLE'); assert.equal(body.provider_status, 503); assert.equal(body.gateway_status, 502);
  assert.equal(body.retryable, true);
  const visible = JSON.stringify(body) + p.logs.join('\n');
  for (const secret of ['AIzaSy', 'server-test-key', 'Bearer abc', 'calicata']) assert.equal(visible.includes(secret), false, secret);
});
test('CHAT: one logical request: history sent once per attempt, quota consumed once, single answer', async () => {
  provider.quota = 0;
  const p = provider(model => model === 'gemini-3.8-flash' ? providerError(503, 'UNAVAILABLE', 'x') : answer('ok'));
  const body = await (await p.handler(chat())).json();
  assert.equal(provider.quota, 1);
  for (const sent of p.google) {
    assert.equal(sent.input.split('¿Cómo completo una calicata?').length - 1, 1);
    assert.equal(JSON.parse(sent.input.slice(sent.input.indexOf('\n') + 1)).length, history.length);
    assert.equal(sent.system_instruction.startsWith('Eres InGe+ IA'), true);
  }
  assert.equal(typeof body.respuesta, 'string');
});
test('CHAT: fallback can be disabled with an empty GEMINI_CHAT_FALLBACK_MODEL', async () => {
  const p = provider(() => providerError(503, 'UNAVAILABLE', 'x'), { GEMINI_CHAT_FALLBACK_MODEL: '' });
  await p.handler(chat());
  assert.equal(p.google.length, 3); assert.equal(p.google.every(g => g.model === 'gemini-3.8-flash'), true);
});
test('LIVE TOKEN: constraint model is exactly gemini-3.8-live and the token is returned', async () => {
  const p = provider(() => Response.json({ name: 'auth_tokens/abc' }));
  const body = await (await p.handler(live())).json();
  assert.equal(p.google[0].config.liveConnectConstraints.model, 'gemini-3.8-live');
  assert.equal(p.google[0].config.liveConnectConstraints.config.responseModalities[0], 'AUDIO');
  assert.equal(p.google[0].config.uses, 1);
  assert.equal(body.token, 'auth_tokens/abc'); assert.equal(body.model, 'gemini-3.8-live');
  assert.equal(JSON.stringify(body).includes('server-test-key'), false);
  assert.ok(p.logs.includes('INGE_AI_LIVE_TOKEN_START model=gemini-3.8-live'));
  assert.ok(p.logs.includes('INGE_AI_LIVE_TOKEN_OK attempts=1'));
  assert.equal(p.logs.join('').includes('auth_tokens/abc'), false);
});
test('LIVE TOKEN: 400 is not retried; sanitized structured failure', async () => {
  const p = provider(() => providerError(400, 'INVALID_ARGUMENT', 'bad constraint for key=AIzaSyFAKEFAKEFAKEFAKE1'));
  const result = await p.handler(live()); const body = await result.json();
  assert.equal(result.status, 502); assert.equal(p.google.length, 1);
  assert.equal(body.provider_status, 400); assert.equal(body.provider_reason, 'INVALID_ARGUMENT'); assert.equal(body.retryable, false);
  assert.equal(JSON.stringify(body).includes('AIzaSy') || p.logs.join('').includes('AIzaSy'), false);
  assert.ok(p.logs.some(l => l.startsWith('INGE_AI_LIVE_TOKEN_FAIL status=400 code=INVALID_ARGUMENT')));
});
test('LIVE TOKEN: 503 is retried, then succeeds', async () => {
  const p = provider((model, i) => i < 2 ? providerError(503, 'UNAVAILABLE', 'busy') : Response.json({ name: 'auth_tokens/ok' }));
  const body = await (await p.handler(live())).json();
  assert.equal(body.token, 'auth_tokens/ok'); assert.equal(p.google.length, 3);
  assert.ok(p.logs.includes('INGE_AI_LIVE_TOKEN_RETRY status=503 attempt=1 wait_ms=475'));
});

import { test } from 'node:test';
import assert from 'node:assert/strict';
const events = new EventTarget();
const sent = [];
globalThis.window = { addEventListener: events.addEventListener.bind(events), setTimeout, clearTimeout,
  InGeAssistantNative: { postMessage: json => sent.push(JSON.parse(json)) } };
const { nativeRequest, cancelPending, closeAssistant } = await import('./src/inge/nativeBridge.ts');
const reply = detail => events.dispatchEvent(new CustomEvent('inge-native', { detail }));
test('concurrent native replies resolve only their own request', async () => {
  const chat = nativeRequest('chat', { messages: [{role:'user', text:'Hola'}] });
  const live = nativeRequest('live-token');
  const [a, b] = sent.slice(-2);
  reply({id:b.id, token:'temporary'}); reply({id:a.id, respuesta:'Hola'});
  assert.equal((await live).token, 'temporary'); assert.equal((await chat).respuesta, 'Hola');
});
test('server errors reject and never appear as successful answers', async () => {
  const pending = nativeRequest('chat'); const id = sent.at(-1).id;
  reply({id, error:'Gemini rechazó la consulta (HTTP 429).'});
  await assert.rejects(pending, /429/);
});
test('cancellation invalidates pending requests; stale replies are ignored', async () => {
  const pending = nativeRequest('live-token'); const id = sent.at(-1).id;
  cancelPending(); reply({id, token:'stale'});
  await assert.rejects(pending, /cancelada/);
});
test('close goes through the host; a normal browser cannot make native calls', async () => {
  closeAssistant(); assert.equal(sent.at(-1).operation, 'closed');
  window.InGeAssistantNative = undefined;
  await assert.rejects(nativeRequest('chat'), /Android/);
});
test('gateway contract fields travel with the rejection (code/provider status), C++ no-body failure is NETWORK', async () => {
  window.InGeAssistantNative = { postMessage: json => sent.push(JSON.parse(json)) };
  const busy = nativeRequest('chat'); let id = sent.at(-1).id;
  reply({id, error:'Gemini está temporalmente ocupado. Intenta nuevamente en unos segundos.', code:'GEMINI_UNAVAILABLE', provider_status:503, retryable:true, attempts:3});
  await assert.rejects(busy, e => e.code === 'GEMINI_UNAVAILABLE' && e.providerStatus === 503 && e.retryable === true && e.attempts === 3);
  const offline = nativeRequest('chat'); id = sent.at(-1).id;
  reply({id, error:'No se pudo conectar con InGe+ IA.'});
  await assert.rejects(offline, e => e.code === 'NETWORK');
  const gateway = nativeRequest('chat'); id = sent.at(-1).id;
  reply({id, code:401, error:'La sesión venció. Vuelve a iniciar sesión.'});
  await assert.rejects(gateway, e => e.code === 'AUTH_REQUIRED');
});

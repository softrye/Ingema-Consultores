import { test } from 'node:test';
import assert from 'node:assert/strict';
import { BetaLiveSession } from './src/lib/beta-live-session.ts';
class Socket {
  static OPEN = 1; readyState = 1; sent = []; closed = false;
  send(raw) { this.sent.push(JSON.parse(raw)); }
  close() { this.closed = true; }
  open() { this.onopen?.(); }
  message(detail) { this.onmessage?.({data: JSON.stringify(detail)}); }
}
globalThis.WebSocket = Socket;
test('documented beta transport uses an ephemeral token and waits for setup before audio', async () => {
  const socket = new Socket(); let endpoint; const messages = [];
  const session = new BetaLiveSession('auth_tokens/test', 'gemini-3.8-live', {responseModalities:['AUDIO']},
    {onmessage: m => messages.push(m)}, url => { endpoint = url; return socket; });
  const connecting = session.connect(); socket.open();
  assert.match(endpoint, /v1beta\.GenerativeService\.BidiGenerateContentConstrained\?access_token=/);
  assert.equal(endpoint.includes('?key='), false);
  session.sendRealtimeInput({audio:{data:'before', mimeType:'audio/pcm;rate=16000'}});
  assert.equal(socket.sent.length, 1);
  assert.equal(socket.sent[0].setup.model, 'models/gemini-3.8-live');
  socket.message({setupComplete:{}}); await connecting;
  session.sendRealtimeInput({audio:{data:'after', mimeType:'audio/pcm;rate=16000'}});
  assert.equal(socket.sent.at(-1).realtimeInput.audio.data, 'after');
  socket.message({serverContent:{inputTranscription:{text:'Hola'}}}); await new Promise(resolve => setImmediate(resolve));
  assert.equal(messages.at(-1).serverContent.inputTranscription.text, 'Hola');
  session.close(); assert.equal(socket.closed, true);
});
test('closing before setup rejects the connection and drops late audio', async () => {
  const socket = new Socket();
  const session = new BetaLiveSession('auth_tokens/test', 'gemini-3.8-live', {}, {onmessage(){}}, () => socket);
  const pending = session.connect(); session.close();
  await assert.rejects(pending, /cancelada/);
  session.sendRealtimeInput({audio:{data:'late'}}); assert.equal(socket.sent.length, 0);
});
test('LIVE client: exact Constrained endpoint, encoded token, setup first with models/ prefix', async () => {
  const socket = new Socket(); let endpoint; const lines = [];
  const session = new BetaLiveSession('auth_tokens/a+b/c=', 'gemini-3.8-live',
    {responseModalities:['AUDIO'], inputAudioTranscription:{}, outputAudioTranscription:{}},
    {onmessage(){}}, url => { endpoint = url; return socket; }, line => lines.push(line));
  const connecting = session.connect(); socket.open();
  assert.equal(endpoint, 'wss://generativelanguage.googleapis.com/ws/google.ai.generativelanguage.v1beta.GenerativeService.BidiGenerateContentConstrained?access_token=auth_tokens%2Fa%2Bb%2Fc%3D');
  assert.equal(Object.keys(socket.sent[0])[0], 'setup');
  assert.equal(socket.sent[0].setup.model, 'models/gemini-3.8-live');
  assert.deepEqual(socket.sent[0].setup.generationConfig.responseModalities, ['AUDIO']);
  session.sendRealtimeInput({audio:{data:'early', mimeType:'audio/pcm;rate=16000'}});
  assert.equal(socket.sent.length, 1, 'no audio before setupComplete');
  socket.message({setupComplete:{}}); await connecting;
  session.sendRealtimeInput({audio:{data:'AAAA', mimeType:'audio/pcm;rate=16000'}});
  session.sendRealtimeInput({audio:{data:'BBBB', mimeType:'audio/pcm;rate=16000'}});
  assert.equal(socket.sent.at(-1).realtimeInput.audio.mimeType, 'audio/pcm;rate=16000');
  socket.message({serverContent:{modelTurn:{parts:[{inlineData:{mimeType:'audio/pcm;rate=24000', data:'AAAA'}}]}}});
  await new Promise(resolve => setImmediate(resolve));
  socket.onclose?.({code:1000, reason:''});
  assert.deepEqual(lines.map(l => l.split(' ')[0]), ['INGE_AI_LIVE_WS_OPEN', 'INGE_AI_LIVE_SETUP_SENT', 'INGE_AI_LIVE_SETUP_OK',
    'INGE_AI_LIVE_AUDIO_TX_STARTED', 'INGE_AI_LIVE_AUDIO_RX_STARTED', 'INGE_AI_LIVE_WS_CLOSE']);
  assert.equal(lines.join('\n').includes('auth_tokens'), false, 'token never logged');
  assert.equal(lines.filter(l => l.startsWith('INGE_AI_LIVE_AUDIO_TX')).length, 1, 'one line, not one per chunk');
});
test('recorder worklet emits clamped PCM16 at 16 kHz even from a 48 kHz context', async () => {
  const { default: source } = await import('./src/lib/worklets/audio-processing.ts');
  const chunks = [];
  globalThis.sampleRate = 48000;
  globalThis.AudioWorkletProcessor = class { port = { postMessage: m => chunks.push(new Int16Array(m.data.int16arrayBuffer)) }; };
  const Worklet = new Function(`return (${source});`)();
  const node = new Worklet();
  const second = new Float32Array(48000).fill(1.5); // clipped input, 1 s at 48 kHz
  for (let i = 0; i < second.length; i += 128) node.process([[second.subarray(i, i + 128)]]);
  const total = chunks.reduce((n, c) => n + c.length, 0) + node.bufferWriteIndex;
  assert.ok(Math.abs(total - 16000) <= 1, `16 kHz output, got ${total}`);
  assert.equal(chunks[0][0], 32767, 'clamped, no Int16 wrap-around');
  globalThis.sampleRate = 16000;
  const passthrough = new Worklet(); passthrough.process([[new Float32Array([-1, 0.5])]]);
  assert.deepEqual([...passthrough.buffer.slice(0, 2)], [-32768, 16383]);
});

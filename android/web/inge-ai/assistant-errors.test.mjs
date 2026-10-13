import { test } from 'node:test';
import assert from 'node:assert/strict';
const { atStage, stageError, voiceStageOf, voiceUserMessage, logVoiceError, chatFailureMessage, sanitizeDiagnostic } =
  await import('./src/inge/assistantErrors.ts');
const named = (name, message = 'detail') => Object.assign(new Error(message), { name });
const failAt = async (stage, failure) => { try { await atStage(stage, () => { throw failure; }); } catch (e) { return e; } assert.fail('no error'); };
test('VOZ 1: getUserMedia without input device is GET_USER_MEDIA, not a permission denial', async () => {
  const error = await failAt('GET_USER_MEDIA', named('NotFoundError', 'Requested device not found'));
  assert.equal(voiceStageOf(error), 'GET_USER_MEDIA');
  assert.equal(voiceUserMessage(voiceStageOf(error)), 'No se pudo acceder al micrófono.');
  const denied = await failAt('GET_USER_MEDIA', named('NotAllowedError', 'Permission denied'));
  assert.equal(voiceStageOf(denied), 'MIC_PERMISSION');
});
test('VOZ 2: AudioWorklet failure is audio processing, never "permissions"', async () => {
  const error = await failAt('AUDIO_WORKLET_LOAD', named('AbortError', 'Unable to load a worklet module.'));
  assert.equal(voiceStageOf(error), 'AUDIO_WORKLET_LOAD');
  const message = voiceUserMessage(voiceStageOf(error));
  assert.equal(message, 'No se pudo iniciar el procesamiento de audio.');
  assert.equal(/permis/i.test(message), false);
});
test('VOZ 3: LIVE_TOKEN / LIVE_CONNECT failures are voice connection, not microphone', async () => {
  for (const stage of ['LIVE_TOKEN', 'LIVE_CONNECT']) {
    const error = await failAt(stage, new Error('Gemini está temporalmente ocupado.'));
    assert.equal(voiceStageOf(error), stage);
    const message = voiceUserMessage(stage);
    assert.equal(message, 'No se pudo conectar la conversación por voz.');
    assert.equal(/micr[oó]fono|permis/i.test(message), false);
  }
});
test('the first stage wins: an inner stage is not relabeled by an outer one', async () => {
  const inner = stageError('AUDIO_CONTEXT_RESUME', named('InvalidStateError'));
  const error = await failAt('LIVE_CONNECT', inner);
  assert.equal(voiceStageOf(error), 'AUDIO_CONTEXT_RESUME');
});
test('voice logs are sanitized: stage + class + short summary, no secrets', () => {
  const lines = [];
  logVoiceError('LIVE_TOKEN', new Error('token=ya29.AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA key=AIzaSyFAKEFAKEFAKE Bearer abc.def.ghi'), l => lines.push(l));
  assert.match(lines[0], /^INGE_AI_VOICE_ERROR stage=LIVE_TOKEN name=Error message=/);
  for (const secret of ['ya29', 'AIzaSy', 'abc.def.ghi']) assert.equal(lines[0].includes(secret), false, secret);
  assert.ok(sanitizeDiagnostic('x'.repeat(500)).length <= 120);
});
test('chat failures are told apart: temporary Gemini, session, network, rejected', () => {
  const err = (code, message = 'Gemini rechazó la consulta (HTTP 400).') => Object.assign(new Error(message), { code });
  assert.match(chatFailureMessage(err('GEMINI_UNAVAILABLE', 'x')), /temporalmente ocupado/);
  assert.match(chatFailureMessage(err('AUTH_REQUIRED', 'x')), /sesión venció/);
  assert.match(chatFailureMessage(err('NETWORK', 'x')), /conexión/);
  assert.equal(chatFailureMessage(err('GEMINI_ERROR')), 'Gemini rechazó la consulta (HTTP 400).');
  assert.equal(/HTTP 503/.test(chatFailureMessage(err('GEMINI_UNAVAILABLE', 'Gemini rechazó la consulta (HTTP 503).'))), false);
});

// InGe+ IA: one place that names where voice/chat failed and what the user sees.
// Logs carry only stage, error class and a short sanitized summary: never tokens,
// JWT, API keys, audio or transcripts.

export type VoiceStage =
  | 'MIC_PERMISSION' | 'GET_USER_MEDIA' | 'AUDIO_CONTEXT_CREATE' | 'AUDIO_CONTEXT_RESUME'
  | 'AUDIO_WORKLET_LOAD' | 'PCM_INPUT' | 'AUDIO_OUTPUT' | 'LIVE_TOKEN' | 'LIVE_CONNECT' | 'LIVE_SETUP';

export type VoiceStageError = Error & { stage: VoiceStage; causeName: string };

export function sanitizeDiagnostic(text: unknown): string {
  return String(text ?? '').replace(/AIza[0-9A-Za-z_-]{10,}/g, '[key]')
    .replace(/(key|token|authorization|bearer)\s*[=:]\s*\S+/gi, '$1=[hidden]')
    .replace(/\bbearer\s+\S+/gi, 'Bearer [hidden]')
    .replace(/[A-Za-z0-9_\-./+]{32,}/g, '[redacted]')
    .replace(/\s+/g, ' ').trim().slice(0, 120);
}

const PERMISSION_DENIED = new Set(['NotAllowedError', 'SecurityError', 'PermissionDeniedError']);

export function stageError(stage: VoiceStage, failure: unknown): VoiceStageError {
  if (failure && typeof failure === 'object' && 'stage' in failure) return failure as VoiceStageError;
  const name = failure instanceof Error || (failure && typeof failure === 'object' && 'name' in failure)
    ? String((failure as { name?: unknown }).name || 'Error') : 'Error';
  // A denied capture is a permission problem; any other getUserMedia failure is not.
  const resolved: VoiceStage = stage === 'GET_USER_MEDIA' && PERMISSION_DENIED.has(name) ? 'MIC_PERMISSION' : stage;
  const error = new Error(sanitizeDiagnostic((failure as { message?: unknown })?.message ?? failure)) as VoiceStageError;
  error.name = 'VoiceStageError';
  error.stage = resolved;
  error.causeName = name.slice(0, 40);
  return error;
}

export async function atStage<T>(stage: VoiceStage, run: () => T | Promise<T>): Promise<T> {
  try { return await run(); } catch (failure) { throw stageError(stage, failure); }
}

export function voiceStageOf(failure: unknown): VoiceStage | undefined {
  return failure && typeof failure === 'object' && 'stage' in failure ? (failure as VoiceStageError).stage : undefined;
}

export function voiceUserMessage(stage: VoiceStage): string {
  switch (stage) {
    case 'MIC_PERMISSION': return 'Permite el micrófono para hablar con InGe+ IA.';
    case 'GET_USER_MEDIA': return 'No se pudo acceder al micrófono.';
    case 'AUDIO_CONTEXT_CREATE':
    case 'AUDIO_CONTEXT_RESUME':
    case 'AUDIO_WORKLET_LOAD':
    case 'PCM_INPUT': return 'No se pudo iniciar el procesamiento de audio.';
    case 'AUDIO_OUTPUT': return 'No se pudo preparar el audio de respuesta.';
    case 'LIVE_SETUP': return 'Gemini Live no inició la sesión. Reintenta la conexión de voz.';
    case 'LIVE_TOKEN':
    case 'LIVE_CONNECT': return 'No se pudo conectar la conversación por voz.';
  }
}

export function logVoiceError(stage: VoiceStage, failure: unknown, log: (line: string) => void = console.warn): VoiceStageError {
  const error = stageError(stage, failure);
  log(`INGE_AI_VOICE_ERROR stage=${error.stage} name=${error.causeName} message=${error.message}`);
  return error;
}

// Chat failures arrive from the native bridge with the gateway contract fields.
export type ChatFailure = Error & { code?: string; providerStatus?: number; retryable?: boolean; attempts?: number };

export function chatFailureMessage(failure: unknown): string {
  const error = (failure ?? {}) as ChatFailure;
  switch (error.code) {
    case 'GEMINI_UNAVAILABLE': return 'Gemini está temporalmente ocupado. Intenta nuevamente en unos segundos.';
    case 'GEMINI_RATE_LIMIT':
    case 'RATE_LIMIT': return error.message || 'Hay demasiadas consultas. Espera un momento e intenta de nuevo.';
    case 'AUTH_REQUIRED': return 'La sesión venció. Vuelve a iniciar sesión.';
    case 'NETWORK_ERROR':
    case 'NETWORK': return 'No se pudo conectar con InGe+ IA. Revisa la conexión y reintenta.';
    default: return error.message || 'No se pudo completar la consulta.';
  }
}

export function logChatError(failure: unknown, log: (line: string) => void = console.warn) {
  const error = (failure ?? {}) as ChatFailure;
  log(`INGE_AI_CHAT_ERROR code=${error.code ?? 'UNKNOWN'} provider_status=${error.providerStatus ?? '-'}`
      + ` retryable=${error.retryable ?? '-'} attempts=${error.attempts ?? '-'}`);
}

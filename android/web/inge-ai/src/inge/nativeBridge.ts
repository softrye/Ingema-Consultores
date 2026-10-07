type Result = { ok?: boolean; error?: string; respuesta?: string; token?: string; model?: string; config?: any; expiresAt?: string;
  code?: string | number; provider_status?: number; retryable?: boolean; attempts?: number };
// Gateway failure fields travel with the Error (code/provider status), never the payload.
function failure(result: Result): Error {
  const error = new Error(result.error) as Error & { code?: string; providerStatus?: number; retryable?: boolean; attempts?: number };
  // Gateway 401 (verify_jwt) arrives as a numeric code; GeminiAssistant's no-body failure has none.
  error.code = result.code === 401 ? 'AUTH_REQUIRED' : typeof result.code === 'string' ? result.code
    : result.error === 'No se pudo conectar con InGe+ IA.' ? 'NETWORK' : undefined;
  error.providerStatus = result.provider_status; error.retryable = result.retryable; error.attempts = result.attempts;
  return error;
}
declare global {
  interface Window { InGeAssistantNative?: { postMessage(json: string): void } }
}
const pending = new Map<string, { resolve(value: Result): void; reject(error: Error): void; timer: number }>();
let sequence = 0;
window.addEventListener('inge-native', ((event: CustomEvent) => {
  const result = event.detail;
  const entry = pending.get(result.id);
  if (!entry) return;
  pending.delete(result.id); window.clearTimeout(entry.timer);
  if (result.error) entry.reject(failure(result)); else entry.resolve(result);
}) as EventListener);
export function nativeRequest(operation: 'chat' | 'live-token', extra = {}): Promise<Result> {
  return new Promise((resolve, reject) => {
    if (!window.InGeAssistantNative) { reject(new Error('Abre InGe+ IA desde la app Android.')); return; }
    const id = `${Date.now()}-${++sequence}`;
    const timer = window.setTimeout(() => { pending.delete(id); reject(Object.assign(new Error('La conexión tardó demasiado. Reintenta.'), { code: 'NETWORK' })); }, 45000);
    pending.set(id, { resolve, reject, timer });
    window.InGeAssistantNative.postMessage(JSON.stringify({ ...extra, operation, id }));
  });
}
export function closeAssistant() { window.InGeAssistantNative?.postMessage('{"operation":"closed"}'); }
export function cancelPending() {
  for (const entry of pending.values()) { window.clearTimeout(entry.timer); entry.reject(new Error('Consulta cancelada.')); }
  pending.clear();
}

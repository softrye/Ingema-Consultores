import type { LiveCallbacks, LiveConnectConfig, LiveServerMessage } from '@google/genai';
// Ephemeral tokens (auth_tokens/...) are only accepted by the Constrained v1beta RPC:
// BidiGenerateContentConstrained?access_token=<token>. The plain BidiGenerateContent
// endpoint is for permanent keys, which never reach Android. The token's
// liveConnectConstraints carry the bare model id; setup.model is models/<id>.
export const LIVE_ENDPOINT = 'wss://generativelanguage.googleapis.com/ws/google.ai.generativelanguage.v1beta.GenerativeService.BidiGenerateContentConstrained';
// Lifecycle lines only (no token, audio or transcript); never one line per chunk.
function sanitizeReason(reason: unknown): string {
  return String(reason ?? '').replace(/[A-Za-z0-9_\-./+]{32,}/g, '[redacted]').replace(/\s+/g, ' ').trim().slice(0, 120);
}
export class BetaLiveSession {
  private socket: WebSocket | null = null;
  private ready = false;
  private rejectConnect?: (reason: Error) => void;
  private incoming: Promise<void> = Promise.resolve();
  private token: string;
  private model: string;
  private config: LiveConnectConfig;
  private callbacks: LiveCallbacks;
  private createSocket: (url: string) => WebSocket;
  private log: (line: string) => void;
  private audioSent = false;
  private audioReceived = false;
  constructor(token: string, model: string, config: LiveConnectConfig,
    callbacks: LiveCallbacks, createSocket = (url: string) => new WebSocket(url),
    log: (line: string) => void = line => console.info(line)) {
    this.token = token; this.model = model; this.config = config;
    this.callbacks = callbacks; this.createSocket = createSocket; this.log = log;
  }
  connect(): Promise<void> {
    return new Promise((resolve, reject) => {
      this.rejectConnect = reject;
      const socket = this.createSocket(LIVE_ENDPOINT + '?access_token=' + encodeURIComponent(this.token));
      this.token = ''; this.socket = socket;
      socket.onopen = () => {
        if (socket !== this.socket) return;
        this.log('INGE_AI_LIVE_WS_OPEN');
        this.callbacks.onopen?.();
        // First message on the socket: setup. Nothing else is sent before setupComplete.
        socket.send(JSON.stringify({setup: {
          model: this.model.startsWith('models/') ? this.model : `models/${this.model}`,
          generationConfig: {responseModalities: this.config.responseModalities},
          systemInstruction: this.config.systemInstruction,
          inputAudioTranscription: this.config.inputAudioTranscription,
          outputAudioTranscription: this.config.outputAudioTranscription,
        }}));
        this.log('INGE_AI_LIVE_SETUP_SENT');
      };
      socket.onmessage = event => {
        this.incoming = this.incoming.then(async () => {
          if (socket !== this.socket) return;
          const text = typeof event.data === 'string' ? event.data : event.data instanceof Blob
            ? await event.data.text() : new TextDecoder().decode(event.data);
          const message = JSON.parse(text) as LiveServerMessage;
          if (message.setupComplete) {
            this.ready = true; this.rejectConnect = undefined; this.log('INGE_AI_LIVE_SETUP_OK'); resolve();
          }
          if (!this.audioReceived && message.serverContent?.modelTurn?.parts?.some(part => part.inlineData?.mimeType?.startsWith('audio/'))) {
            this.audioReceived = true; this.log('INGE_AI_LIVE_AUDIO_RX_STARTED');
          }
          this.callbacks.onmessage(message);
        }).catch(() => {
          this.callbacks.onerror?.(new ErrorEvent('error', {message: 'Respuesta Live inválida.'})); this.close();
        });
      };
      socket.onerror = () => {
        reject(new Error('No se pudo abrir Gemini Live.')); this.callbacks.onerror?.(new ErrorEvent('error'));
      };
      socket.onclose = event => {
        this.log(`INGE_AI_LIVE_WS_CLOSE code=${event?.code ?? '-'} reason=${sanitizeReason(event?.reason) || '-'}`);
        this.ready = false; this.socket = null; reject(new Error('La conexión de voz se cerró.'));
        this.callbacks.onclose?.(event);
      };
    });
  }
  private send(message: object) {
    if (this.ready && this.socket?.readyState === WebSocket.OPEN) this.socket.send(JSON.stringify(message));
  }
  sendRealtimeInput(input: {audio?: {mimeType?: string; data?: string}; [key: string]: unknown}) {
    if (!this.ready) return;
    if (!this.audioSent && input.audio) { this.audioSent = true; this.log(`INGE_AI_LIVE_AUDIO_TX_STARTED mime=${input.audio.mimeType ?? '-'}`); }
    this.send({realtimeInput: input});
  }
  sendClientContent(content: object) { this.send({clientContent: content}); }
  sendToolResponse(response: object) { this.send({toolResponse: response}); }
  close() {
    this.ready = false; this.rejectConnect?.(new Error('Conexión de voz cancelada.')); this.rejectConnect = undefined;
    const socket = this.socket; this.socket = null;
    if (socket) { socket.onmessage = null; socket.close(); }
  }
}

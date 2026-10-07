import { useEffect, useRef, useState } from 'react';
import { LiveAPIProvider, useLiveAPIContext } from '../contexts/LiveAPIContext';
import ControlTray from '../components/control-tray/ControlTray';
import { closeAssistant, nativeRequest } from './nativeBridge';
import { chatFailureMessage, logChatError } from './assistantErrors';
import InGeLiveEdgeGlow from './InGeLiveEdgeGlow';
import './liquid-glass.scss';
const options = { apiKey: 'ephemeral-token-issued-by-native-host' };
type Message = { role: 'user' | 'assistant'; text: string };
function Console() {
  const { client, connected, connecting, error, setError } = useLiveAPIContext();
  const [messages, setMessages] = useState<Message[]>([]);
  const [draft, setDraft] = useState('');
  const [busy, setBusy] = useState(false);
  const [expanded, setExpanded] = useState(false);
  // Cierre visual: el halo y el panel se apagan (~280 ms) y luego se usa el
  // cierre real del bridge, que destruye el WebView y devuelve el Dock.
  const [closing, setClosing] = useState(false);
  const closeTimer = useRef(0);
  const requestClose = () => {
    if (closeTimer.current) return;
    const reduced = document.documentElement.dataset.motion === 'false'
      || window.matchMedia?.('(prefers-reduced-motion: reduce)').matches === true;
    setClosing(true);
    closeTimer.current = window.setTimeout(closeAssistant, reduced ? 0 : 280);
  };
  useEffect(() => () => window.clearTimeout(closeTimer.current), []);
  const [transcript, setTranscript] = useState({ user: '', assistant: '' });
  const end = useRef<HTMLDivElement>(null);
  const video = useRef<HTMLVideoElement>(null);
  const alive = useRef(true);
  const submitting = useRef(false);
  const wasConnected = useRef(false);
  useEffect(() => {
    alive.current = true;
    const visuals = (event: CustomEvent) => {
      if (event.detail.event !== 'visuals') return;
      const v = event.detail.visuals;
      for (const key of ['glass', 'glassStrong', 'line', 'highlight', 'shadow', 'text', 'muted', 'accent', 'error'])
        if (v[key]) document.documentElement.style.setProperty(`--${key}`, v[key]);
      for (const key of ['fast', 'normal', 'sheet']) document.documentElement.style.setProperty(`--${key}`, `${v[key]}ms`);
      document.documentElement.style.setProperty('--blur', `${v.blur}px`);
      document.documentElement.dataset.motion = String(v.motion);
    };
    window.addEventListener('inge-native', visuals as EventListener);
    return () => { alive.current = false; window.removeEventListener('inge-native', visuals as EventListener); };
  }, []);
  useEffect(() => { end.current?.scrollIntoView({ behavior: 'auto' }); }, [messages, busy, transcript]);
  useEffect(() => {
    const onContent = (content: any) => {
      if (content.inputTranscription?.text) setTranscript(t => ({ ...t, user: t.user + content.inputTranscription.text }));
      if (content.outputTranscription?.text) setTranscript(t => ({ ...t, assistant: t.assistant + content.outputTranscription.text }));
    };
    client.on('content', onContent);
    return () => { client.off('content', onContent); };
  }, [client]);
  useEffect(() => { if (connecting) setTranscript({ user: '', assistant: '' }); }, [connecting]);
  useEffect(() => {
    if (wasConnected.current && !connected) {
      const turns: Message[] = [];
      if (transcript.user) turns.push({role: 'user', text: transcript.user});
      if (transcript.assistant) turns.push({role: 'assistant', text: transcript.assistant});
      setMessages(history => [...history, ...turns]); setTranscript({user: '', assistant: ''});
    }
    wasConnected.current = connected;
  }, [connected, transcript]);
  async function send(text = draft) {
    if (!text.trim() || submitting.current || connected || connecting) return;
    submitting.current = true; setBusy(true); setError('');
    const next: Message[] = [...messages, { role: 'user', text: text.trim().slice(0, 4000) }];
    setMessages(next); setDraft('');
    try {
      // Keep complete recent turns and a bounded payload for the authenticated gateway.
      const result = await nativeRequest('chat', { messages: next.slice(-5).map(m => ({ ...m, text: m.text.slice(0, 4000) })) });
      if (!result.respuesta) throw new Error('Gemini no devolvió una respuesta.');
      if (alive.current) setMessages([...next, { role: 'assistant', text: result.respuesta }]);
    } catch (failure) {
      // Temporary Gemini, session, network and rejected queries get distinct messages;
      // the log keeps only the gateway contract fields (no conversation).
      logChatError(failure);
      if (alive.current) setError(chatFailureMessage(failure));
    }
    finally { submitting.current = false; if (alive.current) setBusy(false); }
  }
  const glowMode = connected ? 'voice' : busy ? 'thinking' : 'idle';
  return <>
  <InGeLiveEdgeGlow leaving={closing} mode={glowMode} />
  <div className={`assistant-scrim${closing ? ' closing' : ''}`} onClick={requestClose}>
    <main className={`assistant-sheet glass ${expanded ? 'expanded' : ''}`} onClick={e => e.stopPropagation()} aria-label="InGe+ IA">
      <div className="sheet-grip" />
      <header><div className="brand-mark" aria-hidden>✦</div><div><h1>InGe+ IA</h1><p>{connected ? 'Conversación por voz · micrófono activo' : connecting ? 'Conectando con Gemini…' : 'Tu asistente de ingeniería'}</p></div>
        <button className="icon-button glass" aria-label={expanded ? 'Reducir panel' : 'Ampliar panel'} onClick={() => setExpanded(!expanded)}>{expanded ? '↙' : '↗'}</button>
        <button className="icon-button glass" aria-label="Cerrar asistente" onClick={requestClose}>×</button></header>
      <section className="conversation" aria-live="polite" aria-busy={busy}>
        {!messages.length && !transcript.user && <div className="welcome"><div className="welcome-star">✦</div><h2>¿En qué te ayudo?</h2><p>Escribe tu consulta o inicia una conversación por voz.</p><div className="suggestions">
          {['¿Cómo completo una calicata?', '¿Cómo exporto mi Excel?', 'Explícame la clasificación SUCS'].map(text => <button className="glass" key={text} onClick={() => send(text)} disabled={busy || connected || connecting}>{text}<span>↗</span></button>)}
        </div></div>}
        {messages.map((m, i) => <article key={i} className={`message ${m.role}`}><small>{m.role === 'user' ? 'Tú' : 'InGe+ IA'}</small><p>{m.text}</p></article>)}
        {transcript.user && <article className="message user"><small>Tú · voz</small><p>{transcript.user}</p></article>}
        {transcript.assistant && <article className="message assistant"><small>InGe+ IA · voz</small><p>{transcript.assistant}</p></article>}
        {busy && <p className="pending">Gemini está respondiendo…</p>}
        {error && <div className="error glass" role="alert">{error}<button onClick={() => setError('')} aria-label="Cerrar aviso">×</button></div>}
        <div ref={end} />
      </section>
      <div className="composer glass"><textarea aria-label="Consulta para InGe+ IA" placeholder="Pregunta a InGe+ IA…" value={draft} maxLength={4000} disabled={busy || connected || connecting} rows={2} onChange={e => setDraft(e.target.value)} />
        <button className="send-button" aria-label="Enviar consulta" disabled={!draft.trim() || busy || connected || connecting} onClick={() => send()}>↑</button></div>
      <ControlTray videoRef={video} supportsVideo={false} disabled={busy} />
      <footer>Con Gemini · Revisa los datos antes de tomar decisiones técnicas.</footer>
    </main>
  </div>
  </>;
}
// El estado visual activo (halo perimetral) vive dentro de la consola real;
// la apertura con orbe (IngeOpening) ya no se monta.
export default function InGeConsole() { return <LiveAPIProvider options={options}><Console /></LiveAPIProvider>; }

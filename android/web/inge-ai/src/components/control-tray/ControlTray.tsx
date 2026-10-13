/**
 * Copyright 2024 Google LLC
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

// Modified for InGe+: native auth, lifecycle and Liquid Glass.
import { memo, RefObject, useEffect, useRef, useState } from "react";
import { useLiveAPIContext } from "../../contexts/LiveAPIContext";
import { AudioRecorder } from "../../lib/audio-recorder";
import { logVoiceError, voiceStageOf, voiceUserMessage } from "../../inge/assistantErrors";
import AudioPulse from "../audio-pulse/AudioPulse";
export type ControlTrayProps = { videoRef: RefObject<HTMLVideoElement>; supportsVideo: boolean; disabled?: boolean };
function ControlTray({disabled}: ControlTrayProps) {
 const {client, connected, connecting, connect, disconnect, volume, setError} = useLiveAPIContext();
 const [muted, setMuted] = useState(false);
 const [starting, setStarting] = useState(false);
 const recorder = useRef(new AudioRecorder());
 const ready = useRef(false);
 const pcmFailed = useRef(false);
 const epoch = useRef(0);
 useEffect(() => {
   const capture = recorder.current;
   const data = (base64: string) => {
     if (!ready.current) return;
     // The recorder worklet always emits raw PCM16 LE mono at 16 kHz (it resamples itself).
     try { client.sendRealtimeInput([{mimeType: 'audio/pcm;rate=16000', data: base64}]); pcmFailed.current = false; }
     catch (failure) { if (!pcmFailed.current) { pcmFailed.current = true; logVoiceError('PCM_INPUT', failure); } }
   };
   capture.on('data', data);
   return () => { ++epoch.current; capture.off('data', data); capture.stop(); };
 }, [client]);
 useEffect(() => { ready.current = connected && !muted; }, [connected, muted]);
 useEffect(() => { if (!connected && !connecting && !starting) recorder.current.stop(); }, [connected, connecting, starting]);
 const stop = async () => { ++epoch.current; ready.current = false; recorder.current.stop(); setStarting(false); await disconnect(); };
 const start = async () => {
   if (starting || connecting) return;
   const ticket = ++epoch.current; setStarting(true); setMuted(false); setError('');
   try {
     // Request permission before spending a Live token; nothing streams before setup.
     await recorder.current.start();
     if (ticket !== epoch.current) { recorder.current.stop(); return; }
     await connect();
   } catch (failure) {
     recorder.current.stop();
     // Capture stages only (connect() reports its own LIVE_* stages): the message
     // says where it failed instead of always blaming permissions.
     const stage = voiceStageOf(failure) ?? 'GET_USER_MEDIA';
     logVoiceError(stage, failure);
     if (ticket === epoch.current) setError(voiceUserMessage(stage));
   } finally { if (ticket === epoch.current) setStarting(false); }
 };
 const toggleMute = async () => {
   if (!connected) return;
   if (!muted) { recorder.current.stop(); setMuted(true); }
   else {
     const ticket = epoch.current;
     try { await recorder.current.start(); if (ticket !== epoch.current) recorder.current.stop(); else setMuted(false); }
     catch (failure) { const stage = voiceStageOf(failure) ?? 'GET_USER_MEDIA'; logVoiceError(stage, failure); setError(voiceUserMessage(stage)); }
   }
 };
 return <section className="control-tray" aria-label="Controles de voz">
   <button className={`voice-button glass ${connected ? 'connected' : ''}`} disabled={disabled} onClick={connected || connecting || starting ? stop : start}>
     <AudioPulse active={connected} volume={volume} hover={false} />
     {connected ? 'Terminar voz' : connecting || starting ? 'Cancelar conexión' : 'Hablar con InGe+ IA'}
   </button>
   {connected && <button className="voice-button glass" onClick={toggleMute} aria-pressed={muted}>{muted ? 'Activar micrófono' : 'Silenciar'}</button>}
 </section>;
}
export default memo(ControlTray);

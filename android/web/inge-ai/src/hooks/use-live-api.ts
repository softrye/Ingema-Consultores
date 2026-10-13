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
import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import { GenAILiveClient } from "../lib/genai-live-client";
import { LiveClientOptions } from "../types";
import { AudioStreamer } from "../lib/audio-streamer";
import { audioContext } from "../lib/utils";
import { LiveConnectConfig } from "@google/genai";
import { nativeRequest } from "../inge/nativeBridge";
import { atStage, logVoiceError, voiceStageOf, voiceUserMessage } from "../inge/assistantErrors";

export type UseLiveAPIResults = {
 client: GenAILiveClient; setConfig: (config: LiveConnectConfig) => void; config: LiveConnectConfig;
 model: string; setModel: (model: string) => void; connected: boolean; connecting: boolean;
 connect: () => Promise<void>; disconnect: () => Promise<void>; volume: number;
 error: string; setError: (error: string) => void;
};
export function useLiveAPI(options: LiveClientOptions): UseLiveAPIResults {
 const client = useMemo(() => new GenAILiveClient(options), [options]);
 const streamer = useRef<AudioStreamer | null>(null);
 const generation = useRef(0);
 const watchdog = useRef<number>();
 const [model, setModel] = useState("gemini-3.8-live");
 const [config, setConfig] = useState<LiveConnectConfig>({});
 const [connected, setConnected] = useState(false);
 const [connecting, setConnecting] = useState(false);
 const [volume, setVolume] = useState(0);
 const [error, setError] = useState('');
 const live = useRef(false);
 useEffect(() => {
   const ready = () => { window.clearTimeout(watchdog.current); live.current = true; setConnected(true); setConnecting(false); };
   const closed = (event?: CloseEvent) => {
     window.clearTimeout(watchdog.current); live.current = false; setConnected(false); setConnecting(false); streamer.current?.stop(); setVolume(0);
     if (event && event.code !== 1000) setError('La conexión de voz se interrumpió. Vuelve a iniciar la voz.');
   };
   // Before setupComplete the socket failed to start the session; afterwards the live connection dropped.
   const failed = (event?: unknown) => {
     const stage = live.current ? 'LIVE_CONNECT' : 'LIVE_SETUP';
     logVoiceError(stage, (event as ErrorEvent)?.error ?? new Error('socket error'));
     setError(live.current ? 'La conexión de voz con Gemini falló. Vuelve a iniciar la voz.' : voiceUserMessage(stage));
     client.disconnect(); closed();
   };
   const interrupted = () => streamer.current?.stop();
   const audio = (data: ArrayBuffer) => {
     try { streamer.current?.addPCM16(new Uint8Array(data)); }
     catch (failure) { logVoiceError('AUDIO_OUTPUT', failure); }
     const samples = new DataView(data); let energy = 0;
     for (let i = 0; i + 1 < data.byteLength; i += 2) energy += (samples.getInt16(i, true) / 32768) ** 2;
     setVolume(Math.sqrt(energy / Math.max(1, data.byteLength / 2)));
   };
   const turn = () => setVolume(0);
   client.on('setupcomplete', ready).on('close', closed).on('error', failed).on('interrupted', interrupted).on('audio', audio).on('turncomplete', turn);
   return () => {
     ++generation.current;
     window.clearTimeout(watchdog.current);
     client.off('setupcomplete', ready).off('close', closed).off('error', failed).off('interrupted', interrupted).off('audio', audio).off('turncomplete', turn).disconnect();
     streamer.current?.stop();
   };
 }, [client]);
 const disconnect = useCallback(async () => {
   ++generation.current; client.disconnect(); streamer.current?.stop();
   window.clearTimeout(watchdog.current);
   setConnected(false); setConnecting(false); setVolume(0);
 }, [client]);
 const connect = useCallback(async () => {
   const ticket = ++generation.current; setConnecting(true); setError('');
   try {
     // Audio context resumes from the user's microphone tap.
     await atStage('AUDIO_OUTPUT', async () => {
       if (!streamer.current) streamer.current = new AudioStreamer(await audioContext({id: 'inge-live-out'}));
       await streamer.current.resume();
     });
     const auth = await atStage('LIVE_TOKEN', async () => {
       const result = await nativeRequest('live-token');
       if (!result.token || !result.model || !result.config) throw new Error('missing live credential');
       return { token: result.token, model: result.model, config: result.config as LiveConnectConfig };
     });
     if (ticket !== generation.current) return;
     console.info(`INGE_AI_LIVE_TOKEN_RECEIVED model=${auth.model}`);
     client.setCredentials({apiKey: auth.token, httpOptions: {apiVersion: 'v1beta'}});
     setModel(auth.model); setConfig(auth.config);
     watchdog.current = window.setTimeout(() => {
       if (ticket !== generation.current) return;
       ++generation.current; client.disconnect(); streamer.current?.stop();
       logVoiceError('LIVE_SETUP', new Error('setupComplete timeout'));
       setConnecting(false); setConnected(false); setError(voiceUserMessage('LIVE_SETUP'));
     }, 25000);
     await atStage('LIVE_CONNECT', () => client.connect(auth.model, auth.config));
     if (ticket !== generation.current) client.disconnect();
   } catch (failure) {
     if (ticket === generation.current) {
       const stage = voiceStageOf(failure) ?? 'LIVE_CONNECT';
       logVoiceError(stage, failure);
       window.clearTimeout(watchdog.current); client.disconnect(); setConnecting(false); setConnected(false);
       setError(voiceUserMessage(stage));
     }
   }
 }, [client]);
 return {client, config, setConfig, model, setModel, connected, connecting, connect, disconnect, volume, error, setError};
}

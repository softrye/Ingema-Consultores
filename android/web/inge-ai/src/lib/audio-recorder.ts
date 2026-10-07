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

import { audioContext } from "./utils";
import AudioRecordingWorklet from "./worklets/audio-processing";
import VolMeterWorket from "./worklets/vol-meter";

import { createWorketFromSrc } from "./audioworklet-registry";
import EventEmitter from "eventemitter3";
import { atStage, stageError } from "../inge/assistantErrors";

function arrayBufferToBase64(buffer: ArrayBuffer) {
  var binary = "";
  var bytes = new Uint8Array(buffer);
  var len = bytes.byteLength;
  for (var i = 0; i < len; i++) {
    binary += String.fromCharCode(bytes[i]);
  }
  return window.btoa(binary);
}

export class AudioRecorder extends EventEmitter {
  stream: MediaStream | undefined;
  audioContext: AudioContext | undefined;
  source: MediaStreamAudioSourceNode | undefined;
  recording: boolean = false;
  recordingWorklet: AudioWorkletNode | undefined;
  vuWorklet: AudioWorkletNode | undefined;

  private starting: Promise<void> | null = null;

  constructor(public sampleRate = 16000) {
    super();
  }

  private epoch = 0;
  async start() {
    if (this.starting) return this.starting;
    if (this.recording) return;
    if (!navigator.mediaDevices?.getUserMedia)
      throw stageError("GET_USER_MEDIA", new Error("mediaDevices.getUserMedia unavailable"));
    const ticket = ++this.epoch;
    // Each step names its stage: a missing input device, a blocked worklet or a
    // suspended context must not all look like a permission problem.
    this.starting = (async () => {
      const stream = await atStage("GET_USER_MEDIA", () => navigator.mediaDevices.getUserMedia({audio: true}));
      if (ticket !== this.epoch) { stream.getTracks().forEach(t => t.stop()); return; }
      this.stream = stream;
      const context = await atStage("AUDIO_CONTEXT_CREATE", () => new AudioContext({sampleRate: this.sampleRate}));
      this.audioContext = context;
      await atStage("AUDIO_CONTEXT_RESUME", () => context.resume());
      this.source = await atStage("PCM_INPUT", () => context.createMediaStreamSource(stream));
      const src = createWorketFromSrc("audio-recorder-worklet", AudioRecordingWorklet);
      try { await atStage("AUDIO_WORKLET_LOAD", () => context.audioWorklet.addModule(src)); } finally { URL.revokeObjectURL(src); }
      if (ticket !== this.epoch) return;
      const source = this.source;
      this.recordingWorklet = await atStage("PCM_INPUT", () => {
        const node = new AudioWorkletNode(context, "audio-recorder-worklet");
        node.port.onmessage = (ev: MessageEvent) => {
          const data = ev.data.data?.int16arrayBuffer;
          if (data && ticket === this.epoch) this.emit("data", arrayBufferToBase64(data));
        };
        source.connect(node);
        return node;
      });
      this.recording = true;
    })();
    try { await this.starting; } catch (error) { this.stop(); throw error; } finally { this.starting = null; }
  }
  stop() {
    ++this.epoch;
    this.source?.disconnect();
    this.recordingWorklet?.disconnect();
    if (this.recordingWorklet) this.recordingWorklet.port.onmessage = null;
    this.stream?.getTracks().forEach(track => track.stop());
    if (this.audioContext && this.audioContext.state !== "closed") void this.audioContext.close();
    this.stream = undefined; this.source = undefined; this.recordingWorklet = undefined;
    this.audioContext = undefined; this.recording = false;
  }
}

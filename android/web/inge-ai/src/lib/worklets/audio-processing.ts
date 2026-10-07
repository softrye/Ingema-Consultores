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

const AudioRecordingWorklet = `
class AudioProcessingWorklet extends AudioWorkletProcessor {

  // send and clear buffer every 2048 samples,
  // which at 16khz is about 8 times a second
  buffer = new Int16Array(2048);

  // current write index
  bufferWriteIndex = 0;

  // InGe+: Gemini Live input is raw PCM16 little-endian mono at 16 kHz. The context
  // asks for 16 kHz, but if the device keeps another rate (e.g. 48 kHz) this
  // worklet decimates explicitly (box average) so the declared rate is always true.
  ratio = sampleRate / 16000;
  phase = 0;
  acc = 0;
  accCount = 0;

  constructor() {
    super();
    this.hasAudio = false;
  }

  pushSample(value) {
    // clamp to [-1, 1] before scaling: 1.0 * 32768 would wrap to -32768 in Int16
    const s = value > 1 ? 1 : value < -1 ? -1 : value;
    this.buffer[this.bufferWriteIndex++] = s < 0 ? s * 32768 : s * 32767;
    if (this.bufferWriteIndex >= this.buffer.length) {
      this.sendAndClearBuffer();
    }
  }

  /**
   * @param inputs Float32Array[][] [input#][channel#][sample#] so to access first inputs 1st channel inputs[0][0]
   * @param outputs Float32Array[][]
   */
  process(inputs) {
    if (inputs[0].length) {
      const channel0 = inputs[0][0];
      this.processChunk(channel0);
    }
    return true;
  }

  sendAndClearBuffer(){
    this.port.postMessage({
      event: "chunk",
      data: {
        int16arrayBuffer: this.buffer.slice(0, this.bufferWriteIndex).buffer,
      },
    });
    this.bufferWriteIndex = 0;
  }

  processChunk(float32Array) {
    const l = float32Array.length;
    if (this.ratio <= 1.0001) {
      for (let i = 0; i < l; i++) this.pushSample(float32Array[i]);
      return;
    }
    for (let i = 0; i < l; i++) {
      this.acc += float32Array[i];
      this.accCount++;
      this.phase += 1;
      if (this.phase >= this.ratio) {
        this.pushSample(this.acc / this.accCount);
        this.phase -= this.ratio;
        this.acc = 0;
        this.accCount = 0;
      }
    }
  }
}
`;

export default AudioRecordingWorklet;

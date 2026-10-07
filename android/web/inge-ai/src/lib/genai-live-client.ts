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

import {
  Content,
  LiveCallbacks,
  LiveClientToolResponse,
  LiveConnectConfig,
  LiveServerContent,
  LiveServerMessage,
  LiveServerToolCall,
  LiveServerToolCallCancellation,
  Part,
} from "@google/genai";

import { BetaLiveSession } from "./beta-live-session";
import { EventEmitter } from "eventemitter3";
import { LiveClientOptions, StreamingLog } from "../types";
import { base64ToArrayBuffer } from "./utils";

/**
 * Event types that can be emitted by the MultimodalLiveClient.
 * Each event corresponds to a specific message from GenAI or client state change.
 */
export interface LiveClientEventTypes {
  // Emitted when audio data is received
  audio: (data: ArrayBuffer) => void;
  // Emitted when the connection closes
  close: (event: CloseEvent) => void;
  // Emitted when content is received from the server
  content: (data: LiveServerContent) => void;
  // Emitted when an error occurs
  error: (error: ErrorEvent) => void;
  // Emitted when the server interrupts the current generation
  interrupted: () => void;
  // Emitted for logging events
  log: (log: StreamingLog) => void;
  // Emitted when the connection opens
  open: () => void;
  // Emitted when the initial setup is complete
  setupcomplete: () => void;
  // Emitted when a tool call is received
  toolcall: (toolCall: LiveServerToolCall) => void;
  // Emitted when a tool call is cancelled
  toolcallcancellation: (
    toolcallCancellation: LiveServerToolCallCancellation
  ) => void;
  // Emitted when the current turn is complete
  turncomplete: () => void;
}

/**
 * A event-emitting class that manages the connection to the websocket and emits
 * events to the rest of the application.
 * If you dont want to use react you can still use this.
 */
export class GenAILiveClient extends EventEmitter<LiveClientEventTypes> {
  protected credentials: LiveClientOptions;
  private connectEpoch = 0;
  public setCredentials(options: LiveClientOptions) {
    if (this._status !== "disconnected") throw new Error("Finaliza la conexión de voz actual.");
    this.credentials = options;
  }

  private _status: "connected" | "disconnected" | "connecting" = "disconnected";
  public get status() {
    return this._status;
  }

  private _session: BetaLiveSession | null = null;
  public get session() {
    return this._session;
  }

  private _model: string | null = null;
  public get model() {
    return this._model;
  }

  protected config: LiveConnectConfig | null = null;

  public getConfig() {
    return { ...this.config };
  }

  constructor(options: LiveClientOptions) {
    super();
    this.credentials = options;
    this.send = this.send.bind(this);
    this.onopen = this.onopen.bind(this);
    this.onerror = this.onerror.bind(this);
    this.onclose = this.onclose.bind(this);
    this.onmessage = this.onmessage.bind(this);
  }

  protected log(type: string, message: StreamingLog["message"]) {
    const log: StreamingLog = {
      date: new Date(),
      type,
      message,
    };
    this.emit("log", log);
  }

  async connect(model: string, config: LiveConnectConfig): Promise<boolean> {
    if (this._status === "connected" || this._status === "connecting") {
      return false;
    }

    const ticket = ++this.connectEpoch;
    this._status = "connecting";
    this.config = config;
    this._model = model;

    const callbacks: LiveCallbacks = {
      onopen: () => { if (ticket === this.connectEpoch) this.onopen(); },
      onmessage: (m) => { if (ticket === this.connectEpoch) void this.onmessage(m); },
      onerror: (e) => { if (ticket === this.connectEpoch) this.onerror(e); },
      onclose: (e) => { if (ticket === this.connectEpoch) this.onclose(e); },
    };

    try {
      const session = new BetaLiveSession(this.credentials.apiKey, model, config, callbacks);
      this.credentials = {apiKey: ''};
      this._session = session;
      await session.connect();
      if (ticket !== this.connectEpoch) { session.close(); return false; }
      this._session = session;
    } catch (e) {
      if (ticket === this.connectEpoch) this._status = "disconnected";
      throw new Error("No se pudo conectar con Gemini Live. Revisa la disponibilidad del modelo y la cuota.");
    }

    this._status = "connected";
    return true;
  }

  public disconnect() {
    ++this.connectEpoch;
    this._session?.close(); this._session = null;
    this._status = "disconnected";
    return true;
  }

  protected onopen() {
    this.log("client.open", "Connected");
    this.emit("open");
  }

  protected onerror(e: ErrorEvent) {
    this.emit("error", e);
  }

  protected onclose(e: CloseEvent) {
    this._session = null; this._status = "disconnected";
    this.log(
      `server.close`,
      `disconnected ${e.reason ? `with reason: ${e.reason}` : ``}`
    );
    this.emit("close", e);
  }

  protected async onmessage(message: LiveServerMessage) {
    if (message.setupComplete) this.emit("setupcomplete");
    if (message.toolCall) this.emit("toolcall", message.toolCall);
    if (message.toolCallCancellation) this.emit("toolcallcancellation", message.toolCallCancellation);
    if (message.goAway) this.emit("error", new ErrorEvent("error", {message: "La sesión de voz terminó. Inicia una nueva conversación."}));
    const content = message.serverContent;
    if (!content) return;
    if (content.interrupted) this.emit("interrupted");
    if (content.turnComplete) this.emit("turncomplete");
    for (const part of content.modelTurn?.parts ?? []) {
      if (part.inlineData?.mimeType?.startsWith("audio/pcm") && part.inlineData.data)
        this.emit("audio", base64ToArrayBuffer(part.inlineData.data));
    }
    // Transcriptions are separate from modelTurn; do not drop audio-only messages.
    this.emit("content", content);
  }

  /**
   * send realtimeInput, this is base64 chunks of "audio/pcm" and/or "image/jpg"
   */
  sendRealtimeInput(chunks: Array<{ mimeType: string; data: string }>) {
    let hasAudio = false;
    let hasVideo = false;
    for (const ch of chunks) {
      if (ch.mimeType.startsWith("audio/")) this.session?.sendRealtimeInput({ audio: ch });
      else if (ch.mimeType.startsWith("image/")) this.session?.sendRealtimeInput({ video: ch });
      if (ch.mimeType.includes("audio")) {
        hasAudio = true;
      }
      if (ch.mimeType.includes("image")) {
        hasVideo = true;
      }
      if (hasAudio && hasVideo) {
        break;
      }
    }
    const message =
      hasAudio && hasVideo
        ? "audio + video"
        : hasAudio
        ? "audio"
        : hasVideo
        ? "video"
        : "unknown";
    this.log(`client.realtimeInput`, message);
  }

  /**
   *  send a response to a function call and provide the id of the functions you are responding to
   */
  sendToolResponse(toolResponse: LiveClientToolResponse) {
    if (
      toolResponse.functionResponses &&
      toolResponse.functionResponses.length
    ) {
      this.session?.sendToolResponse({
        functionResponses: toolResponse.functionResponses,
      });
      this.log(`client.toolResponse`, toolResponse);
    }
  }

  /**
   * send normal content parts such as { text }
   */
  send(parts: Part | Part[], turnComplete: boolean = true) {
    this.session?.sendClientContent({ turns: [{ role: "user", parts: Array.isArray(parts) ? parts : [parts] }], turnComplete });
    this.log(`client.send`, {
      turns: Array.isArray(parts) ? parts : [parts],
      turnComplete,
    });
  }
}

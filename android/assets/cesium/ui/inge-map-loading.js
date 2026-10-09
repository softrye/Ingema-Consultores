// Coordinador ÚNICO de preparación visual de Cesium (InGe Earth y selector de
// Calicatas). No dibuja nada: el host Android posee la única pantalla de carga
// y la retira solo con VISUAL_READY de la sesión vigente.
// IDLE -> INITIALIZING -> STREAMING -> REFINING -> READY (+ CANCELLED).
(() => {
  'use strict';
  const viewer = window.viewer;
  const Cesium = window.Cesium;
  const runtime = window.InGeEarthBaseRuntime;
  if (!viewer || !Cesium || !runtime) return;

  const STABLE_FRAMES = 3;          // fotogramas consecutivos completos y quietos
  const MIN_LUMA = 10;              // 0..255: rechaza un lienzo negro/vacío
  let session = 0;
  let stage = 'IDLE';
  let reason = '';
  let mapType = '';
  let startedAt = 0;
  let stableFrames = 0;
  let moving = false;
  let pollTimer = 0;
  const probe = document.createElement('canvas');
  probe.width = 12;
  probe.height = 12;
  const probeContext = probe.getContext('2d', { willReadFrequently: true });

  const post = (state) => {
    try {
      const bridge = window.InGeEarthUiBridge;
      if (bridge && typeof bridge.mapLoading === 'function')
        bridge.mapLoading(state, session, mapType, Math.round(performance.now() - startedAt));
      else if (window.InGeEarthTelemetry)
        window.InGeEarthTelemetry.post(`INGE_EARTH_MAP_LOADING ${state} session=${session} type=${mapType}`);
    } catch (ignored) {}
  };
  const poll = () => {
    clearTimeout(pollTimer);
    pollTimer = setTimeout(() => { if (stage !== 'IDLE' && stage !== 'READY') viewer.scene.requestRender(); }, 60);
  };
  const imageryReady = () => {
    if (!viewer.scene.globe.show) return true;
    let shown = 0;
    for (let i = 0; i < viewer.imageryLayers.length; i += 1) {
      const layer = viewer.imageryLayers.get(i);
      if (!layer.show) continue;
      shown += 1;
      if (layer.ready === false) return false;
    }
    return shown > 0;
  };
  const tilesetReady = () => {
    const tileset = runtime.getPhotorealisticTileset();
    return !tileset || !tileset.show || tileset.tilesLoaded === true;
  };
  const canvasHasContent = () => {
    try {
      const canvas = viewer.scene.canvas;
      probeContext.drawImage(canvas, canvas.width / 4, canvas.height / 4,
        canvas.width / 2, canvas.height / 2, 0, 0, probe.width, probe.height);
      const data = probeContext.getImageData(0, 0, probe.width, probe.height).data;
      let sum = 0;
      for (let i = 0; i < data.length; i += 4) sum += data[i] + data[i + 1] + data[i + 2];
      return sum / (data.length / 4 * 3) >= MIN_LUMA;
    } catch (ignored) {
      return true;   // sin lectura posible no se bloquea el mapa (lo cubre el timeout)
    }
  };

  viewer.camera.moveStart.addEventListener(() => { moving = true; stableFrames = 0; });
  viewer.camera.moveEnd.addEventListener(() => { moving = false; if (stage !== 'IDLE' && stage !== 'READY') poll(); });
  viewer.scene.postRender.addEventListener(() => {
    if (stage === 'IDLE' || stage === 'READY') return;
    if (stage === 'INITIALIZING') { stage = 'STREAMING'; post('ENGINE_READY'); }
    const globeOk = !viewer.scene.globe.show || viewer.scene.globe.tilesLoaded;
    const imageryOk = imageryReady() && globeOk;
    if (stage === 'STREAMING' && imageryOk) { stage = 'REFINING'; post('IMAGERY_READY'); }
    const complete = stage === 'REFINING' && imageryOk && tilesetReady() && !moving;
    stableFrames = complete ? stableFrames + 1 : 0;
    if (stableFrames === 1) post('VIEWPORT_REFINED');
    if (stableFrames >= STABLE_FRAMES) {
      if (canvasHasContent()) {
        stage = 'READY';
        post('VISUAL_READY');
        return;
      }
      stableFrames = 0;
    }
    poll();
  });

  const begin = (why, type) => {
    session += 1;
    reason = String(why || 'open');
    mapType = String(type || runtime.mapType || 'DEFAULT');
    stage = 'INITIALIZING';
    stableFrames = 0;
    startedAt = performance.now();
    post('BEGIN');
    viewer.scene.requestRender();
    poll();
    return session;
  };
  const cancel = () => {
    if (stage !== 'IDLE' && stage !== 'READY') post('CANCELLED');
    stage = 'IDLE';
    clearTimeout(pollTimer);
  };
  window.InGeMapLoading = {
    begin, cancel,
    retry: () => begin(reason || 'retry', mapType),
    isReady: () => stage === 'READY',
    stage: () => stage
  };

  // InGe Earth completo: cada aparición inicia la preparación (el selector usa
  // su propia entrada con el tipo de mapa elegido).
  const setVisible = window.InGeEarthSetVisible;
  if (typeof setVisible === 'function') {
    window.InGeEarthSetVisible = (visible) => {
      setVisible(visible);
      if (visible && !window.InGeEarthPickerActive) begin('earth', runtime.mapType);
      else if (!visible && !window.InGeEarthPickerActive) cancel();
    };
  }
})();

// Selector de coordenadas de Calicatas sobre el MISMO viewer de InGe Earth
// (un solo WebView y un solo motor Cesium). El host Android coloca el WebView
// sobre el área de mapa del selector QML; la ficha solo cambia cuando el
// técnico pulsa «Usar esta ubicación» en Qt. Aquí solo se elige el candidato.
(() => {
  'use strict';
  const viewer = window.viewer;
  const Cesium = window.Cesium;
  const ui = window.InGeEarthUi;
  const runtime = window.InGeEarthBaseRuntime;
  if (!viewer || !Cesium || !ui || !runtime) return;

  const PICK_HEIGHT_M = 1400;
  const OVERVIEW = { latitude: -9.2, longitude: -75.0, height: 2600000 };
  let active = false;
  let saved = null;
  let chosenMarker = null;
  let gpsMarker = null;
  let gpsAccuracy = null;
  let satelliteLayer = null;
  let satelliteRequested = false;
  let mapType = 'DEFAULT';
  let overlay = null;
  let pointLat = NaN;
  let pointLon = NaN;

  const log = (event) => {
    try { if (window.InGeEarthTelemetry) window.InGeEarthTelemetry.post(`INGE_EARTH_PICKER ${event}`); } catch (ignored) {}
  };
  const bridgeCall = (method, ...args) => {
    try {
      const bridge = window.InGeEarthUiBridge;
      if (bridge && typeof bridge[method] === 'function') return bridge[method](...args);
    } catch (ignored) {}
    return undefined;
  };
  const render = () => ui.requestRender();
  const parse = (payload) => {
    try { return typeof payload === 'string' ? JSON.parse(payload) : (payload || {}); }
    catch (ignored) { return {}; }
  };
  const validPoint = (lat, lon) => Number.isFinite(lat) && Number.isFinite(lon)
    && lat >= -90 && lat <= 90 && Math.abs(lon) <= 180;

  const ensureOverlay = () => {
    if (overlay) return overlay;
    overlay = document.createElement('section');
    overlay.id = 'earthPicker';
    overlay.className = 'earth-picker';
    overlay.hidden = true;
    overlay.innerHTML = `
      <div class="picker-types glass" role="group" aria-label="Tipo de mapa">
        <button type="button" data-picker-type="DEFAULT" aria-pressed="true">Mapa</button>
        <button type="button" data-picker-type="SATELLITE" aria-pressed="false">Satélite</button>
      </div>
      <div class="picker-readout glass" aria-live="polite">
        <span id="pickerHint">Toca el mapa para elegir el punto</span>
        <span id="pickerUtm" hidden></span>
      </div>`;
    overlay.addEventListener('click', (event) => {
      const button = event.target.closest('[data-picker-type]');
      if (button) setMapType(button.dataset.pickerType);
    });
    ['pointerdown', 'touchstart'].forEach((type) => overlay.addEventListener(type,
      (event) => { if (event.target.closest('.glass')) event.stopPropagation(); },
      type === 'touchstart' ? { passive: true } : undefined));
    document.body.appendChild(overlay);
    return overlay;
  };

  const renderTypes = () => {
    if (!overlay) return;
    overlay.querySelectorAll('[data-picker-type]').forEach((button) => {
      const selected = button.dataset.pickerType === mapType;
      button.classList.toggle('selected', selected);
      button.setAttribute('aria-pressed', String(selected));
      if (button.dataset.pickerType === 'SATELLITE') {
        button.disabled = !runtime.ionConfigured;
        button.title = runtime.ionConfigured ? 'Imagen satelital' : 'Requiere configurar Cesium ion';
      }
    });
  };

  // Mapa: capa de calles de InGe Earth (OSM o la configurada). Satélite: imagen
  // ion sobre el globo (más liviana que las teselas fotorrealistas 3D).
  const applyMapType = () => {
    const details = window.InGeEarthMapDetails;
    const defaultLayer = details && typeof details.ensureDefaultLayer === 'function'
      ? details.ensureDefaultLayer() : null;
    const satellite = mapType === 'SATELLITE' && runtime.ionConfigured;
    if (satellite && !satelliteLayer && !satelliteRequested) {
      satelliteRequested = true;
      const layer = Cesium.ImageryLayer.fromWorldImagery({ style: Cesium.IonWorldImageryStyle.AERIAL });
      layer.readyEvent.addEventListener(() => {
        satelliteLayer = layer;
        viewer.imageryLayers.add(layer);
        requestSnapshot();
        layer.show = active && mapType === 'SATELLITE';
        log('SATELLITE_READY');
        render();
      });
      layer.errorEvent.addEventListener(() => {
        satelliteRequested = false;
        ui.notify('No se pudo cargar la imagen satelital', 'error', 3000);
        log('SATELLITE_FAIL');
      });
    }
    if (satelliteLayer) satelliteLayer.show = satellite;
    if (defaultLayer) defaultLayer.show = !satellite;
    runtime.naturalEarthLayer.show = satellite ? !satelliteLayer : !defaultLayer;
    const tileset = runtime.getPhotorealisticTileset();
    if (tileset) tileset.show = false;
    viewer.scene.globe.show = true;
    renderTypes();
    render();
  };
  const setMapType = (type) => {
    if (type !== 'DEFAULT' && type !== 'SATELLITE') return;
    if (type === 'SATELLITE' && !runtime.ionConfigured) return;
    mapType = type;
    applyMapType();
    beginLoading('layer');
    // El tipo elegido viaja a Qt aunque aún no haya captura válida.
    if (type === 'DEFAULT') bridgeCall('pickerSnapshot', 'DEFAULT', pointLat, pointLon, 'data:image/jpeg;base64,');
    else requestSnapshot();
    log(`TYPE=${type}`);
  };

  const markerAt = (entity, latitude, longitude, color, size) => {
    const position = Cesium.Cartesian3.fromDegrees(longitude, latitude);
    if (entity) {
      if (entity.position && typeof entity.position.setValue === 'function') entity.position.setValue(position);
      else entity.position = position;
      return entity;
    }
    return viewer.entities.add({ position, point: ui.markerStyle(Cesium.Color.fromCssColorString(color), size) });
  };
  const showReadout = (latitude, longitude) => {
    if (!overlay) return;
    const hint = overlay.querySelector('#pickerHint');
    const utm = overlay.querySelector('#pickerUtm');
    hint.textContent = `${latitude.toFixed(6)}, ${longitude.toFixed(6)}`;
    let text = '';
    try { text = window.InGeEarthCoordinates.formatUtm({ latitude, longitude }); } catch (ignored) {}
    utm.textContent = text;
    utm.hidden = !text;
  };
  const flyTo = (latitude, longitude, height, duration) => {
    viewer.camera.flyTo({
      destination: Cesium.Cartesian3.fromDegrees(longitude, latitude, height),
      orientation: { heading: 0, pitch: -Cesium.Math.PI_OVER_TWO, roll: 0 },
      duration: duration === undefined ? 0.9 : duration
    });
  };

  const choose = (position) => {
    const coordinates = ui.toCoordinates(position);
    if (!coordinates || !validPoint(coordinates.latitude, coordinates.longitude)) return true;
    chosenMarker = markerAt(chosenMarker, coordinates.latitude, coordinates.longitude, '#ffb84d', 14);
    pointLat = coordinates.latitude;
    pointLon = coordinates.longitude;
    showReadout(coordinates.latitude, coordinates.longitude);
    requestSnapshot();
    render();
    // Altitud: el globo del selector es un elipsoide (no terreno); la cota real
    // la obtiene la ficha del DEM al confirmar. Solo viaja lat/lon.
    const accepted = bridgeCall('pickerSelected', coordinates.latitude, coordinates.longitude);
    log(`POINT_SELECTED delivered=${accepted === true}`);
    return true;
  };

  const enter = (payload) => {
    const options = parse(payload);
    if (!active) {
      saved = {
        destination: Cesium.Cartesian3.clone(viewer.camera.positionWC),
        direction: Cesium.Cartesian3.clone(viewer.camera.directionWC),
        up: Cesium.Cartesian3.clone(viewer.camera.upWC),
        tilt: viewer.scene.screenSpaceCameraController.enableTilt,
        look: viewer.scene.screenSpaceCameraController.enableLook,
        globeShow: viewer.scene.globe.show,
        naturalShow: runtime.naturalEarthLayer.show,
        mapType: runtime.mapType,
        tilesetShow: runtime.getPhotorealisticTileset() ? runtime.getPhotorealisticTileset().show : null
      };
    }
    active = true;
    window.InGeEarthPickerActive = true;
    document.body.classList.add('picker-mode');
    const boot = document.getElementById('earthBoot');
    if (boot) boot.classList.add('done');
    ensureOverlay().hidden = false;
    ui.closeTransientPanels();
    ui.setVisualOverlay('NONE');
    ui.setPageVisible(true);
    const controls = viewer.scene.screenSpaceCameraController;
    controls.enableTilt = false;
    controls.enableLook = false;
    mapType = options.mapType === 'SATELLITE' && runtime.ionConfigured ? 'SATELLITE' : 'DEFAULT';
    applyMapType();
    ui.setInteraction('PICKER', choose, null);
    beginLoading('picker');
    requestSnapshot();
    const latitude = Number(options.latitude);
    const longitude = Number(options.longitude);
    pointLat = NaN;
    pointLon = NaN;
    if (options.hasPoint && validPoint(latitude, longitude)) {
      pointLat = latitude;
      pointLon = longitude;
      chosenMarker = markerAt(chosenMarker, latitude, longitude, '#ffb84d', 14);
      showReadout(latitude, longitude);
      flyTo(latitude, longitude, PICK_HEIGHT_M, 0);
    } else {
      if (chosenMarker) { viewer.entities.remove(chosenMarker); chosenMarker = null; }
      overlay.querySelector('#pickerHint').textContent = 'Toca el mapa para elegir el punto';
      overlay.querySelector('#pickerUtm').hidden = true;
      flyTo(OVERVIEW.latitude, OVERVIEW.longitude, OVERVIEW.height, 0);
    }
    viewer.resize();
    render();
    log(`ENTER hasPoint=${Boolean(options.hasPoint)} ion=${runtime.ionConfigured} type=${mapType}`);
    return true;
  };

  // Punto enviado desde Qt: lectura GPS (azul, con precisión) o candidato.
  const setPoint = (payload) => {
    if (!active) return false;
    const point = parse(payload);
    const latitude = Number(point.latitude);
    const longitude = Number(point.longitude);
    if (!validPoint(latitude, longitude)) return false;
    const accuracy = Number(point.accuracy);
    pointLat = latitude;
    pointLon = longitude;
    if (point.kind === 'gps') {
      gpsMarker = markerAt(gpsMarker, latitude, longitude, '#3ba7ff', 13);
      if (Number.isFinite(accuracy) && accuracy > 0) {
        if (!gpsAccuracy) {
          gpsAccuracy = viewer.entities.add({ position: Cesium.Cartesian3.fromDegrees(longitude, latitude), ellipse: {
            semiMajorAxis: accuracy, semiMinorAxis: accuracy,
            material: Cesium.Color.fromCssColorString('#3ba7ff').withAlpha(0.22) } });
        } else {
          gpsAccuracy.position = Cesium.Cartesian3.fromDegrees(longitude, latitude);
          gpsAccuracy.ellipse.semiMajorAxis = accuracy;
          gpsAccuracy.ellipse.semiMinorAxis = accuracy;
        }
      }
      if (point.selected && chosenMarker) { viewer.entities.remove(chosenMarker); chosenMarker = null; }
    } else {
      chosenMarker = markerAt(chosenMarker, latitude, longitude, '#ffb84d', 14);
    }
    showReadout(latitude, longitude);
    if (point.fly !== false)
      flyTo(latitude, longitude, Math.max(PICK_HEIGHT_M, Number.isFinite(accuracy) ? accuracy * 40 : 0));
    render();
    return true;
  };

  // Carga visible (P0.2): cubre el mapa hasta que Cesium declara las teselas
  // cargadas y pinta un fotograma; timeout con reintento, nunca bloquea.
  // Una sola pantalla de carga (host Android). El selector solo abre sesiones.
  const beginLoading = (reason) => {
    if (window.InGeMapLoading) window.InGeMapLoading.begin(reason, mapType);
  };
  const reload = () => {
    if (!active) return false;
    applyMapType();
    beginLoading('retry');
    return true;
  };

  // Miniatura satelital (P0.3): se captura DENTRO de postRender (búfer WebGL
  // válido), solo con teselas cargadas, cámara quieta y el punto cerca del
  // centro; un fotograma casi negro se descarta. Nunca al cerrar.
  let snapshotTimer = 0;
  let snapshotWanted = false;
  const requestSnapshot = () => {
    clearTimeout(snapshotTimer);
    snapshotTimer = setTimeout(() => { snapshotWanted = true; render(); }, 700);
  };
  const captureSnapshot = () => {
    if (!validPoint(pointLat, pointLon) || mapType !== 'SATELLITE') return;
    try {
      const at = Cesium.SceneTransforms.worldToWindowCoordinates
        ? Cesium.SceneTransforms.worldToWindowCoordinates(viewer.scene, Cesium.Cartesian3.fromDegrees(pointLon, pointLat))
        : Cesium.SceneTransforms.wgs84ToWindowCoordinates(viewer.scene, Cesium.Cartesian3.fromDegrees(pointLon, pointLat));
      const css = viewer.scene.canvas;
      if (!at || Math.abs(at.x / css.clientWidth - 0.5) > 0.3 || Math.abs(at.y / css.clientHeight - 0.5) > 0.3) return;
      const source = viewer.scene.canvas;
      if (!source.width || !source.height) return;
      const scale = Math.min(1, 480 / source.width);
      const thumb = document.createElement('canvas');
      thumb.width = Math.round(source.width * scale);
      thumb.height = Math.round(source.height * scale);
      thumb.getContext('2d').drawImage(source, 0, 0, thumb.width, thumb.height);
      const pixels = thumb.getContext('2d').getImageData(0, 0, thumb.width, thumb.height).data;
      let luma = 0, count = 0;
      for (let i = 0; i < pixels.length; i += 160) { luma += pixels[i] + pixels[i + 1] + pixels[i + 2]; count += 3; }
      if (!count || luma / count < 12) { log('SNAPSHOT_DISCARDED_DARK'); return; }
      const image = thumb.toDataURL('image/jpeg', 0.72);
      const delivered = bridgeCall('pickerSnapshot', mapType, pointLat, pointLon, image);
      log(`SNAPSHOT type=${mapType} bytes=${image.length} delivered=${delivered === true}`);
    } catch (error) {
      log('SNAPSHOT_FAILED');
    }
  };

  const exit = () => {
    if (!active) return false;
    clearTimeout(snapshotTimer);
    active = false;
    window.InGeEarthPickerActive = false;
    ui.clearInteraction();
    [chosenMarker, gpsMarker, gpsAccuracy].forEach((entity) => { if (entity) viewer.entities.remove(entity); });
    chosenMarker = null; gpsMarker = null; gpsAccuracy = null;
    if (satelliteLayer) satelliteLayer.show = false;
    if (saved) {
      const controls = viewer.scene.screenSpaceCameraController;
      controls.enableTilt = saved.tilt;
      controls.enableLook = saved.look;
      runtime.naturalEarthLayer.show = saved.naturalShow;
      viewer.scene.globe.show = saved.globeShow;
      const tileset = runtime.getPhotorealisticTileset();
      if (tileset && saved.tilesetShow !== null) tileset.show = saved.tilesetShow;
      const details = window.InGeEarthMapDetails;
      if (details && typeof details.restoreMapType === 'function') details.restoreMapType(saved.mapType);
      viewer.camera.setView({ destination: saved.destination, orientation: { direction: saved.direction, up: saved.up } });
    }
    saved = null;
    document.body.classList.remove('picker-mode');
    if (overlay) overlay.hidden = true;
    ui.setPageVisible(false);
    log('EXIT');
    return true;
  };

  viewer.scene.postRender.addEventListener(() => {
    if (!active) return;
    // Miniatura solo desde un mapa ya preparado (VISUAL_READY del coordinador).
    const tilesReady = viewer.scene.globe.tilesLoaded
      && !!window.InGeMapLoading && window.InGeMapLoading.isReady();
    if (snapshotWanted && tilesReady) { snapshotWanted = false; captureSnapshot(); }
    else if (snapshotWanted) render();
  });
  viewer.camera.moveEnd.addEventListener(() => { if (active) requestSnapshot(); });

  window.InGeEarthPicker = { enter, exit, setPoint, setMapType, reload, isActive: () => active };
})();

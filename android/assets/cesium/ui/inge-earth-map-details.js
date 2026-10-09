(() => {
  'use strict';
  const viewer = window.viewer;
  const Cesium = window.Cesium;
  const ui = window.InGeEarthUi;
  const runtime = window.InGeEarthBaseRuntime;
  if (!viewer || !Cesium || !ui || !runtime) return;
  const $ = ui.$;
  const configValue = (method) => {
    try {
      const bridge = window.InGeEarthConfig;
      return bridge && typeof bridge[method] === 'function'
        ? String(bridge[method]() || '').trim() : '';
    } catch (ignored) { return ''; }
  };
  const config = Object.freeze({
    defaultMapUrl: configValue('getDefaultMapUrl'),
    terrainUrl: configValue('getTerrainUrl'),
    valhallaBaseUrl: configValue('getValhallaBaseUrl').replace(/\/+$/, '')
  });
  const state = {
    mapType: 'SATELLITE',
    reliefEnabled: false,
    reliefStatus: 'OFF',
    routeToolState: 'OFF'
  };
  let defaultMapLayer = null;
  let terrainGeneration = 0;
  let routeRequest = null;
  let origin = null;
  let destination = null;
  let originEntity = null;
  let destinationEntity = null;
  let routeEntity = null;

  const log = (message) => {
    try { if (window.InGeEarthTelemetry) window.InGeEarthTelemetry.post(`INGE_EARTH_MAP ${message}`); } catch (ignored) {}
  };
  const requestRender = () => window.requestEarthRender
    ? window.requestEarthRender() : viewer.scene.requestRender();
  const normalizedXyzUrl = (baseUrl) => {
    if (!baseUrl) return '';
    if (/\{z\}/i.test(baseUrl)) return baseUrl;
    return `${baseUrl.replace(/\/+$/, '')}/{z}/{x}/{y}.png`;
  };
  // Mapa base sin claves: si no se configura DEFAULT_MAP_URL se usan las
  // teselas públicas de OpenStreetMap (con su atribución). Producción puede
  // apuntar DEFAULT_MAP_URL a un servidor de teselas propio o contratado.
  const PUBLIC_OSM_TILES = 'https://tile.openstreetmap.org/{z}/{x}/{y}.png';
  const createDefaultImageryProvider = () => {
    const url = normalizedXyzUrl(config.defaultMapUrl) || PUBLIC_OSM_TILES;
    return new Cesium.UrlTemplateImageryProvider({
      url,
      maximumLevel: 19,
      credit: new Cesium.Credit('<a href="https://www.openstreetmap.org/copyright" target="_blank">© OpenStreetMap contributors</a>', true)
    });
  };
  const ensureDefaultMapLayer = () => {
    if (defaultMapLayer) return defaultMapLayer;
    defaultMapLayer = viewer.imageryLayers.addImageryProvider(createDefaultImageryProvider());
    defaultMapLayer.show = false;
    return defaultMapLayer;
  };
  const renderMapState = () => {
    runtime.mapType = state.mapType;
    const satellite = state.mapType === 'SATELLITE';
    const tileset = runtime.getPhotorealisticTileset();
    if (defaultMapLayer) defaultMapLayer.show = !satellite;
    runtime.naturalEarthLayer.show = satellite ? !tileset : !defaultMapLayer;
    if (tileset) tileset.show = satellite;
    viewer.scene.globe.show = !satellite || state.reliefEnabled || !tileset;
    document.querySelectorAll('[data-map-type]').forEach((button) => {
      const selected = button.dataset.mapType === state.mapType;
      button.classList.toggle('selected', selected);
      button.setAttribute('aria-pressed', String(selected));
    });
    $('reliefToggle').checked = state.reliefEnabled;
    runtime.reliefEnabled = state.reliefEnabled;
    requestRender();
  };
  const setMapType = (mapType) => {
    if (mapType !== 'DEFAULT' && mapType !== 'SATELLITE') return;
    try {
      if (mapType === 'DEFAULT') ensureDefaultMapLayer();
      state.mapType = mapType;
      renderMapState();
      log(`TYPE=${mapType} VIEWER_RECREATED=NO`);
    } catch (error) {
      ui.notify(error.message || 'No se pudo activar el mapa predeterminado', 'error', 3600);
      log(`DEFAULT_FAIL=${error && error.name ? error.name : 'ERROR'}`);
    }
  };
  const createTerrainProvider = () => {
    if (config.terrainUrl) {
      return Cesium.CesiumTerrainProvider.fromUrl(config.terrainUrl, {
        requestVertexNormals: true
      });
    }
    if (runtime.ionConfigured) {
      return Cesium.createWorldTerrainAsync({ requestVertexNormals: true });
    }
    return Promise.reject(new Error('NO_TERRAIN_ENDPOINT'));
  };
  const renderReliefStatus = (message) => {
    const status = $('reliefStatus');
    status.textContent = message || '';
    status.hidden = !message;
  };
  const setRelief = async (enabled) => {
    const generation = ++terrainGeneration;
    if (!enabled) {
      state.reliefEnabled = false;
      state.reliefStatus = 'OFF';
      viewer.terrainProvider = runtime.ellipsoidTerrain;
      $('reliefToggle').disabled = false;
      renderReliefStatus('');
      renderMapState();
      log('RELIEF=OFF');
      return;
    }
    state.reliefStatus = 'LOADING';
    $('reliefToggle').disabled = true;
    renderReliefStatus('Activando topografía…');
    try {
      const provider = await createTerrainProvider();
      if (generation !== terrainGeneration) return;
      viewer.terrainProvider = provider;
      state.reliefEnabled = true;
      state.reliefStatus = 'READY';
      renderReliefStatus(config.terrainUrl ? 'Terreno de empresa activo' : 'Cesium World Terrain activo');
      log(`RELIEF=ON SOURCE=${config.terrainUrl ? 'CONFIGURED_QUANTIZED_MESH' : 'CESIUM_WORLD_TERRAIN'}`);
    } catch (error) {
      if (generation !== terrainGeneration) return;
      viewer.terrainProvider = runtime.ellipsoidTerrain;
      state.reliefEnabled = false;
      state.reliefStatus = 'ERROR';
      renderReliefStatus('RELIEF_RUNTIME_BLOCKER=NO_TERRAIN_ENDPOINT');
      ui.notify('No hay un proveedor de relieve disponible', 'error', 3600);
      log('RELIEF_RUNTIME_BLOCKER=NO_TERRAIN_ENDPOINT');
    } finally {
      if (generation === terrainGeneration) {
        $('reliefToggle').disabled = false;
        renderMapState();
      }
    }
  };

  const decodePolyline6 = (encoded) => {
    const coordinates = [];
    let index = 0;
    let latitude = 0;
    let longitude = 0;
    while (index < encoded.length) {
      const nextValue = () => {
        let result = 0;
        let shift = 0;
        let byte;
        do {
          if (index >= encoded.length) throw new Error('INVALID_ROUTE_SHAPE');
          byte = encoded.charCodeAt(index++) - 63;
          result |= (byte & 0x1f) << shift;
          shift += 5;
        } while (byte >= 0x20);
        return result & 1 ? ~(result >> 1) : result >> 1;
      };
      latitude += nextValue();
      longitude += nextValue();
      coordinates.push([longitude / 1e6, latitude / 1e6]);
    }
    return coordinates;
  };
  const routeMarker = (point, color) => viewer.entities.add({
    position: point.position,
    point: ui.markerStyle(Cesium.Color.fromCssColorString(color), 12)
  });
  const removeEntity = (entity) => { if (entity) viewer.entities.remove(entity); };
  const clearRouteGeometry = () => {
    removeEntity(routeEntity);
    routeEntity = null;
    requestRender();
  };
  const formatDuration = (seconds) => {
    const minutes = Math.max(0, Math.round(seconds / 60));
    const hours = Math.floor(minutes / 60);
    const rest = minutes % 60;
    return hours ? `${hours} h ${String(rest).padStart(2, '0')} min` : `${rest} min`;
  };
  const renderRouteUi = () => {
    const sheet = $('routeSheet');
    const prompt = $('routePrompt');
    const result = $('routeResult');
    sheet.hidden = state.routeToolState === 'OFF';
    prompt.classList.toggle('error', state.routeToolState === 'ERROR');
    const prompts = {
      SELECT_ORIGIN: 'Selecciona el origen en el mapa',
      SELECT_DESTINATION: 'Selecciona el destino en el mapa',
      CALCULATING: 'Calculando por la red vial…',
      RESULT: 'Ruta calculada con Valhalla',
      ERROR: config.valhallaBaseUrl ? 'No se pudo calcular una ruta vial' : 'ROUTE_BACKEND_NOT_CONFIGURED'
    };
    prompt.textContent = prompts[state.routeToolState] || '';
    result.hidden = state.routeToolState !== 'RESULT';
    sheet.querySelector('[data-route-action="destination"]').hidden = !origin;
    sheet.querySelector('[data-route-action="recalculate"]').hidden = !(origin && destination);
    sheet.querySelectorAll('button').forEach((button) => {
      if (button.id !== 'routeClose') button.disabled = state.routeToolState === 'CALCULATING';
    });
  };
  const pointFromCartesian = (position) => {
    const coordinate = ui.toCoordinates(position);
    return coordinate ? {
      latitude: coordinate.latitude,
      longitude: coordinate.longitude,
      position: Cesium.Cartesian3.clone(position)
    } : null;
  };
  const drawRoute = (coordinates) => {
    clearRouteGeometry();
    if (coordinates.length < 2) return;
    routeEntity = viewer.entities.add({
      polyline: {
        positions: coordinates.map((value) => Cesium.Cartesian3.fromDegrees(value[0], value[1], 8)),
        width: 6,
        material: Cesium.Color.fromCssColorString('#4dd6a5'),
        depthFailMaterial: Cesium.Color.fromCssColorString('#4dd6a5').withAlpha(.85),
        clampToGround: state.mapType === 'DEFAULT'
      }
    });
    requestRender();
  };
  const calculateRoute = async () => {
    if (!origin || !destination) return;
    clearRouteGeometry();
    if (!config.valhallaBaseUrl) {
      state.routeToolState = 'ERROR';
      renderRouteUi();
      log('ROUTE_RUNTIME_BLOCKER=ROUTE_BACKEND_NOT_CONFIGURED');
      return;
    }
    state.routeToolState = 'CALCULATING';
    renderRouteUi();
    routeRequest = new AbortController();
    try {
      const response = await fetch(`${config.valhallaBaseUrl}/route`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json', Accept: 'application/json' },
        body: JSON.stringify({
          locations: [
            { lat: origin.latitude, lon: origin.longitude, type: 'break' },
            { lat: destination.latitude, lon: destination.longitude, type: 'break' }
          ],
          costing: 'auto',
          units: 'kilometers'
        }),
        signal: routeRequest.signal
      });
      if (!response.ok) throw new Error(`VALHALLA_HTTP_${response.status}`);
      const data = await response.json();
      const trip = data && data.trip;
      const summary = trip && trip.summary;
      if (!summary || !Number.isFinite(Number(summary.length)) || !Number.isFinite(Number(summary.time)))
        throw new Error('INVALID_VALHALLA_RESPONSE');
      const coordinates = [];
      (trip.legs || []).forEach((leg) => {
        if (!leg || typeof leg.shape !== 'string') return;
        const decoded = decodePolyline6(leg.shape);
        if (coordinates.length && decoded.length) decoded.shift();
        coordinates.push(...decoded);
      });
      drawRoute(coordinates);
      $('routeDistance').textContent = `${Number(summary.length).toFixed(Number(summary.length) >= 10 ? 1 : 2)} km`;
      $('routeTime').textContent = formatDuration(Number(summary.time));
      state.routeToolState = 'RESULT';
      log('ROUTE=RESULT CONTRACT=VALHALLA_3_8_3');
    } catch (error) {
      if (error && error.name === 'AbortError') return;
      state.routeToolState = 'ERROR';
      ui.notify('No se pudo calcular la ruta vial', 'error', 3600);
      log(`ROUTE_FAIL=${error && error.message ? error.message : 'ERROR'}`);
    } finally {
      routeRequest = null;
      renderRouteUi();
    }
  };
  const selectOrigin = () => {
    state.routeToolState = 'SELECT_ORIGIN';
    ui.setInteraction('ROUTE_ORIGIN', (position) => {
      const point = pointFromCartesian(position);
      if (!point) return true;
      removeEntity(originEntity);
      origin = point;
      originEntity = routeMarker(point, '#55d6a7');
      if (destination) { ui.pauseInteraction(); calculateRoute(); }
      else selectDestination();
      requestRender();
      return true;
    });
    ui.setVisualOverlay('BOTTOM_SHEET');
    renderRouteUi();
  };
  const selectDestination = () => {
    if (!origin) { selectOrigin(); return; }
    state.routeToolState = 'SELECT_DESTINATION';
    ui.setInteraction('ROUTE_DESTINATION', (position) => {
      const point = pointFromCartesian(position);
      if (!point) return true;
      removeEntity(destinationEntity);
      destination = point;
      destinationEntity = routeMarker(point, '#ffb84d');
      ui.pauseInteraction();
      calculateRoute();
      requestRender();
      return true;
    });
    ui.setVisualOverlay('BOTTOM_SHEET');
    renderRouteUi();
  };
  const startRoute = () => {
    ui.closeTransientPanels();
    $('layersSheet').hidden = true;
    $('routeSheet').hidden = false;
    selectOrigin();
  };
  const closeRoute = () => {
    if (routeRequest) routeRequest.abort();
    routeRequest = null;
    removeEntity(originEntity);
    removeEntity(destinationEntity);
    clearRouteGeometry();
    originEntity = null;
    destinationEntity = null;
    origin = null;
    destination = null;
    state.routeToolState = 'OFF';
    $('routeSheet').hidden = true;
    if (/^ROUTE_/.test(ui.getInteractionMode())) ui.clearInteraction();
    ui.setVisualOverlay('NONE');
    requestRender();
  };
  const setVisible = (visible) => {
    if (!visible) closeRoute();
    else renderMapState();
  };

  document.querySelectorAll('[data-map-type]').forEach((button) => {
    button.addEventListener('click', () => setMapType(button.dataset.mapType));
  });
  $('reliefToggle').addEventListener('change', (event) => setRelief(event.target.checked));
  $('routeDurationButton').addEventListener('click', startRoute);
  $('routeClose').addEventListener('click', closeRoute);
  $('routeSheet').addEventListener('click', (event) => {
    const button = event.target.closest('[data-route-action]');
    if (!button) return;
    const action = button.dataset.routeAction;
    if (action === 'origin') selectOrigin();
    else if (action === 'destination') selectDestination();
    else if (action === 'recalculate') calculateRoute();
    else if (action === 'close') closeRoute();
  });
  // Selector de Calicatas: usa la misma capa de calles y, al salir, devuelve
  // a InGe Earth exactamente el tipo de mapa que tenía.
  const restoreMapType = (mapType) => {
    if (mapType === 'DEFAULT' || mapType === 'SATELLITE') state.mapType = mapType;
    renderMapState();
  };
  window.InGeEarthMapDetails = {
    state,
    setMapType,
    restoreMapType,
    ensureDefaultLayer: () => { try { return ensureDefaultMapLayer(); } catch (ignored) { return null; } },
    setRelief,
    startRoute,
    closeRoute,
    setVisible,
    config: Object.freeze({
      defaultMapConfigured: Boolean(config.defaultMapUrl),
      terrainConfigured: Boolean(config.terrainUrl || runtime.ionConfigured),
      valhallaConfigured: Boolean(config.valhallaBaseUrl)
    })
  };
  // Sin Cesium ion no hay imagen satelital detallada: InGe Earth arranca en el
  // mapa de calles (sin claves) en lugar del globo de baja resolución.
  if (!runtime.ionConfigured) setMapType('DEFAULT');
  renderMapState();
  renderRouteUi();
  log(`DEFAULT_MAP=${config.defaultMapUrl ? 'CONFIGURED' : 'PUBLIC_OSM'} TERRAIN=${config.terrainUrl || runtime.ionConfigured ? 'CONFIGURED' : 'NOT_CONFIGURED'} VALHALLA=${config.valhallaBaseUrl ? 'CONFIGURED' : 'NOT_CONFIGURED'}`);
})();

// Motor de mapa de InGe Earth sin interfaz (Visual Zero, 2026-10-10).
// Extraído de ui/inge-earth-map-details.js y ui/inge-earth-ui.js: mapa base
// (satélite fotorrealista / calles), relieve, ruteo vial Valhalla, geocodificación,
// selección en escena, normalización de fixes GPS nativos y vuelo de cámara.
// Sin DOM: ningún control, panel ni texto visible.
(() => {
  'use strict';
  const viewer = window.viewer;
  const Cesium = window.Cesium;
  const runtime = window.InGeEarthBaseRuntime;
  if (!viewer || !Cesium || !runtime) return;

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
    reliefStatus: 'OFF'
  };
  let defaultMapLayer = null;
  let terrainGeneration = 0;

  const log = (message) => {
    try { if (window.InGeEarthTelemetry) window.InGeEarthTelemetry.post(`INGE_EARTH_MAP ${message}`); } catch (ignored) {}
  };
  const requestRender = () => window.requestEarthRender
    ? window.requestEarthRender() : viewer.scene.requestRender();

  // ------------------------------------------------------------ Mapa base
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
  const applyMapState = () => {
    runtime.mapType = state.mapType;
    const satellite = state.mapType === 'SATELLITE';
    const tileset = runtime.getPhotorealisticTileset();
    if (defaultMapLayer) defaultMapLayer.show = !satellite;
    runtime.naturalEarthLayer.show = satellite ? !tileset : !defaultMapLayer;
    if (tileset) tileset.show = satellite;
    viewer.scene.globe.show = !satellite || state.reliefEnabled || !tileset;
    runtime.reliefEnabled = state.reliefEnabled;
    requestRender();
  };
  // Devuelve false si el tipo no es válido o la capa no pudo activarse.
  const setMapType = (mapType) => {
    if (mapType !== 'DEFAULT' && mapType !== 'SATELLITE') return false;
    try {
      if (mapType === 'DEFAULT') ensureDefaultMapLayer();
      state.mapType = mapType;
      applyMapState();
      log(`TYPE=${mapType} VIEWER_RECREATED=NO`);
      return true;
    } catch (error) {
      log(`DEFAULT_FAIL=${error && error.name ? error.name : 'ERROR'}`);
      return false;
    }
  };

  // -------------------------------------------------------------- Relieve
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
  // Resuelve con el estado final del relieve: OFF, READY, ERROR o
  // SUPERSEDED (otra solicitud posterior tomó el control).
  const setRelief = async (enabled) => {
    const generation = ++terrainGeneration;
    if (!enabled) {
      state.reliefEnabled = false;
      state.reliefStatus = 'OFF';
      viewer.terrainProvider = runtime.ellipsoidTerrain;
      applyMapState();
      log('RELIEF=OFF');
      return 'OFF';
    }
    state.reliefStatus = 'LOADING';
    try {
      const provider = await createTerrainProvider();
      if (generation !== terrainGeneration) return 'SUPERSEDED';
      viewer.terrainProvider = provider;
      state.reliefEnabled = true;
      state.reliefStatus = 'READY';
      log(`RELIEF=ON SOURCE=${config.terrainUrl ? 'CONFIGURED_QUANTIZED_MESH' : 'CESIUM_WORLD_TERRAIN'}`);
      return 'READY';
    } catch (error) {
      if (generation !== terrainGeneration) return 'SUPERSEDED';
      viewer.terrainProvider = runtime.ellipsoidTerrain;
      state.reliefEnabled = false;
      state.reliefStatus = 'ERROR';
      log('RELIEF_RUNTIME_BLOCKER=NO_TERRAIN_ENDPOINT');
      return 'ERROR';
    } finally {
      if (generation === terrainGeneration) applyMapState();
    }
  };

  // ---------------------------------------------------- Ruteo vial Valhalla
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
  // Contrato Valhalla 3.8.3: /route con costing auto. Lanza
  // ROUTE_BACKEND_NOT_CONFIGURED, VALHALLA_HTTP_<status>,
  // INVALID_VALHALLA_RESPONSE o AbortError.
  const requestRoute = async (origin, destination, signal) => {
    if (!config.valhallaBaseUrl) {
      log('ROUTE_RUNTIME_BLOCKER=ROUTE_BACKEND_NOT_CONFIGURED');
      throw new Error('ROUTE_BACKEND_NOT_CONFIGURED');
    }
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
      signal
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
    log('ROUTE=RESULT CONTRACT=VALHALLA_3_8_3');
    return { lengthKm: Number(summary.length), timeSeconds: Number(summary.time), coordinates };
  };

  // ------------------------------------------------ Geodesia y selección
  const toCoordinates = (cartesian) => {
    if (!Cesium.defined(cartesian)) return null;
    const value = Cesium.Cartographic.fromCartesian(cartesian);
    if (!value) return null;
    const result = { latitude: Cesium.Math.toDegrees(value.latitude), longitude: Cesium.Math.toDegrees(value.longitude), height: value.height };
    return Number.isFinite(result.latitude) && Number.isFinite(result.longitude) ? result : null;
  };
  const pickScenePosition = (screenPosition) => {
    let position;
    if (viewer.scene.pickPositionSupported) {
      try { position = viewer.scene.pickPosition(screenPosition); } catch (ignored) {}
    }
    if (!Cesium.defined(position)) {
      try { const ray = viewer.camera.getPickRay(screenPosition); position = ray ? viewer.scene.globe.pick(ray, viewer.scene) : undefined; } catch (ignored) {}
    }
    if (!Cesium.defined(position)) {
      try { position = viewer.camera.pickEllipsoid(screenPosition, viewer.scene.globe.ellipsoid); } catch (ignored) {}
    }
    return Cesium.defined(position) ? position : null;
  };
  const flyToCoordinates = (coordinates) => {
    viewer.camera.flyTo({
      destination: Cesium.Cartesian3.fromDegrees(coordinates.longitude, coordinates.latitude, Math.max(1800, (coordinates.height || 0) + 1800)),
      orientation: { heading: 0, pitch: Cesium.Math.toRadians(-55), roll: 0 }, duration: 1.25
    });
  };

  // Geocodificación: coordenadas WGS84/UTM locales; nombres vía el servicio
  // Google de Cesium ion (mismo proveedor que las teselas fotorrealistas).
  let geocoderService = null;
  const geocode = async (rawText) => {
    const query = String(rawText || '').trim();
    if (!query) return null;
    const coordinates = window.InGeEarthCoordinates && window.InGeEarthCoordinates.parse(query);
    if (coordinates) {
      return { kind: /^UTM/i.test(query) ? 'UTM' : 'WGS84', coordinates,
        destination: Cesium.Cartesian3.fromDegrees(coordinates.longitude, coordinates.latitude, coordinates.height || 0) };
    }
    if (!runtime.ionConfigured) throw new Error('GEOCODER_UNAVAILABLE');
    if (!geocoderService)
      geocoderService = new Cesium.IonGeocoderService({ scene: viewer.scene, geocodeProviderType: Cesium.IonGeocodeProviderType.GOOGLE });
    const results = await geocoderService.geocode(query, Cesium.GeocodeType.SEARCH);
    if (!results || !results.length) throw new Error('NO_RESULTS');
    return { kind: 'NAME', displayName: results[0].displayName || query, destination: results[0].destination };
  };

  // ------------------------------------------------------- GPS nativo
  // Fix de InGeQtActivity (receiveNativeLocation) → coordenada normalizada.
  const normalizeLocationFix = (fix, nowMs) => {
    const latitude = Number(fix && fix.latitude);
    const longitude = Number(fix && fix.longitude);
    if (!Number.isFinite(latitude) || !Number.isFinite(longitude)) return null;
    const accuracy = Number(fix.accuracy);
    const timestampMs = Number(fix.timestampMs);
    return {
      latitude, longitude, height: Number(fix.altitude) || 0, accuracy,
      timestamp: Number.isFinite(timestampMs) && timestampMs > 0
        ? new Date(timestampMs).toISOString() : new Date(nowMs === undefined ? Date.now() : nowMs).toISOString(),
      source: fix.provider ? `InGe Earth GPS (${fix.provider})` : 'InGe Earth GPS'
    };
  };
  const isFinalFix = (fix, accuracy) => Boolean(fix && fix.final) || accuracy <= 5;

  window.InGeEarthMapEngine = {
    state,
    config: Object.freeze({
      defaultMapConfigured: Boolean(config.defaultMapUrl),
      terrainConfigured: Boolean(config.terrainUrl || runtime.ionConfigured),
      valhallaConfigured: Boolean(config.valhallaBaseUrl)
    }),
    normalizedXyzUrl, setMapType, applyMapState,
    ensureDefaultLayer: () => { try { return ensureDefaultMapLayer(); } catch (ignored) { return null; } },
    setRelief, decodePolyline6, requestRoute,
    toCoordinates, pickScenePosition, flyToCoordinates, geocode,
    normalizeLocationFix, isFinalFix
  };
  // Sin Cesium ion no hay imagen satelital detallada: el motor arranca en el
  // mapa de calles (sin claves) en lugar del globo de baja resolución.
  if (!runtime.ionConfigured) setMapType('DEFAULT');
  applyMapState();
  log(`DEFAULT_MAP=${config.defaultMapUrl ? 'CONFIGURED' : 'PUBLIC_OSM'} TERRAIN=${config.terrainUrl || runtime.ionConfigured ? 'CONFIGURED' : 'NOT_CONFIGURED'} VALHALLA=${config.valhallaBaseUrl ? 'CONFIGURED' : 'NOT_CONFIGURED'}`);
})();

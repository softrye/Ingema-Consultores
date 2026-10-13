// InGe Earth 4.0 — MapLibre GL JS (globo) + OpenFreeMap + maplibre-gl-streetview.
// Corre en el WebView de InGeQtActivity (WebViewAssetLoader, sin acceso a
// archivos). Contrato con Android/Qt:
//   window.InGeEarth.command(name, argsJson)  acciones del Dock global
//   window.InGeEarth.handleBack()             true si consumió Atrás
//   window.InGeEarth.setInsets({top,bottom})  márgenes seguros (px CSS)
//   window.InGeEarthEngineSetVisible(bool)    visor mostrado / oculto
//   window.InGeEarthUi.receiveNativeLocation / receiveNativeLocationStatus  (GPS nativo)
import maplibregl from 'maplibre-gl';
import 'maplibre-gl/dist/maplibre-gl.css';
import 'mapillary-js/dist/mapillary.css';
import { StreetViewControl } from 'maplibre-gl-streetview';
import './earth.css';

const STYLE_URL = 'https://tiles.openfreemap.org/styles/liberty';
const INITIAL = { center: [-77.0428, -12.0464], zoom: 1.5, pitch: 0, bearing: 0 };   // [lng, lat]
const SV_PENDING = 'Configura Google Street View o Mapillary para activar las panorámicas';
const KEY = {
  camera: 'ingeearth.camera.v1',
  streetview: 'ingeearth.streetview.v1',
  satellite: 'ingeearth.satellite.v1',
};
const SAT_SOURCE = 'ingeearth-satellite';
const SAT_LAYER = 'ingeearth-satellite-layer';

const $ = (id) => document.getElementById(id);
const nativeUi = window.InGeEarthUiBridge || null;
const nativeConfig = window.InGeEarthConfig || null;

function log(event, detail) {
  console.info('INGE_EARTH4_' + event + (detail ? ' ' + detail : ''));
}
function readJson(key) {
  try { return JSON.parse(window.localStorage.getItem(key) || 'null'); } catch (e) { return null; }
}
function writeJson(key, value) {
  try {
    if (value === null) window.localStorage.removeItem(key);
    else window.localStorage.setItem(key, JSON.stringify(value));
  } catch (e) { log('STORAGE_ERROR', e.name); }
}

// ------------------------------------------------------------- Mensajes
let messageTimer = 0;
function message(text, ms = 3500) {
  const el = $('message');
  el.textContent = text;
  el.hidden = false;
  clearTimeout(messageTimer);
  messageTimer = setTimeout(() => { el.hidden = true; }, ms);
}
function status(text) { $('status').textContent = text || ''; }
function fatal(text) {
  const el = $('fatal');
  el.textContent = text;
  el.hidden = false;
  log('FATAL', text);
}

// ------------------------------------------------------------- Paneles
const panels = ['panel-search', 'panel-layers', 'panel-streetview'];
function openPanel(id) {
  for (const p of panels) $(p).hidden = p !== id;
}
function togglePanel(id) {
  if ($(id).hidden) openPanel(id); else $(id).hidden = true;
}
function closePanels() {
  let closed = false;
  for (const p of panels) if (!$(p).hidden) { $(p).hidden = true; closed = true; }
  return closed;
}
document.querySelectorAll('[data-close]').forEach((b) => b.addEventListener('click', () => { $(b.dataset.close).hidden = true; }));

// ------------------------------------------------------------- Rendimiento
function performanceTier() {
  try { return String(nativeConfig ? nativeConfig.getEarthPerformanceTier() : 'MID'); } catch (e) { return 'MID'; }
}
const tier = performanceTier();
const pixelRatio = Math.min(window.devicePixelRatio || 1, tier === 'LOW' || tier === 'ULTRA_LOW' ? 1.25 : 2);

function validCamera(c) {
  return c && Array.isArray(c.center) && c.center.length === 2
    && Number.isFinite(c.center[0]) && Number.isFinite(c.center[1])
    && Number.isFinite(c.zoom) && Number.isFinite(c.bearing) && Number.isFinite(c.pitch);
}

// ------------------------------------------------------------- Mapa
let map = null;
try {
  const saved = readJson(KEY.camera);
  const camera = validCamera(saved) ? saved : INITIAL;
  map = new maplibregl.Map({
    container: 'map',
    style: STYLE_URL,
    center: camera.center,
    zoom: camera.zoom,
    bearing: camera.bearing,
    pitch: camera.pitch,
    maxPitch: 75,
    pixelRatio,
    dragRotate: true,
    touchZoomRotate: true,
    touchPitch: true,
    attributionControl: { compact: true },
    fadeDuration: tier === 'LOW' || tier === 'ULTRA_LOW' ? 0 : 300,
  });
  log('MAP_CREATED', 'tier=' + tier + ' pixelRatio=' + pixelRatio);
} catch (e) {
  fatal('No se pudo iniciar el mapa (WebGL no disponible): ' + (e && e.message ? e.message : e));
}

if (map) {
  map.on('style.load', () => {
    map.setProjection({ type: 'globe' });
    log('STYLE_LOADED', 'projection=globe');
    status('');
    applySatellite();
  });
  map.on('error', (e) => {
    const text = e && e.error && e.error.message ? e.error.message : 'error desconocido';
    status('Error de cartografía: ' + text);
    log('MAP_ERROR', text);
  });
  map.getCanvas().addEventListener('webglcontextlost', (ev) => {
    ev.preventDefault();
    status('Se perdió el contexto gráfico; se recuperará al volver.');
    log('WEBGL_CONTEXT_LOST');
  });
  map.getCanvas().addEventListener('webglcontextrestored', () => {
    status('');
    log('WEBGL_CONTEXT_RESTORED');
  });

  let readoutFrame = 0;
  map.on('move', () => {
    if (readoutFrame) return;
    readoutFrame = requestAnimationFrame(() => { readoutFrame = 0; updateReadout(); });
  });
  let saveTimer = 0;
  map.on('moveend', () => {
    clearTimeout(saveTimer);
    saveTimer = setTimeout(() => {
      const c = map.getCenter();
      writeJson(KEY.camera, { center: [c.lng, c.lat], zoom: map.getZoom(), bearing: map.getBearing(), pitch: map.getPitch() });
    }, 400);
  });
  map.on('click', (e) => {
    if (streetView && !streetView.getState().collapsed) return;   // el control usa el toque
    selectPoint(e.lngLat, 'Punto seleccionado');
  });
  updateReadout();
}

function fmt(v) { return Number(v).toFixed(5); }
function updateReadout() {
  if (!map) return;
  const c = map.getCenter();
  $('readout').textContent = 'Lat ' + fmt(c.lat) + ' · Lon ' + fmt(c.lng) + ' · Z ' + map.getZoom().toFixed(1);
}

// ------------------------------------------------------------- Marcadores
let selected = null;
let selectedMarker = null;
let gpsMarker = null;
function markerElement(className) {
  const el = document.createElement('div');
  el.className = className;
  return el;
}
function selectPoint(lngLat, label) {
  selected = { lng: lngLat.lng, lat: lngLat.lat };
  if (!selectedMarker) selectedMarker = new maplibregl.Marker({ element: markerElement('pin-selected') });
  selectedMarker.setLngLat([selected.lng, selected.lat]).addTo(map);
  message(label + ': ' + fmt(selected.lat) + ', ' + fmt(selected.lng));
}

// ------------------------------------------------------------- Cámara
function flyToPoint(lat, lng, zoom, label) {
  if (!map) return;
  map.flyTo({ center: [lng, lat], zoom, bearing: map.getBearing(), pitch: map.getPitch(), essential: true });
  selectPoint({ lng, lat }, label || 'Coordenadas');
}
function goGlobal() {
  map.flyTo({ center: INITIAL.center, zoom: INITIAL.zoom, bearing: 0, pitch: 0, essential: true });
}

// ------------------------------------------------------------- Buscar (coordenadas)
function parseNumber(text) {
  const v = Number(String(text).trim().replace(',', '.'));
  return Number.isFinite(v) ? v : NaN;
}
$('search-go').addEventListener('click', () => {
  const lat = parseNumber($('search-lat').value);
  const lng = parseNumber($('search-lon').value);
  const zoomText = $('search-zoom').value.trim();
  const zoom = zoomText.length ? parseNumber(zoomText) : 15;
  const err = $('search-error');
  if (!(lat >= -90 && lat <= 90) || !(lng >= -180 && lng <= 180) || !(zoom >= 0 && zoom <= 22)) {
    err.textContent = 'Latitud entre -90 y 90, longitud entre -180 y 180, zoom entre 0 y 22.';
    err.hidden = false;
    return;
  }
  err.hidden = true;
  $('panel-search').hidden = true;
  flyToPoint(lat, lng, zoom, 'Coordenadas');
});

// ------------------------------------------------------------- GPS nativo
let gpsCentered = false;
function startGps() {
  if (!nativeUi || typeof nativeUi.requestLocation !== 'function') {
    message('El GPS nativo de InGe+ no está disponible en este entorno.');
    return;
  }
  gpsCentered = false;
  status('Buscando GPS…');
  nativeUi.requestLocation();
  log('GPS_REQUEST');
}
window.InGeEarthUi = Object.assign(window.InGeEarthUi || {}, {
  receiveNativeLocationStatus(payload) {
    const state = payload && payload.state ? String(payload.state) : '';
    const text = payload && payload.message ? String(payload.message) : '';
    status(text);
    if (state === 'error') message(text || 'No hay una posición GPS disponible.');
    log('GPS_STATUS', state);
  },
  receiveNativeLocation(fix) {
    const lat = Number(fix && fix.latitude);
    const lng = Number(fix && fix.longitude);
    if (!Number.isFinite(lat) || !Number.isFinite(lng)) return;
    const accuracy = Number(fix.accuracy);
    if (!gpsMarker) gpsMarker = new maplibregl.Marker({ element: markerElement('pin-gps') });
    gpsMarker.setLngLat([lng, lat]).addTo(map);
    status('GPS: ' + fmt(lat) + ', ' + fmt(lng) + (Number.isFinite(accuracy) ? ' ±' + Math.round(accuracy) + ' m' : ''));
    if (!gpsCentered) {
      gpsCentered = true;
      map.flyTo({ center: [lng, lat], zoom: Math.max(map.getZoom(), 15), essential: true });
    }
    log('GPS_FIX', 'accuracy=' + (Number.isFinite(accuracy) ? Math.round(accuracy) : '-'));
  },
});

// ------------------------------------------------------------- Satélite (fuente configurable)
function satelliteConfig() {
  const c = readJson(KEY.satellite);
  return c && validSatellite(c) ? c : null;
}
function validSatellite(c) {
  return typeof c.url === 'string' && /^https:\/\/\S+$/.test(c.url)
    && c.url.includes('{z}') && c.url.includes('{x}') && c.url.includes('{y}')
    && typeof c.attribution === 'string' && c.attribution.trim().length > 0;
}
let satelliteOn = false;
function refreshSatelliteUi() {
  const c = satelliteConfig();
  $('base-satellite').disabled = !c;
  $('satellite-state').textContent = c
    ? 'Fuente satelital configurada (' + c.attribution + ').'
    : 'Sin fuente satelital configurada. OpenFreeMap no ofrece imágenes satelitales.';
  document.querySelector('input[name="base"][value="' + (satelliteOn && c ? 'satellite' : 'map') + '"]').checked = true;
}
function applySatellite() {
  if (!map || !map.isStyleLoaded()) return;
  const c = satelliteConfig();
  if (map.getLayer(SAT_LAYER)) map.removeLayer(SAT_LAYER);
  if (map.getSource(SAT_SOURCE)) map.removeSource(SAT_SOURCE);
  if (satelliteOn && c) {
    map.addSource(SAT_SOURCE, {
      type: 'raster', tiles: [c.url], tileSize: 256,
      maxzoom: Number.isFinite(c.maxzoom) ? c.maxzoom : 19, attribution: c.attribution,
    });
    // Debajo de la primera capa de símbolos: las etiquetas siguen visibles.
    const firstSymbol = (map.getStyle().layers || []).find((l) => l.type === 'symbol');
    map.addLayer({ id: SAT_LAYER, type: 'raster', source: SAT_SOURCE }, firstSymbol ? firstSymbol.id : undefined);
  }
  refreshSatelliteUi();
}
document.querySelectorAll('input[name="base"]').forEach((r) => r.addEventListener('change', () => {
  satelliteOn = r.value === 'satellite' && r.checked;
  applySatellite();
}));
$('sat-save').addEventListener('click', () => {
  const maxzoom = parseNumber($('sat-maxzoom').value);
  const config = { url: $('sat-url').value.trim(), attribution: $('sat-attribution').value.trim(),
                   maxzoom: Number.isFinite(maxzoom) ? Math.round(maxzoom) : 19 };
  const err = $('sat-error');
  if (!validSatellite(config)) {
    err.textContent = 'La plantilla debe ser https e incluir {z}, {x} e {y}, y la atribución es obligatoria.';
    err.hidden = false;
    return;
  }
  err.hidden = true;
  writeJson(KEY.satellite, config);
  applySatellite();
  message('Fuente satelital guardada.');
});
$('sat-clear').addEventListener('click', () => {
  writeJson(KEY.satellite, null);
  satelliteOn = false;
  applySatellite();
});

// ------------------------------------------------------------- Street View
function svConfig() {
  const c = readJson(KEY.streetview) || {};
  return { googleApiKey: String(c.googleApiKey || ''), mapillaryAccessToken: String(c.mapillaryAccessToken || '') };
}
function hasSvCredentials() {
  const c = svConfig();
  return c.googleApiKey.length > 0 || c.mapillaryAccessToken.length > 0;
}
function refreshSvUi() {
  const c = svConfig();
  const providers = [c.googleApiKey ? 'Google Street View' : null, c.mapillaryAccessToken ? 'Mapillary' : null].filter(Boolean);
  $('sv-state').textContent = providers.length ? 'Proveedores configurados: ' + providers.join(' y ') + '.' : SV_PENDING + '.';
  $('sv-google').value = c.googleApiKey;
  $('sv-mapillary').value = c.mapillaryAccessToken;
}

let streetView = null;
if (map) {
  const c = svConfig();
  streetView = new StreetViewControl({
    collapsed: true,
    position: 'top-right',
    title: 'Street View',
    defaultProvider: c.googleApiKey ? 'google' : 'mapillary',
    googleApiKey: c.googleApiKey || undefined,
    mapillaryAccessToken: c.mapillaryAccessToken || undefined,
    showApiKeyInputs: false,
    clickToView: true,
    showMarker: true,
    panelWidth: Math.max(280, Math.min(window.innerWidth - 24, 460)),
    panelHeight: Math.max(220, Math.min(Math.round(window.innerHeight * 0.45), 360)),
  });
  map.addControl(streetView, 'top-right');
  streetView.on('expand', () => log('STREETVIEW_OPEN'));
  streetView.on('collapse', () => log('STREETVIEW_CLOSE'));
}
function openStreetView() {
  if (!streetView) return;
  if (!hasSvCredentials()) {
    message(SV_PENDING, 5000);
    refreshSvUi();
    openPanel('panel-streetview');
    log('STREETVIEW_PENDING_CREDENTIALS');
    return;
  }
  closePanels();
  streetView.expand();
  const target = selected || map.getCenter();
  // El proveedor consulta la cobertura real; sin cobertura muestra su aviso.
  streetView.showStreetView([target.lng, target.lat]);
}
$('sv-save').addEventListener('click', () => {
  const config = { googleApiKey: $('sv-google').value.trim(), mapillaryAccessToken: $('sv-mapillary').value.trim() };
  writeJson(KEY.streetview, config);
  if (streetView) streetView.setApiKeys({ googleApiKey: config.googleApiKey || null, mapillaryAccessToken: config.mapillaryAccessToken || null });
  refreshSvUi();
  message(hasSvCredentials() ? 'Credenciales guardadas en este dispositivo.' : SV_PENDING);
});
$('sv-clear').addEventListener('click', () => {
  writeJson(KEY.streetview, null);
  if (streetView) {
    streetView.setApiKeys({ googleApiKey: null, mapillaryAccessToken: null });
    streetView.collapse();
  }
  refreshSvUi();
});

// ------------------------------------------------------------- Contrato con InGe+
const commands = {
  zoomIn: () => map.zoomIn({ duration: 300 }),
  zoomOut: () => map.zoomOut({ duration: 300 }),
  rotateLeft: () => map.easeTo({ bearing: map.getBearing() - 45, duration: 400 }),
  rotateRight: () => map.easeTo({ bearing: map.getBearing() + 45, duration: 400 }),
  north: () => map.easeTo({ bearing: 0, duration: 400 }),
  tilt3d: () => map.easeTo({ pitch: 60, duration: 500 }),
  topView: () => map.easeTo({ pitch: 0, duration: 500 }),
  globalView: goGlobal,
  gps: startGps,
  search: () => togglePanel('panel-search'),
  layers: () => { refreshSatelliteUi(); togglePanel('panel-layers'); },
  streetview: openStreetView,
  streetviewSettings: () => { refreshSvUi(); togglePanel('panel-streetview'); },
  flyTo: (args) => {
    const lat = Number(args && args.lat);
    const lng = Number(args && args.lon);
    if (Number.isFinite(lat) && Number.isFinite(lng))
      flyToPoint(lat, lng, Number.isFinite(Number(args.zoom)) ? Number(args.zoom) : 16, args.label || 'Ubicación');
  },
};

window.InGeEarth = {
  command(name, argsJson) {
    if (!map) return false;
    const fn = commands[String(name)];
    if (!fn) { log('UNKNOWN_COMMAND', String(name)); return false; }
    let args = null;
    try { args = argsJson ? JSON.parse(argsJson) : null; } catch (e) { args = null; }
    fn(args);
    log('COMMAND', String(name));
    return true;
  },
  // Atrás: primero Street View, luego paneles; si no hay nada, lo resuelve InGe+.
  handleBack() {
    if (streetView && !streetView.getState().collapsed) { streetView.collapse(); return true; }
    return closePanels();
  },
  setInsets(insets) {
    const top = Math.max(0, Number(insets && insets.top) || 0);
    const bottom = Math.max(0, Number(insets && insets.bottom) || 0);
    document.documentElement.style.setProperty('--inset-top', top + 'px');
    document.documentElement.style.setProperty('--inset-bottom', bottom + 'px');
  },
};
window.InGeEarthEngineSetVisible = (visible) => {
  if (!map) return;
  if (visible) {
    map.resize();
    map.triggerRepaint();
  } else if (streetView) {
    streetView.collapse();
  }
};
window.addEventListener('resize', () => { if (map) map.resize(); });

refreshSvUi();
refreshSatelliteUi();
log('READY');

(() => {
  'use strict';
  const viewer = window.viewer;
  if (!viewer || !window.Cesium) return;
  const $ = (id) => document.getElementById(id);
  const ui = $('earthUi');
  const searchForm = $('earthSearch');
  const searchInput = $('earthSearchInput');
  const quickActions = $('earthQuickActions');
  const compassIcon = $('earthCompassIcon');
  const layersSheet = $('layersSheet');
  const contextSheet = $('contextSheet');
  const coordinateDetails = $('coordinateDetails');
  const aboutDetails = $('aboutDetails');
  const toast = $('earthToast');
  const workspaceSheet = $('workspaceSheet');
  let qualityTier = String(window.InGeEarthPerformanceTier || 'MID').toUpperCase();
  if (!window.InGeEarthPerformanceTier) {
    try { qualityTier = String(window.InGeEarthConfig.getEarthPerformanceTier() || 'MID').toUpperCase(); } catch (ignored) {}
  }
  ui.classList.toggle('low-tier', qualityTier === 'LOW');

  let toastTimer = 0;
  let currentCoordinates = null;
  let currentAccuracy = NaN;
  let selectionMarker = null;
  let locationMarker = null;
  let locationAccuracy = null;
  let bestLocationFix = null;
  let locationFlightDone = false;
  let lastLocationLatitude = NaN;
  let lastLocationLongitude = NaN;
  let lastLocationHeight = NaN;
  let lastLocationAccuracy = NaN;
  let lastLocationSheetSignature = '';
  let lastLoggedGpsAccuracy = '';
  let interactionMode = 'EXPLORE';
  let interactionClick = null;
  let interactionCleanup = null;
  let visualOverlay = 'NONE';

  const log = (event) => {
    try { if (window.InGeEarthTelemetry) window.InGeEarthTelemetry.post(`INGE_EARTH_PROJECTS ${event}`); } catch (ignored) {}
  };
  const notify = (message, type, duration) => {
    clearTimeout(toastTimer);
    toast.textContent = message;
    toast.className = `earth-toast glass visible ${type || 'info'}`;
    toastTimer = setTimeout(() => { toast.className = 'earth-toast glass'; }, duration || 2600);
  };
  const closeRouteTool = () => {
    if (window.InGeEarthMapDetails
        && window.InGeEarthMapDetails.state.routeToolState !== 'OFF')
      window.InGeEarthMapDetails.closeRoute();
  };
  const requestRender = () => window.requestEarthRender
    ? window.requestEarthRender() : viewer.scene.requestRender();
  const setText = (element, value) => {
    const text = String(value);
    if (element.textContent !== text) element.textContent = text;
  };
  const setHidden = (element, hidden) => {
    if (element.hidden !== hidden) element.hidden = hidden;
  };
  let sheetState = 'closed';
  const setSheetState = (state) => {
    if (sheetState === state) return;
    sheetState = state;
    contextSheet.classList.toggle('closed', state === 'closed');
    contextSheet.classList.toggle('collapsed', state === 'collapsed');
  };
  const setVisualOverlay = (kind) => {
    const next = kind || 'NONE';
    if (visualOverlay === next) return;
    visualOverlay = next;
    ui.dataset.overlay = visualOverlay;
  };
  const closeTransientPanels = (except) => {
    if (except !== 'layers' && !layersSheet.hidden) layersSheet.hidden = true;
    if (except !== 'workspace' && !workspaceSheet.hidden) workspaceSheet.hidden = true;
    if (except !== 'context') setSheetState('closed');
  };

  const formatDegrees = (value) => `${Number(value).toFixed(6)}°`;
  const formatAltitude = (value) => Number.isFinite(value) ? `${Math.round(value).toLocaleString('es-PE')} m` : 'No disponible';
  const formatDistance = (meters) => meters >= 1000 ? `${(meters / 1000).toFixed(meters >= 10000 ? 1 : 2)} km` : `${Math.round(meters)} m`;
  const formatArea = (meters) => meters >= 1000000 ? `${(meters / 1000000).toFixed(2)} km²` : meters >= 10000 ? `${(meters / 10000).toFixed(2)} ha` : `${Math.round(meters)} m²`;
  const showCoordinateSheet = (title, subtitle, coordinates) => {
    closeTransientPanels();
    setVisualOverlay('BOTTOM_SHEET');
    currentCoordinates = coordinates;
    currentAccuracy = Number(coordinates.accuracy);
    setText($('contextTitle'), title || 'Punto seleccionado');
    setText($('contextSubtitle'), subtitle || 'InGe Earth');
    setText($('contextLatitude'), formatDegrees(coordinates.latitude));
    setText($('contextLongitude'), formatDegrees(coordinates.longitude));
    setText($('contextAltitude'), formatAltitude(coordinates.height));
    setText($('contextUtm'), window.InGeEarthCoordinates.formatUtm(coordinates));
    setHidden(coordinateDetails, false);
    setHidden(aboutDetails, true);
    setHidden($('copyCoordinates'), false);
    setHidden($('copyUtm'), false);
    setHidden($('useInCalicata'), false);
    setSheetState('expanded');
  };
  const showAbout = () => {
    closeTransientPanels();
    setVisualOverlay('BOTTOM_SHEET');
    currentCoordinates = null;
    currentAccuracy = NaN;
    $('contextTitle').textContent = 'InGe Earth';
    $('contextSubtitle').textContent = 'InGe+';
    coordinateDetails.hidden = true;
    aboutDetails.hidden = false;
    $('copyCoordinates').hidden = true;
    $('copyUtm').hidden = true;
    $('useInCalicata').hidden = true;
    setSheetState('expanded');
  };
  const showSummary = (title, subtitle) => {
    closeTransientPanels();
    setVisualOverlay('BOTTOM_SHEET');
    currentCoordinates = null;
    currentAccuracy = NaN;
    $('contextTitle').textContent = title;
    $('contextSubtitle').textContent = subtitle;
    coordinateDetails.hidden = true;
    aboutDetails.hidden = true;
    $('copyCoordinates').hidden = true;
    $('copyUtm').hidden = true;
    $('useInCalicata').hidden = true;
    setSheetState('expanded');
  };
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
  const markerStyle = (color, size) => ({ pixelSize: size || 11, color, outlineColor: Cesium.Color.WHITE, outlineWidth: 2, disableDepthTestDistance: Number.POSITIVE_INFINITY });
  const setEntityPosition = (entity, position) => {
    if (entity.position && typeof entity.position.setValue === 'function')
      entity.position.setValue(position);
    else entity.position = position;
  };
  const setSelectionMarker = (position) => {
    if (selectionMarker) setEntityPosition(selectionMarker, position);
    else selectionMarker = viewer.entities.add({ position, point: markerStyle(Cesium.Color.fromCssColorString('#ffb84d'), 12) });
    requestRender();
  };
  const clearSelection = () => {
    if (selectionMarker) viewer.entities.remove(selectionMarker);
    selectionMarker = null;
    currentCoordinates = null;
    currentAccuracy = NaN;
    setSheetState('closed');
    requestRender();
  };
  const flyToCoordinates = (coordinates, title) => {
    const position = Cesium.Cartesian3.fromDegrees(coordinates.longitude, coordinates.latitude, coordinates.height || 0);
    setSelectionMarker(position);
    viewer.camera.flyTo({
      destination: Cesium.Cartesian3.fromDegrees(coordinates.longitude, coordinates.latitude, Math.max(1800, (coordinates.height || 0) + 1800)),
      orientation: { heading: 0, pitch: Cesium.Math.toRadians(-55), roll: 0 }, duration: 1.25
    });
    showCoordinateSheet(title, 'Resultado de búsqueda', coordinates);
  };
  const runSearch = async (rawText) => {
    const query = String(rawText || '').trim();
    if (!query) return;
    searchInput.blur();
    searchForm.classList.add('searching');
    closeTransientPanels();
    try {
      const coordinates = window.InGeEarthCoordinates.parse(query);
      if (coordinates) { flyToCoordinates(coordinates, /^UTM/i.test(query) ? 'Coordenadas UTM' : 'Coordenadas WGS84'); return; }
      const services = viewer.geocoder && viewer.geocoder.viewModel ? viewer.geocoder.viewModel.geocoderServices : [];
      const geocoder = services && services[0];
      if (!geocoder || typeof geocoder.geocode !== 'function') throw new Error('GEOCODER_UNAVAILABLE');
      const results = await geocoder.geocode(query, Cesium.GeocodeType.SEARCH);
      if (!results || !results.length) throw new Error('NO_RESULTS');
      viewer.camera.flyTo({ destination: results[0].destination, duration: 1.35 });
      showSummary(results[0].displayName || query, 'Resultado de búsqueda');
    } catch (error) {
      notify(error && error.message === 'NO_RESULTS' ? 'No se encontró la ubicación' : 'La búsqueda por nombre requiere conexión', 'error', 3400);
    } finally { searchForm.classList.remove('searching'); }
  };
  const globalView = () => { viewer.camera.flyHome(1.25); log('GLOBAL_VIEW'); notify('Vista global', 'success'); };
  const updateCameraUi = () => {
    if (!compassIcon) return;
    const heading = Cesium.Math.toDegrees(viewer.camera.heading);
    compassIcon.style.transform = `rotate(${-heading}deg)`;
  };
  const receiveNativeLocation = (fix) => {
    const latitude = Number(fix && fix.latitude);
    const longitude = Number(fix && fix.longitude);
    if (!Number.isFinite(latitude) || !Number.isFinite(longitude)) return;
    const accuracy = Number(fix.accuracy);
    const timestampMs = Number(fix.timestampMs);
    const coordinates = {
      latitude, longitude, height: Number(fix.altitude) || 0, accuracy,
      timestamp: Number.isFinite(timestampMs) && timestampMs > 0
        ? new Date(timestampMs).toISOString() : new Date().toISOString(),
      source: fix.provider ? `InGe Earth GPS (${fix.provider})` : 'InGe Earth GPS'
    };
    bestLocationFix = { ...fix, ...coordinates, accuracy };
    currentCoordinates = coordinates;
    currentAccuracy = accuracy;
    if (window.InGeEarthPageVisible === false) return;
    const positionChanged = lastLocationLatitude !== latitude
      || lastLocationLongitude !== longitude
      || lastLocationHeight !== coordinates.height;
    const accuracyChanged = lastLocationAccuracy !== accuracy;
    let entityChanged = false;
    if (locationMarker) {
      if (positionChanged) {
        setEntityPosition(locationMarker,
          Cesium.Cartesian3.fromDegrees(longitude, latitude, coordinates.height));
        entityChanged = true;
      }
    } else {
      locationMarker = viewer.entities.add({
        position: Cesium.Cartesian3.fromDegrees(longitude, latitude, coordinates.height),
        point: markerStyle(Cesium.Color.fromCssColorString('#3ba7ff'), 12)
      });
      entityChanged = true;
    }
    if (Number.isFinite(accuracy) && accuracy > 0) {
      if (!locationAccuracy) {
        locationAccuracy = viewer.entities.add({ position: Cesium.Cartesian3.fromDegrees(longitude, latitude), ellipse: {
          semiMajorAxis: accuracy, semiMinorAxis: accuracy,
          material: Cesium.Color.fromCssColorString('#3ba7ff').withAlpha(.22)
        } });
        entityChanged = true;
      } else {
        if (positionChanged) {
          setEntityPosition(locationAccuracy,
            Cesium.Cartesian3.fromDegrees(longitude, latitude));
          entityChanged = true;
        }
        if (accuracyChanged) {
          locationAccuracy.ellipse.semiMajorAxis.setValue(accuracy);
          locationAccuracy.ellipse.semiMinorAxis.setValue(accuracy);
          entityChanged = true;
        }
      }
    } else if (locationAccuracy) {
      viewer.entities.remove(locationAccuracy);
      locationAccuracy = null;
      entityChanged = true;
    }
    lastLocationLatitude = latitude;
    lastLocationLongitude = longitude;
    lastLocationHeight = coordinates.height;
    lastLocationAccuracy = accuracy;
    const isFinal = Boolean(fix.final) || accuracy <= 5;
    if (isFinal && !locationFlightDone) {
      locationFlightDone = true;
      viewer.camera.flyTo({ destination: Cesium.Cartesian3.fromDegrees(longitude, latitude, Math.max(450, coordinates.height + Math.max(350, accuracy * 35))), orientation: { heading: 0, pitch: Cesium.Math.toRadians(-55), roll: 0 }, duration: 1.2 });
    }
    const roundedAccuracy = Number.isFinite(accuracy) ? String(Math.round(accuracy)) : 'NA';
    const sheetSignature = `${latitude.toFixed(5)}|${longitude.toFixed(5)}|${Math.round(coordinates.height)}|${roundedAccuracy}|${fix.provider || ''}`;
    if (sheetSignature !== lastLocationSheetSignature) {
      lastLocationSheetSignature = sheetSignature;
      showCoordinateSheet('Mi ubicación', Number.isFinite(accuracy) ? `Precisión ±${roundedAccuracy} m · ${fix.provider || 'ubicación'}` : 'Ubicación actual', coordinates);
    }
    if (roundedAccuracy !== lastLoggedGpsAccuracy) {
      lastLoggedGpsAccuracy = roundedAccuracy;
      log(`GPS_BEST_FIX accuracy=${roundedAccuracy}`);
    }
    if (entityChanged) requestRender();
  };
  const receiveNativeLocationStatus = (status) => {
    if (!status) return;
    if (status.state === 'error') notify(status.message || 'No se pudo obtener la ubicación', 'error', 3400);
    else if (status.state === 'permission') notify('Activa Ubicación precisa para mejorar la exactitud', 'info', 3600);
    else if (status.state === 'searching') notify('Buscando ubicación precisa…');
  };
  const requestLocation = () => {
    closeRouteTool();
    closeTransientPanels();
    locationFlightDone = false;
    notify('Buscando ubicación precisa…');
    try { if (window.InGeEarthUiBridge && typeof window.InGeEarthUiBridge.requestLocation === 'function') { window.InGeEarthUiBridge.requestLocation(); return; } } catch (ignored) {}
    if (!navigator.geolocation) { receiveNativeLocationStatus({ state: 'error', message: 'La ubicación no está disponible' }); return; }
    navigator.geolocation.getCurrentPosition((position) => receiveNativeLocation({ latitude: position.coords.latitude, longitude: position.coords.longitude, altitude: position.coords.altitude, accuracy: position.coords.accuracy, final: true }), () => receiveNativeLocationStatus({ state: 'error' }), { enableHighAccuracy: true, timeout: 10000, maximumAge: 3000 });
  };
  const copyText = async (text, message) => {
    try { await navigator.clipboard.writeText(text); notify(message, 'success'); return; } catch (ignored) {}
    try { if (window.InGeEarthUiBridge) { window.InGeEarthUiBridge.copyText(text); notify(message, 'success'); return; } } catch (ignored) {}
    notify('No se pudo copiar', 'error');
  };
  const setInteraction = (mode, clickHandler, cleanup) => {
    if (interactionCleanup) interactionCleanup();
    interactionMode = mode || 'EXPLORE';
    interactionClick = clickHandler || null;
    interactionCleanup = cleanup || null;
    viewer.scene.canvas.style.cursor = interactionMode === 'EXPLORE' ? '' : 'crosshair';
    setSheetState('closed');
    if (visualOverlay === 'BOTTOM_SHEET') setVisualOverlay('NONE');
  };
  const clearInteraction = () => setInteraction('EXPLORE', null, null);
  const pauseInteraction = () => {
    interactionMode = 'EXPLORE';
    interactionClick = null;
    viewer.scene.canvas.style.cursor = '';
  };
  const focusCoordinate = (coordinate) => {
    const latitude = Number(coordinate && coordinate.latitude);
    const longitude = Number(coordinate && coordinate.longitude);
    if (!Number.isFinite(latitude) || !Number.isFinite(longitude)) return;
    flyToCoordinates({ latitude, longitude, height: Number(coordinate.altitude) || 0 }, coordinate.label || 'Coordenada de Calicata');
  };
  const useCurrentInCalicata = () => {
    if (!currentCoordinates) return;
    try {
      if (window.InGeEarthUiBridge && typeof window.InGeEarthUiBridge.usePointInCalicata === 'function') {
        const accepted = window.InGeEarthUiBridge.usePointInCalicata(
          currentCoordinates.latitude, currentCoordinates.longitude,
          Number(currentCoordinates.height) || 0,
          Number.isFinite(currentAccuracy) ? currentAccuracy : -1,
          currentCoordinates.timestamp || new Date().toISOString(),
          currentCoordinates.source || 'InGe Earth');
        if (accepted) log('POINT_SENT_TO_CALICATA');
        else notify('No se pudo enviar la coordenada a Calicatas', 'error');
        return;
      }
    } catch (error) {}
    notify('El enlace con Calicatas no está disponible', 'error');
  };
  const setPageVisible = (visible) => {
    window.InGeEarthPageVisible = Boolean(visible);
    if (typeof window.InGeEarthEngineSetVisible === 'function')
      window.InGeEarthEngineSetVisible(Boolean(visible));
    if (!visible) {
      clearTimeout(toastTimer);
      toastTimer = 0;
      toast.className = 'earth-toast glass';
      closeTransientPanels();
      setVisualOverlay('NONE');
    } else {
      updateCameraUi();
    }
    if (window.InGeEarthProjects && typeof window.InGeEarthProjects.setVisible === 'function')
      window.InGeEarthProjects.setVisible(Boolean(visible));
    if (window.InGeEarthMapDetails && typeof window.InGeEarthMapDetails.setVisible === 'function')
      window.InGeEarthMapDetails.setVisible(Boolean(visible));
  };

  const runEarthAction = (action) => {
    const key = String(action || '').toLowerCase();
    closeTransientPanels();
    if (key === 'explore') {
      if (window.InGeEarthProjects) window.InGeEarthProjects.endInteraction();
    } else if (key === 'location') {
      requestLocation();
    } else if (key === 'layers') {
      const open = layersSheet.hidden;
      if (open) closeRouteTool();
      closeTransientPanels(open ? 'layers' : '');
      layersSheet.hidden = !open;
      setVisualOverlay(open ? 'BOTTOM_SHEET' : 'NONE');
    } else if (key === 'point' || key === 'line' || key === 'polygon') {
      if (window.InGeEarthProjects)
        window.InGeEarthProjects.startDrawing(
          key === 'point' ? 'POINT' : key === 'line' ? 'POLYLINE' : 'POLYGON');
    } else if (key === 'measure' || key === 'area') {
      closeRouteTool();
      if (window.InGeEarthProjects)
        window.InGeEarthProjects.startMeasurement(key === 'area' ? 'AREA' : 'DISTANCE');
    } else if (key === 'route') {
      if (window.InGeEarthMapDetails) window.InGeEarthMapDetails.startRoute();
    } else if (key === 'projects') {
      if (window.InGeEarthProjects
          && typeof window.InGeEarthProjects.showProjects === 'function')
        window.InGeEarthProjects.showProjects();
    } else if (key === 'open-kml') {
      if (window.InGeEarthProjects) window.InGeEarthProjects.requestImport('TEMPORARY');
    } else if (key === 'global') {
      globalView();
    } else {
      return false;
    }
    log(`EARTH_ACTION_${key.toUpperCase()}`);
    return true;
  };

  quickActions.addEventListener('click', (event) => {
    const button = event.target.closest('button[data-earth-action]');
    if (button) runEarthAction(button.dataset.earthAction);
  });

  searchForm.addEventListener('submit', (event) => { event.preventDefault(); runSearch(searchInput.value); });
  layersSheet.querySelector('.sheet-close').addEventListener('click', () => { closeTransientPanels(); setVisualOverlay('NONE'); });
  $('sheetHandle').addEventListener('click', () => { if (!contextSheet.classList.contains('closed')) setSheetState(contextSheet.classList.contains('collapsed') ? 'expanded' : 'collapsed'); });
  $('closeContext').addEventListener('click', () => { setSheetState('closed'); setVisualOverlay('NONE'); });
  $('copyCoordinates').addEventListener('click', () => currentCoordinates && copyText(`${currentCoordinates.latitude.toFixed(6)}, ${currentCoordinates.longitude.toFixed(6)}`, 'WGS84 copiado'));
  $('copyUtm').addEventListener('click', () => currentCoordinates && copyText(window.InGeEarthCoordinates.formatUtm(currentCoordinates), 'UTM copiado'));
  $('useInCalicata').addEventListener('click', useCurrentInCalicata);
  ui.querySelectorAll('button, input, textarea, select, .floating-sheet, .context-sheet, .workspace-sheet, .earth-drawer, .interaction-bar, .route-sheet, .modal-scrim').forEach((element) => {
    element.addEventListener('pointerdown', (event) => event.stopPropagation());
    element.addEventListener('touchstart', (event) => event.stopPropagation(), { passive: true });
  });
  const mapHandler = new Cesium.ScreenSpaceEventHandler(viewer.scene.canvas);
  mapHandler.setInputAction((movement) => {
    closeTransientPanels();
    const position = pickScenePosition(movement.position);
    if (!position) return;
    if (interactionClick && interactionClick(position, movement.position) !== false) return;
    const picked = viewer.scene.pick(movement.position);
    if (window.InGeEarthProjects && window.InGeEarthProjects.handlePickedFeature(picked)) return;
    const coordinates = toCoordinates(position);
    if (!coordinates) return;
    setSelectionMarker(position);
    showCoordinateSheet('Punto seleccionado', 'InGe Earth', coordinates);
  }, Cesium.ScreenSpaceEventType.LEFT_CLICK);
  viewer.camera.moveEnd.addEventListener(updateCameraUi);
  window.InGeEarthUi = {
    viewer, $, log, notify, requestRender, closeTransientPanels,
    showCoordinateSheet, showSummary, toCoordinates, pickScenePosition, markerStyle, formatDistance,
    formatArea, globalView, requestLocation, setInteraction, clearInteraction, pauseInteraction,
    getInteractionMode: () => interactionMode, getBestLocation: () => bestLocationFix,
    receiveNativeLocation, receiveNativeLocationStatus, focusCoordinate, setPageVisible,
    setVisualOverlay, getVisualOverlay: () => visualOverlay
  };
  // Semantic dock context: Earth states the actions of its current mode and
  // the host dock renders them. Earth never draws a dock.
  const earthContextSets = {
    root: [['explore', 'Explorar', 'nav.map'], ['create', 'Crear', 'action.add'],
      ['location', 'Ubicar', 'map.location'], ['layers', 'Capas', 'map.layers'],
      ['tools', 'Herramientas', 'map.measure']],
    create: [['back', 'Atrás', 'action.close'], ['point', 'Punto', 'map.marker'],
      ['line', 'Línea', 'nav.map'], ['polygon', 'Polígono', 'map.layers']],
    tools: [['back', 'Atrás', 'action.close'], ['measure', 'Medir', 'map.measure'],
      ['area', 'Área', 'map.layers'], ['route', 'Ruta', 'nav.map'], ['more', 'Más', 'action.more']],
    more: [['back', 'Atrás', 'action.close'], ['projects', 'Proyectos', 'project.current'],
      ['open-kml', 'KML/KMZ', 'documents.upload'], ['global', 'Global', 'nav.map']]
  };
  let earthContextMode = 'root';
  let earthContextVisible = false;
  const publishEarthContext = () => {
    const bridge = window.InGeEarthUiBridge;
    if (!bridge || typeof bridge.publishContext !== 'function') return;
    if (!earthContextVisible) {
      bridge.clearContext('earth');
      return;
    }
    const actions = earthContextSets[earthContextMode].map(([id, label, icon], index) => ({
      id, label, icon, command: `earth.${id}`, priority: (index + 1) * 10
    }));
    bridge.publishContext(JSON.stringify({ ownerId: 'earth', contextId: `earth/${earthContextMode}`, actions }));
  };
  window.InGeEarthContext = {
    command: (payload) => {
      let data = null;
      let ok = false;
      try {
        data = typeof payload === 'string' ? JSON.parse(payload) : payload;
        if (data && data.ownerId === 'earth' && data.contextId === `earth/${earthContextMode}`) {
          const key = String(data.command || '').replace(/^earth\./, '');
          if (key === 'create' || key === 'tools' || key === 'more') {
            earthContextMode = key;
            publishEarthContext();
            ok = true;
          } else if (key === 'back') {
            earthContextMode = 'root';
            publishEarthContext();
            ok = true;
          } else {
            ok = runEarthAction(key) === true;
          }
        }
      } catch (error) {
        log('EARTH_CONTEXT_COMMAND_FAILED');
      } finally {
        const bridge = window.InGeEarthUiBridge;
        if (data && bridge && typeof bridge.completeContextCommand === 'function')
          bridge.completeContextCommand(JSON.stringify({ dispatchId: String(data.dispatchId || ''), ok }));
      }
    }
  };
  // Backdrop for the host dock glass: the strip behind the dock, downscaled,
  // copied right after a Cesium render (the WebGL buffer is still valid in
  // postRender). Never while the camera moves: one frame on entry and one
  // after the camera settles into its refined state; idle means no captures.
  // Each capture forces one extra Cesium frame, so there is no second one.
  const dockBackdropStripCss = 160;
  const dockBackdropCanvas = document.createElement('canvas');
  dockBackdropCanvas.width = 112;
  dockBackdropCanvas.height = 50;
  const dockBackdropContext = dockBackdropCanvas.getContext('2d', { willReadFrequently: true });
  let dockBackdropMoving = false;
  let dockBackdropWanted = false;
  let dockBackdropLastImage = '';
  let dockBackdropTimers = [];
  const cancelDockBackdrop = () => {
    dockBackdropTimers.forEach((id) => clearTimeout(id));
    dockBackdropTimers = [];
    dockBackdropWanted = false;
  };
  const requestDockBackdrop = (delaysMs) => {
    if (document.body.classList.contains('bare-ui')) return;
    cancelDockBackdrop();
    dockBackdropTimers = delaysMs.map((delay) => setTimeout(() => {
      if (!earthContextVisible || dockBackdropMoving) return;
      dockBackdropWanted = true;
      viewer.scene.requestRender();
    }, delay));
  };
  const captureDockBackdrop = () => {
    const bridge = window.InGeEarthUiBridge;
    if (!dockBackdropContext || !bridge || typeof bridge.publishDockBackdrop !== 'function') return;
    const source = viewer.scene.canvas;
    const cssHeight = source.clientHeight || window.innerHeight;
    if (!source.width || !source.height || !cssHeight) return;
    const stripPx = Math.min(source.height, Math.round(dockBackdropStripCss * source.height / cssHeight));
    try {
      dockBackdropContext.drawImage(source, 0, source.height - stripPx, source.width, stripPx,
        0, 0, dockBackdropCanvas.width, dockBackdropCanvas.height);
      const image = dockBackdropCanvas.toDataURL('image/jpeg', 0.6);
      if (image === dockBackdropLastImage) return;
      dockBackdropLastImage = image;
      const pixels = dockBackdropContext.getImageData(0, 0, dockBackdropCanvas.width, dockBackdropCanvas.height).data;
      let luma = 0;
      let count = 0;
      for (let i = 0; i < pixels.length; i += 64) {
        luma += 0.2126 * pixels[i] + 0.7152 * pixels[i + 1] + 0.0722 * pixels[i + 2];
        count += 1;
      }
      bridge.publishDockBackdrop(JSON.stringify({ owner: 'earth', image, luma: count ? luma / (count * 255) : -1 }));
    } catch (error) {
      log('EARTH_DOCK_BACKDROP_FAILED');
    }
  };
  viewer.camera.moveStart.addEventListener(() => {
    dockBackdropMoving = true;
    cancelDockBackdrop();
  });
  viewer.camera.moveEnd.addEventListener(() => {
    dockBackdropMoving = false;
    if (earthContextVisible) requestDockBackdrop([750]);
  });
  viewer.scene.postRender.addEventListener(() => {
    if (!earthContextVisible || dockBackdropMoving || !dockBackdropWanted) return;
    dockBackdropWanted = false;
    captureDockBackdrop();
  });
  window.InGeEarthSetVisible = (visible) => {
    setPageVisible(visible);
    earthContextVisible = Boolean(visible);
    if (!earthContextVisible) earthContextMode = 'root';
    publishEarthContext();
    if (earthContextVisible) {
      dockBackdropLastImage = '';
      requestDockBackdrop([900]);
    } else {
      cancelDockBackdrop();
    }
  };
  updateCameraUi();
})();

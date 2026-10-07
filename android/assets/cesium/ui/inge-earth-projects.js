(() => {
  'use strict';
  const ui = window.InGeEarthUi;
  const db = window.InGeEarthStorage;
  const Cesium = window.Cesium;
  if (!ui || !db || !Cesium) return;
  const viewer = ui.viewer;
  const $ = ui.$;
  const projectSource = new Cesium.CustomDataSource('InGe Earth Project');
  viewer.dataSources.add(projectSource);
  const importSources = new Map();
  let activeProject = null;
  let saveTimer = 0;
  let pendingImportTarget = 'TEMPORARY';
  let importSession = null;
  let drawing = null;
  let measurement = null;
  let selectedFeatureId = null;
  let pendingExportKind = 'KML';

  const uuid = () => {
    try { if (crypto.randomUUID) return crypto.randomUUID(); } catch (ignored) {}
    return `inge-${Date.now().toString(36)}-${Math.random().toString(36).slice(2)}-${Math.random().toString(36).slice(2)}`;
  };
  const now = () => new Date().toISOString();
  const escapeHtml = (value) => String(value == null ? '' : value).replace(/[&<>'"]/g, (character) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', "'": '&#39;', '"': '&quot;' }[character]));
  const featureCount = (project) => (project.features || []).length + (project.measurements || []).length + (project.imports || []).length;
  const getLayer = (id) => activeProject && activeProject.layers.find((layer) => layer.id === id);
  const defaultLayerName = (type) => ({ POINT: 'Puntos', POLYLINE: 'Líneas', POLYGON: 'Polígonos', MEASUREMENT: 'Mediciones' }[type] || 'Importados');
  const getLayerFor = (type) => activeProject.layers.find((layer) => layer.kind === type) || activeProject.layers[0];
  const createLayer = (name, kind) => ({ id: uuid(), name, kind, visible: true, opacity: 1, order: 0, style: {}, createdAt: now(), updatedAt: now() });
  const createProjectModel = (name, description) => {
    const created = now();
    return {
      schemaVersion: 1, id: uuid(), name, description: description || '', createdAt: created, updatedAt: created,
      cameraView: null,
      layers: [createLayer('Puntos', 'POINT'), createLayer('Líneas', 'POLYLINE'), createLayer('Polígonos', 'POLYGON'), createLayer('Mediciones', 'MEASUREMENT'), createLayer('Importados', 'IMPORTED')],
      features: [], measurements: [], imports: []
    };
  };
  const pointLog = (event) => {
    try { if (window.InGeEarthTelemetry) window.InGeEarthTelemetry.post(`INGE_EARTH_POINT_${event}`); } catch (ignored) {}
  };
  const setChip = () => {};
  const setSaveState = () => {};
  const saveNow = async () => {
    if (!activeProject) return;
    activeProject.updatedAt = now();
    setSaveState('Guardando…');
    try {
      await db.putProject(activeProject);
      await db.setSetting('activeProjectId', activeProject.id);
      setSaveState('Guardado');
      ui.log(`PROJECT_SAVED id=${activeProject.id}`);
    } catch (error) {
      setSaveState('Error al guardar');
      ui.notify('No se pudo guardar el proyecto', 'error', 3600);
    }
  };
  const mutate = (refreshLayers = true) => {
    clearTimeout(saveTimer);
    setSaveState('Guardando…');
    saveTimer = setTimeout(() => { saveTimer = 0; saveNow(); }, 500);
    if (refreshLayers) renderLayers();
    setChip();
  };

  const color = (value, fallback) => {
    try { return Cesium.Color.fromCssColorString(value || fallback); } catch (ignored) { return Cesium.Color.fromCssColorString(fallback); }
  };
  const cartesian = (coordinate) => Cesium.Cartesian3.fromDegrees(coordinate[0], coordinate[1], coordinate[2] || 0);
  const addEntityForFeature = (feature) => {
    const layer = getLayer(feature.layerId);
    if (!layer) return;
    const style = { ...layer.style, ...(feature.style || {}) };
    const alpha = Number.isFinite(Number(layer.opacity)) ? Math.min(1, Math.max(0, Number(layer.opacity))) : 1;
    const common = { id: `feature-${feature.id}`, name: feature.properties.name || defaultLayerName(feature.type), description: feature.properties.description || '', show: layer.visible !== false };
    let entity;
    if (feature.type === 'POINT') {
      entity = projectSource.entities.add({ ...common, position: cartesian(feature.geometry.coordinates), point: ui.markerStyle(color(style.color, '#ffb84d').withAlpha(alpha), Number(style.size) || 12), label: {
        text: feature.properties.name || '', show: Boolean(feature.properties.name), font: '600 13px sans-serif', fillColor: Cesium.Color.WHITE,
        outlineColor: Cesium.Color.BLACK, outlineWidth: 3, style: Cesium.LabelStyle.FILL_AND_OUTLINE,
        pixelOffset: new Cesium.Cartesian2(0, -22), disableDepthTestDistance: Number.POSITIVE_INFINITY
      } });
    } else if (feature.type === 'POLYLINE') {
      entity = projectSource.entities.add({ ...common, polyline: { positions: feature.geometry.coordinates.map(cartesian), width: Number(style.width) || 4, material: color(style.color, '#75d6b0').withAlpha(alpha), clampToGround: false } });
    } else if (feature.type === 'POLYGON') {
      const positions = feature.geometry.coordinates.map(cartesian);
      entity = projectSource.entities.add({ ...common, polygon: { hierarchy: positions, material: color(style.color, '#75d6b0').withAlpha(.28 * alpha), outline: false }, polyline: { positions: positions.concat(positions[0]), width: Number(style.width) || 3, material: color(style.outlineColor || style.color, '#75d6b0').withAlpha(alpha) } });
    }
    if (entity) entity.ingeFeatureId = feature.id;
  };
  const addEntityForMeasurement = (item) => {
    const layer = getLayer(item.layerId);
    if (!layer) return;
    const positions = item.geometry.coordinates.map(cartesian);
    const entity = projectSource.entities.add({
      id: `measurement-${item.id}`, name: item.name,
      show: layer.visible !== false,
      polyline: { positions: item.kind === 'AREA' ? positions.concat(positions[0]) : positions, width: 4, material: color('#ffd166', '#ffd166') },
      polygon: item.kind === 'AREA' ? { hierarchy: positions, material: color('#ffd166', '#ffd166').withAlpha(.2) } : undefined
    });
    entity.ingeMeasurementId = item.id;
  };
  const upsertFeatureEntity = (feature) => {
    projectSource.entities.removeById(`feature-${feature.id}`);
    addEntityForFeature(feature);
    ui.requestRender();
  };
  const upsertMeasurementEntity = (item) => {
    projectSource.entities.removeById(`measurement-${item.id}`);
    addEntityForMeasurement(item);
    ui.requestRender();
  };
  const setLayerVisibility = (layer) => {
    activeProject.features.filter((item) => item.layerId === layer.id).forEach((item) => {
      const entity = projectSource.entities.getById(`feature-${item.id}`);
      if (entity) entity.show = layer.visible !== false;
    });
    activeProject.measurements.filter((item) => item.layerId === layer.id).forEach((item) => {
      const entity = projectSource.entities.getById(`measurement-${item.id}`);
      if (entity) entity.show = layer.visible !== false;
    });
    activeProject.imports.filter((item) => item.layerId === layer.id).forEach((item) => {
      const source = importSources.get(item.id);
      if (source) source.show = layer.visible !== false;
    });
    ui.requestRender();
  };
  const refreshLayerEntities = (layerId) => {
    activeProject.features.filter((item) => item.layerId === layerId).forEach(upsertFeatureEntity);
    activeProject.measurements.filter((item) => item.layerId === layerId).forEach(upsertMeasurementEntity);
  };
  const renderProject = () => {
    projectSource.entities.removeAll();
    if (!activeProject) { ui.requestRender(); return; }
    activeProject.features.forEach(addEntityForFeature);
    activeProject.measurements.forEach(addEntityForMeasurement);
    importSources.forEach((source, importId) => {
      const item = activeProject.imports.find((entry) => entry.id === importId);
      const layer = item && getLayer(item.layerId);
      source.show = Boolean(item && layer && layer.visible !== false);
    });
    ui.requestRender();
  };
  const renderLayers = () => {
    const container = $('projectLayers');
    if (!activeProject) { container.innerHTML = '<p class="empty-state">Abre un proyecto para administrar sus capas.</p>'; return; }
    container.innerHTML = activeProject.layers.map((layer) => {
      const count = activeProject.features.filter((item) => item.layerId === layer.id).length
        + activeProject.measurements.filter((item) => item.layerId === layer.id).length
        + activeProject.imports.filter((item) => item.layerId === layer.id).length;
      const referenceOnly = activeProject.imports.some((item) => item.layerId === layer.id && item.referenceOnly);
      return `<div class="layer-row" data-layer-id="${layer.id}"><div class="layer-main"><button data-layer-action="visibility" aria-label="Mostrar u ocultar">${layer.visible === false ? '○' : '●'}</button><span><strong>${escapeHtml(layer.name)}</strong><small>${count} elemento${count === 1 ? '' : 's'}${referenceOnly ? ' · Referencia KML' : ''}</small></span></div><div class="layer-actions"><button data-layer-action="zoom">Ver</button><button data-layer-action="rename">Renombrar</button>${referenceOnly ? '' : '<button data-layer-action="style">Estilo</button>'}<button class="danger" data-layer-action="delete">Eliminar</button></div></div>`;
    }).join('');
  };

  const dialog = (options) => new Promise((resolve) => {
    const scrim = $('modalScrim');
    const form = $('earthDialog');
    $('dialogTitle').textContent = options.title;
    $('dialogMessage').hidden = !options.message;
    $('dialogMessage').textContent = options.message || '';
    $('dialogAccept').textContent = options.accept || 'Aceptar';
    $('dialogAccept').classList.toggle('danger', Boolean(options.danger));
    $('dialogFields').innerHTML = (options.fields || []).map((field) => {
      const value = escapeHtml(field.value || '');
      if (field.type === 'textarea') return `<label>${escapeHtml(field.label)}<textarea name="${field.name}" maxlength="${field.maxlength || 500}">${value}</textarea></label>`;
      if (field.type === 'color') return `<label>${escapeHtml(field.label)}<input name="${field.name}" type="color" value="${value || '#75d6b0'}"></label>`;
      return `<label>${escapeHtml(field.label)}<input name="${field.name}" type="${field.type || 'text'}" value="${value}" maxlength="${field.maxlength || 80}" ${field.required ? 'required' : ''}></label>`;
    }).join('');
    ui.setVisualOverlay('MODAL');
    scrim.hidden = false;
    void form.offsetWidth;
    form.classList.add('open');
    const close = (result) => {
      form.classList.remove('open');
      scrim.hidden = true;
      ui.setVisualOverlay('NONE');
      form.removeEventListener('submit', submit);
      $('dialogCancel').removeEventListener('click', cancel);
      resolve(result);
    };
    const cancel = () => close(null);
    const submit = (event) => {
      event.preventDefault();
      if (!form.reportValidity()) return;
      const values = {};
      new FormData(form).forEach((value, key) => { values[key] = String(value).trim(); });
      close(values);
    };
    form.addEventListener('submit', submit);
    $('dialogCancel').addEventListener('click', cancel);
    const first = form.querySelector('input,textarea');
    if (first) setTimeout(() => first.focus(), 50);
  });

  const createProject = async () => {
    const values = await dialog({ title: 'Nuevo proyecto', fields: [
      { name: 'name', label: 'Nombre', required: true, maxlength: 80 },
      { name: 'description', label: 'Descripción (opcional)', type: 'textarea', maxlength: 500 }
    ], accept: 'Crear' });
    if (!values || !values.name) return;
    const project = createProjectModel(values.name, values.description);
    await db.putProject(project);
    await openProject(project.id);
    ui.log(`PROJECT_CREATED id=${project.id}`);
    ui.notify('Proyecto creado', 'success');
  };
  const clearImports = async () => {
    for (const source of importSources.values()) viewer.dataSources.remove(source, true);
    importSources.clear();
  };
  const openProject = async (id, revealWorkspace = true) => {
    if (saveTimer && activeProject) {
      clearTimeout(saveTimer);
      saveTimer = 0;
      await saveNow();
    }
    await clearImports();
    activeProject = await db.getProject(id);
    if (!activeProject) return;
    await db.setSetting('activeProjectId', id);
    setChip();
    renderLayers();
    renderProject();
    await restoreImports();
    ui.log(`PROJECT_OPENED id=${id}`);
    ui.notify(`Proyecto ${activeProject.name}`, 'success');
    if (revealWorkspace) showActiveProject();
  };
  const closeProject = async () => {
    clearTimeout(saveTimer);
    saveTimer = 0;
    await saveNow();
    await clearImports();
    activeProject = null;
    await db.setSetting('activeProjectId', null);
    setChip();
    renderLayers();
    renderProject();
    $('workspaceSheet').hidden = true;
    ui.notify('Modo Explorar', 'success');
  };
  const renameProject = async (project) => {
    const values = await dialog({ title: 'Renombrar proyecto', fields: [{ name: 'name', label: 'Nombre', required: true, maxlength: 80, value: project.name }], accept: 'Guardar' });
    if (!values) return;
    project.name = values.name;
    project.updatedAt = now();
    await db.putProject(project);
    if (activeProject && project.id === activeProject.id) { activeProject.name = values.name; setChip(); }
  };
  const duplicateProject = async (project) => {
    const copy = JSON.parse(JSON.stringify(project));
    const layerIds = new Map();
    copy.id = uuid();
    copy.name = `Copia de ${project.name}`.slice(0, 80);
    copy.createdAt = copy.updatedAt = now();
    copy.layers.forEach((layer) => { const old = layer.id; layer.id = uuid(); layerIds.set(old, layer.id); });
    copy.features.forEach((item) => { item.id = uuid(); item.layerId = layerIds.get(item.layerId); });
    copy.measurements.forEach((item) => { item.id = uuid(); item.layerId = layerIds.get(item.layerId); });
    const newImports = [];
    for (const item of copy.imports) {
      const source = await db.getBlob(item.blobId);
      const blobId = uuid();
      if (source) await db.putBlob(blobId, source.blob, source.metadata);
      item.id = uuid(); item.blobId = blobId; item.layerId = layerIds.get(item.layerId);
      newImports.push(item);
    }
    copy.imports = newImports;
    await db.putProject(copy);
    ui.notify('Proyecto duplicado', 'success');
    showProjects();
  };
  const deleteProject = async (project) => {
    const accepted = await dialog({ title: 'Eliminar proyecto', message: `Se eliminará “${project.name}” y sus datos locales.`, accept: 'Eliminar', danger: true });
    if (!accepted) return;
    if (activeProject && activeProject.id === project.id) { await clearImports(); activeProject = null; }
    await db.deleteProject(project);
    setChip(); renderProject(); renderLayers();
    ui.log(`PROJECT_DELETED id=${project.id}`);
    ui.notify('Proyecto eliminado', 'success');
    showProjects();
  };

  const showWorkspace = (title, subtitle, html) => {
    if (window.InGeEarthMapDetails
        && window.InGeEarthMapDetails.state.routeToolState !== 'OFF')
      window.InGeEarthMapDetails.closeRoute();
    ui.closeTransientPanels('workspace');
    $('workspaceTitle').textContent = title;
    $('workspaceSubtitle').textContent = subtitle;
    $('workspaceContent').innerHTML = html;
    $('workspaceSheet').hidden = false;
    ui.setVisualOverlay('BOTTOM_SHEET');
  };
  const showProjects = async () => {
    const projects = await db.listProjects();
    const cards = projects.length ? projects.map((project) => `<article class="project-card" data-project-id="${project.id}"><header><div><strong>${escapeHtml(project.name)}</strong><small>${new Date(project.updatedAt).toLocaleString('es-PE')} · ${featureCount(project)} elementos</small></div></header><div class="card-actions"><button data-project-action="open">Abrir</button><button data-project-action="rename">Renombrar</button><button data-project-action="duplicate">Duplicar</button><button class="danger" data-project-action="delete">Eliminar</button></div></article>`).join('') : '<p class="empty-state">Todavía no hay proyectos locales.</p>';
    showWorkspace('Proyectos', 'Guardados en este dispositivo', `<div class="workspace-toolbar"><button class="workspace-button primary" data-workspace-action="new-project">＋ Nuevo proyecto</button><button class="workspace-button" data-workspace-action="open-kml">Abrir KML/KMZ temporal</button></div>${cards}`);
  };
  const showActiveProject = () => {
    if (!activeProject) { showProjects(); return; }
    const featureRows = activeProject.features.map((item) => `<div class="feature-row" data-feature-id="${item.id}"><div><strong>${escapeHtml(item.properties.name || defaultLayerName(item.type))}</strong><small>${item.type}</small></div><div class="card-actions"><button data-feature-action="zoom">Ver</button><button data-feature-action="edit">Editar</button><button data-feature-action="geometry">Geometría</button><button class="danger" data-feature-action="delete">Eliminar</button></div></div>`).join('');
    showWorkspace(activeProject.name, `${featureCount(activeProject)} elementos · almacenamiento local`, `<div class="workspace-toolbar"><button class="workspace-button primary" data-workspace-action="import-project">Importar KML/KMZ</button><button class="workspace-button" data-workspace-action="zoom-project">Ver proyecto completo</button><button class="workspace-button" data-workspace-action="save-view">Guardar vista actual</button>${activeProject.cameraView ? '<button class="workspace-button" data-workspace-action="go-view">Ir a vista guardada</button>' : ''}<button class="workspace-button" data-workspace-action="export-kml">Exportar KML</button><button class="workspace-button" data-workspace-action="export-kmz">Exportar KMZ</button><button class="workspace-button" data-workspace-action="rename-active">Renombrar</button><button class="workspace-button" data-workspace-action="close-project">Cerrar proyecto</button></div><h3>Elementos</h3>${featureRows || '<p class="empty-state">Usa Crear para agregar puntos, líneas y polígonos.</p>'}`);
  };

  const coordinatesFromPositions = (positions) => positions.map((position) => {
    const value = ui.toCoordinates(position);
    return [value.longitude, value.latitude, value.height || 0];
  });
  const removePreview = (state) => {
    if (!state) return;
    (state.preview || []).forEach((entity) => viewer.entities.remove(entity));
    state.preview = [];
    ui.requestRender();
  };
  const updateDrawingPreview = () => {
    removePreview(drawing);
    if (!drawing || !drawing.positions.length) return;
    drawing.preview = drawing.positions.map((position) => viewer.entities.add({ position, point: ui.markerStyle(color('#75d6b0', '#75d6b0'), 9) }));
    if (drawing.type === 'POLYLINE' && drawing.positions.length > 1)
      drawing.preview.push(viewer.entities.add({ polyline: { positions: drawing.positions.slice(), width: 4, material: color('#75d6b0', '#75d6b0') } }));
    if (drawing.type === 'POLYGON' && drawing.positions.length > 2) {
      drawing.preview.push(viewer.entities.add({ polygon: { hierarchy: drawing.positions.slice(), material: color('#75d6b0', '#75d6b0').withAlpha(.25), outline: false } }));
      drawing.preview.push(viewer.entities.add({ polyline: { positions: drawing.positions.concat(drawing.positions[0]), width: 3, material: color('#75d6b0', '#75d6b0') } }));
    }
    ui.requestRender();
  };
  const endInteraction = () => {
    const leavingPoint = Boolean(drawing && drawing.type === 'POINT');
    removePreview(drawing); removePreview(measurement);
    drawing = null; measurement = null;
    $('interactionBar').hidden = true;
    $('interactionGps').hidden = true;
    $('measurePanel').hidden = true;
    ui.clearInteraction();
    if (leavingPoint) pointLog('MODE_EXIT');
  };
  const requireProject = () => {
    if (activeProject) return true;
    ui.notify('Crea o abre un proyecto primero', 'info', 3200);
    showProjects();
    return false;
  };
  const startDrawing = (type, existing) => {
    if (!requireProject()) return;
    endInteraction();
    drawing = { type, positions: [], preview: [], existing: existing || null };
    $('interactionTitle').textContent = existing ? 'Redibujar geometría' : `Crear ${defaultLayerName(type).toLowerCase()}`;
    $('interactionHint').textContent = type === 'POINT' ? 'Toca la nueva ubicación' : 'Toca el mapa para agregar vértices';
    $('interactionUndo').hidden = type === 'POINT';
    $('interactionFinish').hidden = type === 'POINT';
    $('interactionGps').hidden = type !== 'POINT';
    $('interactionBar').hidden = false;
    if (type === 'POINT') pointLog('MODE_ENTER');
    ui.setInteraction(`DRAW_${type}`, (position) => {
      if (!drawing || drawing.dialogOpen) return false;
      drawing.positions.push(Cesium.Cartesian3.clone(position));
      updateDrawingPreview();
      if (type === 'POINT') {
        pointLog('PICK');
        drawing.dialogOpen = true;
        ui.pauseInteraction();
        finishDrawing();
      }
      return true;
    }, () => removePreview(drawing));
  };
  const finishDrawing = async () => {
    if (!drawing) return;
    const minimum = drawing.type === 'POINT' ? 1 : drawing.type === 'POLYLINE' ? 2 : 3;
    if (drawing.positions.length < minimum) { ui.notify(`Se necesitan al menos ${minimum} puntos`, 'error'); return; }
    const state = drawing;
    const existing = state.existing;
    if (state.type === 'POINT') pointLog('DIALOG');
    const values = existing ? { name: existing.properties.name, description: existing.properties.description } : await dialog({ title: `Guardar ${defaultLayerName(state.type).toLowerCase()}`, fields: [
      { name: 'name', label: 'Nombre', required: true, maxlength: 80, value: `${defaultLayerName(state.type)} ${activeProject.features.filter((item) => item.type === state.type).length + 1}` },
      { name: 'description', label: 'Descripción (opcional)', type: 'textarea', maxlength: 500 }
    ], accept: 'Guardar' });
    if (!values) {
      if (state.type === 'POINT') pointLog('CANCEL');
      endInteraction();
      return;
    }
    const geometry = { type: state.type === 'POINT' ? 'Point' : state.type === 'POLYLINE' ? 'LineString' : 'Polygon', coordinates: state.type === 'POINT' ? coordinatesFromPositions(state.positions)[0] : coordinatesFromPositions(state.positions) };
    let feature = existing;
    if (existing) { existing.geometry = geometry; existing.updatedAt = now(); }
    else {
      feature = { id: uuid(), layerId: getLayerFor(state.type).id, type: state.type, geometry, properties: { name: values.name, description: values.description || '' }, style: {}, createdAt: now(), updatedAt: now() };
      if (state.type === 'POINT') {
        if (Number.isFinite(state.accuracy)) feature.accuracyMeters = state.accuracy;
        if (state.coordinateTimestamp) feature.coordinateTimestamp = state.coordinateTimestamp;
        if (state.coordinateSource) feature.coordinateSource = state.coordinateSource;
      }
      activeProject.features.push(feature);
    }
    upsertFeatureEntity(feature);
    if (state.type === 'POINT') pointLog('SAVE');
    endInteraction(); mutate();
    if (state.type === 'POINT') {
      selectedFeatureId = feature.id;
      ui.showCoordinateSheet(feature.properties.name || 'Punto', getLayer(feature.layerId).name, {
        longitude: Number(feature.geometry.coordinates[0]),
        latitude: Number(feature.geometry.coordinates[1]),
        height: Number(feature.geometry.coordinates[2]) || 0,
        accuracy: Number(feature.accuracyMeters),
        timestamp: feature.coordinateTimestamp,
        source: feature.coordinateSource || 'InGe Earth'
      });
    }
    ui.log(`DRAW_${state.type === 'POLYLINE' ? 'LINE' : state.type}_COMPLETE`);
    ui.notify('Elemento guardado', 'success');
  };
  const pointFromGps = async () => {
    if (!drawing || drawing.type !== 'POINT') startDrawing('POINT');
    if (!drawing || drawing.type !== 'POINT' || drawing.dialogOpen) return;
    const fix = ui.getBestLocation();
    if (!fix) { ui.requestLocation(); ui.notify('Obtén una ubicación precisa y vuelve a elegir esta acción', 'info', 3800); return; }
    drawing.positions = [Cesium.Cartesian3.fromDegrees(fix.longitude, fix.latitude, fix.height || 0)];
    drawing.accuracy = Number(fix.accuracy);
    drawing.coordinateTimestamp = fix.timestamp
      || (Number(fix.timestampMs) > 0 ? new Date(Number(fix.timestampMs)).toISOString() : new Date().toISOString());
    drawing.coordinateSource = fix.source || (fix.provider ? `InGe Earth GPS (${fix.provider})` : 'InGe Earth GPS');
    updateDrawingPreview();
    pointLog('PICK source=gps');
    drawing.dialogOpen = true;
    ui.pauseInteraction();
    await finishDrawing();
  };

  const segmentDistance = (first, second) => {
    const a = Cesium.Cartographic.fromCartesian(first);
    const b = Cesium.Cartographic.fromCartesian(second);
    const geodesic = new Cesium.EllipsoidGeodesic(a, b);
    return Math.hypot(geodesic.surfaceDistance || 0, (b.height || 0) - (a.height || 0));
  };
  const distanceFor = (positions, closed) => {
    let total = 0;
    for (let index = 1; index < positions.length; index += 1) total += segmentDistance(positions[index - 1], positions[index]);
    if (closed && positions.length > 2) total += segmentDistance(positions[positions.length - 1], positions[0]);
    return total;
  };
  const areaFor = (positions) => {
    if (positions.length < 3) return 0;
    const plane = new Cesium.EllipsoidTangentPlane(positions[0], Cesium.Ellipsoid.WGS84);
    const points = plane.projectPointsOntoPlane(positions);
    let area = 0;
    for (let i = 0, j = points.length - 1; i < points.length; j = i++) area += points[j].x * points[i].y - points[i].x * points[j].y;
    return Math.abs(area / 2);
  };
  const updateMeasurement = () => {
    removePreview(measurement);
    const positions = measurement.positions;
    measurement.preview = positions.map((position) => viewer.entities.add({ position, point: ui.markerStyle(color('#ffd166', '#ffd166'), 9) }));
    if (positions.length > 1) measurement.preview.push(viewer.entities.add({ polyline: { positions: measurement.kind === 'AREA' && positions.length > 2 ? positions.concat(positions[0]) : positions.slice(), width: 4, material: color('#ffd166', '#ffd166') } }));
    if (measurement.kind === 'AREA' && positions.length > 2) measurement.preview.push(viewer.entities.add({ polygon: { hierarchy: positions.slice(), material: color('#ffd166', '#ffd166').withAlpha(.18) } }));
    measurement.distance = distanceFor(positions, measurement.kind === 'AREA');
    measurement.area = measurement.kind === 'AREA' ? areaFor(positions) : 0;
    $('measureDistance').textContent = measurement.kind === 'AREA' ? ui.formatArea(measurement.area) : ui.formatDistance(measurement.distance);
    $('measureHint').textContent = measurement.kind === 'AREA' && positions.length > 2 ? `Perímetro ${ui.formatDistance(measurement.distance)}` : `${positions.length} puntos`;
    $('saveMeasure').hidden = positions.length < (measurement.kind === 'AREA' ? 3 : 2) || !activeProject;
    ui.requestRender();
  };
  const startMeasurement = (kind) => {
    endInteraction();
    measurement = { kind, positions: [], preview: [], distance: 0, area: 0 };
    $('measureKind').textContent = kind === 'AREA' ? 'Área' : 'Distancia';
    $('measureDistance').textContent = kind === 'AREA' ? '0 m²' : '0 m';
    $('measureHint').textContent = 'Toca puntos para medir';
    $('measureModeToggle').textContent = 'Distancia';
    $('measureModeToggle').hidden = kind !== 'AREA';
    $('saveMeasure').hidden = true;
    $('measurePanel').hidden = false;
    ui.setInteraction(kind === 'AREA' ? 'MEASURE_AREA' : 'MEASURE_DISTANCE', (position) => { measurement.positions.push(Cesium.Cartesian3.clone(position)); updateMeasurement(); return true; }, () => removePreview(measurement));
    ui.notify(kind === 'AREA' ? 'Toca al menos 3 vértices' : 'Toca puntos para medir');
  };
  const finishMeasurement = () => {
    if (!measurement) return;
    const minimum = measurement.kind === 'AREA' ? 3 : 2;
    if (measurement.positions.length < minimum) { ui.notify(`Se necesitan al menos ${minimum} puntos`, 'error'); return; }
    ui.showSummary('Medición completada', measurement.kind === 'AREA' ? `${ui.formatArea(measurement.area)} · perímetro ${ui.formatDistance(measurement.distance)}` : `${measurement.positions.length} puntos · ${ui.formatDistance(measurement.distance)}`);
    $('measurePanel').hidden = true;
    ui.setInteraction('EXPLORE', null, null);
    measurement.preview = [];
  };
  const saveMeasurement = async () => {
    if (!measurement || !requireProject()) return;
    const values = await dialog({ title: 'Guardar medición', fields: [{ name: 'name', label: 'Nombre', required: true, maxlength: 80, value: measurement.kind === 'AREA' ? 'Área medida' : 'Distancia medida' }], accept: 'Guardar' });
    if (!values) return;
    const item = { id: uuid(), layerId: getLayerFor('MEASUREMENT').id, kind: measurement.kind, name: values.name, geometry: { coordinates: coordinatesFromPositions(measurement.positions) }, distanceMeters: measurement.distance, areaMeters: measurement.area, createdAt: now(), updatedAt: now() };
    activeProject.measurements.push(item);
    upsertMeasurementEntity(item);
    ui.log('MEASURE_COMPLETE');
    endInteraction(); mutate(); ui.notify('Medición guardada', 'success');
  };

  const allPositions = (filterLayer) => {
    const result = [];
    if (!activeProject) return result;
    activeProject.features.filter((item) => !filterLayer || item.layerId === filterLayer).forEach((item) => {
      const coordinates = item.type === 'POINT' ? [item.geometry.coordinates] : item.geometry.coordinates;
      coordinates.forEach((value) => result.push(cartesian(value)));
    });
    activeProject.measurements.filter((item) => !filterLayer || item.layerId === filterLayer).forEach((item) => item.geometry.coordinates.forEach((value) => result.push(cartesian(value))));
    const time = viewer.clock.currentTime;
    activeProject.imports.filter((item) => !filterLayer || item.layerId === filterLayer).forEach((item) => {
      const source = importSources.get(item.id);
      if (!source) return;
      source.entities.values.forEach((entity) => {
        try {
          if (entity.position) {
            const position = entity.position.getValue(time);
            if (position) result.push(position);
          } else if (entity.polyline && entity.polyline.positions) {
            result.push(...(entity.polyline.positions.getValue(time) || []));
          } else if (entity.polygon && entity.polygon.hierarchy) {
            const hierarchy = entity.polygon.hierarchy.getValue(time);
            if (hierarchy && hierarchy.positions) result.push(...hierarchy.positions);
          }
        } catch (ignored) {}
      });
    });
    return result;
  };
  const zoomPositions = (positions) => {
    if (!positions.length) { ui.notify('La selección no tiene geometría visible', 'info'); return; }
    viewer.camera.flyToBoundingSphere(Cesium.BoundingSphere.fromPoints(positions), { duration: 1.25, offset: new Cesium.HeadingPitchRange(0, Cesium.Math.toRadians(-45), 0) });
  };
  const zoomProject = () => {
    const positions = allPositions();
    if (positions.length) zoomPositions(positions);
    else if (importSources.size) viewer.flyTo(Array.from(importSources.values())[0]);
    else ui.notify('El proyecto todavía no tiene elementos', 'info');
  };
  const zoomLayer = (layerId) => {
    const positions = allPositions(layerId);
    if (positions.length) zoomPositions(positions);
    else {
      const item = activeProject.imports.find((entry) => entry.layerId === layerId);
      const source = item && importSources.get(item.id);
      if (source) viewer.flyTo(source); else ui.notify('La capa está vacía', 'info');
    }
  };

  const extractEntity = (entity, time, layerId) => {
    const properties = { name: entity.name || '', description: entity.description ? String(entity.description.getValue(time) || '') : '' };
    const style = {};
    const readColor = (material) => {
      try {
        const value = material && material.color && material.color.getValue(time);
        return value ? value.toCssColorString() : null;
      } catch (ignored) { return null; }
    };
    if (entity.position) {
      const value = entity.position.getValue(time);
      const coordinate = ui.toCoordinates(value);
      try {
        const pointColor = entity.point && entity.point.color && entity.point.color.getValue(time);
        if (pointColor) style.color = pointColor.toCssColorString();
        const size = entity.point && entity.point.pixelSize && entity.point.pixelSize.getValue(time);
        if (Number.isFinite(size)) style.size = size;
      } catch (ignored) {}
      return coordinate ? { id: uuid(), layerId, type: 'POINT', geometry: { type: 'Point', coordinates: [coordinate.longitude, coordinate.latitude, coordinate.height || 0] }, properties, style, createdAt: now(), updatedAt: now() } : null;
    }
    if (entity.polyline && entity.polyline.positions) {
      const positions = entity.polyline.positions.getValue(time) || [];
      const lineColor = readColor(entity.polyline.material);
      if (lineColor) style.color = lineColor;
      try { const width = entity.polyline.width.getValue(time); if (Number.isFinite(width)) style.width = width; } catch (ignored) {}
      return positions.length >= 2 ? { id: uuid(), layerId, type: 'POLYLINE', geometry: { type: 'LineString', coordinates: coordinatesFromPositions(positions) }, properties, style, createdAt: now(), updatedAt: now() } : null;
    }
    if (entity.polygon && entity.polygon.hierarchy) {
      const hierarchy = entity.polygon.hierarchy.getValue(time);
      const polygonColor = readColor(entity.polygon.material);
      if (polygonColor) style.color = polygonColor;
      return hierarchy && hierarchy.positions && hierarchy.positions.length >= 3 ? { id: uuid(), layerId, type: 'POLYGON', geometry: { type: 'Polygon', coordinates: coordinatesFromPositions(hierarchy.positions) }, properties, style, createdAt: now(), updatedAt: now() } : null;
    }
    return null;
  };
  const loadKmlBlob = (blob, name) => Cesium.KmlDataSource.load(new File([blob], name, { type: blob.type }), { camera: viewer.scene.camera, canvas: viewer.scene.canvas, clampToGround: false });
  const processImport = async (blob, name, target) => {
    const lower = name.toLowerCase();
    if (!lower.endsWith('.kml') && !lower.endsWith('.kmz')) throw new Error('Selecciona un archivo .kml o .kmz');
    const source = await loadKmlBlob(blob, name);
    await viewer.dataSources.add(source);
    await viewer.flyTo(source);
    if (target !== 'PROJECT') {
      ui.log(lower.endsWith('.kmz') ? 'KMZ_OPENED' : 'KML_OPENED');
      ui.notify(`${name} abierto temporalmente`, 'success');
      return;
    }
    if (!requireProject()) { viewer.dataSources.remove(source, true); return; }
    const layer = createLayer(name.replace(/\.(kml|kmz)$/i, ''), 'IMPORTED');
    activeProject.layers.push(layer);
    const normalized = [];
    let unsupported = false;
    source.entities.values.forEach((entity) => {
      const item = extractEntity(entity, viewer.clock.currentTime, layer.id);
      if (item) normalized.push(item); else unsupported = true;
    });
    const blobId = uuid();
    const importId = uuid();
    await db.putBlob(blobId, blob, { originalFilename: name, mime: blob.type, size: blob.size });
    activeProject.imports.push({ id: importId, layerId: layer.id, blobId, originalFilename: name, mime: blob.type || (lower.endsWith('.kmz') ? 'application/vnd.google-earth.kmz' : 'application/vnd.google-earth.kml+xml'), size: blob.size, importedAt: now(), referenceOnly: unsupported });
    if (unsupported) importSources.set(importId, source);
    else { viewer.dataSources.remove(source, true); activeProject.features.push(...normalized); }
    renderProject(); mutate();
    ui.log(lower.endsWith('.kmz') ? 'KMZ_IMPORTED' : 'KML_IMPORTED');
    ui.notify(unsupported ? 'Importado como referencia KML de solo lectura' : 'Archivo agregado al proyecto', 'success', 3600);
  };
  const restoreImports = async () => {
    if (!activeProject) return;
    for (const item of activeProject.imports.filter((entry) => entry.referenceOnly)) {
      try {
        const stored = await db.getBlob(item.blobId);
        if (!stored) continue;
        const source = await loadKmlBlob(stored.blob, item.originalFilename);
        await viewer.dataSources.add(source);
        importSources.set(item.id, source);
      } catch (error) { ui.notify(`No se pudo restaurar ${item.originalFilename}`, 'error'); }
    }
    renderProject();
  };
  const requestImport = (target) => {
    pendingImportTarget = target;
    try {
      if (window.InGeEarthUiBridge && typeof window.InGeEarthUiBridge.openEarthDocument === 'function') { window.InGeEarthUiBridge.openEarthDocument(); return; }
    } catch (ignored) {}
    const input = document.createElement('input');
    input.type = 'file'; input.accept = '.kml,.kmz,application/vnd.google-earth.kml+xml,application/vnd.google-earth.kmz';
    input.addEventListener('change', () => { if (input.files && input.files[0]) processImport(input.files[0], input.files[0].name, target).catch((error) => ui.notify(error.message || 'No se pudo abrir el archivo', 'error')); });
    input.click();
  };
  const receiveImportStart = (metadata) => { importSession = { metadata, chunks: [] }; };
  const receiveImportChunk = (chunk) => { if (importSession) importSession.chunks.push(chunk); };
  const receiveImportComplete = async () => {
    if (!importSession) return;
    try {
      const binaryParts = importSession.chunks.map((chunk) => {
        const binary = atob(chunk); const bytes = new Uint8Array(binary.length);
        for (let index = 0; index < binary.length; index += 1) bytes[index] = binary.charCodeAt(index);
        return bytes;
      });
      const metadata = importSession.metadata;
      await processImport(new Blob(binaryParts, { type: metadata.mime }), metadata.name, pendingImportTarget);
    } catch (error) { ui.notify(error.message || 'No se pudo importar el archivo', 'error', 4000); }
    finally { importSession = null; }
  };
  const receiveImportError = (message) => { importSession = null; ui.notify(message || 'No se pudo leer el archivo', 'error'); };

  const sanitizeFilename = (name) => String(name || 'Proyecto').replace(/[\\/:*?"<>|]/g, '_').replace(/\s+/g, '_').slice(0, 90);
  const sendBlobToAndroid = async (blob, filename, mime) => {
    const bridge = window.InGeEarthUiBridge;
    if (!bridge || typeof bridge.beginEarthExport !== 'function') {
      const link = document.createElement('a'); link.href = URL.createObjectURL(blob); link.download = filename; link.click(); setTimeout(() => URL.revokeObjectURL(link.href), 30000); return;
    }
    const chunkSize = 192 * 1024;
    const count = Math.ceil(blob.size / chunkSize);
    bridge.beginEarthExport(filename, mime, count);
    for (let index = 0; index < count; index += 1) {
      const buffer = await blob.slice(index * chunkSize, Math.min(blob.size, (index + 1) * chunkSize)).arrayBuffer();
      const bytes = new Uint8Array(buffer);
      let binary = '';
      for (let offset = 0; offset < bytes.length; offset += 0x8000) binary += String.fromCharCode(...bytes.subarray(offset, Math.min(bytes.length, offset + 0x8000)));
      bridge.appendEarthExportChunk(btoa(binary));
    }
    bridge.finishEarthExport();
  };
  const exportProject = async (kmz) => {
    if (!requireProject()) return;
    pendingExportKind = kmz ? 'KMZ' : 'KML';
    ui.log(`EXPORT_${kmz ? 'KMZ' : 'KML'}_REQUESTED`);
    try {
      const exportSource = new Cesium.CustomDataSource('Export');
      activeProject.features.forEach((feature) => {
        const layer = getLayer(feature.layerId);
        const style = { ...((layer && layer.style) || {}), ...(feature.style || {}) };
        const common = { name: feature.properties.name || defaultLayerName(feature.type), description: feature.properties.description || '' };
        if (feature.type === 'POINT') exportSource.entities.add({ ...common, position: cartesian(feature.geometry.coordinates), point: ui.markerStyle(color(style.color, '#ffb84d'), Number(style.size) || 12) });
        else if (feature.type === 'POLYLINE') exportSource.entities.add({ ...common, polyline: { positions: feature.geometry.coordinates.map(cartesian), width: Number(style.width) || 4, material: color(style.color, '#75d6b0') } });
        else if (feature.type === 'POLYGON') {
          const positions = feature.geometry.coordinates.map(cartesian);
          exportSource.entities.add({ ...common, polygon: { hierarchy: positions, material: color(style.color, '#75d6b0').withAlpha(.28), outline: false } });
        }
      });
      activeProject.measurements.forEach((item) => {
        const coordinates = item.geometry.coordinates.map(cartesian);
        exportSource.entities.add({ name: item.name, polyline: { positions: item.kind === 'AREA' ? coordinates.concat(coordinates[0]) : coordinates, width: 3, material: color('#ffd166', '#ffd166') }, polygon: item.kind === 'AREA' ? { hierarchy: coordinates, material: color('#ffd166', '#ffd166').withAlpha(.2) } : undefined });
      });
      const result = await Cesium.exportKml({ entities: exportSource.entities, kmz });
      let blob;
      if (result instanceof Blob) blob = result;
      else if (result && result.kmz instanceof Blob) blob = result.kmz;
      else blob = new Blob([result && result.kml ? result.kml : String(result || '')], { type: 'application/vnd.google-earth.kml+xml' });
      const extension = kmz ? 'kmz' : 'kml';
      await sendBlobToAndroid(blob, `${sanitizeFilename(activeProject.name)}.${extension}`, kmz ? 'application/vnd.google-earth.kmz' : 'application/vnd.google-earth.kml+xml');
    } catch (error) { ui.notify(`No se pudo exportar: ${error.message || 'error'}`, 'error', 4200); }
  };
  const receiveExportResult = (success, message) => {
    if (success) { ui.log(`EXPORT_${pendingExportKind}_COMPLETE`); ui.notify('Proyecto exportado', 'success'); }
    else ui.notify(message || 'No se pudo guardar la exportación', 'error');
  };

  const handlePickedFeature = (picked) => {
    const entity = picked && picked.id;
    if (!entity || (!entity.ingeFeatureId && !entity.ingeMeasurementId)) return false;
    if (entity.ingeFeatureId) {
      selectedFeatureId = entity.ingeFeatureId;
      const feature = activeProject && activeProject.features.find((item) => item.id === selectedFeatureId);
      if (feature && feature.type === 'POINT') {
        const coordinates = feature.geometry.coordinates;
        ui.showCoordinateSheet(feature.properties.name || 'Punto', getLayer(feature.layerId).name, {
          longitude: Number(coordinates[0]), latitude: Number(coordinates[1]), height: Number(coordinates[2]) || 0,
          accuracy: Number(feature.accuracyMeters), timestamp: feature.coordinateTimestamp,
          source: feature.coordinateSource || 'InGe Earth'
        });
        return true;
      }
      if (feature) { ui.showSummary(feature.properties.name || defaultLayerName(feature.type), `${feature.type} · ${getLayer(feature.layerId).name}`); return true; }
    }
    if (entity.ingeMeasurementId) {
      const item = activeProject.measurements.find((value) => value.id === entity.ingeMeasurementId);
      if (item) { ui.showSummary(item.name, item.kind === 'AREA' ? `${ui.formatArea(item.areaMeters)} · perímetro ${ui.formatDistance(item.distanceMeters)}` : ui.formatDistance(item.distanceMeters)); return true; }
    }
    return false;
  };

  $('workspaceSheet').querySelector('[data-close="workspace"]').addEventListener('click', () => { $('workspaceSheet').hidden = true; ui.setVisualOverlay('NONE'); });
  $('workspaceContent').addEventListener('click', async (event) => {
    const workspaceAction = event.target.closest('[data-workspace-action]');
    if (workspaceAction) {
      const action = workspaceAction.dataset.workspaceAction;
      if (action === 'new-project') createProject();
      else if (action === 'open-kml') requestImport('TEMPORARY');
      else if (action === 'import-project') requestImport('PROJECT');
      else if (action === 'zoom-project') zoomProject();
      else if (action === 'save-view') {
        activeProject.cameraView = { position: [viewer.camera.positionWC.x, viewer.camera.positionWC.y, viewer.camera.positionWC.z], heading: viewer.camera.heading, pitch: viewer.camera.pitch, roll: viewer.camera.roll };
        mutate(); ui.notify('Vista guardada', 'success'); showActiveProject();
      } else if (action === 'go-view' && activeProject.cameraView) {
        const view = activeProject.cameraView; viewer.camera.flyTo({ destination: new Cesium.Cartesian3(...view.position), orientation: { heading: view.heading, pitch: view.pitch, roll: view.roll }, duration: 1.2 });
      } else if (action === 'export-kml') exportProject(false);
      else if (action === 'export-kmz') exportProject(true);
      else if (action === 'rename-active') { await renameProject(activeProject); showActiveProject(); }
      else if (action === 'close-project') closeProject();
      return;
    }
    const projectCard = event.target.closest('[data-project-id]');
    const projectAction = event.target.closest('[data-project-action]');
    if (projectCard && projectAction) {
      const project = await db.getProject(projectCard.dataset.projectId);
      if (projectAction.dataset.projectAction === 'open') openProject(project.id);
      else if (projectAction.dataset.projectAction === 'rename') { await renameProject(project); showProjects(); }
      else if (projectAction.dataset.projectAction === 'duplicate') duplicateProject(project);
      else if (projectAction.dataset.projectAction === 'delete') deleteProject(project);
      return;
    }
    const row = event.target.closest('[data-feature-id]');
    const featureAction = event.target.closest('[data-feature-action]');
    if (!row || !featureAction || !activeProject) return;
    const feature = activeProject.features.find((item) => item.id === row.dataset.featureId);
    if (!feature) return;
    const action = featureAction.dataset.featureAction;
    if (action === 'zoom') zoomPositions(feature.type === 'POINT' ? [cartesian(feature.geometry.coordinates)] : feature.geometry.coordinates.map(cartesian));
    else if (action === 'edit') {
      const values = await dialog({ title: 'Editar elemento', fields: [{ name: 'name', label: 'Nombre', required: true, maxlength: 80, value: feature.properties.name }, { name: 'description', label: 'Descripción', type: 'textarea', maxlength: 500, value: feature.properties.description }], accept: 'Guardar' });
      if (values) { feature.properties = values; feature.updatedAt = now(); upsertFeatureEntity(feature); mutate(); showActiveProject(); }
    } else if (action === 'geometry') { $('workspaceSheet').hidden = true; startDrawing(feature.type, feature); }
    else if (action === 'delete') {
      const accepted = await dialog({ title: 'Eliminar elemento', message: `Se eliminará “${feature.properties.name}”.`, accept: 'Eliminar', danger: true });
      if (accepted) { activeProject.features = activeProject.features.filter((item) => item.id !== feature.id); projectSource.entities.removeById(`feature-${feature.id}`); ui.requestRender(); mutate(); showActiveProject(); }
    }
  });
  $('projectLayers').addEventListener('click', async (event) => {
    const row = event.target.closest('[data-layer-id]');
    const button = event.target.closest('[data-layer-action]');
    if (!row || !button || !activeProject) return;
    const layer = getLayer(row.dataset.layerId);
    const action = button.dataset.layerAction;
    if (action === 'visibility') {
      layer.visible = layer.visible === false;
      layer.updatedAt = now();
      setLayerVisibility(layer);
      button.textContent = layer.visible === false ? '○' : '●';
      mutate(false);
    }
    else if (action === 'zoom') zoomLayer(layer.id);
    else if (action === 'rename') {
      const values = await dialog({ title: 'Renombrar capa', fields: [{ name: 'name', label: 'Nombre', required: true, maxlength: 80, value: layer.name }], accept: 'Guardar' });
      if (values) {
        layer.name = values.name;
        layer.updatedAt = now();
        const label = row.querySelector('.layer-main strong');
        if (label) label.textContent = layer.name;
        mutate(false);
      }
    } else if (action === 'style') {
      const values = await dialog({ title: 'Estilo de capa', fields: [{ name: 'color', label: 'Color', type: 'color', value: layer.style.color || '#75d6b0' }, { name: 'width', label: 'Grosor de línea (1–12)', type: 'number', value: layer.style.width || '4' }, { name: 'opacity', label: 'Opacidad (0–100 %)', type: 'number', value: String(Math.round((layer.opacity == null ? 1 : layer.opacity) * 100)) }], accept: 'Aplicar' });
      if (values) { layer.style.color = values.color; layer.style.width = Math.min(12, Math.max(1, Number(values.width) || 4)); layer.opacity = Math.min(1, Math.max(0, (Number(values.opacity) || 0) / 100)); refreshLayerEntities(layer.id); mutate(false); }
    } else if (action === 'delete') {
      const accepted = await dialog({ title: 'Eliminar capa', message: `También se eliminarán los elementos de “${layer.name}”.`, accept: 'Eliminar', danger: true });
      if (!accepted) return;
      const imports = activeProject.imports.filter((item) => item.layerId === layer.id);
      const removedFeatureIds = new Set(activeProject.features.filter((item) => item.layerId === layer.id).map((item) => item.id));
      const removedMeasurementIds = new Set(activeProject.measurements.filter((item) => item.layerId === layer.id).map((item) => item.id));
      for (const item of imports) { const source = importSources.get(item.id); if (source) viewer.dataSources.remove(source, true); importSources.delete(item.id); await db.deleteBlob(item.blobId); }
      activeProject.features = activeProject.features.filter((item) => item.layerId !== layer.id);
      activeProject.measurements = activeProject.measurements.filter((item) => item.layerId !== layer.id);
      activeProject.imports = activeProject.imports.filter((item) => item.layerId !== layer.id);
      activeProject.layers = activeProject.layers.filter((item) => item.id !== layer.id);
      projectSource.entities.values.filter((entity) =>
        (entity.ingeFeatureId && removedFeatureIds.has(entity.ingeFeatureId))
        || (entity.ingeMeasurementId && removedMeasurementIds.has(entity.ingeMeasurementId)))
        .forEach((entity) => projectSource.entities.remove(entity));
      ui.requestRender(); mutate();
    }
  });
  $('interactionUndo').addEventListener('click', () => { if (drawing && drawing.positions.length) { drawing.positions.pop(); updateDrawingPreview(); } });
  $('interactionFinish').addEventListener('click', finishDrawing);
  $('interactionGps').addEventListener('click', pointFromGps);
  $('interactionCancel').addEventListener('click', endInteraction);
  $('finishMeasure').addEventListener('click', finishMeasurement);
  $('saveMeasure').addEventListener('click', saveMeasurement);
  $('measureModeToggle').addEventListener('click', () => startMeasurement(measurement && measurement.kind === 'AREA' ? 'DISTANCE' : 'AREA'));
  $('clearMeasure').addEventListener('click', () => { if (measurement) { measurement.positions = []; updateMeasurement(); } });

  const initialize = async () => {
    try {
      await db.open();
      const activeId = await db.getSetting('activeProjectId', null);
      if (activeId) await openProject(activeId, false);
      else { setChip(); renderLayers(); }
    } catch (error) { ui.notify('Proyectos locales no disponibles; continúa en Explorar', 'error', 4400); }
  };
  const setVisible = (visible) => {
    if (!visible) {
      if (!$('modalScrim').hidden) $('dialogCancel').click();
      endInteraction();
      if (saveTimer) { clearTimeout(saveTimer); saveTimer = 0; saveNow(); }
    } else ui.requestRender();
  };
  window.InGeEarthProjects = {
    startDrawing, startMeasurement, showProjects,
    requestImport, endInteraction, handlePickedFeature,
    receiveImportStart, receiveImportChunk, receiveImportComplete, receiveImportError,
    receiveExportResult, setVisible
  };
  initialize();
})();

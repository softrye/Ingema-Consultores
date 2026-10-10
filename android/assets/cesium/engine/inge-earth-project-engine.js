// Motor de proyectos de InGe Earth sin interfaz (Visual Zero, 2026-10-10).
// Extraído de ui/inge-earth-projects.js: modelo de proyecto/capas/elementos,
// mediciones geodésicas, importación KML/KMZ (entidades normalizadas o
// referencia de solo lectura), exportación KML/KMZ y protocolo de bloques con
// InGeQtActivity. Persistencia: InGeEarthStorage (IndexedDB). Sin DOM.
(() => {
  'use strict';
  const db = window.InGeEarthStorage;
  const Cesium = window.Cesium;
  const map = window.InGeEarthMapEngine;
  if (!db || !Cesium || !map) return;

  const uuid = () => {
    try { if (crypto.randomUUID) return crypto.randomUUID(); } catch (ignored) {}
    return `inge-${Date.now().toString(36)}-${Math.random().toString(36).slice(2)}-${Math.random().toString(36).slice(2)}`;
  };
  const now = () => new Date().toISOString();

  // ------------------------------------------------------------- Modelo
  const featureCount = (project) => (project.features || []).length + (project.measurements || []).length + (project.imports || []).length;
  const defaultLayerName = (type) => ({ POINT: 'Puntos', POLYLINE: 'Líneas', POLYGON: 'Polígonos', MEASUREMENT: 'Mediciones' }[type] || 'Importados');
  const layerById = (project, id) => project && project.layers.find((layer) => layer.id === id);
  const layerFor = (project, type) => project.layers.find((layer) => layer.kind === type) || project.layers[0];
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
  // Copia con identidades nuevas (proyecto, capas, elementos, importaciones y
  // blobs KML/KMZ duplicados en IndexedDB).
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
    return copy;
  };
  const saveProject = async (project, active = true) => {
    project.updatedAt = now();
    await db.putProject(project);
    if (active) await db.setSetting('activeProjectId', project.id);
    return project;
  };

  // ------------------------------------------------------- Elementos
  const minimumVertices = (type) => type === 'POINT' ? 1 : type === 'POLYLINE' ? 2 : 3;
  const coordinatesFromPositions = (positions) => positions.map((position) => {
    const value = map.toCoordinates(position);
    return [value.longitude, value.latitude, value.height || 0];
  });
  const geometryFor = (type, positions) => ({
    type: type === 'POINT' ? 'Point' : type === 'POLYLINE' ? 'LineString' : 'Polygon',
    coordinates: type === 'POINT' ? coordinatesFromPositions(positions)[0] : coordinatesFromPositions(positions)
  });
  const nextFeatureName = (project, type) =>
    `${defaultLayerName(type)} ${project.features.filter((item) => item.type === type).length + 1}`;
  // Nuevo elemento en la capa de su tipo; un punto GPS conserva precisión,
  // marca de tiempo y fuente del fix.
  const addFeature = (project, type, positions, values, gps) => {
    if (positions.length < minimumVertices(type)) throw new Error(`Se necesitan al menos ${minimumVertices(type)} puntos`);
    const feature = { id: uuid(), layerId: layerFor(project, type).id, type, geometry: geometryFor(type, positions), properties: { name: values.name, description: values.description || '' }, style: {}, createdAt: now(), updatedAt: now() };
    if (type === 'POINT' && gps) {
      if (Number.isFinite(gps.accuracy)) feature.accuracyMeters = gps.accuracy;
      if (gps.coordinateTimestamp) feature.coordinateTimestamp = gps.coordinateTimestamp;
      if (gps.coordinateSource) feature.coordinateSource = gps.coordinateSource;
    }
    project.features.push(feature);
    return feature;
  };
  const updateFeatureGeometry = (feature, positions) => {
    feature.geometry = geometryFor(feature.type, positions);
    feature.updatedAt = now();
    return feature;
  };
  // Metadatos de un punto tomado de un fix GPS (ver InGeEarthMapEngine).
  const gpsPointMetadata = (fix) => ({
    accuracy: Number(fix.accuracy),
    coordinateTimestamp: fix.timestamp
      || (Number(fix.timestampMs) > 0 ? new Date(Number(fix.timestampMs)).toISOString() : new Date().toISOString()),
    coordinateSource: fix.source || (fix.provider ? `InGe Earth GPS (${fix.provider})` : 'InGe Earth GPS')
  });
  const removeFeature = (project, featureId) => {
    project.features = project.features.filter((item) => item.id !== featureId);
  };

  // ----------------------------------------------------- Mediciones
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
  const measure = (kind, positions) => ({
    distance: distanceFor(positions, kind === 'AREA'),
    area: kind === 'AREA' ? areaFor(positions) : 0
  });
  const addMeasurement = (project, kind, positions, name) => {
    if (positions.length < (kind === 'AREA' ? 3 : 2)) throw new Error(`Se necesitan al menos ${kind === 'AREA' ? 3 : 2} puntos`);
    const values = measure(kind, positions);
    const item = { id: uuid(), layerId: layerFor(project, 'MEASUREMENT').id, kind, name, geometry: { coordinates: coordinatesFromPositions(positions) }, distanceMeters: values.distance, areaMeters: values.area, createdAt: now(), updatedAt: now() };
    project.measurements.push(item);
    return item;
  };

  // ---------------------------------------------------------- Capas
  // Estilo de capa acotado: grosor 1–12, opacidad 0–100 %.
  const applyLayerStyle = (layer, values) => {
    layer.style.color = values.color;
    layer.style.width = Math.min(12, Math.max(1, Number(values.width) || 4));
    layer.opacity = Math.min(1, Math.max(0, (Number(values.opacity) || 0) / 100));
    layer.updatedAt = now();
    return layer;
  };
  const renameLayer = (layer, name) => { layer.name = name; layer.updatedAt = now(); return layer; };
  const toggleLayerVisibility = (layer) => { layer.visible = layer.visible === false; layer.updatedAt = now(); return layer.visible; };
  // Elimina la capa, sus elementos, mediciones e importaciones (con sus blobs).
  const removeLayer = async (project, layerId) => {
    const imports = project.imports.filter((item) => item.layerId === layerId);
    for (const item of imports) await db.deleteBlob(item.blobId);
    project.features = project.features.filter((item) => item.layerId !== layerId);
    project.measurements = project.measurements.filter((item) => item.layerId !== layerId);
    project.imports = project.imports.filter((item) => item.layerId !== layerId);
    project.layers = project.layers.filter((item) => item.id !== layerId);
    return imports.map((item) => item.id);
  };
  const cameraViewOf = (camera) => ({ position: [camera.positionWC.x, camera.positionWC.y, camera.positionWC.z], heading: camera.heading, pitch: camera.pitch, roll: camera.roll });

  // --------------------------------------------------- Importación KML
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
      const coordinate = map.toCoordinates(value);
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
  const isKmlName = (name) => /\.(kml|kmz)$/i.test(String(name || ''));
  const loadKmlBlob = (blob, name, scene) => Cesium.KmlDataSource.load(new File([blob], name, { type: blob.type }), { camera: scene.camera, canvas: scene.canvas, clampToGround: false });
  // Agrega un KML/KMZ al proyecto: entidades soportadas → elementos propios;
  // cualquier entidad no soportada conserva el archivo como referencia de
  // solo lectura (se devuelve `source` para mantenerlo cargado).
  const importIntoProject = async (project, blob, name, scene, time) => {
    const lower = name.toLowerCase();
    if (!isKmlName(lower)) throw new Error('Selecciona un archivo .kml o .kmz');
    const source = await loadKmlBlob(blob, name, scene);
    const layer = createLayer(name.replace(/\.(kml|kmz)$/i, ''), 'IMPORTED');
    project.layers.push(layer);
    const normalized = [];
    let unsupported = false;
    source.entities.values.forEach((entity) => {
      const item = extractEntity(entity, time, layer.id);
      if (item) normalized.push(item); else unsupported = true;
    });
    const blobId = uuid();
    const importId = uuid();
    await db.putBlob(blobId, blob, { originalFilename: name, mime: blob.type, size: blob.size });
    project.imports.push({ id: importId, layerId: layer.id, blobId, originalFilename: name, mime: blob.type || (lower.endsWith('.kmz') ? 'application/vnd.google-earth.kmz' : 'application/vnd.google-earth.kml+xml'), size: blob.size, importedAt: now(), referenceOnly: unsupported });
    if (!unsupported) project.features.push(...normalized);
    return { importId, layer, referenceOnly: unsupported, source };
  };
  // Bloques base64 recibidos de InGeQtActivity (streamEarthDocumentToWeb).
  const decodeChunks = (chunks, mime) => new Blob(chunks.map((chunk) => {
    const binary = atob(chunk); const bytes = new Uint8Array(binary.length);
    for (let index = 0; index < binary.length; index += 1) bytes[index] = binary.charCodeAt(index);
    return bytes;
  }), { type: mime });

  // --------------------------------------------------- Exportación KML
  const color = (value, fallback) => {
    try { return Cesium.Color.fromCssColorString(value || fallback); } catch (ignored) { return Cesium.Color.fromCssColorString(fallback); }
  };
  const cartesian = (coordinate) => Cesium.Cartesian3.fromDegrees(coordinate[0], coordinate[1], coordinate[2] || 0);
  const markerStyle = (pointColor, size) => ({ pixelSize: size || 11, color: pointColor, outlineColor: Cesium.Color.WHITE, outlineWidth: 2, disableDepthTestDistance: Number.POSITIVE_INFINITY });
  const sanitizeFilename = (name) => String(name || 'Proyecto').replace(/[\\/:*?"<>|]/g, '_').replace(/\s+/g, '_').slice(0, 90);
  const exportMime = (kmz) => kmz ? 'application/vnd.google-earth.kmz' : 'application/vnd.google-earth.kml+xml';
  const exportProjectBlob = async (project, kmz) => {
    const exportSource = new Cesium.CustomDataSource('Export');
    project.features.forEach((feature) => {
      const layer = layerById(project, feature.layerId);
      const style = { ...((layer && layer.style) || {}), ...(feature.style || {}) };
      const common = { name: feature.properties.name || defaultLayerName(feature.type), description: feature.properties.description || '' };
      if (feature.type === 'POINT') exportSource.entities.add({ ...common, position: cartesian(feature.geometry.coordinates), point: markerStyle(color(style.color, '#ffb84d'), Number(style.size) || 12) });
      else if (feature.type === 'POLYLINE') exportSource.entities.add({ ...common, polyline: { positions: feature.geometry.coordinates.map(cartesian), width: Number(style.width) || 4, material: color(style.color, '#75d6b0') } });
      else if (feature.type === 'POLYGON') {
        const positions = feature.geometry.coordinates.map(cartesian);
        exportSource.entities.add({ ...common, polygon: { hierarchy: positions, material: color(style.color, '#75d6b0').withAlpha(.28), outline: false } });
      }
    });
    project.measurements.forEach((item) => {
      const coordinates = item.geometry.coordinates.map(cartesian);
      exportSource.entities.add({ name: item.name, polyline: { positions: item.kind === 'AREA' ? coordinates.concat(coordinates[0]) : coordinates, width: 3, material: color('#ffd166', '#ffd166') }, polygon: item.kind === 'AREA' ? { hierarchy: coordinates, material: color('#ffd166', '#ffd166').withAlpha(.2) } : undefined });
    });
    const result = await Cesium.exportKml({ entities: exportSource.entities, kmz });
    let blob;
    if (result instanceof Blob) blob = result;
    else if (result && result.kmz instanceof Blob) blob = result.kmz;
    else blob = new Blob([result && result.kml ? result.kml : String(result || '')], { type: 'application/vnd.google-earth.kml+xml' });
    return { blob, filename: `${sanitizeFilename(project.name)}.${kmz ? 'kmz' : 'kml'}`, mime: exportMime(kmz) };
  };
  // Protocolo de exportación por bloques de 192 KiB hacia InGeQtActivity
  // (EarthUiBridge.beginEarthExport/appendEarthExportChunk/finishEarthExport).
  const EXPORT_CHUNK_BYTES = 192 * 1024;
  const sendBlobToAndroid = async (blob, filename, mime) => {
    const bridge = window.InGeEarthUiBridge;
    if (!bridge || typeof bridge.beginEarthExport !== 'function') throw new Error('EXPORT_BRIDGE_UNAVAILABLE');
    const count = Math.ceil(blob.size / EXPORT_CHUNK_BYTES);
    bridge.beginEarthExport(filename, mime, count);
    for (let index = 0; index < count; index += 1) {
      const buffer = await blob.slice(index * EXPORT_CHUNK_BYTES, Math.min(blob.size, (index + 1) * EXPORT_CHUNK_BYTES)).arrayBuffer();
      const bytes = new Uint8Array(buffer);
      let binary = '';
      for (let offset = 0; offset < bytes.length; offset += 0x8000) binary += String.fromCharCode(...bytes.subarray(offset, Math.min(bytes.length, offset + 0x8000)));
      bridge.appendEarthExportChunk(btoa(binary));
    }
    bridge.finishEarthExport();
    return count;
  };

  window.InGeEarthProjectEngine = {
    uuid, featureCount, defaultLayerName, layerById, layerFor, createLayer,
    createProjectModel, duplicateProject, saveProject,
    minimumVertices, coordinatesFromPositions, geometryFor, nextFeatureName,
    addFeature, updateFeatureGeometry, gpsPointMetadata, removeFeature,
    segmentDistance, distanceFor, areaFor, measure, addMeasurement,
    applyLayerStyle, renameLayer, toggleLayerVisibility, removeLayer, cameraViewOf,
    extractEntity, isKmlName, loadKmlBlob, importIntoProject, decodeChunks,
    sanitizeFilename, exportMime, exportProjectBlob, sendBlobToAndroid
  };
})();

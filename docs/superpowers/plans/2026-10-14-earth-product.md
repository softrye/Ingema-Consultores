# InGe Earth: pantalla, datos y documentos

**Objetivo:** ampliar el visor Retroplasma existente a pantalla completa, detalle regional real y documentos geográficos, dentro de la misma APK.
**Ejecución:** secuencial en este checkout; solicitud explícita del usuario de empezar directamente. Respaldo completo previo: `../_backups/earth_product_20261014_082631_before` (1551 archivos, SHA256 y bundle Git).
**Restricciones:** Qt 6.9.3; no build Android, ADB ni emuladores; no modificar servicios de Login, Calicatas, Supabase, Drive, IA ni shaders globales. Un renderizador, una cámara, GPS compartido, Dock global conservado.

- [x] Datos: probar proveedor EOX 2016 EPSG:4326, licencia CC BY 4.0, niveles 0–11 (~10 m), carga intermedia progresiva y zoom hasta 2 km; conservar NASA mundial y HLS opcional.
- [x] Geografía: ray picking WGS84, marcadores y medición geodésica; pruebas de polos, horizonte, antimeridiano y coordenadas inválidas.
- [x] Documentos: parser KML limitado y seguro, KMZ doc.kml sin extracción de recursos, geometrías nativas y exportación; probar XML inválido, límites, multi-geometrías y round trip.
- [x] UI: Item fullscreen; búsqueda, acciones accesibles, paneles inferiores, indicadores, GPS existente; Back cierra panel antes de salir de Earth.
- [x] Archivos: adaptador QML usa NothingDocuments existente para navegar, descargar y subir KML/KMZ dentro de la cuenta. Compartir exportación con Drive mediante chooser Android existente; nunca crear otro cliente Auth o Storage.
- [x] Validar CTest host, qmllint, recursos, firmas y diff protegido; documentar alcances y crear commits por componente.
- [ ] Validación visual Android: exclusivamente usuario; pendiente incluso si las pruebas host pasan.

El globo siempre conserva cartografía NASA incorporada. EOX es archivo 2016, sin edificios 3D ni actualización urbana; el servicio gratuito no tiene SLA. Se muestra atribución visible y resolución efectiva cargada. KMZ admite geometría KML, no modelos 3D, overlays raster ni NetworkLinks; se informa cualquier contenido omitido. Un cambio de cuenta elimina capas de memoria, sin borrar documentos locales.

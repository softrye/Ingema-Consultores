# InGeRetroplasma Native — plan de implementación autorizado

**Objetivo:** motor GPU y carga de escena 3D texturizada georreferenciada en InGe+.
**Spec:** ../../RETROPLASMA_AUDIT_20261013.md y solicitud P0 del usuario.
**Ejecución:** directa, secuencial, sin APK/ADB/emulador; pruebas host permitidas.

- [x] Fase1: audit ZIP, dependencias/licencias, backend real en fuentes y respaldo.
- [ ] Fase2: módulo QQuickRhiItem, shaders propios, recursos GPU y sincronización.
- [ ] Fase3: math/camera double, mallas OBJ, normales/UV, BC1 seguro y tests host.
- [ ] Fase4: manifest/proveedor local asíncrono y escena autorizada texturizada.
- [ ] Fase5: cámara única, gestos, navegación geográfica y límites near/far.
- [ ] Fase6: conectar preset al Dock existente y retirar captura del flujo principal.
- [ ] Fase7: árbol espacial/LOD, prioridad/cancelación, cache/telemetría/lifecycle.
- [ ] Fase8: revisión secuencial, verificaciones, commits y guía Qt Creator.

Archivos previstos: `src/retroplasma/{RetroplasmaMath,RetroplasmaCamera,
RetroplasmaGeometryDecoder,RetroplasmaTextureDecoder,RetroplasmaScene,
RetroplasmaDataProvider,RetroplasmaController,RetroplasmaItem}`; shaders/recursos
locales del módulo; `qml/Mobile/RetroplasmaEarthView.qml`, Home/CMake/main;
retiro de hooks exclusivamente FusionBridge en Activity/manifest.

Riesgos que deben verificarse: precisión geográfica, archivo truncado/índice
inválido, límites de texturas, selección de LOD sin agujeros, respuestas tardías
tras salir, reconstrucción RHI/contexto y registro QML único. No afirmar FPS,
shader funcional en GPU ni regresión Android sin mediciones del usuario.

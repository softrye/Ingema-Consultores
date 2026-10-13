# InGeRetroplasma Native — plan de implementación autorizado

**Objetivo:** motor GPU y carga de escena 3D texturizada georreferenciada en InGe+.
**Spec:** ../../RETROPLASMA_AUDIT_20261013.md y solicitud P0 del usuario.
**Ejecución:** directa, secuencial, sin APK/ADB/emulador. El usuario revocó
también la compilación host: la entrega final usa solo inspección estática.

- [x] Fase1: audit ZIP, dependencias/licencias, backend real en fuentes y respaldo.
- [x] Fase2: fuentes QQuickRhiItem, shaders propios, recursos GPU y sincronización.
- [x] Fase3: math/camera double, OBJ, normales/UV y BC1; tests fuente conservados.
- [x] Fase4: manifest/proveedor local asíncrono y escena autorizada texturizada.
- [x] Fase5: cámara única, gestos, navegación geográfica y límites near/far.
- [x] Fase6: preset del Dock existente y captura movida a respaldo histórico.
- [x] Fase7: árbol espacial/LOD, prioridad/cancelación, cache/telemetría/lifecycle.
- [x] Fase8: revisión secuencial, verificación estática y guía Qt Creator.

Estos checks acreditan implementación en fuentes. La ejecución Android está
pendiente de la compilación/pruebas del usuario; no son PASS_ANDROID.
NOT_IMPLEMENTED: semántica Protobuf RockTree, CRN, fuente remota y selector SAF.

Archivos previstos: `src/retroplasma/{RetroplasmaMath,RetroplasmaCamera,
RetroplasmaGeometryDecoder,RetroplasmaTextureDecoder,RetroplasmaScene,
RetroplasmaDataProvider,RetroplasmaController,RetroplasmaItem}`; shaders/recursos
locales del módulo; `qml/Mobile/RetroplasmaEarthView.qml`, Home/CMake/main;
retiro de hooks exclusivamente FusionBridge en Activity/manifest.

Riesgos que deben verificarse: precisión geográfica, archivo truncado/índice
inválido, límites de texturas, selección de LOD sin agujeros, respuestas tardías
tras salir, reconstrucción RHI/contexto y registro QML único. No afirmar FPS,
shader funcional en GPU ni regresión Android sin mediciones del usuario.

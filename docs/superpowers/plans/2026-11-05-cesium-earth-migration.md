# InGe Earth — Cesium 1.147

Objetivo autorizado: reemplazar el viewport de Earth por Cesium manteniendo la UI QML y el Dock global. Sin compilar ni instalar. El usuario pide avanzar directamente; se conserva una copia de los archivos previamente modificados antes de editar.

- [x] Runtime Cesium local y una página sin UI duplicada; cielo con el algoritmo estático de Claude, atmósfera y presupuestos por perfil.
- [x] Adaptar los paquetes RockTree existentes a tilesets 3D Tiles y contenido b3dm/GLB con origen local de alta precisión (técnica explicada en OpenGlobe).
- [x] Reutilizar el WebView existente, composición debajo de Qt y puente de comandos/telemetría para conservar controles, documentos y GPS.
- [x] Cámara y selección/medición/capas compartidas; globo base WGS84 continuo y horizonte/LOD a cargo de Cesium, cubriendo las funciones equivalentes estudiadas en osgEarth y Locus.
- [x] Verificación estática y qmllint; cambios aislados para un único commit. Validación visual, compilación y memoria quedan para el usuario.

No se mezclan OpenSceneGraph, C#/OpenTK ni la app Locus completa con el runtime. No se reutilizan claves de sus demos. Cada técnica incorporada se documentará; no se declara equivalencia total con Google Earth ni compatibilidad real sin pruebas Android.

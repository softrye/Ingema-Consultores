# InGe Earth / RockTree — 2026-11-05

## Alcance

Integración del proveedor de datos y algoritmos de la ingeniería inversa aportada en el viewport nativo Qt/RHI. No se incorpora otro visor Cesium, SDL ni otro motor de animaciones. Se conservan las estrellas y el shader de atmósfera que ya estaban modificados por Claude.

## Evidencia de datos reales

Sonda HTTPS de solo lectura (`python tests/earth/rocktree_probe.py`):

- `PlanetoidMetadata`: HTTP 200; epoch raíz **1016**, paquete de 13 bytes.
- `BulkMetadata`: HTTP 200; **124** registros, 3780 bytes.
- Nodo **02**: HTTP 200; **11998** bytes; una malla, 282 vértices, 2130 índices en strip, 1266 índices en las tres primeras capas, **253** triángulos no degenerados.
- La versión de imagen general era **1030** pero el nodo 02 declaraba **1040**. La consulta con la versión general devolvió HTTP 404. Respetar el override del nodo devolvió HTTP 200.

Las fixtures versionadas contienen sólo metadatos. La imagen/malla remota usada en la sonda no se incorpora al repositorio.

## Implementación

- Lector Protobuf acotado para el esquema adjunto; posiciones delta, OBB, matrices ECEF, UV, índices/strips y capas de terreno. Conserva todas las mallas/texturas de un nodo mediante partes con propietario de caché común.
- JPEG, BC1 y CRN-DXT1 a RGBA para no exigir S3TC en Mali. Descompresor CRN aportado con licencia ZLIB, ancho de puntero corregido para arm64 y rangos comprobados antes del descompresor.
- HTTPS, respuesta máxima 16 MiB, timeout/cancelación y caché de paquetes versionados; PlanetoidMetadata se consulta en red para obtener la versión actual.
- Recorrido lazy de BulkMetadata con descarte por frustum/horizonte y selección por error en pantalla. Un padre se sustituye cuando la cobertura hija visible está disponible. Errores de red/datos se muestran; no cambia de fuente automáticamente.
- RockTree es la fuente inicial si no había elección guardada. NASA/Sentinel siguen disponibles por selección explícita. La cámara se conserva al cambiar de fuente.
- GraphicsCore alimenta presupuestos CPU/GPU, concurrencia y detalle. Baja: 40/32 MiB, nivel 15; Alta: 80/72 MiB, nivel 18; Muy alta: 128/112 MiB, nivel 20; Extrema: 192/160 MiB, nivel 21. Los valores son límites de implementación, no mediciones de rendimiento. Presión térmica/memoria y ahorro de energía limitan el detalle.

## Verificación y límites

- `node tests/earth/rocktree_quality.cjs`: PASS. Se observó primero el fallo por ausencia de la política y después pasó con la política real utilizada por QML.
- `python tests/earth/rocktree_probe.py`: PASS con datos reales descritos arriba. Valida la compatibilidad del formato recibido, **no ejecuta el C++ de producción**.
- Pruebas host C++ añadidas a `tests/retroplasma/rocktree_tests.cpp`: metadatos reales, paquetes inválidos, paths, cancelación, geometría/texturas sintéticas y múltiples partes. **No ejecutadas: requieren compilar y el usuario lo prohíbe.**
- `node tests/earth/earth_engine_static.cjs`: falla en la comprobación antigua que prohíbe `ui/` en el Cesium HTML. El HTML de HEAD ya contiene esas rutas; no se modificó ese archivo.
- `node tests/calicatas/earth_picker_static.cjs`: falla porque referencia `src/graphics/InGeEarthHostController.cpp`, ausente también en HEAD. No se modifica esta prueba antigua ni Calicatas para esconder su fallo.
- Sin CMake, compilación, instalación, ADB, logcat ni prueba visual. **No se declara funcionalidad completa o rendimiento validado en Android.**

Pendiente comprobar con la compilación del usuario: carga inicial, acercamiento a zonas con fotogrametría, cambios de fuente/perfil, errores/reintento, volver a Home, memoria/GPU en A12, KML/KMZ/medición/GPS y atribuciones específicas de proveedores. La atribución general se muestra; la resolución de los copyright IDs específicos del proveedor aún necesita completarse.

## Riesgos

El protocolo es no documentado y puede cambiar. No se ha confirmado cobertura ni geometría urbana en todas las ubicaciones. La sonda de un nodo grueso no demuestra todo el streaming en el teléfono. Las cotas actuales de cámara y precisión del motor existente siguen vigentes. No se tocaron credenciales, AuthSession, Login, multicuenta ni Supabase.

## Trabajo ajeno

Se preservó una copia de los archivos previamente modificados en el directorio de artefactos de Codex antes de editar. Los commits de estas fases incluyen sólo adiciones de esta tarea; las modificaciones previas de Claude siguen en el árbol de trabajo.

# Sincronización de InGe+ Android a main — 29/10/2026

**Repositorio:** softrye/Ingema-Consultores
**Origen verificado:** release/android-20261029-source, commit 5b98fd8b4b4105cbe825755fda7f339e961b0ff9.
**Base de main:** de290e87a3c1b5b7c41c7bb20efa2272078d528c.
**Alcance de la operación:** 457 rutas actualizadas o incorporadas desde el release de fuentes (348 altas y 109 actualizaciones). Los demás archivos preexistentes en main se conservan; no hubo limpieza ni eliminación masiva.

## Cambios incluidos
- Interfaz Android QML: Calicatas, Rendiciones, Dock Liquid Glass, ajustes del editor, formularios y teclado.
- Sincronización de funciones de sesión, almacenamiento, archivos, preferencias y flujos de revisión.
- Integración nativa C++/Java, recursos gráficos, servicios de exportación, migraciones y pruebas.
- Documentación de source release, diagnósticos y pruebas.

## Seguridad e integridad
- El directorio de trabajo local AppCalicatasDemo **no fue modificado**, ni se hizo checkout, pull, reset o commit en la copia local.
- Se tomó como autoridad la instantánea de fuentes previamente publicada, verificada contra los 1.709 archivos locales candidatos: todos coincidían salvo el archivo de ejemplo gps/demo.nmea, que **no** se sobrescribe por este procedimiento.
- No se publicaron artefactos de QA bajo artifacts/, videos ni capturas locales.
- No se eliminan los archivos históricos de main que no existen en el snapshot; requiere limpieza posterior y evaluación independiente.
- Publicación de código fuente únicamente; no acredita APK compilada ni QA en dispositivo.

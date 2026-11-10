# InGe+ Android — Código fuente — 10 de noviembre de 2026

**Tipo:** actualización integral del repositorio de trabajo PC-02.
**Etiqueta:** `android-2026.11.10-source`
**Estado:** prerelease de código fuente; **QA en dispositivo pendiente**.
**Plataforma prevista:** Qt 6.9.3 / QML / CMake / Android arm64-v8a.

## Resumen de los cambios incluidos

- **Calicatas / Identidad / Ubicación:** interfaz de ficha y sección Identidad revisadas; nuevas vistas de inicio, ubicación y mapa; componentes con Figtree y controles optimizados para móviles; fotografías y vista de sitio ajustadas.
- **Colaboración y nube:** tratamiento de presencia y edición en tiempo real, integración de avatares, sincronización de logos y medios, mejoras en formularios y sesión de usuario. El indicador visual «viendo» se oculta en la ficha sin desactivar Supabase Realtime.
- **Geotecnia y exportación:** correcciones de estratos, laboratorio, clasificación SUCS, perfiles, fotos y ajustes del exportador Excel (QXlsx) y de la paginación.
- **Animaciones y apariencia:** cambios en Liquid Glass, QML, shaders, fidelidad gráfica y efectos; nuevas escenas y recursos de bienvenida, Halloween y personajes kawaii con video MP4.
- **Android / autenticación:** integración nativa Google OAuth, sesiones, permisos y ajustes del runtime gráfico; componentes de configuración y perfil.
- **Rendiciones / Documentos:** interfaz, presencia, sincronización, borradores, archivo, recuperación, validaciones y servicios C++ actualizados.
- **Infraestructura y pruebas:** fuentes QML/C++/Java, recursos, pruebas estáticas, migraciones SQL de Supabase, documentación y licencias de terceros añadidos o actualizados.

Se incluye el estado de fuente de la rama local al momento de esta publicación, junto con los commits anteriores de la rama.

## Alcance y exclusiones

- **Incluido:** código fuente, recursos utilizados por la app, pruebas, migraciones y documentación del proyecto.
- **No incluido:** carpetas de compilación, APK/AAB generados, archivos secretos locales y la carpeta de artefactos temporales `artifacts/` (logs, capturas de diagnóstico, estados y volcados locales); permanecen en PC-02.
- **No se ha compilado ni instalado** una nueva APK para esta publicación, por indicación del usuario.
- Los cambios visuales y de compatibilidad GPU, así como las rutas críticas de autenticación y nube, requieren validación posterior en dispositivos Android reales.
- Este release **no implica cambios desplegados** en la base de datos ni ejecución automática de migraciones Supabase.

## Referencias

- Directorio fuente: `AppCalicatasDemo`.
- Rama del snapshot: `release/android-20261110-source`.
- Se recomienda compilar con el kit Android arm64-v8a de Qt 6.9.3 y revisar errores QML/logcat antes de promoverlo a una versión estable.

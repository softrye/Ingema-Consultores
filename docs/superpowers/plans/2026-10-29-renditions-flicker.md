# Rendiciones: diagnóstico y eliminación de parpadeo

**Objetivo:** estabilizar Rendiciones en Qt 6.9.3 / Android arm64-v8a / OpenGL (Samsung A12).
**Arquitectura:** conservar bridge, almacén, sesión, Dock y el único InGeCoreFlow. Publicar cambios efectivos, conservar identidad de delegados y coordinar el ciclo de textura con navegación e IME.
**Especificación:** solicitud del usuario del 2026-10-29 y AGENTS.md.

## Restricciones

- Actualización del usuario: no ejecutar más compilaciones; el usuario compila. El build de instrumentación previo terminó; instalación rechazada por firma sin modificar datos. Validación Android posterior queda a cargo del usuario.

- Trabajar secuencialmente sobre fuentes, conservando cambios previos y datos locales.
- No modificar saveEditorDraft quiet=true ni crear otro sistema de animaciones.
- Sin secretos en diagnósticos. No cambiar contratos ni credenciales de Supabase.
- Un commit por fase; no declarar terminado sin build, instalación y regresión real.

## Fases

- [x] Instrumentación con flag --renditions-render-diagnostics. Build inicial correcto; instalación rechazada por firma. Logcat anterior: 26 avisos y resize IME confirmado. Tasas A12 pendientes; el usuario compila.
- [x] Publicación efectiva y modelos con identidad por localId. Pruebas QML ejecutadas; nuevos tests C++ y build/instalación finales pendientes del usuario.
- [x] Protección de textura, pausa de capturas y cola Realtime implementadas y probadas en QML. Loaders/Behaviors revisados. adjustResize conservado; la alternativa global exige validar los formularios reales.
- [ ] Host C:\InGeBuild\RenditionHost_20261016b, regresión Android completa, medición posterior, logcat, documentación y commit.

## Revisión

- Cambio de cuenta: ningún dato anterior debe sobrevivir en los modelos ni en la caché de publicación.
- Actualizar una fila, reordenar, insertar y eliminar: conservar sólo las identidades que sigan presentes.
- Salir a Home durante una respuesta RPC o cierre de menú: ningún shader debe dibujar sin textura.
- Invalidación Realtime durante edición: diferirla y procesarla una vez al salir, sin perder invalidaciones nuevas.
- Teclado: mantener visible el campo sin restar dos veces el solapamiento ni perder el borrador.

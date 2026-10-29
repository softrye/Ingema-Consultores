# Correcciones de Dock y revisión (2026-10-29)

## Dock: primera captura

La regresión del Dock fue introducida por la espera de `textureReady` del cambio anterior. Se retenía `glassTexture=null` hasta `scheduledUpdateCompleted` mientras todos sus consumidores estaban ocultos. En Qt 6.9.3, `scheduleUpdate()` sólo solicita trabajo: la textura se crea en el ciclo de render o al consultar su texture provider. Un productor invisible, sin consumidores visibles, no puede usarse como barrera de arranque de sus propios consumidores.

Se corrigieron las condiciones de HomeScreen y RenditionsApp para exponer el ShaderEffectSource con fuente y dimensiones válidas antes de la primera captura. La protección interna de GlassSurface ante fuente nula sigue activa. No se cambiaron tamaño, tinte, bisel, sombra, iconos, separadores, material ni animaciones del Dock.

Fuentes: `qml/Mobile/HomeScreen.qml` y `qml/Mobile/renditions/RenditionsApp.qml`. Prueba nueva: `tests/renditions/dock_glass_bootstrap.cjs`. Se comprobaron dos fallos de arranque antes de corregirlos; después pasan sus tres casos, los contratos existentes del Dock y la suite QML de estabilidad (12/12, sin avisos).

Comandos ejecutados (sin compilación):

```text
node --test tests/renditions/dock_glass_bootstrap.cjs tests/renditions/dock_first_tap_static.cjs tests/calicatas/health_glass_logos.cjs
C:/Qt/6.9.3/mingw_64/bin/qmltestrunner.exe -input tests/renditions/qml/tst_render_stability.qml -o artifacts/renditions-flicker-20261029/qml-dock-restored.txt,txt
git diff --cached --check
```

No se compiló ni instaló. La comprobación visual del A12 queda pendiente del build del usuario. La prueba de bindings verifica el arranque lógico; la suite offscreen no demuestra el resultado de OpenGL/Mali.

## Devolución a Borrador

Se consultaron únicamente las definiciones desplegadas de `get_rendition_review_context_v03`, `transition_rendition_review_v03` y `request_rendition_state_v04` en el proyecto configurado por `appcontext.cpp`. No hubo cambios de esquema, datos ni permisos.

La transición directa a BORRADOR exige estado inicial EN_REVISION y comentario vacío. La hoja del Dock y ReviewPanel exigían un motivo no vacío; además, el bridge rechazaba cualquier transición sin motivo antes de llamar al servidor. El texto mostrado en la captura activa exactamente la guarda `p_next_state='BORRADOR' AND (r.status<>'EN_REVISION' OR comment<>'')` del RPC.

Ahora ambas interfaces ocultan el motivo en la devolución directa a Borrador y envían `reason=""`. El bridge acepta ese caso mediante `RenditionAdminRpc::requiresReviewReason`. OBSERVADO, las otras transiciones, las solicitudes del propietario y las decisiones conservan el motivo obligatorio. La hoja limita el texto a los 500 caracteres del servidor. No se cambia de estado automáticamente ni se sustituyen las decisiones del servidor.

Fuentes: `RenditionsApp.qml`, `ReviewPanel.qml`, `renditionadminrpc.h` y `renditionflutterbridge.cpp`. Pruebas QML: se reprodujo el botón bloqueado y después pasan los dos flujos (Dock y panel), incluida la exigencia de motivo para Observado. Suite de estabilidad: 14/14, sin avisos. Se añadieron casos C++ a `tests/renditions/ui_controller.cpp`; su ejecución requiere que el usuario recompile los tests host.

Comando: `qmltestrunner.exe -input tests/renditions/qml/tst_render_stability.qml -o artifacts/renditions-flicker-20261029/qml-review-green.txt,txt`. No se ejecutó una transición sobre datos reales; la regresión Android y el RPC como usuario autenticado quedan pendientes del build del usuario.

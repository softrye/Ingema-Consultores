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

## Formulario, teclado y parpadeo

Se revisó el video aportado (67 s) extrayendo fotogramas locales con ffprobe/ffmpeg. Las imágenes de análisis permanecen en artifacts, no en Git; no se registraron valores de formulario en trazas.

Causas verificadas y correcciones:

- El viewport de InGeCoreFlow conservaba su valor inicial 0: no había ningún Binding desde la ventana real. Main.qml ahora publica `root.height` en el singleton existente. No se instancia otro motor ni se cambian AuthSession o la lógica de Login.
- Si el editor es más alto que la zona visible, `ensureActiveFocusVisible()` alternaba entre alinear su borde superior e inferior. Se reprodujo en QML con contentY alternando 288/440. Ahora sigue el rectángulo del cursor en ese caso. Un campo/cursor ya visible no reinicia el desplazamiento. Las líneas nuevas se revelan mediante la misma cola, escuchando `cursorRectangleChanged`.
- RField iniciaba revelados inmediatos además del temporizador IME. Ahora usa la cola existente de ImeAwareFlickable; el revelado tardío se reserva a sus contenedores antiguos sin esa cola. No se añade otro temporizador ni sistema de animaciones.
- «Siguiente» ocultaba el teclado al cambiar entre campo numérico y texto, esperaba 220 ms y lo reabría. Eso provocaba resize y restauración del scroll. Ahora cambia el foco y actualiza ImHints/ImQueryInput con el teclado abierto.
- El scroll espera a que termine la animación IME y respeta arrastre/flick del usuario. El modal conserva su posición al cerrar el teclado y reserva la altura de sus pestañas fijas.
- El MultiEffect de la hoja muestreaba en vivo toda la subapp, incluidas auras y cambios RPC. Ahora conserva una captura estática del mismo fondo con los mismos valores blurMax=48/blur=0.8/saturación. El vidrio del Dock no se modifica en esta fase. La hoja de cambio de estado también bloquea capturas/Realtime mientras está visible.

Fuentes: Main.qml, flowcore/InGeCoreFlow.qml, flowcore/ImeAwareFlickable.qml, renditions/RField.qml, RenditionExpenses.qml y RenditionsApp.qml. No se modificó adjustResize ni el guardado quiet=true.

Validación sin compilar:

- `tst_ImeStability.qml`: siete resultados correctos, sin avisos; incluye oscilación, 20 caracteres sin desplazamiento adicional, líneas nuevas, pausa IME y conservación de posición. Los dos primeros casos fallaron antes de corregir el algoritmo; el caso de líneas nuevas falló sin la conexión al cursor.
- `tst_render_stability.qml`: volver a ejecutar tras esta fase; cubre Dock/revisión/identidad/Realtime.
- `node --test tests/renditions/dock_glass_bootstrap.cjs tests/renditions/ime_input_contract.cjs tests/renditions/dock_first_tap_static.cjs tests/renditions/expense_modal_close.cjs tests/renditions/expense_editor_checkpoint_static.cjs tests/renditions/active_ui_static.cjs tests/calicatas/health_glass_logos.cjs`: 24/24.
- No se ejecutaron CMake, build, instalación ni transiciones de base de datos en estas tres correcciones. La compilación la realiza el usuario.

Los QML de Rendiciones contienen trabajo previo sin commit; se conserva en el working tree. Usar el working tree completo para el build, no una reconstrucción basada únicamente en los commits parciales de esta intervención.

## Usabilidad en el A12 después del build del usuario

Cuando el usuario confirme que compiló e instaló estas fuentes, ejecutar por ADB y observación de pantalla, con datos QA nuevos identificables:

1. Home: comprobar cápsula, separadores, sombra/filo y botón IA; entrar/salir de Rendiciones y abrir/cerrar Estado y menús del Dock.
2. Abrir dos rendiciones, esperar sus RPC y registrar cualquier reconstrucción, desaparición de vidrio o salto de lista.
3. Gasto: Concepto → Monto → Proveedor; usar «Siguiente» texto/número, pulsar campos con teclado abierto y arrastrar manualmente la hoja.
4. Comprobante: seleccionar cada tipo aplicable, rellenar número, RUC de prueba, detalle y justificación con varias líneas; comprobar cursor, pestañas fijas y acciones Guardar/Cancelar.
5. Pago: cambiar medio, escribir operación y volver a los campos anteriores. Sustentos: abrir/cerrar selector y verificar que conserva texto y posición.
6. Abrir/cerrar IME, alternar secciones y esperar autoguardado/RPC: medir saltos contentY, viewport y avisos de textura. No considerar terminada la tarea sólo por las pruebas host.
7. Guardar, reabrir y editar el gasto QA; fondo/tipo de cambio; presentar según permisos; devolver de EN_REVISION a BORRADOR sin motivo y enviar una observación con motivo.
8. Recorrer PDF/Excel y destinos disponibles, Archivo/Papelera y vuelta a Home según el alcance original. Registrar permisos o servicios externos que impidan alguna prueba.

El informe de dispositivo debe separar defectos reproducidos, pasos exactos, capturas/logcat, facilidad de rellenado y acciones pendientes. Las pruebas offscreen no acreditan cero parpadeo OpenGL/Mali, tipos de teclado Samsung ni ausencia de regresiones globales en Login/Perfil/Calicatas. Esos puntos siguen pendientes de la versión que compile el usuario.

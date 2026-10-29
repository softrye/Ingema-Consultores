# Correcciones tras la prueba del A12

## Render y teclado

- `RenditionsApp.qml`: el ShaderEffectSource conservado ya no pierde `sourceItem`
  al ocultar la página. La fuente de vidrio sigue registrada mientras viva la
  subapp; las capturas se detienen durante transición, teclado, menús y ocultación.
  Antes se invalidaban todos los consumidores en la salida y se restablecían al entrar.
- `HomeScreen.qml`: el efecto de foco 3D Touch no dibuja con el Loader oculto.
  El Dock pausa capturas durante menú, IME y transición; conserva su material.
  Sólo el menú recibe un tinte mayor para separar sus textos del fondo capturado.
- `RenditionExpenses.qml`: la captura del modal retiene su fuente y se actualiza
  una vez al abrir, sin alternar el sampler a null al cerrar.
- `RField.qml`: al pasar entre campos con distintos hints se solicita show()
  con el nuevo foco sin hide(). En Qt Android 6.9.3, update() sólo consulta los hints;
  showInputPanel() los envía al teclado. Fuente oficial:
  https://github.com/qt/qtbase/blob/v6.9.3/src/plugins/platforms/android/qandroidinputcontext.cpp#L829-L876
- `RExpenseQuickForm.qml`: pestañas opacas en oscuro, texto de justificación
  sobre la superficie del tema; no se ve el contenido desplazado detrás del selector.

## Validación y recuperación

Consulta de sólo lectura de las funciones reales `create_my_rendition_expense_v01`
y `update_my_rendition_expense_v01` en el proyecto de desarrollo. Corrección del
diagnóstico preliminar: JUSTIFICATION_REQUIRED depende de **categoría OTHER**
o **DECLARATION_WITHOUT_SUPPORT**; supportType OTHER exige **supportDetail**.

- `renditionvalidation.h` comprueba esas reglas antes de encolar; también
  paymentMethod OTHER exige paymentMethodDetail.
- `renditionlocalstore.cpp` permite corregir o eliminar una creación local
  definitivamente rechazada por esas tres reglas. La corrección conserva localId,
  adjuntos y borrador, genera un requestId nuevo y reinicia sus intentos.
  Respuestas perdidas, timeouts y conflictos siguen conservando la intención original.
  Reconoce los rechazos ya persistidos, sin migrar ni borrar datos del usuario.
- Formularios rápido/completo indican los campos obligatorios. El rápido abre
  la sección y enfoca el campo pendiente al intentar guardar.
- `RenditionEditor.qml`: Flow con ancho limitado en el navegador de carpetas;
  los botones pasan de fila en vez de exceder el borde.
- `RenditionsDiagnostics.qml` y diálogo de estado: ajuste de palabras largas.
  `renditionuicontroller.cpp`: mensajes comprensibles para las reglas anteriores
  y RENDITION_VALIDATION_ERROR; el código técnico permanece en diagnósticos.

## Comprobación y límites

Sin CMake, compilación, instalación ni reinicio de la app, por instrucción del usuario.

- qmltestrunner Qt 6.9.3, offscreen: render 15/15 e IME 7/7.
  La nueva prueba falla antes con sourceItem=null al ocultar, y pasa tras conservarlo.
- Node, handlers QML ejecutados y contratos de fuente: 14/14 y 20/20.
- Suite DraftContext: conserva fallos de sus mocks/entorno (haptic/resolveIssue,
  ventana y expectativas anteriores); no se declara que toda la suite pase.
- `checks.cpp`: nuevos casos nativos de validación, rechazo tras reinicio,
  requestId nuevo, borrado local permitido y respuesta perdida inmutable.
  Pendientes de compilar/ejecutar en C:\InGeBuild\RenditionHost_20261016b.
- Evidencia local: `artifacts/usabilidad_rendiciones_20261029/fix-*`.

Comandos: qmltestrunner -input (suites render, IME y DraftContext) -o archivo,txt;
node --test --test-reporter=tap (ocho archivos de tests/renditions); git diff --check.
SQL de sólo lectura pg_get_functiondef para contrastar reglas, sin cambios remotos.

Pendiente obligatorio tras el build del usuario: retomar RDC-2026-000043,
completar justificación y detalle, guardar/sincronizar, presentar, volver a borrador
desde el Dock, exportar ambos formatos a los tres destinos, archivar/restaurar,
Papelera y Home. Repetir vídeo y logcat: no se acredita aún cero parpadeos ni cero
avisos t1 en OpenGL/Mali con estos cambios.

El repositorio contiene modificaciones previas y componentes nuevos sin commit.
Los commits de esta fase aíslan cambios donde existe contexto versionado;
los ajustes dentro de bloques/componentes previos no versionados permanecen en
el árbol de trabajo. Compilar el árbol de trabajo completo, conservando esos archivos.

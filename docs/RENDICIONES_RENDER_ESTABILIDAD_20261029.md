# Rendiciones: estabilidad de renderizado (2026-10-29)

Estado: correcciones de fuentes y pruebas QML realizadas. Validación final Android pendiente de la compilación del usuario. No se declara eliminado el parpadeo en el Samsung A12.

## Alcance y evidencias

1. **Publicación.** El coalescer de 24 ms ya existía. Se conserva. `publishStateNow()` enviaba el estado incluso sin cambios; el controlador notificaba siempre. Ahora se compara el QVariantMap completo antes de serializar/enviar y antes de notificar QML. La caché del bridge se limpia en `receivedReset`; el controlador permite publicar nuevamente tras el reset. No se modificó el autoguardado quiet=true ni RenditionLocalStore.
2. **Identidad.** La prueba directa de Qt 6.9.3 muestra que un array de contenido igual conserva delegados en este host: la identidad nueva del array por sí sola no demuestra el fallo propuesto. Al cambiar una fila, 20 actualizaciones del modelo array crean 20 delegados; el diff por localId crea cero delegados adicionales. Se aplicó a propias/recibidas, gastos, documentos, sustentos, versiones y observaciones. Las recibidas usan rendición + número de versión. Sólo cambia el payload de la fila que cambió; movimientos, inserciones y eliminaciones conservan los supervivientes.
3. **Vidrio.** Los consumidores de RCard y RenditionCard sustituían `GlassSurface.visible` por `onScreen`, anulando la protección del sampler nulo. GlassSurface ahora es un Item con el ShaderEffect protegido dentro; forzar visible=true en el llamador no activa el shader sin fuente. Las tarjetas usan su material sólido mientras la textura no está lista. No se filtran avisos ni errores.
4. **Capturas.** El Timer de 50 ms sólo revisaba visibilidad/aplicación, y la fuente de tarjetas se exponía antes de completar su captura. Ahora se espera `scheduledUpdateCompleted`, se agrupan solicitudes pendientes y se congela el tamaño de textura de tarjetas entre capturas. Se suspenden las capturas programadas durante navegación, cambio de sección, teclado/animación IME, editores y menús, incluido el cierre animado. Home proporciona el estado de su transición y del menú Dock. El Dock tiene su propia confirmación de captura y pausa el modo live durante estas interacciones de Rendiciones. La textura de tarjetas se conserva durante la salida visible; se retira cuando la subapp queda oculta.
5. **Loaders/Behaviors.** El Loader principal usa `renditionsEverLoaded`: navegar normalmente no lo destruye. RGlassMenu conserva su contenido; no se añadió una animación. El cambio explícito de tema sí puede recrear la subapp fuera de pantalla; no se cambió la arquitectura de temas. Los Loaders de formularios nuevos/Archivo conservan su ciclo específico; no se alteró su lógica de borradores o recuperación. Las transiciones del Dock ya comparan contenido antes de generar un contexto; no se cambió DockContextController.
6. **Realtime.** El canal ya pide `self=false`; no se demostró eco propio en el A12. La fuente sí mostraba un Timer que sincronizaba sin comprobar edición. Se añadió un origen opaco por cliente para ignorar también un eco recibido. Las invalidaciones se agrupan en una cola pendiente y esperan a que terminen edición, IME, menús, transición y sincronización. Una invalidación posterior durante una operación queda pendiente. Al abandonar el tema, se descarta sólo la invalidación de ese tema.
7. **IME.** El buffer del proceso instalado contiene SurfaceView 720×1524 ↔ 720×866. InGeCoreFlow ya calcula el solapamiento dentro del viewport, evitando restarlo de nuevo cuando Android lo redujo. Se evaluó adjustNothing/adjustPan, pero no se cambió el manifiesto ni Java sin poder probar Login, Perfil y los formularios globales en el A12. Qt 6.9.3 aplica explícitamente el modo configurado en su [QtInputDelegate](https://github.com/qt/qtbase/blob/v6.9.3/src/android/jar/src/org/qtproject/qt/android/QtInputDelegate.java); cambiarlo afecta a toda la Activity. La eliminación del resize queda pendiente de una validación específica, no se afirma corregida.

## Archivos de esta intervención

- `src/cpp/renditionflutterbridge.{cpp,h}`: deduplicación, reset de caché y contadores opt-in.
- `src/cpp/renditionuicontroller.cpp`: no notificar estados iguales.
- `qml/Mobile/renditions/RStyle.js`: reconciliación ListModel y contadores.
- `RenditionsHome.qml`, `RenditionExpenses.qml`, `RenditionDocuments.qml`, `RenditionReview.qml`: modelos estables.
- `qml/Mobile/GlassSurface.qml`, `RCard.qml`, `RenditionCard.qml`: ciclo de sampler y material disponible.
- `RenditionsApp.qml`, `qml/Mobile/HomeScreen.qml`: captura, transición, diagnóstico y cola Realtime.
- `ExpenseEditor.qml`, `RenditionEditor.qml`, `RenditionDetail.qml`: exposición de estado de edición/interacción.
- `tests/renditions/ui_controller.cpp`: igualdad de estado, cambio efectivo y reset de cuenta; pendiente recompilar por el usuario.
- `tests/renditions/qml/tst_render_stability.qml`: pruebas ejecutables directamente sobre las fuentes.

El checkout tenía muchos cambios previos. Se conservaron. La validación documentada corresponde al working tree completo; los binarios host antiguos no validan los nuevos cambios C++.

## Comandos y resultados

Antes de la instrucción «no me compiles nada»:

```text
C:/Qt/Tools/CMake_64/bin/cmake.exe -S . -B C:/InGeBuild/QtCreator_Android_arm64_Release
C:/Qt/Tools/CMake_64/bin/cmake.exe --build C:/InGeBuild/QtCreator_Android_arm64_Release --target apk --parallel 4
adb install -r C:/InGeBuild/RenditionsFlicker_20261029/baseline.apk
```

El build de la instrumentación inicial terminó. La instalación fue rechazada con `INSTALL_FAILED_UPDATE_INCOMPATIBLE`: firma distinta. No se desinstaló, borró ni sustituyó la app existente. No hubo más compilaciones ni intentos de instalar después de la instrucción del usuario. El build inicial NO incluye las correcciones posteriores.

Después de esa instrucción, sólo ejecución de pruebas sin rebuild y lecturas:

```text
C:/Qt/6.9.3/mingw_64/bin/qmltestrunner.exe -input tests/renditions/qml/tst_render_stability.qml -o artifacts/renditions-flicker-20261029/qml-final.txt,txt
node --test tests/renditions/dock_first_tap_static.cjs tests/renditions/expense_editor_checkpoint_static.cjs tests/renditions/active_ui_static.cjs tests/renditions/expense_modal_close.cjs tests/calicatas/health_glass_logos.cjs
C:/Qt/Tools/CMake_64/bin/ctest.exe --test-dir C:/InGeBuild/RenditionHost_20261016b --output-on-failure
C:/Qt/6.9.3/mingw_64/bin/qmltestrunner.exe -input tests/renditions/qml -o artifacts/renditions-flicker-20261029/qml-suite.txt,txt
adb devices -l
adb shell pidof com.ingema.ingeplus
adb logcat -d --pid=<proceso instalado> -v brief
git diff --check
```

Entorno de pruebas QML: Qt 6.9.3, `QT_QPA_PLATFORM=offscreen`, `QT_QUICK_CONTROLS_STYLE=Basic`, `QT_QPA_FONTDIR=C:/Windows/Fonts`, PATH de Qt y MinGW. No se generaron ejecutables host nuevos.

- Suite nueva: 12/12 resultados QtTest correctos (incluidos init/cleanup), sin advertencias QML. Ver `artifacts/renditions-flicker-20261029/qml-final.txt`.
- Comprobaciones Node: 17 pruebas correctas.
- CTest host existente: 9/10. `qml-flow` falla en `IMG2 rendition dock: Buscar, Información, +, Actividad (no Atrás)`, igual que al ejecutarlo antes de los cambios de modelos; sus fixtures también carecen de las propiedades de vidrio actuales.
- Suite QML previa `tst_DraftContext.qml`: ocho fallos, con mocks incompletos (por ejemplo, `expenseError` ausente) y avisos previos de propiedades de vidrio ausentes. No se cambiaron esos tests para ocultar fallos. La suite nueva usa sus propios fixtures completos.
- Logcat de la app instalada: 26 avisos `Texture t1` en el buffer existente, de un periodo no delimitado; no es una medición de tasa ni un log posterior al arreglo. Se guardaron sólo líneas de render/SurfaceView/crash pertinentes.
- Captura inicial: `artifacts/renditions-flicker-20261029/before-initial.png`, sólo local, no incorporada al commit.

## Diagnóstico para el build del usuario

El flag `--renditions-render-diagnostics` activa `INGE_REND_RENDER`: solicitudes y emisiones por segundo, altas de delegados/GlassSurface, capturas programadas y geometría de viewport/IME. No incluye contenidos de filas ni datos de cuenta. Sin el flag no se inicia el temporizador de diagnóstico.

Después de compilar e instalar con la firma habitual, iniciar con los argumentos Qt correspondientes, por ejemplo:

```text
adb shell am force-stop com.ingema.ingeplus
adb logcat -c
adb shell am start -n com.ingema.ingeplus/com.ingema.ingeplus.InGeQtActivity --es applicationArguments --renditions-render-diagnostics
```

Confirmar primero que aparecen líneas `INGE_REND_RENDER`. Recorrer abrir/volver/otra rendición, Estado del Dock, gasto/teclado y Home. Guardar capturas equivalentes y un logcat nuevo. El objetivo es cero advertencias de textura, cero recreaciones al actualizar filas existentes y cero capturas programadas durante las interacciones bloqueadas. publish/s y comparación visual antes/después en el A12 siguen pendientes.

## Riesgos y validación pendiente

- Recompilar C++ Android/host con estas fuentes, instalar con la firma correcta y ejecutar la regresión real. El usuario asume la compilación por instrucción expresa.
- Confirmar ShaderEffectSource/OpenGL/Mali-G52, material del Dock al cambiar de fuente y reanudación tras segundo plano; las pruebas offscreen no demuestran esos resultados en GPU.
- Medir CPU/serialización con una lista grande: el diff serializa las filas para evitar roles QML anidados; no se ha medido en el A12.
- Probar multicuenta y reset con una nueva compilación. Ninguna migración ni borrado local fue añadido.
- Pendiente completo: crear rendición, añadir/editar gasto y sustento, fondo, tipo de cambio, presentar, estado desde Dock, PDF y Excel a teléfono/InGe Drive/Google Drive, archivar y Papelera.
- Pendiente decidir/corroborar el modo IME global con campos inferiores, cierre/restauración del scroll y Login/Perfil/Home. No se cambió adjustResize a ciegas.

No se afirma cero avisos en Android, ausencia de crash/ANR de la versión nueva ni regresión completa.

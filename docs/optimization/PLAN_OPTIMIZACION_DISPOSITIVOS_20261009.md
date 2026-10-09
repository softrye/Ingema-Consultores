# InGe+ Android: plan de optimización para distintos móviles

Resultado de un análisis de solo lectura del código: 42 hallazgos en 5 áreas. Un verificador adversarial revisó cada uno: 12 confirmados, 30 parcialmente correctos (con la propuesta ya corregida) y 0 refutados. Varios hallazgos se repetían entre áreas y aquí se agrupan. El detalle completo, con archivos, líneas, evidencia y riesgos, está en `anexo_hallazgos.md`.

Nada está compilado ni probado en un teléfono. Cada fase necesita build arm64-v8a, instalación, logcat y regresión (Login, Auth, multicuenta, Perfil y Home), y un commit por fase, según AGENTS.md.

## La causa principal

**InGe+ ya sabe qué tipo de móvil es, pero no lo usa.**
`InGePerformanceRuntime.java` clasifica el equipo (ULTRA_LOW…HIGH) y calcula un presupuesto (Hz, blur, animación, caché). Ese resultado solo lo leen el log y Cesium.

En QML, el perfil sale de `firstExperience.performanceLevel`, que vale 2 por defecto (`firstexperiencecontroller.cpp:60`). La Primera Experiencia está dormida (`Main.qml:3800`), así que nadie elige otro valor y ese 2 queda guardado. Resultado: **todos los móviles, incluido uno de 2 GB, arrancan en `performance.high`**, con blur, reflejos y shaders activos. Flutter Home recibe ese mismo perfil y tampoco entra en su modo ligero, así que el video de Auth nunca se apaga en gama baja.

## Fase A: arreglos rápidos (esfuerzo bajo, mucho efecto)

| # | Cambio | Dónde | Afecta a |
|---|---|---|---|
| A1 | Pedir la tasa de refresco del presupuesto (`budget.sustainableRefreshHz`) en vez de la del panel en `onCreate`. Usar `preferredDisplayModeId` (API 23+). | `InGeQtActivity.java:950-984` | Gama baja con panel de 90/120 Hz (hoy renderiza al doble). Flagships que arrancan a 60 Hz (hoy quedan fijos en 60). |
| A2 | `onRenderProcessGone` en los dos `WebViewClient` (Earth y asistente). | `InGeQtActivity.java:1358`, `InGeAssistantWebHost.java:47` | Todos. Hoy, si Android mata el renderer de la WebView, **cae toda la app**. |
| A3 | Llamar `InGeNativeLocation.stop()` al terminar el refinado de "Mi ubicación". | `InGeQtActivity.java:2147-2173` | Batería y CPU: hoy el GPS sigue a 1 Hz con 3 proveedores mientras estés en Earth. |
| A4 | Texto mínimo de 12 px y controles táctiles de al menos 48 dp en la ficha de Calicatas. Subir el suelo de `uiScale` en teléfono a unos 0.92. | `CalicataFormPage.qml:693-698`, 46 etiquetas con `root.dp(10/11)` | Móviles de 360 dp: hoy hay texto de 9 px y botones de 39-40 dp. |
| A5 | Breakpoint teléfono/tablet por **ancho** (más una altura estable sin teclado), no por `min(width, height)`. | `CalicataFormPage.qml:693`, `CalicatasEditorPage.qml:27-34` | Tablets, plegables y landscape: hoy toda la ficha se re-maqueta al abrir el teclado. |
| A6 | Recodificar el video de Auth de 2560x1440 a 20 Mbps (30 MB) a 1080p y unos 3.5 Mbps. | asset Flutter de Auth | Gama baja: su decodificador no garantiza 1440p. APK: unos 25 MB menos. |
| A7 | CMake: con `RelWithDebInfo`/`MinSizeRel`, poner `QT_ANDROID_DEPLOYMENT_TYPE=Release`. Añadir un preset `android-arm64-release` (firma por variables de entorno) y un `WARNING` cuando el build es Debug. | `CMakeLists.txt:11-33`, `CMakePresets.json` | Todos. Hoy un build sin tipo sale Debug (-O0, Flutter en JIT) y RelWithDebInfo sale *debuggable*. |

## Fase B: conectar el nivel del dispositivo (el cambio de mayor impacto)

Sin crear otro motor ni otro sistema de animación: se alimentan propiedades que **InGeCoreFlow ya tiene** (`lowMemoryMode`, `accessibility.reducedMotion`, `performance.profile`), que hoy nadie escribe.

1. **Java → C++**: exponer `tier`, `powerSave`, `thermal`, `animatorsEnabled` y `fontScale` como `Q_PROPERTY` con `NOTIFY` en el singleton `GraphicsCore` existente, sin un registro nuevo. Leerlos por JNI y refrescarlos con los listeners de ahorro de batería, térmico (API 29+) y `onConfigurationChanged`.
2. **Perfil automático**: añadir la marca `performance_user_set`. Mientras el usuario no haya elegido, derivar el perfil del tier en cada arranque: ULTRA_LOW/LOW → `safe` (0), MEDIUM → `balanced` (1), MEDIUM_HIGH/HIGH → `high` (2). No volver a persistir el 2 automático. Quitar el 2 fijo de `FirstExperience.qml:171/644`.
3. Enlazar `InGeCoreFlow.lowMemoryMode` y `accessibility.reducedMotion`, y respetar "Quitar animaciones" de Android.
4. Hacer que el Dock y el vidrio de Calicatas consulten el perfil (`lowCostGlass`) y bajar la resolución de sus capturas (`captureScale` 0.33-0.5).
5. Con esto, Flutter Home recibe `safe` en gama baja y se activa su modo ligero (incluido apagar el video).

## Fase C: memoria y estabilidad en móviles de 2-4 GB

- **`onTrimMemory`** en `InGeQtActivity`: avisar a Flutter (`sendMemoryPressureWarning`) y destruir la WebView de Earth si está oculta. Desde Android 14 solo llegan `UI_HIDDEN` y `BACKGROUND`.
- **Earth oculta**: antes de pausarla, bajar `cacheBytes` de Cesium y llamar `trimLoadedTiles()`. En LOW/ULTRA_LOW, destruirla al cerrarla.
- **Cámara**: guardar en QSettings la captura pendiente (ruta, campo, calicata) antes de abrir la cámara, y ofrecer recuperarla al volver. Hoy, si el sistema mata la app con la cámara abierta, **la foto se pierde**. No borrar capturas huérfanas sin confirmación (regla 13).
- **Avatar**: decodificar y escalar en un hilo aparte (QtConcurrent) y poner `sourceSize` en `CircularAvatar`. Hoy una foto de 12-50 MP se decodifica entera en el hilo GUI (48-200 MB).
- **APK**: sacar `resources.qrc` de escritorio del target Android (unos 11.5 MB muertos dentro del `.so`) y crear un `resources_mobile.qrc` con solo los alias usados. No se borra ningún archivo.

## Fase D: trabajo grande (planificar aparte)

- `formLoader` con `asynchronous: true` en Calicatas, y diferir la etapa Fotos.
- Exportación PDF/XLSX fuera del hilo GUI.
- Vidrio del Dock: una sola captura compartida en vez de 3-5 FBO por frame.
- Escala de texto unificada (A-/A+ de la app, fuente del sistema y `FlowAccessibility.textScale`) y una sola fuente de breakpoints en `InGeCoreFlow.metrics`.
- Safe area en los 4 lados (edge-to-edge forzado en Android 15+) y diseño para landscape compacto.
- QML con tipos para que qmlcachegen pueda compilar a C++ (hoy 0 de 1058 funciones tipadas).

## Descartado a propósito

- **Añadir armeabi-v7a u otras ABI**: va contra la regla del proyecto (solo arm64-v8a).
- **Tocar `setLayerType(HARDWARE)` de Earth sin medir**: probablemente sostiene el recorte del dock.
- **Cambiar ya el suelo global de `FlowAccessibility.scaledTextSize`**: afecta a toda la app. Mejor en una fase propia.

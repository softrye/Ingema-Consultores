# CHANGELOG COMPLETO — Optimización Android InGe+

Incluye los siete arreglos iniciales y fases A, B, C y D. Rama: `claude/awesome-davinci-egn3wo`.

No hay mediciones definitivas de FPS, RAM o tiempo de inicio en Android; cifras puntuales se deben revalidar.

## Resumen por fases

- Arreglos rápidos y revisión adversarial: refresco, WebView, GNSS, CMake, video Auth, texto táctil, breakpoints.
- A: clasificación Android → Qt/C++ → InGeCoreFlow → Flutter, opciones automáticas/manuales y reducción dinámica de efectos.
- B: onTrimMemory, liberación de Earth, persistencia de captura pendiente y avatar fuera del hilo gráfico.
- C: Liquid Glass con capturas menores, FlowIcon con DPR real, eliminación de blur inactivo, Flutter prewarm, escala de fuente.
- D: QRC mínimo en Android y QtLocation conservado solo para escritorio, sin tocar Cesium ni Supabase.

## Commits incluidos hasta el comienzo de esta continuación

### `730aa97542` — chore(releases): add SHA-256 safe incremental updater

Archivos: `.github/scripts/apply_delta.ps1`.

### `d486b29cc2` — chore(releases): package only changed paths with deletion manifest

Archivos: `.github/scripts/make_delta_release.py`.

### `de290e87a3` — ci(releases): publish ZIP with changed files on each main update

Archivos: `.github/workflows/release-delta.yml`.

### `a733e8e1c5` — perf(android): pedir la tasa de refresco del presupuesto del dispositivo

configureAdaptiveRefreshRate pedia display.getRefreshRate() leido en
onCreate y nunca usaba budget.sustainableRefreshHz. Un gama baja con
panel de 90/120 Hz renderizaba Qt y QML al doble de lo sostenible, y un
flagship que arrancaba en 60 Hz quedaba fijado a 60 toda la sesion.

Ahora, si el presupuesto alcanza la tasa maxima del panel, no se pide
nada y decide el sistema (adaptativo/LTPO, ajuste del usuario). Si es
menor, se fija el modo fisico con esa tasa y la misma resolucion
(preferredDisplayModeId, API 23+), con preferredRefreshRate como
respaldo. Las surfaces reciben la misma tasa (0 = sin preferencia).

Validacion: javac contra android-all API 35 sin errores nuevos.
Pendiente en dispositivo: INGE_REFRESH_REQUEST_HZ y
INGE_DISPLAY_ACTIVE_HZ en logcat (gama baja 90/120 Hz y flagship).

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01AaquLFZhVoHgtnU5giZqcX

Archivos: `android/src/com/ingema/ingeplus/InGeQtActivity.java`.

### `00f6d2aebf` — fix(android): sobrevivir a la muerte del renderer de WebView

Ningun WebViewClient implementaba onRenderProcessGone. Desde Android 8,
si el sistema o el OEM matan el renderer (presion de memoria con Earth
oculto, muy habitual en equipos de 2-4 GB) o este falla, Android mata
tambien el proceso de InGe+ y el usuario lo ve como un cierre al volver.

Earth: con la vista oculta se libera y la siguiente apertura la recrea
por el camino existente. Si estaba visible se recrea una vez; una
segunda perdida en menos de 30 s vuelve a Home por el mismo puente de
Back (nativeRequestEarthBackToHome) y, si el puente no acepta, recrea.
Asistente IA: se cierra por closeFromUser(), que ya notifica a Qt.

Validacion: javac contra android-all API 35 sin errores nuevos.
Pendiente en dispositivo: adb shell am crash del proceso
:sandboxed_process de WebView con Earth oculto y visible; buscar
INGE_EARTH_RENDERER_GONE en logcat y que la app siga viva.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01AaquLFZhVoHgtnU5giZqcX

Archivos: `android/src/com/ingema/ingeplus/InGeAssistantWebHost.java`, `android/src/com/ingema/ingeplus/InGeQtActivity.java`.

### `cbbbcad608` — fix(android): apagar el GPS de Earth al terminar la busqueda

Tras "Mi ubicacion" (8 s de busqueda + 15 s de refinado) solo se
cancelaban los Runnables: GPS, fused y red seguian registrados a 1 Hz,
con callbacks en el hilo principal de Android, mientras el usuario
permaneciera en Earth. Despues del refinado no se emite ningun fix.

Ahora InGeNativeLocation.stop() se llama al vencer el refinado y en la
rama sin fix. InGeNativeLocation solo lo usa Earth; Calicatas y Mapa
usan QGeoPositionInfoSource y no cambian.

Validacion: javac contra android-all API 35 sin errores nuevos.
Pendiente en dispositivo: adb shell dumpsys location tras 25 s.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01AaquLFZhVoHgtnU5giZqcX

Archivos: `android/src/com/ingema/ingeplus/InGeQtActivity.java`.

### `d8392c21ee` — build(android): RelWithDebInfo y MinSizeRel generan APK release

QT_ANDROID_DEPLOYMENT_TYPE copiaba CMAKE_BUILD_TYPE. Qt 6.9.3 solo
reconoce Debug o Release en esa variable: con RelWithDebInfo o
MinSizeRel no pasa --release a androiddeployqt, asi que el APK salia
debuggable (ART sin optimizaciones completas) y Gradle enlazaba el AAR
flutter_debug, con Home/Auth/Rendiciones en JIT.

Ahora Debug -> Debug y cualquier otro tipo -> Release. El valor por
defecto (Debug cuando no se indica tipo) no cambia mientras la firma no
este configurada; en ese caso se imprime un aviso para no medir
rendimiento sobre un build Debug.

Validacion: proyecto CMake minimo con el bloque Android para "",
Debug, RelWithDebInfo, MinSizeRel y Release.
Pendiente: un build RelWithDebInfo necesita firma (QT_ANDROID_SIGN_APK
o la firma de Qt Creator) para poder instalarse por adb.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01AaquLFZhVoHgtnU5giZqcX

Archivos: `CMakeLists.txt`.

### `6b8df05c3e` — perf(auth): video de fondo a 1080p y fuera el PNG de Auth sin uso

El video de Auth era H.264 Main 5.0 a 2560x1440, `20 Mbps y 30 MB. Los
decodificadores de gama baja (Helio, Unisoc, Snapdragon 4xx) solo
garantizan 1080p30; por encima caen a software o fallan y Auth queda en
el poster (AUTH_VIDEO_UNAVAILABLE). En vertical 20:9 el modo cover solo
muestra `26% del ancho decodificado.

Recodificado a 1920x1080 (igual que el poster), H.264 Main 4.0,
yuv420p bt709, CRF 18 con techo de 6 Mbps, GOP 60, faststart y sin la
pista de audio muda: 6.2 MB, 365 fotogramas, misma duracion. SSIM frente
al original escalado: 0.980.

ingema_auth_background.png (3.5 MB) solo figuraba en pubspec.yaml; se
quita del bundle sin borrar el archivo.

El cambio de assets fuerza la regeneracion del AAR (GLOB de assets en
CMakeLists.txt).

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01AaquLFZhVoHgtnU5giZqcX

Archivos: `flutter/inge_earth/assets/auth/ingema_auth_video.mp4`, `flutter/inge_earth/pubspec.yaml`.

### `b86045cfd3` — fix(calicatas): texto minimo 12 px y botones de 48 dp en telefonos pequenos

En telefono uiScale = clamp(ladoMenor/430, 0.82, 1.00): a 360 dp vale
0.84, asi que dp(11) daba 9 px en 44 etiquetas, dp(10) 8 px, dp(12)
10 px y hBtn 39 dp, por debajo de los 48 dp de Android. La barra del
editor (__sp) ya usa un suelo de 12 px para el texto.

- Nuevo sp(v) = max(12, dp(v)), la misma regla que __sp() del editor.
- Los 81 font.pixelSize que llamaban a root.dp() pasan a root.sp().
  Solo se cambian las llamadas de primer nivel: los root.dp() anidados
  (umbrales de ancho dentro de un ternario) siguen siendo geometria.
  Por encima de 14 px el resultado no cambia.
- hBtn y touchMinTarget nunca bajan de 48.
- La geometria (anchos, alturas, margenes) sigue escalando con dp().

Validacion: qmlcachegen (Qt 6.9.3) compila el archivo; qmllint da las
mismas 4567 advertencias antes y despues (ninguna nueva).
Pendiente en dispositivo: ficha completa a 360 dp y a 320 dp (chips
"Auto", "1 foto", iniciales y la barra de acciones de Fotos).

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01AaquLFZhVoHgtnU5giZqcX

Archivos: `qml/Mobile/pages/CalicataFormPage.qml`.

### `5b3f407b30` — fix(calicatas): el teclado ya no cambia el modo phone/tablet de la ficha

CalicatasEditorPage y CalicataFormPage clasificaban con
Math.min(width, height). Con adjustResize la ventana se encoge al abrir
el IME, asi que en una tablet en landscape (unos 1280x730 dp) el alto
bajaba a `350 dp, isPhone pasaba a true y `40 tokens isPhone ? a : b,
uiScale y __armScale cambiaban a la vez: toda la ficha se re-maquetaba
con el campo enfocado. Igual en plegables abiertos y en split-screen.

Ahora el alto de referencia es el maximo visto con el ancho actual (el
IME nunca cambia el ancho). Rotar o redimensionar la ventana cambia el
ancho y reinicia la referencia; Qt.callLater espera a que ancho y alto
se asienten. Se inicializa en Component.onCompleted. Con el teclado
cerrado las clasificaciones son identicas a las anteriores.

Validacion (Qt 6.9.3 via PySide6, offscreen): arnes QML con la misma
logica: tablet landscape con y sin teclado, rotacion, telefono 360 dp
con teclado y en landscape, plegable con teclado, split-screen y pagina
creada sin cambios de tamano posteriores: todos PASS. qmlcachegen
compila ambos archivos; qmllint sin advertencias nuevas (4567 y 1241).
Pendiente en dispositivo: tablet/plegable escribiendo en Identidad,
Estratos y Laboratorio.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01AaquLFZhVoHgtnU5giZqcX

Archivos: `qml/Mobile/pages/CalicataFormPage.qml`, `qml/Mobile/pages/CalicatasEditorPage.qml`.

### `8147f257a7` — docs(optimization): conservar la auditoria de 42 hallazgos por dispositivo

Plan por fases, anexo con evidencia (archivo:linea, codigo citado,
verificacion adversarial, cambio recomendado y riesgos) y la misma
informacion en JSON. Sirven de base para futuras auditorias y para
seguir el estado de cada hallazgo.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01AaquLFZhVoHgtnU5giZqcX

Archivos: `docs/optimization/ANEXO_42_HALLAZGOS_20261009.md`, `docs/optimization/PLAN_OPTIMIZACION_DISPOSITIVOS_20261009.md`, `docs/optimization/README.md`, `docs/optimization/hallazgos_20261009.json`.

### `a2bd2e9389` — fix(android): correcciones de la revision adversarial (refresco, WebView, GPS)

Revisores escepticos por commit encontraron defectos reales:

Refresco (a733e8e):
- El modeId se calculaba una vez en onCreate; al plegar/desplegar o
  cambiar de pantalla los IDs ya no existen y el limite se perdia. Ahora
  solo se pide preferredRefreshRate, que el sistema resuelve contra la
  resolucion por defecto de la pantalla actual.
- MEDIUM con panel 60/120 (sin modo intermedio) bajaba a 60 Hz. Ahora
  deriveBudget usa la tasa maxima en ese caso y decide el sistema.

WebView (00f6d2a):
- Con la app en segundo plano (caso tipico del LMK) Earth se recreaba en
  pausa y gastaba el unico reintento. Ahora solo se recrea en primer
  plano; en segundo plano se libera y onResume lo recrea.
- earthAssetLoader quedaba null mientras podian llegar peticiones del
  WebView muerto (NPE relanzado en el hilo UI). Cada WebView captura su
  propio loader.
- La perdida del renderer solo quedaba en logcat: ahora se registra en
  el diagnostico beta (EARTH_/ASSISTANT_RENDERER_GONE, ERROR si
  didCrash), segun la regla 2 de AGENTS.md.

GPS (cbbbcad):
- Apagar el GNSS a los 8 s sin fix impedia que un arranque en frio sin
  asistencia (18-30 s) llegara a resolverse. Ahora sigue rastreando
  mientras el mejor fix sea peor de 20 m, con un limite de 90 s desde el
  inicio de la busqueda; un fix tardio se entrega y un fix preciso cierra
  la sesion 15 s despues. onPause y ocultar Earth lo siguen apagando.

Validacion: javac contra android-all API 35; el unico simbolo nuevo sin
resolver es ...

Archivos: `android/src/com/ingema/ingeplus/InGeAssistantWebHost.java`, `android/src/com/ingema/ingeplus/InGePerformanceRuntime.java`, `android/src/com/ingema/ingeplus/InGeQtActivity.java`.

### `b82f7133ae` — fix(build,auth): correcciones de la revision adversarial (CMake y video)

CMake (d8392c2):
- La comparacion con "Debug" distinguia mayusculas: -DCMAKE_BUILD_TYPE=debug
  compilaba -O0 pero empaquetaba release sin firmar. Ahora se compara en
  mayusculas, como hace Qt 6.9.3.
- RelWithDebInfo/MinSizeRel pasan a release sin firma: aviso explicito
  si QT_ANDROID_SIGN_APK esta apagado (adb install lo rechazaria). En
  Release no cambia nada respecto a antes y no se avisa.
- Nota para RelWithDebInfo: en Qt Creator la configuracion Profile
  instala un APK debug por su cuenta; para medir usar Release.

Video de Auth (6b8df05):
- 1920x1080 se codificaba a 1920x1088 con recorte en el SPS. En Android
  10+ Flutter (ImageReader) no aplica ese recorte y dibuja 1088 filas:
  salto de `9 px y 8 filas de relleno al pasar del poster al video.
  Ahora 1792x1008 (16:9 exacto, multiplo de 16, sin recorte), H.264 Main
  4.0, CRF 18, VBV 6 Mbps/12 Mb: 5.8 MB, 365 fotogramas, media 3.6 Mbps,
  pico de 15 Mbps en 1 s (dentro de L4.0). SSIM 0.982 frente al original
  escalado y 0.993 del primer fotograma frente al poster 1920x1080.

Revisado y descartado: "el AAR debug no se regenera". flutter build aar
genera debug, profile y release salvo --no-debug, asi que la regla
existente tambien actualiza flutter_debug.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01AaquLFZhVoHgtnU5giZqcX

Archivos: `CMakeLists.txt`, `flutter/inge_earth/assets/auth/ingema_auth_video.mp4`.

### `5dfe43c34e` — fix(calicatas): breakpoint con teclado sin transitorio y con split vertical

Correcciones de la revision adversarial de 5b3f407:

- Al rotar, la altura retenida se mezclaba con el ancho nuevo hasta el
  Qt.callLater: el editor hacia phone -> tablet -> phone durante una
  vuelta del event loop (unos 250 bindings recalculados dos veces y un
  posible frame con layout de tablet en el crossfade de rotacion). Ahora
  la altura retenida solo se usa con el mismo ancho, y la expresion lee
  width/height directamente: una rotacion se clasifica en el mismo
  frame.
- "Alto maximo con el ancho actual" ignoraba reducciones verticales
  legitimas (split arriba/abajo, divisor, ventanas libres): un Fold en
  split seguia en tablet en 370 dp de alto. Ahora solo se conserva el
  alto previo mientras se escribe: IME visible o un campo con cursor con
  foco (el foco llega antes que el resize del IME).

Validacion (Qt 6.9.3, offscreen; Window -> Loader -> Page -> Loader ->
Item con setGeometry atomico, como Android): teclado con foco en una
tablet landscape sin cambio de modo; rotacion de telefono y de tablet
sin cambio del editor; Fold landscape en split arriba/abajo pasa a
phone. En la ficha queda el transitorio sincrono de anclas (ancho y
alto llegan por separado en el mismo redimensionado), igual que antes
de 5b3f407: no se pinta ningun frame entre ambos. qmlcachegen compila.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01AaquLFZhVoHgtnU5giZqcX

Archivos: `qml/Mobile/pages/CalicataFormPage.qml`, `qml/Mobile/pages/CalicatasEditorPage.qml`.

### `dccf8f37cb` — fix(calicatas): el rotulo de ubicacion ya no se sale de su vidrio

Revision adversarial de b86045c: con el texto minimo de 12 px,
"UBICACION DE LA CALICATA" (letterSpacing 1.4, DemiBold) mide `198 px y
el recuadro de ancho fijo min(ancho - 20, dp(230)) quedaba en 193 px a
360 dp: el texto se pintaba 15 px fuera del LiquidGlassSurface, encima
del mapa (19 px a 320 dp).

El recuadro crece con el rotulo sin pasar del ancho disponible del mapa
y el Text recorta con elide como red de seguridad.

Validacion: medido con Rubik SemiBold y Qt 6.9.3 a 320, 360, 384, 393 y
412 dp: el rotulo cabe entero (197.8 px en un recuadro de 217.8-220.8)
sin recorte.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01AaquLFZhVoHgtnU5giZqcX

Archivos: `qml/Mobile/pages/CalicataFormPage.qml`.

### `61744b3863` — perf(core): el nivel real del dispositivo llega a Qt, InGeCoreFlow y Flutter

Problema (hallazgos tier-no-llega-a-qml, presion-memoria-y-tier,
budget-android-no-llega-a-inGeCoreFlow, termico-ahorro-bateria): Java
clasificaba el equipo (ULTRA_LOW..HIGH) y solo lo usaban el log y
Cesium. QML tomaba firstExperience.performanceLevel (2 por defecto, la
Primera Experiencia esta dormida) y lo persistia: todos los moviles,
incluidos los de 2-3 GB, arrancaban en performance.high con blur,
reflejos y shaders. Ahorro de bateria, temperatura y "Quitar
animaciones" de Android no se respetaban, y el tier se calculaba una sola
vez en onCreate.

Java (InGePerformanceRuntime): tier base (solo hardware) y tier vivo
(hardware + ahorro de bateria + termico). Receptor de
ACTION_POWER_SAVE_MODE_CHANGED, listener termico (API 29+), observador
de ANIMATOR_DURATION_SCALE y fontScale desde onConfigurationChanged. Si
el tier vivo cambia se recalcula el presupuesto y la Activity vuelve a
aplicar la tasa de refresco. stateJson() y nativePerformanceStateChanged
publican el estado.

C++ (GraphicsCore, mismo singleton y registro): Q_PROPERTY deviceTier,
baseDeviceTier, lowRamDevice, totalMemoryMb, powerSaveMode,
thermalStatus, systemAnimationsEnabled, systemFontScale y
memoryTrimLevel (NOTIFY deviceStateChanged). Lee stateJson() al crearse
y recibe los cambios por JNI en cola hacia el hilo GUI.

QML (motor unico InGeCoreFlow, sin sistema paralelo):
- automaticPerformanceLevel (LOW/ULTRA_LOW -> Ahorro, MEDIUM ->
  Balance, MEDIUM_HIGH/HIGH -> Alto; escritorio -> Balance) y
  ...

Archivos: `android/src/com/ingema/ingeplus/InGePerformanceRuntime.java`, `android/src/com/ingema/ingeplus/InGeQtActivity.java`, `qml/Mobile/Main.qml`, `qml/Mobile/flowcore/GlobalContextDock.qml`, `qml/Mobile/flowcore/InGeCoreFlow.qml`, `qml/Mobile/pages/CalicataFormPage.qml`, `qml/Mobile/pages/CalicataLiquidGlass.qml`, `qml/Mobile/pages/CalicataReview.qml`, `qml/Mobile/pages/CalicatasEditorPage.qml`, `src/graphics/InGeGraphicsCore.cpp`, `src/graphics/InGeGraphicsCore.h`.

### `ba7741a3d8` — fix(calicatas): no perder la foto si Android cierra InGe+ con la camara abierta

Hallazgo camara-muerte-proceso-pierde-foto (confirmado): la camara del
OEM pide mucha memoria y en equipos de 2-4 GB Android suele matar InGe+
mientras esta delante. El destino (archivo y bloque) solo vivia en
memoria y en la lambda de startActivity: al volver en frio el resultado
no tenia destino y el JPEG quedaba huerfano en cache/calicata_camera.

- La ficha pasa a PermissionHelper su identidad estable (doc.fileUrl)
  antes de abrir la camara.
- PermissionHelper guarda en QSettings (photoCapture/pending) archivo,
  URI, bloque, ficha y hora justo antes de startActivity; el callback en
  proceso (cualquier resultado) borra la marca.
- Al abrir esa ficha (Component.onCompleted u onDocChanged),
  _recoverInterruptedCapture prepara el mismo estado que una captura
  normal y recoverPendingCapture valida el JPEG (bytes > 0 y decodificable),
  lo copia a la cache privada y emite photoSelected: el usuario ve el
  dialogo de datos impresos de siempre.
- Un solo intento por captura. Solo se borra el marcador vacio que se
  crea antes de lanzar la camara; si la copia falla, la foto se conserva
  en disco (regla 13).

Validacion: g++ -fsyntax-only (rama escritorio y Android con stubs JNI)
sin errores nuevos; qmlcachegen compila la ficha.
Pendiente en dispositivo: tomar foto con "No conservar actividades"
activado (o adb shell am kill con la camara delante) y reabrir la ficha.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: ...

Archivos: `permissionhelper.cpp`, `permissionhelper.h`, `qml/Mobile/pages/CalicataFormPage.qml`.

### `76aa04d72e` — perf(android): presion de memoria hacia Flutter, Earth y QML

Hallazgos memoria-earth-webview-sin-ontrimmemory y
earth-webview-retenida (parciales): no habia onTrimMemory; el host no es
una FlutterActivity, asi que Flutter nunca recibia avisos de memoria, y
el WebView de Cesium (contexto WebGL, teselas y su proceso renderer) se
quedaba vivo oculto hasta onDestroy. En equipos de 2-4 GB eso hace que
el LMK mate el proceso al abrir la camara o cambiar de app.

- onTrimMemory/onLowMemory en InGeQtActivity: mismo contrato que
  FlutterActivityAndFragmentDelegate (notifyLowMemoryWarning,
  sendMemoryPressureWarning y FlutterRenderer.onTrimMemory) para los
  motores Home y Earth. APIs verificadas con javap en el embedding exacto
  1.0.0-5a2a6a42cce6.
- Con nivel >= RUNNING_LOW se libera el WebView de Earth si no es la
  superficie pedida; la siguiente apertura (u onResume) lo recrea.
- LOW/ULTRA_LOW/low-RAM: Earth oculto se libera 2 s despues de salir de
  pantalla; durante el Back se reintenta hasta que termina. Mostrarlo
  cancela la liberacion. MEDIUM+ lo conserva para reabrir rapido.
- El nivel de trim se publica a GraphicsCore (memoryTrimLevel) y vuelve
  a 0 en onResume.
- Qt: en ApplicationSuspended (antes de que Qt bloquee su bucle) se
  liberan los componentes QML sin uso y el heap JS. No toca el scene
  graph ni datos.

Descartado con motivo: recortar la cache de Cesium por JS al ocultar
Earth; con el WebView oculto no se pinta ningun frame y el recorte no se
aplica. Liberar el WebView entero es determinista.

Validacion: javac ...

Archivos: `android/src/com/ingema/ingeplus/InGePerformanceRuntime.java`, `android/src/com/ingema/ingeplus/InGeQtActivity.java`, `main_mobile.cpp`.

### `8d4c81010e` — perf(perfil): la foto de perfil se procesa fuera del hilo GUI y a su tamano

Hallazgos avatar-decodificacion-completa y avatar-sin-sourcesize
(confirmados): updateUserAvatar (Q_INVOKABLE, hilo GUI) decodificaba la
foto completa (12-50 MP = 48-200 MB RGBA), copiaba, escalaba y codificaba
PNG de forma sincrona; ademas los avatares (92, 112 px, cabecera) cargaban
el original sin sourceSize y con cache:false, una copia por instancia.

- readAvatarImage: el lector recorta el cuadrado central y escala a 1024
  px (JPEG decodifica a escala DCT reducida). Prueba con un JPEG de
  4000x3000: 1024x1024, 4 MB en vez de 45 MB, mismo recorte centrado.
- Decodificar, recortar y codificar corre en QThreadPool (QtCore, sin
  dependencias nuevas). Guardado local, subida a Storage y senales siguen
  en el hilo GUI (finishAvatarUpdate). Si la cuenta cambia mientras se
  procesa, el resultado se descarta. Un solo trabajo a la vez.
- CircularAvatar: sourceSize = tamano mostrado x DPR x imageScale. En Qt
  6.9.3 con PreserveAspectCrop el lector cubre el recuadro (267x200 para
  un recuadro de 200x200 con un JPEG 4:3), asi que el recorte queda nitido.

Validacion: g++ -fsyntax-only (escritorio y Android con stubs) sin
errores; qmlcachegen compila CircularAvatar.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01AaquLFZhVoHgtnU5giZqcX

Archivos: `authsession.cpp`, `authsession.h`, `qml/Mobile/components/CircularAvatar.qml`.

### `a8ea406822` — perf(glass): capturas del vidrio a menor resolucion donde no se nota

Hallazgos calicata-glass-memoria (confirmado) y dock-glass-capturas-vivas
(parcial): cada LiquidGlassSurface captura su fondo en un FBO a la
resolucion fisica completa (sourceRect x DPR). En la ficha de Calicatas
hay 30-60 controles de vidrio por etapa: 15-40 MB de GPU a DPR 2.6-3 y
decenas de pases al abrir una etapa o volver de la camara. El Dock hace
3-5 capturas vivas por frame al hacer scroll bajo el.

- LiquidGlassSurface.captureScale (por defecto 1.0, sin cambios): fija
  ShaderEffectSource.textureSize = sourceRect x DPR x captureScale. En Qt
  6.9.3 un textureSize explicito se usa como pixeles fisicos (verificado
  en qquickshadereffectsource.cpp de v6.9.3), por eso se aplica el DPR.
  liquidglass.frag trabaja en espacio de item (pxToUv), asi que la
  geometria no cambia; solo se suaviza un fondo que el frost ya desenfoca.
- Calicatas: 0.5 en superficies primarias y 0.33 en controles. Sus fondos
  son ambientes opacos sin texto: 4-9x menos memoria por control.
- Dock: 0.5 solo con el material de bajo coste (perfil Ahorro, memoria
  baja o Earth); en el resto conserva la resolucion completa porque
  refracta texto de la pagina.

Validacion: qmlcachegen 6.9.3 compila los tres archivos. Arnes Qt 6.9.3
con el LiquidGlassSurface.qml real a DPR 2: captura completa por defecto
(textureSize vacio = 224x124 px) y 112x62 px con captureScale 0.5.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01AaquLFZhVoHgtnU5giZqcX

Archivos: `qml/Mobile/flowcore/GlobalContextDock.qml`, `qml/Mobile/flowcore/LiquidGlassSurface.qml`, `qml/Mobile/pages/CalicataLiquidGlass.qml`.

### `7b27781e3b` — perf(icons): rasterizar los iconos SVG al DPR real del telefono

Hallazgo flowicon-layer-por-icono (parcial): FlowIcon rasterizaba con
rasterScale 2.0 fijo. En Qt 6.9.3 QQuickImageBase solo multiplica
sourceSize por el DPR si QQuickPixmap::isScalableImageFormat(url) es
verdadero (image: o ruta terminada en svg/svgz/pdf; verificado en
qquickpixmapcache.cpp v6.9.3). Los SVG data: de IconCatalog terminan en
"</svg>" codificado, asi que no lo son: a DPR 2.75-4 (la mayoria de
FHD+/QHD) los iconos salian borrosos y a DPR 1.5-2 sobremuestreados.

- rasterScale = DPR real para fuentes que Qt no escala; 1.0 para las que
  si (image:, .svg, .svgz, .pdf), que ya reciben el DPR de Qt.
- mipmap solo si se rasteriza por encima del tamano fisico.
- Se conserva el MultiEffect de tinte (cambiarlo exige comparar capturas
  en claro/oscuro; queda para otra fase).

Validacion: arnes Qt 6.9.3 con el FlowIcon.qml real: icono 24 dp ->
sourceSize 36x36 a DPR 1.5 y 84x84 a DPR 3.5 (antes 48x48 en ambos),
estado Ready; un .svg de archivo queda en rasterScale 1. qmlcachegen OK.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01AaquLFZhVoHgtnU5giZqcX

Archivos: `qml/Mobile/components/FlowIcon.qml`.

### `a245800b91` — perf(glass): no crear el pipeline de blur desactivado de FlowGlassSurface

Hallazgo glass-surface-layer-sombra (parcial): realBlurActive es la
constante false (las capturas de escena son inestables con la
TextureView de Flutter en el A12), pero cada FlowGlassSurface creaba igual
una mascara con layer, un ShaderEffectSource y tres MultiEffect. No
cuestan por frame (invisibles), pero si tiempo de creacion y memoria en
cada instancia (Buscador, Perfil, Documentos y demas).

Ahora la mascara, la captura y el blur viven en un Loader con
active: root.realBlurActive, y los dos pases de dispersion en otro que
depende del primero. Mismo orden de apilado; si algun dia se reactiva el
blur, el comportamiento es el de antes.

No se cambia la sombra MultiEffect del panel del Buscador: anima opacity,
scale y un Translate propio, y una sombra hermana se desincronizaria; se
deja para una fase con prueba visual en dispositivo.

Validacion: qmlcachegen 6.9.3 compila. Arnes Qt 6.9.3 con el archivo real:
11 items por superficie con el blur desactivado y una variante con
realBlurActive true crea el pipeline completo (38 items) sin errores de
referencia.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01AaquLFZhVoHgtnU5giZqcX

Archivos: `qml/Mobile/flowcore/FlowGlassSurface.qml`.

### `2055694be1` — merge: integrar origin/main (herramientas de release delta) en la rama de optimizacion

Trae .github/workflows/release-delta.yml y .github/scripts/ para que la
punta de esta rama pueda empaquetarse con el mismo flujo de Release DELTA.
Sin conflictos: main solo cambio archivos de .github.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01AaquLFZhVoHgtnU5giZqcX

Sin cambios directos (merge).

### `32a4ad3cb1` — perf(memoria): no decodificar el fondo topografico invisible

Hallazgo imagenes-densidad-sourcesize, parte (b) (confirmada):
bg_topographic_lines.svg declara 1080x2400 y se cargaba sin sourceSize
en tres Image de Main.qml, una de ellas en profileOverlayV18 (se crea al
arrancar). opacity 0 / visible false no evitan la decodificacion: unos
10.4 MB RGBA residentes por una decoracion del tema Glass, y liquidGlass
es hoy la constante false.

Ahora la fuente solo se asigna con liquidGlass, y si se reactiva el tema
se decodifica asincrona y al tamano del item.

Descartado de este hallazgo: elegir el fondo de Auth por DPR. En Android
Auth es la superficie Flutter (opaca) y el fondo QML no se ve; subir a
1080x2400 aumentaria la RAM sin beneficio visible.

Validacion: qmlcachegen 6.9.3 compila Main.qml.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01AaquLFZhVoHgtnU5giZqcX

Archivos: `qml/Mobile/Main.qml`.

### `5c2fd38d1f` — perf(arranque): iniciar la carga de Flutter en segundo plano desde onCreate

Hallazgos flutter-init-sincrona-hilo-ui y arranque-frio-y-peso-binario
(punto 3): la primera vez que se mostraba Auth/Home, entrypoint() llamaba
a startInitialization y ensureInitializationComplete seguidos en el hilo
UI de Android, asi que la carga de libflutter/libapp ocurria entera en
ese momento, retrasando toques y frames. El log anunciaba un "prewarm"
que no existia.

Ahora onCreate llama a FlutterLoader.startInitialization: en el
embedding exacto (1.0.0-5a2a6a42cce6, verificado con javap) solo
comprueba el hilo, lee ApplicationInfo, inicia el VsyncWaiter y envia
la carga pesada al ejecutor propio de Flutter. La carga se solapa con el
arranque de Qt (carga de Main.qml) y entrypoint() solo espera lo que
falte. Es idempotente; si falla, se registra y entrypoint() sigue como
antes. Auth/Home es siempre la primera superficie, asi que no se carga
nada que no se fuera a usar.

Validacion: javac contra android-all API 35 + flutter_embedding exacto:
sin errores nuevos.
Pendiente en dispositivo: INGE_STARTUP AUTH_READY/HOME_READY antes y
despues en un equipo de 4 nucleos.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01AaquLFZhVoHgtnU5giZqcX

Archivos: `android/src/com/ingema/ingeplus/InGeQtActivity.java`.

### `4ce62a598a` — fix(texto): una sola escala de texto, A-/A+ por la fuente de Android

Hallazgo escala-texto-sistema-y-usuario (Fase C, ANEXO_42).

Causa raiz: habia dos escalas de texto que no se hablaban. Main.fs()
solo aplicaba el ajuste A-/A+ de la app (fontScale) a los textos de
Main.qml, y FlowAccessibility.textScale, que usan FlowText, FlowField y
FlowIconButton mediante scaledTextSize(), nadie lo enlazaba y valia
siempre 1.0. GraphicsCore ya publica systemFontScale
(Configuration.fontScale, en vivo) e InGeCoreFlow lo expone, pero ningun
QML lo consumia: con la fuente de Android al 130 % el Home de Flutter se
veia grande y el QML no cambiaba, y el A+ de la app no llegaba a los
componentes de InGeCoreFlow.

Cambio:
- Main.qml: readonly property effectiveTextScale =
  clamp(fontScale * InGeCoreFlow.systemFontScale, 0.85, 1.30).
- fs(n) usa effectiveTextScale y conserva su minimo de 9 px (fs(8) y
  fs(9) estan en filas estrechas; subirlo a 10 cambiaria el tamaño a
  escala 1.0).
- Binding de InGeCoreFlow.accessibility.textScale a effectiveTextScale,
  junto a los demas Bindings de InGeCoreFlow.
- El tope 1.30 es el mismo maximo que A+ ya permitia, asi que fs() nunca
  supera los tamaños que Main.qml ya soportaba; con la fuente de Samsung
  al 115-130 % o la no lineal de Android 14+ al 200 % el texto se queda
  en 1.30. Solo fontScale se sigue persistiendo en lastFontScale; la
  escala del sistema no se guarda ni se escribe en el log.
- Calicatas (dp()/__sp()) y Documentos no se tocan en este commit.

Validacion (sin kit Qt Android en este entorno):
- ...

Archivos: `qml/Mobile/Main.qml`, `qml/Mobile/flowcore/FlowAccessibility.qml`.

## Cierre Fase D

- `CMakeLists.txt`: QRC móvil separado y sin enlace QtLocation para Mobile. Desktop retiene QtLocation y el QRC original.
- `resources_mobile_brand.qrc`: tres aliases indispensables de logos y avatar.
- `qml/Mobile/Main.qml`: se elimina un import QtLocation inactivo.

Consulta `ESTADO_HALLAZGOS.md`, `REPORTE_PRUEBAS.md` y `CONFLICTOS_CESIUM.md`.

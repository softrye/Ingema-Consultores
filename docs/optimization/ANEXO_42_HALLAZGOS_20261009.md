# InGe+ Android: auditoría de optimización por tipo de móvil (anexo completo)

Análisis de solo lectura sobre la rama actual. 5 auditores por área y 1 verificador adversarial por área. El verificador abrió cada archivo citado e intentó refutar cada hallazgo. «Impacto» es el valor re-calificado por el verificador. Cuando el verificador corrigió la propuesta, se muestra **su** versión como «Cambio recomendado».

Nada de esto está compilado ni probado en un dispositivo. Cada cambio necesita build arm64-v8a, instalación, logcat y regresión según AGENTS.md.


## Pantallas, escala y texto


### La ficha Calicatas reduce el texto a 9 px y los botones a 40 dp en telefonos de 360 dp

- **Veredicto:** confirmado · **Impacto:** alto · **Esfuerzo:** bajo · id `minimos-texto-tactil-360dp`
- **Archivos:** `qml/Mobile/pages/CalicataFormPage.qml:695-698`, `qml/Mobile/pages/CalicataFormPage.qml:1815-1820`, `qml/Mobile/pages/CalicataFormPage.qml:1844`, `qml/Mobile/pages/CalicataFormPage.qml:3423`, `qml/Mobile/flowcore/FlowMetrics.qml:4`, `qml/Mobile/flowcore/FlowAccessibility.qml:8-17`, `flutter/inge_earth/lib/home_final.dart:49-51`

**Problema.** En telefono, uiScale = clamp(ladoMenor/430, 0.82, 1.00): solo llega a 1.0 desde 430 dp, asi que encoge la ficha en casi todos los telefonos. En 360 dp (gama baja Android 9-12 tipo Galaxy A0x, Moto E o Redmi, y cualquier movil con 'Tamaño de pantalla' grande) vale 0.837: dp(11) da 9 px en 44 etiquetas, dp(10) da 8 px, hBtn queda en 39 dp y touchMinTarget en 40 dp, por debajo de los 48 dp de Android. En 393 dp dp(11) da 10 px. La barra del editor que la contiene usa otra formula (0.95 en el mismo dispositivo), asi que en una misma pantalla conviven dos escalas. Flutter Home, en el mismo telefono, nunca baja de 1.0. En campo (sol directo, guantes) esto provoca toques erroneos y texto ilegible.

**Evidencia.**

```
CalicataFormPage.qml:696  ? Math.max(0.82, Math.min(1.00, Math.min(root.width, root.height) / 430.0))
CalicataFormPage.qml:698  function dp(v) { return Math.round(v * root.uiScale) }
CalicataFormPage.qml:3423  font.pixelSize: root.dp(11)   (44 apariciones de root.dp(11) y 2 de root.dp(10); 79 font.pixelSize: root.dp(...) en total)
CalicataFormPage.qml:1818  readonly property int hBtn: root.dp(root.isPhone ? 46 : 52)
CalicataFormPage.qml:1844  readonly property int touchMinTarget: root.dp(root.isPhone ? 48 : 54)   (definido y nunca usado; tampoco se usan hBtnCompact ni corteHdrBtn)
FlowMetrics.qml:4  readonly property int minimumTouchTarget: 48
FlowAccessibility.qml:15-17  function touchSize(requestedSize) { return Math.max(minimumTouchTarget, Number(requestedSize)) }
home_final.dart:49-51  // Phone controls never shrink with the viewport. ...  final scale = (math.min(width, 480) / 412).clamp(1.0, 1.08);
```

**Verificación.** Revisé CalicataFormPage.qml:695-698. En teléfono, uiScale = clamp(min/430, 0.82, 1.0). Con 360 dp sale 0.837: dp(11) da 9, dp(10) da 8, hBtn = round(46×0.837) = 39 y touchMinTarget = 40. Hay exactamente 44 `font.pixelSize: root.dp(11)` y 2 `root.dp(10)`, sobre 79 font.pixelSize con root.dp en total. touchMinTarget (1844), hBtnCompact (1819) y corteHdrBtn (1741) se definen y nunca se usan. FlowMetrics.qml:4 tiene minimumTouchTarget 48 y FlowAccessibility.qml:11-17 tiene scaledTextSize/touchSize. home_final.dart:49-51 usa un clamp(1.0, 1.08). El editor usa __armScale = max(0.95, 360/390), es decir 0.95, así que en el mismo teléfono conviven dos escalas. Matices: fsLabel, fsField y hField ya tienen suelos (12/14/44, líneas 1815-1817), por lo que los campos principales no bajan de ahí. hBtn solo lo usa StageButton (línea 3257), que se usa una vez, así que el botón de 39 dp tiene poco alcance real. El problema principal son los 44 textos a 9 px en el ancho más común de la gama baja. Lo mantengo en alto porque es la pantalla de trabajo principal.

**Corrección de evidencia.** root.dp(11) aparece 47 veces en total y 44 de ellas como font.pixelSize. hBtn solo se usa en CalicataFormPage.qml:3257 (component StageButton). fsLabel, fsField y hField ya tienen piso: `Math.max(12, root.dp(...))`, `Math.max(14, ...)` y `Math.max(44, ...)`.

**Cambio recomendado.** Cambio más seguro que llevar todo el layout a 1.0 de golpe (eso agranda un 20 % todas las columnas fijas a 360 dp): (1) subir solo el suelo de uiScale en teléfono a unos 0.92, o usar width/412 con clamp(0.92, 1.08); (2) añadir en CalicataFormPage un helper `function sp(n) { return Math.max(12, root.dp(n)) }` y migrar los 46 font.pixelSize de root.dp(10) y root.dp(11) a sp(n), dejando 11 solo para captions; (3) pasar los controles táctiles por `root.flow.accessibility.touchSize(root.dp(n))` y borrar los tokens muertos (touchMinTarget, hBtnCompact, corteHdrBtn). No cambiar el suelo global de FlowAccessibility.scaledTextSize (10 a 12) en este paso, porque afecta a todos los FlowText, FlowField y FlowIconButton. Si se quiere, hacerlo en una fase propia.

**Riesgo y pruebas.** La ficha sera algo mas alta (mas scroll) y las columnas de ancho fijo (wDesc 260, labelW 92, wClasi 110...) crecen hasta un 20 % en 360 dp: verificar que la tabla de cortes conserve el scroll horizontal y que nada se recorte. Probar en emulador de 360x640 (Android 9) y 360x800, y en 412 dp. La exportacion Excel/PDF (C++) no deberia cambiar, pero hay que exportar una ficha de prueba.


### Unificar escala y breakpoints en InGeCoreFlow.metrics y eliminar las copias por pagina (6 de ellas en paginas muertas)

- **Veredicto:** parcial · **Impacto:** medio · **Esfuerzo:** medio · id `fuente-unica-escala-flowmetrics`
- **Archivos:** `qml/Mobile/pages/CalicatasEditorPage.qml:26-39`, `qml/Mobile/pages/CalicataFormPage.qml:693-698`, `qml/Mobile/pages/CalicataReview.qml:37-51`, `qml/Mobile/pages/CalicataPhotoEditor.qml:128`, `qml/Mobile/pages/LoginPage.qml:7-20`, `qml/Mobile/pages/LoginPageForm.qml:18-31`, `qml/Mobile/pages/RegisterPage.qml:7-20`, `qml/Mobile/pages/RegisterPageForm.qml:18-31`, `qml/Mobile/pages/HomePage.qml:10-24`, `qml/Mobile/pages/HomePageContent.qml:18-31`, `qml/Mobile/flowcore/FlowMetrics.qml:3-19`, `qml/Mobile/flowcore/InGeCoreFlow.qml:23`, `qml/Mobile/Main.qml:2037-2041`, `qml/Mobile/Main.qml:4857`, `qml/Mobile/Main.qml:5199`, `qml/Mobile/Main.qml:5234`, `qml/Mobile/Main.qml:5315`, `CMakeLists.txt:552-671`, `main_mobile.cpp:205-207`

**Problema.** En el arbol vivo hay tres sistemas de escala distintos: (a) __armScale en CalicatasEditorPage, con base 390; (b) uiScale/dp en CalicataFormPage, con base 430, heredado por CalicataReview (scaleFactor) y CalicataPhotoEditor; (c) ninguno: NothingDocumentsRoot, GlobalContextDock y GlobalSearchOverlay usan px literales. Flutter Home aplica un cuarto (clamp 1.0-1.08 y ancho maximo 480). El mismo telefono muestra densidades distintas segun la pantalla, y cada ajuste para tablet o plegable hay que repetirlo en cada archivo. Las otras 6 copias de __armScale/__dp viven en paginas legadas que ya no se cargan (Login y Home reales son Flutter: Main.qml:4080 'Android uses Flutter'), pero se siguen compilando con qmlcachegen y empaquetando, en contra de la regla 3 (una sola implementacion activa por pagina). FlowMetrics.pageMaximumWidth existe y nadie lo usa: en tablets el contenido se estira a todo el ancho o se escala hasta 1.32 en lugar de limitar el ancho.

**Evidencia.**

```
CalicatasEditorPage.qml:32-34  readonly property real __armScale: __armPhone ? Math.max(0.95, Math.min(1.16, __armMinSide / 390.0)) : Math.max(1.05, Math.min(1.32, __armMinSide / 720.0))
CalicataFormPage.qml:695-697  readonly property real uiScale: root.isPhone ? Math.max(0.82, Math.min(1.00, Math.min(root.width, root.height) / 430.0)) : Math.max(0.92, Math.min(1.12, Math.min(root.width, root.height) / 760.0))
CalicataReview.qml:51  function dp(v) { return Math.round(v * review.scaleFactor) }
CalicataPhotoEditor.qml:128  function dp(v) { return form ? form.dp(v) : v }
LoginPageForm.qml:30 / RegisterPageForm.qml:30 / HomePageContent.qml:30 / HomePage.qml:23 / LoginPage.qml:19 / RegisterPage.qml:19  function __dp(v) { return Math.round(v * __armScale) }
FlowMetrics.qml:14  readonly property int pageMaximumWidth: 720   (sin ningun consumidor en qml/Mobile)
InGeCoreFlow.qml:23  readonly property FlowMetrics metrics: FlowMetrics {}
Main.qml:2037-2040  Binding { target: Mobile.InGeCoreFlow; property: "imeViewportHeight"; value: app.height }
Main.qml solo instancia Pages.HomePagePhase1 (4857), Pages.CalicatasEditorPage (5199), Pages.MapNativePage (5234) y NothingFiles.NothingDocumentsRoot (5315); ningun archivo vivo instancia AppShell, HeaderBar, BottomNav, HomePage, LoginPage, RegisterPage, MapPage, ProfilePage, MapWorkspacePage ni Phase54CalicataOverview, pero todos estan en MOBILE_QML_FILES.
```

**Verificación.** La parte central es correcta: en el árbol vivo hay al menos tres sistemas de escala. Son __armScale con base 390 (CalicatasEditorPage.qml:32-34); uiScale con base 430 (CalicataFormPage.qml:695-698), heredado por CalicataReview (scaleFactor: root.uiScale en 6114/12657/13091) y por PhotoEditor (línea 128); y px literales en Documents. FlowMetrics.pageMaximumWidth (línea 14) no tiene ningún consumidor. InGeCoreFlow se registra una sola vez con qmlRegisterSingletonType (main_mobile.cpp:205-207) y metrics es hijo suyo (InGeCoreFlow.qml:23), así que ampliar FlowMetrics no añade registros. Encontré dos errores. (a) HomePagePhase1 tampoco se instancia: solo existe dentro de `Component { id: homePhase1Page }` (Main.qml:4855) y ese id no se referencia en ninguna parte, porque el Loader de páginas (4649-4655) usa homePage. (b) El borrado propuesto rompe el build. Las páginas legadas también están en resources.qrc:74-86, y resources.qrc se compila tanto en AppCalicatasMobile (CMakeLists.txt:229) como en el target desktop (CMakeLists.txt:109). Si se borran del disco y solo se quitan de MOBILE_QML_FILES, rcc falla. Además, resources.qrc empaqueta otra vez Main.qml y las páginas de Calicatas (líneas 73, 90-91) fuera del módulo, en contra del comentario V35.1 de CMakeLists.txt:894-899. Por último, borrar páginas muertas no cambia el comportamiento en ningún teléfono, solo el tamaño del APK y el tiempo de build. Debe ir en un commit o fase aparte de la unificación de escala.

**Corrección de evidencia.** Main.qml:4855-4857 `Component { id: homePhase1Page  Pages.HomePagePhase1 {` es código muerto (homePhase1Page no tiene referencias). resources.qrc:73-86 lista Main.qml, LoginPage, RegisterPage, LoginPageForm, RegisterPageForm, HomePage, HomePageContent, MapPage, ProfilePage, MapPageContent, ProfilePageContent, AppShell, HeaderBar y BottomNav, y resources.qrc:90-91 lista CalicatasEditorPage y CalicataFormPage. resources.qrc está en MOBILE_SOURCES (CMakeLists.txt:229) y en PROJECT_SOURCES de desktop (CMakeLists.txt:109). resources_mobile_raw.qrc también los lista, pero no está enlazado.

**Cambio recomendado.** Fase A (layout): ampliar FlowMetrics con viewportWidth/viewportHeight (Binding desde Main.qml), sizeClass por ancho, uiScale, contentMaxWidth = pageMaximumWidth en clases media y expandida, y dp() y touch(). Convertir __armScale/__dp/__sp de CalicatasEditorPage y uiScale/dp de CalicataFormPage en delegados de una línea. Comparar capturas en 360, 393, 412, 600, 800 y 1280 dp. Fase B (alineación, commit separado): quitar AppShell, HeaderBar, BottomNav, HomePage, HomePageContent, HomePagePhase1 (y el Component homePhase1Page de Main.qml), LoginPage, LoginPageForm, RegisterPage, RegisterPageForm, MapPage, MapPageContent, ProfilePage, ProfilePageContent, MapWorkspacePage y Phase54CalicataOverview, a la vez de MOBILE_QML_FILES y de resources.qrc (y de resources_mobile_raw.qrc o archivar ese qrc). Retirar también de resources.qrc las copias duplicadas de Main.qml y de las páginas de Calicatas si el desktop no las carga por :/qml/Mobile. Después: CMake, build Android y desktop, y grep de referencias.

**Riesgo y pruebas.** Es un cambio visual en todo Calicatas: comparar capturas antes y despues en 360, 393, 412, 600, 800 y 1280 dp, plegable y landscape. Al borrar las paginas legadas: correr CMake, revisar que qmlcachegen y el qmldir generado no las sigan esperando y que el kit desktop de Qt Creator (que carga el mismo Main.qml) arranque. No toca Login, Supabase ni AuthSession reales, que viven en Flutter y C++.


### El tamaño de fuente (del usuario y de Android) solo llega a Main.qml; FlowAccessibility.textScale nunca se enlaza

- **Veredicto:** confirmado · **Impacto:** medio · **Esfuerzo:** medio · id `escala-texto-sistema-y-usuario`
- **Archivos:** `qml/Mobile/Main.qml:2141`, `qml/Mobile/Main.qml:2241`, `qml/Mobile/Main.qml:3927-3929`, `qml/Mobile/flowcore/FlowAccessibility.qml:7-13`, `qml/Mobile/flowcore/FlowText.qml:16`, `qml/Mobile/flowcore/InGeCoreFlow.qml:30`, `qml/Mobile/pages/CalicataFormPage.qml:3423`, `qml/Mobile/documents/NothingDocumentsRoot.qml:494`, `android/src/com/ingema/ingeplus/InGeQtActivity.java:895-905`, `android/AndroidManifest.xml:97`, `flutter/inge_earth/lib/home_final.dart:52`

**Problema.** Hay tres caminos de texto que no se hablan entre si: (1) Main.fs(), que aplica el ajuste A-/A+ de la app (0.85-1.30), pero solo a los 97 textos de Main.qml; (2) FlowAccessibility.textScale, pensado para esto y usado por FlowText/FlowField/FlowIconButton, que vale siempre 1.0 porque nadie lo enlaza; (3) Calicatas (79 root.dp + 38 __sp) y Documentos (23 literales), que ignoran ambos. Ademas, ningun punto de Java, C++ ni QML lee Configuration.fontScale. Con fontScale en configChanges la Activity no se recrea, y onConfigurationChanged solo escribe en el log. Flutter Home si sigue el tamaño de fuente del sistema. En un telefono con fuente al 130 % (o hasta 200 % en el escalado no lineal de Android 14+), Home se ve grande y Calicatas y Documentos pequeños; el A+ de la app no llega a la ficha. Hay 604 font.pixelSize y 0 pointSize. No he verificado si Qt 6.9.3 aplica scaledDensity a pixelSize en Android (normalmente no): hay que medirlo en un dispositivo.

**Evidencia.**

```
Main.qml:2141  property real fontScale: 1.0
Main.qml:2241  function fs(n) { return Math.max(9, Math.round(n * fontScale)) }   (97 usos, solo en Main.qml)
Main.qml:3927  SecondaryButton { width: 76; label: "A-"; onClicked: fontScale = Math.max(0.85, fontScale - 0.05) }
FlowAccessibility.qml:7  property real textScale: 1.0
FlowAccessibility.qml:11-13  function scaledTextSize(baseSize) { return Math.max(10, Math.round(Number(baseSize) * textScale)) }
FlowText.qml:16  font.pixelSize: flow.accessibility.scaledTextSize(   (tambien FlowField, FlowIconButton, HomePagePhase1)
(grep 'accessibility' en Main.qml: 0 resultados; ningun Binding a textScale)
CalicataFormPage.qml:3423  font.pixelSize: root.dp(11)   (79 fuentes via root.dp; CalicatasEditorPage: 38 via root.__sp)
NothingDocumentsRoot.qml:494  font.pixelSize: 13   (23 literales)
InGeQtActivity.java:896-904  public void onConfigurationChanged(...) { ... android.util.Log.i("InGeLifecycle", "INGE_ACTIVITY_CONFIG_CHANGE=" + diff ...); super.onConfigurationChanged(newConfig); }
AndroidManifest.xml:97  android:configChanges="...|fontScale|...|density"
home_final.dart:52  final textScale = MediaQuery.textScalerOf(context).scale(12) / 12;
```

**Verificación.** Lo verifiqué. Main.qml:2141 tiene `property real fontScale: 1.0` y Main.qml:2241 tiene `function fs(n)`. A-/A+ están en 3927-3929, el valor se persiste en appSettingsV41.lastFontScale (1726, 2268, 3750) y hay un toggle en Ajustes (5447-5448). FlowAccessibility.textScale (línea 7) no se enlaza en ningún sitio: grep 'accessibility' en Main.qml da 0 resultados y grep textScale fuera de FlowAccessibility tampoco devuelve nada. FlowText.qml:16 usa scaledTextSize. Calicatas usa 79 root.dp y 38 root.__sp, y NothingDocumentsRoot tiene 23 font.pixelSize literales (línea 494: 13). En total hay 604 font.pixelSize y 0 pointSize. onConfigurationChanged (InGeQtActivity.java:895-905) solo escribe en el log, y no hay ninguna lectura de fontScale ni de scaledDensity en Java, C++ ni QML. Qt no aplica fontScale a pixelSize. Flutter Home sí lo sigue (home_final.dart:52). Conclusión: el ajuste propio de la app no llega a la ficha ni a Documentos, y el tamaño de letra del sistema no llega a ningún QML. Es un problema de accesibilidad real, aunque no de rendimiento por gama, así que lo dejo en impacto medio.

**Corrección de evidencia.** fs( aparece en 103 líneas de Main.qml (unos 102 usos más la definición), no 97. Hay un toggle extra de fontScale en Main.qml:2295-2299 y 5447-5448 que hay que mantener coherente.

**Cambio recomendado.** (1) Hacer el Binding con un clamp: `Binding { target: Mobile.InGeCoreFlow.accessibility; property: "textScale"; value: Math.max(0.85, Math.min(1.5, app.fontScale * app.systemFontScale)) }` y redefinir fs(n) como `inGeCoreFlow.accessibility.scaledTextSize(n)`. Ojo: el suelo pasa de 9 a 10. (2) Leer Configuration.fontScale en C++ con QNativeInterface::QAndroidApplication::context() (en Qt 6.9 devuelve QtJniTypes::Context, que es un QJniObject): getResources().getConfiguration() y el campo float fontScale. Exponerlo como Q_PROPERTY con NOTIFY en el singleton GraphicsCore existente, sin registrar tipos nuevos. Como fontScale está en configChanges, el disparador más fiable es un native llamado desde onConfigurationChanged (el patrón JNI que ya existe); releer al volver a ApplicationActive sirve como respaldo. (3) Migrar CalicataFormPage, CalicatasEditorPage y NothingDocumentsRoot a scaledTextSize, limitando el factor efectivo a 1.3 en tablas densas y usando alturas con implicitHeight. No escribir valores de usuario en el log.

**Riesgo y pruebas.** El texto mas grande puede recortarse en filas de alto fijo (InputBox height: 54 en Main.qml:6040, etiquetas del dock). Probar con fuente del sistema al 85 %, 100 %, 130 % y 200 % (Android 14+) combinada con A-/A+. El cambio solo afecta al tamaño: el correo y su texto siguen intactos (regla 8). No imprimir valores sensibles en el log nuevo.


### QML solo usa el inset inferior; arriba, izquierda y derecha se ignoran pese al edge-to-edge forzado en Android 15+

- **Veredicto:** parcial · **Impacto:** medio · **Esfuerzo:** medio · id `safe-area-cuatro-lados`
- **Archivos:** `qml/Mobile/Main.qml:1705-1708`, `qml/Mobile/Main.qml:4452-4458`, `qml/Mobile/Main.qml:4628-4631`, `qml/Mobile/pages/CalicatasEditorPage.qml:4775`, `android/res/values/styles.xml:14-16`, `android/res/values-night/styles.xml`, `CMakeLists.txt:429`, `android/AndroidManifest.xml:102`, `flutter/inge_earth/lib/home_final.dart:44`, `android/assets/cesium/ui/inge-earth-ui.css:3-6`

**Problema.** Flutter Home (SafeArea) y los WebView de Cesium e IA (env(safe-area-inset-*)) gestionan los cuatro lados; la UI QML solo gestiona el inferior. Con targetSdk 35, en Android 15/16 el edge-to-edge es obligatorio y statusBarColor/navigationBarColor (styles.xml) se ignoran. En Android 9-14 no lo es, asi que el resultado depende de la version y del OEM. Si Qt 6.9.3 extiende la ventana bajo las barras, la cabecera de Calicatas (topBar de alto 0, la pagina empieza en y=0) y accountHeaderV20 quedan bajo la barra de estado o el orificio de la camara. En landscape (screenOrientation=unspecified) el notch y la barra de 3 botones pasan a los laterales (margins.left/right) y el formulario y el dock quedan debajo. No he verificado en dispositivo como configura Qt 6.9.3 la ventana; la API SafeArea si existe en 6.9, porque el repo ya la usa (Main.qml:1708).

**Evidencia.**

```
Main.qml:1705-1708
// Qt 6.9 expone el inset real de barras/gestos mediante SafeArea.
readonly property real safeBottomInsetV49:
    Math.max(0.0, Qt69.SafeArea.margins.bottom)
(no hay ninguna lectura de SafeArea.margins.top/left/right en qml/Mobile)
Main.qml:4456-4458  anchors.top: parent.top
        height: visible ? 72 : 0      (accountHeaderV20)
Main.qml:4628-4631  id: pageViewport / anchors.fill: parent
CalicatasEditorPage.qml:4775  Item { id: topBar; anchors.top: parent.top; width: parent.width; height: 0 }
styles.xml:15-16  <item name="android:statusBarColor">#F8FAFD</item> <item name="android:navigationBarColor">#FFFFFF</item>
CMakeLists.txt:429  QT_ANDROID_TARGET_SDK_VERSION 35
InGeQtActivity.java: ningun WindowInsets / setOnApplyWindowInsetsListener (solo configureHomeViewInsets con topMargin = 0)
home_final.dart:44  body: SafeArea(   |   inge-earth-ui.css:3  --safe-top: env(safe-area-inset-top, 0px);
```

**Verificación.** La evidencia del código es correcta. La única lectura de SafeArea en qml/Mobile es Main.qml:1708 (margins.bottom). accountHeaderV20 se ancla a parent.top sin margen (4452-4458), pageViewport hace anchors.fill (4628-4631) y topBar de Calicatas tiene alto 0 (CalicatasEditorPage.qml:4775). styles.xml usa statusBarColor/navigationBarColor, targetSdk es 35 y en Java no hay WindowInsets, setDecorFitsSystemWindows ni layoutInDisplayCutoutMode. Main.qml no pone flags de ventana (ni Qt.ExpandedClientAreaHint) ni en QML ni en C++. FlowPage.qml tiene safeTopMargin, pero vale siempre 0. Lo que no pude comprobar, porque Qt no está disponible en el entorno, es si Qt 6.9.3 en Android extiende la ventana bajo la barra de estado sin ExpandedClientAreaHint, o si acolcha el layout raíz y SafeArea solo da 0. El propio hallazgo lo reconoce. El riesgo depende de esa conducta. Que el equipo usara un inset inferior real (V49) sugiere que en algún dispositivo la ventana sí es edge-to-edge, pero no está demostrado para el lado superior. Primero hay que medir y después aplicar márgenes, o habrá doble relleno.

**Corrección de evidencia.** FlowPage.qml:10/32/38/43 ya tiene `safeTopMargin` (con valor 0 y sin enlazar). Ni Main.qml ni main_mobile.cpp ponen flags de ventana ni ExpandedClientAreaHint.

**Cambio recomendado.** Paso 0, obligatorio: registrar al arrancar `Qt69.SafeArea.margins.top/left/right/bottom` y app.width/height en Android 12, 14, 15 y 16, con navegación por gestos y de 3 botones, en vertical y landscape. Si top > 0 (ventana edge-to-edge): publicar safeTop, safeLeft, safeRight y safeBottom en InGeCoreFlow.metrics con Binding (patrón imeViewportHeight), enlazar FlowPage.safeTopMargin, dar a topBar de Calicatas height = safeTop y a accountHeaderV20 un topMargin, poner márgenes laterales en pageViewport y centrar el dock en [safeLeft, width - safeRight]. Pintar la franja de estado desde QML. Si top = 0 en todas las versiones, limitarse a left/right en landscape. No usar windowOptOutEdgeToEdgeEnforcement.

**Riesgo y pruebas.** Riesgo de doble relleno o franjas vacias si Qt ya aplica los insets. Probar en Android 9, 12, 14, 15 y 16, con navegacion por gestos y de 3 botones, en vertical y landscape, en dispositivos con notch o punch-hole, y en al menos un Samsung (One UI) y un Xiaomi (HyperOS). Revisar que el dock y las aperturas nativas sobre Earth sigan alineados.


### El modo phone/tablet de Calicatas cambia al abrir el teclado o al rotar (tablets, plegables, landscape)

- **Veredicto:** confirmado · **Impacto:** medio · **Esfuerzo:** bajo · id `breakpoint-cambia-con-teclado`
- **Archivos:** `qml/Mobile/pages/CalicataFormPage.qml:693-698`, `qml/Mobile/pages/CalicatasEditorPage.qml:27-39`, `qml/Mobile/pages/CalicatasEditorPage.qml:5121-5134`, `android/AndroidManifest.xml:101`, `qml/Mobile/Main.qml:2037-2041`, `qml/Mobile/flowcore/InGeCoreFlow.qml:95-103`

**Problema.** Los dos breakpoints que estan activos (CalicatasEditorPage y CalicataFormPage, que se carga dentro de el) se calculan con Math.min(width, height) de la pagina. Con adjustResize la ventana se encoge al abrir el IME (el propio InGeCoreFlow lo documenta), asi que la altura entra en el calculo. Ejemplo en una tablet en landscape de 1280x800 dp: la pagina mide unos 730 dp de alto y con un teclado de 350 a 400 dp queda en unos 350 dp. Entonces min < 600, isPhone pasa a true y, mientras se escribe, cambian a la vez unos 40 tokens 'root.isPhone ? a : b' (corteHdrH, hCell, wDesc, labelW, fsField, hField...), uiScale baja de 0.96 a 0.82 y __armScale de 1.05 a 0.95. Una ficha de 13.293 lineas se vuelve a maquetar entera con el campo enfocado: salta el scroll, el campo puede salir de la vista y en tablets de gama baja hay tirones. Lo mismo pasa en plegables abiertos en vertical (unos 690x840 dp, de 840 a ~470 con teclado) y en telefonos en landscape (lado menor ~330, uiScale fijado a 0.82).

**Evidencia.**

```
CalicataFormPage.qml:693-697
    readonly property bool isPhone: root.width > 0 && Math.min(root.width, root.height) < 600
    readonly property bool isTablet: root.width > 0 && Math.min(root.width, root.height) >= 600
    readonly property real uiScale: root.isPhone
        ? Math.max(0.82, Math.min(1.00, Math.min(root.width, root.height) / 430.0))
        : Math.max(0.92, Math.min(1.12, Math.min(root.width, root.height) / 760.0))
CalicatasEditorPage.qml:29-34
    readonly property real __armMinSide: Math.min(__armWidth, __armHeight)
    readonly property bool __armPhone: __armMinSide < 600
    readonly property real __armScale: __armPhone ? Math.max(0.95, Math.min(1.16, __armMinSide / 390.0)) : Math.max(1.05, Math.min(1.32, __armMinSide / 720.0))
AndroidManifest.xml:101  android:windowSoftInputMode="adjustResize"
InGeCoreFlow.qml:97-98  // imeViewportHeight lo publica el unico ApplicationWindow real. Cuando adjustResize ya redujo la ventana, keyboardRectangle queda fuera de ese viewport
CalicatasEditorPage.qml:5121-5126  Loader { id: formLoader ... anchors.bottom: bottomBar.top  (el formulario sigue la altura de la ventana)
```

**Verificación.** Revisé las líneas citadas. CalicataFormPage.qml:693-697 y CalicatasEditorPage.qml:27-37 calculan isPhone, uiScale y __armScale con Math.min(width, height). El formulario se carga en un Loader anclado a bottomBar.top (CalicatasEditorPage.qml:5122-5127), y bottomBar es un Item de alto 0 pegado al fondo (línea 5203), así que su altura es la de la ventana. El manifest usa adjustResize (línea 101). Ninguna de las dos páginas tiene un guard que congele el breakpoint mientras el IME está visible: grep de imeVisible/inputMethod solo devuelve llamadas a hide() y commit(). Hay 41 líneas con isPhone/isTablet en el form y 7 con __armPhone/__armTablet en el editor. Los números del ejemplo cuadran: 730/760 = 0.96 pasa a 0.82, y __armScale baja de 1.05 a 0.95. Matiz: el cálculo de imeHeight en InGeCoreFlow.qml:106-115 funciona tanto si la ventana se encoge como si no. El encogimiento con adjustResize está garantizado en Android 9-14. En Android 15+ (targetSdk 35, edge-to-edge forzado) depende de cómo Qt 6.9.3 trate los insets del IME, y eso no está verificado. El problema es real, pero solo afecta a tablets y plegables en landscape o desplegados, no a la mayoría de teléfonos. Por eso bajo el impacto a medio.

**Corrección de evidencia.** El Loader está en CalicatasEditorPage.qml:5122 (5121 es el comentario) y bottomBar es `Item { id: bottomBar; anchors.bottom: parent.bottom; width: parent.width; height: 0 }` en la línea 5203. Todas las propiedades de FlowMetrics.qml son `readonly` y hoy no tiene viewportWidth ni viewportHeight.

**Cambio recomendado.** Mantener el enfoque: clasificar por ancho y usar una altura estable sin teclado. Detalles para que compile y no oscile: (1) añadir a FlowMetrics.qml `property real viewportWidth: 0` y `property real viewportHeight: 0`, no readonly. (2) En Main.qml, junto al Binding de imeViewportHeight: `Binding { target: Mobile.InGeCoreFlow.metrics; property: "viewportHeight"; value: app.height; when: !Mobile.InGeCoreFlow.imeVisible && !Qt.inputMethod.visible; restoreMode: Binding.RestoreNone }` (restoreMode y RestoreNone existen en Qt 6.9). (3) isPhone = width < 600 || metrics.viewportHeight < 480, con una histéresis de unos 24 dp para no alternar en anchos cercanos a 600 (split-screen). Probar también en Android 15/16 si la ventana se encoge o no con el IME.

**Riesgo y pruebas.** Algunas tablets pequeñas en vertical (600-839 dp) pasaran a modo tablet en ambas orientaciones; revisar que las tablas de cortes y el perfil (prfLayout.mode) quepan. Probar: tablet en landscape con teclado en Identidad, editor de estrato y Laboratorio; plegable plegando y desplegando con el teclado abierto; split-screen; telefono de 360 dp en vertical y landscape. Comprobar que ImeAwareFlickable sigue llevando el campo a la vista.


### El dock global tiene tamaño fijo y las paginas reservan su espacio con numeros magicos (90, dp(110))

- **Veredicto:** confirmado · **Impacto:** medio · **Esfuerzo:** bajo · id `dock-geometria-fija-y-holguras`
- **Archivos:** `qml/Mobile/flowcore/GlobalContextDock.qml:259-270`, `qml/Mobile/flowcore/GlobalContextDock.qml:295-302`, `qml/Mobile/flowcore/GlobalContextDock.qml:461-464`, `src/dock/DockContextController.cpp:19`, `qml/Mobile/documents/NothingDocumentsRoot.qml:772`, `qml/Mobile/documents/NothingDocumentsRoot.qml:803`, `qml/Mobile/pages/CalicataFormPage.qml:10127`, `qml/Mobile/Main.qml:4423-4437`

**Problema.** El grupo del dock mide 20 + n*46 + (n-1)*8 + 16 + 49 dp, sin adaptarse al ancho. Con las 5 acciones de Calicatas son 347 dp, y el controlador admite hasta 8 (509 dp). En telefonos con ancho logico de 320-360 dp ('Tamaño de pantalla' grande o gama baja), x = (width - groupWidth)/2 queda en 6 dp o se vuelve negativo, y el boton de IA o la ultima accion se salen de la pantalla. El espacio que dejan las paginas no sale del dock real: Documentos usa bottomMargin 90 y Calicatas root.dp(110), que en 360 dp se queda en 92 por el uiScale. Sin embargo, la banda real es 54 + 8 + safeBottom: con navegacion de 3 botones (48 dp, habitual en gama baja, Android 9-10 y muchos Samsung) son 110 dp, asi que la ultima fila o el boton del footer quedan debajo del cristal y no se pueden tocar. En landscape la barra de 3 botones va a un lateral (inset derecho) y el dock, centrado sobre todo el ancho, se le superpone.

**Evidencia.**

```
GlobalContextDock.qml:259-270  readonly property real mainHeight: 54 / slotSize: 46 / actionGap: 8 / sidePadding: 10 / coreSize: 49 / coreGap: 16 / bottomGap: 8
GlobalContextDock.qml:295-298  readonly property real mainWidth: sidePadding * 2 + Math.max(1, mainActions.length) * slotSize + Math.max(0, mainActions.length - 1) * actionGap
    readonly property real groupWidth: capsule.width + coreGap + coreSize
GlobalContextDock.qml:300-302  visualBandHeight: capsuleY + mainHeight + bottomGap + bottomSafeInset;  reservedHeight: shown ? visualBandHeight : 0
GlobalContextDock.qml:464  x: Math.round((root.width - root.groupWidth) / 2)
DockContextController.cpp:19  constexpr int kMaxActions = 8;
NothingDocumentsRoot.qml:772 y 803  bottomMargin: 90
CalicataFormPage.qml:10127  contentHeight: finalPageCol.implicitHeight + root.dp(110)
Main.qml:4423-4426  Binding { target: app.inGeCoreFlow; property: "glassMaterial"; value: globalContextDockV1 }
```

**Verificación.** GlobalContextDock.qml:259-270 usa geometría fija (mainHeight 54, slotSize 46, actionGap 8, sidePadding 10, coreSize 49, coreGap 16, bottomGap 8). mainWidth y groupWidth están en 295-298, reservedHeight en 302 y x = (width - groupWidth)/2 en 464. Calicatas publica como máximo 5 acciones: tabs, information, la acción de la etapa, previous y next o export (CalicatasEditorPage.qml:544-604). Eso da 20 + 5×46 + 4×8 + 16 + 49 = 347 dp. Con 360 dp quedan 6.5 dp por lado, y por debajo de unos 347 dp (Android Go de 320 dp, o 'Tamaño de pantalla' grande) el grupo se sale de la pantalla. kMaxActions = 8 está en DockContextController.cpp:19. El dock se superpone a pageViewport, y Documentos rellena el padre con bottomSafeInset 0 cuando el dock está visible (Main.qml:5330). Su ListView y su GridView reservan bottomMargin 90 (NothingDocumentsRoot.qml:772 y 803), y Calicatas reserva root.dp(110) (CalicataFormPage.qml:10127), que con 360 dp son 92. La banda real es 54 + 8 + bottomSafeInset (Main.qml:4437, safeBottomInsetV49). Con navegación de 3 botones en edge-to-edge (inset de unos 48 dp) son 110 dp y el final del contenido queda bajo el cristal. En Android ≤14 sin edge-to-edge el inset puede ser 0 y no hay solapamiento. ImeAwareFlickable no lee glassMaterial ni reservedHeight. Impacto medio confirmado.

**Corrección de evidencia.** Las acciones de Calicatas están en CalicatasEditorPage.qml:544-604. Con 360 dp el grupo cabe con 6.5 dp de margen; solo desborda por debajo de unos 347 dp. InGeCoreFlow.glassMaterial está declarado como `property Item glassMaterial: null` (InGeCoreFlow.qml:43): leer `.reservedHeight` funciona en tiempo de ejecución, pero qmllint no lo ve tipado.

**Cambio recomendado.** (1) Publicar en InGeCoreFlow una propiedad `dockReservedHeight` mediante un Binding en Main.qml (value: globalContextDockV1.reservedHeight) en lugar de leer glassMaterial.reservedHeight, y usarla en NothingDocumentsRoot.qml:772/803 y en CalicataFormPage.qml:10127, sumándole un margen. (2) Slots adaptables: con el mínimo de 44 no alcanza en 320 dp (20 + 5×44 + 32 + 16 + 49 = 337 > 320), así que el desborde a un hijo 'Más' (con el mecanismo children existente, empezando por las acciones de priority más alta) es obligatorio, no opcional. Centrar el grupo en [safeLeft, width - safeRight]. Reutilizar el Behavior existente y verificar syncNativeGeometry sobre Earth y Flutter.

**Riesgo y pruebas.** Las aperturas nativas (setNativeGeometry) tienen que coincidir con el dock sobre Earth (WebView) y Flutter Home: verificarlo con 'Tamaño de pantalla' al maximo, navegacion de 3 botones y por gestos, y en landscape. Probar el menu de pulsacion larga (children) en Calicatas etapa 5 (Exportar).


### Imagenes por densidad: el fondo se elige comparando dp con pixeles y un SVG de 1080x2400 se decodifica aunque es invisible

- **Veredicto:** parcial · **Impacto:** medio · **Esfuerzo:** bajo · id `imagenes-densidad-sourcesize`
- **Archivos:** `qml/Mobile/Main.qml:1585-1596`, `qml/Mobile/Main.qml:4045-4052`, `qml/Mobile/Main.qml:1061-1066`, `qml/Mobile/Main.qml:5059-5066`, `qml/Mobile/Main.qml:5349-5354`, `qml/Mobile/Main.qml:2125`, `qml/Mobile/pages/HomePagePhase1.qml:33-45`, `qml/Mobile/flowcore/FlowTheme.qml:19`, `qml/Mobile/assets_ui_v2/backgrounds/bg_topographic_lines.svg:1`

**Problema.** (a) width y height del ApplicationWindow son unidades logicas (dp): en cualquier telefono o tablet Math.max(width, height) esta entre 640 y 1400, siempre <= 1800. Por eso siempre se elige el PNG de 720x1600. Las variantes 1080x2400 (826 KB la clara, mas la oscura) se empaquetan y nunca se usan en Android, y en flagships QHD+ (1440x3200, DPR ~3.5) el fondo se estira unas 2 veces y se ve blando durante el bootstrap y las transiciones de auth. (b) bg_topographic_lines.svg declara 1080x2400. Sin sourceSize, Qt lo rasteriza al menos a su tamaño natural (~10 MB RGBA en RAM) y se carga en 4 sitios, aunque liquidGlass es constante false y por tanto opacity 0 o visible false. Ninguna de las dos cosas impide la decodificacion. En equipos de 2-3 GB es memoria gastada en una decoracion que nunca se ve, y en pantallas 720p son 2.8 veces mas pixeles de los necesarios.

**Evidencia.**

```
Main.qml:1585  readonly property bool authUseCompactBackgroundV40: Math.max(width, height) <= 1800
Main.qml:1593-1595  return authUseCompactBackgroundV40 ? "qrc:/ui/v2/backgrounds/bg_auth_forest_light_720x1600.png" : "qrc:/ui/v2/backgrounds/bg_auth_forest_light_1080x2400.png"
Main.qml:4045-4049  Image { id: authBackground; anchors.fill: parent; source: app.authBackgroundSourceV40(); fillMode: Image.PreserveAspectCrop   (sin sourceSize)
bg_topographic_lines.svg:1  <svg ... width="1080" height="2400" viewBox="0 0 1080 2400">
Main.qml:5349-5353  Image { anchors.fill: parent; source: "qrc:/ui/v2/backgrounds/bg_topographic_lines.svg"; fillMode: Image.PreserveAspectCrop; opacity: liquidGlass ? 0.34 : 0.0 }
Main.qml:2125  readonly property bool liquidGlass: false     FlowTheme.qml:19  readonly property bool isGlass: false
HomePagePhase1.qml:33-38  Image { anchors.fill: parent; visible: root.liquidGlass; source: "qrc:/ui/v2/backgrounds/bg_topographic_lines.svg" ... layer.enabled: true
```

**Verificación.** (b) Confirmado y es la parte valiosa. bg_topographic_lines.svg declara 1080x2400 (pesa 1.4 KB). liquidGlass es constante false (Main.qml:2125), y opacity 0 o visible false no impiden la carga. La instancia de Main.qml:1061 cuelga de profileOverlayV18, un Rectangle de nivel superior del ApplicationWindow (Main.qml:1043), así que se crea al arrancar y decodifica el SVG de forma síncrona (asynchronous es false por defecto) a 1080x2400, unos 10.4 MB RGBA que quedan residentes. Hay otras instancias en homePage (5059) y settingsSoonPage (5350); comparten la entrada de la caché de pixmaps, así que el coste es unos 10 MB una sola vez, no por instancia. HomePagePhase1 (33-45) es código muerto: el Component homePhase1Page no se usa. (a) La comparación de dp con píxeles es correcta: siempre se elige el PNG de 720x1600. Pero en Android authView abre la superficie Flutter de auth (onVisibleChanged → setFlutterAuthSurfaceV70, Main.qml:4031 y 618-640), cuyo AuthVideoBackground es opaco: ColoredBox IngemaBrand.deep más un póster (auth_video_background.dart, aprox. 150-158). El fondo QML de auth no se ve en Android. Cambiar a 1080x2400 en pantallas con DPR alto subiría la RAM de unos 4.6 MB a unos 10.4 MB por una imagen invisible, justo lo contrario de lo que conviene en gama baja. La mejora de nitidez solo aplica al kit desktop.

**Corrección de evidencia.** Las instancias del SVG vivas son 3 (Main.qml:1061 al arrancar, 5059 y 5350); la de HomePagePhase1.qml:33-45 nunca se instancia. authBackground (Main.qml:4045-4052) está dentro de authView, y en Android Flutter Auth la tapa por completo (auth_video_background.dart: ColoredBox más el póster ingema_auth_video_poster.jpg).

**Cambio recomendado.** (b) Mientras liquidGlass sea la constante false, usar `source: app.liquidGlass ? "qrc:/ui/v2/backgrounds/bg_topographic_lines.svg" : ""` en Main.qml:1061, 5059 y 5350, y si algún día se activa, añadir `sourceSize: Qt.size(width, height)` y `asynchronous: true`. (a) En Android no decodificar el fondo QML de auth: `source: Qt.platform.os === "android" ? "" : app.authBackgroundSourceV40()`. Si se quiere un respaldo hasta el primer frame de Flutter, usar el de 720x1600 con `asynchronous: true` y sourceSize limitado. La corrección con DPR (`Math.max(width, height) * Screen.devicePixelRatio`) aplicarla solo en desktop. En los logos (Main.qml:337, 1513, 4133), poner sourceSize = tamaño mostrado × DPR. Medir con dumpsys meminfo antes y después.

**Riesgo y pruebas.** Bajo. Comprobar la nitidez del fondo de auth en un dispositivo de 1440p y en uno de 720p, y medir RSS antes y despues con dumpsys meminfo. Si en el futuro se activa liquidGlass, el SVG se cargara bajo demanda, con un posible primer frame sin fondo.


### Telefonos en landscape: la orientacion es libre pero ningun QML esta preparado para una altura compacta

- **Veredicto:** confirmado · **Impacto:** medio · **Esfuerzo:** bajo · id `orientacion-telefono-sin-diseno`
- **Archivos:** `android/AndroidManifest.xml:97-104`, `android/src/com/ingema/ingeplus/InGeQtActivity.java:895-905`, `qml/Mobile/pages/CalicataFormPage.qml:695-697`, `qml/Mobile/flowcore/GlobalContextDock.qml:300-302`, `qml/Mobile/flowcore/GlobalContextDock.qml:259`

**Problema.** Si el auto-giro esta activo, un telefono en campo gira a landscape (unos 800x330 dp utiles) y nada se adapta: la ficha baja al minimo de uiScale (0.82, porque el lado menor es la altura), el dock fijo ocupa 62 dp o mas, y con el teclado abierto el area visible para un campo queda en unos 100-150 dp. No existe una clase de altura compacta en ningun QML. En tablets y plegables (sw >= 600) el landscape si tiene sentido.

**Evidencia.**

```
AndroidManifest.xml:102  android:screenOrientation="unspecified"
AndroidManifest.xml:104  android:resizeableActivity="true">
grep -rn "landscape|orientation|isPortrait|width > height" qml/Mobile -> solo Gradient.Horizontal / ListView.Horizontal (ninguna logica de orientacion)
CalicataFormPage.qml:696  ? Math.max(0.82, Math.min(1.00, Math.min(root.width, root.height) / 430.0))
GlobalContextDock.qml:300-301  readonly property real visualBandHeight: capsuleY + mainHeight + bottomGap + bottomSafeInset
InGeQtActivity.java:896-905  onConfigurationChanged solo registra el diff (no hay setRequestedOrientation en android/src)
```

**Verificación.** Lo verifiqué. AndroidManifest.xml:102 tiene screenOrientation="unspecified" y la línea 104 resizeableActivity="true". configChanges incluye orientation, screenSize y smallestScreenSize, así que la Activity no se recrea. grep de landscape/orientation/isPortrait/Screen.orientation/width > height en qml/Mobile no devuelve ninguna lógica de orientación. En android/src no hay setRequestedOrientation, SCREEN_ORIENTATION ni smallestScreenWidthDp. onConfigurationChanged (InGeQtActivity.java:895-905) solo escribe en el log. En un teléfono en landscape, el lado menor es la altura (unos 330-360 dp), lo que lleva uiScale a su mínimo de 0.82 (CalicataFormPage.qml:696), y el dock ocupa 62 dp o más (GlobalContextDock.qml:300-302). La opción A es compatible: setRequestedOrientation existe desde API 1, y con targetSdk 35 se respeta en teléfonos. Android 16 solo ignora estas restricciones en pantallas con sw ≥ 600 cuando se apunta a targetSdk 36, y la condición sw < 600 ya va en esa línea. Es una decisión de producto de esfuerzo bajo y con impacto medio.

**Cambio recomendado.** Opción A, con dos precisiones: llamar a setRequestedOrientation solo si el valor cambia, para evitar relanzar la configuración; y evaluarlo en onCreate y en onConfigurationChanged, que ya se invoca con smallestScreenSize al plegar o desplegar. En multi-ventana el sistema ignora la petición, lo cual es aceptable. Si Earth necesita landscape, liberar el bloqueo solo con pageIndex === 2 mediante el patrón JNI existente.

**Riesgo y pruebas.** Usuarios que giran el telefono para ver Earth o fotos: confirmar con producto. Probar plegar y desplegar (sw cambia y onConfigurationChanged debe reevaluar), split-screen, y que las superficies Flutter y Cesium se recompongan bien tras el bloqueo.


## GPU, efectos y refresco


### El tier/budget de InGePerformanceRuntime nunca llega a QML/C++ y todos los equipos arrancan en perfil 'high'

- **Veredicto:** parcial · **Impacto:** alto · **Esfuerzo:** medio · id `tier-no-llega-a-qml`
- **Archivos:** `android/src/com/ingema/ingeplus/InGePerformanceRuntime.java:148`, `android/src/com/ingema/ingeplus/InGePerformanceRuntime.java:286`, `android/src/com/ingema/ingeplus/InGeQtActivity.java:1562`, `src/core/InGeCoreContext.h:19`, `qml/Mobile/Main.qml:1881`, `qml/Mobile/Main.qml:2043`, `qml/Mobile/Main.qml:3743`, `qml/Mobile/Main.qml:3800`, `firstexperiencecontroller.cpp:60`, `qml/Mobile/flowcore/FlowAccessibility.qml:4`, `qml/Mobile/flowcore/InGeCoreFlow.qml:44`, `qml/Mobile/flowcore/InGeCoreFlow.qml:159`, `qml/Mobile/flowcore/GlobalContextDock.qml:271`

**Problema.** Java calcula DeviceTier (ULTRA_LOW..HIGH), ahorro de bateria y estado termico, pero el resultado solo se loguea y se usa para Cesium; ni InGeCoreFlow ni C++ lo reciben (grep de tier/budget/powerSave en .qml/.cpp sin consumidores). Peor: en una instalacion nueva lastPerformanceLevel es -1, se toma firstExperience.performanceLevel cuyo valor por defecto es 2, y como la Primera Experiencia esta dormida nadie lo elige: TODOS los moviles (2-3 GB con Mali-G52/Adreno 610 incluidos) quedan en performance.high (secondaryEffectsEnabled, reflectionsEnabled y shaderEffectsEnabled activos, performanceFactor 1.08 = animaciones 8% mas largas) y ese 2 queda persistido. Tampoco se respeta 'Quitar animaciones' de Android, el modo ahorro ni el estrangulamiento termico: en ahorro de bateria (CPU/GPU limitados por el OEM) la app sigue con todos los efectos. Ademas el Dock usa 400 ms fijos, sin pasar por flow.duration(), asi que ni motionLevel ni el perfil lo escalan.

**Evidencia.**

```
InGePerformanceRuntime.java:148-155 (unico consumidor del budget): Log.i("InGePerformance", "INGE_PERFORMANCE_BUDGET refreshHz=" + budget.sustainableRefreshHz ... + " animation=" + budget.animationBudget + " blur=" + budget.blurBudget ...);
InGeQtActivity.java:1562-1567 (unico uso del tier): public String getEarthPerformanceTier() { ... switch (runtime.deviceTier()) {
src/core/InGeCoreContext.h:19: DeviceTier deviceTier = DeviceTier::Unknown;   // solo se asigna en tests/inge-core
Main.qml:1881-1883: // Perfil equilibrado por defecto. El perfil "high" se reserva para equipos que lo seleccionen explícitamente ... property int flowPerformanceLevel: 1
Main.qml:3743-3746: var selectedPerformance = appSettingsV41.lastPerformanceLevel >= 0 ? appSettingsV41.lastPerformanceLevel : Number(firstExperience.performanceLevel)
firstexperiencecontroller.cpp:60: return qBound(0, s.value(kPerformance, 2).toInt(), 2);
Main.qml:2043-2050: Binding { target: Mobile.InGeCoreFlow.performance; property: "profile"; value: app.flowPerformanceLevel >= 2 ? Mobile.InGeCoreFlow.performance.high : ...
Main.qml:3800: readonly property bool shouldOpen: false // Dormant until final onboarding phase.
FlowAccessibility.qml:4: property bool reducedMotion: false   (ningun archivo lo escribe)
InGeCoreFlow.qml:159: property bool lowMemoryMode: false   (ningun archivo lo escribe)
GlobalContextDock.qml:271: readonly property int motionDuration: flow && flow.motionAllowed ? 400 : 0
```

**Verificación.** El nucleo se confirma. InGePerformanceRuntime solo expone tier y budget a Java: se loguean en las lineas 148-155, se usan para Earth en InGeQtActivity.java:1562-1580 y en el snapshot de diagnostico beta en la linea 336. En .qml/.cpp/.h no hay ningun consumidor: InGeCoreContext.deviceTier solo se asigna en tests/inge-core. En una instalacion nueva, Main.qml:1719 tiene lastPerformanceLevel -1, asi que en las lineas 3743-3746 se toma firstExperience.performanceLevel. Ese valor es 2 por defecto (firstexperiencecontroller.cpp:60) y el Loader de onboarding esta dormido (shouldOpen:false, Main.qml:3800). Por eso flowPerformanceLevel=2 y, por el Binding de la linea 2043, queda performance.high. onFlowPerformanceLevelChanged lo persiste (lineas 2277-2280), en contra del comentario de 1881-1883 que dice 'equilibrado por defecto'. Nadie escribe FlowAccessibility.reducedMotion ni InGeCoreFlow.lowMemoryMode. El Dock usa 400 ms fijos (GlobalContextDock.qml:271). Fallan algunos detalles. (a) secondaryEffectsEnabled y shaderEffectsEnabled tambien estan activos en balanced (FlowPerformance.qml:17-19). La diferencia real entre high y balanced es reflections, complexBlur, blurIntensity 0.72 frente a 0.38 y performanceFactor 1.08; solo safe apaga los efectos. (b) Solo FlowGlassSurface, FlowSurface, FlowButton, Main.qml y InGeCoreFlow leen el perfil. El vidrio del Dock y el de Calicatas lo ignoran, asi que conectar el tier por si solo apenas cambia la GPU si no se aplican tambien los hallazgos de vidrio. (c) classifyTier resta 2 puntos por powerSave y 2 por thermal (InGePerformanceRuntime.java:286-287). Si el nivel 'auto' derivado del tier se persiste, una primera ejecucion en ahorro de bateria deja el equipo en ahorro para siempre. (d) Las APIs propuestas son correctas para minSdk 28: ACTION_POWER_SAVE_MODE_CHANGED, addThermalStatusListener (API 29+), ValueAnimator.areAnimatorsEnabled (API 26+) y ContentObserver sobre ANIMATOR_DURATION_SCALE. No crean un segundo motor.

**Corrección de evidencia.** Ademas de Earth, el tier tambien se usa en InGeQtActivity.java:336 (device.put("performance_tier", ...), diagnostico beta), asi que no es 'el unico uso'. InGeEarthHostController.cpp:27 usa QJniObject::callStaticMethod<jboolean>; el patron para String seria callStaticObjectMethod<jstring>. FlowPerformance.qml:17-19: secondaryEffectsEnabled y shaderEffectsEnabled valen 'profile <= balanced' (activos tambien en balanced). La persistencia automatica esta en Main.qml:2277-2280 (onFlowPerformanceLevelChanged). InGePerformanceRuntime.initialize se llama despues de super.onCreate (InGeQtActivity.java:817-820).

**Cambio recomendado.** Mantener los pasos 1-3: puente JNI hacia GraphicsCore y propiedades derivadas en InGeCoreFlow, sin un motor nuevo. Proteger la llamada nativa desde Java con try/catch(UnsatisfiedLinkError) mientras libAppCalicatasMobile no este cargada. Cambios en el paso 4: (a) no persistir el nivel automatico. Guardar performanceLevelSource=auto|user y, con auto, recalcular el nivel en cada arranque. Calcularlo con un tier SIN las penalizaciones transitorias de powerSave/thermal (por ejemplo, un baseTier en Java) y usar systemConstrained solo como degradacion temporal en el Binding. Hacer que onFlowPerformanceLevelChanged solo escriba lastPerformanceLevel cuando el origen sea user (la accion de Main.qml:5473). (b) En instalaciones existentes no se puede distinguir un 'Alto' elegido por el usuario del 2 por defecto. Re-derivar solo si el tier es LOW o ULTRA_LOW, y dejar un log. (c) Mapear LOW/ULTRA_LOW a 0 (safe), porque balanced no apaga los efectos. Paso 5: el Dock usa 400 ms a proposito para imitar un resorte de .40 (GlobalContextDock.qml:273-276). Mejor 'flow && flow.motionAllowed ? Math.round(400 * flow.performance.animationIntensity) : 0' que flow.duration(400), que aplicaria 1.08 y 0.68. Para que el ahorro se note en GPU, este hallazgo debe ir junto con los de vidrio del Dock y de Calicatas, que consumen el perfil.

**Riesgo y pruebas.** Toca Main.qml (zona de Login/Home): limitarse a Bindings y al calculo del valor inicial; no tocar AuthSession ni Supabase. Antes de que GraphicsCore lea el snapshot, deviceTier debe valer "UNKNOWN" y mapear a 1 (balanced), nunca a 0. Probar: build debug y lanzar con 'adb shell am start -n <paquete>/com.ingema.ingeplus.InGeQtActivity --es inge.performance.override FORCE_CONSERVATIVE' y FORCE_MAX (InGePerformanceRuntime.java:337-350); 'adb shell settings put global low_power 1/0'; 'adb shell cmd thermalservice override-status 3' y 'reset'; 'adb shell settings put global animator_duration_scale 0'. Verificar en logcat INGE_ADAPTIVE_RUNTIME y un log nuevo del perfil aplicado, que el ajuste manual de Rendimiento sigue funcionando y que usuarios ya instalados con nivel 2 persistido como 'auto' pasan al nivel de su tier.


### La tasa de refresco pedida usa la del instante de onCreate e ignora budget.sustainableRefreshHz

- **Veredicto:** confirmado · **Impacto:** alto · **Esfuerzo:** bajo · id `refresh-ignora-budget`
- **Archivos:** `android/src/com/ingema/ingeplus/InGeQtActivity.java:950`, `android/src/com/ingema/ingeplus/InGeQtActivity.java:954`, `android/src/com/ingema/ingeplus/InGeQtActivity.java:958`, `android/src/com/ingema/ingeplus/InGeQtActivity.java:982`, `android/src/com/ingema/ingeplus/InGePerformanceRuntime.java:305`, `android/src/com/ingema/ingeplus/InGePerformanceRuntime.java:328`

**Problema.** El budget ya calcula una frecuencia sostenible y elegida entre los modos fisicos reales (chooseRefresh solo devuelve valores de supportedRefreshRates), pero la Activity pide display.getRefreshRate() del momento de onCreate. Consecuencias: (a) gama baja con panel de 90/120 Hz (Redmi/Galaxy A con Adreno 610 o Mali-G52/G57) que arranca en 120 Hz: Qt (render loop por vsync) y todas las animaciones QML corren a 120 Hz, el doble de trabajo de GPU por segundo, con tirones y calor, aunque el budget dice 60; (b) flagship que arranca con el panel en 60 Hz (modo adaptativo en reposo o ahorro activo) queda fijado a 60 Hz toda la sesion y se siente lento; (c) el valor no se recalcula si luego cambian el modo ahorro o el estado termico.

**Evidencia.**

```
InGeQtActivity.java:954-958:
  preferredRefreshRateHz = performanceRuntime == null
          ? 0.0f : performanceRuntime.capabilities().currentRefreshHz;
  ...
  params.preferredRefreshRate = preferredRefreshRateHz;
InGeQtActivity.java:982-984: surface.setFrameRate(preferredRefreshRateHz, android.view.Surface.FRAME_RATE_COMPATIBILITY_DEFAULT);
InGePerformanceRuntime.java:308-312:
  final float refreshCeiling = tier == DeviceTier.ULTRA_LOW || tier == DeviceTier.LOW ? 60.0f : (tier == DeviceTier.MEDIUM ? 90.0f : maxRefresh);
  final float sustainable = chooseRefresh(c.supportedRefreshRates, Math.min(maxRefresh, refreshCeiling), c.currentRefreshHz);
```

**Verificación.** El codigo coincide. InGeQtActivity.java:954-958 pide performanceRuntime.capabilities().currentRefreshHz, que es display.getRefreshRate() leido en detect() durante onCreate. Las lineas 982-984 aplican setFrameRate con ese mismo valor. budget.sustainableRefreshHz (InGePerformanceRuntime.java:305-312) no se usa en ningun sitio: budget solo se lee en el log. chooseRefresh (lineas 328-335) devuelve un valor de supportedRefreshRates, que son modos fisicos, salvo cuando la lista esta vacia. El comentario sobre '~40.9 Hz fraccionarios' ya no aplica porque budget es inmutable (solo se asigna en la linea 131). Qt 6.9 en Android renderiza sincronizado con vsync, asi que en un panel de 120 Hz la escena y las animaciones QML corren a 120 fps. En gama baja con panel de 90 o 120 Hz (equipos de 4 GB, que dan menos de 4 GiB y quedan en LOW) el budget fijaria 60 Hz. onWindowFocusChanged (lineas 1000-1004) vuelve a aplicar el mismo valor de onCreate, que nunca se recalcula. El cambio es de bajo esfuerzo y compatible con minSdk 28.

**Corrección de evidencia.** La lectura de capabilities.currentRefreshHz viene de detect(): display.getRefreshRate() en InGePerformanceRuntime.java:262. La reaplicacion con el mismo valor esta en InGeQtActivity.java:996-1004 (onWindowFocusChanged) y en la linea 2063.

**Cambio recomendado.** preferredDisplayModeId existe desde API 23, asi que se puede usar en todo el rango minSdk 28..35 sin limitarlo a API 30+. Elegir el Display.Mode cuyo refreshRate este a +-0.5 de sustainableRefreshHz y cuyas getPhysicalWidth/Height coincidan con display.getMode(); si no hay ninguno, dejar solo preferredRefreshRate. Matices: (1) el tier se calcula con las penalizaciones de powerSave y thermal de onCreate, asi que arrancar en ahorro de bateria limita a 60 Hz toda la sesion hasta que exista el listener del hallazgo del tier. Recalcular el budget en ese listener y volver a aplicar la ventana y las surfaces. (2) Un equipo MEDIUM con panel de solo 60/120 Hz (techo 90) queda en 60 Hz. Es una decision del budget actual; validarla en un gama media de 120 Hz.

**Riesgo y pruebas.** Afecta a la ventana compartida por Qt, la TextureView de Flutter Home y la WebView de Earth. Probar en equipos de 60, 90 y 120 Hz: logcat INGE_REFRESH_REQUEST_HZ e INGE_DISPLAY_ACTIVE_HZ, y 'adb shell dumpsys display | grep -i mActiveMode' / 'adb shell dumpsys SurfaceFlinger | grep -i refresh'. Algunos OEM (Samsung en modo adaptativo) ignoran preferredRefreshRate: verificar que preferredDisplayModeId si se respete. Comprobar que Earth sigue recibiendo su tier y que el scroll de Home no queda a 60 Hz en tier HIGH.


### El Dock recaptura toda la pagina en 3 a 5 FBO a resolucion completa en cada frame de scroll, con 12 taps y sin mirar el perfil

- **Veredicto:** parcial · **Impacto:** medio · **Esfuerzo:** medio · id `dock-glass-capturas-vivas`
- **Archivos:** `qml/Mobile/Main.qml:4445`, `qml/Mobile/flowcore/GlobalContextDock.qml:81`, `qml/Mobile/flowcore/GlobalContextDock.qml:97`, `qml/Mobile/flowcore/GlobalContextDock.qml:476`, `qml/Mobile/flowcore/GlobalContextDock.qml:480`, `qml/Mobile/flowcore/GlobalContextDock.qml:660`, `qml/Mobile/flowcore/GlobalContextDock.qml:715`, `qml/Mobile/flowcore/LiquidGlassSurface.qml:16`, `qml/Mobile/flowcore/LiquidGlassSurface.qml:67`, `qml/Mobile/flowcore/LiquidGlassSurface.qml:83`, `qml/Mobile/flowcore/LiquidGlassSurface.qml:121`, `qml/Mobile/flowcore/FlowPerformance.qml:12`, `qml/Mobile/pages/CalicatasEditorPage.qml:3159`

**Problema.** En las paginas QML (lista de Calicatas, Documentos) la capsula, el lente de seleccion y el boton IA estan siempre visibles (mas busqueda y menu cuando aparecen); cada uno tiene su propio ShaderEffectSource vivo de pageViewport, o sea de toda la pagina, sin textureSize. Al hacer scroll bajo el Dock el subarbol se ensucia en cada frame y se renderiza 3 a 5 veces extra a resolucion fisica completa, mas un frost de 12 muestras por pixel con sin/cos/exp. En GPUs tiler (Mali-G52, Adreno 610) cada cambio de render target obliga a vaciar los tiles: frames perdidos a 60 Hz. En flagships de 120 Hz el costo por segundo se duplica (calor y bateria). lowCostGlass solo se activa en Earth y ningun parametro del Dock consulta InGeCoreFlow.performance. Los peeks de Calicatas ya usan el patron barato (captura congelada a 0.5x).

**Evidencia.**

```
Main.qml:4445: backdropItem: pageViewport
GlobalContextDock.qml:81-82: readonly property Item glassBackdrop: nativeSurface ? (nativeBackdropReady ? backdropFrontImage : null) : backdropItem
GlobalContextDock.qml:97: readonly property bool lowCostGlass: nativeSurface && darkBackdrop
GlobalContextDock.qml:476: LiquidGlassSurface { id: capsuleGlass; anchors.fill: parent; tokens: root; frost: 4.5; lowCostTaps: 4; surfaceName: "main" }
GlobalContextDock.qml:660: LiquidGlassSurface { ... surfaceName: "search" }   :715: LiquidGlassSurface { ... surfaceName: "ai" }
LiquidGlassSurface.qml:16: property real frostTaps: 12
LiquidGlassSurface.qml:83-84: // Re-renders only when the backdrop subtree is dirty; no timer.
        live: surface.captureActive && surface.liveCapture
LiquidGlassSurface.qml:121: property real taps: surface.tokens.lowCostGlass ? surface.lowCostTaps : surface.frostTaps
CalicatasEditorPage.qml:3159: // One frozen grab at 0.5x (it is blurred anyway), blurred once
```

**Verificación.** Se confirma lo siguiente. El Dock captura pageViewport en las paginas QML (Main.qml:4445). Cada LiquidGlassSurface tiene su propio ShaderEffectSource con live:true (LiquidGlassSurface.qml:66-94). taps vale 12 salvo lowCostGlass, que solo se activa en Earth (GlobalContextDock.qml:97). Ningun parametro del Dock consulta InGeCoreFlow.performance (grep vacio). Al hacer scroll el subarbol se ensucia y cada captura se vuelve a renderizar en cada frame. Lo que no se sostiene: las capturas NO son de toda la pagina. sourceRect (lineas 69-82) limita cada FBO a la superficie mas 6 px de margen. Las superficies son pequenas: capsula de mainWidth x 54 dp, seleccion de 46x46, IA de 49x49 y busqueda de 78x26 (GlobalContextDock.qml:259-266). Con DPR 3, la capsula ocupa unos 790x200 px, aproximadamente 0.6 MB. El coste real son 3 o 4 pases extra por frame, y cada uno recorre todos los lotes del subarbol de pageViewport, porque Qt no descarta geometria fuera de sourceRect. Ese es el coste de draw calls en el hilo de render y de cambios de render target en GPUs tiler. Hay que sumar 12 muestras de frost sobre un area pequena. Por eso captureScale ahorra poco en el Dock. La mejora de fondo es la captura compartida (el punto 4 de la propuesta), y lowCostGlass por perfil, que reduce taps y quita el RectangularShadow. La nota sobre textureSize es correcta: Qt multiplica textureSize por el DPR, y el shader usa UV normalizadas (liquidglass.frag:113-114), asi que no se rompe.

**Corrección de evidencia.** LiquidGlassSurface.qml:69-82: sourceRect = mapToItem(glassBackdrop) + captureMargin 6, por lo que el FBO es del tamaño de la superficie, no de la pagina. GlobalContextDock.qml:259-266: mainHeight 54, slotSize 46, selectedSize 46; coreSize 49 (linea 269); searchHeight 26 y searchMinWidth 78. Superficies visibles en la practica: capsula, seleccion (visible: opacity > 0) e IA siempre; busqueda solo si hay searchAction.

**Cambio recomendado.** Convertir en cambio principal lo que la propuesta tenia como opcional. Crear una sola ShaderEffectSource por Dock que capture la banda union de las superficies sobre pageViewport. Pasarla a cada LiquidGlassSurface junto con un uniform vec4 srcRect (offset y escala UV) en liquidglass.frag. El shader se compila con qt_add_shaders (CMakeLists.txt:872-881), asi que es compatible con Qt 6.9. Asi se pasa de N pases a 1 por frame. Ademas: GlobalContextDock.lowCostGlass = (nativeSurface && darkBackdrop) || (flow && (flow.performance.profile >= flow.performance.safe || flow.lowMemoryMode)). Con eso los taps bajan a 2-4 y el RectangularShadow se apaga en gama baja. captureScale es opcional y de poco beneficio aqui. En perfil safe tambien se puede actualizar la captura con scheduleUpdate a 30 Hz mientras pageViewport se desplaza, validandolo a ojo.

**Riesgo y pruebas.** El Dock es la navegacion global: validar visualmente la refraccion a 0.75 y 0.5 en claro (el material puede verse mas suave) y que no aparezcan bordes negros. Home/Flutter y Earth usan backdrop nativo de 112x50 y no cambian salvo en perfil safe. Medir con QSG_RENDER_TIMING=1 / 'qt.scenegraph.time.renderloop' en logcat durante scroll en Calicatas, antes y despues, en un equipo Mali-G52 o Adreno 610 y en uno de 120 Hz; revisar INGE_DOCK_SHADER_STATUS y INGE_DOCK_GLASS_MODE.


### Cada FlowIcon tintado crea un layer offscreen + MultiEffect, aunque sus fuentes son SVG generados que podrían llevar el color

- **Veredicto:** parcial · **Impacto:** medio · **Esfuerzo:** medio · id `flowicon-layer-por-icono`
- **Archivos:** `qml/Mobile/components/FlowIcon.qml:20`, `qml/Mobile/components/FlowIcon.qml:78`, `qml/Mobile/components/FlowIcon.qml:84`, `qml/Mobile/components/FlowIcon.qml:85`, `qml/Mobile/lib/IconCatalog.js:79`, `qml/Mobile/lib/IconCatalog.js:276`, `qml/Mobile/lib/IconCatalog.js:308`

**Problema.** Cada icono tintado tiene su propia textura de layer, su nodo MultiEffect y un pase de render a textura cada vez que cambia. Eso rompe el batching del scene graph (un draw call y un material por icono) y suma memoria de GPU. En GPUs tiler de gama baja los cambios de render target son caros, y en listas, el Dock y la ficha hay decenas de iconos a la vez. Con asynchronous: false la rasterizacion SVG ocurre en el hilo de UI al abrir cada pagina, lo que provoca tirones en CPUs lentas. Ademas rasterScale = 2.0 es fijo y no depende de Screen.devicePixelRatio: segun como Qt aplique el DPR a URLs data: (solo lo hace automaticamente para rutas .svg, falta verificarlo), en pantallas de 3x-3.5x el icono puede rasterizarse por debajo de su tamaño fisico y en 1.5x-2x por encima.

**Evidencia.**

```
FlowIcon.qml:20: property real rasterScale: 2.0
FlowIcon.qml:80-84: sourceSize.width: Math.max(1, Math.round(width * root.rasterScale)) ... asynchronous: false ... layer.enabled: root.tintEnabled && status === Image.Ready
FlowIcon.qml:85-90: layer.effect: MultiEffect { brightness: root.flow.theme.isDark ? 0.55 : 0.0; colorization: 1.0; colorizationColor: { ... } }
IconCatalog.js:82-86: "<svg xmlns='http://www.w3.org/2000/svg' fill='none' viewBox='0 0 24 24'" + " stroke='black' stroke-width='" ... return "data:image/svg+xml;utf8," + encodeURIComponent(source)
IconCatalog.js:280-282: " fill='black'><path d='" + path + "'/></svg>"
101 declaraciones 'FlowIcon {' (CalicataFormPage 29, Main 22, CalicatasEditorPage 14, Dock 6 dentro de delegates); solo 5 con tintEnabled: false
```

**Verificación.** Se confirma lo siguiente. FlowIcon.qml:84-103 hace layer.enabled con MultiEffect por cada icono tintado, asynchronous:false en la linea 82 y rasterScale 2.0 fijo en la 20. Hay 101 declaraciones y 5 con tintEnabled:false. IconCatalog genera SVG en negro como data: URL (lineas 79-87 y 276-283). Ajusto el coste: el contenido de los iconos es estatico, asi que cada capa se renderiza una vez, al crear la pagina o al reconstruir la escena tras releaseResources. La memoria es despreciable (24 dp son unos 72² px). El coste continuo es que cada icono es un lote propio con su material MultiEffect, sin batching, mas N cambios de render target al abrir. Lo mas relevante entre dispositivos es el DPR. En Qt 6, QQuickImageBase solo multiplica sourceSize por el DPR si QQuickPixmap::isScalableImageFormat(url) es verdadero, es decir, con esquema image: o una ruta que termine en svg, svgz o pdf. La ruta de un data: URL termina en '</svg>', asi que el DPR no se aplica: el SVG se rasteriza a exactamente ancho×2 px. Se ve borroso en DPR 2.75-4 (la mayoria de FHD+ y QHD) y desperdicia en 1.5-2. Precalcular el color del SVG no es trivial: el MultiEffect aplica brightness 0.55 en oscuro y colorization 1.0 sobre trazos negros.

**Corrección de evidencia.** FlowIcon.qml:79-82: mipmap: root.rasterScale > 1.0; sourceSize = round(width*2); asynchronous:false. Uso por archivo: CalicataFormPage 29, Main 22, CalicatasEditorPage 14, CalicataReview 7, GlobalContextDock 6, CalicataPhotoEditor 5 y GlobalSearchOverlay 4.

**Cambio recomendado.** Primero, sin riesgo visual: rasterScale: Math.max(1, Screen.devicePixelRatio) y mipmap:false, porque se rasteriza al tamaño fisico exacto; validar a ojo en DPR 2 y 3.5. Despues, color dentro del SVG: agregar un parametro color a heroiconSvg, phosphorSvg y sourceForState (stroke o fill '#RRGGBB' con stroke-opacity o fill-opacity) y usar directamente el color semantico (tintColor, activeTintColor, error...). Comparar con capturas en claro y oscuro, porque el resultado actual del MultiEffect no es exactamente el tinte. Dejar el layer solo para sourceOverride con PNG o JPG. Mantener asynchronous:false en el Dock para que no aparezcan huecos, y usar true solo en delegates de listas largas.

**Riesgo y pruebas.** La regla 18 (rediseño de iconos despues de Configuracion y temas) no se ve afectada: se conservan los mismos glifos y solo cambia la tecnica de tintado, pero hay que comprobar que no haya diferencia visual. Comparar capturas antes y despues de los estados idle, selected, disabled, error, warning y success en el Dock, la ficha de Calicatas, Documentos y el Buscador. El cache de pixmaps pasara a tener una entrada por color (pocas). Probar que asynchronous: true no deja huecos visibles en el Dock al primer frame.


### Cada control de la ficha de Calicatas mantiene su propia textura de captura a DPR completo (decenas de MB de GPU)

- **Veredicto:** confirmado · **Impacto:** medio · **Esfuerzo:** bajo · id `calicata-glass-memoria`
- **Archivos:** `qml/Mobile/pages/CalicataLiquidGlass.qml:54`, `qml/Mobile/pages/CalicataLiquidGlass.qml:56`, `qml/Mobile/pages/CalicataLiquidGlass.qml:104`, `qml/Mobile/pages/CalicataLiquidGlass.qml:127`, `qml/Mobile/pages/CalicataLiquidGlass.qml:171`, `qml/Mobile/pages/CalicataLiquidGlass.qml:178`, `qml/Mobile/flowcore/LiquidGlassSurface.qml:67`, `src/graphics/InGeGraphicsCore.cpp:111`

**Problema.** Cada campo, chip y boton es un LiquidGlassSurface con su propio FBO de captura sin textureSize, es decir a resolucion fisica, y la textura sigue viva mientras el control este visible en la etapa activa, este o no dentro del viewport. Memoria aproximada por control: (w+12)·(h+12)·DPR²·4 B; un campo de 340x48 dp ocupa unos 0.9 MB con DPR 3.5 (1440p) y unos 0.3 MB con DPR 2. Con mas de 100 controles son decenas de MB de GPU, y abrir una etapa cuesta mas de 100 pases offscreen (tiron al abrir). En moviles de 2-3 GB eleva el riesgo de que el LMK mate la app mientras Camara/Galeria estan delante; al volver, prepareForExternalActivity/releaseResources obliga a recapturar todo. En flagships la memoria crece con DPR² aunque el frost de 3 a 8 px oculta ese detalle. lowCostGlass esta fijo en false e ignora el perfil.

**Evidencia.**

```
CalicataLiquidGlass.qml:54-55: readonly property bool _captureFits: glass.width * Screen.devicePixelRatio <= 4096 && glass.height * Screen.devicePixelRatio <= 4096
CalicataLiquidGlass.qml:56: // TODAS las superficies (primarias y controles) refractan un fondo real y opaco
CalicataLiquidGlass.qml:104 y :127: readonly property bool lowCostGlass: false
CalicataLiquidGlass.qml:171: frostTaps: glass.primarySurface ? 6 : 4
CalicataLiquidGlass.qml:178: liveCapture: true
CalicataFormPage.qml: 53 declaraciones 'CalicataLiquidGlass {', varias dentro de componentes reutilizados (PrfPickField x20, PrfToolButton x11, PrfCard x11, PhotoPill x10, MobileReadOnlyField x6...), mas CalicatasEditorPage x22 y CalicataPhotoEditor x9
```

**Verificación.** Verificado. _captureFits esta en CalicataLiquidGlass.qml:54-55; lowCostGlass:false fijo en las lineas 104 y 127; frostTaps 6/4 en la 171; liveCapture:true en la 178; y no hay textureSize, porque LiquidGlassSurface no lo expone. Los conteos se confirman: 53 en CalicataFormPage, 22 en CalicatasEditorPage y 9 en CalicataPhotoEditor. PrfPickField se usa 20 veces, PrfToolButton 11, PrfCard 11, PhotoPill 10 y MobileReadOnlyField 6. Los controles fuera del viewport siguen con visible:true dentro del Flickable, asi que mantienen su textura. Matiz importante: los fondos que capturan son ambientes opacos, estaticos y sin texto. Son formGlassAmbient con PhotoGlassAmbient (CalicataFormPage.qml:10139) y el scrim ya desenfocado a 0.5x (linea 4576). Por eso live:true no vuelve a renderizar en cada frame: el coste es memoria (FBO de (w+12)·(h+12)·DPR²·4 B por control) y N pases al abrir una etapa o al volver de Camara o Galeria. Eso ultimo ocurre porque releaseResources se llama en InGeGraphicsCore.cpp:113. Por la misma razon, bajar la escala de captura a 0.5 o menos es casi invisible, porque el fondo es un degradado suave. Con DPR 2.6-3 y 30-60 controles visibles por etapa son unos 15-40 MB de GPU: hay que reportarlo como impacto medio, no alto.

**Corrección de evidencia.** releaseResources esta en InGeGraphicsCore.cpp:113 (no en la 111). CalicataLiquidGlass.qml no importa InGe.CoreFlow: solo importa QtQuick, QtQuick.Window, QtQuick.Controls y "../flowcore" as FlowCore (lineas 1-4).

**Cambio recomendado.** Agregar captureScale a LiquidGlassSurface (textureSize = ceil(sourceRect × captureScale); Qt aplica el DPR). En CalicataLiquidGlass.qml agregar 'import InGe.CoreFlow 3.0 as Mobile', igual que en CalicataFormPage.qml:15. Usar captureScale: glass.primarySurface ? 0.5 : 0.33. Como los fondos son ambientes sin texto, no hace falta atarlo al perfil. Usar lowCostGlass: Mobile.InGeCoreFlow.performance.profile >= Mobile.InGeCoreFlow.performance.safe || Mobile.InGeCoreFlow.lowMemoryMode en ambos tokens. Opcional y de mas impacto: una sola captura compartida de formGlassAmbient con un uniform de sub-rectangulo UV, para pasar de mas de 100 FBO a 1.

**Riesgo y pruebas.** Calicatas es el modulo central: comparar capturas en claro y oscuro de la ficha, los campos enfocados o con error y las hojas flotantes; confirmar que el recorte de captureRect sigue sin muestrear fuera del ambiente (sin bordes negros). Medir 'adb shell dumpsys meminfo <paquete>' (filas Graphics / GL mtrack) antes y despues de abrir la ficha en un equipo DPR 2.x y otro DPR 3.5. Probar el flujo Camara/Galeria → volver (INGE_EXTERNAL_ACTIVITY_RENDER_RESTORED) y el autosave.


### FlowGlassSurface pone todo el panel del Buscador en un layer con sombra MultiEffect y además crea un pipeline de blur que nunca se usa

- **Veredicto:** parcial · **Impacto:** medio · **Esfuerzo:** bajo · id `glass-surface-layer-sombra`
- **Archivos:** `qml/Mobile/flowcore/FlowGlassSurface.qml:26`, `qml/Mobile/flowcore/FlowGlassSurface.qml:36`, `qml/Mobile/flowcore/FlowGlassSurface.qml:143`, `qml/Mobile/flowcore/FlowGlassSurface.qml:176`, `qml/Mobile/flowcore/FlowGlassSurface.qml:242`, `qml/Mobile/flowcore/FlowTheme.qml:19`, `qml/Mobile/GlobalSearchOverlay.qml:390`, `qml/Mobile/GlobalSearchOverlay.qml:555`, `qml/Mobile/GlobalSearchOverlay.qml:658`, `qml/Mobile/flowcore/LiquidGlassSurface.qml:96`

**Problema.** El panel del Buscador global (hasta 520x600 dp) se dibuja completo en una textura offscreen y luego pasa por los pases de blur de la sombra. Cualquier cambio interno (parpadeo del cursor del TextField cada ~500 ms, cada frame de scroll de la ListView de resultados) re-renderiza el panel entero y la sombra. Como hoy todos los equipos quedan en perfil high (hallazgo 1), esto esta activo siempre: en Mali-G52/Adreno 610 el scroll de resultados baja de 60 fps y a 120 Hz el costo se duplica. Ademas, cada FlowGlassSurface (unas 20 en Main, Documentos y Buscador) instancia una mascara con layer, un ShaderEffectSource y tres MultiEffect que nunca se muestran porque realBlurActive es la constante false e isGlass es readonly false: costo de creacion y memoria sin ningun resultado visual.

**Evidencia.**

```
FlowGlassSurface.qml:26: property bool elevationEnabled: materialRole === "emphasized"
FlowGlassSurface.qml:143-155: layer.enabled: elevationEnabled && !root.canonicalActive && visible && flow.performance.secondaryEffectsEnabled
    layer.effect: MultiEffect { shadowEnabled: true ... blurMax: 32 ... autoPaddingEnabled: true }
GlobalSearchOverlay.qml:390-393: FlowCore.FlowGlassSurface { id: panel ... materialRole: "emphasized"   (contiene TextField en :555 y ListView en :658)
FlowGlassSurface.qml:36: readonly property bool realBlurActive: false
FlowTheme.qml:19: readonly property bool isGlass: false
FlowGlassSurface.qml:176-208 y 242-280: Rectangle { id: glassMask ... layer.enabled: true }, ShaderEffectSource { id: glassCapture ... }, tres MultiEffect { source: glassCapture; visible: root.realBlurActive ... }
```

**Verificación.** Se confirma lo siguiente. layer.enabled con MultiEffect de sombra esta en FlowGlassSurface.qml:143-155. canonicalActive siempre es false porque requiere theme.isGlass, que es readonly false (FlowTheme.qml:19). realBlurActive es la constante false (linea 36). El panel del Buscador (GlobalSearchOverlay.qml:390-418) es emphasized y contiene un TextField y un ListView, asi que cada cambio interno, el cursor o el scroll, vuelve a renderizar la capa de hasta 520x600 dp y los pases de blur de la sombra. Corrijo el alcance: de las 27 FlowGlassSurface, solo el Buscador, la tarjeta de Perfil (Main.qml:1124, casi estatica) y el dialogo de Documentos (NothingDocumentsRoot.qml:1104, fondo de un Popup sin contenido, por tanto estatico) tienen la capa activa. El resto tiene elevationEnabled en false o ligado a liquidGlass, que es readonly false (Main.qml:2125). El pipeline sin usar (glassMask, glassCapture y los 3 MultiEffect) no cuesta GPU por frame: son invisibles y sin un consumidor visible no se renderizan. El coste es solo de creacion de objetos y memoria por instancia. La propuesta de RectangularShadow es valida en Qt 6.9 (blur, offset, radius, spread y color existen), pero el panel no solo usa transform: anima opacity, scale (con transformOrigin al centro) y el Translate panelTranslateV31 (lineas 414-425). Con solo 'transform: panel.transform' la sombra se desincroniza en la apertura y en el arrastre.

**Corrección de evidencia.** GlobalSearchOverlay.qml:414-425: opacity, scale, transformOrigin: Item.Center y transform: Translate { id: panelTranslateV31 }. Main.qml:4511, 5377 y 5427-5595: elevationEnabled: liquidGlass, que en Main.qml:2125 es 'readonly property bool liquidGlass: false'. NothingDocumentsRoot.qml:1052-1060 tiene elevationEnabled:false. Hay 27 declaraciones FlowGlassSurface, no unas 20.

**Cambio recomendado.** En GlobalSearchOverlay: poner elevationEnabled:false en el panel y declarar un RectangularShadow hermano, justo antes, con estas propiedades: x: panel.x; y: panel.y; width: panel.width; height: panel.height; radius: panel.radius; opacity: panel.opacity; scale: panel.scale; transformOrigin: Item.Center; transform: Translate { y: panelTranslateV31.y }; offset: Qt.vector2d(0, 8); blur: 24; spread: -4; color: root.flow.theme.glassShadow; visible: panel.visible && root.flow.performance.secondaryEffectsEnabled. Otra opcion es agrupar la sombra y el panel en un Item contenedor que reciba las tres transformaciones. En FlowGlassSurface, envolver glassMask, glassCapture y los 3 MultiEffect en un Loader { active: root.realBlurActive }. El beneficio es tiempo de creacion y memoria, no fps.

**Riesgo y pruebas.** Cambio visual leve de la sombra: comparar en claro el Buscador abierto, la animacion de apertura y cierre (panelTranslateV31) y los dialogos de Documentos que usan materialRole emphasized (NothingDocumentsRoot.qml:1107). Confirmar que nadie lee glassCapture/glassMask por id (grep). Medir con QSG_RENDER_TIMING el scroll de resultados del Buscador antes y despues.


### CircularAvatar decodifica la foto a resolución completa (sin sourceSize, cache:false, mipmap) en cada instancia

- **Veredicto:** parcial · **Impacto:** medio · **Esfuerzo:** bajo · id `avatar-sin-sourcesize`
- **Archivos:** `qml/Mobile/components/CircularAvatar.qml:57`, `qml/Mobile/components/CircularAvatar.qml:64`, `qml/Mobile/components/CircularAvatar.qml:66`, `qml/Mobile/components/CircularAvatar.qml:70`, `qml/Mobile/Main.qml:3324`, `qml/Mobile/Main.qml:1133`, `authsession.cpp:207`

**Problema.** Sin sourceSize, cada avatar decodifica la imagen completa: los avatares guardados ocupan 1024² = 4 MB, mas cerca de 1/3 de mipmaps, por instancia, y con cache: false cada una de las instancias de Main (cabecera, Perfil, lista multicuenta) hace su propia copia para mostrar 36 a 92 dp. Durante la vista previa inmediata (Main.qml:3324) se carga el archivo original de la galeria o la camara: de 12 a 108 MP, es decir entre 48 y 430 MB RGBA. En moviles de 2-4 GB eso es un riesgo directo de OOM o de que el LMK mate la app, y las texturas de mas de 4096 a 8192 px pueden superar GL_MAX_TEXTURE_SIZE en GPUs de gama baja, dejando el avatar en blanco. Ademas cada avatar suma un layer con MultiEffect.

**Evidencia.**

```
CircularAvatar.qml:57-72: Image { id: avatarImage; anchors.fill: parent; source: root.source; ... asynchronous: true; cache: false; smooth: true; mipmap: true; autoTransform: true ... layer.enabled: visible && status === Image.Ready; layer.effect: MultiEffect { maskEnabled: true; maskSource: avatarMaskSource } }   (no hay sourceSize en el archivo)
Main.qml:3322-3324: // Vista previa inmediata. ... profilePhotoSource = selectedFile
authsession.cpp:207-209: // 1024 px conserva calidad suficiente ... image = image.scaled(1024, 1024, ...)
Main.qml: 5 instancias de Components.CircularAvatar (1133, 1367, 3936, 4201, 4557)
```

**Verificación.** Se confirma lo siguiente. CircularAvatar.qml:56-74 no tiene sourceSize, tiene cache:false, mipmap:true y layer con MultiEffect de mascara. authsession.cpp:207-209 guarda 1024x1024 RGBA. Main.qml:3324 usa el selectedFile original como vista previa. Hay 5 instancias en Main: 1133, 1367, 3936, 4201 (lista multicuenta, una por cuenta) y 4557. Para JPG y PNG, Qt usa sourceSize en pixeles fisicos (solo los formatos escalables reciben DPR), asi que la formula propuesta es correcta, y con PreserveAspectCrop Qt elige el tamaño optimo de recorte. cache:true es seguro porque los avatares se guardan con nombre unico avatar_<ms>.png (authsession.cpp:183). Corrijo dos afirmaciones. Una imagen mayor que el tamaño maximo de textura no queda en blanco: Qt (QSGPlainTexture) la reduce en CPU al limite, con coste extra. Y QImageReader en Qt 6 tiene un allocationLimit por defecto, asi que una foto de 108 MP (≈432 MB) falla al cargar (avatar en error) en vez de provocar un OOM. Fotos de 12 a 50 MP (48-200 MB) si se decodifican completas, y ese es el riesgo real en equipos de 2 a 4 GB.

**Corrección de evidencia.** El nombre unico del archivo esta en authsession.cpp:183: "/avatar_%1.png".arg(QDateTime::currentMSecsSinceEpoch()). La cadena de la vista previa: Main.qml:3324 asigna profilePhotoSource, que accountPhotoV18() (linea 512) devuelve a los avatares.

**Cambio recomendado.** En CircularAvatar.qml usar sourceSize.width: Math.max(1, Math.ceil(avatarViewport.width * Screen.devicePixelRatio)) y lo mismo para height (en Qt 6, Screen esta disponible desde import QtQuick). Usar cache:true y mipmap:false, y mantener autoTransform:true. Para evitar recargas durante animaciones de tamaño, redondear a multiplos de 32 px. Lo guardado en disco es PNG, que no se puede escalar al decodificar: el ahorro en avatares guardados es de memoria residente (4 MB + mipmaps por instancia, a unos 100-300 px); en la vista previa JPEG se evita la decodificacion completa.

**Riesgo y pruebas.** Perfil y multicuenta son zonas protegidas: probar cambio de foto desde galeria (imagen de mas de 12 MP) y desde camara, foto vertical con EXIF, cambio de cuenta, avatar de la cabecera y lista de cuentas guardadas. Verificar que al cambiar el tamaño del avatar (animaciones de Perfil) no se recarga en bucle; si ocurre, redondear el sourceSize a pasos de 32 px. Medir 'adb shell dumpsys meminfo <paquete>' durante la vista previa antes y despues.


## Memoria, arranque e hilo principal


### La WebView de Cesium queda viva oculta con hasta 96–576 MB de caché y sin onRenderProcessGone

- **Veredicto:** parcial · **Impacto:** alto · **Esfuerzo:** medio · id `earth-webview-retenida-sin-renderer-gone`
- **Archivos:** `android/src/com/ingema/ingeplus/InGeQtActivity.java:1358`, `android/src/com/ingema/ingeplus/InGeQtActivity.java:1399`, `android/src/com/ingema/ingeplus/InGeQtActivity.java:1501`, `android/src/com/ingema/ingeplus/InGeQtActivity.java:2692`, `android/assets/cesium/index.html:398`, `android/src/com/ingema/ingeplus/InGeAssistantWebHost.java:47`

**Problema.** Tras visitar Earth una sola vez, la WebView de Cesium (contexto WebGL, teselas fotorrealistas y su caché de 96+32 MB en LOW, 256+128 MB en MID y 384+192 MB en HIGH) se queda en memoria oculta (GONE + onPause) hasta que la Activity se destruye, conviviendo con el scene graph de Qt y el motor Flutter de Home. En teléfonos de 3–4 GB clasificados como MEDIUM (reciben 'MID'), eso son hasta 384 MB retenidos en el proceso renderer. Cuando Android o el OEM matan ese renderer por memoria (muy habitual con la app en segundo plano), al no existir onRenderProcessGone el sistema (Android 8+) mata también el proceso de la app: el usuario lo ve como un crash al volver, y se pierde el estado no guardado. Lo mismo aplica a InGeAssistantWebHost mientras el asistente está abierto.

**Evidencia.**

```
InGeQtActivity.java:1399-1408:
    private void hideDirectEarthWebView(boolean releaseBackCallback) {
        emitEarthPageVisibility(false);
        stopEarthLocationSearch();
        if (earthWebView != null) {
            final WebView hiding = earthWebView;
            hiding.onPause();
            hiding.setEnabled(false);
            fadeOutSurface(hiding, () -> hiding.setVisibility(View.GONE));
        }
    }

InGeQtActivity.java:2692 (único llamador de la destrucción, en onDestroy):
        destroyDirectEarthWebView();

InGeQtActivity.java:1358 webView.setWebViewClient(new WebViewClient() { ... } solo sobrescribe shouldInterceptRequest y onPageFinished (no hay onRenderProcessGone en todo android/src).

index.html:398-401:
      const cacheBytes = (qualityTier === 'LOW' ? 96
        : qualityTier === 'MID' ? 256 : 384) * 1024 * 1024;
      const maximumCacheOverflowBytes = (qualityTier === 'LOW' ? 32
        : qualityTier === 'MID' ? 128 : 192) * 1024 * 1024;
```

**Verificación.** Confirmado: el WebViewClient de Earth (InGeQtActivity.java:1358-1373) solo sobrescribe shouldInterceptRequest y onPageFinished. No hay onRenderProcessGone en ningún archivo de android/src (tampoco en InGeAssistantWebHost.java:47-66). hideDirectEarthWebView (1399-1408) solo hace onPause, setEnabled(false) y GONE. destroyDirectEarthWebView (1501) solo se llama desde onDestroy (2692). Los valores de index.html:398-401 son los citados. En Android 8+ un renderer muerto sin manejar termina el proceso de la app, así que el riesgo de crash es real. Detalle incorrecto: classifyTier (InGePerformanceRuntime.java:296-298) devuelve LOW si totalMemoryBytes < 4 GiB, y un móvil vendido como de 3-4 GB reporta menos de 4 GiB. Esos móviles reciben 'LOW' (96+32 MB), no 'MID'; 'MID' corresponde en la práctica a equipos de 6 GB o más. Además cacheBytes es un techo que solo se llena al navegar. El asistente ya se destruye en onStop (InGeQtActivity.java:888 → closeFromUser → view.destroy()), así que su riesgo se limita al primer plano.

**Corrección de evidencia.** InGePerformanceRuntime.java:295-298: 'if (score < 1.5 || c.totalMemoryBytes < 4L * 1024L * 1024L * 1024L) return DeviceTier.LOW;'. InGeQtActivity.java:1567-1576 asigna LOW/ULTRA_LOW→'LOW' y MEDIUM/MEDIUM_HIGH→'MID'. InGeAssistantWebHost.java:109-120 destruye la WebView al cerrarse.

**Cambio recomendado.** 1) Prioridad: añadir onRenderProcessGone en ambos WebViewClient y devolver true. Para Earth: removeView + destroy, earthWebView=null, earthWebViewLoaded=false y, si Earth estaba visible, volver a Home por el camino existente. Si estaba oculta, basta con anularla y que se recree en la próxima apertura. 2) Al ocultar Earth: en JS, antes de onPause, bajar photorealisticTileset.cacheBytes (16-32 MB), llamar tileset.trimLoadedTiles() y viewer.scene.requestRender(). El recorte solo se aplica en el siguiente update y, con el WebView pausado, no habría ninguno. Restaurar cacheBytes al volver a InGeEarthEngineSetVisible(true). 3) Destrucción diferida (30-60 s) o inmediata en ULTRA_LOW/LOW, guardando la última cámara en Java. 4) setRendererPriorityPolicy(RENDERER_PRIORITY_WAIVED, true) solo después de tener el punto 1.

**Riesgo y pruebas.** Riesgo medio: reabrir Earth tras destruirla cuesta una carga en frío de Cesium (1–3 s en gama baja). Probar: Home→Earth→Home→Earth; selección de coordenada para Calicata (coordinateForCalicata/useEarthPointInCalicataM0809); Back nativo desde Earth; dock sobre la WebView; simular muerte del renderer con adb shell am crash o matando el proceso sandboxed_process de WebView y comprobar que la app sigue viva y vuelve a Home; logcat sin 'Render process ... crashed' seguido de muerte del proceso.


### Ni el tier del dispositivo ni la presión de memoria llegan a Qt/InGeCoreFlow: perfil 'high' en todos los móviles y sin onTrimMemory

- **Veredicto:** parcial · **Impacto:** alto · **Esfuerzo:** medio · id `presion-memoria-y-tier-no-llegan-a-qt`
- **Archivos:** `firstexperiencecontroller.cpp:60`, `qml/Mobile/Main.qml:3743`, `qml/Mobile/Main.qml:3800`, `qml/Mobile/Main.qml:1881`, `qml/Mobile/Main.qml:2043`, `qml/Mobile/flowcore/FlowPerformance.qml:15`, `qml/Mobile/flowcore/InGeCoreFlow.qml:159`, `android/src/com/ingema/ingeplus/InGePerformanceRuntime.java:269`, `android/src/com/ingema/ingeplus/InGePerformanceRuntime.java:315`, `android/src/com/ingema/ingeplus/InGeQtActivity.java:1567`, `src/graphics/InGeGraphicsCore.cpp:70`

**Problema.** InGePerformanceRuntime clasifica el equipo (ULTRA_LOW..HIGH, lowRam, memoryClass, powerSave, thermal) y calcula un presupuesto, pero en Java solo lo consume la telemetría y Earth (getEarthPerformanceTier). En Qt, el primer arranque toma firstExperience.performanceLevel, cuyo valor por defecto es 2, y como la Primera Experiencia está dormida el usuario nunca elige: todos los móviles, incluido uno de 2 GB, arrancan con performance.high (blur, blur complejo, reflejos, efectos secundarios y shaders activos según FlowPerformance.qml:15-19), contradiciendo el comentario de Main.qml:1881. InGeCoreFlow.lowMemoryMode ya existe y reduce física/animaciones, pero nadie lo escribe. Además no hay ningún manejador de onTrimMemory: la ventana Qt mantiene contexto GL y scene graph persistentes, la caché de componentes QML y el heap JS nunca se recortan, y Flutter nunca recibe aviso de presión de memoria; en segundo plano el proceso queda con un PSS alto y los OEM agresivos lo matan primero.

**Evidencia.**

```
firstexperiencecontroller.cpp:60:
    return qBound(0, s.value(kPerformance, 2).toInt(), 2);

Main.qml:3743-3748:
        var selectedPerformance = appSettingsV41.lastPerformanceLevel >= 0
                ? appSettingsV41.lastPerformanceLevel
                : Number(firstExperience.performanceLevel)
        flowPerformanceLevel = isFinite(selectedPerformance)

Main.qml:3800:
    readonly property bool shouldOpen: false // Dormant until final onboarding phase.

Main.qml:1881-1883:
// Perfil equilibrado por defecto. El perfil "high" se reserva para equipos
// que lo seleccionen explícitamente; evita sobrecargar GPU/main thread al arrancar.
property int flowPerformanceLevel: 1

Main.qml:2046-2047:
    value: app.flowPerformanceLevel >= 2
           ? Mobile.InGeCoreFlow.performance.high

InGeCoreFlow.qml:159:
    property bool lowMemoryMode: false

InGePerformanceRuntime.java:315:
        final int cacheMb = Math.max(24, Math.min(128, c.memoryClassMb / 3));

InGeGraphicsCore.cpp:70-71:
    window->setPersistentGraphics(true);
    window->setPersistentSceneGraph(true);

(grep: no existe onTrimMemory/onLowMemory/ComponentCallbacks2/trimComponentCache/sendMemoryPressureWarning en android/src ni en C++/QML)
```

**Verificación.** El núcleo es correcto. FirstExperienceController::performanceLevel tiene 2 por defecto (firstexperiencecontroller.cpp:60). La Primera Experiencia está dormida (Main.qml:3800). Component.onCompleted (3743-3748) asigna 2, y el Binding de 2043-2050 lo convierte en performance.high: con FlowPerformance.qml:15-19 quedan blur, complexBlur, reflejos y shaders activos. Ningún .qml/.cpp consume InGePerformanceRuntime: InGeCoreContext::deviceTier existe pero nadie lo asigna, y lowMemoryMode (InGeCoreFlow.qml:159) nunca se escribe. Agravante que el hallazgo no menciona: el mismo perfil se envía a Flutter Home como String(profile)='1' (Main.qml:4885-4890), y home.dart:41-43 solo activa su modo ligero con 'safe'/'low'/>=3, así que Flutter tampoco se adapta. No hay onTrimMemory/onLowMemory en android/src. Hay dos errores en el cambio propuesto. (a) onFlowPerformanceLevelChanged (Main.qml:2276-2279) persiste lastPerformanceLevel automáticamente, así que en el primer arranque ya se guarda 2. En las instalaciones existentes 'lastPerformanceLevel < 0' nunca será cierto y no sirve para detectar que el usuario nunca eligió (la elección manual existe en Main.qml:5473). (b) El manifiesto no declara android.app.background_running=true, y por defecto Qt for Android bloquea su bucle de eventos en ApplicationSuspended. Un nativeTrimMemory encolado con QueuedConnection en onTrimMemory(UI_HIDDEN/BACKGROUND) no se ejecutaría hasta volver a primer plano, justo cuando ya no sirve.

**Corrección de evidencia.** Main.qml:2276-2279 'onFlowPerformanceLevelChanged: { if (appSettingsV41) appSettingsV41.lastPerformanceLevel = flowPerformanceLevel }'. Main.qml:4885-4890 Perms.setFlutterHomeVisible(..., String(inGeCoreFlow.performance.profile)). flutter/inge_earth/lib/home.dart:41-43. AndroidManifest.xml no contiene android.app.background_running.

**Cambio recomendado.** Parte A: exponer el tier vía PermissionHelper (Q_INVOKABLE QVariantMap devicePerformance()) y añadir una clave nueva appSettingsV41.performanceUserChosen (bool), que solo se pone en true desde el control manual (Main.qml:5473). Si es false, derivar el nivel del tier: ULTRA_LOW/LOW→0 (safe, que Flutter también entiende), MEDIUM→1, MEDIUM_HIGH/HIGH→2, y volver a evaluarlo en cada arranque. Añadir el Binding de InGeCoreFlow.lowMemoryMode desde el tier. Parte B, solo en el lado Java (hilo principal de Android, que sí corre en segundo plano): onTrimMemory(level >= TRIM_MEMORY_UI_HIDDEN) → homeEngine.getSystemChannel().sendMemoryPressureWarning() y liberar la WebView de Earth oculta. En Qt, si se quiere recortar, hacerlo en el handler de QGuiApplication::applicationStateChanged(Qt::ApplicationSuspended), que corre antes de que Qt bloquee el bucle: engine.trimComponentCache() y collectGarbage(). No alternar persistentSceneGraph en segundo plano salvo con pruebas explícitas del patrón prepareForExternalActivity (InGeGraphicsCore.cpp:95-117).

**Riesgo y pruebas.** Riesgo medio. El comentario de InGeGraphicsCore.cpp:68-69 exige no liberar recursos cuando Earth oculta la ventana para reanudar Home en el mismo estado: solo liberar con la app en segundo plano, nunca durante Earth en primer plano. Probar: adb shell am send-trim-memory com.ingema.ingeplus BACKGROUND y UI_HIDDEN con Home, Calicatas abiertas y Earth; volver a primer plano sin pantalla negra ni el problema QueuePresentKHR citado en main_mobile.cpp:90-93; comprobar que un usuario que ya eligió perfil lo conserva; forzar tiers con el extra inge.performance.override (solo builds debuggable) y verificar logcat INGE_ADAPTIVE_RUNTIME.


### Entrar a Calicatas crea ~20k líneas de QML de forma síncrona y todas las etapas de la ficha a la vez

- **Veredicto:** parcial · **Impacto:** medio · **Esfuerzo:** alto · id `calicatas-creacion-sincrona`
- **Archivos:** `qml/Mobile/Main.qml:4640`, `qml/Mobile/Main.qml:5199`, `qml/Mobile/pages/CalicatasEditorPage.qml:5122`, `qml/Mobile/pages/CalicataFormPage.qml:3194`, `qml/Mobile/pages/CalicataFormPage.qml:3208`, `qml/Mobile/pages/CalicataFormPage.qml:11378`, `qml/Mobile/Main.qml:1680`

**Problema.** Al navegar a Calicatas, el Loader único de Main.qml crea de forma síncrona CalicatasEditorPage (6.392 líneas) y, en cuanto hay una pestaña, formLoader crea también de forma síncrona CalicataFormPage (13.293 líneas). Dentro de la ficha todas las etapas (General, Ubicación, Estratos, Muestras, Fotos, Revisión) se instancian a la vez y solo se ocultan con visible, por lo que también se decodifican al abrir las fotos de la etapa Fotos (3 × 720×720 RGBA ≈ 6 MB) aunque no se visiten. Todo ese trabajo ocurre en el hilo GUI de Qt dentro de uno o dos frames: en un teléfono de gama baja el dock y la transición se congelan perceptiblemente (y se repite cada vez que se vuelve a entrar, porque el Loader destruye la página al salir y al cerrar pestañas con _suspendFormLoader). En un flagship de 120 Hz el mismo bloqueo se ve como varios frames perdidos.

**Evidencia.**

```
Main.qml:4640-4655 (sin asynchronous):
        Loader {
            id: pageLoader
            active: app.loggedIn || app.guestMode
            ...
            sourceComponent: pageIndex === 0 ? homePage :
                             pageIndex === 1 ? fichaPage :

CalicatasEditorPage.qml:5122-5135 (sin asynchronous):
    Loader {
        id: formLoader
        ...
        active: tabsModel.count > 0 && root._formLoaderReady && !root._suspendFormLoader
        ...
        sourceComponent: Component {
            CalicataFormPage {

CalicataFormPage.qml:3194-3208:
    // A stage body has no collapsed state. Its controls stay instantiated so
    // changing context never discards a pending field or a document binding.
    component MobileStageBody: Rectangle {
        ...
        visible: root.sectionVisible(sectionNumber)

CalicataFormPage.qml:11378-11384 (etapa Fotos, sectionNumber 7):
                                    Image {
                                        id: photoHeroImage
                                        anchors.fill: parent
                                        source: photoCard.info.has ? root._photoSource(photoCard.slot) : ""
                                        sourceSize: Qt.size(720, 720)
```

**Verificación.** Confirmado: pageLoader (Main.qml:4640-4655) y formLoader (CalicatasEditorPage.qml:5122-5135) no son asynchronous. Las 9 MobileStageBody de CalicataFormPage (9371…13159) se instancian todas y solo se ocultan con visible (sectionVisible, 1599-1606). Al salir de Calicatas el Loader destruye la página. Pero el hallazgo omite una mitigación existente. CalicatasEditorPage.Component.onCompleted (4766-4771) arranca deferredWorkspaceInit (Timer de 32 ms, 4188-4193), que pinta primero el shell, y solo después initializeWorkspaceDeferred pone _formLoaderReady=true (2042). Es decir, la creación ya está partida en dos bloques: el shell y la ficha. El bloqueo grande que queda es la creación síncrona de CalicataFormPage. Error de detalle: photoHeroImage (11378-11384) tiene asynchronous: true y sourceSize 720×720, así que esas fotos no bloquean el hilo GUI; solo cuestan unos 6 MB de memoria. Crear las etapas de forma diferida contradice la garantía explícita de 3194-3195 y afecta a exportState/commitPendingField, por lo que su riesgo es alto.

**Corrección de evidencia.** CalicatasEditorPage.qml:4766-4771 'Paint the shell first; drafts, filesystem probing and CalicataFormPage construction run only after the initial interactive frame. deferredWorkspaceInit.start()'. CalicatasEditorPage.qml:2042 '_formLoaderReady = true'. CalicataFormPage.qml:11383-11385 'sourceSize: Qt.size(720, 720) ... asynchronous: true'.

**Cambio recomendado.** Cambio principal, de riesgo bajo-medio: formLoader asynchronous: true, mostrando el indicador de operación existente mientras status === Loader.Loading. Proteger los accesos a formLoader.item, que ya se comprueban en CalicatasEditorPage.qml:2555-2556. Después, pageLoader asynchronous solo para pageIndex 1/3, verificando que pageSnapshotV600 cubra el frame con item nulo y que leaveCalicatasSafely y handleBack toleren null. Lo de las etapas diferidas: solo para Fotos, condicionando el source de photoHeroImage a la primera visita, sin tocar los controles de campos. Medir con SUBAPP_FIRST_FRAME y con el log APP_INIT.

**Riesgo y pruebas.** Riesgo medio-alto: exportState(), commitPendingField(), el autosave de 20 s y la revisión no deben leer controles de etapas aún no creadas (deben leer de CalicataDocument). Probar: abrir ficha y exportar Excel/PDF sin visitar Fotos; cambiar de etapa rápido mientras incuba; Back nativo durante la carga asíncrona; abrir calicata desde la nube y desde 'Abrir con Calicatas' (.xlsx) con la página aún incubando; cerrar pestañas (_suspendFormLoader); rotación/cambio de tamaño en plegables; logcat sin 'TypeError: Cannot read property ... of null'.


### Exportar PDF/XLSX y leer Excel se hace de forma síncrona en el hilo GUI de Qt

- **Veredicto:** confirmado · **Impacto:** medio · **Esfuerzo:** alto · id `exportacion-sincrona-hilo-gui`
- **Archivos:** `qml/Mobile/pages/CalicataFormPage.qml:2723`, `androidcalicataexporter.cpp:2744`, `androidcalicataexporter.cpp:2796`, `androidcalicataexporter.cpp:3288`, `androidcalicataexporter.cpp:3303`, `qml/Mobile/pages/CalicatasEditorPage.qml:2070`, `qml/Mobile/Main.qml:3042`, `src/cpp/renditionflutterbridge.cpp:769`

**Problema.** Las exportaciones cargan y guardan la plantilla con QXlsx (descomprimir/comprimir ZIP y XML), decodifican hasta 5 imágenes (logos y 3 fotos, limitadas a 1600 px) y pintan el PDF con QPdfWriter, todo dentro de un Q_INVOKABLE llamado desde QML o desde el puente de Flutter, es decir, en el hilo GUI de Qt. El Timer de 32 ms (CalicataFormPage.qml:2697-2702) solo deja pintar un frame del overlay antes del bloqueo. En gama baja (eMMC lenta, 4 núcleos A53) esto congela la interfaz varios segundos sin progreso; si el usuario sale de la app en ese momento, las llamadas de ciclo de vida de Android que esperan al hilo Qt pueden quedarse bloqueadas y acabar en ANR. Importar un .xlsx (readWorkbookCells) tiene el mismo problema. El proyecto ya usa hilos de trabajo para fotos (calicatadocument.cpp:1829) y documentos (src/documents/nothingdocuments.cpp:143).

**Evidencia.**

```
CalicataFormPage.qml:2723:
            path = String(ExcelExporter.exportCalicataToPdf(state, base) || "")

androidcalicataexporter.cpp:2744-2745:
    QXlsx::Document xlsx(workingTemplatePath);
    if (!xlsx.load()) {
androidcalicataexporter.cpp:2796:
    if (!xlsx.saveAs(generatingPath) || !QFile::rename(generatingPath, outPath)) {
androidcalicataexporter.cpp:3288:
    if (!prepareReportImages(state, resourcesBase, &reportImages, &imageError)) {
androidcalicataexporter.cpp:3303:
    QPdfWriter pdf(&output);

CalicatasEditorPage.qml:2070:
        var raw = ExcelExporter.readWorkbookCells(String(localPath))

Main.qml:3042:
            var out = excelExporter.exportStateToXlsx(calicataState(), "FICHA_" + calCode)

renditionflutterbridge.cpp:769-770:
            ? m_exporter->exportRenditionToPdf(state, baseName)
            : m_exporter->exportRenditionToXlsx(state, baseName);
```

**Verificación.** Verifiqué el código citado. CalicataFormPage.qml:2723 llama de forma síncrona a ExcelExporter.exportCalicataToPdf tras un Timer de 32 ms (2696-2702). androidcalicataexporter.cpp:2744-2745 hace QXlsx load, 2796 saveAs, 3288 prepareReportImages y 3303 QPdfWriter, todo dentro de Q_INVOKABLE (androidcalicataexporter.h:24,30,34). CalicatasEditorPage.qml:2070 llama a readWorkbookCells en síncrono, y renditionflutterbridge.cpp:769-770 exporta en síncrono para Flutter. El cambio propuesto es compatible: QPainter sobre QPdfWriter y QImage está soportado fuera del hilo GUI y el texto usa FreeType en Android. El ANR por ciclo de vida es plausible pero no está demostrado; el congelamiento de varios segundos en gama baja sí es seguro.

**Corrección de evidencia.** Main.qml:3042 es código muerto: exportCalicataExcel() no se llama desde ningún sitio. La ruta real de Excel es CalicatasEditorPage.qml:2565 'out = formLoader.item.exportExcelFlow(provider)' → CalicataFormPage.qml:6760 'var out = exporter.exportStateToXlsx(st, baseName, provider)'.

**Cambio recomendado.** Igual que la propuesta, aplicado a exportExcelFlow (CalicataFormPage.qml:6720-6765), _runPdfExport, importCalicataExcel y RenditionFlutterBridge. Un único job en curso por documento (reusar _exportFlowActive/_pdfExporting) y un epoch de cuenta/documento para descartar resultados obsoletos. En el job solo datos puros (QVariantMap copiado, rutas); m_lastError, enqueueDocument y publish* se ejecutan en el hilo GUI dentro del QFutureWatcher::finished. Eliminar de paso la función muerta exportCalicataExcel de Main.qml.

**Riesgo y pruebas.** Riesgo medio: QXlsx::Document y QPdfWriter deben vivir enteros en el hilo de trabajo (sin tocar QObject del hilo GUI); el pintado de texto en hilos usa FreeType en Android y debe probarse con la fuente Rubik. Evitar dos exportaciones simultáneas del mismo documento (los guards _exportFlowActive/_pdfExporting ya existen). Probar: exportar Excel, PDF, Google Drive y Supabase; exportar con fotos de 50 MP; salir a Home de Android durante la exportación y volver; cambiar de cuenta durante la exportación (los resultados de otra cuenta deben descartarse); importar .xlsx desde InGeDrive; exportación de Rendiciones desde Flutter.


### La foto de perfil se decodifica a resolución completa en el hilo GUI y se pinta sin sourceSize en 5 avatares

- **Veredicto:** confirmado · **Impacto:** medio · **Esfuerzo:** medio · id `avatar-decodificacion-completa`
- **Archivos:** `authsession.cpp:120`, `authsession.cpp:196`, `authsession.cpp:1473`, `authsession.cpp:1483`, `qml/Mobile/Main.qml:3322`, `qml/Mobile/components/CircularAvatar.qml:56`, `qml/Mobile/Main.qml:1133`, `qml/Mobile/Main.qml:3936`, `qml/Mobile/Main.qml:4557`

**Problema.** Al cambiar la foto de perfil, AuthSession::updateUserAvatar (Q_INVOKABLE llamado desde QML, hilo GUI) decodifica la imagen original completa (una foto de cámara de 12–50 MP son 48–200 MB RGBA), hace una copia cuadrada completa, la escala con SmoothTransformation y la codifica a PNG, todo síncrono. En paralelo, Main.qml asigna el archivo original como vista previa y los CircularAvatar (92, 112 px y el avatar del header) lo cargan sin sourceSize, con cache:false (cada instancia decodifica su propia copia) y mipmap:true. En un teléfono de 2–4 GB con Qt + motor Flutter + WebView vivos, esto provoca picos de cientos de MB: muerte por LMK (Xiaomi/Samsung/Huawei matan la app) u OOM, y la UI congelada 1–3 s. Incluso con el avatar ya procesado (PNG 1024 px = 4 MB decodificado) cada avatar de 42–112 px vuelve a decodificar 4 MB + mipmaps sin compartir caché, en todos los móviles.

**Evidencia.**

```
authsession.cpp:125-128:
    if (url.isLocalFile()) {
        QImageReader reader(url.toLocalFile());
        reader.setAutoTransform(true);
        return reader.read();

authsession.cpp:201-209:
    QImage image = original;
    const int side = qMin(image.width(), image.height());
    ...
    image = image.copy(left, top, side, side);
    // 1024 px conserva calidad suficiente y evita cargar fotos gigantes en QML.
    if (image.width() > 1024 || image.height() > 1024)
        image = image.scaled(1024, 1024, Qt::KeepAspectRatio, Qt::SmoothTransformation);

authsession.cpp:1473-1483:
    const QImage sourceImage = readImageFromUrl(fileUrl);
    const QImage avatarImage = squareAvatarImage(sourceImage);
    ...
    if (!buffer.open(QIODevice::WriteOnly) || !avatarImage.save(&buffer, "PNG")) {

Main.qml:3322:  profilePhotoSource = selectedFile

CircularAvatar.qml:56-66 (sin sourceSize):
        Image {
            id: avatarImage
            anchors.fill: parent
            source: root.source
            ...
            asynchronous: true
            cache: false
            smooth: true
            mipmap: true
```

**Verificación.** Verifiqué todo el código citado. authsession.cpp:120-148 (readImageFromUrl) hace reader.read() a resolución completa. squareAvatarImage (196-212) hace copy(), luego scaled(SmoothTransformation) y convertToFormat. updateUserAvatar (1468-1488) es un Q_INVOKABLE (authsession.h:98) que se llama de forma síncrona desde FileDialog.onAccepted (Main.qml:3329) y además codifica a PNG en el hilo GUI. Main.qml:3324 asigna selectedFile a profilePhotoSource, y accountPhotoV18() (Main.qml:511-513) también lo devuelve. Por eso, durante el cambio, el avatar de 92 px (1133), el de 112 px (3936) y el de la cabecera (4557) decodifican el original. CircularAvatar.qml:56-66 no tiene sourceSize y usa cache:false y mipmap:true, así que cada instancia guarda su propia copia; las cuentas guardadas (1367, 4201) también. El cambio propuesto es válido en Qt 6.9.3. QImageReader::setClipRect se aplica sobre el tamaño sin transformar y setScaledSize se aplica después del clipRect (así lo dice la documentación), así que el recorte centrado no cambia con la rotación EXIF. En PNG/JPEG Qt no aplica el devicePixelRatio a sourceSize (solo a formatos escalables), por lo que width*Screen.devicePixelRatio es correcto. Screen está en QtQuick en Qt 6. El proyecto ya enlaza Qt::Concurrent y usa el patrón QFutureWatcher en nothingdocuments.cpp:114-143. Bajo el impacto: el pico de cientos de MB solo ocurre al cambiar la foto (flujo poco frecuente) y el decode de Image es asíncrono. El costo permanente es de unos 4 MB más mipmaps por cada avatar visible, en todos los móviles.

**Corrección de evidencia.** La asignación de la vista previa está en Main.qml:3324 (3322 es onAccepted). La llamada síncrona está en Main.qml:3329. accountPhotoV18() en Main.qml:511-513 propaga profilePhotoSource al avatar de 92 px (1133) y al de la cabecera (4557).

**Cambio recomendado.** Mantener 1-3 tal cual. En 2) leer los bytes del content:// (readAndroidContentUriBytes usa JNI, válido en un hilo worker porque QJniEnvironment adjunta el hilo) dentro del mismo job de QtConcurrent. Descartar el resultado si m_userId cambió mientras el job corría (cambio de cuenta). Mantener en el hilo GUI la escritura del caché, saveToDisk y las señales. En CircularAvatar usar sourceSize.width/height: Math.ceil(width * Screen.devicePixelRatio * imageScale) para no perder nitidez cuando imageScale > 1.

**Riesgo y pruebas.** Riesgo bajo-medio. Probar: foto vertical de cámara con EXIF de rotación (debe quedar derecha), PNG con transparencia, imagen de galería por content://, foto de 50 MP, cambio de foto en cuenta A y cambio a cuenta B (el caché local por cuenta no debe mezclarse), avatar remoto de Google/Supabase, modo sin conexión (la copia local debe seguir guardándose primero). Verificar en logcat que no hay 'QImageReader: allocation limit' ni OOM y medir PSS con adb shell dumpsys meminfo antes/después.


### Main.qml crea al arrancar árboles que en Android nunca se ven (UI de login QML) y overlays ocultos, con PNG grandes decodificados en el hilo GUI

- **Veredicto:** parcial · **Impacto:** medio · **Esfuerzo:** medio · id `arranque-arboles-qml-ocultos`
- **Archivos:** `qml/Mobile/Main.qml:4078`, `qml/Mobile/Main.qml:4044`, `qml/Mobile/Main.qml:1585`, `qml/Mobile/Main.qml:4837`, `qml/Mobile/Main.qml:1043`, `qml/Mobile/Main.qml:1299`, `qml/Mobile/Main.qml:4825`, `qml/Mobile/Main.qml:337`, `qml/Mobile/Main.qml:4908`

**Problema.** En Android el login lo dibuja Flutter, pero Main.qml instancia igualmente todo authFlickableV50 (formulario, logo, lista de cuentas guardadas con CircularAvatar) solo para ocultarlo, lo que contradice la regla de una sola implementación activa. El fondo authBackground se crea siempre (también para usuarios con auto-login que nunca ven el login) y, al no ser asynchronous, su PNG de 720×1600 (4,6 MB RGBA) se decodifica en el hilo GUI durante engine.load(), en la ruta crítica del primer frame. Además el umbral compara píxeles lógicos (dp): en cualquier teléfono o tablet Math.max(width, height) es menor que 1800, así que en un flagship de 1440×3200 se estira un fondo de 720 px (se ve borroso) y el asset de 1080×2400 nunca se usa. GlobalSearchOverlay (941 líneas), profileOverlayV18, accountSwitchSheetV18 y FlowQuickBubble también se crean al arrancar aunque estén cerrados. Las tres instancias de WelcomeSplashV600 cargan el logo de 1000×500 (2 MB) para mostrarlo a 240×84 dp. En gama baja todo esto alarga el arranque en frío y suma memoria permanente.

**Evidencia.**

```
Main.qml:4078-4081:
    FlowCore.ImeAwareFlickable {
        id: authFlickableV50
        // Android uses Flutter; Desktop uses the existing QML session UI.
        visible: Qt.platform.os !== "android"

Main.qml:4044-4049 (sin asynchronous ni sourceSize):
    Image {
        id: authBackground
        anchors.fill: parent
        source: app.authBackgroundSourceV40()
        fillMode: Image.PreserveAspectCrop
        smooth: true

Main.qml:1585:
readonly property bool authUseCompactBackgroundV40: Math.max(width, height) <= 1800

Main.qml:4837-4838:
GlobalSearchOverlay {
    id: globalSearchOverlayV30

Main.qml:1043-1047:
    id: profileOverlayV18
    anchors.fill: parent
    z: 99950
    visible: profileOverlayOpenV18 || opacity > 0.01

Main.qml:337-344 (logo 1000×500 en WelcomeSplashV600, sin sourceSize):
        Image {
            width: Math.min(welcomeSplash.width * 0.58, 240)
            height: 84
            ...
            source: welcomeSplash.logoSource
```

**Verificación.** Confirmado: authFlickableV50 (Main.qml:4078-4373) se instancia en Android solo para ocultarse, y fuera de él solo authEntrance (4064-4071) referencia authColumn, así que meterlo en un Loader es viable. authBackground (4044-4052) no es asynchronous: el PNG de qrc (720×1600, unos 4,6 MB en RGBA) se decodifica en el hilo GUI aunque authView no sea visible. El umbral de 1585 compara dp, así que en móviles siempre usa el de 720. GlobalSearchOverlay (941 líneas), profileOverlayV18 (1043), accountSwitchSheetV18 (1299) y FlowQuickBubble (4825) se crean al arrancar. Errores: (1) En Android el login lo dibuja Flutter en un FlutterTextureView a pantalla completa con AuthVideoBackground (flutter/inge_earth/lib/home.dart:1016), que tapa el fondo QML. El argumento de que se ve borroso en flagships no aplica en Android, y corregir el umbral a píxeles físicos haría que los flagships decodificaran inútilmente el de 1080×2400 (unos 10 MB). (2) Las tres WelcomeSplashV600 usan Image con cache:true por defecto y la misma URL, así que el logo de 1000×500 se decodifica una sola vez (unos 2 MB), no tres; el ahorro con sourceSize es pequeño.

**Corrección de evidencia.** Main.qml:337-344: Image sin 'cache: false', por lo que la caché de pixmaps es compartida. flutter/inge_earth/lib/home.dart:1016 'background: AuthVideoBackground('. InGeQtActivity.java:1966 'new FlutterView(this, new FlutterTextureView(this))'.

**Cambio recomendado.** 1) authFlickableV50 dentro de un Loader { active: Qt.platform.os !== "android" }, con authEntrance protegida contra un authColumn nulo. 2) authBackground: source vacío en Android (Qt.platform.os === "android" ? "" : app.authBackgroundSourceV40()) y asynchronous: true. Mantener el umbral actual para escritorio o calcularlo con píxeles físicos solo fuera de Android. 3) Overlays en Loader con estado publicado en app (globalSearchPresented, quickBubblePresented), porque flutterHomeShouldShowV60 (Main.qml:4898-4911) y las Connections usan .presented; open() y openFor() (Main.qml:2069, 2321) deben activar el Loader y llamar al método cuando el item exista. 4) sourceSize del logo como mejora menor.

**Riesgo y pruebas.** Riesgo medio: no romper Login, AuthSession, multicuenta ni Perfil (rutas protegidas por AGENTS.md). Probar: arranque con auto-login, arranque sin sesión, sesión cerrada, selector de cuentas, añadir cuenta, abrir/cerrar perfil, búsqueda global y burbuja rápida desde Home Flutter (la visibilidad de Home depende de .presented), modo escritorio (la UI QML de login debe seguir funcionando) y tema oscuro. Medir INGE_STARTUP FIRST_UI antes y después.


### Arranque en frío: recursos de escritorio y QtLocation en el APK, Flutter que bloquea el hilo UI y diagnósticos con E/S antes del primer frame

- **Veredicto:** parcial · **Impacto:** medio · **Esfuerzo:** bajo · id `arranque-frio-y-peso-binario`
- **Archivos:** `CMakeLists.txt:229`, `resources.qrc:29`, `resources.qrc:72`, `qml/Mobile/Main.qml:8`, `CMakeLists.txt:504`, `android/src/com/ingema/ingeplus/InGeQtActivity.java:1721`, `android/src/com/ingema/ingeplus/InGeQtActivity.java:825`, `main_mobile.cpp:151`, `betadiagnostics.cpp:62`, `betadiagnostics.cpp:156`

**Problema.** 1) El resources.qrc de escritorio entero se enlaza en el .so de Android: PNG de 4268×4268, avatares por defecto de 1,1 MB, scripts PowerShell y una segunda copia sin compilar de Main.qml, CalicataFormPage.qml, etc. bajo qrc:/qml/Mobile (choca con las reglas de un solo Main.qml y QRC/qmldir alineados). El móvil solo usa unas pocas rutas (qrc:/images/INGEMA_LOGO_COMPLETO.png, ICONO_LOGO_MTC.jpeg, :/templates/Calicata_Formato.xlsx, :/Logos/images/aldesa_logo.png, qrc:/icons/OJO_OPEN.png y OJO_CLOSE.png, qrc:/SUCS/...); el resto son unos 13 MB más de APK y de actualización, que pesan en teléfonos de 32 GB casi llenos. 2) import QtLocation no se usa, pero obliga a cargar libQt6Location y su plugin QML al arrancar y a empaquetarlos. 3) La primera vez que se muestra Auth/Home, entrypoint() ejecuta ensureInitializationComplete síncrono en el hilo UI de Android (cargar libflutter/libapp y, en debug, extraer assets), lo que retrasa toques y frames; el log dice PREWARM pero no se precalienta nada. 4) BetaDiagnostics, antes de engine.load(), lee y parsea hasta 2 MB / 2000 eventos JSON del spool, hace QSettings::sync y una llamada JNI, todo en la ruta crítica del primer frame.

**Evidencia.**

```
CMakeLists.txt:229 (dentro de MOBILE_SOURCES):
        "${INGE_PROJECT_ROOT}/resources.qrc"

resources.qrc:29-34 y 72-73:
        <file>images/Icono_Folder_Proyect.png</file>
        ... <file>images/Icono_Folder_Calicata.png</file> (4268×4268)
        <file alias="Mobile/Main.qml">qml/Mobile/Main.qml</file>
(157 archivos, ~14,7 MB; incluye scripts/export_excel.ps1 y copias QML en texto plano)

Main.qml:7-8:
import QtPositioning
import QtLocation
(sin tipos Map/Plugin; solo QtPositioning.coordinate en Main.qml:2758)

InGeQtActivity.java:1721-1724:
    private DartExecutor.DartEntrypoint entrypoint(String functionName) {
        final FlutterInjector injector = FlutterInjector.instance();
        injector.flutterLoader().startInitialization(getApplicationContext());
        injector.flutterLoader().ensureInitializationComplete(getApplicationContext(), null);

InGeQtActivity.java:825-827:
        android.util.Log.i("InGePerformance",
                "INGE_FLUTTER_PREWARM=SELECTIVE_IDLE");

betadiagnostics.cpp:62 y 156:
    loadLocalState();
    const QList<QJsonObject> persisted = readSpool();
```

**Verificación.** Confirmado: resources.qrc está en MOBILE_SOURCES (CMakeLists.txt:229). Tiene 180 entradas y 14,8 MB, incluidos Icono_Folder_* de 1-1,4 MB (solo los usan las ventanas de escritorio), default_avatar_* de 1,1 MB (solo perfilwindow.cpp), scripts .ps1 (calicataexcelexporter.cpp, de escritorio) y copias crudas bajo /qml/Mobile/... que nadie carga: la única referencia a qrc:/qml/ es MapWidget.qml, de escritorio. El móvil solo usa :/images/INGEMA_LOGO_COMPLETO.png, :/images/ICONO_LOGO_MTC.jpeg, :/Logos/*, :/templates/Calicata_Formato.xlsx, :/icons/OJO_*.png y :/SUCS/web, web/export y mtc. 'import QtLocation' (Main.qml:8) no se usa en qml/Mobile ni en el C++ móvil. entrypoint() (InGeQtActivity.java:1721-1724) llama a startInitialization y ensureInitializationComplete juntos en el hilo UI, y no hay prewarm real (826-827). BetaDiagnostics (betadiagnostics.cpp:62, 156) lee el spool antes de engine.load. Matices: el RCC dentro del .so se mapea en memoria y solo se pagina al accederse, así que el beneficio principal es el tamaño del APK y de las actualizaciones, no la RAM ni el arranque. Diferir todo loadLocalState() es incorrecto: incluye installId y la detección de sesión no limpia (activeSessionId), y record() depende de m_nextSeq calculado a partir del spool.

**Corrección de evidencia.** betadiagnostics.cpp:130-160: loadLocalState gestiona installId, m_priorSessionId/m_previousSessionUnclean con settings.sync() y luego readSpool() calcula m_nextSeq. betadiagnostics.cpp:117-119 graba QT_RUNTIME_READY con ese seq en el constructor.

**Cambio recomendado.** 1) resources_mobile_core.qrc con los mismos prefijos y alias (images/INGEMA_LOGO_COMPLETO.png, ICONO_LOGO_MTC.jpeg, Logos/*, templates/*, icons/OJO_*.png y todo SUCS/web, SUCS/web/export y SUCS/mtc), en sustitución de resources.qrc en MOBILE_SOURCES. resources.qrc se mantiene en el target de escritorio (línea 109). 2) Quitar 'import QtLocation' de Main.qml y Qt::Location del link móvil (504); find_package sigue igual porque el escritorio lo usa (170). 3) startInitialization(getApplicationContext()) en onCreate, o justo cuando Auth/Home se soliciten, y medir con INGE_STARTUP. 4) Mantener síncronos installId y la detección de sesión no limpia. Diferir solo readSpool() y el snapshot JNI al primer frameSwapped, con eventos en memoria sin seq que se renumeran tras cargar el spool.

**Riesgo y pruebas.** Riesgo bajo-medio: un recurso olvidado en el nuevo QRC solo falla en ejecución. Probar: exportar Excel (plantilla), PDF con logos MTC/proyecto/aldesa, iconos de ojo del login, visor SUCS web; revisar logcat sin 'Cannot open: qrc:' ni 'module "QtLocation" is not installed'; comprobar que androiddeployqt ya no empaqueta libQt6Location ni plugins geoservices. Medir INGE_STARTUP AUTH_START→FIRST_UI y HOME_READY antes y después en un equipo de 4 núcleos (la inicialización temprana de Flutter compite con Qt por CPU, así que hay que confirmar la mejora con números).


### QML consulta por JNI a Flutter cada 55–100 ms mientras Home o Auth están activos

- **Veredicto:** parcial · **Impacto:** bajo · **Esfuerzo:** medio · id `polling-jni-flutter`
- **Archivos:** `qml/Mobile/Main.qml:4033`, `qml/Mobile/Main.qml:4970`, `qml/Mobile/Main.qml:5035`, `permissionhelper.cpp:978`, `android/src/com/ingema/ingeplus/InGeQtActivity.java:732`, `android/src/com/ingema/ingeplus/InGeQtActivity.java:744`, `main_mobile.cpp:56`

**Problema.** Mientras Home Flutter está activo (la mayor parte del tiempo de uso) el hilo Qt se despierta unas 16 veces por segundo para ejecutar JavaScript y hacer una llamada JNI (QJniObject::callStaticObjectMethod + monitor synchronized en Java), aunque no haya ninguna acción; en Auth/Seguridad son unas 18 veces por segundo. Eso impide que la CPU entre en estados de reposo, consume batería y compite con animaciones y el render en los móviles de 4 núcleos; en modo ahorro o con limitación térmica el coste relativo aumenta. Además, el buzón de una sola posición descarta una segunda acción que llegue antes del siguiente sondeo (postFlutterHomeAction solo escribe si está vacío) y añade hasta 60 ms de latencia a cada toque en Home.

**Evidencia.**

```
Main.qml:5035-5045:
        Timer {
            id: flutterHomeActionPollV60
            interval: 60
            repeat: true
            onTriggered: {
                var action = ""
                try { action = Perms.takeFlutterHomeAction() } catch (error) {}

Main.qml:4033-4039:
    Timer {
        interval: 55
        repeat: true
        running: authView.visible || app.flutterSecurityOpenV70
        onTriggered: {
            var request = ""
            try { request = Perms.takeFlutterAuthRequest() } catch(e) {}

Main.qml:4970-4976: Timer { id: flutterHomeReadyPollV60; interval: 100; repeat: true ... Perms.isFlutterHomeReady() }

InGeQtActivity.java:744-747:
    private static synchronized void postFlutterHomeAction(String action) {
        if (pendingHomeAction.isEmpty())
            pendingHomeAction = action == null ? "" : action;
    }
```

**Verificación.** El código es real: Timers de 55 ms (Main.qml:4033-4042), 100 ms (4970-4983) y 60 ms (5035-5045) con llamada JNI (permissionhelper.cpp:978-990). Los buzones de una sola posición descartan una segunda acción (InGeQtActivity.java:744-752). La prioridad está sobrestimada. El manifiesto no declara android.app.background_running, así que Qt bloquea su bucle en segundo plano y el sondeo solo existe en primer plano. Cada tick cuesta decenas de µs (JS + JNI cacheado), un costo marginal frente a una pantalla encendida con Flutter dibujando. El problema relevante es de corrección y latencia: acciones perdidas si llegan dos en menos de 60 ms y hasta 60 ms de retraso por toque. flutterHomeActionPollV60 solo corre mientras Home está cargado, porque pageLoader lo destruye al cambiar de página.

**Cambio recomendado.** Mismo modelo push que se propone (patrón nativeRequestGlobalBack de main_mobile.cpp:56-75), con 'if (!qApp) return;' en el JNI y un drenado inicial en Component.onCompleted. Cambiar los buzones a ArrayDeque sincronizado y que takeFlutterHomeAction() devuelva de uno en uno, drenando en bucle desde QML. Como paso mínimo y de bajo riesgo, solo la cola en Java, que arregla las acciones perdidas sin tocar el modelo.

**Riesgo y pruebas.** Riesgo bajo-medio: el callback nativo puede llegar antes de que el motor QML exista (Flutter Auth arranca pronto); proteger con comprobación de qApp/QPointer y dejar que el primer drenado ocurra en Component.onCompleted. Probar: login, login con Google/OAuth, biometría, añadir/cambiar cuenta, Seguridad, todas las acciones de Home (navegación, búsqueda, perfil), Rendiciones y vuelta desde Earth; comprobar con logcat que ninguna acción se pierde ni se duplica.


### El build Android cae por defecto en Debug: C++ sin optimizar y Flutter Home/Auth en modo JIT

- **Veredicto:** parcial · **Impacto:** bajo · **Esfuerzo:** bajo · id `build-debug-flutter-jit`
- **Archivos:** `CMakeLists.txt:11`, `CMakeLists.txt:32`, `android/build.gradle:339`, `android/build.gradle:870`, `CMakePresets.json:9`

**Problema.** Si se configura sin tipo de build, CMake fuerza Debug y QT_ANDROID_DEPLOYMENT_TYPE lo hereda, así que se genera un APK debuggable cuyo Gradle enlaza flutter_debug: el motor Flutter que dibuja Home, Auth y Rendiciones corre en modo debug (Dart JIT, aserciones, VM service), que arranca mucho más lento y consume bastante más RAM que el AOT de release; el C++ se compila sin optimización (-O0) y ART no aplica la compilación optimizada a apps debuggable. En un flagship de 120 Hz se nota poco, pero en un teléfono de 2–4 GB las mediciones de arranque, jank y memoria hechas con este APK son engañosas y el usuario de gama baja que reciba un build así tiene Home lento y más muertes por LMK. No hay ningún preset Android de release que haga explícito el camino de producción.

**Evidencia.**

```
CMakeLists.txt:11-14:
    if(NOT CMAKE_BUILD_TYPE)
        set(CMAKE_BUILD_TYPE "Debug" CACHE STRING
            "Tipo de compilacion Android" FORCE)
    endif()

CMakeLists.txt:32-33:
    set(QT_ANDROID_DEPLOYMENT_TYPE "${CMAKE_BUILD_TYPE}" CACHE STRING
        "Tipo de despliegue Android" FORCE)

android/build.gradle:339:
    debugImplementation 'com.ingema.inge_earth:flutter_debug:1.0'

android/build.gradle:870:
    releaseImplementation("com.ingema.inge_earth:flutter_release:1.0") {

CMakePresets.json: el único preset es "desktop-mingw" con "CMAKE_BUILD_TYPE": "Debug" (no hay preset Android release).
```

**Verificación.** El código citado es real: CMakeLists.txt:11-14 fuerza Debug si CMAKE_BUILD_TYPE está vacío, 32-33 fuerza QT_ANDROID_DEPLOYMENT_TYPE=${CMAKE_BUILD_TYPE}, build.gradle:339/870 usan flutter_debug/flutter_release, y CMakePresets.json solo tiene desktop-mingw. Pero el escenario principal no se da en producción: los APK de entrega se generan en Qt Creator con tipo Release explícito y firma release (docs/RENDICIONES_ANDROID_PAQUETE_TECNICO_WEB_20261005.md:26-27, docs/google-drive-oauth-export-diagnosis.md:23). Qt Creator nunca deja CMAKE_BUILD_TYPE vacío. El defecto real y no detectado está en la línea 32: según la documentación de Qt 6.9, cualquier valor de QT_ANDROID_DEPLOYMENT_TYPE distinto de 'Release' desactiva --release, y esta variable no debe fijarse en el proyecto. Con RelWithDebInfo o MinSizeRel (la configuración 'Profile' de Qt Creator) se obtiene un APK debuggable con flutter_debug JIT, que falsearía cualquier medición de rendimiento. Cambiar el valor por defecto a Release es arriesgado: sin firma, androiddeployqt genera un APK release sin firmar que no se puede instalar por ADB y rompería el ciclo de validación de AGENTS.md.

**Corrección de evidencia.** Evidencia de que producción es Release: docs/RENDICIONES_ANDROID_PAQUETE_TECNICO_WEB_20261005.md:26 '| APK | android-build-release-signed.apk (Release, firmado) |'.

**Cambio recomendado.** 1) Eliminar el set(QT_ANDROID_DEPLOYMENT_TYPE ... FORCE) de CMakeLists.txt:32-33. Qt usará por defecto el empaquetado release en todo tipo distinto de Debug. Si se mantiene, mapear explícitamente: Debug→Debug y cualquier otro→Release. 2) Mantener Debug como valor por defecto cuando el tipo esté vacío, pero emitir message(WARNING) indicando que es un APK de depuración. 3) Añadir presets android-arm64-debug y android-arm64-release (arm64-v8a, Qt 6.9.3), con la firma tomada de variables de entorno. 4) Hacer las mediciones de gama baja siempre con el APK release. R8 queda fuera de esta fase.

**Riesgo y pruebas.** Riesgo bajo en el cambio de CMake; medio si se activa R8 (puede eliminar métodos que se llaman por JNI o @JavascriptInterface y romper Login/Home/Earth en tiempo de ejecución). En release deja de funcionar el extra inge.performance.override (InGePerformanceRuntime.readDebugOverride exige FLAG_DEBUGGABLE), así que conservar el preset debug para pruebas. Probar: build release arm64-v8a, instalación firmada, logcat limpio, Login/AuthSession/multicuenta/Home Flutter/Rendiciones/Earth, y comparar INGE_STARTUP (AUTH_READY, FIRST_UI, HOME_READY) y dumpsys meminfo entre debug y release.


## Build y empaquetado


### El compilador QML (qmlcachegen) casi no puede generar C++: 0 de 1058 funciones tipadas, context properties y el motor InGeCoreFlow sin precompilar

- **Veredicto:** parcial · **Impacto:** medio · **Esfuerzo:** alto · id `qml-aot-bloqueado`
- **Archivos:** `qml/Mobile/pages/CalicataFormPage.qml:36`, `qml/Mobile/flowcore/InGeCoreFlow.qml:68`, `qml/Mobile/pages/HomePage.qml:23`, `main_mobile.cpp:192`, `main_mobile.cpp:197`, `main_mobile.cpp:205`, `main_mobile.cpp:262`, `CMakeLists.txt:680`, `CMakeLists.txt:757`, `CMakeLists.txt:848`

**Problema.** qmlcachegen de Qt 6.9 solo genera C++ para bindings y funciones cuyos tipos puede resolver. Las funciones sin tipos, las búsquedas de context properties y los tipos de módulos sin typeinfo (InGe) quedan como bytecode: primero se interpretan y luego pasan por JIT tras varias llamadas.
Por eso la ficha de 13k líneas, Main.qml y el motor de animación ejecutan su JS interpretado. En CPUs de gama baja (A53) eso alarga la apertura de páginas y provoca caídas de frames en animaciones y scroll; un flagship lo disimula.
InGeCoreFlow, que usan todas las páginas, ni siquiera se precompila: se compila desde el fuente en el primer arranque después de cada instalación o actualización.
Además appCtx, auth y FS tienen dos estrategias de registro a la vez, lo que viola la regla 11.

**Evidencia.**

```
Ninguna de las 1058 declaraciones `function` en qml/Mobile tiene anotaciones de tipo. Ejemplos:
- CalicataFormPage.qml:36 `function setLabEvidence(index, key, value) {`
- InGeCoreFlow.qml:68 `function setRenderProfile(profile) {`
- HomePage.qml:23 `function __dp(v) { return Math.round(v * __armScale) }`
main_mobile.cpp:197-198:
    qmlRegisterSingletonInstance("InGe", 1, 0, "AppCtx", ctx);
    qmlRegisterSingletonInstance("InGe", 1, 0, "Auth", ctx->auth());
main_mobile.cpp:264-265 registra los mismos objetos como context properties:
    engine.rootContext()->setContextProperty("appCtx", ctx);
    engine.rootContext()->setContextProperty("auth", static_cast<QObject*>(ctx->auth()));
FS está duplicado igual en las líneas 192 y 262.
En QML hay 91 usos de appCtx./auth. y 0 de AppCtx./Auth. Otras context properties (renditions, docsOps, dockCommandRouter, ...) suman 129 usos.
CMakeLists.txt:757: set(_INGE_CPP_QMLDIR_TEXT "module InGe\n"), un qmldir sin typeinfo.
CMakeLists.txt:680-684 pone InGeCoreFlow.qml, FlowIcons.qml e InGeIconLibrary.qml en COREFLOW_SINGLETON_RESOURCES, que se pasa como RESOURCES (líneas 848-849), no como QML_FILES.
main_mobile.cpp:205-207: qmlRegisterSingletonType(QUrl(QStringLiteral("qrc:/InGe/Mobile/flowcore/InGeCoreFlow.qml")), "InGe.CoreFlow", 3, 0, "InGeCoreFlow");
```

**Verificación.** Lo que se confirma:
- Hay 1054 declaraciones `function` en qml/Mobile y ninguna tiene tipos.
- InGeCoreFlow.qml:68 es `function setRenderProfile(profile) {` y HomePage.qml:23 es `function __dp(v)`.
- FS, AppCtx y Auth tienen doble registro: main_mobile.cpp:192, 197 y 198 frente a 262, 264 y 265.
- InGeCoreFlow, FlowIcons e InGeIconLibrary van en RESOURCES (CMakeLists.txt:680-684 y 848-849), así que no pasan por qmlcachegen.
- CMakeLists.txt:757 genera un qmldir sin typeinfo.

Correcciones:
(a) appCtx/AppCtx tienen 0 usos en qml/Mobile, y en móvil AppContext no tiene Q_OBJECT (appcontext.h:16-24, `#ifndef INGE_MOBILE Q_OBJECT`). La fase 4 con QML_SINGLETON sobre AppContext es imposible tal como está escrita; basta con eliminar los dos registros.
(b) `Auth.` solo aparece en 2 comentarios, mientras que `auth.` tiene 91 usos. Migrar 91 usos a un singleton registrado con qmlRegisterSingletonInstance no ayuda a qmlcachegen, porque InGe no tiene qmltypes; solo sirve el registro declarativo.
(c) En arm64 el JIT de V4 compila las funciones calientes tras pocas llamadas. El costo principal de CalicataFormPage (13k líneas) es crear los objetos, y el AOT no lo elimina.
(d) InGeCoreFlow tiene 702 líneas y se compila desde el fuente solo en el primer arranque tras instalar; después usa la caché de disco.
(e) Sacar InGeCoreFlow a otro módulo obliga a mover también los Flow* que instancia (FlowPerformance, FlowMotion...), que hoy son QML_FILES de InGe.Mobile.
El beneficio es real pero moderado, y el riesgo para Auth es alto.

**Corrección de evidencia.** Son 1054 funciones, no 1058. appCtx/AppCtx tienen 0 usos y `auth.` tiene 91. Añadir:
- appcontext.h:16-24: Q_OBJECT solo con #ifndef INGE_MOBILE
- InGeCoreFlow.qml:44: `readonly property var graphicsCore: GraphicsCore` (un `var` que bloquea la inferencia de tipos)
- main_mobile.cpp:288: carga qrc:/InGe/Mobile/Main.qml

**Cambio recomendado.** Fase 1: correr qmllint (target AppCalicatasMobile_qmllint) o QT_QMLCACHEGEN_ARGUMENTS --verbose para listar qué no compila.

Fase 2: tipar las rutas calientes, por ejemplo `function __dp(v: real): int`, las funciones de InGeCoreFlow y los handlers de scroll y animación. Cambiar `property var graphicsCore` por un tipo concreto cuando haya registro declarativo.

Fase 3 (regla 11, riesgo bajo):
- Eliminar AppCtx (main_mobile.cpp:197) y appCtx (264), que no tienen ningún uso.
- Eliminar el singleton Auth (198), que no tiene usos reales, y conservar el context property `auth` mientras tanto.
- Para FS, quedarse con una sola de las dos vías (192 o 262).

Fase 4 (opcional, con regresión completa de Login, multicuenta y Perfil): registrar AuthSession de forma declarativa dentro del módulo InGe.Mobile, que ya tiene SOURCES con QML_ELEMENT, usando QML_NAMED_ELEMENT y QML_SINGLETON con un `static create()` que devuelve la instancia existente.

No crear un módulo InGe.CoreFlow aparte sin mover también sus Flow*.

**Riesgo y pruebas.** Alto: Login, Auth, multicuenta y Perfil dependen de auth y appCtx. Los parámetros tipados convierten valores (por ejemplo, truncan a int o convierten null en "" para string), así que hay que revisar cada firma.
Qué probar por fase:
- qmllint sin warnings nuevos.
- logcat "[InGe+ V122 QML]" sin ReferenceError ni TypeError.
- Regresión de login/logout/multicuenta/Perfil/Home.
- Medir el tiempo de apertura de CalicataFormPage y de los marcadores INGE_STARTUP_STAGE en un equipo de gama baja.


### libAppCalicatasMobile.so sin gc-sections, sin visibility=hidden, sin ICF ni LTO

- **Veredicto:** parcial · **Impacto:** medio · **Esfuerzo:** medio · id `flags-enlazador-nativo`
- **Archivos:** `CMakeLists.txt:486`, `CMakeLists.txt:522`, `tests/renditions/CMakeLists.txt:10`, `thirdparty/QXlsx/CMakeLists.txt:49`, `main_mobile.cpp:78`, `src/dock/DockContextController.cpp:387`

**Problema.** El .so exporta todos sus símbolos (visibilidad por defecto) y conserva el código muerto de QXlsx estático y del C++ que genera qmlcachegen.
Con una tabla dinámica más grande, dlopen y las relocaciones del arranque en frío tardan más, y hay más páginas que mapear. Pesa más en la gama baja, con eMMC lenta y poca RAM.
En un flagship el efecto es menor, pero también reduce el tamaño del APK.

**Evidencia.**

```
CMakeLists.txt:486-490: el único flag del target móvil es
            target_compile_options(AppCalicatasMobile PRIVATE
                -Wno-unused-result
            )
No hay -ffunction-sections, -Wl,--gc-sections, -fvisibility=hidden, ICF ni INTERPROCEDURAL_OPTIMIZATION.
tests/renditions/CMakeLists.txt:10-11 ya usa el patrón:
 target_compile_options(rendition-checks PRIVATE -ffunction-sections -fdata-sections)
 target_link_options(rendition-checks PRIVATE -Wl,--gc-sections)
thirdparty/QXlsx/CMakeLists.txt:49: option(BUILD_SHARED_LIBS "Build in shared lib mode" OFF). Es estático y se enlaza en las líneas 522-524.
Los símbolos JNI ya se exportan explícitamente, por ejemplo DockContextController.cpp:387-388: extern "C" JNIEXPORT void JNICALL Java_com_ingema_ingeplus_InGeQtActivity_nativeDockPublish(...)
main_mobile.cpp:78: int main(int argc, char *argv[]) no tiene export explícito.
```

**Verificación.** Lo que se confirma:
- CMakeLists.txt:486-490 solo añade -Wno-unused-result.
- tests/renditions/CMakeLists.txt:10-11 ya usa el patrón de secciones con gc-sections.
- QXlsx es estático (thirdparty/QXlsx/CMakeLists.txt:49 y 141).
- main_mobile.cpp:78 declara `int main` sin export, y Qt 6 en Android resuelve `main` con dlsym, así que Q_DECL_EXPORT es necesario.
- Los 11 métodos native de Java tienen implementación `extern "C" JNIEXPORT`: DockContextController.cpp:387, 403 y 447; DockCommandRouter.cpp:174; googledriveexporttransport.cpp:36; renditionflutterbridge.cpp:1093; GeminiAssistant.cpp:102; InGeEarthHostController.cpp:96 y 114; main_mobile.cpp:56; betadiagnostics.cpp:560. -fvisibility=hidden no los rompe.

Correcciones:
(a) El toolchain del NDK normalmente ya añade -ffunction-sections -fdata-sections a todas las compilaciones, y -Wl,--gc-sections solo a ejecutables, no a librerías compartidas como la app Qt en Android. Lo que falta de verdad es --gc-sections, la visibilidad oculta y ICF. Conviene verificarlo en compile_commands.json; repetir las flags es inofensivo.
(b) LTO sobre el C++ enorme que genera qmlcachegen (Main_qml.cpp y CalicataFormPage_qml.cpp, que en MinGW ya necesitan -mbig-obj, CMakeLists.txt:328-331) alarga mucho el build. Mejor dejarlo para después.

El beneficio es real: el linker de Android resuelve todas las relocaciones al cargar, y con menos símbolos exportados hay menos búsquedas en dlopen y un .so más pequeño. Pero es moderado.

**Corrección de evidencia.** Añadir:
- La lista completa de funciones JNI exportadas: 11 de 11, todas con JNIEXPORT.
- thirdparty/QXlsx/CMakeLists.txt:141 (add_library(QXlsx)).
- CMakeLists.txt:328-331 (código qmlcache gigante, relevante para el costo de LTO).

**Cambio recomendado.** Primera fase, sin LTO:
if(ANDROID)
  target_compile_options(AppCalicatasMobile PRIVATE $<$<NOT:$<CONFIG:Debug>>:-ffunction-sections -fdata-sections -fvisibility=hidden -fvisibility-inlines-hidden>)
  target_link_options(AppCalicatasMobile PRIVATE $<$<NOT:$<CONFIG:Debug>>:-Wl,--gc-sections -Wl,--icf=safe>)
  if(TARGET QXlsx) target_compile_options(QXlsx PRIVATE $<$<NOT:$<CONFIG:Debug>>:-ffunction-sections -fdata-sections>) endif()
endif()

Además:
- Declarar `Q_DECL_EXPORT int main(int argc, char *argv[])` en main_mobile.cpp:78.
- Medir `llvm-nm -D --defined-only | wc -l`, llvm-size y INGE_STARTUP_STAGE antes y después.
- Probar los callbacks JNI del dock, Drive, Rendiciones, Earth y Gemini.
- Dejar ThinLTO para otra fase, solo si el tiempo de build es aceptable.

**Riesgo y pruebas.** Medio: si `main` queda oculto, la app no arranca; ThinLTO además alarga el build.
Qué probar:
- Comparar `llvm-nm -D --defined-only libAppCalicatasMobile_arm64-v8a.so | wc -l` y `llvm-size` antes y después.
- Arranque en frío (INGE_STARTUP_STAGE).
- Callbacks JNI del dock y de Drive sin UnsatisfiedLinkError.
- Exportación Excel (QXlsx).
- logcat sin errores de carga de la librería principal.


### El build Android cae en Debug por defecto y QT_ANDROID_DEPLOYMENT_TYPE copia el tipo de build

- **Veredicto:** parcial · **Impacto:** medio · **Esfuerzo:** bajo · id `android-debug-por-defecto`
- **Archivos:** `CMakeLists.txt:11`, `CMakeLists.txt:32`, `CMakePresets.json:4`, `CMakeLists.txt:328`

**Problema.** Afecta a todos los teléfonos y sobre todo a la gama baja (2-4 GB de RAM, núcleos A53, 60 Hz). Cualquier configuración por línea de comandos sin -DCMAKE_BUILD_TYPE (por ejemplo, el paso "Build Android arm64-v8a" del ciclo de AGENTS.md) produce un APK Debug con estas consecuencias:
- El código propio se compila sin optimizar (-O0, sin NDEBUG). Son unas 28.5k líneas de C++ móvil, QXlsx estático y el C++ que qmlcachegen genera para 113 QML. Las librerías Qt de Android ya vienen precompiladas en release, así que el costo está en el código de la app.
- El APK queda debuggable, y en ese caso ART desactiva optimizaciones y no aplica perfiles AOT.
- Gradle usa el AAR Flutter de debug (ver hallazgo flutter-aar-debug-jit).
Un flagship de 120 Hz disimula el problema; un equipo de gama baja muestra saltos de frames y arranque lento, así que medir rendimiento sobre este build engaña.
Además, la línea 32 fuerza QT_ANDROID_DEPLOYMENT_TYPE igual a CMAKE_BUILD_TYPE. Según la documentación de Qt 6.9, cualquier valor distinto de "Release" impide que androiddeployqt reciba --release. Por eso un build RelWithDebInfo o MinSizeRel también saldría como APK debug aunque el código esté optimizado.

**Evidencia.**

```
CMakeLists.txt:11-14:
    if(NOT CMAKE_BUILD_TYPE)
        set(CMAKE_BUILD_TYPE "Debug" CACHE STRING
            "Tipo de compilacion Android" FORCE)
    endif()
CMakeLists.txt:32-33:
    set(QT_ANDROID_DEPLOYMENT_TYPE "${CMAKE_BUILD_TYPE}" CACHE STRING
        "Tipo de despliegue Android" FORCE)
CMakePresets.json (solo hay un preset, el de escritorio): "name": "desktop-mingw" ... "CMAKE_BUILD_TYPE": "Debug". No existe ningún preset Android.
CMakeLists.txt:328-331: el C++ que genera qmlcachegen es tan grande que MinGW necesita -Wa,-mbig-obj para ".rcc/qmlcache/AppCalicatasMobile_qml/Mobile/Main_qml.cpp" y "pages/CalicataFormPage_qml.cpp".
```

**Verificación.** Lo que se confirma:
- CMakeLists.txt:11-14 fuerza Debug cuando CMAKE_BUILD_TYPE está vacío.
- CMakeLists.txt:32-33 hace QT_ANDROID_DEPLOYMENT_TYPE igual a CMAKE_BUILD_TYPE con FORCE.
- CMakePresets.json solo trae el preset desktop-mingw (Debug).
- En el código de Qt 6.9.3 (Qt6AndroidMacros.cmake, _qt_internal_android_get_deployment_type_option): si QT_ANDROID_DEPLOYMENT_TYPE tiene un valor distinto de RELEASE, Qt no pasa --release. Si la variable no existe, pasa --release para Release, RelWithDebInfo y MinSizeRel. Por la línea 32, un build RelWithDebInfo o MinSizeRel sale como APK debuggable.

Lo que no se sostiene es el impacto:
- El APK de producción documentado es 'android-build-release-signed.apk (Release, firmado)', generado en C:\InGeBuild\A37 (docs/RENDICIONES_ANDROID_PAQUETE_TECNICO_WEB_20261005.md:26-30).
- Qt Creator siempre pasa CMAKE_BUILD_TYPE de forma explícita, así que el valor por defecto Debug solo afecta a configuraciones manuales por CLI. El APK que llega a los usuarios no se ve afectado. Es un problema de higiene de medición y de builds de prueba.

Riesgo que el cambio propuesto añade: cambiar el valor por defecto a RelWithDebInfo sin tener la firma configurada produce un APK release sin firmar que no se instala. Eso rompería el paso 'Instalar APK' del ciclo de AGENTS.md en los builds por CLI.

**Corrección de evidencia.** Añadir esta evidencia: docs/RENDICIONES_ANDROID_PAQUETE_TECNICO_WEB_20261005.md:26-30 ('android-build-release-signed.apk (Release, firmado)', ruta ...\apk\release\...). La línea CMakeLists.txt:328 (-Wa,-mbig-obj) solo aplica a MinGW de escritorio y no es evidencia del build Android.

**Cambio recomendado.** 1. Mantener el cambio de las líneas 32-33: Debug->"Debug" y cualquier otro tipo->"Release", con FORCE. Así RelWithDebInfo genera un APK release.
2. No cambiar el valor por defecto de la línea 12 hasta que exista firma. Mientras tanto, añadir message(WARNING "InGe+ Android Debug: APK debuggable y Flutter en JIT; no usar para medir rendimiento").
3. Añadir en CMakePresets.json un preset android-arm64-release (RelWithDebInfo, solo arm64-v8a, QT_ANDROID_SIGN_APK=ON). El keystore y las contraseñas se toman de variables de entorno, sin escribirlos en el repo ni en logs.
4. Medir el rendimiento por dispositivo solo con ese preset.

**Riesgo y pruebas.** Bajo para el código, pero un APK release sin firmar no se instala, así que la firma tiene que estar configurada. Desaparecen los Q_ASSERT de Debug. Los kits de Qt Creator siguen pasando el tipo explícito y no cambian.
Qué probar:
- El log de build muestra "androiddeployqt ... --release".
- `adb shell dumpsys package com.ingema.ingeplus | grep -i flags` no contiene DEBUGGABLE.
- Regresión de Login/Supabase/AuthSession/multicuenta/Perfil/Home.
- logcat sin errores QML ni crash.
- Comparar los tiempos INGE_STARTUP_STAGE entre Debug y RelWithDebInfo en un equipo de gama baja.


### resources.qrc de escritorio se enlaza en Android: unos 10 MB de imágenes sin uso y 1.59 MB de QML crudo duplicado

- **Veredicto:** parcial · **Impacto:** medio · **Esfuerzo:** bajo · id `qrc-escritorio-en-android`
- **Archivos:** `CMakeLists.txt:229`, `CMakeLists.txt:896`, `resources.qrc:17`, `resources.qrc:29`, `resources.qrc:71`, `resources.qrc:100`

**Problema.** Afecta a todos los teléfonos. El rcc va compilado dentro de libAppCalicatasMobile_arm64-v8a.so, y los PNG/JPEG no se recomprimen. Esto suma unos 11.5 MB muertos al .so, al APK (el release documentado pesa 182,312,268 B) y al espacio instalado. Pesa más en equipos de 32 GB con poco almacenamiento libre y en eMMC lentas.
Como las imágenes están dentro del .so, ni un AAB ni los splits por densidad pueden recortarlas por dispositivo; la única forma de ahorrar es no empaquetarlas.
Las copias crudas de QML bajo /qml/Mobile contradicen la regla 3/12 (una sola implementación y QRC alineado). Si algún día se cargan, saltarían el código precompilado.

**Evidencia.**

```
CMakeLists.txt:229 (dentro de MOBILE_SOURCES):        "${INGE_PROJECT_ROOT}/resources.qrc"
CMakeLists.txt:896-899 (comentario): "All mobile QML is packaged exactly once by qt_add_qml_module() ... This prevents duplicate QML copies"
resources.qrc:71-73:
    <qresource prefix="/qml">
        <file alias="MapWidget.qml">qml/Desktop/MapWidget.qml</file>
        <file alias="Mobile/Main.qml">qml/Mobile/Main.qml</file>
resources.qrc:91:        <file alias="Mobile/pages/CalicataFormPage.qml">qml/Mobile/pages/CalicataFormPage.qml</file>
resources.qrc:29-34:        <file>images/Icono_Folder_Proyect.png</file> ... <file>images/Icono_Folder_Recursos.png</file>
resources.qrc:17-18: default_avatar_men.png, default_avatar_women.png
resources.qrc:100-102: <qresource prefix="/scripts"> <file alias="export_excel.ps1">...
Medición (script sobre los qrc enlazados):
- resources.qrc aporta 14.83 MB en 180 archivos.
- 124 archivos (9.95 MB) no tienen referencia en qml/Mobile, src/, los .cpp móviles ni android/src. Ejemplos: Icono_Folder_Calicata.png 1.40 MB, Icono_Folder_Proyect 1.28 MB, Icono_Folder_PDF 1.19 MB, Icono_Folder_Excel 1.13 MB, default_avatar_men 1.17 MB (este solo aparece en perfilwindow.cpp, que es de escritorio).
- 27 QML/JS crudos (1,590,057 B) duplican el módulo InGe.Mobile bajo qrc:/qml/Mobile/. Ningún código móvil los carga: solo calicatamapdialog.cpp:219 (escritorio) usa qrc:/qml/MapWidget.qml.
Lo que sí usa la app móvil de este qrc:
- qrc:/images/INGEMA_LOGO_COMPLETO.png e ICONO_LOGO_MTC.jpeg (PropACalicataIconMap.js:70, CalicataFormPage.qml:2232)
- :/templates/Calicata_Formato.xlsx (androidcalicataexporter.cpp:2117)
- :/Logos/images/* (docscontroller.cpp:234-235, docsops.cpp:236-237)
- qrc:/icons/OJO_OPEN.png y OJO_CLOSE.png (LoginPageForm.qml:172)
- /SUCS/** (CalicataRules.js, androidcalicataexporter.cpp)
```

**Verificación.** Lo que se confirma:
- CMakeLists.txt:229 mete resources.qrc en MOBILE_SOURCES.
- El comentario de las líneas 895-900 dice que el QML se empaqueta una sola vez.
- main_mobile.cpp:288 carga qrc:/InGe/Mobile/Main.qml, así que las copias /qml/Mobile/* de resources.qrc nunca se cargan (1,590,057 B).

Referencias móviles que encontré a este qrc:
- OJO_OPEN/OJO_CLOSE: LoginPageForm.qml:172 y RegisterPageForm.qml:234 y 292
- Logos INGEMA/MTC: CalicataFormPage.qml:2232 y 2276-2277, PropACalicataIconMap.js:70-71, androidcalicataexporter.cpp:1597-1598
- /Logos: docscontroller.cpp:234-235 y docsops.cpp:236-237
- Plantilla: androidcalicataexporter.cpp:2117
- /SUCS/web, /SUCS/web/export y /SUCS/mtc: CalicataRules.js:1175, 1179 y 1272, androidcalicataexporter.cpp:688, CalicataProfile.qml:7
- /scripts solo se usa en calicataexcelexporter.cpp:796, que es de escritorio.

Mi recuento: 14,827,836 B en total, unos 758 KB usados, 1.59 MB de QML crudo y unos 12.5 MB más sin referencia. Es incluso más de lo que reporta el hallazgo.

Corrección de impacto: los datos de rcc se mapean desde el .so y solo se leen las páginas a las que se accede. Las imágenes que no se usan no cuestan decodificación ni RAM, y el arranque no cambia de forma medible. El beneficio es de tamaño: unos 13-14 MB de 182 MB, alrededor del 7%, en el APK y en el almacenamiento. No hay ganancia de fluidez en la gama baja.

**Corrección de evidencia.** El comentario está en CMakeLists.txt:895-900. La entrada QML real está en main_mobile.cpp:288. Faltan en la lista de usos RegisterPageForm.qml:234 y 292 (OJO) y los prefijos /SUCS/web, /SUCS/web/export y /SUCS/mtc (resources.qrc:122 y siguientes, :156). La cifra sin referencias depende del criterio: entre 9.95 y 12.5 MB más 1.59 MB de QML.

**Cambio recomendado.** Mantener la propuesta: un resources_mobile.qrc con exactamente los alias /images/INGEMA_LOGO_COMPLETO.png, /images/ICONO_LOGO_MTC.jpeg, /Logos/images/*, /templates/Calicata_Formato.xlsx, /icons/OJO_OPEN.png, /icons/OJO_CLOSE.png y todo /SUCS (incluidos web, web/export y mtc).

Usarlo en CMakeLists.txt:229 y dejar resources.qrc solo en el target de escritorio (línea 109). Validar con el bucle FATAL_ERROR que ya existe en las líneas 289-293. No se borra ningún archivo.

Vender el cambio como reducción de tamaño, no de rendimiento.

**Riesgo y pruebas.** Medio: una ruta construida dinámicamente podría quedar fuera y la imagen no cargaría.
Qué probar en logcat ("[InGe+ V122 QML]" y "Cannot open"):
- Login (iconos de ojo)
- Perfil y multicuenta
- Ficha de calicata (logos MTC/INGEMA, patrones SUCS)
- Exportación Excel (plantilla)
- Documentos (copia de Logos)
Comparar el tamaño del APK y del .so antes y después.


### El video de fondo de Auth (2560x1440, 20 Mbps, 30 MB) supera el decodificador de la gama baja, y hay assets Flutter muertos

- **Veredicto:** confirmado · **Impacto:** medio · **Esfuerzo:** bajo · id `video-auth-1440p`
- **Archivos:** `flutter/inge_earth/pubspec.yaml:62`, `flutter/inge_earth/lib/auth_video_background.dart:9`, `flutter/inge_earth/lib/auth_video_background.dart:41`, `flutter/inge_earth/lib/home.dart:1016`

**Problema.** Gama baja (SoC Helio A/P, Unisoc, Snapdragon 4xx): muchos decodificadores H.264 de hardware llegan solo a 1080p30, y el CDD no garantiza 1440p. En esos equipos MediaCodec cae a decodificación por software, o falla y la pantalla queda en el póster (AUTH_VIDEO_UNAVAILABLE). Eso cuesta CPU, temperatura y batería justo en la primera pantalla.
En modo cover sobre un teléfono 20:9 en vertical solo se ve aproximadamente el 26% del ancho decodificado.
En todos los dispositivos, incluidos los flagship, el APK carga 30 MB de video, 3.5 MB de un PNG muerto y unos 2.7 MB de fuentes que no se usan.

**Evidencia.**

```
pubspec.yaml:62-67:
  assets:
    - assets/home_final/approved_reference.png
    - assets/branding/
    - assets/auth/ingema_auth_background.png
    - assets/auth/ingema_auth_video.mp4
    - assets/auth/ingema_auth_video_poster.jpg
ffprobe de ingema_auth_video.mp4: codec_name=h264 profile=Main width=2560 height=1440 r_frame_rate=30/1 bit_rate=19890070. Tiene además una pista codec_name=aac. Dura 12.17 s y pesa 30,267,125 B.
auth_video_background.dart:9: "/// Fondo animado de Auth: video local en modo cover, sin audio"
auth_video_background.dart:41-48: VideoPlayerController.asset(AuthVideoBackground.videoAsset, ... viewType: VideoViewType.textureView,)
ingema_auth_background.png (3,489,455 B) no tiene ninguna referencia en flutter/inge_earth/lib.
El AAR release incluye LucideVariable-w100..w600.ttf (unos 2.7 MB), pero la app solo usa fontFamily 'Lucide', que tras el tree-shaking pesa 6,708 B.
```

**Verificación.** Lo que verifiqué:
- ffprobe: h264 Main, level 50, 2560x1440, 30/1, 19,890,070 bps, yuv420p, más una pista AAC; 12.17 s y 30,267,125 B.
- El póster es de 1920x1080.
- ingema_auth_background.png solo aparece en pubspec.yaml:65; nada en lib/ lo usa.
- En el AAR release, LucideVariable-w100..w600 suman unos 2.7 MB y lucide.ttf pesa 6,708 B.

Agravante que el hallazgo no vio: la única condición que apaga el video es `animate: widget.tokens.motionScale > 0 && !widget.tokens.lowPerformance` (home.dart:1016-1018), y nunca se activa en gama baja.
- lowPerformance exige el perfil 'safe', 'low' o un valor >=3 (home.dart:40-43).
- QML envía String(inGeCoreFlow.performance.profile) (Main.qml:637).
- FlowPerformance.profile vale `high` (1) por defecto (FlowPerformance.qml:12), y no existe ninguna llamada a setPerformanceProfile; solo su definición en InGeCoreFlow.qml:444.
Resultado: todos los equipos, incluidos los de gama baja, decodifican el 1440p.

Matiz de impacto: Auth solo aparece al cerrar sesión o al añadir una cuenta, porque autoLogin lo evita en los arranques normales. El peso del APK, unos 33 MB, afecta a todos los dispositivos.

**Corrección de evidencia.** Añadir:
- home.dart:1016-1018 (condición animate)
- home.dart:40-43 (lowPerformance)
- Main.qml:637 (perfil enviado)
- FlowPerformance.qml:12 (`property int profile: high`)
- InGeCoreFlow.qml:444-445 (setPerformanceProfile sin ninguna llamada)
- ffprobe: level=50, pix_fmt=yuv420p

**Cambio recomendado.** 1. Recodificar como propone el hallazgo, añadiendo -pix_fmt yuv420p: `ffmpeg -i ingema_auth_video.mp4 -an -vf scale=1920:1080 -c:v libx264 -profile:v main -level 4.0 -pix_fmt yuv420p -b:v 3500k -maxrate 4500k -bufsize 9000k -g 60 -movflags +faststart out.mp4`. Mantener 16:9, que coincide con el póster de 1920x1080.
2. Quitar ingema_auth_background.png de pubspec.yaml:65, sin borrar el archivo.
3. En una fase aparte, conectar el tier real del dispositivo a inGeCoreFlow.setPerformanceProfile para que lowPerformance funcione. Se hace con el motor único que ya existe, sin crear otro sistema de animación.

**Riesgo y pruebas.** Bajo. Hay que revisar la calidad visual en un flagship de 120 Hz y en tablet o plegable.
Qué probar:
- En un equipo Android 9 de gama baja, logcat sin AUTH_VIDEO_UNAVAILABLE ni errores de MediaCodec/ExoPlayer.
- Los vidrios se alinean con el video y el póster no produce saltos.
- La ruta animate=false (perfil de ahorro) sigue mostrando el póster.


### Gradle release sin R8/shrinkResources, profileinstaller incluido sin baseline profile, y modelo OCR coreano empaquetado

- **Veredicto:** parcial · **Impacto:** bajo · **Esfuerzo:** medio · id `gradle-release-sin-r8-ni-baseline`
- **Archivos:** `android/build.gradle:403`, `android/build.gradle:320`, `android/build.gradle:316`, `android/src/com/ingema/ingeplus/RenditionReceiptOcr.java:39`, `android/src/com/ingema/ingeplus/InGeQtActivity.java:769`, `docs/RENDICIONES_ANDROID_PAQUETE_TECNICO_WEB_20261005.md:28`

**Problema.** El DEX de release incluye completos GMS auth, ML Kit, AndroidX, el Java de Qt y el embedding de Flutter, sin reducir ni optimizar.
Como la app se instala por ADB o sideload, no recibe perfiles de la nube de Play, y profileinstaller no tiene ningún perfil que instalar. Por eso InGeQtActivity (2717 líneas), el loader de Qt y el embedding de Flutter se interpretan en cada arranque en frío hasta que el JIT calienta. Esto alarga el arranque en Android 9-12 de gama baja.
El modelo coreano empaquetado añade librerías nativas y un modelo que no hacen falta para recibos en alfabeto latino.

**Evidencia.**

```
android/build.gradle:403-753: el bloque `android { ... }` no tiene buildTypes, minifyEnabled ni shrinkResources, y no hay proguard-rules.pro en android/.
android/build.gradle:320:    implementation 'androidx.profileinstaller:profileinstaller:1.4.1'
No existe ningún baseline-prof.txt en el repo (find solo encuentra archivos de node_modules).
android/build.gradle:316:    implementation 'com.google.mlkit:text-recognition-korean:16.0.1'
RenditionReceiptOcr.java:39: recognizer = TextRecognition.getClient(new KoreanTextRecognizerOptions.Builder().build());
InGeQtActivity.java:769-770: Class.forName("org.qtproject.qt.android.QtNative") ... getDeclaredMethod("getStateDetails")
docs/RENDICIONES...:28: "Tamaño | 182.312.268 bytes"
```

**Verificación.** Lo que se confirma:
- El bloque android (líneas 403-753) no tiene buildTypes, minify ni shrinkResources.
- Línea 320: profileinstaller 1.4.1. Línea 316: text-recognition-korean, que se usa en RenditionReceiptOcr.java:39.
- Hay reflexión sobre clases de Qt en InGeQtActivity.java:769-777.
- No existe ningún baseline-prof.txt propio.

Correcciones:
(a) Los AAR de AndroidX (core 1.16.0, profileinstaller...) traen sus propios baseline profiles, y AGP los fusiona en el APK release (assets/dexopt/baseline.prof). profileinstaller sí instala algo; lo que no tiene reglas es el código de la app, de Qt y de Flutter.
(b) En una instalación por ADB el perfil lo aplica el dexopt en segundo plano. La prueba de 'speed-profile tras instalar' no es válida: hay que forzarlo con `adb shell cmd package compile -f -m speed-profile com.ingema.ingeplus`.
(c) La ruta android/src/main/baseline-prof.txt cae dentro de java.srcDirs ['src'], con un manifest en la raíz de android/, que no es la convención src/main.
(d) Con keep para Qt, la app y Flutter completos, R8 casi solo reduce GMS, AndroidX y Kotlin. El APK de 182 MB está dominado por librerías nativas y assets, así que la ganancia es pequeña y el riesgo JNI/reflexión es alto.
(e) build.gradle:315 indica que el modelo coreano se eligió para igualar al donante; cambiarlo requiere tocar el código (KoreanTextRecognizerOptions) y validar el OCR.

**Corrección de evidencia.** Añadir:
- build.gradle:315, comentario 'Same bundled on-device recognizer as flutter_receipt_scanner donor'.
- sourceSets.main con manifest.srcFile 'AndroidManifest.xml' y java.srcDirs [..., 'src', ...] (build.gradle:470-549).
- Los 11 métodos native de Java tienen sus 11 implementaciones JNIEXPORT.

**Cambio recomendado.** Prioridad 1, riesgo bajo: baseline profile propio.
- Declarar en android{} `sourceSets { main { baselineProfiles.srcDirs = ['baselineProfiles'] } }` (AGP 8.10).
- Crear android/baselineProfiles/baseline-prof.txt con reglas HSPL para com/ingema/ingeplus/InGeQtActivity, org/qtproject/qt/android/QtActivityLoader y QtNative, y io/flutter/embedding/engine/FlutterEngine.
- Validar con `cmd package compile -f -m speed-profile` y comparar INGE_STARTUP_STAGE.

Prioridad 2, en una fase aparte y con regresión completa: R8 con las keep propuestas.

OCR: evaluar el modelo latino solo con recibos reales.

**Riesgo y pruebas.** Alto para R8, por los nombres usados vía JNI y reflexión.
Qué probar en release:
- Login Supabase y multicuenta.
- Autorización de Google Drive (callback JNI nativeAuthorized).
- Callbacks JNI del dock (nativeDockPublish).
- WebView con @JavascriptInterface (Gemini/Cesium).
- Home Flutter y OCR.
- logcat sin ClassNotFoundException, NoSuchMethodError ni UnsatisfiedLinkError.
- `adb shell dumpsys package dexopt` muestra speed-profile después de instalar.
OCR: validar la precisión con recibos reales en español.


### En builds Debug, Home/Auth/Rendiciones (Flutter) corren en JIT con un AAR debug que CMake nunca regenera

- **Veredicto:** parcial · **Impacto:** bajo · **Esfuerzo:** bajo · id `flutter-aar-debug-jit`
- **Archivos:** `android/build.gradle:339`, `android/build.gradle:870`, `CMakeLists.txt:361`, `CMakeLists.txt:385`, `CMakeLists.txt:350`

**Problema.** Cuando Qt compila en Debug (el valor por defecto, ver hallazgo 1), Gradle toma flutter_debug. La pantalla Home, Auth, Rendiciones y la UI de Earth ejecutan Dart en modo JIT con asserts y cargan un kernel de 88 MB. Flutter documenta este modo como lento y no representativo. En teléfonos de gama baja se traduce en arranque de Home más lento, saltos de frames en scroll y animaciones, y mayor consumo de RAM.
Además, el comando de CMake solo regenera el AAR release (línea 385). El AAR debug que se empaqueta en Debug es el que esté en el árbol, posiblemente desactualizado respecto de lib/*.dart. Eso contradice el propósito declarado en las líneas 350-352.

**Evidencia.**

```
android/build.gradle:339:    debugImplementation 'com.ingema.inge_earth:flutter_debug:1.0'
android/build.gradle:870:    releaseImplementation("com.ingema.inge_earth:flutter_release:1.0") {
CMakeLists.txt:361-362: set(INGE_FLUTTER_RELEASE_AAR ".../flutter_release/1.0/flutter_release-1.0.aar")
CMakeLists.txt:385:                COMMAND "${INGE_FLUTTER_EXECUTABLE}" build aar --release --no-pub
CMakeLists.txt:350-352: "Evita instalar una mezcla donde QML/Java sean nuevos pero Flutter siga mostrando la interfaz anterior"
Contenido de los AAR (unzip -l):
- flutter_debug-1.0.aar (63,343,908 B) contiene assets/flutter_assets/kernel_blob.bin de 88,643,376 B e isolate_snapshot_data de 11,093,091 B, que corresponden a JIT.
- flutter_release-1.0.aar contiene jni/arm64-v8a/libapp.so de 6,292,368 B, que corresponde a AOT.
```

**Verificación.** Lo que se confirma:
- build.gradle:339 tiene debugImplementation flutter_debug.
- build.gradle:870 tiene releaseImplementation flutter_release.
- flutter_debug-1.0.aar contiene kernel_blob.bin (88,643,376 B) e isolate_snapshot_data (11,093,091 B), es decir, JIT.
- flutter_release-1.0.aar contiene jni/arm64-v8a/libapp.so (6,292,368 B), es decir, AOT.

Lo que se refuta es que el AAR debug esté desactualizado. En flutter_tools (build_aar.dart) las opciones debug, profile y release tienen defaultsTo: true. Por eso `flutter build aar --release --no-pub` (CMakeLists.txt:385) compila los tres modos, y el repo tiene flutter_debug, flutter_profile y flutter_release de la misma ejecución. CMake solo vigila el AAR release como OUTPUT, pero el mismo comando regenera los tres.

Impacto real: el APK de producción es Release, así que usa releaseImplementation y Dart AOT. El JIT solo aparece en builds Debug de desarrollo, sin efecto para los usuarios. Vale como advertencia para no medir rendimiento sobre Debug.

**Corrección de evidencia.** Quitar la afirmación 'CMake nunca regenera el AAR debug'. Para CMakeLists.txt:385, la evidencia correcta es que los flags --debug, --profile y --release valen true por defecto en `flutter build aar`; por eso existen flutter/inge_earth/build/host/outputs/repo/com/ingema/inge_earth/{flutter_debug,flutter_profile,flutter_release}/1.0/*.aar.

**Cambio recomendado.** No tocar la ruta release.

Si hace falta medir en builds no release, apuntar la variante debug al AAR profile, que es AOT y permite usar el timeline de DevTools: `debugImplementation 'com.ingema.inge_earth:flutter_profile:1.0'`. El AAR ya se genera.

Si se decide consumir solo flutter_release en todas las variantes, añadir además `--no-debug --no-profile` en CMakeLists.txt:385. Eso reduce el tiempo de build, pero solo se puede hacer cuando ninguna variante consuma flutter_debug; si no, ese AAR sí quedaría obsoleto.

**Riesgo y pruebas.** Bajo o medio. En Debug de Qt se pierden los asserts de Dart y `flutter attach`. El motor Flutter release dentro de un host debuggable es compatible.
Qué probar:
- logcat muestra el marcador HOME_READY (main_mobile.cpp observa flutterHomeActiveV60).
- Login/Auth con el video de fondo, Rendiciones, OCR, Earth/Cesium y el dock.
- Se resuelven las dependencias transitivas *_release (flutter_secure_storage_release, jni_release).
- No aparece UnsatisfiedLinkError de libflutter/libapp.


### QtLocation se importa y enlaza sin usarse, y el estilo de Controls se elige en runtime

- **Veredicto:** parcial · **Impacto:** bajo · **Esfuerzo:** bajo · id `plugins-qt-sin-uso`
- **Archivos:** `qml/Mobile/Main.qml:8`, `CMakeLists.txt:216`, `CMakeLists.txt:504`, `CMakeLists.txt:62`, `main_mobile.cpp:87`, `main_mobile.cpp:97`

**Problema.** Afecta a todos los dispositivos:
- El import de QtLocation en Main.qml obliga a cargar el plugin QML de QtLocation y libQt6Location* durante el arranque, en el camino crítico antes del primer frame. androiddeployqt además empaqueta las librerías y plugins de Location (geoservices) en el APK, aunque no se usan.
- Con la selección de estilo en runtime, el compilador no sabe qué implementación hay detrás de Button, Popup y demás. Qt recomienda importar el estilo en tiempo de compilación por rendimiento y para no desplegar estilos que no se usan.
El costo de arranque se nota más en la gama baja con almacenamiento lento.

**Evidencia.**

```
Main.qml:8: import QtLocation
No hay ningún uso de Map, MapQuickItem, Plugin, GeocodeModel ni RouteQuery en qml/Mobile (grep devuelve 0).
CMakeLists.txt:216: # Cartography is provided by InGe Earth/Cesium; no native map provider dependency.
CMakeLists.txt:504: Qt${QT_VERSION_MAJOR}::Location (dentro de target_link_libraries(AppCalicatasMobile ...)), además del find_package de las líneas 62 y 65.
main_mobile.cpp:87: qputenv("QT_QUICK_CONTROLS_STYLE", "Basic");
main_mobile.cpp:97: QQuickStyle::setStyle("Basic");
48 archivos usan el import genérico: 11 con `import QtQuick.Controls` y 37 con `import QtQuick.Controls 2.15`. No hay usos de Material ni Universal.
```

**Verificación.** QtLocation se confirma:
- Main.qml:8 tiene `import QtLocation`.
- grep de Map, MapQuickItem, Plugin, GeocodeModel, RouteModel y QGeoServiceProvider da 0 resultados; solo queda un comentario en CalicataFormPage.qml:830.
- CMakeLists.txt:504 enlaza Location.
- El escritorio está protegido por las guardas de las líneas 86 y 93 y enlaza Location en la línea 170.
Quitarlo es seguro y ahorra el dlopen del plugin QML y de libQt6Location en el arranque, además de tamaño del APK. La ganancia es modesta: decenas de ms en gama baja.

Estilo: los 48 archivos con import genérico de Controls se confirman, y no hay ningún import de un estilo concreto.

El paso 5 es incorrecto. Si se elimina QQuickStyle::setStyle("Basic") (main_mobile.cpp:97), en Android el estilo por defecto pasa a ser Material. Cualquier `import QtQuick.Controls` genérico que resuelva Qt internamente, por ejemplo las implementaciones quick de QtQuick.Dialogs que respaldan los FileDialog de Main.qml:3280, 3295 y 3317, cambiaría de apariencia y cargaría otro plugin.

**Corrección de evidencia.** Añadir:
- CMakeLists.txt:86 y 93 (guarda de escritorio)
- CMakeLists.txt:170 (Location en escritorio)
- Main.qml:3280, 3295 y 3317 (FileDialog vía QtQuick.Dialogs)
- main_mobile.cpp:87 (qputenv) y :97 (setStyle)

**Cambio recomendado.** 1. Quitar `import QtLocation` de Main.qml:8.
2. Quitar Qt::Location de CMakeLists.txt:504 y llevar Location al find_package de escritorio.
3. Mantener Positioning.
4. Cambiar los 48 imports a `import QtQuick.Controls.Basic`.
5. Conservar QQuickStyle::setStyle("Basic") (main_mobile.cpp:97) como única fuente de estilo en runtime. Solo se elimina el qputenv redundante de la línea 87, si se quiere un único mecanismo.
6. Verificar en logcat y en android-build/libs que ya no aparece libQt6Location*.

**Riesgo y pruebas.** Bajo.
Qué probar:
- La carpeta android-build/libs/arm64-v8a ya no contiene libQt6Location* ni libplugins_qml_QtLocation*.
- FileDialog (QtQuick.Dialogs), ComboBox y Popup se ven igual que antes.
- El GPS de calicata (Positioning) y el permiso de ubicación funcionan.
- logcat sin "module QtQuick.Controls is not installed".
- El tiempo QML_LOAD_BEGIN→QML_LOAD_END baja.


### PNG opacos sin necesidad, duplicados byte a byte, SVG con un PNG en base64 y fuentes Rubik empaquetadas dos veces

- **Veredicto:** parcial · **Impacto:** bajo · **Esfuerzo:** bajo · id `imagenes-sobredimensionadas-duplicadas`
- **Archivos:** `resources_mobile_ui_v2.qrc:4`, `qml/Mobile/Main.qml:1590`, `resources/ui/InGePlus_UI_Resources_PropuestaA_Fase54/fase54_iconos_reales_propuesta_a.qrc:5`, `CMakeLists.txt:698`, `resources_mobile_ui_v2.qrc:12`, `resources_mobile_ui_v2.qrc:35`, `resources_mobile_ui_v2.qrc:551`, `main_mobile.cpp:105`

**Problema.** Afecta al tamaño en todos los teléfonos. En gama baja, descomprimir un PNG de 900 KB al abrir Auth cuesta más CPU que un JPEG de 70 KB. Un SVG que envuelve un PNG obliga a QtSvg a parsear, decodificar el base64 y luego el PNG, sin ninguna ventaja vectorial.
(La memoria de GPU depende de las dimensiones decodificadas, no del tamaño del archivo; eso se controla con sourceSize en QML.)

**Evidencia.**

```
Fondos opacos:
- resources_mobile_ui_v2.qrc:4: <file alias="backgrounds/bg_auth_forest_dark_1080x2400.png">. Es un PNG RGB sin alfa de 1080x2400 y 901,874 B; lo usa Main.qml:1590-1595.
- Convertido con ffmpeg en scratch: JPEG unos 69 KB, WebP unos 32 KB.
Duplicados exactos:
- fase54...qrc:5-6: logo_ingeplus_full_dark.png y logo_ingeplus_full_light.png tienen el mismo SHA-1 (546 KB cada uno, 1600x1579 RGBA).
- CMakeLists.txt:698-703: file(GLOB_RECURSE MOBILE_EXTRA_RESOURCES ... "${MOBILE_QML_DIR}/icons/*" "${MOBILE_QML_DIR}/images/*" ...). Este glob empaqueta icons/app_logo_company.png, APP_ICON_EXPLORER.png e ICONO_APP.png, idénticos (SHA-1 e9513ccca2a5..., 244 KB cada uno), y también app_mark.png, INGEPLUS_ANDROID_ICON_EMPRESA.png y logo_oficial_ingeplus.png, idénticos (200 KB).
Branding:
- resources_mobile_ui_v2.qrc:12: app_launcher_ingeplus.svg (617,675 B) es `<svg ...><image width="1024" height="1024" href="data:image/png;base64,...`. Solo lo nombra una variable en UiV2Resources.js:10 que nadie consume.
- resources_mobile_ui_v2.qrc:35-36: brand_ingeplus_mark_premium_1024 y premium_dark_1024 (456 + 527 KB) no tienen referencias.
Fuentes:
- resources_mobile_ui_v2.qrc:551-554 empaqueta las Rubik desde flutter/inge_earth/assets/fonts/rubik, que también van en el AAR Flutter (assets/flutter_assets/assets/fonts/rubik/*.ttf). Son unos 775 KB por duplicado.
Total medido: los qrc enlazados más el glob suman 29.31 MB en 1016 archivos, con 1.29 MB en 34 grupos de duplicados exactos.
```

**Verificación.** Lo que verifiqué:
- logo_ingeplus_full_dark.png y logo_ingeplus_full_light.png son idénticos (SHA-1 017e87ef...).
- app_logo_company, APP_ICON_EXPLORER e ICONO_APP son idénticos (SHA-1 e9513ccc...).
- app_mark, INGEPLUS_ANDROID_ICON_EMPRESA y logo_oficial_ingeplus son idénticos (SHA-1 4e02f6d2...).
- bg_auth_forest_dark_1080x2400.png es un PNG RGB de 901,874 B.
- app_launcher_ingeplus.svg (617,675 B) envuelve un PNG en base64.
- Las Rubik están por duplicado.

Correcciones:
(a) El SVG solo aparece en UiV2Resources.js:10 y ningún QML importa ese JS. QtSvg nunca lo parsea, así que el costo es solo de tamaño.
(b) Convertir el fondo a JPEG apenas ahorra CPU.
(c) Cargar Rubik desde assets:/flutter_assets acopla Qt a la estructura interna del AAR Flutter para ahorrar 775 KB. La fragilidad no compensa.

Problema de runtime real que el hallazgo no vio: en Android, cuando authView es visible, Flutter Auth se dibuja encima (Main.qml:4031 llama a setFlutterAuthSurfaceV70(true), Main.qml:618-640). Debajo, el Image authBackground (Main.qml:4045-4053) decodifica de forma síncrona el PNG de 1080x2400 (unos 10 MB de textura) sin asynchronous ni sourceSize, en todas las pantallas con lado mayor de más de 1800 px (Main.qml:1585). Ese trabajo se desperdicia en el hilo GUI justo en el login.

**Corrección de evidencia.** El uso real del fondo está en Main.qml:4045-4053 (Image authBackground); el selector en Main.qml:1585-1596. app_launcher_ingeplus.svg solo lo nombra qml/Mobile/lib/UiV2Resources.js:10 y nadie importa ese archivo. El SHA-1 del logo dark/light es 017e87efea85879cad175ea27826257027049376 (los 546 KB son el tamaño, no el hash).

**Cambio recomendado.** 1. En Main.qml:4045, el Image authBackground pasa a ser `asynchronous: true` y `sourceSize: Qt.size(width, height)`. En Android, cargar source solo si el host Flutter Auth no está disponible. Así se mantiene como fallback visible si falla, sin ocultar errores.
2. Deduplicar apuntando los alias al mismo archivo, sin borrar ninguno. Confirmar antes si al logo light le falta su variante real.
3. Reemplazar el GLOB de CMakeLists.txt:698-703 por una lista explícita.
4. Sacar del qrc el SVG y los premium_1024 que no se usan.
5. JPEG para los fondos es opcional.
6. No mover la carga de Rubik a assets de Flutter.

**Riesgo y pruebas.** Bajo o medio. Que el logo light sea idéntico al dark puede ser un bug de diseño (falta la variante light): confirmarlo antes de unificar. Revisar banding de los JPEG en pantallas AMOLED en tema oscuro.
Qué probar:
- Fondos de Auth en claro y oscuro, en 720p y 1080p.
- Logos en las fichas.
- logcat sin INGE_BRAND_FONT_MISSING ni "Cannot open qrc:".
- Comparar el tamaño del APK.


## Android / Java / OEM


### El tier/presupuesto que calcula Android no llega a QML: todos los moviles arrancan con perfil 'high' (blur y efectos completos)

- **Veredicto:** parcial · **Impacto:** alto · **Esfuerzo:** medio · id `budget-android-no-llega-a-inGeCoreFlow`
- **Archivos:** `android/src/com/ingema/ingeplus/InGePerformanceRuntime.java:302`, `android/src/com/ingema/ingeplus/InGePerformanceRuntime.java:320`, `android/src/com/ingema/ingeplus/InGeQtActivity.java:1561`, `firstexperiencecontroller.cpp:57`, `qml/Mobile/Main.qml:2043`, `qml/Mobile/Main.qml:3743`, `qml/Mobile/flowcore/FlowPerformance.qml:12`, `qml/Mobile/flowcore/InGeCoreFlow.qml:159`, `qml/Mobile/flowcore/FlowAccessibility.qml:4`, `android/src/com/ingema/ingeplus/InGeQtActivity.java:895`

**Problema.** Java clasifica el equipo (ULTRA_LOW..HIGH) y deriva blurBudget/animationBudget, pero ese resultado solo lo lee la pagina Cesium. El perfil de InGeCoreFlow sale de una preferencia guardada cuyo valor por defecto es 2 => FlowPerformance.high (blurIntensity 0.72, complexBlurEnabled, reflections). Resultado: un Android Go / 2-3 GB (Galaxy A0x, Redmi A, Moto E) ejecuta el mismo vidrio/blur y animaciones que un flagship, y ademas Flutter Home recibe ese mismo perfil via String(inGeCoreFlow.performance.profile). Tampoco se respeta 'Quitar animaciones' del sistema (ANIMATOR_DURATION_SCALE=0, que algunos OEM activan en ahorro de bateria) ni el tamano de fuente del sistema: QML usa 604 font.pixelSize y FlowAccessibility.textScale queda en 1.0, mientras Flutter Home si escala con el textScaler del sistema, asi que en telefonos con fuente grande (habitual en Samsung) Home y Calicatas se ven inconsistentes.

**Evidencia.**

```
InGePerformanceRuntime.java:320-325
  return new InGePerformanceBudget(1000.0 / sustainable, sustainable,
          1.0,
          ultraLow ? 0.78 : (low ? 0.86 : (mediumHigh ? 1.08 : 1.0)),
          ultraLow ? 0.72 : (low ? 0.82 : 1.0), ...
Unico consumidor fuera de diagnostico (InGeQtActivity.java:1561-1567): public String getEarthPerformanceTier() { ... switch (runtime.deviceTier()) {  (solo Cesium)
firstexperiencecontroller.cpp:60
  return qBound(0, s.value(kPerformance, 2).toInt(), 2);
Main.qml:2043-2050
  Binding { target: Mobile.InGeCoreFlow.performance; property: "profile"
      value: app.flowPerformanceLevel >= 2 ? Mobile.InGeCoreFlow.performance.high : ...
InGeCoreFlow.qml:159  property bool lowMemoryMode: false   (nadie lo asigna)
FlowAccessibility.qml:4  property bool reducedMotion: false ; :7 property real textScale: 1.0  (nadie los asigna)
InGeQtActivity.java:895-905 onConfigurationChanged solo hace Log.i y super (fontScale esta en configChanges pero no se reenvia).
```

**Verificación.** El diagnostico es correcto. InGePerformanceRuntime solo se consume en la telemetria beta (InGeQtActivity.java:326-341, 350-353), en setState y en getEarthPerformanceTier (1562-1577, solo Cesium). Ningun .qml/.cpp lee el tier: src/core/InGeCoreContext.h:10 define su propio enum DeviceTier, pero no se alimenta desde Java. lowMemoryMode (InGeCoreFlow.qml:159), FlowAccessibility.reducedMotion y textScale no tienen ningun escritor. onConfigurationChanged (895-905) solo registra el cambio en el log. El perfil 'high' por defecto tambien se confirma, aunque llega por mas caminos que el citado. FirstExperience.qml:171 ejecuta setPerformanceLevel(2) y FirstExperience.qml:644 emite finished(...,2,2). Ademas Main.qml:3743-3747 prioriza appSettingsV41.lastPerformanceLevel, que queda persistido a 2 por persistUiStateV41 (Main.qml:1728). Por eso cambiar solo el default de firstexperiencecontroller.cpp:60 no tendria efecto, y los usuarios actuales ya tienen 2 guardado sin haberlo elegido. Sobre la fuente: el texto no pasa por FlowAccessibility. Main.qml tiene su propio fontScale (2141) y fs() (2241), que el usuario ajusta en Ajustes (3927-3929, 5447). Las APIs propuestas existen con minSdk 28: ValueAnimator.areAnimatorsEnabled() es API 26 y QJniObject esta en Qt 6.9. La propuesta tambien respeta AGENTS.md: reutiliza GraphicsCore (registrado con qmlRegisterSingletonInstance en main_mobile.cpp:203) y no crea otro motor.

**Corrección de evidencia.** Origen real del valor 2: qml/Mobile/onboarding/FirstExperience.qml:171 'experience.setPerformanceLevel(2)' y :644 'root.finished(root.languageCode, 0, 2, 2)'; Main.qml:3743-3747 (lastPerformanceLevel tiene prioridad) y Main.qml:3838 (onFinished). La escala de texto real es Main.qml:2141 'property real fontScale: 1.0' y :2241 'function fs(n) { return Math.max(9, Math.round(n * fontScale)) }', no FlowAccessibility.textScale. Mapeo: Main.qml:2043-2050, nivel 2 -> FlowPerformance.high (blurIntensity 0.72, complexBlurEnabled).

**Cambio recomendado.** 1) Exponer el tier, animatorsEnabled y fontScale desde Java a InGeGraphicsCore como Q_PROPERTY con NOTIFY, sin crear un singleton nuevo. 2) Enlazar InGeCoreFlow.lowMemoryMode con tier ULTRA_LOW y accessibility.reducedMotion con !animatorsEnabled. 3) Para el perfil por defecto: anadir en firstexperiencecontroller.cpp una clave 'experience/performance_user_set' (siguiendo el patron de migracion de kThemeSchema, lineas 40-47, sin borrar claves). Mientras no sea true, derivar el nivel del tier (ULTRA_LOW/LOW->0, MEDIUM->1, MEDIUM_HIGH/HIGH->2). Ponerla a true solo cuando el usuario cambie el nivel en Ajustes (Main.qml:5473). Quitar el valor fijo 2 de FirstExperience.qml:171/:644 y, en Main.qml:3743, ignorar lastPerformanceLevel mientras no exista la marca de eleccion explicita. 4) Fuente: usar el fontScale del sistema, acotado entre 0.9 y 1.3, como valor inicial de Main.fontScale solo si appSettingsV41.lastFontScale no fue elegido por el usuario. No usar FlowAccessibility.textScale, porque fs() no lo lee.

**Riesgo y pruebas.** Cambia el aspecto por defecto en gama baja (menos blur), asi que hay que revisar Login, Home Flutter, Perfil y el dock en un equipo de 3 GB y en uno de 8 GB. Hay que comprobar que la preferencia manual del usuario sigue prevaleciendo y se conserva en QSettings sin borrar claves. Probar con 'Quitar animaciones' activo y con fuente del sistema al 130 %, sin cortes de texto en CalicataFormPage. Despues de compilar, revisar en logcat INGE_PERFORMANCE_BUDGET y que no aparezcan errores QML de binding.


### Cesium WebView vive toda la sesion aunque este oculto y no hay onTrimMemory: Qt, Flutter y WebGL compiten por la RAM en equipos de 2-4 GB

- **Veredicto:** parcial · **Impacto:** alto · **Esfuerzo:** medio · id `memoria-earth-webview-sin-ontrimmemory`
- **Archivos:** `android/src/com/ingema/ingeplus/InGeQtActivity.java:1399`, `android/src/com/ingema/ingeplus/InGeQtActivity.java:1501`, `android/src/com/ingema/ingeplus/InGeQtActivity.java:2692`, `android/src/com/ingema/ingeplus/InGeQtActivity.java:1350`, `android/src/com/ingema/ingeplus/InGeQtActivity.java:855`, `android/src/com/ingema/ingeplus/InGeQtActivity.java:1841`

**Problema.** Despues de abrir Earth una vez, el proceso conserva hasta el final de la sesion el renderer de WebView con el contexto WebGL de Cesium, las teselas en cache y la capa hardware de pantalla completa (~10-18 MB por capa en 1080x2400-1440x3200), ademas del scene graph OpenGL de Qt y el FlutterEngine de Home. Como no se implementa onTrimMemory, ni Flutter recibe avisos de presion de memoria (FlutterActivity normalmente los reenvia y aqui el host es propio) ni se libera nada cuando el sistema lo pide. En equipos de 2-4 GB y en OEM con LMK agresivo (Xiaomi/Oppo/Vivo/Samsung gama A) eso provoca que el proceso muera en segundo plano al abrir la camara, compartir un PDF o cambiar de app, y que la vuelta sea un arranque en frio. Ademas LAYER_TYPE_HARDWARE fuerza un render a textura offscreen y una composicion extra por frame en GPUs debiles.

**Evidencia.**

```
InGeQtActivity.java:1399-1407
  private void hideDirectEarthWebView(boolean releaseBackCallback) {
      emitEarthPageVisibility(false);
      stopEarthLocationSearch();
      if (earthWebView != null) {
          final WebView hiding = earthWebView;
          hiding.onPause();
          hiding.setEnabled(false);
          fadeOutSurface(hiding, () -> hiding.setVisibility(View.GONE));
:1501 private void destroyDirectEarthWebView() { ... webView.destroy(); }  -> unico llamador: onDestroy (:2692)
:1350 webView.setLayerType(View.LAYER_TYPE_HARDWARE, null);
grep onTrimMemory|ComponentCallbacks|sendMemoryPressureWarning en android/src: 0 resultados.
:1841 homeEngine = new FlutterEngine(this, (String[]) null, false);  (motor persistente)
```

**Verificación.** Se confirma lo siguiente. destroyDirectEarthWebView (1501-1520) solo se llama en onDestroy (2692). hideDirectEarthWebView (1399-1408) deja la vista en GONE tras onPause. No hay onTrimMemory/ComponentCallbacks en android/src, y el FlutterEngine (1841) no recibe avisos de memoria porque el host no es un FlutterActivity. Hay dos imprecisiones. (a) Una vista en GONE no se dibuja, y HWUI libera la capa de un RenderNode que sale del arbol, asi que la capa HARDWARE de 10-18 MB no queda retenida mientras Earth esta oculto. Ademas, esa capa probablemente es necesaria para que clipOutPath (492-497, 1323-1328) recorte el functor GL del WebView. (b) Chromium/WebView registra sus propios callbacks de trim. El coste real es el contexto WebGL de Cesium: las texturas viven en el proceso de la app, porque el GPU de WebView es in-process, y ademas esta el proceso renderer. Falta lo mas grave para gama baja: ningun WebViewClient implementa onRenderProcessGone (grep: 0 en InGeQtActivity.java:1358 y en InGeAssistantWebHost.java:47). Desde API 26, si el LMK mata el renderer de Cesium o de Gemini Live y la app no devuelve true, el sistema mata InGe+. Mantener el WebView de Earth vivo toda la sesion aumenta justo ese riesgo en equipos de 2-4 GB.

**Corrección de evidencia.** Falta onRenderProcessGone: InGeQtActivity.java:1358 'webView.setWebViewClient(new WebViewClient() {' y InGeAssistantWebHost.java:47 'view.setWebViewClient(new WebViewClient() {'. Ninguno lo sobrescribe. La afirmacion de que la capa HW queda retenida en GONE no se sostiene.

**Cambio recomendado.** 1) Prioridad maxima: sobrescribir onRenderProcessGone(WebView, RenderProcessGoneDetail) en los dos WebViewClient. Debe devolver true, llamar destroyDirectEarthWebView() (o el equivalente del asistente), marcar earthWebViewLoaded=false y, si Earth estaba visible, recrearlo conservando pendingEarthFocusJson. 2) Para el tier LOW/ULTRA_LOW, poner earthWebView.setRendererPriorityPolicy(WebView.RENDERER_PRIORITY_BOUND, true), que es API 26, o destruirlo en el withEndAction del fade de hideDirectEarthWebView. 3) Sobrescribir onTrimMemory en InGeQtActivity: reenviar a homeEngine (getDartExecutor().notifyLowMemoryWarning(), getSystemChannel().sendMemoryPressureWarning() y getRenderer().onTrimMemory(level)), y con level >= TRIM_MEMORY_UI_HIDDEN y !earthRequested destruir el WebView de Earth. 4) No tocar setLayerType(HARDWARE) sin medir, porque probablemente sostiene el recorte del dock.

**Riesgo y pruebas.** Reabrir Earth en gama baja sera un arranque de Cesium en frio (mas lento), y hay que conservar pendingEarthFocusJson y el estado guardado. Riesgo de romper el recorte del dock si se quita la capa HW: probar los toques y el dibujo sobre el dock en Earth. Validar con 'adb shell am send-trim-memory com.ingema.ingeplus RUNNING_LOW' y 'dumpsys meminfo' antes y despues, y comprobar que Home/Auth Flutter no se rompen tras el aviso.


### Si Android mata el proceso mientras la camara externa esta abierta, la foto capturada se pierde (estado pendiente solo en memoria y en cache)

- **Veredicto:** confirmado · **Impacto:** alto · **Esfuerzo:** medio · id `camara-muerte-proceso-pierde-foto`
- **Archivos:** `permissionhelper.cpp:150`, `permissionhelper.cpp:164`, `permissionhelper.cpp:608`, `permissionhelper.cpp:664`, `permissionhelper.cpp:396`, `android/res/xml/nothing_file_paths.xml:7`, `src/graphics/InGeGraphicsCore.cpp:95`

**Problema.** La app de camara del OEM suele pedir mucha memoria, y en equipos de 2-4 GB es habitual que Android mate el proceso InGe+ mientras esta en segundo plano. Al volver, Qt arranca en frio: el callback de QtAndroidPrivate::startActivity y m_pendingCameraFilePath/targetIdx ya no existen, el resultado de la camara llega sin destino y el JPEG queda huerfano en getCacheDir()/calicata_camera, de donde el sistema puede borrarlo cuando falte espacio. El usuario en campo pierde la foto de la calicata y puede perder campos no guardados del formulario. En gama alta casi nunca ocurre, por eso pasa desapercibido en pruebas con flagships.

**Evidencia.**

```
permissionhelper.cpp:155-164
  const QJniObject cacheDir = context.callObjectMethod("getCacheDir", "()Ljava/io/File;");
  ...
  const QString cameraDir = QDir(cacheRoot).filePath(QStringLiteral("calicata_camera"));
:608 m_pendingCameraUri = createPendingCameraUri(&m_pendingCameraFilePath, &error);
:664-668
  const QString cameraUri = m_pendingCameraUri;
  QPointer<PermissionHelper> guard(this);
  emit externalPhotoActivityStarted();
  QtAndroidPrivate::startActivity(intent, kCameraActivityRequestCode, [guard, targetIdx, cameraUri](int, int resultCode, const QJniObject &) {
:396-401 ~PermissionHelper() { ... if (!m_pendingCameraFilePath.isEmpty()) QFile::remove(m_pendingCameraFilePath);
InGeGraphicsCore.cpp:111-113 window->setPersistentGraphics(false); window->setPersistentSceneGraph(false); window->releaseResources();  (Qt se recorta, Flutter/WebView no)
```

**Verificación.** Verificado. createPendingCameraUri crea el JPEG en getCacheDir()/calicata_camera (permissionhelper.cpp:155-164). El destino y targetIdx solo viven en m_pendingCameraFilePath y en la lambda capturada por QtAndroidPrivate::startActivity (608, 664-679). No hay persistencia ni recuperacion al arrancar: el grep de calicata_camera solo aparece en la linea 164, y externalPhotoActivityStarted solo conecta con GraphicsCore (main_mobile.cpp:188). Si el proceso muere con la camara abierta, cosa frecuente en equipos de 2-4 GB, el resultado se pierde y el archivo queda huerfano. El destructor (396-401) no se ejecuta cuando el proceso se mata. Una matizacion: el riesgo de perder campos del formulario es bajo, porque CalicataFormPage ya hace autosave en cada cambio (CalicataFormPage.qml:6665). Las lineas de InGeGraphicsCore.cpp son 111-113 y son correctas.

**Corrección de evidencia.** Hay autosave: qml/Mobile/pages/CalicataFormPage.qml:6665 '// P0 autosave: se emite en CADA cambio, incluso si dirty ya era true.' nothing_file_paths.xml:7 '<cache-path name="inge_camera_captures" path="calicata_camera/" />'.

**Cambio recomendado.** Igual que la propuesta. Persistir en QSettings, antes de startActivity, la ruta, targetIdx y la calicata/proyecto activos, y borrar esa clave solo en finishPhotoActivity. Al arrancar, si la clave existe y el archivo tiene tamano > 0, ofrecer adjuntar la foto mediante una senal unica, usando la clave como token de un solo uso. Mover la captura a filesDir con su <files-path> es opcional: el cache solo se purga cuando falta almacenamiento. Si se mueve, no borrar capturas antiguas sin confirmacion (regla 13).

**Riesgo y pruebas.** Riesgo de adjuntar dos veces si la ruta normal y la recuperacion coinciden: usar la clave como token de un solo uso. Probar con 'Opciones de desarrollador > No mantener actividades' y con 'adb shell am kill com.ingema.ingeplus' mientras la camara esta abierta, en Android 9 (WRITE_EXTERNAL_STORAGE) y Android 14/15. Comprobar que la galeria (OPEN_DOCUMENT) sigue funcionando y que el FileProvider sigue concediendo el URI a la camara.


### Termica y ahorro de bateria se leen una sola vez al crear la Activity y quedan fijados en el tier toda la sesion

- **Veredicto:** parcial · **Impacto:** medio · **Esfuerzo:** medio · id `termico-ahorro-bateria-estaticos`
- **Archivos:** `android/src/com/ingema/ingeplus/InGePerformanceRuntime.java:115`, `android/src/com/ingema/ingeplus/InGePerformanceRuntime.java:122`, `android/src/com/ingema/ingeplus/InGePerformanceRuntime.java:131`, `android/src/com/ingema/ingeplus/InGePerformanceRuntime.java:249`, `android/src/com/ingema/ingeplus/InGePerformanceRuntime.java:286`, `android/src/com/ingema/ingeplus/InGePerformanceRuntime.java:220`, `android/src/com/ingema/ingeplus/InGeQtActivity.java:820`, `android/assets/cesium/ui/inge-earth-ui.js:19`

**Problema.** Hay dos fallos opuestos. (a) Si el telefono arranca la app ya caliente o en ahorro de bateria, resta 2 puntos y queda en LOW o ULTRA_LOW toda la sesion, aunque luego se enfrie. Eso afecta tambien a Cesium, que lee el tier una sola vez. (b) Al reves, un equipo que arranca frio y se calienta trabajando al sol (uso tipico en campo de calicatas) sigue con presupuesto, blur y refresco maximos hasta que el SoC baja frecuencia y aparece jank. Afecta a todos los Snapdragon/Exynos/MediaTek con throttling agresivo (Samsung A/M, Xiaomi) y a los OEM que activan ahorro de bateria automatico al 15-20 %. Ademas, la telemetria de JankStats mide los frames del arbol de Views Android (FlutterTextureView/WebView) y no los del hilo de render Qt en su SurfaceView, asi que no sirve para detectar este jank en paginas Qt.

**Evidencia.**

```
InGePerformanceRuntime.java:249-250
  final int thermal = Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q
          ? powerManager.getCurrentThermalStatus() : -1;
:264  powerManager.isPowerSaveMode(), thermal,
:286-287
  if (c.powerSaveMode) score -= 2.0;
  if (c.thermalStatus >= PowerManager.THERMAL_STATUS_MODERATE) score -= 2.0;
:115 private volatile InGePerformanceBudget budget;  :122 private long budgetVersion = 1L;  :131 budget = baseBudget;  (no hay ninguna otra asignacion; grep de addThermalStatusListener / ACTION_POWER_SAVE_MODE_CHANGED / registerReceiver en android/src: 0 resultados)
:223 jankStats = JankStats.createAndTrack(window, this::recordFrame);
inge-earth-ui.js:19 qualityTier = String(window.InGeEarthConfig.getEarthPerformanceTier() || 'MID')
```

**Verificación.** Los hechos se confirman. detect() lee isPowerSaveMode() y getCurrentThermalStatus() una sola vez (InGePerformanceRuntime.java:249-250, 264), y classifyTier resta 2 puntos por cada uno (286-287). 'budget' solo se asigna en la linea 131 y budgetVersion nunca se incrementa. grep de addThermalStatusListener, ACTION_POWER_SAVE_MODE_CHANGED y registerReceiver en android/src: 0 resultados. Lo de JankStats tambien es cierto: recordFrame usa getFrameDurationUiNanos (FrameMetrics de HWUI) y no ve los frames del SurfaceView de Qt, asi que el 'estimated_fps' de emitBetaPerformanceSample es enganoso. La parte (b) esta exagerada: hoy ni el blur ni el refresco salen del presupuesto. El blur sale de flowPerformanceLevel y el refresco de currentRefreshHz (InGeQtActivity.java:954-955). Por tanto, el unico efecto real hoy es el tier de Cesium fijado al arrancar, mas la telemetria. El hallazgo solo cobra valor si se aplican el de presupuesto/perfil y el de refresco. Las APIs propuestas existen: addThermalStatusListener(Executor, ...) es API 29, getMainExecutor es API 28 y ContextCompat.registerReceiver esta en core 1.16 (android/build.gradle:313). Desactivar JankStats en release romperia la telemetria beta FRAME_WINDOW_SAMPLE.

**Corrección de evidencia.** El presupuesto no tiene consumidores para blur ni refresco: InGeQtActivity.java:954-955 usa capabilities().currentRefreshHz, y el perfil QML sale de Main.qml:2043-2050. inge-earth-ui.js:16-19 lee el tier una sola vez al cargar.

**Cambio recomendado.** Implementarlo despues del hallazgo de presupuesto/perfil y del de refresco, porque depende de ellos. 1) Sacar powerSave y thermal de classifyTier. 2) applyDynamicState(powerSave, thermal) recalcula budget desde baseBudget, incrementa budgetVersion y solo publica cuando el estado cambia. 3) Registrar en onResume y desregistrar en onPause el listener termico (con guarda SDK_INT >= Q) y el receiver de ACTION_POWER_SAVE_MODE_CHANGED. 4) Propagar a GraphicsCore (lowMemoryMode/perfil) y a Cesium con evaluateJavascript, y volver a ejecutar configureAdaptiveRefreshRate. 5) Mantener JankStats, pero etiquetarlo como 'android_views' en la telemetria, y medir Qt aparte con QQuickWindow::frameSwapped en InGeGraphicsDiagnostics.

**Riesgo y pruebas.** Riesgo bajo de regresion funcional. Comprobar que el listener se desregistra (no hay fugas al recrear la Activity) y que no se publica un presupuesto por frame, solo en cada cambio de estado. Probar con 'adb shell cmd thermalservice override-status 3/0', con 'adb shell settings put global low_power 1/0' y en Android 9 (sin API termica, debe quedarse en -1 sin crashear). En logcat revisar INGE_PERFORMANCE_BUDGET antes y despues.


### El refresco pedido usa la frecuencia actual del panel y no el presupuesto: gama baja a 90/120 Hz y flagships LTPO fijados a 60 Hz

- **Veredicto:** confirmado · **Impacto:** medio · **Esfuerzo:** bajo · id `refresco-ignora-presupuesto`
- **Archivos:** `android/src/com/ingema/ingeplus/InGeQtActivity.java:947`, `android/src/com/ingema/ingeplus/InGeQtActivity.java:954`, `android/src/com/ingema/ingeplus/InGeQtActivity.java:982`, `android/src/com/ingema/ingeplus/InGePerformanceRuntime.java:305`, `android/src/com/ingema/ingeplus/InGeQtActivity.java:895`

**Problema.** El tope por tier (60 Hz en LOW, 90 en MEDIUM) se calcula pero no se aplica. Se vota la frecuencia que el panel tenga en el instante de onCreate. En gama baja con panel rapido (Redmi Note con Snapdragon 4 Gen 1 a 120 Hz, Galaxy A14/A15 a 90 Hz, Moto G a 120 Hz), si el panel esta a 120 en ese momento, Qt y Cesium se piden a 120 Hz con una GPU que no los sostiene: mas jank, mas calor y mas bateria. En flagships con LTPO/adaptativo (Pixel, Galaxy S), si la app arranca con el panel en reposo a 60 Hz, la ventana vota 60 toda la sesion y se pierde la fluidez a 120. Tampoco se recalcula al plegar/desplegar (los modos cambian) porque onConfigurationChanged solo registra el log.

**Evidencia.**

```
InGeQtActivity.java:954-959
  preferredRefreshRateHz = performanceRuntime == null
          ? 0.0f : performanceRuntime.capabilities().currentRefreshHz;
  final android.view.WindowManager.LayoutParams params =
          getWindow().getAttributes();
  params.preferredRefreshRate = preferredRefreshRateHz;
  getWindow().setAttributes(params);
:982-984 surface.setFrameRate(preferredRefreshRateHz, android.view.Surface.FRAME_RATE_COMPATIBILITY_DEFAULT);
InGePerformanceRuntime.java:308-312
  final float refreshCeiling = tier == DeviceTier.ULTRA_LOW
          || tier == DeviceTier.LOW ? 60.0f
          : (tier == DeviceTier.MEDIUM ? 90.0f : maxRefresh);
  final float sustainable = chooseRefresh(...)   // budget.sustainableRefreshHz nunca se usa para pedir refresco
```

**Verificación.** Verificado en InGeQtActivity.java:954-959: preferredRefreshRate = capabilities().currentRefreshHz. applyPreferredFrameRateToSurfaces (982-984) aplica ese mismo valor, y se vuelve a llamar en onWindowFocusChanged (1003) y en parkFlutterView (2063), siempre con el mismo valor. El tope por tier de deriveBudget (InGePerformanceRuntime.java:308-312) nunca se usa. El comentario de las lineas 951-953 justifica no pedir valores fraccionarios, pero chooseRefresh (328-335) ya devuelve una tasa que existe en getSupportedModes(), asi que sustainableRefreshHz es un modo fisico valido. Votar la tasa del instante de onCreate es fragil en ambos sentidos: en un panel de 90/120 Hz de gama baja deja el maximo sin tope, y en LTPO puede fijar 120 (lo habitual en el arranque) o 60 toda la sesion. Las APIs existen: preferredDisplayModeId es API 23, Surface.setFrameRate(float,int,int) con CHANGE_FRAME_RATE_ONLY_IF_SEAMLESS es API 31, y la guarda R ya esta en la linea 974. Detalle que falta: capabilities es un singleton cacheado (InGePerformanceRuntime.java:156-170), asi que en plegables, al volver a ejecutar configureAdaptiveRefreshRate desde onConfigurationChanged, los modos seguirian siendo los de la pantalla inicial. El impacto real es medio: Qt solo renderiza cuando hay cambios, y el coste extra aparece en animaciones y scroll.

**Corrección de evidencia.** Tambien en InGeQtActivity.java:1001-1004 (onWindowFocusChanged) y :2063 (parkFlutterView) se reaplica preferredRefreshRateHz. InGePerformanceRuntime.java:239-245 cachea las tasas soportadas una sola vez.

**Cambio recomendado.** Igual que la propuesta, mas dos ajustes. a) En configureAdaptiveRefreshRate, volver a leer getWindowManager().getDefaultDisplay().getSupportedModes() y la resolucion fisica actual en lugar de usar las capabilities cacheadas, para que funcione en plegables. b) Para HIGH/MEDIUM_HIGH, poner preferredRefreshRate=0 y preferredDisplayModeId=0, y llamar setFrameRate(0, ...) en los SurfaceView para limpiar votos previos. Si se votara sustainable=maxRefresh en LTPO, la app quedaria fijada a 120 Hz. Mantener los logs INGE_REFRESH_REQUEST_HZ e INGE_DISPLAY_ACTIVE_HZ.

**Riesgo y pruebas.** Un preferredDisplayModeId con otra resolucion provoca un cambio de modo visible, asi que hay que filtrar por getPhysicalWidth/Height. Probar en un equipo de 60 Hz (debe quedar sin cambios), en uno de 90/120 Hz de gama baja (debe quedar en 60 constantes) y en un flagship (debe alcanzar 120 al desplazar). Medir con 'adb shell dumpsys SurfaceFlinger | grep -i refresh' y revisar los logs INGE_REFRESH_REQUEST_HZ / INGE_DISPLAY_ACTIVE_HZ.


### El GPS de Earth queda encendido indefinidamente tras la busqueda y registra 3 proveedores a 1 s en el hilo principal

- **Veredicto:** parcial · **Impacto:** medio · **Esfuerzo:** bajo · id `gps-earth-no-se-apaga`
- **Archivos:** `android/src/com/ingema/ingeplus/InGeQtActivity.java:2145`, `android/src/com/ingema/ingeplus/InGeQtActivity.java:2159`, `android/src/com/ingema/ingeplus/InGeQtActivity.java:2170`, `android/src/com/ingema/ingeplus/InGeQtActivity.java:2163`, `android/src/com/ingema/ingeplus/InGeNativeLocation.java:43`, `android/src/com/ingema/ingeplus/InGeNativeLocation.java:95`, `android/src/com/ingema/ingeplus/InGeNativeLocation.java:147`, `permissionhelper.cpp:1091`, `qml/Mobile/Main.qml:3196`

**Problema.** La busqueda 'Mi ubicacion' de Earth dura 8 s mas 15 s de refinado. Despues solo se cancelan los Runnables: el chip GPS, el fused y el de red siguen activos a 1 Hz, con callbacks en el hilo principal de Android (el mismo que entrega los toques a Qt) y un Log.i por fix, todo el tiempo que el usuario permanezca en Earth. En API 31+ fused ya combina GPS y red, asi que registrar los tres triplica el trabajo. En Android 9 (minSdk 28) no existe el permiso 'solo mientras se usa', y el PositionSource de Qt sigue pidiendo ubicacion en segundo plano porque Main.qml no lo detiene al pasar a inactivo. El resultado es un consumo de bateria notable en equipos de campo, sobre todo los de bateria pequena. LocationManager (sin GMS) esta bien elegido porque funciona en Huawei sin Google Play Services, asi que no hay que migrar a FusedLocationProviderClient.

**Evidencia.**

```
InGeQtActivity.java:2170-2173
  private void pollEarthLocationRefinement() {
      final long nowElapsed = SystemClock.elapsedRealtime();
      if (nowElapsed > locationRefineUntilMs)
          return;            // deja de sondear pero NO llama InGeNativeLocation.stop()
:2147-2149 if (bestLocationFix.isEmpty()) { emitLocationStatus("error", "No se obtuvo un fix de ubicación en 8 s"); return; }   // tampoco para
:2163-2167 stopEarthLocationSearch() { ... InGeNativeLocation.stop(); }  // solo se invoca al ocultar Earth u onPause
InGeNativeLocation.java:43-45 GPS_INTERVAL_MS = 1000L; NETWORK_INTERVAL_MS = 1800L; MIN_DISTANCE_METERS = 0.25f;
:95-99
  registered |= registerProvider(LocationManager.FUSED_PROVIDER, GPS_INTERVAL_MS);
  registered |= registerProvider(LocationManager.GPS_PROVIDER, GPS_INTERVAL_MS);
  registered |= registerProvider(LocationManager.NETWORK_PROVIDER, NETWORK_INTERVAL_MS);
:147-151 manager.requestLocationUpdates(providerName, intervalMs, MIN_DISTANCE_METERS, LISTENER, Looper.getMainLooper());
permissionhelper.cpp:1091 m_positionSource = QGeoPositionInfoSource::createDefaultSource(this);  (segunda pila GPS, 1.5 s)
Main.qml:3196-3200 if (!appActiveV41) { mapGestureBusy = false; return }  // no detiene Perms en segundo plano
```

**Verificación.** El nucleo se confirma. pollEarthLocationRefinement (InGeQtActivity.java:2170-2173) hace return al vencer locationRefineUntilMs sin llamar a InGeNativeLocation.stop(). finishEarthLocationSearch, en la rama sin fix (2147-2150), tampoco lo detiene. stop() solo se llama desde stopEarthLocationSearch (2163-2168), que se invoca en onPause (879) y en hideDirectEarthWebView (1401). InGeNativeLocation solo lo usa Earth (grep), asi que detenerlo no afecta a Calicata ni al Mapa, que usan QGeoPositionInfoSource en permissionhelper.cpp:1091. Despues de los 15 s de refinado no se emite ningun fix mas, por lo que parar es seguro. En API 31+ se registran tres proveedores a 1 s y 0.25 m (InGeNativeLocation.java:43-45, 95-99, 147-151), y consider() hace Log.i por cada fix aceptado. Lo que no se sostiene: (1) Main.qml:3193-3200 no llama a stop, pero el backend Android de Qt Positioning en Qt 6 pausa las actualizaciones al pasar a ApplicationSuspended. Ademas, en Android 10+ no se declara ACCESS_BACKGROUND_LOCATION, asi que no hay entregas en segundo plano, y Main.qml:2849-2853 ya detiene el GPS con requestGpsM0809(false). Como mucho afecta a Android 9, y hay que verificarlo con dumpsys location antes de anadir codigo. (2) Que callbacks a 1 Hz en el main looper bloqueen los toques de Qt es despreciable. El coste real es de bateria mientras el usuario permanece en Earth.

**Corrección de evidencia.** El comentario de InGeNativeLocation.java:19-23 ('PermissionHelper consulta este estado') esta obsoleto. PermissionHelper usa QGeoPositionInfoSource (permissionhelper.cpp:1091, 1149, 1172) y el unico llamador de InGeNativeLocation.start es InGeQtActivity.java:2089.

**Cambio recomendado.** 1) En pollEarthLocationRefinement, cuando nowElapsed > locationRefineUntilMs, llamar InGeNativeLocation.stop() antes del return. Hacer lo mismo en la rama de error de finishEarthLocationSearch. Es el cambio de mas valor y su riesgo es minimo. 2) En API 31+, si FUSED_PROVIDER se registra, no registrar NETWORK. Mantener GPS solo si fused no esta disponible, y conservar LocationManager para equipos sin GMS. 3) Bajar a Log.d el log de cada fix. 4) Medir primero el punto de Main.qml con 'adb shell dumpsys location' en Android 9. Si Qt ya pausa en ApplicationSuspended, no anadir codigo. Descartar el HandlerThread propio, porque su beneficio no justifica el cambio.

**Riesgo y pruebas.** La reanudacion puede tardar unos segundos mas en dar un fix fresco, aunque se muestra la ultima posicion conservada. Probar: Earth > Mi ubicacion > esperar 30 s y comprobar con 'adb shell dumpsys location' que no quedan requests de com.ingema.ingeplus. Probar tambien en Android 9 que el GPS se detiene en segundo plano y vuelve en Calicata/Mapa, y en un equipo sin GMS si hay uno disponible.


### Barras del sistema: el tema nocturno las vuelve oscuras con iconos claros sobre una UI que siempre es clara; en Android 15/16 los colores se ignoran

- **Veredicto:** parcial · **Impacto:** medio · **Esfuerzo:** bajo · id `barras-sistema-edge-to-edge-noche`
- **Archivos:** `android/res/values-night/styles.xml:4`, `android/res/values-night/styles.xml:14`, `android/res/values/styles.xml:15`, `qml/Mobile/Main.qml:2244`, `qml/Mobile/Main.qml:1707`, `android/AndroidManifest.xml:97`, `android/src/com/ingema/ingeplus/InGeQtActivity.java:1343`

**Problema.** La app fuerza siempre el modo claro (darkMode = false), pero en un telefono con el modo oscuro del sistema activado se aplica values-night: el splash de Android 12+ y la ventana previa salen en #202A36 y luego Qt pinta claro (destello), y las barras quedan oscuras sobre la UI clara. Con targetSdk 35, en Android 15/16 statusBarColor/navigationBarColor ya no tienen efecto (edge-to-edge obligatorio, barras transparentes): con windowLightStatusBar=false del tema nocturno, los iconos blancos de reloj y bateria quedan sobre #F8FAFD y no se ven. En Earth ocurre lo contrario (iconos oscuros sobre el mapa oscuro). Como uiMode esta en configChanges, al cambiar el sistema a noche (programado al atardecer en Samsung/Xiaomi) la ventana no se recrea y las barras quedan desfasadas. Solo se usa el margen inferior de SafeArea, asi que en Android 15+ y en horizontal con notch el contenido superior/lateral puede quedar bajo la barra o el recorte.

**Evidencia.**

```
values-night/styles.xml:10-15
  <item name="android:statusBarColor">#202A36</item>
  <item name="android:navigationBarColor">#202A36</item>
  <item name="android:windowLightStatusBar">false</item>
  <item name="android:windowLightNavigationBar">false</item>
  ... <item name="android:windowBackground">#202A36</item>
Main.qml:2244-2247
  function setVisualThemeMode(mode, announce) {
      themeSyncing = true
      themeMode = 0
      darkMode = false
Main.qml:1707-1708 readonly property real safeBottomInsetV49: Math.max(0.0, Qt69.SafeArea.margins.bottom)  (unico uso de SafeArea; no se usa top/left/right)
AndroidManifest.xml:97 android:configChanges="...|uiMode|...|fontScale|...|density"
InGeQtActivity.java:1343 webView.setBackgroundColor(Color.rgb(7, 17, 28));  (Earth oscuro con iconos oscuros del tema claro)
grep setAppearanceLightStatusBars|WindowInsetsController|setStatusBarColor en Java/C++: 0 resultados
```

**Verificación.** Se confirma que values-night/styles.xml:4-23 define InGePlusTheme con barras y windowBackground #202A36 e iconos claros, mientras Main.qml:2244-2247 fuerza siempre darkMode=false. Con el modo noche del sistema, la ventana previa, el splash (Android 12+) y las barras salen oscuros sobre una UI clara: es la 'barra negra' que FASE UI 24 (values/styles.xml:4-7) queria eliminar. uiMode esta en configChanges (AndroidManifest.xml:97) y no hay codigo de apariencia de barras: el grep de WindowInsetsController/setStatusBarColor/WindowCompat en Java/C++ da 0. Qt69.SafeArea solo se usa para bottom (Main.qml:1707-1708); SafeArea.margins existe en Qt 6.9. Lo que no se sostiene: que en Android 15+ los iconos blancos queden invisibles sobre #F8FAFD en las paginas Qt. Sin ExpandedClientAreaHint, Qt 6.9 coloca su contenido fuera de las barras y la franja muestra windowBackground (#202A36 en noche), asi que los iconos claros se ven. Lo que si es plausible en Android 15+ es Earth: el WebView se anade a android.R.id.content con MATCH_PARENT (InGeQtActivity.java:1383-1388) y en edge-to-edge queda bajo una barra transparente con los iconos oscuros del tema claro. Falta un punto OEM: ningun tema declara android:forceDarkAllowed=false, y MIUI/HyperOS y otros con 'modo oscuro para apps' pueden invertir las Views nativas sobre un tema Light.

**Corrección de evidencia.** Earth se adjunta en InGeQtActivity.java:1383-1388 (content.addView(webView, params)), no fuera de las barras. No hay forceDarkAllowed en android/res ni en el manifest (grep: 0).

**Cambio recomendado.** 1) Igualar values-night/styles.xml al tema claro (o eliminar el override) y anadir <item name="android:forceDarkAllowed">false</item> (API 29) al tema, para evitar el force-dark de los OEM. 2) Anadir applySystemBarAppearance(boolean lightContent) con WindowCompat.getInsetsController(...).setAppearanceLightStatusBars/NavigationBars. Llamarlo en onCreate y onConfigurationChanged, y al mostrar/ocultar Earth: iconos claros sobre el mapa y oscuros al volver a Qt/Flutter. 3) En Earth, aplicar los insets de la barra de estado (ViewCompat.setOnApplyWindowInsetsListener) a la UI superior del WebView, o pasarlos a inge-earth-ui.js. 4) SafeArea top/left/right en QML solo si se activa ExpandedClientAreaHint; sin eso los valores seran 0.

**Riesgo y pruebas.** Revisar que no reaparezca la 'barra negra' que corrigio la FASE UI 24 en Android 9-14 y MIUI. Probar en Android 9, 12, 14 y 15/16 con el modo noche del sistema activado y desactivado, en Earth y en Home Flutter, en vertical y en horizontal con notch. Comprobar que Login/Home no cambian de layout salvo el inset superior.


### Flutter se inicializa de forma sincrona en el hilo UI de Android al pedir Auth/Home; el 'prewarm' que anuncia el log no existe

- **Veredicto:** parcial · **Impacto:** bajo · **Esfuerzo:** medio · id `flutter-init-sincrona-hilo-ui`
- **Archivos:** `android/src/com/ingema/ingeplus/InGeQtActivity.java:826`, `android/src/com/ingema/ingeplus/InGeQtActivity.java:1720`, `android/src/com/ingema/ingeplus/InGeQtActivity.java:1838`, `android/src/com/ingema/ingeplus/InGeQtActivity.java:585`, `android/src/com/ingema/ingeplus/InGeQtActivity.java:1262`

**Problema.** La primera vez que QML pide la superficie Flutter (Auth al arrancar sin sesion, o Home tras el login), el hilo principal de Android carga libflutter/libapp, espera ensureInitializationComplete y crea el engine con su isolate, todo de forma sincrona. Qt sigue pintando en su hilo, pero los toques le llegan por ese mismo hilo Android, asi que la UI parece congelada. En gama baja (eMMC lenta, 4 nucleos A53) son cientos de ms y existe riesgo de ANR en arranques en frio con el sistema cargado. En flagships pasa desapercibido.

**Evidencia.**

```
InGeQtActivity.java:826-827
  android.util.Log.i("InGePerformance",
          "INGE_FLUTTER_PREWARM=SELECTIVE_IDLE");   // no hay IdleHandler ni startInitialization en onCreate
:1720-1724
  private DartExecutor.DartEntrypoint entrypoint(String functionName) {
      final FlutterInjector injector = FlutterInjector.instance();
      injector.flutterLoader().startInitialization(getApplicationContext());
      injector.flutterLoader().ensureInitializationComplete(getApplicationContext(), null);
:1838-1841 private void ensureFlutterHome() { if (homeEngine != null) return; homeEngine = new FlutterEngine(this, (String[]) null, false);
:585 activity.runOnUiThread(() -> activity.applyFlutterHomeVisibility(visible));  -> :1262 ensureFlutterHome();
```

**Verificación.** Es cierto que el log INGE_FLUTTER_PREWARM=SELECTIVE_IDLE (InGeQtActivity.java:826-827) no corresponde a ningun prewarm: no hay addIdleHandler ni startInitialization en onCreate. Tambien es cierto que la primera llamada a ensureFlutterHome (1838-1841) hace en el hilo UI todo el arranque de Flutter. Pero la causa no es entrypoint() (1720-1724): el propio constructor new FlutterEngine(context, args, false) ya ejecuta startInitialization + ensureInitializationComplete de forma sincrona y luego attachToNative (creacion del shell, la VM y el isolate). ensureInitializationCompleteAsync solo saca de ahi la carga de libflutter/libapp; la creacion del engine sigue en el hilo principal, asi que la mejora es parcial. El riesgo de ANR esta exagerado: un bloqueo de cientos de ms no llega al umbral de 5 s de entrada.

**Corrección de evidencia.** El bloqueo principal esta en InGeQtActivity.java:1841 'homeEngine = new FlutterEngine(this, (String[]) null, false);'. El constructor de FlutterEngine llama internamente a flutterLoader.startInitialization/ensureInitializationComplete, y entrypoint() (1722-1723) despues es un no-op.

**Cambio recomendado.** 1) En onCreate, despues de super.onCreate, llamar FlutterInjector.instance().flutterLoader().startInitialization(getApplicationContext()). Es asincrono, cuesta una linea y solapa la carga de libflutter con el arranque de Qt. 2) Opcional: antes de crear el engine, usar ensureInitializationCompleteAsync(appContext, null, mainHandler, callback) y crear el FlutterEngine en el callback, respetando homeRequested/homeSurfaceMode y el handoff Auth->Home V800. 3) Si se quiere un prewarm real, crear el engine en un IdleHandler tras el primer frame de Qt, y solo para tier >= MEDIUM. 4) Corregir el texto del log.

**Riesgo y pruebas.** La secuencia Auth -> Home en la misma FlutterView (handoff V800) es delicada: hay que verificar AUTH_OWNER, el multicuenta y que no aparezca QML entre ambas superficies. Medir con logcat (INGE_HOME_RENDERER_RESUMED, tiempo hasta el primer frame) en arranque en frio con y sin sesion, en un equipo de 3 GB, y revisar que no haya 'Skipped N frames' en Choreographer.


### El manifiesto declara MANAGE_EXTERNAL_STORAGE, READ_MEDIA_*, requestLegacyExternalStorage y cleartext global que el codigo no usa

- **Veredicto:** parcial · **Impacto:** bajo · **Esfuerzo:** bajo · id `manifest-permisos-almacenamiento-cleartext`
- **Archivos:** `android/AndroidManifest.xml:28`, `android/AndroidManifest.xml:29`, `android/AndroidManifest.xml:80`, `android/AndroidManifest.xml:82`, `android/res/xml/network_security_config.xml:3`, `android/src/com/ingema/ingeplus/NothingFileBridge.java:33`, `qml/Mobile/documents/NothingDocumentsRoot.qml:503`, `docsops.cpp:185`, `permissionhelper.cpp:727`

**Problema.** El selector de fotos usa OPEN_DOCUMENT/GET_CONTENT, la camara escribe en almacenamiento propio y la raiz de Documentos es el directorio especifico de la app, asi que ninguno de esos permisos se usa (el unico boton que pide 'All files access' esta oculto). Aun asi tienen coste: Play rechaza MANAGE_EXTERNAL_STORAGE y READ_MEDIA_* sin un uso principal justificado; en Xiaomi/HyperOS, ColorOS y Samsung se listan como permisos sensibles o 'Acceso a todos los archivos' en ajustes; requestLegacyExternalStorage solo cambia el comportamiento en Android 10 y crea una ruta distinta a la de los demas. Ademas hasAccess() devuelve true en API < 30 sin comprobar nada. Por ultimo, el cleartext global junto con la confianza en CAs instaladas por el usuario (comun en moviles con MDM corporativo u OEM) permite interceptar el trafico de Supabase/AuthSession aunque la app no usa ninguna URL http://.

**Evidencia.**

```
AndroidManifest.xml:28-31
  <uses-permission android:name="android.permission.READ_MEDIA_IMAGES"/>
  <uses-permission android:name="android.permission.MANAGE_EXTERNAL_STORAGE"/>
  <uses-permission android:name="android.permission.READ_MEDIA_VIDEO"/>
  <uses-permission android:name="android.permission.READ_MEDIA_VISUAL_USER_SELECTED"/>
:80 android:usesCleartextTraffic="true"   :82 android:requestLegacyExternalStorage="true"
network_security_config.xml:3-7 <base-config cleartextTrafficPermitted="true"> ... <certificates src="user"/>
NothingFileBridge.java:34 return android.os.Build.VERSION.SDK_INT < 30 || android.os.Environment.isExternalStorageManager();
NothingDocumentsRoot.qml:503-507 NothingButton { ... text: "PERMISO"  visible: false  onClicked: files.requestStorageAccess() }
docsops.cpp:185 base = QStandardPaths::writableLocation(QStandardPaths::DocumentsLocation);  (en Qt 6 Android: directorio propio de la app)
permissionhelper.cpp:727-728 buildPickerIntent(QStringLiteral("android.intent.action.OPEN_DOCUMENT"), true);  (SAF, sin READ_MEDIA)
grep "http://" en qml/src/android/src/Cesium UI: 0 resultados
```

**Verificación.** Se confirma lo siguiente. El manifiesto declara READ_MEDIA_IMAGES/VIDEO/VISUAL_USER_SELECTED y MANAGE_EXTERNAL_STORAGE (AndroidManifest.xml:28-31), mas usesCleartextTraffic=true (80) y requestLegacyExternalStorage=true (82). El unico camino de 'All files access' es NothingFileBridge.requestAccess, llamado desde un boton con visible:false (NothingDocumentsRoot.qml:503-507). hasAccess() devuelve true si SDK < 30 (NothingFileBridge.java:34). La galeria usa OPEN_DOCUMENT y el modulo Flutter no tiene plugins de almacenamiento (pubspec: local_auth, flutter_secure_storage, video_player). Sobre la red: Qt obtiene sus CAs con QtNative.getSSLCertificates, que usa el TrustManagerFactory por defecto; en Android 7+ ese factory sigue base-config, que incluye src="user". Por eso quitar 'user' si afecta a Supabase/AuthSession (QNetworkAccessManager), ademas de a los WebView de Cesium y de Gemini Live (wss). El flag de cleartext, en cambio, Qt no lo consulta. Una matizacion: QStandardPaths::DocumentsLocation en Android 9 (minSdk 28) puede apuntar al Documents publico, asi que hay que conservar READ (maxSdk 32) y WRITE (maxSdk 28). El hallazgo afecta mas a cumplimiento con Play, seguridad y la presentacion en ajustes de los OEM que al rendimiento entre moviles, por eso baja de prioridad.

**Corrección de evidencia.** docsops.cpp:183-185, cuyo comentario dice 'Evita Android/data/<package>/files y usa Almacenamiento interno/Documents': la intencion original era almacenamiento publico. nothing_file_paths.xml:8 conserva <external-path ... Documents/InGePlusProyectos/>. network_security_config.xml:10-20 tambien permite cleartext por dominio (supabase.co, ingema.pe, etc.).

**Cambio recomendado.** 1) Quitar MANAGE_EXTERNAL_STORAGE, READ_MEDIA_IMAGES/VIDEO/VISUAL_USER_SELECTED y requestLegacyExternalStorage. Mantener READ_EXTERNAL_STORAGE maxSdk 32 y WRITE maxSdk 28. Antes, verificar en Android 9 y 10 donde resuelve DocumentsLocation y que las carpetas existentes de la cuenta siguen visibles, sin mover ni borrar datos (regla 13). 2) Eliminar el boton oculto y hasAccess/requestAccess, o hacer que hasAccess compruebe READ/WRITE en API < 30. 3) En network_security_config: base-config cleartextTrafficPermitted="false" con solo <certificates src="system"/>, mover src="user" a <debug-overrides>, quitar el domain-config de cleartext y quitar android:usesCleartextTraffic. Probar el login de Supabase, las teselas, Cesium y Gemini Live, y comprobar con 'aapt dump permissions' el APK final.

**Riesgo y pruebas.** Verificar en Android 9 y 10 que Documentos sigue listando la carpeta de la cuenta, que la exportacion a PDF/XLSX y 'Guardar en galeria' funcionan, y que las teselas OSM/Google/Cesium cargan por https. Probar en un dispositivo con una CA de usuario instalada que la app sigue conectando a Supabase solo con CAs del sistema. Revisar que los proveedores de Flutter (AAR) no requieran esos permisos: 'aapt dump permissions' sobre el APK final.

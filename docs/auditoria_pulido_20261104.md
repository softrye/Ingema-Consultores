# Auditoría estática de pulido — 2026-11-04 (Probador)

Alcance: Home, Dock, Rendiciones, Drive/Documentos y Earth. Quedan fuera `pages/`, Login/AuthSession y `settings/`.
Herramientas:
- `qmllint` de Qt 6.9.3 con `-I C:/InGeBuild/A37`.
- Comparación de las rutas de CMake y QRC con los archivos reales.
- Lectura de la tabla de caracteres (cmap) de las fuentes Lucide-w300 y MaterialIcons.
- `grep` de textos.
No modifiqué código.

## P1 — se ve roto
1. **Modo edición del Home: al arrastrar, las fichas se pisan y se salen de pantalla.** Se observó en el video 20261103-1533, entre 0:15 y 0:25. Está en `HomeScreen.qml`, en la cuadrícula y el arrastre de fichas, cerca de la ficha en 3407-3460. Arreglo: colocar las fichas en una cuadrícula fija con un hueco de destino visible, que las demás se aparten con animación y que el tamaño quede limitado al ancho.

## P2 — texto y coherencia
2. **El saludo se corta con «…».** El texto (`HomeScreen.qml:1038-1048`) muestra como máximo 2 líneas y corta el final, y las frases de la IA aceptan hasta 110 caracteres (`HomeScreen.qml:750-760`), así que salen cosas como «Engineering a better wo…». Arreglo: limitar cada línea de `cleanPhrases` a unos 28 caracteres o usar `fontSizeMode: Text.Fit` con un tamaño mínimo.
3. **Textos en inglés en una app en español:**
   - Saludo local «Welcome back, … What's new to do today?» (`HomeScreen.qml:747-748`).
   - «Welcome back,», «Welcome to InGe+,» y «Engineer» (`Main.qml:102-105`, `Main.qml:782`).
   - «Track your reports» (`renditions/RenditionsHome.qml:152`).
   Las frases de la IA también llegan en inglés.
   Arreglo: o se pasan al español, o se documenta que el inglés de bienvenida es una decisión de marca (`src/core/OnboardingState.h:13` lo menciona).
4. **El nombre de la ficha se corta a «InGe Dri… / Gestión de…»** con tamaño Normal (video 20261103). Está en `HomeScreen.qml:3448-3460`, que limita a 1 o 2 líneas y corta el final. Arreglo: un nombre corto («Drive»), o `Text.Fit` con tamaño mínimo para la ficha.
5. **En el modo edición del Home, la × invade la ficha vecina y en «Solo icono» hay dos cascos iguales imposibles de distinguir** (video 20261103). Está en `HomeScreen.qml`, en el delegado de ficha. Arreglo: la × dentro de la esquina de la propia ficha y un rótulo corto durante la edición.
6. **`resources.qrc` tiene 14 entradas que apuntan a archivos que no existen**, entre ellas `qml/Mobile/pages/LoginPage.qml` (`resources.qrc:74`), AppShell, HeaderBar, BottomNav y FlowIconButton. Solo afecta al target de escritorio AppCalicatasDemo (`CMakeLists.txt:140`, 250-251), pero incumple la regla 12. Arreglo: quitar esas entradas del QRC de escritorio.

## P3 — limpieza
7. **Se combina una animación «on» con un binding en la misma propiedad:**
   - `renditions/RConfetti.qml:37`
   - `renditions/REditableTile.qml:60`
   - `renditions/RendicionesSyncStars.qml:46`, 73 y 124
   Arreglo: dar un valor inicial fijo, o controlar la animación con `running` sin un binding sobre la propiedad animada.
8. **Propiedades `var` usadas como función:**
   - `RetroplasmaEarthView.qml:62` (`otherGpsClientActive`)
   - `renditions/RPackedLayout.qml:49` y 51 (`spanOf`)
   Arreglo: convertirlas en `function`.
9. **Imports sin usar:** `HomeScreen.qml:7`, `AddToolPanel.qml:2`, `GlassSurface.qml:2`, `renditions/FilesBrowser.qml:2`, `renditions/RenditionReceived.qml:2`, `renditions/RenditionReview.qml:2`, `renditions/ReviewPanel.qml:2` y `documents/NothingDocumentsRoot.qml:11`. Arreglo: borrarlos.
10. **Botón «OK» en inglés** (`CalicataSaveOpenDialog.qml:317`). Arreglo: cambiarlo por «Aceptar».
11. **Acceso frágil `parent.parent.key`** (`renditions/ExpenseEditor.qml:1258-1260`): si cambia el anidamiento, sale `undefined`. Arreglo: usar `modelData.key` o una propiedad `required`.
12. **`qmllint` ve un `InGeCoreFlow` antiguo en A37.** Marca como inexistentes `advancedMotion`, `hero`, `extremeMotion`, `pressHighlight`, `sheetOriginGel` y `liquidGlassMaterial`, que sí están en el código fuente (`flowcore/InGeCoreFlow.qml:108`, 118). Eso indica que la build A37 es anterior al código actual. Arreglo: recompilar antes de la validación real.
    El resto de avisos de `qmllint` (1346 `unqualified` y unos 140 `missing-property` sobre `QObject` o `QQuickItem`) son accesos dinámicos ya protegidos con comprobaciones `!== undefined` (por ejemplo `HomeScreen.qml:1183-1201`). No los cuento como fallos.

## Verificado sin incidencias
- CMake: sus 127 rutas existen (`CMakeLists.txt:582-720`), y todos los `.qml`/`.js` que hay en disco, salvo los de `pages/` y `settings/`, están listados.
- No hay ningún `qmldir`. Hay una sola estrategia de registro, `qt_add_qml_module` (`CMakeLists.txt:773`).
- No queda ninguna referencia a `RenditionsDock.qml`, que fue borrado.
- `resources_mobile_brand.qrc` y `resources_mobile_calicatas.qrc` no tienen entradas que falten.
- Iconos: los 77 glifos del Dock (`HomeScreen.qml:1906-1941`) y los 392 códigos de carácter escritos a mano existen en Lucide-w300 o en MaterialIcons, así que ninguno sale como cuadro. Todos los nombres `earth.*` y `renditions.*` tienen su glifo asignado.
- Los logs de build de A37 no tienen avisos.

## No comprobable en estático
- Bucles de binding y avisos de ejecución: requieren logcat, y este encargo no autorizó ADB.

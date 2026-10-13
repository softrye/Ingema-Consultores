# Sistema de diseño INGEMA en InGe+ (2026-10-06)

Identidad visual corporativa oficial de Ingema Consultores aplicada a InGe+
Android (QML/Qt, Flutter Add-to-App y la IA en React/WebView). Este cambio es
**solo visual**: no modifica lógica, flujos, Auth, Supabase, sincronización,
GPS, exportaciones, cámara, Gemini ni el puente WebView.

## 1. Fuente

*Manual Corporativo Ingema 2025* (`Dropbox/02_MANUAL_DE_MARCA/Manual Corporativo
Ingema 2025.pdf`). Secciones normativas usadas:

- **05 Elementos gráficos → Colores** ("Colores corporativa"): paleta de la app.
- **05 Elementos gráficos → Tipografías**: Rubik.
- **04 Construcción de logomarca → Usos correctos / incorrectos**: versiones
  responsive para App y espacios reducidos, versión negativa sobre fondos de
  color, no sombras, no distorsión, no colores fuera de la paleta y no perder
  legibilidad.

## 2. Paleta oficial utilizada

| Token | HEX | RGB | CMYK (manual) |
|---|---|---|---|
| INGEMA Deep | `#151A30` | 21, 26, 48 | 99, 88, 47, 64 |
| INGEMA Navy | `#1C2D50` | 28, 45, 80 | 99, 83, 39, 37 |
| INGEMA Blue | `#0654A2` | 6, 84, 162 | 95, 67, 1, 0 |
| INGEMA Green | `#486426` | 72, 100, 38 | 73, 38, 100, 31 |

No se añadieron colores de marca. Los valores marcados como *derivados* son
mezclas de un color oficial con blanco o negro, o el mismo color con alpha. Solo
existen para cumplir contraste WCAG:

| Derivado | Valor | Origen | Uso |
|---|---|---|---|
| `ingemaDeepShade` | `#111527` | Deep + 18 % negro | fondo agrupado Dark |
| `ingemaBlueTint` | `#8FB2D5` | Blue + 55 % blanco | acento/enlace en Dark (6.2:1 sobre Navy) |
| `ingemaGreenTint` | `#ADB99D` | Green + 55 % blanco | éxito/acento en Dark (6.6:1 sobre Navy) |
| `ingemaBlueWash` | `#EBF1F8` | Blue 8 % sobre blanco | contenedor info/selección Light |
| `ingemaGreenWash` | `#EDF0E9` | Green 10 % sobre blanco | contenedor éxito Light |
| `blue100` / `blue050` | `#DCE7F2` / `#F0F5F9` | Blue 14 % / 6 % | lavados de fondo |
| `ingemaInkSecondary` / `Tertiary` | `#575A6A` / `#656876` | Deep 72 % / 66 % sobre blanco | texto secundario Light |
| `ingemaPaperSecondary` / `Tertiary` | `#C2C3C9` / `#989AA4` | blanco 74 % / 56 % sobre Deep | texto secundario Dark |

## 3. Tipografía

**Rubik** (SIL Open Font License 1.1). Archivos estáticos oficiales v2.300 de
`github.com/googlefonts/rubik` (commit `9167c98`, última versión publicada con
estáticos). La licencia está en `OFL.txt` junto a los archivos.

| Peso | Archivo | Uso |
|---|---|---|
| Rubik SemiBold (600) | `Rubik-SemiBold.ttf` | títulos, encabezados y botones principales |
| Rubik Regular (400) | `Rubik-Regular.ttf` | cuerpo, inputs, menús, tablas y labels |
| Rubik Light (300) | `Rubik-Light.ttf` | solo texto secundario grande (≥ 16 px) con contraste ≥ 4.5:1 |

Hay **una sola copia física**, en `flutter/inge_earth/assets/fonts/rubik/`.
Flutter exige que sus assets estén dentro del paquete; Qt y la IA web referencian
la misma carpeta:

- Qt: `resources_mobile_ui_v2.qrc` → `qrc:/ui/v2/fonts/rubik/*.ttf`.
  `main_mobile.cpp` registra los tres pesos antes de crear el motor QML y fija
  Rubik como fuente de la aplicación (`QGuiApplication::setFont`). FreeType
  agrupa los tres archivos bajo la familia tipográfica "Rubik" (nameID 16), así
  que `font.bold: true` resuelve a SemiBold (600) sin negrita sintética. Por eso
  no hubo que reescribir los cientos de `font.bold` existentes.
- Flutter: `pubspec.yaml` declara `family: Rubik` con pesos 300/400/600 y
  `ThemeData.fontFamily: IngemaBrand.fontFamily`.
- IA web: `@font-face` en `liquid-glass.scss`. Vite empaqueta los TTF como assets
  del mismo origen, compatibles con la CSP `default-src 'self'`.

## 4. Mapeo semántico de tokens

| Semántica | Light | Dark |
|---|---|---|
| Fondo general | neutros existentes `#FAFAFA` / `#F4F4F2` | Deep `#151A30` |
| Superficie | `#FDFDFD` / `#FFFFFF` | Navy `#1C2D50`, elevada `#334262` (Navy + blanco 10 %) |
| Texto principal | Deep `#151A30` | `#F6F6F7` |
| Texto secundario | `#575A6A` | `#C2C3C9` |
| Estructura (`structure`) | Navy `#1C2D50` | Navy `#1C2D50` |
| Acción primaria rellena (`actionPrimary`) | Blue `#0654A2` + blanco (7.5:1) | Blue `#0654A2` + blanco |
| Selección / foco / enlaces (`accent`, `focus`, `link`) | Blue `#0654A2` | Blue tint `#8FB2D5` |
| Acento corporativo (`accentSecondary`) | Green `#486426` | Green tint `#ADB99D` |
| Éxito (`success`) | Green `#486426` | Green tint `#ADB99D` |
| Advertencia / error | semánticos conservados (`#9A6300`, `#B83B45`) | (`#E9B95F`, `#FF8A91`) |
| Overlay / scrim | Deep con alpha 0.18 / 0.47 | Deep shade con alpha 0.40 / 0.68 |

## 5. Light Mode

Mantiene los fondos neutros claros existentes. El texto pasa a Deep, la
estructura a Navy y la acción, selección y foco a Blue. Green se usa como acento
y para estados positivos. Los bordes y separadores son Navy al 10–14 % sobre
blanco (`#DFE2E6`, `#E8EAEE`).

## 6. Dark Mode

Base Deep y superficies Navy, elevadas por mezcla con blanco. Texto blanco de
alta legibilidad. **Nunca se usa Blue `#0654A2` ni Green `#486426` como texto
sobre Navy/Deep** (2.3:1 y 2.6:1). En su lugar van sus tintes derivados. Blue
`#0654A2` se mantiene como relleno de la acción primaria con texto blanco.

> Estado actual: `FlowTheme.setMode()` mantiene la app bloqueada en Light. Es
> una decisión previa a esta tarea y no se cambió. Los tokens Dark quedan
> definidos y coherentes para cuando Configuración y temas lo habilite.
> InGeDrive y Calicatas tienen modo oscuro propio y ya consumen estos valores.

## 7. Liquid Glass

No se eliminó ni sustituyó nada: shaders (`liquidglass.frag`), blur,
refracción, dispersión cromática, highlights, specular, rim, opacidades,
sombras y animaciones son los mismos. Solo cambian los **tintes**:

- `FlowTheme.glassClear/Regular/Emphasized` Dark: Deep/Navy con alpha
  (0.46 / 0.58 / 0.72). En Light se conservan bases blancas luminosas para
  legibilidad.
- `glassTint`: Blue con alpha 0.05 (Light) / 0.09 (Dark).
- `glassShadow`, scrims y velos: Deep con alpha.
- Dock (`GlobalContextDock`), Calicatas (`CalicataLiquidGlass`, popups del
  formulario, peek del editor, revisión y selector de punto) y
  `FlowGlassSurface` comparten los mismos tintes derivados de Deep.
  `tests/calicatas/glass_calicatas_static.cjs` sigue verificando que son
  idénticos entre superficies.
- El `fallbackGlass` opaco de Calicatas conserva su neutro original: es el
  respaldo cuando no hay captura y lo fija el test anterior.
- Los colores de dispersión cromática (`#FF5E8B` / `#55D7FF`) son un efecto
  óptico del vidrio, no identidad, y se conservan.

## 8. QML

Fuente única: **`qml/Mobile/flowcore/FlowColors.qml`**, expuesta como
`InGeCoreFlow.colors`. Contiene `ingemaDeep`, `ingemaNavy`, `ingemaBlue`,
`ingemaGreen` y sus derivados. Los nombres históricos (`navy900`, `blue700`,
`cyan500`…) resuelven a la paleta INGEMA.

- `FlowTheme.qml` deriva toda la semántica de `FlowColors`: `brandDeep`,
  `brandNavy`, `brandBlue`, `brandGreen`, `actionPrimary`, `onActionPrimary`,
  `structure`, `onStructure` y `link`, además de los tokens existentes.
- `FlowTypography.qml`: `family: "Rubik"` y `lightWeight`.
- `InGeCoreFlow.navy/blue/interfaceBlue/cyan/teal/green` son alias de
  `FlowColors`. `scrimColor()` deriva de Deep.
- `FlowButton` primario usa `actionPrimary`/`onActionPrimary`.
  `FlowFocusRing` y `FlowBusyIndicator` usan `focus`/`accent`.

## 9. Flutter

Fuente única: **`flutter/inge_earth/lib/ingema_brand.dart`** (`IngemaBrand`),
con los mismos valores que `FlowColors.qml`. `InGePalette` (Auth/Seguridad) e
`InGeHomePalette` (Home) derivan de `IngemaBrand`. `ThemeData` usa
`fontFamily: 'Rubik'` y un `ColorScheme` con `primary` Blue y `secondary`
Green. En Home: tarjetas de módulo (Calicatas Green, Documentos Blue, InGe Earth
Navy, Rendición Deep), enlaces Blue, acciones rápidas Green y la tipografía de
`home_final.dart` en SemiBold/Regular.

## 10. React / WebView (InGe+ IA)

`android/web/inge-ai/src/inge/liquid-glass.scss` define `--ingema-deep`,
`--ingema-navy`, `--ingema-blue`, `--ingema-green`, `--action` y `--on-action`.
Los valores por defecto (`--text`, `--muted`, `--accent`, `--glass`,
`--shadow`) reproducen `FlowTheme` Light. En ejecución, `Main.qml →
assistantVisuals()` sigue publicando los tokens vivos de InGeCoreFlow; como
estos ya derivan de INGEMA, la IA queda sincronizada sin otro sistema. El botón
de envío usa `--action` (Blue + blanco en cualquier modo). Pesos: h1/h2 600.

## 11. Secciones modificadas

| Sección | Archivos |
|---|---|
| Tokens / tipografía | `FlowColors.qml`, `FlowTheme.qml`, `FlowTypography.qml`, `InGeCoreFlow.qml`, `main_mobile.cpp`, `resources_mobile_ui_v2.qrc`, `pubspec.yaml`, `ingema_brand.dart`, `assets/fonts/rubik/*` |
| Login / Auth / cuentas / perfil / toast / sesión | `Main.qml`, `home.dart` (`InGePalette`, bienvenida, pill de cuenta) |
| Home | `home.dart`, `home_final.dart`, `Main.qml` (tarjetas QML de respaldo) |
| Navegación global / Dock / menús contextuales | `GlobalContextDock.qml`, `FlowQuickBubble.qml` |
| Botones, inputs, foco, loaders | `FlowButton.qml`, `FlowFocusRing.qml`, `FlowBusyIndicator.qml`, `Main.qml` (`PrimaryButton`, `AuthInlineField`, `LoginField`), `FlowProgressRing.qml`, `FlowThreeBalls.qml` |
| Liquid Glass | `FlowTheme.qml`, `FlowGlassSurface.qml`, `GlobalContextDock.qml`, `CalicataLiquidGlass.qml` |
| InGeDrive | `NothingDocumentsRoot.qml`, `NothingEntry.qml`, `NothingButton.qml`, `NothingIcon.qml` (acento rojo Nothing a INGEMA Blue, monospace a Rubik, Dark sobre Deep/Navy, gris `#808080` a texto terciario legible) |
| Calicatas | `CalicataFormPage.qml` (paleta `c*`), `CalicatasEditorPage.qml` (estados, peek, GPS, overlay), `CalicataReview.qml`, `CalicataPointPicker.qml` |
| IA | `liquid-glass.scss` |
| Primera experiencia | escenas QML: cian `#27B9DC` (fuera de paleta) a Blue tint y `#496426` (error tipográfico) a Green oficial `#486426` |

**No tocados:** Rendiciones (`flutter/inge_earth/lib/renditions/**`, su
`rendition_theme.dart`; solo hereda Rubik por el `ThemeData` global), InGe
Earth (`android/assets/cesium/**`, `inge_earth_glass.dart`), los labs, el mapa
(`MapNativePage`), las páginas QML heredadas que `Main.qml` ya no carga
(`HomePageContent`, `LoginPageForm`, `RegisterPageForm`, `AppShell`, `HeaderBar`,
`BottomNav`, `Phase54CalicataOverview`, `MapPageContent`) y las ilustraciones SVG.

## 12. Hardcodes conservados y motivo

- **Error / advertencia**: `#B83B45`, `#FF8A91`, `#9A6300`, `#E9B95F`,
  `#D9483B`, `#B4232E`, `#DE7A12`/`#FFB35C` (estado "sugerido", "borrador",
  "pendiente"), "observado" y "conflicto". Son semántica de interfaz y
  accesibilidad.
- **Datos técnicos**: colores de suelo, estratos y clasificación SUCS/AASHTO
  (`#C9D8C0`, `#C7CAD9`, `#E7E7E4`, marrones de muestras) y el respaldo de
  estrato `#E7E7E4`.
- **Fotografía / visor**: backdrop del visor de fotos (`#F20A0D12`) y velos
  blancos sobre fotos.
- **Ópticos del vidrio**: blancos de highlight/specular/rim, dispersión
  cromática y el `fallbackGlass` opaco de Calicatas.
- **OLED** de InGeDrive (`#000000`): es una opción funcional del usuario.
- **Fondos neutros Light** existentes (`#FAFAFA`, `#F4F4F2`, `#F7F7F5`,
  `#FCFCFC`, `#F6F8FB`).
- **Sombras negras** de baja opacidad.
- **Valores por defecto** de componentes que siempre reciben el color del
  llamador (`CalicataReview`, `CalicataProfile`, `CalicataOperationOverlay`).
- **Assets** (SVG de onboarding, ilustraciones de Home e imágenes de marca).
  No se recolorearon.

## 13. Inconsistencia detectada en el manual

La página **"Cromatismo"** (04 Construcción de logomarca) repite cuatro veces
el mismo color **`#2F2D3D` / Pantone 532C** (RGB 47, 45, 61; CMYK 81, 74, 48,
55) como cromatismo de la logomarca. La página **"Colores"** (05 Elementos
gráficos) define cuatro colores distintos: `#151A30`, `#1C2D50`, `#0654A2` y
`#486426`. Por decisión del proyecto, la UI toma como norma **"Elementos
gráficos → Colores"**. `#2F2D3D` no se usa como token de la UI. Se recomienda
que Diseño corrija o aclare la página de cromatismo.

## Logomarca

- InGe+ usa sus recursos existentes sin redibujar, recolorear, distorsionar ni
  añadir sombras: `logo_oficial_ingeplus_light/dark.png` según el modo,
  `ingeplus_mark_light.png` (isotipo responsive) en Auth y lanzadores
  `app_launcher_ingeplus*`.
- La logomarca completa de INGEMA (`logo_ingema_full_*.png`) aparece en la
  escena final del onboarding sobre una tarjeta clara (versión positiva
  correcta).
- **No existe en el repositorio una versión negativa/blanca oficial de la
  logomarca INGEMA.** Los archivos `logo_ingema_full_dark.png` y
  `logo_ingema_full_light.png` son idénticos (positivos). No se inventó ninguna
  versión. Si se requiere el logo sobre Deep/Navy, Diseño debe proveer el
  negativo oficial.

## Validación (estática, sin compilar)

- `qmlformat` (parseo) en los 48 QML modificados: OK. `qmllint` en
  `FlowColors`, `FlowTheme` y `FlowTypography`: sin avisos.
- `dart analyze` en `ingema_brand.dart`, `home.dart` y `home_final.dart`: solo
  un aviso previo (`unused_element_parameter`), que también aparece sin los
  cambios.
- IA: `tsc --noEmit` OK; `npm test` 24/24; `vite build` con `--outDir` en un
  directorio temporal emitió los tres Rubik y la CSS con `font-family: Rubik`.
- `rcc --list resources_mobile_ui_v2.qrc`: rutas Rubik resueltas.
- Tests estáticos Node (`tests/calicatas`, `documents`, `nothing-files`,
  `inge-core`): todos pasan salvo dos fallos previos y ajenos a esta tarea:
  `review_export_static.cjs` (espera `setIngeCoreAvailable(false)`) y
  `beta21_calicatas.cjs` (`writeProfile` en C++).
- No se ejecutó CMake, Gradle, Flutter build, APK/AAB ni ADB.

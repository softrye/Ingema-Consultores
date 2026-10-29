# FusionBridge Native — entrega de código, 2026-10-13

MapLibre fue retirado del flujo principal. FusionBridge está integrado en las
fuentes de la APK principal, con detector y prueba visual MediaProjection.
**La integración interactiva del globo original sigue BLOCKED.** No se ha
compilado Android, instalado APK, ejecutado ADB ni validado logcat, por
instrucción explícita del usuario. No hay ningún `PASS_ANDROID`.

## 1. Respaldo y trazabilidad

Respaldo externo al proyecto:
`C:/Users/PC-02/Documents/InGePlus/_backups/fusionbridge_native_20261013_before/`.
Contiene `source/` y `manifest.json`, 3634 archivos verificados con SHA-256.
Se excluyeron builds, node_modules, .gradle, .cxx, __pycache__ y respaldos anidados;
no se trabajó sobre artefactos de compilación. La copia incluye los restos Git
anteriores y mantiene secretos locales fuera de los logs.

El `.git` inicial solo tenía una referencia
`refs/heads/codex/cleanup-current-android` hacia un objeto inexistente, sin HEAD
ni base de objetos utilizable. Se inicializó Git en este checkout, se conservó
el estado fuente como `a7f0ea7`, y se retiró únicamente la referencia inválida
(su copia permanece en el respaldo). No se pudo recuperar historial anterior.

- Base reversible: `a7f0ea7` — snapshot source before FusionBridge Native.
- Fase MapLibre: `6c724ec` — retire MapLibre navigation and packaged assets.
- Fase FusionBridge: commit posterior de esta entrega; consultar `git log -3 --oneline`.

Para revertir, revisar `git diff a7f0ea7..HEAD` y restaurar SOLO los hunks de
esta tarea o revertir los commits de fase, preservando cualquier trabajo nuevo.
No copiar archivos completos de un respaldo antiguo sobre cambios posteriores.

## 2. Qué se retiró de MapLibre

- `EARTH_ENGINE_MAPLIBRE`, su URL y selección de motor en `InGeQtActivity`.
- Sobrecarga `showEarthViewer(II)`, insets MapLibre, cola de comandos y los
  `evaluateJavascript` de `InGeEarth.command`, `setInsets` y `handleBack`.
- `PermissionHelper.openEarthViewer`, `earthCommand`, `closeEarthViewer`.
- Texto MapLibre/OpenFreeMap, apertura automática de WebView y preset antiguo
  de GPS/búsqueda/capas/vista global/inclinación/Street View en Home.
- `android/assets/ingeearth/index.html` y sus tres bundles: ya no se empaquetan.

`web/ingeearth/` se conserva fuera del flujo Android como fuente histórica,
con `RETIRED.md`. No hay importación o reconstrucción de sus bundles en el nuevo
flujo. No se restauraron archivos completos desde respaldos anteriores.

Se conservaron Cesium y su WebView técnico, AssetLoader, GPS, documentos,
exportación/importación, hápticos y JNI compartido. Cesium no se abre desde Home
ni es fallback de FusionBridge. Se conservó Calicatas → Earth → Calicatas, con
coordenadas/etiqueta pendientes; nunca se afirma que la cámara se haya movido.
El cambio de cuenta cierra la sesión y limpia únicamente su estado efímero.

No existe historial suficiente para atribuir cada línea a Claude. La retirada
está identificada por su función y por el diff contra el estado inicial real.

## 3. Archivos modificados o añadidos

Modificados:
- `CMakeLists.txt`: añade/linkea InGeFusionBridgeNative y una entrada EarthSurfaceHost.qml.
- `main_mobile.cpp`: instancia única, contexto `FusionBridge`, proveedor de imágenes.
- `permissionhelper.h/.cpp`: retira solo APIs MapLibre; GPS/fotos/hápticos quedan intactos.
- `qml/Mobile/HomeScreen.qml`: sesión, estado, host de captura, mismo Dock y retorno.
- `android/AndroidManifest.xml`: visibilidad estrecha de Earth y FGS de captura local.
- `android/src/com/ingema/ingeplus/InGeQtActivity.java`: retirada y hooks de ciclo de vida/resultado.

Añadidos:
- `src/fusionbridge/CMakeLists.txt` y `FusionBridgeController.h/.cpp`.
- `qml/Mobile/EarthSurfaceHost.qml`.
- `android/src/com/ingema/ingeplus/fusionbridge/FusionBridgeNative.java`.
- `EarthIntegrationDetector.java`, `FusionBridgeDiagnostics.java` en ese paquete.
- `EarthLifecycleController.java`, `EarthFrameBridge.java`, `EarthFramePolicy.java`.
- `EarthInputController.java` y `EarthSessionPolicy.java`.
- `scripts/verify_fusionbridge_static.py` y `tests/fusionbridge/FramePolicyTest.java`, `README.md`.
- `web/ingeearth/RETIRED.md`, este informe y diseño/plan en `docs/superpowers/`.

Eliminados del paquete: cuatro archivos en `android/assets/ingeearth/`.

Sin modificaciones: Main.qml, GlassSurface.qml, shaders/glass.frag, AuthSession,
Supabase, InGeCoreFlow, fuentes del Dock, CalicatasEditorPage, InGeDrive y Cesium.
Las comprobaciones de hashes cubren los principales archivos compartidos.

## 4. Arquitectura implementada

```text
Home/Calicatas → FusionBridgeController (una instancia de contexto QML)
              → JNI → FusionBridgeNative → PackageManager / detector

Botón de prueba → consentimiento Android → FGS EarthLifecycleController
               → MediaProjection → VirtualDisplay → ImageReader RGBA
               → EarthFrameBridge → JNI → buzón del último cuadro C++
               → proveedor image://fusionbridge → EarthSurfaceHost.qml

Dock existente → QML → FusionBridgeController.command → JNI
               → EarthInputController → rechazo explícito (sin canal cooperativo)
```

No hay otra APK, launcher, package, servidor, SDK de mapa, motor de animación ni
instancia adicional de InGeCoreFlow. Java usa el sourceSet `src` existente. El
controlador solo se registra como contexto; no combina QML_ELEMENT y singleton.

## 5. Mecanismo visual seleccionado

La integración directa permanece sin contrato verificado. El detector lee
`com.google.earth`, versión, disponibilidad del paquete, actividad lanzable e
inventario de actividades/servicios/proveedores exportados y habilitados. Nunca
inicia Earth automáticamente ni inventa un endpoint Binder.

MediaProjection se implementa **solo como prueba diagnóstica opcional**, Android
API 34+, con consentimiento Android nuevo por sesión. El usuario debe seleccionar
solo Google Earth. No se guarda imagen/audio en disco ni se transmite por red.
La prueba dura como máximo 60 segundos, usa dos buffers, tamaño máximo 640 px
por eje, mantiene proporciones y entrega como máximo cuatro cuadros por segundo.

FLAG_SECURE se agrega temporalmente a la ventana InGe+, conservando el valor
anterior al terminar: evita que nuestra imagen vuelva a capturarse en esa misma
ventana. Durante la prueba las capturas de pantalla de InGe+ pueden salir negras.
El selector no se fuerza ni usa extras internos de SystemUI.

La API pública no devuelve aquí una identidad de paquete del origen. La vista
se etiqueta siempre **captura elegida por el usuario / origen no verificado**.
Elegir otra app o toda la pantalla NO valida Google Earth. La visibilidad del
origen se toma del callback Android y los cambios de píxel de CRC32; ninguno
acredita por sí solo renderizado geográfico válido.

Se limpia la imagen al ocultar origen/anfitrión, ver negro, revocar, salir,
cambiar cuenta o pasar 2500 ms sin cambio. No se cuentan buffers idénticos como
avance. Este umbral conservador puede ocultar un globo quieto que funcione:
`PROBE_NO_CONTENT_CHANGE` significa falta de cambio observable, no crash probado.
Resize cambia el consumidor y redimensiona el MISMO VirtualDisplay; no reutiliza
tokens para crear displays adicionales. Errores de lectura terminan la prueba.

## 6. Controles seleccionados y pendientes

Zoom ±, desplazamiento horizontal/vertical y rotación se describen en el preset
del Dock existente, pero están deshabilitados sin canal interactivo. El puente
QML/C++/JNI recibe comandos y EarthInputController los rechaza con
`EARTH_INPUT_NO_COOPERATIVE_CHANNEL`. Devuelve false, nunca éxito geográfico.
La imagen no tiene MouseArea que finja entregar toques a Earth.

El POC anterior utiliza AccessibilityService.dispatchGesture sobre Earth en
primer plano y un overlay. Se revisó su detector y arquitectura; se trasladó el
patrón PackageManager/visibilidad de paquete, sin copiar overlay, launcher o
servicio de accesibilidad. No se agregó permiso de accesibilidad: ese mecanismo
no conecta la imagen capturada con la ventana remota y el usuario rechazó el
overlay como solución definitiva. No hay prueba de zoom ni desplazamiento real.

## 7. Bloqueos demostrables y evidencia pendiente

| Ruta | Requisito de Android comprobado | Situación de esta entrega |
|---|---|---|
| SurfaceControl / SurfacePackage | El productor remoto debe crear y entregar su SurfacePackage al anfitrión | No hay contrato Earth verificado; adaptador IPC pendiente, no una superficie conectada |
| Activity Embedding | La app destino debe permitir embedding no confiable o confiar en el certificado del host | No se inspeccionó ese opt-in en el Earth instalado; actividad exportada no lo demuestra |
| SurfaceView / SurfaceTexture / EGL | Una superficie propia consume/renderiza nuestros buffers; no obtiene la superficie privada de otro UID | No proporciona acceso al renderizador de Earth por sí sola |
| MediaProjection | Captura con consentimiento, FGS y callbacks; no aporta canal de entrada ni obliga a la app oculta a renderizar | Prueba implementada, continuidad en dispositivo pendiente |
| AccessibilityService | dispatchGesture envía toques a ventanas de pantalla | No satisface por sí solo la vista anfitriona interactiva requerida |

Fuentes primarias:
[SurfaceControlViewHost](https://developer.android.com/reference/android/view/SurfaceControlViewHost),
[Activity Embedding y cooperación de destino](https://developer.android.com/develop/ui/views/layout/activity-embedding),
[MediaProjection](https://developer.android.com/media/grow/media-projection),
[callbacks de visibilidad/resize](https://developer.android.com/reference/android/media/projection/MediaProjection.Callback),
[dispatchGesture](https://developer.android.com/reference/android/accessibilityservice/AccessibilityService).

**No se ha demostrado una imposibilidad universal de todas las versiones de
Google Earth.** ADB y build están prohibidos en esta sesión y no se inspeccionó
el paquete instalado. Lo demostrado son los requisitos del sistema; falta
evidencia de cooperación concreta de Earth. Si aparece un contrato documentado
y autorizado, programar y probar su adaptador es trabajo pendiente real. Añadir
permisos de captura o renombrar clases no reemplaza esa cooperación.

## 8. Matriz de aceptación actual

`IMPLEMENTED` = cambio fuente realizado y revisado estáticamente.
`CODE_READY` = código conectado pendiente de compilación/prueba Android.
`PASS_ANDROID` = solo después de dispositivo, logs y efecto real.
`BLOCKED` = falta una condición externa/contrato para satisfacer el criterio.

| Código | Estado | Evidencia o pendiente |
|---|---|---|
| FB-01 | IMPLEMENTED | Navegación y assets MapLibre retirados, búsqueda estática/diff |
| FB-02 | CODE_READY | Fuentes compartidas conservadas; regresión Android pendiente |
| FB-03 | CODE_READY | Biblioteca enlazada en el target principal y servicio en manifest; APK no compilada |
| FB-04 | CODE_READY | Detector PackageManager integrado; versión instalada no observada aún |
| FB-05 | BLOCKED | Ninguna SurfacePackage/actividad embebida autorizada conectada |
| FB-06 | BLOCKED | Prueba MediaProjection CODE_READY; no cuadros Earth confirmados ni continuidad demostrada |
| FB-07 | BLOCKED | Qt conserva interfaz, pero no se ha alojado Earth original interactivo |
| FB-08 | BLOCKED | Sin canal de zoom hacia Earth; control deshabilitado |
| FB-09 | BLOCKED | Sin canal de desplazamiento verificado |
| FB-10 | BLOCKED | Captura no entrega gestos a Earth |
| FB-11 | CODE_READY | Cierre/reentrada/cancelación implementados; prueba Android pendiente |
| FB-12 | CODE_READY | Liberación de display/reader/proyección/callback/notificación; prueba real pendiente |

## 9. Verificaciones ejecutadas

- Copia y comparación SHA-256 de 3634 archivos del respaldo.
- `git init`, snapshot base, commits de fase, `git diff --check`.
- Búsqueda de referencias principales MapLibre/OpenFreeMap/JS y ausencia de assets.
- `python scripts/verify_fusionbridge_static.py`: **61 comprobaciones aprobadas**.
- `javac` de EarthFramePolicy, EarthInputController, EarthSessionPolicy y FramePolicyTest, sin SDK Android;
  `java ...FramePolicyTest`: **25 comprobaciones aprobadas**.
- Revisión final secuencial de solo lectura: detectó y se corrigió pérdida de
  sesión con Activity recreada y Qt retenido, incluido consentimiento tardío.
  La recuperación espera resume, borra el cuadro y crea una generación nueva;
  no restaura token/proyección. Revisión del delta sin nuevos hallazgos concretos.
- 46 scripts CJS de solo lectura en secuencia: **32 PASS, 14 FAIL**.
  Log completo fuera del proyecto en el respaldo, `static-suite-results.json`.
- Se intentó usar qmlformat 6.9.3 para consultar su ayuda: no produjo salida y
  se terminó el proceso propio. No se cuenta como validación de QML. El chequeo
  léxico Python NO reemplaza qmlcachegen, moc, javac Android ni el linker JNI.

Fallos existentes, contrastados con el snapshot `a7f0ea7`:

| Script | Fallo observado |
|---|---|
| bare_ui_mount_static.cjs | Espera isBareUiEnabled/BARE_UI, ya ausente en Activity inicial |
| bare_ui_static.cjs | home.dart ausente desde la base |
| calicatas-final-static-acceptance.cjs | Espera navegación pageIndex en Main.qml sin cambios |
| closure_1_4_static.cjs | Espera navegación antigua en Main.qml sin cambios |
| earth_picker_static.cjs | InGeEarthHostController.cpp ausente desde la base |
| excel_import.cjs | Espera onCalicataExcelOpenRequested en Main.qml sin cambios |
| laboratory_static.cjs | Espera patrón labContextAction en Editor sin cambios |
| map_loading_single_static.cjs | inge-map-loading.js ausente desde la base |
| p6-dock-export.cjs | Espera función visibleOf en Main.qml sin cambios |
| performance_static.cjs | Aserción _stageSettling en Form sin cambios |
| review_export_static.cjs | Espera capability IA en barra del Editor sin cambios |
| visual_zero_continuation_static.cjs | ProfilePageContent.qml ausente desde la base |
| web_lab_parity_static.cjs | Aserción de etiquetas en Form sin cambios |
| earth_engine_static.cjs | Rechaza ui/ en index.html Cesium sin cambios |

No se ejecutaron tests C++/Qt ni suite SQL contra Supabase: requieren build o
entorno externo. La suite completa no está verde; no se afirma regresión Android.

## 10. Compilar y probar desde Qt Creator

1. Abrir el CMakeLists.txt de ESTE checkout. Seleccionar Qt 6.9.3 Android
   **arm64-v8a** para teléfono/emulador ARM compatible, target AppCalicatasMobile.
   Si el emulador instalado es x86_64, usar el kit x86_64 existente para ese
   dispositivo; una APK ARM no acredita la ejecución en x86_64.
2. Usar un directorio de compilación nuevo para esta validación, para que los
   assets retirados no sobrevivan en un android-build de una compilación previa.
   Ejecutar Run CMake. Confirmar módulo InGeFusionBridgeNative y
   EarthSurfaceHost.qml dentro de InGe.Mobile. No agregar URI/qmldir alternativos.
3. Build Android APK con SDK/NDK/OpenSSL ya configurados en el proyecto. No hay
   proyecto Android Studio obligatorio ni nueva dependencia de mapa.
4. Instalar ACTUALIZANDO la app con la firma habitual. No desinstalar, limpiar
   datos o cambiar package. El target conserva sus requisitos preexistentes de
   AAR Flutter e InGe IA; no se modificaron para ocultar errores.
5. Limpiar logcat, iniciar desde Qt Creator y revisar InGeFusionBridge,
   InGeLifecycle, Qt/QML, AndroidRuntime, crash/ANR y errores JNI.
6. Registrar ABI/API, versiones InGe+/Earth, resultado, logs y observación visual
   de cada prueba. La prueba MediaProjection requiere Android 14/API34+;
   API28–33 debe indicar bloqueo de captura sin afectar los demás módulos.

### Pruebas exactas

| Prueba | Pasos | Resultado a comprobar |
|---|---|---|
| Retirada principal | Login → Home → InGe Earth | Sin mapa MapLibre/OpenFreeMap/Street View ni Cesium automático |
| Detector | Abrir Earth con paquete oficial disponible; repetir en perfil sin Earth | Versión/inventario o EARTH_NOT_INSTALLED_OR_NOT_VISIBLE; nunca falso conectado |
| Retorno | Desde ficha Calicatas con punto, abrir Earth y pulsar Atrás | Coordenadas visibles como pendientes; retorno a Calicatas sin perder ficha/datos |
| Dock | Abrir submenús pan/rotación y tocar herramientas deshabilitadas | No gesto sobre otra ventana ni anuncio de movimiento; Deep Press/Quick Bubble/IA conservados |
| Consentimiento cancelado | Probar captura y cancelar selector Android | Sin servicio persistente ni imagen; interfaz accesible; nueva solicitud permitida |
| Captura Earth | Probar captura, seleccionar SOLO Earth y volver a InGe+ | Anotar si fuente queda oculta, negra o sin cambio; nunca usar el último cuadro como éxito |
| Pantalla dividida | Mantener Earth e InGe+ visibles, seleccionar Earth y moverlo manualmente en su propia ventana | Solo si hay imágenes cambiantes reales, observar actualización en el host; NO valida control del Dock ni embedding exclusivo |
| Recursión | Elegir InGe+ o toda la pantalla en una prueba separada | Área InGe+ protegida/negra, sin efecto espejo infinito; prueba no válida como Earth |
| Frescura | Detener movimiento ≥3 s, ocultar Earth o minimizar InGe+ | Imagen eliminada; estado de origen oculto/negro/no cambio. Describir la diferencia con freeze real |
| Resize | Con captura activa rotar o cambiar tamaño de ventanas | Proporciones estables, sin IllegalStateException por reutilizar token/display |
| Revocación | Detener desde chip Android o notificación de prueba | Imagen eliminada, callback onStop, notificación y recursos liberados |
| Límite | Dejar transcurrir 60 s | Fin automático. Para nueva prueba salir/reentrar al módulo y nuevo consentimiento |
| Reentrada | Repetir 10 veces entrar/probar/salir; incluir salir mientras se espera consentimiento | Ninguna respuesta tardía reabre Earth; no FGS, reader/display o imágenes de sesión anterior |
| Activity recreada | Activar temporalmente «No conservar actividades» en opciones del emulador; abrir prueba y cancelar/aceptar el selector, volver y restaurar la opción | Sin estado anterior atascado; nueva detección/sesión tras resume; cualquier captura requiere consentimiento nuevo |
| Cuenta | Iniciar captura, cerrar sesión y entrar con otra cuenta | Captura cerrada; ningún destino/imagen anterior visible; Login y Perfil correctos |
| Regresión | GPS y cámara/galería Calicatas, guardar/sincronizar, exportar y abrir en InGeDrive, IA, Perfil/Home | Comportamiento previo conservado y sin QML/crash/ANR; documentar fallos existentes por separado |

Zoom/pan/gestos dentro del globo hospedado no pueden aprobarse con este estado.
La captura diagnóstica sirve para comprobar el límite de continuidad; no cambia
un bloqueo en éxito por tener una imagen o un callback de gesto.

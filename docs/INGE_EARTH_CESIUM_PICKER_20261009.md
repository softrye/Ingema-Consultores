# InGe Earth (Cesium) y selector de coordenadas de Calicatas (2026-10-09)

## Arquitectura cartográfica

Hay un solo motor: CesiumJS dentro de **un único WebView nativo** (`InGeQtActivity.earthWebView`, cargado desde `android/assets/cesium/` con `WebViewAssetLoader`). Ese WebView tiene dos modos:

| Modo | Quién lo abre | Geometría | UI web |
|---|---|---|---|
| InGe Earth | `MapNativePage` → `GraphicsCore.openEarth()` | Pantalla completa (deja el hueco del dock QML) | Earth completo |
| Selector de Calicatas | `CalicataPointPicker` → `GraphicsCore.openEarthPicker()` | Solo el área de mapa del selector (el rect llega en píxeles de pantalla) | `body.picker-mode`: tipo de mapa, punto y lectura WGS84/UTM |

Flujo del selector:

1. QML `CalicataPointPicker` (área `mapHost`) llama a `GraphicsCore` (`InGeGraphicsCore`).
2. `InGeEarthHostController` hace la llamada JNI a `InGeQtActivity.showEarthPicker/updateEarthPickerRect/setEarthPickerPoint/setEarthPickerSuspended/hideEarthPicker`.
3. Android ejecuta `evaluateJavascript` sobre `InGeEarthPicker.enter/setPoint/exit` (`ui/inge-earth-picker.js`).
4. Un toque en el mapa llega a `InGeEarthUiBridge.pickerSelected(lat, lon)`.
5. Por JNI se dispara `nativeEarthPickerSelected`, que emite `GraphicsCore.earthPickerPointSelected`.
6. QML recibe el candidato con origen «Punto fijado en mapa».

Reglas:
- La ficha solo cambia con **«Usar esta ubicación»** (`acceptMapPoint`). Mover el mapa o tocarlo solo cambia el candidato. **Cancelar** o **Back** cierran sin persistir.
- GPS explícito con «Mi ubicación» (Qt/`Perms`, one-shot). El fix se muestra en el mapa con su precisión.
- Altitud: el selector no inventa cota. Al confirmar, la ficha consulta el DEM (`resolve-calicata-elevation`).
- Entrar al selector guarda la cámara, el tipo de mapa, las teselas 3D y la inclinación de Earth; salir los restaura. Earth a pantalla completa y el selector nunca conviven.
- La tarjeta de Ubicación de la ficha (no interactiva) es un resumen estático. Tocarla abre el selector. El mapa nativo nunca se incrusta en contenido con scroll.
- Diálogos Qt sobre el mapa (punto distante) suspenden el WebView: queda invisible y se conserva el estado.
- Ciclo de vida: `onPause` llama a `webView.onPause()`; `onResume` restaura la visibilidad y el rect; salir oculta el WebView (GONE + onPause). El WebView se reutiliza (un solo motor en RAM).

## Capas

- **Sin claves:** mapa de calles con las teselas públicas de OpenStreetMap (`https://tile.openstreetmap.org`), con atribución. Para producción conviene configurar `DEFAULT_MAP_URL` (servidor propio o contratado): la política de uso de OSM no admite tráfico intensivo.
- **Cesium ion** (`CESIUM_ION_TOKEN` en `android/local.properties` o variable de entorno; nunca versionado): satélite sobre el globo en el selector, teselas fotorrealistas 3D y terreno en Earth.
- Sin token: Earth arranca en el mapa de calles y el botón Satélite del selector queda deshabilitado.

## Pruebas

- `node tests/calicatas/earth_picker_static.cjs`: contrato JNI, firmas y ciclo de vida.
- Prueba en dispositivo (SM-A127M, nivel LOW), registrada en el reporte de la tarea.

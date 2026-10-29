# Rendiciones: subapp QML nativa en InGe+ Android (2026-10-14)

Arquitectura: `HomeScreen.qml -> qml/Mobile/renditions/RenditionsApp.qml ->
RenditionsUi (RenditionUiController, C++) -> RenditionFlutterBridge::submit ->
RenditionRepository / RenditionLocalStore / RenditionSyncController -> Supabase`.
Sin WebView, sin segunda APK, sin Flutter UI. Respaldo previo: rama
`backup/pre-renditions-ui-20261014` (= `daa2b51`).

## Pantallas

| Archivo | Función |
|---|---|
| `RenditionsApp.qml` | Pila de navegación, Atrás, sincronización, avisos, correlación `requestId` |
| `RenditionsHome.qml` | Propias y recibidas, búsqueda, filtros estado/proyecto, estados de carga/vacío/error/sin conexión |
| `RenditionEditor.qml` | Período, proyectos y principal, carpeta de InGe Drive, autosave, crear/actualizar |
| `RenditionDetail.qml` | Cabecera con estado real, sincronización, permiso y pestañas |
| `RenditionExpenses.qml` / `ExpenseEditor.qml` | Totales (C++), lista, alta, edición, eliminación, sustentos (cámara, galería, PDF) |
| `RenditionFinancial.qml` | Fondo PEN/USD, tipo manual, BCRP/SBS, saldo (RenditionMoney), suplementos congelados |
| `RenditionDocuments.qml` | Ubicación en InGe Drive, sustentos por gasto, apertura firmada, retiro, PDF/XLSX |
| `RenditionReview.qml` / `ReviewPanel.qml` | Presentación, revisión y correcciones, observaciones, versiones |
| `RenditionReceived.qml` | Versión recibida, recepción, notas, actividad, sustentos, exportación, revisión |

## Comandos nuevos del bridge (contratos de la Web)

| Comando | RPC |
|---|---|
| `reviewContext` | `get_rendition_review_context_v03` |
| `reviewTransition` | `transition_rendition_review_v03` |
| `reviewRequest` | `request_rendition_state_v04` |
| `reviewDecide` | `decide_rendition_edit_v03` |
| `receive` | `receive_rendition_v01` |

Mapeo puro en `src/cpp/renditionadminrpc.h` (probado en `tests/renditions/ui_controller.cpp`).
Existen en las migraciones del repositorio madre; su despliegue en InGePlus-Dev no está verificado.

## Pruebas de host

```
cmake -S tests/renditions -B <dir-corto> -G Ninja -DCMAKE_BUILD_TYPE=Debug -DCMAKE_PREFIX_PATH=C:/Qt/6.9.3/mingw_64
cmake --build <dir-corto>
ctest --test-dir <dir-corto> --output-on-failure
```

`qml-flow` carga las pantallas reales con un bridge sintético: no prueba Android ni Supabase.

## Verificación en Android (la realiza el usuario)

1. Qt Creator, kit Android arm64-v8a: ejecutar CMake (hay QML y C++ nuevos), Build, desplegar.
2. `adb logcat -c`; abrir InGe+; filtrar `INGE_RENDITIONS_LOAD_ERROR`, `qml`, `TypeError`.
3. Home -> Rendiciones -> Nueva rendición -> proyecto -> carpeta -> Crear -> Agregar gasto ->
   foto o PDF -> Guardar -> Finanzas (fondo, tipo manual) -> salir de la app -> volver ->
   comprobar el borrador -> Sincronizar -> Revisión -> Presentar.
4. Sin red: repetir un cambio; debe quedar «Pendiente de sincronizar» y no «Sincronizado».
5. Calicatas: tomar una foto de calicata después de usar Rendiciones (slot 101 aislado).

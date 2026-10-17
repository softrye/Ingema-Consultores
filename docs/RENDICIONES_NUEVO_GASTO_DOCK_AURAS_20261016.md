# Rendiciones Android: Nuevo gasto, Dock 3D Touch, auras y diagnóstico (16-10-2026)

Estado: implementado en código fuente y probado en host (Qt 6.9.3 MinGW, offscreen).
**No** se compiló ni instaló el APK, **no** se usó ADB y **no** se hizo commit, push, despliegue ni migración.
`INGE_RENDITIONS_AI_ENABLED=0` sigue sin cambios.

## 1. Archivos

| Archivo | Cambio |
|---|---|
| `qml/Mobile/renditions/ExpenseEditor.qml` | Mismo editor reorganizado en 4 secciones; `headerChip`, `dockActions`/`dockCommand`, herramientas, cuadro de resultado y confeti |
| `qml/Mobile/renditions/RenditionsApp.qml` | Auras derivadas del diagnóstico; política de avisos; chip y título en el encabezado; Dock de la página; acción «Estado de Rendiciones»; panel; `openAssistant`; `goToRendition`; icono de Papelera |
| `qml/Mobile/renditions/RenditionsDiagnostics.qml` (nuevo) | Panel «Estado de Rendiciones» (RGlassMenu grande y desplazable) |
| `qml/Mobile/renditions/RConfetti.qml` (nuevo) | Confeti breve (26 piezas, 1,5 s, sin shaders) |
| `qml/Mobile/assistant/InGeAssistantSheet.qml` (nuevo) | Interfaz global de InGe IA, deshabilitada |
| `qml/Mobile/renditions/RendicionesSyncAura.qml` | Nuevo modo `attention` (azul + amarillo) |
| `qml/Mobile/renditions/RenditionsHome.qml` | Se quitó el recuadro de sesión expirada y de error de arranque |
| `qml/Mobile/renditions/RenditionExpenses.qml` | Errores de registrar/descartar un borrador mostrados en su tarjeta, sin toasts |
| `qml/Mobile/renditions/FilesBrowser.qml` | `hideSync` solo en Papelera |
| `qml/Mobile/HomeScreen.qml` | `tapCommand` opcional; iconos `renditions.*`; botón IA → `openAssistant`; pasa `flow` (InGeCoreFlow) y `requestOpenProfile` |
| `src/dock/DockContextController.cpp` | Conserva `tapCommand` al normalizar acciones |
| `src/cpp/renditiondiagnostics.h` (nuevo) | Catálogo determinista de incidencias |
| `src/cpp/renditionuicontroller.*` | `diagnostics`, `reportIssue`, `resolveIssue` |
| `src/cpp/renditionconnectivity.h` | `AUTH_REQUIRED`/`HTTP_401` tratados como silenciosos |
| `src/cpp/renditionsynccontroller.cpp` | Un 401 deja la operación en espera; ya no es un rechazo guardado en la ficha |
| `src/cpp/renditionlocalstore*.{h,cpp}`, `renditionflutterbridge.cpp` | Se publica `promotedWorkingIds` (confirmación real de la promoción) |
| `CMakeLists.txt` | Registra los 3 QML nuevos y `renditiondiagnostics.h` |
| `tests/renditions/*` | Nuevos `diagnostics.cpp` y `dock_context.cpp`; ampliados `qml_flow.cpp` y `working_queue.cpp` |

## 2. Causa de cada aviso eliminado

| Aviso | Causa | Corrección |
|---|---|---|
| (1) Recuadro de «sin conexión» | Ya se había retirado en el P0 | El aura roja lo comunica, junto con la incidencia NO_NETWORK |
| (2) Conflicto falso | Ya se había corregido en el P0: solo CONFLICT real | Sin cambios |
| (3) Banner de sesión expirada | `RenditionsHome` mostraba un banner con AUTH_REQUIRED o `bootError` | Banner eliminado; ahora es la incidencia SESSION_EXPIRED en el panel |
| (4) Recuadro de sesión expirada sobre una tarjeta | `failCurrent` guardaba el 401 como `syncError` con estado ERROR, y la tarjeta y el detalle lo mostraban como rechazo | Un 401 se trata como espera: marcador técnico, mismo `request_id` y sin texto |
| (5) Toast repetido «La sesión expiró…» (el del vídeo) | En cada sincronización, `errorText(AUTH_REQUIRED)` acababa en `toast(...,"error")` | AUTH es silencioso; además, todo `toast(...,"error")` va al panel con `reportIssue` |

Inventario de avisos:

| Categoría | Tratamiento |
|---|---|
| 1. Estado automático | Aura y panel |
| 2. Error que requiere intervención | Panel |
| 3. Validación de campo | Se mantiene en el formulario |
| 4. Confirmación | Se mantiene (RConfirm) |
| 5. Éxito o información breve | Se mantiene como toast |

«Google Drive» e «Importar» pasan de error a información.

## 3. Pruebas ejecutadas

Directorio de compilación: `C:\InGeBuild\RenditionHost_20261016b`. Resultado de `ctest`: **10/10 suites pasadas**.

| Suite | Resultado |
|---|---|
| qml-flow | 289 verificaciones; sin advertencias QML |
| diagnostics | 31 verificaciones; auras A–F |
| dock-context | 8 verificaciones |
| working-queue | Incluye AUTH1–AUTH4 |
| native-domain, parity, rpc-contract, working-contract, connectivity, ui-controller | Pasadas |

## 4. Pendiente en el Samsung A12

- Compilar e instalar el APK; revisar logcat por errores QML, crash o ANR.
- Comprobar visualmente:
  - las posiciones del Dock;
  - el anclaje de los menús de herramientas sobre el botón ···;
  - la fluidez de las transiciones;
  - la elevación con el teclado (InGeCoreFlow);
  - el confeti.
- Probar «Renovar sesión» con una sesión expirada real.

No se afirma que el diseño coincida exactamente con el preview aprobado: no se verificó visualmente en el dispositivo.

## 5. Riesgos

- **Renovar sesión.** Si el token de renovación ya no es válido, AuthSession cierra la sesión (comportamiento existente). Por eso se pide confirmación y solo se ofrece con AUTH_REQUIRED. Los datos locales se conservan.
- **Mensajes antiguos.** Las fichas guardadas por builds anteriores pueden conservar un `syncError` «La sesión expiró…» hasta su próxima sincronización.
- **Detección de factura.** «Registrar sin comprobante» y el cálculo del IGV dependen de los nombres o códigos del catálogo (factura, declaración jurada, sin comprobante). Si el catálogo real usa otros nombres, la herramienta queda deshabilitada; nunca aplica nada arbitrario.
- **Tasa del IGV.** Se asume la tasa general del 18 %, se muestra la suposición y solo se aplica con confirmación del usuario.
- **Import nuevo en HomeScreen.** `HomeScreen.qml` importa ahora `InGe.CoreFlow 3.0`, igual que `CalicataFormPage`. Las pruebas de host no cargan HomeScreen.

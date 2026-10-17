# Rendiciones Android — P0 auras sin conexión + Working, sustentos, Archivero y Papelera (SIN IA)

16/10/2026 · fuentes Web: PR #5 y #6 (SHA `ab1e1aba`, entregadas en ZIP; PR #7 IA excluida) · entorno: InGePlus-Dev `aalmeaqhhlhzwwzsbbxz`.

> **Estado:** implementado y verificado con 8 suites de host (Qt 6.9.3 MinGW, offscreen):
> - unitarias;
> - cola real con repositorio de prueba;
> - pantallas QML reales con *bridge* sintético.
>
> **No compilado para Android ni probado en el A12** (lo compila el usuario). Sin commit.

## 1. P0 — Causa raíz del fallo de auras

| # | Causa | Dónde |
|---|---|---|
| 1 | Sin conexión → `syncMode = "pending"` (azul): el aura **nunca** se ponía roja | `RenditionsApp.qml` `syncMode` |
| 2 | El estado de conexión se deducía del **estado de la ficha** (`syncStopped(state)` → `updateConnectionState("ERROR"/"NEEDS_RECONCILIATION")`), no del transporte: un fallo de red dejaba `connectionState=ERROR/CONFLICT` | `renditionflutterbridge.cpp` |
| 3 | `NEEDS_RECONCILIATION` (detalle aún no descargado, típico sin red) se mostraba como **conflicto** y bloqueaba la edición | `RenditionDetail.qml` `conflict` |
| 4 | Un fallo de red de la cola se persistía como `ERROR` / `NEEDS_RECONCILIATION` **con el texto de red**: insignias "Error de sincronización", recuadros rojos y refetch en bucle | `renditionsynccontroller.cpp` `failCurrent` |
| 5 | Avisos intrusivos: *toasts* de `refresh`/`sync`/`select`, *banner* "Sin conexión…" del Home, etiqueta "Sin conexión" del botón y texto de error en el detalle | QML |
| 6 | Sin servidor, `select` respondía `DETAIL_BUSY` (navegación bloqueada) | `renditionflutterbridge.cpp` |
| 7 | (Encontrado por los tests) `closeDetail` tardío borraba la ficha recién reabierta | `RenditionDetail.qml` + *bridge* |

## 2. Corrección: fuente única de conexión

`src/cpp/renditionconnectivity.h` (nuevo, puro y probado) combina dos tipos de evidencia.

**Eventos del sistema** (`QNetworkInformation`, sin sondeo):
- `Disconnected` → `NO_NETWORK` al instante.
- Red disponible → solo "posible": nunca se declara ONLINE por tener Wi‑Fi.

**Transporte real de cada RPC** (`RenditionRepository::transportObserved`):
- 2xx/4xx, incluidos CAS y negocio → `ONLINE`.
- Sin respuesta, timeout o 5xx → `SERVER_UNREACHABLE`.
- 401 → `AUTH_REQUIRED`.

**Reintento controlado:** espera de 15 s → 30 s → … → 5 min. Cuenta una vez por intento, solo con red disponible y app en primer plano. Sin red, espera el evento del sistema.

**Propagación hasta QML:**
1. *Bridge*: `connectionState` (`ONLINE` | `OFFLINE` | `AUTH_REQUIRED` | `UNKNOWN`), `connectivity` y `retryInMs`.
2. `RenditionsApp.syncMode = "offline"`.
3. `RendicionesSyncAura`: el modo `offline` usa la **misma** identidad roja aprobada de `error`.

Hay **una sola aura** detrás del `StackView`: lista, detalle y editores.

**Desconexión ≠ conflicto:**
- Un fallo de transporte guarda la marca técnica `TRANSPORT_RETRY`, que la UI oculta y muestra como "pendiente".
- La operación conserva su `request_id` y su CAS, sin refetch.
- Solo un rechazo CAS del servidor produce `CONFLICT`, con el indicador existente y la resolución en su pantalla.

**Avisos eliminados** (punto único `RenditionsApp.errorText`/`toast` y `RenditionUiController::silentError`):
- *toasts* de conexión, *timeout*, `SYNC_BUSY` y `PULL_BUSY`;
- *banner* OFFLINE del Home;
- etiqueta "Sin conexión";
- texto de red del detalle.

Se mantienen solo los que piden acción: sesión expirada, rechazo de permisos o validación, y conflicto real.

**Sin red no se envía nada** (`startRemotePull` y `sync`): los datos locales siguen disponibles, el *outbox* conserva las intenciones y la reconexión reanuda la cola.

## 3. Working Document (8 RPC, firmas exactas del SQL)

| Pieza | Archivo |
|---|---|
| Contrato puro: argumentos y validación idéntica al SQL, normalización, errores | `src/cpp/renditionworkingcontract.h` |
| RPC `list/save/archive/reserve/confirm/promote` y `get_rendition_working_file_v01` (acceso efímero) | `renditionrepository.*` |
| Persistencia local en el **mismo** almacén y el **mismo** *outbox* (`working_save` / `working_promote` / `working_archive`) | `renditionlocalstore_working.cpp` (+ enganches en `renditionlocalstore.cpp`) |
| Cola: guardar → sustentos → registrar o descartar | `renditionsynccontroller.cpp` |
| Lectura de borradores en el pull del detalle, contrato por entorno, comandos | `renditionflutterbridge.cpp` |
| UI: mismo editor ("Guardar como borrador", "Registrar gasto"), sección "Borradores sin registrar" en Gastos, panel de conflicto campo a campo, sugerencia "Completar borradores (N)", bloqueo de "Presentar" | `ExpenseEditor.qml`, `RenditionExpenses.qml`, `RenditionDetail.qml`, `RenditionReview.qml` |

**Garantías:**
- **Intento en vuelo (`inflight`):** si la respuesta se pierde, se reenvía byte a byte; después se envía la intención nueva sobre la versión confirmada. Nunca hay un CAS falso ni una doble escritura.
- **Promoción atómica:** idempotente. `payload.requestId` es la identidad del gasto, así que no hay doble cargo.
- **Conflictos por fila:** no bloquean la ficha ni la cola.
- **Contrato ausente (`PGRST202`):** el borrador queda solo local y no se escribe nada en el servidor.
- **Recuperación entre dispositivos:** metadatos más sustentos READY. Los bytes que nunca se subieron se marcan "por volver a adjuntar" y no se recrean.

## 4. Sustentos de borrador

1. Copia persistente local, con deduplicación por `sha256` y límite de 20 MiB.
2. Reservar (idempotente, renueva la concesión).
3. Confirmar.
4. Subir solo si falta el objeto (`upsert:false`, ruta asignada por el servidor y validada).
5. Confirmar de nuevo.

"Ver" pide `get_rendition_working_file_v01` y una firma de 60 s en cada apertura. **Ninguna URL firmada se persiste.**

## 5. Archivero y Papelera (Files v07)

`FilesBrowser.qml`, abierto desde el menú del Dock **Carpeta documental**:
- comprueba primero el contrato (`get_files_recovery_contract_v07`; `PGRST202` → aviso discreto);
- lista `list_files_archive_children_v07` / `list_files_trash_children_v07`: jerarquía, migas y paginación; el ACL lo aplica el servidor;
- "Ver" de binarios usa `get_recovery_binary_object_v02` (el mismo de la Web) más una firma efímera;
- **recuperación reversible**: `preview_files_recovery_v07` (token) → `mutate_files_recovery_v07` (mismo token, versión esperada y `request_id` idempotente);
- si el origen se movió: proyecto → carpeta → `can_select_files_recovery_destination_v07` → nueva vista previa.

**No hay purga ni borrado desde el móvil:** el test verifica que nunca se envía un comando de purga.

## 6. Pruebas ejecutadas (host)

```
C:\InGeBuild\RenditionHost_20261016b  ->  ctest: 100% (8/8)
```

| Suite | Cubre |
|---|---|
| `connectivity` | Máquina de estados (A, B, D, reintento, Wi‑Fi apagado con datos móviles) y almacén real (D, F, C, "detalle no descargado") |
| `working-queue` (54) | **Cola real** con repositorio de prueba: reintento idéntico tras perder la respuesta, sustentos (reservar, confirmar, subir), promoción idempotente, conflicto y resolución, descarte, recuperación entre dispositivos, `PGRST202`, reinicio del proceso, P0 en la cola |
| `qml-flow` (196) | Pantallas reales: pruebas A, B, C, D y E (aura roja, sin *toasts* ni recuadros, el detalle abre sin red, editable, reconexión), Working en UI, Archivero y Papelera con recuperación, sin purga, sin advertencias QML |
| `working-contract`, `ui-controller`, `rpc-contract`, `shared-vectors-parity`, `native-domain-outbox-and-exports` | Contratos y regresión existente |

## 7. Pruebas pendientes en el Samsung A12 (sin evidencia aún)

1. Abrir Rendiciones conectado → aura normal.
2. Desactivar Wi‑Fi **y** datos móviles → el aura pasa a **rojo**, sin recuadros ni avisos.
3. Crear o editar un gasto, y guardar un borrador, sin conexión. Navegar por lista, detalle y editor: el aura sigue roja y no se bloquea nada.
4. Restablecer Internet → la cola se sincroniza sola y el aura sale del rojo (pendiente → sincronizado).
5. Repetir en el detalle; comprobar que no se perdieron datos ni hay gastos duplicados.
6. Solo Wi‑Fi apagado con datos móviles activos → **no** debe ponerse roja.
7. Wi‑Fi sin Internet (portal cautivo) → rojo tras el *timeout* (≤30 s), sin avisos.
8. Borrador en la nube: crearlo en Android y verlo en la Web (DEV); crearlo en la Web y recuperarlo en Android; registrar; descartar.
9. Archivero y Papelera con una cuenta con permisos (DEV).

Revisar en `logcat`: `INGE_RENDITIONS_LINK` y `INGE_RENDITIONS_SYNC` (sin secretos).

## 8. Riesgos y pendientes

- No pude verificar en DEV, porque la consulta de solo lectura fue denegada por permisos:
  - los *triggers* `rendition_working_*_guard_v01`;
  - si hay filas Working activas;
  - `list_files_archive_children_v07` y `get_recovery_binary_object_v02`.
  La app comprueba el contrato en tiempo de ejecución.
- `QNetworkInformation` necesita el *backend* Android desplegado. Ya lo usaba la cola. Sin *backend*, la detección se apoya solo en el transporte.
- Migraciones Files v04–v07 y Working v01: solo DEV, **no aplicadas** a PROD.
- Los campos locales RUC, subtotal e IGV no forman parte del contrato Working; ya no se enviaban al servidor.

## 9. Compilación (la realiza el usuario)

- **Android:** Qt Creator con el kit Qt 6.9.3 Android arm64‑v8a. El CMake principal ya incluye `renditionlocalstore_working.cpp`, los headers nuevos y `FilesBrowser.qml`.
- **Tests de host:**
  ```
  cmake -S tests/renditions -B C:/InGeBuild/RenditionHost -G Ninja -DCMAKE_PREFIX_PATH=C:/Qt/6.9.3/mingw_64 && cmake --build C:/InGeBuild/RenditionHost && ctest --test-dir C:/InGeBuild/RenditionHost
  ```

IA: `INGE_RENDITIONS_AI_ENABLED 0` sin cambios. Producción: sin tocar. Home, Calicatas, Earth, Liquid Glass y Dock global: sin cambios.

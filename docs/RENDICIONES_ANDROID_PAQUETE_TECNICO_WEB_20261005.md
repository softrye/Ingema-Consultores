# PAQUETE TÉCNICO ANDROID — RENDICIONES
## Integración Web ↔ Android
Fecha: 05/10/2026

Documento generado por auditoría **estática** del código fuente Android (sin compilar, sin ADB, sin tocar Supabase).
Convenciones:

- **[Evidencia]**: comprobado en el código o en disco (archivo + función/línea).
- **[Inferencia]**: deducción razonable no comprobada directamente.
- **NO DETERMINABLE / NO ENCONTRADO**: no pudo establecerse con la evidencia disponible.

Las rutas de código son relativas a `C:\Users\PC-02\Documents\InGePlus\AppCalicatasDemo`. Los números de línea corresponden al árbol de trabajo del 05/10/2026 (incluye cambios sin commit) y pueden desplazarse.

---

## 1. IDENTIFICACIÓN DEL PILOTO

| Dato | Valor |
|---|---|
| Proyecto | `C:\Users\PC-02\Documents\InGePlus\AppCalicatasDemo` (confirmado por `CMAKE_HOME_DIRECTORY` en `C:\InGeBuild\A37\CMakeCache.txt`) |
| Branch | `codex/phase1-tanda1-correction` |
| HEAD | `772ce1a98c8ed76e4529643d741e26ab9b95cc66` |
| Fecha/hora del HEAD | 2026-10-05 11:48:19 -0500 — "fix(calicatas): autofill AI interpretation and retain photo glass" (commit de Calicatas, no de Rendiciones) |
| Estado del árbol de trabajo | **Con cambios sin commit**: 580 entradas (66 modificadas, 4 borradas, 510 sin seguimiento) |
| Cambios sin commit en Rendiciones | `src/cpp/renditionflutterbridge.cpp/.h`, `renditionlocalstore.cpp`, `renditionrepository.cpp`, `renditionsynccontroller.cpp`, `flutter/inge_earth/lib/renditions/v2/*`, `v3/*` (incl. `screens/expense_editor.dart`, `theme/rendition_theme.dart`), tests Flutter de Rendiciones y `tests/renditions/checks.cpp` — 11 archivos, +217 / −336 líneas. Fechas de modificación: 24–26/09/2026 |
| APK | `android-build-release-signed.apk` (Release, firmado) |
| Ruta absoluta | `C:\InGeBuild\A37\android-build\build\outputs\apk\release\android-build-release-signed.apk` |
| Fecha/hora APK | 2026-10-05 11:52:34 |
| Tamaño | 182.312.268 bytes |
| Copia sin firmar | `C:\InGeBuild\A37\android-build\AppCalicatasMobile.apk` — 182.213.121 bytes — 2026-10-05 11:51:54 |

**CORRESPONDENCIA APK↔COMMIT: NO DETERMINABLE**

Motivo: el APK fue generado desde un árbol de trabajo con cambios sin commit (4 minutos después del HEAD). No existe un commit que represente exactamente el contenido del APK.

- [Inferencia] Los cambios de Rendiciones sin commit (24–26/09) son anteriores al APK (05/10 11:52), por lo que probablemente están incluidos.
- [Evidencia] `android/build.gradle` (≈ líneas 155–182) resuelve el módulo Flutter desde el workspace (`flutter/inge_earth`), por lo que el Dart del APK sería el del árbol de trabajo. [Inferencia] No se verificó el contenido binario del APK.

APK anteriores encontrados (NO corresponden al estado actual):

- `C:\InGeBuild\A37\AppCalicatasMobile-master-release-signed.apk` (22/08/2026)
- `C:\Users\PC-02\Documents\InGePlus_Builds\Qt_6_9_3_Android_arm64_Release_Manual\android-build-AppCalicatasMobile\*.apk` (14/08 y 24/08/2026)
- `C:\Users\PC-02\Documents\InGePlus_BUILD_FRESH_CESIUM_20260813\apk\*.apk` (13/08/2026)
- `flutter\inge_earth\build\host\outputs\apk\debug\app-debug.apk` (22/09/2026; host Flutter, no es la app InGe+)

---

## 2. STACK ANDROID REAL

| Capa | Componente real | Evidencia |
|---|---|---|
| UI | Flutter/Dart (add-to-app dentro del shell Android) | `flutter/inge_earth/lib/renditions/**` |
| Canal UI → host | `MethodChannel('inge.renditions/host')`, método `submit` con JSON de comando | `flutter/inge_earth/lib/renditions/renditions_bridge.dart:37` |
| Java | `InGeQtActivity` registra el canal y llama a JNI | `android/src/com/ingema/ingeplus/InGeQtActivity.java:89` (`RENDITIONS_CHANNEL`), `:189` (`native void nativeSubmitRenditionCommand`), `:1820/1829` (handler), `:593` (`dispatchRenditionEvent`) |
| JNI | `Java_com_ingema_ingeplus_InGeQtActivity_nativeSubmitRenditionCommand` → `RenditionFlutterBridge::submitFromAndroid` | `src/cpp/renditionflutterbridge.cpp:1093` |
| C++ (adaptador) | `RenditionFlutterBridge` — traduce comandos JSON, sin reglas de negocio | `src/cpp/renditionflutterbridge.h/.cpp` |
| C++ (dominio local) | `RenditionLocalStore` — store JSON + outbox | `src/cpp/renditionlocalstore.h/.cpp` |
| C++ (sincronización) | `RenditionSyncController` — consume el outbox en orden | `src/cpp/renditionsynccontroller.h/.cpp` |
| C++ (remoto) | `RenditionRepository` — RPC PostgREST | `src/cpp/renditionrepository.h/.cpp` |
| Qt | Event loop, `QNetworkAccessManager`, `QNetworkInformation`, `QSaveFile`. **Qt/QML no participa en la UI de Rendiciones** | constructores de los anteriores |
| Almacenamiento local | **JSON por cuenta** escrito con `QSaveFile` | `RenditionLocalStore::storagePath` (`renditionlocalstore.cpp:174`), `persist` (`:1984`) |
| Remoto | Supabase PostgREST `rest/v1/rpc/<nombre>` | `RenditionRepository::callRpc` (`renditionrepository.cpp:763`) |
| Archivos | Supabase Storage (HTTP directo, bucket `project-files`) | `RenditionRepository::uploadReservedAttachment` (`renditionrepository.cpp:580`) |
| Retorno C++ → UI | `QJniObject::callStaticMethod("com/ingema/ingeplus/InGeQtActivity","dispatchRenditionEvent")` | `RenditionFlutterBridge::sendEvent` (`renditionflutterbridge.cpp:1074`) |

**ANDROID NO USA SQLITE PARA RENDICIONES.**

[Evidencia] No hay `QSql*` en `src/cpp/rendition*` ni `sqflite`/`drift` en `flutter/inge_earth/lib/renditions` ni en `pubspec.yaml`. El almacenamiento local real es un **archivo JSON por cuenta escrito con `QSaveFile`** (escritura atómica). Otras partes de InGe+ pueden usar otros mecanismos; esto no aplica a Rendiciones.

Solo `RenditionRepository` habla con Supabase. Dart nunca llama a Supabase para Rendiciones.

---

## 3. DTO / MODELOS REALES

### 3.0 Las tres representaciones

```
C++ QVariantMap (claves camelCase, sin clases/structs de dominio)
        ↓  QJsonDocument::fromVariant  (RenditionLocalStore::persist)
JSON local por cuenta (mismo contenido, en disco)
        ↓  publishState → sendEvent (JNI) → MethodChannel
Dart JsonMap + envoltorios de solo lectura (RenditionData, ExpenseData, AttachmentData, VersionData)
```

- [Evidencia] **No existen DTO tipados en C++** (ni `struct` ni `class` de dominio): todo es `QVariantMap`.
- Hacia el backend se usa un cuarto formato: argumentos `p_snake_case` construidos en `RenditionRepository` (ver §4).
- Las respuestas del backend (snake_case) se normalizan con `RenditionContract::normalize` (`src/cpp/renditioncontract.h:8`): `project_ids→projectIds`, `primary_project_id→primaryProjectId`, `total_pen→totalPen`, `total_usd→totalUsd`, `expense_count→expenseCount`, `version_number→versionNumber`, `current_version_id→currentVersionId`, `base_currency_code→baseCurrency`, `period_start/end→periodStart/End`, `created_at/updated_at→createdAt/updatedAt`, `associatedProjectIds→projectIds`, `projects[].is_primary→primaryProjectId/primaryProjectName`, `current_version_number→versionNumber`.
- Los modelos Dart aceptan camelCase **o** snake_case en cada getter (`field(map, camel, snake)`, `renditions_models.dart:11`).

### 3.1 Rendición

| Representación | Nombre real | Archivo | Lenguaje |
|---|---|---|---|
| Local | `QVariantMap` "draft" | `RenditionLocalStore::createDraft` (`renditionlocalstore.cpp:236`), `mergeRemoteRenditions` | C++ |
| UI | `RenditionData` | `flutter/inge_earth/lib/renditions/renditions_models.dart:46` | Dart |

Campos locales (C++/JSON):

| Campo | Tipo | Notas |
|---|---|---|
| `localId` | texto UUID | generado en el dispositivo (`newUuid`) |
| `remoteId` | texto UUID | vacío hasta confirmación; se lee de `rendition_id` o `id` (`RenditionLocalStore::remoteId`, `:2081`) |
| `requestId` | texto UUID | clave de idempotencia de `create_my_rendition_draft_v02` |
| `visibleCode` | texto | `visible_code` del servidor |
| `rowVersion` | entero | 0 local; servidor vía `rendition_row_version` o `row_version` (`remoteRowVersion`, `:2092`) |
| `periodStart`, `periodEnd` | texto ISO `yyyy-MM-dd` | |
| `projectIds` | lista de texto | |
| `primaryProjectId` | texto | `primaryProjectName` tras PULL |
| `documentParentNodeId`, `documentNodeId` | texto | ubicación documental `.rend` |
| `documentNodeVersion` | entero | |
| `spaceId` | texto | |
| `status` | texto | `BORRADOR` al crear; `PRESENTADA` y otros desde el servidor |
| `syncState` | texto | ver §3.4 |
| `createdAt`, `updatedAt` | texto UTC ISO | |
| `expenses` | lista de gastos | |
| `payload` | mapa | carga canónica (`canonicalDraftPayload`) |
| Tras PULL | | `baseCurrency`, `reference`, `currentVersionId`, `versionNumber`, `totalPen`, `totalUsd`, `expenseCount`, `remoteSummary`, `expensesLoaded`, `archived`, `syncError`, `pendingCount` |

Dart (`RenditionData`): `localId`, `remoteId` (`remoteId`/`rendition_id`/`id`), `code` (`visibleCode`, por defecto "Borrador local"), `status` (por defecto `BORRADOR`), `syncState` (por defecto `LOCAL_ONLY`), `periodStart/End`, `createdAt/updatedAt`, `baseCurrency`, `reference`, `primaryProjectId/Name`, `projectIds`, `documentParentNodeId/Name`, `spaceId`, `rowVersion` (int), `versionNumber` (int), `totalPen`/`totalUsd` (**double**), `expenseCount`, `readOnly` (`status != BORRADOR`), `hasConflict` (`CONFLICT` o `NEEDS_RECONCILIATION`).

### 3.2 Gasto

| Representación | Nombre real | Archivo | Lenguaje |
|---|---|---|---|
| Local | `QVariantMap` dentro de `rendition.expenses[]` | `RenditionLocalStore::addLocalExpense` (`:389`), `saveLocalExpense` | C++ |
| Hacia backend | argumentos `p_*` | `RenditionRepository::expenseArguments` (`renditionrepository.cpp:385`) | C++ |
| UI | `ExpenseData` | `renditions_models.dart:109` | Dart |

Campos locales: los del formulario más `localId`, `remoteId` (`expense_id`/`id`), `requestId`, `rowVersion`, `amount` (**guardado como texto**), `reviewStatus` (`PENDIENTE`), `syncState`, `createdAt`, `updatedAt`, `attachments[]`, `clientIntentId` (opcional, deduplicación de doble envío), `archived`.

Campos de negocio: `projectId`, `expenseDate`, `categoryCode`, `concept`, `beneficiary`, `paymentMethodCode`, `paymentMethodDetail`, `supportTypeCode`, `supportNumber`, `supportDetail`, `currencyCode`, `amount`, `justification`.

Relación: pertenece a una rendición (`renditionLocalId`/`renditionRemoteId` en el payload del outbox) y a un proyecto de esa rendición.

Dart (`ExpenseData`): `amount` como **double** (`numberField`), `currency` (por defecto `PEN`), `reviewStatus` (por defecto `PENDIENTE`), `syncState` (por defecto `LOCAL_ONLY`), `rowVersion`, `archived`, más nombres de catálogo (`categoryName`, `paymentMethodName`, `supportTypeName`).

### 3.3 Adjunto (sustento)

| Representación | Nombre real | Archivo | Lenguaje |
|---|---|---|---|
| Local | `QVariantMap` dentro de `expense.attachments[]` | `RenditionLocalStore::addLocalAttachment` (`:709`), `updateAttachmentPhase` | C++ |
| Contrato de ruta | `RenditionAttachmentContract::objectPath`, `::valid` | `src/cpp/renditionattachmentcontract.h` | C++ |
| UI | `AttachmentData` | `renditions_models.dart:153` | Dart |

Campos locales: `localUri` (ruta del **espejo local** persistente), `fileName`, `mimeType`, `sizeBytes`, `sha256`, `projectId`, `localId`, `remoteId`, `requestId`, `phase` (`RESERVE` → `UPLOAD` → `FINALIZE` → `READY`, o `ERROR`/`CONFLICT`/`NEEDS_RECONCILIATION`), `syncState`, `createdAt`, `supportTypeCode`, `documentNumber`, `clientIntentId` (opcional). Tras la reserva: `bucket`, `storage_path`/`objectPath`, `attachment_id`, `expires_at`, `syncError`.

Dart (`AttachmentData`): `id` (`remoteId`/`attachment_id`/`attachmentId`/`id`), `localId`, `expenseId`, `fileName` (por defecto "Sustento"), `mimeType`, `documentNumber`, `expenseNumber`, `sizeBytes`, `phase` (`phase`/`status`, por defecto `READY`), `rowVersion`.

### 3.4 Outbox / Sync

Nombre real: entrada `QVariantMap` en `RenditionLocalStore::m_outbox`, creada por `upsertOutbox` (`renditionlocalstore.cpp:1905`).

| Campo | Tipo | Notas |
|---|---|---|
| `id` | UUID | identidad de la entrada |
| `sequence` | entero | orden (`m_nextSequence`) |
| `attempts` | entero | |
| `operation` | texto | `rendition_create`, `rendition_update`, `rendition_delete`, `expense_create`, `expense_update`, `expense_delete`, `attachment_reserve`, `present` |
| `accountScope` | texto | cuenta |
| `aggregateLocalId` | texto | `localId` de la rendición |
| `childLocalId` | texto | `localId` del gasto/adjunto |
| `remoteId` | texto | |
| `requestId` | texto | idempotencia |
| `payload` | mapa | |
| `payloadHash` | texto | |
| `state` | texto | estados de sync |
| `createdAt`, `updatedAt` | texto UTC | |
| `lastSafeError` | texto | |

Estados de sync (`renditionlocalstore.cpp:24-31`): `LOCAL_ONLY`, `PENDING_CREATE`, `PENDING_UPDATE`, `SYNCING`, `SYNCED`, `CONFLICT`, `NEEDS_RECONCILIATION`, `ERROR`.

Estado agregado de una rendición: `RenditionLocalStore::syncStatus` (`:1311`) combina el estado de la cabecera y del outbox; prioridad `CONFLICT` > `NEEDS_RECONCILIATION` > `ERROR` > `SYNCED`.

### 3.5 Conflicto

**No existe un DTO de conflicto ni una RPC de resolución.** [Evidencia]

- Se representa con `syncState` ∈ {`CONFLICT`, `NEEDS_RECONCILIATION`} más `syncError` en la rendición/gasto/adjunto, y `state` en la entrada del outbox.
- La detección se apoya en el control de concurrencia optimista: argumentos `p_expected_row_version`, `p_expected_rendition_row_version`, `p_expected_expense_row_version`, `p_expected_document_node_version` (ver §4 y §9).
- Clasificación: `RenditionSyncController::failCurrent` (`renditionsynccontroller.cpp:341`).

---

## 4. RPC REALMENTE CONSUMIDAS

Todas pasan por `RenditionRepository::callRpc` (`renditionrepository.cpp:763`): `POST rest/v1/rpc/<nombre>` con cuerpo JSON, cabeceras `Prefer: return=representation`, `x-ingeplus-platform: ANDROID`, `X-Client-Info: InGePlus-Android/1.0`, aborto a los 30 s.

Errores comunes a todas (columna "Errores" = **C**):

| Situación | Código emitido |
|---|---|
| HTTP 401 | `AUTH_REQUIRED` |
| HTTP 4xx | `responseErrorCode` (`renditionrepository.cpp:23`): el `message` de PostgREST si empieza por `RENDITION_` o es `AUTH_REQUIRED`/`PROFILE_NOT_ACTIVE`; si no, el `code` de PostgREST; por defecto `HTTP_ERROR` |
| HTTP 5xx, error de red o timeout (abort) | `NETWORK_AMBIGUOUS` |
| Respuesta no JSON | `RENDITION_INVALID_RESPONSE` |
| Sin sesión antes de llamar | `AUTH_REQUIRED` (no se llama) |

Lectura de respuestas: `firstRow` (primera fila) o `rows` (todas). La estructura completa de cada respuesta **NO es DETERMINABLE** desde el cliente; solo se conocen los campos que el código lee (`id`/`<entidad>_id`, `row_version`, `rendition_row_version`, `visible_code`, `status`, `bucket`, `storage_path`, `attachment_id`, `expires_at`, `result_code`, `state`, etc.).

Abreviaturas de los 13 argumentos de gasto (**G13**): `p_project_id`, `p_expense_date`, `p_category_code`, `p_concept`, `p_payment_method_code`, `p_support_type_code`, `p_currency_code`, `p_amount` (**número JSON double**), `p_beneficiary`, `p_payment_method_detail`, `p_support_number`, `p_support_detail`, `p_justification` (los 5 últimos opcionales → `null` si vacíos).

### 4.1 Consumidas (dominio Rendiciones)

| RPC | Operación (línea) | Argumentos | L/E | PULL/PUSH/MERGE | Concurrencia | Errores |
|---|---|---|---|---|---|---|
| `list_my_renditions_v01` | `listRenditions` (:119) | `p_limit` (1–100), `p_after_updated_at`, `p_after_id` | L | PULL (paginado `updated_at`+`id`) → MERGE | — | C + `PULL_CAPACITY`, `PULL_CURSOR_INVALID` |
| `get_my_rendition_v01` | `getRendition` (:150) | `p_rendition_id` | L | PULL | — | C |
| `list_my_rendition_projects_v01` | `listProjects` (:160) | — | L | PULL (catálogo) | — | C |
| `create_my_rendition_draft_v02` | `createRendition` (:190) | `p_request_id`, `p_period_start`, `p_period_end`, `p_project_ids` (uuid[] como texto), `p_primary_project_id`, `p_document_parent_node_id` | E | PUSH | Idempotencia por `p_request_id` | C + `RENDITION_DOCUMENT_LOCATION_REQUIRED` (local) |
| `update_my_rendition_draft_v02` | `editRendition` (:225) | `p_rendition_id`, `p_expected_row_version`, período, `p_project_ids`, `p_primary_project_id`, `p_document_parent_node_id`, `p_expected_document_node_version` (`null` si ≤ 0) | E | PUSH | CAS `p_expected_row_version` | C + `RENDITION_DOCUMENT_LOCATION_REQUIRED` (local) |
| `delete_my_rendition_draft_v01` | `deleteDraft` (:503) | `p_rendition_id`, `p_expected_row_version` | E | PUSH | CAS | C |
| `get_my_rendition_smart_document_location_v01` | `getDocumentLocation` (:253) | `p_rendition_id` | L | PULL → MERGE (`adoptDocumentLocation`) | — | C |
| `set_rendition_smart_document_location_v01` | `setDocumentLocation` (:269) | `p_rendition_id`, `p_document_parent_node_id`, `p_expected_document_node_version` | E | Ubicación documental | CAS de nodo | C |
| `list_my_rendition_expense_catalogs_v01` | `listExpenseCatalogs` (:354) | — | L | PULL (catálogo) | — | C |
| `list_my_rendition_expenses_v01` | `listExpenses` (:364) | `p_rendition_id` | L | PULL → MERGE (`mergeRemoteExpenses`) | — | C |
| `get_my_rendition_expense_summary_v01` | `getExpenseSummary` (:376) | `p_rendition_id` | L | PULL → guardado como `remoteSummary` | — | C |
| `create_my_rendition_expense_v02` | `addExpense` (:448) | `p_request_id`, `p_rendition_id`, `p_expected_rendition_row_version`, G13 | E | PUSH | Idempotencia `p_request_id` + CAS de cabecera | C |
| `update_my_rendition_expense_v01` | `updateExpense` (:468) | `p_expense_id`, `p_rendition_id`, `p_expected_expense_row_version`, `p_expected_rendition_row_version`, G13 | E | PUSH | CAS gasto + cabecera | C |
| `delete_my_rendition_expense_v01` | `deleteExpense` (:480) | `p_rendition_id`, `p_expense_id`, `p_expected_expense_row_version`, `p_expected_rendition_row_version` | E | PUSH | CAS gasto + cabecera | C |
| `list_my_rendition_versions_v01` | `listVersions` (:493) | `p_rendition_id` | L | PULL | — | C |
| `present_my_rendition_v01` | `presentRendition` (:513) | `p_rendition_id`, `p_expected_row_version`, `p_request_id` | E | Presentación (manual) | CAS + idempotencia | C |
| `reserve_rendition_attachment_v01` | `reserveAttachment` (:538) | `p_rendition_id`, `p_expense_id`, `p_request_id`, `p_file_name`, `p_mime_type`, `p_size_bytes`, `p_support_type_code`, `p_document_number` | E | Adjuntos (PUSH) | Idempotencia `p_request_id` | C + `RENDITION_ATTACHMENT_SIZE_INVALID` (local) |
| `finalize_rendition_attachment_v01` | `finalizeAttachment` (:631) | `p_attachment_id` | E | Adjuntos (PUSH) | — | C |
| `list_rendition_attachments_v01` | `listAttachments` (:641) | `p_rendition_id` | L | PULL → MERGE (`mergeRemoteAttachments`) | — | C |
| `get_rendition_attachment_access_v01` | `getAttachmentAccess` (:653), `accessReceivedAttachment` (:675) | `p_attachment_id` | L | Acceso a adjunto | — | C + `ATTACHMENT_ACCESS_INVALID`, `ATTACHMENT_ACCESS_DENIED` |
| `archive_rendition_attachment_v01` | `archiveAttachment` (:664) | `p_attachment_id`, `p_expected_row_version` | E | Adjuntos | CAS | C |

### 4.2 Consumidas (bandeja administrativa "recibidas")

Despachadas por `RenditionRepository::receivedCommand` (`renditionrepository.cpp:718`):

| RPC | Comando | Argumentos | L/E |
|---|---|---|---|
| `list_received_renditions_v02` | `receivedList` | `p_limit` (200), `p_after_submitted_at`, `p_after_id` | L |
| `get_received_rendition_v02` | `receivedQuery` | `p_rendition_id` | L |
| `list_rendition_admin_notes_v01` | `receivedNotes` | `p_rendition_id` | L |
| `list_rendition_activity_v01` | `receivedActivity` | `p_rendition_id` | L |
| `create_rendition_admin_note_v01` | `receivedAddNote` | `p_rendition_id`, `p_rendition_version_id`, `p_request_id`, `p_body` | E |
| `get_document_structural_capabilities_v02` | `folderCapabilities` | `p_space_id`, `p_node_id` | L |

### 4.3 Consumidas (infraestructura documental compartida, selección de carpeta `.rend`)

| RPC | Operación (línea) | Argumentos |
|---|---|---|
| `get_my_project_workspace_v01` | `getProjectWorkspace` (:287) | `p_project_id` |
| `get_my_document_space_v02` | `getDocumentSpace` (:300) | `p_space_id` |
| `list_my_document_explorer_items_v03` | `listDocumentFolders` (:314) | `p_space_id`, `p_parent_node_id` |
| `get_document_structural_capabilities_v02` | `getDocumentCapabilities` (:342) | `p_space_id`, `p_node_id` |

### 4.4 A) RPC existentes en el código pero INACTIVAS

| RPC | Ubicación | Motivo |
|---|---|---|
| `create_my_rendition_draft_v01` | `renditionrepository.cpp:182` | `RenditionRepository::ActiveContractMode = V02` (`renditionrepository.h:39`) → se usa `_v02` |
| `update_my_rendition_draft_v01` | `renditionrepository.cpp:217` | idem |

### 4.5 B) RPC/funciones SOLO documentadas en el handoff de backend y NO consumidas por Android

Fuente: búsqueda en `_server_handoff/` de nombres `*rendition*_v0N` contra las RPC de `renditionrepository.cpp`. Algunas son funciones internas o políticas, no RPC públicas; **no se verificó su exposición pública**.

`create_my_rendition_expense_v01`, `get_received_rendition_v01`, `list_received_renditions_v01`, `receive_rendition_v01`, `ensure_rendition_smart_document_v01`, `extend_rendition_snapshot_attachments_v01`, `list_usable_rendition_projects_for_actor_v01`, `next_rendition_visible_code_value_v01`, `is_active_rendition_administrator_v01`, `enforce_rendition_smart_primary_project_v01`, `can_read_rendition_attachment_v01`, `rendition_client_platform_v01`, `rendition_lima_year_v01`, `rendition_attachment_storage_uploadable_v01`, `rendition_attachment_storage_readable_v01`, y las políticas de Storage `rendition_attachment_exact_upload_v01` / `rendition_attachment_exact_read_v01`.

> Web no debe interpretar la lista 4.5 como contrato utilizado por Android.

---

## 5. CÁLCULOS

### 5.1 Función única de cálculo en Android

`RenditionValidation::totals(QVariantMap &draft)` — `src/cpp/renditionvalidation.h` (≈ línea 60) — C++.

| Aspecto | Comportamiento real |
|---|---|
| Entrada | `draft.expenses[]` (gastos locales de la rendición) |
| Gastos archivados | Se excluyen (`archived == true` → `continue`) |
| Conversión a céntimos | `qRound64(amount.toDouble() * 100)` por gasto |
| Acumulación | Enteros `qint64` separados por moneda: `pen` (`currencyCode == "PEN"`), `usd` (`currencyCode == "USD"`); otras monedas se ignoran |
| Salida | `totalPen = pen / 100.0` y `totalUsd = usd / 100.0` (**double**); `expenseCount` = gastos no archivados; `pendingCount` = gastos con `reviewStatus` `PENDIENTE` o `PENDING` (por defecto `PENDIENTE`) |
| Redondeo | `qRound64` (redondeo al entero más cercano; mitades se alejan de cero) sobre `double*100`, una vez por gasto. No hay redondeo bancario ni aritmética decimal |
| Conversión PEN ↔ USD | **NO EXISTE** en el cliente |
| Impuestos, deducciones, subtotales por categoría | **NO ENCONTRADO** |

Se invoca tras cada mutación local: `addLocalExpense` (`renditionlocalstore.cpp:432`), y en las líneas `:533`, `:622`, `:702`, `:795`, `:858` (edición/eliminación de gasto, adjuntos y merge).

### 5.2 Qué calcula Android vs qué recibe del servidor

| Origen | Dato | Evidencia |
|---|---|---|
| Android | `totalPen`, `totalUsd`, `expenseCount`, `pendingCount` locales | `RenditionValidation::totals` |
| Servidor (lista) | `total_pen`, `total_usd`, `expense_count` en `list_my_renditions_v01` → normalizados a `totalPen`/`totalUsd`/`expenseCount` | `RenditionContract::normalize`, `mergeRemoteRenditions` |
| Servidor (resumen) | Respuesta de `get_my_rendition_expense_summary_v01` guardada íntegra como `remoteSummary` | `RenditionLocalStore::adoptRemoteSummary` (`:1301`) |
| Servidor (versiones) | `total_pen`/`total_usd` por versión | `VersionData` (Dart) |

- Cuando la rendición ya tiene gastos cargados, los totales locales **no se sobrescriben** con los del encabezado remoto (comentario y condición en `mergeRemoteRenditions`: "Once expenses are loaded, their persisted rows own local totals").
- [Evidencia] **No existe comparación** entre los totales locales y `remoteSummary`/`total_pen` del servidor.
- El cálculo real del servidor (fórmula, redondeo, tipo numérico) es **NO DETERMINABLE** desde el cliente.

### 5.3 Dart

Dart **solo formatea** (`toStringAsFixed(2)`) en `v2/rendition_detail.dart`, `v2/widgets/dashboard_widgets.dart`, `v3/renditions_root.dart`, `v2/received/*`. No es motor de cálculo. Lee los montos como `double` (`numberField`).

---

## 6. VALIDACIONES

### 6.1 Validaciones de Rendición

Archivo/función: `RenditionValidation::header(start, end, projects, primary, folder, space)` — `src/cpp/renditionvalidation.h` (≈ línea 22). Se llama en `RenditionLocalStore::createDraft` (`:248`), `saveDraft` (`:309`) y `presentationBlocker` (`:1454`).

| Regla | Condición | Si falla |
|---|---|---|
| Fechas | `date()`: `QDate::fromString(value, ISODate)` válida **y** reformateo idéntico (`yyyy-MM-dd` estricto); `end >= start` | No se guarda; mensaje "El período no es válido…" vía `lastError`; el puente devuelve `CREATE_LOCAL_FAILED`/`UPDATE_LOCAL_FAILED` |
| Proyecto | `primary` no vacío y contenido en `projects` | "Selecciona proyectos asociados y un proyecto principal." |
| Ubicación documental | `folder` y `space` no vacíos | "Selecciona una carpeta documental dentro del proyecto." |
| Cuenta | `m_accountScope` no vacío (`createDraft`) | "Selecciona una cuenta antes de guardar." |
| row_version (pre-chequeo local) | Comando `update` con `expectedRowVersion` ≠ `rowVersion` local (`renditionflutterbridge.cpp:528`) | `ROW_VERSION_CONFLICT` a Flutter, sin red |
| V02 | `documentParentNodeId` vacío en `createRendition`/`editRendition` (`renditionrepository.cpp:184/219`) | `RENDITION_DOCUMENT_LOCATION_REQUIRED` |

### 6.2 Validaciones de Gasto

Archivo/función: `RenditionValidation::expense(draft, row)` — `src/cpp/renditionvalidation.h` (≈ línea 33). Se llama en `addLocalExpense` (`:413`), `saveLocalExpense` (`:487`) y `presentationBlocker` (`:1464`). Orden real de las reglas:

| # | Regla | Condición | Mensaje si falla |
|---|---|---|---|
| 1 | Fecha | `expenseDate` ISO estricta y `periodStart <= expenseDate <= periodEnd` (comparación de texto ISO) | "La fecha del gasto debe estar dentro del período de la rendición." |
| 2 | Proyecto | `projectId` ∈ `draft.projectIds` | "El proyecto del gasto debe estar asociado a la rendición." |
| 3 | Monto / decimales | texto con `^[0-9]+(\.[0-9]{1,2})?$` (punto decimal, **máx. 2 decimales**), finito, `> 0`, `<= 999999999999.99` | "El monto debe ser positivo, con un máximo de dos decimales." |
| 4 | Moneda | `currencyCode` ∈ {`PEN`, `USD`} | "Moneda no admitida." |
| 5 | Texto significativo (concepto) | `meaningfulText(concept)`: ≥ 2 palabras de ≥ 2 letras y ≥ 4 letras distintas | "Concepto: describe qué se compró…" |
| 6 | Texto significativo (justificación) | si no está vacía, `meaningfulText(justification)` | "Justificación: explica la relación del gasto con el trabajo." |
| 7 | Obligatorios | `concept`, `categoryCode`, `paymentMethodCode`, `supportTypeCode` no vacíos | "Falta completar: <clave>." |
| 8 | Método de pago | `paymentMethodCode != "UNKNOWN"` | "Indica el medio real de pago…" |
| — | Estado de cabecera | En `addLocalExpense`: cabecera en `CONFLICT`/`NEEDS_RECONCILIATION` bloquea | "Reconciliar la cabecera antes de añadir gastos." |
| — | Borrador | `assertDraftStatus` (solo `BORRADOR`) | No se guarda |
| — | Doble envío | mismo `clientIntentId` → devuelve el gasto existente | Sin duplicado |
| — | row_version (pre-chequeo local) | `saveExpense` con `expectedExpenseRowVersion` ≠ `rowVersion` local (`renditionflutterbridge.cpp:565`) | `EXPENSE_CONFLICT` a Flutter, sin red |

Comportamiento común al fallar: no se persiste; `lastError` con el mensaje; el puente devuelve `EXPENSE_LOCAL_FAILED`.

**Validaciones duplicadas en Dart** — `flutter/inge_earth/lib/renditions/v3/screens/expense_editor.dart` (≈ línea 604, `validator`) y `v3/state/smart_fill.dart:61` (`meaningfulExpenseText`):

| Regla | Dart | C++ | Diferencia observable |
|---|---|---|---|
| Campo obligatorio | `trim().isEmpty` → "Campo obligatorio" | regla 7 | Equivalente en intención |
| Monto | `double.tryParse(value.replaceAll(',', '.'))`, finito, `> 0`, regex `^\d+([.,]\d{1,2})?$` | regla 3 (solo `.`, máx. 999999999999.99) | Dart **acepta coma** decimal y no aplica tope máximo. [Inferencia] El valor se normaliza antes de llegar a C++; no verificado |
| Texto significativo | `meaningfulExpenseText` (concepto/justificación) | `meaningfulText` | Implementaciones separadas; equivalencia **NO DETERMINABLE** sin prueba |

### 6.3 Validaciones de Adjunto

| Regla | Archivo/función | Condición | Si falla |
|---|---|---|---|
| Tamaño | `addLocalAttachment` (`:709`); `reserveAttachment` (`renditionrepository.cpp:531`); `uploadReservedAttachment` (`:600`) | `0 < sizeBytes <= 20 MiB` (20·1024·1024) y `localUri` presente | "El sustento local no es válido o supera 20 MiB." / `RENDITION_ATTACHMENT_SIZE_INVALID` / `RENDITION_ATTACHMENT_LOCAL_FILE_INVALID` |
| Integridad local | `addLocalAttachment` | el archivo se lee completo y `size == sizeBytes` | "No se pudo conservar el sustento original." |
| Duplicados | `addLocalAttachment` | mismo `localUri` o mismo `sha256` (no archivado), o mismo `clientIntentId` | Devuelve el adjunto existente (sin duplicar) |
| Nombre | `addLocalAttachment` | `fileName` no vacío ni `.`/`..` | "No se pudo crear el mirror del sustento." |
| Gasto | `addLocalAttachment` | gasto no `archived` | "Este gasto fue eliminado." |
| Ruta/bucket | `RenditionAttachmentContract::valid` (`renditionattachmentcontract.h`) | bucket `project-files`; ruta de 6 segmentos `renditions/<uuid>/expenses/<uuid>/attachments/<attachment_id>`; último segmento = `attachment_id` | `RENDITION_ATTACHMENT_RESERVATION_INVALID` / `RENDITION_ATTACHMENT_PATH_INVALID` |
| Vigencia de reserva | listener de `attachmentReserved` (`renditionsynccontroller.cpp:86`) | `expires_at` válido y futuro, salvo `result_code == IDEMPOTENT_READY` | `RENDITION_ATTACHMENT_RESERVATION_EXPIRED` |
| Identidad al finalizar | listener de `attachmentFinalized` (`:139`) | `attachment_id` devuelto = el subido | `INVALID_RESPONSE` |
| Alcance | `processNext` (`:282`) | proyecto, `remoteId` de rendición, `expenseRemoteId` y `fileName` presentes | `RENDITION_ATTACHMENT_SCOPE_REQUIRED` |

### 6.4 Validaciones antes de sincronización

`RenditionLocalStore::pendingOperations` (`renditionlocalstore.cpp:1517`):

- Solo despacha entradas `PENDING_CREATE`/`PENDING_UPDATE`; además `ERROR` si la operación es idempotente (`rendition_create`, `rendition_delete`, `expense_create`, `expense_delete`, `attachment_reserve`), y `NEEDS_RECONCILIATION` para `attachment_reserve` y `*_delete`.
- Nunca despacha `present` (solo por confirmación humana).
- Omite rendiciones archivadas (salvo `rendition_delete`) y las que no están en `BORRADOR` o ya tienen `currentVersionId`.
- `expense_create` y `attachment_*` esperan a que la rendición tenga `remoteId`; `expense_update/delete` y `attachment_*` esperan a que el gasto tenga `remoteId` propio (distinto del de la rendición).
- Antes de cada envío: `markRenditionSyncing` / `markExpenseSyncing`; si falla la persistencia → `LOCAL_PERSISTENCE_FAILED`.
- Comando `sync` del puente: `stageLocalOnlyChanges(v02Enabled)` pasa los cambios `LOCAL_ONLY` a pendientes; si falla → `SYNC_STAGE_FAILED`.

### 6.5 Validaciones de presentación

`RenditionLocalStore::presentationBlocker` (`:1447`) y comando `present` (`renditionflutterbridge.cpp:644`):

| Regla | Mensaje / código |
|---|---|
| Estado agregado `SYNCED` | "Sincroniza los cambios pendientes antes de presentar." |
| `documentNodeId` presente | "La rendición necesita su documento .rend canónico confirmado." |
| Cabecera válida (`header`) | mensaje de §6.1 |
| Cada gasto activo válido (`expense`) | mensaje de §6.2 |
| ≥ 1 gasto activo | "Agrega al menos un gasto antes de presentar." |
| `status == BORRADOR` | "Sólo una rendición BORRADOR puede presentarse." / `PRESENT_NOT_ALLOWED` |
| Sin presentación en curso | `PRESENT_BUSY` |
| Repositorio/sync ociosos | `PRESENT_NOT_READY` |

Además se ejecuta un PULL de comprobación (`startRemotePull(…, "present_preflight")`) antes de `present_my_rendition_v01`.

### 6.6 Validaciones dependientes del backend

**NO DETERMINABLES desde el cliente.** Android solo propaga el código/mensaje que devuelve PostgREST (`responseErrorCode`/`responseErrorMessage`). Códigos `RENDITION_*` del servidor se usan tal cual como código de error. Las reglas del servidor (rangos, catálogos, períodos, unicidad, concurrencia) deben verificarse en el backend.

---

## 7. ALMACENAMIENTO LOCAL

| Aspecto | Valor real |
|---|---|
| Ubicación | `QStandardPaths::AppDataLocation + "/renditions/accounts/<sha256(accountScope)>.json"` (`RenditionLocalStore::storagePath`, `:174`) |
| Un archivo por cuenta | Sí (nombre = SHA-256 hex del `accountScope`) |
| Escritura | `QSaveFile` → escritura completa → `commit()` (atómica: archivo temporal + renombrado) (`persist`, `:1984`) |
| Formato | JSON compacto (`QJsonDocument::fromVariant`) |
| Raíz | `schemaVersion: 2`, `accountScope`, `updatedAt`, `nextSequence`, `renditions[]`, `outbox[]`, `editorDrafts` (mapa) |
| `renditions[]` | Rendiciones con `expenses[]` anidados; cada gasto con `attachments[]` anidados |
| `outbox[]` | Operaciones pendientes (§3.4) |
| `editorDrafts` | Mapa de borradores de editor (`saveEditorDraft`) |
| Carpeta de adjuntos | `<archivo>.json.attachments/<attachmentLocalId>/<fileName>` — copia íntegra del archivo elegido (espejo offline) |
| Cambios pendientes | Entradas de `outbox` según `pendingOperations` (§6.4) |
| Fallo de persistencia | `addLocalAttachment` restaura el estado previo en memoria si `persist()` falla; en el resto se informa `lastError` |

**Por qué NO es SQLite:** no hay tablas, columnas, índices, transacciones SQL ni migraciones. Es un único documento JSON reescrito completo en cada `persist()`. "Tabla", "índice" o "clave primaria" no aplican; las identidades son campos (`localId`, `remoteId`, `requestId`) dentro del JSON.

---

## 8. FLUJO REAL COMPLETO

### 8.0 Diagrama

```
Flutter (Dart)                renditions_bridge.dart: MethodChannel('inge.renditions/host').invokeMethod('submit', json)
   ↓
MethodChannel
   ↓
Java                          InGeQtActivity.java: handler del canal → nativeSubmitRenditionCommand(json)
   ↓
JNI                           renditionflutterbridge.cpp:1093 Java_..._nativeSubmitRenditionCommand
   ↓
C++                           RenditionFlutterBridge::submitFromAndroid → handleCommand
   ↓
RenditionLocalStore (JSON + outbox)  /  RenditionSyncController (cola)  /  RenditionRepository (red)
   ↓
Supabase RPC (rest/v1/rpc/...)  /  Supabase Storage (HTTP)
   ↓
respuesta
   ↓
C++                           RenditionRepository señales → SyncController.finishCurrent/failCurrent → LocalStore.mark*/merge*
   ↓
JNI                           RenditionFlutterBridge::sendEvent → QJniObject::callStaticMethod("dispatchRenditionEvent")
   ↓
Java                          InGeQtActivity.dispatchRenditionEvent(String)
   ↓
Flutter                       evento por el MethodChannel → estado/UI
```

Las respuestas a comandos son `sendResult(requestId, …)` / `sendError(requestId, code, message)`; el estado completo se publica con `publishState`/`publishStateNow`.

### 8.1 Crear Rendición
1. Comando `create` (`renditionflutterbridge.cpp:496`).
2. `RenditionLocalStore::createDraft`: valida `header`, genera `localId` y `requestId`, `status=BORRADOR`, `syncState=PENDING_CREATE` (o `LOCAL_ONLY` si `synchronize=false`), encola `rendition_create`, `persist()`.
3. `sendResult` con `pendingSync: true` (la UI no espera a la red).
4. `RenditionSyncController::synchronize` → `processNext` → `markRenditionSyncing` → `create_my_rendition_draft_v02`.
5. Respuesta → `finishCurrent` → `markRenditionSynced` (`:1591`): exige `id` y `row_version > 0`; guarda `remoteId`, `visibleCode`, `status`, `rowVersion`; `SYNCED`; propaga `renditionRemoteId` y `expectedRenditionRowVersion` a los gastos/adjuntos encolados; luego `getDocumentLocation`.

### 8.2 Editar Rendición
Comando `update` (`:523`): pre-chequeo de `expectedRowVersion` local → `saveDraft` (valida `header`) → `PENDING_UPDATE` → `update_my_rendition_draft_v02` con `p_expected_row_version` y `p_expected_document_node_version`.

### 8.3 Crear Gasto
Comando `saveExpense` sin `expenseLocalId` (`:560`) → `addLocalExpense` (valida, `totals`, encola `expense_create` con `expectedRenditionRowVersion`) → espera `remoteId` de la rendición → `create_my_rendition_expense_v02` → `markExpenseSynced`.

### 8.4 Editar Gasto
Comando `saveExpense` con `expenseLocalId`: pre-chequeo `expectedExpenseRowVersion` → `saveLocalExpense` (valida, `totals`) → `expense_update` → `update_my_rendition_expense_v01` con ambas versiones esperadas.

### 8.5 Eliminar
- Rendición: comando `deleteDraft` (`:596`) → `removeDraft` → `rendition_delete` → `delete_my_rendition_draft_v01` → `markDraftDeleted`.
- Gasto: comando `deleteExpense` (`:604`) → `removeLocalExpense` → `expense_delete` → `delete_my_rendition_expense_v01`.
- Adjunto: `archive_rendition_attachment_v01` (comando `archiveAttachment`, `:750`).
- Ambos borrados se rechazan si hay sincronización en curso (`SYNC_BUSY`).

### 8.6 PULL
`RenditionFlutterBridge::startRemotePull` (comandos `bootstrap`, `refresh`, `select`, `present_preflight`): `listProjects`, `listExpenseCatalogs`, `listRenditions(50)` (paginado); si hay rendición seleccionada con `remoteId`: `getRendition`, `listExpenses`, `getExpenseSummary`, `listVersions`, `listAttachments`, `getDocumentLocation`. Rechaza un PULL concurrente (`PULL_BUSY`).

### 8.7 MERGE
- `renditionsChanged` → `mergeRemoteRenditions` + `reconcileCompleteRenditionList`.
  - Ignora filas con `row_version` menor que la local ("A delayed response must never roll back a newer local server version").
  - No toca rendiciones `PRESENTADA` con `currentVersionId`.
  - Si la local está en `NEEDS_RECONCILIATION`, el servidor está en `BORRADOR` y la versión es igual: vuelve a `PENDING_UPDATE` para repetir la intención original sin adelantar la versión esperada.
  - Si ya hay gastos cargados, los totales locales prevalecen.
- `expensesLoaded` → `mergeRemoteExpenses`; `attachmentsLoaded` → `mergeRemoteAttachments`; `summaryLoaded` → `adoptRemoteSummary`; ubicación → `adoptDocumentLocation`.
- [Evidencia parcial] El interior de `mergeRemoteExpenses` no se auditó línea por línea; su comportamiento está cubierto por `tests/renditions/checks.cpp` (líneas 39–74: el PULL conserva ediciones pendientes, no duplica, no adopta el UUID del padre como identidad del gasto, reconcilia totales).

### 8.8 PUSH
`RenditionSyncController::processNext` (`:188`) toma **la primera** operación de `pendingOperations` y la ejecuta; `finishCurrent` (`:307`) la confirma y llama de nuevo a `processNext`. Es secuencial y se detiene en el primer fallo.

### 8.9 Conflicto
`failCurrent` (`:341`) clasifica (§9.3), marca el estado en el store, emite `syncStopped(state, message)` y, si el estado es `CONFLICT` o `NEEDS_RECONCILIATION`, lanza un PULL dirigido (`listRenditions(50)`, `getRendition`, `listExpenses`, `getExpenseSummary`, `listAttachments`, `getDocumentLocation`). No hay resolución automática ni RPC de resolución.

### 8.10 Adjuntos
Comando `attachSupport` (`:627`) → `addLocalAttachment` (espejo local + `attachment_reserve` en outbox) → ver §10.

### 8.11 Recuperación offline
El outbox persiste en disco. `RenditionSyncController` (constructor, `:28-40`) sincroniza:
- al volver a primer plano (`applicationStateChanged` → `ApplicationActive`);
- al recuperar red (`QNetworkInformation::reachabilityChanged` → `Online`);
- al cambiar de cuenta (`accountIdChanged`);
- al arrancar (`QTimer::singleShot(0, …)`).

### 8.12 Presentación
Comando `present` (`:644`): validaciones §6.5 → `m_presentAfterSync` → PULL `present_preflight` → `present_my_rendition_v01` con `p_request_id` persistido (`ensurePresentationRequestId`) → luego `getRendition`, `listVersions`, `listRenditions`. Nunca se ejecuta desde la sincronización automática.

---

## 9. SINCRONIZACIÓN Y CONCURRENCIA

### 9.1 Modelo
- **Local-first:** toda mutación se valida y persiste en el JSON local antes de cualquier red; la UI recibe `pendingSync: true` de inmediato.
- **Outbox:** cola persistente ordenada por `sequence`; una entrada por (operación, rendición, hijo) — `upsertOutbox` reemplaza la intención pendiente previa.
- **request_id / idempotencia:** `requestId` generado al crear la intención y reutilizado en reintentos para `create_my_rendition_draft_v02`, `create_my_rendition_expense_v02`, `reserve_rendition_attachment_v01`, `present_my_rendition_v01`, `create_rendition_admin_note_v01`.
- **row_version / expected_row_version:** control de concurrencia optimista (CAS) en update/delete/presentación/archivo; el valor esperado es el `rowVersion` local confirmado por el servidor.
- **Lectura de versión de respuesta:** `rendition_row_version` (o `renditionRowVersion`) tiene prioridad sobre `row_version` (`remoteRowVersion`).
- **Stale:** respuestas con `row_version` menor que la local se ignoran en el MERGE.

### 9.2 Retry
- Los reintentos ocurren al volver a llamar `synchronize()` (eventos §8.11 o comando `sync`); **no hay backoff ni temporizador de reintento** en `RenditionSyncController`.
- Reintentables automáticamente: `PENDING_*`, `ERROR` en operaciones idempotentes, `NEEDS_RECONCILIATION` en adjuntos y borrados (§6.4).
- `expense_create` en `ERROR` conserva la misma intención y `requestId` (comentario en `failCurrent`: "CREATE V02 es idempotente").

### 9.3 Qué hace Android ante cada respuesta

Código producido por `callRpc` → clasificación en `failCurrent`:

| Situación | Código | Estado resultante |
|---|---|---|
| 401 | `AUTH_REQUIRED` | `ERROR` en operaciones de cabecera y `expense_create`; `NEEDS_RECONCILIATION` en `expense_update`/`expense_delete` (rama `kind.startsWith("expense_")`); en adjuntos según fase (RESERVE → `ERROR`, UPLOAD/FINALIZE → `NEEDS_RECONCILIATION`) |
| 4xx con código/mensaje que contiene `CONFLICT` o `ROW_VERSION` | código del backend | `CONFLICT` |
| 4xx otro | código del backend | `ERROR` (cabecera, `expense_create`); `NEEDS_RECONCILIATION` para `expense_update`/`expense_delete` (rama `kind.startsWith("expense_")`) |
| 5xx | `NETWORK_AMBIGUOUS` | `NEEDS_RECONCILIATION` en `rendition_update`, `expense_update`, `expense_delete`, `attachment_reserve` (fase ≠ RESERVE); `ERROR` en `rendition_create`/`rendition_delete`/`expense_create` |
| Timeout (abort a 30 s) | `NETWORK_AMBIGUOUS` | igual que 5xx |
| Error de red | `NETWORK_AMBIGUOUS` | igual que 5xx |
| `ROW_VERSION_CONFLICT` | pre-chequeo local del puente (`update`) | Error inmediato a Flutter; no se envía nada |
| `EXPENSE_CONFLICT` | pre-chequeo local del puente (`saveExpense`) | Error inmediato a Flutter; no se envía nada |
| `CONFLICT` (cualquier código que lo contenga) | — | `CONFLICT` + PULL dirigido |
| `INVALID_RESPONSE` / `RENDITION_INVALID_RESPONSE` | JSON inválido o respuesta sin identidad/versión | Tratado como ambiguo: `NEEDS_RECONCILIATION` en `rendition_update`, `expense_update`, `expense_delete` y adjuntos en UPLOAD/FINALIZE; `ERROR` en `rendition_create`/`rendition_delete`/`expense_create` |
| Fallo de Storage | `ATTACHMENT_UPLOAD_NEEDS_RECONCILIATION` (reintentable) o el error de Storage | `NEEDS_RECONCILIATION` (fase UPLOAD/FINALIZE) |

Tras `CONFLICT` o `NEEDS_RECONCILIATION` se ejecuta el PULL dirigido de §8.9. La cola se detiene (`setBusy(false)`, `syncStopped`).

---

## 10. STORAGE / ADJUNTOS

### 10.1 Fases

| Fase | Qué ocurre | Evidencia |
|---|---|---|
| RESERVE | RPC `reserve_rendition_attachment_v01` (siempre se repite antes de subir para renovar la reserva, conservando UUID y ruta) | `processNext` (`renditionsynccontroller.cpp:289-299`) |
| (validación) | bucket/ruta (`RenditionAttachmentContract::valid`), vigencia (`expires_at`) | listener `attachmentReserved` (`:67-116`) |
| UPLOAD | **HTTP de Storage** (no RPC): `RenditionExportService::shared(...)->storage()->uploadReserved(localFile, bucket, objectPath, mimeType, cb)` | `RenditionRepository::uploadReservedAttachment` (`renditionrepository.cpp:580`) |
| FINALIZE | RPC `finalize_rendition_attachment_v01(p_attachment_id)` | listener `attachmentUploaded` (`:117-133`) |
| READY | `attachment_id` devuelto = el subido → `READY` | listener `attachmentFinalized` (`:134-155`) |
| Atajo | `result_code == IDEMPOTENT_READY` en la reserva → `READY` directo | `:93-102` |
| ERROR | fallo en fase RESERVE/ERROR | `failCurrent` (`:367-380`) |
| CONFLICT | código con `CONFLICT`/`ROW_VERSION` | `failCurrent` |
| NEEDS_RECONCILIATION | fallo en fase UPLOAD/FINALIZE | `failCurrent`; reintentable (§6.4) |

### 10.2 Contrato de ubicación

- **Bucket:** `project-files` (exigido por `RenditionAttachmentContract::valid`).
- **Ruta:** `renditions/<rendition_uuid>/expenses/<expense_uuid>/attachments/<attachment_id>` (6 segmentos; el último debe ser el `attachment_id`). La clave la genera el servidor en la reserva; el cliente nunca la fabrica (comentario en `renditionattachmentcontract.h`).
- **Tamaño máximo:** 20 MiB (validado en cliente en 3 puntos, §6.3).
- **Idempotencia:** `p_request_id` en la reserva + deduplicación local por `sha256`/`localUri`/`clientIntentId`.
- **Acceso (lectura):** RPC `get_rendition_attachment_access_v01`; para la bandeja recibida, URL firmada de Storage con `expiresIn: 60` (`accessReceivedAttachment`, `:672-716`).

### 10.3 Separación RPC vs Storage HTTP

| Paso | Tipo |
|---|---|
| `reserve_rendition_attachment_v01` | RPC PostgREST |
| Subida del archivo | HTTP Storage (`RenditionExportService::storage()->uploadReserved`) |
| `finalize_rendition_attachment_v01` | RPC PostgREST |
| `list_rendition_attachments_v01`, `get_rendition_attachment_access_v01`, `archive_rendition_attachment_v01` | RPC PostgREST |
| Firma de URL (recibidas) | HTTP Storage `POST /storage/v1/object/sign/...` |

[Inferencia] Los detalles internos de `RenditionExportService::storage()->uploadReserved` (cabeceras, `x-upsert`) no se auditaron en esta revisión.

---

## 11. CALC-01 A CALC-05

| Caso | Datos de entrada | Resultado esperado | Resultado Android | Estado |
|---|---|---|---|---|
| CALC-01 | — | — | — | **NO ENCONTRADO** |
| CALC-02 | — | — | — | **NO ENCONTRADO** |
| CALC-03 | — | — | — | **NO ENCONTRADO** |
| CALC-04 | — | — | — | **NO ENCONTRADO** |
| CALC-05 | — | — | — | **NO ENCONTRADO** |

Búsqueda realizada (patrón `CALC[-_]0[1-5]`) en: `src`, `flutter/inge_earth/lib`, `flutter/inge_earth/test`, `tests`, `docs`, `_server_handoff`, `handoff`, `outputs`, `qml`, `android`, `.md` de la raíz del proyecto y las carpetas `C:\Users\PC-02\Documents\InGePlus\AUDITORIA_CIERRE_CALICATAS_*`. Sin coincidencias.

Evidencia relacionada (NO equivalente a CALC-01..05) — `tests/renditions/checks.cpp`:

| Línea | Etiqueta | Aserción |
|---|---|---|
| 63 | "persisted total" | Tras reabrir el store, `totalPen == 20` (gasto editado de 10.00 a 20.00 PEN) |
| 74 | "PULL reconciles totals" | Tras PULL con 2 gastos, `totalPen == 70` |

Última ejecución registrada: `outputs/renditions-closure-native-tests.log` y `outputs/renditions-closure-flutter-tests.log` (22/09/2026: "PASS…" / "All tests passed!"). Son **anteriores** a los cambios de Rendiciones sin commit (24–26/09) y no se re-ejecutaron para este paquete.

> Estos tests verifican persistencia y reconciliación de totales locales; **no** constituyen casos de cálculo acordados con Web. CALC-01..05 deben definirse.

---

## 12. PUNTOS DE CONTRASTE WEB ↔ ANDROID

| # | Tema | Android | Evidencia | Web debe contrastar |
|---|---|---|---|---|
| 1 | Representación de montos | Texto en el store local y en la validación; `double` en Dart | `addLocalExpense` (`amount` como texto); `ExpenseData.amount` | Tipo usado en formularios, estado y almacenamiento |
| 2 | Decimal vs double | `p_amount` se envía como **número JSON double** (`amount.toDouble()`) | `renditionrepository.cpp:401` | Si Web envía número o texto; tipo SQL de la columna/argumento (`numeric`?) y riesgo de precisión |
| 3 | Redondeo | `qRound64(amount*100)` por gasto; acumulación en céntimos enteros; `/100.0` | `RenditionValidation::totals` | Regla de redondeo de Web y del servidor (half-up, banker's, truncado) |
| 4 | Cálculo de totales | Local por moneda (PEN/USD), excluye archivados; no se compara con el servidor | `totals`, `adoptRemoteSummary`, `mergeRemoteRenditions` | Si Web calcula en cliente o usa `get_my_rendition_expense_summary_v01`; qué total es autoritativo |
| 5 | Validaciones duplicadas | C++ (`RenditionValidation`) + Dart (`expense_editor.dart`, `smart_fill.dart`) con diferencias (coma decimal, tope) | §6.2 | Reglas de Web y si coinciden con las de Android |
| 6 | Validaciones backend | NO DETERMINABLE; Android propaga códigos `RENDITION_*` | `responseErrorCode` | Lista de reglas/códigos del servidor que Web ya maneja |
| 7 | row_version | CAS en update/delete/present/archive; prioridad `rendition_row_version` sobre `row_version` | `remoteRowVersion`, §4 | Qué versión envía Web y cuál lee de cada respuesta |
| 8 | request_id | UUID por intención, persistido y reutilizado en reintentos | `createDraft`, `addLocalExpense`, `addLocalAttachment`, `ensurePresentationRequestId` | Si Web usa request_id y en qué RPC |
| 9 | Estados | `BORRADOR`/`PRESENTADA` + 8 estados de sync locales | `renditionlocalstore.cpp:24-31` | Vocabulario de estados de Web (servidor y cliente) |
| 10 | RPC V02 | `create_my_rendition_draft_v02`, `update_my_rendition_draft_v02`, `create_my_rendition_expense_v02`; el resto `_v01` | §4.1 | Versión de cada RPC que usa Web |
| 11 | Storage | Bucket `project-files`, ruta de 6 segmentos fijada por el servidor | `RenditionAttachmentContract::valid` | Bucket y ruta de Web |
| 12 | Conflictos | Sin RPC de resolución; `CONFLICT`/`NEEDS_RECONCILIATION` + PULL dirigido | `failCurrent` | Cómo detecta y resuelve Web los conflictos |
| 13 | Adjuntos | RESERVE → UPLOAD → FINALIZE → READY; reserva repetida en cada intento; máx. 20 MiB; dedup por sha256 | §10 | Flujo y límites de Web |
| 14 | PULL/MERGE | `list_my_renditions_v01` paginado por (`updated_at`, `id`); no retrocede versiones; totales locales prevalecen si hay gastos | `listRenditions`, `mergeRemoteRenditions` | Estrategia de lectura y caché de Web |
| 15 | Presentación | Solo manual; requiere todo `SYNCED`, documento `.rend`, ≥ 1 gasto válido; PULL previo | `presentationBlocker`, comando `present` | Precondiciones de Web para presentar |
| 16 | Identidad Rendición/Gasto | `localId` (dispositivo) + `remoteId` (servidor; `<entidad>_id` o `id`); el gasto nunca adopta el UUID del padre | `RenditionLocalStore::remoteId`, `checks.cpp:73` | Campo de identidad que Web lee en cada respuesta |
| 17 | Respuestas RPC | Se toma la primera fila o la lista; estructura completa NO DETERMINABLE | `firstRow`, `rows` | Forma real de las respuestas que Web consume |
| 18 | Errores | 401→`AUTH_REQUIRED`; 4xx→código backend; 5xx/red/timeout→`NETWORK_AMBIGUOUS`; JSON inválido→`RENDITION_INVALID_RESPONSE` | `callRpc`, `responseErrorCode` | Catálogo de errores y su manejo en Web |

---

## 13. PROPUESTA DE CONTRATO COMÚN (candidatos de comparación)

> Esta sección es una **propuesta de comparación**, **NO** una decisión de arquitectura. No implica migración ni cambios en ningún cliente.

Elementos candidatos a fijarse como contrato común entre Web, Android y Supabase:

- **IDs:** campo de identidad en cada respuesta (`<entidad>_id` vs `id`); relación `localId`/`remoteId` en clientes offline.
- **DTO:** nombres canónicos (snake_case del servidor) y su forma en lista vs detalle (`RenditionContract::normalize` documenta que hoy difieren).
- **Montos:** tipo de transporte (texto decimal vs número) y escala (2 decimales).
- **Redondeo:** regla única (y si se aplica por gasto o sobre el total).
- **Totales:** fuente autoritativa (servidor vs cliente) y si los clientes deben comparar.
- **Estados:** vocabulario de `status` del servidor y semántica de sync visible al usuario.
- **row_version:** qué versión se espera y cuál se devuelve en cada RPC de escritura (cabecera vs gasto).
- **request_id:** RPC que lo exigen y garantía de idempotencia.
- **RPC:** versión vigente por operación (`_v01`/`_v02`) y retiro de las inactivas.
- **Errores:** catálogo de códigos (`RENDITION_*`, conflicto, autenticación) y su clasificación (reintentable / conflicto / definitivo).
- **Validaciones críticas:** fechas, monto, moneda, proyecto, catálogos obligatorios, texto significativo, adjuntos (y cuáles son autoritativas en el servidor).
- **Storage:** bucket, formato de ruta, tamaño máximo, flujo reserve/upload/finalize.
- **Conflictos:** detección y mecanismo de resolución.

---

## 14. ESTADO DEL PILOTO

### Estado actual

- Auditoría Android: COMPLETA
- Paquete técnico: COMPLETO
- APK/commit verificable: PENDIENTE
- CALC-01..05: PENDIENTES DE DEFINICIÓN
- Contraste Web ↔ Android: PENDIENTE
- Piloto E2E: PENDIENTE
- Migración: NO INICIADA

---

## 15. CONCLUSIÓN EJECUTIVA PARA WEB

1. Android implementa Rendiciones como **local-first**: UI Flutter, puente MethodChannel → Java → JNI → C++, y un dominio C++ que guarda todo en un **JSON por cuenta** (no SQLite) con un **outbox** persistente.
2. Solo C++ (`RenditionRepository`) habla con Supabase, mediante las RPC listadas en §4 (contrato V02 activo) y Storage HTTP para sustentos.
3. La concurrencia es optimista (`p_expected_*_row_version`) y la idempotencia se basa en `p_request_id`.
4. Los conflictos se marcan como `CONFLICT`/`NEEDS_RECONCILIATION` y disparan un PULL dirigido; no hay RPC de resolución.
5. Web puede contrastar de inmediato: nombres y argumentos de RPC, bucket/ruta de adjuntos, reglas de validación de §6 y estados de §3.4.
6. Diferencias críticas a revisar: `p_amount` enviado como número double; totales calculados en el cliente en céntimos y no comparados con el servidor; validaciones de gasto duplicadas en C++ y Dart con pequeñas diferencias.
7. Falta comprobar: la forma completa de las respuestas RPC, las validaciones del servidor, el cálculo del servidor y la correspondencia exacta del APK con un commit.
8. CALC-01..05 no existen en el proyecto y deben definirse en común.
9. Siguiente paso sugerido: que Web complete la tabla de §12 con su implementación, definir CALC-01..05 y ejecutar el piloto E2E sobre un APK construido desde un commit sin cambios pendientes.

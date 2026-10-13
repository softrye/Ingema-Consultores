# Calicatas — colaboración en vivo (Android ↔ Web)

Android adopta el protocolo **ya existente en Web**. No hay protocolo Android propio.

```
CANONICAL_PROTOCOL_SOURCE = ingeplus-web / feature/calicatas-cloud-media-04a
                            (384dc54 Presence · 60acf73 cambios por campo · cabe8d2 recepción sin reload)
CANONICAL_CHANNEL         = calicata:<calicatas.id>   (private = true)
CANONICAL_FIELD_EVENT     = calicata-field-change
CANONICAL_FIELD_RPC       = apply_calicata_field_change_v02
CANONICAL_PROSE_EVENT     = calicata-prose            (Yjs; Web)
PRESENCE_KEY              = userId
PRESENCE_META             = userId, name, field, joinedAt
CHANNEL_AUTHORIZATION     = realtime.messages RLS (SELECT/INSERT, presence + broadcast)
                            vía private.can_join_calicata_presence_v01(topic)
                            migración Web 20260917190000_calicatas_presence_channel_v01.sql
```

Fuentes Web de referencia: `src/lib/calicatas/presenceService.ts`, `presenceIdentity.ts`,
`fieldChanges.ts`, `fieldChangeService.ts`, `liveText.ts`,
`src/components/calicatas/CalicataDetailPanel.tsx`.

> Nota de verificación: este contrato se implementó a partir de la especificación
> verificada por el equipo en GitHub. Desde este equipo no se pudo leer el repositorio
> privado (sin sesión de GitHub en esta máquina), así que la forma exacta de la fila
> devuelta por la RPC y el soporte `LAB_RESULT` del servidor quedan por confirmar
> (ver §8).

## 1. Dos capas

| Capa | Mecanismo | Autoridad |
|---|---|---|
| Campo en vivo | `apply_calicata_field_change_v02` → broadcast `calicata-field-change` | La RPC (idempotente por `changeId`, solo BORRADOR, decide el cambio vigente) |
| Todo lo demás | Sync completo de `CalicataCloudService` (autosave/Guardar, `row_version` CAS, Smart Document, JSON InGeDrive) | `row_version` |

Entrar al canal ≠ poder editar: la política de Realtime deja estar en Presence/Broadcast
a quien puede leer; la RPC decide si puede modificar.

## 2. Evento `calicata-field-change`

```ts
{
  changeId: string,                                    // uuid, idempotencia de la RPC
  target: { type: "CALICATA" | "STRATUM" | "LAB_RESULT", id: string },
  field: string,
  value: string | null,                                // p_value es text
  authorId: string,                                    // auth.uid() del autor
  at: string                                           // ISO
}
```

Sin `event_id`, `seq`, `base_revision`, `sent_at` ni `section`.

### Campos

- `CALICATA` (`target.id` = id de la calicata): `code, title, location, progresiva,
  easting, northing, altitude_m, depth_m, groundwater_depth_m, utm_zone, supervisor,
  machine, start_date, end_date, description, observations`.
- `STRATUM` (`target.id` = id cloud del estrato): `to_depth_m, description,
  moisture_condition, consistency_compaction, excavability, color, sample_type,
  observations`. `from_depth_m` es derivado y `sequence_number` es estructura:
  **no** son campos en vivo.

## 3. Flujo Android (persistir primero, anunciar después)

```
edición local → eco inmediato en la UI
  → (debounce 150 ms que agrupa commits) diff por campo canónico no-prose
  → CalicataCloud.applyFieldChange(doc, type, id, field, value)
      → RPC apply_calicata_field_change_v02(p_project_id, p_calicata_id, p_target_type,
                                            p_target_id, p_change_id, p_field, p_value, p_client_at)
      → fila vigente devuelta por el servidor
          APPLIED     changeId vigente == el nuestro
          SUPERSEDED  vigente es otro cambio → Android aplica ese valor (sin dirty)
          REFUSED     decisión del servidor (solo borrador, no autorizado, campo desconocido)
          UNAVAILABLE red/servidor/RPC no desplegada
      → solo APPLIED/SUPERSEDED: broadcast calicata-field-change con el CAMBIO VIGENTE
```

- REFUSED/UNAVAILABLE **nunca** se anuncian. El valor sigue en el sync completo normal.
- Solo se usa la vía en vivo si la ficha tiene id cloud, está en BORRADOR y el canal
  está unido. Si no, el valor viaja únicamente por el sync completo.
- Un cambio en vivo **no mueve** `calicatas.row_version` (CALICATA conserva
  `OLD.row_version`; STRATUM/LAB_RESULT no tocan la fila raíz). Android no lee ni
  adopta `row_version` tras la RPC; el CAS del guardado completo no cambia.
- La RPC devuelve `public.calicata_field_changes`: `row.id` → `changeId`,
  `row.author_id` → `authorId`, `row.client_at` → `at`, `row.value` → `value`.
- Estratos: solo los que tienen id cloud. Altas, bajas y reordenamiento son
  **estructura**: siguen por la RPC propia + CAS del guardado completo.

## 4. Recepción Android (sin reload)

1. `broadcast.event == "calicata-field-change"`; `target.type` ∈ {CALICATA, STRATUM} y
   `field` en la lista canónica (lo demás se ignora).
2. CALICATA: `target.id` debe ser la calicata abierta.
3. **Regla self del contrato Web**: `authorId == auth.uid()` → ignorar.
4. Deduplicación local por `changeId` (no forma parte del payload).
5. Se aplica SOLO ese campo (`applyRemoteFieldChange`) con `applyingLivePatch`:
   sin dirty, sin autosave, sin re-emisión, sin hydrate ni reconstrucción.
   `to_depth_m` recalcula localmente `from_depth_m` del siguiente estrato.
   `depth_m` no se aplica: Android la deriva de los estratos.
6. `calicata-prose` se ignora en Android (ver §6).

Al reconectar no se reproducen cambios perdidos: si la ficha está limpia, se revalida
con el hydrate existente.

## 5. Presence

- Clave: `userId`. Meta exacta: `{ userId, name, field, joinedAt }` (`field: null` = viendo).
- Web agrupa las pestañas de una persona. Android muestra una entrada por persona.
- Android no añade `sessionId`/`surface` al meta. `field` es una etiqueta legible de
  la celda en edición (`Supervisor`, `Progresiva`, `Corte 2, Descripción`) o `null`.
- Android sale del canal en segundo plano y vuelve a entrar al volver (heartbeat 25 s,
  reintentos 1→2→4→8→15→30 s, renovación de token).

## 6. Prose

`PROSE_ANDROID_STATUS = DEFERRED`

Web edita en simultáneo los campos prose con Yjs (`calicata-prose`, `liveText.ts`).
Android no implementa Yjs. Para no corromper texto colaborativo:

- Android **no** envía en vivo los campos prose: CALICATA `title`, `description`,
  `observations`; STRATUM `description`, `observations`. Persisten por el sync completo.
- Android ignora `calicata-prose`.
- Si llega un `calicata-field-change` durable de un campo prose, se aplica ese valor.

Portar el protocolo de `liveText.ts` (Yjs) es un trabajo aparte.

## 7. Lo que Android soporta tras esta pasada

| Capacidad | Estado |
|---|---|
| Canal privado `calicata:<id>` | Sí |
| Presence canónica (userId + 4 claves) | Sí |
| Envío `calicata-field-change` tras confirmación durable | Sí (CALICATA y STRATUM no-prose) |
| APPLIED / SUPERSEDED / REFUSED / UNAVAILABLE | Sí |
| Recepción por campo sin reload | Sí (CALICATA y STRATUM) |
| LAB_RESULT | Sí (target = id del estrato; 14 campos; envío tras RPC durable, recepción por campo sin dirty/autosave/re-emisión; LL/LP con decimales no viajan en vivo mientras el servidor sea integer) |
| Prose (Yjs) | Diferido |
| Estructura | Por guardado completo (RPC + CAS), sin evento en vivo |

## 8. Pendiente de verificación contra la fuente

- Confirmado: fila `calicata_field_changes` (`id`, `author_id`, `client_at`, `value`);
  el lector prioriza `id` y conserva alias defensivos.
- `LAB_RESULT` (sieve_max_pct, sieve_no4_pct, sieve_2mm_pct, sieve_04mm_pct,
  sieve_008mm_pct, liquid_limit, plastic_limit, natural_moisture_pct, primary_sucs,
  is_composite, secondary_sucs, aashto, laboratory_source, test_date) queda para la
  pasada de Laboratorio.

## 9. Logs Android

`INGE_LIVE_JOIN`, `INGE_LIVE_READY`, `INGE_LIVE_RECONNECT`, `INGE_LIVE_DISCONNECT`,
`INGE_LIVE_PRESENCE`, `INGE_LIVE_FIELD_TX_BEGIN`,
`INGE_LIVE_FIELD_TX_(APPLIED|SUPERSEDED|REFUSED|UNAVAILABLE)`, `INGE_LIVE_FIELD_RX`,
`INGE_LIVE_REVALIDATE(_SKIPPED|_FAILED)`. Se registran rutas, nunca valores.

## 10. Laboratorio: Campo vs Laboratorio y persistencia

| Dato | Fuente | Cloud |
|---|---|---|
| SUCS/AASHTO de campo | Perfil (`field_sucs`/`field_aashto` si hay confirmación de lab) | `calicata_strata.sucs/aashto` vía `set_my_calicata_stratum_field_classification_v01` (migración 20260930200100, **no aplicada**) |
| SUCS/AASHTO sugeridos, IP, IG, Cu, Cc | Derivados locales (CalicataRules) | No se guardan (se recalculan) |
| SUCS/AASHTO de laboratorio | Solo confirmación explícita (`lab_confirmed_sucs/aashto`) | `calicata_lab_results.primary_sucs/secondary_sucs/is_composite/aashto` |
| Clasificación global del estrato | `sucs`/`aashto` del estrato (lab confirmado si existe) | Export Excel/PDF/Smart Document usa esta global |
| Granulometría, LL, LP, humedad natural, laboratorio, fecha | Ensayo | `upsert_my_calicata_lab_result_v02` (enteros) / `v03` (decimales, migración 20260930200000, **no aplicada**) |
| D10/D30/D60, NP, observaciones de lab, A-8 visual | Ensayo / acción explícita | `set_my_calicata_lab_extension_v01` (migración 20260930200100, **no aplicada**) |

- `primary_sucs` ya **no** se copia desde el SUCS de campo.
- Datos legados: filas cloud antiguas cuyo `primary_sucs` salió de ese espejo se leen como laboratorio.
- NP es `is_nonplastic = true`, que es distinto de LP NULL (sin ensayo) y de LP 0.
- A-8 va en `visual_classification`, porque no está en el catálogo AASHTO.
- Si una RPC nueva aún no existe (`PGRST202`/`42883`):
  - el valor local se conserva;
  - solo ese estrato queda con `lab_cloud_pending` (`LAB_LIMITS`, `LAB_EXTENSION` o `FIELD_CLASS`);
  - el resto de la ficha se sincroniza;
  - el estado muestra "Lab pendiente", nunca "Al día".
- Al rehidratar desde el servidor se conservan del documento local los valores pendientes.
- Historial: solo hitos locales reales (fecha de ensayo, confirmación, A-8). Sin historial de servidor: "Sin historial sincronizado".
- Seguimiento (dueño del contrato Web): `apply_calicata_field_change_v02` debe convertir LL/LP de LAB_RESULT a numeric.

# Eliminar borrador desde la lista: diagnostico y migracion aplicada

Fecha: 2026-10-27. Proyecto: InGePlus-Dev (`aalmeaqhhlhzwwzsbbxz`).
Estado: cliente corregido en fuentes; SQL aprobado y aplicado exclusivamente en
InGePlus-Dev mediante apply_migration, version `20261027143355`. Sin build,
instalacion, commit ni push. Ademas del DDL y su registro de migracion, las
operaciones remotas fueron de solo lectura: no se invoco ningun RPC de borrado,
ni siquiera con rollback. No se accedio al proyecto IngePlus (`zzoaqymmejdpfrolecps`).

## Evidencia remota

Los logs API/Postgres muestran dos intentos Android (`InGePlus-Android/1.0`)
de la cuenta propietaria:

| Hora UTC | Hora Lima | RPC | HTTP |
| --- | --- | --- | --- |
| 2026-10-27 14:20:24.175 | 09:20:24.175 | get_rendition_effective_v06 | 200 |
| 2026-10-27 14:20:25.183 | 09:20:25.183 | delete_my_rendition_draft_v01 | 400 |
| 2026-10-27 14:20:56.072 | 09:20:56.072 | delete_my_rendition_draft_v01 | 400 |

Los errores Postgres a 14:20:25.586 y 14:20:56.286 registran:

```text
RENDITION_NOT_EDITABLE
PL/pgSQL function private.guard_rendition_financial_work_v03() line 14 at RAISE
SQL statement "UPDATE public.renditions r SET archived_at=v_at,..."
PL/pgSQL function public.delete_my_rendition_draft_v01(uuid,bigint) line 30 at SQL statement
```

La funcion `get_rendition_effective_v06` desplegada no contiene ese RAISE;
consulta legibilidad y calcula `can_edit_content`. La lectura efectiva con el
contexto de la cuenta propietaria devuelve permiso de edicion verdadero para
el borrador investigado. No se modificaron privilegios ni funciones para leerlo.

La fila comprobada es `prueba 5`, `RDC-2026-000035`, UUID
`06607ee6-ec99-49d6-8b2e-d4f38633dccd`: BORRADOR, row_version=1,
current_version_id=NULL, archived_at=NULL, is_blocked=false, cero versiones,
cero gastos activos, una asociacion primaria activa y una vinculacion documental.

Limite de la evidencia: los logs conservan la sentencia parametrizada `$1`,
sin el cuerpo JSON ni el valor de `p_rendition_id`. Por ello NO se puede
certificar retrospectivamente que esos dos POST enviaron este UUID. La cuenta,
cliente, RPC y punto exacto del error si estan confirmados. El nuevo mensaje
`INGE_RENDITIONS_DELETE` en logcat muestra el UUID y la version reales enviados,
sin tokens, correos ni contrasenas.

## Causa

El RPC existente valida propietario, perfil activo, estado, ausencia de versiones
y CAS. Despues archiva sustentos, gastos y `rendition_projects`, y finalmente
actualiza `renditions.archived_at`.

El trigger BEFORE UPDATE `guard_rendition_financial_work_v03` vuelve a consultar
`rendition_owner_content_editable_v03` -> `rendition_content_editable_v05` ->
`rendition_content_editable_v05_before_archive_v07`. Esta ultima exige una
asociacion primaria con archived_at=NULL. El UPDATE previo acaba de quitarla;
por eso el trigger rechaza la cabecera, aunque el RPC haya pasado sus guardas.
Toda la transaccion revierte, incluida la eliminacion de asociaciones.

Hay otro obstaculo si solo se cambia el orden de UPDATE: el constraint trigger
diferido `enforce_rendition_smart_primary_project_v01` exige mantener la
asociacion primaria mientras exista `document_smart_bindings`, incluso cuando
la raiz ya este archivada. Mover el UPDATE de proyectos al final no basta.

## Cambios

- `src/cpp/renditionflutterbridge.cpp`: retira la consulta previa agregada en la
  correccion anterior y usa el localId de la accion para el flujo existente.
- `src/cpp/renditionrepository.h` y `.cpp`: retiran getDraftDeletionContext;
  deleteDraft registra solo UUID/version y conserva los parametros del RPC.
- `src/cpp/renditionlocalstore.cpp`: removeDraft deja de exigir capacidad de
  edicion de contenido; mantiene estado, ausencia de version actual, bloqueo de
  snapshots, conflictos y operaciones en vuelo. El servidor sigue siendo la
  autoridad de propietario, perfil activo, historial de versiones y CAS.
- `tests/renditions/checks.cpp`: regresion nativa con dos rendiciones, permiso
  ausente/falso y comprobacion de UUID, CAS y preservacion de la otra fila.
  Agregada en fuentes, sin compilar/ejecutar por el alcance de esta entrega.
- `supabase/migrations/20261027143355_rendition_draft_delete_preserve_project_bindings.sql`:
  migracion aplicada que conserva rendition_projects como historial
  de la raiz archivada. Mantiene guardas, triggers, ACL, RLS, auditoria,
  idempotencia y archivado de gastos/sustentos. No cambia datos al instalarla.
  La propuesta original `docs/sql_proposals/20261027142558_rendition_draft_delete_preserve_project_bindings.sql`
  se movio a supabase/migrations despues de aplicar, usando la version que
  registro Supabase; no queda una segunda copia pendiente de aplicacion.

## Aplicacion y verificacion (2026-10-27)

1. Se confirmo con get_project el destino InGePlus-Dev, ref `aalmeaqhhlhzwwzsbbxz`.
2. Antes de aplicar se guardo pg_get_functiondef, sin cambios, en
   `docs/sql_proposals/BACKUP_20261027T143259Z_delete_my_rendition_draft_v01.sql`.
   Captura: 14:32:59.122057 UTC / 09:32:59.122057 Lima.
   MD5 de la definicion original: `94e7ece39480a6d6da034a55cdac2294`.
   Se comprobo que el archivo local contiene exactamente esa definicion.
3. apply_migration devolvio success=true para
   `rendition_draft_delete_preserve_project_bindings`, solo en el ref autorizado.
   El historial remoto registro la version `20261027143355` (hora de version:
   14:33:55 UTC / 09:33:55 Lima). Se aplico el SQL aprobado, sin invocar la funcion.
4. Verificacion posterior a las 14:34:03.555313 UTC / 09:34:03.555313 Lima:

| Comprobacion | Resultado |
| --- | --- |
| Funcion y sobrecargas | Una sola: public.delete_my_rendition_draft_v01(uuid,bigint) |
| Firma y nombres | p_rendition_id uuid, p_expected_row_version bigint; sin cambios |
| Retorno | TABLE(rendition_id uuid, row_version bigint, archived_at timestamptz, result_code text); sin cambios |
| SECURITY DEFINER | true |
| search_path | vacio; proconfig = `search_path=""` |
| EXECUTE authenticated | true |
| EXECUTE anon | false |
| EXECUTE PUBLIC | false |
| ACL | `{postgres=X/postgres,authenticated=X/postgres}`; postgres es propietario |
| Cuerpo desplegado | Coincide exactamente con el cuerpo del SQL aprobado |
| MD5 pg_get_functiondef nuevo | `35cfee076dd1bf3fc9ed4493e4c85a17` |
| Historial remoto | Version `20261027143355`, nombre correcto |

Tambien se consulto el asesor de seguridad. Para esta funcion registra el aviso
esperado [authenticated_security_definer_function_executable](https://supabase.com/docs/guides/database/database-linter?lint=0029_authenticated_security_definer_function_executable):
authenticated puede ejecutar el RPC SECURITY DEFINER. Es el contrato existente
y expresamente solicitado; se conservan las comprobaciones de identidad,
propietario, perfil activo, estado y CAS dentro de la funcion, sin ampliar ACL.
No se modificaron hallazgos ajenos a esta tarea. La verificacion funcional queda
pendiente: no se ejecuto ningun borrado ni se usaron datos reales como fixtures.

## Como revertir (NO ejecutado)

Con autorizacion para revertir, aplicar el contenido completo del respaldo
`docs/sql_proposals/BACKUP_20261027T143259Z_delete_my_rendition_draft_v01.sql`
mediante apply_migration con un nombre NUEVO, por ejemplo
`revert_rendition_draft_delete_preserve_project_bindings`, SOLO en
`aalmeaqhhlhzwwzsbbxz`. El respaldo restaura CREATE OR REPLACE FUNCTION, los
permisos anteriores y NOTIFY pgrst; no contiene llamadas de borrado.

Verificar despues la firma, SECURITY DEFINER, search_path vacio, ACL anterior
y MD5 de pg_get_functiondef `94e7ece39480a6d6da034a55cdac2294`. Conservar ambas
entradas del historial y agregar el SQL de reversion con su nueva version en
supabase/migrations; no editar ni borrar la migracion ya aplicada para revertir.

La reversion restaura el codigo anterior y por tanto tambien su defecto; no
recupera datos ni deshace borrados que un usuario haya confirmado entretanto.

Riesgo/limite: preservar asociaciones activas de una raiz archivada exige que
los consumidores filtren por el estado de la raiz. La lista y la legibilidad
efectiva desplegadas ya exigen `r.archived_at IS NULL`. No se cambio el ciclo
documental ni se borraron nodos, archivos o vinculos. Los guardas de proyectos
bloqueados/archivados permanecen en vigor.

## Validacion y prueba pendiente

- `git diff --check`: correcto.
- `for %f in (tests\renditions\*.cjs) do node %f`: cinco archivos, 38
  comprobaciones, cero fallos.
- No se modifico QML; no corresponde qmllint. Sin build ni prueba en telefono.
- SQL aplicado con aprobacion; DDL, cuerpo y permisos verificados por catalogos.
  No se ejecutaron pruebas funcionales que modifiquen rendiciones.

Despues de compilar Android con los cambios del cliente:

1. Desde la lista, sin abrirla, eliminar `prueba 5`. En logcat verificar
   `INGE_RENDITIONS_DELETE`, p_rendition_id igual al UUID arriba y version vigente.
2. Confirmar respuesta DELETED y luego sincronizar, reiniciar y actualizar:
   la rendicion debe seguir ausente; las demas deben conservarse.
3. Probar un borrador sintetico con gastos/sustentos, cancelacion, repeticion
   idempotente y conflicto de version; verificar restricciones con otra cuenta
   y con estados presentados, usando solo fixtures de prueba.

La correccion del servidor ya esta aplicada; queda pendiente confirmar el flujo
completo en Android con instalacion, logcat y sincronizacion reales.

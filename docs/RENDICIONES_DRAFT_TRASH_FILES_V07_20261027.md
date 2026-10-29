# Papelera de borradores: Files v07 y Android

## Despliegue

Solo InGePlus-Dev (`aalmeaqhhlhzwwzsbbxz`). Migracion aplicada mediante
apply_migration: `20261027145502_rendition_draft_trash_files_v07.sql`, version
remota `20261027145502`, 2026-10-27 14:55:02 UTC / 09:55:02 Lima.
No se accedio a `zzoaqymmejdpfrolecps`.

## Diseno y contrato

`public.trash_my_rendition_draft_v01(p_rendition_id uuid,
p_expected_row_version bigint,p_request_id uuid)` devuelve rendition_id,
row_version, node_id, node_version, lifecycle y result_code.

Exige perfil activo, propietario, BORRADOR sin version actual ni historial,
raiz no archivada/bloqueada, nodo .rend ACTIVE y CAS vigente. Deduplica por
actor/request_id en ledger privado con RLS y sin grants de cliente; rechaza
reutilizar el request_id con otro payload. Sigue el orden de locks de Files,
incrementa row_version de la rendicion y ejecuta preview/mutate_files_lifecycle_v07
en la misma transaccion. Registra RENDITION_DRAFT_TRASHED una sola vez.

El lifecycle del nodo .rend es la unica fuente de Papelera. No se marca
renditions.archived_at ni se archivan gastos/sustentos/asociaciones: asi se
preservan los datos y el estado independiente de gastos ya eliminados.
TRASHED impide que la rendicion aparezca en list_renditions_effective_v06 y
desactiva su capacidad de escritura. Files preview/recover v07 vuelve el nodo
a ACTIVE y con ello restablece la disponibilidad de la rendicion y sus gastos.
No se reemplazo ninguna funcion de Files ni del borrado logico anterior.

Un replay del request de trash despues de recuperar devuelve el receipt original
sin volver a enviar el nodo a Papelera. El pull posterior reconcilia el estado
actual. El usuario puede hacer una nueva accion con un nuevo request_id.

## Puente C++ (sin cambios QML)

Operacion exacta: `trashDraft`, argumentos `{ localId }`.

Ejemplo para el menu que agregara el usuario:

```js
app.call("trashDraft", { localId: String(row.localId) },
         "trashDraft:" + row.localId, callback)
```

- renditionflutterbridge.cpp: comando hacia la cola existente; responde por
  el mismo camino de sync/error tras confirmacion y pull. Al recuperar desde
  Files, actualiza la lista de rendiciones.
- renditionrepository.h/.cpp: trashDraft(id,version,requestId) y draftTrashed.
- renditionlocalstore.h/.cpp: intencion durable rendition_trash, sin eliminar
  contenido local; exige sincronizar antes y conserva el request_id al reintentar.
  Se mantiene visible hasta recibir un receipt valido. Solo entonces trashed=true.
  Una lista anterior no la resucita; una lista vigente despues de recovery
  elimina el marcador. Los rechazos definitivos liberan la intencion pendiente,
  conservan el error en el outbox y lo propagan por syncStopped al solicitante.
- renditionsynccontroller.cpp: envio, ack, reintento y rechazo en el motor existente.
- renditioncontract.h: impide ediciones ordinarias mientras el trash esta
  pendiente o confirmado; no cambia permisos de Login, Perfil o Home.
- tests/renditions/working_queue.cpp y fake_repository.cpp: regresion nativa
  para ack, transporte, replay, reinicio, lista vieja, recovery y rechazo definitivo.
  Agregada en fuentes; NO compilada/ejecutada por la restriccion de esta entrega.

Los borradores aun locales y los que tienen gastos/cambios sin sincronizar
requieren sincronizar antes de mandarlos a la Papelera. No se descarta nada.
El marcado local es aditivo y conserva los JSON existentes, sin migracion
destructiva de cache. Al cambiar de cuenta se mantiene el aislamiento existente.

## Verificacion

- Firma desplegada: `(uuid,bigint,uuid)`; SECURITY DEFINER=true;
  search_path vacio; authenticated EXECUTE=true; anon/PUBLIC=false.
  ACL: `{postgres=X/postgres,authenticated=X/postgres}`.
- Verificacion de catalogos: 2026-10-27 15:03:16 UTC / 10:03:16 Lima.
- Verificacion adicional a 15:07:55 UTC / 10:07:55 Lima: cuerpo desplegado
  identico al aprobado, mutate_files_recovery_v07 sin cambios respecto de su
  definicion previa, ledger RLS=true y SELECT para authenticated/anon=false.
- `tests/renditions/trash_recover_v07.sql`: ejecutado en Dev con carpeta,
  borrador y gasto NUEVOS, en transaccion con ROLLBACK. Paso propietario, CAS,
  trash, replay, conflicto de payload, lista global, lista movil/can_restore,
  preview, recover, reaparicion y preservacion del gasto. Un replay despues de
  recovery no volvio a enviar el nodo a Papelera.
- Ultimos IDs sinteticos: rendicion `5c25f4f1-1baa-44a4-96cf-c1290535e25b`,
  nodo `aef52e20-fd07-4c05-bca2-d31f07e82711`, carpeta
  `f4efc34b-9ead-4e95-84c7-30bab12d41c4`, gasto
  `3c88d09d-7f48-4009-a96d-302d6813ce8f`. Todas sus filas se revirtieron;
  tambien los receipts/auditoria creados por la prueba. Las secuencias PostgreSQL
  pueden conservar saltos de numeracion tras rollback.
- Consulta posterior de limpieza: cero rendiciones, cero nodos/carpeta, cero
  gastos y cero receipts para esos UUID. No se borro ningun dato preexistente.
- Cinco `.cjs`, 38 comprobaciones: correctas. git diff --check: correcto.
- Revision independiente de solo lectura: sin defectos bloqueantes identificados;
  no sustituye compilacion/enlace ni pruebas Android.
- No QML, build, instalacion, commit ni push en esta tarea. La prueba Android
  queda pendiente hasta que el usuario agregue su menu y compile.

El asesor de seguridad registra dos avisos esperados por el contrato aprobado:
[ledger RLS sin politicas](https://supabase.com/docs/guides/database/database-linter?lint=0008_rls_enabled_no_policy)
(tabla privada, sin acceso de cliente) y
[RPC SECURITY DEFINER ejecutable por authenticated](https://supabase.com/docs/guides/database/database-linter?lint=0029_authenticated_security_definer_function_executable)
(guardas de propietario/estado/CAS dentro de la funcion). No se ampliaron grants
ni se cambiaron hallazgos de otras partes del proyecto.

## Reversion

No se sustituyo ninguna funcion existente, por lo que no hay una definicion
anterior que restaurar. El respaldo del estado previo y SQL de reversion estan
en `docs/sql_proposals/BACKUP_20261027_rendition_draft_trash_prestate_and_rollback.sql`.
Aplicarlo con autorizacion como una NUEVA migracion solo en Dev. No borrar ni
editar el historial ya aplicado. Mantener ledger y catalogo para conservar
idempotencia/auditoria; revocar/eliminar solo el nuevo RPC. La recuperacion
Files de nodos que ya esten en Papelera sigue funcionando.

Para retirar el cliente, revertir solo los hunks de trashDraft y rendition_trash
de los archivos indicados, sin revertir cambios previos del borrado ni trabajo
ajeno en este checkout. No borrar archivos locales de cuentas.

## Prueba en telefono

Tras compilar y agregar el menu: enviar un borrador propio sincronizado con un
gasto a Papelera usando trashDraft. Debe salir de Rendiciones al confirmar el
servidor y aparecer en la Papelera global. Recuperarlo en su ubicacion de origen
con Files: debe reaparecer con el mismo gasto tras actualizar/reiniciar. Comprobar
cancelacion, falta de red y que otra cuenta no pueda mandar ese borrador a Papelera.

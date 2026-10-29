# Archivar una rendicion propia: Files v07

## Reglas aplicadas

Propietario con perfil ACTIVO y ACL documental WRITE, rendicion sincronizada,
nodo .rend ACTIVE y CAS por row_version. Se permite BORRADOR, OBSERVADO y
APROBADO; tambien REVISADO, ARCHIVADO y EXPORTADO para filas historicas que ya
existan. El trigger de estados v09 solo admite actualmente crear/transicionar
a BORRADOR, EN_REVISION, OBSERVADO y APROBADO; este RPC no cambia status.

EN_REVISION se rechaza siempre. Tambien se rechaza cualquier solicitud
private.rendition_edit_requests_v03 PENDING, aunque el estado sea otro, para
no dejar una revision pendiente fuera de la lista de trabajo. Se rechazan
bloqueos, borrado logico previo, nodo no activo, ACL insuficiente y CAS vencido.
La autoridad de archivar en este RPC es solo del propietario, no del editor
compartido ni de otro administrador. Las facultades administrativas Files ya
existentes no se amplian ni se eliminan.

## Migraciones aplicadas

Solo InGePlus-Dev (`aalmeaqhhlhzwwzsbbxz`); no se accedio a `zzoaqymmejdpfrolecps`.

- `20261027152819_rendition_owner_archive_files_v07.sql`: aplicada con
  apply_migration el 2026-10-27, hora de version 15:28:19 UTC / 10:28:19 Lima.
  Nuevo archive_my_rendition_v01(uuid,bigint,uuid), ledger privado de request_id,
  evento RENDITION_ARCHIVED y excepciones Files para un .rend del propietario.
- `20261027153128_rendition_archive_active_list_filter.sql`: aplicada con
  apply_migration, hora de version 15:31:28 UTC / 10:31:28 Lima. Filtra la lista
  activa por lifecycle ACTIVE. La prueba encontro que la legibilidad de archivo
  por si sola no distinguia entre consulta archivada y lista activa.

- `20261027154741_files_archive_browse_container_kind.sql`: aplicada con
  apply_migration, hora de version 15:47:41 UTC / 10:47:41 Lima. can_browse=true
  solo para SPACE/FOLDER. Los SMART_DOCUMENT (.rend) usan filesArchivedContext
  al pulsarlos; no intentan navegar como una carpeta. QML no modificado.

Los tres archivos locales se alinearon con las versiones del historial remoto.
No se aplico ninguna llamada de archivo/recuperacion a datos preexistentes.

## Arquitectura y permisos

El estado de Archivero es document_nodes.lifecycle=ARCHIVED, no
renditions.archived_at del borrado logico anterior. El RPC incrementa la version
de la rendicion y ejecuta preview/mutate_files_lifecycle_v07 de forma atomica,
con los mismos locks que Files. Conserva gastos, sustentos, asociaciones,
current_version_id, snapshots inmutables y status. Un replay tras reactivar
devuelve el recibo anterior sin volver a archivar.

Files v07 reservaba todo el archivo a administradores. La extension es por
nodo .rend propio e independientemente archivado, con las ACL documentales
originales. No se cambia files_archive_authority_v07 ni se concede autoridad
sobre carpetas, espacios, calicatas o documentos ajenos.

La excepcion al trigger de ARCHIVE exige, ademas de propietario/estado valido,
el guard transaccional privado que ya instala Files v07. No hay flags de sesion
controlables por Android. Los guardas ARCHIVE_READ_ONLY permanecen en vigor.
list_files_archive_children_v07 y filesArchivedContext permiten consultar ese
nodo; filesRecover existente lo reactiva. El cuerpo de mutate_files_recovery_v07
no se reemplazo. Recuperar devuelve el mismo estado (por ejemplo APROBADO), sin
convertirlo a BORRADOR ni otorgar permiso para editar una version presentada.

## Cliente C++

Operacion exacta del puente: `archiveRendition`, `{ localId }`. QML no modificado.

- renditionflutterbridge.cpp: comparte el camino de intencion/sync/error de
  trashDraft y espera confirmacion remota. Tras recovery actualiza la lista.
- renditionrepository.h/.cpp: archiveRendition(id,version,requestId), RPC
  archive_my_rendition_v01 y senal renditionArchived.
- renditionlocalstore.h/.cpp: request/ack/rechazo de ambos lifecycle reutilizan
  funciones comunes de la cola existente. Marker fileArchived separado del
  borrado legacy archived y de trashed; no se elimina contenido local.
- renditionsynccontroller.cpp: rendition_archive durable, request_id/CAS
  preservados en reconexion y reinicio; rechazo definitivo libera la intencion
  y notifica el error. Oculta de la lista solo tras validar el recibo.
- renditioncontract.h: estados de archivo permitidos y bloqueo de edicion durante
  archiveRequested o fileArchived, sin sustituir la autoridad del servidor.

Se exige sincronizar cambios/gastos pendientes antes de continuar. Solo una
lista ACTIVA con version vigente prueba reactivacion: un detalle legible del
Archivero no puede quitar el marcador local ni una lista anterior resucitarlo.
La migracion de cache es aditiva y no elimina datos ni archivos de cuentas.

## Verificacion ejecutada

- Catalogos a 2026-10-27 15:36:31 UTC / 10:36:31 Lima: firma `(uuid,bigint,uuid)`,
  SECURITY DEFINER=true, search_path vacio, authenticated EXECUTE=true,
  anon=false, PUBLIC=false; ACL `{postgres=X/postgres,authenticated=X/postgres}`.
- `tests/renditions/archive_recover_v07.sql`: PASS en Dev, con rollback.
  Se creo carpeta, dos rendiciones y gasto nuevos. Para probar al propietario
  sin rol administrativo se crearon una membresia temporal y un grant solo
  sobre la carpeta de prueba; no se alteraron perfiles, roles ni grants previos.
  Una rendicion de fixture cambio de propietario; ninguna rendicion real cambio.
- Verificado con BORRADOR y APROBADO, este ultimo con un snapshot inmutable real:
  propietario no administrador, aislamiento de otro archivo, sin autoridad para
  archivar carpetas, rechazo EN_REVISION, CAS, replay y conflicto de payload,
  desaparicion activa, aparicion en Archivero/can_reactivate, contexto de archivo,
  lectura sin edicion (UPDATE del gasto rechazado), recovery, gasto intacto,
  historial inmutable intacto, status preservado y replay posterior sin rearchivar.
- IDs de la prueba: rendicion `d38e5651-e3f4-4788-89cd-656dcb297083`, otra
  `1f51d4df-ffb8-4b9f-993d-298a8d1424f2`, nodo
  `22f2bf82-6414-4114-92ed-cb701e61840d`, otro nodo
  `dae61d31-e7d8-41c4-abeb-efcf344d45b0`, carpeta
  `3fa2f18b-3d59-4951-8e39-2ac2cf8d3559`, gasto
  `a242edc2-48a6-43dd-b5c1-eca34f2b023b`, membresia
  `4af7d00d-284d-4c84-a6c0-cabc3dc0778b`, grant
  `83488277-df4e-4be6-8ae6-5614e8899139`. Todos revertidos por ROLLBACK,
  incluidos receipts y auditoria. Pueden quedar saltos de secuencias PostgreSQL.
- Cinco .cjs, 38 comprobaciones: correctas. git diff --check: correcto.
- Tras corregir can_browse se repitio la prueba completa: PASS, incluyendo que
  el .rend no sea navegable como carpeta y si sea reactivable. Ultimos UUID:
  rendicion `57c1ae79-208c-4108-8cf3-adf7ef865c6b`, otra
  `ac247f5f-4540-4831-a0be-a6f11b6ffcc9`, nodo
  `fd42d010-4174-4b0e-96cb-5d798788b4d2`, otro nodo
  `4c9ca06b-aa41-4484-af23-6f3b7a16756f`, carpeta
  `ced306e4-75ae-4ea6-b86d-4a143b4887f9`, gasto
  `a3656291-c13e-4a4f-80d0-51a56b7faf25`, membresia
  `83473837-f903-4bc8-b7dc-c63a1fdaa56c` y grant
  `b5ca0d84-b9e8-4eb8-afa8-4ac5c9e09df7`. Todos revertidos por ROLLBACK.
- Regresion de trash_recover_v07.sql despues de extender Files: PASS.
- Cuerpos de las siete funciones reemplazadas cotejados con las migraciones,
  ACL previas conservadas y files_archive_authority_v07 global sin cambios.
  Ledger con RLS y sin acceso de tabla para authenticated/anon.
- Revision independiente de solo lectura: sin defectos importantes confirmados.
  Se comprobo la ruta actual de consulta Files (filesArchivedContext), sin
  compilacion ni prueba Android.
- Regresion nativa agregada en working_queue.cpp/fake_repository.cpp: APROBADO
  sin permiso de contenido, request persistente, respuesta perdida, ack,
  preservacion de version, detalle archivado que no reactiva, lista vieja y
  recovery. No compilada/ejecutada por el alcance solicitado.
- No QML, build, instalacion, commit ni push. Android queda pendiente.

El asesor registra los avisos esperados de
[RLS sin politicas](https://supabase.com/docs/guides/database/database-linter?lint=0008_rls_enabled_no_policy)
en el ledger privado sin grants y
[RPC SECURITY DEFINER para authenticated](https://supabase.com/docs/guides/database/database-linter?lint=0029_authenticated_security_definer_function_executable).
El segundo es el contrato solicitado, con guardas de propietario/estado/ACL/CAS.

## Respaldo y reversion

`docs/sql_proposals/BACKUP_20261027_owner_archive_files_v07.sql` contiene
pg_get_functiondef exacto y ACL de las SIETE funciones sustituidas; las seis
primeras se respaldaron antes de la migracion principal y la lista activa antes
del ajuste posterior. Incluye los MD5 originales y una reversion completa.
El estado intermedio de list_files_archive_children_v07 inmediatamente anterior
a la correccion can_browse tambien se guardo en
`docs/sql_proposals/BACKUP_20261027_archive_list_before_browse_flag.sql`.

Con autorizacion para revertir, aplicar el contenido del respaldo como NUEVA
migracion solo en Dev. Restaura las siete funciones originales y sus permisos,
retira el RPC/helper nuevos y notifica PostgREST. Conserva ledger y catalogo
de actividad para no borrar auditoria ni idempotencia. No editar/borrar las
migraciones ya aplicadas del historial. Verificar luego MD5 y ACL del respaldo.

Revertir devuelve el acceso de Archivero al modelo administrativo anterior:
los datos seguiran intactos, pero un propietario no administrador necesitara
ayuda administrativa para reactivar archivos que ya esten en el Archivero.
No se recuperan ni borran datos de negocio mediante esta reversion de codigo.

Para retirar el cliente, revertir solo los hunks de archiveRendition y sus
marcadores en los archivos indicados, conservando el trabajo previo y la cola
trashDraft. No limpiar caches ni datos locales.

## Telefono

Compilar con estos fuentes y usar el menu Archivar ya agregado por el usuario.
Archivar una rendicion propia sincronizada; debe desaparecer solo al confirmar,
aparecer en Archivero para consulta sin edicion y reactivarse con Files. Despues
de sincronizar/reiniciar debe volver con el mismo estado, gastos y versiones.
Comprobar EN_REVISION, otra cuenta y una interrupcion de red.

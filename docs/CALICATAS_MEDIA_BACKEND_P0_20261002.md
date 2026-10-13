# Calicatas Media: reparación del backend, 2 de octubre de 2026

BACKEND_CALICATAS_MEDIA_STATUS=SQL_VERIFIED_PENDING_ANDROID_UPLOAD

Proyecto: InGePlus-Dev (`aalmeaqhhlhzwwzsbbxz`). Ámbito: migraciones SQL,
pruebas SQL y documentación. No se modificó el cliente, QML, C++, Auth,
Login, Perfil, Home ni el motor de animaciones. No se compiló ni generó APK.

## Causa raíz y evidencia

El log adjunto y las capturas muestran HTTP 400 en UPLOAD_ORIGINAL con
`permission denied for function rendition_attachment_storage_uploadable_v01`.
Se reprodujo el mismo error directamente como `authenticated`, usando
`request.jwt.claims` y `storage.operation=storage.object.upload`, dentro de
una transacción revertida.

`rendition_attachment_exact_upload_v01`, política permisiva de
`storage.objects`, invocaba directamente esa función privada sin discriminar
el bucket. Su ACL era únicamente `postgres=X/postgres`. Una política que
arroja un error no equivale a una política que devuelve false: interrumpía
también la subida al bucket `calicata-media` aunque su propia reserva fuera
válida. No faltaban las RPC de Calicatas ni era necesario exponer Rendiciones.

La auditoría detectó también:

- La política antigua del original permitía PHOTO cuando el media seguía
  UPLOADING, incluso si su versión había pasado a FAILED.
- La comparación `<>` de metadatos obligatorios en una reserva repetida
  permitía NULL por la lógica UNKNOWN de SQL. Se reprodujo con una reserva
  FAILED real y se revirtió la operación.
- El CHECK de la derivada permitía tamaño/dimensiones NULL. Se reprodujo
  una reserva con derivada y tamaño NULL; la transacción fue revertida.

## Migraciones ejecutadas

| Versión remota y archivo local | Cambio |
| --- | --- |
| `20261002150502_calicata_media_storage_policy_isolation.sql` | Aísla políticas de Rendiciones por bucket, limita la política antigua de inserción a LOGO y corrige comparaciones de identidad de reserve con IS DISTINCT FROM. |
| `20261002150755_calicata_media_derivative_reservation_validation.sql` | Exige que la derivada esté ausente o incluya nombre, MIME, tamaño, ancho y alto; SHA256 sigue siendo opcional. |

Los nombres locales se alinearon con las versiones asignadas por
`supabase_apply_migration`. Ambos resultados fueron `success=true`.
No hubo borrado de filas, versiones READY, objetos reales ni datos locales.

## Permisos y políticas finales

Las diez RPC de media ya existentes mantienen sus nombres, firmas, owner
`postgres`, SECURITY DEFINER y `search_path=''`. Su EXECUTE sigue limitado
a postgres, authenticated y service_role del servidor. No se otorgaron
permisos a anon o PUBLIC. Las tablas `calicata_media` y
`calicata_media_versions` mantienen RLS y únicamente SELECT para authenticated;
las escrituras del modelo pasan por las RPC y sus controles de autorización.

La función privada `rendition_attachment_storage_uploadable_v01(text,text)`
mantiene exactamente su ACL exclusiva de postgres. No se hizo pública ni
se concedió EXECUTE a authenticated, anon o PUBLIC.

El único nuevo helper, no expuesto en public, es
`private.storage_rendition_attachment_insert_allowed_v01(text,text)`:
SECURITY DEFINER, owner postgres, search_path vacío, EXECUTE únicamente
postgres/authenticated. Antes de consultar la autorización existente de
Rendiciones exige auth.uid(), bucket `project-files`, path no nulo y operación
upload. Para `calicata-media` devuelve false sin invocar el helper restringido.
No genera rutas ni permite escritura genérica.

Cambios en políticas compartidas necesarios para reparar Calicatas:

- `rendition_attachment_exact_upload_v01`: CASE por bucket y entrada privada
  específica para project-files. Conserva las validaciones originales de
  actor, reserva, vencimiento, perfil activo y edición de Rendiciones.
- `rendition_attachment_exact_read_v01`: CASE por bucket antes del helper
  de lectura existente.
- `calicata_media_storage_insert_policy`: permite solamente originales LOGO
  reservados, de su creador, en UPLOADING y con Calicata autorizada.

Políticas de versiones de Calicatas conservadas:

- `calicata_media_version_storage_insert_policy`: solo original/derivada
  exactos de una versión UPLOADING, creada por auth.uid(), para una Calicata
  que el usuario puede escribir.
- `calicata_media_version_storage_read_policy`: rutas de versiones
  UPLOADING/READY, con autorización de lectura de la Calicata, limitadas a
  las operaciones existentes de upload, info, lectura y firma.
- `calicata_media_version_storage_delete_policy`: versiones UPLOADING/FAILED,
  creador y autorización de escritura. READY no tiene permiso de borrado.
- `calicata_media_storage_read_policy`: lectura de originales reservados o
  publicados, con autorización del proyecto/Calicata.

No se añadió una política UPDATE ni upsert. El bucket permanece privado,
con límite 50 MiB y MIME image/jpeg, image/png, image/webp; los límites más
estrictos de PHOTO/LOGO en las tablas siguen vigentes.

## Contrato que debe usar el cliente

PHOTO:

1. `create_my_calicata_media_v01`: conservar media_id estable y metadatos del
   original; valida usuario, Calicata y autorización de escritura.
2. `reserve_my_calicata_media_version_v01`: conservar version_id estable y
   enviar los 15 argumentos existentes. Usar exclusivamente los campos
   original_bucket/original_storage_path y derivative_bucket/derivative_storage_path
   devueltos. El servidor construye las rutas a partir de proyecto, Calicata,
   media, versión y nombre validado.
3. Subir original y, si fue reservada, derivada por Storage con JWT del
   usuario, clave pública/anon y `x-upsert:false`. No usar service_role.
4. `finalize_my_calicata_media_version_v01(p_version_id)`: verifica objetos,
   propietario, tamaño y MIME; pasa la versión a READY y mueve active_version_id.
   Una derivada ausente en la reserva es opcional; una derivada reservada
   debe existir y coincidir. Finalize repetido no incrementa row_version.
5. `fail_my_calicata_media_version_v01(p_version_id)`: marca FAILED de manera
   idempotente, sin cambiar la versión activa anterior. Rechaza READY.
6. Reintentar con **el mismo version_id y exactamente los mismos metadatos**:
   reserve recupera FAILED a UPLOADING y conserva número/rutas. Si los bytes
   cambiaron se necesita una versión nueva. Una colisión del original no
   autoriza a sobrescribirlo: finalize decide por propietario/tamaño/MIME.

LOGO conserva create → reserve_my_calicata_media_original_v01 → Storage →
finalize_my_calicata_media_original_v01. La ruta propuesta al reserve original
debe coincidir exactamente con la ruta validada por el servidor.

RPC complementarias conservadas y auditadas:
`set_my_calicata_media_active_version_v01`,
`discard_my_calicata_media_version_v01`, `discard_my_calicata_media_v01` y
`empty_my_calicata_media_slot_v01`. La selección activa exige versión propia
READY no descartada y usa p_expected_row_version para cambios reales.

El código del cliente observado durante la investigación cambiaba version_id
tras un fallo no transitorio. Ese comportamiento puede acumular FAILED;
el backend ya permite reutilizar la reserva. Se documenta el contrato para
el agente del cliente; no se modificó ese código.

## Consultas y resultados de validación

`tests/calicatas/media-backend-audit.sql` contiene las consultas de catálogo,
definiciones, privilegios, políticas, bucket, RLS, constraints, rutas, estados,
objetos y migraciones realizadas durante la auditoría.

| Comprobación | Resultado |
| --- | --- |
| Reproducción previa del rechazo | Mismo error 42501 de Rendiciones que explica el HTTP 400. |
| RPC existentes, owner, search_path y ACL | Diez RPC de media presentes; firmas y privilegios conservados. |
| Función privada restringida | EXECUTE authenticated=false, anon=false; ACL solo postgres. |
| Bucket y rutas | Privado; rutas originales/derivadas generadas por reserve. |
| RLS del modelo | Activado en ambas tablas; authenticated solo SELECT. |
| Versiones activas inconsistentes | 0 antes y después de las migraciones. |
| CREATE repetido | PASS, una sola identidad. |
| RESERVE, original sin derivada, FINALIZE repetido | PASS; activación solo al finalizar y row_version estable al repetir. |
| Upload SQL al path reservado | PASS después de la reparación; era el fallo inicial. |
| Path arbitrario y otro bucket | Rechazados. |
| Otro colaborador usando reserva ajena | Upload, fail y finalize rechazados. |
| Usuario sin pertenencia/autorización | Lectura y create rechazados. |
| FAILED y original antiguo | Upload rechazado hasta reserve del mismo UUID. |
| FAIL repetido y conservación de READY activa | PASS. |
| RETRY | PASS, misma versión, número y ruta; no crea filas adicionales. |
| NULL en identidad de retry | Rechazado. |
| Derivada incompleta | Rechazada. |
| Original/derivada faltantes, tamaño incorrecto | Finalize rechazado. |
| Original existente | Colisión, sin sobrescritura; retry puede continuar con derivada. |
| READY | Fail rechazado; UPDATE de bytes denegado. |
| LOGO completo | PASS. |
| Activar versión perteneciente a otro media | Rechazado. |
| Ausencia de auth.uid() | Finalize rechazado. |
| Subida HTTP desde Android | Pendiente de ejecución/confirmación del usuario. |

`tests/calicatas/media-backend-contract.sql` ejecuta el contrato real como
authenticated con identidades controladas y fixtures nuevos aleatorios en
una transacción. Utiliza **metadata sintética** de storage.objects para
verificar RLS/finalize; no crea bytes en Storage y no sustituye una subida
HTTP. Todas las escrituras y los eventos de auditoría se revierten mediante
ROLLBACK. No se reutilizan ni modifican fotografías reales para estas pruebas.

Una primera versión del test intentaba borrar metadata sintética y fue
rechazada por la protección actual de Storage. Se eliminó ese paso;
no se desactivó la protección. El test final no hace DELETE sobre Storage.

La revisión independiente de los cinco archivos y del catálogo remoto no
encontró defectos adicionales en las migraciones. Señaló que las aserciones
de active_version_id/row_version debían usar IS DISTINCT FROM para detectar
también NULL. Se corrigieron y volvió a pasar el contrato completo. El
revisor excluyó expresamente HTTP, bytes reales y pruebas del cliente de
su veredicto. La última observación remota sigue mostrando las reservas
fallidas del log sin objetos nuevos ni finalización posterior a la reparación;
se conservan para el reintento del cliente, sin alterar sus datos reales.

## Comandos y herramientas

- `git status --short`, `git ls-files`, `rg` en fuentes activas.
- Supabase CLI 2.117.0: `migration new --help` y
  `migration new calicata_media_storage_policy_isolation` /
  `migration new calicata_media_derivative_reservation_validation`.
- Plugin Supabase: list_projects, execute_sql, apply_migration, search_docs
  y get_advisors(type=security).
- ADB: `devices`, `shell pidof com.ingema.ingeplus` y lectura filtrada de
  `logcat -d -v time -t 2500`; sin limpiar logs, reinstalar ni iniciar la app.
- `git diff --check` para los archivos de esta fase.

Documentación oficial consultada:
[Storage Access Control](https://supabase.com/docs/guides/storage/security/access-control)
y [Storage Helper Functions](https://supabase.com/docs/guides/storage/schema/helper-functions).
Se consultó también el changelog vigente. El contrato conserva uploads
inmutables; upsert requeriría SELECT/INSERT/UPDATE y no se habilitó.

## Riesgos y límites de la evidencia

El advisor señala las RPC públicas SECURITY DEFINER ejecutables por
authenticated: es intencional y se validó la autorización interna.
[Criterio del advisor](https://supabase.com/docs/guides/database/database-linter?lint=0029_authenticated_security_definer_function_executable).
No hay acceso anon a las RPC de media ni al nuevo helper privado.
Los avisos generales de otros módulos/Auth quedaron fuera de este alcance;
no se declara una auditoría de seguridad completa del proyecto.

La comprobación de finalize existente verifica propietario, tamaño y MIME
del objeto; no recalcula SHA256 de los bytes almacenados. No se sustituyó
esa arquitectura ni se amplió a un nuevo servicio de procesamiento.

La aplicación de migraciones y los tests SQL prueban el backend y su RLS.
Hasta observar upload/finalize reales y el reintento desde Android, el estado
es SQL_VERIFIED_PENDING_ANDROID_UPLOAD, no «100% solucionado».

Commit de fase: registrar el hash al entregar; incluye solamente los dos
archivos SQL de migración, los dos tests SQL y este informe.

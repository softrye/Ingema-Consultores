# Calicatas: bloqueo de sincronizacion RPC (2026-09-29)

## Fase 1: diagnostico directo

Backend autorizado: InGePlus-Dev (`aalmeaqhhlhzwwzsbbxz`). Consultas mediante
el complemento Supabase de Codex, sin compilacion ni ADB.

- `calicatacloudservice.cpp:3367`, `ensureProjectGabinete`, llama por POST a
  `ensure_calicata_field_folder_v01` con `{p_project_id: UUID normalizado}`.
  Espera una fila con `space_id` y `folder_id` UUID; SQL declara tambien
  `result_code text`. El cliente no necesita otra firma.
- `finalizeSmartDocument` llama primero a esta RPC, luego a
  `ensure_calicata_smart_document_v01(p_calicata_id)`. Tambien la usa el destino
  JSON por defecto. El fallo propaga `syncFailed` y mantiene LOCAL/PENDING;
  no elimina el borrador. La UI confirma su conservacion.
- Catalogo vivo: `to_regprocedure('public.ensure_calicata_field_folder_v01(uuid)')`
  devuelve NULL. Busqueda en todos los esquemas: ninguna version de esta RPC.
  Por tanto no tiene firma, owner ni grants remotos que inspeccionar.
- Existe el archivo fuente pendiente y sin seguimiento Git
  `supabase/migrations/20260929120000_calicatas_field_folder_06_gabinete.sql`.
  Su nombre/version no figura en `supabase_migrations.schema_migrations`.
- La migracion pendiente tampoco es aplicable sin correccion: su ancla
  `v_is_controlled_binding` tiene cero coincidencias en el trigger vivo.
  El trigger actual conserva la guarda de creacion ADMINISTRATION y rechaza
  cualquier cambio de contexto. Owner postgres, SECURITY DEFINER,
  search_path vacio, ACL solo postgres.
- Hay cinco espacios PROJECT activos: uno tiene FIELD/06_GABINETE, uno tiene
  06_GABINETE de plantilla sin FIELD y tres carecen de carpeta canonica.
  La RPC Smart Document sigue buscando FIELD; no hay RPC sucesora equivalente.

Clasificacion: **A confirmada, C confirmada**. B descartada (no hay otra firma),
D descartada como causa primaria (objeto ausente), E descartada como causa unica
(refrescar cache no crea una funcion inexistente).

Correccion prevista: reparar y aplicar exclusivamente esta migracion pendiente,
manteniendo su RPC y guardas privadas, adaptando el enlace FIELD al trigger vivo.
Eliminar la normalizacion masiva: no renombrar ni mover datos existentes.
Conservar el resto del trigger, permisos y RLS. Verificar invocacion como
authenticated y rechazos de acceso mediante SQL transaccional con rollback.

Comandos de inspeccion: `rg`, `git status --short`, `git diff --cached --stat`,
`git log`; SQL: `pg_proc`, `pg_namespace`, `pg_get_functiondef`, `pg_trigger`,
`pg_attribute`, `pg_db_role_setting`, historial de migraciones y lectura limitada
de espacios/nodos (sin credenciales ni datos de autenticacion).

Hay numerosos cambios previos del usuario. Los commits de esta tarea se limitan
a esta documentacion, la migracion indicada y su prueba SQL.

## Fase 2: correccion aplicada y validada

Se aplicaron mediante `supabase_apply_migration` exclusivamente:

1. `20260929150428_calicatas_field_folder_06_gabinete.sql`: la migracion pendiente,
   corregida para el trigger actual y sin normalizacion masiva. El archivo
   anteriormente llamado `20260929120000_...` se renombro a la version que el
   complemento registro realmente en el historial remoto.
2. `20260929150713_calicatas_field_folder_actor_version.sql`: ajuste incremental
   necesario detectado durante la validacion real. El trigger de invariantes
   incrementa `node_version` antes del trigger de contexto y exige `updated_by`
   igual al actor. La RPC ahora registra ese actor y la guarda permite solamente
   esos metadatos y el enlace FIELD, conservando el resto de la fila.
   El archivo fue generado por `npx --yes supabase migration new
   calicatas_field_folder_actor_version` (CLI 2.118.0) y su version se alineo con
   el historial remoto. No se reescribio la primera migracion ya aplicada.

La excepcion compartida se limita a una carpeta raiz activa 06_GABINETE,
NULL -> FIELD, con guarda privada del mismo actor, nodo y transaccion. La RPC
comprueba perfil ACTIVO, lectura del proyecto y escritura de su espacio.
La creacion usa la ruta privada existente de mutacion; no hay funciones
duplicadas, RLS desactivada, renombrados, movimientos ni borrado de datos.
No se cambiaron roles, claves, Auth, Home, Rendiciones ni InGe Earth. Los REVOKE
solo restringen los objetos nuevos de Calicatas, sin alterar service_role.
No se modifico C++/QML ni la conservacion local del borrador.

Contrato final verificado en `pg_proc`:

```sql
public.ensure_calicata_field_folder_v01(p_project_id uuid)
RETURNS TABLE(space_id uuid, folder_id uuid, result_code text)
```

Owner `postgres`, SECURITY DEFINER, search_path vacio. ACL exacta:
`{postgres=X/postgres,authenticated=X/postgres}`. `anon` y PUBLIC sin EXECUTE.
El trigger conserva owner, ACL y cuerpo previo salvo la excepcion FIELD.

Validacion ejecutada mediante `supabase_execute_sql`, sin compilar:

- Prueba inicial: FAIL esperado por RPC ausente.
- Primer intento tras despliegue: fallo `PROJECT_FOLDER_CONTEXT_IMMUTABLE` por
  incremento automatico de version; transaccion revertida. Motivo de la segunda
  migracion, sin ocultar el error ni alterar las otras invariantes.
- `tests/calicatas/field-folder-rpc.sql`: PASS final. Invoca la RPC con
  `SET LOCAL ROLE authenticated` y claims de identidades reales descubiertas en
  la base (sin tokens ni contrasenas). Cinco proyectos activos: tres CREATED,
  uno BOUND, uno IDEMPOTENT_REPLAY; segunda invocacion idempotente en los cinco.
- Smart Document posterior: probado sobre una calicata existente en cada uno
  de los dos proyectos que contienen calicatas.
- Rechazos comprobados: anon, identidad ausente, identidad sin perfil activo,
  proyecto inexistente, identidades activas sin acceso/escritura al proyecto,
  intento de forjar guarda privada y de quitar FIELD directamente.
- Todas las escrituras de prueba terminan en ROLLBACK. Los 65 nodos conservan
  el digest completo `ab0b8a524c5dd155518932907c307b49`; cero guardas remanentes.
  RLS continua habilitada en calicatas, document_nodes y document_spaces.
- Ambas migraciones notifican `pgrst, 'reload schema'`. Prueba REST real con
  clave publicable y sin sesion: HTTP 401 / SQLSTATE 42501,
  `permission denied for function ensure_calicata_field_folder_v01`.
  Esto confirma resolucion de la RPC en la cache y rechazo anonimo esperado;
  la ejecucion autorizada se valido mediante SQL, no con un JWT del dispositivo.
- Asesor de seguridad revisado: advertencia de SECURITY DEFINER ejecutable por
  authenticated es intencional para esta RPC controlada; sus rechazos se probaron.
  [Criterio del asesor](https://supabase.com/docs/guides/database/database-linter?lint=0029_authenticated_security_definer_function_executable).
  Avisos de otros objetos/configuracion quedan fuera de esta tarea.
- Referencia de [recarga de PostgREST](https://supabase.com/docs/guides/troubleshooting/refresh-postgrest-schema).

Revision de entrega: diff y git status, incluyendo separacion de los cambios
previos del usuario. Commit de diagnostico: `5d3c6e2`; segundo commit para SQL,
regresion y esta evidencia. No se ejecutaron CMake, ninja, Gradle, Flutter build,
APK/AAB, instalacion, ADB ni logcat.

Limite y prueba del usuario: falta la validacion Android real. Reintentar Guardar
en el borrador existente; comprobar sincronizacion y documento en 06_GABINETE,
repetir sin duplicados y comprobar que un fallo de nube conserva el borrador.
Una carpeta FIELD preexistente no canonica seguira fallando explicitamente;
no se modifica automaticamente su nombre, ubicacion ni historial.

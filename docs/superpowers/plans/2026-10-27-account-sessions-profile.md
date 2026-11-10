# Mi cuenta: sesiones, area y perfil

**Especificacion:** solicitud detallada del usuario en este chat, 2026-10-27.
**Objetivo:** completar el backend existente de Mi cuenta sin cambiar login ni
multicuenta. Ejecucion secuencial, solo Dev aalmeaqhhlhzwwzsbbxz, en la rama
codex/fusionbridge-native; sin commit, push, build ni uso del telefono.

**Decision confirmada:** avatares privados, lectura propia con URL firmada.
**Arquitectura:** dos RPC con retorno jsonb (array y objeto respectivamente),
auth.uid y session_id, SECURITY DEFINER con search_path vacio y ACL restringida.
Area con SELECT/RLS existente y setter administrativo controlado/CAS/auditoria.
Un trigger permite sincronizar solo nombre, telefono y referencia de avatar
propio desde Auth. Bucket avatars privado 5 MiB PNG/JPEG; URL firmada solo en
memoria cliente. Datos administrativos nunca proceden de user_metadata.

## Riesgos y comprobaciones
- Cuenta A nunca ve ni revoca sesiones B; no se revoca la sesion actual.
- Sesiones expiradas excluidas; UTC explicito para refreshed_at sin zona.
- UA se reduce a etiquetas conocidas y modelo saneado, sin datos crudos.
- Callbacks tardios no escriben en otra cuenta, incluso al volver A-B-A.
- Metadata maliciosa no cambia area, position, role, status o global_role.
- Firma de avatar requiere JWT propio; web debe firmar la referencia privada.
- Revocacion borra refresh tokens por FK, no invalida JWT emitido inmediatamente.

## Fases
- [x] Inspeccionar fuentes, schema, funciones administrativas, RLS y FK.
- [x] Crear test SQL de contrato y observar fallo previo.
- [x] Implementar migracion versionada, aplicar solo Dev y ejecutar pruebas.
- [x] C++: UA JNI, select area, avatar privado/firma y protecciones multicuenta.
- [x] Revisar diff y advisors; documentar JSON anonimizado, comandos y limites.

## Registro
- RPC ausentes; area ausente; profiles solo SELECT para authenticated.
- Administracion usa private.files_admin_require_v01 y funciones controladas.
- Auth solo tenia trigger INSERT, sin sincronizacion de cambios de metadata.
- Bucket IngePlus usado por C++ no existe. No se toca ningun bucket existente.
- Aplicada 20261027214310_account_sessions_profile_v01; SQL local/remoto coincide.
- SQL normal/authenticated y admin controlado: PASS con rollback. No sesiones
  reales cerradas; trigger de alta conserva LECTOR/PENDIENTE sin copiar privilegios.
- Host Qt 6.9.3: authsession.cpp y supabaseclient.cpp compilados, CTest 1/1 PASS.
- Fallos A-B-A y escritura transitoria del correo reproducidos antes de corregir.
- URL firmada consumida dentro de C++; QML solo recibe cache local sin tokens.
- SET ROLE supabase_auth_admin no permitido por conector; no se altera seguridad
  para el test. Flujos reales GoTrue/Storage con JWT firmado siguen pendientes.
- Informe: docs/ACCOUNT_SESSIONS_PROFILE_20261027.md. Sin build ni prueba Android.

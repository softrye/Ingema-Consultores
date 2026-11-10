# Configuracion: Storage del servidor y recuperacion (2026-10-27)

Proyecto intervenido: **InGePlus-Dev / aalmeaqhhlhzwwzsbbxz**.
Rama: `codex/fusionbridge-native`. Sin commit ni push. Sin compilacion,
instalacion, arranque o logcat Android por instruccion expresa del usuario.

## Causa raiz

`inge_drive_storage_usage_v03(uuid)` ya sumaba `storage.objects` de todos los
buckets, pero solo despues de verificar que el usuario tuviera un espacio
legible. Si no lo tenia, devolvia cero y cuota nula. Ademas delegaba `breakdown`
a v02: espacios accesibles al usuario, nombres de espacios y un total distinto
del uso del proyecto. El LECTOR de prueba recibia 54385703 bytes y `[]`.

`NothingDocuments::storageUsage()` envia `m_space` o JSON null si esta vacio.
En `home` puede conservar `_root_space` del journal. `SupabaseStorageProvider`
usa `SupabaseClient::makeRequest(..., auth->accessToken())`, que agrega la anon
key y el JWT del usuario. No necesita service_role ni cambios C++ para la RPC.

## Migracion aplicada

`supabase/migrations/20261027204426_settings_project_storage_usage_v03.sql`.
Nombre remoto: `settings_project_storage_usage_v03`; version `20261027204426`.
Se creo el archivo con CLI `supabase migration new`; se alineo su timestamp con
el asignado por `apply_migration`. SQL local/remoto identico al normalizar
saltos de linea y espacios exteriores: MD5 `3f4b75496f7f9196d1f30b3def2bbf76`.

- Misma firma, default null y `returns setof jsonb`: REST sigue devolviendo `[{}]`.
- `used`: suma una vez cada objeto de TODOS los buckets, sin filtrar por usuario,
  espacio, lifecycle o estado del archivo. Incluye retenidos y no enlazados.
- `breakdown`: cinco objetos `{key,label,bytes}`. Precedencia: Calicatas
  (bucket y referencias originales/derivadas), Rendiciones (referencias de
  adjuntos y prefijo reservado `project-files/renditions/`), Fotos (MIME image),
  Documentos (project-files/referencias documentales), Otros (resto).
  Las fotos pertenecientes a un dominio se incluyen en ese dominio. Objetos
  sin clasificacion documental conocida en otros buckets pertenecen a Otros.
- `scope='project'`; `quota_kind='ADMIN_CONFIGURED_PROJECT_ALLOCATION'`.
- `remaining=total-used`, incluso si el resultado fuera negativo.
- `measured_at`: instante de inicio de la consulta del servidor, ISO 8601.
- Se conserva el campo adicional legado `drive_used`; solo ese escalar depende
  de p_space_id. No participa en used, remaining ni breakdown.
- Auth obligatoria; `SECURITY DEFINER SET search_path=''`; ACL:
  `postgres=X/postgres, authenticated=X/postgres`. Sin EXECUTE para PUBLIC,
  anon ni service_role. No se exponen archivos, rutas, usuarios o espacios.
- Sin cuota: `STORAGE_QUOTA_NOT_CONFIGURED`. Tamano ausente/invalido:
  `STORAGE_OBJECT_SIZE_UNAVAILABLE`. Nunca se inventa cero silenciosamente.

## Cuota: procedencia y limite de interpretacion

Tabla privada existente `private.inge_drive_project_storage_config`, fila
singleton: **1073741824 bytes (1 GiB)**, `plan=free`. Se mantuvo el importe y se
actualizo la evidencia de verificacion. `get_organization` confirmo Free el
2026-10-27. La fuente oficial publica Free=1 GB y usa 1073741824 en su ejemplo:
https://supabase.com/docs/guides/platform/manage-your-usage/storage-size

Es una **asignacion administrativa para este proyecto**. Supabase define la
cuota facturada por organizacion y promedio temporal (GB-horas); no es disco
fisico disponible, un limite duro por proyecto ni el remanente de facturacion
de la organizacion. Se debe revisar esta configuracion si cambia el plan o
la asignacion. No se consulto ni modifico el otro proyecto.

## Pruebas reales de base de datos

Archivo: `tests/settings/project_storage_usage_v03.sql`, ejecutado con
`execute_sql` en Dev. RED anterior: `FAIL_PROJECT_SCOPE`. GREEN posterior:
ejecucion sin errores, con rollback de todas las modificaciones de prueba.

Se selecciono un perfil existente ACTIVO, LECTOR, sin global_role; se asignaron
sus claims en la transaccion y se ejecuto `SET LOCAL ROLE authenticated`.
**Es una prueba SQL de rol e identidad, no un login ni una llamada HTTP con un
JWT real de esa persona.** No se uso una sesion de administrador para ejecutar
esa parte de la prueba. La conexion de mantenimiento prepara/verifica el test.

Comprueba null y UUID inexistente, suma exacta de todos los buckets, cuota de
configuracion, resta exacta, cinco etiquetas, solo claves agregadas, fecha,
ACL, search_path y rechazo sin auth.uid. Tambien prueba cuota ausente y excedida
mediante cambios privados temporales que se revierten en la misma transaccion.
La cuota real se volvio a consultar y sigue en 1073741824 bytes.

JSON obtenido (bytes; sin identificadores personales):

```json
{
  "used": 54385703,
  "total": 1073741824,
  "remaining": 1019356121,
  "breakdown": [
    {"key":"documents","label":"Documentos","bytes":926249},
    {"key":"photos","label":"Fotos","bytes":5831447},
    {"key":"renditions","label":"Rendiciones","bytes":9591519},
    {"key":"calicatas","label":"Calicatas","bytes":37324768},
    {"key":"other","label":"Otros","bytes":711720}
  ],
  "scope": "project",
  "quota_kind": "ADMIN_CONFIGURED_PROJECT_ALLOCATION",
  "measured_at": "2026-10-27T20:45:46.38536+00:00",
  "drive_used": 0
}
```

`get_advisors(type=security)` ejecutado: el proyecto tiene avisos generales,
incluido SECURITY DEFINER expuesto a authenticated (intencional en esta RPC),
tablas privadas con RLS sin politicas y proteccion de contrasenas filtradas
desactivada. No se modificaron permisos ni funciones ajenas para silenciarlos.

## Cambiar contrasena: fuente C++ y pendientes Auth

`AuthSession::requestPasswordReset` conservaba el correo exactamente como lo
recibe, pero enviaba `redirect_to` dentro del JSON. Auth lo lee de query/form
o cabecera, no del objeto JSON; corroborado en la fuente oficial:
https://github.com/supabase/auth/blob/master/internal/utilities/request.go

Cambio minimo en `authsession.cpp`: `QUrlQuery` agrega `redirect_to` a la URL
de `/auth/v1/recover`; body solo `{email: em}`. Se conserva la URL prevista:
`com.ingema.ingeplus://login-callback`. El log solo registra HTTP y codigo de
error de red; se retiran cuerpo y texto libre de error de esa operacion.
Revisado con `git diff --check` e inspeccion de fuente; no compilado/ejecutado.

El conector Supabase no ofrece lectura/escritura de configuracion Auth. El
panel abierto solicito login y el usuario indico que iniciara sesion. Hasta
tener acceso siguen **sin verificar**:

1. Plantilla Reset password y asunto en espanol.
2. Allowlist exacta `com.ingema.ingeplus://login-callback` en URL Configuration.
3. SMTP personalizado, remitente, limites y entrega a una bandeja real.

Si no hay SMTP personalizado, el servicio por defecto solo entrega a miembros
del equipo del proyecto y esta limitado actualmente a 2 mensajes/hora:
https://supabase.com/docs/guides/auth/auth-smtp
No afirmar que esos limites sean los configurados aqui sin ver el panel.

Riesgos de cliente detectados para quien mantiene la pantalla:
- HomeScreen muestra "Te enviamos" inmediatamente, sin esperar
  `passwordResetRequestedOk/Fail`; un fallo de SMTP puede parecer exito.
- El manifest fuente solo tiene intent-filter MAIN/LAUNCHER: no se encontro
  BROWSABLE ni manejo de `login-callback` o flujo de nueva contrasena en los
  fuentes revisados. Allowlist y entrega de correo no bastan para cerrar la
  recuperacion en Android. No se implemento ese flujo nuevo en esta tarea.
- Se necesita compilar el cambio C++ y probar correo/enlace con el usuario.

La huella no requiere cambios de Supabase y no se modifico su implementacion.

## Herramientas/comandos

`get_project`, `get_organization`, `execute_sql` (auditoria y archivo de prueba),
`apply_migration`, `get_advisors`, `query_logs` (solo agregados de Auth);
`npm exec --yes --package=supabase -- supabase --version` (2.122.0),
`npm exec --yes --package=supabase -- supabase migration new settings_project_storage_usage_v03`,
`git diff --check -- authsession.cpp`, `git diff -- authsession.cpp`.

Solo se listo ADB antes de la aclaracion del usuario; no se compilo, instalo,
inicio ni opero la app del telefono. No hay validacion Android ni afirmacion
de entrega de correo. El trabajo de Auth queda abierto hasta verificar panel
y probar entrega/enlace. No se han creado commits ni enviado cambios a Git.

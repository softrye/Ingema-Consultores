# Mi cuenta: sesiones, area y avatar privado

Fecha: 2026-10-27. Proyecto intervenido exclusivamente:
**InGePlus-Dev / aalmeaqhhlhzwwzsbbxz**. Rama `codex/fusionbridge-native`.
Sin commit, push, compilacion Android, ADB ni operacion del telefono.
Se preservaron los cambios locales previos.

## Causas y migracion aplicada

Faltaban ambas RPC, `profiles.area`, la sincronizacion de cambios de metadata
Auth a profiles y el bucket usado por el cliente (`IngePlus`, inexistente).
El cliente tampoco enviaba un User-Agent identificable.

Migracion: `supabase/migrations/20261027214310_account_sessions_profile_v01.sql`.
Creada con `supabase migration new account_sessions_profile_v01`, aplicada
mediante `apply_migration` solo en Dev y renombrada para coincidir con la
version remota `20261027214310`. SQL local/remoto iguales al normalizar saltos
de linea y espacios exteriores: MD5 `0f9272fab0ec5a2a7ac3efde8ad318cb`.

### RPC de sesiones

- `list_my_auth_sessions_v01() returns jsonb`: array JSON directo, compatible
  con el cliente (no SETOF ni array anidado). Filtra `user_id=auth.uid()` y
  `not_after IS NULL OR not_after>=now()`. Actual primero; luego actividad
  descendente, usando `coalesce(refreshed_at AT TIME ZONE 'UTC',updated_at,created_at)`.
  `refreshed_at` no tiene zona en este proyecto; la conversion explicita evita
  depender de la timezone de la conexion.
- Solo entrega id, current, platform, platform_label, device_label, location
  null, created_at y last_active_at. No devuelve UA crudo, IP ni credenciales.
- Clasifica Android nativo, navegadores Android, iPhone/iPad, navegadores PC,
  cliente Desktop y desconocidos. Modelo Android limitado a caracteres/longitud
  seguros; navegador y sistema se reducen a etiquetas conocidas.
- `revoke_my_auth_session_v01(p_session_id uuid) returns jsonb`: solo elimina
  otra sesion propia; exige identificar una sesion actual todavia existente.
  Actual: error 22023 en espanol. Ausente/ajena: mismo error P0002 en espanol,
  evitando revelar existencia ajena. Exito: `{"ok":true}`.
- FK real comprobada: `auth.refresh_tokens.session_id -> auth.sessions.id ON
  DELETE CASCADE`. Los JWT ya emitidos no desaparecen: siguen siendo utilizables
  en APIs que solo validan su firma/expiracion hasta expirar, normalmente ~1 h.
  La RPC de revocacion adicionalmente exige que la sesion emisora siga activa.
- Ambas: SECURITY DEFINER, search_path vacio; ACL efectiva solo propietario
  postgres y authenticated. Sin EXECUTE para PUBLIC, anon ni service_role.
  No se agregaron permisos directos sobre auth.sessions ni auth.refresh_tokens.

Fuente de la limitacion de JWT:
https://supabase.com/docs/guides/auth/signout

### Area administrativa

`profiles.area text nullable`. Conserva el SELECT-only de authenticated y el
RLS existente: perfil propio o acceso global autorizado. No se agregaron
UPDATE de tabla ni policies de escritura propias.

Para administracion se agrego:
`set_profile_area_controlled_v01(p_profile_id uuid,p_area text,p_expected_updated_at timestamptz)`.
Reutiliza `private.files_admin_require_v01()` y las reglas del setter de rol
institucional: destino activo, no autoasignacion y proteccion de administradores
superiores. Comprueba updated_at, bloquea la fila y registra
`PROFILE_AREA_UPDATED` en el sistema existente de actividad, sin guardar el
texto del area en el log. Limite 120 caracteres; null/vacio limpia la asignacion.
La web debe llamar esa RPC con la version leida de profiles si implementa edicion.

### Metadata y alta de usuarios

Trigger privado `zz_sync_auth_profile_metadata_v01` AFTER INSERT / UPDATE de
raw_user_meta_data en auth.users. Conserva `on_auth_user_created` y se ejecuta
despues de el. Solo sincroniza claves presentes y cambiadas: full_name, phone
y avatar_path propio. No toca email, position, area, role, status, global_role,
app_metadata ni asignaciones administrativas. El telefono puede vaciarse.

La migracion solo rellena phone si profiles.phone era null y existia metadata
de texto. No sobrescribe nombres existentes ni borra datos en migracion.

## Avatar: decision confirmada por el usuario

Bucket `avatars` **privado**, 5242880 bytes por objeto, MIME image/png y
image/jpeg. Rutas propias permitidas: `<uid>/avatar/avatar.png`, `.jpg` o `.jpeg`.
Policies SELECT/INSERT/UPDATE/DELETE propias, mas una policy restrictiva para
impedir que policies permisivas de otros dominios abran avatares ajenos.
No se modificaron buckets ni policies anteriores.

Metadata Auth persiste `avatar_path=<uid>/avatar/avatar.png`. El trigger
comprueba propiedad y existencia del objeto antes de fijar
`profiles.avatar_url=storage://avatars/<uid>/avatar/avatar.png`. Esa referencia
no contiene credenciales y no es una URL publica ni firmada.

**Contrato para la web:** reconocer `storage://avatars/`, extraer la ruta y usar
`supabase.storage.from('avatars').createSignedUrl(path,3600)` con la sesion del
propio usuario. Los demas usuarios, incluidos administradores desde el cliente,
no pueden leer avatares ajenos con estas policies. No se edito una web externa.

Android/C++ solicita firma con JWT propio y descarga internamente mediante esa
firma. QML recibe solo una imagen cacheada localmente: ni preferencias ni
errores automaticos de Image reciben URLs con token. La firma vive solo en
memoria durante la descarga. Las firmas emitidas duran una hora.

Referencia de firma y borrado REST corroborada en codigo oficial:
https://github.com/supabase/storage-js/blob/master/src/packages/StorageFileApi.ts

## Cambios C++

- `supabaseclient.cpp`: User-Agent para todas las solicitudes, incluido login
  y refresh. Android usa Build.MANUFACTURER, Build.MODEL y Build.VERSION.RELEASE
  via QJniObject; version de QCoreApplication. No usa serial ni identificador
  unico. Formato: `InGePlus-Android/<version> (Samsung SM-A125M; Android 12)`.
  Desktop/iOS tienen identificadores propios. Campos saneados contra CR/LF.
- `authsession.cpp`: select de profiles agrega area; phone vacio se refleja.
  updateUserProfile mantiene el correo exacto y actualiza notificaciones del
  nombre; no emite ni temporalmente la escritura normalizada del servidor.
- `authsession.cpp/.h`: callbacks de sesiones y perfil validan usuario,
  generacion de Auth y contador de restauracion de cuenta. Se reprodujo y
  corrigio el caso A -> B -> A donde una lista vieja podia volver a aplicarse.
  Una respuesta de sesiones malformada da error explicito.
- Avatar: bucket fijo avatars, PNG/JPEG hasta 5 MiB de entrada y salida,
  firma/descarga privada, guardas contra cambio de cuenta y concurrencia.
  Quitar avatar usa DELETE de Storage con prefixes y despues limpia metadata;
  ya no oculta errores de borrado/metadata ni declara exito remoto si fallan.
- `signOutOtherSessions` conserva Auth `/logout?scope=others` y la cuenta actual.

## Pruebas y evidencia

`tests/settings/account_sessions_profile_v01.sql`: ejecutado en Dev, PASS.
Claims construidos a partir de un LECTOR ACTIVO real sin global_role y su
session_id real; `SET LOCAL ROLE authenticated`. No se extraen JWT, IP ni tokens.
Es una prueba de identidad/rol SQL, **no una peticion HTTP con JWT firmado**.

La prueba crea sesiones y un refresh token de prueba en una transaccion,
comprueba revocacion/cascada y termina con ROLLBACK. No se cerro ninguna sesion
real. Cubre aislamiento de sesiones y profiles, expiracion, orden, etiquetas,
rechazo de la actual y ajenas, area inaccesible al propietario, setter
administrativo/auditoria/version obsoleta y metadata con intentos de elevar roles.
Tambien verifica el alta conserva LECTOR/PENDIENTE y no copia privilegios.

La conexion del conector rechazo `SET ROLE supabase_auth_admin`; no se
ampliaron permisos. Alta/sync se probaron con la conexion de mantenimiento,
incluido el trigger SECURITY DEFINER. Sigue pendiente el flujo HTTP GoTrue real.

Prueba de avatares en servidor: limite, MIME, bucket privado, cinco policies y
predicado real de propiedad/ajeno/traversal comprobados. No se subieron binarios
al servidor ni se probaron firmas HTTP reales; el bucket tiene 0 objetos.

Regresion `tests/settings/project_storage_usage_v03.sql`: PASS; total usado
54385703 bytes sin cambios. Estado posterior: 4 perfiles, 1 sesion del LECTOR,
0 areas de prueba. Todos los datos de prueba fueron revertidos.

`tests/settings/client`: ejecutable Windows aislado con los archivos reales
authsession.cpp y supabaseclient.cpp, Qt 6.9.3, servidor HTTP local de prueba e
INI temporal (credenciales ficticias). CTest PASS 1/1. Cubre UA/cabeceras/timeout,
A-B-A, error de JSON, payload de perfil, telefono vacio, correo exacto incluso
en señales, avatar upload/firma/descarga/delete, fallo 403 visible, 5 MiB,
formato BMP rechazado, revocacion y logout others sin cambiar la cuenta actual.

Se observaron fallos RED reales antes de las correcciones de RPC ausente,
UA ausente, respuesta A-B-A y cambio transitorio de escritura del correo.
Problemas de compilacion del test/entorno se corrigieron antes del PASS final.

Comandos de host (PATH de Qt/MinGW habilitado en la sesion de prueba):

```text
C:/Qt/Tools/CMake_64/bin/cmake.exe -S tests/settings/client -B C:/Users/PC-02/AppData/Local/Temp/inge-account-client-checks -G Ninja -DCMAKE_PREFIX_PATH=C:/Qt/6.9.3/mingw_64 -DCMAKE_CXX_COMPILER=C:/Qt/Tools/mingw1310_64/bin/g++.exe -DCMAKE_MAKE_PROGRAM=C:/Qt/Tools/Ninja/ninja.exe
C:/Qt/Tools/CMake_64/bin/cmake.exe --build C:/Users/PC-02/AppData/Local/Temp/inge-account-client-checks
C:/Qt/Tools/CMake_64/bin/ctest.exe --test-dir C:/Users/PC-02/AppData/Local/Temp/inge-account-client-checks --output-on-failure
git diff --check -- authsession.cpp authsession.h supabaseclient.cpp
```

Advisors consultados antes/despues. Las tres nuevas RPC generan el aviso
generico SECURITY DEFINER accesible por authenticated, intencional y revisado.
No se abrio EXECUTE anon. Permanecen avisos generales previos del proyecto.
Revision final propia y secuencial, respetando la regla de no paralelizar.

## JSON obtenido de la RPC 1

Solo se sustituyo id por un UUID de ejemplo antes de devolverlo desde SQL:

```json
[
  {
    "id": "00000000-0000-4000-8000-000000000001",
    "current": true,
    "platform": "web",
    "platform_label": "Windows · Chrome",
    "device_label": "PC · Chrome",
    "location": null,
    "created_at": "2026-09-04T00:23:01.65584+00:00",
    "last_active_at": "2026-09-04T00:23:01.65584+00:00"
  }
]
```

RPC 2, sobre sesion temporal propia revertida: `{"ok":true}`.
Fixture Android comprobado: platform android, platform_label Android,
device_label Samsung SM-A125M. Sesiones antiguas conservan el UA que Auth
registro; el nuevo nombre requiere una solicitud de Auth con el nuevo cliente.

## Limites pendientes

- No hay build Android, JNI ejecutado en telefono, instalacion ni logcat.
- Falta probar login/edicion/avatar HTTP con JWT real y el cliente web.
- La web debe implementar la firma propia de la referencia storage://avatars/.
- Revocar no invalida inmediatamente los access tokens ya emitidos.
- Si se borra el objeto pero falla limpiar metadata, se informa el error y
  puede reintentarse quitar foto; no se afirma una transaccion entre Storage/Auth.
- No se declara la app Android completa ni validada en dispositivo.

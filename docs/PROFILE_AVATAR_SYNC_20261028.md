# Foto de perfil entre dispositivos

Proyecto intervenido: **InGePlus-Dev / aalmeaqhhlhzwwzsbbxz**.
Rama `codex/fusionbridge-native`. Fecha local: 28/10/2026, America/Lima.
No se consultó ni modificó `zzoaqymmejdpfrolecps`. Sin commit/push, build Android,
instalación ni logcat. Se preservaron los cambios previos de otros trabajos.

## Causas y solución

`AuthSession` ya tenía subida privada y caché, pero codificaba PNG y usaba
`<uid>/avatar/avatar.png`. Auth solo recibía avatar_path. La descarga firmada
se omitía si existía caché: una referencia estable nunca mostraba el reemplazo
hecho desde otro dispositivo. Un avatar vacío en profiles tampoco borraba
la referencia/caché anterior. Quitar foto no emitía profileAvatarSynced.
Las policies v01 solo daban lectura al dueño.

Migración aplicada mediante apply_migration, exclusivamente en Dev:
`supabase/migrations/20261028125513_profile_avatar_sync_v02.sql`.
Versión remota **20261028125513**, aplicada 28/10/2026 12:55:13 UTC
(07:55:13 America/Lima). Nombre `profile_avatar_sync_v02`.
El archivo se generó con Supabase CLI y se renombró a la versión real remota.
SQL local/remoto iguales al eliminar espacios: MD5
`c9149e1eade50b72692c00ed324e40db`. Verificación remota 28/10/2026
13:04:42 UTC (08:04:42 America/Lima).

Migración adicional aplicada **20261028131158**:
`supabase/migrations/20261028131158_profile_avatar_oauth_metadata_compat_v02.sql`,
28/10/2026 13:11:58 UTC (08:11:58 America/Lima). Preserva el alta/login OAuth:
los proveedores usan también avatar_url con una URL externa; esas claves se
ignoran para profiles, conservando cualquier avatar privado existente. Solo
storage:// y la limpieza explícita disparan la sincronización por avatar_url;
avatar_path conserva compatibilidad. No cambia handle_new_user ni sus defaults.
Prueba RED: alta con avatar_url externo rechazada por el trigger v02 inicial;
prueba GREEN tras esta corrección, incluyendo actualización externa que no
sobrescribe una foto privada. MD5 normalizado local/remoto:
`97373dcb536c75d3a21130b38182a377`.

- Bucket privado `avatars`: 5242880 bytes, image/png e image/jpeg.
- Escritura INSERT/UPDATE/DELETE solo en carpeta propia. Se conserva el
  soporte de las tres rutas antiguas avatar/avatar.{png,jpg,jpeg}.
- SELECT para perfiles ACTIVO: dueño, administradores globales
  ADMINISTRADOR/ADMINISTRADOR_GENERAL/GERENCIA, o dos membresías ACTIVO
  vigentes del mismo proyecto ACTIVO. Sin acceso anónimo.
- Se separa la antigua admission restrictiva ALL en cuatro admissions por
  operación: ampliar SELECT nunca amplía UPDATE/INSERT/DELETE.
- La consulta cruzada de membresías usa un helper privado SECURITY DEFINER
  con search_path vacío y EXECUTE solo postgres/authenticated. El helper no
  confía en user_metadata. No se amplían las políticas ni privilegios de profiles.
- El trigger existente Auth → profiles reconoce avatar_url storage:// y el
  antiguo avatar_path. Valida pertenencia y existencia antes de guardar.
  full_name/phone conservan sus reglas; no copia email ni campos de autorización.

## C++

`authsession.cpp`, `authsession.h`:

1. Worker: JPG/PNG de hasta 5 MiB; recorte cuadrado, máximo 1024 px, JPEG
   calidad 85; comprueba también tamaño de salida. Android conserva content://.
2. POST Storage, x-upsert:true, image/jpeg, `<uid>/avatar.jpg` y no-cache.
3. PUT Auth /user con avatar_url=`storage://avatars/<uid>/avatar.jpg`,
   avatar_path y avatar_updated_at. El trigger confirma la referencia en profiles
   en la misma transacción de Auth. Se exige respuesta del usuario correcto
   con metadata confirmada; un 200 vacío no cuenta como éxito.
4. La imagen preparada queda temporalmente con sufijo .pending, fuera del
   descubrimiento de caché. Solo se publica tras confirmar Storage/Auth.
   Se limpian las rutas antiguas conocidas y la referencia propia anterior.
5. profileAvatarSynced solo tras confirmación remota y limpieza; cualquier
   error emite profileAvatarSyncWarning en español, sin cuerpos de error,
   URLs firmadas, claves ni tokens. El borrado usa el mismo contrato.
6. Firma de 300 segundos, válida solo en memoria; origen/ruta/token validados.
   Descarga privada sin Authorization de usuario ni redirecciones; máximo
   5 MiB. QML y preferencias reciben únicamente file:// de caché.
7. Al cargar profiles desde login/restauración/cambio de cuenta se descarga
   aunque exista copia local. profiles.avatar_url vacío limpia la copia y la
   referencia. Cuenta y generaciones de Auth/avatar/descarga descartan respuestas
   antiguas, incluido A→B→A. Caché separada por uid; no se modificó QML.
8. La revisión independiente encontró una carrera reproducida en RED: una
   respuesta personal antigua podía resucitar la referencia después de quitar
   foto. Los PUT de nombre/teléfono ahora excluyen los campos del avatar al
   aplicar su respuesta. Las lecturas de profiles comparan también la revisión
   de confirmación del avatar para no sobreescribir una mutación confirmada
   mientras esa lectura estaba pendiente.

## Pruebas

Pruebas host reales de los archivos AuthSession/SupabaseClient con Qt **6.9.3**,
servidor HTTP local e INI de pruebas. Compilación y CTest **1/1 PASS**.
`tests/settings/client/auth_checks.cpp` cubre JPEG/dimensiones/upsert/referencia,
errores 403 y 200 malformado, confirmación tardía, limpieza, firma 300s,
descarga fresca con caché, login de otra cuenta usando solamente profiles,
borrado remoto, A→B→A, formato/tamaño, correo exacto y sesiones.
También cubre PUT personal retenido → quitar foto confirmado → respuesta
antigua, y refresh de sesión → GET profiles iniciado durante el borrado →
confirmación del borrado → GET antiguo. Ambos conservan la eliminación.

```text
C:/Qt/Tools/CMake_64/bin/cmake.exe -S tests/settings/client -B C:/Users/PC-02/AppData/Local/Temp/inge-avatar-client-checks -G Ninja -DCMAKE_PREFIX_PATH=C:/Qt/6.9.3/mingw_64 -DCMAKE_CXX_COMPILER=C:/Qt/Tools/mingw1310_64/bin/g++.exe -DCMAKE_MAKE_PROGRAM=C:/Qt/Tools/Ninja/ninja.exe
C:/Qt/Tools/CMake_64/bin/cmake.exe --build C:/Users/PC-02/AppData/Local/Temp/inge-avatar-client-checks
C:/Qt/Tools/CMake_64/bin/ctest.exe --test-dir C:/Users/PC-02/AppData/Local/Temp/inge-avatar-client-checks --output-on-failure
git diff --check
```

SQL ejecutado en Dev: `tests/settings/profile_avatar_sync_v02.sql`, **PASS**.
Identidad del dueño: perfil real ACTIVO sin global_role, seleccionado por
consulta. SET LOCAL ROLE authenticated y claims sub/role; nunca se extrae un JWT.
Peer y ajeno, proyecto/membresías y objeto son fixtures nuevos. CRUD de metadatos
de storage.objects con RLS: insertar/leer/reemplazar/borrar propio; compañero
lee pero no escribe/borra; ajeno no lee; administrador lee; membresía finalizada
pierde acceso; no se permite mover un objeto a carpeta ajena. Prueba el trigger
Auth/profiles y la configuración privada/MIME/tamaño del bucket. Final ROLLBACK.
La guarda protect_delete solo se habilita en la transacción de prueba, para
su objeto de fixture, como lo hace el servicio Storage; no se elimina un binario real.

Esta prueba SQL **no es una subida binaria al servicio Storage**. El límite y
MIME de Storage se verificaron por configuración; el cliente se ejercitó con
binarios JPEG en HTTP local. **HTTP con JWT real pendiente**: el conector no
provee una sesión de usuario para Storage; no se extrajeron tokens guardados ni
se crearon sesiones permanentes para sortearlo.

Regresión `tests/settings/account_sessions_profile_v01.sql`: **PASS**, con
ROLLBACK, incluida creación de usuario/perfil, metadata, sesiones y área.
Después de las pruebas: cero objetos/perfiles/proyectos de fixture; el bucket
conserva su único objeto previo. Advisors de seguridad antes/después:
mismos cuatro grupos y cantidades, sin hallazgos nuevos para avatars.

## Reversión

Respaldo exacto de pg_get_functiondef de ambas funciones reemplazadas y de las
policies anteriores: `docs/sql_proposals/BACKUP_20261028_profile_avatar_sync.sql`.
Ese respaldo revierte ambas migraciones. El estado intermedio del trigger,
antes de corregir OAuth, también está guardado en
`docs/sql_proposals/BACKUP_20261028_avatar_trigger_before_oauth_compat.sql`;
no usarlo para un rollback normal porque reintroduce el rechazo a fotos de proveedores.
Para revertir, copiar su SQL a **una migración nueva**, aplicarla únicamente
en Dev mediante apply_migration y coordinar con la reversión C++ del avatar.
No reescribir la migración ya aplicada ni revertir todos los cambios de
AuthSession: había trabajo previo en esos archivos.

El respaldo restaura las funciones/policies v01 y elimina los helpers nuevos;
no borra objetos ni profiles. Al volver a v01, las nuevas rutas `<uid>/avatar.jpg`
dejan de cumplir el predicado antiguo y los compañeros pierden lectura:
no usar esa reversión aislada con clientes que ya guardaron la ruta nueva.

## Qué probar en teléfono / web y límites

- Elegir JPG/PNG, esperar confirmación; reemplazar y comprobar un único
  `<uid>/avatar.jpg`, profiles.avatar_url y Auth metadata con storage://.
- Misma cuenta en otro teléfono sin caché: descarga automática. Cambiar cuentas
  A/B y volver a A: cada foto debe ser de su dueño.
- Reemplazar desde un segundo dispositivo y volver a iniciar sesión/cargar
  el perfil en el primero: muestra la foto nueva pese a la ruta estable.
- Quitar foto y volver a entrar desde el otro dispositivo: vuelve el avatar
  predeterminado y se limpian las referencias.
- Sin conexión o ante error de Storage/Auth: aviso en español, sin éxito remoto.
- Falta validación Android real (JNI/content URI, permisos, FileDialog,
  instalación/logcat), y subida/firma/MIME/tamaño reales con JWT de usuario.
- Storage y Auth son dos servicios: una caída intermedia puede dejar objeto
  subido sin metadata, o metadata apuntando a objeto eliminado. Se informa el
  paso fallido y se puede reintentar; no se afirma atomicidad entre servicios.
- Dos dispositivos que escriben a la vez usan último escritor sobre el mismo
  objeto. No se implementó CAS para fotos. No hay escucha en tiempo real:
  se actualiza al volver a cargar profiles/iniciar sesión.
- Una firma emitida sigue siendo válida hasta 300 s aunque cambie una membresía.

Pendiente web: reconocer storage://avatars/, extraer bucket/ruta y firmar con
la sesión del usuario, por ejemplo createSignedUrl(path,300). Nunca usar una
URL pública ni guardar firmas en profiles. [Documentación oficial](https://supabase.com/docs/guides/storage/buckets/fundamentals).

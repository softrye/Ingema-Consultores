# Google nativo y cuentas registradas — 05/11/2026

**Actualización posterior:** el usuario completó la verificación en dos pasos; se resolvió la configuración y se activó el selector en el código. El cierre de esta activación está en `GOOGLE_NATIVE_ACTIVATION_20261105.md`. Las secciones de bloqueo y estado parcial de abajo documentan la etapa anterior.

## Causa comprobada

El botón `AuthSession::signInWithGoogle()` delegaba a `/auth/v1/authorize` y abría una Custom Tab mediante `InGeQtActivity.openOAuthUrl()`. Por eso aparecía una página web.

En InGePlus-Dev no había un hook de creación configurado. El trigger `public.handle_new_user()` crea un perfil PENDIENTE después de insertar Auth; por sí solo no impide crear una cuenta nueva por Google. Había 6 usuarios Auth antes del cambio y siguen siendo 6 después de las comprobaciones. No se consultaron ni publicaron sus correos.

## Fase 1 — servidor aplicado

Migración `20261105131939_google_existing_accounts_before_user_created_v01.sql`, aplicada en `aalmeaqhhlhzwwzsbbxz` con nombre `google_existing_accounts_before_user_created_v01`. Se creó con Supabase CLI y se alineó el nombre del archivo con la versión devuelta por el historial del servidor.

- Función `public.hook_google_existing_accounts_v01(jsonb)`, SECURITY INVOKER y search_path vacío, sin lecturas de usuarios ni elevación de privilegios.
- Hook **Before User Created / Postgres / public / hook_google_existing_accounts_v01**, confirmado **ENABLED** en el panel.
- Rechaza una creación cuyo proveedor o lista de proveedores de app_metadata incluya Google: HTTP 403, `GOOGLE_ACCOUNT_NOT_REGISTERED`.
- Permite el flujo de registro por correo. No toma decisiones usando user_metadata.
- Solo supabase_auth_admin tiene EXECUTE entre los roles de Auth/API; anon y authenticated no pueden invocarla.
- Los usuarios existentes y su vinculación de identidad se resuelven por Supabase antes de la creación; no se amplía ni se cambia su estado de aprobación.

Pruebas: `tests/settings/google_existing_accounts_v01.sql`, 9 aserciones aprobadas en Dev. Son llamadas de función y verificación de privilegios, sin crear usuarios. El intento adicional de ejecutar SET ROLE supabase_auth_admin fue rechazado por los permisos del conector; no se eludió esa restricción. La prueba real de login existente/desconocido queda para el dispositivo.

Advisors consultados: 4 categorías de seguridad (incluyen funciones SECURITY DEFINER ajenas y protección de contraseñas) y 4 de rendimiento. Ninguna menciona la función añadida. No se afirma que el proyecto esté libre de avisos ni que exista una comparación global anterior/posterior.

Reversión: deshabilitar primero el hook en Auth Hooks y después ejecutar `docs/sql_proposals/ROLLBACK_google_existing_accounts_v01.sql`. No se borran usuarios ni datos locales.

## Fase 2 — selector nativo

Fuentes preparadas: Credential Manager con GetSignInWithGoogleOption; ID token hacia AuthSession; nonce SHA-256 a Google y nonce original a Supabase; finalización común con perfil y MFA. Las rutas genéricas Google en Android también pasan por el selector nativo; no existe una recuperación automática hacia el navegador. Cancelación, tiempo límite y resultados atrasados se separan por generación de autenticación. El callback JNI se entrega en el hilo de Qt.

El puente Java está en `android/pending-google-signin`, fuera de las raíces Java activas. Las nuevas dependencias credentials 1.6.0, credentials-play-services-auth 1.6.0 y googleid 1.2.1 se documentaron para la futura activación, pero **no se añadieron al Gradle activo**. Se retiraron las llamadas nuevas a ese puente de InGeQtActivity. La lógica Google Drive conserva AuthorizationClient y sus permisos propios.

Pruebas interpretadas: `node tests/settings/google_native_result.cjs` ejecuta el control real de callbacks/cancelación Java; `node tests/settings/google_native_session.cjs` comprueba la finalización C++ preparada, con adaptación de sintaxis Qt/Java. Pasan descarte de respuestas antiguas y duplicadas, cancelación, respuestas de sesión incompletas, recuerdo de sesión y bloqueo MFA. También pasan `google-authorization-result.cjs` y `google-drive-export.cjs`. No equivalen a compilar Java/C++ ni ejecutar Credential Manager en Android.

### Bloqueo de configuración: identidad Android ya registrada

Se calculó la huella pública de `.android/debug.keystore` mediante keytool: `DA:46:3A:DC:67:14:48:4B:2F:26:D1:6E:F7:79:57:F9:3F:49:E5:62`. Con confirmación expresa del usuario se intentó crear el cliente Android para `com.ingema.ingeplus` en `helical-autumn-513714-h2`. Google rechazó la operación: «el nombre del paquete de Android y la huella digital ya están en uso». No se creó el cliente ni se borró el existente.

El diagnóstico anterior `docs/google-drive-oauth-export-diagnosis.md` registra esos clientes en `ingeplus-drive` y también la huella release suministrada anteriormente por el usuario: `ED:AD:F4:9C:76:7A:5F:DD:0B:E0:C5:3D:CB:16:F2:1F:B0:BA:4F:F4`. No asumir que debug sea la firma del APK instalado.

Se abrió después el perfil Proyecto Lechemayo, pero Google Cloud lo bloqueó por verificación en dos pasos. El usuario indicó que los dispositivos de verificación no son suyos y pidió dejar esta implementación parcial para poder compilar.

**Estado parcial autorizado:** `src/cpp/googleauthconfiguration.h` fija `INGE_GOOGLE_NATIVE_SIGN_IN_CONFIGURED = 0`. Android sigue utilizando el flujo web PKCE que el usuario ya comprobó. Ambas entradas Google respetan la misma selección, evitando recursión. No se intenta abrir el navegador como reacción a un error nativo: el modo web es la selección explícita de esta versión parcial. El bloqueo servidor de altas Google permanece activo.

La configuración externa pendiente no impide compilar esta selección web. No se ha ejecutado una compilación para confirmarlo, por instrucción del usuario. La parte nativa permanece preparada y desactivada hasta reutilizar una configuración compatible del mismo proyecto para el cliente Android y la audiencia web, conservando Google Drive. La audiencia web que figura temporalmente en GoogleNativeSignIn corresponde al proyecto nuevo y debe revisarse antes de activar la parte nativa.

No se ha compilado, instalado, cerrado sesión en la app ni probado el selector en el teléfono. Los cambios C++/cabecera preparados de esta fase permanecen sin commit: parten de cambios anteriores sin commit y `git apply --cached --3way --check` mostró solapamientos. Ese comando fue solo comprobación; no se reemplazaron archivos ni se dejaron conflictos en el índice. El commit de servidor es independiente. El checkpoint parcial conserva el puente Java desactivado, su configuración y documentación sin incorporar cambios ajenos de AuthSession. Resolver la integración del commit al completar la configuración.

## Fuentes

- Código fuente: authsession.cpp, authsession.h, android/src/com/ingema/ingeplus/InGeQtActivity.java.
- SQL: trigger `on_auth_user_created`, función `public.handle_new_user`, conteo auth.users e historial supabase_migrations.schema_migrations.
- https://developer.android.com/identity/sign-in/credential-manager-siwg-implementation
- https://supabase.com/docs/guides/auth/social-sign-in/auth-google
- https://supabase.com/docs/guides/auth/auth-hooks/before-user-created-hook

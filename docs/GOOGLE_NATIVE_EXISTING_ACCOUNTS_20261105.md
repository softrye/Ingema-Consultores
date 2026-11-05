# Google nativo y cuentas registradas — 05/11/2026

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

Implementación en curso en esta fase: Credential Manager con GetSignInWithGoogleOption; ID token hacia AuthSession; nonce SHA-256 a Google y nonce original a Supabase; finalización común con perfil y MFA. El cliente Android restringido por paquete y certificado requiere creación en Google Cloud. No se ha compilado ni probado el selector en el teléfono.

## Fuentes

- Código fuente: authsession.cpp, authsession.h, android/src/com/ingema/ingeplus/InGeQtActivity.java.
- SQL: trigger `on_auth_user_created`, función `public.handle_new_user`, conteo auth.users e historial supabase_migrations.schema_migrations.
- https://developer.android.com/identity/sign-in/credential-manager-siwg-implementation
- https://supabase.com/docs/guides/auth/social-sign-in/auth-google
- https://supabase.com/docs/guides/auth/auth-hooks/before-user-created-hook

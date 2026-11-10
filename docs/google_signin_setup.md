# Iniciar sesión con Google: configuración (Google Cloud + Supabase)

La app usa **Supabase OAuth con PKCE**:

1. Abre `{SUPABASE_URL}/auth/v1/authorize?provider=google&redirect_to=com.ingema.ingeplus://login-callback&code_challenge=…&code_challenge_method=s256` en una Custom Tab.
2. Supabase redirige a `com.ingema.ingeplus://login-callback?code=…`.
3. `InGeOAuthCallbackActivity` recibe ese enlace y se lo pasa a `InGeQtActivity`.
4. `AuthSession` canjea el código con `POST /auth/v1/token?grant_type=pkce`.

En la app no hay `service_role` ni el secreto del cliente de Google. El secreto se guarda solo en el dashboard de Supabase.

Datos de este proyecto:
- `SUPABASE_URL`: `https://aalmeaqhhlhzwwzsbbxz.supabase.co` (en `appcontext.cpp`).
- Paquete Android: `com.ingema.ingeplus` (en `CMakeLists.txt`, `INGE_ANDROID_PACKAGE_NAME`).
- Redirect de la app: `com.ingema.ingeplus://login-callback`.

## 1. Google Cloud Console

Proyecto: [PROYECTO DE GOOGLE CLOUD A USAR — el de Drive es `ingeplus-drive`].

1. Ve a **APIs y servicios → Pantalla de consentimiento de OAuth** (Google Auth Platform → Branding).
   - Tipo de usuario: **Externo**.
   - Nombre de la app: `InGe+`. Correo de asistencia: [CORREO DE SOPORTE].
   - Dominios autorizados: `supabase.co`.
   - Permisos: `openid`, `.../auth/userinfo.email` y `.../auth/userinfo.profile`. No hacen falta permisos sensibles.
   - Mientras la app esté en «Prueba», solo entran los **usuarios de prueba** que añadas. Para abrirla a todos, publícala con «Publicar app».
2. Ve a **Credenciales → Crear credenciales → ID de cliente de OAuth → Aplicación web**. Este es el cliente que usa Supabase.
   - Nombre: `InGe+ Supabase (web)`.
   - **Orígenes de JavaScript autorizados**: `https://aalmeaqhhlhzwwzsbbxz.supabase.co`.
   - **URI de redireccionamiento autorizados**: `https://aalmeaqhhlhzwwzsbbxz.supabase.co/auth/v1/callback`.
   - Guarda el **ID de cliente** y el **Secreto del cliente**. Van solo en Supabase, nunca en la app ni en Git.
3. Ve a **Credenciales → Crear credenciales → ID de cliente de OAuth → Android**. Sirve para identificar el APK. Con la Custom Tab, Supabase no lo usa, pero Google lo exige para apps Android y para un Google Sign-In nativo futuro.
   - Nombre del paquete: `com.ingema.ingeplus`.
   - Huella SHA-1 del certificado con el que se firma el APK. Créalo dos veces si usas dos firmas (debug y release). Para obtener la huella:
     ```bash
     keytool -list -v -keystore "%USERPROFILE%\.android\debug.keystore" -alias androiddebugkey -storepass android -keypass android
     ```
     ```bash
     keytool -list -v -keystore [RUTA DEL KEYSTORE DE RELEASE] -alias [ALIAS]
     ```
     Copia la línea `SHA1: XX:XX:…`. Si publicas en Play con «Firma de apps de Google Play», usa también el SHA-1 que aparece en Play Console → Integridad de la app.

## 2. Dashboard de Supabase (proyecto `aalmeaqhhlhzwwzsbbxz`)

1. Ve a **Authentication → Sign In / Providers → Google**.
   - Activa **Enable Sign in with Google**.
   - **Client IDs**: pega el ID de cliente **web** del paso 1.2. Si también quieres aceptar tokens del cliente Android, añádelo separado por coma.
   - **Client Secret (for OAuth)**: pega el secreto del cliente web.
   - Deja «Skip nonce checks» desactivado.
   - Guarda.
2. Ve a **Authentication → URL Configuration → Redirect URLs** y añade:
   - `com.ingema.ingeplus://login-callback`

   (La app ya lo usaba para recuperar la contraseña. Si ya está en la lista, no hace falta repetirlo.)
3. **Site URL**: no la cambies. Sigue siendo la de la web.
4. En **Authentication → Sign In / Providers**, revisa que **Allow new users to sign up** esté como quieras.
   - Si está activo, cualquier cuenta de Google crea un usuario nuevo. Con la puerta de perfil, ese usuario verá «Tu cuenta está pendiente de aprobación» hasta que un administrador lo apruebe.

## 3. Pendiente de servidor

- **[PENDIENTE SERVIDOR]** Comprueba que el trigger que crea `public.profiles` al registrarse un usuario también corre para usuarios OAuth y deja `status = 'PENDIENTE'`.
  - Si no hay perfil, la app muestra «La cuenta no tiene un perfil autorizado en InGe+» en lugar de la pantalla de pendiente.
- **[PENDIENTE SERVIDOR]** La política RLS de `profiles` debe dejar que un usuario `PENDIENTE` lea su propia fila (`id = auth.uid()`). Con eso basta para la pantalla de pendiente.
  - `get_coordinated_access_state_v01` no da el estado del perfil (solo indica si el sistema coordinado está activo), así que no se usa.

## 4. Prueba en el teléfono (después de compilar)

1. Login → «Continuar con Google» → se abre una Custom Tab de Google → eliges la cuenta → vuelves a InGe+.
2. En logcat deben aparecer:
   - `INGE_OAUTH_CALLBACK_RECEIVED`
   - `[Auth] OAUTH_EXCHANGE_STARTED`
   - `[Auth] OAUTH_RESULT=SUCCESS`

   Nunca se registran el código ni el verifier.
3. Según la cuenta:
   - **ACTIVO**: entra igual que con correo. Si es la primera vez, pasa por la bienvenida.
   - **Con 2FA**: pide el código de 6 dígitos.
   - **PENDIENTE**: aparece la pantalla de vidrio «Tu cuenta está pendiente de aprobación».
4. Si cierras la Custom Tab sin elegir cuenta, verás «No se completó el inicio de sesión con Google.».
5. Errores frecuentes:
   - `redirect_uri_mismatch` en Google: falta el URI `…/auth/v1/callback` del paso 1.2.
   - Vuelves a la web en lugar de la app: falta el Redirect URL del paso 2.2.

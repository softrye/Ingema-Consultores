# Google Login — configuración del 04/11/2026

## Fase 1: Google Cloud configurado para pruebas

- Proyecto nuevo solicitado por el usuario: **InGePlus Google Login**.
- ID asignado: `helical-autumn-513714-h2`.
- Identidad OAuth: **InGe+**, público externo, estado **Prueba**.
- Soporte y contacto: cuenta de Fernando autorizada por el usuario; no se reproduce su correo en este documento.
- Cliente creado: **InGe+ Android · Supabase Dev**, tipo **Aplicación web** (Supabase realiza el intercambio con Google).
- Único retorno autorizado del cliente: `https://aalmeaqhhlhzwwzsbbxz.supabase.co/auth/v1/callback`.
- Permisos declarados y guardados: `openid`, `https://www.googleapis.com/auth/userinfo.email`, `https://www.googleapis.com/auth/userinfo.profile`.
- Un usuario de prueba añadido: la cuenta de Fernando autorizada por el usuario.
- Se aceptó la política de datos y se creó el cliente después de recibir confirmación explícita. No se habilitaron permisos de Drive ni se modificó el proyecto existente `ingeplus-drive`.
- Durante esta fase el secreto se conservó en el diálogo de creación y temporalmente en memoria. En la fase 2 se guardó únicamente en Supabase y se cerró ese diálogo. No se escribió en Android, Git ni archivos; se eliminaron las variables temporales que lo contenían.

## Evidencia de Android existente, sin cambios en esta fase

- `authsession.cpp`: `signInWithGoogle()` usa `/auth/v1/authorize`, challenge S256 y canje PKCE mediante `/auth/v1/token?grant_type=pkce`.
- `qml/Mobile/Main.qml`: botón y función de acceso con Google; configura recuerdo de sesión mediante AuthSession.
- `android/AndroidManifest.xml`: filtro `com.ingema.ingeplus://login-callback`.
- `android/src/com/ingema/ingeplus/InGeOAuthCallbackActivity.java`: entrega el retorno al host Qt existente.
- Estos archivos ya tenían cambios ajenos sin commit antes de esta tarea; no se modificaron ni se incluyeron en este commit.

## Fase 2: proveedor de Supabase activado y retorno Android configurado

- Antes del cambio, consulta de lectura al endpoint público `/auth/v1/settings` de **InGePlus-Dev**, usando exclusivamente su clave publicable obtenida con el complemento: `external.google = false`.
- El complemento Supabase disponible no expone una operación de configuración de proveedores de Auth. No se intentó sustituir esa configuración mediante SQL.
- Después de que el usuario inició sesión en el panel, se guardaron el ID y secreto del cliente nuevo y se activó Google. Comprobación independiente posterior del endpoint público: `external.google = true`.
- Faltaba el redirect nativo exacto `com.ingema.ingeplus://login-callback`; se añadió. La lista pasó de 3 a 4 URLs, conservando las tres existentes de la web y desarrollo.
- Site URL conservada: `https://ingeplus-web.vercel.app`. El panel confirmó Google activado, `Skip nonce checks = false` y `Allow users without an email = false`.
- No se modificaron permisos de perfiles, sesiones ni multicuenta. No se tocó el proyecto Supabase prohibido.
- Prueba de autorización en Chrome con challenge PKCE de ejemplo RFC 7636 y `prompt=select_account`: Supabase redirigió al selector de cuentas de Google usando el cliente creado y el callback configurado. No se eligió una cuenta, aceptó consentimiento de usuario, canjeó código ni creó una sesión de usuario en esta prueba. Se cerró la pestaña de prueba después de comprobar el selector.
- Esta prueba confirma el arranque del flujo y la aceptación de la configuración de cliente/redirect por Google; no confirma el canje del código ni el retorno completo en Android.

## Pendiente: validación en Android y publicación

- No se compiló, instaló ni usó ADB. La compilación la realiza el usuario.
- Después de la configuración: compilar por el usuario; probar Google → retorno a Android → perfil autorizado o pendiente → MFA cuando corresponda → restauración de la sesión. Verificar también cancelación y cambio de cuenta.
- En modo Prueba solo está habilitada la cuenta añadida. Publicación general y marca final pendientes.

## Fuentes y comprobaciones

- Google Cloud: páginas visibles de creación del proyecto, identidad, cliente OAuth, usuario de prueba y confirmación «Se guardaron los cambios de acceso a los datos».
- Endpoint de lectura: `https://aalmeaqhhlhzwwzsbbxz.supabase.co/auth/v1/settings` (solo se registró el booleano del proveedor).
- Documentación oficial consultada: https://supabase.com/docs/guides/auth/social-sign-in/auth-google
- Verificación local: `git diff --check`, revisión del documento y commits por fase limitados a este archivo. Sin pruebas nativas ni compilación.
- Evidencia visual local de la fase 2: `artifacts/google-login-20261104/supabase-google-enabled.jpg` (campo secreto en modo contraseña, sin revelar su contenido).

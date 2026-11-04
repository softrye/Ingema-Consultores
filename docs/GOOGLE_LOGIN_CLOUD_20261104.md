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
- El secreto permanece en el diálogo de creación abierto y temporalmente en memoria de la sesión de automatización. No se escribió en Android, Git ni archivos. **No cerrar ese diálogo antes de configurar Supabase**: Google advierte que el secreto solo se muestra una vez.

## Evidencia de Android existente, sin cambios en esta fase

- `authsession.cpp`: `signInWithGoogle()` usa `/auth/v1/authorize`, challenge S256 y canje PKCE mediante `/auth/v1/token?grant_type=pkce`.
- `qml/Mobile/Main.qml`: botón y función de acceso con Google; configura recuerdo de sesión mediante AuthSession.
- `android/AndroidManifest.xml`: filtro `com.ingema.ingeplus://login-callback`.
- `android/src/com/ingema/ingeplus/InGeOAuthCallbackActivity.java`: entrega el retorno al host Qt existente.
- Estos archivos ya tenían cambios ajenos sin commit antes de esta tarea; no se modificaron ni se incluyeron en este commit.

## Pendiente: configuración de Supabase y validación real

- Consulta de lectura al endpoint público `/auth/v1/settings` de **InGePlus-Dev**, usando exclusivamente su clave publicable obtenida con el complemento: `external.google = false`.
- El complemento Supabase disponible no expone una operación de configuración de proveedores de Auth. No se intentó sustituir esa configuración mediante SQL.
- El panel de InGePlus-Dev abierto en Chrome solicita iniciar sesión. Falta acceso al panel para guardar el ID y secreto del nuevo cliente, activar Google y comprobar/añadir el redirect nativo exacto `com.ingema.ingeplus://login-callback` a la lista permitida.
- Mantener Site URL, permisos de perfiles, sesiones, multicuenta y verificaciones nonce existentes. No tocar el proyecto Supabase prohibido.
- No afirmar que el inicio con Google funciona todavía: el proveedor sigue desactivado y no se realizó un login completo.
- No se compiló, instaló ni usó ADB. La compilación la realiza el usuario.
- Después de la configuración: compilar por el usuario; probar Google → retorno a Android → perfil autorizado o pendiente → MFA cuando corresponda → restauración de la sesión. Verificar también cancelación y cambio de cuenta.
- En modo Prueba solo está habilitada la cuenta añadida. Publicación general y marca final pendientes.

## Fuentes y comprobaciones

- Google Cloud: páginas visibles de creación del proyecto, identidad, cliente OAuth, usuario de prueba y confirmación «Se guardaron los cambios de acceso a los datos».
- Endpoint de lectura: `https://aalmeaqhhlhzwwzsbbxz.supabase.co/auth/v1/settings` (solo se registró el booleano del proveedor).
- Documentación oficial consultada: https://supabase.com/docs/guides/auth/social-sign-in/auth-google
- Verificación local: `git diff --check`, revisión del documento y commit limitado a este archivo. Sin pruebas nativas ni compilación.

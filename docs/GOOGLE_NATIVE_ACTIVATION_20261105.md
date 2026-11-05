# Activación de Google nativo — 05/11/2026

## Configuración verificada

Google Cloud `ingeplus-drive`, abierto con el perfil Proyecto Lechemayo después de que el usuario completó la verificación en dos pasos. No se cambiaron permisos IAM.

Clientes Android existentes, consultados sin modificarlos:

- `InGePlus Android Release`: paquete `com.ingema.ingeplus`, SHA-1 `ED:AD:F4:9C:76:7A:5F:DD:0B:E0:C5:3D:CB:16:F2:1F:B0:BA:4F:F4`.
- `InGePlus Android — Drive`: mismo paquete, SHA-1 debug `DA:46:3A:DC:67:14:48:4B:2F:26:D1:6E:F7:79:57:F9:3F:49:E5:62`.

Con aprobación explícita del usuario se creó el cliente web `InGe+ Android Login · Supabase Dev` en ese mismo proyecto:

- ID público: `503316492000-gu98earl4g0d2n0km3u7sh7m45fe951d.apps.googleusercontent.com`.
- Único redirect: `https://aalmeaqhhlhzwwzsbbxz.supabase.co/auth/v1/callback`.
- Secreto guardado exclusivamente en el proveedor Google de InGePlus-Dev; no se escribió en archivos ni se imprimió. Se cerró el diálogo de creación y se eliminaron las variables temporales con el secreto después de guardarlo.
- Proveedor recargado desde el panel: cliente nuevo en primer lugar, Google activo, Skip nonce checks desactivado y correo obligatorio.
- El ID web anterior del proyecto `helical-autumn-513714-h2` se conservó como segunda audiencia aceptada para no quitar compatibilidad a tokens anteriores. El OAuth web utiliza ahora el nuevo cliente principal y su secreto.
- No se modificaron los clientes Android, permisos de Drive, Site URL ni las redirecciones existentes. No se tocó el proyecto Supabase prohibido.

## Código

- `INGE_GOOGLE_NATIVE_SIGN_IN_CONFIGURED = 1`: el botón Android usa Credential Manager; el genérico provider=google se dirige al mismo flujo, sin navegador ante errores.
- Único puente Java movido a `android/src/com/ingema/ingeplus/GoogleNativeSignIn.java`; audiencia nueva en SERVER_CLIENT_ID.
- Dependencias activas y fijadas: credentials 1.6.0, credentials-play-services-auth 1.6.0, googleid 1.2.1.
- Resultado JNI encolado al hilo Qt. Generación, cancelación y timeout separan intentos anteriores del actual. El nonce original queda solo en memoria; Google recibe su SHA-256 hexadecimal.
- AuthSession canjea el ID token con Supabase y conserva el cierre de sesión, perfil autorizado/pendiente, multicuenta, recuerdo de sesión y MFA existentes.
- El hook `public.hook_google_existing_accounts_v01` bloquea las altas nuevas por Google; no se agrega un registro automático ni una consulta pública de correos.

## Validación y límites

Las pruebas interpretadas de Java/C++ adaptan sintaxis y tipos Qt; no son una compilación ni ejecutan el SDK de Google. La validación real debe hacerla el usuario al compilar: selector en Android, cuenta registrada, rechazo de cuenta desconocida, cancelación, MFA, cambio de cuenta, restauración de sesión, Home y exportación a Google Drive.

No se ejecutó CMake, compilación, instalación ni ADB. No se cerró la sesión de la app. No afirmar que el flujo nativo está validado en el A12 hasta esa prueba.

La integración de AuthSession preparada anteriormente sigue mezclada en esos archivos con cambios previos sin commit. Se preservó la fuente de trabajo sin incorporar esos cambios ajenos al commit de configuración/activación; el detalle se mantiene en GOOGLE_NATIVE_EXISTING_ACCOUNTS_20261105.md.

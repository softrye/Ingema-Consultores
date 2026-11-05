# Selector Google pendiente de configuración

Esta carpeta no pertenece a `android.sourceSets.main.java.srcDirs` y no se compila ni se empaqueta. El acceso activo sigue siendo Supabase OAuth PKCE.

`com/ingema/ingeplus/GoogleNativeSignIn.java` conserva el único puente nativo preparado. Su audiencia web todavía debe revisarse con acceso al proyecto que contiene los clientes Android existentes.

Antes de activarlo:

1. Resolver acceso a `ingeplus-drive` y comprobar certificados debug/release y audiencia web compatibles, sin borrar los clientes de Drive.
2. Configurar la audiencia validada en Java y Supabase manteniendo las comprobaciones de nonce y el hook de cuentas existentes.
3. Añadir esta carpeta como raíz Java en el Gradle fuente y las dependencias `androidx.credentials:credentials:1.6.0`, `androidx.credentials:credentials-play-services-auth:1.6.0` y `com.google.android.libraries.identity.googleid:googleid:1.2.1`.
4. Cambiar `INGE_GOOGLE_NATIVE_SIGN_IN_CONFIGURED` a 1 en `src/cpp/googleauthconfiguration.h` solamente después de esa configuración.
5. Compilar por el usuario y validar selección, cancelación, cuenta existente/desconocida, MFA, multicuenta y Google Drive en Android.

No activar solo cambiando el flag: faltan configuración externa y validación real.

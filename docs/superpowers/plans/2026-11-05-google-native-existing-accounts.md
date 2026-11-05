# Google nativo y cuentas existentes

Objetivo solicitado: el botón Android abre el selector del sistema y solo permite autenticar cuentas ya registradas en Supabase. No compilar; el usuario valida el APK.

Decisión técnica: Credential Manager (`GetSignInWithGoogleOption`) devuelve un ID token; AuthSession lo canjea con Supabase y reutiliza su finalización de sesión, perfil, multicuenta y MFA. Nonce aleatorio por intento: hash SHA-256 hacia Google y valor original hacia Supabase. Resultado JNI encolado al hilo Qt, protegido por la generación de autenticación. No abrir el navegador como recuperación ante errores.

Servidor: hook Before User Created que rechaza cualquier creación por proveedor Google, antes de insertar el usuario. Los usuarios existentes se resuelven/vinculan por Supabase antes de esa ruta. No consultar correos desde el cliente ni desactivar las solicitudes de registro por correo. Privilegios solo para supabase_auth_admin; sin service_role en Android.

Secuencia y comprobaciones:
- [ ] Probar el rechazo del hook a Google nuevo, permitir email y rechazar payload incompleto; crear migración reversible, aplicar y activar el hook en InGePlus-Dev; revisar advisors.
- [ ] Configurar cliente Android con paquete/firma verificada; no suponer que la firma debug corresponde a release.
- [ ] Prueba previa del contrato nativo: nonce, generación, cancelación y uso de la finalización común; implementar puente Java/C++ y dependencias fijadas.
- [ ] Revisar cambios, ejecutar pruebas interpretadas y comprobar API/configuración; commit por fase sin incluir cambios ajenos.
- [ ] Dejar explícitamente pendiente compilación, selector real en A12, cuenta existente/desconocida, MFA y regreso a Home.

Fuentes: developer.android.com/identity/sign-in/credential-manager-siwg-implementation; supabase.com/docs/guides/auth/social-sign-in/auth-google; supabase.com/docs/guides/auth/auth-hooks/before-user-created-hook.

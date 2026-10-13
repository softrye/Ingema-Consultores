# Google Drive: bloqueo tras elegir cuenta (2026-10-05)

## Segunda prueba: 20261005-1833-31.3729237.mp4

El usuario obtuvo la huella pública release ED:AD:F4:9C:76:7A:5F:DD:0B:E0:C5:3D:CB:16:F2:1F:B0:BA:4F:F4 y creó el cliente Android adicional 503316492000-tm1vmsvmtv6mujil7hglbkkijol6pcen.apps.googleusercontent.com. El nuevo video llega al consentimiento de Google con Fernando y después al selector «Conceder acceso a los archivos». El selector termina mostrando «Esta carpeta está vacía» y el usuario lo cierra sin seleccionar una carpeta. No se observa una autorización completada ni una subida confirmada. Esperar la propagación no resuelve por sí solo este paso de selección.

El registro de esa prueba no contiene INGE_GOOGLE_OAUTH_APK ni INGE_GOOGLE_AUTH_RESULT. Muestra reintentos de tres identificadores de Excel distintos. Esa combinación es compatible con un APK anterior al commit 1543e78; el registro no permite certificar su versión instalada. La corrección del reintento individual debe llegar al teléfono mediante la próxima compilación/actualización del usuario.

La petición del selector estaba filtrada por el ID de destino. Se retiró ese filtro opcional para permitir navegar/buscar las carpetas accesibles y pegar el enlace, manteniendo el filtro de tipo carpeta, selección única y drive.file. El transporte sigue rechazando cualquier selección distinta del ID configurado: no cambia el destino y no sube a otra carpeta. Los errores de permiso explican usar la cuenta propietaria o compartir 01_CALICATAS con la cuenta elegida como Editor. Que Fernando sea usuario de prueba OAuth no demuestra que pueda acceder a esta carpeta; falta confirmar ese permiso.

Prueba manual pendiente: actualizar el APK conservando los datos, pulsar Reintentar una sola vez, elegir Lechemayo (o Fernando con permiso Editor), seleccionar 01_CALICATAS en el selector y confirmar. Si no aparece, pegar https://drive.google.com/drive/folders/1UJnOr5Ef5TYdtP_g0HTRcRGIr0TgfeuX en su buscador. Comprobar los nuevos mensajes de diagnóstico y finalmente el archivo remoto. No se ha ejecutado compilación, instalación ni ADB, por instrucción del usuario. Los 27 scripts de tests/calicatas pasan con node y git diff --check no encuentra errores de espacios en los archivos de esta fase. Esta validación de fuente no sustituye una prueba Android del SDK de Google.

Referencia para los filtros opcionales y confirmación de selección: https://developers.google.com/workspace/drive/picker/guides/desktop-mobile-picker . El origen exacto de la vista vacía (visibilidad de la carpeta/cuenta o filtro) no puede confirmarse solo con este video.

## Primera prueba

Evidencia del video 20261005-1811-29.9509375.mp4 y del registro aportado: el XLSX se genera y la autorización muestra cuentas Google. Tras seleccionar, la app muestra «Autorización Google cancelada». No hay código OAuth en el registro. Los avisos de dimensiones son informativos y no impiden generar el Excel.

Causa confirmada en código: GoogleDriveAuthorization descartaba cualquier Intent con resultCode distinto de RESULT_OK antes de llamar a getAuthorizationResultFromIntent. Así reemplazaba errores OAuth por una cancelación genérica. Ahora todo Intent no nulo se decodifica con el SDK. Una respuesta realmente nula informa que Google no devolvió datos, sin atribuir una cancelación al usuario. Si Google devuelve código 10, la pantalla muestra paquete y SHA-1 del certificado del APK instalado. El registro incluye únicamente la identidad pública de firma y el código de estado, sin tokens ni correos.

También se detectaron varias operaciones Excel fallidas y autorizaciones repetidas al pulsar Reintentar. El reintento genérico liberaba todas las operaciones Google y abría consentimiento para archivos antiguos. Ahora ExcelExporter reintenta solo su proyecto/ruta/proveedor; los reintentos genéricos no abren Google. La operación elegida tiene prioridad y conserva el identificador remoto reservado.

Configuración pendiente de comprobar: .qtcreator/CMakeLists.txt.user señala como configuración activa la firma C:/Users/PC-02/Documents/InGePlus_Keys/ingeplus-release.keystore. La huella obtenida durante la configuración inicial correspondía a .android/debug.keystore (DA:46:3A:DC:67:14:48:4B:2F:26:D1:6E:F7:79:57:F9:3F:49:E5:62). No se pudo obtener el certificado del almacén release sin su contraseña; no se solicitaron ni leyeron contraseñas. Esto indica una posible falta del cliente OAuth para la firma release, pero el registro original no permite confirmar un código 10.

Para comprobar la firma sin compilar: abrir una terminal local y ejecutar el keytool del JDK, que solicita la contraseña de forma local (no enviarla al chat):

```powershell
& 'C:\Program Files\Android\Android Studio\jbr\bin\keytool.exe' -list -v -keystore 'C:\Users\PC-02\Documents\InGePlus_Keys\ingeplus-release.keystore' -alias ingeplus_release
```

Copiar únicamente SHA1. En https://console.cloud.google.com/auth/clients?project=ingeplus-drive crear un cliente Android adicional para com.ingema.ingeplus con esa huella si no existe. Conservar el cliente debug. Los usuarios de prueba y los permisos de edición de 01_CALICATAS siguen siendo necesarios. Registrar el correo como usuario de prueba no registra la firma del APK.

Después de la próxima compilación realizada por el usuario, buscar INGE_GOOGLE_OAUTH_APK y INGE_GOOGLE_AUTH_RESULT en su registro. Confirmar autorización, selección de 01_CALICATAS y archivo remoto antes de declarar la integración verificada.

Validación de fuente: test nuevo reproduce la pérdida del status 10 con RESULT_CANCELED antes del cambio y pasa después. Verifica éxito, status 16, respuesta nula y request ajeno. Los 27 scripts de tests/calicatas pasan. No se ejecutaron build, instalación ni ADB. El bloqueo real de autorización todavía requiere comprobar la firma/configuración y probar en el teléfono. Referencia oficial: https://developer.android.com/identity/authorization#request-permissions-required-by-user-actions y https://developers.google.com/android/reference/com/google/android/gms/auth/api/identity/AuthorizationClient#getAuthorizationResultFromIntent(android.content.Intent)

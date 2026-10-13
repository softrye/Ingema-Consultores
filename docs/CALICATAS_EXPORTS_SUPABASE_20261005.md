# Excel de Calicatas en la carpeta exports

Destino: el padre real del JSON editable vinculado en el servidor, con una
subcarpeta `exports`. La ubicación habitual es
`04_PROYECTOS/<proyecto>/06_GABINETE/exports`. Si el JSON se movió a otra
carpeta, las nuevas exportaciones siguen ese padre. Si aún no hay JSON,
se inicializa su carpeta canónica. No se mueven exportaciones anteriores.

La RPC `ensure_my_calicata_exports_folder_v01` ya está aplicada en
InGePlus-Dev, mediante la migración `20261005144710`. Comprueba sesión,
perfil activo, proyecto, permisos del espacio, JSON y carpeta; reutiliza
`exports` con bloqueo transaccional. Su ejecución privilegiada es necesaria
para leer el vínculo privado del JSON y usar las mutaciones existentes;
solo `authenticated` puede invocarla. No se concedió acceso a `anon`, ni se
introdujeron claves de servicio, cambios de RLS o accesos desde Android al
esquema privado. El aviso del asesor sobre SECURITY DEFINER autenticado es
esperado para esta RPC; la sesión y las ACL se validan explícitamente.

`androidcalicataexporter.cpp` pasa `remoteCalicataId` a la cola y distingue
las nuevas operaciones con `Calicatas/exports/`. La generación y recuperación
persisten esa identidad. La cola resuelve el destino antes de reservar el
binario, envía el `parent_node_id` real y conserva las reservas existentes
al reintentar. Se reutiliza el transporte compartido de la cola actual.
`CalicatasEditorPage.qml` muestra el destino real cuando está disponible;
mientras se resuelve, indica carpeta del JSON y exports sin inventar rutas.

## Comprobaciones

- `tests/calicatas/exports-folder.sql`: fallo inicial por RPC ausente, luego
  PASS contra Supabase como `authenticated`. Prueba padre del JSON, carpeta
  única, reserva XLSX dentro de exports, primer archivo local sin id remoto,
  JSON movido, rechazo de otro proyecto y ausencia de sesión. Todo se revierte
  al acabar: no deja JSON movidos ni carpetas o versiones de prueba.
- `tests/calicatas/exports-routing.cjs`: fallo inicial por destino sin resolver,
  luego PASS. Verifica integración, recuperación y ejecuta el formateador
  real de rutas QML, incluyendo una carpeta personalizada.
- 22 suites JavaScript de Calicatas pasan.
- Se comprobó que anon no puede ejecutar la RPC; authenticated sí.

No se ejecutaron CMake, compilación, instalación, ADB o logcat. Fabián
compila. La prueba del dispositivo y la subida del nuevo XLSX quedan pendientes.
La copia en Descargas permanece activa y los archivos históricos se conservan.

Para probar: compilar, iniciar sesión, abrir la calicata en su proyecto y
exportar con internet. Revisar InGeDrive en la carpeta del JSON, dentro de
exports. Un resultado completo requiere objeto en `project-files` y reserva
`FINALIZADO`; una operación en cola no confirma la subida.

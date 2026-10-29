# Avatar privado sincronizado

Especificación: solicitud del usuario del 28/10/2026; Qt 6.9.3, InGePlus-Dev
`aalmeaqhhlhzwwzsbbxz`, sin commit/push ni cambios de Login/correo/permisos de perfiles.

Diseño: conservar AuthSession y el trigger Auth → profiles. JPEG de 1024 px,
calidad 85 y máximo 5 MiB; upsert en `<uid>/avatar.jpg`; referencia estable
`storage://avatars/<uid>/avatar.jpg` en Auth/profiles. Firma de 300 segundos
solo en memoria; descarga renovada al cargar el perfil; QML recibe file://.
Lectura: dueño, miembros activos de un proyecto activo común y roles globales
ADMINISTRADOR/ADMINISTRADOR_GENERAL/GERENCIA activos. Escritura solo carpeta propia.
Rutas heredadas siguen legibles y se limpian explícitamente al reemplazar/quitar.

- [x] Reproducir incumplimientos con pruebas host y SQL con ROLE authenticated.
- [x] Respaldar funciones/policies y crear migración versionada; aplicar solo Dev.
- [x] Corregir JPEG, metadata, descarga fresca, borrado y señales en AuthSession.
- [x] Compilar y ejecutar pruebas host; cubrir red fallida y respuestas de otra cuenta.
- [x] Ejecutar SQL transaccional con identidades reales y fixtures revertidos.
- [x] Revisar diff, advisors, documentar límites de SQL frente a HTTP/JWT real y reversión.

Evidencia: upload host RED (ruta/MIME), INSERT SQL RLS RED (ruta nueva),
migración 20261028125513 aplicada. Host/SQL GREEN. Revisión independiente
encontró carrera de respuesta personal; test RED y corrección GREEN, también
GET profiles iniciado durante clear. Informe: docs/PROFILE_AVATAR_SYNC_20261028.md.
Compatibilidad OAuth: alta con avatar_url externo RED; migración adicional
20261028131158 conserva proveedor externo sin copiarlo a profiles; alta y
actualización que preserva avatar privado GREEN. Regresión de cuenta GREEN.

Revisión: caché antigua con referencia estable, borrado remoto desde otro equipo,
A→B→A durante descargas, respuesta Auth incompleta, error parcial Storage/Auth.
Las credenciales reales no se extraen de sesiones ni se imprimen.

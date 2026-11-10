# Configuracion: almacenamiento de servidor y recuperacion

**Objetivo:** cumplir el contrato solicitado para InGePlus-Dev exclusivamente.
**Arquitectura:** conservar `inge_drive_storage_usage_v03(uuid) returns setof jsonb`;
medir `storage.objects` una vez por objeto, sin filtros de usuario o espacio.
La cuota sigue siendo la asignacion administrativa privada, no disco fisico ni
promedio facturado de la organizacion. Qt 6.9.3, C++, QML, PostgreSQL 17.
**Especificacion:** solicitud del usuario del 2026-10-27 en este chat.

## Restricciones
- Solo aalmeaqhhlhzwwzsbbxz, rama codex/fusionbridge-native.
- Trabajo secuencial en este checkout con los cambios existentes preservados.
- Sin build, instalacion o ejecucion Android; sin commit o push.
- Ningun secreto en logs ni service_role en Android.
- Cada cambio de servidor debe quedar en una migracion versionada.

## Revision y pruebas
- [x] Auditar definicion, cuota, plan, buckets, llamada C++ y consumidor QML.
- [x] Reproducir contrato incorrecto con rol authenticated de un LECTOR real.
- [x] Corregir solo v03 mediante migracion; probar null y UUID sin acceso.
- [x] Comprobar suma de categorias, totalidad de buckets, ACL y auth.uid.
- [ ] Revisar Auth en panel si hay sesion; registrar cualquier bloqueo.
- [x] Revisar /recover contra fuente oficial; corregir solo defectos confirmados.
- [x] Documentar JSON real, comandos, limites y riesgos; revisar diff final.

## Condiciones relevantes
- Un usuario sin espacios y un parametro obsoleto deben seguir viendo agregados.
- Versiones retenidas y objetos no enlazados siguen ocupando almacenamiento.
- Un objeto relacionado con dos dominios se cuenta una sola vez.
- Metadatos de tamano ausentes deben producir error, nunca cero silencioso.
- Cuota ausente debe producir error; cuota excedida debe dar total-used negativo.

## Registro
- Plan Free confirmado con get_organization; asignacion existente 1073741824 bytes.
- El conector Supabase no ofrece configuracion Auth; el panel solicita login.
- No se crean agentes ni worktrees porque el usuario exige ejecucion secuencial
  sobre la rama y los archivos de esta copia con cambios locales existentes.
- Migracion aplicada: 20261027204426_settings_project_storage_usage_v03.sql.
- Prueba SQL RED: FAIL_PROJECT_SCOPE; GREEN tras migracion y con casos de
  cuota ausente/excedida. No se almacenaron modificaciones de prueba.
- Auth: el usuario eligio iniciar sesion; pendiente acceso al panel. No hay
  eventos /recover en logs de Auth de las ultimas 24 horas consultadas.
- Revision final propia: alcance, ACL, suma sin duplicados, cuota configurada
  y compatibilidad de SETOF revisados; C++ solo inspeccion, sin build.
- Informe: docs/SETTINGS_SERVER_STORAGE_AUTH_20261027.md.

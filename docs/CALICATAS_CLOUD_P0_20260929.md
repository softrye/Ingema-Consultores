# Calicatas Cloud P0 — 2026-09-29

Estado: PARCIAL. Cambios implementados y backend comprobado; no se ha compilado
ni ejecutado Android. El origen exacto del aviso de timer negativo NO está demostrado.
No se afirma que el caso físico esté cerrado.

## Evidencia real

Supabase InGePlus-Dev, ref aalmeaqhhlhzwwzsbbxz. Proyecto
f4547c5d-5290-4de9-b999-8f1e260af012; calicata
cf3740fb-0a46-46dd-8273-0b85bc1e17e4; revisión persistente 1134,
updated_at 2026-09-29T19:35:48.908294Z. Tres estratos, dos muestras,
tres resultados de laboratorio. El primer estrato no tiene muestra.
Smart Document 67cd4907-e1f7-45a7-a8fd-e097e2ed4fa8: proyecto y destino correctos.
El docId local distinto del UUID cloud es válido.

La prueba transaccional realizó PATCH equivalente a Android, tres RPCs de estratos,
dos de muestras y tres de laboratorio. Revisión 1134 → 1143; lectura posterior
verificó el cambio. Un segundo PATCH con la revisión inicial fue rechazado.
Prueba pasada tanto con el creador como con la cuenta indicada por el usuario.
ROLLBACK dejó revisión 1134 y los datos originales. No se cambió RLS.

## Causas verificadas y límites

- Autosave tras hydrate: los estratos remotos no recibían local_stratum_id.
  _normalizeCorte lo asignaba y _assignedStratumIds llamaba _markDirty al importar.
  Además _syncFormIntoDoc exportaba defaults y derivados aunque no hubiese edición.
- Conflicto: autosave y Guardar podían ejecutar syncDocument sobre la misma revisión.
  La segunda escritura CAS queda obsoleta por la primera. La revisión se conservaba
  al completar toda la cadena o al fallar, no tras cada respuesta confirmada.
  El log aportado no identifica la RPC que produjo el conflicto del dispositivo:
  esa atribución concreta queda pendiente; no se elimina un CONFLICT existente sin
  demostrar que no contiene cambios locales divergentes.
- Android → Web: la ruta real acepta las escrituras y sus permisos son correctos.
  Se corrigieron la coordinación local y la conservación de revisiones/ediciones
  durante solicitudes. Una respuesta perdida después del commit aún puede requerir
  conciliación: no se sustituye una revisión obsoleta por la actual a ciegas.
- Undefined: QVariant inválido al leer sample_code/id de una muestra inexistente.
- Lentitud: cuatro peticiones encadenadas antes de aplicar datos y reconstrucción
  del formulario tanto por dataChanged como por remoteLoadSucceeded.
- Cuenta: la lista del servicio no se invalidaba por cuenta ni rechazaba respuestas
  antiguas. El proyecto inicial ya procede de AuthSession.assignedProjects, no de
  calicatas/activeProject. La cuenta indicada tiene cinco memberships ACTIVO.
- Timer: los timers de Calicatas son constantes positivas y el retry de presencia
  usa una tabla acotada. Se revisaron intervalos QML, Core, autosave, etapas y las
  llamadas nativas de timer. No hay evidencia suficiente para atribuir el aviso a
  un timer concreto. No se añadió un clamp ni se tocó Main/focus/GPS/MapLibre.

## Implementación

- CalicataDocument: aplicación cloud explícita sin dirty de usuario; snapshot
  completo admite cero estratos; conserva ediciones posteriores al inicio de sync;
  checkpoint local PENDING con cada revisión confirmada para recuperar procesos
  interrumpidos, sin dataChanged/reconstrucción por cada checkpoint.
- CalicataCloudService: una RPC de snapshot bajo RLS; ids locales de estrato
  estables, muestra ausente como texto vacío; captura inmutable de observaciones;
  cuenta/generación en callbacks, memberships actuales y descarte de listas viejas.
- QML: carga no activa autosave; formulario limpio no exporta defaults;
  una reconstrucción explícita al finalizar hydrate; Guardar espera al autosave.
- InGeDrive: binding privado por calicata, mismo contenido reutiliza versión,
  contenido nuevo versiona el mismo nodo. Un intento interrumpido conserva sus
  bytes y su registro local; se termina antes de enviar el contenido posterior.
  Se reprodujo STALE_VERSION al reintentar porque retry_document_upload_controlled
  no copiaba las revisiones binarias. La nueva RPC de Calicatas conserva esas bases
  y valida la identidad devuelta por el retry, sin alterar el RPC genérico.
- Actividad: lifecycle ya lo audita el servidor; exportaciones por RPC autorizada
  e idempotente. activity_logs continúa sin INSERT directo para authenticated.

## Migraciones aplicadas

- 20260929201308_calicata_atomic_snapshot.sql
- 20260929201351_calicatas_json_identity_and_android_export_activity.sql
- 20260929202505_calicata_json_retry_base_versions.sql
- 20260929202844_calicata_json_retry_idempotency_guard.sql

Las RPCs tienen search_path vacío, owner postgres, EXECUTE authenticated y no anon.
Snapshot usa SECURITY INVOKER; reserva/exportación SECURITY DEFINER con controles
de actor, proyecto, nodo y catálogo. RLS sigue activa. Tests dejaron cero bindings
nuevos persistentes. Los binarios históricos de exportaciones no se borraron.

## Validación y alcance

- SQL: cloud-roundtrip, drive-activity-idempotency, drive-version-reuse,
  drive-conflict-before (regresión final) y drive-retry, todos transaccionales.
- SQL negativo: identidad no miembro rechazada en snapshot, reserva y actividad.
- Node sin compilación: hydrate-model.cjs y drive-save-coordination.cjs.
- qmllint Qt 6.9.3: sin errores sintácticos; análisis incompleto por módulo InGe
  registrado en C++ y no disponible sin generar sus tipos. Existen advertencias
  de imports/propiedades/UI previas; no se declara lint limpio.
- EXPLAIN ANALYZE snapshot, rol authenticated: 46.095 ms en servidor.
  Peticiones de hydrate 4 → 1. Se eliminan tres viajes de red, no se promete
  un tiempo Android medido. INGE_CALICATA_TRACE habilita un log de red/apply.
- C++: revisión estática manual; sin compilador ni instalación ni ADB.
- Diff/status revisados. El árbol ya contenía más de 500 cambios previos.
  No se agregan esos cambios ajenos a commits de esta fase.

Fuentes intervenidas: calicatacloudservice.cpp/.h, calicatadocument.cpp/.h,
qml/Mobile/pages/CalicataFormPage.qml (solo modelo/coordinación),
qml/Mobile/pages/CalicatasEditorPage.qml (solo coordinación cloud).
No se alteraron visuales General/Ubicación/Perfil/Dock, GPS, Datum ni fixes de foco.

Pendiente en dispositivo: abrir la ficha real, confirmar Al día sin autosave,
editar y verificar Web, autosave+Guardar, doble Guardar, cierre/reapertura,
cambio de cuenta y obtener el emisor exacto del timer negativo. Un borrador ya
en CONFLICT se conserva; no se pisa automáticamente con datos de Web.

## Cierre (Claude, continuación)

- Hydrate: `applyCloudSync` valida los estratos ANTES de tocar la cabecera
  (sin estado a medias) y devuelve bool; `applyRemoteSnapshot` deja la ficha
  `dirty=false` tras aplicar y persistir el snapshot. Estado final: Al día.
- JSON InGeDrive: un intento reanudado en `EN_CARGA` sube y finaliza el MISMO
  intento sin un segundo `begin`; la copia local inmutable se elimina tras la
  confirmación del servidor.
- Cuenta: `refreshProjects` ignora en silencio las respuestas `ACCOUNT_CHANGED`
  (la lista vieja ya se descartaba por época en el transporte).
- Timer negativo: `QTimer` guarda el intervalo como int (ms). El Timer de la
  plataforma Qt de MapLibre convertía `Duration::max()` (modo offline) y
  expiraciones de caché de semanas/meses sin acotar: más de ~24,8 días
  desborda a negativo. Corregido en
  `thirdparty/maplibre-native-qt-src/vendor/maplibre-native/platform/qt/src/mbgl/timer.cpp`
  (satura a INT_MAX; plazo vencido = ahora). La app enlaza el paquete
  precompilado `thirdparty/maplibre-install`: el aviso desaparece al
  recompilar QMapLibre con esta fuente.
- Artefacto temporal `tests/calicatas/qmllint-p0.json` eliminado.
